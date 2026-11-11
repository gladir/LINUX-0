{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2026
  @website(https://www.gladir.com/linux-0)
  @abstract(Target: Linux Pascal (LPC /K))
  @description: Noyau LINUX-0 16 bits (IBM PC, 8086/8088, mode reel).

  Compilation (un seul fichier, une seule image) :
    LPC /K KERNEL.PAS      -> KERNEL.SYS, copie sous le nom UNIX a la racine
                              du disque d'amorce (voir KERNEL16UNIX/BUILD.SH).

  Le noyau est monolithique et ecrit dans un seul fichier source, decoupe en
  segments-unites (SegmentUnit) de Linux Pascal : chaque segment-unite a sa
  propre portee et son propre segment de code, ce qui permet de depasser la
  limite de 64 Ko de code d'un segment 8086. Les donnees du noyau occupent un
  segment de 64 Ko (DS).

  Organisation inspiree de UNIX V6 (Lions), de UNIX V7 et de xv6 (MIT
  6.828) :
   - table des processus (Procs), pile noyau par processus (allouee a sa
     creation), swtch (KSwitch), sleep/wakeup sur des canaux, ordonnanceur
     preemptif a priorites (temps processeur recent et nice, comme p_cpu de
     V7; interruption 08h de l'horloge, quantum de 3 tops);
   - appels systeme par INT 80h, numeros et semantique de UNIX V7 (puis de
     4.2BSD) : etat de wait, errno, stat, sgttyb, signaux avec gestionnaires,
     alarm, uid/gid reels et effectifs, set-uid, permissions, core;
   - memoire : table des zones libres (coremap) en paragraphes; fork par
     echange de memoire (les images 8086 contiennent des segments absolus :
     le fils partage l'adresse du pere et les images sont permutees a chaque
     commutation, comme le swapping de UNIX V1), exec charge un executable
     COFF (ou MZ) avec argc/argv/envp sur la pile; break agrandit l'image;
     va-et-vient (KSwap) : images ecrites dans une partition de type 82h
     quand la memoire manque, et ramenees a leur adresse d'execution;
   - systemes de fichiers : UFS1 (FreeBSD, racine du disque dur), FAT12 et
     FAT16 (disquettes, partition d'amorce), /dev, tubes; montage par chemin,
     cache de secteurs a ecriture differee (sync, toutes les 30 secondes);
   - console : ecran et clavier du BIOS, recopie sur COM1, discipline de
     ligne de V7 (RAW, CBREAK, ECHO, CRMOD; ^C = SIGINT, ^\ = SIGQUIT,
     ^D = fin de fichier).

  Carte memoire :
   00000-003FF vecteurs d'interruption  00400-004FF donnees du BIOS
   00500-07BFF pile du processus 0 (amorce)   07C00 secteur d'amorce
   08000-0FFFF cache disque (64 tampons de 512 octets)
   10000-...   noyau (code, puis donnees DS de 64 Ko)
   ...-A0000   memoire des processus et piles noyau (coremap)
}

Program Kernel;

{$S-,R-,I-,Q-,B-}

{ ====================================================================== }
SegmentUnit KTypes;
{ Constantes, types et tables partagees par tout le noyau. }
SegmentInterface

Const
 KVersion='0.1';
 NPROC=16;          { processus }
 NOFILE=20;         { descripteurs par processus }
 NFILE=64;          { table des fichiers ouverts }
 NVNODE=64;         { table des noeuds (vnodes) }
 NMOUNT=8;          { systemes de fichiers montes }
 NBUF=64;           { tampons du cache disque }
 NPIPE=4;           { tubes }
 PIPESIZE=512;
 NDISK=8;           { peripheriques disques connus }
 BUFBASE=$0800;      { segment du cache disque (08000h-0FFFFh) }
 KSTKPARAS=256;     { pile noyau : 4 Ko par processus }
 KSTKTOP=KSTKPARAS*16;
 QUANTUM=3;         { tops d'horloge par tranche de temps }
 DEFHEAP=256;       { tas initial par defaut (paragraphes, 4 Ko; break ensuite) }

 { etats des processus }
 PFREE=0; PRUN=1; PSLEEP=2; PZOMB=3;

 { types de vnode }
 VNON=0; VREG=1; VDIR=2; VCHR=3; VFIFO=4;

 { systemes de fichiers }
 FSNONE=0; FSFAT12=1; FSFAT16=2; FSUFS=3; FSDEV=4;

 { peripheriques de /dev (Minor) }
 DEVTTY=1; DEVNULL=2; DEVZERO=3; DEVDISK=16;   { DEVDISK+n = Disks[n] }

 { canaux de sommeil }
 CHTTY=1; CHPIPE=16; CHWAIT=32; CHPAUSE=64; CHSLEEP=96; CHVFORK=128;

 { modes }
 S_IFMT=$F000; S_IFDIR=$4000; S_IFCHR=$2000; S_IFREG=$8000; S_IFIFO=$1000;

 { open }
 O_RDONLY=0; O_WRONLY=1; O_RDWR=2; O_ACCMODE=3; O_NDELAY=4; O_APPEND=8;
 O_CREAT=$200; O_TRUNC=$400; O_EXCL=$800;   { valeurs de 4.2BSD }

 { signaux }
 { signaux (numeros de UNIX V7) }
 SIGHUP=1; SIGINT=2; SIGQUIT=3; SIGILL=4; SIGTRAP=5; SIGIOT=6; SIGEMT=7;
 SIGFPE=8; SIGKILL=9; SIGBUS=10; SIGSEGV=11; SIGSYS=12; SIGPIPE=13;
 SIGALRM=14; SIGTERM=15; NSIG=16;

 { codes d'erreur }
 EPERM=1; ENOENT=2; ESRCH=3; EINTR=4; EIO=5; ENXIO=6; E2BIG=7; ENOEXEC=8;
 EBADF=9; ECHILD=10; EAGAIN=11; ENOMEM=12; EACCES=13; EFAULT=14; EBUSY=16;
 EEXIST=17; EXDEV=18; ENODEV=19; ENOTDIR=20; EISDIR=21; EINVAL=22;
 ENFILE=23; EMFILE=24; ENOTTY=25; EFBIG=27; ENOSPC=28; ESPIPE=29;
 EROFS=30; EMLINK=31; EPIPE=32; EDOM=33; ERANGE=34;
 { au-dela de V7 : valeurs de BSD }
 ENAMETOOLONG=63; ENOTEMPTY=66; ENOSYS=78;

Type
 TPath=String[127];
 TName=String[63];
 T83=String[11];    { nom FAT 8.3 sur 11 caracteres }

 TProc=Record
  Stat: Byte;          { PFREE, PRUN, PSLEEP, PZOMB }
  Intr: Boolean;       { sommeil interruptible par un signal }
  Pid, PPid: Integer;
  Chan: Word;          { canal de sommeil }
  Wake: Longint;       { reveil a ce top d'horloge (0 = aucun) }
  KSP, KSS: Word;      { contexte noyau sauve par KSwitch }
  KStack: Word;        { segment de la pile noyau }
  USP, USS: Word;      { trame utilisateur (registres sur la pile) }
  Home: Word;          { segment ou l'image doit s'executer }
  Where: Word;         { segment ou se trouve l'image }
  Size: Word;          { taille en paragraphes }
  PSP: Word;           { prefixe du programme }
  DosOfs, DosSeg: Word;{ point d'entree libc pour INT 21h }
  Status: Word;        { etat de wait : code de sortie * 256 + signal }
  SigPend, SigIgn: Word;
  SigH: Array[1..NSIG-1] Of Longint;  { gestionnaires (0 = SIG_DFL) }
  SigTramp: Longint;   { trampoline de la libc pour les gestionnaires }
  Alarm: Longint;      { top d'horloge de SIGALRM (0 = aucune alarme) }
  Uid, Gid: Word;      { utilisateur et groupe effectifs (permissions) }
  RUid, RGid: Word;    { utilisateur et groupe reels }
  DosProg: Boolean;    { executable MZ (programme DOS) }
  Umask: Word;
  Nice: Integer;
  CpuRecent: Word;     { temps processeur recent (tops, divise par 2 par seconde) }
  ChildTicks: Longint; { temps processeur des fils attendus (times) }
  ArgPtr: Longint;     { argc/argv/envp sur la pile (exec) }
  Borrowed: Boolean;   { vfork : la memoire est celle du pere }
  Swapped: Boolean;    { image dans la zone de va-et-vient (Where = 0) }
  SwapBlk: Longint;    { premier secteur de l'image dans cette zone }
  SysCtx: Array[0..31] Of Byte;  { contexte de l'appel systeme en cours }
  CpuTicks: Longint;   { temps processeur (tops d'horloge) }
  Fd: Array[0..NOFILE-1] Of Byte;  { 0 = libre, sinon index fichier }
  Cwd: TPath;
  Name: String[15];
 End;

 TVNode=Record
  Ref: Byte;
  Typ: Byte;           { VREG, VDIR, VCHR, VFIFO }
  Mnt: Byte;           { index du montage }
  Dirty: Boolean;
  Ino: Longint;        { UFS : inode; FAT : DirLBA*16+entree (racine 0) }
  Size: Longint;
  Mode: Word;
  NLink: Word;
  MTime: Longint;
  First: Longint;      { FAT : premier cluster }
  DirLBA: Longint;     { FAT : secteur de l'entree de repertoire }
  DirIdx: Word;        { FAT : entree dans le secteur }
  Minor: Word;         { peripherique ou numero de tube }
  CIdx, CClus: Longint;{ FAT : dernier cluster parcouru (index, numero) }
  Uid, Gid: Word;      { proprietaire (UFS; 0 sur FAT et /dev) }
 End;

 TFile=Record
  Ref: Byte;
  Vn: Byte;
  Flags: Word;
  Off: Longint;
 End;

 TMount=Record
  Used: Boolean;
  Typ: Byte;
  Drive: Byte;         { index dans Disks }
  RO: Boolean;
  Start: Longint;      { premier secteur absolu }
  Sectors: Longint;
  Dir: String[31];
  Special: String[15];
  RootVn: Byte;
  { FAT }
  SecPerClus: Word;
  NFats: Word;
  RootEnt: Word;
  SecPerFat: Longint;
  FatLBA, RootLBA, DataLBA, Clusters, FreeHint: Longint;
  FreeClus: Longint;   { grappes libres (-1 = pas encore compte) }
  { UFS1 }
  FSize, BSize, Frag, Ipg, Fpg, Ncg, Iblkno, Cblkno, Dblkno: Longint;
  Inopb, Nindir, CsAddr, CgSize: Longint;
  FsbToDb: Word;
  CgOffset, CgMask: Longint;
 End;

 TDisk=Record
  Bios: Byte;          { unite BIOS }
  Present: Boolean;
  Spt, Heads: Word;
  Cyls: Word;
  Start, Sectors: Longint; { partition (0 = disque entier) }
  PartType: Byte;
  Name: String[7];
 End;

Var
 Procs: Array[0..NPROC-1] Of TProc;
 VNodes: Array[1..NVNODE] Of TVNode;
 Files: Array[1..NFILE] Of TFile;
 Mounts: Array[1..NMOUNT] Of TMount;
 Disks: Array[0..NDISK-1] Of TDisk;
 DiskCount: Integer;
 Cur: Integer;                  { processus courant }
 CurUSS, CurUSP, CurKStack: Word;
 InKernel: Byte;
 Ticks: Longint;                { tops d'horloge depuis l'amorce }
 BootTime: Longint;             { secondes depuis 1970 a l'amorce }
 KDataSeg: Word;
 MemTop: Word;                  { fin de la memoire conventionnelle }
 KernelEnd: Word;               { premier paragraphe libre apres le noyau }
 BootDrive: Byte;
 BootStart: Longint;
 SysHook, PreemptHook, FaultHook: Pointer;
 ZeroBuf: Array[0..511] Of Byte;
 SysCtxOfs, SysCtxLen: Word;   { contexte de l'appel systeme (KSys) }

SegmentImplementation
SegmentEnd;

{ ====================================================================== }
SegmentUnit KLib;
{ Console du noyau (BIOS + COM1), chaines, copie de memoire, panique. }
Uses KTypes;
SegmentInterface

Var
 SerialPort: Word;              { 0 = pas de port serie }
 ConPage: Byte;

Procedure SerialInit;
Procedure ConPutC(C: Char);
Procedure KPrint(S: String);
Procedure KPrintLn(S: String);
Function IntStr(L: Longint): String;
Function HexStr(W: Word): String;
Procedure Panic(S: String);
Procedure FarMove(SS_, SO, DS_, DO_, N: Word);
Procedure FarFill(DS_, DO_, N: Word; B: Byte);
Procedure ParaCopy(Src, Dst, Paras: Word);
Procedure ParaXchg(A, B, Paras: Word);
Procedure ParaZero(Dst, Paras: Word);
Function FarStr(Sg, Os: Word; Max: Integer): String;
Procedure PutFarStr(Sg, Os: Word; S: String);
Function UpStr(S: String): String;
Function LowStr(S: String): String;
Function KTime: Longint;
Function ReadRTC: Longint;
Procedure CliHlt;

SegmentImplementation

Procedure SerialInit;
Begin
 SerialPort:=MemW[$40:0];
 If SerialPort<>0 Then Begin
  Port[SerialPort+1]:=0;        { pas d'interruptions }
  Port[SerialPort+3]:=$80;      { DLAB }
  Port[SerialPort]:=12;         { 9600 bauds }
  Port[SerialPort+1]:=0;
  Port[SerialPort+3]:=3;        { 8N1 }
  Port[SerialPort+2]:=$C7;      { FIFO }
  Port[SerialPort+4]:=3;
 End;
End;

Procedure ConPutC(C: Char);
{ sortie d'un caractere a l'ecran, sans la fonction teletype (INT 10h AH=0Eh)
  dont certains emulateurs ne tiennent pas a jour le curseur de la zone BIOS
  (0040:0050) lue par l'unite CRT des programmes : curseur lu (AH=03h),
  caractere ecrit (AH=09h), defilement (AH=06h) et curseur replace (AH=02h,
  qui met a jour la zone BIOS); recopie sur COM1 }
Var B,Row,Col,Rows,Cols,Pg: Byte; N: Word;
Begin
 B:=Ord(C); Pg:=ConPage;
 Asm
  MOV AH,3
  MOV BH,Pg
  PUSH BP
  INT 10h
  POP BP
  MOV Row,DH
  MOV Col,DL
 End;
 Cols:=Mem[$40:$4A]; If Cols=0 Then Cols:=80;
 Rows:=Mem[$40:$84]+1; If Rows<25 Then Rows:=25;
 Case B Of
  13: Col:=0;
  10: Inc(Row);
  8: If Col>0 Then Dec(Col);
  7: ;
  Else Begin
   Asm
    MOV AH,9
    MOV AL,B
    MOV BH,Pg
    MOV BL,7
    MOV CX,1
    PUSH BP
    INT 10h
    POP BP
   End;
   Inc(Col);
   If Col>=Cols Then Begin Col:=0; Inc(Row) End;
  End;
 End;
 If Row>=Rows Then Begin
  Row:=Rows-1;
  Asm
   MOV AX,0601h
   MOV BH,7
   XOR CX,CX
   MOV DH,Row
   MOV DL,Cols
   DEC DL
   PUSH BP
   INT 10h
   POP BP
  End;
 End;
 Asm
  MOV AH,2
  MOV BH,Pg
  MOV DH,Row
  MOV DL,Col
  PUSH BP
  INT 10h
  POP BP
 End;
 If SerialPort<>0 Then Begin
  N:=0;
  While (Port[SerialPort+5] And $20=0) And (N<10000) Do Inc(N);
  Port[SerialPort]:=B;
 End;
End;

Procedure KPrint(S: String);
Var I: Integer;
Begin
 For I:=1 To Length(S) Do Begin
  If S[I]=#10 Then ConPutC(#13);
  ConPutC(S[I]);
 End;
End;

Procedure KPrintLn(S: String);
Begin
 KPrint(S); ConPutC(#13); ConPutC(#10);
End;

Function IntStr(L: Longint): String;
Var S: String;
Begin
 Str(L,S); IntStr:=S;
End;

Function HexStr(W: Word): String;
Const H: String[16]='0123456789ABCDEF';
Begin
 HexStr:=H[(W Shr 12)+1]+H[((W Shr 8) And 15)+1]+H[((W Shr 4) And 15)+1]+
   H[(W And 15)+1];
End;

Procedure CliHlt; Assembler;
Asm
@L:
 CLI
 HLT
 JMP @L
End;

Procedure Panic(S: String);
Begin
 KPrintLn('');
 KPrintLn('panique : '+S);
 CliHlt;
End;

Procedure FarMove(SS_, SO, DS_, DO_, N: Word); Assembler;
Asm
 PUSH DS
 MOV CX,N
 JCXZ @Fin
 MOV AX,SS_
 MOV SI,SO
 MOV ES,DS_
 MOV DI,DO_
 MOV DS,AX
 CLD
 SHR CX,1
 REP MOVSW
 JNC @Fin
 MOVSB
@Fin:
 POP DS
End;

Procedure FarFill(DS_, DO_, N: Word; B: Byte); Assembler;
Asm
 MOV CX,N
 JCXZ @Fin
 MOV ES,DS_
 MOV DI,DO_
 MOV AL,B
 CLD
 REP STOSB
@Fin:
End;

Procedure ParaCopy(Src, Dst, Paras: Word);
{ copie de Paras paragraphes (zones disjointes ou Dst < Src) }
Var N: Word;
Begin
 While Paras>0 Do Begin
  If Paras>$800 Then N:=$800 Else N:=Paras;
  FarMove(Src,0,Dst,0,N*16);
  Inc(Src,N); Inc(Dst,N); Dec(Paras,N);
 End;
End;

Procedure ParaZero(Dst, Paras: Word);
Var N: Word;
Begin
 While Paras>0 Do Begin
  If Paras>$800 Then N:=$800 Else N:=Paras;
  FarFill(Dst,0,N*16,0);
  Inc(Dst,N); Dec(Paras,N);
 End;
End;

Procedure XchgBlock(A, B, Words: Word); Assembler;
Asm
 PUSH DS
 MOV CX,Words
 JCXZ @Fin
 MOV ES,B
 MOV AX,A
 MOV DS,AX
 XOR SI,SI
@L:
 MOV AX,[SI]
 MOV DX,ES:[SI]
 MOV ES:[SI],AX
 MOV [SI],DX
 ADD SI,2
 LOOP @L
@Fin:
 POP DS
End;

Procedure ParaXchg(A, B, Paras: Word);
{ permute deux zones disjointes de Paras paragraphes }
Var N: Word;
Begin
 While Paras>0 Do Begin
  If Paras>$800 Then N:=$800 Else N:=Paras;
  XchgBlock(A,B,N*8);
  Inc(A,N); Inc(B,N); Dec(Paras,N);
 End;
End;

Function FarStr(Sg, Os: Word; Max: Integer): String;
Var S: String;
Begin
 S:='';
 While (Mem[Sg:Os]<>0) And (Length(S)<Max) Do Begin
  S:=S+Chr(Mem[Sg:Os]); Inc(Os);
 End;
 FarStr:=S;
End;

Procedure PutFarStr(Sg, Os: Word; S: String);
Var I: Integer;
Begin
 For I:=1 To Length(S) Do Mem[Sg:Os+I-1]:=Ord(S[I]);
 Mem[Sg:Os+Length(S)]:=0;
End;

Function UpStr(S: String): String;
Var I: Integer;
Begin
 For I:=1 To Length(S) Do S[I]:=UpCase(S[I]);
 UpStr:=S;
End;

Function LowStr(S: String): String;
Var I: Integer;
Begin
 For I:=1 To Length(S) Do If S[I] In ['A'..'Z'] Then S[I]:=Chr(Ord(S[I])+32);
 LowStr:=S;
End;

Function Bcd(B: Byte): Word;
Begin
 Bcd:=(B Shr 4)*10+(B And 15);
End;

Function ReadRTC: Longint;
{ secondes depuis 1970 lues dans l'horloge temps reel (INT 1Ah) }
Var H,M,S,C,Y,Mo,D,Ok: Byte; Days: Longint; I,Yr: Word;
Const MDays: Array[1..12] Of Word=(31,28,31,30,31,30,31,31,30,31,30,31);
Begin
 Ok:=0;
 Asm
  MOV AH,2
  INT 1Ah
  MOV H,CH
  MOV M,CL
  MOV S,DH
  MOV AH,4
  INT 1Ah
  JC @NoRtc
  MOV C,CH
  MOV Y,CL
  MOV Mo,DH
  MOV D,DL
  MOV Ok,1
 @NoRtc:
 End;
 If (Ok=0) Or (Mo=0) Then Begin ReadRTC:=1767225600; Exit End; { 2026-01-01 }
 Yr:=Bcd(C)*100+Bcd(Y);
 If Yr<1980 Then Yr:=2026;
 Days:=0;
 For I:=1970 To Yr-1 Do If I Mod 4=0 Then Inc(Days,366) Else Inc(Days,365);
 For I:=1 To Bcd(Mo)-1 Do Begin
  If I<=12 Then Inc(Days,MDays[I]);
  If (I=2) And (Yr Mod 4=0) Then Inc(Days);
 End;
 Inc(Days,Bcd(D)-1);
 ReadRTC:=Days*86400+Longint(Bcd(H))*3600+Bcd(M)*60+Bcd(S);
End;

Function KTime: Longint;
Begin
 KTime:=BootTime+(Ticks*10) Div 182;
End;

SegmentEnd;

{ ====================================================================== }
SegmentUnit KMem;
{ Gestion de la memoire physique : table des zones libres (coremap) en
  paragraphes, allocation premier ajustement (malloc de UNIX V6). }
Uses KTypes,KLib;
SegmentInterface

Const NMAP=64;

Var
 MapAddr, MapSize: Array[1..NMAP] Of Word;
 MapCount: Integer;
 TotalParas: Word;

Procedure CoreInit(Start, Top: Word);
Function CoreAlloc(Paras: Word): Word;
Procedure CoreFree(Sg, Paras: Word);
Function CoreFreeTotal: Word;
Function CoreLargest: Word;
Function CoreGrow(Sg, Paras: Word): Boolean;
Function CoreAllocHigh(Paras: Word): Word;
Function CoreAllocAt(Sg, Paras: Word): Boolean;

SegmentImplementation

Procedure CoreInit(Start, Top: Word);
Begin
 MapCount:=1; MapAddr[1]:=Start; MapSize[1]:=Top-Start;
 TotalParas:=Top-Start;
End;

Function CoreAlloc(Paras: Word): Word;
Var I,J: Integer;
Begin
 CoreAlloc:=0;
 If Paras=0 Then Exit;
 For I:=1 To MapCount Do
  If MapSize[I]>=Paras Then Begin
   CoreAlloc:=MapAddr[I];
   Inc(MapAddr[I],Paras); Dec(MapSize[I],Paras);
   If MapSize[I]=0 Then Begin
    For J:=I To MapCount-1 Do Begin
     MapAddr[J]:=MapAddr[J+1]; MapSize[J]:=MapSize[J+1];
    End;
    Dec(MapCount);
   End;
   Exit;
  End;
End;

Procedure CoreFree(Sg, Paras: Word);
Var I,J: Integer;
Begin
 If (Sg=0) Or (Paras=0) Then Exit;
 I:=1;
 While (I<=MapCount) And (MapAddr[I]<Sg) Do Inc(I);
 { fusion avec la zone precedente }
 If (I>1) And (MapAddr[I-1]+MapSize[I-1]=Sg) Then Begin
  Inc(MapSize[I-1],Paras);
  If (I<=MapCount) And (Sg+Paras=MapAddr[I]) Then Begin
   Inc(MapSize[I-1],MapSize[I]);
   For J:=I To MapCount-1 Do Begin
    MapAddr[J]:=MapAddr[J+1]; MapSize[J]:=MapSize[J+1];
   End;
   Dec(MapCount);
  End;
  Exit;
 End;
 { fusion avec la zone suivante }
 If (I<=MapCount) And (Sg+Paras=MapAddr[I]) Then Begin
  MapAddr[I]:=Sg; Inc(MapSize[I],Paras); Exit;
 End;
 If MapCount=NMAP Then Begin KPrintLn('coremap pleine'); Exit End;
 For J:=MapCount DownTo I Do Begin
  MapAddr[J+1]:=MapAddr[J]; MapSize[J+1]:=MapSize[J];
 End;
 MapAddr[I]:=Sg; MapSize[I]:=Paras; Inc(MapCount);
End;

Function CoreFreeTotal: Word;
Var I: Integer; T: Word;
Begin
 T:=0;
 For I:=1 To MapCount Do Inc(T,MapSize[I]);
 CoreFreeTotal:=T;
End;

Function CoreLargest: Word;
Var I: Integer; T: Word;
Begin
 T:=0;
 For I:=1 To MapCount Do If MapSize[I]>T Then T:=MapSize[I];
 CoreLargest:=T;
End;

Function CoreAllocHigh(Paras: Word): Word;
{ allocation au haut de la memoire (piles noyau), pour laisser le bas,
  d'un seul tenant, aux images des processus }
Var I,J: Integer;
Begin
 CoreAllocHigh:=0;
 If Paras=0 Then Exit;
 For I:=MapCount DownTo 1 Do
  If MapSize[I]>=Paras Then Begin
   Dec(MapSize[I],Paras);
   CoreAllocHigh:=MapAddr[I]+MapSize[I];
   If MapSize[I]=0 Then Begin
    For J:=I To MapCount-1 Do Begin
     MapAddr[J]:=MapAddr[J+1]; MapSize[J]:=MapSize[J+1];
    End;
    Dec(MapCount);
   End;
   Exit;
  End;
End;

Function CoreAllocAt(Sg, Paras: Word): Boolean;
{ allocation de [Sg, Sg+Paras) a cette adresse precise (retour d'une image
  non deplacable depuis la zone de va-et-vient) : la zone doit etre libre }
Var I,J: Integer; A,E: Word;
Begin
 CoreAllocAt:=False;
 If Paras=0 Then Begin CoreAllocAt:=True; Exit End;
 For I:=1 To MapCount Do
  If (MapAddr[I]<=Sg) And (Longint(Sg)+Paras<=Longint(MapAddr[I])+MapSize[I]) Then Begin
   A:=MapAddr[I]; E:=MapAddr[I]+MapSize[I];
   If (A<Sg) And (Sg+Paras<E) Then Begin
    { coupe en deux : une entree de plus }
    If MapCount=NMAP Then Exit;
    For J:=MapCount DownTo I+1 Do Begin
     MapAddr[J+1]:=MapAddr[J]; MapSize[J+1]:=MapSize[J];
    End;
    Inc(MapCount);
    MapSize[I]:=Sg-A;
    MapAddr[I+1]:=Sg+Paras; MapSize[I+1]:=E-(Sg+Paras);
   End Else If A<Sg Then MapSize[I]:=Sg-A
   Else If Sg+Paras<E Then Begin
    MapAddr[I]:=Sg+Paras; MapSize[I]:=E-(Sg+Paras);
   End Else Begin
    For J:=I To MapCount-1 Do Begin
     MapAddr[J]:=MapAddr[J+1]; MapSize[J]:=MapSize[J+1];
    End;
    Dec(MapCount);
   End;
   CoreAllocAt:=True; Exit;
  End;
End;

Function CoreGrow(Sg, Paras: Word): Boolean;
{ prend Paras paragraphes libres a partir de Sg : agrandissement sur place
  d'une image dont la fin est en Sg (break) }
Var I,J: Integer;
Begin
 CoreGrow:=False;
 For I:=1 To MapCount Do
  If MapAddr[I]=Sg Then Begin
   If MapSize[I]<Paras Then Exit;
   Inc(MapAddr[I],Paras); Dec(MapSize[I],Paras);
   If MapSize[I]=0 Then Begin
    For J:=I To MapCount-1 Do Begin
     MapAddr[J]:=MapAddr[J+1]; MapSize[J]:=MapSize[J+1];
    End;
    Dec(MapCount);
   End;
   CoreGrow:=True; Exit;
  End;
End;

SegmentEnd;

{ ====================================================================== }
SegmentUnit KSched;
{ Ordonnanceur : commutation de contexte, sommeil et reveil, horloge,
  points d'entree des interruptions (appels systeme, horloge, fautes). }
Uses KTypes,KLib,KMem;
SegmentInterface

Var
 SwSave, SwLoad: Word;         { decalages (DS) des contextes KSP/KSS }
 SwSaveP: Integer;
 Quantum: Integer;
 RunRun: Boolean;              { une commutation est demandee }
 SchedOn: Boolean;             { preemption active }
 OldInt08, OldInt1B: Pointer;
 BreakFlag: Boolean;           { Ctrl+Break }
 IdleHook: Pointer;            { scrutation du terminal (KTty) }
 SyncHook: Pointer;            { ecriture des tampons modifies (KDisk) }
 ResidentHook: Pointer;        { mise en memoire d'un processus (KSwap) }
 ResArg: Integer;              { argument et resultat de ResidentHook }
 ResOk: Boolean;
 NextPid: Integer;
 IdleTicks: Longint;
 SwitchStamp: Longint;

Procedure KSwitch;
Procedure ForkRet;
Procedure Int80Stub;
Procedure Int08Stub;
Procedure Int1BStub;
Procedure Int00Stub;
Procedure NoDosStub;
Procedure SetVector(N: Byte; Sg, Os: Word);
Function GetVector(N: Byte): Pointer;
Procedure SetDosVector(P: Integer);
Function MakeResident(P: Integer): Boolean;
Procedure Swtch;
Procedure Sleep(Chan: Word);
Function SleepIntr(Chan: Word): Boolean;
Procedure Wakeup(Chan: Word);
Procedure WakeProc(P: Integer);
Function FindPid(Pid: Integer): Integer;
Procedure PostSig(P: Integer; Sig: Integer);
Function UserW(Off: Word): Word;
Procedure SetUserW(Off: Word; W: Word);
Procedure CallIdleHook;

SegmentImplementation

Procedure KSwitch; Assembler;
{ Sauve le contexte noyau courant dans [SwSave] (SP, SS) et reprend celui de
  [SwLoad]. Appelee par Swtch : le retour se fait dans le processus elu. }
Asm
 PUSH BP
 PUSH SI
 PUSH DI
 MOV BX,SwSave
 MOV [BX],SP
 MOV [BX+2],SS
 MOV BX,SwLoad
 CLI
 MOV SS,[BX+2]
 MOV SP,[BX]
 STI
 POP DI
 POP SI
 POP BP
End;

Procedure ForkRet; Assembler;
{ Premier passage d'un processus cree par fork ou par le noyau : retour
  direct en mode utilisateur avec la trame de CurUSS:CurUSP. }
Asm
 MOV AX,SEG @DATA
 MOV DS,AX
 CLI
 MOV InKernel,0
 MOV SS,CurUSS
 MOV SP,CurUSP
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

Procedure Int80Stub; Assembler;
{ INT 80h : appel systeme. Registres sauves sur la pile utilisateur, puis
  passage sur la pile noyau du processus et appel de SysHook. }
Asm
 PUSH DS
 PUSH ES
 PUSH BP
 PUSH DI
 PUSH SI
 PUSH DX
 PUSH CX
 PUSH BX
 PUSH AX
 MOV AX,SEG @DATA
 MOV DS,AX
 MOV CurUSS,SS
 MOV CurUSP,SP
 MOV AX,CurKStack
 MOV SS,AX
 MOV SP,KSTKTOP
 MOV InKernel,1
 MOV ES,AX
 STI
 CLD
 CALL DWORD PTR SysHook
 MOV AX,SEG @DATA
 MOV DS,AX
 CLI
 MOV InKernel,0
 MOV SS,CurUSS
 MOV SP,CurUSP
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

Procedure Int00Stub; Assembler;
{ Faute du processeur (division par zero) : SIGFPE au processus courant. }
Asm
 PUSH DS
 PUSH ES
 PUSH BP
 PUSH DI
 PUSH SI
 PUSH DX
 PUSH CX
 PUSH BX
 PUSH AX
 MOV AX,SEG @DATA
 MOV DS,AX
 CMP InKernel,0
 JE @User
 CALL CliHlt
@User:
 MOV CurUSS,SS
 MOV CurUSP,SP
 MOV AX,CurKStack
 MOV SS,AX
 MOV SP,KSTKTOP
 MOV InKernel,1
 STI
 CLD
 CALL DWORD PTR FaultHook
 MOV AX,SEG @DATA
 MOV DS,AX
 CLI
 MOV InKernel,0
 MOV SS,CurUSS
 MOV SP,CurUSP
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

Procedure NoDosStub; Assembler;
{ INT 21h d'un processus sans couche libc : kill(getpid(), SIGSYS). }
Asm
 MOV AX,20
 INT 80h
 MOV BX,AX
 MOV CX,12
 MOV AX,37
 INT 80h
@L:
 JMP @L
End;

Procedure Int08Stub; Assembler;
{ IRQ0 (horloge, 18,2 Hz) : BIOS, puis preemption du processus courant si
  son quantum est epuise et qu'il est en mode utilisateur. }
Asm
 PUSH DS
 PUSH ES
 PUSH BP
 PUSH DI
 PUSH SI
 PUSH DX
 PUSH CX
 PUSH BX
 PUSH AX
 MOV AX,SEG @DATA
 MOV DS,AX
 PUSHF
 CALL DWORD PTR OldInt08
 ADD WORD PTR Ticks,1
 ADC WORD PTR Ticks+2,0
 CMP SchedOn,0
 JE @Out
 CMP InKernel,0
 JNE @Out
 MOV BP,SP
 MOV AX,[BP+20]
 CMP AX,0A000h
 JAE @Out
 DEC Quantum
 JLE @Preempt
 CMP BreakFlag,0
 JNE @Preempt
 JMP @Out
@Preempt:
 MOV CurUSS,SS
 MOV CurUSP,SP
 MOV AX,CurKStack
 MOV SS,AX
 MOV SP,KSTKTOP
 MOV InKernel,1
 STI
 CLD
 CALL DWORD PTR PreemptHook
 MOV AX,SEG @DATA
 MOV DS,AX
 CLI
 MOV InKernel,0
 MOV SS,CurUSS
 MOV SP,CurUSP
@Out:
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

Procedure Int1BStub; Assembler;
{ Ctrl+Break du BIOS }
Asm
 PUSH DS
 PUSH AX
 MOV AX,SEG @DATA
 MOV DS,AX
 MOV BreakFlag,1
 POP AX
 POP DS
 IRET
End;

Procedure SetVector(N: Byte; Sg, Os: Word);
Begin
 Asm CLI End;
 MemW[0:N*4]:=Os; MemW[0:N*4+2]:=Sg;
 Asm STI End;
End;

Function GetVector(N: Byte): Pointer;
Begin
 GetVector:=Ptr(MemW[0:N*4+2],MemW[0:N*4]);
End;

Procedure SetDosVector(P: Integer);
Begin
 If (P>0) And (Procs[P].DosSeg<>0) Then
   SetVector($21,Procs[P].DosSeg,Procs[P].DosOfs)
 Else SetVector($21,Seg(NoDosStub),Ofs(NoDosStub));
End;

Function UserW(Off: Word): Word;
{ mot Off de la trame utilisateur du processus courant }
Begin
 UserW:=MemW[CurUSS:CurUSP+Off];
End;

Procedure SetUserW(Off: Word; W: Word);
Begin
 MemW[CurUSS:CurUSP+Off]:=W;
End;

Procedure CallResidentHook; Assembler;
Asm
 CALL DWORD PTR ResidentHook
End;

Function MakeResident(P: Integer): Boolean;
{ L'image de P doit etre a son adresse d'execution (Home) avant qu'il ne
  s'execute : echange avec un processus issu du meme fork, recopie, ou
  retour depuis la zone de va-et-vient (KSwap.ResidentEntry). Faux si ce
  n'est pas possible pour l'instant (memoire tenue par un vfork). }
Begin
 With Procs[P] Do
  If Borrowed Or (Size=0) Or (Where=Home) Then Begin
   MakeResident:=True; Exit;
  End;
 ResArg:=P; ResOk:=False;
 CallResidentHook;
 MakeResident:=ResOk;
End;

Procedure CallSyncHook; Assembler;
Asm
 CMP WORD PTR SyncHook+2,0
 JE @Fin
 CALL DWORD PTR SyncHook
@Fin:
End;

Procedure CallIdleHook; Assembler;
Asm
 CMP WORD PTR IdleHook+2,0
 JE @Fin
 CALL DWORD PTR IdleHook
@Fin:
End;

Var
 LastDecay, LastSync: Longint;

Procedure CheckTimers;
{ reveils temporises, alarmes (SIGALRM) et, chaque seconde, decroissance
  du temps processeur recent (priorites, comme p_cpu de UNIX V7) }
Var I: Integer;
Begin
 If (Ticks-LastDecay>=18) Or (Ticks<LastDecay) Then Begin
  LastDecay:=Ticks;
  For I:=1 To NPROC-1 Do Procs[I].CpuRecent:=Procs[I].CpuRecent Shr 1;
 End;
 { toutes les 30 secondes : tampons modifies ecrits sur le disque (comme
   /etc/update de UNIX V7) }
 If (Ticks-LastSync>=546) Or (Ticks<LastSync) Then Begin
  LastSync:=Ticks; CallSyncHook;
 End;
 For I:=1 To NPROC-1 Do Begin
  With Procs[I] Do
   If (Stat=PSLEEP) And (Wake<>0) And (Ticks>=Wake) Then Begin
    Wake:=0; Stat:=PRUN;
   End;
  If (Procs[I].Alarm<>0) And (Ticks>=Procs[I].Alarm) And
    (Procs[I].Stat In [PRUN,PSLEEP]) Then Begin
   Procs[I].Alarm:=0; PostSig(I,SIGALRM);
  End;
 End;
End;

Function Prio(P: Integer): Integer;
{ priorite d'un processus pret (la plus petite valeur passe d'abord) :
  temps processeur recent, plus la valeur de nice }
Begin
 Prio:=Integer(Procs[P].CpuRecent)+Procs[P].Nice*4;
End;

Procedure Swtch;
{ Elit le processus pret de meilleure priorite (tourniquet a priorite egale)
  et lui donne le processeur. Si aucun n'est pret, attend une interruption
  (HLT). }
Var N,I,K,Best,Pr: Integer; T: Longint; Skip: Word;
Begin
 { controle de debordement de la pile noyau (motif CCh au fond) }
 If (Cur>0) And (MemW[Procs[Cur].KStack:0]<>$CCCC) Then
  Panic('debordement de la pile noyau (pid '+IntStr(Procs[Cur].Pid)+')');
 Procs[Cur].USS:=CurUSS; Procs[Cur].USP:=CurUSP;
 RunRun:=False; Skip:=0;
 Repeat
  CallIdleHook;
  CheckTimers;
  N:=-1; I:=Cur; Best:=MaxInt;
  For K:=1 To NPROC-1 Do Begin
   Inc(I); If I>=NPROC Then I:=1;
   If (Procs[I].Stat=PRUN) And (Skip And (1 Shl I)=0) Then Begin
    Pr:=Prio(I);
    If Pr<Best Then Begin Best:=Pr; N:=I End;
   End;
  End;
  { l'elu doit etre en memoire, a son adresse (va-et-vient, fork) }
  If (N>=0) And Not MakeResident(N) Then Begin
   Skip:=Skip Or (1 Shl N); N:=-1;
   If Skip<>0 Then Continue;
  End;
  If N<0 Then Begin
   Skip:=0;
   T:=Ticks;
   Asm
    STI
    HLT
   End;
   Inc(IdleTicks,Ticks-T);
  End;
 Until N>=0;
 Quantum:=QUANTUM;
 { temps processeur du processus sortant }
 Inc(Procs[Cur].CpuTicks,Ticks-SwitchStamp);
 If Procs[Cur].CpuRecent<1000 Then Inc(Procs[Cur].CpuRecent,Ticks-SwitchStamp);
 SwitchStamp:=Ticks;
 If N=Cur Then Exit;
 SwSaveP:=Cur;
 SwSave:=Ofs(Procs[Cur].KSP); SwLoad:=Ofs(Procs[N].KSP);
 Cur:=N;
 CurUSS:=Procs[N].USS; CurUSP:=Procs[N].USP; CurKStack:=Procs[N].KStack;
 SetDosVector(N);
 If SysCtxLen<>0 Then
  FarMove(DSeg,SysCtxOfs,DSeg,Ofs(Procs[SwSaveP].SysCtx),SysCtxLen);
 KSwitch;
 { de retour dans ce processus : son contexte d'appel systeme }
 If SysCtxLen<>0 Then
  FarMove(DSeg,Ofs(Procs[Cur].SysCtx),DSeg,SysCtxOfs,SysCtxLen);
End;

Procedure Sleep(Chan: Word);
Begin
 Procs[Cur].Chan:=Chan; Procs[Cur].Intr:=False; Procs[Cur].Stat:=PSLEEP;
 Swtch;
End;

Function SleepIntr(Chan: Word): Boolean;
{ Sommeil interruptible : False si un signal est arrive. }
Begin
 If Procs[Cur].SigPend And Not Procs[Cur].SigIgn<>0 Then Begin
  SleepIntr:=False; Exit;
 End;
 Procs[Cur].Chan:=Chan; Procs[Cur].Intr:=True; Procs[Cur].Stat:=PSLEEP;
 Swtch;
 Procs[Cur].Intr:=False;
 SleepIntr:=Procs[Cur].SigPend And Not Procs[Cur].SigIgn=0;
End;

Procedure Wakeup(Chan: Word);
Var I: Integer;
Begin
 For I:=1 To NPROC-1 Do
  If (Procs[I].Stat=PSLEEP) And (Procs[I].Chan=Chan) Then Begin
   Procs[I].Stat:=PRUN; Procs[I].Wake:=0;
  End;
End;

Procedure WakeProc(P: Integer);
Begin
 If Procs[P].Stat=PSLEEP Then Begin Procs[P].Stat:=PRUN; Procs[P].Wake:=0 End;
End;

Function FindPid(Pid: Integer): Integer;
Var I: Integer;
Begin
 FindPid:=-1;
 For I:=1 To NPROC-1 Do
  If (Procs[I].Stat<>PFREE) And (Procs[I].Pid=Pid) Then Begin
   FindPid:=I; Exit;
  End;
End;

Procedure PostSig(P: Integer; Sig: Integer);
Begin
 If (Sig<1) Or (Sig>=NSIG) Then Exit;
 With Procs[P] Do Begin
  If Stat In [PFREE,PZOMB] Then Exit;
  If (SigIgn And (1 Shl Sig)<>0) And (Sig<>SIGKILL) Then Exit;
  SigPend:=SigPend Or (1 Shl Sig);
  If (Stat=PSLEEP) And Intr Then Begin Stat:=PRUN; Wake:=0 End;
 End;
End;

SegmentEnd;

{ ====================================================================== }
SegmentUnit KDisk;
{ Disques du BIOS (INT 13h) et cache de secteurs (ecriture differee). }
Uses KTypes,KLib;
SegmentInterface

Var
 BufDev: Array[1..NBUF] Of Byte;     { $FF = libre }
 BufLBA: Array[1..NBUF] Of Longint;
 BufAge: Array[1..NBUF] Of Longint;
 BufDirty: Array[1..NBUF] Of Boolean;
 BufClock: Longint;
 DiskErrors: Word;

Procedure DiskInit;
Function DiskIO(D: Integer; LBA: Longint; Sg, Os: Word; Wr: Boolean): Boolean;
Function BRead(D: Integer; LBA: Longint): Integer;
Function BGet(D: Integer; LBA: Longint): Integer;
Function BWrite(B: Integer): Boolean;
Procedure BFlush(D: Integer);
Procedure BSync;
Function BufSeg(B: Integer): Word;
Procedure BInval(D: Integer);
Function AddDisk(Bios: Byte; Name: String; Start, Sectors: Longint;
  PType: Byte): Integer;
Procedure SetGeometry(D: Integer);
Function DiskRescan(D: Integer): Integer;

SegmentImplementation

Function AddDisk(Bios: Byte; Name: String; Start, Sectors: Longint;
  PType: Byte): Integer;
Var I,N: Integer;
Begin
 AddDisk:=-1;
 If DiskCount>=NDISK Then Exit;
 N:=DiskCount;
 Disks[N].Bios:=Bios; Disks[N].Present:=True;
 Disks[N].Spt:=0; Disks[N].Heads:=0; Disks[N].Cyls:=0;
 For I:=0 To N-1 Do If Disks[I].Bios=Bios Then Begin
  Disks[N].Spt:=Disks[I].Spt; Disks[N].Heads:=Disks[I].Heads;
  Disks[N].Cyls:=Disks[I].Cyls;
 End;
 Disks[N].Start:=Start; Disks[N].Sectors:=Sectors;
 Disks[N].PartType:=PType; Disks[N].Name:=Name;
 AddDisk:=N;
 Inc(DiskCount);
End;

Function Geometry(Bios: Byte; Var Spt, Heads, Cyls: Word): Boolean;
Var S,H,C1,C2,Ok: Byte;
Begin
 Ok:=0;
 Asm
  PUSH ES
  PUSH DI
  MOV AH,8
  MOV DL,Bios
  PUSH BP
  INT 13h
  POP BP
  JC @Err
  MOV S,CL
  MOV C1,CH
  MOV H,DH
  MOV Ok,1
 @Err:
  POP DI
  POP ES
 End;
 Geometry:=(Ok=1) And (S And 63<>0);
 Spt:=S And 63; Heads:=Word(H)+1;
 Cyls:=(Word(S And $C0) Shl 2)+C1+1;
End;

Procedure DiskInit;
Var I: Integer;
Begin
 For I:=1 To NBUF Do Begin BufDev[I]:=$FF; BufAge[I]:=0; BufDirty[I]:=False End;
 BufClock:=0;
End;

Procedure SetGeometry(D: Integer);
Var Spt_,Heads_,Cyls_: Word; I: Integer;
Begin
 If Disks[D].Spt<>0 Then Exit;
 If Geometry(Disks[D].Bios,Spt_,Heads_,Cyls_) Then Begin
  Disks[D].Spt:=Spt_; Disks[D].Heads:=Heads_; Disks[D].Cyls:=Cyls_;
 End Else Begin
  Disks[D].Spt:=18; Disks[D].Heads:=2; Disks[D].Cyls:=80;
 End;
 For I:=0 To DiskCount-1 Do If Disks[I].Bios=Disks[D].Bios Then Begin
  Disks[I].Spt:=Disks[D].Spt; Disks[I].Heads:=Disks[D].Heads;
  Disks[I].Cyls:=Disks[D].Cyls;
 End;
End;

Function DiskIO(D: Integer; LBA: Longint; Sg, Os: Word; Wr: Boolean): Boolean;
Var C,H,S,Cmd,Drv,Tries,Ok: Byte; Cyl: Word; T: Longint;
Begin
 DiskIO:=False;
 If (D<0) Or (D>=DiskCount) Then Exit;
 If Not Disks[D].Present Then Exit;
 SetGeometry(D);
 With Disks[D] Do Begin
  If (Sectors<>0) And (LBA>=Sectors) Then Exit;
  T:=LBA+Start;
  S:=(T Mod Spt)+1; T:=T Div Spt;
  H:=T Mod Heads; Cyl:=T Div Heads;
  Drv:=Bios;
 End;
 If Cyl>1023 Then Exit;
 C:=Lo(Cyl); S:=S Or ((Hi(Cyl) And 3) Shl 6);
 If Wr Then Cmd:=3 Else Cmd:=2;
 Tries:=0;
 Repeat
  Ok:=0;
  Asm
   PUSH ES
   MOV AH,Cmd
   MOV AL,1
   MOV CH,C
   MOV CL,S
   MOV DH,H
   MOV DL,Drv
   MOV ES,Sg
   MOV BX,Os
   PUSH BP
   INT 13h
   POP BP
   POP ES
   JC @Err
   MOV Ok,1
  @Err:
  End;
  If Ok=1 Then Begin DiskIO:=True; Exit End;
  Asm
   MOV AH,0
   MOV DL,Drv
   PUSH BP
   INT 13h
   POP BP
  End;
  Inc(Tries);
 Until Tries>=4;
 Inc(DiskErrors);
End;

Function BufSeg(B: Integer): Word;
Begin
 BufSeg:=BUFBASE+(B-1)*32;
End;

Function Find(D: Integer; LBA: Longint): Integer;
Var I: Integer;
Begin
 Find:=0;
 For I:=1 To NBUF Do
  If (BufDev[I]=D) And (BufLBA[I]=LBA) Then Begin Find:=I; Exit End;
End;

Procedure BOut(B: Integer);
{ ecriture d'un tampon modifie (ecriture differee) }
Begin
 If BufDirty[B] And (BufDev[B]<>$FF) Then
  DiskIO(BufDev[B],BufLBA[B],BufSeg(B),0,True);
 BufDirty[B]:=False;
End;

Function Victim: Integer;
{ tampon libre, sinon le plus ancien (ecrit s'il a ete modifie) }
Var I,V: Integer;
Begin
 V:=1;
 For I:=1 To NBUF Do Begin
  If BufDev[I]=$FF Then Begin Victim:=I; Exit End;
  If BufAge[I]<BufAge[V] Then V:=I;
 End;
 BOut(V);
 Victim:=V;
End;

Function BGet(D: Integer; LBA: Longint): Integer;
{ tampon pour le secteur (sans lecture : il sera entierement ecrit) }
Var B: Integer;
Begin
 B:=Find(D,LBA);
 If B=0 Then Begin
  B:=Victim; BufDev[B]:=D; BufLBA[B]:=LBA;
 End;
 Inc(BufClock); BufAge[B]:=BufClock;
 BGet:=B;
End;

Function BRead(D: Integer; LBA: Longint): Integer;
{ tampon contenant le secteur LBA (relatif a Disks[D]), 0 si erreur }
Var B: Integer;
Begin
 B:=Find(D,LBA);
 If B=0 Then Begin
  B:=Victim;
  If Not DiskIO(D,LBA,BufSeg(B),0,False) Then Begin
   BufDev[B]:=$FF; BRead:=0; Exit;
  End;
  BufDev[B]:=D; BufLBA[B]:=LBA;
 End;
 Inc(BufClock); BufAge[B]:=BufClock;
 BRead:=B;
End;

Function BWrite(B: Integer): Boolean;
{ ecriture differee (bdwrite de UNIX) : le tampon est marque modifie et
  sera ecrit quand il sera reutilise, par sync, au demontage ou par
  l'ecriture periodique (toutes les 30 secondes) }
Begin
 BufDirty[B]:=True;
 BWrite:=True;
End;

Procedure BFlush(D: Integer);
{ ecrit les tampons modifies du disque D (-1 : tous) }
Var I: Integer;
Begin
 For I:=1 To NBUF Do
  If BufDirty[I] And ((D<0) Or (BufDev[I]=D)) Then BOut(I);
End;

Procedure BSync;
Begin
 BFlush(-1);
End;

Procedure BInval(D: Integer);
Var I: Integer;
Begin
 BFlush(D);
 For I:=1 To NBUF Do If BufDev[I]=D Then BufDev[I]:=$FF;
End;

Var
 ScanBuf: Array[0..511] Of Byte;

Function DiskRescan(D: Integer): Integer;
{ relit la table des partitions (MBR) du disque dur entier D, apres son
  ecriture par un programme (installation) : les partitions hdX1 a hdX4
  sont mises a jour, ajoutees ou retirees }
Var J,K,I: Integer; T: Byte; S,N: Longint; Nm: String[7];
Begin
 DiskRescan:=EINVAL;
 If (D<0) Or (D>=DiskCount) Then Exit;
 If (Disks[D].Start<>0) Or (Disks[D].Bios<$80) Then Exit;
 BInval(D);
 DiskRescan:=EIO;
 If Not DiskIO(D,0,Seg(ScanBuf),Ofs(ScanBuf),False) Then Exit;
 For J:=0 To 3 Do Begin
  T:=ScanBuf[446+J*16+4];
  S:=MemL[Seg(ScanBuf):Ofs(ScanBuf)+446+J*16+8];
  N:=MemL[Seg(ScanBuf):Ofs(ScanBuf)+446+J*16+12];
  If (ScanBuf[510]<>$55) Or (ScanBuf[511]<>$AA) Then T:=0;
  Nm:=Disks[D].Name+Chr(49+J);
  K:=-1;
  For I:=0 To DiskCount-1 Do If Disks[I].Name=Nm Then K:=I;
  If K>=0 Then Begin
   BInval(K);
   Disks[K].Present:=(T<>0) And (N<>0);
   Disks[K].Start:=S; Disks[K].Sectors:=N; Disks[K].PartType:=T;
  End Else If (T<>0) And (N<>0) Then AddDisk(Disks[D].Bios,Nm,S,N,T);
 End;
 DiskRescan:=0;
End;

SegmentEnd;

{ ====================================================================== }
SegmentUnit KSwap;
{ Va-et-vient (swapping) comme UNIX V6/V7 : quand la memoire manque, des
  images de processus sont ecrites dans la zone de va-et-vient (partition
  de type 82h) et liberees. Une image 8086 contient des adresses de
  segments absolues : elle n'est pas deplacable, mais elle revient a son
  adresse d'execution (Home), apres que les processus qui l'occupent ont ete
  ecrits a leur tour dans la zone. Les piles noyau sont reservees a
  l'amorce (jamais dans une zone a liberer); la memoire d'un pere de vfork
  dont le fils s'execute n'est jamais ecrite. }
Uses KTypes,KLib,KMem,KSched,KDisk;
SegmentInterface

Const
 NSWAPMAP=32;

Var
 SwapDisk: Integer;               { index dans Disks, -1 = pas de zone }
 SwapSize: Longint;               { secteurs }
 SwapOuts, SwapIns: Longint;      { statistiques (ps) }

Procedure SwapInit(D: Integer);
Function SwapFreeSectors: Longint;
Function Locked(Q: Integer): Boolean;
Function SwapOut(Q: Integer): Boolean;
Function SwapImage(P: Integer; Sg: Word): Boolean;
Procedure SwapRelease(P: Integer);
Function Reclaim(Paras: Word; Except: Integer): Boolean;
Function ClaimRange(Sg, Paras: Word; Except: Integer): Boolean;
Procedure ResidentEntry;

SegmentImplementation

Var
 SMapAddr, SMapSize: Array[1..NSWAPMAP] Of Longint;
 SMapCount: Integer;
 SwapBuf: Array[0..511] Of Byte;

Procedure SwapInit(D: Integer);
Begin
 SwapDisk:=D; SwapSize:=Disks[D].Sectors;
 SMapCount:=1; SMapAddr[1]:=0; SMapSize[1]:=SwapSize;
End;

Function SwapFreeSectors: Longint;
Var I: Integer; T: Longint;
Begin
 T:=0;
 For I:=1 To SMapCount Do Inc(T,SMapSize[I]);
 SwapFreeSectors:=T;
End;

Function SAlloc(N: Longint): Longint;
{ N secteurs consecutifs de la zone (premier ajustement), -1 si plein }
Var I,J: Integer;
Begin
 SAlloc:=-1;
 For I:=1 To SMapCount Do
  If SMapSize[I]>=N Then Begin
   SAlloc:=SMapAddr[I];
   Inc(SMapAddr[I],N); Dec(SMapSize[I],N);
   If SMapSize[I]=0 Then Begin
    For J:=I To SMapCount-1 Do Begin
     SMapAddr[J]:=SMapAddr[J+1]; SMapSize[J]:=SMapSize[J+1];
    End;
    Dec(SMapCount);
   End;
   Exit;
  End;
End;

Procedure SFree(A, N: Longint);
Var I,J: Integer;
Begin
 If N<=0 Then Exit;
 I:=1;
 While (I<=SMapCount) And (SMapAddr[I]<A) Do Inc(I);
 If (I>1) And (SMapAddr[I-1]+SMapSize[I-1]=A) Then Begin
  Inc(SMapSize[I-1],N);
  If (I<=SMapCount) And (A+N=SMapAddr[I]) Then Begin
   Inc(SMapSize[I-1],SMapSize[I]);
   For J:=I To SMapCount-1 Do Begin
    SMapAddr[J]:=SMapAddr[J+1]; SMapSize[J]:=SMapSize[J+1];
   End;
   Dec(SMapCount);
  End;
  Exit;
 End;
 If (I<=SMapCount) And (A+N=SMapAddr[I]) Then Begin
  SMapAddr[I]:=A; Inc(SMapSize[I],N); Exit;
 End;
 If SMapCount=NSWAPMAP Then Begin KPrintLn('carte du va-et-vient pleine'); Exit End;
 For J:=SMapCount DownTo I Do Begin
  SMapAddr[J+1]:=SMapAddr[J]; SMapSize[J+1]:=SMapSize[J];
 End;
 SMapAddr[I]:=A; SMapSize[I]:=N; Inc(SMapCount);
End;

Function Sectors(Paras: Word): Longint;
Begin
 Sectors:=(Longint(Paras)+31) Div 32;
End;

Function SwapIO(Blk: Longint; Sg, Paras: Word; Wr: Boolean): Boolean;
{ transfert de Paras paragraphes entre Sg:0 et la zone (secteur Blk); le
  dernier secteur, incomplet, passe par SwapBuf pour ne rien ecrire au-dela
  de l'image en memoire }
Var I,N: Longint; Rest: Word;
Begin
 SwapIO:=False;
 N:=Paras Div 32; Rest:=(Paras Mod 32)*16;
 I:=0;
 While I<N Do Begin
  If Not DiskIO(SwapDisk,Blk+I,Sg+Word(I)*32,0,Wr) Then Exit;
  Inc(I);
 End;
 If Rest>0 Then Begin
  If Wr Then Begin
   FillChar(SwapBuf,SizeOf(SwapBuf),0);
   FarMove(Sg+Word(N)*32,0,Seg(SwapBuf),Ofs(SwapBuf),Rest);
   If Not DiskIO(SwapDisk,Blk+N,Seg(SwapBuf),Ofs(SwapBuf),True) Then Exit;
  End Else Begin
   If Not DiskIO(SwapDisk,Blk+N,Seg(SwapBuf),Ofs(SwapBuf),False) Then Exit;
   FarMove(Seg(SwapBuf),Ofs(SwapBuf),Sg+Word(N)*32,0,Rest);
  End;
 End;
 SwapIO:=True;
End;

Function Locked(Q: Integer): Boolean;
{ la memoire de Q est utilisee par un fils de vfork (qui s'execute dedans) }
Var I: Integer;
Begin
 Locked:=False;
 For I:=1 To NPROC-1 Do
  If (I<>Q) And (Procs[I].Stat<>PFREE) And Procs[I].Borrowed And
    (Procs[I].Home=Procs[Q].Home) Then Locked:=True;
End;

Function SwapImage(P: Integer; Sg: Word): Boolean;
{ ecrit Procs[P].Size paragraphes depuis Sg comme image de P dans la zone }
Var B: Longint;
Begin
 SwapImage:=False;
 If SwapDisk<0 Then Exit;
 B:=SAlloc(Sectors(Procs[P].Size));
 If B<0 Then Exit;
 If Not SwapIO(B,Sg,Procs[P].Size,True) Then Begin
  SFree(B,Sectors(Procs[P].Size)); Exit;
 End;
 Procs[P].SwapBlk:=B; Procs[P].Swapped:=True; Procs[P].Where:=0;
 Inc(SwapOuts);
 SwapImage:=True;
End;

Function SwapOut(Q: Integer): Boolean;
{ image de Q (en memoire : a son adresse ou copie de fork) vers la zone }
Var W: Word;
Begin
 SwapOut:=False;
 With Procs[Q] Do Begin
  If (Stat=PFREE) Or (Size=0) Or (Where=0) Or Borrowed Or Swapped Then Exit;
  If Locked(Q) Then Exit;
  W:=Where;
  If Not SwapImage(Q,W) Then Exit;
  CoreFree(W,Size);
 End;
 SwapOut:=True;
End;

Procedure SwapRelease(P: Integer);
{ abandon de l'image de P dans la zone }
Begin
 With Procs[P] Do If Swapped Then Begin
  SFree(SwapBlk,Sectors(Size)); Swapped:=False;
 End;
End;

Function Overlaps(Q: Integer; Sg, Paras: Word): Boolean;
Begin
 With Procs[Q] Do
  Overlaps:=(Stat<>PFREE) And (Size<>0) And (Where<>0) And Not Borrowed And
    (Longint(Where)<Longint(Sg)+Paras) And (Longint(Sg)<Longint(Where)+Size);
End;

Function ClaimRange(Sg, Paras: Word; Except: Integer): Boolean;
{ libere [Sg, Sg+Paras) en ecrivant ses occupants dans la zone, puis
  l'alloue }
Var Q: Integer;
Begin
 ClaimRange:=False;
 For Q:=1 To NPROC-1 Do
  If (Q<>Except) And Overlaps(Q,Sg,Paras) Then
   If Not SwapOut(Q) Then Exit;
 ClaimRange:=CoreAllocAt(Sg,Paras);
End;

Function Reclaim(Paras: Word; Except: Integer): Boolean;
{ ecrit des processus dans la zone jusqu'a ce qu'un bloc de Paras
  paragraphes soit libre : d'abord ceux qui dorment, les plus gros d'abord
  (le processus courant et Except sont epargnes) }
Var Q,V: Integer; Best: Longint;
Begin
 While CoreLargest<Paras Do Begin
  V:=0; Best:=-1;
  For Q:=1 To NPROC-1 Do
   With Procs[Q] Do
    If (Q<>Cur) And (Q<>Except) And (Stat In [PRUN,PSLEEP]) And (Size<>0) And
      (Where<>0) And Not Borrowed And Not Locked(Q) Then
     If Longint(Size)+Ord(Stat=PSLEEP)*65536>Best Then Begin
      Best:=Longint(Size)+Ord(Stat=PSLEEP)*65536; V:=Q;
     End;
  If (V=0) Or Not SwapOut(V) Then Begin Reclaim:=False; Exit End;
 End;
 Reclaim:=True;
End;

Procedure ResidentEntry;
{ ResidentHook : met Procs[ResArg] a son adresse d'execution; ResOk }
Var P,O: Integer;
Begin
 P:=ResArg; ResOk:=False;
 With Procs[P] Do Begin
  { copie de fork en memoire et image soeur a l'adresse : echange }
  If (Where<>0) And Not Swapped Then
   For O:=1 To NPROC-1 Do
    If (O<>P) And (Procs[O].Stat<>PFREE) And (Procs[O].Size=Size) And
      Not Procs[O].Borrowed And (Procs[O].Home=Home) And
      (Procs[O].Where=Home) And Not Locked(O) Then Begin
     ParaXchg(Home,Where,Size);
     Procs[O].Where:=Where; Where:=Home;
     ResOk:=True; Exit;
    End;
  { sinon : l'adresse est liberee (occupants vers la zone), puis copie ou
    lecture de la zone }
  If Not ClaimRange(Home,Size,P) Then Exit;
  If Swapped Then Begin
   If Not SwapIO(SwapBlk,Home,Size,False) Then
    Panic('lecture de la zone de va-et-vient impossible');
   SFree(SwapBlk,Sectors(Size)); Swapped:=False;
   Inc(SwapIns);
  End Else Begin
   ParaCopy(Where,Home,Size);
   CoreFree(Where,Size);
  End;
  Where:=Home;
 End;
 ResOk:=True;
End;

SegmentEnd;

{ ====================================================================== }
SegmentUnit KTty;
{ Terminal console : ecran (BIOS INT 10h), clavier (BIOS INT 16h) et port
  serie COM1. Discipline de ligne canonique ou brute. }
Uses KTypes,KLib,KSched;
SegmentInterface

Const
 { sg_flags de la structure sgttyb (UNIX V7, ioctl TIOCGETP/TIOCSETP) }
 TT_TANDEM=1; TT_CBREAK=2; TT_LCASE=4; TT_ECHO=8; TT_CRMOD=$10; TT_RAW=$20;

Var
 TtyFlags: Word;                   { sg_flags }
 TtyErase, TtyKill: Char;          { sg_erase, sg_kill }
 TChars: Array[0..5] Of Char;      { tchars : intr, quit, start, stop, eof, brk }
 TtyWaiting: Integer;

Procedure TtyInit;
Procedure TtyPoll;
Procedure TtyCheckIntr;
Procedure TtySig(Sig: Integer);
Procedure TtyFlush;
Function TtyRead(Sg, Os, N: Word; Var Err: Integer): Integer;
Function TtyWrite(Sg, Os, N: Word): Integer;
Function TtyAvail: Integer;

SegmentImplementation

Var
 KbdQ: Array[0..127] Of Word;      { frappes recues (code de balayage, car.) }
 KbdHead, KbdTail: Word;
 InBuf: Array[0..511] Of Char;     { caracteres prets a lire }
 InHead, InTail: Word;
 InEof: Integer;                   { fins de fichier (^D) en attente }
 Line: Array[0..255] Of Char;      { ligne en cours d'edition }
 LineLen: Integer;

Procedure PutIn(C: Char);
Var N: Word;
Begin
 N:=(InTail+1) And 511;
 If N<>InHead Then Begin InBuf[InTail]:=C; InTail:=N End;
End;

Function InCount: Integer;
Begin
 InCount:=(InTail-InHead) And 511;
End;

Procedure TtyInit;
{ etat initial du terminal (comme apres stty sane) }
Begin
 TtyFlags:=TT_ECHO Or TT_CRMOD;
 TtyErase:=#8; TtyKill:=#21;
 TChars[0]:=#3; TChars[1]:=#28; TChars[2]:=#17; TChars[3]:=#19;
 TChars[4]:=#4; TChars[5]:=#255;
End;

Procedure Echo(C: Char);
Begin
 If TtyFlags And TT_ECHO=0 Then Exit;
 If C=#10 Then ConPutC(#13);
 ConPutC(C);
End;

Procedure TtyFlush;
{ entree en attente videe (TIOCFLUSH, TIOCSETP, signal du clavier) }
Begin
 InHead:=InTail; InEof:=0; LineLen:=0;
End;

Procedure TtySig(Sig: Integer);
{ ^C (SIGINT), ^\ (SIGQUIT) ou Ctrl+Break : signal a tous les processus
  du terminal, sauf init (comme UNIX V7, dont le terminal unique est celui
  de tous les processus). L'interpreteur de commandes ignore ces signaux
  pour ses commandes lancees en arriere-plan (&). }
Var I: Integer;
Begin
 TtyFlush;
 For I:=1 To NPROC-1 Do With Procs[I] Do
  If (Stat In [PRUN,PSLEEP]) And (Pid>1) Then PostSig(I,Sig);
End;

Procedure Input(C: Char; Scan: Byte);
Var I: Integer;
Begin
 If TtyFlags And (TT_RAW Or TT_CBREAK)<>0 Then Begin
  { RAW : caracteres tels quels; CBREAK : un caractere a la fois, avec
    l'echo et les signaux. Touches etendues : 0 puis code de balayage. }
  If (C=#0) Or (C=#$E0) Then Begin
   If Scan<>0 Then Begin PutIn(#0); PutIn(Chr(Scan)) End;
  End Else Begin
   If (C=#13) And (TtyFlags And (TT_RAW Or TT_CRMOD)=TT_CRMOD) Then C:=#10;
   PutIn(C);
   If TtyFlags And TT_RAW=0 Then Echo(C);
  End;
  Wakeup(CHTTY);
  Exit;
 End;
 If C=#127 Then C:=TtyErase;
 If (C=#13) And (TtyFlags And TT_CRMOD<>0) Then C:=#10;
 If (C=#0) Or (C=#$E0) Then
 Else If C=TtyErase Then Begin
  If LineLen>0 Then Begin Dec(LineLen); Echo(#8); Echo(' '); Echo(#8) End;
 End Else If C=TtyKill Then Begin
  While LineLen>0 Do Begin Dec(LineLen); Echo(#8); Echo(' '); Echo(#8) End;
 End Else If C=TChars[4] Then Begin
  If LineLen=0 Then Inc(InEof)
  Else Begin
   For I:=0 To LineLen-1 Do PutIn(Line[I]);
   LineLen:=0;
  End;
 End Else If (C=#10) Or (C=#13) Then Begin
  For I:=0 To LineLen-1 Do PutIn(Line[I]);
  PutIn(#10); LineLen:=0; Echo(#10);
 End Else If (C>=' ') Or (C=#9) Or (C=#27) Then Begin
  If LineLen<255 Then Begin Line[LineLen]:=C; Inc(LineLen); Echo(C) End;
 End;
 Wakeup(CHTTY);
End;

Procedure KbdPut(A, S: Byte);
{ frappe recue : le caractere d'interruption (^C) ou d'abandon (^\), hors
  mode RAW, envoie aussitot SIGINT ou SIGQUIT }
Var N: Word;
Begin
 If (TtyFlags And TT_RAW=0) And (A<>0) And
   ((A=Ord(TChars[0])) Or (A=Ord(TChars[1]))) Then Begin
  Echo('^');
  If A=Ord(TChars[0]) Then Echo('C') Else Echo('\');
  Echo(#10);
  If A=Ord(TChars[0]) Then TtySig(SIGINT) Else TtySig(SIGQUIT);
  Exit;
 End;
 N:=(KbdTail+1) And 127;
 If N<>KbdHead Then Begin KbdQ[KbdTail]:=Word(S) Shl 8+A; KbdTail:=N End;
End;

Procedure KbdDrain;
{ vide le tampon clavier du BIOS (15 touches) et le port serie dans la file
  du terminal : appelee a chaque commutation et a chaque fin de quantum, pour
  ne perdre aucune frappe pendant qu'un programme calcule }
Var A,S,Have: Byte;
Begin
 Repeat
  Have:=0;
  Asm
   MOV AH,1
   INT 16h
   JZ @None
   MOV AH,0
   INT 16h
   MOV A,AL
   MOV S,AH
   MOV Have,1
  @None:
  End;
  If Have=1 Then KbdPut(A,S);
 Until Have=0;
 If SerialPort<>0 Then
  While Port[SerialPort+5] And 1<>0 Do Begin
   A:=Port[SerialPort];
   If (A=13) Or (A<>10) Then KbdPut(A,0);
  End;
End;

Procedure PollKeys;
{ traite les frappes en attente selon le mode du lecteur }
Var W: Word;
Begin
 KbdDrain;
 While KbdHead<>KbdTail Do Begin
  W:=KbdQ[KbdHead]; KbdHead:=(KbdHead+1) And 127;
  Input(Chr(Lo(W)),Hi(W));
 End;
End;

Procedure TtyPoll;
{ appelee par l'ordonnanceur : recueille les frappes, les traite si un
  processus lit le terminal }
Begin
 If TtyWaiting>0 Then PollKeys Else KbdDrain;
 If BreakFlag Then Begin BreakFlag:=False; TtySig(SIGINT) End;
End;

Procedure TtyCheckIntr;
{ appelee a la preemption : frappes en attente (^C), Ctrl+Break }
Begin
 If BreakFlag Then Begin BreakFlag:=False; TtySig(SIGINT) End;
 KbdDrain;
End;

Function TtyAvail: Integer;
Begin
 PollKeys;
 TtyAvail:=InCount;
End;

Function TtyRead(Sg, Os, N: Word; Var Err: Integer): Integer;
Var Got: Word; C: Char;
Begin
 Err:=0; TtyRead:=0;
 If N=0 Then Exit;
 Inc(TtyWaiting);
 PollKeys;
 While (InCount=0) And (InEof=0) Do Begin
  If Not SleepIntr(CHTTY) Then Begin
   Dec(TtyWaiting); Err:=EINTR; TtyRead:=-1; Exit;
  End;
  PollKeys;
 End;
 Dec(TtyWaiting);
 Got:=0;
 If InCount=0 Then Begin Dec(InEof); TtyRead:=0; Exit End;
 While (Got<N) And (InCount>0) Do Begin
  C:=InBuf[InHead]; InHead:=(InHead+1) And 511;
  Mem[Sg:Os+Got]:=Ord(C); Inc(Got);
  If (C=#10) And (TtyFlags And (TT_RAW Or TT_CBREAK)=0) Then Break;
 End;
 TtyRead:=Got;
End;

Function TtyWrite(Sg, Os, N: Word): Integer;
Var I: Word; C: Char;
Begin
 For I:=0 To N-1 Do Begin
  C:=Chr(Mem[Sg:Os+I]);
  If (C=#10) And (TtyFlags And (TT_RAW Or TT_CRMOD)=TT_CRMOD) Then ConPutC(#13);
  ConPutC(C);
 End;
 TtyWrite:=N;
End;

SegmentEnd;

{ ====================================================================== }
SegmentUnit KFat;
{ Systemes de fichiers FAT12 et FAT16 (noms 8.3, presentes en minuscules). }
Uses KTypes,KLib,KDisk;
SegmentInterface

Const FATEOC=$FFFF;

Function FatMount(M: Integer): Integer;
Procedure FatRoot(M: Integer; Var V: TVNode);
Function FatGet(M: Integer; C: Longint): Longint;
Function FatLookup(Var Dir: TVNode; Name: TName; Var V: TVNode): Integer;
Function FatRead(Var V: TVNode; Off: Longint; Sg, Os, N: Word): Integer;
Function FatWrite(Var V: TVNode; Off: Longint; Sg, Os, N: Word): Integer;
Function FatTrunc(Var V: TVNode): Integer;
Function FatReadDir(Var V: TVNode; Var Pos: Longint; Var Name: TName;
  Var Ino: Longint; Var Typ: Byte): Boolean;
Function FatCreate(Var Dir: TVNode; Name: TName; IsDir: Boolean;
  Var V: TVNode): Integer;
Function FatRemove(Var Dir: TVNode; Name: TName; IsDir: Boolean): Integer;
Function FatRename(Var D1: TVNode; N1: TName; Var D2: TVNode;
  N2: TName): Integer;
Procedure FatUpdate(Var V: TVNode);
Function FatFreeKB(M: Integer): Longint;
Function DosStamp(T: Longint): Longint;
Function UnixStamp(D, T: Word): Longint;

SegmentImplementation

Var


Function DosStamp(T: Longint): Longint;
{ secondes depuis 1970 -> date (mot haut) et heure (mot bas) DOS }
Var Days,Secs: Longint; Y,M,D,DM: Word;
Begin
 If T<315532800 Then T:=315532800;
 Days:=T Div 86400; Secs:=T Mod 86400;
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
 DosStamp:=(Longint((Y-1980) Shl 9 Or (M Shl 5) Or D) Shl 16) Or
   ((Secs Div 3600) Shl 11) Or (((Secs Mod 3600) Div 60) Shl 5) Or
   ((Secs Mod 60) Div 2);
End;

Function UnixStamp(D, T: Word): Longint;
Var Y,M,I: Word; Days: Longint;
Const MD: Array[1..12] Of Word=(31,28,31,30,31,30,31,31,30,31,30,31);
Begin
 Y:=(D Shr 9)+1980; M:=(D Shr 5) And 15;
 If (M<1) Or (M>12) Then Begin UnixStamp:=315532800; Exit End;
 Days:=0;
 For I:=1970 To Y-1 Do If I Mod 4=0 Then Inc(Days,366) Else Inc(Days,365);
 For I:=1 To M-1 Do Begin
  Inc(Days,MD[I]); If (I=2) And (Y Mod 4=0) Then Inc(Days);
 End;
 Inc(Days,(D And 31)-1);
 UnixStamp:=Days*86400+Longint(T Shr 11)*3600+((T Shr 5) And 63)*60+
   (T And 31)*2;
End;

Function Fat16(M: Integer): Boolean;
Begin
 Fat16:=Mounts[M].Typ=FSFAT16;
End;

Function FatMount(M: Integer): Integer;
Var B: Integer; S: Word; Tot: Longint;
Begin
 FatMount:=EIO;
 With Mounts[M] Do Begin
  B:=BRead(Drive,0);
  If B=0 Then Exit;
  S:=BufSeg(B);
  FatMount:=EINVAL;
  If (MemW[S:11]<>512) Or (Mem[S:13]=0) Or (Mem[S:16]=0) Then Exit;
  SecPerClus:=Mem[S:13];
  NFats:=Mem[S:16];
  RootEnt:=MemW[S:17];
  Tot:=MemW[S:19]; If Tot=0 Then Tot:=MemL[S:32];
  SecPerFat:=MemW[S:22];
  If SecPerFat=0 Then Exit; { FAT32 non gere }
  FatLBA:=MemW[S:14];
  RootLBA:=FatLBA+NFats*SecPerFat;
  DataLBA:=RootLBA+(Longint(RootEnt)*32+511) Div 512;
  Clusters:=(Tot-DataLBA) Div SecPerClus;
  Sectors:=Tot;
  If Clusters<4085 Then Typ:=FSFAT12 Else Typ:=FSFAT16;
  FreeHint:=2; FreeClus:=-1;
 End;
 FatMount:=0;
End;

Procedure FatRoot(M: Integer; Var V: TVNode);
Begin
 FillChar(V,SizeOf(V),0);
 V.Typ:=VDIR; V.Mnt:=M; V.Ino:=0; V.First:=0; V.Mode:=S_IFDIR Or $1FF;
 V.NLink:=2; V.MTime:=BootTime;
End;

Function ClusLBA(M: Integer; C: Longint): Longint;
Begin
 ClusLBA:=Mounts[M].DataLBA+(C-2)*Mounts[M].SecPerClus;
End;

Function FatGet(M: Integer; C: Longint): Longint;
Var Off,Sec: Longint; B: Integer; O,V: Word; Lo_,Hi_: Byte;
Begin
 FatGet:=FATEOC;
 With Mounts[M] Do Begin
  If (C<2) Or (C>Clusters+1) Then Exit;
  If Typ=FSFAT16 Then Begin
   Off:=C*2; B:=BRead(Drive,FatLBA+Off Div 512);
   If B=0 Then Exit;
   V:=MemW[BufSeg(B):Off Mod 512];
   If V>=$FFF8 Then FatGet:=FATEOC Else FatGet:=V;
  End Else Begin
   Off:=C+C Div 2; Sec:=FatLBA+Off Div 512; O:=Off Mod 512;
   B:=BRead(Drive,Sec); If B=0 Then Exit;
   Lo_:=Mem[BufSeg(B):O];
   If O=511 Then Begin
    B:=BRead(Drive,Sec+1); If B=0 Then Exit;
    Hi_:=Mem[BufSeg(B):0];
   End Else Hi_:=Mem[BufSeg(B):O+1];
   V:=Lo_+Word(Hi_) Shl 8;
   If Odd(C) Then V:=V Shr 4 Else V:=V And $FFF;
   If V>=$FF8 Then FatGet:=FATEOC Else FatGet:=V;
  End;
 End;
End;

Procedure FatSet(M: Integer; C, Val: Longint);
Var Off,Sec: Longint; B,K: Integer; O,V: Word; S: Word;
Begin
 With Mounts[M] Do Begin
  If (C<2) Or (C>Clusters+1) Then Exit;
  For K:=0 To NFats-1 Do Begin
   If Typ=FSFAT16 Then Begin
    Off:=C*2; B:=BRead(Drive,FatLBA+K*SecPerFat+Off Div 512);
    If B=0 Then Exit;
    MemW[BufSeg(B):Off Mod 512]:=Word(Val); BWrite(B);
   End Else Begin
    V:=Word(Val) And $FFF;
    Off:=C+C Div 2; Sec:=FatLBA+K*SecPerFat+Off Div 512; O:=Off Mod 512;
    B:=BRead(Drive,Sec); If B=0 Then Exit;
    S:=BufSeg(B);
    If Odd(C) Then Mem[S:O]:=(Mem[S:O] And $0F) Or Lo(V Shl 4)
    Else Mem[S:O]:=Lo(V);
    If O=511 Then Begin
     BWrite(B);
     B:=BRead(Drive,Sec+1); If B=0 Then Exit;
     S:=BufSeg(B); O:=0;
    End Else Inc(O);
    If Odd(C) Then Mem[S:O]:=Hi(V Shl 4)
    Else Mem[S:O]:=(Mem[S:O] And $F0) Or Hi(V);
    BWrite(B);
   End;
  End;
 End;
End;

Function FatAlloc(M: Integer): Longint;
{ cluster libre marque fin de chaine, 0 si le disque est plein }
Var C,N: Longint;
Begin
 FatAlloc:=0;
 With Mounts[M] Do Begin
  C:=FreeHint; If (C<2) Or (C>Clusters+1) Then C:=2;
  For N:=1 To Clusters Do Begin
   If FatGet(M,C)=0 Then Begin
    FatSet(M,C,FATEOC); FreeHint:=C+1; FatAlloc:=C;
    If FreeClus>0 Then Dec(FreeClus);
    Exit;
   End;
   Inc(C); If C>Clusters+1 Then C:=2;
  End;
 End;
End;

Procedure FreeChain(M: Integer; C: Longint);
Var N: Longint; K: Longint;
Begin
 K:=0;
 While (C>=2) And (C<>FATEOC) And (K<=Mounts[M].Clusters) Do Begin
  N:=FatGet(M,C); FatSet(M,C,0);
  If C<Mounts[M].FreeHint Then Mounts[M].FreeHint:=C;
  If Mounts[M].FreeClus>=0 Then Inc(Mounts[M].FreeClus);
  C:=N; Inc(K);
 End;
End;

Function FatFreeKB(M: Integer): Longint;
{ espace libre : le compte des grappes libres est fait une seule fois, puis
  tenu a jour par FatAlloc et FreeChain }
Var C,N: Longint;
Begin
 If Mounts[M].FreeClus<0 Then Begin
  N:=0;
  For C:=2 To Mounts[M].Clusters+1 Do If FatGet(M,C)=0 Then Inc(N);
  Mounts[M].FreeClus:=N;
 End;
 FatFreeKB:=Mounts[M].FreeClus*Mounts[M].SecPerClus Div 2;
End;

Procedure ZeroCluster(M: Integer; C: Longint);
Var I: Integer; B: Integer;
Begin
 For I:=0 To Mounts[M].SecPerClus-1 Do Begin
  B:=BGet(Mounts[M].Drive,ClusLBA(M,C)+I);
  FarFill(BufSeg(B),0,512,0); BWrite(B);
 End;
End;

Function DirSector(Var D: TVNode; Index: Longint; Grow: Boolean;
  Var LBA: Longint; Var Idx: Word): Boolean;
{ secteur et position de l'entree Index du repertoire D }
Var Sec,CI,K,C,N: Longint; M: Integer;
Begin
 DirSector:=False; M:=D.Mnt;
 Idx:=Index Mod 16; Sec:=Index Div 16;
 With Mounts[M] Do
 If D.First=0 Then Begin
  If Index>=RootEnt Then Exit;
  LBA:=RootLBA+Sec;
 End Else Begin
  CI:=Sec Div SecPerClus; C:=D.First; K:=0;
  While K<CI Do Begin
   N:=FatGet(M,C);
   If (N<2) Or (N=FATEOC) Then Begin
    If Not Grow Then Exit;
    N:=FatAlloc(M); If N=0 Then Exit;
    ZeroCluster(M,N); FatSet(M,C,N);
   End;
   C:=N; Inc(K);
  End;
  LBA:=ClusLBA(M,C)+Sec Mod SecPerClus;
 End;
 DirSector:=True;
End;

Function To83(Name: TName; Var R: T83): Boolean;
Var I,P: Integer; B,E: TName;
Begin
 To83:=False;
 If (Name='') Or (Name='.') Or (Name='..') Then Begin
  If Name='.' Then R:='.          ' Else If Name='..' Then R:='..         '
  Else Exit;
  To83:=True; Exit;
 End;
 Name:=UpStr(Name);
 P:=0; For I:=Length(Name) DownTo 2 Do If Name[I]='.' Then Begin P:=I; Break End;
 If P>0 Then Begin B:=Copy(Name,1,P-1); E:=Copy(Name,P+1,255) End
 Else Begin B:=Name; E:='' End;
 If (Length(B)>8) Or (Length(E)>3) Or (B='') Then Exit;
 For I:=1 To Length(B) Do If B[I] In ['.',' ','"','*','+',',','/',':',';',
   '<','=','>','?','[','\',']','|'] Then Exit;
 For I:=1 To Length(E) Do If E[I] In ['.',' ','"','*','+',',','/',':',';',
   '<','=','>','?','[','\',']','|'] Then Exit;
 While Length(B)<8 Do B:=B+' ';
 While Length(E)<3 Do E:=E+' ';
 R:=B+E; To83:=True;
End;

Function From83(Sg, Os: Word): TName;
Var B,E: TName; I: Integer;
Begin
 B:=''; E:='';
 For I:=0 To 7 Do B:=B+Chr(Mem[Sg:Os+I]);
 For I:=8 To 10 Do E:=E+Chr(Mem[Sg:Os+I]);
 While (B<>'') And (B[Length(B)]=' ') Do Dec(B[0]);
 While (E<>'') And (E[Length(E)]=' ') Do Dec(E[0]);
 If B[1]=#5 Then B[1]:=#$E5;
 If E<>'' Then B:=B+'.'+E;
 From83:=LowStr(B);
End;

Procedure FillVn(M: Integer; Sg, Os: Word; LBA: Longint; Idx: Word;
  Var V: TVNode);
Var A: Byte;
Begin
 FillChar(V,SizeOf(V),0);
 A:=Mem[Sg:Os+11];
 V.Mnt:=M; V.First:=MemW[Sg:Os+26]; V.Size:=MemL[Sg:Os+28];
 V.DirLBA:=LBA; V.DirIdx:=Idx; V.Ino:=LBA*16+Idx;
 V.MTime:=UnixStamp(MemW[Sg:Os+24],MemW[Sg:Os+22]);
 If A And $10<>0 Then Begin
  V.Typ:=VDIR; V.Mode:=S_IFDIR Or $1FF; V.NLink:=2; V.Size:=0;
 End Else Begin
  V.Typ:=VREG; V.Mode:=S_IFREG Or $1FF; V.NLink:=1;
 End;
 If A And 1<>0 Then V.Mode:=V.Mode And Not $92;
End;

Function Search(Var Dir: TVNode; Var N83: T83; Var LBA: Longint;
  Var Idx: Word): Boolean;
Var I: Longint; B: Integer; S,O: Word; K: Integer; Ok: Boolean; A: Byte;
Begin
 Search:=False; I:=0;
 While DirSector(Dir,I,False,LBA,Idx) Do Begin
  B:=BRead(Mounts[Dir.Mnt].Drive,LBA);
  If B=0 Then Exit;
  S:=BufSeg(B); O:=Idx*32;
  If Mem[S:O]=0 Then Exit;
  A:=Mem[S:O+11];
  If (Mem[S:O]<>$E5) And (A<>$0F) And (A And 8=0) Then Begin
   Ok:=True;
   For K:=0 To 10 Do If Mem[S:O+K]<>Ord(N83[K+1]) Then Begin
    Ok:=False; Break;
   End;
   If Ok Then Begin Search:=True; Exit End;
  End;
  Inc(I);
 End;
End;

Function FatLookup(Var Dir: TVNode; Name: TName; Var V: TVNode): Integer;
Var N83: T83; LBA,C: Longint; Idx: Word; B: Integer;
Begin
 If Not To83(Name,N83) Then Begin FatLookup:=ENOENT; Exit End;
 If Not Search(Dir,N83,LBA,Idx) Then Begin FatLookup:=ENOENT; Exit End;
 B:=BRead(Mounts[Dir.Mnt].Drive,LBA);
 If B=0 Then Begin FatLookup:=EIO; Exit End;
 FillVn(Dir.Mnt,BufSeg(B),Idx*32,LBA,Idx,V);
 { ".." vers la racine (cluster 0) }
 If (V.Typ=VDIR) And (V.First=0) Then FatRoot(Dir.Mnt,V);
 FatLookup:=0;
End;

Function ClusterAt(Var V: TVNode; Idx: Longint): Longint;
Var C,I: Longint;
Begin
 If (V.CClus>=2) And (Idx>=V.CIdx) Then Begin C:=V.CClus; I:=V.CIdx End
 Else Begin C:=V.First; I:=0 End;
 While (I<Idx) And (C>=2) And (C<>FATEOC) Do Begin
  C:=FatGet(V.Mnt,C); Inc(I);
 End;
 If (C<2) Or (C=FATEOC) Then Begin ClusterAt:=0; Exit End;
 V.CIdx:=Idx; V.CClus:=C;
 ClusterAt:=C;
End;

Function FatRead(Var V: TVNode; Off: Longint; Sg, Os, N: Word): Integer;
Var Done,Chunk,O: Word; CB: Longint; C: Longint; B: Integer; M: Integer;
Begin
 FatRead:=0;
 If Off>=V.Size Then Exit;
 If Off+N>V.Size Then N:=V.Size-Off;
 M:=V.Mnt; CB:=Longint(Mounts[M].SecPerClus)*512; Done:=0;
 While Done<N Do Begin
  C:=ClusterAt(V,Off Div CB);
  If C=0 Then Break;
  O:=Off Mod 512; Chunk:=512-O; If Chunk>N-Done Then Chunk:=N-Done;
  B:=BRead(Mounts[M].Drive,ClusLBA(M,C)+(Off Mod CB) Div 512);
  If B=0 Then Begin FatRead:=-EIO; Exit End;
  FarMove(BufSeg(B),O,Sg,Os+Done,Chunk);
  Inc(Done,Chunk); Inc(Off,Chunk);
 End;
 FatRead:=Done;
End;

Procedure FatUpdate(Var V: TVNode);
Var B: Integer; S,O: Word; T: Longint;
Begin
 If (V.Ino=0) Or (V.Typ<>VREG) Then Exit;
 B:=BRead(Mounts[V.Mnt].Drive,V.DirLBA);
 If B=0 Then Exit;
 S:=BufSeg(B); O:=V.DirIdx*32;
 MemW[S:O+26]:=Word(V.First); MemL[S:O+28]:=V.Size;
 T:=DosStamp(V.MTime);
 MemW[S:O+22]:=Word(T); MemW[S:O+24]:=Word(T Shr 16);
 MemW[S:O+18]:=Word(T Shr 16);
 BWrite(B);
 V.Dirty:=False;
End;

Function Extend(Var V: TVNode; Idx: Longint): Longint;
{ cluster numero Idx du fichier, alloue si besoin }
Var C,N,I: Longint;
Begin
 Extend:=0;
 If V.First<2 Then Begin
  N:=FatAlloc(V.Mnt); If N=0 Then Exit;
  V.First:=N; V.CIdx:=0; V.CClus:=N; V.Dirty:=True;
 End;
 C:=ClusterAt(V,Idx);
 If C<>0 Then Begin Extend:=C; Exit End;
 { aller a la fin de la chaine }
 C:=V.First; I:=0;
 While True Do Begin
  N:=FatGet(V.Mnt,C);
  If (N<2) Or (N=FATEOC) Then Break;
  C:=N; Inc(I);
 End;
 While I<Idx Do Begin
  N:=FatAlloc(V.Mnt); If N=0 Then Exit;
  FatSet(V.Mnt,C,N); C:=N; Inc(I);
 End;
 V.CIdx:=Idx; V.CClus:=C;
 Extend:=C;
End;

Function FatWrite(Var V: TVNode; Off: Longint; Sg, Os, N: Word): Integer;
Var Done,Chunk,O: Word; CB: Longint; C: Longint; B: Integer; M: Integer;
  Pad: Longint;
Begin
 M:=V.Mnt; CB:=Longint(Mounts[M].SecPerClus)*512;
 If Mounts[M].RO Then Begin FatWrite:=-EROFS; Exit End;
 { trou : rempli de zeros }
 While V.Size<Off Do Begin
  Pad:=Off-V.Size; If Pad>512 Then Pad:=512;
  C:=FatWrite(V,V.Size,Seg(ZeroBuf),Ofs(ZeroBuf),Pad);
  If C<=0 Then Begin FatWrite:=C; Exit End;
 End;
 Done:=0;
 While Done<N Do Begin
  C:=Extend(V,Off Div CB);
  If C=0 Then Begin
   If Done=0 Then Begin FatWrite:=-ENOSPC; Exit End;
   Break;
  End;
  O:=Off Mod 512; Chunk:=512-O; If Chunk>N-Done Then Chunk:=N-Done;
  If (O=0) And ((Chunk=512) Or (Off+Chunk>=V.Size)) Then Begin
   B:=BGet(Mounts[M].Drive,ClusLBA(M,C)+(Off Mod CB) Div 512);
   If Chunk<512 Then FarFill(BufSeg(B),0,512,0);
  End Else B:=BRead(Mounts[M].Drive,ClusLBA(M,C)+(Off Mod CB) Div 512);
  If B=0 Then Begin FatWrite:=-EIO; Exit End;
  FarMove(Sg,Os+Done,BufSeg(B),O,Chunk);
  If Not BWrite(B) Then Begin FatWrite:=-EIO; Exit End;
  Inc(Done,Chunk); Inc(Off,Chunk);
  If Off>V.Size Then V.Size:=Off;
 End;
 V.MTime:=KTime;
 FatUpdate(V);
 FatWrite:=Done;
End;

Function FatTrunc(Var V: TVNode): Integer;
Begin
 FatTrunc:=0;
 If V.Typ<>VREG Then Exit;
 If Mounts[V.Mnt].RO Then Begin FatTrunc:=EROFS; Exit End;
 FreeChain(V.Mnt,V.First);
 V.First:=0; V.Size:=0; V.CIdx:=0; V.CClus:=0; V.MTime:=KTime;
 FatUpdate(V);
End;

Function FatReadDir(Var V: TVNode; Var Pos: Longint; Var Name: TName;
  Var Ino: Longint; Var Typ: Byte): Boolean;
Var LBA: Longint; Idx: Word; B: Integer; S,O: Word; A: Byte;
Begin
 FatReadDir:=False;
 While DirSector(V,Pos,False,LBA,Idx) Do Begin
  B:=BRead(Mounts[V.Mnt].Drive,LBA);
  If B=0 Then Exit;
  S:=BufSeg(B); O:=Idx*32;
  If Mem[S:O]=0 Then Exit;
  Inc(Pos);
  A:=Mem[S:O+11];
  If (Mem[S:O]<>$E5) And (A<>$0F) And (A And 8=0) Then Begin
   Name:=From83(S,O); Ino:=LBA*16+Idx;
   If A And $10<>0 Then Typ:=VDIR Else Typ:=VREG;
   FatReadDir:=True; Exit;
  End;
 End;
End;

Function FreeSlot(Var Dir: TVNode; Var LBA: Longint; Var Idx: Word): Boolean;
Var I: Longint; B: Integer; S: Word;
Begin
 FreeSlot:=False; I:=0;
 While DirSector(Dir,I,Dir.First<>0,LBA,Idx) Do Begin
  B:=BRead(Mounts[Dir.Mnt].Drive,LBA);
  If B=0 Then Exit;
  S:=BufSeg(B);
  If (Mem[S:Idx*32]=0) Or (Mem[S:Idx*32]=$E5) Then Begin
   FreeSlot:=True; Exit;
  End;
  Inc(I);
  If I>65535 Then Exit;
 End;
End;

Procedure PutEntry(S, O: Word; N83: T83; Attr: Byte; First: Longint);
Var I: Integer; T: Longint;
Begin
 FarFill(S,O,32,0);
 For I:=0 To 10 Do Mem[S:O+I]:=Ord(N83[I+1]);
 Mem[S:O+11]:=Attr;
 T:=DosStamp(KTime);
 MemW[S:O+14]:=Word(T); MemW[S:O+16]:=Word(T Shr 16);
 MemW[S:O+18]:=Word(T Shr 16);
 MemW[S:O+22]:=Word(T); MemW[S:O+24]:=Word(T Shr 16);
 MemW[S:O+26]:=Word(First);
End;

Function FatCreate(Var Dir: TVNode; Name: TName; IsDir: Boolean;
  Var V: TVNode): Integer;
Var N83: T83; LBA,C: Longint; Idx: Word; B: Integer; S: Word;
Begin
 If Mounts[Dir.Mnt].RO Then Begin FatCreate:=EROFS; Exit End;
 If Not To83(Name,N83) Or (Name='.') Or (Name='..') Then Begin
  FatCreate:=ENAMETOOLONG; Exit;
 End;
 If Search(Dir,N83,LBA,Idx) Then Begin FatCreate:=EEXIST; Exit End;
 If Not FreeSlot(Dir,LBA,Idx) Then Begin FatCreate:=ENOSPC; Exit End;
 C:=0;
 If IsDir Then Begin
  C:=FatAlloc(Dir.Mnt);
  If C=0 Then Begin FatCreate:=ENOSPC; Exit End;
  ZeroCluster(Dir.Mnt,C);
  B:=BRead(Mounts[Dir.Mnt].Drive,ClusLBA(Dir.Mnt,C));
  If B=0 Then Begin FatCreate:=EIO; Exit End;
  PutEntry(BufSeg(B),0,'.          ',$10,C);
  PutEntry(BufSeg(B),32,'..         ',$10,Dir.First);
  BWrite(B);
 End;
 B:=BRead(Mounts[Dir.Mnt].Drive,LBA);
 If B=0 Then Begin FatCreate:=EIO; Exit End;
 S:=BufSeg(B);
 If IsDir Then PutEntry(S,Idx*32,N83,$10,C) Else PutEntry(S,Idx*32,N83,$20,0);
 If Not BWrite(B) Then Begin FatCreate:=EIO; Exit End;
 FillVn(Dir.Mnt,S,Idx*32,LBA,Idx,V);
 FatCreate:=0;
End;

Function DirEmpty(Var D: TVNode): Boolean;
Var Pos,Ino: Longint; Name: TName; Typ: Byte;
Begin
 DirEmpty:=True; Pos:=0;
 While FatReadDir(D,Pos,Name,Ino,Typ) Do
  If (Name<>'.') And (Name<>'..') Then Begin DirEmpty:=False; Exit End;
End;

Function FatRemove(Var Dir: TVNode; Name: TName; IsDir: Boolean): Integer;
Var N83: T83; LBA: Longint; Idx: Word; B: Integer; V: TVNode;
Begin
 If Mounts[Dir.Mnt].RO Then Begin FatRemove:=EROFS; Exit End;
 If (Name='.') Or (Name='..') Then Begin FatRemove:=EINVAL; Exit End;
 If Not To83(Name,N83) Then Begin FatRemove:=ENOENT; Exit End;
 If Not Search(Dir,N83,LBA,Idx) Then Begin FatRemove:=ENOENT; Exit End;
 B:=BRead(Mounts[Dir.Mnt].Drive,LBA);
 If B=0 Then Begin FatRemove:=EIO; Exit End;
 FillVn(Dir.Mnt,BufSeg(B),Idx*32,LBA,Idx,V);
 If IsDir And (V.Typ<>VDIR) Then Begin FatRemove:=ENOTDIR; Exit End;
 If Not IsDir And (V.Typ=VDIR) Then Begin FatRemove:=EISDIR; Exit End;
 If IsDir And Not DirEmpty(V) Then Begin FatRemove:=ENOTEMPTY; Exit End;
 FreeChain(Dir.Mnt,V.First);
 B:=BRead(Mounts[Dir.Mnt].Drive,LBA);
 If B=0 Then Begin FatRemove:=EIO; Exit End;
 Mem[BufSeg(B):Idx*32]:=$E5;
 BWrite(B);
 FatRemove:=0;
End;

Function FatRename(Var D1: TVNode; N1: TName; Var D2: TVNode;
  N2: TName): Integer;
Var A,B83: T83; L1,L2: Longint; I1,I2: Word; B,E: Integer;
  Raw: Array[0..31] Of Byte; V: TVNode;
Begin
 If Mounts[D1.Mnt].RO Then Begin FatRename:=EROFS; Exit End;
 If Not To83(N1,A) Or Not Search(D1,A,L1,I1) Then Begin
  FatRename:=ENOENT; Exit;
 End;
 If Not To83(N2,B83) Then Begin FatRename:=ENAMETOOLONG; Exit End;
 If Search(D2,B83,L2,I2) Then Begin
  E:=FatRemove(D2,N2,False);
  If E<>0 Then Begin FatRename:=EEXIST; Exit End;
  If Not Search(D1,A,L1,I1) Then Begin FatRename:=ENOENT; Exit End;
 End;
 B:=BRead(Mounts[D1.Mnt].Drive,L1);
 If B=0 Then Begin FatRename:=EIO; Exit End;
 FarMove(BufSeg(B),I1*32,Seg(Raw),Ofs(Raw),32);
 If Not FreeSlot(D2,L2,I2) Then Begin FatRename:=ENOSPC; Exit End;
 B:=BRead(Mounts[D1.Mnt].Drive,L2);
 If B=0 Then Begin FatRename:=EIO; Exit End;
 FarMove(Seg(Raw),Ofs(Raw),BufSeg(B),I2*32,32);
 For E:=0 To 10 Do Mem[BufSeg(B):I2*32+E]:=Ord(B83[E+1]);
 BWrite(B);
 B:=BRead(Mounts[D1.Mnt].Drive,L1);
 If B=0 Then Begin FatRename:=EIO; Exit End;
 Mem[BufSeg(B):I1*32]:=$E5;
 BWrite(B);
 { repertoire deplace : mise a jour de ".." }
 If (Raw[11] And $10<>0) And (D1.First<>D2.First) Then Begin
  V.Mnt:=D1.Mnt;
  B:=BRead(Mounts[D1.Mnt].Drive,ClusLBA(D1.Mnt,Raw[26]+Word(Raw[27]) Shl 8));
  If B<>0 Then Begin
   MemW[BufSeg(B):32+26]:=Word(D2.First); BWrite(B);
  End;
 End;
 FatRename:=0;
End;

SegmentEnd;

{ ====================================================================== }
SegmentUnit KUfs;
{ Systeme de fichiers UFS1 (Unix File System de FreeBSD, "makefs -t ffs",
  "newfs -O 1") : superbloc a l'octet 8192, groupes de cylindres, inodes de
  128 octets, blocs et fragments, blocs indirects simples et doubles,
  repertoires a entrees de longueur variable (d_type). En ecriture, les
  blocs sont alloues entiers puis le dernier bloc direct est ramene au
  nombre de fragments necessaire (regle de FFS) a la fermeture; les cartes
  des blocs libres, des grappes (clusters), les resumes frsum et les
  compteurs (groupe, table csum, superbloc) sont tenus a jour. }
Uses KTypes,KLib,KDisk;
SegmentInterface

Const UFSMAGIC=$011954; ROOTINO=2;

Function UfsMount(M: Integer): Integer;
Function UfsIGet(M: Integer; Ino: Longint; Var V: TVNode): Integer;
Function UfsLookup(Var Dir: TVNode; Name: TName; Var V: TVNode): Integer;
Function UfsRead(Var V: TVNode; Off: Longint; Sg, Os, N: Word): Integer;
Function UfsWrite(Var V: TVNode; Off: Longint; Sg, Os, N: Word): Integer;
Function UfsTrunc(Var V: TVNode): Integer;
Procedure UfsClose(Var V: TVNode);
Function UfsReadDir(Var V: TVNode; Var Pos: Longint; Var Name: TName;
  Var Ino: Longint; Var Typ: Byte): Boolean;
Function UfsCreate(Var Dir: TVNode; Name: TName; IsDir: Boolean;
  Mode: Word; Var V: TVNode): Integer;
Function UfsRemove(Var Dir: TVNode; Name: TName; IsDir: Boolean): Integer;
Function UfsRename(Var D1: TVNode; N1: TName; Var D2: TVNode;
  N2: TName): Integer;
Function UfsLink(Var Dir: TVNode; Name: TName; Var V: TVNode): Integer;
Function UfsChmod(Var V: TVNode; Mode: Word): Integer;
Function UfsSetAttr(Var V: TVNode): Integer;
Function UfsFreeKB(M: Integer): Longint;

SegmentImplementation

Var
 DirBuf: Array[0..511] Of Byte;
 GenCount: Longint;

{ --- acces au disque ------------------------------------------------- }

Function FragLBA(M: Integer; F: Longint): Longint;
Begin
 FragLBA:=F Shl Mounts[M].FsbToDb;
End;

Function SbGetL(M: Integer; Off: Word): Longint;
Var B: Integer;
Begin
 SbGetL:=0;
 B:=BRead(Mounts[M].Drive,16+Off Div 512);
 If B<>0 Then SbGetL:=MemL[BufSeg(B):Off Mod 512];
End;

Procedure SbAddL(M: Integer; Off: Word; D: Longint);
Var B: Integer;
Begin
 B:=BRead(Mounts[M].Drive,16+Off Div 512);
 If B=0 Then Exit;
 MemL[BufSeg(B):Off Mod 512]:=MemL[BufSeg(B):Off Mod 512]+D;
 BWrite(B);
End;

Function CgStart(M: Integer; Cg: Longint): Longint;
Begin
 With Mounts[M] Do CgStart:=Fpg*Cg+CgOffset*(Cg And Not CgMask);
End;

Function CgLBA(M: Integer; Cg: Longint; Off: Word): Longint;
Begin
 CgLBA:=FragLBA(M,CgStart(M,Cg)+Mounts[M].Cblkno)+Off Div 512;
End;

Function CgGetL(M: Integer; Cg: Longint; Off: Word): Longint;
Var B: Integer;
Begin
 CgGetL:=0;
 B:=BRead(Mounts[M].Drive,CgLBA(M,Cg,Off));
 If B<>0 Then CgGetL:=MemL[BufSeg(B):Off Mod 512];
End;

Procedure CgPutL(M: Integer; Cg: Longint; Off: Word; L: Longint);
Var B: Integer;
Begin
 B:=BRead(Mounts[M].Drive,CgLBA(M,Cg,Off));
 If B=0 Then Exit;
 MemL[BufSeg(B):Off Mod 512]:=L; BWrite(B);
End;

Function CgGetB(M: Integer; Cg: Longint; Off: Word): Byte;
Var B: Integer;
Begin
 CgGetB:=0;
 B:=BRead(Mounts[M].Drive,CgLBA(M,Cg,Off));
 If B<>0 Then CgGetB:=Mem[BufSeg(B):Off Mod 512];
End;

Procedure CgPutB(M: Integer; Cg: Longint; Off: Word; V: Byte);
Var B: Integer;
Begin
 B:=BRead(Mounts[M].Drive,CgLBA(M,Cg,Off));
 If B=0 Then Exit;
 Mem[BufSeg(B):Off Mod 512]:=V; BWrite(B);
End;

Function CgBit(M: Integer; Cg: Longint; MapOff: Word; Bit: Longint): Boolean;
Begin
 CgBit:=CgGetB(M,Cg,MapOff+Bit Div 8) And (1 Shl (Bit Mod 8))<>0;
End;

Procedure CgSetBit(M: Integer; Cg: Longint; MapOff: Word; Bit: Longint;
  On: Boolean);
Var V: Byte; O: Word;
Begin
 O:=MapOff+Bit Div 8;
 V:=CgGetB(M,Cg,O);
 If On Then V:=V Or (1 Shl (Bit Mod 8)) Else V:=V And Not (1 Shl (Bit Mod 8));
 CgPutB(M,Cg,O,V);
End;

Procedure Account(M: Integer; Cg: Longint; Field: Integer; D: Longint);
{ Field : 0 ndir, 1 nbfree, 2 nifree, 3 nffree. Groupe, table csum et
  superbloc (UFS1 32 bits et copie 64 bits). }
Var B: Integer; Off: Longint;
Begin
 CgPutL(M,Cg,24+Field*4,CgGetL(M,Cg,24+Field*4)+D);
 Off:=Cg*16+Field*4;
 B:=BRead(Mounts[M].Drive,FragLBA(M,Mounts[M].CsAddr)+Off Div 512);
 If B<>0 Then Begin
  MemL[BufSeg(B):Off Mod 512]:=MemL[BufSeg(B):Off Mod 512]+D; BWrite(B);
 End;
 SbAddL(M,192+Field*4,D);
 SbAddL(M,1008+Field*8,D);
End;

{ --- montage --------------------------------------------------------- }

Function UfsMount(M: Integer): Integer;
Var B: Integer; S: Word;
Begin
 UfsMount:=EIO;
 B:=BRead(Mounts[M].Drive,18);
 If B=0 Then Exit;
 UfsMount:=EINVAL;
 If MemL[BufSeg(B):1372-1024]<>UFSMAGIC Then Exit;
 B:=BRead(Mounts[M].Drive,16);
 If B=0 Then Begin UfsMount:=EIO; Exit End;
 S:=BufSeg(B);
 With Mounts[M] Do Begin
  Cblkno:=MemL[S:12]; Iblkno:=MemL[S:16]; Dblkno:=MemL[S:20];
  CgOffset:=MemL[S:24]; CgMask:=MemL[S:28];
  Sectors:=MemL[S:36];
  Ncg:=MemL[S:44]; BSize:=MemL[S:48]; FSize:=MemL[S:52]; Frag:=MemL[S:56];
  FsbToDb:=MemL[S:100]; Nindir:=MemL[S:116]; Inopb:=MemL[S:120];
  CsAddr:=MemL[S:152]; CgSize:=MemL[S:160];
  Ipg:=MemL[S:184]; Fpg:=MemL[S:188];
  If (BSize<4096) Or (FSize<512) Or (Frag<1) Or (Frag>8) Or (Ncg<1) Then Exit;
  Sectors:=Sectors Shl FsbToDb;
  Typ:=FSUFS;
 End;
 UfsMount:=0;
End;

Function UfsFreeKB(M: Integer): Longint;
Begin
 With Mounts[M] Do
  UfsFreeKB:=SbGetL(M,196)*(BSize Div 1024)+SbGetL(M,204)*(FSize Div 1024);
End;

{ --- inodes ---------------------------------------------------------- }

Procedure ILoc(M: Integer; Ino: Longint; Var LBA: Longint; Var Off: Word);
Var Cg,F,BO: Longint;
Begin
 With Mounts[M] Do Begin
  Cg:=Ino Div Ipg;
  F:=CgStart(M,Cg)+Iblkno+((Ino Mod Ipg) Div Inopb)*Frag;
  BO:=(Ino Mod Inopb)*128;
  LBA:=FragLBA(M,F)+BO Div 512; Off:=BO Mod 512;
 End;
End;

Function IGetL(Var V: TVNode; Field: Word): Longint;
Var LBA: Longint; O: Word; B: Integer;
Begin
 IGetL:=0;
 ILoc(V.Mnt,V.Ino,LBA,O);
 B:=BRead(Mounts[V.Mnt].Drive,LBA);
 If B<>0 Then IGetL:=MemL[BufSeg(B):O+Field];
End;

Procedure IPutL(Var V: TVNode; Field: Word; L: Longint);
Var LBA: Longint; O: Word; B: Integer;
Begin
 ILoc(V.Mnt,V.Ino,LBA,O);
 B:=BRead(Mounts[V.Mnt].Drive,LBA);
 If B=0 Then Exit;
 MemL[BufSeg(B):O+Field]:=L; BWrite(B);
End;

Procedure IUpdate(Var V: TVNode);
{ taille, mode, liens et dates de V dans l'inode }
Var LBA: Longint; O: Word; B: Integer; S: Word;
Begin
 ILoc(V.Mnt,V.Ino,LBA,O);
 B:=BRead(Mounts[V.Mnt].Drive,LBA);
 If B=0 Then Exit;
 S:=BufSeg(B);
 MemW[S:O]:=V.Mode; MemW[S:O+2]:=V.NLink;
 MemL[S:O+8]:=V.Size; MemL[S:O+12]:=0;
 MemL[S:O+24]:=V.MTime; MemL[S:O+32]:=KTime;
 MemL[S:O+112]:=V.Uid; MemL[S:O+116]:=V.Gid;
 BWrite(B);
End;

Function UfsIGet(M: Integer; Ino: Longint; Var V: TVNode): Integer;
Var LBA: Longint; O: Word; B: Integer; S: Word;
Begin
 UfsIGet:=EIO;
 FillChar(V,SizeOf(V),0);
 V.Mnt:=M; V.Ino:=Ino;
 If (Ino<2) Or (Ino>=Mounts[M].Ipg*Mounts[M].Ncg) Then Begin
  UfsIGet:=ENOENT; Exit;
 End;
 ILoc(M,Ino,LBA,O);
 B:=BRead(Mounts[M].Drive,LBA);
 If B=0 Then Exit;
 S:=BufSeg(B);
 V.Mode:=MemW[S:O]; V.NLink:=MemW[S:O+2];
 V.Size:=MemL[S:O+8]; V.MTime:=MemL[S:O+24];
 V.Uid:=MemW[S:O+112]; V.Gid:=MemW[S:O+116];
 Case V.Mode And S_IFMT Of
  S_IFDIR: V.Typ:=VDIR;
  S_IFREG: V.Typ:=VREG;
  S_IFCHR: V.Typ:=VCHR;
  S_IFIFO: V.Typ:=VFIFO;
  Else V.Typ:=VREG;
 End;
 UfsIGet:=0;
End;

{ --- allocation des blocs, fragments et inodes ----------------------- }

Procedure FragAcct(M: Integer; Cg: Longint; Map: Byte; Cnt: Integer);
{ resume frsum : chaque suite de fragments libres de longueur L (< Frag)
  dans le bloc decrit par Map }
Var I,L: Integer; F: Integer;
Begin
 F:=Mounts[M].Frag; L:=0;
 For I:=0 To F Do Begin
  If (I<F) And (Map And (1 Shl I)<>0) Then Inc(L)
  Else Begin
   If (L>0) And (L<F) Then CgPutL(M,Cg,52+L*4,CgGetL(M,Cg,52+L*4)+Cnt);
   L:=0;
  End;
 End;
End;

Procedure ClusterAcct(M: Integer; Cg, Blk: Longint; Cnt: Integer);
{ carte et resume des grappes de blocs libres (ffs_clusteracct) }
Var COff,SOff: Word; NBlk,I,Fwd,Back,Sz: Longint;
Begin
 If CgGetL(M,Cg,112)=0 Then Exit;
 SOff:=CgGetL(M,Cg,104); COff:=CgGetL(M,Cg,108);
 NBlk:=CgGetL(M,Cg,112);
 Sz:=SbGetL(M,1316);
 If Sz<=0 Then Exit;
 CgSetBit(M,Cg,COff,Blk,Cnt>0);
 Fwd:=0; I:=Blk+1;
 While (I<NBlk) And (Fwd<Sz) And CgBit(M,Cg,COff,I) Do Begin Inc(Fwd); Inc(I) End;
 Back:=0; I:=Blk-1;
 While (I>=0) And (Back<Sz) And CgBit(M,Cg,COff,I) Do Begin Inc(Back); Dec(I) End;
 I:=Back+Fwd+1; If I>Sz Then I:=Sz;
 CgPutL(M,Cg,SOff+I*4,CgGetL(M,Cg,SOff+I*4)+Cnt);
 If Back>0 Then CgPutL(M,Cg,SOff+Back*4,CgGetL(M,Cg,SOff+Back*4)-Cnt);
 If Fwd>0 Then CgPutL(M,Cg,SOff+Fwd*4,CgGetL(M,Cg,SOff+Fwd*4)-Cnt);
End;

Function BlockMap(M: Integer; Cg, Bno: Longint; FreeOff: Word): Byte;
{ bits des fragments du bloc commencant au fragment Bno (relatif au groupe) }
Var I: Integer; R: Byte;
Begin
 R:=0;
 For I:=0 To Mounts[M].Frag-1 Do
  If CgBit(M,Cg,FreeOff,Bno+I) Then R:=R Or (1 Shl I);
 BlockMap:=R;
End;

Function AllocBlock(M: Integer; Pref: Longint): Longint;
{ bloc entier libre (adresse en fragments), 0 si le disque est plein }
Var C,K,Bno,NB,FullB: Longint; FreeOff: Word; Map,Full: Byte; I: Integer;
Begin
 AllocBlock:=0;
 With Mounts[M] Do Begin
  Full:=(1 Shl Frag)-1;
  C:=Pref; If (C<0) Or (C>=Ncg) Then C:=0;
  For K:=1 To Ncg Do Begin
   If CgGetL(M,C,28)>0 Then Begin
    FreeOff:=CgGetL(M,C,96);
    NB:=CgGetL(M,C,20) Div Frag;
    For FullB:=0 To NB-1 Do Begin
     Bno:=FullB*Frag;
     If Frag=8 Then Map:=CgGetB(M,C,FreeOff+FullB)
     Else Map:=BlockMap(M,C,Bno,FreeOff);
     If Map=Full Then Begin
      For I:=0 To Frag-1 Do CgSetBit(M,C,FreeOff,Bno+I,False);
      Account(M,C,1,-1);
      ClusterAcct(M,C,FullB,-1);
      AllocBlock:=CgStart(M,C)-CgOffset*(C And Not CgMask)+Bno;
      Exit;
     End;
    End;
   End;
   Inc(C); If C>=Ncg Then C:=0;
  End;
 End;
End;

Procedure FreeFrags(M: Integer; Addr: Longint; Cnt: Integer);
{ libere Cnt fragments a partir de Addr (dans un meme bloc) }
Var C,Bno,BStart: Longint; FreeOff: Word; Before,After,Full: Byte; I: Integer;
Begin
 If (Addr<=0) Or (Cnt<=0) Then Exit;
 With Mounts[M] Do Begin
  C:=Addr Div Fpg; Bno:=Addr Mod Fpg; BStart:=Bno-Bno Mod Frag;
  FreeOff:=CgGetL(M,C,96);
  Full:=(1 Shl Frag)-1;
  Before:=BlockMap(M,C,BStart,FreeOff);
  If (Before<>0) And (Before<>Full) Then FragAcct(M,C,Before,-1);
  For I:=0 To Cnt-1 Do CgSetBit(M,C,FreeOff,Bno+I,True);
  After:=BlockMap(M,C,BStart,FreeOff);
  If Before=Full Then Exit; { deja libre (incoherence) }
  If Before<>0 Then Begin
   { le bloc contenait deja des fragments libres }
   Account(M,C,3,Cnt);
  End Else Account(M,C,3,Cnt);
  If After=Full Then Begin
   Account(M,C,3,-Frag); Account(M,C,1,1);
   ClusterAcct(M,C,BStart Div Frag,1);
  End Else FragAcct(M,C,After,1);
 End;
End;

Function AllocInode(M: Integer; IsDir: Boolean): Longint;
Var C,K,I: Longint; IOff: Word;
Begin
 AllocInode:=0;
 With Mounts[M] Do
  For K:=0 To Ncg-1 Do Begin
   C:=K;
   If CgGetL(M,C,32)>0 Then Begin
    IOff:=CgGetL(M,C,92);
    For I:=0 To Ipg-1 Do
     If ((C>0) Or (I>ROOTINO)) And Not CgBit(M,C,IOff,I) Then Begin
      CgSetBit(M,C,IOff,I,True);
      Account(M,C,2,-1);
      If IsDir Then Account(M,C,0,1);
      AllocInode:=C*Ipg+I;
      Exit;
     End;
   End;
  End;
End;

Procedure FreeInode(M: Integer; Ino: Longint; IsDir: Boolean);
Var C: Longint;
Begin
 With Mounts[M] Do Begin
  C:=Ino Div Ipg;
  CgSetBit(M,C,CgGetL(M,C,92),Ino Mod Ipg,False);
  Account(M,C,2,1);
  If IsDir Then Account(M,C,0,-1);
 End;
End;

{ --- correspondance blocs logiques -> fragments ---------------------- }

Function IndGet(M: Integer; Blk, Idx: Longint): Longint;
Var B: Integer;
Begin
 IndGet:=0;
 If Blk=0 Then Exit;
 B:=BRead(Mounts[M].Drive,FragLBA(M,Blk)+(Idx*4) Div 512);
 If B<>0 Then IndGet:=MemL[BufSeg(B):(Idx*4) Mod 512];
End;

Procedure IndPut(M: Integer; Blk, Idx, Val: Longint);
Var B: Integer;
Begin
 B:=BRead(Mounts[M].Drive,FragLBA(M,Blk)+(Idx*4) Div 512);
 If B=0 Then Exit;
 MemL[BufSeg(B):(Idx*4) Mod 512]:=Val; BWrite(B);
End;

Procedure ZeroBlock(M: Integer; Blk: Longint);
Var I: Integer; B: Integer;
Begin
 For I:=0 To (Mounts[M].BSize Div 512)-1 Do Begin
  B:=BGet(Mounts[M].Drive,FragLBA(M,Blk)+I);
  FarFill(BufSeg(B),0,512,0); BWrite(B);
 End;
End;

Function NewBlock(Var V: TVNode; Zero: Boolean): Longint;
Var A: Longint;
Begin
 A:=AllocBlock(V.Mnt,V.Ino Div Mounts[V.Mnt].Ipg);
 If A<>0 Then Begin
  If Zero Then ZeroBlock(V.Mnt,A);
  IPutL(V,104,IGetL(V,104)+Mounts[V.Mnt].BSize Div 512);
 End;
 NewBlock:=A;
End;

Function BMap(Var V: TVNode; Lbn: Longint; Alloc: Boolean): Longint;
{ fragment de debut du bloc logique Lbn (0 = trou) }
Var M: Integer; A,Ind,Ind2,L: Longint;
Begin
 BMap:=0; M:=V.Mnt;
 With Mounts[M] Do Begin
  If Lbn<12 Then Begin
   A:=IGetL(V,40+Lbn*4);
   If (A=0) And Alloc Then Begin
    A:=NewBlock(V,False); If A<>0 Then IPutL(V,40+Lbn*4,A);
   End;
   BMap:=A; Exit;
  End;
  L:=Lbn-12;
  If L<Nindir Then Begin
   Ind:=IGetL(V,88);
   If Ind=0 Then Begin
    If Not Alloc Then Exit;
    Ind:=NewBlock(V,True); If Ind=0 Then Exit;
    IPutL(V,88,Ind);
   End;
   A:=IndGet(M,Ind,L);
   If (A=0) And Alloc Then Begin
    A:=NewBlock(V,False); If A<>0 Then IndPut(M,Ind,L,A);
   End;
   BMap:=A; Exit;
  End;
  L:=L-Nindir;
  If L Div Nindir>=Nindir Then Exit;
  Ind2:=IGetL(V,92);
  If Ind2=0 Then Begin
   If Not Alloc Then Exit;
   Ind2:=NewBlock(V,True); If Ind2=0 Then Exit;
   IPutL(V,92,Ind2);
  End;
  Ind:=IndGet(M,Ind2,L Div Nindir);
  If Ind=0 Then Begin
   If Not Alloc Then Exit;
   Ind:=NewBlock(V,True); If Ind=0 Then Exit;
   IndPut(M,Ind2,L Div Nindir,Ind);
  End;
  A:=IndGet(M,Ind,L Mod Nindir);
  If (A=0) And Alloc Then Begin
   A:=NewBlock(V,False); If A<>0 Then IndPut(M,Ind,L Mod Nindir,A);
  End;
  BMap:=A;
 End;
End;

Function FragsOf(M: Integer; Size, Lbn: Longint): Longint;
{ fragments occupes par le bloc Lbn d'un fichier de Size octets (FFS) }
Var R: Longint;
Begin
 With Mounts[M] Do Begin
  If (Lbn>=12) Or ((Lbn+1)*BSize<=Size) Then Begin FragsOf:=Frag; Exit End;
  R:=Size-Lbn*BSize;
  If R<=0 Then FragsOf:=0 Else FragsOf:=(R+FSize-1) Div FSize;
 End;
End;

Function GrowTail(Var V: TVNode): Boolean;
{ le dernier bloc direct (fragments) devient un bloc entier; V.Dirty indique
  ensuite que tous les blocs du fichier sont entiers }
Var M: Integer; K,Old,New_,Cnt: Longint; I: Integer; B,B2: Integer;
Begin
 GrowTail:=True;
 M:=V.Mnt;
 If V.Dirty Then Exit;
 If V.Size=0 Then Begin V.Dirty:=True; Exit End;
 K:=(V.Size-1) Div Mounts[M].BSize;
 If K>=12 Then Begin V.Dirty:=True; Exit End;
 Cnt:=FragsOf(M,V.Size,K);
 If Cnt>=Mounts[M].Frag Then Begin V.Dirty:=True; Exit End;
 Old:=IGetL(V,40+K*4);
 If Old=0 Then Begin V.Dirty:=True; Exit End;
 New_:=AllocBlock(M,V.Ino Div Mounts[M].Ipg);
 If New_=0 Then Begin GrowTail:=False; Exit End;
 For I:=0 To (Cnt*Mounts[M].FSize) Div 512-1 Do Begin
  B:=BRead(Mounts[M].Drive,FragLBA(M,Old)+I);
  If B<>0 Then Begin
   B2:=BGet(Mounts[M].Drive,FragLBA(M,New_)+I);
   FarMove(BufSeg(B),0,BufSeg(B2),0,512); BWrite(B2);
  End;
 End;
 IPutL(V,40+K*4,New_);
 FreeFrags(M,Old,Cnt);
 IPutL(V,104,IGetL(V,104)+((Mounts[M].Frag-Cnt)*Mounts[M].FSize) Div 512);
 V.Dirty:=True;
End;

Procedure UfsClose(Var V: TVNode);
{ ramene le dernier bloc direct au nombre de fragments necessaire }
Var M: Integer; K,A,Cnt: Longint;
Begin
 If Not V.Dirty Then Exit;
 V.Dirty:=False;
 If V.Size=0 Then Exit;
 M:=V.Mnt;
 K:=(V.Size-1) Div Mounts[M].BSize;
 If K>=12 Then Exit;
 Cnt:=FragsOf(M,V.Size,K);
 A:=IGetL(V,40+K*4);
 If (A=0) Or (Cnt>=Mounts[M].Frag) Then Exit;
 FreeFrags(M,A+Cnt,Mounts[M].Frag-Cnt);
 IPutL(V,104,IGetL(V,104)-((Mounts[M].Frag-Cnt)*Mounts[M].FSize) Div 512);
End;

{ --- lecture et ecriture --------------------------------------------- }

Function UfsRead(Var V: TVNode; Off: Longint; Sg, Os, N: Word): Integer;
Var Done,Chunk,O: Word; A: Longint; B: Integer; M: Integer; BS: Longint;
Begin
 UfsRead:=0;
 If Off>=V.Size Then Exit;
 If Off+N>V.Size Then N:=V.Size-Off;
 M:=V.Mnt; BS:=Mounts[M].BSize; Done:=0;
 While Done<N Do Begin
  O:=Off Mod 512; Chunk:=512-O; If Chunk>N-Done Then Chunk:=N-Done;
  A:=BMap(V,Off Div BS,False);
  If A=0 Then FarFill(Sg,Os+Done,Chunk,0)
  Else Begin
   B:=BRead(Mounts[M].Drive,FragLBA(M,A)+(Off Mod BS) Div 512);
   If B=0 Then Begin UfsRead:=-EIO; Exit End;
   FarMove(BufSeg(B),O,Sg,Os+Done,Chunk);
  End;
  Inc(Done,Chunk); Inc(Off,Chunk);
 End;
 UfsRead:=Done;
End;

Function UfsWrite(Var V: TVNode; Off: Longint; Sg, Os, N: Word): Integer;
Var Done,Chunk,O: Word; A: Longint; B: Integer; M: Integer; BS,Pad: Longint;
  R: Integer;
Begin
 M:=V.Mnt; BS:=Mounts[M].BSize;
 If Mounts[M].RO Then Begin UfsWrite:=-EROFS; Exit End;
 If N=0 Then Begin UfsWrite:=0; Exit End;
 If Off+N>V.Size Then
  If Not GrowTail(V) Then Begin UfsWrite:=-ENOSPC; Exit End;
 While V.Size<Off Do Begin
  Pad:=Off-V.Size; If Pad>512 Then Pad:=512;
  R:=UfsWrite(V,V.Size,Seg(ZeroBuf),Ofs(ZeroBuf),Pad);
  If R<=0 Then Begin UfsWrite:=R; Exit End;
 End;
 Done:=0;
 While Done<N Do Begin
  A:=BMap(V,Off Div BS,True);
  If A=0 Then Begin
   If Done=0 Then Begin UfsWrite:=-ENOSPC; Exit End;
   Break;
  End;
  O:=Off Mod 512; Chunk:=512-O; If Chunk>N-Done Then Chunk:=N-Done;
  If (O=0) And ((Chunk=512) Or (Off+Chunk>=V.Size)) Then Begin
   B:=BGet(Mounts[M].Drive,FragLBA(M,A)+(Off Mod BS) Div 512);
   If Chunk<512 Then FarFill(BufSeg(B),0,512,0);
  End Else B:=BRead(Mounts[M].Drive,FragLBA(M,A)+(Off Mod BS) Div 512);
  If B=0 Then Begin UfsWrite:=-EIO; Exit End;
  FarMove(Sg,Os+Done,BufSeg(B),O,Chunk);
  If Not BWrite(B) Then Begin UfsWrite:=-EIO; Exit End;
  Inc(Done,Chunk); Inc(Off,Chunk);
  If Off>V.Size Then V.Size:=Off;
 End;
 V.MTime:=KTime;
 IUpdate(V);
 UfsWrite:=Done;
End;

Function UfsTrunc(Var V: TVNode): Integer;
Var M: Integer; I,J,A,Ind,Ind2: Longint;
Begin
 UfsTrunc:=0; M:=V.Mnt;
 If Mounts[M].RO Then Begin UfsTrunc:=EROFS; Exit End;
 If V.Typ<>VREG Then Exit;
 With Mounts[M] Do Begin
  For I:=0 To 11 Do Begin
   A:=IGetL(V,40+I*4);
   If A<>0 Then Begin
    If V.Dirty Then FreeFrags(M,A,Frag) Else FreeFrags(M,A,FragsOf(M,V.Size,I));
    IPutL(V,40+I*4,0);
   End;
  End;
  Ind:=IGetL(V,88);
  If Ind<>0 Then Begin
   For J:=0 To Nindir-1 Do Begin
    A:=IndGet(M,Ind,J); If A<>0 Then FreeFrags(M,A,Frag);
   End;
   FreeFrags(M,Ind,Frag); IPutL(V,88,0);
  End;
  Ind2:=IGetL(V,92);
  If Ind2<>0 Then Begin
   For I:=0 To Nindir-1 Do Begin
    Ind:=IndGet(M,Ind2,I);
    If Ind<>0 Then Begin
     For J:=0 To Nindir-1 Do Begin
      A:=IndGet(M,Ind,J); If A<>0 Then FreeFrags(M,A,Frag);
     End;
     FreeFrags(M,Ind,Frag);
    End;
   End;
   FreeFrags(M,Ind2,Frag); IPutL(V,92,0);
  End;
 End;
 IPutL(V,104,0);
 V.Size:=0; V.Dirty:=False; V.MTime:=KTime;
 IUpdate(V);
End;

{ --- repertoires ----------------------------------------------------- }

Function UfsReadDir(Var V: TVNode; Var Pos: Longint; Var Name: TName;
  Var Ino: Longint; Var Typ: Byte): Boolean;
Var Base: Longint; O,RecLen: Word; NL,I: Integer; T: Byte;
Begin
 UfsReadDir:=False;
 While Pos<V.Size Do Begin
  Base:=Pos-Pos Mod 512;
  If UfsRead(V,Base,Seg(DirBuf),Ofs(DirBuf),512)<=0 Then Exit;
  O:=Pos Mod 512;
  RecLen:=DirBuf[O+4]+Word(DirBuf[O+5]) Shl 8;
  If (RecLen<8) Or (O+RecLen>512) Then Begin Pos:=Base+512; Continue End;
  Inc(Pos,RecLen);
  Ino:=MemL[Seg(DirBuf):Ofs(DirBuf)+O];
  If Ino<>0 Then Begin
   NL:=DirBuf[O+7]; Name:='';
   For I:=0 To NL-1 Do If Length(Name)<63 Then Name:=Name+Chr(DirBuf[O+8+I]);
   T:=DirBuf[O+6];
   Case T Of
    4: Typ:=VDIR;
    2: Typ:=VCHR;
    1: Typ:=VFIFO;
    Else Typ:=VREG;
   End;
   UfsReadDir:=True; Exit;
  End;
 End;
End;

Function FindName(Var Dir: TVNode; Var Name: TName; Var Ino: Longint): Boolean;
{ cherche Name dans Dir; Name recoit le nom tel qu'il est enregistre }
Var Pos,I: Longint; N: TName; T: Byte; U: TName;
Begin
 FindName:=False; Pos:=0;
 While UfsReadDir(Dir,Pos,N,I,T) Do
  If N=Name Then Begin Ino:=I; FindName:=True; Exit End;
 { programme DOS (executable MZ) : noms en majuscules, comparaison sans
   tenir compte de la casse; un programme LINUX-0 (COFF) a la semantique
   UNIX (casse significative) }
 If Not Procs[Cur].DosProg Then Exit;
 U:=UpStr(Name); Pos:=0;
 While UfsReadDir(Dir,Pos,N,I,T) Do
  If UpStr(N)=U Then Begin Ino:=I; Name:=N; FindName:=True; Exit End;
End;

Function Find(Var Dir: TVNode; Name: TName; Var Ino: Longint): Boolean;
Begin
 Find:=FindName(Dir,Name,Ino);
End;

Function UfsLookup(Var Dir: TVNode; Name: TName; Var V: TVNode): Integer;
Var Ino: Longint;
Begin
 If Not Find(Dir,Name,Ino) Then Begin UfsLookup:=ENOENT; Exit End;
 UfsLookup:=UfsIGet(Dir.Mnt,Ino,V);
End;

Function DType(Typ: Byte): Byte;
Begin
 Case Typ Of VDIR: DType:=4; VCHR: DType:=2; VFIFO: DType:=1; Else DType:=8; End;
End;

Function AddEntry(Var Dir: TVNode; Name: TName; Ino: Longint;
  Typ: Byte): Integer;
Var Base: Longint; O,RecLen,Act,Need: Word; I: Integer; Done: Boolean;
Begin
 AddEntry:=0;
 Need:=8+((Length(Name)+1+3) And Not 3);
 Base:=0; Done:=False;
 While (Base<Dir.Size) And Not Done Do Begin
  If UfsRead(Dir,Base,Seg(DirBuf),Ofs(DirBuf),512)<=0 Then Begin
   AddEntry:=EIO; Exit;
  End;
  O:=0;
  While O<512 Do Begin
   RecLen:=DirBuf[O+4]+Word(DirBuf[O+5]) Shl 8;
   If RecLen<8 Then Break;
   If MemL[Seg(DirBuf):Ofs(DirBuf)+O]=0 Then Act:=0
   Else Act:=8+((DirBuf[O+7]+1+3) And Not 3);
   If RecLen-Act>=Need Then Begin
    If Act>0 Then Begin
     DirBuf[O+4]:=Lo(Act); DirBuf[O+5]:=Hi(Act);
     O:=O+Act; RecLen:=RecLen-Act;
    End;
    MemL[Seg(DirBuf):Ofs(DirBuf)+O]:=Ino;
    DirBuf[O+4]:=Lo(RecLen); DirBuf[O+5]:=Hi(RecLen);
    DirBuf[O+6]:=DType(Typ); DirBuf[O+7]:=Length(Name);
    For I:=1 To Length(Name) Do DirBuf[O+7+I]:=Ord(Name[I]);
    For I:=Length(Name)+1 To ((Length(Name)+1+3) And Not 3) Do
      DirBuf[O+7+I]:=0;
    Done:=True; Break;
   End;
   O:=O+RecLen;
  End;
  If Done Then Begin
   If UfsWrite(Dir,Base,Seg(DirBuf),Ofs(DirBuf),512)<>512 Then AddEntry:=EIO;
   Exit;
  End;
  Inc(Base,512);
 End;
 { nouveau bloc de repertoire }
 FillChar(DirBuf,SizeOf(DirBuf),0);
 MemL[Seg(DirBuf):Ofs(DirBuf)]:=Ino;
 DirBuf[4]:=0; DirBuf[5]:=2;
 DirBuf[6]:=DType(Typ); DirBuf[7]:=Length(Name);
 For I:=1 To Length(Name) Do DirBuf[7+I]:=Ord(Name[I]);
 If UfsWrite(Dir,Dir.Size,Seg(DirBuf),Ofs(DirBuf),512)<>512 Then
   AddEntry:=ENOSPC;
 UfsClose(Dir);
End;

Function DelEntry(Var Dir: TVNode; Name: TName): Integer;
Var Base: Longint; O,P,RecLen: Word; NL,I: Integer; Ok: Boolean;
Begin
 DelEntry:=ENOENT; Base:=0;
 While Base<Dir.Size Do Begin
  If UfsRead(Dir,Base,Seg(DirBuf),Ofs(DirBuf),512)<=0 Then Begin
   DelEntry:=EIO; Exit;
  End;
  O:=0; P:=$FFFF;
  While O<512 Do Begin
   RecLen:=DirBuf[O+4]+Word(DirBuf[O+5]) Shl 8;
   If RecLen<8 Then Break;
   If MemL[Seg(DirBuf):Ofs(DirBuf)+O]<>0 Then Begin
    NL:=DirBuf[O+7]; Ok:=NL=Length(Name);
    If Ok Then For I:=1 To NL Do If DirBuf[O+7+I]<>Ord(Name[I]) Then Ok:=False;
    If Ok Then Begin
     If P=$FFFF Then MemL[Seg(DirBuf):Ofs(DirBuf)+O]:=0
     Else Begin
      RecLen:=RecLen+DirBuf[P+4]+Word(DirBuf[P+5]) Shl 8;
      DirBuf[P+4]:=Lo(RecLen); DirBuf[P+5]:=Hi(RecLen);
     End;
     If UfsWrite(Dir,Base,Seg(DirBuf),Ofs(DirBuf),512)<>512 Then
       DelEntry:=EIO Else DelEntry:=0;
     UfsClose(Dir);
     Exit;
    End;
   End;
   P:=O; O:=O+RecLen;
  End;
  Inc(Base,512);
 End;
End;

Function InitInode(Var V: TVNode; M: Integer; Ino: Longint; Mode: Word;
  NLink: Word): Integer;
Var LBA: Longint; O: Word; B: Integer; S: Word; T: Longint;
Begin
 InitInode:=EIO;
 ILoc(M,Ino,LBA,O);
 B:=BRead(Mounts[M].Drive,LBA);
 If B=0 Then Exit;
 S:=BufSeg(B);
 FarFill(S,O,128,0);
 T:=KTime; Inc(GenCount);
 MemW[S:O]:=Mode; MemW[S:O+2]:=NLink;
 MemL[S:O+16]:=T; MemL[S:O+24]:=T; MemL[S:O+32]:=T;
 MemL[S:O+108]:=T Xor GenCount;
 MemW[S:O+112]:=Procs[Cur].Uid; MemW[S:O+116]:=Procs[Cur].Gid;
 If Not BWrite(B) Then Exit;
 FillChar(V,SizeOf(V),0);
 V.Mnt:=M; V.Ino:=Ino; V.Mode:=Mode; V.NLink:=NLink; V.MTime:=T;
 V.Uid:=Procs[Cur].Uid; V.Gid:=Procs[Cur].Gid;
 If Mode And S_IFMT=S_IFDIR Then V.Typ:=VDIR Else V.Typ:=VREG;
 InitInode:=0;
End;

Function UfsCreate(Var Dir: TVNode; Name: TName; IsDir: Boolean;
  Mode: Word; Var V: TVNode): Integer;
Var M: Integer; Ino,X: Longint; E: Integer;
Begin
 M:=Dir.Mnt;
 If Mounts[M].RO Then Begin UfsCreate:=EROFS; Exit End;
 If (Name='') Or (Name='.') Or (Name='..') Then Begin UfsCreate:=EINVAL; Exit End;
 If Length(Name)>63 Then Begin UfsCreate:=ENAMETOOLONG; Exit End;
 If Find(Dir,Name,X) Then Begin UfsCreate:=EEXIST; Exit End;
 Ino:=AllocInode(M,IsDir);
 If Ino=0 Then Begin UfsCreate:=ENOSPC; Exit End;
 If IsDir Then E:=InitInode(V,M,Ino,S_IFDIR Or (Mode And $FFF),2)
 Else E:=InitInode(V,M,Ino,S_IFREG Or (Mode And $FFF),1);
 If E<>0 Then Begin UfsCreate:=E; Exit End;
 If IsDir Then Begin
  { "." et ".." }
  FillChar(DirBuf,SizeOf(DirBuf),0);
  MemL[Seg(DirBuf):Ofs(DirBuf)]:=Ino; DirBuf[4]:=12; DirBuf[6]:=4;
  DirBuf[7]:=1; DirBuf[8]:=Ord('.');
  MemL[Seg(DirBuf):Ofs(DirBuf)+12]:=Dir.Ino; DirBuf[16]:=Lo(500);
  DirBuf[17]:=Hi(500); DirBuf[18]:=4; DirBuf[19]:=2; DirBuf[20]:=Ord('.');
  DirBuf[21]:=Ord('.');
  If UfsWrite(V,0,Seg(DirBuf),Ofs(DirBuf),512)<>512 Then Begin
   UfsCreate:=ENOSPC; Exit;
  End;
  UfsClose(V);
  Inc(Dir.NLink); IUpdate(Dir);
 End;
 E:=AddEntry(Dir,Name,Ino,V.Typ);
 UfsCreate:=E;
End;

Function DirEmpty(Var D: TVNode): Boolean;
Var Pos,Ino: Longint; N: TName; T: Byte;
Begin
 DirEmpty:=True; Pos:=0;
 While UfsReadDir(D,Pos,N,Ino,T) Do
  If (N<>'.') And (N<>'..') Then Begin DirEmpty:=False; Exit End;
End;

Function UfsRemove(Var Dir: TVNode; Name: TName; IsDir: Boolean): Integer;
Var Ino: Longint; V: TVNode; E: Integer;
Begin
 If Mounts[Dir.Mnt].RO Then Begin UfsRemove:=EROFS; Exit End;
 If (Name='.') Or (Name='..') Then Begin UfsRemove:=EINVAL; Exit End;
 If Not FindName(Dir,Name,Ino) Then Begin UfsRemove:=ENOENT; Exit End;
 E:=UfsIGet(Dir.Mnt,Ino,V);
 If E<>0 Then Begin UfsRemove:=E; Exit End;
 If IsDir And (V.Typ<>VDIR) Then Begin UfsRemove:=ENOTDIR; Exit End;
 If Not IsDir And (V.Typ=VDIR) Then Begin UfsRemove:=EISDIR; Exit End;
 If IsDir And Not DirEmpty(V) Then Begin UfsRemove:=ENOTEMPTY; Exit End;
 E:=DelEntry(Dir,Name);
 If E<>0 Then Begin UfsRemove:=E; Exit End;
 If IsDir Then Begin
  V.NLink:=0;
  If Dir.NLink>2 Then Dec(Dir.NLink);
  IUpdate(Dir);
 End Else If V.NLink>0 Then Dec(V.NLink);
 If V.NLink=0 Then Begin
  V.Typ:=VREG; UfsTrunc(V);
  V.Mode:=0; IUpdate(V);
  FreeInode(Dir.Mnt,Ino,IsDir);
 End Else IUpdate(V);
 UfsRemove:=0;
End;

Function UfsLink(Var Dir: TVNode; Name: TName; Var V: TVNode): Integer;
Var X: Longint; E: Integer;
Begin
 If Mounts[Dir.Mnt].RO Then Begin UfsLink:=EROFS; Exit End;
 If V.Typ=VDIR Then Begin UfsLink:=EPERM; Exit End;
 If Find(Dir,Name,X) Then Begin UfsLink:=EEXIST; Exit End;
 E:=AddEntry(Dir,Name,V.Ino,V.Typ);
 If E=0 Then Begin Inc(V.NLink); IUpdate(V) End;
 UfsLink:=E;
End;

Function UfsRename(Var D1: TVNode; N1: TName; Var D2: TVNode;
  N2: TName): Integer;
Var Ino,X: Longint; V: TVNode; E: Integer;
Begin
 If Mounts[D1.Mnt].RO Then Begin UfsRename:=EROFS; Exit End;
 If Not FindName(D1,N1,Ino) Then Begin UfsRename:=ENOENT; Exit End;
 E:=UfsIGet(D1.Mnt,Ino,V);
 If E<>0 Then Begin UfsRename:=E; Exit End;
 If Find(D2,N2,X) Then Begin
  If X=Ino Then Begin UfsRename:=0; Exit End;
  E:=UfsRemove(D2,N2,False);
  If E<>0 Then Begin UfsRename:=E; Exit End;
 End;
 E:=AddEntry(D2,N2,Ino,V.Typ);
 If E<>0 Then Begin UfsRename:=E; Exit End;
 E:=DelEntry(D1,N1);
 If (V.Typ=VDIR) And (D1.Ino<>D2.Ino) Then Begin
  { ".." du repertoire deplace }
  If UfsRead(V,0,Seg(DirBuf),Ofs(DirBuf),512)=512 Then Begin
   MemL[Seg(DirBuf):Ofs(DirBuf)+12]:=D2.Ino;
   UfsWrite(V,0,Seg(DirBuf),Ofs(DirBuf),512); UfsClose(V);
  End;
  If D1.NLink>2 Then Dec(D1.NLink); IUpdate(D1);
  Inc(D2.NLink); IUpdate(D2);
 End;
 UfsRename:=E;
End;

Function UfsChmod(Var V: TVNode; Mode: Word): Integer;
Begin
 If Mounts[V.Mnt].RO Then Begin UfsChmod:=EROFS; Exit End;
 V.Mode:=(V.Mode And S_IFMT) Or (Mode And $FFF);
 IUpdate(V);
 UfsChmod:=0;
End;

Function UfsSetAttr(Var V: TVNode): Integer;
{ proprietaire, groupe et date de modification de V ecrits dans l'inode }
Begin
 If Mounts[V.Mnt].RO Then Begin UfsSetAttr:=EROFS; Exit End;
 IUpdate(V);
 UfsSetAttr:=0;
End;

SegmentEnd;

{ ====================================================================== }
SegmentUnit KVfs;
{ Systeme de fichiers virtuel : table des vnodes, resolution des chemins
  (namei), table des montages, fichiers ouverts, /dev et tubes. }
Uses KTypes,KLib,KSched,KDisk,KTty,KFat,KUfs;
SegmentInterface

Var
 PipeUsed: Array[0..NPIPE-1] Of Boolean;
 PipeReaders, PipeWriters, PipeHead, PipeCount: Array[0..NPIPE-1] Of Word;

Function NormPath(Base: TPath; Path: String): TPath;
Function VGet(Var T: TVNode): Integer;
Procedure VPut(I: Integer);
Procedure VRef(I: Integer);
Function Namei(Path: TPath; Var Vn: Integer): Integer;
Function NameiParent(Path: TPath; Var Dir: Integer; Var Last: TName): Integer;
Function VRead(Vn: Integer; Off: Longint; Sg, Os, N: Word): Integer;
Function VWrite(Vn: Integer; Off: Longint; Sg, Os, N: Word): Integer;
Function VTrunc(Vn: Integer): Integer;
Function VReadDir(Vn: Integer; Var Pos: Longint; Var Name: TName;
  Var Ino: Longint; Var Typ: Byte): Boolean;
Function VCreate(Dir: Integer; Name: TName; IsDir: Boolean; Mode: Word;
  Var Vn: Integer): Integer;
Function VRemove(Dir: Integer; Name: TName; IsDir: Boolean): Integer;
Function VRename(D1: Integer; N1: TName; D2: Integer; N2: TName): Integer;
Function VLink(Dir: Integer; Name: TName; Vn: Integer): Integer;
Function VChmod(Vn: Integer; Mode: Word): Integer;
Function VChown(Vn: Integer; U, G: Word): Integer;
Function VUtime(Vn: Integer; T: Longint): Integer;
Function VAccess(Vn: Integer; Want: Word): Integer;
Function DoMount(Special, Dir: TPath; FsType: Word): Integer;
Function DoUmount(Dir: TPath): Integer;
Function MountFree(M: Integer): Longint;
Function IsMountDir(P: TPath): Boolean;
Function FAlloc(Vn: Integer; Flags: Word): Integer;
Procedure FRef(F: Integer);
Procedure FClose(F: Integer);
Function PipeAlloc(Var R, W: Integer): Integer;
Function DevName(Minor: Word): TName;
Procedure DevRegisterDisks;

SegmentImplementation

Var
 PipeBuf: Array[0..NPIPE-1,0..PIPESIZE-1] Of Byte;

Function NormPath(Base: TPath; Path: String): TPath;
{ chemin absolu sans ".", ".." ni "/" doubles }
Var R: String; C: TName; I,J: Integer;
Begin
 If (Path='') Or (Path[1]<>'/') Then Path:=Base+'/'+Path;
 R:=''; I:=1;
 While I<=Length(Path) Do Begin
  While (I<=Length(Path)) And (Path[I]='/') Do Inc(I);
  C:='';
  While (I<=Length(Path)) And (Path[I]<>'/') Do Begin C:=C+Path[I]; Inc(I) End;
  If (C='') Or (C='.') Then Continue;
  If C='..' Then Begin
   J:=Length(R);
   While (J>0) And (R[J]<>'/') Do Dec(J);
   If J>0 Then R:=Copy(R,1,J-1) Else R:='';
  End Else R:=R+'/'+C;
 End;
 If R='' Then R:='/';
 If Length(R)>127 Then R:=Copy(R,1,127);
 NormPath:=R;
End;

Function VGet(Var T: TVNode): Integer;
{ vnode de la table equivalent a T (meme systeme, meme inode), reference }
Var I,F: Integer;
Begin
 F:=0;
 For I:=1 To NVNODE Do
  If VNodes[I].Ref>0 Then Begin
   If (T.Typ<>VFIFO) And (VNodes[I].Typ=T.Typ) And (VNodes[I].Mnt=T.Mnt) And
     (VNodes[I].Ino=T.Ino) Then Begin
    Inc(VNodes[I].Ref); VGet:=I; Exit;
   End;
  End Else If F=0 Then F:=I;
 If F=0 Then Begin VGet:=0; Exit End;
 VNodes[F]:=T; VNodes[F].Ref:=1;
 VGet:=F;
End;

Procedure VRef(I: Integer);
Begin
 If I>0 Then Inc(VNodes[I].Ref);
End;

Procedure VPut(I: Integer);
Begin
 If (I<=0) Or (VNodes[I].Ref=0) Then Exit;
 Dec(VNodes[I].Ref);
 If VNodes[I].Ref=0 Then
  If VNodes[I].Mnt>0 Then
   If Mounts[VNodes[I].Mnt].Typ=FSUFS Then UfsClose(VNodes[I]);
End;

{ --- /dev ------------------------------------------------------------- }

Function DevName(Minor: Word): TName;
Begin
 Case Minor Of
  DEVTTY: DevName:='tty';
  DEVNULL: DevName:='null';
  DEVZERO: DevName:='zero';
  Else If (Minor>=DEVDISK) And (Minor<DEVDISK+DiskCount) Then
   DevName:=Disks[Minor-DEVDISK].Name
  Else DevName:='';
 End;
End;

Procedure DevRegisterDisks;
Begin
End;

Function DevMinor(Name: TName): Integer;
Var I: Integer;
Begin
 DevMinor:=0;
 If Name='console' Then Begin DevMinor:=DEVTTY; Exit End;
 For I:=1 To DEVDISK+DiskCount-1 Do
  If (DevName(I)<>'') And (DevName(I)=Name) Then Begin DevMinor:=I; Exit End;
End;

Procedure DevVn(M: Integer; Minor: Word; Var T: TVNode);
Begin
 FillChar(T,SizeOf(T),0);
 T.Mnt:=M; T.Typ:=VCHR; T.Ino:=Minor; T.Minor:=Minor;
 T.Mode:=S_IFCHR Or $1B6; T.NLink:=1; T.MTime:=BootTime;
 If Minor>=DEVDISK Then Begin
  T.Size:=Disks[Minor-DEVDISK].Sectors*512;
  T.Mode:=S_IFCHR Or $1A0;
 End;
End;

Function DevLookup(M: Integer; Name: TName; Var T: TVNode): Integer;
Var N: Integer;
Begin
 N:=DevMinor(Name);
 If N=0 Then Begin DevLookup:=ENOENT; Exit End;
 DevVn(M,N,T);
 DevLookup:=0;
End;

Function DevReadDir(Var Pos: Longint; Var Name: TName; Var Ino: Longint;
  Var Typ: Byte): Boolean;
Begin
 DevReadDir:=False;
 While Pos<DEVDISK+DiskCount Do Begin
  Inc(Pos);
  Name:=DevName(Pos);
  If Name<>'' Then Begin Ino:=Pos; Typ:=VCHR; DevReadDir:=True; Exit End;
 End;
End;

Function DiskSize(D: Integer): Longint;
Begin
 SetGeometry(D);
 With Disks[D] Do
  If Sectors<>0 Then DiskSize:=Sectors
  Else DiskSize:=Longint(Spt)*Heads*Cyls;
End;

Function DevRW(Minor: Word; Off: Longint; Sg, Os, N: Word;
  Wr: Boolean): Integer;
Var D,B: Integer; Done,Chunk,O: Word; Err: Integer; Lim: Longint;
Begin
 Case Minor Of
  DEVTTY: If Wr Then DevRW:=TtyWrite(Sg,Os,N)
          Else Begin
           DevRW:=TtyRead(Sg,Os,N,Err);
           If Err<>0 Then DevRW:=-Err;
          End;
  DEVNULL: If Wr Then DevRW:=N Else DevRW:=0;
  DEVZERO: Begin If Not Wr Then FarFill(Sg,Os,N,0); DevRW:=N End;
  Else Begin
   D:=Minor-DEVDISK;
   If (D<0) Or (D>=DiskCount) Then Begin DevRW:=-ENXIO; Exit End;
   Lim:=DiskSize(D)*512;
   If (Lim>0) And (Off>=Lim) Then Begin DevRW:=0; Exit End;
   If (Lim>0) And (Off+N>Lim) Then N:=Lim-Off;
   Done:=0;
   While Done<N Do Begin
    O:=Off Mod 512; Chunk:=512-O; If Chunk>N-Done Then Chunk:=N-Done;
    If Wr And (Chunk=512) Then B:=BGet(D,Off Div 512)
    Else B:=BRead(D,Off Div 512);
    If B=0 Then Begin
     If Done=0 Then DevRW:=-EIO Else DevRW:=Done;
     Exit;
    End;
    If Wr Then Begin
     FarMove(Sg,Os+Done,BufSeg(B),O,Chunk);
     If Not BWrite(B) Then Begin DevRW:=-EIO; Exit End;
    End Else FarMove(BufSeg(B),O,Sg,Os+Done,Chunk);
    Inc(Done,Chunk); Inc(Off,Chunk);
   End;
   DevRW:=Done;
  End;
 End;
End;

{ --- tubes ------------------------------------------------------------ }

Function PipeAlloc(Var R, W: Integer): Integer;
Var P,V: Integer; T: TVNode;
Begin
 PipeAlloc:=ENFILE;
 For P:=0 To NPIPE-1 Do If Not PipeUsed[P] Then Begin
  FillChar(T,SizeOf(T),0);
  T.Typ:=VFIFO; T.Minor:=P; T.Mode:=S_IFIFO Or $180; T.NLink:=1;
  T.MTime:=KTime; T.Ino:=P;
  V:=VGet(T);
  If V=0 Then Exit;
  R:=FAlloc(V,O_RDONLY);
  If R=0 Then Begin VPut(V); Exit End;
  VRef(V);
  W:=FAlloc(V,O_WRONLY);
  If W=0 Then Begin FClose(R); VPut(V); Exit End;
  PipeUsed[P]:=True; PipeReaders[P]:=1; PipeWriters[P]:=1;
  PipeHead[P]:=0; PipeCount[P]:=0;
  PipeAlloc:=0; Exit;
 End;
End;

Function PipeRead(P: Integer; Sg, Os, N: Word): Integer;
Var Done: Word;
Begin
 While PipeCount[P]=0 Do Begin
  If PipeWriters[P]=0 Then Begin PipeRead:=0; Exit End;
  If Not SleepIntr(CHPIPE+P) Then Begin PipeRead:=-EINTR; Exit End;
 End;
 Done:=0;
 While (Done<N) And (PipeCount[P]>0) Do Begin
  Mem[Sg:Os+Done]:=PipeBuf[P,PipeHead[P]];
  PipeHead[P]:=(PipeHead[P]+1) Mod PIPESIZE; Dec(PipeCount[P]); Inc(Done);
 End;
 Wakeup(CHPIPE+P);
 PipeRead:=Done;
End;

Function PipeWrite(P: Integer; Sg, Os, N: Word): Integer;
Var Done: Word;
Begin
 Done:=0;
 While Done<N Do Begin
  If PipeReaders[P]=0 Then Begin
   PostSig(Cur,SIGPIPE); PipeWrite:=-EPIPE; Exit;
  End;
  If PipeCount[P]=PIPESIZE Then Begin
   Wakeup(CHPIPE+P);
   If Not SleepIntr(CHPIPE+P) Then Begin
    If Done>0 Then PipeWrite:=Done Else PipeWrite:=-EINTR;
    Exit;
   End;
   Continue;
  End;
  PipeBuf[P,(PipeHead[P]+PipeCount[P]) Mod PIPESIZE]:=Mem[Sg:Os+Done];
  Inc(PipeCount[P]); Inc(Done);
 End;
 Wakeup(CHPIPE+P);
 PipeWrite:=Done;
End;

{ --- fichiers ouverts ------------------------------------------------- }

Function FAlloc(Vn: Integer; Flags: Word): Integer;
Var I: Integer;
Begin
 FAlloc:=0;
 For I:=1 To NFILE Do If Files[I].Ref=0 Then Begin
  Files[I].Ref:=1; Files[I].Vn:=Vn; Files[I].Flags:=Flags; Files[I].Off:=0;
  FAlloc:=I; Exit;
 End;
End;

Procedure FRef(F: Integer);
Begin
 If F>0 Then Inc(Files[F].Ref);
End;

Procedure FClose(F: Integer);
Var V,P: Integer;
Begin
 If (F<=0) Or (Files[F].Ref=0) Then Exit;
 Dec(Files[F].Ref);
 If Files[F].Ref>0 Then Exit;
 V:=Files[F].Vn;
 If (V>0) And (VNodes[V].Typ=VFIFO) Then Begin
  P:=VNodes[V].Minor;
  If Files[F].Flags And O_ACCMODE=O_RDONLY Then Begin
   If PipeReaders[P]>0 Then Dec(PipeReaders[P]);
  End Else If PipeWriters[P]>0 Then Dec(PipeWriters[P]);
  Wakeup(CHPIPE+P);
  If (PipeReaders[P]=0) And (PipeWriters[P]=0) Then PipeUsed[P]:=False;
 End;
 VPut(V);
End;

{ --- montages --------------------------------------------------------- }

Function IsMountDir(P: TPath): Boolean;
Var M: Integer;
Begin
 IsMountDir:=False;
 For M:=1 To NMOUNT Do If Mounts[M].Used And (Mounts[M].Dir=P) Then
   IsMountDir:=True;
End;

Function MountOf(P: TPath; Var Rest: TPath): Integer;
{ montage dont le repertoire est le plus long prefixe de P }
Var M,Best,L: Integer;
Begin
 Best:=0; L:=-1;
 For M:=1 To NMOUNT Do With Mounts[M] Do
  If Used Then
   If (Dir='/') Or (P=Dir) Or (Copy(P,1,Length(Dir)+1)=Dir+'/') Then
    If Length(Dir)>L Then Begin Best:=M; L:=Length(Dir) End;
 MountOf:=Best;
 If Best=0 Then Begin Rest:=''; Exit End;
 If Mounts[Best].Dir='/' Then Rest:=Copy(P,2,255)
 Else Rest:=Copy(P,Length(Mounts[Best].Dir)+2,255);
End;

Function VLookup(D: Integer; Name: TName; Var T: TVNode): Integer;
Var M: Integer;
Begin
 M:=VNodes[D].Mnt;
 Case Mounts[M].Typ Of
  FSFAT12,FSFAT16: VLookup:=FatLookup(VNodes[D],Name,T);
  FSUFS: VLookup:=UfsLookup(VNodes[D],Name,T);
  FSDEV: VLookup:=DevLookup(M,Name,T);
  Else VLookup:=ENOENT;
 End;
End;

Function Namei(Path: TPath; Var Vn: Integer): Integer;
Var P,Rest: TPath; M,V,I,E: Integer; C: TName; T: TVNode;
Begin
 Vn:=0;
 If Path='' Then Begin Namei:=ENOENT; Exit End;
 P:=NormPath(Procs[Cur].Cwd,Path);
 M:=MountOf(P,Rest);
 If M=0 Then Begin Namei:=ENOENT; Exit End;
 V:=Mounts[M].RootVn; VRef(V);
 I:=1;
 While I<=Length(Rest) Do Begin
  C:='';
  While (I<=Length(Rest)) And (Rest[I]<>'/') Do Begin
   If Length(C)<63 Then C:=C+Rest[I]; Inc(I);
  End;
  Inc(I);
  If VNodes[V].Typ<>VDIR Then Begin VPut(V); Namei:=ENOTDIR; Exit End;
  E:=VAccess(V,1);
  If E=0 Then E:=VLookup(V,C,T);
  VPut(V);
  If E<>0 Then Begin Namei:=E; Exit End;
  V:=VGet(T);
  If V=0 Then Begin Namei:=ENFILE; Exit End;
 End;
 Vn:=V; Namei:=0;
End;

Function NameiParent(Path: TPath; Var Dir: Integer; Var Last: TName): Integer;
Var P: TPath; I,E: Integer;
Begin
 Dir:=0;
 P:=NormPath(Procs[Cur].Cwd,Path);
 If (P='/') Or IsMountDir(P) Then Begin NameiParent:=EBUSY; Exit End;
 I:=Length(P);
 While (I>0) And (P[I]<>'/') Do Dec(I);
 Last:=Copy(P,I+1,63);
 If I<=1 Then E:=Namei('/',Dir) Else E:=Namei(Copy(P,1,I-1),Dir);
 If (E=0) And (VNodes[Dir].Typ<>VDIR) Then Begin
  VPut(Dir); Dir:=0; E:=ENOTDIR;
 End;
 NameiParent:=E;
End;

Function FsType(Vn: Integer): Byte;
Begin
 If VNodes[Vn].Mnt=0 Then FsType:=FSNONE
 Else FsType:=Mounts[VNodes[Vn].Mnt].Typ;
End;

Function VRead(Vn: Integer; Off: Longint; Sg, Os, N: Word): Integer;
Begin
 Case VNodes[Vn].Typ Of
  VFIFO: VRead:=PipeRead(VNodes[Vn].Minor,Sg,Os,N);
  VCHR: VRead:=DevRW(VNodes[Vn].Minor,Off,Sg,Os,N,False);
  VDIR: VRead:=-EISDIR;
  Else Case FsType(Vn) Of
   FSFAT12,FSFAT16: VRead:=FatRead(VNodes[Vn],Off,Sg,Os,N);
   FSUFS: VRead:=UfsRead(VNodes[Vn],Off,Sg,Os,N);
   Else VRead:=-EIO;
  End;
 End;
End;

Function VWrite(Vn: Integer; Off: Longint; Sg, Os, N: Word): Integer;
Begin
 Case VNodes[Vn].Typ Of
  VFIFO: VWrite:=PipeWrite(VNodes[Vn].Minor,Sg,Os,N);
  VCHR: VWrite:=DevRW(VNodes[Vn].Minor,Off,Sg,Os,N,True);
  VDIR: VWrite:=-EISDIR;
  Else Case FsType(Vn) Of
   FSFAT12,FSFAT16: VWrite:=FatWrite(VNodes[Vn],Off,Sg,Os,N);
   FSUFS: VWrite:=UfsWrite(VNodes[Vn],Off,Sg,Os,N);
   Else VWrite:=-EIO;
  End;
 End;
End;

Function VTrunc(Vn: Integer): Integer;
Begin
 VTrunc:=0;
 If VNodes[Vn].Typ<>VREG Then Exit;
 Case FsType(Vn) Of
  FSFAT12,FSFAT16: VTrunc:=FatTrunc(VNodes[Vn]);
  FSUFS: VTrunc:=UfsTrunc(VNodes[Vn]);
 End;
End;

Function VReadDir(Vn: Integer; Var Pos: Longint; Var Name: TName;
  Var Ino: Longint; Var Typ: Byte): Boolean;
Begin
 Case FsType(Vn) Of
  FSFAT12,FSFAT16: VReadDir:=FatReadDir(VNodes[Vn],Pos,Name,Ino,Typ);
  FSUFS: VReadDir:=UfsReadDir(VNodes[Vn],Pos,Name,Ino,Typ);
  FSDEV: VReadDir:=DevReadDir(Pos,Name,Ino,Typ);
  Else VReadDir:=False;
 End;
End;

Function VCreate(Dir: Integer; Name: TName; IsDir: Boolean; Mode: Word;
  Var Vn: Integer): Integer;
Var T: TVNode; E: Integer;
Begin
 Vn:=0;
 Case FsType(Dir) Of
  FSFAT12,FSFAT16: E:=FatCreate(VNodes[Dir],Name,IsDir,T);
  FSUFS: E:=UfsCreate(VNodes[Dir],Name,IsDir,Mode And Not Procs[Cur].Umask,T);
  Else E:=EROFS;
 End;
 If E=0 Then Begin
  Vn:=VGet(T);
  If Vn=0 Then E:=ENFILE;
 End;
 VCreate:=E;
End;

Function VRemove(Dir: Integer; Name: TName; IsDir: Boolean): Integer;
Begin
 Case FsType(Dir) Of
  FSFAT12,FSFAT16: VRemove:=FatRemove(VNodes[Dir],Name,IsDir);
  FSUFS: VRemove:=UfsRemove(VNodes[Dir],Name,IsDir);
  Else VRemove:=EROFS;
 End;
End;

Function VRename(D1: Integer; N1: TName; D2: Integer; N2: TName): Integer;
Begin
 If VNodes[D1].Mnt<>VNodes[D2].Mnt Then Begin VRename:=EXDEV; Exit End;
 Case FsType(D1) Of
  FSFAT12,FSFAT16: VRename:=FatRename(VNodes[D1],N1,VNodes[D2],N2);
  FSUFS: VRename:=UfsRename(VNodes[D1],N1,VNodes[D2],N2);
  Else VRename:=EROFS;
 End;
End;

Function VLink(Dir: Integer; Name: TName; Vn: Integer): Integer;
Begin
 If VNodes[Dir].Mnt<>VNodes[Vn].Mnt Then Begin VLink:=EXDEV; Exit End;
 If FsType(Dir)=FSUFS Then VLink:=UfsLink(VNodes[Dir],Name,VNodes[Vn])
 Else VLink:=EPERM;
End;

Function VChmod(Vn: Integer; Mode: Word): Integer;
Begin
 Case FsType(Vn) Of
  FSUFS: VChmod:=UfsChmod(VNodes[Vn],Mode);
  Else VChmod:=0;   { FAT, /dev : pas de permissions enregistrees }
 End;
End;

Function VChown(Vn: Integer; U, G: Word): Integer;
Begin
 VChown:=0;
 If FsType(Vn)<>FSUFS Then Exit;   { FAT, /dev : proprietaire root }
 VNodes[Vn].Uid:=U; VNodes[Vn].Gid:=G;
 VChown:=UfsSetAttr(VNodes[Vn]);
End;

Function VUtime(Vn: Integer; T: Longint): Integer;
Begin
 VUtime:=0;
 Case FsType(Vn) Of
  FSUFS: Begin VNodes[Vn].MTime:=T; VUtime:=UfsSetAttr(VNodes[Vn]) End;
  FSFAT12,FSFAT16: If VNodes[Vn].Typ=VREG Then Begin
   If Mounts[VNodes[Vn].Mnt].RO Then Begin VUtime:=EROFS; Exit End;
   VNodes[Vn].MTime:=T; FatUpdate(VNodes[Vn]);
  End;
 End;
End;

Function VAccess(Vn: Integer; Want: Word): Integer;
{ permission Want (4 lecture, 2 ecriture, 1 execution ou recherche) pour
  l'utilisateur du processus courant : bits du proprietaire, du groupe ou
  des autres; le super-utilisateur (uid 0) a tous les droits, sauf
  l'execution d'un fichier sans aucun bit x }
Var M: Word;
Begin
 VAccess:=0;
 With VNodes[Vn] Do Begin
  If Procs[Cur].Uid=0 Then Begin
   If (Want And 1<>0) And (Typ<>VDIR) And (Mode And $49=0) Then
     VAccess:=EACCES;
   Exit;
  End;
  M:=Mode;
  If Uid=Procs[Cur].Uid Then M:=M Shr 6
  Else If Gid=Procs[Cur].Gid Then M:=M Shr 3;
  If M And Want And 7<>Want And 7 Then VAccess:=EACCES;
 End;
End;

Function MountFree(M: Integer): Longint;
Begin
 Case Mounts[M].Typ Of
  FSFAT12,FSFAT16: MountFree:=FatFreeKB(M);
  FSUFS: MountFree:=UfsFreeKB(M);
  Else MountFree:=0;
 End;
End;

Function DoMount(Special, Dir: TPath; FsType: Word): Integer;
Var M,D,V,E,I: Integer; P: TPath; T: TVNode; S: TName;
Begin
 P:=NormPath('/',Dir);
 For M:=1 To NMOUNT Do If Mounts[M].Used And (Mounts[M].Dir=P) Then Begin
  DoMount:=EBUSY; Exit;
 End;
 M:=0;
 For I:=1 To NMOUNT Do If (M=0) And Not Mounts[I].Used Then M:=I;
 If M=0 Then Begin DoMount:=ENFILE; Exit End;
 FillChar(Mounts[M],SizeOf(TMount),0);
 Mounts[M].Dir:=P;
 S:=Special;
 If Copy(S,1,5)='/dev/' Then Delete(S,1,5);
 Mounts[M].Special:=S;
 If S='devfs' Then Begin
  Mounts[M].Typ:=FSDEV;
  FillChar(T,SizeOf(T),0);
  T.Typ:=VDIR; T.Mnt:=M; T.Mode:=S_IFDIR Or $1ED; T.NLink:=2;
  T.MTime:=BootTime; T.Ino:=0;
 End Else Begin
  D:=DevMinor(S)-DEVDISK;
  If (D<0) Or (D>=DiskCount) Then Begin DoMount:=ENODEV; Exit End;
  For I:=1 To NMOUNT Do
   If Mounts[I].Used And (Mounts[I].Typ<>FSDEV) And (Mounts[I].Drive=D) Then
   Begin DoMount:=EBUSY; Exit End;
  Mounts[M].Drive:=D; Mounts[M].Start:=Disks[D].Start;
  BInval(D);
  E:=EINVAL;
  If FsType<>1 Then E:=UfsMount(M);
  If (E<>0) And (FsType<>2) Then E:=FatMount(M);
  If E<>0 Then Begin DoMount:=E; Exit End;
  If Mounts[M].Typ=FSUFS Then Begin
   E:=UfsIGet(M,ROOTINO,T);
   If E<>0 Then Begin DoMount:=E; Exit End;
  End Else FatRoot(M,T);
 End;
 Mounts[M].Used:=True;
 V:=VGet(T);
 If V=0 Then Begin Mounts[M].Used:=False; DoMount:=ENFILE; Exit End;
 Mounts[M].RootVn:=V;
 DoMount:=0;
End;

Function DoUmount(Dir: TPath): Integer;
Var M,I: Integer; P: TPath;
Begin
 P:=NormPath('/',Dir);
 For M:=1 To NMOUNT Do If Mounts[M].Used And (Mounts[M].Dir=P) Then Begin
  If P='/' Then Begin DoUmount:=EBUSY; Exit End;
  For I:=1 To NVNODE Do
   If (VNodes[I].Ref>0) And (VNodes[I].Mnt=M) And (I<>Mounts[M].RootVn) Then
   Begin DoUmount:=EBUSY; Exit End;
  If VNodes[Mounts[M].RootVn].Ref>1 Then Begin DoUmount:=EBUSY; Exit End;
  VPut(Mounts[M].RootVn);
  Mounts[M].Used:=False;
  If Mounts[M].Typ<>FSDEV Then BInval(Mounts[M].Drive);
  DoUmount:=0; Exit;
 End;
 DoUmount:=EINVAL;
End;

SegmentEnd;

{ ====================================================================== }
SegmentUnit KProc;
{ Processus : chargement des executables MZ (exec), fork, exit, wait,
  signaux, liberation de la memoire. }
Uses KTypes,KLib,KMem,KSched,KVfs,KSwap;
SegmentInterface

Var
 { arguments et environnement d'exec : KArgc chaines de argv puis KEnvc
   chaines de l'environnement, chacune terminee par un octet nul }
 KArgs: Array[0..2047] Of Char;
 KArgLen: Word;
 KArgc, KEnvc: Integer;

Function NewProc: Integer;
Procedure ReleaseMemory(P: Integer);
Function DoFork: Integer;
Function DoVFork: Integer;
Function DoExec(Path: TPath): Integer;
Function GatherArgs(ASeg, AOfs, ESeg, EOfs: Word): Integer;
Procedure DoExit(Status: Word);
Function DoWait(Pid: Integer; Options: Word; Var Status: Word): Integer;
Procedure CheckSignals;
Procedure CloseAll(P: Integer);
Procedure SetupKStack(P: Integer);
Function GetKStack(P: Integer): Boolean;

SegmentImplementation

Function NewProc: Integer;
Var I: Integer;
Begin
 NewProc:=-1;
 For I:=1 To NPROC-1 Do If Procs[I].Stat=PFREE Then Begin
  NewProc:=I; Exit;
 End;
End;

Function GetKStack(P: Integer): Boolean;
{ pile noyau de 4 Ko du processus P, allouee a sa creation (en haut de la
  memoire) et rendue quand son pere recupere son etat (wait) }
Var K: Word;
Begin
 GetKStack:=True;
 If Procs[P].KStack<>0 Then Exit;
 K:=CoreAllocHigh(KSTKPARAS);
 If K=0 Then Begin GetKStack:=False; Exit End;
 FarFill(K,0,KSTKTOP,$CC);   { motif de detection du debordement }
 Procs[P].KStack:=K;
End;

Procedure SetupKStack(P: Integer);
{ pile noyau d'un nouveau processus : KSwitch y retrouvera DI, SI, BP et
  l'adresse de retour FAR de ForkRet }
Var K: Word;
Begin
 K:=Procs[P].KStack;
 MemW[K:KSTKTOP-10]:=0;            { DI }
 MemW[K:KSTKTOP-8]:=0;             { SI }
 MemW[K:KSTKTOP-6]:=0;             { BP }
 MemW[K:KSTKTOP-4]:=Ofs(ForkRet);
 MemW[K:KSTKTOP-2]:=Seg(ForkRet);
 Procs[P].KSP:=KSTKTOP-10; Procs[P].KSS:=K;
End;

Procedure ReleaseMemory(P: Integer);
{ libere l'image de P; si un autre processus partage la meme adresse
  d'execution (fork), il y est ramene. Un fils de vfork rend la memoire
  empruntee a son pere et le reveille. }
Var O: Integer;
Begin
 With Procs[P] Do Begin
  If Borrowed Then Begin
   Borrowed:=False; Home:=0; Where:=0; Size:=0;
   Wakeup(CHVFORK+P);
   Exit;
  End;
  If Size=0 Then Exit;
  If Swapped Then SwapRelease(P)
  Else If Where<>Home Then CoreFree(Where,Size)
  Else Begin
   { une image soeur (fork) reprend l'adresse depuis sa copie en memoire;
     si elle est dans la zone de va-et-vient, elle y reviendra a sa
     prochaine execution }
   For O:=1 To NPROC-1 Do
    If (O<>P) And (Procs[O].Stat<>PFREE) And (Procs[O].Size<>0) And
      Not Procs[O].Borrowed And Not Procs[O].Swapped And
      (Procs[O].Home=Home) Then Begin
     ParaCopy(Procs[O].Where,Home,Size);
     CoreFree(Procs[O].Where,Size);
     Procs[O].Where:=Home;
     Home:=0; Where:=0; Size:=0;
     Exit;
    End;
   CoreFree(Home,Size);
  End;
  Home:=0; Where:=0; Size:=0;
 End;
End;

Procedure CloseAll(P: Integer);
Var I: Integer;
Begin
 For I:=0 To NOFILE-1 Do If Procs[P].Fd[I]<>0 Then Begin
  FClose(Procs[P].Fd[I]); Procs[P].Fd[I]:=0;
 End;
End;

Function DoFork: Integer;
Var C,I: Integer; A,FS: Word; K: Word; SAX,SFL: Word; Ok: Boolean;
Begin
 C:=NewProc;
 If C<0 Then Begin DoFork:=-EAGAIN; Exit End;
 If Procs[Cur].Size=0 Then Begin DoFork:=-EINVAL; Exit End;
 If Not GetKStack(C) Then Begin DoFork:=-EAGAIN; Exit End;
 A:=CoreAlloc(Procs[Cur].Size);
 If (A=0) And (SwapDisk<0) Then Begin DoFork:=-ENOMEM; Exit End;
 { sans memoire libre, la copie du fils va directement dans la zone de
   va-et-vient (comme UNIX V7) }
 If A<>0 Then ParaCopy(Procs[Cur].Home,A,Procs[Cur].Size);
 K:=Procs[C].KStack;
 Procs[C]:=Procs[Cur];
 With Procs[C] Do Begin
  KStack:=K;
  Inc(NextPid); If NextPid>30000 Then NextPid:=2;
  While FindPid(NextPid)>=0 Do Inc(NextPid);
  Pid:=NextPid; PPid:=Procs[Cur].Pid;
  Where:=A; CpuTicks:=0; ChildTicks:=0; CpuRecent:=0; SigPend:=0; Chan:=0; Wake:=0;
  Intr:=False; Alarm:=0;
  USS:=CurUSS; USP:=CurUSP;
  For I:=0 To NOFILE-1 Do If Fd[I]<>0 Then FRef(Fd[I]);
  If A<>0 Then Begin
   { trame du fils (dans sa copie) : AX = 0, CF = 0 }
   FS:=A+(CurUSS-Procs[Cur].Home);
   MemW[FS:CurUSP]:=0;
   MemW[FS:CurUSP+22]:=MemW[FS:CurUSP+22] And $FFFE;
  End;
 End;
 If A=0 Then Begin
  { trame du fils modifiee le temps d'ecrire l'image dans la zone }
  SAX:=MemW[CurUSS:CurUSP]; SFL:=MemW[CurUSS:CurUSP+22];
  MemW[CurUSS:CurUSP]:=0; MemW[CurUSS:CurUSP+22]:=SFL And $FFFE;
  Ok:=SwapImage(C,Procs[Cur].Home);
  MemW[CurUSS:CurUSP]:=SAX; MemW[CurUSS:CurUSP+22]:=SFL;
  If Not Ok Then Begin
   For I:=0 To NOFILE-1 Do If Procs[C].Fd[I]<>0 Then FClose(Procs[C].Fd[I]);
   Procs[C].Stat:=PFREE; Procs[C].Size:=0; Procs[C].Pid:=0;
   DoFork:=-ENOMEM; Exit;
  End;
 End;
 SetupKStack(C);
 Procs[C].Stat:=PRUN;
 DoFork:=Procs[C].Pid;
End;

Var
 VSave: Array[0..NPROC-1,0..255] Of Byte;   { pile du pere pendant vfork }

Function DoVFork: Integer;
{ vfork : le fils s'execute dans la memoire du pere, suspendu jusqu'a ce
  que le fils appelle exec ou exit. Les 256 octets de pile utilisateur du
  pere (trame de l'appel systeme comprise) sont sauvegardes et restaures. }
Var C,I,O: Integer; K: Word;
Begin
 For O:=1 To NPROC-1 Do
  If (O<>Cur) And (Procs[O].Stat<>PFREE) And (Procs[O].Size<>0) And
    (Procs[O].Home=Procs[Cur].Home) Then Begin
   DoVFork:=DoFork; Exit;  { memoire deja partagee : fork ordinaire }
  End;
 C:=NewProc;
 If C<0 Then Begin DoVFork:=-EAGAIN; Exit End;
 If Procs[Cur].Size=0 Then Begin DoVFork:=-EINVAL; Exit End;
 If Not GetKStack(C) Then Begin DoVFork:=-EAGAIN; Exit End;
 K:=Procs[C].KStack;
 Procs[C]:=Procs[Cur];
 With Procs[C] Do Begin
  KStack:=K; Borrowed:=True;
  Inc(NextPid); If NextPid>30000 Then NextPid:=2;
  While FindPid(NextPid)>=0 Do Inc(NextPid);
  Pid:=NextPid; PPid:=Procs[Cur].Pid;
  CpuTicks:=0; ChildTicks:=0; SigPend:=0; Chan:=0; Wake:=0; Intr:=False;
  Alarm:=0;
  USS:=CurUSS; USP:=CurUSP;
  For I:=0 To NOFILE-1 Do If Fd[I]<>0 Then FRef(Fd[I]);
 End;
 FarMove(CurUSS,CurUSP,Seg(VSave),Ofs(VSave[Cur]),256);
 { trame du fils : AX = 0 }
 MemW[CurUSS:CurUSP]:=0;
 MemW[CurUSS:CurUSP+22]:=MemW[CurUSS:CurUSP+22] And $FFFE;
 SetupKStack(C);
 Procs[C].Stat:=PRUN;
 { le pere attend la fin de l'emprunt }
 While Procs[C].Borrowed And (Procs[C].Stat<>PFREE) Do Sleep(CHVFORK+C);
 FarMove(Seg(VSave),Ofs(VSave[Cur]),CurUSS,CurUSP,256);
 DoVFork:=Procs[C].Pid;
End;

Const
 { COFF (System V) : en-tete de fichier, en-tete a.out facultatif, sections }
 COFFMAGIC=$0153;     { I286LMAGIC : Intel 286/8086, modele large (segments) }
 COFF_F_EXEC=$0002;
 STYP_TEXT=$20; STYP_DATA=$40; STYP_BSS=$80;
 R_SEG12=9;           { relocalisation de segment 8086 (r_type 011) }
 MAXCOFFSEC=40;

Var
 CoffSh: Array[0..MAXCOFFSEC*40-1] Of Byte;   { en-tetes de sections }

Function CoffL(O: Word): Longint;
Begin
 CoffL:=MemL[Seg(CoffSh):Ofs(CoffSh)+O];
End;

Function GatherArgs(ASeg, AOfs, ESeg, EOfs: Word): Integer;
{ recopie dans KArgs les chaines des tableaux argv (ASeg:AOfs) et envp
  (ESeg:EOfs) de l'appelant : pointeurs FAR termines par un pointeur nul
  (un tableau a l'adresse 0:0 est vide) }
Var Sg,Os,O: Word; Pass: Integer; N: Integer;
Begin
 GatherArgs:=0; KArgLen:=0; KArgc:=0; KEnvc:=0;
 For Pass:=0 To 1 Do Begin
  If Pass=0 Then Begin Sg:=ASeg; O:=AOfs End Else Begin Sg:=ESeg; O:=EOfs End;
  If (Sg<>0) Or (O<>0) Then
   While (MemW[Sg:O]<>0) Or (MemW[Sg:O+2]<>0) Do Begin
    Os:=MemW[Sg:O];
    N:=0;
    Repeat
     If KArgLen>=SizeOf(KArgs)-1 Then Begin GatherArgs:=E2BIG; Exit End;
     KArgs[KArgLen]:=Chr(Mem[MemW[Sg:O+2]:Os+N]); Inc(KArgLen); Inc(N);
    Until KArgs[KArgLen-1]=#0;
    If Pass=0 Then Inc(KArgc) Else Inc(KEnvc);
    Inc(O,4);
    If (Pass=0) And (KArgc>255) Or (KEnvc>255) Then Begin
     GatherArgs:=E2BIG; Exit;
    End;
   End;
 End;
End;

Function DoExec(Path: TPath): Integer;
{ Charge un executable COFF (format natif de LINUX-0, produit par LPC /X) ou
  MZ (programmes DOS), puis prepare la pile (argc, argv, envp comme UNIX),
  le prefixe compatible DOS, l'environnement et la trame initiale du
  processus courant. Les arguments sont dans KArgs (KArgc, KEnvc). }
Var
 Vn,I,N: Integer;
 H: Array[0..15] Of Word;
 Coff: Boolean;
 NSec,Ext: Longint;
 CsRel,IpV,SsRel,SpV: Word;
 HeapMin: Longint;
 RE: Array[0..4] Of Word;
 J: Longint;
 ImgBytes,Off,Rem: Longint;
 HdrParas,LoadParas,EnvParas,Total,Extra,MinA,MaxA: Longint;
 Mem_,Load,PSP_,EnvS,SS_,SP_: Word;
 R: Array[0..1] Of Word;
 Chunk,Sg,O,K,EnvStart,TailLen,StrPos,PtrPos,ArgcPos: Word;
 Top,UArea: Longint;
 Name: TPath;
 E: Integer;
 Lost: Boolean;
 FMode,FUid,FGid: Word;
Begin
 { debut de l'environnement dans KArgs }
 I:=0;
 For N:=1 To KArgc Do Begin
  While KArgs[I]<>#0 Do Inc(I);
  Inc(I);
 End;
 EnvStart:=I;
 E:=Namei(Path,Vn);
 If E<>0 Then Begin DoExec:=E; Exit End;
 If VNodes[Vn].Typ<>VREG Then Begin VPut(Vn); DoExec:=EACCES; Exit End;
 E:=VAccess(Vn,1);
 If E<>0 Then Begin VPut(Vn); DoExec:=E; Exit End;
 FMode:=VNodes[Vn].Mode; FUid:=VNodes[Vn].Uid; FGid:=VNodes[Vn].Gid;
 FillChar(H,SizeOf(H),0);
 If VRead(Vn,0,Seg(H),Ofs(H),32)<20 Then Begin
  VPut(Vn); DoExec:=ENOEXEC; Exit;
 End;
 Coff:=H[0]=COFFMAGIC;
 HeapMin:=DEFHEAP;
 If Coff Then Begin
  { en-tete COFF : f_nscns (H[1]), f_opthdr (H[8]), f_flags (H[9]) ;
    a.out : entry a l'octet 20+16 }
  NSec:=H[1];
  If (H[9] And COFF_F_EXEC=0) Or (NSec<1) Or (NSec>MAXCOFFSEC) Or (H[8]<28) Then
  Begin VPut(Vn); DoExec:=ENOEXEC; Exit End;
  If VRead(Vn,20+H[8],Seg(CoffSh),Ofs(CoffSh),NSec*40)<>NSec*40 Then Begin
   VPut(Vn); DoExec:=ENOEXEC; Exit;
  End;
  If VRead(Vn,20+16,Seg(J),Ofs(J),4)<>4 Then Begin
   VPut(Vn); DoExec:=ENOEXEC; Exit;
  End;
  CsRel:=Word(J Shr 4); IpV:=Word(J And 15);
  Ext:=0; SsRel:=$FFFF; SpV:=0; HeapMin:=-1;
  For I:=0 To NSec-1 Do Begin
   If CoffL(I*40+12)+CoffL(I*40+16)>Ext Then Ext:=CoffL(I*40+12)+CoffL(I*40+16);
   If (CoffSh[I*40]=Ord('.')) And (CoffSh[I*40+1]=Ord('s')) And
     (CoffSh[I*40+2]=Ord('t')) And (CoffSh[I*40+3]=Ord('a')) Then Begin
    SsRel:=CoffL(I*40+12) Shr 4; SpV:=Word(CoffL(I*40+16));
   End;
   If (CoffSh[I*40]=Ord('.')) And (CoffSh[I*40+1]=Ord('h')) And
     (CoffSh[I*40+2]=Ord('e')) Then HeapMin:=(CoffL(I*40+16)+15) Div 16;
   { .heap de taille nulle : programme sans tas }
  End;
  If (SsRel=$FFFF) Or (Ext>$9FFF0) Then Begin VPut(Vn); DoExec:=ENOEXEC; Exit End;
  If HeapMin=-1 Then HeapMin:=DEFHEAP;
  LoadParas:=(Ext+15) Div 16; MinA:=0; HdrParas:=0; ImgBytes:=0;
 End Else Begin
  If H[0]<>$5A4D Then Begin VPut(Vn); DoExec:=ENOEXEC; Exit End;
  If H[1]=0 Then ImgBytes:=Longint(H[2])*512 Else ImgBytes:=Longint(H[2]-1)*512+H[1];
  HdrParas:=H[4];
  ImgBytes:=ImgBytes-HdrParas*16;
  If ImgBytes<=0 Then Begin VPut(Vn); DoExec:=ENOEXEC; Exit End;
  LoadParas:=(ImgBytes+15) Div 16;
  MinA:=H[5]; MaxA:=H[6];
  CsRel:=H[11]; IpV:=H[10]; SsRel:=H[7]; SpV:=H[8];
 End;
 { pile : chaines, envp[], argv[] et argc au sommet de la pile; il faut
   qu'il reste au moins la moitie de la pile au programme }
 Top:=SpV; If Top=0 Then Top:=$10000;
 UArea:=((KArgLen+1) And $FFFE)+Longint(KArgc+KEnvc+2)*4+2;
 If UArea+24>Top Div 2 Then Begin VPut(Vn); DoExec:=E2BIG; Exit End;
 { environnement (programmes DOS) : env, nom du programme, argc et argv }
 EnvParas:=(Longint(KArgLen)+Length(Path)+64) Div 16+1;
 { tas : le runtime de Linux Pascal reserve ses blocs par la libc (service
   48h), dans la zone qui suit l'image et sa pile (maxalloc = minalloc) }
 Extra:=HeapMin;   { .heap du COFF, sinon DEFHEAP }
 Total:=EnvParas+16+LoadParas+MinA+Extra;
 If Total>$A000 Then Begin VPut(Vn); DoExec:=ENOMEM; Exit End;
 { comme UNIX V7, l'ancienne image est liberee avant le chargement de la
   nouvelle (les arguments sont deja dans KArgs, les en-tetes verifies) :
   la nouvelle image prend la place la plus basse possible, ce qui limite
   la fragmentation (les images 8086 ne sont pas deplacables). Une erreur
   d'entree/sortie pendant le chargement termine alors le processus
   (SIGKILL). L'image d'un fils de vfork appartient a son pere. }
 Lost:=False;
 If Not Procs[Cur].Borrowed And (Procs[Cur].Size<>0) Then Begin
  ReleaseMemory(Cur); Lost:=True;
 End;
 Mem_:=CoreAlloc(Total);
 { memoire insuffisante : d'autres processus vont dans la zone de
   va-et-vient }
 If (Mem_=0) And Reclaim(Total,-1) Then Mem_:=CoreAlloc(Total);
 If Mem_=0 Then Begin VPut(Vn); If Lost Then DoExit(SIGKILL); DoExec:=ENOMEM; Exit End;
 ParaZero(Mem_,EnvParas+16);
 EnvS:=Mem_; PSP_:=Mem_+EnvParas; Load:=PSP_+16;
 If Coff Then Begin
  { COFF : image (bss et pile compris) mise a zero, sections .text et .data
    lues a load + s_vaddr, puis relocalisations R_SEG12 de chaque section }
  ParaZero(Load,LoadParas);
  For I:=0 To NSec-1 Do
   If (CoffL(I*40+36) And STYP_BSS=0) And (CoffL(I*40+20)<>0) Then Begin
    Off:=CoffL(I*40+20); Rem:=CoffL(I*40+16);
    Sg:=Load+Word(CoffL(I*40+12) Shr 4); O:=Word(CoffL(I*40+12) And 15);
    While Rem>0 Do Begin
     If Rem>$4000 Then Chunk:=$4000 Else Chunk:=Rem;
     If VRead(Vn,Off,Sg,O,Chunk)<>Chunk Then Begin
      VPut(Vn); CoreFree(Mem_,Total); If Lost Then DoExit(SIGKILL); DoExec:=EIO; Exit;
     End;
     Inc(Off,Chunk); Dec(Rem,Chunk); Inc(Sg,Chunk Div 16);
    End;
   End;
  For I:=0 To NSec-1 Do
   For J:=0 To Longint(MemW[Seg(CoffSh):Ofs(CoffSh)+I*40+32])-1 Do Begin
    If VRead(Vn,CoffL(I*40+24)+J*10,Seg(RE),Ofs(RE),10)<>10 Then Begin
     VPut(Vn); CoreFree(Mem_,Total); If Lost Then DoExit(SIGKILL); DoExec:=ENOEXEC; Exit;
    End;
    Off:=Longint(RE[1]) Shl 16+RE[0];
    If (RE[4]<>R_SEG12) Or (Off+2>Longint(LoadParas)*16) Then Begin
     VPut(Vn); CoreFree(Mem_,Total); If Lost Then DoExit(SIGKILL); DoExec:=ENOEXEC; Exit;
    End;
    Sg:=Load+Word(Off Shr 4); O:=Word(Off And 15);
    MemW[Sg:O]:=MemW[Sg:O]+Load;
   End;
 End Else Begin
  { MZ : image apres l'en-tete, table des relocalisations }
  Off:=HdrParas*16; Rem:=ImgBytes; Sg:=Load;
  While Rem>0 Do Begin
   If Rem>$4000 Then Chunk:=$4000 Else Chunk:=Rem;
   If VRead(Vn,Off,Sg,0,Chunk)<>Chunk Then Begin
    VPut(Vn); CoreFree(Mem_,Total); If Lost Then DoExit(SIGKILL); DoExec:=EIO; Exit;
   End;
   Inc(Off,Chunk); Dec(Rem,Chunk); Inc(Sg,Chunk Div 16);
  End;
  For I:=0 To H[3]-1 Do Begin
   If VRead(Vn,H[12]+Longint(I)*4,Seg(R),Ofs(R),4)<>4 Then Begin
    VPut(Vn); CoreFree(Mem_,Total); If Lost Then DoExit(SIGKILL); DoExec:=ENOEXEC; Exit;
   End;
   MemW[Load+R[1]:R[0]]:=MemW[Load+R[1]:R[0]]+Load;
  End;
 End;
 VPut(Vn);
 ParaZero(Load+LoadParas,MinA);
 { environnement : VAR=VAL..., 0, mot 1, chemin, puis argc et argv }
 O:=0;
 For I:=EnvStart To KArgLen-1 Do Begin Mem[EnvS:O]:=Ord(KArgs[I]); Inc(O) End;
 Mem[EnvS:O]:=0; Inc(O);
 MemW[EnvS:O]:=1; Inc(O,2);
 Name:=NormPath(Procs[Cur].Cwd,Path);
 PutFarStr(EnvS,O,Name); Inc(O,Length(Name)+1);
 MemW[EnvS:O]:=KArgc; Inc(O,2);
 For I:=0 To EnvStart-1 Do Begin Mem[EnvS:O]:=Ord(KArgs[I]); Inc(O) End;
 Mem[EnvS:O]:=0;
 { prefixe du programme (disposition du PSP) }
 Mem[PSP_:0]:=$CD; Mem[PSP_:1]:=$20;
 MemW[PSP_:2]:=Mem_+Total;
 MemW[PSP_:$2C]:=EnvS;
 MemW[PSP_:$48]:=Load+LoadParas+MinA;   { debut du tas (libc) }
 { ligne de commande : argv[1..] separes par des espaces }
 TailLen:=0; I:=0;
 If KArgc>0 Then Begin
  While KArgs[I]<>#0 Do Inc(I);
  Inc(I);
 End;
 While (I<EnvStart) And (TailLen<126) Do Begin
  If KArgs[I]=#0 Then Begin
   If I<EnvStart-1 Then Begin Mem[PSP_:$81+TailLen]:=32; Inc(TailLen) End;
  End Else Begin Mem[PSP_:$81+TailLen]:=Ord(KArgs[I]); Inc(TailLen) End;
  Inc(I);
 End;
 If TailLen>0 Then Begin
  { la ligne de commande DOS commence par un espace }
  For K:=TailLen DownTo 1 Do Mem[PSP_:$81+K]:=Mem[PSP_:$80+K];
  Mem[PSP_:$81]:=32; Inc(TailLen);
 End;
 Mem[PSP_:$80]:=TailLen; Mem[PSP_:$81+TailLen]:=13;
 { l'ancienne image est liberee, la nouvelle devient celle du processus }
 ReleaseMemory(Cur);
 With Procs[Cur] Do Begin
  Home:=Mem_; Where:=Mem_; Size:=Total; PSP:=PSP_;
  DosOfs:=0; DosSeg:=0;
  { bits set-uid et set-gid : utilisateur et groupe effectifs du
    proprietaire du fichier; programme DOS (MZ) : noms sans casse sur UFS }
  If FMode And $800<>0 Then Uid:=FUid;
  If FMode And $400<>0 Then Gid:=FGid;
  DosProg:=Not Coff;
  { signaux interceptes : remis a SIG_DFL; les signaux ignores le restent }
  For I:=1 To NSIG-1 Do If SigH[I]<>1 Then SigH[I]:=0;
  SigTramp:=0;
 End;
 { nom de la commande (ps) : dernier element du chemin }
 I:=Length(Name);
 While (I>0) And (Name[I]<>'/') Do Dec(I);
 Procs[Cur].Name:=Copy(Name,I+1,15);
 SetDosVector(Cur);
 { pile UNIX : chaines au sommet, puis envp[] et argv[] (pointeurs FAR
   termines par un pointeur nul) et argc, sur lequel pointe SP au debut du
   programme (et PSP:4Ch, pour la libc) }
 SS_:=Load+SsRel;
 StrPos:=Word(Top-((KArgLen+1) And $FFFE));
 PtrPos:=StrPos-Word(KArgc+KEnvc+2)*4;
 ArgcPos:=PtrPos-2;
 FarMove(Seg(KArgs),Ofs(KArgs),SS_,StrPos,KArgLen);
 MemW[SS_:ArgcPos]:=KArgc;
 O:=StrPos; K:=PtrPos;
 For I:=0 To KArgc+KEnvc-1 Do Begin
  If I=KArgc Then Begin MemL[SS_:K]:=0; Inc(K,4) End;
  MemW[SS_:K]:=O; MemW[SS_:K+2]:=SS_; Inc(K,4);
  While Mem[SS_:O]<>0 Do Inc(O);
  Inc(O);
 End;
 If KEnvc=0 Then Begin MemL[SS_:K]:=0; Inc(K,4) End;
 MemL[SS_:K]:=0;
 MemW[PSP_:$4C]:=ArgcPos; MemW[PSP_:$4E]:=SS_;
 Procs[Cur].ArgPtr:=Longint(SS_) Shl 16+ArgcPos;
 { trame initiale : registres, puis IP, CS, FLAGS }
 SP_:=ArgcPos-24;
 For K:=0 To 11 Do MemW[SS_:SP_+K*2]:=0;
 MemW[SS_:SP_+14]:=PSP_;          { ES }
 MemW[SS_:SP_+16]:=PSP_;          { DS }
 MemW[SS_:SP_+18]:=IpV;           { IP }
 MemW[SS_:SP_+20]:=Load+CsRel;    { CS }
 MemW[SS_:SP_+22]:=$0202;         { FLAGS (IF) }
 CurUSS:=SS_; CurUSP:=SP_;
 Procs[Cur].USS:=SS_; Procs[Cur].USP:=SP_;
 DoExec:=0;
End;

Procedure DoExit(Status: Word);
{ Status : etat rendu par wait, code de sortie * 256 (exit) ou numero du
  signal qui a termine le processus }
Var I: Integer; Parent: Integer;
Begin
 If Procs[Cur].Pid=1 Then Begin
  KPrintLn('init termine (etat '+IntStr(Status)+')');
  Panic('init est mort');
 End;
 CloseAll(Cur);
 ReleaseMemory(Cur);
 Procs[Cur].Status:=Status;
 Procs[Cur].DosSeg:=0; Procs[Cur].Alarm:=0;
 Parent:=FindPid(Procs[Cur].PPid);
 { les fils deviennent ceux d'init }
 For I:=1 To NPROC-1 Do
  If (Procs[I].Stat<>PFREE) And (Procs[I].PPid=Procs[Cur].Pid) Then Begin
   Procs[I].PPid:=1;
   If Procs[I].Stat=PZOMB Then Wakeup(CHWAIT+FindPid(1));
  End;
 Procs[Cur].Stat:=PZOMB;
 If Parent>=0 Then Wakeup(CHWAIT+Parent) Else Wakeup(CHWAIT+FindPid(1));
 Swtch;
 Panic('zombie reveille');
End;

Function DoWait(Pid: Integer; Options: Word; Var Status: Word): Integer;
Var I: Integer; Have: Boolean;
Begin
 Repeat
  Have:=False;
  For I:=1 To NPROC-1 Do
   If (Procs[I].Stat<>PFREE) And (Procs[I].PPid=Procs[Cur].Pid) And
     ((Pid=-1) Or (Pid=0) Or (Procs[I].Pid=Pid)) Then Begin
    Have:=True;
    If Procs[I].Stat=PZOMB Then Begin
     Status:=Procs[I].Status;
     DoWait:=Procs[I].Pid;
     Inc(Procs[Cur].ChildTicks,Procs[I].CpuTicks+Procs[I].ChildTicks);
     Procs[I].Stat:=PFREE; Procs[I].Pid:=0;
     If SwapDisk<0 Then Begin
      CoreFree(Procs[I].KStack,KSTKPARAS); Procs[I].KStack:=0;
     End;
     Exit;
    End;
   End;
  If Not Have Then Begin DoWait:=-ECHILD; Exit End;
  If Options And 1<>0 Then Begin DoWait:=0; Exit End;
  If Not SleepIntr(CHWAIT+Cur) Then Begin DoWait:=-EINTR; Exit End;
 Until False;
End;

Function DumpCore: Boolean;
{ image memoire du processus courant ecrite dans le fichier "core" du
  repertoire courant (comme UNIX V7), si l'utilisateur peut l'ecrire }
Var D,Vn,E: Integer; Last: TName; Off,Rem: Longint; Sg,Chunk: Word;
Begin
 DumpCore:=False;
 If (Procs[Cur].Size=0) Or Procs[Cur].Borrowed Then Exit;
 E:=Namei('core',Vn);
 If E=ENOENT Then Begin
  E:=NameiParent('core',D,Last);
  If E=0 Then Begin
   E:=VAccess(D,3);
   If E=0 Then E:=VCreate(D,Last,False,$1B6,Vn);
   VPut(D);
  End;
 End Else If E=0 Then Begin
  If (VNodes[Vn].Typ<>VREG) Or (VAccess(Vn,2)<>0) Then E:=EACCES
  Else E:=VTrunc(Vn);
  If E<>0 Then VPut(Vn);
 End;
 If E<>0 Then Exit;
 Off:=0; Sg:=Procs[Cur].Home; Rem:=Longint(Procs[Cur].Size)*16;
 While Rem>0 Do Begin
  If Rem>$4000 Then Chunk:=$4000 Else Chunk:=Rem;
  If VWrite(Vn,Off,Sg,0,Chunk)<>Chunk Then Break;
  Inc(Off,Chunk); Dec(Rem,Chunk); Inc(Sg,Chunk Div 16);
 End;
 VPut(Vn);
 DumpCore:=Rem=0;
End;

Procedure CheckSignals;
{ au retour en mode utilisateur : signal en attente -> action par defaut
  (fin du processus, etat de wait = numero du signal) ou gestionnaire de
  l'utilisateur (signal(sig, fonction)). Comme dans UNIX V7, le gestionnaire
  est remis a SIG_DFL avant d'etre appele. Une trame est preparee sur la pile
  utilisateur : la trampoline de la libc appelle fonction(sig) avec DS =
  donnees du programme, puis restaure les registres interrompus (IRET). }
Var I,K: Integer; NSP: Word; H: Longint;
Begin
 With Procs[Cur] Do Begin
  SigPend:=SigPend And Not (SigIgn And Not (1 Shl SIGKILL));
  If SigPend=0 Then Exit;
  For I:=1 To NSIG-1 Do If SigPend And (1 Shl I)<>0 Then Begin
   SigPend:=SigPend And Not (1 Shl I);
   H:=SigH[I];
   If (I=SIGKILL) Or (H=0) Or (SigTramp=0) Or (CurUSP<128) Then Begin
    SigPend:=0;
    { action par defaut : fin du processus, avec image memoire (core, bit
      80h de l'etat) pour les signaux d'erreur et SIGQUIT, comme V7 }
    If (I In [SIGQUIT,SIGILL,SIGTRAP,SIGIOT,SIGEMT,SIGFPE,SIGBUS,SIGSEGV,
      SIGSYS]) And DumpCore Then DoExit(I Or $80);
    DoExit(I);
   End;
   SigH[I]:=0;
   NSP:=CurUSP-30;
   For K:=0 To 8 Do MemW[CurUSS:NSP+K*2]:=MemW[CurUSS:CurUSP+K*2];
   MemW[CurUSS:NSP+18]:=Word(SigTramp);
   MemW[CurUSS:NSP+20]:=Word(SigTramp Shr 16);
   MemW[CurUSS:NSP+22]:=MemW[CurUSS:CurUSP+22];
   MemW[CurUSS:NSP+24]:=I;
   MemL[CurUSS:NSP+26]:=H;
   CurUSP:=NSP;
   Exit;
  End;
 End;
End;
SegmentEnd;

{ ====================================================================== }
SegmentUnit KSys;
{ Appels systeme (INT 80h) : lecture de la trame, aiguillage, retour. }
Uses KTypes,KLib,KMem,KSched,KDisk,KSwap,KTty,KVfs,KProc;
SegmentInterface

Procedure KSysInit;
Procedure SysDispatch;
Procedure PreemptEntry;
Procedure FaultEntry;

SegmentImplementation

Type
 TSysCtx=Record
  RAX,RBX,RCX,RDX,RSI,RDI,RDS,RES: Word;
  Ret,Ret2: Longint;
  SetDX, Two: Boolean;   { DX = Ret2 (Two) ou mot haut de Ret }
 End;

Const
 { ioctl (UNIX V7 et 4.2BSD, sur 16 bits) }
 TIOCHPCL=$7402; TIOCGETP=$7408; TIOCSETP=$7409; TIOCSETN=$740A;
 TIOCEXCL=$740D; TIOCNXCL=$740E; TIOCFLUSH=$7410; TIOCSETC=$7411;
 TIOCGETC=$7412; FIONREAD=$667F;
 { disques (LINUX-0, pour l'installation) }
 DIOCGINFO=$6401; DIOCRESCAN=$6402; DIOCINVAL=$6403;

Var
 { registres de l'appel en cours : sauvegardes avec le processus par Swtch
   (un appel systeme peut s'endormir pendant qu'un autre s'execute) }
 C: TSysCtx;

Procedure KSysInit;
Begin
 SysCtxOfs:=Ofs(C); SysCtxLen:=SizeOf(C);
End;

Function UStr(Sg, Os: Word): TPath;
Begin
 UStr:=FarStr(Sg,Os,127);
End;

Function Suser: Boolean;
Begin
 Suser:=Procs[Cur].Uid=0;
End;

Function GetFile(Fd: Word; Var F: Integer): Integer;
Begin
 GetFile:=EBADF; F:=0;
 If Fd>=NOFILE Then Exit;
 F:=Procs[Cur].Fd[Fd];
 If F=0 Then Exit;
 GetFile:=0;
End;

Function NewFd(F: Integer): Integer;
Var I: Integer;
Begin
 NewFd:=-1;
 For I:=0 To NOFILE-1 Do If Procs[Cur].Fd[I]=0 Then Begin
  Procs[Cur].Fd[I]:=F; NewFd:=I; Exit;
 End;
End;

Function ReadDirV7(F: Integer): Integer;
{ read() d'un repertoire : entrees de 16 octets de UNIX V7 (numero d'inode
  sur 16 bits, nom de 14 caracteres au plus complete par des nuls) }
Var Pos,Save,Ino: Longint; Name: TName; Typ: Byte; Done: Word; I: Integer;
Begin
 ReadDirV7:=0; Pos:=Files[F].Off; Done:=0;
 While Done+16<=C.RCX Do Begin
  Save:=Pos;
  If Not VReadDir(Files[F].Vn,Pos,Name,Ino,Typ) Then Break;
  If Word(Ino)=0 Then Ino:=1;
  MemW[C.RDS:C.RDX+Done]:=Word(Ino);
  FarFill(C.RDS,C.RDX+Done+2,14,0);
  For I:=1 To Length(Name) Do
   If I<=14 Then Mem[C.RDS:C.RDX+Done+1+I]:=Ord(Name[I]);
  Inc(Done,16);
 End;
 Files[F].Off:=Pos; C.Ret:=Done;
End;

Function SysRead: Integer;
Var F,N: Integer;
Begin
 SysRead:=GetFile(C.RBX,F);
 If F=0 Then Exit;
 If Files[F].Flags And O_ACCMODE=O_WRONLY Then Begin SysRead:=EBADF; Exit End;
 If VNodes[Files[F].Vn].Typ=VDIR Then Begin SysRead:=ReadDirV7(F); Exit End;
 N:=VRead(Files[F].Vn,Files[F].Off,C.RDS,C.RDX,C.RCX);
 If N<0 Then Begin SysRead:=-N; Exit End;
 Inc(Files[F].Off,N); C.Ret:=N; SysRead:=0;
End;

Function SysWrite: Integer;
Var F,N: Integer;
Begin
 SysWrite:=GetFile(C.RBX,F);
 If F=0 Then Exit;
 If Files[F].Flags And O_ACCMODE=O_RDONLY Then Begin SysWrite:=EBADF; Exit End;
 If Files[F].Flags And O_APPEND<>0 Then Files[F].Off:=VNodes[Files[F].Vn].Size;
 N:=VWrite(Files[F].Vn,Files[F].Off,C.RDS,C.RDX,C.RCX);
 If N<0 Then Begin SysWrite:=-N; Exit End;
 Inc(Files[F].Off,N); C.Ret:=N; SysWrite:=0;
End;

Function SysOpen(Path: TPath; Flags, Mode: Word): Integer;
{ open (drapeaux de 4.2BSD) et creat; mode de creation filtre par umask }
Var E,Vn,D,F,Fd: Integer; Last: TName; Want: Word; Created: Boolean;
Begin
 Created:=False;
 E:=Namei(Path,Vn);
 If (E=ENOENT) And (Flags And O_CREAT<>0) Then Begin
  E:=NameiParent(Path,D,Last);
  If E=0 Then Begin
   E:=VAccess(D,3);
   If E=0 Then E:=VCreate(D,Last,False,Mode,Vn);
   VPut(D);
   Created:=E=0;
  End;
 End Else If (E=0) And (Flags And O_CREAT<>0) And (Flags And O_EXCL<>0) Then
 Begin
  VPut(Vn); E:=EEXIST;
 End;
 If E<>0 Then Begin SysOpen:=E; Exit End;
 If Not Created Then Begin
  Case Flags And O_ACCMODE Of
   O_RDONLY: Want:=4;
   O_WRONLY: Want:=2;
   Else Want:=6;
  End;
  E:=VAccess(Vn,Want);
  If E<>0 Then Begin VPut(Vn); SysOpen:=E; Exit End;
 End;
 If (VNodes[Vn].Typ=VDIR) And (Flags And O_ACCMODE<>O_RDONLY) Then Begin
  VPut(Vn); SysOpen:=EISDIR; Exit;
 End;
 If (Flags And O_TRUNC<>0) And (Flags And O_ACCMODE<>O_RDONLY) Then Begin
  E:=VTrunc(Vn);
  If E<>0 Then Begin VPut(Vn); SysOpen:=E; Exit End;
 End;
 F:=FAlloc(Vn,Flags);
 If F=0 Then Begin VPut(Vn); SysOpen:=ENFILE; Exit End;
 Fd:=NewFd(F);
 If Fd<0 Then Begin FClose(F); SysOpen:=EMFILE; Exit End;
 C.Ret:=Fd; SysOpen:=0;
End;

Function SysClose: Integer;
Var F: Integer;
Begin
 SysClose:=GetFile(C.RBX,F);
 If F=0 Then Exit;
 Procs[Cur].Fd[C.RBX]:=0; FClose(F);
End;

Procedure FillStat(Vn: Integer; Sg, Os: Word);
{ struct stat de UNIX V7 (30 octets) : st_dev, st_ino, st_mode, st_nlink,
  st_uid, st_gid, st_rdev, st_size (32 bits), st_atime, st_mtime,
  st_ctime }
Begin
 FarFill(Sg,Os,30,0);
 With VNodes[Vn] Do Begin
  MemW[Sg:Os]:=Mnt;
  If Word(Ino)=0 Then MemW[Sg:Os+2]:=1 Else MemW[Sg:Os+2]:=Word(Ino);
  MemW[Sg:Os+4]:=Mode;
  MemW[Sg:Os+6]:=NLink;
  MemW[Sg:Os+8]:=Uid;
  MemW[Sg:Os+10]:=Gid;
  If Typ=VCHR Then MemW[Sg:Os+12]:=Minor;
  MemL[Sg:Os+14]:=Size;
  MemL[Sg:Os+18]:=MTime; MemL[Sg:Os+22]:=MTime; MemL[Sg:Os+26]:=MTime;
 End;
End;

Function SysGetDirEntries: Integer;
{ getdirentries (4.4BSD) : struct dirent = d_fileno (32 bits), d_reclen
  (16 bits), d_type, d_namlen, d_name termine par un nul, longueur arrondie
  a un multiple de 4 }
Var F,Vn: Integer; Pos,Save,Ino: Longint; Name: TName; Typ: Byte;
  Done,RecLen: Word; I: Integer;
Begin
 SysGetDirEntries:=GetFile(C.RBX,F);
 If F=0 Then Exit;
 Vn:=Files[F].Vn;
 If VNodes[Vn].Typ<>VDIR Then Begin SysGetDirEntries:=ENOTDIR; Exit End;
 Pos:=Files[F].Off; Done:=0;
 Repeat
  Save:=Pos;
  If Not VReadDir(Vn,Pos,Name,Ino,Typ) Then Break;
  RecLen:=(8+Length(Name)+1+3) And $FFFC;
  If Done+RecLen>C.RCX Then Begin
   Pos:=Save;
   If Done=0 Then Begin SysGetDirEntries:=EINVAL; Exit End;
   Break;
  End;
  FarFill(C.RDS,C.RDX+Done,RecLen,0);
  MemL[C.RDS:C.RDX+Done]:=Ino;
  MemW[C.RDS:C.RDX+Done+4]:=RecLen;
  Mem[C.RDS:C.RDX+Done+6]:=Typ;
  Mem[C.RDS:C.RDX+Done+7]:=Length(Name);
  For I:=1 To Length(Name) Do Mem[C.RDS:C.RDX+Done+7+I]:=Ord(Name[I]);
  Inc(Done,RecLen);
 Until False;
 Files[F].Off:=Pos;
 C.Ret:=Done;
End;

Function SysLSeek: Integer;
Var F: Integer; O: Longint;
Begin
 SysLSeek:=GetFile(C.RBX,F);
 If F=0 Then Exit;
 If VNodes[Files[F].Vn].Typ In [VFIFO,VCHR] Then
  If (VNodes[Files[F].Vn].Typ=VFIFO) Or (VNodes[Files[F].Vn].Minor<DEVDISK) Then
  Begin SysLSeek:=ESPIPE; Exit End;
 O:=Longint(C.RCX) Shl 16+C.RDX;
 Case C.RSI Of
  0: ;
  1: O:=O+Files[F].Off;
  2: O:=O+VNodes[Files[F].Vn].Size;
  Else Begin SysLSeek:=EINVAL; Exit End;
 End;
 If O<0 Then Begin SysLSeek:=EINVAL; Exit End;
 Files[F].Off:=O; C.Ret:=O; C.SetDX:=True;
End;

Function Owner(Vn: Integer): Integer;
{ EPERM si le processus n'est ni proprietaire de Vn ni super-utilisateur }
Begin
 If Suser Or (VNodes[Vn].Uid=Procs[Cur].Uid) Then Owner:=0 Else Owner:=EPERM;
End;

Function SysPathOp(Op: Integer): Integer;
{ unlink (10), chdir (12), mknod (14), chmod (15), chown (16), utime (30),
  access (33), mkdir (136), rmdir (137) }
Var E,D,Vn: Integer; Last: TName; P: TPath; T: Longint; U,G: Word;
Begin
 P:=UStr(C.RDS,C.RDX);
 Case Op Of
  10,14,136,137: Begin
   E:=NameiParent(P,D,Last);
   If E=0 Then Begin
    E:=VAccess(D,3);
    If E=0 Then Case Op Of
     10: E:=VRemove(D,Last,False);
     137: E:=VRemove(D,Last,True);
     136: Begin E:=VCreate(D,Last,True,C.RCX,Vn); If E=0 Then VPut(Vn) End;
     14: Case C.RCX And S_IFMT Of
          S_IFDIR: Begin E:=VCreate(D,Last,True,C.RCX,Vn); If E=0 Then VPut(Vn) End;
          0,S_IFREG: Begin E:=VCreate(D,Last,False,C.RCX,Vn); If E=0 Then VPut(Vn) End;
          Else If Suser Then E:=EINVAL Else E:=EPERM;
         End;
    End;
    VPut(D);
   End;
  End;
  Else Begin
   E:=Namei(P,Vn);
   If E<>0 Then Begin SysPathOp:=E; Exit End;
   Case Op Of
    12: If VNodes[Vn].Typ<>VDIR Then E:=ENOTDIR
        Else Begin
         E:=VAccess(Vn,1);
         If E=0 Then Procs[Cur].Cwd:=NormPath(Procs[Cur].Cwd,P);
        End;
    15: Begin E:=Owner(Vn); If E=0 Then E:=VChmod(Vn,C.RCX) End;
    16: If Not Suser Then E:=EPERM Else E:=VChown(Vn,C.RBX,C.RCX);
    30: Begin
         { utime(nom, temps) : temps = (acces, modification), ou 0 = maintenant }
         If (C.RES=0) And (C.RDI=0) Then Begin
          T:=KTime; E:=Owner(Vn); If E<>0 Then E:=VAccess(Vn,2);
         End Else Begin T:=MemL[C.RES:C.RDI+4]; E:=Owner(Vn) End;
         If E=0 Then E:=VUtime(Vn,T);
        End;
    33: If C.RBX And 7<>0 Then With Procs[Cur] Do Begin
         { access : avec l'utilisateur et le groupe reels (comme V7) }
         U:=Uid; G:=Gid; Uid:=RUid; Gid:=RGid;
         E:=VAccess(Vn,C.RBX And 7);
         Uid:=U; Gid:=G;
        End;
   End;
   VPut(Vn);
  End;
 End;
 SysPathOp:=E;
End;

Function SysRename(Link: Boolean): Integer;
Var E,D1,D2,Vn: Integer; L1,L2: TName; P1,P2: TPath;
Begin
 P1:=UStr(C.RDS,C.RDX); P2:=UStr(C.RES,C.RDI);
 E:=NameiParent(P2,D2,L2);
 If E<>0 Then Begin SysRename:=E; Exit End;
 E:=VAccess(D2,3);
 If E<>0 Then Begin VPut(D2); SysRename:=E; Exit End;
 If Link Then Begin
  E:=Namei(P1,Vn);
  If E=0 Then Begin E:=VLink(D2,L2,Vn); VPut(Vn) End;
 End Else Begin
  E:=NameiParent(P1,D1,L1);
  If E=0 Then Begin
   E:=VAccess(D1,3);
   If E=0 Then E:=VRename(D1,L1,D2,L2);
   VPut(D1);
  End;
 End;
 VPut(D2);
 SysRename:=E;
End;

Function SysKill: Integer;
{ kill(pid, sig) : pid > 0 un processus, 0 tous ceux de l'utilisateur
  (le terminal est commun), -1 tous sauf init et l'appelant; sig = 0 :
  verification seulement. Un utilisateur ordinaire ne peut signaler que
  ses propres processus. }
Var I,P,N: Integer;
Begin
 SysKill:=0; N:=0;
 If (C.RCX<0) Or (C.RCX>=NSIG) Then Begin SysKill:=EINVAL; Exit End;
 If (Integer(C.RBX)=-1) Or (C.RBX=0) Then Begin
  For I:=1 To NPROC-1 Do
   If (Procs[I].Stat In [PRUN,PSLEEP]) And (Procs[I].Pid>1) And
     ((I<>Cur) Or (C.RBX=0)) And
     (Suser Or (Procs[I].Uid=Procs[Cur].Uid)) Then
   Begin If C.RCX<>0 Then PostSig(I,C.RCX); Inc(N) End;
  If N=0 Then SysKill:=ESRCH;
  Exit;
 End;
 P:=FindPid(C.RBX);
 If (P<0) Or (Procs[P].Stat=PZOMB) Then Begin SysKill:=ESRCH; Exit End;
 If Not Suser And (Procs[P].Uid<>Procs[Cur].Uid) Then Begin
  SysKill:=EPERM; Exit;
 End;
 If C.RCX<>0 Then PostSig(P,C.RCX);
End;

Function DiskIoctl(D: Integer): Integer;
{ DIOCGINFO : secteurs (32 bits), tetes, secteurs par piste, cylindres,
  debut (32 bits), type de partition, unite BIOS; DIOCRESCAN : relecture
  de la table des partitions (aucune partition du disque montee);
  DIOCINVAL : tampons du disque ecrits puis oublies (changement de
  disquette) }
Var M: Integer;
Begin
 DiskIoctl:=0;
 Case C.RCX Of
  DIOCGINFO: With Disks[D] Do Begin
   SetGeometry(D);
   If Sectors<>0 Then MemL[C.RDS:C.RDX]:=Sectors
   Else MemL[C.RDS:C.RDX]:=Longint(Cyls)*Heads*Spt;
   MemW[C.RDS:C.RDX+4]:=Heads; MemW[C.RDS:C.RDX+6]:=Spt;
   MemW[C.RDS:C.RDX+8]:=Cyls; MemL[C.RDS:C.RDX+10]:=Start;
   Mem[C.RDS:C.RDX+14]:=PartType; Mem[C.RDS:C.RDX+15]:=Bios;
  End;
  DIOCRESCAN: Begin
   If Not Suser Then Begin DiskIoctl:=EPERM; Exit End;
   For M:=1 To NMOUNT Do
    If Mounts[M].Used And (Mounts[M].Typ<>FSDEV) And
      (Disks[Mounts[M].Drive].Bios=Disks[D].Bios) Then Begin
     DiskIoctl:=EBUSY; Exit;
    End;
   DiskIoctl:=DiskRescan(D);
  End;
  DIOCINVAL: BInval(D);
 End;
End;

Function SysIoctl: Integer;
{ ioctl(fd, requete, DS:DX argument) : sgttyb et tchars de UNIX V7 pour la
  console, FIONREAD (4.2BSD) pour la console, les tubes et les fichiers }
Var F,Vn: Integer; IsTty: Boolean; I: Integer; N: Longint;
Begin
 SysIoctl:=GetFile(C.RBX,F);
 If F=0 Then Exit;
 Vn:=Files[F].Vn;
 IsTty:=(VNodes[Vn].Typ=VCHR) And (VNodes[Vn].Minor=DEVTTY);
 If (VNodes[Vn].Typ=VCHR) And (VNodes[Vn].Minor>=DEVDISK) And
   (C.RCX>=DIOCGINFO) And (C.RCX<=DIOCINVAL) Then Begin
  SysIoctl:=DiskIoctl(VNodes[Vn].Minor-DEVDISK);
  Exit;
 End;
 If C.RCX=FIONREAD Then Begin
  If IsTty Then N:=TtyAvail
  Else If VNodes[Vn].Typ=VFIFO Then N:=PipeCount[VNodes[Vn].Minor]
  Else If VNodes[Vn].Typ=VREG Then N:=VNodes[Vn].Size-Files[F].Off
  Else N:=0;
  If N>$7FFF Then N:=$7FFF;
  If N<0 Then N:=0;
  MemW[C.RDS:C.RDX]:=N;
  Exit;
 End;
 If Not IsTty Then Begin SysIoctl:=ENOTTY; Exit End;
 Case C.RCX Of
  TIOCGETP: Begin
   Mem[C.RDS:C.RDX]:=13; Mem[C.RDS:C.RDX+1]:=13;   { B9600 }
   Mem[C.RDS:C.RDX+2]:=Ord(TtyErase); Mem[C.RDS:C.RDX+3]:=Ord(TtyKill);
   MemW[C.RDS:C.RDX+4]:=TtyFlags;
  End;
  TIOCSETP,TIOCSETN: Begin
   TtyErase:=Chr(Mem[C.RDS:C.RDX+2]); TtyKill:=Chr(Mem[C.RDS:C.RDX+3]);
   TtyFlags:=MemW[C.RDS:C.RDX+4];
   If C.RCX=TIOCSETP Then TtyFlush;
  End;
  TIOCGETC: For I:=0 To 5 Do Mem[C.RDS:C.RDX+I]:=Ord(TChars[I]);
  TIOCSETC: For I:=0 To 5 Do TChars[I]:=Chr(Mem[C.RDS:C.RDX+I]);
  TIOCFLUSH: TtyFlush;
  TIOCHPCL,TIOCEXCL,TIOCNXCL: ;
  Else SysIoctl:=EINVAL;
 End;
End;

Procedure PutPStr(Sg, Os: Word; S: String; Max: Integer);
Var I: Integer;
Begin
 If Length(S)>Max Then S[0]:=Chr(Max);
 For I:=0 To Length(S) Do Mem[Sg:Os+I]:=Ord(S[I]);
End;

Function SysProcInfo: Integer;
Var P: Integer;
Begin
 SysProcInfo:=0;
 If C.RBX>=NPROC Then Begin SysProcInfo:=EINVAL; Exit End;
 P:=C.RBX; C.Ret:=0;
 If (P=0) Or (Procs[P].Stat=PFREE) Then Exit;
 With Procs[P] Do Begin
  MemW[C.RDS:C.RDX]:=Pid; MemW[C.RDS:C.RDX+2]:=PPid;
  If Stat=PRUN Then Mem[C.RDS:C.RDX+4]:=1 Else If Stat=PSLEEP Then
    Mem[C.RDS:C.RDX+4]:=2 Else Mem[C.RDS:C.RDX+4]:=3;
  Mem[C.RDS:C.RDX+5]:=Ord(P=Cur) Or (Ord(Swapped) Shl 1);
  MemW[C.RDS:C.RDX+6]:=Size;
  MemL[C.RDS:C.RDX+8]:=CpuTicks;
  PutPStr(C.RDS,C.RDX+12,Name,15);
  MemW[C.RDS:C.RDX+28]:=Uid;
  MemW[C.RDS:C.RDX+30]:=Gid;
 End;
 C.Ret:=1;
End;

Function SysMountInfo: Integer;
Var M: Integer;
Begin
 SysMountInfo:=0; C.Ret:=0;
 If (C.RBX<1) Or (C.RBX>NMOUNT) Then Begin SysMountInfo:=EINVAL; Exit End;
 M:=C.RBX;
 If Not Mounts[M].Used Then Exit;
 FarFill(C.RDS,C.RDX,64,0);
 With Mounts[M] Do Begin
  Case Typ Of FSFAT12: Mem[C.RDS:C.RDX]:=1; FSFAT16: Mem[C.RDS:C.RDX]:=2;
   FSUFS: Mem[C.RDS:C.RDX]:=3; Else Mem[C.RDS:C.RDX]:=4; End;
  Mem[C.RDS:C.RDX+1]:=Drive; Mem[C.RDS:C.RDX+2]:=Ord(RO);
  MemL[C.RDS:C.RDX+4]:=Start;
  MemL[C.RDS:C.RDX+8]:=Sectors Div 2;
  MemL[C.RDS:C.RDX+12]:=MountFree(M);
  PutPStr(C.RDS,C.RDX+16,Dir,31);
  PutPStr(C.RDS,C.RDX+48,Special,15);
 End;
 C.Ret:=1;
End;

Function Hz60(T: Longint): Longint;
{ tops d'horloge (18,2 Hz) -> soixantiemes de seconde (HZ de UNIX V7) }
Begin
 Hz60:=(T Div 91)*300+((T Mod 91)*300) Div 91;
End;

Function Shared(P: Integer): Boolean;
{ l'image de P est partagee (vfork, ou fork dont l'autre image est
  echangee a la meme adresse) }
Var I: Integer;
Begin
 Shared:=Procs[P].Borrowed;
 For I:=1 To NPROC-1 Do
  If (I<>P) And (Procs[I].Stat<>PFREE) And (Procs[I].Size<>0) And
    (Procs[I].Home=Procs[P].Home) Then Shared:=True;
End;

Function SysBreak: Integer;
{ break (UNIX V7) : BX = nouvelle fin de l'image (paragraphe absolu; 0 =
  fin actuelle), rendue dans AX. L'image d'un processus 8086 n'est pas
  deplacable : elle s'agrandit sur place si la memoire qui la suit est
  libre (sinon ENOMEM), et peut rendre sa fin au systeme. }
Var Fin: Word;
Begin
 SysBreak:=0;
 With Procs[Cur] Do Begin
  Fin:=Home+Size; C.Ret:=Fin;
  If C.RBX=0 Then Exit;
  If C.RBX>Fin Then Begin
   If Shared(Cur) Then Begin SysBreak:=ENOMEM; Exit End;
   { la memoire qui suit l'image est liberee au besoin par le va-et-vient }
   If Not CoreGrow(Fin,C.RBX-Fin) Then
    If (SwapDisk<0) Or Not ClaimRange(Fin,C.RBX-Fin,Cur) Then Begin
     SysBreak:=ENOMEM; Exit;
    End;
  End Else Begin
   If C.RBX<PSP+16 Then Begin SysBreak:=EINVAL; Exit End;
   If Shared(Cur) Then Begin SysBreak:=ENOMEM; Exit End;
   CoreFree(C.RBX,Fin-C.RBX);
  End;
  Size:=C.RBX-Home; C.Ret:=C.RBX;
 End;
End;

Function SysWait: Integer;
Var St: Word; R: Integer;
Begin
 SysWait:=0;
 R:=DoWait(Integer(C.RBX),C.RCX,St);
 If R<0 Then SysWait:=-R
 Else Begin C.Ret:=R; C.Ret2:=St; C.SetDX:=True; C.Two:=True End;
End;

Function SysExec(Env: Boolean): Integer;
{ exec (11) : DS:DX nom, ES:DI argv; exece (59) : et SI:CX envp }
Var P: TPath; E: Integer;
Begin
 P:=UStr(C.RDS,C.RDX);
 If Env Then E:=GatherArgs(C.RES,C.RDI,C.RSI,C.RCX)
 Else E:=GatherArgs(C.RES,C.RDI,0,0);
 If E=0 Then E:=DoExec(P);
 SysExec:=E;
End;

Function SysDup2(Fd, Fd2: Word): Integer;
Var E,F: Integer;
Begin
 E:=GetFile(Fd,F);
 If (F<>0) And (Fd2>=NOFILE) Then E:=EBADF;
 If (E=0) And (Fd<>Fd2) Then Begin
  If Procs[Cur].Fd[Fd2]<>0 Then FClose(Procs[Cur].Fd[Fd2]);
  Procs[Cur].Fd[Fd2]:=F; FRef(F);
 End;
 C.Ret:=Fd2; SysDup2:=E;
End;

Function SysSignal: Integer;
{ signal(sig, action) : CX:DX = action (0 = SIG_DFL, 1 = SIG_IGN, sinon
  adresse FAR du gestionnaire, appele par la trampoline de la libc);
  DX:AX = action precedente }
Var H: Longint;
Begin
 SysSignal:=0;
 If (C.RBX<1) Or (C.RBX>=NSIG) Or (C.RBX=SIGKILL) Then Begin
  SysSignal:=EINVAL; Exit;
 End;
 With Procs[Cur] Do Begin
  C.Ret:=SigH[C.RBX]; C.SetDX:=True;
  H:=Longint(C.RDX) Shl 16+C.RCX;
  SigH[C.RBX]:=H;
  If H=1 Then Begin
   SigIgn:=SigIgn Or (1 Shl C.RBX);
   SigPend:=SigPend And Not (1 Shl C.RBX);
  End Else SigIgn:=SigIgn And Not (1 Shl C.RBX);
 End;
End;

Procedure SysDispatch;
Var E,F,Fd,R,W,I: Integer; P: TPath; Vn: Integer; T: Longint;
Begin
 C.RAX:=UserW(0); C.RBX:=UserW(2); C.RCX:=UserW(4); C.RDX:=UserW(6);
 C.RSI:=UserW(8); C.RDI:=UserW(10); C.RES:=UserW(14); C.RDS:=UserW(16);
 E:=0; C.Ret:=0; C.Ret2:=0; C.SetDX:=False; C.Two:=False;
 Case C.RAX Of
  1: DoExit((C.RBX And $FF) Shl 8);
  2: Begin C.Ret:=DoFork; If C.Ret<0 Then Begin E:=-C.Ret; C.Ret:=0 End End;
  3: E:=SysRead;
  4: E:=SysWrite;
  5: E:=SysOpen(UStr(C.RDS,C.RDX),C.RBX,C.RCX);
  6: E:=SysClose;
  7: E:=SysWait;
  8: E:=SysOpen(UStr(C.RDS,C.RDX),O_WRONLY Or O_CREAT Or O_TRUNC,C.RCX);
  9: E:=SysRename(True);
  10,12,14,15,16,30,33,136,137: E:=SysPathOp(C.RAX);
  11: E:=SysExec(False);
  13: Begin C.Ret:=KTime; C.SetDX:=True End;
  17: E:=SysBreak;
  18: Begin
       E:=Namei(UStr(C.RDS,C.RDX),Vn);
       If E=0 Then Begin FillStat(Vn,C.RES,C.RDI); VPut(Vn) End;
      End;
  19: E:=SysLSeek;
  20: Begin C.Ret:=Procs[Cur].Pid; C.Ret2:=Procs[Cur].PPid; C.SetDX:=True; C.Two:=True End;
  21: If Not Suser Then E:=EPERM Else Begin
       E:=Namei(UStr(C.RES,C.RDI),Vn);
       If E=0 Then Begin
        If VNodes[Vn].Typ<>VDIR Then E:=ENOTDIR;
        VPut(Vn);
       End;
       If E=0 Then E:=DoMount(UStr(C.RDS,C.RDX),UStr(C.RES,C.RDI),C.RBX);
      End;
  22: If Not Suser Then E:=EPERM Else E:=DoUmount(UStr(C.RDS,C.RDX));
  23: With Procs[Cur] Do
       If Suser Or (C.RBX=RUid) Then Begin Uid:=C.RBX; RUid:=C.RBX End
       Else E:=EPERM;
  24: Begin C.Ret:=Procs[Cur].RUid; C.Ret2:=Procs[Cur].Uid; C.SetDX:=True; C.Two:=True End;
  25: If Not Suser Then E:=EPERM Else
       BootTime:=(Longint(C.RCX) Shl 16+C.RBX)-(Ticks*10) Div 182;
  27: With Procs[Cur] Do Begin
       If Alarm<>0 Then C.Ret:=((Alarm-Ticks)*10+181) Div 182 Else C.Ret:=0;
       If C.RBX=0 Then Alarm:=0
       Else Alarm:=Ticks+(Longint(C.RBX)*182) Div 10+1;
      End;
  28: Begin
       E:=GetFile(C.RBX,F);
       If F<>0 Then FillStat(Files[F].Vn,C.RES,C.RDI);
      End;
  29: If Not SleepIntr(CHPAUSE+Cur) Then E:=EINTR;
  31,32: Begin
       { stty/gtty (V7) : comme ioctl TIOCSETP/TIOCGETP }
       If C.RAX=31 Then C.RCX:=TIOCSETP Else C.RCX:=TIOCGETP;
       E:=SysIoctl;
      End;
  34: With Procs[Cur] Do
       If (Integer(C.RBX)<0) And Not Suser Then E:=EPERM
       Else Begin
        Nice:=Nice+Integer(C.RBX);
        If Nice>20 Then Nice:=20; If Nice<-20 Then Nice:=-20;
       End;
  35: Begin
       { ftime : struct timeb (time, millitm, timezone, dstflag) }
       MemL[C.RDS:C.RDX]:=KTime;
       MemW[C.RDS:C.RDX+4]:=Word(((Ticks*10) Mod 182)*1000 Div 182);
       MemW[C.RDS:C.RDX+6]:=0; MemW[C.RDS:C.RDX+8]:=0;
      End;
  36: BSync;
  37: E:=SysKill;
  39: C.Ret:=Procs[Cur].PPid;
  41: If C.RBX And $40<>0 Then E:=SysDup2(C.RBX And $3F,C.RCX)
      Else Begin
       E:=GetFile(C.RBX,F);
       If F<>0 Then Begin
        Fd:=NewFd(F); If Fd<0 Then E:=EMFILE Else Begin FRef(F); C.Ret:=Fd End;
       End;
      End;
  42: Begin
       E:=PipeAlloc(R,W);
       If E=0 Then Begin
        Fd:=NewFd(R);
        If Fd<0 Then Begin FClose(R); FClose(W); E:=EMFILE End
        Else Begin
         C.Ret:=Fd; Fd:=NewFd(W);
         If Fd<0 Then Begin
          Procs[Cur].Fd[C.Ret]:=0; FClose(R); FClose(W); E:=EMFILE;
         End Else Begin C.Ret2:=Fd; C.SetDX:=True; C.Two:=True End;
        End;
       End;
      End;
  43: Begin
       { times : struct tms en soixantiemes de seconde }
       MemL[C.RDS:C.RDX]:=Hz60(Procs[Cur].CpuTicks);
       MemL[C.RDS:C.RDX+4]:=0;
       MemL[C.RDS:C.RDX+8]:=Hz60(Procs[Cur].ChildTicks);
       MemL[C.RDS:C.RDX+12]:=0;
       C.Ret:=Hz60(Ticks); C.SetDX:=True;
      End;
  46: With Procs[Cur] Do
       If Suser Or (C.RBX=RGid) Then Begin Gid:=C.RBX; RGid:=C.RBX End
       Else E:=EPERM;
  47: Begin C.Ret:=Procs[Cur].RGid; C.Ret2:=Procs[Cur].Gid; C.SetDX:=True; C.Two:=True End;
  48: E:=SysSignal;
  54: E:=SysIoctl;
  55: If Not Suser Then E:=EPERM Else Begin
       BSync;
       KPrintLn('Redemarrage du systeme...');
       Asm
        CLI
        MOV AX,40h
        MOV DS,AX
        MOV WORD PTR DS:[72h],1234h
        DB 0EAh
        DW 0000h,0FFFFh
       End;
      End;
  57: Begin
       { uname : 5 champs de 16 octets (chaines Pascal) }
       PutPStr(C.RDS,C.RDX,'LINUX-0',15);
       PutPStr(C.RDS,C.RDX+16,'unix0',15);
       PutPStr(C.RDS,C.RDX+32,KVersion,15);
       PutPStr(C.RDS,C.RDX+48,'2026',15);
       PutPStr(C.RDS,C.RDX+64,'i8086',15);
      End;
  59: E:=SysExec(True);
  60: Begin C.Ret:=Procs[Cur].Umask; Procs[Cur].Umask:=C.RBX And $1FF End;
  66: Begin C.Ret:=DoVFork; If C.Ret<0 Then Begin E:=-C.Ret; C.Ret:=0 End End;
  90: E:=SysDup2(C.RBX,C.RCX);
  128: E:=SysRename(False);
  156: E:=SysGetDirEntries;
  200: E:=SysProcInfo;
  201: Begin
       Procs[Cur].DosOfs:=C.RBX; Procs[Cur].DosSeg:=C.RCX;
       SetDosVector(Cur);
      End;
  202: Begin
       MemW[C.RDS:C.RDX]:=TotalParas;
       MemW[C.RDS:C.RDX+2]:=CoreFreeTotal;
       MemW[C.RDS:C.RDX+4]:=KernelEnd-$1000;
       MemW[C.RDS:C.RDX+6]:=NBUF;
       F:=0; For I:=1 To NPROC-1 Do If Procs[I].Stat<>PFREE Then Inc(F);
       MemW[C.RDS:C.RDX+8]:=F;
       MemW[C.RDS:C.RDX+10]:=NPROC-1;
       MemW[C.RDS:C.RDX+12]:=SwapSize Div 2;          { Ko }
       If SwapDisk>=0 Then MemW[C.RDS:C.RDX+14]:=SwapFreeSectors Div 2
       Else MemW[C.RDS:C.RDX+14]:=0;
       MemW[C.RDS:C.RDX+16]:=Word(SwapOuts);
       MemW[C.RDS:C.RDX+18]:=Word(SwapIns);
      End;
  203: E:=SysMountInfo;
  204: Procs[Cur].SigTramp:=Longint(C.RCX) Shl 16+C.RBX;
  205: Begin
       P:=Procs[Cur].Cwd;
       If Length(P)+1>C.RCX Then E:=ERANGE
       Else PutFarStr(C.RDS,C.RDX,P);
       C.Ret:=Length(P);
      End;
  206: Begin
       { nap(ms) : sommeil en millisecondes (interruptible) }
       Procs[Cur].Wake:=Ticks+(Longint(C.RBX)*182+9999) Div 10000;
       If Procs[Cur].Wake=Ticks Then Inc(Procs[Cur].Wake);
       If Not SleepIntr(CHSLEEP) Then E:=EINTR;
       Procs[Cur].Wake:=0;
      End;
  Else Begin
   { appel inexistant : SIGSYS (comme UNIX V7) }
   E:=EINVAL; PostSig(Cur,SIGSYS);
  End;
 End;
 If E<>0 Then Begin
  SetUserW(0,E); SetUserW(22,UserW(22) Or 1);
 End Else Begin
  SetUserW(0,Word(C.Ret)); SetUserW(22,UserW(22) And $FFFE);
  If C.SetDX Then Begin
   If C.Two Then SetUserW(6,Word(C.Ret2)) Else SetUserW(6,Word(C.Ret Shr 16));
  End;
 End;
 CheckSignals;
 If RunRun Then Swtch;
End;

Procedure PreemptEntry;
{ fin de quantum en mode utilisateur (horloge) }
Begin
 TtyCheckIntr;
 Swtch;
 CheckSignals;
End;

Procedure FaultEntry;
Begin
 PostSig(Cur,SIGFPE);
 CheckSignals;
End;

SegmentEnd;

{ ====================================================================== }
{ Programme principal : initialisation du noyau (processus 0).            }
{ ====================================================================== }

Var
 MbrBuf: Array[0..511] Of Byte;

Procedure ProbeDisks;
{ disquettes (liste d'equipement du BIOS), disques durs et leurs
  partitions (table du MBR) }
Var Equip: Word; NF,NH,I,J,D: Integer; T: Byte; S,N: Longint;
Const Letters: String[4]='abcd';
Begin
 Equip:=MemW[$40:$10];
 NF:=0;
 If Equip And 1<>0 Then NF:=((Equip Shr 6) And 3)+1;
 If (BootDrive<$80) And (NF<=BootDrive) Then NF:=BootDrive+1;
 For I:=0 To NF-1 Do If I<2 Then AddDisk(I,'fd'+Chr(48+I),0,0,0);
 { disques durs : compte du BIOS (0040:0075), sinon INT 13h AH=08h (DL =
   nombre de disques), et au moins jusqu'a l'unite d'amorce }
 NH:=Mem[$40:$75];
 Asm
  PUSH ES
  PUSH DI
  MOV AH,8
  MOV DL,80h
  PUSH BP
  INT 13h
  POP BP
  POP DI
  POP ES
  JC @NoHd
  MOV T,DL
  JMP @Fin
 @NoHd:
  MOV T,0
 @Fin:
 End;
 If T>NH Then NH:=T;
 If (BootDrive>=$80) And (NH<BootDrive-$7F) Then NH:=BootDrive-$7F;
 If NH>2 Then NH:=2;
 For I:=0 To NH-1 Do Begin
  D:=AddDisk($80+I,'hd'+Letters[I+1],0,0,0);
  If D<0 Then Exit;
  If DiskIO(D,0,Seg(MbrBuf),Ofs(MbrBuf),False) And (MbrBuf[510]=$55) And
    (MbrBuf[511]=$AA) Then
   For J:=0 To 3 Do Begin
    T:=MbrBuf[446+J*16+4];
    S:=MemL[Seg(MbrBuf):Ofs(MbrBuf)+446+J*16+8];
    N:=MemL[Seg(MbrBuf):Ofs(MbrBuf)+446+J*16+12];
    If (T<>0) And (N<>0) Then
     AddDisk($80+I,'hd'+Letters[I+1]+Chr(49+J),S,N,T);
   End;
 End;
End;

Function RootDevice: String;
Var I: Integer;
Begin
 RootDevice:='';
 For I:=0 To DiskCount-1 Do With Disks[I] Do
  If Bios=BootDrive Then Begin
   If BootDrive<$80 Then Begin RootDevice:=Name; Exit End;
   If Start=BootStart Then Begin RootDevice:=Name; Exit End;
  End;
End;

Procedure ShowDisks;
Var I: Integer; S: String;
Begin
 For I:=0 To DiskCount-1 Do With Disks[I] Do Begin
  S:='  '+Name+' : unite BIOS '+HexStr(Bios);
  If Start<>0 Then S:=S+', partition de type '+HexStr(PartType)+', '+
    IntStr(Sectors Div 2048)+' Mo';
  KPrintLn(S);
 End;
End;

Procedure StartInit;
{ processus 1 : /etc/init (ou /bin/sh) }
Var P,Fd,F,Vn,E: Integer; Path: String;

 Procedure Add(A: String);
 Var I: Integer;
 Begin
  For I:=1 To Length(A) Do KArgs[KArgLen+I-1]:=A[I];
  Inc(KArgLen,Length(A)); KArgs[KArgLen]:=#0; Inc(KArgLen);
 End;

 Procedure SetArgs(A: String);
 Begin
  KArgLen:=0; KArgc:=1; KEnvc:=2;
  Add(A); Add('PATH=/bin:/usr/bin'); Add('HOME=/');
 End;

Begin
 P:=1;
 FillChar(Procs[P].Fd,SizeOf(Procs[P].Fd),0);
 Procs[P].Pid:=1; Procs[P].PPid:=0; Procs[P].Cwd:='/';
 Procs[P].Name:='init'; Procs[P].Size:=0;
 Procs[P].Umask:=$12;                       { 022 }
 Procs[P].Stat:=PSLEEP;
 Cur:=P;
 { descripteurs 0, 1 et 2 : la console }
 E:=Namei('/dev/tty',Vn);
 If E<>0 Then Panic('/dev/tty introuvable');
 F:=FAlloc(Vn,O_RDWR);
 Procs[P].Fd[0]:=F; Procs[P].Fd[1]:=F; Procs[P].Fd[2]:=F;
 FRef(F); FRef(F);
 Path:='/etc/init'; SetArgs(Path);
 E:=DoExec(Path);
 If E<>0 Then Begin
  Path:='/bin/sh'; SetArgs(Path);
  E:=DoExec(Path);
 End;
 If E<>0 Then Panic('impossible de lancer /etc/init ou /bin/sh (erreur '+
   IntStr(E)+')');
 KPrintLn('init : '+Path+' (pid 1)');
 If Not GetKStack(P) Then Panic('pas de memoire pour la pile noyau d''init');
 SetupKStack(P);
 Procs[P].Stat:=PRUN;
 Cur:=0;
End;

Const
 CSegStart=$1000;   { paragraphe de chargement du noyau (LPC /K) }

Var
 I,E: Integer;
 Root,Boot: String;

BEGIN
 { le processus 0 (amorce) s'execute en mode noyau : l'horloge ne doit
   jamais le preempter, meme apres l'activation de l'ordonnanceur }
 InKernel:=1;
 { le secteur d'amorce (0000:7C00) contient encore le BPB }
 BootDrive:=Mem[0:$7C24];
 BootStart:=MemL[0:$7C1C];
 KDataSeg:=DSeg;
 ConPage:=Mem[$40:$62];
 SerialInit;
 KPrintLn('');
 KPrintLn('LINUX-0 version '+KVersion+' (noyau 16 bits pour IBM PC 8086)');
 BootTime:=ReadRTC;
 MemTop:=MemW[$40:$13]*64;
 { fin des donnees du noyau : les longueurs des donnees stockees et du BSS
   sont dans le code de demarrage (mov di,n ; mov cx,m a 1000:000C) }
 KernelEnd:=DSeg+(Longint(MemW[CSegStart:$0D])+MemW[CSegStart:$10]+15) Div 16+1;
 KPrintLn('memoire : '+IntStr(MemW[$40:$13])+' Ko, noyau '+
   IntStr((Longint(KernelEnd)-$1000) Div 64)+' Ko a 1000:0000, donnees a '+
   HexStr(DSeg)+':0000');
 CoreInit(KernelEnd,MemTop);
 { piles noyau : allouees a la creation de chaque processus (GetKStack) }
 For I:=0 To NPROC-1 Do Begin
  FillChar(Procs[I],SizeOf(TProc),0);
  Procs[I].Cwd:='/';
 End;
 { processus 0 : contexte d'amorce, ne redevient jamais pret }
 Procs[0].Stat:=PSLEEP; Procs[0].Pid:=0; Procs[0].Name:='swapper';
 Procs[0].KStack:=0;
 Cur:=0; NextPid:=1;
 KPrintLn('memoire libre : '+IntStr(Longint(CoreFreeTotal)*16 Div 1024)+' Ko');
 { disques }
 SwapDisk:=-1;
 DiskInit;
 ProbeDisks;
 ShowDisks;
 { va-et-vient : premiere partition de type 82h. Les piles noyau sont
   alors reservees des maintenant, en haut de la memoire : une image qui
   revient de la zone doit pouvoir retrouver son adresse, et une pile noyau
   n'est pas deplacable. }
 ResidentHook:=@ResidentEntry;
 For I:=0 To DiskCount-1 Do
  If (SwapDisk<0) And (Disks[I].PartType=$82) Then SwapInit(I);
 If SwapDisk>=0 Then Begin
  KPrintLn('va-et-vient : /dev/'+Disks[SwapDisk].Name+' ('+
    IntStr(SwapSize Div 2048)+' Mo)');
  For I:=1 To NPROC-1 Do
   If Not GetKStack(I) Then Panic('pas de memoire pour les piles noyau');
 End;
 { vecteurs d'interruption }
 SysHook:=@SysDispatch; PreemptHook:=@PreemptEntry; FaultHook:=@FaultEntry;
 KSysInit; TtyInit;
 IdleHook:=@TtyPoll; SyncHook:=@BSync;
 OldInt08:=GetVector($08); OldInt1B:=GetVector($1B);
 SetVector($80,Seg(Int80Stub),Ofs(Int80Stub));
 SetVector($00,Seg(Int00Stub),Ofs(Int00Stub));
 SetVector($1B,Seg(Int1BStub),Ofs(Int1BStub));
 SetVector($21,Seg(NoDosStub),Ofs(NoDosStub));
 SetVector($08,Seg(Int08Stub),Ofs(Int08Stub));
 { systemes de fichiers }
 { racine : comme un UNIX, la partition UFS (FreeBSD, type A5h) du disque
   d'amorce s'il y en a une. Amorce UFS (UFSBOOT) : c'est la partition
   d'amorce elle-meme (noyau /unix). Amorce FAT16 : la partition FAT, qui
   contient le noyau, est montee sur /boot. Sinon (disquettes, disque tout
   FAT), la racine est l'unite d'amorce FAT et une partition UFS eventuelle
   est montee sur /usr. }
 Boot:=RootDevice;
 If Boot='' Then Panic('unite d''amorce inconnue');
 Root:='';
 For I:=0 To DiskCount-1 Do
  If (Root='') And (Disks[I].Bios=BootDrive) And (Disks[I].PartType In [$A5,$A6,$A9]) Then
   Root:=Disks[I].Name;
 { amorce UFS : la partition d'amorce, si elle est de type UFS }
 For I:=0 To DiskCount-1 Do
  If (Disks[I].Name=Boot) And (Disks[I].PartType In [$A5,$A6,$A9]) Then
   Root:=Boot;
 E:=1;
 If Root<>'' Then E:=DoMount(Root,'/',2);
 If E<>0 Then Begin Root:=Boot; E:=DoMount(Root,'/',0) End;
 If E<>0 Then Panic('montage de la racine impossible ('+IntStr(E)+')');
 KPrintLn('racine : /dev/'+Root+' ('+
   Copy('FAT12FAT16UFS  ',(Mounts[1].Typ-1)*5+1,5)+')');
 E:=DoMount('devfs','/dev',0);
 If Root<>Boot Then Begin
  E:=DoMount(Boot,'/boot',1);
  If E=0 Then KPrintLn('/boot : /dev/'+Boot+' (noyau)');
 End Else If Mounts[1].Typ<>FSUFS Then
  For I:=0 To DiskCount-1 Do
   If Disks[I].PartType In [$A5,$A6,$A9] Then
    If Not IsMountDir('/usr') Then Begin
     E:=DoMount(Disks[I].Name,'/usr',2);
     If E=0 Then KPrintLn('/usr : /dev/'+Disks[I].Name+' (UFS)')
     Else KPrintLn('/dev/'+Disks[I].Name+' : pas de systeme UFS ('+IntStr(E)+')');
    End;
 StartInit;
 SchedOn:=True;
 Swtch;
 Panic('retour au processus 0');
END.
