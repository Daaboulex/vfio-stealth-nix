# Compatibility

This page says which platforms run which part of the stack. It lists every
detection vector this project covers, with the file that handles it. A
detection vector is a way for a program in the guest to tell that it runs in a
VM. The page ends with the limits that remain.

## Platforms

- The stealth stack runs only on `x86_64-linux`, and `meta.platforms` enforces this. The reason: the AutoVirt QEMU patches change `hw/i386/`, `hw/isa/lpc_ich9.c` and `hw/ide/`, the EDK2 patches change `OvmfPkgX64`, and the kernel patches change KVM's x86 code under `arch/x86/kvm/`.
- On `aarch64-linux` you get only `stealth-detect` and the checks that do not need an x86 host. On aarch64, `pkgs.OVMF` is ArmVirtQemu, and nothing is spoofed.
- On an aarch64 guest, the CPU identity registers (`MIDR_EL1`, `REVIDR_EL1`, `AIDR_EL1`) are set from userspace through `KVM_SET_ONE_REG`, not by a patch to KVM. So the x86 approach does not work there. [scripts/update.sh](../scripts/update.sh) tells you when QEMU's ARM KVM backend can set these registers.
- QEMU and OVMF stealth work on AMD and Intel hosts. Each vendor has its own AutoVirt patches.
- `timing`, `cpuidSpoof` and `cpuidPassthrough` patch KVM's SVM code, the part of KVM for AMD CPUs, and work on AMD only. [DESIGN.md](DESIGN.md) explains why. `instructionFixes` works on both vendors: the vfio-native patches 0002 and 0003 apply on both, while 0001, 0004 and the #GP mapping of [kernel/svm-instruction-fixes.nix](../kernel/svm-instruction-fixes.nix) apply on AMD only. Every kernel switch works only in a kernel built through `packages.kernelFor`.

[DEVELOPMENT.md](DEVELOPMENT.md) shows what the checks prove from inside a
booted guest. [AUTOVIRT.md](AUTOVIRT.md) shows what each AutoVirt change turns
into.

## Detection vectors covered

Each row names a detection vector, what this project does about it, and the
file that does it. SMBIOS and ACPI are the tables the firmware gives the guest
to describe the hardware. OVMF is the UEFI firmware the VM boots.

