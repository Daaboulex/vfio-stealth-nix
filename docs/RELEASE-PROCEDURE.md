# Stealth repo release procedure

The discipline for bumping any of the stealth repo's external
dependencies. Run through this before AND after every dep bump. A
contract test under `tests/` catches most fragility; this procedure is
what you do when a contract test fails (or when you're about to
challenge it with a dep bump).

## What this repo is

A fork-of-forks: QEMU + EDK2 + CachyOS Linux, with out-of-tree
patches (AutoVirt + BetterTiming + Hypervisor-Phantom) and our own
sed-based reversions. Every dep in the input set can move. This
procedure minimises the surface area of breakage.

## Before any dep bump

The dependencies that move are:

- `autovirt` (the AutoVirt patch content; pinned via `flake.lock`)
- `nixpkgs` (QEMU upstream; the override in `qemu/package.nix` pins
  QEMU 11.0.1 specifically, so most nixpkgs bumps are inert for
  qemu-stealth — but the QEMU version check in the override fires
  loudly if the pin is bypassed)
- `nix-cachyos-kernel` (the CachyOS LTO latest kernel; tracked
  at HEAD, so this moves continuously)
- `qemu` (the nixpkgs QEMU; the override in `qemu/package.nix` pins
  11.0.1 when the upstream isn't already 11.0.x)
- `better-timing` (BetterTiming patch content; rarely changes)

### 1. Run the contract tests

```sh
nix flake check .#checks.x86_64-linux.sed-contract-qemu
nix flake check .#checks.x86_64-linux.sed-contract-edk2
nix flake check .#checks.x86_64-linux.kernel-anchor-contract
nix flake check .#checks.x86_64-linux.lib-output-contract
nix flake check .#checks.x86_64-linux.boot-smoke
```

If any fails: fix the broken anchor (the contract test output names
it) and re-run. Do NOT proceed to the bump with a known-failing
contract test.

### 2. Read the bump's diff before committing

For `nix flake update autovirt`:

```sh
nix flake update autovirt
git diff flake.lock
```

Read the change. The AutoVirt pin moves; check that no major QEMU
file paths have shifted (the sed anchors in `qemu/post-patch.nix`
assume specific file layouts).

For `nix flake update nix-cachyos-kernel`:

```sh
nix flake update nix-cachyos-kernel
```

This is on HEAD; no specific version to inspect. The
`kernel-anchor-contract` test will fire if a CachyOS patch moves
an awk anchor.

### 3. Bump the contract test against the NEW dep first

Before committing the bump, run the contract test against the new
dep. If it fails, fix the anchors before committing the bump.

```sh
nix flake update autovirt
nix flake check .#checks.x86_64-linux.sed-contract-qemu \
              .#checks.x86_64-linux.sed-contract-edk2
# Per-sed diagnostics are printed on failure; fix in
# qemu/post-patch.nix / ovmf/package.nix + the SED-CATALOG.md
```

If the contract test passes: proceed to commit. If it fails: the
bump is bad — either revert (`nix flake update --revert-lock-file
autovirt`) or fix the anchors first.

## Bump procedure

1. `nix flake update <dep>` (autovirt, nix-cachyos-kernel, or nixpkgs)
2. `nix flake check` — all green
3. `git diff flake.lock` — confirm the bump is what you expected
4. Update `docs/SED-CATALOG.md` if any anchor moved (and the contract
   test no longer matches the old anchor in the catalog)
5. `git add flake.lock docs/SED-CATALOG.md` and commit with a
   message that names the bumped dep + the version
6. Push (the pre-push hook runs `check-behind-remote` and
   `nix-eval-check`)

## After the bump

1. Tag the release: `git tag vYYYY-MM-DD-<dep>`. The tag is
   documentation; the consumer (main nix config) pins the
   `vfio-stealth` input by rev, not by tag.
2. The consumer (main nix config) bumps its `inputs.vfio-stealth`
   rev in lockstep. The `STEALTH-CONSUMER-AUDIT-2026-06-15.md`
   doc in the main repo tracks the consumer-side audit
   follow-ups.
3. The consumer runs `nrb` to validate the new stealth rev
   evaluates.
4. Live VM boot test (the user's existing workflow):
   - `virsh start win11-amd`
   - Read `/tmp/ovmf-debug.log`, `/tmp/windows-serial.log`,
     `/tmp/qemu-guest-errors.log` (all wired in
     `parts/hosts/ryzen-9950x3d/default.nix:829-841`)
5. If the boot fails, the logs are the diagnostic starting point.
   The boot-crash suspects (handoff §3.3) are the framework.

## Rollback

If a bump introduces a regression:

1. `git revert <bump-commit>` in this stealth repo
2. `git push`
3. Bump the consumer's `inputs.vfio-stealth` back to the last-known-good
   rev
4. Open an issue / note in `docs/SED-CATALOG.md`:
   - Which dep was bumped
   - Which seds/anchors broke
   - Why (upstream moved the target)
   - What the fix would be

## How contract tests are structured

Each contract test is a `checks.<system>.<name>` derivation in
`flake.nix`. They are all wired into `nix flake check` automatically.

- `checks.sed-contract-qemu`: applies the AutoVirt QEMU patch + the
  `qemu/post-patch.nix` seds to a fresh QEMU 11.0.1 source; runs a
  per-sed grep guard after each substitution; reports per-sed
  pass/fail.
- `checks.sed-contract-edk2`: applies the filterdiff-trimmed AutoVirt
  EDK2 patch + the `ovmf/package.nix` postPatch to a fresh OVMF
  source; runs per-sed grep guards.
- `checks.kernel-anchor-contract`: extracts both the nixpkgs
  `linux_latest` source AND the CachyOS LTO latest source from
  `xddxdd/nix-cachyos-kernel`; asserts every awk anchor in
  `kernel/*.nix` exists at least once; warns (does NOT fail) if
  the match count exceeds the awk-target's safe maximum (which
  would mean a brace-variant of the anchor has appeared in the
  kernel source).
- `checks.boot-smoke`: actual QEMU + OVMF build with the patched
  sources; boots a minimal NixOS guest to multi-user target.
  This is the end-to-end smoke test; the contract tests above
  are unit-level.

## Layer 2+ roadmap (deferred)

If a real fragility surfaces that the contract tests don't catch,
the next step is a multi-version matrix (per the prior research).
Builds the stealth stack against 3 AutoVirt revs × 3 QEMU revs
× 3 kernel revs; catches version-skew bugs before the user
bumps. Cost: ~16 hours of test infra. YAGNI until proven
otherwise.

## Layer 5 (deferred)

Reproducibility + golden-baseline diff. Catches silent sed
regressions that the FATAL guards + per-sed grep guards miss.
Cost: ~16 hours. YAGNI until proven otherwise.
