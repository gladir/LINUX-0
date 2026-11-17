#!/bin/bash
# @author: Sylvain Maltais (support@gladir.com)
# @created: 2026
# @website(https://www.gladir.com/linux-0)
# @description: Noyau preemptible : lance la suite complete avec preempt=1
#   (ou preempt=0) sur un disque ext2 (stress parallele pstress, latence
#   preempttest), plusieurs fois de suite, puis e2fsck -fn de chaque disque.
#     RUNPREEMPT.SH [-n] [-r repetitions] [-p 0|1]    (defauts : 1 fois, preempt=1)
HERE=$(cd "$(dirname "$0")" && pwd)
K32=$HERE/../..
LPC=${LPC:-/tmp/claude-0/work/k32/bin/lpc}
GEN=1; REP=1; PRE=1
while getopts "nr:p:" o; do case $o in n) GEN=0 ;; r) REP=$OPTARG ;; p) PRE=$OPTARG ;; *) exit 2 ;; esac; done
W=$(mktemp -d)
if [ $GEN = 1 ]; then
  "$HERE/build.sh" "$W/u" >/dev/null || exit 1
  python3 "$HERE/MKEMBED.PY" "$W/u" "$K32/KERNEL32.PAS" >/dev/null || exit 1
fi
cp "$K32/KERNEL32.PAS" "$W/"
(cd "$W" && "$LPC" -3K -q KERNEL32.PAS) || exit 1
RC=0
for R in $(seq 1 "$REP"); do
  "$HERE/MKEXT2.SH" "$W/d.img" 16 1024 128 || exit 1
  rm -f "$W/out.txt"
  timeout 400 qemu-system-i386 -kernel "$W/KERNEL32" -serial "file:$W/out.txt" \
    -display none -m 64 -no-reboot -append "console=ttyS0 preempt=$PRE k32power" \
    -drive "file=$W/d.img,format=raw,if=ide" -smp 1 2>/dev/null
  tr -d '\r' < "$W/out.txt" > "$W/o2.txt"; mv "$W/o2.txt" "$W/out.txt"
  FAILS=$(grep "KTEST:.* FAIL$\|KPROG:.*FAIL\|Oops\|panique" "$W/out.txt")
  DONE=$(grep -c "KTEST: DONE progs=[0-9]* fail=0" "$W/out.txt")
  OKS=$(grep -c "KTEST:.* OK$" "$W/out.txt")
  e2fsck -fn "$W/d.img?offset=1048576" > "$W/fsck.txt" 2>&1; F=$?
  echo "run $R : tests OK=$OKS suite=$DONE e2fsck=$F $(grep -a 'preempt on=' "$W/out.txt")"
  if [ -n "$FAILS" ] || [ "$DONE" != 1 ] || [ $F != 0 ]; then
    echo "$FAILS"; RC=1; cp "$W/out.txt" "$W/out.fail.$R.txt"; cp "$W/d.img" "$W/d.fail.$R.img"
  fi
done
if [ $RC = 0 ]; then echo "RESULTAT : SUCCES"; rm -rf "$W"; exit 0
else echo "RESULTAT : ECHEC (traces dans $W)"; exit 1; fi
