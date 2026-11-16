# essais du lot E6 (userland) sous KERNEL32 : sh /usr/share/bench/lot2.sh
W=/tmp/lot2; rm -rf $W; mkdir -p $W; cd $W
LANGUAGE=EN; export LANGUAGE
P=0; F=0
ok() { echo "LOT2-OK $1"; P=$((P+1)); }
ko() { echo "LOT2-KO $1 : $2"; F=$((F+1)); }
chk() { # nom attendu obtenu
  [ "$2" = "$3" ] && ok "$1" || ko "$1" "attendu [$2] obtenu [$3]"
}
# date -d, fuseaux (TZif de /usr/share/zoneinfo), formats
chk 'date -d epoch UTC' '2023-11-14 22:13:20' \
  "$(date -u -d @1700000000 '+%F %T')"
chk 'date -d ISO + fuseau Paris (hiver)' '2024-01-15 13:00:00 CET +0100' \
  "$(TZ=Europe/Paris date -d '2024-01-15 12:00 UTC' '+%F %T %Z %z')"
chk 'date -d heure d ete Paris' '2024-07-15 14:00:00 CEST +0200' \
  "$(TZ=Europe/Paris date -d '2024-07-15 12:00 UTC' '+%F %T %Z %z')"
chk 'date TZ="Asia/Tokyo" dans le texte' '2024-06-01 03:00' \
  "$(date -u -d 'TZ="Asia/Tokyo" 2024-06-01 12:00' '+%F %H:%M')"
chk 'date -d relatif' '2024-03-01' "$(date -u -d '2024-02-29 +1 day' +%F)"
chk 'date -d mois' '2024-03-02' \
  "$(date -u -d '2024-01-31 +1 month' +%F)"
chk 'date -d texte anglais' '2024-06-15 15:00' \
  "$(date -u -d 'June 15, 2024 3pm' '+%F %H:%M')"
chk 'date -R' 'Sat, 01 Jun 2024 12:00:00 +0000' \
  "$(date -u -d '2024-06-01 12:00 UTC' -R)"
chk 'date %j %U %V' '153 21 22' "$(date -u -d 2024-06-01 '+%j %U %V')"
# zoneinfo / terminfo dans la racine
[ -f /usr/share/zoneinfo/Europe/Paris ] && ok 'zoneinfo Europe/Paris' ||
  ko 'zoneinfo' 'absent'
[ -f /usr/share/terminfo/l/linux ] && ok 'terminfo linux' ||
  ko 'terminfo' 'absent'
# run-parts et cron.* ; /etc/crontab
mkdir -p $W/rp; printf '#!/bin/sh\necho un\n' > $W/rp/10a
printf '#!/bin/sh\necho deux\n' > $W/rp/20b; printf 'echo non\n' > $W/rp/30c
chmod +x $W/rp/10a $W/rp/20b
chk 'run-parts : executables, ordre' 'un deux' \
  "$(run-parts $W/rp | paste -s -d' ' -)"
chk 'run-parts --list' "$W/rp/10a $W/rp/20b" \
  "$(run-parts --list $W/rp | paste -s -d' ' -)"
grep -q 'cron.daily' /etc/crontab && ok '/etc/crontab : cron.daily' ||
  ko '/etc/crontab' 'ligne absente'
[ -x /etc/cron.daily/logrotate ] && [ -x /etc/cron.hourly/00sync ] &&
  ok 'cron.hourly / cron.daily installes' || ko 'cron.*' 'absents'
# logrotate
cat > $W/lr.conf <<EOC
rotate 2
$W/x.log {
  rotate 2
  missingok
}
EOC
echo un > $W/x.log
logrotate -f -s $W/lr.state $W/lr.conf
echo deux > $W/x.log
logrotate -f -s $W/lr.state $W/lr.conf
chk 'logrotate : x.log.1 et x.log.2' 'deux un' \
  "$(cat $W/x.log.1 $W/x.log.2 | paste -s -d' ' -)"
# ntpdate / rdate : serveur injoignable -> echec propre (pas de reseau)
ntpdate -q 127.0.0.1 > $W/ntp.txt 2>&1; chk 'ntpdate sans serveur' 1 $?
# e2tools sur le disque racine
dumpe2fs -h /dev/hda1 | grep -q 'Filesystem magic number:  0xEF53' &&
  ok 'dumpe2fs -h /dev/hda1' || ko 'dumpe2fs' 'sortie'
tune2fs -l /dev/hda1 | grep -q 'Block size' && ok 'tune2fs -l' ||
  ko 'tune2fs -l' x
e2label /dev/hda1 > $W/lab.txt 2>&1; chk 'e2label rc' 0 $?
resize2fs /dev/hda1 | grep -q 'Nothing to do' &&
  ok 'resize2fs : rien a faire' ||
  ko 'resize2fs' 'sortie'
# loadkeys -n
chk 'loadkeys -n fr (touche 16)' 'keycode 16 = a A nul' \
  "$(loadkeys -n fr | grep 'keycode 16 ')"
echo "LOT2-FIN ok=$P ko=$F"
