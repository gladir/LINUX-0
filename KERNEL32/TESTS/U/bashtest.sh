#!/bin/bash
# @author: Sylvain Maltais (support@gladir.com)
# @created: 2026
# @website(https://www.gladir.com/linux-0)
# @description: Essai de /bin/bash (USR/SH.PAS, mode bash) : chaque script de
#   TESTS/U/bash/bNN_*.sh est execute par le shell -3X appele "bash" et sa
#   sortie est comparee a bNN_*.out (produit par GNU bash 5.2 de l'hote).
#   Variables : LPC, W, BASHBIN (shell deja compile, nomme bash).
HERE=$(cd "$(dirname "$0")" && pwd)
LPC=${LPC:-/tmp/claude-0/work/k32/bin/lpc}
W=${W:-/tmp/linux0-u-tests}
mkdir -p "$W/bashbin"
if [ -z "$BASHBIN" ]; then
  cp "$HERE/../../USR/SH.PAS" "$HERE/../../USR/REGEX.INC" "$W/"
  (cd "$W" && "$LPC" -3X -q SH.PAS) || exit 2
  cp "$W/SH" "$W/bashbin/bash"
  BASHBIN=$W/bashbin/bash
fi
P=0; F=0
for s in "$HERE"/bash/b*.sh; do
  b=${s%.sh}
  (cd /tmp && timeout 30 "$BASHBIN" "$s" 2>&1 </dev/null) > "$W/bout.txt"
  if cmp -s "$W/bout.txt" "$b.out"; then echo "ok    $(basename $s)"; P=$((P+1))
  else echo "ECHEC $(basename $s)"; diff "$W/bout.txt" "$b.out" | head -6; F=$((F+1)); fi
done
echo "$P reussi(s), $F echec(s)"
[ $F = 0 ]
