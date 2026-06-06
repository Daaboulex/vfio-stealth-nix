{
  lib,
  OVMF,
  fetchurl,
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
# Apply patches directly to OVMF via overrideAttrs. The previous
# approach (edk2.overrideAttrs → OVMF.override { edk2 = patched; })
# was a no-op: nixpkgs OVMF uses edk2.src (the raw source attribute),
# not the built edk2 output, so edk2's patches/postPatch never reached
# the OVMF build. Applying via OVMF.overrideAttrs puts the patches
# into OVMF's own patchPhase/postPatch, where they act on the actual
# source that gets compiled into OVMF_CODE.fd.
(OVMF.override {
  inherit secureBoot msVarsTemplate tpmSupport;
}).overrideAttrs
  (old: {
    pname = "OVMF-stealth";

    patches = (old.patches or [ ]) ++ [ autovirtPatch ];

    postPatch = (old.postPatch or "") + ''
      echo "=== OVMF-stealth postPatch ==="

      # Replace default firmware vendor string with a realistic one
      substituteInPlace OvmfPkg/OvmfPkgX64.dsc \
        --replace-warn 'L"EDK II"' 'L"American Megatrends Inc."' || true

      # Strip TianoCore boot logo + BGRT table (VMAware CRC identifier 0x110350C5)
      substituteInPlace OvmfPkg/OvmfPkgX64.dsc \
        --replace-warn \
          'MdeModulePkg/Universal/Acpi/BootGraphicsResourceTableDxe/BootGraphicsResourceTableDxe.inf' \
          '# stripped: BootGraphicsResourceTableDxe' || true
      substituteInPlace OvmfPkg/OvmfPkgX64.fdf \
        --replace-warn \
          'INF MdeModulePkg/Logo/LogoDxe.inf' \
          '# stripped: LogoDxe' || true

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
