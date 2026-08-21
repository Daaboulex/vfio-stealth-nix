# BetterTiming TSC compensation patch (postPatch script)
#
# Hand-ported from SamuelTulach/BetterTiming @ 3d95a8f, adapted for CachyOS
# 6.19+ kernel. Not a build input; version.json .betterTiming.rev records the
# ported-from commit and scripts/update.sh flags when upstream moves past it.
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

      # last_exit_start is retained for ABI stability but unused.
      exactly_one include/linux/kvm_host.h \
        'bool valid_wakeup;' \
        "kvm_host.h: valid_wakeup field in struct kvm_vcpu"

      sed -i '/bool valid_wakeup;/a\\n\tu64 last_exit_start;\n\tu64 total_exit_time;' \
        include/linux/kvm_host.h
      landed include/linux/kvm_host.h 'u64 total_exit_time;' \
        "kvm_host.h: timing fields added to struct kvm_vcpu"

      exactly_one arch/x86/kvm/x86.c \
        'case MSR_IA32_TSC: \{' \
        "x86.c: MSR_IA32_TSC case block in kvm_get_msr_common"

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
      landed arch/x86/kvm/x86.c 'u64 bt_start = rdtsc();' \
        "x86.c: MSR_IA32_TSC returns compensated time"

      # sed /a inserts in LIFO order, so the clears cpuid-patch.nix appends on
      # this same anchor land before these sets and the sets win. Intended.
      exactly_one arch/x86/kvm/svm/svm.c \
        'svm_set_intercept\(svm, INTERCEPT_RSM\);' \
        "svm.c: INTERCEPT_RSM anchor in init_vmcb"

      sed -i '/svm_set_intercept(svm, INTERCEPT_RSM);/a\\tsvm_set_intercept(svm, INTERCEPT_RDTSC);\n\tsvm_set_intercept(svm, INTERCEPT_RDTSCP);' \
        arch/x86/kvm/svm/svm.c
      landed arch/x86/kvm/svm/svm.c 'svm_set_intercept(svm, INTERCEPT_RDTSC);' \
        "svm.c: RDTSC+RDTSCP interception enabled in init_vmcb"

      exactly_one arch/x86/kvm/svm/svm.c \
        '^static int \(\*const svm_exit_handlers\[\]\)' \
        "svm.c: svm_exit_handlers table definition"

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
      landed arch/x86/kvm/svm/svm.c 'static int stealth_cpuid_interception' \
        "svm.c: stealth CPUID/WBINVD/XSETBV/INVD wrappers"
      landed arch/x86/kvm/svm/svm.c 'static int stealth_invd_interception' \
        "svm.c: stealth INVD wrapper"

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
      landed arch/x86/kvm/svm/svm.c 'static int handle_rdtsc_interception' \
        "svm.c: handle_rdtsc_interception handler"

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

      sed -i 's/\[SVM_EXIT_CPUID\].*=.*kvm_emulate_cpuid,/[SVM_EXIT_CPUID]\t\t\t= stealth_cpuid_interception,/' \
        arch/x86/kvm/svm/svm.c
      sed -i 's/\[SVM_EXIT_WBINVD\].*=.*kvm_emulate_wbinvd,/[SVM_EXIT_WBINVD]\t\t\t= stealth_wbinvd_interception,/' \
        arch/x86/kvm/svm/svm.c
      sed -i 's/\[SVM_EXIT_XSETBV\].*=.*kvm_emulate_xsetbv,/[SVM_EXIT_XSETBV]\t\t\t= stealth_xsetbv_interception,/' \
        arch/x86/kvm/svm/svm.c
      sed -i 's/\[SVM_EXIT_INVD\].*=.*kvm_emulate_invd,/[SVM_EXIT_INVD]\t\t\t\t= stealth_invd_interception,/' \
        arch/x86/kvm/svm/svm.c
      landed arch/x86/kvm/svm/svm.c '= stealth_cpuid_interception,' \
        "svm.c: exit table SVM_EXIT_CPUID -> stealth wrapper"
      landed arch/x86/kvm/svm/svm.c '= stealth_wbinvd_interception,' \
        "svm.c: exit table SVM_EXIT_WBINVD -> stealth wrapper"
      landed arch/x86/kvm/svm/svm.c '= stealth_xsetbv_interception,' \
        "svm.c: exit table SVM_EXIT_XSETBV -> stealth wrapper"
      landed arch/x86/kvm/svm/svm.c '= stealth_invd_interception,' \
        "svm.c: exit table SVM_EXIT_INVD -> stealth wrapper"

      # KVM's patch_hypercall() writes VMCALL/VMMCALL into guest memory, which
      # on read-execute pages raises #PF where bare metal raises #UD.
      exactly_one arch/x86/kvm/x86.c \
        'if \(!kvm_check_has_quirk\(vcpu->kvm, KVM_X86_QUIRK_FIX_HYPERCALL_INSN\)\)' \
        "x86.c: KVM_X86_QUIRK_FIX_HYPERCALL_INSN check"

      sed -i 's/if (!kvm_check_has_quirk(vcpu->kvm, KVM_X86_QUIRK_FIX_HYPERCALL_INSN))/if (1)/' \
        arch/x86/kvm/x86.c
      gone arch/x86/kvm/x86.c 'if (!kvm_check_has_quirk(vcpu->kvm, KVM_X86_QUIRK_FIX_HYPERCALL_INSN))' \
        "x86.c: hypercall instruction patching disabled (always inject #UD)"

      echo "=== BetterTiming: patch complete ==="
''
