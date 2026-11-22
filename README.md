# vfio-stealth-nix

A NixOS module that builds patched QEMU, OVMF and host kernel patches and
defines libvirt VMs with them, so a Windows guest reports a real PC's hardware
instead of a virtual machine's.

It is for NixOS hosts that run Windows guests through libvirt, often with a
passed-through GPU, where software inside the guest refuses to run in a VM.
Some checks still find the VM; they are listed under
[What does not work](#what-does-not-work).

To see it work first, [docs/QUICKSTART.md](docs/QUICKSTART.md) boots a test
VM. New to VFIO? [docs/GUIDE.md](docs/GUIDE.md) goes from
checking the hardware to a running Windows VM, step by step, and ends with the
recommended value of every option for a hardened gaming VM.

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

- The host must be x86_64 with an AMD or Intel CPU. On aarch64 the flake only
  builds `stealth-detect`.
- The timing and CPUID kernel patches are AMD only. `instructionFixes`
  patches the kernel on both vendors: VMCALL and VMMCALL at CPL > 0 raise #UD
  on both, and its SVM and ICEBP fixes apply on AMD only.
- The checks boot Linux guests on the QEMU and OVMF of both vendors. Windows
  11, with and without VBS, runs on AMD and Intel hosts through the Windows
  harness, which needs an installer ISO and runs by hand, as
  [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md) shows.

## Install

[docs/GUIDE.md](docs/GUIDE.md) walks a first VFIO host through every step
below, with the commands that read each value from the machine.

Add the flake and import one of its modules in the host's `nixosSystem`. A flake you already have keeps its own inputs and gains `vfio-stealth`:

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    vfio-stealth = {
      url = "github:Daaboulex/vfio-stealth-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    { nixpkgs, vfio-stealth, ... }:
    {
      nixosConfigurations.vm-host = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          vfio-stealth.nixosModules.default
          ./hardware-configuration.nix
          ./configuration.nix
        ];
      };
    };
}
```

| Module | What it imports |
|---|---|
| `nixosModules.default` | this module and NixVirt's NixOS module, which defines the VMs |
| `nixosModules.vfio-stealth` | this module alone, for a configuration that already imports NixVirt's module |

Turn it on and set your CPU vendor, your board's strings from `dmidecode`,
and `identity.seed`, a private phrase only this host uses: every serial and id
you leave unset is derived from it.
The module builds its own packages, so no overlay is needed. The overlay is
there for using `qemu-stealth` and the others elsewhere.

```nix
{
  virtualisation.libvirtd.enable = true;
  virtualisation.vfio-stealth = {
    enable = true;
    cpuVendor = "amd";
    identity.seed = "pick a private phrase for this host";
    smbios.manufacturer = "Your board manufacturer";
    smbios.product = "Your board model";
  };
}
```

Build your kernel with the patches the module selects.
`packages.kernelFor` takes a kernel package, the one you would use anyway, and
returns it patched; `linuxPackagesFor` turns that into the kernel packages
NixOS boots. The kernel is then built from source on your machine. On AMD it
carries the timing, CPUID and instruction patches; on Intel only the VMCALL
and VMMCALL fix of `instructionFixes`. To keep a stock kernel, turn the kernel
switches off, as
[Decide on the kernel patches](docs/GUIDE.md#decide-on-the-kernel-patches)
shows.

```nix
{ config, pkgs, ... }:
{
  boot.kernelPackages = pkgs.linuxPackagesFor (
    config.virtualisation.vfio-stealth.packages.kernelFor pkgs.linux_latest
  );
}
```

To pass devices through, also set `virtualisation.vfio-stealth.host.enable`.
It loads VFIO, disables host suspend, which a passed-through device does not
survive, and installs the libvirt hook that does each VM's work at start and
stop. [Make a VM](#make-a-vm) shows a GPU passed through.

Then rebuild. The module makes the stealth QEMU and OVMF libvirt's QEMU and
UEFI firmware, and turns on swtpm with your TPM's identity. Leave
`virtualisation.libvirt.swtpm.enable` unset: NixVirt's swtpm would replace the
patched one. A full configuration is in [examples/](examples/).

## Options you set first

| Option | What it is for |
|---|---|
| `enable`, `cpuVendor` | turn the module on; `cpuVendor`, `"amd"` or `"intel"`, has no default and picks the QEMU and OVMF pair and the kernel patches |
| `identity.seed` | a private phrase unique to this host; the board, memory, disk, monitor and battery serials, the Hyper-V vendor id and each VM's UUID left unset are derived from it. Keep it out of a public repository |
| `smbios.*` | your board, system, chassis, BIOS, memory, cache, port, slot and onboard device data |
| `cpuIdentity.*` | the CPU name, speeds, socket, family, voltage and clock; left null, the socket, family, voltage, external clock, upgrade and characteristics take a real board's for `cpuVendor`, `modelId` keeps the host CPU's, and the speeds keep QEMU's 2000 |
| `devices.*` | the ids and strings of QEMU's emulated USB devices, MegaRAID card and ACPI creator, the same for every install until you set your own |
| `disk.*`, `edid.*`, `acpiOem.*`, `pciSubsystem`, `hdaCodec` | the disk and CD drive models and firmware, the monitor, the ACPI vendor strings, the PCI subsystem and the audio codec built into QEMU and OVMF |
| `tpm.*`, `secureBoot.platformKeyName` | the TPM's maker, model and firmware, and the name of the Secure Boot Platform Key |
| `macPrefix` | the maker part of every declared VM's MAC address |
| `hypervVendorId` | the Hyper-V vendor id the guest sees, derived from `identity.seed` unless set |
| `hypervMode` | `"enlightened"` shows the hypervisor with Hyper-V enlightenments, `"hidden"` hides it |
| `host.enable`, `user` | the passthrough host layer, and the user who runs the Looking Glass client |

Use your own hardware's strings: detection software knows the defaults, and
the rebuild warns about each serial still at the value every host without a
seed shares. Every option is in [docs/OPTIONS.md](docs/OPTIONS.md).

## Make a VM

Declare it under `domains`:

```nix
{
  virtualisation.vfio-stealth.domains.win11 = {
    memory = 16384;
    cores = 4;
    disks = [ { source = "/var/lib/libvirt/images/win11.qcow2"; format = "qcow2"; } ];
    cdroms = [ "/var/lib/libvirt/images/win11.iso" ];
    network = { };
  };
}
```

The module adds the stealth parts, and NixVirt defines the VM in libvirt when
the system activates. The VM's UUID comes from `identity.seed` and its name;
set `uuid` only to keep the one an existing VM has.

- Once one VM is declared, NixVirt owns every VM on `qemu:///system`. It
  deletes a VM that is not declared, keeping its disks, NVRAM and TPM state,
  and overwrites a change made in virt-manager the next time it defines the VM.
