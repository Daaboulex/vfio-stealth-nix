''
      echo "=== BetterTiming: TSC compensation patch ==="

      exactly_one include/linux/kvm_host.h \
        'bool valid_wakeup;' \
        "kvm_host.h: valid_wakeup field in struct kvm_vcpu"

      sed -i '/bool valid_wakeup;/a\\n\tu64 last_exit_start;\n\tu64 total_exit_time;\n\tbool timed_exit;' \
        include/linux/kvm_host.h
      landed include/linux/kvm_host.h 'bool timed_exit;' \
        "kvm_host.h: timing fields added to struct kvm_vcpu"

      tsc_file=arch/x86/kvm/x86.c
      if [ -f arch/x86/kvm/msrs.c ]; then tsc_file=arch/x86/kvm/msrs.c; fi
      exactly_one "$tsc_file" \
        'case MSR_IA32_TSC: \{' \
        "$tsc_file: MSR_IA32_TSC case block in kvm_get_msr_common"

        awk '
        /case MSR_IA32_TSC: \{/ {
          print "\tcase MSR_IA32_TSC: {"
          print "\t\tmsr_info->data = vcpu->last_exit_start - vcpu->total_exit_time;"
          print "\t\tif (!msr_info->host_initiated)"
          print "\t\t\tvcpu->timed_exit = true;"
          print "\t\tbreak;"
          print "\t}"
          in_tsc = 1
          next
        }
        in_tsc && /^\tcase / { in_tsc = 0; print; next }
        in_tsc && /^\t\}/ { in_tsc = 0; next }
        in_tsc { next }
        { print }
        ' "$tsc_file" > "$tsc_file.tmp" && \
          mv "$tsc_file.tmp" "$tsc_file"
      landed "$tsc_file" 'msr_info->data = vcpu->last_exit_start - vcpu->total_exit_time;' \
        "$tsc_file: MSR_IA32_TSC returns the TSC of the exit less the hidden exit time"

      # why: sed /a inserts in LIFO order, so these sets land after cpuid-patch.nix's clears and win
      exactly_one arch/x86/kvm/svm/svm.c \
        'svm_set_intercept\(svm, INTERCEPT_RSM\);' \
        "svm.c: INTERCEPT_RSM anchor in init_vmcb"

      sed -i '/svm_set_intercept(svm, INTERCEPT_RSM);/a\\tsvm_set_intercept(svm, INTERCEPT_RDTSC);\n\tsvm_set_intercept(svm, INTERCEPT_RDTSCP);' \
        arch/x86/kvm/svm/svm.c
      landed arch/x86/kvm/svm/svm.c 'svm_set_intercept(svm, INTERCEPT_RDTSC);' \
        "svm.c: RDTSC+RDTSCP interception enabled in init_vmcb"

      exactly_one arch/x86/kvm/svm/svm.c \
        '^static noinstr void svm_vcpu_enter_exit\(struct kvm_vcpu \*vcpu' \
        "svm.c: svm_vcpu_enter_exit definition"
      exactly_one arch/x86/kvm/svm/svm.c \
        '^	guest_state_enter_irqoff\(\);$' \
        "svm.c: guest_state_enter_irqoff in svm_vcpu_enter_exit"
      exactly_one arch/x86/kvm/svm/svm.c \
        '^	guest_state_exit_irqoff\(\);$' \
        "svm.c: guest_state_exit_irqoff in svm_vcpu_enter_exit"

      sed -i '/^static noinstr void svm_vcpu_enter_exit(struct kvm_vcpu \*vcpu/i\
  static __always_inline bool stealth_timed_exit(u64 exit_code)\
  {\
  \treturn exit_code == SVM_EXIT_CPUID || exit_code == SVM_EXIT_RDTSC ||\
  \t       exit_code == SVM_EXIT_RDTSCP || exit_code == SVM_EXIT_WBINVD ||\
  \t       exit_code == SVM_EXIT_XSETBV || exit_code == SVM_EXIT_INVD;\
  }\
  ' arch/x86/kvm/svm/svm.c
      landed arch/x86/kvm/svm/svm.c 'static __always_inline bool stealth_timed_exit(u64 exit_code)' \
        "svm.c: the exits whose handling the guest TSC hides"

      # why: every exit re-enters the guest through svm_vcpu_enter_exit, the CPUID leaf 0 fast path of cpuid-patch.nix included, so the time from an exit to the next entry is measured there and never the guest's own run time
      sed -i '/^static noinstr void svm_vcpu_enter_exit(struct kvm_vcpu \*vcpu/,/^}/{
        /^\tguest_state_enter_irqoff();$/i\\tif (vcpu->timed_exit || stealth_timed_exit(svm->vmcb->control.exit_code)) {\n\t\tvcpu->total_exit_time += rdtsc() - vcpu->last_exit_start;\n\t\tvcpu->timed_exit = false;\n\t}\n
        /^\tguest_state_exit_irqoff();$/a\\tvcpu->last_exit_start = rdtsc();
      }' arch/x86/kvm/svm/svm.c
      landed arch/x86/kvm/svm/svm.c 'vcpu->total_exit_time += rdtsc() - vcpu->last_exit_start;' \
        "svm.c: the time from a timed exit to the next entry is added to the hidden time"
      landed arch/x86/kvm/svm/svm.c 'vcpu->last_exit_start = rdtsc();' \
        "svm.c: every exit stamps its TSC"

      exactly_one arch/x86/kvm/svm/svm.c \
        '^static int \(\*const svm_exit_handlers\[\]\)' \
        "svm.c: svm_exit_handlers table definition"

      sed -i '/^static int (\*const svm_exit_handlers\[\])/i\
  static int handle_rdtsc_interception(struct kvm_vcpu *vcpu)\
  {\
  \tu64 data = vcpu->last_exit_start - vcpu->total_exit_time;\
  \
  \tvcpu->arch.regs[VCPU_REGS_RAX] = (u32)data;\
  \tvcpu->arch.regs[VCPU_REGS_RDX] = (u32)(data >> 32);\
  \treturn kvm_skip_emulated_instruction(vcpu);\
  }\
  \
  static int handle_rdtscp_interception(struct kvm_vcpu *vcpu)\
  {\
  \tu64 data = vcpu->last_exit_start - vcpu->total_exit_time;\
  \
  \tvcpu->arch.regs[VCPU_REGS_RAX] = (u32)data;\
  \tvcpu->arch.regs[VCPU_REGS_RDX] = (u32)(data >> 32);\
  \tvcpu->arch.regs[VCPU_REGS_RCX] = (u32)to_svm(vcpu)->tsc_aux;\
  \treturn kvm_skip_emulated_instruction(vcpu);\
  }\
  ' arch/x86/kvm/svm/svm.c
      landed arch/x86/kvm/svm/svm.c 'static int handle_rdtsc_interception' \
        "svm.c: handle_rdtsc_interception handler"
      landed arch/x86/kvm/svm/svm.c 'static int handle_rdtscp_interception' \
        "svm.c: handle_rdtscp_interception handler"

      exactly_one arch/x86/kvm/svm/svm.c \
        '\[SVM_EXIT_AVIC_UNACCELERATED_ACCESS\].*=.*avic_unaccelerated_access_interception' \
        "svm.c: AVIC_UNACCELERATED_ACCESS exit table entry"

      sed -i '/\[SVM_EXIT_AVIC_UNACCELERATED_ACCESS\].*=.*avic_unaccelerated_access_interception/a\\t[SVM_EXIT_RDTSC]\t\t\t\t= handle_rdtsc_interception,' \
        arch/x86/kvm/svm/svm.c
      landed arch/x86/kvm/svm/svm.c '= handle_rdtsc_interception,' \
        "svm.c: exit table SVM_EXIT_RDTSC -> handle_rdtsc_interception"

      sed -i 's/\[SVM_EXIT_RDTSCP\].*=.*kvm_handle_invalid_op,/[SVM_EXIT_RDTSCP]\t\t\t= handle_rdtscp_interception,/' \
        arch/x86/kvm/svm/svm.c
      landed arch/x86/kvm/svm/svm.c '= handle_rdtscp_interception,' \
        "svm.c: exit table SVM_EXIT_RDTSCP -> handle_rdtscp_interception"

      echo "=== BetterTiming: patch complete ==="
''
