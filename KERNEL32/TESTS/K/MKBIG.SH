#!/bin/bash
# @author: Sylvain Maltais (support@gladir.com)
# @created: 2026
# @website(https://www.gladir.com/linux-0)
# @description: Fabrique un disque de plus de 4 Go pour bigtest (fichiers
#   > 2 Go, partie 35) :
#     MKBIG.SH disque.img ext2 [taille_bloc] [Go]   (defaut 1024, 6 Go)
#     MKBIG.SH disque.img fat                        (FAT32 de 3 Go)
#   Disque creux (sparse) : MBR + partition 83h (ext2, avec un fichier de
#   remplissage de 2,2 Go pour que les allocations depassent 2^31 octets, un
#   fichier creux host.big de 3 Go avec marqueur a 2,5 Go) ou 0Bh (FAT32 avec
#   BIG.BIN de 2300 Mo et marqueurs). Marqueur BIGDISK-MARK dans le dernier
#   secteur du disque.
OUT=${1:?image}; KIND=${2:-ext2}; BS=${3:-1024}; GB=${4:-6}
W=$(mktemp -d)
rm -f "$OUT"
if [ "$KIND" = ext2 ]; then
  SZ=$((GB*1024*1024*1024))
  truncate -s $SZ "$OUT"
  mkdir -p "$W/root"
  python3 - "$W/root" <<'PY'
import sys
r=sys.argv[1]
with open(r+'/filler.bin','wb') as f:
    blk=b'\x55'*(1<<20)
    for i in range(2200): f.write(blk)
with open(r+'/host.big','wb') as f:
    f.seek(5*(1<<29)//1*1)   # 2,5 Go
    f.write(b'HOST-MARK-25')
    f.truncate(3*(1<<30))
PY
  FSB=$(( (SZ-1048576)/1024 ))
  if [ "$BIGT" = ext4 ]; then   # BIGT=ext4 : ext4 par defaut (extents, journal, 64bit...)
    mke2fs -q -F -t ext4 -b "$BS" -N 32768 \
      -E offset=1048576 -d "$W/root" "$OUT" $FSB >/dev/null 2>"$W/mke2fs.err" || { cat "$W/mke2fs.err"; rm -rf "$W"; exit 1; }
  else
    mke2fs -q -t ext2 -b "$BS" -I 128 -r 1 -N 32768 -O none,filetype,sparse_super,large_file \
      -E offset=1048576 -d "$W/root" "$OUT" $FSB >/dev/null 2>"$W/mke2fs.err" || { cat "$W/mke2fs.err"; rm -rf "$W"; exit 1; }
  fi
  PTYPE=0x83
else
  SZ=$((3*1024*1024*1024))
  truncate -s $SZ "$OUT"
  python3 - "$W/BIG.BIN" <<'PY'
import sys
n=2300*1024*1024
with open(sys.argv[1],'wb') as f:
    f.seek(100); f.write(b'FAT-MARK-A')
    f.seek(2100*1024*1024); f.write(b'FAT-MARK-B')
    f.seek(n-10); f.write(b'FAT-MARK-Z')
PY
  mkfs.vfat -F 32 -S 512 --offset 2048 "$OUT" $(( (SZ-1048576)/1024 )) >/dev/null || { rm -rf "$W"; exit 1; }
  export MTOOLS_SKIP_CHECK=1
  mcopy -i "$OUT@@1048576" "$W/BIG.BIN" ::BIG.BIN || { rm -rf "$W"; exit 1; }
  PTYPE=0x0b
fi
python3 - "$OUT" $PTYPE <<'PY'
import struct, sys
path=sys.argv[1]; pt=int(sys.argv[2],16)
img=open(path,'r+b')
img.seek(0,2); size=img.tell()
sectors=size//512-2048
ent=struct.pack('<B3sB3sII',0x80,b'\0\0\0',pt,b'\0\0\0',2048,sectors)
img.seek(446); img.write(ent)
img.seek(510); img.write(b'\x55\xaa')
img.seek(size-512); img.write(b'BIGDISK-MARK')
PY
rm -rf "$W"
