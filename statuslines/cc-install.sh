#!/usr/bin/env bash
set -euo pipefail

REPO_RAW="https://raw.githubusercontent.com/bradsec/vibespec/main"
CLAUDE_CONFIG_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
HOOK_DEST="$CLAUDE_CONFIG_DIR/hooks/cc-statusline.js"
SETTINGS="$CLAUDE_CONFIG_DIR/settings.json"

echo "Installing Claude Code statusline..."
mkdir -p "$CLAUDE_CONFIG_DIR/hooks"

LOCAL_JS="$(dirname "${BASH_SOURCE[0]}")/cc-statusline.js"
if [[ -f "$LOCAL_JS" ]]; then
    cp "$LOCAL_JS" "$HOOK_DEST"
elif command -v curl &>/dev/null; then
    curl -fsSL "${REPO_RAW}/statuslines/cc-statusline.js" -o "$HOOK_DEST"
elif command -v wget &>/dev/null; then
    wget -qO "$HOOK_DEST" "${REPO_RAW}/statuslines/cc-statusline.js"
else
    echo "Error: neither curl nor wget found and no local copy available." >&2
    exit 1
fi

chmod +x "$HOOK_DEST"
echo "Installed: $HOOK_DEST"

# Embed the absolute node path so the statusline works under the non-login
# shell Claude Code uses to run it, where an nvm-managed node is not on PATH.
NODE_BIN="$(command -v node 2>/dev/null || true)"
# Single quotes keep shell metacharacters in installation paths literal.
shell_quote() {
    local value="${1//\'/\'\\\'\'}"
    printf "'%s'" "$value"
}
if [[ -n "$NODE_BIN" ]]; then
    STATUSLINE_CMD="$(shell_quote "$NODE_BIN") $(shell_quote "$HOOK_DEST")"
else
    STATUSLINE_CMD="node $(shell_quote "$HOOK_DEST")"
    echo ""
    echo "Warning: node not found on PATH."
    echo "The statusline runs via node. Install Node.js (e.g. via nvm) and make sure"
    echo "it is on PATH for the shell Claude Code launches, then re-run this installer"
    echo "to embed the absolute node path. Writing the configuration anyway."
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
    except json.JSONDecodeError as exc:
        raise SystemExit(f"Error: refusing to overwrite invalid JSON in {settings_path}: {exc}")
if not isinstance(cfg, dict):
    raise SystemExit(f"Error: expected a JSON object in {settings_path}; leaving it unchanged")

status_line = cfg.get("statusLine")
if not isinstance(status_line, dict):
    status_line = {}
status_line.update({"type": "command", "command": statusline_cmd})
status_line.setdefault("refreshInterval", 5)
cfg["statusLine"] = status_line
settings_path.write_text(json.dumps(cfg, indent=2) + "\n", encoding="utf-8")
PY
    echo "Updated: $SETTINGS"
elif [[ -n "$NODE_BIN" ]]; then
    SETTINGS="$SETTINGS" STATUSLINE_CMD="$STATUSLINE_CMD" node -e "
        const fs = require('fs');
        const p = process.env.SETTINGS;
        const cmd = process.env.STATUSLINE_CMD;
        let cfg = {};
        if (fs.existsSync(p)) cfg = JSON.parse(fs.readFileSync(p, 'utf8'));
        if (typeof cfg !== 'object' || cfg === null || Array.isArray(cfg)) {
            throw new Error('Expected a JSON object; leaving settings unchanged');
        }
        const statusLine = cfg.statusLine && typeof cfg.statusLine === 'object' && !Array.isArray(cfg.statusLine)
            ? cfg.statusLine
            : {};
        statusLine.type = 'command';
        statusLine.command = cmd;
        if (statusLine.refreshInterval === undefined) statusLine.refreshInterval = 5;
        cfg.statusLine = statusLine;
        fs.writeFileSync(p, JSON.stringify(cfg, null, 2) + '\n');
    "
    echo "Updated: $SETTINGS"
else
    echo ""
    echo "Warning: neither python3 nor node found to edit JSON."
    echo "Add to $SETTINGS:"
    echo "  {\"statusLine\": {\"type\": \"command\", \"command\": \"$STATUSLINE_CMD\", \"refreshInterval\": 5}}"
fi

echo ""
echo "Restart Claude Code to activate the statusline."
