{
  lib,
  patchAssertions,
  autovirtPatch,
  patchedOemId,
  patchedOemTableId,
  patchedHdaDevice,
  xhciRegisterWindow,
  edidManufacturer,
  edidSerial,
  edidSerialNumber,
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
  diskFirmware,
  opticalFirmware,
  pciSubsystem,
  hdaCodec,
  scsiVendor,
  scsiTargetProduct,
  smbiosChassisType,
  smbiosMemoryErrorCorrection,
  smbiosMemoryMaxCapacityGb,
  smbiosMemorySlots,
  smbiosMemoryType,
  smbiosMemoryTypeDetail,
  smbiosMemoryRank,
  smbiosMemoryVoltageMillivolts,
  deviceIdentities,
  acpiWaet,
  fadtC2Latency,
  fadtC3Latency,
}:

let
  subsystemVendor = lib.toLower (builtins.substring 0 4 pciSubsystem);
  subsystemDevice = lib.toLower (builtins.substring 5 4 pciSubsystem);
  codecId = lib.toLower (lib.replaceStrings [ ":" ] [ "" ] hdaCodec);
  opticalIdentity = builtins.match "([^ ]{1,8}) +([^ ].{0,15})" (lib.strings.trim opticalModel);
  opticalVendor = builtins.elemAt opticalIdentity 0;
  opticalProduct = builtins.elemAt opticalIdentity 1;
  firmwarePattern = "[A-Za-z0-9._-]{1,8}";
  scsiRevision = builtins.substring (lib.max 0 (
    builtins.stringLength diskFirmware - 4
  )) 4 diskFirmware;
  serialTemplate = identity: lib.fixedWidthString identity.serialLength "0" "";
  inherit (deviceIdentities)
    usbStorageBridge
    usbHub
    usbSerial
    usbBraille
    usbSmartcard
    usbFidoKey
    usbTablet
    usbAudio
    usbPhone
    vmgenidHardwareId
    megasas
    acpiCreator
    ;
  identitySchema = import ./device-identity-schema.nix;
  fits =
    kind: value:
    if kind ? pattern then
      builtins.isString value && builtins.match kind.pattern value != null
    else
      builtins.isInt value && value >= kind.min && value <= kind.max;
  misfit =
    path: kind: value:
    lib.optional (
      !fits kind value
    ) "deviceIdentities.${path} must be ${kind.form}; got ${builtins.toJSON value}";
  identityProblems = lib.concatLists (
    lib.mapAttrsToList (
      name: spec:
      if spec ? form then
        misfit name spec (lib.attrByPath [ name ] null deviceIdentities)
      else
        lib.concatLists (
          lib.mapAttrsToList (
            field: kind: misfit "${name}.${field}" kind (lib.attrByPath [ name field ] null deviceIdentities)
          ) spec
        )
    ) identitySchema
  );
  octal = n: lib.fixedWidthString 3 "0" (lib.concatMapStrings toString (lib.toBaseDigits 8 n));
  acpiCreatorBytes =
    acpiCreator.id
    + lib.concatMapStrings (place: "\\${octal (builtins.bitAnd (acpiCreator.revision / place) 255)}") [
      1
      256
      65536
      16777216
    ];
  memoryTypeCode = (import ../smbios/memory-types.nix).${smbiosMemoryType};
  memoryVoltage = if smbiosMemoryVoltageMillivolts == null then 0 else smbiosMemoryVoltageMillivolts;
  dimmDataWidth = 64;
  memoryTotalWidth = dimmDataWidth + (if smbiosMemoryErrorCorrection >= 4 then 8 else 0);
  hex = n: "0x${lib.toLower (lib.toHexString n)}";
  chassisType = "0x${lib.fixedWidthString 2 "0" (lib.toLower (lib.toHexString smbiosChassisType))}";
  memoryErrorCorrection = "0x${
    lib.fixedWidthString 2 "0" (lib.toHexString smbiosMemoryErrorCorrection)
  }";
  slotTextPattern = "[A-Za-z0-9 _./#:-]{1,64}";
  memoryModules = lib.length (lib.filter (slot: slot.populated) smbiosMemorySlots);
  lastSlot = lib.last smbiosMemorySlots;
  slotLine =
    slot:
    "    { \"${slot.locator}\", \"${slot.bank}\", ${lib.boolToString slot.populated}, ${
          if slot.serial == null then "NULL" else "\"${slot.serial}\""
        } },";
  memorySlotTable = lib.concatStringsSep "\n" (
    [
      "#define SMBIOS_MEMORY_MAX_CAPACITY (${toString smbiosMemoryMaxCapacityGb}ULL * GiB)"
      "#define SMBIOS_MEMORY_MODULES ${toString memoryModules}"
      "#define SMBIOS_MEMORY_TYPE ${hex memoryTypeCode}"
      "#define SMBIOS_MEMORY_TYPE_DETAIL ${hex smbiosMemoryTypeDetail}"
      "#define SMBIOS_MEMORY_RANK ${toString smbiosMemoryRank}"
      "#define SMBIOS_MEMORY_VOLTAGE_MV ${toString memoryVoltage}"
      "#define SMBIOS_MEMORY_DATA_WIDTH ${toString dimmDataWidth}"
      "#define SMBIOS_MEMORY_TOTAL_WIDTH ${toString memoryTotalWidth}"
      "static const struct {"
      "    const char *locator;"
      "    const char *bank;"
      "    bool populated;"
      "    const char *serial;"
      "} smbios_memory_slots[] = {"
    ]
    ++ map slotLine smbiosMemorySlots
    ++ [ "};" ]
  );
  stringlessTablesRule = "if ((smbios_have_defaults || type == 16 || type == 19 || type == 32 || type == 127) && required_table) {";
  inWord = n: builtins.isInt n && n >= 0 && n <= 65535;
  waetEdit =
    if acpiWaet then
      ''
        # why: without WAET Windows falls back to slow timer workarounds that can stall HAL init
        exactly_one hw/i386/acpi-build.c 'Add tables supplied by user' "one anchor for the WAET insertion"
        sed -i '/\/\* Add tables supplied by user/i\    acpi_add_table(table_offsets, tables_blob);\n    build_waet(tables_blob, tables->linker, x86ms->oem_id, x86ms->oem_table_id);' hw/i386/acpi-build.c
        exactly_one hw/i386/acpi-build.c '^ +build_waet\(tables_blob, tables->linker' "the WAET table added back exactly once"

      ''
    else
      ''
        gone hw/i386/acpi-build.c 'build_waet(tables_blob' "no WAET table, which only a virtual machine carries"

      '';
  hdaControllerRevert = lib.optionalString (patchedHdaDevice != null) ''
    # why: AutoVirt gives the HD Audio controller a ${patchedHdaDevice} id, which drivers take for a controller with capabilities QEMU's ICH6 and ICH9 models lack, so a Linux guest finds no codec; the ICH9 board gets the ICH6 and ICH9 controllers' own ids back
    sed -i -e '/^static void intel_hda_class_init_ich6(/,/^}/{s|k->device_id = ${patchedHdaDevice};.*$|k->device_id = 0x2668;|;s|k->revision = 0;|k->revision = 1;|}' \
      -e '/^static void intel_hda_class_init_ich9(/,/^}/{s|k->device_id = ${patchedHdaDevice};.*$|k->device_id = 0x293e;|;s|k->revision = 0;|k->revision = 3;|}' hw/audio/intel-hda.c
    gone hw/audio/intel-hda.c 'k->device_id = ${patchedHdaDevice};' "no HD Audio controller keeps the ${patchedHdaDevice} id"
    landed hw/audio/intel-hda.c 'k->device_id = 0x293e;' "the ICH9 HD Audio controller has its own id"
    landed hw/audio/intel-hda.c 'k->device_id = 0x2668;' "the ICH6 HD Audio controller has its own id"

  '';
  xhciWindow = ''
    # why: for the Intel PCH id AutoVirt gives QEMU's xHCI, Windows' USBXHCI.SYS reads registers past QEMU's 16 KB window and stops with PAGE_FAULT_IN_NONPAGED_AREA, and Intel's PCH controllers decode 64 KB
    exactly_one include/hw/usb/xhci.h '^#define XHCI_LEN_REGS 0x4000$' "one xHCI register window size"
    sed -i 's|^#define XHCI_LEN_REGS 0x4000$|#define XHCI_LEN_REGS ${xhciRegisterWindow}|' include/hw/usb/xhci.h
    landed include/hw/usb/xhci.h '#define XHCI_LEN_REGS ${xhciRegisterWindow}' "the xHCI decodes ${xhciRegisterWindow} bytes"

  '';
