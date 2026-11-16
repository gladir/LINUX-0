#!/usr/bin/env python3
# @author: Sylvain Maltais (support@gladir.com)
# @created: 2026
# @website(https://www.gladir.com/linux-0)
# @abstract(Target: Python 3)
# @description: essais de ed (programme i386) : scripts passes sur l'entree
#   standard, sortie et fichier resultant compares aux valeurs de GNU ed
#   (adresses, a i c d m t j k s g v G V u y x r w e f z = l n p).
#   Usage : edtest.py ED
import os, subprocess, sys, tempfile

ME = os.path.abspath(sys.argv[1])
W = tempfile.mkdtemp(prefix='edtest')
ok = ko = 0
ENV = dict(os.environ, LANG='C', LC_ALL='C')


def ed(script, initial=None, args=('-s',), name='f.txt'):
    f = os.path.join(W, name)
    if os.path.exists(f):
        os.unlink(f)
    if initial is not None:
        open(f, 'w').write(initial)
    cmd = [ME] + list(args)
    if initial is not None or name:
        cmd.append(name)
    r = subprocess.run(cmd, input=script, capture_output=True, text=True,
                       cwd=W, env=ENV, timeout=20)
    res = open(f).read() if os.path.exists(f) else None
    return r.stdout, res, r.returncode


def t(name, script, initial, out=None, res=None, args=('-s',), rc=None):
    global ok, ko
    o, r, c = ed(script, initial, args)
    bad = []
    if out is not None and o != out:
        bad.append('sortie %r (attendu %r)' % (o, out))
    if res is not None and r != res:
        bad.append('fichier %r (attendu %r)' % (r, res))
    if rc is not None and c != rc:
        bad.append('code %d (attendu %d)' % (c, rc))
    if bad:
        ko += 1
        print('KO    %s : %s' % (name, '; '.join(bad)))
    else:
        ok += 1
        print('ok    ' + name)


