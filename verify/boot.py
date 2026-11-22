import itertools
import json
import os
import pathlib
import re
import shlex
import shutil
import socket
import subprocess
import sys
import time
from xml.etree import ElementTree

ATTEMPTS = 3
ATTEMPT_SECONDS = 90
DONE = "VFIO-PROBE-DONE"
REFUSED = "Access Denied"
NO_OPTION = "No bootable option or device was found"
MICROSOFT_CERTIFICATES = [
    "Microsoft Windows Production PCA 2011",
    "Windows UEFI CA 2023",
    "Microsoft Corporation UEFI CA 2011",
    "Microsoft UEFI CA 2023",
    "Microsoft Corporation KEK CA 2011",
    "Microsoft Corporation KEK 2K CA 2023",
]

plan = json.loads(pathlib.Path(sys.argv[1]).read_text())
out = pathlib.Path(sys.argv[2])
config = plan["config"]
probe = pathlib.Path(plan["probe"])
swtpm = pathlib.Path(plan["swtpm"])
vmaware_expected = set(
    json.loads(pathlib.Path(plan["vmawareExpected"]).read_text())
    .get(config["cpuVendor"], {})
    .get(config["hypervMode"] + ("" if config["acpi"]["waet"] else "-nowaet"), [])
)
serial_dir = out / "serial"
serial_dir.mkdir(parents=True)
work = pathlib.Path.cwd() / "vms"
host_cpus = itertools.cycle(sorted(os.sched_getaffinity(0)))
pinned_cpu = {}


def libvirt_argv(case, xml_path):
    result = subprocess.run(
        [
            "virsh",
            "-c",
            "qemu:///session",
            "domxml-to-native",
            "qemu-argv",
            str(xml_path),
        ],
        capture_output=True,
        text=True,
        check=False,
    )
    if result.returncode != 0:
        raise SystemExit(f"{case['name']}: libvirt refused the domain: {result.stderr}")
    tokens = shlex.split(result.stdout)
    start = next(i for i, t in enumerate(tokens) if t.endswith("qemu-system-x86_64"))
    return tokens[start:]


def adapt(argv, directory, nvram_path):
    out_argv = []
    i = 0
    while i < len(argv):
        token = argv[i]
        value = argv[i + 1] if i + 1 < len(argv) else ""
        if token == "-S":
            i += 1
            continue
        if token == "-object" and ("masterKey0" in value or "monitor-qmp" in value):
            i += 2
            continue
        if token == "-chardev" and value.startswith("socket,id=charmonitor"):
            i += 2
            continue
        if token == "-chardev" and value.startswith("null,id=chrtpm"):
            out_argv += [token, f"socket,id=chrtpm,path={directory}/swtpm.sock"]
            i += 2
            continue
        out_argv.append(
            token.replace(nvram_path, str(directory / "vars.fd")).replace(
                "/probe/", f"{directory}/"
            )
        )
        i += 1
    return [
        *out_argv,
        "-chardev",
        f"file,id=probe-serial,path={directory}/serial.log",
        "-device",
        "isa-serial,chardev=probe-serial,index=0",
        "-qmp",
        f"unix:{directory}/qmp.sock,server=on,wait=off",
    ]


def start_tpm(directory):
    state = directory / "tpm"
    state.mkdir()
    localca = directory / "localca"
    localca.mkdir()
    (directory / "swtpm-localca.conf").write_text(
        f"statedir = {localca}\n"
        f"signingkey = {localca}/signkey.pem\n"
        f"issuercert = {localca}/issuercert.pem\n"
        f"certserial = {localca}/certserial\n"
    )
    (directory / "swtpm_setup.conf").write_text(
        f"create_certs_tool = {swtpm}/bin/swtpm_localca\n"
        f"create_certs_tool_config = {directory}/swtpm-localca.conf\n"
        f"create_certs_tool_options = {swtpm}/etc/swtpm-localca.options\n"
        "active_pcr_banks = sha256\n"
    )
    subprocess.run(
        [
            "swtpm_setup",
            "--tpm2",
            "--tpmstate",
            str(state),
            "--create-ek-cert",
            "--create-platform-cert",
            "--config",
            str(directory / "swtpm_setup.conf"),
            "--write-ek-cert-files",
            str(state),
        ],
        check=True,
        capture_output=True,
    )
    return subprocess.Popen(
        [
            "swtpm",
            "socket",
            "--tpm2",
            "--tpmstate",
            f"dir={state}",
            "--ctrl",
            f"type=unixio,path={directory}/swtpm.sock",
            "--flags",
            "startup-clear",
        ]
    )


def start(case, attempt):
    directory = work / case["name"] / f"attempt-{attempt}"
    directory.mkdir(parents=True)
    for name in ("unsigned.img", "signed.img", "unsigned.iso"):
        subprocess.run(
            ["cp", "--sparse=always", str(probe / name), str(directory / name)],
            check=True,
        )
        (directory / name).chmod(0o644)
    tree = ElementTree.parse(case["xml"])
    root = tree.getroot()
    nic = []
    devices = root.find("devices")
    for interface in devices.findall("interface"):
        mac = interface.find("mac")
        model = interface.find("model").get("type")
        address = mac.get("address") if mac is not None else None
        nic += [
            "-netdev",
            "user,id=probe-net",
            "-device",
            f"{model},netdev=probe-net,bus=pcie.0,addr=0x1e"
            + (f",mac={address}" if address else ""),
        ]
        (directory / "mac").write_text(address or "")
        devices.remove(interface)
    tree.write(directory / "domain.xml")
    nvram = root.find("os/nvram")
    template = nvram.get("template").replace("/probe/", f"{probe}/")
    shutil.copy(template, directory / "vars.fd")
    (directory / "vars.fd").chmod(0o644)
    tpm = start_tpm(directory) if root.find("devices/tpm") is not None else None
    argv = (
        adapt(libvirt_argv(case, directory / "domain.xml"), directory, nvram.text) + nic
    )
    (directory / "argv.json").write_text(json.dumps(argv, indent=1))
    cpu = next(host_cpus)
    pinned_cpu[directory] = cpu
    with open(directory / "qemu.log", "w") as log:
        process = subprocess.Popen(
            argv,
            cwd=directory,
            stdout=log,
            stderr=subprocess.STDOUT,
            preexec_fn=lambda: os.sched_setaffinity(0, {cpu}),
        )
    return directory, process, tpm


def serial_text(directory):
    path = directory / "serial.log"
    if not path.exists():
        return ""
    return path.read_bytes().decode("latin-1").replace("\r", "")


def finished(case, text):
    if case["expect"].get("refused"):
        return NO_OPTION in text or DONE in text
    return DONE in text


def sections(text):
    found = {}
    for match in re.finditer(
        r"VFIO-PROBE-BEGIN (\S+)\n(.*?)VFIO-PROBE-END \1 (\d+)", text, re.DOTALL
    ):
        found[match.group(1)] = {"output": match.group(2), "exit": int(match.group(3))}
    return found


