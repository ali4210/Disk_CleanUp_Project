#!/usr/bin/env bash
# ==============================================================================
# MODULE:       docker-storage-migrate.sh  (sourced by vm-space-wizard.sh, V2.3)
# AUTHOR:       Saleem (Open Source DevOps/Sec Contributor)
# DESCRIPTION:  Safe Docker / containerd / Podman storage offload to a secondary
#               disk. Copies images, containers, volumes, networks and the
#               containerd image store BEFORE the new disk is mounted, verifies
#               the result, and rolls back on failure.
#               Original data on the root disk is NEVER deleted automatically;
#               it is removed only by the audit/cleanup menu after confirmation.
# FLAGS:        --dry-run   Print every state-changing step without running it.
#               --yes       Assume "yes" at every confirmation (non-interactive).
# ==============================================================================
# NOTE: this file is sourced, so it must not call `exit` at top level and it
# relies on show_header / pause / show_attachment_guidelines + color variables
# defined by vm-space-wizard.sh.

# A normal (non-login, or just minimally-configured) user's PATH often lacks
# the sbin directories — seen on ParrotOS — even though the tools this script
# depends on (mkfs.btrfs, btrfs, mkfs.xfs, xfs_info, blkid, ...) are installed
# there. Every `command -v` check below, and every direct invocation of one
# of these tools, must not depend on the invoking user's PATH containing
# them, so fix PATH once, here, before anything else runs.
for _vmw_sbin_dir in /usr/sbin /sbin /usr/local/sbin; do
    case ":$PATH:" in
        *":$_vmw_sbin_dir:"*) ;;
        *) PATH="$PATH:$_vmw_sbin_dir" ;;
    esac
done
unset _vmw_sbin_dir
export PATH

DRY_RUN=0
ASSUME_YES=0
for _vmw_arg in "$@"; do
    case "$_vmw_arg" in
        --dry-run) DRY_RUN=1 ;;
        --yes) ASSUME_YES=1 ;;
    esac
done
unset _vmw_arg

VMW_FSTAB="${VMW_FSTAB:-/etc/fstab}"
# Overridable so tests (and non-default Docker installs) never have to touch
# the real /var/lib/docker or /var/lib/containerd.
VMW_DOCKER_ROOT="${VMW_DOCKER_ROOT:-/var/lib/docker}"
VMW_CONTAINERD_ROOT="${VMW_CONTAINERD_ROOT:-/var/lib/containerd}"
VMW_MARKER=".vm-space-wizard-migrated"
if [[ $EUID -eq 0 ]]; then SUDO=""; else SUDO="sudo"; fi

# Where state/logs live. An explicit override always wins (this is how tests
# stay off the real system paths); otherwise prefer the system path when
# root/sudo can write it, falling back to the invoking user's cache dir.
# HOME is normally always set, but not guaranteed (minimal sudo/cron contexts),
# so fall back to /tmp rather than fail under `set -u`.
VMW_HOME="${HOME:-/tmp}"
if [[ -n "${VMW_STATE_DIR:-}${VMW_LOG_DIR:-}" ]]; then
    VMW_STATE_DIR="${VMW_STATE_DIR:-$VMW_HOME/.cache/vm-space-wizard/state}"
    VMW_LOG_DIR="${VMW_LOG_DIR:-$VMW_HOME/.cache/vm-space-wizard/log}"
    mkdir -p "$VMW_STATE_DIR" "$VMW_LOG_DIR" 2>/dev/null
elif $SUDO mkdir -p /var/lib/vm-space-wizard /var/log/vm-space-wizard 2>/dev/null; then
    VMW_STATE_DIR="/var/lib/vm-space-wizard"
    VMW_LOG_DIR="/var/log/vm-space-wizard"
else
    VMW_STATE_DIR="$VMW_HOME/.cache/vm-space-wizard/state"
    VMW_LOG_DIR="$VMW_HOME/.cache/vm-space-wizard/log"
    mkdir -p "$VMW_STATE_DIR" "$VMW_LOG_DIR" 2>/dev/null
fi
VMW_LOG_FILE="${VMW_LOG_FILE:-$VMW_LOG_DIR/migrate-$(date +%Y%m%d-%H%M%S).log}"
VMW_STATE_FILE="${VMW_STATE_FILE:-$VMW_STATE_DIR/migration.state}"
$SUDO mkdir -p "$(dirname "$VMW_LOG_FILE")" 2>/dev/null
# $VMW_LOG_DIR can be root-owned (created with $SUDO on an earlier run, by
# another user, or by the system-path branch above) even when this run is
# not root — same class of bug as the state file (Issue 2): a plain `>`
# redirect additionally fails silently in a way `2>/dev/null` does not catch
# (a failed redirection is reported on the shell's original stderr, before
# the command's own stderr redirection takes effect), so use a real command
# ($SUDO touch) whose own stderr IS properly suppressed instead.
if ! $SUDO touch "$VMW_LOG_FILE" 2>/dev/null; then VMW_LOG_FILE="/dev/null"; fi

ROOT_VIEW=""
STAGE_DIR=""
MIG_FSTAB_BACKUP=""
MIG_STAGE_MOUNTED=0
MIG_DOCKER_MOUNTED=0
MIG_BIND_MOUNTED=0
MIG_SERVICES_STOPPED=0
MIG_DROPIN_INSTALLED=0
SNAP_IMAGES=0; SNAP_CONTAINERS=0; SNAP_VOLUMES=0; SNAP_RUNNING=""
EXP_IMAGES=0;  EXP_CONTAINERS=0;  EXP_VOLUMES=0

# ------------------------------------------------------------------------------
# Small helpers
# ------------------------------------------------------------------------------
log_line() { printf '%s %s\n' "$(date -Is)" "$*" | $SUDO tee -a "$VMW_LOG_FILE" >/dev/null 2>/dev/null || true; }
info() { echo -e "${GREEN}--> $*${NC}"; log_line "INFO $*"; }
warn() { echo -e "${YELLOW}[!] $*${NC}"; log_line "WARN $*"; }
err()  { echo -e "${RED}[✘] $*${NC}"; log_line "ERR  $*"; }
ok()   { echo -e "${GREEN}[✔] $*${NC}"; log_line "OK   $*"; }

# Prompts for confirmation unless --yes was passed (then auto-confirms and logs it).
confirm() {
    local prompt="$1" reply
    if (( ASSUME_YES )); then
        info "(--yes) auto-confirming: $prompt"
        return 0
    fi
    read -r -p "$prompt " reply
    [[ "$reply" =~ ^[Yy]$ ]]
}

# Records/clears the step we are on, so an interrupted run can be recognized
# on the next launch instead of silently retrying from scratch.
mig_state_set() {
    (( DRY_RUN )) && return 0
    # $VMW_STATE_DIR (e.g. /var/lib/vm-space-wizard) is created with $SUDO at
    # source time, so it is root-owned; a plain `>` redirect here as a normal
    # user fails with "Permission denied" on every single call — silently,
    # because of the `|| true` — meaning crash recovery never actually
    # recorded anything. Must go through $SUDO, same as the directory create.
    # The UUID is recorded alongside the /dev name because that name can
    # (and did, on a real reboot) point at a different disk next boot — the
    # UUID is the only part of this record that still identifies the disk.
    local disk_uuid
    disk_uuid=$($SUDO blkid -s UUID -o value "$1" 2>/dev/null)
    printf 'disk=%s\nuuid=%s\nstage=%s\nstarted=%s\n' "$1" "${disk_uuid:-unknown}" "$2" "$(date -Is)" | $SUDO tee "$VMW_STATE_FILE" >/dev/null 2>/dev/null || true
}
mig_state_clear() { $SUDO rm -f "$VMW_STATE_FILE" 2>/dev/null || true; }
mig_state_check() {
    $SUDO test -f "$VMW_STATE_FILE" 2>/dev/null || return 0
    warn "A previous migration did not finish cleanly:"
    $SUDO sed 's/^/      /' "$VMW_STATE_FILE"
    warn "Your original data on the root disk was never deleted by an interrupted run, so it is safe to re-run this wizard."
    (( ASSUME_YES )) || read -r -p "Press [ENTER] to acknowledge and continue..." _ignored
}

# Runs a state-changing command, or only prints it in --dry-run mode.
run() {
    if (( DRY_RUN )); then
        echo -e "${CYAN}[dry-run]${NC} $*"
        return 0
    fi
    "$@"
}

human() { numfmt --to=iec --suffix=B "${1:-0}" 2>/dev/null || echo "${1:-0}B"; }

dir_bytes() {
    local b
    b=$($SUDO du -sb "$1" 2>/dev/null | cut -f1)
    echo "${b:-0}"
}

dir_has_entries() {
    $SUDO find "$1" -mindepth 1 -not -name 'lost+found' -print -quit 2>/dev/null | grep -q .
}

# True if a Docker data-root really holds user data (containers, volumes, overlay2
# layers), not just the empty skeleton Docker creates on first start.
docker_has_payload() {
    local d="$1"
    if $SUDO find "$d/containers" "$d/overlay2" -mindepth 1 -maxdepth 1 \
        -not -name l -not -name backingFsBlockDev -print -quit 2>/dev/null | grep -q .; then
        return 0
    fi
    if $SUDO find "$d/volumes" -mindepth 1 -maxdepth 1 \
        -not -name metadata.db -not -name backingFsBlockDev -print -quit 2>/dev/null | grep -q .; then
        return 0
    fi
    return 1
}

count_dirs() { $SUDO find "$1" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l; }
count_volume_entries() {
    $SUDO find "$1" -mindepth 1 -maxdepth 1 -not -name metadata.db -not -name backingFsBlockDev 2>/dev/null | wc -l
}

# ------------------------------------------------------------------------------
# Detection: storage driver, containerd snapshotter, filesystem types, custom
# data-root, snap/rootless Docker, init system. Run once at the start of a
# migration and printed before any plan is shown, so the chosen filesystem and
# copy method are visible before the target disk is touched at all.
# ------------------------------------------------------------------------------
DET_DRIVER=""; DET_SNAPSHOTTER=0; DET_ROOTLESS=0; DET_SNAP=0
DET_INIT="unknown"; DET_DATAROOT_FSTYPE=""; DET_DAEMON_JSON_DATAROOT=""

# Extracts a JSON string field; prefers jq, falls back to a best-effort
# grep/sed for the single simple "key": "value" shape daemon.json normally uses
# (so detection still mostly works on a minimal system without jq installed).
_vmw_json_field() {
    local json="$1" filter="$2" key="$3"
    if command -v jq &>/dev/null; then
        printf '%s' "$json" | jq -r "$filter" 2>/dev/null
    else
        printf '%s' "$json" | grep -o "\"$key\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" \
            | head -1 | sed -E 's/.*:[[:space:]]*"([^"]*)"/\1/'
    fi
}

