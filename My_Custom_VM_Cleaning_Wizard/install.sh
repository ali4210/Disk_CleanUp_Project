#!/usr/bin/env bash
# ==============================================================================
# INSTALLER: Global CLI Registrar for VM Space Wizard
# BINARY NAME: clean-wizard
# ==============================================================================

set -e

GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

REPO_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
TARGET_SCRIPT="$REPO_DIR/linux/vm-space-wizard.sh"
GLOBAL_BIN="/usr/local/bin/clean-wizard"

echo -e "${CYAN}--> Registering 'clean-wizard' as a global system command...${NC}"

if [[ ! -f "$TARGET_SCRIPT" ]]; then
    echo -e "${RED}[!] Error: Could not find $TARGET_SCRIPT${NC}"
    exit 1
fi

# 1. Ensure execution permissions
chmod +x "$TARGET_SCRIPT"
chmod +x "$REPO_DIR/autorun.sh" 2>/dev/null || true

# 2. Create system symlink in /usr/local/bin
if [ -w "/usr/local/bin" ]; then
    ln -sf "$TARGET_SCRIPT" "$GLOBAL_BIN"
else
    echo -e "${YELLOW}--> Superuser privileges required to install to /usr/local/bin...${NC}"
    sudo ln -sf "$TARGET_SCRIPT" "$GLOBAL_BIN"
fi

echo -e "${GREEN}[✔] SUCCESS: 'clean-wizard' is now installed globally!${NC}"
echo -e "${CYAN}You can now open any terminal window and type: ${YELLOW}clean-wizard${NC}\n"
