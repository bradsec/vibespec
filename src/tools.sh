#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_RAW="https://raw.githubusercontent.com/bradsec/vibespec/main"
# shellcheck source=src/lib.sh
source "${SCRIPT_DIR}/lib.sh" 2>/dev/null || \
    source <(curl -fsSL "${REPO_RAW}/src/lib.sh")

# Run a known statusline reset script (local copy, else fetched from the repo).
# Allowlisted by name; never runs an arbitrary script path.
run_statusline_reset() {
    local script="$1"
    case "$script" in
        codex-reset.sh|copilot-reset.sh) ;;
        *) print_message error "Refusing unknown reset script: ${script}"; return 1 ;;
    esac

    local local_path="${SCRIPT_DIR}/../statuslines/${script}"
    if [[ -f "$local_path" ]]; then
        bash "$local_path" || print_message warning "${script} failed; continuing."
        return 0
    fi

    local tmpfile
    tmpfile="$(mktemp /tmp/vibespec-reset-XXXXXX.sh)"
    if curl -fsSL "${REPO_RAW}/statuslines/${script}" -o "$tmpfile" 2>/dev/null; then
        bash "$tmpfile" || print_message warning "${script} failed; continuing."
    else
        print_message warning "Could not fetch ${script}; skipping statusline reset."
    fi
    rm -f "$tmpfile"
}

install_nvm() {
    local skip_apt_prompt="${1:-}"

    print_message header "Installing nvm (Node Version Manager)"
    if [[ -s "$HOME/.nvm/nvm.sh" ]]; then
        print_message success "nvm already installed at ~/.nvm"
        record_install "tool:nvm" "tool" "nvm installer" "$HOME/.nvm/nvm.sh"
        return
    fi
    if [[ "$skip_apt_prompt" != "skip-apt-prompt" ]] && confirm "Remove system node/npm via apt first? (recommended for nvm)"; then
        sudo apt remove -y nodejs npm 2>/dev/null || true
        sudo apt autoremove -y 2>/dev/null || true
    fi
    print_message info "Running nvm installer..."
    curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/master/install.sh | bash
    print_message success "nvm installed."
    record_install "tool:nvm" "tool" "nvm installer" "$HOME/.nvm/nvm.sh"
    print_message warning "Restart terminal, then run: nvm install --lts && nvm use --delete-prefix --lts"
    print_message warning "After that, re-run vibespec to install Node-based CLI tools."
}

nvm_without_nounset() {
    local restore_nounset=0
    local status

    if [[ "$-" == *u* ]]; then
        restore_nounset=1
        set +u
    fi

    "$@"
    status=$?

    if [[ "$restore_nounset" -eq 1 ]]; then
        set -u
    fi

    return "$status"
}

install_node_lts() {
    export NVM_DIR="$HOME/.nvm"
    if [[ ! -s "$NVM_DIR/nvm.sh" ]]; then
        print_message error "nvm was not found at ~/.nvm/nvm.sh"
        return 1
    fi

    # shellcheck source=/dev/null
    nvm_without_nounset source "$NVM_DIR/nvm.sh"
    if ! declare -F nvm >/dev/null; then
        print_message error "nvm did not load correctly."
        return 1
    fi

    nvm_without_nounset nvm install --lts
    nvm_without_nounset nvm use --delete-prefix --lts
    ensure_node
    print_message success "Node.js LTS installed."
}

replace_node() {
    print_message header "Removing existing Node.js installations"
    if command_exists sudo; then
        sudo apt remove -y nodejs npm 2>/dev/null || true
        sudo apt autoremove -y 2>/dev/null || true
    else
        print_message warning "sudo not found; skipping apt removal for nodejs/npm."
    fi

    if [[ -d "$HOME/.nvm" ]]; then
        rm -rf "$HOME/.nvm"
        print_message success "Removed ~/.nvm"
    fi

    install_nvm skip-apt-prompt
    install_node_lts
}

node_usable() {
    command_exists node && node --version >/dev/null 2>&1
}

npm_usable() {
    command_exists npm && npm --version >/dev/null 2>&1
}

