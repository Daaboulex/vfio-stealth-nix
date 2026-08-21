# Sed / awk / anchor catalog

Single source of truth for every text-replacement anchor in the stealth
patch stack. When an upstream bump (AutoVirt, QEMU, EDK2, CachyOS) moves
a target, this file is the index a future maintainer uses to find the
broken anchor and fix it.

The contract tests under `tests/` verify each anchor on every build of
the stealth repo. A red `nix flake check` from one of those tests is the
first signal that an anchor has moved.

## Reading order

- `qemu/post-patch.nix` (35 substitutions): hardware identity, Q35 chipset
  reversions, ICH9 LPC placement, PCI subsystem
- `ovmf/package.nix` (6 substitutions + 1 filterdiff): firmware identity, MCH,
  PM register address
- `kernel/timing-patch.nix` (5 anchors): hand-ported BetterTiming TSC compensation
- `kernel/cpuid-patch.nix` (2 anchors): Hypervisor-Phantom CPUID override
- `kernel/cpuid-disable.nix` (2 anchors): CPUID passthrough (clear intercept)

---

## qemu/post-patch.nix — EDID manufacturer

- **Anchor:** `"RHT"` (hw/display/edid-generate.c)
- **Replacement:** `"${edidManufacturer}"`
- **Tool:** `substituteInPlace --replace-fail`
- **Guard:** none (substituteInPlace is its own guard)
- **Counters:** Stealth repo identity; not an AutoVirt counter
- **Breaks when:** QEMU renames the default EDID manufacturer
- **Repair:** Update the anchor to match the new QEMU default

## qemu/post-patch.nix — EDID serial

- **Anchor:** `"QEMU Monitor"` (hw/display/edid-generate.c)
- **Replacement:** `"${edidSerial}"`
- **Tool:** `substituteInPlace --replace-fail`
- **Guard:** none
- **Counters:** Stealth identity
- **Breaks when:** QEMU renames the default EDID serial
- **Repair:** Update the anchor

## qemu/post-patch.nix — EDID product code

- **Anchor:** `0x1234` (scoped: hw/display/edid-generate.c)
- **Replacement:** `${edidProductCode}` (default `0x2480`)
- **Tool:** `sed -i 's|0x1234|...|g'`
- **Guard:** `${edidProductCode}` must appear in hw/display/edid-generate.c after sed
- **Counters:** Stealth identity
- **Breaks when:** QEMU changes the EDID product code default, or
  AutoVirt adds another `0x1234` literal in this file
- **Repair:** Update the anchor; consider scoping more narrowly

## qemu/post-patch.nix — EDID manufacture week

- **Anchor:** `edid[16] = 42;` (hw/display/edid-generate.c)
- **Replacement:** `edid[16] = ${toString edidWeek};` (default 22)
- **Tool:** `sed -i 's|edid\[16\] = 42;|...|g'`
- **Guard:** `edid[16] = 22;` must appear after sed
- **Counters:** Stealth identity
- **Breaks when:** QEMU removes or renames the week assignment
- **Repair:** Update the anchor

## qemu/post-patch.nix — EDID manufacture year offset

- **Anchor:** `2014 - 1990` (hw/display/edid-generate.c)
- **Replacement:** `${toString edidYear} - 1990` (default 2020)
- **Tool:** `sed -i 's|2014 - 1990|...|g'`
- **Guard:** `${toString edidYear} - 1990` must appear after sed
- **Counters:** Stealth identity
- **Breaks when:** QEMU refactors the year-offset calculation
- **Repair:** Update the anchor

## qemu/post-patch.nix — EDID DPI

- **Anchor:** `uint32_t dpi = 100;` (hw/display/edid-generate.c)
- **Replacement:** `uint32_t dpi = ${toString edidDpi};` (default 91)
- **Tool:** `sed -i 's|uint32_t dpi = 100;|...|g'`
- **Guard:** `uint32_t dpi = 91;` must appear after sed
- **Counters:** Stealth identity
- **Breaks when:** QEMU changes the DPI default
- **Repair:** Update the anchor

## qemu/post-patch.nix — EDID default resolution X

- **Anchor:** `info->prefx = 1280;` (hw/display/edid-generate.c)
- **Replacement:** `info->prefx = ${toString edidResX};` (default 1920)
- **Tool:** `sed -i 's|info->prefx = 1280;|...|g'`
- **Guard:** `info->prefx = 1920;` must appear after sed
- **Counters:** Stealth identity
- **Breaks when:** QEMU changes the default prefx
- **Repair:** Update the anchor