def cpuid_leaves(output):
    leaves = {}
    for match in re.finditer(
        r"^\s*(0x[0-9a-f]+) (0x[0-9a-f]+): eax=(0x[0-9a-f]+) ebx=(0x[0-9a-f]+) ecx=(0x[0-9a-f]+) edx=(0x[0-9a-f]+)",
        output.split("CPU 1:")[0],
        re.MULTILINE,
    ):
        leaf, sub = int(match.group(1), 16), int(match.group(2), 16)
        leaves.setdefault(
            (leaf, sub), tuple(int(match.group(k), 16) for k in range(3, 7))
        )
    return leaves


def register_text(*registers):
    return (
        b"".join(r.to_bytes(4, "little") for r in registers)
        .decode("latin-1")
        .rstrip("\0")
    )


def dmi_records(output):
    records = []
    for block in output.split("\n\nHandle ")[1:]:
        lines = block.splitlines()
        kind = re.search(r"DMI type (\d+)", lines[0])
        handle = re.match(r"0x[0-9A-Fa-f]{4}", lines[0])
        fields = {}
        for line in lines[2:]:
            if ": " in line:
                key, value = line.strip().split(": ", 1)
                fields[key] = value
        records.append(
            {
                "type": int(kind.group(1)) if kind else None,
                "handle": int(handle.group(0), 16) if handle else None,
                "title": lines[1] if len(lines) > 1 else "",
                "fields": fields,
                "text": block,
            }
        )
    return records


def smbios_problems(output):
    problems = []
    wrong = re.search(r"^Wrong DMI structures length: .*$", output, re.MULTILINE)
    if wrong:
        problems.append(f"dmidecode finds a broken SMBIOS table: {wrong.group(0)}")
    records = dmi_records(output)
    announced = re.search(
        r"^(\d+) structures occupying \d+ bytes\.$", output, re.MULTILINE
    )
    if announced and int(announced.group(1)) != len(records):
        problems.append(
            f"the SMBIOS entry point announces {announced.group(1)} structures, dmidecode decodes {len(records)}"
        )
    if not records or records[-1]["type"] != 127:
        problems.append("the SMBIOS table does not end with its type 127 end-of-table")
    present = {record["type"] for record in records}
    for kind, title in (
        (16, "physical memory array"),
        (19, "memory array mapped address"),
        (32, "system boot information"),
    ):
        if kind not in present:
            problems.append(f"no SMBIOS type {kind} ({title}) in the guest")
    handles = {record["handle"] for record in records}
    for record in records:
        for key, value in record["fields"].items():
            if (
                key.endswith("Handle")
                and re.fullmatch(r"0x[0-9A-Fa-f]{4}", value)
                and int(value, 16) not in handles
            ):
                problems.append(
                    f"SMBIOS type {record['type']} {key} {value} names no structure in the table"
                )
    return problems


def ata_text(words, first, last):
    return "".join(chr(w >> 8) + chr(w & 0xFF) for w in words[first:last]).strip()


def ata_identity(output):
    identities = {}
    for line in output.splitlines():
        parts = line.split()
        if len(parts) > 100 and parts[0].startswith("dev"):
            words = [int(w, 16) for w in parts[1:]]
            identities[parts[0]] = {
                "serial": ata_text(words, 10, 20),
                "firmware": ata_text(words, 23, 27),
                "model": ata_text(words, 27, 47),
            }
    return identities


def edid_identity(output):
    for line in output.splitlines():
        parts = line.split()
        if len(parts) < 129:
            continue
        data = bytes(int(b, 16) for b in parts[1:])
        letters = (data[8] << 8) | data[9]
        manufacturer = "".join(chr(((letters >> s) & 0x1F) + 64) for s in (10, 5, 0))
        texts = []
        for start in range(54, 126, 18):
            if (
                data[start] == 0
                and data[start + 1] == 0
                and data[start + 3] in (0xFF, 0xFC)
            ):
                texts.append(
                    data[start + 5 : start + 18]
                    .decode("latin-1")
                    .split("\n")[0]
                    .strip()
                )
        return {
            "manufacturer": manufacturer,
            "productCode": data[10] | (data[11] << 8),
            "serialNumber": int.from_bytes(data[12:16], "little"),
            "week": data[16],
            "year": data[17] + 1990,
            "texts": texts,
        }
    return None


QEMU_PCI_VENDORS = {"1b36", "1234"}
USB_ROOT_HUB_VENDOR = "1d6b"
USB_QEMU_VENDORS = {"46f4", "0627"}
USB_IDENTITIES = {
    f"{device['vendor'][2:]}:{device['product'][2:]}": (
        device.get("manufacturer", ""),
        device.get("name", ""),
        device.get("serialLength", 0),
    )
    for device in (
        config["deviceIdentities"][name]
        for name in ("usbStorageBridge", "usbSerial", "usbHub")
    )
}


def pci_devices(found):
    pci = found.get("pci", {}).get("output", "")
    return [
        dict(re.findall(r"^(\w+):\s+(.*)$", block, re.MULTILINE))
        for block in pci.strip().split("\n\n")
    ]


def pci_id(device, field):
    match = re.search(r"\[([0-9a-f]{4})\]$", device.get(field, ""))
    return match and match.group(1)


def qemu_vendor_problems(found):
    return [
        f"PCI {device.get('Slot')} carries QEMU's own vendor id: {device.get('Vendor')} {device.get('Device')}"
        for device in pci_devices(found)
        if pci_id(device, "Vendor") in QEMU_PCI_VENDORS
    ]


