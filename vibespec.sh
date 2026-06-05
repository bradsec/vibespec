#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_RAW="https://raw.githubusercontent.com/bradsec/vibespec/main"
LIB="${SCRIPT_DIR}/src/lib.sh"

if [[ -f "$LIB" ]]; then
    # shellcheck source=src/lib.sh
    source "$LIB"
else
    TMPLIB=$(mktemp /tmp/vibespec-lib.XXXXXX.sh)
    curl -fsSL "${REPO_RAW}/src/lib.sh" -o "$TMPLIB"
    # shellcheck source=/dev/null
    source "$TMPLIB"
    rm -f "$TMPLIB"
fi

run_script() {
    local script="$1"
    if [[ ! "$script" =~ ^[a-zA-Z0-9_-]+\.sh$ ]]; then
        print_message error "Invalid script name: ${script}"
        return 1
    fi
    local local_path="${SCRIPT_DIR}/src/${script}"
    if [[ -f "$local_path" ]]; then
        bash "$local_path"
    else
        local tmpfile
        tmpfile=$(mktemp /tmp/vibespec-XXXXXX.sh)
        curl -fsSL "${REPO_RAW}/src/${script}" -o "$tmpfile"
        bash "$tmpfile"
        rm -f "$tmpfile"
    fi
}

main() {
    while true; do
        menu_select "Main Menu" \
            "Install AI Coding CLI Tools" \
            "Configure AI Coding Rules" \
            "Install Status Lines" \
            "Exit"
        case "$MENU_CHOICE" in
            1) run_script "tools.sh" ;;
            2) run_script "config.sh" ;;
            3) run_script "statusline.sh" ;;
            4) echo; print_message info "Done."; exit 0 ;;
        esac
    done
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main
fi
