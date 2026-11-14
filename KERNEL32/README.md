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
| 19 | sockets : `AF_UNIX` (stream, dgram, socketpair, noms dans le VFS ou abstraits, `SCM_RIGHTS`), `AF_INET` en bouclage et reel (appels directs 359-373 et `socketcall`), `bind/listen/accept/connect/send/recv/sendmsg/recvmsg/shutdown/getsockopt...`, `poll` |
| 20 | cache de pages des mappages partages (`MAP_SHARED` de fichiers : pages partagees entre processus, ecritures recopiees dans le fichier, `msync`) |
| 21 | `epoll` (LT, ET, ONESHOT), `eventfd`, `timerfd`, `inotify` (create, open, modify, close, move, delete, attrib) |
| 22 | reseau : pilote RTL8139 (PCI, DMA, IRQ), ARP, IPv4, ICMP (echo), UDP, TCP reel (poignee de mains, retransmission, fenetre, MSS 1400, fermeture), `SIOCGIFADDR/SIOCSIFADDR/SIOCGIFFLAGS...`, `/proc/net/dev` et `route`, `ip=A.B.C.D` sur la ligne de commande |
| 23 | iso9660 (CD-ROM, lecture seule, Rock Ridge : `NM`, `PX`, `SL`) sur ATAPI (commande PACKET en PIO, partie 11) |
| 26 | swap : `swapon`/`swapoff` (87/115) sur un peripherique `mkswap` (SWAPSPACE2 v1, 128 Mo au plus) ou `swap=/dev/hdXN` au demarrage ; `SwapReclaim` (appele par `AllocPages` sous 96 pages libres) ecrit sur disque les pages anonymes privees a une seule reference (seconde chance par bit "accede"), PTE non present portant la case (bit 9), page-in dans la faute de page (aussi en mode noyau), cases comptees pour `fork`, `/proc/meminfo` SwapTotal/SwapFree |
| 25 | framebuffer Bochs/QEMU VGA : `fb=LxH` sur la ligne de commande programme le mode 32 bits (registres VBE 1CEh/1CFh), memoire video (BAR 0 PCI) mappee en F8000000h, `/dev/fb0` (29:0) : read, write, lseek, `FBIOGET_FSCREENINFO/VSCREENINFO`, `mmap` partage (VMA `VmPhys`, PTE hors comptage) |
| 24 | FAT12/16/32 et vfat (noms longs UTF-8/UCS-2, noms courts `~N`, indicateurs de casse NT), lecture/ecriture, repertoires qui grandissent, renommage, troncature, attribut lecture seule, dates, `statfs`, FSInfo FAT32 ; options `ro`, `rw`, `umask=`, `uid=`, `gid=` ; types `vfat`, `msdos`, `fat` |
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
* `mount(2)` : types `ext2`, `ext3`, `vfat`, `msdos`, `fat`, `iso9660`, `tmpfs`,
  `ramfs`, `devtmpfs`, `proc`, `sysfs`, `devpts`.
* `/proc` : `version`, `meminfo`, `uptime`, `mounts`, `cpuinfo`, `stat`,
  `loadavg`, `filesystems`, `cmdline`, `self`, `net/dev`, `net/route`, `N/stat`,
  `N/status`, `N/cmdline`, `N/maps`.
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

### Peripheriques et fonctions ajoutes ensuite (phase 2)

* **Sockets** (partie 19) : `AF_UNIX` et `AF_INET` ; `RUNK.SH` (`socktest`) les
  verifie en bouclage (flux, datagrammes, `socketpair`, `SCM_RIGHTS`, `poll`,
  `getsockname`, `SO_REUSEADDR`...).
* **Reseau reel** (partie 22) : carte RTL8139 de QEMU (reseau utilisateur
  10.0.2.15 / passerelle 10.0.2.2) ; `ping`, `wget`, `nc` de busybox, TCP
  500 Ko dans les deux sens, serveur entrant par `hostfwd` : `RUNNET.SH`.
  Limites : pas de DHCP ni de DNS dans le noyau (adresse par `ip=` ou
  `SIOCSIFADDR`), pas de fragmentation IP, TCP sans SACK ni echelle de fenetre.
