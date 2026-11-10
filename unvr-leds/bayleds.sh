#!/bin/sh
# UNVR drive-bay LEDs: on while a disk is present, blinking off on I/O (like stock).
# Bay -> libata port (from the vendor DT): bay1=ata7 bay2=ata5 bay3=ata1 bay4=ata3
MAP="1:ata7 2:ata5 3:ata1 4:ata3"
L=/sys/class/leds

findmap() {
	DISKS=""
	for m in $MAP; do
		b=${m%%:*}; a=${m#*:}; d=-
		for s in /sys/block/sd*; do
			[ -e "$s" ] || continue
			case "$(readlink -f "$s/device")" in */$a/*) d=${s##*/} ;; esac
		done
		DISKS="$DISKS $b:$d"
	done
}

set_led() { [ -w "$L/bay$1:activity/brightness" ] && echo "$2" > "$L/bay$1:activity/brightness"; }

for b in 1 2 3 4; do eval "last$b=x"; done
n=0
while :; do
	[ $((n % 50)) -eq 0 ] && findmap
	n=$((n + 1))
	for e in $DISKS; do
		b=${e%%:*}; d=${e#*:}
		if [ "$d" = - ] || [ ! -r "/sys/block/$d/stat" ]; then
			set_led "$b" 0; continue
		fi
		read -r r _ _ _ w _ < "/sys/block/$d/stat"
		eval "prev=\$last$b"
		cur="$r.$w"
		if [ "$cur" != "$prev" ] && [ "$prev" != x ]; then set_led "$b" 0; else set_led "$b" 1; fi
		eval "last$b=\$cur"
	done
	sleep 0.1
done
