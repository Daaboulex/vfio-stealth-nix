# vfio-stealth-nix — Build & Operator Reference

Companion to the top-level [README](../README.md). README §Quick Start
covers the user-facing flake-input + module-import path. This doc
covers the developer / operator commands beyond that — dev shell,
formatters, hooks, tests, the update contract, and common
troubleshooting.

## Dev shell

```bash
git clone https://github.com/Daaboulex/vfio-stealth-nix
cd vfio-stealth-nix
nix develop                       # enter dev shell, installs pre-commit hooks
```

The dev shell is the one `flakeModules.base` in nix-packaging-standard defines.
It includes `nil`, a Nix language server for editor integration.

## Build

```bash
nix flake check --no-build        # eval-only check
nix fmt                           # format all .nix
nix build .#default               # patched QEMU (qemu-stealth)
nix build .#ovmf-stealth          # patched EDK2/OVMF
nix build .#acpi-ssdt-stealth     # compiled ACPI SSDT tables
nix build .#smbios-extract        # host SMBIOS dump tool
nix build                         # default — builds qemu-stealth
```

On `aarch64-linux` the flake declares only `stealth-detect`, which `x86_64-linux`
builds too, because the stealth stack is x86-only (see
[`ARCHITECTURE.md`](ARCHITECTURE.md), Architecture support):

```bash
nix build .#stealth-detect  # the detection oracle
```

Each package output produces a verifiable artifact:

| Package | Verify |
|---|---|
| `qemu-stealth` | `./result/bin/qemu-system-x86_64 --version` |
| `ovmf-stealth` | The check `ovmf-sb-vars-exists` requires `FV/OVMF_VARS.ms.fd` in the `fd` output |
| `acpi-ssdt-stealth` | `iasl -d ./result/share/acpi/spoofed-devices.aml` |
| `smbios-extract` | `sudo ./result/bin/smbios-extract <output-path>` needs root and writes the host's SMBIOS dump to the given path, `smbios.bin` when none is given |
| `smbios-stealth-tables` | `python3 generate-tables.py --verify` (runs during build) |

## Pre-commit hooks

`nix develop` installs them. The set is not listed here: it comes from
`flakeModules.base` in nix-packaging-standard, so any list in this file would
be a second copy that drifts. Run the hooks to see the current set:

```sh
nix build .#checks.x86_64-linux.pre-commit --print-build-logs
```

A failing hook prints the exact command to reproduce.

## Tests

Each arch has its own chain, and CI runs a native runner for each, so whichever
outputs an arch declares are the ones it proves. CI evaluates every declared
system, then builds every check that system declares. The packages are checks
too, so that step builds them.

- `x86_64-linux`: the packages, the sed, patch, ceiling, update-gap and lib
  output contracts, the kernel post-patch checks, `ovmf-sb-vars-exists`,
  `detect-fixture-contract` and the `boot-smoke` NixOS tests.
- `aarch64-linux`: the detector, `detect-fixture-contract` and the
  `detect-finds-plain-virt` NixOS test.

The `boot-smoke` check (`checks.boot-smoke`) boots a NixOS VM with
qemu-stealth + ovmf-stealth (secureBoot=false, stealth patches present)
and waits for `multi-user.target`. This catches QEMU/OVMF
regressions that cause firmware hangs (e.g., the QEMU 10.2.2 OVMF hang).
Secure Boot is disabled because the NixOS test kernel is unsigned. It keeps the
`kvm` system feature nixpkgs puts on a VM test, so it needs a builder exposing
`/dev/kvm`; GitHub's x86 runners do.

It then runs `stealth-detect` inside that guest and requires two of the rewrites
[`qemu/post-patch.nix`](../qemu/post-patch.nix) performs to be visible from in there: ACPI tables carrying
the configured OEM id rather than `BOCHS`/`BXPC`, and PCI subsystem ids that are
not QEMU's `0x1af4:0x1100`. The sed contracts prove an edit landed in QEMU's
source; this is what proves the result reached a booted guest.

The SMBIOS rewrites are deliberately not asserted here, and cannot be. The
nixpkgs kernel builds with `CONFIG_DMIID=n` and `CONFIG_DMI_SYSFS=n`, so
`/sys/class/dmi/id` does not exist in a NixOS guest and `dmi-identity` reports
`unknown` rather than `clean`. Covering SMBIOS from inside a guest needs either a
kernel rebuilt with those options or a distro guest that ships them;
[`guest/verify-stealth.ps1`](../guest/verify-stealth.ps1) covers it on the Windows side instead.

