#!/usr/bin/env bash
set -euo pipefail

# why: exit 2 is a transient failure the workflow retries; exit 1 opens its one update-failed issue, so every finding a person must act on exits 1

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
  "Scrut1ny"
  "Zhaodaidai"
  "fortesoft-co"
)

AUTOVIRT_GONE=()

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

dead=0
dead_forks=()
returned_forks=()
transient=0
: >"$TMP/cands"
: >"$TMP/edk2-cands"

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
    warn "${fork}/AutoVirt: fetch failed (HTTP ${code:-000}): transient"
    transient=1
    continue
    ;;
  esac
  jq -r '.[].name' "$TMP/body.json" |
    sed -n 's/^\(AMD\|Intel\)-v\([0-9][0-9.]*\)\.patch$/\1 \2/p' |
    while read -r vendor v; do echo "$vendor $v $fork"; done >>"$TMP/cands"
  edk2_code=$(curl -s -o "$TMP/edk2.json" -w '%{http_code}' \
    "https://api.github.com/repos/${fork}/AutoVirt/contents/patches/EDK2" 2>/dev/null || true)
  case "${edk2_code:-000}" in
  200)
    jq -r '.[].name' "$TMP/edk2.json" |
      sed -n 's/^\(AMD\|Intel\)-edk2-stable\([0-9]\{6\}\)\.patch$/\1 \2/p' |
      while read -r vendor tag; do echo "$vendor $tag $fork"; done >>"$TMP/edk2-cands"
    ;;
  404)
    err "${fork}/AutoVirt has no patches/EDK2 (404): its EDK2 patches moved; point scripts/update.sh at their new place"
    output "error_type" "edk2-watch-moved"
    exit 1
    ;;
  *)
    warn "${fork}/AutoVirt EDK2 list: fetch failed (HTTP ${edk2_code:-000}): transient"
    transient=1
    ;;
  esac
done

if [ "$dead" -ge "${#AUTOVIRT_REPOS[@]}" ]; then
  err "every watched AutoVirt repo is gone (404): update AUTOVIRT_REPOS in scripts/update.sh"
  output "error_type" "upstream-gone"
  exit 1
fi

