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

    timing = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "BetterTiming TSC compensation (hides VM exit timing from guests)";
      };
    };

    cpuidSpoof = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "CPUID leaf 0 spoofing via Hypervisor-Phantom technique";
      };
    };

    kernelParams = {
      maxCState = lib.mkOption {
        type = lib.types.int;
        default = 1;
        description = "processor.max_cstate value passed on the kernel command line";
      };

      tscReliable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Pass tsc=reliable on the kernel command line";
      };
    };

    smbios = {
      manufacturer = lib.mkOption {
        type = lib.types.str;
        default = "ASUSTeK COMPUTER INC.";
        description = "SMBIOS system manufacturer string";
      };
      product = lib.mkOption {
        type = lib.types.str;
        default = "ROG CROSSHAIR X870E HERO";
        description = "SMBIOS product name string";
      };
      biosVendor = lib.mkOption {
        type = lib.types.str;
        default = "American Megatrends Inc.";
        description = "SMBIOS BIOS vendor string";
      };
      biosVersion = lib.mkOption {
        type = lib.types.str;
        default = "2101";
        description = "SMBIOS BIOS version string";
      };
      serial = lib.mkOption {
        type = lib.types.str;
        default = "System Serial Number";
        description = "SMBIOS system serial number";
      };
      socketPrefix = lib.mkOption {
        type = lib.types.str;
        default = "AM5";
        description = "SMBIOS processor socket designator prefix";
      };
    };

    spoofMac = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Spoof guest NIC MAC address with a realistic OUI prefix";
    };

    macPrefix = lib.mkOption {
      type = lib.types.str;
      default = "04:42:1a";
      description = "OUI prefix used when spoofMac is enabled (colon-separated hex, e.g. 04:42:1a)";
    };

    acpiSsdt = {
      spoofedDevices = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Include spoofed ACPI device entries in the SSDT table";
      };
      fakeBattery = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Include a fake ACPI battery device in the SSDT table";
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
