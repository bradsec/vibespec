#!/usr/bin/env bash
set -euo pipefail

SETTINGS="${HOME}/.gemini/antigravity-cli/settings.json"

echo "Resetting Antigravity CLI statusline to default..."

if [[ ! -f "$SETTINGS" ]]; then
    echo "No settings file found at $SETTINGS. Nothing to reset."
    exit 0
fi

if command -v python3 &>/dev/null; then
    SETTINGS="$SETTINGS" python3 - <<'PY'
import json
import os
from pathlib import Path

settings_path = Path(os.environ["SETTINGS"])

try:
    cfg = json.loads(settings_path.read_text(encoding="utf-8"))
except json.JSONDecodeError:
    cfg = {}
if not isinstance(cfg, dict):
    cfg = {}

cfg.pop("statusLine", None)
settings_path.write_text(json.dumps(cfg, indent=2) + "\n", encoding="utf-8")
PY
elif command -v node &>/dev/null; then
    SETTINGS="$SETTINGS" node -e "
        const fs = require('fs');
        const p = process.env.SETTINGS;
        let cfg = {};
        try { cfg = JSON.parse(fs.readFileSync(p, 'utf8')); } catch(e) {}
        if (typeof cfg !== 'object' || cfg === null) cfg = {};
        delete cfg.statusLine;
        fs.writeFileSync(p, JSON.stringify(cfg, null, 2) + '\n');
    "
else
    echo "Error: neither python3 nor node found to edit JSON." >&2
    echo "Manually remove the \"statusLine\" key from $SETTINGS." >&2
    exit 1
fi

echo "Removed statusLine from $SETTINGS"
echo "Restart Antigravity CLI to apply."
