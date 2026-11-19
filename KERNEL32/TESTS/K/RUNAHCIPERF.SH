#!/bin/bash
# @author: Sylvain Maltais (support@gladir.com)
# @created: 2026
# @website(https://www.gladir.com/linux-0)
# @description: Debit et integrite du disque AHCI : deux disques ich9-ahci
#   (-drive cache=writethrough) : sda = ext4 (MKEXT2.SH), sdb = disque brut.
#   aperf ecrit puis relit MB Mo sur le disque brut et EXTMB Mo dans un fichier
#   ext4 (motif a marqueur unique par secteur, verifie par le noyau ET par
#   l'hote), imprime debit et compteurs (commandes AHCI, Ko, acces de
#   registres = VM-exits, IRQ). e2fsck -fn de l'image ext4 ensuite.
#     RUNAHCIPERF.SH [-n] [-m Mo_brut] [-e Mo_ext4] [-b taille_bloc]
#   QX="-smp 2" etc. pour les variantes SMP.
HERE=$(cd "$(dirname "$0")" && pwd)
K32=$HERE/../..
LPC=${LPC:-/tmp/claude-0/work/k32/bin/lpc}
GEN=1; MB=256; EXTMB=128; BS=1024
while [ -n "$1" ]; do case "$1" in -n) GEN=0;; -m) MB=$2; shift;; -e) EXTMB=$2; shift;; -b) BS=$2; shift;; esac; shift; done
W=$(mktemp -d)
if [ $GEN = 1 ]; then
  "$HERE/build.sh" "$W/u" >/dev/null || exit 1
  python3 "$HERE/MKEMBED.PY" "$W/u" "$K32/KERNEL32.PAS" >/dev/null || exit 1
fi
cp "$K32/KERNEL32.PAS" "$W/"
(cd "$W" && "$LPC" -3K -q KERNEL32.PAS) || exit 1
DISK=$((EXTMB + 160)); [ $DISK -lt 200 ] && DISK=200
MKE_OPTS="${MKE_OPTS:--t ext4}" "$HERE/MKEXT2.SH" "$W/a.img" $DISK $BS 256 >/dev/null || exit 1
rm -f "$W/b.img"; truncate -s $((MB + 8))M "$W/b.img"
rm -f "$W/out.txt"
T0=$(date +%s)
timeout ${TMO:-900} qemu-system-i386 -kernel "$W/KERNEL32" -serial "file:$W/out.txt" -display none \
  -m ${MEM:-128} -no-reboot -append "console=ttyS0 init=/bin/aperf aperf=$MB aperfext=$EXTMB k32power $KARGS" \
  -device ich9-ahci,id=ahci -drive "file=$W/a.img,format=raw,if=none,id=d0,cache=writethrough" \
  -device ide-hd,drive=d0,bus=ahci.0 -drive "file=$W/b.img,format=raw,if=none,id=d1,cache=writethrough" \
  -device ide-hd,drive=d1,bus=ahci.1 $QX 2>/dev/null
echo "duree totale (hote) : $(( $(date +%s) - T0 )) s"
tr -d '\r' < "$W/out.txt" | grep -a "APERF\|KTEST: aperf\|ahci:\|Oops\|panique\|dbg\|readahead\|grouped\|ahci_"
RC=0
grep -aq "KTEST: aperf DONE" "$W/out.txt" || { echo "aperf DONE absent"; RC=1; }
grep -aq "KTEST: aperf.* FAIL" "$W/out.txt" && RC=1
# garde-fou de performance : peu de commandes (grosses commandes, groupees, lecture
# anticipee) et peu d'acces de registres (fin de commande par IRQ)
tr -d '\r' < "$W/out.txt" | grep -a "^APERF" | awk -v mb=$MB -v emb=$EXTMB '
  { n = $5; for (i = 1; i <= NF; i++) { if ($i == "commandes") c = $(i+1); if ($i == "registres") r = $(i+1) }
    lim = ($2 == "brut") ? 1.5 * n + 4 : 6 * n + 16
    if (c + 0 > lim) { print "ECHEC : " $2 " " $3 " trop de commandes (" c " > " lim ")"; bad = 1 }
    if (c + 0 > 0 && r / c > 25) { print "ECHEC : " $2 " " $3 " trop d acces de registres par commande (" r / c ")"; bad = 1 } }
  END { exit bad }' || RC=1
e2fsck -fn "$W/a.img?offset=1048576" > "$W/fsck.txt" 2>&1 || { echo "e2fsck : ECHEC"; tail -5 "$W/fsck.txt"; RC=1; }
python3 - "$W/b.img" $MB <<'P' || { echo "verification hote du disque brut : ECHEC"; RC=1; }
import sys, array
mb = int(sys.argv[2])
base = array.array('I', [((k * 0x9E3779B1) ^ (k >> 5)) & 0xFFFFFFFF for k in range(262144)])
f = open(sys.argv[1], 'rb')
for k in range(mb):
    a = array.array('I'); a.frombytes(f.read(1 << 20))
    exp = array.array('I', base)
    for j in range(2048): exp[j * 128] = (((k << 11) | j) ^ 0xA5A50000) & 0xFFFFFFFF
    if a != exp: print("bloc %d different" % k); sys.exit(1)
P
if [ $RC = 0 ]; then echo "RESULTAT : SUCCES"; rm -rf "$W"; exit 0
else echo "RESULTAT : ECHEC (traces dans $W)"; exit 1; fi
