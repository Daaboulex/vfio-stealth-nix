{
  description = "VM hardware emulation stack for NixOS — QEMU, OVMF, ACPI, SMBIOS, timing";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
    git-hooks = {
      url = "github:cachix/git-hooks.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    std = {
      url = "github:Daaboulex/nix-packaging-standard?ref=v2.39.0";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.git-hooks.follows = "git-hooks";
    };

    # CachyOS kernel packaging, tracking master so kernel-postpatch-fits-cachyos
    # runs the real patch scripts against the rolling production kernel source.
    nix-cachyos-kernel = {
      url = "github:xddxdd/nix-cachyos-kernel";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    inputs@{ flake-parts, self, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];

      imports = [ inputs.std.flakeModules.base ];

      flake.overlays.default = final: _prev: {
        qemu-stealth = final.callPackage ./qemu/package.nix {
          autovirt = ./vendor/autovirt;
          cpuVendor = "amd";
        };
        qemu-stealth-intel = final.callPackage ./qemu/package.nix {
          autovirt = ./vendor/autovirt;
          cpuVendor = "intel";
        };
        ovmf-stealth = final.callPackage ./ovmf/package.nix {
          autovirt = ./vendor/autovirt;
          cpuVendor = "amd";
        };
        ovmf-stealth-intel = final.callPackage ./ovmf/package.nix {
          autovirt = ./vendor/autovirt;
          cpuVendor = "intel";
        };
        acpi-ssdt-stealth = final.callPackage ./acpi/package.nix { };
        smbios-extract = final.callPackage ./smbios/package.nix { };
        smbios-stealth-tables = final.callPackage ./smbios/tables-package.nix { };
        stealth-detect = final.callPackage ./detect/package.nix { };
      };

      flake.nixosModules.default = import ./module.nix;

      flake.lib = import ./lib.nix { inherit (inputs.nixpkgs) lib; };

      perSystem =
        { lib, pkgs, ... }:
        let
          x86 = pkgs.stdenv.hostPlatform.system == "x86_64-linux";
          arm = pkgs.stdenv.hostPlatform.system == "aarch64-linux";
          stealth-detect = pkgs.callPackage ./detect/package.nix { };
        in
        {
          pre-commit.settings.hooks.shfmt.excludes = [ "^guest/" ];
          pre-commit.settings.excludes = [ "^vendor/" ];

          packages = lib.mkMerge [
            { inherit stealth-detect; }
            (lib.mkIf x86 {
              default = pkgs.callPackage ./qemu/package.nix {
                autovirt = ./vendor/autovirt;
                cpuVendor = "amd";
              };
              qemu-stealth-intel = pkgs.callPackage ./qemu/package.nix {
                autovirt = ./vendor/autovirt;
                cpuVendor = "intel";
              };
              ovmf-stealth = pkgs.callPackage ./ovmf/package.nix {
                autovirt = ./vendor/autovirt;
                cpuVendor = "amd";
              };
              ovmf-stealth-intel = pkgs.callPackage ./ovmf/package.nix {
                autovirt = ./vendor/autovirt;
                cpuVendor = "intel";
              };
              acpi-ssdt-stealth = pkgs.callPackage ./acpi/package.nix { };
              smbios-extract = pkgs.callPackage ./smbios/package.nix { };
              smbios-stealth-tables = pkgs.callPackage ./smbios/tables-package.nix { };
            })
          ];

          checks = lib.mkMerge [
            {
              detect-fixture-contract = pkgs.callPackage ./tests/detect-fixture-contract.nix {
                inherit stealth-detect;
              };
            }
            (lib.mkIf x86 {
              module-eval-nixos = inputs.std.lib.nixosModuleCheck {
                inherit (inputs) nixpkgs;
                inherit (pkgs.stdenv.hostPlatform) system;
                overlays = [ self.overlays.default ];
                module = ./module.nix;
                config.virtualisation.vfio-stealth.enable = true;
                config.virtualisation.vfio-stealth.cpuVendor = "amd";
                config.virtualisation.vfio-stealth.smbios.manufacturer = "ASUSTeK COMPUTER INC.";
                config.virtualisation.vfio-stealth.smbios.product = "ROG STRIX X670E-E GAMING WIFI";
                config.virtualisation.vfio-stealth.smbios.baseBoardSerial = "230820681900773";
                config.virtualisation.vfio-stealth.disk.serial = "S6B2NS0TB12345X";
                config.virtualisation.vfio-stealth.hypervVendorId = "AuthenticAMD";
                config.virtualisation.vfio-stealth.smbios.memory.manufacturer = "G.Skill";
                config.virtualisation.vfio-stealth.smbios.onboardDevices = [
                  {
                    designation = "Onboard Ethernet";
                    kind = "ethernet";
                    instance = 1;
                  }
                ];
              };

              sed-contract-qemu = pkgs.callPackage ./tests/sed-contract-qemu.nix {
                autovirt = ./vendor/autovirt;
                cpuVendor = "amd";
                qemu-stealth = self.packages.${pkgs.stdenv.hostPlatform.system}.default;
              };

              sed-contract-qemu-intel = pkgs.callPackage ./tests/sed-contract-qemu.nix {
                autovirt = ./vendor/autovirt;
                cpuVendor = "intel";
                qemu-stealth = self.packages.${pkgs.stdenv.hostPlatform.system}.qemu-stealth-intel;
              };

              sed-contract-edk2 = pkgs.callPackage ./tests/sed-contract-edk2.nix {
                autovirt = ./vendor/autovirt;
                cpuVendor = "amd";
              };

              sed-contract-edk2-intel = pkgs.callPackage ./tests/sed-contract-edk2.nix {
                autovirt = ./vendor/autovirt;
                cpuVendor = "intel";
              };

              autovirt-patch-contract = pkgs.callPackage ./tests/autovirt-patch-contract.nix { };

              qemu-ceiling-contract = pkgs.callPackage ./tests/ceiling-contract.nix { };
              update-gap-contract = pkgs.callPackage ./tests/update-gap-contract.nix { };

              # The catalog rotted once already: seven entries still named
              # qemu/package.nix after those seds moved into post-patch.nix, and
              # nothing noticed. Two invariants, both cheap, both silent until
              # something actually drifts.
              sed-catalog-lean =
                pkgs.runCommand "sed-catalog-lean"
                  {
                    catalog = ./docs/SED-CATALOG.md;
                    repo = self;
                  }
                  ''
                    bad=0

                    while IFS= read -r f; do
                      [ -n "$f" ] || continue
                      if [ ! -e "$repo/$f" ]; then
                        echo "::error::SED-CATALOG.md documents '$f', which does not exist. The edit moved; re-point the heading."
                        bad=1
                      elif ! grep -qE 'substituteInPlace|sed -i|awk |filterdiff' "$repo/$f"; then
                        echo "::error::SED-CATALOG.md documents '$f', but that file performs no text rewrite any more."
                        echo "This is how it rotted last time: the file still existed, the seds had moved out of it."
                        bad=1
                      fi
                    done < <(grep -oE '^## [a-zA-Z0-9_./-]+\.nix' "$catalog" | sed 's/^## //' | sort -u)

                    if grep -nE '\*\*(Anchor|Replacement|Tool|Guard):\*\*' "$catalog"; then
                      echo "::error::SED-CATALOG.md restates what post-patch.nix owns (lines above)."
                      echo "Those fields drift silently and the sed-contract checks already verify them. Delete them."
                      bad=1
                    fi

                    [ "$bad" = 0 ] || exit 1
                    echo "sed-catalog-lean: every documented file exists, and nothing the code owns is restated"
                    touch "$out"
                  '';

              options-documented = pkgs.callPackage ./tests/options-documented.nix { };

              kernel-postpatch-fits-cachyos = pkgs.callPackage ./tests/kernel-postpatch-fits.nix {
                sourceName = "cachyos-lto-latest";
                kernelSrc =
                  inputs.nix-cachyos-kernel.legacyPackages.x86_64-linux.linuxPackages-cachyos-latest-lto.kernel.src;
              };

              kernel-postpatch-fits-upstream = pkgs.callPackage ./tests/kernel-postpatch-fits.nix {
                sourceName = "upstream-latest";
                kernelSrc = pkgs.linux_latest.src;
              };

              kernel-kvm-compiles-cachyos = pkgs.callPackage ./tests/kernel-kvm-compiles.nix {
                sourceName = "cachyos-lto-latest";
                kernel =
                  inputs.nix-cachyos-kernel.legacyPackages.x86_64-linux.linuxPackages-cachyos-latest-lto.kernel;
              };

              kernel-kvm-compiles-upstream = pkgs.callPackage ./tests/kernel-kvm-compiles.nix {
                sourceName = "upstream-latest";
                kernel = pkgs.linux_latest;
              };

              lib-output-contract = pkgs.callPackage ./tests/lib-output-contract.nix {
                inherit (self.packages.${pkgs.stdenv.hostPlatform.system})
                  acpi-ssdt-stealth
                  smbios-stealth-tables
                  ;
              };

              boot-smoke = pkgs.testers.runNixOSTest {
                name = "qemu-stealth-boot-smoke";
                globalTimeout = 600;
                nodes.machine =
                  { lib, ... }:
                  {
                    environment.systemPackages = [ stealth-detect ];
                    virtualisation.qemu.package = lib.mkForce self.packages.${pkgs.stdenv.hostPlatform.system}.default;
                    # UEFI boot on Q35: the MCH revert (c730b41) fixed the
                    # OVMF PlatformPei ASSERT that originally forced SeaBIOS.
                    # Q35 is explicit because the test framework defaults to
                    # i440fx, which would skip the AutoVirt Q35 code paths.
                    virtualisation.useEFIBoot = true;
                    virtualisation.efi.OVMF =
                      lib.mkForce
                        (self.packages.${pkgs.stdenv.hostPlatform.system}.ovmf-stealth.override {
                          secureBoot = false;
                        }).fd;
                    virtualisation.qemu.options = [
                      "-machine"
                      "q35"
                    ];
                  };
                testScript = ''
                  import json

                  machine.wait_for_unit("multi-user.target", timeout=300)

                  status, out = machine.execute("stealth-detect --json")
                  print(out)
                  report = json.loads(out)
                  verdicts = {f["vector"]: f["verdict"] for f in report["findings"]}
                  evidence = {f["vector"]: f["evidence"] for f in report["findings"]}

                  # The guest is the proof. The sed contracts show the edit landed in
                  # QEMU's source; only a booted guest shows the result reached it.
                  if verdicts["acpi-oem"] != "clean":
                      raise Exception(
                          "ACPI OEM rewrite did not reach the guest: "
                          f"{verdicts['acpi-oem']}, {evidence['acpi-oem']}"
                      )
                  if "ALASKA" not in evidence["acpi-oem"]:
                      raise Exception(
                          "guest ACPI tables do not carry the configured OEM id: "
                          f"{evidence['acpi-oem']}"
                      )
                  if verdicts["pci-subsystem"] != "clean":
                      raise Exception(
                          "PCI subsystem id rewrite did not reach the guest: "
                          f"{verdicts['pci-subsystem']}, {evidence['pci-subsystem']}"
                      )
                '';
              };

              ovmf-sb-vars-exists =
                let
                  ovmf-sb = self.packages.${pkgs.stdenv.hostPlatform.system}.ovmf-stealth;
                in
                pkgs.runCommand "ovmf-sb-vars-exists" { } ''
                  varsMs="${ovmf-sb.fd}/FV/OVMF_VARS.ms.fd"
                  if [ ! -f "$varsMs" ]; then
                    echo "FAIL: OVMF_VARS.ms.fd absent — Secure Boot key enrollment did not complete"
                    echo "expected: $varsMs"
                    ls -la "${ovmf-sb.fd}/FV/" 2>/dev/null || echo "(FV dir missing)"
                    exit 1
                  fi
                  size=$(stat --format=%s "$varsMs")
                  echo "ovmf-sb-vars-exists: OVMF_VARS.ms.fd present ($size bytes)"
                  touch $out
                '';
            })
            (lib.mkIf arm {
              detect-finds-plain-virt = pkgs.callPackage ./tests/detect-finds-plain-virt.nix {
                inherit stealth-detect;
              };
            })
          ];
        };
    };
}
