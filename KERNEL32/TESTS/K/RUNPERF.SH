#!/bin/bash
# @author: Sylvain Maltais (support@gladir.com)
# @created: 2026
# @website(https://www.gladir.com/linux-0)
# @description: Acces d'E/S et de MMIO du noyau mesures par les traces de QEMU
#   (cpu_in, cpu_out, memory_region_ops_*) : proxy du cout des VM-exit sous
#   Hyper-V/NEM. Demarrage (avec le lecteur de CD vide que QEMU et VirtualBox
#   presentent par defaut) : moins de 150000 acces ; repos : moins de 50 par
#   seconde ; plus la ligne de /proc/k32perf. Le programme /bin/idler dort.
#     RUNPERF.SH [-n]
HERE=$(cd "$(dirname "$0")" && pwd)
K32=$HERE/../..
LPC=${LPC:-/tmp/claude-0/work/k32/bin/lpc}
GEN=1; [ "$1" = -n ] && GEN=0
W=$(mktemp -d)
if [ $GEN = 1 ]; then
  "$HERE/build.sh" "$W/u" >/dev/null || exit 1
  python3 "$HERE/MKEMBED.PY" "$W/u" "$K32/KERNEL32.PAS" >/dev/null || exit 1
fi
cp "$K32/KERNEL32.PAS" "$W/"
(cd "$W" && "$LPC" -3K -q KERNEL32.PAS) || exit 1
for T in idle6 idle16; do
  timeout 60 qemu-system-i386 -kernel "$W/KERNEL32" -serial "file:$W/$T.out" -display none -m 64 -no-reboot \
    -trace "cpu_in" -trace "cpu_out" -trace "memory_region_ops_*" -D "$W/$T.log" \
    -append "console=ttyS0 init=/bin/idler $T k32power" 2>/dev/null
done
python3 - "$W" <<'P'
import re, collections, sys
w = sys.argv[1]
def cnt(f):
    c = collections.Counter(); n = 0
    for l in open(f, errors='replace'):
        if l.startswith('cpu_in') or l.startswith('cpu_out'):
            c['port'] += 1; n += 1
        elif l.startswith('memory_region_ops'):
            m = re.search(r"name '([^']*)'", l); c[m.group(1) if m else '?'] += 1; n += 1
    return n, c
n6, a = cnt(w + '/idle6.log'); n16, b = cnt(w + '/idle16.log')
# pcspk : lectures du port 61h pendant l'etalonnage du LAPIC (dure plus ou moins
# longtemps selon la charge de la machine, hors repos)
rate = ((n16 - b['pcspk']) - (n6 - a['pcspk'])) / 10.0
print("demarrage + 6 s : %d acces ; repos : %.1f acces/s" % (n6, rate))
for k, v in a.most_common(5): print("  %8d  %s" % (v, k))
sys.exit(0 if n6 < 150000 and rate < 50 else 1)
P
RC=$?
if [ $RC = 0 ]; then echo "RESULTAT : SUCCES"; rm -rf "$W"; else echo "RESULTAT : ECHEC (traces dans $W)"; fi
exit $RC
