#!/usr/bin/env bash
set -euo pipefail

# Smoke tests for the statusline formatter scripts. They feed each script a
# mock stdin payload and check the rendered line, catching schema drift and
# syntax errors. Requires node; skips cleanly when it is absent.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if ! command -v node >/dev/null 2>&1; then
    echo "node not found; skipping statusline script tests"
    exit 0
fi

TEST_TMP="$(mktemp -d)"
trap 'rm -rf "$TEST_TMP"' EXIT
export HOME="$TEST_TMP/home"
export CLAUDE_CONFIG_DIR="$HOME/.claude"
mkdir -p "$CLAUDE_CONFIG_DIR"

fail() {
    echo "FAIL: $*" >&2
    exit 1
}

# run <script> <json> -> prints output with ANSI escapes stripped
run() {
    local script="$1" json="$2" out
    out="$(printf '%s' "$json" | node "$ROOT/statuslines/$script")" \
        || fail "$script exited non-zero"
    printf '%s' "$out" | sed -E 's/\x1b\[[0-9;]*m//g'
}

assert_has() {
    local haystack="$1" needle="$2" label="$3"
    case "$haystack" in
        *"$needle"*) ;;
        *) fail "$label: expected output to contain '$needle', got: $haystack" ;;
    esac
}

# ── Claude Code ───────────────────────────────────────────────────────────────

cc_json='{"model":{"display_name":"Opus","id":"claude-opus-5"},"effort":{"level":"high"},
"workspace":{"current_dir":"/tmp/proj","repo":{"host":"github.com","owner":"acme","name":"proj"}},
"cwd":"/tmp/proj","session_id":"s1","version":"2.1.260",
"cost":{"total_cost_usd":0.42},
"context_window":{"total_input_tokens":155000,"total_output_tokens":8200,
"context_window_size":1000000,"used_percentage":18,"remaining_percentage":82,
"current_usage":{"input_tokens":9000,"cache_creation_input_tokens":5000,"cache_read_input_tokens":140000}},
"prompt_cache":{"hit_ratio":0.91},
"rate_limits":{"five_hour":{"used_percentage":23,"resets_at":1799999999}}}'

out="$(run cc-statusline.js "$cc_json")"
assert_has "$out" "Opus [high]"  "cc effort"
assert_has "$out" "CTX"          "cc context bar"
assert_has "$out" "18%"          "cc uses pre-calculated used_percentage"
assert_has "$out" "/ 1.0M"       "cc shows window size"
assert_has "$out" "\$ 0.42"      "cc shows session cost"
assert_has "$out" "CACHE"        "cc cache bar"
assert_has "$out" "91%"          "cc uses prompt_cache.hit_ratio"
assert_has "$out" "github.com/acme/proj" "cc uses workspace.repo"

# Older client: no used_percentage, no prompt_cache. Falls back without error.
cc_old='{"model":{"display_name":"Sonnet"},"cwd":"/tmp/proj","session_id":"s2",
"context_window":{"remaining_percentage":90,
"current_usage":{"input_tokens":1000,"cache_read_input_tokens":9000,"cache_creation_input_tokens":0}}}'
out="$(run cc-statusline.js "$cc_old")"
assert_has "$out" "CTX"   "cc fallback context bar"
assert_has "$out" "CACHE" "cc fallback cache bar"

# Minimal payload: must not crash, must print the model.
out="$(run cc-statusline.js '{"model":{"display_name":"Haiku"},"session_id":"s3"}')"
assert_has "$out" "Haiku" "cc minimal payload"

# ── Antigravity ──────────────────────────────────────────────────────────────

agy_json='{"model":{"display_name":"Gemini"},"effort":{"level":"medium"},
"workspace":{"current_dir":"/tmp/proj"},"cwd":"/tmp/proj",
"cost":{"total_cost_usd":1.2},
"context_window":{"total_input_tokens":240000,"context_window_size":1000000,"used_percentage":24},
"prompt_cache":{"hit_ratio":0.6}}'
out="$(run antigravity-statusline.js "$agy_json")"
assert_has "$out" "Gemini [medium]" "agy effort"
assert_has "$out" "24%"             "agy used_percentage"
assert_has "$out" "/ 1.0M"          "agy window size"
assert_has "$out" "\$ 1.20"         "agy session cost"
assert_has "$out" "60%"             "agy prompt_cache.hit_ratio"

out="$(run antigravity-statusline.js '{"model":"Gemini"}')"
assert_has "$out" "Gemini" "agy minimal payload"

assert_lacks() {
    local haystack="$1" needle="$2" label="$3"
    case "$haystack" in
        *"$needle"*) fail "$label: unexpected '$needle' in: $haystack" ;;
    esac
}

