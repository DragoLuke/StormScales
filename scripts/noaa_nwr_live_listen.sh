#!/bin/bash

# =====================================================================
# Author: DragoLuke
# NOAA NWR Live Listen Scanner
# License: GNU General Public License v3.0 (GPL-3.0-or-later)
# Description: Browse NOAA transmitters by state/county like EAS monitor
#              Quick live listener with zero temp files or directories
# =====================================================================

# =====================================================================
# FEATURE LIST
# =====================================================================
# Core Listening:
#   - Live FM-demodulated audio from any NOAA NWR transmitter
#   - De-emphasis filter for natural weather radio audio
#   - Lean pipeline: rtl_fm -> audio player
#
# Hardware Integration:
#   - RTL-SDR (V3) support via rtl_fm
#   - Auto-detect RTL-SDR devices via lsusb
#   - RTL-SDR Disconnection Detection — Script exits gracefully on
#     device removal using /dev/shm (no temp files in project dir)
#   - Startup error diagnostics with hardware error log
#
# User Experience:
#   - Interactive state -> transmitter selection wizard
#   - Two-letter state abbreviation support (e.g., MT, CA, TX)
#   - Input validation: rejects non-numeric and out-of-range entries
#   - Themed terminal output with colored status blocks
#   - Automatic audio player detection (paplay, pw-play, aplay)
#
# Security:
#   - umask 077 enforced for all spawned processes
#   - Input sanitization: whitespace trim, length cap, case normalize
#   - Clean process termination on exit (rtl_fm + audio player)
#
# Dependencies (Minimal):
#   - rtl-sdr (rtl_fm) — core RF capture
#   - paplay, pw-play, OR aplay — audio output
#   - lsusb — hardware detection
# =====================================================================

PROJECT_DIR="$HOME/StormScales"
STATE_DATA_DIR="$PROJECT_DIR/media/state_data"

# Restrict all created files/processes to owner-only access
umask 077

RTL_DEVICE_INDEX="0"
RTL_SDR_INDEX="0"
RTL_DEVICE_LINE=""
USB_HID=""
USB_DESCRIPTION=""
VERBOSE_MODE=true
AUDIO_PLAYER=""
FREQUENCY=""
declare -A STATE_COUNTIES
declare -A TRANSMITTERS

# Minimal temp usage in shared memory (RAM-backed, auto-cleaned on reboot)
SHM_TEMP="/dev/shm/nwr_listen_$$"
mkdir -p "$SHM_TEMP" 2>/dev/null
RTL_ERR_LOG="$SHM_TEMP/rtl_err.log"
DEVICE_DISCONN_FLAG="$SHM_TEMP/device_disconnected"
echo "0" > "$DEVICE_DISCONN_FLAG"
DEVICE_MON_PID=""
STREAM_PID=""

# Terminal Colours
RED='\033[1;31m'
YELLOW='\033[1;33m'
GREEN='\033[1;32m'
CYAN='\033[1;36m'
DIM='\033[2m'
RESET='\033[0m'

print_header() {
    echo -e "\n────────────────────────────────────────────────────────────────────"
    echo -e " ${CYAN}» $1${RESET}"
    echo -e "────────────────────────────────────────────────────────────────────"
}

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

info_log() {
    if $VERBOSE_MODE; then
        echo -e " ${DIM}[INFO] $1${RESET}"
    fi
}

# =====================================================================
# INPUT VALIDATION FUNCTIONS
# =====================================================================
validate_numeric_input() {
    local input="$1"
    [[ "$input" =~ ^[0-9]+$ ]] && return 0 || return 1
}

