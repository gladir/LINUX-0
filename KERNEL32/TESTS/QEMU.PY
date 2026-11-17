#!/usr/bin/env python3
# @author: Sylvain Maltais (support@gladir.com)
# @created: 2026
# @website(https://www.gladir.com/linux-0)
# @abstract(Target: Python 3, QEMU i386)
# @description: Banc d'essai QEMU de KERNEL32 (chargeur et noyau).
#   - run_qemu() : lance qemu-system-i386 sur une image de disque (.img) ou un
#     noyau ELF (-kernel), console serie COM1 sur stdio, recueille la sortie,
#     envoie des lignes au clavier serie apres des motifs, s'arrete a la fin
#     de QEMU, a un motif d'arret ou apres un delai.
#   - "QEMU.PY run IMAGE|ELF [options]" : une execution (voir RUNQEMU.SH).
#   - "QEMU.PY boot" : batterie d'essais de l'amorce (MBR + chargeur + ext2) :
#     blocs de 1, 2 et 4 Ko, inodes de 128 et 256 octets, gros noyau a
#     indirections double et triple, zone mise a zero, grand repertoire
#     /boot, lien symbolique, /boot/linux0.cfg, CHS, noyau absent, ext4
#     refuse, memoire de 16 a 256 Mo, e2fsck -fn sur chaque image et
#     comparaison avec "qemu -kernel" direct.
#   Variables : W (travail, defaut /tmp/linux0-k32-qemu), QEMU, LPC (pour
#   compiler les noyaux de KERNEL32/TESTS/C si present).
import os, sys, subprocess, threading, time, re, shutil, argparse

HERE = os.path.dirname(os.path.abspath(__file__))
K32 = os.path.dirname(HERE)
QEMU = os.environ.get('QEMU', 'qemu-system-i386')


def run_qemu(target, mem=64, timeout=20.0, stop_on=None, send=(), append=None,
             extra=(), snapshot=False, quiet=True):
    """Retourne (sortie serie, code de retour, secondes, delai depasse).
    send : liste de (motif, ligne) : la ligne est envoyee au clavier serie
    quand le motif (expression reguliere, vide = invite "# ", "$ ", ":" ou
    "> " en fin de texte) apparait dans la sortie recue depuis l'envoi
    precedent (une seule fois chacun, dans l'ordre)."""
    cmd = [QEMU, '-m', str(mem), '-display', 'none', '-monitor', 'none',
           '-serial', 'stdio', '-no-reboot',
           '-device', 'isa-debug-exit,iobase=0xf4,iosize=0x04']
    kind = open(target, 'rb').read(4)
    if kind == b'\x7fELF':
        cmd += ['-kernel', target]
        if append is not None:
            cmd += ['-append', append]
    else:
        d = 'file=%s,format=raw,if=ide' % target
        if snapshot:
            d += ',snapshot=on'
        cmd += ['-drive', d]
    cmd += list(extra)
    t0 = time.time()
    p = subprocess.Popen(cmd, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                         stderr=subprocess.PIPE)
    buf = bytearray()
    lock = threading.Lock()

    def reader():
        while True:
            b = p.stdout.read(1)
            if not b:
                break
            with lock:
                buf.extend(b)
    th = threading.Thread(target=reader, daemon=True)
    th.start()
    pending = list(send)
    sent = 0
    timed_out = False
    found_at = None
    while True:
        if p.poll() is not None:
            break
        time.sleep(0.05)
        with lock:
            txt = buf.decode('latin-1')
        if pending:
            pat = pending[0][0] or r'[#$>:] \Z'
            if re.search(pat, txt[sent:]):
                try:
                    p.stdin.write((pending[0][1] + '\n').encode())
                    p.stdin.flush()
                except Exception:
                    pass
                pending.pop(0)
                sent = len(txt)
        if stop_on and re.search(stop_on, txt) and found_at is None:
            found_at = time.time()
        if found_at and time.time() - found_at > 0.5:
            break
        if time.time() - t0 > timeout:
            timed_out = True
            break
    if p.poll() is None:
        p.kill()
    p.wait()
    th.join(timeout=2)
    with lock:
        out = buf.decode('latin-1')
    return out, p.returncode, time.time() - t0, timed_out


# ---------------------------------------------------------------- essais

