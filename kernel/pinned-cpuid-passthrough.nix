''
  echo "=== vfio-native: runtime CPUID passthrough on pinned vCPUs ==="

  if ! patch -p1 -F0 --no-backup-if-mismatch -i ${../vendor/vfio-native/EXPERIMENTAL-0006-runtime-cpuid-passthrough.patch}; then
    _stealth_die "EXPERIMENTAL-0006 does not apply with zero fuzz to this kernel; port it from vendor/vfio-native"
  fi
  landed arch/x86/kvm/svm/svm.c 'module_param(cpuid_passthrough, bool, 0644);' \
    "svm.c: kvm_amd.cpuid_passthrough switches CPUID passthrough at runtime"
''
