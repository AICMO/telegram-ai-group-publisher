#!/bin/bash
# Builds LLM prompt: combines prompt file with data file
# Required env vars: PROMPT_FILE, DATA_FILE
# Outputs: PROMPT_FILE_TMP_WITH_DATA

set -eo pipefail

PROMPT_FILE_TMP_WITH_DATA="${PROMPT_FILE_TMP_WITH_DATA:-/tmp/user_prompt.txt}"

echo "=== Building prompt from $PROMPT_FILE ===" >&2

cat "$PROMPT_FILE" > "$PROMPT_FILE_TMP_WITH_DATA"
echo -e "\n---\nData:" >> "$PROMPT_FILE_TMP_WITH_DATA"
cat "$DATA_FILE" >> "$PROMPT_FILE_TMP_WITH_DATA"

echo "Prompt saved to $PROMPT_FILE_TMP_WITH_DATA" >&2

# Log prompt stats for debugging
echo "=== Prompt Stats ===" >&2
CHARS=$(wc -c < "$PROMPT_FILE_TMP_WITH_DATA" | tr -d ' ')
WORDS=$(wc -w < "$PROMPT_FILE_TMP_WITH_DATA" | tr -d ' ')
LINES=$(wc -l < "$PROMPT_FILE_TMP_WITH_DATA" | tr -d ' ')
echo "Characters: $CHARS | Words: $WORDS | Lines: $LINES" >&2
echo "" >&2
echo "--- HEAD (2 lines) ---" >&2
head -n 2 "$PROMPT_FILE_TMP_WITH_DATA" >&2
echo "..." >&2
echo "--- TAIL (2 lines) ---" >&2
tail -n 2 "$PROMPT_FILE_TMP_WITH_DATA" >&2
echo "======================" >&2
