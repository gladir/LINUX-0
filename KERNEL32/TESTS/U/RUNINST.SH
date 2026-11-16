#!/bin/bash
# @author: Sylvain Maltais (support@gladir.com)
# @created: 2026
# @website(https://www.gladir.com/linux-0)
# @description: Banc d'essai de l'assistant d'installation (CD-ROM
#   KERNEL32-INSTALL.ISO) sous QEMU : voir instest.py.
#     RUNINST.SH [-r racine] [-k noyau.elf] [-c dossier_captures] [scenario...]
#   scenarios : tz auto-fr auto-de ui-fr ui-de text (defaut : tous)
#     tz       fuseaux horaires (TZif, heure d'ete) contre l'hote
#     auto-fr  installation automatique (preseed) en francais, guide, ext4+swap
#     auto-de  idem en allemand, manuel : ext3 + swap + /home, horloge locale
#     ui-fr    interface au clavier (sendkey), disposition AZERTY, captures
#     ui-de    interface a la souris, editeur de partitions, captures
#     text     mode texte sur la console VGA (captures)
#   Chaque installation est suivie d'un amorcage du disque installe sans le CD
#   (connexion, hostname, langue, fuseau, utilisateur, e2fsck -fn).
#   Variables : LPC, KSRC (source du noyau), W (travail, defaut
#   /tmp/linux0-inst-tests). Les captures vont dans IMAGE/CAPTURES (PNG).
HERE=$(cd "$(dirname "$0")" && pwd)
K32=$HERE/../..
LPC=${LPC:-/tmp/claude-0/work/k32/bin/lpc}
W=${W:-/tmp/linux0-inst-tests}
ROOT=; KERN=; CAP=$K32/IMAGE/CAPTURES
while getopts "r:k:c:" o; do
  case $o in r) ROOT=$OPTARG ;; k) KERN=$OPTARG ;; c) CAP=$OPTARG ;; *) exit 2 ;; esac
done
shift $((OPTIND - 1))
export LPC W
mkdir -p "$W"
if [ -z "$ROOT" ]; then
  echo "== racine du systeme (BUILD.SH)"
  ( cd "$K32" && ROOTONLY=1 LPC=$LPC W=$W/build ./BUILD.SH ) > "$W/build.log" 2>&1 ||
    { echo "ECHEC BUILD.SH (voir $W/build.log)"; exit 1; }
  ROOT=$W/build/root
fi
if [ -z "$KERN" ]; then
  echo "== noyau de production"
  KSRC=${KSRC:-$K32/KERNEL32.PAS}
  "$K32/TOOLS/MKPROD.SH" -l "$LPC" -s "$KSRC" -o "$W/KERNEL32.ELF" > /dev/null ||
    { echo "ECHEC MKPROD.SH"; exit 1; }
  KERN=$W/KERNEL32.ELF
fi
python3 "$HERE/instest.py" "$W/run" "$ROOT" "$KERN" "$CAP" "$@"
