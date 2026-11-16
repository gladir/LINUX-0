#!/bin/bash
# @author: Sylvain Maltais (support@gladir.com)
# @created: 2026
# @website(https://www.gladir.com/linux-0)
# @description: Compile le noyau de PRODUCTION : KERNEL32.PAS sans les programmes
#   de test embarques (TESTS/K : partie entre { BEGIN-EMBED } et { END-EMBED },
#   ~1,8 Mo de base64) -> noyau d'environ 1,5 Mo (au lieu de 3,4 Mo). Les
#   tableaux Emb* deviennent vides (EmbCount = 0) : le noyau ne cree plus
#   /bin/hello, /bin/*test, /sbin/init de test... (sans initrd ni racine
#   reelle valide il n'y a donc pas de systeme).
#     MKPROD.SH [-o NOYAU.ELF] [-s KERNEL32.PAS] [-l lpc]
HERE=$(cd "$(dirname "$0")" && pwd)
SRC=$HERE/../KERNEL32.PAS; OUT=$PWD/KERNEL32.ELF; LPC=${LPC:-/tmp/claude-0/work/k32/bin/lpc}
while getopts "o:s:l:" o; do case $o in o) OUT=$OPTARG ;; s) SRC=$OPTARG ;; l) LPC=$OPTARG ;; *) exit 2 ;; esac; done
W=$(mktemp -d)
python3 - "$SRC" "$W/KERNEL32.PAS" <<'P' || exit 1
import sys
s = open(sys.argv[1], encoding='latin-1').read()
B, E = "{ BEGIN-EMBED }", "{ END-EMBED }"
i = s.index(B) + len(B); j = s.index(E)
empty = """
Const
  EmbCount = 0;
  EmbPath : Array[0..0] Of String[20] = ('');
  EmbSize : Array[0..0] Of LongInt = (0);
  EmbStart : Array[0..1] Of LongInt = (0, 0);
  EmbData : Array[0..0] Of String[60] = ('');
"""
open(sys.argv[2], 'w', encoding='latin-1').write(s[:i] + empty + s[j:])
P
(cd "$W" && "$LPC" -3K -q KERNEL32.PAS) || { echo "echec de compilation (traces dans $W)"; exit 1; }
cp "$W/KERNEL32" "$OUT" && rm -rf "$W"
echo "$OUT : $(stat -c %s "$OUT") octets (noyau de production)"
