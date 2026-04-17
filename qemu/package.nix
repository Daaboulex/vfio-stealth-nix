{
  lib,
  qemu,
  autovirt,
  # EDID: Generic ASUS monitor
  edidManufacturer ? "ACI",
  edidModelAbbrev ? "ACI     ",
  edidModel ? "ASUS VG248      ",
  edidSerial ? "VG248QE",
  edidProductCode ? "0x2480",
  edidDpi ? 91,
  edidWeek ? 22,
  edidYear ? 2020,
  # ACPI OEM: Generic AMI (6-char and 8-char padded)
  acpiOemId ? "ALASKA",
  acpiOemTableId ? "A M I   ",
  # Disk: Generic WD
  diskModel ? "WDC WD10EZEX-00WN4A0     ",
  # Optical: Generic LG
  opticalModel ? "HL-DT-ST DVDRAM GH24NSC0 ",
}:

let
  expectedVersionPrefix = "10.2.";
in

assert lib.assertMsg (lib.hasPrefix expectedVersionPrefix qemu.version)
  "qemu-stealth: expected QEMU ${expectedVersionPrefix}x but got ${qemu.version} — update the patch";

(qemu.override {
  hostCpuOnly = true;
}).overrideAttrs
  (old: {
    pname = "qemu-stealth";
    patches = (old.patches or [ ]) ++ [
      "${autovirt}/patches/QEMU/AMD-v10.2.0.patch"
    ];
    postPatch = (old.postPatch or "") + ''
      echo "=== Customizing stealth QEMU with unique hardware identifiers ==="

      # EDID: patch defaults to MSI G27C4X — replace with real monitor (${edidModel})
      sed -i 's|"MSI     "|"${edidModelAbbrev}"|g' hw/display/edid-generate.c
      sed -i 's|"MSI"|"${edidManufacturer}"|g' hw/display/edid-generate.c
      sed -i 's|"MSI TARGET      "|"${edidModel}"|g' hw/display/edid-generate.c
      sed -i 's|"G27C4X"|"${edidSerial}"|g' hw/display/edid-generate.c
      sed -i 's|0x10ad|${edidProductCode}|g' hw/display/edid-generate.c
      # EDID manufacture week/year: patch uses week=12 year=2025-2018(=7), real=week ${toString edidWeek} year ${toString edidYear}
      sed -i 's|edid\[16\] = 12;|edid[16] = ${toString edidWeek};|g' hw/display/edid-generate.c
      sed -i 's|2025 - 2018|${toString edidYear} - 1990|g' hw/display/edid-generate.c
      # EDID DPI: patch uses 82, real is ${toString edidDpi}
      sed -i 's|uint32_t dpi = 82;|uint32_t dpi = ${toString edidDpi};|g' hw/display/edid-generate.c

      # ACPI OEM: patch uses ALASKA/AMI — replace with configured OEM strings
      # These defines are in include/hw/acpi/aml-build.h (6-char and 8-char padded)
      sed -i 's|"ALASKA"|"${acpiOemId}"|g' include/hw/acpi/aml-build.h
      sed -i 's|"A M I   "|"${acpiOemTableId}"|g' include/hw/acpi/aml-build.h

      # fw_cfg ACPI device: QEMU0002 is a dead giveaway for VM detection.
      # Replace with PNP0C02 (generic motherboard resource) to blend in.
      sed -i 's|"QEMU0002"|"PNP0C02"|g' hw/acpi/core.c hw/acpi/aml-build.c 2>/dev/null || true

      # pvpanic ACPI device: QEMU0001 is another VM fingerprint.
      # Replace with PNP0C02 to match real hardware ACPI tables.
      sed -i 's|"QEMU0001"|"PNP0C02"|g' hw/acpi/generic_event_device.c 2>/dev/null || true

      # Disk model: patch uses "Hitachi HMS360404D5CF00" — replace with ${diskModel}
      sed -i 's|Hitachi HMS360404D5CF00|${diskModel}|g' hw/ide/core.c hw/scsi/scsi-disk.c 2>/dev/null || true

      # Optical drive: patch uses "HL-DT-ST BD-RE WH16NS60" — use ${opticalModel}
      sed -i 's|HL-DT-ST BD-RE WH16NS60|${opticalModel}|g' hw/ide/core.c hw/ide/atapi.c 2>/dev/null || true

      echo "=== Stealth customization complete ==="
    '';
  })
