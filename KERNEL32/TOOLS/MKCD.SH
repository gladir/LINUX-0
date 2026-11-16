#!/bin/bash
# @author: Sylvain Maltais (support@gladir.com)
# @created: 2026
# @website(https://www.gladir.com/linux-0)
# @description: Fabrique un CD-ROM amorcable de KERNEL32 (El Torito sans
#   emulation + ISO 9660 / Rock Ridge / Joliet) : le BIOS charge BOOT/STAGE2CD.BIN
#   (tete STAGE2CD.ASM + corps LOADER.SYS) en 0000:8000 ; le chargeur lit
#   l'ISO (secteurs de 2048 octets, INT 13h etendu), charge /boot/linux0 (noyau
#   ELF32), /boot/initrd.img (cpio newc, brut ou gzip : module Multiboot) et la
#   ligne de commande de /boot/linux0.cfg, puis saute au noyau (Multiboot 1).
#   Usage : MKCD.SH -o KERNEL32.ISO -k NOYAU.ELF [-I initrd.cpio[.gz]]
#                   [-r DOSSIER] [-c "ligne de commande"] [-V ETIQUETTE]
#     -k  noyau ELF32 (lpc -3K KERNEL32.PAS) copie en /boot/linux0
#     -I  initramfs (le systeme "live" : voir MKCPIO.PY / USR/) -> /boot/initrd.img
#     -R  dossier racine du systeme "live" : converti en initramfs gzip par
#         MKINITRD.PY (au lieu de -I) ; son /sbin/init est lance par le noyau
#     -r  dossier dont le contenu est copie a la racine du CD (monte sous
#         /cdrom par l'installateur : paquets, fichiers a installer, noyau...)
#     -c  ligne de commande (defaut : console=tty0 console=ttyS0 rw)
#   Prerequis : genisoimage (ou mkisofs : option -boot-load-seg). Les noms ISO de niveau 1
#   (8.3 majuscules) servent au chargeur ; Rock Ridge/Joliet gardent les noms
#   longs pour le noyau (mount -t iso9660 /dev/hdc /cdrom).
set -e
HERE=$(cd "$(dirname "$0")" && pwd)
B="$HERE/../BOOT"
OUT=; KERN=; IRD=; ROOT=; LIVE=; CMD="console=tty0 console=ttyS0 rw"; VOL=KERNEL32
while getopts "o:k:I:R:r:c:V:" o; do
  case $o in o) OUT=$OPTARG ;; k) KERN=$OPTARG ;; I) IRD=$OPTARG ;; R) LIVE=$OPTARG ;; r) ROOT=$OPTARG ;;
    c) CMD=$OPTARG ;; V) VOL=$OPTARG ;; *) exit 2 ;; esac
done
[ -n "$OUT" ] && [ -f "$KERN" ] || { echo "usage : MKCD.SH -o X.ISO -k NOYAU.ELF [-I initrd] [-r dossier] [-c cmdline]"; exit 2; }
W=$(mktemp -d)
if [ -n "$LIVE" ]; then python3 "$HERE/MKINITRD.PY" "$LIVE" "$W/live.cpio.gz" >/dev/null || exit 1; IRD="$W/live.cpio.gz"; fi
S="$W/cd"; mkdir -p "$S/boot"
[ -n "$ROOT" ] && cp -a "$ROOT"/. "$S"/
cp "$KERN" "$S/boot/linux0"
CFG="kernel=/boot/linux0"
if [ -n "$IRD" ]; then cp "$IRD" "$S/boot/initrd.img"; CFG="$CFG
initrd=/boot/initrd.img"; fi
printf '%s\ncmdline=%s\n' "$CFG" "$CMD" > "$S/boot/linux0.cfg"
# image d'amorce : tete CD + corps du chargeur, completee a un multiple de 2048
cat "$B/STAGE2CDH.BIN" "$B/LOADER.SYS" > "$S/boot/stage2cd.bin"
SZ=$(stat -c %s "$S/boot/stage2cd.bin")
PAD=$(( (2048 - SZ % 2048) % 2048 ))
[ $PAD -gt 0 ] && head -c $PAD /dev/zero >> "$S/boot/stage2cd.bin"
SECT=$(( (SZ + PAD) / 512 ))
[ $SECT -gt 160 ] && { echo "chargeur trop gros ($SECT secteurs)"; exit 1; }
rm -f "$OUT"
OPTS=(-iso-level 1 -R -J -V "$VOL" -b boot/stage2cd.bin -no-emul-boot \
      -boot-load-seg 0x800 -boot-load-size $SECT -c boot/boot.cat)
if command -v genisoimage >/dev/null; then
  genisoimage -quiet -o "$OUT" "${OPTS[@]}" "$S"
elif command -v mkisofs >/dev/null; then
  mkisofs -quiet -o "$OUT" "${OPTS[@]}" "$S"
else
  echo "genisoimage ou mkisofs requis (xorriso ne sait pas fixer le segment de chargement)"; exit 1
fi
[ -s "$OUT" ] || { echo "echec de la fabrication de l'ISO"; exit 1; }
IRDSZ=; [ -n "$IRD" ] && IRDSZ=", initrd $(stat -c %s "$IRD")"
echo "$OUT : $(stat -c %s "$OUT") octets (noyau $(stat -c %s "$KERN")$IRDSZ)"
rm -rf "$W"
