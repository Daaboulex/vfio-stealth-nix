# Options

Every option the modules of this flake declare. This file is generated from the module sources: change a description there, then run `nix run .#std-write-option-reference`.

## NixOS module

Declared in [module.nix](../module.nix).

### `virtualisation.vfio-stealth.enable`

Whether to enable VFIO hardware emulation stack.

Type: `boolean`. Default: `false`.

### `virtualisation.vfio-stealth.acpiOem.id`

6-char ACPI OEM ID (padded with spaces). Populates ACPI table header OEM ID field.

Type: `string`. Default: `"ALASKA"`.

### `virtualisation.vfio-stealth.acpiOem.tableId`

8-char ACPI OEM Table ID (padded with spaces). Populates ACPI table header OEM Table ID field.

Type: `string`. Default: `"A M I   "`.

### `virtualisation.vfio-stealth.acpiSsdt.fakeBattery`

Include an emulated ACPI battery device in the SSDT table. Covers the 'no battery = server/VM' heuristic.

Type: `boolean`. Default: `true`.

### `virtualisation.vfio-stealth.acpiSsdt.sensorProbes`

Include CPU and VRM thermal zone probes (covers MSAcpi_ThermalZoneTemperature WMI checks).

Type: `boolean`. Default: `true`.

### `virtualisation.vfio-stealth.acpiSsdt.spoofedDevices`

Include emulated ACPI device entries in the SSDT table. Covers ACPI namespace enumeration checks.

Type: `boolean`. Default: `true`.

### `virtualisation.vfio-stealth.aperfMperf`

Pass through IA32_APERF/MPERF MSRs to guest (addresses IET-based VM indicators). Requires kernel 6.18+.

Type: `boolean`. Default: `true`.

### `virtualisation.vfio-stealth.cpuIdentity.currentSpeed`

CPU current speed in MHz for SMBIOS type 4. null = omit.

Type: `null or signed integer`. Default: `null`.

### `virtualisation.vfio-stealth.cpuIdentity.manufacturer`

CPU manufacturer for SMBIOS type 4. null = 'Advanced Micro Devices, Inc.' Set to your CPU vendor (e.g. 'GenuineIntel' for Intel hosts).

Type: `null or string`. Default: `null`.

### `virtualisation.vfio-stealth.cpuIdentity.maxSpeed`

CPU max speed in MHz for SMBIOS type 4. null = omit.

Type: `null or signed integer`. Default: `null`.

### `virtualisation.vfio-stealth.cpuIdentity.modelId`

CPU model string reported to guest (e.g. 'AMD Ryzen 7 7800X3D 8-Core Processor'). null = use host CPU.

Type: `null or string`. Default: `null`.

### `virtualisation.vfio-stealth.cpuVendor`

Host CPU vendor. Selects the AutoVirt patch set and the ACPI OEM identity the QEMU postPatch rewrites. There is deliberately no default: a mismatch builds cleanly and yields a guest whose spoofed CPU vendor contradicts the host.

Type: `null or one of "amd", "intel"`. Default: `null`. Example: `"amd"`.

### `virtualisation.vfio-stealth.cpuidPassthrough.enable`

Disable CPUID interception entirely. Guest executes CPUID at native hardware speed (zero VM exit). Addresses software-counter timing checks (VMAware TIMER 95pts, SINGLE_STEP 100pts). Requires AMD host with host-passthrough CPU mode. When enabled, cpuidSpoof is skipped (passthrough takes precedence). Side effect: Hyper-V enlightenments are invisible to guest (Windows uses TSC directly). LIMITATION: the guest sees the host's raw topology (core count, thread count, NUMA nodes) via CPUID -- if the VM has fewer vCPUs than the host has threads, Windows deadlocks at boot waiting for processors that do not exist.

Type: `boolean`. Default: `false`.

### `virtualisation.vfio-stealth.cpuidSpoof.enable`

CPUID leaf 0 emulation via Hypervisor-Phantom technique. Covers the hypervisor-present CPUID bit (leaf 1, bit 31) and hypervisor vendor string (leaf 0x40000000). Skipped when cpuidPassthrough.enable is true.

Type: `boolean`. Default: `true`.

### `virtualisation.vfio-stealth.disk.model`

