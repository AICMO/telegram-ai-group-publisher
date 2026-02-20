#!/bin/bash
# Makes LLM API calls (Claude, OpenAI, Gemini, Vertex AI)
# Required env vars (per provider): ANTHROPIC_API_KEY | OPENAI_API_KEY | GOOGLE_API_KEY | GOOGLE_APPLICATION_CREDENTIALS_JSON + VERTEX_PROJECT
# Optional env vars: PROVIDER, MODEL, MAX_TOKENS, VERTEX_REGION
# Reads prompt from: PROMPT_FILE_TMP_WITH_DATA
# Outputs: LLM response to stdout

set -eo pipefail

PROVIDER="${PROVIDER:-vertex}"
MAX_TOKENS="${MAX_TOKENS:-4096}"
PROMPT_FILE_TMP_WITH_DATA="${PROMPT_FILE_TMP_WITH_DATA:-/tmp/user_prompt.txt}"
TMP_REQUEST_FILE="/tmp/llm_request.json"

# Set default model based on provider
if [ -z "$MODEL" ]; then
  case $PROVIDER in
    claude) MODEL="${CLAUDE_MODEL:-claude-opus-4-5-20251101}" ;;
    openai) MODEL="${OPENAI_MODEL:-gpt-4o}" ;;
    gemini) MODEL="${GEMINI_MODEL:-gemini-2.5-pro}" ;;
    vertex) MODEL="${VERTEX_MODEL:-gemini-2.5-pro}" ;;
  esac
fi

# Read prompt
USER_PROMPT=$(cat "$PROMPT_FILE_TMP_WITH_DATA")

call_claude() {
  echo "Calling Claude ($MODEL)..." >&2

  if [ -z "$ANTHROPIC_API_KEY" ]; then
    echo "::error::ANTHROPIC_API_KEY not set"
    exit 1
  fi

  jq -n \
    --arg model "$MODEL" \
    --argjson max_tokens "$MAX_TOKENS" \
    --arg user "$USER_PROMPT" \
    '{model: $model, max_tokens: $max_tokens, messages: [{role: "user", content: $user}]}' \
    > "$TMP_REQUEST_FILE"

  RESPONSE=$(curl -s -X POST "https://api.anthropic.com/v1/messages" \
    -H "Content-Type: application/json" \
    -H "x-api-key: $ANTHROPIC_API_KEY" \
    -H "anthropic-version: 2023-06-01" \
    -d @"$TMP_REQUEST_FILE")

  if echo "$RESPONSE" | jq -e '.error' > /dev/null 2>&1; then
    echo "::error::Claude API error: $(echo "$RESPONSE" | jq -r '.error.message')" >&2
    exit 1
  fi

  echo "$RESPONSE" | jq -r '.content[0].text'
}

