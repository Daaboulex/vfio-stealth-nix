{
  lib,
  OVMF,
  fetchurl,
  patchutils,
  secureBoot ? true,
  msVarsTemplate ? secureBoot,
  tpmSupport ? true,
}:
let
  # AutoVirt EDK2 patch removes VM indicators from OVMF firmware:
  # - Clears VirtualMachine bit in SMBIOS Type 0
  # - Replaces Red Hat PCI vendor IDs with AMD/Intel
  # - Renames VMM-prefixed variables
  # - Overrides ACPI OEM fields
  autovirtPatch = fetchurl {
    url = "https://raw.githubusercontent.com/Scrut1ny/Hypervisor-Phantom/bd326182066fccc10ffa4b98047981d1abf6383e/patches/EDK2/AMD-edk2-stable202602.patch";
    hash = "sha256-lNWxQFgkDNapoiLZ4XOFhYQi+t0WR9O3H6CrwPNLrCg=";
  };
in
# Apply patches directly to OVMF via overrideAttrs — nixpkgs OVMF uses
# edk2.src (the raw source), so patching edk2 via overrideAttrs is a
# no-op. The AutoVirt patch includes a BaseTools hunk, but BaseTools is
# a separate pre-built derivation symlinked into the OVMF build tree.
# filterdiff strips that hunk so only OvmfPkg/MdeModulePkg/SecurityPkg
# hunks are applied.
(OVMF.override {
  inherit secureBoot msVarsTemplate tpmSupport;
}).overrideAttrs
  (old: {
    pname = "OVMF-stealth";

    nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [ patchutils ];

    postPatch = (old.postPatch or "") + ''
      echo "=== OVMF-stealth: applying AutoVirt EDK2 patch (BaseTools excluded) ==="
      filterdiff -x '*/BaseTools/*' ${autovirtPatch} | patch -p1 --no-backup-if-mismatch
      echo "=== OVMF-stealth: AutoVirt patch applied ==="

      # Replace firmware vendor string. The PCD default L"EDK II" lives in
      # MdeModulePkg.dec (not the DSC). sed handles CRLF line endings.
      sed -i 's|L"EDK II"|L"American Megatrends Inc."|g' \
        MdeModulePkg/MdeModulePkg.dec OvmfPkg/OvmfPkgX64.dsc 2>/dev/null || true
      if grep -rq 'L"EDK II"' MdeModulePkg/MdeModulePkg.dec OvmfPkg/OvmfPkgX64.dsc; then
        echo "FATAL: firmware vendor string still contains L\"EDK II\""
        exit 1
      fi

      # Strip TianoCore boot logo + BGRT table (VMAware CRC identifier 0x110350C5).
      # Must strip from BOTH DSC (build declaration) and FDF (firmware image
      # inclusion) — EDK2 cross-validates and errors if FDF references a
      # module not declared in DSC. FDF uses CRLF + variable whitespace,
      # so use sed substring match instead of exact-match substituteInPlace.
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

      # Revert AutoVirt's Q35 MCH device ID change (0x14d8 -> 0x29C0).
      # With 0x14d8, OVMF enters the Q35-specific PEI init path which
      # hits a fatal assertion (CpuDeadLoop in PlatformPei). With 0x29C0,
      # OVMF does not recognize the AutoVirt-patched MCH and uses generic
      # platform init instead. The QEMU-side MCH remains 0x14d8 (stealth).
      echo "MCH before: $(grep 'INTEL_Q35_MCH_DEVICE_ID' OvmfPkg/Include/IndustryStandard/Q35MchIch9.h)"
      sed -i 's/define INTEL_Q35_MCH_DEVICE_ID.*$/define INTEL_Q35_MCH_DEVICE_ID    0x29C0/' \
        OvmfPkg/Include/IndustryStandard/Q35MchIch9.h
      echo "MCH after:  $(grep 'INTEL_Q35_MCH_DEVICE_ID' OvmfPkg/Include/IndustryStandard/Q35MchIch9.h)"
      if ! grep -q 'INTEL_Q35_MCH_DEVICE_ID.*0x29C0' OvmfPkg/Include/IndustryStandard/Q35MchIch9.h; then
        echo "FATAL: MCH device ID revert failed"
        grep -n 'MCH_DEVICE_ID\|0x14[dD]8\|0x29[cC]0' OvmfPkg/Include/IndustryStandard/Q35MchIch9.h || true
        exit 1
      fi

      echo "=== OVMF-stealth postPatch complete ==="
    '';

    meta = (old.meta or { }) // {
      description = "OVMF firmware with AutoVirt hardware emulation patches";
    };
  })
