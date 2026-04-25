# vfio-stealth-nix

[![CI](https://github.com/Daaboulex/vfio-stealth-nix/actions/workflows/ci.yml/badge.svg)](https://github.com/Daaboulex/vfio-stealth-nix/actions/workflows/ci.yml)
[![License](https://img.shields.io/github/license/Daaboulex/vfio-stealth-nix)](./LICENSE)
[![NixOS](https://img.shields.io/badge/NixOS-unstable-78C0E8?logo=nixos&logoColor=white)](https://nixos.org)
[![Last commit](https://img.shields.io/github/last-commit/Daaboulex/vfio-stealth-nix)](https://github.com/Daaboulex/vfio-stealth-nix/commits)
[![Stars](https://img.shields.io/github/stars/Daaboulex/vfio-stealth-nix?style=flat)](https://github.com/Daaboulex/vfio-stealth-nix/stargazers)
[![Issues](https://img.shields.io/github/issues/Daaboulex/vfio-stealth-nix)](https://github.com/Daaboulex/vfio-stealth-nix/issues)

## Upstream

This is a **multi-upstream Nix integration** combining several anti-detection projects into one declarative NixOS module. All credit for the core techniques goes to:

- **AutoVirt** — QEMU AMD patches + EDK2/OVMF anti-detection patches: [Scrut1ny/AutoVirt](https://github.com/Scrut1ny/AutoVirt)
- **BetterTiming** — TSC compensation kernel patch technique: [SamuelTulach/BetterTiming](https://github.com/SamuelTulach/BetterTiming)
- **Hypervisor-Phantom** — CPUID leaf 0 spoofing technique
- **Original glue + module + ACPI SSDT compilation**: this repo

The update workflow runs on a daily cron schedule. On success, it commits and pushes the flake input update automatically. On failure, it creates a GitHub issue with the build log and pushes the attempted update to a branch for manual recovery.

Licensed under [MIT](./LICENSE) for the Nix-side glue + ACPI SSDT files. Each upstream patch retains its own license — see the linked repos.

## Overview

vfio-stealth-nix is a NixOS module that makes VFIO/KVM virtual machines indistinguishable from bare-metal hardware. It is designed for **legitimate VM gaming** where users own the hardware, the games, and the operating system licenses. The goal is to prevent false-positive VM detection that locks paying customers out of games they own, simply because they run them in a VM for driver isolation, security, or multi-OS workflows.

This is **not a cheat tool**. It does not modify game memory, inject code, or bypass integrity checks. It makes the VM environment report truthful hardware characteristics instead of exposing hypervisor artifacts that have nothing to do with cheating.

## Documentation

For long-form references beyond the quick start below, see:

- [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) — directory layout, component-to-file mapping, kernel-integration boundary
- [`docs/BUILD.md`](docs/BUILD.md) — operator commands: dev shell, formatters, hooks, tests, update contract, troubleshooting
- [`docs/OPTIONS.md`](docs/OPTIONS.md) — full `myModules.vfio.stealth.*` option reference (mirrors the Configuration Reference section)

## Components

| Package | Description |
|---|---|
| **qemu-stealth** | Patched QEMU with AutoVirt AMD anti-detection patches + configurable hardware fingerprints (EDID, ACPI OEM, disk/optical models) |
| **ovmf-stealth** | Patched EDK2/OVMF firmware: clears VirtualMachine bit in SMBIOS Type 0, replaces Red Hat PCI vendor IDs, spoofs ACPI OEM fields |
| **acpi-ssdt-stealth** | Compiled ACPI SSDT tables providing fake embedded controller, fan, thermal zone, battery, power/sleep buttons, timers |
| **smbios-extract** | Host SMBIOS dump + anonymization tool for extracting real hardware strings to inject into VM config |

## Detection Vectors Covered

| Vector | Technique | Where |
|---|---|---|
| CPUID hypervisor bit | Cleared via `kvm.hidden` + Hyper-V vendor_id spoofing | `lib.nix` (libvirt features) |
| CPUID leaf 0 vendor string | Hypervisor-Phantom: intercept at SVM level, spoof AuthenticAMD, re-enter guest without full exit | `kernel/cpuid-patch.nix` |
| RDTSC/RDTSCP timing | BetterTiming: track cumulative VM-exit time, subtract from TSC reads | `kernel/timing-patch.nix` |
| MSR_IA32_TSC reads | Compensated TSC value returned via patched `kvm_get_msr_common` | `kernel/timing-patch.nix` |
| IA32_APERF/MPERF MSR | Passthrough via `kvm-disable-exits=aperfmperf` (defeats IET-based detection) | `lib.nix` (QEMU args) |
| SMBIOS Type 0 (BIOS) | Vendor + version spoofing | `module.nix` options, `lib.nix` sysinfo |
| SMBIOS Type 1 (System) | Manufacturer, product, serial, family, UUID | `module.nix` options, `lib.nix` sysinfo |
| SMBIOS Type 2 (Baseboard) | Manufacturer + product | `lib.nix` sysinfo |
| SMBIOS Type 3 (Chassis) | Manufacturer, version, serial, asset tag | `lib.nix` QEMU args |
| SMBIOS Type 4 (Processor) | Socket, manufacturer, version, speed | `lib.nix` QEMU args (via cpuIdentity) |
| SMBIOS Type 7 (Cache) | L1/L2/L3 cache designation and sizes | `lib.nix` QEMU args |
| SMBIOS Type 8 (Port Connector) | USB port descriptors | `lib.nix` QEMU args |
| SMBIOS Type 9 (System Slots) | PCIe slot designation and type | `lib.nix` QEMU args |
| SMBIOS Type 17 (Memory) | DIMM manufacturer, part number, speed, size, count | `module.nix` options, `lib.nix` QEMU args |
| SMBIOS Type 26 (Voltage Probe) | Voltage probe description + min/max | `lib.nix` QEMU args |
| SMBIOS Type 27 (Cooling Device) | Cooling device type + speed | `lib.nix` QEMU args |
| SMBIOS Type 28 (Temperature Probe) | Temperature probe description + min/max | `lib.nix` QEMU args |
| SMBIOS Type 29 (Current Probe) | Current probe description + min/max | `lib.nix` QEMU args |
| ACPI table OEM IDs | Replaced ALASKA/AMI defaults with configurable strings (6-char + 8-char) | `qemu/package.nix` postPatch |
| ACPI SSDT devices | Fake EC, fan, thermal zone, power/sleep buttons, timers | `acpi/spoofed-devices.dsl` |
| ACPI fake battery | Control Method Battery (PNP0C0A) with BIF/BST methods | `acpi/fake-battery.dsl` |
| EDID display identity | Monitor manufacturer, model, serial, product code, DPI, manufacture date | `qemu/package.nix` arguments |
| Disk model string | IDE/SCSI disk model spoofing in QEMU source | `qemu/package.nix` postPatch |
| Optical drive model | IDE/ATAPI optical drive model spoofing | `qemu/package.nix` postPatch |
| MAC address OUI | Configurable OUI prefix for guest NIC | `module.nix` options |
| Hyper-V enlightenments | Full enlightenment set (relaxed, vapic, spinlocks, stimer, frequencies, etc.) with vendor_id spoofing | `lib.nix` features |
| KVM feature hiding | `kvm.hidden`, `hint-dedicated`, `poll-control` | `lib.nix` features |
| VMPort | Disabled | `lib.nix` features |
| Clock/timer spoofing | kvmclock disabled, hypervclock + native TSC enabled, HPET disabled | `lib.nix` clock config |
| OVMF VirtualMachine bit | Cleared in SMBIOS Type 0 via EDK2 patch | `ovmf/package.nix` |
| OVMF PCI vendor IDs | Red Hat IDs replaced with AMD/Intel | `ovmf/package.nix` |
| VirtIO device fingerprints | Balloon, RNG, tablet devices stripped from VM config | `lib.nix` devicesToRemove |

## Anti-Cheat Compatibility

| Anti-Cheat | Status | Notes |
|---|---|---|
| VAC | Works | Light detection, user-mode only. CPUID + SMBIOS spoofing sufficient. |
| EAC | Partial | Config-dependent. March 2026 crackdown added new timing checks. Requires full BetterTiming + APERF/MPERF passthrough. |
| BattlEye | Difficult | Cat-and-mouse with timing-based detection. Works intermittently; kernel updates may break it. |
| Vanguard | Blocked | Hardware attestation via TPM 2.0 + Secure Boot chain. Cannot be bypassed by software spoofing. |
| FACEIT | Blocked | Requires virtualization disabled at BIOS level. Detects any hypervisor regardless of hiding. |
| nProtect | Works | CPUID + SMBIOS spoofing sufficient for GameGuard. |

## Quick Start

Add as a flake input:

```nix
vfio-stealth = {
  url = "github:Daaboulex/vfio-stealth-nix";
  inputs.nixpkgs.follows = "nixpkgs";
};
```

Import the overlay and NixOS module:

```nix
imports = [ inputs.vfio-stealth.nixosModules.default ];
nixpkgs.overlays = [ inputs.vfio-stealth.overlays.default ];
```

Enable stealth with your own hardware strings:

```nix
myModules.vfio.stealth = {
  enable = true;
  smbios = {
    manufacturer = "Your Motherboard Manufacturer";
    product = "Your Motherboard Model";
  };
};
```

## Configuration Reference

All options live under `myModules.vfio.stealth`.

### Core

| Option | Type | Default | Description | Detection Vector |
|---|---|---|---|---|
| `enable` | `bool` | `false` | Enable the VFIO stealth anti-detection stack | -- |
| `stripVirtio` | `bool` | `true` | Remove VirtIO balloon, RNG, and tablet devices from VM config | VirtIO PCI vendor ID fingerprinting |
| `spoofMac` | `bool` | `true` | Spoof guest NIC MAC address with a realistic OUI prefix | MAC address OUI reveals VM NIC vendor |
| `macPrefix` | `str` | `"04:42:1a"` | OUI prefix for spoofed MAC address (colon-separated hex) | MAC address OUI |
| `aperfMperf` | `bool` | `true` | Pass through IA32_APERF/MPERF MSRs to guest. Requires kernel 6.18+ | IET-based VM detection via MSR absence |

### Kernel

| Option | Type | Default | Description | Detection Vector |
|---|---|---|---|---|
| `timing.enable` | `bool` | `true` | Apply BetterTiming TSC compensation kernel patch | RDTSC/RDTSCP timing attacks |
| `cpuidSpoof.enable` | `bool` | `true` | Apply CPUID leaf 0 spoofing via Hypervisor-Phantom technique | CPUID vendor string + hypervisor bit |
| `kernelParams.maxCState` | `int` | `1` | `processor.max_cstate` kernel parameter value | TSC stability (deep C-states cause drift) |
| `kernelParams.tscReliable` | `bool` | `true` | Pass `tsc=reliable` on kernel command line | TSC source selection |

### SMBIOS

| Option | Type | Default | Description | Detection Vector |
|---|---|---|---|---|
| `smbios.manufacturer` | `str` | `"ASUSTeK COMPUTER INC."` | System and baseboard manufacturer (Types 1, 2) | Win32_ComputerSystem.Manufacturer |
| `smbios.product` | `str` | `"ROG CROSSHAIR X870E HERO"` | System and baseboard product name (Types 1, 2) | Win32_ComputerSystem.Model |
| `smbios.biosVendor` | `str` | `"American Megatrends Inc."` | BIOS vendor string (Type 0) | Win32_BIOS.Manufacturer |
| `smbios.biosVersion` | `str` | `"2101"` | BIOS version string (Type 0) | Win32_BIOS.SMBIOSBIOSVersion |
| `smbios.serial` | `str` | `"System Serial Number"` | System serial number (Type 1) | Win32_ComputerSystem.SerialNumber |
| `smbios.socketPrefix` | `str` | `"AM5"` | Processor socket designator prefix (Type 4) | Win32_Processor.SocketDesignation |
| `smbios.memory.manufacturer` | `str` | `"G.Skill International"` | DIMM manufacturer (Type 17) | Win32_PhysicalMemory.Manufacturer |
| `smbios.memory.partNumber` | `str` | `"F5-6000J3040G32G"` | DIMM part number (Type 17) | Win32_PhysicalMemory.PartNumber |
| `smbios.memory.speed` | `int` | `6000` | Memory speed in MT/s (Type 17) | Win32_PhysicalMemory.Speed |
| `smbios.memory.size` | `int` | `16384` | DIMM size in MB per module (Type 17) | Win32_PhysicalMemory.Capacity |
| `smbios.memory.count` | `int` | `2` | Number of DIMMs to report (Type 17) | Win32_PhysicalMemory count |

### EDID (Display Identity)

These are build-time arguments to `qemu-stealth` (passed via overlay or `callPackage`), not NixOS module options.

| Argument | Default | Description | Detection Vector |
|---|---|---|---|
| `edidManufacturer` | `"DEL"` | 3-letter EDID manufacturer ID | Monitor manufacturer fingerprint |
| `edidModelAbbrev` | `"DEL     "` | 8-char padded manufacturer abbreviation | EDID block manufacturer field |
| `edidModel` | `"DEL AW2521HFA   "` | 16-char padded monitor model string | EDID block model field |
| `edidSerial` | `"AW2521HFA"` | Monitor serial string | EDID serial number |
| `edidProductCode` | `"0xa161"` | EDID product code (hex) | EDID product code field |
| `edidDpi` | `102` | Monitor DPI | EDID physical size calculation |
| `edidWeek` | `18` | Manufacture week (1-52) | EDID manufacture date |
| `edidYear` | `2021` | Manufacture year | EDID manufacture date |

### Disk

Build-time arguments to `qemu-stealth`:

| Argument | Default | Description | Detection Vector |
|---|---|---|---|
| `diskModel` | `"Samsung SSD 870 EVO 1TB "` | IDE/SCSI disk model string (24 chars, space-padded) | Disk model reveals QEMU default |
| `opticalModel` | `"ASUS DRW-24B1ST   c    "` | IDE/ATAPI optical drive model string (24 chars) | Optical drive model reveals QEMU |

### ACPI

| Option | Type | Default | Description | Detection Vector |
|---|---|---|---|---|
| `acpiSsdt.spoofedDevices` | `bool` | `true` | Include spoofed ACPI devices (EC, fan, thermal zone, power/sleep buttons, timers) in SSDT | Missing EC/fan/thermal = VM fingerprint |
| `acpiSsdt.fakeBattery` | `bool` | `true` | Include fake ACPI battery device in SSDT | Missing battery can flag VM detection |

Build-time arguments to `qemu-stealth` for ACPI OEM strings:

| Argument | Default | Description | Detection Vector |
|---|---|---|---|
| `acpiOemId` | `"ASUS  "` | 6-char padded ACPI OEM ID (replaces ALASKA) | ACPI table OEM ID reveals QEMU |
| `acpiOemTableId` | `"ASUS    "` | 8-char padded ACPI OEM Table ID (replaces A M I) | ACPI table OEM Table ID |

### Network

| Option | Type | Default | Description | Detection Vector |
|---|---|---|---|---|
| `spoofMac` | `bool` | `true` | Enable MAC address OUI spoofing | OUI prefix identifies virtual NIC vendor |
| `macPrefix` | `str` | `"04:42:1a"` | OUI prefix (first 3 octets) | MAC OUI lookup reveals VM |

### CPU Identity

CPU identity is passed per-VM via `mkStealthFeatures` in `lib.nix`, not as module options:

| Argument | Description | Detection Vector |
|---|---|---|
| `cpuIdentity.modelId` | CPU model string for SMBIOS Type 4 + QEMU `-global cpu.model-id` | Win32_Processor.Name |
| `cpuIdentity.maxSpeed` | Max CPU speed in MHz (Type 4) | Win32_Processor.MaxClockSpeed |
| `cpuIdentity.currentSpeed` | Current CPU speed in MHz (Type 4) | Win32_Processor.CurrentClockSpeed |

### Cache (SMBIOS Type 7)

Cache entries are hardcoded in `lib.nix` QEMU args with realistic L1/L2/L3 sizes. They populate `Win32_CacheMemory`, which is empty by default on VMs and used as a detection signal.

| Level | Designation | Size |
|---|---|---|
| L1 | L1 Cache | 512 KB |
| L2 | L2 Cache | 8192 KB |
| L3 | L3 Cache | 98304 KB |

## Example Configurations

> **WARNING: Do not use these exact values.** Anti-cheat systems can fingerprint
> known stealth configurations. Use your own realistic hardware strings
> from `dmidecode`, `edid-decode`, or manufacturer websites.

### Example 1: MSI + Corsair + BenQ + WD

```nix
myModules.vfio.stealth = {
  enable = true;
  smbios = {
    manufacturer = "Micro-Star International Co., Ltd.";
    product = "MAG X670E TOMAHAWK WIFI";
    biosVendor = "American Megatrends International, LLC.";
    biosVersion = "7E12vAH";
    serial = "K716234029";
    socketPrefix = "AM5";
    memory = {
      manufacturer = "Corsair";
      partNumber = "CMK32GX5M2B5600C36";
      speed = 5600;
      size = 16384;
      count = 2;
    };
  };
  macPrefix = "2c:f0:5d";  # Peplink OUI
};

# QEMU overlay with matching hardware strings
nixpkgs.overlays = [
  (final: prev: {
    qemu-stealth = prev.qemu-stealth.override {
      edidManufacturer = "BNQ";
      edidModelAbbrev = "BNQ     ";
      edidModel = "BenQ EX2780Q     ";
      edidSerial = "EX2780Q";
      edidProductCode = "0x8532";
      edidDpi = 109;
      edidWeek = 24;
      edidYear = 2022;
      acpiOemId = "MSI_NB";
      acpiOemTableId = "MEGABOOK";
      diskModel = "WDC WD10EZEX-00WN4A0    ";
      opticalModel = "HL-DT-ST DVDRAM GH24NSC0";
    };
  })
];
```

### Example 2: Gigabyte + Crucial + LG + Seagate

```nix
myModules.vfio.stealth = {
  enable = true;
  smbios = {
    manufacturer = "Gigabyte Technology Co., Ltd.";
    product = "B650 AORUS ELITE AX";
    biosVendor = "American Megatrends Inc.";
    biosVersion = "F20";
    serial = "SN220847001234";
    socketPrefix = "AM5";
    memory = {
      manufacturer = "Crucial Technology";
      partNumber = "CT16G56C46S5.M8G1";
      speed = 5600;
      size = 16384;
      count = 4;
    };
  };
  macPrefix = "70:85:c2";  # ASRock OUI
};

# QEMU overlay with matching hardware strings
nixpkgs.overlays = [
  (final: prev: {
    qemu-stealth = prev.qemu-stealth.override {
      edidManufacturer = "GSM";
      edidModelAbbrev = "GSM     ";
      edidModel = "LG ULTRAGEAR     ";
      edidSerial = "27GP850";
      edidProductCode = "0x5bbf";
      edidDpi = 109;
      edidWeek = 38;
      edidYear = 2023;
      acpiOemId = "GBTNB ";
      acpiOemTableId = "GBYTE   ";
      diskModel = "ST2000DM008-2UB102      ";
      opticalModel = "ATAPI iHAS124   Y       ";
    };
  })
];
```

## Guest-Side Setup

Two PowerShell scripts in `guest/` handle cleanup and verification inside the Windows VM.

### cleanup-registry.ps1

Removes QEMU/KVM/VirtIO registry artifacts left behind from before stealth was configured, or from VirtIO driver installation. Targets:

- **SMBIOS registry entries** (`HKLM:\HARDWARE\DESCRIPTION\System\BIOS`) -- overwrites leaked QEMU/Bochs strings
- **VirtIO service keys** (`CurrentControlSet\Services\VirtIO*`, `viostor`, `vioscsi`, `netkvm`, `Balloon`) -- removes driver service remnants
- **QEMU/VirtIO PCI enumeration** (`Enum\PCI\VEN_1AF4*`, `VEN_1B36*`, `VEN_1234*`) -- removes cached device entries
- **QEMU Guest Agent service** -- removes `QEMU Guest Agent` service key if present

**When to run:** Once, after applying host-side vfio-stealth-nix configuration for the first time, or after installing/removing VirtIO guest tools.

```powershell
# Right-click PowerShell -> Run as Administrator
.\cleanup-registry.ps1
# Reboot after running
```

### verify-stealth.ps1

Read-only verification script that checks detection vectors from inside the Windows guest. Does NOT require Administrator. Checks:

1. `Win32_ComputerSystem.Manufacturer` -- flags QEMU, Bochs, VMware, Xen, KVM
2. `Win32_BIOS.Manufacturer` -- flags SeaBIOS, Bochs BIOS
3. `Win32_BaseBoard.Manufacturer` -- flags QEMU, Oracle, Microsoft
4. VM-specific Windows services -- VBoxService, VMTools, Hyper-V integration, QEMU GA
5. PCI device vendor IDs -- VEN_1AF4 (VirtIO), VEN_1B36 (QEMU PCIe), VEN_1234 (QEMU VGA)
6. `Win32_Fan` -- should exist if SSDT loaded (WARN if missing)
7. `Win32_Battery` -- should exist if fake-battery loaded (WARN if missing)
8. `Win32_PhysicalMemory` -- should have DIMM info (WARN if missing)
9. `HypervisorPresent` -- CPUID hypervisor bit (should be False)

**Interpreting results:**

- **PASS** -- vector is properly spoofed
- **FAIL** -- detection vector exposed, fix before running anti-cheat
- **WARN** -- optional feature not active (ACPI SSDT tables may not be loaded)

```powershell
.\verify-stealth.ps1
# Expected output: "0 failures, 0 warnings"
```

## Kernel Integration

The module exposes `myModules.vfio.stealth._kernelPostPatch` -- a shell script string that patches the kernel source tree via sed/awk. It combines BetterTiming (TSC compensation) and CPUID spoofing (Hypervisor-Phantom) based on your config.

The patches target function signatures and symbol names, not line numbers, for resilience across kernel versions. Currently validated against kernel 6.19.x.

### With CachyOS kernel

```nix
boot.kernelPackages = pkgs.linuxPackagesFor (
  pkgs.linuxPackages_cachyos.kernel.overrideAttrs (old: {
    postPatch = (old.postPatch or "") + config.myModules.vfio.stealth._kernelPostPatch;
  })
);
```

### With stock kernel

```nix
boot.kernelPackages = pkgs.linuxPackagesFor (
  pkgs.linux_latest.overrideAttrs (old: {
    postPatch = (old.postPatch or "") + config.myModules.vfio.stealth._kernelPostPatch;
  })
);
```

### What the patches do

**BetterTiming** (`timing-patch.nix`):
- Adds `last_exit_start` and `total_exit_time` fields to `struct kvm_vcpu`
- Wraps `vcpu_enter_guest` to measure VM-exit duration
- Patches `MSR_IA32_TSC` reads to return compensated (exit-time-subtracted) values
- Enables RDTSC interception in SVM `init_vmcb`
- Adds `handle_rdtsc_interception` handler that returns compensated TSC
- Wraps CPUID, WBINVD, XSETBV, INVD exit handlers to tag `exit_reason=123` for timing compensation

**CPUID spoofing** (`cpuid-patch.nix`):
- Intercepts CPUID leaf 0 inside `svm_vcpu_run` after `svm_vcpu_enter_exit` returns
- Spoofs vendor string to `AuthenticAMD` with max leaf `0x16`
- Advances RIP and re-enters guest via `goto reenter_guest_fast` (no full VM exit)
- Clears RDTSC/RDTSCP interception bits (BetterTiming re-enables RDTSC if active)

## Upstream Tracking

Two upstream projects are tracked and auto-updated daily via GitHub Actions (`update.yml`):

- [Scrut1ny/AutoVirt](https://github.com/Scrut1ny/AutoVirt) -- QEMU AMD patch + EDK2 anti-detection patches
- [SamuelTulach/BetterTiming](https://github.com/SamuelTulach/BetterTiming) -- TSC compensation technique

The update workflow runs on a daily cron schedule. On success, it commits and pushes the flake input update automatically. On failure, it creates a GitHub issue with the build log and pushes the attempted update to a branch for manual recovery.

## Known Limitations

These detection methods **cannot be bypassed** by software-level spoofing:

| Limitation | Reason |
|---|---|
| **TPM 2.0 hardware attestation** | The TPM chip cryptographically attests the boot chain. A VM cannot forge hardware-rooted attestation without a physical TPM passthrough, which defeats the purpose if the host also needs TPM. |
| **Secure Boot chain verification** | Anti-cheat that validates the full Secure Boot chain (bootloader signatures, kernel signing) will detect a patched kernel. The kernel patches modify KVM source, breaking any signature chain. |
| **#DB exception timing** | Single-step debug exception timing is a low-level detection vector that operates below the TSC compensation layer. No known mitigation exists for SVM. |
| **AI behavioral analysis** | Machine-learning models that analyze gameplay patterns, input timing distributions, and performance variance can flag VMs based on behavior rather than system fingerprints. No hardware spoofing addresses this. |
| **FACEIT virtualization check** | FACEIT's anti-cheat checks whether virtualization extensions are enabled in the BIOS and refuses to run inside any hypervisor, regardless of how well it is hidden. |

## License

GPL-2.0 (kernel patches mandate GPL)
