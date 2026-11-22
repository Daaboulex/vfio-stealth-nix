{
  lib,
  runCommand,
  writeText,
  acpica-tools,
  count,
  oemId,
  oemTableId,
}:

assert lib.assertMsg (
  count >= 1 && count <= 4096
) "acpi processors: count must be 1 to 4096, got ${toString count}";

let
  device = uid: ''
    Device (C${lib.fixedWidthString 3 "0" (lib.toHexString uid)})
    {
      Name (_HID, "ACPI0007")
      Name (_UID, ${toString uid})
    }
  '';
  source = writeText "processors.dsl" ''
    DefinitionBlock ("", "SSDT", 2, "${oemId}", "${oemTableId}", 0x00000001)
    {
      Scope (\_SB)
      {
        Device (PLTF)
        {
          Name (_HID, "ACPI0010")
          Name (_CID, EisaId ("PNP0A05"))
          Name (_UID, One)
          ${lib.concatMapStrings device (lib.range 0 (count - 1))}
        }
      }
    }
  '';
in
runCommand "acpi-processors-${toString count}" { nativeBuildInputs = [ acpica-tools ]; } ''
  cp ${source} processors.dsl
  iasl -p processors processors.dsl
  install -Dm444 processors.aml $out
''
