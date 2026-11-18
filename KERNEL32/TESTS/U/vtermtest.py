#!/usr/bin/env python3
# @author: Sylvain Maltais (support@gladir.com)
# @created: 2026
# @website(https://www.gladir.com/linux-0)
# @abstract(Target: Python 3)
# @description: essais de VTCORE.INC (emulateur VT100/ANSI) par VTDRV :
#   sequences envoyees, ecran/curseur/historique/reponses compares.
#   Usage : vtermtest.py VTDRV
import subprocess, sys, os

DRV = os.path.abspath(sys.argv[1])
ok = ko = 0


def run(data, cols=80, rows=24):
    r = subprocess.run([DRV, str(cols), str(rows)], input=data,
                       capture_output=True, timeout=20)
    d = {'R': {}, 'S': {}}
    for l in r.stdout.decode('latin-1').splitlines():
        if l.startswith('R') and ':' in l:
            n, t = l[1:].split(':', 1)
            d['R'][int(n)] = t
        elif l.startswith('S') and ':' in l and l[1].isdigit():
            n, t = l[1:].split(':', 1)
            d['S'][int(n)] = t
        else:
            k, _, v = l.partition(' ')
            d[k] = v
    return d


def t(name, data, rows=None, cur=None, sb=None, out=None, at=None,
      cols=80, nrows=24, srow=None):
    global ok, ko
    d = run(data, cols, nrows)
    bad = []
    for y, txt in (rows or {}).items():
        if d['R'].get(y, '') != txt:
            bad.append('ligne %d %r (attendu %r)' % (y, d['R'].get(y, ''), txt))
    if cur is not None and d.get('CUR') != '%d %d' % cur:
        bad.append('curseur %s (attendu %s)' % (d.get('CUR'), cur))
    if sb is not None and d.get('SB') != str(sb):
        bad.append('historique %s (attendu %d)' % (d.get('SB'), sb))
    if out is not None and d.get('OUT') != out.encode().hex().upper():
        bad.append('reponse %s' % d.get('OUT'))
    if at is not None and d.get('AT') != at:
        bad.append('attr %s (attendu %s)' % (d.get('AT'), at))
    for n, txt in (srow or {}).items():
        if d['S'].get(n) != txt:
            bad.append('hist %d %r' % (n, d['S'].get(n)))
    if bad:
        ko += 1
        print('KO    %s : %s' % (name, '; '.join(bad)))
    else:
        ok += 1
        print('ok    ' + name)


E = '\x1b'
t('texte et CRLF', b'hello\r\nworld', rows={0: 'hello', 1: 'world'}, cur=(5, 1))
t('retour chariot', b'abc\rX', rows={0: 'Xbc'}, cur=(1, 0))
t('retour arriere', b'abc\x08\x08X', rows={0: 'aXc'}, cur=(2, 0))
t('tabulation', b'a\tb', rows={0: 'a       b'}, cur=(9, 0))
t('positionnement H', (E + '[3;5Hx').encode(), rows={2: '    x'}, cur=(5, 2))
t('curseur A B C D', (E + '[5;5H' + E + '[2A' + E + '[3C' + E + '[1B' +
                      E + '[2Dx').encode(), rows={3: '     x'}, cur=(6, 3))
t('effacement ecran J', (b'abc\r\ndef' + (E + '[2J').encode()),
  rows={}, cur=(3, 1))
t('effacement fin de ligne K',
  (b'abcdef' + (E + '[3D' + E + '[K').encode()),
  rows={0: 'abc'})
t('effacement debut de ligne',
  (b'abcdef' + (E + '[3D' + E + '[1K').encode()),
  rows={0: '    ef'})
t('insertion de lignes L',
  (b'1\r\n2\r\n3' + (E + '[2;1H' + E + '[L').encode()),
  rows={0: '1', 2: '2', 3: '3'})
