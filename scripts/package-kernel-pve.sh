#!/usr/bin/env bash
set -euo pipefail

root=$(realpath "$(dirname "$0")/..")
kernel_source="${KERNEL_SOURCE:?KERNEL_SOURCE is required}"
modules_root="${KERNEL_MODULES_ROOT:?KERNEL_MODULES_ROOT is required}"
release="${KERNEL_RELEASE:?KERNEL_RELEASE is required}"
zfs_version="${ZFS_VERSION:?ZFS_VERSION is required}"
work_dir="$root/ophub-pve-build"
zfs_source="$work_dir/zfs-$zfs_version"
zfs_build="$work_dir/zfs-build-$release"
stage_dir="$work_dir/stage"
package_dir="$root/packages-ophub"
version="$release"

require_file() {
    [[ -e "$1" ]] || { printf 'Required build artifact not found: %s\n' "$1" >&2; exit 1; }
}

require_file "$kernel_source/arch/arm64/boot/Image"
require_file "$kernel_source/Module.symvers"
require_file "$modules_root/lib/modules/$release"

rm -rf "$stage_dir" "$package_dir"
mkdir -p "$stage_dir" "$package_dir"

image_stage="$stage_dir/linux-image-$release"
image_files="$image_stage/usr/lib/linux-image-$release"
mkdir -p "$image_stage/DEBIAN" "$image_files" "$image_stage/usr/lib/modules"
install -m 0644 "$kernel_source/arch/arm64/boot/Image" "$image_files/vmlinuz"
install -m 0644 "$kernel_source/.config" "$image_files/config"
install -m 0644 "$kernel_source/System.map" "$image_files/System.map"
cp -a "$modules_root/lib/modules/$release" "$image_stage/usr/lib/modules/"
rm -f "$image_stage/usr/lib/modules/$release"/{build,source}
cat > "$image_stage/DEBIAN/control" <<EOF
Package: linux-image-$release
Version: $version
Architecture: arm64
Maintainer: Local Proxmox administrator
Provides: linux-image-ophub
Section: kernel
Priority: optional
Description: Custom ophub Linux $release for Amlogic Proxmox VE
 This package deliberately does not run UEFI, GRUB, or proxmox-boot-tool hooks.
EOF
cat > "$image_stage/DEBIAN/postinst" <<EOF
#!/bin/sh
set -e

/sbin/depmod -a $release

install -m 0644 /usr/lib/linux-image-$release/System.map /boot/System.map-$release
install -m 0644 /usr/lib/linux-image-$release/config /boot/config-$release
install -m 0644 /usr/lib/linux-image-$release/vmlinuz /boot/vmlinuz-$release

initramfs_conf=/etc/initramfs-tools/update-initramfs.conf
if command -v update-initramfs >/dev/null 2>&1; then
    previous_update_initramfs=
    if [ -f "\$initramfs_conf" ]; then
        previous_update_initramfs=\$(grep '^update_initramfs=' "\$initramfs_conf" || true)
        sed -i 's|^update_initramfs=.*|update_initramfs=yes|' "\$initramfs_conf"
    fi

    update-initramfs -c -k $release

    if [ -n "\$previous_update_initramfs" ]; then
        sed -i "s|^update_initramfs=.*|\$previous_update_initramfs|" "\$initramfs_conf"
    fi
fi

if [ ! -f /boot/uInitrd-$release ] && [ -f /boot/uInitrd ]; then
    cp -f /boot/uInitrd /boot/uInitrd-$release
fi

if [ ! -f /boot/uInitrd-$release ] && command -v mkimage >/dev/null 2>&1; then
    mkimage -A arm -O linux -T ramdisk -C none \
        -d /boot/initrd.img-$release /boot/uInitrd-$release
fi

test -f /boot/uInitrd-$release
cp -f /boot/uInitrd-$release /boot/uInitrd
cp -f /boot/vmlinuz-$release /boot/zImage
EOF
chmod 0755 "$image_stage/DEBIAN/postinst"

