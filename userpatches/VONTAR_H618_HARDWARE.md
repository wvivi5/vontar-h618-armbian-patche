# Vontar H618 Hardware Profile

This file documents the tested Vontar H618 / H616-class TV box that this
`userpatches` payload targets.

## Board Identity

| Field | Value |
| --- | --- |
| Board | Vontar H618 TV box |
| Runtime/vendor identity | `apollo-p16` on the tested unit |
| SoC class | Allwinner H616-class, marketed as H618 |
| Validated DRAM variant | 4 GiB DDR3, 648 MHz |
| Boot goal | Armbian from microSD with project U-Boot/SPL |
| Android/eMMC boot chain | Not required for the Armbian boot path |
| Linux DTB | `allwinner/sun50i-h618-vontar-h618.dtb` |
| Armbian board file | `userpatches/config/boards/vontar-h618.tvb` |

## Memory Compatibility

This payload is validated on the 4 GiB DDR3 Vontar H618 box.

- U-Boot config selects the H616 DDR3 profile and DRAM clock:
  `CONFIG_SUNXI_DRAM_H616_DDR3_1333=y` and `CONFIG_DRAM_CLK=648`.
- U-Boot config also carries board-specific DRAM drive/ODT/TPR values.
- The Linux DTS in this payload does not hardcode a fixed `memory@...` size.
  Linux receives the detected RAM size from U-Boot/FDT.
- 1 GiB and 2 GiB variants may work if they use the same DDR3 wiring, voltage,
  timing class, and board layout with lower-density RAM chips.

## Power

| Field | Value |
| --- | --- |
| PMIC silicon observed at runtime | X-Powers AXP1530 |
| PMIC runtime endpoint | Android `i2c-5 / 5-0036`, `reg = <0x36>` |
| DT binding used by current Linux/U-Boot trees | `x-powers,axp313a` |
| DC input rail | `reg_vcc5v` / `vcc-5v`, fixed 5.0 V |
| USB1 VBUS rail | `reg_usb1_vbus` / `usb1-vbus`, fixed 5.0 V |
| CPU rail | `reg_dcdc2` / `vdd-cpu`, programmable 0.81-1.16 V |
| GPU/system rail | `reg_dcdc1` / `vdd-gpu-sys`, programmable 0.81-1.16 V |
| DRAM rail | `reg_dcdc3` / `vdd-dram`, fixed 1.5 V |
| 1.8 V rail | `reg_aldo1` / `vcc1v8`, fixed 1.8 V |
| 3.3 V rail | `reg_dldo1` / `vcc3v3`, fixed 3.3 V |
| Wi-Fi/BT power rail | `reg_vcc_wifi` / `vcc-wifi`, fixed 3.3 V via `PG18 WL_REG_ON` |
| U-Boot LAN PHY supply in this payload | `phy-supply = <&reg_dldo1>`, 3.3 V |

## Boot, Storage, And UART

| Field | Value |
| --- | --- |
| Boot console | UART0 / `serial@5000000` / 115200 8N1 |
| Boot console pins | `PH0/PH1` |
| Linux default console | display/HDMI only; UART0 is not a default Linux system console |
| Bluetooth host UART | UART1 / `serial@5000400` / `ttyS1` |
| UART1 pins | `PG6..PG9` |
| microSD | `mmc0` / `mmc@4020000`, probed even with unreliable U-Boot card-detect |
| SDIO Wi-Fi | `mmc1` / `mmc@4021000` |
| eMMC | `mmc2` / `mmc@4022000` |

## U-Boot Boot Policy

- The project U-Boot uses a compiled default environment; FAT `uboot.env` is
  disabled on purpose.
- `BOOTDELAY=-2` is required on the tested board so UART noise cannot abort
  autoboot before `bootcmd` runs.
- Boot explicitly loads `/boot/boot.scr` from microSD and supplies the
  `devtype`, `devnum`, and `prefix` variables required by Armbian.
- Linux images use the ARM64 `boot-sun50i-next.cmd` flow with `console=display`
  mapped to HDMI/display only. Use `console=both` for UART0 debug.
- Full install-to-eMMC still needs runtime Linux validation after normal boot.

## Built-In Ethernet

