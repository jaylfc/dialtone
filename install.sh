#!/usr/bin/env bash
# ╔══════════════════════════════════════════════════════════════════╗
# ║  Hermes Phone — Installer                                       ║
# ║  Sets up everything: deps, config, LaunchAgents, Twilio         ║
# ╚══════════════════════════════════════════════════════════════════╝
set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

INSTALL_DIR="$HOME/.hermes-phone"
PYTHON="python3"
ENV_FILE="$INSTALL_DIR/.env"

echo ""
echo -e "${CYAN}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║  📞 Hermes Phone — Installer                                ║${NC}"
echo -e "${CYAN}║  AI-powered phone agent for macOS                           ║${NC}"
echo -e "${CYAN}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""

# ── Check requirements ─────────────────────────────────────────────
echo -e "${BLUE}Checking requirements...${NC}"

if [[ "$(uname)" != "Darwin" ]]; then
    echo -e "${RED}❌ macOS required (detected $(uname))${NC}"
    exit 1
fi
echo -e "${GREEN}  ✅ macOS $(sw_vers -productVersion)${NC}"

if ! command -v $PYTHON &>/dev/null; then
    echo -e "${RED}❌ Python 3 not found. Install with: brew install python${NC}"
    exit 1
fi

PY_VERSION=$($PYTHON --version 2>&1 | awk '{print $2}')
PY_MAJOR=$(echo "$PY_VERSION" | cut -d. -f1)
PY_MINOR=$(echo "$PY_VERSION" | cut -d. -f2)
if [[ "$PY_MAJOR" -lt 3 ]] || [[ "$PY_MAJOR" -eq 3 && "$PY_MINOR" -lt 11 ]]; then
    echo -e "${RED}❌ Python 3.11+ required (found $PY_VERSION)${NC}"
    exit 1
fi
echo -e "${GREEN}  ✅ Python $PY_VERSION${NC}"

# Helper to read an existing value from the current .env (used to preserve config)
get_env() {
    local key="$1"
    [[ -f "$ENV_FILE" ]] || { echo ""; return; }
    grep "^${key}=" "$ENV_FILE" 2>/dev/null | head -1 | cut -d= -f2- | sed 's/^"//' | sed 's/"$//'
}

# ── Create install directory ───────────────────────────────────────
echo ""
echo -e "${BLUE}Setting up $INSTALL_DIR...${NC}"
mkdir -p "$INSTALL_DIR/voicemails/audio"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cp "$SCRIPT_DIR/server.py"       "$INSTALL_DIR/"
cp "$SCRIPT_DIR/menubar.py"      "$INSTALL_DIR/"
cp "$SCRIPT_DIR/local_voice.py"  "$INSTALL_DIR/"
cp "$SCRIPT_DIR/requirements.txt" "$INSTALL_DIR/"
cp "$SCRIPT_DIR/.env.example"    "$INSTALL_DIR/" 2>/dev/null || true
echo -e "${GREEN}  ✅ Files copied${NC}"

# ── Install dependencies (in an isolated venv to avoid PEP-668) ─────
echo ""
echo -e "${BLUE}Creating virtual environment + installing dependencies...${NC}"
if [[ ! -d "$INSTALL_DIR/venv" ]]; then
    $PYTHON -m venv "$INSTALL_DIR/venv"
fi
VENV_PY="$INSTALL_DIR/venv/bin/python"
"$VENV_PY" -m pip install --quiet --upgrade pip
"$VENV_PY" -m pip install --quiet -r "$INSTALL_DIR/requirements.txt"
echo -e "${GREEN}  ✅ Dependencies installed into $INSTALL_DIR/venv${NC}"

# ── Setup wizard ───────────────────────────────────────────────────
echo ""
echo -e "${CYAN}═══ Setup Wizard ═══${NC}"
if [[ -f "$ENV_FILE" ]]; then
    echo -e "${YELLOW}Existing config found — press Enter at any prompt to keep the current value.${NC}"
fi
echo ""

