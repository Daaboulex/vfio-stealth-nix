{
  lib,
  qemu,
  fetchurl,
  python3Packages,
  autovirt,
  # EDID: Generic ASUS monitor
  edidManufacturer ? "ACI",
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
  diskSerial ? "Default string",
  # Optical: Generic LG
  opticalModel ? "HL-DT-ST DVDRAM GH24NSC0 ",
  # SCSI vendor (8-char T10 format)
  scsiVendor ? "WDC",
  # SCSI target product for dead-LUN INQUIRY fallback (16-char padded)
  scsiTargetProduct ? "SCSI Disk       ",
  # EDID default resolution
  edidResX ? 1920,
  edidResY ? 1080,
}:

let
  expectedVersionPrefix = "11.0.";

  # Pin QEMU 11.0.x while nixpkgs ships 10.2.x (10.2.2 hangs OVMF firmware).
  # When nixpkgs bumps to 11.0.x, the pin is skipped and nixpkgs patches apply normally.
  qemuBase =
    if lib.hasPrefix expectedVersionPrefix qemu.version then
      qemu
    else
      qemu.overrideAttrs (old: {
        version = "11.0.1";
        src = fetchurl {
          url = "https://download.qemu.org/qemu-11.0.1.tar.xz";
          hash = "sha256-DSNfWCAnjZFKMVXsJ6+OQljWl+qJKJVXCAfWnAy4zWQ=";
        };
        patches = [ ];
        # QEMU 11's mkvenv needs Python packages that 10.2.x's packaging doesn't provide.
        nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [
          python3Packages.setuptools
          python3Packages.pip
          python3Packages.wheel
        ];
      });
in

assert lib.assertMsg (lib.hasPrefix expectedVersionPrefix qemuBase.version)
  "qemu-stealth: expected QEMU ${expectedVersionPrefix}x but got ${qemuBase.version} — update the patch";

