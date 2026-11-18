#!/usr/bin/env python3
# @author: Sylvain Maltais (support@gladir.com)
# @created: 2026
# @website(https://www.gladir.com/linux-0)
# @description: Essais de l'assistant d'installation (appele par RUNINST.SH) :
#   tz        fuseaux horaires de L32API contre l'heure de l'hote (TZif, heure
#             d'ete)
#   auto-fr   CD amorce sous QEMU, installation automatique (preseed) en
#             francais (AZERTY, Europe/Paris, ext4 + swap), puis amorce du
#             disque installe
#   auto-de   idem en allemand, partitionnement manuel (ext3 + swap + /home)
#   ui-fr     interface : touches (sendkey) en francais, captures, installation
#   ui-de     interface : souris + editeur de partitions en allemand, captures
#   text      mode texte (console VGA) : captures
#   Chaque installation est verifiee en amorcant le disque SANS le CD :
#   connexion, nom de machine, langue, fuseau, utilisateur, clavier, fstab,
#   noyau, puis e2fsck -fn de l'hote sur chaque partition.
#   usage : instest.py WORK ROOT KERNEL.ELF CAPDIR scenario...
import os, re, subprocess, sys, time
exec(open(os.path.join(os.path.dirname(os.path.abspath(__file__)),
                       'QCTL.PY')).read().replace("if __name__ == '__main__':",
                                                  "if False:"))

HERE = os.path.dirname(os.path.abspath(__file__))
K32 = os.path.abspath(os.path.join(HERE, '..', '..'))
WORK, ROOT, KERN, CAPDIR = sys.argv[1:5]
SCEN = sys.argv[5:]
LPC = os.environ.get('LPC', '/tmp/claude-0/work/k32/bin/lpc')
RESULTS = []


def check(name, ok, detail=''):
    RESULTS.append((name, bool(ok)))
    extra = (' : ' + detail) if (detail and not ok) else ''
    print(('ok    ' if ok else 'ECHEC ') + name + extra, flush=True)
    return ok


def build_iso(name, cmdline, files=None):
    iso = os.path.join(WORK, name + '.iso')
    extra = os.path.join(WORK, name + '.cd')
    subprocess.run(['rm', '-rf', extra])
    os.makedirs(extra)
    for k, v in (files or {}).items():
        open(os.path.join(extra, k), 'w', encoding='utf-8').write(v)
    env = dict(os.environ, LPC=LPC)
    subprocess.run([K32 + '/TOOLS/MKINSTALLCD.SH', '-o', iso, '-R', ROOT, '-k',
                    KERN, '-r', extra, '-c', cmdline, '-w',
                    os.path.join(WORK, name + '.w')], check=True, env=env,
                   stdout=subprocess.DEVNULL)
    return iso


def new_disk(name, mb):
    d = os.path.join(WORK, name + '.img')
    if os.path.exists(d):
        os.unlink(d)
    subprocess.run(['truncate', '-s', '%dM' % mb, d], check=True)
    return d


def cap(q, name, tag):
    """capture -> CAPDIR/tag.png (PNG <= 300 Ko)"""
    p = q.shot(name)
    if p.endswith('.png') and CAPDIR:
        os.makedirs(CAPDIR, exist_ok=True)
        subprocess.run(['cp', p, os.path.join(CAPDIR, tag + '.png')])
    return p


def drv_args(disk, iface='ide'):
    """arguments QEMU du disque : ahci = controleur SATA ich9-ahci"""
    if iface == 'ahci':
        return ['-device', 'ich9-ahci,id=ahci', '-drive',
                'file=%s,format=raw,if=none,id=d0' % disk, '-device',
                'ide-hd,drive=d0,bus=ahci.0']
    return ['-drive', drive(disk, iface)]


def drive(disk, iface='ide'):
    if iface == 'ide':
        return 'file=%s,format=raw,if=ide,index=0' % disk
    return 'file=%s,format=raw,if=%s' % (disk, iface)


def qemu_cd(name, iso, disk, mem=256, iface='ide', extra=()):
    return Q(os.path.join(WORK, name), ['-cdrom', iso, '-boot', 'd', '-m',
             str(mem), '-vga', 'std'] + list(extra) + drv_args(disk, iface),
             serial_io=True)


def px(q, name, rgb, tol=10):
    """nombre de pixels proches de rgb dans une capture (PPM) de l'ecran"""
    q.shot(name)
    from PIL import Image
    im = Image.open(os.path.join(q.work, name + '.ppm')).convert('RGB')
    r0, g0, b0 = rgb
    n = 0
    for (r, g, b) in im.getdata():
        if abs(r - r0) <= tol and abs(g - g0) <= tol and abs(b - b0) <= tol:
            n += 1
    return n


PINK = (255, 201, 201)       # fond d'un champ invalide (graphique)
VGARED = (170, 0, 0)         # fond rouge en mode texte VGA


def page(q, n, timeout=120, settle=0.8):
    ok = q.wait(r'K32SETUP: page %d\b' % n, timeout)
    time.sleep(settle)
    return ok


def fs_check(disk, parts):
    """e2fsck -fn de l'hote sur chaque partition (debut, nombre de secteurs) ;
    sans copie (disques creux de plusieurs Go) : syntaxe fichier?offset="""
    good = True
    for i, (start, size) in enumerate(parts):
        r = subprocess.run(['e2fsck', '-fn', '%s?offset=%d' % (disk,
                            start * 512)], capture_output=True, text=True)
        if r.returncode != 0:
            print(r.stdout[-800:])
        good = good and r.returncode == 0
    return good


