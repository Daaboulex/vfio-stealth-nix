import argparse
import difflib
import json
import pathlib
import sys

VOLATILE_SECTIONS = {"dmesg", "cpuid-latency", "iomem", "cmdline"}


def load(results):
    loaded = {}
    for result in results:
        path = pathlib.Path(result) / "evidence.json"
        if not path.exists():
            raise SystemExit(f"{result} has no evidence.json")
        loaded[pathlib.Path(result).name.split("-", 1)[1]] = json.loads(
            path.read_text()
        )
    return loaded


def summary(name, records):
    print(f"== {name}")
    for record in records:
        fields = {
            key: record[key]
            for key in (
                "finished",
                "refused",
                "kernel",
                "secure_boot",
                "seconds",
                "cpuid_cycles",
                "cpuid_leaf1_cycles",
                "rdtsc_pair_cycles",
                "hidden_permille",
                "leaf0_eax",
                "leaf0_vendor",
            )
            if key in record
        }
        boots = len(record.get("attempts", []))
        print(
            f"  {record['name']}: "
            + " ".join(f"{k}={v}" for k, v in fields.items())
            + (f" boots={boots}" if boots else "")
        )
        if record.get("vmaware"):
            print(
                f"    vmaware {record['vmaware']['percentage']}%: "
                + (" ".join(record["vmaware"]["techniques"]) or "none")
            )


def differences(name, current, baseline):
    changed = False
    old = {record["name"]: record for record in baseline}
    for record in current:
        previous = old.get(record["name"])
        if previous is None:
            print(f"  {name}/{record['name']}: new case")
            changed = True
            continue
        for key in (
            "finished",
            "refused",
            "kernel",
            "secure_boot",
            "leaf0_eax",
            "leaf0_vendor",
        ):
            if record.get(key) != previous.get(key):
                print(
                    f"  {name}/{record['name']}: {key} {previous.get(key)} -> {record.get(key)}"
                )
                changed = True
        before = set((previous.get("vmaware") or {}).get("techniques", []))
        after = set((record.get("vmaware") or {}).get("techniques", []))
        if before != after:
            changed = True
            print(
                f"  {name}/{record['name']}: vmaware "
                + " ".join(
                    [f"+{t}" for t in sorted(after - before)]
                    + [f"-{t}" for t in sorted(before - after)]
                )
            )
        sections = set(record.get("sections", {})) | set(previous.get("sections", {}))
        for section in sorted(sections - VOLATILE_SECTIONS - {"vmaware"}):
            before = previous.get("sections", {}).get(section, {}).get("output", "")
            after = record.get("sections", {}).get(section, {}).get("output", "")
            if before != after:
                changed = True
                print(f"  {name}/{record['name']}/{section}:")
                for line in difflib.unified_diff(
                    before.splitlines(), after.splitlines(), lineterm="", n=0
                ):
                    if not line.startswith(("---", "+++")):
                        print(f"    {line}")
    return changed


def main():
    parser = argparse.ArgumentParser(
        description="Show what the boot and kernel checks saw, and what changed against an older revision"
    )
    parser.add_argument("--current", nargs="+", required=True)
    parser.add_argument("--baseline", nargs="+")
    arguments = parser.parse_args()
    current = load(arguments.current)
    for name, records in current.items():
        summary(name, records)
    if arguments.baseline:
        baseline = load(arguments.baseline)
        print("== changes against the baseline")
        changed = False
        for name, records in current.items():
            changed |= differences(name, records, baseline.get(name, []))
        if not changed:
            print("  none")


if __name__ == "__main__":
    sys.exit(main())
