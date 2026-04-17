{
  lib,
  OVMF,
  edk2,
  fetchurl,
}:
let
  # AutoVirt EDK2 patch removes VM indicators from OVMF firmware:
  # - Clears VirtualMachine bit in SMBIOS Type 0
  # - Replaces Red Hat PCI vendor IDs with AMD/Intel
  # - Renames VMM-prefixed variables
  # - Spoofs ACPI OEM fields
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
    '';
  });
in
# Override OVMF to use our patched edk2 source tree.
# OVMF accepts `edk2` as an input — swapping it propagates all patches
# into the final firmware binary (OVMF_CODE.fd / OVMF_VARS.fd).
(OVMF.override { edk2 = edk2-patched; }).overrideAttrs (old: {
  pname = "OVMF-stealth";
  meta = (old.meta or { }) // {
    description = "OVMF firmware with AutoVirt anti-detection patches";
  };
})
