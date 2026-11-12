# vfio-stealth-nix — Architecture

Companion to the top-level [README](../README.md). Covers directory
layout, the packages, what the module and `lib.mkStealthFeatures` do and
what they leave to the caller, which file owns which option group, two
worked configurations, and how the kernel integration is layered.

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

## Packages

`overlays.default` provides `qemu-stealth` and `ovmf-stealth` (AMD),
`qemu-stealth-intel` and `ovmf-stealth-intel`, `acpi-ssdt-stealth`,
`smbios-stealth-tables`, `smbios-extract` and `stealth-detect`. Both vendors
are built and contract-tested, each with the AutoVirt patch family of its
vendor. The caller chooses the QEMU and OVMF pair for its CPU and points its
VM at it. The module option `cpuVendor` picks no package.

| Package | Description |
|---|---|
| `qemu-stealth` | QEMU with the AutoVirt hardware-emulation patch applied, which also sets the fw_cfg DMA signature to a fixed value, and with configurable hardware identifiers: EDID, ACPI OEM, disk and optical models, SCSI vendor and target product, disk serial |
| `ovmf-stealth` | Patched EDK2/OVMF firmware: clears VirtualMachine bit in SMBIOS Type 0, replaces Red Hat PCI vendor IDs, overrides ACPI OEM fields, strips BGRT boot logo (VMAware indicator). Overridable: `secureBoot`, `msVarsTemplate`, `tpmSupport` |
| `acpi-ssdt-stealth` | Compiled ACPI SSDT tables providing power and sleep buttons, an AC adapter, timer devices, a voltage regulator device, a fan, thermal zones and a battery |
| `smbios-stealth-tables` | Binary SMBIOS tables for types QEMU cannot build via CLI (Type 7 cache, Types 26-29 probes) |
| `smbios-extract` | Dumps the host's SMBIOS tables to a file with `dmidecode --dump-bin`, as the source of real hardware strings for the VM config. Needs root |
| `stealth-detect` | Built on both systems, and the only package on `aarch64-linux`. Reports, per vector, whether a Linux guest can tell it is virtualized (device tree, PSCI conduit, MIDR, SMBIOS, ACPI OEM and FADT hypervisor identity, virtio, PCI, timer). Exits 1 when any vector fires |

## The module

`cpuVendor` is `"amd"` or `"intel"`. It is required and has no default. With
`enable = true` the module sets:

- `boot.kernelParams`: `processor.max_cstate`, `kvm_amd.vls=0`,
  `kvm_amd.vgif=0`, `kvm.ignore_msrs=1`, `kvm.report_ignored_msrs=0`, and
  `tsc=reliable` while `kernelParams.tscReliable` is on.
- `/etc/swtpm-localca.options`, while `tpm.harden` is on.
- Assertions on the option values, and a warning for each identity value left
  at its placeholder default.
