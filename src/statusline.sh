#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_RAW="https://raw.githubusercontent.com/bradsec/vibespec/main"

# shellcheck source=src/lib.sh
source "${SCRIPT_DIR}/lib.sh" 2>/dev/null || \
    source <(curl -fsSL "${REPO_RAW}/src/lib.sh")

run_statusline_script() {
    local script="$1"
    if [[ ! "$script" =~ ^[a-zA-Z0-9_-]+-[a-zA-Z0-9_-]+\.sh$ ]]; then
        print_message error "Invalid script name: ${script}"
        return 1
    fi
    local repo_root
    repo_root="$(dirname "$SCRIPT_DIR")"
    local local_path="${repo_root}/statuslines/${script}"
    if [[ -f "$local_path" ]]; then
        bash "$local_path"
    else
        local tmpfile
        tmpfile=$(mktemp /tmp/vibespec-statusline-XXXXXX.sh)
        if ! curl -fsSL "${REPO_RAW}/statuslines/${script}" -o "$tmpfile" 2>/dev/null; then
            rm -f "$tmpfile"
            print_message error "Remote fetch failed for ${script} and no local copy found."
            return 1
        fi
        bash "$tmpfile"
        rm -f "$tmpfile"
    fi

    case "$script" in
        cc-install.sh)
            record_install "statusline:claude-code" "statusline" "$script" "$HOME/.claude/hooks/cc-statusline.js" "$HOME/.claude/settings.json"
            ;;
        codex-install.sh)
            record_install "statusline:codex" "statusline" "$script" "$HOME/.codex/config.toml"
            ;;
        antigravity-install.sh)
            record_install "statusline:antigravity" "statusline" "$script" "$HOME/.gemini/antigravity-cli/statusline.js" "$HOME/.gemini/antigravity-cli/settings.json"
            ;;
        copilot-install.sh)
            record_install "statusline:copilot" "statusline" "$script" "$HOME/.copilot/statusline.js" "$HOME/.copilot/settings.json"
            ;;
    esac
}

install_all() {
    run_statusline_script "cc-install.sh"
    run_statusline_script "codex-install.sh"
    run_statusline_script "antigravity-install.sh"
    run_statusline_script "copilot-install.sh"
}

reset_all() {
    run_statusline_script "cc-reset.sh"
    run_statusline_script "codex-reset.sh"
    run_statusline_script "antigravity-reset.sh"
    run_statusline_script "copilot-reset.sh"
}

main() {
    while true; do
        menu_select "Install / Reset Status Lines" \
            "Install Claude Code statusline" \
            "Install Codex statusline" \
            "Install Antigravity CLI statusline" \
            "Install GitHub Copilot CLI statusline" \
            "Install all statuslines" \
            "Reset Claude Code statusline" \
            "Reset Codex statusline" \
            "Reset Antigravity CLI statusline" \
            "Reset GitHub Copilot CLI statusline" \
            "Reset all statuslines" \
            "Back"
        case "$MENU_CHOICE" in
            1)  run_statusline_script "cc-install.sh" ;;
            2)  run_statusline_script "codex-install.sh" ;;
            3)  run_statusline_script "antigravity-install.sh" ;;
            4)  run_statusline_script "copilot-install.sh" ;;
            5)  install_all ;;
            6)  run_statusline_script "cc-reset.sh" ;;
            7)  run_statusline_script "codex-reset.sh" ;;
            8)  run_statusline_script "antigravity-reset.sh" ;;
            9)  run_statusline_script "copilot-reset.sh" ;;
            10) reset_all ;;
            11) return ;;
        esac
        pause
    done
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main
fi
