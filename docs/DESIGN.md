# Design

How the parts fit and why each is built the way it is. Every option with its
type and default is in [OPTIONS.md](OPTIONS.md).

## How the parts fit

```text
nixpkgs           QEMU            OVMF (EDK2)        swtpm, libtpms    libvirt
                    |                 |                    |              |
AutoVirt          QEMU patch      EDK2 patch               |              |
                    |                 |                    |              |
this repo         qemu/ patches   ovmf/post-patch.nix  libtpms identity   |
                    |                 |                    |              |
module.nix        packages.qemu   packages.ovmf        libvirt's swtpm    |
                    |                 |                    |              |
                    +-----------------+--------------------+              |
                                      |                                   |
                            domains.<name>, domain.nix                    |
                                      |                                   |
NixVirt                          domain XML, defined in libvirt ----------+
                                      |
guest                        Windows, or bootCheck's probe guests
```

| Part | Who keeps it | Its job here |
| - | - | - |
| QEMU, OVMF, libvirt, swtpm | nixpkgs | the base every package overrides |
| [vendor/autovirt/](../vendor/autovirt) | AutoVirt, an outside project | its QEMU and EDK2 patches, vendored and ported here, never fetched; [AUTOVIRT.md](AUTOVIRT.md) says what is kept |
| [qemu/](../qemu), [ovmf/](../ovmf) post-patches and patches | this repo | correct AutoVirt where it breaks a boot or gives the VM away, and inject the identity options |
| [module.nix](../module.nix), [domain.nix](../domain.nix), [lib.nix](../lib.nix) | this repo | turn the options into packages, host settings and VMs |
| NixVirt | an outside project, a pinned flake input | writes the domain XML and defines it in libvirt |
| checks and `bootCheck` | this repo | prove the result in the source and inside a booted guest |

| Part | What it does | Where |
| - | - | - |
| Host kernel patches | Rewrite KVM's SVM code for TSC compensation and CPUID handling, and with `instructionFixes` make VMCALL and VMMCALL on both vendors, and the SVM instructions and ICEBP on AMD, behave as on bare metal; the caller builds its kernel through `packages.kernelFor` | [kernel/](../kernel), `kernelPostPatch` and `packages.kernelFor` in [module.nix](../module.nix) |
| QEMU and OVMF pair | QEMU and firmware with one vendor's AutoVirt patches, this repo's corrections and the configured identity | [qemu/](../qemu), [ovmf/](../ovmf), [lib/](../lib), [vendor/autovirt/](../vendor/autovirt) |
| VMs | Libvirt features, CPU flags, clock, SMBIOS, ACPI tables, QEMU arguments, pinning, huge pages and passed-through devices, rendered into each declared VM | [lib.nix](../lib.nix), [domain.nix](../domain.nix), [render.nix](../render.nix), [smbios/](../smbios), [acpi/](../acpi), `domains`, `domain` and `packages` in [module.nix](../module.nix) |
| Host layer | VFIO modules, kernel parameters, udev rules and the libvirt QEMU hook that binds GPUs, allocates huge pages, unmounts disks and isolates CPUs at start and stop | [host/](../host), `host`, `hugepages`, `kvmfr`, `evdev`, `pinning` in [module.nix](../module.nix) |
| Guest checks | Report from inside a guest which detection vectors still fire | [verify/](../verify), [detect/](../detect), [guest/](../guest) |

## QEMU and OVMF are one pair, picked by cpuVendor

- AutoVirt ships one QEMU patch and one EDK2 patch per CPU vendor. Both edit the same chipset and PCI identity, one from each side.
- OVMF reads that identity at boot: its platform init asserts on the host bridge ID and probes the power management base on the LPC bridge.
- `cpuVendor` picks the AMD or the Intel build of both, `packages.qemu` and `packages.ovmf`, from one value, so the pair cannot be mixed.
- libvirt picks UEFI firmware from the descriptors in its QEMU's `share/qemu/firmware`. `packages.libvirtQemu` is the chosen QEMU carrying only the module's descriptors for `ovmf-stealth`, with and without the Microsoft keys, and the module sets it as libvirt's QEMU with `mkDefault`, so a QEMU the host configuration names wins.
- A declared VM names the firmware and its variable template itself. A VM defined by hand that asks only for `firmware="efi"` gets `ovmf-stealth` from the descriptors.
- Both descriptors are the Secure Boot build. The module offers no build without Secure Boot.

