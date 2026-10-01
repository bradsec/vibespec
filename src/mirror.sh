#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=src/lib.sh
source "${SCRIPT_DIR}/lib.sh" 2>/dev/null || \
    source <(curl -fsSL "https://raw.githubusercontent.com/bradsec/vibespec/main/src/lib.sh")

# Paths mirrored per tool, relative to the profile directory. An allowlist, so
# files a CLI adds later (credentials, caches, state) are never copied.
MIRROR_CLAUDE_PATHS=(
    CLAUDE.md settings.json hooks skills agents commands
    plugins/installed_plugins.json plugins/known_marketplaces.json
    plugins/cache plugins/marketplaces
)
MIRROR_CODEX_PATHS=(AGENTS.md config.toml rules skills plugins/cache)

# Copied config files whose embedded source-profile paths point at the target.
MIRROR_CLAUDE_REWRITE=(CLAUDE.md settings.json plugins/installed_plugins.json plugins/known_marketplaces.json)
MIRROR_CODEX_REWRITE=(AGENTS.md config.toml)

# Copied directories kept byte-identical; mirror only reports source paths in them.
MIRROR_CLAUDE_SCAN=(hooks skills agents commands plugins/cache plugins/marketplaces)
MIRROR_CODEX_SCAN=(rules skills plugins/cache)

MIRROR_SNAPSHOT_ROOT=".vibespec-mirror-backup"

mirror_select_tool() {
    case "$1" in
        claude)
            MIRROR_PATHS=("${MIRROR_CLAUDE_PATHS[@]}")
            MIRROR_REWRITE=("${MIRROR_CLAUDE_REWRITE[@]}")
            MIRROR_SCAN=("${MIRROR_CLAUDE_SCAN[@]}")
            MIRROR_MARKERS=(settings.json CLAUDE.md)
            MIRROR_DEFAULT_NAME=".claude"
            ;;
        codex)
            MIRROR_PATHS=("${MIRROR_CODEX_PATHS[@]}")
            MIRROR_REWRITE=("${MIRROR_CODEX_REWRITE[@]}")
            MIRROR_SCAN=("${MIRROR_CODEX_SCAN[@]}")
            MIRROR_MARKERS=(config.toml AGENTS.md)
            MIRROR_DEFAULT_NAME=".codex"
            ;;
        *)
            print_message error "Unknown tool: $1 (expected claude or codex)"
            return 1
            ;;
    esac
}

# Claude Code keeps MCP servers and account state in .claude.json: inside the
# profile when launched with CLAUDE_CONFIG_DIR, else in $HOME for ~/.claude.
claude_global_config() {
    local profile="$1"
    if [[ -e "$profile/.claude.json" ]]; then
        printf '%s\n' "$profile/.claude.json"
    elif [[ "$(realpath -m "$profile")" == "$(realpath -m "$HOME/.claude")" ]]; then
        printf '%s\n' "$HOME/.claude.json"
    else
        printf '%s\n' "$profile/.claude.json"
    fi
}

mirror_check_parse() {
    local file="$1"
    case "$file" in
        *.json|*.toml) ;;
        *) return 0 ;;
    esac
    [[ -e "$file" ]] || return 0
    python3 - "$file" <<'PY'
import json
import sys

path = sys.argv[1]
try:
    if path.endswith(".toml"):
        import tomllib
        with open(path, "rb") as fh:
            tomllib.load(fh)
    else:
        with open(path, encoding="utf-8") as fh:
            if not isinstance(json.load(fh), dict):
                raise ValueError("not a JSON object")
except Exception as exc:
    print(f"{path}: {exc}", file=sys.stderr)
    sys.exit(1)
PY
}