Emulated disk model string (25 chars, space-padded). Populates Win32_DiskDrive.Model. Set to your real disk model.

Type: `string`. Default: `"WDC WD10EZEX-00WN4A0     "`.

### `virtualisation.vfio-stealth.disk.opticalModel`

Emulated optical drive model (25 chars, space-padded). Populates Win32_CDROMDrive.Name.

Type: `string`. Default: `"HL-DT-ST DVDRAM GH24NSC0 "`.

### `virtualisation.vfio-stealth.disk.serial`

IDE/SCSI disk serial string. Populates Win32_DiskDrive.SerialNumber. Set to your real disk serial from smartctl.

Type: `string`. Default: `"Default string"`.

### `virtualisation.vfio-stealth.edid.dpi`

Monitor DPI.

Type: `signed integer`. Default: `91`.

### `virtualisation.vfio-stealth.edid.manufacturer`

3-char EDID manufacturer code.

Type: `string`. Default: `"ACI"`.

### `virtualisation.vfio-stealth.edid.productCode`

EDID product code (hex).

Type: `string`. Default: `"0x2480"`.

### `virtualisation.vfio-stealth.edid.serial`

Monitor serial string.

Type: `string`. Default: `"VG248QE"`.

### `virtualisation.vfio-stealth.edid.week`

EDID manufacture week.

Type: `signed integer`. Default: `22`.

### `virtualisation.vfio-stealth.edid.year`

EDID manufacture year.

Type: `signed integer`. Default: `2020`.

### `virtualisation.vfio-stealth.hypervFeatures.frequencies`

TSC frequency reporting (HvTscPage). Requires CONFIG_KVM_HYPERV=y (KVM_CAP_HYPERV_TIME); libvirt errors with 'host doesn't support hyperv frequencies' otherwise.

Type: `boolean`. Default: `false`.

### `virtualisation.vfio-stealth.hypervFeatures.ipi`

Hyper-V IPI hypercall. Requires CONFIG_KVM_HYPERV=y.

Type: `boolean`. Default: `false`.

### `virtualisation.vfio-stealth.hypervFeatures.reenlightenment`

TSC re-enlightenment notification (HvReenlightenment). Requires CONFIG_KVM_HYPERV=y.

Type: `boolean`. Default: `false`.

### `virtualisation.vfio-stealth.hypervFeatures.relaxed`

Relaxed timing (HvRelax). QEMU/libvirt-level setting with no KVM cap; always supported.

Type: `boolean`. Default: `true`.

### `virtualisation.vfio-stealth.hypervFeatures.reset`

Hyper-V reset hypercall. Requires CONFIG_KVM_HYPERV=y.

Type: `boolean`. Default: `false`.

### `virtualisation.vfio-stealth.hypervFeatures.runtime`

Hyper-V runtime (HvRuntime). Requires CONFIG_KVM_HYPERV=y.

Type: `boolean`. Default: `false`.

### `virtualisation.vfio-stealth.hypervFeatures.spinlocks`

Spinlock retry reporting (HvSpin). Requires CONFIG_KVM_HYPERV=y (KVM_CAP_HYPERV_SPIN); libvirt errors with 'host doesn't support hyperv spinlocks' otherwise.

Type: `boolean`. Default: `false`.

### `virtualisation.vfio-stealth.hypervFeatures.stimer`

Synthetic timers (HvSyntheticTimers) with direct mode. Requires CONFIG_KVM_HYPERV=y.

Type: `boolean`. Default: `false`.

### `virtualisation.vfio-stealth.hypervFeatures.synic`

Synthetic interrupt controller (HvSynIC). Requires CONFIG_KVM_HYPERV=y.

Type: `boolean`. Default: `false`.

### `virtualisation.vfio-stealth.hypervFeatures.tlbflush`

Hyper-V TLB flush hypercall. Requires CONFIG_KVM_HYPERV=y.

Type: `boolean`. Default: `false`.

### `virtualisation.vfio-stealth.hypervFeatures.vapic`

SynIC APIC virtualization (HvApic). Requires CONFIG_KVM_HYPERV=y in the host kernel (KVM_CAP_HYPERV_VAPIC); libvirt errors with 'host doesn't support hyperv vapic' otherwise.

