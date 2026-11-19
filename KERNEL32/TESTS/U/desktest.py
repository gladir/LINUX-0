#!/usr/bin/env python3
# @author: Sylvain Maltais (support@gladir.com)
# @created: 2026
# @website(https://www.gladir.com/linux-0)
# @abstract(Target: Python 3, QEMU)
# @description: essais des environnements k32-gnome / k32-kde sous QEMU
#   (-vga std ou vmware) : lancement, captures, couleurs caracteristiques
#   (barre superieure noire Adwaita, panneau Breeze), frappe dans la fenetre
#   Terminal (sendkey), fichier cree par la commande tapee, vue Activites,
#   lanceur KDE, sortie par Deconnexion, repli de k32-session.
#   Usage : desktest.py IMAGE.img TRAVAIL CAPTURES [std|vmware]
import os, re, subprocess, sys, time
exec(open(os.path.join(os.path.dirname(os.path.abspath(__file__)),
                       'QCTL.PY')).read().replace("if __name__ == '__main__':",
                                                  "if False:"))
IMG, WORK, CAPDIR = sys.argv[1:4]
VGA = sys.argv[4] if len(sys.argv) > 4 else 'std'
os.makedirs(WORK, exist_ok=True)
os.makedirs(CAPDIR, exist_ok=True)
ok = ko = 0


def check(name, cond, extra=''):
    global ok, ko
    if cond:
        ok += 1
        print('ok    ' + name)
    else:
        ko += 1
        print('ECHEC ' + name + ' ' + str(extra)[:200])


def px(q, name, rgb, tol=6):
    q.shot(name)
    from PIL import Image
    im = Image.open(os.path.join(q.work, name + '.ppm')).convert('RGB')
    r0, g0, b0 = rgb
    n = 0
    for (r, g, b) in im.getdata():
        if abs(r - r0) <= tol and abs(g - g0) <= tol and abs(b - b0) <= tol:
            n += 1
    return n


def cap(q, name, tag):
    p = q.shot(name)
    if p.endswith('.png'):
        subprocess.run(['cp', p, os.path.join(CAPDIR, tag + '.png')])


def serial_run(q, cmd, wait=30):
    mk = 'M%d' % int(time.time() * 1000 % 100000)
    q.serial('echo %s-B; %s; echo %s-E\n' % (mk, cmd, mk))
    q.wait(r'(?m)^%s-E' % mk, wait)
    time.sleep(0.3)
    t = q.text()
    m = re.findall(r'(?m)^' + mk + r'-B\n(.*?)^' + mk + '-E', t, re.S)
    return m[-1] if m else ''


def run_env(kind, prog, tag, bar, panel):
    img = os.path.join(WORK, tag + '.img')
    subprocess.run(['cp', IMG, img], check=True)
    q = Q(os.path.join(WORK, tag), ['-m', '256', '-vga', VGA, '-drive',
          'file=%s,format=raw,if=ide' % img], serial_io=True)
    check(tag + ' : amorce (login:)', q.wait(r'login:', 120))
    q.serial('root\n')
    time.sleep(1.5)
    q.serial('root\n')
    time.sleep(2.5)
    q.serial('%s > /tmp/%s.log 2>&1 &\n' % (prog, tag))
    time.sleep(6)
    cap(q, 'a', tag + '-01-bureau')
    if bar:
        check(tag + ' : fond Adwaita degrade bleu-violet',
              px(q, 'p1', (0x24, 0x5a, 0x91), 14) > 20000, 'pixels')
    if panel:
        check(tag + ' : panneau Breeze', px(q, 'p2', panel) > 20000)
    q.type('echo K32DESK-OK > /tmp/%s.txt' % tag)
    q.key('ret')
    time.sleep(2.5)
    cap(q, 'b', tag + '-02-terminal')
    out = serial_run(q, 'cat /tmp/%s.txt' % tag)
    check(tag + ' : commande tapee dans la fenetre Terminal executee',
          'K32DESK-OK' in out, out)
    q.type('ls /usr/bin | head -40')
    q.key('ret')
    time.sleep(2)
    cap(q, 'c', tag + '-03-ls')
    q.key('alt-f1')
    time.sleep(2)
    cap(q, 'd', tag + '-04-menu')
    q.key('esc')
    time.sleep(1)
    cap(q, 'e', tag + '-05-apres')
    return q


def shot_size(q, name):
    q.shot(name)
    from PIL import Image
    return Image.open(os.path.join(q.work, name + '.ppm')).size


