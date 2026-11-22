{
  lib,
  stdenv,
  testers,
  writeScript,
  writeText,
  makeInitrd,
  busybox,
  qemu_kvm,
  module,
  variants,
}:

cpuVendor: settings:

let
  helper = stdenv.mkDerivation {
    name = "probe-helper";
    src = ../verify/probe-helper.c;
    dontUnpack = true;
    buildPhase = "$CC -O2 -Wall -Werror -o probe-helper $src";
    installPhase = "install -Dm755 probe-helper $out/bin/probe-helper";
  };

  init = writeScript "kernel-runtime-init" ''
    #!${busybox}/bin/sh
    export PATH=${
      lib.makeBinPath [
        helper
        busybox
      ]
    }
    mount -t proc proc /proc
    mount -t sysfs sysfs /sys
    echo VFIO-PROBE-BEGIN cpuid-latency
    probe-helper cpuid-latency
    echo VFIO-PROBE-END cpuid-latency $?
    echo VFIO-PROBE-BEGIN instructions
    probe-helper instructions
    echo VFIO-PROBE-END instructions $?
    echo VFIO-PROBE-BEGIN tsc-hidden
    probe-helper tsc-hidden
    echo VFIO-PROBE-END tsc-hidden $?
    echo VFIO-PROBE-DONE
    poweroff -f
  '';

  initrd = makeInitrd {
    name = "kernel-runtime-initrd";
    contents = [
      {
        object = init;
        symlink = "/init";
      }
    ];
  };

  guest =
    { pkgs, ... }:
    {
      virtualisation.memorySize = 2048;
      virtualisation.cores = 2;
      environment.systemPackages = [
        qemu_kvm
        helper
      ];
      environment.etc."kernel-runtime/initrd".source = "${initrd}/initrd";
      environment.etc."kernel-runtime/kernel".source = "${pkgs.linuxPackages.kernel}/bzImage";
    };

  everySwitchOff = {
    timing.enable = false;
    cpuidSpoof.enable = false;
    instructionFixes.enable = false;
    cpuidPassthrough = {
      enable = false;
      pinned = false;
    };
  };
