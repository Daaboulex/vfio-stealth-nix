{
  autovirt,
  better-timing,
  vfio-stealth,
}:
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.myModules.vfio.stealth;

  # These are shell script strings (postPatch fragments), not .patch files.
  timingPatchScript = import ./kernel/timing-patch.nix;
  cpuidPatchScript = import ./kernel/cpuid-patch.nix;
in
{
  _class = "nixos";

  options.myModules.vfio.stealth = {
    enable = lib.mkEnableOption "VFIO stealth anti-detection stack";

    # --- Kernel-level patches ---
    # These compile directly into the host kernel to defeat low-level
    # hypervisor detection (timing side-channels, CPUID enumeration).

    timing = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "BetterTiming TSC compensation (hides VM exit timing from guests). Defeats timing-based VM detection that measures RDTSC deltas across CPUID/VMCALL.";
      };
    };

    cpuidSpoof = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "CPUID leaf 0 spoofing via Hypervisor-Phantom technique. Defeats anti-cheat that checks the hypervisor-present CPUID bit (leaf 1, bit 31) and hypervisor vendor string (leaf 0x40000000).";
      };
    };

    # --- Kernel boot parameters ---
    # Stabilize TSC and reduce C-state transitions that can leak VM context.

    kernelParams = {
      maxCState = lib.mkOption {
        type = lib.types.int;
        default = 1;
        description = "processor.max_cstate value passed on the kernel command line. Lower values reduce timing jitter that can reveal virtualization.";
      };

      tscReliable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Pass tsc=reliable on the kernel command line. Prevents kernel from falling back to HPET/ACPI PM timer, which anti-cheat can detect.";
      };
    };

    # --- SMBIOS identity ---
    # Populates DMI/SMBIOS tables so the guest looks like real hardware.
    # Anti-cheat queries Win32_BaseBoard, Win32_BIOS, Win32_ComputerSystem,
    # Win32_PhysicalMemory, and Win32_CacheMemory via WMI.

    smbios = {
      manufacturer = lib.mkOption {
        type = lib.types.str;
        default = "To Be Filled By O.E.M.";
        description = "SMBIOS system manufacturer string. Defeats WMI Win32_ComputerSystem.Manufacturer checks.";
      };
      product = lib.mkOption {
        type = lib.types.str;
        default = "To Be Filled By O.E.M.";
        description = "SMBIOS product name string. Defeats WMI Win32_ComputerSystem.Model checks.";
      };
      biosVendor = lib.mkOption {
        type = lib.types.str;
        default = "American Megatrends Inc.";
        description = "SMBIOS BIOS vendor string. Defeats WMI Win32_BIOS.Manufacturer checks.";
      };
      biosVersion = lib.mkOption {
        type = lib.types.str;
        default = "1001";
        description = "SMBIOS BIOS version string. Defeats WMI Win32_BIOS.SMBIOSBIOSVersion checks.";
      };
      serial = lib.mkOption {
        type = lib.types.str;
        default = "System Serial Number";
        description = "SMBIOS system serial number. Defeats WMI Win32_ComputerSystemProduct.IdentifyingNumber checks.";
      };
      socketPrefix = lib.mkOption {
        type = lib.types.str;
        default = "AM5";
        description = "SMBIOS processor socket designator prefix (type 4). Defeats WMI Win32_Processor.SocketDesignation checks.";
      };

      # SMBIOS type 17 — physical memory / DIMMs.
      # Empty Win32_PhysicalMemory is a strong VM indicator.
      memory = {
        manufacturer = lib.mkOption {
          type = lib.types.str;
          default = "Kingston";
          description = "DIMM manufacturer for SMBIOS type 17. Defeats WMI Win32_PhysicalMemory.Manufacturer checks.";
        };
        partNumber = lib.mkOption {
          type = lib.types.str;
          default = "KF560C36-16";
          description = "DIMM part number. Defeats WMI Win32_PhysicalMemory.PartNumber checks.";
        };
        speed = lib.mkOption {
          type = lib.types.int;
          default = 4800;
          description = "Memory speed in MT/s. Defeats WMI Win32_PhysicalMemory.Speed checks.";
        };
        size = lib.mkOption {
          type = lib.types.int;
          default = 16384;
          description = "DIMM size in MB (per module).";
        };
        count = lib.mkOption {
          type = lib.types.int;
          default = 2;
          description = "Number of DIMMs to report.";
        };
      };

      # SMBIOS type 7 — cache information.
      # Empty Win32_CacheMemory is a strong VM indicator.
      cache = {
        l1 = lib.mkOption {
          type = lib.types.int;
          default = 512;
          description = "L1 cache size in KB for SMBIOS type 7.";
        };
        l2 = lib.mkOption {
          type = lib.types.int;
          default = 8192;
          description = "L2 cache size in KB for SMBIOS type 7.";
        };
        l3 = lib.mkOption {
          type = lib.types.int;
          default = 32768;
          description = "L3 cache size in KB for SMBIOS type 7.";
        };
      };
    };

    # --- MSR passthrough ---
    # Defeats instruction-execution-timing (IET) VM detection that reads
    # IA32_APERF/MPERF MSRs to measure actual vs. requested CPU frequency.
    # VMs normally trap these, adding measurable latency.

    aperfMperf = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Pass through IA32_APERF/MPERF MSRs to guest (defeats IET-based VM detection). Requires kernel 6.18+.";
    };

    # --- Network identity ---
    # Anti-cheat checks the NIC MAC OUI prefix. QEMU's default 52:54:00
    # is a well-known KVM fingerprint.

    spoofMac = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Spoof guest NIC MAC address with a realistic OUI prefix. Defeats MAC OUI-based VM detection.";
    };

    macPrefix = lib.mkOption {
      type = lib.types.str;
      default = "00:1b:21";
      description = "OUI prefix used when spoofMac is enabled (colon-separated hex, e.g. 00:1b:21). Intel OUI by default.";
    };

    # --- VirtIO device stripping ---
    # VirtIO PCI vendor/device IDs (1af4:10xx) are trivially fingerprinted.

    stripVirtio = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Remove VirtIO balloon, RNG, and tablet devices from VM config when stealth is enabled. Defeats PCI device enumeration checks.";
    };

    # --- ACPI SSDT tables ---
    # Injects fake ACPI devices (USB controllers, embedded controllers,
    # battery) so the ACPI namespace looks like a real motherboard.
    # Empty ACPI namespace is a strong VM indicator.

    acpiSsdt = {
      spoofedDevices = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Include spoofed ACPI device entries in the SSDT table. Defeats ACPI namespace enumeration checks.";
      };
      fakeBattery = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Include a fake ACPI battery device in the SSDT table. Defeats 'no battery = server/VM' heuristic.";
      };
      sensorProbes = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Include CPU and VRM thermal zone probes (defeats MSAcpi_ThermalZoneTemperature WMI detection).";
      };
    };

    # --- EDID monitor identity ---
    # QEMU's default EDID exposes generic/patched monitor strings.
    # Anti-cheat can query the monitor EDID blob via SetupAPI/WMI and
    # flag non-existent manufacturer/model combinations.

    edid = {
      manufacturer = lib.mkOption {
        type = lib.types.str;
        default = "ACI";
        description = "3-char EDID manufacturer code.";
      };
      modelAbbrev = lib.mkOption {
        type = lib.types.str;
        default = "ACI     ";
        description = "8-char padded EDID model abbreviation.";
      };
      model = lib.mkOption {
        type = lib.types.str;
        default = "ASUS VG248      ";
        description = "16-char padded EDID model string.";
      };
      serial = lib.mkOption {
        type = lib.types.str;
        default = "VG248QE";
        description = "Monitor serial string.";
      };
      productCode = lib.mkOption {
        type = lib.types.str;
        default = "0x2480";
        description = "EDID product code (hex).";
      };
      dpi = lib.mkOption {
        type = lib.types.int;
        default = 91;
        description = "Monitor DPI.";
      };
      week = lib.mkOption {
        type = lib.types.int;
        default = 22;
        description = "EDID manufacture week.";
      };
      year = lib.mkOption {
        type = lib.types.int;
        default = 2020;
        description = "EDID manufacture year.";
      };
    };

    # --- Disk model strings ---
    # QEMU/IDE exposes default drive model strings that anti-cheat
    # cross-references against known virtual disk identifiers.

    disk = {
      model = lib.mkOption {
        type = lib.types.str;
        default = "WDC WD10EZEX-00W          ";
        description = "Emulated disk model string (24 chars padded with spaces). Defeats Win32_DiskDrive.Model checks.";
      };
      opticalModel = lib.mkOption {
        type = lib.types.str;
        default = "HL-DT-ST DVDRAM GH24NSC0  ";
        description = "Emulated optical drive model (24 chars padded). Defeats Win32_CDROMDrive.Name checks.";
      };
    };

    # --- ACPI OEM identity ---
    # QEMU's default ACPI tables use "BOCHS"/"BXPC" as OEM ID/Table ID.
    # Anti-cheat scans raw ACPI table headers for these known VM strings.

    acpiOem = {
      id = lib.mkOption {
        type = lib.types.str;
        default = "ALASKA";
        description = "6-char ACPI OEM ID (padded with spaces). Defeats ACPI table header OEM ID checks.";
      };
      tableId = lib.mkOption {
        type = lib.types.str;
        default = "A M I   ";
        description = "8-char ACPI OEM Table ID (padded with spaces). Defeats ACPI table header OEM Table ID checks.";
      };
    };

    # --- CPU identity ---
    # Anti-cheat queries SMBIOS type 4 and CPUID brand string.
    # Mismatched or missing CPU identity is a VM indicator.

    cpuIdentity = {
      modelId = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "CPU model string reported to guest (e.g. 'AMD Ryzen 7 7800X3D 8-Core Processor'). null = use host CPU.";
      };
      maxSpeed = lib.mkOption {
        type = lib.types.nullOr lib.types.int;
        default = null;
        description = "CPU max speed in MHz for SMBIOS type 4. null = omit.";
      };
      currentSpeed = lib.mkOption {
        type = lib.types.nullOr lib.types.int;
        default = null;
        description = "CPU current speed in MHz for SMBIOS type 4. null = omit.";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    # Expose the postPatch scripts as an option so the host config can apply
    # them to its own kernel (CachyOS, stock, etc.) via overrideAttrs.
    # We do NOT set boot.kernelPackages here to avoid overriding the host's
    # kernel choice (e.g., CachyOS LTO) and to prevent infinite recursion.

    boot.kernelParams = [
      "processor.max_cstate=${toString cfg.kernelParams.maxCState}"
    ]
    ++ lib.optionals cfg.kernelParams.tscReliable [ "tsc=reliable" ];
  };

  # Expose patch scripts for host-level kernel integration
  options.myModules.vfio.stealth._kernelPostPatch = lib.mkOption {
    type = lib.types.str;
    readOnly = true;
    internal = true;
    default =
      lib.optionalString cfg.timing.enable timingPatchScript
      + lib.optionalString cfg.cpuidSpoof.enable cpuidPatchScript;
    description = "Combined kernel postPatch script. Apply via kernel overrideAttrs in host config.";
  };
}
