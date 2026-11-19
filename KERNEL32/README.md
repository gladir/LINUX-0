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

**CD-ROM d'installation** : amorce El Torito (`BOOT/STAGE2CD.ASM`, `TOOLS/MKCD.SH`, `TOOLS/MKINITRD.PY`, `RUNCD.SH`) : voir `BOOT/README.md`, section "Amorce depuis CD-ROM". Le noyau accepte un initramfs sans `/init` mais avec `/sbin/init`.

**Framebuffer** (`/dev/fb0`, carte Bochs/QEMU VGA ; `fb=LxH[xP]` ou `vga=0x31B...`
(tableau des modes VESA 640x480 a 1280x1024, 8/16/32 bits) a l'amorce, ou a chaud) :
`/dev/fb0` existe des que la carte est la, le mode graphique n'est programme que
sur demande. `FBIOPUT_VSCREENINFO` change de mode a chaud (320x200 a 2560x1600,
profondeurs 8, 16 (565), 24, 32 ; `yres_virtual` > `yres` ; `FB_ACTIVATE_TEST`
verifie sans changer ; `EINVAL` si le mode ne tient pas dans les 16 Mo de
memoire video, `fbmem=N` Mo pour une carte plus petite), `FBIOGET_VSCREENINFO`
(champs de couleur exacts selon la profondeur), `FBIOGET_FSCREENINFO` (pas de
ligne, `smem_len`, visuel TRUECOLOR/PSEUDOCOLOR), `FBIOPAN_DISPLAY` (decalage
du pave visible), `FBIOGETCMAP/PUTCMAP` (palette du DAC en 8 bits), mmap partage de toute la
memoire. `KDSETMODE` : `KD_GRAPHICS`/`KD_TEXT` (`KDGETMODE`) ; `KD_TEXT` ramene le mode
texte VGA (registres du mode 3, polices et palette sauvegardees avant le
premier mode graphique, console redessinee). Verifie par captures d'ecran
QEMU (`RUNFB.SH` : 8 captures, pixels exacts dans chaque mode, texte revenu en
720x400). Limites : pas de double tampon, pas de blanking (`FBIOBLANK` sans
effet), la lecture de l'index `VIDEO_MEMORY_64K` de la carte fait avorter QEMU
(taille fixee a 16 Mo), sur BIOS reel il n'y a pas de VBE du chargeur.

**Entrees** : `/dev/input/event0` (clavier) et `event1` (souris), `struct
input_event` de Linux i386 (16 octets), `EVIOCGVERSION/GID/GNAME/GPHYS/GBIT/
GKEY/GRAB`, lecture bloquante ou `O_NONBLOCK`, `poll` ; clavier : `EV_KEY` avec
codes Linux (touches etendues E0 : fleches, Inser/Suppr/Debut/Fin..., Alt
Gr, pave numerique), appui 1, relachement 0, repetition 2 ; souris :
`REL_X`, `REL_Y` (positif vers le bas), `REL_WHEEL` (IntelliMouse negociee au
demarrage, identifiant 3), `BTN_LEFT/RIGHT/MIDDLE`, `EV_SYN`. `KDSKBMODE`
`K_RAW` (octets de balayage bruts, prefixes E0/E1 compris) et `K_MEDIUMRAW`
(code de touche, bit 7 = relachement) sur la console active, `KDGKBMODE` ;
`/dev/input/mice` reste en protocole PS/2 a 3 octets. Limites : un seul clavier
et une seule souris, pas de LED, pas de `EVIOCSREP`, le mode clavier est global
(pas restaure a la fermeture), pas de `/proc/bus/input/devices`. Verifie par
injection QEMU (`sendkey`, `mouse_move` avec molette) : `RUNMOUSE.SH`.

**Partitionnement** (disques IDE et vda) : `BLKRRPART` (relit la table :
`EBUSY` si une partition est montee, `EACCES` hors root, `EINVAL` sur une
partition ; vide et invalide les tampons, recree les noeuds `/dev/hdXN` et
`/sys/block/hdX/hdXN/{dev,size,start,partition}`, supprime ceux des partitions
disparues), `BLKPG` (`ADD_PARTITION`, `DEL_PARTITION`, `RESIZE_PARTITION`,
chevauchement et bornes verifies), `HDIO_GETGEO` (255 tetes, 63 secteurs,
`start` de la partition), `BLKGETSIZE/SIZE64`. **GPT** lue (MBR de protection
EEh, en-tete `EFI PART` du secteur 1, jusqu'a 15 entrees, LBA 32 bits, sommes
de controle non verifiees). Le secteur 0 et les secteurs 1 a 2047 s'ecrivent par `/dev/hdX`
(tampons de 1 Ko, `sync`). Verifie par `RUNPART.SH` (MBR : ecriture de la table
par le programme, `BLKRRPART`, `BLKPG`, retour de la table d'origine, montage
ext2 apres chaque etape, `e2fsck` propre ; GPT : montage). Limites : pas
d'ecriture GPT par le noyau (c'est l'installateur), une table logique
etendue n'est lue qu'en MBR, secteurs > 2^32 non geres.

**Divers [E4]/[E5]** : `LOOP_CLR_FD` s'accepte sur une ouverture en lecture seule
(`losetup -d`) ; `LO_FLAGS_AUTOCLEAR` (flag 4) libere la boucle a l'`umount` ;
`mount --bind` apparait dans `/proc/mounts` (`rw,bind`) ; le cache de tampons
a un maximum reglable `bufmax=N` (essais sous pression : `RUNLOOP.SH` avec
`KARGS=bufmax=100` passe ; le defaut de reentrance de `BufShrink` n'a pas pu
etre reproduit sans le correctif avec ce parametre, la garde `ShrinkBusy`
reste la correction par construction). Non fait : rouvrir un tube par
`/proc/self/fd/N`.

**Materiel reel / VirtualBox (lot D7-1)** : **AHCI/SATA** (`AhciProbe`, classe
01:06:01 : ICH9 de QEMU, defaut de VirtualBox) : ABAR mappe en FAC00000h,
interruptions coupees, une commande a la fois par DMA (READ/WRITE DMA EXT 48
bits, IDENTIFY, paquets ATAPI) ; disques `/dev/sdX` (majeur 8, 16 mineurs,
partitions MBR/GPT comme les autres disques), lecteurs `/dev/srN` (majeur 11)
et lien `/dev/cdrom` ; `/proc/partitions`, `/sys/block`, `BLKRRPART`,
`BLKPG` comme pour hdX ; emplacements de disque 5 a 8, option `noahci`. Pas
d'interruption, pas de NCQ, pas de port multiplicateur, une seule commande en
vol. **e1000** (Intel 82540EM/82545EM/82543GC : la carte par defaut de
VirtualBox et de `qemu -device e1000`) : anneaux de 32 descripteurs de
reception et 8 d'emission, IRQ, MAC lue dans les registres ; pas de
somme de controle ni de segmentation deleguees ; PCnet (AMD 79C970A) non fait.
**VBoxVGA** (PCI 80EE:BEEF, registres Bochs VBE 1CEh/1CFh) reconnue comme la
carte Bochs : taille du BAR mesuree decodage coupe, et un mode que la carte ne
prend pas (relecture de `xres`, `yres`, bit d'activation) est annule avec retour au
texte VGA (`FbSetMode` rend `ENODEV`) ; **non teste** (QEMU n'a pas cette
carte). **ACPI** : FADT (PM1a_CNT_BLK, SMI_CMD, registre de reinitialisation)
et objet `\_S5_` de la DSDT pour l'arret (activation ACPI si necessaire),
reinitialisation par le registre ACPI, sinon 0CF9h, 8042, triple faute ;
`noportoff` : aucun autre moyen d'arret (essais) ; `RUNPOWER.SH` vert sous
QEMU (arret par PM1a 0604, redemarrage). LAPIC/IOAPIC/minuterie : repli sur
les 8259 si l'etalonnage echoue (non teste sous NEM/Hyper-V). Tests : `RUNAHCI.SH`
(disque ext2 sur AHCI seul puis avec un disque IDE, e2fsck, contenu relu,
`root=/dev/sda1`), `RUNCD.SH` (3e essai : CD sur AHCI, `/dev/sr0`),
`RUNNET.SH` avec `NICMODEL=e1000`, `RUNPOWER.SH`.
QEMU ajoute par defaut une carte e1000 : sans option, le noyau voit maintenant
une carte reseau (`socktest` en tient compte).

**Verrous et pare-feu (lot D7-2)** : les appels systeme sans etat partage
(`getpid`, `gettid`, `getuid` et famille, 16 et 32 bits) sont traites a
l'entree du noyau sans le verrou noyau (`FastSyscall`, dans `KTrapSmp` ;
`nofastsys` sur la ligne de commande les remet sous verrou ; ligne `fastsys N`
de `/proc/stat`) ; le CPU courant se lit dans le registre TR (chaque processeur
a son descripteur de TSS dans sa propre GDT, 8 processeurs au plus) et non plus
dans le LAPIC (un acces MMIO serialise les CPU sous QEMU). Mesure sous QEMU
(`smptest`) : 300000 `getpid` en 300 ms sur un CPU, 460 ms sur deux ; sous le
verrou, 60 ms pour 30000 `getppid` sur un CPU et 600 a 880 ms sur deux. Les
verrous fins par sous-systeme (VFS, memoire, ordonnanceur, reseau) ne sont **pas
faits** : tout le reste passe encore par le verrou noyau unique. **Filtre
IP minimal** (`NfEval`) : table `filter` de l'ABI iptables (`IPT_SO_SET_REPLACE`,
`GET_INFO`, `GET_ENTRIES` par `setsockopt/getsockopt` sur un socket brut
protocole 255), chaines INPUT (a la reception, avant ARP) et OUTPUT (avant
l'emission), regles sur adresses source/destination avec masque et
inversion, interfaces, protocole, ports TCP/UDP, cibles ACCEPT et DROP,
compteurs d'octets et de paquets, politique par defaut ; `root` seulement.
La table `nat`, la chaine FORWARD (pas de routage), les modules d'etat
(`conntrack`) et `REJECT`/`LOG` ne sont pas faits (`ENOPROTOOPT`/`EINVAL`).
Tests : `smp.fastsys_*` (smptest), `nf.*` (12 verifications de `nettest`,
RUNNET.SH avec rtl8139, virtio-net et e1000).
**Claviers chargeables** : `KDGKBENT`/`KDSKBENT` (0x4B46/0x4B47) sur
`/dev/ttyN` (struct kbentry `{table, index, valeur 16 bits}`, tables normale /
Maj / AltGr, `EINVAL` hors limites, `EPERM` sans CAP_SYS_TTY_CONFIG) et touches
mortes (valeur 0x500 + n : grave, aigu, circonflexe, tilde, trema ; combinaison
avec a e i o u y n selon le cas, espace ou deux fois la meme touche donne le
signe seul, autre caractere : le signe puis le caractere). Les tables sont des
mots de 16 bits. `loadkeys` d'USR/ peut donc remplir les tables au demarrage ;
`keymap=XX` de la ligne de commande reste limite a us et fr. Test :
`mousetest` (RUNMOUSE.SH, 9 verifications dont `sendkey` a e / a espace / a a).
Le mode du clavier (`KDSKBMODE`) est maintenant propre a chaque console
(remis en XLATE a la fermeture du dernier descripteur, comme Linux) et
`/dev/console` suit la **derniere** option `console=` de la ligne de commande
(`console=tty0 console=ttyS0` : port serie). Tests : `devtest` (4
verifications), `k32conmark`.

**Affichage : VMware SVGA II / VMSVGA (lot D7-4)** : le controleur par defaut
des invites Linux de VirtualBox 7 (PCI 15AD:0405, `-vga vmware` sous QEMU) est
pris en charge par la couche `/dev/fb0` existante : negociation `SVGA_REG_ID`
(version 2), mode par `WIDTH/HEIGHT/BITS_PER_PIXEL/ENABLE`, `BYTES_PER_LINE`
et `FB_OFFSET` relus, memoire video BAR 1 (16 Mo au plus), FIFO BAR 2 initialisee
(min 1200, max = taille, `CONFIG_DONE`). L'hote ne redessine qu'apres une
commande `UPDATE` : `FbTick` en pousse une pour l'ecran entier a 20 Hz tant que
`/dev/fb0` est ouvert ou a ete mappe, et a chaque changement de mode. Limites
de la carte : 32 bits seulement (8/16/24 : `EINVAL`), pas d'ecran virtuel ni de
panoramique (la hauteur virtuelle demandee est ramenee a la hauteur), le retour
au texte (`KD_TEXT`, `ENABLE=0` puis registres VGA) est identique a Bochs.
Choix de la carte : Bochs/VBoxVGA (1234:1111, 80EE:BEEF) puis VMware SVGA II ;
sinon texte seul. Messages du noyau (journal, donc `dmesg`) : `fb: PCI VGA
00:02.0 15AD:0405` pour chaque carte de classe affichage, `fb: carte VMware
SVGA II 15AD:0405 detectee (...)` ou `fb: aucune carte compatible, texte seul` ;
les memes informations sont dans `/proc/fb` (ligne Linux `0 VMWARE SVGA II` puis
lignes `# fb:` et `# pci`) et `/sys/class/graphics/{info,fb0/{name,dev,info}}`.
Teste sous QEMU : `VGA=vmware ./RUNFB.SH -n` (captures d'ecran exactes en
1024x768, 800x600, 1280x1024, retour au texte 720x400, mmap) et `RUNFB.SH`
(Bochs) restent verts. **Non teste** : VirtualBox lui-meme (ni VMSVGA ni
VBoxVGA : ports, taille de la FIFO et rafraichissement a verifier).

**VirtualBox : couts de VM-exit, VMMDev, inventaire (lot D7-11)** : sous
Hyper-V/NEM chaque acces de port ou de registre d'un peripherique emule coute
un VM-exit. Mesure sous QEMU (`-trace cpu_in,cpu_out,memory_region_ops_*`,
`TESTS/K/RUNPERF.SH`) : le demarrage faisait **1 280 000 acces** (1 200 000
lectures du port 80h) a cause de `AtapiCapacity` qui attendait 4 x 300 000
lectures par lecteur de CD vide (celui que VirtualBox presente toujours) ; il
n'en fait plus que **76 000** (-94 %) : REQUEST SENSE (« pas de support » =
abandon immediat) et attente de 3 000 lectures. Au repos : ~0 acces par
seconde (hors LAPIC, que QEMU ne trace pas). Souris : IRQ 12 draine tous les
octets disponibles d'un coup (moins d'interruptions et d'EOI par paquet) ;
`MemFill` ecrit par mots de 32 bits ; frequence des UPDATE VMware reglable
(`fbupd=N` ticks, 5 par defaut). `/proc/k32perf` : totaux et taux par seconde
des interruptions, EOI LAPIC/8259, acces 8042 clavier/souris, registres SVGA,
UPDATE, Ko ecrits dans /dev/fb0, lectures CMOS, appels KLog, ticks (et
compteurs VMMDev). **Pilote VMMDev** (PCI 80EE:CAFE : ES de requete BAR 0,
memoire BAR 1, IRQ) : ReportGuestInfo/2, ReportGuestStatus, filtre d'evenements,
SetMouseStatus (`GUEST_CAN_ABSOLUTE` ; `vboxcursor=1` ajoute
`NEEDS_HOST_CURSOR`), GetMouseStatus et AcknowledgeEvents sur IRQ ou, par
securite, a chaque tick ; positions rendues sur `/dev/input/event2`
(« VirtualBox mouse integration », EV_ABS ABS_X/ABS_Y de 0 a 65535, boutons
repris du PS/2, EVIOCGABS) ; `/dev/input/mice` et PS/2 intacts ; messages
`vbox: ...` au demarrage ; option `novbox`. **Prouve seulement contre une
simulation logicielle** (`k32vboxfake=1`, position par
`/proc/sys/k32/vbox_sim_x|y`, `RUNVBOX.SH`) qui verifie la structure des
requetes (taille, version 10001h, type, rc) comme je la connais des en-tetes de
VirtualBox ; **jamais teste contre VirtualBox** (valeurs de types, taille des
requetes et ordre des operations a verifier avec le journal `vbox:`).
`FBIOGET_FSCREENINFO` : `line_length` est maintenant a l'offset 44 (Linux) et
reste recopie a 48. `e2fsck-lite` : limite portee a 524288 inodes.
En mode graphique le noyau n'ecrit plus dans la memoire VGA texte (B8000h,
MMIO : un VM-exit par ecriture ; `VgaHidden`) : la console texte vit dans
`VcBuf` et est redessinee au retour en KD_TEXT ou en panique.

