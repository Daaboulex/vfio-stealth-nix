{
  lib,
  runCommand,
  writeText,
  kernelSrc,
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

  runVariant = v: ''
    rm -rf work
    cp -al pristine work
    if ( cd work && bash -eu -o pipefail ${writeText "postpatch-${v.name}.sh" (prelude + v.body)} ) \
      > "log-${v.name}" 2>&1; then
      echo "  PASS  ${v.name}"
    else
      echo "  FAIL  ${v.name}"
      sed 's/^/          /' "log-${v.name}"
      failed=$((failed + 1))
    fi
    rm -rf work
  '';

  total = toString (lib.length variants);
in
runCommand "kernel-postpatch-fits-${sourceName}" { } ''
  if [ -d ${kernelSrc} ]; then
    cp -a ${kernelSrc} pristine
  else
    mkdir pristine
    tar -xf ${kernelSrc} -C pristine --strip-components=1
  fi
  chmod -R u+w pristine
  touch .stamp

  echo "kernel patch scripts vs ${sourceName}:"
  failed=0
  ${lib.concatMapStringsSep "\n" runVariant variants}

  mutated=$(find pristine -newer .stamp -type f | head -5)
  if [ -n "$mutated" ]; then
    echo "FAIL: a patch script wrote into the shared pristine tree, so later variants ran on corrupted input:"
    printf '  %s\n' $mutated
    exit 1
  fi

  if [ "$failed" -ne 0 ]; then
    echo "kernel-postpatch-fits[${sourceName}]: $failed of ${total} variant(s) no longer apply."
    echo "The kernel moved past an anchor. Re-aim the named edit in kernel/*.nix."
    exit 1
  fi
  echo "kernel-postpatch-fits[${sourceName}]: all ${total} variants apply"
  touch $out
''
