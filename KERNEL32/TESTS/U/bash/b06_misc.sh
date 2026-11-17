cat <(echo ps1) <(echo ps2)
diff <(printf 'a\nb\n') <(printf 'a\nc\n'); echo rc=$?
while read -r l; do echo "got:$l"; done < <(printf 'x\ny\n')
echo hi > >(cat -n)
sleep 0.1
f() { local -n ref=$1; ref=changed; }
v=orig; f v; echo $v
case a in a) echo one ;& b) echo two ;; c) echo three;; esac
case x in y) echo no ;;& *) echo star;; esac
declare -f f >/dev/null && echo has_f
echo "${!BASH_V*}" | tr ' ' '\n' | wc -l
x=1; { echo a; echo b; } | while read l; do x=$l; done; echo $x
shopt -s lastpipe 2>/dev/null
echo ${x:-def}
a=(3 1 2); IFS=$'\n' sorted=($(printf '%s\n' "${a[@]}" | sort)); echo "${sorted[@]}"
trap 'echo trapped $?' EXIT
echo $LINENO
[[ $- == *i* ]] || echo noninteractive
echo $BASH_SOURCE | head -c 0
echo ${BASH_VERSINFO[0]}
let "r = 5 % 3"; echo $r
echo $(( RANDOM % 1 ))
exec 3>&1; echo fd3 >&3; exec 3>&-
{ echo grp; } 2>&1
echo "a  b" | { read x y; echo "[$x][$y]"; }
IFS=: read a b c <<< "1:2:3"; echo $a $b $c
echo ${#BASH_REMATCH[@]}
