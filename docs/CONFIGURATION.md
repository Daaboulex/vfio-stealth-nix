# Configuration notes

What the option list cannot say by itself: what the module does with its options, which kernel features the Hyper-V options need, and the build arguments of `qemu-stealth`, which are not module options. Every option with its type and default is in [OPTIONS.md](OPTIONS.md).

The module itself acts on few of these options. It sets the kernel parameters
and `/etc/swtpm-localca.options`, checks assertions, warns about placeholder
values, and fills the two read-only outputs listed last in [OPTIONS.md](OPTIONS.md). It
defines no VM and picks no package. Most other options hold the values the
caller passes to `lib.mkStealthFeatures`, and a description there that says
what happens in the VM is true once the caller has placed the function's
result in its VM definition.

## Hyper-V features

Of the 13 Hyper-V enlightenment features exposed by this module, only
`vendor_id` and `relaxed` are unconditional (no KVM cap; libvirt-level
settings). The other 11 all require `CONFIG_KVM_HYPERV=y` in the host
kernel — verified against `arch/x86/kvm/x86.c:4817-4831` in the Linux
kernel source, which puts every relevant `KVM_CAP_HYPERV_*` cap in a
single `#ifdef CONFIG_KVM_HYPERV` block. To check your kernel:

```sh
zcat /proc/config.gz | grep KVM_HYPERV
```

## Kernel capabilities

`hypervFeatures.*` controls what the lib *requests*; `kernelCapabilities`
controls what the host kernel can actually *provide*. The lib intersects
the two: a feature is emitted only if both the user requests it AND the
host kernel supports it. Features that are requested but unsupported are
dropped from the output, and the VM starts without the dropped feature (no
libvirt error). For each dropped feature the function returns one message in
`warnings`, naming the missing `CONFIG_*` option. The function emits nothing
itself: the caller adds that list to its own `warnings`.

Set the attrset by hand. A key left out counts as unsupported, `vendor_id`
and `relaxed` included, so the set names all 13 features:

```nix
virtualisation.vfio-stealth.kernelCapabilities = {
  vendor_id = true;
  relaxed = true;
  vapic = true;
  spinlocks = true;
  frequencies = true;
  vpindex = true;
  synic = true;
  stimer = true;
  reset = true;
  ipi = true;
  tlbflush = true;
  reenlightenment = true;
  runtime = true;
};
```

[`lib/kernel-capabilities.nix`](../lib/kernel-capabilities.nix) holds
`fromConfigText` and `fromConfigPath`, which parse a kernel `.config` into
this attrset, and `emptyCapabilities` (all features = false). The file is not
a flake output: `lib` exports `mkStealthFeatures` only.

## Build-time qemu-stealth arguments

These are NOT module options. Pass them via `callPackage` or an overlay
override, e.g.:

```nix
nixpkgs.overlays = [
  (final: prev: {
    qemu-stealth = prev.qemu-stealth.override {
      edidManufacturer = "ASU";
      edidSerial = "PG279Q";
      diskModel = "Samsung SSD 990 PRO 2TB ";
    };
  })
];
```

### EDID (display identity)

The module also exposes `virtualisation.vfio-stealth.edid.*` options
(`manufacturer`, `serial`, `productCode`, `dpi`, `week`, `year`) that
document the target EDID values for discoverability. The actual EDID
binary is compiled by the build-time arguments below.

| Argument           | Default     | Description                        | Detection vector                |
| ------------------ | ----------- | ---------------------------------- | ------------------------------- |
| `edidManufacturer` | `"ACI"`     | 3-letter EDID manufacturer ID      | Monitor manufacturer identifier |
| `edidSerial`       | `"VG248QE"` | Monitor serial string              | EDID serial number              |
| `edidProductCode`  | `"0x2480"`  | EDID product code (hex)            | EDID product code field         |
| `edidDpi`          | `91`        | Monitor DPI                        | EDID physical size calculation  |
| `edidWeek`         | `22`        | Manufacture week (1-52)            | EDID manufacture date           |
| `edidYear`         | `2020`      | Manufacture year                   | EDID manufacture date           |
| `edidResX`         | `1920`      | Default EDID horizontal resolution | EDID preferred timing           |
| `edidResY`         | `1080`      | Default EDID vertical resolution   | EDID preferred timing           |

### Disk / optical

The module also exposes `virtualisation.vfio-stealth.disk.*` options (`model`,
`serial`, `opticalModel`) that document the target disk identity values
for discoverability. The actual strings are compiled into QEMU by the
build-time arguments below.

| Argument            | Default                       | Description                                                        | Detection vector                    |
| ------------------- | ----------------------------- | ------------------------------------------------------------------ | ----------------------------------- |
| `diskModel`         | `"WDC WD10EZEX-00WN4A0     "` | IDE/SCSI disk model string (25 chars, space-padded)                | Disk model reveals QEMU default     |
| `diskSerial`        | `"Default string"`            | IDE disk serial string (replaces AutoVirt blank serial)            | Blank disk serial is a VM indicator |
| `opticalModel`      | `"HL-DT-ST DVDRAM GH24NSC0 "` | IDE/ATAPI optical drive model string (25 chars)                    | Optical drive model reveals QEMU    |
| `scsiVendor`        | `"WDC"`                       | SCSI INQUIRY vendor string (8-char T10 format, auto-padded)        | SCSI vendor reveals QEMU default    |
| `scsiTargetProduct` | `"SCSI Disk       "`          | SCSI target product for dead-LUN INQUIRY fallback (16-char padded) | SCSI target product reveals QEMU    |

### ACPI OEM

The module also exposes `virtualisation.vfio-stealth.acpiOem.*` options (`id`,
`tableId`) that document the target ACPI OEM identity values for
discoverability. The actual table headers are compiled into QEMU by the
build-time arguments below.

| Argument         | Default      | Description                     | Detection vector               |
| ---------------- | ------------ | ------------------------------- | ------------------------------ |
| `acpiOemId`      | `"ALASKA"`   | 6-char ACPI OEM ID              | ACPI table OEM ID reveals QEMU |
| `acpiOemTableId` | `"A M I   "` | 8-char padded ACPI OEM Table ID | ACPI table OEM Table ID        |