get_validated_selection() {
    local prompt="$1"
    local default="$2"
    local min="$3"
    local selection_max="$4"
    local allow_default="$5"

    local validated_input=""
    local attempts=0
    local max_attempts=10

    while [ $attempts -lt $max_attempts ]; do
        echo -ne "  ${CYAN}${prompt}${RESET}" >&2
        read -r validated_input

        # Sanitize: strip leading/trailing whitespace
        validated_input="${validated_input#"${validated_input%%[![:space:]]*}"}"
        validated_input="${validated_input%"${validated_input##*[![:space:]]}"}"

        # Reject input longer than 10 characters
        if [ ${#validated_input} -gt 10 ]; then
            echo -e "${RED}[ERROR] Input too long (max 10 characters)${RESET}" >&2
            echo "" >&2
            ((attempts++))
            continue
        fi

        if [ -z "$validated_input" ]; then
            if [ "$allow_default" = "true" ]; then
                echo "$default"
                return 0
            else
                echo -e "${RED}[ERROR] Input cannot be empty.${RESET}" >&2
                echo -e "${DIM}Valid range: $min to $selection_max${RESET}" >&2
                echo "" >&2
                ((attempts++))
                continue
            fi
        fi

        if ! validate_numeric_input "$validated_input"; then
            echo -e "${RED}[ERROR] Invalid selection: '$validated_input' is not a number${RESET}" >&2
            echo -e "${DIM}Valid range: $min to $selection_max${RESET}" >&2
            echo "" >&2
            ((attempts++))
            continue
        fi

        if [ "$validated_input" -ge "$min" ] && [ "$validated_input" -le "$selection_max" ]; then
            echo "$validated_input"
            return 0
        else
            echo -e "${RED}[ERROR] Invalid selection: '$validated_input'${RESET}" >&2
            echo -e "${DIM}Valid range: $min to $selection_max${RESET}" >&2
            echo "" >&2
            ((attempts++))
        fi
    done

    echo -e "${RED}[ERROR] Too many invalid attempts. Exiting setup.${RESET}" >&2
    exit 1
}

# =====================================================================
# STATE NAME TO ABBREVIATION MAPPING
# =====================================================================
declare -A STATE_NAME_TO_ABBR
STATE_NAME_TO_ABBR=(
    ["ALABAMA"]="AL" ["ALASKA"]="AK" ["ARIZONA"]="AZ" ["ARKANSAS"]="AR"
    ["CALIFORNIA"]="CA" ["COLORADO"]="CO" ["CONNECTICUT"]="CT" ["DELAWARE"]="DE"
    ["DISTRICT OF COLUMBIA"]="DC" ["FLORIDA"]="FL" ["GEORGIA"]="GA" ["HAWAII"]="HI"
    ["IDAHO"]="ID" ["ILLINOIS"]="IL" ["INDIANA"]="IN" ["IOWA"]="IA"
    ["KANSAS"]="KS" ["KENTUCKY"]="KY" ["LOUISIANA"]="LA" ["MAINE"]="ME"
    ["MARYLAND"]="MD" ["MASSACHUSETTS"]="MA" ["MICHIGAN"]="MI" ["MINNESOTA"]="MN"
    ["MISSISSIPPI"]="MS" ["MISSOURI"]="MO" ["MONTANA"]="MT" ["NEBRASKA"]="NE"
    ["NEVADA"]="NV" ["NEW HAMPSHIRE"]="NH" ["NEW JERSEY"]="NJ" ["NEW MEXICO"]="NM"
    ["NEW YORK"]="NY" ["NORTH CAROLINA"]="NC" ["NORTH DAKOTA"]="ND" ["OHIO"]="OH"
    ["OKLAHOMA"]="OK" ["OREGON"]="OR" ["PENNSYLVANIA"]="PA" ["RHODE ISLAND"]="RI"
    ["SOUTH CAROLINA"]="SC" ["SOUTH DAKOTA"]="SD" ["TENNESSEE"]="TN" ["TEXAS"]="TX"
    ["UTAH"]="UT" ["VERMONT"]="VT" ["VIRGINIA"]="VA" ["WASHINGTON"]="WA"
    ["WEST VIRGINIA"]="WV" ["WISCONSIN"]="WI" ["WYOMING"]="WY"
)

get_state_abbreviation() {
    local state_name="$1"
    local upper_name=$(echo "$state_name" | tr '[:lower:]' '[:upper:]')
    if [ -n "${STATE_NAME_TO_ABBR[$upper_name]:-}" ]; then
        echo "${STATE_NAME_TO_ABBR[$upper_name]}"
    else
        echo "${upper_name:0:2}"
    fi
}

# =====================================================================
# CLEANUP HANDLER
# =====================================================================
CLEANUP_DONE=false

cleanup() {
    $CLEANUP_DONE && return
    CLEANUP_DONE=true

    # Stop device monitor if running
    [[ -n "$DEVICE_MON_PID" ]] && kill "$DEVICE_MON_PID" 2>/dev/null

    # Kill RTL-SDR hardware process
    pkill -f "rtl_fm.*$FREQUENCY" 2>/dev/null
    pkill -f rtl_fm 2>/dev/null

    # Kill audio player process (prevents orphaned listeners)
    case "$AUDIO_PLAYER" in
        paplay)  pkill -f paplay 2>/dev/null ;;
        pw-play) pkill -f pw-play 2>/dev/null ;;
        aplay)   pkill -f aplay 2>/dev/null ;;
    esac

    # Clean up shared memory temp files
    rm -rf "$SHM_TEMP" 2>/dev/null

    # Check if disconnection triggered the exit
    if [ -f "$DEVICE_DISCONN_FLAG" ] && [ "$(cat "$DEVICE_DISCONN_FLAG" 2>/dev/null)" = "1" ]; then
        echo -e "\n${RED}[!] RTL-SDR disconnection detected — audio stream terminated${RESET}"
    else
        echo -e "\n${YELLOW}[!] Exiting — stopping audio stream...${RESET}"
    fi

    exit 0
}

