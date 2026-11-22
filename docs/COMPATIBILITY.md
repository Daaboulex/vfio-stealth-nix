# Compatibility

Which platforms carry which part of the stack, every detection vector that is
covered with the file that handles it, and the limits that remain.

## Platforms

- The stealth stack is `x86_64-linux` only, pinned by `meta.platforms`: the AutoVirt QEMU patches edit `hw/i386/`, `hw/isa/lpc_ich9.c` and `hw/ide/`, the EDK2 patches edit `OvmfPkgX64`, and the kernel patches edit KVM's x86 code under `arch/x86/kvm/`.
- `aarch64-linux` carries only `stealth-detect` and the checks that need no x86 host. On aarch64 `pkgs.OVMF` is ArmVirtQemu, and nothing is spoofed.
- An aarch64 guest's CPU identity registers (`MIDR_EL1`, `REVIDR_EL1`, `AIDR_EL1`) are set from userspace through `KVM_SET_ONE_REG`, not by patching KVM, so the x86 approach does not carry over. [scripts/update.sh](../scripts/update.sh) reports when QEMU's ARM KVM backend can set them.
- QEMU and OVMF stealth apply on AMD and Intel hosts, each with its own vendor's AutoVirt patches.
- `timing`, `cpuidSpoof` and `cpuidPassthrough` patch KVM's SVM code and are AMD only; [DESIGN.md](DESIGN.md) says why. `instructionFixes` applies on both vendors: vfio-native 0002 and 0003 on both, 0001, 0004 and the #GP mapping of [kernel/svm-instruction-fixes.nix](../kernel/svm-instruction-fixes.nix) on AMD only. Every kernel switch acts only in a kernel built through `packages.kernelFor`.

What the checks prove from inside a booted guest is in
[DEVELOPMENT.md](DEVELOPMENT.md). What each AutoVirt change becomes is in
[AUTOVIRT.md](AUTOVIRT.md).

## Detection vectors covered

