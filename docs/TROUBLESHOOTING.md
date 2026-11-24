# Troubleshooting

Find the symptom you see, then its cause and fix. When none fits, the
[logs](#logs) say more, and an issue with them attached helps the most.

## Setting up the host

| You see | Why | Fix |
|---|---|---|
| `error: experimental Nix feature 'nix-command' is disabled` | a fresh NixOS has flakes and the `nix` command off | [Turn on flakes](GUIDE.md#turn-on-flakes) |
| `lspci: command not found`, or the same for `dmidecode` and the other tools | NixOS does not install them, and a `nix shell` ends with its terminal | [Install the tools this guide uses](GUIDE.md#install-the-tools-this-guide-uses) |
| The rebuild says a file, such as a GPU ROM, does not exist | a flake sees only the files git tracks | `git add` the file in `/etc/nixos` |
| A `vfio-stealth:` warning at rebuild | an identity value still at a default every install shares | set the option it names; [Read the identity from your machine](GUIDE.md#read-the-identity-from-your-machine) says from where |
| The screen stays dark at boot, with no disk-encryption password prompt, after binding a GPU with `binding = "boot"` | vfio-pci took the card the firmware shows its picture on, and the prompt went with it | put the host GPU's driver in the initrd, such as `hardware.amdgpu.initrd.enable = true;`, or make the host GPU the primary display in the firmware setup |
| A VM made in virt-manager is gone after a rebuild | once one VM is declared, NixVirt deletes every VM on `qemu:///system` that is not; its disks, firmware variables and TPM state stay | declare it, or `virsh -c qemu:///system define` its saved XML, as [Back up the VMs you already have](GUIDE.md#back-up-the-vms-you-already-have) shows |

## Starting the VM

| You see | Why | Fix |
|---|---|---|
| `refusing to start: ...` | the QEMU hook found something unsafe and says what: a protected disk under a passed-through device, a host process holding the GPU, a mount that will not unmount, too few free huge pages, two passed devices in one IOMMU group with `iommu`, or another pinned VM holding the CPUs | fix what it names; a service holding the GPU goes into the VM's `stopServices` |
| The hook finds too few huge pages | memory is fragmented | `virtualisation.vfio-stealth.hugepages.atBoot = true;`, a host option beside `domains` |
| `host doesn't support hyperv` | your kernel lacks that Hyper-V feature | set `kernelCapabilities`, or turn the feature off in `hypervFeatures` |
| `Unable to find 'efi' firmware that is compatible` | the stealth firmware is always the Secure Boot build | set `secureBoot = false` on the VM; in a VM you defined by hand, set the `enrolled-keys` feature to no instead of turning `secure-boot` off |

## Booting and installing

| You see | Why | Fix |
|---|---|---|
| The firmware's boot menu, or a UEFI shell, instead of Windows setup | the "Press any key to boot from CD or DVD" prompt waits only about five seconds and was missed | open the VM's console before you start it, click into it, and press a key when the prompt shows; [Install Windows](GUIDE.md#install-windows) |
| Windows Boot Manager: "The Boot Configuration Data for your PC is missing or contains errors", `\EFI\Microsoft\Boot\BCD`, status 0xc000000d, while the installer starts | the installer loaded but could not read its own files from the CD. The VM [Declare a first VM without a GPU](GUIDE.md#declare-a-first-vm-without-a-gpu) shows installs Windows 11 25H2 cleanly, so the cause is in the ISO or in what differs from that VM | compare the ISO's SHA-256 with the one Microsoft shows on its download page, and try the VM exactly as the guide declares it. If it still fails, open an issue with `virsh -c qemu:///system dumpxml <name>` and `/var/log/libvirt/qemu/<name>.log` |
| A UEFI shell with no disk at all | the VM does not run on the stealth firmware, or setup needs a driver for its disk | leave the firmware to the module, with no path set by hand; a virtio disk needs the virtio-win storage driver in setup. `bootCheck` boots the same QEMU and firmware from SATA, virtio and CD and shows where a boot stops |
| A black screen before Windows | as above | build `bootCheck` and read its serial logs |
| The VM sometimes hangs before Windows loads | Windows stalls when its vCPUs share host CPUs | pin each vCPU to a host CPU of its own with `pinning`, and `emulator` on other CPUs |
| Windows hangs at boot with `cpuidPassthrough.enable` | the VM has fewer vCPUs than the host has threads | give it as many vCPUs, or turn it off |
| Windows crashes early in boot | `kvmPvEnforceCpuid` is on | turn it off |
| With VBS or Memory integrity, Windows falls into Automatic Repair or stops at the logo on an Intel host | Windows' own Hyper-V does not start while the guest sees CET | keep `cet` at its default, off on Intel |
| With VBS or Memory integrity, a black screen with a passed-through GPU | VBS needs DMA protection, which only an IOMMU in the VM gives | set the VM's `iommu = true` |
| Display corruption with a large GPU | the 64-bit PCI window is too small for the card | raise `pciMmio64Mb` |

## Detection results

A detection tool still finding the VM usually means a setting is left at its
default. [Read a VMAware result](GUIDE.md#read-a-vmaware-result) lists what
each VMAware technique means and the setting that removes it, and
`verify-stealth.ps1` names each check that still fails, as
[Check from inside Windows](GUIDE.md#check-from-inside-windows) shows.

## Performance

| You see | Why | Fix |
|---|---|---|
| Games in the VM run slower | `timing.enable` traps RDTSC in every VM on the host | turn it off if no game you run checks timing; it then hides no exit time from any VM on the host |
| Games on the host run slower | `kernelParams.maxCState` keeps every host core out of deep idle, which can cost boost | raise it |
| The VM feels slow everywhere | its vCPUs share host CPUs, or a scheduler daemon lowers QEMU's priority | pin it as [CPU pinning](GUIDE.md#cpu-pinning) shows, and keep QEMU at normal priority |

## Logs

- `/var/log/libvirt/qemu/<name>.log`: QEMU's own output for the VM.
- `journalctl -b -u libvirtd`: libvirt itself, and the hook's `refusing to start` lines.
- `journalctl -b -u nixvirt`: defining the declared VMs at each rebuild.
- `sudo vfio-stealth-verify-host <name>`: the host's kernel parameters, the QEMU binary and the VM's definition.
- `bootCheck`'s `result/serial/`: what each test guest printed, as
  [Check the build with bootCheck](GUIDE.md#check-the-build-with-bootcheck) shows.
