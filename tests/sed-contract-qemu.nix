{
  lib,
  runCommand,
  fetchurl,
  inputs,
}:

let
  qemuTarball = fetchurl {
    url = "https://download.qemu.org/qemu-11.0.1.tar.xz";
    sha256 = "sha256-DSNfWCAnjZFKMVXsJ6+OQljWl+qJKJVXCAfWnAy4zWQ=";
  };
  autovirtPatch = "${inputs.autovirt}/patches/QEMU/AMD-v11.0.0.patch";

  postPatch = import ../qemu/post-patch.nix {
    inherit lib;
    inherit (inputs) autovirt;
    edidManufacturer = "ACI";
    edidSerial = "VG248QE";
    edidProductCode = "0x2480";
    edidDpi = 91;
    edidWeek = 22;
    edidYear = 2020;
    edidResX = 1920;
    edidResY = 1080;
    acpiOemId = "ALASKA";
    acpiOemTableId = "A M I   ";
    diskModel = "WDC WD10EZEX-00WN4A0     ";
    diskSerial = "Default string";
    opticalModel = "HL-DT-ST DVDRAM GH24NSC0 ";
    scsiVendor = "WDC";
    scsiTargetProduct = "SCSI Disk       ";
  };

  # Per-sed guard: (name, file path inside the source tree, pattern the sed
  # is required to leave in the post-patch file). If the postPatch's FATAL
  # guard passed but the post-patch file does not contain the pattern, the
  # sed was a silent no-op — the contract test catches it here.
  guards = [
    {
      name = "edid-manufacturer";
      path = "hw/display/edid-generate.c";
      pattern = "ACI";
    }
    {
      name = "edid-serial";
      path = "hw/display/edid-generate.c";
      pattern = "VG248QE";
    }
    {
      name = "edid-product-code";
      path = "hw/display/edid-generate.c";
      pattern = "0x2480";
    }
    {
      name = "edid-week";
      path = "hw/display/edid-generate.c";
      pattern = "edid[16] = 22;";
    }
    {
      name = "edid-year";
      path = "hw/display/edid-generate.c";
      pattern = "2020 - 1990";
    }
    {
      name = "edid-dpi";
      path = "hw/display/edid-generate.c";
      pattern = "uint32_t dpi = 91;";
    }
    {
      name = "edid-resx";
      path = "hw/display/edid-generate.c";
      pattern = "info->prefx = 1920;";
    }
    {
      name = "edid-resy";
      path = "hw/display/edid-generate.c";
      pattern = "info->prefy = 1080;";
    }
    {
      name = "scsi-bus-vendor";
      path = "hw/scsi/scsi-bus.c";
      pattern = "WDC";
    }
    {
      name = "scsi-bus-target-prod";
      path = "hw/scsi/scsi-bus.c";
      pattern = "SCSI Disk";
    }
    {
      name = "scsi-disk-product";
      path = "hw/scsi/scsi-disk.c";
      pattern = "WDC WD10EZEX-00WN4A0";
    }
    {
      name = "scsi-cdrom-product";
      path = "hw/scsi/scsi-disk.c";
      pattern = "HL-DT-ST DVDRAM GH24NSC0";
    }
    {
      name = "scsi-disk-vendor";
      path = "hw/scsi/scsi-disk.c";
      pattern = "WDC";
    }
    {
      name = "acpi-oem-id";
      path = "include/hw/acpi/aml-build.h";
      pattern = ''"ALASKA"'';
    }
    {
      name = "acpi-oem-table-id";
      path = "include/hw/acpi/aml-build.h";
      pattern = ''"A M I   "'';
    }
    {
      name = "ide-main-disk";
      path = "hw/ide/core.c";
      pattern = "WDC WD10EZEX-00WN4A0";
    }
    {
      name = "ide-cfata";
      path = "hw/ide/core.c";
      pattern = "WDC WD10EZEX-00WN4A0";
    }
    {
      name = "ide-serial";
      path = "hw/ide/core.c";
      pattern = "pstrcpy(s->drive_serial_str";
    }
    {
      name = "ide-optical";
      path = "hw/ide/core.c";
      pattern = "HL-DT-ST DVDRAM GH24NSC0";
    }
    {
      name = "mch-device-id";
      path = "include/hw/pci/pci_ids.h";
      pattern = "PCI_DEVICE_ID_INTEL_P35_MCH      0x29c0";
    }
    {
      name = "mch-vendor-intel";
      path = "hw/pci-host/q35.c";
      pattern = "k->vendor_id = PCI_VENDOR_ID_INTEL;";
    }
    {
      name = "gpex-vendor-amd";
      path = "hw/pci-host/gpex.c";
      pattern = "k->vendor_id = PCI_VENDOR_ID_AMD;";
    }
    {
      name = "fadt-plvl2-lat";
      path = "hw/i386/acpi-build.c";
      pattern = ".plvl2_lat = 0xfff";
    }
    {
      name = "fadt-plvl3-lat";
      path = "hw/i386/acpi-build.c";
      pattern = ".plvl3_lat = 0xfff";
    }
    {
      name = "waet-table";
      path = "hw/i386/acpi-build.c";
      pattern = "build_waet";
    }
  ];

  # Render each guard as a shell fragment: a `grep -F` test that returns
  # 0 (pass) or 1 (fail), with a clear diagnostic message.
  guardCheck = g: ''
    if ! grep -qF -- ${lib.escapeShellArg g.pattern} ${lib.escapeShellArg g.path}; then
      echo "  FAIL: ${g.name} — expected pattern not found in ${g.path}: ${g.pattern}"
      exit 1
    fi
  '';

  allGuardChecks = lib.concatMapStringsSep "\n" guardCheck guards;
in
# Apply the AutoVirt QEMU patch + our postPatch to a fresh source tree.
# The postPatch's FATAL guards fire as part of this runCommand — if any
# sed no-ops, the build aborts here.
#
# After the postPatch, the per-sed grep guards run for the per-sed
# diagnosis (catches silent no-ops the FATAL might miss).
runCommand "sed-contract-qemu" { } ''
    src=$(mktemp -d)
    tar -xf ${qemuTarball} -C "$src" --strip-components=1
    chmod -R u+w "$src"
    cd "$src"
    patch -p1 -i ${autovirtPatch}
    ${postPatch}
    echo "=== sed-contract-qemu: per-sed guard assertions ==="
  ${allGuardChecks}
    echo "sed-contract-qemu: all ${toString (lib.length guards)} guards passed"
    touch $out
''
