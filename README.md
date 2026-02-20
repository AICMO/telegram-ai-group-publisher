# Telegram AI Content Curator & Publisher

Stateless pipeline: reads your Telegram channels, Claude curates a digest, publishes to a target channel.

## How it works

1. **Read** — Reads all subscribed broadcast channels → `/tmp/telegram_messages.json`
2. **Curate** — Claude Code Action reads messages + prompt → writes digest to `/tmp/llm_response.txt`
3. **Publish** — Posts the digest to your target Telegram channel

Runs on a 4-hour cron via GitHub Actions. No persistent state.

## Setup

### 1. Get Telegram API credentials

1. Go to https://my.telegram.org → **API development tools**
2. Create a new application, copy `api_id` and `api_hash`

### 2. Generate a session string

```bash
pip install telethon
export TELEGRAM_API_ID="your_api_id"
export TELEGRAM_API_HASH="your_api_hash"
export TELEGRAM_PHONE="+your_phone_number"
python agent/integrations/telegram/setup_session.py
```

### 3. Create a target channel

In Telegram: Menu → New Channel → make it Public → set a username (e.g. `my_ai_digest`).

### 4. Set up GitHub secrets

| Secret | Description |
|--------|-------------|
| `TELEGRAM_API_ID` | Numeric API ID |
| `TELEGRAM_API_HASH` | API hash string |
| `TELEGRAM_SESSION_STRING` | Output from `setup_session.py` |
| `TELEGRAM_PUBLISH_CHANNEL` | Target channel (e.g. `@my_ai_digest`) |
| `CLAUDE_CODE_OAUTH_TOKEN` | Claude Code OAuth token (or `ANTHROPIC_API_KEY` as fallback) |

### 5. Run

Runs automatically every 4 hours. Manual: Actions → "Process Telegram" → Run workflow.

## Project structure

```
agent/integrations/telegram/
  telegram.py              # Telegram I/O (--read, --post)
  setup_session.py         # one-time auth → StringSession
  requirements.txt         # telethon, cryptg
.github/
  prompts/curate-digest.md # prompt (controls what Claude produces)
  workflows/
    process-telegram.yml   # cron pipeline
```
