{
  lib,
  writeText,
  kernel,
  sourceName,
}:

let
  prelude = import ../kernel/prelude.nix;
  timing = import ../kernel/timing-patch.nix;
  cpuidSpoof = import ../kernel/cpuid-patch.nix;
  cpuidPassthrough = import ../kernel/cpuid-disable.nix;

  variants = [
    {
      name = "timing";
      body = timing;
    }
    {
      name = "cpuid-spoof";
      body = cpuidSpoof;
    }
    {
      name = "cpuid-passthrough";
      body = cpuidPassthrough;
    }
    {
      name = "timing+cpuid-spoof";
      body = timing + cpuidSpoof;
    }
    {
      name = "timing+cpuid-passthrough";
      body = timing + cpuidPassthrough;
    }
  ];

  kernelMakeFlags = lib.escapeShellArgs (map toString (kernel.makeFlags or [ ]));

  runVariant = v: ''
    rm -rf work
    cp -al pristine work
    # set +e, then the subshell as a plain command: inside `( ) && x || y` bash
    # propagates the AND-OR exemption and the inner `set -e` never fires.
    set +e
    (
      set -euo pipefail
      cd work
      bash -eu -o pipefail ${writeText "postpatch-${v.name}.sh" (prelude + v.body)}
      mkflags=(${kernelMakeFlags})
      export buildRoot="$PWD/kbuild"
      mkdir -p "$buildRoot"
      cp "$configSrc" "$buildRoot/.config"
      chmod u+w "$buildRoot/.config"
      sed -i 's/^CONFIG_DEBUG_INFO_BTF=y$/# CONFIG_DEBUG_INFO_BTF is not set/' "$buildRoot/.config"
      make "''${mkflags[@]}" olddefconfig
      make "''${mkflags[@]}" -j"$NIX_BUILD_CORES" modules_prepare
      make "''${mkflags[@]}" -j"$NIX_BUILD_CORES" arch/x86/kvm/
      test -f "$buildRoot/arch/x86/kvm/svm/svm.o" \
        || { echo "make exited 0 but produced no arch/x86/kvm/svm/svm.o"; exit 1; }
    ) > "log-${v.name}" 2>&1
    rc=$?
    set -e
    if [ "$rc" -eq 0 ]; then
      echo "  PASS  ${v.name}"
    else
      echo "  FAIL  ${v.name} (exit $rc)"
      grep -nE 'error:|Error [0-9]|warning:.*svm|_stealth_die|\[FAIL\]' "log-${v.name}" \
        | head -25 | sed 's/^/          /'
      echo "          ---- last 25 lines ----"
      tail -25 "log-${v.name}" | sed 's/^/          /'
      failed=$((failed + 1))
    fi
    rm -rf work
  '';

  total = toString (lib.length variants);
in
kernel.stdenv.mkDerivation {
  name = "kernel-kvm-compiles-${sourceName}";
  inherit (kernel) src nativeBuildInputs makeFlags;

  configSrc = kernel.configfile;

  dontConfigure = true;
  dontFixup = true;
  enableParallelBuilding = true;

  postUnpack = ''
    test -f "$configSrc" \
      || { echo "kernel.configfile is not a plain .config file: $configSrc"; exit 1; }
  '';

  buildPhase = ''
    runHook preBuild
    cd "$NIX_BUILD_TOP"
    mv "$sourceRoot" pristine
    chmod -R u+w pristine
    touch .stamp

    echo "compiling arch/x86/kvm against ${sourceName} (${kernel.version})"
    echo "using the kernel's own .config and makeFlags, with CONFIG_DEBUG_INFO_BTF off"
    echo "(BTF only generates debug info; it does not change the C that KVM compiles)"
    failed=0
    ${lib.concatMapStringsSep "\n" runVariant variants}

    mutated=$(find pristine -newer .stamp -type f | head -5)
    if [ -n "$mutated" ]; then
      echo "FAIL: the shared pristine tree was written to, so later variants compiled corrupted input:"
      printf '  %s\n' $mutated
      exit 1
    fi

    if [ "$failed" -ne 0 ]; then
      echo "kernel-kvm-compiles[${sourceName}]: $failed of ${total} variant(s) do not compile."
      echo "The patch still applies but the C around it changed. Re-work the named edit in kernel/*.nix."
      exit 1
    fi
    echo "kernel-kvm-compiles[${sourceName}]: all ${total} variants compile"
    runHook postBuild
  '';

  installPhase = "touch $out";
}
