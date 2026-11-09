#!/usr/bin/env bash
set -euo pipefail

# Custom update script for vfio-stealth-nix
# AutoVirt's patches are vendored in vendor/autovirt. This script watches
# upstream (Scrut1ny) and the live forks for a patch newer than
# what is vendored, and the newest QEMU for a series no vendored patch
# covers, so the canonical update workflow files an issue the day either
# appears. Adoption stays a hand decision (see docs/RELEASE-PROCEDURE.md).
# Contract: exit 0 = nothing to do, exit 2 = transient network failure, exit 1 =
# a manual port needed, upstream gone, a patch gap, a moved BetterTiming, a dead
# repo still in AUTOVIRT_REPOS, a repo in AUTOVIRT_GONE back online, or aarch64 id
# registers turning configurable upstream;
# error_type says which. Every non-zero reaches the owner as the workflow's
# single open update-failed issue, so nothing is left as a warning on a cron
# nobody reads.

output() { echo "$1=$2" >>"$OUTPUT_FILE"; }
log() { echo "==> $*" >&2; }
warn() { echo "::warning::$*" >&2; }
err() { echo "::error::$*" >&2; }

newest_series() {
  local vendor="$1"
  find "$VENDOR_DIR" -maxdepth 1 -type f -printf '%f\n' |
    sed -n "s/^${vendor}-v\([0-9][0-9.]*\)\.patch$/\1/p" |
    sort -V |
    tail -1
}

VENDORS=(AMD Intel)

series_set() {
  local vendor="$1"
  find "$VENDOR_DIR" -maxdepth 1 -type f -printf '%f\n' |
    sed -n "s/^${vendor}-v\([0-9][0-9]*\.[0-9][0-9]*\)\.[0-9][0-9.]*\.patch$/\1/p" |
    sort -u
}

qemu_gap_for() {
  local qemu_version="$1" vendor="$2" series patched
  series="${qemu_version%.*}"
  patched=$(series_set "$vendor" || true)
  if ! grep -qx "$series" <<<"$patched"; then
    printf '%s' "$qemu_version"
  fi
}

newest_release() {
  sed -n 's|^[0-9a-f]*[[:space:]]*refs/tags/v\([0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*\)$|\1|p' |
    sort -V |
    tail -1
}

newer_fork_patch() {
  local vendor="$1" ours="$2" cands="$3" best_line best_version newest
  best_line=$(awk -v v="$vendor" '$1 == v { print $2, $3 }' "$cands" | sort -V -k1,1 | tail -1)
  [ -n "$best_line" ] || return 0
  best_version=${best_line%% *}
  newest=$(printf '%s\n%s\n' "$ours" "$best_version" | sort -V | tail -1)
  if [ "$newest" = "$best_version" ] && [ "$best_version" != "$ours" ]; then
    printf '%s' "$best_line"
  fi
}

watch_verdict() {
  case "$1:$2" in
  live:200) echo live ;;
  live:404) echo dead ;;
  gone:200) echo returned ;;
  gone:404) echo still-gone ;;
  *) echo transient ;;
  esac
}

probe_stage() {
  local version="$1" hash="$2" vendor="$3" stage
  for stage in qemu sed-contract boot-smoke; do
    if ! nix build --impure --no-link -L --expr \
      "((builtins.getFlake (toString ./.)).legacyPackages.x86_64-linux.qemuProbe { version = \"${version}\"; hash = \"${hash}\"; }).${vendor}.${stage}" >&2; then
      printf '%s' "$stage"
      return 1
    fi
  done
}

[[ ${BASH_SOURCE[0]} == "$0" ]] || return 0

OUTPUT_FILE="${GITHUB_OUTPUT:-/tmp/update-outputs.env}"
: >"$OUTPUT_FILE"

output "package_name" "vfio-stealth"
output "updated" "false"

VENDOR_DIR="vendor/autovirt/patches/QEMU"

declare -A OURS=()
for vendor in "${VENDORS[@]}"; do
  OURS[$vendor]=$(newest_series "$vendor")
  if [ -z "${OURS[$vendor]}" ]; then
    err "vendor patch inventory is empty or malformed in $VENDOR_DIR: no ${vendor}-v<version>.patch"
    output "error_type" "inventory-error"
    exit 1
  fi
done

log "Vendored: AMD-v${OURS[AMD]} Intel-v${OURS[Intel]}"
output "old_version" "AMD-v${OURS[AMD]} Intel-v${OURS[Intel]}"

