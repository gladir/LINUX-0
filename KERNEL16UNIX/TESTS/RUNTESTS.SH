#!/bin/bash
# @author: Sylvain Maltais (support@gladir.com)
# @created: 2026
# @website(https://www.gladir.com/linux-0)
# @description: Tests du noyau LINUX-0 sous QEMU (apres KERNEL16UNIX/BUILD.SH) :
#   chaque programme de test (TPROC, TFS, TSWAP : va-et-vient) est installe comme /etc/init sur une copie de
#   la racine UFS du disque dur, la console serie (COM1) est recueillie, puis
#   les systemes de
#   fichiers sont verifies : UFS1 par TOOLS/UFSCHK.PAS, FAT16 par fsck.vfat
#   (paquet dosfstools), s'il est present; enfin TESTS/SESSION.PY ouvre une
#   session complete (getty, login, sh) par la console serie, et INSTALL.PY
#   installe le systeme depuis les disquettes puis le CD-ROM.
#   Usage : KERNEL16UNIX/TESTS/RUNTESTS.SH   (W = repertoire de BUILD.SH)
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/.." && pwd)
W=${W:-/tmp/unix0-build}
[ -x "$W/bin/lpc" ] || { echo "lancer d'abord KERNEL16UNIX/BUILD.SH"; exit 2; }
T="$W/tests"; rm -rf "$T"; mkdir -p "$T"
fail=0
for t in TPROC TFS TSWAP; do
  cp "$HERE/$t.PAS" "$T/"
  ( cd "$T" && "$W/bin/lpc" /X $t.PAS > $t.log ) || { echo "ECHEC compilation $t"; fail=1; continue; }
  # le programme de test devient /etc/init de la racine UFS
  # (disposition FAT16 d'amorce + racine UFS : TFS ecrit aussi sur /boot)
  rm -rf "$T/root"; cp -a "$W/ufsroot" "$T/root"; cp "$T/$t" "$T/root/etc/init"
  mkdir -p "$T/root/boot"
  chmod 755 "$T/root/etc/init"
  ${MAKEFS:-makefs} -t ffs -o version=1 -s 16m -f 1024 "$T/ufs.img" "$T/root" > /dev/null
  "$W/bin/mkimage" HD "$T/$t.img" "$HERE/../MBR.BIN" "$HERE/../BOOTSECT.BIN" \
    "$W/hdboot" 16 "$T/ufs.img" 4 > /dev/null
  rm -f "$T/$t.out"
  timeout 90 qemu-system-i386 -m 1 -display none -no-reboot -boot c \
    -drive file="$T/$t.img",format=raw,if=ide -serial file:"$T/$t.out" 2>/dev/null &
  Q=$!
  for i in $(seq 1 85); do grep -q "TERMINE\|panique" "$T/$t.out" 2>/dev/null && break; sleep 1; done
  sleep 1; kill $Q 2>/dev/null; wait $Q 2>/dev/null
  sed -n '/^==/,$p' "$T/$t.out" | grep -v "tour"
  if ! grep -q TERMINE "$T/$t.out" || grep -q "ECHEC\|panique" "$T/$t.out"; then
    echo "ECHEC $t"; fail=1
  else echo "OK $t"; fi
  if [ $t = TFS ]; then
    "$W/bin/ufschk" --hd "$T/$t.img" | tail -1 | sed 's/^/UFS : /'
    "$W/bin/ufschk" --hd "$T/$t.img" > /dev/null || fail=1
    if command -v fsck.vfat > /dev/null; then
      dd if="$T/$t.img" of="$T/fat.img" bs=512 skip=63 count=$(od -An -tu4 -j458 -N4 "$T/$t.img" | tr -d " ") 2>/dev/null
      if fsck.vfat -n "$T/fat.img" > "$T/fsck.log" 2>&1; then echo "FAT16 : fsck.vfat sans erreur"
      else echo "FAT16 : fsck.vfat signale des erreurs"; cat "$T/fsck.log"; fail=1; fi
    fi
  fi
done
# session complete : getty, login, sh (console serie)
echo "== Session (getty, login, sh)"
python3 "$HERE/SESSION.PY" "$HERE/../IMAGE/LINUX0-HD.IMG" > "$T/session.out" 2>&1 || fail=1
grep -c "^ok" "$T/session.out" | sed 's/^/controles reussis : /'
grep "^ECHEC" "$T/session.out"
tail -1 "$T/session.out"
# installation : disquettes et CD-ROM de IMAGE/ sur des disques vierges
echo "== Installation (disquettes, CD-ROM)"
python3 "$HERE/INSTALL.PY" "$HERE/../IMAGE" > "$T/install.out" 2>&1 || fail=1
grep -c "^ok" "$T/install.out" | sed 's/^/controles reussis : /'
grep "^ECHEC" "$T/install.out"
tail -1 "$T/install.out"
[ $fail = 0 ] && echo "Tous les tests passent." || { echo "Des tests echouent."; exit 1; }
