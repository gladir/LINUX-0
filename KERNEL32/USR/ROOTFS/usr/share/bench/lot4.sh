# essais du lot E6 (bureaux) sous KERNEL32 : sh /usr/share/bench/lot4.sh
# k32-session (get/set/run, replis), alias GNOME/KDE, fichiers .desktop.
W=/tmp/lot4; rm -rf $W; mkdir -p $W; cd $W
LANGUAGE=EN; export LANGUAGE
P=0; F=0
ok() { echo "LOT4-OK $1"; P=$((P+1)); }
ko() { echo "LOT4-KO $1 : $2"; F=$((F+1)); }
chk() { [ "$2" = "$3" ] && ok "$1" || ko "$1" "attendu [$2] obtenu [$3]"; }
has() { grep -q -e "$3" "$2" && ok "$1" || ko "$1" "motif [$3] absent de $2"; }
SAVE=$(cat /etc/k32/session 2>/dev/null)
# ---- k32-session get / set ----
k32-session set terminal; chk 'k32-session set terminal' terminal \
  "$(k32-session get)"
k32-session set KDE; chk 'k32-session set KDE -> kde' kde "$(k32-session get)"
chk 'fichier /etc/k32/session' kde "$(cat /etc/k32/session)"
k32-session set bogus 2> bad.txt; chk 'mode invalide : code 1' 1 $?
has 'mode invalide : message' bad.txt 'mode invalide'
chk 'mode inchange apres refus' kde "$(k32-session get)"
echo GNOME > /etc/k32/session
chk 'get normalise la casse' gnome "$(k32-session get)"
echo zzz > /etc/k32/session
chk 'fichier invalide -> terminal' terminal "$(k32-session get)"
rm -f /etc/k32/session
chk 'fichier absent -> terminal' terminal "$(k32-session get)"
# ---- run ----
k32-session set terminal; k32-session run; chk 'run terminal : code 0' 0 $?
mv /usr/bin/geoworks /usr/bin/geoworks.x 2>/dev/null
mv /bin/geoworks /bin/geoworks.x 2>/dev/null
k32-session set geoworks
k32-session run > run1.txt 2>&1; chk 'run geoworks absent : code 11' 11 $?
has 'run geoworks absent : message' run1.txt 'absent'
mv /usr/bin/geoworks.x /usr/bin/geoworks 2>/dev/null
mv /bin/geoworks.x /bin/geoworks 2>/dev/null
[ -x /usr/bin/geoworks ] && ok 'geoworks installe (/usr/bin/geoworks)' ||
  ko 'geoworks installe' 'absent'
mv /dev/fb0 /dev/fb0.x 2>/dev/null
k32-session set gnome
k32-session run > run2.txt 2>&1; chk 'run sans /dev/fb0 : code 10' 10 $?
has 'run sans /dev/fb0 : message' run2.txt 'fb0 indisponible'
mv /dev/fb0.x /dev/fb0 2>/dev/null
mv /usr/bin/k32-gnome /usr/bin/k32-gnome.real 2>/dev/null
mv /bin/k32-gnome /bin/k32-gnome.real 2>/dev/null
printf '#!/bin/sh\nexit 5\n' > /usr/bin/k32-gnome; chmod 755 /usr/bin/k32-gnome
k32-session run > run3.txt 2>&1; chk 'environnement en echec : code 12' 12 $?
has 'environnement en echec : message' run3.txt 'a echoue'
printf '#!/bin/sh\nexit 0\n' > /usr/bin/k32-gnome
k32-session run > run4.txt 2>&1; chk 'environnement qui rend 0 : code 0' 0 $?
printf '#!/bin/sh\necho K=$K32_USER U=$K32_UID H=$K32_HOME T=$K32_TTY\n' \
  > /usr/bin/k32-gnome
k32-session run > run5.txt 2>&1
has 'variables K32_* transmises' run5.txt 'K=.* T=/dev/tty1'
rm -f /usr/bin/k32-gnome
mv /usr/bin/k32-gnome.real /usr/bin/k32-gnome 2>/dev/null
mv /bin/k32-gnome.real /bin/k32-gnome 2>/dev/null
has 'journal /var/log/k32-session.log' /var/log/k32-session.log 'echoue'
k32-session status > st.txt
has 'status : mode' st.txt '^mode: gnome'
has 'status : fb0' st.txt '^fb0: ok'
# ---- commandes compatibles et fichiers freedesktop ----
for c in k32-gnome gnome-session gnome-terminal k32-kde startplasma-x11 \
         startkde konsole dolphin k32-session; do
  [ -x /bin/$c ] && ok "commande $c" || ko "commande $c" 'absente'
