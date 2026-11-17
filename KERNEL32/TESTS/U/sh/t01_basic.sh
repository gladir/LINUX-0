# variables, quoting, expansions
a=1; b="two words"; c='single $a'
echo $a "$b" $c
echo "$a$b" '$a' "\$a" \$a
echo ${a}x ${undefined:-dflt} ${undefined-dflt2} ${a:+set} ${undefined:+set}
x=; echo "[${x:-empty}]" "[${x-unset}]"
echo ${#b} ${b#two} ${b%words} ${b##* } ${b%% *}
f=/usr/lib/file.tar.gz
echo ${f##*/} ${f%.*} ${f%%.*} ${f#*/}
echo $((1+2*3)) $(( (1+2)*3 )) $((10/3)) $((10%3)) $((2<3)) $((1<<4)) $((-5+2))
n=7; echo $((n*n)) $((n>5 && n<10)) $((n==7))
echo "a  b" a\ \ b
set -- 1 2 3
echo $# "$*" "$@"
for i in "$@"; do echo -n "<$i>"; done; echo
IFS=:
set -- a:b:c
echo $1 $2 $3
unset IFS
s="a b  c"
set -- $s
echo $#
set -- "$s"
echo $#
echo $0 | sed 's/.*\///'
echo ~ | sed 's/.*/home/'
echo "${nonexist}" end
echo '' "" a
