{
  lib,
  fetchurl,
  python3Packages,
  runCommand,
}:

let
  defaultFloor = "11.0.3";
  defaultCeiling = "11.1.0";
  defaultSeries = [
    "11.0"
    "11.1"
  ];
  defaultHashes = {
    "11.0.3" = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
    "11.1.0" = "sha256-BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB=";
  };

  fakeQemu =
    version:
    let
      self = {
        inherit version;
        src = "pristine-${version}";
        overrideAttrs = f: self // (f self);
      };
    in
    self;

  select =
    {
      qemuVersion,
      minimumVersion ? defaultFloor,
      ceiling ? defaultCeiling,
      tarballHashes ? defaultHashes,
      patchedSeries ? defaultSeries,
    }:
    import ../lib/select-qemu-base.nix {
      inherit
        lib
        fetchurl
        python3Packages
        minimumVersion
        ceiling
        tarballHashes
        patchedSeries
        ;
      qemu = fakeQemu qemuVersion;
    };

  resolves = expr: builtins.tryEval (builtins.seq expr true);

  tarballOf = version: select { qemuVersion = version; };

  cases = [
    {
      name = "exact-patched-version-passes-through-untouched";
      ok =
        let
          base = select { qemuVersion = "11.1.0"; };
        in
        base.src == "pristine-11.1.0" && base.version == "11.1.0";
      detail = "expected the caller's qemu source untouched when its exact version has a vendored patch";
    }
    {
      name = "floor-version-passes-through-when-patched";
      ok =
        let
          base = select { qemuVersion = "11.0.3"; };
        in
        base.src == "pristine-11.0.3" && base.version == "11.0.3";
      detail = "expected the floor version to pass through when its series is patched";
    }
    {
      name = "in-series-point-release-passes-through";
      ok =
        let
          base = select { qemuVersion = "11.0.5"; };
        in
        base.src == "pristine-11.0.5" && base.version == "11.0.5";
      detail = "expected a point release in a patched series to pass through";
    }
    {
      name = "below-floor-builds-the-floor-tarball";
      ok =
        let
          base = tarballOf "10.2.9";
        in
        base.version == "11.0.3" && lib.hasInfix "qemu-11.0.3.tar.xz" base.src.url;
      detail = "expected the 11.0.3 tarball build for a QEMU below the floor";
    }
    {
      name = "above-ceiling-builds-the-ceiling-tarball";
      ok =
        let
          base = tarballOf "12.0.0";
        in
        base.version == "11.1.0" && lib.hasInfix "qemu-11.1.0.tar.xz" base.src.url;
      detail = "expected the 11.1.0 tarball build for a QEMU above the ceiling";
    }
    {
      name = "in-band-unpatched-series-builds-the-ceiling-tarball";
      ok =
        let
          base = select {
            qemuVersion = "11.2.0";
            ceiling = "11.3.0";
            patchedSeries = [
              "11.0"
              "11.3"
            ];
            tarballHashes = {
              "11.0.3" = defaultHashes."11.0.3";
              "11.3.0" = "sha256-CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC=";
            };
          };
        in
        base.version == "11.3.0" && lib.hasInfix "qemu-11.3.0.tar.xz" base.src.url;
      detail = "expected the ceiling tarball for an in-band QEMU whose series has no vendored patch";
    }
    {
      name = "missing-ceiling-hash-fails-closed";
      ok =
        !(resolves (select {
          qemuVersion = "12.0.0";
          tarballHashes = {
            "11.0.3" = defaultHashes."11.0.3";
          };
        })).success;
      detail = "expected evaluation to fail when the ceiling has no tarball hash";
    }
    {
      name = "ceiling-below-floor-fails-closed";
      ok =
        !(resolves (select {
          qemuVersion = "11.0.3";
          ceiling = "10.2.2";
        })).success;
      detail = "expected evaluation to fail when the ceiling is below the floor";
    }
    {
      name = "floor-series-unpatched-fails-closed";
      ok =
        !(resolves (select {
          qemuVersion = "11.1.0";
          patchedSeries = [ "11.1" ];
        })).success;
      detail = "expected evaluation to fail when the floor series has no vendored patch";
    }
  ];

  failures = builtins.filter (c: !c.ok) cases;

  report = lib.concatMapStringsSep "\n" (c: "  FAIL: ${c.name} - ${c.detail}") failures;
in

runCommand "qemu-ceiling-contract" { } (
  if failures == [ ] then
    ''
      echo "qemu-ceiling-contract: all ${toString (lib.length cases)} cases passed"
      touch $out
    ''
  else
    ''
      echo "=== qemu-ceiling-contract ==="
      echo ${lib.escapeShellArg report}
      exit 1
    ''
)
