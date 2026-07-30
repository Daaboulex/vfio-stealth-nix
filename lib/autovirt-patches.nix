{ lib }:

let
  versionsIn =
    dir: prefix:
    map (n: lib.removeSuffix ".patch" (lib.removePrefix prefix n)) (
      builtins.filter (n: lib.hasPrefix prefix n && lib.hasSuffix ".patch" n) (
        builtins.attrNames (builtins.readDir dir)
      )
    );

  newest = versions: builtins.head (lib.sort (a: b: builtins.compareVersions a b > 0) versions);

  render =
    dir: prefix: versions:
    dir + "/${prefix}${newest versions}.patch";

  inventory =
    prefix: versions:
    if versions == [ ] then
      "(none)"
    else
      lib.concatMapStringsSep ", " (v: "${prefix}${v}.patch") versions;

  traits = {
    amd = {
      family = "AMD";
      patchedOemId = "ALASKA";
      patchedOemTableId = "A M I   ";
    };
    intel = {
      family = "Intel";
      patchedOemId = "INTEL ";
      patchedOemTableId = "U Rvp   ";
    };
  };

  familyOf =
    cpuVendor:
    assert lib.assertMsg (traits ? ${cpuVendor})
      "vfio-stealth: unknown cpuVendor ${cpuVendor}; expected one of ${lib.concatStringsSep ", " (builtins.attrNames traits)}";
    traits.${cpuVendor}.family;
in

{
  inherit traits;

  qemu =
    {
      autovirt,
      qemuVersion,
      cpuVendor,
    }:
    let
      dir = autovirt + "/patches/QEMU";
      prefix = "${familyOf cpuVendor}-v";
      all = versionsIn dir prefix;
      series = lib.versions.majorMinor qemuVersion;
      inSeries = builtins.filter (v: lib.versions.majorMinor v == series) all;
    in
    assert lib.assertMsg (builtins.pathExists dir)
      "qemu-stealth: ${toString dir} is absent - AutoVirt restructured patches/";
    assert lib.assertMsg (inSeries != [ ]) ''
      qemu-stealth: AutoVirt ships no ${prefix}${series}.x patch for the QEMU being built (${qemuVersion}).
      Available in ${toString dir}: ${inventory prefix all}
      Move nixpkgs - or the version floor in qemu/package.nix - to the QEMU series AutoVirt patches.
    '';
    render dir prefix inSeries;

  edk2 =
    { autovirt, cpuVendor }:
    let
      dir = autovirt + "/patches/EDK2";
      prefix = "${familyOf cpuVendor}-edk2-stable";
      all = versionsIn dir prefix;
    in
    assert lib.assertMsg (builtins.pathExists dir)
      "ovmf-stealth: ${toString dir} is absent - AutoVirt restructured patches/";
    assert lib.assertMsg (
      all != [ ]
    ) "ovmf-stealth: AutoVirt ships no ${prefix}<tag>.patch in ${toString dir}";
    render dir prefix all;
}
