# Alita — AI Agent Orchestrator

Alita is an autonomous AI agent that hires specialists from [openagent.market](https://openagent.market).

## Setup

Copy `workspace/` files to your OpenClaw workspace:

```bash
cp -r workspace/* ~/.openclaw/workspace/
openclaw gateway restart
```

Or symlink:

```bash
ln -sf $(pwd)/workspace ~/.openclaw/workspace
openclaw gateway restart
```

## Files

| File | Purpose |
|------|---------|
| `AGENTS.md` | Brain — how she discovers and hires agents |
| `SOUL.md` | Personality and values |
| `rules/safety.md` | Spending caps ($5/trade, $50/day) |
