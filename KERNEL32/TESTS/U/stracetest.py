#!/usr/bin/env python3
# @author: Sylvain Maltais (support@gladir.com)
# @created: 2026
# @website(https://www.gladir.com/linux-0)
# @abstract(Target: Python 3, hote Linux avec strace GNU)
# @description: compare notre strace (programme i386 statique) au strace GNU
#   de l'hote sur des programmes i386 : suite des noms d'appels systeme,
#   comptes de -c, code de retour, -f sur un shell, -e trace=, -o.
#   Usage : stracetest.py STRACE BINDIR
import os, re, subprocess, sys, tempfile

ME = os.path.abspath(sys.argv[1])
BIN = os.path.abspath(sys.argv[2])
GNU = '/usr/bin/strace'
W = tempfile.mkdtemp(prefix='stracetest')
ok = ko = 0


def res(name, cond, extra=''):
    global ok, ko
    if cond:
        ok += 1
        print('ok    ' + name)
    else:
        ko += 1
        print('KO    %s %s' % (name, extra))


def names(path, pid=False):
    out = []
    for l in open(path, errors='replace'):
        m = re.match(r'^(?:\[pid +(\d+)\] |(\d+) +)?(\w+)\(', l)
        if m:
            out.append(((m.group(1) or m.group(2) or '') if pid else '',
                    m.group(3)))
    return out


def both(args, env=None, opts=()):
    g = os.path.join(W, 'g.txt')
    m = os.path.join(W, 'm.txt')
    rg = subprocess.run([GNU, '-o', g] + list(opts) + args,
                        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                        cwd=W, env=env)
    rm = subprocess.run([ME, '-o', m] + list(opts) + args,
                        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                        cwd=W, env=env)
    return g, m, rg.returncode, rm.returncode


env = dict(os.environ, LANG='C', LC_ALL='C')
open(os.path.join(W, 'in.txt'), 'w').write('un\ndeux\ntrois\n')
D = os.path.join(W, 'dir')
os.mkdir(D)
for f in ('a', 'b', 'c'):
    open(os.path.join(D, f), 'w').write(f)
cases = [
    ('cat', [BIN + '/cat', 'in.txt']),
    ('ls', [BIN + '/ls', '-l', D]),
    ('echo', [BIN + '/echo', 'bonjour']),
    ('grep', [BIN + '/grep', 'deux', 'in.txt']),
    ('false', [BIN + '/false']),
    ('cat absent', [BIN + '/cat', '/nonexistent']),
    ('wc', [BIN + '/wc', '-l', 'in.txt']),
]
for nm, args in cases:
    g, m, rg, rm = both(args, env)
    a, b = names(g), names(m)
    res('strace %s : suite des appels (%d)' % (nm, len(a)), a == b,
        '\n GNU %s\n moi %s' % ([x[1] for x in a][:30], [x[1] for x in b][:30]))
    res('strace %s : code de retour' % nm, rg == rm, '%d %d' % (rg, rm))

# -e trace=
g, m, _, _ = both([BIN + '/cat', 'in.txt'], env, ['-e', 'trace=open,read'])
res('-e trace=open,read', names(g) == names(m) and len(names(m)) > 0)
g, m, _, _ = both([BIN + '/cat', 'in.txt'], env, ['-e', 'trace=!write,read'])
res('-e trace=!write,read', names(g) == names(m))
g, m, _, _ = both([BIN + '/cat', 'in.txt'], env, ['-e', 'trace=file'])
res('-e trace=file (%d)' % len(names(m)), names(g) == names(m),
    '%s %s' % (names(g), names(m)))

# contenu d'une ligne
l = [x for x in open(os.path.join(W, 'm.txt'))]
g, m, _, _ = both([BIN + '/cat', 'in.txt'], env, ['-e', 'trace=open,write'])
t = open(m).read()
res('ligne write(1, "deux\\n", 5) = 5',
    'write(1, "deux\\n", 5) = 5' in t, t)

# -c : comptes par appel
mc = os.path.join(W, 'mc.txt')
gc = os.path.join(W, 'gc.txt')
subprocess.run([GNU, '-c', '-o', gc, BIN + '/ls', D],
               stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, env=env)
subprocess.run([ME, '-c', '-o', mc, BIN + '/ls', D],
               stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, env=env)


def counts(p):
    d = {}
    for l in open(p):
        f = l.split()
        if len(f) >= 5 and f[0][0].isdigit() and f[-1] != 'total':
            d[f[-1]] = int(f[3])
    return d


cg, cm = counts(gc), counts(mc)
res('-c : comptes par appel (%d appels)' % len(cm), cg == cm and len(cm) > 0,
    '%s %s' % (cg, cm))
res('-c : en-tete', open(mc).read().startswith('% time'))

# -f sur un shell
sh = BIN + '/sh'
script = 'echo un; /bin/true; echo deux'
args = [sh, '-c', 'cat in.txt | wc -l']
env2 = dict(env, PATH=BIN)
g, m, rg, rm = both(args, env2, ['-f'])
ng = sorted(set(x[1] for x in names(g, True)))
nm_ = sorted(set(x[1] for x in names(m, True)))
pg = len(set(x[0] for x in names(g, True) if x[0]))
pm = len(set(x[0] for x in names(m, True) if x[0]))
res('-f sh -c "cat | wc" : processus suivis (%d)' % pm, pm >= 2 and
    pm == pg, '%d %d' % (pg, pm))
res('-f : memes appels distincts', ng == nm_, '%s\n%s' % (ng, nm_))
t = open(m).read()
res('-f : prefixe PID', re.search(r'^\d+ execve', t, re.M)
    is not None)
res('-f : sorties +++ exited', t.count('+++ exited with 0 +++') >= 3,
    t.count('+++ exited'))

# signal
g, m, rg, rm = both([sh, '-c', 'kill -TERM $$'], env)
t = open(m).read()
res('signal : +++ killed by SIGTERM +++', '+++ killed by SIGTERM +++' in t, t)
res('signal : code de retour (%d)' % rm, rg == rm)

# erreur : commande absente
r = subprocess.run([ME, '/nonexistent'], capture_output=True, text=True)
res('commande absente : code 1 et message', r.returncode == 1 and
    'Cannot find executable' in r.stderr)

# -p : attache a un processus qui dort
p = subprocess.Popen([BIN + '/sleep', '2'])
import time
time.sleep(0.3)
mo = os.path.join(W, 'mp.txt')
r = subprocess.run([ME, '-p', str(p.pid), '-o', mo], capture_output=True,
                   text=True, timeout=20)
p.wait()
t = open(mo).read() if os.path.exists(mo) else ''
res('-p PID : trace d\'un sleep', '+++ exited with 0 +++' in t and
    ('exit_group' in t), t + r.stderr)

print('STRACE-FIN ok=%d ko=%d' % (ok, ko))
sys.exit(1 if ko else 0)
