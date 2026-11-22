{ runCommand, acpi-ssdt-stealth }:

let
  tables = acpi-ssdt-stealth.override {
    oemId = "TESTOE";
    oemTableId = "TESTTBL1";
  };
in
runCommand "acpi-oem" { } ''
  for table in ${tables}/share/acpi/*.aml; do
    id=$(dd if="$table" bs=1 skip=10 count=6 status=none)
    tableId=$(dd if="$table" bs=1 skip=16 count=8 status=none)
    if [ "$id$tableId" != TESTOETESTTBL1 ]; then
      echo "$(basename "$table") carries OEM '$id' / '$tableId', not the configured TESTOE / TESTTBL1"
      exit 1
    fi
  done
  touch $out
''