| Vector | Technique | Where |
| - | - | - |
| CPUID hypervisor bit | `kvm.hidden` always set; the hypervisor bit cleared only when `hypervMode` is `"hidden"`; the Hyper-V vendor_id override in enlightened mode | [lib.nix](../lib.nix) `features`, `cpuFeatures` |
| CPUID leaf 0 exit cost | Leaf 0 answered right after the exit with the VM's own leaf 0, and the guest re-entered without the rest of the exit handling | [kernel/cpuid-patch.nix](../kernel/cpuid-patch.nix) |
| CPUID interception timing | CPUID interception off with `cpuidPassthrough`, so guest CPUID runs at native speed | [kernel/cpuid-disable.nix](../kernel/cpuid-disable.nix) |
| RDTSC and RDTSCP timing | The time from each CPUID, RDTSC, RDTSCP, WBINVD, XSETBV and INVD exit to the next entry is hidden from every TSC read | [kernel/timing-patch.nix](../kernel/timing-patch.nix) |
| MSR_IA32_TSC reads | A guest read answers the same hidden-time TSC, and its own exit is hidden | [kernel/timing-patch.nix](../kernel/timing-patch.nix) |
| VMCALL and VMMCALL from user mode | Both raise #UD, as on bare metal. KVM skipped VMMCALL silently (0003 fixes it). VMCALL raised #GP: on a CPU that faults it with #UD, KVM's emulator injected #GP (0002 fixes it); on Zen 5 the CPU itself raises #GP inside every SVM guest, and this repository's addition turns that #GP into #UD in the intercept 0001 adds. 0002 and 0003 apply on Intel too | `instructionFixes`, [vendor/vfio-native](../vendor/vfio-native) 0001 to 0003, [kernel/instruction-fixes.nix](../kernel/instruction-fixes.nix), [kernel/svm-instruction-fixes.nix](../kernel/svm-instruction-fixes.nix) |
| SVM instructions with SVM off | VMLOAD, VMSAVE, CLGI and STGI from user mode raise #UD, as on bare metal, where KVM raised #GP | `instructionFixes`, [vendor/vfio-native](../vendor/vfio-native) 0001 |
| ICEBP | Its #DB reports the address after the instruction even when its delivery causes a VM exit | `instructionFixes`, [vendor/vfio-native](../vendor/vfio-native) 0004 |
| CPUID exits on pinned vCPUs | Experimental: a runtime switch stops CPUID exits on vCPUs pinned 1:1, with a configurable processor name | `cpuidPassthrough.pinned`, [vendor/vfio-native](../vendor/vfio-native) EXPERIMENTAL-0006 |
| SVM instruction interception | `kvm_amd.vls=0` and `kvm_amd.vgif=0` on AMD hosts | [module.nix](../module.nix) kernel parameters |
| IA32_APERF and MPERF | Passed through with `aperfmperf=on` in a VM with `cpuPm` | [lib.nix](../lib.nix) `qemuArgs` |
| KVM paravirt MSR enforcement | QEMU's default, off, unless `kvmPvEnforceCpuid` is on | [lib.nix](../lib.nix) `qemuArgs` |
| KVM feature hiding | `kvm.hidden`, with no KVM hints | [lib.nix](../lib.nix) `features` |
| VMPort | Off | [lib.nix](../lib.nix) `features` |
| Hyper-V enlightenments | `vendor_id` and `relaxed` on by default; the kernel-dependent ones opt in through `hypervFeatures` | [lib.nix](../lib.nix) `features` |
| Hyper-V implementation limits | CPUID 0x40000005 reports 0x140 virtual and 0x200 logical processors and 0x25B0 interrupt vectors, as a Hyper-V build 14393 host does, matching the build QEMU names in 0x40000002, in place of QEMU's 0xFFFFFFFF and 64 | [qemu/post-patch.nix](../qemu/post-patch.nix) |
| Clock and timers | kvmclock absent, HPET present, native TSC, hypervclock only with a kernel-dependent Hyper-V feature | [lib.nix](../lib.nix) `clock` |
| SMBIOS type 0 (BIOS) | Vendor, version, date and release; a real board's BIOS characteristics, UEFI supported, not a virtual machine | [lib.nix](../lib.nix) `sysinfo`, `qemuArgs`, [qemu/post-patch.nix](../qemu/post-patch.nix) |
| SMBIOS type 1 (system) | Manufacturer, product, version, serial, SKU and family; with `smbios.perDomainSerials` each VM its own serial | [lib.nix](../lib.nix) `sysinfo`, `qemuArgs` |
| SMBIOS type 2 (baseboard) | Manufacturer, product, version, serial, asset tag, location; the serial derived from `identity.seed` when unset; with `smbios.perDomainSerials` each VM its own serial | [lib.nix](../lib.nix) `sysinfo`, `qemuArgs` |
| SMBIOS type 3 (chassis) | Manufacturer, and version, serial, asset tag and SKU from `smbios.chassis*`; `smbios.chassisType` in place of QEMU's type 1, Other, which QEMU's `-smbios` option cannot set | [lib.nix](../lib.nix) `qemuArgs`, [qemu/post-patch.nix](../qemu/post-patch.nix) |
| SMBIOS type 4 (processor) | Always present: socket, family, manufacturer, voltage, external clock, upgrade and characteristics from `cpuIdentity`, with defaults for `cpuVendor` from real AM5 and LGA1700 boards; the L1, L2 and L3 cache handles name the type 7 tables; the version is `cpuIdentity.modelId`, which also sets the CPUID model name, or else the model the guest sees in CPUID; speeds when set | [lib.nix](../lib.nix) `qemuArgs`, [smbios/processor-defaults.nix](../smbios/processor-defaults.nix), [qemu/smbios-board-fields.patch](../qemu/smbios-board-fields.patch) |
| SMBIOS type 7 (cache) | L1, L2 and L3 sizes, associativity and error correction from `smbios.cache` | [smbios/](../smbios), [lib.nix](../lib.nix) `qemuArgs` |
| SMBIOS type 8 (port connector) | One entry per `smbios.ports` item, internal and external connector included; the default list is a real AM5 board's | [lib.nix](../lib.nix) `qemuArgs`, [smbios/board-connectors.nix](../smbios/board-connectors.nix), [qemu/smbios-board-fields.patch](../qemu/smbios-board-fields.patch) |
| SMBIOS type 9 (system slot) | One entry per `smbios.systemSlots` item; the default list is a real AM5 board's; no bus address | [lib.nix](../lib.nix) `qemuArgs`, [smbios/board-connectors.nix](../smbios/board-connectors.nix), [qemu/smbios-board-fields.patch](../qemu/smbios-board-fields.patch) |
| SMBIOS type 11 (OEM strings) | `smbios.oemStrings` | [lib.nix](../lib.nix) `qemuArgs` |
| SMBIOS type 16 (memory array) | On the system board, with `smbios.memory.errorCorrection` in place of QEMU's multi-bit ECC | [qemu/post-patch.nix](../qemu/post-patch.nix) |
| SMBIOS types 16, 17 and 19 (memory) | The board's slots and maximum from `smbios.memory`, populated slots sharing the VM's memory with the configured maker, part, speed, type, type detail, rank and voltage, a width that counts ECC bits and a serial of their own, set or derived from `identity.seed`, and empty slots reporting no module | [qemu/smbios-memory-slots.patch](../qemu/smbios-memory-slots.patch), [lib.nix](../lib.nix) `qemuArgs` |
| SMBIOS types 26 to 29 (probes, cooling) | Voltage, cooling, temperature and current entries | [smbios/](../smbios), [lib.nix](../lib.nix) `qemuArgs` |
| SMBIOS type 41 (onboard devices) | One entry per `smbios.onboardDevices` item; none while the list is empty | [lib.nix](../lib.nix) `qemuArgs` |
| ACPI table OEM IDs | The configured `acpiOem.id` and `acpiOem.tableId` in the headers of QEMU's tables and of OVMF's own | [qemu/post-patch.nix](../qemu/post-patch.nix), [ovmf/post-patch.nix](../ovmf/post-patch.nix) |
| ACPI container ids | The PNP0A06 containers numbered 0 to 5 in place of QEMU's GPE0, CPU Hotplug, SMI, PCI Hotplug, Memory hotplug and DIMM devices names, which Windows makes their instance ids | AutoVirt QEMU patch, [qemu/post-patch.nix](../qemu/post-patch.nix) |
| ACPI PCI names | Board names for PCI devices, with hotplug scopes and notifications on the same names | AutoVirt QEMU patch, [qemu/acpi-pci-names.patch](../qemu/acpi-pci-names.patch) |
| ACPI processors | One processor device per vCPU under a processor container | [acpi/processors.nix](../acpi/processors.nix), `acpiProcessors` |
| ACPI devices | Power and sleep buttons, AC adapter, timers, voltage regulator, fan, thermal zones | [acpi/spoofed-devices.dsl](../acpi/spoofed-devices.dsl) |
| ACPI battery | Control method battery with BIF and BST, its serial `acpiSsdt.batterySerial`, derived from `identity.seed` when unset | [acpi/fake-battery.dsl](../acpi/fake-battery.dsl), [acpi/package.nix](../acpi/package.nix) |
| ACPI interrupt routing | The PIC and APIC routing tables named PR00 and AR00, as AMI firmware names them, in place of PRTP and PRTA; APIC mode routes each pin straight to GSI 16 to 23, with no GSIA to GSIH link devices beside LNKA to LNKH | [qemu/post-patch.nix](../qemu/post-patch.nix), [qemu/q35-direct-gsi.patch](../qemu/q35-direct-gsi.patch) |
| HPET | Its `_STA` reports the timer present, without QEMU's check of the period that VMAware reads as QEMU | [qemu/hpet-sta.patch](../qemu/hpet-sta.patch) |
| GPE container | Named GPEB in place of the GPER AutoVirt gives it | [qemu/post-patch.nix](../qemu/post-patch.nix) |
| ACPI thermal readings | CPU and VRM temperatures that move with the ACPI timer | [acpi/sensor-probes.dsl](../acpi/sensor-probes.dsl) |
| ACPI sleep states | S3 and S4 offered to the guest | [lib.nix](../lib.nix) `qemuArgs` |
| FADT and WAET | No hypervisor vendor in the FADT, a desktop profile, C2 and C3 latencies from `acpi.c2Latency` and `acpi.c3Latency`; a WAET table only with `acpi.waet` | AutoVirt QEMU patch, [qemu/post-patch.nix](../qemu/post-patch.nix) |
| EDID display identity | Manufacturer, monitor name, serial number, product code, DPI, manufacture date, preferred resolution; the serial number derived from `identity.seed` when unset; OVMF hands the EDID to Windows through the UEFI EDID protocols, so an emulated display shows that monitor in place of Default_Monitor | `edid` options, [qemu/post-patch.nix](../qemu/post-patch.nix), [ovmf/edid-protocols.patch](../ovmf/edid-protocols.patch) |
| Disk and optical model | IDE, SCSI and NVMe model strings; the CD answers ATA IDENTIFY and SCSI INQUIRY with one identity | `disk` options, [qemu/post-patch.nix](../qemu/post-patch.nix) |
| Drive firmware | `disk.firmware` and `disk.opticalFirmware` in place of QEMU's version on SATA and SCSI drives, and `disk.firmware` on an NVMe drive given no `firmware-version`; a SCSI disk reports the last four characters, the most its revision field holds | [qemu/post-patch.nix](../qemu/post-patch.nix) |
| Disk serial | IDE serial set to `disk.serial` in place of AutoVirt's blank one, derived from `identity.seed` when unset in the form the disk model's maker uses | [qemu/post-patch.nix](../qemu/post-patch.nix), [module.nix](../module.nix) `disk.serial` |
| SCSI vendor and target | INQUIRY vendor and target product | [qemu/post-patch.nix](../qemu/post-patch.nix) |
| PCI subsystem IDs | QEMU's 1af4:1100 replaced with `pciSubsystem` on every device that inherits it | [qemu/post-patch.nix](../qemu/post-patch.nix) |
| QEMU PCI vendor IDs | The Red Hat and QEMU vendor IDs on bridges, root ports, XHCI and VGA replaced with the CPU vendor's | AutoVirt QEMU patch |
| xHCI register window | 64 KB on `cpuVendor` `"intel"`, as Intel's PCH controllers decode, in place of QEMU's 16 KB, past which Windows' driver for the Intel id faults; QEMU's 16 KB on `"amd"` | [lib/autovirt-patches.nix](../lib/autovirt-patches.nix) `xhciRegisterWindow`, [qemu/post-patch.nix](../qemu/post-patch.nix) |
| USB input devices | Logitech IDs and names in place of QEMU's; the tablet takes the mouse's, and none reports a serial number | AutoVirt QEMU patch, [qemu/post-patch.nix](../qemu/post-patch.nix) |
| Other emulated USB devices | Storage, UAS, hub, serial, braille, smartcard, FIDO key, Wacom tablet, audio, MTP and network devices each report one real device's IDs and strings in place of QEMU's, from `devices`; a serial, where the copied device has one, is derived from the VM's uuid and the port, and a `serial=` property still overrides it; the MTP device info reports the phone's Android release and its USB serial | [qemu/post-patch.nix](../qemu/post-patch.nix), [qemu/usb-serial-from-uuid.patch](../qemu/usb-serial-from-uuid.patch) |
| VM generation counter | Hyper-V's `_HID` in place of `QEMUVGID`; the device itself exists only in a VM | [qemu/post-patch.nix](../qemu/post-patch.nix) |
| Hypercall instruction KVM emulates | #UD, as the CPU raises, for VMMCALL on Intel and VMCALL on an AMD CPU that intercepts it as #UD: QEMU turns off KVM's hypercall-patching quirk, which otherwise rewrites the instruction in the guest's code page and shows as an access violation. Zen 5 raises #GP for VMCALL itself, which only `instructionFixes` turns into #UD | [qemu/kvm-hypercall-quirk.patch](../qemu/kvm-hypercall-quirk.patch) |
| MegaRAID controller | A real LSI package version in place of QEMU's version, and a default HBA serial in LSI's form, derived from the VM's uuid and the card's PCI path, in place of `QEMU123456` | `devices.megasas`, [qemu/post-patch.nix](../qemu/post-patch.nix), [qemu/megasas-serial-from-uuid.patch](../qemu/megasas-serial-from-uuid.patch) |
| Headerless `-acpitable` | An `OEM1` signature, `acpiOem` and `devices.acpiCreator`, AMI's by default, in place of `QEMU` | [qemu/post-patch.nix](../qemu/post-patch.nix) |
| HD Audio codec | `hdaCodec` as the codec id and `pciSubsystem` as its subsystem, in place of QEMU's codec id | [qemu/post-patch.nix](../qemu/post-patch.nix) |
| fw_cfg | The port answers 0xFF bytes in place of `QEMU`, the DMA signature changed, the fw_cfg ACPI device removed | [qemu/post-patch.nix](../qemu/post-patch.nix), [ovmf/post-patch.nix](../ovmf/post-patch.nix), AutoVirt QEMU patch |
| OVMF VirtualMachine bit | Cleared in SMBIOS type 0 | AutoVirt EDK2 patch |
| OVMF PCI vendor IDs | Red Hat and QEMU IDs replaced to match QEMU's; the QXL entry keeps 1b36, which QEMU's QXL card reports | AutoVirt EDK2 patch, [ovmf/post-patch.nix](../ovmf/post-patch.nix) |
| OVMF firmware vendor | `EDK II` replaced with `smbios.biosVendor` | [ovmf/post-patch.nix](../ovmf/post-patch.nix) |
| OVMF boot logo and BGRT | LogoDxe and BootGraphicsResourceTableDxe removed | [ovmf/post-patch.nix](../ovmf/post-patch.nix) |
| TPM identity | The manufacturer, vendor strings and firmware version the TPM reports, and its EK and platform certificates, follow `tpm` | [module.nix](../module.nix) `tpm`, `libtpmsIdentityPatch` |
| TPM event log | OVMF follows TCG platform firmware profile revision 105 and logs its firmware volumes as EV_EFI_PLATFORM_FIRMWARE_BLOB2 with their names, in place of bare blobs at OVMF's fixed addresses | [ovmf/post-patch.nix](../ovmf/post-patch.nix) |
| Secure Boot keys | The Microsoft KEK and db under a Platform Key named for the board, with no distribution key, and Microsoft's published revocation list as dbx | [module.nix](../module.nix) `packages.secureBootVars` |
| MAC address | The network card of a declared VM starts with `macPrefix` and the rest comes from its uuid, unless `network.mac` gives the whole address | [domain.nix](../domain.nix) |
| VM UUID and Hyper-V vendor id | Each VM's UUID, a version 4 UUID, and `hypervVendorId` derived from `identity.seed` when unset | [identity.nix](../identity.nix), [module.nix](../module.nix) |
| CPU topology | On AMD the `topoext` flag is required, so Windows sees each core's two threads and their shared caches | [lib.nix](../lib.nix) `cpuFeatures` |
| GPU placement | The GPU's functions sit in one slot behind one PCIe root port, function for function, as on a PC | [domain.nix](../domain.nix) |
| VM IOMMU | With `iommu`, an AMD or Intel IOMMU with interrupt remapping, which VBS with a passed-through GPU needs | [render.nix](../render.nix), [domain.nix](../domain.nix) |
| Emulated sound | With `sound`, an ICH9 HD Audio controller with one codec reporting `hdaCodec`, played and recorded through the host user's PipeWire | [domain.nix](../domain.nix) |
| VirtIO devices | A declared VM has no balloon, RNG or tablet; `domain.devicesToRemove` names them for a VM defined by hand | [domain.nix](../domain.nix), [lib.nix](../lib.nix) `devicesToRemove` |
| pvpanic device | Absent unless the domain has a `<panic>` element, which `vfio-stealth-verify-host` reports | [guest/verify-host.sh](../guest/verify-host.sh) |
| Registry leftovers | VirtIO services and driver files, QEMU and VirtIO devices no longer present, removed with `pnputil`, guest agent, SPICE tools, cached driver descriptions and event logs that name a VM, removed inside Windows; boot drivers and present devices are kept | [guest/cleanup-registry.ps1](../guest/cleanup-registry.ps1) |