F = 'un\ndeux\ntrois\nquatre\ncinq\n'
t('p', '2p\n', F, out='deux\n')
t('p plage', '2,4p\n', F, out='deux\ntrois\nquatre\n')
t('p $', '$p\n', F, out='cinq\n')
t('p .', '.p\n', F, out='cinq\n')
t('virgule', ',p\n', F, out=F)
t('point virgule', '2;p\n', F, out='deux\ntrois\nquatre\ncinq\n')
t('pourcent', '%n\n', F, out='1\tun\n2\tdeux\n3\ttrois\n4\tquatre\n5\tcinq\n')
t('adresse relative', '3\n-1p\n+2p\n', F, out='trois\ndeux\nquatre\n')
t('adresse -', '3p\n-p\n', F, out='trois\ndeux\n')
t('adresse ++', '1\n++p\n', F, out='un\ntrois\n')
t('adresse motif', '/tro/p\n', F, out='trois\n')
t('adresse motif arriere', '$\n?deu?p\n', F, out='cinq\ndeux\n')
t('motif avec decalage', '/deux/+1p\n', F, out='trois\n')
t('numero seul', '3\n', F, out='trois\n')
t('entree vide', '1\n\n', F, out='un\ndeux\n')
t('d', '2d\nw\n', F, res='un\ntrois\nquatre\ncinq\n')
t('d plage', '2,4d\nw\n', F, res='un\ncinq\n')
t('d courant', '3\nd\n.p\nw\n', F, out='trois\nquatre\n', res='un\ndeux\nquatre\ncinq\n')
t('d dernier', '$d\n.p\n', F, out='quatre\n')
t('a', '2a\nnouveau\n.\nw\n', F, res='un\ndeux\nnouveau\ntrois\nquatre\ncinq\n')
t('a 0', '0a\ndebut\n.\nw\n', F, res='debut\nun\ndeux\ntrois\nquatre\ncinq\n')
t('i', '2i\navant\n.\nw\n', F, res='un\navant\ndeux\ntrois\nquatre\ncinq\n')
t('a plusieurs', '$a\nA\nB\n.\nw\n', F, res=F + 'A\nB\n')
t('c', '2,3c\nX\nY\nZ\n.\nw\n', F, res='un\nX\nY\nZ\nquatre\ncinq\n')
t('c une ligne', '1c\nremplace\n.\nw\n', F, res='remplace\ndeux\ntrois\nquatre\ncinq\n')
t('m', '1m3\nw\n', F, res='deux\ntrois\nun\nquatre\ncinq\n')
t('m plage', '1,2m$\nw\n', F, res='trois\nquatre\ncinq\nun\ndeux\n')
t('m 0', '4m0\nw\n', F, res='quatre\nun\ndeux\ntrois\ncinq\n')
t('m courant', '1m3\n.p\n', F, out='un\n')
t('t', '1t$\nw\n', F, res=F + 'un\n')
t('t plage', '1,2t0\nw\n', F, res='un\ndeux\n' + F)
t('t courant', '2t3\n.p\n', F, out='deux\n')
t('j', '1,3j\nw\n', F, res='undeuxtrois\nquatre\ncinq\n')
t('j plage', '2,3j\nw\n', F, res='un\ndeuxtrois\nquatre\ncinq\n')
t('k et marque', '2ka\n4kb\n\'a,\'bp\n', F, out='deux\ntrois\nquatre\n')
t('marque invalide', '\'zp\n', F, out='?\n', rc=1)
t('s', 's/cinq/5/\n.p\n', F, out='5\n')
t('s g', 'a\naaa\n.\ns/a/b/g\n.p\n', '', out='bbb\n')
t('s numero', 'a\naaa\n.\ns/a/b/2\n.p\n', '', out='aba\n')
t('s & ', '1s/un/[&]/\n.p\n', F, out='[un]\n')
t('s groupes', '2s/\\(d\\)\\(eux\\)/\\2\\1/\n.p\n', F, out='euxd\n')
t('s plage', '1,3s/^/> /\nw\n', F, res='> un\n> deux\n> trois\nquatre\ncinq\n')
t('s delimiteur', '1s,un,ONE,\n.p\n', F, out='ONE\n')
t('s drapeau p', '1s/un/UN/p\n', F, out='UN\n')
t('s vide', '1s/un//\n.p\n', F, out='\n')
t('s derniere regex', '/trois/\ns//TROIS/\n.p\n', F, out='trois\nTROIS\n')
t('s repete', '1s/n/N/\ns\n.p\n', 'nn\n', out='NN\n')
t('s saut de ligne', '1s/ /\\\n/\nw\n', 'a b\n', res='a\nb\n')
t('s absent', 's/zzz/y/\n', F, out='?\n', rc=1)
t('s esperluette echappee', '1s/un/\\&/\n.p\n', F, out='&\n')
t('s pourcent', '1s/un/UN/\n2s/deux/%/\n.p\n', F, out='UN\n')
t('g', 'g/e/p\n', F, out='deux\nquatre\n')
t('g sans correspondance', 'g/ui/\n', F, out='?\n', rc=1)
t('g s', 'g/u/s/u/U/\nw\n', F, res='Un\ndeUx\ntrois\nqUatre\ncinq\n')
t('g d', 'g/e/d\nw\n', F, res='un\ntrois\ncinq\n')
t('g plage', '1,2g/./s/$/!/\nw\n', F, res='un!\ndeux!\ntrois\nquatre\ncinq\n')
t('g a', 'g/un/a\\\nbis\\\n.\nw\n', F,
  res='un\nbis\ndeux\ntrois\nquatre\ncinq\n')
t('g m', 'g/^/m0\nw\n', F, res='cinq\nquatre\ntrois\ndeux\nun\n')
t('v', 'v/e/p\n', F, out='un\ntrois\ncinq\n')
t('v d', 'v/e/d\nw\n', F, res='deux\nquatre\n')
t('g et undo', 'g/e/d\nu\nw\n', F, res=F)
t('G', 'G/e/\n\nd\nw\n', F, out='deux\nquatre\n',
  res='un\ndeux\ntrois\ncinq\n')
