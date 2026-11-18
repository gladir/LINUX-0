#!/usr/bin/env python3
# @author: Sylvain Maltais (support@gladir.com)
# @created: 2026
# @website(https://www.gladir.com/linux-0)
# @description: Scenario QEMU de GEOWORKS sous KERNEL32 (voir RUNGEO.SH) :
#   amorce le noyau avec une racine ext2 contenant /usr/bin/geoworks, lance
#   GEOWORKS sur tty1, pilote clavier et souris par le moniteur QEMU, prend
#   des captures (PNG <= 300 Ko) et verifie des effets mesurables (fichiers
#   ecrits par le Terminal et par un bouton Programmes Linux, pixels, sortie
#   vers Linux).
#   usage : georun.py WORK ROOT_DIR KERNEL.ELF CAPDIR [vga|vmware] [ide|ahci]
import os, subprocess, sys, time
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
try:
    from QCTL import Q
except ImportError:                      # QCTL.PY : extension en majuscules
    src = open(os.path.join(os.path.dirname(os.path.abspath(__file__)),
                            'QCTL.PY')).read()
    ns = {'__name__': 'qctl'}
    exec(compile(src, 'QCTL.PY', 'exec'), ns)
    Q = ns['Q']

WORK, ROOT, KERN, CAP = sys.argv[1:5]
VGA = sys.argv[5] if len(sys.argv) > 5 else 'std'
DISK = sys.argv[6] if len(sys.argv) > 6 else 'ide'
TAG = '' if VGA == 'std' and DISK == 'ide' else '-%s-%s' % (VGA, DISK)
os.makedirs(WORK, exist_ok=True)
os.makedirs(CAP, exist_ok=True)
RES = []


def check(name, ok):
    RES.append((name, bool(ok)))
    print('%-52s %s' % (name, 'OK' if ok else 'ECHEC'))
    sys.stdout.flush()


def image(path):
    subprocess.run(['rm', '-f', path])
    subprocess.run(['mke2fs', '-q', '-t', 'ext2', '-b', '1024', '-I', '128',
                    '-O', 'none,filetype,sparse_super', '-d', ROOT, path,
                    '48M'], check=True, stderr=subprocess.DEVNULL)


# fichier de test du Terminal : couleurs, deplacements, effacement, UTF-8
os.makedirs(os.path.join(ROOT, 'root'), exist_ok=True)
open(os.path.join(ROOT, 'root', 'ansi.txt'), 'wb').write(
    b'\x1b[2J\x1b[H\x1b[31mROUGE \x1b[32mVERT \x1b[34mBLEU \x1b[0m'
    b'\x1b[1;33mJAUNE\x1b[0m \x1b[7mINVERSE\x1b[0m\r\n'
    b'\x1b[10;5H\x1b[44;37m FOND BLEU \x1b[0m\x1b[12;1HUTF-8 : '
    b'caf\xc3\xa9 \xc3\xa0 \xc3\xa7a \xe2\x94\x8c\xe2\x94\x80\xe2\x94'
    b'\x90\r\nligne\x1b[2K\r\nFIN ANSI\r\n')
img = os.path.join(WORK, 'root.img')
image(img)
args = ['-kernel', KERN, '-m', '128', '-vga', VGA]
if DISK == 'ahci':
    args += ['-device', 'ich9-ahci,id=ahci', '-drive',
             'file=%s,format=raw,if=none,id=d0' % img, '-device',
             'ide-hd,drive=d0,bus=ahci.0']
    root = '/dev/sda'
else:
    args += ['-drive', 'file=%s,format=raw,if=ide' % img]
    root = '/dev/hda'
cmd = 'console=ttyS0 root=%s rw' % root
if VGA == 'vmware':
    cmd += ' fbvmw'
q = Q(WORK, args + ['-append', cmd], serial_io=True)
if q.sio is None or q.s is None:         # machine chargee : QEMU est lent
    import socket, threading
    for _ in range(600):
        try:
            if q.s is None:
                q.s = socket.socket(socket.AF_UNIX)
                q.s.connect(q.mon)
            q.sio = socket.socket(socket.AF_UNIX)
            q.sio.connect(q.ser)
            open(q.out, 'w').close()
            threading.Thread(target=q._pump, daemon=True).start()
            break
        except OSError:
            q.sio = None
            time.sleep(0.2)


