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
timeout 200 qemu-system-i386 -kernel "$W/KERNEL32" -serial "file:$W/out.txt" \
  -display none -vga std -m 64 -no-reboot -append "console=ttyS0 fb=1024x768 fbshot k32power $KARGS" \
  -monitor "unix:$W/mon,server,nowait" 2>/dev/null &
QP=$!
python3 - "$W" <<'PY'
# prend une capture d'ecran QEMU a "fb DRAWN" (shot0) puis a chaque "FB-SHOT n"
import socket, sys, time
w = sys.argv[1]
def out():
    try: return open(w + "/out.txt", errors='replace').read()
    except OSError: return ""
s = None
for _ in range(100):
    try:
        s = socket.socket(socket.AF_UNIX); s.connect(w + "/mon"); break
    except OSError: time.sleep(0.2)
time.sleep(0.3); s.recv(4096)
def shot(name):
    s.send(("screendump %s/%s.ppm\n" % (w, name)).encode()); time.sleep(0.6)
    try: s.settimeout(0.5); s.recv(4096)
    except Exception: pass
for name, mark in [("shot0", "fb DRAWN")] + [("shot%d" % n, "FB-SHOT %d" % n) for n in range(1, 8)]:
    for _ in range(600):
        if mark in out(): break
        time.sleep(0.1)
    shot(name)
PY
wait $QP 2>/dev/null
tr -d '\r' < "$W/out.txt" | grep "KTEST: fb\|KPROG: /bin/fbtest\|framebuffer"
python3 - "$W" <<'P'
import sys
w0 = sys.argv[1]
def load(n):
    d = open("%s/%s.ppm" % (w0, n), 'rb').read()
    parts = d.split(b'\n', 3)
    assert parts[0] == b'P6'
    w, h = map(int, parts[1].split())
    return w, h, parts[3]
ok = True
def check(shot, exp_size, checks, nonblack=False):
    global ok
    w, h, pix = load(shot)
    at = lambda x, y: tuple(pix[(y * w + x) * 3:(y * w + x) * 3 + 3])
    good = (w, h) == exp_size
    print("%s : %dx%d %s" % (shot, w, h, "OK" if good else "ECHEC (attendu %s)" % (exp_size,)))
    ok = ok and good
    for n, (x, y), e in checks:
        g = at(x, y) if x < w and y < h else None
        print("  pixel %-8s %s %s" % (n, g, "OK" if g == e else "ECHEC (attendu %s)" % (e,)))
        ok = ok and g == e
    if nonblack:
        nb = any(pix[i] for i in range(0, len(pix), 97))
        print("  texte visible : %s" % ("OK" if nb else "ECHEC"))
        ok = ok and nb
R, G, B = (255, 0, 0), (0, 255, 0), (0, 0, 255)
check("shot0", (1024, 768), [("rouge", (5, 5), R), ("vert", (512, 5), G), ("bleu", (1019, 5), B),
      ("pixel", (100, 200), (0x12, 0x34, 0x56)), ("fond", (500, 600), (0, 0, 0)),
      ("mmap", (50, 300), (0xAB, 0xCD, 0xEF)), ("ligne", (700, 400), (255, 255, 255))])
check("shot1", (800, 600), [("rouge", (5, 5), R), ("vert", (400, 5), G), ("bleu", (795, 5), B), ("fond", (400, 300), (0, 0, 0))])
check("shot2", (1280, 1024), [("rouge", (5, 5), R), ("vert", (640, 5), G), ("bleu", (1275, 5), B), ("jaune", (1200, 1000), (255, 255, 0))])
check("shot3", (640, 480), [("rouge565", (5, 5), R), ("vert565", (320, 5), G), ("bleu565", (635, 5), B)])
check("shot4", (800, 600), [("rouge24", (5, 5), R), ("vert24", (400, 5), G), ("bleu24", (795, 5), B)])
check("shot5", (640, 480), [("rouge8", (5, 5), R), ("vert8", (320, 5), G), ("bleu8", (635, 5), B)])
check("shot6", (640, 480), [("pan-haut", (5, 5), G), ("pan-bas", (5, 470), G)])
check("shot7", (720, 400), [], nonblack=True)
sys.exit(0 if ok else 1)
P
RC=$?
if [ $RC = 0 ] && ! grep -q "KTEST: fb.* FAIL" "$W/out.txt" && grep -q "KPROG: /bin/fbtest OK" "$W/out.txt"; then
  echo "RESULTAT : SUCCES"; rm -rf "$W"; exit 0
else echo "RESULTAT : ECHEC (traces dans $W)"; exit 1; fi