| Field | Value |
| --- | --- |
| MAC node | EMAC1 / `ethernet@5030000` / `0x05030000` |
| Linux interface on validated image | `end0` |
| Validated link state | `Link is Up - 100Mbps/Full` |
| PHY mode | RMII |
| RMII pins | `PA0..PA9` |
| Linux DTS PHY node | `mdio1/ethernet-phy@0`, `reg = <0>` |
| Working Linux attach path | `5030000.ethernet-0:00`, `PHYAD 0`, Generic PHY |
| Linux network driver | `sunxi_geth` (`sunxi-gmac`) |
| Additional MDIO responder | address `0x10` / decimal `16` responds on the bus |
| Empty MDIO address | decimal `10` |
| IRQ | `GIC_SPI 15 IRQ_TYPE_LEVEL_HIGH`; Linux IRQ observed as `47` |
| Reset | `RST_BUS_EMAC1` |
| Bus clock | `CLK_BUS_EMAC1` |
| U-Boot EMAC1 syscon offset | `0x34` |
| Runtime transceiver type | external transceiver |

## LAN Integration In This Payload

LAN bring-up is intentionally split into two stages. The kernel part depends on
the board being prepared by the project U-Boot first.

### Stage 1: U-Boot Preinit

- U-Boot board config is `vontar_h618_zero2w_defconfig`.
- U-Boot board DTS models Vontar H618, EMAC1/RMII, `mmc0`, `mmc2`, UART0,
  HDMI, USB, PMIC rails, and `phy-supply = <&reg_dldo1>` for the LAN path.
- `CONFIG_I2C3_ENABLE=y`, `CONFIG_MMC_BROKEN_CD=y`, `CONFIG_SUN8I_EMAC=y`,
  and `CONFIG_PHY_REALTEK=y` are part of the working U-Boot defconfig.
- U-Boot MMC logic keeps probing `mmc0` even when card-detect is unreliable.
- U-Boot adds the H616 EMAC1 driver variant with syscon offset `0x34` and the
  `emac1` pinctrl function for `PA0..PA9`.
- U-Boot enables the H616 I2C3/TWI path on `PA10/PA11/PA12`.
- U-Boot preinit writes the `0x10` companion endpoint before Linux boots.
- U-Boot applies EMAC-related clock/register writes at `0x030017ac`,
  `0x0300a028`, and `0x0300a040`.

### U-Boot Patch Map

| Patch | Role |
| --- | --- |
| `0010` | Adds the Vontar H618 U-Boot board DTS and boot path, including EMAC1/RMII and `phy-supply = <&reg_dldo1>`. |
| `0011` | Adds `vontar_h618_zero2w_defconfig`: DDR3 648 MHz, PMIC/R-I2C, eMMC slot 2, LAN options, `CONFIG_I2C3_ENABLE`, and `CONFIG_MMC_BROKEN_CD`. |
| `0012` | Keeps probing `mmc0` when U-Boot card-detect is unreliable. |
| `0013` | Adds H616 EMAC1 support in U-Boot: driver variant, syscon offset `0x34`, RMII, and `emac1` pinctrl on `PA0..PA9`. |
| `0014` | Adds the Vontar H618 U-Boot binman include path for image generation. |
| `0015` | Adds H616 I2C3/TWI support and preserves the expected I2C bus state before board init. |
| `0016` | Runs Vontar LAN preinit: configures I2C3 pins and writes the `0x10` companion endpoint. |
| `0017` | Applies the EMAC-related clock/register writes used by the working U-Boot path. |

### Stage 2: Linux Kernel Attach

- Linux receives a board state already prepared by U-Boot preinit.
- Kernel DTS exposes EMAC1 as `ethernet@5030000` in RMII mode.
- Kernel DTS exposes the Linux attach PHY as `mdio1/ethernet-phy@0`.
- Kernel config restores `SUNXI_GMAC` with the AC200/MFD/EPHY support modules;
  the board `.tvb` disables the conflicting AC300/DWMAC replacement patches.
- Expected runtime result is `end0` with `Link is Up - 100Mbps/Full`.
- The driver derives a stable locally administered MAC from the SoC SID without
  waiting for a crypto provider. `sunxi_gmac.conf` remains an optional override;
  no personal MAC address is included in this payload.

## Wi-Fi And Bluetooth

| Field | Value |
| --- | --- |
| Wi-Fi runtime interface | `wlan0` |
| Wi-Fi/BT combo family | Broadcom BCM4334 / HS2734C-class module |
| BT compatible | `brcm,bcm4334-bt` |
| BT firmware | `BCM4334B0.vontar,h618.hcd` |
| BT success markers | chip id `68`, `BCM4334B0`, firmware patch load, `BCM4334B1 37.4 MHz ExtLNA Murata VM` |
| Shared Wi-Fi/BT power | `PG18 = WL_REG_ON`, active-high |
| BT device wake | `PG17`, active-high |
| BT host wake | `PG16`, active-high |
| BT reset | `PG19`, active-low reset GPIO |