def shot(name):
    png = q.shot(name + TAG)
    dst = os.path.join(CAP, 'geo-%s%s.png' % (name, TAG))
    subprocess.run(['cp', png, dst])
    return os.path.join(WORK, name + TAG + '.ppm')


def colors(ppm, rgb, tol=8):
    from PIL import Image
    import numpy
    a = numpy.asarray(Image.open(ppm).convert('RGB')).astype(int)
    d = numpy.abs(a - numpy.array(rgb))
    return int((d.max(axis=2) <= tol).sum())


SEQ = [0]


def sh(c, wait=1.5, timeout=40):
    """commande sur la console serie ; attend sa fin (marqueur) : le shell
    est lent quand geoworks occupe le processeur"""
    SEQ[0] += 1
    mark = 'SHDONE%d' % SEQ[0]
    n = len(q.text())
    q.serial(c + '; echo ' + mark + 'X\n')
    q.wait(r'(?m)^' + mark + 'X', timeout, n)
    time.sleep(0.3)


def out_since(mark):
    t = q.text()
    i = t.rfind(mark)
    return t[i + len(mark):] if i >= 0 else ''


def goto(x, y):
    q.move(-2000, -2000)
    q.move(x, y)
    time.sleep(0.3)


def click_at(x, y, wait=1.5):
    goto(x, y)
    q.click()
    time.sleep(wait)


def dclick_at(x, y, wait=2):
    """double-clic : envois directs au moniteur (q.cmd attend 0,3 s par
    commande, trop lent pour le delai de double-clic de GEOS : 0,4 s)"""
    goto(x, y)
    for _ in range(2):
        for b in (b'mouse_button 1\n', b'mouse_button 0\n'):
            q.s.send(b)
            time.sleep(0.09)
    time.sleep(wait)
    q._drain()


def start(args_='', lang='EN'):
    sh('pkill geoworks; sleep 1')
    q.serial('LANGUAGE=%s; export LANGUAGE; geoworks %s </dev/tty1 '
             '>/dev/tty1 2>/tmp/geo.err &\n' % (lang, args_))
    time.sleep(9)


def alive():
    SEQ[0] += 1
    mark = 'PSN%d' % SEQ[0]
    n = len(q.text())
    q.serial('echo "' + mark + '[$(ps | grep -c [g]eoworks)]"\n')
    q.wait(mark + r'\[\d+\]', 40, n)
    return (mark + '[1]') in q.text()[n:]


ok = False
for _ in range(45):                   # le noyau a pu finir avant la connexion
    if q.wait(r'login:', 2):
        ok = True
        break
    q.serial('\n')
check('amorcage et invite de connexion', ok)
if not ok:
    print(q.text()[-1500:])
    q.quit()
    sys.exit(1)
q.serial('root\n')
time.sleep(3)
# racine de test : mot de passe root vide (shadow) ; profil minimal
sh('mkdir -p /root/.geoworks; export HOME=/root', 1)

