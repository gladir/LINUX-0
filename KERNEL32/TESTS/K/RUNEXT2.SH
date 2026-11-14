#!/bin/bash
# @author: Sylvain Maltais (support@gladir.com)
# @created: 2026
# @website(https://www.gladir.com/linux-0)
# @description: Banc d'essai ext2 : fabrique un disque (MKEXT2.SH), lance
#   KERNEL32 sous QEMU (multiboot direct, disque IDE, console COM1), laisse
#   tourner la suite embarquee dont /bin/ext2test, arrete par poweroff
#   (demontage propre) puis verifie le disque avec e2fsck -fn.
#     RUNEXT2.SH [-n] [-b taille_bloc] [-i taille_inode] [-m Mo] [-t secondes]
#   -n : ne pas regenerer les programmes embarques ni recompiler
HERE=$(cd "$(dirname "$0")" && pwd)
K32=$HERE/../..
LPC=${LPC:-/tmp/claude-0/work/k32/bin/lpc}
GEN=1; BS=1024; ISZ=128; MB=16; TMO=240
while getopts "nb:i:m:t:" o; do
  case $o in n) GEN=0 ;; b) BS=$OPTARG ;; i) ISZ=$OPTARG ;; m) MB=$OPTARG ;; t) TMO=$OPTARG ;; *) exit 2 ;; esac
done
W=$(mktemp -d)
if [ $GEN = 1 ]; then
  "$HERE/build.sh" "$W/u" >/dev/null || exit 1
  python3 "$HERE/MKEMBED.PY" "$W/u" "$K32/KERNEL32.PAS" || exit 1
fi
cp "$K32/KERNEL32.PAS" "$W/"
(cd "$W" && "$LPC" -3K -q KERNEL32.PAS) || exit 1
"$HERE/MKEXT2.SH" "$W/d.img" "$MB" "$BS" "$ISZ" || exit 1
timeout "$TMO" qemu-system-i386 -kernel "$W/KERNEL32" -serial "file:$W/out.txt" \
  -display none -m 64 -no-reboot -append "console=ttyS0 k32power" \
  -drive "file=$W/d.img,format=raw,if=ide" 2>/dev/null
tr -d '\r' < "$W/out.txt" > "$W/o2.txt"; mv "$W/o2.txt" "$W/out.txt"
grep "KTEST: ext2\|KPROG: /bin/ext2test\|Oops\|panique" "$W/out.txt"
echo "----"
grep -c "KTEST: ext2.* OK$" "$W/out.txt" | sed 's/^/tests ext2 OK : /'
FAILS=$(grep "KTEST:.* FAIL$" "$W/out.txt")
[ -n "$FAILS" ] && echo "$FAILS"
echo "== e2fsck"
e2fsck -fn "$W/d.img?offset=1048576" > "$W/fsck.txt" 2>&1; RC=$?
tail -8 "$W/fsck.txt"
if [ $RC = 0 ] && grep -q "KTEST: ext2 DONE" "$W/out.txt" && [ -z "$FAILS" ]; then
  echo "RESULTAT : SUCCES"; rm -rf "$W"; exit 0
else echo "RESULTAT : ECHEC (traces dans $W)"; exit 1; fi
