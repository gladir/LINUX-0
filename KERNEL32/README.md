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
| 30 | IPC SysV : memoire partagee (`shmget/shmat/shmdt/shmctl`, segments de 16 Mo au plus, VMA `VmShm`, pages hors comptage, detachement a la sortie, `IPC_RMID` differe), semaphores (`semget/semop/semtimedop/semctl`, blocage, `IPC_NOWAIT`, `SEM_UNDO` applique a la sortie, `GETVAL/SETALL`...), files de messages (`msgget/msgsnd/msgrcv/msgctl`, types >0, <0, `MSG_EXCEPT`, `MSG_NOERROR`, qbytes), `ipc(2)` et appels directs 392-402, droits uid/gid/mode, `IPC_STAT/SET/INFO` |
| 31 | files de messages POSIX (`mq_open/unlink/timedsend/timedreceive/notify/getsetattr`, descripteurs pollables, priorites, notification par signal `SI_MESGQ`), AIO (`io_setup/submit/getevents/cancel/destroy`, execution synchrone a la soumission, notification eventfd), `sendmmsg/recvmmsg`, futex complets (`WAIT/WAKE`, bitsets, delais absolus, `REQUEUE/CMP_REQUEUE/WAKE_OP`, `LOCK_PI/UNLOCK_PI/TRYLOCK_PI` sans elevation de priorite, cle physique pour les pages partagees, listes robustes traitees a la sortie) |
| 32 | ptrace et seccomp : `ptrace(2)` complet (TRACEME, ATTACH/SEIZE/DETACH/INTERRUPT, PEEK/POKE TEXT/DATA/USER avec ecriture forcee dans le code, GETREGS/SETREGS, GETFPREGS/GETFPXREGS, GETREGSET, CONT/SYSCALL/SINGLESTEP/SYSEMU/SYSEMU_SINGLESTEP/KILL, SETOPTIONS : TRACESYSGOOD/FORK/VFORK/CLONE/EXEC/VFORKDONE/EXIT/SECCOMP/EXITKILL, GETEVENTMSG, GETSIGINFO/SETSIGINFO, GET_SYSCALL_INFO, PEEKSIGINFO, GETSIGMASK, GET_THREAD_AREA), arrets aux signaux, aux appels systeme (entree/sortie) et aux evenements `PTRACE_EVENT_*`, attachement automatique des fils, retour du zombie au vrai pere, tracee detache a la mort du traceur ; `int3` (gate DPL 3), pas a pas par `TF` (y compris au travers de `INT 80h`), registres de debogage DR0-DR7 (`POKEUSER`, commutes par tache, points d'arret materiels d'execution et d'ecriture/lecture, `DR6`) ; seccomp : `SECCOMP_MODE_STRICT`, `SECCOMP_MODE_FILTER` (interpreteur BPF classique complet, validation du programme, filtres empiles, heritage par fork, `TSYNC` (teste sur un seul fil)), retours `ALLOW/LOG/ERRNO/TRAP(SIGSYS)/TRACE/KILL_THREAD/KILL_PROCESS`, `prctl(PR_SET_SECCOMP, PR_GET_SECCOMP, PR_SET_NO_NEW_PRIVS, PR_GET_NO_NEW_PRIVS)`, `seccomp(2)` (354), `/proc/PID/status` (`TracerPid`, `Seccomp`, `NoNewPrivs`) |
| 33 | attributs etendus et ACL POSIX : `setxattr/getxattr/listxattr/removexattr` (+ `l*` et `f*`, 226-237), espaces `user.`, `trusted.`, `security.`, `system.posix_acl_access/default` ; magasin en memoire (tmpfs, devtmpfs, ramfs) et ext2 (bloc d'attributs `i_file_acl`, hachage des entrees, copie sur ecriture d'un bloc partage, fonctionnalite `ext_attr`, valide par `e2fsck` et `debugfs ea_list`) ; ACL : validation, equivalence avec les bits de mode, controle des droits (algorithme `posix_acl_permission`), `chmod` qui met a jour le masque, ACL par defaut heritee a la creation (fichiers, repertoires, `mknod`) sans umask |
| 34 | `clone3` (435, arguments 64 bits, `pidfd`, `parent_tid`, `child_tid`, pile), `clone` avec `CLONE_PIDFD/CHILD_SETTID`, `unshare` et `setns` (346) sur les espaces `CLONE_NEW*`, `/proc/PID/ns/*` (liens magiques `type:[ino]` lisibles et ouvrables, repertoire listable). Reels : UTS (noms d'hote et de domaine par espace), IPC (cles et identifiants SysV par espace), PID (pid virtuels : `getpid/getppid/gettid`, valeur de retour de `fork/clone/wait4`, `kill/tkill/pidfd_open` ; le premier processus de l'espace est le pid 1 et sa mort tue les autres). Identite seulement, sans isolation : montages (NS), reseau (NET), utilisateurs (USER : pas de `uid_map`), cgroup, temps |
| 29 | signaux temps reel : file d'attente de `siginfo` par tache (16 entrees, signaux < 32 non empiles, RT empiles), `si_code/si_pid/si_uid/si_value`, `si_addr` des SIGSEGV, `rt_sigtimedwait(+64)`, `rt_sigqueueinfo`, `rt_tgsigqueueinfo`, `signalfd/signalfd4`, minuteries POSIX (`timer_create/settime/gettime/getoverrun/delete` + 64 bits, SIGEV_SIGNAL/NONE/THREAD_ID, resolution 10 ms, supprimees a l'execve), `pidfd_open`, `pidfd_send_signal`, `waitid(P_PIDFD)`, verrous de fichiers reels : `flock`, `fcntl` POSIX (F_GETLK/SETLK/SETLKW, 32 et 64 bits, decoupe des plages, liberes a la fermeture de tout descripteur du fichier et a la sortie du processus) et OFD (F_OFD_*), `F_GETPIPE_SZ` |
| 28 | appels systeme complementaires issus de l'audit (lot A1, apres la partie 16) : ordonnancement (`sched_*`, `getcpu`, affinite), capacites (`capget/capset`, `Capable`, regles setuid/execve), `personality`, `sendfile/sendfile64/copy_file_range/splice/vmsplice`, `preadv/pwritev(+2)`, `fallocate`, `syncfs`, `statx`, `renameat2`, `openat2`, `faccessat2`, `fchmodat2`, `execveat`, `close_range`, `memfd_create`, `mlock*/mincore/madvise` reels (`VmLocked`, RLIMIT_MEMLOCK), `waitid`, `process_vm_readv/writev`, `kcmp`, `unshare(FILES/FS)`, `membarrier`, horloges 64 bits (`clock_*64`, `futex_time64`, `ppoll/pselect6`, `epoll_pwait2`, `timerfd*64`, `utimensat_time64`), `adjtimex`, `ioperm/iopl`, ENOSYS explicites (`EnosysList`) |
| 25 | framebuffer Bochs/QEMU VGA : `fb=LxH` sur la ligne de commande programme le mode 32 bits (registres VBE 1CEh/1CFh), memoire video (BAR 0 PCI) mappee en F8000000h, `/dev/fb0` (29:0) : read, write, lseek, `FBIOGET_FSCREENINFO/VSCREENINFO`, `mmap` partage (VMA `VmPhys`, PTE hors comptage) |
| 24 | FAT12/16/32 et vfat (noms longs UTF-8/UCS-2, noms courts `~N`, indicateurs de casse NT), lecture/ecriture, repertoires qui grandissent, renommage, troncature, attribut lecture seule, dates, `statfs`, FSInfo FAT32 ; options `ro`, `rw`, `umask=`, `uid=`, `gid=` ; types `vfat`, `msdos`, `fat` |
| 35 | fichiers de plus de 2 Go (physiquement apres la partie 2 pour l'arithmetique `U64*`, repartie dans le VFS, ext2, FAT, iso9660, le peripherique bloc, les verrous et les appels systeme) : voir la section "Partie 35" |
| 36 | `/proc/sys` (sysctl en lecture et ecriture), `/proc/swaps`, swap sur fichier ordinaire, chargeur de modules (`init_module/delete_module/finit_module`, `.ko` de `lpc -3M`), `/proc/modules`, `/proc/kallsyms`, `request_irq` pour les modules : voir la section "Partie 36" |
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

Fichiers jusqu'a 16 Go (blocs de 1 Ko) ou 2 To (blocs de 4 Ko) depuis la
partie 35 (`i_size_high`, `large_file`) ; pas d'extents, de journal (rejoue), d'attributs
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

### Noyau preemptible (partie 27)

Le noyau est preemptible comme `CONFIG_PREEMPT` : une tache qui execute du
code noyau (appel systeme, faute de page, thread noyau) est retiree du
processeur par l'interruption du minuteur quand sa tranche est finie, meme
au milieu d'un long traitement (copie de 24 Mo, ecriture de fichiers,
`bdflush`...). Parametre de la ligne de commande : `preempt=0` desactive
(comportement de la phase 2 : IF masque en mode noyau) ; par defaut le
noyau est preemptible.

