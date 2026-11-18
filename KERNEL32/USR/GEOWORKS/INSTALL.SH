#!/bin/bash
# @author: Sylvain Maltais (support@gladir.com)
# @created: 2026
# @website(https://www.gladir.com/linux-0)
# @description: Compile GEOWORKS.PAS (LPC -3X, unite Graph integree) et
#   l'installe dans une racine de systeme : /usr/bin/geoworks (+ lien
#   /bin/geoworks) et /usr/share/geoworks/{WORLD,SYSTEM,DOCUMENT,
#   USERDATA/HELP} (le programme les cree aussi au besoin). A appeler par
#   BUILD.SH apres la boucle de USR/*.PAS (qui ne descend pas dans les
#   sous-dossiers) :
#     USR/GEOWORKS/INSTALL.SH [-l lpc] RACINE
#   exemple : USR/GEOWORKS/INSTALL.SH -l $LPC $W/root
HERE=$(cd "$(dirname "$0")" && pwd)
LPC=${LPC:-/tmp/claude-0/work/k32/bin/lpc}
while getopts "l:" o; do case $o in l) LPC=$OPTARG ;; *) exit 2 ;; esac; done
shift $((OPTIND - 1))
ROOT=$1
[ -d "$ROOT" ] || { echo "usage : INSTALL.SH [-l lpc] RACINE"; exit 2; }
T=$(mktemp -d)
cp "$HERE/GEOWORKS.PAS" "$T/"
( cd "$T" && "$LPC" -3X -q GEOWORKS.PAS ) || { echo "echec LPC"; exit 1; }
mkdir -p "$ROOT/usr/bin" "$ROOT/bin" "$ROOT/usr/share/geoworks/WORLD" \
  "$ROOT/usr/share/geoworks/SYSTEM" "$ROOT/usr/share/geoworks/DOCUMENT" \
  "$ROOT/usr/share/geoworks/USERDATA/HELP"
install -m 755 "$T/GEOWORKS" "$ROOT/usr/bin/geoworks"
ln -sf ../usr/bin/geoworks "$ROOT/bin/geoworks"
rm -rf "$T"
echo "geoworks installe dans $ROOT/usr/bin ($(stat -c %s \
  "$ROOT/usr/bin/geoworks") octets)"