# Twilio
echo -e "${BLUE}── Twilio ──${NC}"
echo "Get these from https://console.twilio.com"
echo ""
CUR=$(get_env TWILIO_ACCOUNT_SID);  read -p "Twilio Account SID [${CUR:+keep}]: " TWILIO_SID;     TWILIO_SID="${TWILIO_SID:-$CUR}"
CUR=$(get_env TWILIO_AUTH_TOKEN);   read -p "Twilio Auth Token [${CUR:+keep}]: " TWILIO_TOKEN;    TWILIO_TOKEN="${TWILIO_TOKEN:-$CUR}"
CUR=$(get_env TWILIO_PHONE_NUMBER); read -p "Twilio Phone Number (e.g. +443xxxxxxxxx) [${CUR:+keep}]: " TWILIO_PHONE; TWILIO_PHONE="${TWILIO_PHONE:-$CUR}"

# Deepgram
echo ""
echo -e "${BLUE}── Deepgram (Speech-to-Text) ──${NC}"
echo "Free \$200 credit at https://console.deepgram.com"
echo ""
CUR=$(get_env DEEPGRAM_API_KEY); read -p "Deepgram API Key [${CUR:+keep}]: " DEEPGRAM_KEY; DEEPGRAM_KEY="${DEEPGRAM_KEY:-$CUR}"

# LLM
echo ""
echo -e "${BLUE}── LLM Provider ──${NC}"
echo "Choose your AI provider:"
echo "  1) OpenAI (GPT-4o, GPT-4-mini)"
echo "  2) Xiaomi MiMo (free tier)"
echo "  3) OpenRouter (100+ models)"
echo "  4) Local (Ollama)"
echo "  5) Other (OpenAI-compatible)"
echo "  6) Keep existing"
echo ""
read -p "Choice [1-6]: " LLM_CHOICE

# Defaults preserved from existing config
LLM_PROVIDER=$(get_env LLM_PROVIDER); LLM_PROVIDER="${LLM_PROVIDER:-openai}"
LLM_MODEL=$(get_env LLM_MODEL)
LLM_KEY=$(get_env OPENAI_API_KEY)
LLM_BASE_URL=$(get_env OPENAI_BASE_URL)

case $LLM_CHOICE in
    1)
        read -p "OpenAI API Key: " LLM_KEY
        LLM_BASE_URL="https://api.openai.com/v1"; LLM_PROVIDER="openai"
        read -p "Model [gpt-4o-mini]: " LLM_MODEL; LLM_MODEL="${LLM_MODEL:-gpt-4o-mini}"
        ;;
    2)
        read -p "Xiaomi API Key: " LLM_KEY
        LLM_BASE_URL="https://token-plan-ams.xiaomimimo.com/v1"; LLM_PROVIDER="xiaomi"; LLM_MODEL="mimo-v2.5"
        ;;
    3)
        read -p "OpenRouter API Key: " LLM_KEY
        LLM_BASE_URL="https://openrouter.ai/api/v1"; LLM_PROVIDER="openrouter"
        read -p "Model [anthropic/claude-sonnet-4]: " LLM_MODEL; LLM_MODEL="${LLM_MODEL:-anthropic/claude-sonnet-4}"
        ;;
    4)
        LLM_KEY="ollama"; LLM_BASE_URL="http://localhost:11434/v1"; LLM_PROVIDER="openai"
        read -p "Model [llama3]: " LLM_MODEL; LLM_MODEL="${LLM_MODEL:-llama3}"
        ;;
    5)
        read -p "API Key: " LLM_KEY
        read -p "Base URL: " LLM_BASE_URL
        LLM_PROVIDER="openai"
        read -p "Model: " LLM_MODEL
        ;;
    *)
        echo -e "${CYAN}  ℹ️ Keeping existing LLM config (${LLM_PROVIDER}/${LLM_MODEL:-unset})${NC}"
        ;;
esac
LLM_MODEL="${LLM_MODEL:-gpt-4o-mini}"
LLM_BASE_URL="${LLM_BASE_URL:-https://api.openai.com/v1}"

