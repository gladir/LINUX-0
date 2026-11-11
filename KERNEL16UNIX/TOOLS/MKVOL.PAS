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
  volumes. L'installateur /bin/install applique modes, proprietaires et
  dates.

  Les modes, proprietaires et dates ne sont pas lus dans le systeme de
  fichiers hote (le projet n'autorise que les unites DOS et CRT) mais dans
  un fichier liste, une ligne par fichier ou repertoire :
     type mode_octal uid gid date chemin
  (type d ou f, date en secondes depuis 1970, eventuellement fractionnaire),
  ce que produit BUILD.SH avec
     find . -mindepth 1 -printf '%y %m %U %G %T@ %P\n' | sort -k6

  Syntaxe :
   MKVOL arbre liste prefixe premier_numero
     -> prefixeN.TAR (volumes, pour le CD-ROM) et prefixeN.IMG (images de
        disquette de 1 474 560 octets), N = premier_numero, ...
}

Program MKVOL;

{$MODE OBJFPC}{$H+}{$I-}

Const
 FLOPPY = 1474560;
 { capacite d'un volume : etiquette (2 blocs) et fin d'archive (2 blocs) }
 CAP = FLOPPY - 4 * 512;

Type
 TEntry = Record
  Dir: Boolean;
  Name: String;               { chemin relatif a l'arbre }
  Mode, Uid, Gid: Longint;
  MTime: Int64;
  Size: Int64;                { place dans l'archive : en-tete + donnees }
  Vol: Integer;
 End;

Var
 Tree, Prefix, ListName: String;
 First, Code, NVol, K, V: Integer;
 Entries: Array of TEntry;
 NDirs: Integer;
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

{ --- liste des fichiers ---------------------------------------------------- }

Function Field(Var L: String): String;
{ premier mot de L (separe par des espaces), retire de L }
Var P: Integer;
Begin
 While (L <> '') And (L[1] = ' ') Do Delete(L, 1, 1);
 P := Pos(' ', L);
 If P = 0 Then P := Length(L) + 1;
 Result := Copy(L, 1, P - 1);
 Delete(L, 1, P);
End;

Function OctVal(S: String): Longint;
Var I: Integer;
Begin
 Result := 0;
 For I := 1 To Length(S) Do
  If S[I] In ['0'..'7'] Then Result := Result * 8 + Ord(S[I]) - 48
  Else Fail('mode octal invalide : ' + S);
End;

Function FileLen(Path: String): Int64;
Var F: File;
Begin
 Assign(F, Path);
 Reset(F, 1);
 If IOResult <> 0 Then Fail('fichier illisible : ' + Path);
 Result := FileSize(F);
 Close(F);
End;

Procedure ReadList;
{ repertoires d'abord (premier volume), puis les fichiers, dans l'ordre de
  la liste }
Var T: Text; L, Kind, M, U, G, D: String; E: TEntry; All: Array of TEntry;
    I, N, Dummy: Integer;
Begin
 Assign(T, ListName);
 Reset(T);
 If IOResult <> 0 Then Fail('liste illisible : ' + ListName);
 N := 0;
 While Not Eof(T) Do Begin
  ReadLn(T, L);
  If L = '' Then Continue;
  Kind := Field(L); M := Field(L); U := Field(L); G := Field(L);
  D := Field(L);
  If (Kind <> 'd') And (Kind <> 'f') Then
   Fail('type ni d ni f (lien ou fichier special ?) : ' + L);
  If Pos('.', D) > 0 Then D := Copy(D, 1, Pos('.', D) - 1);
  E.Dir := Kind = 'd'; E.Name := L;
  E.Mode := OctVal(M);
  Val(U, E.Uid, Dummy); Val(G, E.Gid, Dummy); Val(D, E.MTime, Dummy);
  E.Vol := 0;
  If E.Dir Then E.Size := 512
  Else E.Size := 512 + ((FileLen(Tree + '/' + L) + 511) Div 512) * 512;
  SetLength(All, N + 1); All[N] := E; Inc(N);
 End;
 Close(T);
 SetLength(Entries, N);
 NDirs := 0;
 For I := 0 To N - 1 Do If All[I].Dir Then Begin
  Entries[NDirs] := All[I]; Inc(NDirs);
 End;
 K := NDirs;
 For I := 0 To N - 1 Do If Not All[I].Dir Then Begin
  Entries[K] := All[I]; Inc(K);
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
Procedure Header(Name: String; Mode, Uid, Gid: Longint; MTime, Size: Int64;
  Kind: Char);
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

Procedure AddFile(Const E: TEntry; Var NFiles: Integer);
Var F: File; Data: Array of Byte;
Begin
 If E.Dir Then Begin
  Header(E.Name, E.Mode, E.Uid, E.Gid, E.MTime, 0, '5');
  Exit;
 End;
 Assign(F, Tree + '/' + E.Name);
 Reset(F, 1);
 If IOResult <> 0 Then Fail('fichier illisible : ' + E.Name);
 SetLength(Data, FileSize(F));
 If Length(Data) > 0 Then BlockRead(F, Data[0], Length(Data));
 Close(F);
 Header(E.Name, E.Mode, E.Uid, E.Gid, E.MTime, Length(Data), '0');
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
  If Entries[I].Vol = V Then AddFile(Entries[I], NF);
 FillChar(Z, SizeOf(Z), 0);
 Emit(Z, 1024);
 WriteOut(Prefix + IStr(Num) + '.TAR', BufLen);
 WriteOut(Prefix + IStr(Num) + '.IMG', FLOPPY);
 WriteLn('  volume ', Num, '/', Last, ' : ', NF, ' fichiers, ',
   BufLen Div 1024, ' Ko');
End;

BEGIN
 If ParamCount <> 4 Then Begin
  WriteLn('Syntaxe : MKVOL arbre liste prefixe premier_numero');
  Halt(2);
 End;
 Tree := ParamStr(1); ListName := ParamStr(2); Prefix := ParamStr(3);
 Val(ParamStr(4), First, Code);
 If Code <> 0 Then Fail('numero invalide : ' + ParamStr(4));
 ReadList;
 NVol := 1; Used := 0;
 For K := 0 To High(Entries) Do Begin
  If Entries[K].Size > CAP Then
   Fail('fichier trop gros pour une disquette : ' + Entries[K].Name);
  If Used + Entries[K].Size > CAP Then Begin Inc(NVol); Used := 0 End;
  Entries[K].Vol := NVol - 1;
  Inc(Used, Entries[K].Size);
 End;
 SetLength(Buf, FLOPPY);
 For V := 0 To NVol - 1 Do MakeVolume(First + V, First + NVol - 1, V);
 WriteLn(NVol, ' volume(s) de donnees : disquettes ', First, ' a ',
   First + NVol - 1);
END.
