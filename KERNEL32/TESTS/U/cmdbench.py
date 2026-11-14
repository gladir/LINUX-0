#!/usr/bin/env python3
# @author: Sylvain Maltais (support@gladir.com)
# @created: 2026
# @website(https://www.gladir.com/linux-0)
# @abstract(Target: Python 3)
# @description: Banc d'essai des commandes du depot compilees par LPC -3X.
#   cmdbench.py [-d dossier_des_ELF] [-o sortie.tsv] [-r]   (essai sur l'hote)
#   Chaque commande de la table TESTS recoit un essai fonctionnel dans un
#   dossier de travail absolu (/tmp/linux0-cmdbench) : sortie comparee a celle
#   de la commande GNU de l'hote ('ref'), a un texte ('is'), ou presence d'un
#   texte ('has'). Toutes les autres commandes recoivent l'essai "aide /?".
#   Les commandes destructives ne sont lancees que dans ce dossier, avec des
#   chemins absolus.
import os, sys, subprocess, shutil, time

BIN = os.environ.get('CMDBIN', '/tmp/linux0-u-tests/bin')
W = '/tmp/linux0-cmdbench'
args = sys.argv[1:]
OUT = None
if '-d' in args: BIN = args[args.index('-d') + 1]
if '-o' in args: OUT = args[args.index('-o') + 1]

