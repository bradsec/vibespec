#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# Tests change HOME and must not inherit an active CLI profile.
unset CLAUDE_CONFIG_DIR CODEX_HOME
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

fail() {
    echo "$*" >&2
    exit 1
}

assert_contains() {
    local file="$1" expected="$2"
    if ! grep -Fq -- "$expected" "$file"; then
        echo "Expected $file to contain: $expected" >&2
        echo "--- $file ---" >&2
        cat "$file" >&2
        exit 1
    fi
}

assert_not_contains() {
    local file="$1" unexpected="$2"
    if grep -Fq -- "$unexpected" "$file"; then
        echo "Expected $file not to contain: $unexpected" >&2
        echo "--- $file ---" >&2
        cat "$file" >&2
        exit 1
    fi
}

assert_exists() { [[ -e "$1" || -L "$1" ]] || fail "Expected to exist: $1"; }
assert_missing() { [[ ! -e "$1" && ! -L "$1" ]] || fail "Expected to be missing: $1"; }

# Hash names and contents of every entry under a directory.
tree_sum() {
    (cd "$1" && { find . | LC_ALL=C sort; find . -type f -exec sha256sum {} + | LC_ALL=C sort; }) | sha256sum
}

# Run mirror_profile in a clean shell. confirm reads /dev/tty, so replace it.
run_mirror() {
    local home="$1" answer="$2"
    shift 2
    HOME="$home" MIRROR_ANSWER="$answer" bash -c '
        source "$1"
        shift
        confirm() { [[ "$MIRROR_ANSWER" == y ]]; }
        mirror_profile "$@"
    ' mirror "$ROOT/src/mirror.sh" "$@"
}

make_claude_source() {
    local dir="$1"
    mkdir -p "$dir/hooks" "$dir/skills/alpha" "$dir/agents" "$dir/commands" \
        "$dir/plugins/cache/mk/p1" "$dir/plugins/marketplaces/mk" \
        "$dir/plugins/data/p1" "$dir/projects/demo"
    printf '# CLAUDE.md\nsource rules\n' > "$dir/CLAUDE.md"
    cat > "$dir/settings.json" <<EOF
{
  "statusLine": {"type": "command", "command": "node $dir/hooks/cc-statusline.js"},
  "env": {"API_TOKEN": "sk-settings-secret"},
  "permissions": {"allow": ["Bash(git status)"]},
  "note": "$dir-work/keep"
}
EOF
    printf 'console.log("statusline")\n' > "$dir/hooks/cc-statusline.js"
    printf 'see %s/skills/alpha\n' "$dir" > "$dir/skills/alpha/SKILL.md"
    printf 'agent\n' > "$dir/agents/a.md"
    printf 'command\n' > "$dir/commands/c.md"
    printf 'plugin\n' > "$dir/plugins/cache/mk/p1/plugin.json"
    printf 'market\n' > "$dir/plugins/marketplaces/mk/marketplace.json"
    cat > "$dir/plugins/installed_plugins.json" <<EOF
{"plugins": {"p1@mk": [{"installPath": "$dir/plugins/cache/mk/p1"}]}}
EOF
    cat > "$dir/plugins/known_marketplaces.json" <<EOF
{"mk": {"installLocation": "$dir/plugins/marketplaces/mk"}}
EOF
    printf 'plugin-data-secret\n' > "$dir/plugins/data/p1/state"
    printf 'source-cred-secret\n' > "$dir/.credentials.json"
    printf 'history\n' > "$dir/history.jsonl"
    printf 'transcript\n' > "$dir/projects/demo/t.jsonl"
    printf '{"statusLine": "source-backup"}\n' > "$dir/statusline.vibespec-backup.json"
    cat > "$dir/.claude.json" <<'EOF'
{"oauthAccount": {"emailAddress": "src@example.com"}, "userID": "src-user",
 "mcpServers": {"docs": {"command": "docs-mcp", "env": {"DOCS_KEY": "mcp-secret-value"}}}}
EOF
}

