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
  cpuidDisableScript = import ./kernel/cpuid-disable.nix;
in
{
  _class = "nixos";

  options.myModules.vfio.stealth = {
    enable = lib.mkEnableOption "VFIO hardware emulation stack";

    # --- Kernel-level patches ---
    # These compile directly into the host kernel to handle low-level
    # hypervisor indicators (timing side-channels, CPUID enumeration).

    timing = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "BetterTiming TSC compensation (hides VM exit timing from guests). Compensates RDTSC timing deltas from VM exits across CPUID/VMCALL.";
      };
    };

    cpuidSpoof = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "CPUID leaf 0 emulation via Hypervisor-Phantom technique. Covers the hypervisor-present CPUID bit (leaf 1, bit 31) and hypervisor vendor string (leaf 0x40000000). Skipped when cpuidPassthrough.enable is true.";
      };
    };

    cpuidPassthrough = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Disable CPUID interception entirely. Guest executes CPUID at native hardware speed (zero VM exit). Addresses software-counter timing checks (VMAware TIMER 95pts, SINGLE_STEP 100pts). Requires AMD host with host-passthrough CPU mode. When enabled, cpuidSpoof is skipped (passthrough takes precedence). Side effect: Hyper-V enlightenments are invisible to guest (Windows uses TSC directly).";
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
        description = "Pass tsc=reliable on the kernel command line. Prevents kernel from falling back to HPET/ACPI PM timer, which detection software can flag.";
      };
    };

    # --- SMBIOS identity ---
    # Populates DMI/SMBIOS tables so the guest presents realistic hardware values.
    # Detection software queries Win32_BaseBoard, Win32_BIOS, Win32_ComputerSystem,
    # Win32_PhysicalMemory, and Win32_CacheMemory via WMI.

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
        description = "SMBIOS BIOS vendor string. Populates WMI Win32_BIOS.Manufacturer.";
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
        default = "Default string";
        description = "Baseboard serial number (SMBIOS Type 2). Set to your real board serial from dmidecode.";
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
      socketPrefix = lib.mkOption {
        type = lib.types.str;
        default = "AM5";
        description = "SMBIOS processor socket designator prefix (type 4). Populates WMI Win32_Processor.SocketDesignation.";
      };

      # SMBIOS type 17 — physical memory / DIMMs.
      # Empty Win32_PhysicalMemory is a strong VM indicator.
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
          type = lib.types.int;
          default = 4800;
          description = "Memory speed in MT/s. Populates WMI Win32_PhysicalMemory.Speed.";
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
                type = lib.types.int;
                description = "Device instance number.";
              };
            };
          }
        );
        default = [ ];
        description = "Onboard devices for SMBIOS Type 41. Set to match your board (e.g., LAN, SATA controllers from dmidecode -t 41). Empty = no Type 41 entries.";
      };
    };

    # --- MSR passthrough ---
    # Addresses instruction-execution-timing (IET) checks that read
    # IA32_APERF/MPERF MSRs to measure actual vs. requested CPU frequency.
    # VMs normally trap these, adding measurable latency.

    aperfMperf = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Pass through IA32_APERF/MPERF MSRs to guest (addresses IET-based VM indicators). Requires kernel 6.18+.";
    };

    # --- Network identity ---
    # Detection software checks the NIC MAC OUI prefix. QEMU's default 52:54:00
    # is a well-known KVM identifier.

    spoofMac = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Override guest NIC MAC address with a realistic OUI prefix. Covers MAC OUI-based VM indicators.";
    };

    macPrefix = lib.mkOption {
      type = lib.types.strMatching "^[0-9A-Fa-f]{2}:[0-9A-Fa-f]{2}:[0-9A-Fa-f]{2}$";
      default = "D8:BB:C1";
      description = "OUI prefix used when spoofMac is enabled (colon-separated hex, e.g. D8:BB:C1). Realtek OUI matching ASUS X870E onboard NIC.";
    };

    # --- Hyper-V vendor_id ---
    # The vendor_id exposed via Hyper-V enlightenments. Detection software may flag
    # well-known VM values like "AMDisbetter!" or "Microsoft Hv".

    hypervVendorId = lib.mkOption {
      type = lib.types.strMatching "^.{1,12}$";
      default = "AuthAMDRyzen"; # 12 chars exactly — libvirt max
      description = "Hyper-V vendor_id reported to guest (1–12 chars, libvirt hard limit). Avoid well-known VM values like 'AMDisbetter!' or 'Microsoft Hv'.";
    };

    hypervMode = lib.mkOption {
      type = lib.types.enum [
        "enlightened"
        "hidden"
      ];
      default = "enlightened";
      description = "Hyper-V enlightenment strategy for hardened VMs. \"enlightened\" exposes the hypervisor + full Hyper-V enlightenments (paravirt perf; blends in with VBS-enabled Windows 11). \"hidden\" conceals the hypervisor and emits no enlightenments. Per-VM overridable via vms.<name>.hypervMode";
    };

    # --- VirtIO device stripping ---
    # VirtIO PCI vendor/device IDs (1af4:10xx) are well-known VM indicators.

    stripVirtio = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Remove VirtIO balloon, RNG, and tablet devices from VM config when hardware emulation is enabled. Covers PCI device enumeration checks.";
    };

    # --- ACPI SSDT tables ---
    # Injects emulated ACPI devices (USB controllers, embedded controllers,
    # battery) so the ACPI namespace presents realistic hardware entries.
    # Empty ACPI namespace is a strong VM indicator.

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
      sensorProbes = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Include CPU and VRM thermal zone probes (covers MSAcpi_ThermalZoneTemperature WMI checks).";
      };
    };

    # --- EDID monitor identity ---
    # QEMU's default EDID exposes generic/patched monitor strings.
    # Detection software can query the monitor EDID blob via SetupAPI/WMI and
    # flag non-existent manufacturer/model combinations.

    edid = {
      manufacturer = lib.mkOption {
        type = lib.types.str;
        default = "ACI";
        description = "3-char EDID manufacturer code.";
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
    # QEMU/IDE exposes default drive model strings that detection software
    # cross-references against known virtual disk identifiers.

    disk = {
      model = lib.mkOption {
        type = lib.types.str;
        default = "WDC WD10EZEX-00WN4A0     ";
        description = "Emulated disk model string (25 chars, space-padded). Populates Win32_DiskDrive.Model. Set to your real disk model.";
      };
      serial = lib.mkOption {
        type = lib.types.str;
        default = "Default string";
        description = "IDE/SCSI disk serial string. Populates Win32_DiskDrive.SerialNumber. Set to your real disk serial from smartctl.";
      };
      opticalModel = lib.mkOption {
        type = lib.types.str;
        default = "HL-DT-ST DVDRAM GH24NSC0 ";
        description = "Emulated optical drive model (25 chars, space-padded). Populates Win32_CDROMDrive.Name.";
      };
    };

    # --- ACPI OEM identity ---
    # QEMU's default ACPI tables use "BOCHS"/"BXPC" as OEM ID/Table ID.
    # Detection software scans raw ACPI table headers for these known VM strings.

    acpiOem = {
      id = lib.mkOption {
        type = lib.types.str;
        default = "ALASKA";
        description = "6-char ACPI OEM ID (padded with spaces). Populates ACPI table header OEM ID field.";
      };
      tableId = lib.mkOption {
        type = lib.types.str;
        default = "A M I   ";
        description = "8-char ACPI OEM Table ID (padded with spaces). Populates ACPI table header OEM Table ID field.";
      };
    };

    # --- CPU identity ---
    # Detection software queries SMBIOS type 4 and CPUID brand string.
    # Mismatched or missing CPU identity is a VM indicator.

    cpuIdentity = {
      manufacturer = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "CPU manufacturer for SMBIOS type 4. null = 'Advanced Micro Devices, Inc.' Set to your CPU vendor (e.g. 'GenuineIntel' for Intel hosts).";
      };
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

    # --- TPM identity hardening ---
    # swtpm defaults report manufacturer=IBM, model=swtpm — easily
    # identified via Win32_Tpm WMI class and Get-Tpm PowerShell cmdlet.

    tpm = {
      harden = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Configure swtpm to report realistic hardware TPM identity. Affects EK/platform certificates (swtpm-localca.options) and protocol-level properties (libtpms patch).";
      };
      manufacturer = lib.mkOption {
        type = lib.types.strMatching "^[a-zA-Z0-9:]+$";
        default = "id:49465800";
        description = "TPM manufacturer ID (8 hex digits). id:49465800=Infineon, id:414D4400=AMD fTPM, id:494E5443=Intel PTT.";
      };
      model = lib.mkOption {
        type = lib.types.strMatching "^[a-zA-Z0-9 _-]+$";
        default = "SLB9672";
        description = "TPM model string. Common: SLB9672 (Infineon discrete), AMD (fTPM).";
      };
      firmwareVersion = lib.mkOption {
        type = lib.types.strMatching "^[a-zA-Z0-9:]+$";
        default = "id:000F0018";
        description = "TPM firmware version (8 hex digits). 0x000F0018 = FW 15.24 (Infineon SLB9672).";
      };
      platformManufacturer = lib.mkOption {
        type = lib.types.str;
        default = "ASUSTeK COMPUTER INC.";
        description = "Platform manufacturer for TPM platform certificate. Should match SMBIOS manufacturer.";
      };
      platformModel = lib.mkOption {
        type = lib.types.str;
        default = "System Product Name";
        description = "Platform model for TPM platform certificate.";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = !(cfg.cpuidSpoof.enable && cfg.cpuidPassthrough.enable);
        message = "cpuidSpoof and cpuidPassthrough are mutually exclusive — cpuidPassthrough intercepts all CPUID, making cpuidSpoof redundant";
      }
      {
        assertion = !(cfg.cpuidPassthrough.enable && cfg.hypervMode == "enlightened");
        message = "cpuidPassthrough disables CPUID interception — Hyper-V enlightenments (hypervMode=enlightened) will be invisible to the guest; set hypervMode to hidden";
      }
      {
        assertion = builtins.stringLength cfg.disk.model == 25;
        message = "disk.model must be exactly 25 characters (space-padded per ATA spec); got ${toString (builtins.stringLength cfg.disk.model)}";
      }
      {
        assertion = builtins.stringLength cfg.acpiOem.id == 6;
        message = "acpiOem.id must be exactly 6 characters; got ${toString (builtins.stringLength cfg.acpiOem.id)}";
      }
      {
        assertion = builtins.stringLength cfg.acpiOem.tableId == 8;
        message = "acpiOem.tableId must be exactly 8 characters; got ${toString (builtins.stringLength cfg.acpiOem.tableId)}";
      }
    ];

    boot.kernelParams = [
      "processor.max_cstate=${toString cfg.kernelParams.maxCState}"
      "kvm_amd.vls=0" # Force VMLOAD/VMSAVE interception (prevents SVM instruction indicator)
      "kvm_amd.vgif=0" # Force STGI/CLGI interception (prevents vGIF behavior indicator)
    ]
    ++ lib.optionals cfg.kernelParams.tscReliable [ "tsc=reliable" ];

    # swtpm certificate hardening: custom swtpm-localca.options so EK/platform
    # certificates report realistic hardware identity instead of "QEMU"/"swtpm".
    environment.etc = lib.mkIf cfg.tpm.harden {
      "swtpm-localca.options" = {
        text = lib.concatStringsSep "\n" [
          "--platform-manufacturer \"${cfg.tpm.platformManufacturer}\""
          "--platform-model \"${cfg.tpm.platformModel}\""
          "--platform-version \"1.0\""
          "--tpm-manufacturer \"${cfg.tpm.manufacturer}\""
          "--tpm-model \"${cfg.tpm.model}\""
          "--tpm-version \"${cfg.tpm.firmwareVersion}\""
        ];
      };
    };
  };

  # Expose libtpms identity patch for host-level integration.
  # Apply via: libtpms.overrideAttrs (old: { postPatch = (old.postPatch or "") + cfg._libtpmsIdentityPatch; });
  options.myModules.vfio.stealth._libtpmsIdentityPatch = lib.mkOption {
    type = lib.types.str;
    readOnly = true;
    internal = true;
    default = lib.optionalString (cfg.enable && cfg.tpm.harden) ''
      echo "=== libtpms identity patch: ${cfg.tpm.manufacturer} / ${cfg.tpm.model} ==="
      # The C source uses backslash-escaped quotes inside string literals,
      # so patterns must include the backslash.  grep -F treats the pattern
      # as a fixed string; sed uses \\ to match a literal backslash.
      if grep -Fq '\"manufacturer\":\"id:00001014\"' src/tpm_tpm2_interface.c; then
        sed -i 's/\\"manufacturer\\":\\"id:00001014\\"/\\"manufacturer\\":\\"${cfg.tpm.manufacturer}\\"/g' src/tpm_tpm2_interface.c
        echo "[OK] libtpms: manufacturer patched to ${cfg.tpm.manufacturer}"
      else
        echo "[FAIL] libtpms: manufacturer anchor not found in tpm_tpm2_interface.c"
        exit 1
      fi
      if grep -Fq '\"model\":\"swtpm\"' src/tpm_tpm2_interface.c; then
        sed -i 's/\\"model\\":\\"swtpm\\"/\\"model\\":\\"${cfg.tpm.model}\\"/g' src/tpm_tpm2_interface.c
        echo "[OK] libtpms: model patched to ${cfg.tpm.model}"
      else
        echo "[FAIL] libtpms: model anchor not found in tpm_tpm2_interface.c"
        exit 1
      fi
      echo "=== libtpms identity patch complete ==="
    '';
    description = "libtpms postPatch script that replaces hardcoded IBM/swtpm identity. Apply via libtpms.overrideAttrs in host config.";
  };

  # Expose patch scripts for host-level kernel integration
  options.myModules.vfio.stealth._kernelPostPatch = lib.mkOption {
    type = lib.types.str;
    readOnly = true;
    internal = true;
    default =
      lib.optionalString (cfg.enable && cfg.timing.enable) timingPatchScript
      + lib.optionalString (
        cfg.enable && cfg.cpuidSpoof.enable && !cfg.cpuidPassthrough.enable
      ) cpuidPatchScript
      + lib.optionalString (cfg.enable && cfg.cpuidPassthrough.enable) cpuidDisableScript;
    description = "Combined kernel postPatch script. Apply via kernel overrideAttrs in host config.";
  };
}
