#!/bin/bash
# @author: Sylvain Maltais (support@gladir.com)
# @created: 2026
# @website(https://www.gladir.com/linux-0)
# @description: Banc d'essai des quatre disques IDE : fabrique des disques ext2
#   (MKEXT2.SH), les branche sur les index QEMU voulus (hda=0, hdb=1, hdc=2,
#   hdd=3 : canal primaire 1F0/IRQ14, canal secondaire 170/IRQ15, maitre et
#   esclave), lance /bin/idetest puis verifie chaque image (e2fsck -fn et
#   contenu ecrit par le noyau, relu par debugfs).
#     RUNIDE.SH [-n] [index...]     (par defaut : "2 3", "0 1 2 3", "3", "0 2", "1 3")
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
if [ $# -gt 0 ]; then SETS=("$*"); else SETS=("2 3" "0 1 2 3" "3" "0 2" "1 3"); fi
RC=0
for SET in "${SETS[@]}"; do
  echo "== disques aux index : $SET"
  DRV=()
  for I in $SET; do
    "$HERE/MKEXT2.SH" "$W/d$I.img" 8 1024 128 || { RC=1; continue; }
    DRV+=(-drive "file=$W/d$I.img,format=raw,if=ide,index=$I")
  done
  rm -f "$W/out.txt"
  timeout 200 qemu-system-i386 -kernel "$W/KERNEL32" -serial "file:$W/out.txt" \
    -display none -m 64 -no-reboot -append "console=ttyS0 k32power $KARGS" \
    "${DRV[@]}" 2>/dev/null
  tr -d '\r' < "$W/out.txt" > "$W/o2.txt"; mv "$W/o2.txt" "$W/out.txt"
  grep "disque IDE\|KTEST: ide.* FAIL\|Oops\|panique\|ide DONE" "$W/out.txt"
  echo "tests ide OK : $(grep -c 'KTEST: ide.* OK$' "$W/out.txt")"
  FAILS=$(grep "KTEST: ide.* FAIL" "$W/out.txt")
  N=0
  for I in $SET; do
    L=$(echo a b c d | cut -d' ' -f$((I+1)))
    N=$((N+1))
    e2fsck -fn "$W/d$I.img?offset=1048576" > "$W/fsck$I.txt" 2>&1 || { echo "e2fsck hd$L : ECHEC"; RC=1; }
    debugfs -R "cat /fromk32/w_hd$L.dat" "$W/d$I.img?offset=1048576" 2>/dev/null | md5sum | cut -c1-32 > "$W/md5_$I"
    python3 - "$W/md5_$I" "$((I))" <<'P' || { echo "contenu hd$L : ECHEC"; RC=1; }
import sys, hashlib
d = int(sys.argv[2])
data = bytes((((j + d) * 13 + ((j + d) >> 7) + 1) & 255) for j in range(102400))
got = open(sys.argv[1]).read().strip()
sys.exit(0 if got == hashlib.md5(data).hexdigest() else 1)
P
  done
  [ -n "$FAILS" ] && RC=1
  grep -q "ide DONE $N" "$W/out.txt" || { echo "ide DONE $N absent"; RC=1; }
done
if [ $RC = 0 ]; then echo "RESULTAT : SUCCES"; rm -rf "$W"; exit 0
else echo "RESULTAT : ECHEC (traces dans $W)"; exit 1; fi
