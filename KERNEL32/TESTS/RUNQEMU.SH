#!/bin/bash
# @author: Sylvain Maltais (support@gladir.com)
# @created: 2026
# @website(https://www.gladir.com/linux-0)
# @description: Banc d'essai QEMU reutilisable (disque dur ou noyau ELF) :
#     RUNQEMU.SH [options] IMAGE.IMG|NOYAU.ELF [commande...]
#   Lance qemu-system-i386 sans ecran, COM1 sur la sortie standard (le noyau
#   ecrit sur la console serie), et affiche ce que le noyau ecrit.
#     -m Mo       memoire (defaut 64)
#     -t secondes delai maximal (defaut 20)
#     -s MOTIF    arreter (0,5 s plus tard) quand MOTIF (regex) apparait
#     -e TEXTE    TEXTE doit apparaitre (sinon code de sortie 1; repetable)
#     -a LIGNE    ligne de commande du noyau (mode -kernel seulement)
#     -S          disque en lecture seule (snapshot : rien n'est ecrit)
#     -x ARG      argument supplementaire pour qemu (repetable)
#     commande... lignes envoyees ensuite sur la console serie, une par
#                 argument, chacune apres l'arrivee d'une nouvelle ligne
#                 d'invite se terminant par "# ", "$ ", "> " ou ": " ; pour
#                 un motif (regex) precis : "MOTIF=LIGNE" (une commande
#                 qui contient = s'ecrit "=commande").
#   Un fichier .img est amorce comme disque dur IDE (MBR + chargeur + ext2) ;
#   un ELF est lance directement par "qemu -kernel" (protocole Multiboot sans
#   chargeur : comparaison avec l'amorce par disque).
#   Le noyau peut quitter QEMU par le peripherique isa-debug-exit (port F4h)
#   ou l'extinction ACPI (port 604h, mot 2000h).
HERE=$(cd "$(dirname "$0")" && pwd)
MEM=64; TMO=20; ARGS=()
while getopts "m:t:s:e:a:Sx:" o; do
  case $o in
    m) MEM=$OPTARG ;; t) TMO=$OPTARG ;;
    s) ARGS+=(-s "$OPTARG") ;; e) ARGS+=(-e "$OPTARG") ;;
    a) ARGS+=(-a "$OPTARG") ;; S) ARGS+=(-S) ;; x) ARGS+=(-x "$OPTARG") ;;
    *) sed -n '5,28p' "$0"; exit 2 ;;
  esac
done
shift $((OPTIND - 1))
T=${1:?image ou noyau}
shift
for c in "$@"; do
  case $c in
    *=*) ARGS+=(-c "$c") ;;
    *) ARGS+=(-c "=$c") ;;
  esac
done
exec python3 "$HERE/QEMU.PY" run "$T" -m "$MEM" -t "$TMO" "${ARGS[@]}"