## Infrared Remote

| Field | Value |
| --- | --- |
| Receiver | `sunxi-ir` / `ir@7040000` |
| Receiver pin | `PH10` / `ir_rx` |
| Protocol | NEC |
| Captured address | `0x01` |
| Persistent table | `/etc/rc_keymaps/vontar-h618.toml` |
| Loader | `vontar-h618-ir.service` |
| Power helper | `vontar-h618-power-key.service` |

The stock 12-button handset is not compatible with `rc-beelink-gs1`. Physical
capture produced the following commands: right `0x50`, left `0x51`, up `0x16`,
down `0x1a`, OK `0x13`, back `0x19`, home `0x11`, menu `0x4c`, mouse/context
`0x00`, volume up `0x18`, volume down `0x10`, and power `0x40`. Linux
`ir-keytable` represents these with the NEC address prefix as `0x150`,
`0x151`, and so on.

The kernel DTS already enables `&ir`; no DTB change is needed. Image
customization installs `ir-keytable`, `python3-evdev`, the table, the
wait-for-`rc0` loader, and both enabled systemd units. OK is mapped to
`KEY_ENTER` for the boot menu and text console.

Power is mapped to `KEY_PROG1` so systemd-logind cannot shut down immediately.
On a text VT with a foreground shell, the root helper clears the line and
types `poweroff` without Enter. On a graphical VT it emits virtual
`KEY_POWER`. Unknown VT modes and missing shells are ignored. A completed
poweroff still requires physical power to start the box again; no IR wakeup is
claimed, and the kernel/DTB remain unchanged.

## Wi-Fi/BT Power Sequence

Wi-Fi and Bluetooth initialization depends on the DTS power bundle, not only on
the UART Bluetooth node. Keep these pieces together:

- `reg_vcc_wifi` / `vcc-wifi` is a fixed 3.3 V regulator controlled by `PG18 WL_REG_ON`.
- `PG18 WL_REG_ON` is an active-high enable GPIO on the PG bank, marked `enable-active-high`, and kept `regulator-always-on`.
- The PG GPIO bank is modeled with `vcc-pg-supply = <&reg_dldo1>`; in this DTS that means the PG control lines are supplied from the fixed 3.3 V rail.
- `wifi_pwrseq` uses `mmc-pwrseq-simple` with `CLK_OSC32K_FANOUT` as `ext_clock`.
- `wifi_pwrseq` applies `x32clk_fanout_pin` through pinctrl.
- `mmc1` uses `vmmc-supply = <&reg_dldo1>` at 3.3 V,
  `vqmmc-supply = <&reg_vcc_wifi>` at 3.3 V, and
  `mmc-pwrseq = <&wifi_pwrseq>`.
- UART1 Bluetooth uses the same 32 kHz fanout as `lpo`.
- UART1 Bluetooth `vbat-supply` and `vddio-supply` come from `reg_dldo1`, fixed 3.3 V.
- `PG17` is BT device-wakeup, active-high GPIO on the PG bank.
- `PG16` is BT host-wakeup, active-high GPIO on the PG bank.
- `PG19` is BT reset, active-low GPIO on the PG bank.
- Do not replace this with a standalone BT `shutdown-gpios` model. The working model is shared Wi-Fi/BT 
  power ownership through `PG18` plus the 32 kHz pwrseq/fanout path, then UART1 BT reset/wake lines.

## Firmware Files

The public repository currently ships the board-specific Broadcom firmware
payloads under:

```text
userpatches/overlay/lib/firmware/brcm/
```

Expected filenames for the board-specific install hook:

```text
BCM4334B0.vontar,h618.hcd
brcmfmac4334-sdio.vontar,h618.bin
brcmfmac4334-sdio.vontar,h618.txt
```

The current payload does not require `brcmfmac4334-sdio.vontar,h618.clm_blob`.
If you republish this repository or redistribute built images, confirm that the
firmware licensing and attribution requirements are acceptable for your use.

## Not Included

- No overclock DTBO files are part of the active payload.
- No `brcmfmac4334-sdio.vontar,h618.clm_blob`.
- No personal MAC address.
