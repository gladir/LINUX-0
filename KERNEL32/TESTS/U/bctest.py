#!/usr/bin/env python3
# @author: Sylvain Maltais (support@gladir.com)
# @created: 2026
# @website(https://www.gladir.com/linux-0)
# @abstract(Target: Python 3, hote avec GNU bc)
# @description: compare bc (programme i386) au GNU bc de l'hote sur des
#   scripts : arithmetique, echelle, bases, fonctions, boucles, tableaux,
#   bibliotheque mathematique (-l), coupure des lignes.
#   Usage : bctest.py BC
import os, subprocess, sys

ME = os.path.abspath(sys.argv[1])
ok = ko = 0
ENV = dict(os.environ, LANG='C', LC_ALL='C', BC_LINE_LENGTH='70')


def run(prog, text, opts=(), env=ENV):
    r = subprocess.run([prog] + list(opts), input=text, capture_output=True,
                       text=True, env=env, timeout=60)
    return r.stdout


def check(name, text, opts=()):
    global ok, ko
    a = run('/usr/bin/bc', text, opts)
    b = run(ME, text, opts)
    if a == b:
        ok += 1
        print('ok    ' + name)
    else:
        ko += 1
        print('KO    ' + name)
        al, bl = a.splitlines(), b.splitlines()
        for i in range(max(len(al), len(bl))):
            x = al[i] if i < len(al) else '<fin>'
            y = bl[i] if i < len(bl) else '<fin>'
            if x != y:
                print('   ligne %d : GNU %r  moi %r' % (i + 1, x[:90], y[:90]))
                break


T = []
T.append(('addition', '1+2\n-5+3\n.5+.25\n999999999999+1\n'))
T.append(('soustraction', '5-8\n0.1-0.3\n100-1\n-3-4\n'))
T.append(('multiplication', '3*4\n-3*4\n1.5*2.5\n123456789*987654321\n0*5\n'))
T.append(('division', 'scale=0\n7/2\nscale=5\n7/2\n1/3\n-1/3\n1/7\n10/4\n'))
T.append(('division echelle 20', 'scale=20\n1/3\n22/7\n2/3\n100/7\n'))
T.append(('modulo', '7%3\n-7%3\n7%-3\nscale=2\n7%3\n10%3\n5.5%2\nscale=0\n'
          '10%4\n'))
T.append(('puissance', '2^10\n2^100\n2^-1\nscale=3\n2^-2\n2.5^2\n'
          '(-2)^3\n2^3^2\n0^0\n5^0\n10^20\n'))
T.append(('unaire et priorites', '-2^2\n2*-3\n!0\n!1\n!0+1\n1<2\n2<1\n'
          '1==1\n1!=1\n3>=3\n2<=1\n1&&0\n1||0\n!1||1\n'))
T.append(('racine', 'sqrt(16)\nscale=10\nsqrt(2)\nsqrt(0)\nsqrt(.0001)\n'
          'sqrt(1000000)\nscale=30\nsqrt(3)\n'))
T.append(('length scale', 'length(12.345)\nscale(1.50)\nlength(0)\n'
          'length(.05)\nlength(100)\nscale=5\nscale(5/2)\nlength(5/2)\n'))
T.append(('variables', 'x=5\ny=x*2\nx+y\nx=x+1\nx\nabc=3\nabc_1=4\nabc*abc_1\n'
          'x=y=7\nx+y\n'))
T.append(('affectations composees', 'x=10\nx+=5\nx\nx-=3\nx\nx*=2\nx\nx/=4\n'
          'x\nx%=4\nx\nx^=3\nx\n'))
T.append(('incrementation', 'z=5\nz++\nz\n++z\nz--\nz\n--z\nz\nz++ + ++z\n'))
T.append(('last', '3*4\n.\n.+1\nlast\nlast*2\n'))
T.append(('bases entree', 'ibase=16\nA\nFF\n1A.8\n.1\nibase=2\n101.1\n'
          '11\nibase=A\nibase=3\n.1\n2.12\n'))
T.append(('bases sortie', 'obase=16\n255\n255.5\n.5\nobase=2\n10\n.5\n'
          'obase=8\n64\nobase=3\n.5\n0.1\nobase=36\n1000\n'
          'obase=100\n12345\nobase=1000\n123456789\n'))
