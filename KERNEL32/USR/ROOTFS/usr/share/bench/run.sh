# genere par TESTS/U/cmdbench.py --gen : essai des commandes sous KERNEL32
W=/tmp/bench; rm -rf $W; mkdir -p $W/ls $W/dd
echo x > $W/ls/f1; echo y > $W/ls/f2; cd /usr/share/bench/files
P=0; F=0
LANGUAGE=EN; export LANGUAGE
ok() { echo "BENCH-OK $1"; P=$((P+1)); }
ko() { echo "BENCH-KO $1 : $2"; F=$((F+1)); }
o=$(cat 'in.txt' < /dev/null 2>&1); r=$?
[ "$o" = "$(cat /usr/share/bench/exp/0)" ] && ok 'cat in.txt' || ko 'cat in.txt' "sortie"
o=$(cat '-n' 'a.txt' 'b.txt' < /dev/null 2>&1); r=$?
case "$o" in *'1  apple'*) ok 'cat -n a.txt b.txt';; *) ko 'cat -n a.txt b.txt' "sortie";; esac
o=$(head '-n' '3' 'in.txt' < /dev/null 2>&1); r=$?
[ "$o" = "$(cat /usr/share/bench/exp/2)" ] && ok 'head -n 3 in.txt' || ko 'head -n 3 in.txt' "sortie"
o=$(tail '--lines' '2' 'in.txt' < /dev/null 2>&1); r=$?
[ "$o" = "$(cat /usr/share/bench/exp/3)" ] && ok 'tail --lines 2 in.txt' || ko 'tail --lines 2 in.txt' "sortie"
o=$(wc 'a.txt' '-l' < /dev/null 2>&1); r=$?
case "$o" in *'3'*) ok 'wc a.txt -l';; *) ko 'wc a.txt -l' "sortie";; esac
o=$(sort 'in.txt' < /dev/null 2>&1); r=$?
[ "$o" = "$(cat /usr/share/bench/exp/5)" ] && ok 'sort in.txt' || ko 'sort in.txt' "sortie"
o=$(uniq 'in.txt' < /dev/null 2>&1); r=$?
[ "$o" = "$(cat /usr/share/bench/exp/6)" ] && ok 'uniq in.txt' || ko 'uniq in.txt' "sortie"
o=$(cut 'in.txt' '-b' '1-3' < /dev/null 2>&1); r=$?
[ "$o" = "$(cat /usr/share/bench/exp/7)" ] && ok 'cut in.txt -b 1-3' || ko 'cut in.txt -b 1-3' "sortie"
o=$(tr 'l' 'L' < /usr/share/bench/in/8 2>&1); r=$?
[ "$o" = 'heLLo' ] && ok 'tr l L' || ko 'tr l L' "sortie"
o=$(tac 'in.txt' < /dev/null 2>&1); r=$?
[ "$o" = "$(cat /usr/share/bench/exp/9)" ] && ok 'tac in.txt' || ko 'tac in.txt' "sortie"
o=$(rev 'in.txt' < /dev/null 2>&1); r=$?
[ "$o" = "$(cat /usr/share/bench/exp/10)" ] && ok 'rev in.txt' || ko 'rev in.txt' "sortie"
o=$(nl 'a.txt' < /dev/null 2>&1); r=$?
case "$o" in *'apple'*) ok 'nl a.txt';; *) ko 'nl a.txt' "sortie";; esac
o=$(paste 'a.txt' 'b.txt' < /dev/null 2>&1); r=$?
[ "$o" = "$(cat /usr/share/bench/exp/12)" ] && ok 'paste a.txt b.txt' || ko 'paste a.txt b.txt' "sortie"
o=$(join 'j1.txt' 'j2.txt' < /dev/null 2>&1); r=$?
[ "$o" = "$(cat /usr/share/bench/exp/13)" ] && ok 'join j1.txt j2.txt' || ko 'join j1.txt j2.txt' "sortie"
o=$(comm 'a.txt' 'b.txt' < /dev/null 2>&1); r=$?
case "$o" in *'cherry'*) ok 'comm a.txt b.txt';; *) ko 'comm a.txt b.txt' "sortie";; esac
o=$(cmp 'a.txt' 'a.txt' < /dev/null 2>&1); r=$?
[ $r = 0 ] && ok 'cmp a.txt a.txt' || ko 'cmp a.txt a.txt' "rc=$r"
o=$(cmp 'a.txt' 'b.txt' < /dev/null 2>&1); r=$?
[ $r = 1 ] && ok 'cmp a.txt b.txt' || ko 'cmp a.txt b.txt' "rc=$r"
o=$(diff 'a.txt' 'b.txt' < /dev/null 2>&1); r=$?
case "$o" in *'apple'*) ok 'diff a.txt b.txt';; *) ko 'diff a.txt b.txt' "sortie";; esac
o=$(grep 'alpha' 'in.txt' < /dev/null 2>&1); r=$?
case "$o" in *'alpha 1'*) ok 'grep alpha in.txt';; *) ko 'grep alpha in.txt' "sortie";; esac
o=$(grep 'LIGNE' 'in.txt' '/I' < /dev/null 2>&1); r=$?
case "$o" in *'ligne un'*) ok 'grep LIGNE in.txt /I';; *) ko 'grep LIGNE in.txt /I' "sortie";; esac
o=$(egrep 'al|ze' 'in.txt' < /dev/null 2>&1); r=$?
[ "$o" = "$(cat /usr/share/bench/exp/20)" ] && ok 'egrep al|ze in.txt' || ko 'egrep al|ze in.txt' "sortie"
o=$(fgrep 'alpha' 'in.txt' < /dev/null 2>&1); r=$?
[ "$o" = "$(cat /usr/share/bench/exp/21)" ] && ok 'fgrep alpha in.txt' || ko 'fgrep alpha in.txt' "sortie"
o=$(sed 's/a/A/g' 'a.txt' < /dev/null 2>&1); r=$?
[ "$o" = "$(cat /usr/share/bench/exp/22)" ] && ok 'sed s/a/A/g a.txt' || ko 'sed s/a/A/g a.txt' "sortie"
o=$(sed '-e' 's/a/A/' 'a.txt' < /dev/null 2>&1); r=$?
[ "$o" = "$(cat /usr/share/bench/exp/23)" ] && ok 'sed -e s/a/A/ a.txt' || ko 'sed -e s/a/A/ a.txt' "sortie"
o=$(awk '{print $2}' < /usr/share/bench/in/24 2>&1); r=$?
[ "$o" = 'y' ] && ok 'awk {print $2}' || ko 'awk {print $2}' "sortie"
o=$(awk '{s+=$1} END {print s}' 'nums.txt' < /dev/null 2>&1); r=$?
[ "$o" = "$(cat /usr/share/bench/exp/25)" ] && ok 'awk {s+=$1} END {print s} nums.txt' || ko 'awk {s+=$1} END {print s} nums.txt' "sortie"
o=$(expr '2' '+' '3' < /dev/null 2>&1); r=$?
[ "$o" = '5' ] && ok 'expr 2 + 3' || ko 'expr 2 + 3' "sortie"
o=$(seq '1' '5' < /dev/null 2>&1); r=$?
[ "$o" = "$(cat /usr/share/bench/exp/27)" ] && ok 'seq 1 5' || ko 'seq 1 5' "sortie"
o=$(factor '60' < /dev/null 2>&1); r=$?
case "$o" in *'2 2 3 5'*) ok 'factor 60';; *) ko 'factor 60' "sortie";; esac
o=$(basename '/a/b/c.txt' < /dev/null 2>&1); r=$?
[ "$o" = 'c.txt' ] && ok 'basename /a/b/c.txt' || ko 'basename /a/b/c.txt' "sortie"
o=$(dirname '/a/b/c.txt' < /dev/null 2>&1); r=$?
case "$o" in *'/a/b'*) ok 'dirname /a/b/c.txt';; *) ko 'dirname /a/b/c.txt' "sortie";; esac
o=$(echo 'a' 'b' < /dev/null 2>&1); r=$?
[ "$o" = 'a b' ] && ok 'echo a b' || ko 'echo a b' "sortie"
o=$(printf 'x %s %d\n' 'abc' '5' < /dev/null 2>&1); r=$?
[ "$o" = 'x abc 5' ] && ok 'printf x %s %d\n abc 5' || ko 'printf x %s %d\n abc 5' "sortie"
o=$(true  < /dev/null 2>&1); r=$?
[ $r = 0 ] && ok 'true ' || ko 'true ' "rc=$r"
o=$(false  < /dev/null 2>&1); r=$?
[ $r = 1 ] && ok 'false ' || ko 'false ' "rc=$r"
o=$(fold '--width=20' 'long.txt' < /dev/null 2>&1); r=$?
[ "$o" = "$(cat /usr/share/bench/exp/36)" ] && ok 'fold --width=20 long.txt' || ko 'fold --width=20 long.txt' "sortie"
o=$(fmt '--width=30' 'long.txt' < /dev/null 2>&1); r=$?
case "$o" in *'quick'*) ok 'fmt --width=30 long.txt';; *) ko 'fmt --width=30 long.txt' "sortie";; esac
o=$(expand 'tab.txt' < /dev/null 2>&1); r=$?
[ $r = 0 ] && ok 'expand tab.txt' || ko 'expand tab.txt' "rc=$r"
o=$(unexpand 'a.txt' < /dev/null 2>&1); r=$?
[ "$o" = "$(cat /usr/share/bench/exp/39)" ] && ok 'unexpand a.txt' || ko 'unexpand a.txt' "sortie"
o=$(column '-t' 'j1.txt' < /dev/null 2>&1); r=$?
case "$o" in *'a'*) ok 'column -t j1.txt';; *) ko 'column -t j1.txt' "sortie";; esac
o=$(od '-c' 'a.txt' < /dev/null 2>&1); r=$?
case "$o" in *'97'*) ok 'od -c a.txt';; *) ko 'od -c a.txt' "sortie";; esac
o=$(hd 'a.txt' < /dev/null 2>&1); r=$?
case "$o" in *'61 70'*) ok 'hd a.txt';; *) ko 'hd a.txt' "sortie";; esac
o=$(hexdump '-C' 'a.txt' < /dev/null 2>&1); r=$?
case "$o" in *'61 70'*) ok 'hexdump -C a.txt';; *) ko 'hexdump -C a.txt' "sortie";; esac
o=$(md5sum 'a.txt' < /dev/null 2>&1); r=$?
[ "$o" = "$(cat /usr/share/bench/exp/44)" ] && ok 'md5sum a.txt' || ko 'md5sum a.txt' "sortie"
o=$(cksum 'a.txt' < /dev/null 2>&1); r=$?
case "$o" in *'B55C5728'*) ok 'cksum a.txt';; *) ko 'cksum a.txt' "sortie";; esac
o=$(sum 'a.txt' < /dev/null 2>&1); r=$?
case "$o" in *'22875'*) ok 'sum a.txt';; *) ko 'sum a.txt' "sortie";; esac
o=$(base64 'a.txt' < /dev/null 2>&1); r=$?
[ "$o" = "$(cat /usr/share/bench/exp/47)" ] && ok 'base64 a.txt' || ko 'base64 a.txt' "sortie"
o=$(uuencode 'a.txt' '/tmp/bench/uu.out' < /dev/null 2>&1); r=$?
[ $r = 0 ] && ok 'uuencode a.txt /tmp/bench/uu.out' || ko 'uuencode a.txt /tmp/bench/uu.out' "rc=$r"
o=$(split '-l' '1' 'a.txt' '/tmp/bench/sp_' < /dev/null 2>&1); r=$?
[ $r = 0 ] && ok 'split -l 1 a.txt /tmp/bench/sp_' || ko 'split -l 1 a.txt /tmp/bench/sp_' "rc=$r"
o=$(tee '/tmp/bench/tee.out' < /usr/share/bench/in/50 2>&1); r=$?
[ "$o" = 'hello' ] && ok 'tee /tmp/bench/tee.out' || ko 'tee /tmp/bench/tee.out' "sortie"
o=$(touch '/tmp/bench/touched' < /dev/null 2>&1); r=$?
[ $r = 0 ] && ok 'touch /tmp/bench/touched' || ko 'touch /tmp/bench/touched' "rc=$r"
o=$(mkdir '/tmp/bench/dd/ee' < /dev/null 2>&1); r=$?
[ $r = 0 ] && ok 'mkdir /tmp/bench/dd/ee' || ko 'mkdir /tmp/bench/dd/ee' "rc=$r"
o=$(rmdir '/tmp/bench/dd/ee' < /dev/null 2>&1); r=$?
[ $r = 0 ] && ok 'rmdir /tmp/bench/dd/ee' || ko 'rmdir /tmp/bench/dd/ee' "rc=$r"
o=$(cp 'a.txt' '/tmp/bench/cp.out' < /dev/null 2>&1); r=$?
[ $r = 0 ] && ok 'cp a.txt /tmp/bench/cp.out' || ko 'cp a.txt /tmp/bench/cp.out' "rc=$r"
o=$(mv '/tmp/bench/cp.out' '/tmp/bench/mv.out' < /dev/null 2>&1); r=$?
[ $r = 0 ] && ok 'mv /tmp/bench/cp.out /tmp/bench/mv.out' || ko 'mv /tmp/bench/cp.out /tmp/bench/mv.out' "rc=$r"
o=$(rm '/tmp/bench/mv.out' < /dev/null 2>&1); r=$?
[ $r = 0 ] && ok 'rm /tmp/bench/mv.out' || ko 'rm /tmp/bench/mv.out' "rc=$r"
o=$(ls '/tmp/bench/ls' < /dev/null 2>&1); r=$?
case "$o" in *'f1'*) ok 'ls /tmp/bench/ls';; *) ko 'ls /tmp/bench/ls' "sortie";; esac
o=$(ls '-l' '/tmp/bench/ls' < /dev/null 2>&1); r=$?
case "$o" in *'f1'*) ok 'ls -l /tmp/bench/ls';; *) ko 'ls -l /tmp/bench/ls' "sortie";; esac
o=$(date  < /dev/null 2>&1); r=$?
[ $r = 0 ] && ok 'date ' || ko 'date ' "rc=$r"
o=$(cal '2' '2026' < /dev/null 2>&1); r=$?
case "$o" in *'28'*) ok 'cal 2 2026';; *) ko 'cal 2 2026' "sortie";; esac
o=$(env  < /dev/null 2>&1); r=$?
case "$o" in *'PATH'*) ok 'env ';; *) ko 'env ' "sortie";; esac
o=$(uname '-s' < /dev/null 2>&1); r=$?
[ $r = 0 ] && ok 'uname -s' || ko 'uname -s' "rc=$r"
o=$(id  < /dev/null 2>&1); r=$?
case "$o" in *'uid'*) ok 'id ';; *) ko 'id ' "sortie";; esac
o=$(pwd  < /dev/null 2>&1); r=$?
case "$o" in *'/'*) ok 'pwd ';; *) ko 'pwd ' "sortie";; esac
o=$(which 'ls' < /dev/null 2>&1); r=$?
[ $r = 0 ] && ok 'which ls' || ko 'which ls' "rc=$r"
o=$(df  < /dev/null 2>&1); r=$?
[ $r = 0 ] && ok 'df ' || ko 'df ' "rc=$r"
o=$(du '/tmp/bench/ls' < /dev/null 2>&1); r=$?
[ $r = 0 ] && ok 'du /tmp/bench/ls' || ko 'du /tmp/bench/ls' "rc=$r"
o=$(stat 'a.txt' < /dev/null 2>&1); r=$?
case "$o" in *'a.txt'*) ok 'stat a.txt';; *) ko 'stat a.txt' "sortie";; esac
o=$(tree '/tmp/bench' < /dev/null 2>&1); r=$?
case "$o" in *'ls'*) ok 'tree /tmp/bench';; *) ko 'tree /tmp/bench' "sortie";; esac
o=$(strings 'bin.dat' < /dev/null 2>&1); r=$?
[ $r = 0 ] && ok 'strings bin.dat' || ko 'strings bin.dat' "rc=$r"
o=$(look 'ap' 'a.txt' < /dev/null 2>&1); r=$?
case "$o" in *'apple'*) ok 'look ap a.txt';; *) ko 'look ap a.txt' "sortie";; esac
o=$(sleep '0' < /dev/null 2>&1); r=$?
[ $r = 0 ] && ok 'sleep 0' || ko 'sleep 0' "rc=$r"
o=$(bc '-q' < /usr/share/bench/in/73 2>&1); r=$?
[ "$o" = '14' ] && ok 'bc -q' || ko 'bc -q' "sortie"
o=$(dc  < /usr/share/bench/in/74 2>&1); r=$?
[ "$o" = '5' ] && ok 'dc ' || ko 'dc ' "sortie"
o=$(sdiff 'a.txt' 'b.txt' < /dev/null 2>&1); r=$?
case "$o" in *'apple'*) ok 'sdiff a.txt b.txt';; *) ko 'sdiff a.txt b.txt' "sortie";; esac
o=$(csplit 'a.txt' '2' < /dev/null 2>&1); r=$?
[ $r = 0 ] && ok 'csplit a.txt 2' || ko 'csplit a.txt 2' "rc=$r"
o=$(mktemp  < /dev/null 2>&1); r=$?
[ $r = 0 ] && ok 'mktemp ' || ko 'mktemp ' "rc=$r"
o=$(seq '3' < /dev/null 2>&1); r=$?
[ "$o" = "$(cat /usr/share/bench/exp/78)" ] && ok 'seq 3' || ko 'seq 3' "sortie"
o=$(groups  < /dev/null 2>&1); r=$?
[ $r = 0 ] && ok 'groups ' || ko 'groups ' "rc=$r"
o=$(dd 'if=a.txt' 'of=/tmp/bench/dd.out' < /dev/null 2>&1); r=$?
[ $r = 0 ] && ok 'dd if=a.txt of=/tmp/bench/dd.out' || ko 'dd if=a.txt of=/tmp/bench/dd.out' "rc=$r"
o=$(unlink '/tmp/bench/touched' < /dev/null 2>&1); r=$?
[ $r = 0 ] && ok 'unlink /tmp/bench/touched' || ko 'unlink /tmp/bench/touched' "rc=$r"
o=$(repeat '2' '/bin/echo' 'hi' < /dev/null 2>&1); r=$?
case "$o" in *'hi'*) ok 'repeat 2 /bin/echo hi';; *) ko 'repeat 2 /bin/echo hi' "sortie";; esac
o=$(banner 'OK' < /dev/null 2>&1); r=$?
case "$o" in *'#'*) ok 'banner OK';; *) ko 'banner OK' "sortie";; esac
o=$(clear  < /dev/null 2>&1); r=$?
[ $r = 0 ] && ok 'clear ' || ko 'clear ' "rc=$r"
o=$(chmod '644' '/tmp/bench/ls/f1' < /dev/null 2>&1); r=$?
[ $r = 0 ] && ok 'chmod 644 /tmp/bench/ls/f1' || ko 'chmod 644 /tmp/bench/ls/f1' "rc=$r"
o=$(basename 'a.txt' '.txt' < /dev/null 2>&1); r=$?
[ "$o" = 'a' ] && ok 'basename a.txt .txt' || ko 'basename a.txt .txt' "sortie"
o=$(ed 'a.txt' < /usr/share/bench/in/90 2>&1); r=$?
case "$o" in *'apple'*) ok 'ed a.txt';; *) ko 'ed a.txt' "sortie";; esac
echo "BENCH-FIN ok=$P ko=$F"
H=0; K=0
for c in /bin/*; do n=${c##*/}
  case $n in yes|login|sh|ash|ksh|strings) continue;; esac
  $c "/?" < /dev/null > /dev/null 2>&1; r=$?
  if [ $r -ge 128 ]; then echo "HELP-KO $n rc=$r"; K=$((K+1)); else H=$((H+1)); fi
done
echo "HELP-FIN ok=$H ko=$K"
