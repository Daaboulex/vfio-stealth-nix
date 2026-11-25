{
  lib,
  nixosSystem,
  module,
}:

let
  switches = [
    {
      name = "instruction-fixes";
      path = [
        "instructionFixes"
        "enable"
      ];
    }
    {
      name = "pinned-cpuid";
      path = [
        "cpuidPassthrough"
        "pinned"
      ];
    }
    {
      name = "timing";
      path = [
        "timing"
        "enable"
      ];
    }
    {
      name = "cpuid-spoof";
      path = [
        "cpuidSpoof"
        "enable"
      ];
    }
    {
      name = "cpuid-passthrough";
      path = [
        "cpuidPassthrough"
        "enable"
      ];
    }
  ];

  settingsTheKernelIgnores = [
    { hypervMode = "enlightened"; }
    { hypervMode = "hidden"; }
  ];

  subsets = lib.foldr (switch: rest: rest ++ map (chosen: [ switch ] ++ chosen) rest) [
    [ ]
  ] switches;

  evaluate =
    cpuVendor: settings:
    (nixosSystem {
      system = "x86_64-linux";
      modules = [
        module
        {
          virtualisation.vfio-stealth = {
            enable = true;
            inherit cpuVendor;
          }
          // settings;
          virtualisation.libvirtd.enable = true;
          fileSystems."/" = {
            device = "/dev/disk/by-label/nixos";
            fsType = "ext4";
          };
          boot.loader.grub.enable = false;
          system.stateVersion = lib.trivial.release;
        }
      ];
    }).config;

  accepts = config: lib.all (a: a.assertion) config.assertions;

  variantOf =
    cpuVendor: chosen:
    let
      switched = lib.foldl' lib.recursiveUpdate { } (
        map (switch: lib.setAttrByPath switch.path (lib.elem switch chosen)) switches
      );
      accepting = lib.findFirst accepts null (
        map (extra: evaluate cpuVendor (switched // extra)) settingsTheKernelIgnores
      );
    in
    lib.optional (accepting != null) (
      let
        variant = {
          name =
            lib.optionalString (cpuVendor == "intel") "intel-"
            + lib.concatMapStringsSep "+" (switch: switch.name) chosen;
          body = accepting.virtualisation.vfio-stealth.kernelPostPatch;
        };
      in
      builtins.deepSeq variant variant
    );

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
