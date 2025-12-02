#!/bin/sh

# run as root if not
if [ "$(id -u)" -ne 0 ]
  then
  sudo true || { printf " *** Run as root! ***\n" >&2; exit 1; } || exit 1
  sudo "$0" "$@"; exit "$?"
fi

# all commands are basically root commands from now on

kname="lckdn_hiber"


# assign key

# check if key exists
if certutil -d /etc/pki/pesign -L -n "$kname" >/dev/null 2>/dev/null
then
  printf " * Key '%s' already exists on '/etc/pki/pesign'!\n    It seems that you are trying to install related key twice.\n   Run the script '../remove/2-remove-kernel-signing-key.sh', and try again.\n" "$kname" >&2
  exit 1
fi

# check if MOK cert exists
if [ -n "$(mokutil --list-enrolled --short | grep -n " $kname\$" | cut -d: -f1)" ]
then
  printf " * Certificate '%s' already enrolled on shim!\n    It seems that you are trying to install related key twice.\n   Run the script '../remove/2-remove-kernel-signing-key.sh', and try again.\n" "$kname" >&2
  exit 1
fi

# check if MOK cert is in enroll request
if [ -n "$(mokutil --list-new --short | grep -n " $kname\$" | cut -d: -f1)" ]
then
  printf " * Certificate '%s' already in enrollment request list to shim!\n    It seems that you are trying to install related key twice.\n   If you want to cancel all current import request including '%s',\n   run the following command 'sudo mokutil --revoke-import' yourself.\n" "$kname" "$kname" >&2
  exit 1
fi

trap 'ret=$?; [ -n "$tmp_cert" ] && rm -f "$tmp_cert"; exit $?;' INT TERM HUP QUIT EXIT
tmp_cert="$(mktemp)"
printf " - Generating a key set...\n"
efikeygen --dbdir /etc/pki/pesign --common-name "CN=$kname" \
          --nickname "$kname" --self-sign --kernel 2>/dev/null || exit 1
printf " - Exporting a certificate...\n"
certutil -d /etc/pki/pesign -Lr -n "$kname" > "$tmp_cert" || exit 1

printf " - Requesting certificate enrollment to MOK...\n   Now enter any one-time password needed for 'Enroll MOK' stage, which appears during the next reboot.\n"
mokutil --import "$tmp_cert" || exit 1
rm -f "$tmp_cert"
trap - INT TERM HUP QUIT EXIT

printf " + Certificate enrollment requested to shim!\n"
printf "\n ***** IMPORTANT *****\n   To finish certificate enrollment:\n   1. Reboot the device.\n   2. MOK manager menu will appear during the reboot. Choose '"'Enroll MOK'"'\n   3. Finish the rest procedures according to the screen.\n   (The one-time password you entered right before will be prompt during the enrollment.)\n"
