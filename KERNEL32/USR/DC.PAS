{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2026
  @website(https://www.gladir.com/linux-0)
  @abstract(Target: LPC -3X)
  @description: dc : calculatrice a pile, precision arbitraire (GNU dc).
   Nombres (_ pour negatif), chaines [..], + - * / % ~ ^ | v, c d r R z Z X,
   p n P f a, s l S L (registres et piles de registres), : ; (tableaux),
   k K i I o O, x ? q Q, comparaisons < > = !< !> != suivies d'un registre
   (et e pour sinon), # commentaire.
   dc [-V] [-h] [-e expression] [-f fichier] [fichier ...] }

Program Dc;

Const
  MaxStk = 20000;
  MaxReg = 256;
  MaxRD = 200;
  InBufSize = 8191;

Var
  OB : Array[0..8191] Of Byte;
  OLen, OCol, LineLen : LongInt;
  { pile : Kind 1 nombre, 2 chaine (adresse : longueur puis octets) }
  SK, SV : Array[0..MaxStk - 1] Of LongInt;
  SP : LongInt;
  { registres : pile de (kind, valeur) et tableaux }
  RK, RV : Array[0..MaxReg - 1, 0..MaxRD - 1] Of LongInt;
  RT : Array[0..MaxReg - 1] Of LongInt;
  RA : Array[0..MaxReg - 1] Of LongInt;      { tableau d'elements }
  ScaleV, IBase, OBase : LongInt;
  Quit_ : LongInt;                           { niveaux a quitter }
  Failed : Boolean;
  InFd, InPos, InCnt : LongInt;
  InBuf : Array[0..InBufSize] Of Byte;
  InEof : Boolean;
  ExitCode, Level : LongInt;

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

Procedure Warn(Const S : String);
Begin
  Flush;
  SysPut(2, 'dc: ' + S + #10);
End;

Procedure MathErr(Const S : String);
Begin
  If Failed Then Exit;
  Failed := True;
  ExitCode := 1;
  Warn(S);
End;

{$I BIGNUM.INC}

{ ---- chaines (bloc : [0..3] longueur, octets a partir de 4) ---- }

Function SNew(Len : LongInt) : LongInt;
Var P : LongInt;
Begin
  P := NAlloc(Len + 4);
  MemL[0:P] := Len;
  SNew := P;
End;

Function SFromBytes(Src, Len : LongInt) : LongInt;
Var P, K : LongInt;
Begin
  P := SNew(Len);
  For K := 0 To Len - 1 Do Mem[0:P + 4 + K] := Mem[0:Src + K];
  SFromBytes := P;
End;

Function SCopy(P : LongInt) : LongInt;
Begin
  SCopy := SFromBytes(P + 4, MemL[0:P]);
End;

Function SLen(P : LongInt) : LongInt;
Begin
  SLen := MemL[0:P];
End;

{ ---- pile ---- }

Procedure FreeItem(K, V : LongInt);
Begin
  If K = 1 Then NFree(V) Else If K = 2 Then NFree(V);
End;

Function CopyItem(K, V : LongInt) : LongInt;
Begin
  If K = 1 Then CopyItem := NCopy(V) Else CopyItem := SCopy(V);
End;

Procedure Push(K, V : LongInt);
Begin
  If SP >= MaxStk Then
  Begin
    MathErr('stack overflow');
    FreeItem(K, V);
    Exit;
  End;
  SK[SP] := K;
  SV[SP] := V;
  Inc(SP);
End;

Function Need(N : LongInt) : Boolean;
Begin
  If SP < N Then
  Begin
    Warn('stack empty');
    ExitCode := 1;
    Need := False;
  End
  Else Need := True;
End;

{ depile un nombre (une chaine n'est pas un nombre : 0 avec avertissement) }
Function PopNum : LongInt;
Var K, V : LongInt;
Begin
  PopNum := 0;
  If Not Need(1) Then Exit;
  Dec(SP);
  K := SK[SP];
  V := SV[SP];
  If K = 1 Then PopNum := V
  Else
  Begin
    NFree(V);
    Warn('non numeric value');
    ExitCode := 1;
    PopNum := NNew(0, 0);
  End;
End;

{ ---- sortie ---- }

Procedure PrintItem(K, V : LongInt; Nl : Boolean);
Var I : LongInt;
Begin
  If K = 1 Then NPrint(V, OBase)
  Else
    For I := 0 To MemL[0:V] - 1 Do RawC(Chr(Mem[0:V + 4 + I]));
  If Nl Then RawC(#10);
End;

{ P : octets (poids fort d'abord) du nombre entier en base 256 }
Procedure PrintBytes(K, V : LongInt);
Var I, Cnt, N, R, X, Tl : LongInt; Ib, Dg : LongInt;
Begin
  If K = 2 Then
  Begin
    For I := 0 To MemL[0:V] - 1 Do RawC(Chr(Mem[0:V + 4 + I]));
    Exit;
  End;
  N := MemL[0:V] - MemL[0:V + 4];
  If N <= 0 Then
  Begin
    Exit;
  End;
  Ib := NAlloc(N + 4);
  For I := 0 To N - 1 Do Mem[0:Ib + I] := Mem[0:V + 12 + MemL[0:V + 4] + I];
  Dg := NAlloc(N + 4);
  Cnt := 0;
  Tl := N;
  While (Tl > 0) And (Mem[0:Ib + Tl - 1] = 0) Do Dec(Tl);
  While Tl > 0 Do
  Begin
    R := 0;
    For I := Tl - 1 DownTo 0 Do
    Begin
      X := R * 10 + Mem[0:Ib + I];
      Mem[0:Ib + I] := X Div 256;
      R := X Mod 256;
    End;
    Mem[0:Dg + Cnt] := R;
    Inc(Cnt);
    While (Tl > 0) And (Mem[0:Ib + Tl - 1] = 0) Do Dec(Tl);
  End;
  For I := Cnt - 1 DownTo 0 Do RawC(Chr(Mem[0:Dg + I]));
  NFree(Dg);
  NFree(Ib);
End;

{ ---- nombres ---- }

Function DigitOf(C : Char) : LongInt;
Begin
  DigitOf := -1;
  If (C >= '0') And (C <= '9') Then DigitOf := Ord(C) - 48
  Else If (C >= 'A') And (C <= 'F') Then DigitOf := Ord(C) - 55;
End;

{ lit un nombre dans S a partir de Pos ; Pos est place apres }
Function ReadNum(S, Len : LongInt; Var Pos : LongInt) : LongInt;
Var Ip, T, X, Fd, D, Num, Den, Q : LongInt; Dot, Neg : Boolean; C : Char;
Begin
  Neg := False;
  If Chr(Mem[0:S + Pos]) = '_' Then
  Begin
    Neg := True;
    Inc(Pos);
  End;
  Ip := NNew(0, 0);
  Fd := 0;
  Dot := False;
  While Pos < Len Do
  Begin
    C := Chr(Mem[0:S + Pos]);
    If (C = '\') And (Pos + 1 < Len) And (Mem[0:S + Pos + 1] = 10) Then
    Begin
      Pos := Pos + 2;
      Continue;
    End;
    If C = '.' Then
    Begin
      If Dot Then Break;
      Dot := True;
      Inc(Pos);
      Continue;
    End;
    D := DigitOf(C);
    If D < 0 Then Break;
    If D >= IBase Then D := IBase - 1;
    T := NFromLong(IBase);
    X := NMul(Ip, T, 0);
    NFree(Ip);
    NFree(T);
    T := NFromLong(D);
    Ip := NAdd(X, T, False);
    NFree(X);
    NFree(T);
    If Dot Then Inc(Fd);
    Inc(Pos);
  End;
  If IBase = 10 Then
  Begin
    T := NWithScale(Ip, Fd);
    NFree(Ip);
    Ip := T;
  End
  Else If Fd > 0 Then
  Begin
    Num := NFromLong(IBase);
    Den := NFromLong(Fd);
    T := NPow(Num, Den, 0);
    NFree(Num);
    NFree(Den);
    Q := NDiv(Ip, T, Fd);
    NFree(Ip);
    NFree(T);
    Ip := Q;
  End;
  If Neg And (MemL[0:Ip] > 0) Then Mem[0:Ip + 8] := 1;
  ReadNum := Ip;
End;

Function ToSmall(P : LongInt; Lo, Hi : LongInt) : LongInt;
Var V : LongInt;
Begin
  V := NToLong(P);
  If (V < Lo) Or (V > Hi) Then
  Begin
    MathErr('value out of range');
    V := Lo;
  End;
  ToSmall := V;
End;

{ ---- registres ---- }

Procedure RegPush(R, K, V : LongInt);
Begin
  If RT[R] >= MaxRD Then
  Begin
    MathErr('register stack overflow');
    FreeItem(K, V);
    Exit;
  End;
  RK[R, RT[R]] := K;
  RV[R, RT[R]] := V;
  Inc(RT[R]);
End;

Procedure RegSet(R, K, V : LongInt);
Begin
  If RT[R] = 0 Then RegPush(R, K, V)
  Else
  Begin
    FreeItem(RK[R, RT[R] - 1], RV[R, RT[R] - 1]);
    RK[R, RT[R] - 1] := K;
    RV[R, RT[R] - 1] := V;
  End;
End;

{ ---- lecture des lignes ---- }

Function ReadByte : LongInt;
Begin
  If InPos >= InCnt Then
  Begin
    If InEof Then
    Begin
      ReadByte := -1;
      Exit;
    End;
    Flush;
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

{ une ligne dans un bloc neuf : Buf, longueur L (saut de ligne compris) }
Function ReadLine(Var Buf : LongInt; Var L : LongInt) : Boolean;
Var Cap, B, K, P : LongInt; Pt : Pointer;
Begin
  Cap := 256;
  GetMem(Pt, Cap + 8);
  P := LongInt(Pt);
  L := 0;
  ReadLine := False;
  While True Do
  Begin
    B := ReadByte;
    If B < 0 Then
    Begin
      If L = 0 Then
      Begin
        FreeMem(Pointer(P), 1);
        Exit;
      End;
      Break;
    End;
    If L >= Cap Then
    Begin
      Cap := Cap * 2;
      GetMem(Pt, Cap + 8);
      For K := 0 To L - 1 Do Mem[0:LongInt(Pt) + K] := Mem[0:P + K];
      FreeMem(Pointer(P), 1);
      P := LongInt(Pt);
    End;
    Mem[0:P + L] := B;
    Inc(L);
    If B = 10 Then Break;
  End;
  Buf := P;
  ReadLine := True;
End;

{ ---- tableaux de registres ---- }

Function ArrGetD(A, I : LongInt) : LongInt;
Var R : LongInt;
Begin
  R := 0;
  If (A <> 0) And (I >= 0) And (I < MemL[0:A]) Then
    R := MemL[0:A + 4 + I * 4];
  ArrGetD := R;
End;

Procedure ArrSetD(Var A : LongInt; I, V : LongInt);
Var N, K, Cap : LongInt;
Begin
  If A = 0 Then
  Begin
    Cap := I + 16;
    A := NAlloc(Cap * 4 + 4);
    MemL[0:A] := Cap;
    For K := 1 To Cap Do MemL[0:A + K * 4] := 0;
  End;
  If I >= MemL[0:A] Then
  Begin
    Cap := MemL[0:A] * 2;
    If Cap <= I Then Cap := I + 16;
    N := NAlloc(Cap * 4 + 4);
    MemL[0:N] := Cap;
    For K := 1 To Cap Do MemL[0:N + K * 4] := 0;
    For K := 0 To MemL[0:A] - 1 Do
      MemL[0:N + 4 + K * 4] := MemL[0:A + 4 + K * 4];
    NFree(A);
    A := N;
  End;
  NFree(MemL[0:A + 4 + I * 4]);
  MemL[0:A + 4 + I * 4] := V;
End;

{ ---- execution ---- }

Var
  TailP : LongInt;           { chaine a executer en appel terminal }

Function RestIsBlank(P, L, Pos : LongInt) : Boolean;
Var C : Byte; R : Boolean;
Begin
  R := True;
  While Pos < L Do
  Begin
    C := Mem[0:P + Pos];
    If (C <> 32) And (C <> 10) And (C <> 9) And (C <> 13) Then
    Begin
      R := False;
      Break;
    End;
    Inc(Pos);
  End;
  RestIsBlank := R;
End;

Procedure ExecStr(Base, P, L : LongInt; Own, Top : Boolean); Forward;

{ lance la chaine (bloc) S : en appel terminal si Tail }
Procedure RunStr(S : LongInt; Tail : Boolean);
Begin
  If Tail Then
  Begin
    If TailP <> 0 Then NFree(TailP);
    TailP := S;
  End
  Else ExecStr(S, S + 4, MemL[0:S], True, False);
End;

Procedure Arith(Op : Char);
Var A, B, C, T, Q, R : LongInt;
Begin
  If Not Need(2) Then Exit;
  B := PopNum;
  A := PopNum;
  T := 0;
  If Op = '+' Then T := NAdd(A, B, False)
  Else If Op = '-' Then T := NAdd(A, B, True)
  Else If Op = '*' Then T := NMul(A, B, ScaleV)
  Else If Op = '/' Then T := NDiv(A, B, ScaleV)
  Else If Op = '%' Then T := NMod(A, B, ScaleV)
  Else If Op = '^' Then
  Begin
    If NSc(B) > 0 Then
    Begin
      C := NRescale(B, 0);
      NFree(B);
      B := C;
    End;
    T := NPow(A, B, ScaleV);
  End
  Else
  Begin
    Q := NDiv(A, B, 0);
    R := NMod(A, B, 0);
    If Failed Then
    Begin
      NFree(Q);
      NFree(R);
    End
    Else
    Begin
      Push(1, Q);
      T := R;
    End;
  End;
  NFree(A);
  NFree(B);
  If Failed Then
  Begin
    NFree(T);
    Failed := False;
    Exit;
  End;
  Push(1, T);
End;

{ a^b mod c, entiers }
Procedure ModExp;
Var A, B, C, Res, Two, Q, Rm, T : LongInt;
Begin
  If Not Need(3) Then Exit;
  C := PopNum;
  B := PopNum;
  A := PopNum;
  If NIsZero(C) Then
  Begin
    MathErr('remainder by zero');
    Failed := False;
    NFree(A);
    NFree(B);
    NFree(C);
    Exit;
  End;
  Res := NFromLong(1);
  T := NMod(A, C, 0);
  NFree(A);
  A := T;
  Two := NFromLong(2);
  While Not NIsZero(B) Do
  Begin
    Rm := NMod(B, Two, 0);
    If Not NIsZero(Rm) Then
    Begin
      T := NMul(Res, A, 0);
      NFree(Res);
      Res := NMod(T, C, 0);
      NFree(T);
    End;
    NFree(Rm);
    T := NMul(A, A, 0);
    NFree(A);
    A := NMod(T, C, 0);
    NFree(T);
    Q := NDiv(B, Two, 0);
    NFree(B);
    B := Q;
  End;
  NFree(Two);
  NFree(A);
  NFree(B);
  NFree(C);
  Push(1, Res);
End;

{ comparaison ; le registre Reg contient la macro a executer }
Procedure DoCmp(Op : Char; Neg : Boolean; Reg : LongInt; Tail : Boolean);
Var A, B, C : LongInt; Ok : Boolean; S : LongInt;
Begin
  If Not Need(2) Then Exit;
  B := PopNum;
  A := PopNum;
  C := NCmp(B, A);
  NFree(A);
  NFree(B);
  Ok := False;
  If Op = '<' Then Ok := C < 0
  Else If Op = '>' Then Ok := C > 0
  Else Ok := C = 0;
  If Neg Then Ok := Not Ok;
  If Not Ok Then Exit;
  If RT[Reg] = 0 Then
  Begin
    Warn('register ''' + Chr(Reg) + ''' is empty');
    Exit;
  End;
  If RK[Reg, RT[Reg] - 1] <> 2 Then Exit;
  S := SCopy(RV[Reg, RT[Reg] - 1]);
  RunStr(S, Tail);
End;

Procedure ExecChar(C : Char; P, L : LongInt; Var Pos : LongInt;
                   Var Done : Boolean);
Var A, T, K, V, Depth, Sp0, N, Q : LongInt; S : LongInt;
    Op : Char; Reg : LongInt; Ln : LongInt; Bf : LongInt;
Begin
  If ((C >= '0') And (C <= '9')) Or (C = '.') Or (C = '_') Or
     ((C >= 'A') And (C <= 'F')) Then
  Begin
    Dec(Pos);
    Push(1, ReadNum(P, L, Pos));
    Exit;
  End;
  If (C = ' ') Or (C = #10) Or (C = #9) Or (C = #13) Then Exit;
  If C = '[' Then
  Begin
    Depth := 1;
    Sp0 := Pos;
    While (Pos < L) And (Depth > 0) Do
    Begin
      Op := Chr(Mem[0:P + Pos]);
      If Op = '\' Then Inc(Pos)
      Else If Op = '[' Then Inc(Depth)
      Else If Op = ']' Then Dec(Depth);
      Inc(Pos);
    End;
    If Pos > L Then Pos := L;
    N := Pos - Sp0;
    If (Depth = 0) And (N > 0) Then Dec(N);
    S := SNew(N);
    Q := 0;
    K := Sp0;
    While K < Sp0 + N Do
    Begin
      Op := Chr(Mem[0:P + K]);
      If (Op = '\') And (K + 1 < Sp0 + N) Then
      Begin
        Inc(K);
        Op := Chr(Mem[0:P + K]);
      End;
      Mem[0:S + 4 + Q] := Ord(Op);
      Inc(Q);
      Inc(K);
    End;
    MemL[0:S] := Q;
    Push(2, S);
    Exit;
  End;
  If (C = '+') Or (C = '-') Or (C = '*') Or (C = '/') Or (C = '%') Or
     (C = '^') Or (C = '~') Then
  Begin
    Arith(C);
    Exit;
  End;
  If C = '|' Then
  Begin
    ModExp;
    Exit;
  End;
  Case C Of
    'v' :
      If Need(1) Then
      Begin
        A := PopNum;
        T := NSqrt(A, ScaleV);
        NFree(A);
        If Failed Then
        Begin
          NFree(T);
          Failed := False;
        End
        Else Push(1, T);
      End;
    'c' :
      While SP > 0 Do
      Begin
        Dec(SP);
        FreeItem(SK[SP], SV[SP]);
      End;
    'd' :
      If Need(1) Then Push(SK[SP - 1], CopyItem(SK[SP - 1], SV[SP - 1]));
    'r' :
      If Need(2) Then
      Begin
        K := SK[SP - 1];
        V := SV[SP - 1];
        SK[SP - 1] := SK[SP - 2];
        SV[SP - 1] := SV[SP - 2];
        SK[SP - 2] := K;
        SV[SP - 2] := V;
      End;
    'R' :
      If Need(1) Then
      Begin
        Dec(SP);
        FreeItem(SK[SP], SV[SP]);
      End;
    'z' : Push(1, NFromLong(SP));
    'Z' :
      If Need(1) Then
      Begin
        Dec(SP);
        If SK[SP] = 1 Then
        Begin
          N := MemL[0:SV[SP]];
          If MemL[0:SV[SP] + 4] > N Then N := MemL[0:SV[SP] + 4];
          If N = 0 Then N := 1;
        End
        Else N := MemL[0:SV[SP]];
        FreeItem(SK[SP], SV[SP]);
        Push(1, NFromLong(N));
      End;
    'X' :
      If Need(1) Then
      Begin
        Dec(SP);
        If SK[SP] = 1 Then N := MemL[0:SV[SP] + 4] Else N := 0;
        FreeItem(SK[SP], SV[SP]);
        Push(1, NFromLong(N));
      End;
    'p' :
      If Need(1) Then PrintItem(SK[SP - 1], SV[SP - 1], True);
    'n' :
      If Need(1) Then
      Begin
        Dec(SP);
        PrintItem(SK[SP], SV[SP], False);
        FreeItem(SK[SP], SV[SP]);
      End;
    'P' :
      If Need(1) Then
      Begin
        Dec(SP);
        PrintBytes(SK[SP], SV[SP]);
        FreeItem(SK[SP], SV[SP]);
      End;
    'f' :
      For K := SP - 1 DownTo 0 Do PrintItem(SK[K], SV[K], True);
    'a' :
      If Need(1) Then
      Begin
        Dec(SP);
        If SK[SP] = 1 Then
        Begin
          S := SNew(1);
          Mem[0:S + 4] := NToLong(SV[SP]) And 255;
        End
        Else
        Begin
          S := SNew(0);
          If MemL[0:SV[SP]] > 0 Then
          Begin
            MemL[0:S] := 1;
            Mem[0:S + 4] := Mem[0:SV[SP] + 4];
          End;
        End;
        FreeItem(SK[SP], SV[SP]);
        Push(2, S);
      End;
    'k' :
      If Need(1) Then
      Begin
        A := PopNum;
        ScaleV := ToSmall(A, 0, 100000);
        Failed := False;
        NFree(A);
      End;
    'K' : Push(1, NFromLong(ScaleV));
    'i' :
      If Need(1) Then
      Begin
        A := PopNum;
        IBase := ToSmall(A, 2, 16);
        Failed := False;
        NFree(A);
      End;
    'I' : Push(1, NFromLong(IBase));
    'o' :
      If Need(1) Then
      Begin
        A := PopNum;
        OBase := ToSmall(A, 2, 1000);
        Failed := False;
        NFree(A);
      End;
    'O' : Push(1, NFromLong(OBase));
    's', 'l', 'S', 'L', ':', ';' :
      Begin
        If Pos >= L Then
        Begin
          Warn('unexpected end of input');
          Exit;
        End;
        Reg := Mem[0:P + Pos];
        Inc(Pos);
        If C = 's' Then
        Begin
          If Need(1) Then
          Begin
            Dec(SP);
            RegSet(Reg, SK[SP], SV[SP]);
          End;
        End
        Else If C = 'S' Then
        Begin
          If Need(1) Then
          Begin
            Dec(SP);
            RegPush(Reg, SK[SP], SV[SP]);
          End;
        End
        Else If C = 'l' Then
        Begin
          If RT[Reg] = 0 Then Push(1, NNew(0, 0))
          Else Push(RK[Reg, RT[Reg] - 1],
                    CopyItem(RK[Reg, RT[Reg] - 1], RV[Reg, RT[Reg] - 1]));
        End
        Else If C = 'L' Then
        Begin
          If RT[Reg] = 0 Then Warn('stack register ''' + Chr(Reg) +
                                   ''' is empty')
          Else
          Begin
            Dec(RT[Reg]);
            Push(RK[Reg, RT[Reg]], RV[Reg, RT[Reg]]);
          End;
        End
        Else If C = ':' Then
        Begin
          If Need(2) Then
          Begin
            A := PopNum;
            Dec(SP);
            K := SK[SP];
            V := SV[SP];
            N := ToSmall(A, 0, 65535);
            Failed := False;
            NFree(A);
            If K = 2 Then
            Begin
              FreeItem(K, V);
              V := NNew(0, 0);
            End;
            ArrSetD(RA[Reg], N, V);
          End;
        End
        Else
        Begin
          If Need(1) Then
          Begin
            A := PopNum;
            N := ToSmall(A, 0, 65535);
            Failed := False;
            NFree(A);
            V := ArrGetD(RA[Reg], N);
            If V = 0 Then Push(1, NNew(0, 0)) Else Push(1, NCopy(V));
          End;
        End;
      End;
    'x' :
      If Need(1) Then
      Begin
        Dec(SP);
        If SK[SP] = 2 Then RunStr(SV[SP], RestIsBlank(P, L, Pos))
        Else Push(SK[SP], SV[SP]);
      End;
    '<', '>', '=' :
      Begin
        If Pos >= L Then Exit;
        Reg := Mem[0:P + Pos];
        Inc(Pos);
        DoCmp(C, False, Reg, RestIsBlank(P, L, Pos));
      End;
    '!' :
      Begin
        If Pos >= L Then Exit;
        Op := Chr(Mem[0:P + Pos]);
        If (Op = '<') Or (Op = '>') Or (Op = '=') Then
        Begin
          Inc(Pos);
          If Pos >= L Then Exit;
          Reg := Mem[0:P + Pos];
          Inc(Pos);
          DoCmp(Op, True, Reg, RestIsBlank(P, L, Pos));
        End
        Else Pos := L;
      End;
    '?' :
      If ReadLine(Bf, Ln) Then ExecStr(Bf, Bf, Ln, True, False);
    'q' :
      Begin
        Quit_ := 2;
        Done := True;
      End;
    'Q' :
      If Need(1) Then
      Begin
        A := PopNum;
        N := ToSmall(A, 1, 1000000);
        Failed := False;
        NFree(A);
        Quit_ := N;
        Done := True;
      End;
    '#' :
      While (Pos < L) And (Mem[0:P + Pos] <> 10) Do Inc(Pos);
  Else
    Warn('''' + C + ''' (0' + 'x' + ') unimplemented');
  End;
End;

Procedure ExecStr(Base, P, L : LongInt; Own, Top : Boolean);
Var Pos : LongInt; C : Char; Done : Boolean;
Begin
  Pos := 0;
  Done := False;
  Inc(Level);
  While (Pos < L) And (Not Done) And (Quit_ = 0) Do
  Begin
    C := Chr(Mem[0:P + Pos]);
    Inc(Pos);
    ExecChar(C, P, L, Pos, Done);
    Failed := False;
    If TailP <> 0 Then
    Begin
      If Own Then NFree(Base);
      Base := TailP;
      P := TailP + 4;
      L := MemL[0:TailP];
      Own := True;
      TailP := 0;
      Pos := 0;
    End;
  End;
  Dec(Level);
  If Own Then NFree(Base);
  If (Quit_ > 0) And (Not Top) Then Dec(Quit_);
End;

Procedure Usage;
Begin
  SysPut(1, 'Usage: dc [OPTION] [file ...]' + #10 +
         '  -e, --expression=EXPR    evaluate expression' + #10 +
         '  -f, --file=FILE          evaluate contents of file' + #10 +
         '  -h, --help               display this help and exit' + #10 +
         '  -V, --version            output version information and exit' +
         #10);
  SysExit(0);
End;

{ lit un fichier complet : bloc, longueur }
Function LoadFile(Const Name : String; Var Buf, L : LongInt) : Boolean;
Var Fd, Cap, N, K, P : LongInt; Pt : Pointer;
Begin
  LoadFile := False;
  Fd := SysOpen(Name, 0, 0);
  If Fd < 0 Then
  Begin
    Warn('File ''' + Name + ''' is unreadable');
    ExitCode := 1;
    Exit;
  End;
  Cap := 4096;
  GetMem(Pt, Cap + 8);
  P := LongInt(Pt);
  L := 0;
  While True Do
  Begin
    If L + 2048 > Cap Then
    Begin
      Cap := Cap * 2;
      GetMem(Pt, Cap + 8);
      For K := 0 To L - 1 Do Mem[0:LongInt(Pt) + K] := Mem[0:P + K];
      FreeMem(Pointer(P), 1);
      P := LongInt(Pt);
    End;
    N := LnxSys3(3, Fd, P + L, 2048);
    If N <= 0 Then Break;
    L := L + N;
  End;
  SysClose(Fd);
  Buf := P;
  LoadFile := True;
End;

Procedure RunText(Const V : String);
Var Ln, Bf, K : LongInt;
Begin
  Ln := Length(V);
  Bf := NAlloc(Ln + 8);
  For K := 1 To Ln Do Mem[0:Bf + K - 1] := Ord(V[K]);
  ExecStr(Bf, Bf, Ln, True, True);
End;

Var
  I, K, J, Ln, Bf, Depth : LongInt;
  A, V : String;
  Stdin_ : Boolean;
  Acc, AccL, Cap : LongInt;
  E : String;
Begin
  OLen := 0;
  OCol := 0;
  LineLen := 70;
  E := SysGetEnv('DC_LINE_LENGTH');
  If E = '' Then E := SysGetEnv('BC_LINE_LENGTH');
  If E <> '' Then
  Begin
    LineLen := 0;
    For K := 1 To Length(E) Do
      If (E[K] >= '0') And (E[K] <= '9') Then
        LineLen := LineLen * 10 + Ord(E[K]) - 48;
    If LineLen = 1 Then LineLen := 70;
  End;
  SP := 0;
  ScaleV := 0;
  IBase := 10;
  OBase := 10;
  Quit_ := 0;
  Failed := False;
  ExitCode := 0;
  Level := 0;
  TailP := 0;
  InFd := 0;
  InPos := 0;
  InCnt := 0;
  InEof := False;
  For I := 0 To MaxReg - 1 Do
  Begin
    RT[I] := 0;
    RA[I] := 0;
  End;
  Stdin_ := True;
  I := 1;
  While (I < SysArgCount) And (Quit_ = 0) Do
  Begin
    A := SysArgStr(I);
    If (A = '-e') Or (A = '--expression') Or (A = '-f') Or (A = '--file') Then
    Begin
      Inc(I);
      If I >= SysArgCount Then Usage;
      V := SysArgStr(I);
      Stdin_ := False;
      If (A = '-e') Or (A = '--expression') Then RunText(V)
      Else If LoadFile(V, Bf, Ln) Then ExecStr(Bf, Bf, Ln, True, True);
    End
    Else If Copy(A, 1, 13) = '--expression=' Then
    Begin
      Stdin_ := False;
      RunText(Copy(A, 14, 250));
    End
    Else If (A = '-V') Or (A = '--version') Then
    Begin
      SysPut(1, 'dc (GNU bc 1.07.1) 1.4.1' + #10);
      SysExit(0);
    End
    Else If (A = '-h') Or (A = '--help') Then Usage
    Else If A = '-' Then Stdin_ := True
    Else If (A <> '') And (A[1] = '-') And (Length(A) > 1) Then
    Begin
      SysPut(2, 'dc: invalid option -- ' + A + #10);
      Usage;
    End
    Else
    Begin
      Stdin_ := False;
      If LoadFile(A, Bf, Ln) Then ExecStr(Bf, Bf, Ln, True, True);
    End;
    Inc(I);
  End;
  If Stdin_ And (Quit_ = 0) Then
  Begin
    While Quit_ = 0 Do
    Begin
      If Not ReadLine(Acc, AccL) Then Break;
      Depth := 0;
      K := 0;
      While True Do
      Begin
        While K < AccL Do
        Begin
          If Mem[0:Acc + K] = 92 Then Inc(K)
          Else If Mem[0:Acc + K] = 91 Then Inc(Depth)
          Else If Mem[0:Acc + K] = 93 Then
            If Depth > 0 Then Dec(Depth);
          Inc(K);
        End;
        If Depth = 0 Then Break;
        If Not ReadLine(Bf, Ln) Then Break;
        Cap := AccL + Ln;
        J := NAlloc(Cap + 8);
        For K := 0 To AccL - 1 Do Mem[0:J + K] := Mem[0:Acc + K];
        For K := 0 To Ln - 1 Do Mem[0:J + AccL + K] := Mem[0:Bf + K];
        NFree(Acc);
        NFree(Bf);
        K := AccL;
        Acc := J;
        AccL := Cap;
      End;
      ExecStr(Acc, Acc, AccL, True, True);
    End;
  End;
  Flush;
  SysExit(ExitCode);
End.