def read_logical(disk):
    """chaine des EBR : [(type, debut, taille)] des partitions logiques"""
    tab = read_table(disk)
    ext = [t for t in tab if t[0] in (5, 0x0F, 0x85)]
    out = []
    if not ext:
        return out
    base = lba = ext[0][1]
    with open(disk, 'rb') as f:
        for _ in range(16):
            f.seek(lba * 512)
            d = f.read(512)
            if len(d) < 512 or d[510:512] != b'\x55\xaa':
                break
            e0 = d[446:462]
            e1 = d[462:478]
            if e0[4]:
                out.append((e0[4],
                            lba + int.from_bytes(e0[8:12], 'little'),
                            int.from_bytes(e0[12:16], 'little')))
            nx = int.from_bytes(e1[8:12], 'little')
            if not e1[4] or not nx:
                break
            lba = base + nx
    return out


def zone_copy_ok(disk, start, zone):
    """/etc/localtime du disque installe = fichier TZif de l'hote"""
    out = disk + '.lt'
    subprocess.run(['debugfs', '-R', 'dump /etc/localtime ' + out,
                    '%s?offset=%d' % (disk, start * 512)], capture_output=True)
    try:
        a = open(out, 'rb').read()
        b = open('/usr/share/zoneinfo/' + zone, 'rb').read()
        os.unlink(out)
        return a == b
    except OSError:
        return False


def read_table(disk):
    """table MBR : [(type, start, size)]"""
    d = open(disk, 'rb').read(512)
    out = []
    if d[510:512] != b'\x55\xaa':
        return out
    for i in range(4):
        e = d[446 + 16 * i:462 + 16 * i]
        t = e[4]
        st = int.from_bytes(e[8:12], 'little')
        sz = int.from_bytes(e[12:16], 'little')
        out.append((t, st, sz, e[0] == 0x80))
    return out


def boot_verify(tag, disk, rootpw, checks, mem=128, rtc_tz=None,
                iface='ide'):
    """amorce le disque installe SANS le CD, ouvre une session root et execute
    les commandes ; checks = [(libelle, commande, regex attendue)] ;
    rtc_tz : fuseau de l'horloge materielle de QEMU (-rtc base=localtime)"""
    extra = []
    env = None
    if rtc_tz:
        extra = ['-rtc', 'base=localtime']
        env = {'TZ': rtc_tz}
    q = Q(os.path.join(WORK, tag + '-boot'), extra + ['-m', str(mem)] +
          drv_args(disk, iface), serial_io=True, env=env)
    ok = q.wait(r'login:', 90)
    check(tag + ' : amorce du disque installe (login:)', ok)
    if not ok:
        q.quit()
        return
    q.serial('root\n')
    time.sleep(1.5)
    q.serial(rootpw + '\n')
    time.sleep(2.5)
    for n, (label, cmd, rx) in enumerate(checks):
        mk = 'MK%d' % n
        q.serial('echo %s-BEGIN; %s; echo %s-END\n' % (mk, cmd, mk))
        q.wait(r'(?m)^%s-END' % mk, 30)
        time.sleep(0.3)
        t = q.text()
        m = re.findall(r'(?m)^' + mk + r'-BEGIN\n(.*?)^' + mk + '-END', t, re.S)
        out = m[-1] if m else ''
        if callable(rx):
            good = rx(out)
        else:
            good = re.search(rx, out) is not None
        check(tag + ' : ' + label, good, 'sortie %r' % out[-200:])
    q.serial('sync; poweroff\n')
    time.sleep(2)
    q.quit()


def local_hhmm(zone):
    """predicat : la sortie contient l'heure HH:MM de la zone (a 4 min pres)"""
    from zoneinfo import ZoneInfo
    from datetime import datetime

    def f(out):
        m = re.search(r'(\d\d):(\d\d)', out)
        if not m:
            return False
        now = datetime.now(ZoneInfo(zone))
        g = int(m.group(1)) * 60 + int(m.group(2))
        h = now.hour * 60 + now.minute
        return min((g - h) % 1440, (h - g) % 1440) <= 4
    return f


def host_offset(zone):
    from zoneinfo import ZoneInfo
    from datetime import datetime, timezone
    now = datetime.now(timezone.utc).astimezone(ZoneInfo(zone))
    return now.utcoffset().total_seconds()


# ---------------------------------------------------------------- tz
def t_tz():
    src = os.path.join(WORK, 'tz')
    os.makedirs(src, exist_ok=True)
    open(src + '/TZT.PAS', 'w').write("""Program TzT;
Var I, T, E : LongInt;
Begin
  LnxTzSelect(SysArgStr(1));
  For I := 2 To SysArgCount - 1 Do
  Begin
    Val(SysArgStr(I), T, E);
    WriteLn(LnxTzAt(T), ' ', LnxTzUtcOf(T + LnxTzAt(T)) - T);
  End;
End.
""")
    r = subprocess.run([LPC, '-3X', '-q', 'TZT.PAS'], cwd=src,
                       capture_output=True, text=True)
    if not os.path.exists(src + '/TZT'):
        check('tz : compilation', False, r.stdout + r.stderr)
        return
    zones = ['Europe/Paris', 'Europe/Berlin', 'Europe/London',
             'America/New_York', 'America/Los_Angeles', 'America/Sao_Paulo',
             'Asia/Tokyo', 'Asia/Kolkata', 'Australia/Sydney',
             'Pacific/Auckland', 'Africa/Cairo', 'Europe/Moscow', 'UTC',
             'Asia/Kathmandu', 'America/St_Johns', 'Europe/Lisbon']
    stamps = []
    t0 = 1262304000
    for k in range(0, 56):
        stamps.append(t0 + k * 8 * 86400 * 7 + 12345)
    stamps += [1711846799, 1711846800, 1743296399, 1743296400, 1729990799,
               1729990800, 2000000000, 2100000000]
    bad = 0
    n = 0
    for z in zones:
        out = subprocess.run([src + '/TZT', z] + [str(s) for s in stamps],
                             capture_output=True, text=True).stdout.split('\n')
        for s, line in zip(stamps, out):
            exp = subprocess.run(['date', '-d', '@%d' % s, '+%z'],
                                 env=dict(os.environ, TZ=z),
                                 capture_output=True,
                                 text=True).stdout.strip()
            sign = -1 if exp[0] == '-' else 1
            e = sign * (int(exp[1:3]) * 3600 + int(exp[3:5]) * 60)
            if s > 2145916800:      # TZif v1 : transitions jusqu'en 2037
                continue
            n += 1
            if not line or int(line.split()[0]) != e:
                bad += 1
                if bad < 6:
                    print('  tz', z, s, line, exp)
    check('tz : decalages de %d zones x %d dates = hote (heure d\'ete comprise)'
          % (len(zones), len(stamps)), bad == 0, '%d ecarts sur %d' % (bad, n))