class Suite:
    def __init__(self, w):
        self.w = w
        self.ok = 0
        self.bad = 0
        os.makedirs(w, exist_ok=True)

    def check(self, name, cond, detail=''):
        if cond:
            self.ok += 1
            print('ok    ' + name)
        else:
            self.bad += 1
            print('ECHEC ' + name + (' : ' + detail if detail else ''))

    def sh(self, *a):
        r = subprocess.run(list(a), stdout=subprocess.PIPE,
                           stderr=subprocess.STDOUT)
        return r.returncode, r.stdout.decode('latin-1')

    def mkimage(self, name, *args):
        img = os.path.join(self.w, name + '.img')
        rc, out = self.sh(os.path.join(K32, 'TOOLS', 'MKIMAGE.SH'), '-o', img,
                          *args)
        if rc != 0:
            print('MKIMAGE a echoue pour %s : %s' % (name, out))
        return img, rc

    def fsck(self, name, img, start=2048):
        rc, out = self.sh('e2fsck', '-fn', '%s?offset=%d' % (img, start * 512))
        self.check('e2fsck ' + name, rc == 0, out[-300:])

    def boot(self, name, img, expect=(), mem=64, timeout=30, stop_on=None,
             snapshot=True, forbid=()):
        out, rc, dt, to = run_qemu(img, mem=mem, timeout=timeout,
                                   stop_on=stop_on, snapshot=snapshot)
        miss = [e for e in expect if e not in out]
        bad = [e for e in forbid if e in out]
        self.check('%s (%.1f s)' % (name, dt), not miss and not bad,
                   'manque %r interdit %r ; sortie : %r' %
                   (miss, bad, out[-600:]))
        return out


