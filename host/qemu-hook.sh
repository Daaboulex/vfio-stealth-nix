guest=$1
operation=$2
phase=$3

sysfs=${SYSFS_ROOT:-/sys}
proc=${PROC_ROOT:-/proc}
state=${RUN_ROOT:-/run}/vfio-stealth

log() {
  printf 'vfio-stealth hook, %s: %s\n' "$guest" "$*" >&2
}

refuse() {
  log "refusing to start: $*"
  exit 1
}

plan=$(<"$VFIO_STEALTH_PLAN")
domain=$(jq -c --arg guest "$guest" '.domains[$guest]' <<<"$plan")
if [ "$domain" = null ]; then
  exit 0
fi

read_list() {
  local text
  text=$(jq -r "$1 | .[]" <<<"$2")
  list=()
  if [ -n "$text" ]; then
    mapfile -t list <<<"$text"
  fi
}

read_list .protectedDisks "$plan"
protected_disks=("${list[@]}")
read_list .devices "$domain"
devices=("${list[@]}")
read_list .unmount "$domain"
unmount=("${list[@]}")
read_list .vcpus "$domain"
vcpus=("${list[@]}")
read_list .stopServices "$domain"
stop_services=("${list[@]}")
iommu=$(jq -r .iommu <<<"$domain")
systemctl=${SYSTEMCTL:-systemctl}
pages=$(jq -r .hugepages <<<"$domain")
page_kb=$(jq -r .hugepages.pageKb <<<"$plan")
at_boot=$(jq -r .hugepages.atBoot <<<"$plan")
isolate=$(jq -r .isolate <<<"$plan")
gpu=$(jq -c .gpu <<<"$domain")
pool=$sysfs/kernel/mm/hugepages/hugepages-${page_kb}kB
lock=$state/isolating
isolated=0
failed=0

