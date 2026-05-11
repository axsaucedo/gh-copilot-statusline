# gh-copilot-statusline

Simple, reusable setup for GitHub Copilot CLI experimental statusline.

## What it shows

`scripts/statusline.sh` prints:

- Model
- Current directory
- Session name
- Cumulative premium request count
- Context usage (current/limit and percentage)
- Last call input/output tokens
- Credit placeholder (`n/a`) because remaining monthly credit is not exposed in payload

## Install

Prerequisites:

- `copilot`
- `jq`

Run:

```bash
./scripts/install.sh
```

Then restart Copilot CLI (or run `/restart` in session).

## Test (tmux integration)

Prerequisites:

- `tmux`
- `jq`
- `copilot`

Run:

```bash
./scripts/test_tmux.sh
```

This test:

1. Creates a temporary probe statusline script.
2. Applies temporary Copilot settings.
3. Launches Copilot in tmux and captures pane output to `./tmp/tmux-pane.log`.
4. Captures statusline payload to `./tmp/statusline_payload.json`.
5. Asserts probe marker and required payload fields.

## Local scratch space

`./tmp/` is intentionally gitignored and reserved for local test artifacts and helper scripts.
