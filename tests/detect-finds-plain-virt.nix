{
  lib,
  testers,
  stealth-detect-arm64,
}:

# QEMU runs this under accel=kvm:tcg either way, but Nix's "kvm" system feature
# refuses to schedule the build at all without /dev/kvm, which no GitHub-hosted
# aarch64 runner exposes (actions/runner-images#14062). Timeouts are sized for
# TCG, measured at 110s on an M1.
(testers.runNixOSTest {
  name = "detect-finds-plain-virt";
  globalTimeout = 1800;

  nodes.machine = {
    environment.systemPackages = [ stealth-detect-arm64 ];
  };

  testScript = ''
    import json

    machine.wait_for_unit("multi-user.target", timeout=900)

    status, out = machine.execute("stealth-detect-arm64 --json")
    print(out)

    if status != 1:
        raise Exception(f"expected exit 1 on a plain QEMU virt guest, got {status}")

    report = json.loads(out)
    detected = set(report["detected"])
    verdicts = {f["vector"]: f["verdict"] for f in report["findings"]}

    missing = {"dt-machine-compatible", "dt-psci-conduit", "virtio-bus"} - detected
    if missing:
        raise Exception(f"these vectors did not fire on a plain QEMU virt guest: {sorted(missing)}")

    unreadable = {v for v, verdict in verdicts.items() if verdict == "unknown"}
    unmeasured = {"acpi-oem", "acpi-hypervisor-id"} - unreadable
    if unmeasured:
        raise Exception(f"this guest exposes no ACPI, so these must report unknown: {sorted(unmeasured)}")
  '';
}).overrideTestDerivation
  (old: {
    requiredSystemFeatures = lib.remove "kvm" (old.requiredSystemFeatures or [ ]);
  })
