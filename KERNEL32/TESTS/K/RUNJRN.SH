#!/bin/bash
# @author: Sylvain Maltais (support@gladir.com)
# @created: 2026
# @website(https://www.gladir.com/linux-0)
# @description: Journal ext3/ext4 et arret brutal : fabrique un disque, lance
#   KERNEL32 sous QEMU avec jrnwrite + jcrash=N (le noyau s'arrete
#   brutalement a l'etape N de la validation du journal : 1 = journal valide
#   mais blocs pas encore recopies, 2 = transaction incomplete, 3 = recopie
#   a moitie, 4 = recopie finie), puis relance le noyau (jrnpresent/jrnabsent :
#   le journal est rejoue au montage) et verifie avec e2fsck -fn.
#     RUNJRN.SH [-n] [-b bloc] [-o "options mke2fs"] [-m Mo]
#   -n : ne pas regenerer les programmes embarques
HERE=$(cd "$(dirname "$0")" && pwd)
K32=$HERE/../..
LPC=${LPC:-/tmp/claude-0/work/k32/bin/lpc}
WB=${WB:-}; SCEN=files; STEPS="0 1 2 3 4"; GEN=1; BS=1024; MB=16; OPTS="-t ext4"; TMO=120
while getopts "nb:o:m:s:S:" o; do
  case $o in n) GEN=0 ;; b) BS=$OPTARG ;; o) OPTS=$OPTARG ;; m) MB=$OPTARG ;; s) SCEN=$OPTARG ;; S) STEPS=$OPTARG ;; *) exit 2 ;; esac
done
W=$(mktemp -d)
if [ $GEN = 1 ]; then
  "$HERE/build.sh" "$W/u" >/dev/null || exit 1
  python3 "$HERE/MKEMBED.PY" "$W/u" "$K32/KERNEL32.PAS" || exit 1
fi
cp "$K32/KERNEL32.PAS" "$W/"
(cd "$W" && "$LPC" -3K -q KERNEL32.PAS) || exit 1
printf "[options]\n\tbroken_system_clock = 1\n" > "$W/e2fsck.conf"
export E2FSCK_CONFIG="$W/e2fsck.conf"
FAILS=0
run_qemu() { # sortie, arguments noyau
  out=$1; shift
  timeout $TMO qemu-system-i386 -kernel "$W/KERNEL32" -serial "file:$out" \
    -display none -m 64 -no-reboot -append "console=ttyS0 k32power $*" \
    -drive "file=$W/d.img,format=raw,if=ide" 2>/dev/null
  tr -d '\r' < "$out" > "$out.2"; mv "$out.2" "$out"
}
for SC in "$SCEN"; do
for N in $STEPS; do
  MKE_OPTS="$OPTS" "$HERE/MKEXT4.SH" "$W/d.img" $MB $BS 256 || exit 1
  EXTRA=$WB; [ "$SC" = orphan ] && EXTRA="$EXTRA jrnorphan"
  run_qemu "$W/w$N.txt" "jrntest jrnwrite $EXTRA jcrash=$N"
  if [ $N = 0 ]; then EXP=jrnpresent
  elif [ $N = 2 ]; then EXP=jrnabsent; else EXP=jrnpresent; fi
  [ "$SC" = orphan ] && EXP="$EXP jrnorphan"
  # journal sale vu de l'hote (informatif)
  JS=$(dumpe2fs -h "$W/d.img?offset=1048576" 2>/dev/null | grep -i "needs_recovery\|Journal start" | tr '\n' ' ')
  run_qemu "$W/c$N.txt" "jrntest $EXP $WB"
  nok=$(grep -c "KTEST: jrn\..* OK$" "$W/c$N.txt")
  bad=$(grep "KTEST: jrn\..* FAIL$" "$W/c$N.txt")
  e2fsck -fn "$W/d.img?offset=1048576" > "$W/f$N.txt" 2>&1; rc=$?
  crashed=$(grep -c "jcrash" "$W/w$N.txt")
  echo "etape $N : arret=$crashed attendu=$EXP verifs OK=$nok e2fsck=$rc [$JS]"
  [ -n "$bad" ] && echo "$bad"
  if [ $rc != 0 ] || [ -n "$bad" ] || [ "$nok" -lt 2 ]; then FAILS=1; echo "  traces : $W/{w,c,f}$N.txt"; fi
  grep -q "jrn DONE" "$W/c$N.txt" || { FAILS=1; echo "  (jrntest incomplet)"; }
  [ "$SC" = orphan ] && grep "orphelin" "$W/c$N.txt" | head -2
done
done
if [ $FAILS = 0 ]; then echo "RESULTAT : SUCCES"; rm -rf "$W"; exit 0
else echo "RESULTAT : ECHEC (traces dans $W)"; exit 1; fi
