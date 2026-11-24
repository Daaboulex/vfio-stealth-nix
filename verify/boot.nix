{
  lib,
  pkgs,
  stdenv,
  runCommand,
  writeText,
  writeScript,
  cfg,
  nixvirt,
  swtpm,
  libvirt,
  linuxPackages,
  makeModulesClosure,
  makeInitrd,
  busybox,
  dmidecode,
  cpuid,
  pciutils,
  tpm2-tools,
  systemd,
  systemdMinimal,
  systemdUkify,
  dosfstools,
  mtools,
  util-linux,
  xorriso,
  openssl,
  sbsigntool,
  python3,
  python3Packages,
}:

let
  inherit (cfg.packages) ovmf;
  inherit (linuxPackages) kernel;

  helper = stdenv.mkDerivation {
    name = "probe-helper";
    src = ./probe-helper.c;
    dontUnpack = true;
    buildPhase = "$CC -O2 -Wall -Werror -o probe-helper $src";
    installPhase = "install -Dm755 probe-helper $out/bin/probe-helper";
  };

  vmaware = pkgs.callPackage ./vmaware.nix { };

  guestModules = [
    "ahci"
    "sd_mod"
    "sr_mod"
    "virtio_pci"
    "virtio_blk"
    "efivarfs"
    "battery"
    "ac"
    "fan"
    "thermal"
    "button"
    "bochs"
    "e1000e"
    "realtek"
    "r8169"
    "snd_hda_codec_generic"
    "snd_hda_codec_realtek"
    "snd_hda_codec_realtek_lib"
    "snd_hda_codec_alc260"
    "snd_hda_codec_alc262"
    "snd_hda_codec_alc268"
    "snd_hda_codec_alc269"
    "snd_hda_codec_alc662"
    "snd_hda_codec_alc680"
    "snd_hda_codec_alc861"
    "snd_hda_codec_alc861vd"
    "snd_hda_codec_alc880"
    "snd_hda_codec_alc882"
    "snd_hda_intel"
    "xhci_pci"
    "msr"
  ];

  modules = makeModulesClosure {
    kernel = kernel.modules or kernel;
    firmware = runCommand "no-firmware" { } "mkdir -p $out/lib/firmware";
    rootModules = guestModules;
    allowMissing = true;
  };

  init = writeScript "probe-init" ''
    #!${busybox}/bin/sh
    export PATH=${
      lib.makeBinPath [
        pciutils
        dmidecode
        cpuid
        tpm2-tools
        helper
        vmaware
        systemdMinimal
        busybox
      ]
    }
    mkdir -p /tmp
    mount -t proc proc /proc
    mount -t sysfs sysfs /sys
    mount -t devtmpfs devtmpfs /dev
    for module in ${lib.concatStringsSep " " guestModules}; do
      modprobe "$module" || echo "VFIO-PROBE-MODULE-MISSING $module"
    done
    mount -t efivarfs efivarfs /sys/firmware/efi/efivars || echo "VFIO-PROBE-EFIVARFS-FAILED"
    for d in /sys/bus/pci/devices/*; do
      if [ "$(cat "$d/class")" = 0x030000 ] && [ "$(cat "$d/vendor")" != 0x1b36 ]; then
        echo "$(cut -c3- "$d/vendor") $(cut -c3- "$d/device")" > /sys/bus/pci/drivers/bochs-drm/new_id
      fi
    done
    sleep 3
    section() {
      name=$1
      shift
      echo "VFIO-PROBE-BEGIN $name"
      "$@" 2>&1
      echo "VFIO-PROBE-END $name $?"
    }
    section cmdline cat /proc/cmdline
    section cpuid cpuid -r -1
    section cpuid-latency probe-helper cpuid-latency
    section fw-cfg probe-helper fw-cfg
    section cpuinfo cat /proc/cpuinfo
    section dmidecode dmidecode
    section smbios-raw sh -c 'dmidecode -q --dump-bin /tmp/smbios.bin > /dev/null && od -A n -t x1 -v /tmp/smbios.bin'
    section pci lspci -nnvmmk
    section pci-bars sh -c 'for d in /sys/bus/pci/devices/*; do echo "$(basename "$d") $(cat "$d/class") $(head -n 1 "$d/resource")"; done'
    section acpi-tables sh -c 'for t in /sys/firmware/acpi/tables/*; do if [ -f "$t" ]; then echo "$(basename "$t") $(od -A n -t x1 -N 36 -v "$t" | tr -d "\n")"; fi; done'
    section facp od -A n -t x1 -v /sys/firmware/acpi/tables/FACP
    section acpi-devices sh -c 'for d in /sys/bus/acpi/devices/*; do if [ -f "$d/path" ]; then uid=-; if [ -f "$d/uid" ]; then uid=$(cat "$d/uid"); fi; echo "$(basename "$d") $(cat "$d/path") $uid"; fi; done'
    section instructions probe-helper instructions
    section tcg-log sh -c 'mount -t securityfs securityfs /sys/kernel/security && od -A n -t x1 -v /sys/kernel/security/tpm0/binary_bios_measurements'
    section power-supply ls /sys/class/power_supply
    section battery sh -c 'for b in /sys/class/power_supply/*; do if [ -f "$b/serial_number" ]; then echo "$(basename "$b") $(cat "$b/serial_number")"; fi; done'
    section thermal sh -c 'for z in /sys/class/thermal/thermal_zone*; do echo "$(cat "$z/type") $(cat "$z/temp")"; done'
    section edid sh -c 'for e in /sys/class/drm/*/edid; do echo "$e $(od -A n -t x1 -v "$e" | tr -d "\n")"; done'
    section ata sh -c 'for d in /sys/class/ata_device/*; do echo "$(basename "$d") $(tr "\n" " " < "$d/id")"; done; for b in /sys/block/*; do echo "$(basename "$b") $(readlink -f "$b/device")"; done'
    section scsi sh -c 'for b in /sys/block/*; do if [ -f "$b/device/vendor" ]; then echo "$(basename "$b")|$(cat "$b/device/vendor")|$(cat "$b/device/model")|$(cat "$b/device/rev")"; fi; done'
    section tpm tpm2_getcap -T device:/dev/tpmrm0 properties-fixed
    section tpm-ek-read tpm2_nvread -T device:/dev/tpmrm0 -o /tmp/ek.der 0x01c00002
    section tpm-ek-cert od -A n -t x1 -v /tmp/ek.der
    section tpm-platform-read tpm2_nvread -T device:/dev/tpmrm0 -o /tmp/platform.der 0x01c08000
    section tpm-platform-cert od -A n -t x1 -v /tmp/platform.der
    section clock cat /sys/devices/system/clocksource/clocksource0/available_clocksource /sys/devices/system/clocksource/clocksource0/current_clocksource
    section iomem cat /proc/iomem
    section net sh -c 'for n in /sys/class/net/*; do driver=none; if [ -e "$n/device/driver" ]; then driver=$(basename "$(readlink -f "$n/device/driver")"); fi; echo "$(basename "$n") $(cat "$n/address") $driver"; done'
    section usb sh -c 'value() { if [ -f "$1" ]; then cat "$1"; fi; }; for d in /sys/bus/usb/devices/*; do if [ -f "$d/idVendor" ]; then echo "$(basename "$d")|$(cat "$d/idVendor")|$(cat "$d/idProduct")|$(value "$d/manufacturer")|$(value "$d/product")|$(value "$d/serial")"; fi; done'
    section hda sh -c 'for c in /sys/bus/hdaudio/devices/*; do if [ -f "$c/vendor_id" ]; then driver=none; if [ -e "$c/driver" ]; then driver=$(basename "$(readlink -f "$c/driver")"); fi; echo "$(basename "$c") $(cat "$c/vendor_id") $(cat "$c/subsystem_id") $driver"; fi; done'
    section secure-boot od -A n -t x1 -v /sys/firmware/efi/efivars/SecureBoot-8be4df61-93ca-11d2-aa0d-00e098032b8c
    mkdir -p /bin /usr/sbin /usr/bin
    ln -s ${busybox}/bin/sh /bin/sh
    ln -s ${busybox}/bin/dmesg /bin/dmesg
    ln -s ${dmidecode}/bin/dmidecode /usr/sbin/dmidecode
    ln -s ${systemdMinimal}/bin/systemd-detect-virt /usr/bin/systemd-detect-virt
    section detect-virt systemd-detect-virt
    section vmaware sh -c 'vmaware --json --output /tmp/vmaware.json && cat /tmp/vmaware.json'
    section dmesg dmesg
    echo VFIO-PROBE-DONE
    poweroff -f
  '';

  initrd = makeInitrd {
    name = "probe-initrd";
    compressor = "zstd";
    contents = [
      {
        object = init;
        symlink = "/init";
      }
      {
        object = "${modules}/lib/modules";
        symlink = "/lib/modules";
      }
    ];
  };

  probe =
    runCommand "boot-probe"
      {
        nativeBuildInputs = [
          systemdUkify
          dosfstools
          mtools
          util-linux
          xorriso
          openssl
          sbsigntool
          python3Packages.virt-firmware
        ];
      }
      ''
        mkdir -p $out iso
        uki() {
          ukify build \
            --linux=${kernel}/bzImage \
            --initrd=${initrd}/initrd \
            --stub=${systemd}/lib/systemd/boot/efi/linuxx64.efi.stub \
            --cmdline="console=ttyS0 panic=0 no_timer_check probe=$1" \
            --os-release="ID=boot-probe" \
            --output="$2"
        }
        disk() {
          rm -f esp.img
          truncate -s 200M esp.img
          mkfs.vfat -F 32 -n PROBE esp.img
          mmd -i esp.img ::/EFI ::/EFI/BOOT
          mcopy -i esp.img "$1" ::/EFI/BOOT/BOOTX64.EFI
          truncate -s 256M "$2"
          echo 'start=2048, size=409600, type=uefi' | sfdisk --label gpt "$2"
          dd if=esp.img of="$2" bs=512 seek=2048 conv=notrunc,sparse status=none
        }
        uki unsigned unsigned.efi
        uki signed signed-plain.efi
        for key in pk kek db; do
          openssl req -new -x509 -newkey rsa:2048 -nodes -days 3650 \
            -subj "/CN=boot-probe test $key/" -keyout $key.key -out $key.crt
        done
        sbsign --key db.key --cert db.crt --output signed.efi signed-plain.efi
        disk signed.efi $out/signed.img
        disk unsigned.efi $out/unsigned.img
        cp esp.img iso/esp.img
        xorriso -as mkisofs -R -J -e esp.img -no-emul-boot -o $out/unsigned.iso iso
        owner=6b0a1f52-6c3e-4d8a-9a51-2f6f2c1b7e01
        virt-fw-vars -i ${ovmf.fd}/FV/OVMF_VARS.fd -o $out/own-keys-vars.fd \
          --set-pk $owner pk.crt --add-kek $owner kek.crt --add-db $owner db.crt --sb
        virt-fw-vars -i ${cfg.packages.secureBootVars} -v -p > $out/microsoft-vars.txt
      '';

  render = import ./domain-xml.nix {
    inherit
      lib
      pkgs
      writeText
      cfg
      nixvirt
      ;
  };

  cases = [
    {
      name = "sata-disk";
      domain = {
        disks = [ { source = "/probe/unsigned.img"; } ];
        tpm = true;
        network = {
          type = "network";
          source = "default";
          model = "e1000e";
        };
      };
      expect = {
        kernel = "unsigned";
        secureBoot = false;
        full = true;
      };
    }
    {
      name = "virtio-disk";
      domain = {
        disks = [
          {
            source = "/probe/unsigned.img";
            bus = "virtio";
          }
          {
            source = "/probe/unsigned.iso";
            bus = "usb";
          }
        ];
        network = {
          type = "network";
          source = "default";
          model = "rtl8125";
        };
        extra.devices = {
          sound = [
            {
              model = "ich9";
              codec.type = "duplex";
            }
          ];
          input =
            map
              (type: {
                inherit type;
                bus = "usb";
              })
              [
                "keyboard"
                "mouse"
                "tablet"
              ];
          hub = [ { type = "usb"; } ];
          serial = [
            {
              type = "null";
              target.type = "usb-serial";
            }
          ];
        };
      };
      expect = {
        kernel = "unsigned";
        secureBoot = false;
        devices = true;
      };
    }
    {
      name = "sata-cdrom";
      domain.cdroms = [ "/probe/unsigned.iso" ];
      expect = {
        kernel = "unsigned";
        secureBoot = false;
      };
    }
    {
      name = "smbios-emulate";
      domain = {
        disks = [ { source = "/probe/unsigned.img"; } ];
        extra.os.smbios.mode = "emulate";
      };
      expect = {
        kernel = "unsigned";
        secureBoot = false;
      };
    }
    {
      name = "viommu";
      domain = {
        disks = [ { source = "/probe/unsigned.img"; } ];
        iommu = true;
      };
      expect = {
        kernel = "unsigned";
        secureBoot = false;
        vmaware = lib.optional (cfg.cpuVendor == "intel") "FIRMWARE";
      };
    }
    {
      name = "qxl-video";
      domain = {
        disks = [ { source = "/probe/unsigned.img"; } ];
        extra.devices.video.model.type = "qxl";
      };
      expect = {
        kernel = "unsigned";
        secureBoot = false;
      };
    }
    {
      name = "secure-boot-microsoft";
      domain = {
        disks = [ { source = "/probe/unsigned.img"; } ];
        secureBoot = true;
      };
      expect.refused = true;
    }
    {
      name = "secure-boot-own-keys";
      domain = {
        disks = [
          { source = "/probe/unsigned.img"; }
          { source = "/probe/signed.img"; }
        ];
        secureBoot = true;
        extra.os.nvram.template = "/probe/own-keys-vars.fd";
      };
      expect = {
        kernel = "signed";
        secureBoot = true;
        refusedFirst = true;
      };
    }
  ];

  inherit (cfg.domain.sysinfo) bios system baseBoard;
  identity = import ../identity.nix { inherit lib; };
  derivedSerial = identity.domainSerial cfg.identity.seed;
  serialsOf =
    name:
    if cfg.smbios.perDomainSerials then
      {
        system = derivedSerial name "system";
        baseboard = derivedSerial name "baseboard";
      }
    else
      {
        system = entry system.entry "serial";
        baseboard = entry baseBoard.entry "serial";
      };
  entry = section: key: (lib.findFirst (e: e.name == key) { value = null; } section).value;

  plan = writeText "boot-check.json" (
    builtins.toJSON {
      inherit probe;
      vmawareExpected = ./vmaware-expected.json;
      swtpm = "${swtpm}";
      cases = map (
        c:
        c
        // {
          xml = render c.name c.domain;
          serials = serialsOf c.name;
        }
      ) cases;
      config = {
        platformKeyName = cfg.secureBoot.platformKeyName;
        inherit (cfg)
          cpuVendor
          hypervMode
          hypervVendorId
          aperfMperf
          macPrefix
          pciMmio64Mb
          pciSubsystem
          hdaCodec
          ;
        inherit (cfg.packages.qemu) xhciRegisterWindow;
        board = {
          biosVendor = entry bios.entry "vendor";
          biosVersion = entry bios.entry "version";
          biosDate = entry bios.entry "date";
          manufacturer = entry system.entry "manufacturer";
          product = entry system.entry "product";
          systemSerial = entry system.entry "serial";
          boardVersion = entry baseBoard.entry "version";
        };
        memory = {
          inherit (cfg.smbios.memory)
            manufacturer
            partNumber
            speed
            maxCapacityGb
            typeDetail
            rank
            voltageMillivolts
            errorCorrection
            ;
          type = (import ../smbios/memory-types.nix).${cfg.smbios.memory.type};
          slots = identity.memorySlots cfg.identity.seed cfg.smbios.memory.slots;
        };
        system = {
          version = cfg.smbios.systemVersion;
          sku = cfg.smbios.systemSku;
          family = cfg.smbios.systemFamily;
        };
        chassis = {
          type = cfg.smbios.chassisType;
          version = cfg.smbios.chassisVersion;
          serial = cfg.smbios.chassisSerial;
          asset = cfg.smbios.chassisAsset;
          sku = cfg.smbios.chassisSku;
        };
        inherit (cfg.domain) processor;
        inherit (cfg.packages.smbiosTables) cacheHandles;
        inherit (cfg.smbios)
          cache
          ports
          systemSlots
          perDomainSerials
          ;
        inherit (cfg.smbios) oemStrings onboardDevices;
        inherit (cfg)
          acpi
          acpiOem
          acpiSsdt
          disk
          edid
          tpm
          ;
        deviceIdentities = cfg.devices;
        hypervEnabled = cfg.domain.features ? hyperv;
      };
    }
  );
in
runCommand "vfio-stealth-boot-check-${cfg.cpuVendor}-${cfg.hypervMode}"
  {
    nativeBuildInputs = [
      python3
      libvirt
      swtpm
      openssl
      python3Packages.virt-firmware
    ];
    requiredSystemFeatures = [ "kvm" ];
  }
  ''
    export HOME=$TMPDIR XDG_RUNTIME_DIR=$TMPDIR/run XDG_CONFIG_HOME=$TMPDIR/config XDG_CACHE_HOME=$TMPDIR/cache
    mkdir -p $XDG_RUNTIME_DIR
    python3 ${./boot.py} ${plan} $out
  ''
