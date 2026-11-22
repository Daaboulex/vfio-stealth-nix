{
  lib,
  runCommand,
  nixosSystem,
  module,
}:

let
  documents = [
    {
      name = "README.md";
      key = "readme";
      file = ../README.md;
    }
    {
      name = "docs/GUIDE.md";
      key = "guide";
      file = ../docs/GUIDE.md;
    }
    {
      name = "docs/QUICKSTART.md";
      key = "quickstart";
      file = ../docs/QUICKSTART.md;
    }
  ];

  blocksOf =
    document:
    let
      lines = lib.imap1 (number: text: { inherit number text; }) (
        lib.splitString "\n" (builtins.readFile document.file)
      );
      step =
        state: line:
        let
          opening = builtins.match "( *)```nix[[:space:]]*" line.text;
          closing = builtins.match " *```[[:space:]]*" line.text;
        in
        if state.open == null then
          if opening != null then
            state
            // {
              open = {
                inherit (line) number;
                indent = lib.head opening;
                body = [ ];
              };
            }
          else
            state
        else if closing != null then
          {
            open = null;
            blocks = state.blocks ++ [
              {
                document = document.name;
                inherit (state.open) number body;
              }
            ];
          }
        else
          state
          // {
            open = state.open // {
              body = state.open.body ++ [ (lib.removePrefix state.open.indent line.text) ];
            };
          };
      final = lib.foldl' step {
        open = null;
        blocks = [ ];
      } lines;
    in
    assert lib.assertMsg (final.open == null)
      "guide-snippets: ${document.name} line ${toString final.open.number} opens a nix block that never closes";
    lib.imap1 (
      index: block:
      let
        text = lib.concatStringsSep "\n" block.body + "\n";
        name = "${document.key}-${lib.fixedWidthString 2 "0" (toString index)}.txt";
        snippet = ./snippets + "/${name}";
        firstLine = lib.findFirst (line: builtins.match "[[:space:]{}]*" line == null) (lib.head (
          block.body ++ [ "" ]
        )) block.body;
      in
      block
      // {
        inherit text;
        label = "${block.document} line ${toString block.number}: ${lib.strings.trim firstLine}";
        isModule = lib.hasInfix "virtualisation.vfio-stealth" text && !lib.hasInfix "nixosSystem" text;
        value =
          assert lib.assertMsg (builtins.pathExists snippet && builtins.readFile snippet == text)
            "guide-snippets: tests/snippets/${name} differs from the nix block at ${block.document} line ${toString block.number}; copy the block into it";
          import snippet;
      }
    ) final.blocks;

  snippetFiles = lib.attrNames (builtins.readDir ./snippets);

  base = {
    virtualisation.vfio-stealth = {
      enable = lib.mkDefault true;
      cpuVendor = lib.mkDefault "amd";
      smbios.manufacturer = lib.mkDefault "Example Inc.";
      smbios.product = lib.mkDefault "Example Board";
    };
    virtualisation.libvirtd.enable = lib.mkDefault true;
    fileSystems."/" = {
      device = "/dev/disk/by-label/nixos";
      fsType = "ext4";
    };
    boot.loader.grub.enable = false;
    system.stateVersion = lib.trivial.release;
  };

  stepsOf =
    blocks:
    (lib.foldl'
      (
        state: block:
        let
          merged =
            if lib.isFunction block.value then
              state // { functions = state.functions ++ [ block.value ]; }
            else
              state // { settings = lib.recursiveUpdate state.settings block.value; };
        in
        merged
        // {
          steps = state.steps ++ [
            {
              inherit (block) label;
              modules = [
                module
                base
                merged.settings
              ]
              ++ merged.functions;
            }
          ];
        }
      )
      {
        settings = { };
        functions = [ ];
        steps = [ ];
      }
      (lib.filter (block: block.isModule) blocks)
    ).steps;

  check =
    step:
    let
      inherit
        (nixosSystem {
          system = "x86_64-linux";
          inherit (step) modules;
        })
        config
        ;
      outputs = [
        config.system.build.toplevel.drvPath
      ]
      ++ lib.mapAttrsToList (_: domain: domain.xml.drvPath) config.virtualisation.vfio-stealth.domains;
      failed = map (a: a.message) (lib.filter (a: !a.assertion) config.assertions);
      broken =
        part:
        builtins.trace "guide-snippets: ${step.label} no longer evaluates with the blocks before it" (
          builtins.deepSeq part false
        );
    in
    if !(builtins.tryEval (builtins.deepSeq failed true)).success then
      broken failed
    else if failed != [ ] then
      lib.assertMsg false "guide-snippets: ${step.label} fails an assertion with the blocks before it: ${lib.concatStringsSep "; " failed}"
    else if !(builtins.tryEval (builtins.deepSeq outputs true)).success then
      broken outputs
    else
      true;

  perDocument = map blocksOf documents;
  blocks = lib.concatLists perDocument;
  steps = lib.concatMap stepsOf perDocument;
  parsed = lib.all (block: builtins.seq block.value true) blocks;
in
assert parsed;
assert lib.assertMsg (lib.length snippetFiles == lib.length blocks)
  "guide-snippets: tests/snippets holds ${toString (lib.length snippetFiles)} files for ${toString (lib.length blocks)} nix blocks; remove the files no block has";
assert lib.all check steps;
runCommand "guide-snippets" { } ''
  echo "guide-snippets: ${toString (lib.length blocks)} nix blocks parse; ${toString (lib.length steps)} module blocks evaluate in document order"
  touch $out
''
