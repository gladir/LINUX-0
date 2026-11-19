#!/usr/bin/env python3
# @author: Sylvain Maltais (support@gladir.com)
# @created: 2026
# @website(https://www.gladir.com/linux-0)
# @description: Banc d'essai de l'unite Graph, de la souris et du clavier de
#   LPC -3X sous QEMU (appele par RUNGFX.SH) :
#   prim   TESTS/C/UX11.PAS dessine une scene sur /dev/fb0 ; la capture
#          d'ecran (screendump) est comparee pixel par pixel a l'image que le
#          meme programme produit sur l'hote (GFXMEM=1, GfxDump) ; la console
#          texte doit revenir (720x400) a la fin
#   mouse  programme Intr 33h : mouse_move / mouse_button / sendkey, les
#          positions et codes recus sont lus sur le port serie
#   geo    GEOWORKS.PAS de DEV-COOLS (non modifie, compile avec
#          -DFPC,UNIX) : accueil, clic, fenetre Notepad, texte tape au
#          clavier, "Entrer sous DOS" (fork + execve de /bin/sh) et retour
#   usage : gfxt.py WORK LPC KERNEL.ELF CAPDIR vga scenario...
#           vga : std | vmware (ajoute fbvmw ; 800x600 : voir LPC.TXT)
import os, subprocess, sys, time
exec(open(os.path.join(os.path.dirname(os.path.abspath(__file__)),
                       'QCTL.PY')).read().replace("if __name__ == '__main__':",
                                                  "if False:"))
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
K32 = os.path.abspath(os.path.join(HERE, '..', '..'))
WORK, LPC, KERN, CAPDIR, VGA = sys.argv[1:6]
SCEN = sys.argv[6:] or ['prim', 'mouse', 'geo', 'dos', 'bench', 'robust']
GEO = os.environ.get('GEOWORKS', '/home/user/dev-cools/GEOWORKS.PAS')
RES = []


def check(name, ok, detail=''):
    RES.append((name, bool(ok)))
    print(('ok    ' if ok else 'ECHEC ') + name +
          ((' : ' + str(detail)) if (detail and not ok) else ''), flush=True)
    return ok


def sh(cmd, **kw):
    return subprocess.run(cmd, shell=True, capture_output=True, text=True, **kw)


def build():
    """racine de l'essai : init, sh, programmes de test, GEOWORKS"""
    b = os.path.join(WORK, 'b')
    root = os.path.join(WORK, 'root')
    sh('rm -rf %s %s' % (b, root))
    for d in ('sbin', 'bin', 'etc', 'dev', 'proc', 'sys', 'tmp'):
        os.makedirs(os.path.join(root, d))
    os.makedirs(b)
    for f in ('INIT.PAS', 'SH.PAS'):
        sh('cp %s/USR/%s %s' % (K32, f, b))
    sh('cp %s/USR/*.INC %s/USR/INSTALLER/LAYOUTS.INC %s' % (K32, K32, b))
    for f in ('UX11', 'UX12', 'UX13'):
        sh('cp %s/TESTS/C/%s.PAS %s' % (K32, f, b))
    sh('cp %s/GFXMS.PAS %s/GFXBENCH.PAS %s/GFXCUR0.PAS %s' %
       (HERE, HERE, HERE, b))
    sh('cp %s %s/GEOWORKS.PAS' % (GEO, b))
    for p, extra in (('INIT', ''), ('SH', ''), ('UX11', ''), ('GFXMS', ''),
                     ('GFXBENCH', ''), ('GFXCUR0', ''),
                     ('GEOWORKS', '-DFPC,UNIX')):
        r = sh('cd %s && %s -3X -q %s %s.PAS' % (b, LPC, extra, p))
        if r.returncode:
            print('compilation de %s impossible : %s' %
                  (p, r.stdout + r.stderr))
            sys.exit(1)
    sh('cp %s/INIT %s/sbin/init; cp %s/SH %s/bin/sh; cp %s/UX11 %s/bin/ux11; '
       'cp %s/GFXMS %s/bin/gfxms; cp %s/GEOWORKS %s/bin/geoworks; '
       'cp %s/GFXBENCH %s/bin/gfxbench; cp %s/GFXCUR0 %s/bin/gfxcur0' %
       ((b, root) * 7))
    return root


