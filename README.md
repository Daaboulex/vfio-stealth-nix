# vfio-stealth-nix

A NixOS module that builds a patched QEMU, OVMF firmware and host kernel, and
defines your libvirt VMs with them, so a Windows guest reports a real PC's
hardware instead of a virtual machine's.

It is for NixOS hosts that run Windows guests through libvirt, often with a
passed-through GPU, where software inside the guest refuses to run in a VM.

> [!WARNING]
> Once you declare one VM with this module, NixVirt manages every VM on
> `qemu:///system` and deletes the ones you have not declared at the next
> rebuild. Their disks stay, but their definitions go. Back them up first, as
> [Before you start](docs/GUIDE.md#before-you-start) shows.

## Start here

| You want to | Read |
|---|---|
| see it work on a test VM, in eight steps | [docs/QUICKSTART.md](docs/QUICKSTART.md) |
| set up a gaming VM with your own hardware's identity and a GPU, step by step | [docs/GUIDE.md](docs/GUIDE.md) |
| fix something that does not work | [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md) |
| look up an option | [docs/OPTIONS.md](docs/OPTIONS.md) |
| copy a working configuration | [examples/](examples/) |

## What it changes

| Part | What the guest sees |
|---|---|
| QEMU and OVMF | a q35 board with Intel ICH9 chipset IDs, your monitor, disk, CD drive, audio codec where the VM has one, PCI subsystem and ACPI vendor strings, Logitech USB input with no serial numbers, no TianoCore logo |
| SMBIOS and ACPI tables | your board, BIOS, memory and cache data, one processor per vCPU, and the buttons, battery, fan and thermal zones real hardware has |
| Serials and ids | board, memory, disk, monitor and battery serials, the Hyper-V vendor id and each VM's UUID, derived from a private seed of yours in the form real parts report |
| TPM and Secure Boot | a TPM with your TPM's maker, model and firmware, and the Microsoft keys under a Platform Key named for your board |
| Host kernel | on AMD, CPUID answers and timing that hide VM exits; on both vendors, VMCALL and VMMCALL faulting as on real hardware |
| The VM | Hyper-V and KVM settings, clock and CPU flags that match real hardware |

## Will it work on my machine

- The host must be x86_64 with an AMD or Intel CPU and an IOMMU. On aarch64
  the flake only builds `stealth-detect`.
- The timing and CPUID kernel patches are AMD only. `instructionFixes` works on
  both vendors.
- Windows 11, with and without VBS, is installed and checked on AMD and Intel
  hosts. The flake's own checks boot Linux guests on every build.

## Install

1. Add the flake to your system and turn the module on with your CPU vendor and
   a private `identity.seed`.
2. Read your board's strings from `dmidecode` into the identity options.
3. Declare a VM under `virtualisation.vfio-stealth.domains`, with a GPU if you
   pass one through.
4. Rebuild. `bootCheck` boots small test guests on your build, and
   `verify-stealth.ps1` checks Windows from the inside.

The [quickstart](docs/QUICKSTART.md) does this with the fewest settings; the
[guide](docs/GUIDE.md) explains every step.

## What does not work

- Remote TPM attestation. swtpm keys are not signed by a TPM maker.
- Kernel drivers that load at boot can still find the hypervisor through other
  ways than CPUID.
- A guest that times CPUID sees the cost of the VM exit, unless the AMD timing
  patch runs. Timing checks based on context switches still see it.
- `timing.enable` traps RDTSC for every VM on the host, and each read costs a
  VM exit.

The full list, with the reasons, is in
[docs/COMPATIBILITY.md](docs/COMPATIBILITY.md).

## More

- [docs/DESIGN.md](docs/DESIGN.md): how the parts fit and why
- [docs/COMPATIBILITY.md](docs/COMPATIBILITY.md): every detection vector and limit
- [docs/AUTOVIRT.md](docs/AUTOVIRT.md): what the vendored AutoVirt patches change and what this repository keeps
- [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md): working on this repo

## What this repository carries itself

- AutoVirt's patches ported to the QEMU series it builds, and its duplicate ACPI name fix.
- Every correction to AutoVirt in QEMU and OVMF, listed in [docs/AUTOVIRT.md](docs/AUTOVIRT.md).
- The KVM timing patch, which hides each exit from the guest's TSC.
- The identity options with the serials derived from a private seed, the Secure Boot keys and the TPM identity.
- The VFIO host layer, its start hook, and the VMs rendered through NixVirt.
- The checks that boot every build and read what the guest sees, and the harness that installs and runs Windows on it.

## Credits

- [AutoVirt](https://github.com/Scrut1ny/AutoVirt) by Scrut1ny: the QEMU and EDK2 patches.
- [vfio-native](https://git.archworks.co/sandwich/vfio-native) by Sandwich: the KVM instruction fixes.
- [BetterTiming](https://github.com/SamuelTulach/BetterTiming) by Samuel Tulach: the idea behind the timing patch.
- AutoVirt, under its former name Hypervisor-Phantom: the CPUID leaf 0 fast path.
- [NixVirt](https://github.com/AshleyYakeley/NixVirt) by Ashley Yakeley: the libvirt domains.
- [VMAware](https://github.com/kernelwernel/VMAware): the detection reference.

## License

[LICENSE](LICENSE) is the GNU General Public License, version 2, for this
repository's own code. `qemu-stealth` and `ovmf-stealth` keep the licences of
the nixpkgs packages they override. [vendor/autovirt](vendor/autovirt) carries
its own [LICENSE](vendor/autovirt/LICENSE) and [README](vendor/autovirt/README),
which states the licence of the vendored patches. [vendor/vfio-native](vendor/vfio-native)
holds GPL-2.0 kernel patches; its [README](vendor/vfio-native/README) records their origin.
