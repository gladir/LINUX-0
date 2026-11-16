#!/usr/bin/env python3
# @author: Sylvain Maltais (support@gladir.com)
# @created: 2026
# @website(https://www.gladir.com/linux-0)
# @abstract(Target: Python 3, hote avec GNU bc)
# @description: essais de dc (programme i386) : sorties attendues connues de
#   GNU dc, et recoupement des operations arithmetiques avec le GNU bc de
#   l'hote (memes echelles, memes arrondis, coupure des lignes).
#   Usage : dctest.py DC
import os, random, subprocess, sys

ME = os.path.abspath(sys.argv[1])
ok = ko = 0
ENV = dict(os.environ, LANG='C', LC_ALL='C', BC_LINE_LENGTH='70')


def dc(text, args=()):
    r = subprocess.run([ME] + list(args), input=text, capture_output=True,
                       text=True, env=ENV, timeout=60)
    return r.stdout, r.stderr, r.returncode


def t(name, text, expect, args=()):
    global ok, ko
    out = dc(text, args)[0]
    if out == expect:
        ok += 1
        print('ok    ' + name)
    else:
        ko += 1
        print('KO    %s : attendu %r obtenu %r' % (name, expect, out[:200]))


t('addition', '2 3 + p\n', '5\n')
t('soustraction', '3 5 - p\n', '-2\n')
t('multiplication', '123456789 987654321 * p\n', '121932631112635269\n')
t('division entiere', '10 3 / p\n', '3\n')
t('division echelle', '5k 10 3 / p\n', '3.33333\n')
t('modulo', '10 3 % p\n_7 3 % p\n', '1\n-1\n')
t('divmod', '10 3 ~ f\n', '1\n3\n')
t('puissance', '2 10 ^ p\n2 100 ^ p\n', '1024\n1267650600228229401496703205376\n')
t('puissance negative', '3k 2 _2 ^ p\n', '.250\n')
t('racine', '4 v p\n2k 2 v p\n0 v p\n', '2\n1.41\n0\n')
t('modexp', '4 13 497 | p\n', '445\n')
t('negatif', '_5 p\n_5 3 + p\n', '-5\n-2\n')
t('fraction', '.5 p\n0.25 p\n1.50 p\n', '.5\n.25\n1.50\n')
t('pile f', '1 2 3 f\n', '3\n2\n1\n')
t('swap', '1 2 r f\n', '1\n2\n')
t('dup', '3 d * p\n', '9\n')
t('depth', 'z p\n1 2 3 z p\n', '0\n4\n')
t('clear', '1 2 3 c z p\n', '0\n')
t('R retire', '1 2 3 R f\n', '2\n1\n')
t('chaine', '[hello]p\n[a [b] c]p\n', 'hello\na [b] c\n')
t('chaine echappee', '[a\\]b]p\n', 'a]b\n')
t('Z chiffres', '12345 Z p\n1.5 Z p\n[abc] Z p\n0 Z p\n', '5\n2\n3\n1\n')
t('X echelle', '1.500 X p\n7 X p\n', '3\n0\n')
t('registres', '5 sa 6 sb la lb + p\n', '11\n')
t('pile de registre', '1 Sa 2 Sa La p La p\n', '2\n1\n')
t('registre vide', 'la p\n', '0\n')
t('tableaux', '5 0:a 7 1:a 0;a 1;a + p\n9 3:b 3;b p 4;b p\n', '12\n9\n0\n')
t('bases', '16 o 255 p\n2 o 10 p\n', 'FF\n1010\n')
t('ibase', '16 i FF p\n', '255\n')
t('K I O', 'K p I p O p\n3 k K p\n', '0\n10\n10\n3\n')
t('base sortie fraction', '16 o .5 p\n', '.8\n')
t('base 100', '100 o 12345 p\n', ' 01 23 45\n')
t('macro x', '[1 p]x\n', '1\n')
t('macro dans registre', '[2 3 *]sa la x p\n', '6\n')
t('comparaison >', '[[plus]p]sa 3 5 >a\n5 3 >a\n', 'plus\n')
t('comparaison <', '[[moins]p]sa 5 3 <a\n3 5 <a\n', 'moins\n')
t('comparaison =', '[[egal]p]sa 3 3 =a\n3 4 =a\n', 'egal\n')
t('comparaison !=', '[[diff]p]sa 3 4 !=a\n3 3 !=a\n', 'diff\n')
t('comparaison !<', '[[ok]p]sa 3 5 !<a\n5 3 !<a\n', 'ok\n')
t('boucle', '0sa [la 1 + d sa p la 3 >L]sL lLx\n', '1\n2\n3\n')
t('factorielle', '5 [d1-d1<F*]dsFx p\n', '120\n')
t('factorielle 30', '30 [d1-d1<F*]dsFx p\n',
  '265252859812191058636308480000000\n')
t('appel terminal profond', '0sa [la 1 + d sa 20000 >L]sL lLx la p\n',
  '20000\n')