`acpi-hypervisor-id` is likewise not asserted here. That guest's FADT is
revision 3, which predates the ACPI 6.0 Hypervisor Vendor Identity field, so the
vector reports `unknown` rather than reading anything. It is the strongest tell
on the `virt` machine, whose FADT is revision 6, and effectively an ARM-only
vector in this repo. `detect-fixture-contract` is what exercises it, in all
three states.

The `detect-finds-plain-virt` check (`checks.aarch64-linux.detect-finds-plain-virt`)
boots a plain aarch64 NixOS guest and requires `stealth-detect` to exit 1 with
`dt-machine-compatible`, `dt-psci-conduit` and `virtio-bus` firing. A detector that
goes quiet on unmodified QEMU could not prove a spoof, so this check is what keeps it
honest. It drops the `kvm` system feature, because GitHub's aarch64 runners expose no
`/dev/kvm` and Nix refuses such a derivation outright rather than falling back. QEMU
is launched with `accel=kvm:tcg`, so it uses KVM on a machine that has it and TCG on
one that does not.

The `detect-fixture-contract` check drives the same detector over built-in fixture
trees instead of a VM. It is what covers `acpi-hypervisor-id` and `acpi-oem`, which a
directly-booted guest exposes no ACPI for, and it needs neither KVM nor a VM.

CI wires this in [`.github/workflows/ci.yml`](../.github/workflows/ci.yml). Each step fails the job on
non-zero exit. No "passing eval" without a clean build and a booting VM.

## Update contract

[`scripts/update.sh`](../scripts/update.sh) changes no file in the repository
and pushes nothing. It watches the upstreams and reports through its exit
code. Adopting a change is a hand decision, described in
[`RELEASE-PROCEDURE.md`](RELEASE-PROCEDURE.md). It watches:

- [Scrut1ny/AutoVirt](https://github.com/Scrut1ny/AutoVirt) and the forks
  the script lists, for a QEMU patch newer than the vendored one.
- nixpkgs-unstable and QEMU's release tags, for a QEMU series no vendored
  patch covers.
- [SamuelTulach/BetterTiming](https://github.com/SamuelTulach/BetterTiming),
  for a commit past the one [`version.json`](../version.json) records.
- QEMU's ARM KVM backend, for the capability that would make an aarch64
  guest's CPU identity settable.

It builds in one case. When the newest QEMU is in a series a vendor has no
patch for, the probe stage builds that QEMU with the vendor's newest patch,
then its sed contract and its boot-smoke guest.

Exit codes:

| Exit | Meaning |
|---|---|
| `0` | Nothing to do |
| `1` | Something needs a hand decision. `error_type` says which, and the update workflow files an issue |
| `2` | A transient network failure. The next run checks again |

Outputs (read by the workflow):

- `package_name`, `old_version` and `updated`, which is always `false`.
- `error_type`, on every exit 1.
- `new_version` and `upstream_url`, when a newer AutoVirt patch or an
  uncovered QEMU version was found.

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| `nix build` fails with `cannot resolve goto reenter_guest_fast` | Kernel newer than the patch target | Run `nix build .#checks.x86_64-linux.kernel-postpatch-fits-cachyos`; it names the edit that no longer lands. Re-aim that edit in `kernel/*.nix` |
| Eval error: `option virtualisation.vfio-stealth.timing.enable already declared` | Loaded both this flake's module and an outdated copy from another flake | Drop the duplicate `imports` entry — only one stealth module per system |
| `iasl` complains about ACPI SSDT compilation in `acpi-ssdt-stealth` | Outdated `iasl` | Bump nixpkgs input or `inputs.nixpkgs.follows = "nixpkgs";` to use the host's nixpkgs |
| Guest still detected as VM despite `virtualisation.vfio-stealth.enable = true` | One of the kernel patches not applied | Confirm `boot.kernelPackages` is wired to a kernel built with `kernelPostPatch` appended (see README §Kernel Integration) |
| The guest's libvirt domain lacks `kvm.hidden` and the other fragments | The caller did not place the `lib.mkStealthFeatures` result in its VM definition | The module defines no VM. Call `lib.mkStealthFeatures` and put `features`, `cpuFeatures`, `clock`, `sysinfo` and `qemuArgs` into the VM definition (see README §Quick Start) |
| TPM-attesting detection software still rejects | Software emulation cannot address hardware-rooted attestation | See README §Known Limitations -- there is no software-only fix |

For other issues, attach the failing nix log + the relevant module
config snippet to a GitHub Issue.
