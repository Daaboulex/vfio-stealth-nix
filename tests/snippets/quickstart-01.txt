{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    vfio-stealth = {
      url = "github:Daaboulex/vfio-stealth-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    { nixpkgs, vfio-stealth, ... }:
    {
      nixosConfigurations.vm-host = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          vfio-stealth.nixosModules.default
          ./hardware-configuration.nix
          ./configuration.nix
        ];
      };
    };
}
