# Design

How the parts fit together, and why each part is built the way it is.
[OPTIONS.md](OPTIONS.md) lists every option with its type and default.

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
| QEMU, OVMF, libvirt, swtpm | nixpkgs | the base that every package here overrides |
| [vendor/autovirt/](../vendor/autovirt) | AutoVirt, an outside project | its QEMU and EDK2 patches, vendored and ported here, never fetched; [AUTOVIRT.md](AUTOVIRT.md) says what is kept |
| [qemu/](../qemu), [ovmf/](../ovmf) post-patches and patches | this repo | fix AutoVirt where it breaks a boot or gives the VM away, and add the identity options |
| [module.nix](../module.nix), [domain.nix](../domain.nix), [lib.nix](../lib.nix) | this repo | turn the options into packages, host settings and VMs |
| NixVirt | an outside project, a pinned flake input | writes the domain XML and defines it in libvirt |
| checks and `bootCheck` | this repo | prove the result in the source and inside a booted guest |

| Part | What it does | Where |
| - | - | - |
| Host kernel patches | Rewrite KVM's SVM code for TSC compensation and CPUID handling. With `instructionFixes`, VMCALL and VMMCALL on both vendors, and the SVM instructions and ICEBP on AMD, behave as on bare metal. The caller builds its kernel through `packages.kernelFor` | [kernel/](../kernel), `kernelPostPatch` and `packages.kernelFor` in [module.nix](../module.nix) |
| QEMU and OVMF pair | QEMU and firmware built with the AutoVirt patches for one vendor, this repo's fixes and the configured identity | [qemu/](../qemu), [ovmf/](../ovmf), [lib/](../lib), [vendor/autovirt/](../vendor/autovirt) |
| VMs | Put libvirt features, CPU flags, clock, SMBIOS, ACPI tables, QEMU arguments, pinning, huge pages and passed-through devices into each declared VM | [lib.nix](../lib.nix), [domain.nix](../domain.nix), [render.nix](../render.nix), [smbios/](../smbios), [acpi/](../acpi), `domains`, `domain` and `packages` in [module.nix](../module.nix) |
| Host layer | VFIO modules, kernel parameters, udev rules, and the libvirt QEMU hook. At VM start and stop the hook binds GPUs, allocates huge pages, unmounts disks and isolates CPUs | [host/](../host), `host`, `hugepages`, `kvmfr`, `evdev`, `pinning` in [module.nix](../module.nix) |
| Guest checks | Report, from inside a guest, which detection vectors still fire | [verify/](../verify), [detect/](../detect), [guest/](../guest) |

## QEMU and OVMF are one pair, picked by cpuVendor

- AutoVirt ships one QEMU patch and one EDK2 patch for each CPU vendor. Both patches change the same chipset and PCI identity, one from each side.
- OVMF reads that identity at boot. Its platform init asserts on the host bridge ID, and it probes the power management base on the LPC bridge.
- `cpuVendor` picks the AMD or the Intel build of both packages, `packages.qemu` and `packages.ovmf`. It is one value, so the pair cannot be mixed.
- libvirt picks UEFI firmware from the descriptors in its QEMU's `share/qemu/firmware`. `packages.libvirtQemu` is the chosen QEMU, and it carries only the module's descriptors for `ovmf-stealth`, with and without the Microsoft keys. The module sets it as libvirt's QEMU with `mkDefault`, so a QEMU that the host configuration names wins.
- A declared VM names its firmware and its variable template itself. A VM defined by hand that asks only for `firmware="efi"` gets `ovmf-stealth` from the descriptors.
- Both descriptors describe the Secure Boot build. The module offers no build without Secure Boot.

## The chipset stays Intel ICH9 at stock addresses