FILES = {
 'in.txt': 'ligne un\nLigne deux\nzebra 3\nalpha 1\nbeta 2\nalpha 1\n\nfin\n',
 'nums.txt': '10\n9\n100\n2\n33\n',
 'a.txt': 'apple\nbanana\ncherry\n',
 'b.txt': 'banana\ncherry\ndate\n',
 'j1.txt': '1 a\n2 b\n3 c\n',
 'j2.txt': '1 x\n2 y\n4 z\n',
 'csv.txt': 'a,b,c\n1,2,3\nx,y,z\n',
 'long.txt': 'the quick brown fox jumps over the lazy dog and keeps running far away\n',
 'tab.txt': 'a\tb\tc\n',
 'bin.dat': ''.join(chr(i) for i in range(256)),
}
# (commande, arguments, entree standard, mode, attendu)
T = []
def t(cmd, a, stdin, mode, exp): T.append((cmd, a, stdin, mode, exp))
t('cat', ['in.txt'], None, 'ref', 'cat in.txt')
t('cat', ['-n', 'a.txt', 'b.txt'], None, 'has', '1  apple')
t('head', ['-n', '3', 'in.txt'], None, 'ref', 'head -n 3 in.txt')
t('tail', ['--lines', '2', 'in.txt'], None, 'ref', 'tail -n 2 in.txt')
t('wc', ['a.txt', '-l'], None, 'has', '3')
t('sort', ['in.txt'], None, 'ref', 'LC_ALL=C sort in.txt')
t('uniq', ['in.txt'], None, 'ref', 'uniq in.txt')
t('cut', ['in.txt', '-b', '1-3'], None, 'ref', 'cut -b1-3 in.txt')
t('tr', ['l', 'L'], 'hello\n', 'is', 'heLLo\n')
t('tac', ['in.txt'], None, 'ref', 'tac in.txt')
t('rev', ['in.txt'], None, 'ref', 'rev in.txt')
t('nl', ['a.txt'], None, 'has', 'apple')
t('paste', ['a.txt', 'b.txt'], None, 'ref', 'paste a.txt b.txt')
t('join', ['j1.txt', 'j2.txt'], None, 'ref', 'join j1.txt j2.txt')
t('comm', ['a.txt', 'b.txt'], None, 'has', 'cherry')
t('cmp', ['a.txt', 'a.txt'], None, 'rc', 0)
t('cmp', ['a.txt', 'b.txt'], None, 'rc', 1)
t('diff', ['a.txt', 'b.txt'], None, 'has', 'apple')
t('grep', ['alpha', 'in.txt'], None, 'has', 'alpha 1')
t('grep', ['LIGNE', 'in.txt', '/I'], None, 'has', 'ligne un')
t('egrep', ['al|ze', 'in.txt'], None, 'ref', 'grep -E "al|ze" in.txt')
t('fgrep', ['alpha', 'in.txt'], None, 'ref', 'grep -F alpha in.txt')
t('sed', ['s/a/A/g', 'a.txt'], None, 'ref', 'sed s/a/A/g a.txt')
t('sed', ['-e', 's/a/A/', 'a.txt'], None, 'ref', 'sed -e s/a/A/ a.txt')
t('awk', ['{print $2}'], 'x y z\n', 'is', 'y\n')
t('awk', ['{s+=$1} END {print s}', 'nums.txt'], None, 'ref', "awk '{s+=$1} END {print s}' nums.txt")
t('expr', ['2', '+', '3'], None, 'is', '5\n')
t('seq', ['1', '5'], None, 'ref', 'seq 1 5')
t('factor', ['60'], None, 'has', '2 2 3 5')
t('basename', ['/a/b/c.txt'], None, 'is', 'c.txt\n')
t('dirname', ['/a/b/c.txt'], None, 'has', '/a/b')
t('echo', ['a', 'b'], None, 'is', 'a b\n')
t('printf', ['x %s %d\\n', 'abc', '5'], None, 'is', 'x abc 5\n')
t('true', [], None, 'rc', 0)
t('false', [], None, 'rc', 1)
t("yes", [], None, "yeshead", "y")
t('fold', ['--width=20', 'long.txt'], None, 'ref', 'fold -w 20 long.txt')
t('fmt', ['--width=30', 'long.txt'], None, 'has', 'quick')
t('expand', ['tab.txt'], None, 'rc', 0)
t('unexpand', ['a.txt'], None, 'ref', 'unexpand a.txt')
t('column', ['-t', 'j1.txt'], None, 'has', 'a')
t('od', ['-c', 'a.txt'], None, 'has', '97')
t('hd', ['a.txt'], None, 'has', '61 70')
t('hexdump', ['-C', 'a.txt'], None, 'has', '61 70')
t('md5sum', ['a.txt'], None, 'ref', 'md5sum a.txt')
t('cksum', ['a.txt'], None, 'has', 'B55C5728')
t('sum', ['a.txt'], None, 'has', '22875')
t('base64', ['a.txt'], None, 'ref', 'base64 a.txt')
t('uuencode', ['a.txt', '/tmp/linux0-cmdbench/uu.out'], None, 'rc', 0)
t('split', ['-l', '1', 'a.txt', '/tmp/linux0-cmdbench/sp_'], None, 'rc', 0)
t('tee', ['/tmp/linux0-cmdbench/tee.out'], 'hello\n', 'is', 'hello\n')
t('touch', ['/tmp/linux0-cmdbench/touched'], None, 'rc', 0)
t('mkdir', ['/tmp/linux0-cmdbench/dd/ee'], None, 'rc', 0)
t('rmdir', ['/tmp/linux0-cmdbench/dd/ee'], None, 'rc', 0)
t('cp', ['a.txt', '/tmp/linux0-cmdbench/cp.out'], None, 'rc', 0)
t('mv', ['/tmp/linux0-cmdbench/cp.out', '/tmp/linux0-cmdbench/mv.out'], None, 'rc', 0)
t('rm', ['/tmp/linux0-cmdbench/mv.out'], None, 'rc', 0)
t('ls', ['/tmp/linux0-cmdbench/ls'], None, 'has', 'f1')
t('ls', ['-l', '/tmp/linux0-cmdbench/ls'], None, 'has', 'f1')
t('date', [], None, 'rc', 0)
t('cal', ['2', '2026'], None, 'has', '28')
t('env', [], None, 'has', 'PATH')
t('uname', ['-s'], None, 'rc', 0)
t('id', [], None, 'has', 'uid')
t('pwd', [], None, 'has', '/')
t('which', ['ls'], None, 'rc', 0)
t('df', [], None, 'rc', 0)
t('du', ['/tmp/linux0-cmdbench/ls'], None, 'rc', 0)
t('stat', ['a.txt'], None, 'has', 'a.txt')
t('tree', ['/tmp/linux0-cmdbench'], None, 'has', 'ls')
t('strings', ['bin.dat'], None, 'rc', 0)
t('look', ['ap', 'a.txt'], None, 'has', 'apple')
t('sleep', ['0'], None, 'rc', 0)
t('bc', ['-q'], '2+3*4\n', 'is', '14\n')
t('dc', [], '2 3 + p\n', 'is', '5\n')
t('sdiff', ['a.txt', 'b.txt'], None, 'has', 'apple')
t('csplit', ['a.txt', '2'], None, 'rc', 0)
t('mktemp', [], None, 'rc', 0)
t('seq', ['3'], None, 'ref', 'seq 3')
t('groups', [], None, 'rc', 0)
t('dd', ['if=a.txt', 'of=/tmp/linux0-cmdbench/dd.out'], None, 'rc', 0)
t('unlink', ['/tmp/linux0-cmdbench/touched'], None, 'rc', 0)
t('repeat', ['2', '/bin/echo', 'hi'], None, 'has', 'hi')
t('banner', ['OK'], None, 'has', '#')
t('clear', [], None, 'rc', 0)
t('gzip', ['-c', 'a.txt'], None, 'rt', 'gzip')
t('bzip2', ['-c', 'a.txt'], None, 'rt', 'bzip2')
t('compress', ['-c', 'a.txt'], None, 'rt', 'gzip')
t('chmod', ['644', '/tmp/linux0-cmdbench/ls/f1'], None, 'rc', 0)
t('basename', ['a.txt', '.txt'], None, 'is', 'a\n')
t('ed', ['a.txt'], '1p\nq\n', 'has', 'apple')

