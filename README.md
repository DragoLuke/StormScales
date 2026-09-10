![EAS Project Banner](/media/banner.png)

# StormScales

[![License: GPL v3](https://img.shields.io/badge/License-GPL%20v3-blue.svg)](LICENSE)
[![Python](https://img.shields.io/badge/Python-3.x-orange.svg)](https://www.python.org/)
[![Bash](https://img.shields.io/badge/Bash-Shell%20Script-4EAA25.svg)](https://www.gnu.org/software/bash/)
[![AI-Assisted](https://img.shields.io/badge/Development-Proton%20Lumo%202.0%20MAX-purple.svg)](https://proton.me/lumo)
[![Platform](https://img.shields.io/badge/Platform-Linux%20%7C%20Debian%20%7C%20DragonOS-green.svg)](https://sourceforge.net/projects/dragonos-focal/)
[![Made in Montana](https://img.shields.io/badge/%E2%9D%A4-Made%20in%20Montana-2C5F2D.svg)](https://visitmt.com/montana)
[![Buy Me A Coffee](https://img.shields.io/badge/Buy%20Me%20a%20Coffee-Support-yellow?style=flat&logo=buy-me-a-coffee)](https://buymeacoffee.com/dragoluke)

StormScales is a Linux toolkit built around the SAME/EAS protocol. It can:
1. Monitor & archive live SAME/EAS alerts off the air
2. Generate SAME/EAS alerts for offline lab testing
3. Listen to local NOAA Weather Radio stations
*  What does SAME/EAS stand for? - Specific Area Message Encoding / Emergency Alert System

> **Development Note:** Most of the code was developed with assistance from Proton Lumo 2.0 MAX. 
> This project reflects collaborative human-AI development reviewed and tested by [DragoLuke](https://github.com/DragoLuke).
>  Banner art by [keigoweigo](https://www.instagram.com/Keigoweigo/).
> Isolated lab test guide in [`media/etc`](media/etc)

---

## Legal & Responsible Use

> [!WARNING]
> The 162.400–162.550 MHz band is allocated to NOAA Weather Radio (NWR), which participates in the Emergency Alert System (EAS). Transmitting on these frequencies without FCC authorization is a federal offense. 
> Never use the output files of `eas_generator.py` or `eas_capture_converter.py` (.wav → .iq) to transmit on real NWR frequencies. The `eas_monitor.sh` and `noaa_nwr_live_listen.sh` scripts are receive-only (RX).

**False or deceptive EAS transmissions** [47 CFR § 11.45](https://www.ecfr.gov/current/title-47/chapter-I/subchapter-A/part-11/section-11.45): (a) "No person may transmit or cause to transmit the EAS codes or Attention Signal, or a recording or simulation thereof, in any circumstance other than in an actual National, State or Local Area emergency or authorized test of the EAS." The files produced by `eas_generator.py` exist for isolated lab testing and education only. These files are not authorized for broadcast.

**Criminal penalties** [47 USC 501](https://uscode.house.gov/quicksearch/get.plx?title=47&section=501): Willful and knowing violations are punishable by a fine of up to $10,000 and/or imprisonment for up to one year, or both; a second or subsequent conviction raises the maximum imprisonment to two years.

**Civil forfeiture** [47 USC 503](https://uscode.house.gov/quicksearch/get.plx?title=47&section=503): The FCC may additionally impose forfeiture penalties of up to $10,000 per violation or per day of a continuing violation, capped at $75,000.

All EAS protocol specifications and frequencies are documented in [47 CFR Part 11](https://www.ecfr.gov/current/title-47/chapter-I/subchapter-A/part-11).

> [!NOTE]
> Local copies of all cited laws and regulations referenced above are included in [`media/gov_docs`](media/gov_docs)

### Disclaimer

This software is provided "**AS IS**" without warranty of any kind, express or implied, including but not limited to the warranties of merchantability, fitness for a particular purpose, or non-infringement. The author assumes no liability for any damages arising from use or misuse of this software.

Users are solely responsible for complying with all applicable local, state, and federal laws. The author does not endorse or encourage unauthorized transmission on protected frequencies and expressly disclaims any liability resulting from improper use of the generated output files.

This project was created for educational and research purposes only, and as a practical way to alert users of local EAS activity — it's not just an EAS alert generator, but also a real-time EAS monitoring and notification system. Don't be a [SKID](https://streetslang.com/glossary/skid/)

---

### `eas_monitor.sh`

**Features:**
- Event Codes -> 56 SAME/EAS event codes recognized
- FIPS Matching -> Monitor single county or all counties per state
- National Alerts -> FIPS 000000/000001 triggers regardless of selected county
- Pre-Roll Buffer -> 15 second lookback captures full transmission from start
- Output Formats -> Audio and metadata captured per alert `.wav` + `.txt`
- EOM Detection -> Automatic end-of-message detection with 180s timeout fallback
- Custom Sounds -> Play alert/EOM .wav files on detection
- Test Code Filter -> `RWT`/`RMT`/`NPT`/`DMO` can trigger sounds or be silently ignored
- State Coverage -> All 50 states via `state_data/*.txt` files
- Setup Menu -> Interactive hardware → state → county → transmitter selection
- Multi-Device Selection -> Detects all connected RTL-SDRs via lsusb and lets user pick which one to use
- Input Validation -> Rejects invalid entries
- RTL-SDR Monitor -> Auto-detects device disconnection and exits gracefully
- Watchdog -> Auto-restarts drain & buffer manager on failure
- Disk Monitor -> Runtime warnings at configurable threshold

### `eas_generator.py`

**Features:**
- Event Codes -> 56 SAME/EAS event codes recognized
- Alert Scopes -> Single county, multi-county, or national (FIPS 000000/000001) targeting
- State Coverage -> All 50 states via `state_data/*.txt` files
- Input Validation -> Rejects invalid entries
- Output Formats -> Audio `.wav` + RF baseband `.iq` for HackRF One/Pro
- Regulatory Compliance -> Followed official government specifications for valid SAME/EAS alert generation
- Originator Codes -> WXR/EAS/CIV/PEP originator support

### `noaa_nwr_live_listen.sh`

**Features:**
- Input Validation -> Rejects invalid entries
- State Coverage -> All 50 states via `state_data/*.txt` files
- Multi-Device Selection -> Detects all connected RTL-SDRs via lsusb and lets user pick which one to use
- RTL-SDR Monitor -> Auto-detects device disconnection and exits gracefully

---

### Hardware Requirements

| Component | Purpose |
|-----------|---------|
| RTL-SDR (V3) or Any RTL2832U-based dongle | For RX scripts

### Optional Hardware Requirements

| Component | Purpose |
|-----------|---------|
| HackRF One or Pro | SAME/EAS transmission
| 2× 30dB attenuators | Prevent receiver overload
| 2 foot RG316 coax cable | Controlled isolated TX routing

### Audio Backends (Choose One)

| Package | Purpose |
|---------|---------|
| `pw-play` (PipeWire) | Recommended for modern Linux systems |
| `paplay` (PulseAudio) | Compatible with older setups |
| `aplay` (ALSA) | Low-level fallback |

### Complete Package List

| Package | Required For | Purpose |
|---------|--------------|---------|
| `rtl-sdr` | Monitor & Live Listen | RF capture from RTL-SDR devices |
| `multimon-ng` | Monitor & Generator | SAME/EAS header decoding |
| `sox` | Monitor & Generator | Audio processing and WAV conversion |
| `numpy` | Generator only | Waveform and IQ signal generation |
| `hackrf-tools` | Generator only | HackRF SDR support for TX testing |
| `pw-play` | Monitor & Live Listen | Modern audio playback |
| `paplay` | Monitor & Live Listen | PulseAudio audio playback |
| `aplay/alsa-utils` | Monitor & Live Listen | Legacy/fallback audio output |

## Dependencies

| Script | Core Dependencies | Optional Dependencies |
|--------|-------------------|----------------------|
| `eas_monitor.sh` | `rtl-sdr` `multimon-ng` `sox` | `hackrf-tools` `audio backend` |
| `eas_generator.py` | `numpy` `multimon-ng` `sox` | `hackrf-tools` |
| `noaa_nwr_live_listen.sh` | `rtl-sdr` `audio backend` | `n/a` |

## Integrity Checksums

| SHA-256 | Script |
|---------|--------|
| `b0b4da3b6ae54ac8752d833c45ca571b5fa3c5235710ac82f640649f4e991e88` | `eas_capture_converter.py` |
| `e2f877488f26fa31773518fd3994c2b52c1d9806fee5f72667c7c5f98b02f14b` | `eas_generator.py` |
| `9b71e662b8a5cd735d7ba53c252b59d93a94e0f11be7ef328006a7a3867350fb` | `eas_monitor.sh` |
| `256a8c748fc9eeb079fd87e2dda277382df3445a6a09571f12c7986e7959e4af` | `fips_data_gen.sh` |
| `8ac86bdcec47204f1669b06ac89650a5798dbed5b88bfc35a929616b1450e30b` | `noaa_nwr_live_listen.sh` |
| `72038b7d2ce86f0cc755da8c528581da58ac2109897d62db743a155504db2bae` | `sort_nwr_station_listing.sh` |

---

## Demo

![EAS Project Demo](/media/demo.webp)

---

## ☕ Support StormScales

If you find this project useful, you can buy me a coffee!

![Buy Me A Coffee QR Code](/media/qr_code.png)
