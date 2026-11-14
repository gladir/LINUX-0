{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2026
  @website(https://www.gladir.com/linux-0)
  @abstract(Target: LPC -K0840, 8086 mode reel)
  @description: Corps du chargeur (stage2) de KERNEL32. Il suit la tete
    STAGE2.ASM (0000:8000, 2 secteurs) et est compile par Linux Pascal :
    lpc -K0840 LOADER.PAS -> LOADER.SYS (image plate chargee en 0840:0000).
    Il lit le superbloc ext2 de la partition active, parcourt les
    repertoires (/boot/linux0), lit le fichier noyau (blocs directs,
    indirects simples, doubles et triples, blocs de 1 a 4 Ko, inodes de 128
    ou 256 octets, revisions 0 et 1, sans extents), charge ses segments
    PT_LOAD ELF32 a p_paddr (memoire haute par INT 15h AH=87h), recupere la
    carte memoire, construit la structure MULTIBOOT 1 a 0007E000h puis
    saute au noyau en mode protege plat (EAX=2BADB002h, EBX=structure).
    Les messages sortent a l'ecran (INT 10h) et sur COM1 (115200 bauds).
    Variables et appels de la tete : voir STAGE2.ASM. }

{$S-,R-,Q-,I-}
Program Loader;

Const
 { disposition de la tete (STAGE2.ASM) }
 HBootDrv=$8007; HPartIdx=$8008; HPartTyp=$8009; HPartLba=$800A;
 HEntry32=$8014; HMbiAddr=$8018; HMemLow=$8020; HMmapCnt=$8022;
 HMmapLen=$8024; HFbUpper=$8028; HA20Ok=$802C;
 { tampons en memoire basse : segment 6000h (64 Ko, sans passage de 64 Ko
   pour le DMA du BIOS) }
 BufSeg=$6000;
 DataBuf=$0000;   { bloc de donnees du fichier courant }
 DirBuf=$1000;    { bloc de repertoire }
 I1Buf=$2000;     { blocs d'indirection (niveaux 1, 2 et 3) }
 I2Buf=$3000;
 I3Buf=$4000;
 InoBuf=$5000;    { bloc de la table d'inodes }
 SbBuf=$6000;     { superbloc (1 Ko) }
 GdBuf=$7000;     { bloc des descripteurs de groupes }
 ZeroBuf=$8000;   { 4 Ko de zeros }
 TmpBuf=$9000;    { divers }
 { structure Multiboot : 7E00:0000 }
 MbiSeg=$7E00;
 MbiPhys=$7E000;
 CmdOfs=$80;
 MmapOfs=$200;
 Version='0.1';

Type
 Str255=String[255];

Var
 Drive:Byte;
 PartIdx:Byte;
 PartLba:LongInt;
 HasExt:Boolean;
 Spt,Heads:Word;
 Dap:Array[0..7] Of Word;
 G87:Array[0..47] Of Byte;
 { ext2 }
 BlkSize:Word;
 SecPerBlk:Word;
 Ppb:LongInt;
 InoSize:Word;
 Ipg,Bpg,FirstData,BlocksCount:LongInt;
 GdtBlk:LongInt;
 GdCur,InoCur,C1,C2,C3,DirCur:LongInt;
 { inode courant }
 IMode:Word;
 ISize,IFlags,IBlocks:LongInt;
 IBlk:Array[0..14] Of LongInt;
 Raw:Array[0..127] Of Byte;
 { noyau }
 KPath,CmdLine,LinkBuf:Str255;
 Entry:LongInt;
 LoadEnd:LongInt;
 MemTop:LongInt;
 Shown:LongInt;

{ ------------------------------------------------------------ console }

Procedure PutC(C:Char);
Var T:Word;
Begin
 Asm
  mov al,C
  mov ah,0Eh
  mov bx,7
  int 10h
 End;
 T:=0;
 While (T<$FFF) And ((Port[$3FD] And $20)=0) Do Inc(T);
 Port[$3F8]:=Ord(C);
End;

Procedure Print(S:Str255);
Var I:Word;
Begin
 For I:=1 To Length(S) Do PutC(S[I]);
End;

Procedure PrintLn(S:Str255);
Begin
 Print(S); PutC(Chr(13)); PutC(Chr(10));
End;

Function Num(L:LongInt):Str255;
Var S:Str255; I:Integer;
Begin
 Str(L,S); Num:=S;
End;

Function Hex(L:LongInt;N:Integer):Str255;
Const D:String[16]='0123456789ABCDEF';
Var S:Str255; I:Integer;
Begin
 S:='';
 For I:=N-1 DownTo 0 Do S:=S+D[((L Shr (I*4)) And 15)+1];
 Hex:=S;
End;

Procedure Die(S:Str255);
Begin
 PrintLn('');
 PrintLn('ERREUR : '+S);
 PrintLn('Systeme arrete.');
 Asm
 @l:
  sti
  hlt
  jmp @l
 End;
End;

{ ------------------------------------------------------------ disque }

Procedure DiskInit;
Var Ok:Byte; GCx,GDx:Word;
Begin
 HasExt:=False; Spt:=63; Heads:=255; GCx:=0; GDx:=0;
 Asm
  mov dl,Drive
  mov ah,41h
  mov bx,55AAh
  int 13h
  mov Ok,0
  jc @n
  cmp bx,0AA55h
  jne @n
  test cl,1
  jz @n
  mov Ok,1
 @n:
 End;
 If Ok=1 Then HasExt:=True;
 Asm
  mov dl,Drive
  mov ah,8
  int 13h
  jc @x
  mov GCx,cx
  mov GDx,dx
 @x:
 End;
 If (GCx And 63)<>0 Then Begin
  Spt:=GCx And 63; Heads:=(GDx Shr 8)+1;
 End;
End;

{ lit Cnt secteurs (Cnt <= 8) a partir du LBA dans Seg:Ofs ; 0 = succes }
Function RdOne(Lba:LongInt;Cnt,Sg,Of2:Word):Byte;
Var E:Byte; C,H,S:Word; Q:LongInt;
Begin
 If HasExt Then Begin
  FillChar(Dap,SizeOf(Dap),0);
  Dap[0]:=16; Dap[1]:=Cnt; Dap[2]:=Of2; Dap[3]:=Sg;
  Move(Lba,Dap[4],4);
  Asm
   mov dl,Drive
   mov ah,42h
   lea si,Dap
   int 13h
   mov E,ah
  End;
 End Else Begin
  Q:=Lba Div Spt;
  S:=Word(Lba-Q*Spt)+1;
  H:=Word(Q Mod Heads);
  C:=Word(Q Div Heads);
  Asm
   mov dl,Drive
   mov ax,C
   mov ch,al
   mov cl,ah
   mov ah,Byte Ptr S
   mov al,cl
   mov cl,6
   shl al,cl
   or al,ah
   mov cl,al
   mov dh,Byte Ptr H
   mov ax,Sg
   mov es,ax
   mov bx,Of2
   mov al,1
   mov ah,2
   int 13h
   mov E,ah
  End;
 End;
 RdOne:=E;
End;

Procedure ReadSec(Lba:LongInt;Cnt,Sg,Of2:Word);
Var I,Try:Integer; E:Byte;
Begin
 If HasExt Then Begin
  Try:=0;
  Repeat
   E:=RdOne(Lba,Cnt,Sg,Of2);
   If E<>0 Then Begin
    Inc(Try);
    Asm
     mov dl,Drive
     xor ax,ax
     int 13h
    End;
   End;
  Until (E=0) Or (Try>=4);
  If E<>0 Then Die('lecture disque (code '+Hex(E,2)+'h)');
 End Else
  For I:=0 To Cnt-1 Do Begin
   Try:=0;
   Repeat
    E:=RdOne(Lba+I,1,Sg,Of2+I*512);
    If E<>0 Then Begin
     Inc(Try);
     Asm
      mov dl,Drive
      xor ax,ax
      int 13h
     End;
    End;
   Until (E=0) Or (Try>=4);
   If E<>0 Then Die('lecture disque (code '+Hex(E,2)+'h)');
  End;
End;

{ lit le bloc ext2 B dans BufSeg:Ofs (0 = trou : des zeros) }
Procedure ReadBlock(B:LongInt;Ofs:Word);
Begin
 If B=0 Then Begin
  FillChar(Mem[BufSeg:Ofs],BlkSize,0); Exit;
 End;
 If (B<0) Or (B>=BlocksCount) Then Die('bloc ext2 hors du disque');
 ReadSec(PartLba+B*SecPerBlk,SecPerBlk,BufSeg,Ofs);
End;

{ ------------------------------------------------------------ memoire haute }

{ copie W mots de la memoire physique Src vers Dst (INT 15h AH=87h) }
Procedure Raw87(Src,Dst:LongInt;W:Word);
Var E:Byte; Lim:Word;
Begin
 FillChar(G87,SizeOf(G87),0);
 Lim:=W*2-1;
 G87[16]:=Lo(Lim); G87[17]:=Hi(Lim);
 G87[18]:=Src And $FF; G87[19]:=(Src Shr 8) And $FF;
 G87[20]:=(Src Shr 16) And $FF; G87[21]:=$93;
 G87[23]:=(Src Shr 24) And $FF;
 G87[24]:=Lo(Lim); G87[25]:=Hi(Lim);
 G87[26]:=Dst And $FF; G87[27]:=(Dst Shr 8) And $FF;
 G87[28]:=(Dst Shr 16) And $FF; G87[29]:=$93;
 G87[31]:=(Dst Shr 24) And $FF;
 Asm
  push ds
  pop es
  lea si,G87
  mov cx,W
  mov ah,87h
  int 15h
  mov E,ah
 End;
 If E<>0 Then Die('copie en memoire haute (INT 15h/87h code '+Hex(E,2)+'h)');
End;

{ ecrit N octets pris en memoire basse SrcSeg:SrcOfs a l'adresse Dst }
Procedure HiPut(Dst:LongInt;SrcSeg,SrcOfs,N:Word);
Var W:Word; Src:LongInt;
Begin
 If N=0 Then Exit;
 Src:=LongInt(SrcSeg)*16+SrcOfs;
 W:=N Shr 1;
 If W>0 Then Raw87(Src,Dst,W);
 If Odd(N) Then Begin
  { dernier octet : lecture-modification-ecriture du mot }
  Raw87(Dst+N-1,LongInt(BufSeg)*16+TmpBuf,1);
  Mem[BufSeg:TmpBuf]:=Mem[SrcSeg:SrcOfs+N-1];
  Raw87(LongInt(BufSeg)*16+TmpBuf,Dst+N-1,1);
 End;
End;

Procedure HiZero(Dst,N:LongInt);
Var C:Word;
Begin
 While N>0 Do Begin
  If N>4096 Then C:=4096 Else C:=Word(N);
  HiPut(Dst,BufSeg,ZeroBuf,C);
  Inc(Dst,C); Dec(N,C);
 End;
End;

{ ------------------------------------------------------------ ext2 }

Function Ind(Tbl:LongInt;Idx,Slot:Word;Var Cur:LongInt):LongInt;
Begin
 If Tbl=0 Then Begin Ind:=0; Exit; End;
 If Cur<>Tbl Then Begin ReadBlock(Tbl,Slot); Cur:=Tbl; End;
 Ind:=MemL[BufSeg:Slot+Idx*4];
End;

{ numero (physique) du bloc N du fichier courant }
Function Bmap(N:LongInt):LongInt;
Var X,Y:LongInt;
Begin
 If N<12 Then Begin Bmap:=IBlk[N]; Exit; End;
 Dec(N,12);
 If N<Ppb Then Begin
  Bmap:=Ind(IBlk[12],Word(N),I1Buf,C1); Exit;
 End;
 Dec(N,Ppb);
 If N<Ppb*Ppb Then Begin
  X:=Ind(IBlk[13],Word(N Div Ppb),I2Buf,C2);
  Bmap:=Ind(X,Word(N Mod Ppb),I1Buf,C1); Exit;
 End;
 Dec(N,Ppb*Ppb);
 X:=Ind(IBlk[14],Word(N Div (Ppb*Ppb)),I3Buf,C3);
 Y:=Ind(X,Word((N Div Ppb) Mod Ppb),I2Buf,C2);
 Bmap:=Ind(Y,Word(N Mod Ppb),I1Buf,C1);
End;

Procedure ReadInode(N:LongInt);
Var Grp,Idx,Tbl,Pos,Blk:LongInt; O:Word; I:Integer;
Begin
 If (N<1) Or (N>$7FFFFF) Then Die('numero d''inode invalide');
 Dec(N); Grp:=N Div Ipg; Idx:=N Mod Ipg;
 Blk:=GdtBlk+(Grp*32) Div BlkSize;
 If GdCur<>Blk Then Begin ReadBlock(Blk,GdBuf); GdCur:=Blk; End;
 Tbl:=MemL[BufSeg:GdBuf+Word((Grp*32) Mod BlkSize)+8];
 Pos:=Idx*InoSize;
 Blk:=Tbl+Pos Div BlkSize;
 If InoCur<>Blk Then Begin ReadBlock(Blk,InoBuf); InoCur:=Blk; End;
 O:=InoBuf+Word(Pos Mod BlkSize);
 Move(Mem[BufSeg:O],Raw,128);
 Move(Raw[0],IMode,2);
 Move(Raw[4],ISize,4);
 Move(Raw[28],IBlocks,4);
 Move(Raw[32],IFlags,4);
 Move(Raw[40],IBlk,60);
 If (IFlags And $80000)<>0 Then
  Die('fichier a extents (ext4) non supporte');
End;

{ octets du fichier courant [Off,Off+Len) -> memoire basse Seg:Ofs }
Procedure ReadFile(Off:LongInt;Len,Sg,Of2:Word);
Var Bo,Chunk:Word; B:LongInt;
Begin
 If Off+Len>ISize Then Die('lecture au-dela de la fin du fichier');
 While Len>0 Do Begin
  B:=Off Div BlkSize; Bo:=Word(Off Mod BlkSize);
  Chunk:=BlkSize-Bo; If Chunk>Len Then Chunk:=Len;
  ReadBlock(Bmap(B),DataBuf);
  Move(Mem[BufSeg:DataBuf+Bo],Mem[Sg:Of2],Chunk);
  Inc(Off,Chunk); Inc(Of2,Chunk); Dec(Len,Chunk);
 End;
End;

{ cherche Name dans le repertoire courant : numero d'inode, 0 si absent }
Function DirFind(Name:Str255):LongInt;
Var K,Nb,Blk:LongInt; P,RecLen:Word; NLen:Byte; I:Word; Ok:Boolean;
    Ino:LongInt;
Begin
 DirFind:=0;
 If (IMode And $F000)<>$4000 Then Exit;
 Nb:=(ISize+BlkSize-1) Div BlkSize;
 K:=0;
 While K<Nb Do Begin
  Blk:=Bmap(K);
  If Blk<>0 Then Begin
   If DirCur<>Blk Then Begin ReadBlock(Blk,DirBuf); DirCur:=Blk; End;
   P:=0;
   While P+8<=BlkSize Do Begin
    Ino:=MemL[BufSeg:DirBuf+P];
    RecLen:=MemW[BufSeg:DirBuf+P+4];
    NLen:=Mem[BufSeg:DirBuf+P+6];
    If (RecLen<8) Or ((RecLen And 3)<>0) Or (P+RecLen>BlkSize) Then P:=BlkSize
    Else Begin
     If (Ino<>0) And (NLen=Length(Name)) Then Begin
      Ok:=True;
      For I:=1 To NLen Do
       If Mem[BufSeg:DirBuf+P+7+I]<>Ord(Name[I]) Then Ok:=False;
      If Ok Then Begin DirFind:=Ino; Exit; End;
     End;
     Inc(P,RecLen);
    End;
   End;
  End;
  Inc(K);
 End;
End;

{ cible du lien symbolique courant }
Function ReadLink:Str255;
Begin
 If (ISize>255) Then Die('lien symbolique trop long');
 LinkBuf[0]:=Chr(ISize);
 If (IBlocks=0) And (ISize<60) Then Move(Raw[40],LinkBuf[1],ISize)
 Else ReadFile(0,Word(ISize),Seg(LinkBuf),Ofs(LinkBuf)+1);
 ReadLink:=LinkBuf;
End;

{ resout un chemin : le numero d'inode (inode courant charge), 0 si absent }
Function Resolve(Path:Str255):LongInt;
Var Cur,Nxt:LongInt; Name,Target:Str255; P,Links:Integer;
Begin
 Resolve:=0; Cur:=2; Links:=0;
 While True Do Begin
  While (Length(Path)>0) And (Path[1]='/') Do Delete(Path,1,1);
  ReadInode(Cur);
  If Path='' Then Begin Resolve:=Cur; Exit; End;
  P:=Pos('/',Path);
  If P=0 Then Begin Name:=Path; Path:=''; End
  Else Begin Name:=Copy(Path,1,P-1); Delete(Path,1,P-1); End;
  Nxt:=DirFind(Name);
  If Nxt=0 Then Exit;
  ReadInode(Nxt);
  If (IMode And $F000)=$A000 Then Begin
   Inc(Links); If Links>8 Then Exit;
   Target:=ReadLink;
   If Target='' Then Exit;
   If Target[1]='/' Then Cur:=2;
   If (Length(Target)+Length(Path))>250 Then Exit;
   Path:=Target+Path;
  End Else Cur:=Nxt;
 End;
End;

Procedure Mount;
Var Magic:Word; Rev,Inc2,Ro,I:LongInt; Sh:Word;
Begin
 ReadSec(PartLba+2,2,BufSeg,SbBuf);
 Magic:=MemW[BufSeg:SbBuf+56];
 If Magic<>$EF53 Then
  Die('pas de systeme de fichiers ext2 sur la partition active');
 Sh:=Word(MemL[BufSeg:SbBuf+24]);
 If Sh>2 Then Die('taille de bloc ext2 non supportee (> 4096)');
 BlkSize:=1024 Shl Sh; SecPerBlk:=BlkSize Shr 9;
 Ppb:=BlkSize Div 4;
 FirstData:=MemL[BufSeg:SbBuf+20];
 BlocksCount:=MemL[BufSeg:SbBuf+4];
 Bpg:=MemL[BufSeg:SbBuf+32];
 Ipg:=MemL[BufSeg:SbBuf+40];
 Rev:=MemL[BufSeg:SbBuf+76];
 InoSize:=128;
 If Rev>=1 Then Begin
  InoSize:=MemW[BufSeg:SbBuf+88];
  Inc2:=MemL[BufSeg:SbBuf+96];
  { FILETYPE (2) et FLEX_BG (200h) : lisibles ; le reste non }
  If (Inc2 And Not($202))<>0 Then
   Die('fonction ext2 incompatible non supportee ('+Hex(Inc2,8)+'h)');
 End;
 If (InoSize<128) Or (InoSize>BlkSize) Or ((InoSize And (InoSize-1))<>0) Then
  Die('taille d''inode ext2 invalide');
 If (Ipg=0) Or (Bpg=0) Then Die('superbloc ext2 invalide');
 GdtBlk:=FirstData+1;
 GdCur:=-1; InoCur:=-1; C1:=-1; C2:=-1; C3:=-1; DirCur:=-1;
End;

{ ------------------------------------------------------------ configuration }

Function Trim(S:Str255):Str255;
Begin
 While (Length(S)>0) And (S[Length(S)]<=' ') Do Dec(S[0]);
 While (Length(S)>0) And (S[1]<=' ') Do Delete(S,1,1);
 Trim:=S;
End;

Procedure ReadConfig;
Var Ino:LongInt; Off:LongInt; L,N:Word; Line:Str255; I:Word; C:Char;
    Done:Boolean;
Begin
 Ino:=Resolve('/boot/linux0.cfg');
 If Ino=0 Then Exit;
 If (IMode And $F000)<>$8000 Then Exit;
 If ISize>4000 Then Begin PrintLn('linux0.cfg trop gros : ignore'); Exit; End;
 N:=Word(ISize);
 ReadFile(0,N,BufSeg,TmpBuf);
 PrintLn('Configuration : /boot/linux0.cfg');
 Line:=''; I:=0;
 For I:=0 To N Do Begin
  If I<N Then C:=Chr(Mem[BufSeg:TmpBuf+I]) Else C:=Chr(10);
  If (C=Chr(10)) Or (C=Chr(13)) Then Begin
   Line:=Trim(Line);
   If Copy(Line,1,7)='kernel=' Then KPath:=Trim(Copy(Line,8,255))
   Else If Copy(Line,1,8)='cmdline=' Then CmdLine:=Trim(Copy(Line,9,255))
   Else If Line='chs=1' Then Begin
    HasExt:=False; PrintLn('Lecture en CHS imposee (chs=1)');
   End;
   Line:='';
  End Else If Length(Line)<255 Then Line:=Line+C;
 End;
End;

{ ------------------------------------------------------------ noyau ELF }

Function RdW(O:Word):Word;
Begin RdW:=MemW[BufSeg:TmpBuf+O]; End;

Function RdL(O:Word):LongInt;
Begin RdL:=MemL[BufSeg:TmpBuf+O]; End;

Procedure LoadElf;
Var Ino,PhOff,Fsz,Msz,Pa,Va,Off,Done:LongInt;
    PhNum,PhSz,I,Chunk,Bo:Word; B:LongInt; Seg:Integer; Found:Boolean;
    Tp:LongInt; Dst,Mx:LongInt;
Begin
 Ino:=Resolve(KPath);
 If Ino=0 Then Die('noyau '+KPath+' introuvable');
 If (IMode And $F000)<>$8000 Then Die(KPath+' n''est pas un fichier');
 Print('Noyau : '+KPath+' ('+Num(ISize)+' octets)');
 PrintLn('');
 If ISize<52 Then Die('fichier noyau trop court');
 ReadFile(0,52,BufSeg,TmpBuf);
 If (RdL(0)<>$464C457F) Or (Mem[BufSeg:TmpBuf+4]<>1) Or
    (Mem[BufSeg:TmpBuf+5]<>1) Then Die('le noyau n''est pas un ELF32');
 If (RdW(16)<>2) Or (RdW(18)<>3) Then
  Die('le noyau n''est pas un executable ELF32 i386');
 Entry:=RdL(24); PhOff:=RdL(28); PhSz:=RdW(42); PhNum:=RdW(44);
 If (PhSz<32) Or (PhNum=0) Or (PhNum>32) Then Die('en-tetes ELF invalides');
 Found:=False; LoadEnd:=0; Shown:=0;
 For I:=0 To PhNum-1 Do Begin
  ReadFile(PhOff+LongInt(I)*PhSz,32,BufSeg,TmpBuf);
  If RdL(0)=1 Then Begin
   Off:=RdL(4); Va:=RdL(8); Pa:=RdL(12); Fsz:=RdL(16); Msz:=RdL(20);
   If Msz<Fsz Then Msz:=Fsz;
   If Pa<0 Then Pa:=Pa-$C0000000;      { p_paddr = adresse virtuelle haute }
   If (Pa<$100000) Or (Pa+Msz>MemTop) Or (Pa+Msz<Pa) Then
    Die('segment du noyau hors memoire (paddr '+Hex(Pa,8)+'h, taille '+
        Hex(Msz,8)+'h)');
   If Pa+Msz>$1000000 Then
    Die('le noyau doit tenir sous 16 Mo (INT 15h/87h)');
   If Off+Fsz>ISize Then Die('segment ELF au-dela de la fin du fichier');
   Print('  segment '+Hex(Pa,8)+'h, '+Num(Fsz)+' octets');
   If Msz>Fsz Then Print(' (+ '+Num(Msz-Fsz)+' de zeros)');
   Print(' ');
   { entree virtuelle -> physique }
   If Not Found And (Entry>=Va) And (Entry<Va+Msz) Then Begin
    Entry:=Entry-Va+Pa; Found:=True;
   End;
   Done:=0; Dst:=Pa;
   While Done<Fsz Do Begin
    B:=(Off+Done) Div BlkSize; Bo:=Word((Off+Done) Mod BlkSize);
    Chunk:=BlkSize-Bo;
    If Fsz-Done<Chunk Then Chunk:=Word(Fsz-Done);
    ReadBlock(Bmap(B),DataBuf);
    HiPut(Dst,BufSeg,DataBuf+Bo,Chunk);
    Inc(Dst,Chunk); Inc(Done,Chunk);
    If Done-Shown>=65536 Then Begin PutC('.'); Shown:=Done; End;
   End;
   Shown:=0;
   If Msz>Fsz Then HiZero(Pa+Fsz,Msz-Fsz);
   PrintLn('');
   If Pa+Msz>LoadEnd Then LoadEnd:=Pa+Msz;
  End;
 End;
 If LoadEnd=0 Then Die('le noyau n''a aucun segment PT_LOAD');
 If (Not Found) And (Entry<0) Then Entry:=Entry-$C0000000;
 If (Entry<$100000) Or (Entry>=LoadEnd) Then
  Die('point d''entree du noyau invalide ('+Hex(Entry,8)+'h)');
End;

{ ------------------------------------------------------------ Multiboot }

Procedure BuildMbi;
Var I,Cnt,E,Low:Word; UpKb,Base,Len,Top,Typ:LongInt;
Begin
 FillChar(Mem[MbiSeg:0],$100,0);
 Low:=MemW[0:HMemLow];
 Cnt:=MemW[0:HMmapCnt];
 { memoire au-dessus de 1 Mo : entrees E820 de type 1 qui contiennent 1 Mo
   (plafonnee a 2 Go) }
 UpKb:=0;
 If Cnt>0 Then Begin
  E:=MmapOfs;
  For I:=1 To Cnt Do Begin
   Base:=MemL[MbiSeg:E+4]; Len:=MemL[MbiSeg:E+12];
   Typ:=MemL[MbiSeg:E+20];
   If (Typ=1) And (MemL[MbiSeg:E+8]=0) And (Base>=0) And
      (Base<=$100000) Then Begin
    If (MemL[MbiSeg:E+16]<>0) Or (Len<0) Then Top:=$7FFFFFFF
    Else Begin
     Top:=Base+Len; If Top<Base Then Top:=$7FFFFFFF;
    End;
    If Top>$100000 Then Begin
     Top:=(Top-$100000) Shr 10;
     If Top>UpKb Then UpKb:=Top;
    End;
   End;
   E:=E+Word(MemL[MbiSeg:E])+4;
  End;
 End Else UpKb:=MemL[0:HFbUpper];
 If UpKb>$1FF000 Then UpKb:=$1FF000;
 MemTop:=$100000+UpKb*1024;
 MemL[MbiSeg:0]:=$247;                  { mem, boot_device, cmdline,
                                          mmap, nom du chargeur }
 MemL[MbiSeg:4]:=Low;
 MemL[MbiSeg:8]:=UpKb;
 MemL[MbiSeg:12]:=(LongInt(Drive) Shl 24) Or (LongInt(PartIdx) Shl 16) Or
                  $FFFF;
 MemL[MbiSeg:16]:=MbiPhys+CmdOfs;
 If Cnt>0 Then Begin
  MemL[MbiSeg:44]:=MemL[0:HMmapLen];
  MemL[MbiSeg:48]:=MbiPhys+MmapOfs;
 End Else MemL[MbiSeg:0]:=$207;
 MemL[MbiSeg:64]:=MbiPhys+$60;
End;

Procedure PutCmdline;
Const Nm:String[7]='LINUX-0';
Var I:Word;
Begin
 For I:=1 To Length(CmdLine) Do Mem[MbiSeg:CmdOfs+I-1]:=Ord(CmdLine[I]);
 Mem[MbiSeg:CmdOfs+Length(CmdLine)]:=0;
 For I:=1 To 7 Do Mem[MbiSeg:$5F+I]:=Ord(Nm[I]);
 Mem[MbiSeg:$67]:=0;
End;

Procedure Go32;
Begin
 MemL[0:HEntry32]:=Entry;
 MemL[0:HMbiAddr]:=MbiPhys;
 Asm
  db 0EAh
  dw 8046h
  dw 0
 End;
End;

{ ------------------------------------------------------------ principal }

Begin
 Port[$3F9]:=0; Port[$3FB]:=$80; Port[$3F8]:=1; Port[$3F9]:=0;
 Port[$3FB]:=3; Port[$3FA]:=0; Port[$3FC]:=3;
 Drive:=Mem[0:HBootDrv]; PartIdx:=Mem[0:HPartIdx];
 PartLba:=MemL[0:HPartLba];
 PrintLn('LINUX-0 KERNEL32 : chargeur ext2 version '+Version);
 Asm
  db 9Ah
  dw 8040h
  dw 0
 End;
 If Mem[0:HA20Ok]=0 Then Die('impossible d''activer la ligne d''adresse A20');
 Asm
  db 9Ah
  dw 8043h
  dw 0
 End;
 FillChar(Mem[BufSeg:ZeroBuf],4096,0);
 BuildMbi;
 DiskInit;
 Print('Unite '+Hex(Drive,2)+'h, partition '+Num(PartIdx+1)+' (type '+
       Hex(Mem[0:HPartTyp],2)+'h) debut '+Num(PartLba));
 If HasExt Then PrintLn(', LBA') Else PrintLn(', CHS');
 PrintLn('Memoire : '+Num(MemW[0:HMemLow])+' Ko + '+
         Num(MemL[MbiSeg:8])+' Ko');
 Mount;
 PrintLn('ext2 : blocs de '+Num(BlkSize)+' octets, inodes de '+
         Num(InoSize)+' octets');
 KPath:='/boot/linux0';
 CmdLine:='root=/dev/hd'+Chr(97+(Drive And $7F))+Chr(49+PartIdx)+' ro';
 ReadConfig;
 LoadElf;
 PutCmdline;
 PrintLn('Ligne de commande : '+CmdLine);
 PrintLn('Entree du noyau en '+Hex(Entry,8)+'h : demarrage');
 Go32;
End.
