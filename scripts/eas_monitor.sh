#!/bin/bash

# =======================================================================================================
# Author: DragoLuke
# USA Persistent SAME/EAS Monitor
# Target Environment: Debian/KDE OR DragonOS
# License: GNU General Public License v3.0 (GPL-3.0-or-later)
# Dependencies: rtl-sdr, multimon-ng, sox, alsa-utils, pw-play, paplay
# Description: Continuously monitors a NOAA Weather Radio transmitter
#              via RTL-SDR, decodes EAS/SAME headers with multimon-ng,
#              and captures full EAS transmissions (with pre-roll
#              audio) when a matching FIPS code is intercepted.
#              Custom WAV files are played on alert detection and EOM.
#              Supports ALL 50 states via generated state_data/*.txt files.
#              Test codes (RWT/RMT/NPT/DMO) can optionally trigger sounds.
# =======================================================================================================

# ======================================================
# FEATURE LIST
# ======================================================
# Core Monitoring:
#   - 56 EAS/SAME event codes recognized
#   - FIPS code matching — single county or ALL counties per state
#   - SAME header validation and decoder output logging
#
# Recording & Capture:
#   - Dual-output: .WAV audio + .TXT metadata for every alert
#   - Test alerts routed to dedicated alerts/tests/ subdirectory
#   - Pre-roll buffering (15-second lookback) — never miss alert beginnings
#   - Automatic EOM (End of Message) detection and buffer extraction
#   - 180 second timeout protection if EOM not received (.txt file is still saved)
#   - EOM Status tracking — partial captures marked as "Missed" in metadata
#
# Hardware Integration:
#   - RTL-SDR (V3) support via rtl_fm
#   - Auto-detect RTL-SDR devices via lsusb
#   - Dynamic frequency mapping from transmitter database
#   - Signal diagnostics logged on hardware errors
#   - RTL-SDR Disconnection Detection — Script exits gracefully on device removal
#
# Process Reliability:
#   - Watchdog process health check — auto-restarts drain & buffer manager
#   - Background PID tracking for all child processes
#   - Graceful cleanup on SIGINT/SIGTERM/EXIT
#   - Per-process error logging
#
# Storage Management:
#   - Pre-flight disk space verification
#   - Runtime disk monitor (warns at 20% remaining)
#   - Rotating temp file cleanup on start/exit
#   - Configurable save directory ($PROJECT_DIR/alerts)
#
# User Experience:
#   - Interactive state -> county -> transmitter selection menu
#   - Themed terminal output with colored status blocks
#   - Custom WAV sound playback on alert detection and EOM (user-configurable)
#   - Clear decoder sync messages during operation
#   - Skip notifications for alerts outside selected FIPS
#   - Optional: Test alarm for test codes (RWT/RMT/NPT/DMO)
#   - Optional: Audio enabled/disabled for headless systems
#   - Input Validation: Rejects non-numeric and out-of-range entries
#
# Date Organization:
#   - Alerts saved in dated subdirectories (YYYY/MM_DD/)
#   - Keeps alert folders organized by capture date
#   - Filename format: HHMM (hour and minute only)
#
# Dependencies (Minimal):
#   - rtl-sdr (rtl_fm) — core RF capture
#   - multimon-ng (The 3 tested versions are 1.3.0, 1.3.1, and 1.4.1) — SAME/EAS decoding
#   - sox — audio processing and WAV conversion
#   - Optional: pw-play, play (sox), paplay/aplay for alert/eom sound playback
# =======================================================================================================

# ======================================================
# PROJECT CONFIGURATION
# ======================================================
PROJECT_DIR="$HOME/StormScales"
STATE_DATA_DIR="$PROJECT_DIR/media/state_data"
SAVE_DIR="$PROJECT_DIR/scripts/alerts"
TEMP_DATA_DIR="$PROJECT_DIR/scripts/temp"

umask 077

mkdir -p "$SAVE_DIR"
mkdir -p "$SAVE_DIR/tests"
mkdir -p "$TEMP_DATA_DIR"
chmod 700 "$TEMP_DATA_DIR" "$SAVE_DIR" "$SAVE_DIR/tests"

# ======================================================
# FILE PATHS
# ======================================================
DECODER_LOG="$TEMP_DATA_DIR/eas_raw_string.txt"
LIVE_BUFFER="$TEMP_DATA_DIR/eas_live_buffer.raw"
STATE_FILE="$TEMP_DATA_DIR/eas_alert_state"
OFFSET_FILE="$TEMP_DATA_DIR/alert_start_offset"
EXTRACT_RAW="$TEMP_DATA_DIR/extract.raw"

RTL_ERR_LOG="$TEMP_DATA_DIR/eas_rtl_err.log"
EXTRACT_ERR_LOG="$TEMP_DATA_DIR/eas_extract_errors.log"
DEBUG_LOG="$TEMP_DATA_DIR/eas_debug.log"

SELECTED_STATE_FILE="$TEMP_DATA_DIR/selected_state"
MM_RESTART_FLAG="$TEMP_DATA_DIR/mm_restart"
DEVICE_DISCONN_FLAG="$TEMP_DATA_DIR/device_disconnected"
AUDIO_FIFO="$TEMP_DATA_DIR/eas_audio.fifo"

DRAIN_PID_FILE="$TEMP_DATA_DIR/drain.pid"
BUFFER_MGR_PID_FILE="$TEMP_DATA_DIR/buffer_mgr.pid"
WATCHDOG_PID_FILE="$TEMP_DATA_DIR/watchdog.pid"
DISK_MON_PID_FILE="$TEMP_DATA_DIR/disk_mon.pid"
DEVICE_MON_PID_FILE="$TEMP_DATA_DIR/device_mon.pid"

ALERT_TYPE_FILE="$TEMP_DATA_DIR/alert_type"
ALERT_HAZARD_FILE="$TEMP_DATA_DIR/alert_hazard"
ALERT_IS_TEST_FILE="$TEMP_DATA_DIR/alert_is_test"
ALERT_INTERCEPT_FILE="$TEMP_DATA_DIR/alert_intercept_time"
ALERT_COUNTY_FILE="$TEMP_DATA_DIR/alert_county"
ALERT_DECODER_FILE="$TEMP_DATA_DIR/alert_decoder"
ALERT_OFFSET_FILE="$TEMP_DATA_DIR/alert_offset"
ALERT_PLAY_SOUNDS_FILE="$TEMP_DATA_DIR/alert_play_sounds"
ALERT_EOM_STATUS_FILE="$TEMP_DATA_DIR/alert_eom_status"

SNAPSHOT_RAW="$TEMP_DATA_DIR/eas_snapshot.raw"

# ======================================================
# HARDWARE CONFIGURATION
# ======================================================
RTL_DEVICE_INDEX="0"
USB_HID=""
USB_DESCRIPTION=""
VERBOSE_MODE=true
GAIN="40"
SQUELCH="10"
FIR="0"
PPM_CORRECTION="0"

# ======================================================
# AUDIO / BUFFER CONFIGURATION
# ======================================================
SAMPLE_RATE=22050
BYTES_PER_SAMPLE=2
BYTES_PER_SECOND=$((SAMPLE_RATE * BYTES_PER_SAMPLE))
PRE_ROLL_SECONDS=15
PRE_ROLL_BYTES=$((PRE_ROLL_SECONDS * BYTES_PER_SECOND))
MAX_STANDBY_SECONDS=120
MAX_STANDBY_BYTES=$((MAX_STANDBY_SECONDS * BYTES_PER_SECOND))
DISK_WARNING_THRESHOLD=20
EOM_TIMEOUT_SECONDS=180

# ======================================================
# DATE ORGANIZATION
# ======================================================
ENABLE_DATE_DIRS=true
HOUR_MINUTE_FORMAT="%H%M"

# ======================================================
# USER OPTIONS
# ======================================================
ENABLE_TEST_TONES=false
ENABLE_AUDIO=true
MONITOR_ALL=false
FREQUENCY=""
SOURCE_ID=""

# ======================================================
# CUSTOM ALERT SOUNDS
# ======================================================
ALERT_WAV="$PROJECT_DIR/media/alert.wav"
EOM_WAV="$PROJECT_DIR/media/eom.wav"

get_play_command() {
    if command -v paplay &> /dev/null; then
        echo "paplay"
    elif command -v pw-play &> /dev/null; then
        echo "pw-play"
    elif command -v play &> /dev/null; then
        echo "play"
    elif command -v aplay &> /dev/null; then
        echo "aplay"
    else
        echo ""
    fi
}

play_custom_wav() {
    local wav_file="$1"

    if ! $ENABLE_AUDIO; then
        return
    fi

    local player_cmd
    player_cmd=$(get_play_command)

    if [ -z "$player_cmd" ]; then
        return
    fi

    if [ ! -f "$wav_file" ]; then
        return
    fi

    case "$player_cmd" in
        pw-play) pw-play "$wav_file" &>/dev/null & ;;
        play)    play "$wav_file" &>/dev/null & ;;
        paplay)  paplay "$wav_file" &>/dev/null & ;;
        aplay)   aplay "$wav_file" &>/dev/null & ;;
    esac
}

# ======================================================
# TERMINAL COLOUR CONSTANTS
# ======================================================
RED='\033[1;31m'
YELLOW='\033[1;33m'
GREEN='\033[1;32m'
CYAN='\033[1;36m'
DIM='\033[2m'
RESET='\033[0m'

print_header() {
    echo -e "\n--------------------------------------------------------------------------------"
    echo -e " \033[1;36m» $1\033[0m"
    echo -e "--------------------------------------------------------------------------------"
}

print_block_top() {
    echo -e "\033[1;36m┌──────────────────────────────────────────────────────────────────┐\033[0m"
}

print_block_mid() {
    echo -e "\033[1;36m├──────────────────────────────────────────────────────────────────┤\033[0m"
}

print_block_bot() {
    echo -e "\033[1;36m└──────────────────────────────────────────────────────────────────┘\033[0m"
}

print_block_row() {
    local label="$1"
    local value="$2"
    printf "\033[1;36m│\033[0m \033[1;36m%-14s\033[0m %s\n" "$label" "$value"
}

info_log() {
    if $VERBOSE_MODE; then
        echo -e " \033[2m[INFO] $1\033[0m"
    fi
}

