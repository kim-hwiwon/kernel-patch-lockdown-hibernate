#!/bin/sh

# https://community.frame.work/t/guide-fedora-36-hibernation-with-enabled-secure-boot-and-full-disk-encryption-fde-decrypting-over-tpm2/25474

TARGET_KVER_FULL="${1:-$(uname -r)}"


### Set variables
kname="lckdn_hiber"
kver_full="${TARGET_KVER_FULL}"
kver_major_minor="$(printf "%s" "$kver_full" | cut -d. -f-2)"
kver_sem="$(printf "%s" "$kver_full" | cut -d- -f1)"
kver_fver="$(printf "%s" "$kver_full" | cut -d. -f-4)"
kver_target="$(printf "%s" "$kver_full" | cut -d. -f-3).$kname.$(printf "%s" "$kver_full" | cut -d. -f4-)"
karch="$(printf "%s" "$kver_full" | cut -d. -f5)"
src_patch_name="v${kver_major_minor}.patch"
src_patch_link=https://github.com/kim-hwiwon/kernel-patch-lockdown-hibernate/raw/refs/heads/main/patchs/"$src_patch_name"
target_patch_name="lockdown-hibernate-${src_patch_name}"
workspace=~/.lckdn-hiber-workspace
workspace_kver="$workspace/$kver_full"
rpmbuild="${workspace_kver}/unpack/${HOME}/rpmbuild"
rpmbuild_subdirs="BUILD RPMS SOURCES SPECS SRPMS"

printf "\n - Processing with following variables:\n   - kver_full: %s\n   - kver_sem: %s\n   - kver_fver: %s\n   - kver_target: %s\n   - karch: %s\n   - src_patch_link: %s\n\n" \
  "$kver_full" "$kver_sem" "$kver_fver" "$kver_target" "$karch" "$src_patch_link"

# tmp workspace
mkdir -p "$workspace_kver" || exit 1
printf " - Temp workspace: \"%s\"\n" "$workspace_kver"
cd "$workspace_kver" || exit 1

# skip if already exists
if [ -f "$rpmbuild/RPMS/$karch/kernel-$kver_target.rpm" ]
then
  printf " - rpm files already exists in '%s'! Build skipped.\n   If you want to rebuild it, remove dir '%s' and try again.\n" "$rpmbuild/RPMS/$karch" "$rpmbuild/RPMS/$karch"
  exit 0
fi

# Test if remote patch file exists
wget --spider "$src_patch_link" || exit 1

### Setup build system
for dir in $rpmbuild_subdirs; do mkdir -p "$rpmbuild/$dir" || exit 1; done
koji download-build --arch=src "kernel-$kver_full" || exit 1
rpm -Uvh "kernel-$kver_fver.src.rpm" --root="$workspace_kver/unpack" || exit 1
cd "$rpmbuild/SPECS" || exit 1

### Apply patches and customize kernel configuration
# Get patch to enable hibernate in lockdown mode (secure boot)
wget "$src_patch_link" -O "$rpmbuild/SOURCES/$target_patch_name" || exit 1
# Define patch in kernel.spec for building the rpms
patch_list="$(grep -o "^Patch[0-9][0-9]*" kernel.spec | cut -c6- | sort -r)"
for last_patch in $patch_list; do target_patch="$((last_patch - 1))"; echo "$patch_list" | grep -qx "$target_patch" || break; done;
sed -i "/^Patch${last_patch}/i Patch${target_patch}: ${target_patch_name}" kernel.spec || exit 1
# Add patch as ApplyOptionalPatch
sed -i "/^ApplyOptionalPatch linux-kernel-test.patch/i ApplyOptionalPatch $target_patch_name" kernel.spec || exit 1
# Add custom kernel name
sed -i "s/# define buildid .local/%define buildid .$kname/g" kernel.spec || exit 1
# Install necessary dependencies for compiling hte kernel
rpmbuild --define "_topdir $rpmbuild" -bp kernel.spec || exit 1

# Compile kernel
time rpmbuild --define "_topdir $rpmbuild" -bb --with baseonly --without debuginfo --target="$karch" kernel.spec 2>&1 | tee "$workspace_kver"/build-kernel.log || exit 1

printf " - Built the kernel '%s'!\n" "${kver_target}"
