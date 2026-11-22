{
  lib,
  OVMF,
  autovirt,
  cpuVendor,
  patchutils,
  secureBoot ? true,
  msVarsTemplate ? false,
  tpmSupport ? true,
  firmwareVendor ? "American Megatrends Inc.",
  acpiOemId ? "ALASKA",
  acpiOemTableId ? "A M I   ",
  patchAssertions,
}:
let
  autovirtPatch = (import ../lib/autovirt-patches.nix { inherit lib; }).edk2 {
    inherit autovirt cpuVendor;
  };
in
assert lib.assertMsg (
  !(lib.hasInfix "'" firmwareVendor || lib.hasInfix "\"" firmwareVendor)
) "ovmf-stealth: firmwareVendor may not contain a quote, got '${firmwareVendor}'";
# why: nixpkgs OVMF builds from edk2.src with a prebuilt BaseTools, so the patch goes on OVMF without its BaseTools hunk
(OVMF.override {
  inherit secureBoot msVarsTemplate tpmSupport;
}).overrideAttrs
  (old: {
    pname = "OVMF-stealth";

    nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [ patchutils ];

    postPatch =
      (old.postPatch or "")
      + (import ./post-patch.nix {
        inherit
          lib
          autovirtPatch
          patchAssertions
          firmwareVendor
          acpiOemId
          acpiOemTableId
          ;
      });

    meta = (old.meta or { }) // {
      description = "OVMF firmware with AutoVirt hardware emulation patches";
      platforms = [ "x86_64-linux" ];
    };
  })
