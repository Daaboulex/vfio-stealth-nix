{ lib }:
{
  mkStealthFeatures =
    {
      smbios,
      acpiTables,
      # Binary SMBIOS tables for types QEMU can't build via CLI args (7, 26-29).
      # Build with: pkgs.smbios-stealth-tables.override { cacheL1 = ...; ... }
      # Then pass here. The consuming module (parts/vfio/base.nix) wires this.
      smbiosTables,
      vmUuid ? null,
      acpiSsdt ? {
        spoofedDevices = true;
        fakeBattery = true;
        sensorProbes = true;
      },
      aperfMperf ? true,
      stripVirtio ? true,
      hypervVendorId ? "AuthAMDRyzen", # 12 chars — libvirt max
      hypervMode ? "enlightened", # "enlightened" = visible hypervisor + Hyper-V enlightenments; "hidden" = concealed hypervisor, no enlightenments
    }:
    {
      cpuFeatures =
        lib.optional (hypervMode == "hidden") {
          policy = "disable";
          name = "hypervisor";
        }
        ++ [
          {
            policy = "optional";
            name = "topoext";
          }
          {
            policy = "optional";
            name = "invtsc";
          }
        ];

      features = {
        kvm = {
          hidden.state = true;
          hint-dedicated.state = true;
          poll-control.state = true;
        };
        vmport.state = false;
      }
      // lib.optionalAttrs (hypervMode == "enlightened") {
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
            present = (hypervMode == "enlightened");
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
          # QEMU QemuOpts parses -smbios values as comma-separated key=value
          # pairs; a literal comma in a value must be doubled (,,) to escape it.
          escapeSmbios = lib.replaceStrings [ "," ] [ ",," ];
        in
        # SMBIOS type 2 (baseboard) is handled by sysinfo.baseBoard above —
        # libvirt translates it to -smbios type=2 automatically (since v1.2.17).
        # SMBIOS type 3 (chassis)
        [
          "-smbios"
          "type=3,manufacturer=${escapeSmbios smbios.manufacturer},version=1.0,serial=Default string,asset=Default string,sku=Default string"
        ]
        # SMBIOS types 7, 26-29 — binary table injection via -smbios file=
        # QEMU's smbios_entry_add() only supports structured field parsing for
        # types 0,1,2,3,4,8,9,11,17,41. Types 7,26,27,28,29 crash with
        # "Don't know how to build fields for SMBIOS type %ld". Raw binary
        # tables generated by smbios/generate-tables.py work around this limitation.
        #
        # Type 7 (cache) — prevents empty Win32_CacheMemory
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
        # Type 26 (voltage probe)
        ++ [
          "-smbios"
          "file=${smbiosDir}/type26.bin"
        ]
        # Type 27 (cooling device)
        ++ [
          "-smbios"
          "file=${smbiosDir}/type27.bin"
        ]
        # Type 28 (temperature probe)
        ++ [
          "-smbios"
          "file=${smbiosDir}/type28.bin"
        ]
        # Type 29 (current probe)
        ++ [
          "-smbios"
          "file=${smbiosDir}/type29.bin"
        ]
        # SMBIOS type 8 (port connector) — prevents empty Win32_PortConnector
        ++ [
          "-smbios"
          "type=8,internal_reference=USB 3.2 Gen 2,port_type=9"
        ]
        # SMBIOS type 9 (system slots) — prevents empty Win32_SystemSlot
        ++ [
          "-smbios"
          "type=9,slot_designation=PCIEX16_1,slot_type=0xa5,current_usage=3,slot_length=4"
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
        # S3/S4 sleep states — DSDT _S3/_S4 packages visible to guest.
        # VMAware VM::POWER_CAPABILITIES detects missing sleep states.
        ++ [
          "-global"
          "ICH9-LPC.disable_s3=0"
          "-global"
          "ICH9-LPC.disable_s4=0"
        ]
        # CPU identity (per-VM)
        ++ lib.optionals (cpuIdentity != null && cpuIdentity ? modelId && cpuIdentity.modelId != null) [
          "-global"
          "cpu.model-id=${cpuIdentity.modelId}"
          "-smbios"
          "type=4,sock_pfx=${smbios.socketPrefix},manufacturer=${
            escapeSmbios (cpuIdentity.manufacturer or "Advanced Micro Devices, Inc.")
          },version=${escapeSmbios cpuIdentity.modelId}${
            lib.optionalString (cpuIdentity.maxSpeed != null) ",max-speed=${toString cpuIdentity.maxSpeed}"
          }${
            lib.optionalString (
              cpuIdentity.currentSpeed != null
            ) ",current-speed=${toString cpuIdentity.currentSpeed}"
          }"
        ]
        # SMBIOS type 17 (physical memory / DIMMs)
        ++ lib.concatMap (i: [
          "-smbios"
          "type=17,loc_pfx=DIMM_,bank=BANK ${toString i},speed=${toString smbios.memory.speed},part=${escapeSmbios smbios.memory.partNumber},serial=0000000${toString i},manufacturer=${escapeSmbios smbios.memory.manufacturer}"
        ]) (lib.range 0 (smbios.memory.count - 1))
        # SMBIOS type 11 (OEM strings) — prevents empty Win32_ComputerSystem.OEMStringArray
        ++ [
          "-smbios"
          ("type=11" + lib.concatMapStrings (s: ",value=${escapeSmbios s}") smbios.oemStrings)
        ]
        # SMBIOS type 41 (onboard devices extended) — prevents empty Win32_OnBoardDevice
        ++ lib.concatMap (dev: [
          "-smbios"
          "type=41,designation=${escapeSmbios dev.designation},kind=${escapeSmbios dev.kind},instance=${toString dev.instance}"
        ]) smbios.onboardDevices
        # KVM paravirt MSR enforcement + APERF/MPERF passthrough.
        # Intentional: libvirt emits its own -cpu host,... and this
        # appends a second -cpu; QEMU merges them, last properties win.
        # APERF/MPERF: covers IET-based VM detection by passing
        # IA32_APERF/MPERF MSRs directly to guest. Requires kernel 6.18+
        # (KVM_X86_DISABLE_EXITS_APERFMPERF) + QEMU 11+ APERF/MPERF support
        # (native in AMD-v11.0.0.patch) + -overcommit cpu-pm=on
        # (already set above). When aperfMperf=false, omitted from -cpu.
        ++ [
          "-cpu"
          ("host,kvm-pv-enforce-cpuid=on" + lib.optionalString aperfMperf ",aperfmperf=on")
        ];

      # Devices the consuming module should remove when stripVirtio is true.
      # VirtIO device models are trivially identified by detection software;
      # replace balloon with static memory, RNG with virtio-rng-pci passthrough
      # or remove entirely, and tablet with USB passthrough or PS/2 emulation.
      devicesToRemove = lib.optionals stripVirtio [
        "virtio-balloon"
        "virtio-rng"
        "virtio-tablet"
      ];
    };
}
