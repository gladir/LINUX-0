#!/bin/bash
# @author: Sylvain Maltais (support@gladir.com)
# @created: 2026
# @website(https://www.gladir.com/linux-0)
# @description: Essai de la souris PS/2 : lance KERNEL32 (k32mouse sur la ligne
#   de commande), attend MOUSE-READY puis injecte des evenements par le
#   moniteur QEMU (mouse_move, mouse_button) ; mousetest verifie les paquets.
#     RUNMOUSE.SH [-n]   (-n : ne pas regenerer les programmes embarques)
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
timeout 120 qemu-system-i386 -kernel "$W/KERNEL32" -serial "file:$W/out.txt" -display none \
  -m 64 -no-reboot -append "console=ttyS0 k32mouse k32power" \
  -monitor "unix:$W/mon.sock,server,nowait" 2>/dev/null &
QP=$!
python3 - "$W" <<'PY'
import socket, sys, time, os
w = sys.argv[1]
for _ in range(600):
    try:
        if 'MOUSE-READY' in open(w + '/out.txt', errors='replace').read(): break
    except OSError: pass
    time.sleep(0.2)
s = socket.socket(socket.AF_UNIX); 
for _ in range(50):
    try: s.connect(w + '/mon.sock'); break
    except OSError: time.sleep(0.1)
time.sleep(0.3)
for cmd in ['mouse_move 10 5', 'mouse_button 1', 'mouse_move 3 3', 'mouse_button 0', 'mouse_move -4 2']:
    try:
        s.send((cmd + '\n').encode()); time.sleep(0.3)
    except OSError: break
PY
wait $QP
tr -d '\r' < "$W/out.txt" | grep "KTEST: mouse\|MOUSE\|KPROG: /bin/mousetest"
if grep -q "KTEST: mouse.motion OK" "$W/out.txt" && ! grep -q "KTEST: mouse.* FAIL" "$W/out.txt"; then echo "RESULTAT : SUCCES"; rm -rf "$W"; exit 0
else echo "RESULTAT : ECHEC (traces dans $W)"; exit 1; fi
