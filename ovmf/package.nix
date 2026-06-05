{
  lib,
  OVMF,
  edk2,
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

  # Patch edk2 source first, then pass to OVMF which wraps it.
  # OVMF in nixpkgs delegates compilation to edk2, so we must patch
  # at the edk2 level for source-level changes to take effect.
  edk2-patched = edk2.overrideAttrs (old: {
    patches = (old.patches or [ ]) ++ [ autovirtPatch ];

    postPatch = (old.postPatch or "") + ''
      # Replace default firmware vendor string with a realistic one
      substituteInPlace OvmfPkg/OvmfPkgX64.dsc \
        --replace-warn 'L"EDK II"' 'L"American Megatrends Inc."' || true

      # Strip TianoCore boot logo + BGRT table (VMAware CRC identifier 0x110350C5)
      # Many real desktops have no BGRT, so absence is normal.
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
      # hits a fatal assertion. With 0x29C0, OVMF does not recognize
      # the AutoVirt-patched MCH and uses generic platform init instead.
      # Proven functional: stock QEMU 10.2.2 (MCH=0x29c0 vs OVMF=0x14d8)
      # boots identically — PCI enumerates, GPU passthrough works,
      # Windows boots. The QEMU-side MCH remains 0x14d8 (stealth).
      echo "=== Reverting MCH device ID in Q35MchIch9.h ==="
      echo "Before: $(grep 'INTEL_Q35_MCH_DEVICE_ID' OvmfPkg/Include/IndustryStandard/Q35MchIch9.h)"
      sed -i 's/define INTEL_Q35_MCH_DEVICE_ID.*$/define INTEL_Q35_MCH_DEVICE_ID    0x29C0/' \
        OvmfPkg/Include/IndustryStandard/Q35MchIch9.h
      echo "After:  $(grep 'INTEL_Q35_MCH_DEVICE_ID' OvmfPkg/Include/IndustryStandard/Q35MchIch9.h)"
      if ! grep -q 'INTEL_Q35_MCH_DEVICE_ID.*0x29C0' OvmfPkg/Include/IndustryStandard/Q35MchIch9.h; then
        echo "FATAL: MCH device ID revert failed — INTEL_Q35_MCH_DEVICE_ID not set to 0x29C0"
        echo "File contents:"
        grep -n 'MCH_DEVICE_ID\|0x14[dD]8\|0x29[cC]0' OvmfPkg/Include/IndustryStandard/Q35MchIch9.h || true
        exit 1
      fi
    '';
  });
in
# Override OVMF to use our patched edk2 source tree.
# OVMF accepts `edk2` as an input — swapping it propagates all patches
# into the final firmware binary (OVMF_CODE.fd / OVMF_VARS.fd).
(OVMF.override {
  edk2 = edk2-patched;
  inherit secureBoot msVarsTemplate tpmSupport;
}).overrideAttrs
  (old: {
    pname = "OVMF-stealth";
    meta = (old.meta or { }) // {
      description = "OVMF firmware with AutoVirt hardware emulation patches";
    };
  })
