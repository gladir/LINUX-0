#!/bin/bash
# @author: Sylvain Maltais (support@gladir.com)
# @created: 2026
# @website(https://www.gladir.com/linux-0)
# @description: Construit LINUX-0 et les images de disque amorcables de IMAGE/.
#
#  1. compile avec Free Pascal (fpc), sur la machine hote, le compilateur
#     Linux Pascal (TOOLS/LPC.PAS) et les outils de TOOLS : MKIMAGE (images
#     de disque), COFFINFO (verification des executables), UFSCHK
#     (verification UFS1), MKVOL (volumes tar), MKISO (CD-ROM El Torito) et
#     MKPASSWD (mots de passe de /etc/passwd);
#  2. assemble le secteur d'amorce et le MBR (nasm), si nasm est present
#     (sinon les fichiers BOOTSECT.BIN et MBR.BIN deja fournis sont utilises);
#  3. compile le noyau : LPC /K KERNEL.PAS -> KERNEL.SYS (copie sous le nom
#     UNIX a la racine des disques);
#  4. compile /etc/init, les programmes systeme de KERNEL16UNIX/USR (sh, getty,
#     login, passwd, ps, kill, id, mkdir, rmdir, rm) et toutes les commandes
#     LINUX-0 du depot (*.PAS) avec LPC /X (appels systeme LINUX-0); le SH du
#     depot (interpreteur de style DOS) est installe sous le nom /bin/shdos;
#  5. fabrique les images :
#       IMAGE/LINUX0-144.IMG  disquette 1,44 Mo FAT12 (commandes essentielles)
#       IMAGE/LINUX0-288.IMG  disquette 2,88 Mo FAT12 (commandes, sauf bash/csh/ksh)
#       IMAGE/LINUX0-HD.IMG   disque dur amorce sur UFS : partition 1 UFS1
#                             (FreeBSD, makefs -t ffs) avec UFSBOOT et le
#                             noyau /unix, partition 2 de va-et-vient (4 Mo);
#                             sans makefs, racine FAT16.
#
#  Usage : KERNEL16UNIX/BUILD.SH            (depuis n'importe quel repertoire)
#  Variables : FPC (defaut fpc), NASM (defaut nasm), MAKEFS (defaut makefs),
#              W (repertoire de travail, defaut /tmp/unix0-build)
set -e
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/.." && pwd)
W=${W:-/tmp/unix0-build}
FPC=${FPC:-fpc}
NASM=${NASM:-nasm}
MAKEFS=${MAKEFS:-makefs}
rm -rf "$W"; mkdir -p "$W/bin" "$W/src" "$W/log"

echo "== Outils (Free Pascal)"
# copies : TOOLS/UNIX.PAS (unite de LINUX-0) masquerait l'unite unix de FPC
mkdir -p "$W/tools"
for t in LPC MKIMAGE COFFINFO UFSCHK MKVOL MKISO MKPASSWD; do
  cp "$HERE/TOOLS/$t.PAS" "$W/tools/"
  l=$(echo $t | tr 'A-Z' 'a-z')
  case $t in LPC|MKIMAGE) m=-Mtp ;; *) m= ;; esac
  ( cd "$W/tools" && $FPC $m -O1 -FE"$W/bin" -o"$W/bin/$l" $t.PAS ) > "$W/log/$l.log" 2>&1 ||
    { tail -20 "$W/log/$l.log"; exit 1; }
