#!/usr/bin/env python3
# @author: Sylvain Maltais (support@gladir.com)
# @created: 2026
# @website(https://www.gladir.com/linux-0)
# @abstract(Target: Python 3)
# @description: Enveloppe une image plate en ELF32 i386 (ET_EXEC) pour tester
#   le chargeur de KERNEL32. Segment principal a --base (decalage de fichier
#   1000h). Options : --entry, --bss N (memsz du segment principal),
#   --zero ADDR:LEN (segment sans donnees : p_filesz=0, p_memsz=LEN),
#   --far OFF:ADDR:LEN (segment de LEN octets motif (i*7+3)&255 place au
#   decalage OFF du fichier, fichier creux), --high (p_vaddr = C0000000h +
#   p_paddr, point d'entree virtuel, comme le noyau mappe en haute memoire).
import sys, struct, argparse

def num(s):
    return int(s, 0)

ap = argparse.ArgumentParser()
ap.add_argument('flat')
ap.add_argument('out')
ap.add_argument('--base', type=num, default=0x100000)
ap.add_argument('--entry', type=num, default=None)
ap.add_argument('--bss', type=num, default=0)
ap.add_argument('--zero', action='append', default=[])
ap.add_argument('--far', action='append', default=[])
ap.add_argument('--high', action='store_true')
a = ap.parse_args()

data = open(a.flat, 'rb').read()
entry = a.entry if a.entry is not None else a.base + 12
segs = []   # (offset, paddr, filesz, memsz, payload)
segs.append((0x1000, a.base, len(data), len(data) + a.bss, data))
for z in a.zero:
    addr, ln = [num(x) for x in z.split(':')]
    segs.append((0x1000 + len(data), addr, 0, ln, b''))
for f in a.far:
    off, addr, ln = [num(x) for x in f.split(':')]
    pat = bytes(((i * 7 + 3) & 255) for i in range(ln))
    segs.append((off, addr, ln, ln, pat))
voff = 0xC0000000 if a.high else 0
phoff = 52
ehdr = b'\x7fELF' + bytes([1, 1, 1, 0]) + bytes(8)
ehdr += struct.pack('<HHIIIIIHHHHHH', 2, 3, 1, entry + voff, phoff, 0, 0, 52,
                    32, len(segs), 40, 0, 0)
phs = b''
for (off, pa, fs, ms, _) in segs:
    phs += struct.pack('<IIIIIIII', 1, off, pa + voff, pa, fs, ms, 7, 0x1000)
with open(a.out, 'wb') as o:
    o.write(ehdr + phs)
    for (off, pa, fs, ms, p) in segs:
        o.seek(off)
        o.write(p)
