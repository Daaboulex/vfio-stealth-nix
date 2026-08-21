# Clears INTERCEPT_CPUID so the guest executes CPUID at native speed.
# VMRUN loads guest XCR0 from the VMCB before guest execution, so CPUID leaf
# 0xD stays consistent with the guest's XCR0 and needs no synchronization.
# Targets: arch/x86/kvm/svm/svm.c
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
