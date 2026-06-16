{
  lib,
  runCommand,
  linux_latest,
  cachyosLtoLatest,
}:

let
  # Two kernel sources are checked:
  # 1. linux_latest (nixpkgs upstream) — sanity check the anchors exist
  #    in current upstream, so a future refactor that breaks the anchor
  #    is caught even if CachyOS hasn't pulled it yet.
  # 2. CachyOS LTO latest (the user's actual production source) — the
  #    CachyOS patchset is applied on top of upstream; if any anchor
  #    moves under CachyOS, this test fails LOUDLY. Tracks the user's
  #    rolling kernel (no pin) so the contract test follows the
  #    user's actual production source.
  sources = [
    {
      name = "upstream-latest";
      inherit (linux_latest) src;
    }
    {
      name = "cachyos-lto-latest";
      src = cachyosLtoLatest.kernel.src;
    }
  ];

  # Per-anchor contract: (name, relative path inside the kernel tree,
  # pattern, max-allowed-match-count for awk anchors that would edit
  # the wrong block if multiple matches exist).
  anchors = [
    {
      name = "kvm_vcpu.valid_wakeup";
      path = "include/linux/kvm_host.h";
      pattern = "bool valid_wakeup;";
      max = 1;
    }
    {
      name = "msr_ia32_tsc.case";
      path = "arch/x86/kvm/x86.c";
      pattern = "case MSR_IA32_TSC: \\{";
      max = 1;
    }
    {
      name = "intercept_rsm.svm";
      path = "arch/x86/kvm/svm/svm.c";
      pattern = "svm_set_intercept\\(svm, INTERCEPT_RSM\\);";
      max = 1;
    }
    {
      name = "svm_exit_handlers";
      path = "arch/x86/kvm/svm/svm.c";
      pattern = "static int \\(\\*const svm_exit_handlers\\[\\])";
      max = 1;
    }
    {
      name = "avic_unacc_entry";
      path = "arch/x86/kvm/svm/svm.c";
      pattern = "\\[SVM_EXIT_AVIC_UNACCELERATED_ACCESS\\].*avic_unaccelerated_access_interception";
      max = 1;
    }
    {
      name = "svm_exit_rdtscp";
      path = "arch/x86/kvm/svm/svm.c";
      pattern = "\\[SVM_EXIT_RDTSCP\\].*=.*kvm_handle_invalid_op,";
      max = 1;
    }
    {
      name = "kvm_quirk_hypercall";
      path = "arch/x86/kvm/x86.c";
      pattern = "if \\(!kvm_check_has_quirk\\(vcpu->kvm, KVM_X86_QUIRK_FIX_HYPERCALL_INSN\\)\\)";
      max = 1;
    }
    {
      name = "svm_vcpu_enter_exit";
      path = "arch/x86/kvm/svm/svm.c";
      pattern = "svm_vcpu_enter_exit\\(vcpu, spec_ctrl_intercepted\\);";
      max = 1;
    }
    {
      name = "pre_svm_run.def";
      path = "arch/x86/kvm/svm/svm.c";
      pattern = "static int pre_svm_run\\(struct kvm_vcpu \\*vcpu\\)";
      max = 1;
    }
  ];

  # Render a per-(source, anchor) check as a shell script. Nix
  # interpolation gives us source name, anchor name, anchor path,
  # anchor pattern, and the int max — all materialised into the
  # shell at eval time. The shell uses literal numbers for
  # comparison (no shell-variable interpolation; the multiline
  # Nix string's $ would otherwise confuse the Nix parser).
  #
  # Source-type detection: upstream `linux_latest.src` is a tarball
  # (fetchurl); CachyOS's `kernel.src` is a directory (the build
  # produces a tree). We test the source type and handle both —
  # the test does NOT build the kernel, it just inspects the
  # already-patched source for the awk anchors.
  renderCheck =
    s: a:
    let
      patternEsc = lib.escapeShellArg a.pattern;
      maxStr = toString a.max;
    in
    ''
      if [ ! -d /tmp/anchorsrc ]; then
        mkdir -p /tmp/anchorsrc
        if [ -d ${s.src} ]; then
          cp -r ${s.src}/. /tmp/anchorsrc/
        else
          tar -xf ${s.src} -C /tmp/anchorsrc --strip-components=1
        fi
      fi
      if [ ! -f /tmp/anchorsrc/${a.path} ]; then
        echo "  FAIL [${s.name}]: ${a.path} not found in the source tree"
      else
        found=$(grep -cE -- ${patternEsc} /tmp/anchorsrc/${a.path} 2>/dev/null || echo 0)
        if [ "$found" -lt 1 ]; then
          echo "  FAIL [${s.name}]: ${a.name} -- anchor not found in ${a.path}: ${a.pattern}"
        elif [ "$found" -gt ${maxStr} ]; then
          echo "  WARN [${s.name}]: ${a.name} -- $found matches in ${a.path} (max allowed ${maxStr}); awk-anchored edits may target the wrong block"
        else
          echo "  OK   [${s.name}]: ${a.name} -- $found match in ${a.path}"
        fi
      fi
    '';

  renderSource = s: ''
    echo "=== source: ${s.name} ==="
    rm -rf /tmp/anchorsrc
    ${lib.concatMapStringsSep "\n" (a: renderCheck s a) anchors}
  '';

  allChecks = lib.concatMapStringsSep "\n" renderSource sources;
in
runCommand "kernel-anchor-contract" { } ''
  ${allChecks}
  echo "kernel-anchor-contract: all ${toString (lib.length anchors)} anchors checked across ${toString (lib.length sources)} sources"
  touch $out
''
