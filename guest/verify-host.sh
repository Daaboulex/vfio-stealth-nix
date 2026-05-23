#!/usr/bin/env bash
# vfio-stealth host-side verification
# Checks kernel patches, IOMMU groups, QEMU config, and domain XML
#
# Usage: ./verify-host.sh [domain-name]
#   domain-name: libvirt domain to inspect (default: win11)

set -euo pipefail

DOMAIN="${1:-win11}"
FAIL=0
WARN=0

pass() { printf "\033[32m[PASS]\033[0m %s\n" "$1"; }
fail() { printf "\033[31m[FAIL]\033[0m %s\n" "$1"; ((FAIL++)); }
warn() { printf "\033[33m[WARN]\033[0m %s\n" "$1"; ((WARN++)); }
skip() { printf "\033[33m[SKIP]\033[0m %s\n" "$1"; }

echo "=== vfio-stealth host verification (domain: $DOMAIN) ==="
echo ""

# -----------------------------------------------------------------------
# 1. BetterTiming kernel patch — check for markers in running kernel config
# -----------------------------------------------------------------------
if [[ -f /proc/config.gz ]]; then
    # BetterTiming patches kvm_get_msr_common; check if KVM is built-in or module
    if zcat /proc/config.gz | grep -q "CONFIG_KVM="; then
        # Check kernel source markers via /sys if available, else check module symbols
        if grep -q "total_exit_time" /proc/kallsyms 2>/dev/null; then
            pass "BetterTiming: total_exit_time symbol found in kernel"
        else
            warn "BetterTiming: total_exit_time symbol not found (patch may not be applied)"
        fi
    else
        skip "KVM not configured in kernel"
    fi
else
    # Fallback: check loaded module
    if lsmod | grep -q "^kvm "; then
        if grep -q "total_exit_time" /proc/kallsyms 2>/dev/null; then
            pass "BetterTiming: total_exit_time symbol found"
        else
            warn "BetterTiming: total_exit_time not in kallsyms (may need CONFIG_KALLSYMS_ALL)"
        fi
    else
        skip "KVM module not loaded"
    fi
fi

# -----------------------------------------------------------------------
# 2. CPUID spoofing patch — check for Hypervisor-Phantom marker
# -----------------------------------------------------------------------
if grep -q "cpuid_leaf0_spoof" /proc/kallsyms 2>/dev/null; then
    pass "CPUID spoof: cpuid_leaf0_spoof symbol found"
elif grep -q "reenter_guest_fast" /proc/kallsyms 2>/dev/null; then
    pass "CPUID spoof: reenter_guest_fast symbol found"
else
    warn "CPUID spoof: no Hypervisor-Phantom symbols in kallsyms"
fi

