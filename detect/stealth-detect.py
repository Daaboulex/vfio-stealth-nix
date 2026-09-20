#!/usr/bin/env python3
"""Report, per vector, whether an aarch64 guest can tell it is virtualized.

Exit 1 when any vector reports "detected", 0 otherwise. A vector that cannot be
read reports "unknown" and never "clean": an unreadable source is an absent
measurement, not a passing one.
"""

from __future__ import annotations

import argparse
import json
import struct
import sys
from dataclasses import dataclass
from pathlib import Path

DETECTED = "detected"
CLEAN = "clean"
UNKNOWN = "unknown"

DEVICE_TREE = "proc/device-tree"
CPU0_MIDR = "sys/devices/system/cpu/cpu0/regs/identification/midr_el1"
DMI_ID = "sys/class/dmi/id"
ACPI_TABLES = "sys/firmware/acpi/tables"
VIRTIO_BUS = "sys/bus/virtio/devices"
PCI_BUS = "sys/bus/pci/devices"

QEMU_VIRT_COMPATIBLE = "linux,dummy-virt"
QEMU_VIRT_TIMER_HZ = 62500000

FADT_REVISION_OFFSET = 8
FADT_REVISION_WITH_HYPERVISOR_ID = 6
FADT_HYPERVISOR_ID_OFFSET = 268
FADT_HYPERVISOR_ID_END = FADT_HYPERVISOR_ID_OFFSET + 8

HYPERVISOR_STRINGS = (
    "ArmVirt",
    "BHYVE",
    "Bochs",
    "EFI Development Kit",
    "KVM",
    "OVMF",
    "QEMU",
    "Red Hat",
    "SeaBIOS",
    "Virtual Machine",
    "Xen",
    "edk2",
)

ACPI_OEM_STRINGS = ("BOCHS", "BXPC", "LINUX", "QEMU", "VRTUAL")

PARAVIRT_PCI_VENDORS = {
    0x1AF4: "Red Hat / virtio",
    0x1B36: "Red Hat / QEMU PCI",
    0x5853: "XenSource",
}

ARM_IMPLEMENTERS = {
    0x41: "ARM",
    0x42: "Broadcom",
    0x43: "Cavium",
    0x44: "DEC",
    0x46: "Fujitsu",
    0x48: "HiSilicon",
    0x49: "Infineon",
    0x4D: "Motorola",
    0x4E: "NVIDIA",
    0x50: "Applied Micro",
    0x51: "Qualcomm",
    0x53: "Samsung",
    0x56: "Marvell",
    0x61: "Apple",
    0x66: "Faraday",
    0x69: "Intel",
    0x6D: "Microsoft",
    0x70: "Phytium",
    0xC0: "Ampere",
}

DMI_FIELDS = (
    "bios_vendor",
    "bios_version",
    "board_vendor",
    "chassis_vendor",
    "product_name",
    "sys_vendor",
)


@dataclass(frozen=True)
class Sources:
    device_tree: Path
    cpu0_midr: Path
    dmi_id: Path
    acpi_tables: Path
    virtio_bus: Path
    pci_bus: Path

    @classmethod
    def under(cls, root: Path) -> Sources:
        return cls(
            device_tree=root / DEVICE_TREE,
            cpu0_midr=root / CPU0_MIDR,
            dmi_id=root / DMI_ID,
            acpi_tables=root / ACPI_TABLES,
            virtio_bus=root / VIRTIO_BUS,
            pci_bus=root / PCI_BUS,
        )


@dataclass
class Finding:
    vector: str
    verdict: str
    evidence: str


def read_bytes(path: Path) -> bytes | None:
    try:
        return path.read_bytes()
    except OSError:
        return None


def read_line(path: Path) -> str | None:
    raw = read_bytes(path)
    if raw is None:
        return None
    return raw.decode("utf-8", "replace").strip().strip("\0")


def device_tree_strings(src: Sources, relative: str) -> list[str] | None:
    raw = read_bytes(src.device_tree / relative)
    if raw is None:
        return None
    return [s for s in raw.decode("ascii", "replace").split("\0") if s]


def matching_markers(haystack: str, markers) -> list[str]:
    lowered = haystack.lower()
    return [m for m in markers if m.lower() in lowered]


def hypervisor_node(src: Sources) -> Finding:
    if not src.device_tree.is_dir():
        return Finding("dt-hypervisor-node", UNKNOWN, f"no {src.device_tree}")
    compatible = device_tree_strings(src, "hypervisor/compatible")
    if compatible is None:
        return Finding(
            "dt-hypervisor-node", CLEAN, "device tree declares no hypervisor node"
        )
    return Finding(
        "dt-hypervisor-node",
        DETECTED,
        "hypervisor/compatible = " + ", ".join(compatible),
    )


