#!/usr/bin/env python3
# @author: Sylvain Maltais (support@gladir.com)
# @created: 2026
# @website(https://www.gladir.com/linux-0)
# @description: Essai de l'installation de LINUX-0 sous QEMU, de bout en bout :
#   1. depuis les disquettes (LINUX0-INST1.IMG, puis 2, 3, ... inserees par le
#      moniteur de QEMU a la demande de l'installateur) sur un disque vierge,
#      installation par defaut (UFS seul, amorce UFS);
#   2. depuis le CD-ROM (LINUX0-CD.ISO, El Torito) : FAT16 d'amorce + UFS,
#      puis FAT16 seul, sur d'autres disques vierges.
#   Chaque disque installe est verifie (UFS1 par TOOLS/UFSCHK.PAS, FAT16 par
#   fsck.vfat s'il est present), puis demarre seul : connexion de root et
#   quelques commandes.
#   Usage : python3 INSTALL.PY [dossier_IMAGES]   (code de sortie 0 si OK)
import os, re, shutil, socket, struct, subprocess, sys, tempfile, time

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, '..'))
# verificateur UFS1 (TOOLS/UFSCHK.PAS, compile par BUILD.SH)
UFSCHK = os.path.join(os.environ.get('W', '/tmp/unix0-build'), 'bin', 'ufschk')
IMG = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, 'IMAGE')
TMP = tempfile.mkdtemp()
fails = 0


def ok(cond, what):
    global fails
    print(('ok    ' if cond else 'ECHEC ') + what)
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


def check_disk(path, what):
    d = open(path, 'rb').read(512)
    for i in range(4):
        typ = d[446 + 16 * i + 4]
        start, size = struct.unpack_from('<II', d, 446 + 16 * i + 8)
        if typ == 0xA5:
            r = subprocess.run([UFSCHK,
                                path, str(start)], capture_output=True, text=True)
            ok(r.returncode == 0, '%s : UFS1 coherent (%s)' % (what, r.stdout.strip().splitlines()[-1]))
        elif typ in (4, 6) and shutil.which('fsck.vfat'):
            fat = os.path.join(TMP, 'fat.img')
            with open(path, 'rb') as f, open(fat, 'wb') as g:
                f.seek(start * 512)
                g.write(f.read(size * 512))
            r = subprocess.run(['fsck.vfat', '-n', fat], capture_output=True, text=True)
            ok(r.returncode == 0, '%s : FAT16 sans erreur (fsck.vfat)' % what)
            if r.returncode:
                print('      | ' + (r.stdout + r.stderr).strip().replace('\n', '\n      | '))


def boot_installed(path, what, expect):
    vm = Vm(['-drive', 'file=%s,format=raw,if=ide' % path, '-boot', 'c'])
    try:
        boot = vm.expect(r'login: ', 120)
        ok(all(e in boot for e in expect),
           '%s : demarrage du disque dur (%s)' % (what, ', '.join(expect)))
        vm.send('root')
        vm.expect(r'# $', 30)
        vm.send('ls /bin | wc -l; cat /etc/passwd | grep invite; ls -l /bin/passwd; ls /; id')
        r = vm.expect(r'(?m)^# $', 60).replace('\r', '')
        n = re.search(r'^(\d+)$', r, re.M)
        ok(n is not None and int(n.group(1)) >= 50 and 'invite:' in r and 'unix' in r
           and 'uid=0(root)' in r, '%s : commandes et fichiers installes (%s commandes)'
           % (what, n.group(1) if n else '?'))
    except TimeoutError as e:
        ok(False, '%s : %s' % (what, e))
    finally:
        vm.close()


def install_floppy():
    target = os.path.join(TMP, 'disque1.img')
    with open(target, 'wb') as f:
        f.truncate(64 * 1024 * 1024)
    disks = sorted(f for f in os.listdir(IMG) if re.match(r'LINUX0-INST\d+\.IMG$', f))
    disks.sort(key=lambda f: int(re.search(r'\d+', f[5:]).group()))
    ok(len(disks) >= 2, 'jeu de %d disquettes d\'installation' % len(disks))
    copies = []
    for d in disks:
        c = os.path.join(TMP, d)
        shutil.copy(os.path.join(IMG, d), c)
        copies.append(c)
    vm = Vm(['-drive', 'file=%s,format=raw,if=floppy' % copies[0],
             '-drive', 'file=%s,format=raw,if=ide' % target, '-boot', 'a'])
    try:
        vm.expect(r'"install"', 120)
        vm.expect(r'login: ', 30)
        vm.send('install')
        vm.expect(r'Choix \[1\] : ', 60)
        vm.send('')                       # installation par defaut : UFS seul
        vm.expect(r'Continuer \? \(oui/non\) ', 60)
        vm.send('oui')
        changes = 0
        while True:
            t = vm.expect(r'Inserez la disquette (\d+)|Redemarrer maintenant \? \(oui/non\) ', 600)
            m = re.search(r'Inserez la disquette (\d+)', t)
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
    check_disk(target, 'disquettes')
    boot_installed(target, 'disquettes', ['racine : /dev/hda1 (UFS',
                                          'va-et-vient : /dev/hda2'])


def install_cd(layout, size, expect, what):
    target = os.path.join(TMP, 'disque%d.img' % (layout + 1))
    with open(target, 'wb') as f:
        f.truncate(size * 1024 * 1024)
    vm = Vm(['-cdrom', os.path.join(IMG, 'LINUX0-CD.ISO'),
             '-drive', 'file=%s,format=raw,if=ide,index=0' % target, '-boot', 'd'])
    try:
        vm.expect(r'"install"', 120)
        vm.expect(r'login: ', 30)
        vm.send('install')
        t = vm.expect(r'Choix \[1\] : ', 60)
        ok('/dev/hdb' in t and 'CD-ROM' in t, '%s : disque cible /dev/hdb (le CD est hda)' % what)
        vm.send(str(layout))
        vm.expect(r'Continuer \? \(oui/non\) ', 60)
        vm.send('oui')
        vm.expect(r'Redemarrer maintenant \? \(oui/non\) ', 900)
        ok('Installation terminee' in vm.log, '%s : installation terminee' % what)
        vm.send('non')
        vm.expect(r'login: ', 60)
    except TimeoutError as e:
        ok(False, '%s : %s' % (what, e))
        print(vm.log[-1500:])
    finally:
        vm.close()
    check_disk(target, what)
    boot_installed(target, what, expect)


MODE = os.environ.get('INSTALL_MODE', 'disquettes cd')
if 'disquettes' in MODE:
    print('== Installation depuis les disquettes')
    install_floppy()
if 'cd' in MODE:
    print('== Installation depuis le CD-ROM : FAT16 d\'amorce + UFS')
    install_cd(2, 48, ['racine : /dev/hda2 (UFS', '/boot : /dev/hda1', 'va-et-vient : /dev/hda3'],
               'CD-ROM, FAT16 + UFS')
    print('== Installation depuis le CD-ROM : FAT16 seul')
    install_cd(3, 48, ['racine : /dev/hda1 (FAT16', 'va-et-vient : /dev/hda2'],
               'CD-ROM, FAT16 seul')
shutil.rmtree(TMP)
print('Installation : %d echec(s)' % fails)
sys.exit(1 if fails else 0)
