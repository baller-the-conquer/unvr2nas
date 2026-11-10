# unvr2nas
Turning a UNVR to a (kinda decent) NAS 

## Synapsis

Replacing UniFi OS on a **UNVR** with **Alpine Linux** running a current mainline
kernel (**6.18 LTS**), and turning it into a 4-bay NAS: btrfs array and a NFS
server.


||Stock|This project|
|-|-|-|
|Kernel|4.1.37 (vendor)|6.18.58 (mainline + out-of-tree `al_eth`)|
|OS|UniFi OS (Debian based)|Alpine Linux 3.23 (OpenRC, musl)|
|Root filesystem|eMMC|eMMC, so all 4 bays are free for data|
|Use|NVR only|NAS: btrfs, NFS, and more!|

> [!WARNING]
> This erases UniFi OS from the internal eMMC. **Back up the SPI
> flash and the eMMC from the stock OS first.** You need a 3.3 V UART adapter on
> the board's serial header to talk to U-Boot.

## Hardware

- **SoC:** Annapurna Labs Alpine V2 (AL-324), 4× Cortex-A57 @ 1.7 GHz
- **RAM:** 4 GB
- **Storage:** 4× SATA bays (2 AHCI controllers), internal eMMC on a USB bridge
  behind the external PCIe port
- **Network:** 1 GbE (Alpine `al_eth` MAC + Realtek RTL8211F PHY over RGMII)
- **Misc:** S35390A RTC, ADT7475 fan/temperature controller, PCA9575 GPIO
  expander (bay fault LEDs), SGPO serial GPIO (bay activity LEDs), front logo
  LEDs
- **Bootloader:** U-Boot 2015.07 (`ALPINE_UBNT_NAS_ALL`) in SPI flash. It boots
  legacy uImages only (no FIT support).

## What works

- [x] Mainline 6.18 kernel boots from U-Boot (legacy uImage)
- [x] Gigabit Ethernet: ported `al_eth` driver, ~940 Mbit/s, no packet loss
- [x] All 4 SATA bays, hot-plug presence
- [x] Root filesystem on the internal eMMC
- [x] Clean `reboot` (SP805 watchdog)
- [x] RTC (`hwclock`)
- [x] Fan control: ADT7475 hardware auto curve, 40 → 65 °C
- [x] Front logo LEDs (white/blue), bay activity and fault LEDs
- [x] Temperature and fan sensors (`sensors`), drive temperatures (`drivetemp`)
- [x] btrfs RAID across the 4 bays, NFS export

### Known issues

- `al_eth` reports byte counters from 32-bit hardware registers, so the rx/tx
  byte totals in `ip -s link` wrap at 4 GiB. Traffic itself is unaffected.
- U-Boot's `scsi init` sees only the first AHCI controller (bays 3 and 4), and
  only after a cold boot. That is why `/boot` lives on the eMMC.

## Repository layout

```
build-kernel.sh    Cross-compile 6.18 + modules, wrap as a uImage
build-rootfs.sh    Build a RAM-boot Alpine rootfs (first boot / rescue)
al_eth-6.18/           Out-of-tree al_eth Ethernet + al_sgpo drivers, ported to 6.18
unvr-leds/
  unvr-dtb.sh          Build /boot/unvr.dtb from the running device tree (LEDs, PCIe fixes)
  bayleds.sh/.initd    Bay LEDs: on when a disk is present, blink on I/O
  emmc-install.sh      Move the running system onto the internal eMMC
```
## Building (on an x86_64 Linux host)

Tested on Arch Linux:

```sh
sudo pacman -S --needed aarch64-linux-gnu-gcc base-devel bc flex bison openssl \
    libelf cpio xz uboot-tools dtc squashfs-tools qemu-user-static qemu-user-static-binfmt
```
### Kernel and drivers

```sh
WORK=$HOME/unvr KLOCALVERSION=-unvr AL_ETH_DIR=$PWD/al_eth-6.18 ./build-kernel.sh
```
The script downloads Linux 6.18.58 and starts from Alpine's `linux-lts` aarch64
config. It then:

