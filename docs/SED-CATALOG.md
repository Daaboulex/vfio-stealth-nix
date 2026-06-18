# Sed / awk / anchor catalog

Single source of truth for every text-replacement anchor in the stealth
patch stack. When an upstream bump (AutoVirt, QEMU, EDK2, CachyOS) moves
a target, this file is the index a future maintainer uses to find the
broken anchor and fix it.

The contract tests under `tests/` verify each anchor on every build of
the stealth repo. A red `nix flake check` from one of those tests is the
first signal that an anchor has moved.

## Reading order

- `qemu/package.nix` (21 anchors): hardware identity + MCH vendor/device
- `ovmf/package.nix` (11 anchors + 1 filterdiff): firmware identity + MCH + debug port
- `kernel/timing-patch.nix` (5 anchors): BetterTiming TSC compensation
- `kernel/cpuid-patch.nix` (2 anchors): Hypervisor-Phantom CPUID override
- `kernel/cpuid-disable.nix` (2 anchors): CPUID passthrough (clear intercept)

---

## qemu/package.nix:94 — EDID manufacturer

- **Anchor:** `"RHT"` (hw/display/edid-generate.c)
- **Replacement:** `"${edidManufacturer}"`
- **Tool:** `substituteInPlace --replace-fail`
- **Guard:** none (substituteInPlace is its own guard)
- **Counters:** Stealth repo identity; not an AutoVirt counter
- **Breaks when:** QEMU renames the default EDID manufacturer
- **Repair:** Update the anchor to match the new QEMU default

## qemu/package.nix:95 — EDID serial

- **Anchor:** `"QEMU Monitor"` (hw/display/edid-generate.c)
- **Replacement:** `"${edidSerial}"`
- **Tool:** `substituteInPlace --replace-fail`
- **Guard:** none
- **Counters:** Stealth identity
- **Breaks when:** QEMU renames the default EDID serial
- **Repair:** Update the anchor

## qemu/package.nix:97 — EDID product code

- **Anchor:** `0x1234` (scoped: hw/display/edid-generate.c)
- **Replacement:** `${edidProductCode}` (default `0x2480`)
- **Tool:** `sed -i 's|0x1234|...|g'`
- **Guard:** `${edidProductCode}` must appear in hw/display/edid-generate.c after sed
- **Counters:** Stealth identity
- **Breaks when:** QEMU changes the EDID product code default, or
  AutoVirt adds another `0x1234` literal in this file
- **Repair:** Update the anchor; consider scoping more narrowly

## qemu/package.nix:102 — EDID manufacture week

- **Anchor:** `edid[16] = 42;` (hw/display/edid-generate.c)
- **Replacement:** `edid[16] = ${toString edidWeek};` (default 22)
- **Tool:** `sed -i 's|edid\[16\] = 42;|...|g'`
- **Guard:** `edid[16] = 22;` must appear after sed
- **Counters:** Stealth identity
- **Breaks when:** QEMU removes or renames the week assignment
- **Repair:** Update the anchor

## qemu/package.nix:107 — EDID manufacture year offset

- **Anchor:** `2014 - 1990` (hw/display/edid-generate.c)
- **Replacement:** `${toString edidYear} - 1990` (default 2020)
- **Tool:** `sed -i 's|2014 - 1990|...|g'`
- **Guard:** `${toString edidYear} - 1990` must appear after sed
- **Counters:** Stealth identity
- **Breaks when:** QEMU refactors the year-offset calculation
- **Repair:** Update the anchor

## qemu/package.nix:112 — EDID DPI

- **Anchor:** `uint32_t dpi = 100;` (hw/display/edid-generate.c)
- **Replacement:** `uint32_t dpi = ${toString edidDpi};` (default 91)
- **Tool:** `sed -i 's|uint32_t dpi = 100;|...|g'`
- **Guard:** `uint32_t dpi = 91;` must appear after sed
- **Counters:** Stealth identity
- **Breaks when:** QEMU changes the DPI default
- **Repair:** Update the anchor

## qemu/package.nix:118 — EDID default resolution X

- **Anchor:** `info->prefx = 1280;` (hw/display/edid-generate.c)
- **Replacement:** `info->prefx = ${toString edidResX};` (default 1920)
- **Tool:** `sed -i 's|info->prefx = 1280;|...|g'`
- **Guard:** `info->prefx = 1920;` must appear after sed
- **Counters:** Stealth identity
- **Breaks when:** QEMU changes the default prefx
- **Repair:** Update the anchor