## Known limitations

| Limitation | Reason |
| - | - |
| Remote TPM attestation | Remote attestation checks the TPM endorsement key against the manufacturer. swtpm keys are not manufacturer signed. No software fix exists. |
| VBS and HVCI | Windows runs its own Hyper-V for them. On an AMD host it starts in either mode and VBS and HVCI run; with `"enlightened"` VMAware also reports INTERRUPT_SHADOW, SINGLE_STEP and VMID, so use `"hidden"`. On an Intel host it starts in either mode only while the guest does not see CET, which `cet` hides there by default; with CET shown, `"enlightened"` falls into Automatic Repair and `"hidden"` stops at the boot logo. With `"enlightened"` VMAware also reports SINGLE_STEP and VMID on Intel. |
| CET on Intel | `cet` is off by default with Intel, so the guest's CPUID lacks the shadow-stack and indirect-branch-tracking bits its CPU model has, and Windows runs without hardware-enforced stack protection. With CET shown, Windows' own Hyper-V does not start under KVM. |
| Boot-time kernel drivers | A detection driver that loads before the OS has more vectors than CPUID. swtpm satisfies TPM presence checks only. |
| Chipset identity | The q35 chipset reads as Intel ICH9 on every host. [DESIGN.md](DESIGN.md) says why. |
| HD Audio controller | On AMD it keeps the ID AutoVirt gives it, a controller of another platform than the ICH9 chipset around it; on Intel it is ICH9's own. The codec reports `hdaCodec` but keeps QEMU's widget layout, which differs from that codec's. |
| Other emulated USB devices | Each copies one device's IDs and strings but keeps QEMU's descriptor layout, speed and behaviour, which differ from that device's. |
| WAET | Only virtual machines carry it, and `acpi.waet` keeps it by default for the reason its description gives. |
| FADT C2 and C3 latency | The defaults, 101 and 1001 microseconds, are what a desktop board with AMI firmware reports, and Windows boots with them. VMAware flags QEMU's own 0x0FFF. |
| VM IOMMU on Intel | QEMU's DMAR table, which `iommu` adds on an Intel host, still carries signs VMAware's FIRMWARE check reads as QEMU. |
| VirtIO devices | They keep vendor 1af4, which their drivers bind to. Use SATA disks and an emulated network card where that matters. |
| fw_cfg | Only the signature changes. A guest that reads further finds QEMU's file directory. |
| MAC address of a VM defined by hand | `spoofMac` reaches only VMs under `domains`. The caller sets the NIC's MAC address. |
| CPUID timing | Without the AMD kernel patches a CPUID exit costs what it costs in any VM, and a guest that times CPUID sees it. |
| Context-switch timing | Clocks built on context switches do not read the TSC, so TSC compensation does not hide exits from them. |
| Frame-time jitter | VM exits add jitter. The timing patches and `cpuidPassthrough` reduce it but do not remove it. |
| `timing.enable` cost | It makes RDTSC and RDTSCP exit in every VM on the host, which costs frame rate in games run in any of them. |
| Looking Glass on kvmfr | The module creates one `/dev/kvmfr0`, so one VM with `lookingGlass` runs at a time on it. |
| `pinning.isolate` | One pinned VM runs at a time. A VM stopped without libvirt's release hook, such as by a crash of libvirtd, leaves `/run/vfio-stealth/isolating` behind, and the next start is refused until it is removed. |
| Boot stall on a hybrid Intel CPU | An unpinned VM can stall in OVMF's AHCI polling when its vCPU moves between P-core threads, and goes on only at its next VM exit. Stock QEMU with nixpkgs' stock OVMF stalls the same way. Pin the vCPUs with `domains.<name>.pinning`. Why the move loses a wakeup is open. |
| Windows boot stall on shared CPUs | Windows can stop at the boot logo when its vCPUs do not each get a host CPU: four vCPUs pinned to four host CPUs that also run QEMU's own threads stalled every time, as did unpinned VMs on a host busy compiling, while the same image booted unpinned on an idle host. Pin each vCPU to a core of its own with `domains.<name>.pinning` and keep `emulator` on others. |
| VMAware TIMER | It times CPUID, and a CPUID exit costs what it costs in a VM: on Intel always, since no timing patch exists for Intel, and on AMD without `timing.enable`. |
| VMAware TRAP on Intel | An Intel CPU run bare reports the single step after CPUID and an instruction breakpoint on the next instruction as two #DBs, BS and then B0, as KVM does; VMAware expects one #DB with both, so it reads the CPU's own behaviour as a hypervisor. A KVM that merged them would differ from bare metal. Measured from the DR6 Linux reports, not on Windows. |
| VMAware KVM_INTERCEPTION | It fires on a host kernel without `instructionFixes`: there a user-mode VMCALL or VMMCALL raises nothing, where a real CPU raises #UD. With Hyper-V enlightenments on, KVM's Hyper-V hypercall path raises #UD on Intel itself. The Windows runs on stock host kernels record it; `evidence.libvirt-windows`, whose host kernel carries the patches, does not, on AMD and Intel. |
| VMAware SVM_EXCEPTIONS | On AMD it fires on a host kernel without `instructionFixes`: there an SVM instruction with EFER.SVME clear raises #GP, where a real CPU raises #UD. With VBS on in hidden mode it did not fire, in enlightened mode it did. `evidence.libvirt-windows`, whose host kernel carries the patches, does not record it. |
| VMAware GPU_CAPABILITIES | The Microsoft Basic Display Adapter on an emulated display reports no gamma ramp; a passed-through GPU with its vendor driver does. |
| VMAware THREAD_MISMATCH | It fires when the VM has fewer vCPUs than the CPU model it shows has threads, as a VM smaller than its host does. Set `cpuIdentity.modelId` to a model with as many threads as the VM has vCPUs. |
