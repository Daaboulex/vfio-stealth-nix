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
CURRENT_AV=$(jq -r '.autovirt.rev' version.json)
CURRENT_BT=$(jq -r '.betterTiming.rev' version.json)
CURRENT_VERSION="${CURRENT_AV:0:7}-${CURRENT_BT:0:7}"
output "old_version" "$CURRENT_VERSION"
log "Current: autovirt=${CURRENT_AV:0:7} betterTiming=${CURRENT_BT:0:7}"

# --- Fetch latest upstream commits ---
fetch_latest() {
  local retries=3 delay=2
  for i in $(seq 1 $retries); do
    if RESULT=$(eval "$1" 2>/dev/null) && [ -n "$RESULT" ] && [ "$RESULT" != "null" ]; then
      echo "$RESULT"
      return 0
    fi
    log "Retry $i/$retries (waiting ${delay}s)..."
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

LATEST_BT=$(fetch_latest "curl -sfL 'https://api.github.com/repos/SamuelTulach/BetterTiming/commits/master' | jq -r '.sha'") || {
  warn "Failed to fetch latest BetterTiming commit"
  output "updated" "false"
  exit 2
}

output "upstream_url" "https://github.com/Scrut1ny/AutoVirt/commit/${LATEST_AV}"

log "Latest: autovirt=${LATEST_AV:0:7} betterTiming=${LATEST_BT:0:7}"

# --- Compare ---
if [ "$CURRENT_AV" = "$LATEST_AV" ] && [ "$CURRENT_BT" = "$LATEST_BT" ]; then
  log "Already up to date"
  output "updated" "false"
  exit 0
fi

log "Update found"
output "updated" "true"

NEW_VERSION="${LATEST_AV:0:7}-${LATEST_BT:0:7}"
output "new_version" "$NEW_VERSION"

# --- Update version.json ---
DATE=$(date +%Y-%m-%d)
jq --arg av "$LATEST_AV" --arg bt "$LATEST_BT" --arg d "$DATE" \
  --arg avs "${LATEST_AV:0:7}" --arg bts "${LATEST_BT:0:7}" \
  '.autovirt.rev = $av | .autovirt.version = $avs | .autovirt.date = $d |
   .betterTiming.rev = $bt | .betterTiming.version = $bts | .betterTiming.date = $d' \
  version.json > version.json.tmp && mv version.json.tmp version.json

# --- Update flake inputs ---
log "Updating flake inputs..."
nix flake update autovirt better-timing

# --- Verification chain ---
log "Step 1/3: Eval check"
if ! nix flake check --no-build 2>&1; then
  err "Eval check failed after update"
  output "error_type" "eval-error"
  exit 1
fi

log "Step 2/3: Build qemu-stealth"
if ! nix build .#default --no-link --print-build-logs 2>&1; then
  err "Build failed after update"
  output "error_type" "build-error"
  exit 1
fi

log "Step 3/3: ELF verification"
nix build .#default
FOUND=$(find result/bin/ \( -type f -o -type l \) -executable 2>/dev/null | head -1)
if [ -n "$FOUND" ]; then
  file "$FOUND" | grep -q ELF || { err "Not an ELF binary: $FOUND"; output "error_type" "verification-error"; exit 1; }
fi
rm -f result

log "Update verified: $CURRENT_VERSION → $NEW_VERSION"
exit 0
