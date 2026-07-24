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
    "${dir}/${prefix}${newest versions}.patch";

  inventory =
    prefix: versions:
    if versions == [ ] then
      "(none)"
    else
      lib.concatMapStringsSep ", " (v: "${prefix}${v}.patch") versions;
in

{
  qemu =
    {
      autovirt,
      qemuVersion,
    }:
    let
      dir = "${autovirt}/patches/QEMU";
      prefix = "AMD-v";
      all = versionsIn dir prefix;
      series = lib.versions.majorMinor qemuVersion;
      inSeries = builtins.filter (v: lib.versions.majorMinor v == series) all;
    in
    assert lib.assertMsg (builtins.pathExists dir)
      "qemu-stealth: ${dir} is absent - AutoVirt restructured patches/";
    assert lib.assertMsg (inSeries != [ ]) ''
      qemu-stealth: AutoVirt ships no ${prefix}${series}.x patch for the QEMU being built (${qemuVersion}).
      Available in ${dir}: ${inventory prefix all}
      Move nixpkgs - or the version floor in qemu/package.nix - to the QEMU series AutoVirt patches.
    '';
    render dir prefix inSeries;

  edk2 =
    { autovirt }:
    let
      dir = "${autovirt}/patches/EDK2";
      prefix = "AMD-edk2-stable";
      all = versionsIn dir prefix;
    in
    assert lib.assertMsg (builtins.pathExists dir)
      "ovmf-stealth: ${dir} is absent - AutoVirt restructured patches/";
    assert lib.assertMsg (all != [ ]) "ovmf-stealth: AutoVirt ships no ${prefix}<tag>.patch in ${dir}";
    render dir prefix all;
}
