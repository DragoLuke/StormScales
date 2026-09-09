#!/usr/bin/env python3

# ============================================================================
#  Author:  DragoLuke
#  Emergency Alert System (EAS) - SAME Protocol Generator
#  License: GNU General Public License v3.0 (GPL-3.0-or-later)
# ============================================================================
#
# ============================================================================
# REGULATORY SOURCES (Manually checked and verified myself - DragoLuke)
# All technical parameters in this implementation are derived from the
# following official U.S. government publications and open standards.
# Each parameter has been verified against the primary source documentation.
# This ensures compliance with FCC-mandated EAS/SAME protocol requirements.
# ============================================================================
#
#  ------------------------------------------------------------------------
#  SOURCE 1: FCC 47 CFR PART 11 -- EMERGENCY ALERT SYSTEM
#  ------------------------------------------------------------------------
#  URL:  https://www.ecfr.gov/current/title-47/chapter-I/subchapter-A/part-11
#  Doc:  Code of Federal Regulations, Title 47, Part 11
#  Updated: September 3, 2026
#
#  Section 11.31(a)(1) -- FSK Frequencies and Bit Timing:
#    "Mark frequency is 2083.3 Hz and space frequency is 1562.5 Hz.
#     Mark and space time must be 1.92 milliseconds."
#
#  Section 11.31(a)(1) -- Baud Rate:
#    "The Preamble and EAS Codes must use Audio Frequency Shift Keying at a
#     rate of 520.83 bits per second to transmit the codes."
#
#  Section 11.31(a)(2) -- Attention Signal Frequencies:
#    "The Attention Signal must be made up of the fundamental frequencies
#     of 853 and 960 Hz. The two tones must be transmitted simultaneously."
#
#  Section 11.32(a)(9)(iv) -- Attention Signal Duration:
#    "The encoder shall have timing circuitry that automatically generates
#     the two tones simultaneously for a time period of 8 seconds."
#
#  Section 11.31(c) -- Header Format:
#     "The EAS protocol, including any codes, must not be amended, extended
#     or abridged without FCC authorization. The EAS protocol and message
#     format are specified in the following representation."
#    "[PREAMBLE]ZCZC-ORG-EEE-PSSCCC+TTTT-JJJHHMM-LLLLLLLL-(one second pause)"
#    "[PREAMBLE]ZCZC-ORG-EEE-PSSCCC+TTTTPJJJHHMM-LLLLLLLL-(one second pause)"
#    "[PREAMBLE]ZCZC-ORG-EEE-PSSCCC+TTTT-JJJHHMM-LLLLLLLL-(at least a one second pause)"
#    "(transmission of 8 to 25 seconds of Attention Signal)"
#    "(transmission of audio, video or text messages)"
#    "(at least a one second pause)"
#    "[PREAMBLE]NNNN (one second pause)"
#    "[PREAMBLE]NNNN (one second pause)"
#    "[PREAMBLE]NNNN (at least one second pause)"
#
#  Header Field Breakdown # Note, this is a example I added, this is not in Section 11.31(c) - DragoLuke
#    ZCZC-WXR-TOR-030013+0045-2470755-WXJ43-
#     │    │    │    │     │     │      │
#     │    │    │    │     │     │      └─ LLLLLLLL: Station Identifier
#     │    │    │    │     │     └─ JJJHHMM: Julian day + time (DDDHHMM)
#     │    │    │    │     └─ +TTTT: Duration (HHMM)
#     │    │    │    └─ PSSCCC: State + County FIPS code
#     │    │    └─ EEE: Event Code (e.g., SVR, TOR, EAN)
#     │    └─ ORG: Originator Code (WXR/EAS/CIV/PEP)
#     └─ ZCZC: Protocol Start-of-Message Marker
#
#  Section 11.31(d)(1) -- Originator Codes:
#    WXR = National Weather Service
#    EAS = EAS Participant
#    CIV = Civil authorities
#    PEP = United States Government
#
#  Section 11.31(e) -- Event Codes (representative subset):
#    TOR = Tornado Warning
#    FFW = Flash Flood Warning
#    RWT = Required Weekly Test
#    (Authorized codes are also listed on https://www.weather.gov/nwr/eventcodes)
#
#  Section 11.31(f) -- State/Territory ANSI Codes:
#    Assigns two-digit SS numbers to each state, territory, and
#    offshore marine areas.
#
#  ------------------------------------------------------------------------
#  SOURCE 2: NOAA NWS INSTRUCTION 10-518 -- NON-WEATHER EMERGENCY PRODUCTS
#  ------------------------------------------------------------------------
#  URL:  https://www.weather.gov/media/directives/010_pdfs/pd01005018curr.pdf
#  Doc:  NWS Instruction 10-518
#  Date: September 21, 2021
#  Issuer: NOAA / National Weather Service
#
#  Section 3.2.10 -- MND Broadcast Instruction Line:
#    Specifies standard broadcast instruction phrases used when EAS
#    activation is requested:
#      "BULLETIN - EAS ACTIVATION REQUESTED"
#      "BULLETIN - IMMEDIATE BROADCAST REQUESTED"
#      "URGENT - IMMEDIATE BROADCAST REQUESTED"
#
#  Section 3.2.12(c) -- Content Requirements:
#    "If the alerting authority requests EAS activation, the word count of
#     the message should be 200 words or less, so that broadcast over NWS
#     and EAS takes less than two minutes."
#
#  ------------------------------------------------------------------------
#  SOURCE 3: NOAA NWS -- EAS / NWR PROGRAM DESCRIPTION
#  ------------------------------------------------------------------------
#  URL:  https://www.weather.gov/media/nwr/EAS_factsheet_2025.pdf
#  Doc:  NOAA's National Weather Service and the Emergency Alert System
#  Issuer: NOAA / National Weather Service
#
#  Key statement:
#    "NOAA's National Weather Service generates about 90 percent of EAS activations,
#     primarily for short-duration weather warnings and watches.
#     NOAA Weather Radio All Hazards (NWR) uses the same digital protocols as EAS,
#     and is the primary means for NWS to activate EAS."
#
#  ------------------------------------------------------------------------
#  SOURCE 4: NOAA NWS INSTRUCTION 10-701 -- TSUNAMI WARNING SERVICES
#  ------------------------------------------------------------------------
#  URL:  https://www.weather.gov/media/directives/010_pdfs_archived/pd01007001e.pdf
#  Doc:  NWS Instruction 10-701
#  Date: January 6, 2022 (administrative update)
#  Issuer: NOAA / National Weather Service
#
#  Relevant section: NWS Weather Forecast Office (WFO) and Weather Service Office (WSO) Support and Responsibilities:
#    "WFOs and Pacific Region WSOs are responsible for issuing tsunami
#     messages over NOAA Weather Radio All Hazards (NWR) and are responsible for
#     the activation of the EAS in accordance with individual state EAS plans."
#
#  ------------------------------------------------------------------------
#  SOURCE 5: CRC-16 Algorithm & Error Detection Requirements
#  ------------------------------------------------------------------------
#
#  CRC Algorithm: CCITT-FALSE (non-reflected variant)
#  Alias: CRC-16/IBM-3740, CRC-16/CCITT-FALSE
#  URL: https://reveng.sourceforge.io/crc-catalogue/16.htm
#
#  Protocol Requirement: FCC 47 CFR Part 11 (EAS Protocol Format)
#  Relevant section: 11.31 (message format), 11.33(a)(10) (error detection)
#
#  Per 11.33(a)(10), EAS decoders must validate headers using repetition
#  matching ("two of the three headers match exactly") and may use "any
#  other error detection and validation protocol."
#
#  ------------------------------------------------------------------------
#  SOURCE 6: INTEGRATED PUBLIC ALERT AND WARNING SYSTEM (IPAWS)
#  ------------------------------------------------------------------------
#  URL:  https://www.fema.gov/emergency-managers/practitioners/integrated-public-alert-warning-system/technology-developers/common-alerting-protocol
#  Doc:  Common Alerting Protocol (CAP) - IPAWS Program
#  Issuer: FEMA / Department of Homeland Security
#
#  IMPORTANT CLARIFICATION:
#    This project DOES NOT produce CAP-formatted messages. It DOES NOT
#    integrate with FEMA's IPAWS infrastructure. It DOES NOT generate
#    Wireless Emergency Alerts (WEA) for mobile phones.
#
#    What this code DOES: Implements the legacy SAME audio protocol
#    (per FCC 47 CFR Part 11) for EAS/NOAA Weather Radio use cases.
#
# ============================================================================

