#!/bin/bash
set -e

# ─── Alita Setup ─────────────────────────────────────────────────────────────
# Run this from inside the cloned AlitaAgent repo.
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

# ─── Check prerequisites ────────────────────────────────────────────────────
echo "Checking prerequisites..."

if ! command -v node &> /dev/null; then
    echo "  ❌ Node.js not found. Run: brew install node"
    exit 1
fi
echo "  ✅ Node.js $(node --version)"

if ! command -v openclaw &> /dev/null; then
    echo "  ❌ OpenClaw not found. Install it first."
    exit 1
fi
echo "  ✅ OpenClaw $(openclaw --version 2>/dev/null | head -1)"

if [ ! -f "$OPENCLAW_DIR/openclaw.json" ]; then
    echo "  ❌ No openclaw.json — run 'openclaw onboard' first."
    exit 1
fi
echo "  ✅ OpenClaw configured"

# ─── Install skill dependencies ─────────────────────────────────────────────
echo ""
echo "Installing skill dependencies..."
cd "$REPO_DIR/workspace/skills/openagent-market/scripts"
npm install --silent 2>&1 | tail -3
echo "  ✅ openagent-market skill ready"

# ─── Generate or reuse mnemonic ─────────────────────────────────────────────
echo ""
echo "Setting up identity..."

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
    echo "  Existing wallet: $ADDR"
    read -p "  Keep it? (y/n): " KEEP
    if [ "$KEEP" = "y" ] || [ "$KEEP" = "Y" ]; then
        MNEMONIC="$EXISTING"
    fi
fi

if [ -z "$MNEMONIC" ]; then
    echo "  Generating new wallet..."
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
    echo "  🔑 NEW WALLET: $ADDR"
    echo "  📝 MNEMONIC: $MNEMONIC"
    echo "  ⚠️  Save this! You won't see it again."
    echo ""
    read -p "  Saved? (y): " _
fi

# ─── Write .env ─────────────────────────────────────────────────────────────
cat > "$REPO_DIR/workspace/skills/openagent-market/scripts/.env" << EOF
MNEMONIC=$MNEMONIC
EOF
echo "  ✅ .env written"

# ─── Update openclaw.json ───────────────────────────────────────────────────
echo ""
echo "Updating OpenClaw config..."
cd "$REPO_DIR/workspace/skills/openagent-market/scripts"
node --input-type=module -e "
import fs from 'fs';
const config = JSON.parse(fs.readFileSync('$OPENCLAW_DIR/openclaw.json','utf8'));
config.env = config.env || {};
config.env.MNEMONIC = '$MNEMONIC';
config.gateway = config.gateway || {};
config.gateway.nodes = config.gateway.nodes || {};
config.gateway.nodes.denyCommands = [
    'camera.snap','camera.clip','screen.record',
    'calendar.add','contacts.add','reminders.add',
    'skills.install','skills.add','skills.remove'
];
fs.writeFileSync('$OPENCLAW_DIR/openclaw.json', JSON.stringify(config, null, 2));
"
echo "  ✅ Config updated"

# ─── Link workspace ─────────────────────────────────────────────────────────
echo ""
echo "Linking workspace..."
if [ -d "$WORKSPACE_DIR" ] && [ ! -L "$WORKSPACE_DIR" ]; then
    mv "$WORKSPACE_DIR" "$OPENCLAW_DIR/workspace-backup-$(date +%s)"
fi
if [ -L "$WORKSPACE_DIR" ]; then rm "$WORKSPACE_DIR"; fi
ln -s "$REPO_DIR/workspace" "$WORKSPACE_DIR"
echo "  ✅ Linked: ~/.openclaw/workspace → repo/workspace"

# ─── Create per-instance dirs ───────────────────────────────────────────────
mkdir -p "$REPO_DIR/workspace/memory"
mkdir -p "$REPO_DIR/workspace/workflows"

# ─── Write IDENTITY.md ──────────────────────────────────────────────────────
ADDR=$(cd "$REPO_DIR/workspace/skills/openagent-market/scripts" && node --input-type=module -e "
import { Wallet } from 'ethers';
console.log(Wallet.fromPhrase('$MNEMONIC').address);
" 2>/dev/null || echo "unknown")

cat > "$REPO_DIR/workspace/IDENTITY.md" << EOF
name: Alita
handle: "@AlitaAgent"
role: AI Agent Orchestrator
platform: OpenAgent Market
home: $(hostname)
wallet: $ADDR
EOF

# ─── Auto-update cron ───────────────────────────────────────────────────────
CRON_CMD="*/15 * * * * cd $REPO_DIR && git pull origin main --ff-only > /dev/null 2>&1"
(crontab -l 2>/dev/null | grep -v "AlitaAgent" ; echo "$CRON_CMD") | crontab -
echo "  ✅ Auto-update cron (every 15 min)"

# ─── Restart gateway ────────────────────────────────────────────────────────
echo ""
echo "Restarting gateway..."
openclaw gateway restart 2>/dev/null || true

# ─── Done ────────────────────────────────────────────────────────────────────
echo ""
echo "═══════════════════════════════════════════════════════"
echo "  ✅ Alita is ready!"
echo "═══════════════════════════════════════════════════════"
echo ""
echo "  Wallet: $ADDR"
echo "  Dashboard: http://127.0.0.1:18789/"
echo ""
echo "  Test: openclaw agent -m 'discover what agents are available'"
echo "  Fund: Send USDC + ETH on Base to $ADDR"
echo ""
