{ lib }:

let
  # Map each kernel-dependent Hyper-V enlightenment to the CONFIG_* options
  # the KVM module requires to advertise it via KVM_CHECK_EXTENSION.
  #
  # Verified against the Linux kernel source arch/x86/kvm/x86.c:4817-4831:
  # every KVM_CAP_HYPERV_* cap (VAPIC, SPIN, TIME, SYNIC, SYNIC2,
  # VP_INDEX, TLBFLUSH, SEND_IPI) sits inside a single #ifdef
  # CONFIG_KVM_HYPERV block. Add a feature here ONLY after verifying
  # it has its own KVM cap gated by KVM_HYPERV in the source.
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

  # Universal features: no KVM cap at all, libvirt/QEMU-emulated only.
  # Verified by absence from the kernel's KVM_CHECK_EXTENSION switch.
  universalFeatures = [
    "vendor_id"
    "relaxed"
  ];

  allFeatures = universalFeatures ++ builtins.attrNames featureRequires;

  # fromConfigText: parse a kernel .config text and return a capability attrset
  # keyed by feature name. Universal features are always true. Kernel-dependent
  # features are true only if every CONFIG option they require is =y in the
  # config text.
  fromConfigText =
    configText:
    let
      hasConfigOption = opt: builtins.match ".*CONFIG_${opt}=y[ \t]*.*" configText != null;
      kernelDeps = lib.mapAttrs (
        feature: requiredOpts: lib.all hasConfigOption requiredOpts
      ) featureRequires;
    in
    kernelDeps // lib.genAttrs universalFeatures (_: true);

  # fromConfigPath: read a .config file from a path. Returns null if the file
  # does not exist (consumer falls back to setting the attrset by hand or
  # points at a different path). Expects an uncompressed .config; for
  # /proc/config.gz the consumer must gunzip first (the path will not exist
  # at eval time anyway since /proc is not in the Nix store).
  fromConfigPath =
    path: if !(builtins.pathExists path) then null else fromConfigText (builtins.readFile path);

  # Empty capabilities: every feature reported as unsupported. Useful for
  # negative tests in the contract suite.
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
