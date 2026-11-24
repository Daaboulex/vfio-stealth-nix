{
  lib,
  runCommand,
}:

let
  techniques =
    file:
    lib.unique (lib.concatLists (lib.concatMap lib.attrValues (lib.attrValues (lib.importJSON file))));
  windows = techniques ../verify/vmaware-expected-windows.json;
  linux = techniques ../verify/vmaware-expected.json;
  expected = lib.unique (windows ++ linux);

  section =
    file: heading:
    let
      parts = lib.splitString "\n${heading}\n" (builtins.readFile file);
    in
    assert lib.assertMsg (
      lib.length parts == 2
    ) "vmaware-docs: ${toString file} has no single heading '${heading}'";
    lib.head (lib.splitString "\n#" (lib.elemAt parts 1));

  words = text: lib.filter lib.isString (builtins.split "[^A-Za-z0-9_]+" text);
  names = text: lib.filter (word: builtins.match "[A-Z][A-Z0-9_]{3,}" word != null) (words text);
  mentions = text: technique: lib.elem technique (words text);

  firstCells =
    text:
    lib.concatMap (
      line:
      let
        cells = builtins.match "[|] ([^|]*) [|].*" line;
      in
      lib.optional (cells != null) (lib.head cells)
    ) (lib.splitString "\n" text);

  places = {
    limits = {
      where = "docs/COMPATIBILITY.md, Known limitations";
      text = section ../docs/COMPATIBILITY.md "## Known limitations";
      need = windows;
      rows =
        cells: map (cell: lib.removePrefix "VMAware " cell) (lib.filter (lib.hasPrefix "VMAware ") cells);
    };
    guide = {
      where = "docs/GUIDE.md, Read a VMAware result";
      text = section ../docs/GUIDE.md "### Read a VMAware result";
      need = windows;
      rows = cells: cells;
    };
    probe = {
      where = "docs/DEVELOPMENT.md, VMAware in the probe";
      text = section ../docs/DEVELOPMENT.md "## VMAware in the probe";
      need = linux;
      rows = cells: cells;
    };
  };

  missing = lib.concatLists (
    lib.mapAttrsToList (
      _: place:
      map (technique: "${place.where} does not explain ${technique}, which a VMAware list expects") (
        lib.filter (technique: !mentions place.text technique) place.need
      )
    ) places
  );

  stale = lib.concatLists (
    lib.mapAttrsToList (
      _: place:
      map
        (
          name:
          "${place.where} has a row for ${name}, which no VMAware list expects any more; remove or reword it"
        )
        (
          lib.filter (name: !lib.elem name expected) (
            lib.concatMap names (place.rows (firstCells place.text))
          )
        )
    ) places
  );

  problems = missing ++ stale;
in
assert lib.assertMsg (problems == [ ]) "vmaware-docs: ${lib.concatStringsSep "; " problems}";
runCommand "vmaware-docs" { } ''
  echo "vmaware-docs: every expected VMAware technique is explained where users and developers read it"
  touch $out
''
