#!/bin/bash

# =====================================================================
# Author: DragoLuke
# StormScales — Emergency Alert System Suite Launcher
# Description: Front-end menu for launching StormScales scripts
# Scripts - eas_monitor.sh EAS eas_generator.py noaa_nwr_live_listen.sh
# License: GNU General Public License v3.0 (GPL-3.0-or-later)
# =====================================================================

# Restrict all spawned processes to owner-only access
umask 077

PROJECT_DIR="$HOME/StormScales"
SCRIPTS_DIR="$PROJECT_DIR/scripts"

# Script paths
MONITOR_SCRIPT="$SCRIPTS_DIR/eas_monitor.sh"
GENERATOR_SCRIPT="$SCRIPTS_DIR/eas_generator.py"
LISTEN_SCRIPT="$SCRIPTS_DIR/noaa_nwr_live_listen.sh"

# Terminal Colours
RED='\033[1;31m'
YELLOW='\033[1;33m'
GREEN='\033[1;32m'
CYAN='\033[1;36m'
PURPLE='\033[1;35m'
DIM='\033[2m'
RESET='\033[0m'

# =====================================================================
# ASCII ART — STORMSCALES
# =====================================================================
show_banner() {
    clear
    echo -e "${CYAN}"
    cat << 'ART'
  █████████   █████                                        █████████                     ████
 ███░░░░░███ ░░███                                        ███░░░░░███                   ░░███
░███    ░░░  ███████    ██████  ████████  █████████████  ░███    ░░░   ██████   ██████   ░███   ██████   █████
░░█████████ ░░░███░    ███░░███░░███░░███░░███░░███░░███ ░░█████████  ███░░███ ░░░░░███  ░███  ███░░███ ███░░
 ░░░░░░░░███  ░███    ░███ ░███ ░███ ░░░  ░███ ░███ ░███  ░░░░░░░░███░███ ░░░   ███████  ░███ ░███████ ░░█████
 ███    ░███  ░███ ███░███ ░███ ░███      ░███ ░███ ░███  ███    ░███░███  ███ ███░░███  ░███ ░███░░░   ░░░░███
░░█████████   ░░█████ ░░██████  █████     █████░███ █████░░█████████ ░░██████ ░░████████ █████░░██████  ██████
 ░░░░░░░░░     ░░░░░   ░░░░░░  ░░░░░     ░░░░░ ░░░ ░░░░░  ░░░░░░░░░   ░░░░░░   ░░░░░░░░ ░░░░░  ░░░░░░  ░░░░░░
ART
    echo -e "${RESET}"
    echo -e "  ${DIM}StormScales — Emergency Alert System Suite${RESET}"
    echo -e "  ${DIM}Author: DragoLuke  | Version: 1.0  |  License: GPL-3.0${RESET}"
    echo ""
}

# =====================================================================
# PRINT HELPERS
# =====================================================================
print_block_top() {
    echo -e "${CYAN}┌──────────────────────────────────────────────────────────────────┐${RESET}"
}

print_block_mid() {
    echo -e "${CYAN}├──────────────────────────────────────────────────────────────────┤${RESET}"
}

print_block_bot() {
    echo -e "${CYAN}└──────────────────────────────────────────────────────────────────┘${RESET}"
}

print_block_row() {
    local label="$1"
    local value="$2"
    printf "${CYAN}│${RESET} ${CYAN}%-14s${RESET} %s\n" "$label" "$value"
}

# =====================================================================
# INPUT VALIDATION
# =====================================================================
validate_numeric_input() {
    local input="$1"
    [[ "$input" =~ ^[0-9]+$ ]] && return 0 || return 1
}