Principe (un seul verrou, pas de verrous fins) :

* **Verrou du noyau (`BklOwner`)** : un verrou dormant unique protege tout le
  code noyau des taches (VFS, ext2, FAT, iso9660, reseau, swap, ordonnanceur,
  caches...). Une tache le prend a l'entree en mode noyau (`BklAcquire` dans
  `KTrap` pour un appel systeme ou une exception venant du mode utilisateur ;
  si une autre tache le detient, elle attend sans etre ordonnable) et le rend
  au retour en mode utilisateur (`ReturnToUser`) ou quand elle cede
  volontairement le processeur (sommeil, `yield`, sortie) : `Schedule` le rend
  alors et la tache le reprendra, par transmission au moment du choix de
  l'ordonnanceur (champ `NeedBkl`). Une **preemption** (`KPreemptCheck`) garde
  le verrou. Invariant : le code noyau de deux taches ne s'entrelace jamais ;
  il ne s'entrelace qu'aux points ou le noyau non preemptible cedait deja
  (appels de `Schedule`). Il n'y a donc qu'un verrou : pas d'ordre de
  verrous. En revanche les processus en mode utilisateur pur (et les
  processus non bloques sur le verrou) tournent pendant qu'une tache noyau
  est preemptee.
* **IRQ** : les gestionnaires (clavier, serie, souris, reseau, minuteur) ne
  sont pas reentrants. Quand l'IRQ arrive alors qu'une tache detient le
  verrou (ou que la tache courante est en mode noyau), `IrqTop` ne fait que
  compter le tick (`Jiffies`, comptabilite et tranche de la tache courante,
  `TickPend`) ou masquer la ligne et noter l'IRQ (`PendIrq`) ; le travail
  complet (reveils, minuteries, reseau, `KbdIrq`...) est execute plus tard par
  `RunBH`, avec IF masque, par la tache qui rend le verrou, par `Schedule`, ou
  par la tache d'inactivite. Quand le verrou est libre et que l'IRQ interrompt
  du code utilisateur ou l'inactivite, le gestionnaire s'execute tout de
  suite (comme avant). Les sections critiques en IF=0 ne sont donc pas
  converties en spinlocks : il n'y a pas de donnee partagee avec une IRQ
  hormis `Jiffies`, `NeedResched`, `TickPend`, `PendIrq` et le masque du PIC.
