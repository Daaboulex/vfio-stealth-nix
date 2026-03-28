{
  lib,
  stdenvNoCC,
}:
# Placeholder — replaced in Task 6
stdenvNoCC.mkDerivation {
  pname = "smbios-extract";
  version = "0.0.1";
  dontUnpack = true;
  installPhase = "mkdir -p $out/bin";
}