# Phone settings
echo ""
echo -e "${BLUE}── Phone Settings ──${NC}"
CUR=$(get_env COMPANY_NAME);     read -p "Company Name [${CUR:-My Company}]: " COMPANY_NAME;   COMPANY_NAME="${COMPANY_NAME:-${CUR:-My Company}}"
CUR=$(get_env VOICEMAIL_EMAIL);  read -p "Voicemail Email [${CUR:+keep}]: " VOICEMAIL_EMAIL;  VOICEMAIL_EMAIL="${VOICEMAIL_EMAIL:-$CUR}"
CUR=$(get_env VOICEMAIL_PIN);    read -p "Voicemail PIN [${CUR:-1234}]: " VOICEMAIL_PIN;       VOICEMAIL_PIN="${VOICEMAIL_PIN:-${CUR:-1234}}"

# Telegram (optional)
echo ""
echo -e "${BLUE}── Telegram Notifications (optional) ──${NC}"
echo "Get a bot token from @BotFather on Telegram"
CUR=$(get_env TELEGRAM_BOT_TOKEN); read -p "Telegram Bot Token (Enter to skip/keep) [${CUR:+keep}]: " TELEGRAM_TOKEN; TELEGRAM_TOKEN="${TELEGRAM_TOKEN:-$CUR}"
CUR=$(get_env TELEGRAM_CHAT_ID)
if [[ -n "$TELEGRAM_TOKEN" ]]; then
    read -p "Telegram Chat ID [${CUR:+keep}]: " TELEGRAM_CHAT_ID; TELEGRAM_CHAT_ID="${TELEGRAM_CHAT_ID:-$CUR}"
fi

# ── Preserve settings not asked about in the wizard ────────────────
VOICEMAIL_MAX_LENGTH=$(get_env VOICEMAIL_MAX_LENGTH); VOICEMAIL_MAX_LENGTH="${VOICEMAIL_MAX_LENGTH:-120}"
VOICEMAIL_GREETING=$(get_env VOICEMAIL_GREETING)
CALL_GOAL=$(get_env CALL_GOAL); CALL_GOAL="${CALL_GOAL:-Have a helpful conversation.}"
CALL_SYSTEM_PROMPT=$(get_env CALL_SYSTEM_PROMPT)
TTS_VOICE=$(get_env TTS_VOICE); TTS_VOICE="${TTS_VOICE:-Polly.Amy}"
TTS_LANGUAGE=$(get_env TTS_LANGUAGE); TTS_LANGUAGE="${TTS_LANGUAGE:-en-GB}"
USE_LOCAL_VOICE=$(get_env USE_LOCAL_VOICE); USE_LOCAL_VOICE="${USE_LOCAL_VOICE:-auto}"
PUBLIC_URL=$(get_env PUBLIC_URL)

# API token: preserve if present, otherwise generate one for safe remote access
HERMES_API_TOKEN=$(get_env HERMES_API_TOKEN)
if [[ -z "$HERMES_API_TOKEN" ]]; then
    HERMES_API_TOKEN=$($PYTHON -c "import secrets; print(secrets.token_urlsafe(32))")
fi

# ── Write .env ─────────────────────────────────────────────────────
echo ""
echo -e "${BLUE}Writing configuration...${NC}"

cat > "$ENV_FILE" << EOF
# Hermes Phone — Configuration
# Generated by installer on $(date)

# Twilio
TWILIO_ACCOUNT_SID=$TWILIO_SID
TWILIO_AUTH_TOKEN=$TWILIO_TOKEN
TWILIO_PHONE_NUMBER=$TWILIO_PHONE

# Deepgram (STT)
DEEPGRAM_API_KEY=$DEEPGRAM_KEY

# LLM
LLM_PROVIDER=$LLM_PROVIDER
LLM_MODEL=$LLM_MODEL
OPENAI_API_KEY=$LLM_KEY
OPENAI_BASE_URL=$LLM_BASE_URL

# Phone Agent
VOICEMAIL_PIN=$VOICEMAIL_PIN
COMPANY_NAME=$COMPANY_NAME
VOICEMAIL_EMAIL=$VOICEMAIL_EMAIL
VOICEMAIL_MAX_LENGTH=$VOICEMAIL_MAX_LENGTH
VOICEMAIL_GREETING=$VOICEMAIL_GREETING

# Voice
TTS_VOICE=$TTS_VOICE
TTS_LANGUAGE=$TTS_LANGUAGE
USE_LOCAL_VOICE=$USE_LOCAL_VOICE

