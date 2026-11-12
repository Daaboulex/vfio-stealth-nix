# vfio-stealth-nix: Compatibility

Companion to the top-level [README](../README.md). Which platforms carry
which part of the stack, every detection vector that is covered with the
file that handles it, and the vectors that remain.

## Platforms

The stealth stack is `x86_64-linux` only, and `aarch64-linux` carries only
`stealth-detect`. [`ARCHITECTURE.md`](ARCHITECTURE.md), Architecture support,
says why.

QEMU and OVMF stealth apply on AMD and on Intel. Both vendors are built and
contract-tested, each with the AutoVirt patch family of its vendor.

The kernel-level stealth (`timing.enable`, `cpuidSpoof.enable`,
`cpuidPassthrough.enable`) is AMD/SVM-only. Those patches target
`arch/x86/kvm/svm/svm.c`, which `kvm-intel` never executes. An assertion
refuses that combination rather than shipping a feature that silently does
nothing.

What the checks prove from inside a booted guest, and what they cannot, is in
[`BUILD.md`](BUILD.md), Tests.

## Detection vectors covered

This table is the canonical listing of the covered vectors. Other documents
link here instead of repeating it.

| Vector | Technique | Where |
|---|---|---|
| CPUID hypervisor bit | `kvm.hidden` is always set. The hypervisor bit itself is cleared only when `hypervMode` is `"hidden"`. The Hyper-V vendor_id override applies in enlightened mode | [`lib.nix`](../lib.nix) `features`, `cpuFeatures`, `qemuArgs` |
| CPUID leaf 0 vendor string | Hypervisor-Phantom: intercept at SVM level, override to AuthenticAMD, re-enter guest without full exit | [`kernel/cpuid-patch.nix`](../kernel/cpuid-patch.nix) |
| CPUID interception timing | Disabled entirely via cpuidPassthrough, so guest CPUID runs at native speed | [`kernel/cpuid-disable.nix`](../kernel/cpuid-disable.nix) |
| RDTSC/RDTSCP timing | BetterTiming: track cumulative VM-exit time, subtract from TSC reads (RDTSC + RDTSCP handlers with compensated values) | [`kernel/timing-patch.nix`](../kernel/timing-patch.nix) |
| MSR_IA32_TSC reads | Compensated TSC value returned via patched `kvm_get_msr_common` | [`kernel/timing-patch.nix`](../kernel/timing-patch.nix) |
| IA32_APERF/MPERF MSR | Passthrough via `-cpu host,aperfmperf=on` (covers IET-based detection) | [`lib.nix`](../lib.nix) `qemuArgs` |
| SMBIOS Type 0 (BIOS) | Vendor, version, date, release override | [`module.nix`](../module.nix) options, [`lib.nix`](../lib.nix) `sysinfo` |
| SMBIOS Type 1 (System) | Manufacturer, product, serial, family, UUID | [`module.nix`](../module.nix) options, [`lib.nix`](../lib.nix) `sysinfo` |
| SMBIOS Type 2 (Baseboard) | Manufacturer, product, version, serial, asset tag, location | [`lib.nix`](../lib.nix) `sysinfo` |
| SMBIOS Type 3 (Chassis) | Manufacturer, version, serial, asset tag | [`lib.nix`](../lib.nix) `qemuArgs` |
| SMBIOS Type 4 (Processor) | Socket, manufacturer, version, speed | [`lib.nix`](../lib.nix) `qemuArgs` (via cpuIdentity) |
| SMBIOS Type 7 (Cache) | L1/L2/L3 cache designation and sizes | [`lib.nix`](../lib.nix) `qemuArgs` |
| SMBIOS Type 8 (Port Connector) | USB port descriptors | [`lib.nix`](../lib.nix) `qemuArgs` |
| SMBIOS Type 9 (System Slots) | PCIe slot designation and type | [`lib.nix`](../lib.nix) `qemuArgs` |
| SMBIOS Type 17 (Memory) | DIMM manufacturer, part number, speed, count | [`module.nix`](../module.nix) options, [`lib.nix`](../lib.nix) `qemuArgs` |
| SMBIOS Type 26 (Voltage Probe) | Voltage probe description + min/max | [`lib.nix`](../lib.nix) `qemuArgs` |
| SMBIOS Type 27 (Cooling Device) | Cooling device type + speed | [`lib.nix`](../lib.nix) `qemuArgs` |
| SMBIOS Type 28 (Temperature Probe) | Temperature probe description + min/max | [`lib.nix`](../lib.nix) `qemuArgs` |
| SMBIOS Type 29 (Current Probe) | Current probe description + min/max | [`lib.nix`](../lib.nix) `qemuArgs` |
| ACPI table OEM IDs | The OEM ID and OEM Table ID the AutoVirt patch sets are replaced with the configured `acpiOemId` (6 characters) and `acpiOemTableId` (8 characters) | [`qemu/post-patch.nix`](../qemu/post-patch.nix) |
| ACPI SSDT devices | Power and sleep buttons, AC adapter, timer devices, voltage regulator device, fan, thermal zone | [`acpi/spoofed-devices.dsl`](../acpi/spoofed-devices.dsl) |
| ACPI emulated battery | Control Method Battery (PNP0C0A) with BIF/BST methods | [`acpi/fake-battery.dsl`](../acpi/fake-battery.dsl) |
| EDID display identity | Monitor manufacturer, model, serial, product code, DPI, manufacture date | [`qemu/package.nix`](../qemu/package.nix) arguments, applied in [`qemu/post-patch.nix`](../qemu/post-patch.nix) |
| Disk model string | IDE/SCSI disk model override in QEMU source | [`qemu/post-patch.nix`](../qemu/post-patch.nix) |
| Optical drive model | IDE/ATAPI optical drive model override | [`qemu/post-patch.nix`](../qemu/post-patch.nix) |
| MAC address OUI | Not applied by this flake. The options `spoofMac` and `macPrefix` are declared and read by no code here, so the caller sets the guest NIC's MAC address in its VM definition | [`module.nix`](../module.nix) options |
| Hyper-V enlightenments | `vendor_id` and `relaxed` are on by default. The other eleven (vapic, spinlocks, stimer, frequencies and the rest) are opt-in through `hypervFeatures` | [`lib.nix`](../lib.nix) `features` |
| KVM feature hiding | `kvm.hidden`, `hint-dedicated`, `poll-control` | [`lib.nix`](../lib.nix) `features` |
| VMPort | Disabled | [`lib.nix`](../lib.nix) `features` |
| Clock/timer emulation | kvmclock absent, hypervclock present only when at least one kernel-dependent Hyper-V feature is enabled, native TSC, HPET present | [`lib.nix`](../lib.nix) `clock` |
| OVMF VirtualMachine bit | Cleared in SMBIOS Type 0 via EDK2 patch | AutoVirt EDK2 patch, applied by [`ovmf/post-patch.nix`](../ovmf/post-patch.nix) |
| OVMF PCI vendor IDs | Red Hat IDs replaced with AMD/Intel | AutoVirt EDK2 patch, applied by [`ovmf/post-patch.nix`](../ovmf/post-patch.nix) |
| VirtIO device identifiers | When `stripVirtio` is true, `devicesToRemove` names the balloon, RNG and tablet devices. The caller removes them from its VM definition | [`lib.nix`](../lib.nix) `devicesToRemove` |
| SMBIOS Type 11 (OEM Strings) | Populated with realistic entries (empty Type 11 is a VM indicator) | [`module.nix`](../module.nix) options, [`lib.nix`](../lib.nix) `qemuArgs` |
| SMBIOS Type 41 (Onboard Devices) | One entry per item of `smbios.onboardDevices`. The default list is empty, so no Type 41 entry exists until the caller lists its board's devices | [`module.nix`](../module.nix) options, [`lib.nix`](../lib.nix) `qemuArgs` |
| Disk serial string | IDE drive serial set to the configured `diskSerial` in place of the blank serial AutoVirt leaves. The default, `Default string`, is a placeholder | [`qemu/post-patch.nix`](../qemu/post-patch.nix) |
| fw_cfg DMA signature + ACPI device | 8-byte DMA signature changed from "QEMU CFG" to "QCOM CFG"; fw_cfg ACPI device node removed from DSDT (4-byte probe at selector 0x0000 still reads "QEMU") | AutoVirt patch, applied by [`qemu/post-patch.nix`](../qemu/post-patch.nix) |
| KVM paravirt MSR enforcement | Opt-in, off by default. `kvmPvEnforceCpuid = true` passes `kvm-pv-enforce-cpuid=on`, so guest_pv_has() rejects pvclock/steal-time MSRs when kvm.hidden=on. Otherwise `kvm-pv-enforce-cpuid=off` is passed | [`lib.nix`](../lib.nix) `qemuArgs` |
| KVM hypercall patching | Disabled: emulator_fix_hypercall always injects #UD (bare-metal behavior on VMCALL/VMMCALL) | [`kernel/timing-patch.nix`](../kernel/timing-patch.nix) |
| SVM instruction interception | `kvm_amd.vls=0` + `kvm_amd.vgif=0` force VMLOAD/VMSAVE/STGI/CLGI interception | [`module.nix`](../module.nix) kernel params |
| OVMF boot logo / BGRT | TianoCore LogoDxe + BootGraphicsResourceTableDxe stripped (VMAware CRC indicator) | [`ovmf/post-patch.nix`](../ovmf/post-patch.nix) |
| ACPI thermal zone fluctuation | Timer()-based dynamic temperature in CPU + VRM thermal zones (handles static-value detection) | [`acpi/sensor-probes.dsl`](../acpi/sensor-probes.dsl) |
| PCI subsystem vendor:device | Default 0x1af4:0x1100 (Red Hat/QEMU) replaced with 0x8086:0x0000 (Intel) on all Q35 chipset devices | [`qemu/post-patch.nix`](../qemu/post-patch.nix) |
| QEMU pvpanic device | Consumer excludes `<panic>` from domain XML; verified by [`guest/verify-host.sh`](../guest/verify-host.sh) | [`guest/verify-host.sh`](../guest/verify-host.sh) |
| Registry SCSI DEVICEMAP | Cleaned via guest-side registry script | [`guest/cleanup-registry.ps1`](../guest/cleanup-registry.ps1) |