def machine_compatible(src: Sources) -> Finding:
    compatible = device_tree_strings(src, "compatible")
    if compatible is None:
        return Finding(
            "dt-machine-compatible", UNKNOWN, f"no {src.device_tree}/compatible"
        )
    joined = ", ".join(compatible)
    if QEMU_VIRT_COMPATIBLE in compatible:
        return Finding("dt-machine-compatible", DETECTED, "compatible = " + joined)
    return Finding("dt-machine-compatible", CLEAN, "compatible = " + joined)


def cpu_identity(src: Sources) -> Finding:
    raw = read_line(src.cpu0_midr)
    if raw is None:
        return Finding("cpu-identity", UNKNOWN, f"cannot read {src.cpu0_midr}")
    midr = int(raw, 16)
    implementer = (midr >> 24) & 0xFF
    variant = (midr >> 20) & 0xF
    part = (midr >> 4) & 0xFFF
    revision = midr & 0xF
    name = ARM_IMPLEMENTERS.get(implementer)
    evidence = (
        f"MIDR_EL1 = {midr:#010x} implementer={implementer:#04x}"
        f" ({name or 'unassigned'}) part={part:#05x} variant={variant} revision={revision}"
    )
    if name is None:
        return Finding("cpu-identity", DETECTED, evidence)
    return Finding("cpu-identity", CLEAN, evidence)


def dmi_identity(src: Sources) -> Finding:
    if not src.dmi_id.is_dir():
        return Finding(
            "dmi-identity", UNKNOWN, f"no {src.dmi_id} (guest exposes no SMBIOS)"
        )
    hits: list[str] = []
    seen: list[str] = []
    for field in DMI_FIELDS:
        value = read_line(src.dmi_id / field)
        if value is None:
            continue
        seen.append(f"{field}={value}")
        for marker in matching_markers(value, HYPERVISOR_STRINGS):
            hits.append(f"{field} contains {marker!r}")
    if not seen:
        return Finding("dmi-identity", UNKNOWN, "no readable DMI field")
    if hits:
        return Finding("dmi-identity", DETECTED, "; ".join(hits))
    return Finding("dmi-identity", CLEAN, "; ".join(seen))


def acpi_oem(src: Sources) -> Finding:
    if not src.acpi_tables.is_dir():
        return Finding(
            "acpi-oem",
            UNKNOWN,
            f"no {src.acpi_tables} (guest booted without ACPI)",
        )
    hits: list[str] = []
    read_any = False
    try:
        tables = sorted(src.acpi_tables.iterdir())
    except OSError as exc:
        return Finding("acpi-oem", UNKNOWN, f"cannot list {src.acpi_tables}: {exc}")
    for table in tables:
        header = read_bytes(table)
        if header is None or len(header) < 24:
            continue
        read_any = True
        oem_id = header[10:16].decode("ascii", "replace").strip()
        oem_table_id = header[16:24].decode("ascii", "replace").strip()
        for marker in matching_markers(oem_id + " " + oem_table_id, ACPI_OEM_STRINGS):
            hits.append(
                f"{table.name}: OEM {oem_id!r}/{oem_table_id!r} contains {marker!r}"
            )
    if not read_any:
        return Finding("acpi-oem", UNKNOWN, "no ACPI table header was readable")
    if hits:
        return Finding("acpi-oem", DETECTED, "; ".join(hits))
    return Finding(
        "acpi-oem", CLEAN, f"{len(tables)} ACPI tables carry no emulator OEM string"
    )


def virtio_bus(src: Sources) -> Finding:
    if not src.virtio_bus.is_dir():
        return Finding(
            "virtio-bus",
            UNKNOWN,
            f"no {src.virtio_bus} (driver absent, not proof of absence)",
        )
    devices = sorted(p.name for p in src.virtio_bus.iterdir())
    if devices:
        return Finding("virtio-bus", DETECTED, "virtio devices: " + ", ".join(devices))
    return Finding("virtio-bus", CLEAN, "virtio bus present but carries no device")


def pci_vendor(src: Sources) -> Finding:
    if not src.pci_bus.is_dir():
        return Finding("pci-vendor", UNKNOWN, f"no {src.pci_bus}")
    hits: list[str] = []
    count = 0
    for device in sorted(src.pci_bus.iterdir()):
        value = read_line(device / "vendor")
        if value is None:
            continue
        count += 1
        vendor = int(value, 16)
        label = PARAVIRT_PCI_VENDORS.get(vendor)
        if label is not None:
            hits.append(f"{device.name}: vendor {vendor:#06x} ({label})")
    if count == 0:
        return Finding("pci-vendor", UNKNOWN, "no PCI device exposed a vendor id")
    if hits:
        return Finding("pci-vendor", DETECTED, "; ".join(hits))
    return Finding(
        "pci-vendor", CLEAN, f"{count} PCI devices, no paravirtual vendor id"
    )