def device_checks(found):
    problems = qemu_vendor_problems(found)

    def need(condition, message):
        if not condition:
            problems.append(message)

    devices = pci_devices(found)
    nics = [
        d
        for d in devices
        if (pci_id(d, "Vendor"), pci_id(d, "Device")) == ("10ec", "8125")
    ]
    need(nics, "no RTL8125 (10ec:8125) network card is on the PCI bus")
    need(
        all(d.get("Driver") == "r8169" for d in nics),
        f"the RTL8125 card is not driven by r8169: {nics}",
    )
    net = found.get("net", {}).get("output", "").split("\n")
    need(
        any(line.endswith(" r8169") for line in net),
        f"no network interface is up on r8169: {net}",
    )
    audio = [d for d in devices if pci_id(d, "Class") == "0403"]
    need(audio, "no HD Audio controller is on the PCI bus")
    for device in audio:
        need(
            device.get("Driver") == "snd_hda_intel",
            f"the HD Audio controller is not driven by snd_hda_intel: {device}",
        )
    codecs = found.get("hda", {}).get("output", "").split()
    codec_ids = [int(value, 16) for value in codecs[1::4]]
    codec_drivers = codecs[3::4]
    need(codec_ids, "the HD Audio controller reports no codec")
    expected_codec = int(config["hdaCodec"].replace(":", ""), 16)
    expected_subsystem = int(config["pciSubsystem"].replace(":", ""), 16)
    codec_subsystems = [int(value, 16) for value in codecs[2::4]]
    need(
        codec_drivers and "none" not in codec_drivers,
        f"no Linux codec driver took the HD Audio codec: {codecs}",
    )
    need(
        all(codec == expected_codec for codec in codec_ids),
        f"the HD Audio codec reports {[f'{c:#010x}' for c in codec_ids]}, hdaCodec is {config['hdaCodec']}",
    )
    need(
        all(sub == expected_subsystem for sub in codec_subsystems),
        f"the HD Audio codec subsystem is {[f'{c:#010x}' for c in codec_subsystems]}, pciSubsystem is {config['pciSubsystem']}",
    )
    xhci_windows = [
        int(end, 16) - int(start, 16) + 1
        for _, device_class, start, end, _ in (
            line.split()
            for line in found.get("pci-bars", {}).get("output", "").splitlines()
            if len(line.split()) == 5
        )
        if device_class == "0x0c0330"
    ]
    expected_window = int(config["xhciRegisterWindow"], 16)
    need(
        xhci_windows and all(w == expected_window for w in xhci_windows),
        f"the xHCI controllers decode {[hex(w) for w in xhci_windows]} bytes, the QEMU build sets {expected_window:#x}",
    )
    usb = [
        line.split("|")
        for line in found.get("usb", {}).get("output", "").splitlines()
        if line.count("|") == 5
    ]
    attached = [fields for fields in usb if fields[1] != USB_ROOT_HUB_VENDOR]
    need(
        len(attached) >= 6,
        f"the guest sees {len(attached)} USB devices, the case attaches a keyboard, a mouse, a tablet, a USB disk, a hub and a USB serial adapter: {usb}",
    )
    for name, vendor, product, maker, label, serial in attached:
        need(
            vendor not in USB_QEMU_VENDORS,
            f"USB device {name} keeps QEMU's vendor id {vendor}:{product}",
        )
        need(
            "QEMU" not in f"{maker} {label} {serial}",
            f"USB device {name} names QEMU: {maker!r} {label!r} {serial!r}",
        )
        identity = USB_IDENTITIES.get(f"{vendor}:{product}")
        if identity is None:
            need(
                not serial,
                f"USB device {name} reports the serial number {serial!r}; a real mouse or keyboard reports none, and QEMU's names the host controller's path",
            )
            continue
        expected_maker, expected_label, serial_length = identity
        need(
            (maker, label) == (expected_maker, expected_label),
            f"USB device {name} {vendor}:{product} names itself {maker!r} {label!r}, the device it copies is {expected_maker!r} {expected_label!r}",
        )
        need(
            re.fullmatch(f"[0-9A-F]{{{serial_length}}}", serial) is not None
            if serial_length
            else not serial,
            f"USB device {name} {vendor}:{product} reports the serial number {serial!r}, expected {serial_length} hex digits derived from the VM uuid"
            if serial_length
            else f"USB device {name} {vendor}:{product} reports the serial number {serial!r}; the hub it copies has none",
        )
    present = {f"{fields[1]}:{fields[2]}" for fields in attached}
    for key in sorted(set(USB_IDENTITIES) - present):
        need(
            False,
            f"no USB device reports {key}; the case attaches a USB disk, a hub and a USB serial adapter: {usb}",
        )
    return problems


def kib(text):
    size = re.fullmatch(r"(\d+) ([kKMGT])i?B", text or "")
    if not size:
        return None
    return int(size.group(1)) << 10 * "KMGT".index(size.group(2).upper())


def memory_problems(by_type):
    problems = []

    def need(condition, message):
        if not condition:
            problems.append(message)

    board = config["memory"]
    slots = board["slots"]
    modules = sum(slot["populated"] for slot in slots)
    arrays = by_type.get(16, [])
    need(
        len(arrays) == 1,
        f"the guest has {len(arrays)} SMBIOS memory arrays, a desktop board has one",
    )
    if not arrays:
        return problems
    array = arrays[0]
    array_handle = f"0x{array['handle']:04X}"
    need(
        kib(array["fields"].get("Maximum Capacity")) == board["maxCapacityGb"] << 20,
        f"SMBIOS type 16 maximum capacity is {array['fields'].get('Maximum Capacity')!r}, smbios.memory.maxCapacityGb is {board['maxCapacityGb']}",
    )
    need(
        array["fields"].get("Number Of Devices") == str(len(slots)),
        f"SMBIOS type 16 counts {array['fields'].get('Number Of Devices')!r} devices, smbios.memory.slots lists {len(slots)}",
    )
    devices = by_type.get(17, [])
    need(
        len(devices) == len(slots),
        f"the guest has {len(devices)} SMBIOS memory devices, smbios.memory.slots lists {len(slots)}",
    )
    installed = 0
    for record, slot in zip(devices, slots, strict=False):
        fields = record["fields"]
        place = f"{slot['locator']!r} in {slot['bank']!r}"
        need(
            (fields.get("Locator"), fields.get("Bank Locator"))
            == (slot["locator"], slot["bank"]),
            f"SMBIOS memory device {record['handle']:#06x} is {fields.get('Locator')!r} in {fields.get('Bank Locator')!r}, the slot there is {place}",
        )
        need(
            fields.get("Array Handle") == array_handle,
            f"SMBIOS memory device {place} names array {fields.get('Array Handle')!r}, the array is {array_handle}",
        )
        if not slot["populated"]:
            need(
                fields.get("Size") == "No Module Installed",
                f"the empty slot {place} reports size {fields.get('Size')!r}, not No Module Installed",
            )
            continue
        size = kib(fields.get("Size"))
        need(size, f"the populated slot {place} reports size {fields.get('Size')!r}")
        installed += size or 0
        need(
            fields.get("Manufacturer") == board["manufacturer"],
            f"the module in {place} is made by {fields.get('Manufacturer')!r}",
        )
        need(
            fields.get("Part Number") == board["partNumber"],
            f"the module in {place} has part number {fields.get('Part Number')!r}",
        )
        need(
            fields.get("Serial Number") == (slot["serial"] or "Not Specified"),
            f"the module in {place} has serial number {fields.get('Serial Number')!r}, the slot's serial is {slot['serial']!r}",
        )
    ranges = by_type.get(19, [])
    mapped = sum(kib(r["fields"].get("Range Size")) or 0 for r in ranges)
    need(
        installed == mapped,
        f"the populated modules hold {installed} kB, the SMBIOS type 19 ranges map {mapped} kB",
    )
    for record in ranges:
        need(
            record["fields"].get("Physical Array Handle") == array_handle,
            f"SMBIOS type 19 {record['handle']:#06x} maps array {record['fields'].get('Physical Array Handle')!r}, the array is {array_handle}",
        )
        need(
            record["fields"].get("Partition Width") == str(modules),
            f"SMBIOS type 19 {record['handle']:#06x} has partition width {record['fields'].get('Partition Width')!r}, {modules} modules are populated",
        )
    return problems