- A rebuild that changes a running VM's definition powers it off and starts it
  again.
- To keep a VM in virt-manager instead, build its XML with
  `nix build /etc/nixos#nixosConfigurations.<host>.config.virtualisation.vfio-stealth.domains.<name>.xml`,
  run `virsh -c qemu:///system define result`, and remove every declaration.
  A VM defined that way gets none of the hook's work at start and stop. Its
  XML names the firmware, ACPI and SMBIOS tables in the Nix store, which only
  `result` keeps from garbage collection: keep it where it is, or build with
  `-o` to a link you keep.

A VM with a passed-through GPU, its own CPU cores, huge pages, a USB device and
Looking Glass, on a host with `host.enable` set. The addresses are the ones
`lspci -D` prints, the CPU numbers the ones `lscpu -e` pairs into cores:

```nix
{
  virtualisation.vfio-stealth = {
    host.enable = true;
    user = "alice";
    kvmfr = { enable = true; sizeMb = 64; };
    lookingGlass.client = true;
    evdev.keyboard = "/dev/input/by-id/usb-Example_Keyboard-event-kbd";
    evdev.mouse = "/dev/input/by-id/usb-Example_Mouse-event-mouse";

    domains.win11 = {
      memory = 16384;
      cores = 4;
      machine = "pc-q35-10.0";
      pinning = {
        vcpus = [ 2 10 3 11 4 12 5 13 ];
        emulator = "0-1";
      };
      hugepages = true;
      disks = [ { source = "/dev/disk/by-id/nvme-Example_SSD_1TB"; } ];
      network = { };
      gpu = {
        address = "0000:01:00.0";
        audio = "0000:01:00.1";
      };
      usb = [ { vendor = 4660; product = 22136; } ];
      lookingGlass = true;
    };
  };
}
```

- `gpu.binding` says how the GPU reaches vfio-pci: `"libvirt"`, the default,
  takes it from the host driver at start and gives it back at stop; `"hook"`
  binds it in the hook after the host has initialised it, for cards that need
  that; `"boot"` claims it at boot by the ids in `gpu.ids`, so the host never
  drives it.
- Before the VM starts, the hook refuses a GPU or `hostDevices` entry that one
  of `host.protectedDisks` sits on, and unmounts what is mounted from a disk
  the VM takes.
- `evdev` hands the keyboard and mouse to the running VM; both Ctrl keys
  switch them between host and guest.
- The USB ids are numbers: lsusb's `1234:5678` is `4660` and `22136`.

In Windows, run [guest/verify-stealth.ps1](guest/verify-stealth.ps1), with
`-HypervMode hidden` for a VM with `hypervMode = "hidden"`. It prints PASS,
FAIL, WARN or SKIP for each check and changes nothing. On the host,
`vfio-stealth-verify-host <name>` checks the kernel parameters, the QEMU binary
and the VM's definition.

[guest/cleanup-registry.ps1](guest/cleanup-registry.ps1) removes what QEMU and
VirtIO drivers left in a Windows install. It clears any event log that names a
VM, whole.

