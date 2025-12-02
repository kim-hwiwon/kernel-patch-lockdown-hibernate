#!/bin/sh

TARGET_KVER_FULL="${1:-$(uname -r)}"

# run as root if not
if [ "$(id -u)" -ne 0 ]
  then
  sudo true || { printf " *** Run as root! ***\n" >&2; exit 1; } || exit 1
  sudo "$0" "$@"; exit "$?"
fi

# all commands are basically root commands from now on

kname="lckdn_hiber"
kver_full="$(printf "%s" "$TARGET_KVER_FULL" | sed "s/\.$kname\./\./g")"
kver_target="$(printf "%s" "$kver_full" | cut -d. -f-3).$kname.$(printf "%s" "$kver_full" | cut -d. -f4-)"

# remove kernel
kver_to_rm="$kver_full"
if ! printf "%s" "$kver_to_rm" | grep -q "\.$kname\."
then
  kver_to_rm="$kver_target"
fi

dnf remove 'kernel*-*:'"$kver_to_rm" || exit 1

printf " - Removed the kernel '%s'!\n" "${kver_target}"
