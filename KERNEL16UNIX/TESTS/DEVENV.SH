#!/bin/bash
# @author: Sylvain Maltais (support@gladir.com)
# @created: 2026
# @website(https://www.gladir.com/linux-0)
# @description: Essai de LINUX-0 dans l'emulateur 8086 de DEVENV (depot
#   DEV-COOLS), en mode banc d'essai sans interface (/KERNELTEST,
#   /KTBOOTIMG) : amorcage de la disquette et du disque dur de IMAGE/,
#   connexion de root a l'invite de getty, commandes tapees dans le shell et
#   verification de l'ecran.
#   Usage : DEVENV=/chemin/devenv KERNEL16UNIX/TESTS/DEVENV.SH
#   Sous Linux, devenv se construit avec DEV-COOLS/OSSPAS_TESTS/
#   devenv_linux_build.py (Free Pascal, unites ptc/graph, X11) et s'execute
#   sous Xvfb (xvfb-run). Dans l'IDE, le meme essai se fait dans un onglet
#   d'emulateur : devenv /DISK0:LINUX0-144.IMG puis BOOT A: dans le terminal
#   CMD (ou /DISK80:LINUX0-HD.IMG puis BOOT C:).
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/.." && pwd)
DEVENV=${DEVENV:?definir DEVENV (executable de DEVENV)}
T=$(mktemp -d); mkdir -p "$T/kt"
cat > "$T/script.txt" <<'EOS'
run 150000000
type root
run 120000000
type ls /etc
run 60000000
type echo $HOME $USER; id
run 80000000
type uname -o | cat
run 80000000
screen
EOS
fail=0
for img in LINUX0-144 LINUX0-HD; do
  cp "$HERE/../IMAGE/$img.IMG" "$T/$img.img"
  ( cd "$T" && timeout 900 xvfb-run -a "$DEVENV" /KERNELTEST,kt /KTBOOTIMG:$img.img \
      /KTSCRIPT:script.txt /KTSTEPS:900000000 ) > "$T/$img.out" 2>&1
  sed -n '/ECRAN/,/^+----$/p' "$T/$img.out" | tail -14
  if grep -q "^|LINUX-0 *|*$\||LINUX-0 *$" "$T/$img.out" && grep -q "Bienvenue sous LINUX-0" "$T/$img.out" &&
     grep -q "uid=0(root)" "$T/$img.out"; then
    echo "OK $img (DEVENV)"
  else echo "ECHEC $img (DEVENV)"; fail=1; fi
done
rm -rf "$T"
exit $fail