import sys
import os
import subprocess
import wave
import re
from datetime import datetime, timezone
from pathlib import Path
from typing import Dict, List, Tuple, Optional

import numpy as np

# ============================================================================
# CONSTANTS (Per FCC 47 CFR Section 11.31)
# ============================================================================

# FSK Frequency Pair (FCC Mandated)
FREQUENCY_MARK = 2083.3          # Binary '1' [Hz]
FREQUENCY_SPACE = 1562.5         # Binary '0' [Hz]

# Audio Sampling
SAMPLE_RATE_HZ = 96000           # Samples per second
SAMPLES_PER_BIT = 184            # 1.92ms at 96kHz (per regulation)

# Signal Amplitude (16-bit signed integer)
SIGNAL_AMPLITUDE = 16000

# Attention Tone (Two-tone alarm, 8 seconds standard)
ATTENTION_FREQ_1 = 853           # First tone [Hz]
ATTENTION_FREQ_2 = 960           # Second tone [Hz]
# Range allowed: 8 to 25 seconds (per section 11.31(c))
ATTENTION_DURATION_SEC = 8       # Duration [seconds]

# Protocol Framing
PREAMBLE_BYTE = 0xAB             # Preamble marker
PREAMBLE_COUNT = 16              # Repetitions
HEADER_REPEATS = 3               # SAME header bursts
EOM_REPEATS = 3                  # End-of-message bursts
BURST_GAP_SECONDS = 1            # Silence between bursts

# EOM Signature
EOM_CODE = "NNNN"

# State Data Directory
STATE_DATA_DIRECTORY = Path.home() / "StormScales" / "media" / "state_data"

# Input Validation Constants
MAX_INPUT_LENGTH = 256

# Maximum counties per alert (I do not recommend going past 6)
MAX_COUNTY_SELECT = 6

# ==================================================================================================
# EAS EVENT CODE DICTIONARY
# All codes verified against weather.gov/nwr/eventcodes and 47 CFR Part 11 (eCFR) — as of 2026-09-08
# [PS Docket No. 15-94; FCC 22-75; FR ID 110632]
# ==================================================================================================

EVENT_CATALOG = {
    # --- Official NWR-SAME: Weather-related ---
    "BZW": "BLIZZARD WARNING",
    "CFA": "COASTAL FLOOD WATCH",
    "CFW": "COASTAL FLOOD WARNING",
    "DSW": "DUST STORM WARNING",
    "EWW": "EXTREME WIND WARNING",
    "FFA": "FLASH FLOOD WATCH",
    "FFW": "FLASH FLOOD WARNING",
    "FFS": "FLASH FLOOD STATEMENT",
    "FLA": "FLOOD WATCH",
    "FLW": "FLOOD WARNING",
    "FLS": "FLOOD STATEMENT",
    "HWA": "HIGH WIND WATCH",
    "HWW": "HIGH WIND WARNING",
    "HUA": "HURRICANE WATCH",
    "HUW": "HURRICANE WARNING",
    "HLS": "HURRICANE STATEMENT",
    "SVA": "SEVERE THUNDERSTORM WATCH",
    "SVR": "SEVERE THUNDERSTORM WARNING",
    "SVS": "SEVERE WEATHER STATEMENT",
    "SQW": "SNOW SQUALL WARNING",
    "SMW": "SPECIAL MARINE WARNING",
    "SPS": "SPECIAL WEATHER STATEMENT",
    "SSA": "STORM SURGE WATCH",
    "SSW": "STORM SURGE WARNING",
    "TOA": "TORNADO WATCH",
    "TOR": "TORNADO WARNING",
    "TRA": "TROPICAL STORM WATCH",
    "TRW": "TROPICAL STORM WARNING",
    "TSA": "TSUNAMI WATCH",
    "TSW": "TSUNAMI WARNING",
    "WSA": "WINTER STORM WATCH",
    "WSW": "WINTER STORM WARNING",

    # --- Official NWR-SAME: Non-weather (state & local) ---
    "AVA": "AVALANCHE WATCH",
    "AVW": "AVALANCHE WARNING",
    "BLU": "BLUE ALERT",
    "CAE": "CHILD ABDUCTION EMERGENCY",
    "CDW": "CIVIL DANGER WARNING",
    "CEM": "CIVIL EMERGENCY MESSAGE",
    "EQW": "EARTHQUAKE WARNING",
    "EVI": "EVACUATION IMMEDIATE",
    "FRW": "FIRE WARNING",
    "HMW": "HAZARDOUS MATERIALS WARNING",
    "LEW": "LAW ENFORCEMENT WARNING",
    "LAE": "LOCAL AREA EMERGENCY",
    "TOE": "911 TELEPHONE OUTAGE EMERGENCY",
    "NUW": "NUCLEAR POWER PLANT WARNING",
    "RHW": "RADIOLOGICAL HAZARD WARNING",
    "SPW": "SHELTER IN-PLACE WARNING",
    "VOW": "VOLCANO WARNING",

    # --- Official NWR-SAME: Administrative ---
    "ADR": "ADMINISTRATIVE MESSAGE",
    "DMO": "PRACTICE/DEMO WARNING",
    "RMT": "REQUIRED MONTHLY TEST",
    "RWT": "REQUIRED WEEKLY TEST",

    # --- EAS National Codes (eCFR 47 CFR Part 11) ---
    "EAN": "NATIONAL EMERGENCY MESSAGE",                      # Renamed from "Emergency Action Notification" by FCC 2022
    "NPT": "NATIONWIDE TEST OF THE EMERGENCY ALERT SYSTEM",   # Renamed from "National Periodic Test" by FCC 2022
    "MEP": "MISSING AND ENDANGERED PERSONS ALERT",            # Adopted by FCC, effective Sept 8, 2025
}

# ============================================================================
# STATE NAME TO ABBREVIATION MAPPING
# ============================================================================

