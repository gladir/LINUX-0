#!/usr/bin/env python3
# Cree un disque de test (8 Mo) : MBR avec 2 partitions (type 83h) dont le debut
# contient 'PARTITION-ONE...' / 'PARTITION-TWO...' (utilise par blktest).
# usage : MKDISK.PY disque.img
import struct, sys
img = bytearray(8 * 1024 * 1024)
def part(i, start, size):
    img[446 + 16 * i:446 + 16 * i + 16] = struct.pack('<B3sB3sII', 0x80 if i == 0 else 0, b'\0\0\0', 0x83, b'\0\0\0', start, size)
part(0, 2048, 4096); part(1, 8192, 4096)
img[510] = 0x55; img[511] = 0xAA
img[2048 * 512:2048 * 512 + 16] = b'PARTITION-ONE...'
img[8192 * 512:8192 * 512 + 16] = b'PARTITION-TWO...'
open(sys.argv[1], 'wb').write(img)
