#!/bin/sh
# @author: Sylvain Maltais (support@gladir.com)
# @created: 2026
# @website(https://www.gladir.com/linux-0)
# @description: compare USR/E2FSCK.PAS (e2fsck-lite) a e2fsck -fn de l'hote sur
#   des images saines (ext2 1 Ko et 4 Ko, ext3) et corrompues par debugfs :
#   sortie et code de retour identiques. Usage : e2fsckcmp.sh chemin/E2FSCK
BIN=$(cd "$(dirname "$1")" && pwd)/$(basename "$1")
W=${W:-/tmp/linux0-e2fsck}; mkdir -p "$W/tree/d1/d2"; cd "$W" || exit 1
cp "$BIN" e2fsck_lite
seq 1 3000 > tree/big.txt; echo hi > tree/d1/small
ln -f tree/d1/small tree/d1/hard; ln -sf small tree/d1/sym
head -c 300000 /dev/urandom > tree/d1/d2/rand
for i in 1 2 3 4 5 6 7 8 9 10; do echo $i > tree/d1/f$i; done
head -c 5000000 /dev/zero | tr '\0' 'x' > tree/dense
for bs in 1024 4096; do
  mke2fs -q -F -t ext2 -b $bs -d tree img$bs.img 16M >/dev/null 2>&1
done
n=0; bad=0
t() { # base commande debugfs
  n=$((n+1)); cp $1 t.img
  [ -n "$2" ] && debugfs -w -R "$2" t.img >/dev/null 2>&1
  e2fsck -fn t.img > real.txt 2>&1; r1=$?
  ./e2fsck_lite -fn t.img > mine.txt 2>&1; r2=$?
  if [ $r1 != $r2 ] || ! diff -q mine.txt real.txt >/dev/null; then
    bad=$((bad+1)); echo "### DIFF [$1] $2 (rc real=$r1 mine=$r2)"
    diff mine.txt real.txt | head -${LINES_MAX:-8}
  fi
}
for b in img1024.img img4096.img; do
t $b ""
t $b "set_inode_field /d1/small links_count 5"
t $b "freeb 3000"
t $b "ssv free_blocks_count 5"
t $b "set_inode_field /big.txt links_count 0"
t $b "set_inode_field /d1/f1 mode 0"
t $b "unlink /d1/f2"
t $b "set_bg_field 0 free_inodes_count 3"
t $b "set_bg_field 0 free_blocks_count 7"
t $b "freei <20>"
t $b "seti <40>"
t $b "setb 5000"
t $b "clri /d1/f3"
t $b "set_inode_field /d1/small blocks 2000"
done
echo "cas=$n diff=$bad"
