#!/usr/bin/env python3
# @author: Sylvain Maltais (support@gladir.com)
# @created: 2026
# @website(https://www.gladir.com/linux-0)
# @description: Mesure de la charge graphique de GEOWORKS sous QEMU avec les
#   compteurs de l'unite Graph (GFXSTAT=1, imprimes a la sortie : s0 poll,
#   s1 lectures souris, s5 recopies vers l'ecran, s6 lignes, s7 pixels,
#   s9 ioctl). Scenarios de 40 s : idle, move (160 deplacements), drag
#   (glisser GeoManager), menu (F10 et fleches), term (ls dans le Terminal).
#   usage : geobench.py RACINE NOYAU.ELF SORTIE.json prog1,prog2 [scenario..]
#   (prog = noms dans RACINE/usr/bin, par ex. geoworks_avant,geoworks)
import json, os, re, subprocess, sys, time
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
src = open(os.path.join(HERE, 'QCTL.PY')).read()
ns = {'__name__': 'qctl'}
exec(compile(src, 'QCTL.PY', 'exec'), ns)
Q = ns['Q']
ROOT, KERN, OUT, PROGS = sys.argv[1:5]
ONLY = sys.argv[5:]
W = os.path.join(os.environ.get('W', '/tmp/linux0-geo-bench'), 'run')
os.makedirs(W, exist_ok=True)
img = W + '/root.img'
subprocess.run(['rm', '-f', img])
subprocess.run(['mke2fs', '-q', '-t', 'ext2', '-b', '1024', '-I', '128', '-O',
                'none,filetype,sparse_super', '-d', ROOT, img, '64M'],
               check=True, stderr=subprocess.DEVNULL)
VGA = os.environ.get('VGA', 'std')
cmd = 'console=ttyS0 root=/dev/hda rw' + (' fbvmw' if VGA == 'vmware' else '')
q = Q(W, ['-kernel', KERN, '-m', '128', '-vga', VGA, '-drive',
          'file=%s,format=raw,if=ide' % img, '-append', cmd], serial_io=True)
for _ in range(60):
    if q.wait('login:', 2):
        break
    q.serial('\n')
q.serial('root\n')
time.sleep(3)
SEQ = [0]
T = 40.0


def sh(c, timeout=60):
    SEQ[0] += 1
    m = 'BD%dX' % SEQ[0]
    n = len(q.text())
    q.serial(c + '; echo ' + m + '\n')
    q.wait(r'(?m)^' + m, timeout, n)


def raw(c, d=0.03):
    q.s.send((c + '\n').encode())
    time.sleep(d)


def goto(x, y):
    for _ in range(25):
        raw('mouse_move -120 -120', 0.02)
    time.sleep(0.5)
    while x or y:
        sx = max(-100, min(100, x))
        sy = max(-100, min(100, y))
        raw('mouse_move %d %d' % (sx, sy), 0.03)
        x -= sx
        y -= sy
    time.sleep(0.5)
    q._drain()


def rest(t0):
    time.sleep(max(0, T - (time.time() - t0)))


def idle():
    time.sleep(T)


def move():
    t0 = time.time()
    goto(200, 200)
    for i in range(160):
        d = 3 if (i // 10) % 2 == 0 else -3
        raw('mouse_move %d %d' % (d, d // 3 or 1), 0.05)
    q._drain()
    rest(t0)


def drag():
    t0 = time.time()
    goto(300, 12)
    raw('mouse_button 1', 0.3)
    for i in range(80):
        raw('mouse_move 3 2', 0.08)
    raw('mouse_button 0', 0.5)
    q._drain()
    rest(t0)


def menu():
    t0 = time.time()
    q.key('f10', 0.5)
    for i in range(30):
        q.key('right' if i % 2 == 0 else 'left', 0.2)
        raw('sendkey down', 0.1)
    q.key('esc', 0.5)
    rest(t0)


def term():
    t0 = time.time()
    for _ in range(2):
        q.type('ls -l /bin /usr/bin /etc', 0.08)
        q.key('ret', 0.3)
    rest(t0)


SC = [('idle', idle, ''), ('move', move, ''), ('drag', drag, ''),
      ('menu', menu, ''), ('term', term, '/R:TERMINAL')]
res = {}
for prog in PROGS.split(','):
    for name, fn, extra in SC:
        if ONLY and name not in ONLY:
            continue
        tag = '%s-%s' % (prog, name)
        sh('pkill geoworks; sleep 1; rm -f /tmp/st.txt')
        q.serial('GFXSTAT=1 LANGUAGE=EN /usr/bin/%s /NOWELCOME %s '
                 '</dev/tty1 >/dev/tty1 2>/tmp/st.txt &\n' % (prog, extra))
        time.sleep(12)
        fn()
        q.key('f11', 0.8)
        q.key('up', 0.5)
        q.key('ret', 0.8)
        q.key('ret', 1.5)
        time.sleep(4)
        sh('cat /tmp/st.txt')
        m = [x for x in re.findall(r'GFXSTAT([^\r\n]*)', q.text())
             if 's0=' in x]
        res[tag] = {int(k): int(v) for k, v in
                    re.findall(r's(\d+)=(\d+)', m[-1])} if m else {}
        print(tag, res[tag])
        sys.stdout.flush()
json.dump(res, open(OUT, 'w'), indent=1)
q.quit()
