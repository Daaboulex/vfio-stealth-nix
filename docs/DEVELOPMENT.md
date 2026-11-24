# Development

For someone changing this repository. Why the parts are built the way they
are is in [DESIGN.md](DESIGN.md).

## Dev shell

- `nix develop` enters the dev shell of nix-packaging-standard and installs its pre-commit hooks.
- `nix fmt` formats the tree.
- The hooks skip [vendor/](../vendor), and shfmt skips [guest/](../guest).
- The stealth stack builds on `x86_64-linux` only. On `aarch64-linux` the flake declares `stealth-detect` and the checks that need no x86 host.

## Checks

`nix flake check` runs all of them. The standard adds its own `package-*`,
`std-*` and `pre-commit` checks, which its README describes.

| Check | Kind | What it proves |
| - | - | - |
| `module-eval-nixos` | eval | The module evaluates in a NixOS system with the identity placeholders replaced, the host layer with most of its options, and two domains: one with pinning, huge pages, a GPU bound by the hook with a ROM, USB, unmount, Looking Glass and most per-domain overrides, one with a GPU bound at boot |
| `vmaware-not-shipped` | eval and derivation walk | A system with the host layer, kvmfr, the Looking Glass client, evdev and a domain with a hook-bound GPU and huge pages has no VMAware derivation anywhere in its derivation closure, which its QEMU is found in; nothing of the system is built |
| `module-eval-own-nixvirt` | eval | `nixosModules.vfio-stealth` evaluates with a declared domain in a system that imports NixVirt's module itself |
| `module-assertions` | eval | The module's assertions and option types refuse the settings they guard against, and accept a valid one |
| `identity-seed` | eval | With `identity.seed`, every unique value left unset is derived in its real form: fifteen board serial digits, a WD-WCC disk serial for the default model and twelve hex digits for another, twelve hex digits of Hyper-V vendor id, a nonzero EDID serial number, five battery digits, a version 4 UUID per VM, and eight hex digits for each populated memory slot in the slot table QEMU is built with; QEMU and the battery table are built with them, a second seed changes every one, a value set by hand wins, and `perDomainSerials` follows the seed. Without a seed the rebuild warns about each shared value and about unset cache sizes |
| `option-combinations` | eval | Combinations of the module's mixable switches, generated with `host.enable` on whenever a chosen value needs it, so that every pair of values sits in a combination the assertions accept; each accepted one evaluates its system and every domain's XML with no warning, and a refused one is logged with its assertion and fails the check when it leaves a pair untested |
| `guide-snippets` | doc check | Every `nix` block of [README.md](../README.md), [GUIDE.md](GUIDE.md) and [QUICKSTART.md](QUICKSTART.md) has a copy in [tests/snippets/](../tests/snippets), the files the evaluation imports, and matches it; each parses, and each block that sets `virtualisation.vfio-stealth` evaluates with no failed assertion on top of the blocks before it in its file, a later block's values replacing an earlier one's |
| `examples` | eval | Every module in [examples/](../examples), [configuration.nix](../examples/configuration.nix), a passthrough host whose kernel is built through `packages.kernelFor`, and [hardened-gaming.nix](../examples/hardened-gaming.nix), evaluates with no failed assertion, every domain they declare passes libvirt's schema, and [examples/flake.nix](../examples/flake.nix) parses |
| `domain-render` | eval and schema, both systems | Domains using pinning, huge pages, a GPU in each binding, a ROM, USB, unmount, Looking Glass on shared memory and on kvmfr, evdev, a MAC, a machine type, per-domain serials from the seed, the VM's IOMMU, PipeWire sound and every per-domain override pass libvirt's schema, and their XML carries the vcpupin, emulatorpin and iothreadpin, the managed flag of each binding, the GPU's functions in one slot behind one root port, the ROM, the shmem or kvmfr device, the IOMMU with interrupt remapping and a QEMU IOAPIC, the HD Audio codec and its PipeWire backend, the huge page backing and the QEMU arguments each asks for; the host gets the vfio-pci ids, the hook, the USB udev rule and the evdev device ACL |
| `qemu-hook` | shell contract, both systems | The QEMU hook, run on a fake sysfs and proc tree, refuses a device that the root filesystem, a filesystem on device mapper or swap sits on, honours the unmount list, adds huge pages to the pool and takes them back at release, refuses a missing GPU function, a GPU a process holds open, two passed devices of one IOMMU group with `iommu`, and a second pinned VM under `pinning.isolate`, stops the running `stopServices` before the bind and starts them again at release, and ignores a VM the plan does not name |
| `sed-contract-qemu`, `sed-contract-qemu-intel` | source replay | The vendor's AutoVirt patch and [qemu/post-patch.nix](../qemu/post-patch.nix) apply to the QEMU source the package builds, after nixpkgs' own patches, and each edit's result is in the tree |
| `sed-contract-edk2`, `sed-contract-edk2-intel` | source replay | The vendor's EDK2 patch and [ovmf/post-patch.nix](../ovmf/post-patch.nix) apply to the OVMF source, and each edit's result is in the tree |
| `sed-contract-edk2-vendor` | source replay | The same with a firmware vendor and ACPI OEM other than the defaults, so an edit that matches only the default values fails |
| `autovirt-patch-contract` | Nix contract | The patch resolver picks the newest patch of a series by version order and refuses an unknown vendor or an unpatched series |
| `qemu-ceiling-contract` | Nix contract | The QEMU base is nixpkgs inside the patched band and a floor or ceiling tarball outside it; a missing hash or a ceiling below the floor is refused |
| `update-gap-contract` | shell contract | Which QEMU versions [scripts/update.sh](../scripts/update.sh) counts as covered or as a gap, and which release tag it reads as newest |
| `lib-output-contract` | Nix contract | `lib.mkStealthFeatures` returns the expected QEMU arguments, features, clock and sysinfo, including the Hyper-V intersection with `kernelCapabilities` and no `-cpu` argument |
| `sed-catalog-lean` | doc check | Every file [SED-CATALOG.md](SED-CATALOG.md) names exists and still rewrites text, and the catalog restates no anchor |
| `kernel-postpatch-fits-cachyos`, `kernel-postpatch-fits-upstream` | source replay | The `kernelPostPatch` of every combination of the kernel switches the module's assertions accept, generated by [tests/kernel-variants.nix](../tests/kernel-variants.nix), applies to the CachyOS and nixpkgs latest kernel sources, each edit asserted |
| `kernel-kvm-compiles-cachyos`, `kernel-kvm-compiles-upstream` | compile | Every combination compiles `arch/x86/kvm` with that kernel's own config |
| `acpi-oem` | build | Every SSDT of `acpi-ssdt-stealth` carries the configured OEM id and table id |
| `smbios-cache-associativity` | build | The generated SMBIOS type 7 tables carry the associativity byte of each default cache level |
| `smbios-extract` | build, both systems | `smbios-split` writes the same per-structure files from an `_SM3_` and an `_SM_` dump, drops the structures QEMU builds itself, and refuses a file that is no dump |
| `libvirt-firmware`, `libvirt-firmware-intel` | VM test | With the module on, libvirt offers only `ovmf-stealth`, a domain asking for `firmware="efi"` starts on it, and a VM under `domains` is defined by NixVirt and passes the domain checks of `vfio-stealth-verify-host` |
| `boot-smoke`, `boot-smoke-intel` | VM test | A q35 NixOS guest boots on `qemu-stealth` and `ovmf-stealth`; inside it the ACPI tables carry the configured OEM id, PCI subsystem ids are not QEMU's, the kernel logs no ACPI firmware error, the USB and ICH9 devices carry their board names, the ICH9 devices sit at 0x1f with ICH9 IDs and revisions, slot 0x14 is empty, and the SATA disk and CD answer ATA IDENTIFY and SCSI INQUIRY with one configured model and firmware |
| `boot-matrix`, `boot-matrix-hidden`, `boot-matrix-intel`, `boot-matrix-intel-hidden`, `boot-matrix-intel-hidden-nowaet` | VM test | The module option `bootCheck`, built for an example AMD host and an Intel host with an `identity.seed`, each also with `hypervMode = "hidden"`, the Intel one with `smbios.perDomainSerials` as well, and once with `acpi.waet = false`, where VMAware must not report FIRMWARE. Its probe VMs are rendered by [domain.nix](../domain.nix) and started from the command line libvirt makes of them: a SATA disk, a virtio disk, a SATA CD, QXL video and emulated SMBIOS each boot and hand over a framebuffer; the virtio case also carries an RTL8125, HD Audio and USB input devices and reads their identities; the SATA case reads CPUID, SMBIOS with each memory module's serial, PCI, ACPI, the battery serial, EDID with its serial number, the disk, the TPM, the clocks, the PCI window, the MAC and fw_cfg against the configuration and hot-plugs a USB keyboard; the Microsoft keys refuse an unsigned loader, an enrolled test key boots only the signed one, and the Microsoft variable template carries the Microsoft certificates under the configured Platform Key and Microsoft's revocation list; every booted case reads an SMBIOS table that dmidecode decodes whole up to its end-of-table, with the memory array, its address map and the boot status, and no handle that names a missing structure, and runs VMAware, and a technique it detects that [verify/vmaware-expected.json](../verify/vmaware-expected.json) does not list for the host's `cpuVendor` and `hypervMode`, with `-nowaet` appended when `acpi.waet` is off, fails the check. Each probe VM runs pinned to one host CPU. Its output keeps every serial log and an evidence.json of what each guest reported and on which CPU |
| `detect-fixture-contract` | shell contract, both systems | `stealth-detect` gives the right verdict on fixture trees, including the ACPI vectors a directly booted guest does not expose |
| `detect-finds-plain-virt` | VM test, aarch64 | `stealth-detect` finds a plain aarch64 QEMU guest through the device tree, PSCI and virtio vectors, and agrees with `systemd-detect-virt` |

