#!/usr/bin/env python3
# DEVENVTEST.PY - Teste une image de KERNEL16 dans l'emulateur DOS de DEVENV
# (DEV-COOLS\DEVENV.PAS), sans interface graphique : amorcage reel de l'image
# (/KERNELTEST /KTBOOTIMG), frappes au clavier, capture de l'ecran emule.
#
# Utilisation :
#   DEVENVTEST.PY ../IMAGE/LINUX144A.IMG --b ../IMAGE/LINUX144B.IMG
#   DEVENVTEST.PY ../IMAGE/LINUX.ISO --all        (tous les fichiers sur A:)
#   DEVENVTEST.PY LINUXHD.IMG --all --write
#
# Options :
#   --b image   monte une 2e disquette sur B:
#   --all       toutes les commandes sont accessibles (CD, disque dur, 2,88 Mo)
#   --nowrite   n'essaie pas d'ecrire (image en lecture seule)
#
# Variables d'environnement :
#   DEVENV   executable DEVENV compile pour Linux (obligatoire)
#   LD_LIBRARY_PATH est transmis tel quel (bibliotheques de remplacement des
#   DLL Windows, voir KERNEL16/README.md).
# L'image est copiee : DEVENV ecrit dans l'image montee.
import sys, os, re, shutil, subprocess, tempfile

DEVENV = os.environ.get('DEVENV', 'DEVENV')
BOOT_STEPS = 3000000      # instructions avant la premiere capture
CLEAR_STEPS = 3000000     # attente apres 'clear'
PER_CMD = 20000000        # instructions par commande (df en demande 80 M)

# (commande, expression reguliere attendue, besoin, ecriture, instructions)
# besoin : '' = disquette de demarrage, 'B' = commandes de B: ou --all
TESTS = [
 ('ls /', 'BIN', '', 0, 0),
 ('ls /etc/sysctl.d', 'CUSTOM.CFG', '', 0, 0),
 ('echo $PATH $HOME $USER $HOSTNAME', r'\\BIN;B:\\BIN \\ root linux0', '', 0, 0),
 ('uname -a', 'LINUX-0 KERNEL16', '', 0, 0),
 ('cat /etc/profile', 'export PATH', '', 0, 0),
 ('cat /etc/sysctl.d/custom.cfg', 'fs.files', '', 0, 0),
 ('head -n 2 /etc/profile', 'Les commandes', '', 0, 0),
 ('tail -n 1 /etc/profile', 'export PATH', '', 0, 0),
 ('cd /etc; grep PATH profile', 'export PATH', '', 0, 0),
 ('cd /etc; wc -l profile', '4', '', 0, 0),
 ('false; echo $?', '^1', '', 0, 0),
 ('true && echo ok', '^ok', '', 0, 0),
 ('for i in a b c; do echo $i; done', '^c', '', 0, 0),
 ('if test -d /bin; then echo dir; fi', '^dir', '', 0, 0),
 ('ls /bin/ca*', 'CAL.EXE', '', 0, 0),
 ('cd /bin; pwd', '/bin', '', 0, 0),
 ('factor 12', '2 2 3', '', 0, 0),
 ('date', '20', '', 0, 0),
 ('cal', '2026', '', 0, 0),
 ('banner hi', '#', '', 0, 0),
 ('sleep 1; echo fin', '^fin', '', 0, 0),
 ('cat /nofile', '.', '', 0, 0),
 ('export LANGUAGE=EN; cd /nope', 'No such directory', '', 0, 0),
 ('export LANGUAGE=GR; cd /nope', 'Verzeichnis', '', 0, 0),
 ('export LANGUAGE=SP; cd /nope', 'irectorio', '', 0, 0),
 ('export LANGUAGE=IT; cd /nope', 'Directory non trovata', '', 0, 0),
 ('mkdir /tmp/d1; cd /tmp/d1; pwd', '/tmp/d1', '', 1, 0),
 ('echo salut > /tmp/x.txt; cat /tmp/x.txt', '^salut', '', 1, 0),
 ('cp /tmp/x.txt /tmp/y.txt; cat /tmp/y.txt', '^salut', '', 1, 0),
 ('mkdir /home/u; mv /tmp/y.txt /home/u; ls /home/u', 'Y.TXT', '', 1, 0),
 ('cat /etc/profile | grep export', '^export PATH', '', 1, 0),
 ('seq 3', '^3', 'B', 0, 0),
 ('ls /bin | wc -c', '[0-9]', 'B', 1, 60000000),
 ('echo hi | tee /tmp/t.txt', '^hi', 'B', 1, 0),
 ('df', r'A:|C:', '', 0, 150000000),
 ('free', 'Total', '', 0, 150000000),
]

def run(img, cmds, mounts, steps=2000000000):
    wd = tempfile.mkdtemp(prefix='k16test')
    sc = ['run %d' % BOOT_STEPS, 'screen']
    for m in mounts:
        sc.append('mount ' + m)
    for c, per in cmds:
        sc += ['type clear', 'run %d' % CLEAR_STEPS, 'type ' + c,
               'run %d' % (per or PER_CMD), 'screen']
    open(wd + '/s.txt', 'w').write('\n'.join(sc) + '\n')
    cmd = ['xvfb-run', '-a', DEVENV, '/KERNELTEST,' + wd,
           '/KTBOOTIMG:' + img, '/KTSCRIPT:' + wd + '/s.txt',
           '/KTSTEPS:%d' % steps]
    p = subprocess.run(cmd, capture_output=True, text=True, cwd=wd, timeout=3600)
    scr, cur = [], None
    for l in p.stdout.split('\n'):
        if l.startswith('+---- ECRAN'):
            cur = []
        elif l.startswith('+----') and cur is not None:
            scr.append(cur)
            cur = None
        elif cur is not None:
            cur.append(l[1:] if l.startswith('|') else l)
    shutil.rmtree(wd, ignore_errors=True)
    return p.returncode, scr

def main():
    a = sys.argv[1:]
    if not a:
        print(__doc__)
        return 2
    img = a[0]
    b = a[a.index('--b') + 1] if '--b' in a else None
    everything = '--all' in a
    nowrite = '--nowrite' in a
    tmp = tempfile.mkdtemp(prefix='k16img')
    ci = os.path.join(tmp, os.path.basename(img))
    shutil.copy(img, ci)
    mounts = []
    if b:
        cb = os.path.join(tmp, os.path.basename(b))
        shutil.copy(b, cb)
        mounts.append('B: ' + cb)
    tests = [t for t in TESTS
             if (not t[2] or b or everything) and not (nowrite and t[3])]
    rc, scr = run(ci, [(t[0], t[4]) for t in tests], mounts)
    shutil.rmtree(tmp, ignore_errors=True)
    boot = '\n'.join(l for l in scr[0] if l.strip()) if scr else ''
    good = 0
    print('amorcage :', 'OK' if 'root@linux0' in boot else 'ECHEC')
    for k, t in enumerate(tests):
        if k + 1 >= len(scr):
            print('MANQUE', t[0])
            continue
        body = '\n'.join(l.rstrip() for l in scr[k + 1]
                         if l.strip() and not l.startswith('root@'))
        ok = bool(re.search(t[1], body, re.M | re.S | re.I))
        good += ok
        print('OK   ' if ok else 'ECHEC', t[0], '->',
              ' / '.join(body.split('\n')[:3])[:100])
    print('reussis %d / %d' % (good, len(tests)))
    return 0 if good == len(tests) and 'root@linux0' in boot else 1

if __name__ == '__main__':
    sys.exit(main())
