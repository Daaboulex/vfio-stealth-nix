{
  lib,
  autovirt,
  edidManufacturer,
  edidSerial,
  edidProductCode,
  edidDpi,
  edidWeek,
  edidYear,
  edidResX,
  edidResY,
  acpiOemId,
  acpiOemTableId,
  diskModel,
  diskSerial,
  opticalModel,
  scsiVendor,
  scsiTargetProduct,
}:

''
  echo "=== Applying EDK2/OVMF patch ==="
    # nixpkgs builds OVMF separately; roms/edk2 is absent in the normal
    # derivation, so this block is a no-op.  Kept for standalone builds.
    if [ -d roms/edk2 ]; then
      EDK2_PATCH=""
      for p in "${autovirt}"/patches/EDK2/AMD-edk2-stable*.patch; do
        if [ -f "$p" ]; then EDK2_PATCH="$p"; break; fi
      done
      if [ -z "$EDK2_PATCH" ]; then
        echo "FATAL: no AMD EDK2 patch found in ${autovirt}/patches/EDK2/"
        ls -la "${autovirt}/patches/EDK2/" 2>/dev/null || true
        exit 1
      fi
      echo "Using EDK2 patch: $(basename "$EDK2_PATCH")"
      patch -d roms/edk2 -p1 < "$EDK2_PATCH" || {
        echo "FATAL: EDK2 patch failed"
        exit 1
      }
      substituteInPlace roms/edk2/OvmfPkg/OvmfPkgX64.dsc \
        --replace-warn 'L"EDK II"' 'L"American Megatrends Inc."' || true
    fi

    echo "=== Customizing hardware identifiers ==="

    # EDID: replace stock QEMU monitor identity with configured values
    substituteInPlace hw/display/edid-generate.c \
      --replace-fail '"RHT"' '"${edidManufacturer}"'
    substituteInPlace hw/display/edid-generate.c \
      --replace-fail '"QEMU Monitor"' '"${edidSerial}"'
    sed -i 's|0x1234|${edidProductCode}|g' hw/display/edid-generate.c
    if ! grep -q '${edidProductCode}' hw/display/edid-generate.c; then
      echo "FATAL: EDID product code replacement to ${edidProductCode} did not apply"
      exit 1
    fi
    sed -i 's|edid\[16\] = 42;|edid[16] = ${toString edidWeek};|g' hw/display/edid-generate.c
    if ! grep -q 'edid\[16\] = ${toString edidWeek};' hw/display/edid-generate.c; then
      echo "FATAL: EDID week replacement to ${toString edidWeek} did not apply"
      exit 1
    fi
    sed -i 's|2014 - 1990|${toString edidYear} - 1990|g' hw/display/edid-generate.c
    if ! grep -q '${toString edidYear} - 1990' hw/display/edid-generate.c; then
      echo "FATAL: EDID year replacement to ${toString edidYear} did not apply"
      exit 1
    fi
    sed -i 's|uint32_t dpi = 100;|uint32_t dpi = ${toString edidDpi};|g' hw/display/edid-generate.c
    if ! grep -q 'uint32_t dpi = ${toString edidDpi};' hw/display/edid-generate.c; then
      echo "FATAL: EDID DPI replacement to ${toString edidDpi} did not apply"
      exit 1
    fi
    sed -i 's|info->prefx = 1280;|info->prefx = ${toString edidResX};|g' hw/display/edid-generate.c
    if ! grep -q 'info->prefx = ${toString edidResX};' hw/display/edid-generate.c; then
      echo "FATAL: EDID resolution X replacement to ${toString edidResX} did not apply"
      exit 1
    fi
    sed -i 's|info->prefy = 800;|info->prefy = ${toString edidResY};|g' hw/display/edid-generate.c
    if ! grep -q 'info->prefy = ${toString edidResY};' hw/display/edid-generate.c; then
      echo "FATAL: EDID resolution Y replacement to ${toString edidResY} did not apply"
      exit 1
    fi

    # SCSI INQUIRY: replace stock QEMU vendor/product for dead-LUN fallback in scsi-bus.c
    substituteInPlace hw/scsi/scsi-bus.c \
      --replace-fail '"QEMU    "' '"${builtins.substring 0 8 (scsiVendor + "        ")}"'
    substituteInPlace hw/scsi/scsi-bus.c \
      --replace-fail '"QEMU TARGET     "' '"${scsiTargetProduct}"'

    # SCSI disk: replace stock QEMU product/vendor in scsi-disk.c
    substituteInPlace hw/scsi/scsi-disk.c \
      --replace-fail '"QEMU HARDDISK"' '"${diskModel}"'
    substituteInPlace hw/scsi/scsi-disk.c \
      --replace-fail '"QEMU CD-ROM"' '"${opticalModel}"'
    substituteInPlace hw/scsi/scsi-disk.c \
      --replace-fail '"QEMU"' '"${scsiVendor}"'

    # ACPI OEM: replace values in aml-build.h
    sed -i 's|"ALASKA"|"${acpiOemId}"|g' include/hw/acpi/aml-build.h
    if ! grep -q '"${acpiOemId}"' include/hw/acpi/aml-build.h; then
      echo "FATAL: ACPI OEM ID replacement to ${acpiOemId} did not apply"
      exit 1
    fi
    sed -i 's|"A M I   "|"${acpiOemTableId}"|g' include/hw/acpi/aml-build.h
    if ! grep -q '"${acpiOemTableId}"' include/hw/acpi/aml-build.h; then
      echo "FATAL: ACPI OEM Table ID replacement did not apply"
      exit 1
    fi

    # IDE disk model: patch sets "Samsung SSD 980 500GB" (main) and "Hitachi HMS360404D5CF00" (CF)
    substituteInPlace hw/ide/core.c \
      --replace-fail 'Samsung SSD 980 500GB' '${diskModel}'
    substituteInPlace hw/ide/core.c \
      --replace-fail 'Hitachi HMS360404D5CF00' '${diskModel}'
    # IDE serial: patch blanks it — set realistic serial
    sed -i "s|s->drive_serial_str\[0\] = '\\\\0';|pstrcpy(s->drive_serial_str, sizeof(s->drive_serial_str), \"${diskSerial}\");|g" hw/ide/core.c
    if ! grep -q 'pstrcpy(s->drive_serial_str' hw/ide/core.c; then
      echo "FATAL: IDE serial replacement did not apply"
      exit 1
    fi
    # IDE optical drive: patch sets "HL-DT-ST BD-RE WH16NS60" — replace with configured
    substituteInPlace hw/ide/core.c \
      --replace-fail 'HL-DT-ST BD-RE WH16NS60' '${opticalModel}'

    # Revert Q35 chipset PCI IDs to stock Intel values. AutoVirt remaps
    # ICH9 LPC/SMBus/AHCI to AMD FCH IDs (790e/790b/43f6), but Q35
    # emulates Intel ICH9 behavior. The AMD GPU driver (amdkmdag.sys)
    # sees AMD FCH IDs, takes an AMD-platform code path that expects
    # real FCH hardware features, and crashes with 0x113 BSOD
    # (UNEXPECTED_DEFERRED_DESTRUCTION) when Q35 doesn't provide them.
    # Detection software checks CPUID/SMBIOS/VGA IDs, not chipset bridge IDs,
    # so reverting these has minimal stealth impact.

    # MCH: device ID to 0x29C0 (OVMF build compat + Q35 identity)
    sed -i 's/define PCI_DEVICE_ID_INTEL_P35_MCH.*$/define PCI_DEVICE_ID_INTEL_P35_MCH      0x29c0/' \
      include/hw/pci/pci_ids.h

    # ICH9 LPC bridge: 0x790E -> 0x2918
    sed -i 's/define PCI_DEVICE_ID_INTEL_ICH9_8.*$/define PCI_DEVICE_ID_INTEL_ICH9_8       0x2918/' include/hw/pci/pci_ids.h
    sed -i 's|k->vendor_id = PCI_VENDOR_ID_AMD;|k->vendor_id = PCI_VENDOR_ID_INTEL;|' hw/isa/lpc_ich9.c

    # ICH9 SMBus: 0x790B -> 0x2930
    sed -i 's/define PCI_DEVICE_ID_INTEL_ICH9_6.*$/define PCI_DEVICE_ID_INTEL_ICH9_6       0x2930/' include/hw/pci/pci_ids.h
    sed -i 's|k->vendor_id = PCI_VENDOR_ID_AMD;|k->vendor_id = PCI_VENDOR_ID_INTEL;|' hw/i2c/smbus_ich9.c

    # AHCI: AMD 0x43F6 -> Intel 0x2922 (define lives in pci.h, not pci_ids.h)
    sed -i 's/define PCI_DEVICE_ID_INTEL_82801IR.*$/define PCI_DEVICE_ID_INTEL_82801IR      0x2922/' include/hw/pci/pci.h
    sed -i 's|k->vendor_id = PCI_VENDOR_ID_AMD;|k->vendor_id = PCI_VENDOR_ID_INTEL;|' hw/ide/ich.c
    sed -i 's|k->device_id = PCI_DEVICE_ID_AMD_SATA;|k->device_id = PCI_DEVICE_ID_INTEL_82801IR;|' hw/ide/ich.c

    # Verify all reverts applied
    grep -q 'PCI_DEVICE_ID_INTEL_P35_MCH.*0x29c0' include/hw/pci/pci_ids.h || { echo "FATAL: MCH revert failed"; exit 1; }
    grep -q 'PCI_DEVICE_ID_INTEL_ICH9_8.*0x2918' include/hw/pci/pci_ids.h || { echo "FATAL: LPC revert failed"; exit 1; }
    grep -q 'PCI_DEVICE_ID_INTEL_ICH9_6.*0x2930' include/hw/pci/pci_ids.h || { echo "FATAL: SMBus revert failed"; exit 1; }
    grep -q 'PCI_DEVICE_ID_INTEL_82801IR.*0x2922' include/hw/pci/pci.h || { echo "FATAL: AHCI revert failed"; exit 1; }
    grep -q 'PCI_VENDOR_ID_INTEL' hw/isa/lpc_ich9.c || { echo "FATAL: LPC vendor revert failed"; exit 1; }
    grep -q 'PCI_VENDOR_ID_INTEL' hw/i2c/smbus_ich9.c || { echo "FATAL: SMBus vendor revert failed"; exit 1; }
    grep -q 'PCI_VENDOR_ID_INTEL' hw/ide/ich.c || { echo "FATAL: AHCI vendor revert failed"; exit 1; }
    grep -q 'PCI_DEVICE_ID_INTEL_82801IR' hw/ide/ich.c || { echo "FATAL: AHCI device_id revert failed"; exit 1; }

    # Revert AutoVirt's FADT C-state latency spoofing.
    # AutoVirt sets plvl2_lat=0x0065 and plvl3_lat=0x03e9 (1 above
    # the ACPI "not supported" threshold) to fool detection software.
    # Windows HAL interprets these boundary values as C2/C3-capable
    # and attempts power state transitions that hang under QEMU.
    sed -i 's/\.plvl2_lat = 0x0065/\.plvl2_lat = 0xfff/' hw/i386/acpi-build.c
    if ! grep -q '\.plvl2_lat = 0xfff' hw/i386/acpi-build.c; then
      echo "FATAL: FADT plvl2_lat revert to 0xfff failed"
      exit 1
    fi
    sed -i 's/\.plvl3_lat = 0x03e9/\.plvl3_lat = 0xfff/' hw/i386/acpi-build.c
    if ! grep -q '\.plvl3_lat = 0xfff' hw/i386/acpi-build.c; then
      echo "FATAL: FADT plvl3_lat revert to 0xfff failed"
      exit 1
    fi

    # Re-add WAET (Windows ACPI Emulation Table) removed by AutoVirt.
    # Without WAET, Windows uses slow timer workarounds (triple-read PM
    # timer, cli-bracketed RTC) that can stall HAL init under QEMU.
    sed -i '/\/\* Add tables supplied by user/i\    acpi_add_table(table_offsets, tables_blob);\n    build_waet(tables_blob, tables->linker, x86ms->oem_id, x86ms->oem_table_id);' hw/i386/acpi-build.c
    if ! grep -q 'build_waet' hw/i386/acpi-build.c; then
      echo "FATAL: WAET table re-addition failed"
      exit 1
    fi

    echo "=== Hardware identity customization complete ==="''