- The VM tests need a builder with `/dev/kvm`. `detect-finds-plain-virt` drops that requirement and runs under TCG, because GitHub's aarch64 runners have no KVM.
- A `boot-matrix` boot that reaches no result in time is retried, and evidence.json lists every boot. On some KVM hosts stock QEMU with nixpkgs' stock OVMF crawls through a share of boots at random, in the firmware or the boot stub. A boot that finishes with a wrong result fails at once.
- `boot-matrix` reads what Linux sees in the guest. What Windows sees through WMI and the registry is checked by [guest/verify-stealth.ps1](../guest/verify-stealth.ps1), which no check runs; [Windows evidence](#windows-evidence) runs it off CI.

## VMAware in the probe

[VMAware](https://github.com/kernelwernel/VMAware)'s command line tool runs in
the probe initrd only. Its dmidecode and dmesg techniques look for those tools
at FHS paths and run them through `/bin/sh`, so the probe links them there;
`systemd-detect-virt` is not in the initrd, so its SYSTEMD technique never
fires. An expected technique that no longer fires in any case is printed and
does not fail. Why each expected one fires:

| Technique | Why it fires |
| - | - |
| `HYPERVISOR_BIT` | Enlightened mode keeps the CPUID hypervisor bit, which the Hyper-V enlightenments need |
| `HYPERVISOR_STR` | Enlightened mode answers CPUID 0x40000000 with `hypervVendorId` |
| `CPUID_SIGNATURE` | Expected for `cpuVendor` `"intel"` only, and fires only when that configuration runs on an AMD builder: there KVM sets Intel's IBRS, STIBP and SSBD bits in CPUID 7 EDX, which AMD hardware leaves clear, and [lib.nix](../lib.nix) disables them only for `"amd"`. On an Intel CPU the check compares the topology leaves instead, which agree |
| `DEVICES` | The virtio and QXL cases carry vendor 1af4 and 1b36 devices, which the limits in [COMPATIBILITY.md](COMPATIBILITY.md) name |
| `DMESG` | A Linux kernel built with paravirt support logs that it boots a paravirtualized kernel even on bare metal, and VMAware matches it; Windows has no such log |
| `FIRMWARE` | The WAET table, which `acpi.waet` keeps by default for the reason its description gives; `boot-matrix-intel-hidden-nowaet` shows it is the only trace left |
| `THREAD_COUNT` | The probe VM has one vCPU, and VMAware flags two threads or fewer |
| `THREAD_MISMATCH` | The guest reads the host CPU's model name with fewer threads than that model has, as any VM with fewer vCPUs than its host does |

## Off-CI evidence

`legacyPackages.x86_64-linux.evidence.kernel-runtime` is not a check, so CI
never builds it. Each of its named sets turns on some kernel switches, every
other switch off, and is named after the kernel variant that builds; called as a
function, `kernel-runtime <cpuVendor> <settings>`, it tests any other set the
module accepts. A set boots a NixOS VM whose kernel carries those switches and
one with a stock kernel, starts a guest inside each, and
[tests/kernel-runtime.py](../tests/kernel-runtime.py) judges what the guests
saw against the switches. Most rules hold in both directions, a check that
must hold with a switch failing without it: the share of time `timing` hides,
what `instructionFixes` makes VMLOAD, VMCALL and VMMCALL raise, the exit cost
`cpuidPassthrough` removes, and the RDTSC and RDTSCP handler symbols of the
timing patch. Two are read one way, with the switch only: CPUID leaf 0 for
`cpuidSpoof`, and ICEBP for `instructionFixes` on AMD. It reads the guest TSC against the ACPI PM timer,
which QEMU keeps from host time, for the time `timing` hides; CPUID leaf 0
against the stock kernel for `cpuidSpoof`; the cost of a CPUID against one of
the VM the guest runs in for `cpuidPassthrough`; and what VMLOAD, VMCALL,
VMMCALL and ICEBP raise for `instructionFixes`. On Intel only VMCALL is read:
VMLOAD raises #UD there without a patch, and VMMCALL depends on QEMU's quirk
setting, which the boot matrix checks, as the inner guest here runs on
nixpkgs' QEMU, the only one that boots a kernel directly. Raw CPUID cycles are
not compared: under nested KVM every trapped RDTSC also carries the outer
hypervisor's work. It needs nested KVM and a builder of the set's vendor.
Build a set by hand after a change to [kernel/](../kernel):

```sh
nix build .#legacyPackages.x86_64-linux.evidence.kernel-runtime.timing -L
```

`nix run .#evidence` builds the `boot-matrix` checks and every `kernel-runtime` set and
prints what each guest saw. `nix run .#evidence -- --against <rev>` builds the
same at another revision and prints what changed. That revision must have the
kernel-runtime sets: one from before they were added cannot be a baseline.

## Windows evidence

`legacyPackages.x86_64-linux.evidence.windows` installs Windows 11 from an ISO
you supply, which no CI store can hold, into a VM rendered by
[domain.nix](../domain.nix) and started the way `boot-matrix` starts its probes:
the stealth QEMU and OVMF, Secure Boot with the Microsoft keys, the swtpm TPM,
a SATA disk and CDs so Setup needs no driver, and an e1000e on a user network
without a route out. At the first logon, and at each logon of a later run, the
probe CD runs [guest/verify-stealth.ps1](../guest/verify-stealth.ps1) with the host's
`hypervMode`, VMAware's Windows build and `Win32_DeviceGuard`, writes each to
COM1 between the probe's markers and shuts Windows down. Before
verify-stealth.ps1 it runs [guest/cleanup-registry.ps1](../guest/cleanup-registry.ps1),
whose failure fails the build. The build fails on a
`[FAIL]` line and on a VMAware technique that
[verify/vmaware-expected-windows.json](../verify/vmaware-expected-windows.json)
does not list for the host's `cpuVendor` and `hypervMode`, with `-vbs` appended
to the mode in a run built with `vbs = true;` and `-nowaet` with `acpi.waet` off. Its entries fire for
the reasons the probe's table above gives, or because the builder's own kernel
lacks the kernel patches; a patched builder kernel prints the entries it no
longer sees. Three fire whatever the builder's kernel: TRAP on Intel, which is
the Intel CPU's own behaviour, TIMER on Intel, for which no timing patch
exists, and GPU_CAPABILITIES, because the guest has an emulated display. The
[known limitations](COMPATIBILITY.md#known-limitations) give their reasons. The VBS and HVCI state is recorded,
not judged, unless the run is built with `vbs = true;`: then the probe turns
VBS and HVCI on at the first logon and reboots, and the build fails unless
both run. Pass the builder's CPU vendor and a path, which Nix copies into the
store:

```sh
nix build -L --impure -o windows-install --expr '(builtins.getFlake (toString ./.)).legacyPackages.x86_64-linux.evidence.windows { cpuVendor = "amd"; iso = /path/to/Win11.iso; }'
```

The install's output keeps `disk.qcow2`, `vars.fd` and `tpm/` beside
evidence.json and the serial log. A later run boots a copy of them without
installing, here with module settings changed as `boot-matrix-hidden` does:

```sh
nix build -L --impure --expr '(builtins.getFlake (toString ./.)).legacyPackages.x86_64-linux.evidence.windows { cpuVendor = "amd"; installed = ./windows-install; settings.hypervMode = "hidden"; }'
```

- The answer file is [verify/windows/autounattend.xml](../verify/windows/autounattend.xml). Its language is the first one `sources/lang.ini` of the ISO lists, so an ISO of any language installs. The answer file's `Group` element takes a group name, which Windows localizes, so [verify/windows/account.ps1](../verify/windows/account.ps1) creates the logon account in the specialize pass and adds it to Administrators and Users by their well-known SIDs. Pro is chosen by Microsoft's generic installation key, which installs it unactivated. Device encryption is turned off, so the kept disk boots with the kept TPM state and can be read offline.
- The Windows CD bootloader waits five seconds for a key and otherwise boots the next device. The harness presses space for 8 seconds after the firmware first starts a boot option: a later space lands in Setup, which opens with Cancel focused, and cancels the install.
- VMAware's Windows build needs MSVC's `__try`, which GCC lacks, so `pkgsCross.mingw-ucrt-x86_64-llvm` builds it with clang. [verify/vmaware-mingw.patch](../verify/vmaware-mingw.patch) adapts the four places where the mingw-w64 headers differ from the Windows SDK. Clang drops a `__try` whose body is only inline assembly, as no instruction there can throw for it, and a trap-flag exception reports the address after its instruction, outside any such body, so the patch moves each of those assembly statements into a function called inside the `__try`; otherwise the trap ends VMAware with STATUS_SINGLE_STEP.
- A failed run leaves no output. Build it again with `--keep-failed` and read `vms/windows/` in the kept build directory: the serial log, the QEMU command line and `screen.ppm`, the last screen, taken every minute.
- The run's verdict is [verify/windows-judge.py](../verify/windows-judge.py), which reads the serial log, so the libvirt run below shares it.
- A run with real hardware passes `gpu = { address = "0000:01:00.0"; audio = "0000:01:00.1"; }`, `hostDevices`, and `memory`, `cores`, `threads` and `pinning` as a domain takes them; the verdict then needs each passed device to report status OK in Windows. The build sandbox reaches no VFIO device, so such a run goes through the build's `runner` instead, as root on the host with the devices free of host drivers: `nix build --impure -o windows-runner --expr '(... .evidence.windows { ...; gpu = { ... }; }).runner'`, then `sudo ./windows-runner/bin/vfio-stealth-windows-run ./windows-gpu`, which works in `/var/tmp` and writes its output to the path it is given.

`legacyPackages.x86_64-linux.evidence.libvirt-windows` runs the whole stack on
an installed image: a NixOS VM whose kernel carries the module's kernel
patches runs libvirtd with the module and NixVirt, which defines the VM;
`virsh start` boots the installed Windows, which runs the same probe, and the
verdict reads it against the `-patched` lists in
[verify/vmaware-expected-windows.json](../verify/vmaware-expected-windows.json),
which leave out what the kernel patches remove. Windows runs nested, so a host
needs nested KVM. Pass the builder's CPU vendor and the result of an install:

```sh
nix build -L --impure --expr '(builtins.getFlake (toString ./.)).legacyPackages.x86_64-linux.evidence.libvirt-windows { cpuVendor = "amd"; installed = ./windows-install; settings.hypervMode = "hidden"; }'
```

## Adding a change

Every kind of change has the same three parts: the edit, the guard that
fails when its anchor moves, and a check that reads the result.

| Change | Edit | Guard | Proof |
| - | - | - | - |
| A string or id QEMU shows the guest | [qemu/post-patch.nix](../qemu/post-patch.nix); for an emulated device, its option in [qemu/device-identity-schema.nix](../qemu/device-identity-schema.nix) and its value in [qemu/device-identities.nix](../qemu/device-identities.nix); otherwise an option threaded through [qemu/package.nix](../qemu/package.nix), or for SMBIOS through `qemuArgs` in [lib.nix](../lib.nix) | `landed`, `gone` or `exactly_one` next to the edit, and a guard with its own test value in [tests/sed-contract-qemu.nix](../tests/sed-contract-qemu.nix) | a comparison in [verify/boot.py](../verify/boot.py) |
| A firmware value | [ovmf/post-patch.nix](../ovmf/post-patch.nix) | the same, in [tests/sed-contract-edk2.nix](../tests/sed-contract-edk2.nix) | [verify/boot.py](../verify/boot.py) |
| A larger QEMU change | a `.patch` file in [qemu/](../qemu) applied with `patch -F0` | its zero-fuzz apply and a guard on the result | [verify/boot.py](../verify/boot.py) |
| A kernel patch | a script in [kernel/](../kernel) and a switch in [module.nix](../module.nix) `kernelPostPatch` | `exactly_one` before each edit, `landed` after, from [kernel/prelude.nix](../kernel/prelude.nix) | the fit and compile checks pick the switch up by themselves; add a set to `kernelRuntimeSets` in [flake.nix](../flake.nix) and the switch's rule to [tests/kernel-runtime.py](../tests/kernel-runtime.py) |
| A domain or host option | [module.nix](../module.nix), rendered in [domain.nix](../domain.nix) or the host layer | a type, and an assertion for each refused combination | a refusal case in [tests/module-assertions.nix](../tests/module-assertions.nix); a new value of a switch gets a setting in [tests/option-combinations.nix](../tests/option-combinations.nix) |
| A third-party source | vendor it with a README naming origin, commit and licence, and pin it in [version.json](../version.json) | a watch in [scripts/update.sh](../scripts/update.sh) that exits 1 with what to do when it moves, and 2 when a fetch fails | run the script with the pin moved back |
| A new VMAware detection | the fix where it belongs, or a limitation row in [COMPATIBILITY.md](COMPATIBILITY.md) | | its entry leaves [verify/vmaware-expected.json](../verify/vmaware-expected.json) and [verify/vmaware-expected-windows.json](../verify/vmaware-expected-windows.json) |
| A failure users hit that no check catches | its cause fixed in the code where it can be | | a row in [TROUBLESHOOTING.md](TROUBLESHOOTING.md) with what they see, why, and the fix |
| Any option text | its `description` in [module.nix](../module.nix) | `std-option-reference` fails while [OPTIONS.md](OPTIONS.md) differs | `nix run .#std-write-option-reference` rewrites it |

A new check is shown to fail on the code before the change before it counts.

## Keeping up to date

Two scheduled workflows keep the sources current. The update workflow runs
[scripts/update.sh](../scripts/update.sh), which changes no file: exit 0 means
nothing moved, exit 2 is a failed fetch that the next run retries, and exit 1
opens one `update-failed` issue whose `error_type` names the case and whose
message says what to do; the next clean run closes it. The maintenance workflow
runs `nix flake update`, builds every check on the new lock, pushes the lock
when they pass and opens a `maintenance` issue when they do not. That covers
nixpkgs, with its QEMU, edk2 and kernels, NixVirt, nix-cachyos-kernel and the
packaging standard.

Run the updater by hand from the repository root with
`nix develop -c bash scripts/update.sh`. It writes its outputs to
`$GITHUB_OUTPUT`, or to `/tmp/update-outputs.env` outside CI. To test a watch,
move its pin in [version.json](../version.json) back and run it again.

| `error_type` | What moved | What to do |
| - | - | - |
| `manual-port-needed` | a watched AutoVirt fork ships a QEMU patch newer than ours | [Port a QEMU patch](#port-a-qemu-patch) |
| `qemu-series-ready` | nixpkgs or upstream has a QEMU series we have no patch for, and our newest patch applies, passes its sed contract and boots on it | copy that patch under the new version's name and add the tarball hash the message prints; the ceiling rises by itself |
| `patch-gap` | the same, but our newest patch fails at the stage the message names | [Port a QEMU patch](#port-a-qemu-patch) to the new series |
| `edk2-manual-port-needed` | a watched fork ships a newer EDK2 patch | [Port an EDK2 patch](#port-an-edk2-patch) |
| `autovirt-patches-moved` | AutoVirt changed a file under `patches/` since `.autovirt.rev` | read the change and port what applies into [vendor/autovirt](../vendor/autovirt), or into [acpi/](../acpi) for its `.dsl` tables; record it in [vendor/autovirt/README](../vendor/autovirt/README) and set `.autovirt.rev` |
| `autovirt-pr-settled` | one of this repository's pull requests to AutoVirt, listed in `AV_PRS` in the script, was merged or closed | merged: take upstream's patch in place of the local fix; either way, remove it from `AV_PRS` |
| `betterTiming-moved` | BetterTiming has a new commit | read it, port what applies into [kernel/timing-patch.nix](../kernel/timing-patch.nix) by hand, build the kernel-runtime sets, set `.betterTiming.rev` |
| `vfioNative-moved` | vfio-native has a new commit | [Adopt a vfio-native patch](#adopt-a-vfio-native-patch) |
| `vmaware-moved` | VMAware has a new release | [Move VMAware](#move-vmaware) |
| `dbx-moved` | Microsoft published a new revocation list | [Move the Secure Boot revocation list](#move-the-secure-boot-revocation-list) |
| `fork-stale`, `fork-returned`, `upstream-gone` | a watched AutoVirt repository went away or came back | move it between `AUTOVIRT_REPOS` and `AUTOVIRT_GONE` in the script |
| `autovirt-rev-gone`, `autovirt-pr-gone`, `edk2-watch-moved`, `betterTiming-gone`, `vfioNative-gone`, `vmaware-gone`, `dbx-gone`, `arm-watch-source-moved` | a watched URL answers 404 | find the new home and point the script at it, or keep the pin |
| `arm-idregs-upstream` | QEMU's ARM KVM backend can now set the guest CPU's id registers | read Platforms in [COMPATIBILITY.md](COMPATIBILITY.md) on what an aarch64 target would need |
| `inventory-error` | [vendor/autovirt/patches](../vendor/autovirt/patches) lacks a patch the script expects | restore it |

### Port a QEMU patch

The vendored QEMU patches are `<Vendor>-v<version>.patch` in
[vendor/autovirt/patches/QEMU/](../vendor/autovirt/patches/QEMU), named for the
QEMU they apply to. Every one carries this repository's fix for duplicate ACPI
device names (EHC1, XHC1), which a patch taken from upstream lacks.

1. Read the new patch. It comes from a third-party fork.
2. Apply it, or our newest patch, to the new QEMU and fix what does not apply.
   Carry over the duplicate ACPI name fix from our previous patch.
3. Test it before vendoring: build `sed-contract` and `boot-smoke` of
   `legacyPackages.x86_64-linux.qemuProbe { version = "<version>"; hash = "<tarball hash>"; }`,
   under `.amd` and `.intel`. The probe builds a QEMU past the ceiling.
4. Save it under its name, add the QEMU's tarball hash to `tarballHashes` in
   [qemu/package.nix](../qemu/package.nix), and record its origin in
   [vendor/autovirt/README](../vendor/autovirt/README). Set `.autovirt.rev` in
   [version.json](../version.json) when it came from AutoVirt.
5. Re-aim the edits in [qemu/post-patch.nix](../qemu/post-patch.nix) and the
   `.patch` files in [qemu/](../qemu) whose anchors moved; their guards name them.
6. Run `nix flake check`, then `nix run .#evidence -- --against <rev>` with the
   commit before, and update [AUTOVIRT.md](AUTOVIRT.md) for every change the
   guest shows.

`minimumVersion` in [qemu/package.nix](../qemu/package.nix) is the floor: a
caller's nixpkgs QEMU older than it is replaced by that release's tarball. To
drop an old series, raise the floor to the oldest series still vendored and
remove the older patches. Evaluation refuses a floor without a tarball hash or
a vendored patch.

### Port an EDK2 patch

OVMF is the caller's nixpkgs OVMF with the newest
`<Vendor>-edk2-stable<tag>.patch` from
[vendor/autovirt/patches/EDK2/](../vendor/autovirt/patches/EDK2) applied,
without its BaseTools hunk: nixpkgs builds OVMF with a prebuilt BaseTools, so
`filterdiff` drops it. The edk2 source is not pinned, so a nixpkgs edk2 that the
patch no longer fits fails `sed-contract-edk2` and the maintenance run. Port the
patch to that edk2 tag and save it under the tag's name, re-aim
[ovmf/post-patch.nix](../ovmf/post-patch.nix) and
[ovmf/edid-protocols.patch](../ovmf/edid-protocols.patch) where their guards
fail, and build `sed-contract-edk2`, `sed-contract-edk2-intel`,
`sed-contract-edk2-vendor` and the boot matrices.

### Adopt a vfio-native patch

[vendor/vfio-native](../vendor/vfio-native) is an unchanged copy of
[vfio-native](https://git.archworks.co/sandwich/vfio-native)'s KVM patches,
applied before this repository's own kernel scripts:
[kernel/instruction-fixes.nix](../kernel/instruction-fixes.nix) applies 0002
and 0003, [kernel/svm-instruction-fixes.nix](../kernel/svm-instruction-fixes.nix)
0001 and 0004, and [kernel/pinned-cpuid-passthrough.nix](../kernel/pinned-cpuid-passthrough.nix)
EXPERIMENTAL-0006. Compare its `patches/kvm`, copy what changed, build the
kernel checks and the kernel-runtime sets, then set `.vfioNative.rev` in
[version.json](../version.json). The kernel-runtime sets prove 0001 to 0003
from a guest program; the ICEBP fix in 0004 shows only when delivering the #DB
faults, which no guest program can force, so the fit and compile checks are its
only proof. The script applies 0004 only to a kernel that lacks upstream's own
ICEBP fix, so a check whose kernel carries it never exercises that branch.
[kernel/timing-patch.nix](../kernel/timing-patch.nix) is a port of
[BetterTiming](https://github.com/SamuelTulach/BetterTiming), and
[kernel/cpuid-patch.nix](../kernel/cpuid-patch.nix) and
[kernel/cpuid-disable.nix](../kernel/cpuid-disable.nix) are this repository's
own; [Decide on the kernel patches](GUIDE.md#decide-on-the-kernel-patches) says what each switch does.

### Move VMAware

Set `.vmaware.version` and `.vmaware.hash` in [version.json](../version.json),
re-aim [verify/vmaware-mingw.patch](../verify/vmaware-mingw.patch) where its
hunks moved, build the boot matrices and a Windows run, and update
[verify/vmaware-expected.json](../verify/vmaware-expected.json) and
[verify/vmaware-expected-windows.json](../verify/vmaware-expected-windows.json)
for each technique the release adds, with its reason in the probe table above
or a row in [COMPATIBILITY.md](COMPATIBILITY.md).

### Move the Secure Boot revocation list

`packages.secureBootVars` enrolls the x64 dbx from
[microsoft/secureboot_objects](https://github.com/microsoft/secureboot_objects),
pinned by commit and hash as `.microsoftDbx` in [version.json](../version.json).
Set the new commit, version, date and hash there and build a `boot-matrix`
check, which fails when the template's dbx is the placeholder.

### Flake inputs by hand

`nix flake update <input>`, then `nix flake check`, read by its exit code. A
new nixpkgs also moves QEMU, edk2 and the kernels: test a nixpkgs revision
before it lands with
`nix flake check --override-input nixpkgs github:NixOS/nixpkgs/<rev>`. A
NixVirt change shows in `domain-render`, `module-eval-own-nixvirt` and
`libvirt-firmware`.

### Hardware defaults

The SMBIOS defaults in [smbios/](../smbios), the port connectors and slots in
`board-connectors.nix`, the CPU fields per vendor in `processor-defaults.nix`
and the memory layout in `memory-layout.nix`, are what `dmidecode` reads on
real AM5 and LGA1700 boards. Refresh one from a current board's
`dmidecode -t 4`, `-t 8`, `-t 9`, `-t 16` or `-t 17`.
[smbios/generate-tables.py](../smbios/generate-tables.py) builds the type 7
cache tables from the cache options.

## When a check fails

- A sed contract: the log names the guard or the failed assertion. The anchor moved in QEMU, EDK2 or the AutoVirt patch. Read [SED-CATALOG.md](SED-CATALOG.md), then re-aim the edit in the post-patch file.
- A patch that does not apply with zero fuzz: the AutoVirt patch no longer fits that source, through a new QEMU release or a new nixpkgs patch. [qemu/acpi-pci-names.patch](../qemu/acpi-pci-names.patch) also fails when the AutoVirt patch changes the naming code it edits.
- `kernel-postpatch-fits-*`: the failing combination's log names the edit and the anchor. Re-aim it in [kernel/](../kernel). A caller's kernel build that fails inside `kernelPostPatch` prints the same message for its own kernel.
- `kernel-kvm-compiles-*`: the scripts apply but the C around them changed. The log ends with the compiler's last lines.
- `boot-smoke`: the exception names the vector or the device. A guest with no console output at all is a firmware hang; the chipset edits in QEMU and OVMF must agree.
- `domain-render`: the message names the domain and the element that differs; a schema failure names the line of the rendered XML.
- `qemu-hook`: the message names the VM and the refusal it expected; the hook's own output is printed above it.
- `boot-matrix`: the log names the case and what its guest reported. A failed build leaves no `result`; build it again with `--keep-failed` and read `vms/<case>/attempt-<n>/` in the kept build directory, which holds the serial log, the QEMU command line and the QEMU log.
- `libvirt-firmware`: libvirt offers a firmware other than `ovmf-stealth`, so `packages.libvirtQemu` no longer carries only its descriptors, or the declared VM fails a host check the log names.
- An evaluation error about a ceiling, a floor or a tarball hash comes from [lib/select-qemu-base.nix](../lib/select-qemu-base.nix); one about a missing patch for a QEMU series comes from [lib/autovirt-patches.nix](../lib/autovirt-patches.nix).