t('suppression de lignes M',
  (b'1\r\n2\r\n3' + (E + '[2;1H' + E + '[M').encode()),
  rows={0: '1', 1: '3'})
t('suppression de caracteres P',
  (b'abcdef' + (E + '[1;2H' + E + '[2P').encode()),
  rows={0: 'adef'})
t('insertion de caracteres @',
  (b'abcdef' + (E + '[1;2H' + E + '[2@').encode()),
  rows={0: 'a  bcdef'})
t('effacement de caracteres X',
  (b'abcdef' + (E + '[1;2H' + E + '[3X').encode()),
  rows={0: 'a   ef'})
t('defilement avec historique', b''.join(b'l%d\r\n' % i for i in range(30)),
  rows={0: 'l7', 22: 'l29'}, sb=7, srow={0: 'l6', 1: 'l5'})
t('region : defilement interne',
  (E + '[1;1Hhaut' + E + '[2;3r' + E + '[3;1Ha\r\nb\r\nc').encode(),
  rows={0: 'haut', 1: 'b', 2: 'c'})
t('retour a la ligne automatique', b'x' * 85, rows={0: 'x' * 80, 1: 'xxxxx'},
  cur=(5, 1))
t('ESC 7 / ESC 8', (b'ab' + (E + '7').encode() + b'\r\n\r\ncd' +
                    (E + '8').encode() + b'X'), rows={0: 'abX', 2: 'cd'})
t('ESC M indexation inverse', (b'1\r\n2' + (E + '[1;1H' + E + 'M').encode()),
  rows={1: '1', 2: '2'})
t('SGR : rouge sur bleu', (E + '[31;44mA').encode(), at='65 0')
t('SGR : gras', (E + '[1mA').encode(), at='7 4')
t('SGR : souligne et inverse', (E + '[4;7mA').encode(), at='7 3')
t('SGR 256 couleurs', (E + '[38;5;9mA').encode(), at='9 0')
t('SGR vives 90-97', (E + '[91mA').encode(), at='9 0')
t('SGR 0 remet a zero', (E + '[1;31m' + E + '[0mA').encode(), at='7 0')
t('rapport de position DSR', (E + '[3;7H' + E + '[6n').encode(), out=E + '[3;7R')
t('identification DA', (E + '[c').encode(), out=E + '[?1;2c')
t('ecran alternatif 1049', (b'main' + (E + '[?1049h').encode() + b'alt' +
                            (E + '[?1049l').encode()), rows={0: 'main'})
t('ecran alternatif : contenu propre',
  b'main' + (E + '[?1049h').encode() + b'alt', rows={0: 'alt'})
t('sequence OSC (titre) ignoree', (E + ']0;titre\x07ok').encode(),
  rows={0: 'ok'})
t('jeu de caracteres ESC ( B ignore', (E + '(Bok').encode(), rows={0: 'ok'})
t('UTF-8 Latin-1', 'café à'.encode(), rows={0: 'caf\xe9 \xe0'})
t('UTF-8 hors Latin-1 : ?', '中'.encode(), rows={0: '?'})
t('cadre en trait : ASCII', '┌─┐'.encode(), rows={0: '+-+'})
t('sequence coupee puis reprise', (E + '[1;1').encode() + b'Hxy', rows={0: 'xy'})
t('petit terminal 40x10', b''.join(b'%d\r\n' % i for i in range(15)),
  rows={0: '6', 8: '14'}, sb=6, cols=40, nrows=10)
t('curseur borne', (E + '[999;999H').encode(), cur=(79, 23))
t('ESC c reinitialise', (b'abc' + (E + 'c').encode() + b'x'), rows={0: 'x'})
t('S / T defilement', (b'1\r\n2\r\n3' + (E + '[1S').encode()),
  rows={0: '2', 1: '3'})
print('VTERM-FIN ok=%d ko=%d' % (ok, ko))
sys.exit(1 if ko else 0)