## qemu/post-patch.nix — EDID default resolution Y

- **Anchor:** `info->prefy = 800;` (hw/display/edid-generate.c)
- **Replacement:** `info->prefy = ${toString edidResY};` (default 1080)
- **Tool:** `sed -i 's|info->prefy = 800;|...|g'`
- **Guard:** `info->prefy = 1080;` must appear after sed
- **Counters:** Stealth identity
- **Breaks when:** QEMU changes the default prefy
- **Repair:** Update the anchor

## qemu/post-patch.nix — SCSI INQUIRY vendor (8-char)

- **Anchor:** `"QEMU    "` (8 spaces; hw/scsi/scsi-bus.c)
- **Replacement:** `"${builtins.substring 0 8 (scsiVendor + "        ")}"`
- **Tool:** `substituteInPlace --replace-fail`
- **Guard:** none
- **Counters:** Stealth identity; AutoVirt does not touch this
- **Breaks when:** QEMU changes the default SCSI vendor string
- **Repair:** Update the anchor; check the 8-space padding

## qemu/post-patch.nix — SCSI INQUIRY target product

- **Anchor:** `"QEMU TARGET     "` (16 chars; hw/scsi/scsi-bus.c)
- **Replacement:** `"${scsiTargetProduct}"`
- **Tool:** `substituteInPlace --replace-fail`
- **Guard:** none
- **Counters:** Stealth identity
- **Breaks when:** QEMU changes the target product string
- **Repair:** Update the anchor; check the 5-space padding

## qemu/post-patch.nix — SCSI disk product

- **Anchor:** `"QEMU HARDDISK"` (hw/scsi/scsi-disk.c)
- **Replacement:** `"${diskModel}"`
- **Tool:** `substituteInPlace --replace-fail`
- **Guard:** none
- **Counters:** Stealth identity
- **Breaks when:** QEMU changes the default disk product
- **Repair:** Update the anchor

## qemu/post-patch.nix — SCSI CD-ROM product

- **Anchor:** `"QEMU CD-ROM"` (hw/scsi/scsi-disk.c)
- **Replacement:** `"${opticalModel}"`
- **Tool:** `substituteInPlace --replace-fail`
- **Guard:** none
- **Counters:** Stealth identity
- **Breaks when:** QEMU changes the default CD-ROM product
- **Repair:** Update the anchor

## qemu/post-patch.nix — SCSI vendor (4-char)

- **Anchor:** `"QEMU"` (hw/scsi/scsi-disk.c) — generic 4-char match
- **Replacement:** `"${scsiVendor}"`
- **Tool:** `substituteInPlace --replace-fail`
- **Guard:** none
- **Counters:** Stealth identity
- **Breaks when:** QEMU changes the 4-char vendor default
- **Repair:** Update the anchor; consider scoping to specific
  occurrences if QEMU adds more `"QEMU"` literals

## qemu/post-patch.nix — ACPI OEM ID

- **Anchor:** `"${patchedOemId}"` -- `"ALASKA"` on AMD, `"INTEL "` on Intel
  (include/hw/acpi/aml-build.h)
- **Replacement:** `"${acpiOemId}"`
- **Tool:** `sed -i 's|"${patchedOemId}"|...|g'`
- **Guard:** `"${acpiOemId}"` must appear after sed
- **Counters:** AutoVirt SETS this (replaces `"BOCHS "`); our sed
  reverses AutoVirt's choice
- **Breaks when:** AutoVirt changes the OEM ID for a vendor. The anchor is
  no longer hardcoded -- it comes from `lib/autovirt-patches.nix` `traits`,
  keyed by `cpuVendor` -- so the AMD and Intel patches no longer collide.
  A changed upstream value still no-ops silently, which the per-vendor
  `sed-contract-qemu-<vendor>` guard catches.
- **Repair:** Update `traits.<vendor>.patchedOemId` in
  `lib/autovirt-patches.nix`

## qemu/post-patch.nix — ACPI OEM Table ID

- **Anchor:** `"${patchedOemTableId}"` -- `"A M I   "` on AMD, `"U Rvp   "`
  on Intel (8 chars, padded; include/hw/acpi/aml-build.h)
