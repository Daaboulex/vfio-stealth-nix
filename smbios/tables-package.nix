{
  lib,
  runCommand,
  python3,
  cacheL1 ? 512,
  cacheL2 ? 8192,
  cacheL3 ? 32768,
}:

runCommand "smbios-stealth-tables"
  {
    nativeBuildInputs = [ python3 ];

    meta = {
      description = "Raw SMBIOS binary tables for VM hardware emulation (cache, voltage, cooling, thermal, current)";
      license = lib.licenses.gpl2Only;
      platforms = [ "x86_64-linux" ];
    };
  }
  ''
    python3 ${./generate-tables.py} \
      --cache-l1 ${toString cacheL1} \
      --cache-l2 ${toString cacheL2} \
      --cache-l3 ${toString cacheL3} \
      --output-dir $out/share/smbios

    python3 ${./generate-tables.py} --verify $out/share/smbios
  ''