make_claude_target() {
    local dir="$1"
    mkdir -p "$dir/skills/extra" "$dir/hooks"
    printf '# CLAUDE.md\ntarget rules\n' > "$dir/CLAUDE.md"
    printf '{"theme": "dark"}\n' > "$dir/settings.json"
    printf 'extra skill\n' > "$dir/skills/extra/SKILL.md"
    printf 'extra hook\n' > "$dir/hooks/extra.sh"
    printf 'target-cred\n' > "$dir/.credentials.json"
    cat > "$dir/.claude.json" <<'EOF'
{"oauthAccount": {"emailAddress": "dst@example.com"}, "userID": "dst-user",
 "mcpServers": {"old": {"command": "old-mcp"}}}
EOF
}

# Test functions and calls go here.

test_claude_copies_allowlist_and_removes_extras() {
    local home="$TMPDIR/copy-home" src dst snapshot
    src="$home/src claude"
    dst="$home/dst claude"
    make_claude_source "$src"
    make_claude_target "$dst"
    run_mirror "$home" y claude "$src" "$dst" > "$TMPDIR/copy.out"

    assert_contains "$dst/CLAUDE.md" "source rules"
    assert_contains "$dst/settings.json" "Bash(git status)"
    assert_exists "$dst/hooks/cc-statusline.js"
    assert_exists "$dst/skills/alpha/SKILL.md"
    assert_exists "$dst/agents/a.md"
    assert_exists "$dst/commands/c.md"
    assert_exists "$dst/plugins/cache/mk/p1/plugin.json"
    assert_exists "$dst/plugins/marketplaces/mk/marketplace.json"
    assert_exists "$dst/plugins/installed_plugins.json"
    assert_exists "$dst/plugins/known_marketplaces.json"
    assert_missing "$dst/skills/extra"
    assert_missing "$dst/hooks/extra.sh"

    snapshot="$dst/.vibespec-mirror-backup/$(date +%d%m%Y)"
    assert_exists "$snapshot/skills/extra/SKILL.md"
    assert_exists "$snapshot/hooks/extra.sh"
    assert_contains "$snapshot/CLAUDE.md" "target rules"
    assert_contains "$TMPDIR/copy.out" "$snapshot"
}
test_claude_copies_allowlist_and_removes_extras

test_claude_never_copies_account_data() {
    local home="$TMPDIR/private-home" src dst
    src="$home/src claude"
    dst="$home/dst claude"
    make_claude_source "$src"
    make_claude_target "$dst"
    run_mirror "$home" y claude "$src" "$dst" > /dev/null

    assert_contains "$dst/.credentials.json" "target-cred"
    assert_missing "$dst/history.jsonl"
    assert_missing "$dst/projects"
    assert_missing "$dst/plugins/data"
    assert_missing "$dst/statusline.vibespec-backup.json"
}
test_claude_never_copies_account_data

test_cancel_changes_nothing() {
    local home="$TMPDIR/cancel-home" src dst before
    src="$home/src claude"
    dst="$home/dst claude"
    make_claude_source "$src"
    make_claude_target "$dst"
    before="$(tree_sum "$dst")"
    run_mirror "$home" n claude "$src" "$dst" > "$TMPDIR/cancel.out"
    [[ "$(tree_sum "$dst")" == "$before" ]] || fail "Cancel changed the target"
    assert_contains "$TMPDIR/cancel.out" "nothing changed"
}
test_cancel_changes_nothing

test_rejects_unsafe_pairs() {
    local home="$TMPDIR/reject-home" src dst before
    src="$home/src claude"
    dst="$home/dst claude"
    make_claude_source "$src"
    make_claude_target "$dst"
    before="$(tree_sum "$home")"

    if run_mirror "$home" y claude "$src" "$src/" > /dev/null 2>&1; then
        fail "Mirror onto itself was accepted"
    fi
    if run_mirror "$home" y claude "$src" "$src/nested" > /dev/null 2>&1; then
        fail "Target inside source was accepted"
    fi
    if run_mirror "$home" y claude "$dst/skills" "$dst" > /dev/null 2>&1; then
        fail "Source without marker was accepted"
    fi
    if run_mirror "$home" y claude "$src" "$home/bad\"name" > /dev/null 2>&1; then
        fail "Target with a quote was accepted"
    fi
    if run_mirror "$home" y gemini "$src" "$dst" > /dev/null 2>&1; then
        fail "Unknown tool was accepted"
    fi
    [[ "$(tree_sum "$home")" == "$before" ]] || fail "A rejected mirror changed files"
}
test_rejects_unsafe_pairs

