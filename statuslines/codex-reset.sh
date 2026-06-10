#!/usr/bin/env bash
set -euo pipefail

CONFIG="${HOME}/.codex/config.toml"

echo "Resetting Codex CLI statusline to default..."

if [[ ! -f "$CONFIG" ]]; then
    echo "No config file found at $CONFIG — nothing to reset."
    exit 0
fi

if ! command -v python3 &>/dev/null; then
    echo "Error: python3 is required to update $CONFIG safely." >&2
    echo "Manually remove the status_line entry from the [tui] section of $CONFIG." >&2
    exit 1
fi

# Remove status_line from [tui] only. This restores the Codex default without
# touching similarly named keys in other sections.
python3 - "$CONFIG" <<'PYEOF'
import sys

config_path = sys.argv[1]
with open(config_path, 'r', encoding='utf-8') as f:
    content = f.read()

lines = content.splitlines()
out = []
in_tui = False

for line in lines:
    stripped = line.strip()
    is_section = stripped.startswith('[') and stripped.endswith(']')
    if is_section:
        in_tui = stripped == '[tui]'
        out.append(line)
        continue

    if in_tui and stripped.startswith('status_line'):
        continue

    out.append(line)

with open(config_path, 'w', encoding='utf-8') as f:
    f.write('\n'.join(out).rstrip() + '\n')
PYEOF

echo "Removed status_line from $CONFIG"
echo "Codex will use its default footer items (spinner, project)."
echo "Restart Codex CLI to apply."
