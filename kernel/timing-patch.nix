# BetterTiming TSC compensation patch (postPatch script)
#
# Based on SamuelTulach/BetterTiming, adapted for CachyOS 6.19+ kernel.
# Provides realistic VM exit timing by tracking cumulative exit time and
# subtracting it from TSC reads inside the guest.
#
# Each stealth exit handler self-times with rdtsc() at entry and exit,
# accumulating only the handler's own execution time into total_exit_time.
# This avoids the original bug where the vcpu_enter_guest wrapper counted
# guest execution time as exit overhead, making TSC advance too slowly.
#
# Targets: arch/x86/kvm/svm/svm.c, arch/x86/kvm/x86.c, include/linux/kvm_host.h
''
      echo "=== BetterTiming: TSC compensation patch ==="

      # ---------- 1. Add tracking fields to struct kvm_vcpu ----------
      # Insert last_exit_start and total_exit_time after valid_wakeup.
      # last_exit_start is retained for ABI stability but unused.
      if grep -q 'bool valid_wakeup;' include/linux/kvm_host.h; then
        sed -i '/bool valid_wakeup;/a\\n\tu64 last_exit_start;\n\tu64 total_exit_time;' \
          include/linux/kvm_host.h
        echo "[OK] kvm_host.h: added timing fields to struct kvm_vcpu"
      else
        echo "[FAIL] kvm_host.h: could not find valid_wakeup field"
        exit 1
      fi

      # ---------- 2. Patch MSR_IA32_TSC read to return compensated time ----------
      # Replace the TSC computation block in kvm_get_msr_common.
      # Returns rdtsc() minus accumulated exit time, and self-times.
      if grep -q 'case MSR_IA32_TSC: {' arch/x86/kvm/x86.c; then
        awk '
        /case MSR_IA32_TSC: \{/ {
          print "\tcase MSR_IA32_TSC: {"
          print "\t\tu64 bt_start = rdtsc();"
          print "\t\tmsr_info->data = bt_start - vcpu->total_exit_time;"
          print "\t\tvcpu->total_exit_time += rdtsc() - bt_start;"
          print "\t\tbreak;"
          print "\t}"
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
        echo "[FAIL] x86.c: could not find MSR_IA32_TSC case block — TSC compensation broken without this"
        exit 1
      fi

      # ---------- 3. Enable RDTSC and RDTSCP interception in init_vmcb ----------
      # Note: sed /a inserts in LIFO order — last appended is closest to
      # anchor. When cpuid-patch.nix clears these intercepts (also via /a
      # on the same anchor), the clears land BEFORE these sets, so the
      # sets override the clears. This is correct behavior.
      if grep -q 'svm_set_intercept(svm, INTERCEPT_RSM);' arch/x86/kvm/svm/svm.c; then
        sed -i '/svm_set_intercept(svm, INTERCEPT_RSM);/a\\tsvm_set_intercept(svm, INTERCEPT_RDTSC);\n\tsvm_set_intercept(svm, INTERCEPT_RDTSCP);' \
          arch/x86/kvm/svm/svm.c
        echo "[OK] svm.c: enabled RDTSC+RDTSCP interception in init_vmcb"
      else
        echo "[FAIL] svm.c: could not find INTERCEPT_RSM anchor for RDTSC/RDTSCP interception"
        exit 1
      fi

      # ---------- 4. Add stealth wrapper functions ----------
      # Each wrapper self-times: rdtsc() at entry, accumulate delta at exit.
      # Insert before svm_exit_handlers table definition.

      # 4a. CPUID, WBINVD, XSETBV, INVD wrappers
      sed -i '/^static int (\*const svm_exit_handlers\[\])/i\
  static int stealth_cpuid_interception(struct kvm_vcpu *vcpu)\
  {\
  \tu64 _start = rdtsc();\
  \tint ret = kvm_emulate_cpuid(vcpu);\
  \tvcpu->total_exit_time += rdtsc() - _start;\
  \treturn ret;\
  }\
  \
  static int stealth_wbinvd_interception(struct kvm_vcpu *vcpu)\
  {\
  \tu64 _start = rdtsc();\
  \tint ret = kvm_emulate_wbinvd(vcpu);\
  \tvcpu->total_exit_time += rdtsc() - _start;\
  \treturn ret;\
  }\
  \
  static int stealth_xsetbv_interception(struct kvm_vcpu *vcpu)\
  {\
  \tu64 _start = rdtsc();\
  \tint ret = kvm_emulate_xsetbv(vcpu);\
  \tvcpu->total_exit_time += rdtsc() - _start;\
  \treturn ret;\
  }\
  \
  static int stealth_invd_interception(struct kvm_vcpu *vcpu)\
  {\
  \tu64 _start = rdtsc();\
  \tint ret = kvm_emulate_invd(vcpu);\
  \tvcpu->total_exit_time += rdtsc() - _start;\
  \treturn ret;\
  }\
  ' arch/x86/kvm/svm/svm.c
      echo "[OK] svm.c: created stealth wrapper functions with per-handler timing"

      # 4b. RDTSC handler — reads compensated TSC and self-times
      sed -i '/^static int (\*const svm_exit_handlers\[\])/i\
  static int handle_rdtsc_interception(struct kvm_vcpu *vcpu)\
  {\
  \tu64 start = rdtsc();\
  \tu64 data = start - vcpu->total_exit_time;\
  \tint ret;\
  \
  \tvcpu->arch.regs[VCPU_REGS_RAX] = (u32)data;\
  \tvcpu->arch.regs[VCPU_REGS_RDX] = (u32)(data >> 32);\
  \
  \tret = kvm_skip_emulated_instruction(vcpu);\
  \tvcpu->total_exit_time += rdtsc() - start;\
  \treturn ret;\
  }\
  ' arch/x86/kvm/svm/svm.c
      echo "[OK] svm.c: added handle_rdtsc_interception handler"

      # 4c. RDTSCP handler — same as RDTSC but also returns TSC_AUX in ECX
      sed -i '/^static int (\*const svm_exit_handlers\[\])/i\
  static int handle_rdtscp_interception(struct kvm_vcpu *vcpu)\
  {\
  \tu64 start = rdtsc();\
  \tu64 data = start - vcpu->total_exit_time;\
  \tint ret;\
  \
  \tvcpu->arch.regs[VCPU_REGS_RAX] = (u32)data;\
  \tvcpu->arch.regs[VCPU_REGS_RDX] = (u32)(data >> 32);\
  \tvcpu->arch.regs[VCPU_REGS_RCX] = (u32)to_svm(vcpu)->tsc_aux;\
  \
  \tret = kvm_skip_emulated_instruction(vcpu);\
  \tvcpu->total_exit_time += rdtsc() - start;\
  \treturn ret;\
  }\
  ' arch/x86/kvm/svm/svm.c
      echo "[OK] svm.c: added handle_rdtscp_interception handler"

      # ---------- 5. Register handlers in svm_exit_handlers table ----------
      # 5a. RDTSC — add new entry after AVIC_UNACCELERATED_ACCESS
      if grep -q 'SVM_EXIT_AVIC_UNACCELERATED_ACCESS.*avic_unaccelerated_access_interception' arch/x86/kvm/svm/svm.c; then
        sed -i '/\[SVM_EXIT_AVIC_UNACCELERATED_ACCESS\].*=.*avic_unaccelerated_access_interception/a\\t[SVM_EXIT_RDTSC]\t\t\t\t= handle_rdtsc_interception,' \
          arch/x86/kvm/svm/svm.c
        echo "[OK] svm.c: registered SVM_EXIT_RDTSC handler"
      else
        echo "[FAIL] svm.c: could not find AVIC_UNACCELERATED_ACCESS entry for RDTSC registration"
        exit 1
      fi

      # 5b. RDTSCP — replace upstream kvm_handle_invalid_op mapping
      if grep -q '\[SVM_EXIT_RDTSCP\].*=.*kvm_handle_invalid_op,' arch/x86/kvm/svm/svm.c; then
        sed -i 's/\[SVM_EXIT_RDTSCP\].*=.*kvm_handle_invalid_op,/[SVM_EXIT_RDTSCP]\t\t\t= handle_rdtscp_interception,/' \
          arch/x86/kvm/svm/svm.c
        echo "[OK] svm.c: registered SVM_EXIT_RDTSCP handler"
      else
        echo "[FAIL] svm.c: could not find SVM_EXIT_RDTSCP entry for handler registration"
        exit 1
      fi

      # 5c. Replace handler table entries for CPUID, WBINVD, XSETBV, INVD
      sed -i 's/\[SVM_EXIT_CPUID\].*=.*kvm_emulate_cpuid,/[SVM_EXIT_CPUID]\t\t\t= stealth_cpuid_interception,/' \
        arch/x86/kvm/svm/svm.c
      sed -i 's/\[SVM_EXIT_WBINVD\].*=.*kvm_emulate_wbinvd,/[SVM_EXIT_WBINVD]\t\t\t= stealth_wbinvd_interception,/' \
        arch/x86/kvm/svm/svm.c
      sed -i 's/\[SVM_EXIT_XSETBV\].*=.*kvm_emulate_xsetbv,/[SVM_EXIT_XSETBV]\t\t\t= stealth_xsetbv_interception,/' \
        arch/x86/kvm/svm/svm.c
      sed -i 's/\[SVM_EXIT_INVD\].*=.*kvm_emulate_invd,/[SVM_EXIT_INVD]\t\t\t\t= stealth_invd_interception,/' \
        arch/x86/kvm/svm/svm.c
      echo "[OK] svm.c: updated exit handler table to use stealth wrappers"

      # ---------- 6. Disable KVM hypercall instruction patching ----------
      # KVM's patch_hypercall() writes VMCALL/VMMCALL to guest memory.
      # On read-execute pages this triggers #PF instead of #UD (bare metal
      # behavior). Force the quirk check to always inject #UD.
      if grep -q 'if (!kvm_check_has_quirk(vcpu->kvm, KVM_X86_QUIRK_FIX_HYPERCALL_INSN))' arch/x86/kvm/x86.c; then
        sed -i 's/if (!kvm_check_has_quirk(vcpu->kvm, KVM_X86_QUIRK_FIX_HYPERCALL_INSN))/if (1)/' \
          arch/x86/kvm/x86.c
        echo "[OK] x86.c: disabled hypercall instruction patching (always inject #UD)"
      else
        echo "[FAIL] x86.c: could not find KVM_X86_QUIRK_FIX_HYPERCALL_INSN check"
        exit 1
      fi

      echo "=== BetterTiming: patch complete ==="
''
