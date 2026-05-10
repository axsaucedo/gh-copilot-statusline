#!/usr/bin/env bash
# Copilot CLI powerline-style statusline
# Reads JSON payload from stdin, renders colored segmented status bar.

payload="$(cat)"

# ── Parse fields ────────────────────────────────────────────────────────────
model="$(printf '%s' "$payload" | jq -r '.model.display_name // .model.id // "?"')"
cwd="$(printf '%s' "$payload" | jq -r '.workspace.current_dir // .cwd // "?"')"
cwd="${cwd/#$HOME/~}"
# Truncate long paths keeping the rightmost components
if [[ ${#cwd} -gt 32 ]]; then
  cwd="…${cwd: -29}"
fi
session_name="$(printf '%s' "$payload" | jq -r '.session_name // empty // ""')"
premium_req="$(printf '%s' "$payload" | jq -r '.cost.total_premium_requests // 0')"
ctx_pct="$(printf '%s' "$payload" | jq -r '.context_window.current_context_used_percentage // .context_window.used_percentage // empty')"
ctx_cur="$(printf '%s' "$payload" | jq -r '.context_window.current_context_tokens // 0')"
ctx_lim="$(printf '%s' "$payload" | jq -r '.context_window.displayed_context_limit // .context_window.context_window_size // 0')"
last_in="$(printf '%s' "$payload" | jq -r '.context_window.last_call_input_tokens // 0')"
last_out="$(printf '%s' "$payload" | jq -r '.context_window.last_call_output_tokens // 0')"

# ── Formatting helpers ──────────────────────────────────────────────────────
# Powerline arrow separators (requires Nerd Fonts / powerline-patched font)
SEP=''   # U+E0B0 solid right-pointing arrow
THIN=''  # U+E0B1 thin right-pointing arrow

# ANSI color helpers: fg FG BG, reset R
fg() { printf '\033[38;5;%sm' "$1"; }
bg() { printf '\033[48;5;%sm' "$1"; }
R=$'\033[0m'

# Transition: end block at old bg, start next bg, print separator
# Usage: trans <old_bg_color> <new_bg_color>
trans() { printf '%s%s%s%s' "$(fg "$1")" "$(bg "$2")" "$SEP" "$(fg 255)"; }
# End the last block (transition to transparent)
trans_end() { printf '%s%s%s%s' "$R" "$(fg "$1")" "$SEP" "$R"; }

# Pretty-print token count: 1234 → 1.2K, 12345 → 12K
fmt_tok() {
  local n="$1"
  if [[ "$n" -ge 1000 ]]; then
    printf '%dK' $(( (n + 500) / 1000 ))
  else
    printf '%d' "$n"
  fi
}

# ── Segment values ──────────────────────────────────────────────────────────
# Trim model string to keep it compact
model_short="${model:0:24}"

# Context % color: green < 60%, yellow 60-85%, red > 85%
if [[ -z "$ctx_pct" || "$ctx_pct" == "null" ]]; then
  ctx_label="ctx:—"
  ctx_color=240   # dim gray for cold-start
else
  ctx_label="ctx:${ctx_pct}%"
  if   (( ctx_pct >= 85 )); then ctx_color=196   # bright red
  elif (( ctx_pct >= 60 )); then ctx_color=214   # orange
  else                           ctx_color=71    # muted green
  fi
fi

# Request count
if [[ "$premium_req" == "0" ]]; then
  req_label="req:—"
else
  req_label="req:${premium_req}"
fi

# Last-turn tokens
if [[ "$last_in" == "0" && "$last_out" == "0" ]]; then
  last_label="last:—"
else
  last_label="last:$(fmt_tok "$last_in")→$(fmt_tok "$last_out")"
fi

# Context window (only show if we have data)
if [[ "$ctx_lim" == "0" ]]; then
  ctx_window=""
else
  ctx_window=" $(fmt_tok "$ctx_cur")/$(fmt_tok "$ctx_lim")"
fi

# Session segment (skip if empty/null)
session_seg=""
if [[ -n "$session_name" && "$session_name" != "null" ]]; then
  session_seg="${session_name:0:28}"
fi

# ── Color palette ───────────────────────────────────────────────────────────
C_MODEL_BG=24      # steel blue bg
C_CWD_BG=236       # near-black bg
C_SES_BG=237       # dark gray bg
C_REQ_BG=30        # teal bg
C_CTX_BG=235       # darkest gray (ctx% uses fg color)
C_LAST_BG=54       # purple bg
FG=255             # white fg for all segments

# ── Render ──────────────────────────────────────────────────────────────────
printf '%s' "$(bg $C_MODEL_BG)$(fg $FG) ${model_short} "

if [[ -n "$session_seg" ]]; then
  printf '%s' "$(trans $C_MODEL_BG $C_CWD_BG) ${cwd} "
  printf '%s' "$(trans $C_CWD_BG $C_SES_BG) ${session_seg} "
  printf '%s' "$(trans $C_SES_BG $C_REQ_BG) ${req_label} "
  printf '%s' "$(trans $C_REQ_BG $C_CTX_BG)$(fg $ctx_color) ${ctx_label}${ctx_window} "
  printf '%s' "$(trans $C_CTX_BG $C_LAST_BG)$(fg $FG) ${last_label} "
  printf '%s' "$(trans_end $C_LAST_BG)"
else
  printf '%s' "$(trans $C_MODEL_BG $C_CWD_BG) ${cwd} "
  printf '%s' "$(trans $C_CWD_BG $C_REQ_BG) ${req_label} "
  printf '%s' "$(trans $C_REQ_BG $C_CTX_BG)$(fg $ctx_color) ${ctx_label}${ctx_window} "
  printf '%s' "$(trans $C_CTX_BG $C_LAST_BG)$(fg $FG) ${last_label} "
  printf '%s' "$(trans_end $C_LAST_BG)"
fi
