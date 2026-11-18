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
#  6. "BUILD.SH cd" : au lieu de l'image de disque, fabrique le CD-ROM
#     d'installation IMAGE/KERNEL32-INSTALL.ISO (TOOLS/MKINSTALLCD.SH : noyau
#     de production, assistant graphique, systeme a installer). ROOTONLY=1 :
#     s'arrete apres l'etape 4 (racine dans $W/root).
#
#  Usage : KERNEL32/BUILD.SH [boot|cd]    ("boot" : etape 2 seulement)
#  Variables : W (dossier de travail, defaut /tmp/linux32-build), FPC, NASM,
#              LPC (compilateur deja construit), TESTKERNEL=1, MB (taille du
#              disque en Mo, KSRC (source du noyau), IMG (image produite), defaut 64), BS (blocs ext2, defaut 1024), INODE
#              (taille d'inode, defaut 128), CMDLINE (ligne de commande du
#              noyau, defaut : root=/dev/hda1 rw console=ttyS0), NOCMDS=1 (sans les 178
#              commandes du depot : systeme minimal).
set -e
HERE=$(cd "$(dirname "$0")" && pwd)
CDMODE=
[ "$1" = cd ] && { CDMODE=1; ROOTONLY=1; }
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
KSRC=${KSRC:-$HERE/KERNEL32.PAS}     # source du noyau (KSRC=... pour un autre)
if [ -z "$TESTKERNEL" ] && [ -f "$KSRC" ]; then
  mkdir -p "$W/src"
  cp "$KSRC" "$W/src/KERNEL32.PAS"
  ( cd "$W/src" && "$LPC" -3K -q KERNEL32.PAS ) || exit 1
  KERNEL="$W/src/KERNEL32"
else
  echo "   (noyau de test TESTS/B/TESTK.ASM)"
  "$HERE/TESTS/B/MKTESTK.SH" "$W/testk" > "$W/log/testk.log"
  KERNEL="$W/testk/TESTK.ELF"
fi

echo "== Programmes (LPC -3X)"
rm -rf "$W/root"
mkdir -p "$W/root/sbin" "$W/root/bin" "$W/root/etc" "$W/root/dev" \
  "$W/root/tmp" "$W/root/proc" "$W/root/sys" "$W/root/boot" "$W/root/home" \
  "$W/root/root" "$W/root/usr/bin" "$W/root/usr/sbin" "$W/root/var/log" "$W/root/var/run" \
  "$W/root/var/tmp" "$W/root/mnt" "$W/root/lib"
