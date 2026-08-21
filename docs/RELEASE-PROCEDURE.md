# Stealth repo release procedure

The discipline for bumping any of the stealth repo's external
dependencies. Run through this before AND after every dep bump. A
contract test under `tests/` catches most fragility; this procedure is
what you do when a contract test fails (or when you're about to
challenge it with a dep bump).

## What this repo is

A fork-of-forks: QEMU + EDK2 + CachyOS Linux, with out-of-tree
patches (AutoVirt, upstream deleted ~2026-05, its patches vendored
in `vendor/autovirt/`, plus Hypervisor-Phantom and a hand-ported
BetterTiming) and our own sed-based reversions. Every dep in the
input set can move. This procedure minimises the surface area of
breakage.

## The QEMU floor and ceiling

The vendored patch inventory `vendor/autovirt/patches/QEMU/` is the
single source of truth. `qemu/package.nix` derives the newest patched
series per CPU vendor from it and picks the QEMU base:

- nixpkgs' QEMU when it is within the patched series;
- the newest patched series, built from a `download.qemu.org`
  tarball, when nixpkgs' QEMU is newer (the ceiling);
- the `minimumVersion` floor tarball when nixpkgs' QEMU is older.

So a nixpkgs bump past the patched series never breaks the build: the
host and CI stay green, at the ceiling, until a newer patch is
vendored -- and the day one is, the ceiling rises with no code
change. Eval fails closed if a patched series has no tarball hash in
`qemu/package.nix`, if the ceiling falls below the floor, or if a
vendor has no patches at all.

## Before any dep bump

The dependencies that move are:

- `nixpkgs` (QEMU upstream; governed by the ceiling above)
- `nix-cachyos-kernel` (the CachyOS LTO latest kernel; tracked
  at HEAD, so this moves continuously)
- `std` (nix-packaging-standard; adopt via `nix flake update std`)

`kernel/timing-patch.nix` is a hand-port of BetterTiming, not a flake
input. `version.json` records the upstream commit it was ported from and
`scripts/update.sh` warns when upstream moves past it.

### 1. Run the contract tests

```sh
nix flake check .#checks.x86_64-linux.sed-contract-qemu
nix flake check .#checks.x86_64-linux.sed-contract-edk2
nix flake check .#checks.x86_64-linux.autovirt-patch-contract
nix flake check .#checks.x86_64-linux.qemu-ceiling-contract
nix flake check .#checks.x86_64-linux.kernel-postpatch-fits-cachyos
nix flake check .#checks.x86_64-linux.kernel-postpatch-fits-upstream
nix flake check .#checks.x86_64-linux.lib-output-contract
nix flake check .#checks.x86_64-linux.boot-smoke
```

If any fails: fix the broken anchor (the contract test output names
it) and re-run. Do NOT proceed to the bump with a known-failing
contract test.

### 2. Read the bump's diff before committing

For `nix flake update nixpkgs`:

```sh
nix flake update nixpkgs
git diff flake.lock
```

Read the change. Check the QEMU version the new nixpkgs carries and
what the ceiling does with it. Check that no major QEMU file paths
have shifted (the sed anchors in `qemu/post-patch.nix` assume
specific file layouts).

For `nix flake update nix-cachyos-kernel`:

```sh
nix flake update nix-cachyos-kernel
```

This is on HEAD; no specific version to inspect. The
`kernel-postpatch-fits-cachyos` check will fire if a CachyOS or upstream
change moves an anchor the patch scripts edit.

### 3. Bump the contract test against the NEW dep first

Before committing the bump, run the contract test against the new
dep. If it fails, fix the anchors before committing the bump.

```sh
nix flake update nixpkgs
nix flake check .#checks.x86_64-linux.sed-contract-qemu \
              .#checks.x86_64-linux.sed-contract-edk2 \
              .#checks.x86_64-linux.qemu-ceiling-contract
# Per-sed diagnostics are printed on failure; fix in
# qemu/post-patch.nix / ovmf/package.nix + the SED-CATALOG.md
```

If the contract test passes: proceed to commit. If it fails: the
bump is bad -- either revert (`nix flake update --revert-lock-file
nixpkgs`) or fix the anchors first.

## Adopting a newer AutoVirt patch

`scripts/update.sh` watches the live AutoVirt forks daily and
nixpkgs-unstable's QEMU version. A fork patch newer than what we
vendor exits 1 with `manual-port-needed`, and a nixpkgs QEMU series no
vendored patch covers exits 1 with `patch-gap` -- either way the
canonical update workflow files a deduplicated issue that closes
itself on the next green run. Adoption is always a hand decision:

1. Review the patch by hand -- it comes from a third-party fork,
   never auto-adopted.
