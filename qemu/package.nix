{
  lib,
  qemu,
  fetchurl,
  python3Packages,
  autovirt,
  cpuVendor,
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
  # QEMU 10.2.2 hangs OVMF firmware; 11.0.1 is the oldest release verified good.
  minimumVersion = "11.0.1";

  qemuBase =
    if builtins.compareVersions qemu.version minimumVersion >= 0 then
      qemu
    else
      qemu.overrideAttrs (old: {
        version = minimumVersion;
        src = fetchurl {
          url = "https://download.qemu.org/qemu-${minimumVersion}.tar.xz";
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

  autovirtPatches = import ../lib/autovirt-patches.nix { inherit lib; };

  autovirtPatch = autovirtPatches.qemu {
    inherit autovirt cpuVendor;
    qemuVersion = qemuBase.version;
  };

  inherit (autovirtPatches.traits.${cpuVendor}) patchedOemId patchedOemTableId;
in

(qemuBase.override {
  hostCpuOnly = true;
}).overrideAttrs
  (old: {
    pname = "qemu-stealth";
    postPatch =
      (old.postPatch or "")
      + (import ./post-patch.nix {
        inherit
          lib
          autovirtPatch
          patchedOemId
          patchedOemTableId
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
