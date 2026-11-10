# al_eth for Linux 6.18 (Ubiquiti UNVR / Annapurna Labs Alpine V2)

Out-of-tree port of the Annapurna Labs `al_eth` 1G/10G Ethernet driver and the
parts of the Alpine HAL it needs, taken from Ubiquiti's UNVR 1.3.35 GPL release
(kernel 4.1.37), built as a single module `al_eth.ko`.

## Build

Against a kernel tree that has been fully built (so `Module.symvers` exists),
with `CONFIG_ARCH_ALPINE=y`, `CONFIG_PHYLIB` and the PHY driver enabled:

    make KDIR=~/unvr-kernel/linux-6.18.58
    make KDIR=~/unvr-kernel/linux-6.18.58 INSTALL_MOD_PATH=/path/to/rootfs \
         -C ~/unvr-kernel/linux-6.18.58 M=$PWD modules_install

`build-kernel.sh` does this automatically when `AL_ETH_DIR` points here.

## What changed from the vendor code

- Builds the HAL (UDMA, IOFIC, serdes, group link-management) into the module;
  the vendor `arch/subsys/fs_initcall`s run from `al_eth_hal_init()` instead.
- Mainline 6.18 API: MDIO C22/C45 split accessors, `mdiobus_get_phy()`,
  link-mode bitmaps, `ethtool_link_ksettings`, new coalesce/ringparam/rxfh/EEE
  callbacks, `ndo_select_queue`/`ndo_get_stats64`/`ndo_tx_timeout` signatures,
  `ndo_eth_ioctl`, `eth_hw_addr_set()`, `dma_set_mask()`, MSI-X range API,
  `netif_napi_add_weight()`, `skb_frag_off_add()`, ktime.
- Ubiquiti's RTL83xx switch netdev hook is compiled out (`HAVE_RTL83XX_OPS`).
- Serdes tuning no longer `BUG()`s without the vendor thermal driver; it
  assumes 50 C when no thermal zone exists.
- `MODULE_SOFTDEP("pre: marvell realtek")` so the PHY driver binds first.
- PHY connected as `rgmii-id` (UNVR's RTL8211F must add TX+RX delays; mainline
  programs them, the vendor kernel didn't) — override with `phy_mode=`.
- EEE disabled on the PHY by default (`eee=1` to re-enable): the MAC doesn't
  handle LPI wake-up and silently loses frames after idle.

## al_sgpo.ko

Also builds `al_sgpo.ko`, a port of Ubiquiti's Alpine SGPO (serial GPIO output)
driver. On the UNVR its lines drive the per-bay SATA activity LEDs.

## Licensing

Driver files are GPL; most HAL files are GPL-2.0/BSD/commercial tri-licensed.
`include/soc/alpine/al_serdes.h` carries an Annapurna-commercial-only header and
three HAL files carry no header.