| Vector | Technique | Where |
| - | - | - |
| CPUID hypervisor bit | `kvm.hidden` is always set. The hypervisor bit is cleared only when `hypervMode` is `"hidden"`. In enlightened mode, Hyper-V's vendor id shows `hypervVendorId` | [lib.nix](../lib.nix) `features`, `cpuFeatures` |
| CPUID leaf 0 exit cost | Right after the exit, leaf 0 gets the VM's own leaf 0 as its answer, and the guest runs again without the rest of the exit handling | [kernel/cpuid-patch.nix](../kernel/cpuid-patch.nix) |
| CPUID interception timing | With `cpuidPassthrough`, CPUID interception is off, so CPUID in the guest runs at native speed | [kernel/cpuid-disable.nix](../kernel/cpuid-disable.nix) |
| RDTSC and RDTSCP timing | Every TSC read leaves out the time from each CPUID, RDTSC, RDTSCP, WBINVD, XSETBV and INVD exit to the next entry | [kernel/timing-patch.nix](../kernel/timing-patch.nix) |
| MSR_IA32_TSC reads | A guest read gets the same TSC, with the hidden time left out, and the exit for that read is hidden too | [kernel/timing-patch.nix](../kernel/timing-patch.nix) |
| VMCALL and VMMCALL from user mode | Both raise #UD, the invalid instruction error, as on bare metal. KVM used to skip VMMCALL without any error; 0003 fixes this. VMCALL raised #GP, the general protection error. On a CPU that faults VMCALL with #UD, KVM's emulator injected #GP; 0002 fixes this. On Zen 5 the CPU itself raises #GP inside every SVM guest. Code this repository adds turns that #GP into #UD, in the intercept that 0001 adds. 0002 and 0003 also apply on Intel | `instructionFixes`, [vendor/vfio-native](../vendor/vfio-native) 0001 to 0003, [kernel/instruction-fixes.nix](../kernel/instruction-fixes.nix), [kernel/svm-instruction-fixes.nix](../kernel/svm-instruction-fixes.nix) |
| SVM instructions with SVM off | From user mode, VMLOAD, VMSAVE, CLGI and STGI raise #UD, as on bare metal. KVM raised #GP for them | `instructionFixes`, [vendor/vfio-native](../vendor/vfio-native) 0001 |
| ICEBP | Its #DB, the debug exception, reports the address after the instruction, even when its delivery causes a VM exit | `instructionFixes`, [vendor/vfio-native](../vendor/vfio-native) 0004 |
| CPUID exits on pinned vCPUs | Experimental. A runtime switch stops CPUID exits on vCPUs pinned 1:1. You can set the processor name | `cpuidPassthrough.pinned`, [vendor/vfio-native](../vendor/vfio-native) EXPERIMENTAL-0006 |
| SVM instruction interception | `kvm_amd.vls=0` and `kvm_amd.vgif=0` on AMD hosts | [module.nix](../module.nix) kernel parameters |
| IA32_APERF and MPERF | In a VM with `cpuPm`, they are passed through with `aperfmperf=on` | [lib.nix](../lib.nix) `qemuArgs` |
| KVM paravirt MSR enforcement | Off, which is QEMU's default, unless `kvmPvEnforceCpuid` is on | [lib.nix](../lib.nix) `qemuArgs` |
| KVM feature hiding | `kvm.hidden`, and no KVM hints | [lib.nix](../lib.nix) `features` |
| VMPort | Off | [lib.nix](../lib.nix) `features` |
| Hyper-V enlightenments | `vendor_id` and `relaxed` are on by default. The ones that depend on the kernel are opt-in through `hypervFeatures` | [lib.nix](../lib.nix) `features` |
| Hyper-V implementation limits | CPUID 0x40000005 reports 0x140 virtual processors, 0x200 logical processors and 0x25B0 interrupt vectors. A Hyper-V build 14393 host reports the same, and that is the build QEMU names in 0x40000002. This replaces QEMU's 0xFFFFFFFF and 64 | [qemu/post-patch.nix](../qemu/post-patch.nix) |
| Clock and timers | No kvmclock, HPET present, native TSC. hypervclock is there only when you turn on a `hypervFeatures` entry that needs a kernel feature | [lib.nix](../lib.nix) `clock` |
| SMBIOS type 0 (BIOS) | Vendor, version, date and release. The BIOS characteristics of a real board, UEFI marked as supported, and not marked as a virtual machine | [lib.nix](../lib.nix) `sysinfo`, `qemuArgs`, [qemu/post-patch.nix](../qemu/post-patch.nix) |
| SMBIOS type 1 (system) | Manufacturer, product, version, serial, SKU and family. With `smbios.perDomainSerials`, each VM gets its own serial | [lib.nix](../lib.nix) `sysinfo`, `qemuArgs` |
| SMBIOS type 2 (baseboard) | Manufacturer, product, version, serial, asset tag and location. When the serial is unset, it is derived from `identity.seed`. With `smbios.perDomainSerials`, each VM gets its own serial | [lib.nix](../lib.nix) `sysinfo`, `qemuArgs` |
| SMBIOS type 3 (chassis) | Manufacturer, plus version, serial, asset tag and SKU from `smbios.chassis*`. QEMU writes chassis type 1, Other, and its `-smbios` option cannot change it, so a patch writes `smbios.chassisType` instead | [lib.nix](../lib.nix) `qemuArgs`, [qemu/post-patch.nix](../qemu/post-patch.nix) |
| SMBIOS type 4 (processor) | Always present. Socket, family, manufacturer, voltage, external clock, upgrade and characteristics come from `cpuIdentity`, with defaults for `cpuVendor` taken from real AM5 and LGA1700 boards. The L1, L2 and L3 cache handles point to the type 7 tables. The version is `cpuIdentity.modelId`, which also sets the CPUID model name; without it, the version is the model the guest sees in CPUID. Speeds appear when they are set | [lib.nix](../lib.nix) `qemuArgs`, [smbios/processor-defaults.nix](../smbios/processor-defaults.nix), [qemu/smbios-board-fields.patch](../qemu/smbios-board-fields.patch) |
| SMBIOS type 7 (cache) | L1, L2 and L3 sizes, associativity and error correction, from `smbios.cache` | [smbios/](../smbios), [lib.nix](../lib.nix) `qemuArgs` |
| SMBIOS type 8 (port connector) | One entry for each `smbios.ports` item, with its internal and external connector. The default list comes from a real AM5 board | [lib.nix](../lib.nix) `qemuArgs`, [smbios/board-connectors.nix](../smbios/board-connectors.nix), [qemu/smbios-board-fields.patch](../qemu/smbios-board-fields.patch) |
| SMBIOS type 9 (system slot) | One entry for each `smbios.systemSlots` item. The default list comes from a real AM5 board. No bus address | [lib.nix](../lib.nix) `qemuArgs`, [smbios/board-connectors.nix](../smbios/board-connectors.nix), [qemu/smbios-board-fields.patch](../qemu/smbios-board-fields.patch) |
| SMBIOS type 11 (OEM strings) | From `smbios.oemStrings` | [lib.nix](../lib.nix) `qemuArgs` |
| SMBIOS type 16 (memory array) | On the system board. `smbios.memory.errorCorrection` replaces QEMU's multi-bit ECC | [qemu/post-patch.nix](../qemu/post-patch.nix) |
| SMBIOS types 16, 17 and 19 (memory) | The board's slots and maximum come from `smbios.memory`. Populated slots share the VM's memory and use the configured maker, part, speed, type, type detail, rank and voltage. Their width counts ECC bits, and each has its own serial, set or derived from `identity.seed`. Empty slots report no module | [qemu/smbios-memory-slots.patch](../qemu/smbios-memory-slots.patch), [lib.nix](../lib.nix) `qemuArgs` |
| SMBIOS types 26 to 29 (probes, cooling) | Voltage, cooling, temperature and current entries | [smbios/](../smbios), [lib.nix](../lib.nix) `qemuArgs` |
| SMBIOS type 41 (onboard devices) | One entry for each `smbios.onboardDevices` item. No entries while the list is empty | [lib.nix](../lib.nix) `qemuArgs` |
| ACPI table OEM IDs | The configured `acpiOem.id` and `acpiOem.tableId` go into the headers of QEMU's tables and of OVMF's own tables | [qemu/post-patch.nix](../qemu/post-patch.nix), [ovmf/post-patch.nix](../ovmf/post-patch.nix) |
| ACPI container ids | The PNP0A06 containers are numbered 0 to 5. This replaces QEMU's names GPE0, CPU Hotplug, SMI, PCI Hotplug, Memory hotplug and DIMM devices, which Windows turns into their instance ids | AutoVirt QEMU patch, [qemu/post-patch.nix](../qemu/post-patch.nix) |
| ACPI PCI names | PCI devices get board names. Hotplug scopes and notifications use the same names | AutoVirt QEMU patch, [qemu/acpi-pci-names.patch](../qemu/acpi-pci-names.patch) |
| ACPI processors | One processor device for each vCPU, under a processor container | [acpi/processors.nix](../acpi/processors.nix), `acpiProcessors` |
| ACPI devices | Power and sleep buttons, AC adapter, timers, voltage regulator, fan and thermal zones | [acpi/spoofed-devices.dsl](../acpi/spoofed-devices.dsl) |
| ACPI battery | A control method battery with BIF and BST. Its serial is `acpiSsdt.batterySerial`, derived from `identity.seed` when unset | [acpi/fake-battery.dsl](../acpi/fake-battery.dsl), [acpi/package.nix](../acpi/package.nix) |
| ACPI interrupt routing | The PIC and APIC routing tables are named PR00 and AR00, as AMI firmware names them, in place of PRTP and PRTA. In APIC mode each pin goes straight to GSI 16 to 23. There are no GSIA to GSIH link devices beside LNKA to LNKH | [qemu/post-patch.nix](../qemu/post-patch.nix), [qemu/q35-direct-gsi.patch](../qemu/q35-direct-gsi.patch) |
| HPET | Its `_STA` reports the timer as present. It does not run QEMU's check of the period, which VMAware reads as QEMU | [qemu/hpet-sta.patch](../qemu/hpet-sta.patch) |
| GPE container | Named GPEB instead of GPER, the name AutoVirt gives it | [qemu/post-patch.nix](../qemu/post-patch.nix) |
| ACPI thermal readings | CPU and VRM temperatures that change with the ACPI timer | [acpi/sensor-probes.dsl](../acpi/sensor-probes.dsl) |
| ACPI sleep states | The guest is offered S3 and S4 | [lib.nix](../lib.nix) `qemuArgs` |
| FADT and WAET | The FADT names no hypervisor vendor, has a desktop profile, and takes its C2 and C3 latencies from `acpi.c2Latency` and `acpi.c3Latency`. A WAET table exists only with `acpi.waet` | AutoVirt QEMU patch, [qemu/post-patch.nix](../qemu/post-patch.nix) |
| EDID display identity | Manufacturer, monitor name, serial number, product code, DPI, manufacture date and preferred resolution. When the serial number is unset, it is derived from `identity.seed`. OVMF passes the EDID to Windows through the UEFI EDID protocols, so an emulated display shows that monitor instead of Default_Monitor | `edid` options, [qemu/post-patch.nix](../qemu/post-patch.nix), [ovmf/edid-protocols.patch](../ovmf/edid-protocols.patch) |
| Disk and optical model | IDE, SCSI and NVMe model strings. The CD answers ATA IDENTIFY and SCSI INQUIRY with the same identity | `disk` options, [qemu/post-patch.nix](../qemu/post-patch.nix) |
| Drive firmware | `disk.firmware` and `disk.opticalFirmware` replace QEMU's version on SATA and SCSI drives. `disk.firmware` also goes to an NVMe drive that has no `firmware-version`. A SCSI disk reports only the last four characters, because its revision field holds no more | [qemu/post-patch.nix](../qemu/post-patch.nix) |
| Disk serial | The IDE serial is `disk.serial`, instead of AutoVirt's blank one. When unset, it is derived from `identity.seed`, in the form the disk model's maker uses | [qemu/post-patch.nix](../qemu/post-patch.nix), [module.nix](../module.nix) `disk.serial` |
| SCSI vendor and target | INQUIRY vendor and target product | [qemu/post-patch.nix](../qemu/post-patch.nix) |
| PCI subsystem IDs | `pciSubsystem` replaces QEMU's 1af4:1100 on every device that inherits it | [qemu/post-patch.nix](../qemu/post-patch.nix) |
| QEMU PCI vendor IDs | The Red Hat and QEMU vendor IDs on bridges, root ports, XHCI and VGA are replaced with the CPU vendor's | AutoVirt QEMU patch |
| xHCI register window | 64 KB when `cpuVendor` is `"intel"`, as Intel's PCH controllers decode, instead of QEMU's 16 KB. Windows' driver for the Intel id faults past those 16 KB. On `"amd"` it stays at QEMU's 16 KB | [lib/autovirt-patches.nix](../lib/autovirt-patches.nix) `xhciRegisterWindow`, [qemu/post-patch.nix](../qemu/post-patch.nix) |
| USB input devices | Logitech IDs and names replace QEMU's. The tablet takes the mouse's, and none of them reports a serial number | AutoVirt QEMU patch, [qemu/post-patch.nix](../qemu/post-patch.nix) |
| Other emulated USB devices | Storage, UAS, hub, serial, braille, smartcard, FIDO key, Wacom tablet, audio, MTP and network devices each report one real device's IDs and strings from `devices`, instead of QEMU's. Where the copied device has a serial, it is derived from the VM's uuid and the port, and a `serial=` property still overrides it. The MTP device info reports the phone's Android release and its USB serial | [qemu/post-patch.nix](../qemu/post-patch.nix), [qemu/usb-serial-from-uuid.patch](../qemu/usb-serial-from-uuid.patch) |
| VM generation counter | Hyper-V's `_HID` replaces `QEMUVGID`. The device itself exists only in a VM | [qemu/post-patch.nix](../qemu/post-patch.nix) |
| Hypercall instruction KVM emulates | #UD, as the CPU raises it, for VMMCALL on Intel and for VMCALL on an AMD CPU that intercepts it as #UD. QEMU turns off KVM's hypercall-patching quirk. Otherwise that quirk rewrites the instruction in the guest's code page, which shows as an access violation. Zen 5 itself raises #GP for VMCALL, and only `instructionFixes` turns that into #UD | [qemu/kvm-hypercall-quirk.patch](../qemu/kvm-hypercall-quirk.patch) |
| MegaRAID controller | A real LSI package version replaces QEMU's version. The default HBA serial replaces `QEMU123456`: it is in LSI's form, derived from the VM's uuid and the card's PCI path | `devices.megasas`, [qemu/post-patch.nix](../qemu/post-patch.nix), [qemu/megasas-serial-from-uuid.patch](../qemu/megasas-serial-from-uuid.patch) |
| Headerless `-acpitable` | An `OEM1` signature, `acpiOem` and `devices.acpiCreator` (AMI's by default) replace `QEMU` | [qemu/post-patch.nix](../qemu/post-patch.nix) |
| HD Audio codec | `hdaCodec` is the codec id and `pciSubsystem` its subsystem, instead of QEMU's codec id | [qemu/post-patch.nix](../qemu/post-patch.nix) |
| fw_cfg | The port answers with 0xFF bytes instead of `QEMU`. The DMA signature is changed. The fw_cfg ACPI device is removed | [qemu/post-patch.nix](../qemu/post-patch.nix), [ovmf/post-patch.nix](../ovmf/post-patch.nix), AutoVirt QEMU patch |
| OVMF VirtualMachine bit | Cleared in SMBIOS type 0 | AutoVirt EDK2 patch |
| OVMF PCI vendor IDs | Red Hat and QEMU IDs are replaced to match QEMU's. The QXL entry keeps 1b36, which QEMU's QXL card reports | AutoVirt EDK2 patch, [ovmf/post-patch.nix](../ovmf/post-patch.nix) |
| OVMF firmware vendor | `smbios.biosVendor` replaces `EDK II` | [ovmf/post-patch.nix](../ovmf/post-patch.nix) |
| OVMF boot logo and BGRT | LogoDxe and BootGraphicsResourceTableDxe are removed | [ovmf/post-patch.nix](../ovmf/post-patch.nix) |
| TPM identity | The manufacturer, vendor strings and firmware version the TPM reports, and its EK and platform certificates, follow `tpm` | [module.nix](../module.nix) `tpm`, `libtpmsIdentityPatch` |
| TPM event log | OVMF follows TCG platform firmware profile revision 105. It logs its firmware volumes as EV_EFI_PLATFORM_FIRMWARE_BLOB2 with their names, instead of as bare blobs at OVMF's fixed addresses | [ovmf/post-patch.nix](../ovmf/post-patch.nix) |
| Secure Boot keys | The Microsoft KEK and db under a Platform Key named after the board, with no distribution key. Microsoft's published revocation list is the dbx | [module.nix](../module.nix) `packages.secureBootVars` |
| MAC address | The network card of a declared VM starts with `macPrefix`, and the rest comes from the VM's uuid, unless `network.mac` gives the whole address | [domain.nix](../domain.nix) |
| VM UUID and Hyper-V vendor id | Each VM's UUID, a version 4 UUID, and `hypervVendorId` are derived from `identity.seed` when unset | [identity.nix](../identity.nix), [module.nix](../module.nix) |
| CPU topology | On AMD the `topoext` flag is required, so Windows sees each core's two threads and their shared caches | [lib.nix](../lib.nix) `cpuFeatures` |
| GPU placement | The GPU's functions sit in one slot behind one PCIe root port, and each keeps the function number it has on the host, as on a PC | [domain.nix](../domain.nix) |
| VM IOMMU | With `iommu`, the VM gets an AMD or Intel IOMMU with interrupt remapping. VBS with a passed-through GPU needs this on AMD; on Intel, Windows with VBS does not start with it. On AMD the module also turns on the IOMMU's DMA remapping, which QEMU leaves off: without it the guest's disks read the wrong memory and time out | [render.nix](../render.nix), [domain.nix](../domain.nix) |
| Emulated sound | With `sound`, an ICH9 HD Audio controller with one codec that reports `hdaCodec`. It plays and records through the host user's PipeWire | [domain.nix](../domain.nix) |
| VirtIO devices | A declared VM has no balloon, RNG or tablet. For a VM defined by hand, `domain.devicesToRemove` names them | [domain.nix](../domain.nix), [lib.nix](../lib.nix) `devicesToRemove` |
| pvpanic device | Absent unless the domain has a `<panic>` element. `vfio-stealth-verify-host` reports that element | [guest/verify-host.sh](../guest/verify-host.sh) |
| Registry leftovers | Inside Windows, the cleanup removes VirtIO services and driver files, QEMU and VirtIO devices that are no longer present (with `pnputil`), the guest agent, SPICE tools, cached driver descriptions, and event logs that name a VM. It keeps boot drivers and present devices | [guest/cleanup-registry.ps1](../guest/cleanup-registry.ps1) |

## Known limitations

What still gives the VM away, or costs something, and why. "Shown by" names
the check or run that proves it, or the code that makes it so. A line that
starts with "Open:" is not measured yet.

| Limit | Why | Shown by |
| - | - | - |
| Remote TPM attestation | A remote check asks the TPM's maker to vouch for its key. swtpm makes its own key, which no maker signed, and no software can change that. | how swtpm works |
| VMAware HYPERVISOR_BIT and HYPERVISOR_STR | `hypervMode = "enlightened"`, the default, shows the hypervisor bit and the Hyper-V vendor string, because the Hyper-V speedups need them. `"hidden"` removes both. | `boot-matrix` and the Windows runs, in both modes |
| VBS and Memory integrity | Windows runs its own Hyper-V for them, and they work in both modes. In enlightened mode VMAware also finds SINGLE_STEP and VMID, and INTERRUPT_SHADOW on AMD, so use `"hidden"`. | Windows runs with `vbs = true`, AMD and Intel |
| CET on Intel | Windows' own Hyper-V does not start while the guest sees CET, so on Intel `cet` hides it by default. Windows then runs without hardware stack protection. With CET shown, enlightened mode falls into Automatic Repair and hidden mode stops at the boot logo. | Windows runs on Intel with `cet` on and off |
| Chipset identity | The q35 chipset shows as Intel ICH9 on every host. [DESIGN.md](DESIGN.md) says why. | the code, [qemu/post-patch.nix](../qemu/post-patch.nix) |
| HD Audio controller | On AMD it keeps the ID AutoVirt gives it, which belongs to another platform than the ICH9 chipset around it; on Intel it is ICH9's own. The codec reports `hdaCodec` but keeps QEMU's inner layout, which differs from that codec's. | the code, [qemu/post-patch.nix](../qemu/post-patch.nix) |
| Other emulated USB devices | Each copies one real device's IDs and names, but keeps QEMU's descriptors, speed and behaviour. | the code, [qemu/post-patch.nix](../qemu/post-patch.nix) |
| WAET, and VMAware FIRMWARE | Only virtual machines have the WAET table, and VMAware's FIRMWARE check finds it. With `acpi.waet = false`, FIRMWARE goes away on Intel and AMD: nothing else in the firmware gives the VM away. The module keeps WAET on by default, because Windows uses it to read its timers the fast way. Open: how much slower Windows runs without WAET is not measured; it boots and runs without it on Intel and AMD. | `boot-matrix-intel-hidden-nowaet`, `boot-matrix-hidden-nowaet`, and a Windows run without WAET on Intel and on AMD |
| The VM's IOMMU and VMAware FIRMWARE | The DMAR table that `iommu` adds on Intel carries signs VMAware's FIRMWARE check reads as QEMU. The IVRS table it adds on AMD does not. | the `viommu` case of `boot-matrix-intel-hidden-nowaet` and of `boot-matrix-hidden-nowaet` |
| VirtIO devices | They keep vendor 1af4, which their drivers need. Use SATA disks and an emulated network card where that matters. | the code, [domain.nix](../domain.nix) |
| fw_cfg | Only its signature changes. A guest that reads further finds QEMU's file list. | the code, [qemu/post-patch.nix](../qemu/post-patch.nix) |
| MAC address of a VM defined by hand | `spoofMac` reaches only VMs under `domains`. For any other VM, you set the MAC address. | the code, [domain.nix](../domain.nix) |
| CPUID timing | Without the AMD kernel patches, a CPUID exit takes as long as in any VM, and a guest that times CPUID sees it. | `evidence.kernel-runtime` |
| Timing from context switches | Open: clocks built on context switches do not read the TSC, so the timing patch cannot hide exits from them. Not measured. | not measured |
| Frame-time jitter | Open: VM exits add jitter, which the timing patches and `cpuidPassthrough` should reduce. Not measured. | not measured |
| Cost of `timing.enable` | It makes RDTSC and RDTSCP exit in every VM on the host. Open: a user reported a lower frame rate with the patched kernel; how much it costs is not measured here. | the code, [kernel/](../kernel); one user's report |
| Detection drivers that load at boot | Open: an anti-cheat driver that loads before Windows may check things this module does not change. None was tested. | not measured |
| Looking Glass on kvmfr | The module makes one `/dev/kvmfr0`, so one VM with `lookingGlass` runs at a time on it. | the code, [module.nix](../module.nix) |
| `pinning.isolate` | One pinned VM runs at a time. If libvirt's release hook never runs, for example because libvirtd crashed, `/run/vfio-stealth/isolating` stays behind and the next start is refused until you remove it. | `qemu-hook` |
| VBS with the VM's IOMMU on Intel | Windows 11 with VBS and Memory integrity does not start once the VM has its Intel IOMMU: the first boot with VBS crashes twice, and Windows falls into Automatic Repair. It fails the same in hidden and enlightened mode, and with interrupt remapping, caching mode or DMA translation off, with 39 address bits, and with extended interrupt mode. Without the IOMMU, VBS runs on Intel. On AMD, VBS runs with the IOMMU and Windows reports DMA protection. Open: why Windows' hypervisor fails on the Intel IOMMU. | Windows runs with `vbs` and `iommu` on Intel and on AMD |
| Boot stall of an unpinned VM | An unpinned VM can stall in OVMF when its vCPU moves between host CPUs. On a hybrid Intel CPU it stalls in OVMF's AHCI polling when the vCPU moves between P-core threads, and goes on only at its next VM exit; stock QEMU with nixpkgs' stock OVMF stalls the same way. On an AMD CPU it showed when the host was busy, with nixpkgs' OVMF too. Pin the vCPUs with `domains.<name>.pinning`. Open: why the move loses a wakeup. | runs on a hybrid Intel host, with the stock QEMU and OVMF too; 16 unpinned VMs at once on a busy AMD host, with nixpkgs' OVMF too, against none stalled when pinned |
| Windows boot stall on shared CPUs | Windows can stop at the boot logo when its vCPUs do not each get a host CPU of their own: four vCPUs pinned to four host CPUs that also ran QEMU's own threads stalled every time, and so did unpinned VMs on a host busy compiling. The same image booted unpinned on an idle host. Give each vCPU its own core with `domains.<name>.pinning`, and keep `emulator` on other cores. | Windows runs |
| VMAware TIMER | It times CPUID, and a CPUID exit takes as long as in any VM: always on Intel, where no timing patch exists, and on AMD without `timing.enable`. | the Windows runs |
| VMAware TRAP on Intel | VMAware reports it in every Intel Windows run. A bare Intel CPU reports the single step after CPUID and an instruction breakpoint on the next instruction as two debug exceptions, as KVM does; VMAware expects one, so it reads the CPU's own behaviour as a hypervisor. A KVM that merged them would differ from bare metal. | the Windows runs on Intel; DR6 read in the Linux probe |
| VMAware KVM_INTERCEPTION | It fires on a host kernel without `instructionFixes`: there, a VMCALL or VMMCALL from a program raises nothing, where a real CPU raises an error. With Hyper-V enlightenments on, KVM's own Hyper-V path raises the error on Intel. | the Windows runs on stock kernels; `evidence.libvirt-windows`, with the patches, does not show it |
| VMAware SVM_EXCEPTIONS | On AMD it fires on a host kernel without `instructionFixes`: there an SVM instruction raises a different error than on a real CPU. With VBS on, it did not fire in hidden mode and did in enlightened mode. | the Windows runs on AMD; `evidence.libvirt-windows`, with the patches, does not show it |
| VMAware GPU_CAPABILITIES | The Microsoft Basic Display Adapter of an emulated display reports no gamma ramp. Open: whether a passed-through GPU with its own driver clears it is not measured. | the Windows runs, with an emulated display |
| VMAware THREAD_MISMATCH | It fires when the VM has fewer vCPUs than the CPU model it shows has threads, as any VM smaller than its host does. Set `cpuIdentity.modelId` to a model with as many threads as the VM has vCPUs. | `boot-matrix` and the Windows runs |
