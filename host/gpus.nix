{
  lib,
  writeShellApplication,
  pciutils,
  coreutils,
}:

writeShellApplication {
  name = "vfio-stealth-gpus";
  runtimeInputs = [
    pciutils
    coreutils
  ];
  text = builtins.readFile ./gpus.sh;
  meta = {
    description = "List each GPU with its IOMMU group, say whether it can go to a VM, and print its gpu settings for the module";
    license = lib.licenses.gpl2Only;
    platforms = lib.platforms.linux;
    mainProgram = "vfio-stealth-gpus";
  };
}