## Known limitations

These represent current boundaries of software-level VM stealth:

| Limitation | Reason |
|---|---|
| Remote TPM attestation | Cloud-based attestation (e.g. Microsoft Azure Attestation) verifies TPM endorsement keys against manufacturer databases. swtpm keys are not manufacturer-signed and cannot pass remote attestation. No software-only fix. |
| VBS-dependent detection | Detection stacks requiring Virtualization-Based Security (VBS) + `hypervisorlaunchtype=auto` are incompatible with standard KVM guests. VBS means Windows must run under its own Hyper-V hypervisor. |
| Boot-time kernel drivers | Kernel-mode detection drivers that load before the OS can detect hypervisors via multiple vectors beyond CPUID. swtpm satisfies TPM 2.0 presence checks, but detection is independent of TPM state. |
| PCIe root port vendor `1b36:000c` | QEMU's generic PCIe root port uses vendor 1b36 (Red Hat). No upstream override mechanism; patching the root port device type would need a QEMU source change. |
| fw_cfg I/O port probe | Reading 4 bytes from fw_cfg selector 0x0000 returns "QEMU". The DMA signature is patched but the legacy I/O path (ports 0x510/0x511) remains. Requires QEMU source patch to fully suppress. |
| Context-switch timing oracles | Detection libraries (VMAware v2.5+) use context-switch-based clocks independent of TSC. Claims immunity to all TSC/hardware clock spoofing including BetterTiming. An evolving area. |
| XSAVE state identification | Detection of CPUID interception handling via XCR0/XSS size discrepancies. On AMD SVM, VMRUN loads guest XCR0 from the VMCB, which makes leaf 0xD naturally consistent. An evolving area. |
| NPT page-walk latency | Nested Page Table translation adds ~10-20ns per TLB miss. Detectable in theory via microbenchmarks, but high noise floor makes it impractical for false-positive rates. No known detection software uses this. |
| Performance variance | ML-based detection of frame-time jitter from VM exits. BetterTiming + `cpuidPassthrough` substantially reduce but cannot eliminate this surface. |

### Hyper-V enlightenment capability mismatch

Of the 13 Hyper-V enlightenment features in this module, only
`vendor_id` and `relaxed` are unconditional (no KVM cap; libvirt-level
settings). The other 11 (`vapic`, `spinlocks`, `frequencies`,
`vpindex`, `synic`, `stimer`, `reset`, `ipi`, `tlbflush`,
`reenlightenment`, `runtime`) all require `CONFIG_KVM_HYPERV=y` in the
host kernel, a single switch in the kernel. The module's defaults
reflect this: the 11 KVM-gated features default off, the 2 truly
universal features default on. Enable additional features only after
verifying your kernel has `CONFIG_KVM_HYPERV=y` with
`zcat /proc/config.gz | grep KVM_HYPERV`. See
[`OPTIONS.md`](OPTIONS.md) for the `hypervFeatures` options and the
`kernelCapabilities` option.
