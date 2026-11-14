# if / while / for / case / functions
for i in 1 2 3; do echo i=$i; done
for i in a b; do for j in x y; do echo $i$j; done; done
i=0
while [ $i -lt 3 ]; do echo w$i; i=$((i+1)); done
until [ $i -le 0 ]; do echo u$i; i=$((i-1)); done
for i in 1 2 3 4 5; do
  if [ $i -eq 2 ]; then continue; fi
  if [ $i -eq 4 ]; then break; fi
  echo loop$i
done
if true; then echo t; fi
if false; then echo f; elif true; then echo elif; else echo else; fi
case abc in
  a*) echo prefix ;;
  *) echo other ;;
esac
case x in a|b) echo ab ;; x|y) echo xy ;; esac
case "hello world" in "hello world") echo exact ;; esac
case 5 in [0-9]) echo digit ;; esac
f() { echo "f($1,$2)"; return 5; }
f a b; echo $?
g() { local v=inner; echo $v; }
v=outer; g; echo $v
fact() { if [ $1 -le 1 ]; then echo 1; else echo $(( $1 * $(fact $(( $1 - 1 ))) )); fi; }
fact 5
h() { for x in "$@"; do echo "h:$x"; done; }
h one "two words" three
true && echo and1
false || echo or1
false && echo no
true || echo no
! false && echo notok
{ echo brace; echo group; }
( echo sub; exit 3 ); echo status=$?
e() { return 7; }; e; echo $?
