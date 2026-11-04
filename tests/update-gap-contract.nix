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
  [ "$(qemu_gap_for 11.1.0 AMD)" = "" ]
  [ "$(qemu_gap_for 11.0.5 AMD)" = "" ]
  [ "$(qemu_gap_for 11.2.0 AMD)" = "11.2.0" ]
  [ "$(qemu_gap_for 12.0.0 AMD)" = "12.0.0" ]
  [ "$(qemu_gap_for 11.0.5 Intel)" = "" ]
  [ "$(qemu_gap_for 11.1.2 Intel)" = "11.1.2" ]
  [ "$(series_set AMD | tr '\n' ' ')" = "11.0 11.1 " ]
  [ "$(series_set Intel | tr '\n' ' ')" = "11.0 " ]
  tags=$(printf '%s\n' \
    'aaaa	refs/tags/v11.1.3' \
    'bbbb	refs/tags/v11.2.0-rc1' \
    'cccc	refs/tags/v11.1.10' \
    'dddd	refs/tags/v9.9.9' \
    'eeee	refs/tags/kvm-88')
  [ "$(newest_release <<<"$tags")" = "11.1.10" ]
  [ "$(newest_release <<<"")" = "" ]
  cands="$fake/cands"
  printf '%s\n' 'AMD 11.0.3 forkA' 'AMD 11.1.0 forkB' 'Intel 11.2.0 forkA' 'Intel 11.0.2 forkB' >"$cands"
  [ "$(newer_fork_patch AMD 11.1.0 "$cands")" = "" ]
  [ "$(newer_fork_patch Intel 11.1.0 "$cands")" = "11.2.0 forkA" ]
  [ "$(newer_fork_patch AMD 11.0.3 "$cands")" = "11.1.0 forkB" ]
  printf '%s\n' 'AMD 11.1.0 forkB' >"$cands"
  [ "$(newer_fork_patch Intel 11.1.0 "$cands")" = "" ]
  : >"$cands"
  [ "$(newer_fork_patch AMD 11.1.0 "$cands")" = "" ]
  echo "update-gap-contract: all 15 cases passed"
  touch $out
''
