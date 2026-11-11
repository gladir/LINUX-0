{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2026
  @website(https://www.gladir.com/linux-0)
  @abstract(Target: Free Pascal)
  @description: Fabrique les images de disque amorcables de LINUX-0 a partir
  d'un systeme de fichiers UFS1 deja construit (image produite par "makefs
  -t ffs -o version=1" ou par un newfs de FreeBSD). Il n'y a pas d'autre
  systeme de fichiers que UFS1.

  Syntaxe :
   MKIMAGE HD image mbr.bin ufsboot.bin ufs.img [taille_va_et_vient_Mo]
     Disque dur (16 tetes, 63 secteurs par piste) : secteur de partition
     mbr.bin, partition 1 active de type A5h contenant le systeme de
     fichiers UFS1, dont les 16 premiers secteurs (zone d'amorce, avant le
     superbloc) recoivent ufsboot.bin (8 Ko, KERNEL16UNIX/UFSBOOT.ASM, qui
     charge /unix), puis, si une taille non nulle est donnee, partition 2 de
     type 82h : la zone de va-et-vient (swap) du noyau.
   MKIMAGE FLOPPY image ufsboot.bin ufs.img [taille_Ko]
     Disquette (1440 Ko par defaut, ou 720, 1200, 2880) : le systeme de
     fichiers UFS1 occupe toute la disquette (pas de MBR : le secteur 0 est
     celui de l'amorce), ufsboot.bin remplace sa zone d'amorce. ufs.img
     doit tenir sur la disquette (makefs -s 1440k ou 2880k).
}

Program MKIMAGE;

{$MODE TP}{$H-}{$R-}{$I-}

Type
 TSector = Array[0..511] Of Byte;
 TBoot = Array[0..8191] Of Byte;

Var
 Img: File;

Procedure Die(S: String);
Begin
 WriteLn('MKIMAGE: ',S);
 Halt(1);
End;

Procedure PutLong(Var B; Ofs: Word; L: Longint);
Var A: Array[0..8191] Of Byte Absolute B;
Begin
 A[Ofs]:=L And 255; A[Ofs+1]:=(L Shr 8) And 255;
 A[Ofs+2]:=(L Shr 16) And 255; A[Ofs+3]:=(L Shr 24) And 255;
End;

Procedure WriteSectors(LBA: Longint; Var Buf; Count: Longint);
Begin
 Seek(Img,LBA*512);
 BlockWrite(Img,Buf,Count*512);
 If IOResult<>0 Then Die('Ecriture impossible dans l''image');
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

Procedure LoadBoot(Name: String; Var B: TBoot);
Var F: File; N: Longint;
Begin
 Assign(F,Name); Reset(F,1);
 If (IOResult<>0) Or (FileSize(F)<>8192) Then
   Die('Amorce UFS de 8 Ko attendue: '+Name);
 BlockRead(F,B,8192,N); Close(F);
 If (N<>8192) Or (B[510]<>$55) Or (B[511]<>$AA) Then
   Die('Amorce UFS invalide: '+Name);
End;

Procedure CopyFs(Var Ufs: File; Size: Longint);
{ recopie l'image UFS a la position courante de l'image }
Var Buf: Array[0..32767] Of Byte; Done, Chunk: Longint;
Begin
 Done:=0;
 While Done<Size Do Begin
  Chunk:=Size-Done; If Chunk>SizeOf(Buf) Then Chunk:=SizeOf(Buf);
  BlockRead(Ufs,Buf,Chunk); BlockWrite(Img,Buf,Chunk); Inc(Done,Chunk);
 End;
 Close(Ufs);
 If IOResult<>0 Then Die('Copie de l''image UFS impossible');
End;

Procedure CHS(LBA: Longint; Var B: TSector; At: Word);
Var C, H, S: Longint;
Begin
 C:=LBA Div (16*63); H:=(LBA Div 63) Mod 16; S:=LBA Mod 63+1;
 If C>1023 Then Begin C:=1023; H:=15; S:=63 End;
 B[At]:=H; B[At+1]:=S Or ((C Shr 2) And $C0); B[At+2]:=C And 255;
End;

Procedure Entry(Var B: TSector; N: Integer; Active: Boolean; Typ: Byte;
  Start, Size: Longint);
Var O: Word;
Begin
 O:=446+N*16;
 If Active Then B[O]:=$80 Else B[O]:=0;
 CHS(Start,B,O+1); B[O+4]:=Typ; CHS(Start+Size-1,B,O+5);
 PutLong(B,O+8,Start); PutLong(B,O+12,Size);
End;

Function Align(LBA, Sectors: Longint): Longint;
{ Sectors arrondi pour que la partition finisse sur une limite de cylindre }
Begin
 Align:=Sectors+(16*63-(LBA+Sectors) Mod (16*63)) Mod (16*63);
End;

Procedure MakeHD;
Var
 Mbr: TSector;
 BootBlk: TBoot;
 Ufs: File;
 UfsSize, UfsLBA, UfsSectors, SwapLBA, SwapSectors, Total: Longint;
 SwapMB, Code: Integer;
Begin
 LoadSector(ParamStr(3),Mbr);
 LoadBoot(ParamStr(4),BootBlk);
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
 UfsSectors:=Align(UfsLBA,(UfsSize+511) Div 512);
 SwapLBA:=UfsLBA+UfsSectors; SwapSectors:=0;
 If SwapMB>0 Then SwapSectors:=Align(SwapLBA,Longint(SwapMB)*2048);
 Total:=SwapLBA+SwapSectors;
 Assign(Img,ParamStr(2)); Rewrite(Img,1);
 If IOResult<>0 Then Die('Creation impossible: '+ParamStr(2));
 ZeroImage(Total);
 WriteLn('Disque dur ',ParamStr(2),' (',Total Div 2048,' Mo, ',
   Total Div (16*63),' cylindres, 16 tetes, 63 secteurs), amorce UFS');
 FillChar(Mbr[446],64,0);
 Entry(Mbr,0,True,$A5,UfsLBA,UfsSectors);
 If SwapSectors>0 Then Entry(Mbr,1,False,$82,SwapLBA,SwapSectors);
 WriteSectors(0,Mbr,1);
 Seek(Img,UfsLBA*512);
 CopyFs(Ufs,UfsSize);
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

Procedure MakeFloppy;
Var
 BootBlk: TBoot;
 Ufs: File;
 KB, Code: Integer;
 UfsSize, Total: Longint;
Begin
 KB:=1440;
 If ParamCount>=5 Then Val(ParamStr(5),KB,Code);
 If (KB<>720) And (KB<>1200) And (KB<>1440) And (KB<>2880) Then
   Die('Taille de disquette inconnue (720, 1200, 1440, 2880)');
 LoadBoot(ParamStr(3),BootBlk);
 Assign(Ufs,ParamStr(4)); Reset(Ufs,1);
 If IOResult<>0 Then Die('Image UFS introuvable: '+ParamStr(4));
 UfsSize:=FileSize(Ufs);
 Total:=Longint(KB)*2;
 If UfsSize>Total*512 Then Die('L''image UFS depasse la disquette');
 Assign(Img,ParamStr(2)); Rewrite(Img,1);
 If IOResult<>0 Then Die('Creation impossible: '+ParamStr(2));
 ZeroImage(Total);
 Seek(Img,0);
 CopyFs(Ufs,UfsSize);
 { le debut du systeme de fichiers est le secteur 0 (pas de MBR), l'unite
   est lue par UFSBOOT dans DL }
 PutLong(BootBlk,$1C,0); BootBlk[$24]:=0;
 Seek(Img,0); BlockWrite(Img,BootBlk,8192);
 If IOResult<>0 Then Die('Ecriture de l''image impossible');
 WriteLn('Disquette ',ParamStr(2),' (',KB,' Ko) : UFS1 sur toute la ',
   'disquette, amorce UFS, ',UfsSize Div 1024,' Ko d''image');
 Close(Img);
End;

Var Mode: String; I: Integer;
BEGIN
 If ParamCount<4 Then Begin
  WriteLn('MKIMAGE HD image mbr.bin ufsboot.bin ufs.img [swap_Mo]');
  WriteLn('MKIMAGE FLOPPY image ufsboot.bin ufs.img [taille_Ko]');
  Halt(1);
 End;
 Mode:=ParamStr(1); For I:=1 To Length(Mode) Do Mode[I]:=UpCase(Mode[I]);
 If (Mode='HD') And (ParamCount>=5) Then MakeHD
 Else If Mode='FLOPPY' Then MakeFloppy
 Else Die('Mode inconnu ou arguments manquants');
END.
