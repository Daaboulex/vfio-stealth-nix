# vfio-stealth-nix — Option Reference

Companion to the top-level [README](../README.md). All options live
under the `myModules.vfio.stealth.*` namespace. EDID / disk / optical /
ACPI OEM strings have both module options (for discoverability) and
build-time `qemu-stealth` arguments (for compilation). The build-time
arguments are listed separately at the bottom.

Canonical reference for all `myModules.vfio.stealth.*` options and
`qemu-stealth` build-time arguments.

## Core

| Option              | Type                            | Default          | Description                                                                                                                                                                                                                                                                                                      | Detection vector                       |
| ------------------- | ------------------------------- | ---------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------- |
| `enable`            | `bool`                          | `false`          | Enable the VFIO stealth hardware emulation stack                                                                                                                                                                                                                                                                 | --                                     |
| `stripVirtio`       | `bool`                          | `true`           | Remove VirtIO balloon, RNG, tablet devices from VM config                                                                                                                                                                                                                                                        | VirtIO PCI vendor ID identification    |
| `spoofMac`          | `bool`                          | `true`           | Override guest NIC MAC address with a realistic OUI prefix                                                                                                                                                                                                                                                       | MAC OUI reveals VM NIC vendor          |
| `macPrefix`         | `str`                           | `"D8:BB:C1"`     | OUI prefix for overridden MAC (Realtek OUI matching ASUS X870E onboard LAN)                                                                                                                                                                                                                                      | MAC address OUI                        |
| `aperfMperf`        | `bool`                          | `true`           | Pass through IA32_APERF/MPERF MSRs to guest. Requires kernel 6.18+                                                                                                                                                                                                                                               | IET-based VM detection via MSR absence |
| `hypervVendorId`    | `str` (1-12 chars)              | `"AuthAMDRyzen"` | Hyper-V vendor_id reported to guest. Avoid known VM values (AMDisbetter!, Microsoft Hv)                                                                                                                                                                                                                          | Hyper-V vendor_id identification       |
| `hypervMode`        | `enum ["enlightened" "hidden"]` | `"enlightened"`  | "enlightened" exposes hypervisor + Hyper-V enlightenments. "hidden" conceals the hypervisor and emits no enlightenments                                                                                                                                                                                     | Hyper-V presence detection             |
| `kernelCapabilities` | `nullOr (attrsOf bool)` | `null`       | Per-feature capability set from the host kernel. `null` = assume all features supported (back-compat). Compute via `vfio-stealth-nix.lib.kernelCapabilities.fromConfigPath` in your host config, or set the attrset by hand after `zcat /proc/config.gz \| grep KVM_HYPERV`. See [Kernel capabilities](#kernel-capabilities) | Hyper-V capability mismatches          |

## Hyper-V features

Of the 13 Hyper-V enlightenment features exposed by this module, only
`vendor_id` and `relaxed` are unconditional (no KVM cap; libvirt-level
settings). The other 11 all require `CONFIG_KVM_HYPERV=y` in the host
kernel — verified against `arch/x86/kvm/x86.c:4817-4831` in the Linux
kernel source, which puts every relevant `KVM_CAP_HYPERV_*` cap in a
single `#ifdef CONFIG_KVM_HYPERV` block. To check your kernel:

```
zcat /proc/config.gz | grep KVM_HYPERV
```

| Option                        | Type   | Default | Kernel dep         | Description                                                                            |
| ----------------------------- | ------ | ------- | ------------------ | -------------------------------------------------------------------------------------- |
| `hypervFeatures.vendor_id`    | `bool` | `true`  | --                 | Hyper-V vendor_id exposure. Libvirt-level setting; no KVM cap. Always supported.       |
| `hypervFeatures.relaxed`      | `bool` | `true`  | --                 | Relaxed timing (HvRelax). Libvirt-level setting; no KVM cap. Always supported.          |
| `hypervFeatures.vapic`        | `bool` | `false` | `CONFIG_KVM_HYPERV` | SynIC APIC virtualization (HvApic / `KVM_CAP_HYPERV_VAPIC`).                            |
| `hypervFeatures.spinlocks`    | `bool` | `false` | `CONFIG_KVM_HYPERV` | Spinlock retry reporting (HvSpin / `KVM_CAP_HYPERV_SPIN`).                             |
| `hypervFeatures.frequencies`  | `bool` | `false` | `CONFIG_KVM_HYPERV` | TSC frequency reporting (HvTscPage / `KVM_CAP_HYPERV_TIME`).                           |
| `hypervFeatures.vpindex`      | `bool` | `false` | `CONFIG_KVM_HYPERV` | Virtual processor index (HvVpIndex / `KVM_CAP_HYPERV_VP_INDEX`).                       |
| `hypervFeatures.synic`        | `bool` | `false` | `CONFIG_KVM_HYPERV` | Synthetic interrupt controller (HvSynIC / `KVM_CAP_HYPERV_SYNIC` + `SYNIC2`).            |
| `hypervFeatures.stimer`       | `bool` | `false` | `CONFIG_KVM_HYPERV` | Synthetic timers with direct mode.                                                      |
| `hypervFeatures.reset`        | `bool` | `false` | `CONFIG_KVM_HYPERV` | Hyper-V reset hypercall.                                                                |
| `hypervFeatures.ipi`          | `bool` | `false` | `CONFIG_KVM_HYPERV` | Hyper-V IPI hypercall (`KVM_CAP_HYPERV_SEND_IPI`).                                      |
| `hypervFeatures.tlbflush`     | `bool` | `false` | `CONFIG_KVM_HYPERV` | Hyper-V TLB flush hypercall (`KVM_CAP_HYPERV_TLBFLUSH`).                                |
| `hypervFeatures.reenlightenment` | `bool` | `false` | `CONFIG_KVM_HYPERV` | TSC re-enlightenment notification (HvReenlightenment).                                 |
| `hypervFeatures.runtime`      | `bool` | `false` | `CONFIG_KVM_HYPERV` | Hyper-V runtime (HvRuntime).                                                            |

## Kernel capabilities

`hypervFeatures.*` controls what the lib *requests*; `kernelCapabilities`
controls what the host kernel can actually *provide*. The lib intersects
the two: a feature is emitted only if both the user requests it AND the
host kernel supports it. Features that are requested but unsupported are
dropped from the output, a NixOS warning is emitted naming the missing
`CONFIG_*` option, and the VM starts without the dropped feature (no
libvirt error).

Compute the capability set from the running kernel's `.config` in the
host config:

```nix
{ config, pkgs, vfio-stealth-nix, ... }:
{
  myModules.vfio.stealth.kernelCapabilities =
    vfio-stealth-nix.lib.kernelCapabilities.fromConfigPath
      "${config.boot.kernelPackages.kernel}/.config";
}
```

If the kernel derivation does not expose `.config` in its output, point
at a path the consumer knows exists (e.g. a gunzipped copy of
`/proc/config.gz` placed in the Nix store), or set the attrset by hand:

```nix
myModules.vfio.stealth.kernelCapabilities = {
  vpindex = true;
  synic = true;
  stimer = true;
  reset = true;
  ipi = true;
  tlbflush = true;
  reenlightenment = true;
  runtime = true;
};
```

The `lib/kernel-capabilities.nix` helper also exports `fromConfigText`
(for tests) and `emptyCapabilities` (returns all features = false).
| `kvmPvEnforceCpuid` | `bool`                          | `false`          | Pass `kvm-pv-enforce-cpuid=on` to the guest `-cpu` flag. AutoVirt's QEMU patch flipped the QEMU default to on; that flag faults RDMSR/WRMSR in the KVM paravirt range (0x4b564d00-0x4b564d08) with #GP unless the matching CPUID feature is set, which crashes Windows HAL/HvLoader. Off = pre-AutoVirt behavior | KVM paravirt MSR #GP on Win init       |
| `pciMmio64Mb`       | `int`                           | `65536`          | Size of the OVMF 64-bit PCI MMIO window in MB. 65536 (64 GB) covers GPUs up to 64 GB VRAM. 0 = omit the flag (OVMF uses its default, which may be too small for modern GPUs)                                                                                                                                    | --                                     |

## Kernel

| Option                     | Type   | Default | Description                                                                                                                                                            | Detection vector                                    |
| -------------------------- | ------ | ------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------- |
| `timing.enable`            | `bool` | `true`  | Apply BetterTiming TSC compensation kernel patch                                                                                                                       | RDTSC/RDTSCP timing attacks                         |
| `cpuidSpoof.enable`        | `bool` | `true`  | Apply CPUID leaf 0 override via Hypervisor-Phantom technique                                                                                                           | CPUID vendor string + hypervisor bit                |
| `cpuidPassthrough.enable`  | `bool` | `false` | Disable CPUID interception entirely — guest executes at native speed. Handles TIMER + SINGLE_STEP. Requires AMD host-passthrough. When enabled, cpuidSpoof is skipped. | RDTSC software-counter timing, #DB exception timing |
| `kernelParams.maxCState`   | `int`  | `1`     | `processor.max_cstate` kernel parameter                                                                                                                                | TSC stability (deep C-states cause drift)           |
| `kernelParams.tscReliable` | `bool` | `true`  | Pass `tsc=reliable` on kernel command line                                                                                                                             | TSC source selection                                |

## SMBIOS

| Option                       | Type               | Default                              | Description                                                                                                                                                               | Detection vector                        |
| ---------------------------- | ------------------ | ------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------- |
| `smbios.manufacturer`        | `str`              | `"To Be Filled By O.E.M."`           | System + baseboard manufacturer (Types 1, 2)                                                                                                                              | `Win32_ComputerSystem.Manufacturer`     |
| `smbios.product`             | `str`              | `"To Be Filled By O.E.M."`           | System + baseboard product (Types 1, 2)                                                                                                                                   | `Win32_ComputerSystem.Model`            |
| `smbios.biosVendor`          | `str`              | `"American Megatrends Inc."`         | BIOS vendor string (Type 0)                                                                                                                                               | `Win32_BIOS.Manufacturer`               |
| `smbios.biosVersion`         | `str`              | `"1001"`                             | BIOS version string (Type 0)                                                                                                                                              | `Win32_BIOS.SMBIOSBIOSVersion`          |
| `smbios.biosDate`            | `str`              | `"01/01/2025"`                       | BIOS release date MM/DD/YYYY (Type 0). OVMF default 02/02/2022 is a generic VM date                                                                                       | `Win32_BIOS.ReleaseDate`                |
| `smbios.biosRelease`         | `str`              | `"2.4"`                              | BIOS release version major.minor (Type 0 System BIOS Release field)                                                                                                       | `Win32_BIOS` release fields             |
| `smbios.serial`              | `str`              | `"System Serial Number"`             | System serial number (Type 1)                                                                                                                                             | `Win32_ComputerSystem.SerialNumber`     |
| `smbios.baseBoardVersion`    | `str`              | `"Rev 1.xx"`                         | Baseboard version string (Type 2)                                                                                                                                         | `Win32_BaseBoard.Version`               |
| `smbios.baseBoardSerial`     | `str`              | `"Default string"`                   | Baseboard serial number (Type 2, set from dmidecode)                                                                                                                      | `Win32_BaseBoard.SerialNumber`          |
| `smbios.baseBoardAsset`      | `str`              | `"Default string"`                   | Baseboard asset tag (Type 2)                                                                                                                                              | `Win32_BaseBoard.Tag`                   |
| `smbios.baseBoardLocation`   | `str`              | `"Default string"`                   | Baseboard location in chassis (Type 2)                                                                                                                                    | `Win32_BaseBoard.LocationInChassis`     |
| `smbios.socketPrefix`        | `str`              | `"AM5"`                              | Processor socket designator prefix (Type 4)                                                                                                                               | `Win32_Processor.SocketDesignation`     |
| `smbios.memory.manufacturer` | `str`              | `"Unknown"`                          | DIMM manufacturer (Type 17)                                                                                                                                               | `Win32_PhysicalMemory.Manufacturer`     |
| `smbios.memory.partNumber`   | `str`              | `"Unknown"`                          | DIMM part number (Type 17)                                                                                                                                                | `Win32_PhysicalMemory.PartNumber`       |
| `smbios.memory.speed`        | `int`              | `4800`                               | Memory speed MT/s (Type 17)                                                                                                                                               | `Win32_PhysicalMemory.Speed`            |
| `smbios.memory.count`        | `int`              | `2`                                  | Number of DIMMs to report (Type 17)                                                                                                                                       | `Win32_PhysicalMemory` count            |
| `smbios.oemStrings`          | `listOf str`       | `["Default string" ...]` (4 entries) | OEM Strings for Type 11. Real boards populate 4-6 entries; empty Type 11 is a VM indicator                                                                                | `Win32_ComputerSystem.OEMStringArray`   |
| `smbios.onboardDevices`      | `listOf submodule` | `[ ]`                                | Onboard devices for Type 41 (submodule: designation, kind, instance). Set to match your board. Empty = no Type 41 entries                                                 | `Win32_OnBoardDevice`                   |
| `smbios.cache.l1`            | `int`              | `512`                                | L1 cache size in KB (SMBIOS Type 7)                                                                                                                                       | `Win32_CacheMemory`                     |
| `smbios.cache.l2`            | `int`              | `8192`                               | L2 cache size in KB (SMBIOS Type 7)                                                                                                                                       | `Win32_CacheMemory`                     |
| `smbios.cache.l3`            | `int`              | `32768`                              | L3 cache size in KB (SMBIOS Type 7)                                                                                                                                       | `Win32_CacheMemory`                     |
| `smbios.cache.assocL1`       | `int`              | `7`                                  | SMBIOS Type 7 L1 associativity byte (7 = 8-way, AMD Zen 4/5 L1d)                                                                                                          | `Win32_CacheMemory.Associativity`       |
| `smbios.cache.assocL2`       | `int`              | `7`                                  | SMBIOS Type 7 L2 associativity byte (7 = 8-way)                                                                                                                           | `Win32_CacheMemory.Associativity`       |
| `smbios.cache.assocL3`       | `int`              | `9`                                  | SMBIOS Type 7 L3 associativity byte (9 = 16-way V-Cache; 7 for non-V-Cache)                                                                                               | `Win32_CacheMemory.Associativity`       |
| `smbios.cache.ecc`           | `int`              | `3`                                  | SMBIOS Type 7 error correction type per DSP0134 Table 39 (0 Reserved, 1 Other, 2 Unknown, 3 None, 4 Parity, 5 Single-bit ECC, 6 Multi-bit ECC). Consumer Ryzen has no ECC | `Win32_CacheMemory.ErrorCorrectionType` |

## ACPI SSDT

| Option                    | Type   | Default | Description                                                            | Detection vector                      |
| ------------------------- | ------ | ------- | ---------------------------------------------------------------------- | ------------------------------------- |
| `acpiSsdt.spoofedDevices` | `bool` | `true`  | Include EC, fan, thermal zone, power/sleep buttons, timers             | Missing EC/fan/thermal = VM indicator |
| `acpiSsdt.fakeBattery`    | `bool` | `true`  | Include emulated ACPI battery (PNP0C0A) in SSDT                        | Missing battery is a VM indicator     |
| `acpiSsdt.sensorProbes`   | `bool` | `true`  | Include CPU + VRM thermal zones with Timer()-based dynamic fluctuation | Static/missing thermal data flags VM  |

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
      edidSerial = "PG279Q";
      diskModel = "Samsung SSD 990 PRO 2TB ";
    };
  })
];
```

### EDID (display identity)

The module also exposes `myModules.vfio.stealth.edid.*` options
(`manufacturer`, `serial`, `productCode`, `dpi`, `week`, `year`) that
document the target EDID values for discoverability. The actual EDID
binary is compiled by the build-time arguments below.

| Argument           | Default     | Description                        | Detection vector                |
| ------------------ | ----------- | ---------------------------------- | ------------------------------- |
| `edidManufacturer` | `"ACI"`     | 3-letter EDID manufacturer ID      | Monitor manufacturer identifier |
| `edidSerial`       | `"VG248QE"` | Monitor serial string              | EDID serial number              |
| `edidProductCode`  | `"0x2480"`  | EDID product code (hex)            | EDID product code field         |
| `edidDpi`          | `91`        | Monitor DPI                        | EDID physical size calculation  |
| `edidWeek`         | `22`        | Manufacture week (1-52)            | EDID manufacture date           |
| `edidYear`         | `2020`      | Manufacture year                   | EDID manufacture date           |
| `edidResX`         | `1920`      | Default EDID horizontal resolution | EDID preferred timing           |
| `edidResY`         | `1080`      | Default EDID vertical resolution   | EDID preferred timing           |

### Disk / optical

The module also exposes `myModules.vfio.stealth.disk.*` options (`model`,
`serial`, `opticalModel`) that document the target disk identity values
for discoverability. The actual strings are compiled into QEMU by the
build-time arguments below.

| Argument            | Default                       | Description                                                        | Detection vector                    |
| ------------------- | ----------------------------- | ------------------------------------------------------------------ | ----------------------------------- |
| `diskModel`         | `"WDC WD10EZEX-00WN4A0     "` | IDE/SCSI disk model string (25 chars, space-padded)                | Disk model reveals QEMU default     |
| `diskSerial`        | `"Default string"`            | IDE disk serial string (replaces AutoVirt blank serial)            | Blank disk serial is a VM indicator |
| `opticalModel`      | `"HL-DT-ST DVDRAM GH24NSC0 "` | IDE/ATAPI optical drive model string (25 chars)                    | Optical drive model reveals QEMU    |
| `scsiVendor`        | `"WDC"`                       | SCSI INQUIRY vendor string (8-char T10 format, auto-padded)        | SCSI vendor reveals QEMU default    |
| `scsiTargetProduct` | `"SCSI Disk       "`          | SCSI target product for dead-LUN INQUIRY fallback (16-char padded) | SCSI target product reveals QEMU    |

### ACPI OEM

The module also exposes `myModules.vfio.stealth.acpiOem.*` options (`id`,
`tableId`) that document the target ACPI OEM identity values for
discoverability. The actual table headers are compiled into QEMU by the
build-time arguments below.

| Argument         | Default      | Description                     | Detection vector               |
| ---------------- | ------------ | ------------------------------- | ------------------------------ |
| `acpiOemId`      | `"ALASKA"`   | 6-char ACPI OEM ID              | ACPI table OEM ID reveals QEMU |
| `acpiOemTableId` | `"A M I   "` | 8-char padded ACPI OEM Table ID | ACPI table OEM Table ID        |

## CPU Identity

| Option                     | Type         | Default | Description                                                                                            | Detection vector                    |
| -------------------------- | ------------ | ------- | ------------------------------------------------------------------------------------------------------ | ----------------------------------- |
| `cpuIdentity.manufacturer` | `nullOr str` | `null`  | CPU manufacturer for SMBIOS Type 4. null = "Advanced Micro Devices, Inc." Set to your CPU vendor string | `Win32_Processor.Manufacturer`      |
| `cpuIdentity.modelId`      | `nullOr str` | `null`  | CPU model string for SMBIOS Type 4 + QEMU `-global cpu.model-id`. null = use host CPU                  | `Win32_Processor.Name`              |
| `cpuIdentity.maxSpeed`     | `nullOr int` | `null`  | Max CPU speed in MHz (Type 4). null = omit                                            | `Win32_Processor.MaxClockSpeed`     |
| `cpuIdentity.currentSpeed` | `nullOr int` | `null`  | Current CPU speed in MHz (Type 4). null = omit                                        | `Win32_Processor.CurrentClockSpeed` |

## TPM Identity

| Option                     | Type   | Default                   | Description                                                    | Detection vector                |
| -------------------------- | ------ | ------------------------- | -------------------------------------------------------------- | ------------------------------- |
| `tpm.harden`               | `bool` | `true`                    | Configure swtpm to report realistic hardware TPM identity      | swtpm defaults report IBM/swtpm |
| `tpm.manufacturer`         | `str`  | `"id:49465800"`           | TPM manufacturer ID (8 hex digits). id:49465800=Infineon       | Win32_Tpm manufacturer          |
| `tpm.model`                | `str`  | `"SLB9672"`               | TPM model string. SLB9672 = Infineon discrete TPM              | Win32_Tpm model                 |
| `tpm.firmwareVersion`      | `str`  | `"id:000F0018"`           | TPM firmware version. 0x000F0018 = FW 15.24 (Infineon SLB9672) | Win32_Tpm firmware version      |
| `tpm.platformManufacturer` | `str`  | `"ASUSTeK COMPUTER INC."` | Platform manufacturer for TPM platform certificate             | TPM platform certificate        |
| `tpm.platformModel`        | `str`  | `"System Product Name"`   | Platform model for TPM platform certificate                    | TPM platform certificate        |

## Read-only outputs

| Attribute               | Type                | Description                                                                                                                                                                                                         |
| ----------------------- | ------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `_kernelPostPatch`      | shell-script string | Append to `boot.kernelPackages.kernel.overrideAttrs.postPatch` to apply BetterTiming + CPUID emulation/passthrough to the kernel build. See [`docs/ARCHITECTURE.md`](ARCHITECTURE.md) §Kernel-integration layering. |
| `_libtpmsIdentityPatch` | shell-script string | Append to `libtpms.overrideAttrs.postPatch` to replace hardcoded IBM/swtpm identity with configured TPM manufacturer/model.                                                                                         |