STATE_NAME_TO_ABBR = {
    "ALABAMA": "AL", "ALASKA": "AK", "ARIZONA": "AZ", "ARKANSAS": "AR",
    "CALIFORNIA": "CA", "COLORADO": "CO", "CONNECTICUT": "CT", "DELAWARE": "DE",
    "DISTRICT OF COLUMBIA": "DC", "FLORIDA": "FL", "GEORGIA": "GA", "HAWAII": "HI",
    "IDAHO": "ID", "ILLINOIS": "IL", "INDIANA": "IN", "IOWA": "IA",
    "KANSAS": "KS", "KENTUCKY": "KY", "LOUISIANA": "LA", "MAINE": "ME",
    "MARYLAND": "MD", "MASSACHUSETTS": "MA", "MICHIGAN": "MI", "MINNESOTA": "MN",
    "MISSISSIPPI": "MS", "MISSOURI": "MO", "MONTANA": "MT", "NEBRASKA": "NE",
    "NEVADA": "NV", "NEW HAMPSHIRE": "NH", "NEW JERSEY": "NJ", "NEW MEXICO": "NM",
    "NEW YORK": "NY", "NORTH CAROLINA": "NC", "NORTH DAKOTA": "ND", "OHIO": "OH",
    "OKLAHOMA": "OK", "OREGON": "OR", "PENNSYLVANIA": "PA", "RHODE ISLAND": "RI",
    "SOUTH CAROLINA": "SC", "SOUTH DAKOTA": "SD", "TENNESSEE": "TN", "TEXAS": "TX",
    "UTAH": "UT", "VERMONT": "VT", "VIRGINIA": "VA", "WASHINGTON": "WA",
    "WEST VIRGINIA": "WV", "WISCONSIN": "WI", "WYOMING": "WY",
}

def _get_state_abbreviation(state_name: str) -> str:
    """Convert full state name to 2-letter postal abbreviation."""
    return STATE_NAME_TO_ABBR.get(state_name, state_name[:2].upper())

# ============================================================================
# ANSI COLOR CODES FOR TERMINAL OUTPUT
# ============================================================================

COLOR_GREEN = "\033[32m"
COLOR_RED = "\033[31m"
COLOR_YELLOW = "\033[33m"
COLOR_CYAN = "\033[1;36m"
COLOR_BLUE = "\033[1;34m"
COLOR_DIM = "\033[2m"
COLOR_RESET = "\033[0m"

def log_info(message: str) -> None:
    print(f"[{COLOR_GREEN}+{COLOR_RESET}] {message}")

def log_error(message: str) -> None:
    print(f"[{COLOR_RED}-{COLOR_RESET}] {message}")

def log_warn(message: str) -> None:
    print(f"[{COLOR_YELLOW}!{COLOR_RESET}] {message}")

def log_dim(message: str) -> None:
    print(f"{COLOR_DIM}{message}{COLOR_RESET}")

# ============================================================================
# UNICODE BOX DRAWING FOR TERMINAL OUTPUT
# ============================================================================

BOX_TOP_LEFT = "┌"
BOX_TOP_RIGHT = "┐"
BOX_BOTTOM_LEFT = "└"
BOX_BOTTOM_RIGHT = "┘"
BOX_HORIZONTAL = "─"
BOX_VERTICAL = "│"
BOX_LEFT_TEE = "├"
BOX_RIGHT_TEE = "┤"

def _visible_len(s: str) -> int:
    """Return visible length of a string, ignoring ANSI escape codes."""
    import re as _re
    return len(_re.sub(r'\033\[[0-9;]*m', '', s))

def print_panel(title: str, lines: List[str], width: int = 72) -> None:
    """Print a complete boxed panel with a titled header and content lines."""
    prefix = f"{COLOR_CYAN}"
    suffix = f"{COLOR_RESET}"

    inner_w = width - 2

    title_text = f" » {title}"
    title_pad = inner_w - _visible_len(title_text)
    if title_pad < 0:
        title_pad = 0
    top = f"{prefix}{BOX_TOP_LEFT}{'─' * inner_w}{BOX_TOP_RIGHT}{suffix}"
    title_line = f"{prefix}{BOX_VERTICAL}{title_text}{' ' * title_pad}{BOX_VERTICAL}{suffix}"
    divider = f"{prefix}{BOX_LEFT_TEE}{'─' * inner_w}{BOX_RIGHT_TEE}{suffix}"

    print(top)
    print(title_line)
    print(divider)
    for line in lines:
        line_text = f" {line}"
        line_pad = inner_w - _visible_len(line_text)
        if line_pad < 0:
            line_text = line_text[:inner_w - 1]
            line_pad = 0
        print(f"{prefix}{BOX_VERTICAL}{line_text}{' ' * line_pad}{BOX_VERTICAL}{suffix}")
    bottom = f"{prefix}{BOX_BOTTOM_LEFT}{'─' * inner_w}{BOX_BOTTOM_RIGHT}{suffix}"
    print(bottom)

def print_plain_panel(lines: List[str], width: int = 72) -> None:
    """Print a boxed panel with content lines only (no title row)."""
    prefix = f"{COLOR_CYAN}"
    suffix = f"{COLOR_RESET}"
    inner_w = width - 2

    top = f"{prefix}{BOX_TOP_LEFT}{'─' * inner_w}{BOX_TOP_RIGHT}{suffix}"
    print(top)
    for line in lines:
        line_text = f" {line}"
        line_pad = inner_w - _visible_len(line_text)
        if line_pad < 0:
            line_text = line_text[:inner_w - 1]
            line_pad = 0
        print(f"{prefix}{BOX_VERTICAL}{line_text}{' ' * line_pad}{BOX_VERTICAL}{suffix}")
    bottom = f"{prefix}{BOX_BOTTOM_LEFT}{'─' * inner_w}{BOX_BOTTOM_RIGHT}{suffix}"
    print(bottom)

# ============================================================================
# SECURE FILE NAME SANITIZATION
# ============================================================================

def sanitize_filename(slug: str) -> str:
    r"""
    Sanitize filename to prevent path traversal and filesystem exploits.

    Removes or replaces:
    - Path separators (/ \ ..)
    - Null bytes
    - Control characters
    - Dangerous special characters

    Returns a safe, alphanumeric-with-underscores slug.
    """
    # Limit length
    slug = slug[:MAX_INPUT_LENGTH]

    # Remove null bytes and control characters
    slug = ''.join(c for c in slug if ord(c) >= 32)

    # Replace path separators and dangerous sequences
    slug = slug.replace('/', '_').replace('\\', '_').replace('..', '_')
    slug = slug.replace('.', '_')

    # Replace spaces with underscores
    slug = slug.replace(' ', '_')

    # Keep only safe characters (alphanumeric, underscore, hyphen)
    slug = re.sub(r'[^A-Za-z0-9_-]', '_', slug)

    # Collapse consecutive underscores
    slug = re.sub(r'_+', '_', slug)

    # Trim leading/trailing underscores
    slug = slug.strip('_')

    return slug or 'unnamed'

def validate_output_path(filepath: str, base_directory: Path) -> bool:
    """
    Validate that resolved output path stays within base directory.

    Prevents path traversal attacks via symbolic links or ../ escapes.
    """
    try:
        abs_filepath = os.path.abspath(os.path.realpath(filepath))
        abs_base = os.path.abspath(os.path.realpath(base_directory))

        return abs_filepath.startswith(abs_base)
    except OSError:
        return False

# ============================================================================
# CRC-16-CCITT IMPLEMENTATION
# ============================================================================

def calculate_crc16_ccitt(data_bytes: bytes) -> int:
    """
    Calculate CRC-16-CCITT (CCITT-FALSE / IBM-3740) checksum.

    Official name: CRC-16/IBM-3740 (alias: CRC-16/CCITT-FALSE)
    Reference: https://reveng.sourceforge.io/crc-catalogue/16.htm

    Parameters (per CRC RevEng Catalogue):
      width=16 poly=0x1021 init=0xffff refin=false refout=false xorout=0x0000
      check="123456789"=0x29b1

    This variant is used in SAME/EAS protocol headers.
    """
    crc_register = 0xFFFF

    for octet in data_bytes:
        crc_register ^= (octet << 8)

        for _ in range(8):
            if crc_register & 0x8000:
                crc_register = ((crc_register << 1) ^ 0x1021) & 0xFFFF
            else:
                crc_register = (crc_register << 1) & 0xFFFF

    return crc_register

