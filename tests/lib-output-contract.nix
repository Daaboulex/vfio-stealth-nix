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
    product = "Test Board";
    biosVendor = "American Megatrends Inc.";
    biosVersion = "2401";
    biosDate = "03/15/2025";
    biosRelease = "2.4";
    serial = "TST-123456";
    baseBoardVersion = "Rev 1.02";
    baseBoardSerial = "BB-789012";
    baseBoardAsset = "BB-Asset";
    baseBoardLocation = "Slot 0";
    systemVersion = "Test System Version";
    systemSku = "Test SKU";
    systemFamily = "Test Family";
    chassisVersion = "Test Chassis Version";
    chassisSerial = "Test Chassis Serial";
    chassisAsset = "Test Chassis Asset";
    chassisSku = "Test Chassis SKU";
    ports = [
      {
        internalReference = "TEST_HDR";
        internalConnectorType = 255;
        externalReference = null;
        externalConnectorType = 0;
        portType = 255;
      }
      {
        internalReference = null;
        internalConnectorType = 0;
        externalReference = "Test USB, rear";
        externalConnectorType = 18;
        portType = 16;
      }
    ];
    systemSlots = [
      {
        designation = "TESTSLOT_1";
        type = 195;
        dataBusWidth = 13;
        currentUsage = 3;
        length = 4;
        id = 7;
        characteristics1 = 4;
        characteristics2 = 9;
      }
    ];
    memory = {
      manufacturer = "Example Memory Inc.";
      partNumber = "EX-DDR5-32G";
      speed = 5600;
    };
    oemStrings = [
      "Default string"
      "Default string"
      "EXAMPLE"
      "Default string"
    ];
    onboardDevices = [
      {
        designation = "Example LAN";
        kind = "ethernet";
        instance = 0;
      }
      {
        designation = "ASMedia ASM1074";
        kind = "sata";
        instance = 1;
      }
    ];
  };

  testCpuIdentity = {
    modelId = "AMD Ryzen 7 7700X 8-Core Processor";
    manufacturer = "Advanced Micro Devices, Inc.";
    maxSpeed = 5700;
    currentSpeed = 5700;
    socket = "TESTSOCK";
    family = 300;
    voltageDecivolts = 12;
    externalClock = 133;
    upgrade = 88;
    characteristics = 236;
  };

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
    cpuPm = true;
    stripVirtio = true;
    hypervVendorId = "AuthAMDRyzen";
    hypervMode = "enlightened";
    kvmPvEnforceCpuid = false;
    pciMmio64Mb = 65536;
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

  hidden = stealthLib.mkStealthFeatures {
    smbios = testSmbios;
    acpiTables = acpi-ssdt-stealth;
    smbiosTables = smbios-stealth-tables;
    hypervMode = "hidden";
  };

  default = stealthLib.mkStealthFeatures {
    smbios = testSmbios;
    acpiTables = acpi-ssdt-stealth;
    smbiosTables = smbios-stealth-tables;
  };

  intel = stealthLib.mkStealthFeatures {
    smbios = testSmbios;
    acpiTables = acpi-ssdt-stealth;
    smbiosTables = smbios-stealth-tables;
    cpuVendor = "intel";
  };

  noCet = stealthLib.mkStealthFeatures {
    smbios = testSmbios;
    acpiTables = acpi-ssdt-stealth;
    smbiosTables = smbios-stealth-tables;
    cpuVendor = "intel";
    cet = false;
  };

  supported = stealthLib.mkStealthFeatures {
    smbios = testSmbios;
    acpiTables = acpi-ssdt-stealth;
    smbiosTables = smbios-stealth-tables;
    hypervMode = "enlightened";
    hypervFeatures = {
      vapic = true;
      vpindex = true;
      synic = true;
    };
    kernelCapabilities = cap.fromConfigText ''
      CONFIG_KVM_HYPERV=y
      CONFIG_KVM_AMD=y
    '';
  };

  unsupported = stealthLib.mkStealthFeatures {
    smbios = testSmbios;
    acpiTables = acpi-ssdt-stealth;
    smbiosTables = smbios-stealth-tables;
    hypervMode = "enlightened";
    hypervFeatures = {
      vapic = true;
      vpindex = true;
      synic = true;
      vendor_id = true;
      relaxed = true;
    };
    kernelCapabilities = cap.fromConfigText ''
      CONFIG_KVM_AMD=y
    '';
  };

  enlightenedArgs = enlightened.qemuArgs testCpuIdentity;
  hiddenArgs = hidden.qemuArgs testCpuIdentity;

  argsJson = builtins.toJSON enlightenedArgs;
  hiddenArgsJson = builtins.toJSON hiddenArgs;
  featuresJson = builtins.toJSON enlightened.features;
  hiddenFeaturesJson = builtins.toJSON hidden.features;
  supportedFeaturesJson = builtins.toJSON supported.features;
  unsupportedFeaturesJson = builtins.toJSON unsupported.features;
  defaultFeaturesJson = builtins.toJSON default.features;
  defaultArgsJson = builtins.toJSON (default.qemuArgs testCpuIdentity);
  clockJson = builtins.toJSON enlightened.clock;
  hiddenClockJson = builtins.toJSON hidden.clock;
  sysinfoJson = builtins.toJSON enlightened.sysinfo;
  hiddenCpuFeaturesJson = builtins.toJSON hidden.cpuFeatures;
  cpuFeaturesJson = builtins.toJSON enlightened.cpuFeatures;
  intelCpuFeaturesJson = builtins.toJSON intel.cpuFeatures;
  noCetCpuFeaturesJson = builtins.toJSON noCet.cpuFeatures;
  devicesJson = builtins.toJSON enlightened.devicesToRemove;
  unsupportedWarningsJson = builtins.toJSON unsupported.warnings;

  perVmCpuIdentity = {
    modelId = "AMD Ryzen 7 7700X 8-Core Processor";
    maxSpeed = 5700;
    currentSpeed = 5700;
  };

  hostWideCpuIdentity = {
    manufacturer = null;
    modelId = null;
    maxSpeed = null;
    currentSpeed = null;
  };

  mergedCpuIdentity = hostWideCpuIdentity // lib.filterAttrs (_: v: v != null) perVmCpuIdentity;

  cpuIdentityShapesAgreeJson = builtins.toJSON (
    enlightened.qemuArgs perVmCpuIdentity == enlightened.qemuArgs mergedCpuIdentity
  );

  cpuIdentityInheritedManufacturerJson = builtins.toJSON (
    enlightened.qemuArgs (mergedCpuIdentity // { manufacturer = "Intel Corporation"; })
  );

  vendorDefaultArgsJson = builtins.toJSON (default.qemuArgs null);
  intelDefaultArgsJson = builtins.toJSON (intel.qemuArgs null);

  guards = [
    {
      name = "cpuidentity-null-and-absent-agree";
      json = cpuIdentityShapesAgreeJson;
      filter = ".";
    }
    {
      name = "cpuidentity-null-manufacturer-falls-back-to-amd";
      json = builtins.toJSON (enlightened.qemuArgs mergedCpuIdentity);
      filter = ''[. | join(" ")] | .[0] | contains("manufacturer=Advanced Micro Devices,, Inc.")'';
    }
    {
      name = "cpuidentity-set-manufacturer-wins";
      json = cpuIdentityInheritedManufacturerJson;
      filter = ''[. | join(" ")] | .[0] | contains("manufacturer=Intel Corporation")'';
    }
    {
      name = "smbios-type3-chassis";
      json = argsJson;
      filter = ''[. | join(" ")] | .[0] | contains("type=3,manufacturer=Test Manufacturer Inc.,version=Test Chassis Version,serial=Test Chassis Serial,asset=Test Chassis Asset,sku=Test Chassis SKU")'';
    }
    {
      name = "smbios-type1-system";
      json = argsJson;
      filter = ''[. | join(" ")] | .[0] | contains("version=Test System Version,serial=TST-123456,sku=Test SKU,family=Test Family")'';
    }
    {
      name = "smbios-type4-processor";
      json = argsJson;
      filter = ''map(select(startswith("type=4,"))) == ["type=4,characteristics=236,current-speed=5700,external-clock=133,l1-cache-handle=1792,l2-cache-handle=1793,l3-cache-handle=1794,manufacturer=Advanced Micro Devices,, Inc.,max-speed=5700,processor-family=300,sock_pfx=TESTSOCK,upgrade=88,version=AMD Ryzen 7 7700X 8-Core Processor,voltage=140"]'';
    }
    {
      name = "smbios-type4-without-model-takes-amd-defaults";
      json = vendorDefaultArgsJson;
      filter = ''map(select(startswith("type=4,"))) == ["type=4,characteristics=252,external-clock=100,l1-cache-handle=1792,l2-cache-handle=1793,l3-cache-handle=1794,manufacturer=Advanced Micro Devices,, Inc.,processor-family=107,sock_pfx=AM5,upgrade=73,voltage=141"]'';
    }
    {
      name = "smbios-type4-without-model-takes-intel-defaults";
      json = intelDefaultArgsJson;
      filter = ''map(select(startswith("type=4,"))) == ["type=4,characteristics=252,external-clock=100,l1-cache-handle=1792,l2-cache-handle=1793,l3-cache-handle=1794,manufacturer=Intel(R) Corporation,processor-family=198,sock_pfx=LGA1700,upgrade=64,voltage=142"]'';
    }
    {
      name = "no-model-id-without-model";
      json = vendorDefaultArgsJson;
      filter = ''[. | join(" ")] | .[0] | contains("model-id") | not'';
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
      filter = ''map(select(startswith("type=8,"))) == ["type=8,connector_type=0,internal_connector_type=255,internal_reference=TEST_HDR,port_type=255", "type=8,connector_type=18,external_reference=Test USB,, rear,internal_connector_type=0,port_type=16"]'';
    }
    {
      name = "smbios-type9-slot";
      json = argsJson;
      filter = ''map(select(startswith("type=9,"))) == ["type=9,current_usage=3,slot_characteristics1=4,slot_characteristics2=9,slot_data_bus_width=13,slot_designation=TESTSLOT_1,slot_id=7,slot_length=4,slot_type=195"]'';
    }
    {
      name = "smbios-type11-oem";
      json = argsJson;
      filter = ''[. | join(" ")] | .[0] | contains("type=11,value=Default string")'';
    }
    {
      name = "smbios-type17-module";
      json = argsJson;
      filter = ''[. | join(" ")] | .[0] | contains("type=17,speed=5600,")'';
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
      filter = ''[. | join(" ")] | .[0] | contains("type=41,designation=Example LAN")'';
    }

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

    {
      name = "cpu-pm-on";
      json = argsJson;
      filter = ''[. | join(" ")] | .[0] | contains("cpu-pm=on")'';
    }
    {
      name = "cpu-pm-off-by-default";
      json = defaultArgsJson;
      filter = ''[. | join(" ")] | .[0] | contains("cpu-pm") | not'';
    }
    {
      name = "aperfmperf-needs-cpu-pm";
      json = defaultArgsJson;
      filter = ''[. | join(" ")] | .[0] | contains("aperfmperf") | not'';
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
      filter = ''[. | join(" ")] | .[0] | contains("x86_64-cpu.model-id=AMD Ryzen 7 7700X")'';
    }
    {
      name = "board-identity-args";
      json = argsJson;
      filter = ''[. | join(" ")] | .[0] | contains("type=1,manufacturer=") and contains("type=2,manufacturer=") and contains("type=0,vendor=")'';
    }
    {
      name = "no-cpu-override";
      json = argsJson;
      filter = ''map(select(. == "-cpu")) | length == 0'';
    }
    {
      name = "amd-topoext";
      json = cpuFeaturesJson;
      filter = ''[.[] | select(.name == "topoext" and .policy == "require")] | length == 1'';
    }
    {
      name = "amd-no-intel-speculation-bits";
      json = cpuFeaturesJson;
      filter = ''[.[] | select(.policy == "disable" and (.name == "spec-ctrl" or .name == "stibp" or .name == "flush-l1d" or .name == "ssbd"))] | length == 4'';
    }
    {
      name = "intel-keeps-speculation-bits";
      json = intelCpuFeaturesJson;
      filter = ''[.[] | select(.name == "spec-ctrl" or .name == "stibp" or .name == "flush-l1d" or .name == "ssbd")] | length == 0'';
    }
    {
      name = "intel-no-topoext";
      json = intelCpuFeaturesJson;
      filter = ''[.[] | select(.name == "topoext")] | length == 0'';
    }
    {
      name = "cet-shown";
      json = cpuFeaturesJson;
      filter = ''[.[] | select(.name == "cet-ibt" or .name == "cet-ss")] | length == 0'';
    }
    {
      name = "cet-hidden";
      json = noCetCpuFeaturesJson;
      filter = ''[.[] | select(.policy == "disable" and (.name == "cet-ibt" or .name == "cet-ss"))] | length == 2'';
    }
    {
      name = "invtsc";
      json = cpuFeaturesJson;
      filter = ''[.[] | select(.name == "invtsc")] | length == 1'';
    }
    {
      name = "cpu-pv-enforce-off";
      json = argsJson;
      filter = ''[. | join(" ")] | .[0] | contains("kvm-pv-enforce-cpuid") | not'';
    }
    {
      name = "cpu-aperfmperf";
      json = argsJson;
      filter = ''[. | join(" ")] | .[0] | contains("x86_64-cpu.aperfmperf=on")'';
    }

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
      name = "no-kvm-hints";
      json = featuresJson;
      filter = ''.kvm | has("hint-dedicated") or has("poll-control") | not'';
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
      name = "hidden-no-cpu-override";
      json = hiddenArgsJson;
      filter = ''map(select(. == "-cpu")) | length == 0'';
    }
    {
      name = "hidden-hypervclock-off";
      json = hiddenClockJson;
      filter = ''[.timer[] | select(.name == "hypervclock")] | .[0].present == false'';
    }

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

    {
      name = "kernel-supported-features-pass-through";
      json = supportedFeaturesJson;
      filter = ".hyperv.vpindex.state == true and .hyperv.synic.state == true";
    }
    {
      name = "kernel-unsupported-features-dropped";
      json = unsupportedFeaturesJson;
      filter = "(.hyperv.vpindex.state == null or .hyperv.vpindex.state == false) and (.hyperv.synic.state == null or .hyperv.synic.state == false)";
    }
    {
      name = "kvm-gated-features-dropped-no-kvm-hyperv";
      json = unsupportedFeaturesJson;
      filter = "(.hyperv.vapic.state == null or .hyperv.vapic.state == false) and (.hyperv.vpindex.state == null or .hyperv.vpindex.state == false) and (.hyperv.synic.state == null or .hyperv.synic.state == false)";
    }
    {
      name = "truly-universal-features-survive-no-kvm-hyperv";
      json = unsupportedFeaturesJson;
      filter = ".hyperv.vendor_id.state == true and .hyperv.relaxed.state == true";
    }
    {
      name = "warning-emitted-on-drop";
      json = unsupportedWarningsJson;
      filter = ''any(. | contains("hypervFeatures.vpindex"))'';
    }
    {
      name = "back-compat-null-kernel-caps-passes-through";
      json = featuresJson;
      filter = ".hyperv.vpindex.state == true";
    }
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
      echo "    filter: "${lib.escapeShellArg g.filter}
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
