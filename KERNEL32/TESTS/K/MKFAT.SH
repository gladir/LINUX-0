#!/bin/bash
# @author: Sylvain Maltais (support@gladir.com)
# @created: 2026
# @website(https://www.gladir.com/linux-0)
# @description: Fabrique un disque FAT de test pour fattest (TESTS/K) :
#     MKFAT.SH disque.img 12|16|32|fd   (fd : disquette 1,44 Mo, FAT12)
#   Image brute (sans MBR) formatee par mkfs.vfat puis remplie par mtools
#   (hello.txt, nom long, big.bin de motif i*7+(i>>8), dir1 de 40 fichiers...).
OUT=${1:?image}; TYP=${2:-16}
case $TYP in
  12) MB=8;  OPT="-F 12 -s 8" ;;
  16) MB=20; OPT="-F 16 -s 2" ;;
  32) MB=40; OPT="-F 32 -s 1" ;;
  fd) MB=0; OPT="-F 12" ;;
  *) echo "type FAT inconnu" >&2; exit 2 ;;
esac
W=$(mktemp -d)
rm -f "$OUT"
if [ "$TYP" = fd ]; then
  dd if=/dev/zero of="$OUT" bs=1024 count=1440 status=none
  mkfs.vfat $OPT -n K32FAT "$OUT" 1440 >/dev/null || { rm -rf "$W"; exit 1; }
else
  dd if=/dev/zero of="$OUT" bs=1M count=$MB status=none
  mkfs.vfat $OPT -S 512 -n K32FAT "$OUT" >/dev/null || { rm -rf "$W"; exit 1; }
fi
export MTOOLS_SKIP_CHECK=1
I="-i $OUT"
echo "hello from fat" > "$W/hello.txt"
echo "long name file" > "$W/Long File Name Example.txt"
python3 -c "
import sys
sys.stdout.buffer.write(bytes(((i*7+(i>>8))&255) for i in range(300000)))" > "$W/big.bin"
mcopy $I "$W/hello.txt" ::hello.txt
mcopy $I "$W/Long File Name Example.txt" "::Long File Name Example.txt"
mcopy $I "$W/big.bin" ::big.bin
mmd $I ::dir1 ::dir1/sub ::emptydir
for i in $(seq 1 40); do echo "file $i" > "$W/f.txt"; mcopy $I "$W/f.txt" ::dir1/f$i.txt; done
echo "deep" > "$W/deep.txt"; mcopy $I "$W/deep.txt" ::dir1/sub/deep.txt
rm -rf "$W"
