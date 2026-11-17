# misc: command substitution, nested quotes, globbing, functions
d=/tmp/shglob.$$
mkdir $d; cd $d
touch a.txt b.txt c.dat .hidden
echo *.txt
echo *
echo [ab].txt
echo ?.dat
echo "*.txt"
echo \*.txt
echo nomatch*
ls | wc -l
cd /; rm -rf $d
x=$(echo hello; echo world)
echo "$x"
echo $(echo a b   c)
y=`echo back`
echo $y
echo "$(echo "nested quotes")"
echo $(printf 'a\nb\n')
z=$(true); echo "[$z]"
n=$(printf 'abc'); echo ${#n}
echo $((3 + $(echo 4)))
r=$(sh -c 'exit 5'); echo $?
set -e
true
echo still
f() { echo "func $#"; }
f 1 2 3
for w in $(echo x y z); do echo $w; done
a='x y'; for w in $a "$a"; do echo "[$w]"; done
printf '%s\n' "a b" c
echo $((0x10)) $((010))
case "$(echo AbC)" in AbC) echo case-ok;; esac
echo done
