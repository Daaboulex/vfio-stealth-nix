# Guide

From a NixOS machine with nothing set up to a Windows VM that reports your
board's hardware, with a GPU of its own if you want one. Each step says what
you see when it worked. To only see it work first, follow
[QUICKSTART.md](QUICKSTART.md). The recommended value of every option for a
hardened gaming VM is in [Hardened gaming settings](#hardened-gaming-settings).

The commands assume your configuration is a flake in `/etc/nixos` with a host
named `vm-host`, as in [examples/flake.nix](../examples/flake.nix). Change both
to yours. Every value below is an example; read yours from your machine.

Flakes and the `nix` command are off on a fresh NixOS. Turn them on first: add
`nix.settings.experimental-features = [ "nix-command" "flakes" ];` to
`/etc/nixos/configuration.nix` and run `sudo nixos-rebuild switch`. Then put a
`flake.nix` beside it, as [examples/flake.nix](../examples/flake.nix) shows.
If `/etc/nixos` is a git repository, a flake sees only the files git tracks:
`git add` each new file, such as a GPU ROM, before the rebuild that reads it.

Tools that NixOS does not install by default come from `nix shell`. If `sudo`
then says a command is not found, run it as `sudo env "PATH=$PATH" <command>`.

```sh
nix shell nixpkgs#pciutils nixpkgs#usbutils nixpkgs#dmidecode nixpkgs#smartmontools nixpkgs#lsscsi nixpkgs#edid-decode nixpkgs#tpm2-tools nixpkgs#mokutil
```

## Check the hardware

You need an x86_64 AMD or Intel CPU, a board whose firmware turns on the
IOMMU, and for a passed-through GPU a second GPU for the desktop. An
integrated GPU counts.

1. In the firmware setup, turn on CPU virtualisation (SVM on AMD, VT-x on
   Intel) and the IOMMU (often called IOMMU or AMD-Vi on AMD, VT-d on Intel).
   The menu names differ between boards.
2. Check the CPU flag and KVM:

   ```sh
   grep -c -w -e svm -e vmx /proc/cpuinfo
   ls -l /dev/kvm
   ```

   It worked when the count is above 0 and `/dev/kvm` exists.
3. Check the IOMMU:

   ```sh
   sudo dmesg | grep -i -e DMAR -e IOMMU
   ```

   It worked when you see `AMD-Vi` lines on AMD or `DMAR: IOMMU enabled` on
   Intel, and lines saying devices were added to IOMMU groups. If Intel shows
   nothing, add `boot.kernelParams = [ "intel_iommu=on" ];` to your
   configuration, rebuild, reboot and check again. If it is still empty, the
   IOMMU is off in the firmware setup.
4. List the IOMMU groups:

   ```sh
   for group in /sys/kernel/iommu_groups/*; do
     echo "group ${group##*/}"
     for device in "$group"/devices/*; do
       echo "  $(lspci -nns "${device##*/}")"
     done
   done
   ```

5. Find your GPU in the list. It is fine when its group holds only the GPU's
   own functions (the video function, its HDMI audio, sometimes a USB
   controller on the card), apart from PCI bridges. Each of them goes to the
   VM: the audio function as `gpu.audio`, a USB-C controller or any other
   function as `gpu.extraFunctions`.

VFIO hands a whole group to a VM, never one device of it. Devices in one group
can reach each other's memory without the IOMMU in between, so every device
of the group goes to the guest, or the VM does not start.

When the GPU shares its group with other devices, try another slot first: a
slot wired to the CPU usually has a group of its own, one wired to the
chipset often shares. A PCIe port without the ACS capability puts
everything below it in one group, unless the kernel's quirk list vouches for
that port; no firmware setting adds the capability. `sudo lspci -vvv` lists
it as Access Control Services under the ports that have it. The other way is
the ACS override, `host.acsOverride`. It splits the groups, but only on a
kernel that carries the ACS override patch; mainline ignores it. The split is
fake: a passed-through device can still reach the other devices of its real
group by DMA, so a guest with that device can read or corrupt their memory.

## Add the flake

1. Add the input and the module to `/etc/nixos/flake.nix`, as
   [README.md](../README.md#install) shows. Use `nixosModules.default`, or
   `nixosModules.vfio-stealth` if your configuration already imports NixVirt's
   module.
2. In `configuration.nix`, turn on libvirt and the module, and let your user
   manage VMs:

   ```nix
   {
     virtualisation.libvirtd.enable = true;
     programs.virt-manager.enable = true;
     users.users.alice = {
       isNormalUser = true;
       extraGroups = [ "libvirtd" ];
     };

     virtualisation.vfio-stealth = {
       enable = true;
       cpuVendor = "amd";
     };
   }
   ```

   The `libvirtd` group reaches your user at the next login; the reboot below
   gives you one.

Do not rebuild yet: the next step fills in the identity.

## Read the identity from your machine

Start with `identity.seed`: a private phrase of 8 or more characters that no
other host uses. Every value that is unique to one real part and that you
leave unset is derived from it, in the form that kind of part reports: the
board serial, each memory module's serial, the disk serial, the monitor's
serial number, the battery serial, the Hyper-V vendor id, and each VM's UUID.
The same seed gives the same values on every rebuild, and a second host with
its own seed gets values of its own. Without a seed these values are the ones
every host without a seed shares, which tie a guest to this module, and the
rebuild warns about each.

Each row below names the options, the command that shows the values, and the
fields to copy. Run the commands on the machine the VM will run on. The option
descriptions in [OPTIONS.md](OPTIONS.md) give each format.

| Options | Command | Copy |
|---|---|---|
| `smbios.biosVendor`, `biosVersion`, `biosDate`, `biosRelease` | `sudo dmidecode -t 0` | Vendor, Version, Release Date, BIOS Revision |
| `smbios.manufacturer`, `smbios.product` | `sudo dmidecode -t 2` | Manufacturer, Product Name. They fill both the system and the board entry; on many desktop boards `-t 1` holds placeholder text, so take the board's |
| `smbios.serial`, `systemVersion`, `systemSku`, `systemFamily` | `sudo dmidecode -t 1` | Serial Number, Version, SKU Number, Family |
| `smbios.chassisType` | `cat /sys/class/dmi/id/chassis_type` | the number; 3 is a desktop |
| `smbios.chassisVersion`, `chassisSerial`, `chassisAsset`, `chassisSku` | `sudo dmidecode -t 3` | Version, Serial Number, Asset Tag, SKU Number |
| `smbios.baseBoardVersion`, `baseBoardSerial`, `baseBoardAsset`, `baseBoardLocation` | `sudo dmidecode -t 2` | Version, Serial Number, Asset Tag, Location In Chassis; `identity.seed` derives the serial when you leave it unset |
| `cpuIdentity.*` | `sudo dmidecode -t 4`, and `sudo dmidecode -u -t 4` for the numbers | Socket Designation, Manufacturer, Version, Max Speed, Current Speed; the Family, Voltage, External Clock, Upgrade and Characteristics bytes below |
| `smbios.cache.*` | `sudo dmidecode -t 7` | Installed Size, Associativity, Error Correction Type of L1, L2 and L3 |
| `smbios.oemStrings` | `sudo dmidecode -t 11` | each String line |
| `smbios.ports` | `sudo dmidecode -t 8`, and `sudo dmidecode -u -t 8` for the numbers | per port: Internal and External Reference Designator, and the connector and port type bytes below |
| `smbios.systemSlots` | `sudo dmidecode -t 9`, and `sudo dmidecode -u -t 9` for the numbers | per slot: Designation, ID, and the type, width, usage, length and characteristics bytes below |
| `smbios.memory.*` | `sudo dmidecode -t 17`, and `sudo dmidecode -u -t 17` for the type detail | Manufacturer, Part Number, Speed, Type, Rank, Configured Voltage in millivolts; the type detail word below. Each slot's `serial` is its Serial Number; `identity.seed` derives one per populated slot when you leave it null |
| `smbios.onboardDevices` | `sudo dmidecode -t 41` | Reference Designation, Type, Type Instance |
| `pciSubsystem` | `lspci -nnv -s 00:00.0` | the `[vvvv:dddd]` at the end of the Subsystem line; if the host bridge shows none, take a chipset device's, such as the SMBus or SATA controller |
| `hdaCodec` | `cat /proc/asound/card*/codec#*` | the board's own codec's Vendor Id: `0x10ec0897` is `"10ec:0897"`. Skip a GPU's HDMI codec |
| `disk.model`, `disk.firmware`, `disk.serial` | `cat /sys/class/nvme/nvme0/model /sys/class/nvme/nvme0/firmware_rev /sys/class/nvme/nvme0/serial`, or `sudo smartctl -i /dev/sda` | model, firmware revision, serial; `identity.seed` derives the serial when you leave it unset |
| `disk.opticalModel`, `disk.opticalFirmware` | `lsscsi`, or `udevadm info --query=property /dev/sr0` | vendor and model, revision; or `ID_VENDOR`, `ID_MODEL`, `ID_REVISION` |
| `edid.*` | `edid-decode /sys/class/drm/card1-DP-1/edid`, with the connector your monitor is on (`ls /sys/class/drm/*/edid`) | Manufacturer, Model, Display Product Name, Made in week and year, Serial Number; `identity.seed` derives `edid.serialNumber` when you leave it unset |
| `tpm.*` | `sudo tpm2_getcap properties-fixed` | the raw value of `TPM2_PT_MANUFACTURER` as `id:` and 8 hex digits, the four `TPM2_PT_VENDOR_STRING` values joined for `model`, the raw value of `TPM2_PT_FIRMWARE_VERSION_1` |
| `secureBoot.platformKeyName` | `mokutil --pk` | the CN of the Subject line |
| `macPrefix` | `ip link` | the first three bytes after `link/ether` of the board's network card |
| `acpiOem.id`, `acpiOem.tableId` | see below | 6 and 8 characters, spaces included |
| `hypervVendorId` | none | derived from `identity.seed`, or any 1 to 12 characters of your own |
| `acpiSsdt.batterySerial` | none: the battery is emulated | derived from `identity.seed`, or any 1 to 16 letters and digits |
| `devices.*` | none: they are the emulated USB devices, MegaRAID card, generation counter and ACPI creator, which the host has no value for | any real device's ids and strings; each install that sets its own no longer shares the defaults with every other |

Some fields need a second step:

- `edid.serial` is the monitor name: copy Display Product Name, not the
  serial number.
- `edid.productCode` is hex; `edid-decode` prints Model as a decimal number.
  Convert it with `printf '0x%04x\n' 9344`.
- `edid.dpi` is the horizontal resolution divided by the width in inches:
  width in cm, from "Maximum image size", divided by 2.54.
- `smbios.cache.*` sizes are in KB: 1 MB from `dmidecode` is 1024. Set
  `l1`, `l2` and `l3` from your own CPU: the guest sees its caches through
  CPUID, and the defaults are an eight core Zen 4's, so the rebuild warns
  while they are unset.
- `smbios.cache.assocL1`, `assocL2`, `assocL3` and `ecc` take the byte the
  SMBIOS specification,
  [DMTF DSP0134](https://www.dmtf.org/standards/smbios), assigns to the word
  `dmidecode -t 7` prints:

  | Associativity | Byte | Error Correction Type | Byte |
  |---|---|---|---|
  | Other | 1 | Other | 1 |
  | Unknown | 2 | Unknown | 2 |
  | Direct Mapped | 3 | None | 3 |
  | 2-way Set-associative | 4 | Parity | 4 |
  | 4-way Set-associative | 5 | Single-bit ECC | 5 |
  | Fully Associative | 6 | Multi-bit ECC | 6 |
  | 8-way Set-associative | 7 | | |
  | 16-way Set-associative | 8 | | |
  | 12-way Set-associative | 9 | | |
  | 24-way Set-associative | 10 | | |
  | 32-way Set-associative | 11 | | |
  | 48-way Set-associative | 12 | | |
  | 64-way Set-associative | 13 | | |
  | 20-way Set-associative | 14 | | |

- Without `cpuIdentity.modelId` the SMBIOS processor Version is the CPU model
  the guest sees, the host's. The other `cpuIdentity` fields left null take
  the values of a real board for `cpuVendor`.
- `dmidecode -u -t N` prints each structure's bytes under Header and Data,
  16 to a row from offset 0x00. A word is two bytes, low byte first: `10 01`
  is 0x0110, 272. The options take these bytes as numbers:

  | Type | Option | Offset |
  |---|---|---|
  | 4 | `cpuIdentity.family` | 0x06; when it is FE, the word at 0x28 |
  | 4 | `cpuIdentity.voltageDecivolts` | 0x11 minus 0x80: 8D is 13, 1.3 V |
  | 4 | `cpuIdentity.externalClock` | word at 0x12 |
  | 4 | `cpuIdentity.upgrade` | 0x19 |
  | 4 | `cpuIdentity.characteristics` | word at 0x26 |
  | 8 | `internalConnectorType`, `externalConnectorType`, `portType` | 0x05, 0x07, 0x08 |
  | 9 | `type`, `dataBusWidth`, `currentUsage`, `length` | 0x05, 0x06, 0x07, 0x08 |
  | 9 | `characteristics1`, `characteristics2` | 0x0B, 0x0C |
  | 17 | `smbios.memory.typeDetail` | word at 0x13 |

- The ACPI OEM id and table id sit in every ACPI table header. The brackets
  show the padding spaces:

  ```sh
  printf '[%s]\n' "$(sudo dd if=/sys/firmware/acpi/tables/FACP bs=1 skip=10 count=6 status=none)"
  printf '[%s]\n' "$(sudo dd if=/sys/firmware/acpi/tables/FACP bs=1 skip=16 count=8 status=none)"
  ```

- `hdaCodec` shows only in a VM with emulated sound, `domains.<name>.sound`.
  A board without an HD Audio codec gives the VM none and leaves `hdaCodec`
  as it is.
- The disk identity is what the guest sees on its emulated SATA disk. A SATA
  drive's identity fits it better than an NVMe drive's.
- Without a CD drive, leave `disk.opticalModel` and `disk.opticalFirmware` as
  they are; they name a real drive.
- `acpi.waet`, `acpi.c2Latency` and `acpi.c3Latency` are not read from your
  machine; their descriptions in [OPTIONS.md](OPTIONS.md) say when to change
  them.

Your real serial numbers, the TPM and board strings and `identity.seed`
identify your machine. Anyone who reads your configuration learns them, so
keep them out of a public repository, for example in a private flake input.
`smbios.serial` and `smbios.chassisSerial` default to `System Serial Number`
and `Default string`, what AMI firmware on many desktop boards reports, so
they need no seed.

Put the values into the module:

```nix
{
  virtualisation.vfio-stealth = {
    identity.seed = "pick a private phrase for this host";
    smbios = {
      manufacturer = "Example Inc.";
      product = "Example Board X1";
      biosVendor = "American Megatrends International, LLC.";
      biosVersion = "1.20";
      biosDate = "03/12/2025";
      memory.manufacturer = "Example Memory";
      memory.partNumber = "EX-DDR5-16G";
      cache = { l1 = 512; l2 = 8192; l3 = 32768; };
      onboardDevices = [ { designation = "Onboard LAN"; kind = "ethernet"; instance = 1; } ];
    };
    disk = {
      model = "Example SSD 1TB";
      firmware = "EX01";
    };
    macPrefix = "D8:BB:C1";
  };
}
```

## Decide on the kernel patches

On AMD, `timing.enable` and `cpuidSpoof.enable` are on by default. They patch
the host kernel's KVM to hide the time each VM exit takes and to answer CPUID
leaf 0 without a full exit. They act only in a kernel built through
`packages.kernelFor`:

```nix
{ config, pkgs, ... }:
{
  boot.kernelPackages = pkgs.linuxPackagesFor (
    config.virtualisation.vfio-stealth.packages.kernelFor pkgs.linux_latest
  );
}
```

Your machine then compiles the kernel at the next rebuild, which takes a long
time, and again at every kernel update.

The same kernel carries `instructionFixes.enable`, on by default on AMD and
Intel: VMCALL and VMMCALL run by a program in the guest raise an
illegal-instruction error, as on a real PC. On AMD an SVM instruction raises
the same error and ICEBP reports the right address. It has no cost.

`cpuidPassthrough.pinned` is experimental and off by default. It adds a switch
that stops CPUID exits on vCPUs pinned one to one to host cores. Turn it on
only after Windows has booted, or Windows hangs:

```sh
echo 1 | sudo tee /sys/module/kvm_amd/parameters/cpuid_passthrough
```

Write `0` the same way before the VM restarts.

On Intel only `instructionFixes` applies; the module refuses the others,
which patch AMD's SVM code. Skip `timing` when you do not need timing
stealth: it traps RDTSC in every VM of the host, which costs frame rate in
games. To skip every kernel patch, leave
`boot.kernelPackages` alone and set `timing.enable = false;`,
`cpuidSpoof.enable = false;` and `instructionFixes.enable = false;`.

## Rebuild and check the host

1. Rebuild and reboot, since the kernel and its parameters change:

   ```sh
   sudo nixos-rebuild switch --flake /etc/nixos#vm-host
   sudo reboot
   ```

   It worked when the rebuild ends without an error. A `vfio-stealth:` warning
   names an option still at its default.
2. Check the host:

   ```sh
   sudo vfio-stealth-verify-host none
   ```

   It takes a VM's name; before a VM exists the one FAIL is that `virsh`
   finds no VM called `none`. Read the host lines: the kernel parameters,
   `ignore_msrs` and, on AMD with the patch, BetterTiming PASS. A WARN that
   some IOMMU groups hold several devices is normal; only the GPU's group
   matters. A BetterTiming SKIP on AMD means the kernel was not built through
   `kernelFor`.

## Check the build with bootCheck

`bootCheck` boots small Linux guests on your QEMU and firmware and reads what
each guest sees:

```sh
cd ~
nix build /etc/nixos#nixosConfigurations.vm-host.config.virtualisation.vfio-stealth.bootCheck -L
```

Nix refuses a git repository another user owns. With `/etc/nixos` owned by
root, run the build with `sudo`, or from a checkout of your own.

It worked when the build ends with one line per case, each with
`finished=True`, except `secure-boot-microsoft` with `finished=False
refused=True`: the Microsoft keys refuse the probe's unsigned loader, as they
should. `./result` then exists. `boots=2` or more means a boot stalled and was
retried. Read what each guest saw:

```sh
ls result/serial
nix shell nixpkgs#jq -c jq '.[] | {name, finished, seconds}' result/evidence.json
```

A failed build leaves no `result`; its last lines name the case and the value
that gave the VM away. Remove `result` when you are done.

## Prepare storage

A VM disk is an image file, a whole disk, or a whole NVMe controller.

An image file:

```sh
sudo mkdir -p /var/lib/libvirt/images
sudo qemu-img create -f qcow2 /var/lib/libvirt/images/win11.qcow2 128G
```

It worked when `qemu-img` prints a `Formatting` line. Windows 11 needs at
least 64 GB. Download the Windows 11 ISO for x64 from
[Microsoft](https://www.microsoft.com/software-download/windows11) and put it
next to the disk, for example as `/var/lib/libvirt/images/win11.iso`.

If `stat -f -c %T /var/lib/libvirt/images` prints `btrfs`, give the disk
`cache = "writeback";`. With the default `none`, Windows setup on btrfs fails
with read errors partway through.

A whole disk the host does not use, as an emulated SATA disk: name it by its
`/dev/disk/by-id/` path in `disks`. The guest sees the `disk.*` identity, not
the drive's. Check twice that it is the right disk with
`lsblk -o NAME,MODEL,SERIAL,MOUNTPOINTS`: the guard below does not cover a disk
given this way.

A whole NVMe controller, passed through as a PCI device: the guest sees the
real drive at full speed.

1. Find its address: `readlink -f /sys/class/nvme/nvme1/device` ends in it,
   such as `0000:02:00.0`.
2. Check that it has an IOMMU group of its own.
3. Add it to the VM as `hostDevices = [ "0000:02:00.0" ];`.

With `host.enable`, the hook refuses to start a VM that passes through a PCI
device under a path of `host.protectedDisks` or an active swap device, and
unmounts what is mounted from it. Setting `host.protectedDisks` replaces the
default list, so keep `/`, `/boot`, `/nix/store` and `/home` in yours.

## Declare a first VM without a GPU

1. Print the newest q35 machine type with
   `virsh -c qemu:///system capabilities | grep -o 'pc-q35-[0-9.]*' | sort -V | tail -1`
   and use it for `machine`; `pc-q35-10.0` below is an example. The VM's
   UUID comes from `identity.seed` and the VM's name; set `uuid` only to keep
   the one an existing VM already has.
2. Declare the VM:

   ```nix
   {
     virtualisation.vfio-stealth.domains.win11 = {
       memory = 8192;
       cores = 4;
       machine = "pc-q35-10.0";
       disks = [ { source = "/var/lib/libvirt/images/win11.qcow2"; format = "qcow2"; } ];
       cdroms = [ "/var/lib/libvirt/images/win11.iso" ];
       network = { };
     };
   }
   ```

   `cores = 4` with the default two threads per core gives 8 vCPUs. A pinned
   machine type keeps the hardware Windows was activated on when QEMU updates.
3. Rebuild. It worked when `virsh -c qemu:///system list --all` shows `win11`
   shut off. If not, `journalctl -b -u nixvirt` says why.
4. The VM uses libvirt's `default` network. If
   `virsh -c qemu:///system net-list --all` shows it inactive:

   ```sh
   virsh -c qemu:///system net-start default
   virsh -c qemu:///system net-autostart default
   ```

   To put the VM on a host bridge instead, set
   `network = { type = "bridge"; source = "br0"; };` with your bridge's name.
5. Run `sudo vfio-stealth-verify-host win11`. It worked when it ends with no
   failures.

Once one VM is declared, NixVirt owns every VM on `qemu:///system`:

- It deletes every VM that is not declared at the next rebuild, keeping its
  disks, NVRAM and TPM state. Declare every VM you keep.
- A change made in virt-manager is overwritten at the next rebuild. Change the
  Nix declaration instead.
- A rebuild that changes a running VM's declaration powers it off and starts
  it again. Shut Windows down first.

## Add a GPU

1. Find the GPU's functions and ids:

   ```sh
   lspci -nn -D | grep -i -e vga -e 3d -e audio
   ```

   A line such as
   `0000:01:00.0 VGA compatible controller [0300]: Example GPU [10de:2484]`
   gives the address `0000:01:00.0` and the id `10de:2484`.
2. Check its group, as in [Check the hardware](#check-the-hardware).
3. Pick how the GPU reaches vfio-pci:

   | `gpu.binding` | When it fits |
   |---|---|
   | `"boot"` | a second GPU the host never uses; two identical cards both go |
   | `"libvirt"`, the default | a GPU the host uses for other work while the VM is off, with no display on it |
   | `"hook"` | a card that works only after its host driver has set it up |

   The GPU your desktop draws on fits none of them. The module stops no
   desktop, and a GPU a running desktop holds open cannot be taken from its
   driver cleanly. Run the desktop on another GPU and cable the passed-through
   card to a monitor input of its own.
4. Declare it, with the host layer on:

   ```nix
   {
     virtualisation.vfio-stealth = {
       host.enable = true;
       domains.win11.gpu = {
         address = "0000:01:00.0";
         audio = "0000:01:00.1";
         binding = "boot";
         ids = [ "10de:2484" "10de:228b" ];
       };
     };
   }
   ```

   A further function in the GPU's group, such as `0000:01:00.2`, goes into
   `gpu.extraFunctions = [ "0000:01:00.2" ];`, and its ids into `ids` with
   `"boot"`.
5. Rebuild, and reboot for `"boot"`. With `"boot"`,
   `lspci -k -s 01:00.0` then shows `Kernel driver in use: vfio-pci`.

The VM then has no emulated video card. Its picture is on the monitor cabled to
the GPU, or in Looking Glass. The guest sees the GPU's functions as one card in
one slot, as a PC does.

Before it binds a GPU, the hook checks that no host process holds the card
open, and refuses to start the VM with the processes named when one does: a
driver cannot release a card in use, and the host can hang trying. A fan, RGB
or monitoring daemon that keeps the card open goes into `stopServices`; the
hook stops it before the bind and starts it again when the VM stops:

```nix
{ virtualisation.vfio-stealth.domains.win11.stopServices = [ "coolercontrold.service" ]; }
```

A KDE Plasma session opens every GPU it finds. Set `KWIN_DRM_DEVICES` to the
host GPU's `/dev/dri/card` path so it leaves the other card alone.

Windows' Virtualization-based Security (Memory integrity) with a passed GPU
needs the VM's own IOMMU, `iommu = true;`: without it the screen stays black
once VBS starts. The VM's IOMMU gives each passed device an address space of
its own, which QEMU refuses for two devices in one IOMMU group, so the hook
refuses such a domain and names the group. A GPU whose video and audio
functions share a group runs without `iommu`, and then without VBS.

### When a ROM file is needed

A guest usually reads the card's own ROM. The host firmware alters the ROM of
the card it boots on, and a guest given that card can show no picture until
Windows loads its driver, or none at all. Then give the guest a clean copy:

1. Make the other GPU the primary one in the firmware setup and boot.
2. Dump the ROM:

   ```sh
   cd /sys/bus/pci/devices/0000:01:00.0
   echo 1 | sudo tee rom
   sudo cat rom > ~/vbios.rom
   echo 0 | sudo tee rom
   head -c 2 ~/vbios.rom | od -An -tx1
   ```

   It worked when the last line prints `55 aa`.
3. Copy it next to your `flake.nix`, run `git add vbios.rom` (a flake sees only
   files git tracks), and set `gpu.rom.file = ./vbios.rom;`.

A picture that is corrupted rather than missing points at the ROM BAR instead:
set `gpu.rom.bar = false;`.

A card that drops off the bus, or fails to start a second time without a host
reboot, may be losing its PCIe link in a power-saving state: set
`host.disableAspm = true;`, which costs some host power. One whose guest
driver fails on its large BAR, or that starts only once per host boot, can
take `gpu.resizeBar2Mb` with `binding = "hook"`.

## USB devices, CPU pinning, huge pages, input and Looking Glass

### USB devices

`lsusb` prints ids in hex, such as `ID 1234:5678`. The options take numbers:
`printf '%d %d\n' 0x1234 0x5678` prints `4660 22136`.

```nix
{ virtualisation.vfio-stealth.domains.win11.usb = [ { vendor = 4660; product = 22136; } ]; }
```

The device leaves the host while the VM runs. Plugged in again while the VM
runs, it goes back to the VM.

### CPU pinning

Pinning gives each vCPU a host CPU of its own. `lscpu -e` shows which CPUs are
the two threads of one core. On an 8-core, 16-thread CPU it often looks like
this, where CPUs 0 and 8 share core 0:

```text
CPU NODE SOCKET CORE L1d:L1i:L2:L3 ONLINE
  0    0      0    0 0:0:0:0          yes
  1    0      0    1 1:1:1:0          yes
...
  8    0      0    0 0:0:0:0          yes
  9    0      0    1 1:1:1:0          yes
...
```

To give the guest cores 2 to 7 and keep cores 0 and 1 for the host, list the
two threads of each core side by side:

```nix
{
  virtualisation.vfio-stealth.domains.win11 = {
    cores = 6;
    pinning = {
      vcpus = [ 2 10 3 11 4 12 5 13 6 14 7 15 ];
      emulator = "0,8";
    };
  };
}
```

Your numbering can differ: read it from `lscpu -e`. On a CPU where the L3
field differs between CPUs, keep the guest on CPUs that share one L3. Add
`pinning.iothread` only for virtio disks. A pinned VM gets `cpuPm` on; set
`cpuPm = false;` on it when the host still runs its own work on those CPUs.

Pinned to the cores of one L3, with VBS and the VM's IOMMU on, a 7-Zip
benchmark in the guest reached 91% of the same cores' bare-metal score. A
scheduler daemon such as ananicy that lowers QEMU's priority cuts that score;
keep QEMU at normal priority.

To also keep the host's own work off the guest's CPUs while it runs, set the
host option, beside `domains`, with `host.enable`:

```nix
{ virtualisation.vfio-stealth.pinning.isolate = true; }
```

### Huge pages

Set `hugepages` on the VM, with `host.enable`:

```nix
{ virtualisation.vfio-stealth.domains.win11.hugepages = true; }
```

The hook reserves the pages at start. It worked when
`grep HugePages_Total /proc/meminfo` shows them while the VM runs. When the
start is refused for too few free pages, reserve them at boot with the host
option:

```nix
{ virtualisation.vfio-stealth.hugepages.atBoot = true; }
```

With `virtualisation.vfio-stealth.hugepages.size = "1G";` the VM's `memory`
must be a multiple of 1024, and the pages seldom come free without `atBoot`.

### Keyboard and mouse

Pass the host's keyboard and mouse to the VM:

1. Find them: `ls /dev/input/by-id/ | grep -e event-kbd -e event-mouse`.
2. Set them, with `host.enable`:

   ```nix
   {
     virtualisation.vfio-stealth.evdev = {
       keyboard = "/dev/input/by-id/usb-Example_Keyboard-event-kbd";
       mouse = "/dev/input/by-id/usb-Example_Mouse-event-mouse";
     };
   }
   ```

When the VM starts, the guest takes them. Press both Ctrl keys to switch
between host and guest. A keyboard that shows several `event-kbd` entries goes
into `evdev.extraKeyboards` with the rest.

### Looking Glass

Looking Glass shows the GPU's picture in a window on the host:

```nix
{
  virtualisation.vfio-stealth = {
    host.enable = true;
    user = "alice";
    kvmfr = { enable = true; sizeMb = 64; };
    lookingGlass.client = true;
    domains.win11.lookingGlass = true;
  };
}
```

In Windows, install the IVSHMEM driver and the Looking Glass host program, in
the release that matches `looking-glass-client` on the host, as the
[Looking Glass documentation](https://looking-glass.io/docs) describes. Then
run `looking-glass-client -f /dev/kvmfr0` on the host as `alice`. Only one VM
with `lookingGlass` runs at a time on `/dev/kvmfr0`. Leave the VM's `display`
at `"spice"`: the client sends the keyboard, mouse and clipboard through it.

## Hardened gaming settings

Each table below gives every option its value for a Windows VM that games and
should read as a real PC. Option names are under `virtualisation.vfio-stealth`. "default" means
leave the option unset. "yours" means read the value from your machine, with
the command in [Read the identity from your machine](#read-the-identity-from-your-machine)
unless the row names one. [examples/hardened-gaming.nix](../examples/hardened-gaming.nix)
sets every value that differs from the default, with placeholders to replace.

- The host CPU vendor decides the kernel patches. Everything the guest sees is
  set by the options below, on AMD and Intel alike.
- `hypervMode = "hidden"` is the stealth setting: the CPUID hypervisor bit is
  off and the guest sees no Hyper-V enlightenments. `"enlightened"` is faster
  for some workloads, and VMAware's HYPERVISOR_BIT and HYPERVISOR_STR checks
  find the VM there. Run `verify-stealth.ps1` with `-HypervMode hidden`.
- VBS and HVCI (Memory integrity) run in the guest on AMD and Intel hosts;
  turn them on in Windows Security as on a PC. Keep `hypervMode = "hidden"`:
  with `"enlightened"` VMAware also reports SINGLE_STEP and VMID, and
  INTERRUPT_SHADOW on AMD. On Intel keep `cet` at its default, off: while the
  guest sees CET, Windows' own Hyper-V does not start.
- Some VMAware checks still fire with these values: FIRMWARE, for the WAET
  table `acpi.waet` keeps for the reason the table gives; TIMER and TRAP on Intel;
  GPU_CAPABILITIES on an emulated display until a GPU is passed through; and
  THREAD_MISMATCH until `cpuIdentity.modelId` names a CPU with as many threads
  as the VM has vCPUs. On a host kernel without the kernel patches also
  KVM_INTERCEPTION, and on AMD SVM_EXCEPTIONS and TIMER; `instructionFixes` and
  `timing` remove them. The [known limitations](COMPATIBILITY.md#known-limitations)
  give the reasons.

### Module

| Option | Value | Why |
|---|---|---|
| `enable` | `true` | turns the module on |
| `cpuVendor` | yours: `"amd"` or `"intel"`, as `grep -m1 vendor_id /proc/cpuinfo` prints AuthenticAMD or GenuineIntel | picks the QEMU and OVMF pair and the kernel patches |
| `identity.seed` | a private phrase of your own, unique to this host | every unique serial and id left unset is derived from it; without it they are the values every host without a seed shares |

### Board identity

| Option | Value | Why |
|---|---|---|
| `smbios.manufacturer`, `smbios.product` | yours | the defaults are placeholders, and the rebuild warns about them |
| `smbios.biosVendor`, `smbios.biosVersion`, `smbios.biosDate`, `smbios.biosRelease` | yours | the guest reads them in WMI; `biosVendor` also names the firmware vendor |
| `smbios.serial`, `smbios.systemVersion`, `smbios.systemSku`, `smbios.systemFamily` | yours | the defaults are what an AMI desktop board reports, and every install shares them |
| `smbios.baseBoardSerial` | default with `identity.seed` | fifteen digits derived from the seed |
| `smbios.baseBoardVersion`, `smbios.baseBoardAsset`, `smbios.baseBoardLocation` | yours | the defaults are what an AMI desktop board reports |
| `smbios.chassisType` | default on a desktop, else yours | 3 is a desktop |
| `smbios.chassisVersion`, `smbios.chassisSerial`, `smbios.chassisAsset`, `smbios.chassisSku` | yours | the defaults are what an AMI desktop board reports |
| `smbios.perDomainSerials` | default | one VM at a time keeps the host's serials; turn it on when two VMs run at once, and each gets serials derived from `identity.seed` and its name |
| `smbios.memory.manufacturer`, `smbios.memory.partNumber`, `smbios.memory.speed` | yours | the guest reads them in WMI; the rebuild warns about the default maker |
| `smbios.memory.errorCorrection` | default with non-ECC memory, else yours from `sudo dmidecode -t 16` | 3 is what a desktop with non-ECC modules reports |
| `smbios.memory.maxCapacityGb` | yours, the Maximum Capacity of `sudo dmidecode -t 16` | the default is an AM5 board's; it also limits the VM's memory |
| `smbios.memory.slots`, `smbios.memory.slots.*.locator`, `smbios.memory.slots.*.bank`, `smbios.memory.slots.*.populated` | yours, from `sudo dmidecode -t 17`, populated where the host holds a module | the VM's memory splits evenly over the populated slots |
| `smbios.memory.slots.*.serial` | default with `identity.seed` | each populated slot gets eight hex digits of its own, as a module reports |
| `smbios.memory.type`, `smbios.memory.typeDetail`, `smbios.memory.rank`, `smbios.memory.voltageMillivolts` | default with 16 GB desktop DDR5 modules at JEDEC voltage, else yours | the defaults are such a module's |
| `smbios.cache.l1`, `smbios.cache.l2`, `smbios.cache.l3`, `smbios.cache.assocL1`, `smbios.cache.assocL2`, `smbios.cache.assocL3`, `smbios.cache.ecc` | yours | the defaults describe an eight core AMD Zen 4 CPU, and the guest sees the host's caches through CPUID; the rebuild warns while the sizes are unset |
| `smbios.oemStrings` | yours | an empty type 11 is a VM sign |
| `smbios.onboardDevices`, `smbios.onboardDevices.*.designation`, `smbios.onboardDevices.*.kind`, `smbios.onboardDevices.*.instance` | yours | an empty list leaves type 41 out, and the rebuild warns |
| `smbios.ports`, `smbios.ports.*.internalReference`, `smbios.ports.*.internalConnectorType`, `smbios.ports.*.externalReference`, `smbios.ports.*.externalConnectorType`, `smbios.ports.*.portType` | yours | the default list is one ASRock board's |
| `smbios.systemSlots`, `smbios.systemSlots.*.designation`, `smbios.systemSlots.*.type`, `smbios.systemSlots.*.dataBusWidth`, `smbios.systemSlots.*.currentUsage`, `smbios.systemSlots.*.length`, `smbios.systemSlots.*.id`, `smbios.systemSlots.*.characteristics1`, `smbios.systemSlots.*.characteristics2` | yours | the default list is one ASRock board's |
| `tpm.harden` | default | the TPM reports a real TPM's identity |
| `tpm.manufacturer`, `tpm.model`, `tpm.firmwareVersion` | yours | the defaults are one Infineon chip's |
| `tpm.platformManufacturer`, `tpm.platformModel` | default | they follow `smbios.manufacturer` and `smbios.product` |
| `secureBoot.platformKeyName` | yours | the guest can read it |

### CPU identity

| Option | Value | Why |
|---|---|---|
| `cpuIdentity.modelId` | a CPU model with as many threads as the VM has vCPUs | VMAware's THREAD_MISMATCH fires otherwise; null shows the host's model |
| `cpuIdentity.manufacturer` | default | it follows `cpuVendor` |
| `cpuIdentity.maxSpeed`, `cpuIdentity.currentSpeed` | yours, from `sudo dmidecode -t 4` | null leaves QEMU's 2000 |
| `cpuIdentity.socket`, `cpuIdentity.family`, `cpuIdentity.voltageDecivolts`, `cpuIdentity.externalClock`, `cpuIdentity.upgrade`, `cpuIdentity.characteristics` | default on an AM5 or LGA1700 board, else yours | the defaults come from real boards of those sockets |

### Hyper-V and CPU features

| Option | Value | Why |
|---|---|---|
| `hypervMode` | `"hidden"` | the hypervisor bit is off and no enlightenments show |
| `hypervVendorId` | default with `identity.seed` | read only in enlightened mode; twelve hex digits derived from the seed |
| `hypervFeatures.frequencies`, `hypervFeatures.ipi`, `hypervFeatures.reenlightenment`, `hypervFeatures.relaxed`, `hypervFeatures.reset`, `hypervFeatures.runtime`, `hypervFeatures.spinlocks`, `hypervFeatures.stimer`, `hypervFeatures.synic`, `hypervFeatures.tlbflush`, `hypervFeatures.vapic`, `hypervFeatures.vendor_id`, `hypervFeatures.vpindex` | default | hidden mode emits no enlightenments, so they are unused |
| `kernelCapabilities` | default | it only filters `hypervFeatures` |
| `aperfMperf` | default | a pinned VM gets the APERF and MPERF MSRs; needs kernel 6.18 or later |
| `cet` | default: on with AMD, off with Intel | on Intel, Windows' own Hyper-V, which VBS and HVCI need, does not start while the guest sees CET |
| `kvmPvEnforceCpuid` | default | on, it stops Windows in early boot |

### Emulated devices

| Option | Value | Why |
|---|---|---|
| `devices.acpiCreator.id`, `devices.acpiCreator.revision`, `devices.megasas.package`, `devices.megasas.serialDigits`, `devices.megasas.serialPrefix`, `devices.usbAudio.manufacturer`, `devices.usbAudio.name`, `devices.usbAudio.product`, `devices.usbAudio.release`, `devices.usbAudio.vendor`, `devices.usbBraille.manufacturer`, `devices.usbBraille.name`, `devices.usbFidoKey.manufacturer`, `devices.usbFidoKey.name`, `devices.usbFidoKey.product`, `devices.usbFidoKey.vendor`, `devices.usbHub.product`, `devices.usbHub.vendor`, `devices.usbPhone.androidRelease`, `devices.usbPhone.manufacturer`, `devices.usbPhone.mtpProduct`, `devices.usbPhone.name`, `devices.usbPhone.serialLength`, `devices.usbPhone.tetherProduct`, `devices.usbPhone.vendor`, `devices.usbSerial.manufacturer`, `devices.usbSerial.name`, `devices.usbSerial.product`, `devices.usbSerial.release`, `devices.usbSerial.serialLength`, `devices.usbSerial.vendor`, `devices.usbSmartcard.manufacturer`, `devices.usbSmartcard.name`, `devices.usbSmartcard.release`, `devices.usbSmartcard.serialLength`, `devices.usbStorageBridge.manufacturer`, `devices.usbStorageBridge.name`, `devices.usbStorageBridge.product`, `devices.usbStorageBridge.serialLength`, `devices.usbStorageBridge.vendor`, `devices.usbTablet.manufacturer`, `devices.vmgenidHardwareId` | default | a VM under `domains` adds none of these devices; before adding one through `extra` or `extraQemuArgs`, set its values to a real device's |
| `pciSubsystem` | yours | every emulated PCI device reports it |
| `hdaCodec` | yours with `domains.<name>.sound`, else default | only a VM with emulated sound reports it |
| `macPrefix` | yours | the maker part of the VM's MAC address |
| `spoofMac` | default | the MAC does not start with QEMU's 52:54:00 |
| `stripVirtio` | default | it matters only for a VM defined by hand; a VM under `domains` never gets the VirtIO balloon, RNG or tablet |

### Disk, monitor and ACPI

| Option | Value | Why |
|---|---|---|
| `disk.model`, `disk.firmware` | yours, a SATA drive's where you have one | the guest sees them on an emulated SATA disk |
| `disk.serial` | default with `identity.seed` | derived in the form the default model's maker uses; with another `disk.model`, twelve hex digits, or set one in that maker's form |
| `disk.opticalModel`, `disk.opticalFirmware` | default without a CD drive, else yours | the defaults name a real drive |
| `edid.manufacturer`, `edid.productCode`, `edid.serial`, `edid.dpi`, `edid.week`, `edid.year` | yours | the guest sees them on an emulated display, such as during the install |
| `edid.serialNumber` | default with `identity.seed` | QEMU's is 0 |
| `edid.resolution.width`, `edid.resolution.height` | your monitor's native mode | the preferred mode of the emulated display |
| `acpiOem.id`, `acpiOem.tableId` | yours | every ACPI table header carries them |
| `acpi.waet` | default | without it Windows' timer reads slow down and HAL init can stall; it is the one table VMAware's FIRMWARE check still flags |
| `acpi.c2Latency`, `acpi.c3Latency` | default | 101 and 1001 are what a desktop board with AMI firmware reports, and Windows boots with them; VMAware flags QEMU's 0x0FFF |
| `acpiSsdt.spoofedDevices`, `acpiSsdt.fakeBattery`, `acpiSsdt.sensorProbes` | default | the guest sees the buttons, battery, fan and thermal zones real hardware has |
| `acpiSsdt.batterySerial` | default with `identity.seed` | five digits derived from the seed |
| `pciMmio64Mb` | default | it covers GPUs up to 64 GB of VRAM; raise it on display corruption |

### Kernel switches

The patches act only in a kernel built through `packages.kernelFor`, as
[Decide on the kernel patches](#decide-on-the-kernel-patches) shows. On
Intel only `instructionFixes` is available; `timing`, `cpuidSpoof` and
`cpuidPassthrough` are AMD only. The two `kernelParams` are kernel parameters
and need no patched kernel.

| Option | Value | Why |
|---|---|---|
| `timing.enable` | default: on with AMD, refused with Intel | it hides VM exits from the guest's TSC reads, but traps RDTSC in every VM of the host, which costs frame rate; set `false` when no game you run checks timing |
| `cpuidSpoof.enable` | default: on with AMD, refused with Intel | CPUID leaf 0 is answered without the rest of the exit handling |
| `instructionFixes.enable` | default | VMCALL and VMMCALL raise #UD, as on a real PC, at no cost |
| `cpuidPassthrough.enable` | default | Windows hangs at boot when the VM has fewer vCPUs than the host has threads |
| `cpuidPassthrough.pinned` | default | experimental; Windows hangs when it is switched on during boot |
| `kernelParams.maxCState` | default | less timing jitter; raise it when the host itself games |
| `kernelParams.tscReliable` | default | the host kernel stays on the TSC |

### Host layer

| Option | Value | Why |
|---|---|---|
| `host.enable` | `true` | it loads VFIO and installs the hook that binds the GPU, reserves huge pages and isolates CPUs |
| `host.acsOverride` | default | it fakes isolation: a device still reaches its real group by DMA |
| `host.disableAspm` | default, `true` for a card that drops off the bus | it costs host power |
| `host.protectedDisks` | default, plus any further disk the host needs | setting it replaces the list, so keep `/`, `/boot`, `/nix/store` and `/home` |
| `user` | default without Looking Glass or sound, else yours | it owns `/dev/kvmfr0`, and a VM's sound plays through its PipeWire |
| `pipewireRuntimeDir` | default | it follows `user` when `users.users.<user>.uid` is set |
| `hugepages.size` | `"1G"` | fewer TLB misses; the VM's `memory` must be a multiple of 1024 |
| `hugepages.atBoot` | `true` | 1G pages seldom come free later; the host gives up that memory from boot |
| `hugepages.count` | default | null reserves the memory of every VM with `hugepages` |
| `kvmfr.enable`, `kvmfr.sizeMb`, `lookingGlass.client`, `lookingGlass.shmemSizeMb` | default without Looking Glass, else as [Looking Glass](#looking-glass) shows | the picture goes to the monitor cabled to the GPU |
| `evdev.keyboard`, `evdev.mouse` | yours, from `ls /dev/input/by-id/` | the guest takes the host's keyboard and mouse, switched with both Ctrl keys |
| `evdev.extraKeyboards` | default, or the further `event-kbd` entries of one keyboard | they follow `evdev.keyboard` |
| `pinning.isolate` | `true` | host work stays off the guest's CPUs while it runs; one pinned VM runs at a time |

### VMs

| Option | Value | Why |
|---|---|---|
| `domains` | every VM of the host | NixVirt deletes a VM that is not declared |
| `domains.<name>.uuid` | default with `identity.seed`, or the one an existing VM has | Windows activation, the TPM state and the MAC address follow it, so it never changes |
| `domains.<name>.memory` | what the host can spare, a multiple of 1024 | 1G pages need it; it must also split over the populated `smbios.memory.slots` |
| `domains.<name>.cores` | the host cores you give the guest | the guest sees one socket |
| `domains.<name>.threads` | default | two threads per core, matching the thread pairs in `pinning.vcpus` |
| `domains.<name>.machine` | a versioned q35, such as `"pc-q35-10.0"`, from `qemu-system-x86_64 -machine help` | it keeps the hardware Windows was activated on |
| `domains.<name>.pinning` | set | each vCPU gets a host CPU of its own |
| `domains.<name>.pinning.vcpus` | thread pairs from `lscpu -e`, on CPUs that share one L3 | the guest's sibling threads share a core; see [CPU pinning](#cpu-pinning) |
| `domains.<name>.pinning.emulator` | host CPUs outside `pinning.vcpus` | QEMU's own work does not stall the guest |
| `domains.<name>.pinning.iothread` | default | it serves only virtio disks |
| `domains.<name>.cpuPm` | default | on with pinning: idle vCPUs wake without an exit, and the guest gets MWAIT |
| `domains.<name>.hugepages` | `true` | locked huge pages back the guest's memory |
| `domains.<name>.gpu` | set | the guest drives a real GPU |
| `domains.<name>.gpu.address`, `domains.<name>.gpu.audio` | yours, from `lspci -nn -D` | the video and audio functions, as [Add a GPU](#add-a-gpu) shows |
| `domains.<name>.gpu.binding` | `"boot"` | the host never drives a GPU it does not use |
| `domains.<name>.gpu.ids` | yours, from `lspci -nn` | `"boot"` claims the GPU by them |
| `domains.<name>.gpu.extraFunctions` | default, or the further functions of the GPU's group | the whole group goes to the VM |
| `domains.<name>.gpu.rom`, `domains.<name>.gpu.rom.file`, `domains.<name>.gpu.rom.bar` | default | needed only as [When a ROM file is needed](#when-a-rom-file-is-needed) says |
| `domains.<name>.gpu.resizeBar2Mb`, `domains.<name>.gpu.rebindOnStop` | default | they act only with `binding = "hook"` |
| `domains.<name>.iommu` | `true` with a GPU and VBS | Windows gets the DMA protection VBS needs; every passed device then needs an IOMMU group of its own |
| `domains.<name>.stopServices` | yours: host services that hold the GPU open, such as a fan or RGB daemon | the hook stops them before it binds the GPU and starts them after |
| `domains.<name>.hostDevices` | yours: the NVMe controller the guest boots from | the guest sees the real drive at full speed; see [Prepare storage](#prepare-storage) |
| `domains.<name>.disks` | default with an NVMe controller passed through, else one disk | the controller replaces it |
| `domains.<name>.disks.*.source` | a whole disk by its `/dev/disk/by-id/` path, or an image file | the guest sees the `disk.*` identity |
| `domains.<name>.disks.*.format` | default for a disk, `"qcow2"` for a qcow2 image | a block device is raw |
| `domains.<name>.disks.*.bus` | default | a virtio disk keeps vendor 1af4 and needs the virtio-win driver |
| `domains.<name>.disks.*.cache` | default, `"writeback"` for an image on btrfs | on btrfs the default ends in read errors |
| `domains.<name>.cdroms` | default after the install | the ISOs are only for setup |
| `domains.<name>.network` | `{ }` | an emulated network card on libvirt's `default` network |
| `domains.<name>.network.type`, `domains.<name>.network.source` | default, or `"bridge"` and your bridge's name | the VM uses libvirt's `default` network |
| `domains.<name>.network.model` | default | Windows has the e1000e driver; a virtio card keeps vendor 1af4 |
| `domains.<name>.network.mac` | default, or the address Windows was activated with | null derives it from `macPrefix` and the uuid |
| `domains.<name>.tpm` | default | Windows 11 needs a TPM 2.0 |
| `domains.<name>.secureBoot` | default | Windows boots with the Microsoft keys, as on a real PC |
| `domains.<name>.display` | `"none"` | with a GPU and `evdev` the guest needs no remote display; Looking Glass needs `"spice"` |
| `domains.<name>.sound` | default with the GPU's HDMI audio or a passed USB audio device, else `"micro"` | an emulated codec reporting `hdaCodec`, played through the host's PipeWire |
| `domains.<name>.usb`, `domains.<name>.usb.*.vendor`, `domains.<name>.usb.*.product` | default, or the USB devices the guest owns | a passed-through device is the real one |
| `domains.<name>.unmount` | default | only for a filesystem on a disk the VM takes |
| `domains.<name>.lookingGlass` | default | as the `kvmfr` row above |
| `domains.<name>.cpuIdentity.characteristics`, `domains.<name>.cpuIdentity.currentSpeed`, `domains.<name>.cpuIdentity.externalClock`, `domains.<name>.cpuIdentity.family`, `domains.<name>.cpuIdentity.manufacturer`, `domains.<name>.cpuIdentity.maxSpeed`, `domains.<name>.cpuIdentity.modelId`, `domains.<name>.cpuIdentity.socket`, `domains.<name>.cpuIdentity.upgrade`, `domains.<name>.cpuIdentity.voltageDecivolts` | default | null takes the host's `cpuIdentity`; set one only for a VM that shows other hardware |
| `domains.<name>.cache.assocL1`, `domains.<name>.cache.assocL2`, `domains.<name>.cache.assocL3`, `domains.<name>.cache.ecc`, `domains.<name>.cache.l1`, `domains.<name>.cache.l2`, `domains.<name>.cache.l3` | default | null takes the host's `smbios.cache` |
| `domains.<name>.hypervMode`, `domains.<name>.kvmPvEnforceCpuid` | default | null takes the host's values above |
| `domains.<name>.extraQemuArgs` | default | for what the options do not cover |
| `domains.<name>.active` | default | NixVirt leaves the VM running or stopped as it is |
| `domains.<name>.extra` | default | for what the options do not cover |
| `domains.<name>.xml` | read only | the rendered domain |

### Read-only outputs

| Option | Value | Why |
|---|---|---|
| `acpiProcessors`, `domain`, `kernelPostPatch`, `libtpmsIdentityPatch` | read only | the module uses them; a VM defined by hand reads `domain` |
| `packages` | read only | `packages.kernelFor` builds the patched kernel |
| `bootCheck` | read only | build it after every change, as [Check the build with bootCheck](#check-the-build-with-bootcheck) shows |

## Start the VM

- In virt-manager, open the QEMU/KVM connection, select `win11` and press
  Run, or
- `virsh -c qemu:///system start win11`.

It worked when `virsh -c qemu:///system list` shows `win11` running. Without a
GPU, virt-manager's console shows the firmware and then the Windows setup.
When it fails, libvirt's error carries the reason; the hook's lines start with
`vfio-stealth hook, win11:`. With `active = true;` on the VM, NixVirt starts
it at every rebuild and boot.

## Install Windows

1. Press a key when the VM asks to boot from the CD. If it falls through to
   the firmware's boot menu, restart the VM and press a key sooner.
2. Install as on a real PC. Secure Boot and a TPM 2.0 are on, so Windows 11
   finds what it needs. Setup sees the SATA disk and the e1000e network card
   with its own drivers.
3. Only a virtio disk (`bus = "virtio"`) or a virtio network card needs the
   virtio-win drivers. Then add the virtio-win ISO from the
   [virtio-win project](https://github.com/virtio-win/virtio-win-pkg-scripts)
   to `cdroms`, and in setup load the storage driver from it.
4. After the install, shut Windows down, remove the ISOs from `cdroms`, and
   rebuild.
5. With a GPU, install its driver in Windows.

## Check from inside Windows

1. In PowerShell run as administrator, download
   [guest/verify-stealth.ps1](../guest/verify-stealth.ps1) and
   [guest/cleanup-registry.ps1](../guest/cleanup-registry.ps1):

   ```powershell
   $base = "https://raw.githubusercontent.com/Daaboulex/vfio-stealth-nix/main/guest"
   Invoke-WebRequest "$base/verify-stealth.ps1" -OutFile verify-stealth.ps1
   Invoke-WebRequest "$base/cleanup-registry.ps1" -OutFile cleanup-registry.ps1
   ```

2. In the same PowerShell:

   ```powershell
   Set-ExecutionPolicy -Scope Process Bypass
   .\verify-stealth.ps1
   ```

   Add `-HypervMode hidden` for a VM with `hypervMode = "hidden"`.
3. Read the result. Each check prints `[PASS]`, `[FAIL]`, `[WARN]` or
   `[SKIP]`, and the last line counts them. A FAIL names what still gives the
   VM away. A SKIP means the check could not run: without administrator rights
   some are skipped, and Windows PowerShell 5.1 cannot read the hypervisor
   vendor that PowerShell 7 shows. The script changes nothing.
4. `cleanup-registry.ps1` deletes what QEMU and VirtIO drivers left in
   Windows, and clears whole any event log that names a VM. It keeps boot
   drivers and the drivers of present devices. Snapshot the disk first, with
   the VM off:

   ```sh
   sudo qemu-img snapshot -c before-cleanup /var/lib/libvirt/images/win11.qcow2
   ```

   Then run `.\cleanup-registry.ps1` as administrator and restart Windows. It
   ends with the count of sections it cleaned; a `[FAIL]` line names what it
   could not remove.

## Update later

1. Bump the input and rebuild. Run `nix flake update` as the user who owns
   `/etc/nixos`:

   ```sh
   cd /etc/nixos
   nix flake update vfio-stealth
   sudo nixos-rebuild switch --flake /etc/nixos#vm-host
   ```

2. Read what the rebuild says. A removed or renamed option fails evaluation
   with a message saying what replaced it. A new assertion or warning names
   the option to set. A kernel patch that no longer fits your kernel fails the
   kernel build with a message naming the edit; keep the previous input until
   a fix lands.
3. Build `bootCheck` again, run `sudo vfio-stealth-verify-host win11`, and run
   `verify-stealth.ps1` in Windows.
4. To go back, run `sudo nixos-rebuild switch --rollback` and restore the
   previous `flake.lock`.

## When something fails

The table in [README.md](../README.md#when-it-breaks) maps the common symptoms
to their fix. The logs behind them:

- `/var/log/libvirt/qemu/win11.log`: QEMU's own output for the VM.
- `journalctl -b -u libvirtd`: libvirt itself.
- `journalctl -b -u nixvirt`: defining the declared VMs at activation.

## Undo everything

1. Shut down every VM.
2. Remove every `domains` declaration and rebuild. The VMs stay defined in
   libvirt.
3. Remove each VM with its firmware variables and TPM state, and its disk
   image:

   ```sh
   virsh -c qemu:///system undefine --nvram --tpm win11
   sudo rm /var/lib/libvirt/images/win11.qcow2
   ```

4. Remove the `virtualisation.vfio-stealth` block and the
   `boot.kernelPackages` line from your configuration, and the module and the
   input from `flake.nix`. Run `nix flake lock` in `/etc/nixos` to drop the
   input from `flake.lock`.
5. Rebuild and reboot. The stock kernel, its parameters, the sleep targets and
   the GPU's host driver come back.
6. The patched kernel stays in older boot entries until you delete the old
   generations with `sudo nix-collect-garbage -d`, after which you cannot roll
   back to them. A VM still defined in libvirt then loses the firmware and
   tables its XML names in the Nix store, unless a `result` link of that XML,
   built as [README.md](../README.md#make-a-vm) shows, is kept.
