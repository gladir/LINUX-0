# KERNEL16UNIX : noyau LINUX-0 16 bits, personnalité UNIX

Noyau UNIX pour IBM PC (8086/8088, mode réel), écrit en Pascal dans **un seul
fichier source**, `KERNEL.PAS`, et compilé par **Linux Pascal** (`TOOLS/LPC.PAS`)
en **une seule image monolithique** de plus de 64 Ko (environ 187 Ko : 160 Ko
de code répartis en segments, 30 Ko de données). Son interface suit celle de
**UNIX V7** (numéros et sémantique des appels système, signaux, `wait`,
`stat`, terminal, utilisateurs), complétée par quelques appels de 4.2BSD.

Les noyaux du projet se nomment `KERNEL<architecture et bits><personnalité>` :
la personnalité **UNIX** est celle de ce noyau : appels système V7 par
`INT 80h`, exécutables **COFF**, système de fichiers **UFS**. Il n'a
volontairement aucun support de FAT : les disquettes et disques DOS relèvent
de `KERNEL16DOS`.

Le noyau se présente comme **LINUX-0** : bannière d'amorce
(`LINUX-0 KERNEL16UNIX version 0.1`), appel système `uname` (`sysname`
`LINUX-0`, `nodename` `linux0`, `release` `KERNEL16UNIX`), `/etc/issue` et
`/etc/motd`. Ses messages (amorce, `panic`) sont en **français** : il ne peut
pas lire la variable d'environnement `LANGUAGE` à l'amorce (aucun processus
n'existe encore). Tous les programmes utilisateur (installateur, `login`,
`passwd`, `sh`…) choisissent leur langue par `LANGUAGE` : français par défaut,
`EN` anglais, `GR` allemand, `SP` espagnol, `IT` italien.

## Fichiers

