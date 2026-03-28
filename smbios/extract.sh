#!/usr/bin/env bash
set -euo pipefail

# smbios-extract: Dump host SMBIOS tables for VM injection
# Usage: smbios-extract [output-path]
# Requires: root (dmidecode needs it)

OUTPUT="${1:-smbios.bin}"

if [ "$(id -u)" -ne 0 ]; then
  echo "Error: must run as root (dmidecode requires root)" >&2
  echo "Usage: sudo smbios-extract [output-path]" >&2
  exit 1
fi

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

echo "Dumping host SMBIOS tables..."
dmidecode --dump-bin "$TMPDIR/raw.bin"

cp "$TMPDIR/raw.bin" "$OUTPUT"

echo ""
echo "Host SMBIOS dumped to: $OUTPUT"
echo "Inject into QEMU with: -smbios file=$OUTPUT"
echo ""
echo "Review contents with: dmidecode --from-dump $OUTPUT"
