{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2026
  @website(https://www.gladir.com/linux-0)
  @abstract(Target: LPC -3X)
  @description: df, blkid, lsblk, findmnt (un seul programme, le nom lu dans
      argv[0]).
    df [-hHkmPTiaB] [-t type] [-x type] [fichier...] : espace libre des
      systemes de fichiers montes (appel statfs).
    blkid [-s TAG] [-o value|full|export] [-t NOM=VALEUR] [-L nom] [-U uuid]
      [peripherique...] : type, nom et UUID lus dans le superbloc (ext2/3/4,
      FAT, iso9660, minix, cramfs, romfs, swap).
    lsblk [-flnab] [-o COLONNES] : peripheriques blocs (/proc/partitions).
    findmnt [-nlfsT] [-t type] [-o COLONNES] [-S source] [-M cible]
      [chemin] : montages (/proc/self/mountinfo ou /proc/mounts, /etc/fstab).
    Messages en cinq langues (LANGUAGE).
}

Program FsInfo;

Const
  MAXMNT = 96;
  MAXDEV = 64;
  U : Array[1..4, 1..5] Of PChar = (
    ('Usage : df [-hHkmPTia] [-t type] [-x type] [fichier...]',
     'Usage: df [-hHkmPTia] [-t type] [-x type] [file...]',
     'Aufruf: df [-hHkmPTia] [-t Typ] [-x Typ] [Datei...]',
     'Uso: df [-hHkmPTia] [-t tipo] [-x tipo] [fichero...]',
     'Uso: df [-hHkmPTia] [-t tipo] [-x tipo] [file...]'),
    ('Usage : blkid [-s TAG] [-o fmt] [-t N=V] [-L n] [-U u] [dev...]',
     'Usage: blkid [-s TAG] [-o fmt] [-t N=V] [-L l] [-U u] [dev...]',
     'Aufruf: blkid [-s TAG] [-o Fmt] [-t N=W] [-L n] [-U u] [Dev...]',
     'Uso: blkid [-s TAG] [-o fmt] [-t N=V] [-L n] [-U u] [dev...]',
     'Uso: blkid [-s TAG] [-o fmt] [-t N=V] [-L n] [-U u] [dev...]'),
    ('Usage : lsblk [-flnab] [-o COLONNES] [peripherique...]',
     'Usage: lsblk [-flnab] [-o COLUMNS] [device...]',
     'Aufruf: lsblk [-flnab] [-o SPALTEN] [Geraet...]',
     'Uso: lsblk [-flnab] [-o COLUMNAS] [dispositivo...]',
     'Uso: lsblk [-flnab] [-o COLONNE] [dispositivo...]'),
    ('Usage : findmnt [-nlfsT] [-t type] [-o COLS] [-S src] [-M cible] [chem]',
     'Usage: findmnt [-nlfsT] [-t type] [-o COLS] [-S src] [-M target] [path]',
     'Aufruf: findmnt [-nlfsT] [-t Typ] [-o SPALTEN] [-S Q] [-M Z] [Pfad]',
     'Uso: findmnt [-nlfsT] [-t tipo] [-o COLS] [-S orig] [-M dest] [ruta]',
     'Uso: findmnt [-nlfsT] [-t tipo] [-o COLS] [-S orig] [-M dest] [path]'));
  W : Array[1..4, 1..5] Of PChar = (
    ('Sys. de fichiers', 'Filesystem', 'Dateisystem', 'S. de ficheros',
     'File system'),
    ('Taille', 'Size', 'Groesse', 'Tamano', 'Dim.'),
    ('Utilise', 'Used', 'Benutzt', 'Usado', 'Usati'),
    ('Monte sur', 'Mounted on', 'Eingehaengt auf', 'Montado en',
     'Montato su'));

Type
  TMnt = Record
    Src, Dir, Typ, Opt : String;
  End;
  TDev = Record
    Name, Typ, Lbl, Uuid : String;
    Maj, Min : LongInt;
    Blocks : Double;
  End;

Var
  Mnt : Array[1..MAXMNT] Of TMnt;
  NMnt : LongInt;
  Dev : Array[1..MAXDEV] Of TDev;
  NDev : LongInt;
  Prog : String;
  Opt : Array[0..255] Of Boolean;
  OptV : Array[0..255] Of String;
  Args : Array[1..32] Of String;
  NArg : LongInt;

Function PS(P : PChar) : String;
Var X : String;
Begin
  X := '';
  While P^ <> #0 Do
  Begin
    X := X + P^;
    Inc(P);
  End;
  PS := X;
End;

Function NumS(V : LongInt) : String;
Var S : String;
Begin
  Str(V, S);
  NumS := S;
End;

Function PadR(Const S : String; N : LongInt) : String;
Var R : String;
Begin
  R := S;
  While Length(R) < N Do R := R + ' ';
  PadR := R;
End;

Function PadL(Const S : String; N : LongInt) : String;
Var R : String;
Begin
  R := S;
  While Length(R) < N Do R := ' ' + R;
  PadL := R;
End;

Function Lower(Const S : String) : String;
Var R : String; K : LongInt;
Begin
  R := S;
  For K := 1 To Length(R) Do
    If R[K] In ['A'..'Z'] Then R[K] := Chr(Ord(R[K]) + 32);
  Lower := R;
End;

Function Field(Const S : String; N : LongInt) : String;
Var K, F, A : LongInt;
Begin
  F := 0;
  K := 1;
  Field := '';
  While K <= Length(S) Do
  Begin
    While (K <= Length(S)) And (S[K] In [' ', #9]) Do Inc(K);
    If K > Length(S) Then Break;
    A := K;
    While (K <= Length(S)) And Not (S[K] In [' ', #9]) Do Inc(K);
    Inc(F);
    If F = N Then
    Begin
      Field := Copy(S, A, K - A);
      Exit;
    End;
  End;
End;

Function ToNum(Const S : String) : LongInt;
Var V, C : LongInt;
Begin
  Val(S, V, C);
  If C <> 0 Then V := 0;
  ToNum := V;
End;

{ ---------- lecture des tables ---------- }

{ /proc/mounts : \040 = espace }
Function Unesc(Const S : String) : String;
Var R : String; K : LongInt;
Begin
  R := '';
  K := 1;
  While K <= Length(S) Do
  Begin
    If (S[K] = '\') And (K + 3 <= Length(S)) Then
    Begin
      R := R + Chr(ToNum(Copy(S, K + 1, 1)) * 64 + ToNum(Copy(S, K + 2, 1)) *
           8 + ToNum(Copy(S, K + 3, 1)));
      K := K + 3;
    End
    Else R := R + S[K];
    Inc(K);
  End;
  Unesc := R;
End;

Procedure LoadTable(Const Path : String);
Var F : LongInt; L : String;
Begin
  NMnt := 0;
  F := SysOpen(Path, O_RDONLY, 0);
  If F < 0 Then Exit;
  While SysReadLine(F, L) Do
  Begin
    If (L = '') Or (L[1] = '#') Then Continue;
    If NMnt >= MAXMNT Then Break;
    Inc(NMnt);
    Mnt[NMnt].Src := Unesc(Field(L, 1));
    Mnt[NMnt].Dir := Unesc(Field(L, 2));
    Mnt[NMnt].Typ := Field(L, 3);
    Mnt[NMnt].Opt := Field(L, 4);
  End;
  SysClose(F);
End;

Procedure LoadParts;
Var F : LongInt; L : String;
Begin
  NDev := 0;
  F := SysOpen('/proc/partitions', O_RDONLY, 0);
  If F < 0 Then Exit;
  While SysReadLine(F, L) Do
  Begin
    If (Field(L, 1) = '') Or (Field(L, 1) = 'major') Then Continue;
    If NDev >= MAXDEV Then Break;
    Inc(NDev);
    Dev[NDev].Maj := ToNum(Field(L, 1));
    Dev[NDev].Min := ToNum(Field(L, 2));
    Dev[NDev].Blocks := ToNum(Field(L, 3));
    Dev[NDev].Name := Field(L, 4);
    Dev[NDev].Typ := '';
    Dev[NDev].Lbl := '';
    Dev[NDev].Uuid := '';
  End;
  SysClose(F);
End;

{ ---------- reconnaissance du contenu d'un peripherique ---------- }

{$I FSPROBE.INC}

Procedure ProbeDevs;
Var K : LongInt;
Begin
  For K := 1 To NDev Do
    Probe('/dev/' + Dev[K].Name, Dev[K].Typ, Dev[K].Lbl, Dev[K].Uuid);
End;

{ ---------- options ---------- }

Procedure ParseOpts(Const Valued : String);
Var I, K : LongInt; A : String;
Begin
  FillChar(Opt, SizeOf(Opt), 0);
  NArg := 0;
  I := 1;
  While I < SysArgCount Do
  Begin
    A := SysArgStr(I);
    If (A = '--help') Or (A = '/?') Then
    Begin
      If Prog = 'df' Then K := 1
      Else If Prog = 'blkid' Then K := 2
      Else If Prog = 'lsblk' Then K := 3
      Else K := 4;
      SysPut(1, PS(U[K, SysLang]) + #10);
      SysExit(0);
    End;
    If (Length(A) > 1) And (A[1] = '-') And (A <> '--') Then
    Begin
      If A = '--human-readable' Then A := '-h'
      Else If A = '--print-type' Then A := '-T'
      Else If A = '--portability' Then A := '-P'
      Else If A = '--inodes' Then A := '-i'
      Else If A = '--all' Then A := '-a'
      Else If A = '--list' Then A := '-l'
      Else If A = '--noheadings' Then A := '-n'
      Else If A = '--fstab' Then A := '-s'
      Else If A = '--first-only' Then A := '-f';
      K := 2;
      While K <= Length(A) Do
      Begin
        Opt[Ord(A[K])] := True;
        If Pos(A[K], Valued) > 0 Then
        Begin
          If K < Length(A) Then OptV[Ord(A[K])] := Copy(A, K + 1, 255)
          Else
          Begin
            Inc(I);
            If I < SysArgCount Then OptV[Ord(A[K])] := SysArgStr(I);
          End;
          K := Length(A);
        End;
        Inc(K);
      End;
    End
    Else If NArg < 32 Then
    Begin
      Inc(NArg);
      Args[NArg] := A;
    End;
    Inc(I);
  End;
End;

Function InList(Const L, T : String) : Boolean;
Var K, J : LongInt;
Begin
  InList := False;
  K := 1;
  While K <= Length(L) + 1 Do
  Begin
    J := K;
    While (J <= Length(L)) And (L[J] <> ',') Do Inc(J);
    If Copy(L, K, J - K) = T Then InList := True;
    K := J + 1;
  End;
End;

{ ---------- df ---------- }

Function Human(K : Double; Base : LongInt) : String;
Var V : Double; Idx, T : LongInt; S : String;
Const Un : String = 'KMGTP';
Begin
  V := K;
  Idx := 1;
  While (V >= Base) And (Idx < 5) Do
  Begin
    V := V / Base;
    Inc(Idx);
  End;
  If (Idx = 1) Then
  Begin
    If V = 0 Then
    Begin
      Human := '0';
      Exit;
    End;
    T := Trunc(V);
    If T < V Then Inc(T);
    Human := NumS(T) + 'K';
    Exit;
  End;
  T := Trunc(V * 10);
  If T < V * 10 Then Inc(T);
  If (V < 10) And (T < 100) Then
    S := NumS(T Div 10) + '.' + NumS(T Mod 10)
  Else If V < 10 Then S := '10'
  Else
  Begin
    T := Trunc(V);
    If T < V Then Inc(T);
    S := NumS(T);
  End;
  Human := S + Un[Idx];
End;

Function SizeS(K : Double) : String;
Var T : LongInt;
Begin
  If Opt[Ord('h')] Then SizeS := Human(K, 1024)
  Else If Opt[Ord('H')] Then SizeS := Human(K * 1024 / 1000, 1000)
  Else If Opt[Ord('m')] Then
  Begin
    T := Trunc(K / 1024);
    If T * 1024 < K Then Inc(T);
    SizeS := NumS(T);
  End
  Else If Opt[Ord('B')] Then SizeS := NumS(Trunc(K))
  Else SizeS := NumS(Trunc(K));
End;

Function Pct(Used, Tot : Double) : String;
Var T : LongInt;
Begin
  If Tot <= 0 Then
  Begin
    Pct := '-';
    Exit;
  End;
  T := Trunc(Used * 100 / Tot);
  If T * Tot < Used * 100 Then Inc(T);
  Pct := NumS(T) + '%';
End;

Type
  TStatFs = Record
    FType, FBsize, FBlocks, FBfree, FBavail, FFiles, FFfree : LongInt;
    FsidA, FsidB, FNamelen, FFrsize, FFlags : LongInt;
    Spare : Array[0..3] Of LongInt;
  End;

Function UnsU(V : LongInt) : Double;
Begin
  If V < 0 Then UnsU := V + 4294967296.0 Else UnsU := V;
End;

Procedure RunDf;
Var K, J, N, R : LongInt; F : TStatFs; Bs, Tot, Fre, Av, Used : Double;
    Lines : Array[1..MAXMNT] Of String; NL : LongInt;
    Sel : Array[1..MAXMNT] Of Boolean; Seen : Boolean; St : TSysStat;
    Ln : String; Bsz : Double; NRow : LongInt;
    Cell : Array[1..MAXMNT + 1, 1..7] Of String; Wd : Array[1..7] Of LongInt;
  Procedure AddRow(A, B, C, D, E, F_, G : String);
  Begin
    Inc(NRow);
    Cell[NRow, 1] := A;
    Cell[NRow, 2] := B;
    Cell[NRow, 3] := C;
    Cell[NRow, 4] := D;
    Cell[NRow, 5] := E;
    Cell[NRow, 6] := F_;
    Cell[NRow, 7] := G;
  End;
Begin
  ParseOpts('tx');
  LoadTable('/proc/mounts');
  For K := 1 To NMnt Do Sel[K] := True;
  If NArg > 0 Then
  Begin
    For K := 1 To NMnt Do Sel[K] := False;
    For J := 1 To NArg Do
    Begin
      If SysStat(Args[J], St) < 0 Then
      Begin
        SysPut(2, 'df: ' + Args[J] + ': ' + SysErrorText(SysErrno) + #10);
        Continue;
      End;
      { montage le plus long prefixe du chemin (ou le peripherique) }
      N := 0;
      R := -1;
      For K := 1 To NMnt Do
        If (Mnt[K].Src = Args[J]) Then R := K;
      If R < 0 Then
      Begin
        Ln := Args[J];
        If SysReadlink(Args[J]) <> '' Then Ln := SysReadlink(Args[J]);
        If (Length(Ln) > 0) And (Ln[1] <> '/') Then
        Begin
          Ln := SysGetCwd;
          If Ln = '/' Then Ln := '/' + Args[J] Else Ln := Ln + '/' + Args[J];
        End;
        For K := 1 To NMnt Do
          If (Copy(Ln, 1, Length(Mnt[K].Dir)) = Mnt[K].Dir) And
             ((Length(Ln) = Length(Mnt[K].Dir)) Or (Mnt[K].Dir = '/') Or
              (Ln[Length(Mnt[K].Dir) + 1] = '/')) And
             (Length(Mnt[K].Dir) >= N) Then
          Begin
            N := Length(Mnt[K].Dir);
            R := K;
          End;
      End;
      If R > 0 Then Sel[R] := True;
    End;
  End;
  { colonnes : 1 source, [type], 3 nombres, pourcentage, point de montage }
  NRow := 0;
  AddRow(PS(W[1, SysLang]), 'Type', '', '', '', '', PS(W[4, SysLang]));
  If Opt[Ord('i')] Then
  Begin
    Cell[1, 3] := 'Inodes';
    Cell[1, 4] := 'IUsed';
    Cell[1, 5] := 'IFree';
    Cell[1, 6] := 'IUse%';
  End
  Else If Opt[Ord('h')] Or Opt[Ord('H')] Then
  Begin
    Cell[1, 3] := PS(W[2, SysLang]);
    Cell[1, 4] := PS(W[3, SysLang]);
    Cell[1, 5] := 'Avail';
    Cell[1, 6] := 'Use%';
  End
  Else
  Begin
    If Opt[Ord('m')] Then Cell[1, 3] := '1M-blocks'
    Else If Opt[Ord('P')] Then Cell[1, 3] := '1024-blocks'
    Else Cell[1, 3] := '1K-blocks';
    Cell[1, 4] := 'Used';
    Cell[1, 5] := 'Available';
    If Opt[Ord('P')] Then Cell[1, 6] := 'Capacity' Else Cell[1, 6] := 'Use%';
  End;
  For K := 1 To NMnt Do
  Begin
    If Not Sel[K] Then Continue;
    If Opt[Ord('t')] And Not InList(OptV[Ord('t')], Mnt[K].Typ) Then Continue;
    If Opt[Ord('x')] And InList(OptV[Ord('x')], Mnt[K].Typ) Then Continue;
    FillChar(F, SizeOf(F), 0);
    If LnxSys3(99, LnxZ(Mnt[K].Dir), LongInt(@F), 0) < 0 Then Continue;
    Tot := UnsU(F.FBlocks);
    If (Tot = 0) And Not Opt[Ord('a')] And (NArg = 0) Then Continue;
    Bs := UnsU(F.FBsize);
    If F.FFrsize <> 0 Then Bs := UnsU(F.FFrsize);
    Bsz := Bs / 1024;
    Fre := UnsU(F.FBfree);
    Av := UnsU(F.FBavail);
    Used := Tot - Fre;
    If Opt[Ord('i')] Then
    Begin
      Tot := UnsU(F.FFiles);
      Fre := UnsU(F.FFfree);
      Used := Tot - Fre;
      AddRow(Mnt[K].Src, Mnt[K].Typ, NumS(Trunc(Tot)), NumS(Trunc(Used)),
             NumS(Trunc(Fre)), Pct(Used, Tot), Mnt[K].Dir);
    End
    Else
      AddRow(Mnt[K].Src, Mnt[K].Typ, SizeS(Tot * Bsz), SizeS(Used * Bsz),
             SizeS(Av * Bsz), Pct(Used, Used + Av), Mnt[K].Dir);
  End;
  { largeurs : sources 14 au moins ; nombres 5 au moins avec -h }
  For J := 1 To 7 Do Wd[J] := 0;
  For K := 1 To NRow Do
    For J := 1 To 7 Do
      If Length(Cell[K, J]) > Wd[J] Then Wd[J] := Length(Cell[K, J]);
  If Wd[1] < 14 Then Wd[1] := 14;
  If Opt[Ord('h')] Or Opt[Ord('H')] Then
    For J := 3 To 5 Do
      If Wd[J] < 5 Then Wd[J] := 5;
  For K := 1 To NRow Do
  Begin
    Ln := PadR(Cell[K, 1], Wd[1]);
    If Opt[Ord('T')] Then Ln := Ln + ' ' + PadR(Cell[K, 2], Wd[2]);
    For J := 3 To 6 Do Ln := Ln + ' ' + PadL(Cell[K, J], Wd[J]);
    Ln := Ln + ' ' + Cell[K, 7];
    SysPut(1, Ln + #10);
  End;
End;

{ ---------- blkid ---------- }

Procedure BlkLine(Const Name, Typ, Lbl, Uuid : String);
Var Only : String; Ln : String;
Begin
  Only := '';
  If Opt[Ord('s')] Then Only := OptV[Ord('s')];
  If Opt[Ord('o')] And (OptV[Ord('o')] = 'value') Then
  Begin
    If (Lbl <> '') And ((Only = '') Or (Only = 'LABEL')) Then
      SysPut(1, Lbl + #10);
    If (Uuid <> '') And ((Only = '') Or (Only = 'UUID')) Then
      SysPut(1, Uuid + #10);
    If (Typ <> '') And ((Only = '') Or (Only = 'TYPE')) Then
      SysPut(1, Typ + #10);
    Exit;
  End;
  If Opt[Ord('o')] And (OptV[Ord('o')] = 'export') Then
  Begin
    SysPut(1, 'DEVNAME=' + Name + #10);
    If (Lbl <> '') And ((Only = '') Or (Only = 'LABEL')) Then
      SysPut(1, 'LABEL=' + Lbl + #10);
    If (Uuid <> '') And ((Only = '') Or (Only = 'UUID')) Then
      SysPut(1, 'UUID=' + Uuid + #10);
    If (Typ <> '') And ((Only = '') Or (Only = 'TYPE')) Then
      SysPut(1, 'TYPE=' + Typ + #10);
    SysPut(1, #10);
    Exit;
  End;
  Ln := Name + ':';
  If (Lbl <> '') And ((Only = '') Or (Only = 'LABEL')) Then
    Ln := Ln + ' LABEL="' + Lbl + '"';
  If (Uuid <> '') And ((Only = '') Or (Only = 'UUID')) Then
    Ln := Ln + ' UUID="' + Uuid + '"';
  If (Typ <> '') And ((Only = '') Or (Only = 'TYPE')) Then
    Ln := Ln + ' TYPE="' + Typ + '"';
  SysPut(1, Ln + #10);
End;

Function BlkMatch(Const Typ, Lbl, Uuid : String) : Boolean;
Var T, N, V : String; P : LongInt;
Begin
  BlkMatch := True;
  If Opt[Ord('L')] And (Lbl <> OptV[Ord('L')]) Then BlkMatch := False;
  If Opt[Ord('U')] And (Lower(Uuid) <> Lower(OptV[Ord('U')])) Then
    BlkMatch := False;
  If Opt[Ord('t')] Then
  Begin
    T := OptV[Ord('t')];
    P := Pos('=', T);
    If P = 0 Then Exit;
    N := Copy(T, 1, P - 1);
    V := Copy(T, P + 1, 200);
    If Length(V) > 1 Then
      If (V[1] = '"') Or (V[1] = '''') Then V := Copy(V, 2, Length(V) - 2);
    If (N = 'TYPE') And (Typ <> V) Then BlkMatch := False;
    If (N = 'LABEL') And (Lbl <> V) Then BlkMatch := False;
    If (N = 'UUID') And (Lower(Uuid) <> Lower(V)) Then BlkMatch := False;
  End;
End;

Procedure RunBlkid;
Var K : LongInt; Typ, Lbl, Uuid : String; Found : Boolean;
Begin
  ParseOpts('sotLU');
  Found := False;
  If NArg > 0 Then
  Begin
    For K := 1 To NArg Do
    Begin
      Probe(Args[K], Typ, Lbl, Uuid);
      If Typ = '' Then Continue;
      If Not BlkMatch(Typ, Lbl, Uuid) Then Continue;
      Found := True;
      If Opt[Ord('L')] Or Opt[Ord('U')] Then SysPut(1, Args[K] + #10)
      Else BlkLine(Args[K], Typ, Lbl, Uuid);
    End;
    If Not Found Then SysExit(2);
    SysExit(0);
  End;
  LoadParts;
  ProbeDevs;
  For K := 1 To NDev Do
  Begin
    If Dev[K].Typ = '' Then Continue;
    If Not BlkMatch(Dev[K].Typ, Dev[K].Lbl, Dev[K].Uuid) Then Continue;
    Found := True;
    If Opt[Ord('L')] Or Opt[Ord('U')] Then
      SysPut(1, '/dev/' + Dev[K].Name + #10)
    Else BlkLine('/dev/' + Dev[K].Name, Dev[K].Typ, Dev[K].Lbl, Dev[K].Uuid);
  End;
  If Not Found Then SysExit(2);
End;

{ ---------- lsblk ---------- }

Function IsPart(Const N, Whole : String) : Boolean;
Var K : LongInt;
Begin
  IsPart := False;
  If (Length(N) <= Length(Whole)) Or (Copy(N, 1, Length(Whole)) <> Whole) Then
    Exit;
  If Whole = '' Then Exit;
  If (Whole[Length(Whole)] In ['0'..'9']) And (N[Length(Whole) + 1] = 'p') Then
    Exit(True);
  IsPart := True;
  For K := Length(Whole) + 1 To Length(N) Do
    If Not (N[K] In ['0'..'9']) Then IsPart := False;
End;

Function MountOf(Const Name : String) : String;
Var K : LongInt; R : String;
Begin
  R := '';
  For K := 1 To NMnt Do
    If Mnt[K].Src = '/dev/' + Name Then
      If R = '' Then R := Mnt[K].Dir Else R := R + ',' + Mnt[K].Dir;
  MountOf := R;
End;

Function ColVal(Const Col : String; K : LongInt; IsPrt : Boolean) : String;
Var Sz : Double; D : String;
Begin
  D := Dev[K].Name;
  If Col = 'NAME' Then ColVal := D
  Else If Col = 'MAJ:MIN' Then ColVal := NumS(Dev[K].Maj) + ':' +
    NumS(Dev[K].Min)
  Else If Col = 'RM' Then ColVal := '0'
  Else If Col = 'RO' Then ColVal := '0'
  Else If Col = 'SIZE' Then
  Begin
    Sz := Dev[K].Blocks;
    If Opt[Ord('b')] Then ColVal := NumS(Trunc(Sz)) + '000'
    Else ColVal := Human(Sz, 1024);
    If Opt[Ord('b')] Then ColVal := NumS(Trunc(Sz * 1024))
  End
  Else If Col = 'TYPE' Then
  Begin
    If Copy(D, 1, 4) = 'loop' Then ColVal := 'loop'
    Else If Copy(D, 1, 3) = 'rom' Then ColVal := 'rom'
    Else If IsPrt Then ColVal := 'part'
    Else ColVal := 'disk';
  End
  Else If (Col = 'MOUNTPOINT') Or (Col = 'MOUNTPOINTS') Then
    ColVal := MountOf(D)
  Else If Col = 'FSTYPE' Then ColVal := Dev[K].Typ
  Else If Col = 'LABEL' Then ColVal := Dev[K].Lbl
  Else If Col = 'UUID' Then ColVal := Dev[K].Uuid
  Else If Col = 'PATH' Then ColVal := '/dev/' + D
  Else ColVal := '';
End;

Procedure RunLsblk;
Var K, J, C, NC, Order : LongInt; Cols : Array[1..12] Of String; L, Nm : String;
    Cw : Array[1..12] Of LongInt; Rows : Array[1..MAXDEV * 2] Of String;
    NR : LongInt; Lines : Array[1..MAXDEV] Of LongInt; Val_ : String;
    Prefix : String; Done : Array[1..MAXDEV] Of Boolean; Lst : Boolean;
    Cells : Array[1..MAXDEV, 1..12] Of String; Cnt : LongInt;
    Pre : Array[1..MAXDEV] Of String; Ord_ : Array[1..MAXDEV] Of LongInt;
    Hdr : Boolean; Isp : Boolean;
Begin
  ParseOpts('o');
  LoadParts;
  LoadTable('/proc/mounts');
  If Opt[Ord('f')] Then ProbeDevs;
  Lst := Opt[Ord('l')];
  If Opt[Ord('o')] Then L := OptV[Ord('o')]
  Else If Opt[Ord('f')] Then L := 'NAME,FSTYPE,LABEL,UUID,MOUNTPOINTS'
  Else L := 'NAME,MAJ:MIN,RM,SIZE,RO,TYPE,MOUNTPOINTS';
  NC := 0;
  K := 1;
  While K <= Length(L) Do
  Begin
    J := K;
    While (J <= Length(L)) And (L[J] <> ',') Do Inc(J);
    If NC < 12 Then
    Begin
      Inc(NC);
      Cols[NC] := Copy(L, K, J - K);
      For C := 1 To Length(Cols[NC]) Do
        Cols[NC][C] := UpCase(Cols[NC][C]);
    End;
    K := J + 1;
  End;
  { ordre : disque puis ses partitions }
  Cnt := 0;
  For K := 1 To NDev Do Done[K] := False;
  For K := 1 To NDev Do
  Begin
    If Done[K] Then Continue;
    Isp := False;
    For J := 1 To NDev Do
      If (J <> K) And IsPart(Dev[K].Name, Dev[J].Name) Then Isp := True;
    If Isp Then Continue;
    If (NArg > 0) Then
    Begin
      Isp := False;
      For C := 1 To NArg Do
        If (Args[C] = Dev[K].Name) Or (Args[C] = '/dev/' + Dev[K].Name) Then
          Isp := True;
      If Not Isp Then Continue;
    End;
    Done[K] := True;
    Inc(Cnt);
    Ord_[Cnt] := K;
    Pre[Cnt] := '';
    For J := 1 To NDev Do
      If (Not Done[J]) And IsPart(Dev[J].Name, Dev[K].Name) Then
      Begin
        Done[J] := True;
        Inc(Cnt);
        Ord_[Cnt] := J;
        Pre[Cnt] := '|-';
        If Not Lst Then
        Begin
          { dernier enfant : `- }
        End;
      End;
  End;
  { le dernier enfant d'un disque porte `- }
  For K := 1 To Cnt Do
    If Pre[K] <> '' Then
      If (K = Cnt) Or (Pre[K + 1] = '') Then Pre[K] := '`-';
  For C := 1 To NC Do Cw[C] := Length(Cols[C]);
  For K := 1 To Cnt Do
    For C := 1 To NC Do
    Begin
      Isp := Pre[K] <> '';
      Val_ := ColVal(Cols[C], Ord_[K], Isp);
      If (Cols[C] = 'NAME') And Not Lst Then Val_ := Pre[K] + Val_;
      Cells[K, C] := Val_;
      If Length(Val_) > Cw[C] Then Cw[C] := Length(Val_);
    End;
  If Not Opt[Ord('n')] Then
  Begin
    L := '';
    For C := 1 To NC Do
      If C = NC Then L := L + Cols[C] Else L := L + PadR(Cols[C], Cw[C] + 1);
    SysPut(1, L + #10);
  End;
  For K := 1 To Cnt Do
  Begin
    L := '';
    For C := 1 To NC Do
    Begin
      If C = NC Then L := L + Cells[K, C]
      Else If (Cols[C] = 'SIZE') Or (Cols[C] = 'RM') Or (Cols[C] = 'RO') Then
        L := L + PadL(Cells[K, C], Cw[C]) + ' '
      Else L := L + PadR(Cells[K, C], Cw[C] + 1);
    End;
    SysPut(1, L + #10);
  End;
End;

{ ---------- findmnt ---------- }

Function MCol(Const Col : String; K : LongInt) : String;
Begin
  If Col = 'TARGET' Then MCol := Mnt[K].Dir
  Else If Col = 'SOURCE' Then MCol := Mnt[K].Src
  Else If Col = 'FSTYPE' Then MCol := Mnt[K].Typ
  Else If Col = 'OPTIONS' Then MCol := Mnt[K].Opt
  Else If Col = 'PASSNO' Then MCol := '0'
  Else MCol := '';
End;

Procedure RunFindmnt;
Var K, J, C, NC, N, Best, BL : LongInt; L, Cl, Tg : String;
    Cols : Array[1..8] Of String; Cw : Array[1..8] Of LongInt;
    Sel : Array[1..MAXMNT] Of Boolean; Depth : Array[1..MAXMNT] Of LongInt;
    Pre : Array[1..MAXMNT] Of String; Fs : Boolean; Tree : Boolean;
    Cells : Array[1..MAXMNT, 1..8] Of String;
    Ord_ : Array[1..MAXMNT] Of LongInt;
    Cnt, Par : LongInt; Done : Array[1..MAXMNT] Of Boolean;
    Pr : Array[1..MAXMNT] Of LongInt;
  Procedure Add(Idx, Dp : LongInt; Const Pf : String);
  Var Q, Last, Nk : LongInt; Np : String;
  Begin
    Inc(Cnt);
    Ord_[Cnt] := Idx;
    Depth[Cnt] := Dp;
    Pre[Cnt] := Pf;
    Done[Idx] := True;
    Last := 0;
    For Q := 1 To NMnt Do
      If (Not Done[Q]) And (Pr[Q] = Idx) Then Last := Q;
    For Q := 1 To NMnt Do
      If (Not Done[Q]) And (Pr[Q] = Idx) Then
      Begin
        Np := '';
        If Dp > 0 Then
        Begin
          Np := Copy(Pf, 1, Length(Pf) - 2);
          If Copy(Pf, Length(Pf) - 1, 2) = '|-' Then Np := Np + '| '
          Else Np := Np + '  ';
        End;
        If Q = Last Then Add(Q, Dp + 1, Np + '`-')
        Else Add(Q, Dp + 1, Np + '|-');
      End;
  End;
Begin
  ParseOpts('toSMo');
  Fs := Opt[Ord('s')];
  If Fs Then LoadTable('/etc/fstab') Else LoadTable('/proc/mounts');
  If Opt[Ord('o')] Then L := OptV[Ord('o')]
  Else L := 'TARGET,SOURCE,FSTYPE,OPTIONS';
  NC := 0;
  K := 1;
  While K <= Length(L) Do
  Begin
    J := K;
    While (J <= Length(L)) And (L[J] <> ',') Do Inc(J);
    If NC < 8 Then
    Begin
      Inc(NC);
      Cols[NC] := Copy(L, K, J - K);
      For C := 1 To Length(Cols[NC]) Do
        Cols[NC][C] := UpCase(Cols[NC][C]);
    End;
    K := J + 1;
  End;
  For K := 1 To NMnt Do Sel[K] := True;
  Tg := '';
  If NArg > 0 Then Tg := Args[1];
  If Opt[Ord('M')] Then Tg := OptV[Ord('M')];
  If Tg <> '' Then
  Begin
    For K := 1 To NMnt Do
      Sel[K] := (Mnt[K].Dir = Tg) Or (Mnt[K].Src = Tg);
    If Opt[Ord('T')] Then
    Begin
      For K := 1 To NMnt Do Sel[K] := False;
      Best := 0;
      BL := -1;
      For K := 1 To NMnt Do
        If (Copy(Tg, 1, Length(Mnt[K].Dir)) = Mnt[K].Dir) And
           ((Length(Tg) = Length(Mnt[K].Dir)) Or (Mnt[K].Dir = '/') Or
            (Tg[Length(Mnt[K].Dir) + 1] = '/')) Then
          If Length(Mnt[K].Dir) >= BL Then
          Begin
            BL := Length(Mnt[K].Dir);
            Best := K;
          End;
      If Best > 0 Then Sel[Best] := True;
    End;
  End;
  If Opt[Ord('S')] Then
    For K := 1 To NMnt Do
      If Mnt[K].Src <> OptV[Ord('S')] Then Sel[K] := False;
  If Opt[Ord('t')] Then
    For K := 1 To NMnt Do
      If Not InList(OptV[Ord('t')], Mnt[K].Typ) Then Sel[K] := False;
  Tree := Not (Opt[Ord('l')] Or Fs Or (Tg <> '') Or Opt[Ord('t')] Or
               Opt[Ord('S')]);
  Cnt := 0;
  If Tree Then
  Begin
    { parent = montage dont le point est le plus long prefixe strict }
    For K := 1 To NMnt Do
    Begin
      Pr[K] := 0;
      BL := -1;
      For J := 1 To NMnt Do
        If (J < K) And (Mnt[J].Dir <> Mnt[K].Dir) Then
          If (Copy(Mnt[K].Dir, 1, Length(Mnt[J].Dir)) = Mnt[J].Dir) And
             ((Mnt[J].Dir = '/') Or
              (Mnt[K].Dir[Length(Mnt[J].Dir) + 1] = '/')) Then
            If Length(Mnt[J].Dir) >= BL Then
            Begin
              BL := Length(Mnt[J].Dir);
              Pr[K] := J;
            End;
      Done[K] := False;
    End;
    For K := 1 To NMnt Do
      If (Not Done[K]) And (Pr[K] = 0) Then Add(K, 0, '');
    For K := 1 To NMnt Do
      If Not Done[K] Then Add(K, 0, '');
  End
  Else
    For K := 1 To NMnt Do
      If Sel[K] Then
      Begin
        Inc(Cnt);
        Ord_[Cnt] := K;
        Pre[Cnt] := '';
      End;
  If Cnt = 0 Then SysExit(1);
  For C := 1 To NC Do Cw[C] := Length(Cols[C]);
  For K := 1 To Cnt Do
    For C := 1 To NC Do
    Begin
      Cl := MCol(Cols[C], Ord_[K]);
      If (C = 1) And Tree Then Cl := Pre[K] + Cl;
      Cells[K, C] := Cl;
      If Length(Cl) > Cw[C] Then Cw[C] := Length(Cl);
    End;
  If Opt[Ord('f')] Then Cnt := 1;
  If Not Opt[Ord('n')] Then
  Begin
    L := '';
    For C := 1 To NC Do
      If C = NC Then L := L + Cols[C] Else L := L + PadR(Cols[C], Cw[C] + 1);
    SysPut(1, L + #10);
  End;
  For K := 1 To Cnt Do
  Begin
    L := '';
    For C := 1 To NC Do
      If C = NC Then L := L + Cells[K, C]
      Else L := L + PadR(Cells[K, C], Cw[C] + 1);
    SysPut(1, L + #10);
  End;
End;

BEGIN
  Prog := SysArgStr(0);
  While Pos('/', Prog) > 0 Do Prog := Copy(Prog, Pos('/', Prog) + 1, 255);
  If Prog = 'blkid' Then RunBlkid
  Else If Prog = 'lsblk' Then RunLsblk
  Else If Prog = 'findmnt' Then RunFindmnt
  Else RunDf;
END.
