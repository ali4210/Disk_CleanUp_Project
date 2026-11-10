#!/usr/bin/env bash
# ==============================================================================
# tests/run-tests.sh — exercises linux/docker-storage-migrate.sh for real,
# without ever touching the real Docker daemon, systemd units, /etc/fstab,
# or a real block device.
#
# Isolation strategy:
#   - "disks" are loop devices backed by sparse files under /tmp (losetup),
#     never a real /dev/sdX.
#   - the "secondary disk" IS mounted at a real path during tests, but that
#     path is /mnt/vmwiz-test-dockerroot, never the real /var/lib/docker
#     (the module's destination path is overridable via VMW_DOCKER_ROOT /
#     VMW_CONTAINERD_ROOT specifically so tests can do this safely).
#   - "docker" and "systemctl" are fake stub binaries (tests/fakebin) that
#     never reach the real daemon or the real systemd units.
#   - /etc/fstab is never touched; VMW_FSTAB points at a throwaway file.
#   - the root-disk "view" binds a throwaway fixture directory, never the
#     real /.
#
# Must run as root (re-execs itself under sudo if not), because mount/losetup/
# mkfs need it and because running as EUID 0 makes the module's own $SUDO
# wrapper a no-op, so our fakebin PATH entries aren't skipped by sudo's
# secure_path.
# ==============================================================================
set -uo pipefail

# Same PATH fix as the two scripts under test (ParrotOS and similar: a normal
# user's PATH can lack the sbin dirs where mkfs.btrfs/mkfs.xfs/losetup/parted
# live). `sudo -E` below preserves whatever PATH we had, it doesn't fix it,
# so this must happen before the self-elevation, not after.
for _vmw_sbin_dir in /usr/sbin /sbin /usr/local/sbin; do
    case ":$PATH:" in
        *":$_vmw_sbin_dir:"*) ;;
        *) PATH="$PATH:$_vmw_sbin_dir" ;;
    esac
done
unset _vmw_sbin_dir
export PATH

if [[ $EUID -ne 0 ]]; then
    echo "[i] Re-executing under sudo (needed for loop devices / mounts on the TEST fixtures only)..."
    exec sudo -E bash "$0" "$@"
fi

REPO_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODULE="$REPO_DIR/linux/docker-storage-migrate.sh"
FAKEBIN="$REPO_DIR/tests/fakebin"
export PATH="$FAKEBIN:$PATH"

TEST_ROOT="$(mktemp -d /tmp/vmwiz-test.XXXXXX)"
LOOP_DEVICES=()
MOUNTED_PATHS=()
PASS=0
FAIL=0
FAILED_NAMES=()

# --- Stubs the module expects from vm-space-wizard.sh when its menu-entry
# wrapper functions are exercised directly; all are used only indirectly, via
# the sourced module's own function bodies, which shellcheck can't see through.
export GREEN='' CYAN='' YELLOW='' RED='' BOLD='' NC=''
# shellcheck disable=SC2329
clear() { :; }
# shellcheck disable=SC2329
show_header() { :; }
# shellcheck disable=SC2329
pause() { :; }
# shellcheck disable=SC2329
show_attachment_guidelines() { :; }

log()  { printf '%s\n' "$*"; }
pass() { PASS=$((PASS+1)); log "  [PASS] $*"; }
fail() { FAIL=$((FAIL+1)); FAILED_NAMES+=("$*"); log "  [FAIL] $*"; }
section() { log ""; log "=== $* ==="; }

# shellcheck disable=SC2329  # invoked via `trap cleanup EXIT` below
cleanup() {
    declare -F _vmw_exit_cleanup >/dev/null && _vmw_exit_cleanup 2>/dev/null
    # Unmount the two real test mountpoints repeatedly — migrate_docker_storage
    # does its own mount --bind onto VMW_CONTAINERD_ROOT on every scenario, and
    # a missed track_mount() call must never leave a stacked mount or a busy
    # loop device behind on the real machine, so this does not rely on
    # MOUNTED_PATHS being complete.
    for mp in /mnt/vmwiz-test-dockerroot /mnt/vmwiz-test-containerdroot "${MOUNTED_PATHS[@]}"; do
        [[ -n "$mp" ]] || continue
        while mountpoint -q "$mp" 2>/dev/null; do umount "$mp" 2>/dev/null || break; done
    done
    # Not iterating $LOOP_DEVICES here: make_loop_disk is always called via
    # $(...) command substitution to capture the device path, which runs it in
    # a subshell — so its LOOP_DEVICES+=() append never reaches this shell's
    # array. Scan losetup directly for anything backed by our own test files
    # instead, which is robust regardless of that.
    for d in $(losetup -a 2>/dev/null | grep -F "$TEST_ROOT/" | cut -d: -f1); do
        losetup -d "$d" 2>/dev/null || true
    done
    rm -rf /mnt/vmwiz-test-dockerroot /mnt/vmwiz-test-containerdroot
    rm -rf "$TEST_ROOT"
}
trap cleanup EXIT

make_loop_disk() {
    local size_mb="$1" img
    img="$TEST_ROOT/disk-$RANDOM.img"
    truncate -s "${size_mb}M" "$img"
    local dev
    dev=$(losetup -f --show "$img")
    LOOP_DEVICES+=("$dev")
    echo "$dev"
}

reset_env() {
    # Fresh per-scenario state: fstab, fake-root fixture, docker/systemctl state,
    # systemd drop-in dir. Never the real equivalents. Loops on the two fixed
    # mountpoints too so a stacked/untracked mount from the previous scenario
    # can never survive into the next one (or linger after the last one).
    for mp in /mnt/vmwiz-test-dockerroot /mnt/vmwiz-test-containerdroot "${MOUNTED_PATHS[@]}"; do
        [[ -n "$mp" ]] || continue
        while mountpoint -q "$mp" 2>/dev/null; do umount "$mp" 2>/dev/null || break; done
    done
    MOUNTED_PATHS=()
    rm -rf "$TEST_ROOT/fstab" "$TEST_ROOT/fakeroot" "$TEST_ROOT/dropin.d" \
           "$TEST_ROOT/docker-state" "$TEST_ROOT/systemctl-state" \
           "$TEST_ROOT/state" "$TEST_ROOT/log"
    printf 'UUID=11111111-1111-1111-1111-111111111111 / ext4 defaults 0 1\n' > "$TEST_ROOT/fstab"
    mkdir -p "$TEST_ROOT/fakeroot/mnt/vmwiz-test-dockerroot" \
             "$TEST_ROOT/fakeroot/mnt/vmwiz-test-containerdroot" \
             "$TEST_ROOT/dropin.d" "$TEST_ROOT/docker-state" "$TEST_ROOT/systemctl-state" \
             "$TEST_ROOT/state" "$TEST_ROOT/log"
    mkdir -p /mnt/vmwiz-test-dockerroot /mnt/vmwiz-test-containerdroot

    export VMW_FSTAB="$TEST_ROOT/fstab"
    export VMW_DOCKER_ROOT="/mnt/vmwiz-test-dockerroot"
    export VMW_CONTAINERD_ROOT="/mnt/vmwiz-test-containerdroot"
    export VMW_ROOT_SOURCE="$TEST_ROOT/fakeroot"
    export VMW_DROPIN_DIR="$TEST_ROOT/dropin.d"
    export VMW_STATE_DIR="$TEST_ROOT/state"
    export VMW_LOG_DIR="$TEST_ROOT/log"
    export FAKE_DOCKER_STATE="$TEST_ROOT/docker-state"
    export FAKE_SYSTEMCTL_STATE="$TEST_ROOT/systemctl-state"
    echo "$VMW_DOCKER_ROOT" > "$FAKE_DOCKER_STATE/rootdir.txt"
    : > "$FAKE_DOCKER_STATE/images.db"; : > "$FAKE_DOCKER_STATE/volumes.txt"; : > "$FAKE_DOCKER_STATE/sizes.db"
    # A default taggable image so mig_verify's write-test (which needs *some*
    # non-<none> image to create/rm a throwaway container from) keeps working
    # for every scenario that doesn't care about image content specifically.
    seed_image "sha256:defaultimg0" "test:latest"
}

track_mount() { MOUNTED_PATHS+=("$1"); }

# Registers an image (id, tag) pair directly in the fake docker's image db —
# the realistic way to seed "pre-existing images" for a scenario, since the
# model is id<->tag like real `docker image ls`, not a flat name list.
seed_image() {
    local id="$1" tag="${2:-}"
    if [[ -n "$tag" ]]; then
        printf '%s\t%s\n' "$id" "$tag" >> "$FAKE_DOCKER_STATE/images.db"
    else
        printf '%s\t<none>:<none>\n' "$id" >> "$FAKE_DOCKER_STATE/images.db"
    fi
}

# Sets the byte size `docker image inspect --format '{{.Size}}'` reports for
# an image id — used to simulate a too-small target disk once images are
# counted, not just volumes (Issue 6).
seed_image_size() {
    local id="$1" bytes="$2"
    printf '%s\t%s\n' "$id" "$bytes" >> "$FAKE_DOCKER_STATE/sizes.db"
}

# Puts dummy "existing Docker data" under the fake root disk's view of
# $VMW_DOCKER_ROOT, sized roughly $1 MB.
seed_existing_docker_data() {
    local size_mb="${1:-2}" base="$TEST_ROOT/fakeroot$VMW_DOCKER_ROOT"
    mkdir -p "$base/containers/abc123" "$base/overlay2/def456" "$base/volumes/myvol/_data"
    echo "running-container" > "$base/containers/abc123/config.v2.json"
    dd if=/dev/urandom of="$base/overlay2/def456/layer.bin" bs=1M count="$size_mb" status=none
    echo "hello" > "$base/volumes/myvol/_data/data.txt"
}

source_module() {
    # shellcheck disable=SC1090
    source "$MODULE" "$@"
    # The module sets its own `trap _vmw_exit_cleanup EXIT`, which — since it's
    # sourced into this same shell — silently replaces our cleanup trap. Without
    # this, the last scenario's sourcing wins and our own loop-device/mount
    # cleanup below never runs when the test script exits.
    trap cleanup EXIT
}

