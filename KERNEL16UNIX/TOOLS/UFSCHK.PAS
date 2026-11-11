{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2026
  @website(https://www.gladir.com/linux-0)
  @abstract(Target: Free Pascal)
  @description: Verification de la coherence d'un systeme de fichiers UFS1
  (FreeBSD), a la maniere de fsck_ffs (passes 1, 2, 4 et 5), pour tester le
  pilote UFS du noyau LINUX-0 et l'installateur sur la machine hote.

  Syntaxe :
   UFSCHK image [debut_en_secteurs]
   UFSCHK --hd IMAGE/LINUX0-HD.IMG     (derniere partition de type A5h,
                                       A6h ou A9h de la table)

  Verifie : carte des fragments libres de chaque groupe de cylindres
  (fragments references par les inodes, regle de FFS pour le dernier bloc
  direct, blocs indirects), compteurs nbfree/nffree/nifree/ndir (groupe,
  table csum, superbloc 32 et 64 bits), resume frsum, carte et resume des
  grappes, carte des inodes, entrees de repertoires et nombres de liens.
  Code de sortie 1 si une erreur est trouvee.
}

Program UFSCHK;

{$MODE OBJFPC}{$H+}

Const
 MAXERR = 60;
 SBOFF = 8192;

Type
 TLongs = Array of Longint;
 TQuad = Array[0..3] Of Int64;

Var
 D: Array of Byte;             { la partition entiere }
 Base0: Int64;                 { debut de la partition dans le fichier }
 NErr: Longint;
 CBlkNo, IBlkNo, DBlkNo, Ncg, BSize, FSize, Frag: Longint;
 NIndir, InoPB, CsAddr, Ipg, Fpg, FsSize, Contig, CgSize: Longint;
 Used: TLongs;                 { fragment -> inode proprietaire (0 : libre) }
 Alloc: Array of Boolean;      { inode allouee (carte des inodes, mode <> 0) }
 Links: TLongs;                { entrees de repertoire vers chaque inode }

Function IStr(V: Int64): String;
Begin
 Str(V, Result);
End;

Function Oct(V: Longint): String;
Begin
 Result := '';
 Repeat
  Result := Chr(48 + V And 7) + Result;
  V := V Shr 3;
 Until V = 0;
End;

Procedure Err(S: String);
Begin
 Inc(NErr);
 If NErr <= MAXERR Then WriteLn('ERREUR ', S);
End;

{ --- acces aux octets ------------------------------------------------------ }

Function B8(O: Int64): Byte;
Begin
 If (O >= 0) And (O < Length(D)) Then B8 := D[O] Else B8 := 0;
End;

Function U16(O: Int64): Longint;
Begin
 U16 := B8(O) Or (B8(O + 1) Shl 8);
End;

Function S16(O: Int64): Longint;
Begin
 S16 := SmallInt(U16(O));
End;

Function S32(O: Int64): Longint;
Begin
 S32 := Longint(Longword(B8(O)) Or (Longword(B8(O + 1)) Shl 8) Or
                (Longword(B8(O + 2)) Shl 16) Or (Longword(B8(O + 3)) Shl 24));
End;

Function U32(O: Int64): Int64;
Begin
 U32 := Longword(S32(O));
End;

Function S64(O: Int64): Int64;
Begin
 S64 := Int64(U32(O)) Or (Int64(S32(O + 4)) Shl 32);
End;

Function SB(O: Longint): Longint;      { champ 32 bits du superbloc }
Begin
 SB := S32(SBOFF + O);
End;

Function CgOff(C: Longint): Int64;     { groupe de cylindres C }
Begin
 CgOff := (Int64(Fpg) * C + CBlkNo) * FSize;
End;

Function InoOff(N: Longint): Int64;    { inode N }
Var C: Longint;
Begin
 C := N Div Ipg;
 InoOff := (Int64(Fpg) * C + IBlkNo + ((N Mod Ipg) Div InoPB) * Frag) * FSize +
           (N Mod InoPB) * 128;
End;

Function Quad(A, B, C, E: Int64): TQuad;
Begin
 Quad[0] := A; Quad[1] := B; Quad[2] := C; Quad[3] := E;
End;

Function QStr(Const Q: Array Of Int64): String;
Var K: Integer;
Begin
 Result := '[';
 For K := 0 To High(Q) Do Begin
  If K > 0 Then Result := Result + ', ';
  Result := Result + IStr(Q[K]);
 End;
 Result := Result + ']';
End;

Function QEq(Const A, B: Array Of Int64): Boolean;
Var K: Integer;
Begin
 Result := Length(A) = Length(B);
 If Result Then
  For K := 0 To High(A) Do
   If A[K] <> B[K] Then Exit(False);
End;

{ --- chargement ------------------------------------------------------------ }

Procedure Load(Path: String; HD: Boolean; Start: Int64);
Var F: File; Mbr: Array[0..511] Of Byte; K, Typ: Integer; Size: Int64;
Begin
 Assign(F, Path);
 {$I-} Reset(F, 1); {$I+}
 If IOResult <> 0 Then Begin WriteLn('UFSCHK : ', Path, ' introuvable'); Halt(2) End;
 If HD Then Begin
  BlockRead(F, Mbr, 512);
  Start := -1;
  For K := 0 To 3 Do Begin
   Typ := Mbr[446 + 16 * K + 4];
   If (Typ = $A5) Or (Typ = $A6) Or (Typ = $A9) Then
    Start := Longword(Mbr[454 + 16 * K] Or (Mbr[455 + 16 * K] Shl 8) Or
             (Mbr[456 + 16 * K] Shl 16) Or (Longword(Mbr[457 + 16 * K]) Shl 24));
  End;
  If Start < 0 Then Begin WriteLn('aucune partition UFS'); Halt(1) End;
 End;
 Base0 := Start * 512;
 Size := FileSize(F) - Base0;
 If Size < SBOFF + 2048 Then Size := SBOFF + 2048;
 SetLength(D, Size);
 FillChar(D[0], Size, 0);
 Seek(F, Base0);
 BlockRead(F, D[0], FileSize(F) - Base0);
 Close(F);
End;

{ --- passe 1 : inodes allouees et fragments qu'elles occupent ------------- }

Procedure Mark(A, Cnt, Ino: Longint; What: String);
Var K, F: Longint;
Begin
 For K := 0 To Cnt - 1 Do Begin
  F := A + K;
  If (F < 0) Or (F >= Length(Used)) Then Begin
   Err('fragment ' + IStr(F) + ' (' + What + ' inode ' + IStr(Ino) + ') hors du systeme');
   Continue;
  End;
  If Used[F] <> 0 Then
   Err('fragment ' + IStr(F) + ' (' + What + ' inode ' + IStr(Ino) +
       ') deja utilise par inode ' + IStr(Used[F]));
  Used[F] := Ino;
 End;
End;

Procedure Pass1;
Var C, I, N, IOff, Mode, L, Cnt, K, K2: Longint;
    G, Di, Size, R, NBlk, NFr, Ind, Ind2, A, A1: Int64;
Begin
 For C := 0 To Ncg - 1 Do Begin
  G := CgOff(C);
  If S32(G + 4) <> $090255 Then Begin
   Err('groupe ' + IStr(C) + ' : signature invalide');
   Continue;
  End;
  IOff := S32(G + 92);
  For I := 0 To Ipg - 1 Do Begin
   N := C * Ipg + I;
   Mode := U16(InoOff(N));
   If B8(G + IOff + I Div 8) And (1 Shl (I Mod 8)) <> 0 Then Begin
    If N < 2 Then Continue;
    If Mode = 0 Then Begin
     Err('inode ' + IStr(N) + ' marque utilise mais libre (mode 0)');
     Continue;
    End;
    Alloc[N] := True;
   End Else If (N >= 2) And (Mode <> 0) Then
    Err('inode ' + IStr(N) + ' non marque mais mode ' + Oct(Mode));
  End;
 End;
 For N := 0 To High(Alloc) Do Begin
  If Not Alloc[N] Then Continue;
  Di := InoOff(N);
  Size := S64(Di + 8);
  NFr := 0;
  NBlk := (Size + BSize - 1) Div BSize;
  For L := 0 To 11 Do Begin
   A := S32(Di + 40 + 4 * L);
   If A = 0 Then Continue;
   If (L < NBlk - 1) Or (Size >= Int64(L + 1) * BSize) Then Cnt := Frag
   Else Begin
    R := Size - Int64(L) * BSize;
    If R > 0 Then Cnt := (R + FSize - 1) Div FSize Else Cnt := 0;
    If Cnt = 0 Then Begin
     Err('inode ' + IStr(N) + ' : bloc ' + IStr(L) + ' au-dela de la taille');
     Cnt := Frag;
    End;
   End;
   Mark(A, Cnt, N, 'direct');
   Inc(NFr, Cnt);
  End;
  Ind := S32(Di + 88);
  If Ind <> 0 Then Begin
   Mark(Ind, Frag, N, 'indirect');
   Inc(NFr, Frag);
   For K := 0 To NIndir - 1 Do Begin
    A := S32(Ind * FSize + 4 * K);
    If A <> 0 Then Begin Mark(A, Frag, N, 'donnee'); Inc(NFr, Frag) End;
   End;
  End;
  Ind2 := S32(Di + 92);
  If Ind2 <> 0 Then Begin
   Mark(Ind2, Frag, N, 'indirect double');
   Inc(NFr, Frag);
   For K := 0 To NIndir - 1 Do Begin
    A1 := S32(Ind2 * FSize + 4 * K);
    If A1 = 0 Then Continue;
    Mark(A1, Frag, N, 'indirect');
    Inc(NFr, Frag);
    For K2 := 0 To NIndir - 1 Do Begin
     A := S32(A1 * FSize + 4 * K2);
     If A <> 0 Then Begin Mark(A, Frag, N, 'donnee'); Inc(NFr, Frag) End;
    End;
   End;
  End;
  If S32(Di + 104) <> NFr * FSize Div 512 Then
   Err('inode ' + IStr(N) + ' : di_blocks=' + IStr(S32(Di + 104)) + ', attendu ' +
       IStr(NFr * FSize Div 512));
 End;
End;

{ --- passes 2 et 4 : repertoires et nombres de liens ---------------------- }

Procedure Pass2;
Var N, Ino, L: Longint; Di, Size, Base, A, Ch, P, Rl, Nl: Int64; Name: String; K: Integer;
Begin
 For N := 0 To High(Alloc) Do Begin
  If Not Alloc[N] Then Continue;
  Di := InoOff(N);
  If U16(Di) And $F000 <> $4000 Then Continue;
  Size := S64(Di + 8);
  Base := 0;
  While Base < Size Do Begin
   L := Base Div BSize;
   If L < 12 Then A := S32(Di + 40 + 4 * L) Else A := 0;
   If A = 0 Then Ch := -1 Else Ch := A * FSize + Base Mod BSize;
   P := 0;
   While P < 512 Do Begin
    If Ch < 0 Then Begin Ino := 0; Rl := 0; Nl := 0 End
    Else Begin
     Ino := S32(Ch + P); Rl := U16(Ch + P + 4); Nl := B8(Ch + P + 7);
    End;
    If (Rl < 8) Or (P + Rl > 512) Then Begin
     Err('repertoire ' + IStr(N) + ' : entree corrompue a ' + IStr(Base + P));
     Break;
    End;
    If Ino <> 0 Then Begin
     Name := '';
     For K := 0 To Nl - 1 Do Name := Name + Chr(B8(Ch + P + 8 + K));
     If (Ino < 0) Or (Ino > High(Alloc)) Or Not Alloc[Ino] Then
      Err('repertoire ' + IStr(N) + ' : "' + Name + '" -> inode ' + IStr(Longword(Ino)) + ' libre');
     If (Ino >= 0) And (Ino <= High(Links)) Then Inc(Links[Ino]);
    End;
    Inc(P, Rl);
   End;
   Inc(Base, 512);
  End;
 End;
 For N := 0 To High(Alloc) Do
  If Alloc[N] And (Links[N] <> S16(InoOff(N) + 2)) Then
   Err('inode ' + IStr(N) + ' : ' + IStr(S16(InoOff(N) + 2)) + ' lien(s) indiques, ' +
       IStr(Links[N]) + ' trouves');
End;

{ --- passe 5 : cartes et compteurs ---------------------------------------- }

Procedure Pass5;
Var C, B, K, F, NDBlk, FOff, IOff, Cbase, M, Run, L, CsSize: Longint;
    NFFree, NBFree, NIFree, NDir: Longint;
    G, Cs, COff, SOff: Int64;
    IsFree, InUse, Bit: Boolean;
    FrSum: Array[0..8] Of Int64;
    ClMap: Array of Boolean;
    Sums, Got, Fs, Want: Array of Int64;
    Tot: TQuad;
    Hdr: TQuad;
    N: Longint;

 Function IsMeta(F: Longint): Boolean;
 Begin
  IsMeta := (F >= Cbase) And (F < Cbase + DBlkNo);
  If (C = 0) And (F >= CsAddr) And (F < CsAddr + (CsSize + FSize - 1) Div FSize) Then
   IsMeta := True;
 End;

 Function Owner(F: Longint): String;
 Begin
  If (F < Length(Used)) And (Used[F] <> 0) Then Owner := 'inode ' + IStr(Used[F])
  Else Owner := 'meta';
 End;

Begin
 FillChar(Tot, SizeOf(Tot), 0);
 Cs := Int64(CsAddr) * FSize;
 CsSize := SB(156);
 For C := 0 To Ncg - 1 Do Begin
  G := CgOff(C);
  Cbase := Fpg * C;
  NDBlk := S32(G + 20);
  FOff := S32(G + 96);
  IOff := S32(G + 92);
  NFFree := 0; NBFree := 0;
  FillChar(FrSum, SizeOf(FrSum), 0);
  SetLength(ClMap, NDBlk Div Frag);
  For B := 0 To NDBlk Div Frag - 1 Do Begin
   M := 0;
   For K := 0 To Frag - 1 Do Begin
    F := Cbase + B * Frag + K;
    IsFree := B8(G + FOff + (B * Frag + K) Div 8) And (1 Shl ((B * Frag + K) Mod 8)) <> 0;
    InUse := ((F < Length(Used)) And (Used[F] <> 0)) Or IsMeta(F);
    If IsFree And InUse Then
     Err('groupe ' + IStr(C) + ' : fragment ' + IStr(F) + ' libre mais utilise (' + Owner(F) + ')');
    If Not IsFree And Not InUse Then
     Err('groupe ' + IStr(C) + ' : fragment ' + IStr(F) + ' perdu (ni libre ni utilise)');
    If IsFree Then M := M Or (1 Shl K);
   End;
   If M = (1 Shl Frag) - 1 Then Begin
    Inc(NBFree);
    ClMap[B] := True;
   End Else Begin
    ClMap[B] := False;
    L := 0;
    For K := 0 To Frag Do
     If (K < Frag) And (M And (1 Shl K) <> 0) Then Inc(L)
     Else Begin
      If L <> 0 Then Begin Inc(FrSum[L]); Inc(NFFree, L) End;
      L := 0;
     End;
   End;
  End;
  NIFree := 0;
  For K := 0 To Ipg - 1 Do
   If B8(G + IOff + K Div 8) And (1 Shl (K Mod 8)) = 0 Then Inc(NIFree);
  NDir := 0;
  For N := C * Ipg To (C + 1) * Ipg - 1 Do
   If Alloc[N] And (U16(InoOff(N)) And $F000 = $4000) Then Inc(NDir);
  Want := [NDir, NBFree, NIFree, NFFree];
  Hdr := Quad(S32(G + 24), S32(G + 28), S32(G + 32), S32(G + 36));
  If Not QEq(Hdr, Want) Then
   Err('groupe ' + IStr(C) + ' : compteurs ' + QStr(Hdr) + ', attendu ' + QStr(Want));
  Hdr := Quad(S32(Cs + C * 16), S32(Cs + C * 16 + 4), S32(Cs + C * 16 + 8), S32(Cs + C * 16 + 12));
  If Not QEq(Hdr, Want) Then
   Err('csum ' + IStr(C) + ' : ' + QStr(Hdr) + ', attendu ' + QStr(Want));
  SetLength(Fs, Frag - 1); SetLength(Got, Frag - 1);
  For K := 1 To Frag - 1 Do Begin Fs[K - 1] := S32(G + 52 + 4 * K); Got[K - 1] := FrSum[K] End;
  If Not QEq(Fs, Got) Then
   Err('groupe ' + IStr(C) + ' : frsum ' + QStr(Fs) + ', attendu ' + QStr(Got));
  If (S32(G + 112) <> 0) And (Contig > 0) Then Begin
   COff := S32(G + 108);
   SOff := S32(G + 104);
   SetLength(Sums, Contig + 1);
   For K := 0 To Contig Do Sums[K] := 0;
   Run := 0;
   For B := 0 To Length(ClMap) Do Begin
    If B < Length(ClMap) Then Begin
     Bit := B8(G + COff + B Div 8) And (1 Shl (B Mod 8)) <> 0;
     If Bit <> ClMap[B] Then
      Err('groupe ' + IStr(C) + ' : grappe ' + IStr(B) + ', carte ' + IStr(Ord(Bit)) +
          ', attendu ' + IStr(Ord(ClMap[B])));
    End;
    If (B < Length(ClMap)) And ClMap[B] Then Inc(Run)
    Else If Run <> 0 Then Begin
     If Run > Contig Then Inc(Sums[Contig]) Else Inc(Sums[Run]);
     Run := 0;
    End;
   End;
   SetLength(Got, Contig); SetLength(Fs, Contig);
   For K := 1 To Contig Do Begin Got[K - 1] := S32(G + SOff + 4 * K); Fs[K - 1] := Sums[K] End;
   If Not QEq(Got, Fs) Then
    Err('groupe ' + IStr(C) + ' : resume des grappes ' + QStr(Got) + ', attendu ' + QStr(Fs));
  End;
  For K := 0 To 3 Do Tot[K] := Tot[K] + Want[K];
 End;
 Hdr := Quad(SB(192), SB(196), SB(200), SB(204));
 If Not QEq(Hdr, Tot) Then
  Err('superbloc (32 bits) ' + QStr(Hdr) + ', attendu ' + QStr(Tot));
 Hdr := Quad(S64(SBOFF + 1008), S64(SBOFF + 1016), S64(SBOFF + 1024), S64(SBOFF + 1032));
 If Not QEq(Hdr, Tot) Then
  Err('superbloc (64 bits) ' + QStr(Hdr) + ', attendu ' + QStr(Tot));
End;

Var
 Start: Int64;
 Code: Integer;

BEGIN
 If ParamCount = 0 Then Begin
  WriteLn('Syntaxe : UFSCHK image [debut_en_secteurs]');
  WriteLn('          UFSCHK --hd disque.img');
  Halt(2);
 End;
 If ParamStr(1) = '--hd' Then Load(ParamStr(2), True, 0)
 Else Begin
  Start := 0;
  If ParamCount > 1 Then Val(ParamStr(2), Start, Code);
  Load(ParamStr(1), False, Start);
 End;
 NErr := 0;
 If SB(1372) <> $011954 Then Err('superbloc UFS1 absent')
 Else Begin
  CBlkNo := SB(12); IBlkNo := SB(16); DBlkNo := SB(20);
  Ncg := SB(44); BSize := SB(48); FSize := SB(52); Frag := SB(56);
  NIndir := SB(116); InoPB := SB(120); CsAddr := SB(152);
  Ipg := SB(184); Fpg := SB(188); FsSize := SB(36); CgSize := SB(160);
  Contig := SB(1316);
  If (Ncg <= 0) Or (Ipg <= 0) Or (Fpg <= 0) Or (FSize <= 0) Or (Frag <= 0) Or (Frag > 8) Or
     (InoPB <= 0) Then
   Err('superbloc UFS1 incoherent')
  Else Begin
   If FsSize < Ncg * Fpg Then SetLength(Used, Ncg * Fpg) Else SetLength(Used, FsSize);
   SetLength(Alloc, Ncg * Ipg);
   SetLength(Links, Ncg * Ipg);
   Pass1;
   Pass2;
   Pass5;
  End;
 End;
 If NErr > MAXERR Then WriteLn('... ', NErr - MAXERR, ' autres erreurs');
 WriteLn(NErr, ' erreur(s)');
 If NErr > 0 Then Halt(1);
END.
