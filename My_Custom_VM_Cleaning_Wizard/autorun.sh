#!/usr/bin/env bash
# ==============================================================================
# TOOL NAME:    autorun.sh (V2.1 Universal Master)
# AUTHOR:       Saleem (Open Source DevOps/Sec Contributor)
# DESCRIPTION:  Master cross-platform entry point for VM maintenance suite.
# ==============================================================================

set -e

# --- Terminal Color Formats ---
GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Look for Linux Wizard in new modular path
TARGET_SCRIPT="${SCRIPT_DIR}/linux/vm-space-wizard.sh"

show_header() {
    clear
    echo -e "${CYAN}${BOLD}====================================================================${NC}"
    echo -e "${CYAN}${BOLD}          🧙‍♂️ VM SPACE WIZARD - UNIVERSAL MASTER (LINUX)           ${NC}"
    echo -e "${CYAN}${BOLD}====================================================================${NC}"
    echo ""
}

show_launch_local() {
    if [[ -f "$TARGET_SCRIPT" ]]; then
        # Handle modular path
        chmod +x "$TARGET_SCRIPT"
        echo -e "${GREEN}--> Launching Stage 1 Linux Engine...${NC}\n"
        sleep 1
        exec "$TARGET_SCRIPT"
    elif [[ -f "${SCRIPT_DIR}/vm-space-wizard.sh" ]]; then
        # Handle legacy root path (for backward compatibility during migration)
        chmod +x "${SCRIPT_DIR}/vm-space-wizard.sh"
        echo -e "${GREEN}--> Launching Stage 1 Linux Engine (Legacy Path)...${NC}\n"
        sleep 1
        exec "${SCRIPT_DIR}/vm-space-wizard.sh"
    else
        show_header
        echo -e "${YELLOW}[!] Error: Could not locate 'vm-space-wizard.sh'!${NC}"
        echo -e "${YELLOW}[!] It is expected at ${TARGET_SCRIPT}.${NC}"
        echo -e "${YELLOW}[!] Verify you cloned the complete modular repository structure.${NC}"
        exit 1
    fi
}

show_windows_guide() {
    show_header
    echo -e "${YELLOW}${BOLD}📌 HOW TO RECLAIM DISK SPACE ON YOUR WINDOWS HOST (STAGE 2)${NC}"
    echo -e "${CYAN}====================================================================${NC}"
    echo -e " If you are running this inside a Linux VM but your VM disks are hosted"
    echo -e " on a Windows PC (VirtualBox or VMware), you must run Stage 2 from Windows."
    echo ""
    echo -e " To get full results, you MUST complete Stage 1 (Cleanup & Zero-Fill)"
    echo -e " inside this Linux VM first using Option [1] on this menu."
    echo ""
    echo -e " Once Stage 1 finishes and this VM shuts down:\n"
    echo -e "  1. On your Windows PC, navigate to your cloned repository folder."
    echo -e "  2. **Double-click autorun.bat** (Master Launcher for Windows)."
    echo -e "  3. Select **Stage 2** to run the VDI/VMDK compaction wizard.\n"
    echo -e "${CYAN}====================================================================${NC}"
    echo -e "${GREEN}[✔] Stage 1 (Cleanup) must happen here first!${NC}"
    read -p "Press [ENTER] to return to the menu..."
}

# --- Universal Context Switch Menu ---
while true; do
    show_header
    echo -e "Select your execution context:\n"
    echo -e "  ${GREEN}[1]${NC} Running inside LINUX GUEST (Perform Stage 1 Cleanup/Zero-Fill)"
    echo -e "  ${GREEN}[2]${NC} Intend to run on WINDOWS HOST (Guidelines for Stage 2 Compaction)"
    echo -e "  ${GREEN}[3]${NC} Exit"
    echo -e "\n===================================================================="
    read -p "Enter choice [1-3]: " CHOICE

    case $CHOICE in
        1) show_launch_local ;;
        2) show_windows_guide ;;
        3) echo -e "\n${GREEN}Goodbye!${NC}"; exit 0 ;;
        *) echo -e "\n${RED}Invalid option!${NC}"; sleep 1 ;;
    esac
done
