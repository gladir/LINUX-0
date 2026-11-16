#!/usr/bin/env python3
# @author: Sylvain Maltais (support@gladir.com)
# @created: 2026
# @website(https://www.gladir.com/linux-0)
# @description: Genere LAYOUTS.INC (dispositions de clavier, depuis
#   LAYOUTS.TXT) et MSGS.INC (textes traduits, depuis CATALOG.TXT) en
#   constantes Pascal ASCII : les caracteres Windows-1252 deviennent #nnn.
#   Usage : MKDATA.PY            (dans USR/INSTALLER)
import os, re, sys

HERE = os.path.dirname(os.path.abspath(__file__))
LANGS = ['fr', 'en', 'de', 'it', 'es', 'pt', 'nl']
# touches mortes : codes internes 2 a 6 (circonflexe, trema, grave, aigu, tilde)
DEAD = {'dcirc': 2, 'ddiaer': 3, 'dgrave': 4, 'dacute': 5, 'dtilde': 6}
DEADCH = {2: 94, 3: 168, 4: 96, 5: 180, 6: 126}
KEYORDER = [41] + list(range(2, 14)) + list(range(16, 28)) + \
    list(range(30, 41)) + [43] + list(range(44, 54)) + [86]


def cp(ch):
    if ch == 'nul':
        return 1
    if ch in DEAD:
        return DEAD[ch]
    if len(ch) != 1:
        raise SystemExit('jeton invalide : %r' % ch)
    return ch.encode('cp1252')[0]


def plit(s, width=70):
    """chaine -> liste de fragments Pascal (<= width colonnes)"""
    out = []
    cur = ''
    inq = False
    for ch in s:
        b = ch.encode('cp1252')[0]
        if 32 <= b < 127 and ch != "'":
            piece = ch
            q = True
        elif ch == "'":
            piece = "''"
            q = True
        else:
            piece = '#%d' % b
            q = False
        if q and not inq:
            cur += "'"
            inq = True
        if not q and inq:
            cur += "'"
            inq = False
        cur += piece
        if len(cur) >= width:
            if inq:
                cur += "'"
                inq = False
            out.append(cur)
            cur = ''
    if inq:
        cur += "'"
    if cur:
        out.append(cur)
    return out or ["''"]


def emit_str(lines, indent, parts, tail):
    first = True
    for i, p in enumerate(parts):
        last = i == len(parts) - 1
        pre = indent if first else indent + '  '
        lines.append(pre + p + (' +' if not last else tail))
        first = False


