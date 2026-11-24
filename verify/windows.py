import atexit
import json
import os
import pathlib
import shlex
import shutil
import signal
import socket
import subprocess
import sys
import time
from xml.etree import ElementTree

POLL_SECONDS = 2
SCREEN_SECONDS = 60
# why: Windows Setup opens with Cancel focused, so a space that lands after the five-second boot prompt cancels the install
KEY_SECONDS = 8
DONE = "VFIO-PROBE-DONE"
BOOTING = "BdsDxe: starting"
NO_OPTION = "No bootable option or device was found"

plan = json.loads(pathlib.Path(sys.argv[1]).read_text())
out = pathlib.Path(sys.argv[2])
installer = plan["installer"]
installed = plan["installed"]
mode = "install" if installer else "installed" if installed else "empty"
deadline = plan["seconds"][mode]
work = pathlib.Path.cwd() / "vms" / "windows"
work.mkdir(parents=True)


def run(*argv):
    subprocess.run([str(a) for a in argv], check=True)


def prepare_disk():
    disk = work / "disk.qcow2"
    if installed:
        source = pathlib.Path(installed)
        missing = [
            name
            for name in ("disk.qcow2", "vars.fd", "tpm")
            if not (source / name).exists()
        ]
        if missing:
            raise SystemExit(
                f"{source} is not the output of an install run: it lacks {', '.join(missing)}"
            )
        run("cp", "--reflink=auto", source / "disk.qcow2", disk)
        run("cp", source / "vars.fd", work / "vars.fd")
        run("cp", "-r", source / "tpm", work / "tpm")
        for path in [disk, work / "vars.fd", *(work / "tpm").rglob("*")]:
            path.chmod(0o755 if path.is_dir() else 0o644)
        (work / "tpm").chmod(0o755)
    else:
        run("qemu-img", "create", "-q", "-f", "qcow2", disk, plan["diskSize"])
    return disk


def start_tpm():
    state = work / "tpm"
    if not installed:
        state.mkdir()
        localca = work / "localca"
        localca.mkdir()
        (work / "swtpm-localca.conf").write_text(
            f"statedir = {localca}\n"
            f"signingkey = {localca}/signkey.pem\n"
            f"issuercert = {localca}/issuercert.pem\n"
            f"certserial = {localca}/certserial\n"
        )
        (work / "swtpm_setup.conf").write_text(
            f"create_certs_tool = {plan['swtpm']}/bin/swtpm_localca\n"
            f"create_certs_tool_config = {work}/swtpm-localca.conf\n"
            f"create_certs_tool_options = {plan['swtpm']}/etc/swtpm-localca.options\n"
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
                str(work / "swtpm_setup.conf"),
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
            f"type=unixio,path={work}/swtpm.sock",
            "--flags",
            "startup-clear",
        ]
    )


def domain_xml(disk):
    tree = ElementTree.parse(plan["xml"])
    root = tree.getroot()
    devices = root.find("devices")
    sources = {
        "/windows/disk.qcow2": str(disk),
        "/windows/installer.iso": installer or "",
        "/windows/probe.iso": plan["media"],
    }
    for element in devices.findall("disk"):
        source = element.find("source")
        if sources.get(source.get("file")) == "":
            devices.remove(element)
        else:
            source.set("file", sources[source.get("file")])
    nic = []
    for interface in devices.findall("interface"):
        mac = interface.find("mac")
        model = interface.find("model").get("type")
        nic += [
            "-netdev",
            "user,id=probe-net,restrict=on",
            "-device",
            f"{model},netdev=probe-net,bus=pcie.0,addr=0x1e"
            + (f",mac={mac.get('address')}" if mac is not None else ""),
        ]
        devices.remove(interface)
    tree.write(work / "domain.xml")
    nvram = root.find("os/nvram")
    if not installed:
        shutil.copy(nvram.get("template"), work / "vars.fd")
        (work / "vars.fd").chmod(0o644)
    return nvram.text, nic


def libvirt_argv():
    result = subprocess.run(
        [
            "virsh",
            "-c",
            f"qemu:///embed?root={work}/libvirt",
            "domxml-to-native",
            "qemu-argv",
            str(work / "domain.xml"),
        ],
        capture_output=True,
        text=True,
        check=False,
    )
    if result.returncode != 0:
        raise SystemExit(f"libvirt refused the Windows domain: {result.stderr}")
    tokens = shlex.split(result.stdout)
    start = next(i for i, t in enumerate(tokens) if t.endswith("qemu-system-x86_64"))
    return tokens[start:]


def adapt(argv, nvram_path):
    adapted = []
    i = 0
    while i < len(argv):
        token = argv[i]
        value = argv[i + 1] if i + 1 < len(argv) else ""
        if token in ("-S", "-no-shutdown"):
            i += 1
            continue
        if token == "-object" and ("masterKey0" in value or "monitor-qmp" in value):
            i += 2
            continue
        if token == "-chardev" and value.startswith("socket,id=charmonitor"):
            i += 2
            continue
        if token == "-chardev" and value.startswith("null,id=chrtpm"):
            adapted += [token, f"socket,id=chrtpm,path={work}/swtpm.sock"]
            i += 2
            continue
        adapted.append(token.replace(nvram_path, str(work / "vars.fd")))
        i += 1
    return [
        *adapted,
        "-chardev",
        f"file,id=probe-serial,path={work}/serial.log",
        "-device",
        "isa-serial,chardev=probe-serial,index=0",
        "-qmp",
        f"unix:{work}/qmp.sock,server=on,wait=off",
    ]


