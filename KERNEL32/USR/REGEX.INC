{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2026
  @website(https://www.gladir.com/linux-0)
  @abstract(Target: LPC -3X)
  @description: moteur d'expressions regulieres POSIX (BRE et ERE avec les
      extensions GNU : \+ \? \| \w \W \s \S \b \B \< \> \{m,n\}, classes
      [:alpha:], references arriere \1..\9), partage par grep, sed et awk
      par la directive include de REGEX.INC. Le programme est compile en
      instructions d'une machine a retour arriere (adresses relatives).
      Recherche de la plus longue correspondance (POSIX) quand le motif contient une alternative.
      Interface : ReCompile(Pat, Ere, Icase) -> programme (ou -1, ReErr),
      ReSearch(Prog, Base, Len, From, Longest) : le texte est lu par
      Mem[0:Base + i] ; resultats ReCap[2k], ReCap[2k+1] (debut, fin du
      groupe k, -1 si absent).
}

Const
  ReMaxProg = 24575;
  ReMaxSet  = 255;
  ReOpChar = 1;  ReOpAny = 2;   ReOpSet = 3;   ReOpBol = 4;
  ReOpEol = 5;   ReOpWb = 6;    ReOpNwb = 7;   ReOpWbeg = 8;
  ReOpWend = 9;  ReOpSave = 10; ReOpSplit = 11; ReOpJmp = 12;
  ReOpBref = 13; ReOpMatch = 14; ReOpStar = 15; ReOpMark = 16;
  ReOpChk = 17;  ReOpNop = 18;

Type
  TReIns = Record
    Op, C : Byte;
    X, Y, Z : LongInt;
  End;

Var
  ReProg : Array[0..ReMaxProg] Of TReIns;
  ReN : LongInt;
  ReSets : Array[0..8191] Of Byte;
  ReSetN : LongInt;
  ReCap : Array[0..19] Of LongInt;
  ReBestCap : Array[0..19] Of LongInt;
  ReMarks : Array[0..63] Of LongInt;
  ReErr : String;
  RePat : String;
  RePos, ReGroups, ReLoops : LongInt;
  ReEre, ReIcase, ReHasAlt, ReBad : Boolean;
  ReBase, ReLen, ReBest : LongInt;
  ReLongest : Boolean;

{ ---------- compilation ---------- }

Function ReIsWord(C : LongInt) : Boolean;
Begin
  ReIsWord := ((C >= 48) And (C <= 57)) Or ((C >= 65) And (C <= 90)) Or
              ((C >= 97) And (C <= 122)) Or (C = 95);
End;

Function ReFold(C : LongInt) : LongInt;
Begin
  If (C >= 65) And (C <= 90) Then ReFold := C + 32 Else ReFold := C;
End;

Procedure ReFail(Const Msg : String);
Begin
  If Not ReBad Then ReErr := Msg;
  ReBad := True;
End;

Function ReEmit(Op, C : LongInt; X, Y, Z : LongInt) : LongInt;
Begin
  If ReN >= ReMaxProg Then
  Begin
    ReFail('regular expression too big');
    ReEmit := 0;
    Exit;
  End;
  ReProg[ReN].Op := Op;
  ReProg[ReN].C := C;
  ReProg[ReN].X := X;
  ReProg[ReN].Y := Y;
  ReProg[ReN].Z := Z;
  ReEmit := ReN;
  Inc(ReN);
End;

{ insere une instruction a la position P (decale le reste vers le haut) }
Procedure ReInsert(P, Op, X, Y : LongInt);
Var K : LongInt;
Begin
  If ReN >= ReMaxProg Then
  Begin
    ReFail('regular expression too big');
    Exit;
  End;
  K := ReN;
  While K > P Do
  Begin
    ReProg[K] := ReProg[K - 1];
    Dec(K);
  End;
  Inc(ReN);
  ReProg[P].Op := Op;
  ReProg[P].C := 0;
  ReProg[P].X := X;
  ReProg[P].Y := Y;
  ReProg[P].Z := 0;
End;

Function ReNewSet : LongInt;
Var K : LongInt;
Begin
  If ReSetN >= ReMaxSet Then
  Begin
    ReFail('too many character classes');
    ReNewSet := 0;
    Exit;
  End;
  For K := 0 To 31 Do ReSets[ReSetN * 32 + K] := 0;
  ReNewSet := ReSetN;
  Inc(ReSetN);
