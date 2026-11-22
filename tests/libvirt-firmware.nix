{
  testers,
  writeText,
  module,
  cpuVendor,
}:

let
  domain = writeText "firmware-probe.xml" ''
    <domain type="qemu">
      <name>firmware-probe</name>
      <memory unit="MiB">256</memory>
      <vcpu>1</vcpu>
      <os firmware="efi">
        <type arch="x86_64" machine="q35">hvm</type>
      </os>
      <features>
        <acpi/>
        <smm state="on"/>
      </features>
      <devices>
        <console type="pty"/>
      </devices>
    </domain>
  '';
in
testers.runNixOSTest {
  name = "libvirt-firmware-${cpuVendor}";
  node.pkgsReadOnly = false;
  nodes.machine = {
    imports = [ module ];
    virtualisation.memorySize = 2048;
    virtualisation.libvirtd.enable = true;
    virtualisation.vfio-stealth = {
      enable = true;
      inherit cpuVendor;
      smbios.manufacturer = "Example Inc.";
      smbios.product = "Example Board";
      hypervVendorId = "ExampleVndr";
      domains.nixvirt-probe = {
        uuid = "22222222-3333-4444-5555-666666666666";
        memory = 256;
        cores = 1;
        threads = 1;
        display = "none";
      };
    };
  };
  testScript = ''
    machine.wait_for_unit("libvirtd.service")
    machine.wait_until_succeeds("virsh -c qemu:///system dominfo nixvirt-probe")
    status, report = machine.execute("vfio-stealth-verify-host nixvirt-probe")
    print(report)
    host_only = ("IOMMU", "Kernel parameter", "BetterTiming")
    failures = [line for line in report.splitlines() if "[FAIL]" in line and not any(word in line for word in host_only)]
    if failures:
        raise Exception(f"the NixVirt-defined domain fails the host check: {failures}")
    for expected in ("the domain has a sysinfo block", "os smbios mode is sysinfo", "KVM hidden: on", "Hyper-V vendor_id: ExampleVndr", "No VirtIO balloon or RNG", "No <panic> device", "SMBIOS tables: all present", "is qemu-stealth", "ACPI OEM ID replaced"):
        if expected not in report:
            raise Exception(f"the host check did not report {expected!r} for the NixVirt-defined domain")
    import re

    def resolve(path):
        return machine.succeed(f"readlink -f {path}").strip()

    caps = machine.succeed("virsh -c qemu:///system domcapabilities --machine q35 --arch x86_64 --virttype qemu")
    offered = re.findall(r"<value>(/[^<]+\.fd)</value>", caps)
    if not offered:
        raise Exception(f"libvirt offers no UEFI firmware at all:\n{caps}")
    for path in offered:
        if "OVMF-stealth" not in resolve(path):
            raise Exception(f"libvirt offers {path}, which is not OVMF-stealth but {resolve(path)}")

    machine.succeed("virsh -c qemu:///system define ${domain}")
    machine.succeed("virsh -c qemu:///system start firmware-probe")
    machine.wait_until_succeeds('test "$(virsh -c qemu:///system domstate firmware-probe)" = running')
    loader = machine.succeed("virsh -c qemu:///system dumpxml firmware-probe | sed -n 's|.*<loader[^>]*>\\([^<]*\\)</loader>.*|\\1|p'").strip()
    if "OVMF-stealth" not in resolve(loader):
        raise Exception(f"a VM asking only for firmware='efi' got {loader}, not OVMF-stealth")
  '';
}
