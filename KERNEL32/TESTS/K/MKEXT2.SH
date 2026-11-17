#!/bin/bash
# @author: Sylvain Maltais (support@gladir.com)
# @created: 2026
# @website(https://www.gladir.com/linux-0)
# @description: Fabrique un disque de test ext2 pour ext2test (TESTS/K) :
#     MKEXT2.SH disque.img [Mo] [taille_bloc] [taille_inode] [options mke2fs...]
#   MBR + partition 1 (type 83h, active, debut secteur 2048) formatee par
#   mke2fs (ext2, revision 1, sparse_super, filetype) et remplie du contenu
#   attendu par ext2test (hello.txt, big.bin de motif i*7+(i>>8), dir1 de 100
#   fichiers, liens, repertoire vide...).
OUT=${1:?image}; MB=${2:-16}; BS=${3:-1024}; ISZ=${4:-128}
shift 4 2>/dev/null
W=$(mktemp -d)
R=$W/root
mkdir -p "$R/dir1/sub" "$R/etc" "$R/emptydir"
echo "hello from ext2" > "$R/hello.txt"
python3 -c "
import sys
sys.stdout.buffer.write(bytes(((i*7+(i>>8))&255) for i in range(300000)))" > "$R/big.bin"
ln -s hello.txt "$R/fastlink"
ln -s "$(printf 'x%.0s' $(seq 1 100))/target" "$R/slowlink"
for i in $(seq 1 100); do echo "file $i" > "$R/dir1/f$i.txt"; done
ln "$R/hello.txt" "$R/hard.txt"
PART=$((MB-1))
rm -f "$OUT"
dd if=/dev/zero of="$OUT" bs=1M count=$MB status=none
dd if=/dev/zero of="$W/fs.img" bs=1M count=$PART status=none
mke2fs -q -t ext2 -b "$BS" -I "$ISZ" -r 1 -O none,filetype,sparse_super \
  -d "$R" "$@" "$W/fs.img" >/dev/null || { rm -rf "$W"; exit 1; }
dd if="$W/fs.img" of="$OUT" bs=512 seek=2048 conv=notrunc status=none
python3 - "$OUT" $((PART*2048)) <<'PY'
import struct, sys
img = open(sys.argv[1], 'r+b')
ent = struct.pack('<B3sB3sII', 0x80, b'\0\0\0', 0x83, b'\0\0\0', 2048, int(sys.argv[2]))
img.seek(446); img.write(ent)
img.seek(510); img.write(b'\x55\xaa')
PY
rm -rf "$W"