def timer_frequency(src: Sources) -> Finding:
    raw = read_bytes(src.device_tree / "timer/clock-frequency")
    if raw is None or len(raw) != 4:
        return Finding(
            "timer-frequency", UNKNOWN, f"no {src.device_tree}/timer/clock-frequency"
        )
    (hz,) = struct.unpack(">I", raw)
    evidence = f"arch timer = {hz} Hz"
    if hz == QEMU_VIRT_TIMER_HZ:
        return Finding("timer-frequency", DETECTED, evidence + " (QEMU virt default)")
    return Finding("timer-frequency", CLEAN, evidence)


def acpi_hypervisor_id(src: Sources) -> Finding:
    raw = read_bytes(src.acpi_tables / "FACP")
    if raw is None:
        return Finding("acpi-hypervisor-id", UNKNOWN, f"no {src.acpi_tables}/FACP")
    if len(raw) < FADT_REVISION_OFFSET + 1:
        return Finding("acpi-hypervisor-id", UNKNOWN, "FADT shorter than its header")
    revision = raw[FADT_REVISION_OFFSET]
    if revision < FADT_REVISION_WITH_HYPERVISOR_ID:
        return Finding(
            "acpi-hypervisor-id",
            UNKNOWN,
            f"FADT revision {revision} predates the hypervisor vendor identity field",
        )
    if len(raw) < FADT_HYPERVISOR_ID_END:
        return Finding(
            "acpi-hypervisor-id",
            UNKNOWN,
            f"FADT revision {revision} is {len(raw)} bytes,"
            f" too short to hold the field at {FADT_HYPERVISOR_ID_OFFSET}",
        )
    field = raw[FADT_HYPERVISOR_ID_OFFSET:FADT_HYPERVISOR_ID_END]
    vendor = field.rstrip(b"\0").decode("ascii", "replace").strip()
    if vendor:
        return Finding(
            "acpi-hypervisor-id",
            DETECTED,
            f"FADT hypervisor vendor identity = {vendor!r}",
        )
    return Finding(
        "acpi-hypervisor-id", CLEAN, "FADT hypervisor vendor identity is empty"
    )


def psci_conduit(src: Sources) -> Finding:
    method = device_tree_strings(src, "psci/method")
    if method is None:
        return Finding("dt-psci-conduit", UNKNOWN, f"no {src.device_tree}/psci/method")
    joined = ", ".join(method)
    if "hvc" in method:
        return Finding(
            "dt-psci-conduit",
            DETECTED,
            f"psci method = {joined} (EL2 conduit; firmware uses smc)",
        )
    return Finding("dt-psci-conduit", CLEAN, f"psci method = {joined}")


VECTORS = (
    hypervisor_node,
    machine_compatible,
    cpu_identity,
    dmi_identity,
    acpi_oem,
    acpi_hypervisor_id,
    psci_conduit,
    virtio_bus,
    pci_vendor,
    timer_frequency,
)


def collect(src: Sources) -> list[Finding]:
    return [vector(src) for vector in VECTORS]


def render_text(findings: list[Finding], stream) -> None:
    width = max(len(f.vector) for f in findings)
    for finding in findings:
        print(
            f"{finding.vector:<{width}}  {finding.verdict:<8}  {finding.evidence}",
            file=stream,
        )


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--json", action="store_true", help="emit findings as JSON")
    parser.add_argument(
        "--root",
        type=Path,
        default=Path("/"),
        help="read every source under this prefix instead of / (for fixtures)",
    )
    args = parser.parse_args(argv)

    findings = collect(Sources.under(args.root))
    detected = [f for f in findings if f.verdict == DETECTED]

    if args.json:
        json.dump(
            {
                "detected": [f.vector for f in detected],
                "findings": [
                    {"vector": f.vector, "verdict": f.verdict, "evidence": f.evidence}
                    for f in findings
                ],
            },
            sys.stdout,
            indent=2,
            sort_keys=True,
        )
        sys.stdout.write("\n")
    else:
        render_text(findings, sys.stdout)
        if detected:
            print(
                "\nvirtualized: " + ", ".join(f.vector for f in detected),
                file=sys.stdout,
            )
        else:
            print("\nno vector reported virtualization", file=sys.stdout)

    return 1 if detected else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
