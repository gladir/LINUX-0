#!/bin/bash
# @author: Sylvain Maltais (support@gladir.com)
# @created: 2026
# @description: Racine reelle autre qu'ext2 (partie 38) : vfat, iso9660, minix,
#   cramfs, romfs sur /dev/hda (disque brut, detection automatique du type,
#   noyau lance par qemu -kernel). roottest.c est /sbin/init.
#     RUNROOT.SH [-t secondes]
HERE=$(cd "$(dirname "$0")" && pwd)
K32=$HERE/../..
LPC=${LPC:-/tmp/claude-0/work/k32/bin/lpc}
TMO=60
while getopts "t:" o; do case $o in t) TMO=$OPTARG ;; *) exit 2 ;; esac; done
W=$(mktemp -d)
gcc -m32 -static -nostdlib -ffreestanding -fno-pic -fno-pie -no-pie -Os -fno-stack-protector \
    -fno-asynchronous-unwind-tables -fno-builtin -Wl,--build-id=none -Wl,-z,noseparate-code \
    -Wl,-z,norelro -o "$W/init" "$HERE/roottest.c" 2>/dev/null || exit 1
cp "$K32/KERNEL32.PAS" "$W/"
(cd "$W" && "$LPC" -3K -q KERNEL32.PAS) || exit 1
export MTOOLS_SKIP_CHECK=1
RC=0
tree() {  # type -> $W/t_$1
  mkdir -p "$W/t_$1/sbin" "$W/t_$1/etc" "$W/t_$1/dev" "$W/t_$1/proc" "$W/t_$1/sys"
  cp "$W/init" "$W/t_$1/sbin/init"; chmod 755 "$W/t_$1/sbin/init"
  echo "marker-$1" > "$W/t_$1/etc/marker"
}
tree vfat; tree iso9660; tree minix; tree cramfs; tree romfs; tree ext2
# vfat
dd if=/dev/zero of="$W/vfat.img" bs=1M count=20 status=none
mkfs.vfat -F 16 -s 2 -S 512 "$W/vfat.img" >/dev/null
mmd -i "$W/vfat.img" ::sbin ::etc ::dev ::proc ::sys; mcopy -i "$W/vfat.img" "$W/init" ::sbin/init; mcopy -i "$W/vfat.img" "$W/t_vfat/etc/marker" ::etc/marker
mkisofs -R -quiet -o "$W/iso9660.img" "$W/t_iso9660" 2>/dev/null
python3 "$HERE/MKROFS.PY" minix2l "$W/t_minix" "$W/minix.img"
mkfs.cramfs "$W/t_cramfs" "$W/cramfs.img" >/dev/null
python3 "$HERE/MKROFS.PY" romfs "$W/t_romfs" "$W/romfs.img"
dd if=/dev/zero of="$W/ext2.img" bs=1M count=8 status=none
mke2fs -q -t ext2 -b 1024 -I 128 -r 1 -O none,filetype,sparse_super -d "$W/t_ext2" "$W/ext2.img" >/dev/null
for T in ext2 vfat iso9660 minix cramfs romfs; do
  rm -f "$W/out.txt"
  timeout "$TMO" qemu-system-i386 -kernel "$W/KERNEL32" -serial "file:$W/out.txt" -display none -m 64 -no-reboot \
    -drive "file=$W/$T.img,format=raw,if=ide" -append "console=ttyS0 root=/dev/hda wantfs=$T" 2>/dev/null &
  QP=$!
  for i in $(seq 1 "$TMO"); do
    grep -q "KTEST: root DONE" "$W/out.txt" 2>/dev/null && break
    kill -0 $QP 2>/dev/null || break
    sleep 1
  done
  kill $QP 2>/dev/null; wait $QP 2>/dev/null
  tr -d '\r' < "$W/out.txt" > "$W/o_$T.txt"
  BAD=$(grep "KTEST:.* FAIL$\|Oops\|panique" "$W/o_$T.txt")
  if grep -q "KTEST: root DONE" "$W/o_$T.txt" && [ -z "$BAD" ]; then echo "$T : $(grep -c 'KTEST: root\..* OK$' "$W/o_$T.txt") verifications OK ($(grep 'racine : type' "$W/o_$T.txt"))"
  else echo "$T : ECHEC"; grep 'racine' "$W/o_$T.txt" | head -3; echo "$BAD" | head -3; RC=1; fi
done
if [ $RC = 0 ]; then echo "RESULTAT : SUCCES"; rm -rf "$W"; else echo "RESULTAT : ECHEC (traces dans $W)"; fi
exit $RC
