{
  lib,
  runCommand,
  patchutils,
  autovirt,
  cpuVendor,
  OVMF,
  patchAssertions,
  firmwareVendor ? "American Megatrends Inc.",
  acpiOemId ? "ALASKA",
  acpiOemTableId ? "A M I   ",
}:

let
  autovirtPatch = (import ../lib/autovirt-patches.nix { inherit lib; }).edk2 {
    inherit autovirt;
    inherit cpuVendor;
  };

  ovmfPostPatch = import ../ovmf/post-patch.nix {
    inherit
      lib
      autovirtPatch
      patchAssertions
      firmwareVendor
      acpiOemId
      acpiOemTableId
      ;
  };

  guards = [
    {
      name = "fw-cfg-signature";
      path = "OvmfPkg/Library/QemuFwCfgLib/QemuFwCfgDxe.c";
      pattern = "SIGNATURE_32 (0xFF, 0xFF, 0xFF, 0xFF)";
      absent = "SIGNATURE_32 ('Q', 'E', 'M', 'U')";
    }
    {
      name = "acpi-default-oem-id";
      path = "MdeModulePkg/MdeModulePkg.dec";
      pattern = ''PcdAcpiDefaultOemId|"${acpiOemId}"|'';
    }
    {
      name = "acpi-default-oem-table-id-not-edk2";
      path = "MdeModulePkg/MdeModulePkg.dec";
      pattern = "PcdAcpiDefaultOemTableId|0x";
      absent = "PcdAcpiDefaultOemTableId|0x20202020324B4445|";
    }
    {
      name = "tcg-pfp-revision";
      path = "MdeModulePkg/MdeModulePkg.dec";
      pattern = "PcdTcgPfpMeasurementRevision|105|UINT32";
      absent = "PcdTcgPfpMeasurementRevision|0|UINT32";
    }
    {
      name = "edid-protocols";
      path = "OvmfPkg/QemuVideoDxe/QemuVideoDxe.inf";
      pattern = "gEfiEdidDiscoveredProtocolGuid";
    }
    {
      name = "firmware-vendor-dec";
      path = "MdeModulePkg/MdeModulePkg.dec";
      pattern = ''L"${firmwareVendor}"'';
    }
    {
      name = "mch-device-id";
      path = "OvmfPkg/Include/IndustryStandard/Q35MchIch9.h";
      pattern = "INTEL_Q35_MCH_DEVICE_ID    0x29C0";
    }
    {
      name = "pm-register-address";
      path = "OvmfPkg/Include/IndustryStandard/Q35MchIch9.h";
      pattern = "EFI_PCI_ADDRESS (0, 0x1f, 0,";
    }
  ];

  guardCheck = g: ''
    if ! grep -qF -- ${lib.escapeShellArg g.pattern} ${lib.escapeShellArg g.path}; then
      echo "  FAIL: ${g.name}: expected pattern not found in ${g.path}: ${g.pattern}"
      exit 1
    fi
    ${lib.optionalString (g ? absent) ''
      if grep -qF -- ${lib.escapeShellArg g.absent} ${lib.escapeShellArg g.path}; then
        echo "  FAIL: ${g.name}: ${g.path} still holds ${g.absent}"
        exit 1
      fi
    ''}
  '';

  allGuardChecks = lib.concatMapStringsSep "\n" guardCheck guards;
in
runCommand "sed-contract-edk2-${cpuVendor}"
  {
    nativeBuildInputs = [ patchutils ];
  }
  ''
    src=$(mktemp -d)
    cp -r ${OVMF.src}/* "$src"/
    chmod -R u+w "$src"
    cd "$src"
    ${ovmfPostPatch}
    echo "=== sed-contract-edk2-${cpuVendor}: per-sed guard assertions ==="
    ${allGuardChecks}
    echo "sed-contract-edk2-${cpuVendor}: all ${toString (lib.length guards)} guards passed"
    touch $out
  ''
