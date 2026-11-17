#!/usr/bin/env python3
# @author: Sylvain Maltais (support@gladir.com)
# @created: 2026
# @website(https://www.gladir.com/linux-0)
# @abstract(Target: Python 3)
# @description: Lecteur ext2 independant (sans e2fsprogs) pour verifier les
#   images de KERNEL32 : superbloc, parcours de chemins, lecture de fichiers,
#   et couverture des indirections (directs, simple, double, triple) exercees
#   par un fichier. Meme sous-ensemble que le chargeur (pas d'extents).
#     E2CHECK.PY IMAGE [--start SECTEUR] [--cat CHEMIN] [--ls CHEMIN]
#                      [--compare CHEMIN FICHIER_HOTE] [--map CHEMIN]
import sys, struct, argparse, hashlib


class Ext2:
    def __init__(self, path, start=2048):
        self.f = open(path, 'rb')
        self.base = start * 512
        sb = self.rd(1024, 1024)
        (self.inodes, self.blocks) = struct.unpack_from('<II', sb, 0)
        self.first_data = struct.unpack_from('<I', sb, 20)[0]
        self.bs = 1024 << struct.unpack_from('<I', sb, 24)[0]
        self.bpg, self.fpg, self.ipg = struct.unpack_from('<III', sb, 32)
        self.magic = struct.unpack_from('<H', sb, 56)[0]
        self.rev = struct.unpack_from('<I', sb, 76)[0]
        self.isz = struct.unpack_from('<H', sb, 88)[0] if self.rev else 128
        self.incompat = struct.unpack_from('<I', sb, 96)[0] if self.rev else 0
        if self.magic != 0xEF53:
            raise SystemExit('pas de superbloc ext2')
        self.ppb = self.bs // 4
        self.stat = {'direct': 0, 'single': 0, 'double': 0, 'triple': 0}

    def rd(self, off, n):
        self.f.seek(self.base + off)
        return self.f.read(n)

    def block(self, n):
        return b'\0' * self.bs if n == 0 else self.rd(n * self.bs, self.bs)

    def inode(self, n):
        g, i = divmod(n - 1, self.ipg)
        gd = self.rd((self.first_data + 1) * self.bs + g * 32, 32)
        tbl = struct.unpack_from('<I', gd, 8)[0]
        raw = self.rd(tbl * self.bs + i * self.isz, 128)
        d = {}
        d['mode'], = struct.unpack_from('<H', raw, 0)
        d['size'], = struct.unpack_from('<I', raw, 4)
        d['flags'], = struct.unpack_from('<I', raw, 32)
        d['blocks'] = struct.unpack_from('<15I', raw, 40)
        d['raw'] = raw
        return d

    def bmap(self, ino, k):
        b = ino['blocks']
        if k < 12:
            self.stat['direct'] += 1
            return b[k]
        k -= 12
        p = self.ppb

        def ind(t, i):
            if t == 0:
                return 0
            return struct.unpack_from('<I', self.block(t), i * 4)[0]
        if k < p:
            self.stat['single'] += 1
            return ind(b[12], k)
        k -= p
        if k < p * p:
            self.stat['double'] += 1
            return ind(ind(b[13], k // p), k % p)
        k -= p * p
        self.stat['triple'] += 1
        return ind(ind(ind(b[14], k // (p * p)), (k // p) % p), k % p)

    def read(self, ino):
        out = bytearray()
        n = (ino['size'] + self.bs - 1) // self.bs
        for k in range(n):
            out += self.block(self.bmap(ino, k))
        return bytes(out[:ino['size']])

    def readdir(self, ino):
        data = self.read(ino)
        p = 0
        res = []
        while p + 8 <= len(data):
            i, rl, nl, ft = struct.unpack_from('<IHBB', data, p)
            if rl < 8:
                break
            if i:
                res.append((data[p + 8:p + 8 + nl].decode('latin-1'), i, ft))
            p += rl
        return res

    def lookup(self, path, depth=0):
        cur = 2
        parts = [x for x in path.split('/') if x]
        while parts:
            name = parts.pop(0)
            ino = self.inode(cur)
            ent = {n: i for n, i, _ in self.readdir(ino)}
            if name not in ent:
                raise SystemExit('introuvable : ' + path)
            nxt = self.inode(ent[name])
            if (nxt['mode'] & 0xF000) == 0xA000 and depth < 8:
                tgt = (struct.pack('<15I', *nxt['blocks'])[:nxt['size']]
                       if nxt['size'] < 60 else self.read(nxt)).decode()
                if tgt.startswith('/'):
                    cur = 2
                parts = [x for x in tgt.split('/') if x] + parts
                depth += 1
                continue
            cur = ent[name]
        return cur


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('image')
    ap.add_argument('--start', type=int, default=2048)
    ap.add_argument('--cat')
    ap.add_argument('--ls')
    ap.add_argument('--map')
    ap.add_argument('--compare', nargs=2, metavar=('CHEMIN', 'FICHIER'))
    a = ap.parse_args()
    fs = Ext2(a.image, a.start)
    print('ext2 : blocs de %d, inodes de %d, revision %d, incompat %#x, '
          '%d blocs' % (fs.bs, fs.isz, fs.rev, fs.incompat, fs.blocks))
    if a.ls:
        for n, i, t in fs.readdir(fs.inode(fs.lookup(a.ls))):
            print('%8d %s' % (i, n))
    if a.cat:
        sys.stdout.buffer.write(fs.read(fs.inode(fs.lookup(a.cat))))
    if a.map:
        ino = fs.inode(fs.lookup(a.map))
        fs.read(ino)
        print('blocs : %s' % fs.stat)
    if a.compare:
        ino = fs.inode(fs.lookup(a.compare[0]))
        got = fs.read(ino)
        ref = open(a.compare[1], 'rb').read()
        ok = got == ref
        print('%s : %s (%d octets, sha1 %s) ; blocs lus : %s' % (
            a.compare[0], 'IDENTIQUE' if ok else 'DIFFERENT', len(got),
            hashlib.sha1(got).hexdigest()[:12], fs.stat))
        sys.exit(0 if ok else 1)


if __name__ == '__main__':
    main()