* **Cache de pages / `MAP_SHARED`** (partie 20) : `shmtest`.
* **Limites de ressources** : `RLIMIT_AS` (`mmap`, `brk`), `RLIMIT_CPU`
  (`SIGXCPU`/`SIGKILL`), `RLIMIT_FSIZE` (`SIGXFSZ`) : `limtest`.
* **Evenements** (partie 21) : `evttest`.
* **Noeuds** : `/dev/mem`, `/dev/kmem`, `/dev/port`, `/dev/kmsg`, `/dev/rtc`
  (`RTC_RD_TIME`, `RTC_SET_TIME`), `/dev/cdrom` : `devtest`.
* **Souris PS/2** (`/dev/input/mice`, `/dev/psaux`) : `mousetest`, `RUNMOUSE.SH`
  (evenements injectes par le moniteur QEMU).
* **ATAPI + iso9660** (parties 11 et 23) : `isotest`, `RUNISO.SH` (CD de
  `genisoimage -R`, liens symboliques Rock Ridge, 300 Ko, 10 verifications).
* **Disquette** (partie 11) : controleur FDC 82077 + DMA ISA canal 2, lecteur 0
  (`/dev/fd0`, 2:0), geometries 360 Ko a 2,88 Mo selon la CMOS, un secteur par
  commande avec 3 essais et remise a zero ; verifie par `fattest` sur une
  disquette FAT12 de 1,44 Mo (`RUNFAT.SH fd`). Un seul lecteur, moteur laisse
  allume, geometrie de la CMOS (pas de detection du format du disque).
* **Swap** (partie 26) : `swaptest`, `RUNSWAP.SH` (24 Mo de RAM, disque de 32 Mo
  `mkswap` : remplit plus de memoire que la RAM, verifie le contenu apres
  page-out/page-in, `fork` avec cases partagees, `swapoff` refuse faute de RAM
  puis accepte, `swapon`). Limites : pas de swap de pages partagees par copie
  sur ecriture, de mappages de fichiers ni de memoire du noyau ; un seul
  peripherique ; pas de fichier de swap ; pas d'entree `/proc/swaps`.
* **Framebuffer** (partie 25) : `fbtest`, `RUNFB.SH` (capture de l'ecran par le
  moniteur QEMU et controle des pixels dessines par `write` et par `mmap`).
* **FAT** (partie 24) : `fattest` (85 verifications) sur FAT12, FAT16 et FAT32
  par `RUNFAT.SH` ; `fsck.vfat -n` propre apres les ecritures du noyau et
  relecture du contenu par mtools ; verifie aussi avec busybox (`cp -r`, `mv`,
  `rm -rf`, `find`, `du`, `df`). Pas de lien dur ni de lien symbolique
  (`EPERM`, comme Linux), pas de `mknod`, fichiers de 2 Go au plus, `chmod`
  n'agit que sur l'attribut lecture seule, le bit "sale" du volume n'est pas
  gere, FAT n'est pas utilisable comme racine (`root=` : ext2 seulement).

### Tests (suite)

