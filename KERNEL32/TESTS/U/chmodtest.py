#!/usr/bin/env python3
# @author: Sylvain Maltais (support@gladir.com)
# @created: 2026
# @website(https://www.gladir.com/linux-0)
# @description: chmod de USR/CHMOD.PAS contre GNU chmod (hote) : modes octaux
#   et symboliques sur fichiers et dossiers, depart de plusieurs modes, -R.
#   usage : chmodtest.py ./CHMOD
import os, stat, subprocess, sys, tempfile

PROG = os.path.abspath(sys.argv[1])
MODES = ['755', '644', '4755', '1777', '0', 'u+x', 'g-w', 'o=r', 'a=rx',
         'u=rwx,go=rx', '+x', '-x', 'a-rwx', 'g+s', 'u+s', '+t', 'u=g', 'o+u',
         'go=u-w', 'a+X', 'u+rX', 'ug+rw,o-r', '=rw', 'g=', 'a-s,o-t']
START = [0o644, 0o755, 0o000, 0o4711, 0o2755, 0o1777, 0o640]
bad = n = 0
d = tempfile.mkdtemp()
for mode in MODES:
    for st in START:
        for kind in ('f', 'd'):
            a = os.path.join(d, 'a' + kind)
            b = os.path.join(d, 'b' + kind)
            for p in (a, b):
                if os.path.exists(p):
                    os.chmod(p, 0o700)
                    (os.rmdir if kind == 'd' else os.unlink)(p)
                if kind == 'f':
                    open(p, 'w').close()
                else:
                    os.mkdir(p)
                os.chmod(p, st)
            ra = subprocess.run([PROG, mode, a], capture_output=True)
            rb = subprocess.run(['chmod', mode, b], capture_output=True)
            ma = stat.S_IMODE(os.stat(a).st_mode)
            mb = stat.S_IMODE(os.stat(b).st_mode)
            n += 1
            if ma != mb or ra.returncode != rb.returncode:
                bad += 1
                if bad < 15:
                    print('DIFF', mode, oct(st), kind, oct(ma), oct(mb))
# -R
t = os.path.join(d, 'tree')
os.makedirs(t + '/s/u')
for f in ('f1', 's/f2', 's/u/f3'):
    open(os.path.join(t, f), 'w').close()
subprocess.run([PROG, '-R', 'u=rwx,go=rx', t])
ok = all(stat.S_IMODE(os.stat(os.path.join(t, p)).st_mode) == 0o755
         for p in ('', 'f1', 's', 's/f2', 's/u', 's/u/f3'))
n += 1
if not ok:
    bad += 1
    print('DIFF -R')
r = subprocess.run([PROG, 'z+q', t], capture_output=True)
n += 1
if r.returncode == 0:
    bad += 1
    print('mode invalide accepte')
print('chmod : %d comparaisons, %d ecarts' % (n, bad))
sys.exit(1 if bad else 0)
