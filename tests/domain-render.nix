{
  lib,
  runCommand,
  writeText,
  libvirt,
  python3,
  nixosSystem,
  module,
  nixvirt,
}:

let
  evaluate =
    settings:
    nixosSystem {
      system = "x86_64-linux";
      modules = [
        module
        {
          virtualisation.vfio-stealth = {
            enable = true;
            cpuVendor = "amd";
            smbios.manufacturer = "Example Inc.";
            smbios.product = "Example Board";
            smbios.serial = "EXAMPLE-SYSTEM";
            smbios.baseBoardSerial = "EXAMPLE-BOARD";
            host.enable = true;
            user = "alice";
          };
          users.users.alice = {
            isNormalUser = true;
            uid = 1000;
          };
          fileSystems."/" = {
            device = "/dev/disk/by-label/nixos";
            fsType = "ext4";
          };
          boot.loader.grub.enable = false;
          system.stateVersion = lib.trivial.release;
        }
        { virtualisation.vfio-stealth = settings; }
      ];
    };

  keyboard = "/dev/input/by-id/usb-Example_Keyboard-event-kbd";
  keyboardExtra = "/dev/input/by-id/usb-Example_Keyboard-if02-event-kbd";
  mouse = "/dev/input/by-id/usb-Example_Mouse-event-mouse";

  shared = {
    evdev = {
      inherit keyboard mouse;
      extraKeyboards = [ keyboardExtra ];
      grabToggle = "alt-alt";
    };
    lookingGlass.shmemSizeMb = 32;
    hugepages.size = "1G";
    pinning.isolate = true;
    smbios.perDomainSerials = true;
    identity.seed = "render example seed";
    domains = {
      managed = {
        uuid = "11111111-2222-3333-4444-555555555555";
        memory = 8192;
        cores = 2;
        machine = "pc-q35-10.0";
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
        disks = [
          { source = "/dev/disk/by-id/nvme-Example_SSD_1TB"; }
          {
            source = "/var/lib/libvirt/images/data.qcow2";
            format = "qcow2";
            bus = "virtio";
            cache = "writeback";
          }
        ];
        network.mac = "D8:BB:C1:12:34:56";
        gpu = {
          address = "0000:01:00.0";
          audio = "0000:01:00.1";
          extraFunctions = [ "0000:01:00.2" ];
          rom = {
            file = "/var/lib/vfio/example-vbios.rom";
            bar = false;
          };
        };
        hostDevices = [ "0000:05:00.0" ];
        usb = [
          {
            vendor = 4660;
            product = 22136;
          }
        ];
        unmount = [ "/mnt/games" ];
        lookingGlass = true;
        cpuIdentity.modelId = "Example CPU 8-Core Processor";
        cache.l3 = 98304;
        hypervMode = "hidden";
        kvmPvEnforceCpuid = true;
        extraQemuArgs = [
          "-global"
          "ICH9-LPC.noreboot=off"
        ];
      };
      hooked = {
        uuid = "22222222-3333-4444-5555-666666666666";
        memory = 4096;
        cores = 2;
        pinning = {
          vcpus = [
            4
            12
            5
            13
          ];
          emulator = "0";
        };
        gpu = {
          address = "0000:02:00.0";
          audio = "0000:02:00.1";
          binding = "hook";
          resizeBar2Mb = 256;
          rebindOnStop = true;
        };
        display = "none";
      };
      captured = {
        uuid = "33333333-4444-5555-6666-777777777777";
        memory = 4096;
        cores = 2;
        threads = 1;
        gpu = {
          address = "0000:03:00.0";
          audio = "0000:03:00.1";
          binding = "boot";
          ids = [
            "10de:2484"
            "10de:228b"
          ];
        };
        network = { };
        iommu = true;
        sound = "micro";
      };
    };
  };

  system = evaluate shared;

  kvmfrSystem = evaluate {
    kvmfr = {
      enable = true;
      sizeMb = 64;
    };
    domains.relay = {
      uuid = "44444444-5555-6666-7777-888888888888";
      memory = 4096;
      cores = 2;
      lookingGlass = true;
    };
  };

  render =
    evaluated: name:
    let
      cfg = evaluated.config.virtualisation.vfio-stealth;
    in
    writeText "${name}.xml" (
      builtins.unsafeDiscardStringContext (
        import ../render.nix {
          inherit
            lib
            cfg
            name
            nixvirt
            ;
          inherit (evaluated) pkgs;
          domain = cfg.domains.${name};
        }
      )
    );

  failed = evaluated: map (a: a.message) (lib.filter (a: !a.assertion) evaluated.config.assertions);

  inherit (system) config;
  plan = import ../host/plan.nix {
    inherit lib;
    cfg = config.virtualisation.vfio-stealth;
  };

  derivedSerial =
    name:
    lib.toUpper (
      builtins.substring 0 12 (builtins.hashString "sha256" "render example seed:${name}:system")
    );

  evdevArgs = [
    "input-linux,id=kbd,evdev=${keyboard},grab_all=on,repeat=on,grab-toggle=alt-alt"
    "input-linux,id=kbd1,evdev=${keyboardExtra},grab_all=on,grab-toggle=alt-alt"
    "input-linux,id=mouse,evdev=${mouse}"
  ];

  expected = {
    managed = {
      xml = render system "managed";
      serial = derivedSerial "managed";
      machine = "pc-q35-10.0";
      vcpupin = [
        "2"
        "10"
        "3"
        "11"
      ];
      emulatorpin = "0-1";
      iothreadpin = "8";
      diskCache = [
        "none"
        "writeback"
      ];
      pci = {
        "0000:01:00.0" = "yes";
        "0000:01:00.1" = "yes";
        "0000:01:00.2" = "yes";
        "0000:05:00.0" = "yes";
      };
      rom = {
        file = "/var/lib/vfio/example-vbios.rom";
        bar = "off";
      };
      usb = [
        [
          4660
          22136
        ]
      ];
      shmem = 32;
      hugepages = {
        size = "1";
        unit = "GiB";
      };
      memfd = true;
      video = "none";
      mac = "D8:BB:C1:12:34:56";
      args = evdevArgs ++ [
        "ICH9-LPC.noreboot=off"
        "x86_64-cpu.model-id=Example CPU 8-Core Processor"
        "x86_64-cpu.kvm-pv-enforce-cpuid=on"
        "cpu-pm=on"
        "x86_64-cpu.aperfmperf=on"
      ];
      absentArgs = [ "memory-backend-file,id=looking-glass,mem-path=/dev/kvmfr0,size=64M,share=yes" ];
      blockIo = true;
      virtioIothread = true;
      hypervisorHidden = true;
      gpuSlot = [
        "0000:01:00.0"
        "0000:01:00.1"
        "0000:01:00.2"
      ];
      iommu = null;
      sound = null;
    };
    hooked = {
      xml = render system "hooked";
      serial = derivedSerial "hooked";
      machine = "q35";
      vcpupin = [
        "4"
        "12"
        "5"
        "13"
      ];
      emulatorpin = "0";
      iothreadpin = null;
      pci = {
        "0000:02:00.0" = "no";
        "0000:02:00.1" = "no";
      };
      rom = null;
      usb = [ ];
      shmem = null;
      hugepages = null;
      memfd = false;
      video = "none";
      mac = null;
      args = evdevArgs;
      absentArgs = [ ];
      blockIo = false;
      virtioIothread = false;
      hypervisorHidden = false;
      gpuSlot = [
        "0000:02:00.0"
        "0000:02:00.1"
      ];
      iommu = null;
      sound = null;
    };
    captured = {
      xml = render system "captured";
      serial = derivedSerial "captured";
      machine = "q35";
      vcpupin = null;
      emulatorpin = null;
      iothreadpin = null;
      pci = {
        "0000:03:00.0" = "no";
        "0000:03:00.1" = "no";
      };
      rom = null;
      usb = [ ];
      shmem = null;
      hugepages = null;
      memfd = false;
      video = "none";
      mac = null;
      args = evdevArgs;
      absentArgs = [
        "cpu-pm=on"
        "x86_64-cpu.aperfmperf=on"
      ];
      blockIo = false;
      virtioIothread = false;
      hypervisorHidden = false;
      gpuSlot = [
        "0000:03:00.0"
        "0000:03:00.1"
      ];
      iommu = "amd";
      sound = "micro";
    };
    relay = {
      xml = render kvmfrSystem "relay";
      serial = "EXAMPLE-SYSTEM";
      machine = "q35";
      vcpupin = null;
      emulatorpin = null;
      iothreadpin = null;
      pci = { };
      rom = null;
      usb = [ ];
      shmem = null;
      hugepages = null;
      memfd = true;
      video = "vga";
      mac = null;
      args = [
        "ivshmem-plain,id=shmem0,memdev=looking-glass"
        "memory-backend-file,id=looking-glass,mem-path=/dev/kvmfr0,size=64M,share=yes"
      ];
      absentArgs = [ ];
      blockIo = false;
      virtioIothread = false;
      hypervisorHidden = false;
      iommu = null;
      sound = null;
    };
  };

  checks = [
    (lib.assertMsg (
      failed system == [ ]
    ) "domain-render: the example host fails its assertions: ${builtins.toJSON (failed system)}")
    (lib.assertMsg (
      failed kvmfrSystem == [ ]
    ) "domain-render: the kvmfr host fails its assertions: ${builtins.toJSON (failed kvmfrSystem)}")
    (lib.assertMsg
      (
        lib.all (driver: lib.hasInfix "softdep ${driver} pre: vfio-pci\n" config.boot.extraModprobeConfig) [
          "nouveau"
          "nvidia"
        ]
        && !lib.hasInfix "softdep amdgpu" config.boot.extraModprobeConfig
      )
      "domain-render: binding \"boot\" of an NVIDIA card did not make exactly its drivers wait for vfio-pci: ${config.boot.extraModprobeConfig}"
    )
    (lib.assertMsg (lib.elem "vfio-pci.ids=10de:2484,10de:228b" config.boot.kernelParams) "domain-render: binding \"boot\" did not put the GPU's ids in vfio-pci.ids: ${builtins.toJSON config.boot.kernelParams}")
    (lib.assertMsg (lib.elem "vfio_pci" config.boot.initrd.kernelModules) "domain-render: binding \"boot\" did not load vfio_pci in the initrd")
    (lib.assertMsg (
      config.virtualisation.libvirtd.hooks.qemu ? vfio-stealth
    ) "domain-render: host.enable did not install the QEMU hook")
    (lib.assertMsg (lib.hasInfix ''ATTR{idVendor}=="1234", ATTR{idProduct}=="5678"'' config.services.udev.extraRules) "domain-render: no udev rule attaches the USB device 1234:5678 again")
    (lib.assertMsg (lib.all
      (path: lib.hasInfix ''"${path}"'' config.virtualisation.libvirtd.qemu.verbatimConfig)
      [
        keyboard
        keyboardExtra
        mouse
      ]
    ) "domain-render: the evdev devices are missing from cgroup_device_acl")
    (lib.assertMsg (
      plan.domains.hooked.gpu == {
        functions = [
          "0000:02:00.0"
          "0000:02:00.1"
        ];
        resizeBar2 = 8;
        rebindOnStop = true;
      }
    ) "domain-render: the hook plan for binding \"hook\" is ${builtins.toJSON plan.domains.hooked.gpu}")
    (lib.assertMsg (
      plan.domains.managed.gpu == null && plan.domains.captured.gpu == null
    ) "domain-render: the hook would bind a GPU that libvirt or the boot binding owns")
    (lib.assertMsg (
      plan.domains.managed.hugepages == 8
      && plan.domains.managed.unmount == [ "/mnt/games" ]
      &&
        plan.domains.managed.devices == [
          "0000:01:00.0"
          "0000:01:00.1"
          "0000:01:00.2"
          "0000:05:00.0"
        ]
    ) "domain-render: the hook plan for managed is ${builtins.toJSON plan.domains.managed}")
    (lib.assertMsg (lib.hasInfix "options kvmfr static_size_mb=64" kvmfrSystem.config.boot.extraModprobeConfig) "domain-render: kvmfr.sizeMb did not reach the kvmfr module")
  ];
in
assert lib.all lib.id checks;
runCommand "domain-render"
  {
    nativeBuildInputs = [
      libvirt
      python3
    ];
    expected = writeText "domain-render.json" (builtins.toJSON expected);
  }
  ''
    export HOME=$TMPDIR
    for xml in ${lib.concatMapStringsSep " " (domain: "${domain.xml}") (lib.attrValues expected)}; do
      virt-xml-validate "$xml" domain
    done
    python3 -I ${./domain-render.py} "$expected"
    touch $out
  ''
