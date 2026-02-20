# Telegram AI Content Curator & Publisher

## Project Overview
Stateless pipeline: read Telegram channels → LLM curates digest → publish to channel.

## Architecture
- `agent/integrations/telegram/telegram.py` — Telegram I/O (read channels, publish digest)
- `.github/prompts/curate-digest.md` — Prompt template (controls what LLM produces)
- `.github/scripts/` — Reusable LLM scripts (API fallback path)
- `.github/workflows/process-telegram.yml` — CI pipeline (4h cron)

## Pipeline
```
1. Read      telegram.py --read --since 6    → /tmp/telegram_messages.json
2. Build     llm-prompt-build.sh              → /tmp/user_prompt.txt
3. Curate    claude-code-action (OAuth)        → /tmp/llm_response.txt
             OR llm-call.sh (API fallback)
4. Parse     llm-response-parse.sh            → /tmp/llm_response.txt
5. Publish   telegram.py --post               → Telegram channel
```

## LLM Auth
- Primary: `CLAUDE_CODE_OAUTH_TOKEN` via claude-code-action
- Fallback: `ANTHROPIC_API_KEY` (or any provider) via llm-call.sh
- Provider/model configurable via `LLM_PROVIDER`, `LLM_MODEL` repo variables

## Environment Variables
- `TELEGRAM_API_ID` — from my.telegram.org
- `TELEGRAM_API_HASH` — from my.telegram.org
- `TELEGRAM_SESSION_STRING` — from setup_session.py
- `TELEGRAM_PUBLISH_CHANNEL` — target channel (e.g. `@my_channel`)
- `CLAUDE_CODE_OAUTH_TOKEN` — Claude Code OAuth token (primary)
- `ANTHROPIC_API_KEY` — Claude API key (fallback)

## Agent Guidelines
- Fix content quality issues in `.github/prompts/curate-digest.md`, not in scripts
- Pipeline is stateless — no persistent state, everything flows through /tmp/
- Respect Telegram rate limits — delays are built into telegram.py
