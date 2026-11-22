{
  lib,
  stdenvNoCC,
  acpica-tools,
  oemId ? "ALASKA",
  oemTableId ? "A M I   ",
  batterySerial ? "41167",
}:

assert lib.assertMsg (
  builtins.stringLength oemId == 6
) "acpi-ssdt-stealth: oemId must be 6 characters, got '${oemId}'";
assert lib.assertMsg (
  builtins.stringLength oemTableId == 8
) "acpi-ssdt-stealth: oemTableId must be 8 characters, got '${oemTableId}'";
assert lib.assertMsg (
  builtins.match "[A-Za-z0-9]{1,16}" batterySerial != null
) "acpi-ssdt-stealth: batterySerial must be 1 to 16 letters and digits, got '${batterySerial}'";

stdenvNoCC.mkDerivation {
  pname = "acpi-ssdt-stealth";
  version = "1.0.0";

  src = ./.;

  nativeBuildInputs = [ acpica-tools ];

  postPatch = ''
    for table in spoofed-devices.dsl fake-battery.dsl sensor-probes.dsl; do
      substituteInPlace "$table" \
        --replace-fail '"ALASKA", "A M I   "' ${lib.escapeShellArg ''"${oemId}", "${oemTableId}"''}
    done
    substituteInPlace fake-battery.dsl --replace-fail '"41167",' '"${batterySerial}",'
  '';

  buildPhase = ''
    iasl -p spoofed-devices spoofed-devices.dsl
    iasl -p fake-battery fake-battery.dsl
    iasl -p sensor-probes sensor-probes.dsl
  '';

  installPhase = ''
    mkdir -p $out/share/acpi
    cp spoofed-devices.aml $out/share/acpi/
    cp fake-battery.aml $out/share/acpi/
    cp sensor-probes.aml $out/share/acpi/
  '';

  meta = {
    description = "ACPI SSDT tables for VM hardware emulation (emulated EC, fan, thermal zone, battery)";
    license = lib.licenses.gpl2Only;
    platforms = [ "x86_64-linux" ];
  };
}
