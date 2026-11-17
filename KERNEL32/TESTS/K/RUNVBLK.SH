#!/bin/bash
# @author: Sylvain Maltais (support@gladir.com)
# @created: 2026
# @website(https://www.gladir.com/linux-0)
# @description: Banc d'essai du disque virtio-blk (partie 39) : disque ext2
#   (MKEXT2.SH) branche en `-drive if=virtio` seul puis avec un disque IDE,
#   /dev/vda1 monte, lu, ecrit (idetest, disque d'index 4), /proc/partitions,
#   /sys/block/vda ; e2fsck de l'image et contenu relu par debugfs ;
#   amorce avec root=/dev/vda1 (racine ext2 sur virtio).
#     RUNVBLK.SH [-n]    (-n : ne pas regenerer les programmes embarques)
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
for SET in "virtio" "ide+virtio"; do
  echo "== disques : $SET"
  "$HERE/MKEXT2.SH" "$W/v.img" 8 1024 128 || { RC=1; continue; }
  DRV=(-drive "file=$W/v.img,format=raw,if=virtio")
  if [ "$SET" = "ide+virtio" ]; then
    "$HERE/MKEXT2.SH" "$W/i.img" 8 1024 128 || { RC=1; continue; }
    DRV+=(-drive "file=$W/i.img,format=raw,if=ide,index=0")
  fi
  rm -f "$W/out.txt"
  timeout 200 qemu-system-i386 -kernel "$W/KERNEL32" -serial "file:$W/out.txt" \
    -display none -m 64 -no-reboot -append "console=ttyS0 k32power $KARGS" \
    "${DRV[@]}" $QX 2>/dev/null
  tr -d '\r' < "$W/out.txt" > "$W/o2.txt"; mv "$W/o2.txt" "$W/out.txt"
  grep "disque IDE\|KTEST: ide.* FAIL\|Oops\|panique\|ide DONE" "$W/out.txt"
  echo "tests ide OK : $(grep -c 'KTEST: ide.* OK$' "$W/out.txt")"
  [ -n "$(grep 'KTEST: ide.* FAIL' "$W/out.txt")" ] && RC=1
  N=1; [ "$SET" = "ide+virtio" ] && N=2
  grep -q "ide DONE $N" "$W/out.txt" || { echo "ide DONE $N absent"; RC=1; }
  e2fsck -fn "$W/v.img?offset=1048576" > "$W/fsck.txt" 2>&1 || { echo "e2fsck vda : ECHEC"; RC=1; }
  debugfs -R "cat /fromk32/w_hde.dat" "$W/v.img?offset=1048576" 2>/dev/null | md5sum | cut -c1-32 > "$W/md5"
  python3 - "$W/md5" <<'P' || { echo "contenu vda : ECHEC"; RC=1; }
import sys, hashlib
d = 4
data = bytes((((j + d) * 13 + ((j + d) >> 7) + 1) & 255) for j in range(102400))
sys.exit(0 if open(sys.argv[1]).read().strip() == hashlib.md5(data).hexdigest() else 1)
P
done
# racine sur virtio
echo "== racine root=/dev/vda1"
rm -f "$W/out.txt"
timeout 100 qemu-system-i386 -kernel "$W/KERNEL32" -serial "file:$W/out.txt" -display none \
  -m 64 -no-reboot -append "console=ttyS0 root=/dev/vda1 rootfstype=ext2 init=/bin/sh k32power $KARGS" \
  -drive "file=$W/v.img,format=raw,if=virtio" $QX < /dev/null 2>/dev/null
tr -d '\r' < "$W/out.txt" | grep -a "racine\|/dev/vda1\|root" | head -5
grep -aq "racine : /dev/vda1 montee\|racine : aucun programme init sur /dev/vda1" "$W/out.txt" || { echo "racine vda1 : absent"; RC=1; }
if [ $RC = 0 ]; then echo "RESULTAT : SUCCES"; rm -rf "$W"; exit 0
else echo "RESULTAT : ECHEC (traces dans $W)"; exit 1; fi