# ------------------------------------------------------------------------------
section "1. Fresh migration onto a blank formatted loop disk"
# ------------------------------------------------------------------------------
reset_env
DISK=$(make_loop_disk 64)
mkfs.ext4 -F -q "$DISK"
source_module --yes

if migrate_docker_storage "$DISK"; then pass "migrate_docker_storage succeeded on a fresh disk"; else fail "migrate_docker_storage should have succeeded on a fresh disk"; fi
track_mount "$VMW_DOCKER_ROOT"

if findmnt -rn -M "$VMW_DOCKER_ROOT" -o SOURCE | grep -q "$DISK"; then pass "VMW_DOCKER_ROOT is mounted from the loop disk"; else fail "VMW_DOCKER_ROOT is not mounted from the loop disk"; fi
if findmnt -rn -M "$VMW_CONTAINERD_ROOT" &>/dev/null; then pass "VMW_CONTAINERD_ROOT is bind-mounted"; else fail "VMW_CONTAINERD_ROOT is not mounted"; fi
if [[ -f "$VMW_DOCKER_ROOT/$VMW_MARKER" ]]; then pass "migration marker file was written"; else fail "migration marker file missing"; fi
if grep -q "nofail" "$VMW_FSTAB"; then pass "fstab entry includes nofail"; else fail "fstab entry missing nofail"; fi
if [[ -n "$MIG_FSTAB_BACKUP" && -f "$MIG_FSTAB_BACKUP" ]]; then pass "fstab was backed up before editing"; else fail "no fstab backup evidence"; fi
if grep -rq "RequiresMountsFor=$VMW_DOCKER_ROOT $VMW_CONTAINERD_ROOT" "$VMW_DROPIN_DIR" 2>/dev/null; then pass "systemd drop-in installed with correct RequiresMountsFor"; else fail "systemd drop-in missing or wrong content"; fi

# ------------------------------------------------------------------------------
section "2. Migration with pre-existing images/containers/volumes on the root disk"
# ------------------------------------------------------------------------------
reset_env
seed_existing_docker_data 3
DISK=$(make_loop_disk 64)
mkfs.ext4 -F -q "$DISK"
source_module --yes

OUT=$(migrate_docker_storage "$DISK"); RC=$?
if (( RC == 0 )); then pass "migration with existing data succeeded"; else fail "migration with existing data should have succeeded"; fi
track_mount "$VMW_DOCKER_ROOT"

if [[ -f "$VMW_DOCKER_ROOT/overlay2/def456/layer.bin" ]]; then pass "existing image layer data was copied to the new disk"; else fail "existing image layer data was NOT copied"; fi
if [[ -f "$VMW_DOCKER_ROOT/volumes/myvol/_data/data.txt" ]]; then pass "existing named volume data was copied to the new disk"; else fail "existing named volume data was NOT copied"; fi
if [[ -f "$TEST_ROOT/fakeroot$VMW_DOCKER_ROOT/overlay2/def456/layer.bin" ]]; then pass "original data on the root disk was left in place (not deleted)"; else fail "original data on the root disk was deleted — it must only be removed via the audit menu"; fi

# Issue 8 (ParrotOS report): the "reclaim it" hint must name the menu entry
# ("Audit & Clean Up Leftover Storage After a Migration"), not a hard-coded
# number like "menu option [5]" that silently goes stale the moment menus
# get renumbered.
if echo "$OUT" | grep -q "Audit & Clean Up Leftover Storage After a Migration"; then
    pass "Issue8: leftover-reclaim hint names the menu entry instead of a number"
else
    fail "Issue8: leftover-reclaim hint does not name the menu entry: $OUT"
fi
if echo "$OUT" | grep -qE "menu option \[?[0-9]+\]?"; then
    fail "Issue8: leftover-reclaim hint still hard-codes a menu number"
else
    pass "Issue8: leftover-reclaim hint does not hard-code a menu number"
fi

# ------------------------------------------------------------------------------
section "3. Re-running the migration against an already-migrated disk (idempotency)"
# ------------------------------------------------------------------------------
FSTAB_LINES_BEFORE=$(wc -l < "$VMW_FSTAB")
if migrate_docker_storage "$DISK"; then pass "re-running migration on an already-migrated disk succeeded (no-op)"; else fail "re-running migration on an already-migrated disk should succeed as a no-op"; fi
FSTAB_LINES_AFTER=$(wc -l < "$VMW_FSTAB")
if [[ "$FSTAB_LINES_BEFORE" == "$FSTAB_LINES_AFTER" ]]; then pass "re-run did not duplicate fstab entries"; else fail "re-run duplicated fstab entries ($FSTAB_LINES_BEFORE -> $FSTAB_LINES_AFTER lines)"; fi
umount "$VMW_CONTAINERD_ROOT" 2>/dev/null || true
umount "$VMW_DOCKER_ROOT" 2>/dev/null || true
MOUNTED_PATHS=()

# ------------------------------------------------------------------------------
section "4. --dry-run makes no changes at all"
# ------------------------------------------------------------------------------
reset_env
seed_existing_docker_data 1
DISK=$(make_loop_disk 64)
mkfs.ext4 -F -q "$DISK"
source_module --dry-run --yes

FSTAB_BEFORE=$(cat "$VMW_FSTAB")
migrate_docker_storage "$DISK" >/dev/null
FSTAB_AFTER=$(cat "$VMW_FSTAB")
if [[ "$FSTAB_BEFORE" == "$FSTAB_AFTER" ]]; then pass "dry-run left fstab untouched"; else fail "dry-run modified fstab"; fi
if findmnt -rn -M "$VMW_DOCKER_ROOT" &>/dev/null; then fail "dry-run actually mounted the disk"; else pass "dry-run did not mount anything"; fi
if [[ -e "$VMW_DROPIN_DIR/99-vm-space-wizard-storage.conf" ]]; then fail "dry-run wrote the systemd drop-in"; else pass "dry-run did not write the systemd drop-in"; fi

# ------------------------------------------------------------------------------
section "5. Rollback when post-migration verification fails"
# ------------------------------------------------------------------------------
reset_env
DISK=$(make_loop_disk 64)
mkfs.ext4 -F -q "$DISK"
source_module --yes
# Make the fake docker report the WRONG root dir after "starting", so mig_verify fails.
echo "/some/other/path" > "$FAKE_DOCKER_STATE/rootdir.txt"

if migrate_docker_storage "$DISK"; then fail "migration should have failed verification and rolled back"; else pass "migration correctly failed when verification detected a problem"; fi
if findmnt -rn -M "$VMW_DOCKER_ROOT" &>/dev/null; then fail "rollback left the disk mounted"; else pass "rollback unmounted the disk"; fi
if grep -q "$DISK" "$VMW_FSTAB" 2>/dev/null; then fail "rollback left an fstab entry behind"; else pass "rollback restored fstab to its original state"; fi
if [[ -e "$VMW_DROPIN_DIR/99-vm-space-wizard-storage.conf" ]]; then fail "rollback left the systemd drop-in behind"; else pass "rollback removed the systemd drop-in"; fi
if [[ -f "$VMW_STATE_DIR/migration.state" ]]; then fail "a completed rollback should have cleared the interrupted-run state file"; else pass "state file cleared after a clean rollback"; fi

# ------------------------------------------------------------------------------
section "6. Interrupted-run state file is detected on the next launch"
# ------------------------------------------------------------------------------
reset_env
mig_state_set "/dev/fake-disk" "copying-data"   # simulate a run that got SIGKILLed mid-copy
if [[ -f "$VMW_STATE_DIR/migration.state" ]]; then pass "a crashed run leaves a state file behind"; else fail "state file was not written"; fi
OUT=$(mig_state_check 2>&1)
if echo "$OUT" | grep -q "did not finish cleanly"; then pass "the next launch detects and reports the interrupted run"; else fail "mig_state_check did not report the interrupted run"; fi

# ------------------------------------------------------------------------------
section "7. Safety refusals"
# ------------------------------------------------------------------------------
reset_env
DISK=$(make_loop_disk 64)
mkfs.ext4 -F -q "$DISK"
source_module --yes

# 7a. Target already mounted elsewhere must be refused.
OTHER_MP="$TEST_ROOT/other-mountpoint"; mkdir -p "$OTHER_MP"
mount "$DISK" "$OTHER_MP"; track_mount "$OTHER_MP"
OUT=$(migrate_docker_storage "$DISK" 2>&1); RC=$?
if (( RC != 0 )) && echo "$OUT" | grep -q "mounted somewhere else"; then pass "refused a disk that is already mounted elsewhere"; else fail "did not refuse an already-mounted-elsewhere disk"; fi
umount "$OTHER_MP"; MOUNTED_PATHS=("${MOUNTED_PATHS[@]/$OTHER_MP}")

# 7b. A disk containing partitions must be refused by the menu wrapper.
PART_DISK=$(make_loop_disk 32)
parted -s "$PART_DISK" mklabel gpt mkpart p1 1MiB 15MiB mkpart p2 15MiB 31MiB >/dev/null
partprobe "$PART_DISK" 2>/dev/null || true
OUT=$(printf '%s\n' "$PART_DISK" | _vmw_setup_secondary_disk 2>&1)
if echo "$OUT" | grep -q "contains partitions"; then pass "refused a whole disk that contains partitions"; else fail "did not refuse a partitioned disk"; fi

# 7c. Too-small target must be refused on free-space grounds.
reset_env
seed_existing_docker_data 20
SMALL_DISK=$(make_loop_disk 8)
mkfs.ext4 -F -q "$SMALL_DISK"
source_module --yes
OUT=$(migrate_docker_storage "$SMALL_DISK" 2>&1)
RC=$?
if (( RC != 0 )) && echo "$OUT" | grep -q "Not enough free space"; then pass "refused a target disk too small to hold the existing data"; else fail "did not refuse a too-small target disk (rc=$RC)"; fi
if findmnt -rn -M "$VMW_DOCKER_ROOT" &>/dev/null; then fail "too-small refusal still left the disk mounted"; else pass "too-small refusal left nothing mounted"; fi

