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
d'essai) et **phase 2 (agent D)** : ext2 lecture/ecriture complet, racine reelle
`root=/dev/hdaN`, montages (remontage, bind, move, pivot_root, umount2),
executables ELF dynamiques (PT_INTERP, PIE), SSE/FXSR, `/sys`, pseudo-terminaux
(`/dev/ptmx`, `/dev/pts`). Voir "Phase 2" plus bas.

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

Parties ajoutees en phase 2 (placees physiquement avant la partie 14) :

| Partie | Contenu |
|---|---|
| 18 | ext2 : superbloc, descripteurs de groupes epingles dans le cache de tampons, bitmaps, allocation de blocs et d'inodes avec regroupement, inodes de 128/256 octets, revisions 0 et 1, blocs de 1/2/4 Ko, `sparse_super`, `filetype`, indirections simple/double/triple, repertoires lineaires (ajout, fusion a la suppression, agrandissement), liens durs, liens symboliques rapides et lents, `mknod` (tty, bloc, fifo, socket), `rename` (entre repertoires, remplacement), troncature, `chmod/chown/utimes`, `statfs`, `s_state` propre/sale, remontage. ext3 (journal propre) monte comme ext2 ; journal a rejouer ou sommes de controle : lecture seule ; ext4 (extents, 64bit...) : refuse |
| ... | `/sys` (`PopulateSys`), pseudo-terminaux (maitre `PtmxXxx`, esclaves `Ttys[PtyBase+N]`, devpts = tmpfs a la partie 14), FPU/SSE (`FpuDetect`, FXSAVE), bind mounts / `pivot_root` / `MS_MOVE` (partie 12), racine reelle `TryRealRoot` (partie 17) |

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
* `uname` : release `KERNEL32` (la glibc de l'hote, statique ou dynamique,
  demarre quand meme ; `uname26` sur la ligne de commande donne `2.6.32` si un
  programme verifie la version du noyau) ;
* chemins limites a 255 caracteres ; 256 descripteurs, 256 taches ;
* fichiers : tailles sur 32 bits (2 Go), `llseek` hors 32 bits : `-EINVAL` ;
* limites appliquees : `RLIMIT_NOFILE`, `STACK`, `DATA` (tas) ; les autres sont
  seulement memorisees.

## Systemes de fichiers et peripheriques

* `/` est un tmpfs (ramfs) sauf si `root=` monte un ext2 (voir Phase 2). Le noyau
  cree `/dev` (tmpfs "devtmpfs" avec `null`, `zero`, `full`, `random`,
  `urandom`, `console`, `tty`, `ptmx`, `tty0..4`, `ttyS0`, `ram0`, `hda..hdd`
  et leurs partitions detectees), `/dev/pts`, `/proc` et `/sys`.
* `mount(2)` : types `ext2`, `ext3`, `tmpfs`, `ramfs`, `devtmpfs`, `proc`,
  `sysfs`, `devpts`.
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
`KTEST: ... OK` et `KTEST: DONE progs=14 fail=0` (apres ajout de `ext2test` et
`ptytest`). `MKDISK.PY` fabrique le disque
IDE de test. Si `/sbin/init` d'une image installee existe plus tard, c'est
lui qui doit etre prefere : voir `init=` et le plan ci-dessous.

## Phase 2 (agent D) : ce qui a ete ajoute

### Racine reelle et montages

* `root=/dev/hdaN` (ext2) : `TryRealRoot` monte l'ext2 comme racine (la racine
  tmpfs en memoire est abandonnee et liberee), cree si besoin `/dev`, `/proc`,
  `/sys` (meme sur une racine `ro`), y remonte devtmpfs, proc, sysfs et devpts,
  puis `init=` ou `/sbin/init` (repli `/etc/init`, `/bin/init`, `/bin/sh`) est lu
  sur le disque. `ro` est le defaut (comme Linux), `rw` sur la ligne de commande
  monte en lecture-ecriture. Si `root=` est absent, illisible ou sans programme
  init, le noyau garde la racine tmpfs et installe les programmes embarques.
* `mount(2)` : `ext2`, `ext3`, `tmpfs`, `ramfs`, `devtmpfs`, `proc`, `sysfs`,
  `devpts` ; `MS_RDONLY`, `MS_REMOUNT` (ro <-> rw, `s_state` propre/sale),
  `MS_BIND` (racine du bind mount = dentry "clone" ; pas de `MS_REC`),
  `MS_MOVE` ; `umount2` (`MNT_DETACH` decroche meme un montage occupe) ;
  `pivot_root` (217) ; `chroot`. Plusieurs disques (`/dev/hdb1`...). Un meme
  peripherique ne se monte qu'une fois (`EBUSY`).