in
assert lib.assertMsg
  (
    builtins.match "[0-9a-fA-F]{4}:[0-9a-fA-F]{4}" pciSubsystem != null
    && (builtins.fromTOML "v = 0x${subsystemDevice}").v >= 64
  )
  "pciSubsystem must be vendor:device in hex with a device id of 0040 or more, which the virtio spec asks of modern devices and OVMF's virtio driver enforces; got '${pciSubsystem}'";
assert lib.assertMsg (builtins.match "[0-9a-fA-F]{4}:[0-9a-fA-F]{4}" hdaCodec != null)
  "hdaCodec must be vendor:device in hex, as `cat /proc/asound/card*/codec#*` shows a codec's Vendor Id; got '${hdaCodec}'";
assert lib.assertMsg (opticalIdentity != null)
  "opticalModel must be a vendor of at most 8 characters, a space, then a product of at most 16 characters, as a real drive answers SCSI INQUIRY; got '${opticalModel}'";
assert lib.assertMsg (
  builtins.match firmwarePattern diskFirmware != null
) "diskFirmware must be 1 to 8 letters, digits, dots, dashes or underscores; got '${diskFirmware}'";
assert lib.assertMsg (builtins.match firmwarePattern opticalFirmware != null)
  "opticalFirmware must be 1 to 8 letters, digits, dots, dashes or underscores; got '${opticalFirmware}'";
assert lib.assertMsg
  (
    builtins.match "[A-Za-z0-9 _.-]{6}" acpiOemId != null
    && builtins.match "[A-Za-z0-9 _.-]{8}" acpiOemTableId != null
  )
  "acpiOemId must be 6 and acpiOemTableId 8 letters, digits, spaces, dots, dashes or underscores, the widths of their ACPI header fields; got '${acpiOemId}' and '${acpiOemTableId}'";
assert lib.assertMsg
  (builtins.isInt smbiosChassisType && smbiosChassisType >= 1 && smbiosChassisType <= 36)
  "smbiosChassisType must be an SMBIOS 3.x chassis type from 1 to 36; got '${toString smbiosChassisType}'";
assert lib.assertMsg
  (
    builtins.isInt smbiosMemoryErrorCorrection
    && smbiosMemoryErrorCorrection >= 1
    && smbiosMemoryErrorCorrection <= 7
  )
  "smbiosMemoryErrorCorrection must be an SMBIOS type 16 error correction from 1 to 7; got '${toString smbiosMemoryErrorCorrection}'";
assert lib.assertMsg (builtins.isInt smbiosMemoryMaxCapacityGb && smbiosMemoryMaxCapacityGb >= 1)
  "smbiosMemoryMaxCapacityGb must be a whole number of GB, 1 or more; got '${toString smbiosMemoryMaxCapacityGb}'";
assert lib.assertMsg
  (
    builtins.isList smbiosMemorySlots
    && smbiosMemorySlots != [ ]
    && lib.all (
      slot:
      builtins.match slotTextPattern slot.locator != null
      && builtins.match slotTextPattern slot.bank != null
      && builtins.isBool slot.populated
      && (slot.serial == null || builtins.match "[A-Za-z0-9]{1,32}" slot.serial != null)
    ) smbiosMemorySlots
    && memoryModules >= 1
  )
  "smbiosMemorySlots must list each DIMM slot as { locator; bank; populated; serial; }, with locator and bank 1 to 64 letters, digits, spaces or any of _./#:-, serial null or 1 to 32 letters and digits, and at least one slot populated; got ${builtins.toJSON smbiosMemorySlots}";
assert lib.assertMsg
  (builtins.isInt edidSerialNumber && edidSerialNumber >= 0 && edidSerialNumber <= 4294967295)
  "edidSerialNumber must fit the EDID's 32-bit serial number, 0 to 4294967295; got '${toString edidSerialNumber}'";
assert lib.assertMsg (builtins.isBool acpiWaet) "acpiWaet must be true or false";
assert lib.assertMsg (inWord fadtC2Latency && inWord fadtC3Latency)
  "fadtC2Latency and fadtC3Latency must each fit the FADT's 16-bit field, 0 to 65535; got '${toString fadtC2Latency}' and '${toString fadtC3Latency}'";
assert lib.assertMsg (identityProblems == [ ]) (lib.concatStringsSep "; " identityProblems);
assert lib.assertMsg (builtins.hasAttr smbiosMemoryType (import ../smbios/memory-types.nix))
  "smbiosMemoryType must be a DSP0134 memory type named in smbios/memory-types.nix, such as DDR5; got '${toString smbiosMemoryType}'";
assert lib.assertMsg (inWord smbiosMemoryTypeDetail)
  "smbiosMemoryTypeDetail must be the 16-bit DSP0134 type detail bit field; got '${toString smbiosMemoryTypeDetail}'";
assert lib.assertMsg
  (builtins.isInt smbiosMemoryRank && smbiosMemoryRank >= 1 && smbiosMemoryRank <= 15)
  "smbiosMemoryRank must be 1 to 15, the rank nibble of SMBIOS type 17; got '${toString smbiosMemoryRank}'";
assert lib.assertMsg
  (
    smbiosMemoryVoltageMillivolts == null
    || (inWord smbiosMemoryVoltageMillivolts && smbiosMemoryVoltageMillivolts >= 1)
  )
  "smbiosMemoryVoltageMillivolts must be null or 1 to 65535 millivolts; got '${toString smbiosMemoryVoltageMillivolts}'";
