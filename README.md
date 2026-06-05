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

vfio-stealth-nix is a NixOS module that makes VFIO/KVM virtual machines indistinguishable from bare-metal hardware. It is designed for **legitimate VM gaming** where users own the hardware, the games, and the operating system licenses. The goal is to prevent false-positive VM detection that locks paying customers out of games they own, simply because they run them in a VM for driver isolation, security, or multi-OS workflows.

This project provides **hardware-accurate VM configuration**. It does not modify game memory, inject code, or tamper with integrity checks. It makes the VM environment report truthful hardware characteristics instead of exposing hypervisor artifacts that have nothing to do with cheating.

## Documentation

For long-form references beyond the quick start below, see:

- [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) — directory layout, component-to-file mapping, kernel-integration boundary
- [`docs/BUILD.md`](docs/BUILD.md) — operator commands: dev shell, formatters, hooks, tests, update contract, troubleshooting
- [`docs/OPTIONS.md`](docs/OPTIONS.md) — full `myModules.vfio.stealth.*` option reference (mirrors the Configuration Reference section)

## Components

| Package | Description |
|---|---|
| **qemu-stealth** | Patched QEMU with AutoVirt AMD hardware-emulation patches + configurable hardware identifiers (EDID, ACPI OEM, disk/optical models, SCSI vendor, disk serial customization, fw_cfg probe fix) |
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
| IA32_APERF/MPERF MSR | Passthrough via `kvm-disable-exits=aperfmperf` (covers IET-based detection) | `lib.nix` (QEMU args) |
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
| fw_cfg probe signature | 4-byte fw_cfg selector 0x0000 changed from "QEMU" to "AMDK" | `qemu/package.nix` postPatch |
| KVM paravirt MSR enforcement | `kvm-pv-enforce-cpuid=on` ensures guest_pv_has() rejects pvclock/steal-time MSRs when kvm.hidden=on | `lib.nix` QEMU args |
| KVM hypercall patching | Disabled: emulator_fix_hypercall always injects #UD (bare-metal behavior on VMCALL/VMMCALL) | `kernel/timing-patch.nix` |
| SVM instruction interception | `kvm_amd.vls=0` + `kvm_amd.vgif=0` force VMLOAD/VMSAVE/STGI/CLGI interception | `module.nix` kernel params |
| OVMF boot logo / BGRT | TianoCore LogoDxe + BootGraphicsResourceTableDxe stripped (VMAware CRC indicator) | `ovmf/package.nix` |
| ACPI thermal zone fluctuation | Timer()-based dynamic temperature in CPU + VRM thermal zones (handles static-value detection) | `acpi/sensor-probes.dsl` |

## Game Security Compatibility

| Software | Status | Notes |
|---|---|---|
| VAC | Works | Light detection, user-mode only. CPUID + SMBIOS emulation sufficient. |
| EAC | Likely | Requires full BetterTiming + RDTSCP handler + APERF/MPERF passthrough + kvm-pv-enforce-cpuid. Timing checks tightened March 2026; current patch set covers known vectors. `cpuidPassthrough` recommended. |
| BattlEye | Likely | Requires full stack: BetterTiming, CPUID emulation, SMBIOS, fw_cfg probe fix, hypercall #UD injection. May 2024 update improved timing detection; `cpuidPassthrough` recommended to eliminate timing surface. |
| Vanguard | Blocked | Kernel-mode driver with boot-time loading detects hypervisors via multiple vectors beyond CPUID. swtpm satisfies TPM 2.0 presence check, but VM detection is independent of TPM state. No known working VM configuration. |
| FACEIT | Blocked | Multi-layer enforcement: TPM 2.0 + Secure Boot + IOMMU + VBS (Virtualization-Based Security) + `hypervisorlaunchtype=auto`. The VBS requirement is incompatible with standard KVM guests. |
| nProtect | Works | CPUID + SMBIOS emulation sufficient for GameGuard. |

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
| `enable` | `bool` | `false` | Enable the VFIO stealth hardware emulation stack | -- |
| `stripVirtio` | `bool` | `true` | Remove VirtIO balloon, RNG, and tablet devices from VM config | VirtIO PCI vendor ID detection |
| `spoofMac` | `bool` | `true` | Override guest NIC MAC address with a realistic OUI prefix | MAC address OUI reveals VM NIC vendor |
| `macPrefix` | `str` | `"D8:BB:C1"` | OUI prefix for overridden MAC (Realtek OUI matching ASUS X870E onboard LAN) | MAC address OUI |
| `aperfMperf` | `bool` | `true` | Pass through IA32_APERF/MPERF MSRs to guest. Requires kernel 6.18+ | IET-based VM detection via MSR absence |
| `hypervVendorId` | `str` (1-12 chars) | `"AuthAMDRyzen"` | Hyper-V vendor_id reported to guest. Avoid known VM values (AMDisbetter!, Microsoft Hv) | Hyper-V vendor_id detection |
| `hypervMode` | `enum ["enlightened" "hidden"]` | `"enlightened"` | "enlightened" exposes hypervisor + full Hyper-V enlightenments (paravirt perf). "hidden" conceals the hypervisor and emits no enlightenments | Hyper-V presence detection |