Type: `boolean`. Default: `false`.

### `virtualisation.vfio-stealth.hypervFeatures.vendor_id`

Hyper-V vendor_id exposure. Libvirt-level setting with no KVM cap; always supported.

Type: `boolean`. Default: `true`.

### `virtualisation.vfio-stealth.hypervFeatures.vpindex`

Virtual processor index (HvVpIndex). Requires CONFIG_KVM_HYPERV=y in the host kernel. Enables libvirtError: 'host doesn't support hyperv vpindex' if requested on a kernel that does not advertise it.

Type: `boolean`. Default: `false`.

### `virtualisation.vfio-stealth.hypervMode`

Hyper-V enlightenment strategy for hardened VMs. "enlightened" exposes the hypervisor + Hyper-V enlightenments (paravirt perf; blends in with VBS-enabled Windows 11). "hidden" conceals the hypervisor and emits no enlightenments. Per-VM overridable via vms.<name>.hypervMode

Type: `one of "enlightened", "hidden"`. Default: `"enlightened"`.

### `virtualisation.vfio-stealth.hypervVendorId`

Hyper-V vendor_id reported to guest (1–12 chars, libvirt hard limit). Avoid well-known VM values like 'AMDisbetter!' or 'Microsoft Hv'.

Type: `string matching the pattern ^.{1,12}$`. Default: `"AuthAMDRyzen"`.

### `virtualisation.vfio-stealth.kernelCapabilities`

Per-feature capability set from the host kernel. null = assume all features supported (back-compat). Compute via lib.kernelCapabilities.fromConfigPath in your host config, or set the attrset by hand after running zcat /proc/config.gz | grep KVM_HYPERV on the host.

Type: `null or (attribute set of boolean)`. Default: `null`.

### `virtualisation.vfio-stealth.kernelParams.maxCState`

processor.max_cstate value passed on the kernel command line. Lower values reduce timing jitter that can reveal virtualization.

Type: `signed integer`. Default: `1`.

### `virtualisation.vfio-stealth.kernelParams.tscReliable`

Pass tsc=reliable on the kernel command line. Prevents kernel from falling back to HPET/ACPI PM timer, which detection software can flag.

Type: `boolean`. Default: `true`.

### `virtualisation.vfio-stealth.kernelPostPatch`

Combined kernel postPatch script. Apply via kernel overrideAttrs in host config.

Type: `string`. Default: `""`. Read only.

### `virtualisation.vfio-stealth.kvmPvEnforceCpuid`

Pass kvm-pv-enforce-cpuid=on to the guest -cpu flag. AutoVirt's default is on; Windows guests without the matching CPUID feature fault with #GP in early HAL init. Off = pre-AutoVirt behavior. Per-VM override available via the consumer's vms.nix kvmPvEnforceCpuid option.

Type: `boolean`. Default: `false`.

### `virtualisation.vfio-stealth.libtpmsIdentityPatch`

libtpms postPatch script that replaces hardcoded IBM/swtpm identity. Apply via libtpms.overrideAttrs in host config.

Type: `string`. Default: `""`. Read only.

### `virtualisation.vfio-stealth.macPrefix`

OUI prefix used when spoofMac is enabled (colon-separated hex, e.g. D8:BB:C1). Realtek OUI matching ASUS X870E onboard NIC.

Type: `string matching the pattern ^[0-9A-Fa-f]{2}:[0-9A-Fa-f]{2}:[0-9A-Fa-f]{2}$`. Default: `"D8:BB:C1"`.

### `virtualisation.vfio-stealth.pciMmio64Mb`

Size of the OVMF 64-bit PCI MMIO window in megabytes. 65536 (64 GB) covers GPUs up to 64 GB VRAM. Set to 0 to omit the flag (OVMF uses its default, which may be too small for modern GPUs).

Type: `signed integer`. Default: `65536`.

### `virtualisation.vfio-stealth.smbios.baseBoardAsset`

Baseboard asset tag (SMBIOS Type 2).

Type: `string`. Default: `"Default string"`.

### `virtualisation.vfio-stealth.smbios.baseBoardLocation`

Baseboard location in chassis (SMBIOS Type 2).

Type: `string`. Default: `"Default string"`.

