#!/bin/bash
# @author: Sylvain Maltais (support@gladir.com)
# @created: 2026
# @website(https://www.gladir.com/linux-0)
# @description: Disque AHCI de 8 Go creux (>2 Gio : _llseek, ecriture/lecture a
#   2 Gio, 4 Gio, fin de disque : bdtest) puis erreur d'E/S injectee par
#   blkdebug sur le secteur 100000 : le pilote doit journaliser
#   "ahci: port 0 erreur ...", remettre le port en etat et reessayer.
#     RUNAHCIERR.SH [-n]   (-n : ne pas regenerer les programmes embarques)
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
truncate -s 8G "$W/d.img"
cat > "$W/bd.conf" <<C
[inject-error]
event = "write_aio"
errno = "5"
sector = "100000"
once = "on"
C
timeout 60 qemu-system-i386 -kernel "$W/KERNEL32" -serial "file:$W/out.txt" -display none \
  -m 1024 -no-reboot -append "console=ttyS0 init=/bin/bdtest aherr k32power" \
  -drive "file=blkdebug:$W/bd.conf:$W/d.img,format=raw,if=none,id=d0" \
  -device ich9-ahci,id=ahci -device ide-hd,drive=d0,bus=ahci.0 2>/dev/null
tr -d '\r' < "$W/out.txt" | grep -a "KTEST: bd\|ahci:\|Oops\|panique"
N=$(grep -ac "KTEST: bd.* OK" "$W/out.txt")
if grep -aq "KTEST: bd.* FAIL" "$W/out.txt" || [ "$N" -lt 8 ] || ! grep -aq "ahci: port 0 erreur" "$W/out.txt"; then
  echo "RESULTAT : ECHEC (traces dans $W)"; exit 1
fi
echo "RESULTAT : SUCCES"; rm -rf "$W"; exit 0
