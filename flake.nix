{
  description = "VM hardware emulation stack for NixOS: QEMU, OVMF, ACPI, SMBIOS, timing";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
    git-hooks = {
      url = "github:cachix/git-hooks.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    std = {
      url = "github:Daaboulex/nix-packaging-standard/release";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.git-hooks.follows = "git-hooks";
    };

    nixvirt = {
      url = "github:AshleyYakeley/NixVirt";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # why: tracks master so kernel-postpatch-fits-cachyos patches the rolling kernel source
    nix-cachyos-kernel = {
      url = "github:xddxdd/nix-cachyos-kernel";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    inputs@{ flake-parts, self, ... }:
    let
      stealthModule = import ./module.nix {
        inherit (inputs) nixvirt;
        inherit (inputs.std.lib) patchAssertions;
      };
    in
    flake-parts.lib.mkFlake { inherit inputs; } {
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];

      imports = [
        inputs.std.flakeModules.base
        {
          perSystem.std.option-reference = {
            "NixOS module" = stealthModule;
          };
        }
      ];

      flake.overlays.default = final: _prev: {
        qemu-stealth = final.callPackage ./qemu/package.nix {
          inherit (inputs.std.lib) patchAssertions;
          autovirt = ./vendor/autovirt;
          cpuVendor = "amd";
        };
        qemu-stealth-intel = final.callPackage ./qemu/package.nix {
          inherit (inputs.std.lib) patchAssertions;
          autovirt = ./vendor/autovirt;
          cpuVendor = "intel";
        };
        ovmf-stealth = final.callPackage ./ovmf/package.nix {
          inherit (inputs.std.lib) patchAssertions;
          autovirt = ./vendor/autovirt;
          cpuVendor = "amd";
        };
        ovmf-stealth-intel = final.callPackage ./ovmf/package.nix {
          inherit (inputs.std.lib) patchAssertions;
          autovirt = ./vendor/autovirt;
          cpuVendor = "intel";
        };
        acpi-ssdt-stealth = final.callPackage ./acpi/package.nix { };
        smbios-extract = final.callPackage ./smbios/package.nix { };
        smbios-stealth-tables = final.callPackage ./smbios/tables-package.nix { };
        stealth-detect = final.callPackage ./detect/package.nix { };
      };

      flake.nixosModules = {
        vfio-stealth = stealthModule;
        default = {
          _class = "nixos";
          imports = [
            inputs.nixvirt.nixosModules.default
            stealthModule
          ];
        };
      };

      flake.lib = import ./lib.nix { inherit (inputs.nixpkgs) lib; };

      perSystem =
        { lib, pkgs, ... }:
        let
          x86 = pkgs.stdenv.hostPlatform.system == "x86_64-linux";
          arm = pkgs.stdenv.hostPlatform.system == "aarch64-linux";
          stealth-detect = pkgs.callPackage ./detect/package.nix { };
          kernelRuntime = pkgs.callPackage ./tests/kernel-runtime.nix {
            module = self.nixosModules.default;
            variants = kernelVariants;
          };
          kernelRuntimeSets = lib.listToAttrs (
            map
              (
                set:
                let
                  test = kernelRuntime set.cpuVendor set.settings;
                in
                lib.nameValuePair test.variant test
              )
              (
                map
                  (settings: {
                    cpuVendor = "amd";
                    inherit settings;
                  })
                  [
                    { timing.enable = true; }
                    { cpuidSpoof.enable = true; }
                    { instructionFixes.enable = true; }
                    { cpuidPassthrough.enable = true; }
                    { cpuidPassthrough.pinned = true; }
                    {
                      timing.enable = true;
                      cpuidSpoof.enable = true;
                      instructionFixes.enable = true;
                      cpuidPassthrough.pinned = true;
                    }
                    {
                      timing.enable = true;
                      cpuidSpoof.enable = true;
                      instructionFixes.enable = true;
                      cpuidPassthrough.enable = true;
                    }
                  ]
                ++ [
                  {
                    cpuVendor = "intel";
                    settings.instructionFixes.enable = true;
                  }
                ]
              )
          );
          kernelVariants = import ./tests/kernel-variants.nix {
            inherit lib;
            inherit (inputs.nixpkgs.lib) nixosSystem;
            module = self.nixosModules.default;
          };
          vendorPackage =
            cpuVendor: name:
            self.packages.${pkgs.stdenv.hostPlatform.system}.${
              if cpuVendor == "amd" then name else "${name}-${cpuVendor}"
            };
          qemuProbe =
            { version, hash }:
            lib.genAttrs [ "amd" "intel" ] (
              cpuVendor:
              let
                qemu = pkgs.callPackage ./qemu/package.nix {
                  inherit (inputs.std.lib) patchAssertions;
                  autovirt = ./vendor/autovirt;
                  inherit cpuVendor;
                  probe = { inherit version hash; };
                };
              in
              {
                inherit qemu;
                sed-contract = pkgs.callPackage ./tests/sed-contract-qemu.nix {
                  inherit (inputs.std.lib) patchAssertions;
                  inherit cpuVendor;
                  qemu-stealth = qemu;
                };
                boot-smoke = bootSmoke { inherit cpuVendor qemu; };
              }
            );
          bootCheck =
            cpuVendor: settings: (exampleHost cpuVendor settings).virtualisation.vfio-stealth.bootCheck;
          exampleHost =
            cpuVendor: settings:
            (inputs.nixpkgs.lib.nixosSystem {
              system = "x86_64-linux";
              modules = [
                self.nixosModules.default
                {
                  virtualisation.vfio-stealth = lib.recursiveUpdate {
                    enable = true;
                    inherit cpuVendor;
                    identity.seed = "boot matrix example seed";
                    smbios.manufacturer = "Example Inc.";
                    smbios.product = "Example Board";
                    acpiOem.id = "TSTOEM";
                    acpiOem.tableId = "EXAMPLE1";
                  } settings;
                  fileSystems."/" = {
                    device = "/dev/disk/by-label/nixos";
                    fsType = "ext4";
                  };
                  boot.loader.grub.enable = false;
                  system.stateVersion = lib.trivial.release;
                }
              ];
            }).config;
          bootSmoke =
            { cpuVendor, qemu }:
            let
              suffix = lib.optionalString (cpuVendor != "amd") "-${cpuVendor}";
              oemId =
                let
                  id = lib.strings.trim qemu.acpiOemId;
                in
                assert lib.assertMsg (
                  id != ""
                ) "boot-smoke: the QEMU under test has a blank acpiOemId, so no guest could prove its OEM rewrite";
                id;
            in
            pkgs.testers.runNixOSTest {
              name = "qemu-stealth-boot-smoke${suffix}-${qemu.version}";
              globalTimeout = 600;
              nodes.machine =
                { lib, ... }:
                {
                  environment.systemPackages = [ stealth-detect ];
                  virtualisation.qemu.package = lib.mkForce qemu;
                  virtualisation.useEFIBoot = true;
                  virtualisation.efi.OVMF =
                    lib.mkForce
                      ((vendorPackage cpuVendor "ovmf-stealth").override {
                        secureBoot = false;
                      }).fd;
                  # why: the test driver defaults to i440fx, which skips the AutoVirt Q35 paths
                  virtualisation.qemu.options = [
                    "-machine"
                    "q35"
                    "-blockdev"
                    "driver=null-co,node-name=sata0,size=67108864"
                    "-device"
                    "ide-hd,drive=sata0,bus=ide.0"
                    "-device"
                    "ide-cd,bus=ide.1"
                  ];
                };
              testScript = ''
                import json

                machine.wait_for_unit("multi-user.target", timeout=300)

                status, out = machine.execute("stealth-detect --json")
                print(out)
                report = json.loads(out)
                verdicts = {f["vector"]: f["verdict"] for f in report["findings"]}
                evidence = {f["vector"]: f["evidence"] for f in report["findings"]}

                if verdicts["acpi-oem"] != "clean":
                    raise Exception(
                        "ACPI OEM rewrite did not reach the guest: "
                        f"{verdicts['acpi-oem']}, {evidence['acpi-oem']}"
                    )
                if ${builtins.toJSON "OEM ${oemId}/"} not in evidence["acpi-oem"]:
                    raise Exception(
                        "guest ACPI tables do not carry the configured OEM id: "
                        f"{evidence['acpi-oem']}"
                    )
                if verdicts["pci-subsystem"] != "clean":
                    raise Exception(
                        "PCI subsystem id rewrite did not reach the guest: "
                        f"{verdicts['pci-subsystem']}, {evidence['pci-subsystem']}"
                    )

                status, kernel_log = machine.execute("dmesg")
                firmware_errors = [l for l in kernel_log.splitlines() if "ACPI BIOS Error" in l or "AE_ALREADY_EXISTS" in l]
                if status != 0 or firmware_errors:
                    raise Exception(f"the guest kernel logged ACPI firmware errors, which real firmware never causes: {firmware_errors}")

                status, acpi_paths = machine.execute("cat /sys/bus/acpi/devices/*/path")
                for name in ["\\_SB_.PCI0.USB1", "\\_SB_.PCI0.USB2", "\\_SB_.PCI0.USB3", "\\_SB_.PCI0.EHC1"]:
                    if status != 0 or name not in acpi_paths.split():
                        raise Exception(f"the ICH9 USB controllers at 00:1d do not carry the real board names: {name} missing")
                for name in ["\\_SB_.PCI0.LPCB", "\\_SB_.PCI0.SAT1", "\\_SB_.PCI0.SBUS"]:
                    if name not in acpi_paths.split():
                        raise Exception(f"the ICH9 devices at 00:1f do not carry their board names: {name} missing")

                chipset = {
                    "0000:00:00.0": ("0x8086", "0x29c0", None),
                    "0000:00:1f.0": ("0x8086", "0x2918", "0x02"),
                    "0000:00:1f.2": ("0x8086", "0x2922", None),
                    "0000:00:1f.3": ("0x8086", "0x2930", "0x02"),
                }
                for address, (vendor, device, revision) in chipset.items():
                    base = f"/sys/bus/pci/devices/{address}"
                    found = (machine.succeed(f"cat {base}/vendor").strip(), machine.succeed(f"cat {base}/device").strip())
                    if found != (vendor, device):
                        raise Exception(f"{address} is {found[0]}:{found[1]}, a real ICH9 board has {vendor}:{device} there")
                    if revision is not None and machine.succeed(f"cat {base}/revision").strip() != revision:
                        raise Exception(f"{address} has revision {machine.succeed(f'cat {base}/revision').strip()}, ICH9 has {revision}")
                stray = machine.succeed("find /sys/bus/pci/devices -maxdepth 1 -name '0000:00:14.*'").strip()
                if stray:
                    raise Exception(f"devices sit in slot 0x14 with no ICH9 counterpart: {stray}")

                if machine.succeed("cat /sys/block/sda/device/vendor").strip() != "ATA":
                    raise Exception("the SATA disk on the q35 AHCI controller is not visible to the guest as /dev/sda")

                def identify(block):
                    port = machine.succeed(f"readlink -f /sys/block/{block}/device").split("/ata")[1].split("/")[0]
                    words = [int(w, 16) for w in machine.succeed(f"cat /sys/class/ata_device/dev{port}.0/id").split()]
                    text = lambda first, last: "".join(chr(w >> 8) + chr(w & 0xFF) for w in words[first:last]).strip()
                    return text(27, 47), text(23, 27)

                def inquiry(block, field):
                    return machine.succeed(f"cat /sys/block/{block}/device/{field}").strip()

                expected = {
                    "sda": (${builtins.toJSON (lib.strings.trim qemu.diskModel)}, ${builtins.toJSON qemu.diskFirmware}),
                    "sr0": (${builtins.toJSON (lib.strings.trim qemu.opticalModel)}, ${builtins.toJSON qemu.opticalFirmware}),
                }
                for block, (model, firmware) in expected.items():
                    found = identify(block)
                    if found != (model, firmware):
                        raise Exception(f"{block} answers ATA IDENTIFY with model {found[0]!r} firmware {found[1]!r}, configured {model!r} {firmware!r}")

                optical_model, optical_firmware = expected["sr0"]
                answered = " ".join([inquiry("sr0", "vendor"), inquiry("sr0", "model")])
                if " ".join(answered.split()) != " ".join(optical_model.split()):
                    raise Exception(f"the CD drive answers SCSI INQUIRY as {answered!r} but ATA IDENTIFY as {optical_model!r}, two identities no real drive has")
                if inquiry("sr0", "rev") != optical_firmware[:4]:
                    raise Exception(f"the CD drive answers SCSI INQUIRY with revision {inquiry('sr0', 'rev')!r}, its firmware is {optical_firmware!r}")
              '';
            };
        in
        {
          pre-commit.settings.hooks.shfmt.excludes = [ "^guest/" ];
          pre-commit.settings.excludes = [ "^vendor/" ];

          packages = lib.mkMerge [
            { inherit stealth-detect; }
            (lib.mkIf x86 {
              default = pkgs.callPackage ./qemu/package.nix {
                inherit (inputs.std.lib) patchAssertions;
                autovirt = ./vendor/autovirt;
                cpuVendor = "amd";
              };
              qemu-stealth-intel = pkgs.callPackage ./qemu/package.nix {
                inherit (inputs.std.lib) patchAssertions;
                autovirt = ./vendor/autovirt;
                cpuVendor = "intel";
              };
              ovmf-stealth = pkgs.callPackage ./ovmf/package.nix {
                inherit (inputs.std.lib) patchAssertions;
                autovirt = ./vendor/autovirt;
                cpuVendor = "amd";
              };
              ovmf-stealth-intel = pkgs.callPackage ./ovmf/package.nix {
                inherit (inputs.std.lib) patchAssertions;
                autovirt = ./vendor/autovirt;
                cpuVendor = "intel";
              };
              acpi-ssdt-stealth = pkgs.callPackage ./acpi/package.nix { };
              smbios-extract = pkgs.callPackage ./smbios/package.nix { };
              vfio-stealth-gpus = pkgs.callPackage ./host/gpus.nix { };
              smbios-stealth-tables = pkgs.callPackage ./smbios/tables-package.nix { };
            })
          ];

          apps = lib.optionalAttrs x86 {
            evidence = {
              type = "app";
              meta.description = "Build the boot and kernel checks and show what each guest saw, or what changed against an older revision";
              program = lib.getExe (
                pkgs.writeShellApplication {
                  name = "evidence";
                  runtimeInputs = [
                    pkgs.nix
                    pkgs.git
                    pkgs.python3
                  ];
                  text = ''
                    flake=$(git rev-parse --show-toplevel)
                    attrs=(checks.x86_64-linux.boot-matrix checks.x86_64-linux.boot-matrix-hidden checks.x86_64-linux.boot-matrix-intel checks.x86_64-linux.boot-matrix-intel-hidden checks.x86_64-linux.boot-matrix-intel-hidden-nowaet ${
                      lib.concatMapStringsSep " " (name: "legacyPackages.x86_64-linux.evidence.kernel-runtime.${name}") (
                        lib.attrNames kernelRuntimeSets
                      )
                    })
                    built=$(nix build --no-link --print-out-paths "''${attrs[@]/#/$flake#}")
                    mapfile -t current <<<"$built"
                    if [ "''${1:-}" = --against ]; then
                      rev=$(git -C "$flake" rev-parse "$2")
                      built=$(nix build --no-link --print-out-paths "''${attrs[@]/#/git+file://$flake?rev=$rev#}")
                      mapfile -t baseline <<<"$built"
                      python3 -I ${./verify/evidence.py} --current "''${current[@]}" --baseline "''${baseline[@]}"
                    else
                      python3 -I ${./verify/evidence.py} --current "''${current[@]}"
                    fi
                  '';
                }
              );
            };
          };

          legacyPackages = lib.optionalAttrs x86 {
            inherit qemuProbe;
            evidence.kernel-runtime = kernelRuntimeSets // {
              __functor = _: kernelRuntime;
            };
            evidence.windows =
              {
                cpuVendor,
                iso ? null,
                installed ? null,
                settings ? { },
                vbs ? false,
                gpu ? null,
                hostDevices ? [ ],
                memory ? 4096,
                cores ? 4,
                threads ? 1,
                pinning ? null,
              }:
              let
                host = exampleHost cpuVendor settings;
              in
              pkgs.callPackage ./verify/windows.nix {
                cfg = host.virtualisation.vfio-stealth;
                inherit (inputs) nixvirt;
                swtpm = host.virtualisation.libvirtd.qemu.swtpm.package;
                vmaware = pkgs.pkgsCross.mingw-ucrt-x86_64-llvm.callPackage ./verify/vmaware.nix { };
                inherit
                  iso
                  installed
                  vbs
                  gpu
                  hostDevices
                  memory
                  cores
                  threads
                  pinning
                  ;
              };
            evidence.libvirt-windows =
              {
                cpuVendor,
                installed,
                settings ? { },
              }:
              pkgs.callPackage ./tests/libvirt-windows.nix {
                module = self.nixosModules.default;
                harness = self.legacyPackages.x86_64-linux.evidence.windows {
                  inherit cpuVendor installed settings;
                };
                inherit cpuVendor installed settings;
              };
          };

          checks = lib.mkMerge [
            {
              detect-fixture-contract = pkgs.callPackage ./tests/detect-fixture-contract.nix {
                inherit stealth-detect;
              };
              smbios-extract = pkgs.callPackage ./tests/smbios-extract.nix {
                smbios-extract = pkgs.callPackage ./smbios/package.nix { };
              };
              qemu-hook = pkgs.callPackage ./tests/qemu-hook.nix { };
              gpus = pkgs.callPackage ./tests/gpus.nix { };
              vmaware-docs = pkgs.callPackage ./tests/vmaware-docs.nix { };
              domain-render = pkgs.callPackage ./tests/domain-render.nix {
                inherit (inputs.nixpkgs.lib) nixosSystem;
                inherit (inputs) nixvirt;
                module = self.nixosModules.default;
              };
            }
            (lib.mkIf x86 {
              module-eval-nixos = inputs.std.lib.nixosModuleCheck {
                inherit (inputs) nixpkgs;
                inherit (pkgs.stdenv.hostPlatform) system;
                module = self.nixosModules.default;
                config.virtualisation.vfio-stealth.enable = true;
                config.virtualisation.vfio-stealth.cpuVendor = "amd";
                config.virtualisation.vfio-stealth.identity.seed = "module check example seed";
                config.virtualisation.vfio-stealth.smbios.manufacturer = "Example Board Co Inc.";
                config.virtualisation.vfio-stealth.smbios.product = "EXAMPLE BOARD X000 GAMING ATX";
                config.virtualisation.vfio-stealth.smbios.baseBoardSerial = "123456789012345";
                config.virtualisation.vfio-stealth.disk.serial = "TESTSERIAL0123X";
                config.virtualisation.vfio-stealth.hypervVendorId = "AuthenticAMD";
                config.virtualisation.vfio-stealth.smbios.memory.manufacturer = "G.Skill";
                config.virtualisation.vfio-stealth.smbios.onboardDevices = [
                  {
                    designation = "Onboard Ethernet";
                    kind = "ethernet";
                    instance = 1;
                  }
                ];
                config.virtualisation.vfio-stealth.smbios.perDomainSerials = true;
                config.virtualisation.vfio-stealth.user = "alice";
                config.users.users.alice.isNormalUser = true;
                config.virtualisation.vfio-stealth.host = {
                  enable = true;
                  acsOverride = "downstream,multifunction";
                  protectedDisks = [
                    "/"
                    "/nix/store"
                  ];
                };
                config.virtualisation.vfio-stealth.hugepages = {
                  size = "1G";
                  atBoot = true;
                  count = 16;
                };
                config.virtualisation.vfio-stealth.kvmfr = {
                  enable = true;
                  sizeMb = 64;
                };
                config.virtualisation.vfio-stealth.lookingGlass = {
                  client = true;
                  shmemSizeMb = 64;
                };
                config.virtualisation.vfio-stealth.evdev = {
                  keyboard = "/dev/input/by-id/usb-Example_Keyboard-event-kbd";
                  extraKeyboards = [ "/dev/input/by-id/usb-Example_Keyboard-if02-event-kbd" ];
                  mouse = "/dev/input/by-id/usb-Example_Mouse-event-mouse";
                };
                config.virtualisation.vfio-stealth.pinning.isolate = true;
                config.virtualisation.vfio-stealth.domains.win11 = {
                  uuid = "6f1c2a3e-8d4b-4c5a-9e7f-1a2b3c4d5e6f";
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
                    iothread = "8";
                  };
                  hugepages = true;
                  network.mac = "D8:BB:C1:12:34:56";
                  gpu = {
                    address = "0000:01:00.0";
                    audio = "0000:01:00.1";
                    extraFunctions = [ "0000:01:00.2" ];
                    rom = {
                      file = "/var/lib/vfio/example-vbios.rom";
                      bar = false;
                    };
                    binding = "hook";
                    resizeBar2Mb = 256;
                    rebindOnStop = true;
                  };
                  usb = [
                    {
                      vendor = 4660;
                      product = 22136;
                    }
                  ];
                  unmount = [ "/mnt/games" ];
                  lookingGlass = true;
                  cpuIdentity = {
                    manufacturer = "Advanced Micro Devices, Inc.";
                    modelId = "Example CPU 8-Core Processor";
                    maxSpeed = 5000;
                    currentSpeed = 4200;
                  };
                  cache = {
                    l1 = 512;
                    l2 = 8192;
                    l3 = 98304;
                    assocL1 = 7;
                    assocL2 = 7;
                    assocL3 = 9;
                    ecc = 3;
                  };
                  hypervMode = "hidden";
                  kvmPvEnforceCpuid = false;
                  extraQemuArgs = [
                    "-global"
                    "ICH9-LPC.noreboot=off"
                  ];
                };
                config.virtualisation.vfio-stealth.domains.captured = {
                  uuid = "33333333-4444-5555-6666-777777777777";
                  memory = 4096;
                  cores = 2;
                  gpu = {
                    address = "0000:03:00.0";
                    binding = "boot";
                    ids = [ "10de:2484" ];
                  };
                };
              };

              vmaware-not-shipped = pkgs.callPackage ./tests/vmaware-not-shipped.nix {
                inherit (inputs.nixpkgs.lib) nixosSystem;
                module = self.nixosModules.default;
                vmaware = pkgs.callPackage ./verify/vmaware.nix { };
              };

              module-eval-own-nixvirt = inputs.std.lib.nixosModuleCheck {
                inherit (inputs) nixpkgs;
                inherit (pkgs.stdenv.hostPlatform) system;
                module = {
                  imports = [
                    inputs.nixvirt.nixosModules.default
                    self.nixosModules.vfio-stealth
                  ];
                };
                config.virtualisation.vfio-stealth.enable = true;
                config.virtualisation.vfio-stealth.cpuVendor = "amd";
                config.virtualisation.vfio-stealth.smbios.manufacturer = "Example Inc.";
                config.virtualisation.vfio-stealth.smbios.product = "Example Board";
                config.virtualisation.vfio-stealth.domains.probe = {
                  uuid = "11111111-2222-3333-4444-555555555555";
                  memory = 4096;
                  cores = 2;
                  threads = 1;
                };
              };

              sed-contract-qemu = pkgs.callPackage ./tests/sed-contract-qemu.nix {
                inherit (inputs.std.lib) patchAssertions;
                cpuVendor = "amd";
                qemu-stealth = self.packages.${pkgs.stdenv.hostPlatform.system}.default;
              };

              sed-contract-qemu-intel = pkgs.callPackage ./tests/sed-contract-qemu.nix {
                inherit (inputs.std.lib) patchAssertions;
                cpuVendor = "intel";
                qemu-stealth = self.packages.${pkgs.stdenv.hostPlatform.system}.qemu-stealth-intel;
              };

              sed-contract-edk2 = pkgs.callPackage ./tests/sed-contract-edk2.nix {
                inherit (inputs.std.lib) patchAssertions;
                autovirt = ./vendor/autovirt;
                cpuVendor = "amd";
              };

              sed-contract-edk2-intel = pkgs.callPackage ./tests/sed-contract-edk2.nix {
                inherit (inputs.std.lib) patchAssertions;
                autovirt = ./vendor/autovirt;
                cpuVendor = "intel";
              };

              sed-contract-edk2-vendor = pkgs.callPackage ./tests/sed-contract-edk2.nix {
                inherit (inputs.std.lib) patchAssertions;
                autovirt = ./vendor/autovirt;
                cpuVendor = "amd";
                firmwareVendor = "Example Firmware Inc.";
                acpiOemId = "TESTID";
                acpiOemTableId = "TESTTBL1";
              };

              acpi-oem = pkgs.callPackage ./tests/acpi-oem.nix {
                inherit (self.packages.${pkgs.stdenv.hostPlatform.system}) acpi-ssdt-stealth;
              };

              autovirt-patch-contract = pkgs.callPackage ./tests/autovirt-patch-contract.nix { };

              qemu-ceiling-contract = pkgs.callPackage ./tests/ceiling-contract.nix { };
              update-gap-contract = pkgs.callPackage ./tests/update-gap-contract.nix { };

              sed-catalog-lean =
                pkgs.runCommand "sed-catalog-lean"
                  {
                    catalog = ./docs/SED-CATALOG.md;
                    repo = self;
                  }
                  ''
                    bad=0

                    while IFS= read -r f; do
                      [ -n "$f" ] || continue
                      if [ ! -e "$repo/$f" ]; then
                        echo "::error::SED-CATALOG.md documents '$f', which does not exist. The edit moved; re-point the heading."
                        bad=1
                      elif ! grep -qE 'substituteInPlace|sed -i|awk |filterdiff' "$repo/$f"; then
                        echo "::error::SED-CATALOG.md documents '$f', but that file performs no text rewrite any more."
                        bad=1
                      fi
                    done < <(grep -oE '^## [a-zA-Z0-9_./-]+\.nix' "$catalog" | sed 's/^## //' | sort -u)

                    if grep -nE '\*\*(Anchor|Replacement|Tool|Guard):\*\*' "$catalog"; then
                      echo "::error::SED-CATALOG.md restates what post-patch.nix owns (lines above)."
                      echo "Those fields drift silently and the sed-contract checks already verify them. Delete them."
                      bad=1
                    fi

                    [ "$bad" = 0 ] || exit 1
                    echo "sed-catalog-lean: every documented file exists, and nothing the code owns is restated"
                    touch "$out"
                  '';

              kernel-postpatch-fits-cachyos = pkgs.callPackage ./tests/kernel-postpatch-fits.nix {
                sourceName = "cachyos-lto-latest";
                variants = kernelVariants;
                kernelSrc =
                  inputs.nix-cachyos-kernel.legacyPackages.x86_64-linux.linuxPackages-cachyos-latest-lto.kernel.src;
              };

              kernel-postpatch-fits-upstream = pkgs.callPackage ./tests/kernel-postpatch-fits.nix {
                sourceName = "upstream-latest";
                variants = kernelVariants;
                kernelSrc = pkgs.linux_latest.src;
              };

              kernel-kvm-compiles-cachyos = pkgs.callPackage ./tests/kernel-kvm-compiles.nix {
                sourceName = "cachyos-lto-latest";
                variants = kernelVariants;
                kernel =
                  inputs.nix-cachyos-kernel.legacyPackages.x86_64-linux.linuxPackages-cachyos-latest-lto.kernel;
              };

              kernel-kvm-compiles-upstream = pkgs.callPackage ./tests/kernel-kvm-compiles.nix {
                sourceName = "upstream-latest";
                variants = kernelVariants;
                kernel = pkgs.linux_latest;
              };

              lib-output-contract = pkgs.callPackage ./tests/lib-output-contract.nix {
                inherit (self.packages.${pkgs.stdenv.hostPlatform.system})
                  acpi-ssdt-stealth
                  smbios-stealth-tables
                  ;
              };

              module-assertions = pkgs.callPackage ./tests/module-assertions.nix {
                inherit (inputs.nixpkgs.lib) nixosSystem;
                module = self.nixosModules.default;
              };

              identity-seed = pkgs.callPackage ./tests/identity-seed.nix {
                inherit (inputs.nixpkgs.lib) nixosSystem;
                module = self.nixosModules.default;
              };

              option-combinations = pkgs.callPackage ./tests/option-combinations.nix {
                inherit (inputs.nixpkgs.lib) nixosSystem;
                module = self.nixosModules.default;
              };

              guide-snippets = pkgs.callPackage ./tests/guide-snippets.nix {
                inherit (inputs.nixpkgs.lib) nixosSystem;
                module = self.nixosModules.default;
              };

              examples = pkgs.callPackage ./tests/examples.nix {
                inherit (inputs.nixpkgs.lib) nixosSystem;
                module = self.nixosModules.default;
              };

              libvirt-firmware = pkgs.callPackage ./tests/libvirt-firmware.nix {
                module = self.nixosModules.default;
                cpuVendor = "amd";
              };

              libvirt-firmware-intel = pkgs.callPackage ./tests/libvirt-firmware.nix {
                module = self.nixosModules.default;
                cpuVendor = "intel";
              };

              boot-matrix = bootCheck "amd" { };
              boot-matrix-hidden = bootCheck "amd" { hypervMode = "hidden"; };

              boot-matrix-intel = bootCheck "intel" { };
              boot-matrix-intel-hidden = bootCheck "intel" {
                hypervMode = "hidden";
                smbios.perDomainSerials = true;
              };

              boot-matrix-intel-hidden-nowaet = bootCheck "intel" {
                hypervMode = "hidden";
                acpi.waet = false;
              };

              smbios-cache-associativity = pkgs.callPackage ./tests/smbios-cache-associativity.nix {
                inherit (self.packages.${pkgs.stdenv.hostPlatform.system}) smbios-stealth-tables;
              };

              boot-smoke = bootSmoke {
                cpuVendor = "amd";
                qemu = self.packages.${pkgs.stdenv.hostPlatform.system}.default;
              };
              boot-smoke-intel = bootSmoke {
                cpuVendor = "intel";
                qemu = vendorPackage "intel" "qemu-stealth";
              };

            })
            (lib.mkIf arm {
              detect-finds-plain-virt = pkgs.callPackage ./tests/detect-finds-plain-virt.nix {
                inherit stealth-detect;
              };
            })
          ];
        };
    };
}
