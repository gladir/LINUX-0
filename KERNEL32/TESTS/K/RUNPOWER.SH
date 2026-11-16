#!/bin/bash
# @author: Sylvain Maltais (support@gladir.com)
# @created: 2026
# @website(https://www.gladir.com/linux-0)
# @description: Arret et redemarrage ACPI (partie 39) : le noyau lit la FADT
#   (PM1a_CNT_BLK, registre de reinitialisation) et l'objet \_S5_ de la DSDT ;
#   avec "noportoff" il n'essaie aucun autre moyen d'arret : QEMU (-no-reboot) doit
#   se terminer de lui-meme apres reboot(POWER_OFF), le journal cite l'ACPI ; le
#   redemarrage (registre ACPI s'il existe, sinon 0CF9h, 8042) aussi.
#     RUNPOWER.SH [-n]
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
for MODE in k32off k32restart; do
  rm -f "$W/out.txt"
  S=$(date +%s)
  NP=noportoff; [ $MODE = k32restart ] && NP=
  timeout 40 qemu-system-i386 -kernel "$W/KERNEL32" -serial "file:$W/out.txt" -display none \
    -m 64 -no-reboot -append "console=ttyS0 init=/bin/pwrtest $NP $MODE" $QX 2>/dev/null
  E=$(( $(date +%s) - S ))
  tr -d '\r' < "$W/out.txt" > "$W/o_$MODE.txt"
  if [ $E -ge 38 ]; then echo "$MODE : QEMU ne s'est pas arrete (ACPI inoperant)"; RC=1; fi
  grep -a "ACPI :\|PWR-\|Redemarrage" "$W/o_$MODE.txt"
  if [ $MODE = k32off ]; then grep -aq "ACPI : arret" "$W/o_$MODE.txt" || { echo "$MODE : pas de message ACPI"; RC=1; }
  else grep -aq "Redemarrage du systeme" "$W/o_$MODE.txt" || { echo "$MODE : pas de redemarrage"; RC=1; }; fi
  grep -aq "PWR-NOT-REACHED" "$W/o_$MODE.txt" && RC=1
  echo "$MODE : termine en $E s"
done
if [ $RC = 0 ]; then echo "RESULTAT : SUCCES"; rm -rf "$W"; exit 0
else echo "RESULTAT : ECHEC (traces dans $W)"; exit 1; fi