def boot_tests(w):
    s = Suite(w)
    tk = os.path.join(w, 'tk')
    rc, out = s.sh(os.path.join(HERE, 'B', 'MKTESTK.SH'), tk)
    if rc != 0:
        print(out)
        sys.exit(2)
    small = os.path.join(tk, 'TESTK.ELF')
    hi = os.path.join(tk, 'TESTKHI.ELF')
    big = os.path.join(tk, 'TESTKBIG.ELF')
    base = ['BOOT OK eax=2BADB002', 'MAGIC OK', 'cmdline=root=/dev/hda1 ro',
            'TESTK END']
    bigx = base + ['CHK pad hash=', 'CHK zero  OK', 'CHK far  OK']

    # qemu -kernel direct (reference)
    # (qemu ne met pas a zero un segment sans donnees : "CHK zero" attendu
    # BAD en direct, et la ligne de commande est precedee du nom du fichier)
    out, rc, dt, to = run_qemu(small, append='root=/dev/hda1 ro', timeout=15)
    s.check('qemu -kernel direct (reference)',
            all(e in out for e in ['BOOT OK eax=2BADB002', 'MAGIC OK',
                                   'root=/dev/hda1 ro', 'TESTK END']),
            out[-300:])
    out, rc, dt, to = run_qemu(big, append='root=/dev/hda1 ro', timeout=30)
    s.check('qemu -kernel direct, gros noyau',
            all(e in out for e in ['CHK pad hash=', 'CHK far  OK']) and
            'hash=' in out and re.search(r'hash=\w+ OK', out), out[-400:])

    # blocs et inodes
    for bs in (1024, 2048, 4096):
        for ino in (128, 256):
            n = 'petit-%d-%d' % (bs, ino)
            img, rc = s.mkimage(n, '-k', small, '-b', str(bs), '-i', str(ino),
                                '-s', '32')
            s.fsck(n, img)
            s.boot(n, img, base + ['blocs de %d octets, inodes de %d' %
                                   (bs, ino)], timeout=20)
    for bs in (1024, 2048, 4096):
        n = 'gros-%d' % bs
        img, rc = s.mkimage(n, '-k', big, '-b', str(bs), '-s', '96')
        s.fsck(n, img)
        s.boot(n, img, bigx + ['hash='], timeout=60, forbid=[' BAD'])
    n = 'gros-1024-i256'
    img, rc = s.mkimage(n, '-k', big, '-b', '1024', '-i', '256', '-s', '96')
    s.boot(n, img, bigx, timeout=60, forbid=[' BAD'])

    # noyau a p_vaddr haut (comme le vrai noyau)
    img, rc = s.mkimage('haut', '-k', hi, '-s', '32')
    s.boot('noyau lie en C0000000h+ (entree physique deduite)', img, base,
           timeout=20)

    # ext2 revision 0 (inodes de 128 octets, sans champs dynamiques)
    for bs in (1024, 4096):
        n = 'rev0-%d' % bs
        img, rc = s.mkimage(n, '-k', small, '-b', str(bs), '-R', '0',
                            '-s', '32')
        s.fsck(n, img)
        s.boot('ext2 revision 0, blocs de %d' % bs, img, base, timeout=20)

    # partition active en 3e entree de la table : hda3, boot_device 02h
    img, rc = s.mkimage('slot3', '-k', small, '-s', '32')
    with open(img, 'r+b') as f:
        f.seek(446)
        ent = f.read(16)
        f.seek(446)
        f.write(bytes(16))
        f.seek(446 + 32)
        f.write(ent)
    s.boot('partition active en 3e entree (hda3)', img,
           ['cmdline=root=/dev/hda3 ro', 'boot_device=8002FFFF', 'MAGIC OK'],
           timeout=20)

    # grand repertoire /boot
    img, rc = s.mkimage('repert', '-k', small, '-s', '64', '-N', '3000')
    s.fsck('repert', img)
    s.boot('/boot avec 3000 entrees', img, base, timeout=30)
    img, rc = s.mkimage('repert4k', '-k', small, '-s', '64', '-N', '3000',
                        '-b', '4096', '-i', '256')
    s.boot('/boot avec 3000 entrees (4 Ko, inodes 256)', img, base,
           timeout=30)

    # configuration et lien symbolique
    rootd = os.path.join(w, 'root-cfg')
    shutil.rmtree(rootd, ignore_errors=True)
    os.makedirs(os.path.join(rootd, 'boot'))
    shutil.copy(small, os.path.join(rootd, 'boot', 'noyau-1.0'))
    os.symlink('noyau-1.0', os.path.join(rootd, 'boot', 'linux0'))
    img, rc = s.mkimage('lien', '-r', rootd, '-s', '32')
    s.boot('/boot/linux0 lien symbolique relatif', img, base, timeout=20)
    img, rc = s.mkimage('cfg', '-r', rootd, '-s', '32', '-c',
                        'root=/dev/hda1 rw init=/sbin/init quiet')
    s.boot('/boot/linux0.cfg : ligne de commande', img,
           ['cmdline=root=/dev/hda1 rw init=/sbin/init quiet', 'MAGIC OK'],
           timeout=20)
    rootc = os.path.join(w, 'root-chs')
    shutil.rmtree(rootc, ignore_errors=True)
    os.makedirs(os.path.join(rootc, 'boot'))
    shutil.copy(big, os.path.join(rootc, 'boot', 'linux0'))
    with open(os.path.join(rootc, 'boot', 'linux0.cfg'), 'w') as f:
        f.write('# essai CHS\ncmdline=root=/dev/hda1 ro chs\nchs=1\n')
    img, rc = s.mkimage('chs', '-r', rootc, '-s', '96')
    s.boot('chargeur : lecture du gros noyau en CHS (chs=1)', img,
           ['cmdline=root=/dev/hda1 ro chs', 'TESTK END', 'CHK far  OK',
            'Lecture en CHS imposee'],
           timeout=120, forbid=[' BAD'])
    img, rc = s.mkimage('chsmbr', '-k', small, '-s', '32', '-C')
    s.boot('MBR : chargement du chargeur en CHS (-C)', img, base, timeout=20)
    cfg2 = os.path.join(w, 'root-cfg2')
    shutil.rmtree(cfg2, ignore_errors=True)
    os.makedirs(os.path.join(cfg2, 'boot'))
    shutil.copy(small, os.path.join(cfg2, 'boot', 'autre'))
    with open(os.path.join(cfg2, 'boot', 'linux0.cfg'), 'w') as f:
        f.write('kernel=/boot/autre\ncmdline=root=/dev/hda1 ro single\n')
    img, rc = s.mkimage('cfg2', '-r', cfg2, '-s', '32')
    s.boot('kernel= dans linux0.cfg', img,
           ['cmdline=root=/dev/hda1 ro single', 'Noyau : /boot/autre'],
           timeout=20)

    # noyau absent
    img, rc = s.mkimage('absent', '-s', '32')
    s.boot('noyau absent : message clair', img,
           ['ERREUR : noyau /boot/linux0 introuvable', 'Systeme arrete'],
           stop_on='Systeme arrete', timeout=20)

    # fichier qui n'est pas un ELF
    rootn = os.path.join(w, 'root-noelf')
    shutil.rmtree(rootn, ignore_errors=True)
    os.makedirs(os.path.join(rootn, 'boot'))
    with open(os.path.join(rootn, 'boot', 'linux0'), 'wb') as f:
        f.write(b'pas un ELF' * 100)
    img, rc = s.mkimage('noelf', '-r', rootn, '-s', '32')
    s.boot('fichier noyau non ELF', img, ['pas un ELF32', 'Systeme arrete'],
           stop_on='Systeme arrete', timeout=20)

    # ext4 (extents) refuse : le chargeur doit le dire
    img4 = os.path.join(w, 'ext4.img')
    with open(img4, 'wb') as f:
        f.truncate(32 << 20)
    d4 = os.path.join(w, 'root-ext4')
    shutil.rmtree(d4, ignore_errors=True)
    os.makedirs(os.path.join(d4, 'boot'))
    shutil.copy(small, os.path.join(d4, 'boot', 'linux0'))
    s.sh('mke2fs', '-q', '-F', '-t', 'ext4', '-I', '256', '-E',
         'offset=%d' % (2048 * 512), '-d', d4, img4,
         str((32 << 20) // 1024 - 2048 // 2))
    # on reutilise le MBR/chargeur d'une image saine
    good = os.path.join(w, 'petit-1024-128.img')
    with open(good, 'rb') as f:
        head = f.read(2048 * 512)
    with open(img4, 'r+b') as f:
        f.write(head)
    s.boot('ext4 (extents) refuse avec un message', img4,
           ['ERREUR', 'non support', 'Systeme arrete'],
           stop_on='Systeme arrete', timeout=20)

    # memoire
    img, rc = s.mkimage('mem', '-k', small, '-s', '32')
    for m in (16, 32, 128, 256, 2048, 3072):
        out = s.boot('memoire %d Mo' % m, img, base + ['mmap base='], mem=m,
                     timeout=20)
        mu = re.search(r'mem_upper=(\d+)', out)
        s.check('  mem_upper coherent pour %d Mo' % m,
                bool(mu) and abs(int(mu.group(1)) -
                                 min(m * 1024 - 1024, 2093056)) < 1100,
                out[-200:])
    # noyau trop gros pour la memoire
    img, rc = s.mkimage('trop', '-k', big, '-s', '96')
    s.boot('gros noyau + 4 Mo : refus memoire', img,
           ['hors memoire', 'Systeme arrete'], mem=4, stop_on='Systeme arrete',
           timeout=20)

    # noyaux compiles par LPC (agent A), si disponibles
    lpc = os.environ.get('LPC', '/tmp/claude-0/work/k32/bin/lpc')
    tkdir = os.path.join(HERE, 'C')
    if os.path.isfile(lpc) and os.path.isdir(tkdir):
        for src in sorted(os.listdir(tkdir)):
            if not (src.startswith('TK') and src.endswith('.PAS')):
                continue
            n = src[:-4]
            outf = os.path.join(tkdir, n + '.OUT')
            if not os.path.isfile(outf):
                continue
            wd = os.path.join(w, 'lpc-' + n)
            os.makedirs(wd, exist_ok=True)
            shutil.copy(os.path.join(tkdir, src), wd)
            r = subprocess.run([lpc, '-3K', '-q', src], cwd=wd,
                               stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
            elf = os.path.join(wd, n)
            if r.returncode != 0 or not os.path.isfile(elf):
                s.check('LPC %s compile' % n, False, r.stdout.decode()[:200])
                continue
            exp = open(outf, 'rb').read().decode('latin-1')
            img, rc = s.mkimage('lpc-' + n, '-k', elf, '-s', '32')
            s.fsck('lpc-' + n, img)
            out, rc, dt, to = run_qemu(img, timeout=20, snapshot=True)
            s.check('LPC %s depuis le disque dur ext2' % n,
                    exp.strip() in out, 'sortie : %r' % out[-300:])
    print('%d reussi(s), %d echec(s)' % (s.ok, s.bad))
    return s.bad == 0


def main():
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest='cmd')
    r = sub.add_parser('run')
    r.add_argument('target')
    r.add_argument('-m', '--mem', type=int, default=64)
    r.add_argument('-t', '--timeout', type=float, default=20)
    r.add_argument('-s', '--stop-on', default=None)
    r.add_argument('-a', '--append', default=None)
    r.add_argument('-e', '--expect', action='append', default=[])
    r.add_argument('-c', '--send', action='append', default=[],
                   help='MOTIF=LIGNE : envoie LIGNE quand MOTIF apparait')
    r.add_argument('-S', '--snapshot', action='store_true')
    r.add_argument('-x', '--extra', action='append', default=[])
    b = sub.add_parser('boot')
    b.add_argument('-w', default=os.environ.get('W', '/tmp/linux0-k32-qemu'))
    a = ap.parse_args()
    if a.cmd == 'run':
        send = [tuple(x.split('=', 1)) for x in a.send]
        out, rc, dt, to = run_qemu(a.target, a.mem, a.timeout, a.stop_on, send,
                                   a.append, a.extra, a.snapshot)
        sys.stdout.write(out)
        if not out.endswith('\n'):
            sys.stdout.write('\n')
        miss = [e for e in a.expect if e not in out]
        if miss:
            print('MANQUE : %r' % miss)
            sys.exit(1)
        if to and not a.expect and not a.stop_on:
            print('(delai de %.0f s depasse)' % a.timeout)
    elif a.cmd == 'boot':
        sys.exit(0 if boot_tests(a.w) else 1)
    else:
        ap.print_help()


if __name__ == '__main__':
    main()
