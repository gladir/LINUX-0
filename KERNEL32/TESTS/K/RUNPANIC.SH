#!/bin/bash
# @author: Sylvain Maltais (support@gladir.com)
# @created: 2026
# @description: kernel.panic (partie 38) : /proc/sysrq-trigger 'c' provoque une
#   panique ; avec panic=1 le noyau redemarre au bout d'1 s (QEMU -no-reboot
#   se termine), sans panic= il reste arrete (QEMU tourne jusqu'au delai).
#     RUNPANIC.SH [-n]
HERE=$(cd "$(dirname "$0")" && pwd)
K32=$HERE/../..
LPC=${LPC:-/tmp/claude-0/work/k32/bin/lpc}
GEN=1
while getopts "n" o; do case $o in n) GEN=0 ;; *) exit 2 ;; esac; done
W=$(mktemp -d)
if [ $GEN = 1 ]; then
  "$HERE/build.sh" "$W/u" >/dev/null 2>&1 || exit 1
  python3 "$HERE/MKEMBED.PY" "$W/u" "$K32/KERNEL32.PAS" >/dev/null || exit 1
fi
cp "$K32/KERNEL32.PAS" "$W/"
(cd "$W" && "$LPC" -3K -q KERNEL32.PAS) || exit 1
RC=0
for P in "panic=1" ""; do
  rm -f "$W/o.txt"; S=$(date +%s)
  timeout 25 qemu-system-i386 -kernel "$W/KERNEL32" -serial "file:$W/o.txt" -display none -m 64 -no-reboot \
    -append "console=ttyS0 init=/bin/effects effcrash $P" 2>/dev/null
  T=$(( $(date +%s) - S ))
  PAN=$(grep -ac "panique : SysRq" "$W/o.txt"); RB=$(grep -ac "redemarrage dans 1 s" "$W/o.txt")
  if [ -n "$P" ]; then
    if [ "$PAN" -ge 1 ] && [ "$RB" -ge 1 ] && [ $T -lt 20 ]; then echo "[$P] OK : panique puis redemarrage (${T} s)"; else echo "[$P] ECHEC"; RC=1; fi
  else
    if [ "$PAN" -ge 1 ] && [ "$RB" = 0 ] && [ $T -ge 24 ]; then echo "[sans panic=] OK : noyau arrete"; else echo "[sans panic=] ECHEC"; RC=1; fi
  fi
done
if [ $RC = 0 ]; then echo "RESULTAT : SUCCES"; rm -rf "$W"; else echo "RESULTAT : ECHEC ($W)"; fi
exit $RC