SMBIOS_TABLE_OFFSET = 32


def smbios_structures(found):
    raw = bytes(
        int(b, 16) for b in found.get("smbios-raw", {}).get("output", "").split()
    )
    table = raw[SMBIOS_TABLE_OFFSET:]
    structures = []
    at = 0
    while at + 4 <= len(table):
        kind, length = table[at], table[at + 1]
        end = table.find(b"\0\0", at + length)
        if length < 4 or end < 0:
            break
        area = table[at + length : end]
        structures.append(
            {
                "type": kind,
                "handle": int.from_bytes(table[at + 2 : at + 4], "little"),
                "data": table[at : at + length],
                "strings": [s.decode("latin-1") for s in area.split(b"\0")]
                if area
                else [],
            }
        )
        at = end + 2
        if kind == 127:
            break
    return structures


def raw_byte(structure, offset):
    data = structure["data"]
    return data[offset] if offset < len(data) else None


def raw_word(structure, offset, size=2):
    data = structure["data"]
    if offset + size > len(data):
        return None
    return int.from_bytes(data[offset : offset + size], "little")


def raw_text(structure, offset):
    index = raw_byte(structure, offset)
    if not index or index > len(structure["strings"]):
        return None
    return structure["strings"][index - 1]


def compare(problems, title, got, wanted):
    if got != wanted:
        problems.append(f"{title} is {got!r}, the configuration gives {wanted!r}")


def cpu_brand(found):
    leaves = cpuid_leaves(found.get("cpuid", {}).get("output", ""))
    parts = [leaves.get((leaf, 0)) for leaf in (0x80000002, 0x80000003, 0x80000004)]
    if None in parts:
        return None
    return register_text(*(register for part in parts for register in part))


def edid_mode(output):
    for line in output.splitlines():
        parts = line.split()
        if len(parts) < 129:
            continue
        timing = bytes(int(b, 16) for b in parts[1:])[54:72]
        return {
            "width": timing[2] | (timing[4] & 0xF0) << 4,
            "height": timing[5] | (timing[7] & 0xF0) << 4,
            "widthMm": timing[12] | (timing[14] & 0xF0) << 4,
            "heightMm": timing[13] | (timing[14] & 0x0F) << 8,
        }
    return None


def identity_checks(found, case):
    problems = []
    structures = smbios_structures(found)
    if not structures:
        return ["the guest gave no raw SMBIOS table to compare"]
    by_type = {}
    for structure in structures:
        by_type.setdefault(structure["type"], []).append(structure)
    by_handle = {structure["handle"]: structure for structure in structures}

    def one(kind):
        found_kind = by_type.get(kind, [])
        if len(found_kind) != 1:
            problems.append(
                f"the guest has {len(found_kind)} SMBIOS type {kind} structures, a board has one"
            )
            return None
        return found_kind[0]

    serials = case["serials"]
    wanted = config["system"]
    system = one(1)
    if system:
        compare(
            problems, "SMBIOS type 1 version", raw_text(system, 0x06), wanted["version"]
        )
        compare(
            problems, "SMBIOS type 1 serial", raw_text(system, 0x07), serials["system"]
        )
        compare(problems, "SMBIOS type 1 SKU", raw_text(system, 0x19), wanted["sku"])
        compare(
            problems, "SMBIOS type 1 family", raw_text(system, 0x1A), wanted["family"]
        )
    board = one(2)
    if board:
        compare(
            problems,
            "SMBIOS type 2 serial",
            raw_text(board, 0x07),
            serials["baseboard"],
        )
    wanted = config["chassis"]
    chassis = one(3)
    if chassis:
        compare(
            problems,
            "SMBIOS type 3 chassis type",
            raw_byte(chassis, 0x05) & 0x7F,
            wanted["type"],
        )
        compare(
            problems,
            "SMBIOS type 3 version",
            raw_text(chassis, 0x06),
            wanted["version"],
        )
        compare(
            problems, "SMBIOS type 3 serial", raw_text(chassis, 0x07), wanted["serial"]
        )
        compare(
            problems,
            "SMBIOS type 3 asset tag",
            raw_text(chassis, 0x08),
            wanted["asset"],
        )
        elements = (raw_byte(chassis, 0x13) or 0) * (raw_byte(chassis, 0x14) or 0)
        compare(
            problems,
            "SMBIOS type 3 SKU",
            raw_text(chassis, 0x15 + elements),
            wanted["sku"],
        )

    wanted = config["processor"]
    processor = one(4)
    if processor:
        compare(
            problems,
            "SMBIOS type 4 socket",
            raw_text(processor, 0x04),
            wanted["socket"],
        )
        compare(
            problems,
            "SMBIOS type 4 manufacturer",
            raw_text(processor, 0x07),
            wanted["manufacturer"],
        )
        compare(
            problems,
            "SMBIOS type 4 version",
            raw_text(processor, 0x10),
            wanted["modelId"] or cpu_brand(found),
        )
        family = wanted["family"]
        compare(
            problems,
            "SMBIOS type 4 family byte",
            raw_byte(processor, 0x06),
            family if family < 0xFE else 0xFE,
        )
        compare(problems, "SMBIOS type 4 family 2", raw_word(processor, 0x28), family)
        compare(
            problems,
            "SMBIOS type 4 voltage",
            raw_byte(processor, 0x11),
            0x80 | wanted["voltageDecivolts"],
        )
        compare(
            problems,
            "SMBIOS type 4 external clock",
            raw_word(processor, 0x12),
            wanted["externalClock"],
        )
        compare(
            problems,
            "SMBIOS type 4 upgrade",
            raw_byte(processor, 0x19),
            wanted["upgrade"],
        )
        compare(
            problems,
            "SMBIOS type 4 characteristics",
            raw_word(processor, 0x26),
            wanted["characteristics"],
        )
        for field, offset in (("maxSpeed", 0x14), ("currentSpeed", 0x16)):
            if wanted[field] is not None:
                compare(
                    problems,
                    f"SMBIOS type 4 {field}",
                    raw_word(processor, offset),
                    wanted[field],
                )
        for level, offset in ((1, 0x1A), (2, 0x1C), (3, 0x1E)):
            handle = raw_word(processor, offset)
            compare(
                problems,
                f"SMBIOS type 4 L{level} cache handle",
                handle,
                config["cacheHandles"][f"l{level}"],
            )
            cache = by_handle.get(handle)
            if cache is None or cache["type"] != 7:
                problems.append(
                    f"SMBIOS type 4 L{level} cache handle {handle:#06x} names no type 7 cache"
                )
                continue
            compare(
                problems,
                f"SMBIOS type 7 {handle:#06x} level",
                (raw_word(cache, 0x05) & 0x07) + 1,
                level,
            )
            compare(
                problems,
                f"SMBIOS type 7 L{level} size in kB",
                raw_word(cache, 0x17, 4),
                config["cache"][f"l{level}"],
            )
            compare(
                problems,
                f"SMBIOS type 7 L{level} associativity",
                raw_byte(cache, 0x12),
                config["cache"][f"assocL{level}"],
            )
            compare(
                problems,
                f"SMBIOS type 7 L{level} error correction",
                raw_byte(cache, 0x10),
                config["cache"]["ecc"],
            )

    ports = [
        {
            "internalReference": raw_text(port, 0x04),
            "internalConnectorType": raw_byte(port, 0x05),
            "externalReference": raw_text(port, 0x06),
            "externalConnectorType": raw_byte(port, 0x07),
            "portType": raw_byte(port, 0x08),
        }
        for port in by_type.get(8, [])
    ]
    compare(problems, "the SMBIOS type 8 port connectors", ports, config["ports"])
    slots = [
        {
            "designation": raw_text(slot, 0x04),
            "type": raw_byte(slot, 0x05),
            "dataBusWidth": raw_byte(slot, 0x06),
            "currentUsage": raw_byte(slot, 0x07),
            "length": raw_byte(slot, 0x08),
            "id": raw_word(slot, 0x09),
            "characteristics1": raw_byte(slot, 0x0B),
            "characteristics2": raw_byte(slot, 0x0C),
        }
        for slot in by_type.get(9, [])
    ]
    compare(problems, "the SMBIOS type 9 slots", slots, config["systemSlots"])
    for slot in by_type.get(9, []):
        compare(
            problems,
            f"SMBIOS type 9 {raw_text(slot, 0x04)!r} bus address",
            (raw_word(slot, 0x0D), raw_byte(slot, 0x0F), raw_byte(slot, 0x10)),
            (0xFFFF, 0xFF, 0xFF),
        )

    memory = config["memory"]
    array = one(16)
    if array:
        compare(
            problems,
            "SMBIOS type 16 error correction",
            raw_byte(array, 0x06),
            memory["errorCorrection"],
        )
    voltage = memory["voltageMillivolts"] or 0
    width = 64 + (8 if memory["errorCorrection"] >= 4 else 0)
    modules = [m for m in by_type.get(17, []) if raw_word(m, 0x0C)]
    compare(
        problems,
        "the count of populated SMBIOS type 17 devices",
        len(modules),
        sum(slot["populated"] for slot in memory["slots"]),
    )
    for module in modules:
        place = (
            f"SMBIOS type 17 {raw_text(module, 0x10)!r} in {raw_text(module, 0x11)!r}"
        )
        compare(problems, f"{place} type", raw_byte(module, 0x12), memory["type"])
        compare(
            problems,
            f"{place} type detail",
            raw_word(module, 0x13),
            memory["typeDetail"],
        )
        compare(problems, f"{place} speed", raw_word(module, 0x15), memory["speed"])
        compare(
            problems,
            f"{place} configured speed",
            raw_word(module, 0x20),
            memory["speed"],
        )
        compare(
            problems, f"{place} rank", raw_byte(module, 0x1B) & 0x0F, memory["rank"]
        )
        compare(problems, f"{place} total width", raw_word(module, 0x08), width)
        compare(problems, f"{place} data width", raw_word(module, 0x0A), 64)
        for title, offset in (
            ("minimum", 0x22),
            ("maximum", 0x24),
            ("configured", 0x26),
        ):
            compare(
                problems,
                f"{place} {title} voltage in mV",
                raw_word(module, offset),
                voltage,
            )

    edid = config["edid"]
    mode = edid_mode(found.get("edid", {}).get("output", ""))
    if mode is None:
        problems.append("no EDID detailed timing in the guest")
    else:
        resolution = edid["resolution"]
        compare(
            problems,
            "the EDID preferred mode",
            (mode["width"], mode["height"]),
            (resolution["width"], resolution["height"]),
        )
        compare(
            problems,
            "the EDID image size in mm",
            (mode["widthMm"], mode["heightMm"]),
            tuple(
                pixels * 254 // 10 // edid["dpi"]
                for pixels in (resolution["width"], resolution["height"])
            ),
        )
    return problems


