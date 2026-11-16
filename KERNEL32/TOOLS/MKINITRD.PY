#!/usr/bin/env python3
# @author: Sylvain Maltais (support@gladir.com)
# @created: 2026
# @description: Fabrique une archive cpio "newc" compressee (gzip) a partir d'un
#   dossier : initramfs de KERNEL32 (partie 38 : module Multiboot, /init ou
#   /sbin/init ; noeuds /dev, /proc, /sys crees par le noyau).
#   usage : MKINITRD.PY DOSSIER SORTIE.cpio.gz [--raw]
#   Fichiers, repertoires, liens symboliques, noeuds de peripheriques ;
#   proprietaires 0:0 ; --raw : sans gzip.
import os, sys, stat, gzip
class Cpio:
    def __init__(s): s.b = bytearray(); s.ino = 1
    def add(s, name, mode, data=b'', rdev=(0, 0), nlink=1, mtime=0):
        s.ino += 1
        nm = name.encode() + b'\0'
        s.b += b'070701' + b''.join(b'%08X' % v for v in (s.ino, mode, 0, 0, nlink, mtime, len(data), 3, 1, rdev[0], rdev[1], len(nm), 0))
        s.b += nm
        while len(s.b) % 4: s.b.append(0)
        s.b += data
        while len(s.b) % 4: s.b.append(0)
src, out = sys.argv[1], sys.argv[2]
c = Cpio()
n = 0
for d, dirs, files in os.walk(src):
    dirs.sort()
    rel = os.path.relpath(d, src)
    if rel != '.':
        st = os.lstat(d)
        c.add(rel, stat.S_IFDIR | (st.st_mode & 0o7777), mtime=int(st.st_mtime))
    for f in sorted(files):
        p = os.path.join(d, f)
        r = os.path.relpath(p, src)
        st = os.lstat(p)
        m = st.st_mode
        if stat.S_ISLNK(m):
            c.add(r, m, os.readlink(p).encode(), mtime=int(st.st_mtime))
        elif stat.S_ISREG(m):
            c.add(r, m, open(p, 'rb').read(), mtime=int(st.st_mtime))
        elif stat.S_ISCHR(m) or stat.S_ISBLK(m):
            c.add(r, m, rdev=(os.major(st.st_rdev), os.minor(st.st_rdev)))
        n += 1
c.add('TRAILER!!!', 0)
while len(c.b) % 512: c.b.append(0)
if '--raw' in sys.argv: open(out, 'wb').write(bytes(c.b))
else: open(out, 'wb').write(gzip.compress(bytes(c.b), 9, mtime=0))
print('%s : %d entrees, %d octets' % (out, n, os.path.getsize(out)))
