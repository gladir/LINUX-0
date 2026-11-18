#!/bin/bash
# @author: Sylvain Maltais (support@gladir.com)
# @created: 2026
# @website(https://www.gladir.com/linux-0)
# @description: Pilote VMMDev de VirtualBox (souris absolue, /dev/input/event2)
#   contre le peripherique LOGICIEL de simulation du noyau (k32vboxfake=1) :
#   QEMU n'emule pas VMMDev, ce test ne prouve donc le pilote que contre la
#   simulation (format des requetes, evenements, evdev), pas contre VirtualBox.
#     RUNVBOX.SH [-n]
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
timeout 60 qemu-system-i386 -kernel "$W/KERNEL32" -serial "file:$W/out.txt" -display none \
  -m 64 -no-reboot -append "console=ttyS0 init=/bin/vboxtest k32vboxfake=1 k32power" 2>/dev/null
tr -d '\r' < "$W/out.txt" | grep -a "vbox:\|KTEST: vbox\|Oops\|panique"
if grep -aq "KTEST: vbox.* FAIL" "$W/out.txt" || ! grep -aq "KTEST: vbox DONE" "$W/out.txt"; then
  echo "RESULTAT : ECHEC (traces dans $W)"; exit 1
fi
echo "RESULTAT : SUCCES (simulation seulement)"; rm -rf "$W"; exit 0
