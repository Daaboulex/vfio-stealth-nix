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
  # We call them with { inherit lib; } as documented in each file's header.
  timingPatchScript = import ./kernel/timing-patch.nix { inherit lib; };
  cpuidPatchScript = import ./kernel/cpuid-patch.nix { inherit lib; };

  # Build a combined postPatch fragment from whichever patches are enabled.
  extraPostPatch =
    lib.optionalString cfg.timing.enable timingPatchScript
    + lib.optionalString cfg.cpuidSpoof.enable cpuidPatchScript;

  # Overlay the current kernel with our postPatch additions.
  # boot.kernelPatches only accepts { name, patch, structuredExtraConfig,
  # extraConfig, features } — there is no postPatch key. Sed-based source
  # modifications therefore require overrideAttrs on the kernel derivation.
  patchedKernel = pkgs.linux.overrideAttrs (old: {
    postPatch = (old.postPatch or "") + extraPostPatch;
  });
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
        default = "American Megatrends International, LLC.";
        description = "SMBIOS BIOS vendor string";
      };
      biosVersion = lib.mkOption {
        type = lib.types.str;
        default = "1401";
        description = "SMBIOS BIOS version string";
      };
      serial = lib.mkOption {
        type = lib.types.str;
        default = "M8OAMB000000000";
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
    # Apply kernel source patches via overrideAttrs on the kernel derivation.
    # NOTE: boot.kernelPatches does NOT support a postPatch key — its items are
    # limited to { name, patch, structuredExtraConfig, extraConfig, features }
    # and the patch value must be a file/derivation, not a shell script string.
    # Our BetterTiming and CPUID patches are sed-based source modifications, so
    # we overlay the kernel package instead.
    boot.kernelPackages = lib.mkIf (cfg.timing.enable || cfg.cpuidSpoof.enable) (
      pkgs.linuxPackagesFor patchedKernel
    );

    boot.kernelParams = [
      "processor.max_cstate=${toString cfg.kernelParams.maxCState}"
    ]
    ++ lib.optionals cfg.kernelParams.tscReliable [ "tsc=reliable" ];
  };
}