### Kernel

| Option | Type | Default | Description | Detection Vector |
|---|---|---|---|---|
| `timing.enable` | `bool` | `true` | Apply BetterTiming TSC compensation kernel patch | RDTSC/RDTSCP timing attacks |
| `cpuidSpoof.enable` | `bool` | `true` | Apply CPUID leaf 0 emulation via Hypervisor-Phantom technique | CPUID vendor string + hypervisor bit |
| `cpuidPassthrough.enable` | `bool` | `false` | Disable CPUID interception entirely — guest executes at native speed. Handles TIMER + SINGLE_STEP. Requires AMD host-passthrough. When enabled, cpuidSpoof is skipped. | RDTSC software-counter timing, #DB exception timing |
| `kernelParams.maxCState` | `int` | `1` | `processor.max_cstate` kernel parameter value | TSC stability (deep C-states cause drift) |
| `kernelParams.tscReliable` | `bool` | `true` | Pass `tsc=reliable` on kernel command line | TSC source selection |

### SMBIOS

| Option | Type | Default | Description | Detection Vector |
|---|---|---|---|---|
| `smbios.manufacturer` | `str` | `"To Be Filled By O.E.M."` | System and baseboard manufacturer (Types 1, 2) | Win32_ComputerSystem.Manufacturer |
| `smbios.product` | `str` | `"To Be Filled By O.E.M."` | System and baseboard product name (Types 1, 2) | Win32_ComputerSystem.Model |
| `smbios.biosVendor` | `str` | `"American Megatrends Inc."` | BIOS vendor string (Type 0) | Win32_BIOS.Manufacturer |
| `smbios.biosVersion` | `str` | `"1001"` | BIOS version string (Type 0) | Win32_BIOS.SMBIOSBIOSVersion |
| `smbios.biosDate` | `str` | `"01/01/2025"` | BIOS release date MM/DD/YYYY (Type 0). OVMF default 02/02/2022 is a generic VM date | Win32_BIOS.ReleaseDate |
| `smbios.biosRelease` | `str` | `"2.4"` | BIOS release version major.minor (Type 0 System BIOS Release field) | Win32_BIOS release fields |
| `smbios.serial` | `str` | `"System Serial Number"` | System serial number (Type 1) | Win32_ComputerSystem.SerialNumber |
| `smbios.baseBoardVersion` | `str` | `"Rev 1.xx"` | Baseboard version string (Type 2) | Win32_BaseBoard.Version |
| `smbios.baseBoardSerial` | `str` | `"Default string"` | Baseboard serial number (Type 2, set from dmidecode) | Win32_BaseBoard.SerialNumber |
| `smbios.baseBoardAsset` | `str` | `"Default string"` | Baseboard asset tag (Type 2) | Win32_BaseBoard.Tag |
| `smbios.baseBoardLocation` | `str` | `"Default string"` | Baseboard location in chassis (Type 2) | Win32_BaseBoard.LocationInChassis |
| `smbios.socketPrefix` | `str` | `"AM5"` | Processor socket designator prefix (Type 4) | Win32_Processor.SocketDesignation |
| `smbios.memory.manufacturer` | `str` | `"Unknown"` | DIMM manufacturer (Type 17) | Win32_PhysicalMemory.Manufacturer |
| `smbios.memory.partNumber` | `str` | `"Unknown"` | DIMM part number (Type 17) | Win32_PhysicalMemory.PartNumber |
| `smbios.memory.speed` | `int` | `4800` | Memory speed in MT/s (Type 17) | Win32_PhysicalMemory.Speed |
| `smbios.memory.size` | `int` | `16384` | DIMM size in MB per module (Type 17) | Win32_PhysicalMemory.Capacity |
| `smbios.memory.count` | `int` | `2` | Number of DIMMs to report (Type 17) | Win32_PhysicalMemory count |
| `smbios.oemStrings` | `listOf str` | `["Default string" ...]` (4 entries) | OEM Strings for Type 11. Real boards populate 4-6 entries; empty Type 11 is a VM indicator | Win32_ComputerSystem.OEMStringArray |
| `smbios.onboardDevices` | `listOf submodule` | `[ ]` | Onboard devices for Type 41 (submodule with designation, kind, instance). Set to match your board. Empty = no Type 41 entries | Win32_OnBoardDevice |

