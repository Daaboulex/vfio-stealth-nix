{ lib }:

let
  featureRequires = {
    vapic = [ "KVM_HYPERV" ];
    spinlocks = [ "KVM_HYPERV" ];
    frequencies = [ "KVM_HYPERV" ];
    vpindex = [ "KVM_HYPERV" ];
    synic = [ "KVM_HYPERV" ];
    stimer = [ "KVM_HYPERV" ];
    reset = [ "KVM_HYPERV" ];
    ipi = [ "KVM_HYPERV" ];
    tlbflush = [ "KVM_HYPERV" ];
    reenlightenment = [ "KVM_HYPERV" ];
    runtime = [ "KVM_HYPERV" ];
  };

  universalFeatures = [
    "vendor_id"
    "relaxed"
  ];

  allFeatures = universalFeatures ++ builtins.attrNames featureRequires;

  fromConfigText =
    configText:
    let
      hasConfigOption = opt: builtins.match ".*CONFIG_${opt}=y[ \t]*.*" configText != null;
      kernelDeps = lib.mapAttrs (
        _feature: requiredOpts: lib.all hasConfigOption requiredOpts
      ) featureRequires;
    in
    kernelDeps // lib.genAttrs universalFeatures (_: true);

  fromConfigPath =
    path: if !(builtins.pathExists path) then null else fromConfigText (builtins.readFile path);

  emptyCapabilities = lib.genAttrs allFeatures (_: false);
in
{
  inherit
    featureRequires
    universalFeatures
    allFeatures
    fromConfigText
    fromConfigPath
    emptyCapabilities
    ;
}
