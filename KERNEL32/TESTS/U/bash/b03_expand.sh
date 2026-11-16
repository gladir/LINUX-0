echo {a,b,c} x{1,2}y {1..5} {a..e} {01..03} {5..1..2} pre{a,b{1,2}}post
echo {10..8} {a..c}{1..2} {,x}
s=hello; echo ${s^^} ${s^} ${s:1:3} ${s: -2} ${s/l/L} ${s//l/L} ${#s}
n=s; echo ${!n}
t=ABC; echo ${t,,} ${t,}
q="a b"; echo ${q@Q} ${q@U}
p=/usr/local/bin/prog.tar.gz; echo ${p##*/} ${p%/*} ${p%.*} ${p%%.*} ${p#*/}
echo ${unset:-dflt} ${unset:=set} $unset ${unset:+alt}
echo $'a\tb\n\x41\101B' $'it\'s'
v="x  y"; echo ${v// /_}
w=abcabc; echo ${w/#a/X} ${w/%c/Y} ${w//b/}
echo ${#} ${#s}
x=(a b c); echo ${#x[1]}
echo "${s:0:2}" "${s:2}" "${s:10}"
echo ${s:-}
cat <<< "here $s string"
cat <<< 'single $s'
f=$(printf 'a\nb'); echo "$f"
echo $(echo $(echo nested))
echo "${s}"world
set -- a b c; echo ${@:2} ${*:1:2} $#
echo ~root ~ | head -c 20; echo
