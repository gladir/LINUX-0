#!/bin/bash
# @author: Sylvain Maltais (support@gladir.com)
# @created: 2026
# @website(https://www.gladir.com/linux-0)
# @description: Banc d'essai rejouable du systeme utilisateur de KERNEL32
#   (agent E). RUNU.SH [etapes...]   etapes : sh host qemu power net install
#   (defaut : toutes)
#     utils    (hote) vi sur pty, wc/head/tail/cut/paste contre coreutils, patch
#              (714 diffs), e2fsck-lite contre e2fsck -fn, zip/unzip contre Info-ZIP
#     tools    (QEMU) /usr/share/bench/tools.sh : filtres, man, patch, zip, cron, at,
#              e2fsck sur le disque racine (TOOLS-FIN ok=.. ko=..)
#     mod      modules du noyau : insmod/lsmod/rmmod de /lib/modules/hello.ko
#              (SKIP si le noyau n'a pas encore le chargeur init_module)
#     sh       shell USR/SH.PAS contre dash (TESTS/U/shtest.sh)
#     bash     mode bash du meme programme (argv[0] = bash) contre GNU bash :
#              tableaux, [[ ]], (( )), accolades, ${..}, printf, traps...
#              (TESTS/U/bashtest.sh)
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
#     lot2host (hote) lot E6 : date contre GNU date, ntpdate/rdate, logrotate,
#              dumpe2fs/tune2fs/e2label/resize2fs contre e2fsprogs
#     lot2     (QEMU) /usr/share/bench/lot2.sh : date -d + fuseaux, run-parts,
#              cron.*, logrotate, e2tools, loadkeys -n, zoneinfo/terminfo
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
STEPS=${*:-sh bash host utils lot2host qemu tools lot2 power net install mod}
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
  bash) "$HERE/bashtest.sh" || FAIL=1 ;;
  host)
    cp "$K32"/../*.PAS "$W/src/"
    ls "$K32"/../*.PAS | xargs -n1 basename | sed 's/\.PAS$//' |
      grep -v '^HALT$\|^REBOOT$' |
      xargs -P4 -I{} sh -c "cd $W/src && $LPC -3X -q {}.PAS >/dev/null 2>$W/bin/{}.err || echo ECHEC compilation {}; mv {} $W/bin/ 2>/dev/null"
    # versions de USR/ qui remplacent celles du depot (awk, sed, grep)
    cp "$K32"/USR/*.INC "$K32"/USR/AWK.PAS "$K32"/USR/SED.PAS \
       "$K32"/USR/GREP.PAS "$W/src/"
    for n in AWK SED GREP; do
      ( cd "$W/src" && $LPC -3X -q $n.PAS > /dev/null 2> "$W/bin/$n.err" &&
        mv $n "$W/bin/$n" ) || echo "ECHEC compilation USR/$n"
    done
    # df : version de USR/FSINFO.PAS (statfs, GNU)
    cp "$K32"/USR/FSINFO.PAS "$K32"/USR/FSPROBE.INC "$W/src/"
    ( cd "$W/src" && $LPC -3X -q FSINFO.PAS >/dev/null 2>&1 &&
      mv FSINFO "$W/bin/df" ) || echo "ECHEC compilation USR/FSINFO"
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
  utils)
    mkdir -p "$W/ut"; cp "$K32"/USR/*.PAS "$K32"/USR/*.INC "$W/ut/"
    for n in VI TEXTUTIL PATCH E2FSCK ZIPTOOL LESS MAN CRON INSTALL FSINFO; do
      ( cd "$W/ut" && $LPC -3X -q $n.PAS >/dev/null 2>"$W/ut/$n.err" ) ||
        { echo "ECHEC compilation $n"; FAIL=1; }
    done
    python3 "$HERE/vitest.py" "$W/ut/VI" | tail -1 || FAIL=1
    "$HERE/textutil.sh" "$W/ut/TEXTUTIL" | tail -1 || FAIL=1
    python3 "$HERE/patchtest.py" "$W/ut/PATCH" | tail -1 || FAIL=1
    W="$W/fs" "$HERE/e2fsckcmp.sh" "$W/ut/E2FSCK" | tail -1 | grep -q 'diff=0' &&
      echo "ok    e2fsck-lite = e2fsck -fn" || { echo "ECHEC e2fsck-lite"; FAIL=1; }
    # mkfs.ext2 / installateur : blocs 1/2/4 Ko, inodes 128/256, -N, sur l'hote
    ( mkdir -p "$W/mk/rt/usr/share/boot" && cd "$W/mk" &&
      cp "$K32"/BOOT/MBR.BIN "$K32"/BOOT/STAGE2.BIN rt/usr/share/boot/ &&
      seq 1 20000 > rt/n.txt && head -c 3000000 /dev/urandom > rt/r.bin &&
      cp "$W/ut/INSTALL" install && ln -sf install mkfs.ext2 && bad=0 &&
      for cfg in "1024 128" "1024 256" "2048 128" "2048 256" "4096 128" "4096 256"
      do set -- $cfg; truncate -s 100M p.img
        ./install -y -q -d p.img -s 100 -r rt -l EN -b $1 -I $2 >/dev/null 2>&1
        e2fsck -fn 'p.img?offset=1048576' >/dev/null 2>&1 || bad=1
        "$W/ut/E2FSCK" -fn 'p.img?offset=1048576' >/dev/null 2>&1 || bad=1
        truncate -s 40M m.img; ./mkfs.ext2 -q -b $1 -I $2 m.img >/dev/null 2>&1
        e2fsck -fn m.img >/dev/null 2>&1 || bad=1
      done; [ $bad = 0 ] ) && echo "ok    install/mkfs.ext2 -b 1024..4096 -I 128/256 : e2fsck propre" ||
      { echo "ECHEC install -b/-I"; FAIL=1; }
    # mkfs.ext3 / mkfs.ext4 : journal, extents, flex_bg, 64bit, metadata_csum,
    # uninit_bg, blocs 1/2/4 Ko, inodes 128/256 : e2fsck -fn et debugfs de l'hote
    ( mkdir -p "$W/mk4" && cd "$W/mk4" && cp "$W/ut/INSTALL" install &&
      for n in mkfs.ext3 mkfs.ext4 mke2fs; do ln -sf install $n; done && bad=0 &&
      for cfg in "ext3 -b1024" "ext3 -b4096 -J size=8" "ext4 -b1024" \
        "ext4 -b2048 -O metadata_csum" "ext4 -b4096 -O metadata_csum,64bit" \
        "ext4 -b1024 -O ^flex_bg,^uninit_bg" "ext4 -b4096 -I256 -O ^has_journal" \
        "ext4 -b1024 -I128 -N 3000" "ext4 -b1024 -O 64bit -J size=8"
      do set -- $cfg; t=$1; shift; truncate -s 64M m.img
        ./mkfs.$t -q "$@" m.img >/dev/null 2>&1 || bad=1
        e2fsck -fn m.img >/dev/null 2>&1 || { echo "  e2fsck : $cfg"; bad=1; }
        dumpe2fs -h m.img 2>/dev/null | grep -q "Filesystem magic" || bad=1
        debugfs -R 'stat <2>' m.img >/dev/null 2>&1 || bad=1
      done; [ $bad = 0 ] ) && echo "ok    mkfs.ext3/ext4 (9 combinaisons) : e2fsck -fn propre" ||
      { echo "ECHEC mkfs.ext3/ext4"; FAIL=1; }
    # installateur sur ext3/ext4 : e2fsck propre et contenu identique (rdump)
    ( mkdir -p "$W/in4/rt/usr/share/boot" "$W/in4/rt/bin" && cd "$W/in4" &&
      cp "$K32"/BOOT/MBR.BIN "$K32"/BOOT/STAGE2.BIN rt/usr/share/boot/ &&
      seq 1 30000 > rt/n.txt && head -c 2000000 /dev/urandom > rt/r.bin &&
      cp /bin/sh rt/bin/ && mkdir -p rt/d1/d2 && echo x > rt/d1/d2/f &&
      ln -sf ../n.txt rt/d1/lnk && cp "$W/ut/INSTALL" install && bad=0 &&
      for t in "-t ext3" "-t ext4" "-t ext4 -O metadata_csum,64bit -b 4096" \
               "-t ext4 -O ^flex_bg -b 2048"; do
        truncate -s 100M p.img
        ./install -y -q -d p.img -s 100 -r rt -l EN $t >/dev/null 2>&1 || bad=1
        e2fsck -fn 'p.img?offset=1048576' >/dev/null 2>&1 || { echo "  e2fsck : $t"; bad=1; }
        rm -rf out; mkdir out
        debugfs -R 'rdump / out' 'p.img?offset=1048576' >/dev/null 2>&1
        for f in n.txt r.bin bin/sh d1/d2/f; do cmp -s rt/$f out/$f || bad=1; done
      done; [ $bad = 0 ] ) && echo "ok    install ext3/ext4 : e2fsck propre, contenu identique" ||
      { echo "ECHEC install ext3/ext4"; FAIL=1; }
    # blkid / lsblk / findmnt / df (USR/FSINFO.PAS) contre l'hote
    ( cd "$W/ut" && ln -sf FSINFO blkid && ln -sf FSINFO df && ln -sf FSINFO findmnt &&
      cp "$W/mk4/m.img" b.img && bad=0 &&
      [ "$(./blkid -o value -s UUID b.img)" = "$(blkid -o value -s UUID b.img)" ] || bad=1
      [ "$(./blkid -o value -s TYPE b.img)" = "$(blkid -o value -s TYPE b.img)" ] || bad=1
      ./blkid b.img | grep -q 'TYPE="ext4"' || bad=1
      [ "$(LANGUAGE=EN ./df -P / | tail -1 | awk '{print $2}')" = \
        "$(df -P / | tail -1 | awk '{print $2}')" ] || bad=1
      [ "$(./findmnt -n -o TARGET -T / )" = "$(findmnt -n -o TARGET -T /)" ] || bad=1
      [ $bad = 0 ] ) && echo "ok    blkid/df/findmnt = util-linux/coreutils" ||
      { echo "ECHEC blkid/df/findmnt"; FAIL=1; }
    # xz / lzma : decompression des fichiers de l'hote, compression relue par xz
    for n in XZ TPUT SUDO NSTOOLS; do
      ( cd "$W/ut" && $LPC -3X -q $n.PAS >/dev/null 2>"$W/ut/$n.err" ) ||
        { echo "ECHEC compilation $n"; FAIL=1; }
    done
    ( mkdir -p "$W/xzt" && cd "$W/xzt" && cp "$W/ut/XZ" xz && ln -sf xz xzcat &&
      ln -sf xz unlzma && seq 1 40000 > a.txt && head -c 200000 /dev/urandom > b.bin &&
      cat "$K32"/USR/*.PAS > c.txt && : > d.empty && echo hi > e.txt && bad=0 &&
      for f in a.txt b.bin c.txt d.empty e.txt; do
        /usr/bin/xz -c $f > $f.h.xz; ./xzcat $f.h.xz | cmp -s - $f || bad=1
        ./xz -c $f > $f.m.xz; /usr/bin/xz -dc $f.m.xz | cmp -s - $f || bad=1
        /usr/bin/xz -tq $f.m.xz || bad=1
      done
      /usr/bin/xz --format=lzma -c c.txt > c.lzma; ./unlzma -c c.lzma | cmp -s - c.txt ||
        bad=1
      [ $bad = 0 ] ) && echo "ok    xz/lzma = xz de l'hote (5 fichiers, 2 sens)" ||
      { echo "ECHEC xz"; FAIL=1; }
    ( cd "$W/ut" && ln -sf TPUT tput && ln -sf SUDO visudo && ln -sf NSTOOLS unshare &&
      bad=0 &&
      for t in linux xterm vt100; do for c in "cup 5 10" bold sgr0 el home rev smul; do
        [ "$(TERM=$t ./tput $c | od -c)" = "$(TERM=$t tput $c | od -c)" ] || bad=1
      done; done
      printf 'root ALL=(ALL) ALL\nbob ALL=(ALL) NOPASSWD: /bin/ls\n' > sd.t
      ./visudo -c -f sd.t >/dev/null || bad=1
      echo 'junk' > sd.b; ./visudo -c -f sd.b >/dev/null 2>&1 && bad=1
      ./unshare -r id -u | grep -q '^0$' || bad=1
      [ $bad = 0 ] ) && echo "ok    tput = ncurses, visudo, unshare" ||
      { echo "ECHEC tput/visudo/unshare"; FAIL=1; }
    ( mkdir -p "$W/zt/src" && cd "$W/zt" && cp "$W/ut/ZIPTOOL" zip &&
      ln -sf zip unzip && seq 1 5000 > src/n.txt && head -c 100000 /dev/urandom > src/r.bin &&
      ./zip -qr a.zip src && /usr/bin/unzip -tq a.zip >/dev/null &&
      /usr/bin/zip -qr b.zip src && mkdir -p o && ./unzip -q -d o b.zip &&
      diff -r src o/src ) && echo "ok    zip/unzip = Info-ZIP" ||
      { echo "ECHEC zip/unzip"; FAIL=1; } ;;
  tools)
    build
    [ -f "$IMAGE" ] || { FAIL=1; continue; }
    cp "$IMAGE" "$W/t.img"
    python3 "$K32/TESTS/QEMU.PY" run "$W/t.img" -m 64 -t "$QT" \
      -c 'login: =root' -c 'Mot de passe : =root' \
      -c '=sh /usr/share/bench/tools.sh' -c '=echo QFIN' -s 'QFIN$' > "$W/tools.txt" 2>&1
    grep 'TOOLS-KO\|TOOLS-FIN' "$W/tools.txt"
    grep -q 'TOOLS-FIN ok=[0-9]* ko=0' "$W/tools.txt" || FAIL=1 ;;
  lot2host)
    # lot E6 sur l'hote : date (contre GNU date), ntpdate/rdate (serveurs
    # factices), logrotate, dumpe2fs/tune2fs/e2label/resize2fs (e2fsprogs)
    mkdir -p "$W/l2"; cp "$K32"/USR/*.PAS "$K32"/USR/*.INC "$W/l2/"
    cp "$K32"/USR/INSTALLER/LAYOUTS.INC "$W/l2/"
    for n in DATE NTPDATE LOGROTATE E2TOOLS LOADKEYS; do
      ( cd "$W/l2" && $LPC -3X -q $n.PAS >/dev/null 2>"$W/l2/$n.err" ) ||
        { echo "ECHEC compilation $n"; FAIL=1; }
    done
    python3 "$HERE/datetest.py" "$W/l2/DATE" | tail -1 || FAIL=1
    python3 "$HERE/nettime.py" "$W/l2/NTPDATE" | grep -c '^ok' |
      grep -q '^4$' && echo "ok    ntpdate/rdate : 4 essais" ||
      { echo "ECHEC ntpdate/rdate"; FAIL=1; }
    python3 "$HERE/logrotatetest.py" "$W/l2/LOGROTATE" | grep -q ECHEC &&
      { echo "ECHEC logrotate"; FAIL=1; } || echo "ok    logrotate (12 essais)"
    python3 "$HERE/e2toolstest.py" "$W/l2/E2TOOLS" | grep -q ECHEC &&
      { echo "ECHEC e2tools"; FAIL=1; } ||
      echo "ok    dumpe2fs/tune2fs/e2label/resize2fs = e2fsprogs" ;;
  lot2)
    build
    [ -f "$IMAGE" ] || { FAIL=1; continue; }
    cp "$IMAGE" "$W/l2.img"
    python3 "$K32/TESTS/QEMU.PY" run "$W/l2.img" -m 64 -t "$QT" \
      -c 'login: =root' -c 'Mot de passe : =root' \
      -c '=sh /usr/share/bench/lot2.sh' -c '=echo QFIN' -s 'QFIN$' \
      > "$W/lot2.txt" 2>&1
    grep 'LOT2-KO\|LOT2-FIN' "$W/lot2.txt"
    grep -q 'LOT2-FIN ok=[0-9]* ko=0' "$W/lot2.txt" || FAIL=1 ;;
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
      -c '=ip addr show dev eth0; ip route; netstat -r' \
      -c "=printf 'GET /index.html HTTP/1.0\\n\\n' | telnet 10.0.2.2 $PORT" \
      -c '=udhcpc -i eth0 -t 1 -T 5' \
      -c '=echo NFIN' -s 'NFIN$' > "$W/net.txt" 2>&1
    kill $WEBPID 2>/dev/null
    for pat in 'inet addr:10.0.2.15' '2 received' 'linux0-net-ok' \
               'inet 10.0.2.15' 'Connected to 10.0.2.2'; do
      if grep -q "$pat" "$W/net.txt"; then echo "ok    net : $pat"
      else echo "ECHEC net : $pat (voir $W/net.txt)"; FAIL=$((FAIL+1)); fi
    done
    # client DHCP : facultatif (diffusion UDP depuis 0.0.0.0 selon le noyau)
    if grep -q 'udhcpc: lease of 10.0.2.15' "$W/net.txt"; then
      echo "ok    net : udhcpc"
    else echo "SKIP  net : udhcpc (pas de bail, voir BUGS_NOYAU.md [E3])"; fi ;;
  mod)
    build
    [ -f "$IMAGE" ] || { FAIL=1; continue; }
    cp "$IMAGE" "$W/m.img"
    python3 "$K32/TESTS/QEMU.PY" run "$W/m.img" -m 64 -t 90 \
      -c 'login: =root' -c 'Mot de passe : =root' \
      -c '=modinfo hello; insmod /lib/modules/hello.ko; lsmod; rmmod hello; lsmod; dmesg | tail -4' \
      -c '=echo MFIN' -s 'MFIN$' > "$W/mod.txt" 2>&1
    if grep -q 'hello: module charge' "$W/mod.txt" &&
       grep -q 'hello: module decharge' "$W/mod.txt"; then
      echo "ok    modules : insmod, lsmod, rmmod, journal du noyau"
    elif grep -qi 'non implant\|not implemented\|ENOSYS' "$W/mod.txt"; then
      echo "SKIP  modules : le noyau n'a pas encore init_module (voir $W/mod.txt)"
    else echo "ECHEC modules (voir $W/mod.txt)"; FAIL=1; fi ;;
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
