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
mkdir -p "$(dirname "$CONFIG")"
touch "$CONFIG"

# Insert status_line under [tui] without touching other sections.
python3 - "$CONFIG" <<'PYEOF'
import sys

config_path = sys.argv[1]
status_line = 'status_line = ["model-with-reasoning", "context-used", "five-hour-limit", "weekly-limit", "git-branch", "current-dir"]'

with open(config_path, 'r', encoding='utf-8') as f:
    content = f.read()

lines = content.splitlines()
out = []
in_tui = False
seen_tui = False
inserted = False

for line in lines:
    stripped = line.strip()
    is_section = stripped.startswith('[') and stripped.endswith(']')
    if is_section:
        if in_tui and not inserted:
            out.append(status_line)
            inserted = True
        in_tui = stripped == '[tui]'
        seen_tui = seen_tui or in_tui
        out.append(line)
        continue

    if in_tui and stripped.startswith('status_line'):
        if not inserted:
            out.append(status_line)
            inserted = True
        continue

    out.append(line)

if in_tui and not inserted:
    out.append(status_line)

if not seen_tui:
    if out and out[-1] != '':
        out.append('')
    out.append('[tui]')
    out.append(status_line)

with open(config_path, 'w', encoding='utf-8') as f:
    f.write('\n'.join(out).rstrip() + '\n')
PYEOF

echo "Updated: $CONFIG"
echo ""
echo "  [tui]"
echo "  status_line = [\"model-with-reasoning\", \"context-used\", \"five-hour-limit\", \"weekly-limit\", \"git-branch\", \"current-dir\"]"
echo ""
echo "Use /statusline inside Codex to toggle and reorder items."
echo "Restart Codex CLI to apply config changes."
