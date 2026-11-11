{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2026
  @website(https://www.gladir.com/linux-0)
  @abstract(Target: Linux Pascal (LPC /X))
  @description: Programme d'installation de LINUX-0 (/bin/install) : installe
   le systeme sur un disque dur, a partir des disquettes d'installation ou
   du CD-ROM.
    1. choix du disque dur (pas celui d'ou le systeme a demarre) et du type
       d'installation :
        1) UFS seul (par defaut) : partition UFS1 active, amorcee
           directement (amorce /mdec/ufsboot dans ses 8 premiers Ko, noyau
           /unix), et partition de va-et-vient;
        2) FAT16 + UFS : partition FAT16 d'amorce de 4 Mo (secteur
           /mdec/bootsect, noyau, montee sur /boot), racine UFS1,
           va-et-vient;
        3) FAT16 seul : racine FAT16 (sans permissions UNIX), va-et-vient;
    2. table des partitions (MBR, code /mdec/mbr), alignees sur les
       cylindres du BIOS; le va-et-vient fait 4 Mo (type 82h);
    3. formatage FAT16 et creation du systeme de fichiers UFS1 (comme
       newfs), amorces;
    4. copie du noyau, puis extraction des volumes tar de la distribution
       (disquettes 2, 3, ... lues directement sur /dev/fd0, ou fichiers
       /dist/volN.tar du CD-ROM), avec modes, proprietaires et dates.
   Sur la disquette ou le CD d'installation, l'utilisateur "install" a ce
   programme pour interpreteur de connexion.
   Usage : install
}

Program Install;

{$M 8192,0,0}
{$I-}

Const
 { UFS1 : memes parametres que makefs -t ffs -o version=1 }
 FSIZE=1024; BSIZE=8192; FRAG=8; INOPB=64;
 SBLKNO=16; CBLKNO=24; IBLKNO=32;
 MAXFPG=32768;            { fragments par groupe de cylindres au plus }
 BOOTMB=4; SWAPMB=4; MINUFSMB=8;
 DIOCGINFO=$6401; DIOCRESCAN=$6402; DIOCINVAL=$6403;

Type
 TDiskInfo=Record
  Sectors: Longint;
  Heads, Spt, Cyls: Word;
  Start: Longint;
  PType, Bios: Byte;
 End;

