#!/usr/bin/env bash
set -euo pipefail

REPO_RAW="https://raw.githubusercontent.com/bradsec/vibespec/main"
CLAUDE_CONFIG_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
HOOK_DEST="$CLAUDE_CONFIG_DIR/hooks/cc-statusline.js"
SETTINGS="$CLAUDE_CONFIG_DIR/settings.json"
# The statusLine setting found before the first install, restored by cc-reset.sh.
BACKUP="$CLAUDE_CONFIG_DIR/statusline.vibespec-backup.json"

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

# Both editors below: keep the statusLine found before the first install in
# $BACKUP (a statusLine already running $HOOK_DEST is ours, not the user's),
# and replace settings.json in one step through any symlink to its target.
mkdir -p "$(dirname "$SETTINGS")"
if command -v python3 &>/dev/null; then
    SETTINGS="$SETTINGS" STATUSLINE_CMD="$STATUSLINE_CMD" HOOK_DEST="$HOOK_DEST" BACKUP="$BACKUP" python3 - <<'PY'
import json
import os
import tempfile
from pathlib import Path

settings_path = Path(os.environ["SETTINGS"])
statusline_cmd = os.environ["STATUSLINE_CMD"]
backup_path = Path(os.environ["BACKUP"])

def write_atomic(path, text):
    target = Path(os.path.realpath(path))
    mode = target.stat().st_mode & 0o777 if target.exists() else 0o600
    fd, tmp = tempfile.mkstemp(dir=target.parent, prefix=target.name + ".", suffix=".tmp")
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            f.write(text)
        os.chmod(tmp, mode)
        os.replace(tmp, target)
    except BaseException:
        os.unlink(tmp)
        raise

cfg = {}
if settings_path.exists():
    try:
        cfg = json.loads(settings_path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        raise SystemExit(f"Error: refusing to overwrite invalid JSON in {settings_path}: {exc}")
if not isinstance(cfg, dict):
    raise SystemExit(f"Error: expected a JSON object in {settings_path}; leaving it unchanged")

status_line = cfg.get("statusLine")
ours = isinstance(status_line, dict) and os.environ["HOOK_DEST"] in str(status_line.get("command", ""))
if not ours and not backup_path.exists():
    write_atomic(backup_path, json.dumps({
        "note": "statusLine before the vibespec install; statuslines/cc-reset.sh restores it.",
        "statusLine": status_line,
    }, indent=2) + "\n")
if not isinstance(status_line, dict):
    status_line = {}
status_line.update({"type": "command", "command": statusline_cmd})
status_line.setdefault("refreshInterval", 5)
cfg["statusLine"] = status_line
write_atomic(settings_path, json.dumps(cfg, indent=2) + "\n")
PY
    echo "Updated: $SETTINGS"
elif [[ -n "$NODE_BIN" ]]; then
    SETTINGS="$SETTINGS" STATUSLINE_CMD="$STATUSLINE_CMD" HOOK_DEST="$HOOK_DEST" BACKUP="$BACKUP" node -e "
        const fs = require('fs');
        const path = require('path');
        const p = process.env.SETTINGS;
        const cmd = process.env.STATUSLINE_CMD;
        const backup = process.env.BACKUP;
        const writeAtomic = (file, text) => {
            let target = file;
            try { target = fs.realpathSync(file); } catch (e) { /* new file */ }
            let mode = 0o600;
            try { mode = fs.statSync(target).mode & 0o777; } catch (e) { /* new file */ }
            const tmp = path.join(path.dirname(target), '.' + path.basename(target) + '.' + process.pid + '.tmp');
            fs.writeFileSync(tmp, text, { mode });
            try { fs.renameSync(tmp, target); } catch (e) { fs.rmSync(tmp, { force: true }); throw e; }
        };
        let cfg = {};
        if (fs.existsSync(p)) cfg = JSON.parse(fs.readFileSync(p, 'utf8'));
        if (typeof cfg !== 'object' || cfg === null || Array.isArray(cfg)) {
            throw new Error('Expected a JSON object; leaving settings unchanged');
        }
        const current = cfg.statusLine;
        const ours = current && typeof current === 'object' && String(current.command || '').includes(process.env.HOOK_DEST);
        if (!ours && !fs.existsSync(backup)) {
            writeAtomic(backup, JSON.stringify({
                note: 'statusLine before the vibespec install; statuslines/cc-reset.sh restores it.',
                statusLine: current === undefined ? null : current,
            }, null, 2) + '\n');
        }
        const statusLine = current && typeof current === 'object' && !Array.isArray(current) ? current : {};
        statusLine.type = 'command';
        statusLine.command = cmd;
        if (statusLine.refreshInterval === undefined) statusLine.refreshInterval = 5;
        cfg.statusLine = statusLine;
        writeAtomic(p, JSON.stringify(cfg, null, 2) + '\n');
    "
    echo "Updated: $SETTINGS"
else
    echo ""
    echo "Warning: neither python3 nor node found to edit JSON."
    echo "Add to $SETTINGS:"
    echo "  {\"statusLine\": {\"type\": \"command\", \"command\": \"$STATUSLINE_CMD\", \"refreshInterval\": 5}}"
fi

# Render once with a sample payload, so a broken install shows up now rather
# than as a blank statusline.
if [[ -n "$NODE_BIN" ]]; then
    SAMPLE='{"model":{"display_name":"Claude"},"workspace":{"current_dir":"'"$HOME"'"}}'
    if ! RENDERED="$(printf '%s' "$SAMPLE" | "$NODE_BIN" "$HOOK_DEST" 2>/dev/null)" || [[ -z "$RENDERED" ]]; then
        echo ""
        echo "Warning: the statusline did not render with a sample payload. Check $HOOK_DEST."
    fi
fi

# Project settings take precedence over $SETTINGS in that project.
for project_settings in "$PWD/.claude/settings.json" "$PWD/.claude/settings.local.json"; do
    if [[ -f "$project_settings" && "$(cd "$(dirname "$project_settings")" && pwd -P)/$(basename "$project_settings")" != "$(cd "$(dirname "$SETTINGS")" && pwd -P)/$(basename "$SETTINGS")" ]] \
        && grep -q '"statusLine"' "$project_settings"; then
        echo ""
        echo "Warning: $project_settings sets its own statusLine, which takes precedence in this project."
    fi
done

echo ""
echo "Restart Claude Code to activate the statusline."