### EDID (Display Identity)

Module options under `myModules.vfio.stealth.edid.*` document the target values. The corresponding build-time arguments to `qemu-stealth` (passed via overlay or `callPackage`) compile them into the QEMU binary.

| Argument | Default | Description | Detection Vector |
|---|---|---|---|
| `edidManufacturer` | `"ACI"` | 3-letter EDID manufacturer ID | Monitor manufacturer identifier |
| `edidSerial` | `"VG248QE"` | Monitor serial string | EDID serial number |
| `edidProductCode` | `"0x2480"` | EDID product code (hex) | EDID product code field |
| `edidDpi` | `91` | Monitor DPI | EDID physical size calculation |
| `edidWeek` | `22` | Manufacture week (1-52) | EDID manufacture date |
| `edidYear` | `2020` | Manufacture year | EDID manufacture date |
| `edidResX` | `1920` | Default EDID horizontal resolution | EDID preferred timing |
| `edidResY` | `1080` | Default EDID vertical resolution | EDID preferred timing |

### Disk / SCSI

Module options under `myModules.vfio.stealth.disk.*` document the target values. Build-time arguments to `qemu-stealth`:

| Argument | Default | Description | Detection Vector |
|---|---|---|---|
| `diskModel` | `"WDC WD10EZEX-00WN4A0     "` | IDE/SCSI disk model string (25 chars, space-padded) | Disk model reveals QEMU default |
| `diskSerial` | `"Default string"` | IDE disk serial string (replaces AutoVirt blank serial) | Blank disk serial is a VM indicator |
| `opticalModel` | `"HL-DT-ST DVDRAM GH24NSC0 "` | IDE/ATAPI optical drive model string (25 chars) | Optical drive model reveals QEMU |
| `scsiVendor` | `"WDC"` | SCSI INQUIRY vendor string (8-char T10 format, auto-padded) | SCSI vendor reveals QEMU default |
| `scsiTargetProduct` | `"SCSI Disk       "` | SCSI target product for dead-LUN INQUIRY fallback (16-char padded) | SCSI target product reveals QEMU |

### ACPI

| Option | Type | Default | Description | Detection Vector |
|---|---|---|---|---|
| `acpiSsdt.spoofedDevices` | `bool` | `true` | Include emulated ACPI devices (EC, fan, thermal zone, power/sleep buttons, timers) in SSDT | Missing EC/fan/thermal = VM indicator |
| `acpiSsdt.fakeBattery` | `bool` | `true` | Include emulated ACPI battery device in SSDT | Missing battery can flag VM detection |
| `acpiSsdt.sensorProbes` | `bool` | `true` | Include CPU + VRM thermal zones with Timer()-based dynamic fluctuation | Static/missing thermal data flags VM |

Module options under `myModules.vfio.stealth.acpiOem.*`. Build-time arguments to `qemu-stealth`:

| Argument | Default | Description | Detection Vector |
|---|---|---|---|
| `acpiOemId` | `"ALASKA"` | 6-char ACPI OEM ID | ACPI table OEM ID reveals QEMU |
| `acpiOemTableId` | `"A M I   "` | 8-char padded ACPI OEM Table ID | ACPI table OEM Table ID |

### Network

