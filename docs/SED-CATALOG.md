# Sed and anchor catalog

The text edits in the patch stack that mislead. The anchors themselves live in
the post-patch files; this file says what a diff of them will not.

## The ordinary case needs no entry

- Upstream renames a string, the anchor stops matching, and the edit's own assertion or the sed contract fails on the next build. The repair is to re-aim the anchor.
- Listed here: an anchor another patch also writes, a match broader than it looks, an assertion that passes without an edit, an edit that must change together with another, and a value kept for a reason the code does not show.
- Anchors, replacements and guards stay out of this file. `sed-catalog-lean` fails when they appear, and when a heading names a file that no longer rewrites text.

## qemu/post-patch.nix: ACPI OEM ID and table ID

- **Counters:** the OEM ID and table ID the AutoVirt patch writes into every ACPI table header.
- **Breaks when:** AutoVirt changes either value for a vendor. The anchor is the vendor's value in `traits` in [lib/autovirt-patches.nix](../lib/autovirt-patches.nix), so the AMD and Intel patches do not collide.
- On AMD the default `acpiOem` equals what AutoVirt writes, so with defaults the edit changes nothing and its assertion still passes. The sed contracts use other values, so the edit is proven there.
- **Repair:** update `traits.<vendor>.patchedOemId` or `patchedOemTableId`.

## qemu/post-patch.nix: aml_string format argument

- **Counters:** nothing; a build fix. `aml_string` is printf-like, and AutoVirt's `_OSI` loop passes a variable as the format, which nixpkgs' `-Werror=format-security` rejects.
- **Breaks when:** AutoVirt fixes it, and the absence check passes with no edit; or AutoVirt renames the loop variable, and the compiler fails.
- **Repair:** drop the edit once AutoVirt carries the fix.

## qemu/post-patch.nix: ICH9 device placement

- **Counters:** the AMD patch's move of the LPC bridge, SATA and SMBus from slot 0x1f to 0x14. The Intel patch leaves them at 0x1f, where the edits change nothing.
- **Breaks when:** the three devices are split. Firmware and guests find a slot through its function 0, so a device left at 0x14 without LPC at 0x14 function 0 is never enumerated: a SATA disk vanishes and the VM lands in the boot manager.
- **Breaks when:** QEMU and OVMF disagree on the LPC slot. OVMF probes its power management base on LPC, and a guest whose LPC sits elsewhere hangs in firmware with no console output.
- The ACPI names follow the slot: LPCB, SAT1 and SBUS move with the devices, or the DSDT's `PCI0.LPCB` references cannot resolve. On Intel the names already sit at 0x1f and that edit is skipped.
- **Repair:** move LPC, SATA and SMBus together, keep LPC at function 0, and change the OVMF power management base and the ACPI name table in the same commit.

## qemu/acpi-pci-names.patch: one name per PCI device

- **Counters:** AutoVirt's board names reach only the device objects, while the hotplug scopes, notifications and empty slots keep QEMU's `S` names, which then point at nothing and make the guest kernel log ACPI errors.
- A slot object built while the slot is empty must carry the name the device gets once plugged in. The naming function therefore compares against every earlier slot and function, populated or not.
- **Breaks when:** a new AutoVirt patch drops the duplicate-name loop this patch replaces. That loop is this repository's own fix inside the vendored patch, recorded in [vendor/autovirt/README](../vendor/autovirt/README), so a patch taken from upstream lacks it unless upstream took the fix, and this patch then no longer applies.
- **Repair:** port the loop into the new AutoVirt patch first, or rebase this patch on what upstream wrote.

## qemu/post-patch.nix: ICH9 vendor and revision

- **Counters:** the AMD vendor the AMD patch puts beside the ICH9 device IDs, and the revisions both vendors' patches set.
- The vendor edits and their checks look for the AMD vendor being absent. That holds on Intel without any edit, by design.
- **Breaks when:** AutoVirt writes the vendor through a different expression. The absence check then passes while the AMD vendor is still set; `boot-smoke` reads the IDs inside the guest and catches it.
- **Repair:** re-aim the vendor edit at the new expression.

## qemu/post-patch.nix: IDE drive serial

- **Counters:** AutoVirt's blank IDE serial, which this edit replaces with `disk.serial`.
- **Breaks when:** AutoVirt blanks the serial another way.
- The anchor carries a C escape inside a sed expression inside a Nix string, so each backslash is written several times over.
- **Repair:** update the anchor and work the escapes out again from the C source.

## qemu/post-patch.nix: EDID serial number

- **Counters:** the serial number of 0 QEMU writes for a display device given no serial string.
- Only the fallback changes. A display device given a serial string still gets that string read as a number, as upstream does, and that string also fills the serial text descriptor.
- `edid.serial` is the monitor name, which a separate edit writes; the numeric serial is `edid.serialNumber`. The two do not change together.
- **Breaks when:** upstream rewrites the fallback expression; the edit's check then fails.
- **Repair:** re-aim the edit at the new expression.