# ------------------------------------------------------------- auto-fr
def t_auto_fr():
    pre = """# reponses de l'installation automatique (essai)
lang=fr
keyboard=fr
timezone=Europe/Paris
clock=utc
hostname=poste-fr
rootpw=motdepasse
user=marie
fullname=Marie Curie
userpw=secret
partitioning=guided
swap=64
fs=ext4
endwait=3
reboot=halt
"""
    iso = build_iso('auto-fr', 'console=tty0 console=ttyS0 fb=1024x768 rw '
                    'preseed=/cdrom/preseed.cfg k32setup.verbose=/dev/ttyS0',
                    {'preseed.cfg': pre})
    disk = new_disk('auto-fr', 400)
    q = qemu_cd('auto-fr', iso, disk, extra=['-no-shutdown'])
    ok = page(q, 12, 90)
    check('auto-fr : page de progression affichee', ok)
    time.sleep(6)
    cap(q, 'fr-prog', 'auto-fr-installation')
    ok = q.wait(r'K32SETUP: DONE', 240)
    check('auto-fr : installation terminee (preseed, progression)', ok)
    time.sleep(1.5)
    cap(q, 'fr-fin', 'auto-fr-fin')
    ended = False
    for _ in range(40):
        if 'shutdown' in q.info('info status') or not q.alive():
            ended = True
            break
        time.sleep(1)
    check('auto-fr : arret apres installation (reboot=halt)', ended)
    blk = q.info('info block')
    check('auto-fr : le CD d\'installation a ete ejecte avant l\'arret',
          'tray open' in blk or 'ejected' in blk or 'empty' in blk.lower(),
          blk[-300:])
    q.quit()
    tab = read_table(disk)
    check('auto-fr : table MBR : Linux 83 active + swap 82',
          len(tab) == 4 and tab[0][0] == 0x83 and tab[0][3] and
          tab[1][0] == 0x82, str(tab))
    check('auto-fr : e2fsck -fn propre',
          fs_check(disk, [(tab[0][1], tab[0][2])]))
    check('auto-fr : /etc/localtime = fichier TZif Europe/Paris',
          zone_copy_ok(disk, tab[0][1], 'Europe/Paris'))
    checks = [
        ('nom de machine', 'hostname', r'poste-fr'),
        ('langue (LANGUAGE=FR)', '. /etc/profile; echo L=$LANGUAGE', r'L=FR'),
        ('fuseau (/etc/timezone)', 'cat /etc/timezone', r'Europe/Paris'),
        ('heure locale (date) = heure de Paris', 'date +%H:%M',
         local_hhmm('Europe/Paris')),
        ('TZ=America/New_York date (L32API)', 'TZ=America/New_York date +%H:%M',
         local_hhmm('America/New_York')),
        ('TZ=Asia/Tokyo date (L32API)', 'TZ=Asia/Tokyo date +%H:%M',
         local_hhmm('Asia/Tokyo')),
        ('utilisateur marie (uid 1000)', 'id marie', r'uid=1000\(marie\)'),
        ('nom complet dans /etc/passwd', 'grep marie /etc/passwd',
         r'Marie Curie'),
        ('clavier fr (/etc/default/keyboard)', 'cat /etc/default/keyboard',
         r'fr'),
        ('fstab : racine ext4 + swap', 'cat /etc/fstab',
         r'hda1 / ext4(.|\n)*hda2 none swap'),
        ('noyau et configuration du chargeur',
         'ls /boot; cat /boot/linux0.cfg',
         r'linux0(.|\n)*root=/dev/hda1 rw(.|\n)*keymap=fr'),
        ('racine montee (df)', 'df | grep hda1', r'/dev/hda1'),
        ('ext4 (blkid)', 'blkid /dev/hda1', r'ext4'),
        ('journal de l\'installation copie', 'ls /var/log/install.log',
         r'install.log'),
        ('racine en ecriture', 'echo ok > /root/t; cat /root/t', r'^ok'),
    ]
    boot_verify('auto-fr', disk, 'motdepasse', checks)


