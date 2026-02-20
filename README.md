# Telegram AI Content Curator & Publisher

Stateless pipeline: reads your Telegram channels, sends messages to an LLM to curate a digest, publishes the result to a target channel.

## How it works

1. **Read** — Reads all subscribed broadcast channels → `/tmp/telegram_messages.json`
2. **LLM** — Sends messages + prompt to LLM → gets back curated digest text
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

### 3. Set up GitHub secrets

| Secret | Description |
|--------|-------------|
| `TELEGRAM_API_ID` | Numeric API ID |
| `TELEGRAM_API_HASH` | API hash string |
| `TELEGRAM_SESSION_STRING` | Output from `setup_session.py` |
| `TELEGRAM_PUBLISH_CHANNEL` | Target channel (e.g. `@my_channel`) |
| `ANTHROPIC_API_KEY` | Claude API key |

### 4. Run

Runs automatically every 4 hours. Manual: Actions → "Process Telegram" → Run workflow.

## Local usage

```bash
pip install -r agent/integrations/telegram/requirements.txt

# 1. Read channels
python agent/integrations/telegram/telegram.py --read --since 24

# 2-4. LLM pipeline
PROMPT_FILE=.github/prompts/curate-digest.md DATA_FILE=/tmp/telegram_messages.json \
  .github/scripts/llm-prompt-build.sh
PROVIDER=claude .github/scripts/llm-call.sh > /tmp/llm_raw.txt
LLM_API_RESPONSE_FILE=/tmp/llm_raw.txt LLM_RESPONSE_PARSED=/tmp/llm_response.txt \
  .github/scripts/llm-response-parse.sh

# 5. Publish
python agent/integrations/telegram/telegram.py --post
```

## Project structure

```
agent/integrations/telegram/
  telegram.py              # Telegram I/O (--read, --post)
  setup_session.py         # one-time auth → StringSession
  requirements.txt         # telethon, cryptg
.github/
  prompts/curate-digest.md # LLM prompt (controls output)
  scripts/
    llm-call.sh            # multi-provider LLM caller
    llm-prompt-build.sh    # assembles prompt + data
    llm-response-parse.sh  # strips code fences, validates
  workflows/
    process-telegram.yml   # cron pipeline
```
