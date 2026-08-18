#!/usr/bin/env bash
set -euo pipefail

# Custom update script for vfio-stealth-nix
# AutoVirt upstream is deleted (~2026-05); its patches are vendored in
# vendor/autovirt. This script watches the live forks for a patch newer than
# what is vendored, and nixpkgs-unstable for a QEMU series no vendored patch
# covers, so the canonical update workflow files an issue the day either
# appears. Adoption stays a hand decision (see docs/RELEASE-PROCEDURE.md).
# Contract: exit 0 = nothing to do, exit 1 = manual port needed, upstream
# gone, or a patch gap (error_type says which), exit 2 = transient network
# failure.

output() { echo "$1=$2" >>"$OUTPUT_FILE"; }
log() { echo "==> $*"; }
warn() { echo "::warning::$*"; }
err() { echo "::error::$*"; }

newest_series() {
  local vendor="$1"
  ls "$VENDOR_DIR" |
    sed -n "s/^${vendor}-v\([0-9][0-9.]*\)\.patch$/\1/p" |
    sort -V |
    tail -1
}

amd_series_set() {
  ls "$VENDOR_DIR" |
    sed -n 's/^AMD-v\([0-9][0-9]*\.[0-9][0-9]*\)\.[0-9][0-9.]*\.patch$/\1/p' |
    sort -u
}

qemu_gap_for() {
  local qemu_version="$1" series
  series="${qemu_version%.*}"
  if ! amd_series_set | grep -qx "$series"; then
    printf '%s' "$qemu_version"
  fi
}

[[ ${BASH_SOURCE[0]} == "$0" ]] || return 0

OUTPUT_FILE="${GITHUB_OUTPUT:-/tmp/update-outputs.env}"
: >"$OUTPUT_FILE"

output "package_name" "vfio-stealth"
output "updated" "false"

VENDOR_DIR="vendor/autovirt/patches/QEMU"

AMD_OURS=$(newest_series AMD)
INTEL_OURS=$(newest_series Intel)

if [ -z "$AMD_OURS" ] || [ -z "$INTEL_OURS" ]; then
  err "vendor patch inventory is empty or malformed in $VENDOR_DIR"
  output "error_type" "inventory-error"
  exit 1
fi

log "Vendored: AMD-v${AMD_OURS} Intel-v${INTEL_OURS}"
output "old_version" "$AMD_OURS"

FORKS=(
  "Zhaodaidai"
  "fortesoft-co"
  "Keyemail"
)

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

dead=0
transient=0
: >"$TMP/cands"

for fork in "${FORKS[@]}"; do
  code=$(curl -s -o "$TMP/body.json" -w '%{http_code}' \
    "https://api.github.com/repos/${fork}/AutoVirt/contents/patches/QEMU" 2>/dev/null || true)
  case "$code" in
  200) ;;
  404)
    warn "fork ${fork}/AutoVirt is gone (404); drop it from FORKS in scripts/update.sh"
    dead=$((dead + 1))
    continue
    ;;
  *)
    warn "fork ${fork}/AutoVirt: fetch failed (HTTP ${code:-000}) - transient"
    transient=1
    continue
    ;;
  esac
  jq -r '.[].name' "$TMP/body.json" |
    sed -n 's/^AMD-v\([0-9][0-9.]*\)\.patch$/\1/p' |
    while read -r v; do echo "$v $fork"; done >>"$TMP/cands"
done

if [ "$dead" -ge "${#FORKS[@]}" ]; then
  err "every watched fork is gone (404) - update FORKS in scripts/update.sh"
  output "error_type" "upstream-gone"
  exit 1
fi

if [ -s "$TMP/cands" ]; then
  best_line=$(sort -V -k1,1 "$TMP/cands" | tail -1)
  best_version=${best_line%% *}
  best_fork=${best_line##* }
  newest=$(printf '%s\n%s\n' "$AMD_OURS" "$best_version" | sort -V | tail -1)
  if [ "$newest" = "$best_version" ] && [ "$best_version" != "$AMD_OURS" ]; then
    warn "fork ${best_fork} ships AMD-v${best_version}.patch; we vendor AMD-v${AMD_OURS} - manual port needed"
    output "new_version" "$best_version"
    output "upstream_url" "https://github.com/${best_fork}/AutoVirt/blob/main/patches/QEMU/AMD-v${best_version}.patch"
    output "error_type" "manual-port-needed"
    exit 1
  fi
fi

NP_QEMU=$(nix eval --raw 'github:NixOS/nixpkgs/nixos-unstable#qemu.version' 2>/dev/null) || NP_QEMU=""
if [ -z "$NP_QEMU" ] || [ "$NP_QEMU" = "null" ]; then
  warn "could not determine nixpkgs-unstable's QEMU version; skipping the patch-gap check"
elif [ -n "$(qemu_gap_for "$NP_QEMU")" ]; then
  warn "nixpkgs-unstable ships QEMU ${NP_QEMU}; no vendored AMD patch for series ${NP_QEMU%.*} - consumers ride the ceiling tarball until one lands"
  output "new_version" "$NP_QEMU"
  output "upstream_url" "https://github.com/NixOS/nixpkgs/blob/nixos-unstable/pkgs/applications/virtualization/qemu/package.nix"
  output "error_type" "patch-gap"
  exit 1
fi

CURRENT_BT=$(jq -r '.betterTiming.rev' version.json)
LATEST_BT=$(curl -sfL 'https://api.github.com/repos/SamuelTulach/BetterTiming/commits/master' 2>/dev/null | jq -r '.sha') || LATEST_BT=""
if [ -n "$LATEST_BT" ] && [ "$LATEST_BT" != "null" ] && [ "$LATEST_BT" != "$CURRENT_BT" ]; then
  warn "BetterTiming moved: kernel/timing-patch.nix is a hand-port -- re-review it, then set version.json .betterTiming.rev"
fi

if [ "$transient" -ne 0 ]; then
  warn "some fork fetches failed transiently; re-checking tomorrow"
  exit 2
fi

log "no fork ships a patch newer than our vendored AMD-v${AMD_OURS}"
exit 0
