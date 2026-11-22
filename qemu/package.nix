{
  lib,
  qemu,
  fetchurl,
  python3Packages,
  autovirt,
  cpuVendor,
  edidManufacturer ? "ACI",
  edidSerial ? "VG248QE",
  edidProductCode ? "0x2480",
  edidDpi ? 91,
  edidWeek ? 22,
  edidYear ? 2020,
  acpiOemId ? "ALASKA",
  acpiOemTableId ? "A M I   ",
  diskModel ? "WDC WD10EZEX-00WN4A0     ",
  diskSerial ? "Default string",
  edidSerialNumber ? 0,
  opticalModel ? "HL-DT-ST DVDRAM GH24NSC0 ",
  diskFirmware ? "01.01A01",
  opticalFirmware ? "LY00",
  pciSubsystem ? "8086:7270",
  hdaCodec ? "10ec:0897",
  scsiVendor ? "WDC",
  scsiTargetProduct ? "SCSI Disk       ",
  edidResX ? 1920,
  edidResY ? 1080,
  smbiosChassisType ? 3,
  smbiosMemoryErrorCorrection ? 3,
  smbiosMemoryMaxCapacityGb ? (import ../smbios/memory-layout.nix).maxCapacityGb,
  smbiosMemorySlots ? (import ../smbios/memory-layout.nix).slots,
  smbiosMemoryType ? (import ../smbios/memory-layout.nix).type,
  smbiosMemoryTypeDetail ? (import ../smbios/memory-layout.nix).typeDetail,
  smbiosMemoryRank ? (import ../smbios/memory-layout.nix).rank,
  smbiosMemoryVoltageMillivolts ? lib.attrByPath [
    smbiosMemoryType
  ] null (import ../smbios/memory-layout.nix).nominalMillivolts,
  deviceIdentities ? import ./device-identities.nix,
  acpiWaet ? true,
  fadtC2Latency ? 101,
  fadtC3Latency ? 1001,
  probe ? null,
  patchAssertions,
}:

let
  # why: QEMU 10.2.2 hangs OVMF; 11.0.3 is the oldest release verified good
  minimumVersion = "11.0.3";

  autovirtPatches = import ../lib/autovirt-patches.nix { inherit lib; };

  ceiling = autovirtPatches.ceiling { inherit autovirt cpuVendor; };

  patchedSeries = autovirtPatches.qemuSeries { inherit autovirt cpuVendor; };

  qemuBase = import ../lib/select-qemu-base.nix {
    inherit
      lib
      qemu
      fetchurl
      python3Packages
      minimumVersion
      ceiling
      patchedSeries
      ;
    probeVersion = if probe == null then null else probe.version;
    tarballHashes = {
      "11.0.3" = "sha256-2l/P/DJ2KCBWi4KO1DCnKIZNNNULbS8wNYWXdgy7BSM=";
      "11.1.3" = "sha256-WoKJx5QNx304c8gabCm6Ov4URvydNud/oWWM2+y4SyI=";
    }
    // lib.optionalAttrs (probe != null) { ${probe.version} = probe.hash; };
  };

  autovirtPatch = autovirtPatches.qemu {
    inherit autovirt cpuVendor;
    qemuVersion = if probe == null then qemuBase.version else ceiling;
  };

  inherit (autovirtPatches.traits.${cpuVendor})
    patchedOemId
    patchedOemTableId
    patchedHdaDevice
    xhciRegisterWindow
    ;
in

(qemuBase.override {
  hostCpuOnly = true;
}).overrideAttrs
  (old: {
    pname = "qemu-stealth";
    meta = (old.meta or { }) // {
      description = "QEMU with AutoVirt hardware emulation patches";
      platforms = [ "x86_64-linux" ];
    };
    passthru = (old.passthru or { }) // {
      inherit
        acpiOemId
        autovirtPatch
        deviceIdentities
        xhciRegisterWindow
        diskModel
        diskFirmware
        opticalModel
        opticalFirmware
        ;
    };
    postPatch =
      (old.postPatch or "")
      + (import ./post-patch.nix {
        inherit
          lib
          patchAssertions
          autovirtPatch
          patchedOemId
          patchedOemTableId
          patchedHdaDevice
          xhciRegisterWindow
          edidManufacturer
          edidSerial
          edidSerialNumber
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
          diskFirmware
          opticalFirmware
          pciSubsystem
          hdaCodec
          scsiVendor
          scsiTargetProduct
          smbiosChassisType
          smbiosMemoryErrorCorrection
          smbiosMemoryMaxCapacityGb
          smbiosMemorySlots
          smbiosMemoryType
          smbiosMemoryTypeDetail
          smbiosMemoryRank
          smbiosMemoryVoltageMillivolts
          deviceIdentities
          acpiWaet
          fadtC2Latency
          fadtC3Latency
          ;
      });
  })
