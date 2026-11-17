#!/bin/bash
# @author: Sylvain Maltais (support@gladir.com)
# @created: 2026
# @website(https://www.gladir.com/linux-0)
# @description: Banc d'essai du disque NVMe : disque ext2 (MKEXT2.SH) branche
#   en `-device nvme`, /dev/nvme0n1p1 monte, lu, ecrit (idetest, index 6),
#   /proc/partitions et /sys/block ; e2fsck de l'image, contenu relu par
#   debugfs ; amorce avec root=/dev/nvme0n1p1 ; disque creux de 8 Go et
#   ecritures a plus de 2 Gio (bdtest avec k32nvme).
#     RUNNVME.SH [-n]
HERE=$(cd "$(dirname "$0")" && pwd)
K32=$HERE/../..
LPC=${LPC:-/tmp/claude-0/work/k32/bin/lpc}
GEN=1; [ "$1" = -n ] && { GEN=0; shift; }
W=$(mktemp -d)
if [ $GEN = 1 ]; then
  "$HERE/build.sh" "$W/u" >/dev/null || exit 1
  python3 "$HERE/MKEMBED.PY" "$W/u" "$K32/KERNEL32.PAS" >/dev/null || exit 1
fi
cp "$K32/KERNEL32.PAS" "$W/"
(cd "$W" && "$LPC" -3K -q KERNEL32.PAS) || exit 1
RC=0
"$HERE/MKEXT2.SH" "$W/v.img" 8 1024 128 || exit 1
DRV=(-drive "file=$W/v.img,format=raw,if=none,id=n0" -device nvme,drive=n0,serial=k32nvme)
rm -f "$W/out.txt"
timeout 200 qemu-system-i386 -kernel "$W/KERNEL32" -serial "file:$W/out.txt" \
  -display none -m 64 -no-reboot -append "console=ttyS0 k32power $KARGS" \
  "${DRV[@]}" $QX 2>/dev/null
tr -d '\r' < "$W/out.txt" > "$W/o2.txt"; mv "$W/o2.txt" "$W/out.txt"
grep -a "nvme:\|KTEST: ide.* FAIL\|Oops\|panique\|ide DONE" "$W/out.txt"
echo "tests ide OK : $(grep -ac 'KTEST: ide.* OK$' "$W/out.txt")"
grep -aq "KTEST: ide.* FAIL" "$W/out.txt" && RC=1
grep -aq "ide DONE 1" "$W/out.txt" || { echo "ide DONE 1 absent"; RC=1; }
grep -aq "KTEST: ide.nvme_proc_partitions OK" "$W/out.txt" || { echo "nvme absent"; RC=1; }
e2fsck -fn "$W/v.img?offset=1048576" > "$W/fsck.txt" 2>&1 || { echo "e2fsck : ECHEC"; RC=1; }
debugfs -R "cat /fromk32/w_hdg.dat" "$W/v.img?offset=1048576" 2>/dev/null | md5sum | cut -c1-32 > "$W/md5"
python3 - "$W/md5" <<'P' || { echo "contenu relu : ECHEC"; RC=1; }
import sys, hashlib
d = 6
data = bytes((((j + d) * 13 + ((j + d) >> 7) + 1) & 255) for j in range(102400))
sys.exit(0 if open(sys.argv[1]).read().strip() == hashlib.md5(data).hexdigest() else 1)
P
# racine sur NVMe
echo "== racine root=/dev/nvme0n1p1"
rm -f "$W/out.txt"
timeout 100 qemu-system-i386 -kernel "$W/KERNEL32" -serial "file:$W/out.txt" -display none \
  -m 64 -no-reboot -append "console=ttyS0 root=/dev/nvme0n1p1 rootfstype=ext2 init=/bin/sh k32power $KARGS" \
  "${DRV[@]}" $QX < /dev/null 2>/dev/null
tr -d '\r' < "$W/out.txt" | grep -a "racine" | head -3
grep -aq "racine : /dev/nvme0n1p1 montee\|racine : aucun programme init sur /dev/nvme0n1p1\|racine : /bin/sh" "$W/out.txt" || { echo "racine nvme : absent"; RC=1; }
# disque de 8 Go : acces a plus de 2 Gio
truncate -s 8G "$W/big.img"
rm -f "$W/out.txt"
timeout 80 qemu-system-i386 -kernel "$W/KERNEL32" -serial "file:$W/out.txt" -display none \
  -m 256 -no-reboot -append "console=ttyS0 init=/bin/bdtest k32nvme" \
  -drive "file=$W/big.img,format=raw,if=none,id=n0" -device nvme,drive=n0,serial=k32nvme $QX < /dev/null 2>/dev/null
tr -d '\r' < "$W/out.txt" | grep -a "KTEST: bd\|nvme:" 
grep -aq "KTEST: bd.* FAIL" "$W/out.txt" && RC=1
[ "$(grep -ac 'KTEST: bd.* OK' "$W/out.txt")" -ge 6 ] || { echo "bdtest nvme : incomplet"; RC=1; }
if [ $RC = 0 ]; then echo "RESULTAT : SUCCES"; rm -rf "$W"; exit 0
else echo "RESULTAT : ECHEC (traces dans $W)"; exit 1; fi