def full_checks(found, mac):
    problems = []

    def need(condition, message):
        if not condition:
            problems.append(message)

    leaves = cpuid_leaves(found.get("cpuid", {}).get("output", ""))
    hypervisor_bit = bool(leaves.get((1, 0), (0, 0, 0, 0))[2] >> 31 & 1)
    need(
        hypervisor_bit == (config["hypervMode"] == "enlightened"),
        f"CPUID.1:ECX hypervisor bit is {hypervisor_bit} with hypervMode {config['hypervMode']}",
    )
    hyperv_leaf = leaves.get((0x40000000, 0))
    if config["hypervEnabled"]:
        vendor = register_text(*hyperv_leaf[1:]) if hyperv_leaf else None
        need(
            vendor == config["hypervVendorId"],
            f"CPUID 0x40000000 vendor is {vendor!r}, hypervVendorId is {config['hypervVendorId']!r}",
        )
    kvm_signature = [
        hex(k[0])
        for k, v in leaves.items()
        if 0x40000000 <= k[0] <= 0x400001FF and "KVMKVMKVM" in register_text(*v[1:])
    ]
    need(not kvm_signature, f"the KVM signature is visible at CPUID {kvm_signature}")
    if config["aperfMperf"]:
        need(
            bool(leaves.get((6, 0), (0, 0, 0, 0))[2] & 1),
            "CPUID.6:ECX APERF/MPERF bit is clear although aperfMperf is on",
        )

    dmi = found.get("dmidecode", {}).get("output", "")
    records = dmi_records(dmi)
    by_type = {}
    for record in records:
        by_type.setdefault(record["type"], []).append(record)
    board = config["board"]
    bios = by_type.get(0, [{"fields": {}}])[0]["fields"]
    system = by_type.get(1, [{"fields": {}}])[0]["fields"]
    need(
        bios.get("Vendor") == board["biosVendor"],
        f"SMBIOS type 0 vendor is {bios.get('Vendor')!r}",
    )
    need(
        bios.get("Version") == board["biosVersion"],
        f"SMBIOS type 0 version is {bios.get('Version')!r}",
    )
    need(
        bios.get("Release Date") == board["biosDate"],
        f"SMBIOS type 0 date is {bios.get('Release Date')!r}",
    )
    need(
        system.get("Manufacturer") == board["manufacturer"],
        f"SMBIOS type 1 manufacturer is {system.get('Manufacturer')!r}",
    )
    need(
        system.get("Product Name") == board["product"],
        f"SMBIOS type 1 product is {system.get('Product Name')!r}",
    )
    need(
        "System is a virtual machine" not in dmi,
        "SMBIOS type 0 still says the system is a virtual machine",
    )
    need(
        "QEMU" not in dmi and "Bochs" not in dmi, "dmidecode output names QEMU or Bochs"
    )
    for kind, title in (
        (7, "cache"),
        (8, "port connector"),
        (17, "memory device"),
        (26, "voltage probe"),
        (27, "cooling device"),
        (28, "temperature probe"),
        (29, "current probe"),
        (11, "OEM strings"),
    ):
        need(kind in by_type, f"no SMBIOS type {kind} ({title}) in the guest")
    need(
        "BIOS characteristics not supported" not in dmi,
        "SMBIOS type 0 says BIOS characteristics are not supported",
    )
    need("UEFI is supported" in dmi, "SMBIOS type 0 does not say UEFI is supported")
    problems += memory_problems(by_type)
    for device in config["onboardDevices"]:
        need(
            device["designation"] in dmi,
            f"onboard device {device['designation']!r} is not in SMBIOS",
        )

    problems += qemu_vendor_problems(found)
    devices = pci_devices(found)
    by_slot = {d.get("Slot"): d for d in devices}
    for slot, ids in {
        "00:00.0": ("8086", "29c0"),
        "00:1f.0": ("8086", "2918"),
        "00:1f.2": ("8086", "2922"),
        "00:1f.3": ("8086", "2930"),
    }.items():
        device = by_slot.get(slot, {})
        vendor = re.search(r"\[([0-9a-f]{4})\]$", device.get("Vendor", ""))
        model = re.search(r"\[([0-9a-f]{4})\]$", device.get("Device", ""))
        need(
            (vendor and vendor.group(1), model and model.group(1)) == ids,
            f"PCI {slot} is {device.get('Vendor')} {device.get('Device')}, expected {ids[0]}:{ids[1]}",
        )
    for device in devices:
        subsystem = device.get("SVendor", "")
        need(
            "1af4" not in subsystem and "Red Hat" not in subsystem,
            f"PCI {device.get('Slot')} has the Red Hat subsystem vendor {subsystem}",
        )

    tables = found.get("acpi-tables", {}).get("output", "")
    names = []
    for line in tables.splitlines():
        name, *data = line.split()
        names.append(name)
        if name in ("FACS",) or len(data) < 24:
            continue
        header = bytes(int(b, 16) for b in data)
        oem_id = header[10:16].decode("latin-1")
        oem_table = header[16:24].decode("latin-1")
        need(
            oem_id == config["acpiOem"]["id"],
            f"ACPI table {name} has OEM id {oem_id!r}, acpiOem.id is {config['acpiOem']['id']!r}",
        )
        need(
            oem_table == config["acpiOem"]["tableId"],
            f"ACPI table {name} has OEM table id {oem_table!r}, acpiOem.tableId is {config['acpiOem']['tableId']!r}",
        )
    if config["acpi"]["waet"]:
        need(
            "WAET" in names,
            "no WAET table, which Windows uses to skip timer workarounds, although acpi.waet is on",
        )
    else:
        need(
            "WAET" not in names,
            "a WAET table is present, which only virtual machines carry, although acpi.waet is off",
        )
    need(
        "BGRT" not in names, "a BGRT table is present, which carries the firmware logo"
    )
    facp = bytes(int(b, 16) for b in found.get("facp", {}).get("output", "").split())
    if len(facp) >= 276:
        latencies = (
            int.from_bytes(facp[96:98], "little"),
            int.from_bytes(facp[98:100], "little"),
        )
        expected_latencies = (config["acpi"]["c2Latency"], config["acpi"]["c3Latency"])
        need(
            latencies == expected_latencies,
            f"FADT C2/C3 latencies are {latencies}, acpi.c2Latency and acpi.c3Latency are {expected_latencies}",
        )
        need(facp[268:276] == b"\0" * 8, f"FADT hypervisor vendor is {facp[268:276]!r}")
    acpi_devices = found.get("acpi-devices", {}).get("output", "")
    containers = [
        line.split()
        for line in acpi_devices.splitlines()
        if line.startswith("PNP0A06:")
    ]
    need(
        all(len(c) == 3 and c[2].isdigit() for c in containers),
        f"an ACPI container (PNP0A06) has a descriptive _UID, which Windows makes its instance id: {containers}",
    )
    if config["hypervEnabled"]:
        limits = leaves.get((0x40000005, 0), (0, 0, 0, 0))[:3]
        need(
            limits == (0x140, 0x200, 0x25B0),
            f"CPUID 0x40000005 reports {[hex(v) for v in limits]} where a Hyper-V build 14393 host reports 0x140, 0x200 and 0x25b0",
        )
    outcomes = {
        parts[0]: parts[1]
        for parts in (
            line.split()
            for line in found.get("instructions", {}).get("output", "").splitlines()
        )
        if len(parts) == 3
    }
    leaf0 = leaves.get((0, 0))
    if leaf0 and register_text(leaf0[1], leaf0[3], leaf0[2]) == "GenuineIntel":
        need(
            outcomes.get("vmmcall") == "ill",
            f"vmmcall from user mode raises {outcomes.get('vmmcall')}, where the CPU raises #UD; KVM's hypercall-patching quirk is still on: {outcomes}",
        )
    firmware_blobs = tcg_event_types(found.get("tcg-log", {}).get("output", ""))
    need(
        firmware_blobs
        and 0x80000008 not in firmware_blobs
        and 0x8000000A in firmware_blobs,
        f"the TCG log's PCR 0 firmware events are {[hex(t) for t in firmware_blobs]}, where OVMF at profile revision 105 logs only EV_EFI_PLATFORM_FIRMWARE_BLOB2 (0x8000000a)",
    )
    for hid, title in (
        ("PNP0C0A", "battery"),
        ("PNP0C0B", "fan"),
        ("LNXTHERM", "thermal zone"),
        ("ACPI0007", "processor"),
    ):
        need(hid in acpi_devices, f"no ACPI {title} device ({hid}) in the guest")
    batteries = found.get("battery", {}).get("output", "").split()[1::2]
    need(
        batteries == [config["acpiSsdt"]["batterySerial"]],
        f"the guest's batteries report serial numbers {batteries}, acpiSsdt.batterySerial is {config['acpiSsdt']['batterySerial']!r}",
    )
    dmesg = found.get("dmesg", {}).get("output", "")
    acpi_errors = [
        line
        for line in dmesg.splitlines()
        if "ACPI BIOS Error" in line or "ACPI Error" in line
    ]
    need(not acpi_errors, f"the guest kernel logged ACPI errors: {acpi_errors[:5]}")

    edid = edid_identity(found.get("edid", {}).get("output", ""))
    need(edid is not None, "no EDID in the guest")
    if edid:
        need(
            edid["manufacturer"] == config["edid"]["manufacturer"],
            f"EDID manufacturer is {edid['manufacturer']!r}",
        )
        need(
            edid["productCode"] == int(str(config["edid"]["productCode"]), 0),
            f"EDID product code is {edid['productCode']:#x}",
        )
        need(
            edid["week"] == config["edid"]["week"]
            and edid["year"] == config["edid"]["year"],
            f"EDID date is week {edid['week']} {edid['year']}",
        )
        need(
            edid["serialNumber"] == config["edid"]["serialNumber"],
            f"EDID serial number is {edid['serialNumber']}, edid.serialNumber is {config['edid']['serialNumber']}",
        )
        need(
            config["edid"]["serial"] in edid["texts"],
            f"EDID text descriptors are {edid['texts']}",
        )

    identities = list(ata_identity(found.get("ata", {}).get("output", "")).values())
    disk = next(
        (i for i in identities if i["model"] == config["disk"]["model"].strip()), None
    )
    need(
        disk is not None,
        f"no ATA disk answers with model {config['disk']['model'].strip()!r}: {identities}",
    )
    if disk:
        need(
            disk["serial"] == config["disk"]["serial"],
            f"ATA disk serial is {disk['serial']!r}",
        )
        need(
            disk["firmware"] == config["disk"]["firmware"],
            f"ATA disk firmware is {disk['firmware']!r}",
        )

    problems += tpm_checks(found)

    clock = found.get("clock", {}).get("output", "")
    need(
        "kvm-clock" not in clock, f"kvm-clock is offered to the guest: {clock.strip()}"
    )
    need("hpet" in clock, f"no HPET clock source in the guest: {clock.strip()}")

    if config["pciMmio64Mb"] > 0:
        windows = re.findall(
            r"^\s*([0-9a-f]+)-([0-9a-f]+) : PCI Bus 0000:00",
            found.get("iomem", {}).get("output", ""),
            re.MULTILINE,
        )
        largest = max(
            (int(e, 16) - int(s, 16) + 1 for s, e in windows if int(s, 16) >= 1 << 32),
            default=0,
        )
        need(
            largest >= config["pciMmio64Mb"] << 20,
            f"the largest 64-bit PCI window is {largest >> 20} MiB, pciMmio64Mb is {config['pciMmio64Mb']}",
        )

    if mac:
        need(
            mac in found.get("net", {}).get("output", ""),
            f"no network card has the MAC {mac}: {found.get('net', {}).get('output', '').strip()}",
        )

    signature = re.search(r"signature (\S*)", found.get("fw-cfg", {}).get("output", ""))
    need(
        signature is not None and signature.group(1) != "QEMU",
        f"fw_cfg answers with signature {signature.group(1) if signature else None!r}",
    )
    return problems