# Load nvm into current shell if available; return 1 if node still missing
ensure_node() {
    export NVM_DIR="$HOME/.nvm"
    # shellcheck source=/dev/null
    [[ -s "$NVM_DIR/nvm.sh" ]] && nvm_without_nounset source "$NVM_DIR/nvm.sh"
    if ! command_exists node; then
        print_message error "Node.js not found. Install nvm (option 1) and run: nvm install --lts"
        return 1
    fi
    if ! node_usable; then
        print_message error "Node.js command exists but failed to run: $(command -v node)"
        print_message error "Use the replace Node.js/nvm option, then run: nvm install --lts && nvm use --delete-prefix --lts"
        return 1
    fi
    if ! command_exists npm; then
        print_message error "npm not found. Run: nvm install --lts && nvm use --delete-prefix --lts"
        return 1
    fi
    if ! npm_usable; then
        print_message error "npm command exists but failed to run: $(command -v npm)"
        print_message error "Use the replace Node.js/nvm option, then run: nvm install --lts && nvm use --delete-prefix --lts"
        return 1
    fi
}

remove_user_command() {
    local cmd="$1"
    local path

    path="$(command -v "$cmd" 2>/dev/null || true)"
    if [[ -z "$path" ]]; then
        return 0
    fi

    case "$path" in
        "$HOME"/*)
            rm -f "$path"
            print_message success "Removed ${cmd}: ${path}"
            ;;
        *)
            print_message warning "Skipping ${cmd} outside home directory: ${path}"
            ;;
    esac
}

# After main uninstall, some binaries may still be reachable at system paths
# (e.g. /usr/local/bin) if they were installed as root via curl or sudo npm.
# Check each known command and offer a targeted sudo rm for any still found.
remove_system_path_residue() {
    local cmds=("claude" "codex" "agy" "copilot")
    local found=0
    local cmd path

    for cmd in "${cmds[@]}"; do
        path="$(command -v "$cmd" 2>/dev/null || true)"
        [[ -z "$path" ]] && continue
        [[ "$path" == "$HOME"/* ]] && continue
        found=1
        print_message warning "${cmd} still found at system path: ${path}"
        if command_exists sudo; then
            if confirm "Remove with: sudo rm \"${path}\""; then
                if sudo rm -f "$path"; then
                    print_message success "Removed ${path}"
                else
                    print_message error "sudo rm failed for ${path}"
                fi
            else
                print_message info "Skipped: ${path}"
            fi
        else
            print_message warning "sudo not available. Remove manually: sudo rm \"${path}\""
        fi
    done

    [[ "$found" -eq 0 ]] && print_message info "No tool binaries remain at system paths."
}

uninstall_all_coding_cli_tools() {
    print_message header "Uninstalling AI coding CLI tools and wiping all config"

    if [[ -z "${HOME:-}" || "$HOME" == "/" ]]; then
        print_message error "HOME is not safely set; aborting."
        return 1
    fi

    if command_exists npm; then
        npm uninstall -g @anthropic-ai/claude-code @openai/codex @github/copilot || \
            print_message warning "npm uninstall failed; continuing with cleanup."
    else
        print_message warning "npm not found; skipping npm package uninstall."
    fi

    # If codex is still present at a system path (e.g. installed via curl as root),
    # the user-space npm above won't see it. Retry via sudo using the system npm.
    if command_exists codex; then
        local codex_path
        codex_path="$(command -v codex)"
        if [[ "$codex_path" != "$HOME"/* ]] && command_exists sudo; then
            print_message info "Codex found at system path ${codex_path}; retrying with sudo npm..."
            sudo npm uninstall -g @openai/codex 2>/dev/null || \
                print_message warning "sudo npm uninstall failed. Run manually: sudo npm uninstall -g @openai/codex"
        fi
    fi

    remove_user_command claude
    remove_user_command codex
    remove_user_command agy
    remove_user_command copilot

    # Full Claude wipe: agents, skills, settings, chat history, projects, saved memory.
    remove_path_under_home "$HOME/.claude"
    # Claude global config file (configured servers and history).
    remove_path_under_home "$HOME/.claude.json"
    # Antigravity install directory and its statusline (installed via curl, not npm).
    remove_path_under_home "$HOME/.gemini/antigravity-cli"
    # vibespec-written rule files for the remaining tools.
    remove_path_under_home "$HOME/.codex/AGENTS.md"
    remove_path_under_home "$HOME/.gemini/AGENTS.md"
    remove_path_under_home "$HOME/.copilot/copilot-instructions.md"

    # Codex and Copilot statusline residue. Claude and Antigravity statuslines
    # live inside the directories wiped above; these two do not. Delete the
    # orphan scripts and surgically strip the statusline entries, leaving the
    # rest of config.toml / settings.json intact.
    remove_path_under_home "$HOME/.codex/statusline.js"
    remove_path_under_home "$HOME/.copilot/statusline.js"
    run_statusline_reset "codex-reset.sh"
    run_statusline_reset "copilot-reset.sh"

    # vibespec install-state tracking.
    remove_path_under_home "$HOME/.config/vibespec"

    # Backups left behind by previous rule installs.
    rm -f "$HOME"/.codex/AGENTS.md.*.bak \
          "$HOME"/.gemini/AGENTS.md.*.bak \
          "$HOME"/.copilot/copilot-instructions.md.*.bak 2>/dev/null || true

    # Final sweep: catch binaries still reachable at system paths (e.g. installed
    # via curl as root) that the steps above could not reach without sudo.
    remove_system_path_residue

    print_message success "All agents and config removed."
}

# Probe a remote installer source without running it: GET to /dev/null, never
# piped to a shell. Returns 0 if reachable or unprobeable, 1 only on a real miss.
check_installer_url() {
    local url="$1" code
    if ! command_exists curl; then
        print_message warning "curl not found; cannot check ${url}"
        return 0
    fi
    # No -f: let curl report 4xx/5xx codes instead of collapsing them to a
    # connection error, so the message shows the real status.
    code="$(curl -sL -o /dev/null --max-time 15 -w '%{http_code}' "$url" 2>/dev/null)" || code="000"
    if [[ "$code" == "200" ]]; then
        print_message success "reachable (${code}): ${url}"
        return 0
    fi
    print_message error "unreachable (${code}): ${url}"
    return 1
}

# Confirm an npm package resolves in the registry without installing it.
check_installer_npm() {
    local pkg="$1" ver
    if ! command_exists npm; then
        print_message warning "npm not found; cannot check ${pkg}"
        return 0
    fi
    if ver="$(npm view "$pkg" version 2>/dev/null)" && [[ -n "$ver" ]]; then
        print_message success "npm package ${pkg} (latest ${ver})"
        return 0
    fi
    print_message error "npm package not found: ${pkg}"
    return 1
}

# Preflight wrappers for install_* functions: bail with a clear message instead
# of attempting an install whose source cannot be reached.
require_installer_url() {
    local name="$1" url="$2"
    check_installer_url "$url" && return 0
    print_message error "${name} installer not available."
    return 1
}

require_installer_npm() {
    local name="$1" pkg="$2"
    check_installer_npm "$pkg" && return 0
    print_message error "${name} installer not available."
    return 1
}

verify_installers() {
    print_message header "Verifying installers (no install)"
    local fail=0 fn

    for fn in install_claude_code install_codex install_antigravity install_copilot; do
        if declare -F "$fn" >/dev/null; then
            print_message success "function defined: ${fn}"
        else
            print_message error "function missing: ${fn}"
            fail=1
        fi
    done

    if ! check_installer_npm "@anthropic-ai/claude-code"; then fail=1; fi
    if ! check_installer_url "https://chatgpt.com/codex/install.sh"; then fail=1; fi
    if ! check_installer_url "https://antigravity.google/cli/install.sh"; then fail=1; fi
    if ! check_installer_url "https://gh.io/copilot-install"; then fail=1; fi

    if [[ "$fail" -eq 0 ]]; then
        print_message success "All installers verified."
    else
        print_message warning "One or more installer checks failed (see above)."
    fi
    return 0
}

install_claude_code() {
    print_message header "Installing Claude Code"
    if command_exists claude; then
        print_message success "Claude Code already installed."
        print_message info "Version: $(claude --version 2>/dev/null || echo 'restart terminal to verify')"
        record_install "tool:claude-code" "tool" "existing claude command" "$(command -v claude)"
        return
    fi
    ensure_node || return 1
    require_installer_npm "Claude Code" "@anthropic-ai/claude-code" || return 1
    npm install -g @anthropic-ai/claude-code
    print_message success "Claude Code installed."
    record_install "tool:claude-code" "tool" "npm package @anthropic-ai/claude-code" "$(command -v claude 2>/dev/null || true)"
    command_exists claude && print_message info "Version: $(claude --version 2>/dev/null || echo 'restart terminal to verify')"
}

install_codex() {
    print_message header "Installing Codex (OpenAI)"
    if command_exists codex; then
        print_message success "Codex already installed."
        print_message info "Version: $(codex --version 2>/dev/null || echo 'restart terminal to verify')"
        record_install "tool:codex" "tool" "existing codex command" "$(command -v codex)"
        return
    fi
    if command_exists curl; then
        require_installer_url "Codex" "https://chatgpt.com/codex/install.sh" || return 1
        curl -fsSL https://chatgpt.com/codex/install.sh | sh
    elif command_exists npm; then
        ensure_node || return 1
        require_installer_npm "Codex" "@openai/codex" || return 1
        npm install -g @openai/codex
    else
        print_message error "Neither curl nor npm found. Install manually."
        return 1
    fi
    print_message success "Codex installed."
    record_install "tool:codex" "tool" "codex installer" "$(command -v codex 2>/dev/null || true)"
    command_exists codex && print_message info "Version: $(codex --version 2>/dev/null || echo 'restart terminal to verify')"
}

install_antigravity() {
    print_message header "Installing Antigravity CLI (Google)"
    if command_exists agy; then
        print_message success "Antigravity CLI already installed."
        print_message info "Version: $(agy --version 2>/dev/null || echo 'restart terminal to verify')"
        record_install "tool:antigravity" "tool" "existing agy command" "$(command -v agy)"
        return
    fi
    if command_exists curl; then
        require_installer_url "Antigravity CLI" "https://antigravity.google/cli/install.sh" || return 1
        curl -fsSL https://antigravity.google/cli/install.sh | bash
    else
        print_message error "curl not found. Install manually."
        return 1
    fi
    print_message success "Antigravity CLI installed."
    record_install "tool:antigravity" "tool" "antigravity installer" "$(command -v agy 2>/dev/null || true)"
    command_exists agy && print_message info "Version: $(agy --version 2>/dev/null || echo 'restart terminal to verify')"
}

install_copilot() {
    print_message header "Installing GitHub Copilot CLI"
    if command_exists copilot; then
        print_message success "GitHub Copilot CLI already installed."
        print_message info "Version: $(copilot --version 2>/dev/null || echo 'restart terminal to verify')"
        record_install "tool:copilot" "tool" "existing copilot command" "$(command -v copilot)"
        return
    fi
    if command_exists curl; then
        require_installer_url "GitHub Copilot CLI" "https://gh.io/copilot-install" || return 1
        curl -fsSL https://gh.io/copilot-install | bash
    elif command_exists npm; then
        print_message warning "Requires Node.js 22 or later."
        ensure_node || return 1
        require_installer_npm "GitHub Copilot CLI" "@github/copilot" || return 1
        npm install -g @github/copilot
    else
        print_message error "Neither curl nor npm found. Install manually."
        return 1
    fi
    print_message success "GitHub Copilot CLI installed."
    record_install "tool:copilot" "tool" "copilot installer" "$(command -v copilot 2>/dev/null || true)"
    command_exists copilot && print_message info "Version: $(copilot --version 2>/dev/null || echo 'restart terminal to verify')"
}

main() {
    while true; do
        menu_select "Install AI Coding CLI Tools" \
            "Install nvm (Node Version Manager)" \
            "Replace Node.js/nvm" \
            "Install Claude Code" \
            "Install Codex (OpenAI)" \
            "Install Antigravity CLI (Google)" \
            "Install GitHub Copilot CLI" \
            "Install all" \
            "Verify installers (no install)" \
            "Remove ALL agents + wipe all config (DESTRUCTIVE)" \
            "Back"
        case "$MENU_CHOICE" in
            1) run_install install_nvm ;;
            2)
                if confirm "Remove existing Node.js/nvm, then reinstall nvm?"; then
                    run_install replace_node
                fi
                ;;
            3) run_install install_claude_code ;;
            4) run_install install_codex ;;
            5) run_install install_antigravity ;;
            6) run_install install_copilot ;;
            7)
                run_install install_nvm
                print_message warning "Node tools below require a new terminal after nvm. Run 'nvm install --lts' first."
                run_install install_claude_code
                run_install install_codex
                run_install install_antigravity
                run_install install_copilot
                ;;
            8) run_install verify_installers ;;
            9)
                print_message warning "DESTRUCTIVE: this NUKES everything below. No undo. No backup."
                print_message warning "  - Claude, Codex, Antigravity, Copilot CLI binaries + npm packages"
                print_message warning "  - ALL of ~/.claude: agents, skills, settings, chat history, projects, saved memory"
                print_message warning "  - ~/.claude.json: global config and all configured servers"
                print_message warning "  - ~/.gemini/antigravity-cli: Antigravity install and statusline"
                print_message warning "  - vibespec rule files in ~/.codex, ~/.gemini, ~/.copilot"
                print_message warning "  - all installed statuslines and their config entries"
                print_message warning "  - vibespec install state in ~/.config/vibespec"
                print_message warning "Everything above will be GONE and cannot be recovered."
                if confirm_word CONFIRM "Type CONFIRM (uppercase) to nuke everything"; then
                    run_install uninstall_all_coding_cli_tools
                else
                    print_message info "Cancelled. Nothing was removed."
                fi
                ;;
            10) return ;;
        esac
    done
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main
fi