- q35 emulates an Intel ICH9 chipset.
- The AMD patch gives the LPC bridge, SMBus and AHCI the device IDs of an AMD FCH. The AMD GPU driver then takes an AMD platform path, and on q35 it stops Windows with bug check 0x113. So the device IDs go back to ICH9.
- Vendor and revision go back together with the IDs. No real board has an ICH9 device ID next to the AMD vendor or next to an FCH revision.
- The host bridge keeps ID 0x29c0, because OVMF's platform init asserts on it.
- The AMD patch moves LPC, SATA and SMBus from slot 0x1f to 0x14. Here they stay at 0x1f, where q35, the Intel patch and stock OVMF put them.
- To match, OVMF's power management base goes back to 0x1f function 0. The ACPI names LPCB, SAT1 and SBUS follow the devices to 0x1f.
- The three devices move together or not at all. Firmware and guests find a slot through its function 0. If SATA and SMBus stay at 0x14 without LPC next to them, they are never enumerated.

## ACPI looks like one board's firmware

- AutoVirt gives PCI devices board names instead of QEMU's `S` and slot number, but only on the device objects. The hotplug scopes, notifications and empty slots kept the old names. Those names pointed at nothing, and the guest kernel logged ACPI errors. [qemu/acpi-pci-names.patch](../qemu/acpi-pci-names.patch) names all of them through one function.
- AutoVirt removes QEMU's CPU hotplug code from the DSDT, and every processor object goes with it. `acpiProcessors` builds one SSDT per VM, with one processor device per vCPU under a processor container, as real firmware does. CPU hotplug stays removed.
- OVMF installs its own tables. They carried `INTEL` and `EDK2`, while QEMU's tables carried the configured OEM. `acpiOem` goes into both.

## One setting feeds every layer

- The module builds every package from the options. The description of `packages` in [OPTIONS.md](OPTIONS.md) names the options that each package takes: QEMU, OVMF, the Secure Boot variables, the SMBIOS cache tables and the ACPI tables. libtpms and swtpm take `tpm`. The VM parts take `smbios` and the rest.
- A guest can read the same identity through several layers. `smbios.manufacturer` names the system, the baseboard, the chassis and, by default, the TPM platform certificate and the Platform Key.
- A value is set once, so it cannot differ between layers. No option is a record that the caller copies into a package override by hand.

## Unique values come from a private seed

- A default that every install shares is a fingerprint of this module, even when it looks real. Some values are shared by a real part with every board of its kind, such as AMI's placeholder strings. These stay fixed defaults. Other values are unique to one real part, such as its serials. These are derived per host from `identity.seed` in [identity.nix](../identity.nix).
- Each derived value has the form that this kind of part reports: digits for a board serial, the maker's prefix for a disk serial, hex digits for a memory module, and a version 4 UUID for a VM. A hash keeps the values stable across rebuilds and unrelated between hosts.
- The seed has no default. The module cannot choose a secret for the user, and a secret it chose would be the same everywhere. Without a seed, the shared values stay, and each one gives a warning.

## VMs are declared in Nix and defined through NixVirt

- A VM's disks, passthrough devices and memory belong to one host, so they are options under `domains`. [domain.nix](../domain.nix) adds what makes the VM look like hardware, and renders the result in NixVirt's format.
- NixVirt is used only to write the XML and to define it. Its NixOS module gets the whole list of VMs on `qemu:///system`. `nixosModules.default` imports that module next to this one, and `nixosModules.vfio-stealth` leaves it to the caller. NixVirt deletes a VM that is not on the list. It powers off and restarts a running VM whose definition changed.
- `bootCheck` renders its probe VMs through the same [domain.nix](../domain.nix) and lets libvirt translate them. So the check boots the same thing that a declared VM boots.
- `domain` gives the same parts for a VM defined by hand. The caller puts them into its own definition and leaves out the devices that `devicesToRemove` names. The module adds `domain.warnings` to the system's warnings.
- AutoVirt turns off QEMU's SMBIOS defaults, so a VM in SMBIOS emulate mode would show empty board strings. For this reason the BIOS, system and board strings go into the QEMU arguments as well as into the sysinfo block. Without the defaults, QEMU also leaves out every required table. OVMF reads QEMU's tables until it finds the end-of-table, so it reads past their end into whatever memory follows. Also, type 17 names a memory array that does not exist. The QEMU build adds back the required tables that carry no string: the memory array, its address map, the boot status and the end-of-table.
- OVMF's `X-PciMmio64Mb` sets the size of the firmware's 64-bit PCI window only. The OS reads the window that QEMU's q35 host describes. So `pciMmio64Mb` also sets `pci-hole64-size`.
- NixVirt writes a USB vendor or product id as a decimal integer. libvirt reads it correctly, but its schema allows at most four digits. So [render.nix](../render.nix) writes the ids in hex.
- A VM's own `cpuIdentity`, `cache`, `hypervMode` and `kvmPvEnforceCpuid` replace the host's values for that VM only. The parts are built per VM, with the VM's own SMBIOS cache tables.

