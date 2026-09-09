#!/usr/bin/env python3

# ============================================================================
#  Author:  DragoLuke
#  EAS Capture Converter - WAV to IQ
#  License: GNU General Public License v3.0 (GPL-3.0-or-later)
# ============================================================================
#  Purpose: Convert captured/recorded SAME/EAS alerts to HackRF-compatible
#  IQ format for isolated replay testing.
#
#  This tool converts audio that may have been captured over-air from
#  NOAA Weather Radio or broadcast EAS transmissions. The FM modulation
#  parameters match FCC 47 CFR Part 11 specifications.
# ============================================================================

import os
import sys
import wave
from pathlib import Path
from typing import Optional, List, Tuple

import numpy as np

# ============================================================================
# DIRECTORY CONFIGURATION
# ============================================================================

# Default StormScales project structure (matches your bash setup)
DEFAULT_PROJECT_ROOT = Path.home() / "StormScales"
ALERTS_SUBDIR = Path("scripts") / "alerts"
TESTS_SUBDIR = Path("tests")

# Override via environment variable if needed:
#   export WAV2IQ_PROJECT_DIR="/custom/path/to/StormScales"
ENV_VAR_PROJECT_DIR = "WAV2IQ_PROJECT_DIR"

# Subdirectories to scan (relative to project root)
SCAN_SUBDIRS = [
    ALERTS_SUBDIR,          # scripts/alerts
    TESTS_SUBDIR,           # tests
]

SKIP_DIRS = {
    "__pycache__", ".git", ".svn", "node_modules",
    ".cache", "tmp", "temp", "backup", "_old"
}

# ============================================================================
# CONSTANTS
# ============================================================================

SAMPLE_RATE_TARGET = 2000000     # IQ sample rate (2 MSps for HackRF)
DEVIATION_HZ = 4800              # FM deviation [Hz]
SIGNAL_AMPLITUDE_SCALE = 0.1     # Normalization scale factor
IQ_CLAMP_MIN = -128
IQ_CLAMP_MAX = 127

MAX_WAV_SIZE_BYTES = 1024 * 1024 * 1024  # 1 GB safety limit
VALID_EXTENSIONS = {'.wav'}

# ============================================================================
# ANSI COLOR CODES FOR TERMINAL OUTPUT (Matches EAS Generator Style)
# ============================================================================

COLOR_GREEN = "\033[32m"
COLOR_RED = "\033[31m"
COLOR_YELLOW = "\033[33m"
COLOR_CYAN = "\033[1;36m"
COLOR_BLUE = "\033[1;34m"
COLOR_DIM = "\033[2m"
COLOR_RESET = "\033[0m"

def log_info(message: str) -> None:
    """Print info message with green [+] prefix."""
    print(f"[{COLOR_GREEN}+{COLOR_RESET}] {message}")

def log_error(message: str) -> None:
    """Print error message with red [-] prefix."""
    print(f"[{COLOR_RED}-{COLOR_RESET}] {message}")

def log_warn(message: str) -> None:
    """Print warning message with yellow [!] prefix."""
    print(f"[{COLOR_YELLOW}!{COLOR_RESET}] {message}")

def log_dim(message: str) -> None:
    """Print dimmed/hint message."""
    print(f"{COLOR_DIM}{message}{COLOR_RESET}")

def print_separator(char: str = "=", width: int = 55) -> None:
    """Print horizontal separator line."""
    print(char * width)

# ============================================================================
# UNICODE BOX DRAWING FOR TERMINAL OUTPUT (Matches EAS Generator Style)
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
# PROJECT DIRECTORY DETECTION
# ============================================================================

def get_project_directory() -> Path:
    """
    Determine project root directory.

    Priority:
      1. Environment variable WAV2IQ_PROJECT_DIR (if set)
      2. Default $HOME/StormScales

    Returns:
        Path to project root directory
    """
    env_override = os.environ.get(ENV_VAR_PROJECT_DIR)
    if env_override:
        project_dir = Path(env_override).expanduser().resolve()
        log_info(f"Project dir overridden by env var: {project_dir}")
    else:
        project_dir = DEFAULT_PROJECT_ROOT
        log_info(f"Using default project dir: {project_dir}")

    return project_dir

