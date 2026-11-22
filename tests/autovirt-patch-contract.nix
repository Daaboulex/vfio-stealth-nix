{
  lib,
  runCommand,
}:

let
  resolve = import ../lib/autovirt-patches.nix { inherit lib; };
  autovirt = ./fixtures/autovirt;

  resolves = expr: builtins.tryEval (builtins.seq expr true);

  qemuFor =
    qemuVersion:
    resolve.qemu {
      inherit autovirt qemuVersion;
      cpuVendor = "amd";
    };

  intelFor =
    qemuVersion:
    resolve.qemu {
      inherit autovirt qemuVersion;
      cpuVendor = "intel";
    };

  cases = [
    {
      name = "qemu-picks-highest-by-version-not-string-order";
      ok = baseNameOf (qemuFor "11.0.1") == "AMD-v11.0.10.patch";
      detail = "expected AMD-v11.0.10.patch, got ${baseNameOf (qemuFor "11.0.1")}";
    }
    {
      name = "qemu-ignores-other-vendor-prefix";
      ok = !lib.hasPrefix "Intel-" (baseNameOf (qemuFor "11.0.1"));
      detail = "resolver selected an Intel patch: ${baseNameOf (qemuFor "11.0.1")}";
    }
    {
      name = "qemu-fails-closed-outside-the-series";
      ok = !(resolves (qemuFor "12.0.0")).success;
      detail = "resolver returned a patch for a QEMU series AutoVirt does not ship";
    }
    {
      name = "edk2-picks-highest-tag";
      ok =
        baseNameOf (
          resolve.edk2 {
            inherit autovirt;
            cpuVendor = "amd";
          }
        ) == "AMD-edk2-stable202605.patch";
      detail = "expected AMD-edk2-stable202605.patch, got ${
        baseNameOf (
          resolve.edk2 {
            inherit autovirt;
            cpuVendor = "amd";
          }
        )
      }";
    }
    {
      name = "intel-vendor-selects-intel-patch";
      ok = baseNameOf (intelFor "11.0.1") == "Intel-v11.0.10.patch";
      detail = "expected Intel-v11.0.10.patch, got ${baseNameOf (intelFor "11.0.1")}";
    }
    {
      name = "unknown-vendor-fails-closed";
      ok =
        !(resolves (
          resolve.qemu {
            inherit autovirt;
            qemuVersion = "11.0.1";
            cpuVendor = "sparc";
          }
        )).success;
      detail = "resolver accepted an unknown cpuVendor";
    }
    {
      name = "qemu-series-lists-unique-major-minor-per-vendor";
      ok =
        resolve.qemuSeries {
          inherit autovirt;
          cpuVendor = "amd";
        } == [ "11.0" ]
        &&
          resolve.qemuSeries {
            inherit autovirt;
            cpuVendor = "intel";
          } == [ "11.0" ];
      detail = "expected [ \"11.0\" ] for both vendors on the fixture inventory";
    }
  ];

  failures = builtins.filter (c: !c.ok) cases;

  report = lib.concatMapStringsSep "\n" (c: "  FAIL: ${c.name} - ${c.detail}") failures;
in

runCommand "autovirt-patch-contract" { } (
  if failures == [ ] then
    ''
      echo "autovirt-patch-contract: all ${toString (lib.length cases)} cases passed"
      touch $out
    ''
  else
    ''
      echo "=== autovirt-patch-contract ==="
      echo ${lib.escapeShellArg report}
      exit 1
    ''
)