`smbios-extract` writes the host's own SMBIOS structures as files QEMU takes
with `-smbios file=`. It copies them as they are, serial numbers included. It
is a package of this flake, not installed by the module:
`nix build github:Daaboulex/vfio-stealth-nix#smbios-extract`, then
`sudo ./result/bin/smbios-extract /var/lib/vfio/smbios`. Give a VM the files
it prints through `domains.<name>.extraQemuArgs`, such as
`[ "-smbios" "file=/var/lib/vfio/smbios/<file>" ]`. QEMU refuses a file of a
type the VM's own `-smbios type=` arguments already set; `domain.qemuArgs`
shows them.

## Check your build

```sh
nix build /etc/nixos#nixosConfigurations.<host>.config.virtualisation.vfio-stealth.bootCheck -L
```

This renders small test VMs the way `domains` does, has libvirt turn each into
a QEMU command line, and boots them on your QEMU and firmware: from a SATA disk,
a virtio disk and a CD, with QXL video, with SMBIOS emulated, and with Secure
Boot. A probe inside each guest reads what the guest sees, from CPUID and
SMBIOS to the TPM and the ACPI tables, and fails the build on a value that
gives the VM away. It needs `/dev/kvm`. `result/evidence.json` and
`result/serial/` hold what each guest saw.

## What does not work

- Remote TPM attestation. swtpm keys are not signed by a TPM maker.
- Kernel drivers that load at boot can still find the hypervisor through other
  ways than CPUID.
- A guest that times CPUID sees the cost of the VM exit, unless the AMD timing
  patch runs. Timing checks based on context switches still see it.
- `timing.enable` traps RDTSC for every VM on the host, and each read costs a
  VM exit.
- On some KVM hosts the QEMU and OVMF of nixpkgs stall in a share of boots,
  stealth or not.

The full list, with the reasons, is in
[docs/COMPATIBILITY.md](docs/COMPATIBILITY.md).

## When it breaks

| Symptom | Fix |
|---|---|
| A black screen, or the VM lands in the UEFI shell and finds no disk | Check that the VM uses the stealth OVMF, not a path set by hand to another one. Build `bootCheck`: it boots the same QEMU and firmware from SATA, virtio and CD with VGA and QXL, and its serial logs show where a boot stops. Windows setup sees a virtio disk only with the virtio-win storage driver |
| "Unable to find 'efi' firmware that is compatible" | The stealth OVMF is always the Secure Boot build. To boot unsigned loaders, set `secureBoot = false` on a declared VM; in a VM defined by hand, set the `enrolled-keys` feature to no instead of turning `secure-boot` off |
| A VM made in virt-manager is gone after a rebuild | NixVirt deletes every VM on `qemu:///system` that is not declared once one is. Its disks, NVRAM and TPM state remain: declare it, or define it again |
| The VM sometimes hangs before Windows loads | Pin each vCPU to a host CPU of its own with `pinning`, with `emulator` on other CPUs: Windows stalls on vCPUs that share host CPUs. An unpinned VM can also hit the stall QEMU with OVMF has on some KVM hosts, which a second start passes |
| The VM does not start: "host doesn't support hyperv" | Your kernel lacks that Hyper-V feature. Set `kernelCapabilities`, or turn the feature off in `hypervFeatures` |
| Windows with VBS or Memory integrity falls into Automatic Repair or stops at the logo on an Intel host | Keep `cet` off, its default with Intel |
| Windows hangs at boot with `cpuidPassthrough.enable` | Give the VM as many vCPUs as the host has threads, or turn it off |
| Windows crashes early in boot | Keep `kvmPvEnforceCpuid` off |
| Display corruption with a large GPU | Raise `pciMmio64Mb` |
| The VM does not start: "refusing to start: ..." | The QEMU hook says what it refused: a passed-through device a protected disk sits on, a host process that holds the GPU open, a mount that will not unmount, too few free huge pages, two passed devices in one IOMMU group with `iommu`, or another pinned VM holding the CPUs. A service holding the GPU goes into the VM's `stopServices` |
| Windows with VBS or Memory integrity shows a black screen with a passed-through GPU | Set the VM's `iommu = true`, which gives Windows the DMA protection VBS needs |
| The hook finds too few huge pages | Memory is fragmented. Set `virtualisation.vfio-stealth.hugepages.atBoot = true;`, a host option beside `domains`, which reserves them at boot |
| Games on the host run slower | `kernelParams.maxCState` keeps every host core out of deep idle, which can cost boost; raise it when the host itself games |
| Games in the VM run slower | `timing.enable` traps RDTSC in every VM on the host to hide VM exits; turning it off removes timing stealth from every VM on the host |

## More

- [docs/QUICKSTART.md](docs/QUICKSTART.md): the shortest path to a test VM
- [docs/GUIDE.md](docs/GUIDE.md): from the hardware check to a running Windows VM, for a first VFIO host, with the hardened gaming settings
- [docs/DESIGN.md](docs/DESIGN.md): how the parts fit and why
- [docs/AUTOVIRT.md](docs/AUTOVIRT.md): what the vendored AutoVirt patches change and what this repository keeps
- [docs/COMPATIBILITY.md](docs/COMPATIBILITY.md): every detection vector and limit
- [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md): working on this repo
- [docs/OPTIONS.md](docs/OPTIONS.md): every option

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
