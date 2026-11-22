{
  lib,
  testers,
  module,
  harness,
  installed,
  cpuVendor,
  settings,
}:

let
  uuid = "5f0c7a52-3b1e-4c6a-9d2e-7a4b8c9d0e1f";
  image = builtins.storePath (toString installed);
in
testers.runNixOSTest {
  name = "libvirt-windows-${cpuVendor}";
  globalTimeout = 7200;
  node.pkgsReadOnly = false;
  nodes.host =
    { config, pkgs, ... }:
    {
      imports = [ module ];
      virtualisation = {
        memorySize = 8192;
        cores = 8;
        diskSize = 16384;
        libvirtd.enable = true;
        vfio-stealth = lib.recursiveUpdate {
          enable = true;
          inherit cpuVendor;
          smbios.manufacturer = "Example Inc.";
          smbios.product = "Example Board";
          acpiOem.id = "TSTOEM";
          acpiOem.tableId = "EXAMPLE1";
          domains.windows = {
            inherit uuid;
            memory = 4096;
            cores = 2;
            disks = [
              {
                source = "/var/lib/windows/disk.qcow2";
                format = "qcow2";
                cache = "writeback";
              }
            ];
            cdroms = [ "/var/lib/windows/probe.iso" ];
            tpm = true;
            secureBoot = true;
            extraQemuArgs = [
              "-chardev"
              "file,id=probe-serial,path=/var/lib/windows/serial.log"
              "-device"
              "isa-serial,chardev=probe-serial,index=0"
            ];
          };
        } settings;
      };
      boot.kernelPackages = pkgs.linuxPackagesFor (
        config.virtualisation.vfio-stealth.packages.kernelFor pkgs.linux_latest
      );
      environment.systemPackages = [ config.virtualisation.vfio-stealth.packages.qemu ];
    };
  testScript = ''
    import json
    import os
    import subprocess
    import sys
    import time

    out = os.environ["out"]
    host.wait_for_unit("libvirtd.service")
    host.wait_until_succeeds("virsh -c qemu:///system dominfo windows")
    handlers = host.succeed("awk '$3 == \"handle_rdtsc_interception\" { print $3 }' /proc/kallsyms | wc -l").strip()
    print(f"libvirt-windows: host kernel {host.succeed('uname -r').strip()}, timing handlers {handlers}")
    host.succeed(
        "mkdir -p /var/lib/windows",
        "qemu-img create -q -f qcow2 -F qcow2 -b ${image}/disk.qcow2 /var/lib/windows/disk.qcow2",
        "cp ${harness.media}/probe.iso /var/lib/windows/probe.iso",
        "install -m 0644 ${image}/vars.fd /var/lib/libvirt/qemu/nvram/windows_VARS.fd",
        "mkdir -p /var/lib/libvirt/swtpm/${uuid}/tpm2",
        "cp -r ${image}/tpm/. /var/lib/libvirt/swtpm/${uuid}/tpm2/",
        "chmod -R u+w /var/lib/libvirt/swtpm/${uuid}",
    )
    began = time.monotonic()
    host.succeed("virsh -c qemu:///system start windows")
    stalled = None
    while host.execute("virsh -c qemu:///system domstate windows")[1].strip() != "shut off":
        if time.monotonic() - began > 3600:
            stalled = "no shutdown after 3600 s"
            host.execute("virsh -c qemu:///system screenshot windows /var/lib/windows/screen.ppm")
            host.execute("virsh -c qemu:///system destroy windows")
            break
        time.sleep(5)
    seconds = round(time.monotonic() - began)
    host.execute("cp /var/log/libvirt/qemu/windows.log /var/lib/windows/qemu.log")
    host.execute("virsh -c qemu:///system dumpxml windows > /var/lib/windows/domain.xml")
    for name in ("serial.log", "screen.ppm", "qemu.log", "domain.xml"):
        if host.execute(f"test -e /var/lib/windows/{name}")[0] == 0:
            host.copy_from_machine(f"/var/lib/windows/{name}", "")
    serial = os.path.join(out, "serial.log")
    text = open(serial, errors="replace").read() if os.path.exists(serial) else ""
    run = os.path.join(out, "run.json")
    with open(run, "w") as f:
        json.dump({"mode": "installed", "seconds": seconds, "firmware_boots": text.count("BdsDxe: starting"), "stalled": stalled, "qemu_exit": 0}, f)
    verdict = subprocess.run([sys.executable, "-I", "${harness.judge}", "${harness.patchedPlan}", run, serial, out], check=False)
    if verdict.returncode != 0:
        raise Exception("the Windows guest started by libvirt on the patched host kernel failed the checks above")
  '';
}
