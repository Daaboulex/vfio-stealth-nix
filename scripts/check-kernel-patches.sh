#!/usr/bin/env bash
# Validate kernel patch anchors against an unpacked kernel source tree.
# Usage: check-kernel-patches.sh <kernel-source-path>
# Exit 0 = all critical anchors match. Exit 1 = critical failure.
set -euo pipefail

KERNEL_SRC="${1:?Usage: check-kernel-patches.sh <kernel-source-path>}"
FAIL=0
WARN=0
PASS=0

check() {
  local severity="$1" file="$2" pattern="$3" label="$4"
  local path="$KERNEL_SRC/$file"
  if [ ! -f "$path" ]; then
    echo "[FAIL] $file: file not found"
    FAIL=$((FAIL + 1))
    return
  fi
  if grep -q "$pattern" "$path"; then
    echo "[OK]   $label"
    PASS=$((PASS + 1))
  elif [ "$severity" = "FAIL" ]; then
    echo "[FAIL] $label — pattern not found"
    FAIL=$((FAIL + 1))
  else
    echo "[WARN] $label — pattern not found"
    WARN=$((WARN + 1))
  fi
}

echo "=== Kernel patch anchor validation ==="
echo "Source: $KERNEL_SRC"
echo "Kernel: $(head -5 "$KERNEL_SRC/Makefile" 2>/dev/null | grep -E 'VERSION|PATCHLEVEL|SUBLEVEL' | tr '\n' ' ')"
echo ""

# --- timing-patch.nix anchors ---
echo "--- timing-patch.nix ---"
check FAIL "include/linux/kvm_host.h" \
  'bool valid_wakeup;' \
  "kvm_host.h: valid_wakeup field"

check FAIL "arch/x86/kvm/x86.c" \
  'static int vcpu_enter_guest' \
  "x86.c: vcpu_enter_guest definition"

check FAIL "arch/x86/kvm/x86.c" \
  'static bool kvm_vcpu_running' \
  "x86.c: kvm_vcpu_running definition"

check FAIL "arch/x86/kvm/x86.c" \
  'case MSR_IA32_TSC: {' \
  "x86.c: MSR_IA32_TSC case block"

check FAIL "arch/x86/kvm/svm/svm.c" \
  'svm_set_intercept(svm, INTERCEPT_RSM);' \
  "svm.c: INTERCEPT_RSM anchor"

check FAIL "arch/x86/kvm/svm/svm.c" \
  'static int (\*const svm_exit_handlers\[\])' \
  "svm.c: svm_exit_handlers table"

check FAIL "arch/x86/kvm/svm/svm.c" \
  'SVM_EXIT_AVIC_UNACCELERATED_ACCESS.*avic_unaccelerated_access_interception' \
  "svm.c: AVIC entry (RDTSC registration anchor)"

check FAIL "arch/x86/kvm/svm/svm.c" \
  '\[SVM_EXIT_RDTSCP\].*=.*kvm_handle_invalid_op,' \
  "svm.c: SVM_EXIT_RDTSCP entry"

check FAIL "arch/x86/kvm/x86.c" \
  'kvm_check_has_quirk(vcpu->kvm, KVM_X86_QUIRK_FIX_HYPERCALL_INSN)' \
  "x86.c: hypercall quirk check"

# --- cpuid-patch.nix anchors ---
echo ""
echo "--- cpuid-patch.nix ---"
check FAIL "arch/x86/kvm/svm/svm.c" \
  'svm_vcpu_enter_exit(vcpu,' \
  "svm.c: svm_vcpu_enter_exit call site"

# --- cpuid-disable.nix anchors ---
echo ""
echo "--- cpuid-disable.nix ---"
check WARN "arch/x86/kvm/svm/svm.c" \
  'static int pre_svm_run' \
  "svm.c: pre_svm_run definition (belt-and-suspenders)"

echo ""
echo "=== Results: $PASS OK, $WARN WARN, $FAIL FAIL ==="

if [ "$FAIL" -gt 0 ]; then
  echo "CRITICAL: $FAIL anchor(s) broken — kernel patches will fail on build."
  exit 1
fi
if [ "$WARN" -gt 0 ]; then
  echo "DEGRADED: $WARN non-critical anchor(s) missing — defense-in-depth features skipped."
fi
echo "All critical anchors validated."
exit 0
