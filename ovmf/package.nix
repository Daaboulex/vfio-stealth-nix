{
  lib,
  OVMF,
  autovirt,
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
  autovirtPatch =
    let
      candidates = builtins.filter (n: lib.hasPrefix "AMD-edk2-stable" n && lib.hasSuffix ".patch" n) (
        builtins.attrNames (builtins.readDir "${autovirt}/patches/EDK2")
      );
    in
    assert lib.assertMsg (
      candidates != [ ]
    ) "ovmf-stealth: no AMD-edk2-stable*.patch found in autovirt/patches/EDK2";
    "${autovirt}/patches/EDK2/${builtins.head (lib.sort (a: b: a > b) candidates)}";
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

      # Revert AutoVirt's MCH device ID (0x14D8) to Intel Q35 (0x29C0).
      # The OVMF build enrolls Secure Boot keys by booting inside STOCK
      # QEMU (accel=tcg), whose MCH is 0x29C0. If OVMF expects 0x14D8,
      # Q35 PEI init hangs during the build. The runtime qemu-stealth
      # also uses 0x29C0 (reverted in post-patch.nix) with AMD vendor --
      # keeping all-AMD vendors while matching OVMF's Q35 check.
      sed -i 's/define INTEL_Q35_MCH_DEVICE_ID.*$/define INTEL_Q35_MCH_DEVICE_ID    0x29C0/' \
        OvmfPkg/Include/IndustryStandard/Q35MchIch9.h
      if ! grep -q 'INTEL_Q35_MCH_DEVICE_ID.*0x29C0' OvmfPkg/Include/IndustryStandard/Q35MchIch9.h; then
        echo "FATAL: MCH device ID revert to 0x29C0 failed"
        exit 1
      fi

      # Redirect OVMF debug output from I/O port 0x402 to nowhere.
      # Port 0x402 is a QEMU/OVMF-specific debug artifact; scanning
      # for responsive I/O ports at 0x402 or 0xE9 reveals QEMU.
      # OvmfPkgX64.dsc selects BaseDebugLibSerialPort which writes to
      # 0x3F8 (COM1), not 0x402 — but the IoLib-based fallback in
      # PlatformDebugLibIoPort targets 0x402. Replace with DebugLibNull
      # for release builds to eliminate the port entirely.
      if grep -q 'PlatformDebugLibIoPort' OvmfPkg/OvmfPkgX64.dsc; then
        sed -i 's|OvmfPkg/Library/PlatformDebugLibIoPort/PlatformDebugLibIoPort.inf|MdePkg/Library/BaseDebugLibNull/BaseDebugLibNull.inf|g' \
          OvmfPkg/OvmfPkgX64.dsc
        echo "[OK] OVMF: debug port 0x402 library replaced with DebugLibNull"
      else
        echo "[INFO] OVMF: PlatformDebugLibIoPort not referenced (may already be patched)"
      fi

      echo "=== OVMF-stealth postPatch complete ==="
    '';

    meta = (old.meta or { }) // {
      description = "OVMF firmware with AutoVirt hardware emulation patches";
    };
  })
