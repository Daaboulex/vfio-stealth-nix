# Development

This file is for people who change this repository. [DESIGN.md](DESIGN.md)
explains why the parts are built the way they are.

## Dev shell

- `nix develop` enters the dev shell of nix-packaging-standard and installs its pre-commit hooks.
- `nix fmt` formats the tree.
- The hooks skip [vendor/](../vendor), and shfmt skips [guest/](../guest).
- The stealth stack builds only on `x86_64-linux`. On `aarch64-linux` the flake declares `stealth-detect` and the checks that need no x86 host.

## Checks

`nix flake check` runs all of them. The standard adds its own `package-*`,
`std-*` and `pre-commit` checks; its README describes them.

| Check | Kind | What it proves |
| - | - | - |
| `module-eval-nixos` | eval | The module evaluates in a NixOS system with the identity placeholders replaced, the host layer with most of its options, and two domains. One domain has pinning, huge pages, a GPU bound by the hook with a ROM, USB, unmount, Looking Glass and most per-domain overrides. The other has a GPU bound at boot |
| `vmaware-not-shipped` | eval and derivation walk | Take a system with the host layer, kvmfr, the Looking Glass client, evdev, and a domain with a hook-bound GPU and huge pages. Its derivation closure contains its QEMU, but no VMAware derivation anywhere. Nothing of the system is built |
| `module-eval-own-nixvirt` | eval | `nixosModules.vfio-stealth` evaluates with a declared domain, in a system that imports NixVirt's module itself |
| `gpus` | shell contract, both systems | `vfio-stealth-gpus`, run on a fake sysfs, prints the settings the module takes for a card whose IOMMU group holds only its own functions, warns about the card the firmware shows its picture on, names the devices a shared group would take along, and says when the IOMMU is off |
| `vmaware-docs` | doc check | Every technique in the VMAware lists is explained in [COMPATIBILITY.md](COMPATIBILITY.md#known-limitations), in the guide's [VMAware table](GUIDE.md#read-a-vmaware-result) or in [VMAware in the probe](#vmaware-in-the-probe), and none of those names a technique the lists no longer expect |
| `module-assertions` | eval | The module's assertions and option types refuse the settings they guard against, and accept a valid one |
| `identity-seed` | eval | With `identity.seed`, every unique value left unset is derived in its real form: fifteen digits of board serial, a WD-WCC disk serial for the default model and twelve hex digits for another model, twelve hex digits of Hyper-V vendor id, a nonzero EDID serial number, five battery digits, a version 4 UUID per VM, and eight hex digits for each populated memory slot in the slot table that QEMU is built with. QEMU and the battery table are built with these values. A second seed changes every one of them, a value set by hand wins, and `perDomainSerials` follows the seed. Without a seed, the rebuild warns about each shared value and about unset cache sizes |
| `option-combinations` | eval | Combinations of the module's mixable switches. They are generated with `host.enable` on whenever a chosen value needs it, so that every pair of values appears in a combination the assertions accept. Each accepted combination evaluates its system and every domain's XML with no warning. A refused one is logged with its assertion, and it fails the check when it leaves a pair untested |
| `guide-snippets` | doc check | Every `nix` block of [README.md](../README.md), [GUIDE.md](GUIDE.md) and [QUICKSTART.md](QUICKSTART.md) has a copy in [tests/snippets/](../tests/snippets), the files the evaluation imports, and matches it. Each block parses. Each block that sets `virtualisation.vfio-stealth` evaluates with no failed assertion, on top of the blocks before it in its file; a later block's values replace an earlier one's |
| `examples` | eval | Every module in [examples/](../examples) evaluates with no failed assertion: [configuration.nix](../examples/configuration.nix), a passthrough host whose kernel is built through `packages.kernelFor`, and [hardened-gaming.nix](../examples/hardened-gaming.nix). Every domain they declare passes libvirt's schema, and [examples/flake.nix](../examples/flake.nix) parses |
| `domain-render` | eval and schema, both systems | Domains with these settings pass libvirt's schema: pinning, huge pages, a GPU in each binding, a ROM, USB, unmount, Looking Glass on shared memory and on kvmfr, evdev, a MAC, a machine type, per-domain serials from the seed, the VM's IOMMU, PipeWire sound and every per-domain override. Their XML carries the vcpupin, emulatorpin and iothreadpin, the managed flag of each binding, the GPU's functions in one slot behind one root port, the ROM, the shmem or kvmfr device, the IOMMU with interrupt remapping and a QEMU IOAPIC, the HD Audio codec and its PipeWire backend, the huge page backing, and the QEMU arguments each one asks for. The host gets the vfio-pci ids, the hook, the USB udev rule and the evdev device ACL |
| `qemu-hook` | shell contract, both systems | The QEMU hook runs on a fake sysfs and proc tree. It refuses a device that the root filesystem, a filesystem on device mapper, or swap is on. It honours the unmount list. It adds huge pages to the pool and takes them back at release. It refuses a missing GPU function, a GPU that a process holds open, two passed devices of one IOMMU group with `iommu`, and a second pinned VM under `pinning.isolate`. It stops the running `stopServices` before the bind and starts them again at release. It ignores a VM that the plan does not name |
| `sed-contract-qemu`, `sed-contract-qemu-intel` | source replay | The vendor's AutoVirt patch and [qemu/post-patch.nix](../qemu/post-patch.nix) apply to the QEMU source that the package builds, after nixpkgs' own patches. Each edit's result is in the tree |
| `sed-contract-edk2`, `sed-contract-edk2-intel` | source replay | The vendor's EDK2 patch and [ovmf/post-patch.nix](../ovmf/post-patch.nix) apply to the OVMF source. Each edit's result is in the tree |
| `sed-contract-edk2-vendor` | source replay | The same, with a firmware vendor and ACPI OEM that are not the defaults. So an edit that matches only the default values fails |
| `autovirt-patch-contract` | Nix contract | The patch resolver picks the newest patch of a series by version order. It refuses an unknown vendor or an unpatched series |
| `qemu-ceiling-contract` | Nix contract | The QEMU base is nixpkgs inside the patched band, and a floor or ceiling tarball outside it. A missing hash, or a ceiling below the floor, is refused |
| `update-gap-contract` | shell contract | Which QEMU versions [scripts/update.sh](../scripts/update.sh) counts as covered or as a gap, and which release tag it reads as the newest |
| `lib-output-contract` | Nix contract | `lib.mkStealthFeatures` returns the expected QEMU arguments, features, clock and sysinfo. This includes the Hyper-V intersection with `kernelCapabilities`, and no `-cpu` argument |
| `sed-catalog-lean` | doc check | Every file that [SED-CATALOG.md](SED-CATALOG.md) names exists and still rewrites text, and the catalog repeats no anchor |
| `kernel-postpatch-fits-cachyos`, `kernel-postpatch-fits-upstream` | source replay | [tests/kernel-variants.nix](../tests/kernel-variants.nix) generates every combination of the kernel switches that [kernel/post-patch.nix](../kernel/post-patch.nix) accepts, the function the module takes its `kernelPostPatch` and its switch assertions from. The `kernelPostPatch` of each combination applies to the CachyOS and nixpkgs latest kernel sources, with each edit asserted |
| `kernel-kvm-compiles-cachyos`, `kernel-kvm-compiles-upstream` | compile | Every combination compiles `arch/x86/kvm` with that kernel's own config |
| `acpi-oem` | build | Every SSDT of `acpi-ssdt-stealth` carries the configured OEM id and table id |
| `smbios-cache-associativity` | build | The generated SMBIOS type 7 tables carry the associativity byte of each default cache level |
| `smbios-extract` | build, both systems | `smbios-split` writes the same per-structure files from an `_SM3_` dump and from an `_SM_` dump. It drops the structures that QEMU builds itself, and refuses a file that is not a dump |
| `libvirt-firmware`, `libvirt-firmware-intel` | VM test | With the module on, libvirt offers only `ovmf-stealth`, and a domain asking for `firmware="efi"` starts on it. A VM under `domains` is defined by NixVirt and passes the domain checks of `vfio-stealth-verify-host` |
| `boot-smoke`, `boot-smoke-intel` | VM test | A q35 NixOS guest boots on `qemu-stealth` and `ovmf-stealth`. Inside it, the ACPI tables carry the configured OEM id, PCI subsystem ids are not QEMU's, the kernel logs no ACPI firmware error, the USB and ICH9 devices carry their board names, the ICH9 devices sit at 0x1f with ICH9 IDs and revisions, slot 0x14 is empty, and the SATA disk and CD answer ATA IDENTIFY and SCSI INQUIRY with one configured model and firmware |
| `boot-matrix`, `boot-matrix-hidden`, `boot-matrix-hidden-nowaet`, `boot-matrix-intel`, `boot-matrix-intel-hidden`, `boot-matrix-intel-hidden-nowaet` | VM test | The module option `bootCheck`, built for an example AMD host and an Intel host with an `identity.seed`. Each is also built with `hypervMode = "hidden"`. The Intel hidden build also sets `smbios.perDomainSerials`. The two `-nowaet` builds set `acpi.waet = false`; there only the `viommu` case on Intel may report FIRMWARE. Its probe VMs are rendered by [domain.nix](../domain.nix) and started from the command line that libvirt makes of them. A SATA disk, a virtio disk, a SATA CD, QXL video and emulated SMBIOS each boot and hand over a framebuffer. The virtio case also carries an RTL8125, HD Audio and USB input devices, and reads their identities. The `viommu` case boots with the VM's own IOMMU, as `iommu` gives it. Every case fails when the guest kernel logs a disk command timeout or an I/O error. A build starts its next probe VM only while it has a free core and the host keeps the VM's memory and a quarter of its own free, so parallel builds and their evaluation fit the host. Each probe VM is pinned to the host CPU it starts on: under load, a VM that moves between host CPUs can stall in the firmware, with the OVMF of nixpkgs as well. Every case runs `systemd-detect-virt`, which must find no VM in hidden mode. The SATA case reads these against the configuration: CPUID, SMBIOS with each memory module's serial, PCI, ACPI, the battery serial, EDID with its serial number, the disk, the TPM, the clocks, the PCI window, the MAC and fw_cfg. It also hot-plugs a USB keyboard. The Microsoft keys refuse an unsigned loader, and an enrolled test key boots only the signed one. The Microsoft variable template carries the Microsoft certificates under the configured Platform Key, and Microsoft's revocation list. Every booted case reads an SMBIOS table that dmidecode decodes whole, up to its end-of-table, with the memory array, its address map and the boot status, and with no handle that names a missing structure. Every booted case also runs VMAware. The check fails when VMAware detects a technique that [verify/vmaware-expected.json](../verify/vmaware-expected.json) does not list for the host's `cpuVendor` and `hypervMode`, with `-nowaet` appended when `acpi.waet` is off, beyond what a case itself expects. The output keeps every serial log, and an evidence.json of what each guest reported |
| `detect-fixture-contract` | shell contract, both systems | `stealth-detect` gives the right verdict on fixture trees, including the ACPI vectors that a directly booted guest does not expose |
| `detect-finds-plain-virt` | VM test, aarch64 | `stealth-detect` finds a plain aarch64 QEMU guest through the device tree, PSCI and virtio vectors, and agrees with `systemd-detect-virt` |

- The VM tests need a builder with `/dev/kvm`. `detect-finds-plain-virt` does not need it and runs under TCG, because GitHub's aarch64 runners have no KVM.
- If a `boot-matrix` boot reaches no result in time, it is retried, and evidence.json lists every boot. On some KVM hosts, stock QEMU with nixpkgs' stock OVMF runs very slowly in some boots, at random, in the firmware or in the boot stub. A boot that finishes with a wrong result fails at once.
- GitHub does not let a workflow choose the CPU of an x86 runner. On a runner with an Intel Xeon Platinum 8573C, where KVM runs nested, every `boot-matrix` probe stalled with no firmware output, while the same lock passed on AMD EPYC runners and on a bare-metal Intel host. Open: why the guests stay silent under that runner's nested KVM.
- `boot-matrix` reads what Linux sees in the guest. What Windows sees through WMI and the registry is checked by [guest/verify-stealth.ps1](../guest/verify-stealth.ps1). No check runs that script; [Windows evidence](#windows-evidence) runs it outside CI.

## VMAware in the probe

[VMAware](https://github.com/kernelwernel/VMAware)'s command line tool runs in
the probe initrd only. Its dmidecode and dmesg techniques look for those tools
at FHS paths and run them through `/bin/sh`, so the probe links them there;
`systemd-detect-virt` is linked at `/usr/bin`, where its SYSTEMD technique
looks for it. An expected technique that no longer fires in any case is printed and
does not fail. Why each expected one fires:

| Technique | Why it fires |
| - | - |
| `HYPERVISOR_BIT` | Enlightened mode keeps the CPUID hypervisor bit, which the Hyper-V enlightenments need |
| `HYPERVISOR_STR` | Enlightened mode answers CPUID 0x40000000 with `hypervVendorId` |
| `CPUID_SIGNATURE` | Expected for `cpuVendor` `"intel"` only, and fires only when that configuration runs on an AMD builder: there KVM sets Intel's IBRS, STIBP and SSBD bits in CPUID 7 EDX, which AMD hardware leaves clear, and [lib.nix](../lib.nix) disables them only for `"amd"`. On an Intel CPU the check compares the topology leaves instead, which agree |
| `DEVICES` | The virtio and QXL cases carry vendor 1af4 and 1b36 devices, which the limits in [COMPATIBILITY.md](COMPATIBILITY.md) name |
| `DMESG` | A Linux kernel built with paravirt support logs that it boots a paravirtualized kernel even on bare metal, and VMAware matches it; Windows has no such log |
| `FIRMWARE` | The WAET table, which `acpi.waet` keeps by default for the reason its description gives; the two `-nowaet` builds show it is the only trace left, apart from the DMAR table of the `viommu` case on Intel |
| `SYSTEMD` | In enlightened mode `systemd-detect-virt` reads the hypervisor bit and reports `vm-other`; in hidden mode it reports `none` |
| `THREAD_COUNT` | The probe VM has one vCPU, and VMAware flags two threads or fewer |
| `THREAD_MISMATCH` | The guest reads the host CPU's model name with fewer threads than that model has, as any VM with fewer vCPUs than its host does |

## Off-CI evidence

`legacyPackages.x86_64-linux.evidence.kernel-runtime` is not a check, so CI
never builds it. Each of its named sets turns on some kernel switches and turns
every other switch off. Each set is named after the kernel variant it builds.
Called as a function, `kernel-runtime <cpuVendor> <settings>`, it tests any
other set that the module accepts. A set boots two NixOS VMs: one whose kernel
has those switches, and one with a stock kernel. It starts a guest inside each.
Then [tests/kernel-runtime.py](../tests/kernel-runtime.py) judges what the
guests saw against the switches.

Most rules hold in both directions: a check must pass with the switch and fail
without it. These rules cover the share of time that `timing` hides, what
`instructionFixes` makes VMLOAD, VMCALL and VMMCALL raise, the exit cost that
`cpuidPassthrough` removes, and the RDTSC and RDTSCP handler symbols of the
timing patch. Two rules are read in one direction only, with the switch on:
CPUID leaf 0 for `cpuidSpoof`, and ICEBP for `instructionFixes` on AMD.

For the time that `timing` hides, the test reads the guest TSC against the ACPI
PM timer, which QEMU keeps from host time. For `cpuidSpoof` it reads CPUID leaf
0 against the stock kernel. For `cpuidPassthrough` it compares the cost of a
CPUID with the cost in the VM the guest runs in. For `instructionFixes` it reads
what VMLOAD, VMCALL, VMMCALL and ICEBP raise. On Intel only VMCALL is read.
There, VMLOAD raises #UD without a patch. VMMCALL depends on QEMU's quirk
setting, and the inner guest here runs on nixpkgs' QEMU, the only one that
boots a kernel directly. The boot matrix checks that quirk setting. Raw CPUID
cycles are not compared, because under nested KVM every trapped RDTSC also
includes the outer hypervisor's work. `kernel-runtime` needs nested KVM and a
builder of the same vendor as the set. Build a set by hand after a change to
[kernel/](../kernel):

```sh
nix build .#legacyPackages.x86_64-linux.evidence.kernel-runtime.timing -L
```

`nix run .#evidence` builds the `boot-matrix` checks and every `kernel-runtime`
set, and prints what each guest saw. `nix run .#evidence -- --against <rev>`
builds the same at another revision and prints what changed. That revision must
have the kernel-runtime sets: a revision from before they were added cannot be
a baseline.

## Windows evidence

`legacyPackages.x86_64-linux.evidence.windows` installs Windows 11 from an ISO
that you supply, because no CI store can hold it. It installs into a VM
rendered by [domain.nix](../domain.nix) and started the way `boot-matrix` starts
its probes: the stealth QEMU and OVMF, Secure Boot with the Microsoft keys, the
swtpm TPM, a SATA disk and CDs so Setup needs no driver, and an e1000e on a user
network with no route out. At the first logon, and at each logon of a later
run, the probe CD runs [guest/verify-stealth.ps1](../guest/verify-stealth.ps1)
with the host's `hypervMode`, VMAware's Windows build and `Win32_DeviceGuard`.
It writes each result to COM1 between the probe's markers, and shuts Windows
down. Before verify-stealth.ps1 it runs
[guest/cleanup-registry.ps1](../guest/cleanup-registry.ps1); if that fails, the
build fails.

The build fails on a `[FAIL]` line. It also fails on a VMAware technique that
[verify/vmaware-expected-windows.json](../verify/vmaware-expected-windows.json)
does not list for the host's `cpuVendor` and `hypervMode`. Here `-vbs` is
appended to the mode in a run built with `vbs = true;`, `-iommu` in one built
with `iommu = true;`, and `-nowaet` when `acpi.waet` is off. A run with `iommu`
gives the VM its own IOMMU, as a domain's `iommu` does, and fails unless Windows
reports DMA protection as available. The entries in that file fire for the reasons the probe's
table above gives, or because the builder's own kernel does not have the kernel
patches. A patched builder kernel prints the entries it no longer sees. Three
fire whatever the builder's kernel is: TRAP on Intel, which is the Intel CPU's
own behaviour; TIMER on Intel, for which no timing patch exists; and
GPU_CAPABILITIES, because the guest has an emulated display. The
[known limitations](COMPATIBILITY.md#known-limitations) give their reasons.

The VBS and HVCI state is recorded but not judged, unless the run is built with
`vbs = true;`. Then the probe turns VBS and HVCI on at the first logon and
reboots, and the build fails unless both run. Pass the builder's CPU vendor and
a path, which Nix copies into the store:

```sh
nix build -L --impure -o windows-install --expr '(builtins.getFlake (toString ./.)).legacyPackages.x86_64-linux.evidence.windows { cpuVendor = "amd"; iso = /path/to/Win11.iso; }'
```

The install's output keeps `disk.qcow2`, `vars.fd` and `tpm/` next to
evidence.json and the serial log. A later run boots a copy of them without
installing again. This example also changes module settings, as
`boot-matrix-hidden` does:

```sh
nix build -L --impure --expr '(builtins.getFlake (toString ./.)).legacyPackages.x86_64-linux.evidence.windows { cpuVendor = "amd"; installed = ./windows-install; settings.hypervMode = "hidden"; }'
```

- The answer file is [verify/windows/autounattend.xml](../verify/windows/autounattend.xml). Its language is the first one that `sources/lang.ini` of the ISO lists, so an ISO in any language installs. The answer file's `Group` element takes a group name, and Windows translates group names. So [verify/windows/account.ps1](../verify/windows/account.ps1) creates the logon account in the specialize pass, and adds it to Administrators and Users by their well-known SIDs. Pro is chosen by Microsoft's generic installation key, which installs it without activation. Device encryption is turned off, so the kept disk boots with the kept TPM state and can be read offline.
- The Windows CD bootloader waits five seconds for a key, and otherwise boots the next device. The harness presses space for 8 seconds after the firmware first starts a boot option. A later space lands in Setup, which opens with Cancel focused, and cancels the install.
- VMAware's Windows build needs MSVC's `__try`, which GCC does not have. So `pkgsCross.mingw-ucrt-x86_64-llvm` builds it with clang. [verify/vmaware-mingw.patch](../verify/vmaware-mingw.patch) adapts the four places where the mingw-w64 headers differ from the Windows SDK. Clang drops a `__try` whose body is only inline assembly, because no instruction there can throw for it. A trap-flag exception reports the address after its instruction, which is outside any such body. So the patch moves each of those assembly statements into a function that is called inside the `__try`. Without this, the trap ends VMAware with STATUS_SINGLE_STEP.
- A failed run leaves no output. Build it again with `--keep-failed`, and read `vms/windows/` in the kept build directory. It holds the serial log, the QEMU command line and `screen.ppm`, the last screen, which is taken every minute.
- The run's verdict comes from [verify/windows-judge.py](../verify/windows-judge.py), which reads the serial log. So the libvirt run below uses it too.
- A run with real hardware passes `gpu = { address = "0000:01:00.0"; audio = "0000:01:00.1"; }`, `hostDevices`, and `memory`, `cores`, `threads` and `pinning` in the form a domain takes them. The verdict then needs each passed device to report status OK in Windows. The build sandbox cannot reach a VFIO device. So such a run goes through the build's `runner` instead, as root on the host, with the devices free of host drivers: `nix build --impure -o windows-runner --expr '(... .evidence.windows { ...; gpu = { ... }; }).runner'`, then `sudo ./windows-runner/bin/vfio-stealth-windows-run ./windows-gpu`. The runner works in `/var/tmp` and writes its output to the path it is given.

`legacyPackages.x86_64-linux.evidence.libvirt-windows` runs the whole stack on
an installed image. A NixOS VM, whose kernel has the module's kernel patches,
runs libvirtd with the module and NixVirt, and NixVirt defines the VM.
`virsh start` boots the installed Windows, which runs the same probe. The
verdict reads the result against the `-patched` lists in
[verify/vmaware-expected-windows.json](../verify/vmaware-expected-windows.json),
which leave out what the kernel patches remove. Windows runs nested, so a host
needs nested KVM. Pass the builder's CPU vendor and the result of an install:

```sh
nix build -L --impure --expr '(builtins.getFlake (toString ./.)).legacyPackages.x86_64-linux.evidence.libvirt-windows { cpuVendor = "amd"; installed = ./windows-install; settings.hypervMode = "hidden"; }'
```

## Adding a change

Every kind of change has the same three parts: the edit, the guard that fails
when the edit's anchor moves, and a check that reads the result.

| Change | Edit | Guard | Proof |
| - | - | - | - |
| A string or id QEMU shows the guest | [qemu/post-patch.nix](../qemu/post-patch.nix). For an emulated device: its option in [qemu/device-identity-schema.nix](../qemu/device-identity-schema.nix) and its value in [qemu/device-identities.nix](../qemu/device-identities.nix). Otherwise: an option passed through [qemu/package.nix](../qemu/package.nix), or for SMBIOS through `qemuArgs` in [lib.nix](../lib.nix) | `landed`, `gone` or `exactly_one` next to the edit, and a guard with its own test value in [tests/sed-contract-qemu.nix](../tests/sed-contract-qemu.nix) | a comparison in [verify/boot.py](../verify/boot.py) |
| A firmware value | [ovmf/post-patch.nix](../ovmf/post-patch.nix) | the same, in [tests/sed-contract-edk2.nix](../tests/sed-contract-edk2.nix) | [verify/boot.py](../verify/boot.py) |
| A larger QEMU change | a `.patch` file in [qemu/](../qemu) applied with `patch -F0` | its zero-fuzz apply and a guard on the result | [verify/boot.py](../verify/boot.py) |
| A kernel patch | a script in [kernel/](../kernel), a switch in [module.nix](../module.nix), and the script and any refusal in [kernel/post-patch.nix](../kernel/post-patch.nix) | `exactly_one` before each edit, `landed` after, from [kernel/prelude.nix](../kernel/prelude.nix) | add the switch to [tests/kernel-variants.nix](../tests/kernel-variants.nix), and the fit and compile checks pick up its combinations; add a set to `kernelRuntimeSets` in [flake.nix](../flake.nix) and the switch's rule to [tests/kernel-runtime.py](../tests/kernel-runtime.py) |
| A domain or host option | [module.nix](../module.nix), rendered in [domain.nix](../domain.nix) or the host layer | a type, and an assertion for each refused combination | a refusal case in [tests/module-assertions.nix](../tests/module-assertions.nix); a new value of a switch gets a setting in [tests/option-combinations.nix](../tests/option-combinations.nix) |
| A third-party source | vendor it with a README that names its origin, commit and licence, and pin it in [version.json](../version.json) | a watch in [scripts/update.sh](../scripts/update.sh) that exits 1 with what to do when the source moves, and exits 2 when a fetch fails | run the script with the pin moved back |
| A new VMAware detection | the fix where it belongs; or, when it stays, its name in [verify/vmaware-expected.json](../verify/vmaware-expected.json) or [verify/vmaware-expected-windows.json](../verify/vmaware-expected-windows.json) | `vmaware-docs` names each page that must explain it, or that still explains one the lists dropped | its entry leaves the lists once the fix lands |
| A new limit, or a limit that changes | a row in [COMPATIBILITY.md](COMPATIBILITY.md#known-limitations) with what it costs and why | | its "Shown by" cell names the check or run that proves it, or the code that makes it so; a row nothing proves starts with "Open:" |
| A failure that users hit and no check catches | its cause fixed in the code where possible | | a row in [TROUBLESHOOTING.md](TROUBLESHOOTING.md) with what they see, why, and the fix |
| Any option text | its `description` in [module.nix](../module.nix) | `std-option-reference` fails while [OPTIONS.md](OPTIONS.md) differs | `nix run .#std-write-option-reference` rewrites it |

A new check counts only after it has been shown to fail on the code from before
the change.

## Keeping up to date

Two scheduled workflows keep the sources current. The update workflow runs
[scripts/update.sh](../scripts/update.sh), which changes no file. Exit 0 means
nothing moved. Exit 2 is a failed fetch, and the next run retries it. Exit 1
opens one `update-failed` issue: its `error_type` names the case, and its
message says what to do. The next clean run closes it. The maintenance workflow
runs `nix flake update` and builds every check on the new lock. It pushes the
lock when the checks pass, and opens a `maintenance` issue when they do not.
This covers nixpkgs (with its QEMU, edk2 and kernels), NixVirt,
nix-cachyos-kernel and the packaging standard.

Run the updater by hand from the repository root with
`nix develop -c bash scripts/update.sh`. It writes its outputs to
`$GITHUB_OUTPUT`, or to `/tmp/update-outputs.env` outside CI. To test a watch,
move its pin in [version.json](../version.json) back and run it again.

| `error_type` | What moved | What to do |
| - | - | - |
| `manual-port-needed` | a watched AutoVirt fork ships a QEMU patch newer than ours | [Port a QEMU patch](#port-a-qemu-patch) |
| `qemu-series-ready` | nixpkgs or upstream has a QEMU series that we have no patch for, and our newest patch applies to it, passes its sed contract and boots on it | copy that patch under the new version's name and add the tarball hash that the message prints; the ceiling rises on its own |
| `patch-gap` | the same, but our newest patch fails at the stage that the message names | [Port a QEMU patch](#port-a-qemu-patch) to the new series |
| `edk2-manual-port-needed` | a watched fork ships a newer EDK2 patch | [Port an EDK2 patch](#port-an-edk2-patch) |
| `autovirt-patches-moved` | AutoVirt changed a file under `patches/` since `.autovirt.rev` | read the change and port what applies into [vendor/autovirt](../vendor/autovirt), or into [acpi/](../acpi) for its `.dsl` tables; record it in [vendor/autovirt/README](../vendor/autovirt/README) and set `.autovirt.rev` |
| `autovirt-pr-settled` | one of this repository's pull requests to AutoVirt (listed in `AV_PRS` in the script) was merged or closed | if merged, take upstream's patch instead of the local fix; in both cases, remove it from `AV_PRS` |
| `betterTiming-moved` | BetterTiming has a new commit | read it, port what applies into [kernel/timing-patch.nix](../kernel/timing-patch.nix) by hand, build the kernel-runtime sets, and set `.betterTiming.rev` |
| `vfioNative-moved` | vfio-native has a new commit | [Adopt a vfio-native patch](#adopt-a-vfio-native-patch) |
| `vmaware-moved` | VMAware has a new release | [Move VMAware](#move-vmaware) |
| `dbx-moved` | Microsoft published a new revocation list | [Move the Secure Boot revocation list](#move-the-secure-boot-revocation-list) |
| `fork-stale`, `fork-returned`, `upstream-gone` | a watched AutoVirt repository went away or came back | move it between `AUTOVIRT_REPOS` and `AUTOVIRT_GONE` in the script |
| `autovirt-rev-gone`, `autovirt-pr-gone`, `edk2-watch-moved`, `betterTiming-gone`, `vfioNative-gone`, `vmaware-gone`, `dbx-gone`, `arm-watch-source-moved` | a watched URL answers 404 | find the new home and point the script at it, or keep the pin |
| `arm-idregs-upstream` | QEMU's ARM KVM backend can now set the guest CPU's id registers | read Platforms in [COMPATIBILITY.md](COMPATIBILITY.md) for what an aarch64 target would need |
| `inventory-error` | [vendor/autovirt/patches](../vendor/autovirt/patches) is missing a patch that the script expects | restore it |

### Port a QEMU patch

The vendored QEMU patches are `<Vendor>-v<version>.patch` in
[vendor/autovirt/patches/QEMU/](../vendor/autovirt/patches/QEMU), named after
the QEMU they apply to. Every one of them carries this repository's fix for
duplicate ACPI device names (EHC1, XHC1). A patch taken from upstream does not
have this fix.

1. Read the new patch. It comes from a third-party fork.
2. Apply it, or our newest patch, to the new QEMU, and fix what does not apply.
   Carry over the duplicate ACPI name fix from our previous patch.
3. Test it before vendoring: build `sed-contract` and `boot-smoke` of
   `legacyPackages.x86_64-linux.qemuProbe { version = "<version>"; hash = "<tarball hash>"; }`,
   under `.amd` and `.intel`. The probe builds a QEMU past the ceiling.
4. Save it under its name, add the QEMU's tarball hash to `tarballHashes` in
   [qemu/package.nix](../qemu/package.nix), and record its origin in
   [vendor/autovirt/README](../vendor/autovirt/README). Set `.autovirt.rev` in
   [version.json](../version.json) if it came from AutoVirt.
5. Re-aim the edits in [qemu/post-patch.nix](../qemu/post-patch.nix) and the
   `.patch` files in [qemu/](../qemu) whose anchors moved; their guards name them.
6. Run `nix flake check`. Then run `nix run .#evidence -- --against <rev>` with
   the commit before, and update [AUTOVIRT.md](AUTOVIRT.md) for every change the
   guest shows.

`minimumVersion` in [qemu/package.nix](../qemu/package.nix) is the floor. If a
caller's nixpkgs QEMU is older than the floor, it is replaced by that release's
tarball. To drop an old series, raise the floor to the oldest series still
vendored, and remove the older patches. Evaluation refuses a floor without a
tarball hash or a vendored patch.

### Port an EDK2 patch

OVMF is the caller's nixpkgs OVMF with the newest
`<Vendor>-edk2-stable<tag>.patch` from
[vendor/autovirt/patches/EDK2/](../vendor/autovirt/patches/EDK2) applied,
without its BaseTools hunk. nixpkgs builds OVMF with a prebuilt BaseTools, so
`filterdiff` drops that hunk. The edk2 source is not pinned. So when nixpkgs has
an edk2 that the patch no longer fits, `sed-contract-edk2` and the maintenance
run fail. Then port the patch to that edk2 tag and save it under the tag's name.
Re-aim [ovmf/post-patch.nix](../ovmf/post-patch.nix) and
[ovmf/edid-protocols.patch](../ovmf/edid-protocols.patch) where their guards
fail. Build `sed-contract-edk2`, `sed-contract-edk2-intel`,
`sed-contract-edk2-vendor` and the boot matrices.

### Adopt a vfio-native patch

[vendor/vfio-native](../vendor/vfio-native) is an unchanged copy of
[vfio-native](https://git.archworks.co/sandwich/vfio-native)'s KVM patches.
They are applied before this repository's own kernel scripts:
[kernel/instruction-fixes.nix](../kernel/instruction-fixes.nix) applies 0002
and 0003, [kernel/svm-instruction-fixes.nix](../kernel/svm-instruction-fixes.nix)
applies 0001 and 0004, and
[kernel/pinned-cpuid-passthrough.nix](../kernel/pinned-cpuid-passthrough.nix)
applies EXPERIMENTAL-0006. Compare its `patches/kvm`, copy what changed, build
the kernel checks and the kernel-runtime sets, then set `.vfioNative.rev` in
[version.json](../version.json).

The kernel-runtime sets prove 0001 to 0003 from a guest program. The ICEBP fix
in 0004 shows only when the #DB faults are delivered, and no guest program can
force that. So the fit and compile checks are its only proof. The script
applies 0004 only to a kernel that does not have upstream's own ICEBP fix. So a
check whose kernel has that fix never runs that branch.
[kernel/timing-patch.nix](../kernel/timing-patch.nix) is a port of
[BetterTiming](https://github.com/SamuelTulach/BetterTiming).
[kernel/cpuid-patch.nix](../kernel/cpuid-patch.nix) and
[kernel/cpuid-disable.nix](../kernel/cpuid-disable.nix) are this repository's
own. [Decide on the kernel patches](GUIDE.md#decide-on-the-kernel-patches) says
what each switch does.

### Move VMAware

Set `.vmaware.version` and `.vmaware.hash` in [version.json](../version.json).
Re-aim [verify/vmaware-mingw.patch](../verify/vmaware-mingw.patch) where its
hunks moved. Build the boot matrices and a Windows run. Then update
[verify/vmaware-expected.json](../verify/vmaware-expected.json) and
[verify/vmaware-expected-windows.json](../verify/vmaware-expected-windows.json)
for each technique the release adds, with its reason in the probe table above
or in a row in [COMPATIBILITY.md](COMPATIBILITY.md).

### Move the Secure Boot revocation list

`packages.secureBootVars` enrolls the x64 dbx from
[microsoft/secureboot_objects](https://github.com/microsoft/secureboot_objects).
It is pinned by commit and hash as `.microsoftDbx` in
[version.json](../version.json). Set the new commit, version, date and hash
there, and build a `boot-matrix` check. That check fails when the template's
dbx is the placeholder.

### Flake inputs by hand

Run `nix flake update <input>`, then `nix flake check`, and read its exit code.
A new nixpkgs also moves QEMU, edk2 and the kernels. To test a nixpkgs revision
before it lands, use
`nix flake check --override-input nixpkgs github:NixOS/nixpkgs/<rev>`. A
NixVirt change shows in `domain-render`, `module-eval-own-nixvirt` and
`libvirt-firmware`.

### Hardware defaults

The SMBIOS defaults in [smbios/](../smbios) are what `dmidecode` reads on real
AM5 and LGA1700 boards: the port connectors and slots in
`board-connectors.nix`, the CPU fields per vendor in `processor-defaults.nix`,
and the memory layout in `memory-layout.nix`. To refresh one, use a current
board's `dmidecode -t 4`, `-t 8`, `-t 9`, `-t 16` or `-t 17`.
[smbios/generate-tables.py](../smbios/generate-tables.py) builds the type 7
cache tables from the cache options.

## When a check fails

- A sed contract: the log names the guard or the failed assertion. The anchor moved in QEMU, EDK2 or the AutoVirt patch. Read [SED-CATALOG.md](SED-CATALOG.md), then re-aim the edit in the post-patch file.
- A patch that does not apply with zero fuzz: the AutoVirt patch no longer fits that source, because of a new QEMU release or a new nixpkgs patch. [qemu/acpi-pci-names.patch](../qemu/acpi-pci-names.patch) also fails when the AutoVirt patch changes the naming code that it edits.
- `kernel-postpatch-fits-*`: the log of the failing combination names the edit and the anchor. Re-aim it in [kernel/](../kernel). If a caller's kernel build fails inside `kernelPostPatch`, it prints the same message for its own kernel.
- `kernel-kvm-compiles-*`: the scripts apply, but the C code around them changed. The log ends with the compiler's last lines.
- `boot-smoke`: the exception names the vector or the device. A guest with no console output at all is a firmware hang. The chipset edits in QEMU and OVMF must agree.
- `domain-render`: the message names the domain and the element that differs. A schema failure names the line of the rendered XML.
- `qemu-hook`: the message names the VM and the refusal it expected. The hook's own output is printed above it.
- `boot-matrix`: the log names the case and what its guest reported. A failed build leaves no `result`. Build it again with `--keep-failed`, and read `vms/<case>/attempt-<n>/` in the kept build directory. It holds the serial log, the QEMU command line and the QEMU log.
- `libvirt-firmware`: either libvirt offers a firmware other than `ovmf-stealth`, so `packages.libvirtQemu` no longer carries only its descriptors; or the declared VM fails a host check that the log names.
- An evaluation error about a ceiling, a floor or a tarball hash comes from [lib/select-qemu-base.nix](../lib/select-qemu-base.nix). An error about a missing patch for a QEMU series comes from [lib/autovirt-patches.nix](../lib/autovirt-patches.nix).
