''
  echo "=== CPUID Passthrough: disabling CPUID interception ==="

  exactly_one arch/x86/kvm/svm/svm.c \
    'svm_set_intercept\(svm, INTERCEPT_RSM\);' \
    "svm.c: INTERCEPT_RSM anchor in init_vmcb"

  sed -i '/svm_set_intercept(svm, INTERCEPT_RSM);/a\\n\tsvm_clr_intercept(svm, INTERCEPT_CPUID);' \
    arch/x86/kvm/svm/svm.c
  landed arch/x86/kvm/svm/svm.c 'svm_clr_intercept(svm, INTERCEPT_CPUID);' \
    "svm.c: INTERCEPT_CPUID cleared in init_vmcb"

  sed -i '/^static int pre_svm_run(struct kvm_vcpu \*vcpu)/,/^}/ {
    /^}/ i\\n\tif (!is_guest_mode(vcpu))\n\t\tsvm_clr_intercept(to_svm(vcpu), INTERCEPT_CPUID);
  }' arch/x86/kvm/svm/svm.c
  landed_soft arch/x86/kvm/svm/svm.c 'svm_clr_intercept(to_svm(vcpu), INTERCEPT_CPUID);' \
    "svm.c: CPUID clear in pre_svm_run (optional; init_vmcb alone covers non-nested)"

  echo "=== CPUID Passthrough: patch complete ==="
''
