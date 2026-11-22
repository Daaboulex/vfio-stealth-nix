{
  lib,
  runCommand,
  cpuVendor,
  qemu-stealth,
  patchAssertions,
}:

let
  autovirtPatches = import ../lib/autovirt-patches.nix { inherit lib; };

  inherit (qemu-stealth) autovirtPatch;

  inherit (autovirtPatches.traits.${cpuVendor})
    patchedOemId
    patchedOemTableId
    patchedHdaDevice
    xhciRegisterWindow
    ;

  nixpkgsPatches = lib.concatMapStringsSep "\n" (p: "patch -p1 -i ${p}") (
    qemu-stealth.patches or [ ]
  );

  postPatch = import ../qemu/post-patch.nix {
    inherit
      lib
      patchAssertions
      autovirtPatch
      patchedOemId
      patchedOemTableId
      patchedHdaDevice
      xhciRegisterWindow
      ;
    edidManufacturer = "TST";
    edidSerial = "TESTMON";
    edidSerialNumber = 305419896;
    edidProductCode = "0x7e57";
    edidDpi = 97;
    edidWeek = 7;
    edidYear = 2019;
    edidResX = 2560;
    edidResY = 1440;
    acpiOemId = "TESTID";
    acpiOemTableId = "TESTTBL1";
    diskModel = "Test Disk Model 9000";
    diskSerial = "TESTSERIAL0123";
    opticalModel = "TESTVEND TEST OPTICAL";
    diskFirmware = "TF01";
    opticalFirmware = "TO02";
    pciSubsystem = "1458:5001";
    hdaCodec = "1D17:3288";
    scsiVendor = "TSTV";
    scsiTargetProduct = "Test Target     ";
    smbiosChassisType = 35;
    smbiosMemoryErrorCorrection = 5;
    smbiosMemoryMaxCapacityGb = 96;
    smbiosMemorySlots = [
      {
        locator = "TSLOT A0";
        bank = "TBANK X";
        populated = true;
        serial = "T35T5ER1";
      }
      {
        locator = "TSLOT B0";
        bank = "TBANK Y";
        populated = false;
        serial = null;
      }
    ];
    smbiosMemoryType = "LPDDR5";
    smbiosMemoryTypeDetail = 8320;
    smbiosMemoryRank = 3;
    smbiosMemoryVoltageMillivolts = 1350;
    deviceIdentities = testIdentities;
    acpiWaet = waet;
    fadtC2Latency = 99;
    fadtC3Latency = 999;
  };

  waet = cpuVendor != "amd";

  testIdentities = {
    usbStorageBridge = {
      vendor = "0x1e01";
      product = "0x2e02";
      manufacturer = "Test Bridge Maker";
      name = "Test Bridge Name";
      serialLength = 10;
    };
    usbHub = {
      vendor = "0x1e03";
      product = "0x2e04";
    };
    usbSerial = {
      vendor = "0x1e05";
      product = "0x2e06";
      manufacturer = "Test Serial Maker";
      name = "Test Serial Name";
      release = "0x0e07";
      serialLength = 9;
    };
    usbBraille = {
      manufacturer = "Test Braille Maker";
      name = "Test Braille Name";
    };
    usbSmartcard = {
      manufacturer = "Test Card Maker";
      name = "Test Card Name";
      release = "0x0e08";
      serialLength = 7;
    };
    usbFidoKey = {
      vendor = "0x1e09";
      product = "0x2e0a";
      manufacturer = "Test Key Maker";
      name = "Test Key Name";
    };
    usbTablet.manufacturer = "Test Tablet Maker";
    usbAudio = {
      vendor = "0x1e0b";
      product = "0x2e0c";
      manufacturer = "Test Audio Maker";
      name = "Test Audio Name";
      release = "0x0e0d";
    };
    usbPhone = {
      vendor = "0x1e0e";
      mtpProduct = "0x2e0f";
      tetherProduct = "0x2e10";
      manufacturer = "Test Phone Maker";
      name = "Test Phone Name";
      androidRelease = "9.1";
      serialLength = 11;
    };
    vmgenidHardwareId = "Test_Gen_Counter";
    megasas = {
      package = "9.87.6-5432";
      serialPrefix = "TQ";
      serialDigits = 11;
    };
    acpiCreator = {
      id = "TSTC";
      revision = 168496141;
    };
  };

  guard = name: path: pattern: absent: {
    inherit
      name
      path
      pattern
      absent
      ;
  };

  guards = [
    (guard "edid-manufacturer" "hw/display/edid-generate.c" ''"TST"'' ''"RHT"'')
    (guard "edid-monitor-name" "hw/display/edid-generate.c" ''"TESTMON"'' ''"QEMU Monitor"'')
    (guard "edid-serial-number" "hw/display/edid-generate.c" "atoi(info->serial) : 305419896U;"
      "atoi(info->serial) : 0;"
    )
    (guard "smbios-memory-slot-serial" "hw/smbios/smbios.c"
      ''{ "TSLOT A0", "TBANK X", true, "T35T5ER1" },''
      "(size ? type17.serial : NULL)"
    )
    (guard "edid-product-code" "hw/display/edid-generate.c" "0x7e57" "0x1234")
    (guard "edid-week" "hw/display/edid-generate.c" "edid[16] = 7;" "edid[16] = 42;")
    (guard "edid-year" "hw/display/edid-generate.c" "2019 - 1990" "2014 - 1990")
    (guard "edid-dpi" "hw/display/edid-generate.c" "uint32_t dpi = 97;" "uint32_t dpi = 100;")
    (guard "edid-resx" "hw/display/edid-generate.c" "info->prefx = 2560;" "info->prefx = 1280;")
    (guard "edid-resy" "hw/display/edid-generate.c" "info->prefy = 1440;" "info->prefy = 800;")
    (guard "scsi-bus-vendor" "hw/scsi/scsi-bus.c" ''"TSTV    "'' ''"QEMU    "'')
    (guard "scsi-bus-target-product" "hw/scsi/scsi-bus.c" ''"Test Target     "'' ''"QEMU TARGET     "'')
    (guard "scsi-disk-product" "hw/scsi/scsi-disk.c" ''"Test Disk Model 9000"'' ''"QEMU HARDDISK"'')
    (guard "scsi-cdrom-product" "hw/scsi/scsi-disk.c" ''"TESTVEND TEST OPTICAL"'' ''"QEMU CD-ROM"'')
    (guard "scsi-disk-vendor" "hw/scsi/scsi-disk.c" ''"TSTV"'' ''"QEMU"'')
    (guard "acpi-oem-id" "include/hw/acpi/aml-build.h" ''"TESTID"'' ''"${patchedOemId}"'')
    (guard "acpi-oem-table-id" "include/hw/acpi/aml-build.h" ''"TESTTBL1"'' ''"${patchedOemTableId}"'')
    (guard "ide-main-disk" "hw/ide/core.c" ''"Test Disk Model 9000"'' "Samsung SSD 980 500GB")
    (guard "ide-cfata" "hw/ide/core.c" ''"Test Disk Model 9000"'' "Hitachi HMS360404D5CF00")
    (guard "ide-serial" "hw/ide/core.c"
      ''pstrcpy(s->drive_serial_str, sizeof(s->drive_serial_str), "TESTSERIAL0123");''
      "s->drive_serial_str[0] = '\\0';"
    )
    (guard "ide-optical" "hw/ide/core.c" ''"TESTVEND TEST OPTICAL"'' "HL-DT-ST BD-RE WH16NS60")
    (guard "atapi-inquiry-vendor" "hw/ide/atapi.c" ''padstr8(buf + 8, 8, "TESTVEND");'' ''"Samsung"'')
    (guard "atapi-inquiry-product" "hw/ide/atapi.c" ''padstr8(buf + 16, 16, "TEST OPTICAL");''
      ''padstr8(buf + 16, 16, "DVD-ROM");''
    )
    (guard "ide-firmware" "hw/ide/core.c"
      ''pstrcpy(s->version, sizeof(s->version), kind == IDE_CD ? "TO02" : "TF01");''
      "QEMU_HW_VERSION);"
    )
    (guard "scsi-disk-firmware" "hw/scsi/scsi-disk.c"
      ''s->version = g_strdup(dev->type == TYPE_ROM ? "TO02" : "TF01");''
      "g_strdup(QEMU_HW_VERSION)"
    )
    (guard "scsi-target-revision" "hw/scsi/scsi-bus.c" ''pstrcpy((char *) &r->buf[32], 4, "TF01");''
      "4, QEMU_HW_VERSION);"
    )
    (guard "smbios-type0-characteristics" "hw/smbios/smbios.c"
      "t->bios_characteristics = cpu_to_le64(0x7c0b9880);"
      "cpu_to_le64(0x08); /* Not supported */"
    )
    (guard "smbios-type0-not-vm" "hw/smbios/smbios.c"
      ''smbios_type0.vm = qemu_opt_get_bool(opts, "vm", false);''
      ''qemu_opt_get_bool(opts, "vm", true)''
    )
    (guard "smbios-type0-uefi" "hw/smbios/smbios.c"
      ''smbios_type0.uefi = qemu_opt_get_bool(opts, "uefi", true);''
      ''qemu_opt_get_bool(opts, "uefi", false)''
    )
    (guard "smbios-type3-chassis-type" "hw/smbios/smbios.c" "t->type = 0x23;"
      "t->type = 0x01; /* Other */"
    )
    (guard "smbios-stringless-required-tables" "hw/smbios/smbios.c"
      "if ((smbios_have_defaults || type == 16 || type == 19 || type == 32 || type == 127) && required_table) {"
      "if (smbios_have_defaults && required_table) {"
    )
    (guard "smbios-memory-array-location" "hw/smbios/smbios.c" "t->location = 0x03;"
      "t->location = 0x01; /* Other */"
    )
    (guard "smbios-memory-array-ecc" "hw/smbios/smbios.c" "t->error_correction = 0x05;"
      "Multi-bit ECC (for Microsoft"
    )
    (guard "smbios-memory-max-capacity" "hw/smbios/smbios.c"
      "#define SMBIOS_MEMORY_MAX_CAPACITY (96ULL * GiB)"
      "GET_DIMM_SZ"
    )
    (guard "smbios-memory-modules" "hw/smbios/smbios.c" "#define SMBIOS_MEMORY_MODULES 1"
      "@smbiosMemorySlots@"
    )
    (guard "smbios-memory-slot-table" "hw/smbios/smbios.c" ''{ "TSLOT B0", "TBANK Y", false, NULL },''
      "type17.loc_pfx, instance"
    )
    (guard "smbios-memory-partition-width" "hw/smbios/smbios.c"
      "t->partition_width = SMBIOS_MEMORY_MODULES;"
      "t->partition_width = 1;"
    )
    (guard "smbios-type8-handle" "hw/smbios/smbios.c"
      "SMBIOS_BUILD_TABLE_PRE(8, 0x800 + instance, true);"
      "SMBIOS_BUILD_TABLE_PRE(8, T0_BASE"
    )
    (guard "acpi-pci-names-consistent" "hw/acpi/pcihp.c" "pci_acpi_name(slot_name, bus, devfn);"
      "S%.02X"
    )
    (guard "fw-cfg-signature" "hw/nvram/fw_cfg.c" ''(char *)"\xff\xff\xff\xff", 4);''
      ''(char *)"QEMU", 4)''
    )
    (guard "devices-hotpluggable" "hw/core/qdev.c" "dc->hotpluggable = true;"
      "dc->hotpluggable = false;"
    )
    (guard "nvme-firmware" "hw/nvme/ctrl.c" ''n->params.firmware_version : "TF01"''
      "n->params.firmware_version : QEMU_VERSION"
    )
    (guard "nvme-model" "hw/nvme/ctrl.c" ''"Test Disk Model 9000"'' ''"NVMe Ctrl"'')
    (guard "pci-subsystem-vendor" "include/hw/pci/pci.h" "PCI_SUBVENDOR_ID_REDHAT_QUMRANET 0x1458"
      "PCI_SUBVENDOR_ID_REDHAT_QUMRANET 0x1af4"
    )
    (guard "pci-subsystem-device" "include/hw/pci/pci.h" "PCI_SUBDEVICE_ID_QEMU            0x5001"
      "PCI_SUBDEVICE_ID_QEMU            0x1100"
    )
    (guard "hda-codec-id" "hw/audio/hda-codec-common.h" ".val = 0x1d173288," "= QEMU_HDA_ID_")
    (guard "hda-codec-subsystem" "hw/audio/hda-codec-common.h" ".iid    = 0x14585001," "= QEMU_HDA_ID_")
  ]
  ++ lib.optionals (patchedHdaDevice != null) [
    (guard "hda-ich9-device" "hw/audio/intel-hda.c" "k->device_id = 0x293e;"
      "k->device_id = ${patchedHdaDevice};"
    )
    (guard "hda-ich6-device" "hw/audio/intel-hda.c" "k->device_id = 0x2668;"
      "k->device_id = ${patchedHdaDevice};"
    )
  ]
  ++ lib.optionals (xhciRegisterWindow != "0x4000") [
    (guard "xhci-register-window" "include/hw/usb/xhci.h" "#define XHCI_LEN_REGS ${xhciRegisterWindow}"
      "#define XHCI_LEN_REGS 0x4000"
    )
  ]
  ++ [
    (guard "usb-tablet-not-qemu" "hw/usb/dev-hid.c" ".iProduct          = STR_PRODUCT_MOUSE," "0x0627")
    (guard "usb-hid-no-serial" "hw/usb/dev-hid.c" ".iSerialNumber     = 0," "usb_desc_create_serial")
    (guard "usb-serial-from-uuid" "hw/usb/desc.c" "g_checksum_update(sum, qemu_uuid.data"
      "path, dev->port->path);"
    )
    (guard "usb-storage-vendor" "hw/usb/dev-storage.c" ".idVendor          = 0x1e01," "0x46f4")
    (guard "usb-storage-name" "hw/usb/dev-storage.c" ''"Test Bridge Name"'' ''"QEMU USB HARDDRIVE"'')
    (guard "usb-uas-vendor" "hw/usb/dev-uas.c" ".idVendor          = 0x1e01," "0x46f4")
    (guard "usb-hub-no-strings" "hw/usb/dev-hub.c" ".iManufacturer     = 0," "[STR_")
    (guard "usb-hub-no-serial" "hw/usb/dev-hub.c" ".iSerialNumber     = 0," "usb_desc_create_serial")
    (guard "usb-serial-ftdi" "hw/usb/dev-serial.c" ''"Test Serial Name"'' ''"QEMU USB SERIAL"'')
    (guard "usb-serial-always-plugged" "hw/usb/dev-serial.c" "always_plugged, true),"
      "always_plugged, false),"
    )
    (guard "usb-braille-maker" "hw/usb/dev-serial.c" ".iManufacturer     = STR_MANUFACTURER_BRAILLE,"
      ''"QEMU USB BAUM BRAILLE"''
    )
    (guard "usb-ccid-name" "hw/usb/dev-smartcard-reader.c" ''"Test Card Name"'' ''"QEMU USB CCID",'')
    (guard "usb-u2f-vendor" "hw/usb/u2f.c" "U2F_KEY_VENDOR_NUM     0x1e09" "0x46f4")
    (guard "usb-u2f-no-serial" "hw/usb/u2f.c" ".iSerialNumber     = 0," "usb_desc_create_serial")
    (guard "usb-wacom-maker" "hw/usb/dev-wacom.c" ''"Test Tablet Maker"'' ''= "QEMU",'')
    (guard "usb-wacom-no-serial" "hw/usb/dev-wacom.c" ".iSerialNumber     = 0,"
      "usb_desc_create_serial"
    )
    (guard "usb-audio-vendor" "hw/usb/dev-audio.c" "USBAUDIO_VENDOR_NUM     0x1e0b" "0x46f4")
    (guard "usb-audio-no-serial" "hw/usb/dev-audio.c" ".iSerialNumber     = 0,"
      "usb_desc_create_serial"
    )
    (guard "usb-mtp-vendor" "hw/usb/dev-mtp.c" ".idVendor          = 0x1e0e," "0x46f4")
    (guard "usb-mtp-maker" "hw/usb/dev-mtp.c" ''MTP_MANUFACTURER  "Test Phone Maker"''
      ''"QEMU filesharing"''
    )
    (guard "usb-mtp-info-version" "hw/usb/dev-mtp.c" ''usb_mtp_add_wstr(d, L"9.1");''
      ''usb_mtp_add_wstr(d, L"0.1");''
    )
    (guard "usb-mtp-info-serial" "hw/usb/dev-mtp.c"
      "usb_mtp_add_str(d, usb_desc_get_string(&s->dev, STR_SERIALNUMBER));"
      "0123456789abcdef"
    )
    (guard "usb-serial-ftdi-ids" "hw/usb/dev-serial.c" ".idProduct         = 0x2e06,"
      ''"QEMU USB SERIAL"''
    )
    (guard "usb-net-vendor" "hw/usb/dev-network.c" "RNDIS_VENDOR_NUM        0x1e0e"
      ''"QEMU USB RNDIS Net"''
    )
    (guard "usb-net-rndis-vendor-id" "hw/usb/dev-network.c" "s->vendorid = 0;" "s->vendorid = 0x1234;")
    (guard "vmgenid-hid" "hw/acpi/vmgenid.c" ''"Test_Gen_Counter"'' "QEMUVGID")
    (guard "megasas-package" "hw/scsi/megasas.c" ''"9.87.6-5432"'' ''"%s-QEMU"'')
    (guard "megasas-hba-serial" "hw/scsi/megasas.c" ''MEGASAS_HBA_SERIAL "TQ"'' "QEMU123456")
    (guard "acpi-default-header-oem" "hw/acpi/core.c" ''"TESTIDTESTTBL1\1\0\0\0"'' "QEMUQEQEMUQEMU")
    (guard "acpi-default-header-creator" "hw/acpi/core.c" ''"TSTC\015\014\013\012"'' ''"QEMU\1\0\0\0"'')
    (guard "megasas-serial-digits" "hw/scsi/megasas.c" "#define MEGASAS_HBA_SERIAL_DIGITS 11"
      "MEGASAS_HBA_SERIAL_DIGITS 8"
    )
    (guard "megasas-serial-from-uuid" "hw/scsi/megasas.c" "g_checksum_update(sum, qemu_uuid.data"
      "s->hba_serial = g_strdup(MEGASAS_HBA_SERIAL);"
    )
    (guard "usb-serial-vendor" "hw/usb/dev-serial.c" ".idVendor          = 0x1e05,"
      ".idProduct         = 0x6001,"
    )
    (guard "smbios-type4-cache-handles" "hw/smbios/smbios.c"
      "t->l1_cache_handle = cpu_to_le16(type4.l1_cache_handle);"
      "cpu_to_le16(0xFFFF); /* N/A */"
    )
    (guard "smbios-type4-voltage" "hw/smbios/smbios.c" "t->voltage = type4.voltage;" "t->voltage = 0;")
    (guard "smbios-type4-external-clock" "hw/smbios/smbios.c"
      "t->external_clock = cpu_to_le16(type4.external_clock);"
      "t->external_clock = cpu_to_le16(0); /* Unknown */"
    )
    (guard "smbios-type4-upgrade" "hw/smbios/smbios.c" "t->processor_upgrade = type4.upgrade;"
      "t->processor_upgrade = 0x01; /* Other */"
    )
    (guard "smbios-type4-characteristics" "hw/smbios/smbios.c"
      "t->processor_characteristics = cpu_to_le16(type4.characteristics);"
      "t->processor_characteristics = cpu_to_le16(0x02); /* Unknown */"
    )
    (guard "smbios-type4-family-byte" "hw/smbios/smbios.c"
      "t->processor_family = type4.processor_family < 0xfe ? type4.processor_family : 0xfe;"
      "t->processor_family = 0xfe; /* use Processor Family 2 field */"
    )
    (guard "smbios-type4-single-socket" "hw/smbios/smbios.c"
      ''snprintf(sock_str, sizeof(sock_str), "%s", type4.sock_pfx);''
      "/* N/A */"
    )
    (guard "smbios-type4-version-from-cpu" "hw/smbios/smbios.c"
      ''object_property_get_str(OBJECT(first_cpu), "model-id", NULL);''
      "SMBIOS_TABLE_SET_STR(4, processor_version_str, type4.version);"
    )
    (guard "smbios-type8-internal-connector" "hw/smbios/smbios.c"
      "t->internal_connector_type = t8->internal_connector_type;"
      "t->internal_connector_type = 0x0;"
    )
    (guard "smbios-type9-no-bus-address" "hw/smbios/smbios.c"
      "t->segment_group_number = cpu_to_le16(0xffff);"
      "t->segment_group_number = 0xff;"
    )
    (guard "smbios-memory-type" "hw/smbios/smbios.c" "#define SMBIOS_MEMORY_TYPE 0x23"
      "t->memory_type = size ? 0x07"
    )
    (guard "smbios-memory-type-detail" "hw/smbios/smbios.c" "#define SMBIOS_MEMORY_TYPE_DETAIL 0x2080"
      "cpu_to_le16(size ? 0x02 : 0x04)"
    )
    (guard "smbios-memory-rank" "hw/smbios/smbios.c" "#define SMBIOS_MEMORY_RANK 3"
      "t->attributes = 0; /* Unknown */"
    )
    (guard "smbios-memory-voltage" "hw/smbios/smbios.c" "#define SMBIOS_MEMORY_VOLTAGE_MV 1350"
      "t->configured_voltage = cpu_to_le16(0); /* Unknown */"
    )
    (guard "smbios-memory-ecc-width" "hw/smbios/smbios.c" "#define SMBIOS_MEMORY_TOTAL_WIDTH 72"
      "t->total_width = cpu_to_le16(0xFFFF); /* Unknown */"
    )
    {
      name = "mch-device-id";
      path = "include/hw/pci/pci_ids.h";
      pattern = "PCI_DEVICE_ID_INTEL_P35_MCH      0x29c0";
    }
    {
      name = "lpc-device-id";
      path = "include/hw/pci/pci_ids.h";
      pattern = "PCI_DEVICE_ID_INTEL_ICH9_8       0x2918";
    }
    {
      name = "smbus-device-id";
      path = "include/hw/pci/pci_ids.h";
      pattern = "PCI_DEVICE_ID_INTEL_ICH9_6       0x2930";
    }
    {
      name = "ahci-device-id";
      path = "include/hw/pci/pci.h";
      pattern = "PCI_DEVICE_ID_INTEL_82801IR      0x2922";
    }
    {
      name = "lpc-vendor-intel";
      path = "hw/isa/lpc_ich9.c";
      pattern = "k->vendor_id = PCI_VENDOR_ID_INTEL;";
      absent = "k->vendor_id = PCI_VENDOR_ID_AMD;";
    }
    {
      name = "smbus-vendor-intel";
      path = "hw/i2c/smbus_ich9.c";
      pattern = "k->vendor_id = PCI_VENDOR_ID_INTEL;";
      absent = "k->vendor_id = PCI_VENDOR_ID_AMD;";
    }
    {
      name = "ahci-vendor-intel";
      path = "hw/ide/ich.c";
      pattern = "k->vendor_id = PCI_VENDOR_ID_INTEL;";
      absent = "k->vendor_id = PCI_VENDOR_ID_AMD;";
    }
    (guard "fadt-plvl2-lat" "hw/i386/acpi-build.c" ".plvl2_lat = 0x63 /*" ".plvl2_lat = 0x0065")
    (guard "hv-max-vps" "target/i386/cpu.c" "hv_max_vps, 0x140)," "hv_max_vps, -1),")
    (guard "hv-max-lps" "target/i386/cpu.c" "cpu->hyperv_limits[0] = 0x200;"
      "cpu->hyperv_limits[0] = 64;"
    )
    (guard "acpi-cpu-hotplug-uid" "hw/acpi/cpu.c" "aml_int(1)" ''aml_string("CPU Hotplug resources")'')
    (guard "acpi-smi-uid" "hw/i386/acpi-build.c" "aml_int(2)" ''aml_string("SMI resources")'')
    (guard "acpi-pci-hotplug-uid" "hw/acpi/pcihp.c" "aml_int(3)"
      ''aml_string("PCI Hotplug resources")''
    )
    (guard "acpi-memory-hotplug-uid" "hw/acpi/memory_hotplug.c" "aml_int(4)"
      ''aml_string("Memory hotplug resources")''
    )
    (guard "kvm-hypercall-quirk" "target/i386/kvm/kvm.c"
      "uint64_t quirks = KVM_X86_QUIRK_FIX_HYPERCALL_INSN;"
      "failed to keep KVM_X86_QUIRK_FIX_HYPERCALL_INSN"
    )
    (guard "fadt-plvl3-lat" "hw/i386/acpi-build.c" ".plvl3_lat = 0x3e7 /*" ".plvl3_lat = 0x03e9")
    (
      if waet then
        {
          name = "waet-table";
          path = "hw/i386/acpi-build.c";
          pattern = "    build_waet(tables_blob, tables->linker, x86ms->oem_id, x86ms->oem_table_id);";
        }
      else
        guard "waet-table-absent" "hw/i386/acpi-build.c" "Add tables supplied by user"
          "build_waet(tables_blob"
    )
    {
      name = "ich9-lpc-dev-stock-q35";
      path = "include/hw/southbridge/ich9.h";
      pattern = "#define ICH9_LPC_DEV                            31";
    }
    {
      name = "ich9-lpc-func-stock-q35";
      path = "include/hw/southbridge/ich9.h";
      pattern = "#define ICH9_LPC_FUNC                           0";
    }
    {
      name = "ich9-sata-dev-stock-q35";
      path = "include/hw/southbridge/ich9.h";
      pattern = "#define ICH9_SATA1_DEV                          31";
    }
    {
      name = "ich9-smb-dev-stock-q35";
      path = "include/hw/southbridge/ich9.h";
      pattern = "#define ICH9_SMB_DEV                            31";
    }
    {
      name = "mch-vendor-intel";
      path = "hw/pci-host/q35.c";
      pattern = "k->vendor_id = PCI_VENDOR_ID_INTEL;";
      absent = "k->vendor_id = PCI_VENDOR_ID_AMD;";
    }
    {
      name = "ich9-lpc-revision-stock";
      path = "include/hw/southbridge/ich9.h";
      pattern = "#define ICH9_A2_LPC_REVISION                    0x2";
      absent = "ICH9_A2_LPC_REVISION                    0x51";
    }
    {
      name = "ich9-smb-revision-stock";
      path = "include/hw/southbridge/ich9.h";
      pattern = "#define ICH9_A2_SMB_REVISION                    0x02";
      absent = "ICH9_A2_SMB_REVISION                    0x71";
    }
    {
      name = "acpi-name-ich9-usb";
      path = "hw/acpi/pcihp.c";
      pattern = ''else sprintf(name, "USB%X", func + 1);'';
    }
    {
      name = "acpi-name-xhci-from-one";
      path = "hw/acpi/pcihp.c";
      pattern = ''sprintf(name, "XHC%X", func + 1);'';
    }
    {
      name = "acpi-name-lpcb-follows-lpc";
      path = "hw/acpi/pcihp.c";
      pattern = "// Slot 31 (0x1F): LPC / SMBus / SATA 2";
    }
  ];

  guardCheck = g: ''
    if ! grep -qF -- ${lib.escapeShellArg g.pattern} ${lib.escapeShellArg g.path}; then
      echo "  FAIL: ${g.name}: expected pattern not found in ${g.path}: ${g.pattern}"
      exit 1
    fi
    ${lib.optionalString (g ? absent) ''
      if grep -qF -- ${lib.escapeShellArg g.absent} ${lib.escapeShellArg g.path}; then
        echo "  FAIL: ${g.name}: ${g.path} still holds ${g.absent}"
        exit 1
      fi
    ''}
  '';

  allGuardChecks = lib.concatMapStringsSep "\n" guardCheck guards;
in
runCommand "sed-contract-qemu-${cpuVendor}" { } ''
    src=$(mktemp -d)
    tar -xf ${qemu-stealth.src} -C "$src" --strip-components=1
    chmod -R u+w "$src"
    cd "$src"
    ${nixpkgsPatches}
    ${postPatch}
    echo "=== sed-contract-qemu-${cpuVendor}: per-sed guard assertions ==="
  ${allGuardChecks}
    echo "sed-contract-qemu-${cpuVendor}: all ${toString (lib.length guards)} guards passed"
    touch $out
''
