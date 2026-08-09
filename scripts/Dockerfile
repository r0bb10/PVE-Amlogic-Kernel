FROM ophub/armbian-resolute:arm64

ARG TOOLCHAIN_NAME=arm-gnu-toolchain-15.3.rel1-aarch64-aarch64-none-linux-gnu
ARG TOOLCHAIN_SHA256=8020be7aa1013704756158400cb5ba438d6f09b2909795d13617b9e7bac53286

RUN apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        $(curl -fsSL https://raw.githubusercontent.com/ophub/amlogic-s9xxx-armbian/main/compile-kernel/tools/script/armbian-compile-kernel-depends) \
        libtool-bin \
    && rm -rf /var/lib/apt/lists/*

RUN mkdir -p /opt/toolchains \
    && curl -fsSL --retry 3 https://github.com/ophub/kernel/releases/download/dev/${TOOLCHAIN_NAME}.tar.xz -o /tmp/toolchain.tar.xz \
    && test "$(sha256sum /tmp/toolchain.tar.xz | cut -d ' ' -f 1)" = "$TOOLCHAIN_SHA256" \
    && tar -xf /tmp/toolchain.tar.xz -C /opt/toolchains \
    && rm /tmp/toolchain.tar.xz

ENV PVE_KERNEL_BUILDER=1 \
    PVE_KERNEL_TOOLCHAIN_BIN=/opt/toolchains/arm-gnu-toolchain-15.3.rel1-aarch64-aarch64-none-linux-gnu/bin \
    CCACHE_DIR=/ccache \
    CCACHE_BASEDIR=/workspace/ophub-pve-build \
    CCACHE_COMPILERCHECK=content \
    CCACHE_NOHASHDIR=true
