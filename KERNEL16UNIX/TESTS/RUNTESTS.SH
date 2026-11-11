#!/bin/bash
# @author: Sylvain Maltais (support@gladir.com)
# @created: 2026
# @website(https://www.gladir.com/linux-0)
# @description: Tests du noyau LINUX-0 sous QEMU (apres KERNEL16UNIX/BUILD.SH).
#   Chaque programme de test (TPROC : processus, TFS : UFS, TSWAP : va-et-vient)
#   est installe comme /etc/init sur une copie de la racine UFS du disque
#   dur, la console serie (COM1) est recueillie, puis le systeme de fichiers
#   est verifie par TOOLS/UFSCHK.PAS. TFS est aussi essaye sur une disquette
#   UFS1 de 2,88 Mo (racine UFS sur toute la disquette, sans MBR). Ensuite
#   TESTS/SESSION.PY ouvre une session complete (getty, login, sh) sur le
#   disque dur puis sur la disquette de 1,44 Mo par la console serie, et
#   INSTALL.PY installe le systeme depuis les disquettes puis depuis le CD-ROM.
#   Il n'y a pas de FAT dans ce noyau : les disques et disquettes sont UFS1.
#   Usage : KERNEL16UNIX/TESTS/RUNTESTS.SH   (W = repertoire de BUILD.SH)
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/.." && pwd)
W=${W:-/tmp/linux0-build}
IMG="$ROOT/IMAGE"
[ -x "$W/bin/lpc" ] || { echo "lancer d'abord KERNEL16UNIX/BUILD.SH"; exit 2; }
T="$W/tests"; rm -rf "$T"; mkdir -p "$T"
fail=0

# racine de test : copie de la racine du disque dur sans les sources, avec
# le programme $1 comme /etc/init
testroot() {
  rm -rf "$T/root"; cp -a "$W/ufsroot" "$T/root"; rm -rf "$T/root/usr/src"
  cp "$T/$1" "$T/root/etc/init"; chmod 755 "$T/root/etc/init"
}
# attend TERMINE ou panique sur la console serie $1 (au plus $2 secondes)
waitend() {
  for i in $(seq 1 $2); do
    grep -q "TERMINE\|panique" "$1" 2>/dev/null && break; sleep 1
  done
  sleep 1
}
report() {   # report NOM FICHIER_SERIE
  sed -n '/^==/,$p' "$2" | grep -v "tour"
  if ! grep -q TERMINE "$2" || grep -q "ECHEC\|panique" "$2"; then
    echo "ECHEC $1"; fail=1
  else echo "OK $1"; fi
}

for t in TPROC TFS TSWAP; do
  cp "$HERE/$t.PAS" "$T/"
  ( cd "$T" && "$W/bin/lpc" /X $t.PAS > $t.log ) || { echo "ECHEC compilation $t"; fail=1; continue; }
  testroot $t
  ${MAKEFS:-makefs} -t ffs -o version=1 -s 16m -f 1024 "$T/ufs.img" "$T/root" > /dev/null
  "$W/bin/mkimage" HD "$T/$t.img" "$HERE/../MBR.BIN" "$HERE/../UFSBOOT.BIN" \
    "$T/ufs.img" 4 > /dev/null
  rm -f "$T/$t.out"
  timeout 90 qemu-system-i386 -m 1 -display none -no-reboot -boot c \
    -drive file="$T/$t.img",format=raw,if=ide -serial file:"$T/$t.out" 2>/dev/null &
  Q=$!
  waitend "$T/$t.out" 85
  kill $Q 2>/dev/null; wait $Q 2>/dev/null
  report "$t (disque dur)" "$T/$t.out"
  if [ $t = TFS ]; then
    "$W/bin/ufschk" --hd "$T/$t.img" | tail -1 | sed 's/^/UFS : /'
    "$W/bin/ufschk" --hd "$T/$t.img" > /dev/null || fail=1
  fi
done

# TFS sur une disquette UFS1 de 2,88 Mo : racine UFS sur toute la disquette
echo "== TFS sur une disquette UFS1 (2,88 Mo)"
rm -rf "$T/fdroot"; mkdir -p "$T/fdroot"/{etc,dev,usr,tmp,mnt}
cp "$W/src/KERNEL.SYS" "$T/fdroot/unix"; cp "$T/TFS" "$T/fdroot/etc/init"
chmod 755 "$T/fdroot/etc/init"; chmod 777 "$T/fdroot/tmp"
${MAKEFS:-makefs} -t ffs -o version=1,minfree=0,bsize=4096,fsize=512,density=4096 \
  -s 2880k "$T/fd.ufs" "$T/fdroot" > /dev/null
"$W/bin/mkimage" FLOPPY "$T/TFSFD.img" "$HERE/../UFSBOOT.BIN" "$T/fd.ufs" 2880 > /dev/null
rm -f "$T/TFSFD.out"
timeout 120 qemu-system-i386 -m 1 -display none -no-reboot -boot a \
  -drive file="$T/TFSFD.img",format=raw,if=floppy -serial file:"$T/TFSFD.out" 2>/dev/null &
Q=$!
waitend "$T/TFSFD.out" 110
kill $Q 2>/dev/null; wait $Q 2>/dev/null
grep -q "racine : /dev/fd0 (UFS1)" "$T/TFSFD.out" || { echo "ECHEC racine fd0"; fail=1; }
report "TFS (disquette UFS1)" "$T/TFSFD.out"
"$W/bin/ufschk" --floppy "$T/TFSFD.img" | tail -1 | sed 's/^/UFS : /'
"$W/bin/ufschk" --floppy "$T/TFSFD.img" > /dev/null || fail=1

# session complete : getty, login, sh (console serie)
echo "== Session (getty, login, sh) sur le disque dur"
python3 "$HERE/SESSION.PY" "$IMG/LINUX0-HD.IMG" > "$T/session.out" 2>&1 || fail=1
grep -c "^ok" "$T/session.out" | sed 's/^/controles reussis : /'
grep "^ECHEC" "$T/session.out"
tail -1 "$T/session.out"
echo "== Session sur les disquettes UFS1 (1,44 Mo, 2,88 Mo)"
for f in 144 288; do
  python3 "$HERE/SESSION.PY" "$IMG/LINUX0-$f.IMG" floppy > "$T/session$f.out" 2>&1 || fail=1
  grep -c "^ok" "$T/session$f.out" | sed "s/^/$f : controles reussis : /"
  grep "^ECHEC" "$T/session$f.out"
  tail -1 "$T/session$f.out"
done
# installation : disquettes et CD-ROM de IMAGE/ sur des disques vierges
echo "== Installation (disquettes, CD-ROM)"
python3 "$HERE/INSTALL.PY" "$IMG" > "$T/install.out" 2>&1 || fail=1
grep -c "^ok" "$T/install.out" | sed 's/^/controles reussis : /'
grep "^ECHEC" "$T/install.out"
tail -1 "$T/install.out"
[ $fail = 0 ] && echo "Tous les tests passent." || { echo "Des tests echouent."; exit 1; }
