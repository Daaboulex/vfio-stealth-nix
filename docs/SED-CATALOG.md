# Sed and anchor catalog

This file lists the text edits in the patch stack that can mislead. The anchors
themselves are in the post-patch files. This file says what a diff of them does
not show.

## The ordinary case needs no entry

- Upstream renames a string, so the anchor stops matching. Then the edit's own assertion or the sed contract fails on the next build. The fix is to re-aim the anchor.
- This file lists these cases: an anchor that another patch also writes, a match broader than it looks, an assertion that passes without an edit, an edit that must change together with another, and a value kept for a reason the code does not show.
- Anchors, replacements and guards stay out of this file. `sed-catalog-lean` fails when they appear here, and when a heading names a file that no longer rewrites text.

## qemu/post-patch.nix: ACPI OEM ID and table ID

- **Counters:** the OEM ID and table ID that the AutoVirt patch writes into every ACPI table header.
- **Breaks when:** AutoVirt changes either value for a vendor. The anchor is the vendor's value in `traits` in [lib/autovirt-patches.nix](../lib/autovirt-patches.nix), so the AMD and Intel patches do not collide.
- On AMD, the default `acpiOem` is the same as what AutoVirt writes. So with the defaults the edit changes nothing, and its assertion still passes. The sed contracts use other values, so the edit is proven there.
- **Repair:** update `traits.<vendor>.patchedOemId` or `patchedOemTableId`.

## qemu/post-patch.nix: aml_string format argument

- **Counters:** nothing; this is a build fix. `aml_string` works like printf. AutoVirt's `_OSI` loop passes a variable as the format, and nixpkgs' `-Werror=format-security` rejects that.
- **Breaks when:** AutoVirt fixes it; then the absence check passes with no edit. Or AutoVirt renames the loop variable; then the compiler fails.
- **Repair:** drop the edit once AutoVirt has the fix.

## qemu/post-patch.nix: ICH9 device placement

- **Counters:** the AMD patch's move of the LPC bridge, SATA and SMBus from slot 0x1f to 0x14. The Intel patch leaves them at 0x1f, where the edits change nothing.
- **Breaks when:** the three devices are split. Firmware and guests find a slot through its function 0. So a device left at 0x14, without LPC at 0x14 function 0, is never enumerated: a SATA disk disappears and the VM ends up in the boot manager.
- **Breaks when:** QEMU and OVMF disagree on the LPC slot. OVMF probes its power management base on LPC. A guest whose LPC is somewhere else hangs in firmware with no console output.
- The ACPI names follow the slot. LPCB, SAT1 and SBUS move with the devices, or the DSDT's `PCI0.LPCB` references cannot resolve. On Intel the names are already at 0x1f, and that edit is skipped.
- **Repair:** move LPC, SATA and SMBus together, keep LPC at function 0, and change the OVMF power management base and the ACPI name table in the same commit.

## qemu/acpi-pci-names.patch: one name per PCI device

- **Counters:** AutoVirt's board names reach only the device objects. The hotplug scopes, notifications and empty slots keep QEMU's `S` names. Those names then point at nothing, and the guest kernel logs ACPI errors.
- A slot object built while the slot is empty must carry the name the device gets once it is plugged in. So the naming function compares against every earlier slot and function, populated or not.
- **Breaks when:** a new AutoVirt patch drops the duplicate-name loop that this patch replaces. That loop is this repository's own fix inside the vendored patch, recorded in [vendor/autovirt/README](../vendor/autovirt/README). So a patch taken from upstream does not have it, unless upstream took the fix. This patch then no longer applies.
- **Repair:** port the loop into the new AutoVirt patch first, or rebase this patch on what upstream wrote.

## qemu/post-patch.nix: ICH9 vendor and revision

- **Counters:** the AMD vendor that the AMD patch puts next to the ICH9 device IDs, and the revisions that both vendors' patches set.
- The vendor edits and their checks test that the AMD vendor is absent. On Intel this holds without any edit, by design.
- **Breaks when:** AutoVirt writes the vendor through a different expression. Then the absence check passes while the AMD vendor is still set. `boot-smoke` reads the IDs inside the guest and catches it.
- **Repair:** re-aim the vendor edit at the new expression.

## qemu/post-patch.nix: IDE drive serial

- **Counters:** AutoVirt's blank IDE serial. This edit replaces it with `disk.serial`.
- **Breaks when:** AutoVirt blanks the serial in another way.
- The anchor has a C escape inside a sed expression inside a Nix string. So each backslash is written several times.
- **Repair:** update the anchor, and work out the escapes again from the C source.

## qemu/post-patch.nix: EDID serial number

