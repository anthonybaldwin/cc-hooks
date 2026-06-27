#!/usr/bin/env bash
# CC Hooks — session-color uninstall (Linux)
#
# Removes the session-color hooks from ~/.claude/settings.json (leaving other
# hooks intact) and resets the terminal background. The hook script itself is
# left in ~/.claude/hooks/ — delete it manually if desired.

set -euo pipefail

SETTINGS="$HOME/.claude/settings.json"

if [[ ! -f "$SETTINGS" ]]; then
    echo "No settings.json — nothing to uninstall"
    exit 0
fi

cp "$SETTINGS" "$SETTINGS.bak"

python3 - "$SETTINGS" <<'PY'
import json, sys

settings_path = sys.argv[1]
CMD = "session-color.sh"

with open(settings_path) as f:
    settings = json.load(f)

hooks = settings.get("hooks", {})
for event in list(hooks.keys()):
    blocks = hooks.get(event, [])
    for b in blocks:
        b["hooks"] = [h for h in b.get("hooks", []) if CMD not in h.get("command", "")]
    # Drop blocks left with no hooks, and events left with no blocks.
    blocks = [b for b in blocks if b.get("hooks")]
    if blocks:
        hooks[event] = blocks
    else:
        del hooks[event]

with open(settings_path, "w") as f:
    json.dump(settings, f, indent=2)
    f.write("\n")

print("Removed session-color hooks from", settings_path)
PY

# Reset background on the current terminal, if any.
printf '\033]111\007' > /dev/tty 2>/dev/null || true

echo "Done."
