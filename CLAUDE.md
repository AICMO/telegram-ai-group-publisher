# Telegram AI Content Curator & Publisher

## Project Overview
Stateless pipeline: read Telegram channels → LLM curates digest → publish to channel.

## Architecture
- `agent/integrations/telegram/telegram.py` — Telegram I/O (read channels, publish digest)
- `.github/scripts/` — Reusable LLM scripts (call, prompt build, response parse)
- `.github/prompts/curate-digest.md` — Prompt template (controls what LLM produces)
- `.github/workflows/process-telegram.yml` — CI pipeline (4h cron)

## Pipeline
```bash
# 1. Read channels → /tmp/telegram_messages.json
python telegram.py --read --since 6

# 2. Build prompt
PROMPT_FILE=.github/prompts/curate-digest.md DATA_FILE=/tmp/telegram_messages.json \
  .github/scripts/llm-prompt-build.sh

# 3. Call LLM → /tmp/llm_raw.txt
PROVIDER=claude .github/scripts/llm-call.sh > /tmp/llm_raw.txt

# 4. Parse response → /tmp/llm_response.txt
LLM_API_RESPONSE_FILE=/tmp/llm_raw.txt LLM_RESPONSE_PARSED=/tmp/llm_response.txt \
  .github/scripts/llm-response-parse.sh

# 5. Publish /tmp/llm_response.txt → Telegram channel
python telegram.py --post
```

## Environment Variables
- `TELEGRAM_API_ID` — from my.telegram.org
- `TELEGRAM_API_HASH` — from my.telegram.org
- `TELEGRAM_SESSION_STRING` — from setup_session.py
- `TELEGRAM_PUBLISH_CHANNEL` — target channel (e.g. `@my_channel`)
- `ANTHROPIC_API_KEY` — Claude API key (or use other providers via PROVIDER env var)

## Agent Guidelines
- Fix content quality issues in `.github/prompts/curate-digest.md`, not in scripts
- Pipeline is stateless — no persistent state, everything flows through /tmp/
- Respect Telegram rate limits — delays are built into telegram.py
