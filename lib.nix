{ lib }:
{
  mkStealthFeatures =
    {
      smbios,
      acpiTables,
      spoofMac ? true,
      macPrefix ? "04:42:1a",
      cpuIdentity ? null,
      vmUuid ? null,
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
            value = "AMDisbetter!";
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
          "type=7,designation=L1 Cache,type=1,level=1,installed-size=512,maximum-size=512"
        ]
        ++ [
          "-smbios"
          "type=7,designation=L2 Cache,type=1,level=2,installed-size=8192,maximum-size=8192"
        ]
        ++ [
          "-smbios"
          "type=7,designation=L3 Cache,type=1,level=3,installed-size=98304,maximum-size=98304"
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
        ++ [
          "-acpitable"
          "file=${acpiDir}/spoofed-devices.aml"
        ]
        ++ [
          "-acpitable"
          "file=${acpiDir}/fake-battery.aml"
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
        ];
    };
}
