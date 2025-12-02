#!/bin/sh

# https://community.frame.work/t/guide-fedora-36-hibernation-with-enabled-secure-boot-and-full-disk-encryption-fde-decrypting-over-tpm2/25474

TARGET_KVER_FULL="${1:-$(uname -r)}"

# run as root if not
if [ "$(id -u)" -ne 0 ]
  then
  sudo true || { printf " *** Run as root! ***\n" >&2; exit 1; } || exit 1
  sudo "$0" "$@"; exit "$?"
fi

# all commands are basically root commands from now on

uid_before_sudo="${SUDO_UID:-0}"
home_before_sudo="$(getent passwd "$uid_before_sudo" | cut -d: -f6)"

kname="lckdn_hiber"
kver_full="${TARGET_KVER_FULL}"
kver_target="$(printf "%s" "$kver_full" | cut -d. -f-3).$kname.$(printf "%s" "$kver_full" | cut -d. -f4-)"
karch="$(printf "%s" "$kver_full" | cut -d. -f5)"
workspace="$home_before_sudo/.lckdn-hiber-workspace"
workspace_kver="$workspace/$kver_full"
rpmbuild="$workspace_kver/unpack/$home_before_sudo/rpmbuild"

vmlinuz_path="/boot/vmlinuz-${kver_target}"

# install kernel
(
  cd "$rpmbuild/RPMS/$karch" || exit 1
  dnf install -y *.rpm || exit 1
) || exit 1

# sign kernel
pesign --certificate "$kname" --in "$vmlinuz_path" \
         --sign --out "$vmlinuz_path.signed" || exit 1
mv "$vmlinuz_path.signed" "$vmlinuz_path" || exit 1

# Add kparam for current & future kernels
grubby --args="lockdown_hibernate=1" --update-kernel="$vmlinuz_path" \
  || exit 1

# update initramfs
dracut -f || exit 1

printf " - Installed & signed the kernel '%s'!\n" "$kver_target"