# Prompts, reads, and validates numeric input within a range
# Args: prompt, min, max, max_attempts
# Note: prompts/errors go to stderr, only valid return value goes to stdout
get_validated_input() {
    local prompt="$1"
    local min="$2"
    local max="$3"
    local max_attempts="${4:-10}"

    local input=""
    local attempts=0

    while [ $attempts -lt $max_attempts ]; do
        echo -ne "  ${CYAN}${prompt}${RESET}" >&2
        read -r input

        # Sanitize: strip leading/trailing whitespace
        input="${input#"${input%%[![:space:]]*}"}"
        input="${input%"${input##*[![:space:]]}"}"

        # Reject input longer than 10 characters
        if [ ${#input} -gt 10 ]; then
            echo -e "${RED}[ERROR] Input too long (max 10 characters)${RESET}" >&2
            echo "" >&2
            ((attempts++))
            continue
        fi

        if [ -z "$input" ]; then
            echo -e "${RED}[ERROR] Input cannot be empty.${RESET}" >&2
            echo -e "${DIM}Valid range: $min to $max${RESET}" >&2
            echo "" >&2
            ((attempts++))
            continue
        fi

        if ! validate_numeric_input "$input"; then
            echo -e "${RED}[ERROR] Invalid selection: '$input' is not a number${RESET}" >&2
            echo -e "${DIM}Valid range: $min to $max${RESET}" >&2
            echo "" >&2
            ((attempts++))
            continue
        fi

        if [ "$input" -ge "$min" ] && [ "$input" -le "$max" ]; then
            echo "$input"
            return 0
        else
            echo -e "${RED}[ERROR] Invalid selection: '$input'${RESET}" >&2
            echo -e "${DIM}Valid range: $min to $max${RESET}" >&2
            echo "" >&2
            ((attempts++))
        fi
    done

    echo -e "${RED}[ERROR] Too many invalid attempts. Returning to menu.${RESET}" >&2
    return 1
}

# Validates Y/N input with retries and clear error messaging
# Args: prompt text, default value (y or n), max_attempts
# Note: prompts/errors go to stderr, only valid return value goes to stdout
get_validated_yes_no() {
    local prompt="$1"
    local default="${2:-n}"
    local max_attempts=5

    local input=""
    local attempts=0

    while [ $attempts -lt $max_attempts ]; do
        echo -ne "  ${CYAN}${prompt}${RESET}" >&2
        read -r input

        # Sanitize: trim whitespace, lowercase, cap length
        input="${input#"${input%%[![:space:]]*}"}"
        input="${input%"${input##*[![:space:]]}"}"
        input="${input,,}"
        input="${input:0:5}"

        if [ -z "$input" ]; then
            if [ "$default" = "y" ]; then
                echo "y"
                return 0
            else
                echo -e "${RED}[ERROR] Input cannot be empty.${RESET}" >&2
                echo -e "${DIM}Valid options: Y or N (default: N)${RESET}" >&2
                echo "" >&2
                ((attempts++))
                continue
            fi
        fi

        case "$input" in
            y|yes)
                echo "y"
                return 0
                ;;
            n|no)
                echo "n"
                return 0
                ;;
            *)
                echo -e "${RED}[ERROR] Invalid selection: '$input'${RESET}" >&2
                echo -e "${DIM}Valid options: Y or N (default: N)${RESET}" >&2
                echo "" >&2
                ((attempts++))
                ;;
        esac
    done

    echo -e "${RED}[ERROR] Too many invalid attempts. Defaulting to NO.${RESET}" >&2
    echo "n"
    return 1
}

# =====================================================================
# SCRIPT EXISTENCE CHECK
# =====================================================================
check_scripts() {
    local all_present=true

    if [ ! -f "$MONITOR_SCRIPT" ]; then
        echo -e "  ${RED}[MISSING]${RESET} eas_monitor.sh  ($MONITOR_SCRIPT)"
        all_present=false
    fi
    if [ ! -f "$GENERATOR_SCRIPT" ]; then
        echo -e "  ${RED}[MISSING]${RESET} eas_generator.py  ($GENERATOR_SCRIPT)"
        all_present=false
    fi
    if [ ! -f "$LISTEN_SCRIPT" ]; then
        echo -e "  ${RED}[MISSING]${RESET} noaa_nwr_live_listen.sh  ($LISTEN_SCRIPT)"
        all_present=false
    fi

    if ! $all_present; then
        echo ""
        echo -e "  ${YELLOW}[!] One or more scripts not found in: $SCRIPTS_DIR${RESET}"
        echo -e "  ${DIM}Ensure all scripts are in the StormScales directory.${RESET}"
        echo ""
        exit 1
    fi
}

# =====================================================================
# DEPENDENCY QUICK-CHECK
# =====================================================================
quick_dep_check() {
    local all_ok=true

    command -v bash &> /dev/null || all_ok=false
    command -v python3 &> /dev/null || { echo -e "  ${RED}[MISSING]${RESET} python3"; all_ok=false; }

    if ! $all_ok; then
        echo -e "\n  ${RED}[!] Missing core dependencies${RESET}"
        exit 1
    fi

    # Optional tools summary
    local tools_found=""
    command -v rtl_fm &> /dev/null && tools_found+="rtl_fm "
    command -v multimon-ng &> /dev/null && tools_found+="multimon-ng "
    command -v sox &> /dev/null && tools_found+="sox "
    command -v lsusb &> /dev/null && tools_found+="lsusb "

    if [ -n "$tools_found" ]; then
        echo -e "  ${GREEN}[+]${RESET} Detected: $tools_found"
    else
        echo -e "  ${YELLOW}[!]${RESET} No SDR tools detected — install rtl-sdr, multimon-ng, sox"
    fi
    echo ""
}

# =====================================================================
# SUB-MENU: SCRIPT-SPECIFIC INFO
# =====================================================================
show_script_info() {
    local choice="$1"

    case "$choice" in
        1)
            print_block_top
            print_block_row "FILE" "eas_monitor.sh"
            print_block_mid
            print_block_row "FUNCTION" "Continuously monitors NOAA NWR"
            print_block_row "REQUIRES" "rtl_fm, multimon-ng, sox, lsusb"
            print_block_bot
            ;;
        2)
            print_block_top
            print_block_row "FILE" "eas_generator.py"
            print_block_mid
            print_block_row "FUNCTION" "Generates SAME/EAS alerts"
            print_block_row "REQUIRES" "python3, numpy, multimon-ng"
            print_block_bot
            ;;
        3)
            print_block_top
            print_block_row "FILE" "noaa_nwr_live_listen.sh"
            print_block_mid
            print_block_row "FUNCTION" "Tune to live weather radio"
            print_block_row "REQUIRES" "rtl_fm, paplay/pw-play/aplay"
            print_block_bot
            ;;
    esac
}

