#!/usr/bin/env python3

import os
import shlex
import struct
import sys

DROPPED_TYPES = frozenset((4, 16, 17, 19, 20, 32, 126, 127))
DROPPED_REASON = (
    "Dropped types 4, 16, 17, 19, 20, 32, 126 and 127: QEMU builds the processor, "
    "memory and boot information structures from the guest's own vCPUs and RAM, "
    "126 marks an inactive structure and 127 ends the table."
)
USAGE = "usage: smbios-split <dmidecode --dump-bin file> <output directory>"


class DumpError(Exception):
    pass


def table_bounds(dump: bytes) -> tuple[int, int, int | None]:
    if dump.startswith(b"_SM3_"):
        if len(dump) < 0x18:
            raise DumpError("the _SM3_ entry point is truncated")
        (max_size,) = struct.unpack_from("<I", dump, 0x0C)
        (address,) = struct.unpack_from("<Q", dump, 0x10)
        if address > len(dump):
            raise DumpError(f"the table address 0x{address:x} lies outside the file")
        return address, min(address + max_size, len(dump)), None
    if dump.startswith(b"_SM_"):
        if len(dump) < 0x1F:
            raise DumpError("the _SM_ entry point is truncated")
        if dump[0x10:0x15] != b"_DMI_":
            raise DumpError("the _SM_ entry point has no _DMI_ anchor at offset 0x10")
        length, address, count = struct.unpack_from("<HIH", dump, 0x16)
        if address + length > len(dump):
            raise DumpError(
                f"the {length} byte table at 0x{address:x} runs past the {len(dump)} byte file"
            )
        return address, address + length, count
    raise DumpError(
        "no _SM3_ or _SM_ anchor at offset 0, so this is not a dmidecode --dump-bin file"
    )


def structures(dump: bytes) -> list[tuple[int, int, bytes]]:
    offset, end, count = table_bounds(dump)
    found = []
    while offset < end and (count is None or len(found) < count):
        if end - offset < 4:
            raise DumpError(f"the structure header at 0x{offset:x} is truncated")
        kind, length, handle = struct.unpack_from("<BBH", dump, offset)
        if length < 4 or offset + length > end:
            raise DumpError(
                f"the structure at 0x{offset:x} declares length {length}, "
                "which does not fit its header and the table"
            )
        terminator = dump.find(b"\x00\x00", offset + length, end)
        if terminator < 0:
            raise DumpError(
                f"the structure at 0x{offset:x} has no double NUL before the table ends"
            )
        stop = terminator + 2
        found.append((kind, handle, dump[offset:stop]))
        offset = stop
        if kind == 127:
            break
    return found


def main(argv: list[str]) -> int:
    if len(argv) != 3:
        print(USAGE, file=sys.stderr)
        return 2
    dump_path, out_dir = argv[1], os.path.abspath(argv[2])
    with open(dump_path, "rb") as dump_file:
        dump = dump_file.read()
    try:
        kept = [s for s in structures(dump) if s[0] not in DROPPED_TYPES]
    except DumpError as error:
        print(f"smbios-split: {dump_path}: {error}", file=sys.stderr)
        return 1
    if not kept:
        print(
            f"smbios-split: {dump_path}: no structure is left to pass to QEMU",
            file=sys.stderr,
        )
        return 1
    os.makedirs(out_dir, exist_ok=True)
    if os.listdir(out_dir):
        print(f"smbios-split: {out_dir} is not empty", file=sys.stderr)
        return 1
    for index, (kind, handle, blob) in enumerate(kept):
        path = os.path.join(out_dir, f"{index:03d}-type{kind}-handle{handle:04x}.bin")
        with open(path, "xb") as out:
            out.write(blob)
        print("-smbios " + shlex.quote("file=" + path.replace(",", ",,")))
    print(DROPPED_REASON, file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