def initrd(root, prog):
    open(os.path.join(root, 'etc', 'inittab'), 'w').write(
        '1::once:/bin/sh /etc/run1\n')
    open(os.path.join(root, 'etc', 'run1'), 'w').write(
        '%s </dev/tty1 >/dev/ttyS0 2>&1\necho rc=$? >/dev/ttyS0\n' % prog)
    out = os.path.join(WORK, 'initrd.gz')
    sh('python3 %s/TOOLS/MKINITRD.PY %s %s' % (K32, root, out))
    return out


def start(name, rd, ahci=False):
    args = ['-kernel', KERN, '-initrd', rd, '-m', '256', '-vga', VGA,
            '-append', 'console=ttyS0' + (' fbvmw' if VGA == 'vmware' else '')]
    if ahci:
        disk = os.path.join(WORK, 'd.img')
        sh('truncate -s 16M %s' % disk)
        args += ['-device', 'ich9-ahci,id=ahci', '-drive',
                 'file=%s,format=raw,if=none,id=d0' % disk, '-device',
                 'ide-hd,drive=d0,bus=ahci.0']
    q = Q(os.path.join(WORK, name), args)
    return q


def cap(q, name, tag):
    p = q.shot(name)
    if CAPDIR and p.endswith('.png'):
        os.makedirs(CAPDIR, exist_ok=True)
        sh('cp %s %s/%s-%s.png' % (p, CAPDIR, VGA, tag))
    return os.path.join(q.work, name + '.ppm')


def load(ppm):
    return Image.open(ppm).convert('RGB')


def px(im, x, y):
    return im.getpixel((x, y))


def scen_prim(root):
    host = os.path.join(WORK, 'host.ppm')
    w, h = (640, 480) if VGA == 'std' else (800, 600)
    env = 'GFXMEM=1 SCENEOUT=%s GFXMODE=%dx%d' % (host, w, h)
    sh('cd %s/b && %s ./UX11 </dev/null >host.txt' % (WORK, env))
    rd = initrd(root, 'GFXNOCUR=1 GFXMODE=%dx%d /bin/ux11 HOLD' % (w, h)
                if VGA != 'std' else 'GFXNOCUR=1 /bin/ux11 HOLD')
    q = start('q-prim', rd, ahci=(VGA == 'std'))
    ok = q.wait('sum  scene', 60)
    check('prim %s : programme termine' % VGA, ok)
    time.sleep(1.5)
    pp = cap(q, 'prim', 'prim')
    a, b = load(pp), Image.open(host).convert('RGB')
    check('prim %s : taille %s' % (VGA, a.size), a.size == (w, h), a.size)
    diff = sum(1 for p, r in zip(a.getdata(), b.getdata()) if p != r)
    check('prim %s : image = image de l hote (pixels differents : %d)' %
          (VGA, diff), diff == 0)
    q.wait('rc=', 60)
    time.sleep(1.5)
    pp = cap(q, 'prim2', 'prim-fin')
    t = load(pp)
    nb = sum(1 for p in t.getdata() if p != (0, 0, 0))
    check('prim %s : console texte rendue (%s, %d pixels)' % (VGA, t.size, nb),
          t.size == (720, 400) and nb > 500)
    q.quit()


def scen_mouse(root, env='', tag='mouse'):
    rd = initrd(root, env + '/bin/gfxms')
    q = start('q-' + tag, rd)
    check('%s %s : fonction 00h' % (tag, VGA),
          q.wait('reset ax=65535 bx=3', 60))
    time.sleep(1)
    q.move(50, 30)
    time.sleep(1)
    q.click()
    time.sleep(1)
    for k in ('a', 'up', 'f1', 'f11', 'alt-x', 'delete'):
        q.key(k)
    q.wait('fin', 40)
    t = q.text()
    x0, y0 = (320, 240) if VGA == 'std' else (400, 300)
    check('%s %s : position apres mouse_move' % (tag, VGA),
          ' x=%d y=%d b=0' % (x0 + 50, y0 + 30) in t, t[-400:])
    check('%s %s : bouton enfonce puis relache' % (tag, VGA),
          ' b=1' in t and t.index(' b=1') < t.rindex(' b=0'))
    ks = [l.split()[1] for l in t.split('\n') if l.startswith('key ')]
    check('%s %s : touches 97 | 0 72 | 0 59 | 0 133 | 0 45 | 0 83' %
          (tag, VGA),
          ks == ['97', '0', '72', '0', '59', '0', '133', '0', '45', '0', '83'],
          ks)
    q.quit()


