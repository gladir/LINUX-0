{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2026
  @website(https://www.gladir.com/linux-0)
  @abstract(Target: KERNEL16UNIX (LPC /X))
  @description: Unite UNIX de Linux Pascal : interface des appels systeme du
   noyau LINUX-0 (INT 80h) et bibliotheque "libc" de la cible LINUX-0.

  Cette unite est integree au compilateur LPC (regeneree dans LPC.PAS par
  TOOLS/MKEMBED.PAS) et liee automatiquement a tout programme compile avec
  l'option /X, avant toute autre unite.

  Convention des appels systeme LINUX-0 (INT 80h) :
   AX = numero de l'appel (numeros de UNIX V7, puis de 4.2BSD au-dela de
   63), BX, CX, DX, SI, DI = arguments, DS:DX = premier pointeur, ES:DI =
   second pointeur. Retour : AX (DX:AX pour 32 bits), CF=1 en cas d'erreur
   avec AX = errno (valeurs de UNIX V7).

  Demarrage d'un programme : comme sous UNIX, SS:SP pointe sur argc, suivi
  des tableaux argv[] et envp[] (pointeurs FAR termines par un pointeur nul)
  et des chaines; le pointeur sur argc est aussi au mot double PSP:4Ch
  (ArgCount, ArgStr). Le prefixe de programme (PSP) compatible DOS est
  conserve pour la bibliotheque d'execution de Turbo Pascal (ParamStr).

  Couche libc : la bibliotheque d'execution de Turbo Pascal (et les unites
  DOS, CRT, PRINTER) s'adressent aux services de MS-DOS par INT 21h. Sous
  LINUX-0, le vecteur 21h est propre a chaque processus : le noyau y place
  l'adresse de DosEntry, enregistree par l'appel systeme 201 (setdos)
  lors de l'initialisation de cette unite. DosEntry traduit alors, dans le
  processus lui-meme, chaque service DOS en appels systeme LINUX-0 (open,
  read, write, getdirentries, vfork/exece/wait, ...), comme le ferait une
  libc : le programme n'appelle jamais de service MS-DOS.

  Signaux : SysSignal(SIGINT, @Gestionnaire) installe un gestionnaire
  "Procedure Gestionnaire(Sig: Integer); Far;". Le noyau le fait executer
  par la trampoline de cette unite (appel systeme 204), qui sauvegarde
  l'etat de la libc; comme dans UNIX V7, l'action redevient SIG_DFL avant
  l'appel du gestionnaire (le reinstaller au besoin).
}

Unit Unix;

{$S-,R-,I-}

Interface

