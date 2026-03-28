{
  lib,
  stdenvNoCC,
  acpica-tools,
}:

stdenvNoCC.mkDerivation {
  pname = "acpi-ssdt-stealth";
  version = "1.0.0";

  src = ./.;

  nativeBuildInputs = [ acpica-tools ];

  buildPhase = ''
    iasl -p spoofed-devices spoofed-devices.dsl
    iasl -p fake-battery fake-battery.dsl
  '';

  installPhase = ''
    mkdir -p $out/share/acpi
    cp spoofed-devices.aml $out/share/acpi/
    cp fake-battery.aml $out/share/acpi/
  '';

  meta = {
    description = "ACPI SSDT tables for VM anti-detection (fake EC, fan, thermal zone, battery)";
    license = lib.licenses.gpl2Only;
    platforms = [ "x86_64-linux" ];
  };
}