def arrow_at(im, x, y):
    """pointe blanche en (x, y), corps noir en (x + 1, y + 2)"""
    return (px(im, x, y) == (255, 255, 255) and
            px(im, x + 1, y + 2) == (0, 0, 0))


def scen_robust(root):
    """sources d'entree : curseur toujours affiche, relatif toujours lu"""
    w, h = (640, 480) if VGA == 'std' else (800, 600)
    cx, cy = w // 2, h // 2
    open(os.path.join(root, 'etc', 'emptyev'), 'w').close()
    for tag, env, want in (
            ('aucune source', 'MOUSEDEV=/nonexistent MOUSEREL=1 ',
             'rel=aucun abs=aucun'),
            ('absolu silencieux', 'MOUSEEVDEV=/etc/emptyev ',
             'abs=/etc/emptyev')):
        rd = initrd(root, env + '/bin/gfxcur0')
        q = start('q-robust', rd)
        check('robust %s %s : programme lance' % (tag, VGA),
              q.wait('ready', 60))
        time.sleep(1.5)
        check('robust %s %s : sources journalisees (%s)' % (tag, VGA, want),
              want in q.text())
        a = load(cap(q, 'r0', 'robust-%s-centre' % tag.replace(' ', '-')))
        check('robust %s %s : curseur au centre sans aucun evenement' %
              (tag, VGA), arrow_at(a, cx, cy), (px(a, cx, cy),))
        if tag == 'absolu silencieux':
            q.move(50, 30)
            time.sleep(1.5)
            b = load(cap(q, 'r1', 'robust-relatif'))
            check('robust %s %s : le relatif deplace le curseur' % (tag, VGA),
                  arrow_at(b, cx + 50, cy + 30) and
                  not arrow_at(b, cx, cy))
        q.quit()
    scen_mouse(root, 'GFXNOPOLL=1 ', 'nopoll')


def similar(a, b, box):
    ca, cb = a.crop(box), b.crop(box)
    return sum(1 for p, r in zip(list(ca.getdata()), list(cb.getdata()))
               if p != r)


