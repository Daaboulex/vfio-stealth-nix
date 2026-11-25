{ lib }:
{
  cpuVendor,
  instructionFixes,
  timing,
  cpuidSpoof,
  cpuidPassthrough,
  pinnedCpuid,
}:
let
  scripts =
    lib.optionalString instructionFixes (import ./instruction-fixes.nix)
    + lib.optionalString (instructionFixes && cpuVendor == "amd") (import ./svm-instruction-fixes.nix)
    + lib.optionalString pinnedCpuid (import ./pinned-cpuid-passthrough.nix)
    + lib.optionalString timing (import ./timing-patch.nix)
    + lib.optionalString (cpuidSpoof && !cpuidPassthrough) (import ./cpuid-patch.nix)
    + lib.optionalString cpuidPassthrough (import ./cpuid-disable.nix);
in
{
  script = lib.optionalString (scripts != "") (import ./prelude.nix) + scripts;
  refusals =
    lib.optional (cpuVendor == "intel" && (timing || cpuidSpoof || cpuidPassthrough || pinnedCpuid))
      "virtualisation.vfio-stealth: timing.enable, cpuidSpoof.enable, cpuidPassthrough.enable and cpuidPassthrough.pinned require cpuVendor \"amd\"; they patch KVM's SVM code, which kvm-intel never runs"
    ++
      lib.optional (cpuidPassthrough && pinnedCpuid)
        "virtualisation.vfio-stealth.cpuidPassthrough: enable stops every CPUID exit already, so pinned has nothing to switch; set one";
}
