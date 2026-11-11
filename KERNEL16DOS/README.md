# KERNEL16DOS

Noyau bootable 16 bits de **LINUX-0**, écrit en Turbo Pascal 7. Il reprend le
noyau de [MSDOS-0](https://github.com/gladir/MSDOS-0) (INT 21h, FAT12 et FAT16,
chargement de fichiers `.EXE` et `.COM`) et lui donne une saveur Linux :
interpréteur de commandes `sh`, chemins avec `/`, variables d'environnement
`USER`, `HOME`, `HOSTNAME`, `LANGUAGE`, arborescence `/bin` et `/etc`.

Les 177 commandes de [`../BIN16`](../BIN16) sont copiées sur les images et
s'exécutent telles quelles sur ce noyau (`ls`, `cat`, `cp`, `grep`, `awk`...).
Les autres noyaux (`KERNEL32`, `KERNELARM64`...) auront chacun leur propre
dossier indépendant : voir la règle de nommage `KERNEL<arch/bits><personnalité>`
dans la section « Noyaux » du [README racine](../README.md). Ici la
personnalité est `DOS` (interface `INT 21h`, `.EXE`, FAT) ; l'unité du noyau
s'appelle `K16DOS` pour rester compatible 8.3 avec TP7 sous DOS.

## Contenu du dossier

| Élément | Rôle |
|---|---|
| `K16DOS.PAS` | L'unité du noyau (un seul fichier, aucune autre unité) |
| `MAKER.PAS` | Extrait le code du noyau et écrit `IO.SYS` (programme DOS) |
| `SH.PAS` | Interpréteur de commandes style Linux, devient `\BIN\SH.EXE` |
| `SYSTEM\` | Fichiers de la racine : `IO.SYS`, `MSDOS.SYS`, `BIN\SH.EXE`, `ETC\SYSCTL.D\CUSTOM.CFG` (configuration du noyau) |
| `TOOLS\` | Outils : `MAKEDISK.PAS` (images), `LSIMG.PAS` (contrôle d'images), **`INSTALL.PAS`** (installation sur disque dur), `IMAGE.INF`, `ETC\PROFILE` |
| `IMAGE\` | Images prêtes à démarrer (voir `IMAGE\LISEZMOI.TXT`) |
| `TESTS\` | `TKENV.PAS` et `TKDATE.PAS` : programmes de test du noyau (environnement, chemins `/`, date) ; `DEVENVTEST.PY` : banc d'essai des images dans l'émulateur de `DEVENV` |
| `BUILD.SH`, `MAKEIMG.BAT` | Construction complète sous Linux ou sous DOS/Windows |

## Essayer

```bash
qemu-system-i386 -fda IMAGE/LINUX144A.IMG -fdb IMAGE/LINUX144B.IMG -boot a
qemu-system-i386 -cdrom IMAGE/LINUX.ISO -boot d
```

Le shell affiche `root@linux0:/#`. La disquette A: contient le système, le shell
et les commandes de base ; B: contient le reste (`PATH=\BIN;B:\BIN`).
Les tuyaux `|` créent des fichiers temporaires dans `\TMP` : il faut donc un
support en écriture (disquette ou disque dur, pas un vrai CD-ROM gravé).
L'ISO démarre en émulation de disquette 2,88 Mo qui contient les 181 fichiers :
le noyau n'a pas de pilote CD-ROM, cette disquette est donc le lecteur `A:`.

## Installer sur un disque dur

Démarrer sur `LINUX144A.IMG` (ou sur le CD-ROM) avec un disque dur, puis taper
`install`. `TOOLS/INSTALL.PAS` (`\BIN\INSTALL.EXE`) fonctionne comme l'installeur
de MSDOS-0 : écrans bleus plein texte, **partitionne** le disque (MBR et
partition active, de 4 à 1000 Mo), le **formate** (FAT12 ou FAT16) et **installe**
le système selon la configuration choisie :

1. bienvenue ; 2. date, heure, pays et langue (`env.LANGUAGE`) ;
3. nom de machine, utilisateur et `HOME` ;
4. disque (80h ou 81h), taille de la partition, formatage, avec avertissement et
   confirmation ; si la partition est déjà une FAT valide, les données peuvent
   être conservées (IO.SYS est replacé en tête du volume) ;
5. type d'installation : *Minimale*, *Standard*, *Complète* ou *Personnalisée*
   (cases à cocher avec la taille de chaque composant) ;
6. réglages du noyau (`fs.files`, `kernel.buffers`, `kernel.lastdrive`) ;
7. copie des fichiers (disquette 2 demandée au besoin, en A: ou en B:), puis
   écriture de `\ETC\SYSCTL.D\CUSTOM.CFG` et `\ETC\PROFILE`, secteur de boot et
   MBR, redémarrage.