mkdir -p "$W/usr"
N=0
# compile : $1 = source, $2 = destination dans la racine
build_one() {
  local f=$1 dst=$2 n
  n=$(basename "$f" .PAS)
  cp "$f" "$W/usr/"
  cp "$HERE"/USR/*.INC "$HERE"/USR/INSTALLER/LAYOUTS.INC \
    "$HERE"/USR/INSTALLER/GFX.INC "$HERE"/USR/INSTALLER/FONTS.INC \
    "$HERE"/USR/INSTALLER/UIBASE.INC "$HERE"/USR/INSTALLER/INPUT.INC \
    "$W/usr/" 2>/dev/null || true
  if ( cd "$W/usr" && "$LPC" -3X -q "$n.PAS" ) > "$W/log/$n.log" 2>&1; then
    install -m 755 "$W/usr/$n" "$W/root/$dst"
    N=$((N + 1))
  else
    echo "   avertissement : $n ignore ($(tail -1 "$W/log/$n.log"))"
  fi
}
# programmes systeme (USR/*.PAS) : sbin pour init, getty, halt, reboot...
for f in "$HERE"/USR/*.PAS; do
  [ -f "$f" ] || continue
  n=$(basename "$f" .PAS); l=$(echo "$n" | tr A-Z a-z)
  case $n in
    INIT) build_one "$f" sbin/init ;;
    GETTY|INSTALL|MOUNT|UMOUNT|HALT|REBOOT|POWEROFF|MKPASSWD|NOLOGIN|IFCONFIG|\
    ROUTE|MKSWAP|SWAPON|SYSCTL|HWCLOCK|LSMOD|USERMGR|TELINIT|SYSLOGD|MODTOOL|\
    E2FSCK|UDHCPC|LOGROTATE|NTPDATE|E2TOOLS|IPTABLES|TCPDUMP)
      build_one "$f" sbin/$l ;;
    *) build_one "$f" bin/$l ;;
  esac
done
# egrep et fgrep : meme programme que grep (nom lu dans argv[0])
for n in egrep fgrep; do
  [ -f "$W/root/bin/grep" ] && ln -sf grep "$W/root/bin/$n" 2>/dev/null || true
done
# commandes du depot (racine) : /bin, sans ecraser les versions de USR/
if [ -z "$NOCMDS" ]; then
  for f in "$HERE"/../*.PAS; do
    [ -f "$f" ] || continue
    n=$(basename "$f" .PAS); l=$(echo "$n" | tr A-Z a-z)
    # remplaces par des programmes de USR/ (noms multiples via liens)
    case $n in HALT|REBOOT|HSWD|WC|HEAD|TAIL|CUT|PASTE|MORE|VI|CRONTAB|DF|BASH|CLEAR)
      continue ;; esac
    [ -f "$W/root/bin/$l" ] || [ -f "$W/root/sbin/$l" ] && continue
    build_one "$f" bin/$l
  done
fi
# modules d'exemple (lpc -3M) : /lib/modules/NOM.ko
mkdir -p "$W/root/lib/modules"
for f in "$HERE"/USR/MODULES/*.PAS; do
  [ -f "$f" ] || continue
  n=$(basename "$f" .PAS); l=$(echo "$n" | tr A-Z a-z)
  cp "$f" "$W/usr/"
  if ( cd "$W/usr" && "$LPC" -3M -q "$n.PAS" ) > "$W/log/$n.log" 2>&1; then
    install -m 644 "$W/usr/$n.ko" "$W/root/lib/modules/$l.ko"
  else
    echo "   avertissement : module $n ignore ($(tail -1 "$W/log/$n.log"))"
  fi
done
ln -sf sh "$W/root/bin/ash" 2>/dev/null || true
# programmes USR/ servant sous plusieurs noms (argv[0]) : nouveau ancien dossier
for l in "chgrp chown bin" "realpath readlink bin" "pkill pgrep bin" \
         "pidof pgrep bin" "killall pgrep bin" "swapoff swapon sbin" \
         "insmod lsmod sbin" "rmmod lsmod sbin" "[ test bin" \
         "useradd usermgr sbin" "userdel usermgr sbin" \
         "usermod usermgr sbin" "groupadd usermgr sbin" \
         "groupdel usermgr sbin" "groupmod usermgr sbin" \
         "adduser usermgr sbin" "addgroup usermgr sbin" \
         "deluser usermgr sbin" "delgroup usermgr sbin" \
         "chpasswd usermgr sbin" "runlevel telinit sbin" \
         "shutdown telinit sbin" "users who bin" "w who bin" \
         "last who bin" "logger syslogd sbin" "vmstat top bin" "modinfo modtool sbin" \
         "modprobe modtool sbin" "depmod modtool sbin" \
         "wc textutil bin" "head textutil bin" "tail textutil bin" \
         "cut textutil bin" "paste textutil bin" \
         "view vi bin" "vim vi bin" "more less bin" \
         "apropos man bin" "whatis man bin" "info man bin" \
         "crond cron bin" "atd cron bin" "crontab cron bin" "at cron bin" \
         "batch cron bin" "atq cron bin" "atrm cron bin" \
         "zip ziptool bin" "unzip ziptool bin" "zipinfo ziptool bin" \
         "fsck e2fsck sbin" "fsck.ext2 e2fsck sbin" "fsck.ext3 e2fsck sbin" \
         "fsck.ext4 e2fsck sbin" \
         "unxz xz bin" "xzcat xz bin" "lzma xz bin" "unlzma xz bin" \
         "lzcat xz bin" "unshare nstools bin" "nsenter nstools bin" \
         "chroot nstools bin" "pivot_root nstools sbin" \
         "switch_root nstools sbin" "setpriv nstools bin" \
         "visudo sudo bin" "clear tput bin" "reset tput bin" "infocmp tput bin" \
         "tset tput bin" "bash sh bin" "df fsinfo bin" "blkid fsinfo bin" "lsblk fsinfo bin" \
         "findmnt fsinfo bin" \
         "lsof procinfo bin" "fuser procinfo bin" "netstat procinfo bin" \
         "ss procinfo bin" "lspci procinfo bin" "lsusb procinfo bin" \
         "losetup procinfo bin" "telnet netutil bin" "ftp netutil bin" \
         "httpd netutil bin" "traceroute netutil bin" \
         "dhclient udhcpc sbin" "ip iptool bin" "dumpkeys loadkeys bin" \
         "rdate ntpdate sbin" "dumpe2fs e2tools sbin" \
         "tune2fs e2tools sbin" "e2label e2tools sbin" \
         "resize2fs e2tools sbin" "iptables-save iptables sbin" \
         "iptables-restore iptables sbin" "k32-session k32sess bin" \
         "k32-gnome k32desk bin" "gnome-session k32desk bin" \
         "gnome-terminal k32desk bin" "k32-kde k32desk bin" \
         "startplasma-x11 k32desk bin" "startkde k32desk bin" \
         "konsole k32desk bin" "dolphin k32desk bin"; do
  set -- $l
  [ -f "$W/root/$3/$2" ] && ln -sf "$2" "$W/root/$3/$1" 2>/dev/null || true
done
ln -sf ../sbin/syslogd "$W/root/bin/logger" 2>/dev/null || true
# commandes dont le nom de fichier se termine par _ (STRINGS_.PAS : mot reserve)
for f in "$W"/root/bin/*_; do
  [ -f "$f" ] && ln -sf "$(basename "$f")" "${f%_}" 2>/dev/null || true
done
# mkfs.ext2 = INSTALL sous un autre nom ; l'installateur copie / sur un disque
for n in mkfs.ext2 mkfs.ext3 mkfs.ext4 mke2fs; do
  ln -sf install "$W/root/sbin/$n" 2>/dev/null || true
done
mkdir -p "$W/root/usr/share/boot"
cp "$B/MBR.BIN" "$B/STAGE2.BIN" "$W/root/usr/share/boot/"
echo "   $N programme(s)"
# fuseaux horaires (TZif de l'hote : ZONES=dossier) et terminfo des terminaux
# courants (TERMINFO=dossier) : lus par L32API (TZ, /etc/localtime) et ncurses
ZONES=${ZONES:-/usr/share/zoneinfo}
if [ -d "$ZONES" ]; then
  mkdir -p "$W/root/usr/share/zoneinfo"
  for d in Africa America Antarctica Arctic Asia Atlantic Australia Europe \
           Indian Pacific; do
    [ -d "$ZONES/$d" ] && cp -a "$ZONES/$d" "$W/root/usr/share/zoneinfo/"
  done
  for f in UTC GMT CET EET MET WET EST MST HST zone.tab iso3166.tab; do
    [ -e "$ZONES/$f" ] && cp -a "$ZONES/$f" "$W/root/usr/share/zoneinfo/" || true
  done
  mkdir -p "$W/root/usr/share/zoneinfo/Etc"
  for f in UTC GMT; do
    [ -e "$ZONES/Etc/$f" ] &&
      cp -a "$ZONES/Etc/$f" "$W/root/usr/share/zoneinfo/Etc/" || true
  done
fi
TERMINFO=${TERMINFO:-/usr/share/terminfo}
if [ -d "$TERMINFO" ]; then
  for t in linux vt100 vt102 vt220 xterm xterm-256color xterm-color ansi screen \
           screen-256color dumb; do
    f=$(find "$TERMINFO" -name "$t" 2>/dev/null | head -1)
    if [ -n "$f" ]; then
      mkdir -p "$W/root/usr/share/terminfo/$(echo $t | cut -c1)"
      cp -L "$f" "$W/root/usr/share/terminfo/$(echo $t | cut -c1)/$t"
    fi
  done
fi
# fichiers de configuration
cp -a "$HERE/USR/ROOTFS"/. "$W/root"/
chmod 600 "$W/root/etc/shadow"; chmod 700 "$W/root/root"
chmod 440 "$W/root/etc/sudoers" 2>/dev/null || true
chmod 4755 "$W/root/bin/sudo" 2>/dev/null || true
mkdir -p "$W/root/home/linux"; chown 1000:1000 "$W/root/home/linux" 2>/dev/null || true
chmod 1777 "$W/root/tmp" "$W/root/var/tmp"

if [ -n "$ROOTONLY" ]; then
  if [ -n "$CDMODE" ]; then
    echo "== CD-ROM d'installation"
    LPC=$LPC "$HERE/TOOLS/MKINSTALLCD.SH" -R "$W/root" -k "${KERNELELF:-}" \
      -o "${ISO:-$HERE/IMAGE/KERNEL32-INSTALL.ISO}" -w "$W/installcd"
  fi
  exit 0
fi
echo "== Image disque"
IMG=${IMG:-$HERE/IMAGE/LINUX32-HD.IMG}     # image produite
mkdir -p "$(dirname "$IMG")"
"$HERE/TOOLS/MKIMAGE.SH" -o "$IMG" -k "$KERNEL" \
  -r "$W/root" -s "$MB" -b "$BS" -i "$INODE" -c "${CMDLINE:-root=/dev/hda1 rw console=ttyS0}"
echo "Essai : qemu-system-i386 -m 64" \
  "-drive file=IMAGE/LINUX32-HD.IMG,format=raw,if=ide"
