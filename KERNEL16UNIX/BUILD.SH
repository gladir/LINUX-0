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
#  2. assemble le MBR et l'amorce UFS (nasm), si nasm est present (sinon les
#     fichiers MBR.BIN et UFSBOOT.BIN deja fournis sont utilises);
#  3. compile le noyau : LPC /K KERNEL.PAS -> KERNEL.SYS (copie sous le nom
#     unix a la racine des disques);
#  4. compile /etc/init, les programmes systeme de KERNEL16UNIX/USR (sh, getty,
#     login, passwd, ps, kill, id, mkdir, rmdir, rm, install) et toutes les
#     commandes LINUX-0 du depot (*.PAS) avec LPC /X (appels systeme
#     LINUX-0); le SH du depot (interpreteur de style DOS) est installe sous
#     le nom /bin/shdos. Une commande que LPC ne sait pas compiler donne un
#     avertissement (elle est absente des images) sans arreter la
#     construction;
#  5. fabrique les images (UFS1 seul, makefs -t ffs -o version=1) :
#       IMAGE/LINUX0-144.IMG  disquette 1,44 Mo : UFS1 sur toute la disquette
#                             (amorce UFSBOOT dans le secteur 0), commandes
#                             essentielles et les plus petites commandes
#       IMAGE/LINUX0-288.IMG  disquette 2,88 Mo : meme disposition, plus de
#                             commandes
#       IMAGE/LINUX0-HD.IMG   disque dur : partition 1 UFS1 active (A5h)
#                             avec UFSBOOT, le noyau /unix, toutes les
#                             commandes et les sources, partition 2 de
#                             va-et-vient (4 Mo, type 82h)
#       IMAGE/LINUX0-INST1.IMG, LINUX0-INST2.IMG...  distribution
#                             (disquette d'installation UFS1 et disquettes
#                             de volumes tar), IMAGE/LINUX0-CD.ISO (CD-ROM
#                             d'installation) : voir la fin du script.
#
#  Usage : KERNEL16UNIX/BUILD.SH            (depuis n'importe quel repertoire)
#  Variables : FPC (defaut fpc), NASM (defaut nasm), MAKEFS (defaut makefs),
#              W (repertoire de travail, defaut /tmp/linux0-build)
#  Execution : en root (ou sous fakeroot), pour que les fichiers de l'UFS1
#  appartiennent a root. Ce noyau n'a volontairement aucun support de FAT.
set -e
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/.." && pwd)
W=${W:-/tmp/linux0-build}
FPC=${FPC:-fpc}
NASM=${NASM:-nasm}
MAKEFS=${MAKEFS:-makefs}
command -v "$MAKEFS" >/dev/null || { echo "makefs introuvable (UFS1)"; exit 1; }
[ "$(id -u)" = 0 ] || echo "avertissement : pas root, les proprietaires UFS seront faux (utiliser fakeroot)"
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

echo "== Secteur de partition et amorce UFS"
if command -v "$NASM" >/dev/null; then
  $NASM -f bin -o "$HERE/MBR.BIN" "$HERE/MBR.ASM"
  $NASM -f bin -o "$HERE/UFSBOOT.BIN" "$HERE/UFSBOOT.ASM"
fi

echo "== Noyau"
cp "$HERE/KERNEL.PAS" "$W/src/"
( cd "$W/src" && "$LPC" /K KERNEL.PAS ) | tail -2

