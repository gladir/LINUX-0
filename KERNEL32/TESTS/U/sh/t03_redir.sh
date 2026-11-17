# redirections and pipes
T=/tmp/shtest.$$
echo one > $T
echo two >> $T
cat $T
cat < $T | wc -l
echo "to stderr" 2>&1 >/dev/null | cat
{ echo out; echo err >&2; } 2>&1 | sort
ls /nonexistent_dir 2>/dev/null
echo rc=$?
cat <<EOF
a $T-not-expanded-here? no: expanded
EOF
cat <<'EOF'
literal $HOME `pwd`
EOF
cat <<-EOF
	tab stripped
	EOF
x=5
cat <<EOF
x=$x $((x+1)) $(echo cmd)
EOF
exec 3>$T
echo three >&3
exec 3>&-
cat $T
echo a | tr a b | tr b c
printf 'l1\nl2\nl3\n' | while read line; do echo "got $line"; done
printf 'a b c\n' | { read x y z; echo "$z $y $x"; }
rm -f $T
