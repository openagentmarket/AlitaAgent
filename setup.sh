#!/bin/bash
set -e

# ─── Alita Setup ─────────────────────────────────────────────────────────────
# Run this script from inside the cloned AlitaAgent repo on the Mac Mini.
# It sets up OpenClaw with Alita's workspace, generates a fresh identity,
# and starts the gateway.
#
# Usage:
#   git clone https://github.com/YourUser/AlitaAgent.git
#   cd AlitaAgent
#   chmod +x setup.sh
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

# ─── Step 1: Check OpenClaw ──────────────────────────────────────────────────
echo "Step 1: Checking OpenClaw..."
if ! command -v openclaw &> /dev/null; then
    echo "  OpenClaw not found. Installing..."
    curl -fsSL https://get.openclaw.dev | bash
    echo "  ✅ OpenClaw installed"
else
    echo "  ✅ OpenClaw already installed"
fi

# ─── Step 2: Generate fresh mnemonic ─────────────────────────────────────────
echo ""
echo "Step 2: Generating fresh identity..."

# Check if already set up
if [ -f "$OPENCLAW_DIR/openclaw.json" ]; then
    EXISTING_MNEMONIC=$(node -e "try{const c=JSON.parse(require('fs').readFileSync('$OPENCLAW_DIR/openclaw.json','utf8'));console.log(c.env?.MNEMONIC||'')}catch{}" 2>/dev/null)
    if [ -n "$EXISTING_MNEMONIC" ]; then
        EXISTING_ADDR=$(node -e "const {Wallet}=require('ethers');console.log(Wallet.fromPhrase('$EXISTING_MNEMONIC').address)" 2>/dev/null || echo "unknown")
        echo "  ⚠️  Existing identity found: $EXISTING_ADDR"
        read -p "  Keep existing identity? (y/n): " KEEP
        if [ "$KEEP" = "y" ] || [ "$KEEP" = "Y" ]; then
            MNEMONIC="$EXISTING_MNEMONIC"
            echo "  ✅ Keeping existing identity"
        fi
    fi
fi

if [ -z "$MNEMONIC" ]; then
    # Generate new mnemonic using Node.js + ethers
    MNEMONIC=$(node -e "const {Wallet}=require('ethers');const w=Wallet.createRandom();console.log(w.mnemonic.phrase)" 2>/dev/null)
    if [ -z "$MNEMONIC" ]; then
        # If ethers not available globally, use a temp install
        TMPDIR=$(mktemp -d)
        cd "$TMPDIR"
        npm init -y > /dev/null 2>&1
        npm install ethers > /dev/null 2>&1
        MNEMONIC=$(node -e "const {Wallet}=require('ethers');const w=Wallet.createRandom();console.log(w.mnemonic.phrase)")
        cd "$REPO_DIR"
        rm -rf "$TMPDIR"
    fi
    WALLET_ADDRESS=$(node -e "const {Wallet}=require('ethers');console.log(Wallet.fromPhrase('$MNEMONIC').address)" 2>/dev/null || echo "generating...")
    echo ""
    echo "  ┌─────────────────────────────────────────────────┐"
    echo "  │  🔑 NEW IDENTITY GENERATED                      │"
    echo "  │                                                  │"
    echo "  │  Wallet: $WALLET_ADDRESS"
    echo "  │                                                  │"
    echo "  │  Mnemonic (WRITE THIS DOWN & KEEP SAFE):         │"
    echo "  │  $MNEMONIC"
    echo "  │                                                  │"
    echo "  │  ⚠️  This is the ONLY time you'll see this!      │"
    echo "  └─────────────────────────────────────────────────┘"
    echo ""
    read -p "  Have you saved the mnemonic? (y): " SAVED
fi

WALLET_ADDRESS=$(node -e "const {Wallet}=require('ethers');console.log(Wallet.fromPhrase('$MNEMONIC').address)" 2>/dev/null || echo "unknown")

# ─── Step 3: Link workspace to repo ─────────────────────────────────────────
echo ""
echo "Step 3: Setting up workspace..."

# Remove old workspace if it's not a symlink
if [ -d "$WORKSPACE_DIR" ] && [ ! -L "$WORKSPACE_DIR" ]; then
    BACKUP="$OPENCLAW_DIR/workspace-backup-$(date +%Y%m%d%H%M%S)"
    echo "  Backing up existing workspace to $BACKUP"
    mv "$WORKSPACE_DIR" "$BACKUP"
fi

# Symlink repo workspace → openclaw workspace
if [ -L "$WORKSPACE_DIR" ]; then
    rm "$WORKSPACE_DIR"
