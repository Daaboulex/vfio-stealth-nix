# Ported from Scrut1ny/AutoVirt (Hypervisor-Phantom), linux-*-svm.patch.
# Targets: arch/x86/kvm/svm/svm.c
''
  echo "=== CPUID Emulation: Hypervisor-Phantom style patch ==="

  exactly_one arch/x86/kvm/svm/svm.c \
    '^[[:blank:]]*svm_vcpu_enter_exit\(vcpu,.*\);$' \
    "svm.c: svm_vcpu_enter_exit call site in svm_vcpu_run"

  sed -i '/^[[:blank:]]*svm_vcpu_enter_exit(vcpu,.*);$/i\\nreenter_guest_fast:' \
    arch/x86/kvm/svm/svm.c
  landed arch/x86/kvm/svm/svm.c 'reenter_guest_fast:' \
    "svm.c: reenter_guest_fast label"

  sed -i '/^[[:blank:]]*svm_vcpu_enter_exit(vcpu,.*);$/a\\n\t/* CPUID leaf 0 override; requires mitigations=off idle=poll processor.max_cstate=1 tsc=reliable */\n\tif (unlikely(svm->vmcb->control.exit_code == SVM_EXIT_CPUID)) {\n\t\tif (svm->vmcb->save.rax == 0) {\n\t\t\tsvm->vmcb->save.rax = 0x20;\n\n\t\t\tvcpu->arch.regs[VCPU_REGS_RBX] = 0x68747541;\n\t\t\tvcpu->arch.regs[VCPU_REGS_RCX] = 0x444d4163;\n\t\t\tvcpu->arch.regs[VCPU_REGS_RDX] = 0x69746e65;\n\n\t\t\t{\n\t\t\t\tu64 next_rip = svm->vmcb->control.next_rip;\n\t\t\t\tif (!next_rip)\n\t\t\t\t\tnext_rip = svm->vmcb->save.rip + svm->vmcb->control.insn_len;\n\t\t\t\tsvm->vmcb->save.rip = next_rip;\n\t\t\t\tvcpu->arch.regs[VCPU_REGS_RIP] = next_rip;\n\t\t\t}\n\n\t\t\tgoto reenter_guest_fast;\n\t\t}\n\t}' \
    arch/x86/kvm/svm/svm.c
  landed arch/x86/kvm/svm/svm.c 'goto reenter_guest_fast;' \
    "svm.c: CPUID leaf 0 override block"

  exactly_one arch/x86/kvm/svm/svm.c \
    'svm_set_intercept\(svm, INTERCEPT_RSM\);' \
    "svm.c: INTERCEPT_RSM anchor in init_vmcb"

  sed -i '/svm_set_intercept(svm, INTERCEPT_RSM);/a\\tsvm_clr_intercept(svm, INTERCEPT_RDTSC);\n\tsvm_clr_intercept(svm, INTERCEPT_RDTSCP);' \
    arch/x86/kvm/svm/svm.c
  landed arch/x86/kvm/svm/svm.c 'svm_clr_intercept(svm, INTERCEPT_RDTSC);' \
    "svm.c: RDTSC/RDTSCP intercept cleared in init_vmcb"

  echo "=== CPUID Emulation: patch complete ==="
''