trap cleanup SIGINT SIGTERM EXIT

# =====================================================================
# VERBOSE MODE PROMPT
# =====================================================================
while true; do
    echo -e "${CYAN}Do you want to display detailed [INFO] messages? [Y/n] ${RESET}"
    read -r VERBOSE_RESPONSE

    # Sanitize: trim whitespace, uppercase, cap length
    VERBOSE_RESPONSE="${VERBOSE_RESPONSE#"${VERBOSE_RESPONSE%%[![:space:]]*}"}"
    VERBOSE_RESPONSE="${VERBOSE_RESPONSE%"${VERBOSE_RESPONSE##*[![:space:]]}"}"
    VERBOSE_RESPONSE="${VERBOSE_RESPONSE:0:5}"
    VERBOSE_RESPONSE="${VERBOSE_RESPONSE^^}"

    case "$VERBOSE_RESPONSE" in
        [Yy]|[Yy][Ee][Ss]|"")
            VERBOSE_MODE=true
            break
            ;;
        [Nn]|[Nn][Oo])
            VERBOSE_MODE=false
            break
            ;;
        *)
            echo -e "${RED}[ERROR] Invalid input: '$VERBOSE_RESPONSE'${RESET}" >&2
            echo -e "${DIM}Please enter Y or N (default: Y)${RESET}" >&2
            echo "" >&2
            continue
            ;;
    esac
done

