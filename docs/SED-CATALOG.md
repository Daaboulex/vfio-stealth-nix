# Sed / awk / anchor catalog

Single source of truth for every text-replacement anchor in the stealth
patch stack. When an upstream bump (AutoVirt, QEMU, EDK2, CachyOS) moves
a target, this file is the index a future maintainer uses to find the
broken anchor and fix it.

The contract tests under `tests/` verify each anchor on every build of
the stealth repo. A red `nix flake check` from one of those tests is the
first signal that an anchor has moved.

## The ordinary case needs no entry here

Nearly every substitution below the surface is the same shape: upstream renames
a default string, the anchor stops matching, and `sed-contract-qemu` or
`sed-contract-edk2` goes red on the next build because they run the real
`post-patch.nix` against the real source. The repair is to update the anchor in
that file. That case is not catalogued, because thirty copies of one sentence
is a file nobody rereads and everybody has to keep in step.

What IS catalogued below is the minority that will mislead you: an anchor that
another patch set also writes, one whose match is broader than it looks, or one
whose current value exists for a reason a diff will not tell you.

Anchors, replacements, tools and guards are deliberately absent. `post-patch.nix`
owns those, and `checks.sed-catalog-lean` fails if they reappear here.

---

## qemu/post-patch.nix — EDID manufacturer

- **Counters:** Stealth repo identity; not an AutoVirt counter
- **Breaks when:** QEMU renames the default EDID manufacturer
- **Repair:** Update the anchor to match the new QEMU default

## qemu/post-patch.nix — ACPI OEM ID

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

- **Counters:** AutoVirt SETS this (replaces `"BXPC    "`)
- **Breaks when:** AutoVirt changes the table ID for a vendor
- **Repair:** Update `traits.<vendor>.patchedOemTableId` in
  `lib/autovirt-patches.nix`

## qemu/post-patch.nix -- aml_string format-security workaround

- **Counters:** Not a stealth counter -- a build fix. `aml_string` is
  `G_GNUC_PRINTF(1,2)`, and AutoVirt's `_OSI` loop passes a variable as
  the format, which nixpkgs' `-Werror=format-security` rejects
- **Breaks when:** AutoVirt fixes it upstream (the sed no-ops, the absence
  grep still passes) or renames the loop variable (the compiler then fails
  loudly, which is the real backstop). See AutoVirt issue #169
- **Repair:** Drop this block once upstream carries the fix

## qemu/post-patch.nix -- ICH9 LPC bridge placement

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

- **Counters:** AutoVirt SETS this (replaces `"QEMU HARDDISK"`)
- **Breaks when:** AutoVirt changes the default IDE disk model
- **Repair:** Update the anchor to match AutoVirt's new value

## qemu/post-patch.nix — IDE drive serial

- **Counters:** AutoVirt SETS this (replaces the previous snprintf with
  an empty-string fallback)
- **Breaks when:** AutoVirt changes the empty-string approach (e.g., to
  `memset(..., 0, sizeof(...))`)
- **Repair:** Update the anchor + re-derive the sed's backslash escapes

## qemu/post-patch.nix — MCH host-bridge device ID

- **Counters:** AutoVirt SETS this (0x29c0 → 0x14d8); OVMF's
  Q35 PEI init requires the real Intel Q35 ID
- **Breaks when:** AutoVirt changes the macro (e.g., renames
  `PCI_DEVICE_ID_INTEL_P35_MCH` to `PCI_DEVICE_ID_Q35_MCH`); the sed's
  `.*$` greedy match would still match the new name, but the FATAL guard
  checks for the literal `PCI_DEVICE_ID_INTEL_P35_MCH` substring which
  would fail
- **Repair:** Update the anchor + the FATAL guard

## qemu/post-patch.nix — MCH host-bridge vendor (declarative)

- **Counters:** AutoVirt SETS this; OVMF + QEMU on a real Q35 machine
  must agree on the vendor
- **Breaks when:** AutoVirt changes the anchor text (e.g., the class
  function changes) OR moves the host bridge to a different directory
- **Repair:** Update the grep pattern; the FATAL is loud so this
  fails LOUDLY

## ovmf/post-patch.nix — Firmware vendor string

- **Counters:** Stealth identity
- **Breaks when:** AutoVirt moves the PCD declaration to a different
  .dec file; the sed misses the new file
- **Repair:** Update the file list in the sed; consider scoping
  the guard to a glob that catches the new file

## ovmf/post-patch.nix — BGRT module strip (DSC)

- **Counters:** VMAware CRC identifier 0x110350C5
- **Breaks when:** AutoVirt renames the BGRT module; the sed no-ops
  silently. The guard catches this (string still present = fail)
- **Repair:** Update the anchor to the new module name

## ovmf/post-patch.nix — BGRT module strip (FDF)

- **Breaks when:** Same as DSC strip

## ovmf/package.nix — AutoVirt BaseTools hunk filter

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
