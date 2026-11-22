import argparse
import json
import pathlib
import sys

BARE_METAL = {
    "amd": {"vmload": "ill", "vmcall": "ill", "vmmcall": "ill"},
    "intel": {"vmcall": "ill"},
}
HIDDEN_FLOOR_PERMILLE = 100
HIDDEN_NOISE_PERMILLE = 30
PASSTHROUGH_NATIVE_FACTOR = 2


def cost(record):
    return record["cpuid_leaf1_cycles"] - record["rdtsc_pair_cycles"]


def native_cost(record):
    return record["native_cpuid_leaf1_cycles"] - record["native_rdtsc_pair_cycles"]


def exits(record):
    return cost(record) > PASSTHROUGH_NATIVE_FACTOR * native_cost(record)


def signals(record, bare_metal):
    return {name: record["instructions"][name].split()[0] for name in bare_metal}


def describe(record):
    return (
        f"{record['name']}: CPUID leaf 0 {record['cpuid_cycles']} cycles, leaf 1 {record['cpuid_leaf1_cycles']} "
        f"(least {record['cpuid_leaf1_min']}), two RDTSC reads {record['rdtsc_pair_cycles']}, so a leaf 1 costs {cost(record)}; "
        f"a leaf 1 of the VM it runs in costs {native_cost(record)}; hidden from the TSC {record['hidden_permille'] / 10}%; "
        f"leaf 0 {record['leaf0_eax']:#x} {record['leaf0_vendor']}; brand {record['brand']!r}; "
        + ", ".join(f"{k} {v}" for k, v in record["instructions"].items())
    )


def judge(switches, records):
    failures = []
    bare_metal = BARE_METAL[switches["cpuVendor"]]
    stock = next(record for record in records if record["name"] == "stock")
    bound = f"{PASSTHROUGH_NATIVE_FACTOR} times what a CPUID of the VM the guest runs in costs"
    if abs(stock["hidden_permille"]) > HIDDEN_NOISE_PERMILLE:
        failures.append(
            f"the stock kernel hides {stock['hidden_permille'] / 10}% of a CPUID loop from the TSC against the PM timer; it hides nothing, so the measurement is off"
        )
    if signals(stock, bare_metal) == bare_metal:
        failures.append(
            f"the stock kernel already raises #UD for {', '.join(bare_metal)}, so this test cannot tell the instruction fixes apart"
        )
    if not exits(stock):
        failures.append(
            f"a CPUID under the stock kernel costs {cost(stock)} cycles, within {bound}, so the passthrough bound cannot tell an exit apart"
        )
    for record in records:
        if record["name"] == "stock":
            continue
        name = record["name"]
        passthrough = switches["cpuidPassthrough"] or record["cpuid_passthrough"]
        if passthrough and exits(record):
            failures.append(
                f"{name}: a CPUID leaf 1 costs {cost(record)} cycles over two RDTSC reads, more than {bound} ({native_cost(record)}); with CPUID passthrough it must not exit to the patched KVM"
            )
        if not passthrough and not exits(record):
            failures.append(
                f"{name}: a CPUID leaf 1 costs {cost(record)} cycles over two RDTSC reads, within {bound} ({native_cost(record)}); without CPUID passthrough it exits to the patched KVM"
            )
        if (
            switches["cpuidSpoof"]
            and not passthrough
            and (
                record["leaf0_eax"],
                record["leaf0_vendor"],
            )
            != (stock["leaf0_eax"], stock["leaf0_vendor"])
        ):
            failures.append(
                f"{name}: CPUID leaf 0 is {record['leaf0_eax']:#x} {record['leaf0_vendor']}, under the stock kernel {stock['leaf0_eax']:#x} {stock['leaf0_vendor']}; the fast path must answer what KVM itself would"
            )
        if record["rdtsc_handlers"] != (2 if switches["timing"] else 0):
            failures.append(
                f"{name}: /proc/kallsyms lists {record['rdtsc_handlers']} of handle_rdtsc_interception and handle_rdtscp_interception, which guest/verify-host.sh reads for the timing patch; it must list both with it and neither without"
            )
        if switches["timing"] and record["cpuid_leaf1_min"] == 0:
            failures.append(
                f"{name}: the guest TSC stood still across a CPUID exit; the timing patch hides the guest's own run time"
            )
        hidden = record["hidden_permille"]
        if switches["timing"] and not passthrough:
            if hidden < HIDDEN_FLOOR_PERMILLE:
                failures.append(
                    f"{name}: {hidden / 10}% of a CPUID loop is hidden from the TSC against the PM timer, under {HIDDEN_FLOOR_PERMILLE / 10}%; the timing patch hides KVM's handling of every CPUID exit"
                )
        elif abs(hidden) > HIDDEN_NOISE_PERMILLE:
            failures.append(
                f"{name}: {hidden / 10}% of a CPUID loop is hidden from the TSC against the PM timer, more than {HIDDEN_NOISE_PERMILLE / 10}%; without the timing patch, or with no CPUID exit to time, nothing is hidden"
            )
        fixed = signals(record, bare_metal) == bare_metal
        if switches["instructionFixes"] and not fixed:
            failures.append(
                f"{name}: {', '.join(bare_metal)} raise {signals(record, bare_metal)}; with the instruction fixes each raises #UD, an illegal instruction, as on bare metal"
            )
        if not switches["instructionFixes"] and fixed:
            failures.append(
                f"{name}: {', '.join(bare_metal)} all raise #UD without the instruction fixes, so the probe cannot tell them apart"
            )
        if (
            switches["instructionFixes"]
            and switches["cpuVendor"] == "amd"
            and record["instructions"]["icebp"] != "trap after"
        ):
            failures.append(
                f"{name}: ICEBP raises {record['instructions']['icebp']}; its #DB reports the address after the instruction"
            )
        if record["instructions"]["cpuidstep"] != "trap after":
            failures.append(
                f"{name}: a single-stepped CPUID leaf 0 raises {record['instructions']['cpuidstep']}; on hardware its #DB reports the address after the CPUID"
            )
        if record["cpuid_passthrough"]:
            if record["name_msr_programmable"]:
                if record["brand"] != record["brand_string"]:
                    failures.append(
                        f"{name}: CPUID 0x80000002 to 0x80000004 read {record['brand']!r}, not kvm_amd.brand_string {record['brand_string']!r}"
                    )
            else:
                print(
                    f"{name}: the VM the guest runs in cannot program the processor name MSRs, so kvm_amd.brand_string cannot reach the guest; it read {record['brand']!r}"
                )
    if switches["pinned"] and not any(
        record["cpuid_passthrough"] for record in records
    ):
        failures.append(
            "cpuidPassthrough.pinned is on, but no guest ran with kvm_amd.cpuid_passthrough switched on"
        )
    return failures


def main():
    parser = argparse.ArgumentParser(
        description="Judge what kernel-runtime's guests saw against the kernel switches their kernel was built with"
    )
    parser.add_argument("--switches", required=True, type=pathlib.Path)
    parser.add_argument("evidence", type=pathlib.Path)
    arguments = parser.parse_args()
    switches = json.loads(arguments.switches.read_text())
    records = json.loads(arguments.evidence.read_text())
    print(f"switches: {switches}")
    for record in records:
        print(describe(record))
    failures = judge(switches, records)
    for failure in failures:
        print(f"[FAIL] {failure}")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
