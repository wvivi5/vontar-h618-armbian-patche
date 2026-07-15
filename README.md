# Vontar H618 Armbian Patches

Public Armbian `userpatches` payload and host-side bring-up tools for Vontar
H618 and similar H616-class Allwinner TV boxes.

The project goal is to boot Armbian from microSD with a dedicated project
U-Boot/SPL path instead of relying on the stock Android or eMMC boot chain.

## Board Photos

These photos document the tested board variant targeted by this payload.
See [VONTAR_H618_HARDWARE.md](userpatches/VONTAR_H618_HARDWARE.md) for full hardware details.

<table>
  <tr>
    <td align="center">
      <img src="userpatches/vontar-h618-frontside.jpg" alt="Vontar H618 board front side" width="420">
      <br>
      <sub>Front side</sub>
    </td>
    <td align="center">
      <img src="userpatches/vontar-h618-backside.jpg" alt="Vontar H618 board back side" width="420">
      <br>
      <sub>Back side</sub>
    </td>
  </tr>
</table>

## Validated Setup

- Validated target: one 4 GiB DDR3 Vontar H618 unit
- Boot path: microSD with project U-Boot/SPL
- Kernel line: Armbian `current` and `edge`
- LAN bring-up: depends on the matching U-Boot preinit sequence in this repo
- Current U-Boot boot policy: deterministic default environment, no FAT
  `uboot.env` dependency, no UART abort window, and a minimal microSD command.
- The board explicitly selects Armbian's ARM64 `boot-sun50i-next.cmd`. It loads
  `Image` and the board DTB and maps `console=display` to `console=tty1`.

## Quick Start

Clone this repository next to an Armbian build checkout and link its
`userpatches/` directory into the build tree:

```bash
git clone https://github.com/aco-art/vontar-h618-armbian-patche.git
git clone https://github.com/armbian/build.git armbian-build

cd armbian-build
rm -rf userpatches
ln -s ../vontar-h618-armbian-patche/userpatches userpatches

./compile.sh BOARD=vontar-h618 BRANCH=current RELEASE=trixie \
  BUILD_DESKTOP=no BUILD_MINIMAL=yes KERNEL_CONFIGURE=no
```

`rm -rf userpatches` removes the existing `userpatches/` directory inside the
Armbian build checkout before replacing it with the symlink above.

The board configuration currently expects:

- U-Boot defconfig: `vontar_h618_zero2w_defconfig`
- Linux DTB: `allwinner/sun50i-h618-vontar-h618.dtb`
- U-Boot branch: `tag:v2025.04`
- U-Boot boot command: load `/boot/boot.scr` from microSD `mmc 0:1`

The same payload was also build-tested with `current/bookworm`, `edge/noble`,
and `edge/resolute`; see [known-status.md](docs/known-status.md) for the exact
kernel versions and hardware-validation boundary.

Board-specific Broadcom firmware payloads are included under
`userpatches/overlay/lib/firmware/brcm/`. If you redistribute this repository
or derived images, verify that the firmware licensing terms are acceptable for
your use.

## Current Boot Notes

- Armbian sunxi sets `BOOTDELAY=1` by default, which allows UART noise to abort
  autoboot and drop to the U-Boot prompt before `bootcmd` runs.
- The Vontar board hook overrides that to `BOOTDELAY=-2`; U-Boot then runs
  `bootcmd` without checking for abort input.
- The board defconfig uses `CONFIG_ENV_IS_NOWHERE=y` and disables FAT env, so
  the build uses the compiled default environment and lets Armbian's
  `/boot/boot.scr` read `/boot/armbianEnv.txt`.
- The minimal boot command sets `devtype`, `devnum`, and `prefix`, then sources
  Armbian's generated `/boot/boot.scr` from `mmc 0:1`.
- The board override is copied from maintained `boot-sun50i-next.cmd` and only
  separates its console mapping. Production `display` excludes `ttyS0`; debug
  `both` still enables it.

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
- Restored H618 LAN driver: `userpatches/kernel/vontar-h618/0004-driver-allwinner-h618-emac-restore-sunxi-gmac.patch`
- Optional manual MAC override: `userpatches/overlay/etc/modprobe.d/sunxi_gmac.conf`
  (normally unnecessary because `sunxi-gmac` derives a stable address from SID)
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