# Call Settings
CALL_GOAL=$CALL_GOAL
CALL_SYSTEM_PROMPT=$CALL_SYSTEM_PROMPT

# Telegram (optional)
TELEGRAM_BOT_TOKEN=${TELEGRAM_TOKEN:-}
TELEGRAM_CHAT_ID=${TELEGRAM_CHAT_ID:-}

# Security / networking
# HERMES_API_TOKEN protects the dashboard/API for remote access (localhost is always trusted).
HERMES_API_TOKEN=$HERMES_API_TOKEN
# PUBLIC_URL: set to your public https origin (e.g. https://abc.ngrok.app) so Twilio
# webhooks validate and Media Streams (wss) work. Leave blank when only using voicemail.
PUBLIC_URL=$PUBLIC_URL
EOF

chmod 600 "$ENV_FILE"
echo -e "${GREEN}  ✅ Configuration saved to $ENV_FILE (chmod 600)${NC}"

# ── Configure Twilio webhook ───────────────────────────────────────
echo ""
echo -e "${BLUE}── Network Setup ──${NC}"
echo "How will Twilio reach your Mac? (AI calls require HTTPS/WSS — use a TLS tunnel.)"
echo "  1) ngrok (recommended — provides HTTPS, required for AI calls)"
echo "  2) Static IP / domain with TLS in front (advanced)"
echo "  3) Manual (I'll configure later)"
echo ""
read -p "Choice [1-3]: " NET_CHOICE

WEBHOOK_URL=""
case $NET_CHOICE in
    1)
        if ! command -v ngrok &>/dev/null; then
            echo -e "${YELLOW}Installing ngrok...${NC}"
            brew install ngrok 2>/dev/null || echo -e "${RED}Install ngrok manually: brew install ngrok${NC}"
        fi
        if command -v ngrok &>/dev/null; then
            read -p "ngrok authtoken: " NGROK_TOKEN
            [[ -n "$NGROK_TOKEN" ]] && ngrok config add-authtoken "$NGROK_TOKEN" 2>/dev/null
            echo -e "${GREEN}  ✅ ngrok configured${NC}"
            echo -e "${YELLOW}Start ngrok:  ngrok http 5050${NC}"
            echo -e "${YELLOW}Then set PUBLIC_URL in $ENV_FILE to the https URL and point the${NC}"
            echo -e "${YELLOW}Twilio Voice webhook to <PUBLIC_URL>/voice/incoming${NC}"
        fi
        ;;
    2)
        read -p "Your public https URL (e.g. https://phone.example.com): " STATIC_URL
        if [[ -n "$STATIC_URL" ]]; then
            WEBHOOK_URL="${STATIC_URL%/}/voice/incoming"
            # persist PUBLIC_URL
            if grep -q '^PUBLIC_URL=' "$ENV_FILE"; then
                sed -i '' "s#^PUBLIC_URL=.*#PUBLIC_URL=${STATIC_URL%/}#" "$ENV_FILE"
            fi
            echo -e "${YELLOW}Ensure TLS terminates in front of port 5050 (Media Streams need wss).${NC}"
        fi
        ;;
    *)
        echo -e "${CYAN}  ℹ️ Configure the Twilio webhook later.${NC}"
        ;;
esac

if [[ -n "$WEBHOOK_URL" && -n "$TWILIO_SID" && -n "$TWILIO_TOKEN" ]]; then
    echo ""
    echo -e "${BLUE}Configuring Twilio webhook...${NC}"
    PN_SID=$(curl -s "https://api.twilio.com/2010-04-01/Accounts/$TWILIO_SID/IncomingPhoneNumbers.json" \
        -u "$TWILIO_SID:$TWILIO_TOKEN" | \
        $PYTHON -c "import json,sys; d=json.load(sys.stdin); print(d['incoming_phone_numbers'][0]['sid'])" 2>/dev/null)
    if [[ -n "$PN_SID" ]]; then
        curl -s -X POST "https://api.twilio.com/2010-04-01/Accounts/$TWILIO_SID/IncomingPhoneNumbers/$PN_SID.json" \
            -u "$TWILIO_SID:$TWILIO_TOKEN" \
            --data-urlencode "VoiceUrl=$WEBHOOK_URL" \
            --data-urlencode "VoiceMethod=POST" > /dev/null
        echo -e "${GREEN}  ✅ Twilio webhook → $WEBHOOK_URL${NC}"
    else
        echo -e "${RED}  ❌ Could not find phone number. Set webhook manually.${NC}"
    fi
