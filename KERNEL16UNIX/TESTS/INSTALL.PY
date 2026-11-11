#!/usr/bin/env python3
# @author: Sylvain Maltais (support@gladir.com)
# @created: 2026
# @website(https://www.gladir.com/linux-0)
# @description: Essai de l'installation de LINUX-0 sous QEMU, de bout en bout.
#   Il n'y a qu'un type d'installation (UFS seul) et pas de FAT :
#   1. depuis les disquettes (LINUX0-INST1.IMG, puis 2, 3, ... inserees par le
#      moniteur de QEMU a la demande de l'installateur) sur un disque vierge,
#      langue du systeme installe par defaut (francais);
#   2. depuis le CD-ROM (LINUX0-CD.ISO, El Torito) sur un autre disque
#      vierge, avec la langue anglaise pour le systeme installe
#      (/etc/profile recoit LANGUAGE=EN);
#   3. l'installateur dans les cinq langues (variable LANGUAGE de l'environnement
#      de root : FR, EN, GR, SP, IT) : titre et abandon a la confirmation.
#   Chaque disque installe est verifie : UFS1, MBR et amorce par TOOLS/UFSCHK.PAS,
#   puis contenu, modes et proprietaires par TESTS/UFSCMP.PY (lecteur UFS1
#   independant) contre la racine de BUILD.SH; enfin le disque demarre seul :
#   connexion de root et quelques commandes.
#   Usage : python3 INSTALL.PY [dossier_IMAGE]   (code de sortie 0 si OK)
#   Variables : W (repertoire de BUILD.SH), INSTALL_MODE (defaut
#   "disquettes cd langues")
import os, re, shutil, socket, struct, subprocess, sys, tempfile, time

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, '..'))
W = os.environ.get('W', '/tmp/linux0-build')
# verificateurs UFS1 : TOOLS/UFSCHK.PAS (compile par BUILD.SH) et UFSCMP.PY
UFSCHK = os.path.join(W, 'bin', 'ufschk')
UFSCMP = os.path.join(HERE, 'UFSCMP.PY')
IMG = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, 'IMAGE')
TMP = tempfile.mkdtemp()
DEBUG = bool(os.environ.get('INSTALL_DEBUG'))
fails = 0


def ok(cond, what):
    global fails
    print(('ok    ' if cond else 'ECHEC ') + what, flush=True)
    if not cond:
        fails += 1


