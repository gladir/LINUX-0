#!/bin/bash
# RUN16.SH - non-regression de la cible 16 bits du LPC de KERNEL32 :
# compile avec le LPC de KERNEL16UNIX et avec celui de KERNEL32 le noyau
# 16 bits (/K), des commandes (/X) et un programme avec -K<seg>, et verifie
# que les images sont identiques octet pour octet.
# Variables : LPC (LPC de KERNEL32 deja construit), W (dossier de travail,
# defaut /tmp/linux0-k32-tests16).
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$HERE/../../..
W=${W:-/tmp/linux0-k32-tests16}
mkdir -p "$W/old" "$W/new" "$W/oldo" "$W/newo"
# compilateur 16 bits d'origine (copie de LPC.PAS seul : UNIX.PAS du dossier
# TOOLS porte le meme nom que l'unite Unix de Free Pascal)
cp "$ROOT/KERNEL16UNIX/TOOLS/LPC.PAS" "$W/oldo/"
mkdir -p "$W/oldo/o"
(cd "$W/oldo" && fpc -Mtp -O1 -FUo -FEo -o"$W/oldo/lpc" LPC.PAS >fpc.log 2>&1) || { echo "LPC 16 bits : construction impossible"; exit 2; }
OLD=$W/oldo/lpc
if [ -z "$LPC" ]; then
  mkdir -p "$W/newo"
  (cd "$ROOT/KERNEL32/TOOLS" && fpc -Mtp -O1 -FU"$W/newo" -FE"$W/newo" -o"$W/newo/lpc" LPC.PAS >"$W/newo/fpc.log" 2>&1) || { echo "LPC KERNEL32 : construction impossible"; exit 2; }
  LPC=$W/newo/lpc
fi
FAIL=0
for T in "KERNEL16UNIX/KERNEL.PAS /K KERNEL.SYS" "CAT.PAS /X CAT" "ECHO.PAS /X ECHO" "LS.PAS /X LS" "KERNEL16UNIX/INIT.PAS /X INIT"; do
  set -- $T
  SRC=$1; OPT=$2; OUT=$3
  B=$(basename "$SRC")
  for D in old new; do cp "$ROOT/$SRC" "$W/$D/$B"; done
  (cd "$W/old" && "$OLD" $OPT "$B" >/dev/null 2>&1)
  (cd "$W/new" && "$LPC" $OPT "$B" >/dev/null 2>&1)
  if cmp -s "$W/old/$OUT" "$W/new/$OUT" && [ -s "$W/new/$OUT" ]; then echo "ok    $SRC $OPT"
  else echo "ECHEC $SRC $OPT"; FAIL=$((FAIL+1)); fi
done
# image plate -K0840 (chargeur 16 bits)
cp "$ROOT/KERNEL16UNIX/KERNEL.PAS" "$W/old/K2.PAS"; cp "$ROOT/KERNEL16UNIX/KERNEL.PAS" "$W/new/K2.PAS"
(cd "$W/old" && "$OLD" -K0840 K2.PAS >/dev/null 2>&1)
(cd "$W/new" && "$LPC" -K0840 K2.PAS >/dev/null 2>&1)
if cmp -s "$W/old/K2.SYS" "$W/new/K2.SYS" && [ -s "$W/new/K2.SYS" ]; then echo "ok    -K0840"
else echo "ECHEC -K0840"; FAIL=$((FAIL+1)); fi
[ "$FAIL" = 0 ]