## The chipset stays Intel ICH9 at stock addresses

- q35 emulates an Intel ICH9 chipset.
- The AMD patch gives the LPC bridge, SMBus and AHCI AMD FCH device IDs. The AMD GPU driver then takes an AMD platform path and stops Windows with bug check 0x113 on q35. The device IDs go back to ICH9.
- Vendor and revision go back with the IDs: an ICH9 device ID beside the AMD vendor or an FCH revision is a pair no board carries.
- The host bridge keeps ID 0x29c0, which OVMF's platform init asserts on.
- The AMD patch moves LPC, SATA and SMBus from slot 0x1f to 0x14. They stay at 0x1f, where q35, the Intel patch and stock OVMF put them.
- OVMF's power management base goes back to 0x1f function 0 to match, and the ACPI names LPCB, SAT1 and SBUS follow the devices to 0x1f.
- The three move together or not at all: firmware and guests find a slot through its function 0, so SATA and SMBus left at 0x14 without LPC beside them are never enumerated.

## ACPI looks like one board's firmware

- AutoVirt gives PCI devices board names in place of QEMU's `S` and slot number, but only on the device objects. The hotplug scopes, notifications and empty slots kept the old names, which pointed at nothing, and the guest kernel logged ACPI errors. [qemu/acpi-pci-names.patch](../qemu/acpi-pci-names.patch) names all of them through one function.
- AutoVirt removes QEMU's CPU hotplug code from the DSDT, and with it every processor object. `acpiProcessors` builds an SSDT per VM with one processor device per vCPU under a processor container, as real firmware does. CPU hotplug stays gone.
- OVMF installs tables of its own, which carried `INTEL` and `EDK2` while QEMU's carried the configured OEM. `acpiOem` goes into both.

## One setting feeds every layer

- The module builds every package from the options: the description of `packages` in [OPTIONS.md](OPTIONS.md) names the options each of QEMU, OVMF, the Secure Boot variables, the SMBIOS cache tables and the ACPI tables takes. libtpms and swtpm take `tpm`, and the VM parts `smbios` and the rest.
- A guest can read one identity through several layers. `smbios.manufacturer` names the system, the baseboard, the chassis and, by default, the TPM platform certificate and the Platform Key.
- A value set once cannot disagree between layers, and no option is a record the caller copies into a package override by hand.

## Unique values come from a private seed

- A default that every install shares is a fingerprint of this module, however real it looks. Values a real part shares with every board of its kind, such as AMI's placeholder strings, stay fixed defaults; values unique to one real part, its serials, are derived per host from `identity.seed` in [identity.nix](../identity.nix).
- Each derived value takes the form that kind of part reports: digits for a board serial, the maker's prefix for a disk serial, hex digits for a memory module, a version 4 UUID for a VM. A hash keeps them stable across rebuilds and unrelated between hosts.
- The seed has no default: the module cannot pick a secret for the user, and one it picked would be the same everywhere. Without it the shared values stay and each one warns.

## VMs are declared in Nix and defined through NixVirt