for vendor in "${VENDORS[@]}"; do
  best_line=$(newer_fork_patch "$vendor" "${OURS[$vendor]}" "$TMP/cands")
  if [ -n "$best_line" ]; then
    best_version=${best_line%% *}
    best_fork=${best_line##* }
    warn "${best_fork}/AutoVirt ships ${vendor}-v${best_version}.patch; we vendor ${vendor}-v${OURS[$vendor]}: manual port needed"
    output "new_version" "${vendor}-v${best_version}"
    output "upstream_url" "https://github.com/${best_fork}/AutoVirt/blob/main/patches/QEMU/${vendor}-v${best_version}.patch"
    output "error_type" "manual-port-needed"
    exit 1
  fi
done

for vendor in "${VENDORS[@]}"; do
  ours_edk2=$(find vendor/autovirt/patches/EDK2 -maxdepth 1 -name "${vendor}-edk2-stable*.patch" -printf '%f\n' |
    sed -n 's/^.*-edk2-stable\([0-9]\{6\}\)\.patch$/\1/p' | sort -n | tail -n 1)
  if [ -z "$ours_edk2" ]; then
    err "vendor/autovirt/patches/EDK2 holds no ${vendor}-edk2-stable<tag>.patch"
    output "error_type" "inventory-error"
    exit 1
  fi
  best_edk2=$(awk -v v="$vendor" '$1 == v {print $2, $3}' "$TMP/edk2-cands" | sort -n | tail -n 1)
  if [ -n "$best_edk2" ] && [ "${best_edk2%% *}" -gt "$ours_edk2" ]; then
    err "${best_edk2##* }/AutoVirt ships ${vendor}-edk2-stable${best_edk2%% *}.patch; we vendor ${vendor}-edk2-stable${ours_edk2}: manual port needed"
    output "new_version" "${vendor}-edk2-stable${best_edk2%% *}"
    output "upstream_url" "https://github.com/${best_edk2##* }/AutoVirt/blob/main/patches/EDK2/${vendor}-edk2-stable${best_edk2%% *}.patch"
    output "error_type" "edk2-manual-port-needed"
    exit 1
  fi
done

NP_QEMU=$(nix eval --raw 'github:NixOS/nixpkgs/nixos-unstable#qemu.version' 2>/dev/null) || NP_QEMU=""
UP_TAGS=$(git ls-remote --tags --refs https://gitlab.com/qemu-project/qemu.git 'v*') || UP_TAGS=""
UP_QEMU=$(newest_release <<<"$UP_TAGS")
if [ -z "$NP_QEMU" ] || [ "$NP_QEMU" = "null" ] || [ -z "$UP_QEMU" ]; then
  warn "could not read the newest QEMU of nixpkgs-unstable (${NP_QEMU:-unread}) and upstream (${UP_QEMU:-unread}): transient"
  transient=1
else
  target=$(printf '%s\n%s\n' "$NP_QEMU" "$UP_QEMU" | sort -V | tail -1)
  gaps=()
  for vendor in "${VENDORS[@]}"; do
    [ -z "$(qemu_gap_for "$target" "$vendor")" ] || gaps+=("$vendor")
  done
  if [ "${#gaps[@]}" -gt 0 ]; then
    if ! prefetch=$(nix store prefetch-file --json "https://download.qemu.org/qemu-${target}.tar.xz"); then
      warn "could not fetch the QEMU ${target} tarball to probe it: transient"
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
LATEST_BT=""
BT_URL='https://api.github.com/repos/SamuelTulach/BetterTiming/commits/master'
bt_code=$(curl -s -o "$TMP/bettertiming.json" -w '%{http_code}' "$BT_URL" 2>/dev/null || true)
case "$bt_code" in
200) LATEST_BT=$(jq -r '.sha' "$TMP/bettertiming.json") ;;
404)
  err "${BT_URL} is gone (404): BetterTiming moved or was removed; find its new home, or keep kernel/timing-patch.nix as the last port"
  output "error_type" "betterTiming-gone"
  exit 1
  ;;
*)
  warn "could not fetch ${BT_URL} (HTTP ${bt_code:-000}): transient"
  transient=1
  ;;
esac

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
  warn "could not fetch ${QEMU_KVM_URL} (HTTP ${kvm_code:-000}): transient"
  transient=1
  ;;
esac
CURRENT_VN=$(jq -r '.vfioNative.rev' version.json)
LATEST_VN=""
VN_URL='https://git.archworks.co/api/v1/repos/sandwich/vfio-native/branches/main'
vn_code=$(curl -s -o "$TMP/vfio-native.json" -w '%{http_code}' "$VN_URL" 2>/dev/null || true)
case "$vn_code" in
200) LATEST_VN=$(jq -r '.commit.id' "$TMP/vfio-native.json") ;;
404)
  err "${VN_URL} is gone (404): vfio-native moved or was removed; find its new home and point scripts/update.sh at it, or keep vendor/vfio-native as the last copy"
  output "error_type" "vfioNative-gone"
  exit 1
  ;;
*)
  warn "could not fetch ${VN_URL} (HTTP ${vn_code:-000}): transient"
  transient=1
  ;;
esac
CURRENT_AV=$(jq -r '.autovirt.rev' version.json)
AV_COMPARE_URL="https://api.github.com/repos/Scrut1ny/AutoVirt/compare/${CURRENT_AV}...HEAD"
av_changed=""
av_code=$(curl -sL -o "$TMP/autovirt-compare.json" -w '%{http_code}' "$AV_COMPARE_URL" 2>/dev/null || true)
case "$av_code" in
200) av_changed=$(jq -r '[.files[] | select(.filename | startswith("patches/")) | select(.filename != "patches/README.md") | .filename] | join(" ")' "$TMP/autovirt-compare.json") ;;
404)
  err "${AV_COMPARE_URL} is gone (404): AutoVirt rewrote its history past ${CURRENT_AV} or moved; compare vendor/autovirt with its patches/ by hand and set .autovirt.rev"
  output "error_type" "autovirt-rev-gone"
  exit 1
  ;;