# -----------------------------------------------------------------------
# 3. IOMMU groups — check for clean passthrough groups
# -----------------------------------------------------------------------
if [[ -d /sys/kernel/iommu_groups ]]; then
    MIXED=0
    for grp in /sys/kernel/iommu_groups/*/devices/*; do
        [[ -e "$grp" ]] || continue
        GRP_DIR=$(dirname "$grp")
        DEV_COUNT=$(find "$GRP_DIR" -maxdepth 1 -mindepth 1 2>/dev/null | wc -l)
        if [[ $DEV_COUNT -gt 1 ]]; then
            # Check if ACS override is handling it
            MIXED=1
        fi
    done
    if [[ $MIXED -eq 0 ]]; then
        pass "IOMMU: all groups have single devices (clean isolation)"
    else
        warn "IOMMU: some groups have multiple devices (ACS override may be needed)"
    fi
else
    fail "IOMMU: /sys/kernel/iommu_groups not found (IOMMU not enabled)"
fi

# -----------------------------------------------------------------------
# 4. Seccomp on running QEMU process
# -----------------------------------------------------------------------
QEMU_PID=$(pgrep -f "qemu-system.*$DOMAIN" 2>/dev/null | head -1 || true)
if [[ -n "$QEMU_PID" ]]; then
    SECCOMP=$(cat "/proc/$QEMU_PID/status" 2>/dev/null | grep "Seccomp:" | awk '{print $2}')
    case "$SECCOMP" in
        2) pass "Seccomp: QEMU PID $QEMU_PID has seccomp filter active" ;;
        1) warn "Seccomp: QEMU PID $QEMU_PID in strict mode (expected filter)" ;;
        0) fail "Seccomp: QEMU PID $QEMU_PID has NO seccomp (sandbox disabled)" ;;
        *) skip "Seccomp: could not read status for PID $QEMU_PID" ;;
    esac
else
    skip "No running QEMU process for domain '$DOMAIN'"
fi

# -----------------------------------------------------------------------
# 5. SMBIOS injection — check domain XML
# -----------------------------------------------------------------------
if command -v virsh &>/dev/null; then
    XML=$(virsh dumpxml "$DOMAIN" 2>/dev/null || true)
    if [[ -n "$XML" ]]; then
        # Check sysinfo smbios block
        if echo "$XML" | grep -q "<sysinfo type='smbios'>"; then
            pass "SMBIOS: sysinfo block present in domain XML"
        else
            fail "SMBIOS: no sysinfo block in domain XML"
        fi

        # Check os smbios mode
        if echo "$XML" | grep -q "smbios mode='sysinfo'"; then
            pass "SMBIOS: os smbios mode=sysinfo set"
        else
            fail "SMBIOS: os smbios mode not set to sysinfo"
        fi
    else
        skip "Could not dump XML for domain '$DOMAIN'"
    fi
else
    skip "virsh not found"
fi

# -----------------------------------------------------------------------
# 6. Red Hat PCI devices in domain XML
# -----------------------------------------------------------------------
if [[ -n "${XML:-}" ]]; then
    # Check for VirtIO devices that should have been stripped
    BALLOON=$(echo "$XML" | grep -c "memballoon model='virtio'" 2>/dev/null || echo "0")
    RNG=$(echo "$XML" | grep -c "<rng model='virtio'" 2>/dev/null || echo "0")

    if [[ "$BALLOON" -gt 0 ]]; then
        fail "VirtIO balloon device present (should be stripped)"
    fi
    if [[ "$RNG" -gt 0 ]]; then
        fail "VirtIO RNG device present (should be stripped)"
    fi
    if [[ "$BALLOON" -eq 0 && "$RNG" -eq 0 ]]; then
        pass "No VirtIO balloon/RNG devices in domain XML"
    fi

    # Check QEMU command line for Red Hat PCI vendor IDs
    QEMU_CMD=$(echo "$XML" | grep -c "1af4\|1b36\|1234" 2>/dev/null || echo "0")
    if [[ "$QEMU_CMD" -gt 0 ]]; then
        warn "Red Hat/QEMU PCI vendor IDs referenced in domain XML"
    else
        pass "No Red Hat PCI vendor IDs in domain XML"
    fi
fi

# -----------------------------------------------------------------------
# 7. KVM hidden + Hyper-V vendor_id
# -----------------------------------------------------------------------
if [[ -n "${XML:-}" ]]; then
    if echo "$XML" | grep -q "<hidden state='on'/>"; then
        pass "KVM hidden: enabled"
    else
        fail "KVM hidden: not set in domain XML"
    fi

    if echo "$XML" | grep -q "vendor_id"; then
        VENDOR_ID=$(echo "$XML" | grep "vendor_id" | sed "s/.*value='\([^']*\)'.*/\1/")
        if [[ "$VENDOR_ID" == "Microsoft Hv" || "$VENDOR_ID" == "KVMKVMKVM" || "$VENDOR_ID" == "AMDisbetter!" ]]; then
            fail "Hyper-V vendor_id is a known VM value: $VENDOR_ID"
        else
            pass "Hyper-V vendor_id: $VENDOR_ID"
        fi
    else
        warn "Hyper-V vendor_id not set"
    fi
fi

# -----------------------------------------------------------------------
# 8. ACPI tables loaded
# -----------------------------------------------------------------------
if [[ -n "${XML:-}" ]]; then
    ACPI_TABLES=$(echo "$XML" | grep -c "acpitable" 2>/dev/null || echo "0")
    if [[ "$ACPI_TABLES" -ge 2 ]]; then
        pass "ACPI: $ACPI_TABLES custom tables loaded"
    elif [[ "$ACPI_TABLES" -ge 1 ]]; then
        warn "ACPI: only $ACPI_TABLES table loaded (expected 2-3)"
    else
        warn "ACPI: no custom ACPI tables in domain XML"
    fi
fi

# -----------------------------------------------------------------------
# Summary
# -----------------------------------------------------------------------
echo ""
if [[ $FAIL -eq 0 && $WARN -eq 0 ]]; then
    printf "\033[32m=== All checks passed ===\033[0m\n"
elif [[ $FAIL -eq 0 ]]; then
    printf "\033[33m=== 0 failures, %d warnings ===\033[0m\n" "$WARN"
else
    printf "\033[31m=== %d failures, %d warnings ===\033[0m\n" "$FAIL" "$WARN"
fi
