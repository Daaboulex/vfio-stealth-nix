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
    postPatch =
      (old.postPatch or "")
      + (import ./post-patch.nix {
        inherit
          lib
          autovirt
          edidManufacturer
          edidSerial
          edidProductCode
          edidDpi
          edidWeek
          edidYear
          edidResX
          edidResY
          acpiOemId
          acpiOemTableId
          diskModel
          diskSerial
          opticalModel
          scsiVendor
          scsiTargetProduct
          ;
      });
  })
