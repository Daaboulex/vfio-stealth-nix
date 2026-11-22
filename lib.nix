{ lib }:
let
  cap = import ./lib/kernel-capabilities.nix { inherit lib; };
  processorDefaults = import ./smbios/processor-defaults.nix;
in
{
  mkStealthFeatures =
    {
      smbios,
      acpiTables,
      smbiosTables,
      vmUuid ? null,
      acpiSsdt ? {
        spoofedDevices = true;
        fakeBattery = true;
        sensorProbes = true;
      },
      aperfMperf ? true,
      cet ? true,
      cpuPm ? false,
      cpuVendor ? "amd",
      stripVirtio ? true,
      hypervVendorId ? "AuthAMDRyzen",
      hypervMode ? "enlightened",
      kvmPvEnforceCpuid ? false,
      pciMmio64Mb ? 65536,
      hypervFeatures ? {
        vapic = false;
        relaxed = true;
        spinlocks = false;
        frequencies = false;
        vendor_id = true;
        vpindex = false;
        synic = false;
        stimer = false;
        reset = false;
        ipi = false;
        tlbflush = false;
        reenlightenment = false;
        runtime = false;
      },
      kernelCapabilities ? null,
    }:
    let
      featureSupported = f: if kernelCapabilities == null then true else kernelCapabilities.${f} or false;
      enabledFeatures = builtins.filter (
        f: (hypervFeatures.${f} or false) && featureSupported f
      ) cap.allFeatures;
      droppedFeatures = builtins.filter (
        f: (hypervFeatures.${f} or false) && !(featureSupported f)
      ) cap.allFeatures;
      featureAttrs = {
        vapic = {
          vapic.state = true;
        };
        relaxed = {
          relaxed.state = true;
        };
        spinlocks = {
          spinlocks = {
            state = true;
            retries = 8191;
          };
        };
        frequencies = {
          frequencies.state = true;
        };
        vendor_id = {
          vendor_id = {
            state = true;
            value = hypervVendorId;
          };
        };
        vpindex = {
          vpindex.state = true;
        };
        synic = {
          synic.state = true;
        };
        stimer = {
          stimer = {
            state = true;
            direct.state = true;
          };
        };
        reset = {
          reset.state = true;
        };
        ipi = {
          ipi.state = true;
        };
        tlbflush = {
          tlbflush.state = true;
        };
        reenlightenment = {
          reenlightenment.state = true;
        };
        runtime = {
          runtime.state = true;
        };
      };
      hypervBlock = lib.foldl' (acc: f: acc // featureAttrs.${f}) { mode = "custom"; } enabledFeatures;
      anyKernelDepEnabled = lib.any (f: builtins.elem f enabledFeatures) (
        builtins.attrNames cap.featureRequires
      );
      droppedWarnings = map (
        f:
        let
          req = cap.featureRequires.${f} or [ ];
        in
        "vfio-stealth: hypervFeatures.${f} = true but the host kernel does not advertise it (missing CONFIG: ${lib.concatStringsSep ", " req}). The feature has been dropped so libvirt can start the VM. To silence this, set hypervFeatures.${f} = false or verify the kernel was built with the required CONFIG options."
      ) droppedFeatures;
      processorOf =
        cpuIdentity:
        {
          modelId = null;
          maxSpeed = null;
          currentSpeed = null;
        }
        // processorDefaults.${cpuVendor}
        // lib.filterAttrs (_: value: value != null) (if cpuIdentity == null then { } else cpuIdentity);
    in
    {
      warnings = droppedWarnings;

      processor = processorOf;

      cpuFeatures =
        lib.optional (hypervMode == "hidden") {
          policy = "disable";
          name = "hypervisor";
        }
        # why: without topoext an AMD guest cannot see which threads share a core and an L3, so Windows counts each thread as a core with an L3 of its own
        ++ lib.optional (cpuVendor == "amd") {
          policy = "require";
          name = "topoext";
        }
        # why: KVM gives AMD guests Intel's leaf 7 speculation-control bits, which no AMD CPU sets; AMD's own bits in leaf 0x80000008 stay
        ++ lib.optionals (cpuVendor == "amd") (
          map
            (name: {
              policy = "disable";
              inherit name;
            })
            [
              "spec-ctrl"
              "stibp"
              "flush-l1d"
              "ssbd"
            ]
        )
        ++ lib.optionals (!cet) (
          map
            (name: {
              policy = "disable";
              inherit name;
            })
            [
              "cet-ibt"
              "cet-ss"
            ]
        )
        ++ [
          {
            policy = "optional";
            name = "invtsc";
          }
        ];

      features = {
        kvm.hidden.state = true;
        vmport.state = false;
      }
      // lib.optionalAttrs (hypervMode == "enlightened" && enabledFeatures != [ ]) {
        hyperv = hypervBlock;
      };

      clock = {
        offset = "localtime";
        timer = [
          {
            name = "rtc";
            tickpolicy = "catchup";
          }
          {
            name = "pit";
            tickpolicy = "delay";
          }
          {
            name = "hpet";
            present = true;
          }
          {
            name = "kvmclock";
            present = false;
          }
          {
            name = "hypervclock";
            present = hypervMode == "enlightened" && anyKernelDepEnabled;
          }
          {
            name = "tsc";
            present = true;
            mode = "native";
          }
        ];
      };

      sysinfo = {
        type = "smbios";
        bios.entry = [
          {
            name = "vendor";
            value = smbios.biosVendor;
          }
          {
            name = "version";
            value = smbios.biosVersion;
          }
          {
            name = "date";
            value = smbios.biosDate;
          }
          {
            name = "release";
            value = smbios.biosRelease;
          }
        ];
        system.entry = [
          {
            name = "manufacturer";
            value = smbios.manufacturer;
          }
          {
            name = "product";
            value = smbios.product;
          }
          {
            name = "serial";
            value = smbios.serial;
          }
        ]
        ++ lib.optionals (vmUuid != null) [
          {
            name = "uuid";
            value = vmUuid;
          }
        ]
        ++ [
          {
            name = "version";
            value = smbios.systemVersion;
          }
          {
            name = "sku";
            value = smbios.systemSku;
          }
          {
            name = "family";
            value = smbios.systemFamily;
          }
        ];
        baseBoard.entry = [
          {
            name = "manufacturer";
            value = smbios.manufacturer;
          }
          {
            name = "product";
            value = smbios.product;
          }
          {
            name = "version";
            value = smbios.baseBoardVersion;
          }
          {
            name = "serial";
            value = smbios.baseBoardSerial;
          }
          {
            name = "asset";
            value = smbios.baseBoardAsset;
          }
          {
            name = "location";
            value = smbios.baseBoardLocation;
          }
        ];
      };

      qemuArgs =
        cpuIdentity:
        let
          acpiDir = "${acpiTables}/share/acpi";
          smbiosDir = "${smbiosTables}/share/smbios";
          escapeSmbios = lib.replaceStrings [ "," ] [ ",," ];
          smbiosEntry = type: fields: [
            "-smbios"
            (lib.concatStringsSep "," (
              [ "type=${toString type}" ]
              ++ lib.mapAttrsToList (
                key: value: "${key}=${if builtins.isString value then escapeSmbios value else toString value}"
              ) (lib.filterAttrs (_: value: value != null) fields)
            ))
          ];
          processor = processorOf cpuIdentity;
          inherit (smbiosTables) cacheHandles;
        in
        [
          "-smbios"
          "type=0,vendor=${escapeSmbios smbios.biosVendor},version=${escapeSmbios smbios.biosVersion},date=${escapeSmbios smbios.biosDate},release=${escapeSmbios smbios.biosRelease}"
          "-smbios"
          "type=1,manufacturer=${escapeSmbios smbios.manufacturer},product=${escapeSmbios smbios.product},version=${escapeSmbios smbios.systemVersion},serial=${escapeSmbios smbios.serial},sku=${escapeSmbios smbios.systemSku},family=${escapeSmbios smbios.systemFamily}"
          "-smbios"
          "type=2,manufacturer=${escapeSmbios smbios.manufacturer},product=${escapeSmbios smbios.product},version=${escapeSmbios smbios.baseBoardVersion},serial=${escapeSmbios smbios.baseBoardSerial},asset=${escapeSmbios smbios.baseBoardAsset},location=${escapeSmbios smbios.baseBoardLocation}"
        ]
        ++ [
          "-smbios"
          "type=3,manufacturer=${escapeSmbios smbios.manufacturer},version=${escapeSmbios smbios.chassisVersion},serial=${escapeSmbios smbios.chassisSerial},asset=${escapeSmbios smbios.chassisAsset},sku=${escapeSmbios smbios.chassisSku}"
        ]
        ++ smbiosEntry 4 {
          sock_pfx = processor.socket;
          inherit (processor) manufacturer;
          version = processor.modelId;
          max-speed = processor.maxSpeed;
          current-speed = processor.currentSpeed;
          processor-family = processor.family;
          voltage = 128 + processor.voltageDecivolts;
          external-clock = processor.externalClock;
          inherit (processor) upgrade characteristics;
          l1-cache-handle = cacheHandles.l1;
          l2-cache-handle = cacheHandles.l2;
          l3-cache-handle = cacheHandles.l3;
        }
        # why: QEMU cannot build SMBIOS types 7 and 26-29 from fields, so they go in as binary tables
        ++ [
          "-smbios"
          "file=${smbiosDir}/type7-l1.bin"
        ]
        ++ [
          "-smbios"
          "file=${smbiosDir}/type7-l2.bin"
        ]
        ++ [
          "-smbios"
          "file=${smbiosDir}/type7-l3.bin"
        ]
        ++ [
          "-smbios"
          "file=${smbiosDir}/type26.bin"
        ]
        ++ [
          "-smbios"
          "file=${smbiosDir}/type27.bin"
        ]
        ++ [
          "-smbios"
          "file=${smbiosDir}/type28.bin"
        ]
        ++ [
          "-smbios"
          "file=${smbiosDir}/type29.bin"
        ]
        ++ lib.concatMap (
          port:
          smbiosEntry 8 {
            internal_reference = port.internalReference;
            internal_connector_type = port.internalConnectorType;
            external_reference = port.externalReference;
            connector_type = port.externalConnectorType;
            port_type = port.portType;
          }
        ) smbios.ports
        ++ lib.concatMap (
          slot:
          smbiosEntry 9 {
            slot_designation = slot.designation;
            slot_type = slot.type;
            slot_data_bus_width = slot.dataBusWidth;
            current_usage = slot.currentUsage;
            slot_length = slot.length;
            slot_id = slot.id;
            slot_characteristics1 = slot.characteristics1;
            slot_characteristics2 = slot.characteristics2;
          }
        ) smbios.systemSlots
        ++ lib.optionals acpiSsdt.spoofedDevices [
          "-acpitable"
          "file=${acpiDir}/spoofed-devices.aml"
        ]
        ++ lib.optionals acpiSsdt.fakeBattery [
          "-acpitable"
          "file=${acpiDir}/fake-battery.aml"
        ]
        ++ lib.optionals acpiSsdt.sensorProbes [
          "-acpitable"
          "file=${acpiDir}/sensor-probes.aml"
        ]
        ++ lib.optionals cpuPm [
          "-overcommit"
          "cpu-pm=on"
        ]
        # why: without a 64-bit MMIO window OVMF cannot map a large-BAR GPU framebuffer
        ++ lib.optionals (pciMmio64Mb > 0) [
          "-fw_cfg"
          "opt/ovmf/X-PciMmio64Mb,string=${toString pciMmio64Mb}"
          "-global"
          "q35-pcihost.pci-hole64-size=${toString pciMmio64Mb}M"
        ]
        ++ [
          "-global"
          "ICH9-LPC.disable_s3=0"
          "-global"
          "ICH9-LPC.disable_s4=0"
        ]
        # why: real boards hot-plug PCIe natively; QEMU's ACPI PCI hotplug adds the PHPR container VMAware's FIRMWARE check reads as QEMU
        ++ [
          "-global"
          "ICH9-LPC.acpi-pci-hotplug-with-bridge-support=off"
        ]
        ++ lib.optionals (processor.modelId != null) [
          "-global"
          "x86_64-cpu.model-id=${escapeSmbios processor.modelId}"
        ]
        ++ [
          "-smbios"
          "type=17,speed=${toString smbios.memory.speed},part=${escapeSmbios smbios.memory.partNumber},manufacturer=${escapeSmbios smbios.memory.manufacturer}"
        ]
        ++ [
          "-smbios"
          ("type=11" + lib.concatMapStrings (s: ",value=${escapeSmbios s}") smbios.oemStrings)
        ]
        ++ lib.concatMap (dev: [
          "-smbios"
          "type=41,designation=${escapeSmbios dev.designation},kind=${escapeSmbios dev.kind},instance=${toString dev.instance}"
        ]) smbios.onboardDevices
        # why: QEMU exposes APERF and MPERF only while cpu-pm=on lets them through without an exit
        ++ lib.optionals (aperfMperf && cpuPm) [
          "-global"
          "x86_64-cpu.aperfmperf=on"
        ]
        ++ lib.optionals kvmPvEnforceCpuid [
          "-global"
          "x86_64-cpu.kvm-pv-enforce-cpuid=on"
        ];

      devicesToRemove = lib.optionals stripVirtio [
        "virtio-balloon"
        "virtio-rng"
        "virtio-tablet"
      ];
    };
}
