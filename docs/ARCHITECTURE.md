# vfio-stealth-nix — Architecture

Companion to the top-level [README](../README.md). Covers directory
layout, which file owns which option group, and how the kernel
integration is layered.

## Directory layout

- [`flake.nix`](../flake.nix): the packages, `overlays.default`, `nixosModules.default`, `lib` and the checks.
- [`module.nix`](../module.nix): the `virtualisation.vfio-stealth.*` options, the assertions and warnings, the kernel parameters, and the two read-only patch scripts.
- [`lib.nix`](../lib.nix): `mkStealthFeatures`, the one function `lib` exports. It returns the libvirt and QEMU fragments for one VM.
- [`lib/`](../lib): the AutoVirt patch resolver, the QEMU base selection and the kernel capability parser. The packages and `mkStealthFeatures` import these files; none is a flake output.
- [`version.json`](../version.json): the AutoVirt revision the vendored patches came from and the BetterTiming commit the timing patch was ported from.
- [`qemu/`](../qemu): `qemu-stealth`, its arguments and its post-patch script.
- [`ovmf/`](../ovmf): `ovmf-stealth` and its post-patch script.
- [`acpi/`](../acpi): the three SSDT sources and `acpi-ssdt-stealth`, which compiles them.
- [`kernel/`](../kernel): the three kernel patch scripts and their shared prelude, joined into `kernelPostPatch`.
- [`smbios/`](../smbios): `smbios-extract` and `smbios-stealth-tables`.
- [`detect/`](../detect): `stealth-detect`, the per-vector detector for a Linux guest.
- [`guest/`](../guest): the two scripts run inside the Windows guest and the host-side check.
- [`tests/`](../tests): the contract checks, wired in as flake checks.
- [`scripts/update.sh`](../scripts/update.sh): watches the upstreams and exits non-zero so an issue is filed.
- [`vendor/autovirt/`](../vendor/autovirt): the vendored AutoVirt patches, with their own licence file and README.
- [`.github/`](../.github): the three workflows and `update.json`.

## Architecture support

The flake declares both canonical arches. Both build `stealth-detect` and run
`detect-fixture-contract`. Every other package and check this flake defines is
declared on one arch only, because the two stacks share no patch surface.

`x86_64-linux` carries the whole stealth stack: `qemu-stealth`, `ovmf-stealth`,
`acpi-ssdt-stealth`, the SMBIOS packages, the [`kernel/`](../kernel) SVM patches and every
sed contract. All of it is pinned there by `meta.platforms`, because the AutoVirt
QEMU patches target `hw/i386/`, `hw/isa/lpc_ich9.c` and `hw/ide/`, the EDK2
patches target `OvmfPkg/OvmfPkgX64.{dsc,fdf}` (on aarch64 `pkgs.OVMF` is
ArmVirtQemu, `AAVMF_CODE.fd`), and [`kernel/`](../kernel) edits `arch/x86/kvm/svm/svm.c`,
which has no ARM counterpart.

`aarch64-linux` carries the oracle only: `stealth-detect`, the
`detect-finds-plain-virt` check that boots an ARM guest and requires the detector to
find it, and `detect-fixture-contract`, which drives the detector over fixture trees
so the ACPI vectors a directly-booted guest cannot expose are still covered.
Nothing is spoofed on ARM yet, deliberately: on this architecture the
CPU identity registers (`MIDR_EL1`, `REVIDR_EL1`, `AIDR_EL1` and the writable
`ID_AA64*` fields) are set from userspace through `KVM_SET_ONE_REG`, so the x86
approach of patching KVM does not apply, and a spoof with no detector to fail
against cannot be verified.

CI runs a native runner per arch and builds whatever that arch declares, so each
half is proved on its own hardware. The GitHub arm runner has no `/dev/kvm`, so
it proves the emulated-identity half under TCG; the `KVM_SET_ONE_REG` half needs
a machine with KVM.

## Component → option-group ownership