- A VM's disks, passthrough devices and memory belong to one host, so they are options under `domains`. [domain.nix](../domain.nix) adds what makes the VM read as hardware and renders the result in NixVirt's format.
- NixVirt is used for the XML and for defining it, nothing else. Its NixOS module, which `nixosModules.default` imports beside this one and `nixosModules.vfio-stealth` leaves to the caller, hands it the whole list of VMs on `qemu:///system`: it deletes a VM that is not on the list, and powers off and restarts a running VM whose definition changed.
- `bootCheck` renders its probe VMs through the same [domain.nix](../domain.nix) and has libvirt translate them, so the check boots what a declared VM boots.
- `domain` keeps the same parts for a VM defined by hand. The caller places them in its own definition and leaves out the devices `devicesToRemove` names. The module adds `domain.warnings` to the system's warnings.
- AutoVirt turns QEMU's SMBIOS defaults off, so a VM in SMBIOS emulate mode would show blank board strings. The BIOS, system and board strings go into the QEMU arguments as well as the sysinfo block. Without the defaults QEMU also leaves out every required table: OVMF reads QEMU's tables until it meets the end-of-table, past their end into whatever memory follows, and type 17 names a memory array that is not there. The QEMU build adds back the required tables that carry no string: the memory array, its address map, the boot status and the end-of-table.
- OVMF's `X-PciMmio64Mb` sizes only the firmware's 64-bit PCI window. The OS reads the window QEMU's q35 host describes, so `pciMmio64Mb` sets `pci-hole64-size` as well.
- NixVirt writes a USB vendor or product id as a decimal integer. libvirt reads it right, but its schema takes at most four digits, so [render.nix](../render.nix) writes the ids in hex.
- A VM's own `cpuIdentity`, `cache`, `hypervMode` and `kvmPvEnforceCpuid` replace the host's for that VM alone: the parts are built per VM, with its own SMBIOS cache tables.

## The host layer acts through one QEMU hook

- What a passthrough host needs beyond libvirt, VFIO modules, kernel parameters, udev rules and the work at VM start and stop, applies only with `host.enable`. A setting that needs it without it is refused by name, never ignored.
- The hook is one packaged script, [host/qemu-hook.sh](../host/qemu-hook.sh), installed through `virtualisation.libvirtd.hooks.qemu` into `qemu.d`, beside any hook of the caller's own, and only while `domains` declares a VM. It acts on `prepare begin` and `release end` only.
- [host/plan.nix](../host/plan.nix) renders what each VM needs as JSON at evaluation. No Nix runs at VM start.
- At start it checks the protected disks, then unmounts, allocates huge pages, binds the GPU and confines the host's CPUs, in that order. A refusal undoes the steps already done, and the error libvirt shows carries the hook's reason.
- A hook must not call back into libvirt, which waits for it; `virsh` from a hook can deadlock the daemon. The lock that lets one pinned VM run at a time under `pinning.isolate` is a file under `/run/vfio-stealth`, not a query of other VMs' state.
- The disk check reads `/proc/self/mountinfo` and sysfs, following device mapper to the disks beneath, instead of asking `lsblk` and `findmnt`. `SYSFS_ROOT`, `PROC_ROOT` and `RUN_ROOT` move those roots, so the `qemu-hook` check runs the real script on a fake tree.
- The hook adds a VM's huge pages to the pool and takes back the same count, so VMs with huge pages can run together.
- With `kvmfr.enable`, the ivshmem device is backed by `/dev/kvmfr0` through QEMU arguments: libvirt's `shmem` element can only back it with a file in `/dev/shm`, which Looking Glass reads without kvmfr.
- `packages.kernelFor` patches a kernel the caller names. The module does not patch `boot.kernelPackages` itself: a definition of that option that reads the option's own value is an infinite recursion.

## The module owns libvirt's QEMU and swtpm

- The module sets kernel parameters, libvirt's QEMU, and libvirt's swtpm built with the patched libtpms.
- What a guest reads from the TPM itself, the manufacturer, vendor strings and firmware version, is compiled into libtpms, so `tpm` rebuilds it.
- swtpm reads `swtpm-localca.options`, which names the TPM in the certificates, from its own package and never from `/etc`. The options are built into the swtpm package.
- NixVirt's own `swtpm.enable` sets libvirt's swtpm to a stock one at normal priority, over the module's default.

## The Secure Boot keys are generated per host

- The Microsoft variable template OVMF can build enrolls a Debian Platform Key, which no board carries.
- `packages.secureBootVars` enrolls the Microsoft KEK and db under a Platform Key generated at build time and named by `secureBoot.platformKeyName`. Its private half is not kept, so nothing can sign with it.
- The revocation list is the x64 dbx Microsoft publishes, signed by its KEK 2023, pinned in `version.json`. Without it the template holds virt-firmware's one placeholder entry, which no board ships.

## Kernel-dependent Hyper-V features default off

