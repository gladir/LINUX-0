#!/usr/bin/env python3
# @author: Sylvain Maltais (support@gladir.com)
# @created: 2026
# @website(https://www.gladir.com/linux-0)
# @abstract(Target: Python 3)
# @description: Fabrique TOOLS/COMMANDES.TXT a partir de la sortie de
#   cmdbench.py (hote) et de celle de run.sh sous QEMU (BENCH-OK/BENCH-KO).
#   mkcmdtab.py host.txt qemu.txt sortie.txt
import sys, re
host, qemu, out = sys.argv[1:4]
NOTES = {
 'awk': ('reserves', "interprete AWK minimal du depot : la plupart des mots (print $N, if, while...) ne sont pas implantes"),
 'ksh': ('reserves', "shell interactif : l'aide /? attend l'entree"),
 'yes': ('marche', "boucle infinie par nature : essai par tube vers head"),
}
rows = []
for l in open(host, encoding='latin-1'):
    p = l.rstrip('\n').split(None, 2)
    if len(p) < 2: continue
    c, etat = p[0], p[1]
    rest = l[len(c):].strip()[len(etat):].strip() if len(p) > 1 else ''
    essai = rest[:44].strip(); note = rest[44:].strip()
    rows.append([c, etat, essai, note])
qok, qko, qhelp, qhko = {}, {}, True, set()
for l in open(qemu, encoding='latin-1', errors='replace'):
    m = re.match(r'BENCH-(OK|KO) (\S+)', l)
    if m:
        d = qok if m.group(1) == 'OK' else qko
        d[m.group(2).lower()] = d.get(m.group(2).lower(), 0) + 1
    m = re.match(r'HELP-KO (\S+)', l)
    if m: qhko.add(m.group(1).lower())
cnt = {'marche': 0, 'reserves': 0, 'echoue': 0}
lines = []
for c, etat, essai, note in rows:
    if c in NOTES:
        etat, note = NOTES[c]
    if etat == 'echoue' and c == 'yes': etat = 'marche'
    q = 'KO' if c in qko else ('ok' if c in qok else ('KO' if c in qhko else 'aide'))
    if c in ('yes',): q = '-'
    cnt[etat] += 1
    lines.append('%-12s %-9s %-5s %-44s %s' % (c, etat, q, essai[:44], note[:70]))
hdr = open(out).read().split('Resume')[0] if False else None
head = '''COMMANDES DE LINUX-0 SOUS KERNEL32 (compilees par LPC -3X)
==============================================================

Banc d'essai : KERNEL32/TESTS/U/cmdbench.py (hote) et
USR/ROOTFS/usr/share/bench/run.sh (sous QEMU). Chaque commande de la table
recoit un essai fonctionnel (sortie comparee a la commande GNU de l'hote, a un
texte, ou presence d'un texte) sur l'hote (ELF32 statique execute directement)
puis, sous le noyau KERNEL32 amorce sous QEMU depuis IMAGE/LINUX32-HD.IMG
(ext2). Les autres commandes recoivent l'essai "aide /?" (demarre, affiche son
aide, code de sortie < 128). Les commandes sont des programmes de style DOS
(Uses Dos, Crt) : leur syntaxe est la leur (voir leur aide), pas celle de GNU ;
seuls les resultats de meme syntaxe sont compares a GNU. Fabrique par
TESTS/U/mkcmdtab.py.

ETAT : marche = fonctionne conformement a son aide pour les essais faits ;
       reserves = fonctionne avec une limite (voir REMARQUE) ;
       echoue = ne fonctionne pas (cause dans REMARQUE).
QEMU : ok = meme resultat sous KERNEL32 ; KO = difference ; aide = seul l'essai
       d'aide a ete fait ; - = non essaye.

Resume : %d marchent, %d avec reserves, %d echouent (sur %d programmes)

COMMANDE     ETAT      QEMU  ESSAI                                        REMARQUE
----------   --------  ----  ------------------------------------------   --------------------
''' % (cnt['marche'], cnt['reserves'], cnt['echoue'], len(rows))
open(out, 'w', encoding='latin-1').write(head + '\n'.join(lines) + '\n')
print(cnt, 'qemu ko:', sorted(qko), 'help ko:', sorted(qhko))
