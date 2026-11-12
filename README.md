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
| **Project** | [Scrut1ny/AutoVirt](https://github.com/Scrut1ny/AutoVirt), whose QEMU and EDK2 patches are vendored in [`vendor/autovirt`](vendor/autovirt), and [SamuelTulach/BetterTiming](https://github.com/SamuelTulach/BetterTiming), hand-ported in [`kernel/timing-patch.nix`](kernel/timing-patch.nix) |
| **License** | For the vendored AutoVirt patches see [`vendor/autovirt/README`](vendor/autovirt/README). This repository records no licence for BetterTiming |
| **Tracked** | [`scripts/update.sh`](scripts/update.sh) |

<!-- END generated:upstream -->

## Overview

vfio-stealth-nix is a flake for NixOS hosts that run VFIO/KVM guests. It replaces the identifiers a guest reads to recognise QEMU, OVMF and KVM (SMBIOS strings, ACPI OEM fields and devices, PCI and disk identifiers, CPUID and timing behaviour) with values taken from real hardware. It has three pieces: an overlay with patched QEMU and OVMF packages, a NixOS module that sets host kernel parameters and exposes kernel and libtpms patch scripts, and `lib.mkStealthFeatures`, which returns the libvirt and QEMU fragments for one VM. Some detection methods remain, listed under [Known Limitations](#known-limitations).

## Documentation

For long-form references beyond the quick start below, see:

- [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) — directory layout, component-to-file mapping, kernel-integration boundary
- [`docs/BUILD.md`](docs/BUILD.md) — operator commands: dev shell, formatters, hooks, tests, update contract, troubleshooting
- [`docs/OPTIONS.md`](docs/OPTIONS.md) — canonical `virtualisation.vfio-stealth.*` option reference

## Components

| Package | Description |
|---|---|
| **qemu-stealth** | QEMU with the AutoVirt hardware-emulation patch applied, which also sets the fw_cfg DMA signature to a fixed value, and with configurable hardware identifiers: EDID, ACPI OEM, disk and optical models, SCSI vendor and target product, disk serial |
| **ovmf-stealth** | Patched EDK2/OVMF firmware: clears VirtualMachine bit in SMBIOS Type 0, replaces Red Hat PCI vendor IDs, overrides ACPI OEM fields, strips BGRT boot logo (VMAware indicator). Overridable: `secureBoot`, `msVarsTemplate`, `tpmSupport` |
| **acpi-ssdt-stealth** | Compiled ACPI SSDT tables providing power and sleep buttons, an AC adapter, timer devices, a voltage regulator device, a fan, thermal zones and a battery |
| **smbios-stealth-tables** | Binary SMBIOS tables for types QEMU cannot build via CLI (Type 7 cache, Types 26-29 probes) |
| **smbios-extract** | Dumps the host's SMBIOS tables to a file with `dmidecode --dump-bin`, as the source of real hardware strings for the VM config. Needs root |
| **stealth-detect** | Built on both systems, and the only package on `aarch64-linux`. Reports, per vector, whether a Linux guest can tell it is virtualized (device tree, PSCI conduit, MIDR, SMBIOS, ACPI OEM and FADT hypervisor identity, virtio, PCI, timer). Exits 1 when any vector fires |

## Detection Vectors Covered

| Vector | Technique | Where |
|---|---|---|
| CPUID hypervisor bit | `kvm.hidden` is always set. The hypervisor bit itself is cleared only when `hypervMode` is `"hidden"`. The Hyper-V vendor_id override applies in enlightened mode | [`lib.nix`](lib.nix) `features`, `cpuFeatures`, `qemuArgs` |
| CPUID leaf 0 vendor string | Hypervisor-Phantom: intercept at SVM level, override to AuthenticAMD, re-enter guest without full exit | [`kernel/cpuid-patch.nix`](kernel/cpuid-patch.nix) |
| CPUID interception timing | Disabled entirely via cpuidPassthrough, so guest CPUID runs at native speed | [`kernel/cpuid-disable.nix`](kernel/cpuid-disable.nix) |
| RDTSC/RDTSCP timing | BetterTiming: track cumulative VM-exit time, subtract from TSC reads (RDTSC + RDTSCP handlers with compensated values) | [`kernel/timing-patch.nix`](kernel/timing-patch.nix) |
| MSR_IA32_TSC reads | Compensated TSC value returned via patched `kvm_get_msr_common` | [`kernel/timing-patch.nix`](kernel/timing-patch.nix) |
| IA32_APERF/MPERF MSR | Passthrough via `-cpu host,aperfmperf=on` (covers IET-based detection) | [`lib.nix`](lib.nix) `qemuArgs` |
| SMBIOS Type 0 (BIOS) | Vendor, version, date, release override | [`module.nix`](module.nix) options, [`lib.nix`](lib.nix) `sysinfo` |
| SMBIOS Type 1 (System) | Manufacturer, product, serial, family, UUID | [`module.nix`](module.nix) options, [`lib.nix`](lib.nix) `sysinfo` |
| SMBIOS Type 2 (Baseboard) | Manufacturer, product, version, serial, asset tag, location | [`lib.nix`](lib.nix) `sysinfo` |
| SMBIOS Type 3 (Chassis) | Manufacturer, version, serial, asset tag | [`lib.nix`](lib.nix) `qemuArgs` |
| SMBIOS Type 4 (Processor) | Socket, manufacturer, version, speed | [`lib.nix`](lib.nix) `qemuArgs` (via cpuIdentity) |
| SMBIOS Type 7 (Cache) | L1/L2/L3 cache designation and sizes | [`lib.nix`](lib.nix) `qemuArgs` |
| SMBIOS Type 8 (Port Connector) | USB port descriptors | [`lib.nix`](lib.nix) `qemuArgs` |
| SMBIOS Type 9 (System Slots) | PCIe slot designation and type | [`lib.nix`](lib.nix) `qemuArgs` |
| SMBIOS Type 17 (Memory) | DIMM manufacturer, part number, speed, count | [`module.nix`](module.nix) options, [`lib.nix`](lib.nix) `qemuArgs` |
| SMBIOS Type 26 (Voltage Probe) | Voltage probe description + min/max | [`lib.nix`](lib.nix) `qemuArgs` |
| SMBIOS Type 27 (Cooling Device) | Cooling device type + speed | [`lib.nix`](lib.nix) `qemuArgs` |
| SMBIOS Type 28 (Temperature Probe) | Temperature probe description + min/max | [`lib.nix`](lib.nix) `qemuArgs` |
| SMBIOS Type 29 (Current Probe) | Current probe description + min/max | [`lib.nix`](lib.nix) `qemuArgs` |
| ACPI table OEM IDs | The OEM ID and OEM Table ID the AutoVirt patch sets are replaced with the configured `acpiOemId` (6 characters) and `acpiOemTableId` (8 characters) | [`qemu/post-patch.nix`](qemu/post-patch.nix) |
| ACPI SSDT devices | Power and sleep buttons, AC adapter, timer devices, voltage regulator device, fan, thermal zone | [`acpi/spoofed-devices.dsl`](acpi/spoofed-devices.dsl) |
| ACPI emulated battery | Control Method Battery (PNP0C0A) with BIF/BST methods | [`acpi/fake-battery.dsl`](acpi/fake-battery.dsl) |
| EDID display identity | Monitor manufacturer, model, serial, product code, DPI, manufacture date | [`qemu/package.nix`](qemu/package.nix) arguments, applied in [`qemu/post-patch.nix`](qemu/post-patch.nix) |
| Disk model string | IDE/SCSI disk model override in QEMU source | [`qemu/post-patch.nix`](qemu/post-patch.nix) |
| Optical drive model | IDE/ATAPI optical drive model override | [`qemu/post-patch.nix`](qemu/post-patch.nix) |
| MAC address OUI | Not applied by this flake. The options `spoofMac` and `macPrefix` are declared and read by no code here, so the caller sets the guest NIC's MAC address in its VM definition | [`module.nix`](module.nix) options |
| Hyper-V enlightenments | `vendor_id` and `relaxed` are on by default. The other eleven (vapic, spinlocks, stimer, frequencies and the rest) are opt-in through `hypervFeatures` | [`lib.nix`](lib.nix) `features` |
| KVM feature hiding | `kvm.hidden`, `hint-dedicated`, `poll-control` | [`lib.nix`](lib.nix) `features` |
| VMPort | Disabled | [`lib.nix`](lib.nix) `features` |
| Clock/timer emulation | kvmclock absent, hypervclock present only when at least one kernel-dependent Hyper-V feature is enabled, native TSC, HPET present | [`lib.nix`](lib.nix) `clock` |
| OVMF VirtualMachine bit | Cleared in SMBIOS Type 0 via EDK2 patch | AutoVirt EDK2 patch, applied by [`ovmf/post-patch.nix`](ovmf/post-patch.nix) |
| OVMF PCI vendor IDs | Red Hat IDs replaced with AMD/Intel | AutoVirt EDK2 patch, applied by [`ovmf/post-patch.nix`](ovmf/post-patch.nix) |
| VirtIO device identifiers | When `stripVirtio` is true, `devicesToRemove` names the balloon, RNG and tablet devices. The caller removes them from its VM definition | [`lib.nix`](lib.nix) `devicesToRemove` |
| SMBIOS Type 11 (OEM Strings) | Populated with realistic entries (empty Type 11 is a VM indicator) | [`module.nix`](module.nix) options, [`lib.nix`](lib.nix) `qemuArgs` |
| SMBIOS Type 41 (Onboard Devices) | One entry per item of `smbios.onboardDevices`. The default list is empty, so no Type 41 entry exists until the caller lists its board's devices | [`module.nix`](module.nix) options, [`lib.nix`](lib.nix) `qemuArgs` |
| Disk serial string | IDE drive serial set to the configured `diskSerial` in place of the blank serial AutoVirt leaves. The default, `Default string`, is a placeholder | [`qemu/post-patch.nix`](qemu/post-patch.nix) |
| fw_cfg DMA signature + ACPI device | 8-byte DMA signature changed from "QEMU CFG" to "QCOM CFG"; fw_cfg ACPI device node removed from DSDT (4-byte probe at selector 0x0000 still reads "QEMU") | AutoVirt patch, applied by [`qemu/post-patch.nix`](qemu/post-patch.nix) |
| KVM paravirt MSR enforcement | Opt-in, off by default. `kvmPvEnforceCpuid = true` passes `kvm-pv-enforce-cpuid=on`, so guest_pv_has() rejects pvclock/steal-time MSRs when kvm.hidden=on. Otherwise `kvm-pv-enforce-cpuid=off` is passed | [`lib.nix`](lib.nix) `qemuArgs` |
| KVM hypercall patching | Disabled: emulator_fix_hypercall always injects #UD (bare-metal behavior on VMCALL/VMMCALL) | [`kernel/timing-patch.nix`](kernel/timing-patch.nix) |
| SVM instruction interception | `kvm_amd.vls=0` + `kvm_amd.vgif=0` force VMLOAD/VMSAVE/STGI/CLGI interception | [`module.nix`](module.nix) kernel params |
| OVMF boot logo / BGRT | TianoCore LogoDxe + BootGraphicsResourceTableDxe stripped (VMAware CRC indicator) | [`ovmf/post-patch.nix`](ovmf/post-patch.nix) |
| ACPI thermal zone fluctuation | Timer()-based dynamic temperature in CPU + VRM thermal zones (handles static-value detection) | [`acpi/sensor-probes.dsl`](acpi/sensor-probes.dsl) |
| PCI subsystem vendor:device | Default 0x1af4:0x1100 (Red Hat/QEMU) replaced with 0x8086:0x0000 (Intel) on all Q35 chipset devices | [`qemu/post-patch.nix`](qemu/post-patch.nix) |
| QEMU pvpanic device | Consumer excludes `<panic>` from domain XML; verified by [`guest/verify-host.sh`](guest/verify-host.sh) | [`guest/verify-host.sh`](guest/verify-host.sh) |
| Registry SCSI DEVICEMAP | Cleaned via guest-side registry script | [`guest/cleanup-registry.ps1`](guest/cleanup-registry.ps1) |

## Quick Start

Add as a flake input:

```nix
vfio-stealth = {
  url = "github:Daaboulex/vfio-stealth-nix";
  inputs.nixpkgs.follows = "nixpkgs";
};
```

The flake has three pieces and a host uses all three. The host also defines
the VM itself: nothing here creates a libvirt domain or selects the QEMU a VM
runs on.

### The overlay

```nix
nixpkgs.overlays = [ inputs.vfio-stealth.overlays.default ];
```

`overlays.default` provides `qemu-stealth` and `ovmf-stealth` (AMD),
`qemu-stealth-intel` and `ovmf-stealth-intel`, `acpi-ssdt-stealth`,
`smbios-stealth-tables`, `smbios-extract` and `stealth-detect`. Both vendors
are built and contract-tested, each with the AutoVirt patch family of its
vendor. The caller chooses the QEMU and OVMF pair for its CPU and points its
VM at it. The module option `cpuVendor` picks no package.

The stealth stack itself is `x86_64-linux` only, pinned there by each package's
`meta.platforms`: the AutoVirt QEMU patches target `hw/i386/` and the Q35
southbridge, the EDK2 patches target `OvmfPkg/OvmfPkgX64.{dsc,fdf}` (on aarch64
`pkgs.OVMF` is ArmVirtQemu), and [`kernel/`](kernel) edits `arch/x86/kvm/svm/svm.c`.
`aarch64-linux` currently carries only `stealth-detect`, the oracle that an
ARM spoof would have to defeat; see
[`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) for why the detector comes first.

### The module

```nix
imports = [ inputs.vfio-stealth.nixosModules.default ];

virtualisation.vfio-stealth = {
  enable = true;
  cpuVendor = "amd";
  smbios = {
    manufacturer = "Your Motherboard Manufacturer";
    product = "Your Motherboard Model";
  };
};
```

`cpuVendor` is `"amd"` or `"intel"`. It is required and has no default. With
`enable = true` the module sets:

- `boot.kernelParams`: `processor.max_cstate`, `kvm_amd.vls=0`,
  `kvm_amd.vgif=0`, `kvm.ignore_msrs=1`, `kvm.report_ignored_msrs=0`, and
  `tsc=reliable` while `kernelParams.tscReliable` is on.
- `/etc/swtpm-localca.options`, while `tpm.harden` is on.
- Assertions on the option values, and a warning for each identity value left
  at its placeholder default.
- Two read-only options the caller applies itself: `kernelPostPatch` (see
  [Kernel Integration](#kernel-integration)) and `libtpmsIdentityPatch`, a
  `postPatch` fragment for `libtpms`.

It sets nothing else. The remaining options hold values for the caller: most
are passed to `lib.mkStealthFeatures`, and `edid`, `disk` and `acpiOem` record
what the caller gives the `qemu-stealth` override. `spoofMac` and `macPrefix`
are read by no code in this flake.

One limitation on Intel: the kernel-level stealth (`timing.enable`,
`cpuidSpoof.enable`, `cpuidPassthrough.enable`) is AMD/SVM-only -- those
patches target `arch/x86/kvm/svm/svm.c`, which `kvm-intel` never executes.
An assertion refuses that combination rather than shipping a feature that
silently does nothing. QEMU and OVMF stealth apply on both.

### `lib.mkStealthFeatures`

`lib.mkStealthFeatures` returns the libvirt and QEMU fragments for one VM. Its
arguments:

- Required: `smbios` (the module's `smbios` option set carries every field it
  reads), `acpiTables` (the `acpi-ssdt-stealth` package) and `smbiosTables`
  (the `smbios-stealth-tables` package).
- Optional: `vmUuid`, which defaults to `null`, and `acpiSsdt`, `aperfMperf`,
  `stripVirtio`, `hypervVendorId`, `hypervMode`, `kvmPvEnforceCpuid`,
  `pciMmio64Mb`, `hypervFeatures` and `kernelCapabilities`, each with the
  default of the module option of the same name.

```nix
stealth = inputs.vfio-stealth.lib.mkStealthFeatures {
  inherit (config.virtualisation.vfio-stealth)
    smbios
    acpiSsdt
    aperfMperf
    stripVirtio
    hypervVendorId
    hypervMode
    kvmPvEnforceCpuid
    pciMmio64Mb
    hypervFeatures
    kernelCapabilities
    ;
  acpiTables = pkgs.acpi-ssdt-stealth;
  smbiosTables = pkgs.smbios-stealth-tables;
};
```

The function writes nothing into the system configuration. The caller places
each attribute of the result:

| Attribute | What the caller does with it |
|---|---|
| `warnings` | Adds the list to its own `warnings`. It holds one message per requested Hyper-V feature that `kernelCapabilities` does not cover |
| `features` | Puts it into the domain's `<features>`: `kvm.hidden`, `hint-dedicated`, `poll-control`, VMPort off, and the `hyperv` block in enlightened mode |
| `cpuFeatures` | Puts it into the domain's `<cpu>` feature list: `topoext` and `invtsc`, and `hypervisor` disabled in hidden mode |
| `clock` | Puts it into the domain's `<clock>` |
| `sysinfo` | Puts it into the domain's `<sysinfo>`: SMBIOS Types 0, 1 and 2 |
| `qemuArgs` | Calls it with the module's `cpuIdentity` option set, or `null`, and adds the returned list to the QEMU command line: the other SMBIOS types, the ACPI tables and the `-cpu` flags |
| `devicesToRemove` | Removes the named devices from the VM. The list is empty when `stripVirtio` is false |

## Configuration Reference

All options live under `virtualisation.vfio-stealth.*`. Module options, build-time `qemu-stealth` arguments, and read-only outputs are documented in [`docs/OPTIONS.md`](docs/OPTIONS.md).

## Example Configurations

> **WARNING: Do not use these exact values.** Detection software can identify
> known stealth configurations. Use your own realistic hardware strings
> from `dmidecode`, `edid-decode`, or manufacturer websites.

### Example 1: MSI + Corsair + BenQ + WD

```nix
virtualisation.vfio-stealth = {
  enable = true;
  cpuVendor = "amd"; # or "intel" -- required, no default
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
  macPrefix = "2c:f0:5d";
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
virtualisation.vfio-stealth = {
  enable = true;
  cpuVendor = "amd"; # or "intel" -- required, no default
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
  macPrefix = "70:85:c2";
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

Two PowerShell scripts in [`guest/`](guest) handle cleanup and verification inside the Windows VM.

### cleanup-registry.ps1

[`guest/cleanup-registry.ps1`](guest/cleanup-registry.ps1) removes QEMU/KVM/VirtIO registry artifacts left behind from before stealth was configured, or from VirtIO driver installation. Among others, it targets:

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

[`guest/verify-stealth.ps1`](guest/verify-stealth.ps1) is a read-only script that checks detection vectors from inside the Windows guest and prints PASS, FAIL, WARN or SKIP for each. It runs without Administrator, and a check that needs Administrator prints SKIP.

```powershell
.\verify-stealth.ps1
```

It ends with a summary line of the form `=== 0 failures, 0 warnings, 0 skipped ===`.

## Kernel Integration

The module exposes `virtualisation.vfio-stealth.kernelPostPatch` -- a shell script string that patches the kernel source tree via sed/awk. It combines BetterTiming (TSC compensation) and CPUID emulation (Hypervisor-Phantom) based on your config.

The patches target function signatures and symbol names, not line numbers, for resilience across kernel versions. CI validates anchors against nixpkgs latest kernel on every push.

### With CachyOS kernel

```nix
boot.kernelPackages = pkgs.linuxPackagesFor (
  pkgs.linuxPackages_cachyos.kernel.overrideAttrs (old: {
    postPatch = (old.postPatch or "") + config.virtualisation.vfio-stealth.kernelPostPatch;
  })
);
```

### With stock kernel

```nix
boot.kernelPackages = pkgs.linuxPackagesFor (
  pkgs.linux_latest.overrideAttrs (old: {
    postPatch = (old.postPatch or "") + config.virtualisation.vfio-stealth.kernelPostPatch;
  })
);
```

### What the patches do

**BetterTiming** ([`kernel/timing-patch.nix`](kernel/timing-patch.nix)):

- Adds `last_exit_start` and `total_exit_time` fields to `struct kvm_vcpu`
- Adds `total_exit_time` to `struct kvm_vcpu`; every stealth exit handler self-times with `rdtsc()` and accumulates only its own duration
- Patches `MSR_IA32_TSC` reads to return compensated (exit-time-subtracted) values
- Enables RDTSC + RDTSCP interception in SVM `init_vmcb`
- Adds `handle_rdtsc_interception` handler that returns compensated TSC
- Adds `handle_rdtscp_interception` handler returning compensated TSC + TSC_AUX in ECX
- Wraps the CPUID, WBINVD, XSETBV and INVD exit handlers so each accumulates its own execution time
- Disables KVM hypercall instruction patching by forcing the `KVM_X86_QUIRK_FIX_HYPERCALL_INSN` check true, so VMCALL/VMMCALL always injects #UD. This is host-wide: every VM on the host gets #UD, so Linux guests lose KVM paravirt features (kvmclock, PV TLB flush)

**CPUID emulation** ([`kernel/cpuid-patch.nix`](kernel/cpuid-patch.nix)):

- Intercepts CPUID leaf 0 inside `svm_vcpu_run` after `svm_vcpu_enter_exit` returns
- Overrides vendor string to `AuthenticAMD` with max leaf `0x20`
- Advances RIP and re-enters guest via `goto reenter_guest_fast` (no full VM exit)
- Clears RDTSC/RDTSCP interception bits (BetterTiming re-enables RDTSC if active)

**CPUID passthrough** ([`kernel/cpuid-disable.nix`](kernel/cpuid-disable.nix)) — Exit-less CPUID:

- Clears `INTERCEPT_CPUID` in `init_vmcb` and `pre_svm_run`
- Guest executes CPUID at native hardware speed (zero VM exit)
- AMD SVM loads guest XCR0 from VMCB — leaf 0xD naturally consistent
- Hardware returns AuthenticAMD with no hypervisor bit (synthetic, absent in real CPUID)
- Side effect: Hyper-V enlightenments invisible to guest (Windows uses TSC directly)

## Upstream Tracking

Both upstream techniques are vendored, not fetched at build time.

- **AutoVirt** (QEMU + EDK2 hardware-emulation patches). Upstream is [Scrut1ny/AutoVirt](https://github.com/Scrut1ny/AutoVirt), watched daily with its live forks; the patches live in [`vendor/autovirt`](vendor/autovirt) and the packages build from those, so the packages never depend on upstream being online. [`vendor/autovirt/README`](vendor/autovirt/README) records where the patches came from and what this repository changed in them.
- **[SamuelTulach/BetterTiming](https://github.com/SamuelTulach/BetterTiming)** (TSC compensation). [`kernel/timing-patch.nix`](kernel/timing-patch.nix) is a hand-port; [`version.json`](version.json) records the commit it was ported from.

[`.github/workflows/update.yml`](.github/workflows/update.yml) runs [`scripts/update.sh`](scripts/update.sh) on a daily cron. It watches the surviving AutoVirt forks for a patch newer than the vendored one, BetterTiming for a commit past the recorded port, and nixpkgs for a QEMU series no vendored patch covers, and files an issue when one appears. Adopting a change is a hand decision, see [`docs/RELEASE-PROCEDURE.md`](docs/RELEASE-PROCEDURE.md).

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
| **PCIe root port vendor `1b36:000c`** | QEMU's generic PCIe root port uses vendor 1b36 (Red Hat). No upstream override mechanism; patching the root port device type would need a QEMU source change. |
| **fw_cfg I/O port probe** | Reading 4 bytes from fw_cfg selector 0x0000 returns "QEMU". The DMA signature is patched but the legacy I/O path (ports 0x510/0x511) remains. Requires QEMU source patch to fully suppress. |
| **Context-switch timing oracles** | Detection libraries (VMAware v2.5+) use context-switch-based clocks independent of TSC. Claims immunity to all TSC/hardware clock spoofing including BetterTiming. An evolving area. |
| **XSAVE state identification** | Detection of CPUID interception handling via XCR0/XSS size discrepancies. On AMD SVM, VMRUN loads guest XCR0 from the VMCB, making leaf 0xD naturally consistent -- an evolving area. |
| **NPT page-walk latency** | Nested Page Table translation adds ~10-20ns per TLB miss. Detectable in theory via microbenchmarks, but high noise floor makes it impractical for false-positive rates. No known detection software uses this. |
| **Performance variance** | ML-based detection of frame-time jitter from VM exits. BetterTiming + `cpuidPassthrough` substantially reduce but cannot eliminate this surface. |

### Hyper-V enlightenment capability mismatch

Of the 13 Hyper-V enlightenment features in this module, only
`vendor_id` and `relaxed` are unconditional (no KVM cap; libvirt-level
settings). The other 11 (`vapic`, `spinlocks`, `frequencies`,
`vpindex`, `synic`, `stimer`, `reset`, `ipi`, `tlbflush`,
`reenlightenment`, `runtime`) all require `CONFIG_KVM_HYPERV=y` in the
host kernel — a single switch in the kernel. The module's defaults
reflect this: the 11 KVM-gated features default off, the 2 truly
universal features default on. Enable additional features only after
verifying your kernel has `CONFIG_KVM_HYPERV=y` with
`zcat /proc/config.gz | grep KVM_HYPERV`. See
[`docs/OPTIONS.md`](docs/OPTIONS.md#hyper-v-features) for the full
opt-in table and the `kernelCapabilities` option.

## License

[`LICENSE`](LICENSE) is the GNU General Public License, version 2. The
packages built from this repository's own sources (`acpi-ssdt-stealth`,
`smbios-extract`, `smbios-stealth-tables`, `stealth-detect`) declare
`gpl2Only` as their `meta.license`. `qemu-stealth` and `ovmf-stealth` set no
`meta.license` of their own and keep the one of the nixpkgs packages they
override. [`vendor/autovirt`](vendor/autovirt) carries its own
[`LICENSE`](vendor/autovirt/LICENSE), the GNU General Public License, version
3, and its own [`README`](vendor/autovirt/README), which states the licence
of the vendored patches.

<!-- BEGIN generated:footer -->
<!-- END generated:footer -->