- Two read-only options the caller applies itself: `kernelPostPatch` (see
  [Kernel-integration layering](#kernel-integration-layering)) and
  `libtpmsIdentityPatch`, a `postPatch` fragment for `libtpms`.

It sets nothing else. The remaining options hold values for the caller: most
are passed to `lib.mkStealthFeatures`, and `edid`, `disk` and `acpiOem` record
what the caller gives the `qemu-stealth` override. `spoofMac` and `macPrefix`
are read by no code in this flake.

## `lib.mkStealthFeatures`

`lib.mkStealthFeatures` returns the libvirt and QEMU fragments for one VM. The
call itself is in the README, under Use it. Its arguments:

- Required: `smbios` (the module's `smbios` option set carries every field it
  reads), `acpiTables` (the `acpi-ssdt-stealth` package) and `smbiosTables`
  (the `smbios-stealth-tables` package).
- Optional: `vmUuid`, which defaults to `null`, and `acpiSsdt`, `aperfMperf`,
  `stripVirtio`, `hypervVendorId`, `hypervMode`, `kvmPvEnforceCpuid`,
  `pciMmio64Mb`, `hypervFeatures` and `kernelCapabilities`, each with the
  default of the module option of the same name.

The function writes nothing into the system configuration. The caller places
each attribute of the result:

| Attribute | What the caller does with it |
|---|---|
| `warnings` | Adds the list to its own `warnings`. It holds one message per requested Hyper-V feature that `kernelCapabilities` does not cover |
| `features` | Puts it into the domain's `<features>`: `kvm.hidden`, `hint-dedicated`, `poll-control`, VMPort off, and the `hyperv` block in enlightened mode |
| `cpuFeatures` | Puts it into the domain's `<cpu>` feature list: `topoext` and `invtsc`, and `hypervisor` disabled in hidden mode |
| `clock` | Puts it into the domain's `<clock>` |
| `sysinfo` | Puts it into the domain's `<sysinfo>`: SMBIOS Types 0, 1 and 2 |
| `qemuArgs` | Calls it with the module's `cpuIdentity` option set, or `null`, and adds the returned list to the QEMU command line: the other SMBIOS types, the ACPI tables and the `-cpu` flags |
| `devicesToRemove` | Removes the named devices from the VM. The list is empty when `stripVirtio` is false |

## Component → option-group ownership

| Component | Option prefix | Detection vectors covered |
|---|---|---|
| `qemu-stealth` ([`qemu/package.nix`](../qemu/package.nix)) | build-time args (`edid*`, `disk*`, `optical*`, `acpiOem*`) — overlay or `callPackage` | EDID display identity, disk/optical model strings, disk serial, ACPI OEM IDs, fw_cfg DMA signature + ACPI device removal |
| `ovmf-stealth` ([`ovmf/package.nix`](../ovmf/package.nix)) | inherited via overlay — no module options | OVMF SMBIOS Type 0 (VirtualMachine bit), Red Hat PCI vendor IDs (1AF4/1B36→1022, 1234→1002), ACPI OEM fields, BGRT table (TianoCore CRC identifier) |
| [`module.nix`](../module.nix) `smbios.*` | `virtualisation.vfio-stealth.smbios.*` | SMBIOS Types 0, 1, 2, 3, 4, 11, 17, 41 (BIOS, system, baseboard incl. version/serial/asset/location, chassis manufacturer, processor socket, OEM strings, memory, onboard devices), once the caller passes the set to `mkStealthFeatures`. `smbios.cache` is read by no code in this flake: Type 7 comes from `smbios-stealth-tables` |
| [`module.nix`](../module.nix) `acpiSsdt.*` | `virtualisation.vfio-stealth.acpiSsdt.*` | ACPI SSDT (fan, thermal zone with fluctuation, battery, buttons, AC adapter, timers) |
| [`module.nix`](../module.nix) `timing`, `cpuidSpoof`, `cpuidPassthrough` | `virtualisation.vfio-stealth.{timing,cpuidSpoof,cpuidPassthrough}.*` | RDTSC/RDTSCP timing, CPUID leaf 0 vendor string (`cpuidSpoof`, which changes no other leaf and leaves the hypervisor bit alone), CPUID execution timing, KVM hypercall instruction patching (disabled by the timing patch) |
| [`module.nix`](../module.nix) `kernelParams.*` | `virtualisation.vfio-stealth.kernelParams.{maxCState,tscReliable}` | TSC stability, TSC source selection, SVM params (kvm_amd.vls=0, kvm_amd.vgif=0) |
| [`module.nix`](../module.nix) `aperfMperf` | `virtualisation.vfio-stealth.aperfMperf` | IA32_APERF/MPERF MSR passthrough (covers IET) |
| [`module.nix`](../module.nix) `stripVirtio` / `spoofMac` / `macPrefix` | top-level toggles | `stripVirtio` yields `devicesToRemove` (VirtIO PCI vendor ID) once the caller passes it to `mkStealthFeatures`. `spoofMac` and `macPrefix` (default `D8:BB:C1`) are declared and read by no code in this flake |
| [`lib.nix`](../lib.nix) `mkStealthFeatures` | the function's arguments; the caller places the result in its VM definition | `kvm.hidden`, hypervisor bit cleared in hidden mode, Hyper-V features and vendor_id override, clock timers (HPET present), SMBIOS and ACPI table arguments, `-cpu` flags (`kvm-pv-enforce-cpuid`, off by default) |
| `acpi/*.dsl` | compiled AML embedded in `acpi-ssdt-stealth` | ACPI SSDT runtime indicators |
| `smbios-extract` ([`smbios/package.nix`](../smbios/package.nix)) | CLI tool, not a module option | Host SMBIOS dump for VM identity customization |
| `smbios-stealth-tables` ([`smbios/tables-package.nix`](../smbios/tables-package.nix)) | build-time args (`cacheL1`, `cacheL2`, `cacheL3`) | SMBIOS Types 7, 26, 27, 28, 29 (cache, probes — binary injection via `-smbios file=`) |

## Example configurations

> Do not use these exact values. Detection software can identify
> known stealth configurations. Use your own realistic hardware strings
> from `dmidecode`, `edid-decode`, or manufacturer websites.

Each example sets the module's options and overrides `qemu-stealth` with the
matching build-time arguments. Two of the values they set are read by no code
in this flake: `macPrefix`, and `smbios.cache`, whose sizes reach the guest
only through the `cacheL1`, `cacheL2` and `cacheL3` arguments of
`smbios-stealth-tables`.

### Example 1: MSI + Corsair + BenQ + WD

```nix
virtualisation.vfio-stealth = {
  enable = true;
  cpuVendor = "amd"; # or "intel". Required, no default
  smbios = {
    manufacturer = "Micro-Star International Co., Ltd.";
    product = "MAG X670E TOMAHAWK WIFI";
    biosVendor = "American Megatrends International, LLC.";
    biosVersion = "7E12vAH";
    biosDate = "02/15/2025";
    biosRelease = "2.3";
    baseBoardVersion = "Rev 1.02";
    baseBoardSerial = "K716234029";
    serial = "K716234029";
    socketPrefix = "AM5";
    cache = {
      l1 = 512;
      l2 = 16384;
      l3 = 65536;
    };
    oemStrings = [
      "Default string"
      "Default string"
      "TOMAHAWK"
      "Default string"
    ];
    memory = {
      manufacturer = "Corsair";
      partNumber = "CMK32GX5M2B5600C36";
      speed = 5600;
      count = 2;
    };
  };
  macPrefix = "2c:f0:5d";
};

# QEMU overlay with matching hardware strings
nixpkgs.overlays = [
  (final: prev: {
    qemu-stealth = prev.qemu-stealth.override {
      edidManufacturer = "BNQ";
      edidSerial = "EX2780Q";
      edidProductCode = "0x8532";
      edidDpi = 109;
      edidWeek = 24;
      edidYear = 2022;
      acpiOemId = "MSI_NB";
      acpiOemTableId = "MEGABOOK";
      diskModel = "WDC WD10EZEX-00WN4A0    ";
      diskSerial = "WD-WMC4T0D2XYZA";
      opticalModel = "HL-DT-ST DVDRAM GH24NSC0";
    };
  })
];
```

### Example 2: Gigabyte + Crucial + LG + Seagate

```nix
virtualisation.vfio-stealth = {
  enable = true;
  cpuVendor = "amd"; # or "intel". Required, no default
  smbios = {
    manufacturer = "Gigabyte Technology Co., Ltd.";
    product = "B650 AORUS ELITE AX";
    biosVendor = "American Megatrends Inc.";
    biosVersion = "F20";
    biosDate = "03/22/2025";
    biosRelease = "2.0";
    baseBoardVersion = "x.x";
    baseBoardSerial = "SN220847001234";
    serial = "SN220847001234";
    socketPrefix = "AM5";
    memory = {
      manufacturer = "Crucial Technology";
      partNumber = "CT16G56C46S5.M8G1";
      speed = 5600;
      count = 4;
    };
  };
  macPrefix = "70:85:c2";
};

# QEMU overlay with matching hardware strings
nixpkgs.overlays = [
  (final: prev: {
    qemu-stealth = prev.qemu-stealth.override {
      edidManufacturer = "GSM";
      edidSerial = "27GP850";
      edidProductCode = "0x5bbf";
      edidDpi = 109;
      edidWeek = 38;
      edidYear = 2023;
      acpiOemId = "GBTNB ";
      acpiOemTableId = "GBYTE   ";
      diskModel = "ST2000DM008-2UB102      ";
      opticalModel = "ATAPI iHAS124   Y       ";
    };
  })
];
```

## Kernel-integration layering

The module exposes `virtualisation.vfio-stealth.kernelPostPatch`, a shell
script string that patches the kernel source tree via sed and awk. It is meant
to be appended to `linux*.kernel.overrideAttrs`'s `postPatch`. Three
composable patch sets target the KVM/SVM subsystem, and the script combines
them according to the `timing`, `cpuidSpoof` and `cpuidPassthrough` options.

1. **BetterTiming** ([`kernel/timing-patch.nix`](../kernel/timing-patch.nix)) -- TSC compensation + hypercall #UD injection
2. **CPUID emulation** ([`kernel/cpuid-patch.nix`](../kernel/cpuid-patch.nix)) -- Hypervisor-Phantom leaf 0 override without full VM exit
3. **CPUID passthrough** ([`kernel/cpuid-disable.nix`](../kernel/cpuid-disable.nix)) -- exit-less CPUID, guest runs at native hardware speed

Patches target function names and symbol names, not line numbers or
argument names, for resilience across kernel versions. Every edit verifies
its own effect, and `checks.kernel-postpatch-fits-cachyos` /
`checks.kernel-postpatch-fits-upstream` run the real scripts against the
CachyOS and nixpkgs-latest kernel sources in CI.

### Wiring

With a CachyOS kernel:

```nix
boot.kernelPackages = pkgs.linuxPackagesFor (
  pkgs.linuxPackages_cachyos.kernel.overrideAttrs (old: {
    postPatch = (old.postPatch or "") + config.virtualisation.vfio-stealth.kernelPostPatch;
  })
);
```

`pkgs.linuxPackages_cachyos` is not a package of this flake. It comes from
whichever CachyOS kernel overlay the host uses. This flake's own checks run
against `linuxPackages-cachyos-latest-lto` from `xddxdd/nix-cachyos-kernel`.

With the stock kernel:

```nix
boot.kernelPackages = pkgs.linuxPackagesFor (
  pkgs.linux_latest.overrideAttrs (old: {
    postPatch = (old.postPatch or "") + config.virtualisation.vfio-stealth.kernelPostPatch;
  })
);
```

### What the patches do

BetterTiming, [`kernel/timing-patch.nix`](../kernel/timing-patch.nix):

- Adds `last_exit_start` and `total_exit_time` fields to `struct kvm_vcpu`.
  Only `total_exit_time` is used: every stealth exit handler self-times with
  `rdtsc()` and accumulates only its own duration
- Patches `MSR_IA32_TSC` reads to return compensated (exit-time-subtracted) values
- Enables RDTSC + RDTSCP interception in SVM `init_vmcb`
- Adds `handle_rdtsc_interception` handler that returns compensated TSC
- Adds `handle_rdtscp_interception` handler returning compensated TSC + TSC_AUX in ECX
- Wraps the CPUID, WBINVD, XSETBV and INVD exit handlers so each accumulates its own execution time
- Disables KVM hypercall instruction patching by forcing the `KVM_X86_QUIRK_FIX_HYPERCALL_INSN` check true, so VMCALL/VMMCALL always injects #UD. This is host-wide: every VM on the host gets #UD, so Linux guests lose KVM paravirt features (kvmclock, PV TLB flush)

CPUID emulation, [`kernel/cpuid-patch.nix`](../kernel/cpuid-patch.nix):

- Intercepts CPUID leaf 0 inside `svm_vcpu_run` after `svm_vcpu_enter_exit` returns
- Overrides vendor string to `AuthenticAMD` with max leaf `0x20`
- Advances RIP and re-enters guest via `goto reenter_guest_fast` (no full VM exit)
- Clears RDTSC/RDTSCP interception bits (BetterTiming re-enables RDTSC if active)

CPUID passthrough, [`kernel/cpuid-disable.nix`](../kernel/cpuid-disable.nix), exit-less CPUID:

- Clears `INTERCEPT_CPUID` in `init_vmcb` and `pre_svm_run`
- Guest executes CPUID at native hardware speed (zero VM exit)
- AMD SVM loads guest XCR0 from VMCB, so leaf 0xD is naturally consistent
- Hardware returns AuthenticAMD with no hypervisor bit (synthetic, absent in real CPUID)
- Side effect: Hyper-V enlightenments invisible to guest (Windows uses TSC directly)

## Detection-vector catalogue

The full table of detection vectors covered, with the file that handles each,
lives in [`COMPATIBILITY.md`](COMPATIBILITY.md), Detection vectors covered. It
is the canonical surface listing. Do not duplicate it here.