- builds in what the board needs to boot without an initramfs: `ARCH_ALPINE`, `
  PCIE_AL`, `PCI_HOST_GENERIC`, AHCI, ext4, USB storage, `ARM_SP805_WATCHDOG`
- disables Xen, because the vendor DT has an empty `/hypervisor` node that
  crashes the kernel
- builds the board drivers as modules: DesignWare I²C, PCA954x mux, S35390A
  RTC, PCA953x GPIO, ADT7475, drivetemp

It outputs:

- `~/tftp/uImage`: the kernel, load/entry address `0x30000000`. It must stay
  clear of ramoops at `0x12000000`.
- `$WORK/modules-6.18.58-unvr/lib/modules/6.18.58-unvr`: the modules, including `
  al_eth.ko` and `al_sgpo.ko`

### Rescue rootfs (optional)

```sh
sudo MODULES_DIR=$HOME/unvr/modules-6.18.58-unvr/lib/modules VER=v3.23 \
     HOSTNAME_=unvr ./build-rootfs.sh
```
This builds `~/tftp/rootfs.uImage`, an Alpine rootfs that runs entirely from
RAM. Use it for the first boot and for recovery.

## Booting

### First boot over TFTP

If you dont have a TFTP server, follow this guide if you are on Arch Linux: https://wiki.archlinux.org/title/TFTP

Serve `~/tftp` from the build host, then at the U-Boot prompt:

```
setenv serverip {YOUR TFTP SERVER IP}
setenv ipaddr {YOUR OWN IP ADDRESS FOR NAS}
tftpboot 0x30000000 uImage
tftpboot 0x20000000 rootfs.uImage
fdt addr ${fdtaddr}                      # wherever your env loads the vendor DT
fdt rm /hypervisor
fdt set /soc/pcie-internal compatible "pci-host-ecam-generic"
setenv bootargs console=ttyS0,115200 rdinit=/sbin/init
bootm 0x30000000 0x20000000 ${fdtaddr}
```
> \[!TIP] U-Boot's console drops characters when you paste long lines. Put
> commands in a `boot.scr` (`mkimage -A arm64 -T script -C none -d boot.cmd
> boot.scr`) and `source` it.

### Device tree

Mainline needs a few changes to the vendor device tree. Run this once on the
UNVR:

```sh
apk add dtc
PCIE_EXT=1 sh unvr-dtb.sh     # writes /boot/unvr.dtb
sync
```
It changes the following:


|Node|Change|
|-|-|
|`/hypervisor`|removed (Xen probe crash)|
|`/soc/pcie-internal`|`pci-host-ecam-generic` (SATA controllers, Ethernet)|
|`/soc/pcie-external0`|described for mainline `pcie-al` (USB → internal eMMC)|
|I²C mux|`nxp,pca9546`|
|`/soc/leds`|logo white `default-on`, blue free for userspace|
|`/soc/leds-bays`|new: `bayN:activity` (SGPO) and `bayN:fault` (PCA9575)|

The script can be run again safely.

### Installing to the eMMC

Boot from a disk or the RAM rootfs. Install `/boot/uImage` and `/boot/unvr.dtb`,
then:

```sh
sh emmc-install.sh /dev/sdX     # the ~29 GB eMMC. ERASES UniFi OS.
```
The script partitions the eMMC (512 MiB `/boot` plus root, both ext4) and copies
the running system over. It also writes an fstab that uses UUIDs and a `boot.scr`
for U-Boot. Then point U-Boot's autoboot at it:

```
setenv emmcscr 'usb start; ext4load usb 0:1 ${loadaddr} /boot.scr && source ${loadaddr}'
setenv ssdscr  'scsi init; ext4load scsi 0:1 ${loadaddr} /boot.scr && source ${loadaddr}'
setenv bootcmd 'run emmcscr; run ssdscr; run bootcmdrecovery'
saveenv
```
## System setup

### Modules (`/etc/modules`)

```
gpio-pl061
al_sgpo
leds-gpio
i2c-designware-platform
i2c-mux-pca954x
rtc-s35390a
gpio-pca953x
adt7475
drivetemp
btrfs
```
`al_eth` loads automatically. Its module parameters:


