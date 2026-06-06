#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=src/lib.sh
source "${SCRIPT_DIR}/lib.sh" 2>/dev/null || \
    source <(curl -fsSL "https://raw.githubusercontent.com/bradsec/vibespec/main/src/lib.sh")

RULES_MD_URL="https://raw.githubusercontent.com/bradsec/vibespec/main/RULES.md"

sha256_file() {
    local file="$1"
    if command_exists sha256sum; then
        sha256sum "$file" | awk '{print $1}'
    elif command_exists shasum; then
        shasum -a 256 "$file" | awk '{print $1}'
    else
        printf 'unavailable'
    fi
}

# Tool name → destination path
declare -A TOOL_PATHS
TOOL_PATHS["Claude Code"]="$HOME/.claude/CLAUDE.md"
TOOL_PATHS["Codex"]="$HOME/.codex/AGENTS.md"
TOOL_PATHS["Antigravity CLI"]="$HOME/.gemini/AGENTS.md"

# Tool name → restart instructions shown after install
declare -A TOOL_RESTART
TOOL_RESTART["Claude Code"]="Restart Claude Code or run /reload in an active session."
TOOL_RESTART["Codex"]="Restart Codex to load the new rules."
TOOL_RESTART["Antigravity CLI"]="Restart Antigravity CLI to load the new rules."

install_config() {
    local tool="$1"
    local dest="${TOOL_PATHS[$tool]}"
    local filename
    filename="$(basename "$dest")"
    print_message header "Configuring ${tool}"
    mkdir -p "$(dirname "$dest")"
    local tmp fetched=0 rules_source=""
    local local_rules="${SCRIPT_DIR}/../RULES.md"
    tmp="$(mktemp)"
    if command_exists curl; then
        if curl -fsSL "$RULES_MD_URL" -o "$tmp" 2>/dev/null; then
            fetched=1
            rules_source="remote ${RULES_MD_URL}"
        fi
    elif command_exists wget; then
        if wget -qO "$tmp" "$RULES_MD_URL" 2>/dev/null; then
            fetched=1
            rules_source="remote ${RULES_MD_URL}"
        fi
    fi
    if [[ $fetched -eq 0 ]]; then
        if [[ -f "$local_rules" ]]; then
            print_message warning "Remote unavailable — using local RULES.md"
            cp "$local_rules" "$tmp"
            rules_source="local ${local_rules}"
        else
            rm -f "$tmp"
            print_message error "Remote fetch failed and RULES.md not found locally."
            return 1
        fi
    fi
    print_message info "Rules source: ${rules_source}"
    local new_file
    new_file="$(mktemp)"
    { printf '# %s\n' "${filename}"; tail -n +2 "$tmp"; } > "$new_file"
    rm -f "$tmp"

    if [[ -f "$dest" ]] && cmp -s "$new_file" "$dest"; then
        rm -f "$new_file"
        print_message success "Rules already up to date: ${dest}"
        record_install "config:$(slugify "$tool")" "config" "RULES.md" "$dest"
        [[ -n "${TOOL_RESTART[$tool]:-}" ]] && print_message info "${TOOL_RESTART[$tool]}"
        return
    fi

    if [[ -f "$dest" ]]; then
        local backup_path
        backup_path="${dest}.$(date +%d%m%Y).bak"
        print_message info "Existing SHA256: $(sha256_file "$dest")"
        print_message info "New SHA256: $(sha256_file "$new_file")"
        cp "$dest" "$backup_path"
        print_message info "Backed up existing file: ${backup_path}"
    fi
    mv "$new_file" "$dest"
    print_message success "Rules installed: ${dest}"
    record_install "config:$(slugify "$tool")" "config" "RULES.md" "$dest"
    [[ -n "${TOOL_RESTART[$tool]:-}" ]] && print_message info "${TOOL_RESTART[$tool]}"
}

main() {
    while true; do
        menu_select "Configure AI Coding Rules" \
            "Configure Claude Code  (~/.claude/CLAUDE.md)" \
            "Configure Codex        (~/.codex/AGENTS.md)" \
            "Configure Antigravity  (~/.gemini/AGENTS.md)" \
            "Configure all tools" \
            "Back"
        case "$MENU_CHOICE" in
            1) run_install install_config "Claude Code" ;;
            2) run_install install_config "Codex" ;;
            3) run_install install_config "Antigravity CLI" ;;
            4)
                run_install install_config "Claude Code"
                run_install install_config "Codex"
                run_install install_config "Antigravity CLI"
                ;;
            5) return ;;
        esac
    done
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main
fi