def shq(x):
    return "'" + x.replace("'", "'\\''") + "'"

def generate(D):
    """Ecrit D/ (fichiers d'essai, exp/N, run.sh) pour l'essai sous KERNEL32."""
    if not os.path.isabs(D) or 'bench' not in D:
        sys.exit('--gen : dossier absolu contenant "bench" exige')
    shutil.rmtree(D, ignore_errors=True)
    os.makedirs(D + '/files'); os.makedirs(D + '/exp'); os.makedirs(D + '/in')
    for n, c in FILES.items():
        open(D + '/files/' + n, 'w', encoding='latin-1').write(c)
    L = ['# genere par TESTS/U/cmdbench.py --gen : essai des commandes sous KERNEL32',
         'W=/tmp/bench; rm -rf $W; mkdir -p $W/ls $W/dd',
         'echo x > $W/ls/f1; echo y > $W/ls/f2; cd /usr/share/bench/files', 'P=0; F=0', 'LANGUAGE=EN; export LANGUAGE',
         'ok() { echo "BENCH-OK $1"; P=$((P+1)); }', 'ko() { echo "BENCH-KO $1 : $2"; F=$((F+1)); }']
    for i, (cmd, a, stdin, mode, exp) in enumerate(T):
        if mode in ('yeshead', 'rt'): continue
        line = shq(cmd.lower() + ' ' + ' '.join(a))
        args = ' '.join(shq(x) for x in a)
        src = ' < /usr/share/bench/in/%d' % i if stdin is not None else ' < /dev/null'
        if stdin is not None: open(D + '/in/%d' % i, 'w', encoding='latin-1').write(stdin)
        L.append('o=$(%s %s%s 2>&1); r=$?' % (cmd.lower(), args, src))
        if mode == 'ref':
            prepare()
            r = subprocess.run(['bash', '-c', exp], cwd=W, capture_output=True)
            open(D + '/exp/%d' % i, 'wb').write(r.stdout)
            L.append('[ "$o" = "$(cat /usr/share/bench/exp/%d)" ] && ok %s || ko %s "sortie"' % (i, line, line))
        elif mode == 'is':
            L.append('[ "$o" = %s ] && ok %s || ko %s "sortie"' % (shq(exp.rstrip('\n')), line, line))
        elif mode == 'has':
            L.append('case "$o" in *%s*) ok %s;; *) ko %s "sortie";; esac' % (shq(exp), line, line))
        elif mode == 'rc':
            L.append('[ $r = %d ] && ok %s || ko %s "rc=$r"' % (exp, line, line))
    L.append('echo "BENCH-FIN ok=$P ko=$F"')
    # essai "aide /?" de tous les programmes de /bin (code de sortie < 128)
    L += ['H=0; K=0',
          'for c in /bin/*; do n=${c##*/}',
          '  case $n in yes|login|sh|ash|ksh|strings) continue;; esac',
          '  $c "/?" < /dev/null > /dev/null 2>&1; r=$?',
          '  if [ $r -ge 128 ]; then echo "HELP-KO $n rc=$r"; K=$((K+1)); else H=$((H+1)); fi',
          'done', 'echo "HELP-FIN ok=$H ko=$K"']
    open(D + '/run.sh', 'w').write(
        ('\n'.join(L) + '\n').replace('/tmp/linux0-cmdbench', '/tmp/bench'))