echo "== Programmes (LPC /X)"
cp "$ROOT"/*.PAS "$W/src/"
# les programmes systeme de USR remplacent les commandes de meme nom
cp "$HERE/INIT.PAS" "$HERE"/USR/*.PAS "$W/src/"
cp "$HERE"/USR/*.INC "$W/src/" 2>/dev/null || true
# une commande que LPC ne sait pas compiler est signalee puis ignoree
SKIPPED=
for f in "$W"/src/*.PAS; do
  n=$(basename "$f" .PAS)
  [ "$n" = KERNEL ] && continue
  if ! ( cd "$W/src" && "$LPC" /X "$n.PAS" > "$W/log/$n.log" 2>&1 ); then
    echo "AVERTISSEMENT $n ignore : $(grep -m1 -i 'erreur\|non implement' "$W/log/$n.log")"
    rm -f "$W/src/$n"
    SKIPPED="$SKIPPED $n"
  fi
done
# commandes compilees (hors noyau)
BUILT=$(cd "$W/src" && for f in *.PAS; do n=${f%.PAS}; [ "$n" = KERNEL ] || { [ -f "$n" ] && echo "$n"; }; done)
for n in INIT SHELL GETTY LOGIN INSTALL; do
  echo "$BUILT" | grep -qx $n || { echo "ECHEC : programme systeme $n absent"; exit 1; }
done
# les commandes LINUX-0 sont des executables COFF : verification
"$W/bin/coffinfo" $(echo "$BUILT" | sed "s|^|$W/src/|") > "$W/log/coff.log" ||
  { grep -B3 ERREUR "$W/log/coff.log"; exit 1; }
echo "   $(grep -c f_magic "$W/log/coff.log") executables COFF verifies; ignorees :${SKIPPED:- aucune}"

# arborescence commune
mkroot() {   # mkroot REPERTOIRE LISTE_DE_COMMANDES
  local d=$1 c; shift
  rm -rf "$d"; mkdir -p "$d/bin" "$d/etc" "$d/dev" "$d/tmp" "$d/usr/tmp" "$d/mnt" "$d/home"
  # le noyau est /unix, comme sous UNIX V7 (charge par UFSBOOT)
  cp "$W/src/KERNEL.SYS" "$d/unix"
  cp "$W/src/INIT" "$d/etc/init"
  cp "$W/src/GETTY" "$d/etc/getty"
  printf 'Bienvenue sous LINUX-0 !\n' > "$d/etc/motd"
  printf 'LINUX-0, le systeme UNIX 16 bits pour IBM PC.\n\n' > "$d/etc/issue"
  # /etc/passwd (format de UNIX V7) : root sans mot de passe, invite avec le
  # mot de passe "invite" (hachage de MKPASSWD, comme login et passwd)
  { printf 'root::0:0:Super-utilisateur:/:/bin/sh\n'
    printf 'invite:%s:100:100:Invite:/home/invite:/bin/sh\n' "$(crypt invite ab)"; } > "$d/etc/passwd"
  printf '10console\n' > "$d/etc/ttys"
  mkdir -p "$d/home/invite"
  for c in "$@"; do
    [ -f "$W/src/$c" ] || { echo "   (commande $c absente, ignoree)"; continue; }
    case $c in
      SHELL) cp "$W/src/$c" "$d/bin/sh" ;;
      SH)    cp "$W/src/$c" "$d/bin/shdos" ;;
      *)     cp "$W/src/$c" "$d/bin/$(echo "$c" | tr 'A-Z' 'a-z')" ;;
    esac
  done
}
# hachage des mots de passe (meme calcul que login et passwd)
crypt() { "$W/bin/mkpasswd" "$1" "$2"; }
# modes et proprietaires de l'UFS1 (permissions verifiees par le noyau) :
# executables 0755, passwd set-uid root (comme V7), /tmp 0777, repertoire de
# connexion de invite a l'utilisateur 100
setperms() {
  local d=$1
  chown -R 0:0 "$d"
  find "$d" -type d -exec chmod 755 {} +
  find "$d" -type f -exec chmod 644 {} +
  chmod 755 "$d"/bin/* "$d/etc/init" "$d/etc/getty"
  [ -f "$d/bin/passwd" ] && chmod 4755 "$d/bin/passwd"
  chmod 777 "$d/tmp" "$d/usr/tmp"
  chown -R 100:100 "$d/home/invite"
}
# floppyfs NOM TAILLE_KO ARBRE : UFS1 qui occupe toute la disquette
# (blocs de 4 Ko, fragments de 512 octets), amorce UFSBOOT dans le secteur 0
floppy() {
  setperms "$3"
  $MAKEFS -t ffs -o version=1,minfree=0,bsize=4096,fsize=512,density=4096 \
    -s ${2}k "$W/$1.ufs" "$3" > "$W/log/makefs-$1.log" ||
    { tail -5 "$W/log/makefs-$1.log"; echo "ECHEC makefs $1"; exit 1; }
  "$W/bin/mkimage" FLOPPY "$HERE/IMAGE/LINUX0-$1.IMG" "$HERE/UFSBOOT.BIN" "$W/$1.ufs" $2
}
ALL=$(echo "$BUILT" | grep -v -x -e INIT -e GETTY)
# commandes essentielles des disquettes (sur le disque dur : toutes)
CORE="SHELL LOGIN PASSWD PS KILL ID MKDIR RMDIR RM CAT LS ECHO CP MV REBOOT UNAME"

# les commandes (de 42 a 200 Ko chacune) sont trop nombreuses pour une
# disquette : les commandes essentielles, puis les plus petites jusqu'a
# remplir la disquette
fit() {   # fit OCTETS_DISPONIBLES COMMANDES_OBLIGATOIRES : liste complete
  local budget=$1 n sz list="$2"; shift 2
  for n in KERNEL.SYS INIT GETTY; do
    budget=$((budget - $(stat -c %s "$W/src/$n")))
  done
  for n in $list; do
    budget=$((budget - $(stat -c %s "$W/src/$n") - 1024))
  done
  for n in $(for n in $ALL; do echo "$(stat -c %s "$W/src/$n") $n"; done |
             sort -n | cut -d' ' -f2); do
    echo " $list " | grep -q " $n " && continue
    sz=$(( $(stat -c %s "$W/src/$n") + 1024 ))
    [ $sz -le $budget ] || continue
    budget=$((budget - sz)); list="$list $n"
  done
  echo $list
}

mkdir -p "$HERE/IMAGE"
rm -f "$HERE"/IMAGE/LINUX0-*.IMG "$HERE"/IMAGE/LINUX0-*.ISO
echo "== Disquette 1,44 Mo (UFS1)"
mkroot "$W/fd144" $(fit 1300000 "$CORE")
floppy 144 1440 "$W/fd144"
echo "== Disquette 2,88 Mo (UFS1)"
# (les interpreteurs BASH, CSH et KSH et les autres commandes sont sur le
# disque dur)
mkroot "$W/fd288" $(fit 2550000 "$CORE")
floppy 288 2880 "$W/fd288"
echo "== Disque dur (partition UFS1 amorcable + va-et-vient)"
mkroot "$W/hd" $ALL
mkdir -p "$W/hd/usr/src" "$W/hd/usr/doc"
cp "$ROOT"/*.PAS "$W/hd/usr/src/"
# les programmes systeme de USR remplacent les commandes de meme nom
cp "$HERE/KERNEL.PAS" "$HERE/INIT.PAS" "$HERE"/USR/*.PAS "$W/hd/usr/src/"
cp "$HERE/README.md" "$W/hd/usr/doc/" 2>/dev/null || true
rm -rf "$W/ufsroot"; mv "$W/hd" "$W/ufsroot"
setperms "$W/ufsroot"
$MAKEFS -t ffs -o version=1 -s 16m -f 1024 "$W/ufs.img" "$W/ufsroot" > "$W/log/makefs.log"
# UFSBOOT dans la zone d'amorce de la partition 1, partition 2 : zone de
# va-et-vient de 4 Mo (type 82h)
"$W/bin/mkimage" HD "$HERE/IMAGE/LINUX0-HD.IMG" "$HERE/MBR.BIN" "$HERE/UFSBOOT.BIN" "$W/ufs.img" 4

# ---------------------------------------------------------------------------
# distribution : disquettes d'installation et CD-ROM d'installation
#   LINUX0-INST1.IMG     disquette 1 (amorcable, UFS1) : noyau, init, getty,
#                       login, sh, install et quelques commandes; /mdec/mbr
#                       et /mdec/ufsboot (amorces du disque dur)
#   LINUX0-INST2.IMG...  disquettes de donnees : volumes tar de la racine
#                       complete (TOOLS/MKVOL.PAS), lus par install sur /dev/fd0
#   LINUX0-CD.ISO        CD-ROM El Torito (emulation de disque dur) : disque
#                       emule a une partition UFS1 (A5h) contenant le noyau,
#                       install et /dist (TOOLS/MKISO.PAS)
echo "== Distribution (installation)"
mkroot "$W/inst" SHELL LOGIN INSTALL LS CAT PS MKDIR RM ECHO REBOOT
mkdir -p "$W/inst/mdec"
cp "$HERE/MBR.BIN" "$W/inst/mdec/mbr"
cp "$HERE/UFSBOOT.BIN" "$W/inst/mdec/ufsboot"
{ printf 'root::0:0:Super-utilisateur:/:/bin/sh\n'
  printf 'install::0:0:Installation de LINUX-0:/:/bin/install\n'; } > "$W/inst/etc/passwd"
printf 'Pour installer LINUX-0 sur le disque dur, connectez-vous sous le nom\n"install" (root ouvre un interpreteur de commandes).\n\n' > "$W/inst/etc/issue"
printf 'Support d installation de LINUX-0.\n' > "$W/inst/etc/motd"
# volumes tar : l'arbre de la racine complete et la liste des fichiers avec
# type, mode, proprietaire, groupe et date (MKVOL n'a pas d'acces aux stat)
rm -rf "$W/vol"; mkdir -p "$W/vol"
( cd "$W/ufsroot" && find . -mindepth 1 -printf '%y %m %U %G %T@ %P\n' | LC_ALL=C sort -k6 ) > "$W/vol/LISTE"
"$W/bin/mkvol" "$W/ufsroot" "$W/vol/LISTE" "$W/vol/INST" 2 | tee "$W/log/mkvol.log"
for f in "$W"/vol/INST*.IMG; do cp "$f" "$HERE/IMAGE/LINUX0-$(basename "$f")"; done
floppy INST1 1440 "$W/inst"
NF=$(ls "$HERE"/IMAGE/LINUX0-INST*.IMG | wc -l)
echo "   $NF disquettes d'installation : LINUX0-INST1.IMG (amorce) a LINUX0-INST$NF.IMG"
# CD-ROM : disque emule d'une seule partition UFS1 (SeaBIOS et la plupart
# des BIOS ne dimensionnent le disque emule que d'apres la partition 1),
# sans zone de va-et-vient
rm -rf "$W/cd"; cp -a "$W/inst" "$W/cd"; mkdir -p "$W/cd/dist"
for f in "$W"/vol/INST*.TAR; do
  n=$(basename "$f" .TAR); cp "$f" "$W/cd/dist/vol${n#INST}.tar"
done
chown -R 0:0 "$W/cd"; chmod 755 "$W/cd/dist"; chmod 644 "$W/cd"/dist/*
$MAKEFS -t ffs -o version=1,minfree=0,density=16384 -s $(( ($(du -sk "$W/cd" | cut -f1) * 13 / 10 / 1024 + 2) ))m \
  "$W/cd.ufs" "$W/cd" > "$W/log/makefs-cd.log"
"$W/bin/mkimage" HD "$W/cdhd.img" "$HERE/MBR.BIN" "$HERE/UFSBOOT.BIN" "$W/cd.ufs" 0 > "$W/log/cdhd.log"
cp "$HERE/IMAGE/LISEZMOI.TXT" "$W/LISEZMOI.TXT"
"$W/bin/mkiso" "$HERE/IMAGE/LINUX0-CD.ISO" "$W/cdhd.img" "$W/LISEZMOI.TXT"
ls -l "$HERE/IMAGE"
