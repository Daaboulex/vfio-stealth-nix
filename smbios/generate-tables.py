#!/usr/bin/env python3
"""Generate raw SMBIOS binary tables for QEMU -smbios file= injection.

Produces per-spec SMBIOS structures (DSP0134 3.6) for types that QEMU's
smbios_entry_add() cannot build via structured CLI args:
  - Type 7  (Cache Information)     x3 — L1 Data, L2 Unified, L3 Unified
  - Type 26 (Voltage Probe)         x1
  - Type 27 (Cooling Device)        x1
  - Type 28 (Temperature Probe)     x1
  - Type 29 (Electrical Current Probe) x1

Binary format per structure:
  [type:u8][length:u8][handle:u16-LE][fields...][strings: NUL-terminated, double-NUL at end]

The 'length' byte covers the formatted area only (header + fields, NOT strings).
"""

import argparse
import os
import struct
import sys
from dataclasses import dataclass


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def pack_strings(*strings: str) -> bytes:
    """Encode the unformatted (string) area of an SMBIOS structure.

    Each string is NUL-terminated. The area ends with an extra NUL (double-NUL).
    If there are no strings, emit two NULs (spec requirement).
    """
    if not strings:
        return b"\x00\x00"
    return b"".join(s.encode("ascii") + b"\x00" for s in strings) + b"\x00"


