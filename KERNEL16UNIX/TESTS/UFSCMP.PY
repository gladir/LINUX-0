#!/usr/bin/env python3
# @author: Sylvain Maltais (support@gladir.com)
# @created: 2026
# @website(https://www.gladir.com/linux-0)
# @description: Controle independant d'un systeme de fichiers UFS1 : relit
#   les superblocs, inodes, repertoires et blocs de donnees avec un lecteur
#   UFS1 ecrit ici en Python (sans le noyau LINUX-0, sans UFSCHK, sans
#   makefs) et compare chaque fichier de l'image (contenu, mode,
#   proprietaire, groupe, nombre de liens des repertoires) a une
#   arborescence de reference de l'hote (la racine de BUILD.SH).
#   Usage : python3 UFSCMP.PY IMAGE ARBRE [--hd | --floppy] [--extra FICHIER...]
#     --hd      : IMAGE est un disque dur (partition UFS de type A5h du MBR)
#     --floppy  : IMAGE est un UFS1 sans MBR (debut 0), comme une disquette
#     --extra   : fichiers presents en plus dans l'image (ex. etc/profile)
#   Code de sortie 0 si l'image est identique a l'arborescence.
import os, struct, sys


class Ufs:
    def __init__(self, data, start=0):
        self.d = data
        self.b = start * 512
        sb = self.b + 8192
        u32 = lambda o: struct.unpack_from('<I', data, sb + o)[0]
        if u32(1372) != 0x011954:
            raise ValueError('pas de superbloc UFS1')
        self.bsize, self.fsize, self.frag = u32(48), u32(52), u32(56)
        self.iblkno, self.ipg, self.fpg = u32(16), u32(184), u32(188)
        self.inopb, self.nindir = u32(120), u32(116)

    def frag_off(self, f):
        return self.b + f * self.fsize

    def inode(self, n):
        cg = n // self.ipg
        f = (self.fpg * cg + self.iblkno
             + ((n % self.ipg) // self.inopb) * self.frag)
        o = self.frag_off(f) + (n % self.inopb) * 128
        mode, nlink = struct.unpack_from('<HH', self.d, o)
        size, = struct.unpack_from('<Q', self.d, o + 8)
        mtime, = struct.unpack_from('<i', self.d, o + 24)
        db = struct.unpack_from('<12I', self.d, o + 40)
        ib = struct.unpack_from('<3I', self.d, o + 88)
        uid, gid = struct.unpack_from('<II', self.d, o + 112)
        return dict(mode=mode, nlink=nlink, size=size, mtime=mtime, db=db,
                    ib=ib, uid=uid, gid=gid)

    def blocks(self, ino):
        """liste des (fragment, nombre de fragments) des blocs de donnees"""
        size, out = ino['size'], []
        nblk = (size + self.bsize - 1) // self.bsize

        def ptrs(f):
            o = self.frag_off(f)
            return struct.unpack_from('<%dI' % self.nindir, self.d, o)
        lst = list(ino['db'])
        if nblk > 12 and ino['ib'][0]:
            lst += ptrs(ino['ib'][0])
        if nblk > 12 + self.nindir and ino['ib'][1]:
            for p in ptrs(ino['ib'][1]):
                lst += ptrs(p) if p else [0] * self.nindir
        for i in range(nblk):
            f = lst[i]
            left = size - i * self.bsize
            n = self.frag if left >= self.bsize else (left + self.fsize - 1) // self.fsize
            out.append((f, n, min(left, self.bsize)))
        return out

    def read(self, ino):
        r = bytearray()
        for f, n, ln in self.blocks(ino):
            if f == 0:
                r += bytes(ln)
            else:
                o = self.frag_off(f)
                r += self.d[o:o + ln]
        return bytes(r)

    def listdir(self, ino):
        data, out, p = self.read(ino), {}, 0
        while p + 8 <= len(data):
            n, rl, typ, nl = struct.unpack_from('<IHBB', data, p)
            if rl == 0:
                break
            if n:
                out[data[p + 8:p + 8 + nl].decode('latin-1')] = n
            p += rl
        return out

    def walk(self, n=2, prefix=''):
        """(chemin, numero d'inode, inode) pour tout l'arbre"""
        ino = self.inode(n)
        for name, c in sorted(self.listdir(ino).items()):
            if name in ('.', '..'):
                continue
            ci = self.inode(c)
            path = prefix + name
            yield path, c, ci
            if ci['mode'] & 0xF000 == 0x4000:
                yield from self.walk(c, path + '/')


def load(path, hd):
    data = open(path, 'rb').read()
    start = 0
    if hd:
        for i in range(4):
            typ = data[446 + 16 * i + 4]
            if typ in (0xA5, 0xA6, 0xA9):
                start = struct.unpack_from('<I', data, 446 + 16 * i + 8)[0]
    return Ufs(data, start)


def compare(img, tree, hd, extra):
    fs = load(img, hd)
    seen, bad = set(), []
    nfiles = 0
    for path, n, ino in fs.walk():
        seen.add(path)
        host = os.path.join(tree, path)
        if path in extra and not os.path.lexists(host):
            continue
        if not os.path.lexists(host):
            bad.append('en trop dans l\'image : ' + path)
            continue
        st = os.lstat(host)
        isdir = ino['mode'] & 0xF000 == 0x4000
        if isdir != os.path.isdir(host):
            bad.append('type different : ' + path)
            continue
        if (ino['mode'] & 0o7777) != (st.st_mode & 0o7777):
            bad.append('mode %o au lieu de %o : %s' % (ino['mode'] & 0o7777,
                                                     st.st_mode & 0o7777, path))
        if (ino['uid'], ino['gid']) != (st.st_uid, st.st_gid):
            bad.append('proprietaire %d:%d au lieu de %d:%d : %s' % (
                ino['uid'], ino['gid'], st.st_uid, st.st_gid, path))
        if not isdir:
            nfiles += 1
            if ino['size'] != st.st_size:
                bad.append('taille %d au lieu de %d : %s' % (ino['size'], st.st_size, path))
            elif fs.read(ino) != open(host, 'rb').read():
                bad.append('contenu different : ' + path)
    for dp, dn, fn in os.walk(tree):
        for x in dn + fn:
            rel = os.path.relpath(os.path.join(dp, x), tree)
            if rel not in seen:
                bad.append('absent de l\'image : ' + rel)
    return nfiles, bad


if __name__ == '__main__':
    args = [a for a in sys.argv[1:] if not a.startswith('--')]
    hd = '--hd' in sys.argv
    extra = []
    if '--extra' in sys.argv:
        extra = sys.argv[sys.argv.index('--extra') + 1:]
        args = [a for a in args if a not in extra]
    nfiles, bad = compare(args[0], args[1], hd, extra)
    for b in bad[:30]:
        print('ECART ' + b)
    print('%d fichier(s) compare(s), %d ecart(s)' % (nfiles, len(bad)))
    sys.exit(1 if bad else 0)