End;

Procedure ReSetBit(S, C : LongInt);
Begin
  ReSets[S * 32 + (C Shr 3)] := ReSets[S * 32 + (C Shr 3)] Or
                                (1 Shl (C And 7));
End;

Function ReGetBit(S, C : LongInt) : Boolean;
Begin
  ReGetBit := (ReSets[S * 32 + (C Shr 3)] And (1 Shl (C And 7))) <> 0;
End;

Procedure ReSetAddC(S, C : LongInt);
Begin
  ReSetBit(S, C);
  If ReIcase Then
  Begin
    If (C >= 65) And (C <= 90) Then ReSetBit(S, C + 32);
    If (C >= 97) And (C <= 122) Then ReSetBit(S, C - 32);
  End;
End;

Function ReInCls(Const Nm : String; C : LongInt) : Boolean;
Begin
  ReInCls := False;
  If Nm = 'alpha' Then ReInCls := ((C >= 65) And (C <= 90)) Or
                                  ((C >= 97) And (C <= 122));
  If Nm = 'digit' Then ReInCls := (C >= 48) And (C <= 57);
  If Nm = 'alnum' Then ReInCls := ((C >= 65) And (C <= 90)) Or
    ((C >= 97) And (C <= 122)) Or ((C >= 48) And (C <= 57));
  If Nm = 'upper' Then ReInCls := ((C >= 65) And (C <= 90)) Or
    (ReIcase And (C >= 97) And (C <= 122));
  If Nm = 'lower' Then ReInCls := ((C >= 97) And (C <= 122)) Or
    (ReIcase And (C >= 65) And (C <= 90));
  If Nm = 'space' Then ReInCls := (C = 32) Or ((C >= 9) And (C <= 13));
  If Nm = 'blank' Then ReInCls := (C = 32) Or (C = 9);
  If Nm = 'punct' Then ReInCls := ((C >= 33) And (C <= 47)) Or
    ((C >= 58) And (C <= 64)) Or ((C >= 91) And (C <= 96)) Or
    ((C >= 123) And (C <= 126));
  If Nm = 'print' Then ReInCls := (C >= 32) And (C <= 126);
  If Nm = 'graph' Then ReInCls := (C >= 33) And (C <= 126);
  If Nm = 'cntrl' Then ReInCls := (C < 32) Or (C = 127);
  If Nm = 'xdigit' Then ReInCls := ((C >= 48) And (C <= 57)) Or
    ((C >= 65) And (C <= 70)) Or ((C >= 97) And (C <= 102));
End;

Procedure ReSetClass(S : LongInt; Const Nm : String);
Var C : LongInt;
Begin
  For C := 0 To 255 Do
    If ReInCls(Nm, C) Then ReSetBit(S, C);
End;

{ [ ... ] : RePos pointe apres le crochet ouvrant }
Procedure ReBracket;
Var S, C, C2, K : LongInt;
    Neg, First : Boolean;
    Nm : String;
Begin
  S := ReNewSet;
  Neg := False;
  If (RePos <= Length(RePat)) And (RePat[RePos] = '^') Then
  Begin
    Neg := True;
    Inc(RePos);
  End;
  First := True;
  While True Do
  Begin
    If RePos > Length(RePat) Then
    Begin
      ReFail('unmatched [');
      Exit;
    End;
    C := Ord(RePat[RePos]);
    If (C = 93) And (Not First) Then
    Begin
      Inc(RePos);
      Break;
    End;
    First := False;
    If (C = 91) And (RePos < Length(RePat)) And
       (RePat[RePos + 1] = ':') Then
    Begin
      K := RePos + 2;
      Nm := '';
      While (K < Length(RePat)) And (RePat[K] <> ':') Do
      Begin
        Nm := Nm + RePat[K];
        Inc(K);
      End;
      If (K < Length(RePat)) And (RePat[K + 1] = ']') Then
      Begin
        ReSetClass(S, Nm);
        RePos := K + 2;
        Continue;
      End;
    End;
    If (C = 91) And (RePos < Length(RePat)) And
       ((RePat[RePos + 1] = '.') Or (RePat[RePos + 1] = '=')) Then
    Begin
      { [.x.] ou [=x=] : le caractere seul }
      If (RePos + 4 <= Length(RePat)) Then
      Begin
        ReSetAddC(S, Ord(RePat[RePos + 2]));
        RePos := RePos + 5;
        Continue;
      End;
    End;
    Inc(RePos);
    If (RePos + 1 <= Length(RePat)) And (RePat[RePos] = '-') And
       (RePat[RePos + 1] <> ']') Then
    Begin
      C2 := Ord(RePat[RePos + 1]);
      RePos := RePos + 2;
      For K := C To C2 Do ReSetAddC(S, K);
    End
    Else ReSetAddC(S, C);
  End;
  If Neg Then
    For K := 0 To 255 Do
      If ReGetBit(S, K) Then ReSets[S * 32 + (K Shr 3)] :=
        ReSets[S * 32 + (K Shr 3)] And (Not (1 Shl (K And 7)))
      Else ReSets[S * 32 + (K Shr 3)] :=
        ReSets[S * 32 + (K Shr 3)] Or (1 Shl (K And 7));
  ReEmit(ReOpSet, 0, S, 0, 0);
