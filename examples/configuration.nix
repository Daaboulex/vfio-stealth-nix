{ config, pkgs, ... }:

{
  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];

  environment.systemPackages = with pkgs; [
    pciutils
    usbutils
    dmidecode
  ];

  boot.kernelPackages = pkgs.linuxPackagesFor (
    config.virtualisation.vfio-stealth.packages.kernelFor pkgs.linux_latest
  );

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
    smbios = {
      manufacturer = "Example Inc.";
      product = "Example Board (EX-0000)";
      biosVendor = "American Megatrends International, LLC.";
      biosVersion = "1.A0";
      biosDate = "03/12/2025";
      memory.manufacturer = "Example Memory Inc.";
      memory.partNumber = "EX0000-16";
      cache = {
        l1 = 512;
        l2 = 8192;
        l3 = 32768;
      };
      onboardDevices = [
        {
          designation = "Onboard LAN";
          kind = "ethernet";
          instance = 1;
        }
      ];
    };
    user = "alice";
    host.enable = true;
    kvmfr = {
      enable = true;
      sizeMb = 64;
    };
    lookingGlass.client = true;
    evdev = {
      keyboard = "/dev/input/by-id/usb-Example_Keyboard-event-kbd";
      mouse = "/dev/input/by-id/usb-Example_Mouse-event-mouse";
    };

    domains.win11 = {
      memory = 16384;
      cores = 4;
      machine = "pc-q35-10.0";
      pinning = {
        vcpus = [
          2
          10
          3
          11
          4
          12
          5
          13
        ];
        emulator = "0-1";
      };
      hugepages = true;
      disks = [
        {
          source = "/var/lib/libvirt/images/win11.qcow2";
          format = "qcow2";
        }
      ];
      cdroms = [
        "/var/lib/libvirt/images/win11.iso"
        "/var/lib/libvirt/images/virtio-win.iso"
      ];
      network = { };
      gpu = {
        address = "0000:01:00.0";
        audio = "0000:01:00.1";
      };
      usb = [
        {
          vendor = 4660;
          product = 22136;
        }
      ];
      lookingGlass = true;
    };
  };
}
