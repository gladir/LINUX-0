{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2026
  @website(https://www.gladir.com/linux-0)
  @abstract(Target: Free Pascal)
  @description: Fabrique les images de disque amorcables de LINUX-0.

  Syntaxe :
   MKIMAGE FLOPPY image boot.bin repertoire [taille_Ko]
     Disquette FAT12 (1440 Ko par defaut, ou 720, 1200, 2880) : le secteur
     d'amorce boot.bin recoit le BPB, puis l'arborescence du repertoire est
     recopiee (noms en majuscules, format 8.3).
   MKIMAGE HD image mbr.bin boot.bin repertoire taille_FAT_Mo [ufs.img
           [taille_va_et_vient_Mo]]
     Disque dur (16 tetes, 63 secteurs par piste) : secteur de partition
     mbr.bin, partition 1 FAT16 active (amorcable, BOOTSECT.BIN) contenant
     l'arborescence du repertoire, puis, si ufs.img est donne, partition 2
     de type A5h (FreeBSD) contenant directement le systeme de fichiers UFS1
     (image produite par "makefs -t ffs" ou par un newfs de FreeBSD), et
     enfin, si une taille est donnee, partition 3 de type 82h : la zone de
     va-et-vient (swap) du noyau.
   MKIMAGE UFS image mbr.bin ufsboot.bin ufs.img [taille_va_et_vient_Mo]
     Disque dur amorce directement sur UFS : partition 1 active de type A5h
     contenant le systeme de fichiers UFS1, dont les 16 premiers secteurs
     (zone d'amorce, avant le superbloc) recoivent ufsboot.bin (8 Ko,
     KERNEL16UNIX/UFSBOOT.ASM, qui charge /unix), puis partition 2 de type 82h
     (va-et-vient), si une taille est donnee.
}

Program MKIMAGE;

{$MODE TP}{$H-}{$R-}{$I-}

Uses Dos;

Const
 MaxClusters = 65530;

Type
 TSector = Array[0..511] Of Byte;
 TFatTable = Array[0..MaxClusters+16] Of Word;
 PFatTable = ^TFatTable;
 TDirBuf = Array[0..65535] Of Byte;
 PDirBuf = ^TDirBuf;
 TBig = Array[0..4194303] Of Byte;
 PBig = ^TBig;

Var
 Img: File;
 PartLBA: Longint;            { debut de la partition FAT dans l'image }
 TotalSectors: Longint;       { secteurs de la partition FAT }
 SecPerClus, NumFats: Byte;
 Reserved, RootEntries, SecPerFat, SecPerTrack, Heads: Word;
 Media: Byte;
 Fat16: Boolean;
 FatLBA, RootLBA, DataLBA: Longint;
 ClusterCount: Longint;
 Fat: PFatTable;
 NextFree: Longint;
 Boot: TSector;
 FileCount, DirCount: Longint;

Procedure Die(S: String);
Begin
 WriteLn('MKIMAGE: ',S);
 Halt(1);
End;

Procedure PutWord(Var B; Ofs: Word; W: Word);
Var A: Array[0..511] Of Byte Absolute B;
Begin
 A[Ofs]:=Lo(W); A[Ofs+1]:=Hi(W);
End;

Procedure PutLong(Var B; Ofs: Word; L: Longint);
Var A: Array[0..511] Of Byte Absolute B;
Begin
 A[Ofs]:=L And 255; A[Ofs+1]:=(L Shr 8) And 255;
 A[Ofs+2]:=(L Shr 16) And 255; A[Ofs+3]:=(L Shr 24) And 255;
End;

Procedure WriteSectors(LBA: Longint; Var Buf; Count: Longint);
Var N: Longint;
Begin
 Seek(Img,LBA*512);
 BlockWrite(Img,Buf,Count*512);
 If IOResult<>0 Then Die('Ecriture impossible dans l''image');
 N:=0; If N<>0 Then;
End;

Procedure ZeroImage(Sectors: Longint);
Var Z: Array[0..32767] Of Byte; Done, Chunk: Longint;
Begin
 FillChar(Z,SizeOf(Z),0); Done:=0; Seek(Img,0);
 While Done<Sectors Do Begin
  Chunk:=Sectors-Done; If Chunk>64 Then Chunk:=64;
  BlockWrite(Img,Z,Chunk*512); Inc(Done,Chunk);
 End;
 If IOResult<>0 Then Die('Creation de l''image impossible');
End;

Procedure LoadSector(Name: String; Var S: TSector);
Var F: File; N: Longint;
Begin
 Assign(F,Name); Reset(F,1);
 If IOResult<>0 Then Die('Fichier introuvable: '+Name);
 FillChar(S,512,0); BlockRead(F,S,512,N); Close(F);
 If (N<>512) Or (S[510]<>$55) Or (S[511]<>$AA) Then
   Die('Secteur d''amorce invalide: '+Name);
End;

Function ClusterLBA(C: Longint): Longint;
Begin
 ClusterLBA:=PartLBA+DataLBA+(C-2)*SecPerClus;
End;

Function AllocChain(Bytes: Longint): Longint;
{ Alloue une chaine de clusters contigus pour Bytes octets (au moins un). }
Var N, I, First: Longint;
Begin
 N:=(Bytes+Longint(SecPerClus)*512-1) Div (Longint(SecPerClus)*512);
 If N=0 Then N:=1;
 If NextFree+N-1>ClusterCount+1 Then Die('Image pleine');
 First:=NextFree;
 For I:=0 To N-2 Do Fat^[First+I]:=First+I+1;
 Fat^[First+N-1]:=$FFFF;
 Inc(NextFree,N);
 AllocChain:=First;
End;

Procedure WriteChain(First: Longint; Var Data; Bytes: Longint);
Var Sectors: Longint; Pad: TSector; A: TBig Absolute Data;
Begin
 Sectors:=Bytes Div 512;
 If Sectors>0 Then WriteSectors(ClusterLBA(First),Data,Sectors);
 If Bytes Mod 512<>0 Then Begin
  FillChar(Pad,512,0); Move(A[Sectors*512],Pad,Bytes Mod 512);
  WriteSectors(ClusterLBA(First)+Sectors,Pad,1);
 End;
End;

Function FatName(S: String): String;
{ Nom 8.3 sur 11 caracteres, en majuscules. }
Var R, B, E: String; P, I: Integer;
Begin
 For I:=1 To Length(S) Do S[I]:=UpCase(S[I]);
 P:=0; For I:=Length(S) DownTo 2 Do If S[I]='.' Then Begin P:=I; Break End;
 If P>0 Then Begin B:=Copy(S,1,P-1); E:=Copy(S,P+1,3) End
        Else Begin B:=S; E:='' End;
 B:=Copy(B,1,8);
 While Length(B)<8 Do B:=B+' ';
 While Length(E)<3 Do E:=E+' ';
 R:=B+E;
 For I:=1 To 11 Do If R[I] In ['.','/','\','*','?',':','"','<','>','|','+',
   ',',';','=','[',']'] Then R[I]:='_';
 FatName:=R;
End;

Procedure MakeEntry(Var D: TDirBuf; At: Longint; Name: String; Attr: Byte;
  Cluster, Size: Longint);
Var I: Integer; T, Dt: Word;
Begin
 For I:=1 To 11 Do D[At+I-1]:=Ord(Name[I]);
 D[At+11]:=Attr;
 T:=0; Dt:=((2026-1980) Shl 9) Or (1 Shl 5) Or 1; { 2026-01-01 00:00 }
 D[At+22]:=Lo(T); D[At+23]:=Hi(T); D[At+24]:=Lo(Dt); D[At+25]:=Hi(Dt);
 D[At+16]:=Lo(Dt); D[At+17]:=Hi(Dt); D[At+18]:=Lo(Dt); D[At+19]:=Hi(Dt);
 D[At+26]:=Cluster And 255; D[At+27]:=(Cluster Shr 8) And 255;
 D[At+28]:=Size And 255; D[At+29]:=(Size Shr 8) And 255;
 D[At+30]:=(Size Shr 16) And 255; D[At+31]:=(Size Shr 24) And 255;
End;

Function CountEntries(Path: String): Longint;
Var R: SearchRec; N: Longint;
Begin
 N:=0;
 FindFirst(Path+'/*',AnyFile,R);
 While DosError=0 Do Begin
  If (R.Name<>'.') And (R.Name<>'..') Then Inc(N);
  FindNext(R);
 End;
 FindClose(R);
 CountEntries:=N;
End;

Var VolLabel: String[11];

Procedure AddDirectory(Path: String; Self, Parent: Longint; IsRoot: Boolean);
{ Recopie le repertoire hote Path. Self = premier cluster du repertoire
  (0 = racine), Parent = cluster du parent (0 = racine). }
Var
 R: SearchRec;
 D: PDirBuf;
 Used, Size, Cl, N, Got: Longint;
 F: File;
 Buf: PBig;
 Name: String;
 Names: Array[1..512] Of String[79];
 IsDir: Array[1..512] Of Boolean;
 Count, I, J: Integer;
 T: String[79]; TB: Boolean;
Begin
 New(D); FillChar(D^,SizeOf(D^),0);
 Used:=0;
 If Not IsRoot Then Begin
  MakeEntry(D^,0,'.          ',$10,Self,0);
  MakeEntry(D^,32,'..         ',$10,Parent,0);
  Used:=64;
 End Else Begin
  { nom de volume : premiere entree de la racine (comme dans le BPB) }
  MakeEntry(D^,0,VolLabel,$08,0,0);
  Used:=32;
 End;
 Count:=0;
 FindFirst(Path+'/*',AnyFile,R);
 While DosError=0 Do Begin
  If (R.Name<>'.') And (R.Name<>'..') Then Begin
   If Count=512 Then Die('Trop d''entrees dans '+Path);
   Inc(Count); Names[Count]:=R.Name; IsDir[Count]:=(R.Attr And Directory)<>0;
  End;
  FindNext(R);
 End;
 FindClose(R);
 { ordre stable : tri par nom }
 For I:=1 To Count-1 Do For J:=I+1 To Count Do
  If Names[J]<Names[I] Then Begin
   T:=Names[I]; Names[I]:=Names[J]; Names[J]:=T;
   TB:=IsDir[I]; IsDir[I]:=IsDir[J]; IsDir[J]:=TB;
  End;
 For I:=1 To Count Do Begin
  Name:=FatName(Names[I]);
  If IsDir[I] Then Begin
   N:=(CountEntries(Path+'/'+Names[I])+2)*32;
   Cl:=AllocChain(N);
   MakeEntry(D^,Used,Name,$10,Cl,0); Inc(Used,32);
   Inc(DirCount);
   If IsRoot Then AddDirectory(Path+'/'+Names[I],Cl,0,False)
             Else AddDirectory(Path+'/'+Names[I],Cl,Self,False);
  End Else Begin
   Assign(F,Path+'/'+Names[I]); Reset(F,1);
   If IOResult<>0 Then Die('Lecture impossible: '+Path+'/'+Names[I]);
   Size:=FileSize(F);
   If Size>SizeOf(TBig) Then Die('Fichier trop gros: '+Names[I]);
   GetMem(Buf,Size+512);
   BlockRead(F,Buf^,Size,Got); Close(F);
   If Got<>Size Then Die('Lecture incomplete: '+Names[I]);
   If Size>0 Then Begin
    Cl:=AllocChain(Size); WriteChain(Cl,Buf^,Size);
   End Else Cl:=0;
   FreeMem(Buf,Size+512);
   MakeEntry(D^,Used,Name,$20,Cl,Size); Inc(Used,32);
   Inc(FileCount);
  End;
 End;
 If IsRoot Then Begin
  If Used>Longint(RootEntries)*32 Then Die('Repertoire racine plein');
  WriteSectors(PartLBA+RootLBA,D^,Longint(RootEntries)*32 Div 512);
 End Else WriteChain(Self,D^,((Used+511) Div 512)*512);
 Dispose(D);
End;

Procedure WriteFats;
Var Sec: TSector; I, K, Off: Longint; V: Word; F, S: Longint;
Begin
 For F:=0 To NumFats-1 Do
  For S:=0 To SecPerFat-1 Do Begin
   FillChar(Sec,512,0);
   For I:=0 To 511 Do Begin
    Off:=S*512+I;
    If Fat16 Then Begin
     K:=Off Div 2;
     If K<=ClusterCount+1 Then Begin
      V:=Fat^[K]; If Off And 1=0 Then Sec[I]:=Lo(V) Else Sec[I]:=Hi(V);
     End;
    End Else Begin
     K:=(Off*2) Div 3;
     If K<=ClusterCount+1 Then Begin
      { octet Off de la FAT12 }
      If Off Mod 3=0 Then Sec[I]:=Fat^[Off Div 3*2] And 255
      Else If Off Mod 3=1 Then
        Sec[I]:=((Fat^[Off Div 3*2] Shr 8) And $0F) Or
                ((Fat^[Off Div 3*2+1] And $0F) Shl 4)
      Else Sec[I]:=(Fat^[Off Div 3*2+1] Shr 4) And 255;
     End;
    End;
   End;
   WriteSectors(PartLBA+FatLBA+F*SecPerFat+S,Sec,1);
  End;
End;

Procedure FormatFat(Dir: String; Label11: String);
Var I: Longint; FatBytes: Longint;
Begin
 { geometrie de la FAT }
 FatLBA:=Reserved;
 Repeat
  RootLBA:=FatLBA+Longint(NumFats)*SecPerFat;
  DataLBA:=RootLBA+Longint(RootEntries)*32 Div 512;
  ClusterCount:=(TotalSectors-DataLBA) Div SecPerClus;
  If Fat16 Then FatBytes:=(ClusterCount+2)*2 Else FatBytes:=((ClusterCount+2)*3+1) Div 2;
  If (FatBytes+511) Div 512>SecPerFat Then Inc(SecPerFat) Else Break;
 Until False;
 If ClusterCount>MaxClusters Then Die('Trop de clusters');
 New(Fat); FillChar(Fat^,SizeOf(Fat^),0);
 If Fat16 Then Begin Fat^[0]:=$FF00 Or Media; Fat^[1]:=$FFFF End
          Else Begin Fat^[0]:=$F00 Or Media; Fat^[1]:=$FFF End;
 NextFree:=2;
 { secteur d'amorce : BPB }
 PutWord(Boot,$0B,512); Boot[$0D]:=SecPerClus; PutWord(Boot,$0E,Reserved);
 Boot[$10]:=NumFats; PutWord(Boot,$11,RootEntries);
 If TotalSectors<65536 Then Begin PutWord(Boot,$13,TotalSectors);
   PutLong(Boot,$20,0) End
 Else Begin PutWord(Boot,$13,0); PutLong(Boot,$20,TotalSectors) End;
 Boot[$15]:=Media; PutWord(Boot,$16,SecPerFat); PutWord(Boot,$18,SecPerTrack);
 PutWord(Boot,$1A,Heads); PutLong(Boot,$1C,PartLBA);
 If PartLBA=0 Then Boot[$24]:=0 Else Boot[$24]:=$80;
 Boot[$26]:=$29;
 For I:=1 To 11 Do Boot[$2B+I-1]:=Ord(Label11[I]);
 If Fat16 Then Move('FAT16   ',Boot[$36],8) Else Move('FAT12   ',Boot[$36],8);
 WriteSectors(PartLBA,Boot,1);
 FileCount:=0; DirCount:=0;
 VolLabel:=Label11;
 AddDirectory(Dir,0,0,True);
 For I:=NextFree To ClusterCount+1 Do Fat^[I]:=0;
 If Not Fat16 Then For I:=0 To ClusterCount+1 Do Fat^[I]:=Fat^[I] And $FFF;
 WriteFats;
 WriteLn('  FAT',12+4*Ord(Fat16),': ',TotalSectors,' secteurs, ',ClusterCount,
   ' clusters de ',SecPerClus*512,' octets, ',FileCount,' fichiers, ',
   DirCount,' repertoires, ',NextFree-2,' clusters utilises');
 Dispose(Fat);
End;

Procedure MakeFloppy;
Var KB, Code: Integer;
Begin
 KB:=1440;
 If ParamCount>=5 Then Val(ParamStr(5),KB,Code);
 LoadSector(ParamStr(3),Boot);
 PartLBA:=0; Reserved:=1; NumFats:=2; Fat16:=False;
 Case KB Of
  720: Begin TotalSectors:=1440; SecPerClus:=2; RootEntries:=112;
         SecPerFat:=3; SecPerTrack:=9; Heads:=2; Media:=$F9 End;
  1200: Begin TotalSectors:=2400; SecPerClus:=1; RootEntries:=224;
         SecPerFat:=7; SecPerTrack:=15; Heads:=2; Media:=$F9 End;
  1440: Begin TotalSectors:=2880; SecPerClus:=1; RootEntries:=224;
         SecPerFat:=9; SecPerTrack:=18; Heads:=2; Media:=$F0 End;
  2880: Begin TotalSectors:=5760; SecPerClus:=2; RootEntries:=240;
         SecPerFat:=9; SecPerTrack:=36; Heads:=2; Media:=$F0 End;
  Else Die('Taille de disquette inconnue (720, 1200, 1440, 2880)');
 End;
 Assign(Img,ParamStr(2)); Rewrite(Img,1);
 If IOResult<>0 Then Die('Creation impossible: '+ParamStr(2));
 ZeroImage(TotalSectors);
 WriteLn('Disquette ',ParamStr(2),' (',KB,' Ko)');
 FormatFat(ParamStr(4),'LINUX-0     ');
 Close(Img);
End;

Procedure CHS(LBA: Longint; Var B: TSector; At: Word);
Var C, H, S: Longint;
Begin
 C:=LBA Div (16*63); H:=(LBA Div 63) Mod 16; S:=LBA Mod 63+1;
 If C>1023 Then Begin C:=1023; H:=15; S:=63 End;
 B[At]:=H; B[At+1]:=S Or ((C Shr 2) And $C0); B[At+2]:=C And 255;
End;

Procedure MakeHD;
Var
 Mbr: TSector;
 FatMB, Code: Integer;
 UfsName: String;
 Ufs: File;
 UfsSize, UfsLBA, UfsSectors, Total, Done, Chunk: Longint;
 SwapMB: Integer; SwapLBA, SwapSectors: Longint;
 Buf: Array[0..32767] Of Byte;
Begin
 LoadSector(ParamStr(3),Mbr);
 LoadSector(ParamStr(4),Boot);
 Val(ParamStr(6),FatMB,Code);
 If (Code<>0) Or (FatMB<8) Or (FatMB>128) Then
   Die('Taille de la partition FAT16 : 8 a 128 Mo');
 UfsName:=''; If ParamCount>=7 Then UfsName:=ParamStr(7);
 PartLBA:=63;
 TotalSectors:=Longint(FatMB)*2048-63;
 TotalSectors:=TotalSectors-(TotalSectors+63) Mod (16*63);
 If FatMB<16 Then SecPerClus:=1 Else If FatMB<=32 Then SecPerClus:=4
   Else If FatMB<=64 Then SecPerClus:=8 Else SecPerClus:=16;
 Reserved:=1; NumFats:=2; RootEntries:=512; SecPerFat:=1; SecPerTrack:=63;
 Heads:=16; Media:=$F8; Fat16:=True;
 UfsLBA:=PartLBA+TotalSectors; UfsSectors:=0; UfsSize:=0;
 If UfsName<>'' Then Begin
  Assign(Ufs,UfsName); Reset(Ufs,1);
  If IOResult<>0 Then Die('Image UFS introuvable: '+UfsName);
  UfsSize:=FileSize(Ufs);
  UfsSectors:=(UfsSize+511) Div 512;
  UfsSectors:=UfsSectors+(16*63-(UfsLBA+UfsSectors) Mod (16*63)) Mod (16*63);
 End;
 SwapMB:=0; SwapSectors:=0;
 If (UfsName<>'') And (ParamCount>=8) Then Begin
  Val(ParamStr(8),SwapMB,Code);
  If (Code<>0) Or (SwapMB<0) Or (SwapMB>32) Then
    Die('Taille de la zone de va-et-vient : 0 a 32 Mo');
 End;
 SwapLBA:=UfsLBA+UfsSectors;
 If SwapMB>0 Then Begin
  SwapSectors:=Longint(SwapMB)*2048;
  SwapSectors:=SwapSectors+(16*63-(SwapLBA+SwapSectors) Mod (16*63)) Mod (16*63);
 End;
 Total:=SwapLBA+SwapSectors;
 Assign(Img,ParamStr(2)); Rewrite(Img,1);
 If IOResult<>0 Then Die('Creation impossible: '+ParamStr(2));
 ZeroImage(Total);
 WriteLn('Disque dur ',ParamStr(2),' (',Total Div 2048,' Mo, ',
   Total Div (16*63),' cylindres, 16 tetes, 63 secteurs)');
 { table des partitions }
 FillChar(Mbr[446],64,0);
 Mbr[446]:=$80; CHS(PartLBA,Mbr,447);
 If TotalSectors<65536 Then Mbr[450]:=$04 Else Mbr[450]:=$06;
 CHS(PartLBA+TotalSectors-1,Mbr,451);
 PutLong(Mbr,454,PartLBA); PutLong(Mbr,458,TotalSectors);
 If UfsName<>'' Then Begin
  Mbr[462]:=$00; CHS(UfsLBA,Mbr,463); Mbr[466]:=$A5;
  CHS(UfsLBA+UfsSectors-1,Mbr,467);
  PutLong(Mbr,470,UfsLBA); PutLong(Mbr,474,UfsSectors);
 End;
 If SwapSectors>0 Then Begin
  Mbr[478]:=$00; CHS(SwapLBA,Mbr,479); Mbr[482]:=$82;
  CHS(SwapLBA+SwapSectors-1,Mbr,483);
  PutLong(Mbr,486,SwapLBA); PutLong(Mbr,490,SwapSectors);
 End;
 WriteSectors(0,Mbr,1);
 FormatFat(ParamStr(5),'LINUX-0 HD  ');
 If UfsName<>'' Then Begin
  Seek(Img,UfsLBA*512); Done:=0;
  While Done<UfsSize Do Begin
   Chunk:=UfsSize-Done; If Chunk>SizeOf(Buf) Then Chunk:=SizeOf(Buf);
   BlockRead(Ufs,Buf,Chunk); BlockWrite(Img,Buf,Chunk); Inc(Done,Chunk);
  End;
  Close(Ufs);
  If IOResult<>0 Then Die('Copie de l''image UFS impossible');
  WriteLn('  UFS : partition 2 (type A5h), ',UfsSectors,' secteurs a partir ',
    'du secteur ',UfsLBA);
 End;
 If SwapSectors>0 Then
  WriteLn('  va-et-vient : partition 3 (type 82h), ',SwapSectors,
    ' secteurs a partir du secteur ',SwapLBA);
 Close(Img);
End;

Procedure MakeUfsHD;
Var
 Mbr: TSector;
 Ufs, BootF: File;
 BootBlk: Array[0..8191] Of Byte;
 UfsSize, UfsLBA, UfsSectors, SwapLBA, SwapSectors, Total, Done, Chunk: Longint;
 SwapMB, Code: Integer;
 Buf: Array[0..32767] Of Byte;
Begin
 LoadSector(ParamStr(3),Mbr);
 Assign(BootF,ParamStr(4)); Reset(BootF,1);
 If (IOResult<>0) Or (FileSize(BootF)<>8192) Then Die('Amorce UFS de 8 Ko attendue: '+ParamStr(4));
 BlockRead(BootF,BootBlk,8192); Close(BootF);
 Assign(Ufs,ParamStr(5)); Reset(Ufs,1);
 If IOResult<>0 Then Die('Image UFS introuvable: '+ParamStr(5));
 UfsSize:=FileSize(Ufs);
 SwapMB:=0;
 If ParamCount>=6 Then Begin
  Val(ParamStr(6),SwapMB,Code);
  If (Code<>0) Or (SwapMB<0) Or (SwapMB>32) Then
    Die('Taille de la zone de va-et-vient : 0 a 32 Mo');
 End;
 UfsLBA:=63;
 UfsSectors:=(UfsSize+511) Div 512;
 UfsSectors:=UfsSectors+(16*63-(UfsLBA+UfsSectors) Mod (16*63)) Mod (16*63);
 SwapLBA:=UfsLBA+UfsSectors; SwapSectors:=0;
 If SwapMB>0 Then Begin
  SwapSectors:=Longint(SwapMB)*2048;
  SwapSectors:=SwapSectors+(16*63-(SwapLBA+SwapSectors) Mod (16*63)) Mod (16*63);
 End;
 Total:=SwapLBA+SwapSectors;
 Assign(Img,ParamStr(2)); Rewrite(Img,1);
 If IOResult<>0 Then Die('Creation impossible: '+ParamStr(2));
 ZeroImage(Total);
 WriteLn('Disque dur ',ParamStr(2),' (',Total Div 2048,' Mo, ',
   Total Div (16*63),' cylindres, 16 tetes, 63 secteurs), amorce UFS');
 FillChar(Mbr[446],64,0);
 Mbr[446]:=$80; CHS(UfsLBA,Mbr,447); Mbr[450]:=$A5;
 CHS(UfsLBA+UfsSectors-1,Mbr,451);
 PutLong(Mbr,454,UfsLBA); PutLong(Mbr,458,UfsSectors);
 If SwapSectors>0 Then Begin
  Mbr[462]:=$00; CHS(SwapLBA,Mbr,463); Mbr[466]:=$82;
  CHS(SwapLBA+SwapSectors-1,Mbr,467);
  PutLong(Mbr,470,SwapLBA); PutLong(Mbr,474,SwapSectors);
 End;
 WriteSectors(0,Mbr,1);
 Seek(Img,UfsLBA*512); Done:=0;
 While Done<UfsSize Do Begin
  Chunk:=UfsSize-Done; If Chunk>SizeOf(Buf) Then Chunk:=SizeOf(Buf);
  BlockRead(Ufs,Buf,Chunk); BlockWrite(Img,Buf,Chunk); Inc(Done,Chunk);
 End;
 Close(Ufs);
 { zone d'amorce de la partition : UFSBOOT (debut de partition, unite) }
 PutLong(BootBlk,$1C,UfsLBA); BootBlk[$24]:=$80;
 Seek(Img,UfsLBA*512); BlockWrite(Img,BootBlk,8192);
 If IOResult<>0 Then Die('Ecriture de l''image impossible');
 WriteLn('  UFS : partition 1 (type A5h, active), ',UfsSectors,
   ' secteurs a partir du secteur ',UfsLBA);
 If SwapSectors>0 Then
  WriteLn('  va-et-vient : partition 2 (type 82h), ',SwapSectors,
    ' secteurs a partir du secteur ',SwapLBA);
 Close(Img);
End;

Var Mode: String; I: Integer;
BEGIN
 If ParamCount<4 Then Begin
  WriteLn('MKIMAGE FLOPPY image boot.bin repertoire [taille_Ko]');
  WriteLn('MKIMAGE HD image mbr.bin boot.bin repertoire taille_FAT_Mo [ufs.img [swap_Mo]]');
  WriteLn('MKIMAGE UFS image mbr.bin ufsboot.bin ufs.img [swap_Mo]');
  Halt(1);
 End;
 Mode:=ParamStr(1); For I:=1 To Length(Mode) Do Mode[I]:=UpCase(Mode[I]);
 If Mode='FLOPPY' Then MakeFloppy
 Else If (Mode='HD') And (ParamCount>=6) Then MakeHD
 Else If (Mode='UFS') And (ParamCount>=5) Then MakeUfsHD
 Else Die('Mode inconnu ou arguments manquants');
END.
