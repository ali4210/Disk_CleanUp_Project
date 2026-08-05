#!/usr/bin/env bash
# ==============================================================================
# TOOL NAME:    autorun.sh (Automated Linux Master Launcher)
# AUTHOR:       Saleem Ali (Open Source Contributor)
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# --- AUTOMATED PERMISSION MANAGEMENT ---
# Automatically make all scripts in the directory executable
chmod +x "$SCRIPT_DIR"/*.sh 2>/dev/null || true

# --- AUTOMATED SUDO CHECK ---
# Check if sudo access is available for system tasks
if [ "$EUID" -ne 0 ]; then
    echo "===================================================================="
    echo " [!] Elevated privileges are required for system cleanup & mounting."
    echo "===================================================================="
    # Prompt for sudo early so the user isn't interrupted mid-execution
    sudo -v
fi

clear
echo "===================================================================="
echo "         🧙‍♂️ VM SPACE WIZARD - MASTER LAUNCHER (LINUX)"
echo "===================================================================="
echo ""
echo "Which stage of the cleanup process are you currently executing?"
echo ""
echo "  [1] Stage 1: Linux System Cleanup & Storage Offloading (RUN HERE)"
echo "  [2] Stage 2: Windows Host VDI Compaction (REQUIRES WINDOWS POWERSHELL)"
echo "  [3] Exit"
echo "===================================================================="
read -p "Select option [1-3]: " CHOICE

case $CHOICE in
    1)
        "$SCRIPT_DIR/vm-space-wizard.sh"
        ;;
    2)
        echo ""
        echo "===================================================================="
        echo " [!] NOTICE: STAGE 2 MUST BE EXECUTED ON YOUR WINDOWS HOST PC"
        echo "===================================================================="
        echo " You are currently inside the Linux Virtual Machine."
        echo " To compact the physical .vdi file on your Windows host drive:"
        echo ""
        echo "   1. Complete Stage 1 and shut down this Virtual Machine."
        echo "   2. Double-click 'autorun.bat' on your Windows Host PC."
        echo "===================================================================="
        read -p "Press [ENTER] to exit..."
        ;;
    3)
        echo "Exiting..."
        exit 0
        ;;
    *)
        echo "Invalid selection!"
        exit 1
        ;;
esac