## The host layer acts through one QEMU hook

- A passthrough host needs more than libvirt: VFIO modules, kernel parameters, udev rules and the work at VM start and stop. All of this applies only with `host.enable`. A setting that needs it, set without it, is refused by name. It is never ignored.
- The hook is one packaged script, [host/qemu-hook.sh](../host/qemu-hook.sh). It is installed through `virtualisation.libvirtd.hooks.qemu` into `qemu.d`, next to any hook the caller has. It is installed only while `domains` declares a VM. It acts only on `prepare begin` and `release end`.
- [host/plan.nix](../host/plan.nix) renders what each VM needs as JSON at evaluation time. No Nix runs when a VM starts.
- At start, the hook first checks the protected disks. Then it unmounts, allocates huge pages, binds the GPU and confines the host's CPUs, in that order. If it refuses, it undoes the steps it already did, and the error that libvirt shows contains the hook's reason.
- A hook must not call back into libvirt, because libvirt waits for the hook. Calling `virsh` from a hook can deadlock the daemon. Under `pinning.isolate` only one pinned VM can run at a time. The lock for this is a file under `/run/vfio-stealth`, not a query of other VMs' state.
- The disk check reads `/proc/self/mountinfo` and sysfs, and follows device mapper to the disks below it. It does not ask `lsblk` and `findmnt`. `SYSFS_ROOT`, `PROC_ROOT` and `RUN_ROOT` move those roots, so the `qemu-hook` check can run the real script on a fake tree.
- The hook adds a VM's huge pages to the pool, and later takes back the same count. So VMs with huge pages can run at the same time.
- With `kvmfr.enable`, the ivshmem device is backed by `/dev/kvmfr0` through QEMU arguments. libvirt's `shmem` element can only back it with a file in `/dev/shm`, which Looking Glass reads without kvmfr.
- `packages.kernelFor` patches a kernel that the caller names. The module does not patch `boot.kernelPackages` itself, because a definition of that option that reads the option's own value is an infinite recursion.

## The module owns libvirt's QEMU and swtpm

- The module sets kernel parameters, libvirt's QEMU, and libvirt's swtpm built with the patched libtpms.
- Some things a guest reads from the TPM itself are compiled into libtpms: the manufacturer, the vendor strings and the firmware version. So `tpm` rebuilds libtpms.
- swtpm reads `swtpm-localca.options`, which names the TPM in the certificates. It reads this file from its own package, never from `/etc`. So the options are built into the swtpm package.
- NixVirt's own `swtpm.enable` sets libvirt's swtpm to a stock one at normal priority. This wins over the module's default.

## The Secure Boot keys are generated per host

- OVMF can build a Microsoft variable template, but that template enrolls a Debian Platform Key. No real board has that key.
- `packages.secureBootVars` enrolls the Microsoft KEK and db under a Platform Key that is generated at build time and named by `secureBoot.platformKeyName`. Its private half is not kept, so nothing can sign with it.
- The revocation list is the x64 dbx that Microsoft publishes, signed by its KEK 2023 and pinned in `version.json`. Without it, the template holds the one placeholder entry from virt-firmware, which no board ships.

## Kernel-dependent Hyper-V features default off

