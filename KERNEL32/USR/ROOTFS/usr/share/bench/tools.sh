# essais des outils lot E3 sous KERNEL32 : sh /usr/share/bench/tools.sh
W=/tmp/tools; rm -rf $W; mkdir -p $W; cd $W
LANGUAGE=EN; export LANGUAGE
P=0; F=0
ok() { echo "TOOLS-OK $1"; P=$((P+1)); }
ko() { echo "TOOLS-KO $1 : $2"; F=$((F+1)); }
chk() { # nom attendu obtenu
  [ "$2" = "$3" ] && ok "$1" || ko "$1" "attendu [$2] obtenu [$3]"
}
printf 'a b\nc\nd e f\n' > t3.txt
seq 1 20 > n20.txt
chk 'wc pipe' '      3       6      12' "$(cat t3.txt | wc)"
chk 'wc -l file' '3 t3.txt' "$(wc -l t3.txt)"
j() { paste -s -d' ' -; }
chk 'tail pipe' '19 20' "$(cat n20.txt | tail -n 2 | j)"
chk 'tail +N' '19 20' "$(tail -n +19 n20.txt | j)"
chk 'head pipe' '1' "$(cat n20.txt | head -n 1)"
chk 'head -n -N' '17' "$(head -n -3 n20.txt | tail -n 1)"
chk 'cut -d' 'a:c' "$(echo 'a:b:c' | cut -d: -f1,3)"
chk 'paste -s' '1,2,3' "$(printf '1\n2\n3\n' | paste -s -d, -)"
# man
man -w vi > $W/mw.txt 2>&1
chk 'man -w' '/usr/share/man/man1/vi.1' "$(cat $W/mw.txt)"
man vi | grep -q 'Modal text editor' && ok 'man vi' || ko 'man vi' 'sortie'
man -k pager | grep -q less && ok 'man -k' || ko 'man -k' 'sortie'
# patch
printf 'one\ntwo\nthree\nfour\n' > p.txt
cat > p.diff <<'EOD'
--- p.txt
+++ p.txt
@@ -1,4 +1,4 @@
 one
-two
+TWO
 three
 four
EOD
patch p.txt < p.diff > /dev/null 2>&1
chk 'patch -u' 'one TWO three four' "$(cat p.txt | j)"
patch -R p.txt < p.diff > /dev/null 2>&1
chk 'patch -R' 'one two three four' "$(cat p.txt | j)"
# zip
mkdir zd; echo hello > zd/h.txt; seq 1 3000 > zd/n.txt
zip -qr z.zip zd && unzip -tq z.zip > /dev/null 2>&1 &&
  ok 'zip -t' || ko 'zip -t' 'rc'
mkdir zo
(cd zo && unzip -q ../z.zip) && cmp zd/n.txt zo/zd/n.txt &&
  ok 'zip roundtrip' || ko 'zip roundtrip' 'cmp'
# cron / at
echo '* * * * * echo tick >> /tmp/tools/tick.txt' | crontab - &&
  crontab -l | grep -q tick && ok 'crontab' || ko 'crontab' 'rc'
crontab -r && ok 'crontab -r' || ko 'crontab -r' 'rc'
echo 'echo atjob > /tmp/tools/at.txt' | at now + 1 minute 2>/dev/null
atq | grep -q root && ok 'at/atq' || ko 'at/atq' 'sortie'
for j in $(atq | cut -f1); do atrm $j; done
[ -z "$(atq)" ] && ok 'atrm' || ko 'atrm' 'reste'
# e2fsck sur le disque racine (lecture seule)
sync
e2fsck -fn /dev/hda1 > $W/fs.txt 2>&1
grep -q 'Pass 5' $W/fs.txt && ok 'e2fsck passes' ||
  ko 'e2fsck passes' "$(tail -2 $W/fs.txt)"
fsck -N /dev/hda1 | grep -q fsck.ext2 && ok 'fsck -N' || ko 'fsck -N' 'sortie'
echo "TOOLS-FIN ok=$P ko=$F"
