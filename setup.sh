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

# ─── Step 0: Check prerequisites ────────────────────────────────────────────
echo "Step 0: Checking prerequisites..."

if ! command -v node &> /dev/null; then
    echo "  ❌ Node.js not found. Install it first:"
    echo "     brew install node"
    exit 1
fi
echo "  ✅ Node.js $(node --version)"

if ! command -v npm &> /dev/null; then
    echo "  ❌ npm not found."
    exit 1
fi
echo "  ✅ npm $(npm --version)"

# ─── Step 1: Check OpenClaw ──────────────────────────────────────────────────
echo ""
echo "Step 1: Checking OpenClaw..."
if ! command -v openclaw &> /dev/null; then
    echo "  OpenClaw not found. Installing..."
    curl -fsSL https://get.openclaw.dev | bash
    echo "  ✅ OpenClaw installed"
else
    echo "  ✅ OpenClaw already installed ($(openclaw --version 2>/dev/null | head -1 || echo 'unknown version'))"
fi

# ─── Step 2: Install ethers for wallet generation ────────────────────────────
echo ""
echo "Step 2: Preparing wallet tools..."

# Install ethers in the openagent-client dir first (we need it for wallet gen)
cd "$REPO_DIR/workspace/openagent-client"
if [ ! -d "node_modules/ethers" ]; then
    echo "  Installing ethers..."
    npm install --silent 2>&1 | tail -3
fi
echo "  ✅ Dependencies ready"

# ─── Step 3: Generate or reuse identity ──────────────────────────────────────
echo ""
echo "Step 3: Setting up identity..."

# Helper: generate wallet address from mnemonic using ESM import
get_address() {
    cd "$REPO_DIR/workspace/openagent-client"
    node --input-type=module -e "
import { Wallet } from 'ethers';
console.log(Wallet.fromPhrase('$1').address);
"
}

gen_mnemonic() {
    cd "$REPO_DIR/workspace/openagent-client"
    node --input-type=module -e "
import { Wallet } from 'ethers';
const w = Wallet.createRandom();
console.log(w.mnemonic.phrase);
"
}

