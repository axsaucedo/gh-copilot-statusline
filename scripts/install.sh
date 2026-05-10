#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COPILOT_HOME="${COPILOT_HOME:-$HOME/.copilot}"
SETTINGS_PATH="$COPILOT_HOME/settings.json"
TARGET_SCRIPT="$COPILOT_HOME/statusline.sh"
BACKUP_PATH="$COPILOT_HOME/settings.json.bak.$(date +%s)"

command -v jq >/dev/null 2>&1 || { echo "jq is required"; exit 1; }
mkdir -p "$COPILOT_HOME"

cp "$ROOT_DIR/scripts/statusline.sh" "$TARGET_SCRIPT"
chmod +x "$TARGET_SCRIPT"

if [[ -f "$SETTINGS_PATH" ]]; then
  cp "$SETTINGS_PATH" "$BACKUP_PATH"
else
  echo '{}' > "$SETTINGS_PATH"
fi

tmp_json="$(mktemp)"
jq --arg cmd "~/.copilot/statusline.sh" '
  .experimental = true
  | .enabledFeatureFlags = ((.enabledFeatureFlags // {}) + {"STATUS_LINE": true})
  | .statusLine = {type: "command", command: $cmd, padding: 1}
  | .footer = ((.footer // {}) + {
      showContextWindow: true,
      showQuota: true,
      showCustom: true,
      showDirectory: true,
      showBranch: true
    })
' "$SETTINGS_PATH" > "$tmp_json"
mv "$tmp_json" "$SETTINGS_PATH"

echo "Installed statusline script at: $TARGET_SCRIPT"
echo "Updated settings: $SETTINGS_PATH"
echo "Backup saved (if settings existed): $BACKUP_PATH"
echo "Restart Copilot CLI (or run /restart) to apply changes."
