#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_RAW="https://raw.githubusercontent.com/bradsec/vibespec/main"

# shellcheck source=src/lib.sh
source "${SCRIPT_DIR}/lib.sh" 2>/dev/null || \
    source <(curl -fsSL "${REPO_RAW}/src/lib.sh")

run_statusline_script() {
    local script="$1"
    local profile_dir="${2:-}"
    if [[ ! "$script" =~ ^[a-zA-Z0-9_-]+-[a-zA-Z0-9_-]+\.sh$ ]]; then
        print_message error "Invalid script name: ${script}"
        return 1
    fi
    local -a runner=(bash)
    case "$script" in
        cc-*.sh)
            if [[ -n "$profile_dir" ]]; then
                runner=(env "CLAUDE_CONFIG_DIR=$profile_dir" bash)
            else
                profile_dir="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
            fi
            ;;
        codex-*.sh)
            if [[ -n "$profile_dir" ]]; then
                runner=(env "CODEX_HOME=$profile_dir" bash)
            else
                profile_dir="${CODEX_HOME:-$HOME/.codex}"
            fi
            ;;
        *)
            if [[ -n "$profile_dir" ]]; then
                print_message error "Custom profiles are available for Claude Code and Codex only."
                return 1
            fi
            ;;
    esac
    local repo_root
    repo_root="$(dirname "$SCRIPT_DIR")"
    local local_path="${repo_root}/statuslines/${script}"
    if [[ -f "$local_path" ]]; then
        "${runner[@]}" "$local_path" || return $?
    else
        local tmpfile
        tmpfile=$(mktemp /tmp/vibespec-statusline-XXXXXX.sh)
        if ! curl -fsSL "${REPO_RAW}/statuslines/${script}" -o "$tmpfile" 2>/dev/null; then
            rm -f "$tmpfile"
            print_message error "Remote fetch failed for ${script} and no local copy found."
            return 1
        fi
        local result=0
        "${runner[@]}" "$tmpfile" || result=$?
        rm -f "$tmpfile"
        if (( result != 0 )); then
            return "$result"
        fi
    fi

    case "$script" in
        cc-install.sh)
            local install_id="statusline:claude-code"
            [[ "$profile_dir" == "$HOME/.claude" ]] || install_id+=":$profile_dir"
            record_install "$install_id" "statusline" "$script" "$profile_dir/hooks/cc-statusline.js" "$profile_dir/settings.json"
            ;;
        codex-install.sh)
            local install_id="statusline:codex"
            [[ "$profile_dir" == "$HOME/.codex" ]] || install_id+=":$profile_dir"
            record_install "$install_id" "statusline" "$script" "$profile_dir/config.toml"
            ;;
        antigravity-install.sh)
            record_install "statusline:antigravity" "statusline" "$script" "$HOME/.gemini/antigravity-cli/statusline.js" "$HOME/.gemini/antigravity-cli/settings.json"
            ;;
    esac
}

run_custom_statusline_script() {
    local script="$1" tool="$2"
    prompt_profile_dir "$tool" || return 1
    run_statusline_script "$script" "$PROFILE_DIR"
}

install_all() {
    run_statusline_script "cc-install.sh"
    run_statusline_script "codex-install.sh"
    run_statusline_script "antigravity-install.sh"
}

reset_all() {
    run_statusline_script "cc-reset.sh"
    run_statusline_script "codex-reset.sh"
    run_statusline_script "antigravity-reset.sh"
}

main() {
    while true; do
        menu_select "Install / Reset Status Lines" \
            "Install Claude Code statusline" \
            "Install Codex statusline" \
            "Install Antigravity CLI statusline" \
            "Install all statuslines" \
            "Reset Claude Code statusline" \
            "Reset Codex statusline" \
            "Reset Antigravity CLI statusline" \
            "Reset all statuslines" \
            "Install Claude Code statusline in custom profile" \
            "Install Codex statusline in custom profile" \
            "Reset Claude Code statusline in custom profile" \
            "Reset Codex statusline in custom profile" \
            "Back"
        case "$MENU_CHOICE" in
            1)  run_statusline_script "cc-install.sh" ;;
            2)  run_statusline_script "codex-install.sh" ;;
            3)  run_statusline_script "antigravity-install.sh" ;;
            4)  install_all ;;
            5)  run_statusline_script "cc-reset.sh" ;;
            6)  run_statusline_script "codex-reset.sh" ;;
            7)  run_statusline_script "antigravity-reset.sh" ;;
            8)  reset_all ;;
            9)  run_custom_statusline_script "cc-install.sh" "Claude Code" ;;
            10) run_custom_statusline_script "codex-install.sh" "Codex" ;;
            11) run_custom_statusline_script "cc-reset.sh" "Claude Code" ;;
            12) run_custom_statusline_script "codex-reset.sh" "Codex" ;;
            13) return ;;
        esac
        pause
    done
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main
fi
