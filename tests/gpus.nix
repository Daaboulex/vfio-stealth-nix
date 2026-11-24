{
  runCommand,
  bash,
  coreutils,
  diffutils,
}:

runCommand "gpus"
  {
    nativeBuildInputs = [
      bash
      coreutils
      diffutils
    ];
  }
  ''
    sys=$TMPDIR/sys
    devices=$sys/bus/pci/devices
    groups=$sys/kernel/iommu_groups
    mkdir -p $sys/bus/pci/drivers/nouveau $TMPDIR/bin

    device() {
      mkdir -p "$devices/$1"
      echo "$2" > "$devices/$1/class"
      echo "0x''${3%%:*}" > "$devices/$1/vendor"
      echo "0x''${3##*:}" > "$devices/$1/device"
      if [ -n "$4" ]; then
        mkdir -p "$groups/$4/devices"
        ln -s "$groups/$4" "$devices/$1/iommu_group"
        ln -s "$devices/$1" "$groups/$4/devices/$1"
      fi
    }

    device 0000:00:01.1 0x060400 1022:14db 14
    device 0000:01:00.0 0x030000 10de:2484 14
    device 0000:01:00.1 0x040300 10de:228b 14
    device 0000:01:00.2 0x0c0330 10de:1ad8 14
    echo 1 > "$devices/0000:01:00.0/boot_vga"
    ln -s $sys/bus/pci/drivers/nouveau "$devices/0000:01:00.0/driver"
    device 0000:0a:00.0 0x030000 1002:73bf 20
    device 0000:0a:00.1 0x040300 1002:ab28 20
    device 0000:0b:00.0 0x0c0330 1022:15b6 20
    device 0000:0c:00.0 0x030000 8086:a780 ""

    cat > $TMPDIR/bin/lspci <<'STUB'
    #!${bash}/bin/bash
    echo "$3 Example device"
    STUB
    chmod +x $TMPDIR/bin/lspci

    PATH=$TMPDIR/bin:$PATH SYSFS_ROOT=$sys bash -euo pipefail ${../host/gpus.sh} > $TMPDIR/out
    cat $TMPDIR/out

    expected() {
      if ! grep -qF -- "$1" $TMPDIR/out; then
        echo "gpus: the output lacks: $1"
        exit 1
      fi
    }

    sed -n '/^0000:01:00.0/,/^0000:0a:00.0/p' $TMPDIR/out | sed -n '/gpu = {/,/};/p' > $TMPDIR/block
    cat > $TMPDIR/want <<'WANT'
        gpu = {
          address = "0000:01:00.0";
          audio = "0000:01:00.1";
          extraFunctions = [ "0000:01:00.2" ];
          ids = [ "10de:2484" "10de:228b" "10de:1ad8" ];
        };
    WANT
    if ! diff -u $TMPDIR/want $TMPDIR/block; then
      echo "gpus: the clean card's settings differ from what the module takes"
      exit 1
    fi
    expected "id 10de:2484, driver nouveau"
    expected "Your firmware shows its picture on this card."
    expected "The group also holds 0000:0b:00.0, which would leave the host with the card."
    expected "No IOMMU group: the IOMMU is off."
    if [ "$(grep -c 'gpu = {' $TMPDIR/out)" != 1 ]; then
      echo "gpus: only the card with a clean group should get settings"
      exit 1
    fi
    echo "gpus: the finder reads every case right"
    touch $out
  ''
