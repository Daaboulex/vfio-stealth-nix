# vfio-stealth-nix — Architecture

Companion to the top-level [README](../README.md). Covers directory
layout, which file owns which option group, and how the kernel
integration is layered.

## Directory layout

```text
vfio-stealth-nix/
├── flake.nix                # packages, overlays.default, nixosModules.default
├── module.nix               # myModules.vfio.stealth.* options + assertions
├── lib.nix                  # libvirt domain rewriter (NixVirt int typing,
│                            # vendor_id, kvm-hidden, emulated-battery wiring)
├── qemu/
│   └── package.nix          # qemu-stealth — patched QEMU + AutoVirt patches
│                            # + EDID + ACPI OEM + disk/optical model overrides
├── ovmf/
│   └── package.nix          # ovmf-stealth — patched EDK2/OVMF firmware,
│                            # SMBIOS Type 0 VirtualMachine bit cleared,
│                            # Red Hat PCI vendor IDs replaced
├── acpi/
│   ├── spoofed-devices.dsl  # ACPI SSDT: emulated EC, fan, thermal zone,
│   │                        # power/sleep buttons, timers
│   ├── sensor-probes.dsl    # CPU/VRM thermal zones + temperature probes
│   ├── fake-battery.dsl     # Control Method Battery (PNP0C0A)
│   └── package.nix          # Compiles DSL → AML, bundles as derivation
├── kernel/
│   ├── timing-patch.nix     # BetterTiming TSC compensation
│   │                        # → exposed via _kernelPostPatch
│   ├── cpuid-patch.nix      # Hypervisor-Phantom CPUID leaf 0 override
│   │                        # → exposed via _kernelPostPatch
│   └── cpuid-disable.nix    # Exit-less CPUID passthrough (AMD SVM)
│                            # → exposed via _kernelPostPatch
├── smbios/
│   ├── package.nix          # smbios-extract — host SMBIOS dump +
│   │                        # anonymization helper
│   ├── extract.sh           # Shell script wrapped by package.nix
│   ├── tables-package.nix   # smbios-stealth-tables — binary SMBIOS
│   │                        # table generator (types 7, 26-29)
│   └── generate-tables.py   # Python script generating raw SMBIOS binaries
├── guest/
│   ├── verify-stealth.ps1   # 38-vector detection check (run inside VM)
│   ├── cleanup-registry.ps1 # Registry artifact removal (admin, run once)
│   └── verify-host.sh       # Host-side sanity checks
├── scripts/
│   ├── update.sh            # AutoVirt + BetterTiming flake-input bumper
│   └── check-kernel-patches.sh  # Validate kernel patch anchors
├── .github/
│   ├── workflows/{ci,update,maintenance}.yml
│   ├── update.json
│   └── dependabot.yml
├── README.md
├── docs/                    # this folder
├── LICENSE
└── SECURITY.md
```

## Component → option-group ownership