- **Counters:** the serial number 0 that QEMU writes for a display device that has no serial string.
- Only the fallback changes. A display device with a serial string still gets that string read as a number, as upstream does. That string also fills the serial text descriptor.
- `edid.serial` is the monitor name, which a separate edit writes. The numeric serial is `edid.serialNumber`. The two do not change together.
- **Breaks when:** upstream rewrites the fallback expression. The edit's check then fails.
- **Repair:** re-aim the edit at the new expression.

## qemu/post-patch.nix: host bridge device ID

- **Counters:** the host bridge ID that each vendor's patch sets.
- The edit is anchored on the macro name and rewrites whatever value follows it. So one edit covers both vendors.
- **Breaks when:** AutoVirt renames the macro. Then the edit matches nothing and its check fails.
- **Repair:** re-aim the edit and its check. The value stays 0x29c0, paired with the same revert in [ovmf/post-patch.nix](../ovmf/post-patch.nix).

## qemu/post-patch.nix: PCI subsystem

- **Counters:** QEMU's 1af4:1100 subsystem, which every device without its own subsystem reports. AutoVirt leaves it.
- The device id must be 0x40 or more. The virtio spec requires this for modern virtio devices. OVMF's virtio driver skips a device below it, so a virtio disk behind a PCIe root port does not boot.
- An assertion refuses a lower value at evaluation, and `boot-matrix` boots a virtio disk.
- **Repair:** pick a subsystem that a real board reports, with a device id of 0x40 or more.

## qemu/post-patch.nix: fw_cfg signature

- **Counters:** the `QEMU` signature that the fw_cfg port answers. AutoVirt changes only the DMA signature. It leaves the port signature, marked with a trailing comment.
- The anchor includes AutoVirt's trailing comment. A new AutoVirt patch that rewrites that line breaks the edit.
- **Breaks when:** QEMU and OVMF disagree. OVMF uses fw_cfg only when the port answers the signature it expects. Without fw_cfg it finds none of QEMU's tables. The edit here and the one in [ovmf/post-patch.nix](../ovmf/post-patch.nix) change together or not at all.
- **Repair:** change the value in both files in one commit.

## qemu/post-patch.nix: USB serial strings

- **Counters:** QEMU's USB serials, which carried the host controller's PCI path. [qemu/usb-serial-from-uuid.patch](../qemu/usb-serial-from-uuid.patch) derives them from the VM uuid and the port instead.
- The zeros that an edit writes into a device's serial string are never shown to a guest. The derived serial replaces them, and their count sets its length.
- If the copied original device has no serial, the device loses its serial string as well as its index, because a guest can read any string by index.
- **Breaks when:** QEMU adds a USB device that calls `usb_desc_create_serial`. That device gets a derived serial as long as its own default serial string. Its other strings stay QEMU's until an edit here names it.
- **Repair:** give the new device an identity here, with a serial string as long as the serial of its original.

## ovmf/post-patch.nix: power management base

- **Counters:** the AMD EDK2 patch's move of the power management base away from slot 0x1f.
- The edit is anchored on the macro names, never on AutoVirt's address. It rewrites the whole line after each definition. A pinned address would stop matching on the day AutoVirt moves it.
- `DRAMC_REGISTER_Q35` addresses device 0 and must stay untouched. A check refuses any other address left in the header.
- **Repair:** keep this edit and the QEMU LPC placement in step.

## ovmf/post-patch.nix: firmware vendor string

- **Counters:** the `EDK II` firmware vendor.
- The default is in `MdeModulePkg.dec`, not in the platform DSC.
- **Breaks when:** EDK2 moves the declaration to another file. Then the check on `MdeModulePkg.dec` fails.
- **Repair:** point the edit and its check at the new file.

## ovmf/post-patch.nix: QXL video entry

- **Counters:** AutoVirt's move of OVMF's QXL entry to the CPU vendor. QEMU's QXL card keeps vendor 1b36. So the firmware would not drive it, and a QXL VM would show nothing until the OS loads its own driver.
- The EDK2 sources have CRLF line ends. A pattern that ends at the end of a line must allow the carriage return, or it matches nothing. The vendored EDK2 patches also have CRLF.
- **Breaks when:** an edit to an EDK2 file is written as if the file had LF line ends. A substring replacement still works, but an anchor on a whole line does not.
- **Repair:** match an optional carriage return before the end of the line, and keep it in the replacement.

## kernel/*.nix: not catalogued

- Each kernel edit checks its own result with the functions in [kernel/prelude.nix](../kernel/prelude.nix).
- `kernel-postpatch-fits-*` runs the real scripts against real kernel sources for every combination, and `kernel-kvm-compiles-*` compiles the result.
- A copy of their anchors in this file could only go out of date.

## Updating this catalog

1. Add the edit and its assertion to the post-patch file.
2. Add a guard for it to [tests/sed-contract-qemu.nix](../tests/sed-contract-qemu.nix) or [tests/sed-contract-edk2.nix](../tests/sed-contract-edk2.nix).
3. Add an entry here only when the edit misleads in one of the ways above.
