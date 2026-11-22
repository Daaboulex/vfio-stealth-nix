# Quickstart

The shortest path to a Windows VM on the stealth stack, without a GPU.
[GUIDE.md](GUIDE.md) explains each step and adds the identity, a GPU and the
[hardened gaming settings](GUIDE.md#hardened-gaming-settings).

You need an x86_64 host with CPU virtualisation turned on, as
[Check the hardware](GUIDE.md#check-the-hardware) shows, and flakes turned on,
as the start of [GUIDE.md](GUIDE.md) shows. The commands assume a flake in
`/etc/nixos` with a host named `vm-host`; change both to yours.

## 1. Add the flake

Add the input and the module to `/etc/nixos/flake.nix`. A flake you already have keeps its own inputs and gains `vfio-stealth`:

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

## 2. Turn it on

In `configuration.nix`, with your user name in place of `alice`,
`cpuVendor = "intel";` on an Intel host, and a private phrase of your own as
`identity.seed`, from which the module derives the VM's serials and UUID:

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
    identity.seed = "pick a private phrase for this host";
  };
}
```

## 3. Rebuild

```sh
sudo nixos-rebuild switch --flake /etc/nixos#vm-host
sudo reboot
```

The rebuild warns about identity values that are still placeholders and about
kernel patches the stock kernel does not carry. A first VM runs without
them; [Read the identity from your machine](GUIDE.md#read-the-identity-from-your-machine)
and [Decide on the kernel patches](GUIDE.md#decide-on-the-kernel-patches)
settle both.

## 4. Check the build

```sh
cd ~
nix build /etc/nixos#nixosConfigurations.vm-host.config.virtualisation.vfio-stealth.bootCheck -L
```

Nix refuses a git repository another user owns: with `/etc/nixos` a git
repository owned by root, run it with `sudo`.
[Check the build with bootCheck](GUIDE.md#check-the-build-with-bootcheck) says
what a passing run prints.

## 5. Make a disk

```sh
sudo mkdir -p /var/lib/libvirt/images
sudo qemu-img create -f qcow2 /var/lib/libvirt/images/win11.qcow2 128G
```

Download the Windows 11 ISO for x64 from
[Microsoft](https://www.microsoft.com/software-download/windows11) and move it
next to the disk as `/var/lib/libvirt/images/win11.iso`. If the images sit on btrfs, add
`cache = "writeback";` to the disk in the next step;
[Prepare storage](GUIDE.md#prepare-storage) says why.

## 6. Declare the VM

Read [Declare a first VM without a GPU](GUIDE.md#declare-a-first-vm-without-a-gpu)
first: once one VM is declared, NixVirt deletes every VM on `qemu:///system`
that is not. Set `machine` to the newest type
`virsh -c qemu:///system capabilities | grep -o 'pc-q35-[0-9.]*' | sort -V | tail -1`
prints.

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

Rebuild as in step 3, without the reboot. `virsh -c qemu:///system list --all`
then shows `win11` shut off. If `virsh -c qemu:///system net-list --all` shows
the `default` network inactive:

```sh
virsh -c qemu:///system net-start default
virsh -c qemu:///system net-autostart default
```

## 7. Start it and install Windows

```sh
virsh -c qemu:///system start win11
```

Open the VM's console in virt-manager, press a key when it asks to boot from
the CD, and install as on a real PC.
[Install Windows](GUIDE.md#install-windows) covers the rest.

## 8. Check from inside Windows

In PowerShell run as administrator, download
[guest/verify-stealth.ps1](../guest/verify-stealth.ps1) and run it:

```powershell
Invoke-WebRequest https://raw.githubusercontent.com/Daaboulex/vfio-stealth-nix/main/guest/verify-stealth.ps1 -OutFile verify-stealth.ps1
Set-ExecutionPolicy -Scope Process Bypass
.\verify-stealth.ps1
```

[Check from inside Windows](GUIDE.md#check-from-inside-windows) says how to
read the result.
