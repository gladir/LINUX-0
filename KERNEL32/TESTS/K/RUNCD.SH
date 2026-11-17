#!/bin/bash
# @author: Sylvain Maltais (support@gladir.com)
# @created: 2026
# @website(https://www.gladir.com/linux-0)
# @description: Essai de l'amorce depuis CD-ROM : fabrique un ISO (TOOLS/MKCD.SH)
#   avec le noyau de PRODUCTION (TOOLS/MKPROD.SH : sans programmes de test), un initramfs dont /init est cdtest.c et un fichier de
#   contenu connu, l'amorce sous QEMU (SeaBIOS : -cdrom -boot d) et verifie que
#   le chargeur El Torito a charge le noyau + l'initrd + la ligne de commande,
#   que /init demarre et que le CD se monte en iso9660 sous /cdrom.
#   Troisieme essai : le CD sur un controleur AHCI (/dev/sr0, defaut de VirtualBox).
#     RUNCD.SH [-t secondes]
HERE=$(cd "$(dirname "$0")" && pwd)
K32=$HERE/../..
LPC=${LPC:-/tmp/claude-0/work/k32/bin/lpc}
TMO=90
while getopts "t:" o; do case $o in t) TMO=$OPTARG ;; *) exit 2 ;; esac; done
W=$(mktemp -d)
gcc -m32 -static -nostdlib -ffreestanding -fno-pic -fno-pie -no-pie -Os -fno-stack-protector \
    -fno-asynchronous-unwind-tables -fno-builtin -Wl,--build-id=none -Wl,-z,noseparate-code \
    -Wl,-z,norelro -o "$W/init" "$HERE/cdtest.c" 2>/dev/null || exit 1
python3 "$HERE/MKCPIO.PY" "$W/init" "$W/ird" || exit 1
"$K32/TOOLS/MKPROD.SH" -l "$LPC" -o "$W/KERNEL32" || exit 1   # noyau de production (sans programmes de test)
mkdir "$W/root"; printf 'hello from cd\n' > "$W/root/readme.txt"
"$K32/TOOLS/MKCD.SH" -o "$W/k32.iso" -k "$W/KERNEL32" -I "$W/ird.cpio.gz" -r "$W/root" \
    -c "console=ttyS0 cdlive=1" || exit 1
RC=0
for SET in "cd" "cd-smp" "cd-ahci"; do
  echo "== $SET"
  rm -f "$W/out.txt"
  X=; [ "$SET" = cd-smp ] && X="-smp 2"
  CDARGS=(-cdrom "$W/k32.iso")
  [ "$SET" = cd-ahci ] && CDARGS=(-device ich9-ahci,id=ahci -drive "file=$W/k32.iso,if=none,id=c0,media=cdrom,format=raw,readonly=on" -device ide-cd,drive=c0,bus=ahci.0)
  timeout "$TMO" qemu-system-i386 "${CDARGS[@]}" -boot d -serial "file:$W/out.txt" \
      -display none -m 64 -no-reboot $X $QX 2>/dev/null &
  QP=$!
  for i in $(seq 1 "$TMO"); do
    grep -q "KTEST: cd DONE" "$W/out.txt" 2>/dev/null && break
    kill -0 $QP 2>/dev/null || break
    sleep 1
  done
  kill $QP 2>/dev/null; wait $QP 2>/dev/null
  tr -d '\r' < "$W/out.txt" > "$W/o_$SET.txt"
  grep -a "Noyau :\|initrd :\|ISO 9660\|Ligne de commande\|CD-LIVE-OK\|KTEST: cd\|ERREUR\|Oops\|panique" "$W/o_$SET.txt"
  for t in init_pid1 cmdline mount readme kernel_on_cd kernel_elf; do
    grep -q "KTEST: cd.$t OK" "$W/o_$SET.txt" || { echo "cd.$t : ECHEC"; RC=1; }
  done
  grep -q "KTEST: cd DONE" "$W/o_$SET.txt" || { echo "cd DONE absent"; RC=1; }
done
if [ $RC = 0 ]; then echo "RESULTAT : SUCCES"; rm -rf "$W"; exit 0
else echo "RESULTAT : ECHEC (traces dans $W)"; exit 1; fi