for script in cc-statusline.js antigravity-statusline.js; do
    out="$(run "$script" '{"context_window":{"current_usage":{"input_tokens":1000}},"context":{"current_usage":{"input_tokens":1000}}}')"
    assert_lacks "$out" "CACHE" "$script absent cache telemetry"
    out="$(run "$script" '{"context_window":{"used_percentage":"bad"},"context":{"used_percent":"bad"},"rate_limits":{"five_hour":{}},"limits":{"weekly":{}},"prompt_cache":{"hit_ratio":1e999}}')"
    assert_lacks "$out" "NaN" "$script invalid metric"
    assert_lacks "$out" "CACHE" "$script invalid cache ratio"
    [[ -n "$out" ]] || fail "$script invalid metric hid the whole statusline"
    out="$(run "$script" '{"context_window":{"current_usage":{"input_tokens":100,"cache_read_input_tokens":0}},"context":{"current_usage":{"input_tokens":100,"cache_read_input_tokens":0}}}')"
    assert_has "$out" "CACHE" "$script explicit zero cache reads"
    assert_has "$out" "0%" "$script zero cache rate"
done

for script in cc-statusline.js antigravity-statusline.js; do
    out="$(run "$script" '{"cwd":"/tmp/proj","context_window":{"remaining_percentage":90}}')"
    assert_has "$out" "10%" "$script remaining percentage complement"
    assert_has "$out" "proj" "$script cwd fallback"
done

git init -q "$TEST_TMP/repo"
git -C "$TEST_TMP/repo" remote add origin 'https://user:secret@example.com/acme/proj.git?token=private#fragment'
out="$(run cc-statusline.js "{\"cwd\":\"$TEST_TMP/repo\"}")"
assert_has "$out" "example.com/acme/proj" "cc remote identity"
assert_lacks "$out" "secret" "cc remote password"
assert_lacks "$out" "private" "cc remote query"

# Git: branch, changed files and upstream counts from one status call.
repo="$TEST_TMP/gitrepo"
g() { git -C "$repo" -c user.name=t -c user.email=t@t -c commit.gpgsign=false "$@"; }
git init -q -b main "$repo"
printf '1' > "$repo/a"
g add a
g commit -q -m one
g remote add origin https://example.com/acme/proj.git
g update-ref refs/remotes/origin/main HEAD
g config branch.main.remote origin
g config branch.main.merge refs/heads/main
g commit -q --allow-empty -m two
printf '2' > "$repo/a"
printf '1' > "$repo/b"
# A new session id each run skips the five-second git cache.
out="$(run cc-statusline.js "{\"cwd\":\"$repo\",\"session_id\":\"git1\"}")"
assert_has "$out" "GIT main · ~2 · ↑1" "cc git status from porcelain v2"
g checkout -q --detach
out="$(run cc-statusline.js "{\"cwd\":\"$repo\",\"session_id\":\"git2\"}")"
case "$out" in *"GIT main"*) fail "cc detached HEAD shows a branch: $out" ;; esac

# Colors: NO_COLOR turns them off; critical usage is bold, not blinking.
busy='{"model":{"display_name":"Opus"},"context_window":{"used_percentage":40},"rate_limits":{"five_hour":{"used_percentage":95,"resets_at":1799999999},"seven_day":{"used_percentage":20,"resets_at":1799999999}}}'
raw="$(printf '%s' "$busy" | node "$ROOT/statuslines/cc-statusline.js")"
case "$raw" in *$'\x1b[5;'*) fail "cc critical usage blinks" ;; esac
raw="$(printf '%s' "$busy" | NO_COLOR=1 node "$ROOT/statuslines/cc-statusline.js")"
case "$raw" in *$'\x1b['*) fail "cc ignores NO_COLOR" ;; esac

# Narrow terminals: account goes first, then bar length, then reset times.
printf '%s' '{"oauthAccount":{"displayName":"Sam","organizationType":"claude_max"}}' > "$CLAUDE_CONFIG_DIR/.claude.json"
line1() { printf '%s' "$busy" | COLUMNS="$1" node "$ROOT/statuslines/cc-statusline.js" | sed -E 's/\x1b\[[0-9;]*m//g' | head -n 1; }
wide="$(line1 400)"
assert_has "$wide" "Sam · Max │ Opus" "cc wide shows account"
no_account="$(line1 $(( ${#wide} - 1 )))"
case "$no_account" in "Opus"*) ;; *) fail "cc narrow keeps account: $no_account" ;; esac
assert_has "$no_account" "CTX ███░░░░░" "cc narrow keeps full bars first"
tight="$(line1 20)"
assert_has "$tight" "CTX ██░░ 40%" "cc tight shortens bars"
assert_lacks "$tight" "↺" "cc tight drops reset times"

# Account info is re-read when ~/.claude.json changes.
printf '%s' '{"oauthAccount":{"displayName":"Alexandra"}}' > "$CLAUDE_CONFIG_DIR/.claude.json"
assert_has "$(line1 400)" "Alexandra" "cc account cache follows file changes"
rm "$CLAUDE_CONFIG_DIR/.claude.json"

echo "statusline script tests passed"
