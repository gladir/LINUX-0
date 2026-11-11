{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2026
  @website(https://www.gladir.com/linux-0)
  @abstract(Target: Free Pascal, Linux)
  @description: Decoupe une arborescence LINUX-0 en volumes d'installation au
  format tar (ustar), a la maniere des bandes de distribution de UNIX V7 :
  chaque volume tient sur une disquette de 1,44 Mo, sans systeme de fichiers
  (l'archive est ecrite directement a partir du secteur 0), et commence par
  le fichier VOLUME ("LINUX-0 numero total"). Les repertoires sont dans le
  premier volume de donnees; un fichier n'est jamais coupe entre deux
  volumes. Modes, proprietaires et dates sont ceux de l'arborescence
  (l'installateur /bin/install les applique).

  Syntaxe :
   MKVOL arbre prefixe premier_numero
     -> prefixeN.TAR (volumes, pour le CD-ROM) et prefixeN.IMG (images de
        disquette de 1 474 560 octets), N = premier_numero, ...
}

Program MKVOL;

{$MODE OBJFPC}{$H+}

Uses BaseUnix;

Const
 FLOPPY = 1474560;
 { capacite d'un volume : etiquette (2 blocs) et fin d'archive (2 blocs) }
 CAP = FLOPPY - 4 * 512;

Type
 TStrList = Array of String;
 TEntry = Record
  Dir: Boolean;
  Name: String;               { chemin relatif a l'arbre }
  Size: Int64;                { place dans l'archive : en-tete + donnees }
  Vol: Integer;
 End;

Var
 Tree, Prefix: String;
 First, Code, NVol, K, V: Integer;
 Dirs, Files: TStrList;
 Entries: Array of TEntry;
 Used: Int64;
 Buf: Array of Byte;
 BufLen: Longint;

Function IStr(V: Int64): String;
Begin
 Str(V, Result);
End;

Procedure Fail(S: String);
Begin
 WriteLn(StdErr, 'MKVOL : ', S);
 Halt(1);
End;

Procedure Push(Var A: TStrList; S: String);
Begin
 SetLength(A, Length(A) + 1);
 A[High(A)] := S;
End;

Procedure SortStrings(Var A: TStrList);
Var I, J: Integer; T: String;
Begin
 For I := 1 To High(A) Do Begin
  T := A[I]; J := I - 1;
  While (J >= 0) And (A[J] > T) Do Begin A[J + 1] := A[J]; Dec(J) End;
  A[J + 1] := T;
 End;
End;

Function Join(Rel, N: String): String;
Begin
 If Rel = '' Then Join := N Else Join := Rel + '/' + N;
End;

{ parcours en profondeur, dans l'ordre alphabetique (comme os.walk trie) }
Procedure Walk(Rel: String);
Var Dp: PDir; De: PDirent; N: String; St: Stat; Sub, Fl: TStrList; I: Integer;
Begin
 Dp := fpOpenDir(Tree + '/' + Rel);
 If Dp = Nil Then Fail('repertoire illisible : ' + Tree + '/' + Rel);
 SetLength(Sub, 0); SetLength(Fl, 0);
 Repeat
  De := fpReadDir(Dp^);
  If De = Nil Then Break;
  N := PChar(@De^.d_name[0]);
  If (N = '.') Or (N = '..') Then Continue;
  If fpLStat(Tree + '/' + Join(Rel, N), St) <> 0 Then Fail('stat : ' + Join(Rel, N));
  If fpS_ISDIR(St.st_mode) Then Push(Sub, N) Else Push(Fl, N);
 Until False;
 fpCloseDir(Dp^);
 SortStrings(Sub); SortStrings(Fl);
 For I := 0 To High(Fl) Do Push(Files, Join(Rel, Fl[I]));
 For I := 0 To High(Sub) Do Begin
  Push(Dirs, Join(Rel, Sub[I]));
  Walk(Join(Rel, Sub[I]));
 End;
End;

{ --- archive ---------------------------------------------------------------- }

Procedure Emit(Const Data; N: Longint);
Begin
 If BufLen + N > Length(Buf) Then Fail('volume trop gros');
 If N > 0 Then Move(Data, Buf[BufLen], N);
 Inc(BufLen, N);
End;

Procedure EmitPad;
Var Z: Array[0..511] Of Byte;
Begin
 FillChar(Z, SizeOf(Z), 0);
 If BufLen Mod 512 <> 0 Then Emit(Z, 512 - BufLen Mod 512);
End;

Function Octal(V: Int64; Digits: Integer): String;
Begin
 Result := '';
 While Length(Result) < Digits Do Begin
  Result := Chr(48 + (V And 7)) + Result;
  V := V Shr 3;
 End;
End;

{ en-tete ustar (POSIX.1-1988), comme le module tarfile de Python }
Procedure Header(Name: String; Mode, Uid, Gid: Longint; MTime, Size: Int64; Kind: Char);
Var H: Array[0..511] Of Byte; Sum, I: Longint;

 Procedure Put(O: Integer; S: String);
 Begin
  If Length(S) > 0 Then Move(S[1], H[O], Length(S));
 End;

Begin
 FillChar(H, SizeOf(H), 0);
 If Kind = '5' Then Name := Name + '/';
 If Length(Name) > 100 Then Fail('nom trop long : ' + Name);
 Put(0, Name);
 Put(100, Octal(Mode, 7));
 Put(108, Octal(Uid, 7));
 Put(116, Octal(Gid, 7));
 Put(124, Octal(Size, 11));
 Put(136, Octal(MTime, 11));
 Put(148, '        ');
 H[156] := Ord(Kind);
 Put(257, 'ustar'); Put(263, '00');
 Sum := 0;
 For I := 0 To 511 Do Inc(Sum, H[I]);
 Put(148, Octal(Sum, 6)); H[154] := 0; H[155] := 32;
 Emit(H, 512);
End;

Procedure AddFile(Rel: String; Var NFiles: Integer);
Var St: Stat; F: File; Data: Array of Byte;
Begin
 If fpLStat(Tree + '/' + Rel, St) <> 0 Then Fail('stat : ' + Rel);
 If fpS_ISDIR(St.st_mode) Then Begin
  Header(Rel, St.st_mode And &7777, St.st_uid, St.st_gid, St.st_mtime, 0, '5');
  Exit;
 End;
 Assign(F, Tree + '/' + Rel);
 Reset(F, 1);
 SetLength(Data, FileSize(F));
 If Length(Data) > 0 Then BlockRead(F, Data[0], Length(Data));
 Close(F);
 Header(Rel, St.st_mode And &7777, St.st_uid, St.st_gid, St.st_mtime, Length(Data), '0');
 If Length(Data) > 0 Then Emit(Data[0], Length(Data));
 EmitPad;
 Inc(NFiles);
End;

Procedure WriteOut(Path: String; Len: Longint);
Var F: File;
Begin
 Assign(F, Path);
 Rewrite(F, 1);
 BlockWrite(F, Buf[0], Len);
 Close(F);
End;

Procedure MakeVolume(Num, Last, V: Integer);
Var Lbl: String; I, NF: Integer; Z: Array[0..1023] Of Byte;
Begin
 BufLen := 0;
 FillChar(Buf[0], Length(Buf), 0);
 Lbl := 'LINUX-0 ' + IStr(Num) + ' ' + IStr(Last) + #10;
 Header('VOLUME', &644, 0, 0, 0, Length(Lbl), '0');
 Emit(Lbl[1], Length(Lbl));
 EmitPad;
 NF := 0;
 For I := 0 To High(Entries) Do
  If Entries[I].Vol = V Then AddFile(Entries[I].Name, NF);
 FillChar(Z, SizeOf(Z), 0);
 Emit(Z, 1024);
 WriteOut(Prefix + IStr(Num) + '.TAR', BufLen);
 WriteOut(Prefix + IStr(Num) + '.IMG', FLOPPY);
 WriteLn('  volume ', Num, '/', Last, ' : ', NF, ' fichiers, ', BufLen Div 1024, ' Ko');
End;

Var St: Stat;

BEGIN
 If ParamCount <> 3 Then Begin
  WriteLn('Syntaxe : MKVOL arbre prefixe premier_numero');
  Halt(2);
 End;
 Tree := ParamStr(1); Prefix := ParamStr(2);
 Val(ParamStr(3), First, Code);
 If Code <> 0 Then Fail('numero invalide : ' + ParamStr(3));
 Walk('');
 { repertoires d'abord (premier volume), puis les fichiers }
 SetLength(Entries, Length(Dirs) + Length(Files));
 For K := 0 To High(Dirs) Do Begin
  Entries[K].Dir := True; Entries[K].Name := Dirs[K]; Entries[K].Size := 512;
 End;
 For K := 0 To High(Files) Do
  With Entries[Length(Dirs) + K] Do Begin
   Dir := False; Name := Files[K];
   If fpStat(Tree + '/' + Name, St) <> 0 Then Fail('stat : ' + Name);
   Size := 512 + ((St.st_size + 511) Div 512) * 512;
  End;
 NVol := 1; Used := 0;
 For K := 0 To High(Entries) Do Begin
  If Entries[K].Size > CAP Then Fail('fichier trop gros pour une disquette : ' + Entries[K].Name);
  If Used + Entries[K].Size > CAP Then Begin Inc(NVol); Used := 0 End;
  Entries[K].Vol := NVol - 1;
  Inc(Used, Entries[K].Size);
 End;
 SetLength(Buf, FLOPPY);
 For V := 0 To NVol - 1 Do MakeVolume(First + V, First + NVol - 1, V);
 WriteLn(NVol, ' volume(s) de donnees : disquettes ', First, ' a ', First + NVol - 1);
END.