def tcg_event_types(output):
    data = bytes(int(x, 16) for x in output.split())
    sizes = {0x0004: 20, 0x000B: 32, 0x000C: 48, 0x000D: 64, 0x0012: 32}
    if len(data) < 32:
        return []
    offset = 32 + int.from_bytes(data[28:32], "little")
    types = []
    while offset + 12 <= len(data):
        pcr = int.from_bytes(data[offset : offset + 4], "little")
        kind = int.from_bytes(data[offset + 4 : offset + 8], "little")
        count = int.from_bytes(data[offset + 8 : offset + 12], "little")
        offset += 12
        for _ in range(count):
            algorithm = int.from_bytes(data[offset : offset + 2], "little")
            if algorithm not in sizes:
                return types
            offset += 2 + sizes[algorithm]
        size = int.from_bytes(data[offset : offset + 4], "little")
        offset += 4 + size
        if pcr == 0 and kind in (0x80000008, 0x8000000A):
            types.append(kind)
    return types


def tpm_value(text, name):
    match = re.search(rf"{name}:\s*raw: (0x[0-9A-Fa-f]+)", text)
    return int(match.group(1), 16) if match else None


def certificate_text(found, section):
    result = found.get(section, {"output": "", "exit": 1})
    if result["exit"] != 0:
        return ""
    data = bytes.fromhex("".join(result["output"].split()))
    return subprocess.run(
        ["openssl", "x509", "-inform", "DER", "-noout", "-text"],
        input=data,
        capture_output=True,
        check=False,
    ).stdout.decode("latin-1")


