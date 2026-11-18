#!/bin/bash
# @author: Sylvain Maltais (support@gladir.com)
# @created: 2026
# @website(https://www.gladir.com/linux-0)
# @description: Pilote USB OHCI + HID sous QEMU (-device pci-ohci et
#   usb-tablet / usb-kbd / usb-mouse) : enumeration, tablette absolue
#   (/dev/input/event2, EVIOCGABS, boutons, molette), clavier USB (event0, tty,
#   repetition), souris relative (event1, /dev/input/mice), priorite de la
#   tablette sur VMMDev (simulation). Les evenements sont injectes par QMP
#   (input-send-event). Ne prouve RIEN contre VirtualBox.
#     RUNUSB.SH [-n]   (-n : ne pas regenerer les programmes embarques)
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
FAIL=0
run() {   # run nom "options qemu" "arguments noyau" "script des evenements"
  local name=$1 qx=$2 ka=$3 script=$4
  rm -f "$W/out.txt" "$W/qmp.sock"
  timeout 90 qemu-system-i386 -kernel "$W/KERNEL32" -serial "file:$W/out.txt" -display none \
    -m 64 -no-reboot -qmp "unix:$W/qmp.sock,server,nowait" $qx \
    -append "console=ttyS0 init=/bin/usbtest k32power $ka" 2>/dev/null &
  local QP=$!
  python3 - "$W" "$script" <<'PY'
import socket, sys, time, json
w, script = sys.argv[1], sys.argv[2]
def out():
    try: return open(w + '/out.txt', errors='replace').read()
    except OSError: return ''
s = socket.socket(socket.AF_UNIX)
for _ in range(100):
    try: s.connect(w + '/qmp.sock'); break
    except OSError: time.sleep(0.1)
f = s.makefile('rw')
f.readline()
def cmd(c, **a):
    f.write(json.dumps({"execute": c, "arguments": a}) + "\n"); f.flush()
    while True:
        l = f.readline()
        if not l: return
        if '"return"' in l or '"error"' in l: return l
cmd("qmp_capabilities")
def wait(mark, t=40):
    for _ in range(int(t * 10)):
        if mark in out(): return True
        time.sleep(0.1)
    return False
def ev(*events): cmd("input-send-event", events=list(events))
def ab(axis, v): return {"type": "abs", "data": {"axis": axis, "value": v}}
def rel(axis, v): return {"type": "rel", "data": {"axis": axis, "value": v}}
def btn(b, down): return {"type": "btn", "data": {"button": b, "down": down}}
def key(k, down): return {"type": "key", "data": {"down": down, "key": {"type": "qcode", "data": k}}}
for step in script.split(','):
    if step == 'ABS':
        wait('USB-READY-ABS'); time.sleep(0.5)
        for _ in range(3): ev(ab('x', 8192), ab('y', 16384)); time.sleep(0.2)
    elif step == 'MOVE2':
        wait('USB-READY-MOVE2'); ev(ab('x', 32767), ab('y', 0)); time.sleep(0.3); ev(ab('x', 32767), ab('y', 0))
    elif step == 'BTN':
        wait('USB-READY-BTN'); time.sleep(0.3)
        ev(btn('left', True)); time.sleep(0.3); ev(btn('left', False)); time.sleep(0.3)
    elif step == 'WHEEL':
        wait('USB-READY-WHEEL'); time.sleep(0.3)
        ev(btn('wheel-up', True)); time.sleep(0.2); ev(btn('wheel-up', False)); time.sleep(0.3)
        ev(btn('wheel-up', True)); time.sleep(0.2); ev(btn('wheel-up', False))
    elif step == 'KEY':
        wait('USB-READY-KEY'); time.sleep(0.3)
        ev(key('a', True)); time.sleep(0.15); ev(key('a', False)); time.sleep(0.3)
        ev(key('ret', True)); time.sleep(0.15); ev(key('ret', False))
    elif step == 'REPEAT':
        wait('USB-READY-REPEAT'); time.sleep(0.3)
        ev(key('b', True)); time.sleep(1.6); ev(key('b', False))
    elif step == 'REL':
        wait('USB-READY-REL'); time.sleep(0.5)
        ev(rel('x', 10), rel('y', 5)); time.sleep(0.3); ev(rel('x', 3), rel('y', 3)); time.sleep(0.3)
        ev(btn('left', True)); time.sleep(0.3); ev(btn('left', False)); time.sleep(0.3)
        ev(btn('wheel-up', True)); time.sleep(0.2); ev(btn('wheel-up', False)); time.sleep(0.3)
    elif step == 'WAIT':
        time.sleep(1)
PY
  wait $QP
  echo "== $name"
  tr -d '\r' < "$W/out.txt" | grep -a "usb:\|KTEST: usb\|Oops\|panique" | grep -av "rapport [23] "
  if grep -aq "KTEST: usb.* FAIL" "$W/out.txt" || ! grep -aq "KTEST: usb DONE" "$W/out.txt" || grep -aq "Oops" "$W/out.txt"; then
    FAIL=1; cp "$W/out.txt" "$W/out-$name.txt"
  fi
}
run abs "-device pci-ohci,id=ohci -device usb-tablet -device usb-kbd" "usbmode=abs" "ABS,MOVE2,BTN,WHEEL,KEY,REPEAT"
run rel "-device pci-ohci,id=ohci -device usb-mouse" "usbmode=rel" "REL"
run prio "-device pci-ohci,id=ohci -device usb-tablet" "usbmode=prio k32vboxfake=1" "ABS,MOVE2"
if [ $FAIL = 0 ]; then echo "RESULTAT : SUCCES (QEMU seulement)"; rm -rf "$W"; exit 0
else echo "RESULTAT : ECHEC (traces dans $W)"; exit 1; fi
