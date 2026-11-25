{ nixvirt, patchAssertions }:
{
  config,
  options,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.virtualisation.vfio-stealth;

  kernelPatch = import ./kernel/post-patch.nix { inherit lib; } {
    inherit (cfg) cpuVendor;
    instructionFixes = cfg.enable && cfg.instructionFixes.enable;
    timing = cfg.enable && cfg.timing.enable;
    cpuidSpoof = cfg.enable && cfg.cpuidSpoof.enable;
    cpuidPassthrough = cfg.enable && cfg.cpuidPassthrough.enable;
    pinnedCpuid = cfg.enable && cfg.cpuidPassthrough.pinned;
  };

  microsoftDbx =
    let
      pin = (lib.importJSON ./version.json).microsoftDbx;
    in
    pkgs.fetchurl {
      name = "microsoft-dbx-x64-${pin.version}.efiauth2";
      url = "https://raw.githubusercontent.com/microsoft/secureboot_objects/${pin.rev}/PostSignedObjects/SignedByKEK2023/dbx_x64.efiauth2";
      inherit (pin) hash;
    };

  pciAddress = lib.types.strMatching "^[0-9a-fA-F]{4}:[0-9a-fA-F]{2}:[0-9a-fA-F]{2}\\.[0-7]$";
  pciId = lib.types.strMatching "^[0-9a-fA-F]{4}:[0-9a-fA-F]{4}$";
  cpuNumber = "(0|[1-9][0-9]*)";
  cpuset = lib.types.strMatching "^${cpuNumber}(-${cpuNumber})?(,${cpuNumber}(-${cpuNumber})?)*$";
  powerOfTwo = lib.types.addCheck lib.types.ints.positive (n: builtins.bitAnd n (n - 1) == 0) // {
    description = "power of two";
  };

  cpusOf =
    set:
    lib.concatMap (
      part:
      let
        bounds = map lib.toInt (lib.splitString "-" part);
      in
      lib.range (lib.head bounds) (lib.last bounds)
    ) (lib.splitString "," set);

  pageMib = if cfg.hugepages.size == "1G" then 1024 else 2;

  memoryLayout = import ./smbios/memory-layout.nix;
  memoryTypes = import ./smbios/memory-types.nix;
  boardConnectors = import ./smbios/board-connectors.nix;
  processorDefaults = import ./smbios/processor-defaults.nix;
  identitySchema = import ./qemu/device-identity-schema.nix;
  identityDefaults = import ./qemu/device-identities.nix;
  smbiosText = lib.types.strMatching "[ -~]{1,64}";
  identity = import ./identity.nix { inherit lib; };
  seeded = shared: derive: if cfg.identity.seed == null then shared else derive cfg.identity.seed;
  sharedIdentity = {
    "smbios.baseBoardSerial" = "Default string";
    "disk.serial" = "Default string";
    hypervVendorId = "AuthAMDRyzen";
    "edid.serialNumber" = 0;
    "acpiSsdt.batterySerial" = "41167";
  };
  unsetCaches =
    lib.filter
      (
        level:
        options.virtualisation.vfio-stealth.smbios.cache.${level}.highestPrio == (lib.mkOptionDefault null)
        .priority
      )
      [
        "l1"
        "l2"
        "l3"
      ];
  sharedValues = lib.filter (
    path: lib.getAttrFromPath (lib.splitString "." path) cfg == sharedIdentity.${path}
  ) (lib.attrNames sharedIdentity);

  identityOption =
    path: kind: default:
    lib.mkOption {
      type =
        if kind ? pattern then
          lib.types.strMatching kind.pattern
        else
          lib.types.ints.between kind.min kind.max;
      inherit default;
      description = "The ${path} an emulated QEMU device reports in place of QEMU's own: ${kind.form}. The default comes from qemu/device-identities.nix, which every install shares; set your own to keep installs apart. Goes into packages.qemu.";
    };

  processorOverride =
    field: type: form:
    lib.mkOption {
      type = lib.types.nullOr type;
      default = null;
      description = "SMBIOS type 4 ${form}. null takes the value smbios/processor-defaults.nix gives cpuVendor: ${
        lib.concatStringsSep " on amd, " (
          map (vendor: builtins.toJSON processorDefaults.${vendor}.${field}) [
            "amd"
            "intel"
          ]
        )
      } on intel, read from real AM5 and LGA1700 boards.";
    };
  memoryModules = lib.length (lib.filter (slot: slot.populated) cfg.smbios.memory.slots);
  slotMib = cfg.smbios.memory.maxCapacityGb * 1024 / lib.length cfg.smbios.memory.slots;

  hugepageDomains = lib.filterAttrs (_: domain: domain.hugepages) cfg.domains;

  bootIds = lib.unique (
    lib.concatMap (
      domain: lib.optionals (domain.gpu != null && domain.gpu.binding == "boot") domain.gpu.ids
    ) (lib.attrValues cfg.domains)
  );

  gpuDriversByVendor = {
    "10de" = [
      "nouveau"
      "nvidia"
    ];
    "1002" = [
      "amdgpu"
      "radeon"
    ];
    "8086" = [
      "i915"
      "xe"
    ];
  };

  bootGpuDrivers = lib.unique (
    lib.concatMap (
      id: lib.attrByPath [ (lib.toLower (builtins.substring 0 4 id)) ] [ ] gpuDriversByVendor
    ) bootIds
  );

  soundVms = lib.attrNames (lib.filterAttrs (_: domain: domain.sound != null) cfg.domains);

  evdevPaths =
    lib.optional (cfg.evdev.keyboard != null) cfg.evdev.keyboard
    ++ cfg.evdev.extraKeyboards
    ++ lib.optional (cfg.evdev.mouse != null) cfg.evdev.mouse;

  plan = import ./host/plan.nix { inherit lib cfg; };

  hook = pkgs.callPackage ./host/qemu-hook.nix { inherit plan; };

  usbReattach = pkgs.callPackage ./host/usb-reattach.nix { };

  domainOverride =
    type: hostOption:
    lib.mkOption {
      type = lib.types.nullOr type;
      default = null;
      description = "This domain's ${hostOption}, for a VM that shows other hardware than the host's other VMs; null takes the host's.";
    };
