#!/bin/bash
# @author: Sylvain Maltais (support@gladir.com)
# @created: 2026
# @website(https://www.gladir.com/linux-0)
# @description: Banc d'essai de GEOWORKS (USR/GEOWORKS/GEOWORKS.PAS) sous
#   QEMU : racine du systeme (BUILD.SH ROOTONLY), GEOWORKS compile par LPC
#   -3X (unite Graph integree) et installe par USR/GEOWORKS/INSTALL.SH,
#   noyau de production (MKPROD.SH), puis georun.py : accueil, Terminal
#   (pty), Programmes Linux, Calculatrice, GeoWrite, GeoDraw, Tetris, horloge,
#   GeoManager, menu du bureau, sortie vers Linux. Captures PNG (<= 300 Ko)
#   dans IMAGE/CAPTURES (geo-*.png).
#     RUNGEO.SH [-r racine] [-k noyau.elf] [-c captures] [-l lpc] [config...]
#   config : std (-vga std, disque IDE, defaut), vmware (-vga vmware),
#   ahci (disque ich9-ahci), all (les trois)
#   Variables : LPC (compilateur -3K/-3X sans Graph), W (travail, defaut
#   /tmp/linux0-geo-tests).
HERE=$(cd "$(dirname "$0")" && pwd)
K32=$HERE/../..
LPC=${LPC:-/tmp/claude-0/work/k32/bin/lpc}
LPCG=
W=${W:-/tmp/linux0-geo-tests}
ROOT=; KERN=; CAP=$K32/IMAGE/CAPTURES
while getopts "r:k:c:l:" o; do
  case $o in
    r) ROOT=$OPTARG ;; k) KERN=$OPTARG ;; c) CAP=$OPTARG ;; l) LPCG=$OPTARG ;;
    *) exit 2 ;;
  esac
done
shift $((OPTIND - 1))
[ -n "$LPCG" ] || LPCG=$LPC
CONFIGS=${*:-std}
[ "$CONFIGS" = all ] && CONFIGS="std vmware ahci"
mkdir -p "$W"
if [ -z "$ROOT" ]; then
  echo "== racine du systeme (BUILD.SH)"
  ( cd "$K32" && ROOTONLY=1 LPC=$LPC W=$W/build ./BUILD.SH ) \
    > "$W/build.log" 2>&1 ||
    { echo "ECHEC BUILD.SH (voir $W/build.log)"; exit 1; }
  ROOT=$W/build/root
fi
echo "== GEOWORKS (LPC -3X)"
rm -rf "$W/root"
cp -a "$ROOT" "$W/root"
"$K32/USR/GEOWORKS/INSTALL.SH" -l "$LPCG" "$W/root" || exit 1
# racine de test : mot de passe root vide
sed -i 's/^root:[^:]*:/root::/' "$W/root/etc/shadow"
if [ -z "$KERN" ]; then
  echo "== noyau de production"
  "$K32/TOOLS/MKPROD.SH" -l "$LPC" -s "$K32/KERNEL32.PAS" \
    -o "$W/KERNEL32.ELF" > /dev/null || { echo "ECHEC MKPROD.SH"; exit 1; }
  KERN=$W/KERNEL32.ELF
fi
RC=0
for c in $CONFIGS; do
  case $c in
    std) V=std; D=ide ;; vmware) V=vmware; D=ide ;; ahci) V=std; D=ahci ;;
    *) echo "config inconnue : $c"; exit 2 ;;
  esac
  echo "== georun : -vga $V, disque $D"
  python3 "$HERE/georun.py" "$W/run-$c" "$W/root" "$KERN" "$CAP" $V $D ||
    RC=1
done
[ $RC = 0 ] && echo "RESULTAT : SUCCES" || echo "RESULTAT : ECHEC"
exit $RC
