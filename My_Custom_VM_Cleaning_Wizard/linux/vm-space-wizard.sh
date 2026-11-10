#!/usr/bin/env bash
# ==============================================================================
# TOOL NAME:    vm-space-wizard.sh (V2.0 Universal Release)
# AUTHOR:       Saleem (Open Source DevOps/Sec Contributor)
# DESCRIPTION:  Universal Linux VM space optimization & disk offloading wizard.
# COMPATIBILITY: Debian, Ubuntu, Kali Linux, CentOS, RHEL, Fedora, Rocky Linux
# HYPERVISORS:   Oracle VirtualBox & VMware Workstation / Player / Fusion
# ==============================================================================

set -euo pipefail

# A normal (non-login, or just minimally-configured) user's PATH often lacks
# the sbin directories — seen on ParrotOS — even though package-manager tools
# this script depends on (apt-get/dnf/pacman/zypper's helpers, etc. and
# anything the sourced migration module needs) are installed there. Fix PATH
# once, here, before anything else runs, same as docker-storage-migrate.sh.
for _vmw_sbin_dir in /usr/sbin /sbin /usr/local/sbin; do
    case ":$PATH:" in
        *":$_vmw_sbin_dir:"*) ;;
        *) PATH="$PATH:$_vmw_sbin_dir" ;;
    esac
done
unset _vmw_sbin_dir
export PATH