t('q', '1 p q 2 p\n', '1\n')
t('q dans macro', '1 p [2 p q]x 3 p\n', '1\n2\n')
t('Q', '[2 p 1Q 3 p]x 4 p\n', '2\n4\n')
t('Q 2', '[[2 p 2Q 3 p]x 4 p]x 5 p\n', '2\n5\n')
t('a caractere', '97 a p\n[xyz] a p\n', 'a\nx\n')
t('P octets', '97 P\n[abc]P\n', 'abc'[0:1] + 'abc')
t('n sans saut', '5 n 6 n\n', '56')
t('commentaire', '1 p # 2 p\n3 p\n', '1\n3\n')
t('echelle k', '20 k 1 3 / p\n', '.33333333333333333333\n')
t('echelle du produit', '2k 3.14159 2 * p\n3.1 2 * p\n', '6.28318\n6.2\n')
t('-e', '', '7\n', ['-e', '3 4 + p'])
t('-e multiple', '', '7\n8\n', ['-e', '3 4 + p', '-e', '8 p'])
open('/tmp/dctest_f.dc', 'w').write('[hi]p\n2 3 * p\n')
t('-f fichier', '', 'hi\n6\n', ['-f', '/tmp/dctest_f.dc'])
t('fichier en argument', '', 'hi\n6\n', ['/tmp/dctest_f.dc'])
t('? lit une ligne', '?\n6 7 * p\n', '42\n')
t('chaine sur plusieurs lignes', '[a\nb]p\n', 'a\nb\n')

# coupure : comparer a bc
out = dc('2 1000 ^ p\n')[0]
ref = subprocess.run(['/usr/bin/bc'], input='2^1000\n', capture_output=True,
                     text=True, env=ENV).stdout
if out == ref:
    ok += 1
    print('ok    coupure des lignes identique a bc')
else:
    ko += 1
    print('KO    coupure des lignes %r %r' % (out[:80], ref[:80]))
ok -= 0

# recoupement avec bc sur des operations aleatoires
random.seed(12345)
bad = 0
n = 0
for i in range(250):
    sc = random.choice([0, 0, 2, 5, 10, 20])
    a = random.choice(['', '-']) + str(random.randint(0, 10 ** random.randint(1, 25)))
    b = str(random.randint(1, 10 ** random.randint(1, 18)))
    if random.random() < 0.4:
        a += '.' + str(random.randint(0, 10 ** random.randint(1, 8)))
    if random.random() < 0.3:
        b += '.' + str(random.randint(1, 10 ** random.randint(1, 6)))
    op = random.choice('+-*/%')
    dcs = '%dk %s %s %s p\n' % (sc, a.replace('-', '_'), b, op)
    bcs = 'scale=%d\n%s %s %s\n' % (sc, a, op, b)
    x = dc(dcs)[0]
    y = subprocess.run(['/usr/bin/bc'], input=bcs, capture_output=True,
                       text=True, env=ENV).stdout
    n += 1
    if x != y:
        bad += 1
        if bad <= 3:
            print('   ecart : %r  dc=%r bc=%r' % (bcs, x, y))
if bad == 0:
    ok += 1
    print('ok    recoupement avec bc : %d operations' % n)
else:
    ko += 1
    print('KO    recoupement avec bc : %d ecarts sur %d' % (bad, n))
# racines et puissances
bad = 0
for i in range(60):
    sc = random.choice([0, 3, 10, 20])
    a = str(random.randint(0, 10 ** random.randint(1, 20)))
    if random.random() < 0.5:
        a += '.' + str(random.randint(0, 10 ** random.randint(1, 6)))
    x = dc('%dk %s v p\n' % (sc, a))[0]
    y = subprocess.run(['/usr/bin/bc'], input='scale=%d\nsqrt(%s)\n' % (sc, a),
                       capture_output=True, text=True, env=ENV).stdout
    if x != y:
        bad += 1
        if bad <= 3:
            print('   ecart racine : %s k=%d dc=%r bc=%r' % (a, sc, x, y))
if bad == 0:
    ok += 1
    print('ok    recoupement racines avec bc : 60')
else:
    ko += 1
    print('KO    racines : %d ecarts' % bad)
bad = 0
for i in range(40):
    sc = random.choice([0, 2, 6])
    a = str(random.randint(1, 50))
    if random.random() < 0.5:
        a += '.' + str(random.randint(1, 99))
    e = random.randint(-5, 30)
    x = dc('%dk %s %s ^ p\n' % (sc, a, str(e).replace('-', '_')))[0]
    y = subprocess.run(['/usr/bin/bc'], input='scale=%d\n%s ^ %d\n' % (sc, a, e),
                       capture_output=True, text=True, env=ENV).stdout
    if x != y:
        bad += 1
        if bad <= 3:
            print('   ecart puissance : %s^%d k=%d dc=%r bc=%r' % (a, e, sc, x, y))
if bad == 0:
    ok += 1
    print('ok    recoupement puissances avec bc : 40')
else:
    ko += 1
    print('KO    puissances : %d ecarts' % bad)
print('DC-FIN ok=%d ko=%d' % (ok, ko))
sys.exit(1 if ko else 0)
