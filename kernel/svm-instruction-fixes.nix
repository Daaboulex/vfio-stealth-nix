''
  echo "=== vfio-native: SVM instructions and ICEBP as on bare metal ==="

  if ! patch -p1 -F0 --no-backup-if-mismatch -i ${../vendor/vfio-native/0001-KVM-SVM-intercept-GP-when-guest-EFER.SVME-is-clear.patch}; then
    _stealth_die "0001 does not apply with zero fuzz to this kernel; port it from vendor/vfio-native"
  fi

  # why: Linux 7.3 intercepts ICEBP itself with the same fix, and 0004 still applies there with zero fuzz, defining the handler twice
  if grep -qF 'static int icebp_interception(struct kvm_vcpu *vcpu)' arch/x86/kvm/svm/svm.c; then
    echo "[OK] svm.c: this kernel intercepts ICEBP itself, so 0004 is not applied"
  elif ! patch -p1 -F0 --no-backup-if-mismatch -i ${../vendor/vfio-native/0004-KVM-SVM-intercept-ICEBP-and-skip-it-before-injecting-its-DB.patch}; then
    _stealth_die "0004 does not apply with zero fuzz to this kernel; port it from vendor/vfio-native"
  fi

  # why: inside an SVM guest the CPU itself raises #GP for VMCALL at CPL > 0, because hardware sees EFER.SVME set, so 0002's emulator path never runs; 0001's #GP intercept is where it can be turned into the #UD of bare metal
  exactly_one arch/x86/kvm/svm/svm.c '^	if \(!enable_vmware_backdoor \|\| is_guest_mode\(vcpu\)\)$' \
    "svm.c: the VMware backdoor check in gp_interception"
  sed -i '/^\tif (!enable_vmware_backdoor || is_guest_mode(vcpu))$/i\
  \tif (vcpu->arch.emulate_ctxt->opcode_len == 2 &&\
  \t    vcpu->arch.emulate_ctxt->b == 0x01 &&\
  \t    vcpu->arch.emulate_ctxt->modrm == 0xc1 &&\
  \t    kvm_x86_call(get_cpl)(vcpu)) {\
  \t\tkvm_queue_exception(vcpu, UD_VECTOR);\
  \t\treturn 1;\
  \t}\
  ' arch/x86/kvm/svm/svm.c
  landed arch/x86/kvm/svm/svm.c 'vcpu->arch.emulate_ctxt->modrm == 0xc1 &&' \
    "svm.c: a VMCALL #GP at CPL > 0 becomes #UD"

  landed arch/x86/kvm/svm/svm.c 'and route it to its handler, which injects the #UD.' \
    "svm.c: #GP intercepted while the guest's EFER.SVME is clear"
  exactly_one arch/x86/kvm/svm/svm.c '^static int icebp_interception\(struct kvm_vcpu \*vcpu\)$' \
    "svm.c: one ICEBP handler that skips the instruction before its #DB"
''