def run_boot(mode, tag, bar, panel, tablet=False):
    """session choisie dans /etc/k32/session : init lance k32-session sur
    tty1, le bureau apparait sans intervention ; Alt+F2 ; deconnexion"""
    img = os.path.join(WORK, tag + '.img')
    subprocess.run(['cp', IMG, img], check=True)
    pf = os.path.join(WORK, tag + '.sess')
    open(pf, 'w').write(mode + '\n')
    subprocess.run(['debugfs', '-w', '-R', 'rm /etc/k32/session',
                    img + '?offset=1048576'], capture_output=True)
    subprocess.run(['debugfs', '-w', '-R', 'write %s /etc/k32/session' % pf,
                    img + '?offset=1048576'], capture_output=True)
    extra = []
    qsock = os.path.join(WORK, tag + '.qmp')
    if tablet:
        # pointeur absolu : tablette USB (EV_ABS sur /dev/input/event*)
        if os.path.exists(qsock):
            os.unlink(qsock)
        extra = ['-device', 'pci-ohci,id=ohci', '-device',
                 'usb-tablet,bus=ohci.0', '-qmp',
                 'unix:%s,server,nowait' % qsock]
    q = Q(os.path.join(WORK, tag), ['-m', '256', '-vga', VGA, '-drive',
          'file=%s,format=raw,if=ide' % img] + extra, serial_io=True)
    check(tag + ' : amorce (login: sur le port serie)', q.wait(r'login:', 120))
    time.sleep(8)
    cap(q, 'a', tag + '-boot-01-bureau')
    logged = False
    if tablet:
        # noyau ou l'USB est optionnel : activation a chaud (le bureau
        # detecte le pointeur absolu en 2 s)
        q.serial('root\n')
        time.sleep(1.5)
        q.serial('root\n')
        time.sleep(2.5)
        logged = True
        serial_run(q, '[ -w /proc/sys/k32/usb_enable ] && echo 1 > '
                   '/proc/sys/k32/usb_enable')
        time.sleep(5)
        qm = Qmp(qsock)
        n0 = px(q, 'ta', (0x24, 0x5a, 0x91), 14)
        qm.abs(50, 12)                  # "Activites" (barre du haut)
        time.sleep(0.5)
        qm.click()
        time.sleep(1.5)
        n1 = px(q, 'tb', (0x24, 0x5a, 0x91), 14)
        cap(q, 'tb', tag + '-boot-01b-activites-tablette')
        check(tag + ' : tablette (pointeur absolu) : clic sur Activites '
              'change l\'ecran (%d -> %d)' % (n0, n1), abs(n1 - n0) > 5000)
        qm.click()                      # referme la vue
        time.sleep(1)
    if bar:
        check(tag + ' : bureau lance par init sur tty1 (fond Adwaita)',
              px(q, 'p1', (0x24, 0x5a, 0x91), 14) > 20000)
    if panel:
        check(tag + ' : bureau lance par init sur tty1 (panneau Breeze)',
              px(q, 'p2', panel) > 20000)
    if not logged:
        q.serial('root\n')
        time.sleep(1.5)
        q.serial('root\n')
        time.sleep(2.5)
    out = serial_run(q, 'ps | grep -c "k32-%s"' % mode)
    check(tag + ' : processus k32-%s present' % mode, out.strip() not in
          ('', '0'), out)
    q.key('alt-f2')
    time.sleep(2)
    sz = shot_size(q, 'v2')
    check(tag + ' : Alt+F2 : autre terminal texte (taille ecran %s)' %
          (sz,), sz[0] != 1024, sz)
    cap(q, 'f', tag + '-boot-02-altf2')
    q.key('alt-f1')
    time.sleep(2)
    sz = shot_size(q, 'v1')
    check(tag + ' : Alt+F1 : retour au bureau (%s)' % (sz,), sz[0] == 1024, sz)
    q.key('ctrl-alt-delete')
    time.sleep(1.5)
    cap(q, 'g', tag + '-boot-03-menu-session')
    q.key('ret')
    time.sleep(5)
    out = serial_run(q, 'ps | grep -c "k32-%s"' % mode)
    cnt = out.strip()
    check(tag + ' : Deconnexion : le bureau se termine', cnt in ('1', '0'), out)
    time.sleep(2)
    sz = shot_size(q, 'v3')
    txt = px(q, 'v4', (170, 170, 170), 20)
    out = serial_run(q, 'ps | grep -c getty', 10)
    if out.strip():
        check(tag + ' : retour au login texte sur tty1 (ecran %s, getty %s)' %
              (sz, out.strip()), sz[0] == 720 and txt > 100 and
              out.strip() != '0', (sz, out))
    else:
        # la console serie ne repond plus apres un cycle bureau (bug noyau
        # signale a D7, DEMANDES_D7.md) : on ne juge que l'ecran
        check(tag + ' : retour au login texte sur tty1 (ecran %s, texte %d '
              'pixels ; serie muette, voir DEMANDES_D7)' % (sz, txt),
              sz[0] == 720 and txt > 100, (sz, txt))
    cap(q, 'h', tag + '-boot-04-login')
    q.quit()


def main():
    run_boot('gnome', 'bgnome', (0, 0, 0), None, True)
    run_boot('kde', 'bkde', None, (0x23, 0x26, 0x29))

main()
print('DESK-FIN ok=%d ko=%d' % (ok, ko))
sys.exit(1 if ko else 0)
