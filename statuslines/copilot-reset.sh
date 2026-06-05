#!/usr/bin/env bash
set -euo pipefail

SETTINGS="${HOME}/.copilot/settings.json"

echo "Resetting GitHub Copilot CLI statusline to default..."

if [[ ! -f "$SETTINGS" ]]; then
    echo "No settings file found at $SETTINGS — nothing to reset."
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

flags = cfg.get("feature_flags")
if isinstance(flags, dict) and isinstance(flags.get("enabled"), list):
    flags["enabled"] = [f for f in flags["enabled"] if f != "STATUS_LINE"]
    if not flags["enabled"]:
        cfg.pop("feature_flags", None)

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
        if (cfg.feature_flags?.enabled) {
            cfg.feature_flags.enabled = cfg.feature_flags.enabled.filter(f => f !== 'STATUS_LINE');
            if (cfg.feature_flags.enabled.length === 0) delete cfg.feature_flags;
        }
        fs.writeFileSync(p, JSON.stringify(cfg, null, 2) + '\n');
    "
else
    echo "Error: neither python3 nor node found to edit JSON." >&2
    echo "Manually remove the \"statusLine\" key and STATUS_LINE flag from $SETTINGS." >&2
    exit 1
fi

echo "Removed statusLine from $SETTINGS"
echo "Restart GitHub Copilot CLI (or run /restart) to apply."