fi

# ── Install LaunchAgents ───────────────────────────────────────────
echo ""
echo -e "${BLUE}Installing macOS services...${NC}"

# Server LaunchAgent (runs from the venv)
cat > "$HOME/Library/LaunchAgents/com.hermes-phone.server.plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.hermes-phone.server</string>
    <key>ProgramArguments</key>
    <array>
        <string>$VENV_PY</string>
        <string>$INSTALL_DIR/server.py</string>
    </array>
    <key>WorkingDirectory</key>
    <string>$INSTALL_DIR</string>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <dict>
        <key>SuccessfulExit</key>
        <false/>
    </dict>
    <key>StandardOutPath</key>
    <string>$INSTALL_DIR/server.log</string>
    <key>StandardErrorPath</key>
    <string>$INSTALL_DIR/server.log</string>
    <key>ThrottleInterval</key>
    <integer>10</integer>
</dict>
</plist>
EOF

# Menu bar LaunchAgent (runs from the venv)
cat > "$HOME/Library/LaunchAgents/com.hermes-phone.menubar.plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.hermes-phone.menubar</string>
    <key>ProgramArguments</key>
    <array>
        <string>$VENV_PY</string>
        <string>$INSTALL_DIR/menubar.py</string>
    </array>
    <key>WorkingDirectory</key>
    <string>$INSTALL_DIR</string>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <false/>
    <key>ProcessType</key>
    <string>Interactive</string>
</dict>
</plist>
EOF

echo -e "${GREEN}  ✅ LaunchAgents installed${NC}"

# ── Start services ─────────────────────────────────────────────────
echo ""
echo -e "${BLUE}Starting services...${NC}"

launchctl unload "$HOME/Library/LaunchAgents/com.hermes-phone.server.plist" 2>/dev/null || true
launchctl load -w "$HOME/Library/LaunchAgents/com.hermes-phone.server.plist"
sleep 3

if curl -s http://localhost:5050/health > /dev/null 2>&1; then
    echo -e "${GREEN}  ✅ Server running on port 5050${NC}"
else
    echo -e "${YELLOW}  ⚠️ Server starting... (check $INSTALL_DIR/server.log)${NC}"
fi

launchctl unload "$HOME/Library/LaunchAgents/com.hermes-phone.menubar.plist" 2>/dev/null || true
launchctl load -w "$HOME/Library/LaunchAgents/com.hermes-phone.menubar.plist"
echo -e "${GREEN}  ✅ Menu bar app started (look for 📞 in your menu bar)${NC}"

# ── Done! ──────────────────────────────────────────────────────────
echo ""
echo -e "${CYAN}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║  📞 Hermes Phone — Installed!                               ║${NC}"
echo -e "${CYAN}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "  ${GREEN}Server:${NC}    http://localhost:5050  (dashboard — localhost is trusted)"
echo -e "  ${GREEN}Config:${NC}    $ENV_FILE"
echo -e "  ${GREEN}Logs:${NC}      $INSTALL_DIR/server.log"
echo -e "  ${GREEN}Voicemails:${NC} $INSTALL_DIR/voicemails/"
echo ""
echo -e "  ${CYAN}Remote dashboard access (over a tunnel):${NC}"
echo -e "    Open <PUBLIC_URL>/ and sign in with the token in:"
echo -e "    $INSTALL_DIR/.env → HERMES_API_TOKEN"
echo ""
echo -e "  ${YELLOW}AI calls need HTTPS/WSS — start a tunnel (ngrok http 5050) and set PUBLIC_URL.${NC}"
echo -e "  ${YELLOW}Call ${TWILIO_PHONE} to test voicemail.${NC}"
echo ""
echo -e "  Manage services:"
echo -e "    launchctl stop com.hermes-phone.server"
echo -e "    launchctl start com.hermes-phone.server"
echo ""
