#!/bin/bash
# @author: Sylvain Maltais (support@gladir.com)
# @created: 2026
# @website(https://www.gladir.com/linux-0)
# @description: Banc d'essai rejouable du systeme utilisateur de KERNEL32
#   (agent E). RUNU.SH [etapes...]   etapes : sh host qemu power net install
#   (defaut : toutes)
#     sh       shell USR/SH.PAS contre dash (TESTS/U/shtest.sh)
#     host     compile les commandes du depot (LPC -3X) et lance cmdbench.py
#              sur l'hote (ELF32 statique) : tableau marche/reserves/echoue
#     qemu     amorce IMAGE/LINUX32-HD.IMG sous QEMU, ouvre une session root et
#              lance /usr/share/bench/run.sh (BENCH-FIN ok=.. ko=..)
#     install  deux disques : amorce l'image, installe sur le second disque
#              (install -d /dev/hdb), e2fsck -fn, puis amorce le disque installe
#     power    halt, poweroff et reboot par init (QEMU doit se terminer pour
#              poweroff et reboot)
#     net      reseau sous QEMU (-nic user,model=rtl8139) : ifconfig, route,
#              ping 127.0.0.1, wget d'un serveur http de l'hote (10.0.2.2)
#     build    (automatique avant qemu/install) fabrique l'image avec BUILD.SH
#              dans $W (pas dans IMAGE/, partage) ; KSRC=... choisit le noyau
#   Variables : LPC (compilateur), W (travail, defaut /tmp/linux0-u-tests),
#   IMAGE (image toute faite : saute l'etape build), KSRC, QEMU_T (delai,
#   defaut 600).
HERE=$(cd "$(dirname "$0")" && pwd)
K32=$HERE/../..
LPC=${LPC:-/tmp/claude-0/work/k32/bin/lpc}
W=${W:-/tmp/linux0-u-tests}
QT=${QEMU_T:-600}
export LPC W
mkdir -p "$W/bin" "$W/src"
STEPS=${*:-sh host qemu power net install}
FAIL=0
build() {
  [ -n "$IMAGE" ] && return 0
  IMAGE=$W/linux32.img
  ( cd "$K32" && LPC=$LPC W=$W/build IMG=$IMAGE ./BUILD.SH ) > "$W/build.log" 2>&1 ||
    { echo "ECHEC BUILD.SH (voir $W/build.log)"; FAIL=1; }
}
for st in $STEPS; do
  echo "=== $st"
  case $st in
  sh) "$HERE/shtest.sh" || FAIL=1 ;;
  host)
    cp "$K32"/../*.PAS "$W/src/"
    ls "$K32"/../*.PAS | xargs -n1 basename | sed 's/\.PAS$//' |
      grep -v '^HALT$\|^REBOOT$' |
      xargs -P4 -I{} sh -c "cd $W/src && $LPC -3X -q {}.PAS >/dev/null 2>$W/bin/{}.err || echo ECHEC compilation {}; mv {} $W/bin/ 2>/dev/null"
    CMDBIN=$W/bin python3 "$HERE/cmdbench.py" -o "$W/host.txt" | tail -1 ;;
  qemu)
    build
    [ -f "$IMAGE" ] || { echo "image absente : lancer BUILD.SH"; FAIL=1; continue; }
    cp "$IMAGE" "$W/q.img"
    python3 "$K32/TESTS/QEMU.PY" run "$W/q.img" -m 64 -t "$QT" \
      -c 'login: =root' -c 'Mot de passe : =root' \
      -c '=sh /usr/share/bench/run.sh' -c '=echo QFIN' -s 'QFIN$' > "$W/qemu.txt" 2>&1
    grep 'BENCH-FIN\|HELP-FIN' "$W/qemu.txt"
    grep -q 'BENCH-FIN' "$W/qemu.txt" && grep -q 'HELP-FIN' "$W/qemu.txt" || FAIL=1 ;;
  power)
    build
    [ -f "$IMAGE" ] || { FAIL=1; continue; }
    for c in poweroff reboot; do
      cp "$IMAGE" "$W/p.img"
      t0=$(date +%s)
      python3 "$K32/TESTS/QEMU.PY" run "$W/p.img" -m 64 -t 60 \
        -c 'login: =root' -c 'Mot de passe : =root' -c "=$c" > "$W/$c.txt" 2>&1
      t1=$(date +%s)
      if [ $((t1 - t0)) -lt 40 ] && grep -q 'init : ' "$W/$c.txt"; then
        echo "ok    $c ($((t1 - t0)) s)"
      else echo "ECHEC $c"; tail -3 "$W/$c.txt"; FAIL=1; fi
    done ;;
  net)
    build
    [ -f "$IMAGE" ] || { FAIL=1; continue; }
    PORT=$((20000 + $$ % 20000))
    mkdir -p "$W/web"; echo "linux0-net-ok" > "$W/web/index.html"
    ( cd "$W/web" && exec python3 -m http.server $PORT --bind 127.0.0.1 \
        > /dev/null 2>&1 ) &
    WEBPID=$!
    sleep 1
    cp "$IMAGE" "$W/n.img"
    python3 "$K32/TESTS/QEMU.PY" run "$W/n.img" -m 64 -t 90 \
      -x=-nic -x=user,model=rtl8139 \
      -c 'login: =root' -c 'Mot de passe : =root' \
      -c '=ifconfig eth0; route; ping -c 2 127.0.0.1' \
      -c "=wget -q -O /tmp/w.html http://10.0.2.2:$PORT/index.html; cat /tmp/w.html" \
      -c '=echo NFIN' -s 'NFIN$' > "$W/net.txt" 2>&1
    kill $WEBPID 2>/dev/null
    for pat in 'inet addr:10.0.2.15' '2 received' 'linux0-net-ok'; do
      if grep -q "$pat" "$W/net.txt"; then echo "ok    net : $pat"
      else echo "ECHEC net : $pat (voir $W/net.txt)"; FAIL=$((FAIL+1)); fi
    done ;;
  install)
    build
    [ -f "$IMAGE" ] || { echo "image absente : lancer BUILD.SH"; FAIL=1; continue; }
    cp "$IMAGE" "$W/src.img"; rm -f "$W/dst.img"; truncate -s 96M "$W/dst.img"
    python3 "$K32/TESTS/QEMU.PY" run "$W/src.img" -m 64 -t "$QT" \
      -x=-drive -x="file=$W/dst.img,format=raw,if=ide,index=1" \
      -c 'login: =root' -c 'Mot de passe : =root' \
      -c '=install -d /dev/hdb -l IT -y' -c '=sync' -c '=echo IFIN' -s 'IFIN$' \
      > "$W/inst1.txt" 2>&1
    grep -q 'Installazione completata' "$W/inst1.txt" || { echo "ECHEC installation"; FAIL=1; continue; }
    dd if="$W/dst.img" of="$W/part.img" bs=512 skip=2048 2>/dev/null
    if e2fsck -fn "$W/part.img" > "$W/fsck.txt" 2>&1; then echo "ok    e2fsck -fn propre"
    else echo "ECHEC e2fsck"; tail -5 "$W/fsck.txt"; FAIL=1; fi
    python3 "$K32/TESTS/QEMU.PY" run "$W/dst.img" -m 64 -t 90 \
      -c 'login: =root' -c 'Password: =root' -c '=echo LANG=$LANGUAGE' \
      -c '=echo BFIN' -s 'BFIN$' > "$W/inst2.txt" 2>&1
    if grep -q 'LANG=IT' "$W/inst2.txt"; then echo "ok    disque installe amorce (LANGUAGE=IT)"
    else echo "ECHEC amorce du disque installe"; tail -5 "$W/inst2.txt"; FAIL=1; fi ;;
  esac
done
[ $FAIL = 0 ] && echo "RUNU : tout est reussi" || echo "RUNU : ECHEC"
exit $FAIL
