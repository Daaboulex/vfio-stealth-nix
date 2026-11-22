{
  lib,
  runCommand,
  python3,
  cacheL1 ? 512,
  cacheL2 ? 8192,
  cacheL3 ? 32768,
  cacheAssocL1 ? 7,
  cacheAssocL2 ? 7,
  cacheAssocL3 ? 8,
  cacheEcc ? 3,
}:

let
  cacheHandles = {
    l1 = 1792;
    l2 = 1793;
    l3 = 1794;
  };
in
runCommand "smbios-stealth-tables"
  {
    nativeBuildInputs = [ python3 ];

    passthru = { inherit cacheHandles; };

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
      --assoc-l1 ${toString cacheAssocL1} \
      --assoc-l2 ${toString cacheAssocL2} \
      --assoc-l3 ${toString cacheAssocL3} \
      --ecc ${toString cacheEcc} \
      --handle-l1 ${toString cacheHandles.l1} \
      --handle-l2 ${toString cacheHandles.l2} \
      --handle-l3 ${toString cacheHandles.l3} \
      --output-dir $out/share/smbios

    python3 ${./generate-tables.py} --verify $out/share/smbios
  ''
