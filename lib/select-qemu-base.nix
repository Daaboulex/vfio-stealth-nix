{
  lib,
  qemu,
  fetchurl,
  python3Packages,
  minimumVersion,
  ceiling,
  tarballHashes,
}:

assert lib.assertMsg (builtins.compareVersions ceiling minimumVersion >= 0)
  "qemu-stealth: the patch ceiling ${ceiling} is below the minimum QEMU ${minimumVersion}. Vendor a patch for at least QEMU ${minimumVersion}";
assert lib.assertMsg (builtins.hasAttr minimumVersion tarballHashes)
  "qemu-stealth: no tarball hash for the QEMU floor ${minimumVersion}";
assert lib.assertMsg (builtins.hasAttr ceiling tarballHashes)
  "qemu-stealth: no tarball hash for the QEMU ceiling ${ceiling}. Add it to tarballHashes in qemu/package.nix";

let
  tarball =
    version:
    qemu.overrideAttrs (old: {
      inherit version;
      src = fetchurl {
        url = "https://download.qemu.org/qemu-${version}.tar.xz";
        hash = tarballHashes.${version};
      };
      patches = [ ];
      # QEMU 11's mkvenv needs Python packages that 10.2.x's packaging doesn't provide.
      nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [
        python3Packages.setuptools
        python3Packages.pip
        python3Packages.wheel
      ];
    });
in

if builtins.compareVersions qemu.version minimumVersion < 0 then
  tarball minimumVersion
else if builtins.compareVersions qemu.version ceiling > 0 then
  tarball ceiling
else
  qemu