### `virtualisation.vfio-stealth.smbios.baseBoardSerial`

Baseboard serial number (SMBIOS Type 2). Set to your real board serial from dmidecode.

Type: `string`. Default: `"Default string"`.

### `virtualisation.vfio-stealth.smbios.baseBoardVersion`

Baseboard version string (SMBIOS Type 2). Populates Win32_BaseBoard.Version.

Type: `string`. Default: `"Rev 1.xx"`.

### `virtualisation.vfio-stealth.smbios.biosDate`

BIOS release date (MM/DD/YYYY format). Populates Win32_BIOS.ReleaseDate. OVMF defaults to 02/02/2022 which is a generic VM date. Set to your board's actual BIOS date.

Type: `string`. Default: `"01/01/2025"`.

### `virtualisation.vfio-stealth.smbios.biosRelease`

BIOS release version (major.minor). Maps to SMBIOS Type 0 System BIOS Release field.

Type: `string`. Default: `"2.4"`.

### `virtualisation.vfio-stealth.smbios.biosVendor`

SMBIOS BIOS vendor string. Populates WMI Win32_BIOS.Manufacturer.

Type: `string`. Default: `"American Megatrends Inc."`.

### `virtualisation.vfio-stealth.smbios.biosVersion`

SMBIOS BIOS version string. Populates WMI Win32_BIOS.SMBIOSBIOSVersion.

Type: `string`. Default: `"1001"`.

### `virtualisation.vfio-stealth.smbios.cache.assocL1`

SMBIOS type 7 associativity byte for L1 (7 = 8-way, the AMD Zen 4/5 L1d value). Other common: 9 (16-way), 6 (fully associative). See DSP0134 Table 36.

Type: `signed integer`. Default: `7`.

### `virtualisation.vfio-stealth.smbios.cache.assocL2`

SMBIOS type 7 associativity byte for L2 (7 = 8-way, the AMD Zen 4/5 L2 value).

Type: `signed integer`. Default: `7`.

### `virtualisation.vfio-stealth.smbios.cache.assocL3`

SMBIOS type 7 associativity byte for L3 (9 = 16-way, the AMD Zen 4/5 V-Cache value; use 7 for non-V-Cache CCDs).

Type: `signed integer`. Default: `9`.

### `virtualisation.vfio-stealth.smbios.cache.ecc`

SMBIOS type 7 error correction type per DSP0134 Table 39. 0 = Reserved, 1 = Other, 2 = Unknown, 3 = None, 4 = Parity, 5 = Single-bit ECC, 6 = Multi-bit ECC. Consumer Ryzen has no cache ECC; server EPYC has parity on L3.

Type: `signed integer`. Default: `3`.

### `virtualisation.vfio-stealth.smbios.cache.l1`

L1 cache size in KB for SMBIOS type 7.

Type: `signed integer`. Default: `512`.

### `virtualisation.vfio-stealth.smbios.cache.l2`

L2 cache size in KB for SMBIOS type 7.

Type: `signed integer`. Default: `8192`.

### `virtualisation.vfio-stealth.smbios.cache.l3`

L3 cache size in KB for SMBIOS type 7.

Type: `signed integer`. Default: `32768`.

### `virtualisation.vfio-stealth.smbios.manufacturer`

SMBIOS system manufacturer string. Populates WMI Win32_ComputerSystem.Manufacturer.

Type: `string`. Default: `"To Be Filled By O.E.M."`.

### `virtualisation.vfio-stealth.smbios.memory.count`

Number of DIMMs to report.

Type: `signed integer`. Default: `2`.

### `virtualisation.vfio-stealth.smbios.memory.manufacturer`

DIMM manufacturer for SMBIOS type 17. Populates WMI Win32_PhysicalMemory.Manufacturer. Set to your real RAM vendor.

Type: `string`. Default: `"Unknown"`.

### `virtualisation.vfio-stealth.smbios.memory.partNumber`

DIMM part number. Populates WMI Win32_PhysicalMemory.PartNumber. Set to your real DIMM part number.

Type: `string`. Default: `"Unknown"`.

### `virtualisation.vfio-stealth.smbios.memory.speed`

Memory speed in MT/s. Populates WMI Win32_PhysicalMemory.Speed.

