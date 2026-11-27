{
  lib,
  autovirtPatch,
  patchAssertions,
  firmwareVendor,
  acpiOemId,
  acpiOemTableId,
}:

let
  oemTableIdHex =
    "0x"
    + lib.concatMapStrings (c: lib.fixedWidthString 2 "0" (lib.toHexString (lib.strings.charToInt c))) (
      lib.reverseList (lib.stringToCharacters acpiOemTableId)
    );
in
''
  ${patchAssertions}
  echo "=== OVMF-stealth: applying AutoVirt EDK2 patch (BaseTools excluded) ==="
  filterdiff -x '*/BaseTools/*' ${autovirtPatch} > autovirt-edk2-filtered.patch
  if [ "$(grep -c '^@@' autovirt-edk2-filtered.patch)" -eq 0 ]; then
    echo "FATAL: filterdiff yielded no hunks from ${autovirtPatch} -- patch would have been a silent no-op"
    exit 1
  fi
  # why: a hunk landing with fuzz can yield firmware that only looks stealthed
  patch -p1 -F0 --no-backup-if-mismatch -i autovirt-edk2-filtered.patch || {
    echo "FATAL: AutoVirt EDK2 patch did not apply with zero fuzz"
    exit 1
  }
  rm -f autovirt-edk2-filtered.patch
  echo "=== OVMF-stealth: AutoVirt patch applied ==="

  substituteInPlace MdeModulePkg/MdeModulePkg.dec --replace-fail 'L"EDK II"' 'L"${firmwareVendor}"'
  substituteInPlace OvmfPkg/OvmfPkgX64.dsc --replace-quiet 'L"EDK II"' 'L"${firmwareVendor}"'
  landed MdeModulePkg/MdeModulePkg.dec 'L"${firmwareVendor}"' "firmware vendor set in MdeModulePkg.dec"
  gone MdeModulePkg/MdeModulePkg.dec 'L"EDK II"' "no EDK II vendor left in MdeModulePkg.dec"
  gone OvmfPkg/OvmfPkgX64.dsc 'L"EDK II"' "no EDK II vendor left in OvmfPkgX64.dsc"

  sed -i -E 's/^(  gEfiMdeModulePkgTokenSpaceGuid\.PcdAcpiDefaultOemId\|)"[^"]*"/\1"${acpiOemId}"/; s/^(  gEfiMdeModulePkgTokenSpaceGuid\.PcdAcpiDefaultOemTableId\|)0x[0-9A-Fa-f]+/\1${oemTableIdHex}/' MdeModulePkg/MdeModulePkg.dec
  landed MdeModulePkg/MdeModulePkg.dec 'PcdAcpiDefaultOemId|"${acpiOemId}"|' "OVMF's own ACPI tables carry the OEM id ${acpiOemId}"
  landed MdeModulePkg/MdeModulePkg.dec 'PcdAcpiDefaultOemTableId|${oemTableIdHex}|' "OVMF's own ACPI tables carry the OEM table id ${acpiOemTableId}"

  # why: at profile revision 0 OVMF logs its firmware volumes as EV_EFI_PLATFORM_FIRMWARE_BLOB at OVMF's own fixed addresses, which VMAware's MEASURED_BOOT reads as OVMF; revision 105 logs them as EV_EFI_PLATFORM_FIRMWARE_BLOB2 with their names
  substituteInPlace MdeModulePkg/MdeModulePkg.dec --replace-fail 'PcdTcgPfpMeasurementRevision|0|UINT32' 'PcdTcgPfpMeasurementRevision|105|UINT32'
  landed MdeModulePkg/MdeModulePkg.dec 'PcdTcgPfpMeasurementRevision|105|UINT32' "OVMF follows TCG platform firmware profile revision 105"

  present OvmfPkg/OvmfPkgX64.dsc BootGraphicsResourceTableDxe "the BGRT driver is listed in the DSC"
  present OvmfPkg/OvmfPkgX64.fdf BootGraphicsResourceTableDxe "the BGRT driver is listed in the FDF"
  present OvmfPkg/OvmfPkgX64.fdf LogoDxe "the boot logo driver is listed in the FDF"
  sed -i '/BootGraphicsResourceTableDxe/d' OvmfPkg/OvmfPkgX64.dsc OvmfPkg/OvmfPkgX64.fdf
  sed -i '/LogoDxe/d' OvmfPkg/OvmfPkgX64.fdf
  gone OvmfPkg/OvmfPkgX64.dsc BootGraphicsResourceTableDxe "BGRT driver removed from the DSC"
  gone OvmfPkg/OvmfPkgX64.fdf BootGraphicsResourceTableDxe "BGRT driver removed from the FDF"
  gone OvmfPkg/OvmfPkgX64.fdf LogoDxe "boot logo driver removed from the FDF"

  # why: qemu/post-patch.nix gives the MCH its stock id 0x29C0, which OVMF's platform code checks
  sed -i 's/define INTEL_Q35_MCH_DEVICE_ID.*$/define INTEL_Q35_MCH_DEVICE_ID    0x29C0/' \
    OvmfPkg/Include/IndustryStandard/Q35MchIch9.h
  if ! grep -q 'INTEL_Q35_MCH_DEVICE_ID.*0x29C0' OvmfPkg/Include/IndustryStandard/Q35MchIch9.h; then
    echo "FATAL: MCH device ID revert to 0x29C0 failed"
    grep -n 'MCH_DEVICE_ID\|0x14[dD]8\|0x29[cC]0' OvmfPkg/Include/IndustryStandard/Q35MchIch9.h || true
    exit 1
  fi

  # why: anchored on the macro name, since AutoVirt has moved this address twice
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

  sed -i 's|^\( *\)0x[0-9A-Fa-f]\{4\}, \/\/ 0x1b36,\(\r\?\)$|\10x1b36,\2|' OvmfPkg/QemuVideoDxe/Driver.c
  exactly_one OvmfPkg/QemuVideoDxe/Driver.c '^ +0x1b36,.?$' "the QXL entry keeps vendor 1b36, which QEMU's QXL card still reports"
  gone OvmfPkg/QemuVideoDxe/Driver.c '// 0x1b36,' "no QXL entry left on another vendor"

  # why: OVMF reads QEMU's EDID only for a resolution, so Windows on an emulated display found no monitor and named it Default_Monitor
  sed -i 's/\r$//' OvmfPkg/QemuVideoDxe/Qemu.h OvmfPkg/QemuVideoDxe/Initialize.c OvmfPkg/QemuVideoDxe/Driver.c OvmfPkg/QemuVideoDxe/QemuVideoDxe.inf
  gone OvmfPkg/QemuVideoDxe/Qemu.h $'\r' "Qemu.h has LF line endings for edid-protocols.patch"
  gone OvmfPkg/QemuVideoDxe/Initialize.c $'\r' "Initialize.c has LF line endings for edid-protocols.patch"
  gone OvmfPkg/QemuVideoDxe/Driver.c $'\r' "Driver.c has LF line endings for edid-protocols.patch"
  gone OvmfPkg/QemuVideoDxe/QemuVideoDxe.inf $'\r' "QemuVideoDxe.inf has LF line endings for edid-protocols.patch"
  patch -p1 -F0 --no-backup-if-mismatch -i ${./edid-protocols.patch} || {
    echo "FATAL: ovmf/edid-protocols.patch did not apply with zero fuzz"
    exit 1
  }
  landed OvmfPkg/QemuVideoDxe/QemuVideoDxe.inf 'gEfiEdidDiscoveredProtocolGuid' "QemuVideoDxe declares the EDID Discovered protocol"
  landed OvmfPkg/QemuVideoDxe/Initialize.c 'Private->EdidActive.Edid           = Private->Edid;' "QemuVideoDxe hands QEMU's EDID to the EDID Active protocol"

  for library in OvmfPkg/Library/QemuFwCfgLib/*.c; do
    substituteInPlace "$library" --replace-quiet "SIGNATURE_32 ('Q', 'E', 'M', 'U')" "SIGNATURE_32 (0xFF, 0xFF, 0xFF, 0xFF)"
  done
  for library in QemuFwCfgSec QemuFwCfgPei QemuFwCfgDxe QemuFwCfgMmioPei QemuFwCfgMmioDxe; do
    landed OvmfPkg/Library/QemuFwCfgLib/$library.c "SIGNATURE_32 (0xFF, 0xFF, 0xFF, 0xFF)" "$library expects the fw_cfg signature qemu/post-patch.nix sets"
  done
  if grep -rlF "SIGNATURE_32 ('Q', 'E', 'M', 'U')" OvmfPkg; then
    echo "FATAL: an OVMF file still expects the QEMU fw_cfg signature (listed above)"
    exit 1
  fi

  echo "=== OVMF-stealth postPatch complete ==="
''
