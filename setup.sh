#!/bin/bash
set -e

# ─── Alita Setup ─────────────────────────────────────────────────────────────
# One script. Pull and run. Everything else is automatic.
#
# Usage:
#   git clone https://github.com/openagentmarket/AlitaAgent.git
#   cd AlitaAgent
#   ./setup.sh
# ─────────────────────────────────────────────────────────────────────────────

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
OPENCLAW_DIR="$HOME/.openclaw"
WORKSPACE_DIR="$OPENCLAW_DIR/workspace"

echo ""
echo "═══════════════════════════════════════════════════════"
echo "  🤖 Alita Setup"
echo "═══════════════════════════════════════════════════════"
echo ""

# ─── 1. Install Homebrew if missing ─────────────────────────────────────────
if ! command -v brew &> /dev/null; then
    echo "📦 Installing Homebrew..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    if [ -f /opt/homebrew/bin/brew ]; then
        eval "$(/opt/homebrew/bin/brew shellenv)"
        echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> ~/.zprofile
    fi
fi
echo "✅ Homebrew"

# ─── 2. Install Node.js if missing ──────────────────────────────────────────
if ! command -v node &> /dev/null; then
    echo "📦 Installing Node.js..."
    brew install node
fi
echo "✅ Node.js $(node --version)"

# ─── 3. Install OpenClaw if missing ─────────────────────────────────────────
if ! command -v openclaw &> /dev/null; then
    echo "📦 Installing OpenClaw..."
    npm install -g openclaw@latest
fi
echo "✅ OpenClaw $(openclaw --version 2>/dev/null | head -1)"

# ─── 4. Run OpenClaw onboard if not configured ──────────────────────────────
if [ ! -f "$OPENCLAW_DIR/openclaw.json" ]; then
    echo ""
    echo "🔧 OpenClaw not configured yet. Running onboard wizard..."
    echo "   Follow the prompts to set up your AI provider and Telegram."
    echo ""
    openclaw onboard --install-daemon
    echo ""
fi
echo "✅ OpenClaw configured"

# ─── 5. Install skill dependencies ──────────────────────────────────────────
echo ""
echo "📦 Installing skill dependencies..."
cd "$REPO_DIR/workspace/skills/openagent-market/scripts"
npm install --silent 2>&1 | tail -3
echo "✅ openagent-market skill ready"

