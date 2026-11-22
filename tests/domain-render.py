import json
import sys
import xml.etree.ElementTree as ET

QEMU = "{http://libvirt.org/schemas/domain/qemu/1.0}"


def fail(name, message):
    sys.exit(f"domain-render: {name}: {message}")


def address(source):
    fields = [int(source.get(key), 0) for key in ("domain", "bus", "slot", "function")]
    return "{:04x}:{:02x}:{:02x}.{:x}".format(*fields)


def check(name, want):
    root = ET.parse(want["xml"]).getroot()

    machine = root.find("os/type").get("machine")
    if machine != want["machine"]:
        fail(name, f"machine is {machine}, not {want['machine']}")

    pins = [pin.get("cpuset") for pin in root.findall("cputune/vcpupin")]
    if want["vcpupin"] is None:
        if root.find("cputune") is not None:
            fail(name, "has a cputune block although the domain is not pinned")
    else:
        if pins != want["vcpupin"]:
            fail(name, f"vcpupin cpusets are {pins}, not {want['vcpupin']}")
        if [int(pin.get("vcpu")) for pin in root.findall("cputune/vcpupin")] != list(
            range(len(pins))
        ):
            fail(name, "vcpupin does not number the vCPUs in order")
        if root.find("cputune/emulatorpin").get("cpuset") != want["emulatorpin"]:
            fail(name, f"emulatorpin is not {want['emulatorpin']}")
    iothread = root.find("cputune/iothreadpin")
    if want["iothreadpin"] is None:
        if iothread is not None or root.find("iothreads") is not None:
            fail(name, "has an I/O thread although pinning.iothread is null")
    else:
        if iothread is None or iothread.get("cpuset") != want["iothreadpin"]:
            fail(name, f"iothreadpin is not {want['iothreadpin']}")
        if root.findtext("iothreads") != "1":
            fail(name, "does not declare its one I/O thread")

    pci = {}
    for hostdev in root.findall("devices/hostdev[@type='pci']"):
        pci[address(hostdev.find("source/address"))] = hostdev.get("managed")
    if pci != want["pci"]:
        fail(name, f"PCI hostdevs and their managed flags are {pci}, not {want['pci']}")

    roms = [
        hostdev.find("rom") for hostdev in root.findall("devices/hostdev[@type='pci']")
    ]
    roms = [rom for rom in roms if rom is not None]
    if want["rom"] is None:
        if roms:
            fail(name, "has a rom element although gpu.rom is null")
    elif (
        len(roms) != 1
        or roms[0].get("file") != want["rom"]["file"]
        or roms[0].get("bar") != want["rom"]["bar"]
    ):
        fail(
            name, f"the GPU's rom is {[rom.attrib for rom in roms]}, not {want['rom']}"
        )

    usb = [
        [
            int(hostdev.find("source/vendor").get("id"), 0),
            int(hostdev.find("source/product").get("id"), 0),
        ]
        for hostdev in root.findall("devices/hostdev[@type='usb']")
    ]
    if usb != want["usb"]:
        fail(name, f"USB hostdevs are {usb}, not {want['usb']}")

    shmem = root.find("devices/shmem")
    if want["shmem"] is None:
        if shmem is not None:
            fail(name, "has a shmem device it should not")
    else:
        if (
            shmem is None
            or shmem.get("name") != "looking-glass"
            or shmem.find("model").get("type") != "ivshmem-plain"
        ):
            fail(name, "has no ivshmem-plain shmem device named looking-glass")
        size = shmem.find("size")
        if int(size.text) != want["shmem"] or size.get("unit") != "M":
            fail(
                name,
                f"the shmem device is {size.text} {size.get('unit')}, not {want['shmem']} M",
            )

    backing = root.find("memoryBacking")
    page = root.find("memoryBacking/hugepages/page")
    if want["hugepages"] is None:
        if page is not None:
            fail(name, "has huge pages it did not ask for")
    else:
        if (
            page is None
            or {"size": page.get("size"), "unit": page.get("unit")} != want["hugepages"]
        ):
            fail(name, f"the huge page size is not {want['hugepages']}")
        if backing.find("locked") is None:
            fail(name, "huge page memory is not locked")
    memfd = (
        backing is not None
        and backing.find("source") is not None
        and backing.find("source").get("type") == "memfd"
        and backing.find("access").get("mode") == "shared"
    )
    if memfd != want["memfd"]:
        fail(name, f"shared memfd backing is {memfd}, not {want['memfd']}")

    video = root.find("devices/video/model").get("type")
    if video != want["video"]:
        fail(name, f"the video model is {video}, not {want['video']}")

    mac = root.find("devices/interface/mac")
    if want["mac"] is not None and (mac is None or mac.get("address") != want["mac"]):
        fail(name, f"the MAC address is not {want['mac']}")

    args = [arg.get("value") for arg in root.findall(f"{QEMU}commandline/{QEMU}arg")]
    for arg in want["args"]:
        if arg not in args:
            fail(name, f"the QEMU arguments lack {arg!r}")
    for arg in want["absentArgs"]:
        if arg in args:
            fail(name, f"the QEMU arguments carry {arg!r}")
    if "-cpu" in args:
        fail(name, "the QEMU arguments carry -cpu")

    disks = root.findall("devices/disk[@device='disk']")
    block = [disk for disk in disks if disk.get("type") == "block"]
    if want["blockIo"] and not any(
        disk.find("driver").get("io") == "native" for disk in block
    ):
        fail(name, "the block disk is not on io=native")
    if any(disk.find("driver").get("cache") != "none" for disk in block):
        fail(name, "a block disk is not on cache=none")
    if "diskCache" in want:
        caches = [disk.find("driver").get("cache") for disk in disks]
        if caches != want["diskCache"]:
            fail(name, f"the disks' cache modes are {caches}, not {want['diskCache']}")
    threaded = [disk for disk in disks if disk.find("driver").get("iothread") == "1"]
    if want["virtioIothread"] != bool(threaded) or any(
        disk.find("target").get("bus") != "virtio" for disk in threaded
    ):
        fail(name, "only virtio disks, and all of them, use the I/O thread")

    if "gpuSlot" in want:
        ports = {
            int(controller.get("index")): controller
            for controller in root.findall("devices/controller[@type='pci']")
            if controller.get("model") == "pcie-root-port"
        }
        placed = {}
        for hostdev in root.findall("devices/hostdev[@type='pci']"):
            host = address(hostdev.find("source/address"))
            if host in want["gpuSlot"]:
                placed[host] = hostdev.find("address")
        if sorted(placed) != sorted(want["gpuSlot"]):
            fail(name, f"the GPU functions are {sorted(placed)}, not {want['gpuSlot']}")
        buses = {int(guest.get("bus"), 0) for guest in placed.values()}
        slots = {int(guest.get("slot"), 0) for guest in placed.values()}
        if len(buses) != 1 or slots != {0} or next(iter(buses)) not in ports:
            fail(
                name,
                "the GPU functions are not one card in slot 0 of one PCIe root port",
            )
        for host, guest in placed.items():
            if int(guest.get("function"), 0) != int(host[-1], 16):
                fail(name, f"{host} sits at guest function {guest.get('function')}")
        first = placed[want["gpuSlot"][0]]
        if len(placed) > 1 and first.get("multifunction") != "on":
            fail(name, "the GPU's function 0 does not declare multifunction")

    iommu = root.find("devices/iommu")
    if want["iommu"] is None:
        if iommu is not None:
            fail(name, "has an IOMMU although iommu is off")
    elif (
        iommu is None
        or iommu.get("model") != want["iommu"]
        or iommu.find("driver").get("intremap") != "on"
        or root.find("features/ioapic") is None
        or root.find("features/ioapic").get("driver") != "qemu"
    ):
        fail(
            name,
            f"has no {want['iommu']} IOMMU with interrupt remapping and a QEMU IOAPIC",
        )

    sounds = root.findall("devices/sound")
    audios = root.findall("devices/audio")
    if want["sound"] is None:
        if sounds or audios:
            fail(name, "has emulated sound although sound is off")
    elif (
        len(sounds) != 1
        or sounds[0].get("model") != "ich9"
        or sounds[0].find("codec") is None
        or sounds[0].find("codec").get("type") != want["sound"]
        or len(audios) != 1
        or audios[0].get("type") != "pipewire"
        or audios[0].get("runtimeDir") != "/run/user/1000"
        or sounds[0].find("audio") is None
        or sounds[0].find("audio").get("id") != audios[0].get("id")
    ):
        fail(
            name,
            f"has no ICH9 HD Audio with a {want['sound']} codec played through the user's PipeWire",
        )

    hidden = any(
        feature.get("name") == "hypervisor" and feature.get("policy") == "disable"
        for feature in root.findall("cpu/feature")
    )
    if hidden != want["hypervisorHidden"]:
        fail(name, f"hypervisor bit hidden is {hidden}, not {want['hypervisorHidden']}")

    serials = [
        entry.text
        for entry in root.findall("sysinfo/system/entry")
        + root.findall("sysinfo/baseBoard/entry")
        if entry.get("name") == "serial"
    ]
    if not serials or serials[0] != want["serial"]:
        fail(name, f"the system serial is {serials[:1]}, not {want['serial']}")


with open(sys.argv[1]) as handle:
    expected = json.load(handle)
for name, want in expected.items():
    check(name, want)
print(f"domain-render: {', '.join(expected)} render as declared")
