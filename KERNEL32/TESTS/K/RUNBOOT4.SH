#!/bin/bash
# @author: Sylvain Maltais (support@gladir.com)
# @created: 2026
# @website(https://www.gladir.com/linux-0)
# @description: Amorce KERNEL32 par le chargeur BOOT/ (MBR + stage2) depuis
#   une partition ext3/ext4 : fabrique un disque (MKIMAGE.SH adapte : mke2fs
#   avec les options fournies), compile le noyau, amorce sous QEMU et verifie
#   que le chargeur a trouve /boot/linux0 (extents, htree, 64bit...) et que
#   le noyau monte la racine.
#     RUNBOOT4.SH [-b bloc] [-i inode] [-N entrees] [-o "options mke2fs"]
#   Exemple : RUNBOOT4.SH -o "-t ext4 -O ^metadata_csum"
HERE=$(cd "$(dirname "$0")" && pwd)
K32=$HERE/../..
LPC=${LPC:-/tmp/claude-0/work/k32/bin/lpc}
BS=1024; ISZ=256; NF=0; OPTS="-t ext4"
while getopts "b:i:N:o:" o; do
  case $o in b) BS=$OPTARG ;; i) ISZ=$OPTARG ;; N) NF=$OPTARG ;; o) OPTS=$OPTARG ;; *) exit 2 ;; esac
done
W=$(mktemp -d)
cp "$K32/KERNEL32.PAS" "$W/"
(cd "$W" && "$LPC" -3K -q KERNEL32.PAS) || exit 1
# MKIMAGE.SH avec la ligne mke2fs remplacee
sed -e 's#^mke2fs -q -F -t ext2 .*#mke2fs -q -F -b "$BS" -I "$INO" -m 0 -L LINUX0 '"$OPTS"' \\#' \
    -e 's#^  -O "\$FEAT" -E#  -E#' "$K32/TOOLS/MKIMAGE.SH" > "$W/mk.sh"
sed -i "s#^HERE=.*#HERE=$K32/TOOLS#" "$W/mk.sh"
mkdir -p "$W/root/etc"
bash "$W/mk.sh" -o "$W/d.img" -k "$W/KERNEL32" -r "$W/root" -s 64 -b "$BS" -i "$ISZ" \
  -N "$NF" > "$W/mk.log" 2>&1 || { cat "$W/mk.log"; exit 1; }
timeout 60 qemu-system-i386 -m 64 -drive "file=$W/d.img,format=raw,if=ide" \
  -serial "file:$W/out.txt" -display none -no-reboot &
QP=$!
for i in $(seq 1 40); do
  grep -q "KTEST: DONE\|Systeme arrete\|Oops\|panique" "$W/out.txt" 2>/dev/null && break
  grep -q "pid 1\|Lancement de\|racine" "$W/out.txt" 2>/dev/null && [ $i -gt 12 ] && break
  sleep 1
done
kill $QP 2>/dev/null; wait $QP 2>/dev/null
tr -d '\r' < "$W/out.txt" > "$W/o2.txt"
head -30 "$W/o2.txt"
echo "----"
e2fsck -fn "$W/d.img?offset=1048576" 2>&1 | tail -2
if grep -q "LINUX-0\|KERNEL32" "$W/o2.txt" && ! grep -q "Systeme arrete\|ERREUR" "$W/o2.txt"; then
  echo "RESULTAT : SUCCES"; rm -rf "$W"; exit 0
else echo "RESULTAT : ECHEC (traces dans $W)"; exit 1; fi
