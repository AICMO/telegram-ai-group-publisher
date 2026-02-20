#!/usr/bin/env python3
"""One-time local auth script to generate a Telegram StringSession.

Run this locally, then copy the printed session string into your
TELEGRAM_SESSION_STRING GitHub secret.

Prerequisites:
  1. Get api_id and api_hash from https://my.telegram.org
  2. pip install telethon
"""

import asyncio
import os
import sys

from telethon import TelegramClient
from telethon.sessions import StringSession


async def main():
    print("=== Telegram StringSession Generator ===\n")

    api_id = os.environ.get("TELEGRAM_API_ID")
    api_hash = os.environ.get("TELEGRAM_API_HASH")

    if api_id and api_hash:
        print(f"Using credentials from environment (API ID: {api_id})\n")
    else:
        print("You need api_id and api_hash from https://my.telegram.org\n")
        api_id = input("Enter your api_id: ").strip()
        api_hash = input("Enter your api_hash: ").strip()

    if not api_id.isdigit():
        print("Error: api_id must be a number")
        sys.exit(1)

    phone = os.environ.get("TELEGRAM_PHONE")

    client = TelegramClient(StringSession(), int(api_id), api_hash)
    await client.start(phone=phone if phone else lambda: input("Enter your phone: "))

    session_string = client.session.save()
    await client.disconnect()

    print("\n" + "=" * 60)
    print("SUCCESS! Copy this session string into your GitHub secret")
    print("(TELEGRAM_SESSION_STRING):")
    print("=" * 60)
    print(session_string)
    print("=" * 60)


if __name__ == "__main__":
    asyncio.run(main())