## qemu/package.nix:123 — EDID default resolution Y

- **Anchor:** `info->prefy = 800;` (hw/display/edid-generate.c)
- **Replacement:** `info->prefy = ${toString edidResY};` (default 1080)
- **Tool:** `sed -i 's|info->prefy = 800;|...|g'`
- **Guard:** `info->prefy = 1080;` must appear after sed
- **Counters:** Stealth identity
- **Breaks when:** QEMU changes the default prefy
- **Repair:** Update the anchor

## qemu/package.nix:131 — SCSI INQUIRY vendor (8-char)

- **Anchor:** `"QEMU    "` (8 spaces; hw/scsi/scsi-bus.c)
- **Replacement:** `"${builtins.substring 0 8 (scsiVendor + "        ")}"`
- **Tool:** `substituteInPlace --replace-fail`
- **Guard:** none
- **Counters:** Stealth identity; AutoVirt does not touch this
- **Breaks when:** QEMU changes the default SCSI vendor string
- **Repair:** Update the anchor; check the 8-space padding

## qemu/package.nix:133 — SCSI INQUIRY target product

- **Anchor:** `"QEMU TARGET     "` (16 chars; hw/scsi/scsi-bus.c)
- **Replacement:** `"${scsiTargetProduct}"`
- **Tool:** `substituteInPlace --replace-fail`
- **Guard:** none
- **Counters:** Stealth identity
- **Breaks when:** QEMU changes the target product string
- **Repair:** Update the anchor; check the 5-space padding

## qemu/package.nix:137 — SCSI disk product

- **Anchor:** `"QEMU HARDDISK"` (hw/scsi/scsi-disk.c)
- **Replacement:** `"${diskModel}"`
- **Tool:** `substituteInPlace --replace-fail`
- **Guard:** none
- **Counters:** Stealth identity
- **Breaks when:** QEMU changes the default disk product
- **Repair:** Update the anchor

## qemu/package.nix:139 — SCSI CD-ROM product

- **Anchor:** `"QEMU CD-ROM"` (hw/scsi/scsi-disk.c)
- **Replacement:** `"${opticalModel}"`
- **Tool:** `substituteInPlace --replace-fail`
- **Guard:** none
- **Counters:** Stealth identity
- **Breaks when:** QEMU changes the default CD-ROM product
- **Repair:** Update the anchor

## qemu/package.nix:141 — SCSI vendor (4-char)

- **Anchor:** `"QEMU"` (hw/scsi/scsi-disk.c) — generic 4-char match
- **Replacement:** `"${scsiVendor}"`
- **Tool:** `substituteInPlace --replace-fail`
- **Guard:** none
- **Counters:** Stealth identity
- **Breaks when:** QEMU changes the 4-char vendor default
- **Repair:** Update the anchor; consider scoping to specific
  occurrences if QEMU adds more `"QEMU"` literals

## qemu/package.nix:144 — ACPI OEM ID

- **Anchor:** `"ALASKA"` (include/hw/acpi/aml-build.h)
- **Replacement:** `"${acpiOemId}"`
- **Tool:** `sed -i 's|"ALASKA"|...|g'`
- **Guard:** `"${acpiOemId}"` must appear after sed
- **Counters:** AutoVirt SETS this (replaces `"BOCHS "`); our sed
  reverses AutoVirt's choice
- **Breaks when:** AutoVirt changes the default OEM ID (e.g., from
  `"ALASKA"` to `"INT  "`); sed would no-op silently and FATAL would
  pass on the existing `"ALASKA"` literal
- **Repair:** Update the anchor to match AutoVirt's new value;
  consider asserting that AutoVirt's anchor IS present before sedding

## qemu/package.nix:149 — ACPI OEM Table ID

- **Anchor:** `"A M I   "` (8 chars, padded; include/hw/acpi/aml-build.h)
- **Replacement:** `"${acpiOemTableId}"`
- **Tool:** `sed -i 's|"A M I   "|...|g'`
- **Guard:** `"${acpiOemTableId}"` must appear after sed
- **Counters:** AutoVirt SETS this (replaces `"BXPC    "`)
- **Breaks when:** AutoVirt changes the default table ID
- **Repair:** Update the anchor to match AutoVirt's new value