# ======================================================
# INPUT VALIDATION FUNCTIONS
# ======================================================
validate_numeric_input() {
    local input="$1"
    [[ "$input" =~ ^[0-9]+$ ]] && return 0 || return 1
}

validate_range() {
    local input="$1"
    local min="$2"
    local max="$3"

    validate_numeric_input "$input" || return 1
    [ "$input" -ge "$min" ] && [ "$input" -le "$max" ] && return 0 || return 1
}

get_validated_selection() {
    local prompt="$1"
    local default="$2"
    local min="$3"
    local max="$4"
    local allow_default="$5"

    local validated_input=""
    local attempts=0
    local max_attempts=10

    while [ $attempts -lt $max_attempts ]; do
        echo -ne "  \033[1;36m${prompt}\033[0m" >&2
        read -r validated_input

        validated_input="${validated_input#"${validated_input%%[![:space:]]*}"}"
        validated_input="${validated_input%"${validated_input##*[![:space:]]}"}"

        if [ ${#validated_input} -gt 10 ]; then
            echo -e "\033[1;31m[ERROR] Input too long (max 10 characters)\033[0m" >&2
            echo "" >&2
            ((attempts++))
            continue
        fi

        if [ -z "$validated_input" ]; then
            if [ "$allow_default" = "true" ]; then
                echo "$default"
                return 0
            else
                echo -e "\033[1;31m[ERROR] Input cannot be empty.\033[0m" >&2
                echo -e "\033[2mValid range: $min to $max\033[0m" >&2
                echo "" >&2
                ((attempts++))
                continue
            fi
        fi

        if ! validate_numeric_input "$validated_input"; then
            echo -e "\033[1;31m[ERROR] Invalid selection: '$validated_input' is not a number\033[0m" >&2
            echo -e "\033[2mValid range: $min to $max\033[0m" >&2
            echo "" >&2
            ((attempts++))
            continue
        fi

        if [ "$validated_input" -ge "$min" ] && [ "$validated_input" -le "$max" ]; then
            echo "$validated_input"
            return 0
        else
            echo -e "\033[1;31m[ERROR] Invalid selection: '$validated_input'\033[0m" >&2
            echo -e "\033[2mValid range: $min to $max\033[0m" >&2
            echo "" >&2
            ((attempts++))
        fi
    done

    echo -e "\033[1;31m[ERROR] Too many invalid attempts. Exiting setup.\033[0m" >&2
    exit 1
}

# ======================================================
# CLEANUP HANDLER
# ======================================================
cleanup() {
    $CLEANUP_DONE && return
    CLEANUP_DONE=true

    if [ -f "$DEVICE_DISCONN_FLAG" ] && [ "$(cat "$DEVICE_DISCONN_FLAG" 2>/dev/null)" = "1" ]; then
        if [ -n "${TIMEOUT_PID:-}" ]; then
            kill "$TIMEOUT_PID" 2>/dev/null
        fi
        if [ -f "$TEMP_DATA_DIR/timeout.pid" ]; then
            local TIMEOUT_PID_FILE=$(cat "$TEMP_DATA_DIR/timeout.pid" 2>/dev/null)
            [[ -n "$TIMEOUT_PID_FILE" ]] && kill "$TIMEOUT_PID_FILE" 2>/dev/null
        fi

        pkill -P $$ 2>/dev/null
        pkill -f rtl_fm 2>/dev/null
        pkill -f multimon-ng 2>/dev/null

        [[ -n "${DRAIN_PID:-}" ]] && kill "$DRAIN_PID" 2>/dev/null
        [[ -n "${BUFFER_MGR_PID:-}" ]] && kill "$BUFFER_MGR_PID" 2>/dev/null
        [[ -n "${WATCHDOG_PID:-}" ]] && kill "$WATCHDOG_PID" 2>/dev/null
        [[ -n "${DISK_MON_PID:-}" ]] && kill "$DISK_MON_PID" 2>/dev/null
        [[ -n "${DEVICE_MON_PID:-}" ]] && kill "$DEVICE_MON_PID" 2>/dev/null

        sleep 1
        wait 2>/dev/null

        rm -f "$LIVE_BUFFER" "$DECODER_LOG" "$STATE_FILE" \
               "$AUDIO_FIFO" "$OFFSET_FILE" "$EXTRACT_RAW" "$EXTRACT_ERR_LOG" \
               "$DEBUG_LOG" "$SELECTED_STATE_FILE" \
               "$DRAIN_PID_FILE" "$BUFFER_MGR_PID_FILE" \
               "$WATCHDOG_PID_FILE" "$DISK_MON_PID_FILE" "$DEVICE_MON_PID_FILE" \
               "$TEMP_DATA_DIR/timeout.pid" \
               "$MM_RESTART_FLAG" "$DEVICE_DISCONN_FLAG" \
               "$ALERT_EOM_STATUS_FILE" \
               "$SNAPSHOT_RAW" "$TEMP_DATA_DIR"/alert_* 2>/dev/null
        exit 0
    fi

    echo -e "\n\033[1;33m[!] Exit signal received. Terminating hardware processes...\033[0m"

    if [ -n "${TIMEOUT_PID:-}" ]; then
        kill "$TIMEOUT_PID" 2>/dev/null
    fi
    if [ -f "$TEMP_DATA_DIR/timeout.pid" ]; then
        local TIMEOUT_PID_FILE=$(cat "$TEMP_DATA_DIR/timeout.pid" 2>/dev/null)
        [[ -n "$TIMEOUT_PID_FILE" ]] && kill "$TIMEOUT_PID_FILE" 2>/dev/null
    fi

    pkill -P $$ 2>/dev/null
    pkill -f rtl_fm 2>/dev/null
    pkill -f multimon-ng 2>/dev/null

    [[ -n "${DRAIN_PID:-}" ]] && kill "$DRAIN_PID" 2>/dev/null
    [[ -n "${BUFFER_MGR_PID:-}" ]] && kill "$BUFFER_MGR_PID" 2>/dev/null
    [[ -n "${WATCHDOG_PID:-}" ]] && kill "$WATCHDOG_PID" 2>/dev/null
    [[ -n "${DISK_MON_PID:-}" ]] && kill "$DISK_MON_PID" 2>/dev/null
    [[ -n "${DEVICE_MON_PID:-}" ]] && kill "$DEVICE_MON_PID" 2>/dev/null

    for pidfile in "$DRAIN_PID_FILE" "$BUFFER_MGR_PID_FILE" "$WATCHDOG_PID_FILE" \
                   "$DISK_MON_PID_FILE" "$DEVICE_MON_PID_FILE" "$TEMP_DATA_DIR/timeout.pid"; do
        if [ -f "$pidfile" ]; then
            PID_FROM_FILE=$(cat "$pidfile" 2>/dev/null)
            [[ -n "$PID_FROM_FILE" ]] && kill "$PID_FROM_FILE" 2>/dev/null
        fi
    done

    sleep 2

    rm -f "$LIVE_BUFFER" "$DECODER_LOG" "$STATE_FILE" \
           "$AUDIO_FIFO" "$OFFSET_FILE" "$EXTRACT_RAW" "$EXTRACT_ERR_LOG" \
           "$DEBUG_LOG" "$SELECTED_STATE_FILE" \
           "$DRAIN_PID_FILE" "$BUFFER_MGR_PID_FILE" \
           "$WATCHDOG_PID_FILE" "$DISK_MON_PID_FILE" "$DEVICE_MON_PID_FILE" \
           "$TEMP_DATA_DIR/timeout.pid" \
           "$MM_RESTART_FLAG" "$DEVICE_DISCONN_FLAG" \
           "$ALERT_EOM_STATUS_FILE" \
           "$SNAPSHOT_RAW" "$TEMP_DATA_DIR"/alert_* 2>/dev/null

    exit 0
}

trap cleanup SIGINT SIGTERM EXIT

# ==================================================================================================
# EAS EVENT CODE DICTIONARY
# All codes verified against weather.gov/nwr/eventcodes and 47 CFR Part 11 (eCFR) — as of 2026-09-08
# [PS Docket No. 15-94; FCC 22-75; FR ID 110632]
# ==================================================================================================
declare -A HAZARDS

# --- Official NWR-SAME: Weather-related ---
HAZARDS["BZW"]="BLIZZARD WARNING"
HAZARDS["CFA"]="COASTAL FLOOD WATCH"
HAZARDS["CFW"]="COASTAL FLOOD WARNING"
HAZARDS["DSW"]="DUST STORM WARNING"
HAZARDS["EWW"]="EXTREME WIND WARNING"
HAZARDS["FFA"]="FLASH FLOOD WATCH"
HAZARDS["FFW"]="FLASH FLOOD WARNING"
HAZARDS["FFS"]="FLASH FLOOD STATEMENT"
HAZARDS["FLA"]="FLOOD WATCH"
HAZARDS["FLW"]="FLOOD WARNING"
HAZARDS["FLS"]="FLOOD STATEMENT"
HAZARDS["HWA"]="HIGH WIND WATCH"
HAZARDS["HWW"]="HIGH WIND WARNING"
HAZARDS["HUA"]="HURRICANE WATCH"
HAZARDS["HUW"]="HURRICANE WARNING"
HAZARDS["HLS"]="HURRICANE STATEMENT"
HAZARDS["SVA"]="SEVERE THUNDERSTORM WATCH"
HAZARDS["SVR"]="SEVERE THUNDERSTORM WARNING"
HAZARDS["SVS"]="SEVERE WEATHER STATEMENT"
HAZARDS["SQW"]="SNOW SQUALL WARNING"
HAZARDS["SMW"]="SPECIAL MARINE WARNING"
HAZARDS["SPS"]="SPECIAL WEATHER STATEMENT"
HAZARDS["SSA"]="STORM SURGE WATCH"
HAZARDS["SSW"]="STORM SURGE WARNING"
HAZARDS["TOA"]="TORNADO WATCH"
HAZARDS["TOR"]="TORNADO WARNING"
HAZARDS["TRA"]="TROPICAL STORM WATCH"
HAZARDS["TRW"]="TROPICAL STORM WARNING"
HAZARDS["TSA"]="TSUNAMI WATCH"
HAZARDS["TSW"]="TSUNAMI WARNING"
HAZARDS["WSA"]="WINTER STORM WATCH"
HAZARDS["WSW"]="WINTER STORM WARNING"

# --- Official NWR-SAME: Non-weather (state & local) ---
HAZARDS["AVA"]="AVALANCHE WATCH"
HAZARDS["AVW"]="AVALANCHE WARNING"
HAZARDS["BLU"]="BLUE ALERT"
HAZARDS["CAE"]="CHILD ABDUCTION EMERGENCY"
HAZARDS["CDW"]="CIVIL DANGER WARNING"
HAZARDS["CEM"]="CIVIL EMERGENCY MESSAGE"
HAZARDS["EQW"]="EARTHQUAKE WARNING"
HAZARDS["EVI"]="EVACUATION IMMEDIATE"
HAZARDS["FRW"]="FIRE WARNING"
HAZARDS["HMW"]="HAZARDOUS MATERIALS WARNING"
HAZARDS["LEW"]="LAW ENFORCEMENT WARNING"
HAZARDS["LAE"]="LOCAL AREA EMERGENCY"
HAZARDS["TOE"]="911 TELEPHONE OUTAGE EMERGENCY"
HAZARDS["NUW"]="NUCLEAR POWER PLANT WARNING"
HAZARDS["RHW"]="RADIOLOGICAL HAZARD WARNING"
HAZARDS["SPW"]="SHELTER IN-PLACE WARNING"
HAZARDS["VOW"]="VOLCANO WARNING"

# --- Official NWR-SAME: Administrative ---
HAZARDS["ADR"]="ADMINISTRATIVE MESSAGE"
HAZARDS["DMO"]="PRACTICE/DEMO WARNING"
HAZARDS["RMT"]="REQUIRED MONTHLY TEST"
HAZARDS["RWT"]="REQUIRED WEEKLY TEST"

# --- EAS National Codes (eCFR 47 CFR Part 11) ---
HAZARDS["EAN"]="NATIONAL EMERGENCY MESSAGE"                     # Renamed from "Emergency Action Notification" by FCC 2022
HAZARDS["NPT"]="NATIONWIDE TEST OF THE EMERGENCY ALERT SYSTEM"  # Renamed from "National Periodic Test" by FCC 2022
HAZARDS["MEP"]="MISSING AND ENDANGERED PERSONS ALERT"           # Adopted by FCC, effective Sept 8, 2025

# ======================================================
# TEST DETECTION
# ======================================================
TEST_CODES=("RWT" "RMT" "NPT" "DMO")

is_test_code() {
    local code="$1"
    for t in "${TEST_CODES[@]}"; do
        [[ "$code" == "$t" ]] && return 0
    done
    return 1
}

# ============================================================================
# STATE NAME TO ABBREVIATION MAPPING
# ============================================================================
declare -A STATE_ABBRS

STATE_ABBRS["ALABAMA"]="AL"
STATE_ABBRS["ALASKA"]="AK"
STATE_ABBRS["ARIZONA"]="AZ"
STATE_ABBRS["ARKANSAS"]="AR"
STATE_ABBRS["CALIFORNIA"]="CA"
STATE_ABBRS["COLORADO"]="CO"
STATE_ABBRS["CONNECTICUT"]="CT"
STATE_ABBRS["DELAWARE"]="DE"
STATE_ABBRS["DISTRICT OF COLUMBIA"]="DC"
STATE_ABBRS["FLORIDA"]="FL"
STATE_ABBRS["GEORGIA"]="GA"
STATE_ABBRS["HAWAII"]="HI"
STATE_ABBRS["IDAHO"]="ID"
STATE_ABBRS["ILLINOIS"]="IL"
STATE_ABBRS["INDIANA"]="IN"
STATE_ABBRS["IOWA"]="IA"
STATE_ABBRS["KANSAS"]="KS"
STATE_ABBRS["KENTUCKY"]="KY"
STATE_ABBRS["LOUISIANA"]="LA"
STATE_ABBRS["MAINE"]="ME"
STATE_ABBRS["MARYLAND"]="MD"
STATE_ABBRS["MASSACHUSETTS"]="MA"
STATE_ABBRS["MICHIGAN"]="MI"
STATE_ABBRS["MINNESOTA"]="MN"
STATE_ABBRS["MISSISSIPPI"]="MS"
STATE_ABBRS["MISSOURI"]="MO"
STATE_ABBRS["MONTANA"]="MT"
STATE_ABBRS["NEBRASKA"]="NE"
STATE_ABBRS["NEVADA"]="NV"
STATE_ABBRS["NEW HAMPSHIRE"]="NH"
STATE_ABBRS["NEW JERSEY"]="NJ"
STATE_ABBRS["NEW MEXICO"]="NM"
STATE_ABBRS["NEW YORK"]="NY"
STATE_ABBRS["NORTH CAROLINA"]="NC"
STATE_ABBRS["NORTH DAKOTA"]="ND"
STATE_ABBRS["OHIO"]="OH"
STATE_ABBRS["OKLAHOMA"]="OK"
STATE_ABBRS["OREGON"]="OR"
STATE_ABBRS["PENNSYLVANIA"]="PA"
STATE_ABBRS["RHODE ISLAND"]="RI"
STATE_ABBRS["SOUTH CAROLINA"]="SC"
STATE_ABBRS["SOUTH DAKOTA"]="SD"
STATE_ABBRS["TENNESSEE"]="TN"
STATE_ABBRS["TEXAS"]="TX"
STATE_ABBRS["UTAH"]="UT"
STATE_ABBRS["VERMONT"]="VT"
STATE_ABBRS["VIRGINIA"]="VA"
STATE_ABBRS["WASHINGTON"]="WA"
STATE_ABBRS["WEST VIRGINIA"]="WV"
STATE_ABBRS["WISCONSIN"]="WI"
STATE_ABBRS["WYOMING"]="WY"

declare -A ABBR_TO_IDX

load_state_data() {
    local state_file="$1"

    if [ ! -f "$state_file" ]; then
        echo -e "\033[1;31m[ERROR] State data file not found: $state_file\033[0m" >&2
        return 1
    fi

    declare -gA STATE_COUNTIES
    declare -gA TRANSMITTERS
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
        echo -e "\033[1;31m[ERROR] No county data found in: $state_file\033[0m" >&2
        return 1
    fi

    return 0
}

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

select_state() {
    clear
    print_header "EAS MONITOR SETUP: SELECT STATE OR TERRITORY"

    if [ ! -d "$STATE_DATA_DIR" ]; then
        print_block_top
        print_block_row "STATUS" "ERROR"
        print_block_mid
        print_block_row "MESSAGE" "state_data directory not found"
        print_block_row "PATH" "$STATE_DATA_DIR"
        print_block_row "ACTION" "Run eas_fips_setup.sh first to generate state files"
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
        print_block_row "ACTION" "Run eas_fips_setup.sh first to generate state files"
        print_block_bot
        exit 1
    fi

    mapfile -t STATE_ENTRIES < <(for sf in "${STATE_FILES[@]}"; do
        dn=$(basename "$sf" .txt | tr '_' ' ' | tr '[:lower:]' '[:upper:]')
        echo "${dn}|${sf}"
    done | sort)

    local num_entries=${#STATE_ENTRIES[@]}

    ABBR_TO_IDX=()
    for ((i=0; i<num_entries; i++)); do
        IFS='|' read -r name _ <<< "${STATE_ENTRIES[i]}"
        local abbr="${STATE_ABBRS[$name]}"
        if [ -n "$abbr" ]; then
            ABBR_TO_IDX["$abbr"]=$i
        fi
    done

    echo -e "  \033[1;36mAvailable States/Territories:\033[0m"
    echo ""

    for ((i=0; i<num_entries; i+=2)); do
        IFS='|' read -r name1 _ <<< "${STATE_ENTRIES[i]}"
        local abbr1="${STATE_ABBRS[$name1]}"
        printf "  \033[1;36m%2d)\033[0m %-4s %-30s" "$((i+1))" "[${abbr1}]" "$name1"
        if [[ $((i+1)) -lt $num_entries ]]; then
            IFS='|' read -r name2 _ <<< "${STATE_ENTRIES[i+1]}"
            local abbr2="${STATE_ABBRS[$name2]}"
            printf "  \033[1;36m%2d)\033[0m %-4s %-30s\n" "$((i+2))" "[${abbr2}]" "$name2"
        else
            echo ""
        fi
    done

    echo "--------------------------------------------------------------------------------"
    echo -e "  \033[2mPress Enter for first state, or type a number/abbreviation.\033[0m"
    echo -e "  \033[2mExamples: 1, 27, MT, CA, DC\033[0m"
    echo ""

    local state_selection
    local attempts=0
    local max_attempts=10

    while [ $attempts -lt $max_attempts ]; do
        echo -ne "  \033[1;36mSelect State Number or Abbreviation [Default: 1]\033[0m "
        read -r state_selection

        if [ -z "$state_selection" ]; then
            state_selection="1"
        fi

        state_selection="${state_selection#"${state_selection%%[![:space:]]*}"}"
        state_selection="${state_selection%"${state_selection##*[![:space:]]}"}"
        state_selection="${state_selection^^}"

        if [[ "$state_selection" =~ ^[0-9]+$ ]]; then
            if [ "$state_selection" -ge 1 ] && [ "$state_selection" -le "$num_entries" ]; then
                IFS='|' read -r SELECTED_STATE_NAME SELECTED_STATE <<< "${STATE_ENTRIES[$((state_selection-1))]}"
                break
            else
                echo -e "\033[1;31m[ERROR] Number '$state_selection' out of range (1-$num_entries).\033[0m" >&2
                ((attempts++))
                continue
            fi
        fi

        if [ -n "${ABBR_TO_IDX[$state_selection]}" ]; then
            local idx="${ABBR_TO_IDX[$state_selection]}"
            IFS='|' read -r SELECTED_STATE_NAME SELECTED_STATE <<< "${STATE_ENTRIES[$idx]}"
            break
        else
            echo -e "\033[1;31m[ERROR] Unknown state abbreviation '$state_selection'. Use number or 2-letter code (e.g., MT, CA, TX).\033[0m" >&2
            ((attempts++))
            continue
        fi
    done

    if [ $attempts -ge $max_attempts ]; then
        echo -e "\033[1;31m[ERROR] Too many invalid attempts. Exiting setup.\033[0m" >&2
        exit 1
    fi

    echo -e "\n\033[1;32mSelected: $SELECTED_STATE_NAME (${STATE_ABBRS[$SELECTED_STATE_NAME]})\033[0m"
    echo -e "\033[2mFile: $SELECTED_STATE\033[0m"
}

select_county() {
    clear
    print_header "EAS MONITOR SETUP: SELECT COUNTY"

    local num_counties=${#STATE_COUNTIES[@]}

    mapfile -t SORTED_COUNTIES < <(for k in "${!STATE_COUNTIES[@]}"; do echo "$k"; done | sort)

    echo -e "  \033[1;36m[0]\033[0m ALL ${SELECTED_STATE_NAME^^} COUNTIES"
    echo ""

    for ((i=0; i<num_counties; i+=2)); do
        printf "  \033[1;36m[%2d]\033[0m %-22s" "$((i+1))" "${SORTED_COUNTIES[i]//_/ }"
        if [[ $((i+1)) -lt $num_counties ]]; then
            printf "  \033[1;36m[%2d]\033[0m %-22s\n" "$((i+2))" "${SORTED_COUNTIES[i+1]//_/ }"
        else
            echo ""
        fi
    done

    echo ""
    echo "---------------------------------------------------------------------"
    echo -e "  Enter 0 for ALL counties, or 1-${num_counties} for a specific county"
    echo -e "  \033[2mExamples: 0, 14, 56\033[0m"
    echo ""

    local county_idx
    county_idx=$(get_validated_selection "Select County Number [Default: 1]: " "1" "0" "$num_counties" "true")

    MONITOR_ALL=false
    if [[ -z "$county_idx" ]]; then
        SELECTED_COUNTY="${SORTED_COUNTIES[0]}"
        SELECTED_FIPS="${STATE_COUNTIES[$SELECTED_COUNTY]}"
    elif [[ "$county_idx" == "0" ]]; then
        SELECTED_COUNTY="ALL ${SELECTED_STATE_NAME^^}"
        SELECTED_FIPS=""
        MONITOR_ALL=true
    else
        SELECTED_COUNTY="${SORTED_COUNTIES[$((county_idx-1))]}"
        SELECTED_FIPS="${STATE_COUNTIES[$SELECTED_COUNTY]}"
    fi

    echo ""
    echo -e "\033[1;32mCounty: $SELECTED_COUNTY\033[0m"
    if ! $MONITOR_ALL; then
        echo -e "\033[2mFIPS: $SELECTED_FIPS\033[0m"
    else
        echo -e "\033[2mMode: Any matching FIPS in ${SELECTED_STATE_NAME^^} will trigger\033[0m"
    fi
}

select_transmitter() {
    clear
    print_header "EAS MONITOR SETUP: SELECT NOAA CALL SIGN"

    if [ ${#TRANSMITTERS[@]} -eq 0 ]; then
        print_block_top
        print_block_row "STATUS" "WARNING"
        print_block_mid
        print_block_row "MESSAGE" "No transmitter data available for this state"
        print_block_row "ACTION" "Check state_data/$(basename "$SELECTED_STATE").txt"
        print_block_bot
        echo ""
        echo -e "\033[1;33mNote: Some states (e.g., District of Columbia) have no NWR transmitters.\033[0m"
        sleep 2
        return 1
    fi

    local num_transmitters=${#TRANSMITTERS[@]}

    mapfile -t SORTED_CALLS < <(for i in "${!TRANSMITTERS[@]}"; do echo "$i"; done | sort)
    for i in "${!SORTED_CALLS[@]}"; do
        call="${SORTED_CALLS[i]}"
        printf "  \033[1;36m%2d)\033[0m %-8s - %s\n" "$((i+1))" "$call" "${TRANSMITTERS[$call]}"
    done

    echo "--------------------------------------------------------------------------------"
    echo -e "  \033[1;36mDefault: First Call Sign\033[0m"
    echo ""

    local call_idx
    call_idx=$(get_validated_selection "Select Call Sign Number [Default: 1]: " "1" "1" "$num_transmitters" "true")

    if [[ -z "$call_idx" ]]; then
        SELECTED_CALL="${SORTED_CALLS[0]}"
    else
        SELECTED_CALL="${SORTED_CALLS[$((call_idx-1))]}"
    fi

    echo -e "\n\033[1;32mSelected: $SELECTED_CALL\033[0m"
    echo -e "\033[2mInfo: ${TRANSMITTERS[$SELECTED_CALL]}\033[0m"

    SOURCE_ID="$SELECTED_CALL - ${TRANSMITTERS[$SELECTED_CALL]}"
}

normalize_fips() {
    local fips="$1"
    fips="${fips//[^0-9]/}"
    fips=$(printf "%06d" "$((10#$fips))")
    echo "$fips"
}

# ======================================================
# MAIN SELECTION FLOW
# ======================================================
rm -f "$LIVE_BUFFER" "$DECODER_LOG" "$STATE_FILE" "$RTL_ERR_LOG" \
       "$AUDIO_FIFO" "$OFFSET_FILE" "$EXTRACT_RAW" "$EXTRACT_ERR_LOG" \
       "$DEBUG_LOG" "$SELECTED_STATE_FILE" \
       "$DRAIN_PID_FILE" "$BUFFER_MGR_PID_FILE" \
       "$WATCHDOG_PID_FILE" "$DISK_MON_PID_FILE" "$DEVICE_MON_PID_FILE" \
       "$MM_RESTART_FLAG" "$DEVICE_DISCONN_FLAG" \
       "$ALERT_EOM_STATUS_FILE" "$TEMP_DATA_DIR"/alert_* "$SNAPSHOT_RAW" 2>/dev/null

echo "0" > "$STATE_FILE"
echo "pending" > "$ALERT_EOM_STATUS_FILE"
touch "$DEVICE_DISCONN_FLAG"

TIMEOUT_PID=""
WATCHDOG_PID=""
DISK_MON_PID=""
DEVICE_MON_PID=""
CLEANUP_DONE=false

while true; do
    echo -ne "  \033[1;36mDo you want to display detailed [INFO] messages? [Y/n] \033[0m"
    read -r VERBOSE_RESPONSE

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
            echo -e "\033[1;31m[ERROR] Invalid input: '$VERBOSE_RESPONSE'\033[0m" >&2
            echo -e "\033[2mPlease enter Y or N (default: Y)\033[0m" >&2
            echo "" >&2
            continue
            ;;
    esac
done

detect_all_rtl_sdars() {
    local usb_output
    usb_output=$(lsusb 2>/dev/null)

    mapfile -t RTL_DEVICES < <(echo "$usb_output" | grep -niE "2838|RTL2832|RTL-SDR")

    if [ ${#RTL_DEVICES[@]} -eq 0 ]; then
        return 1
    fi

    return 0
}

select_rtl_sdr_device() {
    clear
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

    echo -e "  \033[1;36mConnected RTL-SDR Devices:\033[0m"
    echo ""

    for ((i=0; i<num_devices; i++)); do
        local device_line="${RTL_DEVICES[$i]}"
        local line_num="${device_line%%:*}"
        local usb_info="${device_line#*:}"

        local usb_id
        usb_id=$(echo "$usb_info" | grep -oP 'ID\s+\K[A-Fa-f0-9]{4}:[A-Fa-f0-9]{4}' || echo "N/A")
        local usb_desc
        usb_desc=$(echo "$usb_info" | sed 's/.*ID [0-9a-f]*:[0-9a-f]* //')

        printf "  \033[1;36m[%d]\033[0m %s\n" "$((i+1))" "$usb_desc"
        printf "       \033[2mUSB ID: %s\033[0m\n" "$usb_id"
        printf "       \033[2mlsusb line: %d | rtl_fm -d index: %d\033[0m\n" "$line_num" "$i"
        echo ""
    done

    echo "--------------------------------------------------------------------------------"
    echo -e "  \033[2mIf you only have one RTL-SDR, just press Enter to select it.\033[0m"
    echo ""

    local device_choice
    device_choice=$(get_validated_selection "Select Device Number [Default: 1]: " "1" "1" "$num_devices" "true")

    local selected_line_num
    selected_line_num=$(echo "${RTL_DEVICES[$((device_choice-1))]}" | cut -d':' -f1)

    RTL_DEVICE_INDEX="$selected_line_num"

    RTL_SDR_INDEX=$((device_choice - 1))

    echo ""
    echo -e "\033[1;32mSelected device:\033[0m"
    echo ""

    echo -e "\033[2mFull device info:\033[0m"
    echo -e "\033[2m$(lsusb 2>/dev/null | sed -n "${RTL_DEVICE_INDEX}p")\033[0m"

    return 0
}

select_rtl_sdr_device

# ======================================================
# EXTRACT AND VALIDATE USB DEVICE INFO
# ======================================================
target_device=$(lsusb 2>/dev/null | sed -n "${RTL_DEVICE_INDEX}p")

if [ -z "$target_device" ]; then
    echo -e "\033[1;31m[ERROR] Device at lsusb line $RTL_DEVICE_INDEX not found!\033[0m" >&2
    cleanup
fi

USB_HID=$(echo "$target_device" | grep -oP 'ID\s+\K[A-Fa-f0-9]{4}:[A-Fa-f0-9]{4}')
USB_DESCRIPTION=$(echo "$target_device" | sed 's/.*ID [0-9a-f]*:[0-9a-f]* //')

if [ -z "$USB_HID" ]; then
    echo -e "\033[1;31m[ERROR] Could not extract USB HID from device!\033[0m" >&2
    cleanup
fi

if ! echo "$USB_HID" | grep -qE '^0bda:(2838|2832)$'; then
    echo -e "\033[1;31m[ERROR] Selected device is NOT an RTL-SDR!\033[0m" >&2
    echo -e "\033[2mExpected: 0bda:2838 or 0bda:2832, Got: $USB_HID\033[0m" >&2
    echo -e "\033[2mDevice: $target_device\033[0m" >&2
    cleanup
fi

info_log "Detected USB HID: $USB_HID"
info_log "Device description: $USB_DESCRIPTION"

print_header "DEPENDENCY CHECK"

MISSING_CORE=false
CORE_MISSING=""

command -v rtl_fm &> /dev/null || { MISSING_CORE=true; CORE_MISSING="$CORE_MISSING rtl_fm"; }
command -v multimon-ng &> /dev/null || { MISSING_CORE=true; CORE_MISSING="$CORE_MISSING multimon-ng"; }
command -v sox &> /dev/null || { MISSING_CORE=true; CORE_MISSING="$CORE_MISSING sox"; }

if $MISSING_CORE; then
    print_block_top
    print_block_row "STATUS" "FAILED"
    print_block_mid
    print_block_row "MISSING" "Critical tools:$CORE_MISSING"
    print_block_row "ACTION" "Install required toolchain and retry"
    print_block_bot
    exit 1
fi

print_block_top
print_block_row "STATUS" "All dependencies verified"
print_block_row "TOOLS" "rtl_fm, multimon-ng, sox"
print_block_row "SDR INDEX" "$RTL_SDR_INDEX (rtl_fm -d)"
print_block_bot

if ! command -v play &> /dev/null && ! command -v paplay &> /dev/null && ! command -v pw-play &> /dev/null && ! command -v aplay &> /dev/null; then
    echo -e "\n\033[2m[!] NOTICE: Audio playback disabled (paplay, pw-play, play, aplay not found)\033[0m"
    echo -e "\033[2m[!] Custom alert/eom WAV sounds will not be played\033[0m\n"
fi

if [ ! -f "$ALERT_WAV" ]; then
    echo -e "\033[1;33m[!] NOTICE: Alert sound WAV not found at: $ALERT_WAV\033[0m"
    echo -e "\033[1;33m[!] Place a WAV file there or update ALERT_WAV path in the script\033[0m\n"
fi
if [ ! -f "$EOM_WAV" ]; then
    echo -e "\033[1;33m[!] NOTICE: EOM sound WAV not found at: $EOM_WAV\033[0m"
    echo -e "\033[1;33m[!] Place a WAV file there or update EOM_WAV path in the script\033[0m\n"
fi

AVAILABLE_KB=$(df "$SAVE_DIR" --output=avail 2>/dev/null | tail -1 | tr -d ' ')
MIN_REQUIRED_KB=$(( (PRE_ROLL_BYTES * 10) / 1024 ))
if [ -n "$AVAILABLE_KB" ] && [ "$AVAILABLE_KB" -lt "$MIN_REQUIRED_KB" ]; then
    print_block_top
    print_block_row "STATUS" "INSUFFICIENT DISK SPACE"
    print_block_mid
    print_block_row "AVAILABLE" "${AVAILABLE_KB}KB free"
    print_block_row "REQUIRED" "~${MIN_REQUIRED_KB}KB minimum"
    print_block_row "ACTION" "Free up disk space and retry"
    print_block_bot
    exit 1
fi

select_state
load_state_data "$SELECTED_STATE" || exit 1

HAS_TRANSMITTERS=false
[ ${#TRANSMITTERS[@]} -gt 0 ] && HAS_TRANSMITTERS=true

if $HAS_TRANSMITTERS; then
    select_county
    select_transmitter || exit 1
    FREQUENCY=$(get_frequency_from_callsign "$SELECTED_CALL")
else
    clear
    print_header "NOAA WEATHER RADIO TRANSMITTER DATA"
    print_block_top
    print_block_row "STATUS" "NO NOAA WEATHER RADIO TRANSMITTERS"
    print_block_mid
    print_block_row "STATE" "$SELECTED_STATE_NAME"
    print_block_row "FILE" "$(basename "$SELECTED_STATE").txt"
    print_block_mid
    print_block_row "INFO" "This state/territory has no NWR transmitter data"
    print_block_row "ACTION" "Select a different state to continue"
    print_block_bot
    echo ""
    echo -e "\033[1;33mNote: Consider running with ALL COUNTIES mode on a nearby state.\033[0m"
    sleep 3
    cleanup
fi

echo ""

while true; do
    echo -ne "  \033[1;36mWould you like audio for alerts enabled? [Y/n] \033[0m"
    read -r AUDIO_RESPONSE

    AUDIO_RESPONSE="${AUDIO_RESPONSE#"${AUDIO_RESPONSE%%[![:space:]]*}"}"
    AUDIO_RESPONSE="${AUDIO_RESPONSE%"${AUDIO_RESPONSE##*[![:space:]]}"}"
    AUDIO_RESPONSE="${AUDIO_RESPONSE:0:5}"
    AUDIO_RESPONSE="${AUDIO_RESPONSE^^}"

    case "$AUDIO_RESPONSE" in
        [Yy]|[Yy][Ee][Ss]|"")
            ENABLE_AUDIO=true
            break
            ;;
        [Nn]|[Nn][Oo])
            ENABLE_AUDIO=false
            break
            ;;
        *)
            echo -e "\033[1;31m[ERROR] Invalid input: '$AUDIO_RESPONSE'\033[0m" >&2
            echo -e "\033[2mPlease enter Y or N (default: Y)\033[0m" >&2
            echo "" >&2
            continue
            ;;
    esac
done

echo ""

if $ENABLE_AUDIO; then
    while true; do
        echo -ne "  \033[1;36mDo you want to enable test alarm for test codes? [RWT - RMT - NPT - DMO] [y/N] \033[0m"
        read -r TEST_TONE_RESPONSE

        TEST_TONE_RESPONSE="${TEST_TONE_RESPONSE#"${TEST_TONE_RESPONSE%%[![:space:]]*}"}"
        TEST_TONE_RESPONSE="${TEST_TONE_RESPONSE%"${TEST_TONE_RESPONSE##*[![:space:]]}"}"
        TEST_TONE_RESPONSE="${TEST_TONE_RESPONSE:0:5}"
        TEST_TONE_RESPONSE="${TEST_TONE_RESPONSE^^}"

        case "$TEST_TONE_RESPONSE" in
            [Yy]|[Yy][Ee][Ss])
                ENABLE_TEST_TONES=true
                break
                ;;
            [Nn]|[Nn][Oo]|"")
                ENABLE_TEST_TONES=false
                break
                ;;
            *)
                echo -e "\033[1;31m[ERROR] Invalid input: '$TEST_TONE_RESPONSE'\033[0m" >&2
                echo -e "\033[2mPlease enter Y or N (default: N)\033[0m" >&2
                echo "" >&2
                continue
                ;;
        esac
    done
else
    echo -e "  \033[2m[Test alarm skipped — audio is disabled]\033[0m"
    ENABLE_TEST_TONES=false
fi

clear
CURRENT_TIME=$(date +"%m/%d/%Y %I:%M:%S %p %Z")

if [ -n "$USB_HID" ] && [ -n "$USB_DESCRIPTION" ]; then
    HW_INFO="$USB_HID ($USB_DESCRIPTION)"
elif [ -n "$USB_HID" ]; then
    HW_INFO="$USB_HID"
else
    HW_INFO="Device Index: $RTL_SDR_INDEX"
fi

print_block_top
print_block_row "HARDWARE" "$HW_INFO"
print_block_row "STATION" "$SOURCE_ID"
if $MONITOR_ALL; then
    print_block_row "TARGET" "ALL $(echo "$SELECTED_STATE_NAME" | tr '[:lower:]' '[:upper:]') COUNTIES"
else
    print_block_row "TARGET" "$SELECTED_COUNTY ($SELECTED_FIPS)"
fi
print_block_row "PRE-ROLL" "${PRE_ROLL_SECONDS}s lookback buffer"

if $ENABLE_AUDIO; then
    if $ENABLE_TEST_TONES; then
        print_block_row "TEST ALARM" "ENABLED"
    else
        print_block_row "TEST ALARM" "DISABLED"
    fi
else
    print_block_row "AUDIO" "DISABLED"
fi

print_block_mid
echo -e "\033[1;36m│\033[0m \033[2mMonitoring for localized SAME/EAS data bursts...\033[0m"
echo -e "\033[1;36m│\033[0m \033[2mStarted: $CURRENT_TIME\033[0m"
print_block_bot

info_log "Pre-roll: ${PRE_ROLL_SECONDS}s | Max standby: ${MAX_STANDBY_SECONDS}s | EOM timeout: ${EOM_TIMEOUT_SECONDS}s"
if $MONITOR_ALL; then
    info_log "Mode: ALL $(echo "$SELECTED_STATE_NAME" | tr '[:lower:]' '[:upper:]') counties — any matching FIPS will trigger"
fi
info_log "Audio playback: $([ "$ENABLE_AUDIO" = true ] && echo 'ENABLED' || echo 'DISABLED')"
if $ENABLE_AUDIO; then
    if $ENABLE_TEST_TONES; then
        info_log "Test alarm ENABLED: Test codes (RWT/RMT/NPT/DMO) will trigger alert sounds and captures"
    else
        info_log "Test alarm DISABLED: Test codes (RWT/RMT/NPT/DMO) will be silently ignored"
    fi
fi
info_log "Date organization: ENABLED — alerts saved to YYYY/MM/DD subdirectories"
info_log "Alert sound: $ALERT_WAV $( [ -f "$ALERT_WAV" ] && echo "(found)" || echo "(not found)" )"
info_log "EOM sound: $EOM_WAV $( [ -f "$EOM_WAV" ] && echo "(found)" || echo "(not found)" )"
echo ""

# ======================================================
# PRE-ROLL BUFFER ARCHITECTURE
# ======================================================
rm -f "$AUDIO_FIFO"
mkfifo "$AUDIO_FIFO"

# ======================================================
# DRAIN PROCESS (Writes FIFO to live buffer)
# ======================================================
while [ ! -p "$AUDIO_FIFO" ]; do sleep 0.1; done
(
    while true; do
        cat "$AUDIO_FIFO" >> "$LIVE_BUFFER"
    done
) &
DRAIN_PID=$!
echo "$DRAIN_PID" > "$DRAIN_PID_FILE"
info_log "Continuous recording drain started (PID: $DRAIN_PID)"

# ======================================================
# BUFFER MANAGER (Caps buffer size during standby)
# ======================================================
(
    while true; do
        sleep 5
        CURRENT_STATE=""
        if [ -f "$STATE_FILE" ]; then
            CURRENT_STATE=$(cat "$STATE_FILE" 2>/dev/null || echo "0")
        fi

        if [ "$CURRENT_STATE" = "0" ]; then
            if [ -f "$LIVE_BUFFER" ]; then
                SIZE=$(stat -c %s "$LIVE_BUFFER" 2>/dev/null || stat -f %z "$LIVE_BUFFER" 2>/dev/null || echo 0)
                SAFE_TRUNCATION_THRESHOLD=$((MAX_STANDBY_BYTES + PRE_ROLL_BYTES + 102400))
                if [ "$SIZE" -gt "$SAFE_TRUNCATION_THRESHOLD" ]; then
                    : > "$LIVE_BUFFER"
                fi
            fi
        fi
    done
) &
BUFFER_MGR_PID=$!
echo "$BUFFER_MGR_PID" > "$BUFFER_MGR_PID_FILE"
info_log "Buffer manager started (PID: $BUFFER_MGR_PID)"

# ======================================================
# PROCESS WATCHDOG — Health Check & Auto-Restart
# ======================================================
(
    while true; do
        sleep 10

        DRAIN_PID_CHECK=$(cat "$DRAIN_PID_FILE" 2>/dev/null || echo "")
        if [ -n "$DRAIN_PID_CHECK" ] && ! kill -0 "$DRAIN_PID_CHECK" 2>/dev/null; then
            echo -e "\033[1;31m[WATCHDOG] Drain process (PID: $DRAIN_PID_CHECK) died — restarting...\033[0m"
            if [ -p "$AUDIO_FIFO" ]; then
                (
                    while true; do
                        cat "$AUDIO_FIFO" >> "$LIVE_BUFFER"
                    done
                ) &
                NEW_PID=$!
                echo "$NEW_PID" > "$DRAIN_PID_FILE"
                echo -e "\033[1;32m[WATCHDOG] Drain process restarted (PID: $NEW_PID)\033[0m"
            fi
        fi

        BUF_PID_CHECK=$(cat "$BUFFER_MGR_PID_FILE" 2>/dev/null || echo "")
        if [ -n "$BUF_PID_CHECK" ] && ! kill -0 "$BUF_PID_CHECK" 2>/dev/null; then
            echo -e "\033[1;31m[WATCHDOG] Buffer manager (PID: $BUF_PID_CHECK) died — restarting...\033[0m"
            (
                while true; do
                    sleep 5
                    CURRENT_STATE=""
                    if [ -f "$STATE_FILE" ]; then
                        CURRENT_STATE=$(cat "$STATE_FILE" 2>/dev/null || echo "0")
                    fi

                    if [ "$CURRENT_STATE" = "0" ]; then
                        if [ -f "$LIVE_BUFFER" ]; then
                            SIZE=$(stat -c %s "$LIVE_BUFFER" 2>/dev/null || stat -f %z "$LIVE_BUFFER" 2>/dev/null || echo 0)
                            SAFE_TRUNCATION_THRESHOLD=$((MAX_STANDBY_BYTES + PRE_ROLL_BYTES + 102400))
                            if [ "$SIZE" -gt "$SAFE_TRUNCATION_THRESHOLD" ]; then
                                : > "$LIVE_BUFFER"
                            fi
                        fi
                    fi
                done
            ) &
            NEW_PID=$!
            echo "$NEW_PID" > "$BUFFER_MGR_PID_FILE"
            echo -e "\033[1;32m[WATCHDOG] Buffer manager restarted (PID: $NEW_PID)\033[0m"
        fi
    done
) &
WATCHDOG_PID=$!
echo "$WATCHDOG_PID" > "$WATCHDOG_PID_FILE"
info_log "Process watchdog started (PID: $WATCHDOG_PID) — checking every 10s"

# ======================================================
# DISK SPACE MONITOR — Runtime Warning at 20% Remaining
# ======================================================
(
    while true; do
        sleep 30
        AVAIL_KB=$(df "$SAVE_DIR" --output=avail 2>/dev/null | tail -1 | tr -d ' ')
        TOTAL_KB=$(df "$SAVE_DIR" --output=size 2>/dev/null | tail -1 | tr -d ' ')

        if [ -n "$AVAIL_KB" ] && [ -n "$TOTAL_KB" ] && [ "$TOTAL_KB" -gt 0 ]; then
            REMAINING_PERCENT=$(( (AVAIL_KB * 100) / TOTAL_KB ))

            if [ "$REMAINING_PERCENT" -le "$DISK_WARNING_THRESHOLD" ]; then
                echo ""
                print_block_top
                print_block_row "DISK WARNING" "Only ${REMAINING_PERCENT}% space remaining"
                print_block_mid
                print_block_row "FREE" "${AVAIL_KB}KB"
                print_block_row "THRESHOLD" "${DISK_WARNING_THRESHOLD}% minimum"
                print_block_row "STORAGE" "$SAVE_DIR"
                print_block_mid
                print_block_row "ACTION" "Clear old alert captures or expand storage"
                print_block_bot
                echo ""

                echo "$(date): DISK WARNING — ${REMAINING_PERCENT}% remaining (${AVAIL_KB}KB free)" >> "$DEBUG_LOG"
            fi
        fi
    done
) &
DISK_MON_PID=$!
echo "$DISK_MON_PID" > "$DISK_MON_PID_FILE"
info_log "Disk space monitor started (PID: $DISK_MON_PID) — checking every 30s"
echo ""

# ======================================================
# RTL-SDR DEVICE MONITOR — Robust Disconnection Detection
# ======================================================
ORIGINAL_USB_HID="$USB_HID"

(
    consecutive_failures=0
    required_failures=2

    while true; do
        sleep 3

        current_usb_output=$(lsusb 2>/dev/null)

        if echo "$current_usb_output" | grep -q "$ORIGINAL_USB_HID"; then
            consecutive_failures=0
            continue
        fi

        ((consecutive_failures++))

        if [ $consecutive_failures -ge $required_failures ]; then
            echo ""
            print_block_top
            print_block_row "HARDWARE EVENT" "RTL-SDR DISCONNECTED"
            print_block_mid
            print_block_row "HID" "$ORIGINAL_USB_HID"
            print_block_row "STATUS" "Device removed or USB connection lost"
            print_block_row "ACTION" "Reconnect device and restart script"
            print_block_bot
            echo ""

            echo "2" > "$STATE_FILE"
            echo "1" > "$DEVICE_DISCONN_FLAG"

            pkill -f "rtl_fm.*$FREQUENCY" 2>/dev/null

            sleep 1
            exit 0
        fi
    done
) &
DEVICE_MON_PID=$!
echo "$DEVICE_MON_PID" > "$DEVICE_MON_PID_FILE"
info_log "RTL-SDR device monitor started (PID: $DEVICE_MON_PID) — checking every 3s"
echo ""

# ======================================================
# MAIN DECODER LOOP
# ======================================================
RTL_FM_CMD="rtl_fm -d $RTL_SDR_INDEX"
MM_RESTART_FLAG="$TEMP_DATA_DIR/mm_restart"
rm -f "$MM_RESTART_FLAG"

eval "$RTL_FM_CMD -f $FREQUENCY -M fm -s 22050 -g $GAIN -l $SQUELCH -E deemp -F $FIR -p $PPM_CORRECTION" 2>"$RTL_ERR_LOG" | \
    tee "$AUDIO_FIFO" | \
    (
        while true; do
            if [ -f "$DEVICE_DISCONN_FLAG" ] && [ "$(cat "$DEVICE_DISCONN_FLAG" 2>/dev/null)" = "1" ]; then
                exit 1
            fi

            multimon-ng -t raw -a EAS - 2>&1 &
            MM_PID=$!
            while kill -0 "$MM_PID" 2>/dev/null; do
                if [ -f "$DEVICE_DISCONN_FLAG" ] && [ "$(cat "$DEVICE_DISCONN_FLAG" 2>/dev/null)" = "1" ]; then
                    kill "$MM_PID" 2>/dev/null
                    wait "$MM_PID" 2>/dev/null
                    exit 164
                fi

                if [ -f "$MM_RESTART_FLAG" ]; then
                    kill "$MM_PID" 2>/dev/null
                    wait "$MM_PID" 2>/dev/null
                    rm -f "$MM_RESTART_FLAG"
                    break
                fi

                sleep 0.3
            done
            sleep 0.2
        done
    ) | while read -r line; do

    if [ -f "$DEVICE_DISCONN_FLAG" ] && [ "$(cat "$DEVICE_DISCONN_FLAG" 2>/dev/null)" = "1" ]; then
        exit 164
    fi

    if [[ "$line" != *"EAS:"* && "$line" != *"EOM"* && "$line" != *"NNNN"* ]]; then
        continue
    fi

    ACTIVE=$(cat "$STATE_FILE" 2>/dev/null || echo "0")
    FIPS_MATCH=false
    IS_TEST_ALERT=false
    declare -A MATCHED_COUNTIES
    MATCHED_COUNTIES=()
    EVENT_CODE="UNKNOWN"
    ALL_FIPS_CODES=()

    line="${line%$'\r'}"

    if [[ "$line" == *"EAS:"* ]]; then
        echo "[Decoder Burst Sync]: $line"
    fi

    if [[ "$line" == *"EAS:"* && "$ACTIVE" == "0" ]]; then

        ORIGINAL_LINE="$line"

        for code in "${!HAZARDS[@]}"; do
            if [[ "$ORIGINAL_LINE" == *"-${code}-"* ]]; then
                EVENT_CODE="$code"
                break
            fi
        done

        if is_test_code "$EVENT_CODE"; then
            IS_TEST_ALERT=true
        fi

        IFS='-+' read -ra PARTS <<< "$ORIGINAL_LINE"
        for part in "${PARTS[@]}"; do
            if [[ "$part" =~ ^[0-9]{6}$ ]]; then
                ALL_FIPS_CODES+=("$part")
            fi
        done

        if $MONITOR_ALL; then
            for county in "${!STATE_COUNTIES[@]}"; do
                fips="${STATE_COUNTIES[$county]}"
                fips_norm=$(normalize_fips "$fips")
                if [[ "$ORIGINAL_LINE" == *"$fips_norm"* ]] || [[ "$ORIGINAL_LINE" == *"$fips"* ]]; then
                    FIPS_MATCH=true
                    MATCHED_COUNTIES["$county"]="$fips"
                fi
            done
            if ! $FIPS_MATCH; then
                for fips in "${ALL_FIPS_CODES[@]}"; do
                    if [[ "$fips" == "000000" || "$fips" == "000001" ]]; then
                        MATCHED_COUNTIES["NATIONAL_ALERT"]="000000"
                        FIPS_MATCH=true
                        break
                    fi
                done
            fi
        else
            SELECTED_FIPS_NORM=$(normalize_fips "$SELECTED_FIPS")
            for fips in "${ALL_FIPS_CODES[@]}"; do
                fips_norm=$(normalize_fips "$fips")
                if [ "$fips_norm" = "$SELECTED_FIPS_NORM" ]; then
                    MATCHED_COUNTIES["$SELECTED_COUNTY"]="$fips"
                    FIPS_MATCH=true
                    break
                fi
            done

            if ! $FIPS_MATCH; then
                for fips in "${ALL_FIPS_CODES[@]}"; do
                    if [[ "$fips" == "000000" || "$fips" == "000001" ]]; then
                        MATCHED_COUNTIES["NATIONAL_ALERT"]="000000"
                        FIPS_MATCH=true
                        break
                    fi
                done
            fi
        fi

        if $FIPS_MATCH; then
            echo "1" > "$STATE_FILE"
            INTERCEPT_TZ=$(date +"%m/%d/%Y %I:%M:%S %p %Z")

            IS_NATIONAL_ALERT=false
            for fips in "${ALL_FIPS_CODES[@]}"; do
                if [[ "$fips" == "000000" || "$fips" == "000001" ]]; then
                    IS_NATIONAL_ALERT=true
                    break
                fi
            done

            if ! $IS_TEST_ALERT || $IS_NATIONAL_ALERT || $ENABLE_TEST_TONES; then
                play_custom_wav "$ALERT_WAV"
                echo "true" > "$ALERT_PLAY_SOUNDS_FILE"
            else
                echo "false" > "$ALERT_PLAY_SOUNDS_FILE"
            fi

            CURRENT_BUFFER_SIZE=$(stat -c %s "$LIVE_BUFFER" 2>/dev/null || stat -f %z "$LIVE_BUFFER" 2>/dev/null || echo 0)
            ALERT_START_OFFSET=$((CURRENT_BUFFER_SIZE - PRE_ROLL_BYTES))
            if [ "$ALERT_START_OFFSET" -lt 0 ]; then
                ALERT_START_OFFSET=0
            fi
            echo "$ALERT_START_OFFSET" > "$OFFSET_FILE"

            CLEAN_EAS_STRING=$(echo "$ORIGINAL_LINE" | sed 's/.*\(EAS:.*\)/\1/')
            echo "$CLEAN_EAS_STRING" > "$DECODER_LOG"

            HAZARD="${HAZARDS[$EVENT_CODE]:-UNKNOWN EVENT}"
            TYPE_DISPLAY="$HAZARD"

            COUNTY_DISPLAY=""
            for county in "${!MATCHED_COUNTIES[@]}"; do
                fips="${MATCHED_COUNTIES[$county]}"
                if [[ "$county" == "NATIONAL_ALERT" ]]; then
                    county_display="NATIONAL (All U.S. Territories)"
                else
                    county_display=$(echo "$county" | tr '[:upper:]' '[:lower:]' | sed 's/\b\(.\)/\u\1/g' | tr '_' ' ')
                fi
                if [ -z "$COUNTY_DISPLAY" ]; then
                    COUNTY_DISPLAY="$county_display ($fips)"
                else
                    COUNTY_DISPLAY="$COUNTY_DISPLAY | $county_display ($fips)"
                fi
            done

            echo ""
            print_block_top
            print_block_row "ALERT" "$TYPE_DISPLAY"
            print_block_row "COUNTY" "$COUNTY_DISPLAY"
            print_block_row "INTERCEPTED" "$INTERCEPT_TZ"
            print_block_row "DECODER" "$CLEAN_EAS_STRING"
            print_block_mid
            print_block_row "PRE-ROLL" "Capturing full transmission (${PRE_ROLL_SECONDS}s lookback)"
            print_block_row "BUFFER OFFSET" "$ALERT_START_OFFSET bytes"
            print_block_bot
            echo ""

            echo "$TYPE_DISPLAY" > "$ALERT_TYPE_FILE"
            echo "$HAZARD" > "$ALERT_HAZARD_FILE"
            echo "$IS_TEST_ALERT" > "$ALERT_IS_TEST_FILE"
            echo "$INTERCEPT_TZ" > "$ALERT_INTERCEPT_FILE"
            echo "$COUNTY_DISPLAY" > "$ALERT_COUNTY_FILE"
            echo "$CLEAN_EAS_STRING" > "$ALERT_DECODER_FILE"
            cp "$DECODER_LOG" "$ALERT_DECODER_FILE" 2>/dev/null
            echo "$ALERT_START_OFFSET" > "$ALERT_OFFSET_FILE"
            echo "pending" > "$ALERT_EOM_STATUS_FILE"

            (
                sleep $EOM_TIMEOUT_SECONDS
                if [ -f "$STATE_FILE" ] && [ "$(cat "$STATE_FILE")" == "1" ]; then
                    echo "missed" > "$ALERT_EOM_STATUS_FILE"

                    sleep 1
                    cp "$LIVE_BUFFER" "$SNAPSHOT_RAW" 2>/dev/null
                    info_log "Timeout buffer snapshot: $(stat -c %s "$SNAPSHOT_RAW" 2>/dev/null || stat -f %z "$SNAPSHOT_RAW" 2>/dev/null || echo 0) bytes"

                    echo "0" > "$STATE_FILE"
                    touch "$MM_RESTART_FLAG"

                    (
                        sleep 1

                        _TYPE_DISPLAY=$(cat "$ALERT_TYPE_FILE" 2>/dev/null || echo "UNKNOWN")
                        _HAZARD=$(cat "$ALERT_HAZARD_FILE" 2>/dev/null || echo "UNKNOWN EVENT")
                        _IS_TEST=$(cat "$ALERT_IS_TEST_FILE" 2>/dev/null || echo "false")
                        _INTERCEPT_TIME=$(cat "$ALERT_INTERCEPT_FILE" 2>/dev/null || echo "")
                        _COUNTY_DISPLAY=$(cat "$ALERT_COUNTY_FILE" 2>/dev/null || echo "")
                        _DECODER_OUTPUT=$(cat "$ALERT_DECODER_FILE" 2>/dev/null || echo "unavailable")
                        _ALERT_START_OFFSET=$(cat "$ALERT_OFFSET_FILE" 2>/dev/null || echo 0)
                        _EOM_STATUS="missed"

                        SAFE_NAME=$(echo "$_HAZARD" | sed 's/[^A-Za-z0-9_-]/_/g; s/__*/_/g; s/^_//; s/_$//')

                        if [ "$_IS_TEST" = "true" ]; then
                            ALERT_SAVE_DIR="$SAVE_DIR/tests"
                        else
                            ALERT_SAVE_DIR="$SAVE_DIR"
                        fi

                        YEAR=$(date +%Y)
                        MONTH_DAY=$(date +%m_%d)
                        DATE_DIR="$ALERT_SAVE_DIR/$YEAR/$MONTH_DAY"
                        mkdir -p "$DATE_DIR"

                        TIMESTAMP_HM=$(date +%H%M)
                        OUTPUT_WAV="$DATE_DIR/${SAFE_NAME}_${TIMESTAMP_HM}.wav"
                        OUTPUT_TXT="$DATE_DIR/${SAFE_NAME}_${TIMESTAMP_HM}.txt"

                        TOTAL_SIZE=$(stat -c %s "$SNAPSHOT_RAW" 2>/dev/null || stat -f %z "$SNAPSHOT_RAW" 2>/dev/null || echo 0)

                        if [ "$TOTAL_SIZE" -le 0 ] || [ ! -f "$SNAPSHOT_RAW" ]; then
                            echo "[ERROR] Snapshot missing or empty at EOM timeout (${TOTAL_SIZE} bytes)" >&2
                            CAPTURED_SECONDS="0"
                            WRITE_OK=false
                        else
                            EXTRACT_BYTES=$((TOTAL_SIZE - _ALERT_START_OFFSET))

                            if [ "$EXTRACT_BYTES" -lt 0 ]; then
                                echo "[WARNING] Buffer shrank at timeout! Offset=$_ALERT_START_OFFSET, Total=$TOTAL_SIZE. Adjusting to start from beginning." >&2
                                _ALERT_START_OFFSET=0
                                EXTRACT_BYTES=$TOTAL_SIZE
                                CAPTURED_SECONDS="Partial (buffer regression detected)"
                            else
                                CAPTURED_SECONDS="N/A"
                                WRITE_OK=true
                            fi
                        fi

                        if [ "$WRITE_OK" = true ] && [ "$EXTRACT_BYTES" -gt 0 ] && [ -s "$SNAPSHOT_RAW" ]; then
                            BLOCK_SIZE=$BYTES_PER_SECOND
                            SKIP_BLOCKS=$((_ALERT_START_OFFSET / BLOCK_SIZE))
                            COUNT_BLOCKS=$((EXTRACT_BYTES / BLOCK_SIZE + 1))

                            dd if="$SNAPSHOT_RAW" of="$EXTRACT_RAW" bs="$BLOCK_SIZE" skip="$SKIP_BLOCKS" count="$COUNT_BLOCKS" 2>>"$EXTRACT_ERR_LOG"
                            DD_RESULT=$?

                            if [ "$DD_RESULT" -eq 0 ] && [ -s "$EXTRACT_RAW" ]; then
                                sox -t raw -r 22050 -c 1 -e signed-integer -b 16 "$EXTRACT_RAW" "$OUTPUT_WAV" 2>>"$EXTRACT_ERR_LOG"
                                SOX_RESULT=$?

                                if [ "$SOX_RESULT" -eq 0 ] && [ -f "$OUTPUT_WAV" ] && [ -s "$OUTPUT_WAV" ]; then
                                    CAPTURED_SECONDS=$(awk "BEGIN {printf \"%.1f\", $EXTRACT_BYTES / $BYTES_PER_SECOND}")
                                fi
                            fi
                        fi

                        [ -z "$_DECODER_OUTPUT" ] && _DECODER_OUTPUT="Decoder payload unavailable"

                        cat > "$OUTPUT_TXT" << METADATA_EOF
╔════════════════════════════════════════════════════════════╗
║                       ALERT CAPTURE                        ║
╠════════════════════════════════════════════════════════════╣
║ HARDWARE    │ $HW_INFO
║ TARGET      │ $_COUNTY_DISPLAY
║ STATION     │ $SOURCE_ID
╠════════════════════════════════════════════════════════════╣
║                       ALERT DETAILS                        ║
╠════════════════════════════════════════════════════════════╣
║ Type        │ $_TYPE_DISPLAY
║ Intercept   │ $_INTERCEPT_TIME
║ Duration    │ ${CAPTURED_SECONDS}s (${PRE_ROLL_SECONDS}s pre-roll)
║ Decoder     │ $_DECODER_OUTPUT
║ EOM Message │ Missed (Timeout)
╚════════════════════════════════════════════════════════════╝
METADATA_EOF

                        echo ""
                        print_block_top
                        print_block_row "DURATION" "${CAPTURED_SECONDS}s (${PRE_ROLL_SECONDS}s pre-roll)"
                        print_block_row "EOM" "Missed (Timeout)"
                        if [ -f "$OUTPUT_WAV" ] && [ -s "$OUTPUT_WAV" ]; then
                            print_block_row "AUDIO" "$OUTPUT_WAV"
                        fi
                        print_block_row "METADATA" "$OUTPUT_TXT"
                        print_block_bot
                        echo ""

                    ) &

                fi
            ) &
            TIMEOUT_PID=$!
            echo "$TIMEOUT_PID" > "$TEMP_DATA_DIR/timeout.pid"
            info_log "Alert timeout watchdog started (PID: $TIMEOUT_PID)"
        fi
    fi

    if [[ ( "$line" == *"EOM"* || "$line" == *"NNNN"* ) && "$ACTIVE" == "1" ]]; then

        sleep 2

        if [ -n "${TIMEOUT_PID:-}" ]; then
            kill "$TIMEOUT_PID" 2>/dev/null
            TIMEOUT_PID=""
        fi
        if [ -f "$TEMP_DATA_DIR/timeout.pid" ]; then
            TIMEOUT_PID_FROM_FILE=$(cat "$TEMP_DATA_DIR/timeout.pid" 2>/dev/null)
            if [ -n "$TIMEOUT_PID_FROM_FILE" ]; then
                kill "$TIMEOUT_PID_FROM_FILE" 2>/dev/null
                rm -f "$TEMP_DATA_DIR/timeout.pid"
            fi
        fi

        sleep 1
        cp "$LIVE_BUFFER" "$SNAPSHOT_RAW" 2>/dev/null
        info_log "EOM buffer snapshot: $(stat -c %s "$SNAPSHOT_RAW" 2>/dev/null || stat -f %z "$SNAPSHOT_RAW" 2>/dev/null || echo 0) bytes"

        echo "0" > "$STATE_FILE"
        touch "$MM_RESTART_FLAG"

        _PLAY_SOUNDS=$(cat "$ALERT_PLAY_SOUNDS_FILE" 2>/dev/null || echo "false")
        if [ "$_PLAY_SOUNDS" = "true" ]; then
            play_custom_wav "$EOM_WAV"
        fi

        (
            sleep 3

            _TYPE_DISPLAY=$(cat "$ALERT_TYPE_FILE" 2>/dev/null || echo "UNKNOWN")
            _HAZARD=$(cat "$ALERT_HAZARD_FILE" 2>/dev/null || echo "UNKNOWN EVENT")
            _IS_TEST=$(cat "$ALERT_IS_TEST_FILE" 2>/dev/null || echo "false")
            _INTERCEPT_TIME=$(cat "$ALERT_INTERCEPT_FILE" 2>/dev/null || echo "")
            _COUNTY_DISPLAY=$(cat "$ALERT_COUNTY_FILE" 2>/dev/null || echo "")
            _DECODER_OUTPUT=$(cat "$ALERT_DECODER_FILE" 2>/dev/null || echo "unavailable")
            _ALERT_START_OFFSET=$(cat "$ALERT_OFFSET_FILE" 2>/dev/null || echo 0)
            _EOM_STATUS=$(cat "$ALERT_EOM_STATUS_FILE" 2>/dev/null || echo "received")

            if [ -z "$_EOM_STATUS" ] || [ "$_EOM_STATUS" = "pending" ]; then
                _EOM_STATUS="received"
            fi

            SAFE_NAME=$(echo "$_HAZARD" | sed 's/[^A-Za-z0-9_-]/_/g; s/__*/_/g; s/^_//; s/_$//')

            if [ "$_IS_TEST" = "true" ]; then
                ALERT_SAVE_DIR="$SAVE_DIR/tests"
            else
                ALERT_SAVE_DIR="$SAVE_DIR"
            fi

            YEAR=$(date +%Y)
            MONTH_DAY=$(date +%m_%d)
            DATE_DIR="$ALERT_SAVE_DIR/$YEAR/$MONTH_DAY"
            mkdir -p "$DATE_DIR"

            TIMESTAMP_HM=$(date +%H%M)
            OUTPUT_WAV="$DATE_DIR/${SAFE_NAME}_${TIMESTAMP_HM}.wav"
            OUTPUT_TXT="$DATE_DIR/${SAFE_NAME}_${TIMESTAMP_HM}.txt"

            TOTAL_SIZE=$(stat -c %s "$SNAPSHOT_RAW" 2>/dev/null || stat -f %z "$SNAPSHOT_RAW" 2>/dev/null || echo 0)

            if [ "$TOTAL_SIZE" -le 0 ] || [ ! -f "$SNAPSHOT_RAW" ]; then
                echo "[ERROR] Snapshot missing or empty at EOM (${TOTAL_SIZE} bytes)" >&2
                _EOM_STATUS="missed_buffer_empty"
                CAPTURED_SECONDS="0"
                WRITE_OK=false
            else
                EXTRACT_BYTES=$((TOTAL_SIZE - _ALERT_START_OFFSET))

                if [ "$EXTRACT_BYTES" -lt 0 ]; then
                    echo "[WARNING] Buffer shrank! Offset=$_ALERT_START_OFFSET, Total=$TOTAL_SIZE. Adjusting to start from beginning." >&2
                    _ALERT_START_OFFSET=0
                    EXTRACT_BYTES=$TOTAL_SIZE
                    CAPTURED_SECONDS="Partial (buffer regression detected)"
                else
                    CAPTURED_SECONDS="N/A"
                    WRITE_OK=true
                fi
            fi

            if [ "$WRITE_OK" = true ] && [ "$EXTRACT_BYTES" -gt 0 ] && [ -s "$SNAPSHOT_RAW" ]; then
                BLOCK_SIZE=$BYTES_PER_SECOND
                SKIP_BLOCKS=$((_ALERT_START_OFFSET / BLOCK_SIZE))
                COUNT_BLOCKS=$((EXTRACT_BYTES / BLOCK_SIZE + 1))

                dd if="$SNAPSHOT_RAW" of="$EXTRACT_RAW" bs="$BLOCK_SIZE" skip="$SKIP_BLOCKS" count="$COUNT_BLOCKS" 2>>"$EXTRACT_ERR_LOG"
                DD_RESULT=$?

                if [ "$DD_RESULT" -eq 0 ] && [ -s "$EXTRACT_RAW" ]; then
                    sox -t raw -r 22050 -c 1 -e signed-integer -b 16 "$EXTRACT_RAW" "$OUTPUT_WAV" 2>>"$EXTRACT_ERR_LOG"
                    SOX_RESULT=$?

                    if [ "$SOX_RESULT" -eq 0 ] && [ -f "$OUTPUT_WAV" ] && [ -s "$OUTPUT_WAV" ]; then
                        CAPTURED_SECONDS=$(awk "BEGIN {printf \"%.1f\", $EXTRACT_BYTES / $BYTES_PER_SECOND}")
                    else
                        echo "[ERROR] sox failed to write WAV file" >&2
                        echo "Target: $OUTPUT_WAV" >&2
                        echo "Check: $EXTRACT_ERR_LOG" >&2
                        WRITE_OK=false
                    fi
                else
                    echo "[ERROR] dd failed to extract audio buffer" >&2
                    echo "Result code: $DD_RESULT" >&2
                    echo "Offset: $_ALERT_START_OFFSET, Extract: $EXTRACT_BYTES" >&2
                    echo "Check: $EXTRACT_ERR_LOG" >&2
                    WRITE_OK=false
                fi
            else
                if [ "$WRITE_OK" = false ]; then
                    echo "[ERROR] Cannot extract -- snapshot empty or invalid offset" >&2
                    echo "Offset: $_ALERT_START_OFFSET, Total: $TOTAL_SIZE, Extract: $EXTRACT_BYTES" >&2
                else
                    echo "[INFO] No audio data to extract (short alert or empty buffer)" >&2
                fi
                WRITE_OK=false
            fi

            [ -z "$_DECODER_OUTPUT" ] && _DECODER_OUTPUT="Decoder payload unavailable"

            cat > "$OUTPUT_TXT" << METADATA_EOF
╔════════════════════════════════════════════════════════════╗
║                       ALERT CAPTURE                        ║
╠════════════════════════════════════════════════════════════╣
║ HARDWARE    │ $HW_INFO
║ TARGET      │ $_COUNTY_DISPLAY
║ STATION     │ $SOURCE_ID
╠════════════════════════════════════════════════════════════╣
║                       ALERT DETAILS                        ║
╠════════════════════════════════════════════════════════════╣
║ Type        │ $_TYPE_DISPLAY
║ Intercept   │ $_INTERCEPT_TIME
║ Duration    │ ${CAPTURED_SECONDS}s (${PRE_ROLL_SECONDS}s pre-roll)
║ Decoder     │ $_DECODER_OUTPUT
║ EOM Message │ $([ "$_EOM_STATUS" = "missed" ] && echo "Missed (Timeout)" || echo "Received")
╚════════════════════════════════════════════════════════════╝
METADATA_EOF

            echo ""
            print_block_top
            print_block_row "DURATION" "${CAPTURED_SECONDS}s (${PRE_ROLL_SECONDS}s pre-roll)"
            EOM_DISPLAY="Received"
            if [ "$_EOM_STATUS" = "missed" ] || [ "$_EOM_STATUS" = "missed_buffer_empty" ]; then
                EOM_DISPLAY="Missed (Timeout)"
            fi
            print_block_row "EOM" "$EOM_DISPLAY"
            if [ -f "$OUTPUT_WAV" ] && [ -s "$OUTPUT_WAV" ]; then
                print_block_row "AUDIO" "$OUTPUT_WAV"
            else
                print_block_row "AUDIO" "Not written (metadata only)"
            fi
            print_block_row "METADATA" "$OUTPUT_TXT"
            print_block_bot
            echo ""

        ) &

    fi

done
