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
| `macPrefix` | `str` | `"D8:BB:C1"` | OUI prefix for spoofed MAC (Realtek OUI matching ASUS X870E onboard LAN) | MAC address OUI |
| `aperfMperf` | `bool` | `true` | Pass through IA32_APERF/MPERF MSRs to guest. Requires kernel 6.18+ | IET-based VM detection via MSR absence |
| `hypervVendorId` | `str` (1-12 chars) | `"AuthAMDRyzen"` | Hyper-V vendor_id reported to guest. Avoid known VM values (AMDisbetter!, Microsoft Hv) | Hyper-V vendor_id fingerprinting |

## Kernel

| Option | Type | Default | Description | Detection vector |
|---|---|---|---|---|
| `timing.enable` | `bool` | `true` | Apply BetterTiming TSC compensation kernel patch | RDTSC/RDTSCP timing attacks |
| `cpuidSpoof.enable` | `bool` | `true` | Apply CPUID leaf 0 spoof via Hypervisor-Phantom technique | CPUID vendor string + hypervisor bit |
| `cpuidPassthrough.enable` | `bool` | `false` | Disable CPUID interception entirely — guest executes at native speed. Defeats TIMER + SINGLE_STEP. Requires AMD host-passthrough. When enabled, cpuidSpoof is skipped. | RDTSC software-counter timing, #DB exception timing |
| `kernelParams.maxCState` | `int` | `1` | `processor.max_cstate` kernel parameter | TSC stability (deep C-states cause drift) |
| `kernelParams.tscReliable` | `bool` | `true` | Pass `tsc=reliable` on kernel command line | TSC source selection |

## SMBIOS

| Option | Type | Default | Description | Detection vector |
|---|---|---|---|---|
| `smbios.manufacturer` | `str` | `"To Be Filled By O.E.M."` | System + baseboard manufacturer (Types 1, 2) | `Win32_ComputerSystem.Manufacturer` |
| `smbios.product` | `str` | `"To Be Filled By O.E.M."` | System + baseboard product (Types 1, 2) | `Win32_ComputerSystem.Model` |
| `smbios.biosVendor` | `str` | `"American Megatrends Inc."` | BIOS vendor string (Type 0) | `Win32_BIOS.Manufacturer` |
| `smbios.biosVersion` | `str` | `"1001"` | BIOS version string (Type 0) | `Win32_BIOS.SMBIOSBIOSVersion` |
| `smbios.biosDate` | `str` | `"01/01/2025"` | BIOS release date MM/DD/YYYY (Type 0). OVMF default 02/02/2022 is a generic VM date | `Win32_BIOS.ReleaseDate` |
| `smbios.biosRelease` | `str` | `"2.4"` | BIOS release version major.minor (Type 0 System BIOS Release field) | `Win32_BIOS` release fields |
| `smbios.serial` | `str` | `"System Serial Number"` | System serial number (Type 1) | `Win32_ComputerSystem.SerialNumber` |
| `smbios.baseBoardVersion` | `str` | `"Rev 1.xx"` | Baseboard version string (Type 2) | `Win32_BaseBoard.Version` |
| `smbios.baseBoardSerial` | `str` | `"Default string"` | Baseboard serial number (Type 2, set from dmidecode) | `Win32_BaseBoard.SerialNumber` |
| `smbios.baseBoardAsset` | `str` | `"Default string"` | Baseboard asset tag (Type 2) | `Win32_BaseBoard.Tag` |
| `smbios.baseBoardLocation` | `str` | `"Default string"` | Baseboard location in chassis (Type 2) | `Win32_BaseBoard.LocationInChassis` |
| `smbios.socketPrefix` | `str` | `"AM5"` | Processor socket designator prefix (Type 4) | `Win32_Processor.SocketDesignation` |
| `smbios.memory.manufacturer` | `str` | `"Unknown"` | DIMM manufacturer (Type 17) | `Win32_PhysicalMemory.Manufacturer` |
| `smbios.memory.partNumber` | `str` | `"Unknown"` | DIMM part number (Type 17) | `Win32_PhysicalMemory.PartNumber` |
| `smbios.memory.speed` | `int` | `4800` | Memory speed MT/s (Type 17) | `Win32_PhysicalMemory.Speed` |
| `smbios.memory.size` | `int` | `16384` | DIMM size in MB per module (Type 17) | `Win32_PhysicalMemory.Capacity` |
| `smbios.memory.count` | `int` | `2` | Number of DIMMs to report (Type 17) | `Win32_PhysicalMemory` count |
| `smbios.oemStrings` | `listOf str` | `["Default string" ...]` (4 entries) | OEM Strings for Type 11. Real boards populate 4-6 entries; empty Type 11 is a VM indicator | `Win32_ComputerSystem.OEMStringArray` |
| `smbios.onboardDevices` | `listOf submodule` | Ethernet + SATA controller | Onboard devices for Type 41 (submodule: designation, kind, instance). Prevents empty Win32_OnBoardDevice | `Win32_OnBoardDevice` |
| `smbios.cache.l1` | `int` | `512` | L1 cache size in KB (SMBIOS Type 7) | `Win32_CacheMemory` |
| `smbios.cache.l2` | `int` | `8192` | L2 cache size in KB (SMBIOS Type 7) | `Win32_CacheMemory` |
| `smbios.cache.l3` | `int` | `32768` | L3 cache size in KB (SMBIOS Type 7) | `Win32_CacheMemory` |