T.append(('bases mixtes', 'ibase=2\nobase=1010\n1010\nibase=A\nobase=2\n10\n'
          '1/3\nscale=10\n1/3\n'))
T.append(('si sinon', 'x=3\nif (x>2) print "grand\\n"\nif (x>5) print "tres\\n" '
          'else print "petit\\n"\nif (x==3) { print "trois\\n" }\n'))
T.append(('tantque', 'i=0\nwhile (i<5) { i++; i }\n'
          'i=10\nwhile (i>7) i--\ni\n'))
T.append(('pour', 'for (i=0; i<5; i++) i*i\n'
          's=0\nfor (i=1; i<=100; i++) s+=i\ns\n'
          'for (;;) { break }\nfor (i=0; i<3; i++) { for (j=0; j<2; j++) '
          'i*10+j }\n'))
T.append(('break continue', 'for (i=0; i<10; i++) { if (i==3) continue; '
          'if (i==6) break; i }\n'
          'i=0\nwhile (1) { i++; if (i%2) continue; if (i>8) break; i }\n'))
T.append(('fonctions', 'define f(x) { return (x*x) }\nf(5)\nf(1.5)\n'
          'define g(a,b) { return (a+b) }\ng(1,2)\ng(f(2),f(3))\n'
          'define h() { return (42) }\nh()\n'))
T.append(('recursion', 'define f(n) { if (n<=1) return (1); '
          'return (n*f(n-1)) }\nf(10)\nf(30)\nf(50)\n'
          'define fib(n) { if (n<2) return (n); '
          'return (fib(n-1)+fib(n-2)) }\nfib(15)\n'))
T.append(('auto et portee', 'x=100\ndefine f(a) { auto x; x=a*2; return (x) }'
          '\nf(4)\nx\ndefine g() { x=7; return (0) }\ng()\nx\n'))
T.append(('tableaux', 'a[0]=1\na[1]=2\na[5]=6\na[0]+a[1]+a[5]\n'
          'for (i=0;i<10;i++) b[i]=i*i\nb[9]\nb[3]\na[2]\n'
          'define s(a[], n) { auto i, t; for (i=0;i<n;i++) t+=a[i]; '
          'return (t) }\ns(b[], 10)\n'))
T.append(('void', 'define void p(x) { print "x=", x, "\\n" }\np(3)\np(4.5)\n'
          'define q(x) { return (x+1) }\nq(1)\n'))
T.append(('chaines et print', '"bonjour\\n"\nprint "a", 1, "b", 2+3, "\\n"\n'
          'print "tab\\there\\n"\nx=3\nprint x, "\\n"\n'))
T.append(('commentaires', '/* debut */ 1+1 /* milieu */ + 2\n# ligne\n3 # fin\n'
          '/* multi\nligne */ 4\n'))
T.append(('continuation', '1+\\\n2\n12345678901234567890\\\n12345\n'))
T.append(('plusieurs instructions', '1;2;3\nx=1;y=2;x+y\n{ 5\n6 }\n'))
T.append(('affectation entre parentheses', '(x=5)\nx\n(y=x=3)+1\n'))
T.append(('grands nombres', '2^1000\n3^500\n7^77/13\n'
          'scale=50\n1/7\n2^0.5\ne=1\n'))
T.append(('coupure des lignes', '2^1000\n10^100\n1/3\nscale=100\n1/3\n'
          'x=2^300\nx*x\n'))
T.append(('division negative', 'scale=3\n-7/2\n7/-2\n-7/-2\n-1/3\n'))
T.append(('precision', 'scale=40\n1/3\n2/3\n355/113\n'))
T.append(('chiffres', 'scale=2\n1.005*1\n.001\n0.999+0.001\n1.10\n1.10+1.1\n'
          '3.14159*2\n'))