t('u', '1d\nu\nw\n', F, res=F)
t('u deux fois', '1d\nu\nu\nw\n', F, res='deux\ntrois\nquatre\ncinq\n')
t('u s', '1s/un/UN/\nu\nw\n', F, res=F)
t('u rien', 'u\n', F, out='?\n', rc=1)
t('y x', '2y\n4x\nw\n', F, res='un\ndeux\ntrois\nquatre\ndeux\ncinq\n')
t('y plage', '1,2y\n$x\nw\n', F, res=F + 'un\ndeux\n')
t('=', '=\n2=\n', F, out='5\n2\n')
t('l', 'a\na\\b\t$\n.\n1l\n', '', out='a\\\\b\\t$$\n')
t('n', '2n\n', F, out='2\tdeux\n')
t('z fin', 'z2\n', F, out='?\n', rc=1)
t('z suite', '1\nz2\n', F, out='un\ndeux\ntrois\n')
t('f', 'f\n', F, out='f.txt\n')
t('w octets', 'w\n', F, out='')
t('w octets sans -s', 'w\n', F, out='26\n26\n', args=())
t('r', 'r f.txt\nw g.txt\n', F, out='')
t('r a une adresse', '2r f.txt\n,p\n', 'a\nb\n', out='a\nb\na\nb\n')
t('w plage', '2,3w sub.txt\n!cat sub.txt\n', F, out='deux\ntrois\n')
t('W ajoute', '1W f.txt\n,p\n', 'x\n', out='x\n')
t('e', 'e f.txt\n,p\n', 'x\ny\n', out='4\n4\nx\ny\n', args=())
t('q', 'q\n', F, rc=0)
t('q modifie', '1d\nq\n', F, out='?\n', rc=1)
t('Q', '1d\nQ\n', F, out='', rc=0)
t('q puis q', '1d\nq\nq\nw\n', F, out='?\n', rc=1)
t('wq', '1d\nwq\n', F, res='deux\ntrois\nquatre\ncinq\n')
t('H message', 'H\n9p\n', F, out='?\nInvalid address\n', rc=1)
t('h message', '9p\nh\n', F, out='?\nInvalid address\n', rc=1)
t('adresse invalide', '6p\n', F, out='?\n', rc=1)
t('commande inconnue', 'X\n', F, out='?\n', rc=1)
t('suffixe', '2dp\n', F, out='trois\n')
t('suffixe n', '2dn\n', F, out='2\ttrois\n')
t('commentaire', '# note\n1p\n', F, out='un\n')
t('!', '!echo salut\n', F, out='salut\n')
t('r !', 'r !echo bonjour\n,p\n', 'x\n', out='x\nbonjour\n')
t('fichier sans saut final', ',p\n', 'a\nb', out='a\nb\n')
t('fichier vide', ',p\n', '', out='?\n', rc=1)
t('ligne longue', 'a\n' + 'x' * 600 + '\n.\n1p\n', '', out='x' * 600 + '\n')
t('texte avec point', 'a\n..\n.\n,p\n', '', out='..\n')
t('motif crochets', '/[a-c]/p\n', 'zzz\nabc\n', out='abc\n')
t('motif ancre', '/^t/p\n', F, out='trois\n')
t('motif bouclage', '$\n/un/p\n', F, out='cinq\nun\n')
t('adresse ; motif', '1;/trois/p\n', F, out='un\ndeux\ntrois\n')
t('compte g', 'g/./s/./X/\n,p\n', 'ab\ncd\n', out='Xb\nXd\n')
t('suppression et courant', '$d\n$d\n.p\n', F, out='trois\n')
t('P prompt', 'P\n1p\n', F, out='*un\n*')
print('ED-FIN ok=%d ko=%d' % (ok, ko))
sys.exit(1 if ko else 0)
