{
  lib,
  runCommand,
  patchutils,
  inputs,
  OVMF,
}:

let
  autovirtPatch =
    let
      candidates = builtins.filter (n: lib.hasPrefix "AMD-edk2-stable" n && lib.hasSuffix ".patch" n) (
        builtins.attrNames (builtins.readDir "${inputs.autovirt}/patches/EDK2")
      );
    in
    "${inputs.autovirt}/patches/EDK2/${builtins.head (lib.sort (a: b: a > b) candidates)}";

  # The OVMF postPatch as a Nix function: applies the filterdiff-trimmed
  # AutoVirt patch + the 10 hardware-identity seds to a source tree. Same
  # code path as the production build; both must stay in lockstep.
  ovmfPostPatch = ''
    echo "=== OVMF-stealth: applying AutoVirt EDK2 patch (BaseTools excluded) ==="
    filterdiff -x '*/BaseTools/*' ${autovirtPatch} | patch -p1 --no-backup-if-mismatch
    echo "=== OVMF-stealth: AutoVirt patch applied ==="

    sed -i 's|L"EDK II"|L"American Megatrends Inc."|g' \
      MdeModulePkg/MdeModulePkg.dec OvmfPkg/OvmfPkgX64.dsc 2>/dev/null || true
    if grep -rq 'L"EDK II"' MdeModulePkg/MdeModulePkg.dec OvmfPkg/OvmfPkgX64.dsc; then
      echo "FATAL: firmware vendor string still contains L\"EDK II\""
      exit 1
    fi

    sed -i '/BootGraphicsResourceTableDxe/d' OvmfPkg/OvmfPkgX64.dsc OvmfPkg/OvmfPkgX64.fdf
    sed -i '/LogoDxe/d' OvmfPkg/OvmfPkgX64.fdf
    if grep -q 'BootGraphicsResourceTableDxe' OvmfPkg/OvmfPkgX64.dsc; then
      echo "FATAL: BootGraphicsResourceTableDxe still in DSC"; exit 1
    fi
    if grep -q 'BootGraphicsResourceTableDxe' OvmfPkg/OvmfPkgX64.fdf; then
      echo "FATAL: BootGraphicsResourceTableDxe still in FDF"; exit 1
    fi
    if grep -q 'LogoDxe' OvmfPkg/OvmfPkgX64.fdf; then
      echo "FATAL: LogoDxe still in FDF"; exit 1
    fi

    sed -i 's/define INTEL_Q35_MCH_DEVICE_ID.*$/define INTEL_Q35_MCH_DEVICE_ID    0x29C0/' \
      OvmfPkg/Include/IndustryStandard/Q35MchIch9.h
    if ! grep -q 'INTEL_Q35_MCH_DEVICE_ID.*0x29C0' OvmfPkg/Include/IndustryStandard/Q35MchIch9.h; then
      echo "FATAL: MCH device ID revert failed"
      grep -n 'MCH_DEVICE_ID\|0x14[dD]8\|0x29[cC]0' OvmfPkg/Include/IndustryStandard/Q35MchIch9.h || true
      exit 1
    fi
    sed -i 's|PCI_LIB_ADDRESS (0, 0x14, 3,|PCI_LIB_ADDRESS (0, 0x1f, 0,|g' \
      OvmfPkg/Include/IndustryStandard/Q35MchIch9.h
    sed -i 's|EFI_PCI_ADDRESS (0, 0x14, 3,|EFI_PCI_ADDRESS (0, 0x1f, 0,|g' \
      OvmfPkg/Include/IndustryStandard/Q35MchIch9.h
    if ! grep -q 'PCI_LIB_ADDRESS (0, 0x1f, 0,' OvmfPkg/Include/IndustryStandard/Q35MchIch9.h; then
      echo "FATAL: PM PCI_LIB_ADDRESS revert to (0x1f,0) failed"
      exit 1
    fi
    if ! grep -q 'EFI_PCI_ADDRESS (0, 0x1f, 0,' OvmfPkg/Include/IndustryStandard/Q35MchIch9.h; then
      echo "FATAL: PM EFI_PCI_ADDRESS revert to (0x1f,0) failed"
      exit 1
    fi
    if grep -n 'PCI_LIB_ADDRESS (0, 0x14, 3,\|EFI_PCI_ADDRESS (0, 0x14, 3' OvmfPkg/Include/IndustryStandard/Q35MchIch9.h; then
      echo "FATAL: PM register address still at AutoVirt (0x14,3)"
      exit 1
    fi

  '';

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
runCommand "sed-contract-edk2"
  {
    nativeBuildInputs = [ patchutils ];
  }
  ''
    src=$(mktemp -d)
    cp -r ${OVMF.src}/* "$src"/
    chmod -R u+w "$src"
    cd "$src"
    ${ovmfPostPatch}
    echo "=== sed-contract-edk2: per-sed guard assertions ==="
    ${allGuardChecks}
    echo "sed-contract-edk2: all ${toString (lib.length guards)} guards passed"
    touch $out
  ''
