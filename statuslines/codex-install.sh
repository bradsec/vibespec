#!/usr/bin/env bash
set -euo pipefail

REPO_RAW="https://raw.githubusercontent.com/bradsec/vibespec/main"
HOOK_DEST="${HOME}/.codex/statusline.js"
CONFIG="${HOME}/.codex/config.toml"

echo "Installing Codex statusline..."
echo ""
echo "Installing the local formatter script and configuring the"
echo "customizable tui.status_line footer items."
echo ""

mkdir -p "$(dirname "$HOOK_DEST")"

LOCAL_JS="$(dirname "${BASH_SOURCE[0]}")/codex-statusline.js"
if [[ -f "$LOCAL_JS" ]]; then
    cp "$LOCAL_JS" "$HOOK_DEST"
elif command -v curl &>/dev/null; then
    curl -fsSL "${REPO_RAW}/statuslines/codex-statusline.js" -o "$HOOK_DEST"
elif command -v wget &>/dev/null; then
    wget -qO "$HOOK_DEST" "${REPO_RAW}/statuslines/codex-statusline.js"
else
    echo "Error: neither curl nor wget found and no local copy available." >&2
    exit 1
fi

chmod +x "$HOOK_DEST"
echo "Installed: $HOOK_DEST"

# Configure enum-based tui.status_line in config.toml
if ! command -v python3 &>/dev/null; then
    echo "Error: Python 3.11 or newer is required to update $CONFIG safely." >&2
    echo "Install Python 3.11 or newer, or add this manually under [tui] in $CONFIG:" >&2
    echo '  status_line = ["model-with-reasoning", "context-used", "used-tokens", "task-progress", "five-hour-limit", "weekly-limit", "git-branch", "current-dir"]' >&2
    exit 1
fi

mkdir -p "$(dirname "$CONFIG")"
touch "$CONFIG"

# Insert status_line under [tui] without touching other sections.
python3 - "$CONFIG" <<'PYEOF'
status_line = 'status_line = ["model-with-reasoning", "context-used", "used-tokens", "task-progress", "five-hour-limit", "weekly-limit", "git-branch", "current-dir"]'
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
seen_tui = False
inserted = False
for statement in statements(content):
    stripped = statement.strip()
    if stripped.startswith('['):
        if in_tui and not inserted:
            out.append(status_line + '\n')
            inserted = True
        in_tui = bool(re.fullmatch(r'''\[\s*(?:tui|"tui"|'tui')\s*\]\s*(?:\#.*)?''', stripped))
        seen_tui = seen_tui or in_tui
    if in_tui and re.match(r'''(?:status_line|"status_line"|'status_line')\s*=''', stripped):
        if not inserted:
            out.append(status_line + '\n')
            inserted = True
        continue
    out.append(statement)

if not inserted:
    if out and not out[-1].endswith('\n'):
        out.append('\n')
    if not seen_tui:
        out.append('\n[tui]\n')
    out.append(status_line + '\n')

updated = ''.join(out)
try:
    after = tomllib.loads(updated)
    expected = dict(before)
    expected['tui'] = dict(expected.get('tui', {}))
    expected['tui']['status_line'] = tomllib.loads(status_line)['status_line']
    if after != expected:
        raise ValueError('unsupported tui layout')
except (ValueError, TypeError) as exc:
    raise SystemExit('Error: cannot safely edit TOML; leaving config unchanged: ' + str(exc))

with open(config_path, 'w', encoding='utf-8') as f:
    f.write(updated)
PYEOF

echo "Updated: $CONFIG"
echo ""
echo "  [tui]"
echo "  status_line = [\"model-with-reasoning\", \"context-used\", \"used-tokens\", \"task-progress\", \"five-hour-limit\", \"weekly-limit\", \"git-branch\", \"current-dir\"]"
echo ""
echo "Use /statusline inside Codex to toggle and reorder items."
echo "Restart Codex CLI to apply config changes."
