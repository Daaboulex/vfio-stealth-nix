import json
import pathlib
import re
import sys

DONE = "VFIO-PROBE-DONE"
STARTED = "VFIO-PROBE-START"

plan = json.loads(pathlib.Path(sys.argv[1]).read_text())
run = json.loads(pathlib.Path(sys.argv[2]).read_text())
serial = pathlib.Path(sys.argv[3])
out = pathlib.Path(sys.argv[4])
config = plan["config"]
mode = run["mode"]
seconds = run["seconds"]
boots = run["firmware_boots"]
stalled = run["stalled"]
expected_key = (
    config["hypervMode"]
    + ("-vbs" if config["vbs"] else "")
    + ("" if config["waet"] else "-nowaet")
    + ("-patched" if config.get("patchedKernel") else "")
)
vmaware_expected = set(
    json.loads(pathlib.Path(plan["vmawareExpected"]).read_text())
    .get(config["cpuVendor"], {})
    .get(expected_key, [])
)


def serial_text():
    if not serial.exists():
        return ""
    return serial.read_bytes().decode("utf-8", errors="replace").replace("\r", "")


def sections(text):
    found = {}
    for match in re.finditer(
        r"VFIO-PROBE-BEGIN (\S+)\n(.*?)VFIO-PROBE-END \1 (-?\d+)", text, re.DOTALL
    ):
        found[match.group(1)] = {"output": match.group(2), "exit": int(match.group(3))}
    return found


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


def pci_devices(found):
    output = found.get("pci-devices", {}).get("output", "")
    try:
        devices = json.loads(
            output[
                output.find("[")
                if output.lstrip().startswith("[")
                else output.find("{") :
            ]
        )
    except json.JSONDecodeError:
        return None
    return devices if isinstance(devices, list) else [devices]


def device_guard(found):
    output = found.get("device-guard", {}).get("output", "")
    try:
        return json.loads(output[output.find("{") : output.rfind("}") + 1])
    except json.JSONDecodeError:
        return None


text = serial_text()
found = sections(text)
record = {
    "name": f"windows-{mode}",
    "mode": mode,
    "seconds": seconds,
    "firmware_boots": boots,
    "firmware_lines": sorted(set(re.findall(r"BdsDxe: [^\n]*", text))),
    "started": STARTED in text,
    "finished": DONE in text,
    "qemu_exit": run["qemu_exit"],
    "sections": found,
    "vmaware": vmaware_report(found),
    "device_guard": device_guard(found),
    "pci_devices": pci_devices(found),
    "passed": run.get("passed", []),
    "verify_stealth": re.findall(
        r"^\[(?:PASS|FAIL|WARN|SKIP)\] .*$",
        found.get("verify-stealth", {}).get("output", ""),
        re.MULTILINE,
    ),
}

ended = stalled or f"QEMU exited with {run['qemu_exit']}"
failures = []
if mode == "empty":
    failures.append(
        f"no installer ISO and no installed image were given, so the domain had nothing to boot ({ended}); pass iso = /path/to/Win11.iso, or installed = an earlier result"
    )
elif stalled == "the firmware found nothing to boot":
    failures.append(
        "the firmware found nothing to boot"
        + (
            ": the installer ISO is not a bootable UEFI image, or its press-any-key prompt took no key"
            if mode == "install"
            else ": the installed disk carries no boot loader"
        )
        + f"; firmware said: {record['firmware_lines']}"
    )
elif not record["started"]:
    failures.append(
        f"Windows never ran the probe ({ended}) after {boots} firmware boots; the last screen is in vms/windows/screen.ppm of the kept build"
    )
elif not record["finished"]:
    failures.append(
        f"the probe started but did not finish ({ended}); sections seen: {sorted(found)}"
    )
