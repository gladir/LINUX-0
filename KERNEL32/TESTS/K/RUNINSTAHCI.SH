#!/bin/bash
# @author: Sylvain Maltais (support@gladir.com)
# @created: 2026
# @website(https://www.gladir.com/linux-0)
# @description: Installation complete (CD d'installation, mode texte, preseed)
#   sur un disque AHCI/SATA de 8 Go creux, comme sous VirtualBox : QEMU avec
#   ich9-ahci + ide-hd, 1024 Mo, 1 CPU ; mkfs.ext4 de la racine (7935 Mo) et
#   swap de 256 Mo, puis e2fsck -fn. Variables : MEM (1024), SIZE (8192 Mo),
#   CPU (qemu64), ACCEL (tcg), FMT (raw ou qcow2 si qemu-img existe), NCQ,
#   FS (ext4), SWAP (256), W (travail), RUNOPT (options QEMU en plus).
#     RUNINSTAHCI.SH
HERE=$(cd "$(dirname "$0")" && pwd)
K32=$HERE/../..
LPC=${LPC:-/tmp/claude-0/work/k32/bin/lpc}
W=${W:-/tmp/linux0-ahci8g}
MEM=${MEM:-1024}; SIZE=${SIZE:-8192}; CPU=${CPU:-qemu64}; ACCEL=${ACCEL:-tcg}
FS=${FS:-ext4}; SWAP=${SWAP:-256}
mkdir -p "$W"
if [ ! -d "$W/build/root" ]; then
  echo "== racine du systeme"
  ( cd "$K32" && ROOTONLY=1 LPC=$LPC W=$W/build ./BUILD.SH ) > "$W/build.log" 2>&1 ||
    { echo "ECHEC BUILD.SH"; exit 1; }
fi
echo "== noyau de production"
"$K32/TOOLS/MKPROD.SH" -l "$LPC" -s "${KSRC:-$K32/KERNEL32.PAS}" -o "$W/K.ELF" >/dev/null ||
  { echo "ECHEC MKPROD"; exit 1; }
mkdir -p "$W/extra"
cat > "$W/extra/preseed.cfg" <<P
lang=fr
keyboard=fr
timezone=Europe/Paris
hostname=ahci8g
rootpw=clave
user=ana
userpw=clave2
partitioning=guided
swap=$SWAP
fs=$FS
ui=text
endwait=2
reboot=halt
P
LPC=$LPC "$K32/TOOLS/MKINSTALLCD.SH" -o "$W/i.iso" -R "$W/build/root" -k "$W/K.ELF" \
  -r "$W/extra" -c "console=tty0 console=ttyS0 rw preseed=/cdrom/preseed.cfg k32setup.verbose=/dev/ttyS0" \
  -w "$W/cdw" >/dev/null || { echo "ECHEC MKINSTALLCD"; exit 1; }
rm -f "$W/d.img" "$W/out.txt"
truncate -s ${SIZE}M "$W/d.img"
NCQ=${NCQ:-}
echo "== QEMU ($ACCEL, $CPU, $MEM Mo, AHCI ${SIZE} Mo)"
timeout ${TMO:-1500} qemu-system-i386 -accel $ACCEL -cpu $CPU -smp 1 -m $MEM \
  -cdrom "$W/i.iso" -boot d -display none -vga std -no-reboot -serial "file:$W/out.txt" \
  -device ich9-ahci,id=ahci -drive "file=$W/d.img,format=raw,if=none,id=d0" \
  -device ide-hd,drive=d0,bus=ahci.0 $RUNOPT 2>/dev/null
tr -d '\r' < "$W/out.txt" > "$W/o.txt"
grep -a "K32SETUP\|Oops\|panique\|ahci:\|erreur" "$W/o.txt" | tail -15
if grep -aq "K32SETUP: DONE" "$W/o.txt"; then OK=1; else OK=0; fi
python3 - "$W/d.img" <<'Q' > "$W/part.txt"
import struct, sys
d = open(sys.argv[1], 'rb').read(512)
for i in range(4):
    e = d[446 + 16 * i: 462 + 16 * i]
    t = e[4]; s, n = struct.unpack('<II', e[8:16])
    if t: print(i + 1, hex(t), s, n)
Q
cat "$W/part.txt"
RC=1
if [ $OK = 1 ]; then
  read -r _ _ S N < <(head -1 "$W/part.txt")
  e2fsck -fn "$W/d.img?offset=$((S * 512))" > "$W/fsck.txt" 2>&1 && RC=0
  tail -3 "$W/fsck.txt"
fi
[ $RC = 0 ] && echo "RESULTAT : SUCCES" || echo "RESULTAT : ECHEC (traces dans $W)"
exit $RC
