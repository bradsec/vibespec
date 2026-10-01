#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# Tests change HOME and must not inherit an active CLI profile.
unset CLAUDE_CONFIG_DIR CODEX_HOME
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

test_codex_rules_update_reports_source_and_hashes() {
    local home="$TMPDIR/codex-home"
    local bin="$TMPDIR/bin"
    local output="$TMPDIR/config.out"
    local backup_date
    backup_date="$(date +%d%m%Y)"
    mkdir -p "$home/.codex" "$bin"

    cat > "$home/.codex/AGENTS.md" <<'EOF'
# AGENTS.md
old rules
EOF

    cat > "$bin/curl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
out=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        -o)
            out="$2"
            shift 2
            ;;
        *)
            shift
            ;;
    esac
done
cat > "$out" <<'RULES'
# RULES.md
updated rules
RULES
EOF
    chmod +x "$bin/curl"

    HOME="$home" PATH="$bin:$PATH" bash -c '
        source "'"$ROOT"'/src/config.sh"
        install_config "Codex"
    ' > "$output"

    assert_contains "$output" "Rules source: remote"
    assert_contains "$output" "Existing SHA256:"
    assert_contains "$output" "New SHA256:"
    assert_contains "$output" "Backed up existing file: $home/.codex/AGENTS.md.${backup_date}.bak"
    assert_contains "$output" "Rules installed: $home/.codex/AGENTS.md"
    assert_contains "$home/.codex/AGENTS.md.${backup_date}.bak" "old rules"
    assert_contains "$home/.codex/AGENTS.md" "updated rules"
}

test_codex_rules_update_reports_source_and_hashes

test_custom_profiles() {
    local home="$TMPDIR/custom-home"
    local claude="$home/claude profile"
    local codex="$home/codex profile"
    mkdir -p "$home"
    HOME="$home" CLAUDE_CONFIG_DIR="$home/env-claude" CODEX_HOME="$home/env-codex" \
        PATH="$TMPDIR/bin:$PATH" bash -c '
            source "'"$ROOT"'/src/config.sh"
            install_config "Claude Code"
            install_config "Codex"
        ' > /dev/null
    assert_contains "$home/env-claude/CLAUDE.md" "updated rules"
    assert_contains "$home/env-codex/AGENTS.md" "updated rules"

    printf '%s\n' "$claude" | HOME="$home" PATH="$TMPDIR/bin:$PATH" bash -c '
        source "'"$ROOT"'/src/config.sh"
        install_custom_config "Claude Code"
    ' > /dev/null
    printf '%s\n' "$codex" | HOME="$home" PATH="$TMPDIR/bin:$PATH" bash -c '
        source "'"$ROOT"'/src/config.sh"
        install_custom_config "Codex"
    ' > /dev/null
    assert_contains "$claude/CLAUDE.md" "updated rules"
    assert_contains "$codex/AGENTS.md" "updated rules"
    assert_contains "$home/.config/vibespec/installs.json" "$claude/CLAUDE.md"
    assert_contains "$home/.config/vibespec/installs.json" "$codex/AGENTS.md"

    # Send a literal tilde to exercise the profile prompt's expansion.
    # shellcheck disable=SC2088
    printf '~/alternate\n' | HOME="$home" PATH="$TMPDIR/bin:$PATH" bash -c '
        source "'"$ROOT"'/src/config.sh"
        install_custom_config "Codex"
    ' > /dev/null
    assert_contains "$home/alternate/AGENTS.md" "updated rules"

    if printf 'relative/path\n' | HOME="$home" PATH="$TMPDIR/bin:$PATH" bash -c '
        source "'"$ROOT"'/src/config.sh"
        install_custom_config "Codex"
    ' > /dev/null 2>&1; then
        echo "Relative profile path was accepted" >&2
        exit 1
    fi
    test ! -e "$home/.codex/AGENTS.md"
}

test_custom_profiles

test_codex_rules_preserve_same_day_backups() {
    local test_home="$TMPDIR/codex-home"
    local backup
    backup="$test_home/.codex/AGENTS.md.$(date +%d%m%Y).bak"
    printf '# AGENTS.md\nsecond rules\n' > "$test_home/.codex/AGENTS.md"
    HOME="$test_home" PATH="$TMPDIR/bin:$PATH" bash -c '
        source "'"$ROOT"'/src/config.sh"
        install_config "Codex"
    ' > "$TMPDIR/reinstall.out"
    assert_contains "$backup" "old rules"
    assert_contains "$backup.1" "second rules"
    assert_contains "$test_home/.codex/AGENTS.md" "updated rules"
}

test_codex_rules_reject_invalid_downloads() {
    local test_home="$TMPDIR/codex-home"
    local payload="$TMPDIR/payload"
    cat > "$TMPDIR/bin/curl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
while [[ $# -gt 0 ]]; do
    case "$1" in
        -o) cp "$RULES_TEST_PAYLOAD" "$2"; exit ;;
        *) shift ;;
    esac
done
exit 1
EOF
    local invalid
    for invalid in '' '# RULES.md' '<html>not rules</html>'; do
        printf '%s\n' "$invalid" > "$payload"
        if HOME="$test_home" PATH="$TMPDIR/bin:$PATH" RULES_TEST_PAYLOAD="$payload" bash -c '
            source "'"$ROOT"'/src/config.sh"
            install_config "Codex"
        ' > "$TMPDIR/invalid.out" 2>&1; then
            echo "Invalid rules download was accepted" >&2
            exit 1
        fi
        assert_contains "$TMPDIR/invalid.out" "Invalid RULES.md"
        assert_contains "$test_home/.codex/AGENTS.md" "updated rules"
    done
}

test_codex_rules_preserve_same_day_backups
test_codex_rules_reject_invalid_downloads

echo "config rules tests passed"