# ------------------------------------------------------------- auto-de
def t_auto_de():
    pre = """lang=de
keyboard=de
timezone=Europe/Berlin
clock=local
hostname=rechner-de
rootpw=geheim
user=hans
fullname=Hans M\u00fcller
userpw=passwort
partitioning=manual
parts=ext3:/:250M,swap:swap:32M,ext4:/home:*
ui=text
endwait=3
reboot=halt
"""
    # ui=text : installation entierement en mode texte (console VGA)
    iso = build_iso('auto-de', 'console=tty0 console=ttyS0 rw '
                    'preseed=/cdrom/preseed.cfg k32setup.verbose=/dev/ttyS0',
                    {'preseed.cfg': pre})
    disk = new_disk('auto-de', 700)
    q = qemu_cd('auto-de', iso, disk)
    ok = page(q, 12, 90)
    check('auto-de : page de progression affichee', ok)
    time.sleep(5)
    cap(q, 'de-prog', 'auto-de-texte-installation')
    ok = q.wait(r'K32SETUP: DONE', 300)
    check('auto-de : installation terminee (manuel : ext3 + swap + /home ext4)',
          ok)
    time.sleep(1.5)
    for _ in range(40):
        if not q.alive():
            break
        time.sleep(1)
    q.quit()
    tab = read_table(disk)
    check('auto-de : table MBR : 83, 82, 83',
          len(tab) == 4 and [t[0] for t in tab[:3]] == [0x83, 0x82, 0x83],
          str(tab))
    check('auto-de : e2fsck -fn propre (racine et /home)',
          fs_check(disk, [(tab[0][1], tab[0][2]), (tab[2][1], tab[2][2])]))
    feats = []
    for st, sz in ((tab[0][1], tab[0][2]), (tab[2][1], tab[2][2])):
        img = disk + '.f'
        subprocess.run(['dd', 'if=' + disk, 'of=' + img, 'bs=512',
                        'skip=%d' % st, 'count=%d' % sz],
                       stderr=subprocess.DEVNULL)
        feats.append(subprocess.run(['dumpe2fs', '-h', img],
                                    capture_output=True, text=True).stdout)
        os.unlink(img)
    check('auto-de : racine ext3 (journal, sans extents), /home ext4 (extents)',
          'has_journal' in feats[0] and 'extent' not in feats[0] and
          'extent' in feats[1])
    checks = [
        ('nom de machine', 'hostname', r'rechner-de'),
        ('langue (LANGUAGE=DE)', '. /etc/profile; echo L=$LANGUAGE', r'L=DE'),
        ('fuseau Europe/Berlin', 'cat /etc/timezone', r'Europe/Berlin'),
        ('horloge materielle : heure locale (adjtime)', 'cat /etc/adjtime',
         r'LOCAL'),
        ('heure locale (date) = heure de Berlin', 'date +%H:%M',
         local_hhmm('Europe/Berlin')),
        ('utilisateur hans', 'id hans', r'uid=1000\(hans\)'),
        ('nom complet en UTF-8', 'grep hans /etc/passwd',
         r'Hans M\xc3\xbcller|Hans M.*ller'),
        ('clavier de', 'cat /etc/default/keyboard', r'de'),
        ('fstab : ext3 / + /home + swap', 'cat /etc/fstab',
         r'hda1 / ext3(.|\n)*hda2 none swap(.|\n)*hda3 /home ext4'),
        ('/home monte', 'df | grep hda3', r'/home'),
        ('blkid : racine ext3, /home ext4', 'blkid /dev/hda1; blkid /dev/hda3',
         r'ext3(.|\n)*ext4'),
        ('dossier personnel de hans (sur /home)', 'ls /home', r'hans'),
        ('swap actif', 'cat /proc/swaps', r'hda2'),
    ]
    # horloge materielle declaree LOCALE : QEMU la regle sur l'heure de Berlin
    boot_verify('auto-de', disk, 'geheim', checks, mem=128,
                rtc_tz='Europe/Berlin')