| Fichier | Rôle |
|---|---|
| `KERNEL.PAS` | le noyau (segments-unités KTypes, KLib, KMem, KSched, KDisk, KSwap, KTty, KUfs, KVfs, KProc, KSys et le programme principal) |
| `INIT.PAS` | processus 1 (`/etc/init`) : lit `/etc/ttys`, lance `getty` sur chaque terminal et le relance, récupère les orphelins |
| `USR/SHELL.PAS` | `/bin/sh`, l'interpréteur de commandes UNIX |
| `USR/GETTY.PAS`, `USR/LOGIN.PAS` | `/etc/getty` et `/bin/login` : connexion avec `/etc/passwd` |
| `USR/PASSWD.PAS` | `/bin/passwd` (set-uid root) |
| `USR/PS.PAS`, `USR/KILL.PAS`, `USR/ID.PAS` | processus, signaux, identité |
| `USR/MKDIR.PAS`, `USR/RMDIR.PAS`, `USR/RM.PAS` | répertoires et suppression |
| `USR/INSTALL.PAS` | `/bin/install`, l'installation sur un disque dur depuis les disquettes ou le CD-ROM (en cinq langues) |
| `UFSBOOT.ASM` / `.BIN` | amorce UFS1 (8 Ko, dans la zone d'amorce du système de fichiers : partition de disque dur ou disquette entière) : charge `/unix` à 1000:0000 |
| `MBR.ASM` / `.BIN` | secteur de partition du disque dur |
| `BUILD.SH` | construit le compilateur, le noyau, toutes les commandes et les images de `IMAGE/` |
| `TOOLS/` | outils de l'hôte (Free Pascal) : `LPC` (compilateur), `MKIMAGE` (images de disque dur et de disquette), `UFSCHK` (vérification UFS1), `MKVOL` (volumes tar), `MKISO` (CD-ROM), `COFFINFO`, `MKPASSWD`, `UNIX.PAS` (unité de la libc) |
| `TESTS/` | tests sous QEMU et dans DEVENV (voir *Tests*) |
| `IMAGE/` | images produites par `BUILD.SH` (voir `IMAGE/LISEZMOI.TXT`) |

## Construction et essai

```bash
KERNEL16UNIX/BUILD.SH
```

```bash
KERNEL16UNIX/TESTS/RUNTESTS.SH
```

```bash
qemu-system-i386 -drive file=IMAGE/LINUX0-HD.IMG,format=raw,if=ide -boot c
qemu-system-i386 -drive file=IMAGE/LINUX0-144.IMG,format=raw,if=floppy -boot a
```

`BUILD.SH` demande `makefs` (NetBSD, `-t ffs -o version=1`) et s'exécute en
root (ou sous `fakeroot`) pour que les fichiers de l'UFS1 appartiennent à
root ; `W=…` choisit le répertoire de travail (par défaut
`/tmp/linux0-build`). Une commande du dépôt que LPC ne sait pas compiler
donne un avertissement et n'entre pas dans les images.

Prérequis sur l'hôte : Free Pascal (`fpc`) pour compiler LPC et les outils
de `TOOLS` (tous écrits en Pascal), `makefs`, et facultativement `nasm`
(`MBR.BIN` et `UFSBOOT.BIN` sont déjà fournis) et `qemu-system-i386` ;
les essais sous QEMU et DEVENV (`TESTS/*.PY`) demandent aussi `python3`.
Les outils hôtes n'emploient que l'unité DOS de Free Pascal (ou aucune) : les
modes, propriétaires et dates des fichiers de la distribution passent par une
liste produite par `find` (voir `TOOLS/MKVOL.PAS`).

Compilation du noyau seul : `LPC /K KERNEL.PAS` produit `KERNEL.SYS`, image
plate chargée à 1000:0000, copiée sous le nom `unix` à la racine du système
de fichiers d'amorce.

## Tests

`TESTS/RUNTESTS.SH` enchaîne, sous QEMU :

* `TPROC`, `TFS`, `TSWAP` lancés comme `/etc/init` d'une copie de la racine du
  disque dur : processus, signaux, exec, permissions ; UFS1 (création, gros
  fichier à blocs indirects, liens physiques, casse, `core`) ; huit
  processus de 65 Ko qui ne tiennent qu'avec le va-et-vient ; le système de
  fichiers est ensuite vérifié par `TOOLS/UFSCHK.PAS` ;
* `TFS` sur une disquette UFS1 de 2,88 Mo (racine sur toute la disquette),
  puis `UFSCHK --floppy` ;
* `SESSION.PY` : session complète par la console série (getty, login avec
  mot de passe, shell, tubes, arrière-plan, ^C, permissions, `passwd`,
  connexion de root) sur le disque dur, puis sur les disquettes de 1,44 Mo
  et 2,88 Mo (amorce sur UFS1, écritures, `reboot`, vérification de l'UFS1
  de la disquette) ;
* `INSTALL.PY` : installation de bout en bout depuis les disquettes (changées
  par le moniteur de QEMU) puis depuis le CD-ROM sur des disques vierges ;
  chaque disque installé est vérifié par `UFSCHK` (UFS1, MBR, amorce) et par
  `UFSCMP.PY`, un lecteur UFS1 indépendant écrit en Python qui compare chaque
  fichier (contenu, mode, propriétaire) à la racine de `BUILD.SH`, puis il
  démarre seul ; l'installateur est aussi essayé dans les cinq langues.

`TESTS/DEVENV.SH` amorce chaque image (disquettes, disque dur, CD-ROM) dans
l'émulateur de DEVENV et `TESTS/DEVENV_INSTALL.PY` y installe le système
(voir *Installation dans DEVENV*).

## Segments-unités

Le noyau ne peut pas utiliser d'unités (un seul fichier, une seule image) :
Linux Pascal ajoute les **segments-unités** :

```pascal
SegmentUnit KDisk;
Uses KTypes,KLib;              { segments-unites utilises }
SegmentInterface
 Procedure DiskInit;
SegmentImplementation
 Procedure DiskInit;
 Begin ... End;
SegmentEnd;
```

Chaque segment-unité a sa propre portée (des constantes ou variables de même
nom peuvent exister dans deux segments-unités), est accessible par
`KDisk.DiskInit` et reçoit son propre segment de code (32 Ko au plus : voir
*Limites connues*). Les données restent dans un segment DS commun de 64 Ko au
plus.

## Organisation (inspirée de UNIX V6, V7 et de xv6, MIT 6.828)

* **Processus** (`KSched`, `KProc`) : table `Procs` de 16 entrées, une pile
  noyau de 4 Ko par processus (réservée à l'amorce en haut de la mémoire
  s'il y a une zone de va-et-vient, sinon allouée à la création du
  processus et rendue par `wait`), commutation `KSwitch` (équivalent de
  `swtch`/`savu`/`retu`), `Sleep`/`Wakeup` sur des canaux, sommeils
  interruptibles par les signaux, réveils temporisés et alarmes.
* **Ordonnanceur** : préemptif, à priorités comme V7 : le temps processeur
  récent de chaque processus s'accumule et diminue de moitié chaque seconde,
  `nice` s'y ajoute, et le processus prêt de plus petite valeur est élu
  (tourniquet à égalité). L'horloge (IRQ 0, INT 08h, 18,2 Hz) retire le
  processeur à un processus en mode utilisateur après un quantum de 3 tops.
  Le noyau lui-même n'est pas préemptif (comme UNIX). Sans processus prêt,
  le noyau attend une interruption (`HLT`).
* **Mémoire** (`KMem`) : table des zones libres (*coremap*) en paragraphes,
  allocation au premier ajustement (`malloc` de UNIX V6). Les images 8086
  contiennent des adresses de segments absolues : un fils de `fork` ne peut
  pas être déplacé, il partage l'adresse d'exécution du père et les deux
  images sont **échangées** à chaque commutation (comme le *swapping* de
  UNIX V1). `vfork` évite la copie quand le fils appelle aussitôt `exec`.
  `break` agrandit l'image sur place (la libc s'en sert pour le tas).
