#!/bin/bash
# @author: Sylvain Maltais (support@gladir.com)
# @created: 2026
# @website(https://www.gladir.com/linux-0)
# @description: Essai de LINUX-0 dans l'emulateur 8086 de DEVENV (depot
#   DEV-COOLS), en mode banc d'essai sans interface (/KERNELTEST,
#   /KTBOOTIMG, voir DEV-COOLS/DOC/KERNELTEST.txt) : amorcage reel des
#   disquettes UFS1 de 1,44 Mo et 2,88 Mo, de la disquette d'installation,
#   du disque dur UFS1 (MBR, UFSBOOT, partition A5h) et du CD-ROM (El Torito,
#   emulation de disque dur, partition UFS1) de IMAGE/, connexion de root a
#   l'invite de getty, commandes tapees dans le shell et verification de
#   l'ecran emule. Ce noyau n'a pas de FAT : tous les supports sont UFS1.
#   Usage : DEVENV=/chemin/devenv KERNEL16UNIX/TESTS/DEVENV.SH
#   Sous Linux, devenv se construit avec DEV-COOLS/OSSPAS_TESTS/
#   devenv_linux_build.py (Free Pascal, unites ptc/graph, X11) et s'execute
#   sous Xvfb (xvfb-run); LD_LIBRARY_PATH doit nommer les bibliotheques de
#   remplacement des DLL Windows. Dans l'IDE, le meme essai se fait dans un
#   onglet d'emulateur : IMGMOUNT A: LINUX0-144.IMG puis BOOT A: dans le
#   terminal CMD (ou IMGMOUNT C: LINUX0-HD.IMG puis BOOT C:, ou BOOT
#   /CDROM:LINUX0-CD.ISO).
HERE=$(cd "$(dirname "$0")" && pwd)
IMG="$HERE/../IMAGE"
DEVENV=${DEVENV:?definir DEVENV (executable de DEVENV)}
T=$(mktemp -d); mkdir -p "$T/kt"
cat > "$T/script.txt" <<'EOS'
run 40000000
screen
type root
run 80000000
type ls /etc
run 60000000
type echo $HOME $PATH; id
run 80000000
type cat /etc/issue /etc/motd
run 60000000
screen
EOS
fail=0
# image, racine attendue sur l'ecran d'amorce
for spec in "LINUX0-144.IMG|racine : /dev/fd0 (UFS1)" \
            "LINUX0-288.IMG|racine : /dev/fd0 (UFS1)" \
            "LINUX0-INST1.IMG|racine : /dev/fd0 (UFS1)" \
            "LINUX0-HD.IMG|racine : /dev/hda1 (UFS1)" \
            "LINUX0-CD.ISO|racine : /dev/hda1 (UFS1)"; do
  img=${spec%%|*}; want=${spec#*|}
  n=${img%.*}
  cp "$IMG/$img" "$T/$img"
  ( cd "$T" && timeout 900 xvfb-run -a "$DEVENV" /KERNELTEST,kt /KTBOOTIMG:$img \
      /KTSCRIPT:script.txt /KTSTEPS:900000000 ) > "$T/$n.out" 2>&1
  sed -n '/ECRAN/,/^+----$/p' "$T/$n.out" | tail -16
  good=1
  grep -q "racine : /dev/\(fd0\|hda1\)" "$T/$n.out" && grep -qF "$want" "$T/$n.out" || good=0
  grep -q "LINUX-0 KERNEL16UNIX (linux0)" "$T/$n.out" || good=0
  grep -q "Bienvenue sous LINUX-0\|Support d installation de LINUX-0" "$T/$n.out" || good=0
  grep -q "^|/ /bin:/usr/bin" "$T/$n.out" || good=0
  # les supports d'installation n'ont pas la commande id
  case $img in LINUX0-INST1.IMG|LINUX0-CD.ISO) ;;
    *) grep -q "uid=0(root)" "$T/$n.out" || good=0 ;; esac
  grep -q "^|getty" "$T/$n.out" || good=0
  if [ $good = 1 ]; then echo "OK $img (DEVENV)"
  else echo "ECHEC $img (DEVENV)"; fail=1; fi
done
rm -rf "$T"
exit $fail