| Component | Option prefix | Detection vectors covered |
|---|---|---|
| `qemu-stealth` (qemu/package.nix) | build-time args (`edid*`, `disk*`, `optical*`, `acpiOem*`) — overlay or `callPackage` | EDID display identity, disk/optical model strings, disk serial, ACPI OEM IDs, fw_cfg 4-byte probe |
| `ovmf-stealth` (ovmf/package.nix) | inherited via overlay — no module options | OVMF SMBIOS Type 0 (VirtualMachine bit), Red Hat PCI vendor IDs (1AF4/1B36→1022, 1234→1002), ACPI OEM fields, BGRT table (TianoCore CRC identifier) |
| `module.nix` `smbios.*` | `myModules.vfio.stealth.smbios.*` | SMBIOS Types 1, 2, 4, 7, 8, 9, 11, 17, 26, 27, 28, 29, 41 (system, baseboard incl. version/serial/asset/location, processor, cache, port connector, system slots, OEM strings, memory, voltage/cooling/temperature/current probes, onboard devices) |
| `module.nix` `acpiSsdt.*` | `myModules.vfio.stealth.acpiSsdt.*` | ACPI SSDT (EC, fan, thermal zone with fluctuation, battery, buttons, timers) |
| `module.nix` `kernel.*` (timing + cpuidSpoof + cpuidPassthrough) | `myModules.vfio.stealth.{timing,cpuidSpoof,cpuidPassthrough}.*` | RDTSC/RDTSCP timing, CPUID vendor string + hypervisor bit, CPUID execution timing |
| `module.nix` `kernelParams.*` | `myModules.vfio.stealth.kernelParams.{maxCState,tscReliable}` | TSC stability, TSC source selection, SVM params (kvm_amd.vls=0, kvm_amd.vgif=0) |
| `module.nix` `aperfMperf` | `myModules.vfio.stealth.aperfMperf` | IA32_APERF/MPERF MSR passthrough (covers IET) |
| `module.nix` `stripVirtio` / `spoofMac` / `macPrefix` | top-level toggles | VirtIO PCI vendor ID, MAC OUI customization (default: D8:BB:C1, Realtek) |
| `lib.nix` (libvirt rewriter) | applied to `services.virtualisation.vms.<name>` | KVM hidden bit, Hyper-V vendor_id override, emulated-battery wiring, HPET present=true, KVM MSR enforce (kvm-pv-enforce-cpuid=on), hypercall patching disable |
| `acpi/*.dsl` | compiled AML embedded in `acpi-ssdt-stealth` | ACPI SSDT runtime indicators |
| `smbios-extract` (smbios/package.nix) | CLI tool, not a module option | Host SMBIOS dump for VM identity customization |
| `smbios-stealth-tables` (smbios/tables-package.nix) | build-time args (`cacheL1`, `cacheL2`, `cacheL3`) | SMBIOS Types 7, 26, 27, 28, 29 (cache, probes — binary injection via `-smbios file=`) |

## Kernel-integration layering

The module exposes `myModules.vfio.stealth._kernelPostPatch` — a shell
script string that patches kernel sources via `sed`/`awk`. It is meant
to be appended to `linux*.kernel.overrideAttrs`'s `postPatch`. Up to three
patch sets compose into this single hook:

1. **BetterTiming** (`kernel/timing-patch.nix`) — TSC compensation
   - Adds `last_exit_start` and `total_exit_time` fields to `struct kvm_vcpu`
   - Wraps `vcpu_enter_guest` to measure VM-exit duration
   - Patches `MSR_IA32_TSC` reads to return compensated values
   - Enables RDTSC interception in SVM `init_vmcb`
   - Adds `handle_rdtsc_interception` returning compensated TSC
   - Adds `handle_rdtscp_interception` returning compensated TSC + TSC_AUX in ECX
   - Wraps CPUID, WBINVD, XSETBV, INVD exit handlers to tag
     `exit_reason=0xDEAD` for timing compensation
   - Disables KVM hypercall instruction patching (forces `#UD` on
     VMCALL/VMMCALL instead of `#PF`, matching bare-metal behavior)

2. **CPUID emulation** (`kernel/cpuid-patch.nix`) — Hypervisor-Phantom
   - Intercepts CPUID leaf 0 inside `svm_vcpu_run` after
     `svm_vcpu_enter_exit` returns
   - Overrides vendor string to `AuthenticAMD` with max leaf `0x20`
   - Advances RIP and re-enters guest via `goto reenter_guest_fast`
     (no full VM exit)
   - Clears RDTSC/RDTSCP interception bits (BetterTiming re-enables
     RDTSC if active)

3. **CPUID passthrough** (`kernel/cpuid-disable.nix`) — Exit-less CPUID
   - Clears `INTERCEPT_CPUID` in `init_vmcb` and `pre_svm_run`
   - Guest executes CPUID at native hardware speed (zero VM exit)
   - AMD SVM loads guest XCR0 from VMCB — leaf 0xD naturally consistent
   - Hardware returns AuthenticAMD with no hypervisor bit (synthetic,
     absent in real CPUID)
   - Side effect: Hyper-V enlightenments invisible to guest (Windows
     uses TSC directly)

Patches target function signatures and symbol names, not line numbers,
for resilience across kernel versions. Validated via CI against
nixpkgs latest kernel (see `scripts/check-kernel-patches.sh`).
See README §Kernel Integration for the wiring snippets
(CachyOS + stock kernel variants).

## Detection-vector catalogue

The full table of detection vectors covered + the file that handles each
lives in the README's "Detection Vectors Covered" section. It is the
canonical surface listing — do not duplicate it here. This document
covers ownership, layering, and directory layout only.