* **Va-et-vient** (`KSwap`), comme UNIX V6/V7 : quand la mémoire manque
  (`exec`, `fork`, `break`), des images de processus sont écrites dans la
  zone de va-et-vient (partition de type 82h, 4 Mo sur l'image du disque
  dur), d'abord celles des processus endormis, les plus grosses d'abord ;
  un fils de `fork` sans mémoire libre va directement dans la zone. Une
  image 8086 n'est pas déplaçable, mais elle n'a pas à l'être : elle revient
  à **son adresse d'exécution**, et les processus qui occupent cette adresse
  sont à leur tour écrits dans la zone (ou, pour deux images issues du même
  `fork`, simplement échangées en mémoire). L'ordonnanceur ne donne le
  processeur qu'à un processus remis en mémoire ; la mémoire d'un père de
  `vfork` dont le fils s'exécute n'est écrite que pendant l'`exec` de ce fils
  (ses arguments sont déjà copiés : si l'`exec` échoue, le père est remis à
  son adresse avant le retour d'erreur), et les piles noyau,
  qui ne sont pas déplaçables non plus, sont réservées dès l'amorce. `ps`
  montre l'état de chaque image (L en mémoire, W dans la zone) et l'activité
  de la zone.
* **exec** : chargeur d'exécutables **COFF** (format natif de LINUX-0,
  produit par `LPC /X`) et, pour les programmes DOS, MZ. Comme sous V7,
  l'ancienne image est libérée avant le chargement de la nouvelle.
* **Système de fichiers** (`KUfs`, `KVfs`) : **UFS1** seul (FreeBSD :
  superbloc, groupes de cylindres, inodes de 128 octets avec propriétaire,
  groupe et mode, blocs de 4 Ko au moins et fragments de 512 octets au
  moins, indirections simple et double, liens physiques, cartes et résumés
  tenus à jour), `/dev` (tty, console, null, zero, disques et partitions),
  tubes ; montages par chemin ; cache de 64 secteurs à **écriture
  différée** : un secteur modifié est écrit quand son tampon est réutilisé,
  par `sync`, au démontage, avant `reboot` et toutes les 30 secondes (le
  rôle de `/etc/update` sous V7).
* **Console** (`KTty`) : écran BIOS, clavier BIOS et COM1, discipline de
  ligne de V7 (voir *Terminal*). Le tampon clavier du BIOS (15 touches) est
  vidé dans la file du terminal à chaque commutation et à chaque fin de
  quantum. L'écran est écrit sans la fonction télétype (curseur AH=02h,
  caractère AH=09h, défilement AH=06h), pour que la position du curseur de la
  zone BIOS, lue par l'unité CRT des programmes, soit juste partout.
* **Disques** (`KDisk`) : BIOS INT 13h, disquettes et disques durs,
  partitions du MBR.

### Racine, amorce et disquettes

La **racine** est toujours un UFS1. À l'amorce, la première partition de type
82h devient la zone de va-et-vient (elle peut se trouver sur un autre disque
que la racine, par exemple un disque dur pour une racine sur disquette). Puis :

* **disque dur** : la racine est la partition UFS (type A5h, A6h ou A9h) du
  disque d'amorce, celle que le MBR a lancée. Le MBR charge l'amorce
  `UFSBOOT` placée dans les 8 premiers Ko de la partition UFS (zone que le
  système de fichiers réserve à l'amorce, le superbloc étant à 8 Ko), comme
  `boot1`/`boot2` de FreeBSD : elle lit la géométrie du BIOS, le superbloc et
  l'inode 2, cherche `unix` dans la racine et charge ce fichier (blocs
  directs et indirection simple) à 1000:0000. Le noyau est donc `/unix`,
  comme sous UNIX V7 ;
