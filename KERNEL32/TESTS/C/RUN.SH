#!/bin/bash
# RUN.SH - tests de non-regression de la cible 32 bits de LPC (KERNEL32)
#
# Pour chaque TKn.PAS (noyau de test, compile avec "LPC -3K") : compile,
# verifie l'ELF32 (readelf), lance sous QEMU (port serie COM1 redirige vers
# un fichier, sortie par le peripherique isa-debug-exit) et compare la sortie
# serie au fichier TKn.OUT.
# Pour chaque UXn.PAS (programme Linux i386, compile avec "LPC -3X") : compile
# puis execute directement sur l'hote (un noyau Linux qui sait executer les
# ELF32 i386 statiques ; sinon le test est ignore), avec les arguments de
# UXn.ARG et la variable LINUX0TEST=bonjour, et compare la sortie a UXn.OUT.
#
# Variables : LPC (compilateur deja construit, sinon construit depuis
# ../../TOOLS/LPC.PAS avec fpc), QEMU (defaut qemu-system-i386), W (dossier
# de travail, defaut /tmp/linux0-k32-tests), TIMEOUT (secondes, defaut 10).
HERE=$(cd "$(dirname "$0")" && pwd)
TOOLS=$HERE/../../TOOLS
W=${W:-/tmp/linux0-k32-tests}
QEMU=${QEMU:-qemu-system-i386}
TIMEOUT=${TIMEOUT:-10}
mkdir -p "$W"
if [ -z "$LPC" ]; then
  (cd "$TOOLS" && fpc -Mtp -O1 -FU"$W" -FE"$W" -o"$W/lpc" LPC.PAS >"$W/fpc.log" 2>&1) \
    || { echo "construction de LPC impossible (voir $W/fpc.log)"; exit 2; }
  LPC=$W/lpc
fi
PASS=0; FAIL=0
for SRC in "$HERE"/TK*.PAS; do
  N=$(basename "$SRC" .PAS)
  [ -f "$HERE/$N.OUT" ] || continue
  cp "$SRC" "$W/$N.PAS"
  rm -f "$W/$N" "$W/$N.ser"
  if ! "$LPC" -3K -q "$W/$N.PAS" >"$W/$N.log" 2>&1; then
    echo "ECHEC $N : compilation (voir $W/$N.log)"; FAIL=$((FAIL+1)); continue
  fi
  if ! readelf -h "$W/$N" | grep -q 'Machine:.*80386'; then
    echo "ECHEC $N : ELF i386 attendu"; FAIL=$((FAIL+1)); continue
  fi
  timeout "$TIMEOUT" "$QEMU" -kernel "$W/$N" -serial file:"$W/$N.ser" \
    -display none -monitor none -m 64 -no-reboot \
    -device isa-debug-exit,iobase=0xf4,iosize=0x04 >/dev/null 2>&1
  if cmp -s "$W/$N.ser" "$HERE/$N.OUT"; then
    echo "ok    $N"; PASS=$((PASS+1))
  else
    echo "ECHEC $N : sortie serie differente ($W/$N.ser)"; FAIL=$((FAIL+1))
  fi
done
# --- programmes utilisateur -3X, executes sur l'hote ---
if cp "$HERE/UX1.PAS" "$W/UXPROBE.PAS" && "$LPC" -3X -q "$W/UXPROBE.PAS" >/dev/null 2>&1 \
   && "$W/UXPROBE" >/dev/null 2>&1; then
  for SRC in "$HERE"/UX*.PAS; do
    N=$(basename "$SRC" .PAS)
    [ -f "$HERE/$N.OUT" ] || continue
    cp "$SRC" "$W/$N.PAS"
    rm -f "$W/$N"
    if ! "$LPC" -3X -q "$W/$N.PAS" >"$W/$N.log" 2>&1; then
      echo "ECHEC $N : compilation (voir $W/$N.log)"; FAIL=$((FAIL+1)); continue
    fi
    ARGS=""
    [ -f "$HERE/$N.ARG" ] && ARGS=$(cat "$HERE/$N.ARG")
    (cd "$W" && LINUX0TEST=bonjour "./$N" $ARGS </dev/null >"$W/$N.sortie" 2>&1)
    if cmp -s "$W/$N.sortie" "$HERE/$N.OUT"; then
      echo "ok    $N"; PASS=$((PASS+1))
    else
      echo "ECHEC $N : sortie differente ($W/$N.sortie)"; FAIL=$((FAIL+1))
    fi
  done
else
  echo "(tests UX ignores : l'hote n'execute pas les ELF32 i386)"
fi
echo "$PASS reussi(s), $FAIL echec(s)"
[ "$FAIL" = 0 ]