Var
 Big: Array[0..8191] Of Byte;        { bloc de travail (groupe, superbloc) }
 Zero: Array[0..8191] Of Byte;
 Sec: Array[0..511] Of Byte;
 MbrCode, BootCode: Array[0..511] Of Byte;
 UfsBoot: Array[0..8191] Of Byte;     { /mdec/ufsboot, lu avant d'effacer }
 Layout: Integer;                    { 1 UFS, 2 FAT16 + UFS, 3 FAT16 }
 UfsPart, FatPart: String[1];        { numeros des partitions ('' : aucune) }
 UfsStart, UfsSize, FatStart, FatSize, SwapStart, SwapSize: Longint;
 CsTab: Array[0..1023] Of Byte;      { resume des groupes (64 groupes au plus) }
 Disk: String[7];                    { disque choisi : hda, hdb }
 Info: TDiskInfo;
 FromCD: Boolean;
 Now: Longint;
 Files,Dirs: Longint;
 { lecture d'un volume tar par blocs }
 VolFd: Integer;
 RBuf: Array[0..8191] Of Byte;
 RLen,RPos: Integer;

{ --- utilitaires ----------------------------------------------------- }

Function IStr(L: Longint): String;
Var S: String;
Begin
 Str(L,S); IStr:=S;
End;

Procedure Fatal(S: String);
Begin
 WriteLn;
 WriteLn('install : ',S);
 WriteLn('Installation abandonnee.');
 SysSync;
 Halt(1);
End;

Function Ask(Prompt: String): String;
Var S: String; C: Char; N: Integer;
Begin
 Write(Prompt);
 S:='';
 Repeat
  N:=SysRead(0,C,1);
  If N<=0 Then Halt(1);
  If C=#10 Then Break;
  If Length(S)<80 Then S:=S+C;
 Until False;
 While (S<>'')And(S[1]=' ') Do Delete(S,1,1);
 While (S<>'')And(S[Length(S)]=' ') Do Delete(S,Length(S),1);
 Ask:=S;
End;

Function Yes(Prompt: String): Boolean;
Var S: String;
Begin
 Repeat
  S:=Ask(Prompt+' (oui/non) ');
 Until (S='oui')Or(S='non')Or(S='o')Or(S='n');
 Yes:=(S='oui')Or(S='o');
End;

Procedure PutW(Var B; O: Word; W: Word);
Begin
 MemW[Seg(B):Ofs(B)+O]:=W;
End;

Procedure PutL(Var B; O: Word; L: Longint);
Begin
 PutW(B,O,Word(L)); PutW(B,O+2,Word(L Shr 16));
End;

Procedure PutStr(O: Word; S: String);
{ chaine S dans le secteur Sec a partir de l'octet O }
Var I: Integer;
Begin
 For I:=1 To Length(S) Do Sec[O+I-1]:=Ord(S[I]);
End;

Procedure WriteAt(Fd: Integer; Sector: Longint; Var Buf; Count: Word);
{ Count octets a partir du secteur Sector du peripherique Fd }
Begin
 If SysLSeek(Fd,Sector*512,SEEK_SET)<0 Then Fatal('positionnement : '+SysErrorText(Errno));
 If SysWrite(Fd,Buf,Count)<>Count Then
  Fatal('ecriture du secteur '+IStr(Sector)+' : '+SysErrorText(Errno));
End;

Procedure ZeroSectors(Fd: Integer; Sector, Count: Longint);
Var N: Longint;
Begin
 While Count>0 Do Begin
  If Count>16 Then N:=16 Else N:=Count;
  WriteAt(Fd,Sector,Zero,N*512);
  Inc(Sector,N); Dec(Count,N);
 End;
End;

Function LoadFile(Path: String; Var Buf; Max: Word): Integer;
Var Fd,N: Integer;
Begin
 Fd:=SysOpen(Path,O_RDONLY,0);
 If Fd<0 Then Fatal(Path+' : '+SysErrorText(Errno));
 N:=SysRead(Fd,Buf,Max);
 SysClose(Fd);
 LoadFile:=N;
End;

Function OpenDev(Name: String): Integer;
Var Fd: Integer;
Begin
 Fd:=SysOpen('/dev/'+Name,O_RDWR,0);
 If Fd<0 Then Fatal('/dev/'+Name+' : '+SysErrorText(Errno));
 OpenDev:=Fd;
End;

{ --- 1. choix du disque ---------------------------------------------- }

Procedure ChooseDisk;
Var
 Names: Array[1..4] Of String[7];
 Infos: Array[1..4] Of TDiskInfo;
 N,K,Fd,E: Integer; M: TMountInfo; RootDev,S: String; L: Char;
Begin
 RootDev:='';
 If SysMountInfo(1,M) Then RootDev:=M.Special;
 N:=0;
 For L:='a' To 'b' Do Begin
  S:='hd'+L;
  If Copy(RootDev,1,3)=S Then Continue;   { disque d'amorce (CD-ROM emule) }
  Fd:=SysOpen('/dev/'+S,O_RDONLY,0);
  If Fd<0 Then Continue;
  If SysIoctl(Fd,DIOCGINFO,Infos[N+1])=0 Then Begin
   Inc(N); Names[N]:=S;
  End;
  SysClose(Fd);
 End;
 If N=0 Then Fatal('aucun disque dur disponible');
 WriteLn('Disques durs :');
 For K:=1 To N Do With Infos[K] Do
  WriteLn('  ',K,') /dev/',Names[K],' : ',Sectors Div 2048,' Mo (',Cyls,
    ' cylindres, ',Heads,' tetes, ',Spt,' secteurs par piste)');
 K:=1;
 If N>1 Then Begin
  S:=Ask('Disque ou installer LINUX-0 [1] : ');
  If S<>'' Then Val(S,K,E);
  If (K<1)Or(K>N) Then Fatal('choix invalide');
 End;
 Disk:=Names[K]; Info:=Infos[K];
End;

{ --- 2. partitions ----------------------------------------------------- }

Procedure CHS(LBA: Longint; O: Word);
Var C,H,S: Longint;
Begin
 C:=LBA Div (Longint(Info.Heads)*Info.Spt);
 H:=(LBA Div Info.Spt) Mod Info.Heads;
 S:=LBA Mod Info.Spt+1;
 If C>1023 Then Begin C:=1023; H:=Info.Heads-1; S:=Info.Spt End;
 Sec[O]:=H; Sec[O+1]:=S Or ((C Shr 2) And $C0); Sec[O+2]:=C And 255;
End;

Procedure Entry(N: Integer; Boot: Boolean; Typ: Byte; Start, Size: Longint);
Var O: Word;
Begin
 O:=446+N*16;
 If Boot Then Sec[O]:=$80 Else Sec[O]:=0;
 CHS(Start,O+1); Sec[O+4]:=Typ; CHS(Start+Size-1,O+5);
 PutL(Sec,O+8,Start); PutL(Sec,O+12,Size);
End;

Procedure ChooseLayout;
Var S: String; E: Integer;
Begin
 WriteLn('Type d''installation :');
 WriteLn('  1) UFS seul : amorce et racine UFS1 (recommande)');
 WriteLn('  2) FAT16 d''amorce (noyau, /boot) et racine UFS1');
 WriteLn('  3) FAT16 seul (sans permissions UNIX)');
 S:=Ask('Choix [1] : ');
 Layout:=1;
 If S<>'' Then Val(S,Layout,E);
 If (Layout<1)Or(Layout>3) Then Fatal('choix invalide');
End;

Procedure Partition;
Var Cyl,Cyls,BootCyl,SwapCyl,First: Longint; Fd,N: Integer;
Begin
 Cyl:=Longint(Info.Heads)*Info.Spt;
 Cyls:=Info.Cyls; If Cyls>1024 Then Cyls:=1024;   { limite du BIOS (CHS) }
 BootCyl:=0;
 If Layout=2 Then BootCyl:=(Longint(BOOTMB)*2048+Cyl-1) Div Cyl;
 SwapCyl:=(Longint(SWAPMB)*2048+Cyl-1) Div Cyl;
 If (Cyls-BootCyl-SwapCyl)*Cyl<Longint(MINUFSMB)*2048 Then SwapCyl:=0;
 { la premiere partition commence a la piste 1 (piste 0 : le MBR) }
 If BootCyl>0 Then First:=BootCyl*Cyl Else First:=Info.Spt;
 SwapSize:=SwapCyl*Cyl; SwapStart:=(Cyls-SwapCyl)*Cyl;
 UfsPart:=''; FatPart:='';
 Case Layout Of
  1: Begin UfsPart:='1'; UfsStart:=First; UfsSize:=SwapStart-First End;
  2: Begin
      FatPart:='1'; FatStart:=Info.Spt; FatSize:=BootCyl*Cyl-Info.Spt;
      UfsPart:='2'; UfsStart:=First; UfsSize:=SwapStart-First;
     End;
  3: Begin FatPart:='1'; FatStart:=First; FatSize:=SwapStart-First End;
 End;
 If ((UfsPart<>'')And(UfsSize<Longint(MINUFSMB)*2048)) Or
   ((Layout=3)And(FatSize<Longint(MINUFSMB)*2048)) Then
  Fatal('disque trop petit (au moins '+IStr(BOOTMB+MINUFSMB)+' Mo)');
 WriteLn('Partitions :');
 N:=0;
 Fd:=OpenDev(Disk);
 Move(MbrCode,Sec,446);
 FillChar(Sec[446],64,0);
 If FatPart<>'' Then Begin
  If Layout=2 Then
   WriteLn('  /dev/',Disk,FatPart,' : FAT16, amorce et noyau (/boot), ',FatSize Div 2048,' Mo')
  Else WriteLn('  /dev/',Disk,FatPart,' : FAT16, amorce et racine, ',FatSize Div 2048,' Mo');
  Entry(N,True,$04,FatStart,FatSize);
  If FatSize>=65536 Then Sec[446+N*16+4]:=$06;
  Inc(N);
 End;
 If UfsPart<>'' Then Begin
  If Layout=1 Then
   WriteLn('  /dev/',Disk,UfsPart,' : UFS1, amorce et racine, ',UfsSize Div 2048,' Mo')
  Else WriteLn('  /dev/',Disk,UfsPart,' : UFS1, racine, ',UfsSize Div 2048,' Mo');
  Entry(N,Layout=1,$A5,UfsStart,UfsSize);
  Inc(N);
 End;
 If SwapSize>0 Then Begin
  WriteLn('  /dev/',Disk,N+1,' : va-et-vient, ',SwapSize Div 2048,' Mo');
  Entry(N,False,$82,SwapStart,SwapSize);
 End;
 Sec[510]:=$55; Sec[511]:=$AA;
 WriteAt(Fd,0,Sec,512);
 SysSync;
 If SysIoctl(Fd,DIOCRESCAN,Sec)<0 Then
  Fatal('relecture de la table des partitions : '+SysErrorText(Errno));
 SysClose(Fd);
End;

Procedure Release;
{ demonte ce qui viendrait du disque cible (le noyau monte au demarrage une
  partition UFS trouvee sur /usr) }
Var I: Integer; M: TMountInfo;
Begin
 For I:=8 DownTo 2 Do
  If SysMountInfo(I,M) Then
   If Copy(M.Special,1,Length(Disk))=Disk Then
    If SysUmount(M.Dir)<0 Then
     Fatal(M.Dir+' (/dev/'+M.Special+') est occupe : '+SysErrorText(Errno));
End;

{ --- 3a. FAT16 ----------------------------------------------------------- }

Procedure FormatFat;
{ FAT16 sur /dev/<disque><FatPart> : grappes de 512 octets ou plus (au
  plus 65524 grappes), secteur d'amorce /mdec/bootsect }
Var Fd: Integer; Spf,Clus,Data,Spc: Longint; I: Integer;
Const Lab: String[11]='LINUX-0     ';
Begin
 Write('Formatage FAT16 de /dev/',Disk,FatPart,'...');
 Spc:=1;
 While FatSize Div Spc>65000 Do Spc:=Spc*2;
 Spf:=1;
 Repeat
  Data:=1+2*Spf+32;
  Clus:=(FatSize-Data) Div Spc;
  If (Clus+2)*2>Spf*512 Then Inc(Spf) Else Break;
 Until False;
 If (Clus<4085)Or(Clus>65524)Or(Spc>64) Then Fatal('taille de partition FAT16 invalide');
 Fd:=OpenDev(Disk+FatPart);
 Move(BootCode,Sec,512);
 PutStr(3,'LINUX-0  ');
 PutW(Sec,$0B,512); Sec[$0D]:=Spc; PutW(Sec,$0E,1); Sec[$10]:=2;
 PutW(Sec,$11,512);
 If FatSize<65536 Then Begin PutW(Sec,$13,FatSize); PutL(Sec,$20,0) End
 Else Begin PutW(Sec,$13,0); PutL(Sec,$20,FatSize) End;
 Sec[$15]:=$F8; PutW(Sec,$16,Spf); PutW(Sec,$18,Info.Spt);
 PutW(Sec,$1A,Info.Heads); PutL(Sec,$1C,FatStart);
 Sec[$24]:=$80;                 { le disque installe demarrera comme 80h }
 Sec[$25]:=0; Sec[$26]:=$29; PutL(Sec,$27,Now);
 For I:=1 To 11 Do Sec[$2B+I-1]:=Ord(Lab[I]);
 PutStr($36,'FAT16   ');
 Sec[510]:=$55; Sec[511]:=$AA;
 WriteAt(Fd,0,Sec,512);
 ZeroSectors(Fd,1,2*Spf+32);
 FillChar(Sec,512,0);
 Sec[0]:=$F8; Sec[1]:=$FF; Sec[2]:=$FF; Sec[3]:=$FF;
 WriteAt(Fd,1,Sec,512); WriteAt(Fd,1+Spf,Sec,512);
 { premiere entree du repertoire racine : le libelle du volume }
 FillChar(Sec,512,0);
 For I:=1 To 11 Do Sec[I-1]:=Ord(Lab[I]);
 Sec[11]:=$08;
 WriteAt(Fd,1+2*Spf,Sec,512);
 SysClose(Fd);
 WriteLn(' ',Clus,' grappes de ',Spc*512,' octets');
End;

{ --- 3b. UFS1 (newfs) ----------------------------------------------------- }

Procedure SetBit(Var B; O: Word; N: Longint);
Var P: Word;
Begin
 P:=Ofs(B)+O+Word(N Div 8);
 Mem[Seg(B):P]:=Mem[Seg(B):P] Or (1 Shl (N Mod 8));
End;

Function GetBit(Var B; O: Word; N: Longint): Boolean;
Begin
 GetBit:=Mem[Seg(B):Ofs(B)+O+Word(N Div 8)] And (1 Shl (N Mod 8))<>0;
End;

Procedure NewFs;
{ systeme de fichiers UFS1 vide sur /dev/<disque>2 : superbloc (et copies),
  groupes de cylindres (cartes des inodes, des fragments et des grappes,
  resumes), tables d'inodes, repertoire racine (inode 2) }
Var
 Fd,C,K,Run: Integer;
 Frags,Fpg,Ipg,Ncg,Dblk,CsSize,CsFrags,Root,Base,Ndblk,B,F: Longint;
 OIused,OFree,OClsum,OClus,ONext,CgSize: Word;
 Nb,Nf,Ni,Nd,Tot0,Tot1,Tot2,Tot3,Dsize: Longint;
 M,L: Integer;
 FrSum: Array[0..8] Of Longint;
 ClSum: Array[0..8] Of Longint;
Begin
 Write('Creation du systeme de fichiers UFS1 sur /dev/',Disk,UfsPart,'...');
 Frags:=UfsSize Div 2; Frags:=Frags-Frags Mod FRAG;
 If Frags<=MAXFPG Then Begin Ncg:=1; Fpg:=Frags End
 Else Begin
  Fpg:=MAXFPG; Ncg:=(Frags+Fpg-1) Div Fpg;
 End;
 { un inode pour 8 Ko, par blocs d'inodes }
 Ipg:=(Fpg*FSIZE Div 8192+INOPB-1) Div INOPB*INOPB;
 Dblk:=IBLKNO+(Ipg Div INOPB)*FRAG;
 { dernier groupe trop petit : abandonne }
 If (Ncg>1)And(Frags-(Ncg-1)*Fpg<Dblk+64) Then Begin
  Dec(Ncg); Frags:=Ncg*Fpg;
 End;
 If Ncg>64 Then Fatal('partition trop grande');
 CsSize:=((Ncg*16+FSIZE-1) Div FSIZE)*FSIZE; CsFrags:=CsSize Div FSIZE;
 Root:=Dblk+CsFrags;
 OIused:=174; OFree:=OIused+Ipg Div 8;
 OClsum:=((OFree+Fpg Div 8+3) Div 4)*4-4;
 OClus:=OClsum+9*4;
 ONext:=OClus+(Fpg Div FRAG+7) Div 8;
 CgSize:=((ONext+FSIZE-1) Div FSIZE)*FSIZE;
 If CgSize>BSIZE Then Fatal('groupe de cylindres trop grand');
 Fd:=OpenDev(Disk+UfsPart);
 FillChar(CsTab,SizeOf(CsTab),0);
 Tot0:=0; Tot1:=0; Tot2:=0; Tot3:=0;
 For C:=0 To Ncg-1 Do Begin
  Base:=C*Fpg;
  Ndblk:=Frags-Base; If Ndblk>Fpg Then Ndblk:=Fpg;
  FillChar(Big,SizeOf(Big),0);
  PutL(Big,4,$090255); PutL(Big,8,Now); PutL(Big,12,C);
  PutW(Big,16,1); PutW(Big,18,Ipg); PutL(Big,20,Ndblk);
  PutL(Big,44,Dblk);
  PutL(Big,84,168); PutL(Big,88,172); PutL(Big,92,OIused); PutL(Big,96,OFree);
  PutL(Big,100,ONext); PutL(Big,104,OClsum); PutL(Big,108,OClus);
  PutL(Big,112,Ndblk Div FRAG);
  { inodes 0, 1 (reserves) et 2 (racine) }
  If C=0 Then Begin SetBit(Big,OIused,0); SetBit(Big,OIused,1); SetBit(Big,OIused,2) End;
  { fragments libres : tout sauf les metadonnees du groupe (et, dans le
    groupe 0, le resume des groupes et le bloc de la racine) }
  For F:=0 To Ndblk-1 Do
   If (F>=Dblk) And Not ((C=0) And (F<=Root)) Then SetBit(Big,OFree,F);
  Nb:=0; Nf:=0; Run:=0;
  For K:=0 To 8 Do Begin FrSum[K]:=0; ClSum[K]:=0 End;
  For B:=0 To Ndblk Div FRAG-1 Do Begin
   M:=0;
   For K:=0 To FRAG-1 Do If GetBit(Big,OFree,B*FRAG+K) Then M:=M Or (1 Shl K);
   If M=255 Then Begin
    Inc(Nb); SetBit(Big,OClus,B); Inc(Run);
   End Else Begin
    If Run>0 Then Begin If Run>8 Then Run:=8; Inc(ClSum[Run]); Run:=0 End;
    L:=0;
    For K:=0 To FRAG Do
     If (K<FRAG) And (M And (1 Shl K)<>0) Then Inc(L)
     Else Begin
      If L>0 Then Begin Inc(FrSum[L]); Inc(Nf,L) End;
      L:=0;
     End;
   End;
  End;
  If Run>0 Then Begin If Run>8 Then Run:=8; Inc(ClSum[Run]) End;
  For K:=1 To 7 Do PutL(Big,52+K*4,FrSum[K]);
  For K:=1 To 8 Do PutL(Big,OClsum+K*4,ClSum[K]);
  If C=0 Then Nd:=1 Else Nd:=0;
  If C=0 Then Ni:=Ipg-3 Else Ni:=Ipg;
  PutL(Big,24,Nd); PutL(Big,28,Nb); PutL(Big,32,Ni); PutL(Big,36,Nf);
  PutL(CsTab,C*16,Nd); PutL(CsTab,C*16+4,Nb); PutL(CsTab,C*16+8,Ni);
  PutL(CsTab,C*16+12,Nf);
  Inc(Tot0,Nd); Inc(Tot1,Nb); Inc(Tot2,Ni); Inc(Tot3,Nf);
  WriteAt(Fd,(Base+CBLKNO)*2,Big,CgSize);
  { table des inodes a zero }
  ZeroSectors(Fd,(Base+IBLKNO)*2,(Dblk-IBLKNO)*2);
  Write('.');
 End;
 { resume des groupes }
 WriteAt(Fd,Dblk*2,CsTab,CsSize);
 { inode 2 : la racine }
 FillChar(Big,512,0);
 PutW(Big,2*128,$41ED); PutW(Big,2*128+2,2); PutL(Big,2*128+8,512);
 PutL(Big,2*128+16,Now); PutL(Big,2*128+24,Now); PutL(Big,2*128+32,Now);
 PutL(Big,2*128+40,Root); PutL(Big,2*128+104,2); PutL(Big,2*128+108,Now Xor $5A5A);
 WriteAt(Fd,IBLKNO*2,Big,512);
 { repertoire racine : "." et ".." }
 FillChar(Big,FSIZE,0);
 PutL(Big,0,2); PutW(Big,4,12); Big[6]:=4; Big[7]:=1; Big[8]:=Ord('.');
 PutL(Big,12,2); PutW(Big,16,500); Big[18]:=4; Big[19]:=2;
 Big[20]:=Ord('.'); Big[21]:=Ord('.');
 WriteAt(Fd,Root*2,Big,FSIZE);
 { superbloc }
 Dsize:=Frags-Ncg*Dblk-CsFrags;
 FillChar(Big,2048,0);
 PutL(Big,8,SBLKNO); PutL(Big,12,CBLKNO); PutL(Big,16,IBLKNO); PutL(Big,20,Dblk);
 PutL(Big,24,0); PutL(Big,28,-1); PutL(Big,32,Now); PutL(Big,36,Frags);
 PutL(Big,40,Dsize); PutL(Big,44,Ncg); PutL(Big,48,BSIZE); PutL(Big,52,FSIZE);
 PutL(Big,56,FRAG); PutL(Big,60,5); PutL(Big,68,60); PutL(Big,72,-BSIZE);
 PutL(Big,76,-FSIZE); PutL(Big,80,13); PutL(Big,84,10); PutL(Big,88,8);
 PutL(Big,92,2048); PutL(Big,96,3); PutL(Big,100,1); PutL(Big,104,2048);
 PutL(Big,116,BSIZE Div 4); PutL(Big,120,INOPB); PutL(Big,124,2);
 PutL(Big,132,Fpg*2); PutL(Big,136,1);
 PutL(Big,144,Now); PutL(Big,148,Now Xor $1D2E3F);
 PutL(Big,152,Dblk); PutL(Big,156,CsSize); PutL(Big,160,CgSize);
 PutL(Big,168,Fpg*2); PutL(Big,172,Fpg*2); PutL(Big,176,Ncg); PutL(Big,180,1);
 PutL(Big,184,Ipg); PutL(Big,188,Fpg);
 PutL(Big,192,Tot0); PutL(Big,196,Tot1); PutL(Big,200,Tot2); PutL(Big,204,Tot3);
 Big[209]:=1; Big[211]:=$80;           { propre; FS_FLAGS_UPDATED }
 PutL(Big,860,BSIZE); PutL(Big,1000,8192);
 PutL(Big,1008,Tot0); PutL(Big,1016,Tot1); PutL(Big,1024,Tot2); PutL(Big,1032,Tot3);
 PutL(Big,1072,Now); PutL(Big,1080,Frags); PutL(Big,1088,Dsize); PutL(Big,1096,Dblk);
 PutL(Big,1196,16384); PutL(Big,1200,64); PutL(Big,1316,8); PutL(Big,1320,60);
 PutL(Big,1324,2); PutL(Big,1328,16875519); PutL(Big,1332,16392);
 PutL(Big,1336,BSIZE-1); PutL(Big,1344,FSIZE-1);
 PutL(Big,1356,1); PutL(Big,1360,1); PutL(Big,1372,$011954);
 WriteAt(Fd,16,Big,2048);
 For C:=0 To Ncg-1 Do WriteAt(Fd,(Longint(C)*Fpg+SBLKNO)*2,Big,2048);
 If Layout=1 Then Begin
  { zone d'amorce (8 premiers Ko) : UFSBOOT, qui charge /unix }
  Move(UfsBoot,Big,8192);
  PutL(Big,$1C,UfsStart); Big[$24]:=$80;
  WriteAt(Fd,0,Big,8192);
 End;
 SysClose(Fd);
 SysSync;
 WriteLn(' ',Ncg,' groupe(s), ',Ipg*Ncg,' inodes, ',Tot1*BSIZE Div 1024,' Ko libres');
End;

{ --- 4. copie ---------------------------------------------------------- }

Procedure CopyFile(Src, Dst: String; Mode: Word);
Var I,O,N: Integer;
Begin
 I:=SysOpen(Src,O_RDONLY,0);
 If I<0 Then Fatal(Src+' : '+SysErrorText(Errno));
 O:=SysCreat(Dst,Mode);
 If O<0 Then Fatal(Dst+' : '+SysErrorText(Errno));
 Repeat
  N:=SysRead(I,RBuf,SizeOf(RBuf));
  If N>0 Then If SysWrite(O,RBuf,N)<>N Then Fatal(Dst+' : '+SysErrorText(Errno));
 Until N<=0;
 SysClose(I); SysClose(O);
End;

Function ReadBlock(Var Blk): Boolean;
{ bloc de 512 octets suivant du volume }
Begin
 ReadBlock:=False;
 If RPos>=RLen Then Begin
  RLen:=SysRead(VolFd,RBuf,SizeOf(RBuf));
  If RLen<512 Then Exit;
  RPos:=0;
 End;
 Move(RBuf[RPos],Blk,512); Inc(RPos,512);
 ReadBlock:=True;
End;

Function Octal(O, Len: Integer): Longint;
Var L: Longint; K: Integer;
Begin
 L:=0;
 For K:=O To O+Len-1 Do
  If Chr(Sec[K]) In ['0'..'7'] Then L:=L*8+Sec[K]-48;
 Octal:=L;
End;

Function Extract(Num: Integer; Var Last: Integer): Boolean;
{ extrait le volume tar ouvert sur VolFd dans /mnt; Last : dernier volume }
Var
 Name: String; K,Fd,E: Integer; Size,Left: Longint; Mode,Uid,Gid: Word;
 MTime: Longint; Typ: Char; N: Word;
 Lab: Array[0..511] Of Byte;
Begin
 Extract:=False; RLen:=0; RPos:=0;
 { etiquette "LINUX-0 numero total" }
 If Not ReadBlock(Sec) Then Exit;
 Name:=''; K:=0;
 While (K<100)And(Sec[K]<>0) Do Begin Name:=Name+Chr(Sec[K]); Inc(K) End;
 If Name<>'VOLUME' Then Exit;
 If Not ReadBlock(Lab) Then Exit;
 Name:=''; K:=0;
 While (K<40)And(Lab[K]>=32) Do Begin Name:=Name+Chr(Lab[K]); Inc(K) End;
 If Copy(Name,1,7)<>'LINUX-0 ' Then Exit;
 Delete(Name,1,7);
 Val(Copy(Name,1,Pos(' ',Name)-1),K,E);
 If K<>Num Then Begin
  WriteLn('C''est le volume ',K,', pas le volume ',Num,'.');
  Exit;
 End;
 Val(Copy(Name,Pos(' ',Name)+1,10),Last,E);
 Write('Volume ',Num,'/',Last,' ');
 Repeat
  If Not ReadBlock(Sec) Then Fatal('volume '+IStr(Num)+' incomplet');
  If Sec[0]=0 Then Break;
  Name:=''; K:=0;
  While (K<100)And(Sec[K]<>0) Do Begin Name:=Name+Chr(Sec[K]); Inc(K) End;
  While (Name<>'')And(Name[Length(Name)]='/') Do Delete(Name,Length(Name),1);
  If Copy(Name,1,2)='./' Then Delete(Name,1,2);
  Mode:=Octal(100,8); Uid:=Octal(108,8); Gid:=Octal(116,8);
  Size:=Octal(124,12); MTime:=Octal(136,12); Typ:=Chr(Sec[156]);
  Name:='/mnt/'+Name;
  If Typ='5' Then Begin
   SysMkdir(Name,$1FF);
   SysChown(Name,Uid,Gid); SysChmod(Name,Mode);
   Inc(Dirs);
  End Else Begin
   Fd:=SysCreat(Name,$180);
   If Fd<0 Then Fatal(Name+' : '+SysErrorText(Errno));
   Left:=Size;
   While Left>0 Do Begin
    If Not ReadBlock(Sec) Then Fatal('volume '+IStr(Num)+' incomplet');
    If Left>512 Then N:=512 Else N:=Left;
    If SysWrite(Fd,Sec,N)<>N Then Fatal(Name+' : '+SysErrorText(Errno));
    Dec(Left,N);
   End;
   SysClose(Fd);
   SysChown(Name,Uid,Gid); SysChmod(Name,Mode);
   SysUtime(Name,MTime,MTime);
   Inc(Files);
   If Files Mod 4=0 Then Write('.');
  End;
 Until False;
 WriteLn(' termine');
 Extract:=True;
End;

Procedure Volumes;
Var Num,Last: Integer; S: String;
Begin
 Num:=2; Last:=2;
 Repeat
  If FromCD Then Begin
   Str(Num,S);
   VolFd:=SysOpen('/dist/vol'+S+'.tar',O_RDONLY,0);
   If VolFd<0 Then Fatal('/dist/vol'+S+'.tar : '+SysErrorText(Errno));
   If Not Extract(Num,Last) Then Fatal('/dist/vol'+S+'.tar invalide');
   SysClose(VolFd);
  End Else Begin
   WriteLn;
   Ask('Inserez la disquette '+IStr(Num)+' et appuyez sur Entree. ');
   VolFd:=SysOpen('/dev/fd0',O_RDONLY,0);
   If VolFd<0 Then Fatal('/dev/fd0 : '+SysErrorText(Errno));
   { nouvelle disquette : le cache du lecteur est oublie }
   SysIoctl(VolFd,DIOCINVAL,Sec);
   If Not Extract(Num,Last) Then Begin
    WriteLn('Ce n''est pas la disquette ',Num,' de LINUX-0.');
    SysClose(VolFd);
    Continue;
   End;
   SysClose(VolFd);
  End;
  Inc(Num);
 Until Num>Last;
End;

{ --- programme principal ------------------------------------------------ }

Var
 St: TStat;

BEGIN
 Now:=SysTime;
 FillChar(Zero,SizeOf(Zero),0);
 WriteLn;
 WriteLn('Installation de LINUX-0 sur un disque dur');
 WriteLn('========================================');
 If GetEUid<>0 Then Fatal('reserve au super-utilisateur');
 FromCD:=(SysStat('/dist',St)=0)And(St.Mode And S_IFMT=S_IFDIR);
 If FromCD Then WriteLn('Source : CD-ROM (/dist)')
 Else WriteLn('Source : disquettes d''installation (/dev/fd0)');
 If LoadFile('/mdec/mbr',MbrCode,512)<>512 Then Fatal('/mdec/mbr invalide');
 If LoadFile('/mdec/bootsect',BootCode,512)<>512 Then Fatal('/mdec/bootsect invalide');
 If LoadFile('/mdec/ufsboot',UfsBoot,8192)<>8192 Then Fatal('/mdec/ufsboot invalide');
 If SysStat('/UNIX',St)<0 Then Fatal('/UNIX (noyau) introuvable');
 WriteLn;
 ChooseDisk;
 WriteLn;
 ChooseLayout;
 WriteLn;
 WriteLn('ATTENTION : tout le contenu de /dev/',Disk,' sera efface.');
 If Not Yes('Continuer ?') Then Fatal('annulee par l''utilisateur');
 WriteLn;
 Release;
 Partition;
 If FatPart<>'' Then FormatFat;
 If UfsPart<>'' Then NewFs;
 { montage du nouveau systeme sur /mnt (et de la partition d'amorce FAT16
   sur /mnt/boot), puis copie du noyau }
 If UfsPart<>'' Then Begin
  If SysMount('/dev/'+Disk+UfsPart,'/mnt',FS_UFS)<0 Then
   Fatal('montage de /dev/'+Disk+UfsPart+' : '+SysErrorText(Errno));
 End Else If SysMount('/dev/'+Disk+FatPart,'/mnt',FS_FAT)<0 Then
  Fatal('montage de /dev/'+Disk+FatPart+' : '+SysErrorText(Errno));
 If Layout=2 Then Begin
  SysMkdir('/mnt/boot',$1ED);
  If SysMount('/dev/'+Disk+FatPart,'/mnt/boot',FS_FAT)<0 Then
   Fatal('montage de /dev/'+Disk+FatPart+' : '+SysErrorText(Errno));
 End;
 Write('Copie du noyau...');
 Case Layout Of
  1: Begin CopyFile('/UNIX','/mnt/unix',$1A4); WriteLn(' /unix') End;
  2: Begin CopyFile('/UNIX','/mnt/boot/UNIX',$1A4); WriteLn(' /boot/unix') End;
  3: Begin CopyFile('/UNIX','/mnt/UNIX',$1A4); WriteLn(' /unix') End;
 End;
 Files:=0; Dirs:=0;
 Volumes;
 SysSync;
 If Layout=2 Then SysUmount('/mnt/boot');
 SysUmount('/mnt');
 SysSync;
 WriteLn;
 WriteLn('Installation terminee : ',Files,' fichiers, ',Dirs,' repertoires.');
 If FromCD Then WriteLn('Retirez le CD-ROM; LINUX-0 demarrera du disque dur.')
 Else WriteLn('Retirez la disquette; LINUX-0 demarrera du disque dur.');
 WriteLn('Connexion : root (sans mot de passe) ou invite (mot de passe invite).');
 If Yes('Redemarrer maintenant ?') Then SysReboot;
 If Not FromCD Then Begin
  Ask('Remettez la disquette 1 et appuyez sur Entree. ');
  VolFd:=SysOpen('/dev/fd0',O_RDONLY,0);
  If VolFd>=0 Then Begin SysIoctl(VolFd,DIOCINVAL,Sec); SysClose(VolFd) End;
 End;
END.
