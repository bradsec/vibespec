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

# ── Codex (placeholder schema) ───────────────────────────────────────────────

codex_json='{"model":"gpt-5.6","reasoning_effort":"high","cwd":"/tmp/proj","git_branch":"main",
"context":{"used_percent":17,"used_tokens":176000,"window_tokens":1000000},
"prompt_cache":{"hit_ratio":0.8}}'
out="$(run codex-statusline.js "$codex_json")"
assert_has "$out" "gpt-5.6 [high]" "codex model + effort"
assert_has "$out" "17%"            "codex context bar"
assert_has "$out" "80%"            "codex prompt_cache.hit_ratio"

out="$(run codex-statusline.js '{"model":"gpt-5.6"}')"
assert_has "$out" "gpt-5.6" "codex minimal payload"

echo "statusline script tests passed"