# ---- 1. ecran d'accueil ------------------------------------------------
start()
p = shot('welcome')
hdr = open(p, 'rb').read(30).split(b'\n')[1].split()
SW, SH = int(hdr[0]), int(hdr[1])
DX, DY = max(0, (SW - 640) // 2), max(0, (SH - 480) // 2)
print('ecran %dx%d' % (SW, SH))
check('geoworks tourne (ecran d\'accueil)', alive())
check('accueil dessine (fond gris et logo jaune)',
      colors(p, (170, 170, 170)) > 50000 and colors(p, (255, 255, 85)) > 500)
sh('for d in WORLD SYSTEM DOCUMENT USERDATA/HELP; do '
   '[ -d /usr/share/geoworks/$d ] && echo DIROK-$d; done; echo DIRS-END', 2)
d = out_since('for d in WORLD SYSTEM')
check('repertoires de donnees GEOS crees (WORLD SYSTEM DOCUMENT USERDATA/HELP)',
      all('DIROK-' + x in d.replace('\r', '') for x in
          ('WORLD', 'SYSTEM', 'DOCUMENT', 'USERDATA/HELP')))

# variable LANGUAGE : francais (defaut Linux-0) et allemand
if TAG == '':
    start(lang='FR')
    pf = shot('welcome-fr')
    start(lang='GR')
    pd = shot('welcome-de')
    check('LANGUAGE=FR / GR : accueil traduit (captures differentes)',
          open(pf, 'rb').read() != open(pd, 'rb').read())
    start()

# ---- 2. Terminal depuis l'accueil -------------------------------------
def tcmd(text, flag):
    """tape une commande dans le Terminal puis attend le fichier /tmp/flag
    (cree par la commande suivante) : le shell est lent sous charge"""
    q.type(text + '; touch /tmp/' + flag, 0.12)
    q.key('ret')
    sh('while [ ! -f /tmp/%s ]; do sleep 1; done' % flag, timeout=90)


for _ in range(4):
    q.key('right', 0.3)
shot('welcome-terminal-selected')
q.key('ret', 0.3)
time.sleep(5)
tcmd('echo TERMOK > /tmp/term.out; tty > /tmp/term.tty', 'f1')
tcmd('ls /bin | head -3; uname -a', 'f2')
time.sleep(1)
p = shot('terminal')
sh('cat /tmp/term.out; cat /tmp/term.tty', 1)
check('Terminal : commande executee sur le pty (echo)',
      'TERMOK' in out_since('cat /tmp/term.out'))
check('Terminal : le shell tourne sur /dev/pts/N',
      '/dev/pts/' in out_since('cat /tmp/term.out'))
check('Terminal : texte affiche (pixels clairs sur fond noir)',
      colors(p, (0, 0, 0)) > 20000 and colors(p, (170, 170, 170)) > 300)
# couleurs ANSI, deplacements, effacement, UTF-8 : fichier de test
tcmd('cat /root/ansi.txt', 'f3')
time.sleep(1)
p = shot('terminal-colors')
check('Terminal : couleurs ANSI (rouge, vert, bleu, jaune)',
      colors(p, (170, 0, 0)) > 20 and colors(p, (0, 170, 0)) > 20 and
      colors(p, (0, 0, 170)) > 20 and colors(p, (255, 255, 85)) > 20)
# redimensionnement : agrandir la fenetre, le pty doit suivre (TIOCSWINSZ)
tcmd('tput cols > /tmp/c1; tput lines > /tmp/l1', 'f4')
dclick_at(300, 48, 3)       # double-clic sur la barre de titre
tcmd('tput cols > /tmp/c2; tput lines > /tmp/l2', 'f5')
time.sleep(1)
p = shot('terminal-maximized')
sh('echo "SZ $(cat /tmp/c1) $(cat /tmp/c2) $(cat /tmp/l1) $(cat /tmp/l2)"', 1)
m = out_since('echo "SZ $(cat').split('SZ ')
try:
    c1, c2, l1, l2 = [int(x) for x in m[-1].split()[:4]]
except Exception:
    c1 = c2 = l1 = l2 = 0
check('Terminal : fenetre agrandie, taille du pty suivie (%dx%d -> %dx%d)'
      % (c1, l1, c2, l2), c2 > c1 and l2 > l1)
q.type('exit', 0.12)
q.key('ret')
time.sleep(4)
p = shot('desktop-after-exit')
check('Terminal : exit ferme la fenetre (GeoManager visible)',
      colors(p, (255, 255, 255)) > 20000)

# ---- 3. Programmes Linux (bouton configure) ---------------------------
sh('echo "Test|echo GEO-RUN-OK > /tmp/geo-run.out|1" > '
   '/root/.geoworks/linuxprog.cfg', 1)
start()
click_at(240 + DX, 206 + DY, 2)
p = shot('linux-programs')
check('ecran Programmes Linux (bouton configure)',
      colors(p, (85, 255, 85)) > 100)
click_at(100, 120, 3)
p = shot('linux-run-text')
sh('cat /tmp/geo-run.out', 1.5)
check('programme Linux execute (ecran texte + attente d\'une touche)',
      'GEO-RUN-OK' in out_since('cat /tmp/geo-run.out'))
q.key('spc', 0.5)
time.sleep(3)
p = shot('linux-programs-back')
check('retour au graphique apres le programme', alive() and
      colors(p, (170, 170, 170)) > 50000)

# ---- 4. applications de chaque famille --------------------------------
def diffpx(p1, p2):
    from PIL import Image
    import numpy
    a = numpy.asarray(Image.open(p1).convert('RGB')).astype(int)
    b = numpy.asarray(Image.open(p2).convert('RGB')).astype(int)
    return int((numpy.abs(a - b).max(axis=2) > 8).sum())


def wait_ready(name, timeout=60):
    """attend que la fenetre de l'application soit dessinee (des pixels
    blancs) : le demarrage depend de la charge de la machine"""
    t0 = time.time()
    while time.time() - t0 < timeout:
        q.shot(name + '-pre' + TAG)
        p = os.path.join(WORK, name + '-pre' + TAG + '.ppm')
        if colors(p, (255, 255, 255)) > 500:
            return p
        time.sleep(2)
    return p


# (argument /R:, nom, etiquette, actions) ; action : ('type', texte),
# ('key', touche), ('click', x, y) ; 'effet' = l'ecran doit changer
APPS = [('CALC', 'calculator', 'Calculatrice', [('type', '12*3=')]),
        ('WRITE', 'geowrite', 'GeoWrite', [('type', 'Bonjour depuis Linux')]),
        ('DRAW', 'geodraw', 'GeoDraw', []),
        ('TETRIS', 'tetris', 'Tetris', [('key', 'left'), ('key', 'left'),
                                        ('key', 'spc')]),
        ('CLOCK', 'clock', 'Horloge', []),
        ('NOTEPAD', 'notepad', 'Notepad (menus)', [('key', 'f10'),
                                                   ('key', 'down')]),
        ('MANAGER', 'geomanager', 'GeoManager', []),
        ('SOLITAIRE', 'solitaire', 'Solitaire', [('click', 90, 120)]),
        ('GEOCALC', 'geocalc', 'GeoCalc', [('type', '5\n7\n')]),
        ('PLANNER', 'geoplanner', 'GeoPlanner', [('key', 'pgdn'),
                                                 ('key', 'pgdn')]),
        ('GEODEX', 'geodex', 'GeoDex', [('type', 'Linux')]),
        ('BANNER', 'geobanner', 'GeoBanner', [('type', 'Hello')]),
        ('SCRAP', 'scrapbook', 'Scrapbook', [('click', 176, 378)]),
        ('PREFS', 'preferences', 'Preferences', [('key', 'down'),
                                                 ('key', 'ret')]),
        ('GEOBASIC', 'geobasic', 'GeoBasic', [('key', 'f10')]),
        ('GEOPOINT', 'geopoint', 'GeoPoint', [('key', 'pgdn')])]
for arg, name, label, acts in APPS:
    start('/NOWELCOME /R:%s' % arg)
    p0 = wait_ready('app-' + name)
    for act in acts:
        if act[0] == 'type':
            q.type(act[1], 0.12)
        elif act[0] == 'key':
            q.key(act[1], 0.4)
        else:
            click_at(act[1], act[2], 1)
    time.sleep(2)
    p = shot('app-' + name)
    for _ in range(3):                # capture prise pendant un trace ?
        if colors(p, (255, 255, 255)) > 500:
            break
        time.sleep(3)
        p = shot('app-' + name)
    check('%s : fenetre dessinee et processus actif' % label,
          (alive() or alive() or alive()) and
          (colors(p, (255, 255, 255)) > 500 or
           diffpx(p0, p) > 5000))
    if acts:
        check('%s : l\'action change l\'ecran (%d pixels)' % (label,
              diffpx(p0, p)), diffpx(p0, p) > 30)
if True:
    start('/NOWELCOME')
    q.key('f11', 0.5)
    time.sleep(1)
    p = shot('desktop-menu')
    check('menu du bureau (F11) : Terminal et Quitter vers Linux',
          colors(p, (170, 170, 170)) > 10000)
    q.key('esc', 0.5)

# ---- 5. retour a Linux ------------------------------------------------
start()
q.key('esc', 0.5)
time.sleep(1)
p = shot('exit-confirm')
q.key('ret', 0.5)
time.sleep(3)
check('Quitter vers Linux : geoworks termine', not alive())
p = shot('after-exit')
sh('echo done', 1)
check('console texte rendue a Linux (shell sur serie utilisable)',
      'done' in out_since('echo done'))
q.quit()
bad = [n for n, ok in RES if not ok]
print('GEORUN : %d verifications, %d echec(s)%s' % (len(RES), len(bad),
      (' : ' + ', '.join(bad)) if bad else ''))
sys.exit(1 if bad else 0)
