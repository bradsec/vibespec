#!/usr/bin/env bash
set -euo pipefail

REPO_RAW="https://raw.githubusercontent.com/bradsec/vibespec/main"
HOOK_DEST="${HOME}/.gemini/antigravity-cli/statusline.js"
SETTINGS="${HOME}/.gemini/antigravity-cli/settings.json"

echo "Installing Antigravity CLI statusline..."
mkdir -p "$(dirname "$HOOK_DEST")"

LOCAL_JS="$(dirname "${BASH_SOURCE[0]}")/antigravity-statusline.js"
if [[ -f "$LOCAL_JS" ]]; then
    cp "$LOCAL_JS" "$HOOK_DEST"
elif command -v curl &>/dev/null; then
    curl -fsSL "${REPO_RAW}/statuslines/antigravity-statusline.js" -o "$HOOK_DEST"
elif command -v wget &>/dev/null; then
    wget -qO "$HOOK_DEST" "${REPO_RAW}/statuslines/antigravity-statusline.js"
else
    echo "Error: neither curl nor wget found and no local copy available." >&2
    exit 1
fi

chmod +x "$HOOK_DEST"
echo "Installed: $HOOK_DEST"

# Embed the absolute node path so the statusline works under the non-login
# shell Antigravity CLI uses to run it, where an nvm-managed node is not on PATH.
NODE_BIN="$(command -v node 2>/dev/null || true)"
if [[ -n "$NODE_BIN" ]]; then
    STATUSLINE_CMD="\"$NODE_BIN\" \"${HOOK_DEST}\""
else
    STATUSLINE_CMD="node \"${HOOK_DEST}\""
    echo ""
    echo "Warning: node not found on PATH."
    echo "The statusline runs via node. Install Node.js (e.g. via nvm) and make sure"
    echo "it is on PATH for the shell Antigravity CLI launches, then re-run this"
    echo "installer to embed the absolute node path. Writing the configuration anyway."
fi

mkdir -p "$(dirname "$SETTINGS")"
if command -v python3 &>/dev/null; then
    SETTINGS="$SETTINGS" STATUSLINE_CMD="$STATUSLINE_CMD" python3 - <<'PY'
import json
import os
from pathlib import Path

settings_path = Path(os.environ["SETTINGS"])
statusline_cmd = os.environ["STATUSLINE_CMD"]

cfg = {}
if settings_path.exists():
    try:
        cfg = json.loads(settings_path.read_text(encoding="utf-8"))
    except json.JSONDecodeError:
        cfg = {}
if not isinstance(cfg, dict):
    cfg = {}

cfg["statusLine"] = {
    "type": "command",
    "command": statusline_cmd,
}

settings_path.write_text(json.dumps(cfg, indent=2) + "\n", encoding="utf-8")
PY
    echo "Updated: $SETTINGS"
elif [[ -n "$NODE_BIN" ]]; then
    SETTINGS="$SETTINGS" STATUSLINE_CMD="$STATUSLINE_CMD" node -e "
        const fs = require('fs');
        const p = process.env.SETTINGS;
        const cmd = process.env.STATUSLINE_CMD;
        let cfg = {};
        if (fs.existsSync(p)) { try { cfg = JSON.parse(fs.readFileSync(p, 'utf8')); } catch(e) {} }
        if (typeof cfg !== 'object' || cfg === null) cfg = {};
        cfg.statusLine = { type: 'command', command: cmd };
        fs.writeFileSync(p, JSON.stringify(cfg, null, 2) + '\n');
    "
    echo "Updated: $SETTINGS"
else
    echo ""
    echo "Warning: neither python3 nor node found to edit JSON."
    echo "Add to ${SETTINGS}:"
    echo "  \"statusLine\": {\"type\": \"command\", \"command\": \"${STATUSLINE_CMD}\"}"
fi

echo ""
echo "Restart Antigravity CLI to activate the statusline."