* **disquette** : l'UFS1 occupe **toute la disquette** (unité 00h, sans MBR,
  début au secteur 0 ; makefs avec des blocs de 4 Ko et des fragments de
  512 octets) et le même `UFSBOOT` est son secteur d'amorce. Le BIOS charge le
  secteur 0 ; comme une disquette n'a pas d'entrée de partition, `UFSBOOT`
  n'utilise pas `DS:SI` (que le MBR renseigne pour un disque dur), prend 0
  pour le début du système de fichiers et lit la géométrie de la disquette
  par `INT 13h AH=08h`. Le secteur 0 charge les secteurs 1 à 15 puis cherche
  `unix` à la racine ;
* le noyau retrouve l'unité d'amorce en `0000:7C24` et le début du système
  de fichiers en `0000:7C1C` (champs de `UFSBOOT`), et monte la racine :
  `racine : /dev/hda1 (UFS1)` ou `racine : /dev/fd0 (UFS1)`.

`/dev` est toujours monté. Le disque dur d'amorce n'est pas nécessairement
`hda` (le CD-ROM en émulation de disque dur est `hda`, l'installation se fait
sur `hdb`).

## Format des exécutables : COFF

Les commandes de LINUX-0 (`/etc/init`, `/bin/*`) sont des fichiers COFF
(*Common Object File Format* de UNIX System V) produits par `LPC /X` :

| Partie | Contenu |
|---|---|
| en-tête de fichier (20 octets) | `f_magic` = 0153h (I286LMAGIC : Intel 286/8086, modèle large), `f_nscns`, `f_opthdr` = 28, `f_flags` = F_EXEC, F_LNNO, F_LSYMS, F_AR16WR |
| en-tête a.out (28 octets) | `magic` = 0107h (OMAGIC), `tsize`, `dsize`, `bsize`, `entry` (adresse linéaire du point d'entrée), `text_start`, `data_start` |
| sections (40 octets chacune) | `.text`, `.text1`, … (un segment de code 8086 chacune), `.data`, `.bss`, `.stack` (SS = chargement + `s_vaddr`/16, SP = `s_size`), `.heap` (tas initial; de taille nulle pour un programme `{$M pile,0,0}`) |
| relocalisations (10 octets) | `r_vaddr`, `r_symndx` = -1, `r_type` = R_SEG12 (011) : le mot à `r_vaddr` reçoit le paragraphe de chargement |

`s_vaddr` est l'adresse de la section par rapport au début de l'image ; le
noyau charge chaque section à `chargement + s_vaddr`, met à zéro `.bss` et la
pile, puis applique les relocalisations. `TOOLS/COFFINFO.PAS` affiche et
vérifie un exécutable COFF. La pile par défaut d'un programme LINUX-0 est de
8 Ko (`{$M}` peut en demander davantage); sans section `.heap`, le tas
initial est de 4 Ko et grandit ensuite par `break`. Comme une image 8086 ne
se déplace pas, `break` ne réussit que si la mémoire qui suit l'image est
libre : un programme qui alloue beaucoup demande son tas dès l'`exec` par
`{$M pile,tasmin,tasmax}` (en général sous `{$IFDEF LPC}`, comme `diff`,
`join`, `make` et `ldd`), et le noyau écrit alors d'autres processus dans la
zone de va-et-vient pour trouver la place.

### Démarrage d'un programme

Comme sous UNIX, `exec` dépose au sommet de la pile les chaînes des arguments
et de l'environnement, puis les tableaux `envp[]` et `argv[]` (pointeurs FAR
terminés par un pointeur nul), puis `argc`, sur lequel pointe SP au début du
programme. Le pointeur sur `argc` est aussi rangé au mot double PSP:4Ch, d'où
la libc tire `ArgCount`, `ArgStr`, `EnvStr` et les `ParamCount`/`ParamStr`
de Pascal (sans la limite DOS de 127 caractères). Un préfixe compatible PSP
de DOS (ligne de commande en 80h, environnement en 2Ch) est conservé pour la
bibliothèque d'exécution de Turbo Pascal et pour les programmes MZ.

Les gestionnaires de signaux reviennent à SIG_DFL (les signaux ignorés le
restent); les bits **set-uid** et **set-gid** du fichier donnent
l'utilisateur et le groupe effectifs; le droit d'exécution (x) est vérifié.

## Appels système (INT 80h)

AX = numéro, arguments dans BX, CX, DX, SI, DI ; DS:DX = premier pointeur,
ES:DI = second pointeur ; retour dans AX (DX:AX sur 32 bits, ou deux valeurs
AX et DX comme `r0`/`r1` du PDP-11), CF = 1 et AX = errno en cas d'erreur.
Les numéros 1 à 63 sont ceux de **UNIX V7**, les suivants ceux de **4.2BSD**,
et 200 à 206 sont propres à LINUX-0. Un numéro inconnu envoie SIGSYS.

