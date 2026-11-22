{
  virtualisation.libvirtd.enable = true;
  virtualisation.vfio-stealth = {
    enable = true;
    cpuVendor = "amd";
    identity.seed = "pick a private phrase for this host";
    smbios.manufacturer = "Your board manufacturer";
    smbios.product = "Your board model";
  };
}
