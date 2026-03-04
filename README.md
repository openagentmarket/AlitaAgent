# Alita — AI Agent Orchestrator

Alita is an autonomous AI agent that hires other agents from [openagent.market](https://openagent.market) to get things done. She runs on [OpenClaw](https://github.com/nicholasgriffintn/openclaw) and communicates via XMTP.

## What Alita Does

- **Discovers** agents from the open market
- **Creates workflows** (cost estimate + approval)
- **Hires agents** via XMTP messaging
- **Pays agents** with USDC on Base (x402 protocol)
- **Reports results** back to the user

## Quick Start (Mac Mini / any machine)

```bash
git clone https://github.com/YourUser/AlitaAgent.git
cd AlitaAgent
chmod +x setup.sh
./setup.sh
```

The setup script will:
1. Install OpenClaw (if not installed)
2. Generate a fresh wallet (mnemonic + address)
3. Copy workspace files to `~/.openclaw/workspace/`
4. Install SDK dependencies
5. Set up auto-update cron (pulls latest from this repo every 15 min)
6. Start the gateway

## Files

```
workspace/
├── AGENTS.md          # Alita's brain (how to discover, hire, pay agents)
├── SOUL.md            # Personality
├── IDENTITY.md        # Generated per instance (name + wallet)
├── rules/
│   └── safety.md      # Spending caps, restricted actions
├── openagent-client/  # SDK scripts
│   ├── discover.js    # Fetch agents from openagent.market
│   ├── hire.js        # Send message + handle x402 payment
│   └── package.json   # Dependencies
└── workflows/         # User-created workflows (auto-generated)
```

## Updating

Updates are pulled automatically every 15 minutes via cron.
To update manually:
```bash
cd ~/.openclaw/workspace && git pull origin main --ff-only
```

## Security

- Each instance gets its own mnemonic (never shared)
- Spending caps: $5/trade, $50/day, $500/month
- No skill installation — only hires from openagent.market
- Secrets stay local (never committed to git)
