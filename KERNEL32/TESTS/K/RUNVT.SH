#!/bin/bash
# @author: Sylvain Maltais (support@gladir.com)
# @created: 2026
# @website(https://www.gladir.com/linux-0)
# @description: Consoles virtuelles et KD_GRAPHICS (vttest) : mode graphique
#   1024x768, VT_PROCESS (signaux), VT_ACTIVATE depuis la console graphique :
#   retour au texte VGA (720x400) puis retour au graphique, texte restaure a la
#   fermeture de la console, pty (taille de fenetre, FIONREAD, poll) ; captures
#   QEMU a chaque marqueur VT-SHOT. VGA=vmware : carte VMware SVGA II.
#     RUNVT.SH [-n]
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
  -vga ${VGA:-std} -m 64 -no-reboot -monitor "unix:$W/mon,server,nowait" \
  -append "console=ttyS0 fb=1024x768 init=/bin/vttest k32power" 2>/dev/null &
QP=$!
python3 - "$W" <<'PY'
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
for n in range(4):
    for _ in range(600):
        if "VT-SHOT %d" % n in out(): break
        time.sleep(0.1)
    time.sleep(0.7)
    s.send(("screendump %s/shot%d.ppm\n" % (w, n)).encode()); time.sleep(0.6)
    try: s.settimeout(0.5); s.recv(4096)
    except Exception: pass
PY
wait $QP 2>/dev/null
tr -d '\r' < "$W/out.txt" | grep -a "KTEST: vt\|Oops\|panique"
python3 - "$W" <<'P'
import sys
w0 = sys.argv[1]
def load(n):
    d = open("%s/shot%d.ppm" % (w0, n), 'rb').read()
    parts = d.split(b'\n', 3)
    w, h = map(int, parts[1].split())
    return w, h, parts[3]
ok = True
def chk(n, size, px=None, color=None, text=False):
    global ok
    w, h, pix = load(n)
    good = (w, h) == size
    if px:
        c = tuple(pix[(px[1] * w + px[0]) * 3:(px[1] * w + px[0]) * 3 + 3])
        good = good and c == color
    if text:
        good = good and sum(1 for i in range(0, len(pix), 11) if pix[i]) > 300
    print("shot%d : %dx%d %s" % (n, w, h, "OK" if good else "ECHEC"))
    ok = ok and good
chk(0, (1024, 768), (50, 50), (255, 0, 0))
chk(1, (720, 400), text=True)
chk(2, (1024, 768), (50, 50), (0, 255, 0))
chk(3, (720, 400), text=True)
sys.exit(0 if ok else 1)
P
RC=$?
if [ $RC = 0 ] && ! grep -aq "KTEST: vt.* FAIL" "$W/out.txt" && grep -aq "KTEST: vt DONE" "$W/out.txt"; then
  echo "RESULTAT : SUCCES"; rm -rf "$W"; exit 0
else echo "RESULTAT : ECHEC (traces dans $W)"; exit 1; fi