call_openai() {
  echo "Calling OpenAI ($MODEL)..." >&2

  if [ -z "$OPENAI_API_KEY" ]; then
    echo "::error::OPENAI_API_KEY not set"
    exit 1
  fi

  jq -n \
    --arg model "$MODEL" \
    --argjson max_tokens "$MAX_TOKENS" \
    --arg user "$USER_PROMPT" \
    '{model: $model, max_tokens: $max_tokens, messages: [{role: "user", content: $user}]}' \
    > "$TMP_REQUEST_FILE"

  RESPONSE=$(curl -s -X POST "https://api.openai.com/v1/chat/completions" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer $OPENAI_API_KEY" \
    -d @"$TMP_REQUEST_FILE")

  if echo "$RESPONSE" | jq -e '.error' > /dev/null 2>&1; then
    echo "::error::OpenAI API error: $(echo "$RESPONSE" | jq -r '.error.message')" >&2
    exit 1
  fi

  echo "$RESPONSE" | jq -r '.choices[0].message.content'
}

call_gemini() {
  echo "Calling Gemini ($MODEL)..." >&2

  if [ -z "$GOOGLE_API_KEY" ]; then
    echo "::error::GOOGLE_API_KEY not set"
    exit 1
  fi

  jq -n \
    --argjson max_tokens "$MAX_TOKENS" \
    --arg user "$USER_PROMPT" \
    '{contents: [{role: "user", parts: [{text: $user}]}], generationConfig: {maxOutputTokens: $max_tokens}}' \
    > "$TMP_REQUEST_FILE"

  RESPONSE=$(curl -s -X POST "https://generativelanguage.googleapis.com/v1beta/models/${MODEL}:generateContent?key=$GOOGLE_API_KEY" \
    -H "Content-Type: application/json" \
    -d @"$TMP_REQUEST_FILE")

  if echo "$RESPONSE" | jq -e '.error' > /dev/null 2>&1; then
    echo "::error::Gemini API error: $(echo "$RESPONSE" | jq -r '.error.message')" >&2
    exit 1
  fi

  echo "$RESPONSE" | jq -r '.candidates[0].content.parts[0].text'
}

call_vertex() {
  echo "Calling Vertex AI ($MODEL)..." >&2

  VERTEX_REGION="${VERTEX_REGION:-us-central1}"

  if [ -z "$GOOGLE_APPLICATION_CREDENTIALS_JSON" ]; then
    echo "::error::GOOGLE_APPLICATION_CREDENTIALS_JSON not set"
    exit 1
  fi

  # Require base64-encoded credentials
  SA_JSON=$(echo "$GOOGLE_APPLICATION_CREDENTIALS_JSON" | base64 -d 2>/dev/null)
  if [ -z "$SA_JSON" ] || ! echo "$SA_JSON" | jq -e '.client_email' > /dev/null 2>&1; then
    echo "::error::GOOGLE_APPLICATION_CREDENTIALS_JSON must be base64-encoded. Encode it with: base64 < service-account.json" >&2
    exit 1
  fi

  # Extract project from env var or fall back to credentials JSON
  VERTEX_PROJECT="${VERTEX_PROJECT:-$(echo "$SA_JSON" | jq -r '.project_id')}"
  if [ -z "$VERTEX_PROJECT" ] || [ "$VERTEX_PROJECT" = "null" ]; then
    echo "::error::VERTEX_PROJECT not set and could not extract project_id from credentials" >&2
    exit 1
  fi

  CLIENT_EMAIL=$(echo "$SA_JSON" | jq -r '.client_email')
  PRIVATE_KEY_RAW=$(echo "$SA_JSON" | jq -r '.private_key')

  if [ -z "$CLIENT_EMAIL" ] || [ "$CLIENT_EMAIL" = "null" ]; then
    echo "::error::Could not extract client_email from service account JSON" >&2
    exit 1
  fi

  # Write private key to temp file (openssl needs a file)
  TMP_KEY_FILE=$(mktemp)
  trap 'rm -f "$TMP_KEY_FILE"' EXIT
  echo "$PRIVATE_KEY_RAW" > "$TMP_KEY_FILE"

  # Build JWT for OAuth2 token exchange
  NOW=$(date +%s)
  EXP=$((NOW + 3600))
  SCOPE="https://www.googleapis.com/auth/cloud-platform"
  AUD="https://oauth2.googleapis.com/token"

  b64url() { openssl enc -base64 -A | tr '+/' '-_' | tr -d '='; }

  JWT_HEADER=$(printf '{"alg":"RS256","typ":"JWT"}' | b64url)
  JWT_CLAIM=$(printf '{"iss":"%s","scope":"%s","aud":"%s","iat":%d,"exp":%d}' \
    "$CLIENT_EMAIL" "$SCOPE" "$AUD" "$NOW" "$EXP" | b64url)

  SIGNATURE=$(printf '%s.%s' "$JWT_HEADER" "$JWT_CLAIM" \
    | openssl dgst -sha256 -sign "$TMP_KEY_FILE" -binary | b64url)

  JWT="${JWT_HEADER}.${JWT_CLAIM}.${SIGNATURE}"

  # Exchange JWT for access token
  TOKEN_RESPONSE=$(curl -s -X POST "$AUD" \
    -H "Content-Type: application/x-www-form-urlencoded" \
    -d "grant_type=urn%3Aietf%3Aparams%3Aoauth%3Agrant-type%3Ajwt-bearer&assertion=${JWT}")

  ACCESS_TOKEN=$(echo "$TOKEN_RESPONSE" | jq -r '.access_token')
  if [ -z "$ACCESS_TOKEN" ] || [ "$ACCESS_TOKEN" = "null" ]; then
    echo "::error::Failed to get access token: $(echo "$TOKEN_RESPONSE" | jq -r '.error_description // .error // "unknown error"')" >&2
    exit 1
  fi

  rm -f "$TMP_KEY_FILE"

  # Build request (same format as Gemini API)
  jq -n \
    --argjson max_tokens "$MAX_TOKENS" \
    --arg user "$USER_PROMPT" \
    '{contents: [{role: "user", parts: [{text: $user}]}], generationConfig: {maxOutputTokens: $max_tokens}}' \
    > "$TMP_REQUEST_FILE"

  ENDPOINT="https://${VERTEX_REGION}-aiplatform.googleapis.com/v1/projects/${VERTEX_PROJECT}/locations/${VERTEX_REGION}/publishers/google/models/${MODEL}:generateContent"

  RESPONSE=$(curl -s -X POST "$ENDPOINT" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer $ACCESS_TOKEN" \
    -d @"$TMP_REQUEST_FILE")

  if echo "$RESPONSE" | jq -e '.error' > /dev/null 2>&1; then
    echo "::error::Vertex AI API error: $(echo "$RESPONSE" | jq -r '.error.message')" >&2
    exit 1
  fi

  echo "$RESPONSE" | jq -r '.candidates[0].content.parts[0].text'
}

# Main
case $PROVIDER in
  claude) call_claude ;;
  openai) call_openai ;;
  gemini) call_gemini ;;
  vertex) call_vertex ;;
  *) echo "::error::Unknown provider: $PROVIDER" >&2; exit 1 ;;
esac