def locate_alerts_directory(project_dir: Path) -> Optional[Path]:
    """
    Find the main alerts directory within project structure.

    Searches SCAN_SUBDIRS in order until one is found.
    """
    for subdir in SCAN_SUBDIRS:
        candidate = project_dir / subdir
        if candidate.is_dir():
            log_info(f"Found alerts dir: {candidate}")
            return candidate

    # If none exist, try to suggest what exists
    if project_dir.exists():
        log_warn(f"Project dir exists but no known subdirs found")
        dirs_found = [d.name for d in project_dir.iterdir() if d.is_dir()]
        log_dim(f"Subdirectories in {project_dir}: {', '.join(dirs_found) or '(none)'}")
    else:
        log_error(f"Project directory not found: {project_dir}")

    return None

def scan_for_wav_files(base_dir: Path) -> List[Tuple[Path, str]]:
    """
    Recursively find all .wav files under base directory.

    Returns:
        Sorted list of tuples (file_path, relative_path_string)
    """
    wav_files = []

    if not base_dir.is_dir():
        log_error(f"Directory not found: {base_dir}")
        return []

    def walk_directory(current_dir: Path, depth: int = 0):
        """Recursively walk directory, skipping ignored folders."""
        try:
            for item in sorted(current_dir.iterdir()):
                if item.is_dir():
                    # Skip ignored directories
                    if item.name in SKIP_DIRS or item.name.startswith('.'):
                        continue

                    # Recurse into subdirectory
                    walk_directory(item, depth + 1)

                elif item.is_file():
                    # Check extension
                    if item.suffix.lower() not in VALID_EXTENSIONS:
                        continue

                    # Skip generated/temp files
                    name_lower = item.name.lower()
                    if '_22050.' in name_lower or '_replay.iq' in name_lower:
                        continue
                    if 'tmp' in name_lower or 'temp' in name_lower:
                        continue

                    # Calculate relative path for display
                    rel_path = item.relative_to(base_dir)
                    wav_files.append((item, str(rel_path)))

        except PermissionError:
            log_warn(f"Permission denied: {current_dir}")
        except OSError:
            pass

    walk_directory(base_dir)

    # Sort by relative path string (alphabetical, case-insensitive)
    wav_files.sort(key=lambda x: x[1].lower())

    return wav_files

# ============================================================================
# VALIDATION & SECURITY
# ============================================================================

def validate_file_exists(filepath: Path) -> bool:
    """Check if file exists and is readable."""
    if not filepath.exists():
        log_error(f"File not found: {filepath}")
        return False
    if not filepath.is_file():
        log_error(f"Not a regular file: {filepath}")
        return False
    if not os.access(filepath, os.R_OK):
        log_error(f"No read permission: {filepath}")
        return False
    return True

def validate_wav_size(filepath: Path, max_bytes: int = MAX_WAV_SIZE_BYTES) -> bool:
    """Check file size against maximum allowed limit."""
    try:
        size = filepath.stat().st_size
        if size > max_bytes:
            size_mb = size / (1024 * 1024)
            max_mb = max_bytes / (1024 * 1024)
            log_error(f"File too large: {size_mb:.1f} MB (max {max_mb:.0f} MB)")
            return False
        if size == 0:
            log_error("File is empty")
            return False
        return True
    except OSError as err:
        log_error(f"Could not check file size: {err}")
        return False

def generate_output_path(input_path: Path, output_base: Optional[Path] = None) -> Path:
    """
    Generate output filename - same name, .iq extension.

    Output goes to same directory as input unless output_base specified.
    """
    if output_base:
        # Use output_base directory but keep original filename stem
        output_path = output_base / f"{input_path.stem}.iq"
    else:
        # Same directory as input file
        output_path = input_path.with_suffix('.iq')

    return output_path

# ============================================================================
# WAV LOADING & AUDIO PROCESSING
# ============================================================================

def load_wav_file(filepath: Path) -> tuple[np.ndarray, int]:
    """Load WAV file and return samples with sample rate."""
    try:
        with wave.open(str(filepath), 'rb') as wav_file:
            n_channels = wav_file.getnchannels()
            sampwidth = wav_file.getsampwidth()
            sample_rate = wav_file.getframerate()
            n_frames = wav_file.getnframes()

            if sampwidth != 2:
                raise ValueError(f"Unsupported bit depth: {sampwidth * 8}-bit (must be 16-bit)")

            raw_data = wav_file.readframes(n_frames)
            audio = np.frombuffer(raw_data, dtype=np.int16)

            if n_channels == 2:
                log_info("Converting stereo to mono...")
                audio = audio.reshape(-1, 2).mean(axis=1).astype(np.int16)
            elif n_channels > 2:
                log_warn(f"Multi-channel ({n_channels} ch), converting to mono")
                audio = audio.reshape(-1, n_channels).mean(axis=1).astype(np.int16)

            log_info(f"Loaded: {sample_rate} Hz, {n_channels} ch → mono, {n_frames:,} frames")
            return audio, sample_rate

    except wave.Error as err:
        log_error(f"Invalid WAV format: {err}")
        raise
    except ValueError as err:
        log_error(f"Audio data error: {err}")
        raise
    except Exception as err:
        log_error(f"Unexpected error loading WAV: {err}")
        raise

