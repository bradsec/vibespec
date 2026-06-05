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

echo "config rules tests passed"
