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
  diskSerial ? "WD-WMC4N0E0XYZA",
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
      "${autovirt}/patches/QEMU/Archive/AMD-v10.2.0.patch"
    ];
    postPatch = (old.postPatch or "") + ''
      echo "=== Applying EDK2/OVMF stealth patch ==="
      # AutoVirt EDK2 patch: clears VirtualMachine SMBIOS bit, replaces Red Hat
      # PCI vendor IDs (1B36→1022, 1234→1002), renames VMM-prefixed variables,
      # spoofs ACPI OEM fields. Applied inside QEMU's bundled roms/edk2/.
      if [ -d roms/edk2 ]; then
        patch -d roms/edk2 -p1 < "${autovirt}/patches/EDK2/AMD-edk2-stable202602.patch" || {
          echo "WARNING: EDK2 patch failed — firmware may contain VM indicators"
        }
        # Replace firmware vendor string with realistic value
        substituteInPlace roms/edk2/OvmfPkg/OvmfPkgX64.dsc \
          --replace-warn 'L"EDK II"' 'L"American Megatrends Inc."' || true
      fi

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

      # QEMU0001/QEMU0002 ACPI device IDs: already patched by AutoVirt
      # (QEMU0001 → UEFI0001, QEMU0002 → UEFI0002). Previous sed
      # commands here were no-ops since the original strings no longer exist.

      # Disk model: patch uses "Hitachi HMS360404D5CF00" — replace with ${diskModel}
      sed -i 's|Hitachi HMS360404D5CF00|${diskModel}|g' hw/ide/core.c hw/scsi/scsi-disk.c 2>/dev/null || true
      # Disk serial: AutoVirt blanks the IDE serial (drive_serial_str = '\0') — set realistic WD serial
      sed -i "s|drive_serial_str\[0\] = '\\\\0';.*|pstrcpy(s->drive_serial_str, sizeof(s->drive_serial_str), \"${diskSerial}\");|g" hw/ide/core.c 2>/dev/null || true
      # SCSI product: AutoVirt uses "Samsung SSD 980 500GB" — replace with ${diskModel}
      sed -i 's|Samsung SSD 980 500GB|${diskModel}|g' hw/scsi/scsi-disk.c 2>/dev/null || true

      # Optical drive: patch uses "HL-DT-ST BD-RE WH16NS60" — use ${opticalModel}
      sed -i 's|HL-DT-ST BD-RE WH16NS60|${opticalModel}|g' hw/ide/core.c hw/ide/atapi.c 2>/dev/null || true

      # fw_cfg 4-byte probe signature: selector 0x0000 returns "QEMU"
      # AutoVirt patched the 8-byte DMA signature but left this 4-byte probe.
      # Kernel-mode scanners can detect it via inb(0x511) after outw(0x510, 0x0000).
      sed -i 's|fw_cfg_add_bytes(s, FW_CFG_SIGNATURE, (char \*)"QEMU", 4)|fw_cfg_add_bytes(s, FW_CFG_SIGNATURE, (char *)"AMDK", 4)|g' hw/nvram/fw_cfg.c

      echo "=== Stealth customization complete ==="
    '';
  })
