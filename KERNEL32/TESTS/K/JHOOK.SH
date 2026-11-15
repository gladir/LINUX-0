#!/bin/bash
# @author: Sylvain Maltais (support@gladir.com)
# @created: 2026
# @website(https://www.gladir.com/linux-0)
# @description: fabrique un journal ext3/ext4 sale avec debugfs (jo/jw/jc) :
#   4 transactions (voir ext4test.c, "ext4.jrn_*"). Utilise par RUNEXT4.SH
#   (IMG_HOOK) : JHOOK.SH image bloc repertoire_de_travail ; JOPT="-c" pour
#   un journal avec sommes de controle.
IMG=$1; BS=$2; W=$3
read N1 N2 N3 < <(debugfs -R "ffb 3 15300" "$IMG" 2>/dev/null | sed -n 's/.*: //p' | head -1)
[ -n "$N3" ] || { echo "JHOOK : pas de blocs libres"; exit 1; }
python3 -c "
import sys
bs=int(sys.argv[1]); w=sys.argv[2]
open(w+'/pA','wb').write((b'JRNLTEST-A-'*(bs//11+1))[:bs])
open(w+'/pB','wb').write((b'JRNLTEST-B-'*(bs//11+1))[:bs])" "$BS" "$W"
echo "$N1 $N2 $N3" > "$W/jblk.txt"
cat > "$W/jcmds" <<EOT
write $W/jblk.txt jblk.txt
jo $JOPT
jw -b $N1 $W/pA
jw -b $N2 $W/pA
jw -b $N1 $W/pB
jw -r $N2
jw -b $N3 $W/pA
jc
EOT
debugfs -w -f "$W/jcmds" "$IMG" > "$W/jhook.log" 2>&1
debugfs -R "stat /jblk.txt" "$IMG" > /dev/null 2>&1 || { cat "$W/jhook.log"; exit 1; }
