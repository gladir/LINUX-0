#!/bin/bash
# @author: Sylvain Maltais (support@gladir.com)
# @created: 2026
# @website(https://www.gladir.com/linux-0)
# @description: Fabrique les noyaux de test Multiboot (ELF32) du chargeur de
#   KERNEL32 a partir de TESTK.ASM :
#     MKTESTK.SH REPERTOIRE_SORTIE
#   produit dans le repertoire : TESTK.ELF (petit), TESTKBIG.ELF (remplissage
#   de 5 Mo : indirection double meme en blocs de 4 Ko, zone mise a zero,
#   segment lointain a 66 Mo du fichier pour l'indirection triple en blocs de
#   1 Ko) et TESTKHI.ELF (p_vaddr = C0000000h + p_paddr, comme le vrai noyau).
#   Variables : NASM (defaut nasm).
set -e
HERE=$(cd "$(dirname "$0")" && pwd)
OUT=${1:?repertoire de sortie}
NASM=${NASM:-nasm}
mkdir -p "$OUT"
cd "$OUT"
cp "$HERE/TESTK.ASM" .
$NASM -f bin -o TESTK.BIN TESTK.ASM
python3 "$HERE/MKELF.PY" TESTK.BIN TESTK.ELF
cp TESTK.BIN TESTKHI.BIN
printf X >> TESTKHI.BIN          # taille impaire : dernier octet seul
python3 "$HERE/MKELF.PY" --high TESTKHI.BIN TESTKHI.ELF
# gros noyau
PADLEN=5242880
python3 - "$PADLEN" > padhash.txt <<'PY'
import sys, struct
n = int(sys.argv[1]); x = 12345; out = bytearray()
for i in range(n // 4):
    x = (x * 1103515245 + 12345) & 0xFFFFFFFF
    out += struct.pack('<I', x ^ (i * 2654435761 & 0xFFFFFFFF))
open('PAD.BIN', 'wb').write(out)
h = 0
for i in range(n // 4):
    h = (h * 31 + struct.unpack_from('<I', out, i * 4)[0]) & 0xFFFFFFFF
print(h)
PY
HASH=$(cat padhash.txt)
ZLEN=8187
FADDR=$((0xC00000))
FLEN=4096
$NASM -f bin -DPADLEN=$PADLEN -DPADHASH=$HASH -DZLEN=$ZLEN \
  -DFADDR=$FADDR -DFLEN=$FLEN -o TESTKBIG.BIN TESTK.ASM
python3 "$HERE/MKELF.PY" --zero $((0x101001)):$ZLEN \
  --far $((66*1024*1024)):$FADDR:$FLEN TESTKBIG.BIN TESTKBIG.ELF
rm -f TESTK.ASM PAD.BIN padhash.txt
ls -l TESTK.ELF TESTKHI.ELF TESTKBIG.ELF
