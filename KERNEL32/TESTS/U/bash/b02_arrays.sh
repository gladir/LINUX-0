a=(one "two words" three)
echo ${#a[@]} ${a[1]} "${a[@]}"
for x in "${a[@]}"; do echo "[$x]"; done
for x in ${a[@]}; do echo "<$x>"; done
for x in "${a[*]}"; do echo "{$x}"; done
a+=(four five); echo ${#a[@]} ${a[4]} ${a[-1]}
a[7]=seven; echo ${!a[@]}
unset a[1]; echo ${!a[@]} ${#a[@]}
echo "${a[*]}"
b=(1 2 3 4 5); echo ${b[@]:1:2} ${b[@]:3} ${b[@]: -2}
echo ${#a[2]} ${#b[@]}
c=($(echo x y z)); echo ${#c[@]} ${c[2]}
d=(); echo ${#d[@]}; d[3]=x; echo ${#d[@]} ${!d[@]}
e=([2]=b [0]=a [5]=f); echo ${e[@]} ${!e[@]}
declare -a f=(p q); f+=(r); echo ${f[@]}
s=str; echo ${s[0]} ${#s[@]}
echo "${b[@]/3/X}" "${b[@]#1}"
b[1]+=x; echo ${b[1]}
IFS=,; echo "${b[*]}"; unset IFS
unset b; echo ${#b[@]} "${b[@]}"
declare -A m=([x]=1 [y]=2); m[z]=3; echo ${m[y]} ${#m[@]}; for k in x y z; do echo $k=${m[$k]}; done
m[wk]=sp; echo "${m[wk]}"
unset m[x]; echo ${#m[@]}
declare -A n; n[a]=1; n[b]=2; n+=([c]=3); for k in $(printf '%s\n' "${!n[@]}" | sort); do echo $k=${n[$k]}; done
g=(a b c); for i in "${!g[@]}"; do echo $i:${g[$i]}; done
h=("a b" c); set -- "${h[@]}"; echo $# "$1"
echo ${g[@]:1}
declare -p g
read -a rr <<< "p q r"; echo ${#rr[@]} ${rr[1]}
mapfile -t ml < <(printf 'l1\nl2\nl3\n'); echo ${#ml[@]} ${ml[2]}