done
rm -f "$W/bin"/*.o
LPC="$W/bin/lpc"

echo "== Secteurs d'amorce"
if command -v "$NASM" >/dev/null; then
  $NASM -f bin -o "$HERE/BOOTSECT.BIN" "$HERE/BOOTSECT.ASM"
  $NASM -f bin -o "$HERE/MBR.BIN" "$HERE/MBR.ASM"
  $NASM -f bin -o "$HERE/UFSBOOT.BIN" "$HERE/UFSBOOT.ASM"
fi

echo "== Noyau"
cp "$HERE/KERNEL.PAS" "$W/src/"
( cd "$W/src" && "$LPC" /K KERNEL.PAS ) | tail -2

echo "== Programmes (LPC /X)"
cp "$ROOT"/*.PAS "$W/src/"
# les programmes systeme de USR remplacent les commandes de meme nom
cp "$HERE/INIT.PAS" "$HERE"/USR/*.PAS "$HERE"/USR/*.INC "$W/src/"
fail=0
for f in "$W"/src/*.PAS; do
  n=$(basename "$f" .PAS)
  [ "$n" = KERNEL ] && continue
  if ! ( cd "$W/src" && "$LPC" /X "$n.PAS" > "$W/log/$n.log" 2>&1 ); then
    echo "ECHEC $n"; tail -2 "$W/log/$n.log"; fail=1
  fi
done
[ $fail = 0 ] || exit 1
# les commandes LINUX-0 sont des executables COFF : verification
"$W/bin/coffinfo" $(cd "$W/src" && ls *.PAS | sed 's/\.PAS$//' | grep -v -x KERNEL | sed "s|^|$W/src/|") > "$W/log/coff.log" ||
  { grep -B3 ERREUR "$W/log/coff.log"; exit 1; }
echo "   $(grep -c f_magic "$W/log/coff.log") executables COFF verifies"

# arborescence commune
mkroot() {   # mkroot REPERTOIRE LISTE_DE_COMMANDES
  local d=$1; shift
  rm -rf "$d"; mkdir -p "$d/bin" "$d/etc" "$d/dev" "$d/tmp" "$d/usr" "$d/mnt" "$d/home"
  cp "$W/src/KERNEL.SYS" "$d/UNIX"
  cp "$W/src/INIT" "$d/etc/init"
  cp "$W/src/GETTY" "$d/etc/getty"
  printf 'Bienvenue sous LINUX-0 !\n' > "$d/etc/motd"
  # /etc/passwd (format de UNIX V7) : root sans mot de passe, invite avec le
  # mot de passe "invite" (hachage de KERNEL16UNIX/USR/CRYPT.INC)
  { printf 'root::0:0:Super-utilisateur:/:/bin/sh\n'
    printf 'invite:%s:100:100:Invite:/home/invite:/bin/sh\n' "$(crypt invite ab)"; } > "$d/etc/passwd"
  printf '10console\n' > "$d/etc/ttys"
  mkdir -p "$d/home/invite"
  for c in "$@"; do
    case $c in
      SHELL) cp "$W/src/$c" "$d/bin/sh" ;;
      SH)    cp "$W/src/$c" "$d/bin/shdos" ;;
      *)     cp "$W/src/$c" "$d/bin/$(echo "$c" | tr 'A-Z' 'a-z')" ;;
    esac
  done
}
# hachage des mots de passe (meme calcul que KERNEL16UNIX/USR/CRYPT.INC)
crypt() { "$W/bin/mkpasswd" "$1" "$2"; }
ALL=$(cd "$W/src" && ls *.PAS | sed 's/\.PAS$//' | grep -v -x -e KERNEL -e INIT -e GETTY)
CORE="SHELL LOGIN PASSWD PS KILL ID MKDIR RMDIR RM CAT LS ECHO PWD CP MV CHMOD HEAD WC GREP DF UNAME REBOOT"

mkdir -p "$HERE/IMAGE"
echo "== Disquette 1,44 Mo"
mkroot "$W/fd144" $CORE
"$W/bin/mkimage" FLOPPY "$HERE/IMAGE/LINUX0-144.IMG" "$HERE/BOOTSECT.BIN" "$W/fd144" 1440
echo "== Disquette 2,88 Mo"
# sans les interpreteurs de style DOS BASH, CSH et KSH (sur le disque dur)
mkroot "$W/fd288" $(echo $ALL | tr ' ' '\n' | grep -v -x -e BASH -e CSH -e KSH)
"$W/bin/mkimage" FLOPPY "$HERE/IMAGE/LINUX0-288.IMG" "$HERE/BOOTSECT.BIN" "$W/fd288" 2880
echo "== Disque dur (FAT16 d'amorce + racine UFS)"
mkroot "$W/hd" $ALL
# modes et proprietaires de la racine UFS (permissions verifiees par le
# noyau) : executables 0755, passwd set-uid root (comme V7), /tmp 0777,
# repertoire de connexion de invite a l'utilisateur 100
setperms() {
  local d=$1
  chown -R 0:0 "$d"
  find "$d" -type d -exec chmod 755 {} +
  find "$d" -type f -exec chmod 644 {} +
  chmod 755 "$d"/bin/* "$d/etc/init" "$d/etc/getty"
  chmod 4755 "$d/bin/passwd"
  chmod 777 "$d/tmp" "$d/usr/tmp"
  chown -R 100:100 "$d/home/invite"
}
if command -v "$MAKEFS" >/dev/null; then
  # racine : partition UFS1 (FreeBSD) avec toute l'arborescence; la
  # partition FAT16 d'amorce ne contient que le noyau (montee sur /boot)
  # le noyau est /unix, comme sous UNIX V7 (charge par UFSBOOT)
  rm -rf "$W/ufsroot"; cp -a "$W/hd" "$W/ufsroot"; mv "$W/ufsroot/UNIX" "$W/ufsroot/unix"
  mkdir -p "$W/ufsroot/usr/src" "$W/ufsroot/usr/doc" "$W/ufsroot/usr/tmp"
  cp "$ROOT"/*.PAS "$HERE/KERNEL.PAS" "$HERE/INIT.PAS" "$HERE"/USR/*.PAS "$W/ufsroot/usr/src/"
  cp "$HERE/README.md" "$W/ufsroot/usr/doc/" 2>/dev/null || true
  setperms "$W/ufsroot"
  $MAKEFS -t ffs -o version=1 -s 16m -f 1024 "$W/ufs.img" "$W/ufsroot" > "$W/log/makefs.log"
  # partition FAT16 d'amorce (disposition FAT16 + UFS des tests)
  rm -rf "$W/hdboot"; mkdir -p "$W/hdboot"; cp "$W/src/KERNEL.SYS" "$W/hdboot/UNIX"
  # disque dur amorce directement sur UFS (UFSBOOT dans la zone d'amorce de
  # la partition 1), partition 2 : zone de va-et-vient de 4 Mo (type 82h)
  "$W/bin/mkimage" UFS "$HERE/IMAGE/LINUX0-HD.IMG" "$HERE/MBR.BIN" "$HERE/UFSBOOT.BIN" "$W/ufs.img" 4
else
  echo "   (makefs absent : racine FAT16, sans partition UFS)"
  "$W/bin/mkimage" HD "$HERE/IMAGE/LINUX0-HD.IMG" "$HERE/MBR.BIN" "$HERE/BOOTSECT.BIN" "$W/hd" 24
fi

# ---------------------------------------------------------------------------
# distribution : disquettes d'installation et CD-ROM d'installation
#   LINUX0-INST1.IMG     disquette 1 (amorcable) : noyau, init, getty, login,
#                       sh, install et quelques commandes; /mdec/mbr et
#                       /mdec/bootsect (secteurs d'amorce du disque dur)
#   LINUX0-INST2.IMG...  disquettes de donnees : volumes tar de la racine
#                       complete (TOOLS/MKVOL.PAS), lus par install sur /dev/fd0
#   LINUX0-CD.ISO        CD-ROM El Torito (emulation de disque dur) : la
#                       disquette 1 et les volumes dans /dist (TOOLS/MKISO.PAS)
if [ -d "$W/ufsroot" ]; then
  echo "== Distribution (installation)"
  rm -f "$HERE"/IMAGE/LINUX0-INST*.IMG
  mkroot "$W/inst" SHELL LOGIN INSTALL LS CAT PS MKDIR RM ECHO REBOOT
  mkdir -p "$W/inst/mdec"
  cp "$HERE/MBR.BIN" "$W/inst/mdec/mbr"; cp "$HERE/BOOTSECT.BIN" "$W/inst/mdec/bootsect"
  cp "$HERE/UFSBOOT.BIN" "$W/inst/mdec/ufsboot"
  { printf 'root::0:0:Super-utilisateur:/:/bin/sh\n'
    printf 'install::0:0:Installation de LINUX-0:/:/bin/install\n'; } > "$W/inst/etc/passwd"
  printf 'Pour installer LINUX-0 sur le disque dur, connectez-vous sous le nom\n"install" (root ouvre un interpreteur de commandes).\n\n' > "$W/inst/etc/issue"
  printf 'Support d installation de LINUX-0.\n' > "$W/inst/etc/motd"
  rm -rf "$W/vol"; mkdir -p "$W/vol"
  "$W/bin/mkvol" "$W/ufsroot" "$W/vol/INST" 2 | tee "$W/log/mkvol.log"
  for f in "$W"/vol/INST*.IMG; do cp "$f" "$HERE/IMAGE/LINUX0-$(basename "$f")"; done
  "$W/bin/mkimage" FLOPPY "$HERE/IMAGE/LINUX0-INST1.IMG" "$HERE/BOOTSECT.BIN" "$W/inst" 1440
  NF=$(ls "$HERE"/IMAGE/LINUX0-INST*.IMG | wc -l)
  echo "   $NF disquettes d'installation : LINUX0-INST1.IMG (amorce) a LINUX0-INST$NF.IMG"
  # CD-ROM : disque emule d'une seule partition FAT16 (SeaBIOS et la plupart
  # des BIOS ne dimensionnent le disque emule que d'apres la partition 1)
  rm -rf "$W/cd"; cp -a "$W/inst" "$W/cd"; mkdir -p "$W/cd/dist"
  for f in "$W"/vol/INST*.TAR; do
    n=$(basename "$f" .TAR); cp "$f" "$W/cd/dist/vol${n#INST}.tar"
  done
  "$W/bin/mkimage" HD "$W/cdhd.img" "$HERE/MBR.BIN" "$HERE/BOOTSECT.BIN" "$W/cd" 8 > "$W/log/cdhd.log"
  cp "$HERE/IMAGE/LISEZMOI.TXT" "$W/LISEZMOI.TXT"
  "$W/bin/mkiso" "$HERE/IMAGE/LINUX0-CD.ISO" "$W/cdhd.img" "$W/LISEZMOI.TXT"
fi
ls -l "$HERE/IMAGE"