- `vendor_id` and `relaxed` are libvirt and QEMU settings with no KVM capability behind them. They are on by default.
- Every other enlightenment needs a `KVM_CAP_HYPERV_*` capability. KVM offers it only when the host kernel has `CONFIG_KVM_HYPERV=y`. libvirt refuses to start a VM that requests one that the kernel does not have. So these are off by default.
- `hypervclock` needs the same kernel switch. The clock has it only when a kernel-dependent feature is on.
- `kernelCapabilities` states what the host kernel provides. `null` trusts every request.
- An attrset is intersected with the request. A requested feature that it does not allow is left out of the domain and named in `domain.warnings`. A missing key counts as unsupported.
- [lib/kernel-capabilities.nix](../lib/kernel-capabilities.nix) parses a kernel `.config`. But evaluation cannot read the running kernel's `/proc/config.gz`. So the set is written by hand, and the parser is not a flake output.

## timing.enable acts on every VM of the host

- The kernel patches are compiled into the host kernel's KVM. There is no per-VM switch.
- Every SVM guest on the host traps RDTSC and RDTSCP, and each read costs a VM exit.
- The timing patch edits `arch/x86/kvm/svm/svm.c` and the common KVM code next to it: `x86.c` or `msrs.c`, and `include/linux/kvm_host.h`. The common edits depend on what the SVM edits do: the TSC read on the exit stamps, which only `svm.c` takes. So `kvm-intel` would run only half of the patch. An assertion refuses `timing.enable` with `cpuVendor` `"intel"`. For the same reason it refuses `cpuidSpoof` and `cpuidPassthrough`, which edit only `svm.c`.
- `instructionFixes` is not refused on Intel. Its vfio-native 0002 and 0003 edit `emulate.c` and `x86.c`, which `kvm-intel` also runs, so they apply on both vendors. Its 0001, 0004 and the #GP mapping in [kernel/svm-instruction-fixes.nix](../kernel/svm-instruction-fixes.nix) edit `svm.c` and apply on AMD only.

## The hidden time runs from an exit to the next entry

- Each VM exit stamps the TSC as it returns to the host. The guest can be entered again after a CPUID, RDTSC, RDTSCP, WBINVD, XSETBV or INVD exit, or after a guest read of the TSC MSR. In that case the time since that stamp is added to the hidden time.
- RDTSC, RDTSCP and the TSC MSR return the TSC of their own exit minus the hidden time. So the guest never sees the time spent handling those exits.
- The stamps are in `svm_vcpu_enter_exit`, which every entry passes through. So the CPUID leaf 0 fast path of the cpuid patch is hidden too.
- BetterTiming upstream takes the stamp before it enters the guest instead. That also hides the guest's own run time before each such exit, so a guest that reads the TSC in a loop sees it stand still. The first port hid only the time inside each handler.
- What stays visible is the hardware's own exit and entry and, under nested virtualization, the work of the outer hypervisor.

## QEMU follows the vendored patches

- An AutoVirt patch fits one QEMU series.
- `qemu-stealth` builds on nixpkgs' QEMU while there is a vendored patch for its series. Otherwise it builds from a release tarball: the newest patched series when nixpkgs is newer or unpatched, and the floor when nixpkgs is older.
- The floor is the oldest QEMU known to boot OVMF with these patches.
- When nixpkgs moves past the patches, the build stays at the ceiling. Vendoring a newer patch and its tarball hash raises the ceiling, with no other change.
- Patches are vendored, not fetched. So a build does not depend on a third-party fork staying online, and every patch is read before it is used.

## Patches carry their own checks

- Every AutoVirt patch and every patch of this repo applies with zero fuzz. A hunk placed by fuzz can land in the wrong function and still build.
- Each edit after the patch checks its result with the standard's `patchAssertions`: `landed` for text that must appear, `gone` together with `present` for text that must disappear, and `exactly_one` for an insertion anchor. An edit that matches nothing fails the build. [SED-CATALOG.md](SED-CATALOG.md) lists the deliberate exceptions.
- `kernelPostPatch` starts with [kernel/prelude.nix](../kernel/prelude.nix), which has its own `landed`, `gone` and `exactly_one`. It needs its own because it runs inside the caller's kernel build, where the standard's library is not available.
- The sed contracts replay the real post-patch scripts on the source that each package builds. The kernel checks run the real kernel scripts on current kernel sources. The boot checks read the result from inside a booted guest. [DEVELOPMENT.md](DEVELOPMENT.md) lists every check.