load_mounts() {
  local line head rest
  local -a fields others
  mount_ids=()
  mount_types=()
  mount_sources=()
  mount_points=()
  while IFS= read -r line; do
    head=${line%% - *}
    rest=${line#* - }
    read -r -a fields <<<"$head"
    read -r -a others <<<"$rest"
    mount_ids+=("${fields[2]}")
    mount_types+=("${others[0]}")
    mount_sources+=("${others[1]}")
    mount_points+=("$(printf '%b' "${fields[4]}")")
  done <"$proc/self/mountinfo"
}

containing_mount() {
  local path=$1 index point length=-1
  found=-1
  for index in "${!mount_points[@]}"; do
    point=${mount_points[index]}
    if [ "$point" = / ] || [ "$path" = "$point" ] || [ "${path#"$point"/}" != "$path" ]; then
      if [ "${#point}" -ge "$length" ]; then
        found=$index
        length=${#point}
      fi
    fi
  done
}

walk_block() {
  local slave
  blocks+=("$1")
  for slave in "$1"/slaves/*; do
    if [ -e "$slave" ]; then
      walk_block "$(readlink -f "$slave")"
    fi
  done
}

block_devices() {
  local id=$1 source=$2 dir="" candidate
  blocks=()
  if [ "${id%%:*}" != 0 ] && [ -e "$sysfs/dev/block/$id" ]; then
    dir=$sysfs/dev/block/$id
  elif [ "${source#/dev/mapper/}" != "$source" ]; then
    for candidate in "$sysfs"/block/dm-*; do
      if [ -f "$candidate/dm/name" ] && [ "$(<"$candidate/dm/name")" = "${source#/dev/mapper/}" ]; then
        dir=$candidate
      fi
    done
  elif [ "${source#/dev/}" != "$source" ] && [ -e "$sysfs/class/block/${source#/dev/}" ]; then
    dir=$sysfs/class/block/${source#/dev/}
  fi
  if [ -z "$dir" ]; then
    return 1
  fi
  walk_block "$(readlink -f "$dir")"
}

mount_devices() {
  blocks=()
  case "${mount_types[$1]}" in
  tmpfs | ramfs) return 0 ;;
  esac
  block_devices "${mount_ids[$1]}" "${mount_sources[$1]}"
}

sits_on() {
  local path
  for path in "${blocks[@]}"; do
    case "$path/" in
    *"/$1/"*) return 0 ;;
    esac
  done
  return 1
}

guard() {
  local path device swap kind index
  local -a held=() labels=()
  for path in "${protected_disks[@]}"; do
    containing_mount "$path"
    if [ "$found" -lt 0 ]; then
      refuse "no mounted filesystem holds the protected path $path"
    fi
    if ! mount_devices "$found"; then
      refuse "cannot resolve ${mount_sources[found]}, which holds the protected path $path, to a block device"
    fi
    for index in "${!blocks[@]}"; do
      held+=("${blocks[index]}")
      labels+=("$path")
    done
  done
  {
    if read -r _; then
      while read -r swap kind _; do
        if [ "$kind" = file ]; then
          containing_mount "$swap"
          if [ "$found" -lt 0 ] || ! mount_devices "$found"; then
            refuse "cannot resolve the swap file $swap to a block device"
          fi
        elif ! block_devices 0:0 "$swap"; then
          refuse "cannot resolve the swap device $swap to a block device"
        fi
        for index in "${!blocks[@]}"; do
          held+=("${blocks[index]}")
          labels+=("swap on $swap")
        done
      done
    fi
  } <"$proc/swaps"
  for device in "${devices[@]}"; do
    for index in "${!held[@]}"; do
      case "${held[index]}/" in
      *"/$device/"*) refuse "$device holds ${labels[index]}, which the host needs" ;;
      esac
    done
  done
}

cpu_list() {
  local part
  local -a parts
  IFS=, read -r -a parts <<<"$1"
  for part in "${parts[@]}"; do
    seq "${part%-*}" "${part#*-}"
  done
}

restore_cpus() {
  local unit online
  online=$(<"$sysfs/devices/system/cpu/online")
  for unit in system.slice user.slice init.scope; do
    if ! systemctl set-property --runtime -- "$unit" "AllowedCPUs=$online"; then
      log "could not give $unit back the CPUs $online"
      failed=1
    fi
  done
  if ! rm -f "$lock"; then
    failed=1
  fi
}

give_back_pages() {
  local taken current
  if [ ! -f "$state/$guest.pages" ]; then
    return 0
  fi
  taken=$(<"$state/$guest.pages")
  current=$(<"$pool/nr_hugepages")
  if [ "$current" -gt "$taken" ]; then
    current=$((current - taken))
  else
    current=0
  fi
  if ! echo "$current" >"$pool/nr_hugepages"; then
    log "could not shrink the huge page pool to $current"
    failed=1
  fi
  if ! rm -f "$state/$guest.pages"; then
    failed=1
  fi
}

remount() {
  local path
  if [ ! -f "$state/$guest.unmounted" ]; then
    return 0
  fi
  while IFS= read -r path; do
    if ! mount -- "$path"; then
      log "could not mount $path again; mount it by hand"
      failed=1
    fi
  done <"$state/$guest.unmounted"
  if ! rm -f "$state/$guest.unmounted"; then
    failed=1
  fi
}

stop_listed_services() {
  local unit
  : >"$state/$guest.services"
  for unit in "${stop_services[@]}"; do
    if ! "$systemctl" is-active --quiet "$unit"; then
      continue
    fi
    if ! "$systemctl" stop "$unit"; then
      refuse "cannot stop $unit, which stopServices names"
    fi
    echo "$unit" >>"$state/$guest.services"
    log "stopped $unit"
  done
}

start_listed_services() {
  local unit
  if [ ! -f "$state/$guest.services" ]; then
    return
  fi
  while read -r unit; do
    if ! "$systemctl" start "$unit"; then
      log "could not start $unit again"
      failed=1
    fi
  done <"$state/$guest.services"
  rm -f "$state/$guest.services"
}

device_files() {
  local device=$1 node
  for node in "$sysfs/bus/pci/devices/$device"/drm/card* "$sysfs/bus/pci/devices/$device"/drm/renderD*; do
    if [ -e "$node" ]; then
      echo "/dev/dri/${node##*/}"
    fi
  done
  if [ "$(driver_of "$sysfs/bus/pci/devices/$device")" = nvidia ]; then
    echo "/dev/nvidia"
  fi
}

check_holders() {
  local device file process descriptor target holders=""
  local -a files=()
  for device in "${devices[@]}"; do
    while read -r file; do
      [ -n "$file" ] && files+=("$file")
    done < <(device_files "$device")
  done
  if [ "${#files[@]}" -eq 0 ]; then
    return
  fi
  for process in "$proc"/[0-9]*; do
    for descriptor in "$process"/fd/*; do
      target=$(readlink "$descriptor") || continue
      for file in "${files[@]}"; do
        if [ "$target" = "$file" ] || { [ "$file" = /dev/nvidia ] && [[ "$target" == /dev/nvidia* ]]; }; then
          holders+=" ${process##*/} ($(<"$process/comm"))"
          break 2
        fi
      done
    done
  done
  if [ -n "$holders" ]; then
    refuse "these processes have a passed-through device open, and taking it from its driver would wait for them:$holders; close them or name their services in stopServices"
  fi
}