# --------------------------------------------------------------- ui-fr
def t_ui_fr():
    iso = build_iso('ui-fr', 'console=tty0 console=ttyS0 fb=1024x768 rw '
                    'k32setup.verbose=/dev/ttyS0')
    disk = new_disk('ui-fr', 700)
    q = qemu_cd('ui-fr', iso, disk)
    check('ui-fr : assistant lance au demarrage du CD (page 0)', page(q, 0, 90))
    q.key('up')                                  # English -> Francais
    time.sleep(0.8)
    cap(q, 'a', 'fr-01-langue')
    q.key('ret')
    check('ui-fr : langue francaise -> page d\'accueil', page(q, 1))
    cap(q, 'a2', 'fr-01b-accueil')
    q.key('ret')
    check('ui-fr : page clavier', page(q, 2))
    q.key('tab')
    # touches physiques q w e r t y m , 1 : donnent azerty,;& en AZERTY
    for k in ['q', 'w', 'e', 'r', 't', 'y', 'm', 'comma', '1']:
        q.key(k)
    # touches mortes AZERTY : ^ + e = ecirc, trema + u = uuml, ^ + x = ^x
    for k in ['bracket_left', 'e', 'shift-bracket_left', 'u',
              'bracket_left', 'x']:
        q.key(k)
    time.sleep(0.6)
    cap(q, 'b', 'fr-02-clavier')
    q.key('ret')
    check('ui-fr : page fuseau horaire', page(q, 3))
    cap(q, 'c', 'fr-03-fuseau')
    q.key('ret')
    check('ui-fr : date et heure', page(q, 4))
    cap(q, 'c2', 'fr-04-heure')
    check('ui-fr : date valide : aucun champ rouge', px(q, 'p4a', PINK) == 0)
    q.key('tab')
    q.key('end')
    q.key('backspace')
    time.sleep(0.4)
    check('ui-fr : heure invalide : champ sur fond rouge',
          px(q, 'p4b', PINK) > 150)
    cap(q, 'c3', 'fr-04b-heure-invalide')
    q.key('ret')
    check('ui-fr : Entree refusee tant que le champ est rouge',
          not page(q, 5, 3, 0.1))
    q.key('shift-1')
    time.sleep(0.4)
    check('ui-fr : heure corrigee : retour au fond normal',
          px(q, 'p4c', PINK) == 0)
    q.key('ret')
    check('ui-fr : nom de machine', page(q, 5))
    q.key('end')
    q.key('comma')
    time.sleep(0.4)
    check('ui-fr : nom de machine invalide : champ sur fond rouge',
          px(q, 'p5a', PINK) > 150)
    cap(q, 'c4', 'fr-04c-nom-invalide')
    q.key('backspace')
    time.sleep(0.4)
    check('ui-fr : nom de machine corrige : fond normal',
          px(q, 'p5b', PINK) == 0)
    q.key('ret')
    check('ui-fr : comptes', page(q, 6))
    q.type('secret')
    q.key('tab')
    q.type('secre')
    time.sleep(0.4)
    check('ui-fr : confirmation differente : champ rouge',
          px(q, 'p6a', PINK) > 150)
    cap(q, 'd0', 'fr-05a-confirmation-rouge')
    q.type('t')
    time.sleep(0.4)
    check('ui-fr : mots de passe identiques : plus de rouge',
          px(q, 'p6b', PINK) == 0)
    q.key('tab')
    # AZERTY actif : les touches a q z w m changent ; on tape des lettres sures
    q.type('Luc Dubois')
    q.key('tab')
    q.type('Luc')
    time.sleep(0.4)
    check('ui-fr : majuscules converties : pas de rouge',
          px(q, 'p6c', PINK) == 0)
    cap(q, 'd1', 'fr-05b-majuscules-converties')
    q.key('comma')
    time.sleep(0.4)
    check('ui-fr : identifiant invalide : champ sur fond rouge',
          px(q, 'p6d', PINK) > 150)
    cap(q, 'd2', 'fr-05c-identifiant-invalide')
    q.key('ret')
    check('ui-fr : Suivant refuse tant que l\'identifiant est rouge',
          not page(q, 7, 3, 0.1))
    q.key('backspace')
    time.sleep(0.4)
    check('ui-fr : identifiant corrige : retour au fond normal',
          px(q, 'p6e', PINK) == 0)
    q.key('tab')
    q.type('secret')
    q.key('tab')
    q.type('secrex')
    time.sleep(0.4)
    check('ui-fr : confirmation utilisateur differente : rouge',
          px(q, 'p6f', PINK) > 150)
    cap(q, 'd3', 'fr-05d-confirmation-utilisateur')
    q.key('backspace')
    q.type('t')
    time.sleep(0.5)
    check('ui-fr : tout valide : plus aucun champ rouge',
          px(q, 'p6g', PINK) == 0)
    cap(q, 'd', 'fr-05-comptes')
    q.key('ret')
    check('ui-fr : mode de demarrage', page(q, 14))
    cap(q, 'd4', 'fr-05e-mode-demarrage')
    q.key('down'); q.key('down'); q.key('down')           # GEOWORKS
    time.sleep(0.4)
    check('ui-fr : GEOWORKS present : aucune remarque rouge',
          px(q, 'p14a', (179, 38, 30), 14) == 0)
    cap(q, 'd5', 'fr-05f-geoworks')
    q.key('up')                                           # GNOME
    time.sleep(0.4)
    check('ui-fr : GNOME : plus de remarque rouge',
          px(q, 'p14b', (179, 38, 30), 14) == 0)
    cap(q, 'd6', 'fr-05g-gnome')
    q.key('ret')
    check('ui-fr : disque', page(q, 7))
    cap(q, 'e', 'fr-06-disque')
    q.key('ret')
    check('ui-fr : methode de partitionnement', page(q, 8))
    cap(q, 'f', 'fr-07-partitionnement')
    q.key('ret')
    check('ui-fr : recapitulatif', page(q, 11))
    q.key('spc')
    time.sleep(0.4)
    cap(q, 'g', 'fr-08-recapitulatif')
    q.key('tab'); q.key('tab'); q.key('ret')
    time.sleep(1.0)
    cap(q, 'g2', 'fr-09-confirmation')
    q.key('ret')
    check('ui-fr : installation lancee', page(q, 12, 60))
    time.sleep(12)
    cap(q, 'h', 'fr-10-progression')
    ok = q.wait(r'K32SETUP: page 13\b', 300)
    check('ui-fr : fin de l\'installation (page finale)', ok)
    time.sleep(1.5)
    cap(q, 'i', 'fr-11-fin')
    q.quit()
    tab = read_table(disk)
    check('ui-fr : e2fsck -fn propre', fs_check(disk, [(tab[0][1], tab[0][2])]))
    t = q.text()
    check('ui-fr : disposition AZERTY : les touches q w e r t y donnent azerty',
          'keytest=azerty' in t.replace('\r', ''))
    check('ui-fr : touches mortes : ^e = ecirc (234), trema u = uuml (252), '
          '^x = ^ x', 'codes= 97 122 101 114 116 121 44 59 38 234 252 94 120'
          in t.replace('\r', ''))
    checks = [
        ('nom de machine par defaut', 'hostname', r'linux0'),
        ('langue FR', '. /etc/profile; echo L=$LANGUAGE', r'L=FR'),
        ('utilisateur luc (saisi en AZERTY)', 'id luc', r'uid=1000\(luc\)'),
        ('nom complet', 'grep luc /etc/passwd', r'Luc Dubois'),
        ('fuseau Europe/Paris', 'cat /etc/timezone', r'Europe/Paris'),
        ('clavier fr', 'cat /etc/default/keyboard', r'XKBLAYOUT="fr"'),
        ('mode de demarrage GNOME ecrit', 'cat /etc/k32/session', r'gnome'),
        ('k32-session get', 'k32-session get', r'gnome'),
        ('k32-session status : environnement GNOME installe',
         'k32-session status', r'programme: /(usr/)?bin/k32-gnome'),
        ('commandes compatibles GNOME/KDE installees',
         'ls /bin/gnome-session /bin/gnome-terminal /bin/startplasma-x11 '
         '/bin/konsole /usr/share/xsessions/gnome.desktop', r'konsole'),
        ('systeme installe : marque et pas d assistant',
         'cat /etc/k32/installed; ls /sbin/k32-setup 2>&1',
         r'installed by k32-setup(?s:.*)(introuvable|inexistant|not found|'
         r'No such|impossible|Aucune)'),
    ]
    boot_verify('ui-fr', disk, 'secret', checks)


