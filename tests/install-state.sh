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

test_records_install_manifest() {
    local home="$TMPDIR/state-home"
    mkdir -p "$home"

    HOME="$home" bash -c '
        source "'"$ROOT"'/src/lib.sh"
        record_install "tool:codex" "tool" "codex installer" "$HOME/.codex/config.toml"
    '

    local state_file="$home/.config/vibespec/installs.json"
    test -f "$state_file"
    assert_contains "$state_file" '"tool:codex"'
    assert_contains "$state_file" '"type": "tool"'
    assert_contains "$state_file" '"source": "codex installer"'
    assert_contains "$state_file" "$home/.codex/config.toml"
}

test_tools_script_can_be_sourced_without_running_menu() {
    HOME="$TMPDIR/source-home" bash -c '
        source "'"$ROOT"'/src/tools.sh"
        declare -F install_claude_code >/dev/null
    '
}

test_claude_install_skips_when_command_exists() {
    local home="$TMPDIR/claude-home"
    local bin="$TMPDIR/bin"
    mkdir -p "$home" "$bin"
    cat > "$bin/claude" <<'EOF'
#!/usr/bin/env sh
echo "claude-test-version"
EOF
    chmod +x "$bin/claude"
    cat > "$bin/npm" <<'EOF'
#!/usr/bin/env sh
echo "npm should not run" >&2
exit 12
EOF
    chmod +x "$bin/npm"

    HOME="$home" PATH="$bin:$PATH" bash -c '
        source "'"$ROOT"'/src/tools.sh"
        install_claude_code
    ' >/tmp/vibespec-claude-skip.out

    assert_contains "/tmp/vibespec-claude-skip.out" "Claude Code already installed"
    assert_contains "$home/.config/vibespec/installs.json" '"tool:claude-code"'
}

test_ensure_node_rejects_broken_node_command() {
    local home="$TMPDIR/broken-node-home"
    local bin="$TMPDIR/broken-node-bin"
    local output="$TMPDIR/broken-node.out"
    mkdir -p "$home" "$bin"

    cat > "$bin/node" <<'EOF'
#!/usr/bin/env sh
exit 127
EOF
    chmod +x "$bin/node"

    cat > "$bin/npm" <<'EOF'
#!/usr/bin/env sh
echo "npm-test-version"
EOF
    chmod +x "$bin/npm"

    if HOME="$home" PATH="$bin:$PATH" bash -c '
        source "'"$ROOT"'/src/tools.sh"
        ensure_node
    ' > "$output" 2>&1; then
        echo "ensure_node accepted a broken node command" >&2
        exit 1
    fi

    assert_contains "$output" "Node.js command exists but failed to run"
}

test_replace_node_removes_existing_node_before_installing_nvm() {
    local home="$TMPDIR/replace-node-home"
    local bin="$TMPDIR/replace-node-bin"
    local output="$TMPDIR/replace-node.out"
    mkdir -p "$home/.nvm" "$bin"
    touch "$home/.nvm/nvm.sh"

    cat > "$bin/sudo" <<'EOF'
#!/usr/bin/env sh
printf 'sudo %s\n' "$*" >> "$SUDO_LOG"
EOF
    chmod +x "$bin/sudo"

    cat > "$bin/curl" <<'EOF'
#!/usr/bin/env sh
cat <<'INSTALLER'
#!/usr/bin/env sh
mkdir -p "$HOME/.nvm"
cat > "$HOME/.nvm/nvm.sh" <<'NVM'
: "${NVM_TEST_UNSET_SOURCE}"
nvm() {
    : "${NVM_TEST_UNSET_COMMAND}"
    printf 'nvm %s\n' "$*" >> "$NVM_LOG"
}
NVM
INSTALLER
EOF
    chmod +x "$bin/curl"

    cat > "$bin/node" <<'EOF'
#!/usr/bin/env sh
echo "v22.0.0"
EOF
    chmod +x "$bin/node"

    cat > "$bin/npm" <<'EOF'
#!/usr/bin/env sh
echo "10.0.0"
EOF
    chmod +x "$bin/npm"

    SUDO_LOG="$TMPDIR/sudo.log" NVM_LOG="$TMPDIR/nvm.log" HOME="$home" PATH="$bin:$PATH" bash -c '
        source "'"$ROOT"'/src/tools.sh"
        replace_node
    ' > "$output"

    assert_contains "$output" "Removing existing Node.js installations"
    assert_contains "$output" "nvm installed"
    assert_contains "$output" "Node.js LTS installed"
    assert_contains "$TMPDIR/sudo.log" "apt remove -y nodejs npm"
    assert_contains "$TMPDIR/nvm.log" "install --lts"
    assert_contains "$TMPDIR/nvm.log" "use --delete-prefix --lts"
    test -f "$home/.nvm/nvm.sh"
}

test_uninstall_all_coding_cli_tools_removes_known_user_commands_and_npm_packages() {
    local home="$TMPDIR/uninstall-home"
    local bin="$TMPDIR/uninstall-bin"
    local output="$TMPDIR/uninstall.out"
    mkdir -p "$home/.local/bin" "$bin"

    touch "$home/.local/bin/claude" "$home/.local/bin/codex" "$home/.local/bin/agy" "$home/.local/bin/copilot"
    chmod +x "$home/.local/bin/claude" "$home/.local/bin/codex" "$home/.local/bin/agy" "$home/.local/bin/copilot"

    cat > "$bin/npm" <<'EOF'
#!/usr/bin/env sh
printf 'npm %s\n' "$*" >> "$NPM_LOG"
EOF
    chmod +x "$bin/npm"

    NPM_LOG="$TMPDIR/npm.log" HOME="$home" PATH="$bin:$home/.local/bin:$PATH" bash -c '
        source "'"$ROOT"'/src/tools.sh"
        uninstall_all_coding_cli_tools
    ' > "$output"

    assert_contains "$output" "Uninstalling AI coding CLI tools"
    assert_contains "$TMPDIR/npm.log" "uninstall -g @anthropic-ai/claude-code @openai/codex @github/copilot"
    test ! -e "$home/.local/bin/claude"
    test ! -e "$home/.local/bin/codex"
    test ! -e "$home/.local/bin/agy"
    test ! -e "$home/.local/bin/copilot"
}

