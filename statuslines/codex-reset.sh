#!/usr/bin/env bash
set -euo pipefail

CONFIG="${HOME}/.codex/config.toml"

echo "Resetting Codex CLI statusline to default..."

if [[ ! -f "$CONFIG" ]]; then
    echo "No config file found at $CONFIG — nothing to reset."
    exit 0
fi

if ! command -v python3 &>/dev/null; then
    echo "Error: Python 3.11 or newer is required to update $CONFIG safely." >&2
    echo "Manually remove the status_line entry from the [tui] section of $CONFIG." >&2
    exit 1
fi

# Remove status_line from [tui] only. This restores the Codex default without
# touching similarly named keys in other sections.
python3 - "$CONFIG" <<'PYEOF'
import re
import sys

config_path = sys.argv[1]
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

out = []
in_tui = False
for statement in statements(content):
    stripped = statement.strip()
    if stripped.startswith('['):
        in_tui = bool(re.fullmatch(r'''\[\s*(?:tui|"tui"|'tui')\s*\]\s*(?:\#.*)?''', stripped))
    if in_tui and re.match(r'''(?:status_line|"status_line"|'status_line')\s*=''', stripped):
        continue
    out.append(statement)

updated = ''.join(out)
try:
    after = tomllib.loads(updated)
    expected = dict(before)
    expected['tui'] = dict(expected.get('tui', {}))
    expected['tui'].pop('status_line', None)
    if 'tui' not in before:
        del expected['tui']
    if after != expected:
        raise ValueError('unsupported tui layout')
except (ValueError, TypeError) as exc:
    raise SystemExit('Error: cannot safely edit TOML; leaving config unchanged: ' + str(exc))

with open(config_path, 'w', encoding='utf-8') as f:
    f.write(updated)
PYEOF

echo "Removed status_line from $CONFIG"
echo "Codex will use its default footer items."
echo "Restart Codex CLI to apply."
