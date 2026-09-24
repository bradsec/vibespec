#!/usr/bin/env bash
set -euo pipefail

CODEX_HOME="${CODEX_HOME:-$HOME/.codex}"
CONFIG="$CODEX_HOME/config.toml"
# Written by codex-install.sh: the [tui] status_line from before the install.
BACKUP="$CODEX_HOME/status_line.vibespec-backup.json"

echo "Resetting Codex CLI statusline..."

if [[ ! -f "$CONFIG" ]]; then
    echo "No config file found at $CONFIG — nothing to reset."
    exit 0
fi

if ! command -v python3 &>/dev/null; then
    echo "Error: Python 3.11 or newer is required to update $CONFIG safely." >&2
    echo "Manually remove the status_line entry from the [tui] section of $CONFIG." >&2
    exit 1
fi

# Put back the status_line from before the install when there is a backup,
# else remove status_line from [tui] so Codex uses its defaults. Similarly
# named keys in other sections are never touched.
RESULT="$(python3 - "$CONFIG" "$BACKUP" <<'PYEOF'
import json
import os
import re
import sys

config_path = sys.argv[1]
backup_path = sys.argv[2]
with open(config_path, 'r', encoding='utf-8') as f:
    content = f.read()

# Keep complete statements together, including multiline strings and arrays.
# This lets edits preserve unrelated TOML text without a serializer dependency.
def statements(text):
    start = 0
    i = 0
    depth = 0
    while i < len(text):
        char = text[i]
        if char == '#':
            end = text.find('\n', i)
            i = len(text) if end < 0 else end
            continue
        if char in ('"', "'"):
            quote = char * (3 if text.startswith(char * 3, i) else 1)
            i += len(quote)
            while i < len(text):
                if text.startswith(quote, i):
                    i += len(quote)
                    if len(quote) == 3:
                        while i < len(text) and text[i] == char:
                            i += 1
                    break
                if char == '"' and text[i] == '\\':
                    i += 2
                else:
                    i += 1
            else:
                raise SystemExit('Error: unterminated TOML string; leaving config unchanged')
            continue
        if char in '[{':
            depth += 1
        elif char in ']}':
            depth -= 1
            if depth < 0:
                raise SystemExit('Error: unbalanced TOML value; leaving config unchanged')
        elif char == '\n' and depth == 0:
            yield text[start:i + 1]
            start = i + 1
        i += 1
    if depth:
        raise SystemExit('Error: unterminated TOML value; leaving config unchanged')
    if start < len(text):
        yield text[start:]

try:
    import tomllib
except ImportError:
    raise SystemExit('Error: Python 3.11 or newer is required to edit TOML safely; leaving config unchanged')
try:
    before = tomllib.loads(content)
except ValueError as exc:
    raise SystemExit('Error: invalid TOML; leaving config unchanged: ' + str(exc))

restore = None
if os.path.exists(backup_path):
    try:
        with open(backup_path, 'r', encoding='utf-8') as f:
            restore = json.load(f)['status_line']
    except (ValueError, KeyError, TypeError) as exc:
        raise SystemExit('Error: cannot read ' + backup_path + ' (' + str(exc) + '); leaving config unchanged')
    if not (isinstance(restore, list) and all(isinstance(item, str) for item in restore)):
        raise SystemExit('Error: ' + backup_path + ' does not hold a list of item names; leaving config unchanged')
# A JSON array of strings is also a valid TOML inline array.
replacement = 'status_line = ' + json.dumps(restore) + '\n' if restore is not None else None

out = []
in_tui = False
seen_tui = False
inserted = False
for statement in statements(content):
    stripped = statement.strip()
    if stripped.startswith('['):
        if in_tui and replacement and not inserted:
            out.append(replacement)
            inserted = True
        in_tui = bool(re.fullmatch(r'''\[\s*(?:tui|"tui"|'tui')\s*\]\s*(?:\#.*)?''', stripped))
        seen_tui = seen_tui or in_tui
    if in_tui and re.match(r'''(?:status_line|"status_line"|'status_line')\s*=''', stripped):
        if replacement and not inserted:
            out.append(replacement)
            inserted = True
        continue
    out.append(statement)

if replacement and not inserted:
    if out and not out[-1].endswith('\n'):
        out.append('\n')
    if not seen_tui:
        out.append('\n[tui]\n')
    out.append(replacement)

updated = ''.join(out)
try:
    after = tomllib.loads(updated)
    expected = dict(before)
    expected['tui'] = dict(expected.get('tui', {}))
    if restore is not None:
        expected['tui']['status_line'] = restore
    else:
        expected['tui'].pop('status_line', None)
    if 'tui' not in before and restore is None:
        del expected['tui']
    if after != expected:
        raise ValueError('unsupported tui layout')
except (ValueError, TypeError) as exc:
    raise SystemExit('Error: cannot safely edit TOML; leaving config unchanged: ' + str(exc))

def write_atomic(path, text):
    import os, tempfile
    target = os.path.realpath(path)
    mode = os.stat(target).st_mode & 0o777 if os.path.exists(target) else 0o600
    fd, tmp = tempfile.mkstemp(dir=os.path.dirname(target), prefix=os.path.basename(target) + ".", suffix=".tmp")
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            f.write(text)
        os.chmod(tmp, mode)
        os.replace(tmp, target)
    except BaseException:
        os.unlink(tmp)
        raise

write_atomic(config_path, updated)
if os.path.exists(backup_path):
    os.unlink(backup_path)
print('restored' if restore is not None else 'removed')
PYEOF
)"

if [[ "$RESULT" == "restored" ]]; then
    echo "Restored your previous status_line in $CONFIG"
else
    echo "Removed status_line from $CONFIG"
    echo "Codex will use its default footer items."
fi
echo "Restart Codex CLI to apply."