class Vm:
    def __init__(self, args):
        self.port = 4700 + os.getpid() % 200 + int(time.time()) % 50
        cmd = ['qemu-system-i386', '-m', '1', '-display', 'none', '-no-reboot',
               '-serial', 'tcp:127.0.0.1:%d,server,nowait' % self.port,
               '-monitor', 'tcp:127.0.0.1:%d,server,nowait' % (self.port + 1)] + args
        self.q = subprocess.Popen(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        self.s = self.m = None
        for i in range(50):
            try:
                self.s = socket.create_connection(('127.0.0.1', self.port))
                self.m = socket.create_connection(('127.0.0.1', self.port + 1))
                break
            except OSError:
                time.sleep(0.2)
        self.s.settimeout(0.2)
        self.out = ''
        self.log = ''

    def pump(self, t):
        end = time.time() + t
        while time.time() < end:
            try:
                d = self.s.recv(4096)
                if d:
                    t2 = d.decode('latin-1')
                    self.out += t2
                    self.log += t2
            except socket.timeout:
                pass

    def expect(self, pat, t=60):
        end = time.time() + t
        while time.time() < end:
            m = re.search(pat, self.out)
            if m:
                seen = self.out[:m.end()]
                self.out = self.out[m.end():]
                if DEBUG:
                    print('      . vu : ' + seen.strip().splitlines()[-1][:100] if seen.strip() else '      . vu : (vide)', flush=True)
                return seen
            self.pump(0.3)
        raise TimeoutError('attendu %r, recu %r' % (pat, self.out[-400:]))

    def send(self, line):
        for c in line + '\r':
            self.s.send(c.encode('latin-1'))
            time.sleep(0.02)

    def monitor(self, cmd):
        self.m.send((cmd + '\n').encode())
        time.sleep(1)

    def close(self):
        self.q.kill()
        self.q.wait()


def check_disk(path, what, lang_extra):
    """UFSCHK (UFS1, MBR, amorce) puis UFSCMP (contenu) du disque installe"""
    r = subprocess.run([UFSCHK, '--hd', path], capture_output=True, text=True)
    ok(r.returncode == 0, '%s : UFS1, MBR et amorce coherents (%s)'
       % (what, r.stdout.strip().splitlines()[-1]))
    if r.returncode:
        print('      | ' + r.stdout.strip().replace('\n', '\n      | '))
    d = open(path, 'rb').read(512)
    types = [d[446 + 16 * i + 4] for i in range(4)]
    ok(types[:2] == [0xA5, 0x82], '%s : partition 1 UFS (A5h), partition 2 va-et-vient (82h)'
       % what)
    extra = ['etc/profile'] if lang_extra else []
    r = subprocess.run([sys.executable, UFSCMP, path, os.path.join(W, 'ufsroot'), '--hd']
                       + (['--extra'] + extra if extra else []),
                       capture_output=True, text=True)
    ok(r.returncode == 0, '%s : contenu identique a la racine de BUILD.SH (lecteur UFS1 '
       'independant : %s)' % (what, r.stdout.strip().splitlines()[-1]))
    if r.returncode:
        print('      | ' + r.stdout.strip().replace('\n', '\n      | '))


def boot_installed(path, what, expect, profile):
    vm = Vm(['-drive', 'file=%s,format=raw,if=ide' % path, '-boot', 'c'])
    try:
        boot = vm.expect(r'login: ', 120)
        ok(all(e in boot for e in expect),
           '%s : demarrage du disque dur (%s)' % (what, ', '.join(expect)))
        vm.send('root')
        vm.expect(r'# $', 30)
        # le marqueur FIN''TEST s'affiche FINTEST : il ne se confond pas avec
        # l'echo de la commande tapee
        vm.send('echo /bin/[a-c]*; echo /bin/[d-l]*; echo /bin/[m-r]*; echo /bin/[s-z]*; '
                'cat /etc/passwd | grep invite; ls -l /bin/passwd; '
                'ls /; id; cat /etc/profile; echo FIN\'\'TEST')
        r = vm.expect(r'(?m)^FINTEST', 90).replace('\r', '')
        n = r.count('/bin/')
        ok(n >= 50 and 'invite:' in r and 'unix' in r and 'uid=0(root)' in r,
           '%s : commandes et fichiers installes (%d noms dans /bin)' % (what, n))
        ok(('LANGUAGE=%s; export LANGUAGE' % profile in r) if profile
           else ('LANGUAGE=' not in r), '%s : /etc/profile %s' % (
               what, 'contient LANGUAGE=' + profile if profile else 'sans LANGUAGE (francais)'))
    except TimeoutError as e:
        ok(False, '%s : %s' % (what, e))
    finally:
        vm.close()


def install_floppy():
    target = os.path.join(TMP, 'disque1.img')
    with open(target, 'wb') as f:
        f.truncate(64 * 1024 * 1024)
    disks = sorted(f for f in os.listdir(IMG) if re.match(r'LINUX0-INST\d+\.IMG$', f))
    disks.sort(key=lambda f: int(re.search(r'INST(\d+)', f).group(1)))
    ok(len(disks) >= 2, 'jeu de %d disquettes d\'installation UFS1' % len(disks))
    copies = []
    for d in disks:
        c = os.path.join(TMP, d)
        shutil.copy(os.path.join(IMG, d), c)
        copies.append(c)
    vm = Vm(['-drive', 'file=%s,format=raw,if=floppy' % copies[0],
             '-drive', 'file=%s,format=raw,if=ide' % target, '-boot', 'a'])
    try:
        boot = vm.expect(r'"install"', 120)
        ok('racine : /dev/fd0 (UFS1)' in vm.log, 'disquette 1 : racine /dev/fd0 (UFS1)')
        vm.expect(r'login: ', 30)
        vm.send('install')
        vm.expect(r'Langue du systeme installe \(FR, EN, GR, SP, IT\) \[FR\] : ', 60)
        vm.send('')                       # francais par defaut
        vm.expect(r'Continuer \? \(oui/non\) ', 60)
        vm.send('oui')
        changes = 0
        while True:
            t = vm.expect(r'Inserez la disquette (\d+)|Redemarrer maintenant \? \(oui/non\) ', 900)
            m = re.search(r'Inserez la disquette (\d+)', t)
            if DEBUG:
                print(repr(t[-300:]), flush=True)
            if m:
                vm.monitor('change floppy0 %s raw' % copies[int(m.group(1)) - 1])
                changes += 1
                vm.send('')
            else:
                break
        ok(changes == len(disks) - 1, 'disquettes 2 a %d demandees et lues' % len(disks))
        ok('Installation terminee' in vm.log, 'installation terminee depuis les disquettes')
        print('      | ' + re.search(r'Installation terminee[^\r\n]*', vm.log).group(0))
        vm.send('non')
        vm.expect(r'Remettez la disquette 1', 30)
        vm.monitor('change floppy0 %s raw' % copies[0])
        vm.send('')
        vm.expect(r'login: ', 60)
        ok(True, 'retour a l\'invite de connexion de la disquette 1')
    except TimeoutError as e:
        ok(False, 'installation depuis les disquettes : %s' % e)
        print(vm.log[-1500:])
    finally:
        vm.close()
    # la disquette 1 n'a pas ete modifiee par l'installation (UFS1 intact)
    r = subprocess.run([UFSCHK, '--floppy', copies[0]], capture_output=True, text=True)
    ok(r.returncode == 0, 'disquette 1 apres installation : UFS1 coherent (%s)'
       % r.stdout.strip().splitlines()[-1])
    check_disk(target, 'disquettes', False)
    boot_installed(target, 'disquettes', ['racine : /dev/hda1 (UFS1)',
                                          'va-et-vient : /dev/hda2'], None)


def install_cd(lang, answer, what):
    target = os.path.join(TMP, 'disque2.img')
    with open(target, 'wb') as f:
        f.truncate(48 * 1024 * 1024)
    vm = Vm(['-cdrom', os.path.join(IMG, 'LINUX0-CD.ISO'),
             '-drive', 'file=%s,format=raw,if=ide,index=0' % target, '-boot', 'd'])
    try:
        vm.expect(r'"install"', 120)
        ok('racine : /dev/hda1 (UFS1)' in vm.log, '%s : racine du CD (disque emule) /dev/hda1 (UFS1)' % what)
        vm.expect(r'login: ', 30)
        vm.send('install')
        t = vm.expect(r'Langue du systeme installe \(FR, EN, GR, SP, IT\) \[FR\] : ', 60)
        ok('/dev/hdb' in t and 'CD-ROM' in t, '%s : disque cible /dev/hdb (le CD est hda)' % what)
        ok('/dev/hdb' in t and 'UFS seul' in t, '%s : un seul type d\'installation, UFS seul' % what)
        vm.send(answer)
        vm.expect(r'Continuer \? \(oui/non\) ', 60)
        vm.send('oui')
        vm.expect(r'Redemarrer maintenant \? \(oui/non\) ', 1200)
        ok('Installation terminee' in vm.log, '%s : installation terminee' % what)
        vm.send('non')
        vm.expect(r'login: ', 60)
    except TimeoutError as e:
        ok(False, '%s : %s' % (what, e))
        print(vm.log[-1500:])
    finally:
        vm.close()
    check_disk(target, what, lang != 'FR')
    boot_installed(target, what, ['racine : /dev/hda1 (UFS1)', 'va-et-vient : /dev/hda2'],
                   lang if lang != 'FR' else None)


# titre et ligne de langue de l'installateur dans chaque langue
TITLES = {
    'FR': ('Installation de LINUX-0 sur un disque dur', 'oui', 'annulee par l\'utilisateur'),
    'EN': ('LINUX-0 installation on a hard disk', 'no', 'cancelled by the user'),
    'GR': ('Installation von LINUX-0 auf einer Festplatte', 'nein', 'vom Benutzer abgebrochen'),
    'SP': ('Instalacion de LINUX-0 en un disco duro', 'no', 'cancelada por el usuario'),
    'IT': ('Installazione di LINUX-0 su un disco fisso', 'no', 'annullata dall\'utente'),
}


def install_languages():
    target = os.path.join(TMP, 'disque3.img')
    with open(target, 'wb') as f:
        f.truncate(48 * 1024 * 1024)
    vm = Vm(['-cdrom', os.path.join(IMG, 'LINUX0-CD.ISO'),
             '-drive', 'file=%s,format=raw,if=ide,index=0' % target, '-boot', 'd'])
    try:
        vm.expect(r'login: ', 120)
        vm.send('root')
        vm.expect(r'# $', 30)
        for lang in ('FR', 'EN', 'GR', 'SP', 'IT'):
            vm.send('LANGUAGE=%s /bin/install' % lang if lang != 'FR' else '/bin/install')
            title = TITLES[lang][0]
            t = vm.expect(r'\[[A-Z][A-Z]\] ?: ', 60)
            vm.send('')                  # langue du systeme : celle de l'installateur
            t2 = vm.expect(r'\(\w+/\w+\) ', 60)
            ok(title in t, 'langue %s : titre "%s"' % (lang, title))
            ok(('[%s]' % lang) in t, 'langue %s : langue du systeme installe proposee par defaut' % lang)
            vm.send('non' if lang in ('FR',) else TITLES[lang][1])
            u = vm.expect(r'(?m)^# $', 30)
            ok(TITLES[lang][2] in u, 'langue %s : abandon a la confirmation (%s)' % (lang, TITLES[lang][2]))
    except TimeoutError as e:
        ok(False, 'langues : %s' % e)
        print(vm.log[-1500:])
    finally:
        vm.close()


MODE = os.environ.get('INSTALL_MODE', 'disquettes cd langues')
try:
    if 'disquettes' in MODE:
        print('== Installation depuis les disquettes (UFS1 seul, systeme en francais)')
        install_floppy()
    if 'cd' in MODE:
        print('== Installation depuis le CD-ROM (UFS1 seul, systeme en anglais)')
        install_cd('EN', 'EN', 'CD-ROM, langue EN')
    if 'langues' in MODE:
        print('== L\'installateur dans les cinq langues (LANGUAGE)')
        install_languages()
finally:
    if os.environ.get('INSTALL_KEEP'):
        print('disques gardes dans ' + TMP)
    else:
        shutil.rmtree(TMP)
print('Installation : %d echec(s)' % fails)
sys.exit(1 if fails else 0)