| N° | Appel | N° | Appel | N° | Appel |
|---|---|---|---|---|---|
| 1 | exit | 2 | fork | 3 | read |
| 4 | write | 5 | open | 6 | close |
| 7 | wait | 8 | creat | 9 | link |
| 10 | unlink | 11 | exec | 12 | chdir |
| 13 | time | 14 | mknod | 15 | chmod |
| 16 | chown | 17 | break | 18 | stat |
| 19 | lseek | 20 | getpid | 21 | mount |
| 22 | umount | 23 | setuid | 24 | getuid |
| 25 | stime | 27 | alarm | 28 | fstat |
| 29 | pause | 30 | utime | 31 | stty |
| 32 | gtty | 33 | access | 34 | nice |
| 35 | ftime | 36 | sync | 37 | kill |
| 39 | getppid | 41 | dup | 42 | pipe |
| 43 | times | 46 | setgid | 47 | getgid |
| 48 | signal | 54 | ioctl | 55 | reboot |
| 57 | uname | 59 | exece | 60 | umask |
| 66 | vfork | 90 | dup2 | 128 | rename |
| 136 | mkdir | 137 | rmdir | 156 | getdirentries |
| 200 | procinfo (ps) | 201 | setdos (libc) | 202 | meminfo |
| 203 | mountinfo | 204 | sigtramp (libc) | 205 | getcwd |
| 206 | nap (ms) | | | | |

Détails conformes à V7 :

* **`wait`** rend le numéro du fils dans AX et son état dans DX : code de
  sortie × 256, ou numéro du signal qui l'a terminé (bit 80h : fichier
  `core` écrit). BX = numéro d'un fils précis ou -1, CX = WNOHANG
  (extension).
* **`errno`** : valeurs de V7 (EPERM = 1 … ERANGE = 34), puis de BSD
  (ENAMETOOLONG = 63, ENOTEMPTY = 66, ENOSYS = 78).
* **`open`** : O_RDONLY, O_WRONLY, O_RDWR, puis les drapeaux de 4.2BSD
  O_NDELAY = 4, O_APPEND = 8, O_CREAT = 200h, O_TRUNC = 400h, O_EXCL = 800h ;
  le mode de création est filtré par `umask`.
* **`stat`/`fstat`** : `struct stat` de V7 (30 octets : `st_dev`, `st_ino`
  sur 16 bits, `st_mode`, `st_nlink`, `st_uid`, `st_gid`, `st_rdev`,
  `st_size` sur 32 bits, `st_atime`, `st_mtime`, `st_ctime`).
* **Répertoires** : `read()` d'un répertoire rend des entrées de 16 octets
  (inode sur 16 bits, nom de 14 caractères), comme V7 ; `getdirentries`
  rend des `struct dirent` de 4.4BSD (noms longs de UFS).
* **exec** (11) : DS:DX nom, ES:DI `argv` ; **exece** (59) : et SI:CX `envp`
  (tableaux de pointeurs FAR terminés par un pointeur nul).
* **`signal`** : BX = signal, DX:CX = action (0 = SIG_DFL, 1 = SIG_IGN,
  sinon adresse FAR du gestionnaire) ; DX:AX = action précédente.
* **`getuid`/`getgid`** : réel dans AX, effectif dans DX.
* **`uname`** : cinq champs de 16 octets (chaînes Pascal) : `LINUX-0`,
  `linux0`, `KERNEL16UNIX`, la version du noyau, `i8086`.
* **`mount`** : `mount(special, répertoire, type)` ; seul UFS1 existe (type 0
  ou 2), tout autre type donne EINVAL. **`mountinfo`** (203) rend 1 pour un
  UFS1 et 2 pour `/dev`.

## Signaux

