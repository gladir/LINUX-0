# builtins
echo -n no newline; echo
printf 'tab\there\nnewline\n'
pwd > /dev/null && echo pwd-ok
cd /tmp && pwd
cd - >/dev/null
export FOO=bar
sh -c 'echo $FOO'
unset FOO
sh -c 'echo ${FOO:-gone}'
test -d /tmp && echo isdir
[ -f /nonexistent ] || echo nofile
[ "a" = "a" ] && echo eq
[ 3 -lt 5 ] && echo lt
[ -n "x" -a -z "" ] && echo and
[ ! -e /nonexistent ] && echo not
type echo | cut -d' ' -f1-4
eval 'echo evaluated $((1+1))'
eval "x=5; echo \$x"
set -- a b c; shift; echo $@; shift 2; echo "[$@]"
umask 022; umask
trap 'echo trapped' EXIT
read v <<EOF
input line
EOF
echo $v
alias ll='echo aliased'
ll
getopts ab: opt -a -b val; echo $opt
:; echo colon
true; echo $?
false; echo $?
command -v echo
exit 3
