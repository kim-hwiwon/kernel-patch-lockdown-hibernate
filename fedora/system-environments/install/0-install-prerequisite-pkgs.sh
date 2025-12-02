#!/bin/sh

# run as root if not
if [ "$(id -u)" -ne 0 ]
  then
  sudo true || { printf " *** Run as root! ***\n" >&2; exit 1; } || exit 1
  sudo "$0" "$@"; exit "$?"
fi

# all commands are root from now on

# install deps for kernel build
dnf install -y fedpkg rpm-build rpmdevtools koji mokutil nss-tools pesign || exit 1
