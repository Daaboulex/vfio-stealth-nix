{
  writeShellApplication,
  writeText,
  coreutils,
  util-linux,
  jq,
  systemd,
  plan,
}:

writeShellApplication {
  name = "vfio-stealth-qemu-hook";
  runtimeInputs = [
    coreutils
    util-linux
    jq
    systemd
  ];
  runtimeEnv.VFIO_STEALTH_PLAN = "${writeText "vfio-stealth-hook-plan.json" (builtins.toJSON plan)}";
  inheritPath = false;
  text = builtins.readFile ./qemu-hook.sh;
}
