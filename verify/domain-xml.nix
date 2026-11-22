{
  lib,
  pkgs,
  writeText,
  cfg,
  nixvirt,
}:

let
  base = {
    uuid = "11111111-2222-3333-4444-555555555555";
    memory = 1024;
    cores = 1;
    threads = 1;
    disks = [ ];
    cdroms = [ ];
    network = null;
    hostDevices = [ ];
    tpm = false;
    secureBoot = false;
    display = "none";
    machine = "q35";
    pinning = null;
    cpuPm = true;
    hugepages = false;
    gpu = null;
    usb = [ ];
    lookingGlass = false;
    iommu = false;
    sound = null;
    cpuIdentity = lib.mapAttrs (_: _: null) cfg.cpuIdentity;
    cache = lib.mapAttrs (_: _: null) cfg.smbios.cache;
    hypervMode = null;
    kvmPvEnforceCpuid = null;
    extraQemuArgs = [ ];
    active = null;
    extra.devices.emulator = "${cfg.packages.libvirtQemu}/bin/qemu-system-x86_64";
  };
in
name: domain:
writeText "${name}.xml" (
  import ../render.nix {
    inherit
      lib
      pkgs
      cfg
      nixvirt
      name
      ;
    domain = lib.recursiveUpdate base (
      domain
      // {
        disks = map (
          d:
          {
            format = "raw";
            bus = "sata";
            cache = "writeback";
          }
          // d
        ) (domain.disks or [ ]);
        network = if domain ? network then { mac = null; } // domain.network else null;
      }
    );
  }
)
