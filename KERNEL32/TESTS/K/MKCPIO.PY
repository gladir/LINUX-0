#!/usr/bin/env python3
# MKCPIO.PY : fabrique des archives cpio newc pour l'essai de l'initramfs
# (partie 38) : MKCPIO.PY init.elf out_prefix  -> out_prefix.cpio (brut),
# out_prefix.cpio.gz, out_prefix.a.cpio / out_prefix.b.cpio.gz (deux modules),
# out_prefix.cat.gz (gzip + cpio brut concatenes)
import sys, gzip, struct

class Cpio:
    def __init__(self): self.b = bytearray(); self.ino = 100
    def add(self, name, mode, data=b'', uid=0, gid=0, mtime=1234567890, nlink=1,
            rdev=(0, 0), ino=None):
        if ino is None:
            self.ino += 1; ino = self.ino
        nm = name.encode() + b'\0'
        h = b'070701' + b''.join(b'%08X' % v for v in (
            ino, mode, uid, gid, nlink, mtime, len(data), 3, 1, rdev[0], rdev[1],
            len(nm), 0))
        self.b += h + nm
        while len(self.b) % 4: self.b.append(0)
        self.b += data
        while len(self.b) % 4: self.b.append(0)
    def done(self, pad=512):
        self.add('TRAILER!!!', 0)
        while len(self.b) % pad: self.b.append(0)
        return bytes(self.b)

S_DIR, S_REG, S_LNK, S_CHR, S_FIFO = 0o040000, 0o100000, 0o120000, 0o020000, 0o010000
def pattern(n): return bytes(((i * 7 + (i >> 8)) & 255) for i in range(n))

init = open(sys.argv[1], 'rb').read()
out = sys.argv[2]
def part_a():
    c = Cpio()
    c.add('.', S_DIR | 0o755)
    c.add('init', S_REG | 0o755, init)
    c.add('etc', S_DIR | 0o755)
    c.add('etc/hello', S_REG | 0o644, b'hello initramfs\n')
    c.add('etc/hl1', S_REG | 0o644, b'', nlink=2, ino=777)
    c.add('etc/hl2', S_REG | 0o644, b'shared by two names\n', nlink=2, ino=777)
    c.add('lnk', S_LNK | 0o777, b'etc/hello')
    c.add('dir', S_DIR | 0o700, uid=1000, gid=100)
    c.add('dir/sub/deep.txt', S_REG | 0o600, b'deep\n', uid=1000, gid=100)   # parent absent : cree
    c.add('big.bin', S_REG | 0o644, pattern(300000))
    c.add('emptydir', S_DIR | 0o755)
    c.add('suid', S_REG | 0o4755, b'x')
    c.add('mynull', S_CHR | 0o666, rdev=(1, 3))
    c.add('myfifo', S_FIFO | 0o600)
    c.add('./dot/prefixed', S_REG | 0o644, b'dotslash\n')
    c.add('empty.txt', S_REG | 0o644, b'')
    return c
def part_b():
    c = Cpio()
    c.add('etc', S_DIR | 0o755)
    c.add('etc/second', S_REG | 0o644, b'from module b\n')
    c.add('etc/hello', S_REG | 0o644, b'hello initramfs\n')
    return c
a = part_a().done(); open(out + '.cpio', 'wb').write(a)
open(out + '.cpio.gz', 'wb').write(gzip.compress(a, 9))
# deux modules : a (sans fichiers de b) + b
open(out + '.a.cpio', 'wb').write(a)
open(out + '.b.cpio.gz', 'wb').write(gzip.compress(part_b().done(), 6))
# concatenation : gzip(a) puis cpio brut de b
open(out + '.cat.gz', 'wb').write(gzip.compress(a, 6) + part_b().done())
