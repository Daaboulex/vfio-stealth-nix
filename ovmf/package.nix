{
  lib,
  OVMF,
  autovirt,
  cpuVendor,
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
  autovirtPatch = (import ../lib/autovirt-patches.nix { inherit lib; }).edk2 {
    inherit autovirt cpuVendor;
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

    postPatch = (old.postPatch or "") + (import ./post-patch.nix { inherit autovirtPatch; });

    meta = (old.meta or { }) // {
      description = "OVMF firmware with AutoVirt hardware emulation patches";
    };
  })
