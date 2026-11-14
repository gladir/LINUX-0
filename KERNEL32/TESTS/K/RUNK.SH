#!/bin/bash
# @author: Sylvain Maltais (support@gladir.com)
# @created: 2026
# @website(https://www.gladir.com/linux-0)
# @description: Banc d'essai du noyau KERNEL32 (phase 1) : compile les
#   programmes de test C (ELF i386 statiques), les embarque dans KERNEL32.PAS,
#   compile le noyau avec LPC -3K et le lance sous QEMU (multiboot direct,
#   console sur COM1). Verifie que "KTEST: DONE progs=N fail=0" apparait.
#     RUNK.SH [-n] [-d disque.img] [-t secondes]
#     -n  ne pas regenerer les programmes embarques (MKEMBED.PY)
#     -d  disque IDE de test (MBR + 2 partitions : voir TESTS/K/MKDISK.PY)
#   Variables : LPC (compilateur, defaut /tmp/claude-0/work/k32/bin/lpc)
HERE=$(cd "$(dirname "$0")" && pwd)
K32=$HERE/../..
LPC=${LPC:-/tmp/claude-0/work/k32/bin/lpc}
GEN=1; DISK=; TMO=120
while getopts "nd:t:" o; do
  case $o in n) GEN=0 ;; d) DISK=$OPTARG ;; t) TMO=$OPTARG ;; *) exit 2 ;; esac
done
W=$(mktemp -d)
if [ $GEN = 1 ]; then
  "$HERE/build.sh" "$W/u" >/dev/null || exit 1
  python3 "$HERE/MKEMBED.PY" "$W/u" "$K32/KERNEL32.PAS" || exit 1
fi
cp "$K32/KERNEL32.PAS" "$W/"
(cd "$W" && "$LPC" -3K KERNEL32.PAS) || exit 1
ARGS=(-kernel "$W/KERNEL32" -serial "file:$W/out.txt" -display none -m 64 -no-reboot -append "console=ttyS0")
[ -n "$DISK" ] && ARGS+=(-drive "file=$DISK,format=raw,if=ide")
timeout "$TMO" qemu-system-i386 "${ARGS[@]}" 2>/dev/null &
QP=$!
for i in $(seq 1 "$TMO"); do
  grep -q "KTEST: DONE" "$W/out.txt" 2>/dev/null && break
  kill -0 $QP 2>/dev/null || break
  sleep 1
done
kill $QP 2>/dev/null; wait $QP 2>/dev/null
tr -d '\r' < "$W/out.txt" > "$W/o2.txt"; mv "$W/o2.txt" "$W/out.txt"
cat "$W/out.txt"
echo "----"
grep -c "KTEST:.* OK$" "$W/out.txt" | sed 's/^/tests OK : /'
grep "KTEST:.* FAIL$\|Oops\|panique" "$W/out.txt"
if grep -q "KTEST: DONE progs=[0-9]* fail=0" "$W/out.txt"; then echo "RESULTAT : SUCCES"; rm -rf "$W"; exit 0
else echo "RESULTAT : ECHEC (traces dans $W)"; exit 1; fi
