#!/bin/bash
# @author: Sylvain Maltais (support@gladir.com)
# @created: 2026
# @website(https://www.gladir.com/linux-0)
# @description: Essai du CD-ROM ATAPI et d'iso9660 (Rock Ridge) : fabrique une
#   image avec genisoimage, la presente a QEMU comme CD-ROM (/dev/hdc) et
#   lance /bin/isotest (actif avec k32iso).
#     RUNISO.SH [-n]
HERE=$(cd "$(dirname "$0")" && pwd)
K32=$HERE/../..
LPC=${LPC:-/tmp/claude-0/work/k32/bin/lpc}
GEN=1; [ "$1" = -n ] && GEN=0
W=$(mktemp -d)
if [ $GEN = 1 ]; then
  "$HERE/build.sh" "$W/u" >/dev/null || exit 1
  python3 "$HERE/MKEMBED.PY" "$W/u" "$K32/KERNEL32.PAS" >/dev/null || exit 1
fi
cp "$K32/KERNEL32.PAS" "$W/"
(cd "$W" && "$LPC" -3K -q KERNEL32.PAS) || exit 1
R=$W/iso; mkdir -p "$R/sub/deep"
echo "iso hello" > "$R/hello.txt"
python3 -c "
import sys
sys.stdout.buffer.write(bytes(((i*7+(i>>8))&255) for i in range(300000)))" > "$R/big.bin"
echo deep > "$R/sub/deep/file.txt"
ln -s hello.txt "$R/link"; ln -s ../hello.txt "$R/sub/up"
genisoimage -quiet -R -V TESTISO -o "$W/t.iso" "$R" 2>/dev/null
timeout 100 qemu-system-i386 -kernel "$W/KERNEL32" -serial "file:$W/out.txt" -display none \
  -m 64 -no-reboot -append "console=ttyS0 k32iso k32power" -cdrom "$W/t.iso" 2>/dev/null
tr -d '\r' < "$W/out.txt" | grep "KTEST: iso\|KPROG: /bin/isotest"
if grep -q "KTEST: iso.umount OK" "$W/out.txt" && ! grep -q "KTEST: iso.* FAIL" "$W/out.txt"; then
  echo "RESULTAT : SUCCES"; rm -rf "$W"; exit 0
else echo "RESULTAT : ECHEC (traces dans $W)"; exit 1; fi