# --- Terminal Color Formats ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# Dynamically locate the actual repository directory regardless of where the script is executed from
SCRIPT_SOURCE="${BASH_SOURCE[0]}"
while [ -h "$SCRIPT_SOURCE" ]; do
  SCRIPT_DIR="$( cd -P "$( dirname "$SCRIPT_SOURCE" )" >/dev/null 2>&1 && pwd )"
  SCRIPT_SOURCE="$(readlink "$SCRIPT_SOURCE")"
  [[ $SCRIPT_SOURCE != /* ]] && SCRIPT_SOURCE="$SCRIPT_DIR/$SCRIPT_SOURCE"
done
SCRIPT_DIR="$( cd -P "$( dirname "$SCRIPT_SOURCE" )" >/dev/null 2>&1 && pwd )"
TARGET_REPO_DIR="$( cd -P "$SCRIPT_DIR/.." >/dev/null 2>&1 && pwd )"

# --- Whole-session transcript logging (separate from the migration module's own log) ---
_VMW_SESSION_LOG_DIR="${VMW_LOG_DIR:-/var/log/vm-space-wizard}"
if ! mkdir -p "$_VMW_SESSION_LOG_DIR" 2>/dev/null; then
    # HOME is normally always set, but not guaranteed (minimal sudo/cron
    # contexts), so fall back to /tmp rather than fail under `set -u`.
    _VMW_SESSION_LOG_DIR="${HOME:-/tmp}/.cache/vm-space-wizard/log"
    mkdir -p "$_VMW_SESSION_LOG_DIR" 2>/dev/null || _VMW_SESSION_LOG_DIR=""
fi
if [[ -n "$_VMW_SESSION_LOG_DIR" ]]; then
    _VMW_SESSION_LOG_FILE="$_VMW_SESSION_LOG_DIR/session-$(date +%Y%m%d-%H%M%S)-$$.log"
    exec > >(tee -a "$_VMW_SESSION_LOG_FILE") 2>&1
    echo -e "${CYAN}[i] Full session transcript: $_VMW_SESSION_LOG_FILE${NC}"
fi

# --- Docker/Podman storage migration engine (provides setup_secondary_disk and
# docker_storage_audit — the full rsync+verify+rollback pipeline). Flags such as
# --dry-run and --yes are forwarded to it. ---
MIGRATE_MODULE="$SCRIPT_DIR/docker-storage-migrate.sh"
if [[ -f "$MIGRATE_MODULE" ]]; then
    # shellcheck source=./docker-storage-migrate.sh
    source "$MIGRATE_MODULE" "$@"
else
    echo -e "${RED}[!] Error: Could not locate docker-storage-migrate.sh in ${SCRIPT_DIR}. Storage offload/audit will be unavailable.${NC}"
    setup_secondary_disk() { echo -e "${RED}[!] docker-storage-migrate.sh is missing; cannot offload storage.${NC}"; }
    docker_storage_audit() { echo -e "${RED}[!] docker-storage-migrate.sh is missing; cannot audit storage.${NC}"; }
fi


show_banner() {
    clear
    echo -e "${CYAN}${BOLD}"
    cat << "EOF"
WIZARDWIZARDWIZARDWIZARDWIZARDWIZARDWIZARDWIZARDWIZARDWIZARDWIZARDWIZARDWIZARD
WIZARDWIZARDWIZARDWIZARDWIZAR..::::::::::::::::..IZARDWIZARDWIZARDWIZARDWIZARD
WIZARDWIZARDWIZARDWIZARD.::::::::::::::::::::::::::::.WIZARDWIZARDWIZARDWIZARD
WIZARDWIZARDWIZARDWI.:::::::::'mmMMMMMMMMMMMMmm`:::::::::.RDWIZARDWIZARDWIZARD
WIZARDWIZARDWIZAR.:::::::'mMMMMMMMMMMMMMMMMMMMMMMMMm`:::::::.IZARDWIZARDWIZARD
WIZARDWIZARDWI.::::::'mMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMm`:::::.ARDWIZARDWIZARD
WIZARDWIZARDW.::::'mMMMMMM"            "MMMMMMMMMMMMMMMMMMm`::::.DWIZARDWIZA D
WIZARDWIZAR.::::'mMMMM"   mmMMMMMm          "MMMMMMMMMMMMMMMm`::::.IZARDWIZAr
WIZARDWIZ.::::'mMMMM mmMMMMMMMMMMMMMMm          "MMMMMMMMMMMMMMMMMMMZARDWIZ42
WIZARDWI.:::'mMMMMMMMMMMMMMMMMMMMMMMMMMm           "MMMMMMMMMMMM     ARDWIZa
WIZARDW.:::'mMMMMMMMMMMMMMMMMMMMMMMMMMMMMm            MMMMMMMMMM      RDWIZ  I
WIZARD::::'MMMMMMMMMMMMMMMMMMMMMMMMMMMMMm            mMMMMMMMMMMM     RDWI   D
WIZAR.:::'mMMMMMMMMMMMMMMMMMMM    MMMM"              MMMMMMMMMMMMMMMMMMW"   iD
WIZA.:::'MMMMMMMMMMMMMMMMM           MMMm             MMMMMMMMMM           .AD
WIZA:::'mMMMMMMMMMMMMMM                 MMM         mMMMMMMMMMM            ARD
WIZ.:::mMMMMMMMMMMMM             M        MM       mM  MMMMMMM            ZARD
WIZ:::'MMMMMMMMMMM              mMMm       MM     mM     MMMM            M:ARD
WI.:::MMMMMMMMMM               mMMMMMm      MM   mM        M           mM::.RD
WI:::'MMMMMMMM                mMMMMMMM       MM mM  mM               mMM`:::RD
WI:::mMMMMMMM                mMMMMMMMM        MMM  mMMMM          mMMMMMm:::.D
W':::MMMMMMM                mMMMMMMMMMMM          mMMMMMMM    mMMMMMMMMMM:::`D
W:::'MMMMMM        mMMMMMMMMMMMMMMMMMM MM        mMMMMMMMMMMMMMMMMMMMMMMM`:::D
i:::iMMMMM      mMMMMM     MMMMMMMMMM   MMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMi:::D
z:::IMMMM"    mMMMMMMM      MMMMMMMM                             MMMMMMMMI:::)
a:::iMMMM   mMMMMMMMMMM     MMMMMMMM                              MMMMMMMi:::D
r:::`MMMM  MMMMMMMMMMMMMMMMMMMMMMMMMM                             MMMMMMM,:::D
d`:::MMMm mMMMMMMMMMMMMMMMMMMMMMMM  MM               mMMMm       MMMMMMMM:::,D
W`:::mMMM MMMMMMMMMMMMMMMMMMMMMMM    MMMMMMMMMMMMMMMMMMM        mMMMMMMMm:::.D
WI:::`MMMmMMMMMMMMMMMMMMMMMMMMMM            mMMMMMMMMM         mMMMMMMMM,:::RD
WI`:::MMMMMMMMMMMMMMMMMMMMMMMMM           mMMMMMMMMM           MMMMMMMMM:::'RD
WIZ:::.MMMMMMMMMMMMMMMMMMMMMMM          mMMMMMMMMM            mMMMMMMMM':::ARD
WIZ`MMMMM"""        ""MMMMMMM         mMMMMMMMMM              MMMMMMMMm:::'ARD
WIZA"                     "M        mMMMMMMMMM               mMMMMMMMM'::'ZARD
WI"                               mMMMMMMMMM                 MMMMMMMM,::.IZARD
W  ZAMMMm                       mMMMMMMMMM                   MMMMMMM,:::'IZARD
 IZARD`::Mm                   MMMMMMMMMM        mMMMMMMMMMMMMMMMMMM,:::'WIZARD
WIZARDW`:::M               mMMMMMMMMMMM     mMMMMMMMMM      MMMMMMMm::'DWIZARD
WIZARDWI`::MM           mMMMMMMMMMMMMM   mMMMMMMMMMMM             MM:'RDWIZARD
WIZARDWIZAM MM       mMMMMMMMMMMMMMMM  mMMMMMMMMMMMMMmmmmmmmmmmmMMM:ZARDWIZARD
WIZARDWIZA   Mm   mMMMMMMMMMMMMMMMMM" mMMMMMMMMMMMMMMMMMMMMMM'::::'IZARDWIZARD
WIZARDWIZ     M mMM.MMMMMMMMMMMMMMMm mMMMMMMMMMMMMMMMMMMMMM.::::'DWIZARDWIZARD
WIZARDWI    DWMm`::::"MMMMMMMMMMMMMm MMMMMMMMMMMMMMMMMMM".::::'ARDWIZARDWIZARD
WIZARDW   ARDWIZAR`:::::."MMMMMMMMMMmMMMMMMMMMMMMMMM".:::::'WIZARDWIZARDWIZARD
WIZARDW  ZARDWIZARDWI`:::::::.""MMMMMMMMMMMMMM"".::::::::'RDWIZARDWIZARDWIZARD
WIZARDW  ZARDWIZARDWIZAR`::::::::::::::::::::::::::::'WIZARDWIZARDWIZARDWIZARD
WIZARDWIZARDWIZARDWIZARDWIZAR``::::::::::::::::''IZARDWIZARDWIZARDWIZARDWIZARD
WIZARDWIZARDWIZARDWIZARDWIZARDWIZARDWIZARDWIZARDWIZARDWIZARDWIZARDWIZARDWIZARD
	   .aMMMb  dMP     dMMMMMP .aMMMb  dMMMMb  dMP dMP dMP dMP dMMMMMP 
	  dMP"VMP dMP     dMP     dMP"dMP dMP dMP dMP dMP dMP amr   .dMP"  
	 dMP     dMP     dMMMP   dMMMMMP dMP dMP dMP dMP dMP dMP  .dMP"    
	dMP.aMP dMP     dMP     dMP dMP dMP dMP dMP.dMP.dMP dMP .dMP"      
	VMMMP" dMMMMMP dMMMMMP dMP dMP dMP dMP  VMMMPVMMP" dMP dMMMMMP     
                                                                   
EOF
    echo -e "${NC}"
}

show_header() {
    echo -e "${CYAN}${BOLD}====================================================================${NC}"
    echo -e "${CYAN}${BOLD}         🧙‍♂️ VM SPACE WIZARD - SYSTEM & CONTAINER OPTIMIZER       ${NC}"
    echo -e "${CYAN}${BOLD}====================================================================${NC}"
    echo -e "${YELLOW}GitHub  :${NC} ${BOLD}https://github.com/ali4210${NC}"
    echo -e "${YELLOW}Active Repository Context:${NC} ${BOLD}${TARGET_REPO_DIR}${NC}\n"
}

pause() {
    echo ""
    read -r -p "Press [ENTER] to return to the menu..."
}

show_virtualbox_instructions() {
    echo -e "\n${CYAN}====================================================================${NC}"
    echo -e "${YELLOW}${BOLD} 📌 HOW TO ATTACH A SECONDARY HARD DRIVE IN ORACLE VIRTUALBOX${NC}"
    echo -e "${CYAN}====================================================================${NC}"
    echo -e " If you have not created or attached a secondary VDI drive yet:\n"
    echo -e "  1. Shut down this Linux Virtual Machine."
    echo -e "  2. In VirtualBox Manager (Windows Host), click 'Settings' -> 'Storage'."
    echo -e "  3. Under Controller: SATA, click the 'Add Hard Disk' icon (+)."
    echo -e "  4. Click 'Create' -> Choose 'VDI (VirtualBox Disk Image)'."
    echo -e "  5. Select 'Dynamically Allocated' -> Click Next."
    echo -e "  6. Click the folder icon to browse to your preferred host drive"
    echo -e "     (e.g., D:\\VirtualBox_VMs\\Kali-Docker-Storage.vdi)."
    echo -e "  7. Set your desired disk size (e.g., 200 GB or 500 GB)."
    echo -e "  8. Click 'Create', select the newly created disk, and click 'Choose'."
    echo -e "  9. Click 'OK' to save VM settings and boot up Kali Linux."
    echo -e " 10. Re-run this wizard!"
    echo -e "${CYAN}====================================================================${NC}"
}

show_vmware_instructions() {
    echo -e "\n${CYAN}====================================================================${NC}"
    echo -e "${YELLOW}${BOLD} 📌 HOW TO ATTACH A SECONDARY HARD DRIVE IN VMWARE WORKSTATION / PLAYER${NC}"
    echo -e "${CYAN}====================================================================${NC}"
    echo -e " If you have not created or attached a secondary VMDK drive yet:\n"
    echo -e "  1. Shut down this Linux Virtual Machine."
    echo -e "  2. In VMware, right-click your Virtual Machine -> 'Settings'."
    echo -e "  3. On the Hardware tab, click 'Add...' at the bottom."
    echo -e "  4. Select 'Hard Disk' -> Click Next."
    echo -e "  5. Select Disk Type: 'SCSI' or 'SATA' (Recommended) -> Click Next."
    echo -e "  6. Choose 'Create a new virtual disk' -> Click Next."
    echo -e "  7. Specify maximum capacity (e.g., 200 GB or 500 GB)."
    echo -e "  8. Select 'Store virtual disk as a single file' -> Click Next."
    echo -e "  9. Browse to save location on your host PC and click 'Finish'."
    echo -e " 10. Click 'OK' to save VM settings, boot up Linux, and re-run this wizard!"
    echo -e "${CYAN}====================================================================${NC}"
}

show_attachment_guidelines() {
    echo -e "\n${YELLOW}Would you like guidelines on how to attach a secondary disk?${NC}"
    echo -e "  ${GREEN}[1]${NC} Show Oracle VirtualBox Instructions"
    echo -e "  ${GREEN}[2]${NC} Show VMware Workstation / Player Instructions"
    echo -e "  ${GREEN}[0]${NC} Skip Guidelines"
    read -r -p "Select choice [0-2]: " GUIDE_CHOICE

    case $GUIDE_CHOICE in
        1) show_virtualbox_instructions ;;
        2) show_vmware_instructions ;;
        *) echo "Skipping guidelines..." ;;
    esac
}

# Runs one prune command; never lets a single failing engine abort the whole
# wizard (set -e would otherwise kill the menu loop on any non-zero exit).
_vmw_run_prune() {
    local label="$1"; shift
    if "$@"; then
        echo -e "${GREEN}[✔] $label${NC}"
    else
        echo -e "${YELLOW}[!] $label reported an error (exit $?) — continuing.${NC}"
    fi
}

clean_containers() {
    while true; do
        clear
        show_header
        echo -e "${YELLOW}${BOLD}[+] Granular Container Cleanup Engine (Docker & Podman)${NC}\n"
        echo -e "Select container components to clean:"
        echo -e "  ${GREEN}[1]${NC} Prune Build Caches Only ${CYAN}(Safe: Keeps images & containers)${NC}"
        echo -e "  ${GREEN}[2]${NC} Prune Unused Volumes Only ${CYAN}(Deletes unattached volumes)${NC}"
        echo -e "  ${GREEN}[3]${NC} Prune Stopped Containers Only ${CYAN}(Deletes non-running containers)${NC}"
        echo -e "  ${GREEN}[4]${NC} Prune Dangling Images Only ${CYAN}(Untagged image layers)${NC}"
        echo -e "  ${GREEN}[5]${NC} ${BOLD}FULL DEEP CLEAN${NC} ${RED}(Prune ALL unused containers, images, volumes & caches)${NC}"
        echo -e "  ${GREEN}[0]${NC} Return to Main Menu"
        echo -e "\n===================================================================="
        read -r -p "Select prune option [0-5]: " PRUNE_CHOICE

        case $PRUNE_CHOICE in
            1)
                echo -e "\n${GREEN}--> Cleaning Docker & Podman build caches...${NC}"
                command -v docker &>/dev/null && _vmw_run_prune "Docker build cache pruned" docker builder prune -f
                command -v podman &>/dev/null && _vmw_run_prune "Podman build cache pruned" podman builder prune -f
                pause
                ;;
            2)
                echo -e "\n${GREEN}--> Cleaning unused persistent volumes...${NC}"
                command -v docker &>/dev/null && _vmw_run_prune "Docker unused volumes pruned" docker volume prune -f
                command -v podman &>/dev/null && _vmw_run_prune "Podman unused volumes pruned" podman volume prune -f
                pause
                ;;
            3)
                echo -e "\n${GREEN}--> Removing stopped/inactive containers...${NC}"
                command -v docker &>/dev/null && _vmw_run_prune "Docker stopped containers removed" docker container prune -f
                command -v podman &>/dev/null && _vmw_run_prune "Podman stopped containers removed" podman container prune -f
                pause
                ;;
            4)
                echo -e "\n${GREEN}--> Pruning dangling (untagged) images...${NC}"
                command -v docker &>/dev/null && _vmw_run_prune "Docker dangling images pruned" docker image prune -f
                command -v podman &>/dev/null && _vmw_run_prune "Podman dangling images pruned" podman image prune -f
                pause
                ;;
            5)
                echo -e "\n${RED}${BOLD}This removes ALL unused containers, images, volumes and build caches (Docker and Podman).${NC}"
                echo -e "${RED}Anything not currently referenced by a running container will be deleted.${NC}"
                read -r -p "Type YES to continue (anything else cancels): " FULL_PRUNE_CONFIRM
                if [[ "$FULL_PRUNE_CONFIRM" == "YES" ]]; then
                    echo -e "\n${RED}${BOLD}--> Running FULL Container System Prune...${NC}"
                    command -v docker &>/dev/null && _vmw_run_prune "Docker full system prune complete" docker system prune -a --volumes -f
                    command -v podman &>/dev/null && _vmw_run_prune "Podman full system prune complete" podman system prune -a --volumes -f
                else
                    echo "Cancelled."
                fi
                pause
                ;;
            0)
                break
                ;;
            *)
                echo -e "\n${RED}Invalid selection!${NC}"
                sleep 1
                ;;
        esac
    done
}

clean_system() {
    clear
    show_header
    echo -e "${YELLOW}[+] Cleaning OS Package Manager Caches & System Logs...${NC}\n"
    echo -e "This clears package caches/orphans, vacuums old journal logs, and clears"
    echo -e "temp/thumbnail caches older than 1 day. It does not touch Docker/Podman data."
    read -r -p "Proceed? (y/N): " SYS_CLEAN_CONFIRM
    if [[ ! "$SYS_CLEAN_CONFIRM" =~ ^[Yy]$ ]]; then
        echo "Cancelled."
        pause
        return 0
    fi

    if command -v apt-get &> /dev/null; then
        echo -e "${GREEN}--> Running apt-get clean & autoremove...${NC}"
        _vmw_run_prune "apt cache cleaned" sudo apt-get clean
        _vmw_run_prune "unused apt packages removed" sudo apt-get autoremove -y
    elif command -v dnf &> /dev/null; then
        echo -e "${GREEN}--> Running dnf clean all & autoremove...${NC}"
        _vmw_run_prune "dnf cache cleaned" sudo dnf clean all
        _vmw_run_prune "unused dnf packages removed" sudo dnf autoremove -y
    elif command -v yum &> /dev/null; then
        echo -e "${GREEN}--> Running yum clean all...${NC}"
        _vmw_run_prune "yum cache cleaned" sudo yum clean all
    elif command -v pacman &> /dev/null; then
        echo -e "${GREEN}--> Running pacman cache clean & orphan removal (Arch Linux)...${NC}"
        _vmw_run_prune "pacman cache cleaned" sudo pacman -Sc --noconfirm
        mapfile -t PACMAN_ORPHANS < <(pacman -Qtdq 2>/dev/null)
        if (( ${#PACMAN_ORPHANS[@]} > 0 )); then
            _vmw_run_prune "orphaned pacman packages removed" sudo pacman -Rns --noconfirm "${PACMAN_ORPHANS[@]}"
        fi
    elif command -v zypper &> /dev/null; then
        echo -e "${GREEN}--> Running zypper cache clean (openSUSE)...${NC}"
        _vmw_run_prune "zypper cache cleaned" sudo zypper clean --all
    else
        echo -e "${YELLOW}[!] No supported package manager (apt/dnf/yum/pacman/zypper) detected; skipping package cache cleanup.${NC}"
    fi

    if command -v journalctl &> /dev/null; then
        echo -e "${GREEN}--> Vacuuming systemd journal logs (retaining last 3 days)...${NC}"
        _vmw_run_prune "journal vacuumed" sudo journalctl --vacuum-time=3d
    else
        echo -e "${YELLOW}[!] systemd/journalctl not detected (non-systemd init?); skipping journal vacuum.${NC}"
    fi

    echo -e "${GREEN}--> Cleaning temporary files older than 1 day (leaves active sockets/sessions alone)...${NC}"
    sudo find /tmp -mindepth 1 -mmin +1440 \
        ! -path '/tmp/.X11-unix*' ! -path '/tmp/.ICE-unix*' ! -path '/tmp/.font-unix*' \
        ! -path '/tmp/.XIM-unix*' ! -path '/tmp/systemd-private-*' ! -path '/tmp/snap-private-tmp*' \
        -exec sudo rm -rf {} + 2>/dev/null || true
    rm -rf ~/.cache/thumbnails/* 2>/dev/null || true

    echo -e "\n${GREEN}[✔] OS System Cleanup Complete!${NC}"
    pause
}

prepare_vdi_compact() {
    clear
    show_header
    echo -e "${YELLOW}[+] Preparing System for Host Disk Compaction...${NC}\n"
    echo "This process fills all unused disk blocks with zeros so your host hypervisor"
    echo "can reclaim physical disk space on your Windows PC."
    echo -e "${RED}${BOLD}Note: Disk utilization will reach 100% temporarily during zero-fill.${NC}\n"

    # /tmp is tmpfs (RAM-backed) on many distros, including this one — writing the
    # fill file there would fill RAM/swap and never touch the root disk's free
    # blocks at all. Zero-fill a real on-disk directory instead, and verify it.
    local fill_dir fill_fs fill_file
    fill_dir="/var/tmp"
    [[ -d "$fill_dir" ]] || fill_dir="/"
    fill_fs=$(sudo stat -f -c %T "$fill_dir" 2>/dev/null || echo unknown)
    if [[ "$fill_fs" == "tmpfs" || "$fill_fs" == "ramfs" ]]; then
        fill_dir="/"
        fill_fs=$(sudo stat -f -c %T "$fill_dir" 2>/dev/null || echo unknown)
    fi
    if [[ "$fill_fs" == "tmpfs" || "$fill_fs" == "ramfs" ]]; then
        echo -e "${RED}[!] Both /var/tmp and / resolve to a RAM-backed filesystem ($fill_fs).${NC}"
        echo -e "${RED}    Zero-filling here would fill RAM/swap, not your virtual disk. Aborting.${NC}"
        pause
        return 1
    fi
    fill_file="$fill_dir/.vmwizard-zero.fill"
    echo -e "${CYAN}Zero-fill target: $fill_dir (filesystem: $fill_fs)${NC}"
    df -h "$fill_dir"
    echo ""

    read -r -p "Start Zero-Fill sequence? (y/N): " CONFIRM
    if [[ "$CONFIRM" =~ ^[Yy]$ ]]; then
        if (( ${DRY_RUN:-0} )); then
            echo -e "${CYAN}[dry-run]${NC} would run: dd if=/dev/zero of=$fill_file bs=1M status=progress; rm -f $fill_file; sudo shutdown -h now"
            pause
            return 0
        fi
        echo -e "\n${GREEN}--> Writing zeroes to unused disk blocks on $fill_dir (please wait)...${NC}"
        sudo dd if=/dev/zero of="$fill_file" bs=1M status=progress 2>/dev/null || true
        sudo rm -f "$fill_file"

        echo -e "\n${CYAN}====================================================================${NC}"
        echo -e "${GREEN}${BOLD}     STAGE 1 COMPLETE: LINUX SYSTEM ZERO-FILLED & PREPARED!        ${NC}"
        echo -e "${CYAN}====================================================================${NC}"
        echo -e "To reclaim physical storage on your Windows PC hard drive:\n"
        echo -e "  1. Open ${BOLD}Windows PowerShell${NC} as Administrator (or double-click autorun.bat)."
        echo -e "  2. Run Stage 2 to compact your ${GREEN}${BOLD}VirtualBox (.vdi)${NC} or ${GREEN}${BOLD}VMware (.vmdk)${NC} disks.\n"
        if command -v systemctl &>/dev/null; then
            echo -e "The VM will now gracefully shut down in 10 seconds..."
        else
            echo -e "${YELLOW}No systemd detected; attempting 'shutdown -h now' anyway in 10 seconds...${NC}"
        fi
        echo -e "${CYAN}====================================================================${NC}"

        sleep 10
        sudo shutdown -h now
    else
        echo "Zero-fill aborted."
        pause
    fi
}

# --- Initial One-Time Banner Display ---
show_banner

# --- Main Menu Loop ---
while true; do
    show_header
    echo -e "Please select an action:\n"
    echo -e "  ${GREEN}[1]${NC} Free Up Container Space (Customizable Docker & Podman Prune)"
    echo -e "  ${GREEN}[2]${NC} Free Up OS System Space (Clean Package Caches & Logs)"
    echo -e "  ${GREEN}[3]${NC} Offload Docker & Podman Storage to Secondary HDD Drive"
    echo -e "  ${GREEN}[4]${NC} FULL CLEANUP + Zero-Fill for Host Disk Compaction (Stage 1)"
    echo -e "  ${GREEN}[5]${NC} Audit & Clean Up Leftover Storage After a Migration"
    echo -e "  ${GREEN}[0]${NC} Exit"
    echo -e "\n===================================================================="
    read -r -p "Enter choice [0-5]: " CHOICE

    case $CHOICE in
        1) clean_containers ;;
        2) clean_system ;;
        3) setup_secondary_disk ;;
        4) clean_system; clean_containers; prepare_vdi_compact ;;
        5) docker_storage_audit ;;
        0) echo -e "\n${GREEN}Goodbye!${NC}"; exit 0 ;;
        *) echo -e "\n${RED}Invalid option!${NC}"; sleep 1 ;;
    esac
done