def tpm_checks(found):
    problems = []
    tpm = config["tpm"]
    properties = found.get("tpm", {}).get("output", "")
    manufacturer = int(tpm["manufacturer"][3:], 16)
    if tpm_value(properties, "TPM2_PT_MANUFACTURER") != manufacturer:
        problems.append(
            f"the guest TPM reports manufacturer {tpm_value(properties, 'TPM2_PT_MANUFACTURER')}, tpm.manufacturer is {tpm['manufacturer']}"
        )
    model = tpm["model"].encode().ljust(16, b"\0")
    for index in range(4):
        expected = int.from_bytes(model[index * 4 : index * 4 + 4], "big")
        actual = tpm_value(properties, f"TPM2_PT_VENDOR_STRING_{index + 1}")
        if actual != expected:
            problems.append(
                f"the guest TPM vendor string {index + 1} is {actual}, tpm.model {tpm['model']!r} gives {expected}"
            )
    firmware = int(tpm["firmwareVersion"][3:], 16)
    if tpm_value(properties, "TPM2_PT_FIRMWARE_VERSION_1") != firmware:
        problems.append(
            f"the guest TPM firmware version is {tpm_value(properties, 'TPM2_PT_FIRMWARE_VERSION_1')}, tpm.firmwareVersion is {tpm['firmwareVersion']}"
        )
    ek = certificate_text(found, "tpm-ek-cert")
    platform = certificate_text(found, "tpm-platform-cert")
    for name, text, values in (
        ("EK", ek, (tpm["manufacturer"], tpm["model"], tpm["firmwareVersion"])),
        ("platform", platform, (tpm["platformManufacturer"], tpm["platformModel"])),
    ):
        if not text:
            problems.append(f"the guest TPM holds no readable {name} certificate")
            continue
        for value in values:
            if value not in text or f'"{value}"' in text:
                problems.append(
                    f"the {name} certificate does not carry {value!r} as is"
                )
    return problems


def usb_hotplug(directory):
    connection = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    connection.settimeout(10)
    connection.connect(str(directory / "qmp.sock"))
    reader = connection.makefile("r")
    reader.readline()

    def command(name, arguments=None):
        message = {"execute": name} | ({"arguments": arguments} if arguments else {})
        connection.sendall(json.dumps(message).encode() + b"\n")
        while True:
            reply = json.loads(reader.readline())
            if "return" in reply or "error" in reply:
                return reply

    command("qmp_capabilities")
    reply = command(
        "device_add", {"driver": "usb-kbd", "id": "hotplug-probe", "bus": "usb.0"}
    )
    connection.close()
    return reply


def vmaware_report(found):
    result = found.get("vmaware")
    if result is None or result["exit"] != 0:
        return None
    output = result["output"]
    try:
        report = json.loads(output[output.find("{") : output.rfind("}") + 1])
    except json.JSONDecodeError:
        return None
    return {
        "techniques": sorted(report["detected_techniques"]),
        "brand": report["brand"],
        "percentage": report["percentage"],
    }