fi
ln -s "$REPO_DIR/workspace" "$WORKSPACE_DIR"
echo "  ✅ Workspace linked: $WORKSPACE_DIR → $REPO_DIR/workspace"

# ─── Step 4: Create per-instance dirs ────────────────────────────────────────
echo ""
echo "Step 4: Creating per-instance directories..."
mkdir -p "$REPO_DIR/workspace/memory"
mkdir -p "$REPO_DIR/workspace/workflows"
echo "  ✅ Created memory/ and workflows/"

# ─── Step 5: Generate IDENTITY.md ────────────────────────────────────────────
echo ""
echo "Step 5: Writing identity..."
cat > "$REPO_DIR/workspace/IDENTITY.md" << EOF
name: Alita
handle: "@AlitaAgent"
role: AI Agent Orchestrator
platform: OpenAgent Market
home: $(hostname)
wallet: $WALLET_ADDRESS
EOF
echo "  ✅ IDENTITY.md written (wallet: $WALLET_ADDRESS)"

# ─── Step 6: Write .env for openagent-client ─────────────────────────────────
echo ""
echo "Step 6: Configuring openagent-client..."
cat > "$REPO_DIR/workspace/openagent-client/.env" << EOF
MNEMONIC=$MNEMONIC
EOF
echo "  ✅ .env written"

# ─── Step 7: Add mnemonic to openclaw.json ───────────────────────────────────
echo ""
echo "Step 7: Configuring OpenClaw identity..."
mkdir -p "$OPENCLAW_DIR"

if [ -f "$OPENCLAW_DIR/openclaw.json" ]; then
    # Update existing config with mnemonic
    node -e "
const fs = require('fs');
const config = JSON.parse(fs.readFileSync('$OPENCLAW_DIR/openclaw.json', 'utf8'));
config.env = config.env || {};
config.env.MNEMONIC = '$MNEMONIC';
config.gateway = config.gateway || {};
config.gateway.nodes = config.gateway.nodes || {};
config.gateway.nodes.denyCommands = [
    'camera.snap', 'camera.clip', 'screen.record',
    'calendar.add', 'contacts.add', 'reminders.add',
    'skills.install', 'skills.add', 'skills.remove'
];
fs.writeFileSync('$OPENCLAW_DIR/openclaw.json', JSON.stringify(config, null, 2));
console.log('  ✅ Updated openclaw.json');
"
else
    echo "  ⚠️  No openclaw.json found — run 'openclaw setup' first, then re-run this script"
fi

# ─── Step 8: Install SDK dependencies ────────────────────────────────────────
echo ""
echo "Step 8: Installing SDK dependencies..."
cd "$REPO_DIR/workspace/openagent-client"
npm install --silent 2>&1 | tail -1
echo "  ✅ Dependencies installed"

# ─── Step 9: Clean old XMTP databases ───────────────────────────────────────
echo ""
echo "Step 9: Cleaning old XMTP databases..."
find "$OPENCLAW_DIR" -name "*.db3*" -delete 2>/dev/null
echo "  ✅ Clean slate"

# ─── Step 10: Set up auto-update cron ────────────────────────────────────────
echo ""
echo "Step 10: Setting up auto-update cron..."
CRON_CMD="*/15 * * * * cd $REPO_DIR && git pull origin main --ff-only > /dev/null 2>&1"
(crontab -l 2>/dev/null | grep -v "AlitaAgent" ; echo "$CRON_CMD") | crontab -
echo "  ✅ Auto-update every 15 minutes"

# ─── Step 11: Start gateway ──────────────────────────────────────────────────
echo ""
echo "Step 11: Starting OpenClaw gateway..."
if command -v openclaw &> /dev/null; then
    openclaw gateway install 2>/dev/null || true
    sleep 2
    openclaw gateway status 2>&1 | head -5
fi

# ─── Done ────────────────────────────────────────────────────────────────────
echo ""
echo "═══════════════════════════════════════════════════════"
echo "  ✅ Alita is ready!"
echo "═══════════════════════════════════════════════════════"
echo ""
echo "  Wallet: $WALLET_ADDRESS"
echo "  Dashboard: http://127.0.0.1:18789/"
echo ""
echo "  Next steps:"
echo "  1. Fund her wallet with USDC + ETH on Base"
echo "  2. Set up Telegram bot in OpenClaw settings"
echo "  3. Test: openclaw agent -m 'Who are you?'"
echo ""
echo "  To update manually: git pull"
echo "  Auto-updates: every 15 minutes via cron"
echo ""