## qemu/package.nix:157 — IDE main disk model

- **Anchor:** `Samsung SSD 980 500GB` (hw/ide/core.c)
- **Replacement:** `${diskModel}`
- **Tool:** `substituteInPlace --replace-fail`
- **Guard:** none
- **Counters:** AutoVirt SETS this (replaces `"QEMU HARDDISK"`)
- **Breaks when:** AutoVirt changes the default IDE disk model
- **Repair:** Update the anchor to match AutoVirt's new value

## qemu/package.nix:159 — IDE CF-ATA disk model

- **Anchor:** `Hitachi HMS360404D5CF00` (hw/ide/core.c)
- **Replacement:** `${diskModel}`
- **Tool:** `substituteInPlace --replace-fail`
- **Guard:** none
- **Counters:** AutoVirt SETS this
- **Breaks when:** AutoVirt changes the default CF-ATA model
- **Repair:** Update the anchor

## qemu/package.nix:161 — IDE drive serial

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

## qemu/package.nix:168 — IDE optical drive model

- **Anchor:** `HL-DT-ST BD-RE WH16NS60` (hw/ide/core.c)
- **Replacement:** `${opticalModel}`
- **Tool:** `substituteInPlace --replace-fail`
- **Guard:** none
- **Counters:** AutoVirt SETS this (replaces `"QEMU DVD-ROM"`)
- **Breaks when:** AutoVirt changes the default optical model
- **Repair:** Update the anchor

## qemu/package.nix:179 — MCH host-bridge device ID

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

## qemu/package.nix:186 — MCH host-bridge vendor (declarative)

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

---

## ovmf/package.nix:48 — Firmware vendor string

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

## ovmf/package.nix:60 — BGRT module strip (DSC)

- **Anchor:** `BootGraphicsResourceTableDxe` (OvmfPkg/OvmfPkgX64.dsc)
- **Replacement:** (deleted)
- **Tool:** `sed -i '/BootGraphicsResourceTableDxe/d'`
- **Guard:** grep -q must NOT find the string after sed
- **Counters:** VMAware CRC identifier 0x110350C5
- **Breaks when:** AutoVirt renames the BGRT module; the sed no-ops
  silently. The guard catches this (string still present = fail)
- **Repair:** Update the anchor to the new module name

## ovmf/package.nix:60 — BGRT module strip (FDF)

- **Anchor:** `BootGraphicsResourceTableDxe` (OvmfPkg/OvmfPkgX64.fdf)
- **Replacement:** (deleted)
- **Tool:** same sed, applied to both .dsc and .fdf in one line
- **Guard:** grep -q must NOT find the string in .fdf
- **Breaks when:** Same as DSC strip

## ovmf/package.nix:61 — LogoDxe module strip (FDF)

- **Anchor:** `LogoDxe` (OvmfPkg/OvmfPkgX64.fdf)
- **Replacement:** (deleted)
- **Tool:** `sed -i '/LogoDxe/d'`
- **Guard:** grep -q must NOT find the string
- **Counters:** TianoCore boot logo detection
- **Breaks when:** AutoVirt renames LogoDxe
- **Repair:** Update the anchor

## ovmf/package.nix:79 — OVMF MCH device ID

- **Anchor:** `define INTEL_Q35_MCH_DEVICE_ID    0x14d8`
  (OvmfPkg/Include/IndustryStandard/Q35MchIch9.h)
- **Replacement:** `define INTEL_Q35_MCH_DEVICE_ID    0x29C0`
- **Tool:** `sed -i 's/define INTEL_Q35_MCH_DEVICE_ID.*$/.../'`
- **Guard:** grep -q must find `INTEL_Q35_MCH_DEVICE_ID.*0x29C0`
- **Counters:** AutoVirt SETS this; matches the QEMU-side revert
- **Breaks when:** AutoVirt renames the macro
- **Repair:** Update the anchor

## ovmf/package.nix:43 — AutoVirt BaseTools hunk filter

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

## ovmf/package.nix:88 -- OVMF debug port 0x402

- **Anchor:** `PlatformDebugLibIoPort` (OvmfPkg/OvmfPkgX64.dsc)
- **Replacement:** `MdePkg/Library/BaseDebugLibNull/BaseDebugLibNull.inf`
- **Tool:** `sed -i 's|.../PlatformDebugLibIoPort/...|.../BaseDebugLibNull/...|g'`
- **Guard:** conditional -- `if grep -q 'PlatformDebugLibIoPort'`; prints
  `[INFO]` and continues if absent (no FATAL)