# 7d. Issue 7 (ParrotOS report): the final success message must say exactly
# what moved and what was skipped (and why), not a blanket "Docker,
# containerd and Podman storage now live" — this sandbox has no podman
# binary, so a real end-to-end run through the menu wrapper takes the
# "not installed" branch for real, and must say so explicitly rather than
# implying Podman was migrated when it never even ran.
reset_env
echo "overlay2" > "$FAKE_DOCKER_STATE/driver.txt"
seed_existing_docker_data 2
MSGDISK=$(make_loop_disk 64)
mkfs.ext4 -F -q "$MSGDISK"
source_module --yes
MSG_OUT=$(printf '%s\n' "$MSGDISK" | _vmw_setup_secondary_disk 2>&1)
track_mount "$VMW_DOCKER_ROOT"
if echo "$MSG_OUT" | grep -q "Docker, containerd and Podman storage now live"; then
    fail "Issue7: success message still makes the old blanket claim that Podman is now live"
elif echo "$MSG_OUT" | grep -q "Docker + containerd:.*moved to" && echo "$MSG_OUT" | grep -qi "Podman:.*not installed"; then
    pass "Issue7: success message lists Docker/containerd and Podman separately, and correctly says Podman was not installed"
else
    fail "Issue7: success message did not list what actually moved: $MSG_OUT"
fi

# ------------------------------------------------------------------------------
section "8. Audit/cleanup renames leftovers to .bak instead of deleting them"
# ------------------------------------------------------------------------------
reset_env
seed_existing_docker_data 2
DISK=$(make_loop_disk 64)
mkfs.ext4 -F -q "$DISK"
source_module --yes
migrate_docker_storage "$DISK" >/dev/null
track_mount "$VMW_DOCKER_ROOT"

LEFTOVER_BEFORE="$TEST_ROOT/fakeroot$VMW_DOCKER_ROOT/overlay2/def456/layer.bin"
if [[ -f "$LEFTOVER_BEFORE" ]]; then pass "leftover copy exists on the root disk before cleanup"; else fail "setup problem: no leftover to test cleanup against"; fi

docker_storage_audit >/dev/null 2>&1
if [[ -f "$LEFTOVER_BEFORE" ]]; then fail "cleanup should have renamed the original path away"; else pass "original leftover path no longer exists (renamed)"; fi
if compgen -G "$TEST_ROOT/fakeroot$VMW_DOCKER_ROOT.bak.*" > /dev/null; then pass "leftover was renamed to a .bak path, not deleted outright"; else fail "no .bak path found — cleanup may have deleted instead of renamed"; fi
if [[ -f "$VMW_DOCKER_ROOT/overlay2/def456/layer.bin" ]]; then pass "live data on the secondary disk is untouched by cleanup"; else fail "cleanup touched the live secondary-disk data"; fi

# ------------------------------------------------------------------------------
section "9. Podman"
# ------------------------------------------------------------------------------
if command -v podman &>/dev/null; then
    log "  podman is installed — this should not happen in the CI/sandbox environment, extend this section."
else
    log "  [SKIP] podman is not installed in this environment — rootful/rootless Podman paths were reviewed by hand but not run-tested here."
fi

# ------------------------------------------------------------------------------
section "10. Smoke test: the top-level entry scripts actually launch"
# ------------------------------------------------------------------------------
# Catches exactly the class of bug that slipped past every other test here:
# `set -u` turning a stray reference to an undefined variable (e.g. a copy-
# pasted show_header() that never got its own TARGET_REPO_DIR) into a crash
# the very first time a human runs the real entry point, before any menu
# choice is even made. Runs the real files, piped the Exit choice, isolated
# to $TEST_ROOT via reset_env so it doesn't touch the real /var/log or
# /var/lib paths.
reset_env

OUT=$(printf '0\n' | bash "$REPO_DIR/autorun.sh" 2>&1); RC=$?
if (( RC == 0 )) && ! grep -qi "unbound variable" <<<"$OUT"; then pass "autorun.sh launches and exits cleanly (choice: 0/Exit)"; else fail "autorun.sh crashed or hit an unbound variable (rc=$RC)"; fi

OUT=$(printf '0\n' | bash "$REPO_DIR/autorun.sh" --dry-run 2>&1); RC=$?
if (( RC == 0 )) && ! grep -qi "unbound variable" <<<"$OUT"; then pass "autorun.sh --dry-run launches and exits cleanly"; else fail "autorun.sh --dry-run crashed or hit an unbound variable (rc=$RC)"; fi

OUT=$(printf '0\n' | bash "$REPO_DIR/linux/vm-space-wizard.sh" 2>&1); RC=$?
if (( RC == 0 )) && ! grep -qi "unbound variable" <<<"$OUT"; then pass "vm-space-wizard.sh launches and exits cleanly (choice: 0/Exit)"; else fail "vm-space-wizard.sh crashed or hit an unbound variable (rc=$RC)"; fi

OUT=$(printf '0\n' | bash "$REPO_DIR/linux/vm-space-wizard.sh" --dry-run 2>&1); RC=$?
if (( RC == 0 )) && ! grep -qi "unbound variable" <<<"$OUT"; then pass "vm-space-wizard.sh --dry-run launches and exits cleanly"; else fail "vm-space-wizard.sh --dry-run crashed or hit an unbound variable (rc=$RC)"; fi

OUT=$(printf '1\n0\n' | bash "$REPO_DIR/autorun.sh" 2>&1); RC=$?
if (( RC == 0 )) && ! grep -qi "unbound variable" <<<"$OUT"; then pass "autorun.sh -> vm-space-wizard.sh exec chain launches and exits cleanly"; else fail "the autorun.sh -> vm-space-wizard.sh exec chain crashed or hit an unbound variable (rc=$RC)"; fi

# Submenu back-navigation: 1 enters the container-pruning submenu, 0 backs
# out to the main menu, 0 again exits — the "0 is always back/exit" contract
# this whole section exists to verify.
OUT=$(printf '1\n0\n0\n' | bash "$REPO_DIR/linux/vm-space-wizard.sh" 2>&1); RC=$?
if (( RC == 0 )) && ! grep -qi "unbound variable" <<<"$OUT" && grep -q "Please select an action" <<<"$OUT" && grep -qi "Goodbye" <<<"$OUT"; then
    pass "vm-space-wizard.sh: 0 backs out of the pruning submenu to the main menu, 0 again exits"
else
    fail "vm-space-wizard.sh submenu back-then-exit navigation did not behave as expected (rc=$RC)"
fi

# Invalid input must show "Invalid option" and redisplay the menu, not exit
# or crash; 0 afterward should still exit cleanly.
OUT=$(printf '99\n0\n' | bash "$REPO_DIR/linux/vm-space-wizard.sh" 2>&1); RC=$?
if (( RC == 0 )) && echo "$OUT" | grep -qi "Invalid option" && echo "$OUT" | grep -qi "Goodbye"; then
    pass "vm-space-wizard.sh: invalid input shows 'Invalid option' and redisplays the menu; 0 then exits"
else
    fail "vm-space-wizard.sh did not handle invalid input correctly before exiting (rc=$RC)"
fi

OUT=$(printf '99\n0\n' | bash "$REPO_DIR/autorun.sh" 2>&1); RC=$?
if (( RC == 0 )) && echo "$OUT" | grep -qi "Invalid option" && echo "$OUT" | grep -qi "Goodbye"; then
    pass "autorun.sh: invalid input shows 'Invalid option' and redisplays the menu; 0 then exits"
else
    fail "autorun.sh did not handle invalid input correctly before exiting (rc=$RC)"
fi

# ------------------------------------------------------------------------------
section "11. Storage driver detection and filesystem matching"
# ------------------------------------------------------------------------------
reset_env
DISK=$(make_loop_disk 64)
mkfs.ext4 -F -q "$DISK"
source_module --yes

echo "overlay2" > "$FAKE_DOCKER_STATE/driver.txt"; echo "0" > "$FAKE_DOCKER_STATE/snapshotter.txt"
vmw_detect_setup
if [[ "$DET_DRIVER" == "overlay2" && "$DET_SNAPSHOTTER" == "0" ]]; then pass "detects classic overlay2 graphdriver"; else fail "did not detect overlay2 correctly (driver=$DET_DRIVER snapshotter=$DET_SNAPSHOTTER)"; fi
if vmw_choose_target_fs "$DET_DRIVER" && [[ -z "$REQUIRED_FS" ]]; then pass "overlay2 accepts any ext4/xfs target (REQUIRED_FS empty)"; else fail "overlay2 should not require a specific filesystem"; fi

# This machine's own real Docker reports exactly this shape (Driver=overlayfs
# with a containerd.snapshotter DriverStatus entry) — the modern containerd
# image-store mode. It must be treated like overlay2 (plain files, no
# subvolumes), not refused or mishandled.
echo "overlayfs" > "$FAKE_DOCKER_STATE/driver.txt"; echo "1" > "$FAKE_DOCKER_STATE/snapshotter.txt"
vmw_detect_setup
if [[ "$DET_DRIVER" == "overlayfs" && "$DET_SNAPSHOTTER" == "1" ]]; then pass "detects containerd-snapshotter mode (Driver=overlayfs + driver-type)"; else fail "did not detect containerd snapshotter mode"; fi
if vmw_choose_target_fs "$DET_DRIVER" && [[ -z "$REQUIRED_FS" ]]; then pass "containerd-snapshotter overlayfs is treated like overlay2, not refused"; else fail "containerd-snapshotter overlayfs should not be refused or require a specific filesystem"; fi

echo "btrfs" > "$FAKE_DOCKER_STATE/driver.txt"; echo "0" > "$FAKE_DOCKER_STATE/snapshotter.txt"
vmw_detect_setup
if vmw_choose_target_fs "$DET_DRIVER" && [[ "$REQUIRED_FS" == "btrfs" ]]; then pass "btrfs driver requires a btrfs target filesystem"; else fail "btrfs driver did not set REQUIRED_FS=btrfs"; fi

