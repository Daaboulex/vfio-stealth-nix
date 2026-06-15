{
  lib,
  runCommand,
  python3,
  cacheL1 ? 512,
  cacheL2 ? 8192,
  cacheL3 ? 32768,
  cacheAssocL1 ? 7, # SMBIOS Type 7 associativity byte, 7 = 8-way (Zen 4/5 L1d)
  cacheAssocL2 ? 7, # 7 = 8-way (Zen 4/5 L2)
  cacheAssocL3 ? 9, # 9 = 16-way (Zen 4/5 L3 V-Cache; 8 for non-V-Cache CCD)
  cacheEcc ? 3, # 3 = None per DSP0134 Table 39; consumer Ryzen has no cache ECC
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
      --assoc-l1 ${toString cacheAssocL1} \
      --assoc-l2 ${toString cacheAssocL2} \
      --assoc-l3 ${toString cacheAssocL3} \
      --ecc ${toString cacheEcc} \
      --output-dir $out/share/smbios

    python3 ${./generate-tables.py} --verify $out/share/smbios
  ''