| Composant | Contenu |
|---|---|
| 0 Système | `IO.SYS`, `MSDOS.SYS`, `\BIN\SH.EXE`, `\ETC` (toujours installé) |
| 1 Commandes de base | `cat`, `cp`, `mv`, `rm`, `ls`, `echo`, `date`, `df`... |
| 2 Traitement de texte | `grep`, `sed`, `awk`, `sort`, `diff`, `cut`... |
| 3 Éditeurs | `vi`, `ed`, `nano`, `pico`, `emacs`, `less` |
| 4 Archives et compression | `gzip`, `bzip2`, `ar`, `compress`... |
| 5 Programmation et scripts | `make`, `perl`, `python`, `bash`, `bc`, `lex`... |
| 6 Système, utilisateurs, réseau | `useradd`, `groups`, `ifconfig`, `crontab`... |
| 7 Divers | le reste de `\BIN` (groff, outils netpbm...) |

La liste des fichiers par disquette et par composant est `\INSTALL.INF`, écrit par
`MAKEDISK` (lignes `INSTALL` et `COMP n liste` d'`IMAGE.INF`). Les textes de
l'installeur existent en français, anglais, allemand, espagnol et italien
(`LANGUAGE`, ou choix à l'écran 2). Testé sous QEMU et sous DEVENV : installation
complète, minimale et personnalisée, partition de 4 Mo (FAT12), de 20 Mo sur
64 Mo, disque 81h, réinstallation par-dessus un disque installé, et démarrage du
disque installé. Limites : CHS classique (1024 premiers cylindres, partition
d'au plus 1000 Mo) ; « conserver » n'accepte que la première partition ;
`kernel.country` est écrit mais ignoré par le noyau.

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

- Nom et messages : `Demarrage de LINUX-0 KERNEL16DOS...`, shell `\BIN\SH.EXE`
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
- Sur un CD-ROM gravé, `\TMP` est en lecture seule : pas de tuyaux.
- **Correctifs** : `INT 21h AH=2Bh` (fixer la date) convertit l'année en BCD pour le
  BIOS ; sans `kernel.shell`, le shell n'est plus lancé avec un argument parasite.
- Les noms 8.3 de `BIN16` plus longs sont tronqués sur l'image
  (`ADDFTINFO` devient `ADDFTINF`).
- Testé sous QEMU (disquettes, disque dur, CD-ROM) et DOSBox, pas sur matériel réel.

## Tests sous l'émulateur DEVENV

`TESTS/DEVENVTEST.PY` amorce une image dans l'émulateur DOS de
`DEV-COOLS/DEVENV.PAS` (`/KERNELTEST` et `/KTBOOTIMG`, sans interface
graphique), tape une trentaine de commandes et vérifie l'écran émulé :

```bash
export DEVENV=/chemin/DEVENV      # exécutable compilé pour Linux
TESTS/DEVENVTEST.PY IMAGE/LINUX144A.IMG --b IMAGE/LINUX144B.IMG
TESTS/DEVENVTEST.PY IMAGE/LINUX.ISO --all
TESTS/DEVENVTEST.PY LINUXHD.IMG --all
```

Résultat : disquettes 1,44 Mo A+B, ISO et disque dur de 32 Mo, 36 vérifications
sur 36 ; disquettes de 720 Ko, 1,2 Mo et 2,88 Mo, 9 sur 9. Pour compiler
`DEVENV.PAS` sous Linux, voir `DEV-COOLS/DOC/KERNELTEST.txt` (unité `cthreads`,
`fp-units-gfx`, bibliothèques X11 et remplacement des DLL Windows).
### Dans l'onglet émulateur de l'IDE

Avec l'interface graphique (sous Linux : `xvfb-run`, `xdotool` pour les frappes,
`import` pour les captures), l'onglet « Émulateur 8086 » démarre les images ainsi :

```bash
DEVENV /DISK0:LINUX144A.IMG /DISK1:LINUX144B.IMG /DISK80:hd.img /TERMINALDOS:boot.bat   # boot.bat : BOOT A:
DEVENV /CDROM:LINUX.ISO /TERMINALDOS:cd.bat   # cd.bat : BOOT puis IMGMOUNT C: hd.img -t hdd
DEVENV /DISK80:hd.img /TERMINALDOS:bootc.bat  # bootc.bat : BOOT C: (disque installé)
```

Scénarios vérifiés de bout en bout avec `install` : disquettes A: + B: puis
démarrage du disque installé (onglet « C: »), CD-ROM, installation *minimale*
en anglais avec un nom de machine personnalisé, et changement de disquette avec
un seul lecteur (`mount A:` du banc `/KERNELTEST`). Remarques :

- l'onglet **consomme la touche Échap** pour arrêter l'émulation (« [Esc] Fermer ») ;
  les flèches et F1 à F12 sont transmises. L'installeur accepte donc **F4 comme
  équivalent d'Échap** (« ECHAP/F4=Retour ») ;
- la copie se fait désormais disquette par disquette : avec un seul lecteur,
  chaque disquette n'est réclamée qu'une fois (avant, l'ordre alphabétique des
  fichiers réclamait les disquettes 1 et 2 en alternance) ;
- `BOOT` d'un CD-ROM n'est possible que si aucun disque n'est déjà monté : on
  monte le disque dur cible ensuite avec `IMGMOUNT C: hd.img -t hdd`.

Ces tests ont révélé un bogue de l'émulateur (caractère perdu à l'écran,
`INT 10h AH=02` ne mettait pas à jour `BdaCurX/Y`), corrigé dans la branche
`fix/devenv-int10-curseur-bda` de DEV-COOLS.