* **Compteur `PreemptCount`** par tache (`PreemptDisable/Enable`) : interdit la
  preemption (utilise pendant la copie de la structure de tache dans `fork`
  et `KernelThread`, ou la copie est ordonnable un instant).
* **Preemption** : au retour d'une IRQ vers du code noyau (`KTrap` ->
  `KPreemptCheck`) si `NeedResched`, tache courante ordonnable
  (`TsRunnable` : une tache deja zombie/endormie va ceder elle-meme), detentrice
  du verrou, `PreemptCount` = 0 et IF=1 dans le code interrompu.
* Regles pour le code noyau futur : lire `CR2` avant d'autoriser les
  interruptions (fait dans `KTrap`, copie dans `Cur^.Cr2`) ; n'affecter un
  etat non ordonnable (`TsSleeping`, `TsZombie`...) qu'immediatement avant
  `Schedule` ; ne rien supposer de la tache d'inactivite ; ne pas appeler
  `Schedule` depuis un gestionnaire d'IRQ ; tout nouveau champ de la
  structure de tache copie par `fork` doit etre reinitialise a la creation.
* Diagnostic : `/proc/stat` ligne `kpreempt N P D` (preemptions dans le noyau,
  noyau preemptible 0/1, profondeur maximale de pile noyau vue par une IRQ) ;
  la tache d'inactivite imprime l'etat des taches et du verrou toutes les 30 s
  d'inactivite ; un oops en mode preemptible affiche les 16 dernieres
  commutations.
