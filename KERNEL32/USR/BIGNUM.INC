{ BIGNUM.INC : nombres decimaux de precision arbitraire (bc et dc).
  Un nombre est une adresse de bloc du tas :
    [0..3] Len (nombre de chiffres), [4..7] Scale (chiffres apres la
    virgule), [8] signe (1 = negatif), [12..] chiffres, le moins
    significatif en premier (le chiffre I vaut 10 puissance I - Scale).
  Le programme qui inclut ce fichier doit definir avant :
    Procedure MathErr(Const S : String);   (erreur fatale ou levee)
    Procedure OutC(C : Char);              (sortie d'un caractere de nombre)
  Les fonctions rendent un nombre neuf que l'appelant libere avec NFree. }

Function NAlloc(N : LongInt) : LongInt;
Var Pt : Pointer;
Begin
  GetMem(Pt, N + 16);
  If Pt = Nil Then
  Begin
    MathErr('out of memory');
    NAlloc := 0;
    Exit;
  End;
  NAlloc := LongInt(Pt);
End;

Procedure NFree(P : LongInt);
Var Pt : Pointer;
Begin
  If P <> 0 Then
  Begin
    Pt := Pointer(P);
    FreeMem(Pt, 1);
  End;
End;

Function NLen(P : LongInt) : LongInt;
Begin
  NLen := MemL[0:P];
End;

Function NSc(P : LongInt) : LongInt;
Begin
  NSc := MemL[0:P + 4];
End;

Function NNeg(P : LongInt) : Boolean;
Begin
  NNeg := Mem[0:P + 8] <> 0;
End;

Function ND(P, I : LongInt) : LongInt;
Begin
  If (I < 0) Or (I >= MemL[0:P]) Then ND := 0
  Else ND := Mem[0:P + 12 + I];
End;

Procedure NSetD(P, I, V : LongInt);
Begin
  Mem[0:P + 12 + I] := V;
End;

Function NNew(Len, Sc : LongInt) : LongInt;
Var P, K : LongInt;
Begin
  P := NAlloc(Len + 12);
  MemL[0:P] := Len;
  MemL[0:P + 4] := Sc;
  MemL[0:P + 8] := 0;
  For K := 0 To Len - 1 Do Mem[0:P + 12 + K] := 0;
  NNew := P;
End;

Function NIsZero(P : LongInt) : Boolean;
Begin
  NIsZero := MemL[0:P] = 0;
End;

Procedure NNorm(P : LongInt);
Var L : LongInt;
Begin
  L := MemL[0:P];
  While (L > 0) And (Mem[0:P + 12 + L - 1] = 0) Do Dec(L);
  MemL[0:P] := L;
  If L = 0 Then Mem[0:P + 8] := 0;
End;

Function NCopy(P : LongInt) : LongInt;
Var Q, K : LongInt;
Begin
  Q := NNew(MemL[0:P], MemL[0:P + 4]);
  Mem[0:Q + 8] := Mem[0:P + 8];
  For K := 0 To MemL[0:P] - 1 Do Mem[0:Q + 12 + K] := Mem[0:P + 12 + K];
  NCopy := Q;
End;

Function NFromLong(V : LongInt) : LongInt;
Var P, K, N, T : LongInt; Neg : Boolean;
Begin
  Neg := V < 0;
  If Neg Then V := -V;
  N := 0;
  T := V;
  While T > 0 Do
  Begin
    Inc(N);
    T := T Div 10;
  End;
  P := NNew(N, 0);
  For K := 0 To N - 1 Do
  Begin
    Mem[0:P + 12 + K] := V Mod 10;
    V := V Div 10;
  End;
  If Neg And (N > 0) Then Mem[0:P + 8] := 1;
  NFromLong := P;
End;

{ partie entiere tronquee, bornee a 2147483647 }
Function NToLong(P : LongInt) : LongInt;
Var K, Sc, R : LongInt;
Begin
  Sc := MemL[0:P + 4];
  R := 0;
  K := MemL[0:P] - 1;
  While K >= Sc Do
  Begin
    If R > 214748363 Then
    Begin
      R := 2147483647;
      Break;
    End;
    R := R * 10 + Mem[0:P + 12 + K];
    Dec(K);
  End;
  If Mem[0:P + 8] <> 0 Then R := -R;
  NToLong := R;
End;

{ meme valeur avec Sc chiffres apres la virgule (troncature ou zeros) }
Function NRescale(P, Sc : LongInt) : LongInt;
Var Q, K, S0, D, L : LongInt;
Begin
  S0 := MemL[0:P + 4];
  D := Sc - S0;
  L := MemL[0:P] + D;
  If L < 0 Then L := 0;
  Q := NNew(L, Sc);
  For K := 0 To L - 1 Do Mem[0:Q + 12 + K] := ND(P, K - D);
  If Mem[0:P + 8] <> 0 Then Mem[0:Q + 8] := 1;
  NNorm(Q);
  NRescale := Q;
End;

{ compare les valeurs absolues }
Function NMagCmp(A, B : LongInt) : LongInt;
Var Sa, Sb, TopA, TopB, E, Lo, Da, Db : LongInt;
Begin
  NMagCmp := 0;
  If (MemL[0:A] = 0) And (MemL[0:B] = 0) Then Exit;
  If MemL[0:A] = 0 Then
  Begin
    NMagCmp := -1;
    Exit;
  End;
  If MemL[0:B] = 0 Then
  Begin
    NMagCmp := 1;
    Exit;
  End;
  Sa := MemL[0:A + 4];
  Sb := MemL[0:B + 4];
  TopA := MemL[0:A] - Sa;
  TopB := MemL[0:B] - Sb;
  If TopA > TopB Then
  Begin
    NMagCmp := 1;
    Exit;
  End;
  If TopA < TopB Then
  Begin
    NMagCmp := -1;
    Exit;
  End;
  Lo := -Sa;
  If -Sb < Lo Then Lo := -Sb;
  E := TopA - 1;
  While E >= Lo Do
  Begin
    Da := ND(A, E + Sa);
    Db := ND(B, E + Sb);
    If Da > Db Then
    Begin
      NMagCmp := 1;
      Exit;
    End;
    If Da < Db Then
    Begin
      NMagCmp := -1;
      Exit;
    End;
    Dec(E);
  End;
End;

Function NCmp(A, B : LongInt) : LongInt;
Var Na, Nb : Boolean; C : LongInt;
Begin
  Na := Mem[0:A + 8] <> 0;
  Nb := Mem[0:B + 8] <> 0;
  If MemL[0:A] = 0 Then Na := False;
  If MemL[0:B] = 0 Then Nb := False;
  If Na <> Nb Then
  Begin
    If Na Then NCmp := -1 Else NCmp := 1;
    Exit;
  End;
  C := NMagCmp(A, B);
  If Na Then C := -C;
  NCmp := C;
End;

{ A + B, ou A - B si Sub ; echelle = max des deux }
Function NAdd(A, B : LongInt; Sub : Boolean) : LongInt;
Var Sa, Sb, S, R, K, X, Y, Carry, Ra, Rb : LongInt; Na, Nb, Rn : Boolean;
    Cm, Res : LongInt;
Begin
  Sa := MemL[0:A + 4];
  Sb := MemL[0:B + 4];
  S := Sa;
  If Sb > S Then S := Sb;
  Na := Mem[0:A + 8] <> 0;
  Nb := (Mem[0:B + 8] <> 0) <> Sub;
  If MemL[0:B] = 0 Then Nb := False;
  R := MemL[0:A] + (S - Sa);
  If MemL[0:B] + (S - Sb) > R Then R := MemL[0:B] + (S - Sb);
  Ra := S - Sa;
  Rb := S - Sb;
  If Na = Nb Then
  Begin
    Res := NNew(R + 1, S);
    NAdd := Res;
    Carry := 0;
    For K := 0 To R Do
    Begin
      X := ND(A, K - Ra) + ND(B, K - Rb) + Carry;
      If X >= 10 Then
      Begin
        X := X - 10;
        Carry := 1;
      End
      Else Carry := 0;
      Mem[0:Res + 12 + K] := X;
    End;
    If Na Then Mem[0:Res + 8] := 1;
    NNorm(Res);
    Exit;
  End;
  Cm := NMagCmp(A, B);
  If Cm = 0 Then
  Begin
    NAdd := NNew(0, S);
    Exit;
  End;
  Res := NNew(R + 1, S);
  NAdd := Res;
  If Cm > 0 Then
  Begin
    Rn := Na;
    Carry := 0;
    For K := 0 To R Do
    Begin
      X := ND(A, K - Ra) - ND(B, K - Rb) - Carry;
      If X < 0 Then
      Begin
        X := X + 10;
        Carry := 1;
      End
      Else Carry := 0;
      Mem[0:Res + 12 + K] := X;
    End;
  End
  Else
  Begin
    Rn := Nb;
    Carry := 0;
    For K := 0 To R Do
    Begin
      X := ND(B, K - Rb) - ND(A, K - Ra) - Carry;
      If X < 0 Then
      Begin
        X := X + 10;
        Carry := 1;
      End
      Else Carry := 0;
      Mem[0:Res + 12 + K] := X;
    End;
  End;
  If Rn Then Mem[0:Res + 8] := 1;
  NNorm(Res);
End;

Function NNegate(P : LongInt) : LongInt;
Var Q : LongInt;
Begin
  Q := NCopy(P);
  If MemL[0:Q] > 0 Then Mem[0:Q + 8] := 1 - Mem[0:Q + 8];
  NNegate := Q;
End;

{ A * B ; echelle = min(Sa + Sb, max(Sc, Sa, Sb)) }
Function NMul(A, B, Sc : LongInt) : LongInt;
Var La, Lb, K, J, Sa, Sb, Rs, Carry, X : LongInt; Acc, T, R : LongInt;
Begin
  La := MemL[0:A];
  Lb := MemL[0:B];
  Sa := MemL[0:A + 4];
  Sb := MemL[0:B + 4];
  Rs := Sa + Sb;
  X := Sc;
  If Sa > X Then X := Sa;
  If Sb > X Then X := Sb;
  If X < Rs Then Rs := X;
  If (La = 0) Or (Lb = 0) Then
  Begin
    NMul := NNew(0, Rs);
    Exit;
  End;
  Acc := NAlloc((La + Lb + 1) * 4);
  For K := 0 To La + Lb Do MemL[0:Acc + K * 4] := 0;
  For K := 0 To La - 1 Do
  Begin
    X := Mem[0:A + 12 + K];
    If X <> 0 Then
      For J := 0 To Lb - 1 Do
        MemL[0:Acc + (K + J) * 4] := MemL[0:Acc + (K + J) * 4] +
                                      X * Mem[0:B + 12 + J];
  End;
  T := NNew(La + Lb + 1, Sa + Sb);
  Carry := 0;
  For K := 0 To La + Lb Do
  Begin
    X := MemL[0:Acc + K * 4] + Carry;
    Mem[0:T + 12 + K] := X Mod 10;
    Carry := X Div 10;
  End;
  FreeMem(Pointer(Acc), 1);
  If (Mem[0:A + 8] <> 0) <> (Mem[0:B + 8] <> 0) Then Mem[0:T + 8] := 1;
  NNorm(T);
  R := NRescale(T, Rs);
  NFree(T);
  NMul := R;
End;

{ A / B tronque a Sc chiffres apres la virgule }
Function NDiv(A, B, Sc : LongInt) : LongInt;
Var Lb, E, Ln, K, I, Q, R, Cnt, Rl, Top, Borrow, X, Sa, Sb : LongInt;
    Rb, Num, Res, Sg : LongInt; Ge : Boolean;
Begin
  If MemL[0:B] = 0 Then
  Begin
    MathErr('Divide by zero');
    NDiv := NNew(0, Sc);
    Exit;
  End;
  Sa := MemL[0:A + 4];
  Sb := MemL[0:B + 4];
  Lb := MemL[0:B];
  E := Sc + Sb - Sa;
  { numerateur entier : chiffres de A decales de E }
  Ln := MemL[0:A] + E;
  If (MemL[0:A] = 0) Or (Ln <= 0) Then
  Begin
    NDiv := NNew(0, Sc);
    Exit;
  End;
  Num := NNew(Ln, 0);
  For K := 0 To Ln - 1 Do Mem[0:Num + 12 + K] := ND(A, K - E);
  Res := NNew(Ln, Sc);
  Rb := NAlloc(Lb + 4);
  For K := 0 To Lb + 3 Do Mem[0:Rb + K] := 0;
  Rl := 0;
  For I := Ln - 1 DownTo 0 Do
  Begin
    { R := R * 10 + chiffre }
    For K := Rl DownTo 1 Do Mem[0:Rb + K] := Mem[0:Rb + K - 1];
    Mem[0:Rb] := Mem[0:Num + 12 + I];
    Inc(Rl);
    While (Rl > 0) And (Mem[0:Rb + Rl - 1] = 0) Do Dec(Rl);
    Cnt := 0;
    While True Do
    Begin
      If Rl > Lb Then Ge := True
      Else If Rl < Lb Then Ge := False
      Else
      Begin
        Ge := True;
        K := Rl - 1;
        While K >= 0 Do
        Begin
          X := Mem[0:Rb + K];
          If X > Mem[0:B + 12 + K] Then Break;
          If X < Mem[0:B + 12 + K] Then
          Begin
            Ge := False;
            Break;
          End;
          Dec(K);
        End;
      End;
      If Not Ge Then Break;
      Borrow := 0;
      For K := 0 To Rl - 1 Do
      Begin
        X := Mem[0:Rb + K] - Borrow;
        If K < Lb Then X := X - Mem[0:B + 12 + K];
        If X < 0 Then
        Begin
          X := X + 10;
          Borrow := 1;
        End
        Else Borrow := 0;
        Mem[0:Rb + K] := X;
      End;
      While (Rl > 0) And (Mem[0:Rb + Rl - 1] = 0) Do Dec(Rl);
      Inc(Cnt);
    End;
    Mem[0:Res + 12 + I] := Cnt;
  End;
  FreeMem(Pointer(Rb), 1);
  NFree(Num);
  If (Mem[0:A + 8] <> 0) <> (Mem[0:B + 8] <> 0) Then Mem[0:Res + 8] := 1;
  NNorm(Res);
  NDiv := Res;
End;

{ A mod B : A - (A / B a Sc chiffres) * B, echelle max(Sa, Sc + Sb) }
Function NMod(A, B, Sc : LongInt) : LongInt;
Var Q, T, R, Rs : LongInt;
Begin
  If MemL[0:B] = 0 Then
  Begin
    MathErr('Divide by zero');
    NMod := NNew(0, 0);
    Exit;
  End;
  Rs := MemL[0:A + 4];
  If Sc + MemL[0:B + 4] > Rs Then Rs := Sc + MemL[0:B + 4];
  Q := NDiv(A, B, Sc);
  T := NMul(Q, B, Rs);
  R := NAdd(A, T, True);
  NFree(Q);
  NFree(T);
  Q := NRescale(R, Rs);
  NFree(R);
  NMod := Q;
End;

{ A puissance partie entiere de B }
Function NPow(A, B, Sc : LongInt) : LongInt;
Var E, Neg, Rs, Pw, K : LongInt; Power, Temp, T2, One : LongInt;
    Calc : LongInt;
Begin
  E := NToLong(B);
  Neg := 0;
  If E < 0 Then
  Begin
    Neg := 1;
    E := -E;
  End;
  If E = 0 Then
  Begin
    NPow := NFromLong(1);
    Exit;
  End;
  If Neg = 1 Then Rs := Sc
  Else
  Begin
    Rs := MemL[0:A + 4] * E;
    K := Sc;
    If MemL[0:A + 4] > K Then K := MemL[0:A + 4];
    If K < Rs Then Rs := K;
  End;
  Power := NCopy(A);
  Pw := MemL[0:A + 4];
  While (E And 1) = 0 Do
  Begin
    Pw := Pw * 2;
    T2 := NMul(Power, Power, Pw);
    NFree(Power);
    Power := T2;
    E := E Shr 1;
  End;
  Temp := NCopy(Power);
  Calc := Pw;
  E := E Shr 1;
  While E > 0 Do
  Begin
    Pw := Pw * 2;
    T2 := NMul(Power, Power, Pw);
    NFree(Power);
    Power := T2;
    If (E And 1) = 1 Then
    Begin
      Calc := Pw + Calc;
      T2 := NMul(Temp, Power, Calc);
      NFree(Temp);
      Temp := T2;
    End;
    E := E Shr 1;
  End;
  NFree(Power);
  If Neg = 1 Then
  Begin
    One := NFromLong(1);
    T2 := NDiv(One, Temp, Rs);
    NFree(One);
    NFree(Temp);
    NPow := T2;
  End
  Else
  Begin
    T2 := NRescale(Temp, Rs);
    NFree(Temp);
    NPow := T2;
  End;
End;

{ nombre d'un entier ecrit avec ses chiffres, echelle Sc (valeur / 10^Sc) }
Function NWithScale(P, Sc : LongInt) : LongInt;
Var Q, K : LongInt;
Begin
  Q := NNew(MemL[0:P], Sc);
  Mem[0:Q + 8] := Mem[0:P + 8];
  For K := 0 To MemL[0:P] - 1 Do Mem[0:Q + 12 + K] := Mem[0:P + 12 + K];
  NNorm(Q);
  NWithScale := Q;
End;

{ racine carree a max(Sc, echelle de A) chiffres }
Function NSqrt(A, Sc : LongInt) : LongInt;
Var Rs, Sa, E, K, L : LongInt; N, X, Y, Q, S, Two, T : LongInt;
Begin
  If Mem[0:A + 8] <> 0 Then
  Begin
    MathErr('square root of negative number');
    NSqrt := NNew(0, 0);
    Exit;
  End;
  Sa := MemL[0:A + 4];
  Rs := Sc;
  If Sa > Rs Then Rs := Sa;
  If MemL[0:A] = 0 Then
  Begin
    NSqrt := NNew(0, Rs);
    Exit;
  End;
  { N = A * 10^(2 Rs) entier }
  E := 2 * Rs - Sa;
  L := MemL[0:A] + E;
  N := NNew(L, 0);
  For K := 0 To L - 1 Do Mem[0:N + 12 + K] := ND(A, K - E);
  NNorm(N);
  { X0 = 10^(ceil(len / 2)) }
  L := (MemL[0:N] + 1) Div 2;
  X := NNew(L + 1, 0);
  Mem[0:X + 12 + L] := 1;
  Two := NFromLong(2);
  While True Do
  Begin
    Q := NDiv(N, X, 0);
    S := NAdd(X, Q, False);
    NFree(Q);
    Y := NDiv(S, Two, 0);
    NFree(S);
    If NCmp(Y, X) >= 0 Then
    Begin
      NFree(Y);
      Break;
    End;
    NFree(X);
    X := Y;
  End;
  NFree(Two);
  NFree(N);
  T := NWithScale(X, Rs);
  NFree(X);
  NSqrt := T;
End;

{ ---- sortie ---- }

Function Digs(V : LongInt) : LongInt;
Var N : LongInt;
Begin
  N := 1;
  While V >= 10 Do
  Begin
    V := V Div 10;
    Inc(N);
  End;
  Digs := N;
End;

Procedure OutS(Const S : String);
Var K : LongInt;
Begin
  For K := 1 To Length(S) Do OutC(S[K]);
End;

Procedure OutDigit(V, Base : LongInt);
Var S : String; W : LongInt;
Begin
  If Base <= 16 Then
  Begin
    If V < 10 Then OutC(Chr(48 + V)) Else OutC(Chr(55 + V));
  End
  Else
  Begin
    Str(V, S);
    W := Digs(Base - 1);
    OutC(' ');
    While Length(S) < W Do S := '0' + S;
    OutS(S);
  End;
End;

Procedure NPrint(P, Base : LongInt);
Var K, Sc, L, Cnt, R, N, Tl, X : LongInt; Ib, Fr, Tt, Dg : LongInt;
Begin
  Sc := MemL[0:P + 4];
  L := MemL[0:P];
  If L = 0 Then
  Begin
    OutC('0');
    Exit;
  End;
  If Mem[0:P + 8] <> 0 Then OutC('-');
  If Base = 10 Then
  Begin
    K := L - 1;
    While K >= Sc Do
    Begin
      OutC(Chr(48 + Mem[0:P + 12 + K]));
      Dec(K);
    End;
    If Sc > 0 Then
    Begin
      OutC('.');
      For K := Sc - 1 DownTo 0 Do OutC(Chr(48 + ND(P, K)));
    End;
    Exit;
  End;
  { partie entiere en base Base : divisions successives }
  N := L - Sc;
  If N < 0 Then N := 0;
  Ib := NAlloc(N + 4);
  For K := 0 To N - 1 Do Mem[0:Ib + K] := Mem[0:P + 12 + Sc + K];
  Dg := NAlloc((N + 2) * 16);
  Cnt := 0;
  Tl := N;
  While (Tl > 0) And (Mem[0:Ib + Tl - 1] = 0) Do Dec(Tl);
  While Tl > 0 Do
  Begin
    R := 0;
    For K := Tl - 1 DownTo 0 Do
    Begin
      X := R * 10 + Mem[0:Ib + K];
      Mem[0:Ib + K] := X Div Base;
      R := X Mod Base;
    End;
    MemL[0:Dg + Cnt * 4] := R;
    Inc(Cnt);
    While (Tl > 0) And (Mem[0:Ib + Tl - 1] = 0) Do Dec(Tl);
  End;
  For K := Cnt - 1 DownTo 0 Do OutDigit(MemL[0:Dg + K * 4], Base);
  FreeMem(Pointer(Dg), 1);
  FreeMem(Pointer(Ib), 1);
  If Sc > 0 Then
  Begin
    OutC('.');
    Fr := NAlloc(Sc + 4);
    For K := 0 To Sc - 1 Do Mem[0:Fr + K] := Mem[0:P + 12 + K];
    Tt := NAlloc(Sc + 40);
    For K := 0 To Sc + 30 Do Mem[0:Tt + K] := 0;
    Mem[0:Tt] := 1;
    Tl := 1;
    While Tl <= Sc Do
    Begin
      R := 0;
      For K := 0 To Sc - 1 Do
      Begin
        X := Mem[0:Fr + K] * Base + R;
        Mem[0:Fr + K] := X Mod 10;
        R := X Div 10;
      End;
      OutDigit(R, Base);
      R := 0;
      For K := 0 To Tl - 1 Do
      Begin
        X := Mem[0:Tt + K] * Base + R;
        Mem[0:Tt + K] := X Mod 10;
        R := X Div 10;
      End;
      While R > 0 Do
      Begin
        Mem[0:Tt + Tl] := R Mod 10;
        R := R Div 10;
        Inc(Tl);
      End;
    End;
    FreeMem(Pointer(Tt), 1);
    FreeMem(Pointer(Fr), 1);
  End;
End;