AUTOVIRT_REPOS=(
  "Zhaodaidai"
  "fortesoft-co"
)

AUTOVIRT_GONE=(
  "Scrut1ny"
)

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

dead=0
dead_forks=()
returned_forks=()
transient=0
: >"$TMP/cands"

for entry in "${AUTOVIRT_REPOS[@]/#/live:}" "${AUTOVIRT_GONE[@]/#/gone:}"; do
  list=${entry%%:*}
  fork=${entry#*:}
  code=$(curl -s -o "$TMP/body.json" -w '%{http_code}' \
    "https://api.github.com/repos/${fork}/AutoVirt/contents/patches/QEMU" 2>/dev/null || true)
  case "$(watch_verdict "$list" "${code:-000}")" in
  live) ;;
  returned) returned_forks+=("$fork") ;;
  dead)
    dead=$((dead + 1))
    dead_forks+=("$fork")
    continue
    ;;
  still-gone)
    log "${fork}/AutoVirt still returns 404; watching for its return"
    continue
    ;;
  transient)
    warn "${fork}/AutoVirt: fetch failed (HTTP ${code:-000}) - transient"
    transient=1
    continue
    ;;
  esac
  jq -r '.[].name' "$TMP/body.json" |
    sed -n 's/^\(AMD\|Intel\)-v\([0-9][0-9.]*\)\.patch$/\1 \2/p' |
    while read -r vendor v; do echo "$vendor $v $fork"; done >>"$TMP/cands"
done

if [ "$dead" -ge "${#AUTOVIRT_REPOS[@]}" ]; then
  err "every watched AutoVirt repo is gone (404) - update AUTOVIRT_REPOS in scripts/update.sh"
  output "error_type" "upstream-gone"
  exit 1
fi

for vendor in "${VENDORS[@]}"; do
  best_line=$(newer_fork_patch "$vendor" "${OURS[$vendor]}" "$TMP/cands")
  if [ -n "$best_line" ]; then
    best_version=${best_line%% *}
    best_fork=${best_line##* }
    warn "${best_fork}/AutoVirt ships ${vendor}-v${best_version}.patch; we vendor ${vendor}-v${OURS[$vendor]} - manual port needed"
    output "new_version" "${vendor}-v${best_version}"
    output "upstream_url" "https://github.com/${best_fork}/AutoVirt/blob/main/patches/QEMU/${vendor}-v${best_version}.patch"
    output "error_type" "manual-port-needed"
    exit 1
  fi
done

NP_QEMU=$(nix eval --raw 'github:NixOS/nixpkgs/nixos-unstable#qemu.version' 2>/dev/null) || NP_QEMU=""
UP_TAGS=$(git ls-remote --tags --refs https://gitlab.com/qemu-project/qemu.git 'v*') || UP_TAGS=""
UP_QEMU=$(newest_release <<<"$UP_TAGS")
if [ -z "$NP_QEMU" ] || [ "$NP_QEMU" = "null" ] || [ -z "$UP_QEMU" ]; then
  warn "could not read the newest QEMU of nixpkgs-unstable (${NP_QEMU:-unread}) and upstream (${UP_QEMU:-unread}) - transient"
  transient=1
else
  target=$(printf '%s\n%s\n' "$NP_QEMU" "$UP_QEMU" | sort -V | tail -1)
  gaps=()
  for vendor in "${VENDORS[@]}"; do
    [ -z "$(qemu_gap_for "$target" "$vendor")" ] || gaps+=("$vendor")
  done
  if [ "${#gaps[@]}" -gt 0 ]; then
    if ! prefetch=$(nix store prefetch-file --json "https://download.qemu.org/qemu-${target}.tar.xz"); then
      warn "could not fetch the QEMU ${target} tarball to probe it - transient"
      transient=1
    else
      hash=$(jq -r '.hash' <<<"$prefetch")
      ready=()
      broken=()
      for vendor in "${gaps[@]}"; do
        patch="${vendor}-v${OURS[$vendor]}.patch"
        if stage=$(probe_stage "$target" "$hash" "${vendor,,}"); then
          ready+=("$vendor")
          log "probe: ${patch} applies to QEMU ${target}, its sed contract passes and the boot-smoke guest boots"
        else
          broken+=("${vendor} (${patch} fails at ${stage})")
        fi
      done
      output "new_version" "$target"
      output "upstream_url" "https://download.qemu.org/qemu-${target}.tar.xz"
      if [ "${#broken[@]}" -eq 0 ]; then
        err "QEMU ${target} (nixpkgs-unstable ${NP_QEMU}, upstream ${UP_QEMU}) has no vendored patch for ${gaps[*]}, and the newest vendored patch applies, passes its sed contract and boots the boot-smoke guest on it: vendor it as <vendor>-v${target}.patch and add the ${target} tarball hash (${hash}) to raise the ceiling"
        output "error_type" "qemu-series-ready"
      else
        err "QEMU ${target} (nixpkgs-unstable ${NP_QEMU}, upstream ${UP_QEMU}) has no vendored patch for ${gaps[*]}; probed with the newest vendored patch, ready: ${ready[*]:-none}; needs a hand port: ${broken[*]}"
        output "error_type" "patch-gap"
      fi
      exit 1
    fi
  fi
fi

CURRENT_BT=$(jq -r '.betterTiming.rev' version.json)
LATEST_BT=$(curl -sfL 'https://api.github.com/repos/SamuelTulach/BetterTiming/commits/master' 2>/dev/null | jq -r '.sha') || LATEST_BT=""

QEMU_KVM_URL='https://raw.githubusercontent.com/qemu/qemu/master/target/arm/kvm.c'
kvm_code=$(curl -s -o "$TMP/kvm.c" -w '%{http_code}' "$QEMU_KVM_URL" 2>/dev/null || true)
case "$kvm_code" in
200) ;;
404)
  err "${QEMU_KVM_URL} is gone (404): QEMU moved its ARM KVM backend, so point the aarch64 id-register watch at its new file"
  output "error_type" "arm-watch-source-moved"
  exit 1
  ;;