* Bugs trouves par les essais de charge : (1) preemption d'une tache deja
  zombie (reveil du pere perdu) ; (2) preemption entre la copie de la tache
  et son passage a l'etat non ordonnable dans `fork` (commutation vers une
  pile invalide) ; (3) `CR2` lu apres `STI`. Chaque correction a ete validee
  par des centaines d'executions de la suite (`RUNPREEMPT.SH`).
* Ce que ce n'est pas : pas de SMP, pas de verrous fins (le code noyau de deux
  taches ne s'execute jamais en parallele), pas de preemption pendant une
  section qui detient `PreemptCount`. La latence d'une tache en mode noyau est
  bornee par la tranche (environ 70 ms), pas par un point de preemption fin.

### Audit de couverture (phase 4)

`TOOLS/COUVERTURE.PY` genere `TOOLS/COUVERTURE.TXT` : table des 451 appels
systeme de `unistd_32.h` (reel / stub / ENOSYS explicite / absent, test qui
couvre l'appel) et familles d'ioctl, systemes de fichiers, pilotes, entrees
/proc et /sys, sockets, drapeaux. Avant le lot A1 : 219 appels reels sur 451
(48,6 %), 223 absents. Apres : voir `COUVERTURE.TXT` (293 reels, 65,0 %,
5 stubs, 84 ENOSYS explicites, 69 absents). Les ENOSYS explicites sont les
appels obsoletes (`break`, `stty`, `create_module`...) et ceux hors perimetre
(`bpf`, `perf_event_open`, `io_uring`, nouvelle API de montage, `landlock`,
`userfaultfd`, `quotactl`, `modify_ldt`, `vm86`...). Limites connues de ce lot :
fichiers de plus de 2 Go : realises au lot suivant (partie 35), `ioperm`
accorde tous les ports (IOPL), `fallocate` ne reserve pas de blocs,
`renameat2(EXCHANGE)` non atomique, `openat2` refuse les `RESOLVE_*`,
`adjtimex` ne discipline pas l'horloge, les verrous `flock`/`fcntl` sont
reels depuis la partie 29. Correction au passage :
`FUTEX_WAIT_BITSET` utilise un delai absolu comme Linux et
`clock_nanosleep(TIMER_ABSTIME)` tient compte des nanosecondes.

### Tests (suite)

* `RUNK.SH` : 40 programmes embarques, 849 verifications (dont `bigtest` et `modtest` des parties 35 et 36, qui ne font leurs essais de disque que sous `RUNBIG.SH` ; `ptracetest`, `seccomptest`, `xattrtest`, `nstest` des lots A2c/A2d ; `xattrtest` est aussi execute sur ext2 par `ext2test`)
  ; avant ces lots : 34 programmes, 586 verifications (dont `syscalltest` : 94
  verifications du lot A1, `sigrttest` : 58 du lot A2a, `ipctest` et
  `mqfutextest` du lot A2b) (`fattest`, `fbtest`,
  `swaptest`, `idetest` s'ignorent sans le materiel voulu ; `killtest` :
  `kill(pid, 0, -pgrp, -1)` ; `preempttest` : latence d'un processus en mode
  utilisateur pendant de longs appels systeme d'un autre (trou maximal
  mesure par `rdtsc`, 370 ms avec `preempt=0`, 70-90 ms avec le noyau
  preemptible) ; `pstress` : 6 processus en parallele (fichiers avec sommes de
  controle sur ext2 ou tmpfs, tubes + fork, mmap, socketpair, TCP en
  bouclage)). `KARGS="preempt=0" RUNK.SH` rejoue sans preemption ; tous les
  `RUN*.SH` acceptent `KARGS` (parametres ajoutes a la ligne de commande).
* `RUNIDE.SH` : ext2 sur hda..hdd (index QEMU 0..3, jeux "2 3", "0 1 2 3", "3",
  "0 2", "1 3"), e2fsck propre. `RUNPREEMPT.SH [-r N] [-p 0|1]` : la suite
  complete avec disque ext2, N fois, puis e2fsck.
