#!/usr/bin/env bash
# vibespec shared utility functions

# Set by menu_select; read by callers after return
# shellcheck disable=SC2034
MENU_CHOICE=""

# Colors
if [[ "$(tput colors 2>/dev/null || echo 0)" -ge 256 ]]; then
    RED='\033[38;5;203m'
    GREEN='\033[38;5;76m'
    YELLOW='\033[38;5;220m'
    BLUE='\033[38;5;75m'
    CYAN='\033[38;5;87m'
    G_BLUE='\033[1;38;5;75m'
    G_RED='\033[1;38;5;203m'
    G_YELLOW='\033[1;38;5;220m'
    G_GREEN='\033[1;38;5;120m'
else
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[0;34m'
    CYAN='\033[0;36m'
    G_BLUE='\033[1;34m'
    G_RED='\033[1;31m'
    G_YELLOW='\033[1;33m'
    G_GREEN='\033[1;32m'
fi
BOLD='\033[1m'
NC='\033[0m'

print_message() {
    local type="$1" msg="$2"
    case "$type" in
        info)    echo -e "${CYAN}[INFO]${NC} ${msg}" ;;
        success) echo -e "${GREEN}[OK]${NC} ${msg}" ;;
        warning) echo -e "${YELLOW}[WARN]${NC} ${msg}" ;;
        error)   echo -e "${RED}[ERROR]${NC} ${msg}" >&2 ;;
        header)  echo -e "\n${BOLD}${BLUE}==> ${msg}${NC}" ;;
    esac
}

command_exists() {
    command -v "$1" &>/dev/null
}

slugify() {
    printf '%s' "$1" \
        | tr '[:upper:]' '[:lower:]' \
        | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//'
}

vibespec_state_file() {
    local state_dir="${VIBESPEC_STATE_DIR:-$HOME/.config/vibespec}"
    printf '%s/installs.json\n' "$state_dir"
}

record_install() {
    local id="$1"
    local type="$2"
    local source="$3"
    shift 3

    if ! command_exists python3; then
        print_message warning "python3 not found; install state was not recorded."
        return 0
    fi

    local state_file
    state_file="$(vibespec_state_file)"
    mkdir -p "$(dirname "$state_file")"

    INSTALL_ID="$id" INSTALL_TYPE="$type" INSTALL_SOURCE="$source" \
    INSTALL_FILES="$(printf '%s\n' "$@")" python3 - "$state_file" <<'PY'
import json
import os
import sys
from datetime import datetime, timezone
from pathlib import Path

state_path = Path(sys.argv[1])
try:
    data = json.loads(state_path.read_text(encoding="utf-8"))
except (FileNotFoundError, json.JSONDecodeError):
    data = {"installs": {}}

if not isinstance(data, dict):
    data = {"installs": {}}
installs = data.setdefault("installs", {})
if not isinstance(installs, dict):
    data["installs"] = installs = {}

install_id = os.environ["INSTALL_ID"]
files = [line for line in os.environ.get("INSTALL_FILES", "").splitlines() if line]
previous = installs.get(install_id, {})
installed_at = previous.get("installed_at") or datetime.now(timezone.utc).isoformat()

installs[install_id] = {
    "type": os.environ["INSTALL_TYPE"],
    "source": os.environ["INSTALL_SOURCE"],
    "installed_at": installed_at,
    "updated_at": datetime.now(timezone.utc).isoformat(),
    "files": files,
}

state_path.write_text(json.dumps(data, indent=2, sort_keys=True) + "\n", encoding="utf-8")
PY
}

confirm() {
    local prompt="${1:-Are you sure?}"
    local reply
    printf '%b%s [y/N]: %b' "${YELLOW}" "${prompt}" "${NC}" 2>/dev/null > /dev/tty || true
    read -r reply 2>/dev/null < /dev/tty || reply=""
    [[ "${reply,,}" == "y" ]]
}

# Stronger confirmation for irreversible actions: require an exact, case-sensitive
# word (default CONFIRM). Fails closed on empty input or missing tty.
confirm_word() {
    local word="${1:-CONFIRM}"
    local prompt="${2:-Type ${word} to proceed}"
    local reply
    printf '%b%s: %b' "${G_RED}" "${prompt}" "${NC}" 2>/dev/null > /dev/tty || true
    read -r reply 2>/dev/null < /dev/tty || reply=""
    [[ "${reply}" == "${word}" ]]
}

