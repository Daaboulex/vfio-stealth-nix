{
  lib,
  callPackage,
  runCommand,
  runtimeShell,
}:

let
  domain = {
    gpu = null;
    hostDevices = [ ];
    unmount = [ ];
    hugepages = false;
    memory = 1024;
    pinning = null;
    stopServices = [ ];
    iommu = false;
  };

  plan = import ../host/plan.nix {
    inherit lib;
    cfg = {
      host.protectedDisks = [
        "/"
        "/home"
      ];
      pinning.isolate = true;
      hugepages = {
        size = "2M";
        atBoot = false;
      };
      domains = {
        root-disk = domain // {
          hostDevices = [ "0000:01:00.0" ];
        };
        home-disk = domain // {
          hostDevices = [ "0000:02:00.0" ];
        };
        swap-disk = domain // {
          hostDevices = [ "0000:04:00.0" ];
        };
        games = domain // {
          hostDevices = [ "0000:03:00.0" ];
          unmount = [
            "/mnt/absent"
            "/mnt/games"
          ];
        };
        absent-only = domain // {
          unmount = [ "/mnt/absent" ];
          hugepages = true;
          memory = 1024;
        };
        missing-gpu = domain // {
          gpu = {
            address = "0000:09:00.0";
            audio = null;
            extraFunctions = [ ];
            binding = "hook";
            resizeBar2Mb = null;
            rebindOnStop = false;
          };
        };
        held-gpu = domain // {
          hostDevices = [ "0000:0a:00.0" ];
        };
        services = domain // {
          stopServices = [
            "fans.service"
            "idle.service"
          ];
        };
        grouped = domain // {
          iommu = true;
          hostDevices = [
            "0000:0b:00.0"
            "0000:0b:00.1"
          ];
        };
        pinned = domain // {
          pinning.vcpus = [
            2
            3
          ];
        };
      };
    };
  };

  hook = callPackage ../host/qemu-hook.nix { inherit plan; };