End;

Procedure ReAlt; Forward;

Function ReCanBeEmpty(P0, P1 : LongInt) : Boolean;
Var K : LongInt; Cons : Boolean;
Begin
  Cons := False;
  For K := P0 To P1 - 1 Do
    If (ReProg[K].Op = ReOpChar) Or (ReProg[K].Op = ReOpAny) Or
       (ReProg[K].Op = ReOpSet) Then Cons := True;
  ReCanBeEmpty := Not Cons;
End;

{ applique un quantificateur {Mn,Mx} (Mx < 0 : sans limite) au bloc
  [PS, ReN) : l'atome est recopie (adresses relatives) }
Var
  ReTmp : Array[0..1023] Of TReIns;

Procedure ReRepeat(PS, Mn, Mx : LongInt);
Var N, K, J, S0, Cnt : LongInt;
    Op : LongInt;
Begin
  N := ReN - PS;
  Op := ReProg[PS].Op;
  If (N = 1) And ((Op = ReOpChar) Or (Op = ReOpAny) Or (Op = ReOpSet)) Then
  Begin
    { repetition d'un seul caractere : instruction STAR }
    ReProg[PS].Z := Mx;
    ReProg[PS].Y := Mn;
    If Op = ReOpChar Then ReProg[PS].X := -1 - ReProg[PS].C
    Else If Op = ReOpAny Then ReProg[PS].X := -300;
    ReProg[PS].Op := ReOpStar;
    Exit;
  End;
  If (Mn = 1) And (Mx = 1) Then Exit;
  If N > 1023 Then
  Begin
    ReFail('regular expression too big');
    Exit;
  End;
  For J := 0 To N - 1 Do ReTmp[J] := ReProg[PS + J];
  ReN := PS;
  If (Mn = 0) And (Mx = 0) Then Exit;
  If ReN + (Mn + 4) * (N + 2) + 2 * (Mx - Mn + 1) * (N + 2) > ReMaxProg Then
  Begin
    ReFail('regular expression too big');
    Exit;
  End;
  For K := 1 To Mn Do
    For J := 0 To N - 1 Do
      ReEmit(ReTmp[J].Op, ReTmp[J].C, ReTmp[J].X, ReTmp[J].Y, ReTmp[J].Z);
  If Mx < 0 Then
  Begin
    Inc(ReLoops);
    S0 := ReEmit(ReOpSplit, 0, 1, N + 4, 0);
    ReEmit(ReOpMark, 0, ReLoops Mod 64, 0, 0);
    For J := 0 To N - 1 Do
      ReEmit(ReTmp[J].Op, ReTmp[J].C, ReTmp[J].X, ReTmp[J].Y, ReTmp[J].Z);
    ReEmit(ReOpChk, 0, ReLoops Mod 64, 0, 0);
    ReEmit(ReOpJmp, 0, -(N + 3), 0, 0);
    Exit;
  End;
  Cnt := Mx - Mn;
  S0 := ReN;
  For K := 1 To Cnt Do
  Begin
    ReEmit(ReOpSplit, 0, 1, 0, 0);
    For J := 0 To N - 1 Do
      ReEmit(ReTmp[J].Op, ReTmp[J].C, ReTmp[J].X, ReTmp[J].Y, ReTmp[J].Z);
  End;
  For K := 0 To Cnt - 1 Do
    ReProg[S0 + K * (N + 1)].Y := ReN - (S0 + K * (N + 1));
End;

Procedure ReAtomSeq;
Var PS, Mn, Mx, G, K, Dep, C : LongInt;
    Ch : Char;
    Done, AtStart, NextEnd : Boolean;

  Function AtSeqEnd : Boolean;
  Begin
    If RePos > Length(RePat) Then AtSeqEnd := True
    Else If ReEre Then
      AtSeqEnd := (RePat[RePos] = '|') Or (RePat[RePos] = ')')
    Else AtSeqEnd := (RePat[RePos] = '\') And (RePos < Length(RePat)) And
      ((RePat[RePos + 1] = '|') Or (RePat[RePos + 1] = ')'));
  End;

  Function ReadNum(Var N : LongInt) : Boolean;
  Begin
    ReadNum := False;
    N := 0;
    While (RePos <= Length(RePat)) And (RePat[RePos] >= '0') And
          (RePat[RePos] <= '9') Do
    Begin
      N := N * 10 + Ord(RePat[RePos]) - 48;
      Inc(RePos);
      ReadNum := True;
    End;
  End;

  { intervalle apres '{' ou '\{' : renvoie False si ce n'est pas un
    intervalle valide (ERE : '{' litteral) }
  Function Interval(Var A, B : LongInt) : Boolean;
  Var Sv : LongInt; Okn : Boolean;
  Begin
    Interval := False;
    Sv := RePos;
    Okn := ReadNum(A);
    B := A;
    If (RePos <= Length(RePat)) And (RePat[RePos] = ',') Then
    Begin
      Inc(RePos);
      If Not ReadNum(B) Then B := -1;
      If Not Okn Then A := 0;
    End
    Else If Not Okn Then
    Begin
      RePos := Sv;
      Exit;
    End;
    If ReEre Then
    Begin
      If (RePos <= Length(RePat)) And (RePat[RePos] = '}') Then
      Begin
        Inc(RePos);
        Interval := True;
      End
      Else RePos := Sv;
    End
    Else If (RePos + 1 <= Length(RePat)) And (RePat[RePos] = '\') And
            (RePat[RePos + 1] = '}') Then
    Begin
      RePos := RePos + 2;
      Interval := True;
    End
    Else RePos := Sv;
  End;

  Procedure Quant;
  Var Q : Boolean;
  Begin
    While (RePos <= Length(RePat)) And (Not ReBad) Do
    Begin
      Ch := RePat[RePos];
      Q := False;
      If Ch = '*' Then
      Begin
        Inc(RePos); Mn := 0; Mx := -1; Q := True;
      End
      Else If ReEre And (Ch = '+') Then
      Begin
        Inc(RePos); Mn := 1; Mx := -1; Q := True;
      End
      Else If ReEre And (Ch = '?') Then
      Begin
        Inc(RePos); Mn := 0; Mx := 1; Q := True;
      End
      Else If ReEre And (Ch = '{') Then
      Begin
        Inc(RePos);
        If Interval(Mn, Mx) Then Q := True Else Dec(RePos);
      End
      Else If (Not ReEre) And (Ch = '\') And (RePos < Length(RePat)) Then
      Begin
        If RePat[RePos + 1] = '+' Then
        Begin
          RePos := RePos + 2; Mn := 1; Mx := -1; Q := True;
        End
        Else If RePat[RePos + 1] = '?' Then
        Begin
          RePos := RePos + 2; Mn := 0; Mx := 1; Q := True;
        End
        Else If RePat[RePos + 1] = '{' Then
        Begin
          RePos := RePos + 2;
          If Interval(Mn, Mx) Then Q := True
          Else ReFail('invalid content of \{\}');
        End;
      End;
      If Not Q Then Break;
      ReRepeat(PS, Mn, Mx);
    End;
  End;

Begin
  AtStart := True;
  While (Not AtSeqEnd) And (Not ReBad) Do
  Begin
    PS := ReN;
    C := Ord(RePat[RePos]);
    Ch := RePat[RePos];
    Inc(RePos);
    Done := False;
    If Ch = '\' Then
    Begin
      If RePos > Length(RePat) Then
      Begin
        ReFail('trailing backslash');
        Exit;
      End;
      Ch := RePat[RePos];
      Inc(RePos);
      If (Not ReEre) And (Ch = '(') Then
      Begin
        Inc(ReGroups);
        G := ReGroups;
        If G > 9 Then ReFail('too many groups');
        ReEmit(ReOpSave, 0, 2 * G, 0, 0);
        ReAlt;
        If (RePos + 1 <= Length(RePat)) And (RePat[RePos] = '\') And
           (RePat[RePos + 1] = ')') Then RePos := RePos + 2
        Else ReFail('unmatched ( or \(');
        ReEmit(ReOpSave, 0, 2 * G + 1, 0, 0);
        Done := True;
      End
      Else If (Ch >= '1') And (Ch <= '9') Then
      Begin
        ReEmit(ReOpBref, 0, Ord(Ch) - 48, 0, 0);
        Done := True;
      End
      Else If Ch = 'w' Then
      Begin
        K := ReNewSet;
        For C := 0 To 255 Do If ReIsWord(C) Then ReSetBit(K, C);
        ReEmit(ReOpSet, 0, K, 0, 0); Done := True;
      End
      Else If Ch = 'W' Then
      Begin
        K := ReNewSet;
        For C := 0 To 255 Do If Not ReIsWord(C) Then ReSetBit(K, C);
        ReEmit(ReOpSet, 0, K, 0, 0); Done := True;
      End
      Else If Ch = 's' Then
      Begin
        K := ReNewSet;
        ReSetClass(K, 'space');
        ReEmit(ReOpSet, 0, K, 0, 0); Done := True;
      End
      Else If Ch = 'S' Then
      Begin
        K := ReNewSet;
        For C := 0 To 255 Do
          If Not ((C = 32) Or ((C >= 9) And (C <= 13))) Then ReSetBit(K, C);
        ReEmit(ReOpSet, 0, K, 0, 0); Done := True;
      End
      Else If Ch = 'b' Then
      Begin ReEmit(ReOpWb, 0, 0, 0, 0); Done := True; End
      Else If Ch = 'B' Then
      Begin ReEmit(ReOpNwb, 0, 0, 0, 0); Done := True; End
      Else If Ch = '<' Then
      Begin ReEmit(ReOpWbeg, 0, 0, 0, 0); Done := True; End
      Else If Ch = '>' Then
      Begin ReEmit(ReOpWend, 0, 0, 0, 0); Done := True; End
      Else If Ch = '`' Then
      Begin ReEmit(ReOpBol, 0, 0, 0, 0); Done := True; End
      Else If Ch = '''' Then
      Begin ReEmit(ReOpEol, 0, 0, 0, 0); Done := True; End
      Else If Ch = 'n' Then C := 10
      Else If Ch = 't' Then C := 9
      Else C := Ord(Ch);
      If Not Done Then
      Begin
        If ReIcase And (ReFold(C) <> C) Or
           (ReIcase And (C >= 97) And (C <= 122)) Then
        Begin
          K := ReNewSet;
          ReSetAddC(K, C);
          ReEmit(ReOpSet, 0, K, 0, 0);
        End
        Else ReEmit(ReOpChar, C, 0, 0, 0);
      End;
    End
    Else If ReEre And (Ch = '(') Then
    Begin
      Inc(ReGroups);
      G := ReGroups;
      If G > 9 Then ReFail('too many groups');
      ReEmit(ReOpSave, 0, 2 * G, 0, 0);
      ReAlt;
      If (RePos <= Length(RePat)) And (RePat[RePos] = ')') Then Inc(RePos)
      Else ReFail('unmatched (');
      ReEmit(ReOpSave, 0, 2 * G + 1, 0, 0);
    End
    Else If Ch = '[' Then ReBracket
    Else If Ch = '.' Then ReEmit(ReOpAny, 0, 0, 0, 0)
    Else If (Ch = '^') And (ReEre Or AtStart) Then
      ReEmit(ReOpBol, 0, 0, 0, 0)
    Else If (Ch = '$') And (ReEre Or AtSeqEnd) Then
      ReEmit(ReOpEol, 0, 0, 0, 0)
    Else If (Ch = '*') And AtStart And (Not ReEre) Then
      ReEmit(ReOpChar, 42, 0, 0, 0)
    Else If ReEre And ((Ch = '*') Or (Ch = '+') Or (Ch = '?')) And
            AtStart Then
      ReEmit(ReOpChar, C, 0, 0, 0)
    Else
    Begin
      If ReIcase And (((C >= 65) And (C <= 90)) Or
                      ((C >= 97) And (C <= 122))) Then
      Begin
        K := ReNewSet;
        ReSetAddC(K, C);
        ReEmit(ReOpSet, 0, K, 0, 0);
      End
      Else ReEmit(ReOpChar, C, 0, 0, 0);
    End;
    AtStart := False;
    { quantificateurs }
    If ReProg[PS].Op <> ReOpBol Then Quant
    Else If ReEre Then Quant;
    { un groupe ou un atome quantifie : le bloc [PS, ReN) }
    If ReBad Then Exit;
  End;
End;

Procedure ReAlt;
Var S, J : LongInt; HaveAlt : Boolean;
Begin
  S := ReN;
  ReAtomSeq;
  If ReBad Then Exit;
  HaveAlt := False;
  If ReEre Then HaveAlt := (RePos <= Length(RePat)) And (RePat[RePos] = '|')
  Else HaveAlt := (RePos < Length(RePat)) And (RePat[RePos] = '\') And
                  (RePat[RePos + 1] = '|');
  If HaveAlt Then
  Begin
    ReHasAlt := True;
    If ReEre Then Inc(RePos) Else RePos := RePos + 2;
    ReInsert(S, ReOpSplit, 1, 0);
    J := ReEmit(ReOpJmp, 0, 0, 0, 0);
    ReProg[S].Y := J - S + 1;
    ReAlt;
    ReProg[J].X := ReN - J;
  End;
End;

{ compile Pat ; renvoie l'adresse du programme ou -1 }
Function ReCompile(Const Pat : String; Ere, Icase : Boolean) : LongInt;
Var Start : LongInt;
Begin
  RePat := Pat;
  RePos := 1;
  ReEre := Ere;
  ReIcase := Icase;
  ReBad := False;
  ReErr := '';
  ReGroups := 0;
  ReLoops := 0;
  ReHasAlt := False;
  Start := ReN;
  ReEmit(ReOpSave, 0, 0, 0, 0);
  ReAlt;
  If (Not ReBad) And (RePos <= Length(RePat)) Then
  Begin
    If ReEre Then ReFail('unmatched )')
    Else ReFail('unmatched \)');
  End;
  ReEmit(ReOpSave, 0, 1, 0, 0);
  ReEmit(ReOpMatch, 0, 0, 0, 0);
  If ReBad Then
  Begin
    ReN := Start;
    ReCompile := -1;
    Exit;
  End;
  { le drapeau "alternative" est range dans le Z de l'instruction de tete }
  If ReHasAlt Then ReProg[Start].Z := 1 Else ReProg[Start].Z := 0;
  ReProg[Start].Y := ReGroups;
  ReCompile := Start;
End;

{ ---------- execution ---------- }

Function ReWordAt(P : LongInt) : Boolean;
Begin
  If (P < 0) Or (P >= ReLen) Then ReWordAt := False
  Else ReWordAt := ReIsWord(Mem[0:ReBase + P]);
End;

Function ReRun(Pc0, Sp0 : LongInt) : Boolean;
Var Pc, Sp, K, N, Mx, I, C, Old, G0, G1 : LongInt;
    Op : LongInt;
Begin
  Pc := Pc0;
  Sp := Sp0;
  ReRun := False;
  While True Do
  Begin
    Op := ReProg[Pc].Op;
    Case Op Of
      ReOpChar :
        If (Sp < ReLen) And (Mem[0:ReBase + Sp] = ReProg[Pc].C) Then
        Begin
          Inc(Pc);
          Inc(Sp);
        End
        Else Exit;
      ReOpAny :
        If Sp < ReLen Then
        Begin
          Inc(Pc);
          Inc(Sp);
        End
        Else Exit;
      ReOpSet :
        If (Sp < ReLen) And ReGetBit(ReProg[Pc].X, Mem[0:ReBase + Sp]) Then
        Begin
          Inc(Pc);
          Inc(Sp);
        End
        Else Exit;
      ReOpBol :
        If Sp = 0 Then Inc(Pc) Else Exit;
      ReOpEol :
        If Sp = ReLen Then Inc(Pc) Else Exit;
      ReOpWb :
        If ReWordAt(Sp - 1) <> ReWordAt(Sp) Then Inc(Pc) Else Exit;
      ReOpNwb :
        If ReWordAt(Sp - 1) = ReWordAt(Sp) Then Inc(Pc) Else Exit;
      ReOpWbeg :
        If (Not ReWordAt(Sp - 1)) And ReWordAt(Sp) Then Inc(Pc) Else Exit;
      ReOpWend :
        If ReWordAt(Sp - 1) And (Not ReWordAt(Sp)) Then Inc(Pc) Else Exit;
      ReOpSave :
        Begin
          K := ReProg[Pc].X;
          Old := ReCap[K];
          ReCap[K] := Sp;
          If ReRun(Pc + 1, Sp) Then
          Begin
            ReRun := True;
            Exit;
          End;
          ReCap[K] := Old;
          Exit;
        End;
      ReOpSplit :
        Begin
          If ReRun(Pc + ReProg[Pc].X, Sp) Then
          Begin
            ReRun := True;
            Exit;
          End;
          Pc := Pc + ReProg[Pc].Y;
        End;
      ReOpJmp :
        Pc := Pc + ReProg[Pc].X;
      ReOpNop :
        Inc(Pc);
      ReOpMark :
        Begin
          K := ReProg[Pc].X;
          Old := ReMarks[K];
          ReMarks[K] := Sp;
          If ReRun(Pc + 1, Sp) Then
          Begin
            ReRun := True;
            Exit;
          End;
          ReMarks[K] := Old;
          Exit;
        End;
      ReOpChk :
        If ReMarks[ReProg[Pc].X] <> Sp Then Inc(Pc) Else Exit;
      ReOpBref :
        Begin
          K := ReProg[Pc].X;
          G0 := ReCap[2 * K];
          G1 := ReCap[2 * K + 1];
          If (G0 < 0) Or (G1 < G0) Then Exit;
          N := G1 - G0;
          If Sp + N > ReLen Then Exit;
          For I := 0 To N - 1 Do
            If Mem[0:ReBase + G0 + I] <> Mem[0:ReBase + Sp + I] Then Exit;
          Sp := Sp + N;
          Inc(Pc);
        End;
      ReOpStar :
        Begin
          Mx := ReProg[Pc].Z;
          If (Mx < 0) Or (Mx > ReLen - Sp) Then Mx := ReLen - Sp;
          N := 0;
          K := ReProg[Pc].X;
          If K <= -300 Then N := Mx
          Else If K < 0 Then
          Begin
            C := -1 - K;
            While (N < Mx) And (Mem[0:ReBase + Sp + N] = C) Do Inc(N);
          End
          Else
            While (N < Mx) And ReGetBit(K, Mem[0:ReBase + Sp + N]) Do
              Inc(N);
          If N < ReProg[Pc].Y Then Exit;
          I := N;
          While I >= ReProg[Pc].Y Do
          Begin
            If ReRun(Pc + 1, Sp + I) Then
            Begin
              ReRun := True;
              Exit;
            End;
            Dec(I);
          End;
          Exit;
        End;
      ReOpMatch :
        Begin
          If ReLongest Then
          Begin
            If Sp > ReBest Then
            Begin
              ReBest := Sp;
              For K := 0 To 19 Do ReBestCap[K] := ReCap[K];
              ReBestCap[1] := Sp;
            End;
            Exit;
          End;
          ReCap[1] := Sp;
          ReRun := True;
          Exit;
        End;
    Else
      Exit;
    End;
  End;
End;

{ cherche le programme Prog dans Mem[0:Base .. Base+Len-1] a partir de From ;
  Vrai si trouve ; ReCap[0..1] = debut/fin }
Function ReSearch(Prog, Base, Len, From : LongInt; Longest : Boolean)
         : Boolean;
Var S, K, FirstC : LongInt;
Begin
  ReBase := Base;
  ReLen := Len;
  ReSearch := False;
  ReLongest := Longest And (ReProg[Prog].Z = 1);
  FirstC := -1;
  If (ReProg[Prog + 1].Op = ReOpChar) Then FirstC := ReProg[Prog + 1].C;
  S := From;
  While S <= Len Do
  Begin
    If (FirstC >= 0) And (S < Len) And (Mem[0:Base + S] <> FirstC) Then
    Begin
      Inc(S);
      Continue;
    End;
    If (FirstC >= 0) And (S >= Len) Then Break;
    For K := 0 To 19 Do ReCap[K] := -1;
    ReBest := -1;
    If ReLongest Then
    Begin
      ReRun(Prog, S);
      If ReBest >= 0 Then
      Begin
        For K := 0 To 19 Do ReCap[K] := ReBestCap[K];
        ReSearch := True;
        Exit;
      End;
    End
    Else If ReRun(Prog, S) Then
    Begin
      ReSearch := True;
      Exit;
    End;
    Inc(S);
  End;
End;