**VirtualBox : VMMDev et USB sont ETEINTS par defaut (lot D7-13)** : le
premier essai sous VirtualBox 7.0.6 (backup-65) a fait disparaitre le pointeur :
annoncer des « Guest Additions » (ReportGuestInfo + GUEST_CAN_ABSOLUTE) fait
passer l'hote en souris absolue et cacher son pointeur, et rien ne le
remplacait cote invite. Par defaut le noyau n'envoie donc plus rien a VMMDev et
ne touche pas au controleur OHCI : la souris est la PS/2 (`/dev/input/mice`,
event1), comme avant. Activation : ligne de commande `vboxga=1` / `usb=1`, ou a
chaud depuis un shell (Alt+F2) : `echo 1 > /proc/sys/k32/usb_enable` et
`echo 1 > /proc/sys/k32/vbox_enable` (0 : arret, la PS/2 redevient la seule
source). VMMDev annonce NEEDS_HOST_CURSOR : le pointeur de l'hote reste visible
(`vboxcursor=0` pour le retirer). `/dev/input/event2` n'annonce EV_ABS qu'apres
le premier rapport VALIDE (VMMDev ou tablette USB, la premiere reste la source ;
GUEST_CAN_ABSOLUTE n'est plus jamais retire par precaution). `/proc/k32input` :
etat des sources (PS/2, VMMDev, USB, tuyaux, compteurs) ; `dmesg` : lignes
`usb:` / `vbox:` (descripteurs, 5 premiers rapports en hexadecimal, diagnostic
automatique « aucun rapport recu » 3 s puis 20 s apres l'activation avec l'etat
brut des ED/TD/HCCA). `usbpoll=1` : sans IRQ (surveillance par le tick).
Raison reelle de la regression : inconnue (aucun journal du noyau cote
VirtualBox) ; les hypotheses sont dans REPONSES_D7.md.

**USB OHCI + HID, curseur materiel VMSVGA (lot D7-12)** : VirtualBox
presente par defaut un controleur OHCI et une *tablette USB* comme pointeur.
`UsbInit` detecte le controleur par sa classe PCI (0C0310), mappe ses
registres (BAR 0, FC000000h), prend la main sur le BIOS, le reinitialise
(HCR) et le met en USBRESET ; le fil noyau `kusbd` laisse 60 ms de
reinitialisation du bus, passe en operationnel (liste de controle + liste
periodique, IRQ WDH/RHSC/UE), alimente les ports, puis enumere chaque
peripherique (reinitialisation du port, SET_ADDRESS, descripteurs, chaine du
produit, SET_CONFIGURATION, interfaces HID). Branchement/retrait a chaud
(interruption RHSC, repli par un balayage toutes les 20 s). Hub externe,
stockage, UHCI/EHCI/xHCI : non geres (journal `usb: ... non gere`). Entrees :
clavier de boot (usages HID -> codes de balayage de l'ensemble 1 -> `KbdScan`,
le meme chemin que le PS/2 : consoles, Alt+Fn, KbMode ; repetition par le tick,
500 ms puis 33 Hz) ; souris relative (descripteur de rapport analyse ->
`MousePacket` : `/dev/input/event1` et `/dev/input/mice` comme le PS/2) ;
tablette absolue (axes X/Y absolus, boutons, molette) sur `/dev/input/event2`
(EV_ABS ABS_X/ABS_Y ramenes a 0..65535, BTN_LEFT/RIGHT/MIDDLE, REL_WHEEL ;
nom lu dans le descripteur de chaine, ex. « QEMU USB Tablet » ; bustype USB).
**Source unique** : la premiere source qui livre un rapport absolu valide
(tablette USB ou VMMDev) alimente event2 (`AbsSrc`), l'autre se tait (plus
d'emission de SetMouseStatus sans GUEST_CAN_ABSOLUTE) ; le PS/2 relatif reste
sur `/dev/input/mice` dans tous les cas. Les rapports arrivent par
la file des TD termines du HCCA (en memoire) : au repos aucun acces de registre
hors le balayage des ports ; ~2 acces de registre par rapport (lecture de
`HcInterruptStatus` quand l'IRQ est redoublee + acquittement) contre ~16 pour
une souris PS/2 (mesure QEMU : 3,0 puis 2 apres l'optimisation du cas courant).
`/proc/k32perf` : `ohci_reg_access`, `usb_reports`. Journal `usb: ...`
(controleur, ports, descripteurs, interfaces, champs HID, trois premiers
rapports de chaque tuyau en hexadecimal) : a me rapporter depuis VirtualBox.
Option `nousb`. `TESTS/K/RUNUSB.SH` (QEMU, `-device pci-ohci` avec usb-tablet,
usb-kbd, usb-mouse ; evenements par QMP) verifie l'enumeration, la tablette
(position, coins, boutons, molette, EVIOCGABS/EVIOCGNAME/EVIOCGID), le clavier
(event0, tty, repetition), la souris (event1, mice), la priorite sur VMMDev
(simulation) et le branchement/retrait a chaud. **Non teste sur VirtualBox**
(descripteurs de la tablette VirtualBox analyses « sur le papier » : rapport de
7 octets, X/Y 0..7FFFh). Curseur materiel VMSVGA pour Graph (ioctl de
`/dev/fb0`) : `FBIO_K32_UPDATE` 46F0 (rectangle ; le premier appel passe en
mode manuel : plus d'UPDATE periodique tant que le fichier est ouvert),
`FBIO_K32_CURDEF` 46F1 (curseur ARGB jusqu'a 64x64, SVGA_CMD_DEFINE_ALPHA_CURSOR),
`FBIO_K32_CURMOVE` 46F2 (position : FIFO CURSOR_BYPASS_3 sans VM-exit si
l'hote l'annonce, sinon registres CURSOR_*) ; -ENOTTY hors VMware SVGA ; la voie
CURSOR_BYPASS_3 n'est pas prouvable sous QEMU (compteurs `cursor_fifo_moves` /
`cursor_reg_moves`). `poll()`/`select()` sur les evenements d'entree sont
reveilles directement par l'IRQ (plus d'attente complete d'un tick de 10 ms).

**Bureau : CD, consoles, souris (lot D7-10)** : (1) `CDROMEJECT` (5309h),
`CDROMCLOSETRAY` (5319h), `CDROM_LOCKDOOR` (5329h) et `CDROM_DRIVE_STATUS`
(5326h) sur `/dev/hdc`, `/dev/sr0` (ATAPI IDE ou AHCI) : PREVENT/ALLOW MEDIUM
REMOVAL puis START STOP UNIT (LoEj) ; `RUNCD.SH` (trois montages) verifie par
le moniteur QEMU que le plateau est ouvert apres l'ejection. (2) Consoles :
`KDSETMODE` est maintenant propre a chaque console, `VT_SETMODE`/`VT_GETMODE`
(`VT_PROCESS` : signal de liberation `relsig` quand la console graphique
cede l'ecran, `acqsig` quand elle le reprend ; le noyau n'attend pas
`VT_RELDISP`), `Alt+F1..F4` et `VT_ACTIVATE` depuis une console en
`KD_GRAPHICS` : retour au texte VGA (720x400) puis, au retour, mode graphique
retabli (l'ecran est efface : le programme se redessine sur `acqsig`) ; la
fermeture du dernier descripteur d'une console graphique rend le texte (pas
d'ecran noir sans issue) ; la console texte n'ecrase pas le framebuffer (verifie
par capture). `/dev/input/mice` : protocole ImPS/2 (sequence F3 C8 F3 64 F3 50
ecrite sur le fichier, acquittements FA, identifiant F2, paquets de 4 octets
avec molette), PS/2 de 3 octets par defaut. `poll`/`select` marchent sur evdev,
`/dev/input/mice`, `ptmx` et ttys (attente par pas de 10 ms, sans boucle
active) ; `FIONREAD` du maitre pty, `TIOCSWINSZ`/`TIOCGWINSZ` pty, `TIOCSCTTY`,
`TIOCNOTTY` existent. Tests : `RUNVT.SH` (`vttest`, std et `VGA=vmware`, captures),
`RUNMOUSE.SH` (`mice.*`), `RUNCD.SH`. **Non fait** : tablette/pointeur absolu
(il faudrait USB ou vmmouse), attente de `VT_RELDISP`, mmap de /dev/fb0 non
essaye sous Hyper-V/VirtualBox (attributs de cache des pages), 4 consoles
seulement.

**NVMe (lot D7-9)** : controleur PCI 01:08:02 (QEMU `-device nvme`) :
registres BAR 0 mappes en FB800000h, file d'administration et une paire de files
d'E/S de 16 entrees creees par les commandes Create I/O CQ/SQ, Identify de
l'espace de noms 1 (secteur logique de 512 octets seulement), lecture/ecriture
par PRP1/PRP2 ou liste de PRP (128 Ko par commande), une commande a la fois en
scrutation avec delai, Flush a `sync` et a l'arret. Disque `/dev/nvme0n1`
(majeur 259, partitions `nvme0n1p1`..15 dans `/dev`, `/proc/partitions`,
`/sys/block`), table de partitions MBR/GPT lue comme pour sdX ; option
`nonvme`. `RUNNVME.SH` : ext2 monte, lu, ecrit (idetest), e2fsck et contenu
relu par debugfs, racine `root=/dev/nvme0n1p1`, disque creux de 8 Go avec
acces a 2 Gio, 4 Gio et en fin de disque (bdtest). Non fait : interruptions
(MSI-X), plusieurs files ou commandes en vol, espaces de noms autres que le
premier, plusieurs controleurs, secteurs de 4096 octets, TRIM, `nvme0n1p1`
dynamique au-dela de 15 partitions ; les listes de PRP ne sont pas prouvees
par un test dedie (le bloc n'emet peut-etre que de petits transferts).

**Correctif VirtualBox : formatage d'un disque de 8 Go (lot D7-8)** :
l'installateur annoncait « le formatage plante a 3 % » sur un disque de 8 Go.
Reproduit sous QEMU (`ich9-ahci`, disque creux de 8 Go, 1024 Mo) avec le vrai
CD d'installation : `mkfs.ext4 -b 4096 /dev/sda1` rendait 1 en 3 s avec
`Erreur : lseek`. **Cause : `USR/INSTALL.PAS` calculait les decalages d'ecriture
sur 32 bits (`PartStart * 512 + Blk * BS`) et utilisait `lseek` 32 bits : toute
partition de plus de 2 Gio echouait au premier bloc au-dela** ; ni le noyau ni
le pilote AHCI n'etaient en cause (`bdtest` : ecriture/lecture a 2 Gio, 4 Gio et
en fin de disque par `_llseek`, vert). Corrige dans `INSTALL.PAS`
(`WriteAtS` : decalage de 64 bits par `SysLLSeek`). Installation complete
verifiee (`TESTS/K/RUNINSTAHCI.SH` : CD, preseed, ext4 de 7935 Mo + swap de
256 Mo sur AHCI, 1024 Mo, 1 CPU, `e2fsck -fn` propre ; `mkfs.ext4` seul : 14 s).
Durcissement du pilote AHCI : delais en microsecondes (plus de boucles
comptees), erreurs `PxIS` (TFES, HBFS, HBDS, IFS, INFS, OFS, IPMS) detectees,
message `ahci: port N erreur is=.. tfd=.. serr=.. cmd=.. ci=.. ssts=..` puis
la commande (code, LBA, nombre, tampon) dans le journal (dmesg), remise en
etat du port (arret, effacement, CLO, COMRESET), nouvel essai, FLUSH CACHE EXT
a `sync` et a l'arret ; `RUNAHCIERR.SH` (erreur injectee par blkdebug) :
journal, reprise et donnees correctes. **Panique visible** : `KPanic`
repasse l'ecran en mode texte VGA et affiche la console 0 (le framebuffer
cachait le message ; `RUNPANIC.SH` verifie une capture 720x400 non noire apres
une panique avec `fb=1024x768`). Non reproduit : tout comportement propre a
VirtualBox/NEM (pas de KVM ici : seulement TCG), disques qcow2 (pas de
`qemu-img`), NCQ.

**cgroups v2 minimaux (lot D7-7)** : systemes de fichiers `cgroup2` (et
`cgroup`, meme implementation) a monter par `mount -t cgroup2 none
/sys/fs/cgroup` ; `mkdir` cree un groupe avec `cgroup.procs`,
`cgroup.controllers` (`cpu memory pids`), `cgroup.subtree_control`,
`pids.max`, `pids.current`, `memory.max`, `memory.current`, `cpu.weight`
(16 groupes au plus, hierarchie par `mkdir` imbriques, `rmdir` : `EBUSY` s'il
reste des taches ou des sous-groupes). Ecrire un pid dans `cgroup.procs`
deplace le processus (tous ses threads) ; l'enfant d'un processus du groupe en
fait partie ; `/proc/PID/cgroup` donne `0::/chemin`. Application :
`pids.max` (`fork`/`clone` : `EAGAIN` au-dela, comptage du sous-arbre),
`memory.max` (nombre ou `max`, suffixes k m g : une page utilisateur de plus
que le sous-arbre ne peut en avoir tue la tache fautive par SIGKILL avec le
message `Memory cgroup out of memory`), `cpu.weight` (1 a 10000, 100 par defaut :
la tranche de temps est proportionnelle, mesure 400 contre 100 : 4,3 fois plus de
ticks sur un meme CPU). Ecriture reservee a root ; creation d'autres fichiers :
`EPERM`. Test : `cgtest` (25 verifications, avec RUNK). **Non fait** :
cgroups v1 (controleurs separes, `tasks`, `cpuacct`), `memory.high/low/swap`,
`cpu.max`, `io.*`, `cgroup.events`, delegation, `cgroup.threads`, comptabilite
d'utilisation cpu, `/proc/cgroups` a jour.

**IPv6 de base (lot D7-6)** : (1) `AF_INET6` pour TCP et UDP sur la pile
IPv4 : une socket `socket(AF_INET6, SOCK_STREAM|SOCK_DGRAM)` accepte les
adresses `::1` (127.0.0.1), `::` et `::ffff:a.b.c.d` (adresse IPv4 mappee, donc
joignable sur eth0 comme en IPv4) ; `getsockname`, `getpeername`, `accept`,
`recvfrom` et `recvmsg` rendent des `sockaddr_in6` (127.0.0.1 est rendu `::1`) ;
toute autre adresse IPv6 : `ENETUNREACH`. (2) Sur eth0, vraie pile IPv6
minimale : adresses `fe80::` (lien) et `fec0::` (prefixe du reseau utilisateur
de QEMU) en EUI-64, decouverte de voisins (NS/NA, cache de 4 entrees), echo
ICMPv6 (reponse et requete), passerelle `fec0::2`, sockets brutes
`socket(AF_INET6, SOCK_RAW, IPPROTO_ICMPV6)` (root ; le noyau calcule la
somme de controle), `/proc/net/if_inet6`. Tests : `socktest` (`in6.*`, 15,
avec RUNK) et `nettest` (`ip6.*`, 5 : ND + echo vers fec0::2 de QEMU, avec
RUNNET.SH sur les quatre cartes). **Non fait** : TCP et UDP sur le fil
IPv6 (l'hote d'essai n'a pas d'IPv6), retransmission et routage IPv6,
fragmentation, options d'extension, annonces de routeur, `/proc/net/ipv6_route`,
`getaddrinfo` cote L32API, IPv6 sur tun/tap.

**PCnet** (AMD 79C970A/973, PCI 1022:2000 : carte de VirtualBox, `-nic
user,model=pcnet` sous QEMU) : mode 32 bits (DWIO, SWSTYLE 2), anneaux de 32
descripteurs de reception et 8 d'emission, interruptions ; RUNNET.SH vert avec
`NICMODEL=pcnet` (toute la suite `net.*`, `nf.*`, `tun.*`, `nat.*`).

**tun/tap, routage, retransmission, NAT (lot D7-3)** : `/dev/net/tun`
(`TUNSETIFF`, IFF_TUN et IFF_TAP, IFF_NO_PI, nom donne ou `tunN`/`tapN`, 2
interfaces au plus ; l'interface disparait a la fermeture), configuration
par les ioctl d'interface (`SIOCSIFADDR`, `SIOCSIFNETMASK`, `SIOCSIFFLAGS`,
`SIOCGIFHWADDR`, `SIOCGIFINDEX`...). tap : trames Ethernet, ARP repondu par
le noyau, requetes ARP emises sur le tap ; tun : paquets IP seuls. La
couche IP route par sous-reseau d'interface (sur le lien) puis par la
passerelle d'eth0 ; `net.ipv4.ip_forward` autorise la retransmission d'une
interface a l'autre (TTL decremente, erreurs ICMP temps ecoule et reseau
inaccessible). **Netfilter** : tables `filter` (INPUT, FORWARD, OUTPUT, cibles
ACCEPT, DROP, REJECT avec code ICMP, LOG dans le journal du noyau) et `nat`
(PREROUTING, INPUT, OUTPUT, POSTROUTING : SNAT, DNAT, MASQUERADE, REDIRECT),
suivi de connexions de 64 entrees (TCP, UDP et echo ICMP, duree 5 min) avec
traduction des reponses et recalcul des sommes de controle ; l'interface
reste celle d'iptables (`setsockopt`/`getsockopt` SOL_IP sur un socket brut
protocole 255). Tests (`nettest`, RUNNET.SH) : `tun.*` (14), `tap.*` (9),
`nat.*` (12) : MASQUERADE d'un hote derriere tun0 vers l'hote QEMU et retour,
DNAT en sortie avec adresse de reponse retablie, REJECT, LOG. **Non fait** : voir la fin du paragraphe.

Complements (D7-5) : la connexion TCP d'un hote derriere tun0, traduite par
MASQUERADE (SYN, SYN-ACK, donnees, sommes recalculees) est testee
(`nat.tcp_*`) ; **netlink** (`RTM_GETLINK/GETADDR/GETROUTE`, `RTM_NEWADDR/DELADDR`,
`RTM_NEWLINK` pour l'activation) et `/proc/net/dev`, `/proc/net/route` voient
les interfaces tun/tap ; **pont** (`SIOCBRADDBR/DELBR/ADDIF/DELIF`, ports tap,
adresse IP possible sur le pont, table d'adresses de 16 entrees apprise sur les
trames recues, diffusion des destinations inconnues et des diffusions,
remise locale a la pile IP) ; 4 interfaces tun/tap/pont au plus. Tests :
`nltest` (`nl.tap_*` 9, `br.*` 12, avec RUNK), `RUNNET.SH` utilise des ports
aleatoires pour l'hote (`k32netp=`) afin que des essais simultanes ne se
heurtent pas. **Non fait** : eth0 comme port de pont, STP, filtrage de pont,
suivi d'etat TCP, fragmentation, `conntrack` dans /proc, `-m state`, mangle,
fichiers /sys/class/net/tapN, IPv6.

**Noyau de production** : `TOOLS/MKPROD.SH [-o NOYAU.ELF]` compile
`KERNEL32.PAS` sans les programmes de test embarques (2,6 Mo contre 3,4 Mo ; le
reste est de la memoire initialisee a zero que le compilateur ecrit dans le
fichier) ; `RUNCD.SH` l'utilise. **Corrections issues de BUGS_NOYAU.md [E4]** :
`BufShrink/BufReclaim` non reentrants (Oops sous pression du cache avec un
peripherique de boucle), `/dev/fd`, `/dev/stdin|stdout|stderr` (liens vers
`/proc/self/fd`), `Name:` des threads du noyau (`kthread`, `bdflush`), `mount`
d'une source inexistante : `ENOENT`, le bloc `--- taches` n'est plus ecrit
sans `debug` sur la ligne de commande.

Tests : `nltest` (17 verifications, 25 avec une carte reseau ; RUNK), `oomtest` (8 ; RUNK), `parttest` (RUNPART.SH), `fbtest` (+ 22 verifications de modes) et `mousetest` (+ 20 : evdev, clavier brut), `idetest` (5 verifications + 3 pour vda1 ; RUNVBLK.SH : virtio seul, avec un disque IDE, racine `/dev/vda1`, `e2fsck`, contenu relu par `debugfs`), le bloc `pkt.*` de `nettest` (15, avec RUNNET.SH), `smptest` (14 verifications, 20 avec plusieurs CPU : sysfs/proc, affinite, getcpu, chaque CPU
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


## CD-ROM d'installation (agent E5) : `USR/INSTALLER/`, `TOOLS/MKINSTALLCD.SH`

`BUILD.SH cd` (ou `TOOLS/MKINSTALLCD.SH`) fabrique `IMAGE/KERNEL32-INSTALL.ISO`,
un CD-ROM amorcable (El Torito, chargeur `BOOT/STAGE2CD.BIN`) qui lance un
**assistant d'installation graphique** : langue, clavier, fuseau horaire, date et
heure, nom de la machine, comptes, disque, partitionnement (assiste ou manuel),
points de montage, recapitulatif, installation, fin et redemarrage. Il installe
KERNEL32 (noyau, systeme complet, chargeur) sur un disque IDE/virtio.

### Contenu du CD et fonctionnement

| fichier du CD | role |
|---|---|
| `/boot/linux0`, `/boot/linux0.cfg` | noyau de production (`TOOLS/MKPROD.SH`), `console=tty0 console=ttyS0 fb=1024x768 rw` |
| `/boot/initrd.img` | systeme "live" (cpio gzip) : meme racine que le systeme installe + `/sbin/k32-setup` ; `init` lance `k32-setup-run` sur tty1, `getty` sur tty2, tty3 et ttyS0 (shell de secours : `root`/`root`) |
| `/system.tar` | archive tar GNU (modes, proprietaires, liens, `setuid`) de la racine du systeme a installer (rootfs de `BUILD.SH` + `/usr/share/zoneinfo`) |
| `/README.TXT`, fichiers ajoutes par `-r` | par exemple `preseed.cfg` |

`MKINSTALLCD.SH [-o ISO] [-R racine] [-k noyau.elf] [-r dossier] [-c cmdline]` : sans `-R`
il appelle `BUILD.SH` (`ROOTONLY=1`) ; sans `-k` il compile le noyau de production
de `KSRC` (defaut `KERNEL32.PAS`). `genisoimage` requis (voir `TOOLS/MKCD.SH`).
Le live a besoin de 128 Mo de RAM au moins (racine de ~13 Mo en memoire + tampon
d'image 3 Mo).

### Interface (`GFX.INC`, `UIBASE.INC`, `WIDGETS.INC`, `INPUT.INC`)

* **Bibliotheque graphique** (`GFX.INC`, utilisable par tout programme `-3X`) :
  `GOpen(L, H)` ouvre `/dev/fb0` (ioctl `FBIOPUT_VSCREENINFO` 32 bits, `mmap`,
  `KD_GRAPHICS`), un tampon hors ecran 0x00RRGGBB (`GBack`), primitives
  `GPix GFillRect GHLine GVLine GFrame GLine GFillRound GFillCircle GGradV GGradH
  GShade GMix`, texte `GFontSel GChar GText GTextScaled GTextW` (police bitmap
  Windows-1252 : tout Latin-1, euro, oe/OE, tirets, guillemets, en 8x16, 12x24 et
  16x32, generee par `MKFONT.PY` depuis DejaVu Sans Mono dans `FONTS.INC`),
  `GClipSet`, curseur de souris dessine par le logiciel (`GCursorShow/Hide`),
  `GFlush`/`GFlushRect` (copie du tampon vers la memoire video : pas de
  scintillement), `GClose` (retour en `KD_TEXT`).
* **Widgets** (`WIDGETS.INC`) : etiquette multi-lignes, bouton, case a cocher, boutons
  radio, champ de texte et de mot de passe, liste a ascenseur et selection par la
  premiere lettre, barre de progression, journal, boite de message modale, focus
  clavier (Tab, Maj-Tab, Entree, Echap, fleches, Espace) et souris (clic, double
  clic) ; `UiRun` rend l'identifiant du bouton active ou `1000 + id` pour un
  widget qui notifie un changement.
* **Grille de cellules** : la fenetre est decrite en cellules (police 12x24 sur
  1024x768 : 85x32 ; 8x16 sous 1000 pixels de large ; 16x32 des 1500) ; la meme
  description sert au **mode texte plein ecran ANSI** (80x25 mini). `F3` bascule
  a chaud entre graphique et texte (mode "expert", ou repli automatique si
  `/dev/fb0` est absent ou `text` figure sur la ligne de commande). Sur la console
  VGA du noyau les accents sont convertis en CP437 ; sur un terminal serie, en ASCII
  (ou UTF-8 avec `k32setup.utf8`).
* **Touches mortes** (lot E6) : circonflexe, trema, grave, aigu et tilde des
  dispositions fr be de chde chfr es pt (codes 2 a 6 de `LAYOUTS.INC`, jetons
  `dcirc ddiaer dgrave dacute dtilde` de `LAYOUTS.TXT`) : la lettre suivante est
  accentuee (`InCompose`), Espace ou la meme touche donne le signe seul.
* **Clavier** : sur une console virtuelle l'assistant met `KDSKBMODE` en MEDIUMRAW
  et un termios brut ; les codes de touche Linux sont traduits ICI par la
  disposition choisie (`LAYOUTS.TXT` : us uk fr be de chde chfr it es pt nl, trois
  plans normal / majuscule / AltGr, verrouillage des majuscules, Ctrl) : la
  disposition est donc appliquee tout de suite, sans table du noyau. Sur un port
  serie ou sans console virtuelle, les octets sont lus tels quels (UTF-8, fleches
  ANSI). `F2` ouvre un shell de secours (l'assistant reprend a sa fermeture).
  Pas de touches mortes (^ trema) : le caractere est insere seul.
* **Textes** : `CATALOG.TXT` (UTF-8) contient 145 messages en francais, English,
  Deutsch, Italiano, Espanol, Portugues, Nederlands ; `MKDATA.PY` genere
  `MSGS.INC` et `LAYOUTS.INC` (ASCII ; octets Windows-1252). La langue change a
  chaud sur la premiere page et sert au systeme installe. Les noms de
  fuseaux (`Europe/Paris`) ne sont pas traduits ; les regions le sont.

### Etapes de l'assistant

0. Langue puis **accueil** (ecran/memoire/disques detectes, touches ; `F1` ouvre
l'aide a tout moment) ;
1. Langue ; 2. clavier (champ de test) ; 3. fuseau horaire : region puis ville
(`/usr/share/zoneinfo`, heure locale affichee avec le decalage) ; 4. date et heure
(reglage du systeme avec `settimeofday`, horloge materielle UTC ou locale) ;
5. nom de la machine ; 6. mot de passe root, utilisateur (nom, identifiant, mot
de passe : hachage V7 comme `PASSWD`) ; 7. disque (`/proc/partitions` : le CD, les
disques montes ou en swap ne sont pas proposes ; le **contenu existant** est
detecte (`FSPROBE.INC` : type, nom, et `/boot/linux0` d'un systeme LINUX-0 deja
installe) et repete en rouge dans le recapitulatif avant l'effacement) ; 8. partitionnement : *assiste*
(racine + swap optionnel, systeme de fichiers ext4/ext3/ext2) ou *manuel* ;
9. (manuel) **editeur MBR** type cfdisk : liste des 4 partitions primaires, de la
**partition etendue** et des **logiques** (5 a 12, EBR chaines, alignement 1 Mio) et
des espaces libres, creation (tailles `500M`, `2G`, vide = tout), suppression, type
(Linux 83 / swap 82), indicateur d'amorce, tout effacer ; 10. (manuel) roles :
`/` (racine, obligatoire, **primaire** : le chargeur lit `/boot` sur la partition
active), swap, `/home`, ou inutilisee ; systeme de fichiers
(ext4/ext3/ext2) par defaut ou partition par partition (bouton) ;
11. recapitulatif et **confirmation explicite** (case a cocher + boite Oui/Non) ;
12. installation avec barre de progression reelle (octets du tar lus) et journal ;
13. fin : retirer le CD, redemarrer. Aucune ecriture avant la confirmation ; en cas
d'erreur une boite explique et l'assistant revient au recapitulatif (les montages
sont demontes).

Installation (`DoInstall`) : ecriture du MBR (code de `/usr/share/boot/MBR.BIN`,
parametres du chargeur, table, signature) et du chargeur (stage2, secteurs 1..N ;
les partitions commencent a 1 Mio) ; `BLKRRPART` ; `mkfs.ext4|ext3|ext2 -L ...`
et `mkswap` (programmes d'`INSTALL.PAS`) ; montage sur `/target` ; extraction de
`/cdrom/system.tar` ; ecriture de `/etc/fstab`, `hostname`, `hosts`, `passwd`,
`shadow`, `group`, `sudoers`, `profile` (`LANGUAGE=XX`, `LANG=xx_XX.UTF-8`),
`default/locale`, `default/keyboard`, `timezone`, `localtime` (copie TZif),
`adjtime`, ajouts a `/etc/rc` (`hwclock -s`, `swapon -a`, `mount -a`) ;
`/boot/linux0` copie du CD et `/boot/linux0.cfg` (`root=/dev/hdaN rw console=tty0
console=ttyS0`, plus `keymap=fr|us` si c'est la disposition choisie ; les autres
sont chargees par `/bin/loadkeys $KEYMAP` depuis `/etc/rc`) ; `hwclock -w` ; copie de `/var/log/install.log`.

### Installation automatique (preseed)

Parametre du noyau `preseed=/cdrom/preseed.cfg` : fichier `cle=valeur` (commentaires
`#`) : `lang` (fr en de it es pt nl), `keyboard` (us uk fr be de chde chfr it es pt
nl), `timezone`, `clock` (utc|local), `date`/`time` (AAAA-MM-JJ, HH:MM:SS),
`hostname`, `rootpw`, `user`, `fullname`, `userpw`, `disk` (defaut : premier disque
libre), `partitioning` (guided|manual), `swap` (Mo, 0 = aucun), `fs` (ext4|ext3|ext2),
`parts` (manuel : `ext3:/:250M,swap:swap:32M,ext4:/home:*`, systeme de fichiers par
partition, tailles `M`/`G`/`*` ; suffixe `:l` = partition logique, creee dans
une etendue sur l'espace libre restant : `ext4:/:250M,swap:swap:32M:l,ext3:/home:*:l`),
`ui` (gui|text|none), `endwait` (secondes d'affichage de la page finale), `reboot`
(reboot|halt). Autres
parametres du noyau : `lang=fr` (langue initiale de l'assistant interactif ; defaut
English), `text` (mode texte), `k32setup.verbose=/dev/ttyS0` (marqueurs
`K32SETUP: ...` sur le port serie, pour les essais), `k32setup.utf8`.

### Fuseaux horaires (`L32API.PAS`)

`LnxTzSelect(nom)`, `LnxTzAt(t)` (decalage en secondes a l'est de UTC pour l'instant
UTC `t`), `LnxTzUtcOf(local)`, `LnxTzIsDst(t)` lisent des fichiers TZif v1 (transitions
jusqu'en 2037, heure d'ete comprise) : variable `TZ` (`Europe/Paris`,
`:Europe/Paris`, chemin absolu, ou l'ancienne forme `NOM[+-]hh[:mm]`), `/etc/TZ`,
puis `/etc/localtime`. `GetLocalTime`, `SetLocalTime`, les dates de fichiers (`ls`),
`date`, cron, `hwclock` les appliquent. `hwclock -w|-s` lit `/etc/adjtime` (`LOCAL`)
ou `--localtime`/`--utc`. Test : `RUNINST.SH tz` (16 zones x 64 dates comparees a
`date` de l'hote, dont les passages a l'heure d'ete).

### Fabrication des donnees et de la police

`USR/INSTALLER/MKFONT.PY` (FONTS.INC), `MKDATA.PY` (LAYOUTS.INC, MSGS.INC et
`KEYMAPS.KRN` pour le noyau) : a relancer apres modification de `LAYOUTS.TXT`
ou `CATALOG.TXT`. Compilation : `lpc -3X INSTALLER.PAS` (tous les `.INC` dans le
dossier).

### Tests (`TESTS/U/RUNINST.SH`)

`RUNINST.SH [-r racine] [-k noyau] [-c captures] [tz auto-fr auto-de auto-log ui-fr ui-de text refuse virtio exist]` :
CD amorce sous QEMU (`-cdrom`, disque IDE vierge), installation, puis **amorcage du
disque installe sans le CD** (connexion, nom de machine, langue, fuseau,
utilisateur, clavier, fstab, noyau, `e2fsck -fn` de l'hote). `auto-de` installe
en mode texte (`ui=text`) avec une horloge materielle declaree locale (QEMU
`-rtc base=localtime`) ; `refuse` verifie qu'un disque monte (le CD) est refuse.
`ui-fr`, `ui-de` et
`text` pilotent l'interface par le moniteur QEMU (`sendkey`, `mouse_move`,
`mouse_button`) et gardent des captures PNG dans `IMAGE/CAPTURES/`.

### loadkeys / dumpkeys (lot E6)

`USR/LOADKEYS.PAS` (`/bin/loadkeys`, lien `dumpkeys`) : `loadkeys NOM` (les 11
dispositions de l'assistant), `loadkeys -f fichier` (`keycode N = normale
majuscule altgr`), `-n` (affiche sans ecrire), `-d` (us) ; `dumpkeys` relit les
tables. Il utilise KDSKBENT/KDGKBENT (0x4B47/0x4B46) : **le noyau ne les offre pas
encore** (DEMANDES_A.md [E6], pour D7) ; le programme le dit et rend 1.

### Disques virtio, VirtualBox

L'assistant installe aussi sur `/dev/vdX` (scenario `virtio` de `RUNINST.SH` :
installation puis amorce du disque virtio-blk). Sous VirtualBox (carte VBoxVGA :
pas de `/dev/fb0`), l'assistant passe seul en **mode texte** plein ecran (80x25,
accents convertis en CP437, `F3` inoperant faute de framebuffer).


### Guide d'installation pas a pas (lot E6)

**Fabriquer le CD** : `KERNEL32/BUILD.SH cd` (ou `TOOLS/MKINSTALLCD.SH -o X.ISO`) ;
sortie `IMAGE/KERNEL32-INSTALL.ISO` (16 Mo, a regenerer, non conserve dans le depot).

**QEMU** (affichage graphique 1024x768) :

1. `truncate -s 2G disque.img`
2. `qemu-system-i386 -m 256 -vga std -cdrom IMAGE/KERNEL32-INSTALL.ISO -boot d
   -drive file=disque.img,format=raw,if=ide,index=0` (le CD est `/dev/hdc`, le disque
   `/dev/hda` ; `if=virtio` donne `/dev/vda`). Le noyau du CD fixe `fb=1024x768` : la
   carte `-vga std` passe en mode graphique, l'assistant s'affiche (captures
   `IMAGE/CAPTURES/fr-01-langue.png` a `fr-11-fin.png` pour le francais,
   `de-*.png` pour l'allemand).
3. Suivre les pages (Tab, Entree, fleches, souris ; `F1` aide, `F2` shell, `F3` texte) :
   langue, accueil, clavier, fuseau, date, machine, comptes, disque,
   partitionnement, recapitulatif (cocher la confirmation), installation, fin.
4. Quitter QEMU ; relancer **sans** `-cdrom` : `qemu-system-i386 -m 128 -drive
   file=disque.img,format=raw,if=ide,index=0` : le chargeur
   amorce directement le systeme installe, `login:` (root, mot de passe choisi).
5. Installation sans intervention : `-append`/`MKINSTALLCD.SH -c "... preseed=/cdrom/
   preseed.cfg"` (exemple `USR/INSTALLER/preseed.example`).

**VirtualBox 7.0** (carte VBoxVGA : pas de `/dev/fb0` : l'assistant se met seul en
mode texte 80x25, capture `text-01-langue.png`) :

1. Nouvelle machine : type Linux, version "Other Linux (32-bit)", **BIOS** (pas EFI),
   memoire 256 Mo (128 Mo au minimum), 1 processeur.
2. Disque : nouveau disque VDI de 2 Go ou plus ; controleur **IDE** (PIIX4), pas SATA
   (le noyau n'a pas encore de pilote AHCI : DEMANDES_A.md, D7). Le CD
   `KERNEL32-INSTALL.ISO` sur le controleur IDE secondaire.
3. Affichage : `VBoxVGA`, memoire video 16 Mo ; clavier/souris PS/2 par defaut.
4. Demarrer : l'assistant s'affiche en mode texte (touches seulement). Memes pages
   que sous QEMU. En fin d'installation : `Redemarrer`, puis retirer le CD (menu
   Peripheriques > Lecteurs optiques > Retirer) ou le decocher dans l'ordre d'amorce.

**Machine reelle** : graver l'ISO, amorcer en BIOS ; le noyau ne sait programmer le
mode graphique que sur la carte Bochs/QEMU VGA : ailleurs (pas de `/dev/fb0`)
l'assistant se met seul en mode texte (non verifie sur du materiel reel).

### Limites

Pas de logiques sans etendue ni de racine logique ; une racine ne depasse pas 30 Go en mode assiste
(blocs de 4 Ko des 2 Go) ; `mkfs` formate au plus 2 Go avec des blocs de 1 Ko, 32 Go
avec 4 Ko (`INSTALL.PAS` : `MAXBLK`) ; une seule partition `/home` ; pas de GPT, de
LVM ni de chiffrement ; pas de reseau pendant l'installation ; dispositions de clavier
autres que us et fr : voir `BUGS_NOYAU.md` [E5] (le noyau ne les connait pas) ; pas de
touches mortes ; `F2` : shell sans controle de jobs.

### Lot E6 (suite) : userland ajoute dans `USR/`

Audit des commandes de la racine du depot : `date` (version DOS : pas de texte
relatif ni de fuseau), `chmod` (attributs DOS : `chmod +x` / `chmod 755` ne
changeaient pas les droits Unix), pas de `logrotate`, `rdate`, `ntpdate`,
`tune2fs`, `dumpe2fs`, `run-parts`. Ajouts (tous testes, voir `RUNU.SH lot2host
lot2`) :

| programme | contenu | essai |
|---|---|---|
| `DATE.PAS` (`/bin/date`) | syntaxe de GNU date : `-d` (`@epoch`, ISO, americain, mois en lettres, `now today tomorrow yesterday noon`, `next friday`, `3 days ago`, `+1 month`, `TZ="Zone"`, sigles et `+hh:mm`), `-u -s -r -R -I`, strftime complet (`%a..%Z`, `%V %G %U %W %j %:z`, indicateurs `- _ 0 ^`, largeurs), fuseau TZ ou `/etc/localtime` avec heure d'ete et sigle (`LnxTzAbbr`) | `datetest.py` : 420 comparaisons a GNU date sur 5 fuseaux, 0 ecart |
| `CHMOD.PAS` | modes Unix octaux et symboliques (`u+x go-w a=rx u=g +t X`, umask), `-R -v -f`, regles GNU des dossiers (setuid/setgid) | `chmodtest.py` : 352 comparaisons, 0 ecart |
| `NTPDATE.PAS` (`ntpdate`, `rdate`) | SNTP v4 (UDP 123) avec `-q`, `-p port` ; protocole TIME (TCP 37) avec `-p -s -P port` ; serveur par adresse, `/etc/hosts` ou DNS | `nettime.py` : serveurs factices sur l'hote, decalage de 7200 s |
| `LOGROTATE.PAS` (`/sbin/logrotate`) | `rotate size daily weekly monthly missingok notifempty copytruncate create nocreate olddir prerotate postrotate include`, fichier d'etat, `-f -d -s` (la compression est signalee, non faite) | `logrotatetest.py` : 12 essais |
| `IPTABLES.PAS` (`/sbin/iptables`, `iptables-save`, `iptables-restore`) | syntaxe `-t -A -I -D -F -L -S -P -N -X -Z -p -s -d -i -o --sport --dport -m --state -j`, tables filter/nat/mangle/raw ; regles gardees dans `/var/lib/iptables.rules` (`IPTABLES_RULES=`) et NON appliquees : pas encore branche sur le filtre du noyau (setsockopt) | `lot2.sh` sous QEMU (2 essais) |
| `E2TOOLS.PAS` (`dumpe2fs tune2fs e2label resize2fs`) | superbloc ext2/3/4 : `dumpe2fs -h`, `tune2fs -l -L -m -c -C -i -e` (somme de controle `metadata_csum` recalculee), `e2label` ; `resize2fs` affiche la taille et refuse tout changement (non fait) | `e2toolstest.py` : 18 essais contre e2fsprogs (ext2, ext3, ext4 metadata_csum, 64bit) |
| `ROOTFS/etc/crontab`, `cron.hourly daily weekly monthly`, `usr/bin/run-parts`, `etc/logrotate.conf` et `logrotate.d` | `crond` lance `run-parts` aux heures de `/etc/crontab` ; `cron.daily/logrotate` | `lot2.sh` sous QEMU |

`BUILD.SH` installe aussi `/usr/share/zoneinfo` (TZif de l'hote, `ZONES=`) et des
fichiers terminfo (`/usr/share/terminfo`, `TERMINFO=`) dans la racine. Sous QEMU :
`/usr/share/bench/lot2.sh` (`RUNU.SH lot2`). `RUNU.SH` sans argument rejoue
maintenant tout, `lot2host` et `lot2` compris.

### Validation par champ de l'assistant (retour VirtualBox)

Chaque page a saisie (date et heure, nom de machine, comptes, taille de swap,
taille d'une partition) valide **champ par champ**, en direct pendant la frappe :

* le champ invalide passe sur **fond rouge** (graphique : rose + cadre rouge ; texte
  VGA : attribut rouge) et un message d'une ligne, qui nomme le champ, remplace
  l'indice gris place sous lui (`Identifiant : minuscules, chiffres, - et _ ; commence
  par une lettre.`, `Mots de passe differents : confirmation.`, 7 langues) ; il
  redevient normal des que le contenu est valide ;
* sous chaque champ contraint, l'**indice** de la regle s'affiche en gris
  (identifiant : minuscules, chiffres, - et _, commence par une lettre ; mot de
  passe root non vide ; nom de machine : lettres, chiffres, tiret et point ;
  AAAA-MM-JJ, HH:MM:SS ; taille de swap entre 8 Mo et la moitie du disque) ;
* **Suivant** est grise tant qu'un champ est rouge ou incomplet ; Entree sur une
  page invalide est refusee et donne le focus au premier champ fautif ;
* l'identifiant accepte les **majuscules** : elles sont converties en minuscules
  (remarque verte `Majuscules converties en minuscules.`) et les espaces de fin
  sont retires ;
* mots de passe : indicateur de concordance (rouge tant que la confirmation differe,
  vert `Les mots de passe sont identiques.`), case **Afficher les mots de passe**
  ou touche `F5`.

Essais : `RUNINST.SH ui-fr text` (pixels de la capture : champ rouge puis retour au
fond normal, Entree refusee) ; captures `fr-04b-heure-invalide`, `fr-04c-nom-invalide`,
`fr-05a-confirmation-rouge`, `fr-05b-majuscules-converties`,
`fr-05c-identifiant-invalide`, `fr-05d-confirmation-utilisateur`,
`text-04-confirmation-rouge`, `text-05-identifiant-invalide` dans `IMAGE/CAPTURES`.

### Modes de demarrage et environnements de bureau (contrat du 2026-11-18)

**Assistant d'installation** : nouvelle etape "Mode de demarrage" apres les comptes
(7 langues, aide F1, cle de preseed `session=terminal|kde|gnome|geoworks`, ligne du
recapitulatif). Quatre choix : demarrer automatiquement en terminal (defaut), dans un
environnement KDE, GNOME ou GEOWORKS. Des remarques rouges avertissent si GEOWORKS n'est
pas present sur le CD (le systeme demarrera en terminal) ou si le graphique est
indisponible dans l'installateur. Le choix est ecrit dans `/etc/k32/session` (et
`session-user` si un utilisateur est cree) sur le disque cible.

**Apres l'installation** (diagnostic du retour "il relance l'installation") : le systeme
installe ne contient ni `/sbin/k32-setup` ni entree d'assistant dans `inittab`, et
`k32-setup` refuse de tourner si `/etc/k32/installed` existe ; la cause reelle etait le CD
reste dans le lecteur (BIOS : optique en premier). L'assistant ejecte maintenant le CD
(demonte, `CDROMEJECT` 0x5309 sur `/dev/hdc`, `/dev/hdd`, `/dev/hdb`, `/dev/sr0`) avant
de redemarrer ou d'eteindre, et l'ecran final demande de le retirer s'il reste.
Test : `RUNINST.SH auto-fr` verifie "tray open" dans le moniteur QEMU.

**`k32-session get | set MODE | run | tty TTY | status`** (`USR/K32SESS.PAS`, `/bin`) :
`inittab` lance `k32-session tty tty1` : session graphique selon `/etc/k32/session`, puis
`getty` (retour au login a la sortie). Replis automatiques avec message et journal
`/var/log/k32-session.log` : `/dev/fb0` absent (code 10), programme absent (11),
environnement qui echoue en moins de 8 s (12) ; jamais d'ecran noir (la console est remise
en texte). Programmes : `k32-kde`, `k32-gnome`, `geoworks` (fourni par G1 : tant qu'il
est absent, le mode geoworks retombe sur le terminal). Codes de sortie de l'environnement :
100 redemarrer, 101 eteindre. Alt+F2 a Alt+F4 : autres terminaux texte (le bureau
demande `VT_PROCESS` et se redessine au retour).

**Terminal** (`VTCORE.INC` : coeur VT100/ANSI sans dependance, 16 couleurs, defilement,
ecran alternatif, UTF-8 vers Latin-1, DSR/DA ; `VTVIEW.INC` : pty `/dev/ptmx`, dessin
GFX, historique Maj+PgHaut/PgBas ; essais `TESTS/U/vtermtest.py` par `VTDRV.PAS` :
39 cas).

**Environnements compatibles** (`USR/DESKTOP.INC`, un seul programme `K32DESK.PAS` dont
le nom choisit l'environnement ; PAS de serveur X : phase 2) :
* GNOME (`gnome-session`, `k32-gnome`) : apparence Adwaita, barre superieure Activites +
  horloge + menu systeme (Se deconnecter / Redemarrer / Eteindre / A propos), fenetres a
  titre centre, vue Activites (grille d'applications), `XDG_CURRENT_DESKTOP=GNOME`.
* KDE (`startplasma-x11`, `startkde`, `k32-kde`) : apparence Breeze, panneau en bas,
  lanceur d'applications, gestionnaire de taches, zone de notification + horloge,
  `XDG_CURRENT_DESKTOP=KDE`.
* `gnome-terminal`, `konsole`, `dolphin` : une seule fenetre Terminal (`-e commande`).
* Fenetre Terminal fonctionnelle (shell `sh -l` sous l'utilisateur de la session, deplacer,
  redimensionner par le coin, agrandir, fermer), applications lues dans
  `/usr/share/applications/*.desktop` (Name, Name[fr], Exec, Terminal, NoDisplay), sessions
  `/usr/share/xsessions/{gnome,plasma,geoworks}.desktop`, variables XDG_*. Clavier : Alt+F1
  menu/Activites, Alt+F4 ferme, Ctrl+Alt+Suppr menu de session, Alt+F2.. consoles texte.
* Essais : `RUNU.SH vterm lot4 desk` (`lot4.sh` : k32-session et replis ; `desktest.py` :
  bureau lance par init, captures, frappe dans le Terminal, Alt+F2/Alt+F1, deconnexion).
  Captures `IMAGE/CAPTURES/{gnome,kde,bgnome,bkde}-*.png`.

### Diagnostics et echecs de l'installateur

* **Mode texte de repli** : la raison est affichee en rouge en bas de la page de langue
  et de la page d'accueil (`Graphique indisponible : /dev/fb0 : ... ; /proc/fb : ...
  (F3 pour reessayer)` ; ioctl refuses, mode non utilisable, mmap, memoire) et ecrite
  dans le journal ; `F3` retente l'ouverture du graphique et rapporte la nouvelle raison.
* **Progression** : la barre porte le nom de l'etape (partitions, formatage, montages,
  copie, configuration, noyau et chargeur) et, pendant une commande, la sous-etape
  (`: mkfs.ext4 /dev/sda1`) avec le temps ecoule en secondes.
* **Echec** : une commande qui sort en erreur ou ne produit plus aucune sortie pendant
  900 s (preseed `timeout=`) est interrompue ; page d'echec avec le message clair, les
  dernieres lignes du journal et **Reessayer / Shell (F2) / Quitter**. Journal
  `/var/log/install.log`, copie dans `/tmp/install.log` et, si la racine cible est
  montee, sur le disque cible.
* Audit des decalages 32 bits au-dela de 2 Gio : `INSTALL.PAS` (correctif llseek 64 bits
  de D7), `mkswap` (taille par `BLKGETSIZE` sans produit sur 32 bits), `DkSectors` (repli
  par llseek), `ParseSize` (bornee a 1 To) ; `e2fsck-lite` utilisait deja llseek ;
  `FSPROBE`, `e2tools`, `INSTOPS` ne lisent que des offsets de moins de 2 Gio.
* Essais : `RUNINST.SH fail` (mkfs remplace par `sleep` via la cle de preseed
  `testmkfs=`, delai 4 s) et `RUNINST.SH sata8g` (disque creux 8 Go, ich9-ahci, 1 Gio).

### Redemarrage apres l'installation : le systeme installe, pas l'assistant

Retour utilisateur (VirtualBox 7.0.6, Windows 11, BIOS, disque et CD sur SATA/AHCI) :
le bouton **Redemarrer** relancait l'installation, alors que fermer puis rouvrir la VM
demarrait bien le systeme installe.

* **Cause constatee sous QEMU** (ich9-ahci pour le disque ET le CD, SeaBIOS, ordre CD puis
  disque, sans `-no-reboot`) : l'ejection du noyau fonctionne (`START STOP UNIT` apres
  `PREVENT ALLOW 0` : `info block` donne `tray open`), mais **la reinitialisation du
  materiel referme le plateau et le CD est a nouveau amorcable** ; le BIOS demarre donc le
  CD, et l'assistant (preseed ou non) refaisait l'installation en boucle. Un
  redemarrage "a froid" par fermeture de la VM prend un chemin different (CD retire).
  `SysReboot(RESTART)` fait bien un reset complet (le BIOS, le chargeur du CD et le
  noyau repartent de zero : verifie par la banniere du chargeur apres "Redemarrage du
  systeme").
* **Garde-fou (quoi qu'il arrive de l'ejection)** : au lancement, l'assistant cherche un
  systeme deja installe (`/etc/k32/installed` et `/sbin/init` sur une partition
  ext2/3/4). S'il en trouve un, il **n'installe pas** : page "Systeme deja installe"
  (7 langues, langue prise dans `/etc/default/locale` du systeme installe) avec decompte
  de 5 s (preseed `installedwait=`), puis, par defaut, **Demarrer le systeme installe** ;
  autres choix : **Reinstaller** (l'assistant normal, ou la suite du preseed) et **Shell
  (F2)**. Le decompte s'arrete si le focus quitte "Demarrer". `k32setup.reinstall` (ligne
  de commande) ou `reinstall=yes` (preseed) forcent l'assistant sans la page.
* **Demarrer le systeme installe depuis le CD** : `SwitchRoot` monte la racine installee,
  y deplace `/dev`, `/proc` et `/sys` (`MS_MOVE`), appelle `pivot_root` (le noyau deplace
  la racine de tous les processus, init compris), ferme l'ecran, puis demande a init
  (`/var/run/init.req` = `R`, SIGHUP) de **se relancer** : `INIT.PAS` arrete les
  processus du CD et fait `exec /sbin/init` du systeme installe ; son `/etc/inittab`,
  son `/etc/rc` et sa session (terminal, GNOME, KDE, GEOWORKS)
  demarrent comme apres un amorcage du disque. C'est le meme noyau que sur le disque.
  Si le montage ou le pivot echoue, rien n'est change et un message est affiche.
* **Ejection plus robuste** (`EjectCd`) : demontage du CD, puis sur `/dev/sr0..3`,
  `hdc`, `hdd`, `hdb`, `scd0`, `cdrom` : `CDROM_LOCKDOOR 0` puis `CDROMEJECT`, avec le
  retour de chaque ioctl dans le journal (`ejection /dev/sr0 : deverrouillage 0,
  CDROMEJECT 0`). `k32setup.noeject` simule une ejection sans effet (essais). Nouvelle
  commande `eject [-t] [-v] [dev...]` (`USR/EJECT.PAS`).
* Limites : le systeme demarre ainsi garde `/proc/cmdline` du CD et l'ancienne racine
  en memoire du CD reste montee sous `/oldroot` (umount repond "cible occupee" : une
  reference du noyau subsiste, une quinzaine de Mo de RAM) ; apres `reboot`, le CD
  (s'il est toujours la) repasse par la page et redemarre le systeme installe : retirer
  le CD dans les reglages de la VM pour un amorcage direct du disque.
* Essais (`RUNINST.SH reboot reboot-noeject guard guard-reinstall`) : disque et CD sur
  AHCI, preseed jusqu'a "Redemarrer", reset reel ; avec et sans ejection ; le systeme
  installe arrive dans le terminal, GNOME, KDE ou GEOWORKS ; Reinstaller ; `reinstall=yes`.

### Installation lente : formatage rapide et progression continue

Retour VirtualBox : l'etape 12/13 restait a 3 % pendant plusieurs minutes (mkfs) puis sautait a 100 %.

* **Mesure** (QEMU, disque creux 32 Go sur ich9-ahci, `cache=writethrough`) : l'etape lente etait
  **mkfs.ext4** (254 s sur 265 s : ecritures de 4 Ko, 512 Mo de tables d'inodes mises a zero) ;
  extraction du tar 4 s, chargeur 1 s.
* **Correctif `USR/INSTALL.PAS`** : ecritures groupees de 1 Mo ; une zone a ecrire a zero n'est ecrite
  que si elle ne l'est pas deja (relecture, disque neuf : aucune ecriture) ; **tables d'inodes
  paresseuses** sur ext4 (uninit_bg / metadata_csum, comme `lazy_itable_init`) : seul le groupe 0
  est mis a zero, les autres groupes sont `INODE_UNINIT` sans `ITABLE_ZEROED` (le noyau sait les
  initialiser, `e2fsck -fn` reste propre) ; journal ecrit par blocs consecutifs. Apres : **ext4 32 Go
  en 15 s** (installation complete 25 s), ext3/ext2 38 s (les tables sont relues). Au-dela, c'est
  le noyau : 256 secteurs par commande AHCI (voir `DEMANDES_D7.md`).
* **Progression** : mkfs ecrit `K32_PROGRESS` (phase, millieme, groupe, groupes ; au plus 6 fois par
  seconde) ; l'installateur le lit toutes les 100 ms et affiche, sous la barre (qui suit reellement
  le compteur), `tables d'inodes : groupe 90/92 | 57 % | ecoule 00:25 | reste ~00:18 |` (indicateur
  d'activite tournant) ; extraction : `fichier /usr/bin/ls : 12/45 Mo | 27 % | ...` ; au moins 4
  mises a jour par seconde, y compris pendant `sync` (execute dans un fils). Poids de la barre :
  partitions 3 %, formatage 30 %, montages 2 %, copie 50 %, configuration/noyau/fin 15 %.
* **Blocage** : une commande dont le compteur avance n'est plus consideree bloquee (`OpTimeout`).
* Essai : `RUNINST.SH progress` (cle de preseed `mkfsslow=ms` : mkfs ext3 ralenti, operation de 60 s).

### Pointeur absolu et diagnostic des entrees (VirtualBox, tablette USB)

Retour VirtualBox reel (noyau avec USB OHCI + VMMDev) : curseur absent, souris morte.
Cote programmes (`USR/INSTALLER/INPUT.INC`, partage par l'assistant et `K32DESK`) :

* `InOpen` lit `/dev/input/mice` (PS/2 relatif) **et** les `/dev/input/event0..7` qui ont
  `EV_ABS` avec `ABS_X` et `ABS_Y` (`EVIOCGBIT`, `EVIOCGABS` pour le maximum, evenements
  `struct input_event` de 16 octets : `ABS_X/ABS_Y`, `BTN_LEFT/RIGHT/MIDDLE`, `SYN`).
  Regle : le relatif sert tant qu'aucun evenement ABS reel n'est arrive (une position
  nulle d'un hote sans pointeur ne compte pas) ; apres le premier, la position vient de
  l'ABS (mise a l'echelle de l'ecran) et les boutons de l'une ou l'autre source comptent.
* Le curseur est dessine **des l'ouverture**, au centre, meme sans aucun peripherique
  (`InPtr`), et un pointeur absolu qui apparait a chaud
  (`echo 1 > /proc/sys/k32/usb_enable`) est detecte en une demi-seconde (event2 n'annonce `EV_ABS` qu'apres son premier rapport : l'assistant re-sonde).
* **Curseur prisme** (`GCursorShow`, `GCursorTick` dans `GFX.INC`) : fleche 16x23, point chaud
  (0,0), contour noir de 1 px (visible sur les listes blanches), 3 facettes (clair a gauche,
  moyen, sombre en bas) plus un reflet ; la couleur primaire change chaque seconde
  (rouge `E02020`, vert `20C040`, bleu `2060E8`, index = seconde murale mod 3), **meme souris
  immobile** : `InPoll` attend par tranches de 250 ms et appelle `GCursorTick`, qui redessine
  seulement la silhouette en place (ni fond a recopier, ni trainee). `GFXPLAINCUR=1`,
  `k32setup.plaincursor` ou `plaincursor=yes` (preseed) gardent l'ancienne fleche blanche.
  Essais : `RUNINST.SH cursor`, `RUNU.SH desk` (bureaux GNOME et KDE).
* Le clavier seul suffit pour toute l'installation (Tab, Entree, Echap, F2 shell, F3).
* `/bin/k32-input` (`USR/ROOTFS/bin/k32-input`, script sh) : `status`, `usb`, `vbox`, `ps2`,
  `auto` (ecrivent `/proc/sys/k32/usb_enable` et `vbox_enable`), `log` (rapport dans
  `/tmp/k32-input.txt` : noyau, `/proc/k32input`, sysctl, messages `usb:`/`vbox:`/`input`,
  `/dev/input`, interruptions, lspci).
* Essais : `RUNINST.SH pointer` (tablette USB `-device usb-tablet` pilotee par QMP
  `input-send-event` : le moniteur texte `mouse_move` n'agit pas sur une tablette ;
  curseur visible, clic absolu sur une liste et sur "Suivant", Entree seule, F2 puis
  `k32-input log`) ; `RUNU.SH desk` (bureau GNOME : clic absolu sur Activites) ;
  `lot4.sh` (`k32-input`).

### Lot E6 (suite 2) : strace, tcpdump, bc, dc, ed, script

| programme | contenu | essai |
|---|---|---|
| `STRACE.PAS` (`/bin/strace`) | ptrace du noyau : `-f` (fork, vfork, clone), `-c` (tableau recapitulatif), `-e trace=liste` / `!liste` / `%file %process %network %signal %desc %memory %ipc`, `-o fichier`, `-s N`, `-T`, `-q`, `-p pid` ; noms d'appels i386 (`STRACE.INC`, genere par `mkstrace.py` depuis asm/unistd_32.h), arguments decodes (chaines, tampons, drapeaux `O_*`, `PROT_*`, `MAP_*`, `AT_FDCWD`, argv/envp, struct stat, wait status), signaux avec `siginfo`, `+++ exited with N +++` ; entree/sortie d'appel par `PTRACE_GET_SYSCALL_INFO` | `stracetest.py` : suite des appels et comptes `-c` identiques a strace GNU sur 7 programmes i386, `-f` sur un shell, `-e`, signal, `-p` (28 essais) |
| `TCPDUMP.PAS` (`/sbin/tcpdump`) | socket `AF_PACKET` : `-i -n -c -e -x -xx -q -s -w -r`, filtres `tcp udp icmp arp ip ip6 host net port src dst less greater broadcast and or not ( )` ; decode Ethernet, ARP, IPv4/IPv6 (adresses), ICMP, TCP (drapeaux, options mss wscale sackOK TS), UDP, DNS, BOOTP/DHCP ; `-w` ecrit un fichier pcap relu par `-r` ; numeros de sequence TCP absolus (comme `-S`) | `tcpdumptest.py` : 14 trames fabriquees (texte exact), 17 filtres, pcap, capture reelle sur `lo` (47 essais) ; sous QEMU : capture d'un ping de la passerelle |
| `BC.PAS` + `BIGNUM.INC` (`/bin/bc`) | bc complet : `scale ibase obase last`, noms de variables de plusieurs lettres, tableaux, `define` (`void`), `auto`, `return`, `if else while for break continue halt quit print`, `++ -- += -= *= /= %= ^=`, `&& \|\| !`, `length scale sqrt read`, chaines, `-l` (`s c a l e j`), coupure des lignes a 69 caracteres (`BC_LINE_LENGTH`), precision arbitraire | `bctest.py` : 60 scripts compares au GNU bc de l'hote, 0 ecart |
| `DC.PAS` (`/bin/dc`) | dc : `+ - * / % ~ ^ \| v`, pile et registres (`s l S L`), tableaux (`: ;`), chaines et macros (`x`, appels terminaux), `< > = !< !> !=`, `k K i I o O z Z X p n P f a c d r R q Q ?`, `-e -f` | `dctest.py` : 63 essais, dont 250 operations aleatoires recoupees avec bc |
| `ED.PAS` (`/bin/ed`) | ed POSIX + GNU : adresses `. $ % , ; +n -n /re/ ?re? 'x`, `a i c d e E f g G h H j k l m n p P q Q r s t u v V w W wq x y z = ! #`, suffixes `p n l`, `s` avec `g n p l & \1 %`, annulation `u`, `r !cmd` | `edtest.py` : 106 essais |
| `SCRIPT.PAS` (`/bin/script`) | commande sur un pty (`/dev/ptmx`), recopie et journal (`-q -a -e -c`) ; sert a verifier le job control | `lot3.sh` sous QEMU |

Verifie sous KERNEL32 par `/usr/share/bench/lot3.sh` (`RUNU.SH lot3`) : strace, tcpdump,
bc, dc, ed, **job control sur un pty** (`script` + `sh` : `jobs`, `fg`, `^Z`, `^C`,
code 130), `lsof`, `fuser`, `netstat`, `ss`, `lspci`, `losetup` (sorties verifiees,
sockets d'ecoute `nc -l`, peripherique loop). `RUNU.SH lot3host` : les tests de
l'hote. Pas encore fait : `nano` (non audite), `ed -G` / chiffrement `x`, filtre
`iptables` branche sur le noyau.
