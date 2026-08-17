{ autovirtPatch }:

''
  echo "=== OVMF-stealth: applying AutoVirt EDK2 patch (BaseTools excluded) ==="
  filterdiff -x '*/BaseTools/*' ${autovirtPatch} > autovirt-edk2-filtered.patch
  if [ "$(grep -c '^@@' autovirt-edk2-filtered.patch)" -eq 0 ]; then
    echo "FATAL: filterdiff yielded no hunks from ${autovirtPatch} -- patch would have been a silent no-op"
    exit 1
  fi
  # -F0: a hunk landing with fuzz can yield firmware that merely looks stealthed.
  patch -p1 -F0 --no-backup-if-mismatch -i autovirt-edk2-filtered.patch || {
    echo "FATAL: AutoVirt EDK2 patch did not apply with zero fuzz"
    exit 1
  }
  rm -f autovirt-edk2-filtered.patch
  echo "=== OVMF-stealth: AutoVirt patch applied ==="

  # Replace firmware vendor string. The PCD default L"EDK II" lives in
  # MdeModulePkg.dec (not the DSC). sed handles CRLF line endings.
  sed -i 's|L"EDK II"|L"American Megatrends Inc."|g' \
    MdeModulePkg/MdeModulePkg.dec OvmfPkg/OvmfPkgX64.dsc 2>/dev/null || true
  if grep -rq 'L"EDK II"' MdeModulePkg/MdeModulePkg.dec OvmfPkg/OvmfPkgX64.dsc; then
    echo "FATAL: firmware vendor string still contains L\"EDK II\""
    exit 1
  fi

  # Strip TianoCore boot logo + BGRT table (VMAware CRC identifier 0x110350C5).
  sed -i '/BootGraphicsResourceTableDxe/d' OvmfPkg/OvmfPkgX64.dsc OvmfPkg/OvmfPkgX64.fdf
  sed -i '/LogoDxe/d' OvmfPkg/OvmfPkgX64.fdf
  if grep -q 'BootGraphicsResourceTableDxe' OvmfPkg/OvmfPkgX64.dsc; then
    echo "FATAL: BootGraphicsResourceTableDxe still in DSC"; exit 1
  fi
  if grep -q 'BootGraphicsResourceTableDxe' OvmfPkg/OvmfPkgX64.fdf; then
    echo "FATAL: BootGraphicsResourceTableDxe still in FDF"; exit 1
  fi
  if grep -q 'LogoDxe' OvmfPkg/OvmfPkgX64.fdf; then
    echo "FATAL: LogoDxe still in FDF"; exit 1
  fi

  # Revert AutoVirt's Q35 MCH device ID (0x14D8 -> 0x29C0).
  # The OVMF build enrolls Secure Boot keys by booting inside STOCK
  # QEMU (accel=tcg), whose MCH is 0x29C0. The runtime qemu-stealth
  # also reverts this (post-patch.nix).
  sed -i 's/define INTEL_Q35_MCH_DEVICE_ID.*$/define INTEL_Q35_MCH_DEVICE_ID    0x29C0/' \
    OvmfPkg/Include/IndustryStandard/Q35MchIch9.h
  if ! grep -q 'INTEL_Q35_MCH_DEVICE_ID.*0x29C0' OvmfPkg/Include/IndustryStandard/Q35MchIch9.h; then
    echo "FATAL: MCH device ID revert to 0x29C0 failed"
    grep -n 'MCH_DEVICE_ID\|0x14[dD]8\|0x29[cC]0' OvmfPkg/Include/IndustryStandard/Q35MchIch9.h || true
    exit 1
  fi

  # Revert AutoVirt's Q35 PM register base to the stock ICH9 LPC location.
  # Anchored on the macro NAME, never on AutoVirt's address: they have already
  # moved it twice (0x14 function 3, then function 0), so a pinned "from"
  # address silently stops matching and the revert no-ops. Each macro body is
  # the single continuation line after its #define, rewritten wholesale to the
  # stock text. DRAMC_REGISTER_Q35 addresses a different device at (0, 0, 0)
  # and must never be caught by this.
  sed -i -E '/^#define POWER_MGMT_REGISTER_Q35\(Offset\)/{n;s|.*|  PCI_LIB_ADDRESS (0, 0x1f, 0, (Offset))|}' \
    OvmfPkg/Include/IndustryStandard/Q35MchIch9.h
  sed -i -E '/^#define POWER_MGMT_REGISTER_Q35_EFI_PCI_ADDRESS\(Offset\)/{n;s|.*|  EFI_PCI_ADDRESS (0, 0x1f, 0, (Offset))|}' \
    OvmfPkg/Include/IndustryStandard/Q35MchIch9.h
  if ! grep -q '^  PCI_LIB_ADDRESS (0, 0x1f, 0, (Offset))$' OvmfPkg/Include/IndustryStandard/Q35MchIch9.h; then
    echo "FATAL: PM PCI_LIB_ADDRESS revert to (0x1f,0) failed -- POWER_MGMT_REGISTER_Q35 renamed or reshaped?"
    grep -n 'POWER_MGMT_REGISTER_Q35\|PCI_LIB_ADDRESS' OvmfPkg/Include/IndustryStandard/Q35MchIch9.h || true
    exit 1
  fi
  if ! grep -q '^  EFI_PCI_ADDRESS (0, 0x1f, 0, (Offset))$' OvmfPkg/Include/IndustryStandard/Q35MchIch9.h; then
    echo "FATAL: PM EFI_PCI_ADDRESS revert to (0x1f,0) failed -- macro renamed or reshaped?"
    exit 1
  fi
  if ! grep -q 'DRAMC_REGISTER_Q35(Offset)  PCI_LIB_ADDRESS (0, 0, 0, (Offset))' \
    OvmfPkg/Include/IndustryStandard/Q35MchIch9.h; then
    echo "FATAL: DRAMC_REGISTER_Q35 no longer addresses (0, 0, 0) -- the PM revert may have hit the wrong macro"
    exit 1
  fi
  addrs=$(grep -nE '(PCI_LIB_ADDRESS|EFI_PCI_ADDRESS) \(' \
    OvmfPkg/Include/IndustryStandard/Q35MchIch9.h || true)
  if grep -vE '\(0, 0, 0,|\(0, 0x1f, 0,' <<< "$addrs"; then
    echo "FATAL: a non-stock PCI address triple survives in Q35MchIch9.h (listed above)"
    exit 1
  fi

  echo "=== OVMF-stealth postPatch complete ==="
''
