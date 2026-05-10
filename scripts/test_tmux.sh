#!/usr/bin/env bash
# Integration test: launches Copilot in tmux, sends a real prompt, waits for
# the post-response statusline payload (req >= 1), then asserts real metrics.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$ROOT_DIR/tmp"
COPILOT_HOME="${COPILOT_HOME:-$HOME/.copilot}"
SETTINGS_PATH="$COPILOT_HOME/settings.json"
BACKUP_PATH="$TMP_DIR/settings.json.test.bak"
PROBE_SCRIPT="$TMP_DIR/statusline_probe.sh"
PAYLOAD_PATH="$TMP_DIR/statusline_payload.json"
PAYLOADS_LOG="$TMP_DIR/statusline_all_payloads.jsonl"
TMUX_LOG="$TMP_DIR/tmux-pane.log"
SESSION_NAME="copilot-statusline-test"
# How long to wait for the first real AI response (seconds)
POLL_TIMEOUT="${POLL_TIMEOUT:-120}"
POLL_INTERVAL=4

command -v tmux >/dev/null 2>&1 || { echo "SKIP: tmux is required"; exit 0; }
command -v jq >/dev/null 2>&1   || { echo "SKIP: jq is required"; exit 0; }
command -v copilot >/dev/null 2>&1 || { echo "SKIP: copilot CLI is required"; exit 0; }

mkdir -p "$TMP_DIR" "$COPILOT_HOME"

# Probe script: appends every payload to the log, and keeps the last one in
# PAYLOAD_PATH. Prints nothing (we don't want the test marker in the rendered
# statusline — it pollutes the visual).
cat > "$PROBE_SCRIPT" <<'PROBE'
#!/usr/bin/env bash
payload="$(cat)"
PAYLOADS_LOG_="__PAYLOADS_LOG__"
PAYLOAD_PATH_="__PAYLOAD_PATH__"
printf '%s\n' "$payload" >> "$PAYLOADS_LOG_"
printf '%s\n' "$payload" > "$PAYLOAD_PATH_"
# Forward to the real statusline so we can see it render
exec "$(dirname "$0")/../../scripts/statusline.sh" <<< "$payload"
PROBE

# Substitute in actual paths (avoids variable expansion quoting issues)
sed -i '' \
  -e "s|__PAYLOADS_LOG__|${PAYLOADS_LOG}|g" \
  -e "s|__PAYLOAD_PATH__|${PAYLOAD_PATH}|g" \
  "$PROBE_SCRIPT"
chmod +x "$PROBE_SCRIPT"

# Backup real settings
if [[ -f "$SETTINGS_PATH" ]]; then
  cp "$SETTINGS_PATH" "$BACKUP_PATH"
else
  echo '{}' > "$SETTINGS_PATH"
fi

cleanup() {
  [[ -f "$BACKUP_PATH" ]] && mv "$BACKUP_PATH" "$SETTINGS_PATH" || true
  tmux kill-session -t "$SESSION_NAME" 2>/dev/null || true
}
trap cleanup EXIT

# Patch settings.json to use the probe script
tmp_json="$(mktemp)"
jq --arg cmd "$PROBE_SCRIPT" '
  .experimental = true
  | .enabledFeatureFlags = ((.enabledFeatureFlags // {}) + {"STATUS_LINE": true})
  | .statusLine = {type: "command", command: $cmd, padding: 1}
  | .footer = ((.footer // {}) + {showCustom: true, showContextWindow: true})
' "$SETTINGS_PATH" > "$tmp_json"
mv "$tmp_json" "$SETTINGS_PATH"

rm -f "$PAYLOAD_PATH" "$PAYLOADS_LOG" "$TMUX_LOG"

# Start Copilot in a detached tmux window
tmux new-session -d -s "$SESSION_NAME" -x 220 -y 40 "cd \"$ROOT_DIR\" && copilot --allow-all"
sleep 5   # wait for Copilot to load and render first (cold) statusline

# Send a simple prompt that will complete quickly
tmux send-keys -t "$SESSION_NAME" "Reply with exactly: TEST_OK" Enter

echo "Waiting up to ${POLL_TIMEOUT}s for a post-response payload (req >= 1)..."
elapsed=0
got_real_payload=0
while (( elapsed < POLL_TIMEOUT )); do
  sleep "$POLL_INTERVAL"
  (( elapsed += POLL_INTERVAL ))

  if [[ ! -f "$PAYLOAD_PATH" ]]; then
    continue
  fi

  req="$(jq -r '.cost.total_premium_requests // 0' "$PAYLOAD_PATH" 2>/dev/null || echo 0)"
  if (( req >= 1 )); then
    got_real_payload=1
    break
  fi
done

# Capture final tmux pane for debugging
tmux capture-pane -t "$SESSION_NAME" -p > "$TMUX_LOG" 2>/dev/null || true

if (( got_real_payload == 0 )); then
  echo "FAIL: never received a payload with req >= 1 within ${POLL_TIMEOUT}s."
  echo "Payloads collected: $(wc -l < "$PAYLOADS_LOG" 2>/dev/null || echo 0)"
  echo "Last payload:"
  cat "$PAYLOAD_PATH" 2>/dev/null || echo "(none)"
  exit 1
fi

# ── Assert real metric values ────────────────────────────────────────────────
fail=0

req="$(jq -r '.cost.total_premium_requests' "$PAYLOAD_PATH")"
ctx_cur="$(jq -r '.context_window.current_context_tokens // 0' "$PAYLOAD_PATH")"
last_in="$(jq -r '.context_window.last_call_input_tokens // 0' "$PAYLOAD_PATH")"
model_id="$(jq -r '.model.id // ""' "$PAYLOAD_PATH")"
ctx_pct="$(jq -r '.context_window.current_context_used_percentage // 0' "$PAYLOAD_PATH")"
ctx_lim="$(jq -r '.context_window.displayed_context_limit // 0' "$PAYLOAD_PATH")"

assert_gt() {
  local label="$1" val="$2" threshold="$3"
  if ! (( val > threshold )); then
    echo "  FAIL: expected ${label} > ${threshold}, got ${val}"
    fail=1
  else
    echo "  OK  : ${label} = ${val}"
  fi
}
assert_nonempty() {
  local label="$1" val="$2"
  if [[ -z "$val" || "$val" == "null" ]]; then
    echo "  FAIL: expected ${label} to be non-empty"
    fail=1
  else
    echo "  OK  : ${label} = ${val}"
  fi
}

echo ""
echo "Asserting post-response metrics:"
assert_gt       "total_premium_requests"       "$req"     0
assert_gt       "last_call_input_tokens"        "$last_in" 0
assert_gt       "current_context_tokens"        "$ctx_cur" 0
assert_gt       "displayed_context_limit"       "$ctx_lim" 0
assert_nonempty "model.id"                      "$model_id"

echo ""
if (( fail == 1 )); then
  echo "FAIL: one or more assertions did not pass."
  echo "Full payload:"
  cat "$PAYLOAD_PATH"
  exit 1
fi

echo "PASS: tmux integration test — all metric assertions passed."
echo "Payloads captured : $(wc -l < "$PAYLOADS_LOG" 2>/dev/null || echo '?')"
echo "Payload file      : $PAYLOAD_PATH"
echo "tmux log          : $TMUX_LOG"
