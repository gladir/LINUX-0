{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2026
  @website(https://www.gladir.com/linux-0)
  @abstract(Target: Free Pascal, Linux)
  @description: Fabrique un CD-ROM ISO 9660 amorcable (El Torito) de LINUX-0.
  L'image amorcable est une image de disque dur (MBR + partitions) en mode
  "emulation de disque dur" d'El Torito : le BIOS la presente comme le
  disque 80h (le premier disque dur reel devient 81h), le noyau LINUX-0 la
  lit donc par l'INT 13h comme un disque ordinaire, sans pilote de CD-ROM.
  Les autres fichiers donnes sont copies a la racine du CD (lisibles par
  n'importe quel systeme). La date est celle de SOURCE_DATE_EPOCH si cette
  variable est definie (construction reproductible), sinon l'heure courante.

  Syntaxe :
   MKISO cd.iso disque_amorce.img [fichier...]

  Disposition : 16 secteurs systeme, descripteur primaire (16), El Torito
  (17), terminateur (18), tables des chemins (19, 20), racine (21),
  catalogue d'amorce (22), puis les fichiers.
}

Program MKISO;

{$MODE OBJFPC}{$H+}

Uses BaseUnix;

Const
 SECTOR = 2048;

Type
 TBuf = Array of Byte;
 TFile = Record
  Name: String;               { nom ISO 9660 : NOM.EXT;1 }
  Lba: Longint;
  Data: TBuf;
 End;

Var
 Now: Int64;
 Files: Array of TFile;
 Root, Pvd, Cat: TBuf;
 Lba, Total, K, J, Code: Longint;
 F: File;
 Zero: Array[0..SECTOR - 1] Of Byte;

{ --- octets ----------------------------------------------------------------- }

Procedure Add(Var B: TBuf; Const S: String);
Var N: Longint;
Begin
 N := Length(B);
 SetLength(B, N + Length(S));
 If Length(S) > 0 Then Move(S[1], B[N], Length(S));
End;

Procedure AddB(Var B: TBuf; V: Byte);
Begin
 SetLength(B, Length(B) + 1);
 B[High(B)] := V;
End;

Procedure AddBuf(Var B: TBuf; Const C: TBuf);
Var N: Longint;
Begin
 N := Length(B);
 SetLength(B, N + Length(C));
 If Length(C) > 0 Then Move(C[0], B[N], Length(C));
End;

Procedure Le16(Var B: TBuf; V: Longint);
Begin AddB(B, V And $FF); AddB(B, (V Shr 8) And $FF) End;

Procedure Be16(Var B: TBuf; V: Longint);
Begin AddB(B, (V Shr 8) And $FF); AddB(B, V And $FF) End;

Procedure Le32(Var B: TBuf; V: Longint);
Begin Le16(B, V And $FFFF); Le16(B, (V Shr 16) And $FFFF) End;

Procedure Be32(Var B: TBuf; V: Longint);
Begin Be16(B, (V Shr 16) And $FFFF); Be16(B, V And $FFFF) End;

Procedure Both16(Var B: TBuf; V: Longint);
Begin Le16(B, V); Be16(B, V) End;

Procedure Both32(Var B: TBuf; V: Longint);
Begin Le32(B, V); Be32(B, V) End;

Procedure Fill(Var B: TBuf; Len: Longint; V: Byte);   { complete jusqu'a Len }
Begin
 While Length(B) < Len Do AddB(B, V);
End;

Function LJust(S: String; N: Integer): String;
Begin
 Result := S;
 While Length(Result) < N Do Result := Result + ' ';
End;

Function Rep(C: Char; N: Integer): String;
Begin
 Result := StringOfChar(C, N);
End;

{ --- dates (temps universel) ------------------------------------------------ }

Procedure Civil(T: Int64; Out Y, Mo, D, H, Mi, S: Longint);
Var Days, Era, Doe, Yoe, Doy, Mp: Int64;
Begin
 Days := T Div 86400;
 T := T Mod 86400;
 H := T Div 3600; Mi := (T Mod 3600) Div 60; S := T Mod 60;
 Days := Days + 719468;
 Era := Days Div 146097;
 Doe := Days - Era * 146097;
 Yoe := (Doe - Doe Div 1460 + Doe Div 36524 - Doe Div 146096) Div 365;
 Y := Yoe + Era * 400;
 Doy := Doe - (365 * Yoe + Yoe Div 4 - Yoe Div 100);
 Mp := (5 * Doy + 2) Div 153;
 D := Doy - (153 * Mp + 2) Div 5 + 1;
 If Mp < 10 Then Mo := Mp + 3 Else Mo := Mp - 9;
 If Mo <= 2 Then Inc(Y);
End;

Function Dig(V, N: Longint): String;
Begin
 Str(V, Result);
 While Length(Result) < N Do Result := '0' + Result;
End;

Procedure DTime(Var B: TBuf);        { date d'un enregistrement de repertoire }
Var Y, Mo, D, H, Mi, S: Longint;
Begin
 Civil(Now, Y, Mo, D, H, Mi, S);
 AddB(B, Y - 1900); AddB(B, Mo); AddB(B, D); AddB(B, H); AddB(B, Mi); AddB(B, S); AddB(B, 0);
End;

Function VTime: String;              { date d'un descripteur de volume }
Var Y, Mo, D, H, Mi, S: Longint;
Begin
 Civil(Now, Y, Mo, D, H, Mi, S);
 VTime := Dig(Y, 4) + Dig(Mo, 2) + Dig(D, 2) + Dig(H, 2) + Dig(Mi, 2) + Dig(S, 2) + '00' + #0;
End;

{ --- structures ISO 9660 ---------------------------------------------------- }

Function DirRec(L, Size: Longint; Name: String; Flags: Byte): TBuf;
Begin
 Result := Nil;
 AddB(Result, 0); AddB(Result, 0);
 Both32(Result, L); Both32(Result, Size);
 DTime(Result);
 AddB(Result, Flags); AddB(Result, 0); AddB(Result, 0);
 Both16(Result, 1);
 AddB(Result, Length(Name));
 Add(Result, Name);
 If Length(Result) Mod 2 <> 0 Then AddB(Result, 0);
 Result[0] := Length(Result);
End;

Function IsoName(Path: String): String;
Var I: Integer; Base, Ext: String;

 Function Keep(S: String; N: Integer): String;
 Var I: Integer;
 Begin
  Result := '';
  For I := 1 To Length(S) Do
   If S[I] In ['A'..'Z', '0'..'9', '_'] Then Result := Result + S[I]
   Else Result := Result + '_';
  Result := Copy(Result, 1, N);
 End;

Begin
 I := Length(Path);
 While (I > 0) And (Path[I] <> '/') Do Dec(I);
 Base := UpCase(Copy(Path, I + 1, Length(Path)));
 I := Pos('.', Base);
 If I > 0 Then Begin Ext := Copy(Base, I + 1, Length(Base)); Base := Copy(Base, 1, I - 1) End
 Else Ext := '';
 IsoName := Keep(Base, 8) + '.' + Keep(Ext, 3) + ';1';
End;

Function LoadFile(Path: String): TBuf;
Var F: File;
Begin
 Assign(F, Path);
 {$I-} Reset(F, 1); {$I+}
 If IOResult <> 0 Then Begin WriteLn(StdErr, 'MKISO : ', Path, ' introuvable'); Halt(1) End;
 SetLength(Result, FileSize(F));
 If Length(Result) > 0 Then BlockRead(F, Result[0], Length(Result));
 Close(F);
End;

Procedure Catalog;
Var Val, Init: TBuf; S, I: Longint;
Begin
 { entree de validation : plate-forme 80x86, somme de controle nulle }
 Val := Nil;
 AddB(Val, 1); AddB(Val, 0); Le16(Val, 0);
 Add(Val, 'LINUX-0'); Fill(Val, 28, 0);
 Le16(Val, 0); AddB(Val, $55); AddB(Val, $AA);
 S := 0;
 For I := 0 To 15 Do S := S + Val[2 * I] + Val[2 * I + 1] * 256;
 S := (-S) And $FFFF;
 Val[28] := S And $FF; Val[29] := S Shr 8;
 { entree initiale : amorcable, media 4 (emulation de disque dur),
   chargement a 07C0:0000, un secteur virtuel }
 Init := Nil;
 AddB(Init, $88); AddB(Init, 4); Le16(Init, 0); AddB(Init, 0); AddB(Init, 0);
 Le16(Init, 1); Le32(Init, Files[0].Lba);
 Fill(Init, 32, 0);
 Cat := Nil;
 AddBuf(Cat, Val); AddBuf(Cat, Init);
 Fill(Cat, SECTOR, 0);
End;

Procedure PrimaryDescriptor;
Var Pt: Longint;
Begin
 Pt := 10;                     { table des chemins : la seule racine }
 Pvd := Nil;
 AddB(Pvd, 1); Add(Pvd, 'CD001'); AddB(Pvd, 1); AddB(Pvd, 0);
 Add(Pvd, Rep(' ', 32));                    { systeme }
 Add(Pvd, LJust('LINUX0', 32));              { volume }
 Fill(Pvd, Length(Pvd) + 8, 0);
 Both32(Pvd, Total);
 Fill(Pvd, Length(Pvd) + 32, 0);
 Both16(Pvd, 1); Both16(Pvd, 1); Both16(Pvd, SECTOR);
 Both32(Pvd, Pt);
 Le32(Pvd, 19); Le32(Pvd, 0); Be32(Pvd, 20); Be32(Pvd, 0);
 AddBuf(Pvd, DirRec(21, SECTOR, #0, 2));
 Add(Pvd, Rep(' ', 128));
 Add(Pvd, LJust('GLADIR.COM', 128));
 Add(Pvd, LJust('LINUX0 BUILD.SH', 128));
 Add(Pvd, LJust('MKISO', 128));
 Add(Pvd, Rep(' ', 37 * 3));
 Add(Pvd, VTime); Add(Pvd, VTime);
 Add(Pvd, Rep('0', 16)); AddB(Pvd, 0);
 Add(Pvd, Rep('0', 16)); AddB(Pvd, 0);
 AddB(Pvd, 1); AddB(Pvd, 0);
 Fill(Pvd, SECTOR, 0);
End;

Function PathTable(Big: Boolean): TBuf;
Begin
 Result := Nil;
 AddB(Result, 1); AddB(Result, 0);
 If Big Then Begin Be32(Result, 21); Be16(Result, 1) End
 Else Begin Le32(Result, 21); Le16(Result, 1) End;
 AddB(Result, 0); AddB(Result, 0);
 Fill(Result, SECTOR, 0);
End;

Var
 Order: Array of Integer;
 Sec: TBuf;
 S: String;

BEGIN
 If ParamCount < 2 Then Begin
  WriteLn('Syntaxe : MKISO cd.iso disque_amorce.img [fichier...]');
  Halt(2);
 End;
 S := fpGetEnv('SOURCE_DATE_EPOCH');
 Code := 1;
 If S <> '' Then Val(S, Now, Code);
 If Code <> 0 Then Now := fpTime;
 SetLength(Files, ParamCount - 1);
 For K := 2 To ParamCount Do Begin
  Files[K - 2].Name := IsoName(ParamStr(K));
  Files[K - 2].Data := LoadFile(ParamStr(K));
 End;
 Lba := 23;
 For K := 0 To High(Files) Do Begin
  Files[K].Lba := Lba;
  Inc(Lba, (Length(Files[K].Data) + SECTOR - 1) Div SECTOR);
 End;
 Total := Lba;
 { repertoire racine : ".", "..", puis les fichiers par ordre alphabetique }
 SetLength(Order, Length(Files));
 For K := 0 To High(Files) Do Order[K] := K;
 For K := 1 To High(Order) Do Begin
  J := K;
  While (J > 0) And (Files[Order[J - 1]].Name > Files[Order[J]].Name) Do Begin
   Code := Order[J]; Order[J] := Order[J - 1]; Order[J - 1] := Code; Dec(J);
  End;
 End;
 Root := DirRec(21, SECTOR, #0, 2);
 AddBuf(Root, DirRec(21, SECTOR, #1, 2));
 For K := 0 To High(Order) Do
  With Files[Order[K]] Do AddBuf(Root, DirRec(Lba, Length(Data), Name, 0));
 If Length(Root) > SECTOR Then Begin WriteLn(StdErr, 'MKISO : trop de fichiers'); Halt(1) End;
 Fill(Root, SECTOR, 0);
 PrimaryDescriptor;
 Catalog;
 FillChar(Zero, SizeOf(Zero), 0);
 Assign(F, ParamStr(1));
 Rewrite(F, 1);
 For K := 0 To 15 Do BlockWrite(F, Zero, SECTOR);
 BlockWrite(F, Pvd[0], SECTOR);
 { volume d'amorce El Torito : catalogue au secteur 22 }
 Sec := Nil;
 AddB(Sec, 0); Add(Sec, 'CD001'); AddB(Sec, 1); Add(Sec, 'EL TORITO SPECIFICATION');
 Fill(Sec, 71, 0); Le32(Sec, 22); Fill(Sec, SECTOR, 0);
 BlockWrite(F, Sec[0], SECTOR);
 Sec := Nil;
 AddB(Sec, $FF); Add(Sec, 'CD001'); AddB(Sec, 1); Fill(Sec, SECTOR, 0);
 BlockWrite(F, Sec[0], SECTOR);
 Sec := PathTable(False); BlockWrite(F, Sec[0], SECTOR);
 Sec := PathTable(True); BlockWrite(F, Sec[0], SECTOR);
 BlockWrite(F, Root[0], SECTOR);
 BlockWrite(F, Cat[0], SECTOR);
 For K := 0 To High(Files) Do
  With Files[K] Do Begin
   If Length(Data) > 0 Then BlockWrite(F, Data[0], Length(Data));
   If Length(Data) Mod SECTOR <> 0 Then BlockWrite(F, Zero, SECTOR - Length(Data) Mod SECTOR);
  End;
 Close(F);
 WriteLn('CD-ROM ', ParamStr(1), ' : ', Total * 2, ' Ko, amorce El Torito (emulation de disque dur) ',
         Files[0].Name);
END.
