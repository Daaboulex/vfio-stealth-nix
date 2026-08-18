{
  lib,
  runCommand,
}:

runCommand "update-gap-contract" { } ''
  set -euo pipefail
  fake=$(mktemp -d)
  mkdir -p "$fake/vendor/autovirt/patches/QEMU"
  touch "$fake/vendor/autovirt/patches/QEMU/AMD-v11.0.3.patch"
  touch "$fake/vendor/autovirt/patches/QEMU/AMD-v11.1.0.patch"
  touch "$fake/vendor/autovirt/patches/QEMU/Intel-v11.0.3.patch"
  VENDOR_DIR="$fake/vendor/autovirt/patches/QEMU"
  source ${../scripts/update.sh}
  [ "$(qemu_gap_for 11.1.0)" = "" ]
  [ "$(qemu_gap_for 11.0.5)" = "" ]
  [ "$(qemu_gap_for 11.2.0)" = "11.2.0" ]
  [ "$(qemu_gap_for 12.0.0)" = "12.0.0" ]
  [ "$(amd_series_set | tr '\n' ' ')" = "11.0 11.1 " ]
  echo "update-gap-contract: all 5 cases passed"
  touch $out
''