Les 15 signaux de V7 (SIGHUP = 1 … SIGTERM = 15). `signal(sig, fonction)`
installe un gestionnaire : au retour en mode utilisateur, le noyau prépare
une trame sur la pile du processus et la trampoline de la libc (enregistrée
par l'appel 204) appelle `fonction(sig)` en préservant l'état de la libc ;
comme sous V7, l'action redevient SIG_DFL avant l'appel. `alarm` envoie
SIGALRM, `pause` attend un signal, un appel système interrompu rend EINTR.
L'action par défaut termine le processus ; pour SIGQUIT, SIGILL, SIGTRAP,
SIGIOT, SIGEMT, SIGFPE, SIGBUS, SIGSEGV et SIGSYS, l'image mémoire est écrite
dans le fichier `core` du répertoire courant. ^C envoie SIGINT et ^\ SIGQUIT
à tous les processus du terminal sauf init ; le shell les fait ignorer aux
commandes lancées en arrière-plan. `kill(0, sig)` vise les processus de
l'utilisateur, `kill(-1, sig)` tous sauf init ; un utilisateur ordinaire ne
peut signaler que ses propres processus.

## Terminal

`ioctl` (ou `stty`/`gtty`) avec la structure `sgttyb` de V7
(TIOCGETP/TIOCSETP/TIOCSETN : vitesse, caractères d'effacement et
d'annulation, drapeaux RAW, CBREAK, ECHO, CRMOD) et `tchars`
(TIOCGETC/TIOCSETC : ^C, ^\, ^Q, ^S, ^D) ; FIONREAD (4.2BSD) donne le nombre
de caractères en attente. En mode RAW, une touche étendue du clavier PC
arrive sous la forme 0 puis le code de balayage.

## Utilisateurs et permissions

Chaque processus a un utilisateur et un groupe réels et effectifs. Les
fichiers UFS ont un propriétaire, un groupe et un mode : le noyau vérifie
lecture, écriture, exécution et recherche (propriétaire, groupe, autres) ;
le super-utilisateur (uid 0) passe outre, sauf pour exécuter un fichier sans
aucun bit x. `chmod` est réservé au propriétaire, `chown` et `mount` au
super-utilisateur ; `access` utilise l'utilisateur réel. Les fichiers de
`/dev` appartiennent à root.

`/etc/passwd` a le format de V7 (`nom:mot de passe:uid:gid:commentaire:
répertoire:interpréteur`). Les mots de passe ont 13 caractères (2 de sel,
11 de résultat, alphabet `./0-9A-Za-z`) ; le hachage, commun à `login`,
`passwd` et `TOOLS/MKPASSWD.PAS`, n'est pas le DES de `crypt(3)`. Les images
contiennent `root` (sans mot de passe) et `invite` (mot de passe `invite`,
uid 100, répertoire `/home/invite`).

## Session et shell

`init` lit `/etc/ttys` (format de V7 : `10console`) et lance `/etc/getty` sur
chaque terminal actif ; `getty` remet le terminal dans son état normal,
affiche `LINUX-0 KERNEL16UNIX (linux0)` (le résultat de `uname`) puis
`/etc/issue` et lit le nom, `login` vérifie le mot de passe, change de
répertoire, d'utilisateur et de groupe, affiche `/etc/motd` et lance
l'interpréteur de connexion (`-sh`), qui lit `/etc/profile` et
`$HOME/.profile`.

`/bin/sh` (`USR/SHELL.PAS`) suit le Bourne shell de V7 : recherche dans
`PATH`, guillemets `'…'` et `"…"`, `\`, variables (`$NOM`, `$?`, `$$`, `$!`,
`$#`, `$0`…`$9`, `$*`, `export`, `NOM=valeur commande`), motifs `* ? [a-z]`,
redirections `< > >> 2> 2>> 2>&1`, tubes `|`, `;`, `&`, `&&`, `||`,
commentaires, commandes internes `cd`, `exit`, `export`, `unset`, `set`,
`wait`, `exec`, `umask`, `read`, `shift`, `.`, `:`. Un fichier exécutable
qui n'est ni COFF ni MZ est lu par `sh`. `$?` vaut 128 + signal pour une
commande tuée par un signal. Il n'a pas `if`, `while`, `for` ni `case`.
L'interpréteur de style DOS du dépôt (SH.PAS) reste disponible sous le nom
`/bin/shdos`.

## Installation

`BUILD.SH` produit aussi une distribution, comme les bandes de UNIX V7. Tout
est en UFS1 :

* `LINUX0-INST1.IMG` : disquette amorçable (UFS1 sur toute la disquette) avec
  le noyau, `init`, `getty`, `login`, `sh`, l'installateur et quelques
  commandes, plus `/mdec/mbr` et `/mdec/ufsboot` (amorces du disque dur) ;
  `/etc/issue` invite à se connecter sous le nom `install`, dont
  l'interpréteur est `/bin/install` ;
* `LINUX0-INST2.IMG`, … : la racine complète en **volumes tar** (ustar)
  écrits directement sur la disquette, sans système de fichiers ; chaque
  volume commence par un fichier `VOLUME` (« LINUX-0 numéro total »), aucun
  fichier n'est coupé entre deux volumes (`TOOLS/MKVOL.PAS`). La
  distribution complète actuelle (186 commandes, sources dans `/usr/src`)
  demande **9** disquettes de données, soit **10 disquettes de 1,44 Mo** en
  tout ; `BUILD.SH` recalcule ce nombre ;
* `LINUX0-CD.ISO` : CD-ROM ISO 9660 amorçable (El Torito, `TOOLS/MKISO.PAS`)
  en **émulation de disque dur** : le BIOS présente l'image du CD comme le
  disque 80h et le noyau la lit par l'INT 13h, sans pilote de CD-ROM. Le disque
  émulé n'a qu'**une partition UFS1** (type A5h, sans va-et-vient), car les
  BIOS le dimensionnent d'après la première partition ; elle contient le
  noyau `/unix`, l'installateur et les volumes dans `/dist/volN.tar`.

`install` (`USR/INSTALL.PAS`), qui n'a plus qu'un seul type d'installation,
**UFS seul** :

1. propose les disques durs, sauf celui d'où le système a démarré (le CD
   émulé est `hda`, la cible est alors `hdb`), puis demande la **langue du
   système installé** (`FR`, `EN`, `GR`, `SP` ou `IT` ; par défaut celle de
   l'installateur) et confirme ; ce qui serait monté depuis le disque cible
   est démonté ;
2. écrit la table des partitions (code de `/mdec/mbr`), alignées sur les
   cylindres du BIOS : partition 1 UFS1 active (type A5h) et partition 2 de
   va-et-vient de 4 Mo (type 82h) ; le noyau relit la table (`ioctl
   DIOCRESCAN`) et crée `/dev/hdX1`, … ;
3. crée le système UFS1 comme `newfs` : superbloc et copies, groupes de
   cylindres de 32 Mo au plus (cartes des inodes, des fragments et des
   grappes, résumés), tables d'inodes, racine (inode 2), amorce UFS
   (`/mdec/ufsboot` dans les 8 premiers Ko de la partition) ;
4. monte la racine sur `/mnt`, copie le noyau (`/unix`), puis extrait les
   volumes : sur `/dev/fd0`, lu brut, en vidant le cache du lecteur à chaque
   disquette (`ioctl DIOCINVAL`), ou depuis `/dist/volN.tar` ; modes (bit
   set-uid de `passwd` compris), propriétaires et dates sont appliqués. Une
   disquette qui n'est pas la bonne est refusée et redemandée ;
5. si la langue choisie n'est pas le français, écrit
   `LANGUAGE=XX; export LANGUAGE` dans `/etc/profile` du disque installé ;
6. démonte, puis propose de redémarrer.

L'installateur parle la langue de la variable d'environnement `LANGUAGE`
(français par défaut, `EN`, `GR`, `SP`, `IT`) : par exemple, en root,
`LANGUAGE=SP /bin/install`. Le noyau, lui, garde ses messages en français.

`ioctl` des disques (LINUX-0) : `DIOCGINFO` (taille, géométrie du BIOS,
début, type de partition), `DIOCRESCAN` (relecture du MBR, aucune
partition du disque ne doit être montée), `DIOCINVAL` (tampons écrits puis
oubliés : changement de disquette).

### Installation dans DEVENV

Dans DEVENV, lancé en grand écran (`devenv -maxscreen`, pour voir à la fois
l'onglet émulateur et l'Invite de commandes), on procède comme avec
MSDOS-0 :

```
IMGMOUNT A: LINUX0-INST1.IMG
IMGMOUNT C: disque.img
BOOT A:
```

puis, dans l'onglet « Émulateur 8086 », connexion `install`, et à chaque
« Inserez la disquette N » (dans l'Invite de commandes) :

```
IMGMOUNT -u A
IMGMOUNT A: LINUX0-INST2.IMG
```

avant d'appuyer sur Entrée dans l'émulateur. À la fin : `IMGMOUNT -u A`,
puis `BOOT C:` démarre le disque installé. Depuis le CD-ROM :
`BOOT /CDROM:LINUX0-CD.ISO` puis aussitôt `IMGMOUNT D: disque.img` (DEVENV
n'amorce un CD que si aucun disque n'est monté ; le disque cible doit être
monté avant que le noyau ne recense les disques). Sous Linux, DEVENV veut des
chemins absolus dans `IMGMOUNT`.

Le banc d'essai sans interface de DEVENV (`/KERNELTEST`, `/KTBOOTIMG`,
`/KTHD`, `/KTSCRIPT`, voir `DEV-COOLS/DOC/KERNELTEST.txt`) sert aux essais
automatiques : `TESTS/DEVENV.SH` amorce les disquettes de 1,44 Mo et 2,88 Mo,
la disquette d'installation, le disque dur et le CD-ROM, se connecte en root
et tape quelques commandes ; `TESTS/DEVENV_INSTALL.PY` installe le système
(`DEVENV=…/DEVENV python3 TESTS/DEVENV_INSTALL.PY disquettes` ou `cd`),
en espagnol depuis les disquettes et en anglais depuis le CD, puis amorce le
disque installé. Ce banc d'essai est limité à 2 147 483 647 instructions : le
script n'installe donc que le système de base (une disquette de données), pas
les 9 disquettes complètes (installées sous QEMU). Deux particularités de
DEVENV : le disque `/KTHD` a une géométrie de 255 têtes et 63 secteurs, mais un
disque dur donné à `/KTBOOTIMG` en a 2 et 18, si bien que le script réécrit les
coordonnées CHS du MBR du disque installé avant de l'amorcer.

## Carte mémoire

| Adresses | Contenu |
|---|---|
| 00000-003FF | vecteurs d'interruption |
| 00400-004FF | données du BIOS |
| 00500-07BFF | pile du processus 0 (amorce) |
| 07C00-07DFF | secteur 0 de l'amorce UFS (unité d'amorce en 7C24, début du système de fichiers en 7C1C, relus par le noyau) |
| 08000-0FFFF | cache disque (64 tampons de 512 octets) |
| 10000-...   | noyau : code (segments), puis données |
| ...-9FFFF   | images des processus (en bas) et piles noyau (en haut), gérées par la coremap ; les images en trop sont dans la zone de va-et-vient |

Le noyau occupe environ 187 Ko (160 Ko de code, 30 Ko de données) : il reste
environ 388 Ko de mémoire libre pour les processus sur un PC de 640 Ko.

## Programmes LINUX-0

`LPC /X PROGRAMME.PAS` compile un programme pour LINUX-0. La bibliothèque
d'exécution de Turbo Pascal et les unités DOS, CRT et PRINTER n'appellent
plus MS-DOS : le vecteur INT 21h est propre à chaque processus et pointe sur
la couche « libc » de l'unité UNIX (`TOOLS/UNIX.PAS`), qui traduit chaque
service (fichiers, répertoires, FindFirst, Exec, mémoire, date, clavier...)
en appels système LINUX-0, dans le processus lui-même. Les commandes du dépôt
(cat, ls, grep, vi, ...) se compilent ainsi sans modification. L'unité UNIX
offre aussi l'interface UNIX directe : `SysOpen`, `SysRead`, `Fork`,
`VFork`, `Execve`, `ArgExec`, `WaitPid`, `SysSignal`, `SysAlarm`, `GTty`,
`SysStat`, `SetUid`, ...

## Limites connues

* Pas de protection mémoire (8086) : un programme peut écraser le noyau.
* L'installation n'utilise que les 1024 premiers cylindres du BIOS (adressage
  CHS de l'INT 13h, 504 Mo au plus) ; le disque doit faire au moins 16 Mo.
* Le va-et-vient demande une partition de type 82h : les disquettes n'en
  ont pas (une racine sur disquette peut utiliser celle d'un disque dur), et
  le nombre de processus simultanés y est limité par les 640 Ko (environ
  390 Ko pour les processus ; une commande pèse de 42 à 100 Ko, dont au moins
  35 pour le runtime et la libc). Les processus qui se partagent la même
  adresse d'exécution (plusieurs `fork` du même programme) font des
  allers-retours sur le disque à chaque commutation.
* Les disquettes de 1,44 Mo et de 2,88 Mo ne reçoivent que les commandes
  essentielles et les plus petites (une commande pèse plus de 42 Ko) ; toutes
  les commandes sont sur le disque dur et le CD-ROM.
* Les commandes du dépôt restent des programmes de style DOS sous le capot
  (options `/?`, jokers `*.*`, chemins `C:\` acceptés, NUL/CON/PRN) ; `ls`
  ne prend qu'un argument, `wc` exige une option, `grep` affiche le nom du
  fichier à la manière de FIND.
* Les relocalisations de segments des exécutables sont inhérentes au code
  segmenté du 8086 (absentes des binaires PDP-11 de V7).
* Une recherche de nom sur UFS ne se fait sans tenir compte de la casse que
  pour un programme DOS (exécutable MZ).
* Pas de liens symboliques (absents de V7), pas de fichiers spéciaux créés
  par `mknod` (`/dev` est fourni par le noyau), date d'accès non tenue à
  jour, pas de fuseau horaire (l'horloge du PC est en UTC).
* Fichiers de 16 Mo au plus sur UFS (indirection double) ; l'amorce UFS
  charge un noyau de 12 blocs directs et d'un bloc d'indirection simple.
* QEMU 8.2 exécute mal un saut proche 16 bits qui fait le tour des 64 Ko
  d'un segment non aligné sur 4 Ko ; pour les cibles LINUX-0, LPC limite donc
  les segments de code à 32 Ko (aucun saut ne fait le tour du segment).