# =====================================================================
# LAUNCH SCRIPT
# =====================================================================
launch_script() {
    local choice="$1"

    case "$choice" in
        1)
            echo -e "\n${GREEN}[+] Launching EAS Monitor...${RESET}\n"
            sleep 1
            bash "$MONITOR_SCRIPT"
            ;;
        2)
            echo -e "\n${GREEN}[+] Launching EAS Generator...${RESET}\n"
            sleep 1
            python3 "$GENERATOR_SCRIPT"
            ;;
        3)
            echo -e "\n${GREEN}[+] Launching NWR Live Listen...${RESET}\n"
            sleep 1
            bash "$LISTEN_SCRIPT"
            ;;
    esac
}

# =====================================================================
# MAIN MENU
# =====================================================================
main() {
    show_banner
    check_scripts

    quick_dep_check

    # Main menu loop
    while true; do
        echo -e "${CYAN}┌───────────────────────────── MENU ─────────────────────────────┐${RESET}"
        echo -e "${CYAN}│${RESET}"
        echo -e "${CYAN}│${RESET}  ${GREEN}[1]${RESET}  SAME/EAS Monitor        ${DIM}— SAME/EAS Monitoring${RESET}"
        echo -e "${CYAN}│${RESET}  ${GREEN}[2]${RESET}  SAME/EAS Generator      ${DIM}— SAME/EAS Creation${RESET}"
        echo -e "${CYAN}│${RESET}  ${GREEN}[3]${RESET}  NWR Live Listen         ${DIM}— Tune to live weather radio${RESET}"
        echo -e "${CYAN}│${RESET}  ${GREEN}[4]${RESET}  Exit                    ${DIM}— Quit StormScales${RESET}"
        echo -e "${CYAN}│${RESET}"
        echo -e "${CYAN}└────────────────────────────────────────────────────────────────┘${RESET}"
        echo ""

        user_choice=$(get_validated_input "Select option [1-4]: " 1 4 10)

        if [ $? -ne 0 ]; then
            sleep 1
            continue
        fi

        case "$user_choice" in
            [1-3])
                echo ""
                show_script_info "$user_choice"
                echo ""

                confirm=$(get_validated_yes_no "Launch this script? [Y/n]: " "y")

                if [ "$confirm" = "y" ]; then
                    launch_script "$user_choice"

                    echo ""
                    echo -e "${DIM}────────────────────────────────────────────────────────────────────${RESET}"
                    echo -e "${CYAN}Script exited.${RESET}"
                    echo -e "${DIM}────────────────────────────────────────────────────────────────────${RESET}"
                    echo ""

                    return_choice=$(get_validated_yes_no "Return to StormScales menu? [Y/n]: " "y")

                    if [ "$return_choice" = "n" ]; then
                        echo -e "\n${DIM}Goodbye! Stay safe out there. ${PURPLE}${RESET}\n"
                        exit 0
                    else
                        show_banner
                        echo ""
                    fi
                else
                    echo -e "  ${DIM}Cancelled. Returning to menu...${RESET}"
                    sleep 1
                    show_banner
                    echo ""
                fi
                ;;
            4)
                echo ""
                echo -e "${DIM}Goodbye! Stay safe out there. ${PURPLE}${RESET}"
                echo ""
                exit 0
                ;;
        esac
    done
}

main