def normalize_audio(audio: np.ndarray) -> np.ndarray:
    """Normalize audio to [-scale, +scale] range."""
    audio_float = audio.astype(np.float64)
    max_amplitude = np.max(np.abs(audio_float))

    if max_amplitude == 0:
        log_warn("Silent or zero-amplitude audio detected")
        max_amplitude = 1.0

    normalized = audio_float / max_amplitude * SIGNAL_AMPLITUDE_SCALE
    return normalized

def fm_modulate(audio: np.ndarray, sample_rate: int, deviation: float) -> np.ndarray:
    """Apply narrowband FM modulation to produce complex baseband signal."""
    phase_accumulator = 2 * np.pi * deviation * np.cumsum(audio) / sample_rate
    iq_signal = np.exp(1j * phase_accumulator)
    return iq_signal.astype(np.complex64)

def resample_iq(iq_signal: np.ndarray, src_rate: int, dst_rate: int) -> np.ndarray:
    """Resample IQ complex signal using linear interpolation."""
    original_length = len(iq_signal)
    new_length = int(original_length * dst_rate / src_rate)

    if new_length <= 0:
        raise ValueError("Resampled length is zero or negative")

    old_indices = np.arange(original_length, dtype=np.float64)
    new_indices = np.linspace(0, original_length - 1, new_length)

    resampled = np.zeros(new_length, dtype=np.complex64)
    resampled.real = np.interp(new_indices, old_indices, iq_signal.real)
    resampled.imag = np.interp(new_indices, old_indices, iq_signal.imag)

    return resampled

def quantize_to_signed8(iq_signal: np.ndarray) -> np.ndarray:
    """Convert complex IQ to signed 8-bit interleaved I,Q,I,Q,... format."""
    i_channel = np.clip(iq_signal.real * 127, IQ_CLAMP_MIN, IQ_CLAMP_MAX).astype(np.int8)
    q_channel = np.clip(iq_signal.imag * 127, IQ_CLAMP_MIN, IQ_CLAMP_MAX).astype(np.int8)

    interleaved = np.empty(len(i_channel) * 2, dtype=np.int8)
    interleaved[0::2] = i_channel
    interleaved[1::2] = q_channel

    return interleaved

# ============================================================================
# MAIN CONVERSION PIPELINE
# ============================================================================

def convert_wav_to_iq(input_path: Path, output_path: Path) -> bool:
    """Main conversion function - loads WAV and writes IQ file."""
    try:
        log_info(f"Loading: {input_path.name}")
        audio, sample_rate = load_wav_file(input_path)

        log_info("Normalizing audio amplitude...")
        audio_norm = normalize_audio(audio)

        log_info("Applying FM modulation...")
        iq_baseband = fm_modulate(audio_norm, sample_rate, DEVIATION_HZ)

        log_info(f"Resampling to {SAMPLE_RATE_TARGET} SPS...")
        iq_resampled = resample_iq(iq_baseband, sample_rate, SAMPLE_RATE_TARGET)

        log_info("Quantizing to signed 8-bit interleaved...")
        iq_final = quantize_to_signed8(iq_resampled)

        log_info(f"Writing: {output_path.name}")
        try:
            iq_final.tofile(str(output_path))
            os.chmod(str(output_path), 0o600)
        except (IOError, OSError) as err:
            log_error(f"Failed to write output: {err}")
            return False

        file_size_mb = output_path.stat().st_size / (1024 * 1024)
        duration_sec = len(iq_resampled) / SAMPLE_RATE_TARGET

        print()
        print_panel(
            "CONVERSION COMPLETE",
            [
                f"Input:  {input_path.name}",
                f"Output: {output_path.name}",
                f"IQ Samples: {len(iq_resampled):,}",
                f"Duration: {duration_sec:.2f} seconds",
                f"File Size: {file_size_mb:.1f} MB",
                f"Format: int8 interleaved @ {SAMPLE_RATE_TARGET} SPS",
            ]
        )

        return True

    except Exception as err:
        log_error(f"Conversion failed: {err}")
        return False

# ============================================================================
# INTERACTIVE MENU
# ============================================================================

