#!/bin/bash
# @author: Sylvain Maltais (support@gladir.com)
# @created: 2026
# @website(https://www.gladir.com/linux-0)
# @description: Cree une image de disque dur amorcable de KERNEL32 :
#     MBR (BOOT/MBR.BIN) + table des partitions + chargeur (BOOT/STAGE2.BIN,
#     secteurs 1 a N, juste apres le MBR) + partition 1 (type 83h, active,
#     debut au secteur 2048 = 1 Mo) formatee en ext2 et remplie avec la
#     racine fournie et le noyau /boot/linux0.
#
#   MKIMAGE.SH -o IMAGE.IMG [-k NOYAU.ELF] [-r RACINE] [-s Mo]
#              [-b 1024|2048|4096] [-i 128|256] [-c "ligne de commande"]
#              [-N entrees] [-S debut] [-C] [-R 0|1]
#     -o  image a creer
#     -k  noyau ELF32 (copie en /boot/linux0)
#     -r  repertoire dont le contenu devient la racine de l'ext2
#     -s  taille du disque en Mo (defaut 64)
#     -b  taille des blocs ext2 (defaut 1024)
#     -i  taille des inodes (defaut 128)
#     -c  ecrit /boot/linux0.cfg avec cmdline=...
#     -N  /boot : cree ce nombre de fichiers vides (essai des gros repertoires)
#     -S  premier secteur de la partition (defaut 2048)
#     -R  revision ext2 : 1 (defaut, inodes de taille -i) ou 0 (inodes de 128)
#     -C  le MBR charge le chargeur en CHS (essai du repli sans extensions)
#
#   Ligne mke2fs exacte (simple pour le chargeur et pour le noyau : inodes de
#   128 octets, revision 1, sans journal, sans dir_index, sans ext_attr, sans
#   resize_inode ; seules les fonctions filetype et sparse_super restent) :
#     mke2fs -q -F -t ext2 -b BLOC -I INODE -r 1 -m 0 -L LINUX0 \
#            -O none,filetype,sparse_super \
#            -E offset=OCTETS,root_owner=0:0 -d STAGE IMAGE BLOCS
#   Variables : MBR, STAGE2 (defaut BOOT/MBR.BIN et BOOT/STAGE2.BIN).
set -e
HERE=$(cd "$(dirname "$0")" && pwd)
BOOT="$HERE/../BOOT"
MBR=${MBR:-$BOOT/MBR.BIN}
STAGE2=${STAGE2:-$BOOT/STAGE2.BIN}
OUT= ; KERNEL= ; ROOT= ; MB=64 ; BS=1024 ; INO=128 ; CMD= ; NFILES=0
START=2048 ; FORCECHS=0 ; REV=1
usage() { sed -n '11,26p' "$0"; exit 2; }
while getopts "o:k:r:s:b:i:c:N:S:CR:" o; do
  case $o in
    o) OUT=$OPTARG ;; k) KERNEL=$OPTARG ;; r) ROOT=$OPTARG ;;
    s) MB=$OPTARG ;; b) BS=$OPTARG ;; i) INO=$OPTARG ;; c) CMD=$OPTARG ;;
    N) NFILES=$OPTARG ;; S) START=$OPTARG ;; C) FORCECHS=1 ;; R) REV=$OPTARG ;;
    *) usage ;;
  esac
done
[ -n "$OUT" ] || usage
for f in "$MBR" "$STAGE2"; do
  [ -f "$f" ] || { echo "MKIMAGE : $f introuvable"; exit 1; }
done
[ "$(stat -c %s "$MBR")" = 512 ] ||
  { echo "MKIMAGE : MBR.BIN doit faire 512 octets"; exit 1; }
[ -z "$KERNEL" ] || [ -f "$KERNEL" ] ||
  { echo "MKIMAGE : $KERNEL introuvable"; exit 1; }

# nombres en petit-boutiste, sur la sortie standard
hexb() { printf "\\x$(printf %02x $(($1 & 255)))"; }
le16() { hexb $1; hexb $(($1 >> 8)); }
le32() { le16 $(($1 & 65535)); le16 $((($1 >> 16) & 65535)); }
# octets CHS (tete, secteur/cylindre haut, cylindre bas) du LBA $1
chs() {
  local c h s
  c=$(($1 / (255 * 63))); h=$((($1 / 63) % 255)); s=$(($1 % 63 + 1))
  if [ $c -gt 1023 ]; then c=1023; h=254; s=63; fi
  hexb $h; hexb $((s | ((c >> 8) << 6))); hexb $c
}

TOTAL=$((MB * 2048))                    # secteurs de 512 octets
PSECT=$((TOTAL - START))
NS2=$(($(stat -c %s "$STAGE2") + 511))
NS2=$((NS2 / 512))
if [ $((1 + NS2)) -gt $START ]; then
  echo "MKIMAGE : chargeur de $NS2 secteurs : ne tient pas avant la partition"
  exit 1
fi
[ $NS2 -le 120 ] ||
  { echo "MKIMAGE : chargeur trop grand ($NS2 secteurs, 120 au plus)"; exit 1; }
[ $((PSECT * 512 / BS)) -gt 64 ] ||
  { echo "MKIMAGE : disque trop petit"; exit 1; }

STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT
[ -z "$ROOT" ] || cp -a "$ROOT"/. "$STAGE"/
mkdir -p "$STAGE/boot"
[ -z "$KERNEL" ] || cp "$KERNEL" "$STAGE/boot/linux0"
[ -z "$CMD" ] ||
  printf 'kernel=/boot/linux0\ncmdline=%s\n' "$CMD" > "$STAGE/boot/linux0.cfg"
i=0
while [ $i -lt $NFILES ]; do
  : > "$STAGE/boot/entree-$(printf %05d $i)-avec-un-nom-assez-long-pour-remplir"
  i=$((i + 1))
done

rm -f "$OUT"
truncate -s "${MB}M" "$OUT"
BLOCKS=$((PSECT * 512 / BS))
ISZ="-I $INO"; FEAT=none,filetype,sparse_super
[ "$REV" != 0 ] || { ISZ=; FEAT=none; }
mke2fs -q -F -t ext2 -b "$BS" $ISZ -r "$REV" -m 0 -L LINUX0 \
  -O "$FEAT" -E "offset=$((START * 512)),root_owner=0:0" \
  -d "$STAGE" "$OUT" "$BLOCKS"

wr() { dd of="$OUT" bs=1 seek=$1 conv=notrunc 2>/dev/null; }
# MBR : code, parametres du chargeur (LBA 1, N secteurs), table, signature
dd if="$MBR" of="$OUT" bs=512 count=1 conv=notrunc 2>/dev/null
{ le32 1; le16 $NS2; } | wr 3
[ $FORCECHS = 0 ] || printf '\x02' | wr 14
{
  printf '\x80'; chs $START; printf '\x83'; chs $((TOTAL - 1))
  le32 $START; le32 $PSECT
  dd if=/dev/zero bs=1 count=48 2>/dev/null
  printf '\x55\xaa'
} | wr 446
dd if="$STAGE2" of="$OUT" bs=512 seek=1 conv=notrunc 2>/dev/null
echo "MKIMAGE : $OUT ($MB Mo) ; partition 1 ext2 ($BS octets/bloc, inodes de" \
  "$INO), secteur $START ; chargeur : $NS2 secteurs"
