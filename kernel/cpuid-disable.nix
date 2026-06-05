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
# Handles VMAware TIMER (95pts) and SINGLE_STEP (100pts) techniques:
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
#   both are applied — CPUID never exits, so the override never fires.
#
# Stability: init_vmcb sets intercepts once for non-nested operation.
# Nested SVM (enter_svm_guest_mode) can re-set intercepts, but a
# Windows gaming VM never enables nested virtualization. Belt-and-
# suspenders: we also clear in pre_svm_run to catch any future
# kernel path that might re-enable INTERCEPT_CPUID.
#
# Limitation: hypercall patching (timing-patch.nix step 9) is host-
# wide — ALL VMs get #UD for VMCALL/VMMCALL from ring 3. Linux guests
# on this host lose KVM paravirt features (kvmclock, PV TLB flush).
# This is acceptable for a single-purpose gaming VM host.
#
# Targets: arch/x86/kvm/svm/svm.c
''
  echo "=== CPUID Passthrough: disabling CPUID interception ==="

  # ---------- 1. Clear INTERCEPT_CPUID after init_vmcb intercept setup ----------
  # Anchors on INTERCEPT_RSM (same anchor used by timing-patch and cpuid-patch).
  # sed /a inserts in LIFO order — this clear lands closest to the anchor,
  # before timing-patch's RDTSC/RDTSCP sets (which is fine — they're independent).
  if grep -q 'svm_set_intercept(svm, INTERCEPT_RSM);' arch/x86/kvm/svm/svm.c; then
    sed -i '/svm_set_intercept(svm, INTERCEPT_RSM);/a\\n\t/* CPUID passthrough: disable interception so guest reads hardware\n\t * CPUID at native speed. AuthenticAMD + no hypervisor bit natively.\n\t * Handles timing-based VM detection (TIMER, SINGLE_STEP). */\n\tsvm_clr_intercept(svm, INTERCEPT_CPUID);' \
      arch/x86/kvm/svm/svm.c
    echo "[OK] svm.c: cleared INTERCEPT_CPUID in init_vmcb (native CPUID execution)"
  else
    echo "[FAIL] svm.c: could not find INTERCEPT_RSM anchor for CPUID disable"
    exit 1
  fi

  # ---------- 2. Belt-and-suspenders: clear in pre_svm_run ----------
  # Ensures INTERCEPT_CPUID stays clear even if a future kernel path
  # (nested SVM, vCPU reset, intercept recalculation) re-enables it.
  # pre_svm_run runs before every VMRUN — last-writer-wins.
  if grep -q 'static int pre_svm_run(struct kvm_vcpu \*vcpu)' arch/x86/kvm/svm/svm.c; then
    sed -i '/^static int pre_svm_run(struct kvm_vcpu \*vcpu)/,/^}/ {
      /^}/ i\\n\t/* CPUID passthrough: ensure interception stays clear across\n\t * any recalculation path (nested exits, resets, etc.).\n\t * Skip in nested guest mode to preserve L1 hypervisor security. */\n\tif (!is_guest_mode(vcpu))\n\t\tsvm_clr_intercept(to_svm(vcpu), INTERCEPT_CPUID);
    }' arch/x86/kvm/svm/svm.c
    echo "[OK] svm.c: added CPUID clear in pre_svm_run (belt-and-suspenders)"
  else
    echo "[WARN] svm.c: could not find pre_svm_run — init_vmcb clear is sufficient for non-nested"
  fi

  echo "=== CPUID Passthrough: patch complete ==="
''
