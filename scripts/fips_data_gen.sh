#!/bin/bash

# =====================================================================
# Author: DragoLuke
# EAS FIPS PARSER
#  License: GNU General Public License v3.0 (GPL-3.0-or-later)
# ============================================================================
# Downloads FIPS county codes from FCC and generates per-state data files.
# NWR transmitter sections are left as placeholders ("# No transmitter data")
# for manual entry from https://www.weather.gov/nwr/station_listing
# =====================================================================

PROJECT_DIR="$HOME/StormScales"
DATA_DIR="$PROJECT_DIR/media/state_data"
TEMP_DIR="$PROJECT_DIR/media/state_data/parser"
FCC_FIPS_URL="https://transition.fcc.gov/oet/info/maps/census/fips/fips.txt"

CURL_TIMEOUT=30
USER_AGENT="EAS-Monitor-Data-Parser/4.0 (Personal weather monitoring project)"

# Colors
RED='\033[1;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
CYAN='\033[1;36m'
DIM='\033[2m'
RESET='\033[0m'

log_info()    { echo -e "${CYAN}[$(date '+%H:%M:%S')] [INFO]${RESET}    $1"; }
log_success() { echo -e "${GREEN}[$(date '+%H:%M:%S')] [SUCCESS]${RESET} $1"; }
log_error()   { echo -e "${RED}[$(date '+%H:%M:%S')] [ERROR]${RESET}   $1"; }
separator()   { echo -e "${DIM}────────────────────────────────────────────────────────────────────${RESET}"; }

STATES=(
    "AL|Alabama"          "AK|Alaska"           "AZ|Arizona"
    "AR|Arkansas"         "CA|California"       "CO|Colorado"
    "CT|Connecticut"      "DE|Delaware"         "FL|Florida"
    "GA|Georgia"          "HI|Hawaii"           "ID|Idaho"
    "IL|Illinois"         "IN|Indiana"          "IA|Iowa"
    "KS|Kansas"           "KY|Kentucky"         "LA|Louisiana"
    "ME|Maine"            "MD|Maryland"         "MA|Massachusetts"
    "MI|Michigan"         "MN|Minnesota"        "MS|Mississippi"
    "MO|Missouri"         "MT|Montana"          "NE|Nebraska"
    "NV|Nevada"           "NH|New Hampshire"    "NJ|New Jersey"
    "NM|New Mexico"       "NY|New York"         "NC|North Carolina"
    "ND|North Dakota"     "OH|Ohio"             "OK|Oklahoma"
    "OR|Oregon"           "PA|Pennsylvania"     "RI|Rhode Island"
    "SC|South Carolina"   "SD|South Dakota"      "TN|Tennessee"
    "TX|Texas"            "UT|Utah"             "VT|Vermont"
    "VA|Virginia"         "WA|Washington"       "WV|West Virginia"
    "WI|Wisconsin"        "WY|Wyoming"
    "DC|District of Columbia"
)

# =====================================================================
# Get FIPS State Number Prefix
# =====================================================================
get_state_number() {
    case "$1" in
        AL) echo "01" ;; AK) echo "02" ;; AZ) echo "04" ;; AR) echo "05" ;;
        CA) echo "06" ;; CO) echo "08" ;; CT) echo "09" ;; DE) echo "10" ;;
        DC) echo "11" ;; FL) echo "12" ;; GA) echo "13" ;; HI) echo "15" ;;
        ID) echo "16" ;; IL) echo "17" ;; IN) echo "18" ;; IA) echo "19" ;;
        KS) echo "20" ;; KY) echo "21" ;; LA) echo "22" ;; ME) echo "23" ;;
        MD) echo "24" ;; MA) echo "25" ;; MI) echo "26" ;; MN) echo "27" ;;
        MS) echo "28" ;; MO) echo "29" ;; MT) echo "30" ;; NE) echo "31" ;;
        NV) echo "32" ;; NH) echo "33" ;; NJ) echo "34" ;; NM) echo "35" ;;
        NY) echo "36" ;; NC) echo "37" ;; ND) echo "38" ;; OH) echo "39" ;;
        OK) echo "40" ;; OR) echo "41" ;; PA) echo "42" ;; RI) echo "44" ;;
        SC) echo "45" ;; SD) echo "46" ;; TN) echo "47" ;; TX) echo "48" ;;
        UT) echo "49" ;; VT) echo "50" ;; VA) echo "51" ;; WA) echo "53" ;;
        WV) echo "54" ;; WI) echo "55" ;; WY) echo "56" ;;
        *)  echo "00" ;;
    esac
}

