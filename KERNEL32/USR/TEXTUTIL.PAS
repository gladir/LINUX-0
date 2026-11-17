{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2026
  @website(https://www.gladir.com/linux-0)
  @abstract(Target: LPC -3X)
  @description: /bin/wc, head, tail, cut, paste (un seul programme, nom lu
      dans argv[0]) : filtres POSIX/GNU qui lisent des fichiers ou l'entree
      standard (tubes compris).
}

Program TEXTUTIL;

Const
  BufMax = 65536;
  KeepMax = 4194304;
  Msg : Array[1..5] Of PChar =
    ('Usage : ', 'Usage: ', 'Aufruf: ', 'Uso: ', 'Uso: ');
  NoFile : Array[1..5] Of PChar =
    ('Fichier inexistant', 'No such file or directory',
     'Datei nicht gefunden', 'Archivo inexistente', 'File inesistente');

Var
  Prog : String;
  Rc : LongInt;
  OBuf : Array[0..BufMax] Of Byte;
  OLen : LongInt;
  IBuf : Array[0..BufMax] Of Byte;
  Keep : Array[0..KeepMax + BufMax] Of Byte;
  KLen : LongInt;
  Files : Array[1..64] Of String;
  NFiles : LongInt;
  OptN : LongInt;       { -n ou -c : nombre }
  OptPlus : Boolean;    { tail -n +N / head -n -N }
  OptMinus : Boolean;
  OptBytes, OptQ, OptV, OptF, OptS, OptCompl : Boolean;
  OptDelim : Char;
  OutDelim : String;
  OptList : String;
  Mode : Char;          { b c f pour cut }
  OptZ : Boolean;
  FlagL, FlagW, FlagC, FlagM, FlagMax : Boolean;

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

Procedure Flush;
Var Done, R : LongInt;
Begin
  Done := 0;
  While Done < OLen Do
  Begin
    R := SysWrite(1, OBuf[Done], OLen - Done);
    If R <= 0 Then SysExit(141);
    Done := Done + R;
  End;
  OLen := 0;
End;

Procedure PutB(B : Byte);
Begin
  If OLen >= BufMax Then Flush;
  OBuf[OLen] := B;
  Inc(OLen);
End;

Procedure PutS(Const S : String);
Var K : LongInt;
Begin
  For K := 1 To Length(S) Do PutB(Ord(S[K]));
End;

Procedure Warn(Const What, Why : String);
Begin
  Flush;
  SysPut(2, Prog + ': ' + What + ': ' + Why + #10);
  Rc := 1;
End;

Procedure Usage(Const Syn : String);
Begin
  SysPut(2, PS(Msg[SysLang]) + Syn + #10);
  SysExit(1);
End;

Function OpenIn(Const Name : String) : LongInt;
Var Fd : LongInt;
Begin
  If (Name = '') Or (Name = '-') Then
  Begin
    OpenIn := 0;
    Exit;
  End;
  Fd := SysOpen(Name, O_RDONLY, 0);
  If Fd < 0 Then
  Begin
    Warn(Name, SysErrorText(SysErrno));
    OpenIn := -1;
    Exit;
  End;
  OpenIn := Fd;
End;

Procedure CloseIn(Fd : LongInt);
Begin
  If Fd > 0 Then SysClose(Fd);
End;

Function IsNum(Const S : String) : Boolean;
Var K : LongInt;
Begin
  IsNum := Length(S) > 0;
  For K := 1 To Length(S) Do
    If (S[K] < '0') Or (S[K] > '9') Then IsNum := False;
End;

Function ToNum(Const S : String) : LongInt;
Var V, C : LongInt;
Begin
  Val(S, V, C);
  If C <> 0 Then V := 0;
  ToNum := V;
End;

{ ---------------------------- wc ---------------------------- }

Var
  TotL, TotW, TotC, TotM, TotX : LongInt;

Function Digits(V : LongInt) : LongInt;
Var D : LongInt;
Begin
  D := 1;
  While V >= 10 Do
  Begin
    V := V Div 10;
    Inc(D);
  End;
  Digits := D;
End;

Procedure PutNum(V, W : LongInt);
Var S : String;
Begin
  S := NumS(V);
  While Length(S) < W Do S := ' ' + S;
  PutS(S);
End;

Procedure WcOne(Const Name : String; Width : LongInt; Show : Boolean);
Var
  Fd, N, K, Lines, Words, Bytes, Chars, MaxL, CurL : LongInt;
  InWord : Boolean;
  B : Byte;
  First : Boolean;
Begin
  Fd := OpenIn(Name);
  If Fd < 0 Then Exit;
  Lines := 0; Words := 0; Bytes := 0; Chars := 0; MaxL := 0; CurL := 0;
  InWord := False;
  Repeat
    N := SysRead(Fd, IBuf[0], BufMax);
    If N > 0 Then
    Begin
      Bytes := Bytes + N;
      For K := 0 To N - 1 Do
      Begin
        B := IBuf[K];
        If (B And $C0) <> $80 Then Inc(Chars);
        If B = 10 Then
        Begin
          Inc(Lines);
          If CurL > MaxL Then MaxL := CurL;
          CurL := 0;
        End
        Else If B = 9 Then CurL := (CurL Or 7) + 1
        Else If (B And $C0) <> $80 Then Inc(CurL);
        If (B = 32) Or ((B >= 9) And (B <= 13)) Then InWord := False
        Else If Not InWord Then
        Begin
          InWord := True;
          Inc(Words);
        End;
      End;
    End;
  Until N <= 0;
  If CurL > MaxL Then MaxL := CurL;
  CloseIn(Fd);
  First := True;
  If FlagL Then Begin PutNum(Lines, Width); First := False; End;
  If FlagW Then
  Begin
    If Not First Then PutB(32);
    PutNum(Words, Width);
    First := False;
  End;
  If FlagM Then
  Begin
    If Not First Then PutB(32);
    PutNum(Chars, Width);
    First := False;
  End;
  If FlagC Then
  Begin
    If Not First Then PutB(32);
    PutNum(Bytes, Width);
    First := False;
  End;
  If FlagMax Then
  Begin
    If Not First Then PutB(32);
    PutNum(MaxL, Width);
  End;
  If Show Then PutS(' ' + Name);
  PutB(10);
  TotL := TotL + Lines; TotW := TotW + Words; TotC := TotC + Bytes;
  TotM := TotM + Chars;
  If MaxL > TotX Then TotX := MaxL;
End;

Procedure RunWc;
Var
  I, W, Sum, Cnt : LongInt;
  A : String;
  St : TSysStat;
  Only : Boolean;
Begin
  FlagL := False; FlagW := False; FlagC := False; FlagM := False;
  FlagMax := False;
  NFiles := 0;
  I := 1;
  While I < SysArgCount Do
  Begin
    A := SysArgStr(I);
    If (A = '--help') Or (A = '/?') Then Usage('wc [-clmwL] [file...]')
    Else If A = '--lines' Then FlagL := True
    Else If A = '--words' Then FlagW := True
    Else If A = '--bytes' Then FlagC := True
    Else If A = '--chars' Then FlagM := True
    Else If A = '--max-line-length' Then FlagMax := True
    Else If (Length(A) > 1) And (A[1] = '-') And (A[2] <> '-') Then
    Begin
      For W := 2 To Length(A) Do
        Case A[W] Of
          'l' : FlagL := True;
          'w' : FlagW := True;
          'c' : FlagC := True;
          'm' : FlagM := True;
          'L' : FlagMax := True;
        Else Usage('wc [-clmwL] [file...]');
        End;
    End
    Else If NFiles < 64 Then
    Begin
      Inc(NFiles);
      Files[NFiles] := A;
    End;
    Inc(I);
  End;
  If Not (FlagL Or FlagW Or FlagC Or FlagM Or FlagMax) Then
  Begin
    FlagL := True; FlagW := True; FlagC := True;
  End;
  Cnt := 0;
  If FlagL Then Inc(Cnt);
  If FlagW Then Inc(Cnt);
  If FlagC Then Inc(Cnt);
  If FlagM Then Inc(Cnt);
  If FlagMax Then Inc(Cnt);
  TotL := 0; TotW := 0; TotC := 0; TotM := 0; TotX := 0;
  Only := (NFiles <= 1) And (Cnt = 1);
  If NFiles = 0 Then
  Begin
    W := 7;
    If (SysFStat(0, St) = 0) And ((St.Mode And $F000) = $8000) Then
      W := Digits(St.Size);
    If Only Then W := 1;
    WcOne('-', W, False);
  End
  Else
  Begin
    Sum := 0;
    For I := 1 To NFiles Do
      If (Files[I] <> '-') And (SysStat(Files[I], St) = 0) Then
        Sum := Sum + St.Size;
    W := Digits(Sum);
    If Sum = 0 Then W := 1;
    For I := 1 To NFiles Do If Files[I] = '-' Then W := 7;
    If Only Then W := 1;
    For I := 1 To NFiles Do
      WcOne(Files[I], W, Files[I] <> '-');
    If NFiles > 1 Then
    Begin
      Cnt := 0;
      If FlagL Then Begin PutNum(TotL, W); Cnt := 1; End;
      If FlagW Then
      Begin
        If Cnt > 0 Then PutB(32);
        PutNum(TotW, W); Cnt := 1;
      End;
      If FlagM Then
      Begin
        If Cnt > 0 Then PutB(32);
        PutNum(TotM, W); Cnt := 1;
      End;
      If FlagC Then
      Begin
        If Cnt > 0 Then PutB(32);
        PutNum(TotC, W); Cnt := 1;
      End;
      If FlagMax Then
      Begin
        If Cnt > 0 Then PutB(32);
        PutNum(TotX, W);
      End;
      PutS(' total'#10);
    End;
  End;
End;

{ -------------------- options communes head/tail -------------------- }

Procedure ParseCount(Const S : String);
Var T : String;
Begin
  T := S;
  OptPlus := False;
  OptMinus := False;
  If (Length(T) > 0) And (T[1] = '+') Then
  Begin
    OptPlus := True;
    T := Copy(T, 2, 255);
  End
  Else If (Length(T) > 0) And (T[1] = '-') Then
  Begin
    OptMinus := True;
    T := Copy(T, 2, 255);
  End;
  { suffixes k, m, b }
  If Length(T) > 0 Then
    Case T[Length(T)] Of
      'k', 'K' : Begin OptN := 1024; T := Copy(T, 1, Length(T) - 1); End;
      'm', 'M' : Begin OptN := 1048576; T := Copy(T, 1, Length(T) - 1); End;
      'b' : Begin OptN := 512; T := Copy(T, 1, Length(T) - 1); End;
    Else OptN := 1;
    End
  Else OptN := 1;
  If Not IsNum(T) Then
  Begin
    SysPut(2, Prog + ': ' + S + ': invalid number'#10);
    SysExit(1);
  End;
  OptN := OptN * ToNum(T);
End;

Procedure ParseHT(Syn : String);
Var
  I, W : LongInt;
  A : String;
Begin
  OptN := 10; OptBytes := False; OptQ := False; OptV := False;
  OptF := False; OptPlus := False; OptMinus := False; OptZ := False;
  NFiles := 0;
  I := 1;
  While I < SysArgCount Do
  Begin
    A := SysArgStr(I);
    If (A = '--help') Or (A = '/?') Then Usage(Syn)
    Else If (A = '-q') Or (A = '--quiet') Or (A = '--silent') Then OptQ := True
    Else If (A = '-v') Or (A = '--verbose') Then OptV := True
    Else If (A = '-f') Or (A = '--follow') Or (A = '-F') Then OptF := True
    Else If A = '-z' Then OptZ := True
    Else If (A = '-n') Or (A = '--lines') Then
    Begin
      Inc(I);
      OptBytes := False;
      If I < SysArgCount Then ParseCount(SysArgStr(I)) Else Usage(Syn);
    End
    Else If (A = '-c') Or (A = '--bytes') Then
    Begin
      Inc(I);
      OptBytes := True;
      If I < SysArgCount Then ParseCount(SysArgStr(I)) Else Usage(Syn);
    End
    Else If Copy(A, 1, 8) = '--lines=' Then
    Begin
      OptBytes := False;
      ParseCount(Copy(A, 9, 255));
    End
    Else If Copy(A, 1, 8) = '--bytes=' Then
    Begin
      OptBytes := True;
      ParseCount(Copy(A, 9, 255));
    End
    Else If (Length(A) > 2) And (Copy(A, 1, 2) = '-n') Then
    Begin
      OptBytes := False;
      ParseCount(Copy(A, 3, 255));
    End
    Else If (Length(A) > 2) And (Copy(A, 1, 2) = '-c') Then
    Begin
      OptBytes := True;
      ParseCount(Copy(A, 3, 255));
    End
    Else If (Length(A) > 1) And (A[1] = '-') And IsNum(Copy(A, 2, 255)) Then
    Begin
      OptBytes := False;
      OptN := ToNum(Copy(A, 2, 255));
      OptMinus := False;
    End
    Else If (Length(A) > 1) And (A[1] = '+') And IsNum(Copy(A, 2, 255)) Then
    Begin
      OptBytes := False;
      OptN := ToNum(Copy(A, 2, 255));
      OptPlus := True;
    End
    Else If (A = '--') Then
    Begin
      For W := I + 1 To SysArgCount - 1 Do
        If NFiles < 64 Then
        Begin
          Inc(NFiles);
          Files[NFiles] := SysArgStr(W);
        End;
      I := SysArgCount;
    End
    Else If (Length(A) > 1) And (A[1] = '-') Then Usage(Syn)
    Else If NFiles < 64 Then
    Begin
      Inc(NFiles);
      Files[NFiles] := A;
    End;
    Inc(I);
  End;
End;

Procedure Header(Const Name : String; Idx : LongInt);
Begin
  If (NFiles > 1) And (Not OptQ) Or OptV Then
  Begin
    If Idx > 1 Then PutB(10);
    If Name = '-' Then PutS('==> standard input <=='#10)
    Else PutS('==> ' + Name + ' <=='#10);
  End;
End;

{ ---------------------------- head ---------------------------- }

Procedure HeadOne(Const Name : String; Idx : LongInt);
Var
  Fd, N, K, Lines, Left : LongInt;
  B : Byte;
  Sep : Byte;
Begin
  Fd := OpenIn(Name);
  If Fd < 0 Then Exit;
  Header(Name, Idx);
  Sep := 10;
  If OptZ Then Sep := 0;
  If OptMinus Then
  Begin
    { tout sauf les N dernieres lignes/octets : lire dans Keep }
    KLen := 0;
    Repeat
      N := SysRead(Fd, IBuf[0], BufMax);
      If (N > 0) And (KLen + N <= KeepMax) Then
      Begin
        Move(IBuf[0], Keep[KLen], N);
        KLen := KLen + N;
      End;
    Until N <= 0;
    If OptBytes Then
    Begin
      K := KLen - OptN;
      If K < 0 Then K := 0;
    End
    Else
    Begin
      Lines := 0;
      K := KLen;
      While (K > 0) And (Lines <= OptN) Do
      Begin
        Dec(K);
        If Keep[K] = Sep Then Inc(Lines);
        If Lines > OptN Then Begin Inc(K); Break; End;
      End;
      If Lines <= OptN Then K := 0;
    End;
    For N := 0 To K - 1 Do PutB(Keep[N]);
    CloseIn(Fd);
    Exit;
  End;
  Lines := 0;
  Left := OptN;
  If Left > 0 Then
    Repeat
      N := SysRead(Fd, IBuf[0], BufMax);
      If N > 0 Then
        For K := 0 To N - 1 Do
        Begin
          If Left <= 0 Then Break;
          B := IBuf[K];
          PutB(B);
          If OptBytes Then Dec(Left)
          Else If B = Sep Then Dec(Left);
        End;
    Until (N <= 0) Or (Left <= 0);
  CloseIn(Fd);
End;

Procedure RunHead;
Var I : LongInt;
Begin
  ParseHT('head [-n N] [-c N] [-qv] [file...]');
  If NFiles = 0 Then HeadOne('-', 1)
  Else For I := 1 To NFiles Do HeadOne(Files[I], I);
End;

{ ---------------------------- tail ---------------------------- }

Procedure TailOne(Const Name : String; Idx : LongInt);
Var
  Fd, N, K, Start, Lines : LongInt;
  Sep : Byte;
Begin
  Fd := OpenIn(Name);
  If Fd < 0 Then Exit;
  Header(Name, Idx);
  Sep := 10;
  If OptZ Then Sep := 0;
  KLen := 0;
  Repeat
    N := SysRead(Fd, IBuf[0], BufMax);
    If N > 0 Then
    Begin
      If KLen + N > KeepMax Then
      Begin
        { garder la moitie finale }
        Move(Keep[KLen Div 2], Keep[0], KLen - KLen Div 2);
        KLen := KLen - KLen Div 2;
      End;
      Move(IBuf[0], Keep[KLen], N);
      KLen := KLen + N;
    End;
  Until N <= 0;
  If OptPlus Then
  Begin
    Start := 0;
    If OptBytes Then
    Begin
      Start := OptN - 1;
      If Start < 0 Then Start := 0;
    End
    Else
    Begin
      Lines := 1;
      While (Lines < OptN) And (Start < KLen) Do
      Begin
        If Keep[Start] = Sep Then Inc(Lines);
        Inc(Start);
      End;
    End;
  End
  Else If OptBytes Then
  Begin
    Start := KLen - OptN;
    If Start < 0 Then Start := 0;
  End
  Else
  Begin
    Start := KLen;
    Lines := 0;
    If OptN > 0 Then
    Begin
      If (KLen > 0) And (Keep[KLen - 1] = Sep) Then Dec(Start);
      While Start > 0 Do
      Begin
        If Keep[Start - 1] = Sep Then
        Begin
          Inc(Lines);
          If Lines >= OptN Then Break;
        End;
        Dec(Start);
      End;
      If (Start > 0) And (Lines < OptN) Then Start := 0;
    End;
  End;
  For K := Start To KLen - 1 Do PutB(Keep[K]);
  CloseIn(Fd);
End;

Procedure Follow;
Var
  I, Fd, N, K : LongInt;
  Pos : Array[1..64] Of LongInt;
  St : TSysStat;
Begin
  Flush;
  For I := 1 To NFiles Do
    If SysStat(Files[I], St) = 0 Then Pos[I] := St.Size Else Pos[I] := 0;
  While True Do
  Begin
    SysSleep(1);
    For I := 1 To NFiles Do
      If SysStat(Files[I], St) = 0 Then
      Begin
        If St.Size < Pos[I] Then Pos[I] := 0;
        If St.Size > Pos[I] Then
        Begin
          Fd := SysOpen(Files[I], O_RDONLY, 0);
          If Fd >= 0 Then
          Begin
            SysLSeek(Fd, Pos[I], SEEK_SET);
            Repeat
              N := SysRead(Fd, IBuf[0], BufMax);
              If N > 0 Then
              Begin
                For K := 0 To N - 1 Do PutB(IBuf[K]);
                Pos[I] := Pos[I] + N;
              End;
            Until N <= 0;
            SysClose(Fd);
            Flush;
          End;
        End;
      End;
  End;
End;

Procedure RunTail;
Var I : LongInt;
Begin
  ParseHT('tail [-n [+]N] [-c [+]N] [-fqv] [file...]');
  If NFiles = 0 Then TailOne('-', 1)
  Else For I := 1 To NFiles Do TailOne(Files[I], I);
  If OptF And (NFiles > 0) Then Follow;
End;

{ ---------------------------- cut ---------------------------- }

Var
  RLo, RHi : Array[1..64] Of LongInt;
  NR : LongInt;

Procedure ParseList(Const L : String);
Var
  K, V, A, B : LongInt;
  Cur : String;
  Procedure Item(Const T : String);
  Var D : LongInt;
  Begin
    If NR >= 64 Then Exit;
    D := Pos('-', T);
    Inc(NR);
    If D = 0 Then
    Begin
      RLo[NR] := ToNum(T); RHi[NR] := RLo[NR];
    End
    Else
    Begin
      If D = 1 Then RLo[NR] := 1 Else RLo[NR] := ToNum(Copy(T, 1, D - 1));
      If D = Length(T) Then RHi[NR] := 2147483647
      Else RHi[NR] := ToNum(Copy(T, D + 1, 255));
    End;
  End;
Begin
  NR := 0;
  Cur := '';
  For K := 1 To Length(L) Do
    If L[K] = ',' Then
    Begin
      Item(Cur);
      Cur := '';
    End
    Else Cur := Cur + L[K];
  If Cur <> '' Then Item(Cur);
  If NR = 0 Then Usage('cut -b|-c|-f list [-d delim] [-s] [file...]');
End;

Function InList(P : LongInt) : Boolean;
Var K : LongInt; R : Boolean;
Begin
  R := False;
  For K := 1 To NR Do
    If (P >= RLo[K]) And (P <= RHi[K]) Then R := True;
  If OptCompl Then R := Not R;
  InList := R;
End;

Procedure CutLine(Const L : String);
Var
  K, P, Fld, Cnt : LongInt;
  Cur : String;
  Any : Boolean;
Begin
  If Mode <> 'f' Then
  Begin
    P := 0;
    For K := 1 To Length(L) Do
    Begin
      If (Mode = 'b') Or ((Ord(L[K]) And $C0) <> $80) Then Inc(P);
      If InList(P) Then PutB(Ord(L[K]));
    End;
    PutB(10);
    Exit;
  End;
  If Pos(OptDelim, L) = 0 Then
  Begin
    If Not OptS Then Begin PutS(L); PutB(10); End;
    Exit;
  End;
  Fld := 1;
  Cur := '';
  Any := False;
  Cnt := 0;
  For K := 1 To Length(L) + 1 Do
  Begin
    If (K > Length(L)) Or (L[K] = OptDelim) Then
    Begin
      If InList(Fld) Then
      Begin
        If Any Then PutS(OutDelim);
        PutS(Cur);
        Any := True;
      End;
      Inc(Fld);
      Cur := '';
    End
    Else Cur := Cur + L[K];
  End;
  PutB(10);
End;

Var
  RdPos, RdLen : LongInt;

Function ReadLineFd(Fd : LongInt; Var L : String) : Boolean;
Var Got : Boolean; B : Byte;
Begin
  L := '';
  Got := False;
  While True Do
  Begin
    If RdPos >= RdLen Then
    Begin
      RdLen := SysRead(Fd, IBuf[0], BufMax);
      RdPos := 0;
      If RdLen <= 0 Then
      Begin
        RdLen := 0;
        Break;
      End;
    End;
    B := IBuf[RdPos];
    Inc(RdPos);
    Got := True;
    If B = 10 Then Break;
    If Length(L) < 250 Then L := L + Chr(B);
  End;
  ReadLineFd := Got;
End;

Procedure RunCut;
Var
  I, W, Fd : LongInt;
  A : String;
  L : String;
Begin
  Mode := ' ';
  OptDelim := #9;
  OutDelim := '';
  OptS := False;
  OptCompl := False;
  NFiles := 0;
  NR := 0;
  I := 1;
  While I < SysArgCount Do
  Begin
    A := SysArgStr(I);
    If (A = '--help') Or (A = '/?') Then
      Usage('cut -b|-c|-f list [-d delim] [-s] [file...]')
    Else If A = '-s' Then OptS := True
    Else If A = '--complement' Then OptCompl := True
    Else If Copy(A, 1, 19) = '--output-delimiter=' Then
      OutDelim := Copy(A, 20, 255)
    Else If (Length(A) >= 2) And (Copy(A, 1, 2) = '-d') Then
    Begin
      If Length(A) > 2 Then OptDelim := A[3]
      Else
      Begin
        Inc(I);
        If I < SysArgCount Then OptDelim := SysArgStr(I)[1];
      End;
    End
    Else If (Length(A) >= 2) And ((Copy(A, 1, 2) = '-b') Or
      (Copy(A, 1, 2) = '-c') Or (Copy(A, 1, 2) = '-f')) Then
    Begin
      Mode := A[2];
      If Length(A) > 2 Then ParseList(Copy(A, 3, 255))
      Else
      Begin
        Inc(I);
        If I < SysArgCount Then ParseList(SysArgStr(I));
      End;
    End
    Else If (Length(A) > 1) And (A[1] = '-') Then
      Usage('cut -b|-c|-f list [-d delim] [-s] [file...]')
    Else If NFiles < 64 Then
    Begin
      Inc(NFiles);
      Files[NFiles] := A;
    End;
    Inc(I);
  End;
  If (Mode = ' ') Or (NR = 0) Then
    Usage('cut -b|-c|-f list [-d delim] [-s] [file...]');
  If OutDelim = '' Then OutDelim := OptDelim;
  If NFiles = 0 Then
  Begin
    NFiles := 1;
    Files[1] := '-';
  End;
  For I := 1 To NFiles Do
  Begin
    Fd := OpenIn(Files[I]);
    If Fd >= 0 Then
    Begin
      RdPos := 0;
      RdLen := 0;
      While ReadLineFd(Fd, L) Do CutLine(L);
      CloseIn(Fd);
    End;
  End;
End;

{ ---------------------------- paste ---------------------------- }

Procedure RunPaste;
Var
  I, W, K, Fd : LongInt;
  A, L, Delims : String;
  Ser : Boolean;
  Fds : Array[1..64] Of LongInt;
  DI : LongInt;
  Row : String;
  Got, Have : Boolean;
  First : Boolean;
  Ch : Byte;
Begin
  Delims := #9;
  Ser := False;
  NFiles := 0;
  I := 1;
  While I < SysArgCount Do
  Begin
    A := SysArgStr(I);
    If (A = '--help') Or (A = '/?') Then Usage('paste [-s] [-d list] file...')
    Else If A = '--serial' Then Ser := True
    Else If (Length(A) > 1) And (A[1] = '-') And (A[2] In ['s', 'd']) Then
    Begin
      { options groupees : -s, -d liste, -sd: }
      W := 2;
      While W <= Length(A) Do
      Begin
        If A[W] = 's' Then Ser := True
        Else If A[W] = 'd' Then
        Begin
          If W < Length(A) Then Delims := Copy(A, W + 1, 255)
          Else
          Begin
            Inc(I);
            If I < SysArgCount Then Delims := SysArgStr(I);
          End;
          W := Length(A);
        End
        Else Usage('paste [-s] [-d list] file...');
        Inc(W);
      End;
    End
    Else If (A = '-') Or (A[1] <> '-') Then
    Begin
      If NFiles < 64 Then
      Begin
        Inc(NFiles);
        Files[NFiles] := A;
      End;
    End
    Else Usage('paste [-s] [-d list] file...');
    Inc(I);
  End;
  If NFiles = 0 Then
  Begin
    NFiles := 1;
    Files[1] := '-';
  End;
  If Ser Then
  Begin
    For I := 1 To NFiles Do
    Begin
      Fd := OpenIn(Files[I]);
      If Fd >= 0 Then
      Begin
        RdPos := 0; RdLen := 0;
        First := True;
        DI := 0;
        While ReadLineFd(Fd, L) Do
        Begin
          If Not First Then
          Begin
            PutB(Ord(Delims[(DI Mod Length(Delims)) + 1]));
            Inc(DI);
          End;
          PutS(L);
          First := False;
        End;
        PutB(10);
        CloseIn(Fd);
      End;
    End;
    Exit;
  End;
  { paste parallele : un descripteur par fichier, lecture octet par octet
    (les tubes et l'entree standard sont admis) }
  For I := 1 To NFiles Do
  Begin
    Fds[I] := OpenIn(Files[I]);
    If Fds[I] < 0 Then Fds[I] := -2;
  End;
  While True Do
  Begin
    Row := '';
    Got := False;
    For I := 1 To NFiles Do
    Begin
      L := '';
      If Fds[I] <> -2 Then
      Begin
        Have := False;
        While True Do
        Begin
          K := SysRead(Fds[I], Ch, 1);
          If K <= 0 Then
          Begin
            Fds[I] := -2;
            Break;
          End;
          Have := True;
          If Ch = 10 Then Break;
          If Length(L) < 250 Then L := L + Chr(Ch);
        End;
        If Have Then Got := True;
      End;
      If I > 1 Then Row := Row + Delims[((I - 2) Mod Length(Delims)) + 1];
      Row := Row + L;
    End;
    If Not Got Then Break;
    PutS(Row);
    PutB(10);
  End;
End;

BEGIN
  Prog := SysArgStr(0);
  While Pos('/', Prog) > 0 Do Prog := Copy(Prog, Pos('/', Prog) + 1, 255);
  Rc := 0;
  OLen := 0;
  OptZ := False;
  If Prog = 'wc' Then RunWc
  Else If Prog = 'head' Then RunHead
  Else If Prog = 'tail' Then RunTail
  Else If Prog = 'cut' Then RunCut
  Else If Prog = 'paste' Then RunPaste
  Else Usage('wc | head | tail | cut | paste  (nom du programme)');
  Flush;
  SysExit(Rc);
END.