# ------------------------------------------------------------------------------
# The btrfs/portable path's container/image JSON parsing uses jq throughout.
# On ParrotOS, `apt install jq` has no candidate at all — the tool must not
# simply refuse. _vmw_json runs the SAME named query either via jq (if
# present, unchanged behavior) or via a small python3 companion script that
# implements exactly these named lookups (not a general jq clone — the set
# of shapes this file ever asks for is small and fixed). Refuses only if
# NEITHER jq nor python3 is available, checked once up front by
# vmw_check_prereqs(), not discovered mid-migration after formatting.
# Keyed by $$ (the top-level shell's PID, unlike $BASHPID this stays the same
# across every subshell command/process substitution forks from it) so every
# `_vmw_json` call — each one its own subshell via $(...) or <(...), where a
# plain cache variable can't survive — resolves to the SAME path instead of
# mktemp'ing (and leaking) a fresh, never-cleaned-up file per call.
_vmw_json_helper_target() { printf '%s/.vmwiz-json-helper.%s.py' "${TMPDIR:-/tmp}" "$$"; }
_vmw_json_helper_path() {
    local target tmp
    target=$(_vmw_json_helper_target)
    [[ -f "$target" ]] && { echo "$target"; return 0; }
    tmp=$(mktemp "${target}.XXXXXX")
    cat > "$tmp" <<'VMWPYEOF'
import json, sys

def main():
    query = sys.argv[1]
    data = json.load(sys.stdin)
    # unwrap0/network_driver/network_subnet operate on the raw array-wrapped
    # ([...]) shape docker always returns for a single-object lookup — Config/
    # HostConfig only make sense once that is unwrapped, so compute them
    # lazily and only for a dict, or data.get() on a list blows up first.
    cfg = (data.get("Config") or {}) if isinstance(data, dict) else {}
    host = (data.get("HostConfig") or {}) if isinstance(data, dict) else {}

    def lines(items):
        for x in items:
            print(x)

    if query == "unwrap0":
        print(json.dumps(data[0] if isinstance(data, list) and data else {}, separators=(",", ":")))
    elif query == "name":
        n = data.get("Name", "") or ""
        print(n[1:] if n.startswith("/") else n)
    elif query == "image":
        print(cfg.get("Image") if cfg.get("Image") is not None else "null")
    elif query == "image_or_empty":
        print(cfg.get("Image") or "")
    elif query == "image_used":
        print(data.get("Image") or "")
    elif query == "state_running":
        print("true" if (data.get("State") or {}).get("Running") else "false")
    elif query == "workdir":
        print(cfg.get("WorkingDir") or "")
    elif query == "user":
        print(cfg.get("User") or "")
    elif query == "restart_name":
        print((host.get("RestartPolicy") or {}).get("Name") or "no")
    elif query == "restart_max":
        print((host.get("RestartPolicy") or {}).get("MaximumRetryCount") or 0)
    elif query == "privileged":
        print("true" if host.get("Privileged") else "false")
    elif query == "memory":
        print(host.get("Memory") or 0)
    elif query == "nanocpus":
        print(host.get("NanoCpus") or 0)
    elif query == "env":
        lines(cfg.get("Env") or [])
    elif query == "capadd":
        lines(host.get("CapAdd") or [])
    elif query == "capdrop":
        lines(host.get("CapDrop") or [])
    elif query == "entrypoint":
        lines(cfg.get("Entrypoint") or [])
    elif query == "cmd":
        lines(cfg.get("Cmd") or [])
    elif query == "networks_keys":
        nets = (data.get("NetworkSettings") or {}).get("Networks") or {}
        lines(sorted(nets.keys()))  # jq's `keys[]` sorts; match it exactly
    elif query == "portbindings":
        for cport, binds in (host.get("PortBindings") or {}).items():
            for b in (binds or []):
                hostip = b.get("HostIp") or "0.0.0.0"
                hostport = b.get("HostPort")
                print("%s:%s:%s" % (hostip, hostport, cport))
    elif query == "mounts":
        for m in (data.get("Mounts") or []):
            rw = m.get("RW", True)
            suffix = "" if rw else ":ro"
            if m.get("Type") == "volume":
                print("%s:%s%s" % (m.get("Name"), m.get("Destination"), suffix))
            elif m.get("Type") == "bind":
                print("%s:%s%s" % (m.get("Source"), m.get("Destination"), suffix))
    elif query == "labels":
        for k, v in (cfg.get("Labels") or {}).items():
            print("%s=%s" % (k, v))
    elif query == "devices":
        for d in (host.get("Devices") or []):
            print("%s:%s" % (d.get("PathOnHost"), d.get("PathInContainer")))
    elif query == "healthcheck_type":
        test = (cfg.get("Healthcheck") or {}).get("Test") or []
        print(test[0] if len(test) > 0 else "")
    elif query == "healthcheck_cmd":
        test = (cfg.get("Healthcheck") or {}).get("Test") or []
        print(test[1] if len(test) > 1 else "")
    elif query == "exotic":
        items = []
        if host.get("Dns"): items.append("dns")
        if host.get("ExtraHosts"): items.append("extra-hosts")
        if host.get("Sysctls"): items.append("sysctls")
        if host.get("Ulimits"): items.append("ulimits")
        if host.get("PidsLimit"): items.append("pids-limit")
        print(", ".join(items))
    elif query == "network_driver":
        obj = data[0] if isinstance(data, list) and data else {}
        print(obj.get("Driver") or "bridge")
    elif query == "network_subnet":
        obj = data[0] if isinstance(data, list) and data else {}
        cfgs = (obj.get("IPAM") or {}).get("Config") or []
        print((cfgs[0].get("Subnet") if cfgs else "") or "")
    else:
        sys.exit(1)

main()
VMWPYEOF
    mv -f "$tmp" "$target" 2>/dev/null || rm -f "$tmp"
    echo "$target"
}

