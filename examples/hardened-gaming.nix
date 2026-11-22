{ config, pkgs, ... }:

{
  boot.kernelPackages = pkgs.linuxPackagesFor (
    config.virtualisation.vfio-stealth.packages.kernelFor pkgs.linux_latest
  );

  virtualisation.libvirtd.enable = true;

  virtualisation.vfio-stealth = {
    enable = true;
    cpuVendor = "amd";
    identity.seed = "pick a private phrase for this host";

    smbios = {
      manufacturer = "Example Inc.";
      product = "Example Board X1";
      biosVendor = "Example BIOS Inc.";
      biosVersion = "1.00";
      biosDate = "06/15/2025";
      biosRelease = "5.27";
      systemVersion = "1.0";
      systemSku = "EXAMPLE-SKU";
      systemFamily = "Example Family";
      baseBoardVersion = "1.0";
      baseBoardAsset = "Example Asset Tag";
      baseBoardLocation = "Example Location";
      chassisVersion = "1.0";
      chassisAsset = "Example Asset Tag";
      chassisSku = "EXAMPLE-SKU";
      memory = {
        manufacturer = "Example Memory";
        partNumber = "EX-DDR5-16G";
        speed = 5600;
        maxCapacityGb = 192;
        slots = [
          {
            locator = "DIMM_A1";
            bank = "BANK 0";
            populated = false;
          }
          {
            locator = "DIMM_A2";
            bank = "BANK 1";
            populated = true;
          }
          {
            locator = "DIMM_B1";
            bank = "BANK 2";
            populated = false;
          }
          {
            locator = "DIMM_B2";
            bank = "BANK 3";
            populated = true;
          }
        ];
      };
      cache = {
        l1 = 384;
        l2 = 6144;
        l3 = 32768;
        assocL1 = 7;
        assocL2 = 7;
        assocL3 = 8;
        ecc = 3;
      };
      oemStrings = [
        "Example OEM string"
        "Example OEM string"
        "Example OEM string"
        "Example OEM string"
      ];
      onboardDevices = [
        {
          designation = "Onboard LAN";
          kind = "ethernet";
          instance = 1;
        }
      ];
      ports = [
        {
          internalReference = "USB1";
          internalConnectorType = 255;
          externalReference = "USB 3.2 Port";
          externalConnectorType = 18;
          portType = 16;
        }
      ];
      systemSlots = [
        {
          designation = "PCIE1";
          type = 189;
          dataBusWidth = 13;
          currentUsage = 4;
          length = 4;
          id = 1;
          characteristics1 = 4;
          characteristics2 = 1;
        }
      ];
    };

    tpm = {
      manufacturer = "id:4558414D";
      model = "EXAMPLE-TPM";
      firmwareVersion = "id:00010002";
    };
    secureBoot.platformKeyName = "Example Platform Key";

    cpuIdentity = {
      modelId = "Example 6-Core Processor";
      maxSpeed = 5000;
      currentSpeed = 4500;
    };

    hypervMode = "hidden";

    macPrefix = "D8:BB:C1";

    disk = {
      model = "Example SSD 1TB";
      firmware = "EX01";
    };
    edid = {
      manufacturer = "EXA";
      serial = "Example Monitor";
      dpi = 109;
      week = 10;
      year = 2023;
      resolution = {
        width = 2560;
        height = 1440;
      };
    };

    host.enable = true;
    hugepages = {
      size = "1G";
      atBoot = true;
    };
    evdev = {
      keyboard = "/dev/input/by-id/usb-Example_Keyboard-event-kbd";
      mouse = "/dev/input/by-id/usb-Example_Mouse-event-mouse";
    };
    pinning.isolate = true;

    domains.win11 = {
      memory = 16384;
      cores = 6;
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
          6
          14
          7
          15
        ];
        emulator = "0,8";
      };
      hugepages = true;
      hostDevices = [ "0000:02:00.0" ];
      network = { };
      display = "none";
      gpu = {
        address = "0000:01:00.0";
        audio = "0000:01:00.1";
        binding = "boot";
        ids = [
          "10de:2484"
          "10de:228b"
        ];
      };
    };
  };
}
