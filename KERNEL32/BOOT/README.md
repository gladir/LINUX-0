# KERNEL32 / BOOT : amorce sur disque dur (MBR + partition ext2)

KERNEL32 s'amorce depuis une **partition Linux** (type `83h`, active) d'un
disque dur MBR, formatée en **ext2, ext3 ou ext4**, sans GRUB ni LILO : le MBR charge un
chargeur (*stage2*) placé juste après lui, qui lit l'ext2, charge le fichier
ELF32 `/boot/linux0` en mémoire haute et saute dans le noyau en mode protégé,
par le protocole **Multiboot 1**.

| Fichier | Rôle |
|---|---|
| `MBR.ASM` / `MBR.BIN` | secteur 0 : 446 octets de code, table des partitions, `55AAh` (nasm) |
| `STAGE2.ASM` / `STAGE2H.BIN` | tête du chargeur (2 secteurs, nasm) : A20, carte mémoire INT 15h, passage en mode protégé |
| `LOADER.PAS` / `LOADER.SYS` | corps du chargeur, **en Pascal**, compilé par `lpc -K0840` : ext2, ELF, Multiboot |
| `STAGE2.BIN` | `STAGE2H.BIN` + `LOADER.SYS` : écrit dans les secteurs 1 à N du disque |

Les `.BIN`/`.SYS` sont fournis (le build ne dépend pas de nasm) ; `KERNEL32/BUILD.SH boot`
les régénère.

## Disposition du disque (`TOOLS/MKIMAGE.SH`)

```
secteur 0          MBR (code 446 octets + paramètres + table + 55AAh)
secteurs 1..N      chargeur STAGE2.BIN (N = 53 environ, 120 au plus)
secteurs N+1..2047 libres
secteur 2048 ...   partition 1 : type 83h, active, ext2
```

Paramètres du MBR remplis par MKIMAGE : octets 3..6 = LBA du chargeur (1),
octets 7..8 = nombre de secteurs du chargeur, octet 14 = 0 (auto) ou 2
(forcer CHS, essais). Le MBR refuse de s'exécuter si le chargeur recouvre le
début de la partition active.

## Déroulement

1. Le BIOS charge le MBR en `0000:7C00` (DL = unité). Le MBR cherche la
   première entrée active, charge les N secteurs du chargeur en `0000:8000`
   (INT 13h AH=42h, sinon CHS AH=02h), vérifie la signature `'L232'` en
   `8003h` et saute en `0000:8000` avec **DL = unité BIOS** et
   **DS:SI = entrée de la partition** (`0000:7DBE + 16*i`).
2. La tête (`8000h`, 2 secteurs) mémorise l'unité, le numéro, le type, le
   LBA de début et la taille de la partition (variables en `8007h`..`802Ch`),
   puis saute au corps Pascal en `0840:0000`.
3. Le corps active A20 (BIOS 2401h, port 92h, contrôleur 8042, vérifié),
   lit la carte mémoire (E820, sinon E801, sinon 88h), monte l'ext2,
   résout `/boot/linux0` (ou `kernel=` de `/boot/linux0.cfg`), charge chaque
   segment `PT_LOAD` à `p_paddr` par INT 15h AH=87h (zéros pour
   `p_memsz > p_filesz`), construit la structure Multiboot puis appelle la
   tête (`0000:8046`) qui passe en mode protégé.
4. Les messages s'affichent à l'écran (INT 10h) **et** sur COM1 (115200
   bauds, 8N1), ce qui permet les essais sans écran. En cas d'erreur
   (`ERREUR : noyau /boot/linux0 introuvable`, ext2 invalide, ELF invalide,
   mémoire insuffisante, lecture disque...) le chargeur écrit
   `Systeme arrete.` et attend (Ctrl-Alt-Suppr redémarre).

## Remise au noyau (à lire par le noyau)

À l'entrée du noyau, au point d'entrée **physique** de l'ELF :