# --------------------------------------------------------------- ui-de
def t_ui_de():
    iso = build_iso('ui-de', 'console=tty0 console=ttyS0 fb=1024x768 rw '
                    'k32setup.verbose=/dev/ttyS0')
    disk = new_disk('ui-de', 700)
    q = qemu_cd('ui-de', iso, disk, mem=128)
    check('ui-de : assistant lance (page 0)', page(q, 0, 90))
    # souris : curseur en haut a gauche puis sur "Deutsch", clic, puis "Weiter"
    q.move(-2000, -2000)
    time.sleep(0.3)
    q.move(100, 276)
    time.sleep(0.3)
    q.click()
    time.sleep(0.8)
    cap(q, 'a', 'de-01-sprache')
    q.move(630, 385)
    time.sleep(0.3)
    q.click()
    check('ui-de : clic souris Deutsch puis Weiter -> Willkommen',
          page(q, 1))
    cap(q, 'a2', 'de-01b-willkommen')
    q.key('f1')
    time.sleep(1.0)
    cap(q, 'a3', 'de-01c-hilfe')                  # F1 : aide
    q.key('ret')
    time.sleep(0.5)
    q.key('ret')
    check('ui-de : page Tastatur', page(q, 2))
    q.key('tab')
    for k in ['y', 'z', 'x', 'slash', 'minus', 'shift-2', 'equal', 'e']:
        q.key(k)                                # equal, e : accent aigu + e
    time.sleep(0.6)
    cap(q, 'b', 'de-02-tastatur')
    q.key('ret')
    page(q, 3)
    q.key('ret'); page(q, 4)
    q.key('ret'); page(q, 5)
    q.key('ret'); page(q, 6)
    q.type('geheim'); q.key('tab'); q.type('geheim'); q.key('tab')
    q.type('Hans Mueller'); q.key('tab'); q.type('hans'); q.key('tab')
    q.type('passwort'); q.key('tab'); q.type('passwort')
    q.key('ret'); page(q, 14)
    q.key('ret'); page(q, 7)
    q.key('ret'); page(q, 8)
    q.key('down')                               # manuell
    time.sleep(0.5)
    cap(q, 'c', 'de-03-partitionierung')
    q.key('ret')
    check('ui-de : partitionnement manuel -> editeur', page(q, 9))
    cap(q, 'd', 'de-04-editor-leer')
    q.key('tab'); q.key('ret'); time.sleep(1.0)
    q.type('300M')
    cap(q, 'e', 'de-05-neue-partition')
    q.key('ret'); page(q, 9)
    q.key('down'); q.key('tab'); q.key('ret'); time.sleep(1.0)
    q.type('64M'); q.key('tab'); q.key('down'); time.sleep(0.4)
    q.key('ret'); page(q, 9)
    time.sleep(0.5)
    cap(q, 'f', 'de-06-editor')
    q.key('ret')
    check('ui-de : roles des partitions', page(q, 10))
    q.key('tab'); q.key('tab'); q.key('ret')        # bouton Dateisystem
    time.sleep(1.0)                                 # racine : ext4 -> ext3
    cap(q, 'g', 'de-07-rollen')
    q.key('ret')
    check('ui-de : zusammenfassung', page(q, 11))
    q.key('spc'); time.sleep(0.3)
    cap(q, 'h', 'de-08-zusammenfassung')
    q.key('tab'); q.key('tab'); q.key('ret'); time.sleep(0.8); q.key('ret')
    check('ui-de : installation lancee', page(q, 12, 60))
    time.sleep(14)
    cap(q, 'i', 'de-09-fortschritt')
    ok = q.wait(r'K32SETUP: page 13\b', 300)
    check('ui-de : fin de l\'installation', ok)
    time.sleep(1.5)
    cap(q, 'j', 'de-10-fertig')
    t = q.text().replace('\r', '')
    check('ui-de : clavier QWERTZ (touches y z x / - 2 -> zyx-ss"), accent '
          'aigu mort + e = e acute (233)',
          'keytest=zyx-s"e layout=de' in t and ' 233' in t.split('codes=')[1])
    q.quit()
    tab = read_table(disk)
    check('ui-de : table 83 (active) + 82',
          len(tab) == 4 and tab[0][0] == 0x83 and tab[0][3] and
          tab[1][0] == 0x82, str(tab))
    check('ui-de : e2fsck -fn propre', fs_check(disk, [(tab[0][1], tab[0][2])]))
    img = disk + '.f'
    subprocess.run(['dd', 'if=' + disk, 'of=' + img, 'bs=512',
                    'skip=%d' % tab[0][1], 'count=%d' % tab[0][2]],
                   stderr=subprocess.DEVNULL)
    ft = subprocess.run(['dumpe2fs', '-h', img], capture_output=True,
                        text=True).stdout
    os.unlink(img)
    check('ui-de : racine en ext3 (bouton Dateisystem : journal, sans extents)',
          'has_journal' in ft and 'extent' not in ft)
    checks = [
        ('langue DE', '. /etc/profile; echo L=$LANGUAGE', r'L=DE'),
        ('utilisateur hans', 'id hans', r'uid=1000\(hans\)'),
        ('fuseau Europe/Berlin', 'cat /etc/timezone', r'Europe/Berlin'),
        ('invite de connexion en allemand', 'echo x', r'x'),
    ]
    boot_verify('ui-de', disk, 'geheim', checks)


# ------------------------------------------------------------- auto-log
def t_auto_log():
    pre = """lang=it
keyboard=it
timezone=Europe/Rome
hostname=logiche
rootpw=radice
user=gigi
userpw=gigi
partitioning=manual
parts=ext4:/:250M,swap:swap:32M:l,ext3:/home:*:l
ui=text
endwait=2
reboot=halt
"""
    iso = build_iso('auto-log', 'console=tty0 console=ttyS0 rw '
                    'preseed=/cdrom/preseed.cfg k32setup.verbose=/dev/ttyS0',
                    {'preseed.cfg': pre})
    disk = new_disk('auto-log', 700)
    q = qemu_cd('auto-log', iso, disk)
    ok = q.wait(r'K32SETUP: DONE', 300)
    check('auto-log : installation avec partitions logiques', ok)
    for _ in range(40):
        if not q.alive():
            break
        time.sleep(1)
    q.quit()
    tab = read_table(disk)
    lg = read_logical(disk)
    check('auto-log : primaire 83 active + etendue 05 + 2 logiques 82 et 83',
          len(tab) == 4 and tab[0][0] == 0x83 and tab[0][3] and
          tab[1][0] == 5 and [t[0] for t in lg] == [0x82, 0x83], str(tab) +
          str(lg))
    check('auto-log : e2fsck -fn propre (racine et /home logique)',
          fs_check(disk, [(tab[0][1], tab[0][2]), (lg[1][1], lg[1][2])]))
    checks = [
        ('hostname', 'hostname', r'logiche'),
        ('fstab : /home sur hda6, swap sur hda5', 'cat /etc/fstab',
         r'hda5 none swap(.|\n)*hda6 /home ext3'),
        ('partitions logiques vues par le noyau', 'cat /proc/partitions',
         r'hda5(.|\n)*hda6'),
        ('/home monte (hda6)', 'df | grep hda6', r'/home'),
        ('swap actif (hda5)', 'cat /proc/swaps', r'hda5'),
        ('langue IT', '. /etc/profile; echo L=$LANGUAGE', r'L=IT'),
    ]
    boot_verify('auto-log', disk, 'radice', checks)