in
runCommand "qemu-hook" { } ''
  root=$TMPDIR/root
  sys=$root/sys
  proc=$root/proc
  pci=$sys/devices/pci0000:00
  mkdir -p $proc/self $proc/sys/vm $root/run $sys/dev/block $sys/class/block $sys/block
  mkdir -p $sys/kernel/mm/hugepages/hugepages-2048kB $sys/devices/system/cpu
  echo 0 > $sys/kernel/mm/hugepages/hugepages-2048kB/nr_hugepages
  touch $proc/sys/vm/drop_caches $proc/sys/vm/compact_memory
  echo 0-7 > $sys/devices/system/cpu/online

  disk() {
    local address=$1 name=$2 part=$3 id=$4
    local dir=$pci/0000:00:01.1/$address/nvme/''${name%n1}/$name/$part
    mkdir -p $dir
    ln -s ../../devices/pci0000:00/0000:00:01.1/$address/nvme/''${name%n1}/$name/$part $sys/class/block/$part
    ln -s ../../devices/pci0000:00/0000:00:01.1/$address/nvme/''${name%n1}/$name/$part $sys/dev/block/$id
  }
  disk 0000:01:00.0 nvme0n1 nvme0n1p2 259:2
  disk 0000:02:00.0 nvme1n1 nvme1n1p1 259:5
  disk 0000:03:00.0 nvme2n1 nvme2n1p1 259:8
  disk 0000:04:00.0 nvme3n1 nvme3n1p1 259:11
  mkdir -p $sys/devices/virtual/block/dm-0/slaves $sys/devices/virtual/block/dm-0/dm
  echo crypthome > $sys/devices/virtual/block/dm-0/dm/name
  ln -s ../../../../pci0000:00/0000:00:01.1/0000:02:00.0/nvme/nvme1/nvme1n1/nvme1n1p1 $sys/devices/virtual/block/dm-0/slaves/nvme1n1p1
  ln -s ../devices/virtual/block/dm-0 $sys/block/dm-0
  ln -s ../../devices/virtual/block/dm-0 $sys/dev/block/254:0

  cat > $proc/self/mountinfo <<'EOF'
  22 1 259:2 / / rw,relatime shared:1 - ext4 /dev/nvme0n1p2 rw
  30 22 0:40 / /home rw,relatime shared:2 - btrfs /dev/mapper/crypthome rw
  31 22 259:8 / /mnt/games rw,relatime shared:3 - ext4 /dev/nvme2n1p1 rw
  32 22 0:25 / /tmp rw shared:4 - tmpfs tmpfs rw
  EOF
  printf 'Filename\tType\tSize\tUsed\tPriority\n/dev/nvme3n1p1\tpartition\t8388604\t0\t-2\n' > $proc/swaps

  mkdir -p $sys/bus/pci/devices/0000:0a:00.0/drm/card7 $proc/4242/fd
  echo kwin_wayland > $proc/4242/comm
  ln -s /dev/dri/card7 $proc/4242/fd/3
  mkdir -p $sys/kernel/iommu_groups/9/devices $sys/bus/pci/devices/0000:0b:00.0 $sys/bus/pci/devices/0000:0b:00.1
  for function in 0000:0b:00.0 0000:0b:00.1; do
    ln -s ../../../bus/pci/devices/$function $sys/kernel/iommu_groups/9/devices/$function
    ln -s ../../../../kernel/iommu_groups/9 $sys/bus/pci/devices/$function/iommu_group
  done
  cat > $TMPDIR/systemctl <<EOF
  #!${runtimeShell}
  echo "\$*" >> $TMPDIR/systemctl.log
  if [ "\$1 \$3" = "is-active idle.service" ]; then
    exit 3
  fi
  EOF
  chmod +x $TMPDIR/systemctl

  run() {
    local status=0
    SYSTEMCTL=$TMPDIR/systemctl SYSFS_ROOT=$sys PROC_ROOT=$proc RUN_ROOT=$root/run ${lib.getExe hook} "$@" - 2> $TMPDIR/stderr || status=$?
    cat $TMPDIR/stderr
    return $status
  }

  refused() {
    local guest=$1 fragment=$2
    if run "$guest" prepare begin; then
      echo "qemu-hook: $guest started although it should be refused for: $fragment"
      exit 1
    fi
    if ! grep -qF -- "$fragment" $TMPDIR/stderr; then
      echo "qemu-hook: $guest was refused, but not for: $fragment"
      exit 1
    fi
  }

  refused root-disk "0000:01:00.0 holds /, which the host needs"
  refused home-disk "0000:02:00.0 holds /home, which the host needs"
  refused swap-disk "0000:04:00.0 holds swap on /dev/nvme3n1p1, which the host needs"
  refused games "cannot unmount /mnt/games"
  grep -qF "/mnt/absent is not mounted" $TMPDIR/stderr
  refused missing-gpu "the GPU function 0000:09:00.0 is not present"

  if ! run absent-only prepare begin; then
    echo "qemu-hook: absent-only, whose unmount list names only a path that is not mounted, was refused"
    exit 1
  fi
  grep -qF "/mnt/absent is not mounted" $TMPDIR/stderr
  if [ "$(cat $sys/kernel/mm/hugepages/hugepages-2048kB/nr_hugepages)" != 512 ]; then
    echo "qemu-hook: the pool does not hold the 512 pages of 2 MiB absent-only asked for"
    exit 1
  fi
  run absent-only release end
  if [ "$(cat $sys/kernel/mm/hugepages/hugepages-2048kB/nr_hugepages)" != 0 ] || [ -e $root/run/vfio-stealth/absent-only.pages ]; then
    echo "qemu-hook: release did not give the 512 pages back"
    exit 1
  fi

  refused held-gpu "4242 (kwin_wayland)"
  refused grouped "0000:0b:00.0 and 0000:0b:00.1 share IOMMU group 9"

  : > $TMPDIR/systemctl.log
  if ! run services prepare begin; then
    echo "qemu-hook: services was refused"
    exit 1
  fi
  run services release end
  expected=$(printf '%s\n' "is-active --quiet fans.service" "stop fans.service" "is-active --quiet idle.service" "start fans.service")
  if [ "$(cat $TMPDIR/systemctl.log)" != "$expected" ]; then
    echo "qemu-hook: stopServices should stop the running fans.service, leave the stopped idle.service alone and start only fans.service again; systemctl saw:"
    cat $TMPDIR/systemctl.log
    exit 1
  fi

  echo other > $root/run/vfio-stealth/isolating
  refused pinned "other holds the host's CPUs"

  if ! run not-declared prepare begin; then
    echo "qemu-hook: a domain the plan does not name was refused"
    exit 1
  fi

  touch $out
''
