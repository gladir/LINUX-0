#!/bin/bash
# @author: Sylvain Maltais (support@gladir.com)
# @created: 2026
# @website(https://www.gladir.com/linux-0)
# @description: Banc d'essai FAT12/16/32 (vfat) : fabrique une image
#   (MKFAT.SH), lance KERNEL32 sous QEMU avec l'image en /dev/hdb, laisse
#   tourner /bin/fattest, puis verifie l'image avec fsck.vfat -n et avec
#   mtools (relecture de ce que le noyau a ecrit).
#     RUNFAT.SH [-n] [12|16|32|fd]   (par defaut : les quatre ; fd = disquette)
HERE=$(cd "$(dirname "$0")" && pwd)
K32=$HERE/../..
LPC=${LPC:-/tmp/claude-0/work/k32/bin/lpc}
GEN=1; [ "$1" = -n ] && { GEN=0; shift; }
TYPES=${*:-"12 16 32 fd"}
W=$(mktemp -d)
if [ $GEN = 1 ]; then
  "$HERE/build.sh" "$W/u" >/dev/null || exit 1
  python3 "$HERE/MKEMBED.PY" "$W/u" "$K32/KERNEL32.PAS" >/dev/null || exit 1
fi
cp "$K32/KERNEL32.PAS" "$W/"
(cd "$W" && "$LPC" -3K -q KERNEL32.PAS) || exit 1
export MTOOLS_SKIP_CHECK=1
RC=0
for T in $TYPES; do
  echo "== FAT$T"
  "$HERE/MKFAT.SH" "$W/f$T.img" "$T" || { RC=1; continue; }
  if [ "$T" = fd ]; then DRV="-drive file=$W/f$T.img,format=raw,if=floppy"
  else DRV="-drive file=$W/f$T.img,format=raw,if=ide,index=1"; fi
  timeout 300 qemu-system-i386 -kernel "$W/KERNEL32" -serial "file:$W/out$T.txt" \
    -display none -m 64 -no-reboot -append "console=ttyS0 k32power" \
    $DRV 2>/dev/null
  tr -d '\r' < "$W/out$T.txt" > "$W/o2.txt"; mv "$W/o2.txt" "$W/out$T.txt"
  grep "KTEST: fat.* FAIL\|Oops\|panique\|fat DONE" "$W/out$T.txt"
  echo "tests fat OK : $(grep -c 'KTEST: fat.* OK$' "$W/out$T.txt")"
  FAILS=$(grep "KTEST: fat.* FAIL" "$W/out$T.txt")
  fsck.vfat -n "$W/f$T.img" > "$W/fsck$T.txt" 2>&1; F=$?
  tail -3 "$W/fsck$T.txt"
  # relecture cote hote de ce que le noyau a ecrit
  OK=1
  mcopy -i "$W/f$T.img" ::final.txt - 2>/dev/null | grep -q '^final$' || OK=0
  mcopy -i "$W/f$T.img" "::w/A Very Long File Name With Spaces.data" - 2>/dev/null | grep -q '^long$' || OK=0
  mcopy -i "$W/f$T.img" ::w/rw.txt - 2>/dev/null | grep -q '^rw$' || OK=0
  mcopy -i "$W/f$T.img" ::w/sub2x/sub1moved/in.txt - 2>/dev/null | grep -q '^inside$' || OK=0
  [ "$(mdir -i "$W/f$T.img" ::w/many 2>/dev/null | grep -c file_with_a_long_name)" = 60 ] || OK=0
  [ "$(mcopy -i "$W/f$T.img" ::big.bin - 2>/dev/null | md5sum | cut -c1-32)" = \
    "$(python3 -c "
import sys,hashlib
print(hashlib.md5(bytes(((i*7+(i>>8))&255) for i in range(300000))).hexdigest())")" ] || OK=0
  echo "fsck.vfat rc=$F, relecture hote OK=$OK"
  if [ $F != 0 ] || [ $OK != 1 ] || [ -n "$FAILS" ] || ! grep -q "fat DONE" "$W/out$T.txt"; then RC=1; fi
done
if [ $RC = 0 ]; then echo "RESULTAT : SUCCES"; rm -rf "$W"; exit 0
else echo "RESULTAT : ECHEC (traces dans $W)"; exit 1; fi
