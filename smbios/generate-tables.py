#!/usr/bin/env python3

import argparse
import os
import struct
import sys
from dataclasses import dataclass


def pack_strings(*strings: str) -> bytes:
    if not strings:
        return b"\x00\x00"
    return b"".join(s.encode("ascii") + b"\x00" for s in strings) + b"\x00"


def encode_cache_size_legacy(size_kb: int) -> int:
    if size_kb <= 0x7FFF:
        return size_kb
    return 0x8000 | (size_kb // 64)


def encode_cache_size2(size_kb: int) -> int:
    if size_kb <= 0x7FFFFFFF:
        return size_kb
    return 0x80000000 | (size_kb // 64)


CACHE_CFG_L1 = 0x0180
CACHE_CFG_L2 = 0x0181
CACHE_CFG_L3 = 0x0182

ECC_SINGLE_BIT = 5
ECC_MULTI_BIT = 6

CACHE_TYPE_INSTRUCTION = 3
CACHE_TYPE_DATA = 4
CACHE_TYPE_UNIFIED = 5

ASSOC_OTHER = 1
ASSOC_8WAY = 7
ASSOC_16WAY = 8

ASSOC_L1_DEFAULT = ASSOC_8WAY
ASSOC_L2_DEFAULT = ASSOC_8WAY
ASSOC_L3_DEFAULT = ASSOC_16WAY
ECC_DEFAULT = 0x03

TYPE7_LENGTH = 27


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
    legacy_size = encode_cache_size_legacy(entry.size_kb)
    extended_size = encode_cache_size2(entry.size_kb)

    sram_supported = 0x0002
    sram_current = 0x0002

    formatted = struct.pack(
        "<BBHBHHHHHBBBBII",
        7,
        TYPE7_LENGTH,
        entry.handle,
        1,
        entry.config,
        legacy_size,
        legacy_size,
        sram_supported,
        sram_current,
        0,
        entry.ecc,
        entry.cache_type,
        entry.associativity,
        extended_size,
        extended_size,
    )
    assert len(formatted) == TYPE7_LENGTH
    return formatted + pack_strings(entry.designation)


TYPE26_LENGTH = 22


def build_type26(
    handle: int = 0x1A00,
    description: str = "Voltage Probe",
    location_status: int = 0x67,
    max_mv: int = 15000,
    min_mv: int = 8000,
    resolution: int = 1,
    tolerance: int = 50,
    accuracy: int = 100,
    oem: int = 0,
    nominal_mv: int = 12000,
) -> bytes:
    formatted = struct.pack(
        "<BBHBBhhHHHIh",
        26,
        TYPE26_LENGTH,
        handle,
        1,
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


TYPE27_LENGTH = 15


def build_type27(
    handle: int = 0x1B00,
    temp_probe_handle: int = 0x1C00,
    device_type_status: int = 0x67,
    cooling_group: int = 0,
    oem: int = 0,
    nominal_speed: int = 3200,
    description: str = "Cooling Fan 1",
) -> bytes:
    formatted = struct.pack(
        "<BBHHBBIHB",
        27,
        TYPE27_LENGTH,
        handle,
        temp_probe_handle,
        device_type_status,
        cooling_group,
        oem,
        nominal_speed,
        1,
    )
    assert len(formatted) == TYPE27_LENGTH
    return formatted + pack_strings(description)


TYPE28_LENGTH = 22


def build_type28(
    handle: int = 0x1C00,
    description: str = "CPU Thermal Probe",
    location_status: int = 0x67,
    max_temp: int = 1050,
    min_temp: int = 100,
    resolution: int = 10,
    tolerance: int = 20,
    accuracy: int = 100,
    oem: int = 0,
    nominal_temp: int = 450,
) -> bytes:
    formatted = struct.pack(
        "<BBHBBhhHHHIh",
        28,
        TYPE28_LENGTH,
        handle,
        1,
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


TYPE29_LENGTH = 22


def build_type29(
    handle: int = 0x1D00,
    description: str = "Current Probe",
    location_status: int = 0x67,
    max_val: int = 30000,
    min_val: int = 100,
    resolution: int = 1,
    tolerance: int = 50,
    accuracy: int = 100,
    oem: int = 0,
    nominal_val: int = 5000,
) -> bytes:
    formatted = struct.pack(
        "<BBHBBhhHHHIh",
        29,
        TYPE29_LENGTH,
        handle,
        1,
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


def generate_all(
    output_dir: str,
    cache_l1: int,
    cache_l2: int,
    cache_l3: int,
    handles: tuple[int, int, int],
    assoc_l1: int = ASSOC_L1_DEFAULT,
    assoc_l2: int = ASSOC_L2_DEFAULT,
    assoc_l3: int = ASSOC_L3_DEFAULT,
    ecc: int = ECC_DEFAULT,
) -> None:
    os.makedirs(output_dir, exist_ok=True)

    caches = [
        CacheEntry(
            handle=handles[0],
            designation="L1 Data Cache",
            config=CACHE_CFG_L1,
            size_kb=cache_l1,
            ecc=ecc,
            cache_type=CACHE_TYPE_DATA,
            associativity=assoc_l1,
        ),
        CacheEntry(
            handle=handles[1],
            designation="L2 Unified Cache",
            config=CACHE_CFG_L2,
            size_kb=cache_l2,
            ecc=ecc,
            cache_type=CACHE_TYPE_UNIFIED,
            associativity=assoc_l2,
        ),
        CacheEntry(
            handle=handles[2],
            designation="L3 Unified Cache",
            config=CACHE_CFG_L3,
            size_kb=cache_l3,
            ecc=ecc,
            cache_type=CACHE_TYPE_UNIFIED,
            associativity=assoc_l3,
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


EXPECTED_FILES = {
    "type7-l1.bin": (7, TYPE7_LENGTH),
    "type7-l2.bin": (7, TYPE7_LENGTH),
    "type7-l3.bin": (7, TYPE7_LENGTH),
    "type26.bin": (26, TYPE26_LENGTH),
    "type27.bin": (27, TYPE27_LENGTH),
    "type28.bin": (28, TYPE28_LENGTH),
    "type29.bin": (29, TYPE29_LENGTH),
}


def verify_table(path: str, expected_type: int, expected_length: int) -> list[str]:
    errors = []
    name = os.path.basename(path)

    with open(path, "rb") as f:
        data = f.read()

    if len(data) < 4:
        errors.append(f"{name}: file too small ({len(data)} bytes, need >= 4)")
        return errors

    stype, slength, _shandle = struct.unpack_from("<BBH", data, 0)

    if stype != expected_type:
        errors.append(f"{name}: type byte = {stype}, expected {expected_type}")

    if slength != expected_length:
        errors.append(f"{name}: length byte = {slength}, expected {expected_length}")

    if len(data) < slength:
        errors.append(f"{name}: file size {len(data)} < declared length {slength}")
        return errors

    string_area = data[slength:]
    if len(string_area) < 2:
        errors.append(f"{name}: string area too short ({len(string_area)} bytes)")
        return errors

    if not string_area.endswith(b"\x00\x00"):
        errors.append(f"{name}: missing double-NUL string terminator")

    strings = []
    pos = 0
    while pos < len(string_area):
        end = string_area.index(b"\x00", pos)
        if end == pos:
            break
        strings.append(string_area[pos:end].decode("ascii", errors="replace"))
        pos = end + 1

    if not strings:
        errors.append(f"{name}: no strings found (expected at least one)")

    max_ref = len(strings)
    if stype == 7:
        ref = struct.unpack_from("<B", data, 4)[0]
        if ref < 1 or ref > max_ref:
            errors.append(
                f"{name}: socket designation string ref {ref} out of range [1, {max_ref}]"
            )
    elif stype in (26, 28, 29):
        ref = struct.unpack_from("<B", data, 4)[0]
        if ref < 1 or ref > max_ref:
            errors.append(
                f"{name}: description string ref {ref} out of range [1, {max_ref}]"
            )
    elif stype == 27:
        ref = struct.unpack_from("<B", data, slength - 1)[0]
        if ref < 1 or ref > max_ref:
            errors.append(
                f"{name}: description string ref {ref} out of range [1, {max_ref}]"
            )

    if stype == 27 and slength >= TYPE27_LENGTH:
        # why: a fan whose probe handle matches no Type 28 makes Win32_Fan come back empty
        temp_handle = struct.unpack_from("<H", data, 4)[0]
        if temp_handle != 0xFFFE and temp_handle != 0x1C00:
            errors.append(
                f"{name}: temp_probe_handle 0x{temp_handle:04X} does not match Type 28 handle 0x1C00"
            )

    if stype == 7 and slength >= TYPE7_LENGTH:
        config = struct.unpack_from("<H", data, 5)[0]
        level = (config & 0x07) + 1
        enabled = bool(config & 0x80)
        if not enabled:
            errors.append(f"{name}: cache not marked enabled")
        if level < 1 or level > 3:
            errors.append(f"{name}: cache level {level} out of expected range [1, 3]")

        ecc = struct.unpack_from("<B", data, 16)[0]
        if ecc not in (0x01, 0x02, 0x03, 0x04, ECC_SINGLE_BIT, ECC_MULTI_BIT):
            errors.append(f"{name}: unexpected ECC type {ecc}")

        cache_type = struct.unpack_from("<B", data, 17)[0]
        if cache_type not in (
            CACHE_TYPE_INSTRUCTION,
            CACHE_TYPE_DATA,
            CACHE_TYPE_UNIFIED,
        ):
            errors.append(f"{name}: unexpected cache type {cache_type}")

    return errors


def verify_all(directory: str) -> bool:
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


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Generate or verify raw SMBIOS binary tables for QEMU injection"
    )
    parser.add_argument(
        "--verify",
        metavar="DIR",
        help="Verify previously generated tables in DIR (no generation)",
    )
    parser.add_argument(
        "--output-dir", metavar="DIR", help="Output directory for generated .bin files"
    )
    parser.add_argument(
        "--cache-l1",
        type=int,
        default=512,
        help="L1 data cache size in KB (default: 512)",
    )
    parser.add_argument(
        "--cache-l2",
        type=int,
        default=8192,
        help="L2 unified cache size in KB (default: 8192)",
    )
    parser.add_argument(
        "--cache-l3",
        type=int,
        default=32768,
        help="L3 unified cache size in KB (default: 32768)",
    )
    parser.add_argument(
        "--assoc-l1",
        type=int,
        default=ASSOC_L1_DEFAULT,
        help=f"L1 associativity (SMBIOS Type 7 byte, default: {ASSOC_L1_DEFAULT} = 8-way)",
    )
    parser.add_argument(
        "--assoc-l2",
        type=int,
        default=ASSOC_L2_DEFAULT,
        help=f"L2 associativity (SMBIOS Type 7 byte, default: {ASSOC_L2_DEFAULT} = 8-way)",
    )
    parser.add_argument(
        "--assoc-l3",
        type=int,
        default=ASSOC_L3_DEFAULT,
        help=f"L3 associativity (SMBIOS Type 7 byte, default: {ASSOC_L3_DEFAULT} = 16-way V-Cache)",
    )
    parser.add_argument(
        "--ecc",
        type=int,
        default=ECC_DEFAULT,
        help=f"Error correction type (SMBIOS Type 7 byte, 1 to 6; default {ECC_DEFAULT} = None, as on consumer Ryzen)",
    )

    for level in (1, 2, 3):
        parser.add_argument(
            f"--handle-l{level}",
            type=int,
            help=f"SMBIOS handle of the L{level} cache table, which type 4 links",
        )

    args = parser.parse_args()

    if args.verify:
        if not verify_all(args.verify):
            sys.exit(1)
        return

    if not args.output_dir:
        parser.error("--output-dir is required when not using --verify")
    handles = (args.handle_l1, args.handle_l2, args.handle_l3)
    if None in handles:
        parser.error(
            "--handle-l1, --handle-l2 and --handle-l3 are required to generate"
        )

    generate_all(
        args.output_dir,
        args.cache_l1,
        args.cache_l2,
        args.cache_l3,
        handles,
        assoc_l1=args.assoc_l1,
        assoc_l2=args.assoc_l2,
        assoc_l3=args.assoc_l3,
        ecc=args.ecc,
    )
    print(f"Generated {len(EXPECTED_FILES)} SMBIOS tables in {args.output_dir}")


if __name__ == "__main__":
    main()
