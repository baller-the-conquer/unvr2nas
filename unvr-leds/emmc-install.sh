#!/bin/sh
# Move the running Alpine install (booted from the SSD) onto the UNVR's internal eMMC.
#   sh emmc-install.sh /dev/sdX        (the eMMC: ~29 GB, on USB)
# ERASES the eMMC (stock UniFi OS).  Keep your eMMC backup image safe first.
set -e
DEV=$1
die() { echo "ERROR: $*" >&2; exit 1; }
[ "$(id -u)" = 0 ] || die "run as root"
[ -b "$DEV" ] || die "usage: $0 /dev/sdX (the eMMC)"
B=${DEV##*/}

# --- safety checks --------------------------------------------------------
case "$(readlink -f /sys/block/$B)" in */usb*) ;; *) die "$DEV is not on USB - not the eMMC";; esac
SIZE=$(( $(cat /sys/block/$B/size) / 2048 / 1024 ))
[ "$SIZE" -ge 8 ] && [ "$SIZE" -le 64 ] || die "$DEV is ${SIZE} GiB - doesn't look like the eMMC"
ROOTDEV=$(findmnt -no SOURCE /)
case "$ROOTDEV" in $DEV*) die "$DEV holds the running root filesystem";; esac
grep -q "^$DEV" /proc/mounts && die "a partition of $DEV is mounted"
zcat /proc/config.gz 2>/dev/null | grep -q '^CONFIG_USB_STORAGE=y' || \
	die "running kernel doesn't have USB storage built in - install/boot the new kernel first"

DTB=
for f in /boot/unvr.dtb /boot/unvr-pcie.dtb; do
	[ -f "$f" ] && [ "$(fdtget "$f" /soc/pcie-external0 compatible 2>/dev/null)" = amazon,al-alpine-v2-pcie ] && { DTB=$f; break; }
done
[ -n "$DTB" ] || die "no DTB with the pcie-external0 rewrite (run: PCIE_EXT=1 sh unvr-dtb.sh)"
command -v rsync >/dev/null || apk add rsync
command -v mkimage >/dev/null || apk add u-boot-tools

echo "Target: $DEV (${SIZE} GiB, $(cat /sys/block/$B/device/model 2>/dev/null))"
lsblk "$DEV"
printf 'This ERASES %s. Type ERASE to continue: ' "$DEV"; read -r ans
[ "$ans" = ERASE ] || die "aborted"

# --- partition + format ---------------------------------------------------
sfdisk -q "$DEV" <<SF
label: gpt
size=512MiB, type=L, name=boot
type=L, name=root
SF
sleep 2; mdev -s 2>/dev/null || true
P1=${DEV}1; P2=${DEV}2
mkfs.ext4 -q -F -L emmc-boot -O ^metadata_csum,^64bit,^orphan_file "$P1"
mkfs.ext4 -q -F -L emmc-root -E lazy_itable_init=0,lazy_journal_init=0 "$P2"

# --- copy -----------------------------------------------------------------
M=/mnt/emmc
mkdir -p $M && mount "$P2" $M
mkdir -p $M/boot && mount "$P1" $M/boot
echo ">>> copying root filesystem"
rsync -aHAX --one-file-system --info=progress2 --exclude=/boot/ / $M/
rsync -a --exclude=boot.scr --exclude='*.dtb*' --exclude=lost+found /boot/ $M/boot/
cp "$DTB" $M/boot/unvr.dtb
for d in proc sys dev run tmp mnt data boot; do mkdir -p $M/$d; done
chmod 1777 $M/tmp

# --- fstab: root/boot by UUID, other mounts kept but made nofail ----------
RU=$(blkid -s UUID -o value "$P2"); BU=$(blkid -s UUID -o value "$P1")
RPU=$(blkid -s PARTUUID -o value "$P2")
{
	echo "UUID=$RU  /      ext4  defaults,noatime  0 1"
	echo "UUID=$BU  /boot  ext4  defaults,noatime  0 2"
	awk '$1 !~ /^#/ && NF >= 4 && $2 != "/" && $2 != "/boot" {
		if ($4 !~ /nofail/) $4 = $4 ",nofail"; print }' /etc/fstab
} > $M/etc/fstab

# --- U-Boot script on the eMMC --------------------------------------------
cat > /tmp/emmc-boot.txt <<BS
usb start
ext4load usb 0:1 \${loadaddr_dt} /unvr.dtb
fdt addr \${loadaddr_dt}
ext4load usb 0:1 \${loadaddr_payload} /uImage
setenv bootargs console=ttyS0,115200 root=PARTUUID=$RPU rootwait
bootm \${loadaddr_payload} - \${loadaddr_dt}
BS
mkimage -q -A arm64 -T script -C none -d /tmp/emmc-boot.txt $M/boot/boot.scr

sync
umount $M/boot $M
sync
echo
echo ">>> Done. eMMC root PARTUUID=$RPU"
echo "Now set the U-Boot boot order (eMMC first, SSD second, SPI recovery last)."
