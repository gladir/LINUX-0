#!/bin/sh
# @author: Sylvain Maltais (support@gladir.com)
# @created: 2026
# @website(https://www.gladir.com/linux-0)
# @description: compare USR/TEXTUTIL.PAS (wc head tail cut paste) a coreutils
#   de l'hote sur les cas de textutil.cases. Usage : textutil.sh chemin/TEXTUTIL
BIN=$1; HERE=$(cd "$(dirname "$0")" && pwd)
W=${W:-/tmp/linux0-textutil}; mkdir -p "$W/k"; cd "$W" || exit 1
cp "$BIN" "$W/TEXTUTIL"
for c in wc head tail cut paste; do ln -sf ../TEXTUTIL "$W/k/$c"; done
seq 1 37 > a
printf 'x:y:z\n1:2\nlonger line here:b:c:d\n\n:::\n' > b
printf 'no newline at end' > c
fail=0; n=0
while IFS= read -r cmd; do
  n=$((n+1))
  exp=$(sh -c "$cmd" 2>&1)
  got=$(PATH=$W/k:$PATH sh -c "$cmd" 2>&1)
  if [ "$exp" != "$got" ]; then
    fail=$((fail+1))
    [ $fail -le 5 ] && { echo "DIFF: $cmd"; echo "$exp" | head -3
      echo "-- got"; echo "$got" | head -3; }
  fi
done < "$HERE/textutil.cases"
echo "textutil : cas=$n diff=$fail"
[ $fail = 0 ]
