#!/bin/bash
# @author: Sylvain Maltais (support@gladir.com)
# @created: 2026
# @description: Banc d'essai minix (v1/v2/v3), cramfs, romfs (partie 38) :
#   images fabriquees par MKROFS.PY et mkfs.cramfs, placees dans un initramfs
#   et montees par /dev/loopN (rotest.c). fsck.minix verifie les images minix.
#     RUNRO.SH [-t secondes]
HERE=$(cd "$(dirname "$0")" && pwd)
K32=$HERE/../..
LPC=${LPC:-/tmp/claude-0/work/k32/bin/lpc}
TMO=90
while getopts "t:" o; do case $o in t) TMO=$OPTARG ;; *) exit 2 ;; esac; done
W=$(mktemp -d)
gcc -m32 -static -nostdlib -ffreestanding -fno-pic -fno-pie -no-pie -Os -fno-stack-protector \
    -fno-asynchronous-unwind-tables -fno-builtin -Wl,--build-id=none -Wl,-z,noseparate-code \
    -Wl,-z,norelro -o "$W/init" "$HERE/rotest.c" 2>/dev/null || exit 1
# arbre source
S=$W/src; mkdir -p "$S/dir1/sub"
echo "hello from rofs" > "$S/hello.txt"
echo "deep" > "$S/dir1/sub/deep.txt"
: > "$S/empty"
python3 - "$S" <<'PY'
import sys,os
s=sys.argv[1]
open(s+'/big.bin','wb').write(bytes(((i*7+(i>>8))&255) for i in range(300000)))
x=12345; r=bytearray()
for i in range(20000):
    x=(x*1103515245+12345)&0xffffffff; r.append((x>>16)&255)
open(s+'/rand.bin','wb').write(bytes(r))
open(s+'/zeros.bin','wb').write(bytes(10000))
for i in range(1,41): open(s+'/dir1/f%d.txt'%i,'w').write('file %d\n'%i)
open(s+'/tool','w').write('#!/bin/sh\n'); os.chmod(s+'/tool',0o755)
os.symlink('hello.txt',s+'/lnk')
PY
chown -R 1000:100 "$S" 2>/dev/null
mkdir -p "$W/ird"
cp "$W/init" "$W/ird/init"
RC=0
mkfs.cramfs "$S" "$W/ird/cram.img" >/dev/null 2>&1 || { echo "mkfs.cramfs echec"; RC=1; }
for k in minix1 minix1l minix2 minix2l minix3; do
  python3 "$HERE/MKROFS.PY" $k "$S" "$W/ird/$k.img" || { echo "MKROFS $k echec"; RC=1; }
  FSCK=$(fsck.minix -f "$W/ird/$k.img" 2>&1); echo "fsck.minix $k : $(echo "$FSCK" | grep -c -i "error\|bad\|wrong\|mismatch\|counted") problemes"
  echo "$FSCK" | grep -qi 'error\|bad\|wrong' && { echo "$FSCK" | head -5; RC=1; }
done
python3 "$HERE/MKROFS.PY" romfs "$S" "$W/ird/rom.img" || { echo "MKROFS romfs echec"; RC=1; }
python3 - "$W/ird" "$W/ird.cpio" <<'PY'
import sys,os,struct
sys.path.insert(0,os.path.dirname(os.path.abspath(sys.argv[0])))
d,out=sys.argv[1:3]
b=bytearray(); ino=[0]
def add(name,mode,data):
    ino[0]+=1; nm=name.encode()+b'\0'
    h=b'070701'+b''.join(b'%08X'%v for v in (ino[0],mode,0,0,1,0,len(data),3,1,0,0,len(nm),0))
    b.extend(h+nm)
    while len(b)%4: b.append(0)
    b.extend(data)
    while len(b)%4: b.append(0)
for n in sorted(os.listdir(d)):
    p=os.path.join(d,n)
    add(n,0o100755,open(p,'rb').read())
add('TRAILER!!!',0,b'')
open(out,'wb').write(bytes(b))
PY
[ $RC = 0 ] || { echo "RESULTAT : ECHEC (preparation, $W)"; exit 1; }
cp "$K32/KERNEL32.PAS" "$W/"
(cd "$W" && "$LPC" -3K -q KERNEL32.PAS) || exit 1
LIST=cramfs:/cram.img,minix:/minix1.img,minix:/minix1l.img,minix:/minix2.img,minix:/minix2l.img,minix:/minix3.img,romfs:/rom.img
rm -f "$W/out.txt"
timeout "$TMO" qemu-system-i386 -kernel "$W/KERNEL32" -initrd "$W/ird.cpio" -serial "file:$W/out.txt" \
  -display none -m 96 -no-reboot -append "console=ttyS0 rofs=$LIST" 2>/dev/null &
QP=$!
for i in $(seq 1 "$TMO"); do
  grep -q "KTEST: rofs DONE" "$W/out.txt" 2>/dev/null && break
  kill -0 $QP 2>/dev/null || break
  sleep 1
done
kill $QP 2>/dev/null; wait $QP 2>/dev/null
tr -d '\r' < "$W/out.txt" > "$W/o2.txt"
grep "KTEST: ro" "$W/o2.txt" | grep -v ' OK$'
echo "verifications OK : $(grep -c 'KTEST: ro.*OK$' "$W/o2.txt")"
BAD=$(grep "KTEST:.* FAIL$\|Oops\|panique" "$W/o2.txt")
if grep -q "KTEST: rofs DONE" "$W/o2.txt" && [ -z "$BAD" ]; then echo "RESULTAT : SUCCES"; rm -rf "$W"; exit 0
else echo "$BAD" | head; echo "RESULTAT : ECHEC (traces dans $W)"; exit 1; fi
