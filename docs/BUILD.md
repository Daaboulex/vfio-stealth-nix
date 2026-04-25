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

The dev shell provides:

- `nil` — Nix LSP for editor integration
- `nixfmt-rfc-style` — formatter (run via `nix fmt`)
- `pre-commit` — installed git hooks running on every commit
  (eval check + format check)

## Build

```bash
nix flake check --no-build        # eval-only check (cheap, ~5 s)
nix fmt                           # format all .nix
nix build .#qemu-stealth          # patched QEMU
nix build .#ovmf-stealth          # patched EDK2/OVMF
nix build .#acpi-ssdt-stealth     # compiled ACPI SSDT tables
nix build .#smbios-extract        # host SMBIOS dump tool
nix build                         # default — builds qemu-stealth
```

Each package output produces a verifiable artifact:

| Package | Verify |
|---|---|
| `qemu-stealth` | `./result/bin/qemu-system-x86_64 --version` |
| `ovmf-stealth` | ELF + size sanity check on `OVMF_CODE.fd` |
| `acpi-ssdt-stealth` | `iasl -d ./result/spoofed-devices.aml` round-trips cleanly |
| `smbios-extract` | `./result/bin/smbios-extract --help` |

## Pre-commit hooks

Hooks are installed automatically via `nix develop` (managed by
`git-hooks.nix`):

- `treefmt` — runs `nixfmt-rfc-style` on changed `.nix` files
- `nix-flake-check` — `nix flake check --no-build` on the staged tree

A failing hook prints the exact command to reproduce. Bypassing hooks
(`--no-verify`) is **not** allowed for this repo's branch protection
ruleset — fix the violation and re-commit.

## Tests

This repo's tests are eval-level. There is no live VM smoke test (would
require KVM in CI), so the verification chain is:

```
eval check   →   build all packages   →   ELF / AML sanity   →   ldd check on qemu-stealth
```

CI wires this in `.github/workflows/ci.yml`. Each step fails the job on
non-zero exit. No "passing eval" without a clean build.

## Update contract — `scripts/update.sh`

The update workflow tracks two upstreams:

- [Scrut1ny/AutoVirt](https://github.com/Scrut1ny/AutoVirt) (QEMU AMD
  patch + EDK2 anti-detection patches)
- [SamuelTulach/BetterTiming](https://github.com/SamuelTulach/BetterTiming)
  (TSC compensation kernel patch reference)

Exit codes:

| Exit | Meaning |
|---|---|
| `0` | No update, or update succeeded — main branch advanced |
| `1` | Update found but verification chain failed → workflow opens GitHub Issue with build log + recovery branch |
| `2` | Network / API error → retry next run |

Outputs (read by the workflow):

- `updated`, `new_version`, `old_version`, `package_name`,
  `error_type`, `upstream_url`

Verification chain is identical to CI's — eval → build → binary verify
→ ldd check. **Never false-positive**: every step must pass before
push to `main`.

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| `nix build` fails with `cannot resolve goto reenter_guest_fast` | Kernel newer than the patch target | Pin kernel to a tested version (currently 6.19.x) or update `kernel/cpuid-patch.nix` to match the new symbol name |
| Eval error: `option myModules.vfio.stealth.kernel.timing.enable already declared` | Loaded both this flake's module and an outdated copy from another flake | Drop the duplicate `imports` entry — only one stealth module per system |
| `iasl` complains about ACPI SSDT compilation in `acpi-ssdt-stealth` | Outdated `iasl` (older than 20240927) | Bump nixpkgs input or `inputs.nixpkgs.follows = "nixpkgs";` to use the host's nixpkgs |
| Guest still detected as VM despite `myModules.vfio.stealth.enable = true` | One of the kernel patches not applied | Confirm `boot.kernelPackages` is wired to a kernel built with `_kernelPostPatch` appended (see README §Kernel Integration) |
| `services.virtualisation.vms.<vm>` rewrites missing `kvm-hidden` | `lib.nix` rewriter not applied | The module hooks into NixVirt; ensure `services.virtualisation.libvirt.swtpm.enable = true` and the VM is declared via NixVirt, not raw libvirt XML |
| FACEIT / TPM-attesting anti-cheat still rejects | Software spoofing cannot defeat hardware-rooted attestation | See README §Known Limitations — there is no software-only fix |

For other issues, attach the failing nix log + the relevant module
config snippet to a GitHub Issue.
