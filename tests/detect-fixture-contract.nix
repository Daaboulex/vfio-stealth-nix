{
  lib,
  runCommand,
  python3,
  stealth-detect-arm64,
}:

let
  # ACPI 6.x FADT: signature at 0, length at 4, revision at 8, OEM ID at 10,
  # OEM table ID at 16, Hypervisor Vendor Identity at 268. Written here from the
  # spec, so a wrong offset in the detector shows up as a flipped verdict rather
  # than as a constant that matches itself.
  fadtBuilder = ''
    def fadt(revision, oem_id, oem_table_id, hypervisor_id, length=276):
        table = bytearray(length)
        table[0:4] = b"FACP"
        table[4:8] = length.to_bytes(4, "little")
        table[8] = revision
        table[10:16] = oem_id.ljust(6, b" ")
        table[16:24] = oem_table_id.ljust(8, b" ")
        if hypervisor_id is not None:
            table[268:276] = hypervisor_id.ljust(8, b"\0")
        return bytes(table)
  '';

  cases = {
    qemu-virt = {
      dtCompatible = "linux,dummy-virt";
      psciMethod = "hvc";
      fadt = ''fadt(6, b"BOCHS ", b"BXPC    ", b"QEMU")'';
      exit = 1;
      expect = {
        dt-machine-compatible = "detected";
        dt-psci-conduit = "detected";
        acpi-hypervisor-id = "detected";
        acpi-oem = "detected";
      };
    };

    bare-metal = {
      dtCompatible = "acme,gaming-board";
      psciMethod = "smc";
      fadt = ''fadt(6, b"ALASKA", b"A M I   ", None)'';
      exit = 0;
      expect = {
        dt-machine-compatible = "clean";
        dt-psci-conduit = "clean";
        acpi-hypervisor-id = "clean";
        acpi-oem = "clean";
      };
    };

    pre-acpi6-firmware = {
      dtCompatible = "acme,gaming-board";
      psciMethod = "smc";
      fadt = ''fadt(5, b"ALASKA", b"A M I   ", b"QEMU")'';
      exit = 0;
      expect = {
        acpi-hypervisor-id = "unknown";
        acpi-oem = "clean";
      };
    };
  };

  mkCase = name: case: ''
    python3 - <<'BUILD'
    import pathlib
    ${fadtBuilder}
    root = pathlib.Path("${name}")
    dt = root / "proc/device-tree"
    (dt / "psci").mkdir(parents=True, exist_ok=True)
    (dt / "compatible").write_bytes(b"${case.dtCompatible}\0")
    (dt / "psci/method").write_bytes(b"${case.psciMethod}\0")
    acpi = root / "sys/firmware/acpi/tables"
    acpi.mkdir(parents=True, exist_ok=True)
    (acpi / "FACP").write_bytes(${case.fadt})
    BUILD

    echo "--- ${name} ---"
    set +e
    stealth-detect-arm64 --root "${name}" --json > "${name}.json"
    rc=$?
    set -e
    cat "${name}.json"

    python3 - "$rc" <<'CHECK'
    import json, sys
    rc = int(sys.argv[1])
    report = json.load(open("${name}.json"))
    got = {f["vector"]: f["verdict"] for f in report["findings"]}
    want = ${builtins.toJSON case.expect}
    bad = {v: (want[v], got.get(v)) for v in want if got.get(v) != want[v]}
    for vector, (expected, actual) in sorted(bad.items()):
        print(f"::error::${name}: {vector} expected {expected}, got {actual}")
    if rc != ${toString case.exit}:
        print(f"::error::${name}: expected exit ${toString case.exit}, got {rc}")
    sys.exit(1 if bad or rc != ${toString case.exit} else 0)
    CHECK
  '';
in

runCommand "detect-fixture-contract"
  {
    nativeBuildInputs = [
      python3
      stealth-detect-arm64
    ];
  }
  ''
    set -euo pipefail
    ${lib.concatStringsSep "\n" (lib.mapAttrsToList mkCase cases)}
    echo "detect-fixture-contract: every fixture produced its expected verdict and exit code"
    touch "$out"
  ''
