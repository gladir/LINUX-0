#!/bin/bash
# @author: Sylvain Maltais (support@gladir.com)
# @created: 2026
# @website(https://www.gladir.com/linux-0)
# @description: Fabrique KERNEL32-INSTALL.ISO, le CD-ROM d'installation de
#   KERNEL32 (amorcable, assistant graphique) :
#     - noyau de production (TOOLS/MKPROD.SH) -> /boot/linux0 du CD ;
#     - racine du systeme a installer (celle de BUILD.SH) completee des fuseaux
#       horaires (/usr/share/zoneinfo de l'hote) -> /system.tar sur le CD ;
#     - initramfs "live" : la meme racine + l'assistant /sbin/k32-setup
#       (USR/INSTALLER) lance par init sur tty1, shell de secours sur tty2,
#       tty3 et le port serie.
#   Usage : MKINSTALLCD.SH [-o KERNEL32-INSTALL.ISO] [-R racine] [-k noyau.elf]
#                          [-r dossier_en_plus] [-c cmdline] [-w travail]
#     -R  racine deja construite (BUILD.SH : $W/root) ; sinon BUILD.SH la
#         fabrique (ROOTONLY=1)
#     -k  noyau ELF (defaut : MKPROD.SH sur KSRC ou KERNEL32.PAS)
#     -r  fichiers a ajouter a la racine du CD (par exemple preseed.cfg)
#     -c  ligne de commande du noyau (defaut : console=tty0 console=ttyS0
#         fb=1024x768 rw)
#   Variables : LPC (compilateur), KSRC (source du noyau), W (dossier de
#   travail, defaut /tmp/k32-installcd), ZONES (zoneinfo de l'hote).
#   Les fichiers du CD : /boot/linux0 (noyau), /boot/initrd.img (live),
#   /boot/linux0.cfg, /system.tar (systeme a installer), /README.TXT,
#   /preseed.example (exemple de fichier de reponses).
set -e
HERE=$(cd "$(dirname "$0")" && pwd)
K32=$HERE/..
OUT=KERNEL32-INSTALL.ISO; ROOT=; KERN=; EXTRA=; W=${W:-/tmp/k32-installcd}
CMD="console=tty0 console=ttyS0 fb=1024x768 rw"
while getopts "o:R:k:r:c:w:" o; do
  case $o in o) OUT=$OPTARG ;; R) ROOT=$OPTARG ;; k) KERN=$OPTARG ;;
    r) EXTRA=$OPTARG ;; c) CMD=$OPTARG ;; w) W=$OPTARG ;; *) exit 2 ;; esac
done
LPC=${LPC:-/tmp/claude-0/work/k32/bin/lpc}
ZONES=${ZONES:-/usr/share/zoneinfo}
case $OUT in /*) ;; *) OUT=$PWD/$OUT ;; esac
rm -rf "$W/live" "$W/sys" "$W/cd"; mkdir -p "$W"

echo "== Racine du systeme"
if [ -z "$ROOT" ]; then
  ( cd "$K32" && ROOTONLY=1 LPC=$LPC W=$W/build ./BUILD.SH ) \
    > "$W/build.log" 2>&1 || { tail -20 "$W/build.log"; exit 1; }
  ROOT=$W/build/root
fi
[ -d "$ROOT/sbin" ] || { echo "racine invalide : $ROOT"; exit 1; }
cp -a "$ROOT" "$W/sys"

echo "== Fuseaux horaires ($ZONES)"
if [ -d "$ZONES" ] && [ ! -d "$W/sys/usr/share/zoneinfo/Europe" ]; then
  mkdir -p "$W/sys/usr/share/zoneinfo"
  for d in Africa America Antarctica Arctic Asia Atlantic Australia Europe \
           Indian Pacific; do
    [ -d "$ZONES/$d" ] && cp -a "$ZONES/$d" "$W/sys/usr/share/zoneinfo/"
  done
  for f in UTC GMT CET EET MET WET EST MST HST zone.tab iso3166.tab; do
    [ -e "$ZONES/$f" ] && cp -a "$ZONES/$f" "$W/sys/usr/share/zoneinfo/" || true
  done
  mkdir -p "$W/sys/usr/share/zoneinfo/Etc"
  for f in UTC GMT; do
    [ -e "$ZONES/Etc/$f" ] &&
      cp -a "$ZONES/Etc/$f" "$W/sys/usr/share/zoneinfo/Etc/" || true
  done
fi
ZK=$(du -sk "$W/sys/usr/share/zoneinfo" 2>/dev/null | cut -f1)
echo "   $ZK Ko de fuseaux"

echo "== Archive du systeme (system.tar)"
mkdir -p "$W/cd"
( cd "$W/sys" &&
  tar --format=gnu --numeric-owner --sort=name -cf "$W/cd/system.tar" . )
echo "   $(stat -c %s "$W/cd/system.tar") octets"

echo "== Assistant (USR/INSTALLER)"
mkdir -p "$W/inst"
cp "$K32"/USR/INSTALLER/*.INC "$K32"/USR/INSTALLER/INSTALLER.PAS \
  "$K32"/USR/FSPROBE.INC "$W/inst/"
( cd "$W/inst" && "$LPC" -3X -q INSTALLER.PAS ) ||
  { echo "echec de compilation de l'assistant"; exit 1; }
cp -a "$W/sys" "$W/live"
install -m 755 "$W/inst/INSTALLER" "$W/live/sbin/k32-setup"
install -m 755 "$K32/USR/INSTALLER/k32-setup-run" "$W/live/sbin/k32-setup-run"
cat > "$W/live/etc/inittab" <<'EOT'
# /etc/inittab du CD-ROM d'installation de KERNEL32
rc::sysinit:/bin/sh /etc/rc
1::respawn:/sbin/k32-setup-run /dev/tty1
2::respawn:/sbin/getty tty2 linux
3::respawn:/sbin/getty tty3 linux
S0::respawn:TERM=vt100 /sbin/getty ttyS0
ca::ctrlaltdel:/sbin/reboot
EOT
cat > "$W/live/etc/issue" <<'EOT'
LINUX-0 KERNEL32 : CD-ROM d'installation (shell de secours) \l
EOT

echo "== Noyau"
if [ -z "$KERN" ]; then
  KSRC=${KSRC:-$K32/KERNEL32.PAS}
  "$HERE/MKPROD.SH" -l "$LPC" -s "$KSRC" -o "$W/KERNEL32.ELF" > /dev/null
  KERN=$W/KERNEL32.ELF
fi
echo "   $(stat -c %s "$KERN") octets"

echo "== CD-ROM"
cat > "$W/cd/README.TXT" <<'EOT'
KERNEL32-INSTALL.ISO : CD-ROM d'installation de LINUX-0 KERNEL32.
Amorcer ce CD (BIOS, El Torito) : l'assistant graphique se lance (F2 : shell
de secours, F3 : mode texte). Fichiers : /boot/linux0 (noyau), /system.tar
(systeme a installer), /boot/initrd.img (systeme "live").
Installation automatique : ajouter preseed=/cdrom/preseed.cfg a la ligne de
commande du noyau (voir KERNEL32/README.md, "CD-ROM d'installation").
EOT
cp "$K32/USR/INSTALLER/preseed.example" "$W/cd/preseed.example"
if [ -n "$EXTRA" ]; then cp -a "$EXTRA"/. "$W/cd"/; fi
"$HERE/MKCD.SH" -o "$OUT" -k "$KERN" -R "$W/live" -r "$W/cd" -c "$CMD" \
  -V K32INSTALL
echo "$OUT"