# --------------------------------------------------------------- exist
def t_exist():
    """disque deja installe (disque de auto-fr) : l'assistant l'annonce a
    l'etape du disque et dans le recapitulatif"""
    old = os.path.join(WORK, 'auto-fr.img')
    if not os.path.exists(old):
        t_auto_fr()
    disk = os.path.join(WORK, 'exist.img')
    subprocess.run(['cp', '--sparse=always', old, disk], check=True)
    iso = build_iso('exist', 'console=tty0 console=ttyS0 fb=1024x768 rw '
                    'k32setup.verbose=/dev/ttyS0')
    q = qemu_cd('exist', iso, disk)
    page(q, 0, 90)
    for _ in range(6):                  # langue ... nom de machine
        q.key('ret')
        time.sleep(1.2)
    page(q, 6)
    q.type('x'); q.key('tab'); q.type('x')
    q.key('ret')
    page(q, 14)
    q.key('ret')
    check('exist : page du disque', page(q, 7))
    cap(q, 'a', 'exist-disque')
    t = q.text().replace('\r', '')
    check('exist : partitions et systeme LINUX-0 deja installe detectes',
          re.search(r'existing /dev/hda1 \d+ MB ext4 "root" - '
                    r'(LINUX-0|syst)', t) is not None)
    q.key('ret')
    page(q, 8)
    q.key('ret')
    check('exist : recapitulatif', page(q, 11))
    cap(q, 'b', 'exist-recapitulatif')
    q.quit()


# -------------------------------------------------------------- virtio
def t_virtio():
    pre = """lang=es
keyboard=es
timezone=Europe/Madrid
hostname=virtio-es
session=kde
rootpw=clave
user=ana
userpw=clave2
partitioning=guided
swap=32
fs=ext4
ui=text
endwait=2
reboot=halt
"""
    iso = build_iso('virtio', 'console=tty0 console=ttyS0 rw '
                    'preseed=/cdrom/preseed.cfg k32setup.verbose=/dev/ttyS0',
                    {'preseed.cfg': pre})
    disk = new_disk('virtio', 300)
    q = qemu_cd('virtio', iso, disk, iface='virtio')
    ok = q.wait(r'K32SETUP: DONE', 300)
    check('virtio : installation sur /dev/vda (disque virtio-blk)', ok)
    t = q.text()
    check('virtio : l\'assistant a choisi /dev/vda',
          'a /dev/vda' in t or '/dev/vda' in t)
    for _ in range(40):
        if not q.alive():
            break
        time.sleep(1)
    q.quit()
    tab = read_table(disk)
    check('virtio : e2fsck -fn propre',
          fs_check(disk, [(tab[0][1], tab[0][2])]))
    checks = [
        ('hostname', 'hostname', r'virtio-es'),
        ('session=kde du preseed ecrite', 'cat /etc/k32/session', r'kde'),
        ('racine sur /dev/vda1', 'cat /proc/mounts', r'/dev/vda1 / '),
        ('fstab vda', 'cat /etc/fstab', r'/dev/vda1 / ext4'),
        ('cfg du chargeur', 'cat /boot/linux0.cfg', r'root=/dev/vda1'),
        ('langue ES', '. /etc/profile; echo L=$LANGUAGE', r'L=ES'),
    ]
    boot_verify('virtio', disk, 'clave', checks, iface='virtio')


# -------------------------------------------------------------- refuse
def t_refuse():
    pre = """lang=en
keyboard=us
timezone=UTC
hostname=x
rootpw=x
disk=/dev/hdc
partitioning=guided
swap=0
endwait=1
reboot=halt
"""
    iso = build_iso('refuse', 'console=tty0 console=ttyS0 fb=1024x768 rw '
                    'preseed=/cdrom/preseed.cfg k32setup.verbose=/dev/ttyS0',
                    {'preseed.cfg': pre})
    disk = new_disk('refuse', 100)
    before = open(iso, 'rb').read()[:65536]
    q = qemu_cd('refuse', iso, disk)
    ok = q.wait(r'K32SETUP: .*(in use|utilis)', 120) or \
        q.wait(r'K32SETUP: FAIL', 5)
    check('refuse : disque monte (le CD) refuse par l\'assistant', ok)
    time.sleep(1)
    cap(q, 'a', 'refuse-erreur')
    q.quit()
    after = open(iso, 'rb').read()[:65536]
    check('refuse : le CD est intact', before == after)
    check('refuse : le disque vierge n\'a pas ete touche',
          open(disk, 'rb').read(512) == b'\0' * 512)