in
{
  _class = "nixos";

  imports = [
    (lib.mkRemovedOptionModule [
      "virtualisation"
      "vfio-stealth"
      "smbios"
      "memory"
      "count"
    ] "The VM's memory is split evenly over the populated entries of smbios.memory.slots.")
    (lib.mkRenamedOptionModule
      [
        "virtualisation"
        "vfio-stealth"
        "smbios"
        "socketPrefix"
      ]
      [
        "virtualisation"
        "vfio-stealth"
        "cpuIdentity"
        "socket"
      ]
    )
  ];

  options.virtualisation.vfio-stealth = {
    enable = lib.mkEnableOption "VFIO hardware emulation stack";

    identity.seed = lib.mkOption {
      type = lib.types.nullOr (lib.types.strMatching ".{8,}");
      default = null;
      example = "a private phrase only this host uses";
      description = "A private string of 8 or more characters, unique to this host, from which every unique identity value left unset is derived: smbios.baseBoardSerial, the serial of each populated slot in smbios.memory.slots, disk.serial, edid.serialNumber, acpiSsdt.batterySerial and hypervVendorId, and with smbios.perDomainSerials each VM's serials. Each derived value has the form its kind of part reports, and the same seed gives the same values on every rebuild. null leaves them at values every host without a seed shares, which tie a guest to this module, and warns for each one still set to it. Anyone who knows the seed can compute the values, so keep it out of a public repository, for example in a private flake input.";
    };

    cpuVendor = lib.mkOption {
      type = lib.types.nullOr (
        lib.types.enum [
          "amd"
          "intel"
        ]
      );
      default = null;
      description = "Host CPU vendor. There is no default, and an enabled module refuses null. It picks the QEMU and OVMF pair in packages, the AMD-only kernel options and patches, and the CPU flags in domain. \"intel\" refuses the kernel options that patch KVM's SVM code: timing.enable, cpuidSpoof.enable, cpuidPassthrough.enable and cpuidPassthrough.pinned.";
      example = "amd";
    };

    timing = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = cfg.cpuVendor == "amd";
        defaultText = lib.literalExpression "cpuVendor == \"amd\"";
        description = "BetterTiming TSC compensation: traps RDTSC and RDTSCP in every VM on the host, and hides from every guest TSC read the time KVM spends between a CPUID, RDTSC, RDTSCP, WBINVD, XSETBV or INVD exit, or a guest read of the TSC MSR, and the next entry.";
      };
    };

    cpuidSpoof = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = cfg.cpuVendor == "amd";
        defaultText = lib.literalExpression "cpuVendor == \"amd\"";
        description = "Add the CPUID leaf 0 fast path (from AutoVirt, formerly Hypervisor-Phantom) to kernelPostPatch. A guest CPUID with EAX = 0 is answered right after the VM exit with the VM's own CPUID leaf 0, the values KVM would give, and the guest is re-entered without the rest of the exit handling. The patch also clears the RDTSC and RDTSCP intercepts, which the timing.enable patch sets again. No other leaf is changed: the hypervisor-present bit (leaf 1, bit 31) and the hypervisor vendor leaf (0x40000000) are not touched. Skipped when cpuidPassthrough.enable is true.";
      };
    };

    instructionFixes.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Add KVM patches to kernelPostPatch so the guest sees bare-metal behaviour where KVM differs. On both vendors: VMCALL and VMMCALL at CPL > 0 raise #UD (vfio-native). On amd also: an SVM instruction while the guest's EFER.SVME is clear raises #UD, and ICEBP's #DB reports the address after the instruction. VMAware's KVM_INTERCEPTION, SVM_EXCEPTIONS and SINGLE_STEP checks read these.";
    };

    cpuidPassthrough = {
      pinned = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Add vfio-native's experimental runtime CPUID passthrough to kernelPostPatch. Writing 1 to /sys/module/kvm_amd/parameters/cpuid_passthrough after the guest has booted stops CPUID exits on vCPUs pinned 1:1 to a host core, and kvm_amd.brand_string sets the processor name the guest then reads; Windows hangs when it is switched on during boot. AMD hosts only, and not with cpuidPassthrough.enable.";
      };
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Disable CPUID interception entirely. Guest executes CPUID at native hardware speed (zero VM exit). Addresses software-counter timing checks such as VMAware's TIMER and SINGLE_STEP. Requires AMD host with host-passthrough CPU mode. When enabled, cpuidSpoof is skipped (passthrough takes precedence). Side effect: Hyper-V enlightenments are invisible to guest (Windows uses TSC directly). LIMITATION: the guest sees the host's raw topology (core count, thread count, NUMA nodes) via CPUID; if the VM has fewer vCPUs than the host has threads, Windows deadlocks at boot waiting for processors that do not exist.";
      };
    };

    kernelParams = {
      maxCState = lib.mkOption {
        type = lib.types.ints.between 0 9;
        default = 1;
        description = "processor.max_cstate value passed on the kernel command line. Lower values reduce timing jitter that can reveal virtualization.";
      };

      tscReliable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Pass tsc=reliable on the kernel command line. Prevents kernel from falling back to HPET/ACPI PM timer, which detection software can flag.";
      };
    };

    smbios = {
      manufacturer = lib.mkOption {
        type = lib.types.str;
        default = "To Be Filled By O.E.M.";
        description = "SMBIOS system manufacturer string. Populates WMI Win32_ComputerSystem.Manufacturer.";
      };
      product = lib.mkOption {
        type = lib.types.str;
        default = "To Be Filled By O.E.M.";
        description = "SMBIOS product name string. Populates WMI Win32_ComputerSystem.Model.";
      };
      biosVendor = lib.mkOption {
        type = lib.types.str;
        default = "American Megatrends Inc.";
        description = "SMBIOS BIOS vendor string. Populates WMI Win32_BIOS.Manufacturer. Also the UEFI firmware vendor of packages.ovmf.";
      };
      biosVersion = lib.mkOption {
        type = lib.types.str;
        default = "1001";
        description = "SMBIOS BIOS version string. Populates WMI Win32_BIOS.SMBIOSBIOSVersion.";
      };
      biosDate = lib.mkOption {
        type = lib.types.str;
        default = "01/01/2025";
        description = "BIOS release date (MM/DD/YYYY format). Populates Win32_BIOS.ReleaseDate. OVMF defaults to 02/02/2022 which is a generic VM date. Set to your board's actual BIOS date.";
      };
      biosRelease = lib.mkOption {
        type = lib.types.str;
        default = "2.4";
        description = "BIOS release version (major.minor). Maps to SMBIOS Type 0 System BIOS Release field.";
      };
      serial = lib.mkOption {
        type = lib.types.str;
        default = "System Serial Number";
        description = "SMBIOS system serial number. Populates WMI Win32_ComputerSystemProduct.IdentifyingNumber.";
      };
      baseBoardVersion = lib.mkOption {
        type = lib.types.str;
        default = "Rev 1.xx";
        description = "Baseboard version string (SMBIOS Type 2). Populates Win32_BaseBoard.Version.";
      };
      baseBoardSerial = lib.mkOption {
        type = lib.types.str;
        default = seeded sharedIdentity."smbios.baseBoardSerial" (
          seed: identity.digits seed "baseboard" 15
        );
        defaultText = lib.literalMD "fifteen digits derived from identity.seed, or `\"Default string\"` without one";
        description = "Baseboard serial number (SMBIOS Type 2), as `dmidecode -t 2` shows it. Populates WMI Win32_BaseBoard.SerialNumber.";
      };
      baseBoardAsset = lib.mkOption {
        type = lib.types.str;
        default = "Default string";
        description = "Baseboard asset tag (SMBIOS Type 2).";
      };
      baseBoardLocation = lib.mkOption {
        type = lib.types.str;
        default = "Default string";
        description = "Baseboard location in chassis (SMBIOS Type 2).";
      };
      systemVersion = lib.mkOption {
        type = smbiosText;
        default = "System Version";
        description = "SMBIOS type 1 Version, as `dmidecode -t 1` shows it; the default is what an ASUS Z790 board reports. Populates WMI Win32_ComputerSystemProduct.Version.";
      };
      systemSku = lib.mkOption {
        type = smbiosText;
        default = "SKU";
        description = "SMBIOS type 1 SKU Number, as `dmidecode -t 1` shows it; the default is what an ASUS Z790 board reports. Populates WMI Win32_ComputerSystem.SystemSKUNumber.";
      };
      systemFamily = lib.mkOption {
        type = smbiosText;
        default = "To be filled by O.E.M.";
        description = "SMBIOS type 1 Family, as `dmidecode -t 1` shows it; the default is what an ASUS Z790 board reports. Populates WMI Win32_ComputerSystem.SystemFamily.";
      };
      chassisVersion = lib.mkOption {
        type = smbiosText;
        default = "Default string";
        description = "SMBIOS type 3 Version, as `dmidecode -t 3` shows it; AMI firmware on ASUS and ASRock AM5 and LGA1700 boards reports Default string. Populates WMI Win32_SystemEnclosure.Version.";
      };
      chassisSerial = lib.mkOption {
        type = smbiosText;
        default = "Default string";
        description = "SMBIOS type 3 Serial Number, as `dmidecode -t 3` shows it. Populates WMI Win32_SystemEnclosure.SerialNumber.";
      };
      chassisAsset = lib.mkOption {
        type = smbiosText;
        default = "Default string";
        description = "SMBIOS type 3 Asset Tag, as `dmidecode -t 3` shows it. Populates WMI Win32_SystemEnclosure.SMBIOSAssetTag.";
      };
      chassisSku = lib.mkOption {
        type = smbiosText;
        default = "Default string";
        description = "SMBIOS type 3 SKU Number, as `dmidecode -t 3` shows it; AMI firmware on ASUS and ASRock boards reports Default string.";
      };
      ports = lib.mkOption {
        type = lib.types.listOf (
          lib.types.submodule {
            options = {
              internalReference = lib.mkOption {
                type = lib.types.nullOr smbiosText;
                description = "Internal Reference Designator; null shows as Not Specified.";
              };
              internalConnectorType = lib.mkOption {
                type = lib.types.ints.u8;
                description = "Internal Connector Type byte, DSP0134 7.9.2: 0 = None, 255 = Other, 24 = 9 Pin Dual Inline (pin 10 cut), 34 = SAS/SATA Plug Receptacle.";
              };
              externalReference = lib.mkOption {
                type = lib.types.nullOr smbiosText;
                description = "External Reference Designator; null shows as Not Specified.";
              };
              externalConnectorType = lib.mkOption {
                type = lib.types.ints.u8;
                description = "External Connector Type byte, DSP0134 7.9.2: 0 = None, 15 = PS/2, 18 = Access Bus (USB), 35 = USB Type-C Receptacle, 31 = Mini Jack (headphones).";
              };
              portType = lib.mkOption {
                type = lib.types.ints.u8;
                description = "Port Type byte, DSP0134 7.9.3: 16 = USB, 13 = Keyboard Port, 14 = Mouse Port, 28 = Video Port, 29 = Audio Port, 31 = Network Port, 32 = SATA, 255 = Other.";
              };
            };
          }
        );
        default = boardConnectors.ports;
        defaultText = lib.literalMD "the port connectors an ASRock X670E Pro RS reports, from smbios/board-connectors.nix";
        description = "The board's port connectors in `dmidecode -t 8` order, one SMBIOS type 8 structure each, with the numbers DSP0134 gives the names dmidecode prints. Copy them from `sudo dmidecode -t 8` on the host; an empty list leaves type 8 out, as some boards do. Populates WMI Win32_PortConnector.";
      };
      systemSlots = lib.mkOption {
        type = lib.types.listOf (
          lib.types.submodule {
            options = {
              designation = lib.mkOption {
                type = smbiosText;
                description = "The slot's Designation.";
              };
              type = lib.mkOption {
                type = lib.types.ints.u8;
                description = "Slot Type byte, DSP0134 7.10.1: 165 = PCI Express, 182 = PCI Express 3 x16, 189 = PCI Express 4 x16, 195 = PCI Express 5 x16, 23 = M.2 Socket 3.";
              };
              dataBusWidth = lib.mkOption {
                type = lib.types.ints.between 1 14;
                description = "Slot Data Bus Width, DSP0134 7.10.2: 8 = x1, 10 = x4, 11 = x8, 13 = x16.";
              };
              currentUsage = lib.mkOption {
                type = lib.types.ints.between 1 5;
                description = "Current Usage, DSP0134 7.10.3: 3 = Available, 4 = In Use, 5 = Unavailable.";
              };
              length = lib.mkOption {
                type = lib.types.ints.between 1 6;
                description = "Slot Length, DSP0134 7.10.4: 3 = Short, 4 = Long.";
              };
              id = lib.mkOption {
                type = lib.types.ints.u16;
                description = "Slot ID.";
              };
              characteristics1 = lib.mkOption {
                type = lib.types.ints.u8;
                description = "Slot Characteristics 1 bit field, DSP0134 7.10.6: 4 = 3.3 V is provided, 8 = Opening is shared.";
              };
              characteristics2 = lib.mkOption {
                type = lib.types.ints.u8;
                description = "Slot Characteristics 2 bit field, DSP0134 7.10.7: 1 = PME signal is supported, 2 = Hot-plug, 8 = PCIe slot bifurcation is supported.";
              };
            };
          }
        );
        default = boardConnectors.slots;
        defaultText = lib.literalMD "the four PCI Express slots an ASRock X670E Pro RS reports, from smbios/board-connectors.nix";
        description = "The board's expansion slots in `dmidecode -t 9` order, one SMBIOS type 9 structure each. A slot shows no Bus Address, which QEMU can give only for a device on its root bus. Populates WMI Win32_SystemSlot.";
      };
      chassisType = lib.mkOption {
        type = lib.types.ints.between 1 36;
        default = 3;
        description = "SMBIOS chassis type number (type 3) from DSP0134 3.x, as `cat /sys/class/dmi/id/chassis_type` shows it: 3 = Desktop, 4 = Low Profile Desktop, 6 = Mini Tower, 7 = Tower, 9 = Laptop, 10 = Notebook, 13 = All in One, 35 = Mini PC. QEMU writes 1, Other, which VMAware's CTYPE check flags, and its -smbios option has no field for it. Populates WMI Win32_SystemEnclosure.ChassisTypes. Goes into packages.qemu.";
      };
      perDomainSerials = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Give each VM in domains its own system and baseboard serial, twelve hex digits derived from the VM's name, in place of serial and baseBoardSerial. Two VMs that run at once with the same serials are two machines no vendor ships; one VM at a time keeps the host's.";
      };

      memory = {
        manufacturer = lib.mkOption {
          type = lib.types.str;
          default = "Unknown";
          description = "DIMM manufacturer for SMBIOS type 17. Populates WMI Win32_PhysicalMemory.Manufacturer. Set to your real RAM vendor.";
        };
        partNumber = lib.mkOption {
          type = lib.types.str;
          default = "Unknown";
          description = "DIMM part number. Populates WMI Win32_PhysicalMemory.PartNumber. Set to your real DIMM part number.";
        };
        speed = lib.mkOption {
          type = lib.types.ints.positive;
          default = 4800;
          description = "Memory speed in MT/s. Populates WMI Win32_PhysicalMemory.Speed.";
        };
        errorCorrection = lib.mkOption {
          type = lib.types.ints.between 1 7;
          default = 3;
          description = "SMBIOS type 16 memory array error correction per DSP0134: 1 = Other, 2 = Unknown, 3 = None, 4 = Parity, 5 = Single-bit ECC, 6 = Multi-bit ECC, 7 = CRC. A consumer desktop with non-ECC DIMMs reports 3; QEMU writes 6, which no such board has. Populates WMI Win32_PhysicalMemoryArray.MemoryErrorCorrection. Goes into packages.qemu.";
        };
        type = lib.mkOption {
          type = lib.types.enum (lib.attrNames memoryTypes);
          default = memoryLayout.type;
          description = "Memory type of every populated SMBIOS type 17 device, one of the DSP0134 7.18.2 names in smbios/memory-types.nix, as the Type line of `dmidecode -t 17` shows it. QEMU writes RAM, which no DIMM reports. Populates WMI Win32_PhysicalMemory.SMBIOSMemoryType. Goes into packages.qemu.";
        };
        typeDetail = lib.mkOption {
          type = lib.types.ints.u16;
          default = memoryLayout.typeDetail;
          description = "Type Detail bit field of every populated SMBIOS type 17 device, DSP0134 7.18.3: 128 = Synchronous, 16384 = Unbuffered (Unregistered), 8192 = Registered (Buffered). The default 16512 is the Synchronous Unbuffered (Unregistered) a desktop DDR5 DIMM reports; QEMU writes Other. Populates WMI Win32_PhysicalMemory.TypeDetail. Goes into packages.qemu.";
        };
        rank = lib.mkOption {
          type = lib.types.ints.between 1 15;
          default = memoryLayout.rank;
          description = "Rank of every populated SMBIOS type 17 device, as `dmidecode -t 17` shows it; a 16 GB DDR5 DIMM is single rank, a 32 GB one dual rank. QEMU writes Unknown. Goes into packages.qemu.";
        };
        voltageMillivolts = lib.mkOption {
          type = lib.types.nullOr (lib.types.ints.between 1 65535);
          default = lib.attrByPath [ cfg.smbios.memory.type ] null memoryLayout.nominalMillivolts;
          defaultText = lib.literalMD "the JEDEC voltage of smbios.memory.type: 1100 for DDR5, 1200 for DDR4, 1500 for DDR3, null otherwise";
          description = "Minimum, maximum and configured voltage in millivolts of every populated SMBIOS type 17 device, as `dmidecode -t 17` shows them in volts; a module running an XMP or EXPO profile reports its own. null reports Unknown, as QEMU does. Populates WMI Win32_PhysicalMemory.ConfiguredVoltage. Goes into packages.qemu.";
        };
        maxCapacityGb = lib.mkOption {
          type = lib.types.ints.positive;
          default = memoryLayout.maxCapacityGb;
          description = "The board's maximum memory in GB for the SMBIOS type 16 memory array, as `dmidecode -t 16` shows it under Maximum Capacity; AMD AM5 boards report 128. QEMU reports the VM's memory. A domain whose memory exceeds what its populated slots take, maxCapacityGb divided over every slot, is refused. Populates WMI Win32_PhysicalMemoryArray.MaxCapacity. Goes into packages.qemu.";
        };
        slots = lib.mkOption {
          type = lib.types.nonEmptyListOf (
            lib.types.submodule {
              options = {
                locator = lib.mkOption {
                  type = lib.types.strMatching "[A-Za-z0-9 _./#:-]{1,64}";
                  description = "The slot's Locator, as `dmidecode -t 17` shows it.";
                };
                bank = lib.mkOption {
                  type = lib.types.strMatching "[A-Za-z0-9 _./#:-]{1,64}";
                  description = "The slot's Bank Locator, as `dmidecode -t 17` shows it.";
                };
                populated = lib.mkOption {
                  type = lib.types.bool;
                  description = "Whether the slot holds one of the VM's modules. The VM's memory is split evenly over the populated slots; an empty slot reports No Module Installed.";
                };
                serial = lib.mkOption {
                  type = lib.types.nullOr (lib.types.strMatching "[A-Za-z0-9]{1,32}");
                  default = null;
                  description = "The module's Serial Number, as `dmidecode -t 17` shows it. null takes eight hex digits derived from identity.seed and the slot's place, or none without a seed. An empty slot reports none.";
                };
              };
            }
          );
          default = memoryLayout.slots;
          defaultText = lib.literalExpression ''
            [
              { locator = "DIMM 0"; bank = "P0 CHANNEL A"; populated = false; }
              { locator = "DIMM 1"; bank = "P0 CHANNEL A"; populated = true; }
              { locator = "DIMM 0"; bank = "P0 CHANNEL B"; populated = false; }
              { locator = "DIMM 1"; bank = "P0 CHANNEL B"; populated = true; }
            ]'';
          description = "Every DIMM slot of the board in `dmidecode -t 17` order, one SMBIOS type 17 memory device each, and the slot count of the type 16 memory array. The default is the four slots of an AMD AM5 board with the second slot of each channel populated, as its manual asks for two modules. QEMU builds one memory device per machine-type chunk of the VM's memory, named by loc_pfx and an index, and no empty slot. Populates WMI Win32_PhysicalMemory and Win32_PhysicalMemoryArray.MemoryDevices. Goes into packages.qemu.";
        };
      };

      cache = {
        l1 = lib.mkOption {
          type = lib.types.ints.positive;
          default = 512;
          description = "L1 cache size in KB for SMBIOS type 7. Goes into packages.smbiosTables.";
        };
        l2 = lib.mkOption {
          type = lib.types.ints.positive;
          default = 8192;
          description = "L2 cache size in KB for SMBIOS type 7. Goes into packages.smbiosTables.";
        };
        l3 = lib.mkOption {
          type = lib.types.ints.positive;
          default = 32768;
          description = "L3 cache size in KB for SMBIOS type 7. Goes into packages.smbiosTables.";
        };
        assocL1 = lib.mkOption {
          type = lib.types.ints.between 1 14;
          default = 7;
          description = "SMBIOS type 7 associativity byte for L1 (7 = 8-way, the AMD Zen 4/5 L1d value). Other common: 8 (16-way), 9 (12-way), 6 (fully associative). See DSP0134 Table 36. Goes into packages.smbiosTables.";
        };
        assocL2 = lib.mkOption {
          type = lib.types.ints.between 1 14;
          default = 7;
          description = "SMBIOS type 7 associativity byte for L2 (7 = 8-way, the AMD Zen 4/5 L2 value). Goes into packages.smbiosTables.";
        };
        assocL3 = lib.mkOption {
          type = lib.types.ints.between 1 14;
          default = 8;
          description = "SMBIOS type 7 associativity byte for L3 (8 = 16-way, the AMD Zen 4/5 L3 value). Goes into packages.smbiosTables.";
        };
        ecc = lib.mkOption {
          type = lib.types.ints.between 1 6;
          default = 3;
          description = "SMBIOS type 7 error correction type per DSP0134: 1 = Other, 2 = Unknown, 3 = None, 4 = Parity, 5 = Single-bit ECC, 6 = Multi-bit ECC. Consumer Ryzen has no cache ECC; server EPYC has parity on L3. Goes into packages.smbiosTables.";
        };
      };

      oemStrings = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [
          "Default string"
          "Default string"
          "Default string"
          "Default string"
        ];
        description = "OEM Strings for SMBIOS Type 11. Real boards populate 4-6 entries. Empty Type 11 is a VM indicator.";
      };

      onboardDevices = lib.mkOption {
        type = lib.types.listOf (
          lib.types.submodule {
            options = {
              designation = lib.mkOption {
                type = lib.types.str;
                description = "Device designation string.";
              };
              kind = lib.mkOption {
                type = lib.types.enum [
                  "other"
                  "unknown"
                  "video"
                  "scsi"
                  "ethernet"
                  "tokenring"
                  "sound"
                  "pata"
                  "sata"
                  "sas"
                ];
                description = "Device type.";
              };
              instance = lib.mkOption {
                type = lib.types.ints.between 1 255;
                description = "Device instance number.";
              };
            };
          }
        );
        default = [ ];
        description = "Onboard devices for SMBIOS Type 41. Set to match your board (e.g., LAN, SATA controllers from dmidecode -t 41). Empty = no Type 41 entries.";
      };
    };

    aperfMperf = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Pass through IA32_APERF/MPERF MSRs to guest (addresses IET-based VM indicators), in a VM with cpuPm on, the only one QEMU offers them to. Requires kernel 6.18+.";
    };

    cet = lib.mkOption {
      type = lib.types.bool;
      default = cfg.cpuVendor == "amd";
      defaultText = lib.literalExpression "cpuVendor == \"amd\"";
      description = "Show the guest the host CPU's control-flow enforcement, shadow stacks and indirect branch tracking, as hardware does. Off by default with Intel: under KVM on an Intel host, Windows' own Hyper-V, which VBS and HVCI run on, does not start while the guest sees CET.";
    };

    kvmPvEnforceCpuid = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Set kvm-pv-enforce-cpuid=on on the guest CPU. QEMU's default is off. With it on, a guest that touches the KVM paravirt MSRs without the matching CPUID bit gets #GP, which stops Windows in early boot.";
    };

    spoofMac = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Give the network card of every VM in domains a MAC address that starts with macPrefix, so its maker is not QEMU's 52:54:00. The last three bytes come from the VM's uuid, so they stay fixed.";
    };

    macPrefix = lib.mkOption {
      type = lib.types.strMatching "^[0-9A-Fa-f]{2}:[0-9A-Fa-f]{2}:[0-9A-Fa-f]{2}$";
      default = "D8:BB:C1";
      description = "The first three bytes of the MAC address spoofMac gives, as colon-separated hex, for example D8:BB:C1. Set them to those of your board's own network card.";
    };

    pciSubsystem = lib.mkOption {
      type = lib.types.strMatching "^[0-9a-fA-F]{4}:[0-9a-fA-F]{4}$";
      default = "8086:7270";
      description = "PCI subsystem vendor:device that every emulated PCI device reports in place of QEMU's 1af4:1100. Copy the one your board's chipset devices show in `lspci -nnv`. The device id must be 0040 or more: the virtio spec asks it of modern virtio devices, and OVMF's virtio driver ignores a device below it, so a virtio disk behind a PCIe root port would not boot. Goes into packages.qemu.";
    };

    hdaCodec = lib.mkOption {
      type = lib.types.strMatching "^[0-9a-fA-F]{4}:[0-9a-fA-F]{4}$";
      default = "10ec:0897";
      description = "Vendor:device id the emulated HD Audio codec reports in place of QEMU's, with pciSubsystem as its subsystem id. Copy the Vendor Id that `cat /proc/asound/card*/codec#*` shows for your board's codec; the default is a Realtek ALC897. Goes into packages.qemu.";
    };

    hypervVendorId = lib.mkOption {
      type = lib.types.strMatching "^.{1,12}$";
      default = seeded sharedIdentity.hypervVendorId (seed: identity.hex seed "hyperv" 12);
      defaultText = lib.literalMD "twelve hex digits derived from identity.seed, or `\"AuthAMDRyzen\"` without one";
      description = "Hyper-V vendor_id reported to guest (1 to 12 chars, libvirt hard limit). Avoid well-known VM values like 'AMDisbetter!' or 'Microsoft Hv'.";
    };

    hypervMode = lib.mkOption {
      type = lib.types.enum [
        "enlightened"
        "hidden"
      ];
      default = "enlightened";
      description = "Hyper-V enlightenment strategy. \"enlightened\" sets the hypervisor CPUID bit and exposes the Hyper-V enlightenments, which speed up Windows, and VMAware reads HYPERVISOR_BIT and HYPERVISOR_STR from them. \"hidden\" clears the bit and emits no enlightenments, which is the stealth setting. Windows' own Hyper-V, which VBS and HVCI need, starts in either mode, on an Intel host with cet off; enlightened adds VMAware's SINGLE_STEP and VMID, and INTERRUPT_SHADOW on AMD. Per-VM overridable via domains.<name>.hypervMode";
    };

    hypervFeatures = {
      vapic = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "SynIC APIC virtualization (HvApic). Requires CONFIG_KVM_HYPERV=y in the host kernel (KVM_CAP_HYPERV_VAPIC); libvirt errors with 'host doesn't support hyperv vapic' otherwise.";
      };
      relaxed = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Relaxed timing (HvRelax). QEMU/libvirt-level setting with no KVM cap; always supported.";
      };
      spinlocks = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Spinlock retry reporting (HvSpin). Requires CONFIG_KVM_HYPERV=y (KVM_CAP_HYPERV_SPIN); libvirt errors with 'host doesn't support hyperv spinlocks' otherwise.";
      };
      frequencies = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "TSC frequency reporting (HvTscPage). Requires CONFIG_KVM_HYPERV=y (KVM_CAP_HYPERV_TIME); libvirt errors with 'host doesn't support hyperv frequencies' otherwise.";
      };
      vendor_id = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Hyper-V vendor_id exposure. Libvirt-level setting with no KVM cap; always supported.";
      };
      vpindex = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Virtual processor index (HvVpIndex). Requires CONFIG_KVM_HYPERV=y in the host kernel. Enables libvirtError: 'host doesn't support hyperv vpindex' if requested on a kernel that does not advertise it.";
      };
      synic = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Synthetic interrupt controller (HvSynIC). Requires CONFIG_KVM_HYPERV=y.";
      };
      stimer = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Synthetic timers (HvSyntheticTimers) with direct mode. Requires CONFIG_KVM_HYPERV=y.";
      };
      reset = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Hyper-V reset hypercall. Requires CONFIG_KVM_HYPERV=y.";
      };
      ipi = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Hyper-V IPI hypercall. Requires CONFIG_KVM_HYPERV=y.";
      };
      tlbflush = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Hyper-V TLB flush hypercall. Requires CONFIG_KVM_HYPERV=y.";
      };
      reenlightenment = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "TSC re-enlightenment notification (HvReenlightenment). Requires CONFIG_KVM_HYPERV=y.";
      };
      runtime = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Hyper-V runtime (HvRuntime). Requires CONFIG_KVM_HYPERV=y.";
      };
    };

    kernelCapabilities = lib.mkOption {
      type = lib.types.nullOr (lib.types.attrsOf lib.types.bool);
      default = null;
      description = "Per-feature capability set of the host kernel, passed by the caller to lib.mkStealthFeatures, which drops every requested Hyper-V feature the set does not allow. null = assume all features supported. Set the attrset by hand after running zcat /proc/config.gz | grep KVM_HYPERV on the host, and name every hypervFeatures key: a key left out counts as unsupported. The parser in lib/kernel-capabilities.nix is not a flake output.";
    };

    stripVirtio = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "List the VirtIO balloon, RNG and tablet devices in domain.devicesToRemove, for the VM definition to leave out. This flake removes nothing from a domain itself.";
    };

    acpiSsdt = {
      spoofedDevices = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Include emulated ACPI device entries in the SSDT table. Covers ACPI namespace enumeration checks.";
      };
      fakeBattery = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Include an emulated ACPI battery device in the SSDT table. Covers the 'no battery = server/VM' heuristic.";
      };
      batterySerial = lib.mkOption {
        type = lib.types.strMatching "[A-Za-z0-9]{1,16}";
        default = seeded sharedIdentity."acpiSsdt.batterySerial" (seed: identity.digits seed "battery" 5);
        defaultText = lib.literalMD "five digits derived from identity.seed, or `\"41167\"` without one";
        description = "The serial number the emulated battery's _BIF reports. Populates WMI BatteryStaticData.SerialNumber. Goes into packages.acpiTables.";
      };
      sensorProbes = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Include CPU and VRM thermal zone probes (covers MSAcpi_ThermalZoneTemperature WMI checks).";
      };
    };

    pciMmio64Mb = lib.mkOption {
      type = lib.types.ints.unsigned;
      default = 65536;
      description = "Size of the OVMF 64-bit PCI MMIO window in megabytes. 65536 (64 GB) covers GPUs up to 64 GB VRAM. Set to 0 to omit the flag (OVMF uses its default, which may be too small for modern GPUs).";
    };

    edid = {
      manufacturer = lib.mkOption {
        type = lib.types.str;
        default = "ACI";
        description = "3-char EDID manufacturer code. Goes into packages.qemu.";
      };
      serial = lib.mkOption {
        type = lib.types.str;
        default = "VG248QE";
        description = "The monitor name in the EDID, the descriptor QEMU fills with \"QEMU Monitor\". The numeric serial is edid.serialNumber. Goes into packages.qemu.";
      };
      serialNumber = lib.mkOption {
        type = lib.types.ints.u32;
        default = seeded sharedIdentity."edid.serialNumber" (seed: identity.number seed "edid");
        defaultText = lib.literalMD "a number derived from identity.seed, or 0 without one";
        description = "The EDID ID Serial Number, bytes 12 to 15, as `edid-decode` shows it under Serial Number; QEMU writes 0. Windows reads it into WmiMonitorID.SerialNumberID. Goes into packages.qemu.";
      };
      productCode = lib.mkOption {
        type = lib.types.str;
        default = "0x2480";
        description = "EDID product code (hex). Goes into packages.qemu.";
      };
      dpi = lib.mkOption {
        type = lib.types.ints.between 1 1000;
        default = 91;
        description = "Monitor DPI. Goes into packages.qemu.";
      };
      week = lib.mkOption {
        type = lib.types.ints.between 1 54;
        default = 22;
        description = "EDID manufacture week. Goes into packages.qemu.";
      };
      year = lib.mkOption {
        type = lib.types.ints.between 1990 2245;
        default = 2020;
        description = "EDID manufacture year. Goes into packages.qemu.";
      };
      resolution = {
        width = lib.mkOption {
          type = lib.types.ints.between 1 4095;
          default = 1920;
          description = "Horizontal pixels of the EDID preferred mode, in place of QEMU's 1280, for a display device that sets no xres. Goes into packages.qemu.";
        };
        height = lib.mkOption {
          type = lib.types.ints.between 1 4095;
          default = 1080;
          description = "Vertical pixels of the EDID preferred mode, in place of QEMU's 800, for a display device that sets no yres. Goes into packages.qemu.";
        };
      };
    };

    disk = {
      model = lib.mkOption {
        type = lib.types.strMatching "^.{1,40}$";
        default = "WDC WD10EZEX-00WN4A0     ";
        description = "Disk model string, at most 40 characters. Populates Win32_DiskDrive.Model. Set to your real disk model. Goes into packages.qemu.";
      };
      serial = lib.mkOption {
        type = lib.types.str;
        default = seeded sharedIdentity."disk.serial" (
          seed:
          if lib.hasPrefix "WDC WD" cfg.disk.model then
            "WD-WCC${identity.hex seed "disk" 9}"
          else
            identity.hex seed "disk" 12
        );
        defaultText = lib.literalMD "derived from identity.seed: for a disk.model beginning WDC WD, WD-WCC and nine characters, the form Western Digital drives report; for another, twelve hex digits. `\"Default string\"` without a seed";
        description = "IDE/SCSI disk serial string, as `smartctl -i` shows it. Populates Win32_DiskDrive.SerialNumber; with another disk.model, set one in the form that model's maker uses. Goes into packages.qemu.";
      };
      opticalModel = lib.mkOption {
        type = lib.types.str;
        default = "HL-DT-ST DVDRAM GH24NSC0 ";
        description = "Emulated optical drive model: a vendor of at most 8 characters, a space, then a product of at most 16. The drive reports the whole string to ATA IDENTIFY and the two parts to SCSI INQUIRY, as a real drive does. Populates Win32_CDROMDrive.Name. Goes into packages.qemu.";
      };
      firmware = lib.mkOption {
        type = lib.types.strMatching "^[A-Za-z0-9._-]{1,8}$";
        default = "01.01A01";
        description = "Disk firmware revision, as `hdparm -I` or `smartctl -i` shows it for your real disk. Replaces QEMU's 2.5+ on SATA and SCSI disks. Goes into packages.qemu.";
      };
      opticalFirmware = lib.mkOption {
        type = lib.types.strMatching "^[A-Za-z0-9._-]{1,8}$";
        default = "LY00";
        description = "Optical drive firmware revision, as your real drive reports it. Replaces QEMU's 2.5+ on SATA and SCSI CD drives. Goes into packages.qemu.";
      };
    };

    acpiOem = {
      id = lib.mkOption {
        type = lib.types.strMatching "^[A-Za-z0-9 _.-]{6}$";
        default = "ALASKA";
        description = "6-char ACPI OEM ID (padded with spaces). Populates ACPI table header OEM ID field. Goes into packages.qemu and packages.acpiTables.";
      };
      tableId = lib.mkOption {
        type = lib.types.strMatching "^[A-Za-z0-9 _.-]{8}$";
        default = "A M I   ";
        description = "8-char ACPI OEM Table ID (padded with spaces). Populates ACPI table header OEM Table ID field. Goes into packages.qemu and packages.acpiTables.";
      };
    };

    acpi = {
      waet = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Give the guest the WAET ACPI table, which the AutoVirt patch removes. With it, Windows knows its RTC and ACPI PM timer are emulated and skips the workarounds it otherwise runs for them, which slow timer reads and can stall HAL init. Without it, the table that only virtual machines carry is gone, and VMAware's FIRMWARE check no longer finds it; that check also reads acpi.c2Latency and acpi.c3Latency. Goes into packages.qemu.";
      };
      c2Latency = lib.mkOption {
        type = lib.types.ints.u16;
        default = 101;
        description = "Worst-case C2 latency in microseconds the FADT reports (P_LVL2_LAT); above 100 means the CPU has no C2. The default 101 is what a desktop board with AMI firmware reports. VMAware's FIRMWARE check flags QEMU's own 0x0FFF. Goes into packages.qemu.";
      };
      c3Latency = lib.mkOption {
        type = lib.types.ints.u16;
        default = 1001;
        description = "Worst-case C3 latency in microseconds the FADT reports (P_LVL3_LAT); above 1000 means the CPU has no C3. The default 1001 is what a desktop board with AMI firmware reports. VMAware's FIRMWARE check flags QEMU's own 0x0FFF. Goes into packages.qemu.";
      };
    };

    cpuIdentity = {
      manufacturer = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "CPU manufacturer for SMBIOS type 4, as the Manufacturer line of `dmidecode -t 4` shows it. null takes the name smbios/processor-defaults.nix gives cpuVendor: Advanced Micro Devices, Inc. on amd, Intel(R) Corporation on intel.";
      };
      modelId = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "CPU model string reported to guest (e.g. 'AMD Ryzen 7 7800X3D 8-Core Processor'), in CPUID and as the SMBIOS type 4 Version. null keeps the host CPU's, which type 4 then names too.";
      };
      maxSpeed = lib.mkOption {
        type = lib.types.nullOr (lib.types.ints.between 1 65535);
        default = null;
        description = "CPU max speed in MHz for SMBIOS type 4, as the Max Speed line of `dmidecode -t 4` shows it. null leaves QEMU's 2000.";
      };
      currentSpeed = lib.mkOption {
        type = lib.types.nullOr (lib.types.ints.between 1 65535);
        default = null;
        description = "CPU current speed in MHz for SMBIOS type 4, as the Current Speed line of `dmidecode -t 4` shows it. null leaves QEMU's 2000.";
      };
      socket =
        processorOverride "socket" smbiosText
          "Socket Designation, as `dmidecode -t 4` shows it, in place of QEMU's CPU and an instance number. Populates WMI Win32_Processor.SocketDesignation";
      family =
        processorOverride "family" (lib.types.ints.between 1 65533)
          "Family number per DSP0134 7.5.2, such as 107 for Zen, 198 for Core i7, 205 for Core i5 and 207 for Core i9, in place of QEMU's 1, Other. Populates WMI Win32_Processor.Family";
      voltageDecivolts =
        processorOverride "voltageDecivolts" (lib.types.ints.between 1 127)
          "Voltage in tenths of a volt, 13 for the 1.3 V `dmidecode -t 4` shows, in place of QEMU's Unknown. Populates WMI Win32_Processor.CurrentVoltage";
      externalClock =
        processorOverride "externalClock" (lib.types.ints.between 1 65535)
          "External Clock in MHz, in place of QEMU's Unknown. Populates WMI Win32_Processor.ExtClock";
      upgrade =
        processorOverride "upgrade" (lib.types.ints.between 1 255)
          "Upgrade byte per DSP0134 7.5.5, the socket: 73 = Socket AM5, 49 = Socket AM4, 64 = Socket LGA1700, 85 = Socket LGA1851, in place of QEMU's 1, Other. Populates WMI Win32_Processor.UpgradeMethod";
      characteristics =
        processorOverride "characteristics" lib.types.ints.u16
          "Characteristics bit field per DSP0134 7.5.9; 252 is the 64-bit capable, Multi-Core, Hardware Thread, Execute Protection, Enhanced Virtualization and Power/Performance Control both boards report, in place of QEMU's Unknown. Populates WMI Win32_Processor.Characteristics";
    };

    devices = lib.mapAttrs (
      name: spec:
      if spec ? form then
        identityOption name spec identityDefaults.${name}
      else
        lib.mapAttrs (
          field: kind: identityOption "${name}.${field}" kind identityDefaults.${name}.${field}
        ) spec
    ) identitySchema;

    secureBoot.platformKeyName = lib.mkOption {
      type = lib.types.strMatching "^[^/]{1,64}$";
      default = "${cfg.smbios.manufacturer} PK";
      defaultText = lib.literalExpression "\"\${smbios.manufacturer} PK\"";
      description = "Subject name of the Secure Boot Platform Key in packages.secureBootVars, which a guest can read. Copy your board's own, as `mokutil --pk` prints it on the host. The key is generated at build time and its private half is not kept, so nothing can sign with it.";
    };

    tpm = {
      harden = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Turn on libvirt's swtpm and make it report a real TPM's identity: the EK and platform certificates (swtpm-localca.options) and the manufacturer and model (libtpms patch).";
      };
      manufacturer = lib.mkOption {
        type = lib.types.strMatching "^id:[0-9A-Fa-f]{8}$";
        default = "id:49465800";
        description = "TPM manufacturer ID, id: and 8 hex digits: the TCG vendor code in ASCII, such as id:49465800 (IFX, Infineon), id:414D4400 (AMD fTPM) or id:494E5443 (INTC, Intel PTT). The guest reads it as TPM2_PT_MANUFACTURER and in the EK certificate.";
      };
      model = lib.mkOption {
        type = lib.types.strMatching "^[a-zA-Z0-9 _-]{1,16}$";
        default = "SLB9672";
        description = "TPM model string. Common: SLB9672 (Infineon discrete), AMD (fTPM).";
      };
      firmwareVersion = lib.mkOption {
        type = lib.types.strMatching "^id:[0-9A-Fa-f]{8}$";
        default = "id:000F0018";
        description = "TPM firmware version, id: and 8 hex digits, such as id:000F0018 for firmware 15.24 of an Infineon SLB9672. The guest reads it as TPM2_PT_FIRMWARE_VERSION_1 and in the EK certificate.";
      };
      platformManufacturer = lib.mkOption {
        type = lib.types.strMatching "^[^\"]+$";
        default = cfg.smbios.manufacturer;
        defaultText = lib.literalExpression "smbios.manufacturer";
        description = "Platform manufacturer in the TPM platform certificate.";
      };
      platformModel = lib.mkOption {
        type = lib.types.strMatching "^[^\"]+$";
        default = cfg.smbios.product;
        defaultText = lib.literalExpression "smbios.product";
        description = "Platform model in the TPM platform certificate.";
      };
    };

    tools.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Install the commands the setup reads this machine with: vfio-stealth-gpus, which lists each GPU with its IOMMU group and prints its gpu settings, and lspci, lsusb, dmidecode, smartctl, lsscsi, edid-decode, tpm2_getcap and mokutil. Turn it off once the identity and the VMs are set.";
    };

    user = lib.mkOption {
      type = lib.types.nullOr (lib.types.passwdEntry lib.types.str);
      default = null;
      example = "alice";
      description = "The user who runs the Looking Glass client. With kvmfr.enable, /dev/kvmfr0 belongs to this user, so the client opens it without root. A VM's sound plays through this user's PipeWire.";
    };

    pipewireRuntimeDir = lib.mkOption {
      type = lib.types.nullOr (lib.types.strMatching "/[^ ]*");
      default =
        if
          cfg.user != null && config.users.users ? ${cfg.user} && config.users.users.${cfg.user}.uid != null
        then
          "/run/user/${toString config.users.users.${cfg.user}.uid}"
        else
          null;
      defaultText = lib.literalMD "`/run/user/` and the uid of user, when users.users.<user>.uid is set";
      description = "The runtime directory holding the PipeWire socket that a VM's domains.<name>.sound plays and records through: the XDG_RUNTIME_DIR of the user whose desktop session runs PipeWire.";
    };

    host = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Prepare this host to pass PCI devices to the VMs in domains: load vfio, vfio_iommu_type1 and vfio_pci, keep vfio-pci devices out of idle D3, load vfio-pci before snd_hda_intel so a GPU's audio function is free to bind, let libvirt-guests start no guest at boot, disable the sleep targets, which a passed-through device does not survive, and install the libvirt QEMU hook that does what the domains' gpu, hugepages, unmount and pinning ask at start and stop. hugepages, kvmfr, lookingGlass.client, evdev, pinning.isolate, acsOverride, disableAspm, a changed protectedDisks and a domain's hook or boot GPU binding, hugepages and unmount need it.";
      };
      acsOverride = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        example = "downstream,multifunction";
        description = "Value of the pcie_acs_override= kernel parameter, which splits IOMMU groups the chipset bundles. Only kernels carrying the ACS override patch read it; mainline ignores it. It fakes isolation: a passed-through device can still reach the other devices of its real group by DMA, past the IOMMU. null leaves the parameter out.";
      };
      disableAspm = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Pass pcie_aspm=off, which keeps every PCIe link out of its power-saving states. Some GPUs and boards lose a passed-through device's link, or fail to reset it, when ASPM moves it between states; the cost is host power draw.";
      };
      protectedDisks = lib.mkOption {
        type = lib.types.listOf lib.types.externalPath;
        default = [
          "/"
          "/boot"
          "/nix/store"
          "/home"
        ];
        description = "Paths whose disks a VM must never take. Before a VM starts, the hook resolves each path to the block devices beneath the filesystem that holds it, through device mapper and LVM, adds every active swap device, and refuses to start a VM that passes through a PCI device any of them sits on. A path whose device it cannot resolve, such as one on ZFS, refuses every VM that passes a PCI device; an empty list turns the check off for everything but swap.";
      };
    };

    hugepages = {
      size = lib.mkOption {
        type = lib.types.enum [
          "2M"
          "1G"
        ];
        default = "2M";
        description = "The huge page size of a domain with hugepages. 1G pages cost fewer TLB misses, but after the host has run a while it seldom finds whole free gigabytes, so 1G usually needs atBoot.";
      };
      count = lib.mkOption {
        type = lib.types.nullOr lib.types.ints.positive;
        default = null;
        description = "Pages reserved at boot with atBoot. null reserves the sum of the memory of every domain with hugepages, enough for all of them at once. Unused without atBoot, where each domain allocates its own.";
      };
      atBoot = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Reserve the pages on the kernel command line, before memory fragments. Without it the hook adds a domain's pages to the pool before the domain starts and takes them back after it stops, and refuses the start when the kernel cannot find them.";
      };
    };

    kvmfr = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Load the kvmfr module, which gives Looking Glass its shared memory as /dev/kvmfr0, owned by user. A domain with lookingGlass then gets an ivshmem device backed by it.";
      };
      sizeMb = lib.mkOption {
        type = lib.types.nullOr powerOfTwo;
        default = null;
        example = 64;
        description = "Size of /dev/kvmfr0 in MiB: 32 holds a 1440p SDR frame, 64 a 4K SDR frame, 128 a 4K HDR frame.";
      };
    };

    lookingGlass = {
      client = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Install looking-glass-client, which shows a guest's screen from the shared memory a domain with lookingGlass writes.";
      };
      shmemSizeMb = lib.mkOption {
        type = lib.types.nullOr powerOfTwo;
        default = null;
        example = 64;
        description = "Size in MiB of the shared memory file /dev/shm/looking-glass that a domain with lookingGlass gets when kvmfr.enable is off; sized as kvmfr.sizeMb.";
      };
    };

    evdev = {
      keyboard = lib.mkOption {
        type = lib.types.nullOr lib.types.externalPath;
        default = null;
        example = "/dev/input/by-id/usb-Example_Keyboard-event-kbd";
        description = "The keyboard every VM in domains takes over through QEMU's input-linux, switched between host and guest with the keys grabToggle names. Use its /dev/input/by-id path, which survives a replug.";
      };
      grabToggle = lib.mkOption {
        type = lib.types.enum [
          "ctrl-ctrl"
          "alt-alt"
          "shift-shift"
          "meta-meta"
          "scrolllock"
          "ctrl-scrolllock"
        ];
        default = "ctrl-ctrl";
        description = "The keys that switch the keyboard and mouse between host and guest: both Ctrl keys, both Alt keys, both Shift keys, both Meta keys, Scroll Lock, or Ctrl and Scroll Lock. Pick a pair the guest's own shortcuts do not use.";
      };
      extraKeyboards = lib.mkOption {
        type = lib.types.listOf lib.types.externalPath;
        default = [ ];
        description = "More keyboard event devices passed the same way, such as the other interfaces of a keyboard that shows several.";
      };
      mouse = lib.mkOption {
        type = lib.types.nullOr lib.types.externalPath;
        default = null;
        example = "/dev/input/by-id/usb-Example_Mouse-event-mouse";
        description = "The mouse every VM in domains takes over through input-linux, following the keyboard.";
      };
    };

    pinning.isolate = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "While a domain with pinning runs, confine the host's system.slice, user.slice and init.scope to the online CPUs its vCPUs do not use, and give them back when it stops; the emulator and I/O threads share the host's CPUs. The hook reads the online CPUs from sysfs. One pinned domain runs at a time: the hook refuses a second while the first holds the CPUs. Do not combine it with isolcpus.";
    };
  };

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      {
        warnings =
          lib.optional (cfg.smbios.manufacturer == "To Be Filled By O.E.M.")
            "vfio-stealth: smbios.manufacturer is the default placeholder; set it to your real board manufacturer from dmidecode"
          ++
            lib.optional (cfg.smbios.product == "To Be Filled By O.E.M.")
              "vfio-stealth: smbios.product is the default placeholder; set it to your real board model from dmidecode"
          ++
            lib.optional (unsetCaches != [ ])
              "vfio-stealth: ${
                lib.concatMapStringsSep ", " (level: "smbios.cache.${level}") unsetCaches
              } left unset, so SMBIOS type 7 reports an eight core Zen 4's caches while CPUID passes this host's through; set them to the sizes `dmidecode -t 7` shows"
          ++
            lib.optional (sharedValues != [ ])
              "vfio-stealth: ${lib.concatStringsSep ", " sharedValues} still hold the values every host without identity.seed shares; set identity.seed to a private string unique to this host, or set each"
          ++
            lib.optional (cfg.smbios.memory.manufacturer == "Unknown")
              "vfio-stealth: smbios.memory.manufacturer is 'Unknown'; set it to your real DIMM vendor from dmidecode -t 17"
          ++
            lib.optional (cfg.smbios.onboardDevices == [ ])
              "vfio-stealth: smbios.onboardDevices is empty (no SMBIOS Type 41); set it to match your board from dmidecode -t 41"
          ++
            lib.optional
              (
                cfg.kernelCapabilities == null
                && (
                  cfg.hypervFeatures.vpindex
                  || cfg.hypervFeatures.synic
                  || cfg.hypervFeatures.stimer
                  || cfg.hypervFeatures.reset
                  || cfg.hypervFeatures.ipi
                  || cfg.hypervFeatures.tlbflush
                  || cfg.hypervFeatures.reenlightenment
                  || cfg.hypervFeatures.runtime
                )
              )
              "vfio-stealth: kernel-dependent hypervFeatures.* are enabled while kernelCapabilities is null, so a kernel lacking them fails at VM start; see docs/DESIGN.md, Kernel-dependent Hyper-V features default off"
          ++
            lib.optional
              (
                cfg.kernelPostPatch != ""
                && (
                  let
                    postPatch = toString (config.boot.kernelPackages.kernel.postPatch or "");
                  in
                  builtins.replaceStrings [ cfg.kernelPostPatch ] [ "" ] postPatch == postPatch
                )
              )
              "vfio-stealth: ${
                lib.concatStringsSep ", " (
                  lib.optional cfg.timing.enable "timing.enable"
                  ++ lib.optional cfg.cpuidSpoof.enable "cpuidSpoof.enable"
                  ++ lib.optional cfg.cpuidPassthrough.enable "cpuidPassthrough.enable"
                  ++ lib.optional cfg.cpuidPassthrough.pinned "cpuidPassthrough.pinned"
                  ++ lib.optional cfg.instructionFixes.enable "instructionFixes.enable"
                )
              } patch the host kernel, but boot.kernelPackages.kernel does not carry kernelPostPatch, so they do nothing; build it with packages.kernelFor, or turn them off"
          ++ cfg.domain.warnings;

        assertions = [
          {
            assertion = pkgs.stdenv.hostPlatform.isx86_64;
            message = "virtualisation.vfio-stealth: x86_64-only; this host is ${pkgs.stdenv.hostPlatform.system}";
          }
          {
            assertion = cfg.cpuVendor != null;
            message = "virtualisation.vfio-stealth.cpuVendor: must be \"amd\" or \"intel\"; it picks the QEMU and OVMF pair and the kernel patches";
          }
          {
            assertion = !(cfg.cpuidPassthrough.enable && cfg.hypervMode == "enlightened");
            message = "virtualisation.vfio-stealth: cpuidPassthrough.enable hides Hyper-V enlightenments from the guest; set hypervMode to \"hidden\"";
          }
        ]
        ++ map (message: {
          assertion = false;
          inherit message;
        }) kernelPatch.refusals
        ++ (
          let
            needHost =
              lib.optional cfg.kvmfr.enable "kvmfr.enable"
              ++ lib.optional cfg.lookingGlass.client "lookingGlass.client"
              ++ lib.optional (evdevPaths != [ ]) "evdev"
              ++ lib.optional cfg.pinning.isolate "pinning.isolate"
              ++ lib.optional cfg.hugepages.atBoot "hugepages.atBoot"
              ++ lib.optional (cfg.host.acsOverride != null) "host.acsOverride"
              ++ lib.optional cfg.host.disableAspm "host.disableAspm"
              ++ lib.optional (
                cfg.host.protectedDisks != options.virtualisation.vfio-stealth.host.protectedDisks.default
              ) "host.protectedDisks"
              ++ lib.concatLists (
                lib.mapAttrsToList (
                  name: domain:
                  lib.optional (
                    domain.gpu != null && domain.gpu.binding != "libvirt"
                  ) "domains.${name}.gpu.binding = \"${domain.gpu.binding}\""
                  ++ lib.optional domain.hugepages "domains.${name}.hugepages"
                  ++ lib.optional (domain.unmount != [ ]) "domains.${name}.unmount"
                  ++ lib.optional (domain.stopServices != [ ]) "domains.${name}.stopServices"
                ) cfg.domains
              );
            pinned = lib.filterAttrs (_: domain: domain.pinning != null) cfg.domains;
            allPins = lib.concatMap (domain: domain.pinning.vcpus) (lib.attrValues pinned);
          in
          [
            {
              assertion = !cfg.host.enable || config.virtualisation.libvirtd.enable;
              message = "virtualisation.vfio-stealth.host.enable: the qemu hook and the device ACL live in libvirtd, so set virtualisation.libvirtd.enable = true";
            }
            {
              assertion =
                soundVms == [ ]
                || (cfg.pipewireRuntimeDir != null && config.virtualisation.libvirtd.qemu.runAsRoot);
              message = "virtualisation.vfio-stealth.domains: ${lib.concatStringsSep ", " soundVms} play sound through PipeWire, so QEMU needs its socket: set user with a fixed users.users.<user>.uid, or pipewireRuntimeDir, and virtualisation.libvirtd.qemu.runAsRoot = true, since the socket belongs to that user";
            }
            {
              assertion = evdevPaths == [ ] || config.virtualisation.libvirtd.qemu.runAsRoot;
              message = "virtualisation.vfio-stealth.evdev: QEMU opens the input devices itself through input-linux, which libvirt does not relabel, so it needs virtualisation.libvirtd.qemu.runAsRoot = true";
            }
            {
              assertion = cfg.host.enable || needHost == [ ];
              message = "virtualisation.vfio-stealth: host.enable is off, and these settings act on the host through it: ${lib.concatStringsSep ", " needHost}";
            }
            {
              assertion = !cfg.kvmfr.enable || (cfg.kvmfr.sizeMb != null && cfg.user != null);
              message = "virtualisation.vfio-stealth.kvmfr: the device needs sizeMb for its size and user for its owner, the user who runs the Looking Glass client";
            }
            {
              assertion = cfg.hugepages.count == null || cfg.hugepages.atBoot;
              message = "virtualisation.vfio-stealth.hugepages.count: only atBoot reserves a pool of that size; without it each domain allocates its own memory's pages, so count would be ignored";
            }
            {
              assertion = cfg.pinning.isolate || lib.length allPins == lib.length (lib.unique allPins);
              message = "virtualisation.vfio-stealth.domains: two domains pin vCPUs to the same host CPU, and nothing stops them running at once; give them disjoint CPUs, or set pinning.isolate, which runs one pinned domain at a time";
            }
            {
              assertion = memoryModules >= 1;
              message = "virtualisation.vfio-stealth.smbios.memory.slots: no slot is populated, so the VM's memory sits in no module; set populated on the slots that hold it";
            }
            {
              assertion =
                let
                  places = map (slot: "${slot.locator}/${slot.bank}") cfg.smbios.memory.slots;
                in
                lib.length places == lib.length (lib.unique places);
              message = "virtualisation.vfio-stealth.smbios.memory.slots: two slots share a locator and bank, which no board reports; give each slot its own pair";
            }
          ]
          ++ lib.concatLists (
            lib.mapAttrsToList (
              name: domain:
              let
                at = "virtualisation.vfio-stealth.domains.${name}";
                pci = plan.domains.${name}.devices;
              in
              [
                {
                  assertion = lib.length pci == lib.length (lib.unique pci);
                  message = "${at}: a PCI address appears twice among gpu and hostDevices; list each function once";
                }
                {
                  assertion =
                    domain.gpu == null
                    || (
                      let
                        functions = [
                          domain.gpu.address
                        ]
                        ++ lib.optional (domain.gpu.audio != null) domain.gpu.audio
                        ++ domain.gpu.extraFunctions;
                        slotOf = address: lib.head (lib.splitString "." (lib.toLower address));
                      in
                      lib.hasSuffix ".0" domain.gpu.address
                      && lib.all (address: slotOf address == slotOf domain.gpu.address) functions
                    );
                  message = "${at}.gpu: the GPU goes into the guest as one card in one slot, so address must be function 0 and audio and extraFunctions functions of that same slot; pass a device of another slot through hostDevices";
                }
                {
                  assertion = !(lib.elem "-cpu" domain.extraQemuArgs);
                  message = "${at}.extraQemuArgs: -cpu replaces the -cpu line libvirt writes from the domain's CPU block and drops its Hyper-V settings and the hidden KVM signature; set CPU properties with -global x86_64-cpu.<property>";
                }
                {
                  assertion = !domain.hugepages || lib.mod domain.memory pageMib == 0;
                  message = "${at}.memory: ${toString domain.memory} MiB is not a whole number of ${cfg.hugepages.size} huge pages";
                }
                {
                  assertion =
                    !domain.lookingGlass
                    || (if cfg.kvmfr.enable then cfg.kvmfr.sizeMb != null else cfg.lookingGlass.shmemSizeMb != null);
                  message = "${at}.lookingGlass: the shared memory has no size; set kvmfr.enable with kvmfr.sizeMb, or lookingGlass.shmemSizeMb";
                }
                {
                  assertion = memoryModules < 1 || lib.mod domain.memory memoryModules == 0;
                  message = "${at}.memory: ${toString domain.memory} MiB does not split evenly over the ${toString memoryModules} populated slots of smbios.memory.slots, and a board's modules are one size";
                }
                {
                  assertion = memoryModules < 1 || domain.memory <= memoryModules * slotMib;
                  message = "${at}.memory: ${toString domain.memory} MiB needs more than the ${toString memoryModules} populated slots of smbios.memory.slots hold, ${toString slotMib} MiB each on a ${toString cfg.smbios.memory.maxCapacityGb} GB board of ${toString (lib.length cfg.smbios.memory.slots)} slots; populate more slots or raise smbios.memory.maxCapacityGb";
                }
              ]
              ++ lib.optionals (domain.pinning != null) (
                let
                  inherit (domain.pinning) vcpus emulator iothread;
                  count = domain.cores * domain.threads;
                in
                [
                  {
                    assertion = lib.length vcpus == count;
                    message = "${at}.pinning.vcpus: names ${toString (lib.length vcpus)} host CPUs for ${toString count} vCPUs (cores times threads); give one per vCPU";
                  }
                  {
                    assertion = lib.length vcpus == lib.length (lib.unique vcpus);
                    message = "${at}.pinning.vcpus: pins two vCPUs to one host CPU, where they would take turns";
                  }
                  {
                    assertion = lib.intersectLists (cpusOf emulator) vcpus == [ ];
                    message = "${at}.pinning.emulator: ${emulator} shares host CPUs with the vCPUs, so QEMU's own work stalls the guest; use CPUs outside pinning.vcpus";
                  }
                  {
                    assertion = iothread == null || lib.intersectLists (cpusOf iothread) vcpus == [ ];
                    message = "${at}.pinning.iothread: ${toString iothread} shares host CPUs with the vCPUs; use CPUs outside pinning.vcpus";
                  }
                ]
              )
              ++ lib.optionals (domain.gpu != null) (
                let
                  inherit (domain.gpu) binding ids;
                in
                [
                  {
                    assertion = (binding == "boot") == (ids != [ ]);
                    message =
                      if binding == "boot" then
                        "${at}.gpu.ids: binding \"boot\" captures the GPU at boot by its vendor:device ids, so list them, as lspci -nn shows them"
                      else
                        "${at}.gpu.ids: only binding \"boot\" reads ids; with \"${binding}\" the GPU is bound by its address";
                  }
                  {
                    assertion = binding == "hook" || (domain.gpu.resizeBar2Mb == null && !domain.gpu.rebindOnStop);
                    message = "${at}.gpu: resizeBar2Mb and rebindOnStop act between the host driver's unbind and the vfio-pci bind, which only binding \"hook\" performs";
                  }
                ]
              )
            ) cfg.domains
          )
        );

        boot.kernelParams = [
          "processor.max_cstate=${toString cfg.kernelParams.maxCState}"
          "kvm.ignore_msrs=1"
          "kvm.report_ignored_msrs=0"
        ]
        ++ lib.optionals (cfg.cpuVendor == "amd") [
          "kvm_amd.vls=0"
          "kvm_amd.vgif=0"
        ]
        ++ lib.optionals cfg.kernelParams.tscReliable [ "tsc=reliable" ];

        virtualisation.libvirtd.qemu.package = lib.mkDefault cfg.packages.libvirtQemu;

        environment.systemPackages = [
          (pkgs.writeShellApplication {
            name = "vfio-stealth-verify-host";
            runtimeInputs = [
              pkgs.libvirt
              pkgs.binutils
              pkgs.procps
              pkgs.gawk
              pkgs.gnugrep
              pkgs.gnused
              pkgs.findutils
              pkgs.coreutils
            ];
            text = builtins.readFile ./guest/verify-host.sh;
          })
        ];

        virtualisation.libvirt = lib.mkIf (cfg.domains != { }) {
          enable = true;
          connections."qemu:///system".domains = lib.mapAttrsToList (_: domain: {
            definition = domain.xml;
            inherit (domain) active;
          }) cfg.domains;
        };

        virtualisation.libvirtd.qemu.swtpm.enable = lib.mkIf cfg.tpm.harden (lib.mkDefault true);

        virtualisation.libvirtd.qemu.swtpm.package = lib.mkIf cfg.tpm.harden (
          lib.mkDefault (
            (pkgs.swtpm.override {
              libtpms = pkgs.libtpms.overrideAttrs (old: {
                postPatch = (old.postPatch or "") + cfg.libtpmsIdentityPatch;
              });
            }).overrideAttrs
              (old: {
                postPatch = (old.postPatch or "") + ''
                  substituteInPlace src/swtpm_localca/swtpm_localca.c \
                    --replace-fail 'split = g_strsplit(chomped, " ", -1);' 'if (!g_shell_parse_argv(chomped, NULL, &split, NULL)) { logerr(gl_LOGFILE, "Cannot parse the options line: %s\n", chomped); return 1; }'
                  substituteInPlace tests/test_tpm2_swtpm_setup_create_cert \
                    --replace-fail 's/.*\(IBM[[:print:]]*\)/\1/p' 's/.*\(${
                      lib.concatMapStrings (
                        i:
                        let
                          byte = builtins.substring (3 + i * 2) 2 cfg.tpm.manufacturer;
                        in
                        lib.optionalString (byte != "00") (builtins.fromJSON "\"\\u00${byte}\"")
                      ) (lib.range 0 3)
                    }[[:print:]]*\)/\1/p'
                '';
                postInstall = (old.postInstall or "") + ''
                  cp ${
                    pkgs.writeText "swtpm-localca.options" (
                      lib.concatMapStrings (line: line + "\n") [
                        "--platform-manufacturer \"${cfg.tpm.platformManufacturer}\""
                        "--platform-model \"${cfg.tpm.platformModel}\""
                        "--platform-version \"1.0\""
                        "--tpm-manufacturer \"${cfg.tpm.manufacturer}\""
                        "--tpm-model \"${cfg.tpm.model}\""
                        "--tpm-version \"${cfg.tpm.firmwareVersion}\""
                      ]
                    )
                  } $out/etc/swtpm-localca.options
                '';
              })
          )
        );

        services.udev.extraRules =
          lib.mkIf (lib.any (domain: domain.usb != [ ]) (lib.attrValues cfg.domains))
            (
              lib.concatStrings (
                lib.concatLists (
                  lib.mapAttrsToList (
                    name: domain:
                    map (
                      device:
                      let
                        hex = n: lib.fixedWidthString 4 "0" (lib.toLower (lib.toHexString n));
                        vendor = hex device.vendor;
                        product = hex device.product;
                      in
                      ''
                        ACTION=="add", SUBSYSTEM=="usb", ENV{DEVTYPE}=="usb_device", ATTR{idVendor}=="${vendor}", ATTR{idProduct}=="${product}", RUN+="${pkgs.systemd}/bin/systemd-run --no-block --collect ${lib.getExe usbReattach} ${name} ${vendor} ${product}"
                      ''
                    ) domain.usb
                  ) cfg.domains
                )
              )
            );
      }

      (lib.mkIf cfg.tools.enable {
        environment.systemPackages = [
          (pkgs.callPackage ./host/gpus.nix { })
          pkgs.pciutils
          pkgs.usbutils
          pkgs.dmidecode
          pkgs.smartmontools
          pkgs.lsscsi
          pkgs.edid-decode
          pkgs.tpm2-tools
          pkgs.mokutil
        ];
      })

      (lib.mkIf cfg.host.enable {
        boot.kernelModules = [
          "vfio"
          "vfio_iommu_type1"
          "vfio_pci"
        ]
        ++ lib.optional cfg.kvmfr.enable "kvmfr";

        boot.extraModprobeConfig = ''
          options vfio-pci disable_idle_d3=1
          softdep snd_hda_intel pre: vfio-pci
        ''
        + lib.concatMapStrings (driver: "softdep ${driver} pre: vfio-pci\n") bootGpuDrivers
        + lib.optionalString cfg.kvmfr.enable ''
          options kvmfr static_size_mb=${toString cfg.kvmfr.sizeMb}
        '';

        boot.kernelParams =
          lib.optional cfg.host.disableAspm "pcie_aspm=off"
          ++ lib.optional (cfg.host.acsOverride != null) "pcie_acs_override=${cfg.host.acsOverride}"
          ++ lib.optional (bootIds != [ ]) "vfio-pci.ids=${lib.concatStringsSep "," bootIds}"
          ++ lib.optionals cfg.hugepages.atBoot [
            "hugepagesz=${cfg.hugepages.size}"
            "hugepages=${
              toString (
                if cfg.hugepages.count != null then
                  cfg.hugepages.count
                else
                  lib.foldl' (sum: domain: sum + domain.memory / pageMib) 0 (lib.attrValues hugepageDomains)
              )
            }"
          ];

        boot.initrd.kernelModules = lib.mkIf (bootIds != [ ]) [
          "vfio_pci"
          "vfio"
          "vfio_iommu_type1"
        ];

        boot.extraModulePackages = lib.mkIf cfg.kvmfr.enable [ config.boot.kernelPackages.kvmfr ];

        services.udev.extraRules =
          lib.optionalString cfg.kvmfr.enable ''
            SUBSYSTEM=="kvmfr", OWNER="${cfg.user}", GROUP="kvm", MODE="0660"
          ''
          + lib.optionalString (evdevPaths != [ ]) ''
            SUBSYSTEM=="misc", KERNEL=="uinput", MODE="0660", GROUP="input"
          '';

        systemd.targets =
          lib.genAttrs
            [
              "sleep"
              "suspend"
              "hibernate"
              "hybrid-sleep"
              "suspend-then-hibernate"
            ]
            (_: {
              enable = false;
            });

        services.logind.settings.Login = {
          IdleAction = lib.mkDefault "ignore";
          HandleSuspendKey = lib.mkDefault "ignore";
          HandleHibernateKey = lib.mkDefault "ignore";
        };

        virtualisation.libvirtd.onBoot = lib.mkDefault "ignore";

        virtualisation.libvirtd.qemu.verbatimConfig = lib.mkIf (cfg.kvmfr.enable || evdevPaths != [ ]) (
          (options.virtualisation.libvirtd.qemu.type.getSubOptions [ ]).verbatimConfig.default
          + ''
            cgroup_device_acl = [
              ${lib.concatMapStringsSep ",\n  " builtins.toJSON (
                [
                  "/dev/null"
                  "/dev/full"
                  "/dev/zero"
                  "/dev/random"
                  "/dev/urandom"
                  "/dev/ptmx"
                  "/dev/userfaultfd"
                ]
                ++ lib.optional cfg.kvmfr.enable "/dev/kvmfr0"
                ++ evdevPaths
              )}
            ]
          ''
        );

        virtualisation.libvirtd.hooks.qemu = lib.mkIf (cfg.domains != { }) {
          vfio-stealth = lib.getExe hook;
        };

        environment.systemPackages = lib.optional cfg.lookingGlass.client pkgs.looking-glass-client;
      })
    ]
  );

  options.virtualisation.vfio-stealth.libtpmsIdentityPatch = lib.mkOption {
    type = lib.types.str;
    readOnly = true;
    default =
      let
        bytes = hex: lib.concatMapStrings (i: "\\x${builtins.substring (i * 2) 2 hex}") (lib.range 0 3);
        hexOf =
          s: lib.concatMapStrings (c: lib.toHexString (lib.strings.charToInt c)) (lib.stringToCharacters s);
        model =
          hexOf cfg.tpm.model
          + lib.concatStrings (lib.replicate (16 - builtins.stringLength cfg.tpm.model) "00");
        vendor = i: bytes (builtins.substring (i * 8) 8 model);
        manufacturer = builtins.substring 3 8 cfg.tpm.manufacturer;
        firmware = builtins.substring 3 8 cfg.tpm.firmwareVersion;
        file = "src/tpm2/TPMCmd/Platform/src/VendorInfo.c";
      in
      lib.optionalString (cfg.enable && cfg.tpm.harden) ''
        ${patchAssertions}
        substituteInPlace ${file} \
          --replace-fail '#define MANUFACTURER    "IBM"' '#define MANUFACTURER    "${bytes manufacturer}"' \
          --replace-fail '#define VENDOR_STRING_1 "SW  "' '#define VENDOR_STRING_1 "${vendor 0}"' \
          --replace-fail '#define VENDOR_STRING_2 " TPM"' '#define VENDOR_STRING_2 "${vendor 1}"' \
          --replace-fail '#define VENDOR_STRING_3 "\0\0\0\0"' '#define VENDOR_STRING_3 "${vendor 2}"' \
          --replace-fail '#define VENDOR_STRING_4 "\0\0\0\0"' '#define VENDOR_STRING_4 "${vendor 3}"'
        sed -i 's/^#define FIRMWARE_V1 .*/#define FIRMWARE_V1     (0x${firmware})/; s/^#define FIRMWARE_V2 .*/#define FIRMWARE_V2     (0x00000000)/' ${file}
        landed ${file} '#define MANUFACTURER    "${bytes manufacturer}"' "TPM manufacturer set to ${cfg.tpm.manufacturer}"
        landed ${file} '#define FIRMWARE_V1     (0x${firmware})' "TPM firmware version set to ${cfg.tpm.firmwareVersion}"
        gone ${file} '"IBM"' "no IBM manufacturer left in the TPM vendor info"
        substituteInPlace src/tpm_tpm2_interface.c \
          --replace-fail '\"manufacturer\":\"id:00001014\"' '\"manufacturer\":\"${cfg.tpm.manufacturer}\"' \
          --replace-fail '\"model\":\"swtpm\"' '\"model\":\"${cfg.tpm.model}\"'
        landed src/tpm_tpm2_interface.c '\"manufacturer\":\"${cfg.tpm.manufacturer}\"' "swtpm_setup sees the TPM manufacturer"
        landed src/tpm_tpm2_interface.c '\"model\":\"${cfg.tpm.model}\"' "swtpm_setup sees the TPM model"
      '';
    description = "libtpms postPatch script that gives the emulated TPM the identity of tpm.manufacturer, tpm.model and tpm.firmwareVersion: what a guest reads as TPM2_PT_MANUFACTURER, the vendor strings and the firmware version, and what swtpm_setup writes into the EK certificate. With tpm.harden the module builds libvirt's swtpm with it.";
  };

  options.virtualisation.vfio-stealth.kernelPostPatch = lib.mkOption {
    type = lib.types.str;
    readOnly = true;
    default = kernelPatch.script;
    description = "Combined kernel postPatch script. packages.kernelFor appends it to a kernel package.";
  };

  options.virtualisation.vfio-stealth.packages = lib.mkOption {
    type = lib.types.lazyAttrsOf (
      lib.types.either lib.types.package (lib.types.functionTo lib.types.package)
    );
    readOnly = true;
    default =
      let
        autovirt = ./vendor/autovirt;
        qemu = pkgs.callPackage ./qemu/package.nix {
          inherit autovirt patchAssertions;
          inherit (cfg) cpuVendor;
          edidManufacturer = cfg.edid.manufacturer;
          edidSerial = cfg.edid.serial;
          edidProductCode = cfg.edid.productCode;
          edidDpi = cfg.edid.dpi;
          edidWeek = cfg.edid.week;
          edidYear = cfg.edid.year;
          edidResX = cfg.edid.resolution.width;
          edidResY = cfg.edid.resolution.height;
          acpiOemId = cfg.acpiOem.id;
          acpiOemTableId = cfg.acpiOem.tableId;
          diskModel = cfg.disk.model;
          diskSerial = cfg.disk.serial;
          edidSerialNumber = cfg.edid.serialNumber;
          inherit (cfg.disk) opticalModel opticalFirmware;
          inherit (cfg) pciSubsystem hdaCodec;
          diskFirmware = cfg.disk.firmware;
          smbiosChassisType = cfg.smbios.chassisType;
          smbiosMemoryErrorCorrection = cfg.smbios.memory.errorCorrection;
          smbiosMemoryMaxCapacityGb = cfg.smbios.memory.maxCapacityGb;
          smbiosMemorySlots = identity.memorySlots cfg.identity.seed cfg.smbios.memory.slots;
          smbiosMemoryType = cfg.smbios.memory.type;
          smbiosMemoryTypeDetail = cfg.smbios.memory.typeDetail;
          smbiosMemoryRank = cfg.smbios.memory.rank;
          smbiosMemoryVoltageMillivolts = cfg.smbios.memory.voltageMillivolts;
          deviceIdentities = cfg.devices;
          acpiWaet = cfg.acpi.waet;
          fadtC2Latency = cfg.acpi.c2Latency;
          fadtC3Latency = cfg.acpi.c3Latency;
        };
        ovmf = pkgs.callPackage ./ovmf/package.nix {
          inherit autovirt patchAssertions;
          inherit (cfg) cpuVendor;
          firmwareVendor = cfg.smbios.biosVendor;
          acpiOemId = cfg.acpiOem.id;
          acpiOemTableId = cfg.acpiOem.tableId;
        };
      in
      {
        inherit qemu ovmf;
        kernelFor =
          kernel:
          kernel.overrideAttrs (old: {
            postPatch = (old.postPatch or "") + cfg.kernelPostPatch;
          });
        libvirtQemu =
          let
            descriptor =
              name: vars: features:
              pkgs.writeText name (
                builtins.toJSON {
                  description = "OVMF-stealth, ${name}";
                  interface-types = [ "uefi" ];
                  mapping = {
                    device = "flash";
                    mode = "split";
                    executable = {
                      filename = "@out@/share/qemu/OVMF_CODE.fd";
                      format = "raw";
                    };
                    nvram-template = {
                      filename = "@out@/share/qemu/${vars}";
                      format = "raw";
                    };
                  };
                  targets = [
                    {
                      architecture = "x86_64";
                      machines = [ "pc-q35-*" ];
                    }
                  ];
                  features = [
                    "acpi-s3"
                    "requires-smm"
                    "secure-boot"
                    "verbose-dynamic"
                  ]
                  ++ features;
                  tags = [ ];
                }
              );
          in
          pkgs.runCommand "${qemu.name}-libvirt" { passthru = { inherit (qemu) version; }; } ''
            cp -rs ${qemu}/. $out
            chmod -R u+w $out/share/qemu
            mkdir -p $out/share/qemu/firmware
            rm -f $out/share/qemu/firmware/*.json
            ln -s ${ovmf.fd}/FV/OVMF_CODE.fd $out/share/qemu/OVMF_CODE.fd
            ln -s ${ovmf.fd}/FV/OVMF_VARS.fd $out/share/qemu/OVMF_VARS.fd
            ln -s ${cfg.packages.secureBootVars} $out/share/qemu/OVMF_VARS.ms.fd
            substitute ${
              descriptor "Secure Boot with the Microsoft keys" "OVMF_VARS.ms.fd" [ "enrolled-keys" ]
            } \
              $out/share/qemu/firmware/40-ovmf-stealth-secure-boot-enrolled.json --subst-var out
            substitute ${descriptor "Secure Boot without keys" "OVMF_VARS.fd" [ ]} \
              $out/share/qemu/firmware/50-ovmf-stealth-secure-boot.json --subst-var out
          '';
        secureBootVars =
          pkgs.runCommand "secure-boot-vars.fd"
            {
              nativeBuildInputs = [
                pkgs.openssl
                pkgs.python3Packages.virt-firmware
              ];
            }
            ''
              openssl req -new -x509 -newkey rsa:2048 -nodes -days 7300 \
                -subj ${lib.escapeShellArg "/CN=${cfg.secureBoot.platformKeyName}/"} -keyout pk.key -out pk.crt
              virt-fw-vars -i ${ovmf.fd}/FV/OVMF_VARS.fd -o $out \
                --enroll-cert pk.crt --microsoft-kek all --microsoft-db all \
                --set-dbx ${microsoftDbx} --sb
            '';
        smbiosTables = pkgs.callPackage ./smbios/tables-package.nix {
          cacheL1 = cfg.smbios.cache.l1;
          cacheL2 = cfg.smbios.cache.l2;
          cacheL3 = cfg.smbios.cache.l3;
          cacheAssocL1 = cfg.smbios.cache.assocL1;
          cacheAssocL2 = cfg.smbios.cache.assocL2;
          cacheAssocL3 = cfg.smbios.cache.assocL3;
          cacheEcc = cfg.smbios.cache.ecc;
        };
        acpiTables = pkgs.callPackage ./acpi/package.nix {
          oemId = cfg.acpiOem.id;
          oemTableId = cfg.acpiOem.tableId;
          inherit (cfg.acpiSsdt) batterySerial;
        };
      };
    defaultText = lib.literalMD "built from cpuVendor and the identity options";
    description = "The packages these options build. qemu is qemu-stealth for cpuVendor with the edid, disk, acpiOem and acpi settings, smbios.chassisType, smbios.memory, apart from its manufacturer, part number and speed, which go in through domain.qemuArgs, and devices; ovmf is the matching ovmf-stealth with smbios.biosVendor as its firmware vendor; libvirtQemu is qemu carrying ovmf's firmware descriptors, which the module sets as libvirt's QEMU so its UEFI firmware is ovmf; secureBootVars is ovmf's variable template with the Microsoft KEK and db enrolled under a Platform Key named secureBoot.platformKeyName and Microsoft's published revocation list as dbx; smbiosTables carries the cache options and, as passthru.cacheHandles, the handles the SMBIOS type 4 in domain.qemuArgs links; acpiTables are the SSDTs with the acpiOem id and table id; kernelFor takes a kernel package, such as pkgs.linux_latest, and returns it with kernelPostPatch appended to its postPatch, for boot.kernelPackages = pkgs.linuxPackagesFor (packages.kernelFor pkgs.linux_latest). The module does not patch boot.kernelPackages itself, because a definition of that option that reads its own value recurses.";
  };

  options.virtualisation.vfio-stealth.acpiProcessors = lib.mkOption {
    type = lib.types.functionTo lib.types.package;
    readOnly = true;
    default =
      count:
      pkgs.callPackage ./acpi/processors.nix {
        inherit count;
        oemId = cfg.acpiOem.id;
        oemTableId = cfg.acpiOem.tableId;
      };
    defaultText = lib.literalMD "a function from a vCPU count to an SSDT";
    description = "Builds the SSDT that gives a VM one ACPI processor device per vCPU, under a processor container, as real firmware does; QEMU's own processor objects are removed by the vendor patch. Each VM in domains gets it with its vCPU count; a VM defined by hand passes `-acpitable file=` with it.";
  };

  options.virtualisation.vfio-stealth.bootCheck = lib.mkOption {
    type = lib.types.package;
    readOnly = true;
    default = pkgs.callPackage ./verify/boot.nix {
      inherit cfg nixvirt;
      swtpm = config.virtualisation.libvirtd.qemu.swtpm.package;
    };
    defaultText = lib.literalMD "a build that boots this host's packages and domain.qemuArgs";
    description = "A build that starts this host's packages.qemu with packages.ovmf and domain.qemuArgs under KVM, as libvirt starts them, and boots a probe kernel from a SATA disk, a virtio disk and a SATA CD with SMBIOS emulated and from domain.sysinfo. It also checks that the Secure Boot firmware boots with no keys, refuses an unsigned loader with the Microsoft keys, and with an enrolled test key boots only the signed copy. Build it with `nix build /etc/nixos#nixosConfigurations.<host>.config.virtualisation.vfio-stealth.bootCheck -L`; it needs /dev/kvm, and its output holds every serial log and an evidence.json of what each guest reported. A boot that stalls is retried, up to three boots per case.";
  };

  options.virtualisation.vfio-stealth.domains = lib.mkOption {
    type = lib.types.attrsOf (
      lib.types.submodule (
        { name, config, ... }:
        {
          options = {
            uuid = lib.mkOption (
              {
                type = lib.types.strMatching "^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$";
                description = "The VM's UUID, in lower case, which also becomes its SMBIOS system UUID. Keep it fixed: Windows activation, the TPM state, the MAC address and the USB serials follow it. With identity.seed it defaults to a version 4 UUID derived from the seed and the VM's name; without one it must be set.";
              }
              // lib.optionalAttrs (cfg.identity.seed != null) {
                default = identity.uuid cfg.identity.seed "domain:${name}";
                defaultText = lib.literalMD "a version 4 UUID derived from identity.seed and the VM's name";
              }
            );
            memory = lib.mkOption {
              type = lib.types.ints.positive;
              description = "Memory in MiB.";
            };
            cores = lib.mkOption {
              type = lib.types.ints.positive;
              description = "CPU cores the guest sees, on one socket.";
            };
            threads = lib.mkOption {
              type = lib.types.ints.between 1 2;
              default = 2;
              description = "Threads per core.";
            };
            disks = lib.mkOption {
              type = lib.types.listOf (
                lib.types.submodule {
                  options = {
                    source = lib.mkOption {
                      type = lib.types.str;
                      description = "An image file, or a block device under /dev such as an LVM volume.";
                    };
                    format = lib.mkOption {
                      type = lib.types.enum [
                        "raw"
                        "qcow2"
                      ];
                      default = "raw";
                      description = "The image format; a block device is raw.";
                    };
                    bus = lib.mkOption {
                      type = lib.types.enum [
                        "sata"
                        "virtio"
                      ];
                      default = "sata";
                      description = "sata installs without extra drivers; virtio needs the virtio-win storage driver.";
                    };
                    cache = lib.mkOption {
                      type = lib.types.enum [
                        "none"
                        "writeback"
                        "writethrough"
                        "directsync"
                        "unsafe"
                      ];
                      default = "none";
                      description = "libvirt's cache mode for the disk. none bypasses the host page cache with O_DIRECT, the fastest for a block device or an image on ext4 or XFS. Use writeback for an image on btrfs: there a guest that changes a buffer while its direct write is in flight leaves a block whose checksum fails, and the guest later reads it as an I/O error.";
                    };
                  };
                }
              );
              default = [ ];
              description = "Disks, in boot order.";
            };
            cdroms = lib.mkOption {
              type = lib.types.listOf lib.types.str;
              default = [ ];
              description = "ISO images, attached as SATA CD drives in this order. The VM boots from the first one before the disks.";
            };
            network = lib.mkOption {
              type = lib.types.nullOr (
                lib.types.submodule {
                  options = {
                    type = lib.mkOption {
                      type = lib.types.enum [
                        "network"
                        "bridge"
                      ];
                      default = "network";
                      description = "A libvirt network or a host bridge.";
                    };
                    source = lib.mkOption {
                      type = lib.types.str;
                      default = "default";
                      description = "The libvirt network or bridge name.";
                    };
                    model = lib.mkOption {
                      type = lib.types.str;
                      default = "e1000e";
                      description = "The emulated network card.";
                    };
                    mac = lib.mkOption {
                      type = lib.types.nullOr (lib.types.strMatching "^[0-9A-Fa-f]{2}(:[0-9A-Fa-f]{2}){5}$");
                      default = null;
                      example = "D8:BB:C1:12:34:56";
                      description = "The card's MAC address, such as one a Windows install was activated with. null derives it from macPrefix and the uuid when spoofMac is on, and leaves it to libvirt otherwise.";
                    };
                  };
                }
              );
              default = null;
              description = "The VM's network card, or null for none.";
            };
            hostDevices = lib.mkOption {
              type = lib.types.listOf (
                lib.types.strMatching "^[0-9a-fA-F]{4}:[0-9a-fA-F]{2}:[0-9a-fA-F]{2}\\.[0-7]$"
              );
              default = [ ];
              description = "PCI devices passed through with VFIO, as `lspci -D` prints them, such as 0000:02:00.0 for an NVMe controller, passed managed: libvirt binds them to vfio-pci at start and back at stop. With host.enable the hook refuses to pass one that a protectedDisks path sits on, and unmounts what is mounted from it. A GPU goes under gpu.";
            };
            tpm = lib.mkOption {
              type = lib.types.bool;
              default = true;
              description = "An emulated TPM 2.0, which Windows 11 needs.";
            };
            secureBoot = lib.mkOption {
              type = lib.types.bool;
              default = true;
              description = "Start from the Microsoft Secure Boot keys. With it off the firmware has no keys and boots unsigned loaders.";
            };
            display = lib.mkOption {
              type = lib.types.enum [
                "spice"
                "vnc"
                "none"
              ];
              default = "spice";
              description = "The remote display. With gpu set the VM has no emulated video card, and a spice display carries only input and the clipboard, as Looking Glass uses it; none leaves even that out.";
            };
            sound = lib.mkOption {
              type = lib.types.nullOr (
                lib.types.enum [
                  "micro"
                  "duplex"
                  "output"
                ]
              );
              default = null;
              description = "An emulated Intel HD Audio controller with one codec reporting hdaCodec, played and recorded through the PipeWire session in pipewireRuntimeDir. micro gives a speaker output and a microphone input, duplex a line out and a line in, output a line out alone. QEMU opens the PipeWire socket of another user, so it needs virtualisation.libvirtd.qemu.runAsRoot. null gives the VM no emulated sound; a GPU's HDMI audio or a passed USB audio device needs none.";
            };
            machine = lib.mkOption {
              type = lib.types.strMatching "^(q35|pc-q35-[0-9]+\\.[0-9]+)$";
              default = "q35";
              example = "pc-q35-10.0";
              description = "The QEMU machine type, always a q35, which the stealth patches edit. q35 follows the QEMU version; pin a versioned type such as pc-q35-10.0 to keep the hardware Windows was activated on across QEMU updates.";
            };
            pinning = lib.mkOption {
              type = lib.types.nullOr (
                lib.types.submodule {
                  options = {
                    vcpus = lib.mkOption {
                      type = lib.types.listOf lib.types.ints.unsigned;
                      example = [
                        2
                        18
                        3
                        19
                      ];
                      description = "The host CPU each vCPU runs on, in vCPU order, one per vCPU. With threads = 2, list the two hardware threads of one host core next to each other, as lscpu -e pairs them, so the guest's sibling threads share a core.";
                    };
                    emulator = lib.mkOption {
                      type = cpuset;
                      example = "0-1";
                      description = "Host CPUs for QEMU's emulator threads, as a libvirt cpuset, outside the vCPUs' CPUs.";
                    };
                    iothread = lib.mkOption {
                      type = lib.types.nullOr cpuset;
                      default = null;
                      example = "1";
                      description = "Host CPUs for one I/O thread, which serves the domain's virtio disks. null gives the domain no I/O thread, and QEMU's main loop serves them.";
                    };
                  };
                }
              );
              default = null;
              description = "Pin each vCPU to its own host CPU, and QEMU's threads to others. null leaves placement to the host scheduler.";
            };
            cpuPm = lib.mkOption {
              type = lib.types.bool;
              default = config.pinning != null;
              defaultText = lib.literalExpression "pinning != null";
              description = "Pass -overcommit cpu-pm=on, so HLT, MWAIT and PAUSE no longer exit: an idle vCPU wakes without an exit's delay and the guest gets MWAIT and, with aperfMperf, APERF and MPERF, as on hardware. The vCPU then never hands its host CPU back when idle, so it suits vCPUs pinned one to one to host CPUs nothing else needs, and takes time from host work on CPUs the host shares with it.";
            };
            hugepages = lib.mkOption {
              type = lib.types.bool;
              default = false;
              description = "Back the guest's memory with locked huge pages of hugepages.size from a shared memfd. memory must be a whole number of pages. Needs host.enable; without hugepages.atBoot the hook allocates the pages at start.";
            };
            gpu = lib.mkOption {
              type = lib.types.nullOr (
                lib.types.submodule {
                  options = {
                    address = lib.mkOption {
                      type = pciAddress;
                      example = "0000:01:00.0";
                      description = "The GPU's PCI address, as lspci -D prints it.";
                    };
                    audio = lib.mkOption {
                      type = lib.types.nullOr pciAddress;
                      default = null;
                      example = "0000:01:00.1";
                      description = "The GPU's HDMI audio function, which sits in its IOMMU group.";
                    };
                    extraFunctions = lib.mkOption {
                      type = lib.types.listOf pciAddress;
                      default = [ ];
                      example = [ "0000:01:00.2" ];
                      description = "Further functions in the GPU's IOMMU group, such as the USB-C controller of some cards. They are bound with the GPU.";
                    };
                    rom = lib.mkOption {
                      type = lib.types.nullOr (
                        lib.types.submodule {
                          options = {
                            file = lib.mkOption {
                              type = lib.types.nullOr lib.types.path;
                              default = null;
                              description = "A VBIOS image the guest sees in place of the card's own ROM, for a card whose ROM the host firmware has altered. A path in the flake is copied to the store, where QEMU can read it.";
                            };
                            bar = lib.mkOption {
                              type = lib.types.bool;
                              default = true;
                              description = "Show the guest the card's ROM BAR. Some cards' guest drivers misread it, which shows as a corrupted picture; turn it off for those.";
                            };
                          };
                        }
                      );
                      default = null;
                      description = "The GPU's option ROM; null leaves it as QEMU shows it.";
                    };
                    binding = lib.mkOption {
                      type = lib.types.enum [
                        "libvirt"
                        "hook"
                        "boot"
                      ];
                      default = "libvirt";
                      description = "How the GPU reaches vfio-pci. \"libvirt\" passes it managed: libvirt unbinds the host driver at start and binds it again at stop. \"hook\" binds vfio-pci in the QEMU hook through driver_override after the host driver has initialised the card, for cards that need a host POST, and gives it back only with rebindOnStop. \"boot\" claims it at boot through vfio-pci.ids from ids, so the host never drives it.";
                    };
                    ids = lib.mkOption {
                      type = lib.types.listOf pciId;
                      default = [ ];
                      example = [
                        "10de:2484"
                        "10de:228b"
                      ];
                      description = "The vendor:device ids binding \"boot\" puts in vfio-pci.ids, as lspci -nn shows them. Every device with one of these ids goes to vfio-pci, so never list an id the host's own devices share.";
                    };
                    resizeBar2Mb = lib.mkOption {
                      type = lib.types.nullOr powerOfTwo;
                      default = null;
                      example = 256;
                      description = "With binding \"hook\", resize BAR 2 to this many MiB while no driver holds the card, before vfio-pci binds it. The size must be one the card lists in resource2_resize. A small BAR keeps some guest drivers from failing; the largest makes some cards re-enumerate and clears a reset state a stop leaves. null leaves BAR 2 as it is.";
                    };
                    rebindOnStop = lib.mkOption {
                      type = lib.types.bool;
                      default = false;
                      description = "With binding \"hook\", give the GPU back to its host driver when the VM stops. Off, the card stays on vfio-pci until the next boot; some kernels crash when the host driver takes back a card a guest has used.";
                    };
                  };
                }
              );
              default = null;
              description = "A GPU passed through with VFIO. The VM then has no emulated video card. Its address, audio and extraFunctions are guarded like hostDevices.";
            };
            usb = lib.mkOption {
              type = lib.types.listOf (
                lib.types.submodule {
                  options = {
                    vendor = lib.mkOption {
                      type = lib.types.ints.u16;
                      example = 4660;
                      description = "The USB vendor id, as lsusb shows it in hex; write it as a number, such as 4660 for 1234.";
                    };
                    product = lib.mkOption {
                      type = lib.types.ints.u16;
                      example = 22136;
                      description = "The USB product id, as a number.";
                    };
                  };
                }
              );
              default = [ ];
              description = "USB devices passed through by vendor and product id. A udev rule attaches a device again when it is plugged in while the VM runs.";
            };
            unmount = lib.mkOption {
              type = lib.types.listOf lib.types.externalPath;
              default = [ ];
              example = [ "/mnt/games" ];
              description = "Mount points the hook unmounts before the VM starts, such as a filesystem on a disk the VM takes, and mounts again from fstab after it stops. A path that is not mounted is skipped; one that will not unmount refuses the start. Filesystems left mounted on a passed-through disk are unmounted too, but not mounted again. Needs host.enable.";
            };
            stopServices = lib.mkOption {
              type = lib.types.listOf (lib.types.strMatching "^[A-Za-z0-9@._:-]+$");
              default = [ ];
              example = [
                "coolercontrold.service"
                "lactd.service"
              ];
              description = "systemd units the QEMU hook stops before the VM takes its devices and starts again when it stops, such as fan or GPU control daemons that keep a GPU open. Before taking a device the hook refuses to start while any process still has it open, and names those processes, where taking it from its driver would otherwise wait for them. Needs host.enable.";
            };
            iommu = lib.mkOption {
              type = lib.types.bool;
              default = false;
              description = "Give the VM an IOMMU of the host's vendor, AMD-Vi on AMD and VT-d on Intel, with interrupt remapping, as a real board has. Windows' own hypervisor then finds I/O remapping hardware, which VBS uses for DMA protection; without it a guest with VBS and a passed-through GPU can show no picture. On Intel, Windows with VBS does not start with this IOMMU. Each passed-through device then needs an IOMMU group of its own on the host: a group of several devices, such as a GPU whose audio and USB functions share its group, is refused.";
            };
            lookingGlass = lib.mkOption {
              type = lib.types.bool;
              default = false;
              description = "Give the VM the ivshmem device Looking Glass writes frames to: backed by /dev/kvmfr0 with kvmfr.enable, else by /dev/shm/looking-glass of lookingGlass.shmemSizeMb.";
            };
            cpuIdentity = {
              manufacturer = domainOverride lib.types.str "cpuIdentity.manufacturer";
              modelId = domainOverride lib.types.str "cpuIdentity.modelId";
              maxSpeed = domainOverride (lib.types.ints.between 1 65535) "cpuIdentity.maxSpeed";
              currentSpeed = domainOverride (lib.types.ints.between 1 65535) "cpuIdentity.currentSpeed";
              socket = domainOverride smbiosText "cpuIdentity.socket";
              family = domainOverride (lib.types.ints.between 1 65533) "cpuIdentity.family";
              voltageDecivolts = domainOverride (lib.types.ints.between 1 127) "cpuIdentity.voltageDecivolts";
              externalClock = domainOverride (lib.types.ints.between 1 65535) "cpuIdentity.externalClock";
              upgrade = domainOverride (lib.types.ints.between 1 255) "cpuIdentity.upgrade";
              characteristics = domainOverride lib.types.ints.u16 "cpuIdentity.characteristics";
            };
            cache = {
              l1 = domainOverride lib.types.ints.positive "smbios.cache.l1";
              l2 = domainOverride lib.types.ints.positive "smbios.cache.l2";
              l3 = domainOverride lib.types.ints.positive "smbios.cache.l3";
              assocL1 = domainOverride (lib.types.ints.between 1 14) "smbios.cache.assocL1";
              assocL2 = domainOverride (lib.types.ints.between 1 14) "smbios.cache.assocL2";
              assocL3 = domainOverride (lib.types.ints.between 1 14) "smbios.cache.assocL3";
              ecc = domainOverride (lib.types.ints.between 1 6) "smbios.cache.ecc";
            };
            hypervMode = domainOverride (lib.types.enum [
              "enlightened"
              "hidden"
            ]) "hypervMode";
            kvmPvEnforceCpuid = domainOverride lib.types.bool "kvmPvEnforceCpuid";
            extraQemuArgs = lib.mkOption {
              type = lib.types.listOf lib.types.str;
              default = [ ];
              description = "QEMU arguments added after the generated ones. Never -cpu, which replaces libvirt's CPU line.";
            };
            active = lib.mkOption {
              type = lib.types.nullOr lib.types.bool;
              default = null;
              description = "Whether NixVirt starts (true) or stops (false) the VM at activation; null leaves it as it is.";
            };
            extra = lib.mkOption {
              type = lib.types.attrsOf lib.types.anything;
              default = { };
              description = "NixVirt domain attributes merged over the generated ones, for anything these options do not cover.";
            };
            xml = lib.mkOption {
              type = lib.types.path;
              readOnly = true;
              description = "The rendered domain XML. NixVirt defines it in libvirt; `virsh define` takes it too.";
            };
          };
          config.xml = pkgs.writeText "${name}.xml" (
            import ./render.nix {
              inherit
                lib
                pkgs
                cfg
                nixvirt
                name
                ;
              domain = config;
            }
          );
        }
      )
    );
    default = { };
    description = "VMs this module defines in libvirt through NixVirt, each with the stealth QEMU arguments, SMBIOS sysinfo, Hyper-V and CPU settings, the stealth firmware and Secure Boot keys. NixVirt redefines them at each activation, so a change made in virt-manager does not survive a rebuild. Once any VM is declared here, NixVirt removes every other VM defined on qemu:///system, though not its disks or NVRAM, so declare every VM of the host here or none.";
  };

  options.virtualisation.vfio-stealth.domain = lib.mkOption {
    type = lib.types.lazyAttrsOf lib.types.anything;
    readOnly = true;
    default =
      let
        stealth = (import ./lib.nix { inherit lib; }).mkStealthFeatures {
          inherit (cfg)
            smbios
            acpiSsdt
            aperfMperf
            cet
            stripVirtio
            hypervVendorId
            hypervMode
            kvmPvEnforceCpuid
            pciMmio64Mb
            hypervFeatures
            kernelCapabilities
            cpuVendor
            ;
          inherit (cfg.packages) acpiTables smbiosTables;
        };
      in
      stealth
      // {
        qemuArgs = stealth.qemuArgs cfg.cpuIdentity;
        processor = stealth.processor cfg.cpuIdentity;
      };
    defaultText = lib.literalMD "lib.mkStealthFeatures applied to these options";
    description = "What a VM's libvirt domain takes from these options: features, cpuFeatures, clock and sysinfo for the domain, qemuArgs for its QEMU command line, processor for the SMBIOS type 4 identity cpuIdentity resolves to, the devices devicesToRemove names, and warnings. qemuArgs leave out what domains.<name>.cpuPm adds, -overcommit cpu-pm=on and with aperfMperf -global x86_64-cpu.aperfmperf=on, which a VM pinned one to one adds itself.";
  };
}