def prepare():
    shutil.rmtree(W, ignore_errors=True)
    os.makedirs(W + '/ls')
    for n, c in FILES.items():
        open(W + '/' + n, 'w', encoding='latin-1').write(c)
    os.makedirs(W + '/dd/ee')
    open(W + '/ls/f1', 'w').write('x')
    open(W + '/ls/f2', 'w').write('y')

def run(cmd, a, stdin, to=10):
    exe = os.path.join(BIN, cmd.upper())
    if not os.path.exists(exe): return None, b'', b'absent'
    try:
        p = subprocess.run([exe] + a, input=(stdin or '').encode('latin-1'), cwd=W,
                           capture_output=True, timeout=to)
        return p.returncode, p.stdout, p.stderr
    except subprocess.TimeoutExpired:
        return 'timeout', b'', b''

if '--gen' in args:
    generate(args[args.index('--gen') + 1])
    sys.exit(0)

def main():
    res = {}
    for cmd, a, stdin, mode, exp in T:
        prepare()
        rc, so, se = run(cmd, a, stdin)
        label = cmd + ' ' + ' '.join(a)
        ok = False; note = ''
        if rc is None: note = 'absent'
        elif rc == 'timeout': note = 'delai depasse'
        elif mode == 'ref':
            prepare()
            r = subprocess.run(['bash', '-c', exp], cwd=W, capture_output=True)
            prepare(); rc, so, se = run(cmd, a, stdin)
            ok = so == r.stdout
            if not ok: note = 'sortie differente : %r contre %r' % (so[:60], r.stdout[:60])
        elif mode == 'is':
            ok = so == exp.encode(); note = '' if ok else 'sortie %r' % so[:60]
        elif mode == 'has':
            ok = exp.encode() in so; note = '' if ok else 'sortie %r rc=%s' % (so[:60], rc)
        elif mode == 'rc':
            ok = rc == exp; note = '' if ok else 'rc=%s %r' % (rc, se[:60])
        elif mode == 'yeshead':
            try:
                p = subprocess.run('%s | head -c 6' % os.path.join(BIN, 'YES'), shell=True, cwd=W, capture_output=True, timeout=5)
                ok = p.stdout.startswith(b'y\ny\n'); note = '' if ok else repr(p.stdout)
            except Exception: note = 'delai depasse'
        elif mode == 'rt':
            rc2, z, _ = run(cmd, a, None)
            pr = subprocess.run(['bash', '-c', '%s -dc' % exp], input=z, cwd=W, capture_output=True)
            ok = pr.stdout == FILES['a.txt'].encode(); note = '' if ok else 'aller-retour impossible'
        res.setdefault(cmd, []).append((label, ok, note))
    names = sorted(f for f in os.listdir(BIN) if not f.endswith('.err'))
    lines = []
    for n in names:
        c = n.lower()
        if c in res:
            tests = res[c]
            bad = [x for x in tests if not x[1]]
            etat = 'marche' if not bad else ('reserves' if len(bad) < len(tests) else 'echoue')
            essai = '; '.join(x[0] for x in tests)[:48]
            note = '; '.join(x[2] for x in bad)[:70]
        else:
            prepare()
            rc, so, se = run(c, ['/?'], None, 5)
            if rc is None: etat, essai, note = 'echoue', 'absent', ''
            elif rc == 'timeout': etat, essai, note = 'reserves', 'aide /?', 'delai depasse'
            elif rc in (0, 1, 2) or rc < 128:
                etat, essai, note = 'marche', 'aide /?', 'demarre et affiche son aide' if (so or se) else 'demarre'
            else: etat, essai, note = 'echoue', 'aide /?', 'rc=%s' % rc
        lines.append((c, etat, essai, note))
    out = ['%-12s %-9s %-48s %s' % l for l in lines]
    txt = '\n'.join(out)
    cnt = {k: sum(1 for l in lines if l[1] == k) for k in ('marche', 'reserves', 'echoue')}
    print(txt); print(cnt)
    if OUT: open(OUT, 'w').write(txt + '\n')
main()
