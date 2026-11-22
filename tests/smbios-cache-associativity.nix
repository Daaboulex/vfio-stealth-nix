{ runCommand, smbios-stealth-tables }:

runCommand "smbios-cache-associativity" { } ''
  for pair in l1:7 l2:7 l3:8; do
    level=''${pair%%:*}
    want=''${pair##*:}
    got=$(od -An -tu1 -j18 -N1 "${smbios-stealth-tables}/share/smbios/type7-$level.bin" | tr -d ' ')
    if [ "$got" != "$want" ]; then
      echo "SMBIOS type 7 $level associativity byte is $got, wanted $want."
      echo "DSP0134 7.8.5: 7 is 8-way, 8 is 16-way, 9 is 12-way; Zen 4 and 5 have 8-way L1 and L2 and a 16-way L3."
      exit 1
    fi
  done
  touch $out
''