## ACPI SSDT

| Option | Type | Default | Description | Detection vector |
|---|---|---|---|---|
| `acpiSsdt.spoofedDevices` | `bool` | `true` | Include EC, fan, thermal zone, power/sleep buttons, timers | Missing EC/fan/thermal = VM fingerprint |
| `acpiSsdt.fakeBattery` | `bool` | `true` | Include fake ACPI battery (PNP0C0A) in SSDT | Missing battery flags VM detection |
| `acpiSsdt.sensorProbes` | `bool` | `true` | Include CPU + VRM thermal zones with Timer()-based dynamic fluctuation | Static/missing thermal data flags VM |

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
| `edidManufacturer` | `"ACI"` | 3-letter EDID manufacturer ID | Monitor manufacturer fingerprint |
| `edidModelAbbrev` | `"ACI     "` | 8-char padded manufacturer abbreviation | EDID block manufacturer field |
| `edidModel` | `"ASUS VG248      "` | 16-char padded monitor model string | EDID block model field |
| `edidSerial` | `"VG248QE"` | Monitor serial string | EDID serial number |
| `edidProductCode` | `"0x2480"` | EDID product code (hex) | EDID product code field |
| `edidDpi` | `91` | Monitor DPI | EDID physical size calculation |
| `edidWeek` | `22` | Manufacture week (1-52) | EDID manufacture date |
| `edidYear` | `2020` | Manufacture year | EDID manufacture date |

### Disk / optical

| Argument | Default | Description | Detection vector |
|---|---|---|---|
| `diskModel` | `"WDC WD10EZEX-00WN4A0     "` | IDE/SCSI disk model string (25 chars, space-padded) | Disk model reveals QEMU default |
| `diskSerial` | `"Default string"` | IDE disk serial string (replaces AutoVirt blank serial) | Blank disk serial is a VM indicator |
| `opticalModel` | `"HL-DT-ST DVDRAM GH24NSC0 "` | IDE/ATAPI optical drive model string (25 chars) | Optical drive model reveals QEMU |

### ACPI OEM

| Argument | Default | Description | Detection vector |
|---|---|---|---|
| `acpiOemId` | `"ALASKA"` | 6-char ACPI OEM ID | ACPI table OEM ID reveals QEMU |
| `acpiOemTableId` | `"A M I   "` | 8-char padded ACPI OEM Table ID | ACPI table OEM Table ID |

## Read-only outputs

| Attribute | Type | Description |
|---|---|---|
| `_kernelPostPatch` | shell-script string | Append to `boot.kernelPackages.kernel.overrideAttrs.postPatch` to apply BetterTiming + CPUID-spoof to the kernel build. See [`docs/ARCHITECTURE.md`](ARCHITECTURE.md) §Kernel-integration layering for the full layering. |