# Delete a path, but only when it lives under $HOME. Refuses to touch anything
# outside the home directory and aborts if $HOME is unset or root.
remove_path_under_home() {
    local target="$1"
    if [[ -z "${HOME:-}" || "$HOME" == "/" ]]; then
        print_message error "HOME is not safely set; refusing to remove ${target}"
        return 1
    fi
    case "$target" in
        "$HOME"/*)
            if [[ -e "$target" || -L "$target" ]]; then
                rm -rf "$target"
                print_message success "Removed ${target}"
            fi
            ;;
        *)
            print_message warning "Refusing to remove path outside home: ${target}"
            ;;
    esac
}

pause() {
    printf '%bPress Enter to continue...%b' "${CYAN}" "${NC}" 2>/dev/null > /dev/tty || true
    read -r _ 2>/dev/null < /dev/tty || true
}

# Run an install function, warn on failure, then pause.
# Usage: run_install <fn> [args...]
run_install() {
    local fn="$1"; shift
    if ! "$fn" "$@"; then
        print_message warning "${fn//_/ } failed — see errors above."
    fi
    pause
}

_vibespec_ascii() {
    echo -e ""
    echo -e " ${G_BLUE}██╗   ██╗${G_RED}██╗${G_YELLOW}██████╗ ${G_GREEN}███████╗${G_BLUE}███████╗${G_RED}██████╗ ${G_YELLOW}███████╗${G_GREEN} ██████╗${NC}"
    echo -e " ${G_BLUE}██║   ██║${G_RED}██║${G_YELLOW}██╔══██╗${G_GREEN}██╔════╝${G_BLUE}██╔════╝${G_RED}██╔══██╗${G_YELLOW}██╔════╝${G_GREEN}██╔════╝${NC}"
    echo -e " ${G_BLUE}██║   ██║${G_RED}██║${G_YELLOW}██████╔╝${G_GREEN}█████╗  ${G_BLUE}███████╗${G_RED}██████╔╝${G_YELLOW}█████╗  ${G_GREEN}██║     ${NC}"
    echo -e " ${G_BLUE}╚██╗ ██╔╝${G_RED}██║${G_YELLOW}██╔══██╗${G_GREEN}██╔══╝  ${G_BLUE}╚════██║${G_RED}██╔═══╝ ${G_YELLOW}██╔══╝  ${G_GREEN}██║     ${NC}"
    echo -e " ${G_BLUE} ╚████╔╝ ${G_RED}██║${G_YELLOW}██████╔╝${G_GREEN}███████╗${G_BLUE}███████║${G_RED}██║     ${G_YELLOW}███████╗${G_GREEN}╚██████╗${NC}"
    echo -e " ${G_BLUE}  ╚═══╝  ${G_RED}╚═╝${G_YELLOW}╚═════╝ ${G_GREEN}╚══════╝${G_BLUE}╚══════╝${G_RED}╚═╝     ${G_YELLOW}╚══════╝${G_GREEN} ╚═════╝ ${NC}"
    echo -e ""
}

# Arrow-key interactive menu. Sets MENU_CHOICE to the selected 1-based number.
# Usage: menu_select "Title" "Item1" "Item2" ...
menu_select() {
    local title="$1"; shift
    local options=("$@")
    local selected=0
    local options_count="${#options[@]}"
    local tty="/dev/tty"
    local key sequence idx

    if [[ ${options_count} -eq 0 ]]; then
        print_message error "No menu options supplied."
        return 1
    fi

    # Non-interactive fallback (no TTY)
    if ! { true < "${tty}"; } 2>/dev/null || ! { true > "${tty}"; } 2>/dev/null; then
        {
            _vibespec_ascii
            echo -e "  ${BOLD}${BLUE}${title}${NC}"
            echo
            for idx in "${!options[@]}"; do
                printf "  %2d) %s\n" "$((idx + 1))" "${options[$idx]}"
            done
            echo
            printf "  Select [1-%d]: " "${options_count}"
        } >&2
        local choice
        read -r choice
        MENU_CHOICE="${choice}"
        return 0
    fi

    _draw_items() {
        for idx in "${!options[@]}"; do
            printf "\033[2K" > "${tty}"
            if [[ "${idx}" -eq "${selected}" ]]; then
                printf "  ${BOLD}${GREEN}>  %2d)${NC} ${BOLD}%s${NC}\n" \
                    "$((idx + 1))" "${options[$idx]}" > "${tty}"
            else
                printf "     %2d)  %s\n" "$((idx + 1))" "${options[$idx]}" > "${tty}"
            fi
        done
    }

    {
        clear
        _vibespec_ascii
        echo -e "  ${BOLD}${BLUE}${title}${NC}"
        echo -e "  ${BLUE}$(printf '─%.0s' $(seq 1 50))${NC}"
        echo -e "  ${CYAN}↑↓ or j/k to navigate  ·  Enter to select  ·  q to quit${NC}"
        echo
    } > "${tty}"
    _draw_items

    while true; do
        IFS= read -rsn1 key < "${tty}" || return 1
        case "${key}" in
            $'\x1b')
                IFS= read -rsn2 -t 0.1 sequence < "${tty}" || sequence=""
                case "${sequence}" in
                    "[A") (( selected-- )) || true ;;
                    "[B") (( selected++ )) || true ;;
                esac
                ;;
            j|J) (( selected++ )) || true ;;
            k|K) (( selected-- )) || true ;;
            "")
                MENU_CHOICE="$((selected + 1))"
                return 0
                ;;
            q|Q)
                # shellcheck disable=SC2034
                MENU_CHOICE="${options_count}"
                return 0
                ;;
        esac

        [[ "${selected}" -lt 0 ]] && selected=$(( options_count - 1 ))
        [[ "${selected}" -ge "${options_count}" ]] && selected=0

        printf "\033[%dA" "${options_count}" > "${tty}"
        _draw_items
    done
}
