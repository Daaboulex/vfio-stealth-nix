{
  description = "VM anti-detection stack for NixOS — QEMU, OVMF, ACPI, SMBIOS, timing";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    git-hooks = {
      url = "github:cachix/git-hooks.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    autovirt = {
      url = "github:Scrut1ny/AutoVirt";
      flake = false;
    };
    better-timing = {
      url = "github:SamuelTulach/BetterTiming";
      flake = false;
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      git-hooks,
      autovirt,
      better-timing,
    }:
    let
      supportedSystems = [ "x86_64-linux" ];
      forAllSystems =
        fn:
        nixpkgs.lib.genAttrs supportedSystems (
          system:
          fn {
            pkgs = import nixpkgs { localSystem.system = system; };
            inherit system;
          }
        );
    in
    {
      packages = forAllSystems (
        { pkgs, ... }:
        {
          default = pkgs.callPackage ./qemu/package.nix { inherit autovirt; };
          ovmf-stealth = pkgs.callPackage ./ovmf/package.nix { };
          acpi-ssdt-stealth = pkgs.callPackage ./acpi/package.nix { };
          smbios-extract = pkgs.callPackage ./smbios/package.nix { };
        }
      );

      # Consumers can customize hardware strings:
      # pkgs.qemu-stealth.override { edidManufacturer = "DEL"; diskModel = "..."; }
      overlays.default = final: prev: {
        qemu-stealth = self.packages.${final.system}.default;
        ovmf-stealth = self.packages.${final.system}.ovmf-stealth;
        acpi-ssdt-stealth = self.packages.${final.system}.acpi-ssdt-stealth;
        smbios-extract = self.packages.${final.system}.smbios-extract;
      };

      nixosModules.default = import ./module.nix {
        inherit autovirt better-timing;
        vfio-stealth = self;
      };

      lib = import ./lib.nix { inherit (nixpkgs) lib; };

      formatter = forAllSystems ({ pkgs, ... }: pkgs.nixfmt-rfc-style);

      checks = forAllSystems (
        { system, ... }:
        {
          pre-commit-check = git-hooks.lib.${system}.run {
            src = self;
            hooks.nixfmt-rfc-style.enable = true;
          };
        }
      );

      devShells = forAllSystems (
        { pkgs, system }:
        {
          default = pkgs.mkShell {
            inherit (self.checks.${system}.pre-commit-check) shellHook;
            buildInputs = self.checks.${system}.pre-commit-check.enabledPackages;
            packages = with pkgs; [ nil ];
          };
        }
      );
    };
}
