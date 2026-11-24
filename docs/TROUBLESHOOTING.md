# Troubleshooting

Find the symptom you see. Its row gives the cause and the fix. If no row fits,
the [logs](#logs) tell you more, and an issue with the logs attached helps the most.

## Setting up the host

| You see | Why | Fix |
|---|---|---|
| `error: experimental Nix feature 'nix-command' is disabled` | a fresh NixOS has flakes and the `nix` command turned off | [Turn on flakes](GUIDE.md#turn-on-flakes) |
| `lspci: command not found`, or the same for `dmidecode`, `vfio-stealth-gpus` and the other tools | NixOS does not install them. The module installs them only once it is in your system, with `tools.enable` on | before you [Add the flake](GUIDE.md#add-the-flake), run the finder with `nix run github:Daaboulex/vfio-stealth-nix#vfio-stealth-gpus`; after that, rebuild with `tools.enable` left on |
| The rebuild says a file, such as a GPU ROM, does not exist | a flake sees only the files that git tracks | `git add` the file in `/etc/nixos` |
| A `vfio-stealth:` warning at rebuild | an identity value is still at a default that every install shares | set the option it names; [Read the identity from your machine](GUIDE.md#read-the-identity-from-your-machine) says where to get the value |
| The screen stays dark at boot, with no disk-encryption password prompt, after binding a GPU with `binding = "boot"` | vfio-pci took the card that the firmware shows its picture on, and the prompt went with it | put the host GPU's driver in the initrd, for example `hardware.amdgpu.initrd.enable = true;`, or make the host GPU the primary display in the firmware setup |
| A VM made in virt-manager is gone after a rebuild | once one VM is declared, NixVirt deletes every VM on `qemu:///system` that is not declared. Its disks, firmware variables and TPM state stay | declare it, or run `virsh -c qemu:///system define` on its saved XML, as [Back up the VMs you already have](GUIDE.md#back-up-the-vms-you-already-have) shows |

## Starting the VM

| You see | Why | Fix |
|---|---|---|
| `refusing to start: ...` | the QEMU hook found something unsafe and says what it is: a protected disk under a passed-through device, a host process holding the GPU, a mount that will not unmount, too few free huge pages, two passed devices in one IOMMU group with `iommu`, or another pinned VM holding the CPUs | fix what it names; put a service that holds the GPU into the VM's `stopServices` |
| The hook finds too few huge pages | memory is fragmented | `virtualisation.vfio-stealth.hugepages.atBoot = true;`, a host option next to `domains` |
| `host doesn't support hyperv` | your kernel does not have that Hyper-V feature | set `kernelCapabilities`, or turn the feature off in `hypervFeatures` |
| `Unable to find 'efi' firmware that is compatible` | the stealth firmware is always the Secure Boot build | set `secureBoot = false` on the VM. In a VM you defined by hand, set the `enrolled-keys` feature to no, instead of turning `secure-boot` off |

## Booting and installing

| You see | Why | Fix |
|---|---|---|
| The firmware's boot menu, or a UEFI shell, instead of Windows setup | the "Press any key to boot from CD or DVD" prompt waits only about five seconds, and it was missed | open the VM's console before you start the VM, click into it, and press a key when the prompt shows; see [Install Windows](GUIDE.md#install-windows) |
| Windows Boot Manager: "The Boot Configuration Data for your PC is missing or contains errors", `\EFI\Microsoft\Boot\BCD`, status 0xc000000d, while the installer starts | the installer loaded, but it could not read its own files from the CD. The VM that [Declare a first VM without a GPU](GUIDE.md#declare-a-first-vm-without-a-gpu) shows installs Windows 11 25H2 cleanly. So the cause is in the ISO, or in what differs from that VM | compare the ISO's SHA-256 with the one Microsoft shows on its download page, and try the VM exactly as the guide declares it. If it still fails, open an issue with `virsh -c qemu:///system dumpxml <name>` and `/var/log/libvirt/qemu/<name>.log` |
| A UEFI shell with no disk at all | the VM does not run on the stealth firmware, or setup needs a driver for its disk | let the module choose the firmware, and set no path by hand. A virtio disk needs the virtio-win storage driver in setup. `bootCheck` boots the same QEMU and firmware from SATA, virtio and CD, and shows where a boot stops |
| A black screen before Windows | the same as above | build `bootCheck` and read its serial logs |
| The VM sometimes hangs before Windows loads | the firmware can stall when an unpinned vCPU moves between host CPUs, and Windows when its vCPUs share host CPUs; see [Known limitations](COMPATIBILITY.md#known-limitations) | with `pinning`, pin each vCPU to its own host CPU, and put `emulator` on other CPUs |
| Windows hangs at boot with `cpuidPassthrough.enable` | the VM has fewer vCPUs than the host has threads | give it as many vCPUs as the host has threads, or turn it off |
| Windows crashes early in boot | `kvmPvEnforceCpuid` is on | turn it off |
| With VBS or Memory integrity, Windows falls into Automatic Repair or stops at the logo on an Intel host | Windows' own Hyper-V does not start while the guest sees CET | keep `cet` at its default, which is off on Intel |
| With VBS or Memory integrity, Windows falls into Automatic Repair on an Intel host with `iommu = true` | Windows with VBS does not start with the VM's Intel IOMMU, see [Known limitations](COMPATIBILITY.md#known-limitations) | turn `iommu` off |
| With VBS or Memory integrity, a black screen with a passed-through GPU | VBS needs DMA protection, and only an IOMMU in the VM gives it | on AMD, set the VM's `iommu = true`; on Intel it does not help, see the row above |
| Display corruption with a large GPU | the 64-bit PCI window is too small for the card | raise `pciMmio64Mb` |

## Detection results

If a detection tool still finds the VM, a setting is usually left at its
default. [Read a VMAware result](GUIDE.md#read-a-vmaware-result) lists what
each VMAware technique means and which setting removes it.
`verify-stealth.ps1` names each check that still fails, as
[Check from inside Windows](GUIDE.md#check-from-inside-windows) shows.

## Performance

| You see | Why | Fix |
|---|---|---|
| Games in the VM run slower | `timing.enable` traps RDTSC in every VM on the host | turn it off if no game you run checks timing. Then it hides no exit time from any VM on the host |
| Games on the host run slower | `kernelParams.maxCState` keeps every host core out of deep idle, which can lower boost | raise it |
| The VM feels slow everywhere | its vCPUs share host CPUs, or a scheduler daemon lowers QEMU's priority | pin it as [CPU pinning](GUIDE.md#cpu-pinning) shows, and keep QEMU at normal priority |

## Logs

- `/var/log/libvirt/qemu/<name>.log`: QEMU's own output for the VM.
- `journalctl -b -u libvirtd`: libvirt itself, and the hook's `refusing to start` lines.
- `journalctl -b -u nixvirt`: how the declared VMs are defined at each rebuild.
- `sudo vfio-stealth-verify-host <name>`: the host's kernel parameters, the QEMU binary and the VM's definition.
- `bootCheck`'s `result/serial/`: what each test guest printed, as
  [Check the build with bootCheck](GUIDE.md#check-the-build-with-bootcheck) shows.
