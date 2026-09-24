#!/usr/bin/env bash
set -euo pipefail

CLAUDE_CONFIG_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
SETTINGS="$CLAUDE_CONFIG_DIR/settings.json"
# Written by cc-install.sh: the statusLine setting from before the install.
BACKUP="$CLAUDE_CONFIG_DIR/statusline.vibespec-backup.json"

echo "Resetting Claude Code statusline..."

if [[ ! -f "$SETTINGS" ]]; then
    echo "No settings file found at $SETTINGS — nothing to reset."
    exit 0
fi

# Both editors below restore the backed-up statusLine when there is one (and
# then delete the backup), else remove the key; settings.json is replaced in
# one step through any symlink to its target.
if command -v python3 &>/dev/null; then
    RESULT="$(SETTINGS="$SETTINGS" BACKUP="$BACKUP" python3 - <<'PY'
import json
import os
import tempfile
from pathlib import Path

settings_path = Path(os.environ["SETTINGS"])
backup_path = Path(os.environ["BACKUP"])

def write_atomic(path, text):
    target = Path(os.path.realpath(path))
    mode = target.stat().st_mode & 0o777
    fd, tmp = tempfile.mkstemp(dir=target.parent, prefix=target.name + ".", suffix=".tmp")
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            f.write(text)
        os.chmod(tmp, mode)
        os.replace(tmp, target)
    except BaseException:
        os.unlink(tmp)
        raise

try:
    cfg = json.loads(settings_path.read_text(encoding="utf-8"))
except json.JSONDecodeError as exc:
    raise SystemExit(f"Error: refusing to overwrite invalid JSON in {settings_path}: {exc}")
if not isinstance(cfg, dict):
    raise SystemExit(f"Error: expected a JSON object in {settings_path}; leaving it unchanged")

previous = None
if backup_path.exists():
    try:
        previous = json.loads(backup_path.read_text(encoding="utf-8")).get("statusLine")
    except (json.JSONDecodeError, AttributeError) as exc:
        raise SystemExit(f"Error: cannot read {backup_path} ({exc}); leaving settings unchanged")

if previous is not None:
    cfg["statusLine"] = previous
else:
    cfg.pop("statusLine", None)
write_atomic(settings_path, json.dumps(cfg, indent=2) + "\n")
backup_path.unlink(missing_ok=True)
print("restored" if previous is not None else "removed")
PY
)"
elif command -v node &>/dev/null; then
    RESULT="$(SETTINGS="$SETTINGS" BACKUP="$BACKUP" node -e "
        const fs = require('fs');
        const path = require('path');
        const p = process.env.SETTINGS;
        const backup = process.env.BACKUP;
        const cfg = JSON.parse(fs.readFileSync(p, 'utf8'));
        if (typeof cfg !== 'object' || cfg === null || Array.isArray(cfg)) {
            throw new Error('Expected a JSON object; leaving settings unchanged');
        }
        let previous = null;
        if (fs.existsSync(backup)) previous = JSON.parse(fs.readFileSync(backup, 'utf8')).statusLine ?? null;
        if (previous !== null) cfg.statusLine = previous;
        else delete cfg.statusLine;
        const target = fs.realpathSync(p);
        const tmp = path.join(path.dirname(target), '.' + path.basename(target) + '.' + process.pid + '.tmp');
        fs.writeFileSync(tmp, JSON.stringify(cfg, null, 2) + '\n', { mode: fs.statSync(target).mode & 0o777 });
        try { fs.renameSync(tmp, target); } catch (e) { fs.rmSync(tmp, { force: true }); throw e; }
        fs.rmSync(backup, { force: true });
        process.stdout.write(previous !== null ? 'restored' : 'removed');
    ")"
else
    echo "Error: neither python3 nor node found to edit JSON." >&2
    echo "Manually remove the \"statusLine\" key from $SETTINGS." >&2
    exit 1
fi

if [[ "$RESULT" == "restored" ]]; then
    echo "Restored your previous statusLine in $SETTINGS"
else
    echo "Removed statusLine from $SETTINGS"
fi
echo "Restart Claude Code to apply."
