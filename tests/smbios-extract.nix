{
  runCommand,
  writeText,
  python3,
  smbios-extract,
}:

let
  check = writeText "smbios-extract-check.py" ''
    import os
    import struct
    import subprocess
    import sys


    def structure(kind, handle, formatted, strings):
        header = struct.pack("<BBH", kind, 4 + len(formatted), handle)
        if strings:
            string_set = b"".join(s.encode() + b"\x00" for s in strings) + b"\x00"
        else:
            string_set = b"\x00\x00"
        return header + formatted + string_set


    def checksum(entry):
        return (-sum(entry)) & 0xFF


    KEPT = {
        0: (bytes([1, 2, 0x00, 0xF0, 3, 0xFF]) + bytes(8), ["Fixture BIOS", "1.0", "01/01/2026"]),
        1: (bytes([1, 2, 3, 4]) + bytes(16) + bytes([6, 5, 6]), ["Fixture Inc.", "Fixture Board", "1.0", "FIX-0001", "FIX-SKU", "Fixture Family"]),
        2: (bytes([1, 2, 3, 4]), ["Fixture Inc.", "Fixture Board", "1.0", "FIX-BOARD-0001"]),
    }
    table = b"".join(
        [
            structure(0, 0x0000, *KEPT[0]),
            structure(1, 0x0001, *KEPT[1]),
            structure(2, 0x0002, *KEPT[2]),
            structure(4, 0x0004, bytes([1, 3]) + bytes(20), ["CPU0", "Fixture CPU"]),
            structure(17, 0x0011, bytes(0x24), []),
            structure(127, 0x7F00, b"", []),
        ]
    )
    count = 6


    def sm3():
        entry = bytearray(b"_SM3_" + bytes([0, 0x18, 3, 0, 0, 1, 0]) + struct.pack("<IQ", len(table), 0x20))
        entry[5] = checksum(entry)
        return bytes(entry).ljust(0x20, b"\x00") + table


    def sm():
        dmi = bytearray(b"_DMI_" + bytes([0]) + struct.pack("<HIHB", len(table), 0x20, count, 0x28))
        dmi[5] = checksum(dmi)
        entry = bytearray(b"_SM_" + bytes([0, 0x1F, 2, 8]) + struct.pack("<H", 0x40) + bytes(6) + dmi)
        entry[4] = checksum(entry)
        return bytes(entry).ljust(0x20, b"\x00") + table


    def fail(message):
        print(f"FAIL: {message}")
        sys.exit(1)


    def split(name, dump):
        path = f"{name}.dump"
        with open(path, "wb") as f:
            f.write(dump)
        out_dir = os.path.abspath(f"{name}-out")
        result = subprocess.run(["smbios-split", path, out_dir], capture_output=True, text=True)
        sys.stdout.write(result.stdout)
        sys.stdout.write(result.stderr)
        return result, out_dir


    def check_form(name, dump):
        result, out_dir = split(name, dump)
        if result.returncode != 0:
            fail(f"{name}: smbios-split exited {result.returncode}")
        files = sorted(os.listdir(out_dir))
        printed = result.stdout.splitlines()
        wanted = [f"-smbios file={os.path.join(out_dir, f)}" for f in files]
        if printed != wanted:
            fail(f"{name}: printed {printed!r}, the directory holds {wanted!r}")
        contents = {}
        for f in files:
            with open(os.path.join(out_dir, f), "rb") as handle:
                blob = handle.read()
            kind = blob[0]
            if kind in contents:
                fail(f"{name}: two files for type {kind}")
            contents[kind] = blob
        if sorted(contents) != sorted(KEPT):
            fail(f"{name}: files for types {sorted(contents)}, wanted exactly {sorted(KEPT)}")
        for kind, blob in contents.items():
            formatted, strings = KEPT[kind]
            if blob[1] != 4 + len(formatted):
                fail(f"{name}: type {kind} length byte {blob[1]}, its formatted area is {4 + len(formatted)}")
            if not blob.endswith(b"\x00\x00"):
                fail(f"{name}: type {kind} does not end with a double NUL")
            found = blob[blob[1] : -2].split(b"\x00")
            if found != [s.encode() for s in strings]:
                fail(f"{name}: type {kind} strings {found!r}, wanted {strings!r}")
        return contents


    first = check_form("sm3", sm3())
    second = check_form("sm", sm())
    if first != second:
        fail("the _SM3_ and _SM_ forms of one table give different files")

    refused, refused_dir = split("no-anchor", bytes(0x20) + table)
    if refused.returncode == 0:
        fail("a file with neither _SM3_ nor _SM_ anchor was accepted")
    if os.path.exists(refused_dir):
        fail("a refused file still produced an output directory")
  '';
in
runCommand "smbios-extract"
  {
    nativeBuildInputs = [
      python3
      smbios-extract
    ];
  }
  ''
    python3 -I ${check}
    touch $out
  ''