| Option | Type | Default | Description | Detection Vector |
|---|---|---|---|---|
| `spoofMac` | `bool` | `true` | Enable MAC address OUI override | OUI prefix identifies virtual NIC vendor |
| `macPrefix` | `str` | `"D8:BB:C1"` | OUI prefix (Realtek OUI matching ASUS X870E onboard LAN) | MAC OUI lookup reveals VM |

### CPU Identity

Module options under `myModules.vfio.stealth.cpuIdentity.*`. Passed per-VM via `mkStealthFeatures` in `lib.nix`:

| Argument | Description | Detection Vector |
|---|---|---|
| `cpuIdentity.modelId` | CPU model string for SMBIOS Type 4 + QEMU `-global cpu.model-id` | Win32_Processor.Name |
| `cpuIdentity.maxSpeed` | Max CPU speed in MHz (Type 4) | Win32_Processor.MaxClockSpeed |
| `cpuIdentity.currentSpeed` | Current CPU speed in MHz (Type 4) | Win32_Processor.CurrentClockSpeed |

### Cache (SMBIOS Type 7)

Cache entries are configurable via `smbios.cache.*` options. They populate `Win32_CacheMemory`, which is empty by default on VMs and used as a detection signal.

| Option | Type | Default | Description | Detection Vector |
|---|---|---|---|---|
| `smbios.cache.l1` | `int` | `512` | L1 cache size in KB (SMBIOS Type 7) | Win32_CacheMemory |
| `smbios.cache.l2` | `int` | `8192` | L2 cache size in KB (SMBIOS Type 7) | Win32_CacheMemory |
| `smbios.cache.l3` | `int` | `32768` | L3 cache size in KB (SMBIOS Type 7) | Win32_CacheMemory |

### TPM Identity

| Option | Type | Default | Description | Detection Vector |
|---|---|---|---|---|
| `tpm.harden` | `bool` | `true` | Configure swtpm to report realistic hardware TPM identity | swtpm defaults report IBM/swtpm |
| `tpm.manufacturer` | `str` | `"id:49465800"` | TPM manufacturer ID (8 hex digits). id:49465800=Infineon | Win32_Tpm manufacturer |
| `tpm.model` | `str` | `"SLB9672"` | TPM model string. SLB9672 = Infineon discrete TPM | Win32_Tpm model |
| `tpm.firmwareVersion` | `str` | `"id:000F0018"` | TPM firmware version (8 hex digits). 0x000F0018 = FW 15.24 | Win32_Tpm firmware version |
| `tpm.platformManufacturer` | `str` | `"ASUSTeK COMPUTER INC."` | Platform manufacturer for TPM platform certificate | TPM platform certificate |
| `tpm.platformModel` | `str` | `"System Product Name"` | Platform model for TPM platform certificate | TPM platform certificate |

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
| **Vanguard (Riot Games)** | Kernel-mode driver loads at boot and detects hypervisors via multiple vectors beyond CPUID. swtpm satisfies TPM 2.0 presence check, but VM detection is independent of TPM state. No confirmed working VM configuration as of 2026. |
| **FACEIT** | Multi-layer enforcement: TPM 2.0, Secure Boot, IOMMU/DMA Protection, VBS (Virtualization-Based Security), and `hypervisorlaunchtype=auto`. The VBS requirement means Windows must run under its own Hyper-V hypervisor — incompatible with standard KVM guests. |
| **AI behavioral analysis** | ML models analyzing gameplay patterns (movement, aim, reaction time) can flag statistical anomalies. The VM-relevant subset is performance variance detection (frame-time jitter from VM exits), which BetterTiming + cpuidPassthrough substantially reduce but cannot guarantee identical distributions. |
| **XSAVE state identification (emerging)** | VMAware v2.7+ researches detection of CPUID interception handling via XCR0/XSS size discrepancies. On AMD SVM, VMRUN loads guest XCR0 from the VMCB, making leaf 0xD naturally consistent — but this is an evolving area. |
| **NPT page-walk latency** | Nested Page Table translation adds ~10-20ns per TLB miss. Detectable in theory via microbenchmarks, but high noise floor makes it impractical for detection software false-positive rates. No known detection software uses this. |

## License

GPL-2.0 (kernel patches mandate GPL)

<!-- BEGIN generated:footer -->
---

*Maintained as part of the [Daaboulex](https://github.com/Daaboulex) NixOS ecosystem.*
<!-- END generated:footer -->
