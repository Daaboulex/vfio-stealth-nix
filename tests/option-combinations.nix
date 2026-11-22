{
  lib,
  runCommand,
  writeText,
  nixosSystem,
  module,
}:

let
  gpu = {
    address = "0000:01:00.0";
    audio = "0000:01:00.1";
  };

  pinned = {
    domains.vm.pinning = {
      vcpus = [
        2
        10
        3
        11
      ];
      emulator = "0-1";
      iothread = "8";
    };
  };

  factors = [
    {
      name = "cpuVendor";
      values = [
        {
          label = "amd";
          settings.cpuVendor = "amd";
        }
        {
          label = "intel";
          settings.cpuVendor = "intel";
        }
      ];
    }
    {
      name = "hypervMode";
      values = [
        {
          label = "enlightened";
          settings.hypervMode = "enlightened";
        }
        {
          label = "hidden";
          settings.hypervMode = "hidden";
        }
      ];
    }
    {
      name = "secureBoot";
      values = [
        {
          label = "on";
          settings.domains.vm.secureBoot = true;
        }
        {
          label = "off";
          settings.domains.vm.secureBoot = false;
        }
      ];
    }
    {
      name = "tpm.harden";
      values = [
        {
          label = "on";
          settings.tpm.harden = true;
        }
        {
          label = "off";
          settings.tpm.harden = false;
        }
      ];
    }
    {
      name = "host";
      values = [
        {
          label = "off";
          withoutHost = true;
          settings.host.enable = false;
        }
        {
          label = "on";
          settings.host.enable = true;
        }
      ];
    }
    {
      name = "gpu";
      values = [
        {
          label = "none";
          settings = { };
        }
        {
          label = "libvirt";
          settings.domains.vm.gpu = gpu;
        }
        {
          label = "hook";
          needsHost = true;
          settings.domains.vm.gpu = gpu // {
            binding = "hook";
            resizeBar2Mb = 256;
            rebindOnStop = true;
          };
        }
        {
          label = "boot";
          needsHost = true;
          settings.domains.vm.gpu = gpu // {
            binding = "boot";
            ids = [ "10de:2484" ];
          };
        }
      ];
    }
    {
      name = "hugepages";
      values = [
        {
          label = "off";
          settings.domains.vm.hugepages = false;
        }
        {
          label = "on";
          needsHost = true;
          settings.domains.vm.hugepages = true;
        }
      ];
    }
    {
      name = "evdev";
      values = [
        {
          label = "off";
          settings = { };
        }
        {
          label = "on";
          needsHost = true;
          settings.evdev = {
            keyboard = "/dev/input/by-id/usb-Example_Keyboard-event-kbd";
            mouse = "/dev/input/by-id/usb-Example_Mouse-event-mouse";
          };
        }
      ];
    }
    {
      name = "lookingGlass";
      values = [
        {
          label = "off";
          settings = { };
        }
        {
          label = "shmem";
          settings = {
            lookingGlass.shmemSizeMb = 32;
            domains.vm.lookingGlass = true;
          };
        }
        {
          label = "kvmfr";
          needsHost = true;
          settings = {
            kvmfr = {
              enable = true;
              sizeMb = 64;
            };
            lookingGlass.client = true;
            domains.vm.lookingGlass = true;
          };
        }
      ];
    }
    {
      name = "pinning";
      values = [
        {
          label = "none";
          settings = { };
        }
        {
          label = "pinned";
          settings = pinned;
        }
        {
          label = "isolated";
          needsHost = true;
          settings = pinned // {
            pinning.isolate = true;
          };
        }
      ];
    }
    {
      name = "perDomainSerials";
      values = [
        {
          label = "off";
          settings.smbios.perDomainSerials = false;
        }
        {
          label = "on";
          settings.smbios.perDomainSerials = true;
        }
      ];
    }
    {
      name = "acpi.waet";
      values = [
        {
          label = "on";
          settings.acpi.waet = true;
        }
        {
          label = "off";
          settings.acpi.waet = false;
        }
      ];
    }
    {
      name = "firmwareIdentity";
      values = [
        {
          label = "default";
          settings = { };
        }
        {
          label = "tower-ecc-two-slots-without-c2-c3";
          settings = {
            smbios.chassisType = 7;
            smbios.chassisVersion = "1.0";
            smbios.systemFamily = "Desktop";
            smbios.ports = [ ];
            smbios.systemSlots = [
              {
                designation = "PCIEX16_1";
                type = 195;
                dataBusWidth = 13;
                currentUsage = 3;
                length = 4;
                id = 0;
                characteristics1 = 4;
                characteristics2 = 9;
              }
            ];
            cpuIdentity = {
              socket = "LGA1851";
              family = 207;
              voltageDecivolts = 12;
              upgrade = 85;
            };
            devices.megasas.serialPrefix = "SP";
            domains.vm.cpuIdentity.externalClock = 133;
            smbios.memory = {
              type = "DDR4";
              rank = 2;
              errorCorrection = 6;
              maxCapacityGb = 64;
              slots = [
                {
                  locator = "ChannelA-DIMM0";
                  bank = "BANK 0";
                  populated = true;
                }
                {
                  locator = "ChannelB-DIMM0";
                  bank = "BANK 1";
                  populated = false;
                }
              ];
            };
            acpi = {
              c2Latency = 101;
              c3Latency = 1001;
            };
          };
        }
      ];
    }
  ];

  width = lib.length factors;
  sizeOf = k: lib.length (lib.elemAt factors k).values;
  positions = lib.range 0 (width - 1);
  valueAt = k: lib.elemAt (lib.elemAt factors k).values;

  clash = x: y: (x ? withoutHost && y ? needsHost) || (y ? withoutHost && x ? needsHost);

  pairKey =
    i: a: j: b:
    if i < j then "${toString i}=${toString a},${toString j}=${toString b}" else pairKey j b i a;

  allPairs = lib.filterAttrs (_: pair: !clash (valueAt pair.i pair.a) (valueAt pair.j pair.b)) (
    lib.listToAttrs (
      lib.concatMap (
        i:
        lib.concatMap (
          j:
          lib.concatMap (
            a:
            map (b: {
              name = pairKey i a j b;
              value = {
                inherit
                  i
                  a
                  j
                  b
                  ;
              };
            }) (lib.range 0 (sizeOf j - 1))
          ) (lib.range 0 (sizeOf i - 1))
        ) (lib.range (i + 1) (width - 1))
      ) positions
    )
  );

  pairsOf =
    row:
    lib.concatMap (
      i: map (j: pairKey i (lib.elemAt row i) j (lib.elemAt row j)) (lib.range (i + 1) (width - 1))
    ) positions;

  rowFor =
    uncovered: seed:
    lib.foldl'
      (
        row: k:
        if lib.elemAt row k != null then
          row
        else
          let
            gain =
              v:
              lib.count (
                i: i != k && lib.elemAt row i != null && uncovered ? ${pairKey i (lib.elemAt row i) k v}
              ) positions;
            allowed =
              v:
              lib.all (
                i: i == k || lib.elemAt row i == null || !clash (valueAt i (lib.elemAt row i)) (valueAt k v)
              ) positions;
            choices = lib.filter allowed (lib.range 0 (sizeOf k - 1));
            best = lib.foldl' (kept: v: if gain v > gain kept then v else kept) (lib.head choices) choices;
          in
          lib.imap0 (position: value: if position == k then best else value) row
      )
      (lib.genList (
        k:
        if k == seed.i then
          seed.a
        else if k == seed.j then
          seed.b
        else
          null
      ) width)
      positions;

  cover =
    uncovered: rows:
    if uncovered == { } then
      rows
    else
      let
        row = rowFor uncovered (lib.head (lib.attrValues uncovered));
      in
      cover (removeAttrs uncovered (pairsOf row)) (rows ++ [ row ]);

  defaults = lib.genList (_: 0) width;

  rows = cover (removeAttrs allPairs (pairsOf defaults)) [ defaults ];

  valuesOf = row: lib.imap0 (k: factor: lib.elemAt factor.values (lib.elemAt row k)) factors;

  nameOf =
    row:
    lib.concatStringsSep " " (
      lib.zipListsWith (factor: value: "${factor.name}=${value.label}") factors (valuesOf row)
    );

  base =
    { config, pkgs, ... }:
    {
      virtualisation.vfio-stealth = {
        enable = true;
        user = "alice";
        identity.seed = "combination example seed";
        smbios = {
          manufacturer = "Example Inc.";
          product = "Example Board";
          cache = {
            l1 = 512;
            l2 = 8192;
            l3 = 32768;
          };
          memory.manufacturer = "Example Memory";
          onboardDevices = [
            {
              designation = "Onboard LAN";
              kind = "ethernet";
              instance = 1;
            }
          ];
        };
        domains.vm = {
          uuid = "11111111-2222-3333-4444-555555555555";
          memory = 8192;
          cores = 2;
          disks = [ { source = "/var/lib/libvirt/images/vm.qcow2"; } ];
          network = { };
        };
      };
      users.users.alice.isNormalUser = true;
      virtualisation.libvirtd.enable = true;
      fileSystems."/" = {
        device = "/dev/disk/by-label/nixos";
        fsType = "ext4";
      };
      boot.loader.grub.enable = false;
      boot.kernelPackages = pkgs.linuxPackagesFor (
        config.virtualisation.vfio-stealth.packages.kernelFor pkgs.linux_latest
      );
      system.stateVersion = lib.trivial.release;
    };

  resultOf =
    row:
    let
      name = nameOf row;
      inherit
        (nixosSystem {
          system = "x86_64-linux";
          modules = [
            module
            base
          ]
          ++ map (value: { virtualisation.vfio-stealth = value.settings; }) (valuesOf row);
        })
        config
        ;
      failing = map (a: a.message) (lib.filter (a: !a.assertion) config.assertions);
      refused =
        if (builtins.tryEval (builtins.deepSeq failing true)).success then
          failing
        else
          builtins.trace "option-combinations: ${name} fails to evaluate its assertions" (
            builtins.deepSeq failing failing
          );
      outputs = [
        config.system.build.toplevel.drvPath
      ]
      ++ lib.mapAttrsToList (_: domain: domain.xml.drvPath) config.virtualisation.vfio-stealth.domains;
      evaluated =
        if (builtins.tryEval (builtins.deepSeq outputs true)).success then
          true
        else
          builtins.trace "option-combinations: ${name} passes every assertion and fails to evaluate" (
            builtins.deepSeq outputs true
          );
    in
    {
      inherit name refused;
      accepted = refused == [ ];
      warnings = if refused == [ ] then builtins.seq evaluated config.warnings else [ ];
    };

  results = map (row: { inherit row; } // resultOf row) rows;
  accepted = lib.filter (result: result.accepted) results;
  warned = lib.filter (result: result.warnings != [ ]) accepted;

  held = lib.genAttrs (lib.concatMap (result: pairsOf result.row) accepted) (_: true);

  labelOf = k: v: "${(lib.elemAt factors k).name}=${(valueAt k v).label}";

  missed = lib.mapAttrsToList (_: pair: "${labelOf pair.i pair.a} with ${labelOf pair.j pair.b}") (
    lib.filterAttrs (key: _: !(held ? ${key})) allPairs
  );

  report = writeText "option-combinations-report" (
    lib.concatMapStrings (
      result:
      if result.accepted then
        "  ACCEPT  ${result.name}\n"
      else
        "  REFUSE  ${result.name}\n"
        + lib.concatMapStrings (message: "          ${message}\n") result.refused
    ) results
  );
in
assert lib.assertMsg (warned == [ ])
  "option-combinations: accepted combinations warn although every identity placeholder is replaced: ${
    lib.concatMapStringsSep "; " (result: "${result.name}: ${builtins.toJSON result.warnings}") warned
  }";
assert lib.assertMsg (missed == [ ])
  "option-combinations: no accepted combination holds ${lib.concatStringsSep "; " missed}, so these settings are never evaluated together";
runCommand "option-combinations" { } ''
  cat ${report}
  echo "option-combinations: ${toString (lib.length results)} combinations, ${toString (lib.length accepted)} accepted and ${
    toString (lib.length results - lib.length accepted)
  } refused; the accepted ones hold all ${toString (lib.length (lib.attrNames allPairs))} value pairs that host.enable's dependencies allow"
  touch $out
''