T.append(('zero et signes', '0\n-0\n0.000\nx=0.0\nx\n0*-1\n-0.5\n--1\n'))
T.append(('halt', '1\nhalt\n2\n'))
T.append(('quit', '1\nquit\n2\n'))
T.append(('evaluation courte', 'x=0\n0&&(x=5)\nx\n1||(x=6)\nx\n1&&(x=7)\nx\n'))
T.append(('limites echelle', 'scale=0\n5/2\nscale=1\n5/2\nscale=2\n5/2\n'
          'scale=15\n5/2\nscale\n'))
T.append(('puissance grande echelle', 'scale=20\n2^-10\n1.5^10\n(-1.5)^7\n'
          '0.1^5\n'))
T.append(('conversion ibase constantes', 'ibase=16\nFFFF\nA0\nibase=A\n'
          '10\n'))
T.append(('expression imbriquee', '((1+2)*(3+4))/(5-2)\n'
          'scale=4\n((1+2)*(3+4))/(5-2)\n2*(3+(4*(5+6)))\n'))
T.append(('factorielle 100', 'define f(n) { auto r; r=1; '
          'while (n>1) {\nr*=n\nn-=1\n}\nreturn (r)\n}\nf(100)\n'))
T.append(('suite de nombres', 'for (i=1; i<=12; i++) { 2^i; 3^i }\n'))
T.append(('programme de crible', 'n=50\nfor (i=2;i<=n;i++) p[i]=1\n'
          'for (i=2;i<=n;i++) { if (p[i]) { for (j=i*i;j<=n;j+=i) p[j]=0 } }\n'
          'for (i=2;i<=n;i++) if (p[i]) i\n'))
for n, t in T:
    check(n, t)

LIB = []
LIB.append(('-l e(1)', 'e(1)\ne(0)\ne(-1)\ne(2.5)\ne(10)\n'))
LIB.append(('-l l(2)', 'l(2)\nl(1)\nl(10)\nl(.5)\nl(100)\n'))
LIB.append(('-l s(1)', 's(1)\ns(0)\ns(3)\ns(-2)\ns(100)\ns(.5)\n'))
LIB.append(('-l c(1)', 'c(1)\nc(0)\nc(3)\nc(-2)\nc(100)\n'))
LIB.append(('-l a(1)', 'a(1)\na(0)\na(.5)\na(-1)\na(10)\na(100)\n'))
LIB.append(('-l pi', '4*a(1)\nscale=50\n4*a(1)\n'))
LIB.append(('-l j', 'j(0,1)\nj(1,1)\nj(2,2.5)\nj(3,10)\nj(5,7.5)\nj(2,.3)\nj(0,2)\n'))
LIB.append(('-l echelle', 'scale=10\ne(1)\nl(5)\ns(2)\nc(2)\na(2)\n'
            'scale=40\ne(1)\n'))
LIB.append(('-l sqrt', 'sqrt(2)\nsqrt(10)\n1/3\n'))
for n, t in LIB:
    check(n, t, ['-l'])

# erreurs : ne doivent pas arreter les instructions suivantes
a = run(ME, '1/0\n2+2\n')
check_ok = a.splitlines()[-1:] == ['4']
if check_ok:
    ok += 1
    print('ok    division par zero : on continue')
else:
    ko += 1
    print('KO    division par zero : on continue %r' % a)
a = run(ME, 'f(1)\n3\n')
if a.splitlines()[-1:] == ['3']:
    ok += 1
    print('ok    fonction inconnue : on continue')
else:
    ko += 1
    print('KO    fonction inconnue : on continue %r' % a)
a = run(ME, '1 +* 2\n5\n')
if a.splitlines()[-1:] == ['5']:
    ok += 1
    print('ok    erreur de syntaxe : on continue')
else:
    ko += 1
    print('KO    erreur de syntaxe %r' % a)
# fichiers puis entree standard
open('/tmp/bctest_f.bc', 'w').write('define f(x) { return (x+1) }\n')
r = subprocess.run([ME, '/tmp/bctest_f.bc'], input='f(41)\n',
                   capture_output=True, text=True)
if r.stdout == '42\n':
    ok += 1
    print('ok    fichier puis entree standard')
else:
    ko += 1
    print('KO    fichier puis entree standard %r' % r.stdout)
print('BC-FIN ok=%d ko=%d' % (ok, ko))
sys.exit(1 if ko else 0)
