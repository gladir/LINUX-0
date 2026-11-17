#!/usr/bin/env python3
# @author: Sylvain Maltais (support@gladir.com)
# @created: 2026
# @website(https://www.gladir.com/linux-0)
# @description: essais de USR/PATCH.PAS : fichiers aleatoires, diff -u -c -U0
#   -U1 -C1 et normal de l'hote, application puis inversion (-R).
#   Usage : patchtest.py chemin/du/patch
import subprocess, random, os, shutil, sys, tempfile
PATCH = os.path.abspath(sys.argv[1])
d = tempfile.mkdtemp(prefix='patchtest'); os.chdir(d)
random.seed(11)
fails = 0; tot = 0
for it in range(120):
    n = random.randint(5, 60)
    a = ['line %d' % i for i in range(n)]
    b = list(a)
    for _ in range(random.randint(1, 6)):
        r = random.random()
        if r < 0.35 and b:
            b[random.randrange(len(b))] = 'changed %d' % random.randint(0, 999)
        elif r < 0.65 and len(b) > 2: del b[random.randrange(len(b))]
        else:
            b.insert(random.randrange(len(b) + 1),
                     'new %d' % random.randint(0, 999))
    open('a.txt', 'w').write('\n'.join(a) + '\n')
    open('b.txt', 'w').write('\n'.join(b) + '\n')
    for fmt in ['-u', '-c', '', '-U0', '-U1', '-C1']:
        cmd = ['diff'] + ([fmt] if fmt else []) + ['a.txt', 'b.txt']
        dd = subprocess.run(cmd, capture_output=True).stdout
        if not dd: continue
        tot += 1
        open('d.diff', 'wb').write(dd); shutil.copy('a.txt', 't.txt')
        subprocess.run([PATCH, 't.txt', '-i', 'd.diff'], capture_output=True)
        ok = open('t.txt').read() == open('b.txt').read()
        shutil.copy('b.txt', 't.txt')
        subprocess.run([PATCH, '-R', 't.txt', '-i', 'd.diff'],
                       capture_output=True)
        ok2 = open('t.txt').read() == open('a.txt').read()
        if not (ok and ok2):
            fails += 1
            if fails < 4: print('ECHEC', it, fmt, ok, ok2)
print('patch : cas=%d echecs=%d' % (tot, fails))
sys.exit(1 if fails else 0)
