#!/bin/bash
# @author: Sylvain Maltais (support@gladir.com)
# @created: 2026
# @website(https://www.gladir.com/linux-0)
# @description: Essai du shell KERNEL32/USR/SH.PAS sur l'hote : chaque script
#   de TESTS/U/sh/tNN_*.sh est execute par le shell -3X et sa sortie est
#   comparee a tNN_*.out (produit une fois par dash). Variables : LPC, SHBIN.
HERE=$(cd "$(dirname "$0")" && pwd)
LPC=${LPC:-/tmp/claude-0/work/k32/bin/lpc}
W=${W:-/tmp/linux0-u-tests}
mkdir -p "$W"
if [ -z "$SHBIN" ]; then
  cp "$HERE/../../USR/SH.PAS" "$W/SH.PAS"
  (cd "$W" && "$LPC" -3X -q SH.PAS) || exit 2
  SHBIN=$W/SH
fi
P=0; F=0
for s in "$HERE"/sh/t*.sh; do
  b=${s%.sh}
  (cd /tmp && "$SHBIN" "$s" 2>&1; echo "rc=$?") | sed 's/shtest\.[0-9]*/shtest.N/' > "$W/out.txt"
  sed 's/shtest\.[0-9]*/shtest.N/' "$b.out" > "$W/exp.txt"
  if cmp -s "$W/out.txt" "$W/exp.txt"; then echo "ok    $(basename $s)"; P=$((P+1))
  else echo "ECHEC $(basename $s)"; diff "$W/out.txt" "$W/exp.txt" | head -5; F=$((F+1)); fi
done
echo "$P reussi(s), $F echec(s)"
[ $F = 0 ]
