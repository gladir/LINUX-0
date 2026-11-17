# essais du lot E6 (suite 2) sous KERNEL32 : sh /usr/share/bench/lot3.sh
# strace, tcpdump, bc, dc, ed, job control sur pty (script), lsof, fuser,
# netstat, ss, lspci, losetup. Le reseau (eth0 10.0.2.15, passerelle 10.0.2.2)
# est requis pour tcpdump (QEMU -nic user).
W=/tmp/lot3; rm -rf $W; mkdir -p $W; cd $W
LANGUAGE=EN; export LANGUAGE
P=0; F=0
ok() { echo "LOT3-OK $1"; P=$((P+1)); }
ko() { echo "LOT3-KO $1 : $2"; F=$((F+1)); }
chk() { # nom attendu obtenu
  [ "$2" = "$3" ] && ok "$1" || ko "$1" "attendu [$2] obtenu [$3]"
}
has() { # nom fichier motif
  grep -q -e "$3" "$2" && ok "$1" || ko "$1" "motif [$3] absent de $2"
}
# ---- bc ----
chk 'bc 2^100' 1267650600228229401496703205376 "$(echo '2^100' | bc)"
chk 'bc scale' 3.3333 "$(echo 'scale=4; 10/3' | bc)"
chk 'bc -l pi' 3.14159265358979323844 "$(echo '4*a(1)' | bc -l)"
chk 'bc -l e(1)' 2.71828182845904523536 "$(echo 'e(1)' | bc -l)"
chk 'bc fonction' 3628800 \
  "$(echo 'define f(n) { if (n<2) return (1); return (n*f(n-1)) }; f(10)' | bc)"
chk 'bc obase' FF "$(echo 'obase=16; 255' | bc)"
chk 'bc tableau et boucle' 285 \
  "$(echo 'for (i=0;i<10;i++) a[i]=i*i
s=0; for (i=0;i<10;i++) s+=a[i]
s' | bc)"
chk 'bc sqrt' 1.4142135623 "$(echo 'scale=10; sqrt(2)' | bc)"
chk 'bc erreur puis suite' 4 "$(printf '1/0\n2+2\n' | bc 2>/dev/null)"
# ---- dc ----
chk 'dc 2^100' 1267650600228229401496703205376 "$(echo '2 100 ^ p' | dc)"
chk 'dc factorielle' 3628800 "$(echo '10 [d1-d1<F*]dsFx p' | dc)"
chk 'dc registres' 11 "$(echo '5 sa 6 sb la lb + p' | dc)"
chk 'dc echelle' 3.33333 "$(echo '5k 10 3 / p' | dc)"
chk 'dc boucle' '1 2 3' \
  "$(echo '0sa [la1+dsa p la 3>L]sL lLx' | dc | paste -s -d' ' -)"