check_iommu_groups() {
  local device member group
  for device in "${devices[@]}"; do
    group=$sysfs/bus/pci/devices/$device/iommu_group
    for member in "$group"/devices/*; do
      member=${member##*/}
      if [ "$member" != "$device" ] && [[ " ${devices[*]} " == *" $member "* ]]; then
        refuse "$device and $member share IOMMU group $(basename "$(readlink "$group")"), and the VM's own IOMMU gives each passed-through device an address space of its own; turn iommu off for this domain, or pass one device of the group"
      fi
    done
  done
}

undo() {
  start_listed_services
  give_back_pages
  remount
  if [ "$isolated" = 1 ]; then
    restore_cpus
  fi
}

unmount_listed() {
  local path point output present
  for path in "${unmount[@]}"; do
    present=0
    for point in "${mount_points[@]}"; do
      if [ "$point" = "$path" ]; then
        present=1
      fi
    done
    if [ "$present" = 0 ]; then
      log "$path is not mounted"
      continue
    fi
    if ! output=$(umount -- "$path" 2>&1); then
      refuse "cannot unmount $path: $output"
    fi
    printf '%s\n' "$path" >>"$state/$guest.unmounted"
    log "unmounted $path"
  done
}

unmount_devices() {
  local index device output
  load_mounts
  for ((index = ${#mount_points[@]} - 1; index >= 0; index--)); do
    if ! mount_devices "$index"; then
      continue
    fi
    for device in "${devices[@]}"; do
      if sits_on "$device"; then
        if ! output=$(umount -- "${mount_points[index]}" 2>&1); then
          refuse "cannot unmount ${mount_points[index]}, which sits on $device: $output"
        fi
        log "unmounted ${mount_points[index]}, which sits on $device"
      fi
    done
  done
}

allocate_pages() {
  local current want got
  if [ "$at_boot" = true ]; then
    got=$(<"$pool/free_hugepages")
    if [ "$got" -lt "$pages" ]; then
      refuse "needs $pages huge pages of $page_kb kB and the pool reserved at boot has $got free"
    fi
    return 0
  fi
  current=$(<"$pool/nr_hugepages")
  want=$((current + pages))
  echo 3 >"$proc/sys/vm/drop_caches"
  echo 1 >"$proc/sys/vm/compact_memory"
  echo "$want" >"$pool/nr_hugepages"
  got=$(<"$pool/nr_hugepages")
  if [ "$got" -lt "$want" ]; then
    if ! echo "$current" >"$pool/nr_hugepages"; then
      log "could not shrink the huge page pool back to $current"
    fi
    refuse "the kernel found $((got - current)) of $pages huge pages of $page_kb kB; free memory, or reserve them at boot with hugepages.atBoot"
  fi
  echo "$pages" >"$state/$guest.pages"
  log "added $pages huge pages of $page_kb kB to the pool"
}

driver_of() {
  if [ -L "$1/driver" ]; then
    basename "$(readlink "$1/driver")"
  fi
}

bind_gpu() {
  local device path current bound mask bit index
  local -a functions
  read_list .functions "$gpu"
  functions=("${list[@]}")
  bit=$(jq -r .resizeBar2 <<<"$gpu")
  if [ "$bit" != null ]; then
    path=$sysfs/bus/pci/devices/${functions[0]}
    if [ -L "$path/driver" ] && ! echo "${functions[0]}" >"$path/driver/unbind"; then
      refuse "cannot unbind ${functions[0]} from its driver to resize BAR 2"
    fi
    mask=$(<"$path/resource2_resize")
    if [[ ! $mask =~ ^[0-9a-fA-F]+$ ]] || (((16#$mask >> bit & 1) == 0)); then
      refuse "${functions[0]} does not offer a BAR 2 of $((1 << bit)) MiB; resource2_resize reads $mask"
    fi
    if ! echo "$bit" >"$path/resource2_resize"; then
      refuse "cannot resize BAR 2 of ${functions[0]} to $((1 << bit)) MiB"
    fi
    log "resized BAR 2 of ${functions[0]} to $((1 << bit)) MiB"
  fi
  for ((index = ${#functions[@]} - 1; index >= 0; index--)); do
    device=${functions[index]}
    path=$sysfs/bus/pci/devices/$device
    if [ ! -e "$path" ]; then
      refuse "the GPU function $device is not present"
    fi
    current=$(driver_of "$path")
    if [ "$current" = vfio-pci ]; then
      continue
    fi
    if ! echo vfio-pci >"$path/driver_override"; then
      refuse "cannot set driver_override of $device"
    fi
    if [ -n "$current" ] && ! echo "$device" >"$path/driver/unbind"; then
      refuse "cannot unbind $device from $current"
    fi
    if ! echo "$device" >"$sysfs/bus/pci/drivers_probe"; then
      refuse "the kernel would not probe $device for vfio-pci"
    fi
    bound=$(driver_of "$path")
    if [ "$bound" != vfio-pci ]; then
      refuse "$device is on ${bound:-no driver}, not vfio-pci"
    fi
    log "bound $device to vfio-pci, away from ${current:-no driver}"
  done
}

isolate_host() {
  local cpu online allowed unit
  local -a host_cpus=()
  local -A pinned=()
  for cpu in "${vcpus[@]}"; do
    pinned[$cpu]=1
  done
  online=$(<"$sysfs/devices/system/cpu/online")
  for cpu in $(cpu_list "$online"); do
    if [ -z "${pinned[$cpu]:-}" ]; then
      host_cpus+=("$cpu")
    fi
  done
  if [ "${#host_cpus[@]}" -eq 0 ]; then
    refuse "the vCPUs are pinned to every online CPU ($online), which would leave the host none"
  fi
  allowed=$(
    IFS=,
    echo "${host_cpus[*]}"
  )
  echo "$guest" >"$lock"
  isolated=1
  for unit in system.slice user.slice init.scope; do
    if ! systemctl set-property --runtime -- "$unit" "AllowedCPUs=$allowed"; then
      refuse "cannot confine $unit to the CPUs $allowed"
    fi
  done
  log "confined the host to the CPUs $allowed"
}

prepare() {
  local holder
  mkdir -p "$state"
  load_mounts
  if [ "${#devices[@]}" -gt 0 ]; then
    guard
  fi
  if [ "$isolate" = true ] && [ "${#vcpus[@]}" -gt 0 ] && [ -f "$lock" ]; then
    holder=$(<"$lock")
    if [ "$holder" != "$guest" ]; then
      refuse "$holder holds the host's CPUs; with pinning.isolate one pinned domain runs at a time, and $lock names it"
    fi
  fi
  if [ "$iommu" = true ]; then
    check_iommu_groups
  fi
  trap undo EXIT
  stop_listed_services
  check_holders
  unmount_listed
  if [ "${#devices[@]}" -gt 0 ]; then
    unmount_devices
  fi
  if [ "$pages" -gt 0 ]; then
    allocate_pages
  fi
  if [ "$gpu" != null ]; then
    bind_gpu
  fi
  if [ "$isolate" = true ] && [ "${#vcpus[@]}" -gt 0 ]; then
    isolate_host
  fi
  trap - EXIT
}

rebind_gpu() {
  local device path
  read_list .functions "$gpu"
  for device in "${list[@]}"; do
    path=$sysfs/bus/pci/devices/$device
    if [ "$(driver_of "$path")" != vfio-pci ]; then
      continue
    fi
    if ! echo "$device" >"$path/driver/unbind"; then
      log "could not unbind $device from vfio-pci"
      failed=1
    fi
    if ! echo >"$path/driver_override"; then
      log "could not clear driver_override of $device"
      failed=1
    fi
    if ! echo "$device" >"$sysfs/bus/pci/drivers_probe"; then
      log "the host driver did not take $device back"
      failed=1
    fi
  done
}

release() {
  local holder
  if [ "$gpu" != null ] && [ "$(jq -r .rebindOnStop <<<"$gpu")" = true ]; then
    rebind_gpu
  fi
  give_back_pages
  remount
  start_listed_services
  if [ -f "$lock" ]; then
    holder=$(<"$lock")
    if [ "$holder" = "$guest" ]; then
      restore_cpus
    fi
  fi
  exit "$failed"
}

case "$operation/$phase" in
prepare/begin) prepare ;;
release/end) release ;;
esac
