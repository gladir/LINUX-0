#!/bin/bash
# @author: Sylvain Maltais (support@gladir.com)
# @created: 2026
# @website(https://www.gladir.com/linux-0)
# @description: Banc d'essai du framebuffer : lance KERNEL32 avec fb=1024x768
#   sous QEMU (carte std VGA), laisse /bin/fbtest dessiner, capture l'ecran par
#   le moniteur QEMU (screendump) et verifie les pixels (bandes rouge, vert,
#   bleu et le pixel 123456h) en plus des verifications du programme.
#     RUNFB.SH [-n]
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
timeout 120 qemu-system-i386 -kernel "$W/KERNEL32" -serial "file:$W/out.txt" \
  -display none -vga std -m 64 -no-reboot -append "console=ttyS0 fb=1024x768 k32power" \
  -monitor "unix:$W/mon,server,nowait" 2>/dev/null &
QP=$!
for i in $(seq 1 100); do
  grep -q "fb DRAWN" "$W/out.txt" 2>/dev/null && break
  kill -0 $QP 2>/dev/null || break
  sleep 0.5
done
python3 - "$W" <<'P'
import socket, sys, time
w = sys.argv[1]
s = socket.socket(socket.AF_UNIX)
s.connect(w + "/mon")
time.sleep(0.3)
s.recv(4096)
s.send(("screendump %s/shot.ppm\n" % w).encode())
time.sleep(1.0)
s.close()
P
wait $QP 2>/dev/null
tr -d '\r' < "$W/out.txt" | grep "KTEST: fb\|KPROG: /bin/fbtest\|framebuffer"
python3 - "$W/shot.ppm" <<'P'
import sys
d = open(sys.argv[1], 'rb').read()
parts = d.split(b'\n', 3)
assert parts[0] == b'P6'
w, h = map(int, parts[1].split())
pix = parts[3]
def at(x, y):
    o = (y * w + x) * 3
    return tuple(pix[o:o + 3])
checks = [("rouge", at(5, 5), (255, 0, 0)), ("vert", at(w // 2, 5), (0, 255, 0)),
          ("bleu", at(w - 5, 5), (0, 0, 255)), ("pixel", at(100, 200), (0x12, 0x34, 0x56)),
          ("fond", at(500, 600), (0, 0, 0)), ("mmap", at(50, 300), (0xAB, 0xCD, 0xEF)), ("ligne", at(700, 400), (255, 255, 255))]
ok = True
print("capture : %dx%d" % (w, h))
for n, g, e in checks:
    print("  pixel %-6s %s %s" % (n, g, "OK" if g == e else "ECHEC (attendu %s)" % (e,)))
    ok = ok and g == e
sys.exit(0 if ok else 1)
P
RC=$?
if [ $RC = 0 ] && ! grep -q "KTEST: fb.* FAIL" "$W/out.txt" && grep -q "KPROG: /bin/fbtest OK" "$W/out.txt"; then
  echo "RESULTAT : SUCCES"; rm -rf "$W"; exit 0
else echo "RESULTAT : ECHEC (traces dans $W)"; exit 1; fi