mirror_validate() {
    local tool="$1" source="$2" target="$3" marker found="" file src_real dst_real
    if ! command_exists python3; then
        print_message error "python3 is required to mirror profiles."
        return 1
    fi
    if [[ "$tool" == codex ]] && ! python3 -c 'import tomllib' 2>/dev/null; then
        print_message error "Python 3.11+ is required to mirror Codex profiles."
        return 1
    fi
    if [[ ! -d "$source" ]]; then
        print_message error "Source profile does not exist: ${source}"
        return 1
    fi
    for marker in "${MIRROR_MARKERS[@]}"; do
        if [[ -e "$source/$marker" ]]; then
            found=1
        fi
    done
    if [[ -z "$found" ]]; then
        print_message error "Source has no ${MIRROR_MARKERS[*]}; not a ${tool} profile: ${source}"
        return 1
    fi
    # Rewritten config files embed the target path in JSON and TOML strings.
    if [[ "$target" == *[\"\'\\]* ]]; then
        print_message error "Target path must not contain quotes or backslashes: ${target}"
        return 1
    fi
    src_real="$(realpath -m "$source")"
    dst_real="$(realpath -m "$target")"
    if [[ "$src_real" == "$dst_real" ]]; then
        print_message error "Source and target are the same directory: ${src_real}"
        return 1
    fi
    if [[ "$dst_real/" == "$src_real/"* || "$src_real/" == "$dst_real/"* ]]; then
        print_message error "Source and target must not contain each other."
        return 1
    fi
    local files=()
    for file in "${MIRROR_REWRITE[@]}"; do
        files+=("$source/$file")
    done
    if [[ "$tool" == claude ]]; then
        files+=("$(claude_global_config "$source")" "$(claude_global_config "$target")")
    fi
    for file in "${files[@]}"; do
        if ! mirror_check_parse "$file"; then
            print_message error "Cannot parse ${file}; fix it and run mirror again."
            return 1
        fi
    done
}

mirror_plan() {
    local source="$1" target="$2" path action
    print_message header "Mirror plan: ${source} -> ${target}"
    for path in "${MIRROR_PATHS[@]}"; do
        if [[ -e "$source/$path" || -L "$source/$path" ]]; then
            if [[ -e "$target/$path" || -L "$target/$path" ]]; then
                action="replace"
            else
                action="create"
            fi
        elif [[ -e "$target/$path" || -L "$target/$path" ]]; then
            action="remove"
        else
            action="skip"
        fi
        printf '  %-8s %s\n' "$action" "$path"
    done
}

mirror_snapshot_dir() {
    local target="$1" base dir n=1
    base="$target/$MIRROR_SNAPSHOT_ROOT/$(date +%d%m%Y)"
    dir="$base"
    while [[ -e "$dir" ]]; do
        dir="${base}.${n}"
        n=$((n + 1))
    done
    printf '%s\n' "$dir"
}

# Callers test these functions with `||`, which disables errexit inside them,
# so every step checks its own status.
mirror_copy_paths() {
    local source="$1" target="$2" snapshot="$3" path
    for path in "${MIRROR_PATHS[@]}"; do
        if [[ -e "$target/$path" || -L "$target/$path" ]]; then
            mkdir -p "$(dirname "$snapshot/$path")" || return 1
            mv "$target/$path" "$snapshot/$path" || return 1
        fi
        if [[ -e "$source/$path" || -L "$source/$path" ]]; then
            mkdir -p "$(dirname "$target/$path")" || return 1
            cp -a "$source/$path" "$target/$path" || return 1
        fi
    done
}

mirror_claude_mcp() {
    local source_config="$1" target_config="$2" snapshot="$3"
    if [[ -e "$target_config" ]]; then
        mkdir -p "$snapshot/global-config" || return 1
        cp "$target_config" "$snapshot/global-config/.claude.json" || return 1
    fi
    python3 - "$source_config" "$target_config" <<'PY'
import json
import os
import sys
import tempfile

source_path, target_path = sys.argv[1], sys.argv[2]


def load(path):
    try:
        with open(path, encoding="utf-8") as fh:
            return json.load(fh)
    except FileNotFoundError:
        return None


source = load(source_path) or {}
target = load(target_path)
if target is None:
    if "mcpServers" not in source:
        sys.exit(0)
    target = {}

if "mcpServers" in source:
    target["mcpServers"] = source["mcpServers"]
else:
    target.pop("mcpServers", None)

# Write through a symlink to its target so dotfile-managed configs stay links.
real = os.path.realpath(target_path)
directory = os.path.dirname(real)
os.makedirs(directory, exist_ok=True)
fd, tmp = tempfile.mkstemp(dir=directory, prefix=".claude.json.")
try:
    with os.fdopen(fd, "w", encoding="utf-8") as fh:
        json.dump(target, fh, indent=2)
        fh.write("\n")
    if os.path.exists(real):
        os.chmod(tmp, os.stat(real).st_mode & 0o7777)
    os.replace(tmp, real)
except BaseException:
    if os.path.exists(tmp):
        os.unlink(tmp)
    raise
PY
}

mirror_rewrite_paths() {
    local source="$1" target="$2" path files=()
    for path in "${MIRROR_REWRITE[@]}"; do
        if [[ -f "$target/$path" ]]; then
            files+=("$target/$path")
        fi
    done
    [[ ${#files[@]} -gt 0 ]] || return 0
    MIRROR_SOURCE="$source" MIRROR_TARGET="$target" MIRROR_HOME="$HOME" \
        MIRROR_NAME="$MIRROR_DEFAULT_NAME" python3 - "${files[@]}" <<'PY'
import os
import re
import sys

source = os.environ["MIRROR_SOURCE"]
target = os.path.realpath(os.environ["MIRROR_TARGET"])
home = os.environ["MIRROR_HOME"]
name = os.environ["MIRROR_NAME"]

prefixes = {os.path.abspath(source), os.path.realpath(source)}
if os.path.realpath(source) == os.path.realpath(os.path.join(home, name)):
    prefixes |= {os.path.join(home, name), f"~/{name}", f"$HOME/{name}", f"${{HOME}}/{name}"}
# Longest first, and only at a path boundary, so ~/.claude never matches ~/.claude-work.
alternatives = "|".join(re.escape(p) for p in sorted(prefixes, key=len, reverse=True))
pattern = re.compile(f"(?:{alternatives})(?=[/\"'\\s]|$)", re.MULTILINE)

for path in sys.argv[1:]:
    with open(path, encoding="utf-8") as fh:
        text = fh.read()
    updated = pattern.sub(lambda _match: target, text)
    if updated == text:
        continue
    mode = os.stat(path).st_mode & 0o7777
    tmp = f"{path}.vibespec-tmp"
    with open(tmp, "w", encoding="utf-8") as fh:
        fh.write(updated)
    os.chmod(tmp, mode)
    # Replace the path itself: a symlinked copy becomes a regular file, so the
    # shared file it pointed at (for example a dotfiles repo) stays unchanged.
    os.replace(tmp, path)
PY
}

mirror_scan_refs() {
    local source="$1" target="$2" path src_real hits="" found
    src_real="$(realpath -m "$source")"
    for path in "${MIRROR_SCAN[@]}"; do
        [[ -d "$target/$path" ]] || continue
        found="$(grep -rlF -e "$source" -e "$src_real" -- "$target/$path" 2>/dev/null || true)"
        if [[ -n "$found" ]]; then
            hits+="${found}"$'\n'
        fi
    done
    [[ -n "$hits" ]] || return 0
    print_message warning "These copied files still reference ${source}; mirror leaves them unchanged:"
    while IFS= read -r path; do
        [[ -n "$path" ]] && printf '  %s\n' "$path"
    done <<< "$hits"
    return 0
}

mirror_secrets_warning() {
    local tool="$1" source="$2" names line
    if [[ "$tool" == claude ]]; then
        names="$(python3 - "$source/settings.json" "$(claude_global_config "$source")" <<'PY'
import json
import sys


def load(path):
    try:
        with open(path, encoding="utf-8") as fh:
            data = json.load(fh)
    except FileNotFoundError:
        return {}
    return data if isinstance(data, dict) else {}


settings, config = load(sys.argv[1]), load(sys.argv[2])
env = settings.get("env")
for key in sorted(env if isinstance(env, dict) else {}):
    print(f"settings env: {key}")
if "apiKeyHelper" in settings:
    print("settings: apiKeyHelper")
servers = config.get("mcpServers")
servers = servers if isinstance(servers, dict) else {}
for name in sorted(servers):
    print(f"MCP server: {name}")
    server = servers[name] if isinstance(servers[name], dict) else {}
    server_env = server.get("env")
    for key in sorted(server_env if isinstance(server_env, dict) else {}):
        print(f"MCP server {name} env: {key}")
PY
)" || return 1
    else
        names="$(python3 - "$source/config.toml" <<'PY'
import sys
import tomllib

try:
    with open(sys.argv[1], "rb") as fh:
        config = tomllib.load(fh)
except FileNotFoundError:
    config = {}
servers = config.get("mcp_servers")
servers = servers if isinstance(servers, dict) else {}
for name in sorted(servers):
    print(f"MCP server: {name}")
    server = servers[name] if isinstance(servers[name], dict) else {}
    for field in ("env", "env_vars"):
        value = server.get(field)
        if isinstance(value, (dict, list)):
            for key in sorted(str(item) for item in value):
                print(f"MCP server {name} {field}: {key}")
PY
)" || return 1
    fi
    [[ -n "$names" ]] || return 0
    print_message warning "These may carry API keys or tokens into the target account:"
    while IFS= read -r line; do
        printf '  %s\n' "$line"
    done <<< "$names"
}

mirror_apply() {
    local tool="$1" source="$2" target="$3" snapshot="$4" file source_config="" target_config=""
    if [[ "$tool" == claude ]]; then
        source_config="$(claude_global_config "$source")"
        target_config="$(claude_global_config "$target")"
    fi
    mirror_copy_paths "$source" "$target" "$snapshot" || return 1
    if [[ "$tool" == claude ]]; then
        mirror_claude_mcp "$source_config" "$target_config" "$snapshot" || return 1
    fi
    mirror_rewrite_paths "$source" "$target" || return 1
    for file in "${MIRROR_REWRITE[@]}"; do
        mirror_check_parse "$target/$file" || return 1
    done
    if [[ -n "$target_config" ]]; then
        mirror_check_parse "$target_config" || return 1
    fi
}

# Mirror one profile directory onto another. tool: claude or codex.
mirror_profile() {
    local tool="$1" source="${2%/}" target="${3%/}" snapshot
    mirror_select_tool "$tool" || return 1
    mirror_validate "$tool" "$source" "$target" || return 1
    mirror_plan "$source" "$target"
    if [[ "$tool" == claude ]]; then
        printf '  %-8s %s\n' "update" "mcpServers in $(claude_global_config "$target")"
    fi
    mirror_secrets_warning "$tool" "$source" || return 1
    print_message info "Close sessions that use the target profile before continuing."
    if ! confirm "Mirror ${source} onto ${target}?"; then
        print_message info "Mirror cancelled; nothing changed."
        return 0
    fi
    snapshot="$(mirror_snapshot_dir "$target")"
    mkdir -p "$snapshot"
    if ! mirror_apply "$tool" "$source" "$target" "$snapshot"; then
        print_message error "Mirror failed; the target is partial. Previous files: ${snapshot}"
        return 1
    fi
    mirror_scan_refs "$source" "$target"
    record_install "mirror:${tool}:$(slugify "$target")" "mirror" "$source" "$target" "$snapshot"
    print_message success "Mirrored ${source} onto ${target}"
    print_message info "Previous target files: ${snapshot}"
    print_message info "To restore, move the snapshot contents back into ${target}."
}

mirror_menu_profile() {
    local tool="$1" label="$2" source
    prompt_profile_dir "Source ${label}" || return 1
    source="$PROFILE_DIR"
    prompt_profile_dir "Target ${label}" || return 1
    mirror_profile "$tool" "$source" "$PROFILE_DIR"
}

main() {
    while true; do
        menu_select "Mirror Profiles" \
            "Mirror Claude Code profile" \
            "Mirror Codex profile" \
            "Back"
        case "$MENU_CHOICE" in
            1) run_install mirror_menu_profile claude "Claude Code" ;;
            2) run_install mirror_menu_profile codex "Codex" ;;
            3) return ;;
        esac
    done
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main
fi
