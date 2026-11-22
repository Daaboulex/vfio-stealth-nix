{
  lib,
  pkgs,
  runCommand,
  writeText,
  cfg,
  nixvirt,
  swtpm,
  libvirt,
  python3,
  xorriso,
  libxml2,
  _7zz,
  vmaware,
  iso,
  installed,
  vbs,
  gpu,
  hostDevices,
  memory,
  cores,
  threads,
  pinning,
  writeShellApplication,
}:

assert lib.assertMsg (iso == null || builtins.isPath iso)
  "evidence.windows: iso must be a path such as /path/to/Win11.iso, so Nix copies it into the store";
assert lib.assertMsg (
  iso == null || installed == null
) "evidence.windows: give iso to install Windows or installed to boot an earlier result, not both";

let
  render = import ./domain-xml.nix {
    inherit
      lib
      pkgs
      writeText
      cfg
      nixvirt
      ;
  };

  xml = render "windows" (
    {
      uuid = "5f0c7a52-3b1e-4c6a-9d2e-7a4b8c9d0e1f";
      inherit
        memory
        cores
        threads
        pinning
        ;
      disks = [
        {
          source = "/windows/disk.qcow2";
          format = "qcow2";
        }
      ];
      cdroms = [
        "/windows/installer.iso"
        "/windows/probe.iso"
      ];
      tpm = true;
      secureBoot = true;
      network = {
        type = "network";
        source = "default";
        model = "e1000e";
      };
    }
    // lib.optionalAttrs (hostDevices != [ ]) { inherit hostDevices; }
    // lib.optionalAttrs (gpu != null) {
      gpu = {
        audio = null;
        extraFunctions = [ ];
        rom = null;
        binding = "libvirt";
        ids = [ ];
        resizeBar2Mb = null;
        rebindOnStop = false;
      }
      // gpu;
    }
  );

  probeConfig = writeText "vfio-probe.json" (
    builtins.toJSON {
      inherit (cfg) hypervMode;
      inherit vbs;
    }
  );

  media =
    runCommand "vfio-stealth-windows-media"
      {
        nativeBuildInputs = [
          xorriso
          python3
        ]
        ++ lib.optionals (iso != null) [
          _7zz
          libxml2
        ];
      }
      ''
        mkdir -p root/vmaware $out
        ${lib.optionalString (iso != null) ''
          7zz e -so -ssc- ${iso} sources/lang.ini > lang.ini
          language=$(python3 -I ${./windows-language.py} lang.ini)
          echo "installer language: $language"
          substitute ${./windows/autounattend.xml} root/autounattend.xml --subst-var-by language "$language"
          xmllint --noout root/autounattend.xml
        ''}
        cp ${./windows/run.ps1} root/run.ps1
        cp ${./windows/account.ps1} root/account.ps1
        cp ${../guest/verify-stealth.ps1} root/verify-stealth.ps1
        cp ${../guest/cleanup-registry.ps1} root/cleanup-registry.ps1
        cp -L ${vmaware}/bin/* root/vmaware/
        cp ${probeConfig} root/vfio-probe.json
        xorriso -as mkisofs -quiet -J -joliet-long -R -V VFIOPROBE -o $out/probe.iso root
      '';

  plan = writeText "windows-check.json" (
    builtins.toJSON {
      inherit xml;
      media = "${media}/probe.iso";
      installer = if iso == null then null else "${iso}";
      installed = if installed == null then null else builtins.storePath (toString installed);
      swtpm = "${swtpm}";
      vmawareExpected = ./vmaware-expected-windows.json;
      judge = ./windows-judge.py;
      gpu =
        (
          if gpu == null then
            [ ]
          else
            [ gpu.address ]
            ++ lib.optional ((gpu.audio or null) != null) gpu.audio
            ++ (gpu.extraFunctions or [ ])
        )
        ++ hostDevices;
      diskSize = "64G";
      seconds = {
        install = 4 * 3600;
        installed = 3600;
        empty = 600;
      };
      config = {
        inherit (cfg) cpuVendor hypervMode;
        inherit (cfg.acpi) waet;
        inherit vbs;
      };
    }
  );

  patchedPlan = writeText "windows-check-patched.json" (
    builtins.toJSON {
      vmawareExpected = ./vmaware-expected-windows.json;
      config = {
        inherit (cfg) cpuVendor hypervMode;
        inherit (cfg.acpi) waet;
        inherit vbs;
        patchedKernel = true;
      };
    }
  );
in
runCommand "vfio-stealth-windows-${cfg.cpuVendor}-${cfg.hypervMode}${lib.optionalString vbs "-vbs"}"
  {
    nativeBuildInputs = [
      python3
      libvirt
      swtpm
      cfg.packages.qemu
    ];
    requiredSystemFeatures = [ "kvm" ];
    passthru = {
      inherit media xml patchedPlan;
      judge = ./windows-judge.py;
      runner = writeShellApplication {
        name = "vfio-stealth-windows-run";
        runtimeInputs = [
          python3
          libvirt
          swtpm
          cfg.packages.qemu
        ];
        text = ''
          out=$(realpath -m "$1")
          work=$(mktemp -d -p /var/tmp vfio-stealth-windows.XXXXXX)
          trap 'rm -rf "$work"' EXIT
          cd "$work"
          export HOME=$work XDG_RUNTIME_DIR=$work/run XDG_CONFIG_HOME=$work/config XDG_CACHE_HOME=$work/cache
          mkdir -p "$XDG_RUNTIME_DIR"
          echo "windows: working in $work"
          python3 -I ${./windows.py} ${plan} "$out"
        '';
      };
    };
  }
  ''
    export HOME=$TMPDIR XDG_RUNTIME_DIR=$TMPDIR/run XDG_CONFIG_HOME=$TMPDIR/config XDG_CACHE_HOME=$TMPDIR/cache
    mkdir -p $XDG_RUNTIME_DIR
    python3 -I ${./windows.py} ${plan} $out
  ''
