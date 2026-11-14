#!/usr/bin/env python3
# Genere la partie "programmes embarques" du noyau a partir des ELF compiles.
# usage : MKEMBED.PY <dossier des ELF> <KERNEL32.PAS | sortie.pas>
# Si le fichier de sortie contient les marqueurs { BEGIN-EMBED } et { END-EMBED }
# (cas de KERNEL32.PAS), la partie entre les marqueurs est remplacee.
import sys, os, base64
src, dst = sys.argv[1], sys.argv[2]
progs = [('/sbin/init', 'init'), ('/bin/hello', 'hello'), ('/bin/forkwait', 'forkwait'),
         ('/bin/pipetest', 'pipetest'), ('/bin/sigtest', 'sigtest'),
         ('/bin/mmaptest', 'mmaptest'), ('/bin/dirtest', 'dirtest'),
         ('/bin/ttytest', 'ttytest'), ('/bin/schedtest', 'schedtest'), ('/bin/blktest', 'blktest'), ('/bin/misctest', 'misctest'), ('/bin/proctest', 'proctest'), ('/bin/stress', 'stress'), ('/bin/kbdtest', 'kbdtest')]
lines = []; starts = []; sizes = []
for path, name in progs:
    d = open(os.path.join(src, name), 'rb').read()
    b = base64.b64encode(d).decode()
    starts.append(len(lines)); sizes.append(len(d))
    for i in range(0, len(b), 60):
        lines.append(b[i:i+60])
starts.append(len(lines))
o = []
o.append("{ Programmes embarques (genere par TESTS/K/MKEMBED.PY) : ELF i386 statiques")
o.append("  encodes en base64, ecrits dans le tmpfs racine au demarrage. }")
o.append("")
o.append("Const")
o.append("  EmbCount = %d;" % len(progs))
o.append("  EmbPath : Array[0..%d] Of String[20] = (" % (len(progs) - 1))
o.append(",\n".join("    '%s'" % p for p, n in progs) + ");")
o.append("  EmbSize : Array[0..%d] Of LongInt = (" % (len(progs) - 1))
def wrapnums(v):
    out = []; cur = "   "
    for x in v:
        t = " " + str(x) + ","
        if len(cur) + len(t) > 78:
            out.append(cur); cur = "   "
        cur += t
    out.append(cur)
    return "\n".join(out)[:-1] + ");"
o.append(wrapnums(sizes))
o.append("  EmbStart : Array[0..%d] Of LongInt = (" % len(progs))
o.append(wrapnums(starts))
o.append("  EmbData : Array[0..%d] Of String[60] = (" % (len(lines) - 1))
o.append(",\n".join("    '%s'" % l for l in lines) + ");")
o.append("")
text = "\n".join(o) + "\n"
B, E = "{ BEGIN-EMBED }", "{ END-EMBED }"
try:
    old = open(dst, encoding='latin-1').read()
except IOError:
    old = ''
if B in old and E in old:
    i = old.index(B) + len(B); j = old.index(E)
    new = old[:i] + "\n" + text + old[j:]
    open(dst, 'w', encoding='latin-1').write(new)
else:
    open(dst, 'w').write(B + "\n" + text + E + "\n")
print("embarque: %d programmes, %d octets, %d lignes" % (len(progs), sum(sizes), len(lines)))