* `RUNBIG.SH [-f ext2|fat] [-b 1024|4096]` (partie 35) : disque creux de 6 Go, `bigtest`, `e2fsck`/`fsck.vfat` ;
  `RUNSWAP.SH -f [-b 4096]` : swap sur fichier d'un ext2 (partie 36) ;
  `modtest` (dans `RUNK.SH`) : modules et sysctl.
* `RUNEXT2.SH`, `RUNNET.SH`, `RUNMOUSE.SH`, `RUNISO.SH`, `RUNFAT.SH [12|16|32|fd]`, `RUNFB.SH`, `RUNSWAP.SH` :
  chacun fabrique son disque ou son reseau, lance QEMU et conclut par
  `RESULTAT : SUCCES` (ou `ECHEC` avec le dossier des traces). Avec `-n`, ils
  ne regenerent pas les programmes embarques.

### Partie 35 : fichiers de plus de 2 Go (lot 1 de D3)

Toutes les positions et les tailles sont des paires non signees (`Size`/`SizeHi`
dans `TInode`, `Pos`/`PosHi` dans `TFile`, `TSuper.LargeFiles` pour les systemes
de fichiers qui les gerent) avec l'arithmetique `U64Lt/U64Le/U64Add/U64Sub/
U64ShrL/U64ShlL/Log2U` (partie 2). Realise :

* VFS : `VfsLlseek` (SET/CUR/END, `SEEK_DATA/SEEK_HOLE`), `lseek` 32 bits avec
  `EOVERFLOW`, `_llseek` (140), `pread64/pwrite64` et `preadv/pwritev(+2)` avec
  position de 64 bits, `truncate64/ftruncate64` (`EFBIG` au-dela du maximum du
  systeme de fichiers, taille restauree), `fallocate` 64 bits, `sendfile64`,
  `copy_file_range`, `splice` (decalages de 8 octets), `fstat64/stat64/lstat64/
  fstatat64/statx` (`st_size` et `st_blocks` sur 64 bits), `stat/fstat` 32 bits :
  `EOVERFLOW` ; `open` sans `O_LARGEFILE` d'un fichier de 2 Go ou plus :
  `EOVERFLOW` ; `write` sans `O_LARGEFILE` au-dela de 2 Go - 1 : `EFBIG` ; les
  systemes de fichiers sans positions 64 bits (tmpfs, proc...) lisent
  "fin de fichier" ou refusent `EFBIG` au-dela de 2 Go ; `RLIMIT_FSIZE` non
  signee (limites de 2 Go a 4 Go - 2 exactes, `prlimit64` : au-dela de 32 bits =
  infini) avec `SIGXFSZ` ; verrous `fcntl` (`F_SETLK64/GETLK64/OFD`, `flock64`)
  sur des plages de 64 bits ; `FIONREAD` borne.
* ext2 : `i_size_high` (`i_dir_acl` des fichiers ordinaires), fonctionnalite
  `large_file` posee a l'ecriture (revision 1 forcee comme `ext2_write_inode`),
  taille maximale calculee par bloc (1 Ko : 17 Go ; 4 Ko : 2 To, plafond
  `i_blocks` 32 bits), troncature et ecriture a 64 bits. Disques de plus de
  2 Go : correction du produit `bloc * taille` dans la couche bloc
  (`BRead/BufWrite`) qui depassait 31 bits ; attente IDE bornee par le temps
  (15 s) et non plus par un nombre d'iterations (un disque hote lent faisait
  echouer des lectures).
* FAT12/16/32 : fichiers jusqu'a 4 Go - 1 (taille de 32 bits non signee),
  `EFBIG` au-dela. iso9660 : tailles de 32 bits non signees (adapte, non
  teste au-dela de 2 Go : pas de fichier ISO de cette taille dans les essais).
* Peripheriques blocs : `/dev/hdX` lu et ecrit sur plus de 4 Go, `BLKGETSIZE64`.
* Limites : `mmap2` d'un fichier a un decalage de 2 Go ou plus : `EOVERFLOW`
  (les VMA gardent un decalage de 32 bits) ; tmpfs et les systemes memoire
  refusent les fichiers de plus de 2 Go (`EFBIG`) ; `fadvise/readahead/
  sync_file_range` acceptent les decalages 64 bits sans les exploiter ;
  `getdents64` renvoie `d_off` sur 32 bits utiles.
* Essais : `TESTS/K/bigtest.c` + `RUNBIG.SH` : disque creux de 6 Go (ext2, blocs
  de 1 Ko et 4 Ko, avec un fichier de remplissage de 2,2 Go pour que les
  blocs alloues depassent 2^31 octets), 64 verifications (fichier creux a 3 Go et
  5 Go, `llseek`, `SEEK_DATA/HOLE`, croisement de 4 Go, `EOVERFLOW`, verrous 64
  bits, troncature et `fallocate`, `sendfile64`, `RLIMIT_FSIZE`, demontage et
  remontage, donnees ecrites loin sur le disque, fichier de 3 Go ecrit par
  l'hote lu a 2,5 Go) puis `e2fsck -fn` propre ; FAT32 de 3 Go avec un fichier
  de 2300 Mo ecrit par `mcopy` (marqueurs a 2100 Mo et a la fin, ajout,
  ecriture a 2200 Mo, reduction) puis `fsck.vfat -n` propre.

### Partie 36 : sysctl, swap sur fichier, modules du noyau (lot 2 de D3)

**`/proc/sys`** : arbre de parametres (`SyAddInt/SyAddStr`), lecture et ecriture
par `write(2)` (valeur decimale, verification des bornes, `EINVAL`/`EACCES`/
`EPERM`). Appliques par le noyau : `kernel/hostname` et `domainname` (par espace
UTS, vus par `uname`), `kernel/pid_max` (`AllocPid`), `fs/file-max` (`ENFILE`
dans `FileNew`), `vm/drop_caches` (purge du cache de tampons),
`kernel/modules_disabled` (irreversible), `net/ipv4/ip_default_ttl`,
`net/ipv4/icmp_echo_ignore_all` ; en lecture seule : `ostype`, `osrelease`,
`version`, `threads-max`, `tainted`, `random/boot_id`, `random/uuid` (nouveau a
chaque lecture), `fs/file-nr`, `inode-nr`... Conserves et relus mais **sans effet
dans le noyau** : `randomize_va_space` (pas d'ASLR avant le lot G),
`overcommit_memory/ratio`, `swappiness`, `panic*`, `sysrq`, `printk`, `core_pattern`,
`shm*/msg*/sem`, `net/ipv4/ip_forward` (pas de routage avant le lot E), les
parametres de tampons `net/core/*`, `fs/inotify/*`, `dirty_*`, `nr_hugepages`...
(environ 65 entrees, `InitSysctl`).

**`/proc/swaps`** (en-tete Linux) ; **swap sur fichier ordinaire** : `swapon` accepte
un fichier d'un ext2 ou d'un FAT (operation `SoBmap` du superbloc : bloc logique
-> secteur), refuse les fichiers a trous, garde l'inode (ecriture et troncature :
`ETXTBSY`), priorite `SWAP_FLAG_PREFER`, `swapoff` par chemin ; un seul espace
d'echange actif, 128 Mo au plus.

**Modules** : `init_module(128)`, `finit_module(350)`, `delete_module(129)`.
Chargeur ELF32 `ET_REL` i386 (modules de `lpc -3M`, format dans
`DEMANDES_A.md`) : sections `SHF_ALLOC` placees (alignement, `.bss` mise a zero)
dans un bloc de pages du noyau, relocations `R_386_32`, `R_386_PC32`,
`R_386_PLT32`, symboles resolus par nom (`_TPF_NOM`) dans la table d'exports du
noyau (`KsAdd`, `InitModules`) puis dans ceux des modules charges (procedures
`Export;`) ; symboles inconnus : `ENOENT` ; image invalide : `ENOEXEC` ; module
deja charge ou symbole deja exporte : `EEXIST` ; `init_module` retournant une
erreur : le module est decharge et l'erreur renvoyee ; parametres `nom=valeur`
(`module_param_int/str`) ; droits `CAP_SYS_MODULE`. Dependances : un module qui utilise
les symboles d'un autre ne peut plus l'etre decharge (`EAGAIN`, comme
`rmmod` sous Linux) ; comptage d'utilisation (un peripherique caractere d'un
module est compte tant qu'un fichier est ouvert) ; `/proc/modules` (nom, taille,
utilisation, dependants, etat, adresse), `/proc/kallsyms` (exports du noyau et
des modules), `kernel/tainted` (4096 = module hors arbre, 1 = licence non GPL),
`kernel/modules_disabled`. API exportee aux modules (`KsAdd`) : `printk`,
`printk_int`, `kmalloc`, `kzalloc`, `kfree`, `get_jiffies`, `ksleep`,
`copy_to_user`, `copy_from_user`, `put_user_long`, `get_user_long`,
`register_chrdev(majeur, nom, table)` (table de 16 adresses : `FoRead`=0, `FoWrite`=1,
`FoReaddir`=2, `FoIoctl`=3, `FoPoll`=4, `FoOpen`=5, `FoRelease`=6, `FoLlseek`=7,
`FoFsync`=8 ; majeur 0 : attribution de 254 vers le bas), `unregister_chrdev`,
`mknod_node`, `unlink_node`, `file_get_pos`, `file_set_pos`, `file_flags`,
`module_param_int`, `module_param_str`, `request_irq(irq, procedure)` (IRQ 3 a 15
libres, appelee comme les gestionnaires du noyau), `free_irq`, `get_pid`, `get_uid`,
`panic`. Limites : `register_chrdev` et `request_irq` ne sont acceptes que pendant
`init_module` ; pas de `/sys/module` ; pas d'API de systemes de fichiers, de
reseau ni de blocs pour les modules ; pas de `query_module/create_module` (ENOSYS).
Essais : `modtest` (51 verifications de modules : chargement, erreurs, parametres,
peripherique, comptage, dependances, `finit_module`, `request_irq` sur l'IRQ 8 de
l'horloge CMOS ; 34 de sysctl et /proc/swaps) avec les modules `TESTS/K/hello.pas`, `hello2.pas`
(dependant de `hello`), `badinit.pas`, `unkmod.pas`, `irqmod.pas` ; `RUNSWAP.SH -f`
(swap sur fichier ext2 de 24 Mo sous pression memoire, blocs de 1 Ko et 4 Ko,
`e2fsck` propre).

### Lots A2c et A2d (ptrace, seccomp, xattr/ACL, clone3/espaces de noms)

Limites connues : `PTRACE_SINGLEBLOCK` et `SET_THREAD_AREA` refusent (`EIO`) ;
`PTRACE_LISTEN` ne fait que valider ; `SECCOMP_RET_USER_NOTIF` repond `ENOSYS` ;
au plus 8 filtres seccomp empiles par tache ; les attributs etendus ext2 n'ont
qu'un bloc (pas d'attributs dans l'inode, pas de partage de blocs a la creation) ;
FAT, iso9660, proc et sysfs repondent `EOPNOTSUPP` aux xattr (sauf sysfs, tmpfs) ;
les espaces de noms NS/NET/USER/CGROUP/TIME sont des objets d'identite sans
isolation ; `/proc`, les groupes (`kill(0/-1/-pgrp)`, `getpgid`, `setsid`) et les `si_pid` ne sont pas traduits par espace de pid ; pas de `set_tid` dans
`clone3` ; fichiers de plus de 2 Go : voir la partie 35.

### Plan restant

Verrous fins a la place du verrou unique du noyau (ext2/FAT/reseau/VFS
independants), SMP, journal ext3/ext4, FAT comme racine, DHCP/DNS dans
le noyau, isolation reelle des montages et du reseau (fichiers de plus de 2 Go
et modules : realises, parties 35 et 36).

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
| `LN`, `CHOWN` (+`chgrp`), `MKNOD`, `READLINK` (+`realpath`) | `/bin` | liens, proprietaires (-R), fichiers speciaux, chemins canoniques |
| `UPTIME`, `FREE`, `DMESG`, `PGREP` (+`pkill`, `pidof`, `killall`) | `/bin` | information systeme par `/proc` et `syslog(2)`, recherche et signaux par nom |
| `NICE`, `NOHUP`, `TIMEOUT`, `USLEEP`, `PRINTENV`, `TTY`, `NOLOGIN` | `/bin`, `/sbin/nologin` | lancement de commandes, delais, environnement |
| `IFCONFIG`, `ROUTE`, `PING`, `NSLOOKUP`, `WGET`, `NC` | `/sbin`, `/bin` | reseau : ioctl SIOCGIF*/SIOCSIF*, `/proc/net/*`, sockets (API `SysSocket`, `SysConnect`, `SysSendTo`..., resolveur `SysResolve` : /etc/hosts puis DNS par UDP, `SysServPort`) ; valides sous QEMU (rtl8139 : ping, wget vers un serveur http de l'hote) |
| `SU`, `MKSWAP`, `SWAPON` (+`swapoff`), `SYSCTL`, `HWCLOCK`, `RENICE`, `WATCH`, `TIME`, `LSMOD` (+`insmod`, `rmmod`) | `/bin`, `/sbin` | identite, zones d'echange, parametres, horloge, priorites, modules (`init_module`/`delete_module` : en attente du noyau) |
| `REGEX.INC`, `GREP.PAS` (+`egrep`, `fgrep`), `SED.PAS`, `AWK.PAS` | `/bin` | [E2] moteur d'expressions regulieres POSIX (BRE/ERE, extensions GNU, references arriere, `[[:classes:]]`, plus longue correspondance) partage par include ; `grep` (-EFGiHhvwxclLoqsnbrR -e -f -A -B -C -m -a -z --include --exclude, DOS `/I`), `sed` GNU (s y d D p P n N g G h H x q Q l = a i c r R w W b t T z F { }, adresses N $ /re/ \\cREc N~M A,+N A,~N 0,/re/ !, -n -e -f -E -r -i -s -z -l), `awk` POSIX complet (BEGIN/END/plages, fonctions, tableaux associatifs, getline toutes formes, printf, tubes et fichiers, RS regex, ENVIRON/ARGV, -F -v -f) ; essais contre GNU grep/sed et mawk |
| `TEST.PAS` | `/bin/test`, `/bin/[` | [E2] conditions POSIX (fichiers, chaines, entiers, -nt -ot -ef, ! ( ) -a -o) |
| `USERMGR.PAS` | `/sbin/useradd` `userdel` `usermod` `groupadd` `groupdel` `groupmod` `adduser` `addgroup` `deluser` `delgroup` `chpasswd` | [E2] gestion de /etc/passwd, shadow, group (USERMGR_ROOT=dossier : autre racine) |
| `UTMP.INC`, `WHO.PAS` | `/bin/who`, `users`, `w`, `last` | [E2] utmp/wtmp (struct utmp Linux 384 octets) ecrits par login et init (naissance/mort des sessions, enregistrement de demarrage) |
| `TELINIT.PAS` | `/sbin/telinit`, `runlevel`, `shutdown` | [E2] niveaux d'execution d'init (inittab `id:niveaux:action:commande`, `initdefault`, `telinit N` par /var/run/init.req + SIGHUP, /var/run/runlevel), arret programme avec diffusion aux terminaux |
| `SYSLOGD.PAS` | `/sbin/syslogd`, `/bin/logger` | [E2] journal systeme : /dev/log (AF_UNIX datagrammes), /etc/syslog.conf (facilite.niveau fichier), `logger -t -p -i` |
| `TOP.PAS` | `/bin/top`, `vmstat` | [E2] etat du systeme par /proc |
| `FIND`, `XARGS`, `TAR` | `/bin` | `find` (-name -iname -type -size -mtime -newer -empty -maxdepth -exec -delete), `xargs` (-n -0 -I -t), `tar` ustar c/x/t, v, z (via gzip), -C ; archives relues par GNU tar et inversement |

Cinq langues : `FR` (defaut), `EN`, `GR` (allemand), `SP`, `IT`. La langue vient
de la variable `LANGUAGE` (`/etc/profile`, ou `/etc/default/locale`), que
`init` lit et transmet a ses fils ; messages systeme (`SysErrorText`,
init, getty, login, passwd, installateur...) traduits.

Modules du noyau : `lpc -3M` produit des `.ko` ELF32 ET_REL (voir
`TOOLS/LPC.TXT`, "Cible -3M", et `DEMANDES_A.md`). /etc complet : passwd,
group, shadow (comptes systeme en `/sbin/nologin`), shells, hosts,
resolv.conf, securetty, nsswitch.conf, protocols, services, login.defs.

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
| `RUNU.SH [sh\|host\|qemu\|power\|net\|install\|mod]` | orchestre tous les essais : construit l'image dans `$W` (pas `IMAGE/`), `KSRC=` choisit le noyau ; `mod` : insmod/lsmod/rmmod de `/lib/modules/hello.ko` (SKIP tant que le noyau n'a pas `init_module`) |
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
