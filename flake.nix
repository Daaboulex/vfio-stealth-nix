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
      url = "github:Daaboulex/nix-packaging-standard?ref=v2.7.0";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.git-hooks.follows = "git-hooks";
    };

    autovirt = {
      url = "github:Scrut1ny/AutoVirt";
      flake = false;
    };
    better-timing = {
      url = "github:SamuelTulach/BetterTiming";
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
          packages.default = pkgs.callPackage ./qemu/package.nix { inherit (inputs) autovirt; };
          packages.ovmf-stealth = pkgs.callPackage ./ovmf/package.nix { inherit (inputs) autovirt; };
          packages.acpi-ssdt-stealth = pkgs.callPackage ./acpi/package.nix { };
          packages.smbios-extract = pkgs.callPackage ./smbios/package.nix { };
          packages.smbios-stealth-tables = pkgs.callPackage ./smbios/tables-package.nix { };

          checks.module-eval-nixos = inputs.std.lib.nixosModuleCheck {
            inherit (inputs) nixpkgs;
            inherit (pkgs.stdenv.hostPlatform) system;
            overlays = [ self.overlays.default ];
            module = ./module.nix;
            config.myModules.vfio.stealth.enable = true;
          };

          checks.sed-contract-qemu = pkgs.callPackage ./tests/sed-contract-qemu.nix {
            inherit inputs;
          };

          checks.sed-contract-edk2 = pkgs.callPackage ./tests/sed-contract-edk2.nix {
            inherit inputs;
          };

          checks.kernel-anchor-contract = pkgs.callPackage ./tests/kernel-anchor-contract.nix {
            cachyosLtoLatest =
              inputs.nix-cachyos-kernel.legacyPackages.x86_64-linux.linuxPackages-cachyos-latest-lto;
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
        };
    };
}