(qemuBase.override {
  hostCpuOnly = true;
}).overrideAttrs
  (old: {
    pname = "qemu-stealth";
    patches = (old.patches or [ ]) ++ [
      "${autovirt}/patches/QEMU/AMD-v11.0.0.patch"
    ];
    postPatch = (old.postPatch or "") + ''
      echo "=== Applying EDK2/OVMF patch ==="
      # nixpkgs builds OVMF separately; roms/edk2 is absent in the normal
      # derivation, so this block is a no-op.  Kept for standalone builds.
      if [ -d roms/edk2 ]; then
        EDK2_PATCH=""
        for p in "${autovirt}"/patches/EDK2/AMD-edk2-stable*.patch; do
          if [ -f "$p" ]; then EDK2_PATCH="$p"; break; fi
        done
        if [ -z "$EDK2_PATCH" ]; then
          echo "FATAL: no AMD EDK2 patch found in ${autovirt}/patches/EDK2/"
          ls -la "${autovirt}/patches/EDK2/" 2>/dev/null || true
          exit 1
        fi
        echo "Using EDK2 patch: $(basename "$EDK2_PATCH")"
        patch -d roms/edk2 -p1 < "$EDK2_PATCH" || {
          echo "FATAL: EDK2 patch failed"
          exit 1
        }
        substituteInPlace roms/edk2/OvmfPkg/OvmfPkgX64.dsc \
          --replace-warn 'L"EDK II"' 'L"American Megatrends Inc."' || true
      fi

      echo "=== Customizing hardware identifiers ==="

      # EDID: replace stock QEMU monitor identity with configured values
      substituteInPlace hw/display/edid-generate.c \
        --replace-fail '"RHT"' '"${edidManufacturer}"'
      substituteInPlace hw/display/edid-generate.c \
        --replace-fail '"QEMU Monitor"' '"${edidSerial}"'
      sed -i 's|0x1234|${edidProductCode}|g' hw/display/edid-generate.c
      if ! grep -q '${edidProductCode}' hw/display/edid-generate.c; then
        echo "FATAL: EDID product code replacement to ${edidProductCode} did not apply"
        exit 1
      fi
      sed -i 's|edid\[16\] = 42;|edid[16] = ${toString edidWeek};|g' hw/display/edid-generate.c
      if ! grep -q 'edid\[16\] = ${toString edidWeek};' hw/display/edid-generate.c; then
        echo "FATAL: EDID week replacement to ${toString edidWeek} did not apply"
        exit 1
      fi
      sed -i 's|2014 - 1990|${toString edidYear} - 1990|g' hw/display/edid-generate.c
      if ! grep -q '${toString edidYear} - 1990' hw/display/edid-generate.c; then
        echo "FATAL: EDID year replacement to ${toString edidYear} did not apply"
        exit 1
      fi
      sed -i 's|uint32_t dpi = 100;|uint32_t dpi = ${toString edidDpi};|g' hw/display/edid-generate.c
      if ! grep -q 'uint32_t dpi = ${toString edidDpi};' hw/display/edid-generate.c; then
        echo "FATAL: EDID DPI replacement to ${toString edidDpi} did not apply"
        exit 1
      fi
      # EDID default resolution
      sed -i 's|info->prefx = 1280;|info->prefx = ${toString edidResX};|g' hw/display/edid-generate.c
      if ! grep -q 'info->prefx = ${toString edidResX};' hw/display/edid-generate.c; then
        echo "FATAL: EDID resolution X replacement to ${toString edidResX} did not apply"
        exit 1
      fi
      sed -i 's|info->prefy = 800;|info->prefy = ${toString edidResY};|g' hw/display/edid-generate.c
      if ! grep -q 'info->prefy = ${toString edidResY};' hw/display/edid-generate.c; then
        echo "FATAL: EDID resolution Y replacement to ${toString edidResY} did not apply"
        exit 1
      fi

      # SCSI INQUIRY: replace stock QEMU vendor/product for dead-LUN fallback in scsi-bus.c
      substituteInPlace hw/scsi/scsi-bus.c \
        --replace-fail '"QEMU    "' '"${builtins.substring 0 8 (scsiVendor + "        ")}"'
      substituteInPlace hw/scsi/scsi-bus.c \
        --replace-fail '"QEMU TARGET     "' '"${scsiTargetProduct}"'

      # SCSI disk: replace stock QEMU product/vendor in scsi-disk.c
      substituteInPlace hw/scsi/scsi-disk.c \
        --replace-fail '"QEMU HARDDISK"' '"${diskModel}"'
      substituteInPlace hw/scsi/scsi-disk.c \
        --replace-fail '"QEMU CD-ROM"' '"${opticalModel}"'
      substituteInPlace hw/scsi/scsi-disk.c \
        --replace-fail '"QEMU"' '"${scsiVendor}"'

      # ACPI OEM: replace values in aml-build.h
      sed -i 's|"ALASKA"|"${acpiOemId}"|g' include/hw/acpi/aml-build.h
      if ! grep -q '"${acpiOemId}"' include/hw/acpi/aml-build.h; then
        echo "FATAL: ACPI OEM ID replacement to ${acpiOemId} did not apply"
        exit 1
      fi
      sed -i 's|"A M I   "|"${acpiOemTableId}"|g' include/hw/acpi/aml-build.h
      if ! grep -q '"${acpiOemTableId}"' include/hw/acpi/aml-build.h; then
        echo "FATAL: ACPI OEM Table ID replacement did not apply"
        exit 1
      fi

      # IDE disk model: patch sets "Samsung SSD 980 500GB" (main) and "Hitachi HMS360404D5CF00" (CF)
      substituteInPlace hw/ide/core.c \
        --replace-fail 'Samsung SSD 980 500GB' '${diskModel}'
      substituteInPlace hw/ide/core.c \
        --replace-fail 'Hitachi HMS360404D5CF00' '${diskModel}'
      # IDE serial: patch blanks it — set realistic serial
      sed -i "s|s->drive_serial_str\[0\] = '\\\\0';|pstrcpy(s->drive_serial_str, sizeof(s->drive_serial_str), \"${diskSerial}\");|g" hw/ide/core.c
      if ! grep -q 'pstrcpy(s->drive_serial_str' hw/ide/core.c; then
        echo "FATAL: IDE serial replacement did not apply"
        exit 1
      fi
      # IDE optical drive: patch sets "HL-DT-ST BD-RE WH16NS60" — replace with configured
      substituteInPlace hw/ide/core.c \
        --replace-fail 'HL-DT-ST BD-RE WH16NS60' '${opticalModel}'

      # Revert Q35 MCH host bridge (00:00.0) to real Intel Q35 identity.
      # AutoVirt spoofs it to AMD (1022:14d8), but OVMF's Q35 PEI init
      # (Q35TsegMbytesInitialization, Q35SmramAtDefaultSmbaseInitialization)
      # requires a genuine Q35 MCH — the TSEG/SMRAM registers live at
      # DRAMC_REGISTER_Q35 offsets that only work when OVMF recognizes
      # the real Q35 device ID. The MCH is firmware-internal (Q35 machine
      # regardless), so real Q35 identity costs nothing in stealth — an
      # AMD MCH on a Q35 machine is itself a detectable inconsistency.
      # All other device spoofing (NVMe, HDA, USB, AHCI, etc.) is kept.
      sed -i 's/define PCI_DEVICE_ID_INTEL_P35_MCH.*$/define PCI_DEVICE_ID_INTEL_P35_MCH      0x29c0/' \
        include/hw/pci/pci_ids.h
      if ! grep -q 'PCI_DEVICE_ID_INTEL_P35_MCH.*0x29c0' include/hw/pci/pci_ids.h; then
        echo "FATAL: MCH device ID revert to 0x29c0 failed in pci_ids.h"
        grep -n 'PCI_DEVICE_ID_INTEL_P35_MCH' include/hw/pci/pci_ids.h || true
        exit 1
      fi
      sed -i 's/k->vendor_id = .*/k->vendor_id = PCI_VENDOR_ID_INTEL;/' hw/pci-host/q35.c
      if ! grep -q 'k->vendor_id = PCI_VENDOR_ID_INTEL;' hw/pci-host/q35.c; then
        echo "FATAL: MCH vendor_id revert to Intel failed in q35.c"
        grep -n 'vendor_id' hw/pci-host/q35.c || true
        exit 1
      fi

      echo "=== Hardware identity customization complete ==="
    '';
  })
