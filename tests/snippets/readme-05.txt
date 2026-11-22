{
  virtualisation.vfio-stealth = {
    host.enable = true;
    user = "alice";
    kvmfr = { enable = true; sizeMb = 64; };
    lookingGlass.client = true;
    evdev.keyboard = "/dev/input/by-id/usb-Example_Keyboard-event-kbd";
    evdev.mouse = "/dev/input/by-id/usb-Example_Mouse-event-mouse";

    domains.win11 = {
      memory = 16384;
      cores = 4;
      machine = "pc-q35-10.0";
      pinning = {
        vcpus = [ 2 10 3 11 4 12 5 13 ];
        emulator = "0-1";
      };
      hugepages = true;
      disks = [ { source = "/dev/disk/by-id/nvme-Example_SSD_1TB"; } ];
      network = { };
      gpu = {
        address = "0000:01:00.0";
        audio = "0000:01:00.1";
      };
      usb = [ { vendor = 4660; product = 22136; } ];
      lookingGlass = true;
    };
  };
}