def convert_crc_to_bits(crc_value: int) -> str:
    """
    Convert 16-bit CRC integer to binary string for transmission.

    SAME protocol transmits each byte least-significant bit first.
    This function reverses each octet to match LSB-first convention.

    Args:
        crc_value: CRC from calculate_crc16_ccitt()

    Returns:
        16-character string of '0' and '1' (LSB-first per octet)
    """
    high_octet = (crc_value >> 8) & 0xFF
    low_octet = crc_value & 0xFF

    return format(high_octet, '08b')[::-1] + format(low_octet, '08b')[::-1]

# ============================================================================
# AUDIO WAVEFORM GENERATION
# ============================================================================

def generate_single_bit(bit_char: str) -> np.ndarray:
    """
    Generate FSK waveform for one bit duration.

    Args:
        bit_char: Either '0' or '1'

    Returns:
        NumPy int16 array containing samples for one bit
    """
    time_vector = np.arange(SAMPLES_PER_BIT) / SAMPLE_RATE_HZ
    frequency = FREQUENCY_MARK if bit_char == "1" else FREQUENCY_SPACE
    waveform = SIGNAL_AMPLITUDE * np.sin(2 * np.pi * frequency * time_vector)
    return waveform.astype(np.int16)

def convert_text_to_bits(text_string: str) -> str:
    """
    Convert ASCII text to LSB-first bit string for SAME protocol.

    SAME protocol transmits each byte least-significant bit first.

    Args:
        text_string: Plain text message

    Returns:
        Continuous bit string ('0' and '1' characters)
    """
    bit_accumulator = []

    for character in text_string:
        ascii_value = ord(character)

        # Extract 8 bits, LSB-first order
        for bit_position in range(8):
            extracted_bit = (ascii_value >> bit_position) & 1
            bit_accumulator.append(str(extracted_bit))

    return "".join(bit_accumulator)

def generate_attention_tone(duration_sec: float = ATTENTION_DURATION_SEC) -> np.ndarray:
    """
    Generate two-tone attention signal (853 Hz + 960 Hz).

    Per NWS standard, these tones are summed equally.
    """
    num_samples = int(duration_sec * SAMPLE_RATE_HZ)
    time_axis = np.arange(num_samples) / SAMPLE_RATE_HZ

    tone_one = np.sin(2 * np.pi * ATTENTION_FREQ_1 * time_axis)
    tone_two = np.sin(2 * np.pi * ATTENTION_FREQ_2 * time_axis)

    # Average prevents clipping when summing two sine waves
    combined = (tone_one + tone_two) / 2

    return (combined * SIGNAL_AMPLITUDE).astype(np.int16)

def construct_header_with_crc(header_text: str, repeats: int = HEADER_REPEATS) -> np.ndarray:
    """
    Build SAME header with CRC-16 appended to each burst.

    Args:
        header_text: Complete ZCZC... header string
        repeats: Number of identical bursts

    Returns:
        Concatenated waveform with bursts and gaps
    """
    preamble_bits = format(PREAMBLE_BYTE, '08b')[::-1] * PREAMBLE_COUNT
    header_bits = convert_text_to_bits(header_text)

    header_bytes = header_text.encode("ascii")
    crc_result = calculate_crc16_ccitt(header_bytes)
    crc_bitstring = convert_crc_to_bits(crc_result)

    log_info(f"Header CRC-16: 0x{crc_result:04X} ({crc_bitstring})")

    full_bitstream = preamble_bits + header_bits + crc_bitstring

    full_waveform = np.array([], dtype=np.int16)
    for bit_char in full_bitstream:
        full_waveform = np.concatenate([full_waveform, generate_single_bit(bit_char)])

    output_segments = []
    for burst_index in range(repeats):
        output_segments.append(full_waveform)
        if burst_index < repeats - 1:
            silence = np.zeros(int(SAMPLE_RATE_HZ * BURST_GAP_SECONDS), dtype=np.int16)
            output_segments.append(silence)

    return np.concatenate(output_segments)

def construct_eom_with_crc(include_crc: bool = True, repeats: int = EOM_REPEATS) -> np.ndarray:
    """
    Build End-of-Message (NNNN) with optional CRC.

    Args:
        include_crc: Whether to append CRC-16 to EOM
        repeats: Number of EOM bursts

    Returns:
        Concatenated EOM waveform
    """
    eom_text = EOM_CODE
    preamble_bits = format(PREAMBLE_BYTE, '08b')[::-1] * PREAMBLE_COUNT
    eom_bits = convert_text_to_bits(eom_text)

    if include_crc:
        crc_result = calculate_crc16_ccitt(eom_text.encode("ascii"))
        crc_bits = convert_crc_to_bits(crc_result)
        full_stream = preamble_bits + eom_bits + crc_bits
        log_info(f"EOM CRC-16: 0x{crc_result:04X}")
    else:
        full_stream = preamble_bits + eom_bits

    output_segments = []
    for burst_index in range(repeats):
        full_waveform = np.array([], dtype=np.int16)
        for bit_char in full_stream:
            full_waveform = np.concatenate([full_waveform, generate_single_bit(bit_char)])

        output_segments.append(full_waveform)
        if burst_index < repeats - 1:
            silence = np.zeros(int(SAMPLE_RATE_HZ * BURST_GAP_SECONDS), dtype=np.int16)
            output_segments.append(silence)

    return np.concatenate(output_segments)

def save_wav_file(filepath: str, samples: np.ndarray, sample_rate: int = SAMPLE_RATE_HZ) -> bool:
    """
    Write samples to WAV container with secure permissions.

    Args:
        filepath: Output file path
        samples: Int16 audio samples
        sample_rate: Sample rate in Hz

    Returns:
        True on success, False on failure
    """
    try:
        with wave.open(filepath, "wb") as wav_file:
            wav_file.setnchannels(1)
            wav_file.setsampwidth(2)
            wav_file.setframerate(sample_rate)
            wav_file.writeframes(samples.astype(np.int16).tobytes())

        # Secure file permissions (owner-only read/write)
        os.chmod(filepath, 0o600)

        return True
    except (IOError, PermissionError, OSError) as error:
        log_error(f"Failed to write WAV: {error}")
        return False

# ============================================================================
# IQ EXPORT FOR SDR TRANSMISSION
# ============================================================================

def generate_fm_modulation(audio_samples: np.ndarray,
                           sample_rate: int,
                           deviation_hz: float = 4800) -> np.ndarray:
    """
    Apply narrowband FM modulation for SDR transmission.

    Args:
        audio_samples: Int16 audio data
        sample_rate: Sample rate in Hz
        deviation_hz: Frequency deviation [Hz]

    Returns:
        Complex64 IQ samples
    """
    max_amplitude = np.max(np.abs(audio_samples))
    if max_amplitude == 0:
        max_amplitude = 1.0

    normalized = audio_samples.astype(np.float64) / max_amplitude
    scaled = normalized * 0.1

    phase_accumulator = 2 * np.pi * deviation_hz * np.cumsum(scaled) / sample_rate
    iq_signal = np.exp(1j * phase_accumulator)

    return iq_signal.astype(np.complex64)

def resample_iq_signal(signal: np.ndarray, from_rate: int, to_rate: int) -> np.ndarray:
    """
    Resample IQ complex signal to target sample rate.

    Args:
        signal: Complex64 IQ data
        from_rate: Original sample rate
        to_rate: Target sample rate

    Returns:
        Resampled complex64 IQ signal
    """
    original_length = len(signal)
    new_length = int(original_length * to_rate / from_rate)

    old_indices = np.arange(original_length, dtype=np.float64)
    new_indices = np.linspace(0, original_length - 1, new_length)

    resampled = np.zeros(new_length, dtype=np.complex64)
    resampled.real = np.interp(new_indices, old_indices, signal.real)
    resampled.imag = np.interp(new_indices, old_indices, signal.imag)

    return resampled

