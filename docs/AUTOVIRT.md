# AutoVirt

This file lists what the vendored [AutoVirt](https://github.com/Scrut1ny/AutoVirt)
patches change, what this repository does with each change, and what proves the
result. The patches are in [vendor/autovirt/patches/](../vendor/autovirt/patches).
Their origin, and this repository's own edits to them, are in
[vendor/autovirt/README](../vendor/autovirt/README). The corrections are in
[qemu/post-patch.nix](../qemu/post-patch.nix),
[qemu/acpi-pci-names.patch](../qemu/acpi-pci-names.patch) and
[ovmf/post-patch.nix](../ovmf/post-patch.nix).

Kept means the change ships as AutoVirt wrote it. Reverted means stock QEMU or
EDK2 comes back. Corrected means a configured or matching value replaces it.
The rows describe the AMD patches; [How Intel differs](#how-intel-differs) has
the rest. Proof names the check that reads the result. None means no check
reads it.

## QEMU

| Part | AutoVirt | Here | Proof |
| - | - | - | - |
| Host bridge, LPC, SMBus and AHCI IDs | AMD vendor, FCH device IDs and revisions | reverted to ICH9 | `boot-smoke`, `boot-matrix` read them at 00:00.0 and 00:1f |
| LPC, SATA and SMBus slot | moved from 0x1f to 0x14 | reverted to 0x1f | `boot-smoke` finds slot 0x14 empty |
| QEMU and Red Hat PCI IDs: VGA, PCI and PCIe bridges, root port, XHCI | CPU vendor's IDs | kept | `boot-matrix`: the firmware drives the VGA card, a virtio disk boots behind a root port, and no device has QEMU's vendor 1b36 or 1234, except in the QXL case |
| PCI subsystem 1af4:1100 | left as is | corrected to `pciSubsystem` | `boot-smoke`, `boot-matrix`: no device has the Red Hat subsystem vendor |
| VirtIO vendor 1af4 | left as is | kept, because VirtIO drivers bind to it | none |
| HD Audio controller | AMD controller | kept | `boot-matrix`: snd_hda_intel drives it and finds the codec |
| HD Audio codec | Realtek vendor with QEMU's device number, an id that no real codec has | corrected to `hdaCodec`, with `pciSubsystem` as its subsystem | `sed-contract-qemu`, `boot-matrix` reads both |
| RTL8125 network card | added as a device model | kept | `boot-matrix`: a VM declared with `network.model = "rtl8125"` gets the card, and r8169 drives it |
| USB keyboard, mouse and tablet | Logitech IDs and names on the keyboard and mouse; the tablet keeps QEMU's 0627:0001, and every serial names the host controller's PCI path | kept; the tablet is corrected to the mouse's IDs and name, and the serials are removed | `sed-contract-qemu`, `boot-matrix`: none of them keeps QEMU's vendor id or name, and none reports a serial |
| Other emulated USB devices: storage, UAS, hub, serial, braille, smartcard, FIDO key, Wacom tablet, audio, MTP, network | left as is: QEMU's name, QEMU's vendor 46f4 on several, serials that name the host controller's PCI path, and QEMU's version and a placeholder serial in the MTP device info | each corrected to the ids and strings of one real device. Where the copied device has a serial, the serial is derived from the VM uuid and the port; where it has none, there is none. The MTP device info carries the phone's Android release and the USB serial | `sed-contract-qemu`, `boot-matrix` reads the USB disk, hub and serial adapter |
| VM generation counter `_HID` | left as `QEMUVGID` | corrected to Hyper-V's own; Windows binds the `VM_Gen_Counter` compatible id | `sed-contract-qemu` |
| MegaRAID package and firmware component version, default HBA serial | left as QEMU's version with `-QEMU`, serial `QEMU123456` | corrected to a real LSI package and a serial in LSI's format; the component version loses the suffix | `sed-contract-qemu` |
| SMBIOS chassis type | left as type 1, Other | corrected to `smbios.chassisType` | `sed-contract-qemu`, `boot-matrix`: VMAware's CTYPE check does not fire |
| Default header of an `-acpitable` given without one | left as `QEMU` signature, OEM and creator | corrected to an `OEM1` signature, `acpiOem`, and AMI's creator | `sed-contract-qemu` |
| Device hotplug | off for every device | reverted | `boot-matrix` hot-plugs a USB keyboard |
| IDE disk and CD | Samsung and Hitachi models, Samsung CD INQUIRY, blank serial | corrected to `disk.*` and one CD identity | `boot-smoke` reads ATA IDENTIFY and SCSI INQUIRY, `boot-matrix` reads the disk's ATA IDENTIFY |
| NVMe model | `NVMe Ctrl` | corrected to `disk.model` | `sed-contract-qemu` |
| SMBIOS defaults | off, manufacturer `Unknown` | kept; the board strings come from the QEMU arguments | `boot-matrix` boots with SMBIOS emulated |
| ACPI table header | a compiled-in OEM instead of the machine's `oem-id`, creator `ACPI` | OEM corrected to `acpiOem` | `boot-matrix` reads every table header |
| ACPI PCI device names | board names instead of `S` and the slot number | kept; the LPC slot names follow the devices to 0x1f, and scopes, notifications and empty slots get the same names | `boot-smoke`, `boot-matrix`: no ACPI error in the guest kernel log |
| CPU and memory hotplug in the DSDT | removed, together with the processor objects | kept; processors come back through `acpiProcessors` | `boot-matrix` finds processor devices |
| fw_cfg ACPI device, debug object | removed | kept | none |
| WAET | removed | reverted while `acpi.waet` is on, which is the default; stays removed when it is off | `sed-contract-qemu`, `boot-matrix` finds the table, or finds it missing with `acpi.waet` off |
| FADT C2 and C3 latency | values just past the not-supported limit | corrected to `acpi.c2Latency` and `acpi.c3Latency` | `sed-contract-qemu`, `boot-matrix` reads the FADT |
| FADT profile and hypervisor vendor | Desktop, blank vendor | kept | `boot-matrix` reads the vendor as blank |
| DSDT names, `_OSI` | `DRAC` and `GPE0` renamed, and a Windows `_OSI` table added | kept, except GPE0's new name: VMAware reads it as QEMU next to its PNP0A06 id, so it is renamed again. The format string of the `_OSI` loop is fixed so that it builds | `sed-contract-qemu`, the build |
| PCI interrupt list | more IRQs | kept | none |
| fw_cfg signatures | DMA signature changed, but the port still answers `QEMU` | port signature corrected to 0xFF bytes, with OVMF changed to match | `boot-matrix` reads the port |
| CPUID 6 APERF and MPERF | exposed with `cpu-pm` | kept; a domain's `cpuPm` turns cpu-pm on, and `aperfMperf` turns on the bit inside it | `boot-matrix` reads CPUID 6 |

## EDK2

| Part | AutoVirt | Here | Proof |
| - | - | - | - |
| Firmware vendor | marked for AutoVirt's own script, which is not vendored, so it stays `EDK II` | corrected to `smbios.biosVendor` | `sed-contract-edk2`, `sed-contract-edk2-vendor` |
| ACPI OEM id and table id of OVMF's own tables | marked, so they stay `INTEL` and `EDK2` | corrected to `acpiOem` | `sed-contract-edk2`, `boot-matrix` reads every table header |
| Firmware revision, version and date, ACPI creator and revisions | marked only | left stock | none |
| Host bridge ID OVMF expects | AutoVirt's host bridge ID | reverted to 0x29C0 | `sed-contract-edk2`, every boot |
| Power management base | slot 0x14 | reverted to 0x1f | `sed-contract-edk2`, every boot |
| Bridge resource hints | match the CPU vendor's bridges that QEMU now reports | kept | `boot-matrix` boots a virtio disk behind a root port |
| Boot order variables | `BootOrder` and a number instead of `VMMBootOrder` | kept | none |
| Video driver | VGA IDs follow QEMU's, and the QXL entry moved to the CPU vendor | VGA kept; QXL reverted to 1b36, which QEMU's QXL card still reports | `boot-matrix` needs a firmware framebuffer with VGA and with QXL |
| SMBIOS type 0 default | virtual machine bit cleared | kept | none |
| Authenticated variable store names | `certdb` renamed | kept | `boot-matrix` Secure Boot cases |

Added here, not from AutoVirt:

| Part | Here | File |
| - | - | - |
| EDID identity | QEMU's EDID carries the `edid` options, including its serial number | [qemu/post-patch.nix](../qemu/post-patch.nix) |
| ACPI interrupt routing | the routing tables are named as AMI names them, and APIC mode is routed directly to GSI 16 to 23, without QEMU's GSI link devices | [qemu/post-patch.nix](../qemu/post-patch.nix), [qemu/q35-direct-gsi.patch](../qemu/q35-direct-gsi.patch) |
| HPET `_STA` | reports the timer as present, without QEMU's period check | [qemu/hpet-sta.patch](../qemu/hpet-sta.patch) |
| SCSI vendor and product | set in QEMU | [qemu/post-patch.nix](../qemu/post-patch.nix) |
| Drive firmware revisions | set in QEMU from `disk.firmware` and `disk.opticalFirmware` | [qemu/post-patch.nix](../qemu/post-patch.nix) |
| SMBIOS type 0 | a real board's characteristics and the UEFI flag, in QEMU | [qemu/post-patch.nix](../qemu/post-patch.nix) |
| SMBIOS board fields | type 4 voltage, upgrade, characteristics and cache handles, and type 8 connector types and external references. QEMU had no options for these. They are filled from `cpuIdentity` and `smbios.ports` | [qemu/smbios-board-fields.patch](../qemu/smbios-board-fields.patch) |
| SMBIOS memory slots | type 16 with the board's maximum and slot count; one type 17 per slot, each with its own serial, and an empty slot shown as no module installed; and type 19 to match. This replaces one device per populated module | [qemu/smbios-memory-slots.patch](../qemu/smbios-memory-slots.patch) |
| MegaRAID serial | derived from the VM uuid and the card's PCI path | [qemu/megasas-serial-from-uuid.patch](../qemu/megasas-serial-from-uuid.patch) |
| USB serials | derived from the VM uuid and the port, for the devices whose real model has a serial | [qemu/usb-serial-from-uuid.patch](../qemu/usb-serial-from-uuid.patch) |
| xHCI register window | 64 KB with the Intel patch, as Intel's PCH controllers decode, instead of QEMU's 16 KB. Past 16 KB, Windows' driver for the Intel PCH id faults. 16 KB with the AMD patch | [qemu/post-patch.nix](../qemu/post-patch.nix) |
| Hyper-V implementation limits, CPUID 0x40000005 | 0x140 virtual and 0x200 logical processors and 0x25B0 interrupt vectors, as reported by a host of the Hyper-V build that QEMU names in 0x40000002. This replaces QEMU's 0xFFFFFFFF and 64 | [qemu/post-patch.nix](../qemu/post-patch.nix) |
| ACPI container `_UID`s | the PNP0A06 containers are numbered 1 to 5, instead of QEMU's names CPU Hotplug, SMI, PCI Hotplug, Memory hotplug and DIMM devices, which Windows turns into their instance ids. AutoVirt gives GPE0 the number 0 | [qemu/post-patch.nix](../qemu/post-patch.nix) |
| ACPI device names | every scope, notification and empty slot gets the name that AutoVirt gives the device | [qemu/acpi-pci-names.patch](../qemu/acpi-pci-names.patch) |
| KVM's hypercall-patching quirk | QEMU turns it off for each VM, so KVM no longer rewrites a guest's VMCALL or VMMCALL in the guest's code page | [qemu/kvm-hypercall-quirk.patch](../qemu/kvm-hypercall-quirk.patch) |
| EDID in OVMF | OVMF passes QEMU's EDID to Windows through the UEFI EDID Discovered and EDID Active protocols. Before, it used the EDID only for a resolution | [ovmf/edid-protocols.patch](../ovmf/edid-protocols.patch) |
| TCG platform firmware profile | OVMF follows revision 105. It logs its firmware volumes as EV_EFI_PLATFORM_FIRMWARE_BLOB2 with their names, instead of bare blobs at OVMF's fixed addresses | [ovmf/post-patch.nix](../ovmf/post-patch.nix) |
| Boot logo and BGRT | removed from OVMF | [ovmf/post-patch.nix](../ovmf/post-patch.nix) |

AutoVirt also ships two ACPI tables, `fake_battery.dsl` and
`spoofed_devices.dsl`. [acpi/](../acpi) has this repository's own versions of
them, and a change to AutoVirt's copies does not reach them. In these versions,
the OEM fields come from `acpiOem`. The battery reports a model, a maker and
`acpiSsdt.batterySerial`. The embedded controller is replaced by a voltage
regulator device, because q35 does not decode its I/O ports. The fan speed and
temperatures vary within a real board's range. `sensor-probes.dsl` is this
repository's own. `acpi-oem` checks their headers, and `boot-matrix` boots with
them.

## How Intel differs

- The Intel QEMU patch keeps the Intel vendor on the chipset and leaves LPC, SATA and SMBus at 0x1f. So those reverts change nothing on Intel. It still gives the chipset newer Intel device IDs and the same revisions as on AMD, and both are reverted.
- Its ACPI OEM is `INTEL` and `U Rvp`. The OEM edit replaces it, as on AMD.
- Its PCI IDs are Intel's. The VGA card keeps QEMU's device ID next to the Intel vendor.
- It gives the HD Audio controller Alder Lake's ID 0x51c8. Drivers then treat it as a controller with capabilities that QEMU's model does not have, and a Linux guest finds no codec. The ID is reverted to ICH9's own 0x293e and ICH6's 0x2668, which match the ICH9 board. `boot-matrix-intel` finds the codec.
- Only the Intel patch renames the pvpanic device's ACPI ID from `QEMU0001` to `UEFI0001`. This is kept, and no check reads it.
- The Intel EDK2 patch leaves the power management base at 0x1f. It changes the OEM table id of OVMF's own tables, and `acpiOem` replaces that.
