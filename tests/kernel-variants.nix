{ lib }:

let
  kernelPatch = import ../kernel/post-patch.nix { inherit lib; };

  switches = [
    {
      name = "instruction-fixes";
      key = "instructionFixes";
    }
    {
      name = "pinned-cpuid";
      key = "pinnedCpuid";
    }
    {
      name = "timing";
      key = "timing";
    }
    {
      name = "cpuid-spoof";
      key = "cpuidSpoof";
    }
    {
      name = "cpuid-passthrough";
      key = "cpuidPassthrough";
    }
  ];

  subsets = lib.foldr (switch: rest: rest ++ map (chosen: [ switch ] ++ chosen) rest) [
    [ ]
  ] switches;

  variantOf =
    cpuVendor: chosen:
    let
      patch = kernelPatch (
        {
          inherit cpuVendor;
        }
        // lib.listToAttrs (map (switch: lib.nameValuePair switch.key (lib.elem switch chosen)) switches)
      );
    in
    lib.optional (patch.refusals == [ ]) {
      name =
        lib.optionalString (cpuVendor == "intel") "intel-"
        + lib.concatMapStringsSep "+" (switch: switch.name) chosen;
      body = patch.script;
    };

  variants =
    lib.foldl'
      (
        kept: variant:
        if variant.body == "" || lib.any (other: other.body == variant.body) kept then
          kept
        else
          kept ++ [ variant ]
      )
      [ ]
      (
        lib.concatMap (cpuVendor: lib.concatMap (variantOf cpuVendor) subsets) [
          "amd"
          "intel"
        ]
      );

  unreached = lib.filter (
    switch:
    !lib.any (
      variant: lib.elem switch.name (lib.splitString "+" (lib.removePrefix "intel-" variant.name))
    ) variants
  ) switches;
in
assert lib.assertMsg (unreached == [ ])
  "kernel-variants: no combination the module accepts turns on ${
    lib.concatMapStringsSep ", " (switch: switch.name) unreached
  }, so its script is never applied";
variants
