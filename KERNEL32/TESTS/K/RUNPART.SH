#!/bin/bash
# @author: Sylvain Maltais (support@gladir.com)
# @created: 2026
# @website(https://www.gladir.com/linux-0)
# @description: Partitionnement cote noyau (partie 39) : disque ext2 (MKEXT2.SH) puis
#   disque GPT (MBR de protection + en-tete + entree, fabriques par python) :
#   BLKRRPART, BLKPG, HDIO_GETGEO, ecriture du MBR, /dev, /proc/partitions, /sys ;
#   e2fsck de l'image a la fin (le noyau n'a rien abime).
#     RUNPART.SH [-n]
HERE=$(cd "$(dirname "$0")" && pwd)
K32=$HERE/../..
LPC=${LPC:-/tmp/claude-0/work/k32/bin/lpc}
GEN=1; [ "$1" = -n ] && GEN=0
W=$(mktemp -d)
if [ $GEN = 1 ]; then
  "$HERE/build.sh" "$W/u" >/dev/null || exit 1
  python3 "$HERE/MKEMBED.PY" "$W/u" "$K32/KERNEL32.PAS" >/dev/null || exit 1
fi
cp "$K32/KERNEL32.PAS" "$W/"
(cd "$W" && "$LPC" -3K -q KERNEL32.PAS) || exit 1
RC=0
run() {  # nom image [mots de ligne de commande]
  N=$1; IMG=$2; shift 2
  rm -f "$W/out.txt"
  timeout 120 qemu-system-i386 -kernel "$W/KERNEL32" -serial "file:$W/out.txt" -display none \
    -m 64 -no-reboot -append "console=ttyS0 k32power $*" -drive "file=$IMG,format=raw,if=ide,index=0" $QX 2>/dev/null
  tr -d '\r' < "$W/out.txt" > "$W/o_$N.txt"
  grep -a "KTEST: part.* FAIL\|Oops\|panique" "$W/o_$N.txt"
  echo "$N : tests part OK : $(grep -ac 'KTEST: part.* OK$' "$W/o_$N.txt")"
  grep -q "KTEST: part DONE" "$W/o_$N.txt" || { echo "$N : part DONE absent"; RC=1; }
  grep -q "KTEST: part.* FAIL" "$W/o_$N.txt" && RC=1
}
"$HERE/MKEXT2.SH" "$W/d.img" 8 1024 128 || exit 1
run mbr "$W/d.img"
e2fsck -fn "$W/d.img?offset=1048576" > "$W/fsck.txt" 2>&1 || { echo "e2fsck : ECHEC"; RC=1; }
# GPT : MBR de protection + en-tete + 1 entree pointant sur la meme partition
python3 - "$W/d.img" "$W/g.img" <<'P'
import sys, struct
src = open(sys.argv[1], 'rb').read()
fs = src[2048 * 512:]
total = 2048 + len(fs) // 512 + 34
img = bytearray(total * 512)
img[2048 * 512:2048 * 512 + len(fs)] = fs
mbr = bytearray(512)
mbr[446 + 4] = 0xEE
struct.pack_into('<II', mbr, 446 + 8, 1, min(total - 1, 0xFFFFFFFF))
mbr[510:512] = b'\x55\xAA'
img[0:512] = mbr
n = len(fs) // 512
ent = bytearray(128)
ent[0:16] = bytes(range(1, 17))          # type GUID (non nul)
ent[16:32] = bytes(range(17, 33))
struct.pack_into('<QQQ', ent, 32, 2048, 2048 + n - 1, 0)
img[2 * 512:2 * 512 + 128] = ent
hdr = bytearray(512)
hdr[0:8] = b'EFI PART'
struct.pack_into('<IIIIQQQQ', hdr, 8, 0x10000, 92, 0, 0, 1, total - 1, 34, total - 34)
hdr[56:72] = bytes(16)
struct.pack_into('<QIII', hdr, 72, 2, 128, 128, 0)
img[512:1024] = hdr
open(sys.argv[2], 'wb').write(img)
P
run gpt "$W/g.img" gpt
if [ $RC = 0 ]; then echo "RESULTAT : SUCCES"; rm -rf "$W"; exit 0
else echo "RESULTAT : ECHEC (traces dans $W)"; exit 1; fi
