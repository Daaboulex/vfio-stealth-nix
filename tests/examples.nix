{
  lib,
  runCommand,
  libvirt,
  nix,
  nixosSystem,
  module,
}:

let
  examples = {
    configuration = ../examples/configuration.nix;
    hardened-gaming = ../examples/hardened-gaming.nix;
  };

  evaluate =
    file:
    (nixosSystem {
      system = "x86_64-linux";
      modules = [
        module
        file
        {
          fileSystems."/" = {
            device = "/dev/disk/by-label/nixos";
            fsType = "ext4";
          };
          boot.loader.systemd-boot.enable = true;
          system.stateVersion = lib.trivial.release;
        }
      ];
    }).config;

  configs = lib.mapAttrs (_: evaluate) examples;

  failed = lib.concatLists (
    lib.mapAttrsToList (
      name: config: map (a: "${name}: ${a.message}") (lib.filter (a: !a.assertion) config.assertions)
    ) configs
  );

  warned = lib.concatLists (
    lib.mapAttrsToList (
      name: config: map (w: "${name}: ${w}") (lib.filter (lib.hasPrefix "vfio-stealth:") config.warnings)
    ) configs
  );

  domains = lib.concatMap (
    config: map (domain: domain.xml) (lib.attrValues config.virtualisation.vfio-stealth.domains)
  ) (lib.attrValues configs);
in
assert lib.assertMsg (
  failed == [ ]
) "examples fail their assertions: ${lib.concatStringsSep "; " failed}";
assert lib.assertMsg (warned == [ ])
  "examples raise module warnings, which a user who copies one would inherit: ${lib.concatStringsSep "; " warned}";
assert lib.assertMsg (lib.all (config: config.virtualisation.vfio-stealth.domains != { }) (
  lib.attrValues configs
)) "an example declares no domain, so its rendering is never validated";
runCommand "examples"
  {
    nativeBuildInputs = [
      libvirt
      nix
    ];
    toplevels = map (config: builtins.unsafeDiscardStringContext config.system.build.toplevel.drvPath) (
      lib.attrValues configs
    );
    inherit domains;
  }
  ''
    export HOME=$TMPDIR
    for domain in $domains; do
      virt-xml-validate $domain domain
    done
    nix-instantiate --parse ${../examples/flake.nix} > /dev/null
    echo "the examples evaluate to $toplevels"
    touch $out
  ''