def evidence(case, directory, seconds, process):
    text = serial_text(directory)
    found = sections(text)
    secure = found.get("secure-boot", {}).get("output", "").split()
    return {
        "name": case["name"],
        "seconds": seconds,
        "finished": DONE in text,
        "refused": REFUSED in text,
        "kernel": (
            re.search(r"probe=(\w+)", found.get("cmdline", {}).get("output", ""))
            or [None, None]
        )[1],
        "secure_boot": (secure[-1] == "01") if secure else None,
        "sections": dict(found),
        "vmaware": vmaware_report(found),
        "firmware_lines": sorted(set(re.findall(r"BdsDxe: [^\n]*", text))),
        "qemu_exit": process.poll(),
        "qemu_log": (directory / "qemu.log").read_text()[-2000:],
    }


def problems_of(case, record, directory):
    expect = case["expect"]
    found = []
    if record["qemu_exit"] not in (None, 0):
        found.append(f"QEMU exited with {record['qemu_exit']}: {record['qemu_log']}")
    if expect.get("refused"):
        if record["finished"]:
            found.append(
                "Secure Boot with the Microsoft keys booted an unsigned loader"
            )
        if not record["refused"]:
            found.append("the firmware never refused the unsigned loader")
        return found
    if not record["finished"]:
        found.append(
            f"the probe did not finish in {len(record['attempts'])} boots of {ATTEMPT_SECONDS} s; firmware said: {record['firmware_lines']}"
        )
        return found
    if record["kernel"] != expect["kernel"]:
        found.append(
            f"booted the {record['kernel']} probe, expected the {expect['kernel']} one"
        )
    if record["secure_boot"] != expect["secureBoot"]:
        found.append(
            f"the guest reports Secure Boot {record['secure_boot']}, expected {expect['secureBoot']}"
        )
    if expect.get("refusedFirst") and not record["refused"]:
        found.append(
            "the unsigned loader on the first disk was not refused before the signed one booted"
        )
    sections_found = record["sections"]
    boot_log = sections_found.get("dmesg", {}).get("output", "")
    if not any(
        word in boot_log for word in ("efifb", "simple-framebuffer", "simpledrm")
    ):
        found.append(
            "the firmware handed over no framebuffer, so its video driver did not drive the card"
        )
    vmaware = record["vmaware"]
    if vmaware is None:
        found.append(
            f"VMAware gave no report: {sections_found.get('vmaware', {}).get('output', '')[-2000:]!r}"
        )
    else:
        for technique in sorted(set(vmaware["techniques"]) - vmaware_expected):
            found.append(
                f"VMAware detects {technique}, which verify/vmaware-expected.json does not expect for cpuVendor {config['cpuVendor']}, hypervMode {config['hypervMode']} and acpi.waet {config['acpi']['waet']}"
            )
    dmi = sections_found.get("dmidecode", {}).get("output", "")
    if f"Manufacturer: {config['board']['manufacturer']}" not in dmi:
        found.append(
            f"the guest does not see the configured board manufacturer {config['board']['manufacturer']!r}"
        )
    found += smbios_problems(dmi)
    if expect.get("full") and "error" in record.get("usb_hotplug", {}):
        found.append(
            f"hot-plugging a USB keyboard was refused: {record['usb_hotplug']['error']}"
        )
    if expect.get("devices"):
        found += device_checks(sections_found)
    if expect.get("full"):
        mac_file = directory / "mac"
        found += full_checks(
            sections_found, mac_file.read_text() if mac_file.exists() else ""
        )
        found += identity_checks(sections_found, case)
    return found


running = {}
for case in plan["cases"]:
    directory, process, tpm = start(case, 1)
    running[case["name"]] = (case, 1, directory, process, tpm, time.monotonic())
attempts = {case["name"]: [] for case in plan["cases"]}
records = {}
directories = {}
while running:
    for name, (case, attempt, directory, process, tpm, began) in list(running.items()):
        elapsed = time.monotonic() - began
        done = finished(case, serial_text(directory)) or process.poll() is not None
        if not done and elapsed < ATTEMPT_SECONDS:
            continue
        record = evidence(case, directory, round(elapsed, 1) if done else None, process)
        if done and case["expect"].get("full"):
            record["usb_hotplug"] = usb_hotplug(directory)
        process.kill()
        process.wait()
        if tpm:
            tpm.kill()
            tpm.wait()
        serial = f"{name}-attempt-{attempt}.log"
        shutil.copy(directory / "serial.log", serial_dir / serial)
        attempts[name].append(
            {
                "attempt": attempt,
                "cpu": pinned_cpu[directory],
                "outcome": "finished" if done else "stalled",
                "seconds": record["seconds"],
                "serial": f"serial/{serial}",
            }
        )
        if not done and attempt < ATTEMPTS:
            new_directory, new_process, new_tpm = start(case, attempt + 1)
            running[name] = (
                case,
                attempt + 1,
                new_directory,
                new_process,
                new_tpm,
                time.monotonic(),
            )
            continue
        records[name] = record | {"attempts": attempts[name]}
        directories[name] = directory
        del running[name]
    time.sleep(1)

failures = []
for case in plan["cases"]:
    for problem in problems_of(case, records[case["name"]], directories[case["name"]]):
        failures.append(f"{case['name']}: {problem}")

microsoft = (probe / "microsoft-vars.txt").read_text()
shutil.copy(probe / "microsoft-vars.txt", out / "microsoft-vars.txt")
for certificate in MICROSOFT_CERTIFICATES:
    if certificate not in microsoft:
        failures.append(f"the Microsoft variable template lacks {certificate}")
if "Debian" in microsoft:
    failures.append(
        "the Microsoft variable template carries a Debian Platform Key or KEK, which no real board has"
    )
dbx = re.search(
    r"^name=dbx .*\n\s+siglist type=guid:EfiCertSha256 count=(\d+)", microsoft, re.M
)
if dbx is None or int(dbx.group(1)) < 2:
    failures.append(
        "the Microsoft variable template's dbx is virt-firmware's one placeholder entry, not Microsoft's revocation list"
    )
if f"subject CN={config['platformKeyName']}" not in microsoft:
    failures.append(f"the Platform Key subject is not {config['platformKeyName']!r}")

(out / "evidence.json").write_text(json.dumps(list(records.values()), indent=2))
for record in records.values():
    print(
        f"{record['name']}: finished={record['finished']} refused={record['refused']} kernel={record['kernel']} secure_boot={record['secure_boot']} seconds={record['seconds']} boots={len(record['attempts'])}"
    )
    if record["vmaware"]:
        print(f"{record['name']}: vmaware {' '.join(record['vmaware']['techniques'])}")
fired = {
    technique
    for record in records.values()
    if record["vmaware"]
    for technique in record["vmaware"]["techniques"]
}
for technique in sorted(vmaware_expected - fired):
    print(
        f"VMAware no longer detects {technique} in any case; verify/vmaware-expected.json still expects it for cpuVendor {config['cpuVendor']}, hypervMode {config['hypervMode']} and acpi.waet {config['acpi']['waet']}"
    )
if failures:
    print("\n".join(failures))
    sys.exit(1)
