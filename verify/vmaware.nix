{
  lib,
  stdenv,
  fetchFromGitHub,
  cmake,
}:

let
  pin = (lib.importJSON ../version.json).vmaware;
in
stdenv.mkDerivation (
  finalAttrs:
  {
    pname = "vmaware";
    inherit (pin) version;

    src = fetchFromGitHub {
      owner = "kernelwernel";
      repo = "VMAware";
      tag = "v${finalAttrs.version}";
      inherit (pin) hash;
    };

    nativeBuildInputs = [ cmake ];

    doInstallCheck = stdenv.buildPlatform.canExecute stdenv.hostPlatform;
    installCheckPhase = ''
      $out/bin/vmaware --number > /dev/null
    '';

    meta = {
      description = "VM detection library and its command line tool, run only inside the boot probe guest and the Windows evidence guest";
      homepage = "https://github.com/kernelwernel/VMAware";
      license = lib.licenses.mit;
      platforms = lib.platforms.linux ++ lib.platforms.windows;
      mainProgram = "vmaware";
    };
  }
  // lib.optionalAttrs stdenv.hostPlatform.isWindows {
    # why: upstream builds Windows with MSVC only; mingw-w64 lacks AoAc, pads OBJECT_ATTRIBUTES, has no __cpuid_count and names dbghelp in lower case, GCC has no __try, so clang with -fms-extensions builds it, and clang drops a __try that holds only inline asm, so the patch moves that asm into called functions
    patches = [ ./vmaware-mingw.patch ];

    env.NIX_CFLAGS_COMPILE = "-fms-extensions";
    env.NIX_CFLAGS_LINK = "-static";

    postFixup = ''
      $OBJDUMP -p "$out/bin/vmaware.exe" > imports.txt
      readarray -t imports < <(sed -n 's/.*DLL Name: \(.*\)/\1/p' imports.txt | sort -u)
      if [ ''${#imports[@]} -eq 0 ]; then
        echo "vmaware.exe lists no imported DLL, so its import table was not read" >&2
        exit 1
      fi
      readarray -td: folders < <(printf -- "%s" "$LINK_DLL_FOLDERS")
      shipped=()
      for dll in "''${imports[@]}"; do
        found=$(find -L "''${folders[@]}" -iname "$dll" -type f -print -quit)
        if [ -n "$found" ]; then
          shipped+=("$found")
        fi
      done
      if [ ''${#shipped[@]} -gt 0 ]; then
        echo "vmaware.exe imports DLLs that a Nix input ships and no Windows install has: ''${shipped[*]}" >&2
        exit 1
      fi
      echo "vmaware.exe imports only DLLs no Nix input ships: ''${imports[*]}"
    '';
  }
)