- `vendor_id` and `relaxed` are libvirt and QEMU settings with no KVM capability behind them. They default on.
- Every other enlightenment needs a `KVM_CAP_HYPERV_*` capability, which KVM offers only when the host kernel has `CONFIG_KVM_HYPERV=y`. libvirt refuses to start a VM that requests one the kernel lacks, so they default off.
- `hypervclock` needs the same kernel switch. The clock carries it only when a kernel-dependent feature is on.
- `kernelCapabilities` states what the host kernel provides. `null` trusts every request.
- An attrset is intersected with the request: a requested feature it does not allow is left out of the domain and named in `domain.warnings`. A key left out counts as unsupported.
- [lib/kernel-capabilities.nix](../lib/kernel-capabilities.nix) parses a kernel `.config`, but evaluation cannot read the running kernel's `/proc/config.gz`. The set is written by hand, and the parser is not a flake output.

## timing.enable acts on every VM of the host

- The kernel patches compile into the host kernel's KVM. There is no per-VM switch.
- Every SVM guest on the host traps RDTSC and RDTSCP, and each read costs a VM exit.
- The timing patch edits `arch/x86/kvm/svm/svm.c` and KVM's common code beside it: `x86.c` or `msrs.c` and `include/linux/kvm_host.h`. The common edits rely on what the SVM edits do, the TSC read on the exit stamps only `svm.c` takes, so `kvm-intel` would run half a patch. An assertion refuses `timing.enable` with `cpuVendor` `"intel"`, and so `cpuidSpoof` and `cpuidPassthrough`, which edit `svm.c` alone.
- `instructionFixes` is not refused on Intel: its vfio-native 0002 and 0003 edit `emulate.c` and `x86.c`, which `kvm-intel` runs as well, and apply on both vendors. Its 0001, 0004 and the #GP mapping in [kernel/svm-instruction-fixes.nix](../kernel/svm-instruction-fixes.nix) edit `svm.c` and apply on AMD only.

## The hidden time runs from an exit to the next entry

- Each VM exit stamps the TSC as it returns to the host. When the guest is entered again after a CPUID, RDTSC, RDTSCP, WBINVD, XSETBV or INVD exit, or a guest read of the TSC MSR, the time since that stamp joins the hidden time.
- RDTSC, RDTSCP and the TSC MSR answer the TSC of their own exit less the hidden time, so the guest never sees the handling of those exits.
- The stamps sit in `svm_vcpu_enter_exit`, which every entry passes, so the CPUID leaf 0 fast path of the cpuid patch is hidden too.
- BetterTiming upstream stamps before entering the guest instead. That also hides the guest's own run time before each such exit, so a guest that reads the TSC in a loop sees it stand still. The first port hid only the time inside each handler.
- What stays visible is the hardware's own exit and entry, and under nested virtualization the outer hypervisor's work.

## QEMU follows the vendored patches

- An AutoVirt patch fits one QEMU series.
- `qemu-stealth` builds on nixpkgs' QEMU while its series has a vendored patch. Otherwise it builds a release tarball: the newest patched series when nixpkgs is newer or unpatched, the floor when nixpkgs is older.
- The floor is the oldest QEMU known to boot OVMF with these patches.
- A nixpkgs bump past the patches keeps building at the ceiling. Vendoring a newer patch and its tarball hash raises the ceiling with no other change.
- Patches are vendored, not fetched. A build does not depend on a third-party fork staying online, and every patch is read before it is used.

## Patches carry their own checks

- Every AutoVirt patch and every patch of this repo applies with zero fuzz. A hunk placed by fuzz can land in the wrong function and still build.
- Each edit after it asserts its result with the standard's `patchAssertions`: `landed` for text that must appear, `gone` beside `present` for text that must vanish, `exactly_one` for an insertion anchor. An edit that matches nothing fails the build. The deliberate exceptions are in [SED-CATALOG.md](SED-CATALOG.md).
- `kernelPostPatch` starts with [kernel/prelude.nix](../kernel/prelude.nix), its own `landed`, `gone` and `exactly_one`, because it runs inside the caller's kernel build, where the standard's library is absent.
- The sed contracts replay the real post-patch scripts on the source each package builds. The kernel checks run the real kernel scripts on current kernel sources. The boot checks read the result from inside a booted guest. [DEVELOPMENT.md](DEVELOPMENT.md) lists every check.
