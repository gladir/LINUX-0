set -o pipefail
false | true; echo rc=$?
true | false | true; echo rc=$? ${PIPESTATUS[@]}
set +o pipefail
false | true; echo rc=$?
echo ${PIPESTATUS[@]}
f() { echo in:$FUNCNAME; g; }
g() { echo "${FUNCNAME[@]}"; }
f
trap 'echo ERR line' ERR
false
true
trap - ERR
trap 'echo bye' EXIT
trap 'echo DBG' DEBUG
echo one
trap - DEBUG
t() { trap 'echo RET' RETURN; echo body; }
t
trap - RETURN
set -e
false || echo ok-orlist
! false; echo ok-neg
set +e
select o in a b c; do echo "got $o"; break; done <<< "2"
PS3="pick: "
for i in 1 2; do [[ $i == 2 ]] && continue; echo i=$i; done
declare -r ro=1; (ro=2) 2>/dev/null; echo ro=$ro
local_test() { local -a la=(1 2); local lv=x; echo ${la[@]} $lv; }
la=(9); lv=y; local_test; echo ${la[@]} $lv
declare -x EXP=1; env | grep '^EXP='
printf '%s|%5s|%-5s|%05d|%x|%o|%c|%%\n' a b c 42 255 8 zed
printf '%d %d\n' 1 2 3 4
printf -v pv '%03d' 7; echo $pv
printf '%q\n' "a b"
printf '%.2f %5.1f\n' 3.14159 2.5
printf '%s\n' "$(printf '%b' 'a\tb')"
echo $SECONDS | grep -q '^[0-9]*$' && echo secs
echo ${BASH_VERSION%%.*}
cd /; pushd /tmp > /dev/null; pwd; popd > /dev/null; pwd
read -r -d ',' first rest <<< "a,b"; echo "$first|$rest"
echo "$(( $(wc -l < /etc/passwd) > 0 ))"