- **Counters:** I/O port 0x402 is a QEMU/OVMF debug artifact; detection
  software probes responsive I/O ports
- **Breaks when:** OVMF renames PlatformDebugLibIoPort or switches to a
  different DebugLib implementation (e.g., BaseDebugLibSerialPort for
  COM1 at 0x3F8). The conditional guard makes this a silent no-op.
- **Repair:** Update the anchor; the `sed-contract-edk2` guard for
  `BaseDebugLibNull` catches the break if no other BaseDebugLibNull
  exists in the DSC

## ovmf/package.nix:58 -- BGRT FDF guard

- **Anchor:** `BootGraphicsResourceTableDxe` (OvmfPkg/OvmfPkgX64.fdf)
- **Replacement:** (deleted)
- **Tool:** same sed as DSC strip, applied to both .dsc and .fdf
- **Guard:** grep -q must NOT find the string in .fdf after sed
- **Breaks when:** Same as DSC strip
- **Repair:** Same as DSC strip

---

## kernel/timing-patch.nix:19 — kvm_vcpu.valid_wakeup

- **Anchor:** `bool valid_wakeup;` (include/linux/kvm_host.h)
- **Tool:** sed `/bool valid_wakeup;/a\` (insert timing fields after)
- **Guard:** FATAL if anchor not found
- **Counters:** Adds `last_exit_start` and `total_exit_time` fields
  to struct kvm_vcpu
- **Breaks when:** Kernel renames the field (e.g., to `pending_wakeup`)

## kernel/timing-patch.nix:31 — MSR_IA32_TSC case in kvm_get_msr_common

- **Anchor:** `case MSR_IA32_TSC: {` (arch/x86/kvm/x86.c)
- **Tool:** awk (rewrites the whole block)
- **Guard:** FATAL if anchor not found
- **Counters:** TSC compensation in the MSR read handler
- **Breaks when:** Kernel adds another brace variant of this case label
  (the awk matches the FIRST occurrence; future-you may need to
  disambiguate with a more specific anchor)
- **Repair:** The `tests/kernel-anchor-contract.nix` check asserts
  the match count is 1; if it grows, the test fails LOUDLY

## kernel/timing-patch.nix:60 — svm_set_intercept INTERCEPT_RSM

- **Anchor:** `svm_set_intercept(svm, INTERCEPT_RSM);`
  (arch/x86/kvm/svm/svm.c, in init_vmcb)
- **Tool:** sed `/.../a\` (insert RDTSC/RDTSCP intercepts)
- **Guard:** FATAL if anchor not found
- **Counters:** Enables RDTSC/RDTSCP interception in init_vmcb
- **Breaks when:** Kernel renames INTERCEPT_RSM (very stable enum)

## kernel/timing-patch.nix:74 — svm_exit_handlers table

- **Anchor:** `static int (*const svm_exit_handlers[])` (svm.c)
- **Tool:** sed `/^static int (\*const svm_exit_handlers\[\])/i\`
  (insert stealth wrapper functions before the table)
- **Guard:** none (the wrapper functions are still inserted even
  if the table name moves; the sed becomes a no-op for the table
  registration but the new functions are defined and never called —
  silent failure)
- **Breaks when:** Kernel renames `svm_exit_handlers`. The insertion
  still happens but the function registration in the table breaks.
- **Repair:** Update the anchor; consider asserting the table name
  is in the source before sedding

## kernel/timing-patch.nix:148 — AVIC_UNACCELERATED_ACCESS entry

- **Anchor:** `[SVM_EXIT_AVIC_UNACCELERATED_ACCESS].*=.*avic_unaccelerated_access_interception`
  (svm.c, the exit-handler table)
- **Tool:** sed `/.../a\` (insert RDTSC entry after)
- **Guard:** FATAL if anchor not found
- **Counters:** Anchor for the RDTSC entry insertion in the table
- **Breaks when:** Kernel renames the AVIC handler

## kernel/timing-patch.nix:158 — RDTSCP entry in handler table

- **Anchor:** `[SVM_EXIT_RDTSCP].*=.*kvm_handle_invalid_op,` (svm.c)
- **Tool:** sed `s/[SVM_EXIT_RDTSCP].*=.*kvm_handle_invalid_op,/[SVM_EXIT_RDTSC]\t\t\t= handle_rdtscp_interception,/`
- **Guard:** FATAL if anchor not found
- **Counters:** Replaces the upstream kvm_handle_invalid_op mapping
  with our handle_rdtscp_interception
- **Breaks when:** Kernel removes the kvm_handle_invalid_op fallback
  (e.g., always uses the proper handler) — sed no-ops, our RDTSCP
  handler isn't registered, RDTSCP is no-op'd in the guest

## kernel/timing-patch.nix:182 — KVM_X86_QUIRK_FIX_HYPERCALL_INSN check

- **Anchor:** `if (!kvm_check_has_quirk(vcpu->kvm, KVM_X86_QUIRK_FIX_HYPERCALL_INSN))`
  (arch/x86/kvm/x86.c)
- **Tool:** sed `s/if (!kvm_check_has_quirk(...))/if (1)/`
- **Guard:** FATAL if anchor not found
- **Counters:** Disables KVM's hypercall instruction patching
- **Breaks when:** Kernel renames the quirk (e.g., to
  `KVM_X86_QUIRK_DISABLE_HYPERCALL_PATCH`)

---

## kernel/cpuid-patch.nix:22 — svm_vcpu_enter_exit call site

- **Anchor:** `svm_vcpu_enter_exit(vcpu, spec_ctrl_intercepted);`
  (arch/x86/kvm/svm/svm.c, the call in svm_vcpu_run)
- **Tool:** sed `/.../i\` (insert `reenter_guest_fast:` label before)
- **Guard:** FATAL if anchor not found
- **Counters:** The label for the CPUID leaf 0 override's goto
- **Breaks when:** Kernel changes the call site signature

## kernel/cpuid-patch.nix:38 — svm_vcpu_enter_exit (insertion site)

- **Anchor:** same as above (the call site)
- **Tool:** sed `/^\tsvm_vcpu_enter_exit(vcpu, spec_ctrl_intercepted);$/a\`
  (insert the CPUID override block after)
- **Guard:** FATAL if anchor not found
- **Counters:** The CPUID leaf 0 override block
- **Breaks when:** same as above

## kernel/cpuid-patch.nix:50 — svm_set_intercept INTERCEPT_RSM

- **Anchor:** `svm_set_intercept(svm, INTERCEPT_RSM);` (svm.c)
- **Tool:** sed `/.../a\` (clear RDTSC/RDTSCP intercepts)
- **Guard:** FATAL if anchor not found
- **Counters:** Clears RDTSC/RDTSCP interception (complementary to
  BetterTiming's intercept-enable)
- **Breaks when:** same as timing-patch's INTERCEPT_RSM anchor

---

## kernel/cpuid-disable.nix:47 — svm_set_intercept INTERCEPT_RSM

- **Anchor:** `svm_set_intercept(svm, INTERCEPT_RSM);` (svm.c)
- **Tool:** sed `/.../a\` (clear INTERCEPT_CPUID)
- **Guard:** FATAL if anchor not found
- **Counters:** Disables CPUID interception (CPUID passthrough)
- **Breaks when:** same INTERCEPT_RSM refactor risk

## kernel/cpuid-disable.nix:60 — pre_svm_run function definition

- **Anchor:** `static int pre_svm_run(struct kvm_vcpu *vcpu)` (svm.c)
- **Tool:** sed range `/^static int pre_svm_run(struct kvm_vcpu \*vcpu)/,/^}/` (insert INTERCEPT_CPUID clear inside)
- **Guard:** WARN (not FATAL) if anchor not found; the init_vmcb
  clear is sufficient for non-nested
- **Counters:** Belt-and-suspenders: clears INTERCEPT_CPUID on every
  VMRUN
- **Breaks when:** Kernel refactors pre_svm_run (split for big-PIC,
  renamed, etc.)

---

## Updating this catalog

When a sed is added or moved:

1. Add or update the section here
2. Add the corresponding guard in `tests/sed-contract-qemu.nix` or
   `tests/sed-contract-edk2.nix`
3. Add the corresponding awk anchor in `tests/kernel-anchor-contract.nix`
4. Run `nix flake check` — the contract test must pass with the
   new anchor against the current upstream