Type: `signed integer`. Default: `4800`.

### `virtualisation.vfio-stealth.smbios.oemStrings`

OEM Strings for SMBIOS Type 11. Real boards populate 4-6 entries. Empty Type 11 is a VM indicator.

Type: `list of string`.

Default:

```nix
[
  "Default string"
  "Default string"
  "Default string"
  "Default string"
]
```

### `virtualisation.vfio-stealth.smbios.onboardDevices`

Onboard devices for SMBIOS Type 41. Set to match your board (e.g., LAN, SATA controllers from dmidecode -t 41). Empty = no Type 41 entries.

Type: `list of (submodule)`. Default: `[ ]`.

### `virtualisation.vfio-stealth.smbios.onboardDevices.*.designation`

Device designation string.

Type: `string`.

### `virtualisation.vfio-stealth.smbios.onboardDevices.*.instance`

Device instance number.

Type: `signed integer`.

### `virtualisation.vfio-stealth.smbios.onboardDevices.*.kind`

Device type.

Type: `one of "other", "unknown", "video", "scsi", "ethernet", "tokenring", "sound", "pata", "sata", "sas"`.

### `virtualisation.vfio-stealth.smbios.product`

SMBIOS product name string. Populates WMI Win32_ComputerSystem.Model.

Type: `string`. Default: `"To Be Filled By O.E.M."`.

### `virtualisation.vfio-stealth.smbios.serial`

SMBIOS system serial number. Populates WMI Win32_ComputerSystemProduct.IdentifyingNumber.

Type: `string`. Default: `"System Serial Number"`.

### `virtualisation.vfio-stealth.smbios.socketPrefix`

SMBIOS processor socket designator prefix (type 4). Populates WMI Win32_Processor.SocketDesignation.

Type: `string`. Default: `"AM5"`.

### `virtualisation.vfio-stealth.spoofMac`

Override guest NIC MAC address with a realistic OUI prefix. Covers MAC OUI-based VM indicators.

Type: `boolean`. Default: `true`.

### `virtualisation.vfio-stealth.stripVirtio`

Remove VirtIO balloon, RNG, and tablet devices from VM config when hardware emulation is enabled. Covers PCI device enumeration checks.

Type: `boolean`. Default: `true`.

### `virtualisation.vfio-stealth.timing.enable`

BetterTiming TSC compensation (hides VM exit timing from guests). Compensates RDTSC timing deltas from VM exits across CPUID/VMCALL. Also disables KVM hypercall instruction patching HOST-WIDE, so every VM on this host gets #UD for VMCALL/VMMCALL and Linux guests lose KVM paravirt features (kvmclock, PV TLB flush).

Type: `boolean`. Default: `true`.

### `virtualisation.vfio-stealth.tpm.firmwareVersion`

TPM firmware version (8 hex digits). 0x000F0018 = FW 15.24 (Infineon SLB9672).

Type: `string matching the pattern ^[a-zA-Z0-9:]+$`. Default: `"id:000F0018"`.

### `virtualisation.vfio-stealth.tpm.harden`

Configure swtpm to report realistic hardware TPM identity. Affects EK/platform certificates (swtpm-localca.options) and protocol-level properties (libtpms patch).

Type: `boolean`. Default: `true`.

### `virtualisation.vfio-stealth.tpm.manufacturer`

TPM manufacturer ID (8 hex digits). id:49465800=Infineon, id:414D4400=AMD fTPM, id:494E5443=Intel PTT.

Type: `string matching the pattern ^[a-zA-Z0-9:]+$`. Default: `"id:49465800"`.

### `virtualisation.vfio-stealth.tpm.model`

TPM model string. Common: SLB9672 (Infineon discrete), AMD (fTPM).

Type: `string matching the pattern ^[a-zA-Z0-9 _-]+$`. Default: `"SLB9672"`.

### `virtualisation.vfio-stealth.tpm.platformManufacturer`

Platform manufacturer for TPM platform certificate. Should match SMBIOS manufacturer.

Type: `string`. Default: `"ASUSTeK COMPUTER INC."`.

### `virtualisation.vfio-stealth.tpm.platformModel`

Platform model for TPM platform certificate.

Type: `string`. Default: `"System Product Name"`.
