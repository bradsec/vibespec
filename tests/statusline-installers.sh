#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

assert_contains() {
    local file="$1"
    local expected="$2"
    if ! grep -Fq "$expected" "$file"; then
        echo "Expected $file to contain: $expected" >&2
        echo "--- $file ---" >&2
        cat "$file" >&2
        exit 1
    fi
}

assert_not_contains() {
    local file="$1"
    local unexpected="$2"
    if grep -Fq "$unexpected" "$file"; then
        echo "Expected $file not to contain: $unexpected" >&2
        echo "--- $file ---" >&2
        cat "$file" >&2
        exit 1
    fi
}

test_codex_install_creates_tui_status_line() {
    local home="$TMPDIR/codex-create"
    mkdir -p "$home"

    HOME="$home" bash "$ROOT/statuslines/codex-install.sh" >/dev/null

    local config="$home/.codex/config.toml"
    assert_contains "$config" "[tui]"
    assert_contains "$config" 'status_line = ["model-with-reasoning", "context-used", "five-hour-limit", "weekly-limit", "git-branch", "current-dir"]'
    test -x "$home/.codex/statusline.js"
}

test_codex_install_preserves_other_status_line_keys() {
    local home="$TMPDIR/codex-preserve"
    local config="$home/.codex/config.toml"
    mkdir -p "$(dirname "$config")"
    cat > "$config" <<'EOF'
[profile.review]
status_line = ["do-not-touch"]

[tui]
theme = "ansi"
status_line = ["old"]

[other]
status_line = ["also-keep"]
EOF

    HOME="$home" bash "$ROOT/statuslines/codex-install.sh" >/dev/null

    assert_contains "$config" 'status_line = ["do-not-touch"]'
    assert_contains "$config" 'status_line = ["also-keep"]'
    assert_contains "$config" 'theme = "ansi"'
    assert_contains "$config" 'status_line = ["model-with-reasoning", "context-used", "five-hour-limit", "weekly-limit", "git-branch", "current-dir"]'
    assert_not_contains "$config" 'status_line = ["old"]'
}

test_codex_reset_only_removes_tui_status_line() {
    local home="$TMPDIR/codex-reset"
    local config="$home/.codex/config.toml"
    mkdir -p "$(dirname "$config")"
    cat > "$config" <<'EOF'
[profile.review]
status_line = ["keep"]

[tui]
status_line = ["remove"]
theme = "ansi"
EOF

    HOME="$home" bash "$ROOT/statuslines/codex-reset.sh" >/dev/null

    assert_contains "$config" 'status_line = ["keep"]'
    assert_contains "$config" 'theme = "ansi"'
    assert_not_contains "$config" 'status_line = ["remove"]'
}

test_antigravity_install_configures_command_statusline() {
    local home="$TMPDIR/antigravity"
    local settings="$home/.gemini/antigravity-cli/settings.json"
    mkdir -p "$(dirname "$settings")"
    cat > "$settings" <<'EOF'
{"existing": true}
EOF

    HOME="$home" bash "$ROOT/statuslines/antigravity-install.sh" >/dev/null

    assert_contains "$settings" '"existing": true'
    assert_contains "$settings" '"statusLine"'
    assert_contains "$settings" '"type": "command"'
    assert_contains "$settings" "$home/.gemini/antigravity-cli/statusline.js"
    test -x "$home/.gemini/antigravity-cli/statusline.js"
}

test_antigravity_reset_removes_statusline_only() {
    local home="$TMPDIR/antigravity-reset"
    local settings="$home/.gemini/antigravity-cli/settings.json"
    mkdir -p "$(dirname "$settings")"
    cat > "$settings" <<'EOF'
{
  "existing": true,
  "statusLine": {
    "type": "command",
    "command": "node statusline.js"
  }
}
EOF

    HOME="$home" bash "$ROOT/statuslines/antigravity-reset.sh" >/dev/null

    assert_contains "$settings" '"existing": true'
    assert_not_contains "$settings" '"statusLine"'
}

test_cc_install_configures_command_statusline() {
    local home="$TMPDIR/cc-install"
    mkdir -p "$home"

    HOME="$home" bash "$ROOT/statuslines/cc-install.sh" >/dev/null

    local settings="$home/.claude/settings.json"
    assert_contains "$settings" '"statusLine"'
    assert_contains "$settings" '"type": "command"'
    assert_contains "$settings" "$home/.claude/hooks/cc-statusline.js"
    test -x "$home/.claude/hooks/cc-statusline.js"
}

test_cc_install_writes_settings_without_node() {
    local home="$TMPDIR/cc-no-node"
    mkdir -p "$home"

    # PATH excludes the nvm-managed node but keeps python3 and coreutils.
    HOME="$home" PATH="/usr/bin:/bin" bash "$ROOT/statuslines/cc-install.sh" >/dev/null

    local settings="$home/.claude/settings.json"
    assert_contains "$settings" '"statusLine"'
    assert_contains "$settings" '"type": "command"'
    # No node on PATH: command falls back to bare "node" plus the hook path.
    assert_contains "$settings" '"command": "node '
    assert_contains "$settings" "$home/.claude/hooks/cc-statusline.js"
}

test_cc_install_preserves_other_settings_keys() {
    local home="$TMPDIR/cc-preserve"
    local settings="$home/.claude/settings.json"
    mkdir -p "$(dirname "$settings")"
    cat > "$settings" <<'EOF'
{"keepme": true}
EOF

    HOME="$home" bash "$ROOT/statuslines/cc-install.sh" >/dev/null

    assert_contains "$settings" '"keepme": true'
    assert_contains "$settings" '"statusLine"'
}

test_cc_reset_removes_statusline_only() {
    local home="$TMPDIR/cc-reset"
    local settings="$home/.claude/settings.json"
    mkdir -p "$(dirname "$settings")"
    cat > "$settings" <<'EOF'
{
  "keepme": true,
  "statusLine": {"type": "command", "command": "node x"}
}
EOF

    HOME="$home" bash "$ROOT/statuslines/cc-reset.sh" >/dev/null

    assert_contains "$settings" '"keepme": true'
    assert_not_contains "$settings" '"statusLine"'
}

test_codex_install_creates_tui_status_line
test_codex_install_preserves_other_status_line_keys
test_codex_reset_only_removes_tui_status_line
test_antigravity_install_configures_command_statusline
test_antigravity_reset_removes_statusline_only
test_cc_install_configures_command_statusline
test_cc_install_writes_settings_without_node
test_cc_install_preserves_other_settings_keys
test_cc_reset_removes_statusline_only

echo "statusline installer tests passed"
