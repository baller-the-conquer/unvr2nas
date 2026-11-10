#!/bin/sh
# Build /boot/unvr.dtb for Alpine on the Ubiquiti UNVR from the running device tree.
# Adds the bay activity (SGPO) and fault (PCA9575) LEDs, fixes compatibles mainline
# needs, and strips per-boot leftovers.  Run on the UNVR:  apk add dtc && sh unvr-dtb.sh
set -e
OUT=${1:-/boot/unvr.dtb}
SRC=${SRC:-/sys/firmware/fdt}
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT

dtc -q -I dtb -O dts -o "$T/a.dts" "$SRC"
# Drop memreserve entries U-Boot added for this boot (initrd, fdt); keep firmware's first 1 MiB
grep -v '^/memreserve/' "$T/a.dts" | sed '1a /memreserve/ 0x0000000000000000 0x0000000000100000;' > "$T/b.dts"
dtc -q -I dts -O dtb -p 8192 -o "$T/u.dtb" "$T/b.dts"
D="$T/u.dtb"

for p in bootargs linux,initrd-start linux,initrd-end; do fdtput -d "$D" /chosen "$p" 2>/dev/null || true; done
fdtput -r "$D" /hypervisor 2>/dev/null || true
fdtput -t s "$D" /soc/pcie-internal compatible pci-host-ecam-generic
fdtput -t s "$D" /soc/i2c-pld/i2c_mux@71 compatible nxp,pca9546

# External PCIe (USB controller -> internal eMMC): describe it for mainline's pcie-al
# driver.  Opt-in (PCIE_EXT=1) until tested on hardware.
if [ "${PCIE_EXT:-0}" = 1 ]; then
	P=/soc/pcie-external0
	fdtput -t s "$D" $P compatible amazon,al-alpine-v2-pcie
	fdtput -t x "$D" $P reg 0 fb600000 0 100000  0 fd800000 0 10000  0 fd810000 0 1000
	fdtput -t s "$D" $P reg-names config controller dbi
	fdtput -t x "$D" $P ranges 01000000 0 00010000 0 c0000000 0 00010000 \
	                           02000000 0 c0010000 0 c0010000 0 07ff0000
	fdtput -d "$D" $P cfg-space-offset 2>/dev/null || true
	echo "pcie-external0 rewritten for pcie-al"
fi

# Front logo: white on, blue free for userspace
fdtput -t s "$D" /soc/leds/ulogo_w linux,default-trigger default-on
fdtput -t s "$D" /soc/leds/ulogo_b linux,default-trigger none

SGPO=$(fdtget -t u "$D" /soc/sgpo phandle)
EXP=$(fdtget -t u "$D" /soc/i2c-pld/gpio1@21 phandle)

N=/soc/leds-bays
fdtput -r "$D" $N 2>/dev/null || true     # re-runnable: drop nodes from a previous unvr.dtb
fdtput -c "$D" $N
fdtput -t s "$D" $N compatible gpio-leds
# bay:sgpo-line (from the vendor sata_sw_leds node); fault LED = expander pin 11+bay
for m in 1:22 2:20 3:16 4:18; do
	b=${m%%:*}; s=${m#*:}
	fdtput -c "$D" $N/bay$b-activity
	fdtput -t s "$D" $N/bay$b-activity label "bay$b:activity"
	fdtput -t u "$D" $N/bay$b-activity gpios "$SGPO" "$s" 0
	fdtput -t s "$D" $N/bay$b-activity default-state off
	fdtput -c "$D" $N/bay$b-fault
	fdtput -t s "$D" $N/bay$b-fault label "bay$b:fault"
	fdtput -t u "$D" $N/bay$b-fault gpios "$EXP" $((11 + b)) 0
	fdtput -t s "$D" $N/bay$b-fault default-state off
done

[ -f "$OUT" ] && cp "$OUT" "$OUT.prev"
cp "$D" "$OUT"
echo "Wrote $OUT ($(wc -c < "$OUT") bytes). LED nodes:"
fdtget -l "$OUT" $N