## qemu/post-patch.nix: host bridge device ID

- **Counters:** the host bridge ID each vendor's patch sets.
- The edit is anchored on the macro name and rewrites whatever value follows, so one edit covers both vendors.
- **Breaks when:** AutoVirt renames the macro. The edit then matches nothing and its check fails.
- **Repair:** re-aim the edit and its check. The value stays 0x29c0, paired with the same revert in [ovmf/post-patch.nix](../ovmf/post-patch.nix).

## qemu/post-patch.nix: PCI subsystem

- **Counters:** QEMU's 1af4:1100 subsystem, which every device without its own reports. AutoVirt leaves it.
- The device id must be 0x40 or more. The virtio spec asks it of modern virtio devices, and OVMF's virtio driver skips a device below it, so a virtio disk behind a PCIe root port does not boot.
- An assertion refuses a lower value at evaluation, and `boot-matrix` boots a virtio disk.
- **Repair:** pick a subsystem a real board reports with a device id of 0x40 or more.

## qemu/post-patch.nix: fw_cfg signature

- **Counters:** the `QEMU` signature the fw_cfg port answers. AutoVirt changes only the DMA signature and leaves the port signature, marked with a trailing comment.
- The anchor includes AutoVirt's trailing comment. A new AutoVirt patch that rewrites that line breaks the edit.
- **Breaks when:** QEMU and OVMF disagree. OVMF uses fw_cfg only when the port answers the signature it expects, and without fw_cfg it finds none of QEMU's tables. The edit here and the one in [ovmf/post-patch.nix](../ovmf/post-patch.nix) change together or not at all.
- **Repair:** change the value in both files in one commit.

## qemu/post-patch.nix: USB serial strings

- **Counters:** QEMU's USB serials, which carried the host controller's PCI path. [qemu/usb-serial-from-uuid.patch](../qemu/usb-serial-from-uuid.patch) derives them from the VM uuid and the port instead.
- The zeros an edit writes into a device's serial string are never shown to a guest: the derived serial replaces them, and their count sets its length.
- A device whose copied original has no serial loses its serial string as well as its index, since a guest can read any string by index.
- **Breaks when:** QEMU adds a USB device that calls `usb_desc_create_serial`. It gets a derived serial as long as its own default serial string, and its other strings stay QEMU's until an edit here names it.
- **Repair:** give the new device an identity here, with a serial string of the length its original's serial has.

## ovmf/post-patch.nix: power management base

- **Counters:** the AMD EDK2 patch's move of the power management base off slot 0x1f.
- The edit is anchored on the macro names, never on AutoVirt's address, and rewrites the line after each definition wholesale. A pinned address stops matching the day AutoVirt moves it.
- `DRAMC_REGISTER_Q35` addresses device 0 and must stay untouched; a check refuses any other address left in the header.
- **Repair:** keep this edit and the QEMU LPC placement in step.

## ovmf/post-patch.nix: firmware vendor string

- **Counters:** the `EDK II` firmware vendor.
- The default lives in `MdeModulePkg.dec`, not the platform DSC.
- **Breaks when:** EDK2 moves the declaration to another file. The check on `MdeModulePkg.dec` then fails.
- **Repair:** point the edit and its check at the new file.

## ovmf/post-patch.nix: QXL video entry

- **Counters:** AutoVirt's move of OVMF's QXL entry to the CPU vendor. QEMU's QXL card keeps vendor 1b36, so the firmware would not drive it and a QXL VM would show nothing until the OS loads its own driver.
- The EDK2 sources have CRLF line ends. A pattern that ends at the end of a line must allow the carriage return, or it matches nothing. The vendored EDK2 patches carry CRLF too.
- **Breaks when:** an edit to an EDK2 file is written as if the file had LF line ends. A substring replacement still works; an anchor on a whole line does not.
- **Repair:** match an optional carriage return before the end of the line, and keep it in the replacement.

## kernel/*.nix: not catalogued

- Each kernel edit asserts its own result with the functions in [kernel/prelude.nix](../kernel/prelude.nix).
- `kernel-postpatch-fits-*` runs the real scripts against real kernel sources for every combination, and `kernel-kvm-compiles-*` compiles the result.
- A copy of their anchors here could only drift.

## Updating this catalog

1. Add the edit and its assertion to the post-patch file.
2. Add a guard for it to [tests/sed-contract-qemu.nix](../tests/sed-contract-qemu.nix) or [tests/sed-contract-edk2.nix](../tests/sed-contract-edk2.nix).
3. Add an entry here only when the edit misleads in one of the ways above.
