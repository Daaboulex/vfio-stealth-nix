# vfio-stealth-nix

[![CI](https://github.com/Daaboulex/vfio-stealth-nix/actions/workflows/ci.yml/badge.svg)](https://github.com/Daaboulex/vfio-stealth-nix/actions/workflows/ci.yml)
[![License](https://img.shields.io/github/license/Daaboulex/vfio-stealth-nix)](./LICENSE)
[![NixOS](https://img.shields.io/badge/NixOS-unstable-78C0E8?logo=nixos&logoColor=white)](https://nixos.org)
[![Last commit](https://img.shields.io/github/last-commit/Daaboulex/vfio-stealth-nix)](https://github.com/Daaboulex/vfio-stealth-nix/commits)
[![Stars](https://img.shields.io/github/stars/Daaboulex/vfio-stealth-nix?style=flat)](https://github.com/Daaboulex/vfio-stealth-nix/stargazers)
[![Issues](https://img.shields.io/github/issues/Daaboulex/vfio-stealth-nix)](https://github.com/Daaboulex/vfio-stealth-nix/issues)

VM anti-detection stack for NixOS — QEMU, OVMF, ACPI, SMBIOS, timing.

## Components

| Package | Description |
|---|---|
| **qemu-stealth** | Patched QEMU with AutoVirt AMD anti-detection patch + configurable hardware fingerprints |
| **ovmf-stealth** | Patched EDK2/OVMF firmware hiding VM BIOS signatures *(WIP)* |
| **acpi-ssdt-stealth** | Compiled ACPI SSDT tables — fake EC, fan, thermal zone, battery, power buttons |
| **smbios-extract** | Host SMBIOS dump + anonymization tool for VM injection |
| **Kernel patches** | BetterTiming TSC compensation + CPUID leaf 0 spoofing (via NixOS module postPatch) |

## Detection Vectors Countered

- CPUID hypervisor bit + vendor string + invalid leaf comparison
- RDTSC/RDTSCP timing attacks (dynamic cumulative VM-exit compensation)
- MSR_IA32_TSC reads
- SMBIOS/DMI tables (types 0-4, 7-9, 26-29)
- WMI sensor queries (Win32_Fan, Win32_TemperatureProbe, Win32_VoltageProbe, Win32_CacheMemory)
- ACPI table signatures and device enumeration
- PCI vendor IDs, disk model strings, EDID, audio codec
- KVM/Hyper-V feature hiding with performance enlightenments
- Clock/timer spoofing (kvmclock disabled, hypervclock + native TSC)
- MAC address OUI spoofing
- Battery/power button/embedded controller absence

## Usage

Add as a flake input:

```nix
vfio-stealth = {
  url = "github:Daaboulex/vfio-stealth-nix";
  inputs.nixpkgs.follows = "nixpkgs";
};
```

Import the overlay and NixOS module:

```nix
# In your host flake-module.nix:
imports = [ inputs.vfio-stealth.nixosModules.default ];
nixpkgs.overlays = [ inputs.vfio-stealth.overlays.default ];
```

Enable stealth:

```nix
myModules.vfio.stealth = {
  enable = true;
  smbios = {
    manufacturer = "Your Motherboard Manufacturer";
    product = "Your Motherboard Model";
  };
};
```

## Kernel Patch Integration

The module exposes `myModules.vfio.stealth._kernelPostPatch` — a shell script that patches the kernel source via sed. Apply it to your kernel build:

```nix
boot.kernelPackages = pkgs.linuxPackagesFor (
  yourKernel.overrideAttrs (old: {
    postPatch = (old.postPatch or "") + config.myModules.vfio.stealth._kernelPostPatch;
  })
);
```

The patches target function signatures (not line numbers) for kernel-version resilience.

## Upstream Tracking

- [Scrut1ny/AutoVirt](https://github.com/Scrut1ny/AutoVirt) — QEMU + EDK2 patches
- [SamuelTulach/BetterTiming](https://github.com/SamuelTulach/BetterTiming) — TSC compensation technique

Auto-updated daily via GitHub Actions.

## License

GPL-2.0 (kernel patches mandate GPL)
