#!/usr/bin/env python3
"""Telegram AI Content Curator — single entry point.

Usage:
  python telegram.py --read --since 6     # Read channels → /tmp/telegram_messages.json
  python telegram.py --post               # Publish /tmp/llm_response.txt to channel
"""

import argparse
import asyncio
import json
import os
import sys
from datetime import datetime, timedelta, timezone
from pathlib import Path

from telethon import errors
from telethon.sessions import StringSession
from telethon.tl.types import Channel

MESSAGES_TMP = Path("/tmp/telegram_messages.json")
LLM_RESPONSE_TMP = Path("/tmp/llm_response.txt")
TELEGRAM_MSG_LIMIT = 4096


def get_telegram_client():
    from telethon import TelegramClient

    api_id = os.environ.get("TELEGRAM_API_ID")
    api_hash = os.environ.get("TELEGRAM_API_HASH")
    session_string = os.environ.get("TELEGRAM_SESSION_STRING")

    missing = []
    if not api_id:
        missing.append("TELEGRAM_API_ID")
    if not api_hash:
        missing.append("TELEGRAM_API_HASH")
    if not session_string:
        missing.append("TELEGRAM_SESSION_STRING")

    if missing:
        print(f"Error: Missing environment variables: {', '.join(missing)}")
        sys.exit(1)

    return TelegramClient(StringSession(session_string), int(api_id), api_hash)


# ============================================================
# READ: --read
# ============================================================

async def cmd_read(since_hours: float):
    client = get_telegram_client()
    await client.connect()

    if not await client.is_user_authorized():
        print("ERROR: Session is not authorized. Run setup_session.py first.")
        await client.disconnect()
        return

    me = await client.get_me()
    print(f"Logged in as {me.first_name} (@{me.username or 'no_username'})")

    cutoff = datetime.now(timezone.utc) - timedelta(hours=since_hours)

    channels = []
    async for dialog in client.iter_dialogs():
        if isinstance(dialog.entity, Channel) and dialog.entity.broadcast:
            channels.append(dialog)

    print(f"Scanning {len(channels)} channels since {cutoff.strftime('%Y-%m-%d %H:%M UTC')}...\n")

    collected = []
    total_read = 0

    for dialog in channels:
        channel_collected = 0

        try:
            async for message in client.iter_messages(dialog.entity, limit=100):
                if message.date.replace(tzinfo=timezone.utc) < cutoff:
                    break

                total_read += 1

                if not message.text and not message.raw_text:
                    continue

                text = message.text or message.raw_text
                if len(text.strip()) < 20:
                    continue

                collected.append({
                    "channel_title": dialog.title,
                    "channel_username": getattr(dialog.entity, "username", None),
                    "message_id": message.id,
                    "date": message.date.isoformat(),
                    "text": text,
                    "url": f"https://t.me/{dialog.entity.username}/{message.id}" if dialog.entity.username else None,
                })
                channel_collected += 1

        except errors.FloodWaitError as e:
            print(f"  FloodWait: sleeping {e.seconds}s for {dialog.title}")
            await asyncio.sleep(e.seconds)
        except Exception as e:
            print(f"  Error reading {dialog.title}: {e}")

        if channel_collected:
            print(f"  {dialog.title}: {channel_collected} messages")

        await asyncio.sleep(1)

    await client.disconnect()

    MESSAGES_TMP.write_text(json.dumps(collected, indent=2, ensure_ascii=False) + "\n")
    print(f"\nExtracted {len(collected)} from {total_read} read across {len(channels)} channels")
    print(f"Written to {MESSAGES_TMP}")


# ============================================================
# PUBLISH: --post
# ============================================================

def _split_message(text: str) -> list[str]:
    """Split text into chunks that fit Telegram's message limit."""
    if len(text) <= TELEGRAM_MSG_LIMIT:
        return [text]
    parts = []
    while text:
        if len(text) <= TELEGRAM_MSG_LIMIT:
            parts.append(text)
            break
        split_at = text.rfind('\n', 0, TELEGRAM_MSG_LIMIT)
        if split_at == -1:
            split_at = TELEGRAM_MSG_LIMIT
        parts.append(text[:split_at])
        text = text[split_at:].lstrip('\n')
    return parts


async def cmd_post():
    if not LLM_RESPONSE_TMP.exists():
        print(f"Error: {LLM_RESPONSE_TMP} not found. Run the LLM pipeline first.")
        sys.exit(1)

    digest_text = LLM_RESPONSE_TMP.read_text().strip()
    if not digest_text:
        print("LLM response is empty, nothing to publish.")
        return

    channel_id = os.environ.get("TELEGRAM_PUBLISH_CHANNEL")
    if not channel_id:
        print("Error: TELEGRAM_PUBLISH_CHANNEL environment variable not set")
        sys.exit(1)

    client = get_telegram_client()
    await client.connect()

    if not await client.is_user_authorized():
        print("ERROR: Session is not authorized.")
        await client.disconnect()
        return

    try:
        if channel_id.startswith("@"):
            entity = await client.get_entity(channel_id)
        else:
            entity = await client.get_entity(int(channel_id))
    except Exception as e:
        print(f"ERROR: Could not resolve {channel_id}: {e}")
        await client.disconnect()
        return

    parts = _split_message(digest_text)
    print(f"Publishing {len(parts)} message(s) to {channel_id}")

    for part in parts:
        try:
            await client.send_message(entity, part, link_preview=False)
            await asyncio.sleep(3)
        except Exception as e:
            print(f"ERROR posting to {channel_id}: {e}")
            break

    await client.disconnect()
    print("Done.")


# ============================================================
# CLI
# ============================================================

def main():
    parser = argparse.ArgumentParser(description="Telegram AI Content Curator")
    parser.add_argument("--read", action="store_true", help="Read channels → /tmp/telegram_messages.json")
    parser.add_argument("--since", type=float, default=6, help="Hours to look back (default: 6)")
    parser.add_argument("--post", action="store_true", help="Publish /tmp/llm_response.txt to channel")
    args = parser.parse_args()

    if not any([args.read, args.post]):
        parser.print_help()
        sys.exit(1)

    if args.read:
        asyncio.run(cmd_read(args.since))
    elif args.post:
        asyncio.run(cmd_post())


if __name__ == "__main__":
    main()