test_malformed_source_stops_before_changes() {
    local home="$TMPDIR/malformed-home" src dst before
    src="$home/src claude"
    dst="$home/dst claude"
    make_claude_source "$src"
    make_claude_target "$dst"
    printf '{broken\n' > "$src/settings.json"
    before="$(tree_sum "$dst")"
    if run_mirror "$home" y claude "$src" "$dst" > "$TMPDIR/malformed.out" 2>&1; then
        fail "Malformed settings.json was accepted"
    fi
    assert_contains "$TMPDIR/malformed.out" "Cannot parse"
    [[ "$(tree_sum "$dst")" == "$before" ]] || fail "Malformed source changed the target"
    assert_missing "$dst/.vibespec-mirror-backup"
}
test_malformed_source_stops_before_changes

test_same_day_rerun_keeps_snapshots() {
    local home="$TMPDIR/rerun-home" src dst base
    src="$home/src claude"
    dst="$home/dst claude"
    make_claude_source "$src"
    make_claude_target "$dst"
    run_mirror "$home" y claude "$src" "$dst" > /dev/null
    run_mirror "$home" y claude "$src" "$dst" > /dev/null
    base="$dst/.vibespec-mirror-backup/$(date +%d%m%Y)"
    assert_contains "$base/CLAUDE.md" "target rules"
    assert_contains "$base.1/CLAUDE.md" "source rules"
}
test_same_day_rerun_keeps_snapshots

test_sparse_source_removes_target_paths() {
    local home="$TMPDIR/sparse-home" src dst
    src="$home/src claude"
    dst="$home/dst claude"
    mkdir -p "$src"
    printf '# CLAUDE.md\nonly rules\n' > "$src/CLAUDE.md"
    make_claude_target "$dst"
    run_mirror "$home" y claude "$src" "$dst" > "$TMPDIR/sparse.out"
    assert_contains "$dst/CLAUDE.md" "only rules"
    assert_missing "$dst/settings.json"
    assert_missing "$dst/skills"
    assert_missing "$dst/hooks"
    assert_contains "$TMPDIR/sparse.out" "remove   settings.json"
    assert_contains "$dst/.credentials.json" "target-cred"
}
test_sparse_source_removes_target_paths

test_records_install_state() {
    local home="$TMPDIR/state-home" src dst
    src="$home/src claude"
    dst="$home/dst claude"
    make_claude_source "$src"
    make_claude_target "$dst"
    run_mirror "$home" y claude "$src" "$dst" > /dev/null
    assert_contains "$home/.config/vibespec/installs.json" "\"mirror:claude:$(
        printf '%s' "$dst" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//'
    )\""
    assert_contains "$home/.config/vibespec/installs.json" '"type": "mirror"'
}
test_records_install_state

test_claude_global_config_location() {
    local home="$TMPDIR/global-home" out
    mkdir -p "$home/.claude" "$home/custom"
    out="$(HOME="$home" bash -c 'source "$1"; claude_global_config "$HOME/.claude"' x "$ROOT/src/mirror.sh")"
    [[ "$out" == "$home/.claude.json" ]] || fail "Default profile config: $out"
    touch "$home/.claude/.claude.json"
    out="$(HOME="$home" bash -c 'source "$1"; claude_global_config "$HOME/.claude"' x "$ROOT/src/mirror.sh")"
    [[ "$out" == "$home/.claude/.claude.json" ]] || fail "Default profile with in-dir config: $out"
    out="$(HOME="$home" bash -c 'source "$1"; claude_global_config "$HOME/custom"' x "$ROOT/src/mirror.sh")"
    [[ "$out" == "$home/custom/.claude.json" ]] || fail "Custom profile config: $out"
}
test_claude_global_config_location


echo "mirror tests passed"
