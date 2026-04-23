# Vontar H618 Armbian Patches

Public Armbian `userpatches` payload and host-side bring-up tools for Vontar
H618 and similar H616-class Allwinner TV boxes.

The project goal is to boot Armbian from microSD with a dedicated project
U-Boot/SPL path instead of relying on the stock Android or eMMC boot chain.

## Validated Setup

- Validated target: one 4 GiB DDR3 Vontar H618 unit
- Boot path: microSD with project U-Boot/SPL
- Kernel line: Armbian `current` and `edge`
- LAN bring-up: depends on the matching U-Boot preinit sequence in this repo

## Quick Start

Clone this repository next to an Armbian build checkout and link its
`userpatches/` directory into the build tree:

```bash
git clone https://github.com/aco-art/vontar-h618-armbian-patche.git
git clone https://github.com/armbian/build.git armbian-build

cd armbian-build
rm -rf userpatches
ln -s ../vontar-h618-armbian-patche/userpatches userpatches

./compile.sh BOARD=vontar-h618 BRANCH=current RELEASE=bookworm \
  BUILD_DESKTOP=no BUILD_MINIMAL=no KERNEL_CONFIGURE=no
```

`rm -rf userpatches` removes the existing `userpatches/` directory inside the
Armbian build checkout before replacing it with the symlink above.

The board configuration currently expects:

- U-Boot defconfig: `vontar_h618_zero2w_defconfig`
- Linux DTB: `allwinner/sun50i-h618-vontar-h618.dtb`
- U-Boot branch: `tag:v2025.04`

Board-specific Broadcom firmware payloads are included under
`userpatches/overlay/lib/firmware/brcm/`. If you redistribute this repository
or derived images, verify that the firmware licensing terms are acceptable for
your use.

## Repository Layout

- `userpatches/` contains the board definition, U-Boot patches, kernel patches,
  optional overlay examples, and image customization hook.
- `tools/tvbox/` contains host-side diagnostics for LAN, UART, Android ADB, and
  guarded U-Boot serial workflows.
- `docs/` contains project notes about current bring-up status and publication
  boundaries.
- Local tool runs write logs under `logs/` by default, but that runtime output
  is intentionally not tracked in git.

## Diagnostics

Copy `.env.example` to `.env` or export the same variables in your shell before
using the host-side tools:

```bash
cp .env.example .env
set -a
. ./.env
set +a
tools/tvbox/tvbox-remote.sh all all
```

The remote workflow expects `sshpass` or `expect` on the host. The Windows
`com6-*` helpers require WSL with `powershell.exe` and a Windows COM port.

## Included Payload

- Armbian board file: `userpatches/config/boards/vontar-h618.tvb`
- Kernel DTS patches: `userpatches/kernel/vontar-h618/`
- U-Boot bring-up patches: `userpatches/u-boot/v2025-sunxi/board_vontar-h618/`
- Optional MAC override example: `userpatches/overlay/etc/modprobe.d/sunxi_gmac.conf`
- Board-specific Broadcom firmware payloads: `userpatches/overlay/lib/firmware/brcm/`
- Hardware profile: `userpatches/VONTAR_H618_HARDWARE.md`

## Status

This repository is a board bring-up patch set for reproducible local builds. It
is not an upstream Linux or U-Boot submission series. See
`docs/known-status.md` before using it as a baseline for upstream work.

## Constraints

- Local lab logs, build caches, output images, and other machine-specific
  artifacts are intentionally excluded.
- This repository is a reproducible bring-up baseline, not an upstream-ready
  Linux or U-Boot submission series.
- No default IPs, passwords, UUIDs, or serial port names are embedded in the
  tracked files.
