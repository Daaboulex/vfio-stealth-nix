# vfio-stealth-nix — Architecture

Companion to the top-level [README](../README.md). Covers directory
layout, which file owns which option group, and how the kernel
integration is layered.

## Directory layout

```
vfio-stealth-nix/
├── flake.nix                # packages, overlays.default, nixosModules.default
├── module.nix               # myModules.vfio.stealth.* options + assertions
├── lib.nix                  # libvirt domain rewriter (NixVirt int typing,
│                            # vendor_id, kvm-hidden, fake-battery wiring)
├── qemu/
│   └── package.nix          # qemu-stealth — patched QEMU + AutoVirt patches
│                            # + EDID + ACPI OEM + disk/optical model overrides
├── ovmf/
│   └── package.nix          # ovmf-stealth — patched EDK2/OVMF firmware,
│                            # SMBIOS Type 0 VirtualMachine bit cleared,
│                            # Red Hat PCI vendor IDs replaced
├── acpi/
│   ├── spoofed-devices.dsl  # ACPI SSDT: fake EC, fan, thermal zone,
│   │                        # power/sleep buttons, timers
│   └── fake-battery.dsl     # Control Method Battery (PNP0C0A)
├── kernel/
│   ├── timing-patch.nix     # BetterTiming TSC compensation
│   │                        # → exposed via _kernelPostPatch
│   └── cpuid-patch.nix      # Hypervisor-Phantom CPUID leaf 0 spoof
│                            # → exposed via _kernelPostPatch
├── smbios/
│   └── extract-tool.nix     # smbios-extract — host SMBIOS dump +
│                            # anonymization helper
├── guest/
│   └── windows-tools/       # PowerShell scripts for guest-side cleanup
├── scripts/
│   └── update.sh            # AutoVirt + BetterTiming flake-input bumper
├── .github/
│   ├── workflows/{ci,update,maintenance}.yml
│   ├── update.json
│   └── dependabot.yml
├── flake.nix
├── README.md
├── docs/                    # this folder
├── LICENSE
└── SECURITY.md
```

## Component → option-group ownership

| Component | Option prefix | Detection vectors covered |
|---|---|---|
| `qemu-stealth` (qemu/package.nix) | build-time args (`edid*`, `disk*`, `optical*`, `acpiOem*`) — overlay or `callPackage` | EDID display identity, disk/optical model strings, ACPI OEM IDs |
| `ovmf-stealth` (ovmf/package.nix) | inherited via overlay — no module options | OVMF SMBIOS Type 0 (VirtualMachine bit), Red Hat PCI vendor IDs, ACPI OEM fields |
| `module.nix` `smbios.*` | `myModules.vfio.stealth.smbios.*` | SMBIOS Types 1, 2, 4, 17 (system, baseboard, processor, memory) |
| `module.nix` `acpiSsdt.*` | `myModules.vfio.stealth.acpiSsdt.*` | ACPI SSDT (EC, fan, thermal, battery, buttons, timers) |
| `module.nix` `kernel.*` (timing + cpuidSpoof) | `myModules.vfio.stealth.kernel.{timing,cpuidSpoof}.*` | RDTSC/RDTSCP timing, CPUID vendor string + hypervisor bit |
| `module.nix` `kernelParams.*` | `myModules.vfio.stealth.kernelParams.{maxCState,tscReliable}` | TSC stability, TSC source selection |
| `module.nix` `aperfMperf` | `myModules.vfio.stealth.aperfMperf` | IA32_APERF/MPERF MSR passthrough (defeats IET) |
| `module.nix` `stripVirtio` / `spoofMac` / `macPrefix` | top-level toggles | VirtIO PCI vendor ID, MAC OUI |
| `lib.nix` (libvirt rewriter) | applied to `services.virtualisation.vms.<name>` | KVM hidden bit, Hyper-V vendor_id spoof, fake-battery wiring |
| `acpi/*.dsl` | compiled AML embedded in `acpi-ssdt-stealth` | ACPI SSDT runtime fingerprints |
| `smbios-extract` (smbios/extract-tool.nix) | CLI tool, not a module option | Host SMBIOS dump for VM injection |

## Kernel-integration layering

The module exposes `myModules.vfio.stealth._kernelPostPatch` — a shell
script string that patches kernel sources via `sed`/`awk`. It is meant
to be appended to `linux*.kernel.overrideAttrs`'s `postPatch`. Two
separate patch sets compose into this single hook:

1. **BetterTiming** (`kernel/timing-patch.nix`) — TSC compensation
   - Adds `last_exit_start` and `total_exit_time` fields to `struct kvm_vcpu`
   - Wraps `vcpu_enter_guest` to measure VM-exit duration
   - Patches `MSR_IA32_TSC` reads to return compensated values
   - Enables RDTSC interception in SVM `init_vmcb`
   - Adds `handle_rdtsc_interception` returning compensated TSC
   - Wraps CPUID, WBINVD, XSETBV, INVD exit handlers to tag
     `exit_reason=123` for timing compensation

2. **CPUID spoofing** (`kernel/cpuid-patch.nix`) — Hypervisor-Phantom
   - Intercepts CPUID leaf 0 inside `svm_vcpu_run` after
     `svm_vcpu_enter_exit` returns
   - Spoofs vendor string to `AuthenticAMD` with max leaf `0x16`
   - Advances RIP and re-enters guest via `goto reenter_guest_fast`
     (no full VM exit)
   - Clears RDTSC/RDTSCP interception bits (BetterTiming re-enables
     RDTSC if active)

Patches target function signatures and symbol names, not line numbers,
for resilience across kernel versions. Currently validated against
kernel 6.19.x. See README §Kernel Integration for the wiring snippets
(CachyOS + stock kernel variants).

## Detection-vector catalogue

The full table of detection vectors covered + the file that handles each
lives in the README's "Detection Vectors Covered" section. It is the
canonical surface listing — do not duplicate it here. This document
covers ownership, layering, and directory layout only.
