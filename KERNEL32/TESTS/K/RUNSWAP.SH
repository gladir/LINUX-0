#!/bin/bash
# @author: Sylvain Maltais (support@gladir.com)
# @created: 2026
# @website(https://www.gladir.com/linux-0)
# @description: Banc d'essai du swap : fabrique un disque de 32 Mo prepare par
#   mkswap, lance KERNEL32 avec 24 Mo de RAM et swap=/dev/hdb, laisse tourner
#   /bin/swaptest (remplit plus de memoire que la RAM, verifie les donnees
#   apres page-out/page-in, fork, swapoff, swapon) puis la suite embarquee.
#     RUNSWAP.SH [-n]
HERE=$(cd "$(dirname "$0")" && pwd)
K32=$HERE/../..
LPC=${LPC:-/tmp/claude-0/work/k32/bin/lpc}
GEN=1; MODE=dev; BS=1024
while getopts "nfb:" o; do
  case $o in n) GEN=0 ;; f) MODE=file ;; b) BS=$OPTARG ;; *) exit 2 ;; esac
done
W=$(mktemp -d)
if [ $GEN = 1 ]; then
  "$HERE/build.sh" "$W/u" >/dev/null || exit 1
  python3 "$HERE/MKEMBED.PY" "$W/u" "$K32/KERNEL32.PAS" >/dev/null || exit 1
fi
cp "$K32/KERNEL32.PAS" "$W/"
(cd "$W" && "$LPC" -3K -q KERNEL32.PAS) || exit 1
if [ $MODE = file ]; then
  # swap sur fichier : ext2 sur tout le disque hdb avec swapfile (cree par le test), holes (creux), filler (pas du swap)
  mkdir -p "$W/root"
  python3 -c "
open('$W/root/filler','wb').write(b'\x66'*(1<<20))
f=open('$W/root/holes','wb'); f.truncate(1<<20)" 
  mkswap "$W/root/holes" >/dev/null 2>&1 || { echo "mkswap indisponible"; exit 1; }
  truncate -s 32M "$W/swap.img"
  mke2fs -q -t ext2 -b "$BS" -I 128 -r 1 -O none,filetype,sparse_super -d "$W/root" "$W/swap.img" >/dev/null || exit 1
  APPEND="console=ttyS0 swapfile k32power $KARGS"
else
  dd if=/dev/zero of="$W/swap.img" bs=1M count=32 status=none
  mkswap "$W/swap.img" >/dev/null 2>&1 || { echo "mkswap indisponible"; exit 1; }
  APPEND="console=ttyS0 swap=/dev/hdb k32power $KARGS"
fi
timeout 300 qemu-system-i386 -kernel "$W/KERNEL32" -serial "file:$W/out.txt" \
  -display none -m 24 -no-reboot -append "$APPEND" \
  -drive "file=$W/swap.img,format=raw,if=ide,index=1" 2>/dev/null
tr -d '\r' < "$W/out.txt" > "$W/o2.txt"; mv "$W/o2.txt" "$W/out.txt"
grep "swap :\|KTEST: DONE\|KPROG:.*FAIL\|KTEST: swap\|KPROG: /bin/swaptest\|Oops\|panique\|memoire insuffisante" "$W/out.txt"
echo "tests swap OK : $(grep -c 'KTEST: swap.* OK$' "$W/out.txt")"
FS=0
if [ $MODE = file ]; then
  printf '[options]\n\tbroken_system_clock = 1\n' > "$W/e2fsck.conf"
  E2FSCK_CONFIG="$W/e2fsck.conf" e2fsck -fn "$W/swap.img" > "$W/fsck.txt" 2>&1; FS=$?
  tail -3 "$W/fsck.txt"
fi
if [ $FS = 0 ] && grep -q "swap DONE" "$W/out.txt" && ! grep -q "KTEST: swap.* FAIL\|Oops\|panique" "$W/out.txt" \
   && grep -q "KPROG: /bin/swaptest OK" "$W/out.txt"; then
  echo "RESULTAT : SUCCES"; rm -rf "$W"; exit 0
else echo "RESULTAT : ECHEC (traces dans $W)"; exit 1; fi
