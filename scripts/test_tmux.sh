#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$ROOT_DIR/tmp"
COPILOT_HOME="${COPILOT_HOME:-$HOME/.copilot}"
SETTINGS_PATH="$COPILOT_HOME/settings.json"
BACKUP_PATH="$TMP_DIR/settings.json.test.bak"
PROBE_SCRIPT="$TMP_DIR/statusline_probe.sh"
PAYLOAD_PATH="$TMP_DIR/statusline_payload.json"
TMUX_LOG="$TMP_DIR/tmux-pane.log"
SESSION_NAME="copilot-statusline-test"

command -v tmux >/dev/null 2>&1 || { echo "tmux is required"; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "jq is required"; exit 1; }
command -v copilot >/dev/null 2>&1 || { echo "copilot CLI is required"; exit 1; }

mkdir -p "$TMP_DIR" "$COPILOT_HOME"

cat > "$PROBE_SCRIPT" <<EOF
#!/usr/bin/env bash
set -euo pipefail
payload="\$(cat)"
printf '%s\n' "\$payload" > "$PAYLOAD_PATH"
printf 'COPILOT_STATUSLINE_TEST'
EOF
chmod +x "$PROBE_SCRIPT"

if [[ -f "$SETTINGS_PATH" ]]; then
  cp "$SETTINGS_PATH" "$BACKUP_PATH"
else
  echo '{}' > "$SETTINGS_PATH"
fi

cleanup() {
  if [[ -f "$BACKUP_PATH" ]]; then
    mv "$BACKUP_PATH" "$SETTINGS_PATH"
  fi
  tmux kill-session -t "$SESSION_NAME" 2>/dev/null || true
}
trap cleanup EXIT

tmp_json="$(mktemp)"
jq --arg cmd "$PROBE_SCRIPT" '
  .experimental = true
  | .enabledFeatureFlags = ((.enabledFeatureFlags // {}) + {"STATUS_LINE": true})
  | .statusLine = {type: "command", command: $cmd, padding: 1}
  | .footer = ((.footer // {}) + {showCustom: true, showContextWindow: true, showQuota: true})
' "$SETTINGS_PATH" > "$tmp_json"
mv "$tmp_json" "$SETTINGS_PATH"

rm -f "$PAYLOAD_PATH" "$TMUX_LOG"
tmux new-session -d -s "$SESSION_NAME" "cd \"$ROOT_DIR\" && copilot -i 'Respond with exactly OK' --allow-all"
sleep 5
tmux send-keys -t "$SESSION_NAME" Enter
sleep 20
tmux capture-pane -t "$SESSION_NAME" -p > "$TMUX_LOG" || true

if [[ ! -f "$PAYLOAD_PATH" ]]; then
  echo "FAIL: statusline payload was not captured."
  exit 1
fi

grep -q "COPILOT_STATUSLINE_TEST" "$TMUX_LOG" || {
  echo "FAIL: statusline probe marker not found in tmux output."
  exit 1
}

jq -e '.context_window != null and .cost != null and .model != null' "$PAYLOAD_PATH" >/dev/null

echo "PASS: tmux integration test captured statusline payload and marker."
echo "Captured payload: $PAYLOAD_PATH"
echo "Captured tmux output: $TMUX_LOG"