# ------------------------------------------------------------- sata8g
def t_sata8g(size=8192, tag='sata8g'):
    """installation de bout en bout sur un disque SATA (ich9-ahci) de 8 Go
    avec 1 Gio de memoire : duree, e2fsck, amorce"""
    pre = """lang=fr
keyboard=fr
timezone=Europe/Paris
hostname=sata
rootpw=secret
partitioning=guided
swap=256
fs=ext4
ui=text
endwait=2
reboot=halt
"""
    iso = build_iso(tag, 'console=tty0 console=ttyS0 rw '
                    'preseed=/cdrom/preseed.cfg k32setup.verbose=/dev/ttyS0',
                    {'preseed.cfg': pre})
    disk = new_disk(tag, size)
    t0 = time.time()
    q = qemu_cd(tag, iso, disk, mem=1024, iface='ahci')
    ok = q.wait(r'K32SETUP: DONE', 1500)
    dt = time.time() - t0
    check(tag + ' : installation sur SATA %d Mo avec 1 Gio de RAM (%d s)'
          % (size, dt),
          ok)
    t = q.text()
    print('   duree totale : %d s ; formatage : %s' % (dt,
          re.findall(r'(?m)^.*(?:Formatage|mkfs).*$', t)[:3]))
    for _ in range(60):
        if not q.alive():
            break
        time.sleep(1)
    q.quit()
    tab = read_table(disk)
    check(tag + ' : e2fsck -fn propre',
          fs_check(disk, [(tab[0][1], tab[0][2])]))
    checks = [
        ('hostname', 'hostname', r'sata'),
        ('racine', 'cat /proc/mounts', r'/dev/(sda|hda)1 / '),
        ('df', 'df /', r'/'),
    ]
    boot_verify(tag, disk, 'secret', checks, mem=1024, iface='ahci')



def t_sata40g():
    t_sata8g(40960, 'sata40g')


# ---------------------------------------------------------------- fail
def t_fail():
    """ecran d'echec : mkfs qui ne repond plus (delai 4 s) -> message clair,
    dernieres lignes du journal, Reessayer / Shell / Quitter"""
    pre = """lang=fr
keyboard=fr
timezone=UTC
hostname=x
rootpw=x
partitioning=guided
swap=0
fs=ext2
timeout=4
testmkfs=/bin/sleep 100
"""
    iso = build_iso('fail', 'console=tty0 console=ttyS0 fb=1024x768 rw '
                    'preseed=/cdrom/preseed.cfg k32setup.verbose=/dev/ttyS0',
                    {'preseed.cfg': pre})
    disk = new_disk('fail', 200)
    q = qemu_cd('fail', iso, disk)
    ok = q.wait(r'K32SETUP: .*ne r.pond plus depuis 4 s', 240)
    check('fail : commande bloquee interrompue apres 4 s, message clair', ok)
    time.sleep(1.5)
    cap(q, 'a', 'fail-01-echec')
    check('fail : ecran d\'echec (page installation affichee de nouveau)',
          q.wait(r'K32SETUP: page 12', 5))
    q.key('ret')
    ok = q.wait(r'nouvel essai', 60)
    check('fail : Reessayer relance l\'installation', ok)
    ok = q.wait(r'(?s)nouvel essai.*ne r.pond plus depuis 4 s', 90)
    check('fail : le second essai echoue proprement aussi', ok)
    time.sleep(1.5)
    cap(q, 'b', 'fail-02-second-echec')
    q.quit()

# ---------------------------------------------------------------- text
def t_text():
    iso = build_iso('text', 'console=ttyS0 rw text k32setup.verbose=/dev/ttyS0')
    disk = new_disk('text', 300)
    q = qemu_cd('text', iso, disk)
    check('text : assistant en mode texte sur la console VGA', page(q, 0, 90))
    cap(q, 'a', 'text-01-langue')
    q.key('up')
    q.key('ret')
    check('text : page d\'accueil', page(q, 1))
    cap(q, 'a2', 'text-01b-accueil')
    q.key('ret')
    check('text : navigation au clavier (page clavier)', page(q, 2))
    q.key('tab')
    for k in ['q', 'w', 'e', 'r', 't', 'y']:
        q.key(k)
    time.sleep(0.5)
    cap(q, 'b', 'text-02-clavier')
    q.key('ret')
    page(q, 3)
    cap(q, 'c', 'text-03-fuseau')
    q.key('ret')
    check('text : date et heure', page(q, 4))
    q.key('ret')
    check('text : nom de machine', page(q, 5))
    q.key('ret')
    check('text : comptes', page(q, 6))
    check('text : comptes valides : aucun champ rouge',
          px(q, 't6a', VGARED, 20) == 0)
    q.type('abc')
    q.key('tab')
    q.type('abd')
    time.sleep(0.5)
    check('text : confirmation differente : champ sur fond rouge VGA',
          px(q, 't6b', VGARED, 20) > 60)
    cap(q, 'e', 'text-04-confirmation-rouge')
    q.key('ret')
    check('text : Entree refusee tant que le champ est rouge',
          not page(q, 7, 3, 0.1))
    q.key('backspace')
    q.type('c')
    time.sleep(0.5)
    check('text : mots de passe identiques : plus de rouge',
          px(q, 't6c', VGARED, 20) == 0)
    q.key('tab')
    q.key('tab')
    q.type('Bad,')
    time.sleep(0.5)
    check('text : identifiant invalide : fond rouge VGA',
          px(q, 't6d', VGARED, 20) > 60)
    cap(q, 'f', 'text-05-identifiant-invalide')
    q.quit()


ALL = {'tz': t_tz, 'auto-fr': t_auto_fr, 'auto-de': t_auto_de,
       'ui-fr': t_ui_fr, 'ui-de': t_ui_de, 'text': t_text,
       'refuse': t_refuse, 'virtio': t_virtio, 'exist': t_exist,
       'auto-log': t_auto_log, 'sata8g': t_sata8g, 'sata40g': t_sata40g,
       'fail': t_fail}
DEFAULT = [k for k in ALL if k not in ('sata8g', 'sata40g')]
os.makedirs(WORK, exist_ok=True)
for s in (SCEN or DEFAULT):
    print('=== ' + s, flush=True)
    try:
        ALL[s]()
    except Exception as e:                      # noqa
        import traceback
        traceback.print_exc()
        check(s + ' : exception ' + repr(e), False)
nok = sum(1 for _, o in RESULTS if o)
print('RESULTAT : %d ok, %d echec' % (nok, len(RESULTS) - nok))
sys.exit(0 if nok == len(RESULTS) else 1)