Const
 { Numeros des appels systeme : UNIX V7 (1 a 63), 4.2BSD, puis LINUX-0 }
 SYS_exit=1;      SYS_fork=2;      SYS_read=3;      SYS_write=4;
 SYS_open=5;      SYS_close=6;     SYS_wait=7;      SYS_creat=8;
 SYS_link=9;      SYS_unlink=10;   SYS_exec=11;     SYS_chdir=12;
 SYS_time=13;     SYS_mknod=14;    SYS_chmod=15;    SYS_chown=16;
 SYS_break=17;    SYS_stat=18;     SYS_lseek=19;    SYS_getpid=20;
 SYS_mount=21;    SYS_umount=22;   SYS_setuid=23;   SYS_getuid=24;
 SYS_stime=25;    SYS_alarm=27;    SYS_fstat=28;    SYS_pause=29;
 SYS_utime=30;    SYS_stty=31;     SYS_gtty=32;     SYS_access=33;
 SYS_nice=34;     SYS_ftime=35;    SYS_sync=36;     SYS_kill=37;
 SYS_getppid=39;  SYS_dup=41;      SYS_pipe=42;     SYS_times=43;
 SYS_setgid=46;   SYS_getgid=47;   SYS_signal=48;   SYS_ioctl=54;
 SYS_reboot=55;   SYS_uname=57;    SYS_exece=59;    SYS_umask=60;
 SYS_vfork=66;    SYS_dup2=90;     SYS_rename=128;  SYS_mkdir=136;
 SYS_rmdir=137;   SYS_getdirentries=156;
 SYS_procinfo=200; SYS_setdos=201; SYS_meminfo=202; SYS_mountinfo=203;
 SYS_sigtramp=204; SYS_getcwd=205; SYS_nap=206;

 { open (valeurs de 4.2BSD) }
 O_RDONLY=0; O_WRONLY=1; O_RDWR=2; O_NDELAY=4; O_APPEND=8; O_CREAT=$200;
 O_TRUNC=$400; O_EXCL=$800;
 { lseek }
 SEEK_SET=0; SEEK_CUR=1; SEEK_END=2;
 { wait }
 WNOHANG=1;
 { access }
 R_OK=4; W_OK=2; X_OK=1; F_OK=0;
 { signaux (UNIX V7) }
 SIGHUP=1; SIGINT=2; SIGQUIT=3; SIGILL=4; SIGTRAP=5; SIGIOT=6; SIGEMT=7;
 SIGFPE=8; SIGKILL=9; SIGBUS=10; SIGSEGV=11; SIGSYS=12; SIGPIPE=13;
 SIGALRM=14; SIGTERM=15; NSIG=16;
 { ioctl : terminal (UNIX V7) et 4.2BSD }
 TIOCHPCL=$7402; TIOCGETP=$7408; TIOCSETP=$7409; TIOCSETN=$740A;
 TIOCEXCL=$740D; TIOCNXCL=$740E; TIOCFLUSH=$7410; TIOCSETC=$7411;
 TIOCGETC=$7412; FIONREAD=$667F;
 { sg_flags de sgttyb }
 TANDEM=1; CBREAK=2; LCASE=4; ECHO=8; CRMOD=$10; RAW=$20;
 { types de fichiers et permissions (st_mode) }
 S_IFMT=$F000; S_IFDIR=$4000; S_IFCHR=$2000; S_IFBLK=$6000; S_IFREG=$8000;
 S_IFIFO=$1000; S_ISUID=$800; S_ISGID=$400; S_ISVTX=$200;
 S_IREAD=$100; S_IWRITE=$80; S_IEXEC=$40;
 { types de systemes de fichiers pour mount }
 FS_AUTO=0; FS_UFS=2;
 { codes d'erreur (errno, UNIX V7; au-dela, valeurs de 4.4BSD) }
 EPERM=1; ENOENT=2; ESRCH=3; EINTR=4; EIO=5; ENXIO=6; E2BIG=7; ENOEXEC=8;
 EBADF=9; ECHILD=10; EAGAIN=11; ENOMEM=12; EACCES=13; EFAULT=14;
 ENOTBLK=15; EBUSY=16; EEXIST=17; EXDEV=18; ENODEV=19; ENOTDIR=20;
 EISDIR=21; EINVAL=22; ENFILE=23; EMFILE=24; ENOTTY=25; ETXTBSY=26;
 EFBIG=27; ENOSPC=28; ESPIPE=29; EROFS=30; EMLINK=31; EPIPE=32; EDOM=33;
 ERANGE=34; ENAMETOOLONG=63; ENOTEMPTY=66; ENOSYS=78;

Type
 TStat=Record          { struct stat de UNIX V7 (30 octets) }
  Dev: Integer;
  Ino: Word;
  Mode: Word;
  NLink: Integer;
  Uid: Integer;
  Gid: Integer;
  RDev: Integer;
  Size: Longint;
  ATime: Longint;
  MTime: Longint;
  CTime: Longint;
 End;
 TSgttyb=Record        { struct sgttyb de UNIX V7 }
  ISpeed, OSpeed: Byte;
  Erase, Kill: Char;
  Flags: Word;
 End;
 TTms=Record           { struct tms : soixantiemes de seconde }
  UTime, STime, CUTime, CSTime: Longint;
 End;
 TProcInfo=Record
  Pid: Integer;
  PPid: Integer;
  Stat: Byte;     { 1=pret, 2=en attente, 3=zombie }
  Flags: Byte;    { 1 = processus courant, 2 = image en va-et-vient }
  Paras: Word;    { memoire en paragraphes }
  Ticks: Longint; { temps processeur en tops d'horloge (18,2 par seconde) }
  Name: String[15];
  Uid: Integer;
  Gid: Integer;
 End;
 TUtsName=Record
  SysName: String[15];
  NodeName: String[15];
  Release: String[15];
  Version: String[15];
  Machine: String[15];
 End;
 TMemInfo=Record
  TotalParas: Word;   { memoire geree par le noyau, en paragraphes }
  FreeParas: Word;
  KernelParas: Word;  { taille du noyau (code + donnees) }
  BufCount: Word;     { tampons du cache disque }
  ProcCount: Word;    { processus actifs }
  ProcMax: Word;
  SwapKB: Word;       { zone de va-et-vient (Ko, 0 = aucune) }
  SwapFreeKB: Word;
  SwapOuts: Word;     { images ecrites dans la zone depuis l'amorce }
  SwapIns: Word;      { images relues }
 End;
 TMountInfo=Record
  FsType: Byte;       { 1=UFS, 2=dev }
  Drive: Byte;
  ReadOnly: Byte;
  Pad: Byte;
  Start: Longint;     { premier secteur }
  Blocks: Longint;    { taille en Ko }
  Free: Longint;      { libre en Ko }
  Dir: String[31];
  Special: String[15];
 End;

Var
 Errno: Integer;
 { registres de l'appel systeme brut }
 SAX,SBX,SCX,SDX,SSI,SDI,SDS,SES,SFL: Word;
 SIG_DFL, SIG_IGN: Pointer;   { actions de signal (nil et 0000:0001) }

Procedure DoSys;
Function SysOk: Boolean;
Function SysExit(Status: Integer): Integer;
Function Fork: Integer;
Function VFork: Integer;
Function SysRead(Fd: Integer; Var Buf; Count: Word): Integer;
Function SysWrite(Fd: Integer; Var Buf; Count: Word): Integer;
Function SysOpen(Path: String; Flags, Mode: Word): Integer;
Function SysClose(Fd: Integer): Integer;
Function SysWait(Var Status: Integer): Integer;
Function WaitPid(Pid: Integer; Var Status: Integer; Options: Word): Integer;
Function WIfExited(Status: Integer): Boolean;
Function WExitStatus(Status: Integer): Integer;
Function WTermSig(Status: Integer): Integer;
Function WCoreDump(Status: Integer): Boolean;
Function SysCreat(Path: String; Mode: Word): Integer;
Function SysLink(OldPath, NewPath: String): Integer;
Function SysUnlink(Path: String): Integer;
Procedure ArgReset;
Function ArgAdd(S: String): Boolean;
Function EnvAdd(S: String): Boolean;
Function EnvInherit: Boolean;
Function ArgExec(Path: String): Integer;
Function Execv(Path: String; Args: String): Integer;
Function Execve(Path: String; Var Argv; Var Envp): Integer;
Function ArgCount: Integer;
Function ArgStr(I: Integer): String;
Function EnvCount: Integer;
Function EnvStr(I: Integer): String;
Function SysChdir(Path: String): Integer;
Function SysTime: Longint;
Function SysSTime(T: Longint): Integer;
Function SysMknod(Path: String; Mode, Dev: Word): Integer;
Function SysChmod(Path: String; Mode: Word): Integer;
Function SysChown(Path: String; Uid, Gid: Integer): Integer;
Function SysLSeek(Fd: Integer; Offset: Longint; Whence: Word): Longint;
Function GetPid: Integer;
Function GetPPid: Integer;
Function GetUid: Integer;
Function GetGid: Integer;
Function GetEUid: Integer;
Function GetEGid: Integer;
Function SetUid(Uid: Integer): Integer;
Function SetGid(Gid: Integer): Integer;
Function SysMount(Special, Dir: String; FsType: Word): Integer;
Function SysUmount(Dir: String): Integer;
Function SysAlarm(Seconds: Word): Integer;
Function SysPause: Integer;
Function SysUtime(Path: String; ATime, MTime: Longint): Integer;
Function SysAccess(Path: String; Mode: Word): Integer;
Function SysNice(Incr: Integer): Integer;
Function SysSync: Integer;
Function SysKill(Pid, Sig: Integer): Integer;
Function SysRename(OldPath, NewPath: String): Integer;
Function SysMkdir(Path: String; Mode: Word): Integer;
Function SysRmdir(Path: String): Integer;
Function SysDup(Fd: Integer): Integer;
Function SysDup2(Fd, Fd2: Integer): Integer;
Function SysPipe(Var ReadFd, WriteFd: Integer): Integer;
Function SysTimes(Var T: TTms): Longint;
Function SysSignal(Sig: Integer; Action: Pointer): Pointer;
Function SysIoctl(Fd: Integer; Request: Word; Var Arg): Integer;
Function GTty(Fd: Integer; Var S: TSgttyb): Integer;
Function STty(Fd: Integer; Var S: TSgttyb): Integer;
Function IsATty(Fd: Integer): Boolean;
Function SysUmask(Mask: Word): Word;
Function SysReboot: Integer;
Function SysStat(Path: String; Var St: TStat): Integer;
Function SysFStat(Fd: Integer; Var St: TStat): Integer;
Function SysUname(Var U: TUtsName): Integer;
Function SysGetDirEntries(Fd: Integer; Var Buf; Count: Word): Integer;
Function SysGetDents(Fd: Integer; Var Buf; Count: Word): Integer;
Function SysYield: Integer;
Function SysSleep(Seconds: Word): Integer;
Function SysNap(Ms: Word): Integer;
Function SysGetCwd: String;
Function SysProcInfo(Index: Integer; Var P: TProcInfo): Boolean;
Function SysMemInfo(Var M: TMemInfo): Integer;
Function SysMountInfo(Index: Integer; Var M: TMountInfo): Boolean;
Function SysGetEnv(Name: String): String;
Function SysLangOf(V: String): Integer;
Function SysLang: Integer;
Function SysErrorText(E: Integer): String;
Function SigName(Sig: Integer): String;
Function UnixPath(S: String): String;

Implementation

Type
 PByte=^Byte;
 TBytes=Array[0..65519] Of Byte;
 PBytes=^TBytes;
 TFind=Record           { etat d'une recherche FindFirst/FindNext }
  Used: Boolean;
  Fd: Integer;
  Attr: Byte;
  Dir: String[79];
  Pattern: String[12];
  BufLen, BufPos: Integer;  { entrees getdirentries en attente }
  Buf: Array[0..255] Of Byte;
 End;

Var
 { registres de l'appel DOS en cours de traduction }
 RAX,RBX,RCX,RDX,RSI,RDI,RBP,RDS,RES,RFL: Word;
 DtaSeg,DtaOfs: Word;
 LastExit: Word;
 Finds: Array[0..3] Of TFind;
 FindNo: Byte;
 HeapFirst,HeapTop: Word;   { zone du tas (paragraphes) }
 PathBuf: Array[0..255] Of Char;
 PathBuf2: Array[0..255] Of Char;
 ArgBlock: Array[0..1535] Of Char;   { chaines de argv et envp (exec) }
 ArgLen: Word;
 ArgV: Array[0..63] Of Pointer;     { argv[], nil }
 EnvV: Array[0..47] Of Pointer;     { envp[], nil }
 ArgN, EnvN: Integer;
 DirBuf: Array[0..255] Of Byte;
 KbdAhead: Integer;

{ ------------------------------------------------------------------ }
{ Appels systeme                                                     }
{ ------------------------------------------------------------------ }

Procedure DoSys; Assembler;
Asm
 PUSH BP
 PUSH SI
 PUSH DI
 PUSH DS
 MOV BX,SBX
 MOV CX,SCX
 MOV DX,SDX
 MOV SI,SSI
 MOV DI,SDI
 MOV ES,SES
 MOV AX,SAX
 MOV BP,SDS
 MOV DS,BP
 INT 80h
 PUSHF
 PUSH DS
 PUSH AX
 MOV AX,SEG @DATA
 MOV DS,AX
 POP AX
 MOV SAX,AX
 POP AX
 MOV SDS,AX
 POP AX
 MOV SFL,AX
 MOV SBX,BX
 MOV SCX,CX
 MOV SDX,DX
 MOV SSI,SI
 MOV SDI,DI
 MOV SES,ES
 POP DS
 POP DI
 POP SI
 POP BP
End;

Function SysOk: Boolean;
{ comme sous UNIX, errno n'est modifie qu'en cas d'erreur }
Begin
 If SFL And 1<>0 Then Begin Errno:=SAX; SysOk:=False End
 Else SysOk:=True;
End;

Procedure SetRegs(N,B,C,D: Word);
Begin
 SAX:=N; SBX:=B; SCX:=C; SDX:=D; SSI:=0; SDI:=0; SDS:=DSeg; SES:=DSeg;
End;

Function Result16: Integer;
Begin
 DoSys;
 If SysOk Then Result16:=SAX Else Result16:=-1;
End;

Procedure SetPath(S: String);
{ DS:DX = chemin ASCIIZ (PathBuf) }
Var I: Integer;
Begin
 For I:=1 To Length(S) Do PathBuf[I-1]:=S[I];
 PathBuf[Length(S)]:=#0;
 SDS:=Seg(PathBuf); SDX:=Ofs(PathBuf);
End;

Procedure SetPath2(S: String);
{ ES:DI = second chemin ASCIIZ (PathBuf2) }
Var I: Integer;
Begin
 For I:=1 To Length(S) Do PathBuf2[I-1]:=S[I];
 PathBuf2[Length(S)]:=#0;
 SES:=Seg(PathBuf2); SDI:=Ofs(PathBuf2);
End;

Function FarString(Sg,Os: Word): String;
{ Chaine ASCIIZ Sg:Os -> chaine Pascal }
Var S: String;
Begin
 S:='';
 While (Mem[Sg:Os]<>0) And (Length(S)<255) Do Begin
  S:=S+Chr(Mem[Sg:Os]); Inc(Os);
 End;
 FarString:=S;
End;

Function SysExit(Status: Integer): Integer;
Begin
 SetRegs(SYS_exit,Status,0,0); DoSys; SysExit:=-1;
End;

Function Fork: Integer;
Begin
 SetRegs(SYS_fork,0,0,0); Fork:=Result16;
End;

Function VFork: Integer;
{ comme Fork, mais le fils s'execute dans la memoire du pere (suspendu)
  jusqu'a son appel a exec ou SysExit : sans copie de la memoire.
  Le fils ne doit rien faire d'autre que exec puis SysExit. }
Begin
 SetRegs(SYS_vfork,0,0,0); VFork:=Result16;
End;

Function SysRead(Fd: Integer; Var Buf; Count: Word): Integer;
Begin
 SetRegs(SYS_read,Fd,Count,Ofs(Buf)); SDS:=Seg(Buf); SysRead:=Result16;
End;

Function SysWrite(Fd: Integer; Var Buf; Count: Word): Integer;
Begin
 SetRegs(SYS_write,Fd,Count,Ofs(Buf)); SDS:=Seg(Buf); SysWrite:=Result16;
End;

Function SysOpen(Path: String; Flags, Mode: Word): Integer;
Begin
 SetRegs(SYS_open,Flags,Mode,0); SetPath(Path); SysOpen:=Result16;
End;

Function SysClose(Fd: Integer): Integer;
Begin
 SetRegs(SYS_close,Fd,0,0); SysClose:=Result16;
End;

Function WaitPid(Pid: Integer; Var Status: Integer; Options: Word): Integer;
{ wait (UNIX V7) etendu : Pid = -1 (n'importe quel fils) ou un fils precis,
  WNOHANG. Status : code de sortie * 256, ou numero du signal. }
Begin
 SetRegs(SYS_wait,Pid,Options,0); DoSys;
 If SysOk Then Begin WaitPid:=SAX; Status:=SDX End Else WaitPid:=-1;
End;

Function SysWait(Var Status: Integer): Integer;
Begin
 SysWait:=WaitPid(-1,Status,0);
End;

Function WIfExited(Status: Integer): Boolean;
Begin
 WIfExited:=Status And $7F=0;
End;

Function WExitStatus(Status: Integer): Integer;
Begin
 WExitStatus:=Hi(Status);
End;

Function WTermSig(Status: Integer): Integer;
Begin
 WTermSig:=Status And $7F;
End;

Function WCoreDump(Status: Integer): Boolean;
{ le processus termine par un signal a laisse un fichier core }
Begin
 WCoreDump:=Status And $80<>0;
End;

Function SysCreat(Path: String; Mode: Word): Integer;
Begin
 SetRegs(SYS_creat,0,Mode,0); SetPath(Path); SysCreat:=Result16;
End;

Function SysLink(OldPath, NewPath: String): Integer;
Begin
 SetRegs(SYS_link,0,0,0); SetPath(OldPath); SetPath2(NewPath);
 SysLink:=Result16;
End;

Function SysUnlink(Path: String): Integer;
Begin
 SetRegs(SYS_unlink,0,0,0); SetPath(Path); SysUnlink:=Result16;
End;

{ --- arguments d'exec ------------------------------------------------ }

Procedure ArgReset;
{ vide les listes argv et envp de ArgExec }
Begin
 ArgLen:=0; ArgN:=0; EnvN:=0; ArgV[0]:=Nil; EnvV[0]:=Nil;
End;

Function AddStr(S: String; Var P: Pointer): Boolean;
Var I: Integer;
Begin
 AddStr:=False;
 If ArgLen+Length(S)+1>SizeOf(ArgBlock) Then Exit;
 P:=@ArgBlock[ArgLen];
 For I:=1 To Length(S) Do ArgBlock[ArgLen+I-1]:=S[I];
 Inc(ArgLen,Length(S)); ArgBlock[ArgLen]:=#0; Inc(ArgLen);
 AddStr:=True;
End;

Function ArgAdd(S: String): Boolean;
Begin
 ArgAdd:=False;
 If ArgN>=High(ArgV) Then Exit;
 If Not AddStr(S,ArgV[ArgN]) Then Exit;
 Inc(ArgN); ArgV[ArgN]:=Nil; ArgAdd:=True;
End;

Function EnvAdd(S: String): Boolean;
Begin
 EnvAdd:=False;
 If EnvN>=High(EnvV) Then Exit;
 If Not AddStr(S,EnvV[EnvN]) Then Exit;
 Inc(EnvN); EnvV[EnvN]:=Nil; EnvAdd:=True;
End;

Function EnvInherit: Boolean;
{ ajoute l'environnement du processus (bloc d'environnement, PSP:2Ch) }
Var E,O: Word; S: String;
Begin
 EnvInherit:=True;
 E:=MemW[PrefixSeg:$2C]; O:=0;
 If E=0 Then Exit;
 While Mem[E:O]<>0 Do Begin
  S:='';
  While (Mem[E:O]<>0) And (Length(S)<255) Do Begin
   S:=S+Chr(Mem[E:O]); Inc(O);
  End;
  While Mem[E:O]<>0 Do Inc(O);
  Inc(O);
  If Not EnvAdd(S) Then Begin EnvInherit:=False; Exit End;
 End;
End;

Function Execve(Path: String; Var Argv; Var Envp): Integer;
{ exece : Argv et Envp sont des tableaux de pointeurs FAR sur des chaines
  ASCIIZ, termines par Nil }
Begin
 SetRegs(SYS_exece,0,Ofs(Envp),0); SetPath(Path);
 SSI:=Seg(Envp); SES:=Seg(Argv); SDI:=Ofs(Argv);
 Execve:=Result16;
End;

Function ArgExec(Path: String): Integer;
{ exece(Path, argv, envp) avec les listes de ArgAdd et EnvAdd }
Begin
 ArgExec:=Execve(Path,ArgV,EnvV);
End;

Function BuildArgs(Path: String; Args: String): Boolean;
{ argv[0] = Path, puis les mots de Args separes par des espaces (les
  guillemets regroupent), puis l'environnement courant. }
Var I: Integer; W: String; Quote: Boolean;
Begin
 BuildArgs:=False;
 ArgReset;
 If Not ArgAdd(Path) Then Exit;
 I:=1;
 While I<=Length(Args) Do Begin
  While (I<=Length(Args)) And (Args[I] In [' ',#9]) Do Inc(I);
  If I>Length(Args) Then Break;
  W:=''; Quote:=False;
  While (I<=Length(Args)) And (Quote Or Not (Args[I] In [' ',#9])) Do Begin
   If Args[I]='"' Then Quote:=Not Quote Else W:=W+Args[I];
   Inc(I);
  End;
  If Not ArgAdd(W) Then Exit;
 End;
 BuildArgs:=EnvInherit;
End;

Function Execv(Path: String; Args: String): Integer;
Begin
 If Not BuildArgs(Path,Args) Then Begin Errno:=E2BIG; Execv:=-1; Exit End;
 Execv:=ArgExec(Path);
End;

Function ArgCount: Integer;
{ argc, depuis la pile initiale (pointeur en PSP:4Ch) }
Begin
 If MemW[PrefixSeg:$4E]=0 Then ArgCount:=0
 Else ArgCount:=MemW[MemW[PrefixSeg:$4E]:MemW[PrefixSeg:$4C]];
End;

Function ArgStr(I: Integer): String;
{ argv[I] (argv[0] = nom du programme) }
Var S,O: Word;
Begin
 ArgStr:='';
 If (I<0) Or (I>=ArgCount) Then Exit;
 S:=MemW[PrefixSeg:$4E]; O:=MemW[PrefixSeg:$4C]+2+I*4;
 ArgStr:=FarString(MemW[S:O+2],MemW[S:O]);
End;

Function EnvCount: Integer;
Var S,O: Word; N: Integer;
Begin
 EnvCount:=0;
 S:=MemW[PrefixSeg:$4E];
 If S=0 Then Exit;
 O:=MemW[PrefixSeg:$4C]+2+(ArgCount+1)*4; N:=0;
 While (MemW[S:O]<>0) Or (MemW[S:O+2]<>0) Do Begin Inc(N); Inc(O,4) End;
 EnvCount:=N;
End;

Function EnvStr(I: Integer): String;
{ envp[I] (VAR=VALEUR) }
Var S,O: Word;
Begin
 EnvStr:='';
 If (I<0) Or (I>=EnvCount) Then Exit;
 S:=MemW[PrefixSeg:$4E]; O:=MemW[PrefixSeg:$4C]+2+(ArgCount+1+I)*4;
 EnvStr:=FarString(MemW[S:O+2],MemW[S:O]);
End;

Function SysChdir(Path: String): Integer;
Begin
 SetRegs(SYS_chdir,0,0,0); SetPath(Path); SysChdir:=Result16;
End;

Function SysTime: Longint;
Begin
 SetRegs(SYS_time,0,0,0); DoSys;
 SysTime:=Longint(SDX) Shl 16+SAX;
End;

Function SysSTime(T: Longint): Integer;
Begin
 SetRegs(SYS_stime,Word(T),Word(T Shr 16),0); SysSTime:=Result16;
End;

Function SysMknod(Path: String; Mode, Dev: Word): Integer;
Begin
 SetRegs(SYS_mknod,Dev,Mode,0); SetPath(Path); SysMknod:=Result16;
End;

Function SysChmod(Path: String; Mode: Word): Integer;
Begin
 SetRegs(SYS_chmod,0,Mode,0); SetPath(Path); SysChmod:=Result16;
End;

Function SysChown(Path: String; Uid, Gid: Integer): Integer;
Begin
 SetRegs(SYS_chown,Uid,Gid,0); SetPath(Path); SysChown:=Result16;
End;

Function SysLSeek(Fd: Integer; Offset: Longint; Whence: Word): Longint;
Begin
 SetRegs(SYS_lseek,Fd,Word(Offset Shr 16),Word(Offset)); SSI:=Whence;
 DoSys;
 If SysOk Then SysLSeek:=Longint(SDX) Shl 16+SAX Else SysLSeek:=-1;
End;

Function GetPid: Integer;
Begin
 SetRegs(SYS_getpid,0,0,0); GetPid:=Result16;
End;

Function GetPPid: Integer;
Begin
 SetRegs(SYS_getppid,0,0,0); GetPPid:=Result16;
End;

Function GetUid: Integer;
{ utilisateur reel (getuid rend aussi l'effectif dans DX, comme V7) }
Begin
 SetRegs(SYS_getuid,0,0,0); GetUid:=Result16;
End;

Function GetGid: Integer;
Begin
 SetRegs(SYS_getgid,0,0,0); GetGid:=Result16;
End;

Function GetEUid: Integer;
{ utilisateur effectif (bit set-uid) }
Begin
 SetRegs(SYS_getuid,0,0,0); DoSys; GetEUid:=SDX;
End;

Function GetEGid: Integer;
Begin
 SetRegs(SYS_getgid,0,0,0); DoSys; GetEGid:=SDX;
End;

Function SetUid(Uid: Integer): Integer;
Begin
 SetRegs(SYS_setuid,Uid,0,0); SetUid:=Result16;
End;

Function SetGid(Gid: Integer): Integer;
Begin
 SetRegs(SYS_setgid,Gid,0,0); SetGid:=Result16;
End;

Function SysMount(Special, Dir: String; FsType: Word): Integer;
Begin
 SetRegs(SYS_mount,FsType,0,0); SetPath(Special); SetPath2(Dir);
 SysMount:=Result16;
End;

Function SysUmount(Dir: String): Integer;
Begin
 SetRegs(SYS_umount,0,0,0); SetPath(Dir); SysUmount:=Result16;
End;

Function SysAlarm(Seconds: Word): Integer;
Begin
 SetRegs(SYS_alarm,Seconds,0,0); SysAlarm:=Result16;
End;

Function SysPause: Integer;
Begin
 SetRegs(SYS_pause,0,0,0); SysPause:=Result16;
End;

Function SysUtime(Path: String; ATime, MTime: Longint): Integer;
Var T: Array[0..1] Of Longint;
Begin
 T[0]:=ATime; T[1]:=MTime;
 SetRegs(SYS_utime,0,0,0); SetPath(Path); SES:=Seg(T); SDI:=Ofs(T);
 SysUtime:=Result16;
End;

Function SysAccess(Path: String; Mode: Word): Integer;
Begin
 SetRegs(SYS_access,Mode,0,0); SetPath(Path); SysAccess:=Result16;
End;

Function SysNice(Incr: Integer): Integer;
Begin
 SetRegs(SYS_nice,Incr,0,0); SysNice:=Result16;
End;

Function SysSync: Integer;
Begin
 SetRegs(SYS_sync,0,0,0); SysSync:=Result16;
End;

Function SysKill(Pid, Sig: Integer): Integer;
Begin
 SetRegs(SYS_kill,Pid,Sig,0); SysKill:=Result16;
End;

Function SysRename(OldPath, NewPath: String): Integer;
Begin
 SetRegs(SYS_rename,0,0,0); SetPath(OldPath); SetPath2(NewPath);
 SysRename:=Result16;
End;

Function SysMkdir(Path: String; Mode: Word): Integer;
Begin
 SetRegs(SYS_mkdir,0,Mode,0); SetPath(Path); SysMkdir:=Result16;
End;

Function SysRmdir(Path: String): Integer;
Begin
 SetRegs(SYS_rmdir,0,0,0); SetPath(Path); SysRmdir:=Result16;
End;

Function SysDup(Fd: Integer): Integer;
Begin
 SetRegs(SYS_dup,Fd,0,0); SysDup:=Result16;
End;

Function SysDup2(Fd, Fd2: Integer): Integer;
Begin
 SetRegs(SYS_dup2,Fd,Fd2,0); SysDup2:=Result16;
End;

Function SysPipe(Var ReadFd, WriteFd: Integer): Integer;
Begin
 SetRegs(SYS_pipe,0,0,0); DoSys;
 If SysOk Then Begin ReadFd:=SAX; WriteFd:=SDX; SysPipe:=0 End
 Else SysPipe:=-1;
End;

Function SysTimes(Var T: TTms): Longint;
Begin
 SetRegs(SYS_times,0,0,Ofs(T)); SDS:=Seg(T); DoSys;
 SysTimes:=Longint(SDX) Shl 16+SAX;
End;

Function SysSignal(Sig: Integer; Action: Pointer): Pointer;
{ Action : SIG_DFL, SIG_IGN ou @Gestionnaire ("Procedure G(Sig: Integer);
  Far;"). Rend l'action precedente (Ptr(0,$FFFF) en cas d'erreur). }
Begin
 SetRegs(SYS_signal,Sig,Ofs(Action^),Seg(Action^)); DoSys;
 If SysOk Then SysSignal:=Ptr(SDX,SAX) Else SysSignal:=Ptr(0,$FFFF);
End;

Function SysIoctl(Fd: Integer; Request: Word; Var Arg): Integer;
Begin
 SetRegs(SYS_ioctl,Fd,Request,Ofs(Arg)); SDS:=Seg(Arg);
 SysIoctl:=Result16;
End;

Function GTty(Fd: Integer; Var S: TSgttyb): Integer;
Begin
 GTty:=SysIoctl(Fd,TIOCGETP,S);
End;

Function STty(Fd: Integer; Var S: TSgttyb): Integer;
Begin
 STty:=SysIoctl(Fd,TIOCSETP,S);
End;

Function IsATty(Fd: Integer): Boolean;
Var S: TSgttyb;
Begin
 IsATty:=GTty(Fd,S)=0;
End;

Function SysUmask(Mask: Word): Word;
Begin
 SetRegs(SYS_umask,Mask,0,0); SysUmask:=Result16;
End;

Function SysReboot: Integer;
Begin
 SetRegs(SYS_reboot,0,0,0); SysReboot:=Result16;
End;

Function SysStat(Path: String; Var St: TStat): Integer;
Begin
 SetRegs(SYS_stat,0,0,0); SetPath(Path); SES:=Seg(St); SDI:=Ofs(St);
 SysStat:=Result16;
End;

Function SysFStat(Fd: Integer; Var St: TStat): Integer;
Begin
 SetRegs(SYS_fstat,Fd,0,0); SES:=Seg(St); SDI:=Ofs(St);
 SysFStat:=Result16;
End;

Function SysUname(Var U: TUtsName): Integer;
Begin
 SetRegs(SYS_uname,0,0,Ofs(U)); SDS:=Seg(U); SysUname:=Result16;
End;

Function SysGetDirEntries(Fd: Integer; Var Buf; Count: Word): Integer;
{ entrees de repertoire au format de 4.4BSD (struct dirent) }
Begin
 SetRegs(SYS_getdirentries,Fd,Count,Ofs(Buf)); SDS:=Seg(Buf);
 SysGetDirEntries:=Result16;
End;

Function SysGetDents(Fd: Integer; Var Buf; Count: Word): Integer;
Begin
 SysGetDents:=SysGetDirEntries(Fd,Buf,Count);
End;

Function SysNap(Ms: Word): Integer;
Begin
 SetRegs(SYS_nap,Ms,0,0); SysNap:=Result16;
End;

Function SysYield: Integer;
Begin
 SysYield:=SysNap(0);
End;

Function SysSleep(Seconds: Word): Integer;
{ sleep(3) : par tranches de 60 secondes au plus (appel nap) }
Var N: Word;
Begin
 SysSleep:=0;
 While Seconds>0 Do Begin
  If Seconds>60 Then N:=60 Else N:=Seconds;
  If SysNap(N*1000)<0 Then Begin SysSleep:=-1; Exit End;
  Dec(Seconds,N);
 End;
End;

Function SysGetCwd: String;
Var I: Integer; S: String;
Begin
 SetRegs(SYS_getcwd,0,255,Ofs(PathBuf)); SDS:=Seg(PathBuf);
 S:='';
 If Result16>=0 Then Begin
  I:=0;
  While (I<255) And (PathBuf[I]<>#0) Do Begin S:=S+PathBuf[I]; Inc(I) End;
 End;
 SysGetCwd:=S;
End;

Function SysProcInfo(Index: Integer; Var P: TProcInfo): Boolean;
Begin
 SetRegs(SYS_procinfo,Index,0,Ofs(P)); SDS:=Seg(P);
 SysProcInfo:=Result16>0;
End;

Function SysMemInfo(Var M: TMemInfo): Integer;
Begin
 SetRegs(SYS_meminfo,0,0,Ofs(M)); SDS:=Seg(M); SysMemInfo:=Result16;
End;

Function SysMountInfo(Index: Integer; Var M: TMountInfo): Boolean;
Begin
 SetRegs(SYS_mountinfo,Index,0,Ofs(M)); SDS:=Seg(M);
 SysMountInfo:=Result16>0;
End;

{ --- langue (variable d'environnement LANGUAGE) et messages ---------- }

Function SysGetEnv(Name: String): String;
{ valeur de la variable d'environnement Name ('' si elle n'existe pas) }
Var I: Integer; S: String;
Begin
 SysGetEnv:='';
 For I:=0 To EnvCount-1 Do Begin
  S:=EnvStr(I);
  If Copy(S,1,Length(Name)+1)=Name+'=' Then Begin
   SysGetEnv:=Copy(S,Length(Name)+2,255); Exit;
  End;
 End;
End;

Function SysLangOf(V: String): Integer;
{ numero de colonne de la langue V (FR 1, EN 2, GR 3, SP 4, IT 5); DE et ES
  sont admis pour GR et SP; toute autre valeur : le francais }
Const Codes='FRENGRSPITDEES';
Var P: Integer;
Begin
 SysLangOf:=1;
 If Length(V)<2 Then Exit;
 V:=UpCase(V[1])+UpCase(V[2]);
 P:=Pos(V,Codes);
 If (P=0) Or Not Odd(P) Then Exit;
 P:=(P+1) Div 2;
 If P=6 Then P:=3;
 If P=7 Then P:=4;
 SysLangOf:=P;
End;

Function SysLang: Integer;
Begin
 SysLang:=SysLangOf(SysGetEnv('LANGUAGE'));
End;

(* Messages en cinq langues (colonnes FR, EN, GR, SP, IT) : seulement pour
   les programmes qui declarent le symbole LANGERR (DEFINE) avant leur
   en-tete; les tables occupent environ 5 Ko du segment de donnees. Les
   autres commandes gardent des messages en francais. *)
{$IFDEF LANGERR}
Function PStr(P: PChar): String;
Var S: String;
Begin
 S:='';
 While P^<>#0 Do Begin S:=S+P^; Inc(P) End;
 PStr:=S;
End;

Const
 { messages des erreurs : colonnes FR, EN, GR (allemand), SP, IT }
 ErrMsg: Array[1..37,1..5] Of PChar = (
  ('Operation non permise','Operation not permitted',
   'Operation nicht erlaubt','Operacion no permitida',
   'Operazione non permessa'),
  ('Fichier ou repertoire inexistant','No such file or directory',
   'Datei oder Verzeichnis nicht gefunden',
   'No existe el archivo o directorio','File o directory inesistente'),
  ('Processus inexistant','No such process','Prozess nicht gefunden',
   'No existe el proceso','Processo inesistente'),
  ('Appel systeme interrompu','Interrupted system call',
   'Systemaufruf unterbrochen','Llamada al sistema interrumpida',
   'Chiamata di sistema interrotta'),
  ('Erreur d''entree/sortie','Input/output error','Ein-/Ausgabefehler',
   'Error de entrada/salida','Errore di input/output'),
  ('Peripherique inexistant','No such device or address',
   'Geraet nicht vorhanden','No existe el dispositivo',
   'Dispositivo inesistente'),
  ('Liste d''arguments trop longue','Argument list too long',
   'Argumentliste zu lang','Lista de argumentos demasiado larga',
   'Lista di argomenti troppo lunga'),
  ('Format d''executable invalide','Exec format error',
   'Ungueltiges Programmformat','Formato de ejecutable no valido',
   'Formato eseguibile non valido'),
  ('Descripteur de fichier invalide','Bad file descriptor',
   'Ungueltiger Dateideskriptor','Descriptor de archivo no valido',
   'Descrittore di file non valido'),
  ('Aucun processus fils','No child processes','Keine Kindprozesse',
   'No hay procesos hijos','Nessun processo figlio'),
  ('Ressource temporairement indisponible',
   'Resource temporarily unavailable',
   'Ressource vorlaeufig nicht verfuegbar',
   'Recurso temporalmente no disponible',
   'Risorsa temporaneamente non disponibile'),
  ('Memoire insuffisante','Out of memory','Nicht genug Speicher',
   'Memoria insuficiente','Memoria insufficiente'),
  ('Permission refusee','Permission denied','Zugriff verweigert',
   'Permiso denegado','Permesso negato'),
  ('Adresse invalide','Bad address','Ungueltige Adresse',
   'Direccion no valida','Indirizzo non valido'),
  ('Peripherique bloc requis','Block device required',
   'Blockgeraet erforderlich','Se requiere dispositivo de bloques',
   'Richiesto dispositivo a blocchi'),
  ('Peripherique ou ressource occupe','Device or resource busy',
   'Geraet oder Ressource belegt','Dispositivo o recurso ocupado',
   'Dispositivo o risorsa occupata'),
  ('Le fichier existe','File exists','Datei existiert bereits',
   'El archivo ya existe','Il file esiste'),
  ('Lien entre peripheriques','Cross-device link',
   'Link ueber Geraetegrenzen','Enlace entre dispositivos',
   'Collegamento tra dispositivi'),
  ('Peripherique inexistant','No such device','Geraet nicht vorhanden',
   'No existe el dispositivo','Dispositivo inesistente'),
  ('N''est pas un repertoire','Not a directory','Kein Verzeichnis',
   'No es un directorio','Non e una directory'),
  ('Est un repertoire','Is a directory','Ist ein Verzeichnis',
   'Es un directorio','E una directory'),
  ('Argument invalide','Invalid argument','Ungueltiges Argument',
   'Argumento no valido','Argomento non valido'),
  ('Table des fichiers pleine','File table overflow','Dateitabelle voll',
   'Tabla de archivos llena','Tabella dei file piena'),
  ('Trop de fichiers ouverts','Too many open files',
   'Zu viele offene Dateien','Demasiados archivos abiertos',
   'Troppi file aperti'),
  ('N''est pas un terminal','Not a typewriter','Kein Terminal',
   'No es un terminal','Non e un terminale'),
  ('Fichier texte occupe','Text file busy','Programmdatei belegt',
   'Archivo de texto ocupado','File di testo occupato'),
  ('Fichier trop gros','File too large','Datei zu gross',
   'Archivo demasiado grande','File troppo grande'),
  ('Plus d''espace sur le peripherique','No space left on device',
   'Kein Platz mehr auf dem Geraet','No queda espacio en el dispositivo',
   'Spazio esaurito sul dispositivo'),
  ('Deplacement illegal','Illegal seek','Ungueltiges Positionieren',
   'Busqueda no valida','Posizionamento non valido'),
  ('Systeme de fichiers en lecture seule','Read-only file system',
   'Dateisystem ist schreibgeschuetzt',
   'Sistema de archivos de solo lectura','File system in sola lettura'),
  ('Trop de liens','Too many links','Zu viele Links',
   'Demasiados enlaces','Troppi collegamenti'),
  ('Tube brise','Broken pipe','Unterbrochene Pipe','Tuberia rota',
   'Pipe interrotta'),
  ('Argument hors du domaine','Argument out of domain',
   'Argument ausserhalb des Bereichs','Argumento fuera de dominio',
   'Argomento fuori dominio'),
  ('Resultat hors limites','Result out of range',
   'Ergebnis ausserhalb des Bereichs','Resultado fuera de rango',
   'Risultato fuori intervallo'),
  ('Nom trop long','File name too long','Dateiname zu lang',
   'Nombre demasiado largo','Nome troppo lungo'),
  ('Repertoire non vide','Directory not empty','Verzeichnis nicht leer',
   'Directorio no vacio','Directory non vuota'),
  ('Fonction non implementee','Function not implemented',
   'Funktion nicht implementiert','Funcion no implementada',
   'Funzione non implementata'));
 { 'Erreur N' : mot devant le numero d'une erreur inconnue }
 ErrWord: Array[1..5] Of PChar = ('Erreur ','Error ','Fehler ','Error ',
   'Errore ');
 { messages des signaux (sh de V7) : lignes 1 a 15 = signaux 1 a 15 }
 SigMsg: Array[1..15,1..5] Of PChar = (
  ('Raccroche','Hangup','Aufgelegt','Colgado','Linea caduta'),
  ('','','','',''),
  ('Abandon','Quit','Abbruch','Salir','Uscita'),
  ('Instruction illegale','Illegal instruction','Ungueltiger Befehl',
   'Instruccion ilegal','Istruzione illegale'),
  ('Trappe','Trace/BPT trap','Trace-Falle','Trampa de traza',
   'Trap di traccia'),
  ('IOT','IOT trap','IOT-Falle','Trampa IOT','Trap IOT'),
  ('EMT','EMT trap','EMT-Falle','Trampa EMT','Trap EMT'),
  ('Exception arithmetique','Floating exception','Arithmetikfehler',
   'Excepcion aritmetica','Eccezione aritmetica'),
  ('Tue','Killed','Getoetet','Terminado a la fuerza','Ucciso'),
  ('Erreur de bus','Bus error','Busfehler','Error de bus','Errore di bus'),
  ('Erreur de segmentation','Segmentation fault','Speicherzugriffsfehler',
   'Fallo de segmentacion','Errore di segmentazione'),
  ('Appel systeme invalide','Bad system call','Ungueltiger Systemaufruf',
   'Llamada al sistema no valida','Chiamata di sistema non valida'),
  ('','','','',''),
  ('Alarme','Alarm clock','Alarm','Alarma','Allarme'),
  ('Termine','Terminated','Beendet','Terminado','Terminato'));

Function SysErrorText(E: Integer): String;
{ message de l'erreur E dans la langue de LANGUAGE }
Var S: String; R, L: Integer;
Begin
 L:=SysLang;
 R:=0;
 If (E>=1) And (E<=34) Then R:=E
 Else If E=ENAMETOOLONG Then R:=35
 Else If E=ENOTEMPTY Then R:=36
 Else If E=ENOSYS Then R:=37;
 If R>0 Then S:=PStr(ErrMsg[R,L])
 Else Begin Str(E,S); S:=PStr(ErrWord[L])+S End;
 SysErrorText:=S;
End;

Function SigName(Sig: Integer): String;
{ message du signal qui a termine un processus (comme sh de V7) }
Var S: String;
Begin
 If (Sig>=1) And (Sig<=15) Then S:=PStr(SigMsg[Sig,SysLang])
 Else Begin Str(Sig,S); S:='Signal '+S End;
 SigName:=S;
End;

{$ELSE}
Function SysErrorText(E: Integer): String;
Var S: String;
Begin
 Case E Of
  EPERM: S:='Operation non permise';
  ENOENT: S:='Fichier ou repertoire inexistant';
  ESRCH: S:='Processus inexistant';
  EINTR: S:='Appel systeme interrompu';
  EIO: S:='Erreur d''entree/sortie';
  ENXIO: S:='Peripherique inexistant';
  E2BIG: S:='Liste d''arguments trop longue';
  ENOEXEC: S:='Format d''executable invalide';
  EBADF: S:='Descripteur de fichier invalide';
  ECHILD: S:='Aucun processus fils';
  EAGAIN: S:='Ressource temporairement indisponible';
  ENOMEM: S:='Memoire insuffisante';
  EACCES: S:='Permission refusee';
  EFAULT: S:='Adresse invalide';
  ENOTBLK: S:='Peripherique bloc requis';
  EBUSY: S:='Peripherique ou ressource occupe';
  EEXIST: S:='Le fichier existe';
  EXDEV: S:='Lien entre peripheriques';
  ENODEV: S:='Peripherique inexistant';
  ENOTDIR: S:='N''est pas un repertoire';
  EISDIR: S:='Est un repertoire';
  EINVAL: S:='Argument invalide';
  ENFILE: S:='Table des fichiers pleine';
  EMFILE: S:='Trop de fichiers ouverts';
  ENOTTY: S:='N''est pas un terminal';
  ETXTBSY: S:='Fichier texte occupe';
  EFBIG: S:='Fichier trop gros';
  ENOSPC: S:='Plus d''espace sur le peripherique';
  ESPIPE: S:='Deplacement illegal';
  EROFS: S:='Systeme de fichiers en lecture seule';
  EMLINK: S:='Trop de liens';
  EPIPE: S:='Tube brise';
  EDOM: S:='Argument hors du domaine';
  ERANGE: S:='Resultat hors limites';
  ENAMETOOLONG: S:='Nom trop long';
  ENOSYS: S:='Fonction non implementee';
  ENOTEMPTY: S:='Repertoire non vide';
  Else Begin Str(E,S); S:='Erreur '+S End;
 End;
 SysErrorText:=S;
End;

Function SigName(Sig: Integer): String;
{ message du signal qui a termine un processus (comme sh de V7) }
Var S: String;
Begin
 Case Sig Of
  SIGHUP: S:='Raccroche';
  SIGINT: S:='';
  SIGQUIT: S:='Abandon';
  SIGILL: S:='Instruction illegale';
  SIGTRAP: S:='Trappe';
  SIGIOT: S:='IOT';
  SIGEMT: S:='EMT';
  SIGFPE: S:='Exception arithmetique';
  SIGKILL: S:='Tue';
  SIGBUS: S:='Erreur de bus';
  SIGSEGV: S:='Erreur de segmentation';
  SIGSYS: S:='Appel systeme invalide';
  SIGPIPE: S:='';
  SIGALRM: S:='Alarme';
  SIGTERM: S:='Termine';
  Else Begin Str(Sig,S); S:='Signal '+S End;
 End;
 SigName:=S;
End;

{$ENDIF}

{ --- signaux : trampoline ------------------------------------------- }

Procedure SigDispatch(Sig: Integer; Hd: Pointer); Far;
{ appelle le gestionnaire Hd en preservant l'etat de la libc (un signal
  peut arriver pendant la traduction d'un service DOS) }
Var
 A,B,C,D,E,F,G,H,I,J: Word;
 K,L,M,N,O,P,Q,R,S: Word;
 Er: Integer;
Begin
 A:=RAX; B:=RBX; C:=RCX; D:=RDX; E:=RSI; F:=RDI; G:=RBP; H:=RDS; I:=RES;
 J:=RFL; K:=SAX; L:=SBX; M:=SCX; N:=SDX; O:=SSI; P:=SDI; Q:=SDS; R:=SES;
 S:=SFL; Er:=Errno;
 Asm
  PUSH Sig
  CALL DWORD PTR Hd
 End;
 RAX:=A; RBX:=B; RCX:=C; RDX:=D; RSI:=E; RDI:=F; RBP:=G; RDS:=H; RES:=I;
 RFL:=J; SAX:=K; SBX:=L; SCX:=M; SDX:=N; SSI:=O; SDI:=P; SDS:=Q; SES:=R;
 SFL:=S; Errno:=Er;
End;

Procedure SigTrampoline; Assembler;
{ point d'entree des gestionnaires, prepare par le noyau : sur la pile, le
  numero du signal, l'adresse FAR du gestionnaire, puis les registres du
  programme interrompu (AX, BX, CX, DX, SI, DI, BP, ES, DS, IP, CS, FLAGS) }
Asm
 MOV BP,SP
 MOV AX,SEG @DATA
 MOV DS,AX
 MOV AX,[BP]
 PUSH AX
 MOV AX,[BP+4]
 PUSH AX
 MOV AX,[BP+2]
 PUSH AX
 CALL SigDispatch
 ADD SP,6
 POP AX
 POP BX
 POP CX
 POP DX
 POP SI
 POP DI
 POP BP
 POP ES
 POP DS
 IRET
End;

{ ------------------------------------------------------------------ }
{ Traduction des services DOS (INT 21h) en appels systeme LINUX-0     }
{ ------------------------------------------------------------------ }

Function UnixPath(S: String): String;
{ Chemin DOS -> chemin UNIX : unite "X:" retiree, "\" -> "/", noms de
  peripheriques DOS -> /dev. }
Var I: Integer; U: String;
Begin
 If (Length(S)>=2) And (S[2]=':') Then Delete(S,1,2);
 For I:=1 To Length(S) Do If S[I]='\' Then S[I]:='/';
 U:=S;
 For I:=1 To Length(U) Do U[I]:=UpCase(U[I]);
 If (U='NUL') Or (U='/DEV/NUL') Or (U='PRN') Or (U='LPT1') Or (U='AUX') Or
   (U='COM1') Then S:='/dev/null'
 Else If (U='CON') Or (U='/DEV/CON') Then S:='/dev/tty';
 If S='' Then S:='.';
 UnixPath:=S;
End;

Procedure SetCarry(Err: Word);
Begin
 RAX:=Err; RFL:=RFL Or 1;
End;

Function DosError(E: Integer): Word;
{ errno -> code d'erreur DOS }
Begin
 Case E Of
  ENOENT: DosError:=2;
  ENOTDIR: DosError:=3;
  EMFILE,ENFILE: DosError:=4;
  EACCES,EPERM,EISDIR,EEXIST,EROFS,ENOTEMPTY,EBUSY: DosError:=5;
  EBADF: DosError:=6;
  ENOMEM: DosError:=8;
  ENOEXEC: DosError:=11;
  ENOSPC: DosError:=29;
  EXDEV: DosError:=17;
  Else DosError:=31;
 End;
End;

Procedure Fail;
Begin
 SetCarry(DosError(Errno));
End;

Function FileExistsU(S: String): Boolean;
Var St: TStat;
Begin
 FileExistsU:=(SysStat(S,St)=0) And (St.Mode And S_IFMT<>S_IFDIR);
End;

Function ExecPath(S: String): String;
{ Programme DOS (X.EXE, X.COM) -> executable LINUX-0 (X) si besoin. }
Var U: String; I: Integer;
Begin
 ExecPath:=S;
 If FileExistsU(S) Then Exit;
 U:=S; For I:=1 To Length(U) Do U[I]:=UpCase(U[I]);
 If (Length(S)>4) And ((Copy(U,Length(U)-3,4)='.EXE') Or
   (Copy(U,Length(U)-3,4)='.COM')) Then Begin
  U:=Copy(S,1,Length(S)-4);
  If FileExistsU(U) Then Begin ExecPath:=U; Exit End;
  For I:=1 To Length(U) Do U[I]:=Chr(Ord(U[I]) Or (Ord(U[I] In ['A'..'Z'])*32));
  If FileExistsU(U) Then ExecPath:=U;
 End;
End;

Procedure DosExec;
{ 4B00h : DS:DX programme, ES:BX bloc de parametres -> vfork, exece, wait.
  Comme system(3) de UNIX V7, le pere ignore SIGINT et SIGQUIT pendant
  l'execution du fils (qui les recoit, lui, avec l'action par defaut). }
Var Path,Tail: String; TSeg,TOfs: Word; L,I: Integer; Pid,St,W: Integer;
  OldInt,OldQuit: Pointer;
Begin
 Path:=ExecPath(UnixPath(FarString(RDS,RDX)));
 TOfs:=MemW[RES:RBX+2]; TSeg:=MemW[RES:RBX+4];
 L:=Mem[TSeg:TOfs]; Tail:='';
 For I:=1 To L Do If Mem[TSeg:TOfs+I]<>13 Then Tail:=Tail+Chr(Mem[TSeg:TOfs+I]);
 If Not FileExistsU(Path) Then Begin SetCarry(2); Exit End;
 If Not BuildArgs(Path,Tail) Then Begin SetCarry(10); Exit End;
 OldInt:=SysSignal(SIGINT,SIG_IGN); OldQuit:=SysSignal(SIGQUIT,SIG_IGN);
 Pid:=VFork;
 If Pid=0 Then Begin
  SysSignal(SIGINT,OldInt); SysSignal(SIGQUIT,OldQuit);
  ArgExec(Path);
  SysExit(127);
 End;
 If Pid>0 Then
  Repeat W:=WaitPid(Pid,St,0) Until (W=Pid) Or ((W<0) And (Errno<>EINTR));
 SysSignal(SIGINT,OldInt); SysSignal(SIGQUIT,OldQuit);
 If (Pid<0) Or (W<0) Then Begin Fail; Exit End;
 { DOS (4Dh) : AH = 0 fin normale, 1 interruption (^C); AL = code }
 If WTermSig(St)<>0 Then LastExit:=$100 Or WTermSig(St)
 Else LastExit:=WExitStatus(St);
 RAX:=0;
End;

Function Lower(C: Char): Char;
Begin
 If C In ['A'..'Z'] Then Lower:=Chr(Ord(C)+32) Else Lower:=C;
End;

Function Match(Pat, Name: String): Boolean;
{ Correspondance DOS : * et ?, sans tenir compte de la casse; "*.*"
  correspond aussi aux noms sans point. }
Var P,N: Integer;
 Function M(P,N: Integer): Boolean;
 Begin
  While P<=Length(Pat) Do Begin
   If Pat[P]='*' Then Begin
    While (P<=Length(Pat)) And (Pat[P]='*') Do Inc(P);
    If P>Length(Pat) Then Begin M:=True; Exit End;
    While N<=Length(Name)+1 Do Begin
     If M(P,N) Then Begin M:=True; Exit End;
     Inc(N);
    End;
    M:=False; Exit;
   End;
   If N>Length(Name) Then Begin
    { "X.*" correspond a "X" }
    If (Pat[P]='.') And (P<Length(Pat)) And (Pat[P+1]='*') Then Begin
     Inc(P,2); Continue;
    End;
    M:=(Pat[P]='.') And (P=Length(Pat)); Exit;
   End;
   If (Pat[P]<>'?') And (Lower(Pat[P])<>Lower(Name[N])) Then Begin
    M:=False; Exit;
   End;
   Inc(P); Inc(N);
  End;
  M:=N>Length(Name);
 End;
Begin
 If (Pat='*.*') Or (Pat='*') Then Begin Match:=True; Exit End;
 P:=1; N:=1;
 Match:=M(P,N);
End;

Function DosTime(T: Longint): Longint;
{ secondes depuis 1970 -> date/heure DOS compactee }
Var Days,Secs: Longint; Y,M,D: Word; DM: Word;
Begin
 If T<315532800 Then T:=315532800;
 Days:=T Div 86400; Secs:=T Mod 86400;
 Y:=1970;
 While True Do Begin
  If (Y Mod 4=0) Then DM:=366 Else DM:=365;
  If Days<DM Then Break;
  Dec(Days,DM); Inc(Y);
 End;
 M:=1;
 While True Do Begin
  Case M Of
   1,3,5,7,8,10,12: DM:=31;
   4,6,9,11: DM:=30;
   Else If Y Mod 4=0 Then DM:=29 Else DM:=28;
  End;
  If Days<DM Then Break;
  Dec(Days,DM); Inc(M);
 End;
 D:=Days+1;
 DosTime:=(Longint(Y-1980) Shl 25) Or (Longint(M) Shl 21) Or
   (Longint(D) Shl 16) Or ((Secs Div 3600) Shl 11) Or
   (((Secs Mod 3600) Div 60) Shl 5) Or ((Secs Mod 60) Div 2);
End;

Procedure FindRead(K: Integer);
{ Entree suivante de la recherche K, placee dans la DTA }
Var
 N,Pos,RecLen,I: Integer;
 Name,Full: String;
 St: TStat;
 A: Byte;
 T: Longint;
Begin
 With Finds[K] Do
 While True Do Begin
  If BufPos>=BufLen Then Begin
   N:=SysGetDirEntries(Fd,Buf,SizeOf(Buf));
   If N<=0 Then Begin
    SysClose(Fd); Used:=False; SetCarry(18); Exit;
   End;
   BufLen:=N; BufPos:=0;
  End;
  Pos:=BufPos;
  RecLen:=Buf[Pos+4]+Buf[Pos+5]*256;
  If RecLen<8 Then RecLen:=BufLen-Pos;
  Inc(BufPos,RecLen);
  Name:='';
  For I:=0 To Buf[Pos+7]-1 Do
   If Length(Name)<255 Then Name:=Name+Chr(Buf[Pos+8+I]);
  If Not Match(Pattern,Name) Then Continue;
  If Dir='' Then Full:=Name Else
  If Dir[Length(Dir)]='/' Then Full:=Dir+Name Else Full:=Dir+'/'+Name;
  If SysStat(Full,St)<>0 Then Continue;
  A:=$20;
  If St.Mode And S_IFMT=S_IFDIR Then A:=$10;
  If (Name[1]='.') And (Name<>'.') And (Name<>'..') Then A:=A Or 2;
  If (A And $10<>0) And (Attr And $10=0) Then Continue;
  If (A And 2<>0) And (Attr And 2=0) Then Continue;
  If St.Mode And $80=0 Then A:=A Or 1;
  { DTA : 21 octets reserves (0 = numero de recherche), attribut, heure,
    taille, nom ASCIIZ (13 octets) }
  Mem[DtaSeg:DtaOfs]:=K; Mem[DtaSeg:DtaOfs+1]:=$55;
  Mem[DtaSeg:DtaOfs+21]:=A;
  T:=DosTime(St.MTime);
  MemW[DtaSeg:DtaOfs+22]:=Word(T); MemW[DtaSeg:DtaOfs+24]:=Word(T Shr 16);
  MemW[DtaSeg:DtaOfs+26]:=Word(St.Size);
  MemW[DtaSeg:DtaOfs+28]:=Word(St.Size Shr 16);
  If Length(Name)>12 Then Name[0]:=#12;
  For I:=1 To Length(Name) Do Mem[DtaSeg:DtaOfs+29+I]:=Ord(Name[I]);
  Mem[DtaSeg:DtaOfs+30+Length(Name)]:=0;
  RAX:=0;
  Exit;
 End;
End;

Procedure DosFindFirst;
Var S,D,P: String; I,K: Integer;
Begin
 S:=UnixPath(FarString(RDS,RDX));
 I:=Length(S);
 While (I>0) And (S[I]<>'/') Do Dec(I);
 If I=0 Then Begin D:=''; P:=S End
 Else Begin D:=Copy(S,1,I); P:=Copy(S,I+1,255); If D<>'/' Then Dec(D[0]) End;
 If P='' Then P:='*';
 { sans joker : recherche d'un nom precis }
 K:=FindNo; FindNo:=(FindNo+1) And 3;
 If Finds[K].Used Then SysClose(Finds[K].Fd);
 Finds[K].Used:=False;
 If D='' Then Finds[K].Fd:=SysOpen('.',O_RDONLY,0)
 Else Finds[K].Fd:=SysOpen(D,O_RDONLY,0);
 If Finds[K].Fd<0 Then Begin SetCarry(3); Exit End;
 Finds[K].Used:=True; Finds[K].Attr:=Lo(RCX); Finds[K].Dir:=D;
 Finds[K].BufLen:=0; Finds[K].BufPos:=0;
 Finds[K].Pattern:=P;
 FindRead(K);
 If (RFL And 1<>0) Then RAX:=2;
End;

Procedure DosFindNext;
Var K: Integer;
Begin
 K:=Mem[DtaSeg:DtaOfs];
 If (K>3) Or (Mem[DtaSeg:DtaOfs+1]<>$55) Or Not Finds[K].Used Then Begin
  SetCarry(18); Exit;
 End;
 FindRead(K);
End;

{ Gestion du tas : blocs de paragraphes, en-tete d'un paragraphe
  (octet 0 : 'M' utilise / 'Z' libre, mots 1 : taille en paragraphes
  donnees comprises, 3 : signature 'U0') }
Procedure HeapInit;
{ tas : de PSP:48h a la fin de l'image (PSP:2), eventuellement vide }
Begin
 HeapFirst:=MemW[PrefixSeg:$48];
 HeapTop:=MemW[PrefixSeg:2];
 If (HeapFirst=0) Or (HeapFirst>HeapTop) Then Begin
  HeapFirst:=0; Exit;
 End;
 If HeapFirst=HeapTop Then Exit;
 Mem[HeapFirst:0]:=Ord('Z'); MemW[HeapFirst:1]:=HeapTop-HeapFirst;
 MemW[HeapFirst:3]:=$3055;
End;

Function HeapGrow(Need: Word): Boolean;
{ agrandit le tas d'au moins Need paragraphes (appel systeme break, comme
  sbrk de UNIX) : nouveau bloc libre a la fin, fusionne avec le dernier }
Var Inc_: Word;
Begin
 HeapGrow:=False;
 If (HeapFirst=0) Or (Need>$F000) Then Exit;
 Inc_:=(Need+1+255) And $FF00;     { par 4 Ko }
 If Longint(HeapTop)+Inc_>$A000 Then Exit;
 SetRegs(SYS_break,HeapTop+Inc_,0,0);
 If Result16=-1 Then Exit;
 Mem[HeapTop:0]:=Ord('Z'); MemW[HeapTop:1]:=Inc_; MemW[HeapTop:3]:=$3055;
 HeapTop:=HeapTop+Inc_; MemW[PrefixSeg:2]:=HeapTop;
 HeapGrow:=True;
End;

Procedure HeapMerge;
Var S,N: Word;
Begin
 S:=HeapFirst;
 While (S<>0) And (S<HeapTop) Do Begin
  N:=S+MemW[S:1];
  If (Mem[S:0]=Ord('Z')) And (N<HeapTop) And (Mem[N:0]=Ord('Z')) Then
   MemW[S:1]:=MemW[S:1]+MemW[N:1]
  Else S:=N;
 End;
End;

Procedure DosAlloc;
{ 48h : BX paragraphes -> AX segment; BX = plus grand bloc si echec. Sans
  bloc assez grand, le tas est agrandi (break) puis la recherche reprise. }
Var S,Best,Need,Sz: Word; Grown: Boolean;
Begin
 If HeapFirst=0 Then Begin RBX:=0; SetCarry(8); Exit End;
 Need:=RBX+1; If RBX=$FFFF Then Need:=$FFFF;
 Grown:=False;
 Repeat
 HeapMerge;
 S:=HeapFirst; Best:=0;
 While S<HeapTop Do Begin
  Sz:=MemW[S:1];
  If Mem[S:0]=Ord('Z') Then Begin
   If (Sz>=Need) And (Need<>$FFFF) Then Begin
    If Sz>Need+1 Then Begin
     Mem[S+Need:0]:=Ord('Z'); MemW[S+Need:1]:=Sz-Need;
     MemW[S+Need:3]:=$3055;
     MemW[S:1]:=Need;
    End;
    Mem[S:0]:=Ord('M'); MemW[S:3]:=$3055;
    RAX:=S+1; Exit;
   End;
   If Sz-1>Best Then Best:=Sz-1;
  End;
  S:=S+Sz;
 End;
 If Grown Or (Need=$FFFF) Then Break;
 Grown:=True;
 If Not HeapGrow(Need) Then Break;
 Until False;
 RBX:=Best; SetCarry(8);
End;

Procedure DosFree;
{ 49h : ES = segment du bloc }
Var S: Word;
Begin
 S:=RES-1;
 If (HeapFirst=0) Or (S<HeapFirst) Or (S>=HeapTop) Or (MemW[S:3]<>$3055) Then
 Begin
  SetCarry(9); Exit;
 End;
 Mem[S:0]:=Ord('Z'); HeapMerge;
End;

Procedure DosResize;
{ 4Ah : ES = segment, BX = nouvelle taille }
Var S,Sz,Need,N: Word;
Begin
 If RES=PrefixSeg Then Exit; { bloc du programme : accepte sans effet }
 S:=RES-1;
 If (HeapFirst=0) Or (S<HeapFirst) Or (S>=HeapTop) Or (MemW[S:3]<>$3055) Then
 Begin
  SetCarry(9); Exit;
 End;
 HeapMerge;
 Sz:=MemW[S:1]; Need:=RBX+1;
 If Need<=Sz Then Begin
  If Sz>Need+1 Then Begin
   Mem[S+Need:0]:=Ord('Z'); MemW[S+Need:1]:=Sz-Need; MemW[S+Need:3]:=$3055;
   MemW[S:1]:=Need; HeapMerge;
  End;
  Exit;
 End;
 N:=S+Sz;
 If (N<HeapTop) And (Mem[N:0]=Ord('Z')) And (Sz+MemW[N:1]>=Need) Then Begin
  MemW[S:1]:=Sz+MemW[N:1];
  If MemW[S:1]>Need+1 Then Begin
   Mem[S+Need:0]:=Ord('Z'); MemW[S+Need:1]:=MemW[S:1]-Need;
   MemW[S+Need:3]:=$3055; MemW[S:1]:=Need;
  End;
  Exit;
 End;
 RBX:=Sz-1; If N<HeapTop Then If Mem[N:0]=Ord('Z') Then Inc(RBX,MemW[N:1]);
 SetCarry(8);
End;

Function ReadKey(DoEcho: Boolean): Byte;
{ un caractere de l'entree standard : terminal en mode RAW sans echo le
  temps de la lecture (TIOCSETN, sans perdre les frappes en avance) }
Var Old,New: TSgttyb; Tty: Boolean; B: Byte; N: Integer;
Begin
 If KbdAhead>=0 Then Begin ReadKey:=KbdAhead; KbdAhead:=-1; Exit End;
 Tty:=SysIoctl(0,TIOCGETP,Old)=0;
 If Tty Then Begin
  New:=Old; New.Flags:=(New.Flags Or RAW) And Not ECHO;
  SysIoctl(0,TIOCSETN,New);
 End;
 N:=SysRead(0,B,1);
 If Tty Then SysIoctl(0,TIOCSETN,Old);
 If N<=0 Then B:=26;
 If DoEcho And (B>=32) Then SysWrite(1,B,1);
 ReadKey:=B;
End;

Function KeyReady: Boolean;
Var N: Integer;
Begin
 If KbdAhead>=0 Then Begin KeyReady:=True; Exit End;
 N:=0;
 If SysIoctl(0,FIONREAD,N)<0 Then N:=0;
 KeyReady:=N>0;
End;

Procedure DateOf(Var Y,M,D,W,H,Mi,S: Word);
Var T,Days: Longint; DM: Word;
Begin
 T:=SysTime;
 Days:=T Div 86400; W:=(Days+4) Mod 7;
 H:=(T Mod 86400) Div 3600; Mi:=(T Mod 3600) Div 60; S:=T Mod 60;
 Y:=1970;
 While True Do Begin
  If Y Mod 4=0 Then DM:=366 Else DM:=365;
  If Days<DM Then Break;
  Dec(Days,DM); Inc(Y);
 End;
 M:=1;
 While True Do Begin
  Case M Of
   1,3,5,7,8,10,12: DM:=31;
   4,6,9,11: DM:=30;
   Else If Y Mod 4=0 Then DM:=29 Else DM:=28;
  End;
  If Days<DM Then Break;
  Dec(Days,DM); Inc(M);
 End;
 D:=Days+1;
End;

Procedure DosDiskFree;
{ 36h : unite 0 (par defaut) ou 3 (C:) = systeme de fichiers du repertoire
  courant (racine sinon); grappes de 1 Ko }
Var M: TMountInfo; I,Best,L: Integer; Cwd: String; T,F: Longint;
Begin
 If Not (Lo(RDX) In [0,3]) Then Begin RAX:=$FFFF; Exit End;
 Cwd:=SysGetCwd; Best:=0; L:=-1;
 For I:=1 To 8 Do
  If SysMountInfo(I,M) Then
   If (M.Dir='/') Or (Copy(Cwd,1,Length(M.Dir))=M.Dir) Then
    If Length(M.Dir)>L Then Begin
     Best:=I; L:=Length(M.Dir); T:=M.Blocks; F:=M.Free;
    End;
 If Best=0 Then Begin RAX:=$FFFF; Exit End;
 If T>65535 Then Begin T:=65535 End;
 If F>T Then F:=T;
 RAX:=2; RCX:=512; RBX:=F; RDX:=T;
End;

Procedure DosService;
{ Traduit le service DOS dont les registres sont dans RAX..RFL }
Var
 AH,AL: Byte;
 Fd,N,I,Flags: Integer;
 S,T: String;
 St: TStat;
 L: Longint;
 B: Byte;
 Y,M,D,W,H,Mi,Se: Word;
Begin
 AH:=Hi(RAX); AL:=Lo(RAX); RFL:=RFL And Not 1;
 Case AH Of
  $00: SysExit(0);
  $01: Begin RAX:=(RAX And $FF00) Or ReadKey(True) End;
  $02: Begin B:=Lo(RDX); If B=10 Then Begin B:=10; SysWrite(1,B,1) End
       Else If B<>13 Then SysWrite(1,B,1) End;
  $06: If Lo(RDX)=$FF Then Begin
        If KeyReady Then Begin
         RAX:=(RAX And $FF00) Or ReadKey(False); RFL:=RFL And Not $40;
        End Else Begin RAX:=RAX And $FF00; RFL:=RFL Or $40 End;
       End Else Begin B:=Lo(RDX); If B<>13 Then SysWrite(1,B,1) End;
  $07,$08: RAX:=(RAX And $FF00) Or ReadKey(False);
  $09: Begin
        N:=0;
        While (N<4096) And (Mem[RDS:RDX+N]<>Ord('$')) Do Inc(N);
        For I:=0 To N-1 Do Begin
         B:=Mem[RDS:RDX+I];
         If B<>13 Then SysWrite(1,B,1);
        End;
       End;
  $0A: Begin
        { lecture d'une ligne : DS:DX tampon (taille, lus, caracteres) }
        N:=SysRead(0,DirBuf,Mem[RDS:RDX]);
        If N<0 Then N:=0;
        I:=0;
        While (I<N) And (DirBuf[I]<>10) And (DirBuf[I]<>13) Do Begin
         Mem[RDS:RDX+2+I]:=DirBuf[I]; Inc(I);
        End;
        Mem[RDS:RDX+1]:=I; Mem[RDS:RDX+2+I]:=13;
       End;
  $0B: If KeyReady Then RAX:=(RAX And $FF00) Or $FF Else RAX:=RAX And $FF00;
  $0C: Begin
        While KeyReady Do ReadKey(False);
        If AL In [1,6,7,8,$A] Then Begin RAX:=(RAX And $FF) Or (AL Shl 8);
          DosService; End;
       End;
  $0D: SysSync;
  $0E: RAX:=(RAX And $FF00) Or 26;
  $19: RAX:=(RAX And $FF00) Or 2;
  $1A: Begin DtaSeg:=RDS; DtaOfs:=RDX End;
  $2F: Begin RES:=DtaSeg; RBX:=DtaOfs End;
  $25: ; { vecteurs geres par le noyau : sans effet }
  $35: Begin RBX:=MemW[0:AL*4]; RES:=MemW[0:AL*4+2] End;
  $2A: Begin DateOf(Y,M,D,W,H,Mi,Se); RCX:=Y; RDX:=M*256+D;
         RAX:=(RAX And $FF00) Or W End;
  $2C: Begin DateOf(Y,M,D,W,H,Mi,Se); RCX:=H*256+Mi; RDX:=Se*256 End;
  $2B,$2D: RAX:=RAX And $FF00;
  $2E,$54: RAX:=RAX And $FF00;
  $30: Begin RAX:=$0005; RBX:=$FF00; RCX:=0 End; { version 5.0 }
  $33: RDX:=RDX And $FF00;
  $36: DosDiskFree;
  $39: If SysMkdir(UnixPath(FarString(RDS,RDX)),$1ED)<0 Then Fail;
  $3A: If SysRmdir(UnixPath(FarString(RDS,RDX)))<0 Then Fail;
  $3B: If SysChdir(UnixPath(FarString(RDS,RDX)))<0 Then SetCarry(3);
  $3C,$5B: Begin
        Flags:=O_RDWR Or O_CREAT Or O_TRUNC;
        If AH=$5B Then Flags:=O_RDWR Or O_CREAT Or O_EXCL;
        Fd:=SysOpen(UnixPath(FarString(RDS,RDX)),Flags,$1A4);
        If Fd<0 Then Fail Else RAX:=Fd;
       End;
  $3D: Begin
        Fd:=SysOpen(UnixPath(FarString(RDS,RDX)),AL And 3,0);
        If Fd<0 Then Fail Else RAX:=Fd;
       End;
  $3E: If SysClose(RBX)<0 Then SetCarry(6);
  $3F: Begin
        N:=SysRead(RBX,Mem[RDS:RDX],RCX);
        If N<0 Then Fail Else RAX:=N;
       End;
  $40: Begin
        If RCX=0 Then Begin
         { ecriture de 0 octet : troncature a la position courante }
         RAX:=0;
        End Else Begin
         N:=SysWrite(RBX,Mem[RDS:RDX],RCX);
         If N<0 Then Fail Else RAX:=N;
        End;
       End;
  $41: If SysUnlink(UnixPath(FarString(RDS,RDX)))<0 Then Fail;
  $42: Begin
        L:=Longint(RCX) Shl 16+RDX;
        { DOS : un deplacement absolu de 2 Go ou plus (negatif ici) est un
          deplacement apres la fin du fichier, sans erreur }
        If (AL=SEEK_SET) And (L<0) Then L:=SysLSeek(RBX,0,SEEK_END)
        Else L:=SysLSeek(RBX,L,AL);
        If L<0 Then Fail Else Begin RAX:=Word(L); RDX:=Word(L Shr 16) End;
       End;
  $43: Begin
        S:=UnixPath(FarString(RDS,RDX));
        If SysStat(S,St)<0 Then Fail
        Else If AL=0 Then Begin
         RCX:=$20;
         If St.Mode And S_IFMT=S_IFDIR Then RCX:=$10;
         If St.Mode And $80=0 Then RCX:=RCX Or 1;
         RAX:=RCX;
        End Else Begin
         If RCX And 1<>0 Then SysChmod(S,St.Mode And $16D)
         Else SysChmod(S,St.Mode Or $80);
        End;
       End;
  $44: Case AL Of
        0: Begin
            If IsATty(RBX) Then RDX:=$80D3 Else If SysFStat(RBX,St)<0 Then Fail
            Else RDX:=0;
            RAX:=RDX;
           End;
        1: ;
        6: Begin
            If IsATty(RBX) Then Begin
             If KeyReady Then RAX:=$FF Else RAX:=0;
            End Else RAX:=$FF;
           End;
        7: RAX:=$FF;
        8: RAX:=1;
        Else SetCarry(1);
       End;
  $45: Begin N:=SysDup(RBX); If N<0 Then Fail Else RAX:=N End;
  $46: If SysDup2(RBX,RCX)<0 Then Fail;
  $47: Begin
        S:=SysGetCwd;
        If (S<>'') And (S[1]='/') Then Delete(S,1,1);
        For I:=1 To Length(S) Do Mem[RDS:RSI+I-1]:=Ord(S[I]);
        Mem[RDS:RSI+Length(S)]:=0;
       End;
  $48: DosAlloc;
  $49: DosFree;
  $4A: DosResize;
  $4B: If AL=0 Then DosExec Else SetCarry(1);
  $4C: SysExit(AL);
  $4D: Begin RAX:=LastExit; LastExit:=0 End;
  $4E: DosFindFirst;
  $4F: DosFindNext;
  $50: ;
  $51,$62: RBX:=PrefixSeg;
  $56: If SysRename(UnixPath(FarString(RDS,RDX)),
          UnixPath(FarString(RES,RDI)))<0 Then Fail;
  $57: Begin
        If AL=0 Then Begin
         If SysFStat(RBX,St)<0 Then Fail Else Begin
          L:=DosTime(St.MTime); RCX:=Word(L); RDX:=Word(L Shr 16);
         End;
        End;
       End;
  $59: Begin RAX:=0; RBX:=0; RCX:=0 End;
  $5A: Begin
        { fichier temporaire : DS:DX repertoire termine par \ }
        S:=UnixPath(FarString(RDS,RDX));
        If (S<>'') And (S[Length(S)]<>'/') Then S:=S+'/';
        I:=0;
        Repeat
         Str(GetPid*100+I,T); T:=S+'TMP'+T+'.$$$'; Inc(I);
         Fd:=SysOpen(T,O_RDWR Or O_CREAT Or O_EXCL,$1A4);
        Until (Fd>=0) Or (I>99);
        If Fd<0 Then Fail Else Begin
         RAX:=Fd;
         T:=Copy(T,Length(S)+1,255);
         N:=0; While Mem[RDS:RDX+N]<>0 Do Inc(N);
         For I:=1 To Length(T) Do Mem[RDS:RDX+N+I-1]:=Ord(T[I]);
         Mem[RDS:RDX+N+Length(T)]:=0;
        End;
       End;
  $63,$65,$66,$38: SetCarry(1);
  Else SetCarry(1);
 End;
End;

Procedure DosEntry; Assembler;
{ Point d'entree INT 21h du processus : FLAGS, CS, IP sur la pile. }
Asm
 PUSH DS
 PUSH AX
 MOV AX,SEG @DATA
 MOV DS,AX
 POP AX
 MOV RAX,AX
 POP AX
 MOV RDS,AX
 MOV RBX,BX
 MOV RCX,CX
 MOV RDX,DX
 MOV RSI,SI
 MOV RDI,DI
 MOV RBP,BP
 MOV RES,ES
 MOV BP,SP
 MOV AX,[BP+4]
 MOV RFL,AX
 STI
 CLD
 CALL DosService
 MOV AX,SEG @DATA
 MOV DS,AX
 MOV BP,SP
 MOV AX,[BP+4]
 AND AX,0FFBEh
 MOV BX,RFL
 AND BX,41h
 OR AX,BX
 MOV [BP+4],AX
 MOV BX,RBX
 MOV CX,RCX
 MOV DX,RDX
 MOV SI,RSI
 MOV DI,RDI
 MOV ES,RES
 MOV BP,RBP
 MOV AX,RDS
 PUSH AX
 MOV AX,RAX
 POP DS
 IRET
End;

Procedure Int20Entry; Assembler;
Asm
 MOV AX,SEG @DATA
 MOV DS,AX
 MOV SAX,SYS_exit
 MOV SBX,0
 CALL DoSys
End;

Begin
 KbdAhead:=-1; FindNo:=0; LastExit:=0;
 DtaSeg:=PrefixSeg; DtaOfs:=$80;
 SIG_DFL:=Nil; SIG_IGN:=Ptr(0,1);
 ArgReset;
 HeapInit;
 { enregistre la couche libc aupres du noyau (vecteur 21h du processus) et
   la trampoline des gestionnaires de signaux }
 SetRegs(SYS_setdos,Ofs(DosEntry),Seg(DosEntry),0);
 DoSys;
 SetRegs(SYS_sigtramp,Ofs(SigTrampoline),Seg(SigTrampoline),0);
 DoSys;
End.
