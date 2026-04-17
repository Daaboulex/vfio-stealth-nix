{ lib }:
{
  mkStealthFeatures =
    {
      smbios,
      acpiTables,
      cpuIdentity ? null,
      vmUuid ? null,
      acpiSsdt ? {
        spoofedDevices = true;
        fakeBattery = true;
        sensorProbes = true;
      },
      cache ? {
        l1 = 512;
        l2 = 8192;
        l3 = 32768;
      },
      aperfMperf ? true,
      stripVirtio ? true,
      hypervVendorId ? "AuthAMD Ryzen",
    }:
    {
      cpuFeatures = [
        {
          policy = "disable";
          name = "hypervisor";
        }
        {
          policy = "require";
          name = "topoext";
        }
        {
          policy = "require";
          name = "invtsc";
        }
      ];

      features = {
        hyperv = {
          mode = "custom";
          relaxed.state = true;
          vapic.state = true;
          spinlocks = {
            state = true;
            retries = 8191;
          };
          vpindex.state = true;
          runtime.state = true;
          synic.state = true;
          stimer = {
            state = true;
            direct.state = true;
          };
          reset.state = true;
          vendor_id = {
            state = true;
            value = hypervVendorId;
          };
          frequencies.state = true;
          reenlightenment.state = true;
          tlbflush.state = true;
          ipi.state = true;
        };
        kvm = {
          hidden.state = true;
          hint-dedicated.state = true;
          poll-control.state = true;
        };
        vmport.state = false;
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
            present = false;
          }
          {
            name = "kvmclock";
            present = false;
          }
          {
            name = "hypervclock";
            present = true;
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
            name = "family";
            value = "To be filled by O.E.M.";
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
        ];
      };

      qemuArgs =
        cpuIdentity:
        let
          acpiDir = "${acpiTables}/share/acpi";
        in
        # SMBIOS type 3 (chassis)
        [
          "-smbios"
          "type=3,manufacturer=${smbios.manufacturer},version=1.0,serial=Default string,asset=Default string,sku=Default string"
        ]
        # SMBIOS type 27 (cooling device)
        ++ [
          "-smbios"
          "type=27,type=32,status=3,speed=3200"
        ]
        # SMBIOS type 28 (temperature probe)
        ++ [
          "-smbios"
          "type=28,description=CPU Thermal Probe,type=3,status=3,max=1000,min=100"
        ]
        # SMBIOS type 26 (voltage probe)
        ++ [
          "-smbios"
          "type=26,description=Voltage Probe,type=5,status=3,max=1500,min=800"
        ]
        # SMBIOS type 29 (current probe)
        ++ [
          "-smbios"
          "type=29,description=Current Probe,type=5,status=3,max=30000,min=100"
        ]
        # SMBIOS type 7 (cache memory) — prevents empty Win32_CacheMemory
        ++ [
          "-smbios"
          "type=7,designation=L1 Cache,type=1,level=1,installed-size=${toString cache.l1},maximum-size=${toString cache.l1}"
        ]
        ++ [
          "-smbios"
          "type=7,designation=L2 Cache,type=1,level=2,installed-size=${toString cache.l2},maximum-size=${toString cache.l2}"
        ]
        ++ [
          "-smbios"
          "type=7,designation=L3 Cache,type=1,level=3,installed-size=${toString cache.l3},maximum-size=${toString cache.l3}"
        ]
        # SMBIOS type 8 (port connector) — prevents empty Win32_PortConnector
        ++ [
          "-smbios"
          "type=8,internal-designator=USB 3.2 Gen 2,port-type=9"
        ]
        # SMBIOS type 9 (system slots) — prevents empty Win32_SystemSlot
        ++ [
          "-smbios"
          "type=9,designation=PCIEX16_1,type=0xa5,current-usage=3,length=4"
        ]
        # ACPI SSDT tables
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
        # CPU power management
        ++ [
          "-overcommit"
          "cpu-pm=on"
        ]
        # CPU identity (per-VM)
        ++ lib.optionals (cpuIdentity != null && cpuIdentity ? modelId && cpuIdentity.modelId != null) [
          "-global"
          "cpu.model-id=${cpuIdentity.modelId}"
          "-smbios"
          "type=4,sock_pfx=${smbios.socketPrefix},manufacturer=Advanced Micro Devices\\, Inc.,version=${cpuIdentity.modelId},max-speed=${toString cpuIdentity.maxSpeed},current-speed=${toString cpuIdentity.currentSpeed}"
        ]
        # SMBIOS type 17 (physical memory / DIMMs)
        ++ lib.concatMap (i: [
          "-smbios"
          "type=17,loc_pfx=DIMM_,bank=BANK ${toString i},speed=${toString smbios.memory.speed},part=${smbios.memory.partNumber},serial=0000000${toString i},size=${toString smbios.memory.size},manufacturer=${smbios.memory.manufacturer}"
        ]) (lib.range 0 (smbios.memory.count - 1))
        # APERF/MPERF passthrough (defeats IET-based VM detection, kernel 6.18+)
        # Use standalone -cpu property form to append to libvirt's existing -cpu host
        # rather than re-specifying the model (which would conflict/reset features).
        ++ lib.optionals aperfMperf [
          "-cpu"
          "kvm-disable-exits=aperfmperf"
        ];

      # Devices the consuming module should remove when stripVirtio is true.
      # VirtIO device models are trivially fingerprinted by anti-cheat;
      # replace balloon with static memory, RNG with virtio-rng-pci passthrough
      # or remove entirely, and tablet with USB passthrough or PS/2 emulation.
      devicesToRemove = lib.optionals stripVirtio [
        "virtio-balloon"
        "virtio-rng"
        "virtio-tablet"
      ];
    };
}
