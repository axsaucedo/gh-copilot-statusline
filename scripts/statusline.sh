#!/usr/bin/env bash
set -euo pipefail

payload="$(cat)"

model="$(printf '%s' "$payload" | jq -r '.model.display_name // .model.id // "unknown"')"
cwd="$(printf '%s' "$payload" | jq -r '.workspace.current_dir // .cwd // "?"')"
cwd="${cwd/#$HOME/~}"
session_name="$(printf '%s' "$payload" | jq -r '.session_name // "session"')"
premium_requests="$(printf '%s' "$payload" | jq -r '.cost.total_premium_requests // 0')"
ctx_used_pct="$(printf '%s' "$payload" | jq -r '.context_window.current_context_used_percentage // .context_window.used_percentage // "n/a"')"
ctx_current="$(printf '%s' "$payload" | jq -r '.context_window.current_context_tokens // .context_window.total_tokens // "n/a"')"
ctx_limit="$(printf '%s' "$payload" | jq -r '.context_window.displayed_context_limit // .context_window.context_window_size // "n/a"')"
last_in="$(printf '%s' "$payload" | jq -r '.context_window.last_call_input_tokens // "n/a"')"
last_out="$(printf '%s' "$payload" | jq -r '.context_window.last_call_output_tokens // "n/a"')"

# Remaining monthly credit is not exposed in this payload.
credit="n/a"

printf 'statusline | %s | %s | %s | req:%s | ctx:%s%% (%s/%s) | last:%s/%s tok | credit:%s' \
  "$model" "$cwd" "$session_name" "$premium_requests" "$ctx_used_pct" "$ctx_current" "$ctx_limit" "$last_in" "$last_out" "$credit"
