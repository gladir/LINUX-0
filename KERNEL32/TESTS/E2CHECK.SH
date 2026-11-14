#!/bin/bash
# @author: Sylvain Maltais (support@gladir.com)
# @created: 2026
# @website(https://www.gladir.com/linux-0)
# @description: Verificateur independant d'une image de disque de KERNEL32 :
#     E2CHECK.SH IMAGE.IMG [NOYAU.ELF]
#   1. table des partitions (signature, partition 1 active de type 83h);
#   2. e2fsck -fn sur la partition 1 (decalage lu dans la table) ;
#   3. lecteur ext2 independant E2CHECK.PY : /boot/linux0 est lu et compare
#      au noyau d'origine (octet pour octet) avec la couverture des blocs
#      directs, indirects simples, doubles et triples.
IMG=${1:?image}
KERN=$2
HERE=$(cd "$(dirname "$0")" && pwd)
set -e
od1() { od -An "$@" "$IMG" | tr -d ' '; }
[ "$(od1 -tx1 -j510 -N2)" = 55aa ] ||
  { echo "E2CHECK : signature 55AA absente"; exit 1; }
ST=$(od1 -tx1 -j446 -N1)
TY=$(od1 -tx1 -j450 -N1)
START=$(od1 -tu4 -j454 -N4)
echo "partition 1 : etat $ST, type $TY, debut secteur $START"
[ "$ST" = 80 ] && [ "$TY" = 83 ] ||
  { echo "E2CHECK : partition 1 pas active ou pas de type 83h"; exit 1; }
e2fsck -fn "$IMG?offset=$((START * 512))" | tail -3
if [ -n "$KERN" ]; then
  python3 "$HERE/E2CHECK.PY" "$IMG" --start "$START" \
    --compare /boot/linux0 "$KERN"
else
  python3 "$HERE/E2CHECK.PY" "$IMG" --start "$START" --ls /boot
fi
