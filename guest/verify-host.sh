#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
    echo "usage: verify-host.sh <libvirt-domain>" >&2
    exit 2
fi
DOMAIN=$1
FAIL=0
WARN=0

pass() { printf "\033[32m[PASS]\033[0m %s\n" "$1"; }
fail() {
    printf "\033[31m[FAIL]\033[0m %s\n" "$1"
    FAIL=$((FAIL + 1))
}
warn() {
    printf "\033[33m[WARN]\033[0m %s\n" "$1"
    WARN=$((WARN + 1))
}
skip() { printf "\033[33m[SKIP]\033[0m %s\n" "$1"; }

matches() {
    local n
    n=$(grep -c -- "$1" <<<"$XML") || [[ $? -eq 1 ]]
    echo "${n:-0}"
}

echo "=== vfio-stealth host verification (domain: $DOMAIN) ==="
echo ""

if [[ -d /sys/kernel/iommu_groups ]]; then
    MIXED=0
    for group in /sys/kernel/iommu_groups/*; do
        [[ -d "$group/devices" ]] || continue
        if (($(find "$group/devices" -mindepth 1 -maxdepth 1 | wc -l) > 1)); then
            MIXED=1
        fi
    done
    if [[ $MIXED -eq 0 ]]; then
        pass "IOMMU: every group holds one device"
    else
        warn "IOMMU: some groups hold several devices"
    fi
else
    fail "IOMMU: /sys/kernel/iommu_groups is absent, the IOMMU is off"
fi

if QEMU_PIDS=$(pgrep -f "qemu-system.*guest=$DOMAIN,"); then
    QEMU_PID=${QEMU_PIDS%%$'\n'*}
    SECCOMP=$(awk '/^Seccomp:/ { print $2 }' "/proc/$QEMU_PID/status")
    case "$SECCOMP" in
        2) pass "Seccomp: QEMU $QEMU_PID runs with a seccomp filter" ;;
        1) warn "Seccomp: QEMU $QEMU_PID runs in strict mode, a filter is expected" ;;
        0) fail "Seccomp: QEMU $QEMU_PID runs without seccomp" ;;
        *) fail "Seccomp: /proc/$QEMU_PID/status has no Seccomp line" ;;
    esac
else
    skip "No QEMU runs for domain '$DOMAIN'"
fi

XML=""
if ! command -v virsh >/dev/null; then
    skip "virsh is not on PATH"
elif ! XML=$(virsh -c qemu:///system dumpxml "$DOMAIN" 2>&1); then
    fail "virsh dumpxml $DOMAIN: $XML"
    XML=""
fi

if [[ -n "$XML" ]]; then
    if grep -q "<sysinfo type='smbios'>" <<<"$XML"; then
        pass "SMBIOS: the domain has a sysinfo block"
    else
        fail "SMBIOS: the domain has no sysinfo block"
    fi
    if grep -q "smbios mode='sysinfo'" <<<"$XML"; then
        pass "SMBIOS: os smbios mode is sysinfo"
    else
        fail "SMBIOS: os smbios mode is not sysinfo"
    fi

    BALLOON=$(matches "memballoon model='virtio'")
    RNG=$(matches "<rng model='virtio'")
    if [[ "$BALLOON" -gt 0 ]]; then
        fail "The domain has a VirtIO memory balloon"
    fi
    if [[ "$RNG" -gt 0 ]]; then
        fail "The domain has a VirtIO RNG"
    fi
    if [[ "$BALLOON" -eq 0 && "$RNG" -eq 0 ]]; then
        pass "No VirtIO balloon or RNG in the domain"
    fi
    if [[ $(matches "1af4\|1b36\|1234") -gt 0 ]]; then
        warn "The domain names a Red Hat or QEMU PCI vendor ID"
    else
        pass "No Red Hat or QEMU PCI vendor ID in the domain"
    fi

    if grep -q "<hidden state='on'/>" <<<"$XML"; then
        pass "KVM hidden: on"
    else
        fail "KVM hidden: not set in the domain"
    fi
    if grep -q "vendor_id" <<<"$XML"; then
        VENDOR_ID=$(sed -n "s/.*vendor_id[^>]*value='\([^']*\)'.*/\1/p" <<<"$XML")
        if [[ "$VENDOR_ID" == "Microsoft Hv" || "$VENDOR_ID" == "KVMKVMKVM" || "$VENDOR_ID" == "AMDisbetter!" ]]; then
            fail "Hyper-V vendor_id is a known VM value: $VENDOR_ID"
        else
            pass "Hyper-V vendor_id: $VENDOR_ID"
        fi
    else
        warn "Hyper-V vendor_id is not set"
    fi

    ACPI_TABLES=$(matches "acpitable")
    if [[ "$ACPI_TABLES" -ge 2 ]]; then
        pass "ACPI: $ACPI_TABLES extra tables loaded"
    elif [[ "$ACPI_TABLES" -ge 1 ]]; then
        warn "ACPI: only $ACPI_TABLES extra table loaded"
    else
        warn "ACPI: no extra ACPI tables in the domain"
    fi

    if grep -q '<panic' <<<"$XML"; then
        fail "The domain has a <panic> device, which shows ACPI HID QEMU0001"
    else
        pass "No <panic> device in the domain"
    fi

    SMBIOS_DIR=""
    if [[ $XML =~ (/nix/store/[^\"\']+/share/smbios) ]]; then
        SMBIOS_DIR=${BASH_REMATCH[1]}
    fi
    if [[ -n "$SMBIOS_DIR" && -d "$SMBIOS_DIR" ]]; then
        MISSING=0
        for table in type7-l1.bin type7-l2.bin type7-l3.bin type26.bin type27.bin type28.bin type29.bin; do
            [[ -s "$SMBIOS_DIR/$table" ]] || MISSING=$((MISSING + 1))
        done
        if [[ $MISSING -eq 0 ]]; then
            pass "SMBIOS tables: all present"
        else
            fail "SMBIOS tables: $MISSING missing in $SMBIOS_DIR"
        fi
    else
        warn "SMBIOS tables: the domain names no smbios store path"
    fi
fi

BT_SYMS=(handle_rdtsc_interception handle_rdtscp_interception)
if [[ -r /proc/kallsyms ]]; then
    BT_FOUND=0
    BT_MISSING=""
    for sym in "${BT_SYMS[@]}"; do
        if grep -q -w "$sym" /proc/kallsyms; then
            BT_FOUND=$((BT_FOUND + 1))
        else
            BT_MISSING="$BT_MISSING $sym"
        fi
    done
    if [[ $BT_FOUND -eq ${#BT_SYMS[@]} ]]; then
        pass "BetterTiming: all ${#BT_SYMS[@]} patched handlers present"
    elif [[ $BT_FOUND -eq 0 ]]; then
        skip "BetterTiming: not in this kernel, timing.enable is off or the host is Intel"
    else
        fail "BetterTiming: only $BT_FOUND of ${#BT_SYMS[@]} handlers present, missing:$BT_MISSING"
    fi
else
    skip "BetterTiming: /proc/kallsyms is not readable"
fi

CMDLINE=$(</proc/cmdline)
if [[ -d /sys/module/kvm_amd ]]; then
    for param in kvm_amd.vls=0 kvm_amd.vgif=0; do
        if grep -q -w "$param" <<<"$CMDLINE"; then
            pass "Kernel parameter: $param"
        else
            fail "Kernel parameter: $param missing"
        fi
    done
else
    skip "kvm_amd is not loaded, so its parameters do not apply"
fi
if grep -q -w "tsc=reliable" <<<"$CMDLINE"; then
    pass "Kernel parameter: tsc=reliable"
else
    warn "Kernel parameter: tsc=reliable is not set"
fi

if [[ -r /sys/module/kvm/parameters/ignore_msrs ]]; then
    case "$(</sys/module/kvm/parameters/ignore_msrs)" in
        Y | 1) pass "KVM: ignore_msrs is on, so Windows' HWCR write does not fault" ;;
        *) warn "KVM: ignore_msrs is off, Windows faults on its HWCR write during boot" ;;
    esac
else
    warn "KVM: /sys/module/kvm/parameters/ignore_msrs is not readable"
fi

if [[ -n "$XML" ]]; then
    QEMU_PATH=$(sed -n 's|.*<emulator>\(.*\)</emulator>.*|\1|p' <<<"$XML")
    if [[ -z "$QEMU_PATH" ]]; then
        QEMU_PATH=$(virsh -c qemu:///system capabilities | sed -n '/<arch name=.x86_64.>/,/<\/arch>/s|.*<emulator>\(.*\)</emulator>.*|\1|p' )
        QEMU_PATH=${QEMU_PATH%%$'\n'*}
    fi
    if [[ -z "$QEMU_PATH" ]]; then
        fail "Neither the domain nor libvirt names an x86_64 emulator"
    else
        QEMU_BIN=$(readlink -f "$QEMU_PATH")
        if [[ "$QEMU_BIN" == *qemu-stealth* ]]; then
            pass "QEMU: $QEMU_PATH is qemu-stealth"
        else
            fail "QEMU: $QEMU_PATH is $QEMU_BIN, not qemu-stealth"
        fi
        if ! command -v strings >/dev/null; then
            skip "QEMU identity strings: strings is not on PATH"
        else
            QEMU_STRINGS=$(strings "$QEMU_BIN")
            for pair in "RHT:EDID manufacturer" "BOCHS :ACPI OEM ID" "BXPC    :ACPI table ID" \
                "QEMU HARDDISK:IDE disk model" "QEMU DVD-ROM:IDE optical model" \
                "QEMU    :SCSI vendor" "QEMU USB:USB HID names"; do
                needle=${pair%%:*}
                what=${pair#*:}
                if grep -q -F -- "$needle" <<<"$QEMU_STRINGS"; then
                    fail "QEMU still carries the stock $what ($needle)"
                else
                    pass "QEMU: $what replaced"
                fi
            done
        fi
    fi
fi

echo ""
if [[ $FAIL -eq 0 && $WARN -eq 0 ]]; then
    printf "\033[32m=== All checks passed ===\033[0m\n"
elif [[ $FAIL -eq 0 ]]; then
    printf "\033[33m=== 0 failures, %d warnings ===\033[0m\n" "$WARN"
else
    printf "\033[31m=== %d failures, %d warnings ===\033[0m\n" "$FAIL" "$WARN"
fi

exit "$FAIL"
