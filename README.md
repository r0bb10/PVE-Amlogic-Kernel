[![Build and Release](../../actions/workflows/build-kernel.yml/badge.svg)](../../actions/workflows/build-kernel.yml)
![Platform: ARM64](https://img.shields.io/badge/platform-ARM64-blue)
![License: GPL-2.0](https://img.shields.io/badge/license-GPL--2.0-blue)
![Proxmox ARM64: compatible](https://img.shields.io/badge/Proxmox%20VE-compatible-orange)

# PVE Kernel for S905X3

This repository follows new releases from [ophub/linux-6.18.y](https://github.com/ophub/linux-6.18.y)
and builds an S905X3 kernel release named `-pve` with the corrisponding latest stable OpenZFS modules.


## Install

Download and install all packages from the latest release in /tmp and run `apt install ./*.deb`.

## Upgrade

Add the signed repository to receive future `pve-kernel` upgrades through normal APT operations:

```bash
install -d -m 0755 /etc/apt/keyrings
curl -fsSL https://r0bb10.github.io/PVE-Amlogic-Kernel/gpg.key | gpg --dearmor -o /etc/apt/keyrings/pve-kernel.gpg
echo 'deb [signed-by=/etc/apt/keyrings/pve-kernel.gpg] https://r0bb10.github.io/PVE-Amlogic-Kernel/ trixie main' > /etc/apt/sources.list.d/pve-kernel.list
apt update
```

Future `apt update && apt upgrade` operations install the next `*-pve` image, headers and ZFS package.

## License

This repository is licensed under [GPL-2.0-only](LICENSE), matching the
Ophub-derived kernel build logic and upstream Linux kernel source.