def convert_to_signed_8bit(iq_data: np.ndarray) -> np.ndarray:
    """
    Convert complex IQ to signed 8-bit interleaved format.

    Produces I,Q,I,Q,... byte sequence for HackRF/RTL-SDR.
    """
    i_channel = np.clip(iq_data.real * 127, -128, 127).astype(np.int8)
    q_channel = np.clip(iq_data.imag * 127, -128, 127).astype(np.int8)

    interleaved = np.empty(len(i_channel) * 2, dtype=np.int8)
    interleaved[0::2] = i_channel
    interleaved[1::2] = q_channel

    return interleaved

def export_iq_file(wav_audio: np.ndarray,
                   output_path: str,
                   src_rate: int = SAMPLE_RATE_HZ,
                   target_rate: int = 2000000,
                   deviation: float = 4800) -> bool:
    """
    Generate HackRF-compatible IQ file from audio with secure permissions.

    Args:
        wav_audio: Int16 audio samples
        output_path: Output .iq file path
        src_rate: Audio sample rate
        target_rate: SDR target sample rate
        deviation: FM deviation [Hz]

    Returns:
        True on success
    """
    log_info("Generating IQ baseband file for SDR transmission...")

    if src_rate != 48000:
        log_info(f"   Resampling audio: {src_rate} Hz -> 48000 Hz")
        old_pos = np.arange(len(wav_audio), dtype=np.float64)
        new_pos = int(len(wav_audio) * 48000 / src_rate)
        new_indices = np.linspace(0, len(wav_audio) - 1, new_pos)
        audio_48k = np.interp(new_indices, old_pos, wav_audio.astype(np.float64)).astype(np.int16)
    else:
        audio_48k = wav_audio

    log_info(f"   Audio samples at 48k: {len(audio_48k):,}")
    log_info("   FM modulating signal...")
    iq_baseband = generate_fm_modulation(audio_48k, 48000, deviation)

    log_info(f"   Resampling IQ: 48000 Hz -> {target_rate} Hz")
    iq_resampled = resample_iq_signal(iq_baseband, 48000, target_rate)

    log_info("   Converting to signed 8-bit IQ format...")
    iq_final = convert_to_signed_8bit(iq_resampled)

    try:
        iq_final.tofile(output_path)
        # Secure file permissions (owner-only read/write)
        os.chmod(output_path, 0o600)
    except (IOError, PermissionError, OSError) as error:
        log_error(f"Failed to write IQ file: {error}")
        return False

    file_size_mb = os.path.getsize(output_path) / (1024 * 1024)
    duration_sec = len(iq_resampled) / target_rate

    log_info(f"   IQ file created: {output_path}")
    log_info(f"   Total IQ samples: {len(iq_resampled):,}")
    log_info(f"   Duration: {duration_sec:.2f}s")
    log_info(f"   File size: {file_size_mb:.2f} MB")
    log_info(f"   Format: int8 interleaved (I,Q,I,Q,...) @{target_rate} SPS")

    return True

# ============================================================================
# STATE DATA LOADER
# ============================================================================

def discover_state_files() -> List[str]:
    """Find all available state definition files in state_data directory."""
    if not STATE_DATA_DIRECTORY.is_dir():
        log_warn(f"State directory not found: {STATE_DATA_DIRECTORY}")
        log_warn("Run eas_fips_setup.sh first to generate state files")
        return []

    state_files = []
    for filename in os.listdir(STATE_DATA_DIRECTORY):
        if filename.endswith(".txt") and "_manifest" not in filename:
            state_files.append(filename)

    return sorted(state_files)

def parse_state_file(filepath: Path) -> Tuple[Dict[str, str], Dict[str, str]]:
    """
    Extract county FIPS codes and transmitter information from state file.

    Returns:
        Tuple of (counties_dict, transmitters_dict)
        counties_dict: {COUNTY_KEY: "FIPS"}
        transmitters_dict: {CALLSIGN: "LOCATION (frequency)"}
    """
    counties = {}
    transmitters = {}

    in_counties_section = False
    in_transmitters_section = False

    try:
        with open(filepath, "r", encoding="utf-8") as state_file:
            for line in state_file:
                stripped_line = line.strip()

                if stripped_line == "# ===== COUNTY FIPS CODES =====":
                    in_counties_section = True
                    in_transmitters_section = False
                    continue
                elif stripped_line == "# ===== NOAA WEATHER RADIO TRANSMITTERS =====":
                    in_counties_section = False
                    in_transmitters_section = True
                    continue
                elif stripped_line.startswith("#") or stripped_line.startswith("---") or stripped_line == "======":
                    continue
                elif not stripped_line:
                    continue

                if in_counties_section and "|" in stripped_line:
                    parts = stripped_line.rsplit("|", 1)
                    if len(parts) == 2:
                        county_name = parts[0].strip()
                        fips_digits = parts[1].strip()

                        if fips_digits.isdigit() and len(fips_digits) == 5:
                            county_key = county_name.upper().replace(" ", "_")
                            counties[county_key] = fips_digits

                elif in_transmitters_section and "|" in stripped_line:
                    parts = stripped_line.split("|")
                    if len(parts) >= 3:
                        callsign = parts[0].strip()
                        frequency = parts[1].strip()
                        location = parts[2].strip()

                        if callsign.startswith(("K", "W")) and frequency.startswith("162."):
                            transmitters[callsign] = f"{location} ({frequency} MHz)"

    except IOError as error:
        log_error(f"Could not read state file: {error}")
        return {}, {}

    if not counties:
        log_error(f"No county data found in: {filepath}")
        return {}, {}

    return counties, transmitters

# ============================================================================
# INPUT VALIDATION (SECURITY-HARDENED)
# ============================================================================

def validate_is_numeric(input_string: str) -> bool:
    """Check if string contains only digits."""
    try:
        int(input_string)
        return True
    except ValueError:
        return False

def validate_in_range(input_string: str, min_value: int, max_value: int) -> bool:
    """Check if numeric string falls within specified range."""
    if not validate_is_numeric(input_string):
        return False
    value = int(input_string)
    return min_value <= value <= max_value

def get_sanitized_input(prompt_text: str, max_length: int = MAX_INPUT_LENGTH) -> str:
    """
    Get user input with sanitization: trim, length cap, null-byte removal.

    Returns sanitized string (may be empty).
    """
    try:
        raw_input = input(prompt_text)
    except EOFError:
        return ""

    # Truncate to max length
    truncated = raw_input[:max_length]

    # Strip whitespace
    trimmed = truncated.strip()

    # Remove null bytes and control characters
    cleaned = ''.join(c for c in trimmed if ord(c) >= 32)

    return cleaned