| Component | Option prefix | Detection vectors covered |
|---|---|---|
| `qemu-stealth` ([`qemu/package.nix`](../qemu/package.nix)) | build-time args (`edid*`, `disk*`, `optical*`, `acpiOem*`) — overlay or `callPackage` | EDID display identity, disk/optical model strings, disk serial, ACPI OEM IDs, fw_cfg DMA signature + ACPI device removal |
| `ovmf-stealth` ([`ovmf/package.nix`](../ovmf/package.nix)) | inherited via overlay — no module options | OVMF SMBIOS Type 0 (VirtualMachine bit), Red Hat PCI vendor IDs (1AF4/1B36→1022, 1234→1002), ACPI OEM fields, BGRT table (TianoCore CRC identifier) |
| [`module.nix`](../module.nix) `smbios.*` | `virtualisation.vfio-stealth.smbios.*` | SMBIOS Types 1, 2, 4, 7, 8, 9, 11, 17, 26, 27, 28, 29, 41 (system, baseboard incl. version/serial/asset/location, processor, cache, port connector, system slots, OEM strings, memory, voltage/cooling/temperature/current probes, onboard devices) |
| [`module.nix`](../module.nix) `acpiSsdt.*` | `virtualisation.vfio-stealth.acpiSsdt.*` | ACPI SSDT (fan, thermal zone with fluctuation, battery, buttons, AC adapter, timers) |
| [`module.nix`](../module.nix) `timing`, `cpuidSpoof`, `cpuidPassthrough` | `virtualisation.vfio-stealth.{timing,cpuidSpoof,cpuidPassthrough}.*` | RDTSC/RDTSCP timing, CPUID vendor string + hypervisor bit, CPUID execution timing, KVM hypercall instruction patching (disabled by the timing patch) |
| [`module.nix`](../module.nix) `kernelParams.*` | `virtualisation.vfio-stealth.kernelParams.{maxCState,tscReliable}` | TSC stability, TSC source selection, SVM params (kvm_amd.vls=0, kvm_amd.vgif=0) |
| [`module.nix`](../module.nix) `aperfMperf` | `virtualisation.vfio-stealth.aperfMperf` | IA32_APERF/MPERF MSR passthrough (covers IET) |
| [`module.nix`](../module.nix) `stripVirtio` / `spoofMac` / `macPrefix` | top-level toggles | `stripVirtio` yields `devicesToRemove` (VirtIO PCI vendor ID) once the caller passes it to `mkStealthFeatures`. `spoofMac` and `macPrefix` (default `D8:BB:C1`) are declared and read by no code in this flake |
| [`lib.nix`](../lib.nix) `mkStealthFeatures` | the function's arguments; the caller places the result in its VM definition | `kvm.hidden`, hypervisor bit cleared in hidden mode, Hyper-V features and vendor_id override, clock timers (HPET present), SMBIOS and ACPI table arguments, `-cpu` flags (`kvm-pv-enforce-cpuid`, off by default) |
| `acpi/*.dsl` | compiled AML embedded in `acpi-ssdt-stealth` | ACPI SSDT runtime indicators |
| `smbios-extract` ([`smbios/package.nix`](../smbios/package.nix)) | CLI tool, not a module option | Host SMBIOS dump for VM identity customization |
| `smbios-stealth-tables` ([`smbios/tables-package.nix`](../smbios/tables-package.nix)) | build-time args (`cacheL1`, `cacheL2`, `cacheL3`) | SMBIOS Types 7, 26, 27, 28, 29 (cache, probes — binary injection via `-smbios file=`) |

## Kernel-integration layering

The module exposes `virtualisation.vfio-stealth.kernelPostPatch` -- a shell
script string meant to be appended to `linux*.kernel.overrideAttrs`'s
`postPatch`. Three composable patch sets target the KVM/SVM subsystem.
See README "What the patches do" for the detailed breakdown of each patch.

1. **BetterTiming** ([`kernel/timing-patch.nix`](../kernel/timing-patch.nix)) -- TSC compensation + hypercall #UD injection
2. **CPUID emulation** ([`kernel/cpuid-patch.nix`](../kernel/cpuid-patch.nix)) -- Hypervisor-Phantom leaf 0 override without full VM exit
3. **CPUID passthrough** ([`kernel/cpuid-disable.nix`](../kernel/cpuid-disable.nix)) -- exit-less CPUID, guest runs at native hardware speed

Patches target function names and symbol names, not line numbers or
argument names, for resilience across kernel versions. Every edit verifies
its own effect, and `checks.kernel-postpatch-fits-cachyos` /
`checks.kernel-postpatch-fits-upstream` run the real scripts against the
CachyOS and nixpkgs-latest kernel sources in CI.
See README §Kernel Integration for the wiring snippets
(CachyOS + stock kernel variants).

## Detection-vector catalogue

The full table of detection vectors covered + the file that handles each
lives in the README's "Detection Vectors Covered" section. It is the
canonical surface listing — do not duplicate it here. This document
covers ownership, layering, and directory layout only.