* `reboot` (restart, halt, poweroff) et Ctrl-Alt-Suppr : `VfsShutdown` ecrit tout
  puis remonte les ext2 en lecture seule (systeme marque propre).
* `statfs/fstatfs/statfs64` renvoient les vraies valeurs (`SoStatfs`), `fsync`
  et `sync`.

### Compatibilite Linux

* Executables ELF **dynamiques** : `PT_INTERP`, `ET_DYN` (PIE, charge en
  08048000h), interpreteur charge dans la zone mmap, `AT_BASE`. Essai :
  `ld-linux.so.2` et `libc.so.6` i386 de la glibc de l'hote sur disque.
* SSE/FXSR : `CR4.OSFXSR`, `FXSAVE/FXRSTOR` (etat de 512 octets par tache,
  cadres de signaux avec l'image FXSR a +112 de `fpstate`).
* `uname` : release `KERNEL32` par defaut ; `uname26` (ligne de commande)
  donne `2.6.32`, `uname_release=X.Y.Z` une valeur au choix (`/proc/version`,
  `/sys/kernel/osrelease` suivent).
* Verifie avec des binaires reels : busybox 1.36 i386 statique (ash, ls, grep,
  sed, awk, tar, gzip, find, mount, ps, vi hors tty...), programme glibc statique
  (`gcc -m32 -static` : pthreads, TLS, fork, mmap, signaux, popen) et dynamique.
* `/sys` : `block/hdX[/hdXN]` (`dev`, `size`, `start`, `partition`),
  `class/{block,tty,mem}`, `kernel/{ostype,osrelease,hostname,version}`,
  `devices/system/cpu`, `power/state` (arbre statique cree au demarrage).
* Pseudo-terminaux Unix 98 : `/dev/ptmx` (5:2), `/dev/pts/N` (136:N, devpts :
  tmpfs cree par le noyau, noeud supprime a la fermeture), `TIOCGPTN`,
  `TIOCSPTLCK`, `TIOCGPTLCK`, `TIOCSWINSZ`, `poll`, hangup de l'esclave a la
  fermeture du maitre, 16 pty au plus.

### ext2 : limites

Fichiers de 2 Go au plus ; pas d'extents, de journal (rejoue), d'attributs
etendus ni d'ACL (le bloc d'EA d'un fichier supprime est libere), de `meta_bg`,
`64bit`, ni de repertoires indexes (le drapeau `INDEX_FL` est efface a toute
modification) ; les sommes de controle (`gdt_csum`, `metadata_csum`) imposent la
lecture seule ; blocs de 8 Ko et plus refuses ; pas de quotas ; les copies de
secours du superbloc et des descripteurs ne sont pas mises a jour (comme le
noyau Linux). Les acces au peripherique brut `/dev/hdaN` (tampons de 1 Ko) ne
sont pas coherents avec un ext2 de blocs de 2 ou 4 Ko monte sur le meme disque.

### Tests (phase 2)

* `TESTS/K/RUNEXT2.SH [-b bloc] [-i inode] [-m Mo]` : fabrique un disque
  (`MKEXT2.SH`), lance `ext2test` (96 verifications : lecture, ecriture,
  repertoires de 300 entrees, renommages, liens, fichiers creux jusqu'a
  l'indirection triple, speciaux, permissions, montage en lecture seule, remontage)
  puis `e2fsck -fn` : doit etre propre (essaye en 1K/2K/4K, inodes 128/256).
* `ptytest` (embarque, `RUNK.SH`) : pseudo-terminaux.
* `RUNK.SH` reste le banc d'essai general (150+ verifications).
* Le noyau lance avec `k32power` sur la ligne de commande fait un poweroff
  propre apres la suite (utilise par `RUNEXT2.SH`).

### Plan restant

Sockets AF_UNIX et AF_INET (bouclage), cache de pages et `MAP_SHARED` de
fichiers, swap, `RLIMIT_AS/CPU/FSIZE`, epoll/eventfd/timerfd/inotify, pilote
reseau (NE2000/RTL8139), souris PS/2, framebuffer VESA, disquette, CD-ROM
(ATAPI + iso9660), FAT/vfat, noyau preemptible, SMP, modules.
