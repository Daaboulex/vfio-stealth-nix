{
  lib,
  fetchurl,
  python3Packages,
  runCommand,
}:

let
  minimumVersion = "11.0.1";
  ceiling = "11.0.3";
  tarballHashes = {
    "11.0.1" = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
    "11.0.3" = "sha256-BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB=";
  };

  fakeQemu =
    version:
    let
      self = {
        inherit version;
        overrideAttrs = f: self // (f self);
      };
    in
    self;

  select =
    qemu:
    import ../lib/select-qemu-base.nix {
      inherit
        lib
        qemu
        fetchurl
        python3Packages
        minimumVersion
        ceiling
        tarballHashes
        ;
    };

  baseFor = version: select (fakeQemu version);

  resolves = expr: builtins.tryEval (builtins.seq expr true);

  cases = [
    {
      name = "in-series-qemu-passes-through-untouched";
      ok =
        let
          q = fakeQemu "11.0.3";
        in
        select q == q;
      detail = "expected the caller's qemu untouched when its version is within the floor-ceiling band";
    }
    {
      name = "below-floor-builds-the-floor-tarball";
      ok =
        let
          base = baseFor "10.2.9";
        in
        base.version == "11.0.1" && lib.hasInfix "qemu-11.0.1.tar.xz" base.src.url;
      detail = "expected the 11.0.1 tarball build for a QEMU below the floor";
    }
    {
      name = "above-ceiling-builds-the-ceiling-tarball";
      ok =
        let
          base = baseFor "12.0.0";
        in
        base.version == "11.0.3" && lib.hasInfix "qemu-11.0.3.tar.xz" base.src.url;
      detail = "expected the 11.0.3 tarball build for a QEMU above the ceiling";
    }
    {
      name = "missing-ceiling-hash-fails-closed";
      ok =
        !(resolves (
          import ../lib/select-qemu-base.nix {
            inherit
              lib
              fetchurl
              python3Packages
              minimumVersion
              ceiling
              ;
            qemu = fakeQemu "12.0.0";
            tarballHashes = {
              "11.0.1" = tarballHashes."11.0.1";
            };
          }
        )).success;
      detail = "expected evaluation to fail when the ceiling has no tarball hash";
    }
    {
      name = "ceiling-below-floor-fails-closed";
      ok =
        !(resolves (
          import ../lib/select-qemu-base.nix {
            inherit
              lib
              fetchurl
              python3Packages
              minimumVersion
              tarballHashes
              ;
            qemu = fakeQemu "11.0.3";
            ceiling = "10.2.2";
          }
        )).success;
      detail = "expected evaluation to fail when the ceiling is below the floor";
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