*)
  warn "could not fetch ${QEMU_KVM_URL} (HTTP ${kvm_code:-000}) - transient"
  transient=1
  ;;
esac
# A transient fetch means the run could not see every AutoVirt repo, so nothing below
# may be reported as settled: retry rather than name a stale list we did not
# finish reading.
if [ "$transient" -ne 0 ]; then
  warn "some AutoVirt repo fetches failed transiently; re-checking tomorrow"
  exit 2
fi

# The two checks below are maintenance, not a blocked update, so they run last:
# an earlier exit for manual-port-needed or patch-gap must never be masked by
# them. They exit non-zero rather than warn because the workflow turns exit 1
# into the single open update-failed issue, and a warning on a daily cron
# reaches nobody.
if [ -n "$LATEST_BT" ] && [ "$LATEST_BT" != "null" ] && [ "$LATEST_BT" != "$CURRENT_BT" ]; then
  err "BetterTiming moved to ${LATEST_BT}; kernel/timing-patch.nix is a hand-port from ${CURRENT_BT} -- re-review it, then set version.json .betterTiming.rev"
  output "error_type" "betterTiming-moved"
  exit 1
fi

if [ "$dead" -ne 0 ]; then
  err "watched AutoVirt repo(s) gone (404): ${dead_forks[*]} -- move them from AUTOVIRT_REPOS to AUTOVIRT_GONE in scripts/update.sh, which reports the day one comes back"
  output "error_type" "fork-stale"
  exit 1
fi

if [ "${#returned_forks[@]}" -ne 0 ]; then
  err "AutoVirt repo(s) back online: ${returned_forks[*]} -- move them from AUTOVIRT_GONE to AUTOVIRT_REPOS in scripts/update.sh"
  output "error_type" "fork-returned"
  exit 1
fi

# aarch64 guest CPU identity (MIDR_EL1, REVIDR_EL1, AIDR_EL1) is writable from
# userspace only once the VMM enables KVM_CAP_ARM_WRITABLE_IMP_ID_REGS, a kernel
# feature since Linux 6.15. QEMU's KVM backend enabling it is the merge that
# makes an ARM spoofing target possible.
if grep -qF 'KVM_CAP_ARM_WRITABLE_IMP_ID_REGS' "$TMP/kvm.c"; then
  err "QEMU master's KVM backend (target/arm/kvm.c) now names KVM_CAP_ARM_WRITABLE_IMP_ID_REGS: aarch64 guest CPU identity is becoming settable under KVM, so re-read docs/ARCHITECTURE.md on what an ARM target would now cost"
  output "error_type" "arm-idregs-upstream"
  exit 1
fi

log "no watched AutoVirt repo ships a patch newer than our vendored AMD-v${OURS[AMD]} or Intel-v${OURS[Intel]}"
exit 0