# ---- dispositions ----
def layouts():
    ids, names, planes = [], [], []
    cur = None
    for raw in open(os.path.join(HERE, 'LAYOUTS.TXT'), encoding='utf-8'):
        line = raw.rstrip('\n')
        if not line.strip() or line.startswith('#'):
            continue
        if line.startswith('layout '):
            _, i, *n = line.split()
            ids.append(i)
            names.append(' '.join(n))
            cur = {}
            planes.append(cur)
        else:
            k, rest = line.split(':', 1)
            toks = rest.split()
            if len(toks) != 48:
                raise SystemExit('%s plan %s : %d touches' %
                                 (ids[-1], k, len(toks)))
            cur[k] = [cp(t) for t in toks]
    L = []
    L.append('{ LAYOUTS.INC : genere par MKDATA.PY depuis LAYOUTS.TXT. }')
    L.append('Const')
    L.append('  LayCount = %d;' % len(ids))
    L.append('  LayKc : Array[0..47] Of Byte = (')
    for i in range(0, 48, 16):
        L.append('    ' + ','.join(str(v) for v in KEYORDER[i:i + 16]) +
                 (',' if i + 16 < 48 else ''))
    L.append('  );')
    L.append('  LayId : Array[0..%d] Of String[6] = (' % (len(ids) - 1))
    for i, v in enumerate(ids):
        L.append("    '%s'%s" % (v, ',' if i < len(ids) - 1 else ''))
    L.append('  );')
    L.append('  LayName : Array[0..%d] Of String[40] = (' % (len(ids) - 1))
    for i, v in enumerate(names):
        parts = plit(v)
        emit_str(L, '    ', parts, ',' if i < len(ids) - 1 else '')
    L.append('  );')
    n = len(ids) * 144
    L.append('  LayData : Array[0..%d] Of Byte = (' % (n - 1))
    flat = []
    for p in planes:
        flat += p['N'] + p['S'] + p['A']
    for i in range(0, n, 16):
        L.append('    ' + ','.join(str(v) for v in flat[i:i + 16]) +
                 (',' if i + 16 < n else ''))
    L.append('  );')
    open(os.path.join(HERE, 'LAYOUTS.INC'), 'w').write('\n'.join(L) + '\n')
    print('LAYOUTS.INC', len(ids), 'dispositions')
    # KEYMAPS.KRN : meme donnees sous forme d'appels KbdRow du noyau (a coller
    # dans KbdInitMaps de KERNEL32.PAS pour keymap=XX ; table 0 normale, 1
    # majuscule, 2 AltGr ; caracteres Latin-1 : sortie UTF-8 par KbdPutChar)
    K = ['{ KEYMAPS.KRN : genere par MKDATA.PY depuis LAYOUTS.TXT (E5).',
         '  Procedure KbdLoadLayout(Const N : String) : remplit',
         '  KbdMapLo/Hi/Alt',
         '  pour keymap=N (us uk fr be de chde chfr it es pt nl). }',
         'Procedure KbdLoadLayout(Const N : String);',
         'Begin']
    runs = [(41, 1), (2, 12), (16, 12), (30, 11), (43, 1), (44, 10), (86, 1)]
    for li, lid in enumerate(ids):
        K.append("  If N = '%s' Then" % lid)
        K.append('  Begin')
        for pl, tbl in (('N', 0), ('S', 1), ('A', 2)):
            vals = dict(zip(KEYORDER, planes[li][pl]))
            for st, n in runs:
                seq = [vals[st + j] for j in range(n)]
                # l'euro n'est pas Latin-1 : omis
                seq = [0 if v == 0x80 else DEADCH.get(v, v) for v in seq]
                if all(v in (0, 1) for v in seq):
                    continue
                parts = plit(''.join(chr(v) if v > 1 else '\x00' for v in seq))
                K.append('    KbdRow(%d, %d, %s);' %
                         (tbl, st, ' + '.join(parts)))
        K.append('  End;')
    K.append('End;')
    open(os.path.join(HERE, 'KEYMAPS.KRN'), 'w').write('\n'.join(K) + '\n')


# ---- messages ----
def messages():
    path = os.path.join(HERE, 'CATALOG.TXT')
    if not os.path.exists(path):
        return
    keys, tab = [], {}
    cur = None
    for raw in open(path, encoding='utf-8'):
        line = raw.rstrip('\n')
        if not line.strip() or line.startswith('#'):
            continue
        if line.startswith('@'):
            cur = line[1:].strip()
            if cur in tab:
                raise SystemExit('cle en double : ' + cur)
            keys.append(cur)
            tab[cur] = {}
            continue
        m = re.match(r'^(fr|en|de|it|es|pt|nl):\s?(.*)$', line)
        if not m:
            raise SystemExit('ligne invalide : ' + line)
        tab[cur][m.group(1)] = m.group(2).replace('\\n', '\n')
    L = []
    L.append('{ MSGS.INC : genere par MKDATA.PY depuis CATALOG.TXT. Textes en')
    L.append('  Windows-1252 : MsgBlob (octets) et MsgOff (debuts, N*7+1). }')
    L.append('Const')
    L.append('  MsgLangs = %d;' % len(LANGS))
    for i, k in enumerate(keys):
        L.append('  M_%s = %d;' % (k, i))
    L.append('  MsgCount = %d;' % len(keys))
    blob = bytearray()
    offs = []
    for k in keys:
        for lg in LANGS:
            v = tab[k].get(lg)
            if v is None:
                v = tab[k].get('en')
                print('manque %s:%s' % (k, lg), file=sys.stderr)
            offs.append(len(blob))
            blob += v.encode('cp1252')
    offs.append(len(blob))
    L.append('  MsgOff : Array[0..%d] Of LongInt = (' % (len(offs) - 1))
    for i in range(0, len(offs), 10):
        L.append('    ' + ','.join(str(v) for v in offs[i:i + 10]) +
                 (',' if i + 10 < len(offs) else ''))
    L.append('  );')
    L.append('  MsgBlob : Array[0..%d] Of Byte = (' % (len(blob) - 1))
    for i in range(0, len(blob), 16):
        L.append('    ' + ','.join(str(v) for v in blob[i:i + 16]) +
                 (',' if i + 16 < len(blob) else ''))
    L.append('  );')
    open(os.path.join(HERE, 'MSGS.INC'), 'w').write('\n'.join(L) + '\n')
    print('MSGS.INC', len(keys), 'messages x', len(LANGS), 'langues,',
          len(blob), 'octets')


layouts()
messages()
