{
  lib,
  runCommand,
  patchutils,
  inputs,
  cpuVendor,
  OVMF,
}:

let
  autovirtPatch = (import ../lib/autovirt-patches.nix { inherit lib; }).edk2 {
    inherit (inputs) autovirt;
    inherit cpuVendor;
  };

  # The production OVMF postPatch itself -- ONE source, imported by both
  # ovmf/package.nix and this contract, so the replay can never drift from
  # what the build actually runs.
  ovmfPostPatch = import ../ovmf/post-patch.nix { inherit autovirtPatch; };

  # Per-sed guard: (name, file path, pattern the sed is required to
  # leave in the post-patch file). BGRT/LogoDxe are strip seds (the
  # pattern must be ABSENT in the post-patch file); verified by
  # checking the upstream AutoVirt-set value isn't present, not the
  # stripped absence (an empty-pattern grep matches every line, so
  # we test the positive identity the sed leaves behind instead).
  guards = [
    {
      name = "firmware-vendor-dec";
      path = "MdeModulePkg/MdeModulePkg.dec";
      pattern = ''"American Megatrends Inc."'';
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
      echo "  FAIL: ${g.name} — expected pattern not found in ${g.path}: ${g.pattern}"
      exit 1
    fi
  '';

  allGuardChecks = lib.concatMapStringsSep "\n" guardCheck guards;
in
# The OVMF nixpkgs derivation carries the EDK2 source on `.src`; we apply
# the filterdiff + the sed-based postPatch to a fresh copy and run the
# per-sed grep guards. This catches the silent-no-op class of breaks
# that the build-time FATAL might miss (e.g. an AutoVirt bump that
# renames the BGRT module).
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