# _vmw_json <query> <json>: runs one of the named lookups above against jq
# (unchanged, exact same filters as before) or, only if jq is missing, the
# python3 companion script implementing the same named lookup.
_vmw_json() {
    local query="$1" json="$2"
    if command -v jq &>/dev/null; then
        case "$query" in
            unwrap0)          jq -c '.[0]' <<<"$json" 2>/dev/null ;;
            name)             jq -r '.Name | ltrimstr("/")' <<<"$json" 2>/dev/null ;;
            image)            jq -r '.Config.Image' <<<"$json" 2>/dev/null ;;
            image_or_empty)   jq -r '.Config.Image // empty' <<<"$json" 2>/dev/null ;;
            image_used)       jq -r '.Image // empty' <<<"$json" 2>/dev/null ;;
            state_running)    jq -r '.State.Running' <<<"$json" 2>/dev/null ;;
            workdir)          jq -r '.Config.WorkingDir // ""' <<<"$json" 2>/dev/null ;;
            user)             jq -r '.Config.User // ""' <<<"$json" 2>/dev/null ;;
            restart_name)     jq -r '.HostConfig.RestartPolicy.Name // "no"' <<<"$json" 2>/dev/null ;;
            restart_max)      jq -r '.HostConfig.RestartPolicy.MaximumRetryCount // 0' <<<"$json" 2>/dev/null ;;
            privileged)       jq -r '.HostConfig.Privileged // false' <<<"$json" 2>/dev/null ;;
            memory)           jq -r '.HostConfig.Memory // 0' <<<"$json" 2>/dev/null ;;
            nanocpus)         jq -r '.HostConfig.NanoCpus // 0' <<<"$json" 2>/dev/null ;;
            env)              jq -r '.Config.Env // [] | .[]' <<<"$json" 2>/dev/null ;;
            capadd)           jq -r '.HostConfig.CapAdd // [] | .[]' <<<"$json" 2>/dev/null ;;
            capdrop)          jq -r '.HostConfig.CapDrop // [] | .[]' <<<"$json" 2>/dev/null ;;
            entrypoint)       jq -r '.Config.Entrypoint // [] | .[]' <<<"$json" 2>/dev/null ;;
            cmd)              jq -r '.Config.Cmd // [] | .[]' <<<"$json" 2>/dev/null ;;
            networks_keys)    jq -r '.NetworkSettings.Networks // {} | keys[]' <<<"$json" 2>/dev/null ;;
            portbindings)
                jq -r '
                    (.HostConfig.PortBindings // {}) | to_entries[] |
                    .key as $cport | (.value // [])[] |
                    "\(.HostIp // "0.0.0.0"):\(.HostPort)->\($cport)"
                ' <<<"$json" 2>/dev/null | sed -E 's#->([0-9]+)/(tcp|udp)$#:\1/\2#' ;;
            mounts)
                jq -r '
                    (.Mounts // [])[] |
                    if .Type == "volume" then "\(.Name):\(.Destination)" + (if .RW then "" else ":ro" end)
                    elif .Type == "bind" then "\(.Source):\(.Destination)" + (if .RW then "" else ":ro" end)
                    else empty end
                ' <<<"$json" 2>/dev/null ;;
            labels)           jq -r '.Config.Labels // {} | to_entries[] | "\(.key)=\(.value)"' <<<"$json" 2>/dev/null ;;
            devices)          jq -r '(.HostConfig.Devices // [])[] | "\(.PathOnHost):\(.PathInContainer)"' <<<"$json" 2>/dev/null ;;
            healthcheck_type) jq -r '.Config.Healthcheck.Test[0] // empty' <<<"$json" 2>/dev/null ;;
            healthcheck_cmd)  jq -r '.Config.Healthcheck.Test[1] // empty' <<<"$json" 2>/dev/null ;;
            exotic)
                jq -r '
                    [ (if (.HostConfig.Dns // []) != [] then "dns" else empty end),
                      (if (.HostConfig.ExtraHosts // []) != [] then "extra-hosts" else empty end),
                      (if (.HostConfig.Sysctls // {}) != {} then "sysctls" else empty end),
                      (if (.HostConfig.Ulimits // []) != [] then "ulimits" else empty end),
                      (if (.HostConfig.PidsLimit // 0) != 0 then "pids-limit" else empty end)
                    ] | join(", ")' <<<"$json" 2>/dev/null ;;
            network_driver)   jq -r '.[0].Driver // "bridge"' <<<"$json" 2>/dev/null ;;
            network_subnet)   jq -r '.[0].IPAM.Config[0].Subnet // empty' <<<"$json" 2>/dev/null ;;
            *) return 1 ;;
        esac
    elif command -v python3 &>/dev/null; then
        python3 -I "$(_vmw_json_helper_path)" "$query" <<<"$json" 2>/dev/null
    else
        return 1
    fi
}

# Checks every tool the migration needs, exactly once, BEFORE anything is
# formatted or copied — missing jq/rsync/findmnt/blkid used to only surface
# mid-migration (after the target disk was already formatted). jq is the
# one exception: its absence is not fatal here as long as python3 is
# available (see _vmw_json above); only truly missing BOTH refuses.
vmw_check_prereqs() {
    local driver="$1" missing=""
    command -v rsync &>/dev/null || missing="$missing rsync"
    command -v findmnt &>/dev/null || missing="$missing findmnt(util-linux)"
    command -v blkid &>/dev/null || missing="$missing blkid(util-linux)"
    if [[ "$driver" == "btrfs" ]]; then
        if ! command -v jq &>/dev/null && ! command -v python3 &>/dev/null; then
            missing="$missing jq-or-python3"
        fi
    fi
    if [[ -n "$missing" ]]; then
        err "Missing required tool(s) before starting: $missing"
        err "Install them first (e.g. sudo apt install rsync util-linux jq — or python3 if jq has no candidate on your distro) and re-run."
        return 1
    fi
    return 0
}

vmw_detect_setup() {
    DET_DRIVER=""; DET_SNAPSHOTTER=0; DET_ROOTLESS=0; DET_SNAP=0
    DET_INIT="unknown"; DET_DATAROOT_FSTYPE=""; DET_DAEMON_JSON_DATAROOT=""

    if command -v docker &>/dev/null && $SUDO docker info &>/dev/null; then
        DET_DRIVER=$($SUDO docker info -f '{{.Driver}}' 2>/dev/null)
        if $SUDO docker info -f '{{json .DriverStatus}}' 2>/dev/null | grep -qi 'containerd.snapshotter'; then
            DET_SNAPSHOTTER=1
        fi
        if $SUDO docker info -f '{{json .SecurityOptions}}' 2>/dev/null | grep -qi 'rootless'; then
            DET_ROOTLESS=1
        fi
    fi

    if command -v snap &>/dev/null && snap list docker &>/dev/null 2>&1; then
        DET_SNAP=1
    fi

    if command -v systemctl &>/dev/null; then
        DET_INIT="systemd"
    elif command -v rc-status &>/dev/null; then
        DET_INIT="openrc"
    elif [[ -f /sbin/init || -f /etc/inittab ]]; then
        DET_INIT="sysvinit-or-other"
    fi

    DET_DATAROOT_FSTYPE=$(findmnt -rn -M "$VMW_DOCKER_ROOT" -o FSTYPE 2>/dev/null | head -1)
    if [[ -z "$DET_DATAROOT_FSTYPE" ]]; then
        DET_DATAROOT_FSTYPE=$($SUDO stat -f -c %T "$VMW_DOCKER_ROOT" 2>/dev/null \
            || $SUDO stat -f -c %T "$(dirname "$VMW_DOCKER_ROOT")" 2>/dev/null || true)
    fi

    if $SUDO test -f /etc/docker/daemon.json 2>/dev/null; then
        local content
        content=$($SUDO cat /etc/docker/daemon.json 2>/dev/null)
        DET_DAEMON_JSON_DATAROOT=$(_vmw_json_field "$content" '.["data-root"] // empty' "data-root")
    fi
}

vmw_print_detected_setup() {
    echo -e "\n${CYAN}${BOLD}==================== DETECTED SETUP ====================${NC}"
    echo -e "  Storage driver      : ${BOLD}${DET_DRIVER:-unknown}${NC}$( (( DET_SNAPSHOTTER )) && echo ' (containerd snapshotter)' )"
    echo -e "  Rootless Docker     : $( (( DET_ROOTLESS )) && echo 'yes' || echo 'no' )"
    echo -e "  snap-installed      : $( (( DET_SNAP )) && echo 'yes' || echo 'no' )"
    echo -e "  Init system         : $DET_INIT"
    echo -e "  Data-root filesystem: ${DET_DATAROOT_FSTYPE:-unknown}"
    echo -e "${CYAN}${BOLD}==========================================================${NC}"
    if (( DET_ROOTLESS )); then
        warn "Rootless Docker detected. This wizard targets system-wide (rootful) Docker at"
        warn "$VMW_DOCKER_ROOT managed by systemd system units; rootless Docker's data lives under"
        warn "the user's home directory (.local/share/docker) and runs as a user service — not handled by this path."
    fi
    if (( DET_SNAP )); then
        warn "snap-installed Docker detected. Its data-root is typically under /var/snap/docker/,"
        warn "not $VMW_DOCKER_ROOT, and it's managed by snap.docker.* units, not docker.service."
        warn "This wizard does not auto-detect the snap data-root; it is not supported yet."
    fi
    if [[ -n "$DET_DAEMON_JSON_DATAROOT" && "$DET_DAEMON_JSON_DATAROOT" != "$VMW_DOCKER_ROOT" ]]; then
        warn "/etc/docker/daemon.json sets data-root to '$DET_DAEMON_JSON_DATAROOT', which differs from $VMW_DOCKER_ROOT."
        warn "Re-run with VMW_DOCKER_ROOT=$DET_DAEMON_JSON_DATAROOT (and matching VMW_CONTAINERD_ROOT) to target the right path."
    fi
}

# ------------------------------------------------------------------------------
# Filesystem choice: match the target filesystem to what the storage driver
# actually needs, and refuse up front — before anything is formatted or
# copied — when there is no safe way to proceed.
#   btrfs   -> target MUST be btrfs (the driver stores layers as subvolumes)
#   zfs     -> refuse: same subvolume/dataset problem as btrfs, no send/receive
#              support here; migrate it yourself with zfs send/receive
#   overlay2/overlayfs/vfs/aufs/fuse-overlayfs/unknown
#           -> plain files on any filesystem; ext4 is the default format
#              choice, an existing xfs filesystem is accepted only with
#              ftype=1 (overlay2 needs d_type support)
# ------------------------------------------------------------------------------
REQUIRED_FS=""   # "" = any ext4/xfs(ftype=1) is fine; "btrfs" = must be btrfs

vmw_choose_target_fs() {
    local driver="$1"
    REQUIRED_FS=""
    case "$driver" in
        btrfs)
            REQUIRED_FS="btrfs"
            if ! command -v mkfs.btrfs &>/dev/null || ! command -v btrfs &>/dev/null; then
                err "Docker's storage driver is 'btrfs', but btrfs-progs is not installed."
                err "Install it first, then re-run:"
                err "  Debian/Ubuntu/Kali: sudo apt install btrfs-progs"
                err "  Fedora/RHEL:        sudo dnf install btrfs-progs"
                err "  Arch:               sudo pacman -S btrfs-progs"
                err "  openSUSE:           sudo zypper install btrfsprogs"
                return 1
            fi
            ;;
        zfs)
            err "Docker's storage driver is 'zfs'. This wizard does not support zfs migration:"
            err "zfs stores layers as zpool datasets/snapshots, the same structural problem btrfs"
            err "has with subvolumes, but there is no send/receive support implemented here, and a"
            err "plain file copy would silently produce a broken layer store on the destination."
            err "Migrate it yourself with 'zfs send'/'zfs receive' between pools, or switch Docker"
            err "to the overlay2 driver first (which this wizard fully supports)."
            return 1
            ;;
        overlay2|overlayfs|vfs|aufs|fuse-overlayfs|"")
            REQUIRED_FS=""
            ;;
        *)
            warn "Unrecognized storage driver '$driver'; treating it like overlay2 (plain file copy, any ext4/xfs filesystem)."
            REQUIRED_FS=""
            ;;
    esac
    return 0
}

# Verifies a filesystem (existing, or about to be chosen for formatting)
# actually satisfies REQUIRED_FS and, for overlay2 on xfs, has ftype=1.
vmw_verify_target_fs() {
    local fs="$1" device="$2"
    if [[ -n "$REQUIRED_FS" && "$fs" != "$REQUIRED_FS" ]]; then
        err "$device is formatted as '$fs', but the '$DET_DRIVER' storage driver needs a $REQUIRED_FS filesystem."
        return 1
    fi
    if [[ -z "$REQUIRED_FS" && "$fs" == "xfs" ]]; then
        if command -v xfs_info &>/dev/null; then
            if ! $SUDO xfs_info "$device" 2>/dev/null | grep -q 'ftype=1'; then
                err "$device is xfs with ftype=0. The overlay2/overlayfs driver requires ftype=1 (d_type support)."
                err "Reformat with: mkfs.xfs -n ftype=1 -f $device"
                return 1
            fi
        else
            warn "xfsprogs is not installed; could not verify $device has ftype=1 (required by overlay2)."
            warn "An xfs filesystem formatted long ago may default to ftype=0, which overlay2 cannot use."
        fi
    fi
    return 0
}

# ------------------------------------------------------------------------------
# Root-disk "view": a bind mount of / that shows what is physically stored on the
# root filesystem, even when another disk is mounted over /var/lib/docker.
# ------------------------------------------------------------------------------
mount_root_view() {
    if [[ -n "$ROOT_VIEW" ]]; then return 0; fi
    ROOT_VIEW=$($SUDO mktemp -d /mnt/.vmwiz-rootview.XXXXXX) || { ROOT_VIEW=""; return 1; }
    if ! $SUDO mount --bind "${VMW_ROOT_SOURCE:-/}" "$ROOT_VIEW"; then
        $SUDO rmdir "$ROOT_VIEW" 2>/dev/null
        ROOT_VIEW=""
        return 1
    fi
}

# Unmounts $1, trying a lazy unmount (-l, detaches from the namespace even
# while something still holds it busy) if a normal unmount is refused.
# Real-world failure this guards against: a leftover /mnt/.vmwiz-rootview.*
# or staging mount after a SUCCESSFUL migration, because a plain `umount`
# can transiently fail "busy" and the caller must not just give up.
_vmw_force_umount() {
    $SUDO umount "$1" 2>/dev/null && return 0
    $SUDO umount -l "$1" 2>/dev/null
}

umount_root_view() {
    if [[ -z "$ROOT_VIEW" ]]; then return 0; fi
    local rv nested
    rv="$ROOT_VIEW"
    # Unmount anything nested under the view first, deepest path first — a
    # plain (non-recursive) bind mount of / should never acquire nested
    # mounts during a run, but failing to check costs nothing and a stuck
    # mount here is exactly the bug being fixed.
    while nested=$($SUDO findmnt -rn -o TARGET 2>/dev/null | grep -F "$rv/" | sort -r | head -1) && [[ -n "$nested" ]]; do
        _vmw_force_umount "$nested" || break
    done
    if _vmw_force_umount "$rv"; then
        $SUDO rmdir "$rv" 2>/dev/null
        ROOT_VIEW=""
    else
        warn "Could not unmount the temporary root-disk view at $rv — leaving it tracked so the next cleanup attempt (including this run's own exit trap) retries instead of silently forgetting it."
    fi
}

mig_release_stage() {
    if [[ -z "$STAGE_DIR" ]]; then return 0; fi
    if (( MIG_STAGE_MOUNTED )); then
        if _vmw_force_umount "$STAGE_DIR"; then
            MIG_STAGE_MOUNTED=0
        else
            # Every call site in this file is a bare statement (several run
            # under the caller's `set -e` once sourced), so this must never
            # return non-zero — just warn and leave STAGE_DIR tracked so the
            # next cleanup attempt (including this run's own exit trap)
            # retries instead of silently forgetting it.
            warn "Could not unmount the staging mount at $STAGE_DIR — leaving it tracked to retry on the next cleanup attempt."
            return 0
        fi
    fi
    $SUDO rmdir "$STAGE_DIR" 2>/dev/null
    STAGE_DIR=""
    return 0
}

_vmw_exit_cleanup() {
    umount_root_view
    mig_release_stage
    rm -f "$(_vmw_json_helper_target)" 2>/dev/null
    return 0
}
trap _vmw_exit_cleanup EXIT

# ------------------------------------------------------------------------------
# State snapshot (used to prove that nothing was lost)
# ------------------------------------------------------------------------------
snapshot_docker_state() {
    SNAP_IMAGES=0; SNAP_CONTAINERS=0; SNAP_VOLUMES=0; SNAP_RUNNING=""
    command -v docker &>/dev/null || return 0
    $SUDO docker info &>/dev/null || return 0
    SNAP_IMAGES=$($SUDO docker image ls -q 2>/dev/null | sort -u | wc -l)
    SNAP_CONTAINERS=$($SUDO docker ps -aq 2>/dev/null | wc -l)
    SNAP_VOLUMES=$($SUDO docker volume ls -q 2>/dev/null | wc -l)
    SNAP_RUNNING=$($SUDO docker ps -q --no-trunc 2>/dev/null | tr '\n' ' ')
}

# ------------------------------------------------------------------------------
# fstab handling (backup -> append only missing lines -> validate -> restore)
# ------------------------------------------------------------------------------
fstab_has_mount() {
    awk -v mp="$1" '$0 !~ /^[[:space:]]*#/ && $2 == mp { f = 1 } END { exit !f }' "$VMW_FSTAB"
}

fstab_error_score() {
    local out e p
    out=$($SUDO findmnt --verify --tab-file "$VMW_FSTAB" 2>&1 || true)
    e=$(grep -c '\[E\]' <<<"$out" || true)
    p=$(grep -Eo '[0-9]+ parse errors' <<<"$out" | grep -Eo '^[0-9]+' | head -1 || true)
    echo $(( ${e:-0} + ${p:-0} ))
}

fstab_append() {
    local line="$1"
    if (( DRY_RUN )); then
        echo -e "${CYAN}[dry-run]${NC} append to $VMW_FSTAB: $line"
        return 0
    fi
    # Guard against a missing trailing newline gluing two entries together.
    if [[ -s "$VMW_FSTAB" && -n "$(tail -c1 "$VMW_FSTAB")" ]]; then
        echo | $SUDO tee -a "$VMW_FSTAB" >/dev/null
    fi
    printf '%s\n' "$line" | $SUDO tee -a "$VMW_FSTAB" >/dev/null
}

mig_update_fstab() {
    local uuid="$1" fs="$2" before after added=0
    MIG_FSTAB_BACKUP="${VMW_FSTAB}.vmwizard.bak.$(date +%Y%m%d-%H%M%S)"
    before=$(fstab_error_score)
    run $SUDO cp -a "$VMW_FSTAB" "$MIG_FSTAB_BACKUP" || return 1

    if ! fstab_has_mount "$VMW_DOCKER_ROOT"; then
        # nofail: a detached/renamed secondary disk must never block boot or
        # drop the machine into an emergency shell waiting for this mount.
        fstab_append "UUID=$uuid  $VMW_DOCKER_ROOT  $fs  defaults,nofail,x-systemd.device-timeout=10  0  2" || return 1
        added=1
    else
        info "fstab already has an entry for $VMW_DOCKER_ROOT; leaving it unchanged."
    fi

    if ! fstab_has_mount "$VMW_CONTAINERD_ROOT"; then
        fstab_append "$VMW_DOCKER_ROOT/containerd-data  $VMW_CONTAINERD_ROOT  none  bind,nofail,x-systemd.requires-mounts-for=$VMW_DOCKER_ROOT  0  0" || return 1
        added=1
    else
        info "fstab already has an entry for $VMW_CONTAINERD_ROOT; leaving it unchanged."
    fi

    if (( added == 0 )); then
        run $SUDO rm -f "$MIG_FSTAB_BACKUP"
        MIG_FSTAB_BACKUP=""
        return 0
    fi

    run $SUDO systemctl daemon-reload
    if (( ! DRY_RUN )); then
        after=$(fstab_error_score)
        if (( after > before )); then
            err "fstab validation reported new errors; restoring the backup."
            $SUDO cp -a "$MIG_FSTAB_BACKUP" "$VMW_FSTAB"
            $SUDO systemctl daemon-reload
            MIG_FSTAB_BACKUP=""
            return 1
        fi
    fi
    ok "fstab updated (backup: $MIG_FSTAB_BACKUP)"
}

# ------------------------------------------------------------------------------
# systemd drop-in: makes docker.service wait for the new disk to actually be
# mounted, instead of relying on implicit target ordering. On non-systemd
# hosts this is skipped with a clear warning; fstab + nofail is still safe there.
# ------------------------------------------------------------------------------
VMW_DROPIN_DIR="${VMW_DROPIN_DIR:-/etc/systemd/system/docker.service.d}"
VMW_DROPIN_FILE="99-vm-space-wizard-storage.conf"

mig_install_systemd_dropin() {
    if ! command -v systemctl &>/dev/null; then
        warn "systemd not detected; skipping the docker.service mount-ordering drop-in."
        warn "On this init system, double-check manually that Docker starts after $VMW_DOCKER_ROOT is mounted."
        return 0
    fi
    if (( DRY_RUN )); then
        echo -e "${CYAN}[dry-run]${NC} write $VMW_DROPIN_DIR/$VMW_DROPIN_FILE (RequiresMountsFor=$VMW_DOCKER_ROOT $VMW_CONTAINERD_ROOT)"
        return 0
    fi
    run $SUDO mkdir -p "$VMW_DROPIN_DIR" || return 1
    printf '[Unit]\nRequiresMountsFor=%s %s\n' "$VMW_DOCKER_ROOT" "$VMW_CONTAINERD_ROOT" | $SUDO tee "$VMW_DROPIN_DIR/$VMW_DROPIN_FILE" >/dev/null
    run $SUDO systemctl daemon-reload || return 1
    MIG_DROPIN_INSTALLED=1
    ok "docker.service now explicitly waits for $VMW_DOCKER_ROOT and $VMW_CONTAINERD_ROOT to be mounted."
}

mig_remove_systemd_dropin() {
    (( MIG_DROPIN_INSTALLED )) || return 0
    $SUDO rm -f "$VMW_DROPIN_DIR/$VMW_DROPIN_FILE" 2>/dev/null
    $SUDO systemctl daemon-reload 2>/dev/null
    MIG_DROPIN_INSTALLED=0
}

# ------------------------------------------------------------------------------
# Rollback: the root-disk data is never modified, so undoing = unmount + restore
# ------------------------------------------------------------------------------
mig_rollback() {
    if (( DRY_RUN )); then
        warn "[dry-run] a failure at this step would trigger an automatic rollback."
        umount_root_view
        mig_release_stage
        return 0
    fi
    warn "Rolling back. Your original data on the root disk was not modified."
    $SUDO systemctl stop docker.socket docker.service containerd.service 2>/dev/null
    if (( MIG_BIND_MOUNTED )); then
        $SUDO umount "$VMW_CONTAINERD_ROOT" 2>/dev/null
        MIG_BIND_MOUNTED=0
    fi
    if (( MIG_DOCKER_MOUNTED )); then
        $SUDO umount "$VMW_DOCKER_ROOT" 2>/dev/null
        MIG_DOCKER_MOUNTED=0
    fi
    if [[ -n "$MIG_FSTAB_BACKUP" && -f "$MIG_FSTAB_BACKUP" ]]; then
        $SUDO cp -a "$MIG_FSTAB_BACKUP" "$VMW_FSTAB"
        $SUDO systemctl daemon-reload
    fi
    mig_remove_systemd_dropin
    mig_release_stage
    umount_root_view
    if (( MIG_SERVICES_STOPPED )); then
        $SUDO systemctl start containerd.service docker.service 2>/dev/null
        MIG_SERVICES_STOPPED=0
    fi
    mig_state_clear
    return 0
}

mig_abort() {
    err "$1"
    mig_rollback
    return 1
}

# ------------------------------------------------------------------------------
# Post-migration verification
# ------------------------------------------------------------------------------
mig_verify() {
    local disk="$1" rootdir src src_uuid disk_uuid n img cid fail=0

    rootdir=$($SUDO docker info -f '{{.DockerRootDir}}' 2>/dev/null)
    if [[ "$rootdir" == "$VMW_DOCKER_ROOT" ]]; then
        ok "Docker root dir is $VMW_DOCKER_ROOT"
    else
        err "Docker root dir is '$rootdir' (expected $VMW_DOCKER_ROOT)"; fail=1
    fi

    # Compared by UUID, not by /dev name — $disk is only guaranteed to name
    # the right disk for the duration of THIS run; the whole point of
    # verifying by UUID is that it stays correct even if this disk's /dev
    # name has already changed by the time verify runs (or will, by the
    # next reboot).
    disk_uuid=$($SUDO blkid -s UUID -o value "$disk" 2>/dev/null)
    src=$(findmnt -rn -M "$VMW_DOCKER_ROOT" -o SOURCE 2>/dev/null | head -1)
    src_uuid=$([[ -n "$src" ]] && $SUDO blkid -s UUID -o value "${src%%\[*}" 2>/dev/null)
    if [[ -n "$src_uuid" && -n "$disk_uuid" && "$src_uuid" == "$disk_uuid" ]]; then
        ok "$VMW_DOCKER_ROOT is served by $disk"
    else
        err "$VMW_DOCKER_ROOT is NOT mounted from $disk"; fail=1
    fi

    if findmnt -rn -M "$VMW_CONTAINERD_ROOT" &>/dev/null; then
        ok "$VMW_CONTAINERD_ROOT is bind-mounted from the new disk"
    else
        err "$VMW_CONTAINERD_ROOT is not a mount point"; fail=1
    fi

    n=$($SUDO docker image ls -q 2>/dev/null | sort -u | wc -l)
    if (( n >= EXP_IMAGES )); then ok "Images:     $n (expected at least $EXP_IMAGES)"
    else err "Images:     $n (expected at least $EXP_IMAGES)"; fail=1; fi

    n=$($SUDO docker ps -aq 2>/dev/null | wc -l)
    if (( n >= EXP_CONTAINERS )); then ok "Containers: $n (expected at least $EXP_CONTAINERS)"
    else err "Containers: $n (expected at least $EXP_CONTAINERS)"; fail=1; fi

    n=$($SUDO docker volume ls -q 2>/dev/null | wc -l)
    if (( n >= EXP_VOLUMES )); then ok "Volumes:    $n (expected at least $EXP_VOLUMES)"
    else err "Volumes:    $n (expected at least $EXP_VOLUMES)"; fail=1; fi

    # Write test: create (and remove) a container from a local image. This forces
    # Docker to allocate a writable layer on the new disk without needing a pull.
    img=$($SUDO docker image ls --format '{{.Repository}}:{{.Tag}}' 2>/dev/null | grep -v '<none>' | head -1)
    if [[ -n "$img" ]]; then
        cid=$($SUDO docker create --pull=never --entrypoint true "$img" 2>/dev/null)
        if [[ -n "$cid" ]] && $SUDO docker rm "$cid" &>/dev/null; then
            ok "Write test passed (created and removed a container from $img)"
        else
            err "Write test failed for image $img"; fail=1
        fi
    fi
    return $fail
}

# Lists containers that keep data in host folders. Those folders are NOT part of
# Docker's storage, so they stay on whatever disk they live on.
report_host_bind_mounts() {
    command -v docker &>/dev/null || return 0
    $SUDO docker info &>/dev/null || return 0
    local out
    out=$($SUDO docker ps -aq 2>/dev/null | xargs -r $SUDO docker inspect \
        --format '{{.Name}}{{range .Mounts}}{{if eq .Type "bind"}}  {{.Source}}{{end}}{{end}}' 2>/dev/null | awk 'NF>1')
    if [[ -n "$out" ]]; then
        echo -e "\n${YELLOW}Containers using host folders (bind mounts). These stay where they are:${NC}"
        echo "   ${out//$'\n'/$'\n'   }"
        echo -e "${CYAN}   (Move them later with: stop container, rsync -aHAX, update the compose/run path.)${NC}"
    fi
}

# ------------------------------------------------------------------------------
# The migration itself
# ------------------------------------------------------------------------------
migrate_docker_storage() {
    local disk="$1" fs uuid dsrc dsrc_uuid dest="" legacy=0 cd_mounted=0
    local copy_docker=0 copy_cd=0 marker=0 src_docker src_cd
    local src_has=0 dst_has=0 src_cd_has=0 dst_cd_has=0
    local need=0 avail=0 rc c v b id confirm

    MIG_FSTAB_BACKUP=""; MIG_STAGE_MOUNTED=0; MIG_DOCKER_MOUNTED=0
    MIG_BIND_MOUNTED=0; MIG_SERVICES_STOPPED=0

    # Safety net for direct callers (including this module's own tests): this
    # is the plain-rsync path, which is only correct for drivers that store
    # layers as ordinary files/directories. _vmw_setup_secondary_disk already
    # routes btrfs elsewhere and refuses zfs before calling anything, but a
    # script calling migrate_docker_storage() directly must get the same
    # protection instead of silently corrupting a btrfs layer store.
    vmw_detect_setup
    if [[ "$DET_DRIVER" == "btrfs" ]]; then
        err "Docker's storage driver is 'btrfs'; migrate_docker_storage() (plain rsync) cannot be used safely here."
        err "Use migrate_docker_storage_btrfs() instead (the menu does this automatically)."
        return 1
    fi
    vmw_choose_target_fs "$DET_DRIVER" || return 1

    fs=$($SUDO blkid -s TYPE -o value "$disk" 2>/dev/null)
    uuid=$($SUDO blkid -s UUID -o value "$disk" 2>/dev/null)
    if [[ -z "$fs" || -z "$uuid" ]]; then
        err "Could not read the filesystem type / UUID of $disk."
        return 1
    fi
    if ! vmw_verify_target_fs "$fs" "$disk"; then
        return 1
    fi
    # Recorded in the log (not just on screen) because $disk is a /dev name,
    # which can point at a different physical disk after a reboot — the
    # UUID is what still identifies this disk when someone reads the log later.
    info "Target disk for this migration: $disk (UUID $uuid)"

    info "Pre-flight checks..."
    if ! command -v rsync &>/dev/null; then
        err "rsync is required. Install it first (e.g. sudo apt install rsync) and re-run."
        return 1
    fi
    if ! command -v findmnt &>/dev/null; then
        err "findmnt (util-linux) is required."
        return 1
    fi

    # Is the target already mounted over $VMW_DOCKER_ROOT (old wizard behaviour)?
    # Compared by UUID, not by /dev name — a /dev path can point at a
    # different physical disk after a reboot renumbers it, so comparing
    # names risks either a false "different device" refusal or (worse) a
    # false match against whatever disk now happens to hold that name.
    dsrc=$(findmnt -rn -M "$VMW_DOCKER_ROOT" -o SOURCE 2>/dev/null | head -1)
    if [[ -n "$dsrc" ]]; then
        dsrc_uuid=$($SUDO blkid -s UUID -o value "${dsrc%%\[*}" 2>/dev/null)
        if [[ -n "$dsrc_uuid" && "$dsrc_uuid" == "$uuid" ]]; then
            legacy=1
        else
            err "$VMW_DOCKER_ROOT is already a mount point for a different device ($dsrc)."
            return 1
        fi
    elif [[ -n "$($SUDO lsblk -no MOUNTPOINTS "$disk" 2>/dev/null | tr -d '[:space:]')" ]]; then
        err "$disk is mounted somewhere else. Unmount it first, then re-run."
        return 1
    fi

    # Read-only view of what is physically stored on the ROOT disk.
    if ! mount_root_view; then
        err "Could not create the root-disk view (bind mount of ${VMW_ROOT_SOURCE:-/})."
        return 1
    fi
    src_docker="$ROOT_VIEW$VMW_DOCKER_ROOT"
    src_cd="$ROOT_VIEW$VMW_CONTAINERD_ROOT"

    if (( legacy )); then
        dest="$VMW_DOCKER_ROOT"
        info "$disk is already mounted on $VMW_DOCKER_ROOT; checking for data hidden underneath it."
    else
        STAGE_DIR=$($SUDO mktemp -d /mnt/.vmwiz-stage.XXXXXX) || { umount_root_view; return 1; }
        info "Mounting $disk at a temporary staging path..."
        run $SUDO mount "$disk" "$STAGE_DIR" || { mig_abort "Could not mount $disk."; return 1; }
        MIG_STAGE_MOUNTED=1
        dest="$STAGE_DIR"
    fi

    if findmnt -rn -M "$VMW_CONTAINERD_ROOT" &>/dev/null; then cd_mounted=1; fi
    if $SUDO test -e "$dest/$VMW_MARKER"; then marker=1; fi
    if docker_has_payload "$src_docker"; then src_has=1; fi
    if docker_has_payload "$dest"; then dst_has=1; fi
    if dir_has_entries "$src_cd"; then src_cd_has=1; fi
    if dir_has_entries "$dest/containerd-data"; then dst_cd_has=1; fi

    if (( marker )); then
        info "This disk was already migrated by the wizard; skipping data copy."
    else
        if (( src_has && dst_has )); then
            mig_abort "Docker data exists on BOTH the root disk and $disk. Merging two live Docker states is unsafe. Resolve manually (keep one side), then re-run."
            return 1
        fi
        if (( src_has )); then copy_docker=1; fi
        if (( ! cd_mounted && src_cd_has )); then
            if (( dst_cd_has )); then
                mig_abort "containerd data exists on BOTH the root disk and $disk. Resolve manually, then re-run."
                return 1
            fi
            copy_cd=1
        fi
    fi

    # Fast path: nothing to copy and everything already mounted. No downtime.
    if (( legacy && cd_mounted && ! copy_docker && ! copy_cd )); then
        ok "Docker and containerd already live on $disk and no data is waiting on the root disk."
        mig_update_fstab "$uuid" "$fs" || { mig_abort "fstab update failed."; return 1; }
        mig_install_systemd_dropin || { mig_abort "systemd drop-in install failed."; return 1; }
        if (( ! DRY_RUN )); then
            snapshot_docker_state
            EXP_IMAGES=$SNAP_IMAGES; EXP_CONTAINERS=$SNAP_CONTAINERS; EXP_VOLUMES=$SNAP_VOLUMES
            if mig_verify "$disk"; then
                echo "migrated $(date -Is) (verified in place) by vm-space-wizard V2.3" | $SUDO tee "$VMW_DOCKER_ROOT/$VMW_MARKER" >/dev/null
            else
                warn "Verification reported problems. Nothing was changed."
            fi
        fi
        report_host_bind_mounts
        umount_root_view
        return 0
    fi

    # Space check
    if (( copy_docker )); then b=$(dir_bytes "$src_docker"); need=$(( need + ${b:-0} )); fi
    if (( copy_cd ));     then b=$(dir_bytes "$src_cd");     need=$(( need + ${b:-0} )); fi
    if (( ! DRY_RUN )); then
        avail=$($SUDO df --output=avail -B1 "$dest" 2>/dev/null | tail -1 | tr -d ' ')
        if (( need + need / 10 > ${avail:-0} )); then
            mig_abort "Not enough free space on $disk: need ~$(human $(( need + need / 10 ))), available $(human "${avail:-0}")."
            return 1
        fi
    fi

    snapshot_docker_state
    EXP_IMAGES=$SNAP_IMAGES; EXP_CONTAINERS=$SNAP_CONTAINERS; EXP_VOLUMES=$SNAP_VOLUMES
    if (( copy_docker )); then
        c=$(count_dirs "$src_docker/containers");        if (( c > EXP_CONTAINERS )); then EXP_CONTAINERS=$c; fi
        v=$(count_volume_entries "$src_docker/volumes"); if (( v > EXP_VOLUMES ));    then EXP_VOLUMES=$v; fi
    fi

    echo -e "\n${CYAN}${BOLD}==================== MIGRATION PLAN ====================${NC}"
    echo -e "  Target disk        : ${BOLD}$disk${NC} ($fs, UUID $uuid)"
    echo -e "  Mode               : $( (( legacy )) && echo 'disk already mounted; recovering data hidden under it' || echo 'fresh mount; copy first, then mount' )"
    echo -e "  Docker data        : $( (( copy_docker )) && echo "copy ($(human "$(dir_bytes "$src_docker")"))" || echo 'nothing to copy' )"
    echo -e "  containerd (images): $( (( copy_cd )) && echo "copy ($(human "$(dir_bytes "$src_cd")"))" || echo 'nothing to copy' ), bind-mounted at $VMW_CONTAINERD_ROOT"
    echo -e "  Before             : images=$SNAP_IMAGES containers=$SNAP_CONTAINERS volumes=$SNAP_VOLUMES (expected after: images>=$EXP_IMAGES containers>=$EXP_CONTAINERS volumes>=$EXP_VOLUMES)"
    echo -e "  Original data      : ${GREEN}kept on the root disk${NC} (remove later via 'Audit & Clean Up Leftover Storage After a Migration')"
    echo -e "  ${YELLOW}Downtime           : Docker and all containers stop during the copy${NC}"
    echo -e "${CYAN}${BOLD}========================================================${NC}"
    if (( ! DRY_RUN )); then
        if ! confirm "Proceed with the migration? (y/N):"; then
            info "Cancelled. Nothing was changed."
            mig_release_stage; umount_root_view
            return 1
        fi
    fi

    mig_state_set "$disk" "stopping-services"
    info "Stopping Docker, containerd and Podman..."
    run $SUDO systemctl stop docker.socket docker.service containerd.service 2>/dev/null
    if command -v podman &>/dev/null; then
        systemctl --user stop podman.socket podman.service 2>/dev/null || true
        $SUDO systemctl stop podman.socket podman.service 2>/dev/null || true
    fi
    MIG_SERVICES_STOPPED=1
    if (( ! DRY_RUN )) && $SUDO systemctl is-active --quiet docker.service; then
        mig_abort "Docker would not stop."; return 1
    fi

    mig_state_set "$disk" "copying-data"
    if (( copy_docker )); then
        info "Copying Docker data (containers, volumes, networks, settings)..."
        run $SUDO rsync -aHAXS --numeric-ids --info=progress2 "$src_docker/" "$dest/"
        rc=$?
        if (( rc != 0 && rc != 24 )); then mig_abort "rsync of Docker data failed (exit $rc)."; return 1; fi
    fi
    if (( copy_cd )); then
        info "Copying containerd image store..."
        run $SUDO rsync -aHAXS --numeric-ids --info=progress2 "$src_cd/" "$dest/containerd-data/"
        rc=$?
        if (( rc != 0 && rc != 24 )); then mig_abort "rsync of containerd data failed (exit $rc)."; return 1; fi
    fi

    if (( ! legacy )); then
        info "Mounting $disk on $VMW_DOCKER_ROOT..."
        run $SUDO umount "$STAGE_DIR" || { mig_abort "Could not release the staging mount."; return 1; }
        MIG_STAGE_MOUNTED=0
        $SUDO rmdir "$STAGE_DIR" 2>/dev/null
        STAGE_DIR=""
        run $SUDO mkdir -p "$VMW_DOCKER_ROOT"
        run $SUDO mount "$disk" "$VMW_DOCKER_ROOT" || { mig_abort "Could not mount $disk on $VMW_DOCKER_ROOT."; return 1; }
        MIG_DOCKER_MOUNTED=1
        run $SUDO chmod 711 "$VMW_DOCKER_ROOT"
    fi

    run $SUDO mkdir -p -m 711 "$VMW_DOCKER_ROOT/containerd-data"
    if (( ! cd_mounted )); then
        info "Bind-mounting containerd data from the new disk..."
        run $SUDO mkdir -p "$VMW_CONTAINERD_ROOT"
        run $SUDO mount --bind "$VMW_DOCKER_ROOT/containerd-data" "$VMW_CONTAINERD_ROOT" \
            || { mig_abort "Could not bind-mount containerd data."; return 1; }
        MIG_BIND_MOUNTED=1
    fi

    mig_state_set "$disk" "updating-fstab"
    info "Updating $VMW_FSTAB (persistent mounts)..."
    mig_update_fstab "$uuid" "$fs" || { mig_abort "fstab update failed."; return 1; }
    mig_install_systemd_dropin || { mig_abort "systemd drop-in install failed."; return 1; }

    mig_state_set "$disk" "starting-services"
    info "Starting containerd and Docker..."
    if $SUDO systemctl cat containerd.service &>/dev/null; then
        run $SUDO systemctl start containerd.service || { mig_abort "containerd failed to start."; return 1; }
    fi
    if command -v docker &>/dev/null; then
        run $SUDO systemctl start docker.service || { mig_abort "Docker failed to start."; return 1; }
        MIG_SERVICES_STOPPED=0

        if (( ! DRY_RUN )); then
            rc=1
            for _ in $(seq 1 60); do
                if $SUDO docker info &>/dev/null; then rc=0; break; fi
                sleep 1
            done
            if (( rc != 0 )); then mig_abort "Docker did not become ready within 60 seconds."; return 1; fi

            # Containers with a restart policy come back by themselves; start the rest.
            sleep 5
            for id in $SNAP_RUNNING; do
                if ! $SUDO docker inspect -f '{{.State.Running}}' "$id" 2>/dev/null | grep -q true; then
                    $SUDO docker start "$id" &>/dev/null
                fi
            done

            info "Verifying the result..."
            if ! mig_verify "$disk"; then
                mig_abort "Verification failed."
                warn "Everything was reverted to the root-disk state. Copied files on $disk are harmless leftovers."
                return 1
            fi
            echo "migrated $(date -Is) by vm-space-wizard V2.3" | $SUDO tee "$VMW_DOCKER_ROOT/$VMW_MARKER" >/dev/null
            mig_state_clear
        fi
    else
        MIG_SERVICES_STOPPED=0
        mig_state_clear
        info "Docker is not installed; storage is prepared for when it is."
    fi
    if command -v podman &>/dev/null; then
        systemctl --user start podman.socket 2>/dev/null || true
        $SUDO systemctl start podman.socket 2>/dev/null || true
    fi

    echo ""
    df -h / "$VMW_DOCKER_ROOT" 2>/dev/null
    if (( ! DRY_RUN )) && command -v docker &>/dev/null; then
        c=$($SUDO docker ps -aq 2>/dev/null | wc -l)
        v=$($SUDO docker ps -q 2>/dev/null | wc -l)
        echo -e "\nContainers: $c total, $v running."
        if (( c > v )); then
            echo -e "${YELLOW}Stopped containers (start what you need with: docker start <name>):${NC}"
            $SUDO docker ps -a --filter status=exited --filter status=created --format '   {{.Names}}  ({{.Status}})'
        fi
    fi
    report_host_bind_mounts

    if (( copy_docker || copy_cd )); then
        echo -e "\n${YELLOW}The original copies still occupy space on the root disk (hidden under the new mounts).${NC}"
        echo -e "${YELLOW}After you have confirmed your apps work, reclaim it via 'Audit & Clean Up Leftover Storage After a Migration'.${NC}"
    fi
    umount_root_view
    return 0
}

# ------------------------------------------------------------------------------
# btrfs "portable" migration: docker save (images) + rsync (volumes, which are
# always plain directories regardless of storage driver) + containers
# recreated from `docker inspect`. See the module-level design note above
# this function's call site in _vmw_setup_secondary_disk for why this is used
# instead of btrfs send/receive: Docker's btrfs driver stores every layer as
# a btrfs subvolume, and a plain rsync would flatten those into ordinary
# directories, losing the "is a subvolume" property the driver depends on.
#
# COST, disclosed in the plan before anything runs: containers are recreated
# from their captured config against the reloaded images, so anything a
# container wrote to its OWN writable layer outside a volume is NOT
# preserved. Only true data (named/bind volumes) and the container's
# configuration (image, env, restart policy, published ports, mounts,
# labels, working dir, network membership) survive. Exotic configuration
# (custom entrypoint/cmd override, devices, capabilities, resource limits,
# health checks) is NOT reconstructed and must be checked by hand afterward.
# ------------------------------------------------------------------------------

# Returns one container's full `docker inspect` object (unwrapped from the
# `[...]` array docker always wraps single lookups in).
_vmw_docker_inspect_one() {
    local raw
    raw=$($SUDO docker inspect "$1" 2>/dev/null)
    [[ -n "$raw" ]] || return 0
    _vmw_json unwrap0 "$raw"
}

# Builds a `docker create` argument list (one argument per line — bash has no
# way to return an array, so the caller reads this back with `mapfile`) from
# one container's inspect JSON. Covers: name, image, env, restart policy,
# published ports, volume/bind mounts, labels, working dir, entrypoint (first
# element — docker create only accepts one) + cmd, user, privileged,
# cap-add/cap-drop, devices, memory/cpu limits, and a CMD-SHELL healthcheck.
# Multi-network membership is handled separately via `docker network
# connect` after creation (see migrate_docker_storage_btrfs).
#
# Anything this cannot reconstruct is NEVER silently dropped: it is appended,
# one line per finding, to $2 (a plain file, not a variable — this function
# is always invoked inside a `<(...)` process substitution, which runs in a
# subshell, so a global array written here would vanish before the caller
# could read it; a real file write survives that boundary). The caller
# prints each line with `warn` after reading the create-args back.
_vmw_btrfs_container_create_args() {
    local json="$1" warnfile="$2"
    local name image workdir restart_name restart_max user memory nanocpus privileged hc_type hc_cmd exotic
    local -a args=() entrypoint_arr=() cmd_arr=()
    : > "$warnfile" 2>/dev/null || true

    name=$(_vmw_json name "$json")
    image=$(_vmw_json image "$json")
    workdir=$(_vmw_json workdir "$json")
    user=$(_vmw_json user "$json")
    restart_name=$(_vmw_json restart_name "$json")
    restart_max=$(_vmw_json restart_max "$json")
    privileged=$(_vmw_json privileged "$json")
    memory=$(_vmw_json memory "$json")
    nanocpus=$(_vmw_json nanocpus "$json")

    args+=(--name "$name")

    while IFS= read -r e; do [[ -n "$e" ]] && args+=(--env "$e"); done \
        < <(_vmw_json env "$json")

    if [[ "$restart_name" != "no" && -n "$restart_name" ]]; then
        if [[ "$restart_name" == "on-failure" && "${restart_max:-0}" -gt 0 ]]; then
            args+=(--restart "on-failure:$restart_max")
        else
            args+=(--restart "$restart_name")
        fi
    fi

    while IFS= read -r p; do [[ -n "$p" ]] && args+=(-p "$p"); done < <(_vmw_json portbindings "$json")

    while IFS= read -r m; do [[ -n "$m" ]] && args+=(-v "$m"); done < <(_vmw_json mounts "$json")

    while IFS= read -r l; do [[ -n "$l" ]] && args+=(--label "$l"); done < <(_vmw_json labels "$json")

    [[ -n "$workdir" ]] && args+=(-w "$workdir")
    [[ -n "$user" ]] && args+=(--user "$user")
    [[ "$privileged" == "true" ]] && args+=(--privileged)

    while IFS= read -r c; do [[ -n "$c" ]] && args+=(--cap-add "$c"); done \
        < <(_vmw_json capadd "$json")
    while IFS= read -r c; do [[ -n "$c" ]] && args+=(--cap-drop "$c"); done \
        < <(_vmw_json capdrop "$json")
    while IFS= read -r d; do [[ -n "$d" ]] && args+=(--device "$d"); done < <(_vmw_json devices "$json")

    if [[ -n "$memory" && "$memory" != "0" && "$memory" != "null" ]]; then
        args+=(--memory "$memory")
    fi
    if [[ -n "$nanocpus" && "$nanocpus" != "0" && "$nanocpus" != "null" ]]; then
        args+=(--cpus "$(awk -v n="$nanocpus" 'BEGIN{printf "%.2f", n/1000000000}')")
    fi

    # docker create only accepts ONE --entrypoint value (entrypoint[0]); a
    # multi-part original entrypoint loses everything after that, flagged.
    mapfile -t entrypoint_arr < <(_vmw_json entrypoint "$json")
    if (( ${#entrypoint_arr[@]} > 0 )); then
        args+=(--entrypoint "${entrypoint_arr[0]}")
        if (( ${#entrypoint_arr[@]} > 1 )); then
            echo "entrypoint had ${#entrypoint_arr[@]} parts; only the first (\"${entrypoint_arr[0]}\") could be restored via --entrypoint" >> "$warnfile"
        fi
    fi

    hc_type=$(_vmw_json healthcheck_type "$json")
    if [[ "$hc_type" == "CMD-SHELL" ]]; then
        hc_cmd=$(_vmw_json healthcheck_cmd "$json")
        [[ -n "$hc_cmd" ]] && args+=(--health-cmd "$hc_cmd")
    elif [[ -n "$hc_type" ]]; then
        echo "exec-form healthcheck (Test[0]=$hc_type) is not reconstructed; add it back manually" >> "$warnfile"
    fi

    # Anything else never reconstructed at all, flagged only when actually
    # present so the warning is specific to this one container.
    exotic=$(_vmw_json exotic "$json")
    [[ -n "$exotic" ]] && echo "not reconstructed: $exotic" >> "$warnfile"

    # Cmd must come AFTER the image on the command line.
    mapfile -t cmd_arr < <(_vmw_json cmd "$json")
    args+=("$image")
    (( ${#cmd_arr[@]} > 0 )) && args+=("${cmd_arr[@]}")
    printf '%s\n' "${args[@]}"
}

migrate_docker_storage_btrfs() {
    local disk="$1" fs uuid dsrc dsrc_uuid dest="" legacy=0 marker=0
    local src_docker src_volumes
    local images_tar="" portable_dir=""
    local -a image_refs=() container_jsons=() running_names=() network_names=()
    local n v need=0 avail=0 rc img cid name net driver subnet net_json

    MIG_FSTAB_BACKUP=""; MIG_STAGE_MOUNTED=0; MIG_DOCKER_MOUNTED=0
    MIG_BIND_MOUNTED=0; MIG_SERVICES_STOPPED=0

    vmw_check_prereqs btrfs || return 1

    fs=$($SUDO blkid -s TYPE -o value "$disk" 2>/dev/null)
    uuid=$($SUDO blkid -s UUID -o value "$disk" 2>/dev/null)
    if [[ -z "$fs" || -z "$uuid" ]]; then
        err "Could not read the filesystem type / UUID of $disk."
        return 1
    fi
    if [[ "$fs" != "btrfs" ]]; then
        err "$disk is formatted as '$fs', but the btrfs storage driver needs a btrfs filesystem."
        return 1
    fi
    # Recorded in the log (not just on screen) because $disk is a /dev name,
    # which can point at a different physical disk after a reboot — the
    # UUID is what still identifies this disk when someone reads the log later.
    info "Target disk for this migration: $disk (UUID $uuid)"

    # Compared by UUID, not by /dev name (a plain `grep "$disk"` substring
    # match would also wrongly match a PARTITION of $disk, e.g. /dev/sda1
    # against /dev/sda) — and a /dev path can point at a different physical
    # disk entirely after a reboot renumbers it.
    dsrc=$(findmnt -rn -M "$VMW_DOCKER_ROOT" -o SOURCE 2>/dev/null | head -1)
    if [[ -n "$dsrc" ]]; then
        dsrc_uuid=$($SUDO blkid -s UUID -o value "${dsrc%%\[*}" 2>/dev/null)
        if [[ -n "$dsrc_uuid" && "$dsrc_uuid" == "$uuid" ]]; then
            legacy=1
        else
            err "$VMW_DOCKER_ROOT is already a mount point for a different device ($dsrc)."
            return 1
        fi
    elif [[ -n "$($SUDO lsblk -no MOUNTPOINTS "$disk" 2>/dev/null | tr -d '[:space:]')" ]]; then
        err "$disk is mounted somewhere else. Unmount it first, then re-run."
        return 1
    fi

    if ! mount_root_view; then
        err "Could not create the root-disk view (bind mount of ${VMW_ROOT_SOURCE:-/})."
        return 1
    fi
    src_docker="$ROOT_VIEW$VMW_DOCKER_ROOT"
    src_volumes="$src_docker/volumes"

    if (( legacy )); then
        dest="$VMW_DOCKER_ROOT"
        if $SUDO test -e "$dest/$VMW_MARKER"; then marker=1; fi
    else
        STAGE_DIR=$($SUDO mktemp -d /mnt/.vmwiz-stage.XXXXXX) || { umount_root_view; return 1; }
        info "Mounting $disk at a temporary staging path..."
        run $SUDO mount "$disk" "$STAGE_DIR" || { mig_abort "Could not mount $disk."; return 1; }
        MIG_STAGE_MOUNTED=1
        dest="$STAGE_DIR"
        if $SUDO test -e "$dest/$VMW_MARKER"; then marker=1; fi
    fi

    if (( marker )); then
        ok "This disk was already migrated by the wizard; skipping the portable copy."
        if (( ! legacy )); then
            run $SUDO umount "$STAGE_DIR" || { mig_abort "Could not release the staging mount."; return 1; }
            MIG_STAGE_MOUNTED=0; $SUDO rmdir "$STAGE_DIR" 2>/dev/null; STAGE_DIR=""
            run $SUDO mkdir -p "$VMW_DOCKER_ROOT"
            run $SUDO mount "$disk" "$VMW_DOCKER_ROOT" || { mig_abort "Could not mount $disk on $VMW_DOCKER_ROOT."; return 1; }
            MIG_DOCKER_MOUNTED=1
        fi
        run $SUDO mkdir -p -m 711 "$VMW_DOCKER_ROOT/containerd-data"
        if ! findmnt -rn -M "$VMW_CONTAINERD_ROOT" &>/dev/null; then
            run $SUDO mkdir -p "$VMW_CONTAINERD_ROOT"
            run $SUDO mount --bind "$VMW_DOCKER_ROOT/containerd-data" "$VMW_CONTAINERD_ROOT" \
                || { mig_abort "Could not bind-mount containerd data."; return 1; }
            MIG_BIND_MOUNTED=1
        fi
        mig_update_fstab "$uuid" "$fs" || { mig_abort "fstab update failed."; return 1; }
        mig_install_systemd_dropin || { mig_abort "systemd drop-in install failed."; return 1; }
        umount_root_view
        return 0
    fi

    if (( legacy )); then
        mig_abort "$disk is already mounted on $VMW_DOCKER_ROOT but was not migrated by this wizard. Unmount it first (so the portable copy has a clean staging area), then re-run."
        return 1
    fi

    # --- Capture everything while the OLD Docker (on the root disk) is still running ---
    info "Capturing images, container configs and networks before stopping Docker..."
    snapshot_docker_state
    EXP_IMAGES=$SNAP_IMAGES; EXP_CONTAINERS=$SNAP_CONTAINERS; EXP_VOLUMES=$SNAP_VOLUMES

    local cid_list json cname
    mapfile -t cid_list < <($SUDO docker ps -aq 2>/dev/null)
    for cid in "${cid_list[@]}"; do
        json=$(_vmw_docker_inspect_one "$cid")
        [[ -n "$json" && "$json" != "null" ]] || continue
        container_jsons+=("$json")
        if [[ "$(_vmw_json state_running "$json")" == "true" ]]; then
            cname=$(_vmw_json name "$json")
            running_names+=("$cname")
        fi
    done

    # Image reference set to save: `docker save` only embeds a tag when the
    # image is referenced BY NAME — saving by bare ID drops every tag, even
    # multi-tag ones (this is the exact bug: images used to come back as
    # <none>:<none>). Collect every (id, tag) pair from `docker image ls` so
    # ALL tags of every image are saved by name, plus any image a container
    # actually runs (its resolved .Image content id) that currently has NO
    # tag of its own — e.g. one whose tag moved to a newer build after the
    # container was created — saved by id with its last-known name recorded
    # so it can be restored after load if that name is free on the fresh root.
    declare -A id_tags=() dangling_name=()
    local iid itag used_id cfg_ref
    while IFS=$'\t' read -r iid itag; do
        [[ -n "$iid" ]] || continue
        if [[ -n "$itag" && "$itag" != "<none>:<none>" ]]; then
            id_tags["$iid"]="${id_tags[$iid]:-}${id_tags[$iid]:+ }$itag"
        fi
    done < <($SUDO docker image ls --no-trunc --format '{{.ID}}	{{.Repository}}:{{.Tag}}' 2>/dev/null)

    for json in "${container_jsons[@]}"; do
        used_id=$(_vmw_json image_used "$json")
        [[ -n "$used_id" ]] || continue
        if [[ -z "${id_tags[$used_id]+set}" ]]; then
            cfg_ref=$(_vmw_json image_or_empty "$json")
            if [[ -n "$cfg_ref" && "$cfg_ref" != "$used_id" && "$cfg_ref" != sha256:* ]]; then
                dangling_name["$used_id"]="$cfg_ref"
            fi
            id_tags["$used_id"]=""
        fi
    done

    for iid in "${!id_tags[@]}"; do
        if [[ -n "${id_tags[$iid]}" ]]; then
            for itag in ${id_tags[$iid]}; do image_refs+=("$itag"); done
        else
            image_refs+=("$iid")
        fi
    done

    mapfile -t network_names < <($SUDO docker network ls --filter type=custom --format '{{.Name}}' 2>/dev/null)

    if docker_has_payload "$src_docker" || dir_has_entries "$src_volumes"; then
        v=$(count_volume_entries "$src_volumes"); if (( v > EXP_VOLUMES )); then EXP_VOLUMES=$v; fi
    fi

    # Space check: the volumes directory is rsync'd AND `docker save` writes
    # images.tar onto this same target disk (into $STAGE_DIR, before the
    # container recreate step) — a real migration formatted the disk and
    # only discovered mid-save that images.tar alone didn't fit, because
    # this check used to count the volumes only. One entry per image id
    # (not per tag) so a multi-tag image isn't counted more than once.
    local vol_bytes=0 img_bytes=0 isz
    if dir_has_entries "$src_volumes"; then vol_bytes=$(dir_bytes "$src_volumes"); fi
    for iid in "${!id_tags[@]}"; do
        isz=$($SUDO docker image inspect --format '{{.Size}}' "$iid" 2>/dev/null)
        [[ "$isz" =~ ^[0-9]+$ ]] && img_bytes=$(( img_bytes + isz ))
    done
    need=$(( vol_bytes + img_bytes ))
    if (( ! DRY_RUN )); then
        avail=$($SUDO df --output=avail -B1 "$dest" 2>/dev/null | tail -1 | tr -d ' ')
        if (( need + need / 10 > ${avail:-0} )); then
            mig_abort "Not enough free space on $disk for the volumes and images together: need ~$(human $(( need + need / 10 ))) (volumes $(human "$vol_bytes") + images $(human "$img_bytes")), available $(human "${avail:-0}")."
            return 1
        fi
    fi

    echo -e "\n${CYAN}${BOLD}============== BTRFS / PORTABLE MIGRATION PLAN ==============${NC}"
    echo -e "  Target disk        : ${BOLD}$disk${NC} (btrfs, UUID $uuid)"
    echo -e "  Copy method        : ${BOLD}portable${NC} (docker save/load + volume rsync + container recreate)"
    echo -e "  Images             : ${#image_refs[@]} will be saved and reloaded"
    echo -e "  Volumes            : $( (( vol_bytes > 0 )) && echo "copy ($(human "$vol_bytes"))" || echo 'nothing to copy' )"
    echo -e "  Containers          : ${#container_jsons[@]} will be ${BOLD}recreated${NC} from their saved config"
    echo -e "  Networks            : ${#network_names[@]} custom network(s) will be recreated"
    echo -e "  ${RED}${BOLD}Any data a container wrote to its OWN filesystem outside a volume is LOST.${NC}"
    echo -e "  ${YELLOW}Only volumes, and the container's image/env/ports/restart-policy/mounts, survive.${NC}"
    echo -e "  Original data       : ${GREEN}kept on the root disk, untouched${NC} (remove later via 'Audit & Clean Up Leftover Storage After a Migration')"
    echo -e "  ${YELLOW}Downtime            : Docker and all containers stop during the copy${NC}"
    echo -e "${CYAN}${BOLD}===============================================================${NC}"
    if (( ! DRY_RUN )); then
        if ! confirm "Proceed with the portable btrfs migration? (y/N):"; then
            info "Cancelled. Nothing was changed."
            mig_release_stage; umount_root_view
            return 1
        fi
    fi

    portable_dir="$STAGE_DIR/.vmwiz-portable"
    if (( ${#image_refs[@]} > 0 )); then
        mig_state_set "$disk" "saving-images"
        info "Saving ${#image_refs[@]} image(s) to the new disk (docker save)..."
        run $SUDO mkdir -p "$portable_dir"
        images_tar="$portable_dir/images.tar"
        run $SUDO docker save -o "$images_tar" "${image_refs[@]}" \
            || { mig_abort "docker save failed."; return 1; }
    fi

    mig_state_set "$disk" "stopping-services"
    info "Stopping Docker, containerd and Podman..."
    run $SUDO systemctl stop docker.socket docker.service containerd.service 2>/dev/null
    if command -v podman &>/dev/null; then
        systemctl --user stop podman.socket podman.service 2>/dev/null || true
        $SUDO systemctl stop podman.socket podman.service 2>/dev/null || true
    fi
    MIG_SERVICES_STOPPED=1
    if (( ! DRY_RUN )) && $SUDO systemctl is-active --quiet docker.service; then
        mig_abort "Docker would not stop."; return 1
    fi

    if (( vol_bytes > 0 )); then
        mig_state_set "$disk" "copying-volumes"
        info "Copying volumes (the only part of the old layout that is driver-agnostic)..."
        run $SUDO mkdir -p "$dest/volumes"
        run $SUDO rsync -aHAXS --numeric-ids --info=progress2 "$src_volumes/" "$dest/volumes/"
        rc=$?
        if (( rc != 0 && rc != 24 )); then mig_abort "rsync of volumes failed (exit $rc)."; return 1; fi
    fi

    info "Mounting $disk on $VMW_DOCKER_ROOT..."
    run $SUDO umount "$STAGE_DIR" || { mig_abort "Could not release the staging mount."; return 1; }
    MIG_STAGE_MOUNTED=0
    $SUDO rmdir "$STAGE_DIR" 2>/dev/null
    STAGE_DIR=""
    run $SUDO mkdir -p "$VMW_DOCKER_ROOT"
    run $SUDO mount "$disk" "$VMW_DOCKER_ROOT" || { mig_abort "Could not mount $disk on $VMW_DOCKER_ROOT."; return 1; }
    MIG_DOCKER_MOUNTED=1
    run $SUDO chmod 711 "$VMW_DOCKER_ROOT"
    # The staged images.tar is the same file, physically on $disk, but the
    # staging mountpoint it was written under no longer exists — it is now
    # only reachable via the disk's new mountpoint.
    if [[ -n "$images_tar" ]]; then
        portable_dir="$VMW_DOCKER_ROOT/.vmwiz-portable"
        images_tar="$portable_dir/images.tar"
    fi

    run $SUDO mkdir -p -m 711 "$VMW_DOCKER_ROOT/containerd-data"
    info "Bind-mounting containerd data from the new disk..."
    run $SUDO mkdir -p "$VMW_CONTAINERD_ROOT"
    run $SUDO mount --bind "$VMW_DOCKER_ROOT/containerd-data" "$VMW_CONTAINERD_ROOT" \
        || { mig_abort "Could not bind-mount containerd data."; return 1; }
    MIG_BIND_MOUNTED=1

    mig_state_set "$disk" "updating-fstab"
    info "Updating $VMW_FSTAB (persistent mounts)..."
    mig_update_fstab "$uuid" "$fs" || { mig_abort "fstab update failed."; return 1; }
    mig_install_systemd_dropin || { mig_abort "systemd drop-in install failed."; return 1; }

    mig_state_set "$disk" "starting-services"
    info "Starting containerd and Docker..."
    if $SUDO systemctl cat containerd.service &>/dev/null; then
        run $SUDO systemctl start containerd.service || { mig_abort "containerd failed to start."; return 1; }
    fi
    run $SUDO systemctl start docker.service || { mig_abort "Docker failed to start."; return 1; }
    MIG_SERVICES_STOPPED=0

    if (( DRY_RUN )); then
        umount_root_view
        return 0
    fi

    rc=1
    for _ in $(seq 1 60); do
        if $SUDO docker info &>/dev/null; then rc=0; break; fi
        sleep 1
    done
    if (( rc != 0 )); then mig_abort "Docker did not become ready within 60 seconds."; return 1; fi

    mig_state_set "$disk" "loading-images"
    if [[ -n "$images_tar" ]]; then
        info "Loading images (docker load)..."
        run $SUDO docker load -i "$images_tar" || { mig_abort "docker load failed."; return 1; }
        $SUDO rm -rf "$portable_dir" 2>/dev/null

        if (( ! DRY_RUN )); then
            # Self-heal: saving/loading by name should already restore every
            # tag, but force-restore anything that didn't make it through for
            # some reason, and restore a dangling-but-used image's last-known
            # name now that the fresh root has no conflicting image to protect.
            local missing_tags=""
            for iid in "${!id_tags[@]}"; do
                for itag in ${id_tags[$iid]}; do
                    if ! $SUDO docker image inspect "$itag" &>/dev/null; then
                        if $SUDO docker tag "$iid" "$itag" &>/dev/null; then
                            info "Restored tag $itag -> $iid"
                        else
                            missing_tags="$missing_tags $itag"
                        fi
                    fi
                done
            done
            for iid in "${!dangling_name[@]}"; do
                itag="${dangling_name[$iid]}"
                if ! $SUDO docker image inspect "$itag" &>/dev/null; then
                    $SUDO docker tag "$iid" "$itag" &>/dev/null \
                        && info "Restored last-known name $itag for a previously-dangling (but container-used) image"
                fi
            done
            if [[ -n "$missing_tags" ]]; then
                warn "Could not restore these original tags after load:$missing_tags — recreate them manually (docker tag)."
            fi
        fi
    fi

    mig_state_set "$disk" "recreating-networks-and-containers"
    for net in "${network_names[@]}"; do
        [[ -n "$net" ]] || continue
        net_json=$($SUDO docker network inspect "$net" 2>/dev/null)
        driver=$(_vmw_json network_driver "$net_json")
        subnet=$(_vmw_json network_subnet "$net_json")
        info "Recreating network: $net ($driver)"
        if [[ -n "$subnet" ]]; then
            $SUDO docker network create --driver "$driver" --subnet "$subnet" "$net" &>/dev/null
        else
            $SUDO docker network create --driver "$driver" "$net" &>/dev/null
        fi
    done

    local -a create_args nets_for_container
    local recreate_warnfile recreate_warn_line
    recreate_warnfile=$(mktemp)
    for json in "${container_jsons[@]}"; do
        name=$(_vmw_json name "$json")
        info "Recreating container: $name"
        mapfile -t create_args < <(_vmw_btrfs_container_create_args "$json" "$recreate_warnfile")
        cid=$($SUDO docker create "${create_args[@]}" 2>/dev/null)
        if [[ -z "$cid" ]]; then
            warn "Could not recreate container '$name' — check its image is present and recreate it manually."
            continue
        fi
        while IFS= read -r recreate_warn_line; do
            [[ -n "$recreate_warn_line" ]] && warn "Container '$name': $recreate_warn_line"
        done < "$recreate_warnfile"
        mapfile -t nets_for_container < <(_vmw_json networks_keys "$json")
        for net in "${nets_for_container[@]}"; do
            [[ "$net" == "bridge" ]] && continue
            $SUDO docker network connect "$net" "$cid" &>/dev/null || true
        done
        if ! printf '%s\n' "${nets_for_container[@]}" | grep -qx "bridge"; then
            $SUDO docker network disconnect bridge "$cid" &>/dev/null || true
        fi
    done
    rm -f "$recreate_warnfile" 2>/dev/null

    sleep 2
    for name in "${running_names[@]}"; do
        $SUDO docker start "$name" &>/dev/null || true
    done

    info "Verifying the result..."
    if ! mig_verify "$disk"; then
        mig_abort "Verification failed."
        warn "Everything was reverted to the root-disk state. Copied files on $disk are harmless leftovers."
        return 1
    fi
    echo "migrated $(date -Is) (btrfs/portable) by vm-space-wizard V2.3" | $SUDO tee "$VMW_DOCKER_ROOT/$VMW_MARKER" >/dev/null
    mig_state_clear

    if command -v podman &>/dev/null; then
        systemctl --user start podman.socket 2>/dev/null || true
        $SUDO systemctl start podman.socket 2>/dev/null || true
    fi

    echo ""
    df -h / "$VMW_DOCKER_ROOT" 2>/dev/null
    n=$($SUDO docker ps -aq 2>/dev/null | wc -l)
    v=$($SUDO docker ps -q 2>/dev/null | wc -l)
    echo -e "\nContainers: $n total, $v running."
    report_host_bind_mounts
    echo -e "\n${YELLOW}The original (btrfs subvolume) data is untouched on the root disk.${NC}"
    echo -e "${YELLOW}After you have confirmed every container works as expected, reclaim it via 'Audit & Clean Up Leftover Storage After a Migration'.${NC}"
    echo -e "${YELLOW}Double-check any container that writes outside a volume — that data was NOT carried over.${NC}"
    umount_root_view
    return 0
}

# ------------------------------------------------------------------------------
# Podman: point graphroot+runroot at the new disk (rootless AND rootful), only
# when it is safe to do so, and enable the podman socket for each that applies.
# ------------------------------------------------------------------------------
_vmw_write_storage_conf() {
    local conf_file="$1" graphroot="$2" runroot="$3" owner="$4"
    if (( DRY_RUN )); then
        echo -e "${CYAN}[dry-run]${NC} write $conf_file (graphroot=$graphroot, runroot=$runroot)"
        return 0
    fi
    mkdir -p "$(dirname "$conf_file")" 2>/dev/null || $SUDO mkdir -p "$(dirname "$conf_file")"
    if [[ -f "$conf_file" ]]; then
        $SUDO cp -a "$conf_file" "$conf_file.bak.$(date +%Y%m%d-%H%M%S)"
    fi
    { printf '[storage]\ndriver = "overlay"\ngraphroot = "%s"\nrunroot = "%s"\n' "$graphroot" "$runroot"; } \
        | $SUDO tee "$conf_file" >/dev/null
    [[ -n "$owner" ]] && $SUDO chown "$owner" "$conf_file" 2>/dev/null
}

# Set by every call so the caller's final summary can say exactly what moved
# vs what was skipped (and why) instead of a blanket "now live" claim that
# was wrong whenever Podman was present but already had its own data.
PODMAN_PRESENT=0
PODMAN_ROOTLESS_STATUS=""   # migrated | skipped-existing-data | skipped-no-home | ""
PODMAN_ROOTFUL_STATUS=""    # migrated | skipped-existing-data | ""
PODMAN_ROOTLESS_USER=""

configure_podman_storage() {
    PODMAN_PRESENT=0; PODMAN_ROOTLESS_STATUS=""; PODMAN_ROOTFUL_STATUS=""; PODMAN_ROOTLESS_USER=""
    command -v podman &>/dev/null || return 0
    PODMAN_PRESENT=1
    local user home conf_dir graph run_dir

    # --- Rootless Podman (the common case: the invoking user's own containers) ---
    user="${SUDO_USER:-${USER:-$(id -un)}}"
    PODMAN_ROOTLESS_USER="$user"
    home=$(getent passwd "$user" | cut -d: -f6)
    if [[ -z "$home" ]]; then
        warn "Could not resolve home directory of '$user'; skipping rootless Podman."
        PODMAN_ROOTLESS_STATUS="skipped-no-home"
    elif find "$home/.local/share/containers/storage" -mindepth 1 -print -quit 2>/dev/null | grep -q .; then
        warn "Podman already has local images/containers under $home/.local/share/containers/storage."
        warn "Skipping rootless Podman re-pointing so it keeps working; migrate it manually or run 'podman system reset' first."
        PODMAN_ROOTLESS_STATUS="skipped-existing-data"
    else
        info "Configuring rootless Podman storage path on the new disk..."
        graph="$VMW_DOCKER_ROOT/podman-storage/rootless-$user"
        run_dir="$graph/runroot"
        run $SUDO mkdir -p "$graph" "$run_dir"
        run $SUDO chown -R "$user:$(id -gn "$user")" "$graph"
        run $SUDO chmod 700 "$graph"
        conf_dir="$home/.config/containers"
        _vmw_write_storage_conf "$conf_dir/storage.conf" "$graph" "$run_dir" "$user:$(id -gn "$user")"
        if (( ! DRY_RUN )); then
            run sudo -u "$user" XDG_RUNTIME_DIR="/run/user/$(id -u "$user")" \
                systemctl --user enable --now podman.socket 2>/dev/null \
                || warn "Could not enable the rootless podman.socket for $user (no active user session yet is normal; it will start on next login or 'podman' invocation)."
        fi
        PODMAN_ROOTLESS_STATUS="migrated"
    fi

    # --- Rootful Podman (/var/lib/containers) ---
    if $SUDO find /var/lib/containers/storage -mindepth 1 -print -quit 2>/dev/null | grep -q .; then
        warn "Rootful Podman already has images/containers under /var/lib/containers/storage."
        warn "Skipping rootful Podman re-pointing; migrate it manually or run 'sudo podman system reset' first."
        PODMAN_ROOTFUL_STATUS="skipped-existing-data"
        return 0
    fi
    info "Configuring rootful Podman storage path on the new disk..."
    graph="$VMW_DOCKER_ROOT/podman-storage/rootful"
    run_dir="$graph/runroot"
    run $SUDO mkdir -p "$graph" "$run_dir"
    run $SUDO chmod 700 "$graph"
    _vmw_write_storage_conf "/etc/containers/storage.conf" "$graph" "$run_dir" ""
    if (( ! DRY_RUN )); then
        run $SUDO systemctl enable --now podman.socket 2>/dev/null || true
    fi
    PODMAN_ROOTFUL_STATUS="migrated"
}

# ------------------------------------------------------------------------------
# Menu entry 3: offload Docker/Podman storage to a secondary disk
# ------------------------------------------------------------------------------
_vmw_setup_secondary_disk() {
    clear
    show_header
    echo -e "${YELLOW}[+] Secondary Storage Partitioning & Data Offload Wizard${NC}"
    echo -e "Moves Docker (images, containers, volumes, networks) and containerd to a secondary disk."
    echo -e "Data is copied and verified first; originals stay on the root disk until you clean them up.\n"
    if (( DRY_RUN )); then
        echo -e "${CYAN}${BOLD}*** DRY-RUN MODE: nothing will be changed ***${NC}\n"
    fi
    mig_state_check

    echo -e "${CYAN}--- Currently Detected Block Devices ---${NC}"
    lsblk -o NAME,SIZE,FSTYPE,MOUNTPOINTS
    echo "----------------------------------------------------"

    echo ""
    local TARGET_DISK ROOT_DISK TARGET_NAME TARGET_PK FS_TYPE
    read -r -p "Enter target block device for heavy storage (e.g., /dev/sdb): " TARGET_DISK

    if [[ -z "$TARGET_DISK" ]] || [[ ! -b "$TARGET_DISK" ]]; then
        echo -e "\n${RED}[!] Error: No valid block device specified!${NC}"
        show_attachment_guidelines
        pause
        return 0
    fi

    ROOT_DISK=$(lsblk -no pkname "$(findmnt -n -o SOURCE /)" 2>/dev/null | head -1)
    TARGET_NAME=$(basename "$TARGET_DISK")
    TARGET_PK=$(lsblk -no pkname "$TARGET_DISK" 2>/dev/null | head -1)
    if [[ "$TARGET_NAME" == "$ROOT_DISK" || ( -n "$TARGET_PK" && "$TARGET_PK" == "$ROOT_DISK" ) ]] \
        || lsblk -no MOUNTPOINTS "$TARGET_DISK" 2>/dev/null | grep -qxE '/|/boot|/boot/efi|\[SWAP\]'; then
        echo -e "\n${RED}${BOLD}[CRITICAL SAFETY BLOCK] '$TARGET_DISK' contains your active Linux Root OS (or boot/swap)!${NC}"
        echo -e "${RED}Modifying this drive would destroy your operating system.${NC}"
        pause
        return 0
    fi

    if lsblk -no TYPE "$TARGET_DISK" 2>/dev/null | tail -n +2 | grep -q '^part$'; then
        echo -e "\n${YELLOW}[!] '$TARGET_DISK' contains partitions. Choose the partition itself (e.g. ${TARGET_DISK}1).${NC}"
        pause
        return 0
    fi

    vmw_detect_setup
    vmw_print_detected_setup
    if ! vmw_choose_target_fs "$DET_DRIVER"; then
        pause
        return 0
    fi

    if ! vmw_check_prereqs "$DET_DRIVER"; then
        pause
        return 0
    fi

    FS_TYPE=$(lsblk -no FSTYPE "$TARGET_DISK" 2>/dev/null | head -1 | tr -d ' ')
    local fmt_label="ext4" fmt_cmd=(mkfs.ext4 -F -L docker-data)
    if [[ "$REQUIRED_FS" == "btrfs" ]]; then
        fmt_label="btrfs"
        fmt_cmd=(mkfs.btrfs -f -L docker-data)
    fi

    if [[ -z "$FS_TYPE" ]]; then
        echo -e "\n${YELLOW}[!] Drive '$TARGET_DISK' is unformatted.${NC}"
        if (( DRY_RUN )); then
            echo -e "${CYAN}[dry-run]${NC} would format $TARGET_DISK with $fmt_label (label docker-data); the rest of the plan needs a filesystem, so the dry-run stops here."
            pause
            return 0
        fi
        if confirm "Would you like to format '$TARGET_DISK' with $fmt_label now? (y/N):"; then
            echo -e "${GREEN}--> Formatting $TARGET_DISK with $fmt_label filesystem...${NC}"
            if ! $SUDO "${fmt_cmd[@]}" "$TARGET_DISK"; then
                err "Formatting failed."
                pause
                return 0
            fi
        else
            echo "Format cancelled. Cannot proceed without a formatted filesystem."
            pause
            return 0
        fi
    else
        if ! vmw_verify_target_fs "$FS_TYPE" "$TARGET_DISK"; then
            pause
            return 0
        fi
        echo -e "\n${GREEN}[✔] Existing filesystem ($FS_TYPE) detected on $TARGET_DISK. Preserving data!${NC}"
    fi

    local mig_ok=0
    if [[ "$DET_DRIVER" == "btrfs" ]]; then
        migrate_docker_storage_btrfs "$TARGET_DISK" && mig_ok=1
    else
        migrate_docker_storage "$TARGET_DISK" && mig_ok=1
    fi

    if (( mig_ok )); then
        configure_podman_storage
        if (( DRY_RUN )); then
            echo -e "\n${GREEN}[✔] Dry-run finished. Re-run without --dry-run to apply.${NC}"
        else
            echo -e "\n${GREEN}[✔] SUCCESS${NC}"
            echo -e "  ${GREEN}Docker + containerd:${NC} moved to $TARGET_DISK"
            if (( PODMAN_PRESENT )); then
                case "$PODMAN_ROOTLESS_STATUS" in
                    migrated) echo -e "  ${GREEN}Podman (rootless, $PODMAN_ROOTLESS_USER):${NC} moved to $TARGET_DISK" ;;
                    skipped-existing-data) echo -e "  ${YELLOW}Podman (rootless, $PODMAN_ROOTLESS_USER) was NOT migrated:${NC} it already had its own data; migrate it manually or run 'podman system reset' first" ;;
                    skipped-no-home) echo -e "  ${YELLOW}Podman (rootless) was NOT migrated:${NC} could not resolve a home directory for $PODMAN_ROOTLESS_USER" ;;
                esac
                case "$PODMAN_ROOTFUL_STATUS" in
                    migrated) echo -e "  ${GREEN}Podman (rootful):${NC} moved to $TARGET_DISK" ;;
                    skipped-existing-data) echo -e "  ${YELLOW}Podman (rootful) was NOT migrated:${NC} it already had data under /var/lib/containers; migrate it manually or run 'sudo podman system reset' first" ;;
                esac
            else
                echo -e "  ${CYAN}Podman:${NC} not installed on this system — nothing to migrate"
            fi
        fi
    else
        echo -e "\n${RED}[✘] Migration did not complete. See messages above; the root-disk data is intact.${NC}"
    fi
    pause
    return 0
}

setup_secondary_disk() { _vmw_setup_secondary_disk || true; }

# ------------------------------------------------------------------------------
# Menu entry 5: audit + (confirmed) cleanup of leftovers on the root disk
# ------------------------------------------------------------------------------
_vmw_docker_storage_audit() {
    clear
    show_header
    echo -e "${YELLOW}[+] Docker Storage Audit & Leftover Cleanup${NC}\n"

    local path left dev_live dev_old confirm any_left=0 healthy=0 marker=0
    echo -e "${CYAN}--- Mounts ---${NC}"
    for path in "$VMW_DOCKER_ROOT" "$VMW_CONTAINERD_ROOT"; do
        if findmnt -rn -M "$path" &>/dev/null; then
            echo -e "  ${GREEN}✔${NC} $path  <-  $(findmnt -rn -M "$path" -o SOURCE | head -1)"
        else
            echo -e "  ${YELLOW}✘${NC} $path is NOT a separate mount (its data lives on the root disk)"
        fi
    done
    echo ""
    df -h / "$VMW_DOCKER_ROOT" 2>/dev/null

    if command -v docker &>/dev/null && $SUDO docker info &>/dev/null; then
        healthy=1
        echo -e "\n${CYAN}--- Docker ---${NC}"
        echo "  Root dir  : $($SUDO docker info -f '{{.DockerRootDir}}' 2>/dev/null)"
        echo "  Images    : $($SUDO docker image ls -q 2>/dev/null | sort -u | wc -l)"
        echo "  Containers: $($SUDO docker ps -aq 2>/dev/null | wc -l) ($($SUDO docker ps -q 2>/dev/null | wc -l) running)"
        echo "  Volumes   : $($SUDO docker volume ls -q 2>/dev/null | wc -l)"
    else
        warn "Docker is not responding; leftovers will not be touched."
    fi
    if $SUDO test -e "$VMW_DOCKER_ROOT/$VMW_MARKER"; then marker=1; fi

    if ! mount_root_view; then
        err "Could not create the root-disk view."
        pause
        return 0
    fi

    echo -e "\n${CYAN}--- Leftover copies on the root disk (hidden under the mounts) ---${NC}"
    for path in "$VMW_DOCKER_ROOT" "$VMW_CONTAINERD_ROOT"; do
        findmnt -rn -M "$path" &>/dev/null || continue
        left=$(dir_bytes "$ROOT_VIEW$path")
        if (( left > 1048576 )); then
            any_left=1
            echo -e "  ${YELLOW}$path${NC}: $(human "$left") can be reclaimed"
        else
            echo -e "  ${GREEN}$path${NC}: clean"
        fi
    done
    report_host_bind_mounts

    if (( ! any_left )); then
        echo -e "\n${GREEN}[✔] Nothing to clean up.${NC}"
        umount_root_view
        pause
        return 0
    fi

    echo ""
    if (( ! healthy )); then
        warn "Cleanup refused because Docker is not healthy. Fix Docker first."
        umount_root_view; pause; return 0
    fi
    if (( ! marker )); then
        warn "This disk was not migrated by the wizard (no verification marker). Make sure every container works first."
    fi
    echo -e "${YELLOW}${BOLD}This renames the leftover copies listed above to *.bak on the root disk.${NC}"
    echo -e "Nothing is deleted yet — you get a second chance to remove the .bak copies once you've confirmed everything works."
    echo -e "Your live data on the secondary disk is not touched."
    if (( ASSUME_YES )); then
        confirm="RENAME"
        info "(--yes) auto-confirming: RENAME"
    else
        read -r -p "Type RENAME to continue (anything else cancels): " confirm
    fi
    if [[ "$confirm" != "RENAME" ]]; then
        echo "Cancelled."
        umount_root_view; pause; return 0
    fi

    local bak_suffix renamed_paths=()
    bak_suffix=".bak.$(date +%Y%m%d-%H%M%S)"
    for path in "$VMW_DOCKER_ROOT" "$VMW_CONTAINERD_ROOT"; do
        findmnt -rn -M "$path" &>/dev/null || continue
        dev_live=$($SUDO stat -c %d "$path")
        dev_old=$($SUDO stat -c %d "$ROOT_VIEW$path")
        if [[ -z "$dev_live" || -z "$dev_old" || "$dev_live" == "$dev_old" ]]; then
            err "Safety check failed for $path (both views are the same filesystem). Skipping."
            continue
        fi
        info "Renaming leftover $path to ${path}${bak_suffix} on the root disk..."
        if $SUDO mv "$ROOT_VIEW$path" "$ROOT_VIEW${path}${bak_suffix}"; then
            $SUDO mkdir -p "$ROOT_VIEW$path"
            renamed_paths+=("$ROOT_VIEW${path}${bak_suffix}")
        else
            err "Could not rename $path; leaving it in place."
        fi
    done

    if (( ${#renamed_paths[@]} > 0 )); then
        echo ""
        ok "Renamed. Nothing was deleted. Re-run this audit later to permanently delete the *.bak copies once you're confident everything works."
        # Deliberately NOT gated by --yes/ASSUME_YES: the rename is the automatable
        # step, but permanently deleting the only remaining backup of the original
        # data always needs a real, separate, interactive "y" — this is the one
        # safety net --yes must never skip.
        if (( ASSUME_YES )); then
            info "(--yes) leaving the *.bak copies in place; re-run this audit interactively later to delete them."
        else
            read -r -p "Delete the renamed *.bak copies right now instead of waiting? (y/N): " del_now
            if [[ "$del_now" =~ ^[Yy]$ ]]; then
                for p in "${renamed_paths[@]}"; do
                    info "Deleting $p..."
                    $SUDO rm -rf --one-file-system "$p"
                done
                ok "Backups deleted."
            fi
        fi
    fi
    umount_root_view
    echo ""
    df -h / 2>/dev/null
    ok "Cleanup finished."
    pause
    return 0
}

docker_storage_audit() { _vmw_docker_storage_audit || true; }