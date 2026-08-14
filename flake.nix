{
  description = "VM hardware emulation stack for NixOS — QEMU, OVMF, ACPI, SMBIOS, timing";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
    git-hooks = {
      url = "github:cachix/git-hooks.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    std = {
      url = "github:Daaboulex/nix-packaging-standard?ref=v2.25.0";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.git-hooks.follows = "git-hooks";
    };

    autovirt = {
      url = "github:Scrut1ny/AutoVirt";
      flake = false;
    };
    # CachyOS kernel packaging — used by the kernel-anchor-contract
    # test to verify the awk anchors in the user's actual production
    # kernel source (CachyOS's BORE/LTO/Zen4 patches + upstream Linux).
    # Tracking `master` (latest) so the contract test follows the
    # user's rolling kernel; if a CachyOS bump moves an anchor, the
    # test fails LOUDLY at `nix flake check` time, not at boot.
    nix-cachyos-kernel = {
      url = "github:xddxdd/nix-cachyos-kernel";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    inputs@{ flake-parts, self, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      systems = [ "x86_64-linux" ];

      imports = [ inputs.std.flakeModules.base ];

      flake.overlays.default = final: _prev: {
        qemu-stealth = self.packages.${final.stdenv.hostPlatform.system}.default;
        qemu-stealth-intel = self.packages.${final.stdenv.hostPlatform.system}.qemu-stealth-intel;
        ovmf-stealth-intel = self.packages.${final.stdenv.hostPlatform.system}.ovmf-stealth-intel;
        ovmf-stealth = self.packages.${final.stdenv.hostPlatform.system}.ovmf-stealth;
        acpi-ssdt-stealth = self.packages.${final.stdenv.hostPlatform.system}.acpi-ssdt-stealth;
        smbios-extract = self.packages.${final.stdenv.hostPlatform.system}.smbios-extract;
        smbios-stealth-tables = self.packages.${final.stdenv.hostPlatform.system}.smbios-stealth-tables;
      };

      flake.nixosModules.default = import ./module.nix;

      flake.lib = import ./lib.nix { inherit (inputs.nixpkgs) lib; };

      perSystem =
        { pkgs, ... }:
        {
          pre-commit.settings.hooks.shfmt.excludes = [ "^guest/" ];

          packages.default = pkgs.callPackage ./qemu/package.nix {
            inherit (inputs) autovirt;
            cpuVendor = "amd";
          };
          packages.qemu-stealth-intel = pkgs.callPackage ./qemu/package.nix {
            inherit (inputs) autovirt;
            cpuVendor = "intel";
          };
          packages.ovmf-stealth = pkgs.callPackage ./ovmf/package.nix {
            inherit (inputs) autovirt;
            cpuVendor = "amd";
          };
          packages.ovmf-stealth-intel = pkgs.callPackage ./ovmf/package.nix {
            inherit (inputs) autovirt;
            cpuVendor = "intel";
          };
          packages.acpi-ssdt-stealth = pkgs.callPackage ./acpi/package.nix { };
          packages.smbios-extract = pkgs.callPackage ./smbios/package.nix { };
          packages.smbios-stealth-tables = pkgs.callPackage ./smbios/tables-package.nix { };

          checks.module-eval-nixos = inputs.std.lib.nixosModuleCheck {
            inherit (inputs) nixpkgs;
            inherit (pkgs.stdenv.hostPlatform) system;
            overlays = [ self.overlays.default ];
            module = ./module.nix;
            config.myModules.vfio.stealth.enable = true;
            config.myModules.vfio.stealth.cpuVendor = "amd";
            config.myModules.vfio.stealth.smbios.manufacturer = "ASUSTeK COMPUTER INC.";
            config.myModules.vfio.stealth.smbios.product = "ROG STRIX X670E-E GAMING WIFI";
            config.myModules.vfio.stealth.smbios.baseBoardSerial = "230820681900773";
            config.myModules.vfio.stealth.disk.serial = "S6B2NS0TB12345X";
            config.myModules.vfio.stealth.hypervVendorId = "AuthenticAMD";
            config.myModules.vfio.stealth.smbios.memory.manufacturer = "G.Skill";
            config.myModules.vfio.stealth.smbios.onboardDevices = [
              {
                designation = "Onboard Ethernet";
                kind = "ethernet";
                instance = 1;
              }
            ];
          };

          checks.sed-contract-qemu = pkgs.callPackage ./tests/sed-contract-qemu.nix {
            inherit inputs;
            cpuVendor = "amd";
            qemu-stealth = self.packages.${pkgs.stdenv.hostPlatform.system}.default;
          };

          checks.sed-contract-qemu-intel = pkgs.callPackage ./tests/sed-contract-qemu.nix {
            inherit inputs;
            cpuVendor = "intel";
            qemu-stealth = self.packages.${pkgs.stdenv.hostPlatform.system}.qemu-stealth-intel;
          };

          checks.sed-contract-edk2 = pkgs.callPackage ./tests/sed-contract-edk2.nix {
            inherit inputs;
            cpuVendor = "amd";
          };

          checks.sed-contract-edk2-intel = pkgs.callPackage ./tests/sed-contract-edk2.nix {
            inherit inputs;
            cpuVendor = "intel";
          };

          checks.autovirt-patch-contract = pkgs.callPackage ./tests/autovirt-patch-contract.nix { };

          checks.options-documented = pkgs.callPackage ./tests/options-documented.nix { };

          checks.kernel-anchor-contract = pkgs.callPackage ./tests/kernel-anchor-contract.nix {
            cachyosLtoLatest =
              inputs.nix-cachyos-kernel.legacyPackages.x86_64-linux.linuxPackages-cachyos-latest-lto;
          };

          checks.lib-output-contract = pkgs.callPackage ./tests/lib-output-contract.nix {
            inherit (self.packages.${pkgs.stdenv.hostPlatform.system})
              acpi-ssdt-stealth
              smbios-stealth-tables
              ;
          };

          checks.boot-smoke = pkgs.testers.runNixOSTest {
            name = "qemu-stealth-boot-smoke";
            globalTimeout = 600;
            nodes.machine =
              { lib, ... }:
              {
                virtualisation.qemu.package = lib.mkForce self.packages.${pkgs.stdenv.hostPlatform.system}.default;
                # UEFI boot on Q35: the MCH revert (c730b41) fixed the
                # OVMF PlatformPei ASSERT that originally forced SeaBIOS.
                # Q35 is explicit because the test framework defaults to
                # i440fx, which would skip the AutoVirt Q35 code paths.
                virtualisation.useEFIBoot = true;
                virtualisation.efi.OVMF =
                  lib.mkForce
                    (self.packages.${pkgs.stdenv.hostPlatform.system}.ovmf-stealth.override {
                      secureBoot = false;
                    }).fd;
                virtualisation.qemu.options = [
                  "-machine"
                  "q35"
                ];
              };
            testScript = ''
              machine.wait_for_unit("multi-user.target", timeout=300)
            '';
          };

          checks.ovmf-sb-vars-exists =
            let
              ovmf-sb = self.packages.${pkgs.stdenv.hostPlatform.system}.ovmf-stealth;
            in
            pkgs.runCommand "ovmf-sb-vars-exists" { } ''
              varsMs="${ovmf-sb.fd}/FV/OVMF_VARS.ms.fd"
              if [ ! -f "$varsMs" ]; then
                echo "FAIL: OVMF_VARS.ms.fd absent — Secure Boot key enrollment did not complete"
                echo "expected: $varsMs"
                ls -la "${ovmf-sb.fd}/FV/" 2>/dev/null || echo "(FV dir missing)"
                exit 1
              fi
              size=$(stat --format=%s "$varsMs")
              echo "ovmf-sb-vars-exists: OVMF_VARS.ms.fd present ($size bytes)"
              touch $out
            '';
        };
    };
}
