#!/bin/bash
# @author: Sylvain Maltais (support@gladir.com)
# @created: 2026
# @website(https://www.gladir.com/linux-0)
# @description: Essai du reseau reel : serveur hote (python, TCP 9091 + UDP 9092),
#   KERNEL32 sous QEMU avec une carte RTL8139 en reseau utilisateur (invite
#   10.0.2.15, hote 10.0.2.2, redirection 127.0.0.1:5556 -> invite:7777),
#   programme /bin/nettest (actif avec k32net) puis connexion de l'hote au
#   serveur de l'invite.
#     RUNNET.SH [-n]   (-n : ne pas regenerer les programmes embarques)
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
cat > "$W/srv.py" <<'PY'
import socket, threading, sys, time
def udp():
    s=socket.socket(socket.AF_INET,socket.SOCK_DGRAM); s.bind(('127.0.0.1',9092))
    while True:
        d,a=s.recvfrom(2000); s.sendto(d,a)
def tcp():
    s=socket.socket(); s.setsockopt(socket.SOL_SOCKET,socket.SO_REUSEADDR,1); s.bind(('127.0.0.1',9091)); s.listen(5)
    while True:
        c,_=s.accept(); threading.Thread(target=handle,args=(c,),daemon=True).start()
def handle(c):
    buf=b''
    def readline():
        nonlocal buf
        while b'\n' not in buf:
            d=c.recv(65536)
            if not d: return None
            buf+=d
        l,_,buf=buf.partition(b'\n'); return l
    l=readline(); c.sendall(l+b'\n')
    l=readline()
    if l==b'BULK':
        need=327680
        while len(buf)<need:
            d=c.recv(65536)
            if not d: break
            buf+=d
        c.sendall(b'OK %d\n'%len(buf[:need])); buf=buf[need:]
    l=readline()
    if l==b'SEND':
        c.sendall(bytes((i*5)&255 for i in range(500000)))
    try:
        while True:
            if not c.recv(100): break
    except Exception: pass
    c.close()
threading.Thread(target=udp,daemon=True).start()
threading.Thread(target=tcp,daemon=True).start()
w=sys.argv[1]
# attendre que l'invite ecoute, puis s'y connecter par la redirection
for _ in range(1200):
    try:
        if 'NET-LISTENING' in open(w+'/out.txt',errors='replace').read(): break
    except OSError: pass
    time.sleep(0.1)
time.sleep(0.5)
try:
    c=socket.create_connection(('127.0.0.1',5556),timeout=10)
    c.sendall(b'ping-in\n'); c.settimeout(10)
    r=c.recv(100); open(w+'/hostrecv.txt','w').write(repr(r))
    c.close()
except Exception as e:
    open(w+'/hostrecv.txt','w').write('ERR '+repr(e))
time.sleep(60)
PY
python3 "$W/srv.py" "$W" > "$W/srv.log" 2>&1 &
SP=$!
sleep 1
timeout 120 qemu-system-i386 -kernel "$W/KERNEL32" -serial "file:$W/out.txt" -display none \
  -m 64 -no-reboot -append "console=ttyS0 k32net k32power" \
  -nic user,model=rtl8139,hostfwd=tcp:127.0.0.1:5556-:7777 2>/dev/null
kill $SP 2>/dev/null
tr -d '\r' < "$W/out.txt" | grep "KTEST: net\|NET-\|KPROG: /bin/nettest\|reseau"
cat "$W/hostrecv.txt" 2>/dev/null; echo
if ! grep -q "KTEST: net.accept OK" "$W/out.txt" || grep -q "KTEST: net.* FAIL" "$W/out.txt" \
   || ! grep -q "pong-in" "$W/hostrecv.txt" 2>/dev/null; then
  echo "RESULTAT : ECHEC (traces dans $W)"; exit 1
fi
echo "RESULTAT : SUCCES"; rm -rf "$W"; exit 0
