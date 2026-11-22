''
  echo "=== vfio-native: VMCALL and VMMCALL at CPL > 0 raise #UD ==="

  for fix in \
    ${../vendor/vfio-native/0002-KVM-x86-emulator-UD-not-GP-for-VMCALL-at-CPL-0.patch} \
    ${../vendor/vfio-native/0003-KVM-x86-UD-for-KVM-hypercalls-issued-at-CPL-0.patch}; do
    if ! patch -p1 -F0 --no-backup-if-mismatch -i "$fix"; then
      _stealth_die "$fix does not apply with zero fuzz to this kernel; port it from vendor/vfio-native"
    fi
  done
  landed arch/x86/kvm/emulate.c 'I(SrcNone | Priv | PrivUD | EmulateOnUD,	em_hypercall),' \
    "emulate.c: VMCALL at CPL > 0 raises #UD"
  landed arch/x86/kvm/x86.c 'Bare metal #UDs on VMMCALL from CPL > 0' \
    "x86.c: a hypercall at CPL > 0 raises #UD"
''