''
  ${patchAssertions}
  echo "=== Applying AutoVirt QEMU patch: $(basename ${autovirtPatch}) ==="
    # why: a hunk that needs fuzz may land in the wrong place and yield a detectable or unbootable emulator
    patch -p1 -F0 -i ${autovirtPatch} || {
      echo "FATAL: AutoVirt QEMU patch did not apply with zero fuzz"
      exit 1
    }

    sed -i 's|aml_string(win_osi\[n\].osi)|aml_string("%s", win_osi[n].osi)|' hw/i386/acpi-build.c
    if grep -q 'aml_string(win_osi\[n\]\.osi)' hw/i386/acpi-build.c; then
      echo "FATAL: AutoVirt _OSI loop still passes a non-literal format to aml_string"
      exit 1
    fi

    echo "=== Customizing hardware identifiers ==="

    # why: QEMU names Hyper-V build 14393 in CPUID 0x40000002 but answers 0x40000005 with 0xFFFFFFFF virtual and 64 logical processors, which no Hyper-V host reports; a build 14393 host reports 0x140, 0x200 and 0x25B0
    substituteInPlace target/i386/cpu.c \
      --replace-fail 'DEFINE_PROP_INT32("x-hv-max-vps", X86CPU, hv_max_vps, -1),' 'DEFINE_PROP_INT32("x-hv-max-vps", X86CPU, hv_max_vps, 0x140),' \
      --replace-fail 'cpu->hyperv_limits[0] = 64;' 'cpu->hyperv_limits[0] = 0x200;' \
      --replace-fail 'cpu->hyperv_limits[1] = 0;' 'cpu->hyperv_limits[1] = 0x25B0;'
    landed target/i386/cpu.c 'hv_max_vps, 0x140),' "Hyper-V reports 0x140 virtual processors in CPUID 0x40000005"
    landed target/i386/cpu.c 'cpu->hyperv_limits[0] = 0x200;' "Hyper-V reports 0x200 logical processors in CPUID 0x40000005"

    # why: a PNP0A06 container's _UID becomes its Windows instance id, and QEMU's say CPU Hotplug, SMI, PCI Hotplug, Memory hotplug and DIMM devices; AutoVirt already numbers the GPE0 one 0
    substituteInPlace hw/acpi/cpu.c --replace-fail 'aml_string("CPU Hotplug resources")' 'aml_int(1)'
    substituteInPlace hw/i386/acpi-build.c --replace-fail 'aml_string("SMI resources")' 'aml_int(2)'
    substituteInPlace hw/acpi/pcihp.c --replace-fail 'aml_string("PCI Hotplug resources")' 'aml_int(3)'
    substituteInPlace hw/acpi/memory_hotplug.c \
      --replace-fail 'aml_string("Memory hotplug resources")' 'aml_int(4)' \
      --replace-fail 'aml_string("DIMM devices")' 'aml_int(5)'
    gone hw/i386/acpi-build.c 'aml_string("GPE0 resources")' "AutoVirt numbers the GPE0 container"
    for f in hw/acpi/cpu.c hw/i386/acpi-build.c hw/acpi/pcihp.c hw/acpi/memory_hotplug.c; do
      gone "$f" ' resources")' "no ACPI container in $f keeps a descriptive _UID"
    done

    # why: AMI firmware names the PIC and APIC routing tables PR00 and AR00; QEMU's PRTP and PRTA, equally long, are what VMAware's FIRMWARE check reads as QEMU
    substituteInPlace hw/i386/acpi-build.c \
      --replace-fail 'aml_name_decl("PRTP"' 'aml_name_decl("PR00"' \
      --replace-fail 'aml_name_decl("PRTA"' 'aml_name_decl("AR00"' \
      --replace-fail 'aml_return(aml_name("PRTP"))' 'aml_return(aml_name("PR00"))' \
      --replace-fail 'aml_return(aml_name("PRTA"))' 'aml_return(aml_name("AR00"))'
    gone hw/i386/acpi-build.c '"PRTP"' "no PCI routing table keeps QEMU's PRTP name"
    gone hw/i386/acpi-build.c '"PRTA"' "no PCI routing table keeps QEMU's PRTA name"
    landed hw/i386/acpi-build.c 'aml_return(aml_name("AR00"))' "_PRT returns AR00 in APIC mode"

    # why: real firmware routes APIC mode straight to GSI 16 to 23 in its routing table; QEMU's GSIA to GSIH link devices beside LNKE to LNKH are what VMAware's FIRMWARE check reads as QEMU
    patch -p1 -F0 --no-backup-if-mismatch -i ${./q35-direct-gsi.patch} || {
      echo "FATAL: qemu/q35-direct-gsi.patch did not apply with zero fuzz"
      exit 1
    }
    gone hw/i386/acpi-build.c 'build_gsi_link_dev' "no GSI link device is built"
    landed hw/i386/acpi-build.c 'aml_append(pkg, aml_int(0x10 + s[3] - '"'"'A'"'"'));' "APIC mode routes each pin straight to its GSI"

    # why: an AMI HPET reports itself present; QEMU's _STA rejects a period of zero or above 100000000, the exact check VMAware's FIRMWARE scan reads as QEMU
    patch -p1 -F0 --no-backup-if-mismatch -i ${./hpet-sta.patch} || {
      echo "FATAL: qemu/hpet-sta.patch did not apply with zero fuzz"
      exit 1
    }
    gone hw/i386/acpi-build.c 'aml_lgreater(period, aml_int(100000000))' "the HPET _STA has no period check"

    # why: AutoVirt renamed QEMU's GPE0 container GPER, a name VMAware's FIRMWARE check reads as QEMU beside PNP0A06
    substituteInPlace hw/i386/acpi-build.c --replace-fail 'aml_device("GPER")' 'aml_device("GPEB")'
    gone hw/i386/acpi-build.c '"GPER"' "no ACPI device keeps the GPER name"

    # why: KVM's hypercall-patching quirk rewrites a guest's VMCALL or VMMCALL into the host vendor's instruction in the guest's own code page, which a user-mode caller sees as an access violation in place of the #UD real hardware raises
    patch -p1 -F0 --no-backup-if-mismatch -i ${./kvm-hypercall-quirk.patch} || {
      echo "FATAL: qemu/kvm-hypercall-quirk.patch did not apply with zero fuzz"
      exit 1
    }
    landed target/i386/kvm/kvm.c 'uint64_t quirks = KVM_X86_QUIRK_FIX_HYPERCALL_INSN;' "QEMU disables KVM's hypercall-patching quirk"

    substituteInPlace hw/display/edid-generate.c \
      --replace-fail '"RHT"' '"${edidManufacturer}"'
    substituteInPlace hw/display/edid-generate.c \
      --replace-fail '"QEMU Monitor"' '"${edidSerial}"'
    substituteInPlace hw/display/edid-generate.c \
      --replace-fail 'uint32_t serial_nr = info->serial ? atoi(info->serial) : 0;' 'uint32_t serial_nr = info->serial ? atoi(info->serial) : ${toString edidSerialNumber}U;'
    landed hw/display/edid-generate.c 'atoi(info->serial) : ${toString edidSerialNumber}U;' "the EDID serial number is edidSerialNumber"
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

    substituteInPlace hw/scsi/scsi-bus.c \
      --replace-fail '"QEMU    "' '"${builtins.substring 0 8 (scsiVendor + "        ")}"'
    substituteInPlace hw/scsi/scsi-bus.c \
      --replace-fail '"QEMU TARGET     "' '"${scsiTargetProduct}"'

    substituteInPlace hw/scsi/scsi-disk.c \
      --replace-fail '"QEMU HARDDISK"' '"${diskModel}"'
    substituteInPlace hw/scsi/scsi-disk.c \
      --replace-fail '"QEMU CD-ROM"' '"${opticalModel}"'
    substituteInPlace hw/scsi/scsi-disk.c \
      --replace-fail '"QEMU"' '"${scsiVendor}"'

    sed -i 's|"${patchedOemId}"|"${acpiOemId}"|g' include/hw/acpi/aml-build.h
    if ! grep -q '"${acpiOemId}"' include/hw/acpi/aml-build.h; then
      echo "FATAL: ACPI OEM ID replacement to ${acpiOemId} did not apply"
      exit 1
    fi
    sed -i 's|"${patchedOemTableId}"|"${acpiOemTableId}"|g' include/hw/acpi/aml-build.h
    if ! grep -q '"${acpiOemTableId}"' include/hw/acpi/aml-build.h; then
      echo "FATAL: ACPI OEM Table ID replacement did not apply"
      exit 1
    fi

    substituteInPlace hw/ide/core.c \
      --replace-fail 'Samsung SSD 980 500GB' '${diskModel}'
    substituteInPlace hw/ide/core.c \
      --replace-fail 'Hitachi HMS360404D5CF00' '${diskModel}'
    sed -i "s|s->drive_serial_str\[0\] = '\\\\0';|pstrcpy(s->drive_serial_str, sizeof(s->drive_serial_str), \"${diskSerial}\");|g" hw/ide/core.c
    landed hw/ide/core.c "pstrcpy(s->drive_serial_str, sizeof(s->drive_serial_str), \"${diskSerial}\");" "IDE serial set to diskSerial"
    gone hw/ide/core.c "s->drive_serial_str[0] = '\\0';" "AutoVirt's blank IDE serial replaced"
    substituteInPlace hw/ide/core.c \
      --replace-fail 'HL-DT-ST BD-RE WH16NS60' '${opticalModel}'
    substituteInPlace hw/smbios/smbios.c \
      --replace-fail 't->bios_characteristics = cpu_to_le64(0x08); /* Not supported */' 't->bios_characteristics = cpu_to_le64(0x7c0b9880);' \
      --replace-fail 't->bios_characteristics_extension_bytes[0] = 0;' 't->bios_characteristics_extension_bytes[0] = 0x03;' \
      --replace-fail 't->bios_characteristics_extension_bytes[1] = 0x04; /* TCD/SVVP */' 't->bios_characteristics_extension_bytes[1] = 0x05;' \
      --replace-fail 'smbios_type0.uefi = qemu_opt_get_bool(opts, "uefi", false);' 'smbios_type0.uefi = qemu_opt_get_bool(opts, "uefi", true);' \
      --replace-fail 'smbios_type0.vm = qemu_opt_get_bool(opts, "vm", true);' 'smbios_type0.vm = qemu_opt_get_bool(opts, "vm", false);'
    # why: QEMU's -smbios type=3 has no chassis type field, and the type 1 it writes, Other, is what VMAware's CTYPE check flags
    exactly_one hw/smbios/smbios.c '^ +t->type = 0x01; /\* Other \*/$' "one SMBIOS chassis type to set"
    substituteInPlace hw/smbios/smbios.c \
      --replace-fail 't->type = 0x01; /* Other */' 't->type = ${chassisType};'
    exactly_one hw/smbios/smbios.c '^ +t->type = ${chassisType};$' "the SMBIOS chassis is type ${toString smbiosChassisType}"
    gone hw/smbios/smbios.c 't->type = 0x01; /* Other */' "no SMBIOS chassis is type 1, Other"
    # why: AutoVirt turns QEMU's SMBIOS defaults off, which drops every required table: OVMF reads QEMU's tables until it meets type 127 with no bound, so it installs whatever memory follows them, and type 17 names a memory array, type 16, that is not there; the required tables that carry no string cannot name QEMU
    exactly_one hw/smbios/smbios.c '^ +if \(smbios_have_defaults && required_table\) \{$' "one rule deciding which required SMBIOS tables QEMU builds"
    substituteInPlace hw/smbios/smbios.c \
      --replace-fail 'if (smbios_have_defaults && required_table) {' '${stringlessTablesRule}'
    landed hw/smbios/smbios.c '${stringlessTablesRule}' "QEMU builds the memory array, its address map, the boot status and the end-of-table without its defaults"
    # why: QEMU describes a memory array as large as the VM's memory with one device per machine-type chunk, where a board reports its maximum, every slot with its own locator, and the empty ones as no module installed
    patch -p1 -F0 --no-backup-if-mismatch -i ${./smbios-memory-slots.patch}
    exactly_one hw/smbios/smbios.c '^@smbiosMemorySlots@$' "one place for the board's memory slot table"
    substituteInPlace hw/smbios/smbios.c \
      --replace-fail '@smbiosMemorySlots@' ${lib.escapeShellArg memorySlotTable}
    gone hw/smbios/smbios.c '@smbiosMemorySlots@' "the memory slot table placeholder is filled"
    landed hw/smbios/smbios.c '#define SMBIOS_MEMORY_MAX_CAPACITY (${toString smbiosMemoryMaxCapacityGb}ULL * GiB)' "the SMBIOS memory array reports a maximum of ${toString smbiosMemoryMaxCapacityGb} GB"
    landed hw/smbios/smbios.c '#define SMBIOS_MEMORY_MODULES ${toString memoryModules}' "the VM's memory is split over ${toString memoryModules} modules"
    landed hw/smbios/smbios.c ${lib.escapeShellArg (slotLine lastSlot)} "the last of ${toString (lib.length smbiosMemorySlots)} memory slots is ${lastSlot.locator} in ${lastSlot.bank}"
    exactly_one hw/smbios/smbios.c '^ +smbios_build_type_16_table\(dimm_cnt, SMBIOS_MEMORY_MAX_CAPACITY\);$' "the memory array counts every slot and reports the board's maximum"
    exactly_one hw/smbios/smbios.c '^ +t->partition_width = SMBIOS_MEMORY_MODULES;$' "the memory address map interleaves the populated modules"
    gone hw/smbios/smbios.c 'GET_DIMM_SZ' "no memory device follows the machine type's device size"
    gone hw/smbios/smbios.c 'type17.loc_pfx, instance' "no memory device locator is QEMU's prefix and index"
    # why: QEMU's memory array sits in Other with multi-bit ECC, where a desktop board's sits on the system board with the error correction of its DIMMs
    exactly_one hw/smbios/smbios.c '^ +t->location = 0x01; /\* Other \*/$' "one SMBIOS memory array location to set"
    exactly_one hw/smbios/smbios.c '^ +t->error_correction = 0x06; ' "one SMBIOS memory array error correction to set"
    sed -i -e 's|^\( *\)t->location = 0x01; /\* Other \*/$|\1t->location = 0x03;|' \
      -e 's|^\( *\)t->error_correction = 0x06; .*$|\1t->error_correction = ${memoryErrorCorrection};|' hw/smbios/smbios.c
    landed hw/smbios/smbios.c 't->location = 0x03;' "the SMBIOS memory array sits on the system board"
    landed hw/smbios/smbios.c 't->error_correction = ${memoryErrorCorrection};' "the SMBIOS memory array reports error correction ${toString smbiosMemoryErrorCorrection}"
    gone hw/smbios/smbios.c 'Multi-bit ECC (for Microsoft' "no SMBIOS memory array keeps QEMU's multi-bit ECC"
    # why: QEMU numbers type 8 from type 0's handle, and OVMF refuses a structure whose handle is taken, so the port connectors never reach the guest
    exactly_one hw/smbios/smbios.c 'SMBIOS_BUILD_TABLE_PRE\(8, T0_BASE \+ instance, true\);' "one SMBIOS type 8 handle base to move"
    substituteInPlace hw/smbios/smbios.c \
      --replace-fail 'SMBIOS_BUILD_TABLE_PRE(8, T0_BASE + instance, true);' 'SMBIOS_BUILD_TABLE_PRE(8, 0x800 + instance, true);'
    gone hw/smbios/smbios.c 'SMBIOS_BUILD_TABLE_PRE(8, T0_BASE' "no SMBIOS type 8 structure shares type 0's handle"
    # why: QEMU leaves type 4 without voltage, clock, upgrade, characteristics and cache links, numbers a single socket, names no version without -smbios version, gives type 8 no internal connector and type 9 a one-byte segment, where a board fills them all
    patch -p1 -F0 --no-backup-if-mismatch -i ${./smbios-board-fields.patch}
    exactly_one hw/smbios/smbios.c '^ +\.name = "l3-cache-handle",$' "-smbios type=4 takes the cache handles"
    exactly_one hw/smbios/smbios.c '^ +\.name = "internal_connector_type",$' "-smbios type=8 takes the internal connector type"
    landed hw/smbios/smbios.c 't->voltage = type4.voltage;' "type 4 reports the voltage it is given"
    landed hw/smbios/smbios.c 't->external_clock = cpu_to_le16(type4.external_clock);' "type 4 reports the external clock it is given"
    landed hw/smbios/smbios.c 't->processor_upgrade = type4.upgrade;' "type 4 reports the socket upgrade it is given"
    landed hw/smbios/smbios.c 't->processor_characteristics = cpu_to_le16(type4.characteristics);' "type 4 reports the characteristics it is given"
    landed hw/smbios/smbios.c 't->l3_cache_handle = cpu_to_le16(type4.l3_cache_handle);' "type 4 links the cache tables it is given"
    landed hw/smbios/smbios.c 'snprintf(sock_str, sizeof(sock_str), "%s", type4.sock_pfx);' "a single socket is named as given, without an instance number"
    landed hw/smbios/smbios.c 'model_id = object_property_get_str(OBJECT(first_cpu), "model-id", NULL);' "type 4 names the CPU model the guest sees when no version is given"
    landed hw/smbios/smbios.c 't->internal_connector_type = t8->internal_connector_type;' "type 8 reports the internal connector it is given"
    gone hw/smbios/smbios.c 'cpu_to_le16(0xFFFF); /* N/A */' "no type 4 cache handle is fixed at not provided"
    gone hw/smbios/smbios.c 't->processor_family = 0xfe;' "type 4 keeps a family below 0xfe in its family byte, as a board does"
    gone hw/smbios/smbios.c 't->segment_group_number = 0xff;' "a slot without a PCI device has no bus address, not segment 0x00ff"
    exactly_one hw/smbios/smbios.c '^ +t->memory_type = size \? SMBIOS_MEMORY_TYPE : 0x02;$' "a populated memory device reports smbios.memory.type"
    landed hw/smbios/smbios.c '#define SMBIOS_MEMORY_TYPE ${hex memoryTypeCode}' "the memory devices are ${smbiosMemoryType}"
    landed hw/smbios/smbios.c '#define SMBIOS_MEMORY_TYPE_DETAIL ${hex smbiosMemoryTypeDetail}' "the memory devices report type detail ${hex smbiosMemoryTypeDetail}"
    landed hw/smbios/smbios.c '#define SMBIOS_MEMORY_RANK ${toString smbiosMemoryRank}' "the memory devices are rank ${toString smbiosMemoryRank}"
    landed hw/smbios/smbios.c '#define SMBIOS_MEMORY_VOLTAGE_MV ${toString memoryVoltage}' "the memory devices report ${toString memoryVoltage} mV"
    landed hw/smbios/smbios.c '#define SMBIOS_MEMORY_TOTAL_WIDTH ${toString memoryTotalWidth}' "the memory devices are ${toString memoryTotalWidth} bits wide with their error correction bits"
    gone hw/smbios/smbios.c 't->memory_type = size ? 0x07' "no populated memory device is plain RAM"
    substituteInPlace hw/core/qdev.c \
      --replace-fail 'dc->hotpluggable = false;' 'dc->hotpluggable = true;'
    gone hw/core/qdev.c 'dc->hotpluggable = false;' "devices are hotpluggable again, or a USB device cannot be plugged into a running VM"
    substituteInPlace hw/nvram/fw_cfg.c \
      --replace-fail 'fw_cfg_add_bytes(s, FW_CFG_SIGNATURE, (char *)"QEMU", 4); // "QEMU"' 'fw_cfg_add_bytes(s, FW_CFG_SIGNATURE, (char *)"\xff\xff\xff\xff", 4);'
    gone hw/nvram/fw_cfg.c '(char *)"QEMU", 4)' "the fw_cfg port no longer answers QEMU; ovmf/post-patch.nix expects the same 0xff signature"
    substituteInPlace hw/nvme/ctrl.c \
      --replace-fail '"NVMe Ctrl"' '"${lib.strings.trim diskModel}"' \
      --replace-fail 'n->params.firmware_version ? n->params.firmware_version : QEMU_VERSION' 'n->params.firmware_version ? n->params.firmware_version : "${diskFirmware}"'
    gone hw/nvme/ctrl.c 'n->params.firmware_version : QEMU_VERSION' "an NVMe drive with no firmware-version reports diskFirmware, not QEMU's version"
    substituteInPlace hw/ide/atapi.c \
      --replace-fail 'padstr8(buf + 8, 8, "Samsung");' 'padstr8(buf + 8, 8, "${opticalVendor}");' \
      --replace-fail 'padstr8(buf + 16, 16, "DVD-ROM");' 'padstr8(buf + 16, 16, "${opticalProduct}");'
    substituteInPlace hw/ide/core.c \
      --replace-fail 'pstrcpy(s->version, sizeof(s->version), QEMU_HW_VERSION);' 'pstrcpy(s->version, sizeof(s->version), kind == IDE_CD ? "${opticalFirmware}" : "${diskFirmware}");'
    substituteInPlace hw/scsi/scsi-disk.c \
      --replace-fail 's->version = g_strdup(QEMU_HW_VERSION);' 's->version = g_strdup(dev->type == TYPE_ROM ? "${opticalFirmware}" : "${scsiRevision}");'
    substituteInPlace hw/scsi/scsi-bus.c \
      --replace-fail 'pstrcpy((char *) &r->buf[32], 4, QEMU_HW_VERSION);' 'pstrcpy((char *) &r->buf[32], 4, "${scsiRevision}");'

    # why: AMD FCH IDs on Q35 send the AMD GPU driver down an FCH code path that BSODs with 0x113
    sed -i 's/define PCI_DEVICE_ID_INTEL_P35_MCH.*$/define PCI_DEVICE_ID_INTEL_P35_MCH      0x29c0/' \
      include/hw/pci/pci_ids.h
    sed -i 's|k->vendor_id = PCI_VENDOR_ID_AMD;|k->vendor_id = PCI_VENDOR_ID_INTEL;|' hw/pci-host/q35.c
    sed -i 's/^#define ICH9_A2_LPC_REVISION[[:space:]].*/#define ICH9_A2_LPC_REVISION                    0x2/' \
      include/hw/southbridge/ich9.h
    sed -i 's/^#define ICH9_A2_SMB_REVISION[[:space:]].*/#define ICH9_A2_SMB_REVISION                    0x02/' \
      include/hw/southbridge/ich9.h

    sed -i 's/define PCI_DEVICE_ID_INTEL_ICH9_8.*$/define PCI_DEVICE_ID_INTEL_ICH9_8       0x2918/' include/hw/pci/pci_ids.h
    sed -i 's|k->vendor_id = PCI_VENDOR_ID_AMD;|k->vendor_id = PCI_VENDOR_ID_INTEL;|' hw/isa/lpc_ich9.c

    sed -i 's/define PCI_DEVICE_ID_INTEL_ICH9_6.*$/define PCI_DEVICE_ID_INTEL_ICH9_6       0x2930/' include/hw/pci/pci_ids.h
    sed -i 's|k->vendor_id = PCI_VENDOR_ID_AMD;|k->vendor_id = PCI_VENDOR_ID_INTEL;|' hw/i2c/smbus_ich9.c

    sed -i 's/define PCI_DEVICE_ID_INTEL_82801IR.*$/define PCI_DEVICE_ID_INTEL_82801IR      0x2922/' include/hw/pci/pci.h
    sed -i 's|k->vendor_id = PCI_VENDOR_ID_AMD;|k->vendor_id = PCI_VENDOR_ID_INTEL;|' hw/ide/ich.c
    sed -i 's|k->device_id = PCI_DEVICE_ID_AMD_SATA;|k->device_id = PCI_DEVICE_ID_INTEL_82801IR;|' hw/ide/ich.c

    grep -q 'PCI_DEVICE_ID_INTEL_P35_MCH.*0x29c0' include/hw/pci/pci_ids.h || { echo "FATAL: MCH revert failed"; exit 1; }
    grep -q 'PCI_DEVICE_ID_INTEL_ICH9_8.*0x2918' include/hw/pci/pci_ids.h || { echo "FATAL: LPC revert failed"; exit 1; }
    grep -q 'PCI_DEVICE_ID_INTEL_ICH9_6.*0x2930' include/hw/pci/pci_ids.h || { echo "FATAL: SMBus revert failed"; exit 1; }
    grep -q 'PCI_DEVICE_ID_INTEL_82801IR.*0x2922' include/hw/pci/pci.h || { echo "FATAL: AHCI revert failed"; exit 1; }
    for f in hw/pci-host/q35.c hw/isa/lpc_ich9.c hw/i2c/smbus_ich9.c hw/ide/ich.c; do
      if grep -qF 'k->vendor_id = PCI_VENDOR_ID_AMD;' "$f"; then
        echo "FATAL: $f still sets the AMD vendor on an Intel device ID"
        exit 1
      fi
    done
    grep -qE '^#define ICH9_A2_LPC_REVISION[[:space:]]+0x2$' include/hw/southbridge/ich9.h || { echo "FATAL: LPC revision revert to 0x2 failed"; exit 1; }
    grep -qE '^#define ICH9_A2_SMB_REVISION[[:space:]]+0x02$' include/hw/southbridge/ich9.h || { echo "FATAL: SMBus revision revert to 0x02 failed"; exit 1; }
    grep -q 'PCI_DEVICE_ID_INTEL_82801IR' hw/ide/ich.c || { echo "FATAL: AHCI device_id revert failed"; exit 1; }

    # why: OVMF probes the PM base at 0x1f:0, so LPC must stay there or the firmware hangs before any output
    sed -i 's/^#define ICH9_LPC_DEV[[:space:]].*/#define ICH9_LPC_DEV                            31/' \
      include/hw/southbridge/ich9.h
    sed -i 's/^#define ICH9_LPC_FUNC[[:space:]].*/#define ICH9_LPC_FUNC                           0/' \
      include/hw/southbridge/ich9.h
    if ! grep -qE '^#define ICH9_LPC_DEV[[:space:]]+31$' include/hw/southbridge/ich9.h; then
      echo "FATAL: ICH9 LPC device revert to 31 (stock Q35 0x1f) failed"
      exit 1
    fi
    if ! grep -qE '^#define ICH9_LPC_FUNC[[:space:]]+0$' include/hw/southbridge/ich9.h; then
      echo "FATAL: ICH9 LPC function revert to 0 failed"
      exit 1
    fi
    sed -i 's/^#define ICH9_SATA1_DEV[[:space:]].*/#define ICH9_SATA1_DEV                          31/' \
      include/hw/southbridge/ich9.h
    if ! grep -qE '^#define ICH9_SATA1_DEV[[:space:]]+31$' include/hw/southbridge/ich9.h; then
      echo "FATAL: ICH9 SATA device revert to 31 failed: at 0x14 it has no function 0 beside it, so firmware never enumerates it and finds no SATA disk"
      exit 1
    fi
    sed -i 's/^#define ICH9_SMB_DEV[[:space:]].*/#define ICH9_SMB_DEV                            31/' \
      include/hw/southbridge/ich9.h
    if ! grep -qE '^#define ICH9_SMB_DEV[[:space:]]+31$' include/hw/southbridge/ich9.h; then
      echo "FATAL: ICH9 SMBus device revert to 31 failed: at 0x14 it has no function 0 beside it, so the guest never enumerates it"
      exit 1
    fi
    if grep -qF '// Slot 20 (0x14): LPC / SMBus / SATA 2' hw/acpi/pcihp.c; then
      substituteInPlace hw/acpi/pcihp.c \
        --replace-fail '        case 20:
              // Slot 20 (0x14): LPC / SMBus / SATA 2' \
                       '        case 31:
              // Slot 31 (0x1F): LPC / SMBus / SATA 2' \
        --replace-fail 'sprintf(name, "S20%X", func);' 'sprintf(name, "S31%X", func);'
    fi
    exactly_one hw/acpi/pcihp.c '^ +case 31:$' "the ACPI names LPCB, SAT1 and SBUS follow their devices to slot 0x1f, or PCI0.LPCB.PIRQ cannot resolve"
    landed hw/acpi/pcihp.c 'sprintf(name, "S31%X", func);' "the slot 0x1f fallback name"
    gone hw/acpi/pcihp.c 'sprintf(name, "S20%X", func);' "no ACPI name left on slot 0x14"
    patch -p1 -F0 --no-backup-if-mismatch -i ${./acpi-pci-names.patch}
    exactly_one hw/acpi/pcihp.c '^static void pci_acpi_name' "one naming function for every ACPI PCI device"
    gone hw/acpi/pcihp.c 'S%.02X' "no scope, notify or slot still uses QEMU's S%.02X name, which the devices no longer carry"

    substituteInPlace include/hw/pci/pci.h \
      --replace-fail 'PCI_SUBVENDOR_ID_REDHAT_QUMRANET 0x1af4' 'PCI_SUBVENDOR_ID_REDHAT_QUMRANET 0x${subsystemVendor}' \
      --replace-fail 'PCI_SUBDEVICE_ID_QEMU            0x1100' 'PCI_SUBDEVICE_ID_QEMU            0x${subsystemDevice}'
    landed include/hw/pci/pci.h 'PCI_SUBVENDOR_ID_REDHAT_QUMRANET 0x${subsystemVendor}' "PCI subsystem vendor set to ${subsystemVendor}"
    landed include/hw/pci/pci.h 'PCI_SUBDEVICE_ID_QEMU            0x${subsystemDevice}' "PCI subsystem device set to ${subsystemDevice}"

  ${hdaControllerRevert}
  ${xhciWindow}
    # why: AutoVirt gives the codec Realtek's vendor with QEMU's device number, an id no real codec has, and the board's subsystem belongs in its subsystem id
    sed -i '/\.id  = AC_PAR_VENDOR_ID,/{n;s/\.val = QEMU_HDA_ID_[A-Z]*,/.val = 0x${codecId},/}' hw/audio/hda-codec-common.h
    sed -i -e 's/\.val = QEMU_HDA_ID_[A-Z]*,/.val = 0x${subsystemVendor}${subsystemDevice},/' -e 's/\.iid    = QEMU_HDA_ID_[A-Z]*,/.iid    = 0x${subsystemVendor}${subsystemDevice},/' hw/audio/hda-codec-common.h
    landed hw/audio/hda-codec-common.h '.val = 0x${codecId},' "HD Audio codec id set to ${codecId}"
    landed hw/audio/hda-codec-common.h '.iid    = 0x${subsystemVendor}${subsystemDevice},' "HD Audio codec subsystem set to the board's ${subsystemVendor}${subsystemDevice}"
    gone hw/audio/hda-codec-common.h '= QEMU_HDA_ID_' "no codec parameter or subsystem keeps QEMU's codec id"

    # why: AutoVirt gives the mouse and keyboard Logitech ids but leaves the tablet on QEMU's 0627:0001, and QEMU builds every HID serial from the host controller's PCI path
    mouseVendor=$(sed -n '/^static const USBDesc desc_mouse = {/,/^};/s/^ *\.idVendor *= \(0x[0-9A-Fa-f]*\),$/\1/p' hw/usb/dev-hid.c)
    mouseProduct=$(sed -n '/^static const USBDesc desc_mouse = {/,/^};/s/^ *\.idProduct *= \(0x[0-9A-Fa-f]*\),$/\1/p' hw/usb/dev-hid.c)
    if [ -z "$mouseVendor" ] || [ -z "$mouseProduct" ]; then
      echo "FATAL: hw/usb/dev-hid.c has no desc_mouse idVendor and idProduct to give the tablet"
      exit 1
    fi
    sed -i "/^static const USBDesc desc_tablet2\{0,1\} = {/,/^};/{s/\(\.idVendor *= \)0x[0-9A-Fa-f]*,/\1$mouseVendor,/;s/\(\.idProduct *= \)0x[0-9A-Fa-f]*,/\1$mouseProduct,/;s/STR_PRODUCT_TABLET,/STR_PRODUCT_MOUSE,/}" hw/usb/dev-hid.c
    sed -i 's/\.iSerialNumber     = STR_SERIAL_[A-Z]*,/.iSerialNumber     = 0,/' hw/usb/dev-hid.c
    exactly_one hw/usb/dev-hid.c '^ +usb_desc_create_serial\(dev\);$' "one HID serial call to drop"
    sed -i '/^ *usb_desc_create_serial(dev);$/d' hw/usb/dev-hid.c
    gone hw/usb/dev-hid.c '0x0627' "no HID device keeps QEMU's USB vendor 0627"
    gone hw/usb/dev-hid.c '.iProduct          = STR_PRODUCT_TABLET' "the tablet names itself as the mouse does"
    gone hw/usb/dev-hid.c '.iSerialNumber     = STR_SERIAL' "HID devices report no serial number, as a real mouse or keyboard does"
    gone hw/usb/dev-hid.c 'usb_desc_create_serial' "no HID serial is built from the host controller path"

    # why: QEMU's other USB devices name QEMU or carry its vendor 46f4, and their serials name the host controller's PCI path; each takes one real device's identity, and a serial is derived from the VM uuid and the port so it stays stable and differs between VMs
    patch -p1 -F0 --no-backup-if-mismatch -i ${./usb-serial-from-uuid.patch}
    exactly_one hw/usb/desc.c '^ +g_checksum_update\(sum, qemu_uuid\.data' "a USB serial is derived from the VM uuid and the port path"
    gone hw/usb/desc.c 'path, dev->port->path);' "no USB serial carries the host controller path"
    substituteInPlace hw/usb/dev-storage.c hw/usb/dev-uas.c \
      --replace-fail '[STR_MANUFACTURER] = "QEMU",' '[STR_MANUFACTURER] = "${usbStorageBridge.manufacturer}",' \
      --replace-fail '.idVendor          = 0x46f4, /* CRC16() of "QEMU" */' '.idVendor          = ${usbStorageBridge.vendor},'
    substituteInPlace hw/usb/dev-storage.c \
      --replace-fail '[STR_PRODUCT]      = "QEMU USB HARDDRIVE",' '[STR_PRODUCT]      = "${usbStorageBridge.name}",' \
      --replace-fail '[STR_SERIALNUMBER] = "1",' '[STR_SERIALNUMBER] = "${serialTemplate usbStorageBridge}",' \
      --replace-fail '.idProduct         = 0x0001,' '.idProduct         = ${usbStorageBridge.product},'
    substituteInPlace hw/usb/dev-uas.c \
      --replace-fail '[STR_PRODUCT]      = "USB Attached SCSI HBA",' '[STR_PRODUCT]      = "${usbStorageBridge.name}",' \
      --replace-fail '[STR_SERIALNUMBER] = "27842",' '[STR_SERIALNUMBER] = "${serialTemplate usbStorageBridge}",' \
      --replace-fail '.idProduct         = 0x0003,' '.idProduct         = ${usbStorageBridge.product},'
    for f in hw/usb/dev-storage.c hw/usb/dev-uas.c; do
      landed "$f" '.idProduct         = ${usbStorageBridge.product},' "$f reports the ${usbStorageBridge.manufacturer} bridge's id"
      landed "$f" '[STR_PRODUCT]      = "${usbStorageBridge.name}",' "$f names the ${usbStorageBridge.manufacturer} bridge"
      gone "$f" '0x46f4' "$f keeps no QEMU USB vendor 46f4"
    done

    substituteInPlace hw/usb/dev-hub.c \
      --replace-fail '.idVendor          = 0x0409,' '.idVendor          = ${usbHub.vendor},' \
      --replace-fail '.idProduct         = 0x55aa,' '.idProduct         = ${usbHub.product},' \
      --replace-fail '.iManufacturer     = STR_MANUFACTURER,' '.iManufacturer     = 0,' \
      --replace-fail '.iProduct          = STR_PRODUCT,' '.iProduct          = 0,' \
      --replace-fail '.iSerialNumber     = STR_SERIALNUMBER,' '.iSerialNumber     = 0,'
    exactly_one hw/usb/dev-hub.c '^ +usb_desc_create_serial\(dev\);$' "one hub serial call to drop"
    sed -i -e '/^ *usb_desc_create_serial(dev);$/d' -e '/^ *\[STR_[A-Z]*\] *= "[^"]*",$/d' hw/usb/dev-hub.c
    landed hw/usb/dev-hub.c '.idProduct         = ${usbHub.product},' "the hub reports a real hub chip's id"
    gone hw/usb/dev-hub.c '[STR_' "the hub has no string descriptors, as its chip has none"
    gone hw/usb/dev-hub.c 'usb_desc_create_serial' "the hub reports no serial number"

    exactly_one hw/usb/dev-serial.c '^    STR_PRODUCT_BRAILLE,$' "one braille product index to add the braille manufacturer after"
    sed -i -e 's|^    STR_PRODUCT_BRAILLE,$|    STR_PRODUCT_BRAILLE,\n    STR_MANUFACTURER_BRAILLE,|' \
      -e 's|^    \[STR_MANUFACTURER\]    = "QEMU",$|    [STR_MANUFACTURER]    = "${usbSerial.manufacturer}",\n    [STR_MANUFACTURER_BRAILLE] = "${usbBraille.manufacturer}",|' \
      -e '/^static const USBDesc desc_braille = {/,/^};/s|\.iManufacturer     = STR_MANUFACTURER,|.iManufacturer     = STR_MANUFACTURER_BRAILLE,|' \
      -e '/^static const USBDesc desc_serial = {/,/^};/{s|\.idVendor          = 0x0403,|.idVendor          = ${usbSerial.vendor},|;s|\.idProduct         = 0x6001,|.idProduct         = ${usbSerial.product},|}' \
      -e '/^static const USBDesc desc_serial = {/,/^};/s|\.bcdDevice         = 0x0400,|.bcdDevice         = ${usbSerial.release},|' hw/usb/dev-serial.c
    substituteInPlace hw/usb/dev-serial.c \
      --replace-fail '[STR_PRODUCT_SERIAL]  = "QEMU USB SERIAL",' '[STR_PRODUCT_SERIAL]  = "${usbSerial.name}",' \
      --replace-fail '[STR_PRODUCT_BRAILLE] = "QEMU USB BAUM BRAILLE",' '[STR_PRODUCT_BRAILLE] = "${usbBraille.name}",' \
      --replace-fail '[STR_SERIALNUMBER]    = "1",' '[STR_SERIALNUMBER]    = "${serialTemplate usbSerial}",'
    landed hw/usb/dev-serial.c '[STR_MANUFACTURER_BRAILLE] = "${usbBraille.manufacturer}",' "the braille display names its own maker"
    landed hw/usb/dev-serial.c '.iManufacturer     = STR_MANUFACTURER_BRAILLE,' "the braille display points at its own maker"
    landed hw/usb/dev-serial.c '.bcdDevice         = ${usbSerial.release},' "the serial adapter reports the release of the chip it names"
    landed hw/usb/dev-serial.c '.idVendor          = ${usbSerial.vendor},' "the serial adapter keeps the vendor id of the chip it names"
    landed hw/usb/dev-serial.c '.idProduct         = ${usbSerial.product},' "the serial adapter keeps the product id of the chip it names"
    gone hw/usb/dev-serial.c '= "QEMU",' "the serial adapter's maker is not QEMU"
    # why: QEMU plugs the adapter in only while its character device is open and unplugs it again when it closes, where a real adapter stays on the bus
    substituteInPlace hw/usb/dev-serial.c \
      --replace-fail 'DEFINE_PROP_BOOL("always-plugged", USBSerialState, always_plugged, false),' 'DEFINE_PROP_BOOL("always-plugged", USBSerialState, always_plugged, true),'
    landed hw/usb/dev-serial.c 'always_plugged, true),' "the serial adapter stays plugged, as a real one does"

    substituteInPlace hw/usb/dev-smartcard-reader.c \
      --replace-fail '[STR_MANUFACTURER]  = "QEMU",' '[STR_MANUFACTURER]  = "${usbSmartcard.manufacturer}",' \
      --replace-fail '[STR_PRODUCT]       = "QEMU USB CCID",' '[STR_PRODUCT]       = "${usbSmartcard.name}",' \
      --replace-fail '[STR_SERIALNUMBER]  = "1",' '[STR_SERIALNUMBER]  = "${serialTemplate usbSmartcard}",' \
      --replace-fail '#define CCID_DEVICE_VERSION             0x0000' '#define CCID_DEVICE_VERSION             ${usbSmartcard.release}'
    landed hw/usb/dev-smartcard-reader.c '[STR_PRODUCT]       = "${usbSmartcard.name}",' "the smartcard reader names the reader its ids belong to"
    gone hw/usb/dev-smartcard-reader.c '[STR_MANUFACTURER]  = "QEMU",' "the smartcard reader's maker is not QEMU"

    substituteInPlace hw/usb/u2f.c \
      --replace-fail '#define U2F_KEY_VENDOR_NUM     0x46f4 /* CRC16() of "QEMU" */' '#define U2F_KEY_VENDOR_NUM     ${usbFidoKey.vendor}' \
      --replace-fail '#define U2F_KEY_PRODUCT_NUM    0x0005' '#define U2F_KEY_PRODUCT_NUM    ${usbFidoKey.product}' \
      --replace-fail '[STR_MANUFACTURER]     = "QEMU",' '[STR_MANUFACTURER]     = "${usbFidoKey.manufacturer}",' \
      --replace-fail '[STR_PRODUCT]          = "U2F USB key",' '[STR_PRODUCT]          = "${usbFidoKey.name}",' \
      --replace-fail '.iSerialNumber     = STR_SERIALNUMBER,' '.iSerialNumber     = 0,'
    substituteInPlace hw/usb/dev-wacom.c \
      --replace-fail '[STR_MANUFACTURER]     = "QEMU",' '[STR_MANUFACTURER]     = "${usbTablet.manufacturer}",' \
      --replace-fail '.iSerialNumber     = STR_SERIALNUMBER,' '.iSerialNumber     = 0,'
    substituteInPlace hw/usb/dev-audio.c \
      --replace-fail '#define USBAUDIO_VENDOR_NUM     0x46f4 /* CRC16() of "QEMU" */' '#define USBAUDIO_VENDOR_NUM     ${usbAudio.vendor}' \
      --replace-fail '#define USBAUDIO_PRODUCT_NUM    0x0002' '#define USBAUDIO_PRODUCT_NUM    ${usbAudio.product}' \
      --replace-fail '[STRING_MANUFACTURER]       = "QEMU",' '[STRING_MANUFACTURER]       = "${usbAudio.manufacturer}",' \
      --replace-fail '[STRING_PRODUCT]            = "QEMU USB Audio",' '[STRING_PRODUCT]            = "${usbAudio.name}",' \
      --replace-fail '.bcdDevice         = 0,' '.bcdDevice         = ${usbAudio.release},' \
      --replace-fail '.iSerialNumber     = STRING_SERIALNUMBER,' '.iSerialNumber     = 0,'
    for f in hw/usb/u2f.c hw/usb/dev-wacom.c hw/usb/dev-audio.c; do
      exactly_one "$f" '^ +usb_desc_create_serial\(dev\);$' "one $f serial call to drop"
      sed -i -e '/^ *usb_desc_create_serial(dev);$/d' -e '/^ *\[STR[A-Z]*_SERIALNUMBER\] *= "[^"]*",$/d' "$f"
      gone "$f" 'usb_desc_create_serial' "$f reports no serial number, as the device it copies has none"
      gone "$f" '_SERIALNUMBER]' "$f keeps no serial string a guest could read by index"
      gone "$f" '0x46f4' "$f keeps no QEMU USB vendor 46f4"
      gone "$f" '= "QEMU",' "$f's maker is not QEMU"
    done
    landed hw/usb/u2f.c '#define U2F_KEY_PRODUCT_NUM    ${usbFidoKey.product}' "the FIDO key reports the key it names"
    landed hw/usb/dev-audio.c '#define USBAUDIO_PRODUCT_NUM    ${usbAudio.product}' "the USB sound card reports the chip it names"

    substituteInPlace hw/usb/dev-mtp.c \
      --replace-fail '#define MTP_MANUFACTURER  "QEMU"' '#define MTP_MANUFACTURER  "${usbPhone.manufacturer}"' \
      --replace-fail '#define MTP_PRODUCT       "QEMU filesharing"' '#define MTP_PRODUCT       "${usbPhone.name}"' \
      --replace-fail '[STR_SERIALNUMBER] = "34617",' '[STR_SERIALNUMBER] = "${serialTemplate usbPhone}",' \
      --replace-fail '.idVendor          = 0x46f4, /* CRC16() of "QEMU" */' '.idVendor          = ${usbPhone.vendor},' \
      --replace-fail '.idProduct         = 0x0004,' '.idProduct         = ${usbPhone.mtpProduct},' \
      --replace-fail 'usb_mtp_add_wstr(d, L"0.1");' 'usb_mtp_add_wstr(d, L"${usbPhone.androidRelease}");' \
      --replace-fail 'usb_mtp_add_wstr(d, L"0123456789abcdef0123456789abcdef");' 'usb_mtp_add_str(d, usb_desc_get_string(&s->dev, STR_SERIALNUMBER));'
    landed hw/usb/dev-mtp.c '.idProduct         = ${usbPhone.mtpProduct},' "the MTP device reports the phone's MTP id"
    gone hw/usb/dev-mtp.c '0x46f4' "the MTP device keeps no QEMU USB vendor 46f4"
    landed hw/usb/dev-mtp.c 'usb_mtp_add_wstr(d, L"${usbPhone.androidRelease}");' "the MTP device info reports the phone's Android release as its version"
    landed hw/usb/dev-mtp.c 'usb_mtp_add_str(d, usb_desc_get_string(&s->dev, STR_SERIALNUMBER));' "the MTP device info reports the USB serial, as a phone reports one serial on both"
    gone hw/usb/dev-mtp.c '0123456789abcdef' "the MTP device info keeps no QEMU placeholder serial"

    sed -i -e 's|^#define RNDIS_VENDOR_NUM .*$|#define RNDIS_VENDOR_NUM        ${usbPhone.vendor}|' \
      -e 's|^#define RNDIS_PRODUCT_NUM .*$|#define RNDIS_PRODUCT_NUM       ${usbPhone.tetherProduct}|' \
      -e '/^ *\[STRING_SUBSET\] *= "[^"]*",$/d' hw/usb/dev-network.c
    substituteInPlace hw/usb/dev-network.c \
      --replace-fail '[STRING_MANUFACTURER]       = "QEMU",' '[STRING_MANUFACTURER]       = "${usbPhone.manufacturer}",' \
      --replace-fail '[STRING_PRODUCT]            = "RNDIS/QEMU USB Network Device",' '[STRING_PRODUCT]            = "${usbPhone.name}",' \
      --replace-fail '[STRING_DATA]               = "QEMU USB Net Data Interface",' '[STRING_DATA]               = "RNDIS Ethernet Data",' \
      --replace-fail '[STRING_CONTROL]            = "QEMU USB Net Control Interface",' '[STRING_CONTROL]            = "CDC Ethernet Control Model (ECM)",' \
      --replace-fail '[STRING_RNDIS_CONTROL]      = "QEMU USB Net RNDIS Control Interface",' '[STRING_RNDIS_CONTROL]      = "RNDIS Communications Control",' \
      --replace-fail '[STRING_CDC]                = "QEMU USB Net CDC",' '[STRING_CDC]                = "CDC ECM",' \
      --replace-fail '[STRING_RNDIS]              = "QEMU USB Net RNDIS",' '[STRING_RNDIS]              = "RNDIS",' \
      --replace-fail '[STRING_SERIALNUMBER]       = "1",' '[STRING_SERIALNUMBER]       = "${serialTemplate usbPhone}",' \
      --replace-fail 'pstrcpy((char *)outbuf, outlen, "QEMU USB RNDIS Net");' 'pstrcpy((char *)outbuf, outlen, "");' \
      --replace-fail 's->vendorid = 0x1234;' 's->vendorid = 0;'
    landed hw/usb/dev-network.c '#define RNDIS_PRODUCT_NUM       ${usbPhone.tetherProduct}' "the network device reports the phone's tethering id"
    gone hw/usb/dev-network.c '"QEMU USB Net ' "no network interface string names QEMU"
    gone hw/usb/dev-network.c '"QEMU USB RNDIS Net"' "the RNDIS vendor description does not name QEMU"
    gone hw/usb/dev-network.c '[STRING_SUBSET]' "no unused QEMU string is left for a guest to read by index"

    # why: Windows binds the generation counter on its compatible id, and the hardware id names the hypervisor; Hyper-V's own id replaces QEMU's
    substituteInPlace hw/acpi/vmgenid.c \
      --replace-fail 'aml_string("QEMUVGID")' 'aml_string("${vmgenidHardwareId}")'
    gone hw/acpi/vmgenid.c 'QEMUVGID' "the generation counter's hardware id is not QEMU's"

    patch -p1 -F0 --no-backup-if-mismatch -i ${./megasas-serial-from-uuid.patch}
    exactly_one hw/scsi/megasas.c '^ +g_checksum_update\(sum, qemu_uuid\.data' "a MegaRAID serial is derived from the VM uuid and the card's PCI path"
    substituteInPlace hw/scsi/megasas.c \
      --replace-fail '#define MEGASAS_HBA_SERIAL_DIGITS 8' '#define MEGASAS_HBA_SERIAL_DIGITS ${toString megasas.serialDigits}' \
      --replace-fail 'snprintf(info.package_version, 0x60, "%s-QEMU", QEMU_HW_VERSION);' 'snprintf(info.package_version, 0x60, "%s", "${megasas.package}");' \
      --replace-fail 'snprintf(info.image_component[0].version, 10, "%s-QEMU",' 'snprintf(info.image_component[0].version, 10, "%s",' \
      --replace-fail '#define MEGASAS_HBA_SERIAL "QEMU123456"' '#define MEGASAS_HBA_SERIAL "${megasas.serialPrefix}"'
    gone hw/scsi/megasas.c '-QEMU"' "no MegaRAID version names QEMU"
    landed hw/scsi/megasas.c '"${megasas.package}");' "the MegaRAID package version is a real LSI package"
    landed hw/scsi/megasas.c '#define MEGASAS_HBA_SERIAL "${megasas.serialPrefix}"' "a MegaRAID serial starts with ${megasas.serialPrefix}"
    landed hw/scsi/megasas.c '#define MEGASAS_HBA_SERIAL_DIGITS ${toString megasas.serialDigits}' "a MegaRAID serial has ${toString megasas.serialDigits} digits"
    gone hw/scsi/megasas.c 'QEMU123456' "no MegaRAID serial names QEMU"

    # why: an -acpitable given without a header gets this one; OEMx is the signature the ACPI spec reserves for OEM tables, which an OS ignores as it ignored QEMU's
    substituteInPlace hw/acpi/core.c \
      --replace-fail '"QEMUQEQEMUQEMU\1\0\0\0"' '"${acpiOemId}${acpiOemTableId}\1\0\0\0"' \
      --replace-fail '"QEMU\0\0\0\0\1\0"' '"OEM1\0\0\0\0\1\0"' \
      --replace-fail '"QEMU\1\0\0\0"' '"${acpiCreatorBytes}"'
    landed hw/acpi/core.c '"${acpiOemId}${acpiOemTableId}\1\0\0\0"' "a headerless -acpitable carries the configured OEM id and table id"
    landed hw/acpi/core.c '"${acpiCreatorBytes}"' "a headerless -acpitable names creator ${acpiCreator.id} revision ${toString acpiCreator.revision}"
    gone hw/acpi/core.c '"QEMU' "no default ACPI table header field names QEMU"

    # why: AutoVirt's boundary C2/C3 latencies make the Windows HAL attempt power transitions that hang under QEMU
    exactly_one hw/i386/acpi-build.c '^ +\.plvl2_lat = 0x0065 ' "one FADT C2 latency to set"
    exactly_one hw/i386/acpi-build.c '^ +\.plvl3_lat = 0x03e9 ' "one FADT C3 latency to set"
    sed -i -e 's/\.plvl2_lat = 0x0065 /.plvl2_lat = ${hex fadtC2Latency} /' -e 's/\.plvl3_lat = 0x03e9 /.plvl3_lat = ${hex fadtC3Latency} /' hw/i386/acpi-build.c
    landed hw/i386/acpi-build.c '.plvl2_lat = ${hex fadtC2Latency} /*' "the FADT C2 latency is ${toString fadtC2Latency}"
    landed hw/i386/acpi-build.c '.plvl3_lat = ${hex fadtC3Latency} /*' "the FADT C3 latency is ${toString fadtC3Latency}"
    gone hw/i386/acpi-build.c '.plvl2_lat = 0x0065 /*' "AutoVirt's C2 latency is replaced"
    gone hw/i386/acpi-build.c '.plvl3_lat = 0x03e9 /*' "AutoVirt's C3 latency is replaced"

  ${waetEdit}
    echo "=== Hardware identity customization complete ==="''