*)
  warn "could not fetch ${AV_COMPARE_URL} (HTTP ${av_code:-000}): transient"
  transient=1
  ;;
esac
declare -A AV_PRS=([173]="the duplicate ACPI name fix" [174]="the QEMU 11.1 port")
av_settled=()
for pr in "${!AV_PRS[@]}"; do
  pr_code=$(curl -sL -o "$TMP/pr-${pr}.json" -w '%{http_code}' "https://api.github.com/repos/Scrut1ny/AutoVirt/pulls/${pr}" 2>/dev/null || true)
  case "$pr_code" in
  200)
    if [ "$(jq -r '.state' "$TMP/pr-${pr}.json")" != open ]; then
      av_settled+=("#${pr} (${AV_PRS[$pr]}) is $(jq -r 'if .merged then "merged" else "closed" end' "$TMP/pr-${pr}.json")")
    fi
    ;;
  404)
    err "AutoVirt pull request ${pr} (${AV_PRS[$pr]}) is gone (404); check its state on GitHub and remove it from AV_PRS in scripts/update.sh"
    output "error_type" "autovirt-pr-gone"
    exit 1
    ;;
  *)
    warn "could not fetch AutoVirt pull request ${pr} (HTTP ${pr_code:-000}): transient"
    transient=1
    ;;
  esac
done
CURRENT_VMAWARE=$(jq -r '.vmaware.version' version.json)
LATEST_VMAWARE=""
VMAWARE_URL='https://api.github.com/repos/kernelwernel/VMAware/releases/latest'
vmaware_code=$(curl -sL -o "$TMP/vmaware.json" -w '%{http_code}' "$VMAWARE_URL" 2>/dev/null || true)
case "$vmaware_code" in
200) LATEST_VMAWARE=$(jq -r '.tag_name | ltrimstr("v")' "$TMP/vmaware.json") ;;
404)
  err "${VMAWARE_URL} is gone (404): VMAware moved or stopped publishing releases; find its new home, or keep the pin in version.json"
  output "error_type" "vmaware-gone"
  exit 1
  ;;
*)
  warn "could not fetch ${VMAWARE_URL} (HTTP ${vmaware_code:-000}): transient"
  transient=1
  ;;
esac
CURRENT_DBX=$(jq -r '.microsoftDbx.rev' version.json)
LATEST_DBX=""
DBX_URL='https://api.github.com/repos/microsoft/secureboot_objects/commits?path=PostSignedObjects/SignedByKEK2023/dbx_x64.efiauth2&per_page=1'
dbx_code=$(curl -sL -o "$TMP/dbx.json" -w '%{http_code}' "$DBX_URL" 2>/dev/null || true)
case "$dbx_code" in
200) LATEST_DBX=$(jq -r '.[0].sha // empty' "$TMP/dbx.json") ;;
404)
  err "${DBX_URL} is gone (404): Microsoft moved its revocation list; find the new path of the x64 dbx signed by KEK 2023, or keep the pin in version.json"
  output "error_type" "dbx-gone"
  exit 1
  ;;
*)
  warn "could not fetch ${DBX_URL} (HTTP ${dbx_code:-000}): transient"
  transient=1
  ;;
esac
# why: after a failed fetch the repo list is incomplete, so nothing may be reported as settled
if [ "$transient" -ne 0 ]; then
  warn "some fetches failed transiently; re-checking at the next run"
  exit 2
fi

