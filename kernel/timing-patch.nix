# BetterTiming TSC compensation patch (postPatch script)
#
# Based on SamuelTulach/BetterTiming, adapted for CachyOS 6.19+ kernel.
# Hides VM exit timing from rdtsc-based detection by tracking cumulative
# exit time and subtracting it from TSC reads inside the guest.
#
# Targets: arch/x86/kvm/svm/svm.c, arch/x86/kvm/x86.c, include/linux/kvm_host.h
''
    echo "=== BetterTiming: TSC compensation patch ==="

    # ---------- 1. Add tracking fields to struct kvm_vcpu ----------
    # Insert last_exit_start and total_exit_time after valid_wakeup
    if grep -q 'bool valid_wakeup;' include/linux/kvm_host.h; then
      sed -i '/bool valid_wakeup;/a\\n\tu64 last_exit_start;\n\tu64 total_exit_time;' \
        include/linux/kvm_host.h
      echo "[OK] kvm_host.h: added timing fields to struct kvm_vcpu"
    else
      echo "[FAIL] kvm_host.h: could not find valid_wakeup field"
      exit 1
    fi

    # ---------- 2. Rename vcpu_enter_guest → vcpu_enter_guest_real ----------
    if grep -q '^static int vcpu_enter_guest(struct kvm_vcpu \*vcpu)' arch/x86/kvm/x86.c; then
      sed -i 's/^static int vcpu_enter_guest(struct kvm_vcpu \*vcpu)/static int vcpu_enter_guest_real(struct kvm_vcpu *vcpu)/' \
        arch/x86/kvm/x86.c
      echo "[OK] x86.c: renamed vcpu_enter_guest to vcpu_enter_guest_real"
    else
      echo "[FAIL] x86.c: could not find vcpu_enter_guest definition"
      exit 1
    fi

    # ---------- 3. Add wrapper vcpu_enter_guest after vcpu_enter_guest_real ----------
    # Insert after the closing brace of vcpu_enter_guest_real, which is the first
    # solo '}' on a line after the function. We find it by locating the next function
    # (kvm_vcpu_running) and inserting before it.
    if grep -q '^static bool kvm_vcpu_running(struct kvm_vcpu \*vcpu)' arch/x86/kvm/x86.c; then
      sed -i '/^static bool kvm_vcpu_running(struct kvm_vcpu \*vcpu)/i\
  static int vcpu_enter_guest(struct kvm_vcpu *vcpu)\
  {\
  \tint result;\
  \tu64 difference;\
  \
  \tvcpu->last_exit_start = rdtsc();\
  \
  \tresult = vcpu_enter_guest_real(vcpu);\
  \
  \tif (vcpu->run->exit_reason == 123) {\
  \t\tdifference = rdtsc() - vcpu->last_exit_start;\
  \t\tvcpu->total_exit_time += difference;\
  \t}\
  \
  \treturn result;\
  }\
  ' arch/x86/kvm/x86.c
      echo "[OK] x86.c: added vcpu_enter_guest wrapper"
    else
      echo "[FAIL] x86.c: could not find kvm_vcpu_running to insert wrapper before"
      exit 1
    fi

    # ---------- 4. Patch MSR_IA32_TSC read to return compensated time ----------
    # Replace the TSC computation block in kvm_get_msr_common.
    # In 6.19, the MSR_IA32_TSC case has a block starting with:
    #   u64 offset, ratio;
    # We replace the entire case body with our compensated read.
    if grep -q 'case MSR_IA32_TSC: {' arch/x86/kvm/x86.c; then
      # Use awk for multi-line replacement within the MSR_IA32_TSC case
      awk '
      /case MSR_IA32_TSC: \{/ {
        print "\tcase MSR_IA32_TSC: {"
        print "\t\tu64 bt_diff;"
        print "\t\tu64 bt_total;"
        print ""
        print "\t\tbt_diff = rdtsc() - vcpu->last_exit_start;"
        print "\t\tbt_total = vcpu->total_exit_time + bt_diff;"
        print ""
        print "\t\tmsr_info->data = rdtsc() - bt_total;"
        print ""
        print "\t\tvcpu->run->exit_reason = 123;"
        print "\t\tbreak;"
        print "\t}"
        # Skip old content until the closing brace+break
        in_tsc = 1
        next
      }
      in_tsc && /^\tcase / { in_tsc = 0; print; next }
      in_tsc && /^\t\}/ { in_tsc = 0; next }
      in_tsc { next }
      { print }
      ' arch/x86/kvm/x86.c > arch/x86/kvm/x86.c.tmp && \
        mv arch/x86/kvm/x86.c.tmp arch/x86/kvm/x86.c
      echo "[OK] x86.c: patched MSR_IA32_TSC to return compensated time"
    else
      echo "[WARN] x86.c: could not find MSR_IA32_TSC case block — skipping"
    fi

    # ---------- 5. Enable RDTSC interception in init_vmcb ----------
    if grep -q 'svm_set_intercept(svm, INTERCEPT_RSM);' arch/x86/kvm/svm/svm.c; then
      sed -i '/svm_set_intercept(svm, INTERCEPT_RSM);/a\\tsvm_set_intercept(svm, INTERCEPT_RDTSC);' \
        arch/x86/kvm/svm/svm.c
      echo "[OK] svm.c: enabled RDTSC interception in init_vmcb"
    else
      echo "[WARN] svm.c: could not find INTERCEPT_RSM anchor for RDTSC interception"
    fi

    # ---------- 6. Add handle_rdtsc_interception handler ----------
    # Insert before the svm_exit_handlers table definition.
    # In 6.19, handlers take (struct kvm_vcpu *vcpu), and we use to_svm() to get svm.
    if grep -q '^static int (\*const svm_exit_handlers\[\])' arch/x86/kvm/svm/svm.c; then
      sed -i '/^static int (\*const svm_exit_handlers\[\])/i\
  static int handle_rdtsc_interception(struct kvm_vcpu *vcpu)\
  {\
  \tstruct vcpu_svm *svm = to_svm(vcpu);\
  \tu64 difference;\
  \tu64 final_time;\
  \tu64 data;\
  \
  \tdifference = rdtsc() - vcpu->last_exit_start;\
  \tfinal_time = vcpu->total_exit_time + difference;\
  \
  \tdata = rdtsc() - final_time;\
  \
  \tvcpu->arch.regs[VCPU_REGS_RAX] = data & -1u;\
  \tvcpu->arch.regs[VCPU_REGS_RDX] = (data >> 32) & -1u;\
  \
  \tvcpu->run->exit_reason = 123;\
  \n\treturn kvm_skip_emulated_instruction(vcpu);\
  }\
  ' arch/x86/kvm/svm/svm.c
      echo "[OK] svm.c: added handle_rdtsc_interception handler"
    else
      echo "[FAIL] svm.c: could not find svm_exit_handlers table"
      exit 1
    fi

    # ---------- 7. Register RDTSC handler in svm_exit_handlers table ----------
    # Add [SVM_EXIT_RDTSC] entry after [SVM_EXIT_AVIC_UNACCELERATED_ACCESS]
    if grep -q 'SVM_EXIT_AVIC_UNACCELERATED_ACCESS.*avic_unaccelerated_access_interception' arch/x86/kvm/svm/svm.c; then
      sed -i '/\[SVM_EXIT_AVIC_UNACCELERATED_ACCESS\].*=.*avic_unaccelerated_access_interception/a\\t[SVM_EXIT_RDTSC]\t\t\t\t= handle_rdtsc_interception,' \
        arch/x86/kvm/svm/svm.c
      echo "[OK] svm.c: registered SVM_EXIT_RDTSC handler"
    else
      echo "[WARN] svm.c: could not find AVIC_UNACCELERATED_ACCESS entry for RDTSC registration"
    fi

    # ---------- 8. Tag exit_reason=123 on CPUID, WBINVD, XSETBV, INVD ----------
    # In 6.19, these map directly to kvm_emulate_* functions. We create wrapper
    # functions that set exit_reason=123 then call through, and update the table.

    # 8a. Create wrapper functions (insert before svm_exit_handlers table)
    sed -i '/^static int handle_rdtsc_interception/i\
  static int stealth_cpuid_interception(struct kvm_vcpu *vcpu)\
  {\
  \tvcpu->run->exit_reason = 123;\
  \treturn kvm_emulate_cpuid(vcpu);\
  }\
  \
  static int stealth_wbinvd_interception(struct kvm_vcpu *vcpu)\
  {\
  \tvcpu->run->exit_reason = 123;\
  \treturn kvm_emulate_wbinvd(vcpu);\
  }\
  \
  static int stealth_xsetbv_interception(struct kvm_vcpu *vcpu)\
  {\
  \tvcpu->run->exit_reason = 123;\
  \treturn kvm_emulate_xsetbv(vcpu);\
  }\
  \
  static int stealth_invd_interception(struct kvm_vcpu *vcpu)\
  {\
  \tvcpu->run->exit_reason = 123;\
  \treturn kvm_emulate_invd(vcpu);\
  }\
  ' arch/x86/kvm/svm/svm.c
    echo "[OK] svm.c: created stealth wrapper functions for exit_reason tagging"

    # 8b. Replace handler table entries to use wrappers
    sed -i 's/\[SVM_EXIT_CPUID\].*=.*kvm_emulate_cpuid,/[SVM_EXIT_CPUID]\t\t\t= stealth_cpuid_interception,/' \
      arch/x86/kvm/svm/svm.c
    sed -i 's/\[SVM_EXIT_WBINVD\].*=.*kvm_emulate_wbinvd,/[SVM_EXIT_WBINVD]\t\t\t= stealth_wbinvd_interception,/' \
      arch/x86/kvm/svm/svm.c
    sed -i 's/\[SVM_EXIT_XSETBV\].*=.*kvm_emulate_xsetbv,/[SVM_EXIT_XSETBV]\t\t\t= stealth_xsetbv_interception,/' \
      arch/x86/kvm/svm/svm.c
    sed -i 's/\[SVM_EXIT_INVD\].*=.*kvm_emulate_invd,/[SVM_EXIT_INVD]\t\t\t\t= stealth_invd_interception,/' \
      arch/x86/kvm/svm/svm.c
    echo "[OK] svm.c: updated exit handler table to use stealth wrappers"

    echo "=== BetterTiming: patch complete ==="
''