in
testers.runNixOSTest (
  { config, ... }:
  let
    stealth = config.nodes.patched.virtualisation.vfio-stealth;
    variant =
      lib.findFirst (variant: variant.body == stealth.kernelPostPatch)
        (throw "kernel-runtime: no combination the module accepts patches the kernel as ${builtins.toJSON settings} does; the module refuses it, or it turns no kernel switch on")
        variants;
    switches = writeText "kernel-runtime-switches.json" (
      builtins.toJSON {
        inherit cpuVendor;
        timing = stealth.timing.enable;
        cpuidSpoof = stealth.cpuidSpoof.enable;
        instructionFixes = stealth.instructionFixes.enable;
        cpuidPassthrough = stealth.cpuidPassthrough.enable;
        pinned = stealth.cpuidPassthrough.pinned;
      }
    );
  in
  {
    name = "kernel-runtime-${variant.name}";
    passthru.variant = variant.name;
    globalTimeout = 1800;
    nodes.stock =
      { pkgs, ... }:
      {
        imports = [ guest ];
        boot.kernelPackages = pkgs.linuxPackages_latest;
      };
    nodes.patched =
      { config, pkgs, ... }:
      {
        imports = [
          guest
          module
        ];
        virtualisation.vfio-stealth = lib.recursiveUpdate (
          everySwitchOff
          // {
            enable = true;
            inherit cpuVendor;
            hypervMode = "hidden";
          }
        ) settings;
        boot.kernelPackages = pkgs.linuxPackagesFor (
          config.virtualisation.vfio-stealth.packages.kernelFor pkgs.linux_latest
        );
      };
    testScript = ''
      import json
      import os
      import re
      import subprocess
      import sys

      brand_string = "VFIO-STEALTH-BRAND-PROBE"

      def section(serial, name, where):
          found = re.search(rf"VFIO-PROBE-BEGIN {name}\n(.*?)VFIO-PROBE-END {name} (\d+)", serial, re.DOTALL)
          if found is None or found.group(2) != "0":
              raise Exception(f"the guest on {where} did not finish the {name} probe: {serial[-2000:]}")
          return found.group(1)

      def field(text, pattern, where):
          found = re.search(pattern, text, re.MULTILINE)
          if found is None:
              raise Exception(f"{where} reported in an unknown form: {text}")
          return found

      def latency(text, where):
          values = {name: int(field(text, rf"^{name} (\d+)$", where).group(1)) for name in ("median", "leaf1", "min", "pair")}
          leaf0 = field(text, r"^leaf0 (0x[0-9a-f]+) (\S+)$", where)
          return values | {"leaf0_eax": int(leaf0.group(1), 16), "leaf0_vendor": leaf0.group(2), "brand": field(text, r"^brand (.*)$", where).group(1).strip()}

      def measure(machine, passthrough):
          name = machine.name + ("-pinned" if passthrough else "")
          native = latency(machine.succeed("probe-helper cpuid-latency"), f"{machine.name} itself")
          handlers = machine.succeed("awk '$3 == \"handle_rdtsc_interception\" || $3 == \"handle_rdtscp_interception\" { print $3 }' /proc/kallsyms | sort -u | wc -l").strip()
          pin = "taskset -c 1 " if passthrough else ""
          extra = {}
          if passthrough:
              machine.succeed("modprobe msr")
              msr = field(machine.succeed("probe-helper name-msr"), r"^programmable ([01])$", f"{machine.name} itself")
              machine.succeed(f"printf %s {brand_string} > /sys/module/kvm_amd/parameters/brand_string")
              machine.succeed("echo 1 > /sys/module/kvm_amd/parameters/cpuid_passthrough")
              extra = {"name_msr_programmable": msr.group(1) == "1", "brand_string": brand_string}
          machine.succeed(
              f"timeout 300 {pin}qemu-system-x86_64 -accel kvm -cpu host -m 256 -nodefaults -display none "
              "-kernel /etc/kernel-runtime/kernel -initrd /etc/kernel-runtime/initrd "
              f"-append 'console=ttyS0 panic=-1' -serial file:/tmp/{name}.log -no-reboot"
          )
          serial = machine.succeed(f"cat /tmp/{name}.log").replace("\r", "")
          cpuid = latency(section(serial, "cpuid-latency", name), name)
          hidden = field(section(serial, "tsc-hidden", name), r"^hidden (-?\d+)$", name)
          instruction_text = section(serial, "instructions", name)
          outcomes = {k: f"{sig} {where}" for k, sig, where in re.findall(r"^(\w+) (\w+) (\w+)$", instruction_text, re.MULTILINE)}
          if set(outcomes) != {"vmload", "vmcall", "vmmcall", "icebp", "cpuidstep"}:
              raise Exception(f"the guest on {name} reported the instruction probe in an unknown form: {instruction_text}")
          return {
              "name": name,
              "cpuid_cycles": cpuid["median"],
              "cpuid_leaf1_cycles": cpuid["leaf1"],
              "cpuid_leaf1_min": cpuid["min"],
              "rdtsc_pair_cycles": cpuid["pair"],
              "native_cpuid_leaf1_cycles": native["leaf1"],
              "native_rdtsc_pair_cycles": native["pair"],
              "hidden_permille": int(hidden.group(1)),
              "instructions": outcomes,
              "leaf0_eax": cpuid["leaf0_eax"],
              "leaf0_vendor": cpuid["leaf0_vendor"],
              "brand": cpuid["brand"],
              "cpuid_passthrough": passthrough,
              "rdtsc_handlers": int(handlers),
          } | extra

      start_all()
      stock.wait_for_unit("multi-user.target")
      patched.wait_for_unit("multi-user.target")
      stock.succeed("test -c /dev/kvm")
      patched.succeed("test -c /dev/kvm")
      records = [measure(stock, False), measure(patched, False)]
      if json.load(open("${switches}"))["pinned"]:
          records.append(measure(patched, True))
      evidence = os.path.join(os.environ["out"], "evidence.json")
      with open(evidence, "w") as out:
          json.dump(records, out, indent=2)
      verdict = subprocess.run([sys.executable, "-I", "${./kernel-runtime.py}", "--switches", "${switches}", evidence], capture_output=True, text=True)
      print(verdict.stdout + verdict.stderr)
      if verdict.returncode != 0:
          raise Exception("the guests contradict the kernel switches ${variant.name} was built with; the [FAIL] lines above say how")
    '';
  }
)