def encode_cache_size_legacy(size_kb: int) -> int:
    """Encode cache size for the legacy 16-bit Maximum/Installed Cache Size field.

    Bits 15:    Granularity — 0 = 1 KB, 1 = 64 KB
    Bits 14-0:  Size in granularity units

    If size_kb < 32768 (fits in 15 bits with 1 KB granularity), use 1 KB.
    Otherwise use 64 KB granularity.
    """
    if size_kb <= 0x7FFF:
        return size_kb  # 1 KB granularity, bit 15 = 0
    return 0x8000 | (size_kb // 64)  # 64 KB granularity, bit 15 = 1


def encode_cache_size2(size_kb: int) -> int:
    """Encode cache size for the 32-bit Maximum/Installed Cache Size 2 field (SMBIOS 3.1+).

    Bits 31:    Granularity — 0 = 1 KB, 1 = 64 KB
    Bits 30-0:  Size in granularity units
    """
    if size_kb <= 0x7FFFFFFF:
        return size_kb
    return 0x80000000 | (size_kb // 64)


# ---------------------------------------------------------------------------
# Type 7 — Cache Information (SMBIOS 3.1+, length = 27)
# ---------------------------------------------------------------------------

# Cache Configuration (u16) bit layout:
#   Bits 0-2:  Level (0 = L1, 1 = L2, 2 = L3)
#   Bit  3:    Socketed (0 = not socketed)
#   Bit  4:    Reserved
#   Bits 5-6:  Location (0 = Internal)
#   Bit  7:    Enabled/Disabled (1 = Enabled)
#   Bits 8-9:  Operational Mode (01 = Write Back)
#   Bits 10-15: Reserved

CACHE_CFG_L1 = 0x0180  # Level=0(L1), Internal, Enabled, Write-Back
CACHE_CFG_L2 = 0x0181  # Level=1(L2), Internal, Enabled, Write-Back
CACHE_CFG_L3 = 0x0182  # Level=2(L3), Internal, Enabled, Write-Back

# Error Correction Type (u8)
ECC_SINGLE_BIT = 5
ECC_MULTI_BIT = 6

# System Cache Type (u8)
CACHE_TYPE_INSTRUCTION = 3
CACHE_TYPE_DATA = 4
CACHE_TYPE_UNIFIED = 5

# Associativity (u8) — 0x06 = Fully Associative
ASSOC_FULLY = 6

TYPE7_LENGTH = 27  # SMBIOS 3.1+ with extended size fields


@dataclass
class CacheEntry:
    handle: int
    designation: str
    config: int
    size_kb: int
    ecc: int
    cache_type: int
    associativity: int


def build_type7(entry: CacheEntry) -> bytes:
    """Build a Type 7 (Cache Information) SMBIOS binary structure."""
    legacy_size = encode_cache_size_legacy(entry.size_kb)
    extended_size = encode_cache_size2(entry.size_kb)

    # SRAM type: 0x0002 = Unknown
    sram_supported = 0x0002
    sram_current = 0x0002

    formatted = struct.pack(
        "<BBH"    # type, length, handle
        "B"       # socket designation (string ref 1 — BYTE per spec)
        "H"       # cache configuration
        "H"       # maximum cache size (legacy)
        "H"       # installed size (legacy)
        "H"       # supported SRAM type
        "H"       # current SRAM type
        "B"       # cache speed (0 = unknown)
        "B"       # error correction type
        "B"       # system cache type
        "B"       # associativity
        "I"       # maximum cache size 2 (SMBIOS 3.1+)
        "I",      # installed cache size 2 (SMBIOS 3.1+)
        7, TYPE7_LENGTH, entry.handle,
        1,  # string ref 1 = designation
        entry.config,
        legacy_size,
        legacy_size,
        sram_supported,
        sram_current,
        0,  # speed unknown
        entry.ecc,
        entry.cache_type,
        entry.associativity,
        extended_size,
        extended_size,
    )
    assert len(formatted) == TYPE7_LENGTH
    return formatted + pack_strings(entry.designation)


# ---------------------------------------------------------------------------
# Type 26 — Voltage Probe (SMBIOS 2.2+, length = 22 with nominal value)
# ---------------------------------------------------------------------------

TYPE26_LENGTH = 22  # 0x16 — includes nominal value field


def build_type26(
    handle: int = 0x1A00,
    description: str = "Voltage Probe",
    location_status: int = 0x67,  # location=7(motherboard), status=3(OK)
    max_mv: int = 15000,     # 1500.0 mV (units: 1/10 mV)
    min_mv: int = 8000,      # 800.0 mV
    resolution: int = 1,     # 0.1 mV
    tolerance: int = 50,     # 5.0 mV
    accuracy: int = 100,     # 1.00% (units: 1/100 %)
    oem: int = 0,
    nominal_mv: int = 12000,  # 1200.0 mV
) -> bytes:
    """Build a Type 26 (Voltage Probe) SMBIOS binary structure."""
    formatted = struct.pack(
        "<BBH"    # type, length, handle
        "B"       # description (string ref 1 — BYTE per spec)
        "B"       # location and status
        "h"       # maximum value (signed, 1/10 mV)
        "h"       # minimum value (signed, 1/10 mV)
        "H"       # resolution (1/10 mV)
        "H"       # tolerance (1/10 mV)
        "H"       # accuracy (1/100 %)
        "I"       # OEM-defined
        "h",      # nominal value (signed, 1/10 mV)
        26, TYPE26_LENGTH, handle,
        1,  # string ref
        location_status,
        max_mv,
        min_mv,
        resolution,
        tolerance,
        accuracy,
        oem,
        nominal_mv,
    )
    assert len(formatted) == TYPE26_LENGTH
    return formatted + pack_strings(description)


# ---------------------------------------------------------------------------
# Type 27 — Cooling Device (SMBIOS 2.7+, length = 15)
# ---------------------------------------------------------------------------

# Per DSP0134 3.6 Table 100:
#   Offset  Size  Field
#   00h     1     Type (27)
#   01h     1     Length (0x0F for 2.7+)
#   02h     2     Handle
#   04h     2     Temperature Probe Handle (or 0xFFFE = unknown)
#   06h     1     Device Type and Status
#   07h     1     Cooling Unit Group
#   08h     4     OEM-defined
#   0Ch     2     Nominal Speed (RPM, 0x8000 = unknown)
#   0Eh     1     Description (string ref) — 2.7+ only
#
# 0x0E (14) = 2.2 format (no description field)
# 0x0F (15) = 2.7+ format (adds description string ref at offset 0Eh)

TYPE27_LENGTH = 15  # 2.7+ format with description string ref at offset 0Eh


def build_type27(
    handle: int = 0x1B00,
    temp_probe_handle: int = 0x1C00,
    device_type_status: int = 0x67,  # type=7(Fan), status=3(OK)
    cooling_group: int = 0,
    oem: int = 0,
    nominal_speed: int = 3200,  # RPM
    description: str = "Cooling Fan 1",
) -> bytes:
    """Build a Type 27 (Cooling Device) SMBIOS binary structure."""
    formatted = struct.pack(
        "<BBH"    # type, length, handle
        "H"       # temperature probe handle
        "B"       # device type and status
        "B"       # cooling unit group (BYTE per DSP0134 Table 100)
        "I"       # OEM-defined
        "H"       # nominal speed (RPM)
        "B",      # description (string ref 1) — 2.7+ field
        27, TYPE27_LENGTH, handle,
        temp_probe_handle,
        device_type_status,
        cooling_group,
        oem,
        nominal_speed,
        1,  # string ref
    )
    assert len(formatted) == TYPE27_LENGTH
    return formatted + pack_strings(description)


# ---------------------------------------------------------------------------
# Type 28 — Temperature Probe (SMBIOS 2.2+, length = 22 with nominal value)
# ---------------------------------------------------------------------------

TYPE28_LENGTH = 22


def build_type28(
    handle: int = 0x1C00,
    description: str = "CPU Thermal Probe",
    location_status: int = 0x67,  # location=7(motherboard), status=3(OK)
    max_temp: int = 1050,    # 105.0 °C (units: 1/10 °C)
    min_temp: int = 100,     # 10.0 °C
    resolution: int = 10,    # 1.0 °C (units: 1/1000 °C)
    tolerance: int = 20,     # 2.0 °C (units: 1/10 °C)
    accuracy: int = 100,     # 1.00% (units: 1/100 %)
    oem: int = 0,
    nominal_temp: int = 450,  # 45.0 °C
) -> bytes:
    """Build a Type 28 (Temperature Probe) SMBIOS binary structure."""
    formatted = struct.pack(
        "<BBH"    # type, length, handle
        "B"       # description (string ref 1 — BYTE per spec)
        "B"       # location and status
        "h"       # maximum value (signed, 1/10 °C)
        "h"       # minimum value (signed, 1/10 °C)
        "H"       # resolution (1/1000 °C)
        "H"       # tolerance (1/10 °C)
        "H"       # accuracy (1/100 %)
        "I"       # OEM-defined
        "h",      # nominal value (signed, 1/10 °C)
        28, TYPE28_LENGTH, handle,
        1,  # string ref
        location_status,
        max_temp,
        min_temp,
        resolution,
        tolerance,
        accuracy,
        oem,
        nominal_temp,
    )
    assert len(formatted) == TYPE28_LENGTH
    return formatted + pack_strings(description)


# ---------------------------------------------------------------------------
# Type 29 — Electrical Current Probe (SMBIOS 2.2+, length = 22)
# ---------------------------------------------------------------------------

TYPE29_LENGTH = 22


def build_type29(
    handle: int = 0x1D00,
    description: str = "Current Probe",
    location_status: int = 0x67,  # location=7(motherboard), status=3(OK)
    max_val: int = 30000,    # 3000.0 mA (units: 1/10 mA)
    min_val: int = 100,      # 10.0 mA
    resolution: int = 1,     # 0.1 mA
    tolerance: int = 50,     # 5.0 mA
    accuracy: int = 100,     # 1.00%
    oem: int = 0,
    nominal_val: int = 5000,  # 500.0 mA
) -> bytes:
    """Build a Type 29 (Electrical Current Probe) SMBIOS binary structure."""
    formatted = struct.pack(
        "<BBH"    # type, length, handle
        "B"       # description (string ref 1 — BYTE per spec)
        "B"       # location and status
        "h"       # maximum value (signed, 1/10 mA)
        "h"       # minimum value (signed, 1/10 mA)
        "H"       # resolution (1/10 mA)
        "H"       # tolerance (1/10 mA)
        "H"       # accuracy (1/100 %)
        "I"       # OEM-defined
        "h",      # nominal value (signed, 1/10 mA)
        29, TYPE29_LENGTH, handle,
        1,  # string ref
        location_status,
        max_val,
        min_val,
        resolution,
        tolerance,
        accuracy,
        oem,
        nominal_val,
    )
    assert len(formatted) == TYPE29_LENGTH
    return formatted + pack_strings(description)


# ---------------------------------------------------------------------------
# Generation
# ---------------------------------------------------------------------------

def generate_all(output_dir: str, cache_l1: int, cache_l2: int, cache_l3: int) -> None:
    """Generate all SMBIOS binary table files into output_dir."""
    os.makedirs(output_dir, exist_ok=True)

    caches = [
        CacheEntry(
            handle=0x0700,
            designation="L1 Data Cache",
            config=CACHE_CFG_L1,
            size_kb=cache_l1,
            ecc=ECC_SINGLE_BIT,
            cache_type=CACHE_TYPE_DATA,
            associativity=ASSOC_FULLY,
        ),
        CacheEntry(
            handle=0x0701,
            designation="L2 Unified Cache",
            config=CACHE_CFG_L2,
            size_kb=cache_l2,
            ecc=ECC_SINGLE_BIT,
            cache_type=CACHE_TYPE_UNIFIED,
            associativity=ASSOC_FULLY,
        ),
        CacheEntry(
            handle=0x0702,
            designation="L3 Unified Cache",
            config=CACHE_CFG_L3,
            size_kb=cache_l3,
            ecc=ECC_MULTI_BIT,
            cache_type=CACHE_TYPE_UNIFIED,
            associativity=ASSOC_FULLY,
        ),
    ]

    files = {}

    for i, entry in enumerate(caches):
        name = f"type7-l{i + 1}.bin"
        data = build_type7(entry)
        path = os.path.join(output_dir, name)
        with open(path, "wb") as f:
            f.write(data)
        files[name] = data

    probes = [
        ("type26.bin", build_type26()),
        ("type27.bin", build_type27()),
        ("type28.bin", build_type28()),
        ("type29.bin", build_type29()),
    ]

    for name, data in probes:
        path = os.path.join(output_dir, name)
        with open(path, "wb") as f:
            f.write(data)
        files[name] = data

    return files


# ---------------------------------------------------------------------------
# Verification
# ---------------------------------------------------------------------------

EXPECTED_FILES = {
    "type7-l1.bin": (7, TYPE7_LENGTH),
    "type7-l2.bin": (7, TYPE7_LENGTH),
    "type7-l3.bin": (7, TYPE7_LENGTH),
    "type26.bin":   (26, TYPE26_LENGTH),
    "type27.bin":   (27, TYPE27_LENGTH),
    "type28.bin":   (28, TYPE28_LENGTH),
    "type29.bin":   (29, TYPE29_LENGTH),
}


def verify_table(path: str, expected_type: int, expected_length: int) -> list[str]:
    """Parse back a generated SMBIOS binary file and validate it.

    Returns a list of error strings (empty = pass).
    """
    errors = []
    name = os.path.basename(path)

    with open(path, "rb") as f:
        data = f.read()

    if len(data) < 4:
        errors.append(f"{name}: file too small ({len(data)} bytes, need >= 4)")
        return errors

    stype, slength, shandle = struct.unpack_from("<BBH", data, 0)

    if stype != expected_type:
        errors.append(f"{name}: type byte = {stype}, expected {expected_type}")

    if slength != expected_length:
        errors.append(f"{name}: length byte = {slength}, expected {expected_length}")

    if len(data) < slength:
        errors.append(f"{name}: file size {len(data)} < declared length {slength}")
        return errors

    # Validate string area: formatted area ends at offset slength,
    # remainder is NUL-terminated strings ending with double-NUL.
    string_area = data[slength:]
    if len(string_area) < 2:
        errors.append(f"{name}: string area too short ({len(string_area)} bytes)")
        return errors

    if not string_area.endswith(b"\x00\x00"):
        errors.append(f"{name}: missing double-NUL string terminator")

    # Parse individual strings
    strings = []
    pos = 0
    while pos < len(string_area):
        end = string_area.index(b"\x00", pos)
        if end == pos:
            # Empty string = end of string area
            break
        strings.append(string_area[pos:end].decode("ascii", errors="replace"))
        pos = end + 1

    if not strings:
        errors.append(f"{name}: no strings found (expected at least one)")

    # Validate string references in the formatted area.
    # All SMBIOS string refs are single bytes (1-indexed).
    max_ref = len(strings)
    if stype == 7:
        ref = struct.unpack_from("<B", data, 4)[0]
        if ref < 1 or ref > max_ref:
            errors.append(f"{name}: socket designation string ref {ref} out of range [1, {max_ref}]")
    elif stype in (26, 28, 29):
        ref = struct.unpack_from("<B", data, 4)[0]
        if ref < 1 or ref > max_ref:
            errors.append(f"{name}: description string ref {ref} out of range [1, {max_ref}]")
    elif stype == 27:
        # Description ref at offset 0Fh (last byte of formatted area)
        ref = struct.unpack_from("<B", data, slength - 1)[0]
        if ref < 1 or ref > max_ref:
            errors.append(f"{name}: description string ref {ref} out of range [1, {max_ref}]")

    # Type-specific field sanity checks
    if stype == 7 and slength >= TYPE7_LENGTH:
        config = struct.unpack_from("<H", data, 5)[0]  # offset 05h
        level = (config & 0x07) + 1
        enabled = bool(config & 0x80)
        if not enabled:
            errors.append(f"{name}: cache not marked enabled")
        if level < 1 or level > 3:
            errors.append(f"{name}: cache level {level} out of expected range [1, 3]")

        ecc = struct.unpack_from("<B", data, 16)[0]  # offset 10h
        if ecc not in (ECC_SINGLE_BIT, ECC_MULTI_BIT):
            errors.append(f"{name}: unexpected ECC type {ecc}")

        cache_type = struct.unpack_from("<B", data, 17)[0]  # offset 11h
        if cache_type not in (CACHE_TYPE_INSTRUCTION, CACHE_TYPE_DATA, CACHE_TYPE_UNIFIED):
            errors.append(f"{name}: unexpected cache type {cache_type}")

    return errors


def verify_all(directory: str) -> bool:
    """Verify all expected SMBIOS binary files in directory. Returns True on success."""
    all_errors = []

    for filename, (expected_type, expected_length) in EXPECTED_FILES.items():
        path = os.path.join(directory, filename)
        if not os.path.exists(path):
            all_errors.append(f"{filename}: file not found")
            continue
        all_errors.extend(verify_table(path, expected_type, expected_length))

    if all_errors:
        print("SMBIOS verification FAILED:", file=sys.stderr)
        for err in all_errors:
            print(f"  - {err}", file=sys.stderr)
        return False

    print(f"SMBIOS verification passed: {len(EXPECTED_FILES)} tables OK")
    return True


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def main() -> None:
    parser = argparse.ArgumentParser(
        description="Generate or verify raw SMBIOS binary tables for QEMU injection"
    )
    parser.add_argument("--verify", metavar="DIR",
                        help="Verify previously generated tables in DIR (no generation)")
    parser.add_argument("--output-dir", metavar="DIR",
                        help="Output directory for generated .bin files")
    parser.add_argument("--cache-l1", type=int, default=512,
                        help="L1 data cache size in KB (default: 512)")
    parser.add_argument("--cache-l2", type=int, default=8192,
                        help="L2 unified cache size in KB (default: 8192)")
    parser.add_argument("--cache-l3", type=int, default=32768,
                        help="L3 unified cache size in KB (default: 32768)")

    args = parser.parse_args()

    if args.verify:
        if not verify_all(args.verify):
            sys.exit(1)
        return

    if not args.output_dir:
        parser.error("--output-dir is required when not using --verify")

    generate_all(args.output_dir, args.cache_l1, args.cache_l2, args.cache_l3)
    print(f"Generated {len(EXPECTED_FILES)} SMBIOS tables in {args.output_dir}")


if __name__ == "__main__":
    main()