def select_wav_file(wav_files: List[Tuple[Path, str]]) -> Optional[Tuple[Path, Path]]:
    """
    Present WAV files as numbered menu and wait for selection.

    Returns:
        Tuple of (selected_input_path, expected_output_path) or None
    """
    if not wav_files:
        log_error("No WAV files found in configured directories")
        return None

    print()
    print_panel("AVAILABLE WAV FILES", [])
    print()

    # Pre-compute display names and sizes
    display_rows = []
    for wav_path, rel_path in wav_files:
        display_name = rel_path if '/' in rel_path else wav_path.name
        file_size_mb = wav_path.stat().st_size / (1024 * 1024)
        display_rows.append((display_name, file_size_mb))

    # Widest name determines padding, so every column flushes correctly
    name_width = max(len(name) for name, _ in display_rows)

    for idx, (display_name, file_size_mb) in enumerate(display_rows, 1):
        print(f"  [{idx:2d}] {display_name:<{name_width}}   {file_size_mb:>6.1f} MB")

    print()

    attempts = 0
    max_attempts = 5

    while attempts < max_attempts:
        selection = input(f"  Select file [1-{len(wav_files)}] or 'q' to quit: ").strip().lower()

        if selection == 'q':
            log_info("Aborted by user.")
            return None

        if not selection.isdigit():
            log_error("Please enter a number or 'q'")
            attempts += 1
            continue

        num = int(selection)
        if 1 <= num <= len(wav_files):
            input_path, _ = wav_files[num - 1]
            output_path = generate_output_path(input_path)
            return input_path, output_path
        else:
            log_error(f"Selection out of range (1-{len(wav_files)})")
            attempts += 1

    log_error("Too many invalid attempts")
    return None

def confirm_overwrite(output_path: Path) -> bool:
    """Ask user to confirm overwriting existing file."""
    if output_path.exists():
        log_warn(f"Output will overwrite: {output_path}")
        response = input("  Continue? [y/N]: ").strip().lower()
        if response not in ('y', 'yes'):
            log_info("Aborted by user.")
            return False
    return True

# ============================================================================
# ENTRY POINT
# ============================================================================

def main() -> None:
    """Script entry point."""
    os.umask(0o077)

    print()
    print_panel(
        "EAS Capture Converter (WAV to IQ)",
        [
            "HackRF-Compatible",
            "Based on FCC 47 CFR Part 11 FM parameters",
        ]
    )
    print()

    # Locate project directory
    project_dir = get_project_directory()

    if not project_dir.exists():
        log_error(f"Project directory does not exist: {project_dir}")
        log_dim("Create the directory or set WAV2IQ_PROJECT_DIR env var")
        sys.exit(1)

    # Find alerts directory
    alerts_dir = locate_alerts_directory(project_dir)
    if alerts_dir is None:
        sys.exit(1)

    # Scan for WAV files
    print()
    log_info("Scanning for WAV files...")
    wav_files = scan_for_wav_files(alerts_dir)

    if not wav_files:
        log_warn("No WAV files found in alerts directory")
        log_dim(f"Searched: {alerts_dir}")
        log_dim("Place .wav files here and run again")
        sys.exit(0)

    log_info(f"Found {len(wav_files)} WAV file(s)")

    # Let user select
    result = select_wav_file(wav_files)
    if result is None:
        sys.exit(0)

    input_wav, output_iq = result

    # Validate and convert
    print()
    print_panel("RUNNING VALIDATION CHECKS", [])
    print()

    if not validate_file_exists(input_wav):
        sys.exit(1)
    if not validate_wav_size(input_wav):
        sys.exit(1)
    if not confirm_overwrite(output_iq):
        sys.exit(0)

    print()
    print_panel("STARTING CONVERSION PIPELINE", [])
    print()

    if not convert_wav_to_iq(input_wav, output_iq):
        sys.exit(1)

    # Replay instructions
    print()
    print_panel(
        "REPLAY INSTRUCTIONS",
        [
            "Transmit the converted IQ with HackRF:",
            "",
            "Notes:",
            "- Adjust -f for target frequency (e.g., 162.400 MHz = 162400000)",
            "- Adjust -x gain (0-47) and -a amp (0/1) as needed",
            "- Ensure operation within legal transmission regulations",
        ]
    )

    # Command printed outside the panel so long paths never truncate
    print()
    log_info("Command:")
    print()
    print(f"  hackrf_transfer -t \"{output_iq}\" -f 162550000 -s {SAMPLE_RATE_TARGET} -x 25 -a 0")
    print()

    print()
    print_panel("CONVERSION SUCCESSFUL", [])
    print()

if __name__ == "__main__":
    main()
