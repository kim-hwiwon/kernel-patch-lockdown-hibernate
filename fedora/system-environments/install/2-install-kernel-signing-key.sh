#!/bin/sh

# run as root if not
if [ "$(id -u)" -ne 0 ]
  then
  sudo true || { printf " *** Run as root! ***\n" >&2; exit 1; } || exit 1
  sudo "$0" "$@"; exit "$?"
fi

# all commands are basically root commands from now on

kname="lckdn_hiber"


trap 'ret=$?; [ -n "$tmpdir" ] && umount "$tmpdir"; rm -rf "$tmpdir"/*; exit $?;' INT TERM HUP QUIT EXIT
tmpdir="$(mktemp -d)" || exit 1
mount -t tmpfs tmpfs "$tmpdir" || exit 1

certutil -d /etc/pki/pesign -L -n "$kname" >/dev/null 2>/dev/null; keyset_exists=$?
[ -n "$(mokutil --list-enrolled --short | grep -n " $kname\$" | cut -d: -f1)" ]; mok_exists=$?
[ -n "$(mokutil --list-new --short | grep -n " $kname\$" | cut -d: -f1)" ]; mok_enrolling=$?


### check prerequisites ###
if [ "$mok_enrolling" -eq 0 ]
then
  printf " * A MOK certificate '%s' already in enrollment request list to shim!\n    It seems that you are trying to install related key twice.\n   If you want to cancel all current import request including '%s',\n   run the following command 'sudo mokutil --revoke-import' yourself.\n" "$kname" "$kname" >&2
  exit 1
fi

### key set generation ###
if [ "$keyset_exists" -ne 0 ]
then
  printf " - Generating a key set...\n"
  efikeygen --dbdir /etc/pki/pesign --common-name "CN=$kname" \
            --nickname "$kname" --self-sign --kernel 2>/dev/null || exit 1
else
  printf " - A key set '%s' already exists on '/etc/pki/pesign'! Key set generation skipped.\n" "$kname"
fi

### mok import ###

# request delete before add, if already exists
if [ "$mok_exists" -eq 0 ]
then
  printf " - A MOK certificate '%s' already enrolled on shim!\n   Adding a new delete request to request queue before importing a new certificate...\n" "$kname" >&2
  key_idx_list="$(mokutil --list-enrolled --short | grep -n "^[0-9a-f]* $kname\$" | cut -d: -f1)"
  (
    cd "$tmpdir" || exit 1
    mokutil --export || exit 1
    der_file_list="$(for idx in $key_idx_list; do printf "MOK-%04d.der " "$idx"; done)"
    [ -n "$der_file_list" ] || exit 1
    printf " - Requesting certificate deletion to shim...\n   Now enter any one-time password needed for [Delete MOK] stage, which appears during the next reboot.\n   You can run this script again after the reboot and complete the deletion.\n"
    mokutil --delete $der_file_list || exit 1
  ) || exit 1
  printf " + Certificate deletion requested to shim!\n"
  printf "\n ***** IMPORTANT *****\n   To finish certificate deletion:\n   1. Reboot the device.\n   2. MOK manager menu will appear during the reboot. Choose '"'Delete MOK'"'\n   3. Finish the rest procedures according to the screen.\n      (The one-time password you entered right before will be prompt during the enrollment.)\n"
  exit 0
fi

printf " - Exporting a certificate...\n"
tmp_cert="$tmpdir"/crt
certutil -d /etc/pki/pesign -Lr -n "$kname" > "$tmp_cert" || exit 1

printf " - Requesting certificate enrollment to shim...\n   Now enter any one-time password needed for [Enroll MOK] stage, which appears during the next reboot.\n"
mokutil --import "$tmp_cert" || exit 1

printf " + Certificate enrollment requested to shim!\n"
printf "\n ***** IMPORTANT *****\n   To finish certificate enrollment:\n   1. Reboot the device.\n   2. MOK manager menu will appear during the reboot. Choose '"'Enroll MOK'"'\n   3. Finish the rest procedures according to the screen.\n      (The one-time password you entered right before will be prompt during the enrollment.)\n"