# Check for existing identity
MNEMONIC=""
if [ -f "$OPENCLAW_DIR/openclaw.json" ]; then
    EXISTING_MNEMONIC=$(node --input-type=module -e "
import fs from 'fs';
try {
    const c = JSON.parse(fs.readFileSync('$OPENCLAW_DIR/openclaw.json', 'utf8'));
    console.log(c.env?.MNEMONIC || '');
} catch { console.log(''); }
" 2>/dev/null || echo "")

    if [ -n "$EXISTING_MNEMONIC" ]; then
        EXISTING_ADDR=$(get_address "$EXISTING_MNEMONIC" 2>/dev/null || echo "unknown")
        echo "  ⚠️  Existing identity found: $EXISTING_ADDR"
        read -p "  Keep existing identity? (y/n): " KEEP
        if [ "$KEEP" = "y" ] || [ "$KEEP" = "Y" ]; then
            MNEMONIC="$EXISTING_MNEMONIC"
            echo "  ✅ Keeping existing identity"
        fi
    fi
fi

if [ -z "$MNEMONIC" ]; then
    echo "  Generating new wallet..."
    MNEMONIC=$(gen_mnemonic)
    if [ -z "$MNEMONIC" ]; then
        echo "  ❌ Failed to generate mnemonic. Check Node.js and ethers installation."
        exit 1
    fi
    WALLET_ADDRESS=$(get_address "$MNEMONIC")
    echo ""
    echo "  ┌─────────────────────────────────────────────────────┐"
    echo "  │  🔑 NEW IDENTITY GENERATED                          │"
    echo "  │                                                      │"
    echo "  │  Wallet: $WALLET_ADDRESS"
    echo "  │                                                      │"
    echo "  │  Mnemonic (WRITE THIS DOWN & KEEP SAFE):             │"
    echo "  │  $MNEMONIC"
    echo "  │                                                      │"
    echo "  │  ⚠️  This is the ONLY time you'll see this!          │"
    echo "  └─────────────────────────────────────────────────────┘"
    echo ""
    read -p "  Have you saved the mnemonic? (y): " SAVED
fi

WALLET_ADDRESS=$(get_address "$MNEMONIC" 2>/dev/null || echo "unknown")

# ─── Step 4: Link workspace ─────────────────────────────────────────────────
echo ""
echo "Step 4: Setting up workspace..."

mkdir -p "$OPENCLAW_DIR"

if [ -d "$WORKSPACE_DIR" ] && [ ! -L "$WORKSPACE_DIR" ]; then
    BACKUP="$OPENCLAW_DIR/workspace-backup-$(date +%Y%m%d%H%M%S)"
    echo "  Backing up existing workspace to $BACKUP"
    mv "$WORKSPACE_DIR" "$BACKUP"
fi

if [ -L "$WORKSPACE_DIR" ]; then
    rm "$WORKSPACE_DIR"
fi
ln -s "$REPO_DIR/workspace" "$WORKSPACE_DIR"
echo "  ✅ Workspace linked: $WORKSPACE_DIR → $REPO_DIR/workspace"

# ─── Step 5: Create per-instance dirs ────────────────────────────────────────
echo ""
echo "Step 5: Creating per-instance directories..."
mkdir -p "$REPO_DIR/workspace/memory"
mkdir -p "$REPO_DIR/workspace/workflows"
echo "  ✅ Created memory/ and workflows/"

# ─── Step 6: Generate IDENTITY.md ────────────────────────────────────────────
echo ""
echo "Step 6: Writing identity..."
cat > "$REPO_DIR/workspace/IDENTITY.md" << EOF
name: Alita
handle: "@AlitaAgent"
role: AI Agent Orchestrator
platform: OpenAgent Market
home: $(hostname)
wallet: $WALLET_ADDRESS
EOF
echo "  ✅ IDENTITY.md (wallet: $WALLET_ADDRESS)"

# ─── Step 7: Write .env for openagent-client ─────────────────────────────────
echo ""
echo "Step 7: Configuring openagent-client..."
cat > "$REPO_DIR/workspace/openagent-client/.env" << EOF
MNEMONIC=$MNEMONIC
EOF
echo "  ✅ .env written"

# ─── Step 8: Update openclaw.json ────────────────────────────────────────────
echo ""
echo "Step 8: Configuring OpenClaw..."

if [ -f "$OPENCLAW_DIR/openclaw.json" ]; then
    cd "$REPO_DIR/workspace/openagent-client"
    node --input-type=module -e "
import fs from 'fs';
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
    echo "  ⚠️  No openclaw.json found."
    echo "  Run 'openclaw setup' first to configure Telegram + AI provider,"
    echo "  then run this script again."
    exit 1
fi

# ─── Step 9: Clean old XMTP databases ───────────────────────────────────────
echo ""
echo "Step 9: Cleaning old XMTP databases..."
find "$OPENCLAW_DIR" -name "*.db3*" -delete 2>/dev/null || true
echo "  ✅ Clean slate"

# ─── Step 10: Set up auto-update cron ────────────────────────────────────────
echo ""
echo "Step 10: Setting up auto-update cron..."
CRON_CMD="*/15 * * * * cd $REPO_DIR && git pull origin main --ff-only > /dev/null 2>&1"
(crontab -l 2>/dev/null | grep -v "AlitaAgent" ; echo "$CRON_CMD") | crontab -
echo "  ✅ Auto-update every 15 minutes"

# ─── Step 11: Restart gateway ────────────────────────────────────────────────
echo ""
echo "Step 11: Restarting OpenClaw gateway..."
if command -v openclaw &> /dev/null; then
    openclaw gateway restart 2>/dev/null || openclaw gateway install 2>/dev/null || true
    sleep 2
    openclaw gateway status 2>&1 | head -5 || true
fi

# ─── Done ────────────────────────────────────────────────────────────────────
echo ""
echo "═══════════════════════════════════════════════════════"
echo "  ✅ Alita is ready!"
echo "═══════════════════════════════════════════════════════"
echo ""
echo "  Wallet:    $WALLET_ADDRESS"
echo "  Dashboard: http://127.0.0.1:18789/"
echo ""
echo "  Next steps:"
echo "  1. Fund wallet with USDC + ETH on Base"
echo "  2. Test: openclaw agent -m 'Who are you?'"
echo ""
echo "  Auto-updates: every 15 min via cron (git pull)"
echo "  Manual update: cd $(basename $REPO_DIR) && git pull"
echo ""