- **Replacement:** `"${acpiOemTableId}"`
- **Tool:** `sed -i 's|"${patchedOemTableId}"|...|g'`
- **Guard:** `"${acpiOemTableId}"` must appear after sed
- **Counters:** AutoVirt SETS this (replaces `"BXPC    "`)
- **Breaks when:** AutoVirt changes the table ID for a vendor
- **Repair:** Update `traits.<vendor>.patchedOemTableId` in
  `lib/autovirt-patches.nix`

## qemu/post-patch.nix -- aml_string format-security workaround

- **Anchor:** `aml_string(win_osi[n].osi)` (hw/i386/acpi-build.c)
- **Replacement:** `aml_string("%s", win_osi[n].osi)`
- **Tool:** `sed -i` + absence grep
- **Counters:** Not a stealth counter -- a build fix. `aml_string` is
  `G_GNUC_PRINTF(1,2)`, and AutoVirt's `_OSI` loop passes a variable as
  the format, which nixpkgs' `-Werror=format-security` rejects
- **Breaks when:** AutoVirt fixes it upstream (the sed no-ops, the absence
  grep still passes) or renames the loop variable (the compiler then fails
  loudly, which is the real backstop). See AutoVirt issue #169
- **Repair:** Drop this block once upstream carries the fix

## qemu/post-patch.nix -- ICH9 LPC bridge placement

- **Anchor:** `#define ICH9_LPC_DEV` / `ICH9_LPC_FUNC`
  (include/hw/southbridge/ich9.h)
- **Replacement:** `31` and `0` -- stock Q35 `00:1f.0`
- **Tool:** `sed -i` + `grep -qE` guard on each
- **Counters:** AMD-v11.0.2 moves LPC to device 20; AMD-v11.0.0 and the
  Intel patches leave it alone, so on Intel this is a no-op whose guard
  still passes because stock QEMU already carries 31/0
- **Breaks when:** the pairing with `ovmf/package.nix` is broken. OVMF
  probes the PM register block at `0x1f:0`; if QEMU publishes LPC
  elsewhere the guest hangs in firmware with **no console output at all**.
  Upstream is itself inconsistent here -- its EDK2 patch addresses
  `0x14:3` while its QEMU patch sets `ICH9_LPC_FUNC 0`. See AutoVirt
  issue #170
- **Repair:** Keep this revert and the OVMF PM revert in lockstep; both
  are contract-guarded (`ich9-lpc-dev-stock-q35`,
  `ich9-lpc-func-stock-q35`, `pm-register-address`)

## qemu/post-patch.nix — IDE main disk model

- **Anchor:** `Samsung SSD 980 500GB` (hw/ide/core.c)
- **Replacement:** `${diskModel}`
- **Tool:** `substituteInPlace --replace-fail`
- **Guard:** none
- **Counters:** AutoVirt SETS this (replaces `"QEMU HARDDISK"`)
- **Breaks when:** AutoVirt changes the default IDE disk model
- **Repair:** Update the anchor to match AutoVirt's new value

## qemu/post-patch.nix — IDE CF-ATA disk model

- **Anchor:** `Hitachi HMS360404D5CF00` (hw/ide/core.c)
- **Replacement:** `${diskModel}`
- **Tool:** `substituteInPlace --replace-fail`
- **Guard:** none
- **Counters:** AutoVirt SETS this
- **Breaks when:** AutoVirt changes the default CF-ATA model
- **Repair:** Update the anchor

## qemu/post-patch.nix — IDE drive serial

- **Anchor:** `s->drive_serial_str[0] = '\\\\0';` (the 4-backslash is
  Nix+sed double-escape for a literal `\'0`; hw/ide/core.c)
- **Replacement:** `pstrcpy(s->drive_serial_str, sizeof(s->drive_serial_str), "${diskSerial}");`
- **Tool:** `sed -i "s|s->drive_serial_str\[0\] = '\\\\0';|...|g"`
- **Guard:** `pstrcpy(s->drive_serial_str` must appear after sed
- **Counters:** AutoVirt SETS this (replaces the previous snprintf with
  an empty-string fallback)
- **Breaks when:** AutoVirt changes the empty-string approach (e.g., to
  `memset(..., 0, sizeof(...))`)
- **Repair:** Update the anchor + re-derive the sed's backslash escapes

## qemu/post-patch.nix — IDE optical drive model