def scen_geo(root):
    rd = initrd(root, '/bin/geoworks')
    q = start('q-geo', rd, ahci=(VGA == 'std'))
    q.wait('init : demarrage', 60)
    time.sleep(8)
    w, h = (640, 480) if VGA == 'std' else (800, 600)
    ox, oy = 0, 0
    a = load(cap(q, 'g1', 'geo-accueil'))
    check('geo %s : accueil %s' % (VGA, a.size), a.size == (w, h))
    check('geo %s : barre de titre grise et fond gris' % VGA,
          px(a, w // 2 + 150, 20) == (85, 85, 85) and
          px(a, 30, h // 2) == (170, 170, 170), (px(a, w // 2 + 150, 20),
                                                  px(a, 30, h // 2)))
    # curseur au centre : le dessiner n'est pas necessaire, on le deplace
    q.move(-190, 150 - h // 2)
    time.sleep(1)
    b = load(cap(q, 'g2', 'geo-souris'))
    check('geo %s : la souris deplace le curseur (image modifiee)' % VGA,
          similar(a, b, (0, 0, w, h)) > 30)
    q.click()
    time.sleep(2)
    c = load(cap(q, 'g3', 'geo-appareils'))
    check('geo %s : clic -> "Choisissez un appareil" (image modifiee)' % VGA,
          similar(b, c, (0, 100, w, h)) > 20000)
    q.click()
    time.sleep(3)
    d = load(cap(q, 'g4', 'geo-notepad'))
    yel = sum(1 for p in d.getdata() if p == (255, 255, 85))
    check('geo %s : clic -> fenetre Notepad jaune (%d pixels)' % (VGA, yel),
          yel > 50000)
    q.type('Bonjour Linux')
    time.sleep(1.5)
    e = load(cap(q, 'g5', 'geo-texte'))
    check('geo %s : texte tape au clavier (pixels modifies)' % VGA,
          similar(d, e, (0, 40, 200, 60)) > 40)
    # retour a l'accueil : Echap ferme la fenetre ? sinon ctrl-q
    q.quit()


def scen_dos(root):
    rd = initrd(root, '/bin/geoworks')
    q = start('q-dos', rd)
    q.wait('init : demarrage', 60)
    time.sleep(8)
    w, h = (640, 480) if VGA == 'std' else (800, 600)
    q.move(0, -34)
    time.sleep(0.5)
    q.click()
    time.sleep(3)
    q.move(0, h // 2 - 22)
    time.sleep(0.5)
    q.click()
    time.sleep(3)
    t = load(cap(q, 'd1', 'geo-dos'))
    check('dos %s : console texte (%s)' % (VGA, t.size), t.size == (720, 400))
    q.type('echo salut Linux\n')
    time.sleep(2)
    check('dos %s : /bin/sh lance par Exec (fork + execve)' % VGA,
          'salut Linux' in q.text())
    q.type('exit\n')
    time.sleep(5)
    g = load(cap(q, 'd2', 'geo-dos-retour'))
    check('dos %s : retour a GEOWORKS (%s)' % (VGA, g.size), g.size == (w, h))
    q.quit()


def parse_stat(t, tag='stat'):
    for l in t.split('\n'):
        if l.startswith(tag):
            d = dict(p.split('=') for p in l.split()[1:])
            return {k: int(v) for k, v in d.items()}
    return None


def scen_bench(root):
    """cout d'un deplacement de souris : appels noyau et pixels (GfxStat)"""
    modes = ['SW', 'HW'] + (['HWC'] if VGA == 'vmware' else [])
    for mode in modes:
        # HWC : curseur materiel du noyau (opt-in GFXHWCUR=1, VMware seul)
        prog = ('export GFXHWCUR=1; /bin/gfxbench HW' if mode == 'HWC'
                else ('GFXNOCUR=1 ' if mode == 'SW' else '') +
                '/bin/gfxbench ' + mode)
        rd = initrd(root, prog)
        q = start('q-bench-' + mode, rd)
        q.wait('ready', 60)
        time.sleep(0.5)
        for i in range(120):
            q.s.send(b'mouse_move 2 1\n')
            time.sleep(0.03)
            if i % 20 == 0:
                q._drain()
        if mode == 'HW':
            # curseur logiciel de l'unite (Intr 33h AX=1) visible a l'ecran
            time.sleep(0.4)
            a = load(cap(q, 'cur', 'bench-curseur'))
            cx, cy = (560, 360) if VGA == 'std' else (640, 420)
            check('bench %s HW : curseur de l unite visible (pointe blanche, '
                  'corps noir)' % VGA,
                  px(a, cx, cy) == (255, 255, 255) and
                  px(a, cx + 1, cy + 2) == (0, 0, 0),
                  (px(a, cx, cy), px(a, cx + 1, cy + 2)))
        q.wait('fin', 30)
        st = parse_stat(q.text())
        q.quit()
        if not check('bench %s %s : compteurs lus' % (VGA, mode), st):
            continue
        mv, lp = max(st['moves'], 1), max(st['loops'], 1)
        sys_ = st['s0'] + st['s1'] + st['s2'] + st['s3'] + st['s4']
        print('      %s %s : %d deplacements, %d tours, appels noyau %d '
              '(%.1f par tour, %.1f par deplacement), ioctl %d, pixels %d '
              '(%d par deplacement), recopies %d' %
              (VGA, mode, mv, lp, sys_, sys_ / lp, sys_ / mv, st['s9'],
               st['s7'], st['s7'] // mv, st['s5']))
        check('bench %s %s : au plus 2,5 appels noyau par tour' % (VGA, mode),
              sys_ <= 2.5 * lp + 2 * mv)
        check('bench %s %s : moins de 600 pixels par deplacement' %
              (VGA, mode), st['s7'] // mv < 600)
        if VGA == 'vmware':
            check('bench vmware %s : commandes UPDATE / curseur du noyau '
                  '(ioctl %d)' % (mode, st['s9']), st['s9'] >= 1)
        if mode == 'HWC':
            check('bench vmware HWC : curseur materiel, aucun pixel ecrit '
                  'par deplacement (%d)' % (st['s7'] // mv),
                  st['s7'] // mv == 0 and st['s9'] >= mv - 2)
        elif VGA == 'vmware' and mode == 'HW':
            check('bench vmware HW : curseur logiciel par defaut '
                  '(pixels %d)' % (st['s7'] // mv), st['s7'] // mv > 100)
        check('bench %s %s : au plus une recopie par deplacement' %
              (VGA, mode), st['s5'] <= mv + 2)


root = build()
for s in SCEN:
    {'prim': scen_prim, 'mouse': scen_mouse, 'geo': scen_geo,
     'dos': scen_dos, 'bench': scen_bench,
     'robust': scen_robust}[s](root)
bad = [n for n, ok in RES if not ok]
print('%d verification(s), %d echec(s)' % (len(RES), len(bad)))
sys.exit(1 if bad else 0)
