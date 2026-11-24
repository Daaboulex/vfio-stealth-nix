# Guide

This guide takes a NixOS machine with nothing set up to a Windows VM that
reports your own board's hardware, with a GPU of its own if you want one. Work
through it top to bottom: each step ends with what you should see when it
worked, and [TROUBLESHOOTING.md](TROUBLESHOOTING.md) covers what to do when you
see something else.

Short on time? [QUICKSTART.md](QUICKSTART.md) boots a test VM in eight steps.
Already running and want the most hidden VM? Jump to
[Hardened gaming settings](#hardened-gaming-settings).

The commands assume your configuration is a flake in `/etc/nixos` with a host
named `vm-host`. Change both to yours. Every value below is an example; read
yours from your machine.

## Before you start

### Turn on flakes

A fresh NixOS has flakes and the `nix` command turned off, and every command
below needs them. Without them you see
`error: experimental Nix feature 'nix-command' is disabled`. Add this to
`/etc/nixos/configuration.nix` and run `sudo nixos-rebuild switch`:

```nix
{ nix.settings.experimental-features = [ "nix-command" "flakes" ]; }
```

### Install the tools this guide uses

You do not install them yourself. From [Add the flake](#add-the-flake) on,
the module installs every tool the steps read your machine with, `lspci`,
`dmidecode` and the rest, through `tools.enable`, which is on by default. It
also installs `vfio-stealth-gpus`, which finds your GPU's settings for you.
Before that step, [Check the hardware](#check-the-hardware) runs the finder
straight from GitHub. Once your VM runs, you can turn `tools.enable` off.

### Back up the VMs you already have

> [!WARNING]
> Once you declare one VM with this module, NixVirt manages every VM on
> `qemu:///system`. At the next rebuild it deletes each VM you have not
> declared, and it overwrites changes you make in virt-manager. The disks,
> firmware variables and TPM state stay; the VM definitions do not.

Save every VM's definition before your first declared VM:

```sh
mkdir -p ~/vm-backup
for vm in $(virsh -c qemu:///system list --all --name); do
  virsh -c qemu:///system dumpxml "$vm" > ~/vm-backup/"$vm".xml
done
```

`virsh -c qemu:///system define ~/vm-backup/<name>.xml` brings one back, once
no declared VM is left. To keep using a VM in virt-manager, declare it too, or
leave this module's `domains` empty and define its XML by hand, as
[Keep a VM outside NixVirt](#keep-a-vm-outside-nixvirt) shows.

### Keep the flake's files tracked

If `/etc/nixos` is a git repository, a flake sees only the files git tracks.
Run `git add` on each new file, such as a GPU ROM, before the rebuild that reads
it; otherwise the rebuild says the file does not exist.

## Check the hardware

This section checks that your machine can run a VM, and give it a GPU of its
own, before you change any configuration. You need:

- an x86_64 AMD or Intel CPU,
- a board whose firmware turns on the IOMMU,
- for a passed-through GPU, a second GPU for your desktop. An integrated GPU
  counts.

1. In the firmware setup, turn on CPU virtualisation (SVM on AMD, VT-x on
   Intel) and the IOMMU (often called IOMMU or AMD-Vi on AMD, VT-d on Intel).
   The menu names differ from board to board.
2. Check the CPU flag, and check that KVM is there:

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
   Intel, and lines saying devices were added to IOMMU groups. If you see
   nothing on Intel, add `boot.kernelParams = [ "intel_iommu=on" ];` to your
   configuration, rebuild, reboot and check again. If it is still empty, the
   IOMMU is off in the firmware setup.
4. List your GPUs and their IOMMU groups:

   ```sh
   nix run github:Daaboulex/vfio-stealth-nix#vfio-stealth-gpus
   ```

   For each GPU it prints its IOMMU group and whether that group can go to a
   VM. A group can when it holds only the card's own functions, such as its
   video, its HDMI audio and sometimes a USB controller, apart from PCI
   bridges. It worked when the GPU you want to pass says "The group holds only
   this card, so it can go to a VM", followed by its `gpu` settings, which you
   use in [Add a GPU](#add-a-gpu). "No IOMMU group" means the IOMMU is still
   off.

> [!IMPORTANT]
> VFIO hands a whole group to a VM, never one device of it. Devices in one
> group can reach each other's memory without the IOMMU in between, so every
> device of the group goes to the guest, or the VM does not start.

If the finder says the group also holds other devices, try another slot
first. A
slot wired to the CPU usually has a group of its own; one wired to the
chipset often shares. A PCIe port without the ACS capability puts everything
below it in one group, unless the kernel's quirk list vouches for that port.
No firmware setting adds the capability. `sudo lspci -vvv` lists it as Access
Control Services under the ports that have it.

The other way is the ACS override, `host.acsOverride`. Know what it costs
before you use it. It splits the groups, but only on a kernel that carries
the ACS override patch; mainline ignores it. The split is fake: a
passed-through device can still reach the other devices of its real group by
DMA, so a guest with that device can read or corrupt their memory.

## Add the flake

This section adds the module to your flake and turns it on.

1. Add the input and the module to `/etc/nixos/flake.nix`. If you already
   have a flake, keep its own inputs and add `vfio-stealth` to them:

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

   `nixosModules.default` brings NixVirt's module along. If your configuration
   already imports NixVirt's module, use `nixosModules.vfio-stealth` instead.
   You need no overlay: the module builds its own QEMU, OVMF and kernel
   patches.
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

   Your user joins the `libvirtd` group at the next login. The reboot in
   [Rebuild and check the host](#rebuild-and-check-the-host) gives you one.

Do not rebuild yet. The next section fills in the identity first.

## Read the identity from your machine

In this section you read your machine's hardware values and put them into the
module, so the VM reports your own board's hardware.

Start with `identity.seed`, a private phrase of 8 or more characters that no
other host uses. Some values are unique to one real part. Each of them that
you leave unset is derived from the seed, in the form that kind of part
reports:

- the board serial,
- each memory module's serial,
- the disk serial,
- the monitor's serial number,
- the battery serial,
- the Hyper-V vendor id,
- each VM's UUID.

The same seed gives the same values on every rebuild. A second host with its
own seed gets values of its own. Without a seed, these values are the ones
every host without a seed shares, which tie a guest to this module. The
rebuild warns about each of them.

Each row of the table below names the options, the command that shows their
values, and the fields to copy. Run the commands on the machine the VM will
run on. The option descriptions in [OPTIONS.md](OPTIONS.md) give the format of
each option.

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
- `edid.productCode` is hex, but `edid-decode` prints Model as a decimal
  number. Convert it with `printf '0x%04x\n' 9344`.
- `edid.dpi` is the horizontal resolution divided by the width in inches.
  Take the width in cm from "Maximum image size" and divide it by 2.54.
- `smbios.cache.*` sizes are in KB: 1 MB from `dmidecode` is 1024. Set
  `l1`, `l2` and `l3` from your own CPU. The guest sees its caches through
  CPUID, and the defaults are an eight core Zen 4's, so the rebuild warns
  while they are unset.
- `smbios.cache.assocL1`, `assocL2`, `assocL3` and `ecc` take a byte, not
  the word `dmidecode -t 7` prints. Look the word up in this table, which
  follows the SMBIOS specification,
  [DMTF DSP0134](https://www.dmtf.org/standards/smbios):

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

- Without `cpuIdentity.modelId`, the guest sees the host's CPU model as the
  SMBIOS processor Version. The other `cpuIdentity` fields you leave null
  take the values of a real board for your `cpuVendor`.
- `dmidecode -u -t N` prints each structure's bytes under Header and Data,
  16 to a row, starting at offset 0x00. A word is two bytes, low byte first:
  `10 01` is 0x0110, 272. The options take these bytes as numbers:

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

- The ACPI OEM id and table id sit in every ACPI table header. Read them
  with these commands; the brackets show the padding spaces:

  ```sh
  printf '[%s]\n' "$(sudo dd if=/sys/firmware/acpi/tables/FACP bs=1 skip=10 count=6 status=none)"
  printf '[%s]\n' "$(sudo dd if=/sys/firmware/acpi/tables/FACP bs=1 skip=16 count=8 status=none)"
  ```

- `hdaCodec` shows only in a VM with emulated sound, `domains.<name>.sound`.
  On a board without an HD Audio codec, give the VM none and leave
  `hdaCodec` as it is.
- The disk identity is what the guest sees on its emulated SATA disk, so a
  SATA drive's identity fits it better than an NVMe drive's.
- If you have no CD drive, leave `disk.opticalModel` and
  `disk.opticalFirmware` as they are; they name a real drive.
- You do not read `acpi.waet`, `acpi.c2Latency` and `acpi.c3Latency` from
  your machine. Their descriptions in [OPTIONS.md](OPTIONS.md) say when to
  change them.

Your real serial numbers, the TPM and board strings and `identity.seed`
identify your machine. Anyone who reads your configuration learns them. Keep
them out of a public repository, for example in a private flake input.
`smbios.serial` and `smbios.chassisSerial` default to `System Serial Number`
and `Default string`, which is what AMI firmware on many desktop boards
reports, so they need no seed.

For a VM that should show exactly this machine, `smbios-extract` copies your
host's own SMBIOS structures, serial numbers included, into files QEMU reads:

```sh
nix build -o ~/smbios-extract github:Daaboulex/vfio-stealth-nix#smbios-extract
sudo ~/smbios-extract/bin/smbios-extract /var/lib/vfio/smbios
```

Give a VM the files it prints through `domains.<name>.extraQemuArgs`, such as
`[ "-smbios" "file=/var/lib/vfio/smbios/<file>" ]`. QEMU refuses a file of a
type the module already sets; `domain.qemuArgs` shows those.

Put the values you read into the module:

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

Some stealth features patch the host kernel. This section helps you decide
which of them you want, because a patched kernel is one your machine
compiles itself.

On AMD, `timing.enable` and `cpuidSpoof.enable` are on by default. They patch
the host kernel's KVM to hide the time each VM exit takes, and to answer
CPUID leaf 0 without a full exit. They act only in a kernel built through
`packages.kernelFor`:

```nix
{ config, pkgs, ... }:
{
  boot.kernelPackages = pkgs.linuxPackagesFor (
    config.virtualisation.vfio-stealth.packages.kernelFor pkgs.linux_latest
  );
}
```

> [!NOTE]
> Your machine then compiles the kernel at the next rebuild, which takes a
> long time. It compiles it again at every kernel update.

The same kernel carries `instructionFixes.enable`, which is on by default on
AMD and Intel. With it, VMCALL and VMMCALL run by a program in the guest raise
an illegal-instruction error, as on a real PC. On AMD, an SVM instruction
raises the same error and ICEBP reports the right address. It has no cost.

`cpuidPassthrough.pinned` is experimental and off by default. It adds a switch
that stops CPUID exits on vCPUs pinned one to one to host cores. Turn it on
only after Windows has booted:

```sh
echo 1 | sudo tee /sys/module/kvm_amd/parameters/cpuid_passthrough
```

> [!WARNING]
> Windows hangs if this switch is on while it boots. Write `0` the same way
> before the VM restarts.

On Intel, only `instructionFixes` applies. The module refuses the others,
because they patch AMD's SVM code.

Skip `timing` when you do not need timing stealth. It traps RDTSC in every VM
of the host, which costs frame rate in games.

To skip every kernel patch, leave `boot.kernelPackages` alone and set
`timing.enable = false;`, `cpuidSpoof.enable = false;` and
`instructionFixes.enable = false;`.

## Rebuild and check the host

Now you build the configuration and check that the host is ready for a VM.

1. Rebuild and reboot, since the kernel and its parameters change:

   ```sh
   sudo nixos-rebuild switch --flake /etc/nixos#vm-host
   sudo reboot
   ```

   It worked when the rebuild ends without an error. A `vfio-stealth:` warning
   names an option that is still at its default.
2. Check the host:

   ```sh
   sudo vfio-stealth-verify-host none
   ```

   The command takes a VM's name. No VM exists yet, so expect one FAIL:
   `virsh` finds no VM called `none`. Read the host lines instead. It worked
   when these PASS: the kernel parameters, `ignore_msrs` and, on AMD with the
   patch, BetterTiming. A WARN that some IOMMU groups hold several devices is
   normal; only the GPU's group matters. A BetterTiming SKIP on AMD means the
   kernel was not built through `kernelFor`.

## Check the build with bootCheck

`bootCheck` tests the QEMU and firmware this module built for you. It boots
small Linux guests on them and reads what each guest sees:

```sh
cd ~
nix build /etc/nixos#nixosConfigurations.vm-host.config.virtualisation.vfio-stealth.bootCheck -L
```

Nix refuses a git repository that another user owns. If root owns
`/etc/nixos`, run the build with `sudo`, or from a checkout of your own.

It worked when the build ends with one line per case, each with
`finished=True`. The one exception is `secure-boot-microsoft`, which shows
`finished=False refused=True`: the Microsoft keys refuse the probe's unsigned
loader, as they should. `./result` then exists. `boots=2` or more means a boot
stalled and was retried. To read what each guest saw:

```sh
ls result/serial
nix shell nixpkgs#jq -c jq '.[] | {name, finished, seconds}' result/evidence.json
```

A failed build leaves no `result`. Its last lines name the case and the value
that gave the VM away. Remove `result` when you are done.

## Prepare storage

The VM needs a disk to install Windows on. It can be an image file, a whole
disk, or a whole NVMe controller.

To use an image file, create it:

```sh
sudo mkdir -p /var/lib/libvirt/images
sudo qemu-img create -f qcow2 /var/lib/libvirt/images/win11.qcow2 128G
```

It worked when `qemu-img` prints a `Formatting` line. Windows 11 needs at
least 64 GB.

Download the Windows 11 ISO for x64 from
[Microsoft](https://www.microsoft.com/software-download/windows11) and put it
next to the disk, for example as `/var/lib/libvirt/images/win11.iso`.

> [!WARNING]
> If `stat -f -c %T /var/lib/libvirt/images` prints `btrfs`, give the disk
> `cache = "writeback";`. With the default `none`, Windows setup on btrfs
> fails with read errors partway through.

To use a whole disk the host does not use, name it by its `/dev/disk/by-id/`
path in `disks`. The guest sees it as an emulated SATA disk with the `disk.*`
identity, not the drive's own.

> [!WARNING]
> Check twice that it is the right disk, with
> `lsblk -o NAME,MODEL,SERIAL,MOUNTPOINTS`. The guard described below does not
> cover a disk given this way.

To pass through a whole NVMe controller as a PCI device, so the guest sees
the real drive at full speed:

1. Find its address: `readlink -f /sys/class/nvme/nvme1/device` ends in it,
   such as `0000:02:00.0`.
2. Check that it has an IOMMU group of its own.
3. Add it to the VM as `hostDevices = [ "0000:02:00.0" ];`.

With `host.enable`, a hook guards the disks the host needs. It refuses to
start a VM that passes through a PCI device under a path of
`host.protectedDisks` or an active swap device. Before the VM starts, it also
unmounts any filesystem mounted from a disk the VM takes. Setting
`host.protectedDisks` replaces the default list, so keep `/`, `/boot`,
`/nix/store` and `/home` in yours.

## Declare a first VM without a GPU

This section declares a Windows VM without a GPU. You add the GPU later, in
[Add a GPU](#add-a-gpu).

> [!IMPORTANT]
> This is the step after which NixVirt deletes every VM you have not
> declared. Back them up first, as
> [Back up the VMs you already have](#back-up-the-vms-you-already-have) shows.

1. Print the newest q35 machine type with
   `virsh -c qemu:///system capabilities | grep -o 'pc-q35-[0-9.]*' | sort -V | tail -1`
   and use it for `machine`. The `pc-q35-10.0` below is an example. The VM's
   UUID comes from `identity.seed` and the VM's name. Set `uuid` only to keep
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
   as shut off. If it does not, `journalctl -b -u nixvirt` says why.
4. The VM uses libvirt's `default` network. If
   `virsh -c qemu:///system net-list --all` shows it as inactive, start it and
   turn on its autostart:

   ```sh
   virsh -c qemu:///system net-start default
   virsh -c qemu:///system net-autostart default
   ```

   To put the VM on a host bridge instead, set
   `network = { type = "bridge"; source = "br0"; };` with your bridge's name.
5. Run `sudo vfio-stealth-verify-host win11`. It worked when it ends with no
   failures.

From now on, change the VM in Nix, not in virt-manager. The next rebuild
overwrites changes you make there.

> [!WARNING]
> A rebuild that changes a running VM's declaration powers the VM off and
> starts it again. Shut Windows down before such a rebuild.

### Keep a VM outside NixVirt

If you want to manage a VM in virt-manager yourself, build its XML, define it
by hand, and remove every declaration from `domains`:

```sh
nix build -o ~/win11-domain /etc/nixos#nixosConfigurations.vm-host.config.virtualisation.vfio-stealth.domains.win11.xml
virsh -c qemu:///system define ~/win11-domain
```

The XML names the firmware and the ACPI and SMBIOS tables in the Nix store.
Only the `~/win11-domain` link keeps them from garbage collection, so keep that
link. A VM defined this way gets none of the hook's work at start and stop.

## Add a GPU

This section gives the VM a real GPU of its own. Your desktop then needs a
second GPU, as [Check the hardware](#check-the-hardware) says.

1. Print the GPU's settings. The module installed the finder:

   ```sh
   vfio-stealth-gpus
   ```

   For a card whose IOMMU group can go to a VM, it prints a `gpu = { ... };`
   block with its address, its audio function, any further functions as
   `extraFunctions`, and its ids. If your card shows no block, the finder
   says why: its group also holds other devices, or the IOMMU is off.
2. Pick how the GPU reaches vfio-pci:

   | `gpu.binding` | When it fits |
   |---|---|
   | `"boot"` | a second GPU the host never uses; two identical cards both go |
   | `"libvirt"`, the default | a GPU the host uses for other work while the VM is off, with no display on it |
   | `"hook"` | a card that works only after its host driver has set it up |

   None of them fits the GPU your desktop draws on. The module stops no
   desktop, and a GPU that a running desktop holds open cannot be taken from
   its driver cleanly. Run the desktop on another GPU, and cable the
   passed-through card to a monitor input of its own.
3. Declare it with the settings the finder printed, the binding you picked,
   and the host layer on:

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

   Keep `extraFunctions` if the finder printed it. `ids` matters only with
   `"boot"`.
4. Rebuild, and reboot if you use `"boot"`. With `"boot"`, it worked when
   `lspci -k -s 01:00.0` shows `Kernel driver in use: vfio-pci`.

> [!NOTE]
> With `"boot"`, vfio-pci takes the card early in boot, before the card's own
> driver. You need no driver blacklist. But if that card is the one your
> firmware shows its picture on, your disk-encryption password prompt goes
> with it and the screen stays dark. Put the host GPU's driver in the initrd so
> the prompt moves there: `hardware.amdgpu.initrd.enable = true;` for an AMD
> host GPU, `boot.initrd.kernelModules = [ "i915" ];` for an Intel one. Or make
> the host GPU the primary display in the firmware setup.

The VM then has no emulated video card. You see its picture on the monitor
cabled to the GPU, or in Looking Glass. The guest sees the GPU's functions as
one card in one slot, as a PC does.

Before the hook binds a GPU, it checks that no host process holds the card
open. If one does, the hook refuses to start the VM and names the processes: a
driver cannot release a card in use, and the host can hang trying. If a fan,
RGB or monitoring daemon keeps the card open, put it in `stopServices`. The
hook stops it before the bind and starts it again when the VM stops:

```nix
{ virtualisation.vfio-stealth.domains.win11.stopServices = [ "coolercontrold.service" ]; }
```

A KDE Plasma session opens every GPU it finds. To make it leave the other card
alone, set `KWIN_DRM_DEVICES` to the host GPU's `/dev/dri/card` path.

If you use Windows' Virtualization-based Security (Memory integrity) with a
passed GPU, the VM needs its own IOMMU, `iommu = true;`. Without it, the
screen stays black once VBS starts. The VM's IOMMU gives each passed device an
address space of its own. QEMU refuses that for two devices in one IOMMU
group, so the hook refuses such a domain and names the group. A GPU whose
video and audio functions share a group runs without `iommu`, and so without
VBS.

### When a ROM file is needed

Usually the guest reads the card's own ROM, and you need no file. But the host
firmware alters the ROM of the card it boots on. A guest given that card can
then show no picture until Windows loads its driver, or none at all. In that
case, give the guest a clean copy of the ROM:

1. Make the other GPU the primary one in the firmware setup, and boot.
2. Dump the ROM:

   ```sh
   cd /sys/bus/pci/devices/0000:01:00.0
   echo 1 | sudo tee rom
   sudo cat rom > ~/vbios.rom
   echo 0 | sudo tee rom
   head -c 2 ~/vbios.rom | od -An -tx1
   ```

   It worked when the last line prints `55 aa`.
3. Copy it next to your `flake.nix` and run `git add vbios.rom`, since a flake
   sees only files git tracks. Then set `gpu.rom.file = ./vbios.rom;`.

If the picture is corrupted rather than missing, suspect the ROM BAR instead:
set `gpu.rom.bar = false;`.

A card may drop off the bus, or fail to start a second time without a host
reboot. It may be losing its PCIe link in a power-saving state. Then set
`host.disableAspm = true;`, which costs some host power. If the guest driver
fails on the card's large BAR, or the card starts only once per host boot, you
can set `gpu.resizeBar2Mb` with `binding = "hook"`.

## USB devices, CPU pinning, huge pages, input and Looking Glass

This section covers optional settings. Each subsection stands on its own, so
use only the ones you need.

### USB devices

To give the VM a USB device, you need its ids as numbers. `lsusb` prints them
in hex, such as `ID 1234:5678`. `printf '%d %d\n' 0x1234 0x5678` converts them
and prints `4660 22136`.

```nix
{ virtualisation.vfio-stealth.domains.win11.usb = [ { vendor = 4660; product = 22136; } ]; }
```

The device leaves the host while the VM runs. If you plug it in again while
the VM runs, it goes back to the VM.

### CPU pinning

Pinning gives each vCPU a host CPU of its own. First find which CPUs are the
two threads of one core with `lscpu -e`. On an 8-core, 16-thread CPU it often
looks like this, where CPUs 0 and 8 share core 0:

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

Your numbering can differ, so read it from `lscpu -e`. If the L3 field
differs between CPUs, keep the guest on CPUs that share one L3. Add
`pinning.iothread` only for virtio disks. A pinned VM gets `cpuPm` on. Set
`cpuPm = false;` on it when the host still runs its own work on those CPUs.

Pinned to the cores of one L3, with VBS and the VM's IOMMU on, a 7-Zip
benchmark in the guest reached 91% of the same cores' bare-metal score. A
scheduler daemon that lowers QEMU's priority, such as ananicy, cuts that
score, so keep QEMU at normal priority.

To also keep the host's own work off the guest's CPUs while the guest runs,
set this host option. It sits beside `domains` and needs `host.enable`:

```nix
{ virtualisation.vfio-stealth.pinning.isolate = true; }
```

### Huge pages

Huge pages back the guest's memory with large, locked pages. Set `hugepages`
on the VM, with `host.enable`:

```nix
{ virtualisation.vfio-stealth.domains.win11.hugepages = true; }
```

The hook reserves the pages when the VM starts. It worked when
`grep HugePages_Total /proc/meminfo` shows them while the VM runs. If the
start is refused because too few pages are free, reserve them at boot with
the host option:

```nix
{ virtualisation.vfio-stealth.hugepages.atBoot = true; }
```

With `virtualisation.vfio-stealth.hugepages.size = "1G";`, the VM's `memory`
must be a multiple of 1024, and the pages seldom come free without `atBoot`.

### Keyboard and mouse

You can pass the host's keyboard and mouse to the VM, and switch them between
host and guest with a key combination:

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
between host and guest. To switch with other keys, set `evdev.grabToggle`, for
example to `"alt-alt"` for both Alt keys; the option lists every choice. If
one keyboard shows several `event-kbd` entries, put the rest of them into
`evdev.extraKeyboards`.

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

In Windows, install the IVSHMEM driver and the Looking Glass host program, as
the [Looking Glass documentation](https://looking-glass.io/docs) describes.
Use the release that matches `looking-glass-client` on the host. Then run
`looking-glass-client -f /dev/kvmfr0` on the host as `alice`. Only one VM with
`lookingGlass` runs at a time on `/dev/kvmfr0`. Leave the VM's `display` at
`"spice"`: the client sends the keyboard, mouse and clipboard through it.

## Hardened gaming settings

This section gives every option a value for a Windows VM that games and
should read as a real PC. Use it once your VM runs and you want it as hidden
as it can be.

Option names are under `virtualisation.vfio-stealth`. In the Value column,
"default" means you leave the option unset. "yours" means you read the value
from your machine, with the command in
[Read the identity from your machine](#read-the-identity-from-your-machine)
unless the row names one.
[examples/hardened-gaming.nix](../examples/hardened-gaming.nix) sets every
value that differs from the default, with placeholders to replace.

Keep these points in mind:

- The host CPU vendor decides the kernel patches. The options below set
  everything the guest sees, on AMD and Intel alike.
- `hypervMode = "hidden"` is the stealth setting: the CPUID hypervisor bit is
  off, and the guest sees no Hyper-V enlightenments. `"enlightened"` is faster
  for some workloads, but VMAware's HYPERVISOR_BIT and HYPERVISOR_STR checks
  find the VM there. Run `verify-stealth.ps1` with `-HypervMode hidden`.
- VBS and HVCI (Memory integrity) run in the guest on AMD and Intel hosts.
  Turn them on in Windows Security as on a PC. Keep `hypervMode = "hidden"`:
  with `"enlightened"`, VMAware also reports SINGLE_STEP and VMID, and
  INTERRUPT_SHADOW on AMD. On Intel, keep `cet` at its default, off: while the
  guest sees CET, Windows' own Hyper-V does not start.
- Some VMAware checks still fire with these values:
  - FIRMWARE, for the WAET table, which `acpi.waet` keeps because Windows
    needs it for fast timer reads;
  - TIMER and TRAP on Intel;
  - GPU_CAPABILITIES on an emulated display, until a GPU is passed through;
  - THREAD_MISMATCH, until `cpuIdentity.modelId` names a CPU with as many
    threads as the VM has vCPUs;
  - on a host kernel without the kernel patches, also KVM_INTERCEPTION, and on
    AMD SVM_EXCEPTIONS and TIMER. `instructionFixes` and `timing` remove them.

  The [known limitations](COMPATIBILITY.md#known-limitations) give the
  reasons.

### Module

These options turn the module on and name your CPU vendor and your seed.

| Option | Value | Why |
|---|---|---|
| `enable` | `true` | turns the module on |
| `cpuVendor` | yours: `"amd"` or `"intel"`, as `grep -m1 vendor_id /proc/cpuinfo` prints AuthenticAMD or GenuineIntel | picks the QEMU and OVMF pair and the kernel patches |
| `tools.enable` | default while you set up, `false` after | it installs the finder and the tools the setup reads your machine with |
| `identity.seed` | a private phrase of your own, unique to this host | every unique serial and id left unset is derived from it; without it they are the values every host without a seed shares |

### Board identity

These options make the guest see your own board, firmware, memory, caches,
ports, slots, onboard devices and TPM.

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

These options set the processor the guest reads in SMBIOS.

| Option | Value | Why |
|---|---|---|
| `cpuIdentity.modelId` | a CPU model with as many threads as the VM has vCPUs | VMAware's THREAD_MISMATCH fires otherwise; null shows the host's model |
| `cpuIdentity.manufacturer` | default | it follows `cpuVendor` |
| `cpuIdentity.maxSpeed`, `cpuIdentity.currentSpeed` | yours, from `sudo dmidecode -t 4` | null leaves QEMU's 2000 |
| `cpuIdentity.socket`, `cpuIdentity.family`, `cpuIdentity.voltageDecivolts`, `cpuIdentity.externalClock`, `cpuIdentity.upgrade`, `cpuIdentity.characteristics` | default on an AM5 or LGA1700 board, else yours | the defaults come from real boards of those sockets |

### Hyper-V and CPU features

These options decide what the guest sees of the hypervisor and of the CPU's
features.

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

These options set what the devices QEMU emulates report about themselves.

| Option | Value | Why |
|---|---|---|
| `devices.acpiCreator.id`, `devices.acpiCreator.revision`, `devices.megasas.package`, `devices.megasas.serialDigits`, `devices.megasas.serialPrefix`, `devices.usbAudio.manufacturer`, `devices.usbAudio.name`, `devices.usbAudio.product`, `devices.usbAudio.release`, `devices.usbAudio.vendor`, `devices.usbBraille.manufacturer`, `devices.usbBraille.name`, `devices.usbFidoKey.manufacturer`, `devices.usbFidoKey.name`, `devices.usbFidoKey.product`, `devices.usbFidoKey.vendor`, `devices.usbHub.product`, `devices.usbHub.vendor`, `devices.usbPhone.androidRelease`, `devices.usbPhone.manufacturer`, `devices.usbPhone.mtpProduct`, `devices.usbPhone.name`, `devices.usbPhone.serialLength`, `devices.usbPhone.tetherProduct`, `devices.usbPhone.vendor`, `devices.usbSerial.manufacturer`, `devices.usbSerial.name`, `devices.usbSerial.product`, `devices.usbSerial.release`, `devices.usbSerial.serialLength`, `devices.usbSerial.vendor`, `devices.usbSmartcard.manufacturer`, `devices.usbSmartcard.name`, `devices.usbSmartcard.release`, `devices.usbSmartcard.serialLength`, `devices.usbStorageBridge.manufacturer`, `devices.usbStorageBridge.name`, `devices.usbStorageBridge.product`, `devices.usbStorageBridge.serialLength`, `devices.usbStorageBridge.vendor`, `devices.usbTablet.manufacturer`, `devices.vmgenidHardwareId` | default | a VM under `domains` adds none of these devices; before adding one through `extra` or `extraQemuArgs`, set its values to a real device's |
| `pciSubsystem` | yours | every emulated PCI device reports it |
| `hdaCodec` | yours with `domains.<name>.sound`, else default | only a VM with emulated sound reports it |
| `macPrefix` | yours | the maker part of the VM's MAC address |
| `spoofMac` | default | the MAC does not start with QEMU's 52:54:00 |
| `stripVirtio` | default | it matters only for a VM defined by hand; a VM under `domains` never gets the VirtIO balloon, RNG or tablet |

### Disk, monitor and ACPI

These options set the disk, the monitor and the ACPI tables the guest sees.

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

These options turn the host kernel patches and two kernel parameters on or
off. The patches act only in a kernel built through `packages.kernelFor`, as
[Decide on the kernel patches](#decide-on-the-kernel-patches) shows. On
Intel, only `instructionFixes` is available; `timing`, `cpuidSpoof` and
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

These options set up the host side: VFIO, the hook, huge pages, Looking Glass,
input and CPU isolation.

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
| `evdev.keyboard`, `evdev.mouse` | yours, from `ls /dev/input/by-id/` | the guest takes the host's keyboard and mouse |
| `evdev.grabToggle` | default, or the keys you switch with | both Ctrl keys switch between host and guest unless you name others |
| `evdev.extraKeyboards` | default, or the further `event-kbd` entries of one keyboard | they follow `evdev.keyboard` |
| `pinning.isolate` | `true` | host work stays off the guest's CPUs while it runs; one pinned VM runs at a time |

### VMs

These options describe each VM under `domains`.

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

You do not set these. The module produces them.

| Option | Value | Why |
|---|---|---|
| `acpiProcessors`, `domain`, `kernelPostPatch`, `libtpmsIdentityPatch` | read only | the module uses them; a VM defined by hand reads `domain` |
| `packages` | read only | `packages.kernelFor` builds the patched kernel |
| `bootCheck` | read only | build it after every change, as [Check the build with bootCheck](#check-the-build-with-bootcheck) shows |

## Start the VM

Start the VM in one of two ways:

- In virt-manager, open the QEMU/KVM connection, select `win11` and press
  Run, or
- run `virsh -c qemu:///system start win11`.

It worked when `virsh -c qemu:///system list` shows `win11` running. Without a
GPU, virt-manager's console shows the firmware and then the Windows setup.

If the start fails, libvirt's error carries the reason. The hook's lines start
with `vfio-stealth hook, win11:`. With `active = true;` on the VM, NixVirt
starts it at every rebuild and boot.

## Install Windows

This section installs Windows in the VM.

1. Press a key when the VM shows "Press any key to boot from CD or DVD". The
   prompt waits only about five seconds after the firmware starts, so open
   the console first: start the VM from virt-manager and click into its
   window. With `evdev` set, the guest already has your keyboard. If the VM
   falls through to the firmware's boot menu, restart it and press a key
   sooner.
2. Install Windows as on a real PC. Secure Boot and a TPM 2.0 are on, so
   Windows 11 finds what it needs. Setup sees the SATA disk and the e1000e
   network card with its own drivers.
3. You need the virtio-win drivers only for a virtio disk (`bus = "virtio"`)
   or a virtio network card. In that case, add the virtio-win ISO from the
   [virtio-win project](https://github.com/virtio-win/virtio-win-pkg-scripts)
   to `cdroms`, and load the storage driver from it in setup.
4. After the install, shut Windows down, remove the ISOs from `cdroms`, and
   rebuild.
5. If the VM has a GPU, install the GPU's driver in Windows.

## Check from inside Windows

Two scripts from this project run inside Windows. `verify-stealth.ps1` shows
what still gives the VM away, and `cleanup-registry.ps1` removes what QEMU and
VirtIO drivers left behind.

1. Open PowerShell as administrator, and download
   [guest/verify-stealth.ps1](../guest/verify-stealth.ps1) and
   [guest/cleanup-registry.ps1](../guest/cleanup-registry.ps1):

   ```powershell
   $base = "https://raw.githubusercontent.com/Daaboulex/vfio-stealth-nix/main/guest"
   Invoke-WebRequest "$base/verify-stealth.ps1" -OutFile verify-stealth.ps1
   Invoke-WebRequest "$base/cleanup-registry.ps1" -OutFile cleanup-registry.ps1
   ```

2. In the same PowerShell, run the check:

   ```powershell
   Set-ExecutionPolicy -Scope Process Bypass
   .\verify-stealth.ps1
   ```

   For a VM with `hypervMode = "hidden"`, add `-HypervMode hidden`.
3. Read the result. Each check prints `[PASS]`, `[FAIL]`, `[WARN]` or
   `[SKIP]`, and the last line counts them. A FAIL names what still gives the
   VM away. A SKIP means the check could not run: without administrator rights
   some checks are skipped, and Windows PowerShell 5.1 cannot read the
   hypervisor vendor that PowerShell 7 shows. The script changes nothing.
4. `cleanup-registry.ps1` deletes what QEMU and VirtIO drivers left in
   Windows, and clears the whole of any event log that names a VM. It keeps
   boot drivers and the drivers of present devices. Because it deletes,
   snapshot the disk first, with the VM off:

   ```sh
   sudo qemu-img snapshot -c before-cleanup /var/lib/libvirt/images/win11.qcow2
   ```

   Then run `.\cleanup-registry.ps1` as administrator and restart Windows. It
   ends with the count of sections it cleaned; a `[FAIL]` line names what it
   could not remove.

### Read a VMAware result

[VMAware](https://github.com/kernelwernel/VMAware) is the detection tool this
project measures itself against. Each technique it reports names one thing it
found, and most of them go away with a setting. This table gives the reason
for each and the setting that removes it:

| VMAware reports | Why | What removes it |
|---|---|---|
| HYPERVISOR_BIT, HYPERVISOR_STR, and in a Linux guest `systemd virtualisation` | the default `hypervMode = "enlightened"` shows the hypervisor, which the Hyper-V speedups need | `hypervMode = "hidden"` |
| SINGLE_STEP and VMID, and INTERRUPT_SHADOW on AMD, with VBS or Memory integrity on | Windows' own Hyper-V in enlightened mode | `hypervMode = "hidden"` |
| THREAD_MISMATCH | the VM has fewer vCPUs than the CPU model it shows has threads | `cpuIdentity.modelId`, naming a CPU with as many threads as the VM has vCPUs |
| FIRMWARE | the WAET table, which Windows uses to read its timers the fast way; on Intel also the VM's IOMMU, `iommu` | `acpi.waet = false`, which may slow Windows down; leaving `iommu` off |
| GPU_CAPABILITIES | an emulated display, whose basic driver has no gamma ramp | not measured yet: a passed-through GPU with its own driver may remove it |
| KVM_INTERCEPTION, and SVM_EXCEPTIONS on AMD | a host kernel without the kernel patches | the kernel built through `packages.kernelFor` |
| TIMER, and TRAP on Intel | how long a CPUID takes, and the Intel CPU's own debug behaviour | `timing.enable` on AMD; nothing on Intel |
| low file access count, in a Linux guest | the desktop's list of recently opened files has 10 entries or fewer, as on any fresh install | using the desktop for a while |

[COMPATIBILITY.md](COMPATIBILITY.md#known-limitations) gives the full reason
for each that stays.

## Update later

This section moves the module to a newer version and checks the VM again.

1. Bump the input and rebuild. Run `nix flake update` as the user who owns
   `/etc/nixos`:

   ```sh
   cd /etc/nixos
   nix flake update vfio-stealth
   sudo nixos-rebuild switch --flake /etc/nixos#vm-host
   ```

2. Read what the rebuild says:
   - A removed or renamed option fails evaluation with a message saying what
     replaced it.
   - A new assertion or warning names the option to set.
   - A kernel patch that no longer fits your kernel fails the kernel build
     with a message naming the edit. Keep the previous input until a fix
     lands.
3. Check again: build `bootCheck`, run `sudo vfio-stealth-verify-host win11`,
   and run `verify-stealth.ps1` in Windows.
4. To go back, run `sudo nixos-rebuild switch --rollback` and restore the
   previous `flake.lock`.

## When something fails

When a step shows something other than what it says you should see,
[TROUBLESHOOTING.md](TROUBLESHOOTING.md) lists each symptom with its cause and
fix, and the logs to read.

## Undo everything

This section removes the VMs and the module, and brings back the stock kernel.

1. Shut down every VM.
2. Remove every `domains` declaration and rebuild. The VMs stay defined in
   libvirt.
3. Remove each VM with its firmware variables and TPM state, and its disk
   image. This deletes the disk image and the Windows install in it:

   ```sh
   virsh -c qemu:///system undefine --nvram --tpm win11
   sudo rm /var/lib/libvirt/images/win11.qcow2
   ```

4. Remove the `virtualisation.vfio-stealth` block and the
   `boot.kernelPackages` line from your configuration, and the module and the
   input from `flake.nix`. Then run `nix flake lock` in `/etc/nixos` to drop
   the input from `flake.lock`.
5. Rebuild and reboot. The stock kernel, its parameters, the sleep targets and
   the GPU's host driver come back.
6. The patched kernel stays in older boot entries until you delete the old
   generations with `sudo nix-collect-garbage -d`. After that, you cannot roll
   back to them. A VM still defined in libvirt then loses the firmware and
   tables its XML names in the Nix store, unless you keep a `result` link of
   that XML, built as [Keep a VM outside NixVirt](#keep-a-vm-outside-nixvirt)
   shows.
