#!/bin/bash
# @author: Sylvain Maltais (support@gladir.com)
# @created: 2026
# @website(https://www.gladir.com/linux-0)
# @description: Essais QEMU de l'unite Graph, de la souris et du clavier de
#   LPC -3X (voir GFXT.PY) : cartes -vga std (avec un disque ich9-ahci) puis
#   -vga vmware. Captures PNG dans IMAGE/CAPTURES.
#     RUNGFX.SH [scenario...]     scenarios : prim mouse geo dos bench (tous)
#   Variables : LPC, KSRC (source du noyau), W (travail), GEOWORKS (source de
#   GEOWORKS.PAS, defaut /home/user/dev-cools/GEOWORKS.PAS).
HERE=$(cd "$(dirname "$0")" && pwd)
K32=$HERE/../..
LPC=${LPC:-/tmp/claude-0/work/k32/bin/lpc}
W=${W:-/tmp/linux0-gfx-tests}
CAP=${CAP:-$K32/IMAGE/CAPTURES}
mkdir -p "$W"
"$K32/TOOLS/MKPROD.SH" -l "$LPC" -s "${KSRC:-$K32/KERNEL32.PAS}" \
  -o "$W/KERNEL32.ELF" >/dev/null || { echo "ECHEC MKPROD.SH"; exit 1; }
RC=0
for V in std vmware; do
  echo "== -vga $V"
  python3 "$HERE/GFXT.PY" "$W/$V" "$LPC" "$W/KERNEL32.ELF" "$CAP" $V "$@" ||
    RC=1
done
[ $RC = 0 ] && echo "RESULTAT : SUCCES" || echo "RESULTAT : ECHEC"
exit $RC
