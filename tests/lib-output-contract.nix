{
  lib,
  runCommand,
  jq,
  acpi-ssdt-stealth,
  smbios-stealth-tables,
}:

let
  stealthLib = import ../lib.nix { inherit lib; };
  cap = import ../lib/kernel-capabilities.nix { inherit lib; };

  testSmbios = {
    manufacturer = "Test Manufacturer Inc.";
    product = "Test Board X870E";
    biosVendor = "American Megatrends Inc.";
    biosVersion = "2401";
    biosDate = "03/15/2025";
    biosRelease = "2.4";
    serial = "TST-123456";
    baseBoardVersion = "Rev 1.02";
    baseBoardSerial = "BB-789012";
    baseBoardAsset = "BB-Asset";
    baseBoardLocation = "Slot 0";
    socketPrefix = "AM5";
    memory = {
      manufacturer = "Corsair";
      partNumber = "CMK32GX5M2B5600C36";
      speed = 5600;
      count = 2;
    };
    oemStrings = [
      "Default string"
      "Default string"
      "CROSSHAIR"
      "Default string"
    ];
    onboardDevices = [
      {
        designation = "Realtek RTL8125BG";
        kind = "ethernet";
        instance = 0;
      }
      {
        designation = "ASMedia ASM1074";
        kind = "sata";
        instance = 1;
      }
    ];
    cache = {
      l1 = 512;
      l2 = 8192;
      l3 = 65536;
    };
  };

  testCpuIdentity = {
    modelId = "AMD Ryzen 9 9950X3D 16-Core Processor";
    manufacturer = "Advanced Micro Devices, Inc.";
    maxSpeed = 5700;
    currentSpeed = 5700;
  };

  # Test enlightened mode with all features on and kernelCapabilities = null
  # (back-compat path: lib assumes all features are supported).
  enlightened = stealthLib.mkStealthFeatures {
    smbios = testSmbios;
    acpiTables = acpi-ssdt-stealth;
    smbiosTables = smbios-stealth-tables;
    acpiSsdt = {
      spoofedDevices = true;
      fakeBattery = true;
      sensorProbes = true;
    };
    aperfMperf = true;
    stripVirtio = true;
    hypervVendorId = "AuthAMDRyzen";
    hypervMode = "enlightened";
    kvmPvEnforceCpuid = false;
    pciMmio64Mb = 65536;
    # Explicit all-on to match the pre-per-feature-opt-in behavior.
    hypervFeatures = {
      vapic = true;
      relaxed = true;
      spinlocks = true;
      frequencies = true;
      vendor_id = true;
      vpindex = true;
      synic = true;
      stimer = true;
      reset = true;
      ipi = true;
      tlbflush = true;
      reenlightenment = true;
      runtime = true;
    };
    kernelCapabilities = null;
  };

  # Test hidden mode (no Hyper-V, hypervisor=off)
  hidden = stealthLib.mkStealthFeatures {
    smbios = testSmbios;
    acpiTables = acpi-ssdt-stealth;
    smbiosTables = smbios-stealth-tables;
    hypervMode = "hidden";
  };

  # Test defaults: no hypervFeatures override, no kernelCapabilities.
  # The new defaults emit only vendor_id and relaxed; all 11 KVM-gated
  # features (including vapic, spinlocks, frequencies) are off.
  default = stealthLib.mkStealthFeatures {
    smbios = testSmbios;
    acpiTables = acpi-ssdt-stealth;
    smbiosTables = smbios-stealth-tables;
  };

  # Test new defaults (kernel-dep features off) with a kernel that advertises
  # CONFIG_KVM_HYPERV. Only universal features should be enabled; hypervclock
  # should be absent.
  supported = stealthLib.mkStealthFeatures {
    smbios = testSmbios;
    acpiTables = acpi-ssdt-stealth;
    smbiosTables = smbios-stealth-tables;
    hypervMode = "enlightened";
    # User explicitly opts in to the kernel-dep features they want.
    hypervFeatures = {
      vapic = true;
      vpindex = true;
      synic = true;
    };
    # Kernel advertises CONFIG_KVM_HYPERV=y.
    kernelCapabilities = cap.fromConfigText ''
      CONFIG_KVM_HYPERV=y
      CONFIG_KVM_AMD=y
    '';
  };

  # Test kernel that does NOT advertise CONFIG_KVM_HYPERV. Requested
  # kernel-dep features must be dropped; warnings emitted.
  unsupported = stealthLib.mkStealthFeatures {
    smbios = testSmbios;
    acpiTables = acpi-ssdt-stealth;
    smbiosTables = smbios-stealth-tables;
    hypervMode = "enlightened";
    hypervFeatures = {
      vapic = true;
      vpindex = true;
      synic = true;
      # Request the truly-universal features to verify they survive.
      vendor_id = true;
      relaxed = true;
    };
    # Kernel without KVM_HYPERV.
    kernelCapabilities = cap.fromConfigText ''
      CONFIG_KVM_AMD=y
    '';
  };

  enlightenedArgs = enlightened.qemuArgs testCpuIdentity;
  hiddenArgs = hidden.qemuArgs testCpuIdentity;
  supportedArgs = supported.qemuArgs testCpuIdentity;
  unsupportedArgs = unsupported.qemuArgs testCpuIdentity;

  argsJson = builtins.toJSON enlightenedArgs;
  hiddenArgsJson = builtins.toJSON hiddenArgs;
  supportedArgsJson = builtins.toJSON supportedArgs;
  unsupportedArgsJson = builtins.toJSON unsupportedArgs;
  featuresJson = builtins.toJSON enlightened.features;
  hiddenFeaturesJson = builtins.toJSON hidden.features;
  supportedFeaturesJson = builtins.toJSON supported.features;
  unsupportedFeaturesJson = builtins.toJSON unsupported.features;
  defaultFeaturesJson = builtins.toJSON default.features;
  clockJson = builtins.toJSON enlightened.clock;
  hiddenClockJson = builtins.toJSON hidden.clock;
  supportedClockJson = builtins.toJSON supported.clock;
  unsupportedClockJson = builtins.toJSON unsupported.clock;
  sysinfoJson = builtins.toJSON enlightened.sysinfo;
  cpuFeaturesJson = builtins.toJSON enlightened.cpuFeatures;
  hiddenCpuFeaturesJson = builtins.toJSON hidden.cpuFeatures;
  devicesJson = builtins.toJSON enlightened.devicesToRemove;
  supportedWarningsJson = builtins.toJSON supported.warnings;
  unsupportedWarningsJson = builtins.toJSON unsupported.warnings;

  # Each guard: (name, json-source, jq-filter that must return true)
  guards = [
    # --- qemuArgs: SMBIOS types ---
    {
      name = "smbios-type3-chassis";
      json = argsJson;
      filter = ''[. | join(" ")] | .[0] | contains("type=3,manufacturer=Test Manufacturer Inc.")'';
    }
    {
      name = "smbios-type4-processor";
      json = argsJson;
      filter = ''[. | join(" ")] | .[0] | contains("type=4,sock_pfx=AM5")'';
    }
    {
      name = "smbios-type7-l1";
      json = argsJson;
      filter = ''[. | join(" ")] | .[0] | contains("type7-l1.bin")'';
    }
    {
      name = "smbios-type7-l2";
      json = argsJson;
      filter = ''[. | join(" ")] | .[0] | contains("type7-l2.bin")'';
    }
    {
      name = "smbios-type7-l3";
      json = argsJson;
      filter = ''[. | join(" ")] | .[0] | contains("type7-l3.bin")'';
    }
    {
      name = "smbios-type8-port";
      json = argsJson;
      filter = ''[. | join(" ")] | .[0] | contains("type=8,internal_reference=USB 3.2 Gen 2")'';
    }
    {
      name = "smbios-type9-slot";
      json = argsJson;
      filter = ''[. | join(" ")] | .[0] | contains("type=9,slot_designation=PCIEX16_1")'';
    }
    {
      name = "smbios-type11-oem";
      json = argsJson;
      filter = ''[. | join(" ")] | .[0] | contains("type=11,value=Default string")'';
    }
    {
      name = "smbios-type17-dimm0";
      json = argsJson;
      filter = ''[. | join(" ")] | .[0] | contains("type=17,loc_pfx=DIMM_,bank=BANK 0,speed=5600")'';
    }
    {
      name = "smbios-type17-dimm1";
      json = argsJson;
      filter = ''[. | join(" ")] | .[0] | contains("bank=BANK 1")'';
    }
    {
      name = "smbios-type26-voltage";
      json = argsJson;
      filter = ''[. | join(" ")] | .[0] | contains("type26.bin")'';
    }
    {
      name = "smbios-type27-cooling";
      json = argsJson;
      filter = ''[. | join(" ")] | .[0] | contains("type27.bin")'';
    }
    {
      name = "smbios-type28-temp";
      json = argsJson;
      filter = ''[. | join(" ")] | .[0] | contains("type28.bin")'';
    }
    {
      name = "smbios-type29-current";
      json = argsJson;
      filter = ''[. | join(" ")] | .[0] | contains("type29.bin")'';
    }
    {
      name = "smbios-type41-onboard";
      json = argsJson;
      filter = ''[. | join(" ")] | .[0] | contains("type=41,designation=Realtek RTL8125BG")'';
    }

    # --- qemuArgs: ACPI tables ---
    {
      name = "acpi-spoofed-devices";
      json = argsJson;
      filter = ''[. | join(" ")] | .[0] | contains("spoofed-devices.aml")'';
    }
    {
      name = "acpi-fake-battery";
      json = argsJson;
      filter = ''[. | join(" ")] | .[0] | contains("fake-battery.aml")'';
    }
    {
      name = "acpi-sensor-probes";
      json = argsJson;
      filter = ''[. | join(" ")] | .[0] | contains("sensor-probes.aml")'';
    }

    # --- qemuArgs: hardware config ---
    {
      name = "cpu-pm-on";
      json = argsJson;
      filter = ''[. | join(" ")] | .[0] | contains("cpu-pm=on")'';
    }
    {
      name = "mmio64-window";
      json = argsJson;
      filter = ''[. | join(" ")] | .[0] | contains("X-PciMmio64Mb,string=65536")'';
    }
    {
      name = "s3-sleep";
      json = argsJson;
      filter = ''[. | join(" ")] | .[0] | contains("ICH9-LPC.disable_s3=0")'';
    }
    {
      name = "s4-sleep";
      json = argsJson;
      filter = ''[. | join(" ")] | .[0] | contains("ICH9-LPC.disable_s4=0")'';
    }
    {
      name = "cpu-model-id";
      json = argsJson;
      filter = ''[. | join(" ")] | .[0] | contains("cpu.model-id=AMD Ryzen 9 9950X3D")'';
    }
    {
      name = "cpu-flags-topoext";
      json = argsJson;
      filter = ''[. | join(" ")] | .[0] | contains("host,topoext=on,invtsc=on")'';
    }
    {
      name = "cpu-pv-enforce-off";
      json = argsJson;
      filter = ''[. | join(" ")] | .[0] | contains("kvm-pv-enforce-cpuid=off")'';
    }
    {
      name = "cpu-aperfmperf";
      json = argsJson;
      filter = ''[. | join(" ")] | .[0] | contains("aperfmperf=on")'';
    }

    # --- features ---
    {
      name = "kvm-hidden";
      json = featuresJson;
      filter = ".kvm.hidden.state == true";
    }
    {
      name = "vmport-off";
      json = featuresJson;
      filter = ".vmport.state == false";
    }
    {
      name = "hint-dedicated";
      json = featuresJson;
      filter = ''."kvm"."hint-dedicated".state == true'';
    }
    {
      name = "poll-control";
      json = featuresJson;
      filter = ''."kvm"."poll-control".state == true'';
    }
    {
      name = "hyperv-relaxed";
      json = featuresJson;
      filter = ".hyperv.relaxed.state == true";
    }
    {
      name = "hyperv-vapic";
      json = featuresJson;
      filter = ".hyperv.vapic.state == true";
    }
    {
      name = "hyperv-vendor-id";
      json = featuresJson;
      filter = ''.hyperv.vendor_id.value == "AuthAMDRyzen"'';
    }
    {
      name = "hyperv-stimer-direct";
      json = featuresJson;
      filter = ".hyperv.stimer.direct.state == true";
    }
    {
      name = "hyperv-frequencies";
      json = featuresJson;
      filter = ".hyperv.frequencies.state == true";
    }

    # --- hidden mode: no hyperv block ---
    {
      name = "hidden-no-hyperv";
      json = hiddenFeaturesJson;
      filter = ''has("hyperv") | not'';
    }
    {
      name = "hidden-hypervisor-off";
      json = hiddenCpuFeaturesJson;
      filter = ''[.[] | select(.name == "hypervisor")] | length == 1'';
    }
    {
      name = "hidden-hypervisor-disable";
      json = hiddenCpuFeaturesJson;
      filter = ''[.[] | select(.name == "hypervisor" and .policy == "disable")] | length == 1'';
    }
    {
      name = "hidden-cpu-no-hypervisor";
      json = hiddenArgsJson;
      filter = ''[. | join(" ")] | .[0] | contains("hypervisor=off")'';
    }
    {
      name = "hidden-hypervclock-off";
      json = hiddenClockJson;
      filter = ''[.timer[] | select(.name == "hypervclock")] | .[0].present == false'';
    }

    # --- clock ---
    {
      name = "kvmclock-disabled";
      json = clockJson;
      filter = ''[.timer[] | select(.name == "kvmclock")] | .[0].present == false'';
    }
    {
      name = "tsc-native";
      json = clockJson;
      filter = ''[.timer[] | select(.name == "tsc")] | .[0].mode == "native"'';
    }
    {
      name = "hpet-present";
      json = clockJson;
      filter = ''[.timer[] | select(.name == "hpet")] | .[0].present == true'';
    }
    {
      name = "hypervclock-enlightened";
      json = clockJson;
      filter = ''[.timer[] | select(.name == "hypervclock")] | .[0].present == true'';
    }
    {
      name = "clock-localtime";
      json = clockJson;
      filter = ''.offset == "localtime"'';
    }

    # --- sysinfo ---
    {
      name = "sysinfo-bios-vendor";
      json = sysinfoJson;
      filter = ''[.bios.entry[] | select(.name == "vendor")] | .[0].value == "American Megatrends Inc."'';
    }
    {
      name = "sysinfo-bios-date";
      json = sysinfoJson;
      filter = ''[.bios.entry[] | select(.name == "date")] | .[0].value == "03/15/2025"'';
    }
    {
      name = "sysinfo-system-manufacturer";
      json = sysinfoJson;
      filter = ''[.system.entry[] | select(.name == "manufacturer")] | .[0].value == "Test Manufacturer Inc."'';
    }
    {
      name = "sysinfo-system-serial";
      json = sysinfoJson;
      filter = ''[.system.entry[] | select(.name == "serial")] | .[0].value == "TST-123456"'';
    }
    {
      name = "sysinfo-baseboard-serial";
      json = sysinfoJson;
      filter = ''[.baseBoard.entry[] | select(.name == "serial")] | .[0].value == "BB-789012"'';
    }
    {
      name = "sysinfo-baseboard-location";
      json = sysinfoJson;
      filter = ''[.baseBoard.entry[] | select(.name == "location")] | .[0].value == "Slot 0"'';
    }

    # --- devicesToRemove ---
    {
      name = "strip-balloon";
      json = devicesJson;
      filter = ''any(. == "virtio-balloon")'';
    }
    {
      name = "strip-rng";
      json = devicesJson;
      filter = ''any(. == "virtio-rng")'';
    }
    {
      name = "strip-tablet";
      json = devicesJson;
      filter = ''any(. == "virtio-tablet")'';
    }

    # --- kernelCapabilities: intersection logic ---
    # Request vpindex + synic on a kernel that advertises KVM_HYPERV: both
    # must appear in the hyperv block.
    {
      name = "kernel-supported-features-pass-through";
      json = supportedFeaturesJson;
      filter = ".hyperv.vpindex.state == true and .hyperv.synic.state == true";
    }
    # Same request on a kernel without KVM_HYPERV: both must be dropped.
    {
      name = "kernel-unsupported-features-dropped";
      json = unsupportedFeaturesJson;
      filter = "(.hyperv.vpindex.state == null or .hyperv.vpindex.state == false) and (.hyperv.synic.state == null or .hyperv.synic.state == false)";
    }
    # KVM-gated features (vapic, vpindex, synic) must all be dropped when
    # the kernel does not advertise KVM_HYPERV.
    {
      name = "kvm-gated-features-dropped-no-kvm-hyperv";
      json = unsupportedFeaturesJson;
      filter = "(.hyperv.vapic.state == null or .hyperv.vapic.state == false) and (.hyperv.vpindex.state == null or .hyperv.vpindex.state == false) and (.hyperv.synic.state == null or .hyperv.synic.state == false)";
    }
    # Truly universal features (vendor_id, relaxed) have no KVM cap and must
    # survive on any host, even one without KVM_HYPERV.
    {
      name = "truly-universal-features-survive-no-kvm-hyperv";
      json = unsupportedFeaturesJson;
      filter = ".hyperv.vendor_id.state == true and .hyperv.relaxed.state == true";
    }
    # Warnings: the unsupported case must emit a warning naming vpindex.
    {
      name = "warning-emitted-on-drop";
      json = unsupportedWarningsJson;
      filter = ''any(. | contains("hypervFeatures.vpindex"))'';
    }
    # Back-compat: kernelCapabilities = null + requested feature must pass
    # through (assumes supported).
    {
      name = "back-compat-null-kernel-caps-passes-through";
      json = featuresJson;
      filter = ".hyperv.vpindex.state == true";
    }
    # New defaults: with no hypervFeatures override and no kernelCapabilities,
    # only the 2 truly-universal features (vendor_id, relaxed) are emitted.
    # The 11 KVM-gated features (including vapic, spinlocks, frequencies)
    # are off by default to avoid libvirt "host doesn't support hyperv X"
    # errors on hosts without CONFIG_KVM_HYPERV.
    {
      name = "defaults-only-truly-universal";
      json = defaultFeaturesJson;
      filter = ".hyperv.vendor_id.state == true and .hyperv.relaxed.state == true and (.hyperv.vapic.state == null or .hyperv.vapic.state == false) and (.hyperv.spinlocks.state == null or .hyperv.spinlocks.state == false) and (.hyperv.frequencies.state == null or .hyperv.frequencies.state == false) and (.hyperv.vpindex.state == null or .hyperv.vpindex.state == false)";
    }
  ];

  guardCheck = g: ''
    echo -n "  ${g.name}: "
    if echo '${
      builtins.replaceStrings [ "'" ] [ "'\"'\"'" ] g.json
    }' | ${jq}/bin/jq -e '${g.filter}' > /dev/null 2>&1; then
      echo "PASS"
    else
      echo "FAIL"
      echo "    filter: ${g.filter}"
      echo "    json (first 300 chars):"
      echo '${builtins.replaceStrings [ "'" ] [ "'\"'\"'" ] g.json}' | head -c 300
      echo ""
      FAILURES=$((FAILURES + 1))
    fi
  '';
in
runCommand "lib-output-contract" { } ''
    FAILURES=0
    echo "=== lib-output-contract: ${toString (lib.length guards)} guards ==="

  ${lib.concatMapStringsSep "\n" guardCheck guards}

    echo ""
    if [ "$FAILURES" -gt 0 ]; then
      echo "FAILED: $FAILURES/${toString (lib.length guards)} guards failed"
      exit 1
    fi
    echo "lib-output-contract: all ${toString (lib.length guards)} guards passed"
    touch $out
''
