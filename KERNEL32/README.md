# KERNEL32 : noyau LINUX-0 32 bits (i386)

`KERNEL32` est un noyau Linux 32 bits (80386, mode protege) ecrit en Pascal, en
**un seul fichier** (`KERNEL32.PAS`, environ 360 Ko), compile par le compilateur
**LPC** avec la cible `-3K` (`lpc -3K KERNEL32.PAS` produit l'ELF32 `KERNEL32`).
Il execute des programmes Linux i386 (ELF32 statiques, ABI `INT 80h`, numeros
d'appels systeme EXACTS de Linux, resultats `-errno`). Nom affiche :
`LINUX-0 KERNEL32` ; `uname` : sysname `LINUX-0`, nodename `linux0`, release
`KERNEL32`, version `0.1`, machine `i386`.

Etat : **phase 1 complete** (coeur, memoire, processus, signaux, appels
systeme, VFS avec tmpfs/devfs/tubes, terminaux, disque IDE, init et banc
d'essai) et un debut de phase 2 (`/proc`). L'agent suivant ajoute ext2 sur la
couche bloc, puis les programmes utilisateur (voir "Plan" plus bas).

## Construction et essai

    lpc -3K KERNEL32.PAS                       # produit KERNEL32 (ELF32 multiboot)
    qemu-system-i386 -kernel KERNEL32 -serial stdio -display none -m 64 \
        -append "console=ttyS0"                # amorce multiboot directe
    TESTS/K/RUNK.SH -d disque.img              # compile, embarque, lance, verifie
    BUILD.SH                                   # image disque complete (voir BOOT/)

Amorce par disque : le chargeur de `BOOT/` (MBR + stage2 + ext2) charge
`/boot/linux0` (cet ELF) a l'adresse physique de ses en-tetes (`p_paddr`) et
saute au point d'entree physique avec le protocole multiboot (EAX=2BADB002h,
EBX = structure multiboot, A20 actif, pagination coupee). Essai : le noyau
copie par `TOOLS/MKIMAGE.SH -k KERNEL32` demarre depuis le disque ext2 et
affiche la meme suite de tests.

Parametres de la ligne de commande : `root=` (memorise), `init=` (programme
lance a la place de `/sbin/init`), `console=ttyS0` (la console `/dev/console`
est le port serie ; sinon l'ecran VGA), `mem=NNM` (limite la memoire), `keymap=fr`
(clavier AZERTY ; defaut `us`), `quiet` (pas de messages du noyau a l'ecran
apres le demarrage), `debug` (journal de chaque appel systeme et faute de page).

## Parties du noyau (`KERNEL32.PAS`)

| Partie | Contenu |
|---|---|
| 1 | en-tete multiboot, `KStart` (amorce physique : tables de pages d'amorce, pagination, saut en C0100000h), constantes |
| 2 | utilitaires : copies memoire, chaines, nombres, errno Linux, `Call0..Call6` (appel d'une adresse de procedure) |
| 3 | console VGA texte (4 consoles virtuelles, sequences ANSI/CSI, UTF-8 vers CP437), port serie COM1, journal du noyau en tampon circulaire (dmesg, appel `syslog`) |
| 4 | GDT/TSS/IDT, gabarits d'interruption generes en octets machine, `KTrap`, PIC 8259, exceptions (ecran avec registres et trace des appels) |
| 5 | minuterie PIT a 100 Hz, horloge CMOS, heure Unix |
| 6 | structure multiboot, ligne de commande, carte memoire E820 |
| 7 | pages physiques (allocateur buddy 4 Ko a 4 Mo), `kmalloc/kfree` (classes de 32 a 2048 octets puis pages) |
| 8 | repertoires et tables de pages, VMA, fautes de page (a la demande, croissance de la pile, copie sur ecriture), `brk`, `mmap`, `munmap`, `mprotect`, `fork` (copie sur ecriture) |
| 9 | table des taches, ordonnanceur preemptif a priorites (type Linux 2.4), sommeil/reveil, `clone/fork/vfork`, `exit`, `wait4`, zombies, orphelins reparentes a init |
| 10 | signaux POSIX (cadres `sigcontext` et RT compatibles Linux, `sigreturn`), `alarm`, `setitimer` |
| 11 | couche bloc : cache de tampons (ecriture differee par le fil `bdflush`, `sync`), ramdisk, disque IDE/ATA PIO (LBA28, 4 lecteurs, partitions MBR et logiques) |
| 12 | VFS : superblocs, inodes, dentries (cache de noms), fichiers ouverts, chemins (`.`, `..`, liens symboliques, 8 niveaux, montages), permissions Unix, `mount/umount/chroot` |
| 13 | tmpfs/ramfs (racine), devfs (tmpfs monte en `/dev`), tubes et FIFO, `/dev/null,zero,full,random,urandom`, fichiers de peripheriques blocs ; `/proc` (phase 2) |
| 14 | terminaux : discipline de ligne N_TTY complete, consoles `tty1..tty4` (Alt+F1..F4), `ttyS0`, clavier PS/2 (QWERTY US ou AZERTY) |
| 15 | chargeur ELF (`execve` : ET_EXEC statique, `#!`, pile `argc/argv/envp/auxv`) |
| 16 | appels systeme (liste dans l'en-tete de la partie) |
| 17 | programmes embarques (genere), `init`, programme principal |

## Carte memoire

    physique  00000000-000FFFFF  BIOS, VGA (mappe mais non gere)
              00100000-...       image du noyau (code, donnees, tableaux), puis
                                 tables des pages, drapeaux des pages
              ...                pages libres (buddy)
    virtuelle 00000000-BFFFFFFF  utilisateur : ELF en 08048000h, tas apres
                                 le dernier segment, mmap a partir de 40000000h,
                                 pile en haut (BFFFFFFFh, 8 Mo, croissance auto)
              C0000000-FFFFFFFF  noyau : toute la RAM (au plus 896 Mo) en
                                 C0000000h + adresse physique ; image en C0100000h

L'amorce mappe 16 Mo en 0 et en C0000000h, puis le noyau construit le mapping
direct complet et abandonne l'identite. Les segments utilisateur sont plats
(base 0, limite 4 Go, DPL 3) ; le noyau est protege par le bit U/S des pages.
Piles du noyau : 16 Ko par tache.

## Regles de fonctionnement

* **Noyau non preemptif** : les interruptions sont masquees (IF=0) pendant tout
  le code du noyau, sauf dans la boucle d'inactivite (`STI; HLT`). Un processus
  ne perd le processeur que par `Schedule` (sommeil) ou au retour en mode
  utilisateur quand sa tranche est finie. Les gestionnaires d'IRQ font des
  operations courtes (tampons, reveils) ; l'allocation de chaines temporaires
  y est donc sans danger (jamais d'interruption pendant du code du noyau).
* Tables d'operations (VFS, peripheriques) : tableaux d'adresses de procedures
  (indices `IoXxx`, `FoXxx`, `SoXxx`) appeles par `CallN`.
* Reveil sur "canaux" : un entier (adresse d'un objet) ; `SleepOn`/`WakeUp`.
* Memoire utilisateur : les appels systeme verifient et rendent presentes les
  pages (`EnsureUser`) puis copient directement.

## ABI : appels systeme

Voir l'en-tete de la partie 16 de `KERNEL32.PAS` (numeros Linux i386 :
exit 1, fork 2, read 3, write 4, open 5, ... getrandom 355). Non implementes :
`-ENOSYS`. `socketcall` : `-ENOSYS`. Ecarts connus avec Linux :

* mmap de fichier : toujours prive (copie des pages a la demande) ; `MAP_SHARED`
  d'un fichier ne repercute pas les ecritures (pas de cache de pages) ;
* `mremap` : reduction ou agrandissement sur place seulement ;
* threads : `clone` partage `CLONE_VM/FILES/FS/SIGHAND` et `CLONE_THREAD`
  (`gettid` distinct de `getpid`) ; pas de fils multiples dans `execve`, signaux
  de groupe simplifies ; `futex` : attente/reveil seulement ;
* `uname` : release `KERNEL32` (une glibc statique qui verifie la version du
  noyau refuserait de demarrer ; musl et les programmes LPC -3X : aucun probleme) ;
* chemins limites a 255 caracteres ; 256 descripteurs, 256 taches ;
* fichiers : tailles sur 32 bits (2 Go), `llseek` hors 32 bits : `-EINVAL` ;
* limites appliquees : `RLIMIT_NOFILE`, `STACK`, `DATA` (tas) ; les autres sont
  seulement memorisees.

## Systemes de fichiers et peripheriques

* `/` est un tmpfs (ramfs). Le noyau cree `/dev` (tmpfs "devtmpfs" avec `null`,
  `zero`, `full`, `random`, `urandom`, `console`, `tty`, `tty0..4`, `ttyS0`,
  `ram0`, `hda..hdd` et leurs partitions detectees) et `/proc`.
* `mount(2)` : types `tmpfs`, `ramfs`, `devtmpfs`, `proc` (ajouter ext2 :
  `RegisterFs('ext2', @Ext2MountFn)` et un `SoReadInode`).
* `/proc` : `version`, `meminfo`, `uptime`, `mounts`, `cpuinfo`, `stat`,
  `loadavg`, `filesystems`, `cmdline`, `self`, `N/stat`, `N/status`,
  `N/cmdline`, `N/maps`.
* Terminaux : `termios` complet (canonique, brut, `VMIN/VTIME`, `ISIG`, `ICRNL`,
  `ONLCR`, `ECHOE/K/CTL`), `TCGETS/TCSETS*`, `TIOCGWINSZ/SWINSZ`, `TIOCGPGRP/SPGRP`,
  `TIOCSCTTY`, `FIONREAD`, controle de travaux (`SIGTTIN`, `SIGTTOU`, `SIGTSTP`,
  `SIGHUP` a la fin du chef de session).

## Tests (`TESTS/K/`)

Programmes C (`gcc -m32 -static -nostdlib -ffreestanding`, bibliotheque
`ku.h` : appels systeme `INT 80h`) : `hello`, `forkwait`, `pipetest`, `sigtest`,
`mmaptest`, `dirtest`, `ttytest`, `schedtest`, `blktest`, `misctest`, `proctest`,
`stress` et `init` (lance la suite puis un petit interpreteur de commandes sur
la console : `ls cat echo cd pwd mkdir rm halt` ou un chemin de programme).
`MKEMBED.PY` encode les ELF en base64 dans `KERNEL32.PAS` (entre les marqueurs
`{ BEGIN-EMBED }` et `{ END-EMBED }`) ; le noyau les ecrit dans le tmpfs racine
au demarrage (`/sbin/init`, `/bin/...`). Resultat attendu : 150 lignes
`KTEST: ... OK` et `KTEST: DONE progs=12 fail=0`. `MKDISK.PY` fabrique le disque
IDE de test. Si `/sbin/init` d'une image installee existe plus tard, c'est
lui qui doit etre prefere : voir `init=` et le plan ci-dessous.

## Plan pour la suite

1. **ext2** (lecture puis ecriture) : fonction de montage `Ext2MountFn`
   (lire le superbloc par `BRead(dev, 1, 1024)`), `SoReadInode`, operations
   `IoLookup/Create/Mkdir/Unlink/...`, `FoRead/FoWrite/FoReaddir` sur les blocs
   (indirections), puis monter la racine reelle (`root=/dev/hda1`) :
   monter l'ext2 sur `/mnt`, `chroot`/pivot de `Cur^.Fs^.Root` de `init`,
   remonter `/dev` et `/proc`. Le cache de dentries et d'inodes (`IGet`) est pret.
2. Programmes utilisateur LPC -3X (`/sbin/init`, `sh`, `getty`, `login`...) :
   retirer les programmes embarques de test de l'image finale.
3. `/sys`, pseudo-terminaux (`/dev/ptmx`, `/dev/pts`), sockets AF_UNIX puis
   AF_INET (loopback), SMP, modules : non faits.
4. Ameliorations : cache de pages et `MAP_SHARED` de fichiers, `fdatasync`
   reel, `RLIMIT_AS/CPU/FSIZE`, quotas de processus, `wait` en cas de
   `SIGCHLD` ignore (auto-reap), `/proc/N/fd`, `/proc/sys`.