# =====================================================================
# Download FIPS County Codes from FCC
# =====================================================================
download_fips_data() {
    local output_file="$TEMP_DIR/fcc_fips_raw.txt"
    log_info "Downloading FIPS county codes from FCC..."
    sleep 2

    if curl -sL --max-time "$CURL_TIMEOUT" \
             -A "$USER_AGENT" \
             -o "$output_file" \
             "$FCC_FIPS_URL" 2>/dev/null; then

        if [ -s "$output_file" ]; then
            local byte_count
            byte_count=$(wc -c < "$output_file")
            log_success "Downloaded FCC FIPS data (${byte_count} bytes)"
            return 0
        else
            log_error "Downloaded file is empty"
            return 1
        fi
    else
        log_error "Failed to download FIPS data from FCC"
        return 1
    fi
}

# =====================================================================
# Parse FIPS data into per-state files
# Filters out state-level codes (XXX00) — only keeps county codes
# =====================================================================
parse_fips_data() {
    local fips_file="$TEMP_DIR/fcc_fips_raw.txt"
    local fips_states_dir="$TEMP_DIR/fips_states"

    mkdir -p "$fips_states_dir"
    rm -f "$fips_states_dir"/*.txt

    awk '
    {
        line = $0
        gsub(/^[[:space:]]+/, "", line)
        n = split(line, parts, /[[:space:]]+/)
        code = parts[1]

        # Must be exactly 5 digits
        if (length(code) != 5) next
        if (code !~ /^[0-9][0-9][0-9][0-9][0-9]$/) next

        # Skip state-level codes (positions 3-5 are "000")
        if (substr(code, 3, 3) == "000") next

        state_prefix = substr(code, 1, 2)
        county_name = ""

        for (i = 2; i <= n; i++) {
            if (parts[i] == "") continue
            county_name = (county_name != "") ? county_name " " parts[i] : parts[i]
        }

        gsub(/[[:space:]]+$/, "", county_name)

        if (length(county_name) >= 3) {
            print code "|" county_name >> "'"$fips_states_dir"'/" state_prefix ".txt"
        }
    }
    ' "$fips_file"

    local count
    count=$(find "$fips_states_dir" -name "*.txt" | wc -l)
    log_success "Parsed FIPS into ${count} state files"
    [ "$count" -gt 0 ] && return 0 || return 1
}

# =====================================================================
# Generate State Data File (FIPS only, NWR placeholder)
# =====================================================================
generate_state_file() {
    local state_code="$1"
    local state_name="$2"
    local state_num_prefix="$3"

    local fips_file="$TEMP_DIR/fips_states/${state_num_prefix}.txt"

    local safe_name
    safe_name=$(echo "$state_name" | tr '[:upper:]' '[:lower:]' | tr ' ' '_' | tr -d '.')
    local output_file="${DATA_DIR}/${safe_name}.txt"

    local county_count=0
    [ -f "$fips_file" ] && [ -s "$fips_file" ] && county_count=$(wc -l < "$fips_file")

    [ "$county_count" -eq 0 ] && return 1

    {
        echo "======================================================================"
        echo "# EAS State Data File: ${state_name^^}"
        echo "# FIPS Generated: $(date '+%Y-%m-%d %H:%M:%S')"
        echo "# State FIPS Prefix: ${state_num_prefix}"
        echo "# Source: https://transition.fcc.gov/oet/info/maps/census/fips/fips.txt"
        echo "======================================================================"
        echo ""
        echo "----------------------------------------------------------------------"
        echo "# ===== COUNTY FIPS CODES ====="
        echo "# Format: COUNTY_NAME|FIPS_CODE"
        echo "----------------------------------------------------------------------"
        echo ""
        awk -F'|' '{print $2 "|" $1}' "$fips_file"
        echo ""
        echo "----------------------------------------------------------------------"
        echo "# ===== NOAA WEATHER RADIO TRANSMITTERS ====="
        echo "# Format: CALLSIGN|FREQUENCY|SITE_NAME"
        echo "# Source: https://www.weather.gov/nwr/station_listing"
        echo "----------------------------------------------------------------------"
        echo ""
        echo "# No transmitter data"
        echo ""
        echo "======================================================================"
    } > "$output_file"

    log_success "${state_name}: ${county_count} counties"
    return 0
}

# =====================================================================
# Generate Manifest
# =====================================================================
generate_manifest() {
    local manifest="$DATA_DIR/_manifest.txt"
    local file_count=0
    local total_counties=0

    {
        echo "======================================================================"
        echo "# EAS State Data Manifest"
        echo "# Generated: $(date '+%Y-%m-%d %H:%M:%S')"
        echo "# Source: FCC FIPS County Codes"
        echo "======================================================================"
        echo ""
        printf "%-28s %-12s %-12s\n" "STATE" "COUNTIES" "TRANSMITTERS"
        echo "----------------------------------------------------------------------"

        for state_entry in "${STATES[@]}"; do
            local code="${state_entry%%|*}" name="${state_entry##*|}"
            local safe_name
            safe_name=$(echo "$name" | tr '[:upper:]' '[:lower:]' | tr ' ' '_' | tr -d '.')

            if [ -f "${DATA_DIR}/${safe_name}.txt" ]; then
                file_count=$((file_count + 1))

                # Count counties (lines with | that aren't comments)
                local county_count=0
                county_count=$(awk -F'|' '/^[^#]/ && NF==2 && $2 ~ /^[0-9]{5}$/ {count++} END {print count+0}' \
                    "${DATA_DIR}/${safe_name}.txt")

                # Transmitters always 0 - parser doesn't populate this
                local tx_count=0

                total_counties=$((total_counties + county_count))

                printf "%-28s %-12s %-12s\n" "${name} (${code})" "${county_count}" "${tx_count}"
            fi
        done

        echo "----------------------------------------------------------------------"
        echo ""
        echo "SUMMARY"
        echo "  State files:        ${file_count}"
        echo "  Total counties:     ${total_counties}"
        echo "  Transmitters:       Manual entry required (FCC data only)"
        echo ""
        echo "======================================================================"
    } > "$manifest"

    log_info "Manifest created (${file_count} files, ${total_counties} counties total)"
}

# =====================================================================
# Cleanup Temporary Files
# =====================================================================
cleanup_temp() {
    log_info "Cleaning up..."
    rm -rf "$TEMP_DIR/fips_states" "$TEMP_DIR/fcc_fips_raw.txt"
    log_info "Done."
}

# =====================================================================
# Main
# =====================================================================
main() {
    mkdir -p "$DATA_DIR" "$TEMP_DIR"

    clear
    separator
    echo "   EAS FIPS PARSER"
    echo "   FIPS: FCC (curl)  |  NWR: Manual entry"
    separator
    echo ""

    # Check dependencies
    command -v curl &>/dev/null || { log_error "curl is required."; exit 1; }
    command -v awk &>/dev/null || { log_error "awk is required."; exit 1; }

    # Step 1: Download and parse FIPS data
    separator
    echo "   STEP 1: FCC FIPS COUNTY CODES"
    separator
    echo ""

    download_fips_data || { log_error "Cannot continue without FIPS data."; exit 1; }
    parse_fips_data || { log_error "FIPS parsing failed."; exit 1; }

    # Step 2: Generate per-state files
    echo ""
    separator
    echo "   STEP 2: GENERATING STATE FILES"
    separator
    echo ""

    local success_count=0 fail_count=0 total=${#STATES[@]} current=0

    for state_entry in "${STATES[@]}"; do
        current=$((current + 1))
        local state_code="${state_entry%%|*}" state_name="${state_entry##*|}"
        local state_num
        state_num=$(get_state_number "$state_code")

        echo -e " ${DIM}[${current}/${total}]${RESET} ${state_name} (${state_code})..."

        generate_state_file "$state_code" "$state_name" "$state_num" \
            && success_count=$((success_count + 1)) \
            || fail_count=$((fail_count + 1))
    done

    # Step 3: Manifest and cleanup
    echo ""
    generate_manifest
    cleanup_temp

    echo ""
    separator
    echo -e " ${GREEN}COMPLETE: ${success_count}/${total} states${RESET}"
    [ "$fail_count" -gt 0 ] && echo -e " ${YELLOW}Failed: ${fail_count}${RESET}"
    separator
    echo ""
    echo " NWR transmitter data not included."
    echo " Add manually from: https://www.weather.gov/nwr/station_listing"
    echo " Replace '# No transmitter data' with:"
    echo "   CALLSIGN|FREQUENCY|SITE_NAME"
    echo ""

    # Preview a sample file
    if [ -f "${DATA_DIR}/alabama.txt" ]; then
        echo "Preview (alabama.txt):"
        separator
        head -25 "${DATA_DIR}/alabama.txt"
        echo -e " ${DIM}...${RESET}"
        tail -10 "${DATA_DIR}/alabama.txt"
        separator
    fi
}

main
