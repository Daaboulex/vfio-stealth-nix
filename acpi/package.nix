{
  lib,
  stdenvNoCC,
}:
# Placeholder — replaced in Task 3
stdenvNoCC.mkDerivation {
  pname = "acpi-ssdt-stealth";
  version = "0.0.1";
  dontUnpack = true;
  installPhase = "mkdir -p $out";
}