2. Copy it into `vendor/autovirt/patches/QEMU/` keeping the
   `AMD-v<series>.patch` / `Intel-v<series>.patch` name. If it needs
   hand-porting to a series it does not natively patch, port it
   first and keep the vendored filename honest to the series it
   actually applies to.
3. Add the tarball hash for that series to `qemu/package.nix` if
   nixpkgs may ever move past it:
   `nix-prefetch-url https://download.qemu.org/qemu-<version>.tar.xz`
   then `nix hash convert --hash-algo sha256 --to sri`.
4. Run the contract tests and `boot-smoke`. The ceiling rises on its
   own once the patch and the hash are in place.
5. Update the provenance in `version.json` (`.autovirt` rev) to the
   commit the patch was taken from.
6. Commit and push; the update workflow's open issue closes on the
   next green run.

## Bump procedure

1. `nix flake update <dep>` (nixpkgs, nix-cachyos-kernel, or std)
2. `nix flake check` -- all green
3. `git diff flake.lock` -- confirm the bump is what you expected
4. Update `docs/SED-CATALOG.md` if any anchor moved (and the contract
   test no longer matches the old anchor in the catalog)
5. `git add flake.lock docs/SED-CATALOG.md` and commit with a
   message that names the bumped dep + the version
6. Push. The pre-commit hooks (nixfmt, typos, rumdl,
   check-readme-sections, shfmt) run on commit; there are no
   pre-push hooks.

## After the bump

1. Tag the release: `git tag vYYYY-MM-DD-<dep>`. The tag is
   documentation; the consumer (main nix config) pins the
   `vfio-stealth` input by rev, not by tag.
2. The consumer (main nix config) bumps its `inputs.vfio-stealth`
   rev in lockstep.
3. The consumer runs `nrb` to validate the new stealth rev
   evaluates.
4. Live VM boot test (the user's existing workflow):
   - `virsh start win11-amd`
   - Read `/tmp/ovmf-debug.log`, `/tmp/windows-serial.log`,
     `/tmp/qemu-guest-errors.log` (all wired in
     `parts/hosts/ryzen-9950x3d/default.nix`)
5. If the boot fails, the logs are the diagnostic starting point.

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
  `qemu/post-patch.nix` seds to the QEMU source the package actually
  builds, with the same nixpkgs patches; runs a per-sed grep guard after
  each substitution; reports per-sed pass/fail. Instantiated per vendor
  as `sed-contract-qemu` and `sed-contract-qemu-intel`.
- `checks.sed-contract-edk2`: applies the filterdiff-trimmed AutoVirt
  EDK2 patch + the `ovmf/package.nix` postPatch to a fresh OVMF
  source; runs per-sed grep guards.
- `checks.autovirt-patch-contract`: pins the vendor-inventory
  resolver -- newest patch per vendor by version order, not string
  order; unknown vendor and a QEMU outside the patched series fail
  closed; `qemuSeries` lists the patched series per vendor.
- `checks.qemu-ceiling-contract`: pins the floor/ceiling base
  selection -- pass-through inside the band, the ceiling tarball
  outside it or for an in-band unpatched series, the floor tarball
  below the floor, and fail-closed on a missing hash, a ceiling below
  the floor, or an unpatched floor series.
- `checks.update-gap-contract`: pins the patch-gap probe in
  `scripts/update.sh` -- which QEMU versions count as covered by the
  vendored AMD series and which count as a gap.
- `checks.kernel-postpatch-fits-cachyos` and
  `checks.kernel-postpatch-fits-upstream`: unpack the CachyOS LTO latest
  source from `xddxdd/nix-cachyos-kernel` and the nixpkgs `linux_latest`
  source, then RUN the real `kernel/*.nix` scripts against them, once per
  enable-combination. Each script verifies every edit it makes, so an
  anchor that moved fails the check by name instead of silently applying
  nothing. Both fail-closed; neither prints a failure and then passes.
- `checks.boot-smoke`: actual QEMU + OVMF build with the patched
  sources; boots a minimal NixOS guest to multi-user target.
  This is the end-to-end smoke test; the contract tests above
  are unit-level.

## Layer 2+ roadmap (deferred)

If a real fragility surfaces that the contract tests don't catch,
the next step is a multi-version matrix (per the prior research).
Builds the stealth stack against 3 vendored patch sets x 3 QEMU
revs x 3 kernel revs; catches version-skew bugs before the user
bumps. Cost: ~16 hours of test infra. YAGNI until proven
otherwise.

## Layer 5 (deferred)

Reproducibility + golden-baseline diff. Catches silent sed
regressions that the FATAL guards + per-sed grep guards miss.
Cost: ~16 hours. YAGNI until proven otherwise.
