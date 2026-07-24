#!/usr/bin/env bash
set -euo pipefail

# Custom update script for vfio-stealth-nix
# Tracks two upstreams: Scrut1ny/AutoVirt + SamuelTulach/BetterTiming
# Contract: exit 0 = success/no-update, exit 1 = failed, exit 2 = network error

OUTPUT_FILE="${GITHUB_OUTPUT:-/tmp/update-outputs.env}"
: > "$OUTPUT_FILE"

output() { echo "$1=$2" >> "$OUTPUT_FILE"; }
log() { echo "==> $*"; }
warn() { echo "::warning::$*"; }
err() { echo "::error::$*"; }

output "package_name" "vfio-stealth"

# --- Read current revs from version.json ---
# betterTiming is NOT a build input: kernel/timing-patch.nix is a hand-port, and
# this rev records which upstream commit it was ported from.
CURRENT_AV=$(jq -r '.autovirt.rev' version.json)
PORTED_BT=$(jq -r '.betterTiming.rev' version.json)
CURRENT_VERSION="${CURRENT_AV:0:7}"
output "old_version" "$CURRENT_VERSION"
log "Current: autovirt=${CURRENT_AV:0:7} (timing-patch ported from BetterTiming ${PORTED_BT:0:7})"

# --- Fetch latest upstream commits ---
fetch_latest() {
  local retries=3 delay=2
  for i in $(seq 1 $retries); do
    if RESULT=$(eval "$1" 2>/dev/null) && [ -n "$RESULT" ] && [ "$RESULT" != "null" ]; then
      echo "$RESULT"
      return 0
    fi
    echo "==> Retry $i/$retries (waiting ${delay}s)..." >&2
    sleep $delay
    delay=$((delay * 2))
  done
  return 1
}

LATEST_AV=$(fetch_latest "curl -sfL 'https://api.github.com/repos/Scrut1ny/AutoVirt/commits/main' | jq -r '.sha'") || {
  warn "Failed to fetch latest AutoVirt commit"
  output "updated" "false"
  exit 2
}

LATEST_BT=$(fetch_latest "curl -sfL 'https://api.github.com/repos/SamuelTulach/BetterTiming/commits/master' | jq -r '.sha'") || LATEST_BT=""
if [ -n "$LATEST_BT" ] && [ "$LATEST_BT" != "$PORTED_BT" ]; then
  warn "BetterTiming moved ${PORTED_BT:0:7} -> ${LATEST_BT:0:7}: kernel/timing-patch.nix is a hand-port -- re-review it, then set version.json .betterTiming.rev to the rev you ported"
fi

output "upstream_url" "https://github.com/Scrut1ny/AutoVirt/commit/${LATEST_AV}"

log "Latest: autovirt=${LATEST_AV:0:7}"

# --- Compare ---
if [ "$CURRENT_AV" = "$LATEST_AV" ]; then
  log "Already up to date"
  output "updated" "false"
  exit 0
fi

log "Update found"
output "updated" "true"

NEW_VERSION="${LATEST_AV:0:7}"
output "new_version" "$NEW_VERSION"

# --- Update version.json ---
DATE=$(date +%Y-%m-%d)
jq --arg av "$LATEST_AV" --arg d "$DATE" --arg avs "${LATEST_AV:0:7}" \
  '.autovirt.rev = $av | .autovirt.version = $avs | .autovirt.date = $d' \
  version.json > version.json.tmp && mv version.json.tmp version.json

# --- Update flake inputs ---
log "Updating flake inputs..."
nix flake update autovirt

# --- Verification chain ---
log "Step 1/3: Eval check"
if ! nix flake check --no-build 2>&1; then
  err "Eval check failed after update"
  output "error_type" "eval-error"
  exit 1
fi

log "Step 2/3: Full check suite (qemu-stealth + ovmf-stealth + sed contracts + boot smoke)"
if ! nix flake check --print-build-logs 2>&1; then
  err "Check suite failed after update"
  output "error_type" "build-error"
  exit 1
fi

log "Step 3/3: ELF verification"
nix build .#default
# Verify the binary that actually matters — the stealth emulator. qemu is a
# multi-output derivation (out/ga/doc/debug); the previous `find … | head -1`
# grabbed an arbitrary first executable, which on that layout is qemu-ga (in
# the separate `ga` output, not a plain ELF), so every real upstream bump
# tripped "Not an ELF binary: result/bin/qemu-ga" (issue #5). Checking
# qemu-system-x86_64 directly is robust to the output layout AND meaningful:
# it proves the emulator built, not merely that *some* file is an ELF.
QEMU_BIN="result/bin/qemu-system-x86_64"
if [ ! -e "$QEMU_BIN" ]; then
  err "qemu-system-x86_64 missing from build output"
  output "error_type" "verification-error"
  exit 1
fi
if ! file -L "$QEMU_BIN" | grep -q ELF; then
  err "qemu-system-x86_64 is not an ELF binary: $(file -L "$QEMU_BIN" 2>&1)"
  output "error_type" "verification-error"
  exit 1
fi
log "Verified ELF: qemu-system-x86_64"
rm -f result

log "Update verified: $CURRENT_VERSION → $NEW_VERSION"
exit 0
