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
kver_full="$(printf "%s" "$TARGET_KVER_FULL" | sed "s/\.$kname\./\./g")"
kver_target="$(printf "%s" "$kver_full" | cut -d. -f-3).$kname.$(printf "%s" "$kver_full" | cut -d. -f4-)"
karch="$(printf "%s" "$kver_full" | cut -d. -f5)"
workspace="$home_before_sudo/.lckdn-hiber-workspace"
workspace_kver="$workspace/$kver_full"
rpmbuild="${workspace_kver}/unpack${home_before_sudo}/rpmbuild"

vmlinuz_path="/boot/vmlinuz-${kver_target}"

# install kernel
(
  cd "$rpmbuild/RPMS/$karch" || exit 1

  # install all rpms in two steps (to prevent a picky dracut error when installing at once)
  #   -> install 'kernel-module' rpm at very last

  # initial first install list
  r_list="$(ls *.rpm | sort)"
  kernel_r="kernel-${kver_target}.rpm"
  r_list="$(printf "%s" "$r_list" | sed "/^${kernel_r}\$/d")"

  # initial last install 'type' (without kver) list
  r_type_list="kernel-modules" # install kernel-modules at very last, with its dependants"

  # get all dependants of last install list
  r_type_list_added=1
  while [ -n "$r_type_list_added" ] # repeat until no addition
  do
    unset r_type_list_added
    for r in $r_list
    do
      r_type="${r%-${kver_target}.rpm}"
      for req_r_type in $r_type_list
      do
        if rpm -qp --requires "$r" | grep -q "${req_r_type}-uname-r = ${kver_target}" \
          && ! (printf "%s" "$r_type_list" | grep -q "^$r_type\$")
        then
          r_type_list="$(printf "%s\n%s" "$r_type_list" "$r_type")"
          r_type_list_added=1
          break
        fi
      done
    done
  done

  # include kernel rpm to last install list first
  r_last_list="$kernel_r"

  # for each last install type list,
  # exclude from first install list && include to last install list
  for r_type in $r_type_list
  do
    cur_r_name="$(printf "%s-%s.rpm\n" "$r_type" "$kver_target" | sed 's/\./\\\./g')"
    r_list="$(printf "%s" "$r_list" | sed "/^$cur_r_name\$/d")"
    r_last_list="$(printf "%s\n%s" "$r_last_list" "$(printf "%s" "$cur_r_name" | sed 's/\\\./\./g')")"
  done

  printf " - Installing all rpms in following order:\n==================================================\n%s\n==================================================\n%s\n==================================================\n\n" "$r_list" "$r_last_list"

  rpm -ivh $r_list || exit 1
  rpm -ivh $r_last_list || exit 1
) || exit 1

# sign kernel
pesign --certificate "$kname" --in "$vmlinuz_path" \
       --sign --out "$vmlinuz_path.signed" || exit 1
mv "$vmlinuz_path.signed" "$vmlinuz_path" || exit 1

# sign kernel modules
#mod_list="$(find "/lib/modules/${kver_target}/" -type f -name "*.ko" -name "*.ko.gz" -name "*.ko.xz")"
#(
#  IFS="
#"
#  for mod in $mod_list
#  do
#    mod_ftype="ko"
#    mod_to_sign="$mod"
#    if [ "${mod%\.xz}" != "$mod" ]; then mod_ftype="xz"; mod_to_sign="${mod%\.xz}"; xz -d "$mod" || exit 1
#    elif [ "${mod%\.gz}" != "$mod" ]; then mod_ftype="gz"; mod_to_sign="${mod%\.gz}"; gzip -d "$mod" || exit 1
#    fi

    
#  done
#)

# Add kparam for current & future kernels
grubby --args="lockdown_hibernate=1" --update-kernel="$vmlinuz_path" \
  || exit 1

# update initramfs
dracut -f --kver="$kver_target" || exit 1

printf " - Installed & signed the kernel '%s'!\n" "$kver_target"
