#!/bin/bash
# @author: Sylvain Maltais (support@gladir.com)
# @created: 2026
# @website(https://www.gladir.com/linux-0)
# @description: Banc d'essai des fichiers > 2 Go (partie 35) : disque creux de
#   6 Go (ext2) ou FAT32 de 3 Go fabrique par MKBIG.SH, noyau sous QEMU avec
#   "bigtest" sur la ligne de commande, puis verification par e2fsck -fn
#   (ext2) ou fsck.vfat -n (FAT) de l'hote.
#     RUNBIG.SH [-n] [-f ext2|fat] [-b taille_bloc] [-t secondes]
HERE=$(cd "$(dirname "$0")" && pwd)
K32=$HERE/../..
LPC=${LPC:-/tmp/claude-0/work/k32/bin/lpc}
GEN=1; KIND=ext2; BS=1024; TMO=600
while getopts "nf:b:t:" o; do
  case $o in n) GEN=0 ;; f) KIND=$OPTARG ;; b) BS=$OPTARG ;; t) TMO=$OPTARG ;; *) exit 2 ;; esac
done
W=$(mktemp -d)
if [ $GEN = 1 ]; then
  "$HERE/build.sh" "$W/u" >/dev/null || exit 1
  python3 "$HERE/MKEMBED.PY" "$W/u" "$K32/KERNEL32.PAS" || exit 1
fi
cp "$K32/KERNEL32.PAS" "$W/"
(cd "$W" && "$LPC" -3K KERNEL32.PAS) || exit 1
"$HERE/MKBIG.SH" "$W/d.img" "$KIND" "$BS" || { echo "MKBIG echec"; exit 1; }
timeout "$TMO" qemu-system-i386 -kernel "$W/KERNEL32" -serial "file:$W/out.txt" \
  -display none -m 64 -no-reboot -append "console=ttyS0 k32power bigtest $KARGS" \
  -drive "file=$W/d.img,format=raw,if=ide" 2>/dev/null
tr -d '\r' < "$W/out.txt" > "$W/o2.txt"; mv "$W/o2.txt" "$W/out.txt"
grep "KTEST: big\|KPROG: /bin/bigtest\|Oops\|panique" "$W/out.txt"
echo "----"
grep -c "KTEST: big.* OK$" "$W/out.txt" | sed 's/^/tests big OK : /'
FAILS=$(grep "KTEST: big.* FAIL$" "$W/out.txt")
[ -n "$FAILS" ] && echo "$FAILS"
echo "== fsck"
if [ "$KIND" = ext2 ]; then
  printf '[options]\n\tbroken_system_clock = 1\n' > "$W/e2fsck.conf"   # l'horloge de devtest : 2030
  E2FSCK_CONFIG="$W/e2fsck.conf" e2fsck -fn "$W/d.img?offset=1048576" > "$W/fsck.txt" 2>&1; RC=$?
else
  fsck.vfat -n -v --help >/dev/null 2>&1
  python3 - "$W/d.img" "$W/p.img" <<'PY'
import sys
src=open(sys.argv[1],'rb'); dst=open(sys.argv[2],'wb')
src.seek(1048576)
while True:
    b=src.read(1<<24)
    if not b: break
    dst.write(b)
PY
  fsck.vfat -n "$W/p.img" > "$W/fsck.txt" 2>&1; RC=$?
fi
head -30 "$W/fsck.txt"
if [ $RC = 0 ] && grep -q "KTEST: big DONE" "$W/out.txt" && [ -z "$FAILS" ]; then
  echo "RESULTAT : SUCCES"; rm -rf "$W"; exit 0
else
  # les disques sont enormes : ne garder que les traces
  mkdir -p /tmp/big-traces; cp "$W/out.txt" "$W/fsck.txt" /tmp/big-traces/ 2>/dev/null
  rm -rf "$W"; echo "RESULTAT : ECHEC (traces dans /tmp/big-traces)"; exit 1
fi
