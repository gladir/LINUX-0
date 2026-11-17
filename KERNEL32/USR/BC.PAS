{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2026
  @website(https://www.gladir.com/linux-0)
  @abstract(Target: LPC -3X)
  @description: bc : calculatrice a precision arbitraire (langage bc POSIX et
   extensions GNU courantes) : scale, ibase, obase, last, variables et
   tableaux a noms de plusieurs lettres, define / auto / return, if else
   while for break continue halt quit print, ++ -- += etc., && || !,
   length scale sqrt read, chaines, commentaires, bibliotheque -l
   (s c a l e j). Options : -l -q -s -w -i, fichiers puis entree standard.
   Variable BC_LINE_LENGTH (70 par defaut, 0 : pas de coupure). }

Program Bc;

Const
  MaxNames = 600;
  MaxSave = 6000;
  MaxArgs = 24;
  MaxDepth = 800;
  InBufSize = 8191;

Type
  PLong = ^LongInt;

Var
  { sortie }
  OB : Array[0..8191] Of Byte;
  OLen, OCol, LineLen : LongInt;
  { entree }
  InFd : LongInt;
  InBuf : Array[0..InBufSize] Of Byte;
  InPos, InCnt : LongInt;
  InEof, Interactive, MathLib, Quiet : Boolean;
  Files : Array[0..31] Of String[200];
  NFiles, FileI : LongInt;
  { source courante }
  Src : LongInt;                 { adresse du tampon }
  SLen, SPos, SCap : LongInt;
  IsMain : Boolean;
  LineNo : LongInt;
  { noms }
  NameS : Array[0..MaxNames - 1] Of String[32];
  NNames : LongInt;
  VarV : Array[0..MaxNames - 1] Of LongInt;     { nombre ou 0 }
  ArrV : Array[0..MaxNames - 1] Of LongInt;     { tableau ou 0 }
  FunB : Array[0..MaxNames - 1] Of LongInt;     { corps copie ou 0 }
  FunL : Array[0..MaxNames - 1] Of LongInt;
  FunVoid : Array[0..MaxNames - 1] Of Boolean;
  FunNP : Array[0..MaxNames - 1] Of LongInt;
  FunP : Array[0..MaxNames - 1, 0..MaxArgs - 1] Of LongInt;
  FunPA : Array[0..MaxNames - 1, 0..MaxArgs - 1] Of Boolean;
  { pile de sauvegarde des variables dynamiques }
  SvName : Array[0..MaxSave - 1] Of LongInt;
  SvVal, SvArr : Array[0..MaxSave - 1] Of LongInt;
  NSave : LongInt;
  { variables speciales }
  ScaleV, IBase, OBase : LongInt;
  LastV : LongInt;
  { etat d'execution }
  NX : LongInt;                  { > 0 : analyse sans execution }
  Failed : Boolean;
  Ctl : LongInt;                 { 0 rien, 1 break, 2 continue, 3 return,
                                   4 halt }
  RetVal : LongInt;
  Depth : LongInt;
  CurFun : String[40];
  { lvalue du dernier primaire }
  LvOk : Boolean;
  LvKind, LvIdx, LvSub : LongInt;
  AsgStart, AsgEnd, VoidStart, VoidEnd : LongInt;
  ExitCode : LongInt;
  SynFlag : Boolean;

Procedure Flush;
Begin
  If OLen > 0 Then SysWrite(1, OB[0], OLen);
  OLen := 0;
End;

Procedure RawC(C : Char);
Begin
  If OLen >= 8000 Then Flush;
  OB[OLen] := Ord(C);
  Inc(OLen);
  If C = #10 Then OCol := 0 Else Inc(OCol);
End;

Procedure OutC(C : Char);
Begin
  If (LineLen > 0) And (OCol >= LineLen - 2) And (C <> #10) Then
  Begin
    RawC('\');
    RawC(#10);
  End;
  RawC(C);
End;

Procedure OutRaw(Const S : String);
Var K : LongInt;
Begin
  For K := 1 To Length(S) Do RawC(S[K]);
End;

Procedure Warn(Const S : String);
Begin
  Flush;
  SysPut(2, S + #10);
End;

Procedure MathErr(Const S : String);
Begin
  If Failed Then Exit;
  Failed := True;
  ExitCode := 1;
  If CurFun = '' Then CurFun := '(main)';
  Warn('Runtime error (func=' + CurFun + ', adr=' + '0): ' + S);
End;

{$I BIGNUM.INC}

Procedure SynErr(Const S : String);
Var L : String;
Begin
  If Failed Then Exit;
  Failed := True;
  SynFlag := True;
  ExitCode := 1;
  Str(LineNo, L);
  Warn('(standard_in) ' + L + ': ' + S);
End;

{ ---- entree ---- }

Function ReadByte : LongInt;
Begin
  If InPos >= InCnt Then
  Begin
    If InEof Then
    Begin
      ReadByte := -1;
      Exit;
    End;
    If Interactive Then Flush;
    InCnt := SysRead(InFd, InBuf[0], InBufSize);
    InPos := 0;
    If InCnt <= 0 Then
    Begin
      InCnt := 0;
      InEof := True;
      ReadByte := -1;
      Exit;
    End;
  End;
  ReadByte := InBuf[InPos];
  Inc(InPos);
End;

Function OpenNext : Boolean;
Begin
  OpenNext := False;
  While FileI < NFiles Do
  Begin
    InFd := SysOpen(Files[FileI], 0, 0);
    Inc(FileI);
    If InFd < 0 Then
    Begin
      Warn('bc: cannot open file ' + Files[FileI - 1]);
      ExitCode := 1;
      Continue;
    End;
    InPos := 0;
    InCnt := 0;
    InEof := False;
    OpenNext := True;
    Exit;
  End;
  If FileI = NFiles Then
  Begin
    Inc(FileI);
    If NFiles > 0 Then
    Begin
      InFd := 0;
      InPos := 0;
      InCnt := 0;
      InEof := False;
      OpenNext := True;
    End;
  End;
End;

Procedure Grow(Need : LongInt);
Var NC, K, P : LongInt; Pt : Pointer;
Begin
  If Need <= SCap Then Exit;
  NC := SCap * 2;
  If NC < Need Then NC := Need + 1024;
  GetMem(Pt, NC + 4);
  P := LongInt(Pt);
  For K := 0 To SLen - 1 Do Mem[0:P + K] := Mem[0:Src + K];
  If Src <> 0 Then FreeMem(Pointer(Src), 1);
  Src := P;
  SCap := NC;
End;

{ ajoute une ligne de l'entree au tampon source ; Faux si fin }
Function Refill : Boolean;
Var B : LongInt;
Begin
  Refill := False;
  If Not IsMain Then Exit;
  While True Do
  Begin
    B := ReadByte;
    If B < 0 Then
    Begin
      If Not OpenNext Then Exit;
      Continue;
    End;
    Grow(SLen + 2);
    Mem[0:Src + SLen] := B;
    Inc(SLen);
    Refill := True;
    If B = 10 Then
    Begin
      Inc(LineNo);
      Exit;
    End;
    Break;
  End;
  { continuer jusqu'a la fin de la ligne }
  While True Do
  Begin
    B := ReadByte;
    If B < 0 Then Exit;
    Grow(SLen + 2);
    Mem[0:Src + SLen] := B;
    Inc(SLen);
    If B = 10 Then
    Begin
      Inc(LineNo);
      Exit;
    End;
  End;
End;

Function Cur : Char;
Begin
  While SPos >= SLen Do
    If Not Refill Then
    Begin
      Cur := #0;
      Exit;
    End;
  Cur := Chr(Mem[0:Src + SPos]);
End;

{ caractere K positions plus loin ; ne lit jamais d'entree supplementaire
  (l'analyse a l'avance ne doit pas bloquer en mode interactif) }
Function CurAt(K : LongInt) : Char;
Begin
  If K = 0 Then
  Begin
    CurAt := Cur;
    Exit;
  End;
  If SPos + K >= SLen Then CurAt := #0
  Else CurAt := Chr(Mem[0:Src + SPos + K]);
End;

Procedure Adv;
Begin
  If SPos < SLen Then Inc(SPos);
End;

{ espaces, tabulations, \newline, commentaires ; newline = fin d'instruction }
Procedure SkipBlank;
Var C : Char;
Begin
  While True Do
  Begin
    C := Cur;
    If (C = ' ') Or (C = #9) Or (C = #13) Then Adv
    Else If (C = '\') And (CurAt(1) = #10) Then
    Begin
      Adv;
      Adv;
    End
    Else If (C = '/') And (CurAt(1) = '*') Then
    Begin
      Adv;
      Adv;
      While Not ((Cur = '*') And (CurAt(1) = '/')) Do
      Begin
        If Cur = #0 Then
        Begin
          SynErr('comment not terminated');
          Exit;
        End;
        Adv;
      End;
      Adv;
      Adv;
    End
    Else If C = '#' Then
    Begin
      While (Cur <> #10) And (Cur <> #0) Do Adv;
    End
    Else Break;
  End;
End;

{ en plus : sauts de ligne et points-virgules entre instructions }
Procedure SkipSep;
Begin
  While True Do
  Begin
    SkipBlank;
    If (Cur = #10) Or (Cur = ';') Then Adv Else Break;
  End;
End;

Procedure SkipNl;
Begin
  While True Do
  Begin
    SkipBlank;
    If Cur = #10 Then Adv Else Break;
  End;
End;

{ ---- noms ---- }

Function NameIdx(Const S : String) : LongInt;
Var K : LongInt;
Begin
  For K := 0 To NNames - 1 Do
    If NameS[K] = S Then
    Begin
      NameIdx := K;
      Exit;
    End;
  If NNames >= MaxNames Then
  Begin
    SynErr('too many names');
    NameIdx := 0;
    Exit;
  End;
  NameS[NNames] := S;
  VarV[NNames] := 0;
  ArrV[NNames] := 0;
  FunB[NNames] := 0;
  FunVoid[NNames] := False;
  FunNP[NNames] := 0;
  NameIdx := NNames;
  Inc(NNames);
End;

Function IsLetter(C : Char) : Boolean;
Begin
  IsLetter := (C >= 'a') And (C <= 'z');
End;

Function IsIdent(C : Char) : Boolean;
Begin
  IsIdent := ((C >= 'a') And (C <= 'z')) Or ((C >= '0') And (C <= '9')) Or
             (C = '_');
End;

Function ReadIdent : String;
Var S : String;
Begin
  S := '';
  While IsIdent(Cur) Do
  Begin
    If Length(S) < 31 Then S := S + Cur;
    Adv;
  End;
  ReadIdent := S;
End;

Function Run : Boolean;
Begin
  Run := (NX = 0) And (Not Failed);
End;

{ ---- tableaux ---- }

Function ArrNew(Cap : LongInt) : LongInt;
Var P, K : LongInt;
Begin
  P := NAlloc(Cap * 4 + 4);
  MemL[0:P] := Cap;
  For K := 1 To Cap Do MemL[0:P + K * 4] := 0;
  ArrNew := P;
End;

Function ArrGet(A, I : LongInt) : LongInt;
Begin
  ArrGet := 0;
  If (A <> 0) And (I >= 0) And (I < MemL[0:A]) Then
    ArrGet := MemL[0:A + 4 + I * 4];
End;

Function ArrCopy(A : LongInt) : LongInt;
Var P, K, Cap, V : LongInt;
Begin
  If A = 0 Then
  Begin
    ArrCopy := 0;
    Exit;
  End;
  Cap := MemL[0:A];
  P := ArrNew(Cap);
  For K := 0 To Cap - 1 Do
  Begin
    V := MemL[0:A + 4 + K * 4];
    If V <> 0 Then MemL[0:P + 4 + K * 4] := NCopy(V);
  End;
  ArrCopy := P;
End;

Procedure ArrFree(A : LongInt);
Var K : LongInt;
Begin
  If A = 0 Then Exit;
  For K := 0 To MemL[0:A] - 1 Do NFree(MemL[0:A + 4 + K * 4]);
  NFree(A);
End;

{ affecte l'element I (le nombre V devient propriete du tableau) }
Procedure ArrSet(Var A : LongInt; I, V : LongInt);
Var N, K, Cap : LongInt;
Begin
  If I < 0 Then
  Begin
    NFree(V);
    Exit;
  End;
  If A = 0 Then A := ArrNew(I + 8);
  If I >= MemL[0:A] Then
  Begin
    Cap := MemL[0:A] * 2;
    If Cap <= I Then Cap := I + 8;
    N := ArrNew(Cap);
    For K := 0 To MemL[0:A] - 1 Do
      MemL[0:N + 4 + K * 4] := MemL[0:A + 4 + K * 4];
    NFree(A);
    A := N;
  End;
  NFree(MemL[0:A + 4 + I * 4]);
  MemL[0:A + 4 + I * 4] := V;
End;

{ ---- valeurs ---- }

Function Zero : LongInt;
Begin
  Zero := NNew(0, 0);
End;

Function One : LongInt;
Begin
  One := NFromLong(1);
End;

Function ToLongChecked(P : LongInt; Lo, Hi : LongInt; Const Nm : String)
  : LongInt;
Var V : LongInt;
Begin
  V := NToLong(P);
  If (V < Lo) Or (V > Hi) Then
  Begin
    MathErr(Nm + ' out of range');
    V := Lo;
  End;
  ToLongChecked := V;
End;

Function GetVar(I : LongInt) : LongInt;
Begin
  If VarV[I] = 0 Then GetVar := Zero Else GetVar := NCopy(VarV[I]);
End;

Procedure SetVar(I, V : LongInt);
Begin
  NFree(VarV[I]);
  VarV[I] := V;
End;

{ lecture d'une lvalue ; Kind : 1 scale 2 ibase 3 obase 4 last 5 var
  6 element de tableau }
Function LvGet(Kind, Idx, Sub : LongInt) : LongInt;
Begin
  Case Kind Of
    1 : LvGet := NFromLong(ScaleV);
    2 : LvGet := NFromLong(IBase);
    3 : LvGet := NFromLong(OBase);
    4 : If LastV = 0 Then LvGet := Zero Else LvGet := NCopy(LastV);
    5 : LvGet := GetVar(Idx);
    6 : If ArrGet(ArrV[Idx], Sub) = 0 Then LvGet := Zero
        Else LvGet := NCopy(ArrGet(ArrV[Idx], Sub));
  Else
    LvGet := Zero;
  End;
End;

{ affectation : V reste la propriete de l'appelant }
Procedure LvSet(Kind, Idx, Sub, V : LongInt);
Begin
  Case Kind Of
    1 : ScaleV := ToLongChecked(V, 0, 100000, 'scale');
    2 : IBase := ToLongChecked(V, 2, 16, 'ibase');
    3 : OBase := ToLongChecked(V, 2, 1000, 'obase');
    4 : Begin
          NFree(LastV);
          LastV := NCopy(V);
        End;
    5 : SetVar(Idx, NCopy(V));
    6 : ArrSet(ArrV[Idx], Sub, NCopy(V));
  End;
End;

{ ---- analyse des expressions ---- }

Function ParseOr : LongInt; Forward;
Function ReadNumberStdin : LongInt; Forward;
Function ParseAssign : LongInt; Forward;
Procedure ExecStmt; Forward;
Procedure ExecBlockBody; Forward;

Function IsDigitIn(C : Char; Base : LongInt) : Boolean;
Var V : LongInt;
Begin
  V := -1;
  If (C >= '0') And (C <= '9') Then V := Ord(C) - 48
  Else If (C >= 'A') And (C <= 'Z') Then V := Ord(C) - 55;
  IsDigitIn := (V >= 0) And (V < 16);
End;

Function DigitVal(C : Char) : LongInt;
Begin
  If (C >= '0') And (C <= '9') Then DigitVal := Ord(C) - 48
  Else DigitVal := Ord(C) - 55;
End;

{ constante numerique ; Cur est un chiffre ou un point }
Function ParseNumber : LongInt;
Var Ip, Fp, T, X, Base, Fd, K, Nd : LongInt; Dot : Boolean; D : LongInt;
    Num, Den, Q : LongInt; C : Char;
Begin
  Base := IBase;
  Ip := NNew(0, 0);
  Fd := 0;
  Dot := False;
  { un chiffre seul garde sa valeur quelle que soit la base d'entree }
  K := 0;
  Nd := 0;
  While True Do
  Begin
    C := CurAt(K);
    If IsDigitIn(C, 16) Then Inc(Nd)
    Else If C <> '.' Then Break;
    Inc(K);
  End;
  While True Do
  Begin
    C := Cur;
    If (C = '\') And (CurAt(1) = #10) Then
    Begin
      Adv;
      Adv;
      Continue;
    End;
    If C = '.' Then
    Begin
      If Dot Then Break;
      Dot := True;
      Adv;
      Continue;
    End;
    If Not IsDigitIn(C, 16) Then Break;
    D := DigitVal(C);
    If (D >= Base) And (Nd > 1) Then D := Base - 1;
    { Ip := Ip * Base + D }
    T := NFromLong(Base);
    X := NMul(Ip, T, 0);
    NFree(Ip);
    NFree(T);
    T := NFromLong(D);
    Ip := NAdd(X, T, False);
    NFree(X);
    NFree(T);
    If Dot Then Inc(Fd);
    Adv;
  End;
  If Base = 10 Then
  Begin
    T := NWithScale(Ip, Fd);
    NFree(Ip);
    ParseNumber := T;
    Exit;
  End;
  If Fd = 0 Then
  Begin
    ParseNumber := Ip;
    Exit;
  End;
  { Ip / Base^Fd tronque a Fd chiffres }
  Num := NFromLong(Base);
  Den := NFromLong(Fd);
  T := NPow(Num, Den, 0);
  NFree(Num);
  NFree(Den);
  Q := NDiv(Ip, T, Fd);
  NFree(Ip);
  NFree(T);
  ParseNumber := Q;
End;

Function ParseString : String;
Var S : String;
Begin
  S := '';
  Adv;
  While (Cur <> '"') Do
  Begin
    If Cur = #0 Then
    Begin
      SynErr('string not terminated');
      Break;
    End;
    If Length(S) < 250 Then S := S + Cur;
    Adv;
  End;
  Adv;
  ParseString := S;
End;

Procedure PrintEsc(Const S : String);
Var K : LongInt; C : Char;
Begin
  K := 1;
  While K <= Length(S) Do
  Begin
    C := S[K];
    If (C = '\') And (K < Length(S)) Then
    Begin
      Inc(K);
      Case S[K] Of
        'n' : RawC(#10);
        't' : RawC(#9);
        'a' : RawC(#7);
        'b' : RawC(#8);
        'f' : RawC(#12);
        'r' : RawC(#13);
        'e' : RawC(#27);
        '\' : RawC('\');
        '"' : RawC('"');
        'q' : RawC('"');
      Else
        RawC('\');
        RawC(S[K]);
      End;
    End
    Else RawC(C);
    Inc(K);
  End;
End;

Function CallFunction(Fi : LongInt; Var Args : Array Of LongInt;
                      NArgs : LongInt) : LongInt; Forward;

{ lit les arguments d'un appel f(...) : Cur est apres la parenthese
  ouvrante. Rend le nombre d'arguments ; Args : nombres ou tableaux. }
Function ParseArgs(Fi : LongInt; Var Args : Array Of LongInt) : LongInt;
Var N, Ix, V : LongInt; Nm : String; P : LongInt;
Begin
  N := 0;
  SkipBlank;
  If Cur = ')' Then
  Begin
    Adv;
    ParseArgs := 0;
    Exit;
  End;
  While True Do
  Begin
    SkipBlank;
    { argument tableau : identifiant seul suivi de , ou ) }
    P := SPos;
    If IsLetter(Cur) And (N < MaxArgs) And Run And (FunB[Fi] <> 0) And
       (N < FunNP[Fi]) And FunPA[Fi, N] Then
    Begin
      Nm := ReadIdent;
      SkipBlank;
      If (Cur = '[') And (CurAt(1) = ']') Then
      Begin
        Adv;
        Adv;
        SkipBlank;
      End;
      If (Cur = ',') Or (Cur = ')') Then
      Begin
        Ix := NameIdx(Nm);
        Args[N] := ArrCopy(ArrV[Ix]);
        If Args[N] = 0 Then Args[N] := ArrNew(8);
        Inc(N);
        If Cur = ',' Then
        Begin
          Adv;
          Continue;
        End;
        Adv;
        Break;
      End;
      SPos := P;
    End;
    V := ParseOr;
    If N < MaxArgs Then
    Begin
      Args[N] := V;
      Inc(N);
    End
    Else NFree(V);
    SkipBlank;
    If Cur = ',' Then
    Begin
      Adv;
      Continue;
    End;
    If Cur = ')' Then
    Begin
      Adv;
      Break;
    End;
    SynErr('syntax error');
    Break;
  End;
  ParseArgs := N;
End;

Function ParsePrimary : LongInt;
Var C : Char; Nm : String; Ix, V, T, N, Sub : LongInt;
    Args : Array[0..MaxArgs] Of LongInt;
    K, St : LongInt;
Begin
  LvOk := False;
  SkipBlank;
  C := Cur;
  ParsePrimary := 0;
  If Failed Then Exit;
  If (C >= '0') And (C <= '9') Or (C = '.') Or
     ((C >= 'A') And (C <= 'F')) Then
  Begin
    If C = '.' Then
      If Not IsDigitIn(CurAt(1), 16) Then
      Begin
        { "." seul : last }
        Adv;
        LvOk := True;
        LvKind := 4;
        LvIdx := 0;
        If Run Then ParsePrimary := LvGet(4, 0, 0);
        Exit;
      End;
    V := ParseNumber;
    If Run Then ParsePrimary := V Else NFree(V);
    Exit;
  End;
  If C = '(' Then
  Begin
    Adv;
    V := ParseOr;
    SkipBlank;
    If Cur <> ')' Then SynErr('syntax error')
    Else Adv;
    ParsePrimary := V;
    LvOk := False;
    Exit;
  End;
  If C = '"' Then
  Begin
    SynErr('syntax error');
    Exit;
  End;
  If IsLetter(C) Then
  Begin
    St := SPos;
    Nm := ReadIdent;
    SkipBlank;
    If (Nm = 'length') Or (Nm = 'sqrt') Or (Nm = 'scale') Or (Nm = 'read') Then
    Begin
      If Cur = '(' Then
      Begin
        Adv;
        If Nm = 'read' Then
        Begin
          SkipBlank;
          If Cur = ')' Then Adv Else SynErr('syntax error');
          If Run Then ParsePrimary := ReadNumberStdin Else ParsePrimary := 0;
          Exit;
        End;
        { scale(x) avec x tableau n'est pas gere }
        V := ParseOr;
        SkipBlank;
        If Cur <> ')' Then SynErr('syntax error')
        Else Adv;
        If Run Then
        Begin
          If Nm = 'length' Then
          Begin
            N := NLen(V);
            If NSc(V) > N Then N := NSc(V);
            If N = 0 Then N := 1;
            T := NFromLong(N);
          End
          Else If Nm = 'scale' Then T := NFromLong(NSc(V))
          Else T := NSqrt(V, ScaleV);
          NFree(V);
          ParsePrimary := T;
        End
        Else NFree(V);
        Exit;
      End;
      If Nm = 'scale' Then
      Begin
        LvOk := True;
        LvKind := 1;
        If Run Then ParsePrimary := LvGet(1, 0, 0);
        Exit;
      End;
      SynErr('syntax error');
      Exit;
    End;
    If Nm = 'ibase' Then
    Begin
      LvOk := True;
      LvKind := 2;
      If Run Then ParsePrimary := LvGet(2, 0, 0);
      Exit;
    End;
    If Nm = 'obase' Then
    Begin
      LvOk := True;
      LvKind := 3;
      If Run Then ParsePrimary := LvGet(3, 0, 0);
      Exit;
    End;
    If Nm = 'last' Then
    Begin
      LvOk := True;
      LvKind := 4;
      If Run Then ParsePrimary := LvGet(4, 0, 0);
      Exit;
    End;
    Ix := NameIdx(Nm);
    If Cur = '(' Then
    Begin
      Adv;
      N := ParseArgs(Ix, Args);
      If Failed Then
      Begin
        For K := 0 To N - 1 Do NFree(Args[K]);
        Exit;
      End;
      If Run Then
      Begin
        If FunB[Ix] = 0 Then
        Begin
          MathErr('Function ' + Nm + ' not defined.');
          For K := 0 To N - 1 Do NFree(Args[K]);
          Exit;
        End;
        V := CallFunction(Ix, Args, N);
        If FunVoid[Ix] Then
        Begin
          VoidStart := St;
          VoidEnd := SPos;
        End;
        ParsePrimary := V;
      End
      Else
        For K := 0 To N - 1 Do NFree(Args[K]);
      Exit;
    End;
    If Cur = '[' Then
    Begin
      Adv;
      SkipBlank;
      If Cur = ']' Then
      Begin
        { nom de tableau nu : hors appel, on lit l'element 0 }
        Adv;
        LvOk := False;
        If Run Then ParsePrimary := Zero;
        Exit;
      End;
      T := ParseOr;
      SkipBlank;
      If Cur <> ']' Then SynErr('syntax error')
      Else Adv;
      If Run Then
      Begin
        Sub := NToLong(T);
        If (Sub < 0) Or ((NIsZero(T) = False) And (NNeg(T))) Then
        Begin
          MathErr('Array subscript out of bounds.');
          Sub := 0;
        End;
        NFree(T);
        LvOk := True;
        LvKind := 6;
        LvIdx := Ix;
        LvSub := Sub;
        ParsePrimary := LvGet(6, Ix, Sub);
      End
      Else
      Begin
        NFree(T);
        LvOk := True;
        LvKind := 6;
        LvIdx := Ix;
        LvSub := 0;
      End;
      Exit;
    End;
    LvOk := True;
    LvKind := 5;
    LvIdx := Ix;
    If Run Then ParsePrimary := LvGet(5, Ix, 0);
    Exit;
  End;
  SynErr('syntax error');
End;

Function ParsePostfix : LongInt;
Var V, K, One_, T, Kind, Idx, Sub : LongInt; Neg : Boolean;
Begin
  V := ParsePrimary;
  If (Not Failed) And LvOk Then
  Begin
    SkipBlank;
    If ((Cur = '+') And (CurAt(1) = '+')) Or
       ((Cur = '-') And (CurAt(1) = '-')) Then
    Begin
      Neg := Cur = '-';
      Adv;
      Adv;
      Kind := LvKind;
      Idx := LvIdx;
      Sub := LvSub;
      If Run Then
      Begin
        One_ := NFromLong(1);
        T := NAdd(V, One_, Neg);
        NFree(One_);
        LvSet(Kind, Idx, Sub, T);
        NFree(T);
      End;
      LvOk := False;
    End;
  End;
  ParsePostfix := V;
End;

Function ParseUnary : LongInt;
Var V, T, One_, Kind, Idx, Sub : LongInt; Neg : Boolean;
Begin
  SkipBlank;
  If Failed Then
  Begin
    ParseUnary := 0;
    Exit;
  End;
  If (Cur = '-') And (CurAt(1) <> '-') Then
  Begin
    Adv;
    V := ParseUnary;
    If Run Then
    Begin
      T := NNegate(V);
      NFree(V);
      V := T;
    End;
    LvOk := False;
    ParseUnary := V;
    Exit;
  End;
  If ((Cur = '+') And (CurAt(1) = '+')) Or
     ((Cur = '-') And (CurAt(1) = '-')) Then
  Begin
    Neg := Cur = '-';
    Adv;
    Adv;
    V := ParsePrimary;
    If Not LvOk Then
    Begin
      SynErr('syntax error');
      ParseUnary := V;
      Exit;
    End;
    Kind := LvKind;
    Idx := LvIdx;
    Sub := LvSub;
    If Run Then
    Begin
      One_ := NFromLong(1);
      T := NAdd(V, One_, Neg);
      NFree(One_);
      NFree(V);
      V := T;
      LvSet(Kind, Idx, Sub, V);
    End;
    LvOk := False;
    ParseUnary := V;
    Exit;
  End;
  ParseUnary := ParsePostfix;
End;

Function ParsePow : LongInt;
Var B, E, T : LongInt;
Begin
  B := ParseUnary;
  SkipBlank;
  If (Cur = '^') And (Not Failed) And (CurAt(1) <> '=') Then
  Begin
    Adv;
    E := ParsePow;
    If Run Then
    Begin
      If NSc(E) > 0 Then
      Begin
        T := NRescale(E, 0);
        NFree(E);
        E := T;
      End;
      T := NPow(B, E, ScaleV);
      NFree(B);
      NFree(E);
      B := T;
    End
    Else
    Begin
      NFree(B);
      NFree(E);
      B := 0;
    End;
    LvOk := False;
  End;
  ParsePow := B;
End;

Function ParseMul : LongInt;
Var L, R, T : LongInt; Op : Char;
Begin
  L := ParsePow;
  While Not Failed Do
  Begin
    SkipBlank;
    Op := Cur;
    If ((Op = '*') Or (Op = '/') Or (Op = '%')) And (CurAt(1) <> '=') Then
    Begin
      Adv;
      R := ParsePow;
      If Run Then
      Begin
        If Op = '*' Then T := NMul(L, R, ScaleV)
        Else If Op = '/' Then T := NDiv(L, R, ScaleV)
        Else T := NMod(L, R, ScaleV);
        NFree(L);
        NFree(R);
        L := T;
      End
      Else
      Begin
        NFree(L);
        NFree(R);
        L := 0;
      End;
      LvOk := False;
    End
    Else Break;
  End;
  ParseMul := L;
End;

Function ParseAdd : LongInt;
Var L, R, T : LongInt; Op : Char;
Begin
  L := ParseMul;
  While Not Failed Do
  Begin
    SkipBlank;
    Op := Cur;
    If ((Op = '+') Or (Op = '-')) And (CurAt(1) <> '=') And
       (CurAt(1) <> Op) Then
    Begin
      Adv;
      R := ParseMul;
      If Run Then
      Begin
        T := NAdd(L, R, Op = '-');
        NFree(L);
        NFree(R);
        L := T;
      End
      Else
      Begin
        NFree(L);
        NFree(R);
        L := 0;
      End;
      LvOk := False;
    End
    Else Break;
  End;
  ParseAdd := L;
End;

Function ParseAssign : LongInt;
Var L, R, T, Kind, Idx, Sub, St : LongInt; Op : Char; Lv : Boolean;
Begin
  SkipBlank;
  St := SPos;
  L := ParseAdd;
  SkipBlank;
  If Failed Then
  Begin
    ParseAssign := L;
    Exit;
  End;
  Lv := LvOk;
  Kind := LvKind;
  Idx := LvIdx;
  Sub := LvSub;
  Op := Cur;
  If Lv And (((Op = '=') And (CurAt(1) <> '=')) Or
     (((Op = '+') Or (Op = '-') Or (Op = '*') Or (Op = '/') Or (Op = '%') Or
       (Op = '^')) And (CurAt(1) = '='))) Then
  Begin
    Adv;
    If Op <> '=' Then Adv;
    R := ParseAssign;
    If Run Then
    Begin
      If Op = '=' Then
      Begin
        NFree(L);
        L := R;
      End
      Else
      Begin
        Case Op Of
          '+' : T := NAdd(L, R, False);
          '-' : T := NAdd(L, R, True);
          '*' : T := NMul(L, R, ScaleV);
          '/' : T := NDiv(L, R, ScaleV);
          '%' : T := NMod(L, R, ScaleV);
        Else
          Begin
            If NSc(R) > 0 Then
            Begin
              T := NRescale(R, 0);
              NFree(R);
              R := T;
            End;
            T := NPow(L, R, ScaleV);
          End;
        End;
        NFree(L);
        NFree(R);
        L := T;
      End;
      If Not Failed Then LvSet(Kind, Idx, Sub, L);
    End
    Else
    Begin
      NFree(L);
      NFree(R);
      L := 0;
    End;
    AsgStart := St;
    SkipBlank;
    AsgEnd := SPos;
    LvOk := False;
  End;
  ParseAssign := L;
End;

Function ParseRel : LongInt;
Var L, R, C, T : LongInt; Op : String;
Begin
  L := ParseAssign;
  While Not Failed Do
  Begin
    SkipBlank;
    Op := '';
    If (Cur = '<') Or (Cur = '>') Or ((Cur = '=') And (CurAt(1) = '=')) Or
       ((Cur = '!') And (CurAt(1) = '=')) Then
    Begin
      Op := Cur;
      Adv;
      If Cur = '=' Then
      Begin
        Op := Op + '=';
        Adv;
      End;
    End
    Else Break;
    R := ParseAssign;
    If Run Then
    Begin
      C := NCmp(L, R);
      NFree(L);
      NFree(R);
      T := 0;
      If Op = '<' Then T := Ord(C < 0)
      Else If Op = '>' Then T := Ord(C > 0)
      Else If Op = '<=' Then T := Ord(C <= 0)
      Else If Op = '>=' Then T := Ord(C >= 0)
      Else If Op = '==' Then T := Ord(C = 0)
      Else T := Ord(C <> 0);
      L := NFromLong(T);
    End
    Else
    Begin
      NFree(L);
      NFree(R);
      L := 0;
    End;
    LvOk := False;
  End;
  ParseRel := L;
End;

Function ParseNot : LongInt;
Var V, T : LongInt;
Begin
  SkipBlank;
  If (Cur = '!') And (CurAt(1) <> '=') Then
  Begin
    Adv;
    V := ParseNot;
    If Run Then
    Begin
      T := NFromLong(Ord(NIsZero(V)));
      NFree(V);
      V := T;
    End;
    LvOk := False;
    ParseNot := V;
    Exit;
  End;
  ParseNot := ParseRel;
End;

Function ParseAnd : LongInt;
Var L, R, T : LongInt; Z : Boolean;
Begin
  L := ParseNot;
  While Not Failed Do
  Begin
    SkipBlank;
    If (Cur = '&') And (CurAt(1) = '&') Then
    Begin
      Adv;
      Adv;
      Z := Run And NIsZero(L);
      If Z Then Inc(NX);
      R := ParseNot;
      If Z Then Dec(NX);
      If Run Then
      Begin
        If Z Then T := NFromLong(0)
        Else T := NFromLong(Ord(Not NIsZero(R)));
        NFree(L);
        NFree(R);
        L := T;
      End
      Else
      Begin
        NFree(L);
        NFree(R);
        L := 0;
      End;
      LvOk := False;
    End
    Else Break;
  End;
  ParseAnd := L;
End;

Function ParseOr : LongInt;
Var L, R, T : LongInt; Z : Boolean;
Begin
  L := ParseAnd;
  While Not Failed Do
  Begin
    SkipBlank;
    If (Cur = '|') And (CurAt(1) = '|') Then
    Begin
      Adv;
      Adv;
      Z := Run And (Not NIsZero(L));
      If Z Then Inc(NX);
      R := ParseAnd;
      If Z Then Dec(NX);
      If Run Then
      Begin
        If Z Then T := NFromLong(1)
        Else T := NFromLong(Ord(Not NIsZero(R)));
        NFree(L);
        NFree(R);
        L := T;
      End
      Else
      Begin
        NFree(L);
        NFree(R);
        L := 0;
      End;
      LvOk := False;
    End
    Else Break;
  End;
  ParseOr := L;
End;

{ ---- read() ---- }

Function ReadNumberStdin : LongInt;
Var S : String; B : LongInt; Sp, Sl, Sc : LongInt; Sv : LongInt; M : Boolean;
    V : LongInt;
Begin
  S := '';
  If Interactive Then Flush;
  B := ReadByte;
  While (B >= 0) And (B <> 10) Do
  Begin
    If Length(S) < 200 Then S := S + Chr(B);
    B := ReadByte;
  End;
  { evaluer l'expression lue : on l'ajoute a un tampon temporaire }
  V := NFromLong(0);
  Sv := Src;
  Sp := SPos;
  Sl := SLen;
  Sc := SCap;
  M := IsMain;
  Src := NAlloc(Length(S) + 4);
  For B := 1 To Length(S) Do Mem[0:Src + B - 1] := Ord(S[B]);
  Mem[0:Src + Length(S)] := 10;
  SLen := Length(S) + 1;
  SCap := SLen;
  SPos := 0;
  IsMain := False;
  NFree(V);
  V := ParseOr;
  NFree(Src);
  Src := Sv;
  SPos := Sp;
  SLen := Sl;
  SCap := Sc;
  IsMain := M;
  ReadNumberStdin := V;
End;

{ ---- fonctions ---- }

Function CallFunction(Fi : LongInt; Var Args : Array Of LongInt;
                      NArgs : LongInt) : LongInt;
Var K, Base, Ix, SvSrc, SvPos, SvLen, SvCap : LongInt; SvMain : Boolean;
    SvName_ : String; V : LongInt; SvNx : LongInt;
Begin
  CallFunction := 0;
  If Depth >= MaxDepth Then
  Begin
    MathErr('stack overflow');
    For K := 0 To NArgs - 1 Do NFree(Args[K]);
    Exit;
  End;
  If NArgs <> FunNP[Fi] Then
  Begin
    MathErr('Parameter number mismatch');
    For K := 0 To NArgs - 1 Do NFree(Args[K]);
    Exit;
  End;
  Base := NSave;
  If Base + NArgs + 64 >= MaxSave Then
  Begin
    MathErr('stack overflow');
    Exit;
  End;
  { lier les parametres }
  For K := 0 To NArgs - 1 Do
  Begin
    Ix := FunP[Fi, K];
    SvName[NSave] := Ix;
    SvVal[NSave] := VarV[Ix];
    SvArr[NSave] := ArrV[Ix];
    Inc(NSave);
    VarV[Ix] := 0;
    ArrV[Ix] := 0;
    If FunPA[Fi, K] Then ArrV[Ix] := Args[K]
    Else VarV[Ix] := Args[K];
  End;
  SvSrc := Src;
  SvPos := SPos;
  SvLen := SLen;
  SvCap := SCap;
  SvMain := IsMain;
  SvName_ := CurFun;
  SvNx := NX;
  NX := 0;
  Src := FunB[Fi];
  SLen := FunL[Fi];
  SCap := SLen;
  SPos := 0;
  IsMain := False;
  CurFun := NameS[Fi];
  Inc(Depth);
  Ctl := 0;
  SkipNl;
  If Cur = '{' Then
  Begin
    Adv;
    ExecBlockBody;
  End
  Else SynErr('syntax error');
  Dec(Depth);
  { restaurer }
  V := 0;
  If Ctl = 3 Then
  Begin
    V := RetVal;
    RetVal := 0;
    Ctl := 0;
  End
  Else If Ctl = 4 Then
  Begin
    { halt : on laisse Ctl }
  End
  Else Ctl := 0;
  If (V = 0) And (Ctl <> 4) Then V := Zero;
  While NSave > Base Do
  Begin
    Dec(NSave);
    Ix := SvName[NSave];
    NFree(VarV[Ix]);
    ArrFree(ArrV[Ix]);
    VarV[Ix] := SvVal[NSave];
    ArrV[Ix] := SvArr[NSave];
  End;
  Src := SvSrc;
  SPos := SvPos;
  SLen := SvLen;
  SCap := SvCap;
  IsMain := SvMain;
  CurFun := SvName_;
  NX := SvNx;
  CallFunction := V;
End;

{ ---- instructions ---- }

Procedure SkipToEol;
Begin
  While (Cur <> #10) And (Cur <> #0) Do Adv;
End;

{ analyse "define" : Cur est apres le mot define }
Procedure DoDefine;
Var Nm : String; Ix, N, St, En, Depth_, K : LongInt; C : Char; Arr : Boolean;
    Pn : String; P : LongInt; Void : Boolean; Pt : Pointer;
Begin
  SkipBlank;
  Void := False;
  Nm := ReadIdent;
  If Nm = 'void' Then
  Begin
    Void := True;
    SkipBlank;
    Nm := ReadIdent;
  End;
  If Nm = '' Then
  Begin
    SynErr('syntax error');
    Exit;
  End;
  Ix := NameIdx(Nm);
  SkipBlank;
  If Cur <> '(' Then
  Begin
    SynErr('syntax error');
    Exit;
  End;
  Adv;
  N := 0;
  SkipBlank;
  If Cur = ')' Then Adv
  Else
    While True Do
    Begin
      SkipBlank;
      Pn := ReadIdent;
      If Pn = '' Then
      Begin
        SynErr('syntax error');
        Exit;
      End;
      Arr := False;
      SkipBlank;
      If Cur = '[' Then
      Begin
        Adv;
        SkipBlank;
        If Cur = ']' Then Adv Else SynErr('syntax error');
        Arr := True;
      End;
      If N < MaxArgs Then
      Begin
        FunP[Ix, N] := NameIdx(Pn);
        FunPA[Ix, N] := Arr;
        Inc(N);
      End;
      SkipBlank;
      If Cur = ',' Then
      Begin
        Adv;
        Continue;
      End;
      If Cur = ')' Then
      Begin
        Adv;
        Break;
      End;
      SynErr('syntax error');
      Exit;
    End;
  SkipNl;
  If Cur <> '{' Then
  Begin
    SynErr('syntax error');
    Exit;
  End;
  St := SPos;
  Inc(NX);
  ExecStmt;
  Dec(NX);
  If Failed Then Exit;
  En := SPos;
  { copie du corps }
  If FunB[Ix] <> 0 Then FreeMem(Pointer(FunB[Ix]), 1);
  GetMem(Pt, En - St + 8);
  P := LongInt(Pt);
  For K := 0 To En - St - 1 Do Mem[0:P + K] := Mem[0:Src + St + K];
  FunB[Ix] := P;
  FunL[Ix] := En - St;
  FunNP[Ix] := N;
  FunVoid[Ix] := Void;
End;

Procedure DoAuto;
Var Nm : String; Ix : LongInt; Arr : Boolean;
Begin
  While True Do
  Begin
    SkipBlank;
    Nm := ReadIdent;
    If Nm = '' Then
    Begin
      SynErr('syntax error');
      Exit;
    End;
    Ix := NameIdx(Nm);
    SkipBlank;
    Arr := False;
    If Cur = '[' Then
    Begin
      Adv;
      SkipBlank;
      If Cur = ']' Then Adv Else SynErr('syntax error');
      Arr := True;
    End;
    If Run Then
    Begin
      If NSave >= MaxSave - 2 Then
      Begin
        MathErr('stack overflow');
        Exit;
      End;
      SvName[NSave] := Ix;
      SvVal[NSave] := VarV[Ix];
      SvArr[NSave] := ArrV[Ix];
      Inc(NSave);
      VarV[Ix] := 0;
      ArrV[Ix] := 0;
    End;
    SkipBlank;
    If Cur = ',' Then
    Begin
      Adv;
      Continue;
    End;
    Break;
  End;
End;

{ expression : valeur imprimee si Prt (instruction), sinon rendue }
Procedure ExecExprStmt;
Var V, St : LongInt;
Begin
  SkipBlank;
  St := SPos;
  AsgStart := -1;
  AsgEnd := -2;
  VoidStart := -1;
  VoidEnd := -2;
  V := ParseOr;
  SkipBlank;
  If Failed Then
  Begin
    NFree(V);
    Exit;
  End;
  If Run Then
  Begin
    If (AsgStart = St) And (AsgEnd = SPos) Then NFree(V)
    Else If (VoidStart = St) And (VoidEnd = SPos) Then NFree(V)
    Else
    Begin
      NPrint(V, OBase);
      OutC(#10);
      NFree(LastV);
      LastV := V;
    End;
  End
  Else NFree(V);
End;

Function AtElse : Boolean;
Begin
  AtElse := (Cur = 'e') And (CurAt(1) = 'l') And (CurAt(2) = 's') And
            (CurAt(3) = 'e') And (Not IsIdent(CurAt(4)));
End;

Procedure EndStmt;
Begin
  SkipBlank;
  If AtElse Then
  Begin
  End
  Else If (Cur = ';') Or (Cur = #10) Then Adv
  Else If (Cur = '}') Or (Cur = #0) Then
  Begin
  End
  Else SynErr('syntax error');
End;

Procedure ExecBlockBody;
Begin
  { Cur est apres l'accolade ouvrante }
  While Not Failed Do
  Begin
    SkipSep;
    If Cur = '}' Then
    Begin
      Adv;
      Exit;
    End;
    If Cur = #0 Then
    Begin
      SynErr('syntax error');
      Exit;
    End;
    ExecStmt;
    If (Ctl <> 0) And (NX = 0) Then
    Begin
      { sauter la fin du bloc sans executer }
      Inc(NX);
      While Not Failed Do
      Begin
        SkipSep;
        If Cur = '}' Then
        Begin
          Adv;
          Break;
        End;
        If Cur = #0 Then Break;
        ExecStmt;
      End;
      Dec(NX);
      Exit;
    End;
  End;
End;

Function CondTrue(V : LongInt) : Boolean;
Begin
  CondTrue := Run And (Not NIsZero(V));
  NFree(V);
End;

Procedure DoIf;
Var V : LongInt; T : Boolean; P : LongInt; Nm : String;
Begin
  SkipBlank;
  If Cur <> '(' Then
  Begin
    SynErr('syntax error');
    Exit;
  End;
  Adv;
  V := ParseOr;
  SkipBlank;
  If Cur <> ')' Then
  Begin
    NFree(V);
    SynErr('syntax error');
    Exit;
  End;
  Adv;
  T := CondTrue(V);
  If Not T Then Inc(NX);
  SkipNl;
  ExecStmt;
  If Not T Then Dec(NX);
  { else ? }
  P := SPos;
  SkipSep;
  Nm := '';
  If IsLetter(Cur) Then Nm := ReadIdent;
  If Nm = 'else' Then
  Begin
    If T Then Inc(NX);
    SkipNl;
    ExecStmt;
    If T Then Dec(NX);
  End
  Else SPos := P;
End;

Procedure DoWhile;
Var V, Top : LongInt; T : Boolean; Guard : LongInt;
Begin
  SkipBlank;
  Top := SPos;
  If Cur <> '(' Then
  Begin
    SynErr('syntax error');
    Exit;
  End;
  While Not Failed Do
  Begin
    SPos := Top;
    Adv;
    V := ParseOr;
    SkipBlank;
    If Cur <> ')' Then
    Begin
      NFree(V);
      SynErr('syntax error');
      Exit;
    End;
    Adv;
    T := CondTrue(V);
    If Not T Then
    Begin
      Inc(NX);
      SkipNl;
      ExecStmt;
      Dec(NX);
      Break;
    End;
    SkipNl;
    ExecStmt;
    If Ctl = 1 Then
    Begin
      Ctl := 0;
      Break;
    End;
    If Ctl = 2 Then Ctl := 0;
    If Ctl <> 0 Then Break;
  End;
  If Ctl = 1 Then Ctl := 0;
  { positionner apres le corps : ils est deja apres si la condition a ete
    fausse ; apres un break, sauter le corps restant }
End;

Procedure DoFor;
Var V, CondPos, IncPos, BodyPos, EndPos : LongInt; T : Boolean;
Begin
  SkipBlank;
  If Cur <> '(' Then
  Begin
    SynErr('syntax error');
    Exit;
  End;
  Adv;
  SkipBlank;
  If Cur <> ';' Then NFree(ParseOr);
  SkipBlank;
  If Cur <> ';' Then
  Begin
    SynErr('syntax error');
    Exit;
  End;
  Adv;
  CondPos := SPos;
  { sauter la condition et l'increment pour trouver le corps }
  Inc(NX);
  SkipBlank;
  If Cur <> ';' Then NFree(ParseOr);
  SkipBlank;
  If Cur <> ';' Then
  Begin
    Dec(NX);
    SynErr('syntax error');
    Exit;
  End;
  Adv;
  IncPos := SPos;
  SkipBlank;
  If Cur <> ')' Then NFree(ParseOr);
  SkipBlank;
  If Cur <> ')' Then
  Begin
    Dec(NX);
    SynErr('syntax error');
    Exit;
  End;
  Adv;
  SkipNl;
  BodyPos := SPos;
  ExecStmt;
  EndPos := SPos;
  Dec(NX);
  If Failed Then Exit;
  While Not Failed Do
  Begin
    SPos := CondPos;
    SkipBlank;
    T := True;
    If Cur <> ';' Then
    Begin
      V := ParseOr;
      T := CondTrue(V);
    End;
    If Not T Then Break;
    SPos := BodyPos;
    ExecStmt;
    If Ctl = 1 Then
    Begin
      Ctl := 0;
      Break;
    End;
    If Ctl = 2 Then Ctl := 0;
    If Ctl <> 0 Then Break;
    SPos := IncPos;
    SkipBlank;
    If Cur <> ')' Then NFree(ParseOr);
  End;
  SPos := EndPos;
End;

Procedure DoPrint;
Var V : LongInt; S : String;
Begin
  While True Do
  Begin
    SkipBlank;
    If Cur = '"' Then
    Begin
      S := ParseString;
      If Run Then PrintEsc(S);
    End
    Else
    Begin
      V := ParseOr;
      If Run Then NPrint(V, OBase);
      NFree(V);
    End;
    SkipBlank;
    If Cur = ',' Then
    Begin
      Adv;
      Continue;
    End;
    Break;
  End;
End;

Procedure ExecStmt;
Var C : Char; Nm : String; P : LongInt; V : LongInt; S : String;
Begin
  SkipSep;
  If Failed Then Exit;
  C := Cur;
  If C = #0 Then Exit;
  If C = '{' Then
  Begin
    Adv;
    ExecBlockBody;
    Exit;
  End;
  If C = '"' Then
  Begin
    S := ParseString;
    If Run Then
    Begin
      OutRaw(S);
    End;
    EndStmt;
    Exit;
  End;
  If IsLetter(C) Then
  Begin
    P := SPos;
    Nm := ReadIdent;
    If Nm = 'define' Then
    Begin
      If NX = 0 Then DoDefine
      Else
      Begin
        SynErr('syntax error');
      End;
      Exit;
    End
    Else If Nm = 'auto' Then
    Begin
      DoAuto;
      EndStmt;
      Exit;
    End
    Else If Nm = 'if' Then
    Begin
      DoIf;
      Exit;
    End
    Else If Nm = 'while' Then
    Begin
      DoWhile;
      Exit;
    End
    Else If Nm = 'for' Then
    Begin
      DoFor;
      Exit;
    End
    Else If Nm = 'break' Then
    Begin
      If Run Then Ctl := 1;
      EndStmt;
      Exit;
    End
    Else If Nm = 'continue' Then
    Begin
      If Run Then Ctl := 2;
      EndStmt;
      Exit;
    End
    Else If Nm = 'halt' Then
    Begin
      If Run Then Ctl := 4;
      EndStmt;
      Exit;
    End
    Else If Nm = 'quit' Then
    Begin
      If Run Then Ctl := 4;
      EndStmt;
      Exit;
    End
    Else If Nm = 'return' Then
    Begin
      SkipBlank;
      If (Cur = #10) Or (Cur = ';') Or (Cur = '}') Or (Cur = #0) Then
        V := Zero
      Else V := ParseOr;
      If Run Then
      Begin
        If Depth = 0 Then
        Begin
          NFree(V);
          SynErr('Return outside of a function.');
        End
        Else
        Begin
          RetVal := V;
          Ctl := 3;
        End;
      End
      Else NFree(V);
      EndStmt;
      Exit;
    End
    Else If Nm = 'print' Then
    Begin
      DoPrint;
      EndStmt;
      Exit;
    End
    Else If (Nm = 'limits') Or (Nm = 'warranty') Then
    Begin
      If Run Then
        OutRaw('BC_BASE_MAX     = 1000' + #10 + 'BC_DIM_MAX      = 65535' +
               #10 + 'BC_SCALE_MAX    = 100000' + #10 +
               'BC_STRING_MAX   = 65535' + #10);
      EndStmt;
      Exit;
    End;
    SPos := P;
  End;
  ExecExprStmt;
  EndStmt;
End;


{ ---- bibliotheque mathematique (-l) ---- }

Const
  LibN = 117;
  Lib : Array[0..LibN - 1] Of PChar = (
    'scale = 20',
    'define e(x) {',
    '  auto a, d, e, f, i, m, n, v, z',
    '  if (x < 0) { m = 1; x = -x }',
    '  z = scale',
    '  scale = 4 + z + .44 * x',
    '  while (x > 1) { f += 1; x /= 2 }',
    '  v = 1 + x',
    '  a = x',
    '  d = 1',
    '  for (i = 2; 1; i++) {',
    '    e = (a *= x) / (d *= i)',
    '    if (e == 0) {',
    '      if (f > 0) while (f--) v = v * v',
    '      scale = z',
    '      if (m) return (1 / v)',
    '      return (v / 1)',
    '    }',
    '    v += e',
    '  }',
    '}',
    'define l(x) {',
    '  auto e, f, i, m, n, v, z',
    '  if (x <= 0) { return ((1 - 10 ^ scale) / 1) }',
    '  z = scale',
    '  scale = 4 + z',
    '  for (f = 2; x >= 2; f *= 2) x = sqrt(x)',
    '  for (; x <= .5; f *= 2) x = sqrt(x)',
    '  v = n = (x - 1) / (x + 1)',
    '  m = n * n',
    '  e = n',
    '  for (i = 3; 1; i += 2) {',
    '    e *= m',
    '    if (e / i == 0) {',
    '      scale = z',
    '      return (f * v / 1)',
    '    }',
    '    v += e / i',
    '  }',
    '}',
    'define s(x) {',
    '  auto e, i, m, n, s, v, z',
    '  z = scale',
    '  scale = 1.1 * z + 2',
    '  v = a(1)',
    '  if (x < 0) { m = 1; x = -x }',
    '  scale = 0',
    '  n = (x / v + 2) / 4',
    '  x = x - 4 * n * v',
    '  if (n % 2) x = -x',
    '  scale = z + 2',
    '  v = e = x',
    '  s = -x * x',
    '  for (i = 3; 1; i += 2) {',
    '    e *= s / (i * (i - 1))',
    '    if (e == 0) {',
    '      scale = z',
    '      if (m) return (-v / 1)',
    '      return (v / 1)',
    '    }',
    '    v += e',
    '  }',
    '}',
    'define c(x) {',
    '  auto z',
    '  z = scale',
    '  scale = z * 1.2',
    '  x = s(x + 2 * a(1))',
    '  scale = z',
    '  return (x / 1)',
    '}',
    'define a(x) {',
    '  auto e, i, m, n, p, s, t, v, z',
    '  if (x == 0) return (0)',
    '  z = scale',
    '  if (x < 0) { m = 1; x = -x }',
    '  scale = z + 8',
    '  while (x > .01) {',
    '    x = x / (1 + sqrt(1 + x * x))',
    '    n += 1',
    '  }',
    '  v = p = x',
    '  s = -x * x',
    '  for (i = 3; 1; i += 2) {',
    '    p *= s',
    '    t = p / i',
    '    if (t == 0) break',
    '    v += t',
    '  }',
    '  while (n--) v *= 2',
    '  scale = z',
    '  if (m) return (-v / 1)',
    '  return (v / 1)',
    '}',
    'define j(n, x) {',
    '  auto a, d, e, f, i, m, v, z',
    '  z = scale',
    '  scale = 0',
    '  n = n / 1',
    '  if (n < 0) { n = -n; if (n % 2 == 1) m = 1 }',
    '  a = 1',
    '  for (i = 2; i <= n; i++) a *= i',
    '  scale = 1000',
    '  a = x ^ n / (2 ^ n * a)',
    '  v = a',
    '  f = -x * x / 4',
    '  scale = z + length(a) - scale(a) + 8',
    '  for (i = 1; 1; i++) {',
    '    e = (a *= f / (i * (n + i)))',
    '    if (e == 0) {',
    '      scale = z',
    '      if (m) return (-v / 1)',
    '      return (v / 1)',
    '    }',
    '    v += e',
    '  }',
    '}'
  );

Function LenP(P : PChar) : LongInt;
Var N : LongInt;
Begin
  N := 0;
  While P^ <> #0 Do
  Begin
    Inc(N);
    Inc(P);
  End;
  LenP := N;
End;

{ execute la bibliotheque comme une entree interne }
Procedure LoadLib;
Var K, L, P, T, J : LongInt; Pt : Pointer; Q : PChar; Sv, Sp, Sl, Sc : LongInt;
    M : Boolean;
Begin
  L := 0;
  For K := 0 To LibN - 1 Do L := L + LenP(Lib[K]) + 1;
  GetMem(Pt, L + 8);
  P := LongInt(Pt);
  T := 0;
  For K := 0 To LibN - 1 Do
  Begin
    Q := Lib[K];
    For J := 0 To LenP(Q) - 1 Do
    Begin
      Mem[0:P + T] := Ord(Q[J]);
      Inc(T);
    End;
    Mem[0:P + T] := 10;
    Inc(T);
  End;
  Sv := Src;
  Sp := SPos;
  Sl := SLen;
  Sc := SCap;
  M := IsMain;
  Src := P;
  SLen := T;
  SCap := T;
  SPos := 0;
  IsMain := False;
  While (SPos < SLen) And (Not Failed) Do
  Begin
    SkipSep;
    If SPos >= SLen Then Break;
    ExecStmt;
  End;
  Src := Sv;
  SPos := Sp;
  SLen := Sl;
  SCap := Sc;
  IsMain := M;
End;

Procedure Usage;
Begin
  SysPut(1, 'usage: bc [-hilqsvw] [long-options] [file ...]' + #10 +
         '  -h  --help         print this usage and exit' + #10 +
         '  -i  --interactive  force interactive mode' + #10 +
         '  -l  --mathlib      use the predefined math routines' + #10 +
         '  -q  --quiet        don''t print initial banner' + #10 +
         '  -s  --standard     non-POSIX goes to non-standard' + #10 +
         '  -w  --warn         warn about non-POSIX extensions' + #10 +
         '  -v  --version      print version information and exit' + #10);
  SysExit(0);
End;

Var
  I, K, St : LongInt;
  A, E : String;
  Tm : TSysTermios;
  Done : Boolean;
Begin
  OLen := 0;
  OCol := 0;
  LineLen := 70;
  E := SysGetEnv('BC_LINE_LENGTH');
  If E <> '' Then
  Begin
    LineLen := 0;
    For K := 1 To Length(E) Do
      If (E[K] >= '0') And (E[K] <= '9') Then
        LineLen := LineLen * 10 + Ord(E[K]) - 48;
    If LineLen = 1 Then LineLen := 70;
  End;
  NFiles := 0;
  FileI := 0;
  NNames := 0;
  NSave := 0;
  Src := 0;
  SLen := 0;
  SPos := 0;
  SCap := 0;
  IsMain := True;
  LineNo := 1;
  ScaleV := 0;
  IBase := 10;
  OBase := 10;
  LastV := 0;
  NX := 0;
  Failed := False;
  Ctl := 0;
  Depth := 0;
  CurFun := '';
  ExitCode := 0;
  SynFlag := False;
  MathLib := False;
  Quiet := False;
  Interactive := False;
  InEof := False;
  InPos := 0;
  InCnt := 0;
  I := 1;
  While I < SysArgCount Do
  Begin
    A := SysArgStr(I);
    If (A <> '') And (A[1] = '-') And (Length(A) > 1) Then
    Begin
      If (A = '--help') Then Usage
      Else If A = '--mathlib' Then MathLib := True
      Else If A = '--quiet' Then Quiet := True
      Else If A = '--interactive' Then Interactive := True
      Else If (A = '--standard') Or (A = '--warn') Then
      Begin
      End
      Else If A = '--version' Then
      Begin
        SysPut(1, 'bc 1.07.1' + #10);
        SysExit(0);
      End
      Else If A = '--' Then
      Begin
        Inc(I);
        While I < SysArgCount Do
        Begin
          If NFiles < 32 Then Files[NFiles] := SysArgStr(I);
          Inc(NFiles);
          Inc(I);
        End;
        Break;
      End
      Else
        For K := 2 To Length(A) Do
          Case A[K] Of
            'l' : MathLib := True;
            'q' : Quiet := True;
            'i' : Interactive := True;
            's', 'w' : ;
            'v' : Begin
                    SysPut(1, 'bc 1.07.1' + #10);
                    SysExit(0);
                  End;
            'h' : Usage;
          Else
            SysPut(2, 'bc: invalid option -- ' + A[K] + #10);
            Usage;
          End;
    End
    Else
    Begin
      If NFiles < 32 Then Files[NFiles] := A;
      Inc(NFiles);
    End;
    Inc(I);
  End;
  If NFiles > 32 Then NFiles := 32;
  If SysTcGetAttr(0, Tm) = 0 Then Interactive := True;
  If MathLib Then
  Begin
    LoadLib;
    Failed := False;
  End;
  If Interactive And (Not Quiet) And (NFiles = 0) Then
    OutRaw('bc 1.07.1' + #10 +
           'This is free software with ABSOLUTELY NO WARRANTY.' + #10 +
           'For details type `warranty''.' + #10);
  IsMain := True;
  If NFiles = 0 Then
  Begin
    FileI := 1;
    InFd := 0;
  End
  Else If Not OpenNext Then
  Begin
    Flush;
    SysExit(1);
  End;
  Done := False;
  While Not Done Do
  Begin
    If SPos >= SLen Then
    Begin
      SLen := 0;
      SPos := 0;
    End;
    Failed := False;
    If Cur = #0 Then Break;
    SkipSep;
    If (Cur = #0) And (SPos >= SLen) Then
    Begin
      If Not Refill Then Break;
      Continue;
    End;
    St := SPos;
    ExecStmt;
    If Failed Then
    Begin
      Depth := 0;
      NSave := 0;
      NX := 0;
      If SynFlag Then
      Begin
        If (SPos = 0) Or (Mem[0:Src + SPos - 1] <> 10) Then
        Begin
          SkipToEol;
          Adv;
        End;
      End
      Else
      Begin
        { erreur d'execution : on saute le reste de l'instruction }
        SPos := St;
        Failed := False;
        Inc(NX);
        ExecStmt;
        Dec(NX);
        If Failed Then
        Begin
          Failed := False;
          SkipToEol;
          Adv;
        End;
      End;
      SynFlag := False;
      Ctl := 0;
    End;
    If Ctl = 4 Then Done := True;
    Ctl := 0;
    If Interactive Then Flush;
  End;
  Flush;
  SysExit(ExitCode);
End.
