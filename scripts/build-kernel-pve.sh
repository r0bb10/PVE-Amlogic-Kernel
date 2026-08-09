#!/usr/bin/env bash
set -euo pipefail

root=$(realpath "$(dirname "$0")/..")
work_dir="$root/ophub-pve-build"
kernel_source="$work_dir/linux-6.18.y"
config="$work_dir/config-6.18"
config_url="https://raw.githubusercontent.com/ophub/kernel/main/kernel-config/release/stable/config-6.18"
modules_root="$work_dir/modules"
toolchain_prefix="${CROSS_COMPILE:-aarch64-none-linux-gnu-}"

if ! command -v "${toolchain_prefix}gcc" >/dev/null; then
    printf 'Required compiler not found: %sgcc\n' "$toolchain_prefix" >&2
    exit 1
fi

mkdir -p "$work_dir"
if [[ ! -s "$config" ]]; then
    curl -fsSL "$config_url" -o "$config"
fi

if [[ ! -d "$kernel_source/.git" ]]; then
    git clone --depth 1 https://github.com/ophub/linux-6.18.y.git "$kernel_source"
else
    git -C "$kernel_source" fetch --depth 1 origin main
    git -C "$kernel_source" reset --hard origin/main
    git -C "$kernel_source" clean -fdx
fi

source_epoch=$(git -C "$kernel_source" log -1 --format=%ct)
patch="$root/patches/pve.patch"
git -C "$kernel_source" apply --check "$patch"
git -C "$kernel_source" apply "$patch"
git -C "$kernel_source" add init/Makefile
git -C "$kernel_source" -c user.name='Local PVE kernel build' -c user.email='root@localhost' \
    commit -m 'init: add PVE version timestamp support'

build_date=$(date -u -d "@$source_epoch" '+%Y-%m-%dT%H:%MZ')
export SOURCE_DATE_EPOCH="$source_epoch"
export KBUILD_BUILD_TIMESTAMP="$(date -u -d "@$source_epoch" '+%a %b %e %T UTC %Y')"
export KBUILD_BUILD_VERSION_TIMESTAMP="PMX $(make -sC "$kernel_source" kernelversion) ($build_date)"
export KBUILD_BUILD_USER=build
export KBUILD_BUILD_HOST=proxmox
export KBUILD_BUILD_VERSION=1

make_args=(
    -C "$kernel_source"
    ARCH=arm64
    "CROSS_COMPILE=$toolchain_prefix"
    "CC=ccache ${toolchain_prefix}gcc"
    "LD=${toolchain_prefix}ld"
    LOCALVERSION=-pve
)

# This follows ophub's in-tree model. Do not replace it with an O= build.
make "${make_args[@]}" mrproper
cp "$config" "$kernel_source/.config"
"$kernel_source/scripts/config" --file "$kernel_source/.config" --set-str LOCALVERSION ''
"$kernel_source/scripts/config" --file "$kernel_source/.config" --disable LOCALVERSION_AUTO
"$kernel_source/scripts/config" --file "$kernel_source/.config" --disable IPV6_SIT
"$kernel_source/scripts/config" --file "$kernel_source/.config" --disable IPV6_TUNNEL
"$kernel_source/scripts/config" --file "$kernel_source/.config" --disable IPV6_VTI
"$kernel_source/scripts/config" --file "$kernel_source/.config" --disable IPV6_GRE
"$kernel_source/scripts/config" --file "$kernel_source/.config" --disable IPV6_FOU
"$kernel_source/scripts/config" --file "$kernel_source/.config" --disable IPV6_FOU_TUNNEL
"$kernel_source/scripts/config" --file "$kernel_source/.config" --disable NET_FOU
"$kernel_source/scripts/config" --file "$kernel_source/.config" --disable NET_FOU_IP_TUNNELS
make "${make_args[@]}" olddefconfig

if ! grep -qx 'CONFIG_MODULES=y' "$kernel_source/.config"; then
    printf 'Loadable kernel module support is required for native OpenZFS.\n' >&2
    exit 1
fi

if grep -qE '^CONFIG_(IPV6_SIT|IPV6_TUNNEL)=y' "$kernel_source/.config"; then
    printf 'IPv6 tunnel interfaces remain enabled in the kernel configuration.\n' >&2
    exit 1
fi

release=$(make -s "${make_args[@]}" kernelrelease)
expected_release="$(make -sC "$kernel_source" kernelversion)-pve"
if [[ "$release" != "$expected_release" ]]; then
    printf 'Expected kernel release %s, got %s\n' "$expected_release" "$release" >&2
    exit 1
fi

make "${make_args[@]}" -j"$(nproc)" Image modules
make "${make_args[@]}" modules_prepare
rm -rf "$modules_root"
make "${make_args[@]}" INSTALL_MOD_PATH="$modules_root" modules_install
find "$modules_root" -type f -name '*.ko' -exec "${toolchain_prefix}strip" --strip-debug {} +

KERNEL_SOURCE="$kernel_source" \
KERNEL_MODULES_ROOT="$modules_root" \
KERNEL_RELEASE="$release" \
KERNEL_BUILD_DATE="$build_date" \
    "$root/scripts/package-kernel-pve.sh"
