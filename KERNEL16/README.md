# KERNEL16

Noyau bootable 16 bits de **LINUX-0**, écrit en Turbo Pascal 7. Il reprend le
noyau de [MSDOS-0](https://github.com/gladir/MSDOS-0) (INT 21h, FAT12 et FAT16,
chargement de fichiers `.EXE` et `.COM`) et lui donne une saveur Linux :
interpréteur de commandes `sh`, chemins avec `/`, variables d'environnement
`USER`, `HOME`, `HOSTNAME`, `LANGUAGE`, arborescence `/bin` et `/etc`.

Les 177 commandes de [`../BIN16`](../BIN16) sont copiées sur les images et
s'exécutent telles quelles sur ce noyau (`ls`, `cat`, `cp`, `grep`, `awk`...).
Le noyau 32 bits (KERNEL32) viendra plus tard.

## Contenu du dossier

| Élément | Rôle |
|---|---|
| `KERNEL16.PAS` | L'unité du noyau (un seul fichier, aucune autre unité) |
| `MAKER.PAS` | Extrait le code du noyau et écrit `IO.SYS` (programme DOS) |
| `SH.PAS` | Interpréteur de commandes style Linux, devient `\BIN\SH.EXE` |
| `SYSTEM\` | Fichiers de la racine : `IO.SYS`, `MSDOS.SYS`, `BIN\SH.EXE`, `ETC\SYSCTL.D\CUSTOM.CFG` (configuration du noyau) |
| `TOOLS\` | Outils de fabrication des disques : `MAKEDISK.PAS`, `LSIMG.PAS`, `IMAGE.INF`, `ETC\PROFILE` |
| `IMAGE\` | Images prêtes à démarrer (voir `IMAGE\LISEZMOI.TXT`) |
| `TESTS\` | `TKENV.PAS` : programme de test du noyau (environnement, chemins `/`) |
| `BUILD.SH`, `MAKEIMG.BAT` | Construction complète sous Linux ou sous DOS/Windows |

## Essayer

```bash
qemu-system-i386 -fda IMAGE/LINUX144A.IMG -fdb IMAGE/LINUX144B.IMG -boot a
qemu-system-i386 -cdrom IMAGE/LINUX.ISO -boot d
```

Le shell affiche `root@linux0:/#`. La disquette A: contient le système, le shell
et les commandes de base ; B: contient le reste (`PATH=\BIN;B:\BIN`).
Les tuyaux `|` créent des fichiers temporaires dans `\TMP` : il faut donc un
support en écriture (disquette ou disque dur, pas le CD-ROM).

## Construire

```bash
./BUILD.SH                  # noyau, shell, outils, images
HD=32 ./BUILD.SH images     # ajoute LINUXHD.IMG (disque dur de 32 Mo)
```

Il faut `fpc` (Free Pascal) et `dosbox`. Le compilateur est `TPC.PAS` du dépôt
DEV-COOLS (variables `TPC` ou `DEVCOOLS`, voir l'en-tête de `BUILD.SH`).
`IO.SYS` est produit par `MAKER.EXE`, qui lit son propre code : c'est un
programme DOS, que `BUILD.SH` exécute sous DOSBox. Sous DOS ou Windows :
`MAKEIMG.BAT` (avec `TPC` dans le `PATH`).

`MAKEDISK` (voir `/?`) range les commandes dans `\BIN`, répartit sur autant de
disquettes que nécessaire (`/FLOPPY:720` pour des disquettes de 720 Ko), et
produit au choix un disque dur (`/HD:Mo`, FAT16 avec MBR) et un CD-ROM
(`/ISO`, ISO 9660 + El Torito). `LSIMG image /C` vérifie une image.

## Différences avec le noyau de MSDOS-0

- Nom et messages : `Demarrage de LINUX-0 KERNEL16...`, shell `\BIN\SH.EXE`
  (puis `\SH.EXE`, `\COMMAND.COM`), ou `kernel.shell` de `custom.cfg`.
- **Configuration de style Linux** : le noyau lit `/etc/sysctl.d/custom.cfg`
  (`\ETC\SYSCTL.D\CUSTOM.CFG`), au lieu de `CONFIG.SYS`. Une ligne par
  réglage, `clé = valeur`, `#` ou `;` pour un commentaire :

  | Clé | Effet |
  |---|---|
  | `fs.files` | nombre de fichiers ouverts (8 à 20) |
  | `kernel.buffers` | nombre de tampons |
  | `kernel.lastdrive` | dernière lettre de lecteur (A à F) |
  | `kernel.shell` | interpréteur de commandes (chemin et arguments) |
  | `kernel.device` | pilote de périphérique à charger (`DEVLOAD.EXE`) |
  | `kernel.install` | programme résident à lancer |
  | `env.NOM` | variable d'environnement du premier programme |

  À défaut, `\CONFIG.SYS` (ancienne syntaxe `FILES=`, `SHELL=`, `SET NOM=valeur`)
  est lu.
- **Langues** : français par défaut ; `env.LANGUAGE = EN` (anglais), `GR`
  (allemand), `SP` (espagnol) ou `IT` (italien) dans `custom.cfg` change les
  messages du noyau ; le shell et les outils lisent la même variable.
- **Chemins Linux** : `/` est converti en `\` pour toutes les fonctions INT 21h
  qui reçoivent un nom de fichier. La fonction 37h (caractère d'option) renvoie
  `-`.
- L'environnement hérité par un programme peut atteindre 2 Ko (400 octets avant).
- **API FCB supprimée** (fonctions 0Fh à 17h, 21h à 24h, 27h à 29h, qui
  répondent `AL=FFh`) : le segment de code du noyau est limité à 64 Ko et celui
  de MSDOS-0 était plein. Les programmes Turbo Pascal 7 utilisent les handles.
- **Correction** : l'écriture de 0 octet vers la console (que les programmes
  Turbo Pascal 7 font à la fermeture de `Output`) parcourait 65 536 octets de
  mémoire et remplissait l'écran de caractères ; sans cela les commandes de
  `BIN16` affichaient n'importe quoi.

## Contraintes de programmation respectées

Turbo Pascal 7 sans objet ; seules les unités `DOS` (et `Crt` pour le shell) ;
aucun fichier d'inclusion ; lignes de 80 caractères au plus ; sources en ASCII.

## Limites connues

- Le noyau est un seul segment de 64 Ko : il reste environ 9 Ko de marge.
- `SH.PAS` ne gère pas `$(...)`, `case`, les fonctions, les documents ici (`<<`),
  ni la complétion par Tab ; 16 arguments et 126 caractères par commande externe.
- Sur un CD-ROM démarré, `\TMP` est en lecture seule : pas de tuyaux.
- Les noms 8.3 de `BIN16` plus longs sont tronqués sur l'image
  (`ADDFTINFO` devient `ADDFTINF`).
- Testé sous QEMU (disquettes, disque dur, CD-ROM) et DOSBox, pas sur matériel réel.