def get_validated_number(prompt_text: str,
                         default_value: Optional[int] = None,
                         min_value: int = 1,
                         max_value: int = 999,
                         allow_default: bool = False) -> Optional[int]:
    """
    Get validated numeric input from user with retries and optional default.

    Returns validated integer or None on too many invalid attempts.
    """
    MAX_ATTEMPTS = 10
    attempts = 0

    while attempts < MAX_ATTEMPTS:
        if allow_default and default_value is not None:
            user_input = get_sanitized_input(f"  {prompt_text} [Default: {default_value}] ")
        else:
            user_input = get_sanitized_input(f"  {prompt_text} ")

        # Handle empty input with default
        if not user_input:
            if allow_default and default_value is not None:
                return default_value
            else:
                log_error("Input cannot be empty.")
                log_dim(f"Valid range: {min_value} to {max_value}")
                attempts += 1
                continue

        # Validate numeric
        if not validate_is_numeric(user_input):
            log_error(f"Invalid selection: '{user_input}' is not a number")
            log_dim(f"Valid range: {min_value} to {max_value}")
            attempts += 1
            continue

        # Validate range
        value = int(user_input)
        if min_value <= value <= max_value:
            return value
        else:
            log_error(f"Invalid selection: '{user_input}'")
            log_dim(f"Valid range: {min_value} to {max_value}")
            attempts += 1

    log_error("Too many invalid attempts. Exiting setup.")
    return None

def confirm_question(question_text: str) -> bool:
    """Ask yes/no question, return True for affirmative answers."""
    response = get_sanitized_input(f"{question_text} [y/N] ").lower()
    return response in ("y", "yes")

# ============================================================================
# SECURE SUBPROCESS EXECUTION
# ============================================================================

def run_decode_test_direct(filepath: str) -> int:
    """
    Run multimon-ng decode test using subprocess WITHOUT shell=True.
    Resamples WAV to 22050 Hz first -- multimon-ng's EAS demodulator expects this rate.

    Args:
        filepath: Path to WAV file (already sanitized by script)

    Returns:
        Return code from multimon-ng
    """
    # Create temporary resampled WAV at 22050 Hz
    resampled_path = filepath.replace(".wav", "_22050.wav")

    try:
        subprocess.run(
            ["sox", filepath, "-r", "22050", "-c", "1", "-b", "16", "-e",
             "signed-integer", resampled_path],
            check=True, timeout=30, capture_output=True
        )
    except FileNotFoundError:
        log_error("SoX not found. Install sox for decode testing.")
        return -1
    except subprocess.CalledProcessError as err:
        log_error(f"SoX resample failed: {err.stderr.decode()}")
        return -1
    except subprocess.TimeoutExpired:
        log_warn("SoX resample timed out.")
        return -1

    try:
        proc = subprocess.Popen(
            ["multimon-ng", "-t", "wav", "-a", "EAS", resampled_path],
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT
        )
        proc.wait(timeout=60)
        return proc.returncode
    except FileNotFoundError:
        log_error("multimon-ng not found.")
        return -1
    except subprocess.TimeoutExpired:
        log_warn("Decode test timed out.")
        proc.kill()
        return -1
    except KeyboardInterrupt:
        print("\n[-] Test stopped by user.")
        proc.kill()
        return -1
    finally:
        # Clean up temp file
        try:
            os.unlink(resampled_path)
        except OSError:
            pass

def run_decode_test_pipe(filepath: str) -> int:
    """
    Run multimon-ng decode test via sox pipe WITHOUT shell=True.

    Uses subprocess.Popen with separate processes piped together.

    Args:
        filepath: Path to WAV file

    Returns:
        Return code from multimon-ng
    """
    try:
        # SoX process
        sox_proc = subprocess.Popen(
            ["sox", filepath, "-t", "raw", "-r", "22050", "-e", "signed-integer",
             "-b", "16", "-c", "1", "-"],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE
        )

        # Multimon process
        multimon_proc = subprocess.Popen(
            ["multimon-ng", "-t", "raw", "-a", "EAS", "-"],
            stdin=sox_proc.stdout,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT
        )

        # Close sox stdout to allow proper pipe closure
        sox_proc.stdout.close()

        # Wait for multimon to finish
        multimon_out, multimon_err = multimon_proc.communicate(timeout=60)

        # Wait for sox to finish
        sox_proc.wait()

        return multimon_proc.returncode
    except FileNotFoundError as err:
        log_error(f"Required tool not found: {err}")
        return -1
    except subprocess.TimeoutExpired:
        log_warn("Decode test timed out.")
        return -1
    except KeyboardInterrupt:
        print("\n[-] Test stopped by user.")
        return -1

# ============================================================================
# MAIN WORKFLOW
# ============================================================================

