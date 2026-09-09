#!/bin/bash

# =====================================================================
# Author: DragoLuke
# Sort NWR stations
# License: GNU General Public License v3.0 (GPL-3.0-or-later)
# =====================================================================
# Processes NWR transmitter data in state_data/*.txt files and
# regenerates _manifest.txt with real transmitter counts.
# =====================================================================

SCRIPT_DIR="$HOME/StormScales"
STATE_DATA_DIR="${SCRIPT_DIR}/media/state_data"
MANIFEST_FILE="${STATE_DATA_DIR}/_manifest.txt"

if [[ ! -d "$STATE_DATA_DIR" ]]; then
  echo "ERROR: Directory not found: $STATE_DATA_DIR" >&2
  exit 1
fi

# State list — same format as parser.sh: "CODE|Full Name"
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
    "SC|South Carolina"   "SD|South Dakota"     "TN|Tennessee"
    "TX|Texas"            "UT|Utah"             "VT|Vermont"
    "VA|Virginia"         "WA|Washington"       "WV|West Virginia"
    "WI|Wisconsin"        "WY|Wyoming"
    "DC|District of Columbia"
)

echo "========================================"
echo "  NWR STATION PROCESSOR"
echo "========================================"
echo ""
echo "# Scanning: $STATE_DATA_DIR"
echo ""

# =============================================================================
# AWK script for processing (stored separately to avoid quoting issues)
# =============================================================================
process_stations() {
  awk 'BEGIN { in_section = 0; n = 0 }

    /===== NOAA WEATHER RADIO TRANSMITTERS =====/ {
      in_section = 1
      next
    }

    in_section && /^=+$/ {
      print "# ===== NOAA WEATHER RADIO TRANSMITTERS ====="
      print "# Format: CALLSIGN|FREQUENCY|SITE_NAME"
      print "# Source: https://www.weather.gov/nwr/station_listing"
      print "----------------------------------------------------------------------"
      print ""
      for (i = 1; i <= n; i++) print data[i]
      print ""
      print
      in_section = 0
      next
    }

    in_section && /162\.(400|425|450|475|500|525|550)/ {
      callsign = $1
      freq = ""
      freq_idx = 0
      for (i = 2; i <= NF; i++) {
        if ($i ~ /^162\.[0-9]+$/) {
          freq = $i
          freq_idx = i
          break
        }
      }
      site = ""
      if (freq_idx > 0) {
        for (j = 2; j < freq_idx; j++) {
          site = site (site ? " " : "") $j
        }
      }
      if (callsign && freq && site) {
        n++
        data[n] = callsign "|" freq "|" site
      }
      next
    }

    in_section { next }
    { print }
  '
}

# =============================================================================
# Step 1: Process each state file
# =============================================================================
declare -A TRANSMITTER_COUNTS
declare -A COUNTY_COUNTS

processed=0
skipped=0

for state_entry in "${STATES[@]}"; do
  IFS='|' read -r code state_name <<< "$state_entry"

  safe_name=$(echo "$state_name" | tr '[:upper:]' '[:lower:]' | tr ' ' '_' | tr -d '.')
  state_file="${STATE_DATA_DIR}/${safe_name}.txt"

  if [[ ! -f "$state_file" ]]; then
    echo "[SKIP] ${state_name} (${code}) — file not found"
    TRANSMITTER_COUNTS["$safe_name"]=0
    COUNTY_COUNTS["$safe_name"]=0
    ((skipped++))
    continue
  fi

  county_count=$(awk -F'|' '/^[^#]/ && NF==2 && $2 ~ /^[0-9]{5}$/ {count++} END {print count+0}' "$state_file")
  COUNTY_COUNTS["$safe_name"]=$county_count

  if grep -qE '(# No transmitter|# No data|Number of Stations.*= 0|# No stations)' "$state_file"; then
    TRANSMITTER_COUNTS["$safe_name"]=0
    echo "[SKIP] ${state_name} (${code}) — no transmitter data"
    ((skipped++))
    continue
  fi

  if ! grep -qE '162\.(400|425|450|475|500|525|550)' "$state_file"; then
    TRANSMITTER_COUNTS["$safe_name"]=0
    echo "[SKIP] ${state_name} (${code}) — no transmitter data"
    ((skipped++))
    continue
  fi

  tmp_file="${state_file}.tmp.$$"

  process_stations < "$state_file" > "$tmp_file"
  mv "$tmp_file" "$state_file"

  tx_count=$(grep -cE '^[A-Z0-9]+\|162\.[0-9]+\|' "$state_file")
  TRANSMITTER_COUNTS["$safe_name"]=$tx_count

  echo "[OK] ${state_name} (${code}) — $tx_count transmitters"
  ((processed++))
done

# =============================================================================
# Step 2: Regenerate _manifest.txt
# =============================================================================
echo ""
echo "# Regenerating manifest..."
echo ""

{
  echo "======================================================================"
  echo "# EAS State Data Manifest"
  echo "# Generated: $(date '+%Y-%m-%d %H:%M:%S')"
  echo "# Source: FCC FIPS County Codes + NOAA NWR Stations"
  echo "======================================================================"
  echo ""
  printf "%-28s %-12s %-12s\n" "STATE" "COUNTIES" "TRANSMITTERS"
  echo "----------------------------------------------------------------------"

  total_counties=0
  total_tx=0
  total_files=0

  for state_entry in "${STATES[@]}"; do
    IFS='|' read -r code state_name <<< "$state_entry"
    safe_name=$(echo "$state_name" | tr '[:upper:]' '[:lower:]' | tr ' ' '_' | tr -d '.')

    cc=${COUNTY_COUNTS["$safe_name"]:-0}
    tc=${TRANSMITTER_COUNTS["$safe_name"]:-0}

    printf "%-28s %-12s %-12s\n" "${state_name} (${code})" "${cc}" "${tc}"

    total_counties=$((total_counties + cc))
    total_tx=$((total_tx + tc))
    [[ -f "${STATE_DATA_DIR}/${safe_name}.txt" ]] && ((total_files++))
  done

  echo "----------------------------------------------------------------------"
  echo ""
  echo "SUMMARY"
  echo "  State files:        ${total_files}"
  echo "  Total counties:     ${total_counties}"
  echo "  Transmitters:       ${total_tx}"
  echo ""
  echo "======================================================================"
} > "$MANIFEST_FILE"

echo "[OK] Manifest updated: $MANIFEST_FILE"
echo ""
echo "========================================"
echo " SUMMARY"
echo "========================================"
echo "  Updated: $processed states"
echo "  Skipped: $skipped states (no data)"
echo "  Total transmitters: $total_tx"
echo "========================================"
echo ""
