# Validated Status — Hardware/OS Complete

Hardware and OS bring-up is complete for the photographed 4 GiB DDR3 Vontar
H618 unit as of 2026-07-15. There is no active validation blocker for that
device; the detailed limits below prevent this result from being generalized
to untested RAM sizes or board revisions.

## Completion Scope

- Project U-Boot/SPL boots Armbian independently from microSD.
- The deployed eMMC boots Linux by default from a 30.9 GiB root partition
  while preserving the original Android partitions and 24 GiB userdata.
- A fullscreen English HDMI menu defaults to Linux after 8 seconds. Android is
  an explicit one-boot selection; its next reboot returns to Linux.
- Native Ethernet, Wi-Fi, Bluetooth discovery, HDMI/display, stock IR remote,
  console OK/Enter, and safe two-stage Power handling are runtime validated.
- No further rebuild, reflash, DTB change, or routine hardware validation is
  required. Only a verified regression should reopen bring-up work.

## Current State

- Validated target: 4 GiB DDR3 Vontar H618 unit documented in
  `userpatches/VONTAR_H618_HARDWARE.md`
- Public build path: microSD with project U-Boot/SPL
- Kernel line target: Armbian `current` and `edge` for the Vontar board file
- LAN bring-up depends on the matching U-Boot preinit sequence in this payload
- Linux 7.0.14/Noble runtime is validated with restored `sunxi-gmac`: PHY
  `0x00441400`, carrier `1`, `100Mbps/Full`, and working network traffic.
- The published Linux DTS/DTB remains unchanged. The board `.tvb` selects the
  legacy sunxi-gmac/EPHY path and disables the conflicting AC300/DWMAC patches.
- MAC is deterministically derived from the SoC SID and remains stable across
  reboots. No crypto-provider ordering is required.
- Kernel packages and minimal images are built with one patch payload for the
  following combinations. All contain the GMAC/EPHY/AC200 modules and board
  DTB.

| Branch | Release | Built kernel | Build | Hardware runtime |
| --- | --- | --- | --- | --- |
| `current` | Bookworm | 6.18.38 | pass | not repeated |
| `current` | Trixie | 6.18.38 | pass | pass, clean image |
| `edge` | Noble | 7.0.14 | pass | pass |
| `edge` | Resolute | 7.0.14 | pass | not repeated |

- Two additional 7.0.14 boots on 2026-07-14 kept the same SID-derived MAC,
  carrier, 100Mbps/full link, and native-LAN traffic. A clean 6.18.38/Trixie
  run on 2026-07-15 independently confirmed the same native `end0` path.
- Stock remote IR is validated on 2026-07-15. Raw capture identified all 12
  physical NEC address-`0x01` buttons. The dedicated keymap was loaded and
  left/right/OK were confirmed as post-map evdev events from `sunxi-ir`.
- New images install `ir-keytable`, `python3-evdev`, and both Vontar input
  services automatically. The earlier `rc-beelink-gs1` assumption is rejected.
- OK is `KEY_ENTER`. Power is `KEY_PROG1`: on a text shell the root helper
  types `poweroff` without Enter; on a graphical VT it forwards virtual
  `KEY_POWER`. Console and graphical branches passed runtime checks without
  executing poweroff or restarting the console.
- A physical stock-remote test on the text console confirmed the final safety
  behavior: pressing Power only fills `poweroff`; the box remains running
  until the user explicitly confirms it with OK/Enter.

## Active U-Boot Boot Policy

- U-Boot v2025.04 is built from `vontar_h618_zero2w_defconfig`.
- The default environment is compiled in; FAT `uboot.env` is intentionally not
  used.
- `BOOTDELAY=-2` is required for this board because UART noise can otherwise
  abort autoboot during the countdown before `bootcmd` runs.
- Boot explicitly loads `/boot/boot.scr` from microSD `mmc 0:1` and supplies
  the `devtype`, `devnum`, and `prefix` variables expected by that script.
- Built images force `console=display` through `DEFAULT_CONSOLE`.
- The board uses an ARM64 `boot-sun50i-next.cmd` override, which loads `Image`
  and DTB; its only functional difference is `display` mapping to `tty1`.
- Linux DTS/DTB is not changed by this boot-policy fix.

## Recent Debug Markers

- `P6134`: proved that default env and explicit bootcmd were present, but
  `BOOTDELAY=1` still allowed UART input/noise to abort autoboot.
- `Pa852`: proved `BOOTDELAY=-2` gets past UART abort and that manually sourcing
  Armbian `boot.scr` is fragile without the distro-boot environment.
- `P8b1e`: rejected; a copied legacy script skipped DTB loading and requested
  `/boot/uImage`. This was a boot-script regression, not a kernel/DTB failure.

## Boundaries

- This repository is for reproducible local builds and diagnostics.
- It is not a claim of upstream readiness for Linux, U-Boot, or Armbian.
- Board-specific firmware payloads are currently included in this repository for
  bring-up convenience.
- Other RAM sizes and board revisions are not yet fully validated.
- The IR table targets the photographed/tested 12-button remote. A different
  bundled handset may use another NEC address or command set.
- A completed `poweroff` cannot wake by IR and still requires physical power.
- Optional applications and services are outside the hardware/OS completion
  status.

## Before Upstreaming

- Split board-specific bring-up changes into reviewable topic series.
- Revalidate naming, bindings, and DTS structure against current upstream trees.
- Recheck redistribution and attribution requirements for any firmware payloads.