test_uninstall_all_wipes_config_and_state_paths() {
    local home="$TMPDIR/nuke-home"
    local bin="$TMPDIR/nuke-bin"
    local output="$TMPDIR/nuke.out"
    mkdir -p "$home/.local/bin" "$bin"
    mkdir -p "$home/.claude/agents" "$home/.gemini/antigravity-cli" \
             "$home/.codex" "$home/.copilot" "$home/.config/vibespec"
    touch "$home/.claude.json" \
          "$home/.claude/settings.json" \
          "$home/.gemini/antigravity-cli/statusline.js" \
          "$home/.codex/AGENTS.md" \
          "$home/.gemini/AGENTS.md" \
          "$home/.copilot/copilot-instructions.md" \
          "$home/.codex/AGENTS.md.01012026.bak" \
          "$home/.codex/statusline.js" \
          "$home/.copilot/statusline.js" \
          "$home/.config/vibespec/installs.json"

    cat > "$home/.codex/config.toml" <<'EOF'
[tui]
status_line = "node ~/.codex/statusline.js"

[history]
persistence = "save-all"
EOF

    cat > "$home/.copilot/settings.json" <<'EOF'
{
  "statusLine": { "type": "command", "command": "node ~/.copilot/statusline.js" },
  "theme": "dark"
}
EOF

    cat > "$bin/npm" <<'EOF'
#!/usr/bin/env sh
printf 'npm %s\n' "$*" >> "$NPM_LOG"
EOF
    chmod +x "$bin/npm"

    NPM_LOG="$TMPDIR/nuke-npm.log" HOME="$home" PATH="$bin:$home/.local/bin:$PATH" bash -c '
        source "'"$ROOT"'/src/tools.sh"
        uninstall_all_coding_cli_tools
    ' > "$output"

    assert_contains "$TMPDIR/nuke-npm.log" "uninstall -g @anthropic-ai/claude-code @openai/codex @github/copilot"
    test ! -e "$home/.claude"
    test ! -e "$home/.claude.json"
    test ! -e "$home/.gemini/antigravity-cli"
    test ! -e "$home/.codex/AGENTS.md"
    test ! -e "$home/.gemini/AGENTS.md"
    test ! -e "$home/.copilot/copilot-instructions.md"
    test ! -e "$home/.codex/AGENTS.md.01012026.bak"
    test ! -e "$home/.config/vibespec"

    # Orphan statusline scripts removed.
    test ! -e "$home/.codex/statusline.js"
    test ! -e "$home/.copilot/statusline.js"

    # Tool config files survive, but the statusline entries are stripped.
    test -f "$home/.codex/config.toml"
    test -f "$home/.copilot/settings.json"
    assert_contains "$home/.codex/config.toml" 'persistence = "save-all"'
    assert_contains "$home/.copilot/settings.json" '"theme": "dark"'
    if grep -q 'status_line' "$home/.codex/config.toml"; then
        echo "Expected status_line stripped from config.toml" >&2
        exit 1
    fi
    if grep -q 'statusLine' "$home/.copilot/settings.json"; then
        echo "Expected statusLine stripped from settings.json" >&2
        exit 1
    fi
}

test_uninstall_all_refuses_unsafe_home() {
    local output="$TMPDIR/unsafe-home.out"
    if HOME="/" bash -c '
        source "'"$ROOT"'/src/tools.sh"
        uninstall_all_coding_cli_tools
    ' > "$output" 2>&1; then
        echo "uninstall ran with unsafe HOME=/" >&2
        exit 1
    fi
    assert_contains "$output" "HOME is not safely set"
}

test_removed_installers_are_not_referenced() {
    local removed_script
    local removed_menu_text

    removed_script="$ROOT/src/$(printf 'plu%s.sh' 'gins')"
    removed_menu_text="$(printf 'Install Plu%s' 'gins')"

    test ! -e "$removed_script"
    if grep -Fq "$(basename "$removed_script")" "$ROOT/vibespec.sh"; then
        echo "Main menu still references removed script" >&2
        exit 1
    fi
    if grep -Fq "$removed_menu_text" "$ROOT/vibespec.sh"; then
        echo "Main menu still references removed menu entry" >&2
        exit 1
    fi
}

test_script_code_contains_no_plugin_or_mcp_references() {
    local output

    if output="$(grep -RInE 'plugin|plugins|mcp|MCP|extension|extensions' "$ROOT/vibespec.sh" "$ROOT/src" 2>/dev/null)"; then
        echo "Script code still contains plugin/MCP references:" >&2
        echo "$output" >&2
        exit 1
    fi
}

test_records_install_manifest
test_tools_script_can_be_sourced_without_running_menu
test_claude_install_skips_when_command_exists
test_ensure_node_rejects_broken_node_command
test_replace_node_removes_existing_node_before_installing_nvm
test_uninstall_all_coding_cli_tools_removes_known_user_commands_and_npm_packages
test_uninstall_all_wipes_config_and_state_paths
test_uninstall_all_refuses_unsafe_home
test_removed_installers_are_not_referenced
test_script_code_contains_no_plugin_or_mcp_references

echo "install state tests passed"