| Registre | Valeur |
|---|---|
| `EAX` | `2BADB002h` |
| `EBX` | `0007E000h`, adresse physique de la structure Multiboot |
| `CS` | `08h` : code 32 bits plat, base 0, limite 4 Go |
| `DS ES FS GS SS` | `10h` : données plates 4 Go |
| `ESP` | `00090000h` (pile libre sous 90000h) |
| `EFLAGS` | interruptions coupées (IF=0), DF=0 ; pagination coupée ; A20 actif ; mode protégé 32 bits (CR0.PE=1) |
| GDT | provisoire, en `0000:8xxx` (dans la zone du chargeur) : le noyau doit charger la sienne |

Le noyau doit **copier ce dont il a besoin** (cmdline, mmap) avant de
réutiliser la mémoire basse. Zones occupées par l'amorce : `00007C00h-00007DFFh`
(MBR), `00008000h-0001FFFFh` (chargeur et ses données), `00060000h-0006FFFFh`
(tampons), `0007E000h-0007EFFFh` (structure Multiboot, ci-dessous). Tout le
reste sous 640 Ko est libre, ainsi que la mémoire à partir de 1 Mo en dehors
du noyau.

### Structure Multiboot 1 (`0007E000h`)

`flags = 00000247h` (bits 0, 1, 2, 6, 9) ; `00000207h` si E820 absent
(bit 6 à zéro, mémoire d'après E801/88h).

| Décalage | Champ | Contenu |
|---|---|---|
| 0 | `flags` | `247h` |
| 4 | `mem_lower` | Ko sous 1 Mo (INT 12h, 639 d'ordinaire) |
| 8 | `mem_upper` | Ko contigus à partir de 1 Mo (plafonné à 2093056 Ko) |
| 12 | `boot_device` | `[unité BIOS][partition 0-3][FFh][FFh]` : `8000FFFFh` = unité 80h, 1re entrée, hda1 |
| 16 | `cmdline` | adresse physique `0007E080h` : chaîne ASCIIZ de 255 caractères au plus |
| 20..40 | `mods`, `syms` | 0 (flags 3, 4, 5 à zéro) |
| 44 | `mmap_length` | octets de la carte (somme des `size+4`) |
| 48 | `mmap_addr` | `0007E200h` |
| 64 | `boot_loader_name` | `0007E060h` : `LINUX-0` |
| autres | | 0 |

Carte mémoire (`0007E200h`, 100 entrées au plus) au format Multiboot : pour
chaque entrée `size` (dword, 20 ou 24, **sans** compter lui-même), `base`
(qword), `length` (qword), `type` (dword : 1 = libre, 2 = réservée, 3 = ACPI,
4 = ACPI NVS, 5 = défectueuse). La suivante est à `adresse + size + 4`. Ce
sont les entrées INT 15h E820 brutes (les entrées ACPI 3 désactivées sont
écartées). Ne sont **pas** dans la carte : le chargeur, le noyau ni la
structure elle-même : le noyau les retranche.

### Ligne de commande

Par défaut : `root=/dev/hda1 ro` (le disque est `hd` + lettre de l'unité
BIOS (80h = a) et le chiffre est l'entrée de partition + 1). Elle est
remplacée par `/boot/linux0.cfg` (texte, une directive par ligne, `#`
ignoré ; lignes ni `kernel=` ni `cmdline=` ignorées) :

```
kernel=/boot/linux0
cmdline=root=/dev/hda1 rw init=/sbin/init
chs=1          # essais : lire le noyau en CHS au lieu de LBA
```

## Systèmes de fichiers supportés : ext2, ext3, ext4

* blocs de **1024, 2048, 4096** octets (plus grand : refusé) ; inodes de **128
  à 1024** octets ; révisions **0 et 1** ;
* fonctions incompatibles lisibles : `filetype`, `extents` (ext4 : arbre de
  profondeur 3 au plus ; les extensions non initialisées se lisent comme des
  trous), `64bit` (descripteurs de groupes de 64 octets), `flex_bg`,
  `csum_seed`, `large_dir` ; `recover` (journal ext3/ext4 non rejoué : le
  chargeur affiche un avertissement et lit les blocs tels quels sur le
  disque, le noyau rejouera le journal au montage) ;
* refusées avec un message : `meta_bg`, `inline_data`, compression, chiffrement,
  journal externe..., blocs de plus de 4 Ko ; les fonctions `ro_compat`
  (sommes de contrôle, `huge_file`...) sont sans effet sur la lecture ;
* répertoires linéaires et indexés (`dir_index` : les noeuds d'index sont des
  entrées vides, les blocs se lisent à la suite ; les répertoires de
  plusieurs milliers d'entrées sont lus linéairement) ;
* fichiers : blocs directs, indirects simples, doubles et **triples**, ou
  extents ; les trous (blocs 0) lisent des zéros ; liens symboliques (courts et
  longs, profondeur 8) dans le chemin du noyau ;
* essais : `TESTS/K/RUNBOOT4.SH [-o "options mke2fs"] [-N entrées]` (ext4 par
  défaut avec `metadata_csum`, `64bit`, `flex_bg`, journal, `/boot` de 300
  entrées indexé, noyau creux donc à extensions multiples) ; la ligne
  `mke2fs` historique (ext2 simple) reste documentée dans `TOOLS/MKIMAGE.SH` :
  `-t ext2 -b 1024 -I 128 -r 1 -O none,filetype,sparse_super`. L'installateur
  (`USR/INSTALL.PAS`) et `mkfs.ext2` fabriquent toujours de l'ext2 sans journal.

## Noyau chargé

ELF32 `ET_EXEC`, `EM_386`. Chaque `PT_LOAD` est écrit à `p_paddr`
(en-dessous de `C0000000h` ; si `p_paddr` est lui-même `>= C0000000h`
il est ramené d'autant) ; `p_paddr >= 1 Mo` et fin du noyau `< 16 Mo`
(limite d'INT 15h AH=87h, adresses sur 24 bits) et dans la mémoire détectée.
Le point d'entrée `e_entry` est converti en physique s'il tombe dans un
segment dont `p_vaddr != p_paddr` (`C0100000h` -> `00100000h`). Le noyau doit
avoir un en-tête Multiboot dans ses 8 premiers Ko seulement pour pouvoir
aussi être lancé par `qemu -kernel` ; le chargeur ne le lit pas.

## Limites

* disque dur BIOS seulement (unité >= 80h) ; disquette et CD-ROM : plus tard ;
* LBA sur 32 bits (disques de moins de 2 To) ; le repli CHS ne voit que les
  8 premiers Go ;
* le noyau doit tenir sous 16 Mo (INT 15h AH=87h) ; au-delà, il devra se
  charger lui-même en deux temps (ou un futur chargeur en « unreal mode ») ;
* un seul noyau, pas de menu : `kernel=` de `linux0.cfg` choisit le fichier.

## Fabrication et essais

```bash
KERNEL32/BUILD.SH boot              # MBR.BIN, STAGE2H.BIN, LOADER.SYS, STAGE2.BIN
KERNEL32/TOOLS/MKIMAGE.SH -o X.IMG -k NOYAU.ELF -r RACINE
KERNEL32/TESTS/RUNQEMU.SH X.IMG     # ou un ELF : qemu -kernel
KERNEL32/TESTS/QEMU.PY boot         # batterie complète (une minute environ)
KERNEL32/TESTS/E2CHECK.SH X.IMG NOYAU.ELF   # e2fsck + lecteur indépendant
```

## initrd (partie 38 du noyau)

`/boot/linux0.cfg` accepte `initrd=/chemin` : le fichier (cpio newc, brut ou
gzip) est lu apres le noyau (a l'adresse arrondie a la page, **sous 16 Mo**,
limite de INT 15h/87h) et transmis comme **module Multiboot** (flag 3,
`mods_count` en 20, `mods_addr` en 24, un module en `7E070h`). `TOOLS/MKIMAGE.SH
-I initrd.cpio.gz` le copie en `/boot/initrd.img` et ecrit la ligne.
