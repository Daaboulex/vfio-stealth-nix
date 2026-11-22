{
  lib,
  runCommand,
  python3,
  nixosSystem,
  module,
  vmaware,
}:

let
  system =
    (nixosSystem {
      system = "x86_64-linux";
      modules = [
        module
        {
          virtualisation.libvirtd.enable = true;
          users.users.alice.isNormalUser = true;
          virtualisation.vfio-stealth = {
            enable = true;
            cpuVendor = "amd";
            smbios.manufacturer = "Example Inc.";
            smbios.product = "Example Board";
            user = "alice";
            host.enable = true;
            hugepages = {
              size = "1G";
              atBoot = true;
              count = 8;
            };
            kvmfr = {
              enable = true;
              sizeMb = 64;
            };
            lookingGlass.client = true;
            evdev = {
              keyboard = "/dev/input/by-id/usb-Example_Keyboard-event-kbd";
              mouse = "/dev/input/by-id/usb-Example_Mouse-event-mouse";
            };
            pinning.isolate = true;
            domains.vm = {
              uuid = "11111111-2222-3333-4444-555555555555";
              memory = 8192;
              cores = 2;
              pinning = {
                vcpus = [
                  2
                  10
                  3
                  11
                ];
                emulator = "0-1";
              };
              hugepages = true;
              gpu = {
                address = "0000:01:00.0";
                audio = "0000:01:00.1";
                binding = "hook";
              };
              lookingGlass = true;
            };
          };
          fileSystems."/" = {
            device = "/dev/disk/by-label/nixos";
            fsType = "ext4";
          };
          boot.loader.grub.enable = false;
          system.stateVersion = lib.trivial.release;
        }
      ];
    }).config;

  derivationFile =
    package:
    let
      path = builtins.unsafeDiscardStringContext package.drvPath;
    in
    builtins.appendContext path { ${path}.path = true; };

  shipped = system.virtualisation.vfio-stealth.packages.libvirtQemu;
in
runCommand "vmaware-not-shipped"
  {
    nativeBuildInputs = [ python3 ];
    toplevel = derivationFile system.system.build.toplevel;
    shipped = builtins.unsafeDiscardStringContext shipped.drvPath;
  }
  ''
    python3 -I ${./vmaware-not-shipped.py} "$toplevel" "$shipped" ${vmaware.pname}
    touch $out
  ''