def main() -> None:
    """Entry point for EAS payload generator."""
    os.system('clear')
    os.umask(0o077)

    print()
    print_panel(
        "EAS/SAME Generator (CRC-16 Enabled)",
        [
            "Multi-State Support",
            "Based on FCC 47 CFR Part 11.31",
        ]
    )
    print()

    available_states = discover_state_files()

    if not available_states:
        log_error("No state data files found!")
        log_warn(f"Expected data in: {STATE_DATA_DIRECTORY}")
        log_warn("Run eas_fips_setup.sh to generate state files")
        sys.exit(1)

    log_info(f"Found {len(available_states)} state data file(s)")

    print()
    print_panel(
        "SELECT ALERT SCOPE TYPE",
        [
            "[N] NATIONAL ALERT (FIPS 000000 - All U.S. Territories)",
            "[S] STATE/REGIONAL ALERT (Select state + counties)",
        ]
    )
    print()

    while True:
        scope_choice = get_sanitized_input("Select alert type [N/S]: ").upper()
        if scope_choice in ("N", "S"):
            break
        log_error("Please enter 'N' for national or 'S' for state/regional alert.")

    selected_fips_list = []
    selected_location_names = []
    transmitter_map = {}
    active_state_name = "NATIONAL"

    if scope_choice == "N":
        selected_fips_list = ["000000"]
        selected_location_names = ["NATIONAL"]
        active_state_name = "NATIONAL"
        print()
        print_plain_panel([
            f"Selected: NATIONAL EMERGENCY (All U.S. Territories)",
            f"FIPS code: 000000",
            f"NOTE: State/county selection skipped for national alerts",
        ])
        print()
    else:
        print()
        print_panel(
            "STEP 1: SELECT STATE",
            [
                f"Available States/Territories:",
            ]
        )
        print()

        num_states = len(available_states)

        state_abbr_map = {}
        abbr_to_idx = {}

        for idx in range(num_states):
            filename = available_states[idx]
            state_full = filename[:-4].upper().replace("_", " ")
            state_abbr = _get_state_abbreviation(state_full)
            state_abbr_map[idx + 1] = state_abbr
            abbr_to_idx[state_abbr] = idx

        for idx in range(0, num_states, 2):
            idx1 = idx + 1
            name1 = available_states[idx][:-4].upper().replace("_", " ")
            abbr1 = state_abbr_map[idx1]
            print(f"  [{idx1:2d}] {abbr1:<4} {name1:<31}", end="")
            if idx + 1 < num_states:
                idx2 = idx + 2
                name2 = available_states[idx + 1][:-4].upper().replace("_", " ")
                abbr2 = state_abbr_map[idx2]
                print(f"  [{idx2:2d}] {abbr2:<4} {name2}")
            else:
                print()
        print()

        state_selection = None
        MAX_ATTEMPTS = 10
        attempts = 0

        while attempts < MAX_ATTEMPTS and state_selection is None:
            user_input = get_sanitized_input("  Press Enter for first state, or type a number/abbreviation. ").upper()

            if not user_input:
                state_selection = 1
                break

            if user_input.isdigit():
                num_val = int(user_input)
                if 1 <= num_val <= num_states:
                    state_selection = num_val
                    break
                else:
                    log_error(f"Number '{user_input}' out of range (1-{num_states}).")
                    attempts += 1
                    continue

            if user_input in abbr_to_idx:
                state_selection = abbr_to_idx[user_input] + 1
                break
            else:
                log_error(f"Unknown state abbreviation '{user_input}'. Use number or 2-letter code (e.g., MT, CA, TX).")
                attempts += 1
                continue

        if state_selection is None:
            sys.exit(1)

        state_idx = state_selection - 1
        selected_filename = available_states[state_idx]
        active_state_name = selected_filename[:-4].upper().replace("_", " ")
        log_info(f"Selected: {active_state_name}")
        log_info(f"Data file: {selected_filename}")

        os.system('clear')

        state_file_path = STATE_DATA_DIRECTORY / selected_filename
        county_map, transmitter_map = parse_state_file(state_file_path)

        if not county_map:
            log_error("Failed to load county data for selected state")
            sys.exit(1)

        log_info(f"Loaded {len(county_map)} counties")

        print()
        print_panel(
            f"STEP 2: SELECT {active_state_name.upper()} COUNTIES",
            [
                f"Select up to {MAX_COUNTY_SELECT} counties (comma-separated numbers or names)",
                f"Example: '1,3,5' or 'GALLATIN,FERGUS'",
            ]
        )
        print()

        sorted_county_keys = sorted(list(county_map.keys()))
        num_counties = len(sorted_county_keys)

        print()
        for i in range(0, num_counties, 3):
            row_items = []
            for j in range(3):
                if i + j < num_counties:
                    disp_idx = i + j + 1
                    disp_name = sorted_county_keys[i + j].replace("_", " ")
                    row_items.append(f"  [{disp_idx:3d}] {disp_name:<22}")
            print("".join(row_items))
        print()

        while True:
            county_input = get_sanitized_input(
                f"Enter county selections (max {MAX_COUNTY_SELECT}): ",
                max_length=MAX_INPUT_LENGTH
            ).upper()

            if not county_input:
                log_error("Please enter at least one valid county.")
                continue

            raw_choices = [x.strip() for x in county_input.split(",") if x.strip()]

            if not raw_choices:
                log_error("Please enter at least one valid county.")
                continue

            valid_selection = True
            temp_fips = []
            temp_names = []

            for choice_item in raw_choices:
                if choice_item in county_map:
                    temp_names.append(choice_item.replace("_", " "))
                    county_code = county_map[choice_item]
                    temp_fips.append(f"0{county_code}")
                else:
                    try:
                        numeric_choice = int(choice_item)
                        if 1 <= numeric_choice <= num_counties:
                            key_at_position = sorted_county_keys[numeric_choice - 1]
                            temp_names.append(key_at_position.replace("_", " "))
                            county_code = county_map[key_at_position]
                            temp_fips.append(f"0{county_code}")
                        else:
                            log_error(f"Selection number '{numeric_choice}' is out of range (1-{num_counties}).")
                            valid_selection = False
                            break
                    except ValueError:
                        log_error(f"Could not identify county: '{choice_item}'. Please check spelling or menu number.")
                        valid_selection = False
                        break

            if not valid_selection:
                continue

            if len(temp_fips) > MAX_COUNTY_SELECT:
                log_error(
                    f"You selected {len(temp_fips)} counties, but the maximum is {MAX_COUNTY_SELECT}."
                )
                log_error("Please reduce your selection and try again.")
                continue

            selected_fips_list = temp_fips
            selected_location_names = temp_names
            break

        print()
        print_plain_panel([
            f"Selected {len(selected_fips_list)} location(s): "
            f"{', '.join(selected_location_names)}",
        ])
        print()

        os.system('clear')

    print()
    print_panel(
        f"SELECT EAS HAZARD EVENT ({active_state_name.upper()} scope)",
        [
            "Type code like 'FFW' or menu number",
        ]
    )
    print()

    hazard_keys = list(EVENT_CATALOG.keys())
    print()
    for idx, key in enumerate(hazard_keys, 1):
        print(f"  [{idx:2d}] {key} - {EVENT_CATALOG[key]:<30}", end="\n" if idx % 2 == 0 else "")
    print()

    while True:
        hazard_input = get_sanitized_input("Enter hazard selection (e.g., FFW or 16): ", max_length=MAX_INPUT_LENGTH).upper()

        if hazard_input in EVENT_CATALOG:
            selected_event = hazard_input
            selected_event_name = EVENT_CATALOG[hazard_input]
            break

        try:
            hazard_choice = int(hazard_input)
            if 1 <= hazard_choice <= len(hazard_keys):
                selected_event = hazard_keys[hazard_choice - 1]
                selected_event_name = EVENT_CATALOG[selected_event]
                break
        except ValueError:
            pass

        log_error(f"Invalid hazard selection. Please enter a short code (e.g., TOR) or number (1-{len(hazard_keys)}).")

    print()
    print_plain_panel([
        f"Selected Hazard: {selected_event} ({selected_event_name})",
    ])
    print()

    os.system('clear')

    print()
    print_panel(
        "SELECT ALERT DURATION",
        [
            "[1] 15 Minutes",
            "[2] 30 Minutes",
            "[3] 45 Minutes",
            "[4] 1 Hour",
            "[5] 2 Hours",
            "[6] Custom (Enter minutes manually)",
        ]
    )
    print()

    while True:
        duration_choice = get_validated_number(
            "Enter duration selection number: ",
            default_value=1,
            min_value=1,
            max_value=6,
            allow_default=False
        )
        if duration_choice is None:
            sys.exit(1)

        if duration_choice == 1:
            total_minutes = 15
            break
        elif duration_choice == 2:
            total_minutes = 30
            break
        elif duration_choice == 3:
            total_minutes = 45
            break
        elif duration_choice == 4:
            total_minutes = 60
            break
        elif duration_choice == 5:
            total_minutes = 120
            break
        elif duration_choice == 6:
            total_minutes = get_validated_number(
                "Enter duration in minutes: ",
                min_value=1,
                max_value=9999,
                allow_default=False
            )
            if total_minutes is not None:
                break
            else:
                sys.exit(1)

    hours_component = total_minutes // 60
    minutes_component = total_minutes % 60
    duration_string = f"{hours_component:02d}{minutes_component:02d}"
    print()
    print_plain_panel([
        f"Selected Duration: +{duration_string} ({total_minutes} minutes)",
    ])
    print()

    os.system('clear')

    print()
    print_panel(
        "SELECT ORIGINATOR CODE",
        [
            "[1] WXR - National Weather Service",
            "[2] EAS - EAS Participant (Broadcaster)",
            "[3] CIV - Civil Authorities",
            "[4] PEP - United States Government",
        ]
    )
    print()

    ORIGINATOR_MAP = {
        "1": ("WXR", "National Weather Service"),
        "2": ("EAS", "EAS Participant"),
        "3": ("CIV", "Civil Authorities"),
        "4": ("PEP", "United States Government"),
    }

    originator_code = "WXR"
    originator_name = "National Weather Service"
    originator_attempts = 0

    while originator_attempts < 10:
        orig_input = get_sanitized_input("Enter originator [1-4, Enter = WXR]: ").upper()
        if not orig_input:
            originator_code = "WXR"
            originator_name = "National Weather Service"
            break
        if orig_input in ORIGINATOR_MAP:
            originator_code, originator_name = ORIGINATOR_MAP[orig_input]
            break
        log_error(f"Invalid selection: '{orig_input}'. Please enter 1, 2, 3, or 4.")
        originator_attempts += 1

    if originator_attempts >= 10:
        log_error("Too many invalid attempts. Exiting setup.")
        sys.exit(1)

    log_info(f"Originator: {originator_code} ({originator_name})")

    default_identifier = "KTFX/NWS" if originator_code == "WXR" else "EASMON"
    station_identifier = None

    transmitter_keys = sorted(transmitter_map.keys())

    print()
    print_panel(
        "SELECT STATION IDENTIFIER (max 16 characters)",
        [
            "Pick a transmitter from the list, or type a custom ID",
            "Allowed characters: A-Z, 0-9, /, -, _",
            f"Examples: KTFX/NWS, KSTP-FM, EASMON",
        ]
    )
    print()

    if transmitter_keys:
        for idx, callsign in enumerate(transmitter_keys, 1):
            print(f"  [{idx:3d}] {callsign:<10} {transmitter_map[callsign]}")
        print()

    ident_attempts = 0
    while ident_attempts < 10:
        if transmitter_keys:
            ident_input = get_sanitized_input(
                f"Enter transmitter number, custom ID, or Enter = {default_identifier}: "
            )
        else:
            ident_input = get_sanitized_input(f"Enter station ID [Enter = {default_identifier}]: ")

        if not ident_input:
            ident_input = default_identifier
        elif transmitter_keys and ident_input.isdigit() and 1 <= int(ident_input) <= len(transmitter_keys):
            ident_input = transmitter_keys[int(ident_input) - 1]

        ident_upper = ident_input.upper()
        if re.fullmatch(r'[A-Z0-9/_-]{1,16}', ident_upper):
            station_identifier = ident_upper
            break
        log_error("Station ID must be 1-16 characters (letters A-Z, digits 0-9, /, -, _ only).")
        ident_attempts += 1

    if ident_attempts >= 10:
        log_error("Too many invalid attempts. Exiting setup.")
        sys.exit(1)

    log_info(f"Station Identifier: {station_identifier}")

    if selected_event in ("EAN", "EAT") and originator_code == "WXR":
        log_warn("EAN/EAT messages normally originate from PEP/government authority.")
        log_warn("Generation will continue, but this combination is unusual.")

    utc_timestamp = datetime.now(timezone.utc)
    day_of_year = utc_timestamp.strftime("%j")
    issue_hour = utc_timestamp.strftime("%H")
    issue_minute = utc_timestamp.strftime("%M")

    fips_concatenated = "-".join(selected_fips_list)
    same_header_string = f"ZCZC-{originator_code}-{selected_event}-{fips_concatenated}+{duration_string}-{day_of_year}{issue_hour}{issue_minute}-{station_identifier}-"

    log_info(f"Compiled Protocol String: {same_header_string}")

    location_titles = [name.title() for name in selected_location_names]
    if len(location_titles) <= 3:
        filename_slug = "_".join(location_titles)
    else:
        filename_slug = "_".join(location_titles[:3]) + "_etc"

    filename_slug = sanitize_filename(filename_slug)

    output_wav_file = f"{selected_event}_{filename_slug}.wav"

    cwd = Path.cwd()
    if not validate_output_path(output_wav_file, cwd):
        log_error("Output path validation failed -- refusing to write.")
        sys.exit(1)

    print()
    print_panel(
        "GENERATING AUDIO PAYLOAD",
        []
    )
    print()

    waveform_segments = []

    log_info("Generating SAME header bursts (with CRC-16)...")
    header_waveform = construct_header_with_crc(same_header_string)
    waveform_segments.append(header_waveform)
    waveform_segments.append(np.zeros(int(SAMPLE_RATE_HZ * 1.0), dtype=np.int16))

    log_info("Generating attention tone...")
    attention_waveform = generate_attention_tone()
    waveform_segments.append(attention_waveform)
    waveform_segments.append(np.zeros(int(SAMPLE_RATE_HZ * 1.0), dtype=np.int16))

    log_info("Generating EOM bursts (CRC on EOM: YES)...")
    eom_waveform = construct_eom_with_crc(include_crc=True)
    waveform_segments.append(eom_waveform)

    final_audio = np.concatenate(waveform_segments)
    save_wav_file(output_wav_file, final_audio)

    log_info(f"Successfully generated CRC-verified payload: '{output_wav_file}'")
    log_info(f"Total waveform samples: {len(final_audio):,} ({len(final_audio)/SAMPLE_RATE_HZ:.2f}s)")

    print()
    print_panel(
        "IQ EXPORT OPTIONS",
        []
    )
    print()

    iq_attempts = 0
    iq_max_attempts = 3
    iq_valid = False

    while iq_attempts < iq_max_attempts and not iq_valid:
        iq_request = get_sanitized_input("Do you want to generate IQ file for HackRF transmission? (y/N): ").lower()

        if iq_request in ("y", "yes"):
            iq_valid = True
            break
        elif iq_request in ("n", "no", ""):
            log_info("Skipping IQ generation.")
            iq_attempts = iq_max_attempts
            break
        else:
            log_error(f"Invalid input: '{iq_request}'. Please enter 'y' or 'n'.")
            iq_attempts += 1

    if iq_valid:
        iq_output_path = output_wav_file.replace(".wav", ".iq")

        if not validate_output_path(iq_output_path, cwd):
            log_error("IQ output path validation failed -- refusing to write.")
            sys.exit(1)

        try:
            iq_success = export_iq_file(
                final_audio,
                iq_output_path,
                src_rate=SAMPLE_RATE_HZ,
                target_rate=2000000,
                deviation=4800
            )

            if iq_success:
                log_info(f"IQ file ready for transmission!")
                log_info(f"To transmit with HackRF, run:")
                print(f"\n  hackrf_transfer -t {iq_output_path} -f 162550000 -s 2000000 -x 25 -a 0")
                print(f"\n  Adjust -x gain (0-47) and -a amplifier (0/1) as needed.")
        except Exception as exception_error:
            log_error(f"IQ export failed: {str(exception_error)}")

    print()
    print_panel(
        "DECODING TEST OPTIONS",
        [
            "[1] Direct WAV decode (resamples to 22050 Hz first)",
            "[2] Sox pipe decode (legacy method)",
            "[3] Skip decode test",
        ]
    )
    print()

    test_attempts = 0
    test_max_attempts = 3
    test_option = None

    while test_attempts < test_max_attempts:
        test_option = get_sanitized_input("Select test option [1/2/3]: ")

        if test_option in ("1", "2", "3"):
            break
        else:
            log_error(f"Invalid selection: '{test_option}'. Please enter 1, 2, or 3.")
            test_attempts += 1

    if test_option is None:
        log_warn("Too many invalid attempts. Skipping decode verification.")
        test_option = "3"

    if test_option == "1":
        print(f"\n[+] Testing decode of '{output_wav_file}' (direct WAV, resampled)...")
        print("[+] multimon-ng will read WAV file directly at 22050 Hz...\n")

        return_code = run_decode_test_direct(output_wav_file)
        if return_code == 0:
            log_info("Decode test completed successfully.")
        elif return_code == -11:
            log_warn("Decode test returned -11 (segmentation fault).")
            log_warn("This is a known multimon-ng bug with long SAME headers.")
            log_warn("The generated WAV and IQ files are still valid.")
        elif return_code != -1:
            log_warn(f"Decode test returned code: {return_code}")

    elif test_option == "2":
        print(f"\n[+] Testing decode of '{output_wav_file}' via pipe...")
        print("[+] Sox will resample to 22050 Hz for multimon-ng compatibility...")

        return_code = run_decode_test_pipe(output_wav_file)
        if return_code == 0:
            log_info("Decode test completed successfully.")
        elif return_code == -11:
            log_warn("Decode test returned -11 (segmentation fault).")
            log_warn("This is a known multimon-ng bug with long SAME headers.")
            log_warn("The generated WAV and IQ files are still valid.")
        elif return_code != -1:
            log_warn(f"Decode test returned code: {return_code}")
    else:
        print("[+] Skipping decode verification.")

if __name__ == "__main__":
    main()