if vmw_verify_target_fs "ext4" "$DISK" 2>/dev/null; then fail "should refuse an ext4 target when the driver needs btrfs"; else pass "refuses an ext4 target when the driver is btrfs"; fi

echo "zfs" > "$FAKE_DOCKER_STATE/driver.txt"
vmw_detect_setup
OUT=$(vmw_choose_target_fs "$DET_DRIVER" 2>&1); RC=$?
if (( RC != 0 )) && echo "$OUT" | grep -qi "zfs"; then pass "refuses the zfs driver with a clear explanation, before touching anything"; else fail "did not refuse the zfs driver (rc=$RC)"; fi

echo "btrfs" > "$FAKE_DOCKER_STATE/driver.txt"
# A truly empty PATH would also break sourcing the module itself (mkdir/date
# at the top of the file) before we even reach vmw_choose_target_fs. Build a
# minimal PATH with just those tools symlinked in, deliberately leaving out
# mkfs.btrfs/btrfs, so only the thing actually being tested is missing.
MINI_PATH_DIR=$(mktemp -d)
ln -s "$(command -v mkdir)" "$MINI_PATH_DIR/mkdir"
ln -s "$(command -v date)" "$MINI_PATH_DIR/date"
ln -s "$(command -v bash)" "$MINI_PATH_DIR/bash"
OUT=$(VMW_STATE_DIR="$TEST_ROOT/mini-state" VMW_LOG_DIR="$TEST_ROOT/mini-log" PATH="$MINI_PATH_DIR" bash -c '
    source "'"$REPO_DIR"'/linux/docker-storage-migrate.sh" --yes 2>/dev/null
    vmw_choose_target_fs btrfs
' 2>&1); RC=$?
rm -rf "$MINI_PATH_DIR" "$TEST_ROOT/mini-state" "$TEST_ROOT/mini-log"
if (( RC != 0 )) && echo "$OUT" | grep -qi "btrfs-progs"; then pass "refuses btrfs driver with a clear install hint when btrfs-progs is missing"; else fail "did not refuse cleanly when btrfs-progs is missing (rc=$RC): $OUT"; fi

# Regression test for the ParrotOS report: btrfs-progs IS actually installed
# (mkfs.btrfs lives in /usr/sbin on this machine), but a normal user's PATH
# doesn't contain /usr/sbin at all. Strip it from PATH (mirroring that real
# environment, not an artificially empty one) and confirm the module fixes
# its own PATH so the check still passes, instead of wrongly reporting
# btrfs-progs as missing.
if command -v mkfs.btrfs &>/dev/null; then
    NO_SBIN_PATH=$(printf '%s' "$PATH" | tr ':' '\n' | grep -vx '/usr/sbin\|/sbin\|/usr/local/sbin' | paste -sd: -)
    OUT=$(PATH="$NO_SBIN_PATH" command -v mkfs.btrfs 2>&1)
    if [[ -z "$OUT" ]]; then pass "setup check: /usr/sbin really is needed to find mkfs.btrfs on this system"; else fail "setup check failed: mkfs.btrfs is on PATH even without /usr/sbin — test would not prove anything ($OUT)"; fi

    OUT=$(VMW_STATE_DIR="$TEST_ROOT/mini-state" VMW_LOG_DIR="$TEST_ROOT/mini-log" PATH="$NO_SBIN_PATH" bash -c '
        source "'"$REPO_DIR"'/linux/docker-storage-migrate.sh" --yes 2>/dev/null
        command -v mkfs.btrfs &>/dev/null && command -v btrfs &>/dev/null
    ' 2>&1); RC=$?
    rm -rf "$TEST_ROOT/mini-state" "$TEST_ROOT/mini-log"
    if (( RC == 0 )); then pass "module adds /usr/sbin (etc.) to PATH, so mkfs.btrfs/btrfs are found even when the caller's PATH lacks it"; else fail "module did not fix PATH for sbin tools when sourced with /usr/sbin missing from PATH"; fi

    OUT=$(VMW_STATE_DIR="$TEST_ROOT/mini-state2" VMW_LOG_DIR="$TEST_ROOT/mini-log2" PATH="$NO_SBIN_PATH" bash -c '
        source "'"$REPO_DIR"'/linux/docker-storage-migrate.sh" --yes 2>/dev/null
        vmw_choose_target_fs btrfs
    ' 2>&1); RC=$?
    rm -rf "$TEST_ROOT/mini-state2" "$TEST_ROOT/mini-log2"
    if (( RC == 0 )); then pass "vmw_choose_target_fs(btrfs) succeeds even when the caller's PATH lacks /usr/sbin"; else fail "vmw_choose_target_fs(btrfs) wrongly refused when only the caller's PATH, not btrfs-progs itself, was missing /usr/sbin: $OUT"; fi
else
    log "  [SKIP] mkfs.btrfs is not installed in this environment — cannot test the ParrotOS PATH scenario against it."
fi

XFS_DISK=$(make_loop_disk 320)
mkfs.xfs -f -q -n ftype=0 "$XFS_DISK"
echo "overlay2" > "$FAKE_DOCKER_STATE/driver.txt"
vmw_detect_setup; vmw_choose_target_fs "$DET_DRIVER"
if vmw_verify_target_fs "xfs" "$XFS_DISK" 2>/dev/null; then fail "should refuse an xfs ftype=0 target for overlay2"; else pass "refuses an xfs ftype=0 target (overlay2 needs ftype=1)"; fi

XFS_DISK2=$(make_loop_disk 320)
mkfs.xfs -f -q -n ftype=1 "$XFS_DISK2"
if vmw_verify_target_fs "xfs" "$XFS_DISK2" 2>/dev/null; then pass "accepts an xfs ftype=1 target for overlay2"; else fail "should accept an xfs ftype=1 target for overlay2"; fi

# ------------------------------------------------------------------------------
section "12. btrfs driver: portable migration (loop-file btrfs disk)"
# ------------------------------------------------------------------------------
# NOTE on what this does NOT prove: it validates this script's own logic end
# to end (detection -> refusal/format choice -> save/load/recreate sequencing
# -> volume rsync -> fstab/dropin -> verify) against a REAL btrfs filesystem,
# using a stub docker daemon. It does NOT exercise a real Docker daemon's own
# btrfs graphdriver, real `docker save`/`load` tar fidelity, or recreating a
# container with exotic real-world configuration (health checks, custom
# entrypoints, multi-network edge cases) — those need a real btrfs host with
# Docker actually configured to use the btrfs driver, which this project's
# own environment does not have.
reset_env
echo "btrfs" > "$FAKE_DOCKER_STATE/driver.txt"
seed_image "sha256:myappimg0" "myapp:latest"
mkdir -p "$TEST_ROOT/fakeroot$VMW_DOCKER_ROOT/volumes/myvol/_data"
echo "hello-btrfs" > "$TEST_ROOT/fakeroot$VMW_DOCKER_ROOT/volumes/myvol/_data/data.txt"
BDISK=$(make_loop_disk 256)
mkfs.btrfs -f -q "$BDISK"

CID=$(docker create --name webapp --env FOO=bar --restart unless-stopped -v myvol:/data -p 8080:80 --label app=web myapp:latest)
docker network create --driver bridge --subnet 172.30.0.0/24 appnet >/dev/null
docker network connect appnet "$CID" >/dev/null
docker network disconnect bridge "$CID" >/dev/null
docker start "$CID" >/dev/null

if migrate_docker_storage_btrfs "$BDISK" >/dev/null 2>&1; then pass "btrfs portable migration succeeded"; else fail "btrfs portable migration should have succeeded"; fi
track_mount "$VMW_DOCKER_ROOT"

if [[ -f "$VMW_DOCKER_ROOT/$VMW_MARKER" ]]; then pass "btrfs migration marker written"; else fail "btrfs migration marker missing"; fi
if [[ -f "$VMW_DOCKER_ROOT/volumes/myvol/_data/data.txt" ]]; then pass "volume data copied onto the new btrfs disk"; else fail "volume data was not copied"; fi
if grep -q "nofail" "$VMW_FSTAB" && grep -q "btrfs" "$VMW_FSTAB"; then pass "fstab entry for the btrfs disk includes nofail and the right fs type"; else fail "fstab entry missing or wrong for the btrfs disk"; fi
if grep -rq "RequiresMountsFor=$VMW_DOCKER_ROOT $VMW_CONTAINERD_ROOT" "$VMW_DROPIN_DIR" 2>/dev/null; then pass "systemd drop-in installed for the btrfs disk"; else fail "systemd drop-in missing for the btrfs disk"; fi

# Identify the recreated container by ID, not by name or running-state: this
# fake docker (unlike a real daemon) never makes the pre-migration "webapp"
# disappear just because the data-root changed, so both it and the freshly
# recreated one share the name "webapp" — the new one's ID is always
# different, which is the one property that disambiguates them reliably.
RECREATED=""
for f in "$FAKE_DOCKER_STATE"/containers/*.json; do
    if [[ "$(jq -r '.Name' "$f" 2>/dev/null)" == "/webapp" && "$(jq -r '.Id' "$f" 2>/dev/null)" != "$CID" ]]; then
        RECREATED="$f"
    fi
done
if [[ -n "$RECREATED" ]]; then
    pass "container was recreated from its captured config"
    if [[ "$(jq -r '.Config.Image' "$RECREATED")" == "myapp:latest" ]]; then pass "recreated container has the right image"; else fail "recreated container has the wrong image"; fi
    if [[ "$(jq -r '.Config.Env[0]' "$RECREATED")" == "FOO=bar" ]]; then pass "recreated container env preserved"; else fail "recreated container lost its env"; fi
    if [[ "$(jq -r '.HostConfig.RestartPolicy.Name' "$RECREATED")" == "unless-stopped" ]]; then pass "recreated container restart policy preserved"; else fail "recreated container lost its restart policy"; fi
    if [[ "$(jq -r '.HostConfig.PortBindings["80/tcp"][0].HostPort' "$RECREATED")" == "8080" ]]; then pass "recreated container port binding preserved"; else fail "recreated container lost its port binding"; fi
    if [[ "$(jq -r '.Mounts[0].Name' "$RECREATED")" == "myvol" ]]; then pass "recreated container volume mount preserved"; else fail "recreated container lost its volume mount"; fi
    if [[ "$(jq -r '.NetworkSettings.Networks | keys[0]' "$RECREATED")" == "appnet" ]]; then pass "recreated container network membership preserved (and NOT left on default bridge)"; else fail "recreated container network membership wrong"; fi
else
    fail "could not find the recreated container at all"
fi
if grep -q "^appnet$" "$FAKE_DOCKER_STATE/networks.txt"; then pass "custom network was recreated"; else fail "custom network was not recreated"; fi

# --- Issue 1 (ParrotOS report): image tags must survive the btrfs/portable
# migration. Old code saved images by `docker image ls -q` (bare IDs), and
# real `docker save` only embeds a tag when given a NAME — saving by id
# drops every tag, which is exactly what turned three real images into
# <none>:<none> after a real migration. Covers: a multi-tag image (both
# tags must survive), a single-tag image, and a dangling-but-container-used
# image whose original reference text should be restored after load.
reset_env
echo "btrfs" > "$FAKE_DOCKER_STATE/driver.txt"
seed_image "sha256:multitag0" "app:v1"
seed_image "sha256:multitag0" "app:latest"
seed_image "sha256:single0" "sidecar:v1"
seed_image "sha256:dangling0" ""
TAGDISK=$(make_loop_disk 128)
mkfs.btrfs -f -q "$TAGDISK"

# Created by id directly (so .Image resolves to the known dangling id), then
# Config.Image patched to the tag it was originally created from, simulating
# that tag having since moved to a newer build before migration ran.
OLDCID=$(docker create --name oldapp sha256:dangling0)
OLDF="$FAKE_DOCKER_STATE/containers/$OLDCID.json"
jq '.Config.Image = "oldapp:stable"' "$OLDF" > "$OLDF.tmp" && mv "$OLDF.tmp" "$OLDF"

if migrate_docker_storage_btrfs "$TAGDISK" >/dev/null 2>&1; then pass "Issue1: btrfs migration with multi-tag/dangling images succeeded"; else fail "Issue1: btrfs migration with multi-tag/dangling images should have succeeded"; fi
track_mount "$VMW_DOCKER_ROOT"

if docker image inspect app:v1 &>/dev/null; then pass "Issue1: multi-tag image keeps tag app:v1"; else fail "Issue1: multi-tag image LOST tag app:v1 (the original bug)"; fi
if docker image inspect app:latest &>/dev/null; then pass "Issue1: multi-tag image keeps tag app:latest"; else fail "Issue1: multi-tag image LOST tag app:latest (the original bug)"; fi
if docker image inspect sidecar:v1 &>/dev/null; then pass "Issue1: single-tag image keeps its tag"; else fail "Issue1: single-tag image LOST its tag (the original bug)"; fi
if docker image inspect oldapp:stable &>/dev/null; then pass "Issue1: dangling-but-used image's last-known name was restored"; else fail "Issue1: dangling-but-used image's last-known name was not restored"; fi

# Direct proof of the actual fix, independent of the above (which this fake
# docker's lack of "new root starts empty" semantics could otherwise let a
# stale pre-migration row pass regardless of the fix): verify the `docker
# save` CALL itself was given tag names, not bare ids, for every tagged image.
SAVE_LOG="$FAKE_DOCKER_STATE/last_save.tsv"
if grep -qP '^TAG\tapp:v1\t' "$SAVE_LOG"; then pass "Issue1: docker save was called with the NAME app:v1, not a bare id"; else fail "Issue1: docker save was called with a bare id for app:v1, not its name (the original bug)"; fi
if grep -qP '^TAG\tapp:latest\t' "$SAVE_LOG"; then pass "Issue1: docker save was called with the NAME app:latest, not a bare id"; else fail "Issue1: docker save was called with a bare id for app:latest, not its name (the original bug)"; fi
if grep -qP '^TAG\tsidecar:v1\t' "$SAVE_LOG"; then pass "Issue1: docker save was called with the NAME sidecar:v1, not a bare id"; else fail "Issue1: docker save was called with a bare id for sidecar:v1, not its name (the original bug)"; fi

# --- Issue 3 (ParrotOS report): recreated containers must keep their
# command and entrypoint ("sleep 86400" became a restart loop when these
# were dropped), plus user/privileged/caps/devices/memory/cpus/healthcheck.
reset_env
echo "btrfs" > "$FAKE_DOCKER_STATE/driver.txt"
seed_image "sha256:cmdimg0" "bindbox:latest"
CMDISK=$(make_loop_disk 128)
mkfs.btrfs -f -q "$CMDISK"

CMDCID=$(docker create --name sleeper --entrypoint /bin/sh --user 1000:1000 --privileged \
    --cap-add NET_ADMIN --cap-drop MKNOD --device /dev/foo:/dev/bar \
    --memory 134217728 --cpus 1.5 --health-cmd "curl -f http://localhost/" \
    bindbox:latest sleep 86400)

if migrate_docker_storage_btrfs "$CMDISK" >/dev/null 2>&1; then pass "Issue3: btrfs migration with a custom entrypoint/cmd container succeeded"; else fail "Issue3: btrfs migration with a custom entrypoint/cmd container should have succeeded"; fi
track_mount "$VMW_DOCKER_ROOT"

CMDF=""
for f in "$FAKE_DOCKER_STATE"/containers/*.json; do
    if [[ "$(jq -r '.Name' "$f" 2>/dev/null)" == "/sleeper" && "$(jq -r '.Id' "$f" 2>/dev/null)" != "$CMDCID" ]]; then
        CMDF="$f"
    fi
done
if [[ -n "$CMDF" ]]; then
    pass "Issue3: container 'sleeper' was recreated"
    if [[ "$(jq -r '.Config.Entrypoint[0]' "$CMDF")" == "/bin/sh" ]]; then pass "Issue3: entrypoint preserved"; else fail "Issue3: entrypoint LOST (the original bug)"; fi
    if [[ "$(jq -c '.Config.Cmd' "$CMDF")" == '["sleep","86400"]' ]]; then pass "Issue3: cmd preserved (sleep 86400, not a restart loop)"; else fail "Issue3: cmd LOST (the original bug — became a restart loop)"; fi
    if [[ "$(jq -r '.Config.User' "$CMDF")" == "1000:1000" ]]; then pass "Issue3: user preserved"; else fail "Issue3: user not preserved"; fi
    if [[ "$(jq -r '.HostConfig.Privileged' "$CMDF")" == "true" ]]; then pass "Issue3: privileged preserved"; else fail "Issue3: privileged not preserved"; fi
    if [[ "$(jq -r '.HostConfig.CapAdd[0]' "$CMDF")" == "NET_ADMIN" ]]; then pass "Issue3: cap-add preserved"; else fail "Issue3: cap-add not preserved"; fi
    if [[ "$(jq -r '.HostConfig.CapDrop[0]' "$CMDF")" == "MKNOD" ]]; then pass "Issue3: cap-drop preserved"; else fail "Issue3: cap-drop not preserved"; fi
    if [[ "$(jq -r '.HostConfig.Devices[0].PathOnHost' "$CMDF")" == "/dev/foo" ]]; then pass "Issue3: device preserved"; else fail "Issue3: device not preserved"; fi
    if [[ "$(jq -r '.HostConfig.Memory' "$CMDF")" == "134217728" ]]; then pass "Issue3: memory limit preserved"; else fail "Issue3: memory limit not preserved"; fi
    if [[ "$(jq -r '.HostConfig.NanoCpus' "$CMDF")" == "1500000000" ]]; then pass "Issue3: cpu limit preserved"; else fail "Issue3: cpu limit not preserved"; fi
    if [[ "$(jq -r '.Config.Healthcheck.Test[1]' "$CMDF")" == "curl -f http://localhost/" ]]; then pass "Issue3: healthcheck preserved"; else fail "Issue3: healthcheck not preserved"; fi
else
    fail "Issue3: could not find the recreated 'sleeper' container at all"
fi

# Anything genuinely not reconstructed (here: a multi-part entrypoint, which
# `docker create --entrypoint` cannot express beyond its first element) must
# be printed as a warning, never silently dropped. Patch a second element in
# directly (the CLI itself cannot create one, same technique as Issue 1's
# dangling-name test) and check the migration's own output names it.
MULTIEP_CID=$(docker create --name multiep --entrypoint /bin/sh bindbox:latest)
MULTIEP_F="$FAKE_DOCKER_STATE/containers/$MULTIEP_CID.json"
jq '.Config.Entrypoint = ["/bin/sh", "-c"]' "$MULTIEP_F" > "$MULTIEP_F.tmp" && mv "$MULTIEP_F.tmp" "$MULTIEP_F"
# A fresh disk, not $CMDISK again — that one is already migrated and would
# hit the "already migrated" fast path, skipping container recreation (and
# the warning check) entirely. VMW_DOCKER_ROOT is still mounted from CMDISK
# at this point, though, and migrating onto a second disk now correctly
# refuses that as "already a mount point for a different device" (Issue 9's
# UUID-based check) — unmount it first, exactly as a real second migration
# attempt would need to.
umount "$VMW_CONTAINERD_ROOT" 2>/dev/null || true
umount "$VMW_DOCKER_ROOT" 2>/dev/null || true
MULTIEP_DISK=$(make_loop_disk 128)
mkfs.btrfs -f -q "$MULTIEP_DISK"
WARNOUT=$(migrate_docker_storage_btrfs "$MULTIEP_DISK" 2>&1)
if echo "$WARNOUT" | grep -q "entrypoint had 2 parts"; then pass "Issue3: a multi-part entrypoint that cannot be fully restored is reported as a warning, not silently dropped"; else fail "Issue3: a multi-part entrypoint was silently dropped instead of warned about"; fi

# --- Issue 4 (ParrotOS report): the temporary root-view bind mount
# (/mnt/.vmwiz-rootview.*) must never survive a migration — real scenario:
# it stayed mounted after a SUCCESSFUL migration. The direct cause was
# umount_root_view clearing its own tracking variable even when the
# underlying `umount` failed (e.g. busy), so a later retry never happened.
# First prove the actual mechanism: force the view genuinely busy (a
# background process with its CWD inside it — a real EBUSY cause, not a
# simulated one) and confirm umount_root_view detaches it anyway via a
# lazy unmount fallback instead of silently giving up.
reset_env
if mount_root_view; then
    RV="$ROOT_VIEW"
    BUSY_MARKER="/tmp/vmwiz-busy-marker.$$"
    rm -f "$BUSY_MARKER"
    ( cd "$RV" && touch "$BUSY_MARKER" && sleep 5 ) &
    BUSY_PID=$!
    for _ in $(seq 1 50); do [[ -f "$BUSY_MARKER" ]] && break; sleep 0.1; done
    umount_root_view
    if findmnt -rn -M "$RV" &>/dev/null; then fail "Issue4: root view is still mounted after umount_root_view even though it should have fallen back to a lazy unmount"; else pass "Issue4: umount_root_view detaches a genuinely busy root view via lazy unmount instead of silently giving up"; fi
    kill "$BUSY_PID" 2>/dev/null; wait "$BUSY_PID" 2>/dev/null || true
    rm -f "$BUSY_MARKER"
else
    fail "Issue4: setup problem — could not create the root view to test against"
fi

# Then the end-to-end invariant on real (non-forced) success and failure paths.
reset_env
echo "btrfs" > "$FAKE_DOCKER_STATE/driver.txt"
LEAKDISK=$(make_loop_disk 128)
mkfs.btrfs -f -q "$LEAKDISK"
migrate_docker_storage_btrfs "$LEAKDISK" >/dev/null 2>&1
track_mount "$VMW_DOCKER_ROOT"
LEFTOVER=$(findmnt -rn -o TARGET 2>/dev/null | grep -E '/mnt/\.vmwiz-(rootview|stage)\.' || true)
if [[ -z "$LEFTOVER" ]]; then pass "Issue4: no leftover .vmwiz-rootview/.vmwiz-stage mount after a successful migration"; else fail "Issue4: leftover mount after success: $LEFTOVER"; fi

reset_env
echo "btrfs" > "$FAKE_DOCKER_STATE/driver.txt"
FAILDISK=$(make_loop_disk 128)
mkfs.btrfs -f -q "$FAILDISK"
echo "/some/wrong/path" > "$FAKE_DOCKER_STATE/rootdir.txt"   # forces mig_verify to fail -> mig_abort -> rollback
migrate_docker_storage_btrfs "$FAILDISK" >/dev/null 2>&1
LEFTOVER2=$(findmnt -rn -o TARGET 2>/dev/null | grep -E '/mnt/\.vmwiz-(rootview|stage)\.' || true)
if [[ -z "$LEFTOVER2" ]]; then pass "Issue4: no leftover .vmwiz-rootview/.vmwiz-stage mount after a forced (verification) failure"; else fail "Issue4: leftover mount after forced failure: $LEFTOVER2"; fi

# migrate_docker_storage (the plain-rsync path) must refuse a btrfs-driver
# setup rather than silently flattening subvolumes into plain directories.
reset_env
echo "btrfs" > "$FAKE_DOCKER_STATE/driver.txt"
BDISK2=$(make_loop_disk 64)
mkfs.btrfs -f -q "$BDISK2"
OUT=$(migrate_docker_storage "$BDISK2" 2>&1); RC=$?
if (( RC != 0 )) && echo "$OUT" | grep -qi "btrfs"; then pass "the plain-rsync path refuses a btrfs-driver setup instead of flattening subvolumes"; else fail "the plain-rsync path did not refuse a btrfs-driver setup (rc=$RC)"; fi

# Idempotent re-run against an already-migrated btrfs disk (fast path, no re-copy).
reset_env
echo "btrfs" > "$FAKE_DOCKER_STATE/driver.txt"
seed_image "sha256:myappimg0" "myapp:latest"
BDISK3=$(make_loop_disk 256)
mkfs.btrfs -f -q "$BDISK3"
migrate_docker_storage_btrfs "$BDISK3" >/dev/null 2>&1
track_mount "$VMW_DOCKER_ROOT"
FSTAB_LINES_BEFORE=$(wc -l < "$VMW_FSTAB")
if migrate_docker_storage_btrfs "$BDISK3" >/dev/null 2>&1; then pass "re-running the btrfs migration on an already-migrated disk succeeded (no-op)"; else fail "re-running the btrfs migration should succeed as a no-op"; fi
FSTAB_LINES_AFTER=$(wc -l < "$VMW_FSTAB")
if [[ "$FSTAB_LINES_BEFORE" == "$FSTAB_LINES_AFTER" ]]; then pass "btrfs re-run did not duplicate fstab entries"; else fail "btrfs re-run duplicated fstab entries"; fi

# --- Issue 6 (ParrotOS report): the free-space check must count the images
# `docker save` is about to write onto the SAME target disk (into
# $STAGE_DIR/.vmwiz-portable/images.tar), not just the volumes directory —
# old code's comment said outright "only the volumes directory is actually
# copied", which was true of rsync but not of docker save. The volume here
# is tiny (real bytes on disk); the image's declared size is deliberately
# huge, so volumes-alone comfortably fits the disk but volumes+images does
# not — isolating exactly what's being counted, not real disk exhaustion.
reset_env
echo "btrfs" > "$FAKE_DOCKER_STATE/driver.txt"
seed_image "sha256:hugeimg0" "hugeapp:latest"
seed_image_size "sha256:hugeimg0" $(( 5 * 1024 * 1024 * 1024 ))   # 5 GiB, declared only
mkdir -p "$TEST_ROOT/fakeroot$VMW_DOCKER_ROOT/volumes/tinyvol/_data"
echo "tiny" > "$TEST_ROOT/fakeroot$VMW_DOCKER_ROOT/volumes/tinyvol/_data/f.txt"
SPACEDISK=$(make_loop_disk 200)
mkfs.btrfs -f -q "$SPACEDISK"
SPACE_OUT=$(migrate_docker_storage_btrfs "$SPACEDISK" 2>&1)
SPACE_RC=$?
if (( SPACE_RC != 0 )) && echo "$SPACE_OUT" | grep -qi "Not enough free space.*images"; then
    pass "Issue6: btrfs migration refuses up front when volumes+images together don't fit (images were being ignored, the original bug)"
else
    fail "Issue6: btrfs migration should have refused for insufficient space counting images too (rc=$SPACE_RC): $SPACE_OUT"
fi
if findmnt -rn -M "$VMW_DOCKER_ROOT" &>/dev/null; then fail "Issue6: refused migration left the target disk mounted"; else pass "Issue6: refused migration left nothing mounted"; fi

# --- Issue 9 (ParrotOS report): a real reboot renamed the target disk from
# /dev/sdb to /dev/sda — UUID stayed the same, only the /dev enumeration
# changed, which is normal and expected (BIOS/kernel device ordering is not
# guaranteed stable). "Already migrated" detection and mig_verify must keep
# recognizing the disk by UUID, not by whatever /dev name it happened to
# have during the original migration. Simulated here by detaching the loop
# device and reattaching the SAME backing file under a different loop
# number — same filesystem, same UUID, guaranteed-different /dev path,
# exactly like a reboot's device renumbering.
reset_env
echo "btrfs" > "$FAKE_DOCKER_STATE/driver.txt"
seed_image "sha256:rebootimg0" "rebootapp:latest"
REBOOT_DISK=$(make_loop_disk 128)
mkfs.btrfs -f -q "$REBOOT_DISK"
if migrate_docker_storage_btrfs "$REBOOT_DISK" >/dev/null 2>&1; then pass "Issue9: initial btrfs migration succeeded"; else fail "Issue9: initial btrfs migration should have succeeded"; fi
track_mount "$VMW_DOCKER_ROOT"
REBOOT_UUID=$(blkid -s UUID -o value "$REBOOT_DISK")

umount "$VMW_CONTAINERD_ROOT" 2>/dev/null || true
umount "$VMW_DOCKER_ROOT" 2>/dev/null || true
REBOOT_IMG=$(losetup -l -O BACK-FILE -n "$REBOOT_DISK" | tr -d ' ')
losetup -d "$REBOOT_DISK"
# `losetup -f` would just hand back this same, now-free number, which proves
# nothing — force a specific, guaranteed-different node instead, the same
# way a reboot's device enumeration can land a disk on a different name.
REBOOT_LOOPNUM=$(echo "$REBOOT_DISK" | grep -oE '[0-9]+$')
NEW_REBOOT_DISK="/dev/loop$(( REBOOT_LOOPNUM + 77 ))"
losetup "$NEW_REBOOT_DISK" "$REBOOT_IMG"
NEW_REBOOT_UUID=$(blkid -s UUID -o value "$NEW_REBOOT_DISK")
if [[ -n "$NEW_REBOOT_UUID" && "$NEW_REBOOT_UUID" == "$REBOOT_UUID" && "$NEW_REBOOT_DISK" != "$REBOOT_DISK" ]]; then
    pass "Issue9 setup: reattached loop device has a different /dev name but the same UUID (reboot simulation is valid)"
else
    fail "Issue9 setup: reboot simulation did not reproduce a same-UUID/different-name disk — test fixture broken"
fi

# What fstab (UUID-based already) would do on real boot: mount the disk at
# its recorded mountpoints under its NEW /dev name.
mkdir -p "$VMW_DOCKER_ROOT" "$VMW_CONTAINERD_ROOT"
mount "$NEW_REBOOT_DISK" "$VMW_DOCKER_ROOT"
mount --bind "$VMW_DOCKER_ROOT/containerd-data" "$VMW_CONTAINERD_ROOT"
track_mount "$VMW_DOCKER_ROOT"; track_mount "$VMW_CONTAINERD_ROOT"

# This run's own $disk argument and findmnt's own SOURCE are both always
# queried fresh/live, so they never actually disagree within one process —
# these two checks exercise the realistic reboot scenario end-to-end, but
# the substring-collision test below is what actually proves the UUID
# comparison catches something name-based comparison would get wrong.
if mig_verify "$NEW_REBOOT_DISK" >/dev/null 2>&1; then
    pass "Issue9: mig_verify still matches the disk by UUID after its /dev name changed"
else
    fail "Issue9: mig_verify did not recognize the disk after its /dev name changed"
fi

REBOOT_OUT=$(migrate_docker_storage_btrfs "$NEW_REBOOT_DISK" 2>&1); REBOOT_RC=$?
if (( REBOOT_RC == 0 )) && echo "$REBOOT_OUT" | grep -qi "already migrated"; then
    pass "Issue9: already-migrated detection still recognizes the disk by UUID after its /dev name changed"
else
    fail "Issue9: already-migrated detection failed after the disk's /dev name changed (rc=$REBOOT_RC): $REBOOT_OUT"
fi

# mig_state_set is only called mid-flight (cleared again on success), so
# exercise it directly rather than relying on timing within a full run.
mig_state_set "$NEW_REBOOT_DISK" "testing-issue9"
if grep -q "uuid=$NEW_REBOOT_UUID" "$VMW_STATE_DIR/migration.state" 2>/dev/null; then
    pass "Issue9: migration state file records the disk's UUID, not just its /dev name"
else
    STATE_CONTENT=""
    [[ -f "$VMW_STATE_DIR/migration.state" ]] && STATE_CONTENT=$(cat "$VMW_STATE_DIR/migration.state")
    fail "Issue9: migration state file does not record the disk's UUID: $STATE_CONTENT"
fi
mig_state_clear

# Direct proof the already-migrated check compares by UUID, not a crude
# substring match of /dev names: the old code's `grep -q "$disk"` against
# findmnt's SOURCE would wrongly call /dev/loop90 "already migrated" just
# because its digits are a PREFIX of an unrelated /dev/loop900 that happens
# to be mounted on VMW_DOCKER_ROOT — a real device-identity bug that a
# reboot can trigger just as easily as any other device renumbering.
umount "$VMW_CONTAINERD_ROOT" 2>/dev/null || true
umount "$VMW_DOCKER_ROOT" 2>/dev/null || true
COLLIDE_IMG_A=$(mktemp "$TEST_ROOT/collide-a.XXXXXX.img"); truncate -s 150M "$COLLIDE_IMG_A"
COLLIDE_IMG_B=$(mktemp "$TEST_ROOT/collide-b.XXXXXX.img"); truncate -s 150M "$COLLIDE_IMG_B"
losetup -d /dev/loop900 2>/dev/null; losetup -d /dev/loop90 2>/dev/null
losetup /dev/loop900 "$COLLIDE_IMG_A"
losetup /dev/loop90 "$COLLIDE_IMG_B"
mkfs.btrfs -f -q /dev/loop900
mkfs.btrfs -f -q /dev/loop90
if migrate_docker_storage_btrfs /dev/loop900 >/dev/null 2>&1; then pass "Issue9: setup migration for the substring-collision test succeeded"; else fail "Issue9: setup migration for the substring-collision test should have succeeded"; fi
track_mount "$VMW_DOCKER_ROOT"
COLLIDE_OUT=$(migrate_docker_storage_btrfs /dev/loop90 2>&1); COLLIDE_RC=$?
if (( COLLIDE_RC != 0 )) && echo "$COLLIDE_OUT" | grep -qi "different device"; then
    pass "Issue9: /dev/loop90 was correctly refused as a different device from the /dev/loop900 actually mounted (not a name-substring false match)"
else
    fail "Issue9: /dev/loop90 was NOT refused as a different device — name-substring matching treated it as the same disk as /dev/loop900 (rc=$COLLIDE_RC): $COLLIDE_OUT"
fi
losetup -d /dev/loop900 2>/dev/null; losetup -d /dev/loop90 2>/dev/null

# --dry-run must not touch anything on a btrfs disk either.
reset_env
echo "btrfs" > "$FAKE_DOCKER_STATE/driver.txt"
seed_image "sha256:myappimg0" "myapp:latest"
BDISK4=$(make_loop_disk 256)
mkfs.btrfs -f -q "$BDISK4"
source_module --dry-run --yes
migrate_docker_storage_btrfs "$BDISK4" >/dev/null 2>&1
if findmnt -rn -M "$VMW_DOCKER_ROOT" &>/dev/null; then fail "btrfs --dry-run actually mounted the disk"; else pass "btrfs --dry-run did not mount anything"; fi
if [[ -e "$VMW_DROPIN_DIR/99-vm-space-wizard-storage.conf" ]]; then fail "btrfs --dry-run wrote the systemd drop-in"; else pass "btrfs --dry-run did not write the systemd drop-in"; fi

# ------------------------------------------------------------------------------
section "13. PowerShell menus: 0-as-back/exit (parse-check, lint, and — where pwsh is available — real navigation)"
# ------------------------------------------------------------------------------
# IMPORTANT: this validates the pure control-flow logic of the "0 is always
# back/exit" renumbering on Linux, via PowerShell 7 (pwsh), which is
# cross-platform. The Windows-specific functions these menus call out to
# (VBoxManage.exe, vmware-vdiskmanager.exe, wsl.exe, real Windows paths) all
# no-op harmlessly here (their own Test-Path / Get-Command guards report
# "not found" on Linux) — they are NOT exercised by this section. This does
# NOT validate: the real VBoxManage/vmware-vdiskmanager/wsl.exe integration,
# real Windows path handling, or Windows PowerShell 5.1 specifically (only
# PowerShell 7/pwsh was available to test with here). That must be checked
# by hand on a real Windows host before relying on it.
PS1_FILES=(modules/vm-space-wizard.ps1 modules/virtualbox-engine.ps1 modules/vmware-engine.ps1 modules/docker-desktop-engine.ps1)

if command -v pwsh &>/dev/null; then
    for f in "${PS1_FILES[@]}"; do
        OUT=$(pwsh -NoProfile -Command "
            \$tokens = \$null; \$errors = \$null
            [System.Management.Automation.Language.Parser]::ParseFile('$REPO_DIR/$f', [ref]\$tokens, [ref]\$errors) | Out-Null
            if (\$errors.Count -eq 0) { Write-Output 'PARSE_OK' } else { \$errors | ForEach-Object { Write-Output \$_.Message } }
        " 2>&1)
        if [[ "$OUT" == "PARSE_OK" ]]; then pass "$f parses cleanly"; else fail "$f has parse errors: $OUT"; fi
    done

    if pwsh -NoProfile -Command "Get-Module -ListAvailable PSScriptAnalyzer" 2>/dev/null | grep -q PSScriptAnalyzer; then
        for f in "${PS1_FILES[@]}"; do
            OUT=$(pwsh -NoProfile -Command "
                Import-Module PSScriptAnalyzer
                \$r = Invoke-ScriptAnalyzer -Path '$REPO_DIR/$f' -Severity Error,Warning |
                    Where-Object { \$_.RuleName -notin @('PSAvoidUsingWriteHost','PSAvoidTrailingWhitespace','PSUseApprovedVerbs','PSUseSingularNouns') }
                if (\$r) { \$r | ForEach-Object { \"\$(\$_.RuleName): \$(\$_.Message)\" } } else { 'CLEAN' }
            " 2>&1)
            if [[ "$OUT" == "CLEAN" ]]; then pass "$f: PSScriptAnalyzer reports no correctness warnings"; else fail "$f: PSScriptAnalyzer found issues: $OUT"; fi
        done
    else
        log "  [SKIP] PSScriptAnalyzer module not installed — parse-check above still ran."
    fi

    OUT=$(printf '0\n' | timeout 15 pwsh -NoProfile -File "$REPO_DIR/modules/vm-space-wizard.ps1" 2>&1); RC=$?
    if (( RC == 0 )) && echo "$OUT" | grep -qi "Goodbye"; then pass "vm-space-wizard.ps1: 0 at the platform menu exits cleanly"; else fail "vm-space-wizard.ps1 did not exit cleanly on 0 (rc=$RC)"; fi

    OUT=$(printf '1\n0\n0\n' | timeout 15 pwsh -NoProfile -File "$REPO_DIR/modules/vm-space-wizard.ps1" 2>&1); RC=$?
    if (( RC == 0 )) && echo "$OUT" | grep -q "Select your virtualization platform" && echo "$OUT" | grep -qi "Goodbye"; then
        pass "vm-space-wizard.ps1: 0 backs out of the VirtualBox submenu to the platform menu, 0 again exits"
    else
        fail "vm-space-wizard.ps1 submenu back-then-exit navigation did not behave as expected (rc=$RC)"
    fi

    OUT=$(printf '2\n0\n0\n' | timeout 15 pwsh -NoProfile -File "$REPO_DIR/modules/vm-space-wizard.ps1" 2>&1); RC=$?
    if (( RC == 0 )) && echo "$OUT" | grep -qi "Goodbye"; then pass "vm-space-wizard.ps1: 0 backs out of the VMware submenu, 0 again exits"; else fail "vm-space-wizard.ps1 VMware submenu back navigation failed (rc=$RC)"; fi

    OUT=$(printf '3\n0\n0\n' | timeout 15 pwsh -NoProfile -File "$REPO_DIR/modules/vm-space-wizard.ps1" 2>&1); RC=$?
    if (( RC == 0 )) && echo "$OUT" | grep -qi "Goodbye"; then pass "vm-space-wizard.ps1: 0 backs out of the Docker Desktop/Podman submenu, 0 again exits"; else fail "vm-space-wizard.ps1 Docker Desktop/Podman submenu back navigation failed (rc=$RC)"; fi

    OUT=$(printf '99\n0\n' | timeout 15 pwsh -NoProfile -File "$REPO_DIR/modules/vm-space-wizard.ps1" 2>&1); RC=$?
    if (( RC == 0 )) && echo "$OUT" | grep -qi "Invalid choice" && echo "$OUT" | grep -qi "Goodbye"; then
        pass "vm-space-wizard.ps1: invalid input shows 'Invalid choice' and redisplays the menu; 0 then exits"
    else
        fail "vm-space-wizard.ps1 did not handle invalid input correctly before exiting (rc=$RC)"
    fi
else
    log "  [SKIP] pwsh is not installed in this environment — PowerShell menus were not checked at all here."
fi
log "  [NOTE] None of the above exercises real VBoxManage.exe/vmware-vdiskmanager.exe/wsl.exe,"
log "         real Windows paths, or Windows PowerShell 5.1 — verify the menu for real on a Windows host."

# ------------------------------------------------------------------------------
section "14. Issue 2 (ParrotOS report): state file survives a root-owned state dir"
# ------------------------------------------------------------------------------
# Reproduces the exact failure: $VMW_STATE_DIR is created with $SUDO at
# source time (root-owned, 755), then a later PLAIN `>` redirect as a normal
# user fails with "Permission denied" on every single mig_state_set call —
# silently, because of the `|| true` — so crash recovery never recorded
# anything at all. Must actually run as a non-root user against a
# genuinely root-owned directory to prove it, not just as root (EUID 0
# would make $SUDO a no-op and hide the bug entirely).
if [[ -n "${SUDO_USER:-}" ]] && id "$SUDO_USER" &>/dev/null; then
    # Deliberately NOT under $TEST_ROOT: that is created with `mktemp -d`
    # while this whole suite runs as root, which forces mode 0700 no matter
    # what its *contents* get chmod'd to afterward — the non-root user
    # couldn't even traverse into it, which would silently "prove" the bug
    # fixed for the wrong reason. /tmp itself is traversable by everyone, so
    # build the fixture directly under it instead.
    ROOTOWNED_PARENT=$(mktemp -d /tmp/vmwiz-issue2-root.XXXXXX)
    chmod 755 "$ROOTOWNED_PARENT"
    ROOTOWNED_STATE="$ROOTOWNED_PARENT/state"
    ROOTOWNED_LOG="$ROOTOWNED_PARENT/log"
    mkdir -p "$ROOTOWNED_STATE" "$ROOTOWNED_LOG"
    chown -R root:root "$ROOTOWNED_PARENT"
    chmod 755 "$ROOTOWNED_STATE" "$ROOTOWNED_LOG"

    OUT=$(sudo -u "$SUDO_USER" env PATH="$PATH" VMW_STATE_DIR="$ROOTOWNED_STATE" VMW_LOG_DIR="$ROOTOWNED_LOG" bash -c '
        source "'"$REPO_DIR"'/linux/docker-storage-migrate.sh" --yes 2>&1
        mig_state_set "/dev/fake" "copying-data"
        if [[ -f "'"$ROOTOWNED_STATE"'/migration.state" ]]; then echo STATE_WRITTEN; else echo STATE_MISSING; fi
        mig_state_clear
        if [[ -f "'"$ROOTOWNED_STATE"'/migration.state" ]]; then echo STATE_STILL_THERE; else echo STATE_CLEARED; fi
    ' 2>&1)
    if echo "$OUT" | grep -q "STATE_WRITTEN"; then pass "Issue2: mig_state_set writes the state file as a non-root user against a root-owned dir"; else fail "Issue2: mig_state_set could not write the state file (Permission denied, the original bug): $OUT"; fi
    if echo "$OUT" | grep -q "STATE_CLEARED"; then pass "Issue2: mig_state_clear removes the state file as a non-root user against a root-owned dir"; else fail "Issue2: mig_state_clear could not remove the state file: $OUT"; fi
    rm -rf "$ROOTOWNED_PARENT"
else
    log "  [SKIP] no SUDO_USER available to drop privileges to — cannot test the root-owned-state-dir scenario here."
fi

# ------------------------------------------------------------------------------
section "15. Issue 5 (ParrotOS report): dependency checks before formatting, jq-missing falls back to python3"
# ------------------------------------------------------------------------------
# Reproduces the exact failure: a ParrotOS install has no jq at all (apt has
# no candidate), and the module formatted the target disk before discovering
# that. vmw_check_prereqs() now runs before any format prompt, and when jq is
# missing the btrfs path's JSON parsing (_vmw_json) falls back to a python3
# companion script with the same named-query interface instead of refusing.
# This builds a PATH containing every command this process can currently
# resolve EXCEPT jq (so python3 really is the only option, not just "jq is
# untried") and proves a full btrfs migration — including container
# recreation, which is _vmw_json's heaviest user — still succeeds end to end.
reset_env
echo "btrfs" > "$FAKE_DOCKER_STATE/driver.txt"
seed_image "sha256:nojqimg0" "nojqapp:latest"
NOJQDISK=$(make_loop_disk 128)
mkfs.btrfs -f -q "$NOJQDISK"

NOJQCID=$(docker create --name jqlessapp --env FOO=bar --restart unless-stopped \
    -v myvol:/data -p 8080:80 --label app=web nojqapp:latest)
docker network create --driver bridge --subnet 172.31.0.0/24 nojqnet >/dev/null
docker network connect nojqnet "$NOJQCID" >/dev/null
docker network disconnect bridge "$NOJQCID" >/dev/null
docker start "$NOJQCID" >/dev/null

NOJQ_DIR=$(mktemp -d /tmp/vmwiz-nojq.XXXXXX)
IFS=':' read -r -a _vmw_path_dirs <<< "$PATH"
for _d in "${_vmw_path_dirs[@]}"; do
    [[ -d "$_d" ]] || continue
    for _f in "$_d"/*; do
        [[ -f "$_f" && -x "$_f" ]] || continue
        _bn=$(basename "$_f")
        [[ "$_bn" == "jq" ]] && continue
        [[ -e "$NOJQ_DIR/$_bn" ]] && continue
        ln -s "$_f" "$NOJQ_DIR/$_bn" 2>/dev/null
    done
done
unset _vmw_path_dirs _d _f _bn

NOJQ_OUT=$(PATH="$NOJQ_DIR" bash -c '
    if command -v jq >/dev/null 2>&1; then echo "JQ_STILL_ON_PATH"; exit 1; fi
    if ! command -v python3 >/dev/null 2>&1; then echo "NO_PYTHON3_EITHER"; exit 1; fi
    source "'"$MODULE"'" --yes >/dev/null 2>&1
    migrate_docker_storage_btrfs "'"$NOJQDISK"'" >/dev/null 2>&1
    echo "MIGRATE_EXIT:$?"
' 2>&1)
rm -rf "$NOJQ_DIR"
track_mount "$VMW_DOCKER_ROOT"

if echo "$NOJQ_OUT" | grep -q "JQ_STILL_ON_PATH"; then
    fail "Issue5: the no-jq test PATH was not actually jq-free — test fixture is broken"
elif echo "$NOJQ_OUT" | grep -q "NO_PYTHON3_EITHER"; then
    fail "Issue5: no python3 available on this machine — cannot exercise the fallback"
elif echo "$NOJQ_OUT" | grep -q "^MIGRATE_EXIT:0$"; then
    pass "Issue5: btrfs migration succeeded with jq hidden from PATH (python3 fallback)"
else
    fail "Issue5: btrfs migration with jq hidden from PATH should have succeeded via the python3 fallback: $NOJQ_OUT"
fi

if docker image inspect nojqapp:latest &>/dev/null; then
    pass "Issue5: image tag survived the jq-less migration (python3 fallback parsed save/load bookkeeping correctly)"
else
    fail "Issue5: image tag did not survive the jq-less migration"
fi

NOJQ_RECREATED=""
for f in "$FAKE_DOCKER_STATE"/containers/*.json; do
    if [[ "$(jq -r '.Name' "$f" 2>/dev/null)" == "/jqlessapp" && "$(jq -r '.Id' "$f" 2>/dev/null)" != "$NOJQCID" ]]; then
        NOJQ_RECREATED="$f"
    fi
done
if [[ -n "$NOJQ_RECREATED" ]]; then
    pass "Issue5: container was recreated via the python3 fallback (no jq on PATH)"
    if [[ "$(jq -r '.Config.Env[0]' "$NOJQ_RECREATED")" == "FOO=bar" ]]; then pass "Issue5: recreated container's env survived the python3 fallback"; else fail "Issue5: recreated container lost its env under the python3 fallback"; fi
    if [[ "$(jq -r '.HostConfig.PortBindings["80/tcp"][0].HostPort' "$NOJQ_RECREATED")" == "8080" ]]; then pass "Issue5: recreated container's port binding survived the python3 fallback"; else fail "Issue5: recreated container lost its port binding under the python3 fallback"; fi
    if [[ "$(jq -r '.NetworkSettings.Networks | keys[0]' "$NOJQ_RECREATED")" == "nojqnet" ]]; then pass "Issue5: recreated container's custom network survived the python3 fallback"; else fail "Issue5: recreated container lost its custom network under the python3 fallback"; fi
else
    fail "Issue5: could not find the container recreated via the python3 fallback at all"
fi

# vmw_check_prereqs() itself: refuses up front (before any disk/driver work)
# when a hard requirement is missing, for either reason the ParrotOS report
# called out — a core tool absent, or (btrfs only) neither jq nor python3.
PREREQ_OUT=$(bash -c '
    source "'"$MODULE"'" --yes >/dev/null 2>&1
    EMPTY_DIR=$(mktemp -d)
    PATH="$EMPTY_DIR" vmw_check_prereqs overlay2 2>&1
    echo "RC:$?"
    rmdir "$EMPTY_DIR"
' 2>&1)
if echo "$PREREQ_OUT" | grep -q "RC:1" && echo "$PREREQ_OUT" | grep -qi "Missing required tool"; then
    pass "Issue5: vmw_check_prereqs refuses up front when a core tool (rsync/findmnt/blkid) is missing"
else
    fail "Issue5: vmw_check_prereqs did not refuse with every core tool missing: $PREREQ_OUT"
fi

# ------------------------------------------------------------------------------
section "Results"
# ------------------------------------------------------------------------------
log ""
log "Passed: $PASS   Failed: $FAIL"
if (( FAIL > 0 )); then
    log "Failing checks:"
    for n in "${FAILED_NAMES[@]}"; do log "  - $n"; done
    exit 1
fi
exit 0
