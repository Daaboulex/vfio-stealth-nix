#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -ne 1 ]; then
  echo "Usage: sudo smbios-extract <output-directory>" >&2
  exit 2
fi
OUTPUT="$1"

if [ "$(id -u)" -ne 0 ]; then
  echo "Error: must run as root (dmidecode requires root)" >&2
  echo "Usage: sudo smbios-extract <output-directory>" >&2
  exit 1
fi

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

echo "Dumping host SMBIOS tables..." >&2
dmidecode --dump-bin "$TMPDIR/host.dump" >&2

echo "Pass these arguments to QEMU:" >&2
smbios-split "$TMPDIR/host.dump" "$OUTPUT"
cp "$TMPDIR/host.dump" "$OUTPUT/host.dump"

echo "Review the host tables with: dmidecode --from-dump $OUTPUT/host.dump" >&2
