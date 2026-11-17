#!/usr/bin/env python3
# @author: Sylvain Maltais (support@gladir.com)
# @created: 2026
# @website(https://www.gladir.com/linux-0)
# @description: ntpdate et rdate (USR/NTPDATE.PAS) contre des serveurs SNTP
#   (UDP) et TIME (TCP 37) factices lances sur 127.0.0.1, avance de 7200 s.
#   usage : nettime.py ./NTPDATE   (le programme est lie en "rdate")
import os, socket, struct, subprocess, sys, threading, time

PROG = os.path.abspath(sys.argv[1])
SKEW = 7200
D1900 = 2208988800
bad = 0


def check(name, ok, detail=''):
    global bad
    print(('ok    ' if ok else 'ECHEC ') + name +
          ('' if ok else ' : ' + detail))
    if not ok:
        bad += 1


def udp_server(sock):
    for _ in range(3):
        try:
            data, addr = sock.recvfrom(100)
        except OSError:
            return
        t = int(time.time()) + SKEW + D1900
        reply = bytearray(48)
        reply[0] = 0x24
        reply[1] = 2
        struct.pack_into('>I', reply, 40, t)
        sock.sendto(bytes(reply), addr)


def tcp_server(sock):
    for _ in range(2):
        try:
            c, _a = sock.accept()
        except OSError:
            return
        c.send(struct.pack('>I', int(time.time()) + SKEW + D1900))
        c.close()


u = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
u.bind(('127.0.0.1', 0))
t = socket.socket()
t.bind(('127.0.0.1', 0))
t.listen(2)
threading.Thread(target=udp_server, args=(u,), daemon=True).start()
threading.Thread(target=tcp_server, args=(t,), daemon=True).start()
up, tp = u.getsockname()[1], t.getsockname()[1]
w = os.path.dirname(PROG)
link = os.path.join(w, 'rdate')
if not os.path.exists(link):
    os.symlink(PROG, link)
r = subprocess.run([PROG, '-q', '-p', str(up), '127.0.0.1'],
                   capture_output=True, text=True)
check('ntpdate -q : decalage de +%d s annonce' % SKEW,
      any(('offset +%d.000' % (SKEW + d)) in r.stdout for d in (-1, 0, 1)),
      r.stdout + r.stderr)
r = subprocess.run([link, '-p', '-P', str(tp), '127.0.0.1'],
                   capture_output=True, text=True)
exp = time.strftime('%a %b %d %H:%M:%S %Y', time.gmtime(time.time() + SKEW))
got = r.stdout.strip()
h1 = time.strftime('%a %b %d %H:%M', time.gmtime(time.time() + SKEW))
check('rdate -p : heure du serveur TIME (UTC, +%d s)' % SKEW,
      got[:16] == h1, got + ' / ' + exp)
r = subprocess.run([PROG, '-q', '-p', '9', '127.0.0.1'], capture_output=True,
                   text=True)
check('ntpdate : serveur muet -> echec propre', r.returncode == 1 and
      'pas de reponse' in r.stderr, r.stderr)
r = subprocess.run([PROG, '-q', 'nom-inconnu.invalid'], capture_output=True,
                   text=True)
check('ntpdate : nom inconnu -> echec propre', r.returncode == 1, r.stderr)
sys.exit(1 if bad else 0)
