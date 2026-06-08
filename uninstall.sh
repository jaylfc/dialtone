#!/usr/bin/env bash
# ╔══════════════════════════════════════════════════════════════════╗
# ║  Hermes Phone — Uninstaller                                     ║
# ╚══════════════════════════════════════════════════════════════════╝
set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

INSTALL_DIR="$HOME/.hermes-phone"

echo ""
echo -e "${CYAN}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║  📞 Hermes Phone — Uninstaller                              ║${NC}"
echo -e "${CYAN}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""

# ── Stop services ──────────────────────────────────────────────────
echo -e "${YELLOW}Stopping services...${NC}"

launchctl unload "$HOME/Library/LaunchAgents/com.hermes-phone.server.plist" 2>/dev/null && \
    echo -e "${GREEN}  ✅ Server stopped${NC}" || echo -e "  ⚠️ Server was not running"

launchctl unload "$HOME/Library/LaunchAgents/com.hermes-phone.menubar.plist" 2>/dev/null && \
    echo -e "${GREEN}  ✅ Menu bar app stopped${NC}" || echo -e "  ⚠️ Menu bar app was not running"

# ── Remove LaunchAgents ────────────────────────────────────────────
echo ""
echo -e "${YELLOW}Removing LaunchAgents...${NC}"

rm -f "$HOME/Library/LaunchAgents/com.hermes-phone.server.plist"
rm -f "$HOME/Library/LaunchAgents/com.hermes-phone.menubar.plist"
echo -e "${GREEN}  ✅ LaunchAgents removed${NC}"

# ── Ask about data ─────────────────────────────────────────────────
echo ""
echo -e "${YELLOW}Data directory: $INSTALL_DIR${NC}"
echo ""
read -p "Remove voicemails and config? (y/N): " REMOVE_DATA

if [[ "$REMOVE_DATA" =~ ^[Yy]$ ]]; then
    rm -rf "$INSTALL_DIR"
    echo -e "${GREEN}  ✅ All data removed${NC}"
else
    echo -e "${CYAN}  ℹ️ Data preserved at $INSTALL_DIR${NC}"
    echo -e "${CYAN}  ℹ️ Config: $INSTALL_DIR/.env${NC}"
    echo -e "${CYAN}  ℹ️ Voicemails: $INSTALL_DIR/voicemails/${NC}"
fi

# ── Done ───────────────────────────────────────────────────────────
echo ""
echo -e "${GREEN}✅ Hermes Phone uninstalled${NC}"
echo ""
echo -e "To reinstall: git clone https://github.com/jaylfc/dialtone && cd dialtone && ./install.sh"
echo ""
