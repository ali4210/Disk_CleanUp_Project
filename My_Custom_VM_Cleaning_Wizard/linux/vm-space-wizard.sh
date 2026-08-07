#!/usr/bin/env bash
# ==============================================================================
# TOOL NAME:    vm-space-wizard.sh (V2.0 Universal Release)
# AUTHOR:       Saleem (Open Source DevOps/Sec Contributor)
# DESCRIPTION:  Universal Linux VM space optimization & disk offloading wizard.
# COMPATIBILITY: Debian, Ubuntu, Kali Linux, CentOS, RHEL, Fedora, Rocky Linux
# HYPERVISORS:   Oracle VirtualBox & VMware Workstation / Player / Fusion
# ==============================================================================

set -e

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
TARGET_REPO_DIR="$( cd -P "$( dirname "$SCRIPT_SOURCE" )/.." >/dev/null 2>&1 && pwd )"


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
    read -p "Press [ENTER] to return to the menu..."
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
    echo -e "  ${GREEN}[3]${NC} Skip Guidelines"
    read -p "Select choice [1-3]: " GUIDE_CHOICE

    case $GUIDE_CHOICE in
        1) show_virtualbox_instructions ;;
        2) show_vmware_instructions ;;
        *) echo "Skipping guidelines..." ;;
    esac
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
        echo -e "  ${GREEN}[6]${NC} Return to Main Menu"
        echo -e "\n===================================================================="
        read -p "Select prune option [1-6]: " PRUNE_CHOICE

        case $PRUNE_CHOICE in
            1)
                echo -e "\n${GREEN}--> Cleaning Docker & Podman build caches...${NC}"
                command -v docker &>/dev/null && docker builder prune -f
                command -v podman &>/dev/null && podman builder prune -f || true
                pause
                ;;
            2)
                echo -e "\n${GREEN}--> Cleaning unused persistent volumes...${NC}"
                command -v docker &>/dev/null && docker volume prune -f
                command -v podman &>/dev/null && podman volume prune -f || true
                pause
                ;;
            3)
                echo -e "\n${GREEN}--> Removing stopped/inactive containers...${NC}"
                command -v docker &>/dev/null && docker container prune -f
                command -v podman &>/dev/null && podman container prune -f || true
                pause
                ;;
            4)
                echo -e "\n${GREEN}--> Pruning dangling (untagged) images...${NC}"
                command -v docker &>/dev/null && docker image prune -f
                command -v podman &>/dev/null && podman image prune -f || true
                pause
                ;;
            5)
                echo -e "\n${RED}${BOLD}--> Running FULL Container System Prune...${NC}"
                command -v docker &>/dev/null && docker system prune -a --volumes -f
                command -v podman &>/dev/null && podman system prune -a --volumes -f || true
                pause
                ;;
            6)
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

    if command -v apt-get &> /dev/null; then
        echo -e "${GREEN}--> Running apt-get clean & autoremove...${NC}"
        sudo apt-get clean && sudo apt-get autoremove -y
    elif command -v dnf &> /dev/null; then
        echo -e "${GREEN}--> Running dnf clean all & autoremove...${NC}"
        sudo dnf clean all && sudo dnf autoremove -y
    elif command -v yum &> /dev/null; then
        echo -e "${GREEN}--> Running yum clean all...${NC}"
        sudo yum clean all
    fi

    echo -e "${GREEN}--> Vacuuming systemd journal logs (retaining last 3 days)...${NC}"
    sudo journalctl --vacuum-time=3d 2>/dev/null || true

    echo -e "${GREEN}--> Cleaning temporary runtime files and thumbnail caches...${NC}"
    sudo rm -rf /tmp/* 2>/dev/null || true
    rm -rf ~/.cache/thumbnails/* 2>/dev/null || true

    echo -e "\n${GREEN}[✔] OS System Cleanup Complete!${NC}"
    pause
}

setup_secondary_disk() {
    clear
    show_header
    echo -e "${YELLOW}[+] Secondary Storage Partitioning & Data Offload Wizard${NC}"
    echo -e "This module mounts an attached secondary disk and offloads Docker & Podman storage.\n"

    echo -e "${CYAN}--- Currently Detected Block Devices ---${NC}"
    lsblk -o NAME,SIZE,FSTYPE,MOUNTPOINTS
    echo "----------------------------------------------------"

    echo ""
    read -p "Enter target block device for heavy storage (e.g., /dev/sdb): " TARGET_DISK

    if [[ -z "$TARGET_DISK" ]] || [[ ! -b "$TARGET_DISK" ]]; then
        echo -e "\n${RED}[!] Error: No valid block device specified!${NC}"
        show_attachment_guidelines
        pause
        return
    fi

    ROOT_DISK=$(lsblk -no pkname $(findmnt -n -o SOURCE /))
    TARGET_NAME=$(basename "$TARGET_DISK")
    if [[ "$TARGET_NAME" == "$ROOT_DISK" ]]; then
        echo -e "\n${RED}${BOLD}[CRITICAL SAFETY BLOCK] You selected '$TARGET_DISK' which contains your active Linux Root OS!${NC}"
        echo -e "${RED}Modifying this drive would destroy your operating system.${NC}"
        pause
        return
    fi

    FS_TYPE=$(lsblk -no FSTYPE "$TARGET_DISK" | tr -d ' ')

    if [[ -z "$FS_TYPE" ]]; then
        echo -e "\n${YELLOW}[!] Drive '$TARGET_DISK' is unformatted.${NC}"
        read -p "Would you like to format '$TARGET_DISK' with ext4 now? (y/N): " CONFIRM_FMT
        if [[ "$CONFIRM_FMT" =~ ^[Yy]$ ]]; then
            echo -e "${GREEN}--> Formatting $TARGET_DISK with ext4 filesystem...${NC}"
            sudo mkfs.ext4 -F "$TARGET_DISK"
        else
            echo "Format cancelled. Cannot proceed without a formatted filesystem."
            pause
            return
        fi
    else
        echo -e "\n${GREEN}[✔] Existing filesystem ($FS_TYPE) detected on $TARGET_DISK. Preserving data!${NC}"
    fi

    echo -e "${GREEN}--> Stopping container services...${NC}"
    sudo systemctl stop docker 2>/dev/null || true

    echo -e "${GREEN}--> Creating mount point at /var/lib/docker...${NC}"
    sudo mkdir -p /var/lib/docker

    IS_MOUNTED=$(findmnt -n -o TARGET "$TARGET_DISK" || true)
    if [[ "$IS_MOUNTED" != "/var/lib/docker" ]]; then
        echo -e "${GREEN}--> Mounting $TARGET_DISK to /var/lib/docker...${NC}"
        sudo mount "$TARGET_DISK" /var/lib/docker
    fi

    echo -e "${GREEN}--> Updating /etc/fstab for persistent mount...${NC}"
    UUID=$(sudo blkid -s UUID -o value "$TARGET_DISK")
    
    if ! grep -q "$UUID" /etc/fstab; then
        echo "UUID=$UUID  /var/lib/docker  ext4  defaults  0  2" | sudo tee -a /etc/fstab
    fi

    sudo systemctl daemon-reload

    if command -v podman &> /dev/null; then
        echo -e "${GREEN}--> Configuring Podman storage path to secondary disk...${NC}"
        sudo mkdir -p /var/lib/docker/podman-storage
        sudo chmod 757 /var/lib/docker
        sudo chown -R $USER:$USER /var/lib/docker/podman-storage
        sudo chmod -R 777 /var/lib/docker/podman-storage

        mkdir -p ~/.config/containers
        cat <<EOF > ~/.config/containers/storage.conf
[storage]
driver = "overlay"
graphroot = "/var/lib/docker/podman-storage"
EOF
    fi

    sudo systemctl start docker 2>/dev/null || true
    echo -e "\n${GREEN}[✔] SUCCESS: Docker and Podman are now fully connected to $TARGET_DISK!${NC}"
    pause
}

prepare_vdi_compact() {
    clear
    show_header
    echo -e "${YELLOW}[+] Preparing System for Host Disk Compaction...${NC}\n"
    echo "This process fills all unused disk blocks with zeros so your host hypervisor"
    echo "can reclaim physical disk space on your Windows PC."
    echo -e "${RED}${BOLD}Note: Disk utilization will reach 100% temporarily during zero-fill.${NC}\n"

    read -p "Start Zero-Fill sequence? (y/N): " CONFIRM
    if [[ "$CONFIRM" =~ ^[Yy]$ ]]; then
        echo -e "\n${GREEN}--> Writing zeroes to unused disk blocks (please wait)...${NC}"
        dd if=/dev/zero of=/tmp/zero.fill bs=1M status=progress 2>/dev/null || true
        rm -f /tmp/zero.fill

        echo -e "\n${CYAN}====================================================================${NC}"
        echo -e "${GREEN}${BOLD}     STAGE 1 COMPLETE: LINUX SYSTEM ZERO-FILLED & PREPARED!        ${NC}"
        echo -e "${CYAN}====================================================================${NC}"
        echo -e "To reclaim physical storage on your Windows PC hard drive:\n"
        echo -e "  1. Open ${BOLD}Windows PowerShell${NC} as Administrator (or double-click autorun.bat)."
        echo -e "  2. Run Stage 2 to compact your ${GREEN}${BOLD}VirtualBox (.vdi)${NC} or ${GREEN}${BOLD}VMware (.vmdk)${NC} disks.\n"
        echo -e "The VM will now gracefully shut down in 10 seconds..."
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
    echo -e "  ${GREEN}[5]${NC} Exit"
    echo -e "\n===================================================================="
    read -p "Enter choice [1-5]: " CHOICE

    case $CHOICE in
        1) clean_containers ;;
        2) clean_system ;;
        3) setup_secondary_disk ;;
        4) clean_system; clean_containers; prepare_vdi_compact ;;
        5) echo -e "\n${GREEN}Goodbye!${NC}"; exit 0 ;;
        *) echo -e "\n${RED}Invalid option!${NC}"; sleep 1 ;;
    esac
done