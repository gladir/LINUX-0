#!/bin/bash
# @author: Sylvain Maltais (support@gladir.com)
# @created: 2026
# @description: Banc d'essai de l'initramfs (partie 38) : /init (initrdtest.c)
#   dans une archive cpio newc (MKCPIO.PY), passee a QEMU comme module
#   Multiboot (-initrd) : brut, gzip, deux modules, gzip + brut concatenes.
#     RUNINITRD.SH [-t secondes]
HERE=$(cd "$(dirname "$0")" && pwd)
K32=$HERE/../..
LPC=${LPC:-/tmp/claude-0/work/k32/bin/lpc}
TMO=60
while getopts "t:" o; do case $o in t) TMO=$OPTARG ;; *) exit 2 ;; esac; done
W=$(mktemp -d)
gcc -m32 -static -nostdlib -ffreestanding -fno-pic -fno-pie -no-pie -Os -fno-stack-protector \
    -fno-asynchronous-unwind-tables -fno-builtin -Wl,--build-id=none -Wl,-z,noseparate-code \
    -Wl,-z,norelro -o "$W/init" "$HERE/initrdtest.c" 2>/dev/null || exit 1
python3 "$HERE/MKCPIO.PY" "$W/init" "$W/ird" || exit 1
cp "$K32/KERNEL32.PAS" "$W/"
(cd "$W" && "$LPC" -3K -q KERNEL32.PAS) || exit 1
RC=0
run() {  # nom initrd(s) [mots de ligne de commande] ; initrd "disk:IMG" : amorce par le chargeur
  N=$1; IRD=$2; shift 2
  rm -f "$W/out.txt"
  case $IRD in
    disk:*) timeout "$TMO" qemu-system-i386 -drive "file=${IRD#disk:},format=raw,if=ide" -serial "file:$W/out.txt" \
        -display none -m 64 -no-reboot 2>/dev/null & ;;
    *) timeout "$TMO" qemu-system-i386 -kernel "$W/KERNEL32" -initrd "$IRD" -serial "file:$W/out.txt" \
        -display none -m 64 -no-reboot -append "console=ttyS0 $*" 2>/dev/null & ;;
  esac
  QP=$!
  for i in $(seq 1 "$TMO"); do
    grep -q "KTEST: initrd DONE" "$W/out.txt" 2>/dev/null && break
    kill -0 $QP 2>/dev/null || break
    sleep 1
  done
  kill $QP 2>/dev/null; wait $QP 2>/dev/null
  tr -d '\r' < "$W/out.txt" > "$W/o_$N.txt"
  OK=$(grep -c "KTEST: initrd\..* OK$" "$W/o_$N.txt")
  BAD=$(grep "KTEST:.* FAIL$\|Oops\|panique" "$W/o_$N.txt")
  grep "initramfs :" "$W/o_$N.txt"
  if grep -q "KTEST: initrd DONE" "$W/o_$N.txt" && [ -z "$BAD" ]; then echo "$N : $OK verifications OK"
  else echo "$N : ECHEC ($OK OK)"; echo "$BAD"; RC=1; fi
}
"$K32/TOOLS/MKIMAGE.SH" -o "$W/disk.img" -k "$W/KERNEL32" -I "$W/ird.cpio.gz" -c "console=ttyS0 root=/dev/hda1 ro" -s 24 >/dev/null 2>&1 || { echo "MKIMAGE echec"; RC=1; }
run raw "$W/ird.cpio"
run gzip "$W/ird.cpio.gz"
run multi "$W/ird.a.cpio,$W/ird.b.cpio.gz" initrdmulti
run concat "$W/ird.cat.gz" initrdmulti
run disk "disk:$W/disk.img"
if [ $RC = 0 ]; then echo "RESULTAT : SUCCES"; rm -rf "$W"; else echo "RESULTAT : ECHEC (traces dans $W)"; fi
exit $RC
