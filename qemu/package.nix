{
  lib,
  qemu,
  fetchurl,
  python3Packages,
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
  diskSerial ? "Default string",
  # Optical: Generic LG
  opticalModel ? "HL-DT-ST DVDRAM GH24NSC0 ",
  # SCSI vendor (8-char T10 format)
  scsiVendor ? "WDC",
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
      sed -i 's|edid\[16\] = 42;|edid[16] = ${toString edidWeek};|g' hw/display/edid-generate.c
      sed -i 's|2014 - 1990|${toString edidYear} - 1990|g' hw/display/edid-generate.c
      sed -i 's|uint32_t dpi = 100;|uint32_t dpi = ${toString edidDpi};|g' hw/display/edid-generate.c
      # EDID default resolution
      sed -i 's|info->prefx = 1280;|info->prefx = ${toString edidResX};|g' hw/display/edid-generate.c
      sed -i 's|info->prefy = 800;|info->prefy = ${toString edidResY};|g' hw/display/edid-generate.c

      # SCSI INQUIRY: replace stock QEMU vendor/product in scsi-bus.c
      substituteInPlace hw/scsi/scsi-bus.c \
        --replace-fail '"QEMU    "' '"${edidModelAbbrev}"'
      substituteInPlace hw/scsi/scsi-bus.c \
        --replace-fail '"QEMU TARGET     "' '"${edidModel}"'

      # SCSI disk: replace stock QEMU product/vendor in scsi-disk.c
      substituteInPlace hw/scsi/scsi-disk.c \
        --replace-fail '"QEMU HARDDISK"' '"${diskModel}"'
      substituteInPlace hw/scsi/scsi-disk.c \
        --replace-fail '"QEMU CD-ROM"' '"${opticalModel}"'
      substituteInPlace hw/scsi/scsi-disk.c \
        --replace-fail '"QEMU"' '"${scsiVendor}"'

      # ACPI OEM: replace values in aml-build.h
      sed -i 's|"ALASKA"|"${acpiOemId}"|g' include/hw/acpi/aml-build.h
      sed -i 's|"A M I   "|"${acpiOemTableId}"|g' include/hw/acpi/aml-build.h

      # IDE disk model: patch sets "Samsung SSD 980 500GB" (main) and "Hitachi HMS360404D5CF00" (CF)
      substituteInPlace hw/ide/core.c \
        --replace-fail 'Samsung SSD 980 500GB' '${diskModel}'
      substituteInPlace hw/ide/core.c \
        --replace-fail 'Hitachi HMS360404D5CF00' '${diskModel}'
      # IDE serial: patch blanks it — set realistic serial
      sed -i "s|s->drive_serial_str\[0\] = '\\\\0';|pstrcpy(s->drive_serial_str, sizeof(s->drive_serial_str), \"${diskSerial}\");|g" hw/ide/core.c
      # IDE optical drive: patch sets "HL-DT-ST BD-RE WH16NS60" — replace with configured
      substituteInPlace hw/ide/core.c \
        --replace-fail 'HL-DT-ST BD-RE WH16NS60' '${opticalModel}'

      # fw_cfg 4-byte probe signature: selector 0x0000 returns "QEMU"
      sed -i 's|fw_cfg_add_bytes(s, FW_CFG_SIGNATURE, (char \*)"QEMU", 4)|fw_cfg_add_bytes(s, FW_CFG_SIGNATURE, (char *)"AMDK", 4)|g' hw/nvram/fw_cfg.c
      if ! grep -q '"AMDK"' hw/nvram/fw_cfg.c; then
        echo "FATAL: fw_cfg signature patch failed"
        exit 1
      fi

      echo "=== Hardware identity customization complete ==="
    '';
  })
