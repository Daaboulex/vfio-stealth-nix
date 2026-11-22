{
  lib,
  pkgs,
  cfg,
  name,
  domain,
}:

let
  inherit (cfg.packages) ovmf;

  pick = override: host: if override != null then override else host;

  vcpuCount = domain.cores * domain.threads;

  serial = (import ./identity.nix { inherit lib; }).domainSerial cfg.identity.seed name;

  cache = lib.mapAttrs (field: pick domain.cache.${field}) cfg.smbios.cache;

  parts = (import ./lib.nix { inherit lib; }).mkStealthFeatures {
    smbios =
      cfg.smbios
      // lib.optionalAttrs cfg.smbios.perDomainSerials {
        serial = serial "system";
        baseBoardSerial = serial "baseboard";
      };
    inherit (cfg)
      acpiSsdt
      aperfMperf
      cet
      stripVirtio
      hypervVendorId
      pciMmio64Mb
      hypervFeatures
      kernelCapabilities
      cpuVendor
      ;
    inherit (domain) cpuPm;
    hypervMode = pick domain.hypervMode cfg.hypervMode;
    kvmPvEnforceCpuid = pick domain.kvmPvEnforceCpuid cfg.kvmPvEnforceCpuid;
    inherit (cfg.packages) acpiTables;
    smbiosTables = pkgs.callPackage ./smbios/tables-package.nix {
      cacheL1 = cache.l1;
      cacheL2 = cache.l2;
      cacheL3 = cache.l3;
      cacheAssocL1 = cache.assocL1;
      cacheAssocL2 = cache.assocL2;
      cacheAssocL3 = cache.assocL3;
      cacheEcc = cache.ecc;
    };
  };

  cpuIdentity = lib.mapAttrs (field: pick domain.cpuIdentity.${field}) cfg.cpuIdentity;

  macSuffix =
    let
      hash = builtins.hashString "sha256" "${cfg.macPrefix}:${domain.uuid}";
    in
    lib.concatMapStringsSep ":" (i: builtins.substring (i * 2) 2 hash) [
      0
      1
      2
    ];

  mac =
    if domain.network.mac != null then
      domain.network.mac
    else if cfg.spoofMac then
      "${lib.toLower cfg.macPrefix}:${macSuffix}"
    else
      null;

  sataDevice =
    index: "sd${builtins.elemAt (lib.stringToCharacters "abcdefghijklmnopqrstuvwxyz") index}";
  virtioDevice =
    index: "vd${builtins.elemAt (lib.stringToCharacters "abcdefghijklmnopqrstuvwxyz") index}";

  ioThread = domain.pinning != null && domain.pinning.iothread != null;

  disk =
    index: d:
    let
      block = lib.hasPrefix "/dev/" d.source;
    in
    {
      type = if block then "block" else "file";
      device = "disk";
      driver = {
        name = "qemu";
        type = d.format;
        inherit (d) cache;
        discard = "unmap";
      }
      // lib.optionalAttrs block { io = "native"; }
      // lib.optionalAttrs (ioThread && d.bus == "virtio") { iothread = 1; };
      source = if block then { dev = d.source; } else { file = d.source; };
      target = {
        dev = if d.bus == "virtio" then virtioDevice index else sataDevice index;
        inherit (d) bus;
      };
    };

  cdrom = index: path: {
    type = "file";
    device = "cdrom";
    driver = {
      name = "qemu";
      type = "raw";
    };
    source.file = path;
    target = {
      dev = sataDevice (lib.length domain.disks + index);
      bus = "sata";
    };
    readonly = { };
  };

  hostdev =
    managed: address:
    let
      fields = builtins.match "([0-9a-fA-F]{4}):([0-9a-fA-F]{2}):([0-9a-fA-F]{2})\\.([0-7])" address;
      hex = s: (builtins.fromTOML "v = 0x${s}").v;
    in
    {
      mode = "subsystem";
      type = "pci";
      inherit managed;
      source.address = {
        domain = hex (builtins.elemAt fields 0);
        bus = hex (builtins.elemAt fields 1);
        slot = hex (builtins.elemAt fields 2);
        function = hex (builtins.elemAt fields 3);
      };
    };

  gpuPort = 1;

  gpuHostdevs =
    let
      inherit (domain) gpu;
      managed = gpu.binding == "libvirt";
      functions = [ gpu.address ] ++ lib.optional (gpu.audio != null) gpu.audio ++ gpu.extraFunctions;
      onePort =
        address:
        let
          entry = hostdev managed address;
        in
        entry
        // {
          address = {
            type = "pci";
            domain = 0;
            bus = gpuPort;
            slot = 0;
            inherit (entry.source.address) function;
          }
          // lib.optionalAttrs (entry.source.address.function == 0 && lib.length functions > 1) {
            multifunction = true;
          };
        };
    in
    lib.optionals (gpu != null) (
      lib.imap0 (
        index: address:
        onePort address
        // lib.optionalAttrs (index == 0 && gpu.rom != null) {
          rom = {
            inherit (gpu.rom) bar;
          }
          // lib.optionalAttrs (gpu.rom.file != null) { file = "${gpu.rom.file}"; };
        }
      ) functions
    );

  usbHostdev = device: {
    mode = "subsystem";
    type = "usb";
    managed = true;
    source = {
      vendor.id = device.vendor;
      product.id = device.product;
    };
  };

  escape = lib.replaceStrings [ "," ] [ ",," ];

  evdevArgs =
    lib.optionals (cfg.evdev.keyboard != null) [
      "-object"
      "input-linux,id=kbd,evdev=${escape cfg.evdev.keyboard},grab_all=on,repeat=on"
    ]
    ++ lib.concatLists (
      lib.imap1 (i: path: [
        "-object"
        "input-linux,id=kbd${toString i},evdev=${escape path},grab_all=on"
      ]) cfg.evdev.extraKeyboards
    )
    ++ lib.optionals (cfg.evdev.mouse != null) [
      "-object"
      "input-linux,id=mouse,evdev=${escape cfg.evdev.mouse}"
    ];

  kvmfrArgs = lib.optionals (domain.lookingGlass && cfg.kvmfr.enable) [
    "-device"
    "ivshmem-plain,id=shmem0,memdev=looking-glass"
    "-object"
    "memory-backend-file,id=looking-glass,mem-path=/dev/kvmfr0,size=${toString cfg.kvmfr.sizeMb}M,share=yes"
  ];

  generated = {
    type = "kvm";
    inherit name;
    inherit (domain) uuid;
    memory = {
      count = domain.memory;
      unit = "MiB";
    };
    vcpu = {
      placement = "static";
      count = vcpuCount;
    };
    inherit (parts) sysinfo;
    os = {
      type = "hvm";
      arch = "x86_64";
      inherit (domain) machine;
      loader = {
        readonly = true;
        type = "pflash";
        secure = domain.secureBoot;
        path = "${ovmf.fd}/FV/OVMF_CODE.fd";
      };
      nvram = {
        template =
          if domain.secureBoot then "${cfg.packages.secureBootVars}" else "${ovmf.fd}/FV/OVMF_VARS.fd";
        path = "/var/lib/libvirt/qemu/nvram/${name}_VARS.fd";
      };
      smbios.mode = "sysinfo";
      boot = [
        { dev = "cdrom"; }
        { dev = "hd"; }
      ];
    };
    features =
      parts.features
      // {
        acpi = { };
        apic = { };
        smm.state = true;
      }
      // lib.optionalAttrs domain.iommu { ioapic.driver = "qemu"; };
    cpu = {
      mode = "host-passthrough";
      check = "none";
      migratable = false;
      topology = {
        sockets = 1;
        dies = 1;
        inherit (domain) cores threads;
      };
      cache.mode = "passthrough";
      feature = parts.cpuFeatures;
    };
    inherit (parts) clock;
    on_poweroff = "destroy";
    on_reboot = "restart";
    on_crash = "destroy";
    devices = {
      disk = lib.imap0 disk domain.disks ++ lib.imap0 cdrom domain.cdroms;
      interface = lib.optional (domain.network != null) (
        {
          inherit (domain.network) type;
          source.${domain.network.type} = domain.network.source;
          model.type = domain.network.model;
        }
        // lib.optionalAttrs (mac != null) { mac.address = mac; }
      );
      controller = lib.optional (domain.gpu != null) {
        type = "pci";
        index = gpuPort;
        model = "pcie-root-port";
      };
      hostdev = gpuHostdevs ++ map (hostdev true) domain.hostDevices ++ map usbHostdev domain.usb;
      shmem = lib.optional (domain.lookingGlass && !cfg.kvmfr.enable) {
        name = "looking-glass";
        model.type = "ivshmem-plain";
        size = {
          unit = "M";
          count = cfg.lookingGlass.shmemSizeMb;
        };
      };
      tpm = lib.optional domain.tpm {
        model = "tpm-crb";
        backend = {
          type = "emulator";
          version = "2.0";
        };
      };
      input = [
        {
          type = "keyboard";
          bus = "ps2";
        }
        {
          type = "mouse";
          bus = "ps2";
        }
      ];
      sound = lib.optional (domain.sound != null) {
        model = "ich9";
        codec.type = domain.sound;
        audio.id = 1;
      };
      audio = lib.optional (domain.sound != null) {
        id = 1;
        type = "pipewire";
        runtimeDir = cfg.pipewireRuntimeDir;
      };
      graphics = lib.optional (domain.display != "none") {
        type = domain.display;
        autoport = true;
      };
      video.model.type = if domain.gpu != null then "none" else "vga";
      memballoon.model = "none";
    };
    qemu-commandline.arg = map (value: { inherit value; }) (
      parts.qemuArgs cpuIdentity
      ++ [
        "-acpitable"
        "file=${cfg.acpiProcessors vcpuCount}"
      ]
      ++ evdevArgs
      ++ kvmfrArgs
      ++ domain.extraQemuArgs
    );
  }
  // lib.optionalAttrs (domain.pinning != null) {
    cputune = {
      vcpupin = lib.imap0 (vcpu: cpu: {
        inherit vcpu;
        cpuset = toString cpu;
      }) domain.pinning.vcpus;
      emulatorpin.cpuset = domain.pinning.emulator;
    }
    // lib.optionalAttrs ioThread {
      iothreadpin = [
        {
          iothread = 1;
          cpuset = domain.pinning.iothread;
        }
      ];
    };
  }
  // lib.optionalAttrs ioThread { iothreads.count = 1; }
  // lib.optionalAttrs (domain.hugepages || domain.lookingGlass) {
    memoryBacking = {
      source.type = "memfd";
      access.mode = "shared";
    }
    // lib.optionalAttrs domain.hugepages {
      hugepages.page = [
        (
          if cfg.hugepages.size == "1G" then
            {
              size = 1;
              unit = "GiB";
            }
          else
            {
              size = 2;
              unit = "MiB";
            }
        )
      ];
      nosharepages = { };
      locked = { };
    };
  };
in
lib.recursiveUpdate generated domain.extra
