sysfs=${SYSFS_ROOT:-/sys}
devices=$sysfs/bus/pci/devices

name_of() {
  local line
  line=$(lspci -D -s "$1")
  if [ -n "$line" ]; then
    echo "${line#"$1" }"
  else
    echo "(lspci does not know it)"
  fi
}

id_of() {
  local vendor device
  vendor=$(<"$devices/$1/vendor")
  device=$(<"$devices/$1/device")
  echo "${vendor#0x}:${device#0x}"
}

class_of() {
  local class
  class=$(<"$devices/$1/class")
  echo "${class#0x}"
}

driver_of() {
  if [ -e "$devices/$1/driver" ]; then
    basename "$(readlink -f "$devices/$1/driver")"
  else
    echo "none"
  fi
}

quoted() {
  local item out=""
  for item in "$@"; do
    out+=" \"$item\""
  done
  echo "[${out} ]"
}

found=0
for path in "$devices"/*; do
  gpu=${path##*/}
  class=$(class_of "$gpu")
  [[ $class == 03* ]] || continue
  found=1
  slot=${gpu%.*}

  echo "$gpu  $(name_of "$gpu")"
  echo "  id $(id_of "$gpu"), driver $(driver_of "$gpu")"

  if [ -f "$path/boot_vga" ] && [ "$(<"$path/boot_vga")" = 1 ]; then
    echo "  Your firmware shows its picture on this card. Passed through with binding \"boot\","
    echo "  the boot and disk-encryption prompts go with it; docs/TROUBLESHOOTING.md says how to keep them."
  fi

  if [ ! -e "$path/iommu_group" ]; then
    echo "  No IOMMU group: the IOMMU is off. Turn it on in the firmware setup, as docs/GUIDE.md shows."
    echo
    continue
  fi
  group=$(basename "$(readlink -f "$path/iommu_group")")
  echo "  IOMMU group $group:"

  audio=""
  extra=()
  ids=()
  others=()
  for member_path in "$path/iommu_group/devices"/*; do
    member=${member_path##*/}
    echo "    $member  $(name_of "$member")"
    member_class=$(class_of "$member")
    if [ "${member%.*}" = "$slot" ]; then
      ids+=("$(id_of "$member")")
      if [ "$member" = "$gpu" ]; then
        continue
      elif [[ $member_class == 0403* ]] && [ -z "$audio" ]; then
        audio=$member
      else
        extra+=("$member")
      fi
    elif [[ $member_class != 0604* ]]; then
      others+=("$member")
    fi
  done

  if [ "${gpu##*.}" != 0 ]; then
    echo "  This is not the card's first function, which the module passes; look at ${slot}.0."
  elif [ "${#others[@]}" -gt 0 ]; then
    echo "  The group also holds ${others[*]}, which would leave the host with the card."
    echo "  Try another slot first; docs/GUIDE.md, Check the hardware, says why."
  else
    echo "  The group holds only this card, so it can go to a VM:"
    echo
    echo "    gpu = {"
    echo "      address = \"$gpu\";"
    if [ -n "$audio" ]; then
      echo "      audio = \"$audio\";"
    fi
    if [ "${#extra[@]}" -gt 0 ]; then
      echo "      extraFunctions = $(quoted "${extra[@]}");"
    fi
    echo "      ids = $(quoted "${ids[@]}");"
    echo "    };"
    echo "  ids matters only with binding = \"boot\"."
  fi
  echo
done

if [ "$found" = 0 ]; then
  echo "No GPU found under $devices."
  exit 1
fi
