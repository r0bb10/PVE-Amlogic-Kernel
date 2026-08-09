#!/usr/bin/env bash
set -euo pipefail

root=$(realpath "$(dirname "$0")/..")
toolchain_name="arm-gnu-toolchain-15.3.rel1-aarch64-aarch64-none-linux-gnu"
toolchain_bin="/workspace/toolchains/$toolchain_name/bin"
owner="$(id -u):$(id -g)"
ccache_dir="$root/.cache/ccache"
builder_image="${BUILDER_IMAGE:-}"

if [[ -z "$builder_image" ]]; then
    if [[ -n "${GITHUB_ACTIONS:-}" ]]; then
        builder_image="ghcr.io/r0bb10/pve-kernel-builder:latest"
        if ! docker pull "$builder_image"; then
            builder_image="ophub/armbian-resolute:arm64"
        fi
    else
        builder_image="ophub/armbian-resolute:arm64"
    fi
fi

if [[ -z "${ZFS_VERSION:-}" ]]; then
    mapfile -t zfs_versions < <(
        git ls-remote --refs --tags https://github.com/openzfs/zfs.git 'zfs-[0-9]*' |
            while read -r _ ref; do
                version="${ref##*/zfs-}"
                [[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ && "$version" != *.99 ]] &&
                    printf '%s\n' "$version"
            done |
            sort -V
    )
    (( ${#zfs_versions[@]} )) || { printf 'No stable OpenZFS release tag found.\n' >&2; exit 1; }
    ZFS_VERSION="${zfs_versions[-1]}"
fi
export ZFS_VERSION

mkdir -p "$ccache_dir"

if [[ "$(uname -m)" != "aarch64" ]]; then
    docker run --rm --privileged multiarch/qemu-user-static --reset -p yes
fi

docker run --rm \
    --privileged \
    --platform linux/arm64 \
    --network host \
    -e DEBIAN_FRONTEND=noninteractive \
    -e CCACHE_DIR=/ccache \
    -e CCACHE_BASEDIR=/workspace/ophub-pve-build \
    -e CCACHE_COMPILERCHECK=content \
    -e CCACHE_NOHASHDIR=true \
    -e ZFS_VERSION \
    -v "$root:/workspace" \
    -v "$ccache_dir:/ccache" \
    -w /workspace \
    "$builder_image" \
    bash -ec '
        set -o pipefail
        if [ "${PVE_KERNEL_BUILDER:-}" != 1 ]; then
            apt-get update
            apt-get install -y --no-install-recommends \
                $(curl -fsSL https://raw.githubusercontent.com/ophub/amlogic-s9xxx-armbian/main/compile-kernel/tools/script/armbian-compile-kernel-depends) \
                libtool-bin
            mkdir -p /workspace/toolchains
            archive="/workspace/toolchains/'"$toolchain_name"'.tar.xz"
            if [ ! -x "'"$toolchain_bin"'/aarch64-none-linux-gnu-gcc" ]; then
                curl -fL --retry 3 --output "$archive" \
                    https://github.com/ophub/kernel/releases/download/dev/'"$toolchain_name"'.tar.xz
                test "$(sha256sum "$archive" | cut -d " " -f 1)" = \
                    8020be7aa1013704756158400cb5ba438d6f09b2909795d13617b9e7bac53286
                tar -xf "$archive" -C /workspace/toolchains
            fi
        fi
        git config --global --add safe.directory /workspace/ophub-pve-build/linux-6.18.y
        export PATH="${PVE_KERNEL_TOOLCHAIN_BIN:-'"$toolchain_bin"'}:$PATH"
        export CROSS_COMPILE=aarch64-none-linux-gnu-
        ccache -M 10G
        ./scripts/build-kernel-pve.sh 2>&1 | tee /workspace/ophub-pve-build.log
        ccache -s
        chown -R '"$owner"' ophub-pve-build packages-ophub
    '