- **Anchor:** `HL-DT-ST BD-RE WH16NS60` (hw/ide/core.c)
- **Replacement:** `${opticalModel}`
- **Tool:** `substituteInPlace --replace-fail`
- **Guard:** none
- **Counters:** AutoVirt SETS this (replaces `"QEMU DVD-ROM"`)
- **Breaks when:** AutoVirt changes the default optical model
- **Repair:** Update the anchor

## qemu/post-patch.nix — MCH host-bridge device ID

- **Anchor:** `define PCI_DEVICE_ID_INTEL_P35_MCH      0x14d8`
  (include/hw/pci/pci_ids.h)
- **Replacement:** `define PCI_DEVICE_ID_INTEL_P35_MCH      0x29c0`
- **Tool:** `sed -i 's/define PCI_DEVICE_ID_INTEL_P35_MCH.*$/.../'`
- **Guard:** `PCI_DEVICE_ID_INTEL_P35_MCH.*0x29c0` must appear
- **Counters:** AutoVirt SETS this (0x29c0 → 0x14d8); OVMF's
  Q35 PEI init requires the real Intel Q35 ID
- **Breaks when:** AutoVirt changes the macro (e.g., renames
  `PCI_DEVICE_ID_INTEL_P35_MCH` to `PCI_DEVICE_ID_Q35_MCH`); the sed's
  `.*$` greedy match would still match the new name, but the FATAL guard
  checks for the literal `PCI_DEVICE_ID_INTEL_P35_MCH` substring which
  would fail
- **Repair:** Update the anchor + the FATAL guard

## qemu/post-patch.nix — MCH host-bridge vendor (declarative)

- **Anchor:** `k->vendor_id = PCI_VENDOR_ID_AMD;` (the file under
  `hw/pci-host/` that AutoVirt set this in)
- **Replacement:** `k->vendor_id = PCI_VENDOR_ID_INTEL;`
- **Tool:** `grep -rl` to locate the file + `sed -i 's|...|...|'`
- **Guard:** AutoVirt's AMD anchor must be found under hw/pci-host/
  AND the Intel replacement must appear in the located file
- **Counters:** AutoVirt SETS this; OVMF + QEMU on a real Q35 machine
  must agree on the vendor
- **Breaks when:** AutoVirt changes the anchor text (e.g., the class
  function changes) OR moves the host bridge to a different directory
- **Repair:** Update the grep pattern; the FATAL is loud so this
  fails LOUDLY

## qemu/package.nix — PCI subsystem vendor (global default)

- **Anchor:** `PCI_SUBVENDOR_ID_REDHAT_QUMRANET  0x1af4` (include/hw/pci/pci.h)
- **Replacement:** `PCI_SUBVENDOR_ID_REDHAT_QUMRANET  0x8086`
- **Tool:** `sed -i 's/...0x1af4/.../0x8086/'`
- **Guard:** FATAL if 0x8086 not found after sed
- **Counters:** Every Q35 chipset device inherits this default subsystem
  vendor. 0x1af4 (Red Hat) is a trivial QEMU fingerprint.
- **Breaks when:** QEMU renames the define or changes the spacing
- **Repair:** Update the anchor

## qemu/package.nix — PCI subsystem device (global default)

- **Anchor:** `PCI_SUBDEVICE_ID_QEMU             0x1100` (include/hw/pci/pci.h)
- **Replacement:** `PCI_SUBDEVICE_ID_QEMU             0x0000`
- **Tool:** `sed -i 's/...0x1100/.../0x0000/'`
- **Guard:** FATAL if 0x0000 not found after sed
- **Counters:** Same as above; 0x1100 ("QEMU") is the companion fingerprint
- **Breaks when:** QEMU renames the define or changes the spacing
- **Repair:** Update the anchor

---

## ovmf/package.nix — Firmware vendor string

- **Anchor:** `L"EDK II"` (MdeModulePkg/MdeModulePkg.dec +
  OvmfPkg/OvmfPkgX64.dsc)
- **Replacement:** `L"American Megatrends Inc."`
- **Tool:** `sed -i 's|L"EDK II"|L"American Megatrends Inc."|g'`
- **Guard:** grep -rq must NOT find `L"EDK II"` in either file
- **Counters:** Stealth identity
- **Breaks when:** AutoVirt moves the PCD declaration to a different
  .dec file; the sed misses the new file
- **Repair:** Update the file list in the sed; consider scoping
  the guard to a glob that catches the new file

## ovmf/package.nix — BGRT module strip (DSC)

