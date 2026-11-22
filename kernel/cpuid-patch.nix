''
  echo "=== CPUID Emulation: Hypervisor-Phantom style patch ==="

  exactly_one arch/x86/kvm/svm/svm.c \
    '^[[:blank:]]*svm_vcpu_enter_exit\(vcpu,.*\);$' \
    "svm.c: svm_vcpu_enter_exit call site in svm_vcpu_run"

  sed -i '/^[[:blank:]]*svm_vcpu_enter_exit(vcpu,.*);$/i\\nreenter_guest_fast:' \
    arch/x86/kvm/svm/svm.c
  landed arch/x86/kvm/svm/svm.c 'reenter_guest_fast:' \
    "svm.c: reenter_guest_fast label"

  sed -i '/^[[:blank:]]*svm_vcpu_enter_exit(vcpu,.*);$/a\\n\tif (unlikely(svm->vmcb->control.exit_code == SVM_EXIT_CPUID)) {\n\t\t/* why: a set trap flag needs the single-step #DB after the CPUID, which only the full exit path raises */\n\t\tif (svm->vmcb->save.rax == 0 \&\& !(svm->vmcb->save.rflags \& X86_EFLAGS_TF)) {\n\t\t\tu64 old_rip = svm->vmcb->save.rip;\n\t\t\tu64 next_rip = svm->vmcb->control.next_rip;\n\t\t\tstruct kvm_cpuid_entry2 *leaf0 = kvm_find_cpuid_entry(vcpu, 0);\n\n\t\t\tif (!next_rip)\n\t\t\t\tnext_rip = old_rip + svm->vmcb->control.insn_len;\n\n\t\t\t/* why: a zero-length step would spin here with GIF cleared and lock the CPU */\n\t\t\tif (leaf0 && next_rip != old_rip) {\n\t\t\t\tsvm->vmcb->save.rax = leaf0->eax;\n\n\t\t\t\tvcpu->arch.regs[VCPU_REGS_RBX] = leaf0->ebx;\n\t\t\t\tvcpu->arch.regs[VCPU_REGS_RCX] = leaf0->ecx;\n\t\t\t\tvcpu->arch.regs[VCPU_REGS_RDX] = leaf0->edx;\n\n\t\t\t\tsvm->vmcb->save.rip = next_rip;\n\t\t\t\tkvm_rip_write(vcpu, next_rip);\n\t\t\t\tsvm->vmcb->control.int_state \&= ~SVM_INTERRUPT_SHADOW_MASK;\n\n\t\t\t\tgoto reenter_guest_fast;\n\t\t\t}\n\t\t}\n\t}' \
    arch/x86/kvm/svm/svm.c
  landed arch/x86/kvm/svm/svm.c 'goto reenter_guest_fast;' \
    "svm.c: CPUID leaf 0 answered from the VM's own CPUID entry without a full exit"
  landed arch/x86/kvm/svm/svm.c '!(svm->vmcb->save.rflags & X86_EFLAGS_TF)' \
    "svm.c: the fast path leaves a single-stepped CPUID to the full exit path"
  landed arch/x86/kvm/svm/svm.c 'svm->vmcb->control.int_state &= ~SVM_INTERRUPT_SHADOW_MASK;' \
    "svm.c: the fast path ends an interrupt shadow as skipping an instruction does"
  landed arch/x86/kvm/svm/svm.c 'struct kvm_cpuid_entry2 *leaf0 = kvm_find_cpuid_entry(vcpu, 0);' \
    "svm.c: the fast path reads leaf 0 from the VM's CPUID table, so it reports what KVM would"

  exactly_one arch/x86/kvm/svm/svm.c \
    'svm_set_intercept\(svm, INTERCEPT_RSM\);' \
    "svm.c: INTERCEPT_RSM anchor in init_vmcb"

  sed -i '/svm_set_intercept(svm, INTERCEPT_RSM);/a\\tsvm_clr_intercept(svm, INTERCEPT_RDTSC);\n\tsvm_clr_intercept(svm, INTERCEPT_RDTSCP);' \
    arch/x86/kvm/svm/svm.c
  landed arch/x86/kvm/svm/svm.c 'svm_clr_intercept(svm, INTERCEPT_RDTSC);' \
    "svm.c: RDTSC/RDTSCP intercept cleared in init_vmcb"

  echo "=== CPUID Emulation: patch complete ==="
''