* `RUNK.SH` : 26 programmes embarques, 318 verifications (`fattest` et `fbtest`
  s'ignorent sans disque FAT ni `fb=`).
* `RUNEXT2.SH`, `RUNNET.SH`, `RUNMOUSE.SH`, `RUNISO.SH`, `RUNFAT.SH [12|16|32|fd]`, `RUNFB.SH`, `RUNSWAP.SH` :
  chacun fabrique son disque ou son reseau, lance QEMU et conclut par
  `RESULTAT : SUCCES` (ou `ECHEC` avec le dossier des traces). Avec `-n`, ils
  ne regenerent pas les programmes embarques.

### Plan restant

Noyau preemptible (le noyau reste non preemptif : IF=0 en mode noyau, les
processus sont preemptes au retour en mode utilisateur), SMP,
modules, journal ext3/ext4, FAT comme racine, DHCP/DNS dans le noyau.

---

## Systeme utilisateur (agent E) : `USR/`, `TOOLS/LPC32.PAS`, `TESTS/U/`

Tout le systeme utilisateur est ecrit en Pascal et compile par `lpc -3X`
(ELF32 i386 statiques, sans bibliotheque C) : init, getty, login, un shell
POSIX, les outils de base, les 178 commandes du depot, un installateur.
`BUILD.SH` fabrique la racine (`$W/root`) puis l'image disque ; la racine
type est dans `USR/ROOTFS/` (`etc/passwd`, `shadow`, `group`, `profile`,
`inittab`, `rc`, `fstab`, `issue`, `motd`, `hostname`, `usr/share/bench/`).
`NOCMDS=1` ne construit que le systeme minimal (USR/*), `KSRC=fichier.PAS`
choisit une autre source de noyau.

### Demarrage

`chargeur (BOOT/)` -> `/boot/linux0` -> `/sbin/init` -> `/etc/inittab` ->
`/etc/rc` -> `getty` (affiche `/etc/issue`) -> `login` (`/etc/passwd` +
`/etc/shadow`, hachage crypt de type V7 sur 13 caracteres) -> `$SHELL`
(`/bin/sh`, invite `# ` pour root, `$ ` sinon, `/etc/motd`).
Comptes de l'image : `root` / `root`, `linux` / `linux` (a changer avec
`passwd`). `init` suit `/etc/inittab` (`id:niveaux:action:[VAR=val] cmd`,
actions `sysinit wait once respawn ctrlaltdel shutdown`) et, sans inittab,
`/etc/ttys` ; limitation du rythme des relances ; signaux : `USR1` arret,
`USR2` extinction, `TERM` redemarrage, `INT` Ctrl-Alt-Suppr, `HUP` relecture.

### Programmes (`USR/`)

| Fichier | Installe | Role |
|---|---|---|
| `INIT.PAS` | `/sbin/init` | processus 1 |
| `GETTY.PAS`, `LOGIN.PAS` | `/sbin/getty`, `/bin/login` | terminal, connexion |
| `SH.PAS` | `/bin/sh` (`ash`) | shell POSIX : listes, `&&` `\|\|`, tubes, redirections, here-documents, `$(..)`, `$((..))`, `${..}` (`:- := :? :+ # % ## %%`), fonctions, `case`, `for`, `while`, `until`, `if`, `trap`, `exec`, `eval`, `read`, `getopts`, `set`, `shift`, `wait`, `jobs`/`fg`/`bg`/Ctrl-Z (groupes de processus), historique et edition de ligne, completion par Tab |
| `PASSWD.PAS`, `MKPASSWD.PAS` | `/bin/passwd`, `/sbin/mkpasswd` | mots de passe (shadow) |
| `ID`, `KILL`, `PS`, `MKDIR`, `RMDIR`, `RM`, `SYNC`, `HOSTNAME` | `/bin` | outils de base (`/proc` pour `ps`) |
| `MOUNT`, `UMOUNT`, `HALT`, `REBOOT`, `POWEROFF` | `/sbin` | montages, arret (`reboot(2)`) |
| `INSTALL.PAS` | `/sbin/install`, `/sbin/mkfs.ext2` | installateur et mkfs.ext2 (voir ci-dessous) |

Cinq langues : `FR` (defaut), `EN`, `GR` (allemand), `SP`, `IT`. La langue vient
de la variable `LANGUAGE` (`/etc/profile`, ou `/etc/default/locale`), que
`init` lit et transmet a ses fils ; messages systeme (`SysErrorText`,
init, getty, login, passwd, installateur...) traduits.

### Installateur et mkfs.ext2 (`USR/INSTALL.PAS`)

`install [-d disque] [-l FR|EN|GR|SP|IT] [-s Mo] [-r racine] [-y] [-q]` :
1. partitionne le disque cible : MBR (`/usr/share/boot/MBR.BIN`), chargeur
   `STAGE2.BIN` (52 secteurs apres le MBR, parametres LBA/nombre de secteurs
   ecrits dans le MBR), une partition Linux `83h` active au secteur 2048 ;
2. cree un ext2 equivalent a `mke2fs -t ext2 -b 1024 -I 128
   -O none,filetype,sparse_super` (groupes de 8192 blocs, sauvegardes du
   superbloc/GDT aux groupes 0, 1, 3, 5, 7, 9...), `lost+found` de 12 blocs ;
3. copie `/` (sans le contenu de `/proc /sys /dev /tmp /mnt /var/tmp`) :
   modes, proprietaires, dates, liens symboliques (courts dans l'inode),
   fichiers speciaux, indirections simple et double ; `/etc/profile` recoit
   `LANGUAGE=XX` (langue choisie) ;
4. le disque installe s'amorce seul (chargeur de B + noyau copie de `/boot`).
`mkfs.ext2 [-s Mo] peripherique` (meme programme, autre nom) formate sans
partitionner. Verification : `e2fsck -fn` propre (3 Mo a 300 Mo essayes ;
fichiers de 40 Mo, 300 entrees de repertoire, liens, tubes). Limites : blocs
de 1 Ko et inodes de 128 octets uniquement, disque de 2 Go au plus, 4000
entrees par repertoire, une seule source (`/` en cours d'execution ou
`-r dossier`), ext2 seulement (pas de journal). Essai : `TESTS/U/RUNU.SH install`
(deux disques sous QEMU : `install -d /dev/hdb`, e2fsck, amorce du disque
installe, LANGUAGE=IT).

### Commandes du depot

Les 178 commandes du depot (hors `HALT`, `REBOOT` du BIOS, remplaces par
`USR/`) sont compilees dans `/bin`. Chacune est un programme de style DOS
(`Uses Dos, Crt`) : sa syntaxe est la sienne, voir son aide (`cmd /?`). L'etat
de chaque commande (marche / reserves / echoue), mesure sur l'hote et sous
KERNEL32/QEMU, est dans `TOOLS/COMMANDES.TXT`. Corrections de commandes sous
`{$IFDEF LINUX0}` (separateur `/`, fins de ligne LF, ligne de commande brute
d'`awk`, `mktemp`, `repeat`...) pour rester compatibles avec DOS.

### Tests (`TESTS/U/`)

| Fichier | Contenu |
|---|---|
| `RUNU.SH [sh\|host\|qemu\|power\|install]` | orchestre tous les essais : construit l'image dans `$W` (pas `IMAGE/`), `KSRC=` choisit le noyau |
| `shtest.sh`, `sh/*.sh` | le shell contre `dash` (5 scripts, sortie identique) |
| `cmdbench.py` | essai fonctionnel de chaque commande (hote), `--gen DIR` fabrique `run.sh` pour QEMU |
| `mkcmdtab.py` | fabrique `TOOLS/COMMANDES.TXT` (hote + QEMU) |

### Regles de l'API Unix de `L32API.PAS` utiles aux programmes

Fonctions `Sys*` (`SysFork`, `SysExecve`, `SysWaitPid`, `SysPipe`, `SysDup2`,
`SysOpen/Read/Write/Close`, `SysStat/LStat`, `SysOpenDir/ReadDir`,
`SysMount`, `SysReboot`, `SysTc*`, `SysSigAction`, `SysGetPw*`, `SysCrypt`,
`SysLang`...). Pieges du langage (Pascal insensible a la casse) : ne pas
nommer un type et une constante pareil a la casse pres (`TWord`/`tWord`) ; une
procedure du programme homonyme d'une predefinie ou de l'API est renommee
automatiquement (`NewStr`, `ReadKey`, `Sprintf`...) ; `}` dans un
commentaire `{ }` le termine ; `Until` n'est pas un nom de parametre ;
eviter les procedures imbriquees qui lisent les parametres de l'englobante.
Les parametres `Const` de type chaine sont copies dans le cadre de l'appele
(sinon un temporaire de l'anneau `STRRING` pouvait etre ecrase apres 256
chaines temporaires).

### Demandes au noyau (agent D)

Details et cas minimaux : `/tmp/claude-0/work/k32/BUGS_NOYAU.md`.
1. `kill(-1, sig)` fige le systeme (sous Linux : tous les processus sauf init
   et l'appelant) ; `USR/INIT.PAS` envoie les signaux un par un. Tests faits
   avec `KERNEL32.PAS` du 14:11 (et `D/backup-9.PAS` du 13:14) ; le noyau de
   13:58 paniquait au lancement de `/sbin/init` (corrige depuis).
2. Le second disque IDE (`-drive ...,index=1`, /dev/hdb) fonctionne ; un
   disque en `index=2` (secondaire maitre, hdc) n'est pas detecte.
3. `uname -s` renvoie `LINUX-0` (les programmes Linux courants attendent
   `Linux` : le noyau garde-t-il `uname_release=` seulement pour la release ?).