- **Anchor:** `BootGraphicsResourceTableDxe` (OvmfPkg/OvmfPkgX64.dsc)
- **Replacement:** (deleted)
- **Tool:** `sed -i '/BootGraphicsResourceTableDxe/d'`
- **Guard:** grep -q must NOT find the string after sed
- **Counters:** VMAware CRC identifier 0x110350C5
- **Breaks when:** AutoVirt renames the BGRT module; the sed no-ops
  silently. The guard catches this (string still present = fail)
- **Repair:** Update the anchor to the new module name

## ovmf/package.nix — BGRT module strip (FDF)

- **Anchor:** `BootGraphicsResourceTableDxe` (OvmfPkg/OvmfPkgX64.fdf)
- **Replacement:** (deleted)
- **Tool:** same sed, applied to both .dsc and .fdf in one line
- **Guard:** grep -q must NOT find the string in .fdf
- **Breaks when:** Same as DSC strip

## ovmf/package.nix — LogoDxe module strip (FDF)

- **Anchor:** `LogoDxe` (OvmfPkg/OvmfPkgX64.fdf)
- **Replacement:** (deleted)
- **Tool:** `sed -i '/LogoDxe/d'`
- **Guard:** grep -q must NOT find the string
- **Counters:** TianoCore boot logo detection
- **Breaks when:** AutoVirt renames LogoDxe
- **Repair:** Update the anchor

## ovmf/package.nix — OVMF MCH device ID

- **Anchor:** `define INTEL_Q35_MCH_DEVICE_ID    0x14d8`
  (OvmfPkg/Include/IndustryStandard/Q35MchIch9.h)
- **Replacement:** `define INTEL_Q35_MCH_DEVICE_ID    0x29C0`
- **Tool:** `sed -i 's/define INTEL_Q35_MCH_DEVICE_ID.*$/.../'`
- **Guard:** grep -q must find `INTEL_Q35_MCH_DEVICE_ID.*0x29C0`
- **Counters:** AutoVirt SETS this; matches the QEMU-side revert
- **Breaks when:** AutoVirt renames the macro
- **Repair:** Update the anchor

## ovmf/package.nix — AutoVirt BaseTools hunk filter

- **Anchor:** filterdiff `-x '*/BaseTools/*'` (applied to the AutoVirt
  EDK2 patch)
- **Tool:** `filterdiff -x '*/BaseTools/*' ${autovirtPatch}`
- **Guard:** none
- **Counters:** BaseTools is pre-built and symlinked into the OVMF
  build tree; AutoVirt's BaseTools hunk would corrupt the build
- **Breaks when:** AutoVirt moves the BaseTools hunk to a different
  path (e.g., `*/BaseToolsPy/*` or renames `BaseTools` to
  `BaseTools-2.0`); the filter misses; the BaseTools hunk lands in
  the build tree and may fail later
- **Repair:** Update the filter pattern; the FATAL guards in the
  postPatch don't catch this directly. The contract test
  `sed-contract-edk2` asserts post-patch file content but doesn't
  catch a leaked BaseTools hunk -- strengthen if this becomes an
  issue

## ovmf/package.nix -- BGRT FDF guard

- **Anchor:** `BootGraphicsResourceTableDxe` (OvmfPkg/OvmfPkgX64.fdf)
- **Replacement:** (deleted)
- **Tool:** same sed as DSC strip, applied to both .dsc and .fdf
- **Guard:** grep -q must NOT find the string in .fdf after sed
- **Breaks when:** Same as DSC strip
- **Repair:** Same as DSC strip

---

## kernel/*.nix -- not catalogued here

The kernel scripts are not restated in this catalog. Each of their edits
now verifies its own effect (`landed` / `gone` / `exactly_one` from
`kernel/prelude.nix`), and `checks.kernel-postpatch-fits-cachyos` and
`checks.kernel-postpatch-fits-upstream` run the real scripts against real
kernel sources for every enable-combination. A copy of the anchors here
could only drift from the scripts that own them.

---

## Updating this catalog

When a sed is added or moved:

1. Add or update the section here
2. Add the corresponding guard in `tests/sed-contract-qemu.nix` or
   `tests/sed-contract-edk2.nix`
3. Run `nix flake check` -- the contract test must pass with the
   new anchor against the current upstream

Kernel scripts need no catalog entry: add the edit in `kernel/*.nix`
followed by a `landed` (or `gone`) call naming what it must produce, and
`checks.kernel-postpatch-fits-*` covers it automatically.