else:
    if found.get("elevation", {}).get("output", "").strip() != "True":
        failures.append(
            f"the probe ran without administrator rights: {found.get('elevation')}"
        )
    cleanup = found.get("cleanup-registry", {})
    if cleanup.get("exit") != 0:
        output = cleanup.get("output", "")
        reported = re.findall(r"^\[FAIL\] .*$", output, re.MULTILINE) or output[-2000:]
        failures.append(
            f"cleanup-registry.ps1 exited with {cleanup.get('exit')}: {reported!r}"
        )
    for line in record["verify_stealth"]:
        if line.startswith("[FAIL]"):
            failures.append(f"verify-stealth.ps1: {line}")
    if found.get("verify-stealth", {}).get("exit") != 0 and not any(
        line.startswith("[FAIL]") for line in record["verify_stealth"]
    ):
        failures.append(
            f"verify-stealth.ps1 exited with {found.get('verify-stealth', {}).get('exit')}: {found.get('verify-stealth', {}).get('output', '')[-2000:]!r}"
        )
    if record["vmaware"] is None:
        failures.append(
            f"VMAware gave no report; its run exited {found.get('vmaware-run', {}).get('exit')}: {found.get('vmaware-run', {}).get('output', '')[-2000:]!r}"
        )
    else:
        for technique in sorted(
            set(record["vmaware"]["techniques"]) - vmaware_expected
        ):
            failures.append(
                f"VMAware detects {technique}, which verify/vmaware-expected-windows.json does not expect for cpuVendor {config['cpuVendor']} and {expected_key}"
            )
        for technique in sorted(
            vmaware_expected - set(record["vmaware"]["techniques"])
        ):
            print(
                f"VMAware no longer detects {technique}; verify/vmaware-expected-windows.json still expects it for cpuVendor {config['cpuVendor']} and {expected_key}"
            )
    guard = record["device_guard"] or {}
    if config["vbs"] and (
        guard.get("VirtualizationBasedSecurityStatus") != 2
        or 2 not in (guard.get("SecurityServicesRunning") or [])
    ):
        failures.append(
            f"VBS was switched on, but Win32_DeviceGuard reports VirtualizationBasedSecurityStatus {guard.get('VirtualizationBasedSecurityStatus')} and SecurityServicesRunning {guard.get('SecurityServicesRunning')}; running VBS with HVCI reports 2 and a running service 2"
        )
    for index, device in enumerate(record["passed"]):
        want = f"VEN_{device['vendor'][2:].upper()}&DEV_{device['device'][2:].upper()}"
        listed = [
            entry
            for entry in record["pci_devices"] or []
            if want in (entry.get("InstanceId") or "").upper()
        ]
        if not listed:
            failures.append(
                f"Windows lists no PCI device {want}, the passed-through {device['address']}"
            )
        elif index == 0 and not any(entry.get("Status") == "OK" for entry in listed):
            failures.append(
                f"Windows lists the passed-through GPU {want} as {[entry.get('Status') for entry in listed]}, not OK"
            )
        else:
            print(
                f"windows: passed-through {device['address']} is {listed[0].get('FriendlyName')} ({listed[0].get('Status')})"
            )
    if record["device_guard"] is None:
        failures.append(
            f"Win32_DeviceGuard gave no report: {found.get('device-guard', {}).get('output', '')[-2000:]!r}"
        )

out.mkdir(exist_ok=True)
(out / "evidence.json").write_text(json.dumps([record], indent=2))
print(
    f"windows: mode={mode} started={record['started']} finished={record['finished']} seconds={seconds} firmware_boots={boots}"
)
if record["vmaware"]:
    print(f"windows: vmaware {' '.join(record['vmaware']['techniques']) or 'none'}")
if record["device_guard"]:
    print(
        "windows: device guard "
        + " ".join(
            f"{key}={record['device_guard'].get(key)}"
            for key in (
                "VirtualizationBasedSecurityStatus",
                "SecurityServicesRunning",
                "SecurityServicesConfigured",
            )
        )
    )
if failures:
    print("\n".join(failures))
    sys.exit(1)
