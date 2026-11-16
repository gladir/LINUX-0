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
| 18 | ext2 (et ext3/ext4 depuis la partie 37) : superbloc, descripteurs de groupes epingles dans le cache de tampons, bitmaps, allocation de blocs et d'inodes avec regroupement, inodes de 128 a 1024 octets, revisions 0 et 1, blocs de 1 a 64 Ko, `sparse_super`, `filetype`, indirections simple/double/triple, repertoires lineaires (ajout, fusion a la suppression, agrandissement), liens durs, liens symboliques rapides et lents, `mknod` (tty, bloc, fifo, socket), `rename` (entre repertoires, remplacement), troncature, `chmod/chown/utimes`, `statfs`, `s_state` propre/sale, remontage, liste des orphelins. Extents, journal jbd/jbd2, sommes de controle, `flex_bg`, `64bit`... : voir la section "Partie 37" |
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
| 37 | ext3/ext4 (physiquement dans la partie 18, plus la couche bloc de la partie 11) : fonctionnalites compat/incompat/ro_compat reconnues et refusees proprement si inconnues, arbre d'extents en lecture/ecriture, journal jbd/jbd2 (rejeu au montage, ecriture journalisee `data=ordered`/`data=writeback`), `flex_bg`, `meta_bg`, `64bit`, `uninit_bg`/`GDT_CSUM` (crc16), `metadata_csum` (crc32c), `extra_isize`/`i_crtime`, `huge_file`, `dir_index` (lecture), blocs de 1 a 64 Ko, `sparse_super2`, orphelins, chargeur BOOT/ capable de lire ext3/ext4 : voir la section "Partie 37" |
| 38 | `/proc` et `/sys` complets, loop, PCI, SMP (detection), initramfs, minix/cramfs/romfs, effets de sysctl : `/proc/net/{tcp,udp,raw,unix,arp,snmp,sockstat,protocols}`, `/proc/{partitions,diskstats,devices,interrupts,ioports,iomem,vmstat,buddyinfo,misc,cgroups,tty/drivers,sysrq-trigger}`, `/proc/PID/{environ,limits,statm,comm,io,mountinfo,mounts,cgroup,oom_score,task,fdinfo/N,...}` + liens magiques (`fd/N`, `cwd`, `exe`, `root`), `/dev/loop0..15` + `/dev/loop-control` (`LOOP_*`), enumeration PCI (`/sys/bus/pci/devices`), detection ACPI MADT / tables MP et demarrage des processeurs secondaires a l'arret, inflate (deflate/zlib/gzip), initramfs cpio newc (module Multiboot, `initrd=` du chargeur), minix v1/v2/v3, cramfs, romfs (lecture seule), racine `vfat/iso9660/minix/cramfs/romfs` (`rootfstype=`), ASLR, overcommit, `kernel.panic`, SysRq |
| 39 | SMP reel sous un verrou noyau unique, `AF_NETLINK` (NETLINK_ROUTE), `AF_PACKET` : minuterie du LAPIC (100 Hz, etalonnee sur le PIT) et IOAPIC a la place des 8259 (surcharges de la MADT, repli sur les 8259 / `noapic`), processeurs secondaires qui executent des taches (GDT/TSS/pile/inactivite par CPU, `ScheduleSmp`, IPI de reordonnancement / de vidage de TLB / d'arret, atomiques `LOCK`), `sched_setaffinity` / `sched_getaffinity` / `getcpu` reels, `/proc/cpuinfo`, `/proc/stat` (`cpuN`), `/proc/interrupts` par CPU, `/sys/devices/system/cpu/online` ; virtio-net, virtio-blk, tueur OOM ; physiquement repartie : declarations precoces (partie 4), ordonnanceur (partie 8), traps (partie 16) et amorce des AP (partie 38) |
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
partie 35 (`i_size_high`, `large_file`) ; les attributs etendus et les ACL
sont geres (partie 33) ; ext3/ext4 (extents, journal, sommes de controle,
`64bit`, `meta_bg`, blocs jusqu'a 64 Ko) depuis la partie 37 : voir la section
correspondante pour les limites. Un repertoire indexe (`dir_index`) qu'on
modifie perd son index (le drapeau `INDEX_FL` est efface, comme ext2) ; pas
de quotas ; les copies de secours du superbloc et des descripteurs ne sont pas
mises a jour (comme le noyau Linux). Les acces au peripherique brut
`/dev/hdaN` (tampons de 1 Ko) ne sont pas coherents avec un ext2 de blocs de
2 Ko ou plus monte sur le meme disque.

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
* Ce que ce n'est pas : (avec un seul CPU) pas de verrous fins (le code noyau de deux
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

* `RUNK.SH` : 41 programmes embarques (dont `ext4test` et `jrntest`, qui ne font leurs essais de disque que sous `RUNEXT4.SH` et `RUNJRN.SH`), 849 verifications (dont `bigtest` et `modtest` des parties 35 et 36, qui ne font leurs essais de disque que sous `RUNBIG.SH` ; `ptracetest`, `seccomptest`, `xattrtest`, `nstest` des lots A2c/A2d ; `xattrtest` est aussi execute sur ext2 par `ext2test`)
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

### Partie 37 : ext3 et ext4 (lot C de D4)

Le code est dans la partie 18 (physiquement avant la partie 14) ; la couche
bloc (partie 11) ne change que pour les tampons de plus de 4 Ko
(`AllocPages(ordre)`), l'ecriture differee (`BufWrite` ignore un tampon de la
transaction du journal : drapeau `BvJrn`) et `BDirty`, qui fait entrer les
tampons de metadonnees dans la transaction. `mount -t ext2|ext3|ext4` est le
meme code.

**Fonctionnalites** (`ExParseSb`) : *incompat* reconnues : `filetype`,
`recover`, `meta_bg`, `extents`, `64bit`, `flex_bg`, `csum_seed`, `large_dir` ;
toute autre (compression, journal externe, `mmp`, `ea_inode`, `dirdata`,
`inline_data`, chiffrement, `casefold`) refuse le montage (`EINVAL`, message
dans dmesg). *ro_compat* ecriture : `sparse_super`, `large_file`, `btree_dir`,
`huge_file`, `gdt_csum`, `dir_nlink`, `extra_isize`, `metadata_csum`,
`project` ; les autres (quota, `bigalloc`, `replica`, `snapshot`...) montent
en lecture seule. *compat* : ignorees si inconnues (comme Linux). Une somme
de controle de descripteur de groupe fausse monte en lecture seule.

**Extents** : arbre de profondeur 0 a 5 dans l'inode (4 entrees) et dans des
blocs ; lecture ; ecriture (fusion avec l'extension voisine, division d'une
feuille, croissance de l'arbre quand la racine est pleine, index corriges
quand la premiere cle change) ; troncature (liberation par plages, noeuds
vides retires, profondeur ramenee a 0 si l'arbre est vide) ; extensions non
initialisees (`fallocate` de l'hote) lues comme des zeros et converties a
l'ecriture (division en trois). Valide par `e2fsck` sur des arbres de
profondeur 2 (700 extensions de 1 bloc, blocs de 1 Ko).

**Groupes** : descripteurs de 32 ou 64 octets (`64bit`, au plus 2^32 blocs),
`flex_bg`, `meta_bg` (emplacement des descripteurs et groupes de
sauvegarde), `sparse_super2`, `resize_inode` (conserve, pas de
redimensionnement), `uninit_bg` (bitmaps `BLOCK_UNINIT`/`INODE_UNINIT`
initialises au premier usage, `itable_unused` tenu a jour), blocs de 1 a 64 Ko
(les tampons de plus de 4 Ko sont des pages contigues), inodes de 128 a 1024
octets (256 octets conserves en memoire).

**Sommes de controle** (ecriture ; la lecture ne les verifie pas, sauf celle
des descripteurs au montage) : `GDT_CSUM` (crc16 du groupe) et `metadata_csum`
(crc32c : superbloc, descripteurs, bitmaps de blocs et d'inodes, inodes,
blocs de repertoire (queue de 12 octets), blocs d'extents, blocs d'attributs
etendus). Les repertoires et le journal sont refaits en consequence.

**Inodes etendus** : `i_extra_isize`, `i_crtime` pose a la creation (rendu par
`statx` : `stx_btime`, masque `STATX_BTIME`), `huge_file` (i_blocks en blocs
du systeme de fichiers), 16 bits de poids fort d'`uid`/`gid`.

**Repertoires** : lecture lineaire (un repertoire `htree` se lit comme un
repertoire ordinaire : ses noeuds d'index sont des entrees vides) ; la
premiere modification d'un repertoire indexe le remet a l'etat lineaire
(noeuds d'index reecrits en blocs vides, `INDEX_FL` efface) : `e2fsck`
l'accepte. La creation de repertoires indexes n'est pas faite. Entrees de
64 Ko (`rec_len` code sur 16 bits).

**Liste des orphelins** : un inode sans nom est chaine dans `s_last_orphan`
(par `i_dtime`) jusqu'a sa suppression ; au montage en ecriture, les inodes
orphelins laisses par un arret brutal (par Linux ou par ce noyau) sont
supprimes ou tronques.

**Journal jbd/jbd2** (`ExJrnLoad`, `ExJrnPass`, `ExJrnCommit`) :
* rejeu au montage (meme en lecture seule ; option `noload`/`norecovery`
  pour s'en abstenir : lecture seule) : trois passes comme `do_one_pass` de
  Linux (recherche de la fin, revocations, rejeu), blocs de description et de
  validation, revocations (32 ou 64 bits), blocs echappes, journal circulaire,
  etiquettes de 8, 10, 12, 14 et 16 octets (`64bit`, `CSUM_V2`, `CSUM_V3`),
  sommes de controle crc32c des descriptions, des blocs et des validations ;
  superbloc du journal v1 et v2 ; le rejeu refait lire le superbloc
  (`ExParseSb`) puis efface `needs_recovery` ;
* ecriture : tous les tampons de metadonnees modifies (bitmaps, descripteurs,
  superbloc, inodes, repertoires, extents, indirections, attributs) sont
  epingles dans la transaction courante et ne sont plus ecrits a leur place
  tant qu'elle n'est pas validee. Validation (`ExJrnCommit`) : mode
  `data=ordered` (defaut) : les tampons de donnees sont d'abord ecrits ;
  puis description + blocs + validation dans le journal, superbloc du journal
  (`s_start`), recopie des blocs a leur place (point de reprise), superbloc du
  journal vide. Declenchee par `sync`, `fsync`, demontage, remontage,
  `bdflush` (5 s), ou quand la transaction approche la moitie de la
  capacite. `data=writeback` : pas d'ecriture des donnees avant la validation.
  `data=journal` : refuse (`EINVAL`). `needs_recovery` est pose pendant le
  montage et efface au demontage. Limites : pas de revocations ni de sommes de
  controle ecrites (le journal est remis sans `CSUM_*` a la mise en service ;
  il est vide a ce moment), une transaction a la fois, journal interne
  seulement, pas de `fast_commit`, pas de journal circulaire reutilise (le
  journal est vide apres chaque validation) ;
* essais d'arret brutal : parametre `jcrash=N` (1 journal valide mais blocs
  non recopies, 2 transaction incomplete, 3 recopie a moitie, 4 recopie
  finie) : le noyau coupe la machine a cette etape.

**Chargeur (`BOOT/LOADER.PAS`)** : lit ext2, ext3 et ext4 : extents (arbre de
profondeur 3 au plus, extensions non initialisees lues comme des trous),
`64bit` (descripteurs de 64 octets), `flex_bg`, repertoires `htree`, inodes de
256 octets, blocs de 1 a 4 Ko ; un journal non rejoue est signale (le
noyau est lu tel quel sur le disque). Refuse : `meta_bg`, `inline_data`,
blocs de plus de 4 Ko, autres fonctionnalites incompatibles. L'installateur
et `mkfs.ext2` (E2) restent en ext2 sans journal.

**Essais** : `TESTS/K/RUNEXT4.SH [-n] [-b bloc] [-i inode] [-m Mo]` avec
`MKE_OPTS` (options de `mke2fs`, defaut `-t ext4`) : `MKEXT4.SH` fabrique le
disque (`/hdir` indexe par `e2fsck -D`, `/falloc.bin` a extensions non
initialisees par `debugfs fallocate`), `ext2test` (97 verifications) et
`ext4test` (37 a 40 : extensions non initialisees, arbre profond, troncature,
repertoire indexe, liens longs, `ENOSPC`, `statx`), puis `e2fsck -fn`.
Variantes validees : ext4 par defaut en 1/2/4/8/64 Ko, sans `metadata_csum`,
sans `64bit`, sans `flex_bg`, `meta_bg`, `sparse_super2`, inodes de 128/512,
ext3 (1 Ko et 4 Ko), ext4 sans journal, ext2 revision 0. Journal sale
fabrique par `debugfs` (`IMG_HOOK=TESTS/K/JHOOK.SH`, `JOPT=-c` pour les
sommes de controle) : quatre transactions dont une revocation.
`TESTS/K/RUNJRN.SH [-s files|orphan] [-S "0 1 2 3 4"]` : arret brutal a chaque
etape de la validation, nouveau demarrage (rejeu), verification de l'etat et
`e2fsck`. `TESTS/K/RUNBOOT4.SH [-o "options mke2fs"] [-N entrees]` : amorce
par le chargeur depuis une partition ext4.

### Partie 38 : /proc complet, loop, PCI, detection SMP (lot 1 et debut du lot 2 de D5)

**/proc/net** (generes depuis la table des sockets, colonne `inode` = numero
d'inode de la socket, le meme que celui de `fstat`) : `tcp` et `udp` (format
Linux : adresses/ports en hexadecimal, etat, files, uid, inode), `raw`, `unix`
(RefCount, Flags 00010000 si en ecoute, Type, St, inode, chemin ou `@abstrait`),
`arp` (cache ARP), `snmp` (Ip/Icmp/Tcp/Udp ; seuls `Forwarding`, `DefaultTTL`,
`InReceives`, `OutRequests` et `CurrEstab` sont reels, le reste vaut 0),
`sockstat`, `protocols`, plus `dev` et `route` deja la. `netstat`, `ss`, `lsof`,
`fuser` de `USR/PROCINFO.PAS` les lisent (verifie sous QEMU).

**/proc/PID** : `environ`, `limits` (RLIMIT_*), `statm`, `comm`, `io` (compteurs
a 0 : pas de comptabilite d'E/S par tache), `mountinfo`, `mounts`, `cgroup`
(`0::/`), `oom_score`, `oom_score_adj`, `wchan`, `loginuid`, `sessionid`,
`personality`, `fdinfo/N` (pos, flags octal, mnt_id, ino), `task/TID/...` (les
threads du groupe ; l'inode de `task/TID` est celui de `/proc/TID`), `status`
complete (`Threads`, `SigQ`, `SigIgn`, `SigCgt`, `Cap*`). `/proc` ne liste plus que
les chefs de groupe (les threads restent accessibles par `/proc/TID` et
`task/`). **Liens magiques** : `fd/N`, `cwd`, `exe`, `root` sont suivis jusqu'a
l'objet (`stat("/proc/self/fd/3")` rend l'inode du fichier, du tube ou de la
socket ; `open` d'un tube par ce chemin rejoint le tube) ; `readlink` rend le
chemin, `socket:[n]`, `pipe:[n]` ; `ns/*` ne sont pas suivis.

**Haut de /proc** : `partitions`, `diskstats` (compteurs reels de lectures /
ecritures / secteurs par disque et partition, tenus dans `BlkRW`), `devices`,
`interrupts` (compteur par IRQ), `ioports`, `iomem` (carte E820), `vmstat`,
`buddyinfo`, `misc`, `cgroups` (en-tete seul : pas de cgroups), `tty/drivers`.

**Peripheriques loop** (`/dev/loop0..7` crees au demarrage, `/dev/loop-control`
10:237, jusqu'a 16 peripheriques) : `LOOP_SET_FD`, `CLR_FD`, `SET_STATUS(64)`,
`GET_STATUS(64)`, `CHANGE_FD` (lecture seule), `SET_CAPACITY`, `SET_DIRECT_IO`
(accepte), `SET_BLOCK_SIZE`, `CONFIGURE`, `LOOP_CTL_ADD/REMOVE/GET_FREE`. Offset et
`sizelimit` sur 64 bits, drapeau lecture seule (ecriture refusee `EPERM`,
`EROFS` a l'ecriture differee), fichier de support ordinaire ou peripherique bloc.
`mount -t ext2 /dev/loop0` marche (le cache de tampons est vide au `SET_FD`,
ecrit et vide au `CLR_FD`) ; `CLR_FD` et le changement d'offset refusent `EBUSY`
si le loop est monte. **Limites** : pas de chiffrement (`lo_encrypt_type` != 0 :
`EINVAL`), `AUTOCLEAR` et `PARTSCAN` memorises mais sans effet (pas de comptage
des ouvertures), pas de `/sys/block/loopN/loop/*` ni de taille dans `/sys`.
`BLKROGET`, `BLKFLSBUF` (vide vraiment) et `BLKSSZGET` ajoutes aux
peripheriques blocs.

**PCI** : enumeration du bus 0 et des ponts (jusqu'a 32 fonctions, taille des
BAR mesuree a l'amorce avant les pilotes) ; `/sys/bus/pci/devices/0000:BB:DD.F/`
{`vendor`, `device`, `class`, `revision`, `subsystem_*`, `irq`, `uevent`,
`resource` (7 lignes ; drapeaux approximatifs), `config` (256 octets)}.
`/sys/bus/usb/devices` existe mais est vide : aucun controleur USB n'est gere.

**SMP (detection seulement)** : ACPI (RSDP, RSDT/XSDT, MADT : CPU, IOAPIC,
adresse LAPIC) avec repli sur les tables MP ; LAPIC mappe, identite du BSP lue ;
chaque processeur secondaire est reveille (INIT + 2 SIPI, trampoline 16 bits en
2000h, pagination du noyau) puis **reste arrete (HLT)**. L'ordonnanceur, les
verrous et les interruptions restent mono-processeur (PIC 8259, verrou unique) :
`/proc/cpuinfo`, `sched_getaffinity` et `/sys/devices/system/cpu/online` ne
declarent que le CPU 0 ; `present`, `possible`, `offline` et `cpuN/online` (=0)
decrivent les autres. Option `nosmp` : detection sans demarrage des
processeurs. Valide sous `qemu -smp 1/2/4` (ACPI) ; le repli MP n'est valide
que structurellement (QEMU sans ACPI ne publie qu'un CPU).

**Piege du compilateur (trouve ici)** : un appel dont deux arguments `String`
sont des concatenations (`F(A + B, X, C + D)`) corrompt le premier : copier les
arguments dans des variables avant l'appel. Le code de `PopulateSys` le faisait :
`/sys/block/*/dev`, `size`, `partition`, `/sys/class/block/*` et
`/sys/class/{mem,tty}/*/dev` etaient absents ou faux (corrige, teste).

Tests : `proc2test` (~90 verifications), `looptest` (~45), `smptest` (9) dans
RUNK ; `TESTS/K/RUNLOOP.SH` (ext2 dans un fichier ext2, `e2fsck` du disque et des
deux images). `RUNK.SH` accepte `QX="-smp 4"` (options QEMU supplementaires).

**Initramfs** : un module Multiboot (`qemu -initrd a,b,...`, ou `initrd=/boot/initrd.img`
dans `/boot/linux0.cfg` pour le chargeur de `BOOT/`, fichier place juste apres le
noyau, sous 16 Mo ; `TOOLS/MKIMAGE.SH -I`) est extrait dans la racine en memoire
avant le demarrage : cpio newc brut, gzip (inflate de la partie 38, algorithme de
puff), gzip + cpio concatenes, plusieurs modules (jusqu'a 4). Fichiers (modes
complets, setuid, proprietaire, date), repertoires (parents absents crees), liens
symboliques, liens physiques (`nlink` > 1, meme inode), noeuds de peripheriques,
tubes nommes. Les pages du module sont rendues au noyau apres l'extraction. Si
`/init` (ou `rdinit=`) existe, il devient le processus 1 et la racine reelle
`root=` n'est pas montee d'office (a lui de monter puis `chroot`/`pivot_root`) ;
sinon la suite est inchangee. Limites : pas de bzip2/xz/lzma/lz4/zstd (module
refuse, message), pas de `/dev/initrd` (ancien initrd image), le chargeur ne lit
que ext2/3/4.

**minix, cramfs, romfs** (lecture seule, une seule serie d'operations `RoXxx`) :
minix v1/v2/v3 (noms de 14, 30 ou 60 octets ; zones directes, indirectes, double
et triple ; blocs de 1 Ko verifies, 2 a 4 Ko non testes), cramfs (pages zlib de 4 Ko,
trous, blocs non compresses ; sans les drapeaux `DIRECT_PTR`/XIP), romfs (liens
durs, peripheriques, bit d'execution). Montage par `mount -t minix|cramfs|romfs`
ou comme racine (`root=/dev/hdX`, `rootfstype=` facultatif : sans lui le noyau
essaie ext2, vfat, iso9660, minix, cramfs, romfs). Un systeme de fichiers racine en
lecture seule doit contenir les repertoires `/dev`, `/proc`, `/sys`. NON FAIT :
squashfs, overlayfs, minix en ecriture, `mkfs`.

**Effets de sysctl** (reste stocke sans effet : `vm.swappiness`, `net.ipv4.ip_forward`,
`kernel.printk`, ...) : `kernel.randomize_va_space` (defaut 2 : sommet de pile et base
des `mmap` randomises ; le tas ne l'est pas), `vm.overcommit_memory` (0 refuse une
demande plus grande que RAM + swap ; 1 toujours ; 2 somme des espaces d'adressage
<= swap + RAM x `overcommit_ratio`/100 ; `MAP_NORESERVE`, `PROT_NONE` et
`MAP_SHARED` ne comptent pas), `kernel.sysrq` (defaut 1) avec `/proc/sysrq-trigger`
(`b o s u e i m t h c 0-9`, masque `kernel.sysrq` respecte), `kernel.panic` (et le
parametre `panic=N` : redemarrage N secondes apres une panique). `/proc/sys/kernel/sysrq`
et la touche SysRq du clavier : la touche n'est pas branchee.

Tests (suite) : `RUNINITRD.SH` (raw, gzip, 2 modules, gzip+raw, amorce par le
chargeur sur disque), `RUNRO.SH` (cramfs via `mkfs.cramfs` de l'hote, minix
5 variantes validees par `fsck.minix`, romfs par `MKROFS.PY`, ~140 verifications),
`RUNROOT.SH` (racine ext2, vfat, iso9660, minix, cramfs, romfs), `RUNPANIC.SH`,
`effects` (ASLR, overcommit, sysrq) dans RUNK.

### Partie 39 : SMP reel sous le verrou noyau unique (lot 1 de D6)

**Ce qui est fait et prouve (QEMU `-smp 1/2/4`)** :

* **LAPIC + IOAPIC** (`ApicInit`, apres la MADT) : quand la MADT annonce un
  IOAPIC, les 8259 sont coupes ; la minuterie 100 Hz est celle du LAPIC
  (vecteur 32, etalonnee sur 10 ms de la voie 2 du PIT) ; les IRQ ISA/PCI sont
  routees par l'IOAPIC vers les memes vecteurs `32 + IRQ` (les pilotes ne
  changent pas), en tenant compte des surcharges de la MADT (IRQ0 -> GSI 2,
  IRQ 5/9/10/11 sensibles au niveau) ; l'accuse de reception est l'EOI du
  LAPIC ; `IrqEnable/IrqDisable` agissent sur le masque de l'entree IOAPIC (sous
  `IoapLock`). Repli sur les 8259 sans IOAPIC, si l'etalonnage echoue ou avec
  `noapic`. Les IRQ de peripheriques vont toutes au BSP.
* **Processeurs secondaires** : INIT + SIPI (partie 38), puis chaque AP monte
  sa GDT et son TSS (`CpuGdt/CpuTss`, car les descripteurs TLS sont par CPU),
  active son LAPIC, sa minuterie et ses registres FPU/SSE, et entre dans la
  boucle d'inactivite (`IdleLoopSmp`, HLT). Une tache d'inactivite par CPU
  (`ApIdleTask`, pile du noyau propre).
* **Verrou noyau unique** (`BklOwner`, tache qui le detient) : le code du noyau
  (appels systeme, exceptions, traitements differes des IRQ) ne s'execute que
  sous ce verrou ; le mode utilisateur s'execute en parallele sur tous les CPU.
  Une tache prend le verrou a chaque entree depuis le mode utilisateur
  (`BklAcquireSmp` : attente active `LOCK CMPXCHG`, qui sert les demandes de
  vidage de TLB pendant l'attente) et le rend au retour (`ReturnToUserSmp`).
  `ScheduleSmp` (verrou detenu) choisit parmi les taches ordonnables qui ne
  tournent sur aucun autre CPU (`OnCpu`) et dont l'affinite (`Affinity`)
  autorise ce CPU, et **transmet le verrou** a la tache choisie. Les IRQ ne font
  que la partie haute sans verrou (accuse, comptage, comptabilite de la tranche
  de la tache du CPU : `DoIrqSmp`) ; le traitement differe (`RunBH`) est fait
  par celui qui rend le verrou. Les fils crees en SMP demarrent par
  `SmpChildEntry` (le verrou leur est transmis). **Le noyau n'est pas
  preemptible en mode SMP** (`kpreempt` P = 0 dans `/proc/stat`) : la preemption
  du noyau (partie 27) reste utilisee avec un seul CPU ; une tache en mode noyau
  garde le verrou jusqu'a ce qu'elle dorme ou revienne au mode utilisateur.
* **IPI** (vecteurs F0h reordonnancement, F1h vidage de TLB, F2h arret, FFh
  parasite) : `KickIdleCpu` reveille un CPU inactif quand une tache devient
  ordonnable ; `TlbShoot(Mm)` (munmap, mprotect, copie sur ecriture, fork,
  ecriture forcee de ptrace) vide la TLB des autres CPU qui executent l'espace
  `Mm` et attend leur accuse ; `SwapReclaim` ignore les espaces d'adressage
  charges sur un autre CPU ; une panique arrete les autres CPU.
* **Affinite et observation** : `sched_setaffinity` / `sched_getaffinity` /
  `getcpu` reels (`EINVAL` pour un masque vide ou hors CPU en ligne, `EPERM`
  pour un tiers non privilegie), `/proc/cpuinfo` (un bloc par CPU),
  `/proc/stat` (`cpu0..cpuN` : user/system/idle par CPU), `/proc/interrupts`
  (une colonne par CPU, `LOC`, `RES`, `TLB`), `/sys/devices/system/cpu/{online,
  offline,cpuN/online}`, ITIMER_VIRTUAL/PROF pour la tache de chaque CPU.
* Options : `nosmp` (detection sans demarrage, un seul CPU), `noapic` (8259 ;
  un seul CPU executant des taches).

**Pieges rencontres (utiles aux suites)** : (1) un IOAPIC **perd les fronts**
qui arrivent sur une ligne sensible au front et masquee (contrairement a un
8259 qui les memorise) : la partie haute d'une IRQ ne masque donc que les
lignes sensibles au niveau (`IrqDefer`, `ApicLevel`) ; avant ce correctif la
souris PS/2 (3 octets, une IRQ chacun) perdait ses 2e et 3e octets en SMP ;
(2) le compteur de tranche ne doit jamais devenir negatif (`Counter Shr 1`
d'un negatif donne 2^31-1 : tache jamais elue) ; (3) sous QEMU/TCG,
l'instruction `PAUSE` d'une boucle d'attente retarde le processeur qui fait
des E/S : les attentes actives utilisent `NOP` ; (4) `SwapReclaim` reprend aussi
les pages d'un espace charge sur un autre CPU (page retiree des tables, TLB
videe par IPI, puis ecriture sur le swap).

**Ordre des verrous** : `BklOwner` > `IoapLock` (registres de l'IOAPIC, IF
masque). Les structures `PendIrq` / `TickPend` sont modifiees par des
instructions `LOCK` / `XCHG`. Aucun autre verrou : le verrou fin par
sous-systeme est la suite (non fait).

**Limites** : verrou unique donc pas d'acceleration du code noyau (seul le mode
utilisateur est parallele) ; pas de migration equilibree (choix glouton au
premier CPU qui ordonnance) ; IRQ de peripheriques sur le BSP uniquement ; pas
de preemption du noyau en SMP ; bits accedes/modifie des PTE modifies sans
verrou par le materiel pendant que le noyau les reecrit (perte possible de ces
bits pour un espace partage entre CPU) ; `mprotect(PROT_NONE)` laisse la page
lisible (limite anterieure, identique en monoprocesseur) ; pas de x2APIC, pas
de hotplug.

**AF_NETLINK (NETLINK_ROUTE)** (`NlSend`, `SOCK_RAW` ou `SOCK_DGRAM`,
protocole 0 ; les autres protocoles repondent `EPROTONOSUPPORT`) : `bind` /
`getsockname` (`sockaddr_nl`), `RTM_GETLINK` (liste complete ou un lien par
numero ou par `IFLA_IFNAME` : nom, type, drapeaux, MTU, adresse MAC, file,
etat), `RTM_GETADDR` et `RTM_GETROUTE` (listes, fin `NLMSG_DONE`),
`RTM_NEWADDR` / `RTM_DELADDR` (adresse et masque de eth0), `RTM_NEWROUTE` /
`RTM_DELROUTE` (route par defaut), `RTM_NEWLINK` (`IFF_UP` de eth0 ; un MTU
different de 1500 : `EINVAL`), acquittements `NLM_F_ACK`, erreurs
`NLMSG_ERROR` (`ENODEV`, `EOPNOTSUPP`, `EEXIST`, `EPERM` hors root, ...). Les
reponses sont des datagrammes de 3,5 Ko au plus dans la file de la socket
(poll/select/recvmsg habituels). Limites : pas de groupes multicast
(`RTMGRP_*` : aucune notification), un seul lien Ethernet, pas de routes autres
que la route du reseau de eth0 et la route par defaut, pas de NETLINK_*
autres que ROUTE. **AF_PACKET** (`SOCK_RAW` : trame complete, `SOCK_DGRAM` :
sans l'en-tete Ethernet, protocole `ETH_P_ALL` ou un type precis, root
seulement) : `bind` (`sockaddr_ll`, interface 0/1/2), `getsockname`,
emission d'une trame brute ou d'une charge avec en-tete ajoute (adresse MAC de
destination dans `sockaddr_ll`), reception de toutes les trames de eth0 avec
`sockaddr_ll` (type de paquet : hote, diffusion, multicast, autre, emis) et
copie des trames emises (`PACKET_OUTGOING`, pas pour l'emetteur lui-meme),
comme `tcpdump` ou un client DHCP brut. Limites : seulement eth0 (RTL8139) ;
pas de `PACKET_MMAP`, de filtres BPF (`SO_ATTACH_FILTER`), de mode
promiscuite ni de `/proc/net/packet`.

**virtio-net** (`VnInit`, carte PCI 1AF4:1000 de QEMU, interface "legacy" a
ports d'E/S ; `-nic user,model=virtio-net-pci`) : files 0 (reception, 64
tampons de 2 Ko recycles par la partie differee de l'IRQ) et 1 (emission, 8
tampons), adresse MAC lue dans la configuration, entete virtio de 10 octets nul
(pas de somme de controle ni de segmentation deleguees, pas de
`VIRTIO_NET_F_MRG_RXBUF`, pas de file de controle). Cherchee apres le RTL8139 ;
toute la pile reseau, `AF_PACKET` et `AF_NETLINK` s'appliquent sans changement.
Limites : un seul peripherique reseau a la fois ; pas de virtio moderne
(1AF4:1041), pas de MSI-X, pas de multifile. `RUNNET.SH` avec
`NICMODEL=virtio-net-pci` rejoue les essais reseau reels.

**virtio-blk** (`VblkProbe`, `VblkRW` ; 1AF4:1001, `-drive if=virtio`) :
disque d'index 4 de la couche IDE (arrays `DiskPresent..PartSize` etendus),
majeur 253, `/dev/vda` et `/dev/vda1..15` (table de partitions MBR lue comme
celle des disques IDE, logiques comprises), `/proc/partitions`, `/proc/diskstats`,
`/sys/block/vda`, `root=/dev/vda1`. Une requete a la fois (entete, tampon de
128 secteurs au plus, octet d'etat), attente par scrutation de l'anneau
"utilise" sous le verrou noyau (interruptions du peripherique supprimees par le
drapeau `NO_INTERRUPT` de l'anneau). Option `novirtio` : ne pas le chercher.
Limites : legacy seulement (pas de virtio 1.0), un seul disque virtio, pas
de `BLK_F_FLUSH` / multifile / `DISCARD`, capacite limitee a 2^31-1 secteurs,
le chargeur `BOOT/` n'amorce pas depuis virtio (BIOS) ; `RUNVBLK.SH`.

**Tueur OOM** (`OomKill`, `AllocUserPage`) : quand une page utilisateur ne
peut plus etre allouee (apres reprise de pages / swap), la tache de plus grand
nombre de pages residentes (processus entier ; ni init ni thread du noyau ni
tache deja condamnee) recoit `SIGKILL` (tout son groupe de threads), le journal
indique "Out of memory: Killed process N (nom) rss K kB", `/proc/vmstat` compte
`oom_kill`, et la tache fautive attend (5 fois 3 ticks au plus) que les pages
soient rendues avant d'echouer. `vm.panic_on_oom` non nul : panique du noyau.
Limites : le score est le nombre de pages residentes seulement (pas de
`oom_score_adj`, d'enfants, de swap, de cgroup) ; seules les fautes de page
(zero, copie sur ecriture, relecture du swap) passent par le tueur, pas les
allocations du noyau.

Tests : `nltest` (17 verifications, 25 avec une carte reseau ; RUNK), `oomtest` (8 ; RUNK), `idetest` (5 verifications + 3 pour vda1 ; RUNVBLK.SH : virtio seul, avec un disque IDE, racine `/dev/vda1`, `e2fsck`, contenu relu par `debugfs`), le bloc `pkt.*` de `nettest` (15, avec RUNNET.SH), `smptest` (14 verifications, 20 avec plusieurs CPU : sysfs/proc, affinite, getcpu, chaque CPU
execute une tache epinglee, parallelisme mesure par les ticks `cpuN`, vidage de
TLB prouve par SIGSEGV d'un thread d'un autre CPU apres `mprotect` ;
temoin negatif : sans l'IPI le test echoue), toute la suite RUNK sous
`-smp 2` et `-smp 4`, les autres suites sous `-smp 2` (voir STATUS.md).

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
independants), SMP, FAT comme racine, creation de repertoires `htree`, DHCP/DNS dans
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

`install [-d disque] [-l FR|EN|GR|SP|IT] [-s Mo] [-r racine] [-b 1024|2048|4096]
[-I 128|256] [-N inodes] [-y] [-q]` :
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
`mkfs.ext2 [-b taille] [-I inode] [-N inodes] [-s Mo] peripherique` (meme
programme, autre nom) formate sans partitionner. Lot E3 : `-b` (1 Ko par
defaut, 2 Ko, 4 Ko : premier bloc de donnees 0 et superbloc dans le bloc 0 a
partir de 2 Ko, i_blocks en secteurs de 512 octets, indirections a BS/4
entrees), `-I 256`, `-N` (nombre total d'inodes, arrondi a un bloc de table
par groupe) ; `e2fsck -fn` de l'hote propre pour les six combinaisons 1/2/4 Ko
x 128/256 (mkfs sur 40 Mo, install d'une racine de 35 Mo sur 100 Mo,
`TESTS/U/RUNU.SH utils`). Verification : `e2fsck -fn` propre (3 Mo a 300 Mo essayes ;
fichiers de 40 Mo, 300 entrees de repertoire, liens, tubes). Limites : disque
de 2 Go au plus (blocs de 1 Ko ; 8 Go a 4 Ko), 4000 entrees par repertoire,
une seule source (`/` en cours d'execution ou `-r dossier`), ext2 seulement
(pas de journal : mkfs.ext3 et mkfs.ext4 ne sont pas ecrits, le chargeur lit
ext3/ext4 mais l'installateur ne les cree pas). Essai : `TESTS/U/RUNU.SH
install`
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

### Lot E3 : outils, compilateur, auto-hebergement (agent E3)

`USR/` compte 77 programmes. Nouveaux (un programme peut servir plusieurs
noms, lu dans `argv[0]` ; `BUILD.SH` cree les liens) :

| Programme | Noms | Remarques |
|-----------|------|-----------|
| `VI.PAS` | vi view vim | editeur modal : hjkl w b e W B E 0 ^ $ f F t T ; , % { } G gg H M L, Ctrl-F/B/D/U, i a I A o O R r s S C cw cc, x X dd D d{mvt} y p P J ~ > <, `.`, u, / ? n N * (regex), `:w :q :wq :x :q! :e :r :N :d :y :m :t :j :s///g :g :v :set :!`, marques, objets iw aw. 95 essais sur pty (`TESTS/U/vitest.py`). Un registre, annulation a une etape, lignes de 255 octets |
| `LESS.PAS` | less more | pagineur (fichiers ou tube, clavier sur /dev/tty), recherche regex avec mise en relief, -N -S -i, :n :p, v |
| `MAN.PAS` | man info apropos whatis | formateur roff (macros man), pages dans `/usr/share/man/<langue>/manN` puis `manN`, pagineur `$PAGER`, -k -f -w ; pages `USR/ROOTFS/usr/share/man/man1` generees par un script |
| `TEXTUTIL.PAS` | wc head tail cut paste | filtres compares a coreutils (47 cas) ; remplacent les versions du depot (qui ne lisaient pas un tube) |
| `CRON.PAS` | crond cron crontab at atd batch atq atrm | crontab (listes, pas, noms, @reboot...), spool `/var/spool/cron/crontabs`, travaux at `/var/spool/cron/atjobs`, journal `/var/log/cron.out` ; crond et atd lances par `/etc/rc` |
| `PATCH.PAS` | patch | formats unifie, contexte, normal ; decalage, fuzz 0-2, .rej, -R, -p, -b, --dry-run ; 714 essais contre `diff` (`TESTS/U/patchtest.py`) |
| `CPIO.PAS` | cpio | newc et odc (-o -i -t -p), interoperable avec un lecteur/ecrivain newc independant ; liens physiques ecrits en copies |
| `ZIPTOOL.PAS` | zip unzip zipinfo | ZIP stocke et deflate (inflate complet, deflate LZ77 + Huffman fixe), CRC-32 ; interoperable avec Info-ZIP dans les deux sens |
| `E2FSCK.PAS` | e2fsck fsck fsck.ext2/3/4 | verification ext2/3/4 en lecture seule (blocs mappes et extents), sortie identique a `e2fsck -fn` sur 28 cas (images saines ext2 1 Ko et 4 Ko, corrompues par debugfs), `TESTS/U/e2fsckcmp.sh` ; fsck choisit fsck.TYPE d'apres /etc/fstab |
| `PROCINFO.PAS` | lsof fuser netstat ss lspci lsusb losetup | lisent /proc, /sys, ioctl LOOP_* ; voir "Demandes au noyau" |
| `NETUTIL.PAS` | telnet ftp httpd traceroute | telnet (IAC), ftp passif, httpd statique, traceroute UDP/ICMP ; essais sur l'hote (httpd/curl, ftp contre un serveur de test, traceroute 127.0.0.1) |
| `UDHCPC.PAS` | udhcpc dhclient | DHCP par diffusion UDP (une negociation), configure ifconfig/route/resolv.conf ; non verifie sous QEMU si le noyau refuse la diffusion depuis 0.0.0.0 (etape net de RUNU : SKIP) |
| `IPTOOL.PAS` | ip | `ip addr|link|route [show|add|del|set]` par ioctl (pas de netlink) |

Essais : `TESTS/U/RUNU.SH` (etapes `utils` sur l'hote et `tools` sous QEMU :
`/usr/share/bench/tools.sh`). Non faits : cron.daily/weekly, xz/lzma,
ftp mget/mput, bash-isms (tableaux, `[[ ]]`, `{1..n}`,
substitution de processus) dans `/bin/bash`, loadkeys/terminfo/zoneinfo,
job control teste sur pty, mkfs.ext3/ext4. Le compilateur (voir
`TOOLS/LPC.TXT`, "Ajouts du lot E3") gagne : tableaux ouverts, pointeurs de
procedures complets, reels au format Turbo Pascal, Insert tronque, Move de
litteral, ModuleInit (EAX := 0), noms de modules en minuscules, erreur sur
homonymes variable/procedure.

Demandes au noyau (D4) : `/proc/net/tcp`, `/proc/net/udp`, `/proc/net/unix`
(netstat, ss, lsof -i), `/proc/PID/fd` avec liens `socket:[n]`, `/dev/loop*`
et `/dev/loop-control` avec LOOP_* (losetup), `/sys/bus/pci/devices`,
`/sys/bus/usb/devices` (lspci, lsusb), AF_NETLINK (ip natif), AF_PACKET
(DHCP), `/proc/partitions`. Voir BUGS_NOYAU.md.

### Lot E4 : mkfs ext3/ext4, montages, bash, xz, terminal, espaces de noms

`USR/` compte 82 programmes. Noyau d'essai : `D/backup-38.PAS`.

**Compilateur (`TOOLS/LPC32.PAS`)** : les temporaires `String` de l'operateur
`+`, de `Copy` et de `Concat` sont rendus dans l'anneau `STRRING` (256
tampons) au lieu d'un tampon unique `STRBUF1` : `F(A+B, x, C+D)`,
`G(A+B, B+C, C+A)`, `G(Copy(..), Copy(..), ..)`, `(A+B) < (B+C)` et les
appels imbriques sont corrects (cause du `lsof` a une lettre et du piege
signale par D5 ; le noyau n'est plus concerne). `Delete(S, Pos, Len)` borne
`Pos` et `Len` par la longueur (avant : lecture au-dela de la chaine, d'ou
des chaines corrompues dans `read` du shell). `{$I fichier}` absent : erreur
nette au lieu d'une boucle ou d'un plantage. Tests : `TESTS/C/UX7`, `UX8`.

**mkfs.ext3 / mkfs.ext4 / mke2fs (`USR/INSTALL.PAS`)** : `-t ext2|ext3|ext4`
(ou le nom du programme), `-O fonctions` (`extents flex_bg 64bit
metadata_csum uninit_bg dir_index has_journal huge_file dir_nlink
extra_isize large_file ext_attr none`, `^nom` pour retirer), `-J size=Mo`
(minimum 1024 blocs), `-j`, `-L nom`, `-m pct`, `-b -I -N` (arguments
colles acceptes : `-b4096`). Journal jbd2 interne (inode 8, sauvegarde dans
le superbloc), extents (arbre de profondeur 0 ou 1), groupes flex (taille
adaptee a la table d'inodes), 64bit (descripteurs de 64 octets),
metadata_csum (crc32c : superbloc, descripteurs, bitmaps, inodes, repertoires
avec enregistrement final, blocs d'extents), uninit_bg (crc16, indicateurs
INODE_UNINIT/BLOCK_UNINIT/ITABLE_ZEROED), inodes de 256 octets
(`extra_isize`, `crtime`). L'installateur accepte les memes options
(`install -t ext4 ...`). Verifie par `e2fsck -fn`, `dumpe2fs`, `debugfs
rdump` de l'hote sur 13 combinaisons (RUNU `utils`), et sous QEMU : disque
installe en ext4 (extents, flex_bg, journal) puis en ext4 4 Ko
`metadata_csum,64bit`, amorce par le chargeur, ecriture, `e2fsck -fn`
propre ensuite. Non fait : resize_inode, repertoires htree, bigalloc,
quotas, `tune2fs`, `dumpe2fs`, `resize2fs`.

**Montages** : `MOUNT.PAS` (`-t -o -a -L -U -r -w -v -f`, `--bind --rbind
--move`, options ro rw remount noatime relatime nosuid nodev noexec sync
dirsync loop loop=/dev/loopN offset= sizelimit= defaults noauto nofail x-*,
le reste va au noyau comme `data=`, fstab complet : `mount DIR`, `mount -a`,
UUID=/LABEL=, type lu dans le superbloc ou essai des types, fichier ordinaire
monte par un peripherique de boucle autoclear), `UMOUNT.PAS` (`-a -l -f -r
-d`, libere la boucle), `SWAPON.PAS` (`-a` lit fstab, `-p`, UUID/LABEL),
`FSINFO.PAS` (`df -hHkmPTia -t -x`, `blkid -s -o -t -L -U`, `lsblk -flnab
-o`, `findmnt -nlfsT -t -o -S -M`) et `FSPROBE.INC` (ext2/3/4, FAT,
iso9660, minix, cramfs, romfs, swap). Sous QEMU : mkfs.ext4 sur un fichier,
`mount -o loop`, ecriture, `df`, `findmnt`, `blkid`, `lsblk`, `--bind`,
`remount,ro`, `umount`, libere la boucle, `mount -a` depuis fstab.

**bash (`/bin/bash` = `USR/SH.PAS` appele `bash`)** : le meme interpreteur,
en mode bash quand `argv[0]` est `bash` (`sh` reste POSIX : 5/5 contre dash).
Tableaux indexes et associatifs (`a=(..)`, `a[i]=`, `+=`, `${a[@]}`,
`${#a[@]}`, `${!a[@]}`, tranches, indices negatifs, `unset a[i]`, `declare
-a -A -p`, `read -a`, `mapfile`), `[[ ]]` (motifs, `=~` avec
`BASH_REMATCH`, `-v`, `&& || ! ( )`), `(( ))`, `for ((;;))`, arithmetique
complete (affectations, `++ --`, `?:`, `,`, `**`, bases, court-circuit),
`let`, accolades `{a,b}` `{1..10..2}` `{a..e}` `{01..10}`, `${v^^ ,, ^ ,
@Q @U @L / // /# /%  :off:len  !ref  !prefixe*}`, `$'..'`, `<<<`, `&>`,
`<(cmd)` `>(cmd)`, `select`, `case ;& ;;&`, extglob `@() ?() *() +() !()`,
`shopt` (extglob nullglob dotglob failglob nocasematch), `set -o pipefail`,
`PIPESTATUS`, `trap ERR/DEBUG/RETURN/EXIT`, `declare/typeset/local/readonly`
avec `-i -l -u -r -x -n -a -A`, namerefs, `printf` interne (`-v`, `%q %b`),
`pushd popd dirs`, `FUNCNAME`, `BASH_VERSION`, `BASH_VERSINFO`, `LINENO`,
`SECONDS`, `HOSTNAME`... Essais : `TESTS/U/bashtest.sh` (6 scripts compares
a GNU bash 5.2). Limites : mots de 255 caracteres, 1500 variables, `export
-f` et `declare -f` (corps) absents, completion programmable (`complete`,
`compgen`) en coquilles vides, pas de `coproc`, `wait -n`, `${v@a}`.

**Autres programmes** : `XZ.PAS` (xz unxz xzcat lzma unlzma lzcat : lecture
.xz LZMA2 avec CRC32/CRC64 et flux concatenes, .lzma ancien ; ecriture .xz
(LZMA gourmand, CRC64) relue par `xz -d` de l'hote ; `-k -c -t -l -f`),
`NSTOOLS.PAS` (chroot unshare nsenter pivot_root switch_root setpriv),
`TPUT.PAS` (tput clear reset infocmp tset : terminaux linux vt100 vt220 xterm
xterm-256color ansi screen, sequences identiques a ncurses pour les
capacites courantes ; base integree, pas de fichiers `/usr/share/terminfo`),
`SUDO.PAS` (sudo visudo : `/etc/sudoers` utilisateur/%groupe/ALL, runas,
NOPASSWD, `!authenticate`, `-u -n -l -U -i -s`, mot de passe verifie dans
`/etc/shadow`, `sudo` installe setuid root ; `visudo -c -f` controle la
syntaxe ; aliases non geres).

**Non fait** : loadkeys/dumpkeys, fichiers terminfo et zoneinfo, `date -d`
avec fuseaux, ed complet/nano, logrotate, rdate, strace,
tcpdump, iptables, cron.daily, job control verifie sur pty, `bc`/`dc`
complets, nouveaux appels de `L32API.PAS`.