done
gnome-terminal --help > h1.txt; has 'gnome-terminal --help' h1.txt 'Usage'
konsole --help > h2.txt; has 'konsole --help' h2.txt 'Usage'
[ -f /usr/share/xsessions/gnome.desktop ] && ok 'xsessions/gnome.desktop' ||
  ko 'xsessions/gnome.desktop' x
has 'gnome.desktop : Exec' /usr/share/xsessions/gnome.desktop \
  'Exec=/usr/bin/gnome-session'
has 'plasma.desktop : Exec' /usr/share/xsessions/plasma.desktop \
  'Exec=/usr/bin/startplasma-x11'
has 'applications/*.desktop' /usr/share/applications/k32-nano.desktop \
  '^Exec=nano'
# ---- k32-input ----
k32-input > ki0.txt; chk 'k32-input : usage, code 0' 0 $?
has 'k32-input : usage' ki0.txt 'status|usb|vbox|ps2|auto|log'
k32-input status > ki1.txt 2>&1; chk 'k32-input status : code 0' 0 $?
has 'k32-input status : /proc/k32input' ki1.txt '=== /proc/k32input'
has 'k32-input status : messages' ki1.txt '=== messages du noyau'
k32-input log > ki2.txt 2>&1; chk 'k32-input log : code 0' 0 $?
has 'k32-input log : rapport' /tmp/k32-input.txt '=== /dev/input'
k32-input bogus 2> ki3.txt; chk 'k32-input mode invalide : code 2' 2 $?
if [ -w /proc/sys/k32/usb_enable ]; then
  OLDU=$(cat /proc/sys/k32/usb_enable); OLDV=$(cat /proc/sys/k32/vbox_enable)
  k32-input ps2 > ki4.txt 2>&1
  chk 'k32-input ps2 : usb_enable 0' 0 "$(cat /proc/sys/k32/usb_enable)"
  k32-input vbox > ki4.txt 2>&1
  chk 'k32-input vbox : vbox_enable 1' 1 "$(cat /proc/sys/k32/vbox_enable)"
  echo $OLDU > /proc/sys/k32/usb_enable; echo $OLDV > /proc/sys/k32/vbox_enable
else
  k32-input usb > ki4.txt 2>&1; chk 'k32-input usb sans sysctl : code 1' 1 $?
  has 'k32-input usb : message' ki4.txt 'absent ou non modifiable'
fi
# ---- ls : gros dossiers, tube / terminal ----
mkdir -p $W/lsd; cd $W/lsd
i=0; while [ $i -lt 1000 ]; do : > f$i; i=$((i+1)); done
cd $W
chk 'ls | wc -l : 1000 entrees (tube, une par ligne)' 1000 \
  "$(ls lsd | wc -l | tr -d ' ')"
chk 'ls -1 | wc -l : 1000' 1000 "$(ls -1 lsd | wc -l | tr -d ' ')"
chk 'ls -l | wc -l : 1000' 1000 "$(ls -l lsd | wc -l | tr -d ' ')"
chk 'ls -a | wc -l : 1002 (. et ..)' 1002 "$(ls -a lsd | wc -l | tr -d ' ')"
chk 'ls -R | wc -l : 1000' 1000 "$(ls -R lsd | wc -l | tr -d ' ')"
chk 'ls : tri alphabetique (premiere ligne)' f0 "$(ls lsd | head -1)"
chk 'ls -r : tri inverse (premiere ligne)' f999 "$(ls -r lsd | head -1)"
ls -C lsd > ls_c.txt
[ "$(wc -l < ls_c.txt | tr -d ' ')" -lt 1000 ] &&
  ok 'ls -C dans un tube : colonnes (moins de 1000 lignes)' ||
  ko 'ls -C dans un tube' "$(wc -l < ls_c.txt)"
script -q -c "ls lsd" ls_tty.txt > /dev/null 2>&1
N=$(wc -l < ls_tty.txt | tr -d ' ')
[ "$N" -gt 1 ] && [ "$N" -lt 400 ] &&
  ok "ls sur un terminal : colonnes ($N lignes)" ||
  ko 'ls sur un terminal : colonnes' "$N lignes"
mkdir -p lsd300; cd lsd300
i=0; while [ $i -lt 300 ]; do : > g$i; i=$((i+1)); done
cd $W
chk 'ls : 300 entrees (pas de coupure a 240)' 300 \
  "$(ls lsd300 | wc -l | tr -d ' ')"
echo "${SAVE:-terminal}" > /etc/k32/session
echo "LOT4-FIN ok=$P ko=$F"