class Monitor:
    def __init__(self, path):
        self.connection = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        self.connection.settimeout(30)
        for _ in range(50):
            try:
                self.connection.connect(str(path))
                break
            except (FileNotFoundError, ConnectionRefusedError):
                time.sleep(0.2)
        else:
            raise SystemExit(f"QEMU opened no monitor at {path}: {qemu_log()}")
        self.reader = self.connection.makefile("r")
        self.reader.readline()
        self.command("qmp_capabilities")

    def command(self, name, arguments=None):
        message = {"execute": name} | ({"arguments": arguments} if arguments else {})
        try:
            self.connection.sendall(json.dumps(message).encode() + b"\n")
        except OSError as error:
            return {"error": f"QEMU closed the monitor: {error}"}
        while True:
            try:
                line = self.reader.readline()
            except OSError as error:
                return {"error": f"QEMU closed the monitor: {error}"}
            if not line:
                return {"error": "QEMU closed the monitor"}
            reply = json.loads(line)
            if "return" in reply or "error" in reply:
                return reply


def serial_text():
    path = work / "serial.log"
    if not path.exists():
        return ""
    return path.read_bytes().decode("utf-8", errors="replace").replace("\r", "")


def stop(process):
    if process.poll() is None:
        process.kill()
    process.wait()


def qemu_log():
    path = work / "qemu.log"
    return path.read_text()[-2000:] if path.exists() else ""


disk = prepare_disk()
nvram_path, nic = domain_xml(disk)
tpm = start_tpm()
signal.signal(signal.SIGTERM, lambda *_: sys.exit(1))
atexit.register(stop, tpm)
argv = adapt(libvirt_argv(), nvram_path) + nic
(work / "argv.json").write_text(json.dumps(argv, indent=1))
print(
    f"windows: {mode} run, up to {deadline} s, QEMU log in {work}/qemu.log", flush=True
)
with open(work / "qemu.log", "w") as log:
    qemu = subprocess.Popen(argv, cwd=work, stdout=log, stderr=subprocess.STDOUT)
atexit.register(stop, qemu)
monitor = Monitor(work / "qmp.sock")


def cpu_set(text):
    result = set()
    for part in text.split(","):
        first, _, last = part.partition("-")
        result.update(range(int(first), int(last or first) + 1))
    return result


def pin_threads():
    tune = ElementTree.parse(work / "domain.xml").getroot().find("cputune")
    if tune is None:
        return
    vcpus = {
        int(pin.get("vcpu")): cpu_set(pin.get("cpuset"))
        for pin in tune.findall("vcpupin")
    }
    threads = {
        entry["cpu-index"]: entry["thread-id"]
        for entry in monitor.command("query-cpus-fast")["return"]
    }
    for index, thread in threads.items():
        if index in vcpus:
            os.sched_setaffinity(thread, vcpus[index])
    emulator = tune.find("emulatorpin")
    if emulator is not None:
        for task in os.listdir(f"/proc/{qemu.pid}/task"):
            if int(task) not in threads.values():
                os.sched_setaffinity(int(task), cpu_set(emulator.get("cpuset")))
    print(
        f"windows: pinned {len(vcpus)} vCPUs as the domain's cputune says",
        flush=True,
    )


pin_threads()
began = time.monotonic()
keys_until = None
last_screen = 0
boots = 0
stalled = None
while qemu.poll() is None:
    elapsed = time.monotonic() - began
    text = serial_text()
    seen_boots = text.count(BOOTING)
    if seen_boots != boots:
        boots = seen_boots
        print(f"windows: firmware boot {boots} at {round(elapsed)} s", flush=True)
        if mode == "install" and keys_until is None:
            keys_until = elapsed + KEY_SECONDS
    if keys_until is not None and elapsed < keys_until:
        monitor.command("send-key", {"keys": [{"type": "qcode", "data": "spc"}]})
    if elapsed - last_screen >= SCREEN_SECONDS:
        monitor.command("screendump", {"filename": str(work / "screen.ppm")})
        last_screen = elapsed
    if NO_OPTION in text:
        stalled = "the firmware found nothing to boot"
        break
    if elapsed >= deadline:
        stalled = f"no shutdown after {deadline} s"
        break
    time.sleep(POLL_SECONDS if keys_until is None or elapsed >= keys_until else 1)
seconds = round(time.monotonic() - began)
if qemu.poll() is None:
    monitor.command("screendump", {"filename": str(work / "screen.ppm")})
stop(qemu)
stop(tpm)

passed = [
    {
        "address": address,
        "vendor": pathlib.Path(f"/sys/bus/pci/devices/{address}/vendor")
        .read_text()
        .strip(),
        "device": pathlib.Path(f"/sys/bus/pci/devices/{address}/device")
        .read_text()
        .strip(),
    }
    for address in plan.get("gpu", [])
]
(work / "run.json").write_text(
    json.dumps(
        {
            "passed": passed,
            "mode": mode,
            "seconds": seconds,
            "firmware_boots": boots,
            "stalled": stalled,
            "qemu_exit": qemu.returncode,
        }
    )
)
verdict = subprocess.run(
    [
        sys.executable,
        "-I",
        plan["judge"],
        sys.argv[1],
        work / "run.json",
        work / "serial.log",
        out,
    ],
    check=False,
)
for name in ("serial.log", "argv.json", "domain.xml", "qemu.log", "screen.ppm"):
    if (work / name).exists():
        shutil.copy(work / name, out / name)
if verdict.returncode != 0:
    sys.exit(1)
if mode == "install":
    shutil.move(work / "disk.qcow2", out / "disk.qcow2")
    shutil.move(work / "vars.fd", out / "vars.fd")
    shutil.move(work / "tpm", out / "tpm")
