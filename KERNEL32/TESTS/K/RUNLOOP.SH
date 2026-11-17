#!/bin/bash
# @author: Sylvain Maltais (support@gladir.com)
# @created: 2026
# @description: Banc d'essai loop (partie 38) : disque ext2 contenant deux
#   images ext2 (/inner.img, /inner2.img avec 8192 octets de tete), monte
#   par /dev/loopN (loopmnt), puis e2fsck -fn du disque et des deux images.
#     RUNLOOP.SH [-n] [-t secondes]
HERE=$(cd "$(dirname "$0")" && pwd)
K32=$HERE/../..
LPC=${LPC:-/tmp/claude-0/work/k32/bin/lpc}
GEN=1; TMO=240
while getopts "nt:" o; do
  case $o in n) GEN=0 ;; t) TMO=$OPTARG ;; *) exit 2 ;; esac
done
W=$(mktemp -d)
if [ $GEN = 1 ]; then
  "$HERE/build.sh" "$W/u" >/dev/null || exit 1
  python3 "$HERE/MKEMBED.PY" "$W/u" "$K32/KERNEL32.PAS" || exit 1
fi
cp "$K32/KERNEL32.PAS" "$W/"
(cd "$W" && "$LPC" -3K -q KERNEL32.PAS) || exit 1
# image interne
mkdir -p "$W/in"
echo "hello from inner" > "$W/in/hello.txt"
python3 -c "
import sys
sys.stdout.buffer.write(bytes(((i*7)&255) for i in range(4095)))" > "$W/in/big.bin"
dd if=/dev/zero of="$W/inner.img" bs=1M count=4 status=none
mke2fs -q -t ext2 -b 1024 -I 128 -r 1 -O none,filetype,sparse_super -d "$W/in" "$W/inner.img" >/dev/null || exit 1
dd if=/dev/zero of="$W/inner2.img" bs=1M count=4 status=none
mke2fs -q -t ext2 -b 1024 -I 128 -r 1 -O none,filetype,sparse_super -d "$W/in" "$W/inner2.img" 4000 >/dev/null || exit 1
{ head -c 8192 /dev/zero; cat "$W/inner2.img"; } > "$W/inner2b.img"
mkdir -p "$W/outer"
cp "$W/inner.img" "$W/outer/inner.img"; cp "$W/inner2b.img" "$W/outer/inner2.img"
dd if=/dev/zero of="$W/d.img" bs=1M count=24 status=none
dd if=/dev/zero of="$W/fs.img" bs=1M count=23 status=none
mke2fs -q -t ext2 -b 1024 -I 128 -r 1 -O none,filetype,sparse_super -d "$W/outer" "$W/fs.img" >/dev/null || exit 1
python3 - "$W/d.img" <<'PY'
import sys,struct
f=open(sys.argv[1],'r+b')
e=bytearray(16); e[0]=0x80; e[4]=0x83
struct.pack_into('<II',e,8,2048,23*2048)
f.seek(446); f.write(e); f.seek(510); f.write(b'\x55\xaa')
PY
dd if="$W/fs.img" of="$W/d.img" bs=512 seek=2048 conv=notrunc status=none
timeout "$TMO" qemu-system-i386 -kernel "$W/KERNEL32" -serial "file:$W/out.txt" \
  -display none -m 64 -no-reboot -append "console=ttyS0 init=/bin/loopmnt $KARGS" \
  -drive "file=$W/d.img,format=raw,if=ide" 2>/dev/null
tr -d '\r' < "$W/out.txt" > "$W/o2.txt"; mv "$W/o2.txt" "$W/out.txt"
grep "KTEST: loopmnt\|KPROG: /bin/loopmnt\|Oops\|panique" "$W/out.txt"
echo "----"
grep -c "KTEST: loopmnt.* OK$" "$W/out.txt" | sed 's/^/tests loopmnt OK : /'
FAILS=$(grep "KTEST:.* FAIL$" "$W/out.txt")
[ -n "$FAILS" ] && echo "$FAILS"
echo "== e2fsck"
RC=0
e2fsck -fn "$W/d.img?offset=1048576" > "$W/fsck.txt" 2>&1 || RC=1
debugfs -R "dump /inner.img $W/o_inner.img" "$W/d.img?offset=1048576" >/dev/null 2>&1
debugfs -R "dump /inner2.img $W/o_inner2.img" "$W/d.img?offset=1048576" >/dev/null 2>&1
e2fsck -fn "$W/o_inner.img" >> "$W/fsck.txt" 2>&1 || RC=1
e2fsck -fn "$W/o_inner2.img?offset=8192" >> "$W/fsck.txt" 2>&1 || RC=1
tail -12 "$W/fsck.txt"
# le fichier ecrit a travers le loop est dans l'image
debugfs -R "cat /new.txt" "$W/o_inner.img" 2>/dev/null | grep -q "written through loop" || { echo "new.txt absent de l'image"; RC=1; }
if [ $RC = 0 ] && grep -q "KTEST: loopmnt DONE" "$W/out.txt" && [ -z "$FAILS" ]; then
  echo "RESULTAT : SUCCES"; rm -rf "$W"; exit 0
else echo "RESULTAT : ECHEC (traces dans $W)"; exit 1; fi
