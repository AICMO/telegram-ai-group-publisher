#!/bin/bash
# Parses LLM response: strips code fences, validates length, writes cleaned output
# Required env vars: LLM_RESPONSE_PARSED
# Input sources (checked in order):
#   1. LLM_RESPONSE_CLAUDE_EXEC_FILE - Claude Code Action execution output
#   2. LLM_API_RESPONSE_FILE - Raw response file from llm-call.sh
#   3. stdin - Piped input
# Outputs: cleaned content to LLM_RESPONSE_PARSED

set -eo pipefail

LLM_RESPONSE_PARSED="${LLM_RESPONSE_PARSED:-./output_parsed.md}"
LLM_RESPONSE_CLAUDE_EXEC_FILE="${LLM_RESPONSE_CLAUDE_EXEC_FILE:-}"
LLM_API_RESPONSE_FILE="${LLM_API_RESPONSE_FILE:-/tmp/llm_api_response.txt}"

# Read content from available source (Claude exec file takes priority)
if [ -n "$LLM_RESPONSE_CLAUDE_EXEC_FILE" ] && [ -f "$LLM_RESPONSE_CLAUDE_EXEC_FILE" ]; then
  echo "Reading from Claude execution file: $LLM_RESPONSE_CLAUDE_EXEC_FILE" >&2
  RAW=$(cat "$LLM_RESPONSE_CLAUDE_EXEC_FILE")
  # Auto-detect: if valid JSON with .result → extract, otherwise use raw content
  if command -v jq &>/dev/null && echo "$RAW" | jq empty 2>/dev/null; then
    EXTRACTED=$(echo "$RAW" | jq -r '.[] | select(.type == "result") | .result' 2>/dev/null)
    if [ -n "$EXTRACTED" ] && [ "$EXTRACTED" != "null" ]; then
      CONTENT="$EXTRACTED"
    else
      CONTENT="$RAW"
    fi
  else
    CONTENT="$RAW"
  fi
  if [ -z "$CONTENT" ]; then
    echo "::error::Empty content from Claude execution file" >&2
    exit 1
  fi
elif [ -f "$LLM_API_RESPONSE_FILE" ]; then
  echo "Reading from API response file: $LLM_API_RESPONSE_FILE" >&2
  CONTENT=$(cat "$LLM_API_RESPONSE_FILE")
elif [ ! -t 0 ]; then
  echo "Reading from stdin" >&2
  CONTENT=$(cat)
else
  echo "::error::No input source available (LLM_RESPONSE_CLAUDE_EXEC_FILE, LLM_API_RESPONSE_FILE, or stdin)" >&2
  exit 1
fi

# Strip code fences (LLMs sometimes wrap output in ```markdown ... ```)
CONTENT=$(echo "$CONTENT" | sed '/^```[a-zA-Z]*$/d; /^```$/d')

# Guard: detect error messages that should never be published
ERROR_PATTERNS="outside the allowed working directory|cannot be accessed|I cannot|I'm unable to|error occurred|ENOENT|No such file"
if echo "$CONTENT" | grep -qiE "$ERROR_PATTERNS"; then
  echo "::error::LLM response looks like an error, not valid content:" >&2
  echo "$CONTENT" | head -5 >&2
  exit 1
fi

# Save cleaned content
echo "$CONTENT" > "$LLM_RESPONSE_PARSED"

# Check for empty or whitespace-only content
CONTENT_LENGTH=$(echo -n "$CONTENT" | wc -c | tr -d ' ')
if [ "$CONTENT_LENGTH" -lt 50 ]; then
  echo "::error::Empty or too short response from LLM ($CONTENT_LENGTH chars)" >&2
  exit 1
fi

echo "=== Generated content (first 20 lines) ===" >&2
head -20 "$LLM_RESPONSE_PARSED" >&2
echo "=== Content length: $CONTENT_LENGTH chars ===" >&2

echo "Output saved to $LLM_RESPONSE_PARSED" >&2
