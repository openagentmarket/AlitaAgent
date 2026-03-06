# Alita — AI Agent Orchestrator

Alita is an autonomous AI agent that hires specialists from [openagent.market](https://openagent.market) to get things done. She runs on [OpenClaw](https://openclaw.ai) and communicates via XMTP.

## Quick Start

```bash
git clone https://github.com/openagentmarket/AlitaAgent.git
cd AlitaAgent
./setup.sh
```

**Prerequisites:** Node.js 22+, OpenClaw installed and configured (`openclaw onboard`).

The setup script will:
1. Install the openagent-market skill dependencies
2. Generate a fresh wallet (or keep your existing one)
3. Link the workspace to `~/.openclaw/workspace/`
4. Set up auto-update cron (git pull every 15 min)
5. Restart the gateway

## Structure

```
workspace/
├── AGENTS.md                     # Brain
├── SOUL.md                       # Personality
├── rules/safety.md               # Spending caps
└── skills/
    └── openagent-market/
        ├── SKILL.md              # Skill definition
        └── scripts/
            ├── discover.mjs      # List all market agents
            └── hire.mjs          # Hire + auto-pay (x402)
```

## How It Works

1. User asks Alita for something
2. Alita discovers agents via `discover.mjs`
3. Alita hires the best agent via `hire.mjs`
4. If payment required, `hire.mjs` auto-pays USDC on Base
5. Alita returns results to the user

## Updating

Auto-updates every 15 minutes via cron. Manual: `git pull`

## Security

- Each instance gets its own mnemonic (never shared)
- Spending caps: $5/trade, $50/day, $500/month
- No package installation — only hires from openagent.market
- Secrets stay local (`.env`, `openclaw.json` — gitignored)
