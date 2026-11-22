{
  lib,
  runCommand,
  nixosSystem,
  module,
}:

let
  evaluate =
    settings:
    (nixosSystem {
      system = "x86_64-linux";
      modules = [
        module
        {
          virtualisation.vfio-stealth = lib.recursiveUpdate {
            enable = true;
            cpuVendor = "amd";
            smbios.manufacturer = "Example Inc.";
            smbios.product = "Example Board";
            host.enable = true;
            domains.vm = {
              memory = 4096;
              cores = 2;
            };
          } settings;
          virtualisation.libvirtd.enable = true;
          fileSystems."/" = {
            device = "/dev/disk/by-label/nixos";
            fsType = "ext4";
          };
          boot.loader.grub.enable = false;
          system.stateVersion = lib.trivial.release;
        }
      ];
    }).config.virtualisation.vfio-stealth;

  seeded = evaluate { identity.seed = "first example seed"; };
  other = evaluate { identity.seed = "second example seed"; };
  plainModel = evaluate {
    identity.seed = "first example seed";
    disk.model = "Example SSD 1TB";
  };
  pinned = evaluate {
    identity.seed = "first example seed";
    smbios.baseBoardSerial = "123456789012345";
    domains.vm.uuid = "11111111-2222-3333-4444-555555555555";
  };
  perVm =
    seed:
    (evaluate {
      identity.seed = seed;
      smbios.perDomainSerials = true;
    }).domains.vm.xml;
  unseeded =
    (nixosSystem {
      system = "x86_64-linux";
      modules = [
        module
        {
          virtualisation.vfio-stealth = {
            enable = true;
            cpuVendor = "amd";
            smbios.manufacturer = "Example Inc.";
            smbios.product = "Example Board";
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

  matches = pattern: value: builtins.match pattern (toString value) != null;

  identityOf = cfg: {
    baseBoardSerial = cfg.smbios.baseBoardSerial;
    diskSerial = cfg.disk.serial;
    inherit (cfg) hypervVendorId;
    edidSerialNumber = cfg.edid.serialNumber;
    inherit (cfg.acpiSsdt) batterySerial;
    uuid = cfg.domains.vm.uuid;
    slots = slotSerials cfg;
  };

  slotSerials =
    cfg:
    map (line: builtins.elemAt line 0) (
      lib.filter (line: line != null) (
        map (builtins.match " +[{] \"[^\"]*\", \"[^\"]*\", true, \"([0-9A-Za-z]+)\" },") (
          lib.splitString "\n" cfg.packages.qemu.postPatch
        )
      )
    );

  mine = identityOf seeded;
  theirs = identityOf other;

  checks = [
    {
      ok = matches "[0-9]{15}" mine.baseBoardSerial;
      what = "the derived baseboard serial is fifteen digits: ${mine.baseBoardSerial}";
    }
    {
      ok = matches "WD-WCC[0-9A-F]{9}" mine.diskSerial;
      what = "the derived serial of the default WD model is WD-WCC and nine characters: ${mine.diskSerial}";
    }
    {
      ok = matches "[0-9A-F]{12}" plainModel.disk.serial;
      what = "the derived serial of another model is twelve hex digits: ${plainModel.disk.serial}";
    }
    {
      ok = matches "[0-9A-F]{12}" mine.hypervVendorId;
      what = "the derived Hyper-V vendor id is twelve hex digits: ${mine.hypervVendorId}";
    }
    {
      ok = mine.edidSerialNumber != 0;
      what = "the derived EDID serial number is not QEMU's 0";
    }
    {
      ok = matches "[0-9]{5}" mine.batterySerial && mine.batterySerial != "41167";
      what = "the derived battery serial is five digits other than the shared one: ${mine.batterySerial}";
    }
    {
      ok = matches "[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}" mine.uuid;
      what = "a VM without a uuid gets a version 4 UUID: ${mine.uuid}";
    }
    {
      ok =
        lib.length mine.slots == 2
        && lib.all (matches "[0-9A-F]{8}") mine.slots
        && lib.length (lib.unique mine.slots) == 2;
      what = "each populated memory slot QEMU is built with carries its own eight hex digit serial: ${builtins.toJSON mine.slots}";
    }
    {
      ok = lib.hasInfix "atoi(info->serial) : ${toString mine.edidSerialNumber}U;" seeded.packages.qemu.postPatch;
      what = "QEMU is built with the EDID serial number";
    }
    {
      ok = lib.hasInfix ''"${mine.batterySerial}",'' seeded.packages.acpiTables.postPatch;
      what = "the battery table is built with the battery serial";
    }
    {
      ok = lib.all (field: mine.${field} != theirs.${field}) (lib.attrNames mine);
      what = "a second seed changes every derived value: ${builtins.toJSON mine} against ${builtins.toJSON theirs}";
    }
    {
      ok =
        pinned.smbios.baseBoardSerial == "123456789012345"
        && pinned.domains.vm.uuid == "11111111-2222-3333-4444-555555555555";
      what = "a value set by hand wins over the seed";
    }
    {
      ok = perVm "first example seed" != perVm "second example seed";
      what = "with perDomainSerials, the VM's serials follow the seed";
    }
    {
      ok = lib.any (
        warning:
        lib.hasInfix "identity.seed" warning
        && lib.all (field: lib.hasInfix field warning) [
          "smbios.baseBoardSerial"
          "disk.serial"
          "hypervVendorId"
          "edid.serialNumber"
          "acpiSsdt.batterySerial"
        ]
      ) unseeded.warnings;
      what = "a host without a seed is warned about each shared value: ${builtins.toJSON unseeded.warnings}";
    }
    {
      ok = lib.any (lib.hasInfix "smbios.cache.l1, smbios.cache.l2, smbios.cache.l3 left unset") unseeded.warnings;
      what = "a host that leaves the SMBIOS cache sizes unset is warned: ${builtins.toJSON unseeded.warnings}";
    }
    {
      ok = slotSerials unseeded.virtualisation.vfio-stealth == [ ];
      what = "without a seed no memory slot gets a serial";
    }
  ];

  failed = map (check: check.what) (lib.filter (check: !check.ok) checks);
in
assert lib.assertMsg (failed == [ ]) "identity-seed: ${lib.concatStringsSep "; " failed}";
runCommand "identity-seed" { } ''
  echo "${toString (lib.length checks)} identity seed checks hold"
  touch $out
''
