{
  lib,
  runCommand,
  nixosSystem,
  module,
}:

let
  evaluateWith =
    host: settings:
    (nixosSystem {
      system = "x86_64-linux";
      modules = [
        module
        {
          virtualisation.vfio-stealth = {
            enable = true;
            smbios.manufacturer = "Example Inc.";
            smbios.product = "Example Board";
          }
          // settings;
          fileSystems."/" = {
            device = "/dev/disk/by-label/nixos";
            fsType = "ext4";
          };
          boot.loader.grub.enable = false;
          system.stateVersion = lib.trivial.release;
        }
        host
      ];
    }).config;

  evaluate = evaluateWith { virtualisation.libvirtd.enable = true; };

  failing =
    settings: map (a: a.message) (lib.filter (a: !a.assertion) (evaluate settings).assertions);

  refuses =
    name: settings: fragment:
    let
      messages = failing settings;
    in
    lib.assertMsg (lib.any (lib.hasInfix fragment) messages) "module-assertions: ${name} was not refused with a message containing '${fragment}'; failing assertions: ${builtins.toJSON messages}";

  rejectsType =
    name: settings: attribute:
    lib.assertMsg (
      !(builtins.tryEval (builtins.deepSeq (attribute (evaluate settings)) true)).success
    ) "module-assertions: ${name} was accepted although its value is malformed";

  vm = {
    uuid = "11111111-2222-3333-4444-555555555555";
    memory = 4096;
    cores = 2;
  };

  withVm = extra: {
    cpuVendor = "amd";
    host.enable = true;
    domains.vm = vm // extra;
  };

  stealth = config: config.virtualisation.vfio-stealth;
  inVm = field: config: (stealth config).domains.vm.${field};

  passthrough = {
    cpuVendor = "amd";
    user = "alice";
    host.enable = true;
    kvmfr = {
      enable = true;
      sizeMb = 64;
    };
    evdev.keyboard = "/dev/input/by-id/usb-Example_Keyboard-event-kbd";
    pinning.isolate = true;
    domains.vm = vm // {
      pinning = {
        vcpus = [
          2
          10
          3
          11
        ];
        emulator = "0-1";
        iothread = "8";
      };
      hugepages = true;
      gpu = {
        address = "0000:01:00.0";
        audio = "0000:01:00.1";
        binding = "hook";
        resizeBar2Mb = 256;
      };
      unmount = [ "/mnt/games" ];
      lookingGlass = true;
    };
    domains.other = vm // {
      uuid = "22222222-3333-4444-5555-666666666666";
      pinning = {
        vcpus = [
          2
          10
          3
          11
        ];
        emulator = "0";
      };
      gpu = {
        address = "0000:03:00.0";
        binding = "boot";
        ids = [ "10de:2484" ];
      };
    };
  };

  pinnedVm =
    vcpus: emulator: iothread:
    withVm {
      pinning = { inherit vcpus emulator iothread; };
    };

  checks = [
    (refuses "sound without a PipeWire runtime directory" (withVm {
      sound = "micro";
    }) "play sound through PipeWire")
    (lib.assertMsg (lib.any (lib.hasInfix "needs virtualisation.libvirtd.qemu.runAsRoot = true") (
      map (a: a.message) (
        lib.filter (a: !a.assertion)
          (evaluateWith {
            virtualisation.libvirtd.enable = true;
            virtualisation.libvirtd.qemu.runAsRoot = false;
          } passthrough).assertions
      )
    )) "module-assertions: evdev without runAsRoot was not refused")
    (lib.assertMsg
      (
        let
          host = evaluate (
            passthrough
            // {
              host = passthrough.host // {
                disableAspm = true;
              };
            }
          );
        in
        lib.elem "pcie_aspm=off" host.boot.kernelParams
        && host.services.logind.settings.Login.HandleSuspendKey == "ignore"
      )
      "module-assertions: host.disableAspm did not pass pcie_aspm=off, or host.enable left the suspend key active"
    )
    (lib.assertMsg (lib.any (lib.hasInfix "set virtualisation.libvirtd.enable = true") (
      map (a: a.message) (
        lib.filter (a: !a.assertion)
          (evaluateWith { } {
            cpuVendor = "amd";
            host.enable = true;
          }).assertions
      )
    )) "module-assertions: host.enable without libvirtd was not refused")
    (lib.assertMsg (failing passthrough == [ ])
      "module-assertions: a valid passthrough configuration fails: ${builtins.toJSON (failing passthrough)}"
    )
    (refuses "kvmfr without host.enable" {
      cpuVendor = "amd";
      user = "alice";
      kvmfr = {
        enable = true;
        sizeMb = 32;
      };
    } "act on the host through it: kvmfr.enable")
    (refuses "a hook-bound GPU without host.enable" {
      cpuVendor = "amd";
      domains.vm = vm // {
        gpu = {
          address = "0000:01:00.0";
          binding = "hook";
        };
      };
    } "act on the host through it: domains.vm.gpu.binding = \"hook\"")
    (refuses "kvmfr without its size" {
      cpuVendor = "amd";
      host.enable = true;
      user = "alice";
      kvmfr.enable = true;
    } "kvmfr: the device needs sizeMb")
    (refuses "kvmfr without its user" {
      cpuVendor = "amd";
      host.enable = true;
      kvmfr = {
        enable = true;
        sizeMb = 32;
      };
    } "kvmfr: the device needs sizeMb for its size and user")
    (refuses "a hugepage count without atBoot" {
      cpuVendor = "amd";
      host.enable = true;
      hugepages.count = 8;
    } "only atBoot reserves a pool")
    (refuses "two domains pinned to one CPU" {
      cpuVendor = "amd";
      domains = {
        vm = vm // {
          pinning = {
            vcpus = [
              2
              3
              4
              5
            ];
            emulator = "0";
          };
        };
        other = vm // {
          uuid = "22222222-3333-4444-5555-666666666666";
          pinning = {
            vcpus = [
              5
              6
              7
              8
            ];
            emulator = "0";
          };
        };
      };
    } "two domains pin vCPUs to the same host CPU")
    (refuses "a PCI address listed twice" (withVm {
      gpu.address = "0000:01:00.0";
      hostDevices = [ "0000:01:00.0" ];
    }) "a PCI address appears twice")
    (refuses "GPU functions from another slot" (withVm {
      gpu = {
        address = "0000:01:00.0";
        audio = "0000:02:00.1";
      };
    }) "one card in one slot")
    (refuses "a GPU that is not function 0" (withVm {
      gpu.address = "0000:01:00.1";
    }) "one card in one slot")
    (refuses "stopServices without host.enable" {
      cpuVendor = "amd";
      domains.vm = vm // {
        stopServices = [ "coolercontrold.service" ];
      };
    } "domains.vm.stopServices")
    (refuses "-cpu in extraQemuArgs" (withVm {
      extraQemuArgs = [
        "-cpu"
        "host"
      ];
    }) "extraQemuArgs: -cpu replaces")
    (refuses "memory that is no whole number of huge pages" (
      withVm {
        memory = 3000;
        hugepages = true;
      }
      // {
        hugepages.size = "1G";
      }
    ) "is not a whole number of 1G huge pages")
    (refuses "lookingGlass with no shared memory size" (withVm {
      lookingGlass = true;
    }) "lookingGlass: the shared memory has no size")
    (refuses "pinning with fewer CPUs than vCPUs" (pinnedVm [
      2
      3
      4
    ] "0" null) "names 3 host CPUs for 4 vCPUs")
    (refuses "two vCPUs on one host CPU" (pinnedVm [
      2
      3
      3
      4
    ] "0" null) "pins two vCPUs to one host CPU")
    (refuses "emulator threads on vCPU CPUs" (pinnedVm [
      2
      3
      4
      5
    ] "0-2" null) "pinning.emulator: 0-2 shares host CPUs")
    (refuses "an I/O thread on a vCPU CPU" (pinnedVm [
      2
      3
      4
      5
    ] "0" "5") "pinning.iothread: 5 shares host CPUs")
    (refuses "binding boot without ids" (withVm {
      gpu = {
        address = "0000:01:00.0";
        binding = "boot";
      };
    }) "binding \"boot\" captures the GPU at boot")
    (refuses "ids with binding libvirt" (withVm {
      gpu = {
        address = "0000:01:00.0";
        ids = [ "10de:2484" ];
      };
    }) "only binding \"boot\" reads ids")
    (refuses "a BAR resize without binding hook" (withVm {
      gpu = {
        address = "0000:01:00.0";
        resizeBar2Mb = 256;
      };
    }) "resizeBar2Mb and rebindOnStop act")
    (refuses "rebindOnStop without binding hook" (withVm {
      gpu = {
        address = "0000:01:00.0";
        binding = "boot";
        ids = [ "10de:2484" ];
        rebindOnStop = true;
      };
    }) "resizeBar2Mb and rebindOnStop act")
    (rejectsType "a malformed GPU address" (withVm { gpu.address = "01:00.0"; }) (
      config: (inVm "gpu" config).address
    ))
    (rejectsType "a malformed GPU audio address" (withVm {
      gpu = {
        address = "0000:01:00.0";
        audio = "0000:01:00.8";
      };
    }) (config: (inVm "gpu" config).audio))
    (rejectsType "a malformed extra GPU function" (withVm {
      gpu = {
        address = "0000:01:00.0";
        extraFunctions = [ "0000:01:00" ];
      };
    }) (config: (inVm "gpu" config).extraFunctions))
    (rejectsType "a malformed vfio-pci id" (withVm {
      gpu = {
        address = "0000:01:00.0";
        binding = "boot";
        ids = [ "10de-2484" ];
      };
    }) (config: (inVm "gpu" config).ids))
    (rejectsType "an unknown GPU binding" (withVm {
      gpu = {
        address = "0000:01:00.0";
        binding = "udev";
      };
    }) (config: (inVm "gpu" config).binding))
    (rejectsType "a BAR size that is no power of two" (withVm {
      gpu = {
        address = "0000:01:00.0";
        binding = "hook";
        resizeBar2Mb = 300;
      };
    }) (config: (inVm "gpu" config).resizeBar2Mb))
    (rejectsType "a USB vendor id above 0xffff" (withVm {
      usb = [
        {
          vendor = 65536;
          product = 1;
        }
      ];
    }) (inVm "usb"))
    (rejectsType "a relative unmount path" (withVm { unmount = [ "mnt/games" ]; }) (inVm "unmount"))
    (rejectsType "a malformed MAC address" (withVm { network.mac = "D8:BB:C1:12:34"; }) (
      config: (inVm "network" config).mac
    ))
    (rejectsType "a machine type other than q35" (withVm { machine = "pc-i440fx-10.0"; }) (
      inVm "machine"
    ))
    (rejectsType "a malformed emulator cpuset" (pinnedVm [ 2 3 4 5 ] "0-" null) (
      config: (inVm "pinning" config).emulator
    ))
    (rejectsType "a malformed I/O thread cpuset" (pinnedVm [ 2 3 4 5 ] "0" "01") (
      config: (inVm "pinning" config).iothread
    ))
    (rejectsType "a negative vCPU pin" (pinnedVm [
      (-1)
      3
      4
      5
    ] "0" null) (config: (inVm "pinning" config).vcpus))
    (rejectsType "a domain cache associativity above 14" (withVm { cache.assocL1 = 15; }) (
      config: (inVm "cache" config).assocL1
    ))
    (rejectsType "an unknown domain hypervMode" (withVm { hypervMode = "visible"; }) (
      inVm "hypervMode"
    ))
    (rejectsType "a relative evdev keyboard" {
      cpuVendor = "amd";
      evdev.keyboard = "input/by-id/usb-Example_Keyboard-event-kbd";
    } (config: (stealth config).evdev.keyboard))
    (rejectsType "a relative extra evdev keyboard" {
      cpuVendor = "amd";
      evdev.extraKeyboards = [ "input/event3" ];
    } (config: (stealth config).evdev.extraKeyboards))
    (rejectsType "a relative evdev mouse" {
      cpuVendor = "amd";
      evdev.mouse = "input/by-id/usb-Example_Mouse-event-mouse";
    } (config: (stealth config).evdev.mouse))
    (rejectsType "a kvmfr size that is no power of two" {
      cpuVendor = "amd";
      kvmfr.sizeMb = 48;
    } (config: (stealth config).kvmfr.sizeMb))
    (rejectsType "a shared memory size that is no power of two" {
      cpuVendor = "amd";
      lookingGlass.shmemSizeMb = 48;
    } (config: (stealth config).lookingGlass.shmemSizeMb))
    (rejectsType "an unknown huge page size" {
      cpuVendor = "amd";
      hugepages.size = "4M";
    } (config: (stealth config).hugepages.size))
    (rejectsType "a huge page count of zero" {
      cpuVendor = "amd";
      hugepages.count = 0;
    } (config: (stealth config).hugepages.count))
    (rejectsType "a relative protected disk path" {
      cpuVendor = "amd";
      host.protectedDisks = [ "home" ];
    } (config: (stealth config).host.protectedDisks))
    (rejectsType "a user name with a colon" {
      cpuVendor = "amd";
      user = "alice:x";
    } (config: (stealth config).user))
    (lib.assertMsg (failing { cpuVendor = "amd"; } == [ ])
      "module-assertions: a valid amd configuration fails: ${
        builtins.toJSON (failing {
          cpuVendor = "amd";
        })
      }"
    )
    (lib.assertMsg (
      failing {
        cpuVendor = "intel";
        instructionFixes.enable = true;
      } == [ ]
    ) "module-assertions: intel refuses instructionFixes, whose vendor-neutral half it takes")
    (refuses "intel with the timing patch" {
      cpuVendor = "intel";
      timing.enable = true;
    } "require cpuVendor \"amd\"")
    (refuses "cpuidPassthrough with enlightened Hyper-V" {
      cpuVendor = "amd";
      cpuidPassthrough.enable = true;
    } "cpuidPassthrough.enable hides Hyper-V")
    (refuses "no cpuVendor" { } "must be \"amd\" or \"intel\"")
    (lib.assertMsg
      (lib.any (lib.hasInfix "hypervFeatures.synic")
        (evaluate {
          cpuVendor = "amd";
          hypervFeatures.synic = true;
          kernelCapabilities = {
            relaxed = true;
            vendor_id = true;
            synic = false;
          };
        }).warnings
      )
      "module-assertions: a Hyper-V feature dropped for the host kernel is not named in the system warnings"
    )
    (lib.assertMsg
      (lib.any (lib.hasInfix "does not carry kernelPostPatch")
        (evaluate {
          cpuVendor = "amd";
        }).warnings
      )
      "module-assertions: the AMD kernel patches on a kernel not built through kernelFor give no warning"
    )
    (lib.assertMsg
      (lib.any (lib.hasInfix "does not carry kernelPostPatch")
        (evaluate {
          cpuVendor = "intel";
        }).warnings
      )
      "module-assertions: instructionFixes on an intel kernel not built through kernelFor gives no warning"
    )
    (refuses "host.disableAspm without host.enable" {
      cpuVendor = "amd";
      host.disableAspm = true;
    } "host.disableAspm")
    (lib.assertMsg (
      !lib.any (lib.hasInfix "does not carry kernelPostPatch")
        (evaluateWith (
          { config, pkgs, ... }:
          {
            virtualisation.libvirtd.enable = true;
            boot.kernelPackages = pkgs.linuxPackagesFor (
              config.virtualisation.vfio-stealth.packages.kernelFor pkgs.linux_latest
            );
          }
        ) { cpuVendor = "amd"; }).warnings
    ) "module-assertions: a kernel built through kernelFor is still warned about as unpatched")
    (lib.assertMsg (
      !lib.any (lib.hasInfix "does not carry kernelPostPatch")
        (evaluate {
          cpuVendor = "amd";
          timing.enable = false;
          cpuidSpoof.enable = false;
          instructionFixes.enable = false;
        }).warnings
    ) "module-assertions: a host with every AMD kernel patch off is warned about an unpatched kernel")
    (lib.assertMsg (
      let
        postPatch =
          (stealth (evaluate {
            cpuVendor = "amd";
            edid.resolution = {
              width = 2560;
              height = 1440;
            };
          })).packages.qemu.postPatch;
      in
      lib.hasInfix "info->prefx = 2560;" postPatch && lib.hasInfix "info->prefy = 1440;" postPatch
    ) "module-assertions: edid.resolution does not reach the QEMU build")
    (rejectsType "an EDID width of 0" {
      cpuVendor = "amd";
      edid.resolution.width = 0;
    } (config: (stealth config).edid.resolution.width))
    (rejectsType "an EDID height above 4095" {
      cpuVendor = "amd";
      edid.resolution.height = 4096;
    } (config: (stealth config).edid.resolution.height))
    (rejectsType "a PCI subsystem device below 0x40" {
      cpuVendor = "amd";
      pciSubsystem = "8086:0000";
    } (config: config.virtualisation.vfio-stealth.packages.qemu.drvPath))
    (rejectsType "a TPM manufacturer without the id: form" {
      cpuVendor = "amd";
      tpm.manufacturer = "IFX";
    } (config: config.virtualisation.vfio-stealth.tpm.manufacturer))
    (rejectsType "a five-character ACPI OEM id" {
      cpuVendor = "amd";
      acpiOem.id = "SHORT";
    } (config: config.virtualisation.vfio-stealth.acpiOem.id))
    (lib.assertMsg
      (builtins.tryEval (
        builtins.deepSeq
          (stealth (evaluate {
            cpuVendor = "amd";
            smbios.chassisType = 7;
            smbios.memory.errorCorrection = 6;
            acpi = {
              waet = false;
              c2Latency = 101;
              c3Latency = 1001;
            };
          })).packages.qemu.drvPath
          true
      )).success
      "module-assertions: a tower chassis, ECC memory, no WAET table and other FADT latencies do not build a QEMU"
    )
    (rejectsType "an SMBIOS chassis type above 36" {
      cpuVendor = "amd";
      smbios.chassisType = 37;
    } (config: (stealth config).smbios.chassisType))
    (rejectsType "an SMBIOS chassis type of 0" {
      cpuVendor = "amd";
      smbios.chassisType = 0;
    } (config: (stealth config).smbios.chassisType))
    (rejectsType "an SMBIOS memory error correction above 7" {
      cpuVendor = "amd";
      smbios.memory.errorCorrection = 8;
    } (config: (stealth config).smbios.memory.errorCorrection))
    (rejectsType "an SMBIOS memory error correction of 0" {
      cpuVendor = "amd";
      smbios.memory.errorCorrection = 0;
    } (config: (stealth config).smbios.memory.errorCorrection))
    (refuses "memory that does not split over the populated slots" (withVm {
      memory = 4097;
    }) "does not split evenly over the 2 populated slots")
    (refuses "memory beyond what the populated slots hold" (withVm {
      memory = 131072;
    }) "needs more than the 2 populated slots")
    (refuses "a board with no populated slot" {
      cpuVendor = "amd";
      smbios.memory.slots = [
        {
          locator = "DIMM 0";
          bank = "P0 CHANNEL A";
          populated = false;
        }
      ];
    } "no slot is populated")
    (refuses "two slots with one locator and bank" {
      cpuVendor = "amd";
      smbios.memory.slots = [
        {
          locator = "DIMM 0";
          bank = "P0 CHANNEL A";
          populated = true;
        }
        {
          locator = "DIMM 0";
          bank = "P0 CHANNEL A";
          populated = false;
        }
      ];
    } "two slots share a locator and bank")
    (rejectsType "a board with no memory slots" {
      cpuVendor = "amd";
      smbios.memory.slots = [ ];
    } (config: (stealth config).smbios.memory.slots))
    (rejectsType "a slot locator with a quote" {
      cpuVendor = "amd";
      smbios.memory.slots = [
        {
          locator = ''DIMM "0"'';
          bank = "P0 CHANNEL A";
          populated = true;
        }
      ];
    } (config: (stealth config).smbios.memory.slots))
    (rejectsType "a memory maximum of 0 GB" {
      cpuVendor = "amd";
      smbios.memory.maxCapacityGb = 0;
    } (config: (stealth config).smbios.memory.maxCapacityGb))
    (lib.assertMsg
      (builtins.tryEval (
        builtins.deepSeq
          (stealth (evaluate {
            cpuVendor = "amd";
            smbios.memory = {
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
          })).packages.qemu.drvPath
          true
      )).success
      "module-assertions: a two-slot board with one module does not build a QEMU"
    )
    (rejectsType "a FADT C2 latency wider than 16 bits" {
      cpuVendor = "amd";
      acpi.c2Latency = 65536;
    } (config: (stealth config).acpi.c2Latency))
    (rejectsType "a FADT C3 latency wider than 16 bits" {
      cpuVendor = "amd";
      acpi.c3Latency = 65536;
    } (config: (stealth config).acpi.c3Latency))
    (rejectsType "a memory type DSP0134 does not name" {
      cpuVendor = "amd";
      smbios.memory.type = "DDR6";
    } (config: (stealth config).smbios.memory.type))
    (rejectsType "a memory rank of 0" {
      cpuVendor = "amd";
      smbios.memory.rank = 0;
    } (config: (stealth config).smbios.memory.rank))
    (rejectsType "a memory rank above 15" {
      cpuVendor = "amd";
      smbios.memory.rank = 16;
    } (config: (stealth config).smbios.memory.rank))
    (rejectsType "a memory type detail wider than 16 bits" {
      cpuVendor = "amd";
      smbios.memory.typeDetail = 65536;
    } (config: (stealth config).smbios.memory.typeDetail))
    (rejectsType "a memory voltage of 0 mV" {
      cpuVendor = "amd";
      smbios.memory.voltageMillivolts = 0;
    } (config: (stealth config).smbios.memory.voltageMillivolts))
    (lib.assertMsg (
      (stealth (evaluate {
        cpuVendor = "amd";
        smbios.memory.type = "DDR4";
      })).smbios.memory.voltageMillivolts == 1200
    ) "module-assertions: DDR4 memory does not default to its JEDEC 1.2 V")
    (lib.assertMsg (
      (stealth (evaluate {
        cpuVendor = "amd";
        smbios.memory.type = "LPDDR5";
      })).smbios.memory.voltageMillivolts == null
    ) "module-assertions: a memory type without a known nominal voltage does not default to Unknown")
    (lib.assertMsg
      (
        let
          postPatch =
            (stealth (evaluate {
              cpuVendor = "amd";
              smbios.memory = {
                type = "DDR4";
                typeDetail = 8320;
                rank = 2;
              };
            })).packages.qemu.postPatch;
        in
        lib.all (fragment: lib.hasInfix fragment postPatch) [
          "#define SMBIOS_MEMORY_TYPE 0x1a"
          "#define SMBIOS_MEMORY_TYPE_DETAIL 0x2080"
          "#define SMBIOS_MEMORY_RANK 2"
          "#define SMBIOS_MEMORY_VOLTAGE_MV 1200"
        ]
      )
      "module-assertions: smbios.memory.type, typeDetail, rank or voltageMillivolts does not reach the QEMU build"
    )
    (rejectsType "a processor family above 65533" {
      cpuVendor = "amd";
      cpuIdentity.family = 65534;
    } (config: (stealth config).cpuIdentity.family))
    (rejectsType "a processor voltage above 12.7 V" {
      cpuVendor = "amd";
      cpuIdentity.voltageDecivolts = 128;
    } (config: (stealth config).cpuIdentity.voltageDecivolts))
    (rejectsType "a processor upgrade of 0" {
      cpuVendor = "amd";
      cpuIdentity.upgrade = 0;
    } (config: (stealth config).cpuIdentity.upgrade))
    (rejectsType "a processor external clock of 0" {
      cpuVendor = "amd";
      cpuIdentity.externalClock = 0;
    } (config: (stealth config).cpuIdentity.externalClock))
    (rejectsType "processor characteristics wider than 16 bits" {
      cpuVendor = "amd";
      cpuIdentity.characteristics = 65536;
    } (config: (stealth config).cpuIdentity.characteristics))
    (rejectsType "a processor max speed above 65535 MHz" {
      cpuVendor = "amd";
      cpuIdentity.maxSpeed = 65536;
    } (config: (stealth config).cpuIdentity.maxSpeed))
    (rejectsType "an empty socket designation" {
      cpuVendor = "amd";
      cpuIdentity.socket = "";
    } (config: (stealth config).cpuIdentity.socket))
    (rejectsType "a domain processor family above 65533" (withVm { cpuIdentity.family = 65534; }) (
      config: (inVm "cpuIdentity" config).family
    ))
    (lib.assertMsg (
      (stealth (evaluate {
        cpuVendor = "amd";
        smbios.socketPrefix = "Example Socket";
      })).cpuIdentity.socket == "Example Socket"
    ) "module-assertions: the renamed smbios.socketPrefix does not set cpuIdentity.socket")
    (lib.assertMsg (
      let
        processor =
          (stealth (evaluate {
            cpuVendor = "intel";
          })).domain.processor;
      in
      processor.socket == "LGA1700" && processor.upgrade == 64 && processor.family == 198
    ) "module-assertions: an intel host does not take the LGA1700 processor defaults")
    (rejectsType "an empty system version" {
      cpuVendor = "amd";
      smbios.systemVersion = "";
    } (config: (stealth config).smbios.systemVersion))
    (rejectsType "a chassis SKU with a newline" {
      cpuVendor = "amd";
      smbios.chassisSku = "Default\nstring";
    } (config: (stealth config).smbios.chassisSku))
    (rejectsType "a port type wider than a byte" {
      cpuVendor = "amd";
      smbios.ports = [
        {
          internalReference = "J1";
          internalConnectorType = 0;
          externalReference = null;
          externalConnectorType = 0;
          portType = 256;
        }
      ];
    } (config: (stealth config).smbios.ports))
    (rejectsType "a port without its connector types" {
      cpuVendor = "amd";
      smbios.ports = [ { internalReference = "J1"; } ];
    } (config: (stealth config).smbios.ports))
    (rejectsType "a slot data bus width DSP0134 does not name" {
      cpuVendor = "amd";
      smbios.systemSlots = [
        {
          designation = "PCIEX16_1";
          type = 195;
          dataBusWidth = 15;
          currentUsage = 4;
          length = 4;
          id = 0;
          characteristics1 = 4;
          characteristics2 = 1;
        }
      ];
    } (config: (stealth config).smbios.systemSlots))
    (rejectsType "a USB vendor id of five hex digits" {
      cpuVendor = "amd";
      devices.usbSerial.vendor = "0x12345";
    } (config: (stealth config).devices.usbSerial.vendor))
    (rejectsType "a USB product name with a quote" {
      cpuVendor = "amd";
      devices.usbStorageBridge.name = ''USB "Bridge"'';
    } (config: (stealth config).devices.usbStorageBridge.name))
    (rejectsType "a MegaRAID serial prefix in lower case" {
      cpuVendor = "amd";
      devices.megasas.serialPrefix = "sv";
    } (config: (stealth config).devices.megasas.serialPrefix))
    (rejectsType "a MegaRAID serial of 17 digits" {
      cpuVendor = "amd";
      devices.megasas.serialDigits = 17;
    } (config: (stealth config).devices.megasas.serialDigits))
    (rejectsType "an ACPI creator id of three characters" {
      cpuVendor = "amd";
      devices.acpiCreator.id = "AMI";
    } (config: (stealth config).devices.acpiCreator.id))
    (lib.assertMsg (
      let
        postPatch =
          (stealth (evaluate {
            cpuVendor = "amd";
            devices = {
              usbStorageBridge.name = "Example Bridge";
              megasas.serialPrefix = "EX";
              acpiCreator.revision = 1;
            };
          })).packages.qemu.postPatch;
      in
      lib.all (fragment: lib.hasInfix fragment postPatch) [
        ''"Example Bridge"''
        ''#define MEGASAS_HBA_SERIAL "EX"''
        ''"AMI \001\000\000\000"''
      ]
    ) "module-assertions: devices does not reach the QEMU build")
  ];
in
assert lib.all lib.id checks;
runCommand "module-assertions" { } "touch $out"