# =====================================================================
# RTL-SDR Detection & Selection Functions
# =====================================================================
detect_all_rtl_sdars() {
    local usb_output
    usb_output=$(lsusb 2>/dev/null)

    # grep -n provides the ACTUAL line number in the full lsusb output
    mapfile -t RTL_DEVICES < <(echo "$usb_output" | grep -niE "2838|RTL2832|RTL-SDR")

    if [ ${#RTL_DEVICES[@]} -eq 0 ]; then
        return 1
    fi

    return 0
}

select_rtl_sdr_device() {
    print_header "RTL-SDR DEVICE SELECTION"

    detect_all_rtl_sdars
    local rc=$?

    if [ $rc -ne 0 ]; then
        print_block_top
        print_block_row "STATUS" "NO RTL-SDR DETECTED"
        print_block_mid
        print_block_row "DETAIL" "No supported USB devices found"
        print_block_row "ACTION" "Plug in an RTL-SDR dongle and retry"
        print_block_bot
        exit 1
    fi

    local num_devices=${#RTL_DEVICES[@]}

    echo -e "  ${CYAN}Connected RTL-SDR Devices:${RESET}"
    echo ""

    for ((i=0; i<num_devices; i++)); do
        local device_line="${RTL_DEVICES[$i]}"
        local line_num="${device_line%%:*}"
        local usb_info="${device_line#*:}"

        local usb_id
        usb_id=$(echo "$usb_info" | grep -oP 'ID\s+\K[A-Fa-f0-9]{4}:[A-Fa-f0-9]{4}' || echo "N/A")
        local usb_desc
        usb_desc=$(echo "$usb_info" | sed 's/.*ID [0-9a-f]*:[0-9a-f]* //')

        printf "  ${CYAN}[%d]${RESET} %s\n" "$((i+1))" "$usb_desc"
        printf "       ${DIM}USB ID: %s${RESET}\n" "$usb_id"
        printf "       ${DIM}lsusb line: %d | rtl_fm -d index: %d${RESET}\n" "$line_num" "$i"
        echo ""
    done

    echo "────────────────────────────────────────────────────────────────────"
    echo -e "  ${DIM}If you only have one RTL-SDR, just press Enter to select it.${RESET}"
    echo ""

    local device_choice
    device_choice=$(get_validated_selection "Select Device Number [Default: 1]: " "1" "1" "$num_devices" "true")

    local selected_line_num
    selected_line_num=$(echo "${RTL_DEVICES[$((device_choice-1))]}" | cut -d':' -f1)

    # RTL_DEVICE_INDEX = lsusb line number (used for sed/grep lookups)
    RTL_DEVICE_INDEX="$selected_line_num"

    # RTL_SDR_INDEX = 0-based index among RTL-SDR devices (used for rtl_fm -d)
    RTL_SDR_INDEX=$((device_choice - 1))

    # Extract and validate USB device info
    target_device=$(lsusb 2>/dev/null | sed -n "${RTL_DEVICE_INDEX}p")

    if [ -z "$target_device" ]; then
        echo -e "${RED}[ERROR] Device at lsusb line $RTL_DEVICE_INDEX not found!${RESET}" >&2
        cleanup
    fi

    USB_HID=$(echo "$target_device" | grep -oP 'ID\s+\K[A-Fa-f0-9]{4}:[A-Fa-f0-9]{4}')
    USB_DESCRIPTION=$(echo "$target_device" | sed 's/.*ID [0-9a-f]*:[0-9a-f]* //')

    # Validate we actually got an RTL-SDR (should be 0bda:2838 or 0bda:2832)
    if [ -z "$USB_HID" ]; then
        echo -e "${RED}[ERROR] Could not extract USB HID from device!${RESET}" >&2
        cleanup
    fi

    if ! echo "$USB_HID" | grep -qE '^0bda:(2838|2832)$'; then
        echo -e "${RED}[ERROR] Selected device is NOT an RTL-SDR!${RESET}" >&2
        echo -e "${DIM}Expected: 0bda:2838 or 0bda:2832, Got: $USB_HID${RESET}" >&2
        echo -e "${DIM}Device: $target_device${RESET}" >&2
        cleanup
    fi

    # Save the FULL lsusb line for disconnection monitoring
    RTL_DEVICE_LINE="$target_device"

    info_log "Detected USB HID: $USB_HID"
    info_log "Device description: $USB_DESCRIPTION"
    echo -e "${GREEN}OK — rtl_fm -d index: $RTL_SDR_INDEX (lsusb line: $RTL_DEVICE_INDEX)${RESET}"

    return 0
}

# =====================================================================
# Dependency Check (only shown if VERBOSE_MODE is enabled)
# =====================================================================
if $VERBOSE_MODE; then
    print_header "DEPENDENCY CHECK"
fi

if ! command -v rtl_fm &> /dev/null; then
    print_block_top
    print_block_row "STATUS" "FAILED"
    print_block_mid
    print_block_row "MISSING" "rtl_fm (rtl-sdr-tools)"
    print_block_row "ACTION" "Install rtl-sdr package and retry"
    print_block_bot
    exit 1
fi

if ! command -v lsusb &> /dev/null; then
    print_block_top
    print_block_row "STATUS" "FAILED"
    print_block_mid
    print_block_row "MISSING" "lsusb (usbutils)"
    print_block_row "ACTION" "Install usbutils package and retry"
    print_block_bot
    exit 1
fi

# Check for audio output options
if command -v paplay &> /dev/null; then
    AUDIO_PLAYER="paplay"
elif command -v pw-play &> /dev/null; then
    AUDIO_PLAYER="pw-play"
elif command -v aplay &> /dev/null; then
    AUDIO_PLAYER="aplay"
else
    print_block_top
    print_block_row "STATUS" "FAILED"
    print_block_mid
    print_block_row "MISSING" "No audio player (paplay/pw-play/aplay)"
    print_block_row "ACTION" "Install pulseaudio, pipewire, or alsa-utils"
    print_block_bot
    exit 1
fi

# Only show PASSED summary if verbose mode is enabled
if $VERBOSE_MODE; then
    print_block_top
    print_block_row "STATUS" "PASSED"
    print_block_mid
    print_block_row "rtl_fm" "FOUND"
    print_block_row "lsusb" "FOUND"
    print_block_row "AUDIO PLAYER" "$AUDIO_PLAYER"
    print_block_bot

    select_rtl_sdr_device

    print_block_top
    print_block_row "STATUS" "All dependencies verified"
    print_block_row "AUDIO" "$AUDIO_PLAYER"
    print_block_row "SDR INDEX" "$RTL_SDR_INDEX (rtl_fm -d)"
    print_block_bot

    clear
else
    # Quiet mode - clear screen before device selection for clean look
    clear
    select_rtl_sdr_device
fi

# =====================================================================
# Load State Data Function
# =====================================================================
load_state_data() {
    local state_file="$1"

    if [ ! -f "$state_file" ]; then
        echo -e "${RED}[ERROR] State data file not found: $state_file${RESET}" >&2
        return 1
    fi

    STATE_COUNTIES=()
    TRANSMITTERS=()

    local in_counties=false
    local in_transmitters=false

    while IFS= read -r line; do
        if [[ "$line" == "# ===== COUNTY FIPS CODES =====" ]]; then
            in_counties=true
            in_transmitters=false
            continue
        elif [[ "$line" == "# ===== NOAA WEATHER RADIO TRANSMITTERS =====" ]]; then
            in_counties=false
            in_transmitters=true
            continue
        elif [[ "$line" == "======================================================================" ]]; then
            continue
        elif [[ "$line" == "# "* ]] || [[ "$line" == "-----"* ]] || [[ -z "$line" ]]; then
            continue
        fi

        if $in_counties; then
            if [[ "$line" =~ ^(.+)\|([0-9]{5})$ ]]; then
                local county_name="${BASH_REMATCH[1]}"
                local fips_code="${BASH_REMATCH[2]}"
                local county_key=$(echo "$county_name" | tr '[:lower:]' '[:upper:]' | tr ' ' '_')
                STATE_COUNTIES["$county_key"]="$fips_code"
            fi
        fi

        if $in_transmitters; then
            if [[ "$line" =~ ^([KW][A-Z0-9]+)\|(162\.[0-9]{3})\|(.+)$ ]]; then
                local callsign="${BASH_REMATCH[1]}"
                local frequency="${BASH_REMATCH[2]}"
                local location="${BASH_REMATCH[3]}"
                TRANSMITTERS["$callsign"]="${location} (${frequency} MHz)"
            fi
        fi
    done < "$state_file"

    if [ ${#STATE_COUNTIES[@]} -eq 0 ]; then
        echo -e "${RED}[ERROR] No county data found in: $state_file${RESET}" >&2
        return 1
    fi

    return 0
}

# =====================================================================
# State Selection
# =====================================================================
select_state() {
    clear
    print_header "LIVE LISTEN SETUP: SELECT STATE OR TERRITORY"

    if [ ! -d "$STATE_DATA_DIR" ]; then
        print_block_top
        print_block_row "STATUS" "ERROR"
        print_block_mid
        print_block_row "MESSAGE" "state_data directory not found"
        print_block_row "PATH" "$STATE_DATA_DIR"
        print_block_row "ACTION" "Run fips_data_gen first to generate state files"
        print_block_bot
        exit 1
    fi

    mapfile -t STATE_FILES < <(ls -1 "$STATE_DATA_DIR"/*.txt 2>/dev/null | grep -v "_manifest" | sort)

    if [ ${#STATE_FILES[@]} -eq 0 ]; then
        print_block_top
        print_block_row "STATUS" "ERROR"
        print_block_mid
        print_block_row "MESSAGE" "No state data files found"
        print_block_row "PATH" "$STATE_DATA_DIR"
        print_block_row "ACTION" "Run fips_data_gen first to generate state files"
        print_block_bot
        exit 1
    fi

    mapfile -t STATE_ENTRIES < <(for sf in "${STATE_FILES[@]}"; do
        dn=$(basename "$sf" .txt | tr '_' ' ' | tr '[:lower:]' '[:upper:]')
        echo "${dn}|${sf}"
    done | sort)

    local num_entries=${#STATE_ENTRIES[@]}

    # Build abbreviation lookup: ABBR -> array index (0-based)
    declare -A ABBR_TO_IDX
    for ((i=0; i<num_entries; i++)); do
        IFS='|' read -r state_name _ <<< "${STATE_ENTRIES[i]}"
        local abbr=$(get_state_abbreviation "$state_name")
        ABBR_TO_IDX["$abbr"]="$i"
    done

    echo -e "  ${CYAN}Available States/Territories:${RESET}"
    echo ""

    # Display 2-column layout with abbreviations
    for ((i=0; i<num_entries; i+=2)); do
        IFS='|' read -r name1 _ <<< "${STATE_ENTRIES[i]}"
        local abbr1=$(get_state_abbreviation "$name1")
        printf "  ${CYAN}%2d)${RESET} %-4s %-31s" "$((i+1))" "[${abbr1}]" "$name1"
        if [[ $((i+1)) -lt $num_entries ]]; then
            IFS='|' read -r name2 _ <<< "${STATE_ENTRIES[i+1]}"
            local abbr2=$(get_state_abbreviation "$name2")
            printf "  ${CYAN}%2d)${RESET} %-4s %-31s\n" "$((i+2))" "[${abbr2}]" "$name2"
        else
            echo ""
        fi
    done

    echo "────────────────────────────────────────────────────────────────────"
    echo -e "  ${CYAN}Default: Select First State${RESET}"
    echo -e "  ${DIM}Enter number or 2-letter abbreviation (e.g., MT, CA, TX)${RESET}"
    echo ""

    local state_idx=""
    local attempts=0
    local max_attempts=10

    while [ $attempts -lt $max_attempts ]; do
        echo -ne "  ${CYAN}Select State Number or Abbreviation [Default: 1]${RESET} " >&2
        read -r state_input

        # Sanitize: trim whitespace, uppercase, cap length
        state_input="${state_input#"${state_input%%[![:space:]]*}"}"
        state_input="${state_input%"${state_input##*[![:space:]]}"}"
        state_input="${state_input:0:10}"
        state_input="${state_input^^}"

        # Empty input — use default (first state)
        if [ -z "$state_input" ]; then
            IFS='|' read -r SELECTED_STATE_NAME SELECTED_STATE <<< "${STATE_ENTRIES[0]}"
            break
        fi

        # Try numeric first
        if validate_numeric_input "$state_input"; then
            if [ "$state_input" -ge 1 ] && [ "$state_input" -le "$num_entries" ]; then
                IFS='|' read -r SELECTED_STATE_NAME SELECTED_STATE <<< "${STATE_ENTRIES[$((state_input-1))]}"
                break
            else
                echo -e "${RED}[ERROR] Number '$state_input' out of range (1-$num_entries)${RESET}" >&2
            fi
            echo "" >&2
            ((attempts++))
            continue
        fi

        # Try abbreviation lookup
        if [ -n "${ABBR_TO_IDX[$state_input]:-}" ]; then
            local idx="${ABBR_TO_IDX[$state_input]}"
            IFS='|' read -r SELECTED_STATE_NAME SELECTED_STATE <<< "${STATE_ENTRIES[$idx]}"
            break
        else
            echo -e "${RED}[ERROR] Unknown abbreviation '$state_input'. Use number or 2-letter code (e.g., MT, CA, TX).${RESET}" >&2
            echo "" >&2
            ((attempts++))
            continue
        fi
    done

    if [ $attempts -ge $max_attempts ]; then
        echo -e "${RED}[ERROR] Too many invalid attempts. Exiting setup.${RESET}" >&2
        exit 1
    fi

    echo -e "\n${GREEN}Selected: $SELECTED_STATE_NAME${RESET}"
    echo -e "${DIM}File: $SELECTED_STATE${RESET}"
}

# =====================================================================
# Transmitter Selection
# =====================================================================
select_transmitter() {
    clear
    print_header "LIVE LISTEN SETUP: SELECT NOAA CALL SIGN"

    if [ ${#TRANSMITTERS[@]} -eq 0 ]; then
        print_block_top
        print_block_row "STATUS" "WARNING"
        print_block_mid
        print_block_row "MESSAGE" "No transmitter data available for this state"
        print_block_row "ACTION" "Check state_data/$(basename "$SELECTED_STATE").txt"
        print_block_bot
        echo ""
        echo -e "${YELLOW}Note: Some states (e.g., District of Columbia) have no NWR transmitters.${RESET}"
        sleep 2
        return 1
    fi

    local num_transmitters=${#TRANSMITTERS[@]}

    mapfile -t SORTED_CALLS < <(for i in "${!TRANSMITTERS[@]}"; do echo "$i"; done | sort)

    echo "  Available Transmitters for $SELECTED_STATE_NAME:"
    echo ""

    for i in "${!SORTED_CALLS[@]}"; do
        call="${SORTED_CALLS[i]}"
        printf "  ${CYAN}%2d)${RESET} %-8s — %s\n" "$((i+1))" "$call" "${TRANSMITTERS[$call]}"
    done

    echo ""
    echo "────────────────────────────────────────────────────────────────────"
    echo -e "  ${CYAN}Default: First Call Sign${RESET}"

    local call_idx
    call_idx=$(get_validated_selection "Select Call Sign Number [Default: 1]: " "1" "1" "$num_transmitters" "true")

    if [[ -z "$call_idx" ]]; then
        SELECTED_CALL="${SORTED_CALLS[0]}"
    else
        SELECTED_CALL="${SORTED_CALLS[$((call_idx-1))]}"
    fi

    echo -e "\n${GREEN}Selected: $SELECTED_CALL${RESET}"
    echo -e "${DIM}Info: ${TRANSMITTERS[$SELECTED_CALL]}${RESET}"
}

# =====================================================================
# Get Frequency from Callsign
# =====================================================================
get_frequency_from_callsign() {
    local callsign="$1"
    local location_info="${TRANSMITTERS[$callsign]}"

    if [ -n "$location_info" ]; then
        if [[ "$location_info" =~ \((162\.[0-9]{3})\ MHz\) ]]; then
            echo "${BASH_REMATCH[1]}M"
            return
        fi
    fi

    echo "162.550M"
}

# =====================================================================
# Main Selection Flow
# =====================================================================
select_state

load_state_data "$SELECTED_STATE" || exit 1

HAS_TRANSMITTERS=false
if [ ${#TRANSMITTERS[@]} -gt 0 ]; then
    HAS_TRANSMITTERS=true
fi

if $HAS_TRANSMITTERS; then
    select_transmitter || exit 1

    FREQUENCY=$(get_frequency_from_callsign "$SELECTED_CALL")
else
    clear
    print_header "NOAA WEATHER RADIO TRANSMITTER DATA"

    print_block_top
    print_block_row "STATUS" "NO NOAA WEATHER RADIO TRANSMITTERS"
    print_block_mid
    print_block_row "STATE" "$SELECTED_STATE_NAME"
    print_block_row "FILE" "$(basename "$SELECTED_STATE")"
    print_block_mid
    print_block_row "INFO" "This state/territory has no NWR transmitter data"
    print_block_row "ACTION" "Select a different state to continue"
    print_block_bot

    exit 1
fi

# =====================================================================
# Runtime Status Display
# =====================================================================
clear
CURRENT_TIME=$(date +"%m/%d/%Y %I:%M:%S %p")

if [ -n "$USB_HID" ] && [ -n "$USB_DESCRIPTION" ]; then
    HW_INFO="$USB_HID ($USB_DESCRIPTION)"
elif [ -n "$USB_HID" ]; then
    HW_INFO="$USB_HID"
else
    HW_INFO="Device Index: $RTL_SDR_INDEX"
fi

print_block_top
print_block_row "HARDWARE" "$HW_INFO"
print_block_row "STATE" "$SELECTED_STATE_NAME"
print_block_row "CALL SIGN" "$SELECTED_CALL"
print_block_row "FREQUENCY" "$FREQUENCY"
print_block_mid
echo -e "${CYAN}│${RESET} ${DIM}Press Ctrl+C to stop listening${RESET}"
echo -e "${CYAN}│${RESET} ${DIM}Started: $CURRENT_TIME${RESET}"
print_block_bot

info_log "Starting FM demodulation with de-emphasis filter..."
info_log "RTL-SDR device monitor: watching for disconnection every 5s"
echo ""

# =====================================================================
# RTL-SDR DEVICE MONITOR — Detect Physical Disconnection
# =====================================================================
# Monitor the FULL lsusb line (Bus/Device/HID) — not just the HID —
# because two identical RTL-SDRs share the same HID (0bda:2838).
# The Bus+Device number uniquely identifies THIS physical device.
ORIGINAL_USB_HID="$USB_HID"
ORIGINAL_DEVICE_LINE="$RTL_DEVICE_LINE"

(
    while true; do
        sleep 5

        current_usb_output=$(lsusb 2>/dev/null)

        if ! echo "$current_usb_output" | grep -qF "$ORIGINAL_DEVICE_LINE"; then
            echo ""
            print_block_top
            print_block_row "HARDWARE EVENT" "RTL-SDR DISCONNECTED"
            print_block_mid
            print_block_row "HID" "$ORIGINAL_USB_HID"
            print_block_row "DEVICE" "$ORIGINAL_DEVICE_LINE"
            print_block_row "STATUS" "Device removed or USB connection lost"
            print_block_row "ACTION" "Reconnect device and restart script"
            print_block_bot
            echo ""

            echo "1" > "$DEVICE_DISCONN_FLAG"

            pkill -f "rtl_fm.*$FREQUENCY" 2>/dev/null
            case "$AUDIO_PLAYER" in
                paplay)  pkill -f paplay 2>/dev/null ;;
                pw-play) pkill -f pw-play 2>/dev/null ;;
                aplay)   pkill -f aplay 2>/dev/null ;;
            esac

            kill $$ 2>/dev/null
            exit 0
        fi
    done
) &
DEVICE_MON_PID=$!

# =====================================================================
# LEAN STREAM PIPELINE (direct, no sox, includes deemp)
# =====================================================================
RTL_FM_CMD="rtl_fm -d $RTL_SDR_INDEX -f $FREQUENCY -M fm -s 24K -g 40 -l 40 -E deemp -F 9"

# Run pipeline in a subshell and track its PID for proper cleanup
(
    eval "$RTL_FM_CMD" 2>"$RTL_ERR_LOG" | \
    case "$AUDIO_PLAYER" in
        paplay)  paplay --raw --rate=24000 --format=s16le --channels=1 ;;
        pw-play) pw-play --raw --rate=24000 --format=s16le --channels=1 ;;
        aplay)   aplay -r 24000 -f s16_le -c 1 -t raw ;;
    esac
) &
STREAM_PID=$!
wait $STREAM_PID 2>/dev/null

# =====================================================================
# POST-STREAM DIAGNOSTICS
# =====================================================================
echo ""

if [ -f "$DEVICE_DISCONN_FLAG" ] && [ "$(cat "$DEVICE_DISCONN_FLAG" 2>/dev/null)" = "1" ]; then
    exit 0
fi

# Stream ended without disconnection — check for hardware errors
if [ -s "$RTL_ERR_LOG" ]; then
    print_block_top
    print_block_row "STATUS" "STREAM TERMINATED"
    print_block_mid
    echo -e "${CYAN}│${RESET} ${YELLOW}Hardware Diagnostics:${RESET}"

    while IFS= read -r diag_line; do
        [ -n "$diag_line" ] && echo -e "${CYAN}│${RESET}   $diag_line"
    done < "$RTL_ERR_LOG"

    print_block_mid
    echo -e "${CYAN}│${RESET} ${DIM}Possible causes: device locked, frequency invalid, or signal loss${RESET}"
    echo -e "${CYAN}│${RESET} ${DIM}Error log preserved at: $RTL_ERR_LOG${RESET}"
    print_block_bot
else
    echo -e "${DIM}[INFO] Stream ended${RESET}"
fi

echo ""
