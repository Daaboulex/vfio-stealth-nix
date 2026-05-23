# CPUID interception disable patch (postPatch script)
#
# Clears INTERCEPT_CPUID in init_vmcb so the guest executes CPUID at
# native hardware speed with zero VM exit overhead. The CPU returns
# real hardware values (AuthenticAMD, no hypervisor bit) because the
# host IS an AMD CPU and the hypervisor-present bit is synthetic
# (only set by KVM via interception, absent in real hardware CPUID).
#
# On AMD SVM, VMRUN loads guest XCR0 from the VMCB before guest
# execution, so CPUID leaf 0xD returns XSAVE sizes consistent with
# the guest's active XCR0. No XCR0 synchronization is needed.
#
# Defeats VMAware TIMER (95pts) and SINGLE_STEP (100pts) techniques:
# both measure CPUID execution timing via software counters or #DB
# traps. Without a VM exit, CPUID runs at native speed — identical
# to bare metal.
#
# Side effects:
# - Hyper-V enlightenments (hypervclock, vapic, etc.) are invisible
#   to the guest since KVM can't inject CPUID leaves without interception.
#   Windows falls back to TSC (fine with tsc=reliable + invariant TSC).
# - kvm.hidden has no effect on CPUID (unnecessary — hardware doesn't
#   expose hypervisor). KVM MSR enforcement still works via
#   kvm-pv-enforce-cpuid=on (uses internal CPUID table, not interception).
# - The Hypervisor-Phantom patch (cpuid-patch.nix) becomes a no-op if
#   both are applied — CPUID never exits, so the spoof never fires.
#
# Targets: arch/x86/kvm/svm/svm.c
''
  echo "=== CPUID Passthrough: disabling CPUID interception ==="

  # ---------- 1. Clear INTERCEPT_CPUID after init_vmcb intercept setup ----------
  # Anchors on INTERCEPT_RSM (same anchor used by timing-patch and cpuid-patch).
  # This runs AFTER timing-patch (which adds RDTSC/RDTSCP intercepts after RSM),
  # so the clear is placed after all other intercept additions.
  if grep -q 'svm_set_intercept(svm, INTERCEPT_RSM);' arch/x86/kvm/svm/svm.c; then
    sed -i '/svm_set_intercept(svm, INTERCEPT_RSM);/a\\n\t/* CPUID passthrough: disable interception so guest reads hardware\n\t * CPUID at native speed. AuthenticAMD + no hypervisor bit natively.\n\t * Defeats timing-based VM detection (TIMER, SINGLE_STEP). */\n\tsvm_clr_intercept(svm, INTERCEPT_CPUID);' \
      arch/x86/kvm/svm/svm.c
    echo "[OK] svm.c: cleared INTERCEPT_CPUID in init_vmcb (native CPUID execution)"
  else
    echo "[FAIL] svm.c: could not find INTERCEPT_RSM anchor for CPUID disable"
    exit 1
  fi

  echo "=== CPUID Passthrough: patch complete ==="
''
