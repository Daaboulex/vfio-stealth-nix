# vfio-stealth-nix — Option Reference

Companion to the top-level [README](../README.md). All options live
under the `myModules.vfio.stealth.*` namespace. EDID / disk / optical /
ACPI OEM strings are build-time arguments to `qemu-stealth` (passed via
overlay or `callPackage`), **not** module options — those are listed
separately at the bottom.

This document mirrors the README "Configuration Reference" section; the
README is the canonical home, this page is the deep-link target.

## Core

| Option | Type | Default | Description | Detection vector |
|---|---|---|---|---|
| `enable` | `bool` | `false` | Enable the VFIO stealth anti-detection stack | -- |
| `stripVirtio` | `bool` | `true` | Remove VirtIO balloon, RNG, tablet devices from VM config | VirtIO PCI vendor ID fingerprinting |
| `spoofMac` | `bool` | `true` | Spoof guest NIC MAC address with a realistic OUI prefix | MAC OUI reveals VM NIC vendor |
| `macPrefix` | `str` | `"04:42:1a"` | OUI prefix for spoofed MAC (colon-separated hex) | MAC address OUI |
| `aperfMperf` | `bool` | `true` | Pass through IA32_APERF/MPERF MSRs to guest. Requires kernel 6.18+ | IET-based VM detection via MSR absence |

## Kernel

| Option | Type | Default | Description | Detection vector |
|---|---|---|---|---|
| `timing.enable` | `bool` | `true` | Apply BetterTiming TSC compensation kernel patch | RDTSC/RDTSCP timing attacks |
| `cpuidSpoof.enable` | `bool` | `true` | Apply CPUID leaf 0 spoof via Hypervisor-Phantom technique | CPUID vendor string + hypervisor bit |
| `kernelParams.maxCState` | `int` | `1` | `processor.max_cstate` kernel parameter | TSC stability (deep C-states cause drift) |
| `kernelParams.tscReliable` | `bool` | `true` | Pass `tsc=reliable` on kernel command line | TSC source selection |

## SMBIOS

| Option | Type | Default | Description | Detection vector |
|---|---|---|---|---|
| `smbios.manufacturer` | `str` | `"ASUSTeK COMPUTER INC."` | System + baseboard manufacturer (Types 1, 2) | `Win32_ComputerSystem.Manufacturer` |
| `smbios.product` | `str` | `"ROG CROSSHAIR X870E HERO"` | System + baseboard product (Types 1, 2) | `Win32_ComputerSystem.Model` |
| `smbios.biosVendor` | `str` | `"American Megatrends Inc."` | BIOS vendor string (Type 0) | `Win32_BIOS.Manufacturer` |
| `smbios.biosVersion` | `str` | `"2101"` | BIOS version string (Type 0) | `Win32_BIOS.SMBIOSBIOSVersion` |
| `smbios.serial` | `str` | `"System Serial Number"` | System serial number (Type 1) | `Win32_ComputerSystem.SerialNumber` |
| `smbios.socketPrefix` | `str` | `"AM5"` | Processor socket designator prefix (Type 4) | `Win32_Processor.SocketDesignation` |
| `smbios.memory.manufacturer` | `str` | `"G.Skill International"` | DIMM manufacturer (Type 17) | `Win32_PhysicalMemory.Manufacturer` |
| `smbios.memory.partNumber` | `str` | `"F5-6000J3040G32G"` | DIMM part number (Type 17) | `Win32_PhysicalMemory.PartNumber` |
| `smbios.memory.speed` | `int` | `6000` | Memory speed MT/s (Type 17) | `Win32_PhysicalMemory.Speed` |
| `smbios.memory.size` | `int` | `16384` | DIMM size in MB per module (Type 17) | `Win32_PhysicalMemory.Capacity` |
| `smbios.memory.count` | `int` | `2` | Number of DIMMs to report (Type 17) | `Win32_PhysicalMemory` count |

## ACPI SSDT

| Option | Type | Default | Description | Detection vector |
|---|---|---|---|---|
| `acpiSsdt.spoofedDevices` | `bool` | `true` | Include EC, fan, thermal zone, power/sleep buttons, timers | Missing EC/fan/thermal = VM fingerprint |
| `acpiSsdt.fakeBattery` | `bool` | `true` | Include fake ACPI battery (PNP0C0A) in SSDT | Missing battery flags VM detection |

## Network

See "Core" above (`stripVirtio`, `spoofMac`, `macPrefix`).

## Build-time qemu-stealth arguments

These are NOT module options. Pass them via `callPackage` or an overlay
override, e.g.:

```nix
nixpkgs.overlays = [
  (final: prev: {
    qemu-stealth = prev.qemu-stealth.override {
      edidManufacturer = "ASU";
      edidModel = "ASUS PG279Q       ";
      diskModel = "Samsung SSD 990 PRO 2TB ";
    };
  })
];
```

### EDID (display identity)

| Argument | Default | Description | Detection vector |
|---|---|---|---|
| `edidManufacturer` | `"DEL"` | 3-letter EDID manufacturer ID | Monitor manufacturer fingerprint |
| `edidModelAbbrev` | `"DEL     "` | 8-char padded manufacturer abbreviation | EDID block manufacturer field |
| `edidModel` | `"DEL AW2521HFA   "` | 16-char padded monitor model string | EDID block model field |
| `edidSerial` | `"AW2521HFA"` | Monitor serial string | EDID serial number |
| `edidProductCode` | `"0xa161"` | EDID product code (hex) | EDID product code field |
| `edidDpi` | `102` | Monitor DPI | EDID physical size calculation |
| `edidWeek` | `18` | Manufacture week (1-52) | EDID manufacture date |
| `edidYear` | `2021` | Manufacture year | EDID manufacture date |

### Disk / optical

| Argument | Default | Description | Detection vector |
|---|---|---|---|
| `diskModel` | `"Samsung SSD 870 EVO 1TB "` | IDE/SCSI disk model string (24 chars, space-padded) | Disk model reveals QEMU default |
| `opticalModel` | `"ASUS DRW-24B1ST   c    "` | IDE/ATAPI optical drive model string (24 chars) | Optical drive model reveals QEMU |

### ACPI OEM

| Argument | Default | Description | Detection vector |
|---|---|---|---|
| `acpiOemId` | `"ASUS  "` | 6-char padded ACPI OEM ID (replaces `ALASKA`) | ACPI table OEM ID reveals QEMU |
| `acpiOemTableId` | `"ASUS    "` | 8-char padded ACPI OEM Table ID (replaces `A M I`) | ACPI table OEM Table ID |

## Read-only outputs

| Attribute | Type | Description |
|---|---|---|
| `_kernelPostPatch` | shell-script string | Append to `boot.kernelPackages.kernel.overrideAttrs.postPatch` to apply BetterTiming + CPUID-spoof to the kernel build. See [`docs/ARCHITECTURE.md`](ARCHITECTURE.md) §Kernel-integration layering for the full layering. |