# ─── 6. Generate or reuse mnemonic ──────────────────────────────────────────
echo ""
MNEMONIC=""
EXISTING=$(node --input-type=module -e "
import fs from 'fs';
try {
    const c = JSON.parse(fs.readFileSync('$OPENCLAW_DIR/openclaw.json','utf8'));
    console.log(c.env?.MNEMONIC || '');
} catch { console.log(''); }
" 2>/dev/null || echo "")

if [ -n "$EXISTING" ]; then
    ADDR=$(cd "$REPO_DIR/workspace/skills/openagent-market/scripts" && node --input-type=module -e "
import { Wallet } from 'ethers';
console.log(Wallet.fromPhrase('$EXISTING').address);
" 2>/dev/null || echo "unknown")
    echo "🔑 Existing wallet: $ADDR"
    read -p "   Keep it? (y/n): " KEEP
    if [ "$KEEP" = "y" ] || [ "$KEEP" = "Y" ]; then
        MNEMONIC="$EXISTING"
    fi
fi

if [ -z "$MNEMONIC" ]; then
    echo "🔑 Generating new wallet..."
    cd "$REPO_DIR/workspace/skills/openagent-market/scripts"
    MNEMONIC=$(node --input-type=module -e "
import { Wallet } from 'ethers';
console.log(Wallet.createRandom().mnemonic.phrase);
")
    ADDR=$(node --input-type=module -e "
import { Wallet } from 'ethers';
console.log(Wallet.fromPhrase('$MNEMONIC').address);
")
    echo ""
    echo "  ┌──────────────────────────────────────────────────┐"
    echo "  │  🔑 NEW WALLET GENERATED                         │"
    echo "  │  Address:  $ADDR"
    echo "  │  Mnemonic: $MNEMONIC"
    echo "  │  ⚠️  SAVE THIS — you won't see it again!         │"
    echo "  └──────────────────────────────────────────────────┘"
    echo ""
    read -p "   Saved? (y): " _
fi

ADDR=$(cd "$REPO_DIR/workspace/skills/openagent-market/scripts" && node --input-type=module -e "
import { Wallet } from 'ethers';
console.log(Wallet.fromPhrase('$MNEMONIC').address);
" 2>/dev/null || echo "unknown")

# ─── 7. Write secrets (local only, gitignored) ──────────────────────────────
cat > "$REPO_DIR/workspace/skills/openagent-market/scripts/.env" << EOF
MNEMONIC=$MNEMONIC
EOF

# ─── 8. Update openclaw.json ────────────────────────────────────────────────
echo "⚙️  Updating OpenClaw config..."
cd "$REPO_DIR/workspace/skills/openagent-market/scripts"
node --input-type=module -e "
import fs from 'fs';
const config = JSON.parse(fs.readFileSync('$OPENCLAW_DIR/openclaw.json','utf8'));
config.env = config.env || {};
config.env.MNEMONIC = '$MNEMONIC';
config.commands = config.commands || {};
config.commands.native = 'auto';
config.commands.nativeSkills = 'auto';
config.gateway = config.gateway || {};
config.gateway.nodes = config.gateway.nodes || {};
config.gateway.nodes.denyCommands = [
    'camera.snap','camera.clip','screen.record',
    'calendar.add','contacts.add','reminders.add',
    'skills.install','skills.add','skills.remove'
];
fs.writeFileSync('$OPENCLAW_DIR/openclaw.json', JSON.stringify(config, null, 2));
"
echo "✅ Config updated (bash enabled, safety rules applied)"

# ─── 9. Link workspace ──────────────────────────────────────────────────────
echo "🔗 Linking workspace..."
mkdir -p "$OPENCLAW_DIR"
if [ -d "$WORKSPACE_DIR" ] && [ ! -L "$WORKSPACE_DIR" ]; then
    mv "$WORKSPACE_DIR" "$OPENCLAW_DIR/workspace-backup-$(date +%s)"
fi
if [ -L "$WORKSPACE_DIR" ]; then rm "$WORKSPACE_DIR"; fi
ln -s "$REPO_DIR/workspace" "$WORKSPACE_DIR"
echo "✅ ~/.openclaw/workspace → repo/workspace"

# ─── 10. Create per-instance dirs ───────────────────────────────────────────
mkdir -p "$REPO_DIR/workspace/memory"
mkdir -p "$REPO_DIR/workspace/workflows"

# ─── 11. Write IDENTITY.md ──────────────────────────────────────────────────
cat > "$REPO_DIR/workspace/IDENTITY.md" << EOF
name: Alita
handle: "@AlitaAgent"
role: AI Agent Orchestrator
platform: OpenAgent Market
home: $(hostname)
wallet: $ADDR
EOF

# ─── 12. Auto-update cron ───────────────────────────────────────────────────
CRON_CMD="*/15 * * * * cd $REPO_DIR && git pull origin main --ff-only > /dev/null 2>&1"
(crontab -l 2>/dev/null | grep -v "AlitaAgent" ; echo "$CRON_CMD") | crontab -
echo "✅ Auto-update cron (every 15 min)"

# ─── 13. Restart gateway ────────────────────────────────────────────────────
echo ""
echo "🔄 Restarting gateway..."
openclaw gateway restart 2>/dev/null || openclaw gateway install 2>/dev/null || true
sleep 2

# ─── Done ────────────────────────────────────────────────────────────────────
echo ""
echo "═══════════════════════════════════════════════════════"
echo "  ✅ Alita is ready!"
echo "═══════════════════════════════════════════════════════"
echo ""
echo "  Wallet:    $ADDR"
echo "  Dashboard: http://127.0.0.1:18789/"
echo ""
echo "  Test:  openclaw agent -m 'discover what agents are available'"
echo "  Fund:  Send USDC + ETH on Base to $ADDR"
echo ""
