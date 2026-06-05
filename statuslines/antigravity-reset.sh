#!/usr/bin/env bash
set -euo pipefail

SETTINGS="${HOME}/.gemini/antigravity-cli/settings.json"

echo "Resetting Antigravity CLI statusline to default..."

if [[ ! -f "$SETTINGS" ]]; then
    echo "No settings file found at $SETTINGS. Nothing to reset."
    exit 0
fi

SETTINGS="$SETTINGS" python3 - <<'PY'
import json
import os
from pathlib import Path

settings_path = Path(os.environ["SETTINGS"])

try:
    cfg = json.loads(settings_path.read_text(encoding="utf-8"))
except json.JSONDecodeError:
    cfg = {}

cfg.pop("statusLine", None)
settings_path.write_text(json.dumps(cfg, indent=2) + "\n", encoding="utf-8")
PY

echo "Removed statusLine from $SETTINGS"
echo "Restart Antigravity CLI to apply."
