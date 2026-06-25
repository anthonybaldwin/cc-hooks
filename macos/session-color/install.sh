#!/usr/bin/env bash
# CC Hooks — session-color install
#
# Copies the hook script to ~/.claude/hooks/ and registers the status->color
# hooks in ~/.claude/settings.json. Idempotent and additive: existing hooks
# (e.g. notifications) on the same events are preserved; re-running just
# refreshes the session-color entries.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
HOOKS_DIR="$HOME/.claude/hooks"
SETTINGS="$HOME/.claude/settings.json"
DEST="$HOOKS_DIR/session-color.sh"

mkdir -p "$HOOKS_DIR"
cp "$SCRIPT_DIR/session-color.sh" "$DEST"
chmod +x "$DEST"
echo "Installed $DEST"

[[ -f "$SETTINGS" ]] && cp "$SETTINGS" "$SETTINGS.bak" && echo "Backed up settings.json -> settings.json.bak"

python3 - "$SETTINGS" <<'PY'
import json, os, sys

settings_path = sys.argv[1]
CMD = "~/.claude/hooks/session-color.sh"

# event -> status argument
MAPPING = {
    "SessionStart":       "reset",
    "UserPromptSubmit":   "working",
    "PostToolUse":        "working",
    "PostToolUseFailure": "working",
    "ElicitationResult":  "working",
    "Notification":       "done",
    "PermissionRequest":  "needs",
    "Elicitation":        "needs",
    "Stop":               "done",
    "SessionEnd":         "reset",
}

try:
    with open(settings_path) as f:
        settings = json.load(f)
except FileNotFoundError:
    settings = {}

hooks = settings.setdefault("hooks", {})

for event, arg in MAPPING.items():
    blocks = hooks.setdefault(event, [])
    if not blocks:
        blocks.append({"matcher": "", "hooks": []})
    # Drop any prior session-color command on this event (across all blocks)...
    for b in blocks:
        b["hooks"] = [h for h in b.get("hooks", []) if CMD not in h.get("command", "")]
    # ...then append the current one to the first block.
    blocks[0].setdefault("hooks", []).append(
        {"type": "command", "command": f"{CMD} {arg}"}
    )

os.makedirs(os.path.dirname(settings_path), exist_ok=True)
with open(settings_path, "w") as f:
    json.dump(settings, f, indent=2)
    f.write("\n")

print(f"Registered session-color on {len(MAPPING)} events in {settings_path}")
PY

echo "Done! Restart Claude Code to activate."
