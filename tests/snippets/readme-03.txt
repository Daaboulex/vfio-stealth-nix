{ config, pkgs, ... }:
{
  boot.kernelPackages = pkgs.linuxPackagesFor (
    config.virtualisation.vfio-stealth.packages.kernelFor pkgs.linux_latest
  );
}