# why: these maintenance findings run last, so they never mask a manual-port or patch-gap exit
if [ -n "$LATEST_BT" ] && [ "$LATEST_BT" != "null" ] && [ "$LATEST_BT" != "$CURRENT_BT" ]; then
  err "BetterTiming moved to ${LATEST_BT}; kernel/timing-patch.nix is a hand-port from ${CURRENT_BT}: re-review it, then set version.json .betterTiming.rev"
  output "error_type" "betterTiming-moved"
  exit 1
fi

if [ -n "$LATEST_VN" ] && [ "$LATEST_VN" != "null" ] && [ "$LATEST_VN" != "$CURRENT_VN" ]; then
  err "vfio-native moved to ${LATEST_VN}; vendor/vfio-native holds patches/kvm from ${CURRENT_VN}: compare its patches/kvm, copy what changed, build the kernel-runtime sets, then set version.json .vfioNative.rev"
  output "error_type" "vfioNative-moved"
  exit 1
fi

if [ -n "$LATEST_VMAWARE" ] && [ "$LATEST_VMAWARE" != "null" ] && [ "$LATEST_VMAWARE" != "$CURRENT_VMAWARE" ]; then
  err "VMAware ${LATEST_VMAWARE} is out; the probe runs ${CURRENT_VMAWARE}: set .vmaware.version and .vmaware.hash in version.json, re-aim verify/vmaware-mingw.patch if its hunks moved, build the boot checks, and update verify/vmaware-expected.json and verify/vmaware-expected-windows.json for each check the new release fires"
  output "error_type" "vmaware-moved"
  exit 1
fi

if [ -n "$LATEST_DBX" ] && [ "$LATEST_DBX" != "$CURRENT_DBX" ]; then
  err "Microsoft published a new revocation list at ${LATEST_DBX}; secureBootVars enrolls the one from ${CURRENT_DBX}: set .microsoftDbx.rev, .version, .date and .hash in version.json and build the boot checks"
  output "error_type" "dbx-moved"
  exit 1
fi

if [ -n "$av_changed" ]; then
  err "AutoVirt changed ${av_changed} since ${CURRENT_AV}; read the change, port it into vendor/autovirt and record it in vendor/autovirt/README, then set .autovirt.rev"
  output "error_type" "autovirt-patches-moved"
  exit 1
fi

if [ "${#av_settled[@]}" -gt 0 ]; then
  err "AutoVirt pull request ${av_settled[*]}; when merged, take the upstream patch in place of the local one; when closed, keep the local one"
  output "error_type" "autovirt-pr-settled"
  exit 1
fi

if [ "$dead" -ne 0 ]; then
  err "watched AutoVirt repo(s) gone (404): ${dead_forks[*]}: move them from AUTOVIRT_REPOS to AUTOVIRT_GONE in scripts/update.sh, which reports the day one comes back"
  output "error_type" "fork-stale"
  exit 1
fi

if [ "${#returned_forks[@]}" -ne 0 ]; then
  err "AutoVirt repo(s) back online: ${returned_forks[*]}: move them from AUTOVIRT_GONE to AUTOVIRT_REPOS in scripts/update.sh"
  output "error_type" "fork-returned"
  exit 1
fi

# why: an aarch64 guest's CPU identity becomes spoofable only once QEMU's KVM backend enables KVM_CAP_ARM_WRITABLE_IMP_ID_REGS
if grep -qF 'KVM_CAP_ARM_WRITABLE_IMP_ID_REGS' "$TMP/kvm.c"; then
  err "QEMU master's KVM backend (target/arm/kvm.c) now names KVM_CAP_ARM_WRITABLE_IMP_ID_REGS: aarch64 guest CPU identity is becoming settable under KVM, so re-read docs/COMPATIBILITY.md, Platforms, on what an ARM target would now cost"
  output "error_type" "arm-idregs-upstream"
  exit 1
fi

log "no watched AutoVirt repo ships a patch newer than our vendored AMD-v${OURS[AMD]} or Intel-v${OURS[Intel]}"
exit 0
