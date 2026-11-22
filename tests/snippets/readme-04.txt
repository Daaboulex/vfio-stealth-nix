{
  virtualisation.vfio-stealth.domains.win11 = {
    memory = 16384;
    cores = 4;
    disks = [ { source = "/var/lib/libvirt/images/win11.qcow2"; format = "qcow2"; } ];
    cdroms = [ "/var/lib/libvirt/images/win11.iso" ];
    network = { };
  };
}
