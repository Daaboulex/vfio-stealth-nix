{
  writeShellApplication,
  coreutils,
  libvirt,
}:

writeShellApplication {
  name = "vfio-stealth-usb-reattach";
  runtimeInputs = [
    coreutils
    libvirt
  ];
  inheritPath = false;
  text = ''
    domain=$1
    vendor=$2
    product=$3
    state=$(virsh -c qemu:///system domstate "$domain")
    if [ "$state" != running ]; then
      exit 0
    fi
    # why: an attach in the same instant as udev's add event can find the device not yet usable
    sleep 1
    virsh -c qemu:///system attach-device "$domain" /dev/stdin --live <<<"<hostdev mode='subsystem' type='usb'><source><vendor id='0x$vendor'/><product id='0x$product'/></source></hostdev>"
  '';
}
