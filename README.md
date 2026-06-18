# vfio-stealth-nix

<!-- BEGIN generated:badges -->
[![CI](https://github.com/Daaboulex/vfio-stealth-nix/actions/workflows/ci.yml/badge.svg)](https://github.com/Daaboulex/vfio-stealth-nix/actions/workflows/ci.yml)
[![NixOS unstable](https://img.shields.io/badge/NixOS-unstable-78C0E8?logo=nixos&logoColor=white)](https://nixos.org)
[![License: GPL-2.0](https://img.shields.io/badge/License-GPL--2.0-blue.svg)](./LICENSE)
<!-- END generated:badges -->

<!-- BEGIN generated:upstream -->
## Upstream

| | |
|---|---|
| **Project** | Custom |
| **License** | N/A |
| **Tracked** | Custom update script |

<!-- END generated:upstream -->

## Overview

vfio-stealth-nix is a NixOS module that makes VFIO/KVM virtual machines indistinguishable from bare-metal hardware. It provides hardware-accurate VM configuration -- realistic hardware identity instead of hypervisor artifacts.

## Documentation

For long-form references beyond the quick start below, see:

- [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) — directory layout, component-to-file mapping, kernel-integration boundary
- [`docs/BUILD.md`](docs/BUILD.md) — operator commands: dev shell, formatters, hooks, tests, update contract, troubleshooting
- [`docs/OPTIONS.md`](docs/OPTIONS.md) — canonical `myModules.vfio.stealth.*` option reference

## Components

| Package | Description |
|---|---|
| **qemu-stealth** | Patched QEMU with AutoVirt AMD hardware-emulation patches + configurable hardware identifiers (EDID, ACPI OEM, disk/optical models, SCSI vendor, disk serial customization, fw_cfg DMA signature) |
| **ovmf-stealth** | Patched EDK2/OVMF firmware: clears VirtualMachine bit in SMBIOS Type 0, replaces Red Hat PCI vendor IDs, overrides ACPI OEM fields, strips BGRT boot logo (VMAware indicator). Overridable: `secureBoot`, `msVarsTemplate`, `tpmSupport` |
| **acpi-ssdt-stealth** | Compiled ACPI SSDT tables providing emulated embedded controller, fan, thermal zone, battery, power/sleep buttons, timers |
| **smbios-stealth-tables** | Binary SMBIOS tables for types QEMU cannot build via CLI (Type 7 cache, Types 26-29 probes) |
| **smbios-extract** | Host SMBIOS dump + anonymization tool for extracting real hardware strings to inject into VM config |

## Detection Vectors Covered

| Vector | Technique | Where |
|---|---|---|
| CPUID hypervisor bit | Cleared via `kvm.hidden` + Hyper-V vendor_id override | `lib.nix` (libvirt features) |
| CPUID leaf 0 vendor string | Hypervisor-Phantom: intercept at SVM level, override to AuthenticAMD, re-enter guest without full exit | `kernel/cpuid-patch.nix` |
| CPUID interception timing | Disabled entirely via cpuidPassthrough — guest CPUID runs at native speed | `kernel/cpuid-disable.nix` |
| RDTSC/RDTSCP timing | BetterTiming: track cumulative VM-exit time, subtract from TSC reads (RDTSC + RDTSCP handlers with compensated values) | `kernel/timing-patch.nix` |
| MSR_IA32_TSC reads | Compensated TSC value returned via patched `kvm_get_msr_common` | `kernel/timing-patch.nix` |
| IA32_APERF/MPERF MSR | Passthrough via `-cpu host,aperfmperf=on` (covers IET-based detection) | `lib.nix` (QEMU args) |
| SMBIOS Type 0 (BIOS) | Vendor, version, date, release override | `module.nix` options, `lib.nix` sysinfo |
| SMBIOS Type 1 (System) | Manufacturer, product, serial, family, UUID | `module.nix` options, `lib.nix` sysinfo |
| SMBIOS Type 2 (Baseboard) | Manufacturer, product, version, serial, asset tag, location | `lib.nix` sysinfo |
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
| ACPI SSDT devices | Emulated EC, fan, thermal zone, power/sleep buttons, timers | `acpi/spoofed-devices.dsl` |
| ACPI emulated battery | Control Method Battery (PNP0C0A) with BIF/BST methods | `acpi/fake-battery.dsl` |
| EDID display identity | Monitor manufacturer, model, serial, product code, DPI, manufacture date | `qemu/package.nix` arguments |
| Disk model string | IDE/SCSI disk model override in QEMU source | `qemu/package.nix` postPatch |
| Optical drive model | IDE/ATAPI optical drive model override | `qemu/package.nix` postPatch |
| MAC address OUI | Configurable OUI prefix for guest NIC | `module.nix` options |
| Hyper-V enlightenments | Full enlightenment set (relaxed, vapic, spinlocks, stimer, frequencies, etc.) with vendor_id override | `lib.nix` features |
| KVM feature hiding | `kvm.hidden`, `hint-dedicated`, `poll-control` | `lib.nix` features |
| VMPort | Disabled | `lib.nix` features |
| Clock/timer emulation | kvmclock disabled, hypervclock enabled (enlightened mode) or disabled (hidden mode), native TSC, HPET present | `lib.nix` clock config |
| OVMF VirtualMachine bit | Cleared in SMBIOS Type 0 via EDK2 patch | `ovmf/package.nix` |
| OVMF PCI vendor IDs | Red Hat IDs replaced with AMD/Intel | `ovmf/package.nix` |
| VirtIO device identifiers | Balloon, RNG, tablet devices stripped from VM config | `lib.nix` devicesToRemove |
| SMBIOS Type 11 (OEM Strings) | Populated with realistic entries (empty Type 11 is a VM indicator) | `module.nix` options, `lib.nix` QEMU args |
| SMBIOS Type 41 (Onboard Devices) | Ethernet + SATA controller entries (prevents empty Win32_OnBoardDevice) | `module.nix` options, `lib.nix` QEMU args |
| Disk serial string | IDE drive serial set to realistic WD format instead of AutoVirt blank | `qemu/package.nix` postPatch |
| fw_cfg DMA signature + ACPI device | 8-byte DMA signature changed from "QEMU CFG" to "QCOM CFG"; fw_cfg ACPI device node removed from DSDT (4-byte probe at selector 0x0000 still reads "QEMU") | AutoVirt patch via `qemu/package.nix` |
| KVM paravirt MSR enforcement | `kvm-pv-enforce-cpuid=on` ensures guest_pv_has() rejects pvclock/steal-time MSRs when kvm.hidden=on | `lib.nix` QEMU args |
| KVM hypercall patching | Disabled: emulator_fix_hypercall always injects #UD (bare-metal behavior on VMCALL/VMMCALL) | `kernel/timing-patch.nix` |
| SVM instruction interception | `kvm_amd.vls=0` + `kvm_amd.vgif=0` force VMLOAD/VMSAVE/STGI/CLGI interception | `module.nix` kernel params |
| OVMF boot logo / BGRT | TianoCore LogoDxe + BootGraphicsResourceTableDxe stripped (VMAware CRC indicator) | `ovmf/package.nix` |
| ACPI thermal zone fluctuation | Timer()-based dynamic temperature in CPU + VRM thermal zones (handles static-value detection) | `acpi/sensor-probes.dsl` |
| QEMU pvpanic device | Consumer excludes `<panic>` from domain XML; verified by `verify-host.sh` | `guest/verify-host.sh` |
| OVMF debug output port | DebugLib redirected to null | `ovmf/package.nix` |
| Registry SCSI DEVICEMAP | Cleaned via guest-side registry script | `guest/cleanup-registry.ps1` |

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

All options live under `myModules.vfio.stealth.*`. Module options, build-time `qemu-stealth` arguments, and read-only outputs are documented in [`docs/OPTIONS.md`](docs/OPTIONS.md).

## Example Configurations

> **WARNING: Do not use these exact values.** Detection software can identify
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
    biosDate = "02/15/2025";
    biosRelease = "2.3";
    baseBoardVersion = "Rev 1.02";
    baseBoardSerial = "K716234029";
    serial = "K716234029";
    socketPrefix = "AM5";
    cache = {
      l1 = 512;
      l2 = 16384;
      l3 = 65536;
    };
    oemStrings = [
      "Default string"
      "Default string"
      "TOMAHAWK"
      "Default string"
    ];
    memory = {
      manufacturer = "Corsair";
      partNumber = "CMK32GX5M2B5600C36";
      speed = 5600;
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
      edidSerial = "EX2780Q";
      edidProductCode = "0x8532";
      edidDpi = 109;
      edidWeek = 24;
      edidYear = 2022;
      acpiOemId = "MSI_NB";
      acpiOemTableId = "MEGABOOK";
      diskModel = "WDC WD10EZEX-00WN4A0    ";
      diskSerial = "WD-WMC4T0D2XYZA";
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
    biosDate = "03/22/2025";
    biosRelease = "2.0";
    baseBoardVersion = "x.x";
    baseBoardSerial = "SN220847001234";
    serial = "SN220847001234";
    socketPrefix = "AM5";
    memory = {
      manufacturer = "Crucial Technology";
      partNumber = "CT16G56C46S5.M8G1";
      speed = 5600;
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
7. `Win32_Battery` -- should exist if emulated battery loaded (WARN if missing)
8. `Win32_PhysicalMemory` -- should have DIMM info (WARN if missing)
9. `HypervisorPresent` -- CPUID hypervisor bit (should be False)

**Interpreting results:**

- **PASS** -- vector is properly configured
- **FAIL** -- detection vector exposed, fix before running game security software
- **WARN** -- optional feature not active (ACPI SSDT tables may not be loaded)

```powershell
.\verify-stealth.ps1
# Expected output: "0 failures, 0 warnings"
```

## Kernel Integration

The module exposes `myModules.vfio.stealth._kernelPostPatch` -- a shell script string that patches the kernel source tree via sed/awk. It combines BetterTiming (TSC compensation) and CPUID emulation (Hypervisor-Phantom) based on your config.

The patches target function signatures and symbol names, not line numbers, for resilience across kernel versions. CI validates anchors against nixpkgs latest kernel on every push.

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
- Enables RDTSC + RDTSCP interception in SVM `init_vmcb`
- Adds `handle_rdtsc_interception` handler that returns compensated TSC
- Adds `handle_rdtscp_interception` handler returning compensated TSC + TSC_AUX in ECX
- Wraps CPUID, WBINVD, XSETBV, INVD exit handlers to tag `exit_reason=0xDEAD` for timing compensation
- Disables KVM hypercall instruction patching (`emulator_fix_hypercall` always injects #UD)

**CPUID emulation** (`cpuid-patch.nix`):

- Intercepts CPUID leaf 0 inside `svm_vcpu_run` after `svm_vcpu_enter_exit` returns
- Overrides vendor string to `AuthenticAMD` with max leaf `0x20`
- Advances RIP and re-enters guest via `goto reenter_guest_fast` (no full VM exit)
- Clears RDTSC/RDTSCP interception bits (BetterTiming re-enables RDTSC if active)

**CPUID passthrough** (`kernel/cpuid-disable.nix`) — Exit-less CPUID:

- Clears `INTERCEPT_CPUID` in `init_vmcb` and `pre_svm_run`
- Guest executes CPUID at native hardware speed (zero VM exit)
- AMD SVM loads guest XCR0 from VMCB — leaf 0xD naturally consistent
- Hardware returns AuthenticAMD with no hypervisor bit (synthetic, absent in real CPUID)
- Side effect: Hyper-V enlightenments invisible to guest (Windows uses TSC directly)

## Upstream Tracking

Two upstream projects are tracked and auto-updated daily via GitHub Actions (`update.yml`):

- [Scrut1ny/AutoVirt](https://github.com/Scrut1ny/AutoVirt) -- QEMU AMD patch + EDK2 hardware-emulation patches
- [SamuelTulach/BetterTiming](https://github.com/SamuelTulach/BetterTiming) -- TSC compensation technique

The update workflow runs on a daily cron schedule. On success, it commits and pushes the flake input update automatically. On failure, it creates a GitHub issue with the build log and pushes the attempted update to a branch for manual recovery.

## Development

```bash
nix develop                  # dev shell with pre-commit hooks
nix flake check --no-build   # eval check (fast)
nix build                    # build packages
nix fmt                      # format with treefmt
```

## Known Limitations

These represent current boundaries of software-level VM stealth:

| Limitation | Reason |
|---|---|
| **Remote TPM attestation** | Cloud-based attestation (e.g. Microsoft Azure Attestation) verifies TPM endorsement keys against manufacturer databases. swtpm keys are not manufacturer-signed and cannot pass remote attestation. No software-only fix. |
| **VBS-dependent detection** | Detection stacks requiring Virtualization-Based Security (VBS) + `hypervisorlaunchtype=auto` are incompatible with standard KVM guests. VBS means Windows must run under its own Hyper-V hypervisor. |
| **Boot-time kernel drivers** | Kernel-mode detection drivers that load before the OS can detect hypervisors via multiple vectors beyond CPUID. swtpm satisfies TPM 2.0 presence checks, but detection is independent of TPM state. |
| **PCI subsystem ID `1af4:1100`** | QEMU hardcodes Red Hat subsystem vendor:device on ICH9 LPC, AHCI, SMBus, and HDA devices. Not user-configurable on most chipset devices; requires QEMU source patches to override. |
| **fw_cfg I/O port probe** | Reading 4 bytes from fw_cfg selector 0x0000 returns "QEMU". The DMA signature is patched but the legacy I/O path (ports 0x510/0x511) remains. Requires QEMU source patch to fully suppress. |
| **Context-switch timing oracles** | Detection libraries (VMAware v2.5+) use context-switch-based clocks independent of TSC. Claims immunity to all TSC/hardware clock spoofing including BetterTiming. An evolving area. |
| **XSAVE state identification** | Detection of CPUID interception handling via XCR0/XSS size discrepancies. On AMD SVM, VMRUN loads guest XCR0 from the VMCB, making leaf 0xD naturally consistent -- an evolving area. |
| **NPT page-walk latency** | Nested Page Table translation adds ~10-20ns per TLB miss. Detectable in theory via microbenchmarks, but high noise floor makes it impractical for false-positive rates. No known detection software uses this. |
| **Performance variance** | ML-based detection of frame-time jitter from VM exits. BetterTiming + `cpuidPassthrough` substantially reduce but cannot eliminate this surface. |

## License

GPL-2.0 (kernel patches mandate GPL)

<!-- BEGIN generated:footer -->
---

*Maintained as part of the [Daaboulex](https://github.com/Daaboulex) NixOS ecosystem.*
<!-- END generated:footer -->