headers_stage="$stage_dir/linux-headers-$release"
headers_root="$headers_stage/usr/src/linux-headers-$release"
mkdir -p "$headers_stage/DEBIAN" "$headers_root" "$headers_stage/usr/lib/modules/$release"
cp -a "$kernel_source/Makefile" "$kernel_source/Kbuild" "$kernel_source/Kconfig" "$headers_root/"
cp -a "$kernel_source/arch" "$kernel_source/include" "$kernel_source/scripts" "$headers_root/"
cp -a "$kernel_source/.config" "$kernel_source/Module.symvers" "$headers_root/"
ln -s "/usr/src/linux-headers-$release" "$headers_stage/usr/lib/modules/$release/build"
cat > "$headers_stage/DEBIAN/control" <<EOF
Package: linux-headers-$release
Version: $version
Architecture: arm64
Maintainer: Local Proxmox administrator
Section: kernel
Priority: optional
Description: Headers for custom ophub Linux $release
EOF

if [[ ! -d "$zfs_source/.git" ]]; then
    git clone --depth 1 --branch "zfs-$zfs_version" https://github.com/openzfs/zfs.git "$zfs_source"
else
    git -C "$zfs_source" reset --hard "zfs-$zfs_version"
    git -C "$zfs_source" clean -fdx
fi
(cd "$zfs_source" && ./autogen.sh)
rm -rf "$zfs_build"
mkdir -p "$zfs_build/module"
(
    cd "$zfs_build"
    KERNEL_CC="$root/scripts/ccache-aarch64-none-linux-gnu-gcc" \
    KERNEL_LD=aarch64-none-linux-gnu-ld \
    KERNEL_CROSS_COMPILE=aarch64-none-linux-gnu- \
    KERNEL_ARCH=arm64 \
    "$zfs_source/configure" --with-config=kernel --with-linux="$kernel_source" --with-linux-obj="$kernel_source"
    cp -al "$zfs_source/module/." module/
    make -j"$(nproc)"
)
find "$zfs_build/module" -type f -name '*.ko' -exec aarch64-none-linux-gnu-strip --strip-debug {} +

zfs_stage="$stage_dir/zfs-modules-$release"
zfs_modules="$zfs_stage/usr/lib/modules/$release/zfs"
mkdir -p "$zfs_stage/DEBIAN" "$zfs_modules"
while IFS= read -r -d '' module; do
    install -m 0644 "$module" "$zfs_modules/$(basename "$module")"
done < <(find "$zfs_build/module" -type f -name '*.ko' -print0)
[[ -n "$(ls -A "$zfs_modules")" ]] || { printf 'No OpenZFS modules were produced.\n' >&2; exit 1; }
cat > "$zfs_stage/DEBIAN/control" <<EOF
Package: zfs-modules-$release
Version: $version
Architecture: arm64
Maintainer: Local Proxmox administrator
Depends: linux-image-$release (= $version), zfsutils-linux (>= $zfs_version)
Provides: zfs-modules
Section: kernel
Priority: optional
Description: Native OpenZFS modules for custom ophub Linux $release
 Native modules for this kernel release; no DKMS build is required.
EOF
cat > "$zfs_stage/DEBIAN/postinst" <<EOF
#!/bin/sh
set -e
/sbin/depmod -a $release
EOF
chmod 0755 "$zfs_stage/DEBIAN/postinst"

pve_kernel_stage="$stage_dir/pve-kernel"
mkdir -p "$pve_kernel_stage/DEBIAN"
cat > "$pve_kernel_stage/DEBIAN/control" <<EOF
Package: pve-kernel
Version: $version
Architecture: arm64
Maintainer: Local Proxmox administrator
Depends: linux-image-$release (= $version), linux-headers-$release (= $version), zfs-modules-$release (= $version)
Section: kernel
Priority: optional
Description: Rolling metapackage for the custom PVE kernel
 Installing upgrades this system to the current custom PVE kernel release.
EOF

for stage in "$image_stage" "$headers_stage" "$zfs_stage" "$pve_kernel_stage"; do
    package_name=$(basename "$stage")
    dpkg-deb --build "$stage" "$package_dir/${package_name}_arm64.deb"
done

printf 'Packages written to %s\n' "$package_dir"
