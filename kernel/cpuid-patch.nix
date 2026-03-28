# CPUID spoofing patch (postPatch script)
#
# Based on AutoVirt/Hypervisor-Phantom (Scrut1ny/AutoVirt linux-6.18.8-svm.patch).
# Intercepts CPUID leaf 0 at the lowest level (inside svm_vcpu_run, after
# svm_vcpu_enter_exit returns) and spoofs the vendor string to AuthenticAMD
# with max leaf = 0x16. Re-enters guest without a full exit, making the
# interception invisible to timing-based detection.
#
# Also clears RDTSC/RDTSCP interception so the guest reads the hardware TSC
# directly (complementary to BetterTiming which intercepts RDTSC instead).
# When both patches are applied, the BetterTiming RDTSC intercept in init_vmcb
# takes precedence since it runs after this clear.
#
# Targets: arch/x86/kvm/svm/svm.c
''
  echo "=== CPUID Spoofing: Hypervisor-Phantom style patch ==="

  # ---------- 1. Add reenter_guest_fast label before svm_vcpu_enter_exit ----------
  # The call site in svm_vcpu_run looks like:
  #   svm_vcpu_enter_exit(vcpu, spec_ctrl_intercepted);
  # We add a label before it so we can goto from the CPUID handler.
  if grep -q 'svm_vcpu_enter_exit(vcpu, spec_ctrl_intercepted);' arch/x86/kvm/svm/svm.c; then
    sed -i '/svm_vcpu_enter_exit(vcpu, spec_ctrl_intercepted);/i\\nreenter_guest_fast:' \
      arch/x86/kvm/svm/svm.c
    echo "[OK] svm.c: added reenter_guest_fast label"
  else
    echo "[FAIL] svm.c: could not find svm_vcpu_enter_exit call site"
    exit 1
  fi

  # ---------- 2. Add CPUID leaf 0 spoofing after svm_vcpu_enter_exit ----------
  # Insert the interception block between svm_vcpu_enter_exit() and the
  # spec_ctrl_restore_host call. We anchor on the line after the enter_exit call.
  #
  # The code checks if exit_code == SVM_EXIT_CPUID and leaf (RAX) == 0.
  # If so, it spoofs AuthenticAMD vendor string, caps max leaf at 0x16,
  # advances RIP, and jumps back to re-enter the guest.
  if grep -q 'svm_vcpu_enter_exit(vcpu, spec_ctrl_intercepted);' arch/x86/kvm/svm/svm.c; then
    sed -i '/^\tsvm_vcpu_enter_exit(vcpu, spec_ctrl_intercepted);$/a\\n\t/*\n\t * CPUID leaf 0 spoofing — Hypervisor-Phantom technique.\n\t * Intercept at lowest level, spoof vendor, re-enter without full exit.\n\t * Required kernel cmdline: mitigations=off idle=poll processor.max_cstate=1 tsc=reliable\n\t */\n\tif (unlikely(svm->vmcb->control.exit_code == SVM_EXIT_CPUID)) {\n\t\tif (svm->vmcb->save.rax == 0) {\n\t\t\tsvm->vmcb->save.rax = 0x16;\n\n\t\t\tvcpu->arch.regs[VCPU_REGS_RBX] = 0x68747541; /* Auth */\n\t\t\tvcpu->arch.regs[VCPU_REGS_RCX] = 0x444d4163; /* cAMD */\n\t\t\tvcpu->arch.regs[VCPU_REGS_RDX] = 0x69746e65; /* enti */\n\n\t\t\t{\n\t\t\t\tu64 next_rip = svm->vmcb->control.next_rip;\n\t\t\t\tif (!next_rip)\n\t\t\t\t\tnext_rip = svm->vmcb->save.rip + svm->vmcb->control.insn_len;\n\t\t\t\tsvm->vmcb->save.rip = next_rip;\n\t\t\t\tvcpu->arch.regs[VCPU_REGS_RIP] = next_rip;\n\t\t\t}\n\n\t\t\tgoto reenter_guest_fast;\n\t\t}\n\t}' arch/x86/kvm/svm/svm.c
    echo "[OK] svm.c: added CPUID leaf 0 spoofing with reenter_guest_fast"
  else
    echo "[FAIL] svm.c: could not find svm_vcpu_enter_exit for CPUID insertion"
    exit 1
  fi

  # ---------- 3. Clear RDTSC/RDTSCP interception in init_vmcb ----------
  # This ensures the guest can read TSC directly. When BetterTiming is also
  # applied, its INTERCEPT_RDTSC set call (added after INTERCEPT_RSM) overrides
  # this clear since it runs later in init_vmcb.
  if grep -q 'svm_set_intercept(svm, INTERCEPT_RSM);' arch/x86/kvm/svm/svm.c; then
    sed -i '/svm_set_intercept(svm, INTERCEPT_RSM);/a\\tsvm_clr_intercept(svm, INTERCEPT_RDTSC);\n\tsvm_clr_intercept(svm, INTERCEPT_RDTSCP);' \
      arch/x86/kvm/svm/svm.c
    echo "[OK] svm.c: cleared RDTSC/RDTSCP interception in init_vmcb"
  else
    echo "[WARN] svm.c: could not find INTERCEPT_RSM anchor for clearing RDTSC"
  fi

  echo "=== CPUID Spoofing: patch complete ==="
''