chk 'dc -e' 7 "$(dc -e '3 4 + p')"
# ---- ed ----
printf 'un\ndeux\ntrois\n' > ed.txt
printf '2s/deux/DEUX/\n$a\nquatre\n.\n1d\nw\nq\n' | ed -s ed.txt
chk 'ed edition' 'DEUX trois quatre' "$(paste -s -d' ' ed.txt)"
printf 'g/o/s/o/0/\nw\nq\n' | ed -s ed.txt
chk 'ed global' 'DEUX tr0is quatre' "$(paste -s -d' ' ed.txt)"
printf '1,2m$\nu\nw\nq\n' | ed -s ed.txt
chk 'ed annulation' 'DEUX tr0is quatre' "$(paste -s -d' ' ed.txt)"
chk 'ed adresse motif' tr0is "$(printf '/tr/p\nq\n' | ed -s ed.txt)"
# ---- strace ----
strace -o st1.txt /bin/echo hi > /dev/null
has 'strace write' st1.txt 'write(1, "hi\\n", 3) = 3'
has 'strace execve' st1.txt '^execve("/bin/echo"'
has 'strace exit_group' st1.txt '^exit_group(0) = ?'
has 'strace fin' st1.txt '^+++ exited with 0 +++'
strace -e trace=write -o st2.txt /bin/echo hi > /dev/null
chk 'strace -e trace=write' 2 "$(wc -l < st2.txt | tr -d ' ')"
strace -c -o st3.txt /bin/echo hi > /dev/null
has 'strace -c en-tete' st3.txt '^% time'
has 'strace -c ligne write' st3.txt ' write$'
strace -f -o st4.txt /bin/sh -c 'cat < /nonexistent' > /dev/null 2>&1
has 'strace erreur ENOENT' st4.txt '= -1 ENOENT'
strace -o st5.txt /bin/false; chk 'strace code de retour' 1 $?
strace -f -o st6.txt /bin/sh -c '/bin/echo a; /bin/echo b' > /dev/null
chk 'strace -f : trois execve' 3 "$(grep -c 'execve(' st6.txt | tr -d ' ')"
has 'strace -f : prefixe pid' st6.txt '^[0-9][0-9]* execve'
strace -s 4 -o st7.txt /bin/echo abcdefghij > /dev/null
has 'strace -s' st7.txt 'write(1, "abcd"..., 11)'
sleep 3 &
sleep 1
SP=$(pgrep sleep | tail -1)
strace -o st8.txt -p $SP 2> /dev/null
has 'strace -p' st8.txt '^+++ exited with 0 +++'
# ---- tcpdump ----
tcpdump -n -i eth0 -c 4 -w tp.pcap 2> tp.err &
TP=$!
sleep 1
ping -c 2 10.0.2.2 > /dev/null 2>&1
wait $TP
tcpdump -n -r tp.pcap > tp.txt 2> /dev/null
has 'tcpdump ICMP requete' tp.txt 'IP 10.0.2.15 > 10.0.2.2: ICMP echo request'
has 'tcpdump ICMP reponse' tp.txt 'IP 10.0.2.2 > 10.0.2.15: ICMP echo reply'
has 'tcpdump resume' tp.err '4 packets captured'
tcpdump -n -i eth0 -c 2 icmp > tq.txt 2> /dev/null &
TP=$!
sleep 1
ping -c 1 10.0.2.2 > /dev/null 2>&1
wait $TP
has 'tcpdump filtre icmp' tq.txt 'ICMP echo'
tcpdump -n -e -x -r tp.pcap -c 1 > tr.txt 2> /dev/null
has 'tcpdump -e -x' tr.txt '0x0000:'
# ---- job control sur pty (script) ----
( echo 'sleep 100 &'; sleep 1; echo jobs; sleep 1; echo fg; sleep 1
  echo -en '\032'; sleep 1; echo jobs; echo bg; sleep 1; echo jobs
  sleep 1; echo fg; sleep 1; echo -en '\003'; sleep 1; echo 'echo APRES-FG'
  echo 'sleep 100'; sleep 1; echo -en '\003'; sleep 1; echo 'echo rc=$?'
  sleep 1; echo exit ) | timeout 60 script -q -c /bin/sh jc.txt > jc.out 2>&1
has 'pty : sh interactif' jc.txt '^# '
has 'pty : tache de fond' jc.txt '^\[1\] [0-9]'
has 'pty : jobs Running' jc.txt 'Running'
has 'pty : ^Z Stopped' jc.txt 'Stopped'
has 'pty : ^C sur fg' jc.txt 'APRES-FG'
has 'pty : ^C code 130' jc.txt 'rc=130'
# ---- lsof / fuser ----
sleep 30 &
sleep 1
SL=$(pgrep sleep | tail -1)
lsof > ls.txt 2>&1
has 'lsof en-tete' ls.txt '^COMMAND'
has 'lsof init console' ls.txt '^init .*/dev/console'
has 'lsof sleep' ls.txt "^sleep *$SL "
lsof -p $SL > ls2.txt 2>&1
has 'lsof -p : le processus demande' ls2.txt "^sleep *$SL "
chk 'lsof -p : aucun autre processus' 0 \
  "$(grep -v '^COMMAND' ls2.txt | grep -vc "^sleep *$SL ")"
fuser /bin/sleep > fu.txt 2>&1
has 'fuser /bin/sleep' fu.txt "$SL"
kill $SL
# ---- netstat / ss ----
nc -l -p 5555 > /dev/null 2>&1 &
NC=$!
sleep 1
netstat -ln > ns.txt 2>&1
has 'netstat en-tete' ns.txt '^Proto'
has 'netstat LISTEN 5555' ns.txt ':5555 .*LISTEN'
ss -ltn > ss.txt 2>&1
has 'ss en-tete' ss.txt 'State'
has 'ss LISTEN 5555' ss.txt ':5555'
netstat -r > nr.txt 2>&1
has 'netstat -r route' nr.txt '10.0.2'
netstat -i > ni.txt 2>&1
has 'netstat -i eth0' ni.txt '^eth0'
kill $NC
# ---- lspci ----
lspci > lp.txt 2>&1
has 'lspci hote' lp.txt 'Host bridge'
has 'lspci VGA' lp.txt 'VGA compatible controller'
has 'lspci Ethernet' lp.txt 'Ethernet controller'
# ---- losetup ----
head -c 65536 /dev/zero > loop.img
chk 'losetup -f' /dev/loop0 "$(losetup -f)"
losetup /dev/loop0 loop.img
losetup -a > lo.txt 2>&1
has 'losetup -a' lo.txt '/dev/loop0.*loop.img'
losetup -d /dev/loop0
losetup -a > lo2.txt 2>&1
chk 'losetup -d' 0 "$(grep -c loop.img lo2.txt | tr -d ' ')"
echo "LOT3-FIN ok=$P ko=$F"
