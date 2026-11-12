# vfio-stealth-nix

A flake for NixOS hosts that run VFIO/KVM guests. It replaces the identifiers a
guest reads to recognise QEMU, OVMF and KVM with values taken from real
hardware: SMBIOS strings, ACPI OEM fields and devices, PCI and disk
identifiers, CPUID and timing behaviour. Some detection methods remain, listed
under [Known limits](#known-limits).

## Does it work

The stealth stack is `x86_64-linux` only, for AMD and Intel hosts. The checks
boot a NixOS guest on the QEMU and OVMF of each vendor, and no check boots a
Windows guest. The kernel patches are AMD only. On `aarch64-linux` the flake
builds only `stealth-detect`, and nothing is spoofed there.

## What you get

Three pieces, and a host uses all three: an overlay with the packages below, a
NixOS module, and `lib.mkStealthFeatures`, which returns the libvirt and QEMU
fragments for one VM. The host defines the VM itself. Nothing here creates a
libvirt domain or selects the QEMU a VM runs on.

| Package | What it is |
|---|---|
| `qemu-stealth`, `qemu-stealth-intel` | QEMU with the AutoVirt patch for that vendor and configurable hardware identifiers |
| `ovmf-stealth`, `ovmf-stealth-intel` | Patched OVMF firmware |
| `acpi-ssdt-stealth` | ACPI tables with buttons, an AC adapter, timers, a fan, thermal zones and a battery |
| `smbios-stealth-tables` | Binary SMBIOS tables for the types QEMU cannot build from its command line |
| `smbios-extract` | Dumps the host's SMBIOS tables to a file. Needs root |
| `stealth-detect` | Reports, per vector, whether a Linux guest can tell it is virtualized |

## Install

Add the flake:

```nix
{
  inputs.vfio-stealth = {
    url = "github:Daaboulex/vfio-stealth-nix";
    inputs.nixpkgs.follows = "nixpkgs";
  };
}
```

Then add the overlay, import the module and switch it on. Switched on, it sets
kernel parameters and, while `tpm.harden` is on, `/etc/swtpm-localca.options`.
The last part patches the host kernel. `kernelPostPatch` holds the timing and
CPUID patches your options select.

```nix
{
  imports = [ inputs.vfio-stealth.nixosModules.default ];
  nixpkgs.overlays = [ inputs.vfio-stealth.overlays.default ];

  virtualisation.vfio-stealth = {
    enable = true;
    cpuVendor = "amd";
    smbios.manufacturer = "Your Motherboard Manufacturer";
    smbios.product = "Your Motherboard Model";
  };

  boot.kernelPackages = pkgs.linuxPackagesFor (
    pkgs.linux_latest.overrideAttrs (old: {
      postPatch = (old.postPatch or "") + config.virtualisation.vfio-stealth.kernelPostPatch;
    })
  );
}
```

`cpuVendor` is `"amd"` or `"intel"` and has no default. On Intel, leave the
kernel part out and set `timing.enable` and `cpuidSpoof.enable` to `false`.
Both default to on, and the module refuses them with `cpuVendor = "intel"`.

## Use it

Run the VM on the QEMU and OVMF pair for your CPU: `qemu-stealth` and
`ovmf-stealth` on AMD, the `-intel` pair on Intel. `cpuVendor` picks no
package. Monitor, disk and ACPI OEM strings are build arguments of
`qemu-stealth`, set with an override.

Then build the fragments for the VM:

```nix
stealth = inputs.vfio-stealth.lib.mkStealthFeatures {
  inherit (config.virtualisation.vfio-stealth)
    smbios acpiSsdt aperfMperf stripVirtio hypervVendorId hypervMode
    kvmPvEnforceCpuid pciMmio64Mb hypervFeatures kernelCapabilities;
  acpiTables = pkgs.acpi-ssdt-stealth;
  smbiosTables = pkgs.smbios-stealth-tables;
};
```

Put `features`, `cpuFeatures`, `clock` and `sysinfo` into the libvirt domain.
Call `qemuArgs` with the module's `cpuIdentity` option set, or `null`, and add
the list it returns to the QEMU command line. Remove the devices
`devicesToRemove` names, and add `warnings` to your own.

Use your own hardware strings, from `dmidecode`, `edid-decode` or the
manufacturer's website. Detection software can identify known stealth
configurations, and the module warns about values left at a placeholder.

## Options you are likely to set

| Option | What it is for |
|---|---|
| `smbios.*` | The board, BIOS and memory strings the guest reports |
| `hypervVendorId` | The Hyper-V vendor id the guest sees. The module warns while it is the default |
| `hypervMode` | `"enlightened"` shows the hypervisor with Hyper-V enlightenments, `"hidden"` conceals it |
| `timing.enable`, `cpuidSpoof.enable`, `cpuidPassthrough.enable` | Which kernel patches `kernelPostPatch` carries |

Every option, with its type and default: [docs/OPTIONS.md](docs/OPTIONS.md).

## Known limits

- Remote TPM attestation cannot pass. swtpm keys are not manufacturer-signed.
- Software that requires Virtualization-Based Security is incompatible with a
  standard KVM guest.
- Kernel-mode drivers that load at boot can find a hypervisor through vectors
  beyond CPUID.
- Clocks based on context switches do not depend on the TSC, and frame-time
  jitter from VM exits is reduced, not removed.
- The guest NIC's MAC address is not set. `spoofMac` and `macPrefix` are
  declared and read by no code.
- `timing.enable` switches off KVM hypercall patching for every VM on the host,
  so Linux guests lose kvmclock and PV TLB flush.

The full list, with reasons: [docs/COMPATIBILITY.md](docs/COMPATIBILITY.md).

## When something does not work

Inside the Windows guest, [`guest/verify-stealth.ps1`](guest/verify-stealth.ps1)
checks the detection vectors and prints PASS, FAIL, WARN or SKIP for each. It
is read-only and runs without Administrator.

[`guest/cleanup-registry.ps1`](guest/cleanup-registry.ps1) removes QEMU, KVM
and VirtIO registry entries left from before. Run it once as Administrator,
then reboot.

On the host, [`guest/verify-host.sh`](guest/verify-host.sh) checks the kernel
parameters, the QEMU binary and the libvirt domain. Symptoms and fixes are in
[docs/BUILD.md](docs/BUILD.md), under Troubleshooting.

## More

- [docs/COMPATIBILITY.md](docs/COMPATIBILITY.md): every detection vector
  covered, the file that handles it, and the vectors that remain
- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md): the packages, the module and
  `lib.mkStealthFeatures` in full, two worked configurations, the kernel patches
- [docs/CONFIGURATION.md](docs/CONFIGURATION.md): what the module does with
  its options, the kernel features the Hyper-V options need, and the build
  arguments of `qemu-stealth`
- [docs/BUILD.md](docs/BUILD.md): the dev shell, the checks, the guest scripts,
  and the upstreams, AutoVirt and BetterTiming, with how they are watched
- [docs/RELEASE-PROCEDURE.md](docs/RELEASE-PROCEDURE.md): bumping a dependency
  and adopting a newer AutoVirt patch
- [docs/SED-CATALOG.md](docs/SED-CATALOG.md): the patch anchors that mislead

## License

[`LICENSE`](LICENSE) is the GNU General Public License, version 2. The
packages built from this repository's own sources (`acpi-ssdt-stealth`,
`smbios-extract`, `smbios-stealth-tables`, `stealth-detect`) declare
`gpl2Only` as their `meta.license`. `qemu-stealth` and `ovmf-stealth` set no
`meta.license` of their own and keep the one of the nixpkgs packages they
override. [`vendor/autovirt`](vendor/autovirt) carries its own
[`LICENSE`](vendor/autovirt/LICENSE), the GNU General Public License, version
3, and its own [`README`](vendor/autovirt/README), which states the licence
of the vendored patches.
