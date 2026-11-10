#!/bin/bash
# BUILD.SH - Construit KERNEL16 (noyau 16 bits LINUX-0) et ses images disque.
#
# Utilisation : ./BUILD.SH [etape ...]      etapes : tpc kernel shell tools
#                                                    images  (defaut : toutes)
#
# Variables d'environnement (facultatives) :
#   TPC       compilateur TPC deja compile (clone Turbo Pascal 7)
#   DEVCOOLS  dossier du depot DEV-COOLS (contient TPC.PAS), pour compiler
#             TPC avec Free Pascal si TPC n'est pas fourni
#   W         dossier de travail (defaut /tmp/linux0-kernel16)
#   HD        taille en Mo du disque dur a produire (defaut : aucun)
#   FLOPPY    format des disquettes en Ko (defaut 1440)
#   DATE      date des fichiers des images AAAA-MM-JJ (defaut : aujourd hui)
#
# Outils necessaires : fpc (Free Pascal), dosbox (pour generer IO.SYS).
# IO.SYS est genere par MAKER.EXE, un programme DOS qui lit son propre code.
set -e
HERE=$(cd "$(dirname "$0")" && pwd)
W=${W:-/tmp/linux0-kernel16}
DEVCOOLS=${DEVCOOLS:-$HERE/../../DEV-COOLS}
[ -d "$DEVCOOLS" ] || DEVCOOLS=$HERE/../../dev-cools
STEPS=${*:-tpc kernel shell tools images}
mkdir -p "$W"

has() { case " $STEPS " in *" $1 "*) return 0;; esac; return 1; }

# --- 1. compilateur TPC -----------------------------------------------------
if [ -z "$TPC" ]; then TPC=$W/tpc; fi
if has tpc && [ ! -x "$TPC" ]; then
 [ -f "$DEVCOOLS/TPC.PAS" ] || { echo "TPC.PAS introuvable : definir TPC ou DEVCOOLS"; exit 1; }
 echo "== Compilation de TPC (Free Pascal)"
 mkdir -p "$W/tpcsrc"; cp "$DEVCOOLS/TPC.PAS" "$W/tpcsrc/"
 ( cd "$W/tpcsrc" && fpc -O2 -Mtp TPC.PAS >/dev/null && cp TPC "$TPC" )
fi

# --- 2. noyau : KERNEL16.PAS + MAKER.PAS -> SYSTEM/IO.SYS ---------------------
if has kernel; then
 echo "== Noyau (IO.SYS)"
 rm -rf "$W/kernel"; mkdir -p "$W/kernel"
 cp "$HERE/KERNEL16.PAS" "$HERE/MAKER.PAS" "$W/kernel/"
 ( cd "$W/kernel" && "$TPC" -M -Q MAKER.PAS )
 printf '[sdl]\nfullscreen=false\n[autoexec]\nmount c %s\nc:\nMAKER.EXE\nexit\n' \
   "$W/kernel" > "$W/kernel/dosbox.conf"
 SDL_VIDEODRIVER=dummy timeout 120 dosbox -conf "$W/kernel/dosbox.conf" \
   -noconsole >/dev/null 2>&1 || true
 [ -f "$W/kernel/IO.SYS" ] || { echo "IO.SYS n'a pas ete genere"; exit 1; }
 cp "$W/kernel/IO.SYS" "$HERE/SYSTEM/IO.SYS"
 ls -l "$HERE/SYSTEM/IO.SYS"
fi

# --- 3. shell : SH.PAS -> SYSTEM/BIN/SH.EXE -----------------------------------
if has shell; then
 echo "== Shell (SH.EXE)"
 rm -rf "$W/shell"; mkdir -p "$W/shell"
 cp "$HERE/SH.PAS" "$W/shell/"
 ( cd "$W/shell" && "$TPC" -Q SH.PAS )
 mkdir -p "$HERE/SYSTEM/BIN"
 cp "$W/shell/SH.EXE" "$HERE/SYSTEM/BIN/SH.EXE"
 ls -l "$HERE/SYSTEM/BIN/SH.EXE"
fi

# --- 4. outils : MAKEDISK et LSIMG (natifs) -----------------------------------
if has tools; then
 echo "== Outils (MAKEDISK, LSIMG)"
 mkdir -p "$W/tools"
 fpc -Mtp -O1 -o"$W/tools/MAKEDISK" "$HERE/TOOLS/MAKEDISK.PAS" >/dev/null
 fpc -Mtp -O1 -o"$W/tools/LSIMG" "$HERE/TOOLS/LSIMG.PAS" >/dev/null
fi

# --- 5. images : disquettes, disque dur facultatif, CD-ROM --------------------
if has images; then
 echo "== Images (KERNEL16/IMAGE)"
 OPT=""
 [ -n "$HD" ] && OPT="$OPT /HD:$HD"
 [ -n "$FLOPPY" ] && OPT="$OPT /FLOPPY:$FLOPPY"
 ( cd "$HERE/TOOLS" && "$W/tools/MAKEDISK" /INF:IMAGE.INF $OPT \
     /DATE:${DATE:-$(date +%F)} )
 # CD-ROM : demarre en emulation de disquette 2,88 Mo, qui contient tous les
 # fichiers (le noyau n'a pas de pilote CD-ROM : seule cette disquette est
 # visible comme A: une fois demarre).
 rm -rf "$W/iso"; mkdir -p "$W/iso"
 ( cd "$HERE/TOOLS" && "$W/tools/MAKEDISK" /INF:IMAGE.INF /FLOPPY:2880 /ISO \
     /OUT:"$W/iso" /DATE:${DATE:-$(date +%F)} )
 cp "$W/iso/LINUX.ISO" "$HERE/IMAGE/LINUX.ISO"
 # (chemins relatifs : sous Linux "/x" serait pris pour une option)
 ( cd "$HERE/IMAGE" && for I in *.IMG; do
    echo "Controle de $I"; "$W/tools/LSIMG" "$I" /C /Q || true
   done )
fi
echo "Termine."
