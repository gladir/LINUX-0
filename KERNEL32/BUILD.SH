#!/bin/bash
# @author: Sylvain Maltais (support@gladir.com)
# @created: 2026
# @website(https://www.gladir.com/linux-0)
# @description: Construit KERNEL32 (noyau LINUX-0 32 bits) et son image de
#   disque dur amorcable IMAGE/LINUX32-HD.IMG (MBR + partition ext2).
#
#  1. outils hote : compile avec Free Pascal (fpc -Mtp -O1) le compilateur
#     TOOLS/LPC.PAS (ou utilise LPC=... s'il est deja construit);
#  2. amorce : assemble le MBR et la tete du chargeur (nasm), compile le
#     corps du chargeur BOOT/LOADER.PAS (lpc -K0840) et les assemble en
#     BOOT/STAGE2.BIN. Sans nasm ou si LPC ne sait pas compiler le chargeur,
#     les fichiers BOOT/*.BIN fournis sont utilises;
#  3. noyau : lpc -3K KERNEL32.PAS -> ELF32 (copie en /boot/linux0), ou, avec
#     TESTKERNEL=1 (ou si KERNEL32.PAS n'existe pas encore), le noyau de test
#     TESTS/B/TESTK.ASM;
#  4. programmes de USR/*.PAS : lpc -3X, ranges dans la racine du disque
#     (USR/INIT.PAS -> /sbin/init, USR/SH.PAS -> /bin/sh ...; tout autre
#     USR/NOM.PAS -> /bin/nom). Boucle tolerante s'il n'y en a pas encore;
#  5. cree IMAGE/LINUX32-HD.IMG par TOOLS/MKIMAGE.SH (MBR + chargeur + ext2).
#
#  Usage : KERNEL32/BUILD.SH [boot]       ("boot" : etape 2 seulement)
#  Variables : W (dossier de travail, defaut /tmp/linux32-build), FPC, NASM,
#              LPC (compilateur deja construit), TESTKERNEL=1, MB (taille du
#              disque en Mo, defaut 64), BS (blocs ext2, defaut 1024), INODE
#              (taille d'inode, defaut 128), CMDLINE (ligne de commande du
#              noyau, defaut celle du chargeur : root=/dev/hda1 ro).
set -e
HERE=$(cd "$(dirname "$0")" && pwd)
W=${W:-/tmp/linux32-build}
FPC=${FPC:-fpc}
NASM=${NASM:-nasm}
MB=${MB:-64}
BS=${BS:-1024}
INODE=${INODE:-128}
mkdir -p "$W/bin" "$W/log" "$W/root"

echo "== Outils (Free Pascal)"
if [ -z "$LPC" ]; then
  mkdir -p "$W/tools"
  cp "$HERE"/TOOLS/LPC*.PAS "$HERE"/TOOLS/L32*.PAS "$W/tools/"
  ( cd "$W/tools" && $FPC -Mtp -O1 -FE"$W/bin" -o"$W/bin/lpc" LPC.PAS ) \
    > "$W/log/lpc.log" 2>&1 || { tail -20 "$W/log/lpc.log"; exit 1; }
  rm -f "$W/bin"/*.o "$W/bin"/*.ppu "$W/tools"/*.o "$W/tools"/*.ppu
  LPC="$W/bin/lpc"
fi

echo "== Amorce (MBR, chargeur)"
B="$HERE/BOOT"
if command -v "$NASM" >/dev/null; then
  $NASM -f bin -o "$B/MBR.BIN" "$B/MBR.ASM"
  $NASM -f bin -o "$B/STAGE2H.BIN" "$B/STAGE2.ASM"
fi
mkdir -p "$W/loader"
cp "$B/LOADER.PAS" "$W/loader/"
if ( cd "$W/loader" && "$LPC" -K0840 -q LOADER.PAS ) \
     > "$W/log/loader.log" 2>&1 && [ -f "$W/loader/LOADER.SYS" ]; then
  cp "$W/loader/LOADER.SYS" "$B/LOADER.SYS"
else
  echo "   avertissement : LOADER.PAS non compile" \
    "($(tail -1 "$W/log/loader.log")), LOADER.SYS fourni utilise"
fi
cat "$B/STAGE2H.BIN" "$B/LOADER.SYS" > "$B/STAGE2.BIN"
echo "   MBR.BIN 512 octets ; STAGE2.BIN $(stat -c %s "$B/STAGE2.BIN") octets"
[ "$1" = boot ] && exit 0

echo "== Noyau"
KERNEL=
if [ -z "$TESTKERNEL" ] && [ -f "$HERE/KERNEL32.PAS" ]; then
  mkdir -p "$W/src"
  cp "$HERE/KERNEL32.PAS" "$W/src/"
  ( cd "$W/src" && "$LPC" -3K -q KERNEL32.PAS ) || exit 1
  KERNEL="$W/src/KERNEL32"
else
  echo "   (noyau de test TESTS/B/TESTK.ASM)"
  "$HERE/TESTS/B/MKTESTK.SH" "$W/testk" > "$W/log/testk.log"
  KERNEL="$W/testk/TESTK.ELF"
fi

echo "== Programmes (LPC -3X)"
rm -rf "$W/root"; mkdir -p "$W/root/sbin" "$W/root/bin" "$W/root/etc" \
  "$W/root/dev" "$W/root/tmp" "$W/root/proc" "$W/root/boot"
N=0
for f in "$HERE"/USR/*.PAS; do
  [ -f "$f" ] || continue
  n=$(basename "$f" .PAS)
  mkdir -p "$W/usr"; cp "$f" "$W/usr/"
  if ( cd "$W/usr" && "$LPC" -3X -q "$n.PAS" ) > "$W/log/$n.log" 2>&1; then
    case $n in
      INIT) install -m 755 "$W/usr/$n" "$W/root/sbin/init" ;;
      *) install -m 755 "$W/usr/$n" "$W/root/bin/$(echo $n | tr A-Z a-z)" ;;
    esac
    N=$((N + 1))
  else
    echo "   avertissement : $n ignore ($(tail -1 "$W/log/$n.log"))"
  fi
done
echo "   $N programme(s)"
[ -f "$HERE/USR/INIT.PAS" ] || true

echo "== Image disque"
mkdir -p "$HERE/IMAGE"
"$HERE/TOOLS/MKIMAGE.SH" -o "$HERE/IMAGE/LINUX32-HD.IMG" -k "$KERNEL" \
  -r "$W/root" -s "$MB" -b "$BS" -i "$INODE" ${CMDLINE:+-c "$CMDLINE"}
echo "Essai : qemu-system-i386 -m 64" \
  "-drive file=IMAGE/LINUX32-HD.IMG,format=raw,if=ide"