|Parameter|Default|Meaning|
|-|-|-|
|`phy_mode`|`rgmii-id`|The RTL8211F needs both RGMII delays. Other modes cause RX alignment errors.|
|`eee`|`0`|Energy-Efficient Ethernet. The MAC loses frames on LPI wake-up, so it is off.|

### Bay LEDs

```sh
install -m755 unvr-leds/bayleds.sh /usr/local/sbin/bayleds
install -m755 unvr-leds/bayleds.initd /etc/init.d/bayleds
rc-update add bayleds default
```
Bay to libata port mapping, taken from the vendor DT:


|Bay|1|2|3|4|
|-|-|-|-|-|
|Port|ata7|ata5|ata1|ata3|
|Activity (SGPO line)|22|20|16|18|
|Fault (PCA9575 pin)|12|13|14|15|

> \[!CAUTION] PCA9575 pins 0–3 switch bay **power**. Don't touch them.

To turn off the front logo, write `none` to `/sys/class/leds/ulogo_white/trigger`
and `0` to its `brightness`.

### Storage

```sh
mkfs.btrfs -L Files -d raid0 -m raid1 /dev/sd[abcd]
echo 'LABEL=Files /mnt/files btrfs noatime,compress=zstd:1,nofail 0 0' >> /etc/fstab
```
Add a small OpenRC service that runs `btrfs device scan` before `localmount`.
Without it, the multi-device filesystem won't mount at boot.

Lower the writeback limits so large copies stream steadily instead of stalling
on big flushes:

```
# /etc/sysctl.d/90-writeback.conf
vm.dirty_background_bytes = 67108864
vm.dirty_bytes = 268435456
vm.dirty_expire_centisecs = 1000
```
### NFS

```
# /etc/exports
/mnt/files/data *(rw,async,nohide,no_subtree_check,fsid=0)
```
Client:

```sh
mount -t nfs -o nconnect=4,rsize=1048576,wsize=1048576 unvr:/ /mnt/nas
```
## Porting notes

- `Wrong Image Format` `CONFIG_FITImage` `Image`
-  `0x12000000`
- `/hypervisor`
-  `pci-host-ecam-generic`
- `al_eth`  `ethtool_link_ksettings` 
  [al_eth-6.18/README.md](al_eth-6.18/README.md)
- `reboot` 
-  `pcie-al`Why each fix was needed FIT images fail with . U-Boot 2015.07 is
  built without. The fix is a legacy uImage built from the raw . Alpine's
  kernelis an EFI zboot, so the raw has to be extracted from it first.Hang at
  "Starting kernel". The default load address overlapped ramoops at.NULL
  dereference in Xen init. The vendor DT has an empty node.No PCI devices. The
  internal "PCIe" is a fixed ECAM bus, so drives it.Ethernet. Mainline has no
  driver. Ubiquiti's 4.1 driver and the AlpineHAL were ported to 6.18 (MDIO
  C22/C45 split, link-mode bitmaps,, MSI-X range API, and more). See. hangs.
  The board resets through the SP805 watchdog, which must bebuilt in.eMMC not
  visible. It sits behind a USB controller on the external PCIe port,which
  needs its own DT description for .

## Licensing and sources

- Kernel changes and the `al_eth`/`al_sgpo` drivers are derived from Ubiquiti's
  GPL source release for the UNVR (kernel 4.1.37) and are distributed under **
  GPL-2.0**.
- Most Annapurna HAL files are GPL-2.0/BSD tri-licensed. A few files carry an
  Annapurna-commercial header or no header at all; see `al_eth-6.18/README.md`.
- Scripts and web UI: GPL-2.0 unless noted otherwise.

Not affiliated with or endorsed by Ubiquiti Inc. or Amazon/Annapurna Labs.
"UniFi" and "UNVR" are trademarks of Ubiquiti Inc.

## Credits

- Ubiquiti, for the GPL source release
- The [Alpine Linux](https://alpinelinux.org) project and its `linux-lts` config
- The mainline Linux maintainers of `ARCH_ALPINE` and `pcie-al`
- Claude AI for writing build scripts and a (tee) bit of debugging 
