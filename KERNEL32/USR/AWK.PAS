{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2026
  @website(https://www.gladir.com/linux-0)
  @abstract(Target: LPC -3X)
  @description: /bin/awk : interpreteur awk POSIX (variantes gawk courantes) :
      -F -v -f --, motifs BEGIN/END/expr/regex/plage, fonctions, tableaux
      associatifs, getline (toutes formes), printf, redirections et tubes,
      expressions regulieres ERE (REGEX.INC), variables NR NF FNR FS OFS ORS
      RS FILENAME SUBSEP RSTART RLENGTH CONVFMT OFMT ENVIRON ARGC ARGV,
      fonctions chaines (length substr index split sub gsub match sprintf
      tolower toupper) et numeriques (sin cos atan2 exp log sqrt int rand
      srand), system, close, fflush, systime.
}

Program AWK;

{$I REGEX.INC}

Const
  UsageW : Array[1..5] Of PChar =
    ('Usage : ', 'Usage: ', 'Aufruf: ', 'Uso: ', 'Uso: ');
  ArenaMax = 4194303;
  MaxNode = 8000;
  MaxTok = 12000;
  MaxCell = 6000;
  MaxFld = 4000;
  MaxFn = 100;
  RecMax = 262143;
  { jetons }
  tEOF = 0;  tNL = 1;  tNum = 2;  tStr = 3;  tEre = 4;  tName = 5;
  tFunc = 6; tBuiltin = 7; tKw = 8; tOp = 9;
  { noeuds }
  nNum = 1; nStr = 2; nRe = 3; nVar = 4; nIdx = 5; nFld = 6; nAsg = 7;
  nCond = 8; nOr = 9; nAnd = 10; nIn = 11; nMatch = 12; nNmatch = 13;
  nCmp = 14; nCat = 15; nBin = 16; nNeg = 17; nPlus = 18; nNot = 19;
  nPre = 20; nPost = 21; nCall = 22; nBi = 23; nGetl = 24; nGroup = 25;
  nInM = 26;
  sExpr = 40; sPrint = 41; sPrintf = 42; sIf = 43; sWhile = 44; sDo = 45;
  sFor = 46; sForIn = 47; sBlock = 48; sNext = 49; sNextF = 50; sExit = 51;
  sRet = 52; sBreak = 53; sCont = 54; sDel = 55; sDelAll = 56; sGetl = 57;

Type
  TVal = Record
    F : LongInt;
    N : Double;
    P, L : LongInt;
    C : LongInt;
  End;
  TNode = Record
    Op : LongInt;
    A, B, C, D : LongInt;
    X : Double;
    S : String;
  End;
  TCell = Record
    Kind : LongInt;        { 0 libre, 1 scalaire, 2 tableau, 3 alias }
    V : TVal;
    Arr : LongInt;
    Ref : LongInt;
  End;
  TArr = Record
    Used : Boolean;
    Buckets : LongInt;
    NB, Cnt : LongInt;
    First, Last : LongInt;
  End;

Const
  MaxEnt = 100000;

Var
  EKeyP, EKeyL, ENext, EPrev, EChain : Array[1..MaxEnt] Of LongInt;
  EVal : Array[1..MaxEnt] Of TVal;
  EFree, ENew : LongInt;
  Arena : Array[0..ArenaMax] Of Byte;
  ATop : LongInt;
  Nodes : Array[1..MaxNode] Of TNode;
  NNode : LongInt;
  TokT : Array[0..MaxTok] Of Byte;
  TokV : Array[0..MaxTok] Of LongInt;
  TokO : Array[0..MaxTok] Of LongInt;
  TokX : Array[0..MaxTok] Of Double;
  NTok, TP : LongInt;
  Src : Array[0..131071] Of Char;
  SrcN : LongInt;
  Cells : Array[0..MaxCell] Of TCell;
  NGlob, SP0, SPTop : LongInt;
  GNames : Array[0..255] Of String;
  Arrs : Array[0..255] Of TArr;
  NArr : LongInt;
  RV : TVal;
  OutBuf : Array[0..32767] Of Char;
  OutN : LongInt;
  Status : LongInt;

Const
  vNF = 0; vNR = 1; vFNR = 2; vFS = 3; vOFS = 4; vORS = 5; vRS = 6;
  vFILENAME = 7; vSUBSEP = 8; vRSTART = 9; vRLENGTH = 10; vCONVFMT = 11;
  vOFMT = 12; vENVIRON = 13; vARGC = 14; vARGV = 15; NSpecial = 16;

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

Procedure FlushOut;
Begin
  If OutN > 0 Then SysWrite(1, OutBuf[0], OutN);
  OutN := 0;
End;

Procedure OutMem(Base, N : LongInt);
Var K : LongInt;
Begin
  For K := 0 To N - 1 Do
  Begin
    If OutN >= 32768 Then FlushOut;
    OutBuf[OutN] := Chr(Mem[0:Base + K]);
    Inc(OutN);
  End;
End;

Procedure Die(Const Msg : String);
Begin
  FlushOut;
  SysPut(2, 'awk: ' + Msg + #10);
  SysExit(2);
End;

{ ---------- memoire ---------- }

Function ANew(Len : LongInt) : LongInt;
Begin
  If ATop + Len + 2 > ArenaMax Then Die('memoire de travail epuisee');
  ANew := LongInt(@Arena[0]) + ATop;
  ATop := ATop + Len + 1;
End;

Function PNew(Len : LongInt) : LongInt;
Var Pt : Pointer;
Begin
  GetMem(Pt, Len + 1);
  If Pt = Nil Then Die('memoire epuisee');
  PNew := LongInt(Pt);
End;

Procedure PFree(A : LongInt);
Var Pt : Pointer;
Begin
  If A <> 0 Then
  Begin
    Pt := Pointer(A);
    FreeMem(Pt, 1);
  End;
End;

Procedure MCopy(Dst, Src, N : LongInt);
Begin
  If N <= 0 Then Exit;
  asm
    push esi
    push edi
    mov esi, Src
    mov edi, Dst
    mov ecx, N
    cmp edi, esi
    jbe @fwd
    lea esi, [esi+ecx-1]
    lea edi, [edi+ecx-1]
    std
    rep movsb
    cld
    jmp @done
  @fwd:
    cld
    rep movsb
  @done:
    pop edi
    pop esi
  end;
End;

{ copie permanente de (P,L) : renvoie l'adresse }
Function PDup(P, L : LongInt) : LongInt;
Var A : LongInt;
Begin
  A := PNew(L);
  If L > 0 Then MCopy(A, P, L);
  Mem[0:A + L] := 0;
  PDup := A;
End;

Function ADup(P, L : LongInt) : LongInt;
Var A : LongInt;
Begin
  A := ANew(L);
  If L > 0 Then MCopy(A, P, L);
  Mem[0:A + L] := 0;
  ADup := A;
End;

Function SGet(P, L : LongInt) : String;
Var S : String; K : LongInt;
Begin
  S := '';
  If L > 255 Then L := 255;
  For K := 0 To L - 1 Do S := S + Chr(Mem[0:P + K]);
  SGet := S;
End;

Procedure SetStr(Var V : TVal; Const S : String);
Var A, K : LongInt;
Begin
  A := ANew(Length(S));
  For K := 1 To Length(S) Do Mem[0:A + K - 1] := Ord(S[K]);
  Mem[0:A + Length(S)] := 0;
  V.F := 2;
  V.P := A;
  V.L := Length(S);
  V.N := 0.0;
End;

Procedure SetNum(Var V : TVal; X : Double);
Begin
  V.F := 1;
  V.N := X;
  V.P := 0;
  V.L := 0;
End;

{ ---------- nombres ---------- }

Function Pow10(N : LongInt) : Extended;
Var R, B : Extended; Neg : Boolean;
Begin
  Neg := N < 0;
  If Neg Then N := -N;
  R := 1.0;
  B := 10.0;
  While N > 0 Do
  Begin
    If (N And 1) <> 0 Then R := R * B;
    B := B * B;
    N := N Shr 1;
  End;
  If Neg Then Pow10 := 1.0 / R Else Pow10 := R;
End;

Function IsSp(C : LongInt) : Boolean;
Begin
  IsSp := (C = 32) Or ((C >= 9) And (C <= 13));
End;

{ analyse d'un nombre au debut de (P,L) ; Len = octets consommes (0 : aucun) }
Function ParseNum(P, L : LongInt; Var Used : LongInt) : Double;
Var I, C, Dg, Ex, EV : LongInt; Neg, EN, Any : Boolean;
    M : Extended; Fr : LongInt;
Begin
  I := 0;
  Used := 0;
  ParseNum := 0.0;
  While (I < L) And IsSp(Mem[0:P + I]) Do Inc(I);
  Neg := False;
  If (I < L) And ((Mem[0:P + I] = 43) Or (Mem[0:P + I] = 45)) Then
  Begin
    Neg := Mem[0:P + I] = 45;
    Inc(I);
  End;
  M := 0.0;
  Any := False;
  Ex := 0;
  Dg := 0;
  While (I < L) And (Mem[0:P + I] >= 48) And (Mem[0:P + I] <= 57) Do
  Begin
    Any := True;
    If Dg < 19 Then
    Begin
      M := M * 10.0 + (Mem[0:P + I] - 48);
      If M <> 0.0 Then Inc(Dg);
    End
    Else Inc(Ex);
    Inc(I);
  End;
  If (I < L) And (Mem[0:P + I] = 46) Then
  Begin
    Inc(I);
    While (I < L) And (Mem[0:P + I] >= 48) And (Mem[0:P + I] <= 57) Do
    Begin
      Any := True;
      If Dg < 19 Then
      Begin
        M := M * 10.0 + (Mem[0:P + I] - 48);
        If M <> 0.0 Then Inc(Dg);
        Dec(Ex);
      End;
      Inc(I);
    End;
  End;
  If Not Any Then Exit;
  If (I < L) And ((Mem[0:P + I] = 101) Or (Mem[0:P + I] = 69)) Then
  Begin
    C := I + 1;
    EN := False;
    If (C < L) And ((Mem[0:P + C] = 43) Or (Mem[0:P + C] = 45)) Then
    Begin
      EN := Mem[0:P + C] = 45;
      Inc(C);
    End;
    If (C < L) And (Mem[0:P + C] >= 48) And (Mem[0:P + C] <= 57) Then
    Begin
      EV := 0;
      While (C < L) And (Mem[0:P + C] >= 48) And (Mem[0:P + C] <= 57) Do
      Begin
        If EV < 10000 Then EV := EV * 10 + Mem[0:P + C] - 48;
        Inc(C);
      End;
      If EN Then EV := -EV;
      Ex := Ex + EV;
      I := C;
    End;
  End;
  If Ex > 4000 Then Ex := 4000;
  If Ex < -4000 Then Ex := -4000;
  If M <> 0.0 Then
  Begin
    If Ex > 0 Then M := M * Pow10(Ex)
    Else If Ex < 0 Then M := M / Pow10(-Ex);
  End;
  If Neg Then M := -M;
  Used := I;
  ParseNum := M;
End;

Function StrNum(P, L : LongInt) : Double;
Var U : LongInt;
Begin
  StrNum := ParseNum(P, L, U);
End;

{ la chaine ressemble-t-elle a un nombre (espaces autorises) ? }
Function LooksNum(P, L : LongInt) : Boolean;
Var U : LongInt;
Begin
  LooksNum := False;
  If L = 0 Then Exit;
  ParseNum(P, L, U);
  If U = 0 Then Exit;
  While (U < L) And IsSp(Mem[0:P + U]) Do Inc(U);
  LooksNum := U = L;
End;

{ chiffres decimaux de X (>= 0, entier) dans une chaine }
Function IntDigits(X : Extended) : String;
Var S : String;
Begin
  If X < 1.0E17 Then
  Begin
    Str(X:0:0, S);
    IntDigits := S;
    Exit;
  End;
  { grand : mantisse a 17 chiffres puis zeros }
  IntDigits := '1E17+';
End;

{ format %e/%E : chiffres significatifs en prec+1 chiffres ; Sig = chaine
  de chiffres, E10 = exposant decimal }
Procedure Decomp(X : Extended; NDig : LongInt; Var Dig : String;
                 Var E10 : LongInt);
Var M, Sc, R : Extended; K : LongInt;
Begin
  If X = 0.0 Then
  Begin
    Dig := '';
    For K := 1 To NDig Do Dig := Dig + '0';
    E10 := 0;
    Exit;
  End;
  E10 := Trunc(Ln(X) / Ln(10.0));
  If Pow10(E10) > X Then Dec(E10);
  If Pow10(E10 + 1) <= X Then Inc(E10);
  If NDig > 17 Then NDig := 17;
  Sc := Pow10(NDig - 1 - E10);
  If (NDig - 1 - E10) > 4000 Then Sc := 1.0;
  If (NDig - 1 - E10) > 300 Then
    M := (X * Pow10(300)) * Pow10(NDig - 1 - E10 - 300)
  Else M := X * Sc;
  R := Int(M + 0.5);
  If R >= Pow10(NDig) Then
  Begin
    R := Int(R / 10.0 + 0.5);
    Inc(E10);
  End;
  Str(R:0:0, Dig);
  While Length(Dig) < NDig Do Dig := '0' + Dig;
  If Length(Dig) > NDig Then Dig := Copy(Dig, 1, NDig);
End;

Function Spaces(N : LongInt; C : Char) : String;
Var S : String; K : LongInt;
Begin
  S := '';
  For K := 1 To N Do S := S + C;
  Spaces := S;
End;

{ %f }
Function FmtF(X : Extended; Prec : LongInt) : String;
Var Dig, Ip, Fp : String; E10, K, NDig : LongInt;
Begin
  If X < 0.0 Then X := -X;
  If X >= 1.0E17 Then
  Begin
    { grand nombre : chiffres de tete exacts puis zeros }
    Decomp(X, 17, Dig, E10);
    Ip := Dig + Spaces(E10 - 16, '0');
    If Prec > 0 Then Ip := Ip + '.' + Spaces(Prec, '0');
    FmtF := Ip;
    Exit;
  End;
  If Prec > 17 Then Prec := 17;
  Str(X:0:Prec, Ip);
  FmtF := Ip;
End;

{ %e }
Function FmtE(X : Extended; Prec : LongInt; Upper : Boolean) : String;
Var Dig, R, Ex : String; E10 : LongInt;
Begin
  If X < 0.0 Then X := -X;
  Decomp(X, Prec + 1, Dig, E10);
  R := Copy(Dig, 1, 1);
  If Prec > 0 Then R := R + '.' + Copy(Dig, 2, Prec);
  If E10 < 0 Then Ex := '-' Else Ex := '+';
  If Abs(E10) < 10 Then Ex := Ex + '0';
  Ex := Ex + NumS(Abs(E10));
  If Upper Then FmtE := R + 'E' + Ex Else FmtE := R + 'e' + Ex;
End;

{ %g }
Function FmtG(X : Extended; Prec : LongInt; Alt, Upper : Boolean) : String;
Var Dig, R, Ex : String; E10, K, L : LongInt;
Begin
  If X < 0.0 Then X := -X;
  If Prec = 0 Then Prec := 1;
  If X = 0.0 Then
  Begin
    If Alt Then FmtG := '0.' + Spaces(Prec - 1, '0') Else FmtG := '0';
    Exit;
  End;
  Decomp(X, Prec, Dig, E10);
  If (E10 < -4) Or (E10 >= Prec) Then
  Begin
    R := Copy(Dig, 1, 1);
    L := Length(Dig);
    If Not Alt Then
      While (L > 1) And (Dig[L] = '0') Do Dec(L);
    If L > 1 Then R := R + '.' + Copy(Dig, 2, L - 1);
    If E10 < 0 Then Ex := '-' Else Ex := '+';
    If Abs(E10) < 10 Then Ex := Ex + '0';
    Ex := Ex + NumS(Abs(E10));
    If Upper Then FmtG := R + 'E' + Ex Else FmtG := R + 'e' + Ex;
    Exit;
  End;
  If E10 >= 0 Then
  Begin
    R := Copy(Dig, 1, E10 + 1);
    Dig := Copy(Dig, E10 + 2, 40);
  End
  Else
  Begin
    R := '0';
    Dig := Spaces(-E10 - 1, '0') + Dig;
  End;
  If Not Alt Then
  Begin
    L := Length(Dig);
    While (L > 0) And (Dig[L] = '0') Do Dec(L);
    Dig := Copy(Dig, 1, L);
  End;
  If Dig <> '' Then R := R + '.' + Dig
  Else If Alt Then R := R + '.';
  FmtG := R;
End;

{ nombre -> texte selon le format Fmt (CONVFMT ou OFMT) ; entiers sans point }
Function NumToStr(X : Double; Const Fmt : String) : String;
Var S : String; Neg : Boolean; E : Extended; Prec, K : LongInt; Conv : Char;
Begin
  E := X;
  If X <> X Then
  Begin
    NumToStr := 'nan';
    Exit;
  End;
  If (E > 1.0E300) Then
  Begin
    NumToStr := 'inf';
    Exit;
  End;
  If (E < -1.0E300) Then
  Begin
    NumToStr := '-inf';
    Exit;
  End;
  Neg := E < 0.0;
  If Neg Then E := -E;
  If (E = Int(E)) And (E < 1.0E30) Then
  Begin
    If E = 0.0 Then
      S := '0'
    Else
    Begin
      S := FmtF(E, 0);
      If Neg Then S := '-' + S;
    End;
    NumToStr := S;
    Exit;
  End;
  { format %.<p>g (CONVFMT, OFMT) }
  If Neg Then S := '-' Else S := '';
  Prec := 6;
  Conv := 'g';
  K := Pos('.', Fmt);
  If K > 0 Then
  Begin
    Prec := 0;
    Inc(K);
    While (K <= Length(Fmt)) And (Fmt[K] >= '0') And (Fmt[K] <= '9') Do
    Begin
      Prec := Prec * 10 + Ord(Fmt[K]) - 48;
      Inc(K);
    End;
    If K <= Length(Fmt) Then Conv := Fmt[K];
  End;
  If Conv = 'f' Then NumToStr := S + FmtF(E, Prec)
  Else If (Conv = 'e') Or (Conv = 'E') Then
    NumToStr := S + FmtE(E, Prec, Conv = 'E')
  Else NumToStr := S + FmtG(E, Prec, False, Conv = 'G');
End;

{ ---------- jetons ---------- }

Const
  oInc = 128; oDec = 129; oAddA = 130; oSubA = 131; oMulA = 132;
  oDivA = 133; oModA = 134; oPowA = 135; oEq = 136; oLe = 137; oGe = 138;
  oNe = 139; oNmatch = 140; oAnd = 141; oOr = 142; oApp = 143;
  kBEGIN = 1; kEND = 2; kFunction = 3; kIf = 4; kElse = 5; kWhile = 6;
  kFor = 7; kDo = 8; kBreak = 9; kContinue = 10; kNext = 11; kNextFile = 12;
  kExit = 13; kReturn = 14; kDelete = 15; kIn = 16; kGetline = 17;
  kPrint = 18; kPrintf = 19;
  bLength = 1; bSubstr = 2; bIndex = 3; bSplit = 4; bSub = 5; bGsub = 6;
  bMatch = 7; bSprintf = 8; bSin = 9; bCos = 10; bAtan2 = 11; bExp = 12;
  bLog = 13; bSqrt = 14; bInt = 15; bRand = 16; bSrand = 17; bTolower = 18;
  bToupper = 19; bSystem = 20; bClose = 21; bFflush = 22; bSystime = 23;

Var
  SPool : Array[0..262143] Of Char;
  SPoolN : LongInt;
  TokL : Array[0..MaxTok] Of LongInt;
  Line : LongInt;
  FnName : Array[1..MaxFn] Of String;
  FnBody, FnNPar, FnDefined : Array[1..MaxFn] Of LongInt;
  NFn : LongInt;
  CurFn : LongInt;
  Params : Array[1..32] Of String;
  NParams : LongInt;
  NoGt, NoIn : Boolean;
  RuleK, RuleP1, RuleP2, RuleAct : Array[1..400] Of LongInt;
  RuleOn : Array[1..400] Of Boolean;
  NRule : LongInt;

Function TokStr(I : LongInt) : String;
Var S : String; K : LongInt;
Begin
  S := '';
  For K := 0 To TokL[I] - 1 Do
    If Length(S) < 255 Then S := S + SPool[TokO[I] + K];
  TokStr := S;
End;

Procedure SynErr(Const Msg : String);
Begin
  Die('erreur de syntaxe ligne ' + NumS(Line) + ' : ' + Msg);
End;

Procedure AddTok(T : LongInt; V : LongInt; Const S : String; X : Double);
Var K : LongInt;
Begin
  If NTok >= MaxTok Then Die('programme trop long');
  TokT[NTok] := T;
  TokV[NTok] := V;
  TokX[NTok] := X;
  TokO[NTok] := SPoolN;
  TokL[NTok] := Length(S);
  For K := 1 To Length(S) Do
  Begin
    If SPoolN < 262143 Then
    Begin
      SPool[SPoolN] := S[K];
      Inc(SPoolN);
    End;
  End;
  Inc(NTok);
End;

Function KwId(Const S : String) : LongInt;
Begin
  KwId := 0;
  If S = 'BEGIN' Then KwId := kBEGIN
  Else If S = 'END' Then KwId := kEND
  Else If (S = 'function') Or (S = 'func') Then KwId := kFunction
  Else If S = 'if' Then KwId := kIf
  Else If S = 'else' Then KwId := kElse
  Else If S = 'while' Then KwId := kWhile
  Else If S = 'for' Then KwId := kFor
  Else If S = 'do' Then KwId := kDo
  Else If S = 'break' Then KwId := kBreak
  Else If S = 'continue' Then KwId := kContinue
  Else If S = 'next' Then KwId := kNext
  Else If S = 'nextfile' Then KwId := kNextFile
  Else If S = 'exit' Then KwId := kExit
  Else If S = 'return' Then KwId := kReturn
  Else If S = 'delete' Then KwId := kDelete
  Else If S = 'in' Then KwId := kIn
  Else If S = 'getline' Then KwId := kGetline
  Else If S = 'print' Then KwId := kPrint
  Else If S = 'printf' Then KwId := kPrintf;
End;

Function BiId(Const S : String) : LongInt;
Begin
  BiId := 0;
  If S = 'length' Then BiId := bLength
  Else If S = 'substr' Then BiId := bSubstr
  Else If S = 'index' Then BiId := bIndex
  Else If S = 'split' Then BiId := bSplit
  Else If S = 'sub' Then BiId := bSub
  Else If S = 'gsub' Then BiId := bGsub
  Else If S = 'match' Then BiId := bMatch
  Else If S = 'sprintf' Then BiId := bSprintf
  Else If S = 'sin' Then BiId := bSin
  Else If S = 'cos' Then BiId := bCos
  Else If S = 'atan2' Then BiId := bAtan2
  Else If S = 'exp' Then BiId := bExp
  Else If S = 'log' Then BiId := bLog
  Else If S = 'sqrt' Then BiId := bSqrt
  Else If S = 'int' Then BiId := bInt
  Else If S = 'rand' Then BiId := bRand
  Else If S = 'srand' Then BiId := bSrand
  Else If S = 'tolower' Then BiId := bTolower
  Else If S = 'toupper' Then BiId := bToupper
  Else If S = 'system' Then BiId := bSystem
  Else If S = 'close' Then BiId := bClose
  Else If S = 'fflush' Then BiId := bFflush
  Else If S = 'systime' Then BiId := bSystime;
End;

Function IsOperandTok(T, V : LongInt) : Boolean;
Begin
  IsOperandTok := (T = tNum) Or (T = tStr) Or (T = tName) Or
    (T = tBuiltin) Or ((T = tOp) And ((V = 41) Or (V = 93) Or
    (V = oInc) Or (V = oDec) Or (V = 36)));
End;

Procedure Lex;
Var I, C, K, D : LongInt; S : String; X : Double; Pr : LongInt;
    InBr : Boolean; Id : LongInt; Used : LongInt;
    PT, PV : LongInt;

  Function Peek(O : LongInt) : LongInt;
  Begin
    If I + O < SrcN Then Peek := Ord(Src[I + O]) Else Peek := 0;
  End;

Begin
  I := 0;
  Line := 1;
  NTok := 0;
  SPoolN := 0;
  While I < SrcN Do
  Begin
    C := Ord(Src[I]);
    If (C = 32) Or (C = 9) Or (C = 13) Then
    Begin
      Inc(I);
      Continue;
    End;
    If (C = 92) And (Peek(1) = 10) Then
    Begin
      I := I + 2;
      Inc(Line);
      Continue;
    End;
    If (C = 92) And (Peek(1) = 13) And (Peek(2) = 10) Then
    Begin
      I := I + 3;
      Inc(Line);
      Continue;
    End;
    If C = 35 Then
    Begin
      While (I < SrcN) And (Src[I] <> #10) Do Inc(I);
      Continue;
    End;
    If C = 10 Then
    Begin
      AddTok(tNL, 0, '', 0.0);
      Inc(Line);
      Inc(I);
      Continue;
    End;
    If ((C >= 48) And (C <= 57)) Or ((C = 46) And (Peek(1) >= 48) And
       (Peek(1) <= 57)) Then
    Begin
      X := ParseNum(LongInt(@Src[I]), SrcN - I, Used);
      If (C = 48) And ((Peek(1) = 120) Or (Peek(1) = 88)) Then
      Begin
        K := I + 2;
        X := 0.0;
        While (K < SrcN) And (((Src[K] >= '0') And (Src[K] <= '9')) Or
              ((Src[K] >= 'a') And (Src[K] <= 'f')) Or
              ((Src[K] >= 'A') And (Src[K] <= 'F'))) Do
        Begin
          If Src[K] <= '9' Then D := Ord(Src[K]) - 48
          Else D := (Ord(Src[K]) Or 32) - 87;
          X := X * 16.0 + D;
          Inc(K);
        End;
        Used := K - I;
      End;
      AddTok(tNum, 0, '', X);
      I := I + Used;
      Continue;
    End;
    If C = 34 Then
    Begin
      S := '';
      Inc(I);
      While (I < SrcN) And (Src[I] <> '"') Do
      Begin
        If Src[I] = #10 Then SynErr('chaine non terminee');
        If Src[I] = '\' Then
        Begin
          Inc(I);
          K := Peek(0);
          Case Chr(K) Of
            'n' : S := S + #10;
            't' : S := S + #9;
            'r' : S := S + #13;
            '\' : S := S + '\';
            '"' : S := S + '"';
            '/' : S := S + '/';
            'a' : S := S + #7;
            'b' : S := S + #8;
            'f' : S := S + #12;
            'v' : S := S + #11;
            #10 : Inc(Line);
            '0'..'7' :
              Begin
                D := 0;
                K := 0;
                While (K < 3) And (Peek(0) >= 48) And (Peek(0) <= 55) Do
                Begin
                  D := D * 8 + Peek(0) - 48;
                  Inc(I);
                  Inc(K);
                End;
                Dec(I);
                S := S + Chr(D And 255);
              End;
          Else
            S := S + '\' + Chr(K);
          End;
          Inc(I);
        End
        Else
        Begin
          S := S + Src[I];
          Inc(I);
        End;
      End;
      Inc(I);
      AddTok(tStr, 0, S, 0.0);
      Continue;
    End;
    If (C = 47) Then
    Begin
      PT := -1;
      PV := 0;
      If NTok > 0 Then
      Begin
        PT := TokT[NTok - 1];
        PV := TokV[NTok - 1];
        If PT = tOp Then PV := TokV[NTok - 1];
      End;
      If Not ((NTok > 0) And IsOperandTok(PT, PV)) Then
      Begin
        { litteral regex }
        S := '';
        Inc(I);
        InBr := False;
        While (I < SrcN) And ((Src[I] <> '/') Or InBr) Do
        Begin
          If Src[I] = #10 Then SynErr('regex non terminee');
          If (Src[I] = '\') And (I + 1 < SrcN) Then
          Begin
            If Src[I + 1] = '/' Then S := S + '/'
            Else S := S + '\' + Src[I + 1];
            I := I + 2;
            Continue;
          End;
          If (Src[I] = '[') And (Not InBr) Then
          Begin
            InBr := True;
            S := S + '[';
            Inc(I);
            If (I < SrcN) And (Src[I] = '^') Then
            Begin
              S := S + '^';
              Inc(I);
            End;
            If (I < SrcN) And (Src[I] = ']') Then
            Begin
              S := S + ']';
              Inc(I);
            End;
            Continue;
          End;
          If (Src[I] = ']') And InBr Then InBr := False;
          S := S + Src[I];
          Inc(I);
        End;
        Inc(I);
        AddTok(tEre, 0, S, 0.0);
        Continue;
      End;
    End;
    If ((C >= 65) And (C <= 90)) Or ((C >= 97) And (C <= 122)) Or
       (C = 95) Then
    Begin
      S := '';
      While (I < SrcN) And (ReIsWord(Ord(Src[I]))) Do
      Begin
        S := S + Src[I];
        Inc(I);
      End;
      Id := KwId(S);
      If Id <> 0 Then AddTok(tKw, Id, S, 0.0)
      Else
      Begin
        Id := BiId(S);
        If Id <> 0 Then AddTok(tBuiltin, Id, S, 0.0)
        Else If (I < SrcN) And (Src[I] = '(') Then AddTok(tFunc, 0, S, 0.0)
        Else AddTok(tName, 0, S, 0.0);
      End;
      Continue;
    End;
    { operateurs }
    Pr := C;
    K := Peek(1);
    If (C = 43) And (K = 43) Then Pr := oInc
    Else If (C = 45) And (K = 45) Then Pr := oDec
    Else If (C = 43) And (K = 61) Then Pr := oAddA
    Else If (C = 45) And (K = 61) Then Pr := oSubA
    Else If (C = 42) And (K = 61) Then Pr := oMulA
    Else If (C = 47) And (K = 61) Then Pr := oDivA
    Else If (C = 37) And (K = 61) Then Pr := oModA
    Else If (C = 94) And (K = 61) Then Pr := oPowA
    Else If (C = 61) And (K = 61) Then Pr := oEq
    Else If (C = 60) And (K = 61) Then Pr := oLe
    Else If (C = 62) And (K = 61) Then Pr := oGe
    Else If (C = 33) And (K = 61) Then Pr := oNe
    Else If (C = 33) And (K = 126) Then Pr := oNmatch
    Else If (C = 38) And (K = 38) Then Pr := oAnd
    Else If (C = 124) And (K = 124) Then Pr := oOr
    Else If (C = 62) And (K = 62) Then Pr := oApp
    Else If (C = 42) And (K = 42) Then
    Begin
      If Peek(2) = 61 Then
      Begin
        Pr := oPowA;
        Inc(I);
      End
      Else Pr := 94;
    End;
    If Pr <> C Then Inc(I);
    Inc(I);
    AddTok(tOp, Pr, '', 0.0);
  End;
  AddTok(tNL, 0, '', 0.0);
  AddTok(tEOF, 0, '', 0.0);
End;

{ ---------- noeuds ---------- }

Function NewNode(Op : LongInt) : LongInt;
Begin
  If NNode >= MaxNode Then Die('programme trop long');
  Inc(NNode);
  Nodes[NNode].Op := Op;
  Nodes[NNode].A := 0;
  Nodes[NNode].B := 0;
  Nodes[NNode].C := 0;
  Nodes[NNode].D := 0;
  Nodes[NNode].X := 0.0;
  Nodes[NNode].S := '';
  NewNode := NNode;
End;

Function Mk(Op, A, B, C : LongInt) : LongInt;
Var N : LongInt;
Begin
  N := NewNode(Op);
  Nodes[N].A := A;
  Nodes[N].B := B;
  Nodes[N].C := C;
  Mk := N;
End;

{ ---------- analyse syntaxique ---------- }

Function TT : LongInt;
Begin
  TT := TokT[TP];
End;

Function IsOp(V : LongInt) : Boolean;
Begin
  IsOp := (TokT[TP] = tOp) And (TokV[TP] = V);
End;

Function IsKw(V : LongInt) : Boolean;
Begin
  IsKw := (TokT[TP] = tKw) And (TokV[TP] = V);
End;

Procedure Adv;
Begin
  If TP < NTok - 1 Then Inc(TP);
End;

Procedure SkipNL;
Begin
  While TokT[TP] = tNL Do Adv;
End;

Procedure SkipTerm;
Begin
  While (TokT[TP] = tNL) Or IsOp(59) Do Adv;
End;

Procedure Need(V : LongInt);
Begin
  If Not IsOp(V) Then SynErr('attendu ' + Chr(V));
  Adv;
End;

Function GlobalIdx(Const Nm : String) : LongInt;
Var K : LongInt;
Begin
  For K := 0 To NGlob - 1 Do
    If GNames[K] = Nm Then
    Begin
      GlobalIdx := K;
      Exit;
    End;
  If NGlob >= 256 Then Die('trop de variables');
  GNames[NGlob] := Nm;
  GlobalIdx := NGlob;
  Inc(NGlob);
End;

Function FnIdx(Const Nm : String) : LongInt;
Var K : LongInt;
Begin
  For K := 1 To NFn Do
    If FnName[K] = Nm Then
    Begin
      FnIdx := K;
      Exit;
    End;
  If NFn >= MaxFn Then Die('trop de fonctions');
  Inc(NFn);
  FnName[NFn] := Nm;
  FnBody[NFn] := 0;
  FnNPar[NFn] := 0;
  FnDefined[NFn] := 0;
  FnIdx := NFn;
End;

Function ParseExpr : LongInt; Forward;
Function ParseStmt : LongInt; Forward;

Function VarNode(Const Nm : String) : LongInt;
Var K, N : LongInt;
Begin
  N := NewNode(nVar);
  For K := 1 To NParams Do
    If Params[K] = Nm Then
    Begin
      Nodes[N].A := K - 1;
      Nodes[N].B := 1;
      VarNode := N;
      Exit;
    End;
  Nodes[N].A := GlobalIdx(Nm);
  Nodes[N].B := 0;
  VarNode := N;
End;

Function StartsOperand : Boolean;
Var T, V : LongInt;
Begin
  T := TokT[TP];
  V := TokV[TP];
  StartsOperand := (T = tNum) Or (T = tStr) Or (T = tName) Or (T = tFunc) Or
    (T = tBuiltin) Or (T = tEre) Or
    ((T = tOp) And ((V = 36) Or (V = 40) Or (V = 33) Or (V = 45) Or
    (V = 43) Or (V = oInc) Or (V = oDec)));
End;

Function StartsCat : Boolean;
Var T, V : LongInt;
Begin
  T := TokT[TP];
  V := TokV[TP];
  StartsCat := (T = tNum) Or (T = tStr) Or (T = tName) Or (T = tFunc) Or
    (T = tBuiltin) Or
    ((T = tOp) And ((V = 36) Or (V = 40) Or (V = 33) Or (V = oInc) Or
    (V = oDec) Or (V = 45) Or (V = 43)));
End;

Function IsLv(N : LongInt) : Boolean;
Begin
  IsLv := (Nodes[N].Op = nVar) Or (Nodes[N].Op = nIdx) Or
          (Nodes[N].Op = nFld);
End;

{ liste d'expressions separees par des virgules (tete de liste via D) }
Function ParseList(Close : LongInt) : LongInt;
Var H, L, E : LongInt;
Begin
  H := 0;
  L := 0;
  SkipNL;
  If IsOp(Close) Then
  Begin
    ParseList := 0;
    Exit;
  End;
  While True Do
  Begin
    SkipNL;
    E := ParseExpr;
    If H = 0 Then H := E Else Nodes[L].D := E;
    L := E;
    SkipNL;
    If IsOp(44) Then
    Begin
      Adv;
      Continue;
    End;
    Break;
  End;
  ParseList := H;
End;

Function ParsePrimary : LongInt;
Var N, E, H, K, Bi : LongInt; Nm : String; SvGt, SvIn : Boolean;
Begin
  If TokT[TP] = tNum Then
  Begin
    N := NewNode(nNum);
    Nodes[N].X := TokX[TP];
    Adv;
    ParsePrimary := N;
    Exit;
  End;
  If TokT[TP] = tStr Then
  Begin
    N := NewNode(nStr);
    Nodes[N].S := TokStr(TP);
    Adv;
    ParsePrimary := N;
    Exit;
  End;
  If TokT[TP] = tEre Then
  Begin
    N := NewNode(nRe);
    Nodes[N].S := TokStr(TP);
    Nodes[N].A := -1;
    Adv;
    ParsePrimary := N;
    Exit;
  End;
  If IsOp(36) Then
  Begin
    Adv;
    If IsOp(oInc) Or IsOp(oDec) Then
    Begin
      K := 1;
      If IsOp(oDec) Then K := -1;
      Adv;
      E := ParsePrimary;
      E := Mk(nPre, E, 0, K);
      ParsePrimary := Mk(nFld, E, 0, 0);
      Exit;
    End;
    If IsOp(45) Then
    Begin
      Adv;
      E := Mk(nNeg, ParsePrimary, 0, 0);
      ParsePrimary := Mk(nFld, E, 0, 0);
      Exit;
    End;
    E := ParsePrimary;
    ParsePrimary := Mk(nFld, E, 0, 0);
    Exit;
  End;
  If IsOp(oInc) Or IsOp(oDec) Then
  Begin
    K := 1;
    If IsOp(oDec) Then K := -1;
    Adv;
    E := ParsePrimary;
    If Not IsLv(E) Then SynErr('++ attend une variable');
    ParsePrimary := Mk(nPre, E, 0, K);
    Exit;
  End;
  If IsOp(33) Then
  Begin
    Adv;
    ParsePrimary := Mk(nNot, ParsePrimary, 0, 0);
    Exit;
  End;
  If IsOp(45) Then
  Begin
    Adv;
    ParsePrimary := Mk(nNeg, ParsePrimary, 0, 0);
    Exit;
  End;
  If IsOp(43) Then
  Begin
    Adv;
    ParsePrimary := Mk(nPlus, ParsePrimary, 0, 0);
    Exit;
  End;
  If IsOp(40) Then
  Begin
    Adv;
    SvGt := NoGt;
    SvIn := NoIn;
    NoGt := False;
    NoIn := False;
    H := ParseList(41);
    NoGt := SvGt;
    NoIn := SvIn;
    SkipNL;
    Need(41);
    If (H <> 0) And (Nodes[H].D <> 0) Then
    Begin
      { (i, j) in tableau }
      If Not IsKw(kIn) Then SynErr('attendu in');
      Adv;
      Nm := TokStr(TP);
      N := VarNode(Nm);
      Adv;
      ParsePrimary := Mk(nIn, H, N, 1);
      Exit;
    End;
    ParsePrimary := Mk(nGroup, H, 0, 0);
    Exit;
  End;
  If TokT[TP] = tName Then
  Begin
    Nm := TokStr(TP);
    Adv;
    N := VarNode(Nm);
    If IsOp(91) Then
    Begin
      Adv;
      SvGt := NoGt;
      SvIn := NoIn;
      NoGt := False;
      NoIn := False;
      H := ParseList(93);
      NoGt := SvGt;
      NoIn := SvIn;
      Need(93);
      N := Mk(nIdx, N, H, 0);
    End;
    ParsePrimary := N;
    Exit;
  End;
  If TokT[TP] = tFunc Then
  Begin
    Nm := TokStr(TP);
    Adv;
    Need(40);
    SvGt := NoGt;
    SvIn := NoIn;
    NoGt := False;
    NoIn := False;
    H := ParseList(41);
    NoGt := SvGt;
    NoIn := SvIn;
    SkipNL;
    Need(41);
    ParsePrimary := Mk(nCall, FnIdx(Nm), H, 0);
    Exit;
  End;
  If TokT[TP] = tBuiltin Then
  Begin
    Bi := TokV[TP];
    Adv;
    H := 0;
    If IsOp(40) Then
    Begin
      Adv;
      SvGt := NoGt;
      SvIn := NoIn;
      NoGt := False;
      NoIn := False;
      H := ParseList(41);
      NoGt := SvGt;
      NoIn := SvIn;
      SkipNL;
      Need(41);
    End
    Else If Bi <> bLength Then SynErr('attendu (');
    ParsePrimary := Mk(nBi, Bi, H, 0);
    Exit;
  End;
  If IsKw(kGetline) Then
  Begin
    Adv;
    N := 0;
    If (TokT[TP] = tName) Or IsOp(36) Then N := ParsePrimary;
    E := 0;
    K := 0;
    If IsOp(60) Then
    Begin
      Adv;
      E := ParsePrimary;
      K := 1;
    End;
    ParsePrimary := Mk(nGetl, K, N, E);
    Exit;
  End;
  SynErr('expression attendue');
  ParsePrimary := 0;
End;

Function ParsePostfix : LongInt;
Var E : LongInt;
Begin
  E := ParsePrimary;
  If IsLv(E) Then
  Begin
    If IsOp(oInc) Then
    Begin
      Adv;
      E := Mk(nPost, E, 0, 1);
    End
    Else If IsOp(oDec) Then
    Begin
      Adv;
      E := Mk(nPost, E, 0, -1);
    End;
  End;
  ParsePostfix := E;
End;

Function ParseUnaryPow : LongInt; Forward;

Function ParsePow : LongInt;
Var E, R : LongInt;
Begin
  E := ParsePostfix;
  If IsOp(94) Then
  Begin
    Adv;
    R := ParseUnaryPow;
    E := Mk(nBin, E, R, 94);
  End;
  ParsePow := E;
End;

Function ParseUnaryPow : LongInt;
Begin
  If IsOp(45) Then
  Begin
    Adv;
    ParseUnaryPow := Mk(nNeg, ParseUnaryPow, 0, 0);
  End
  Else If IsOp(43) Then
  Begin
    Adv;
    ParseUnaryPow := ParseUnaryPow;
  End
  Else If IsOp(33) Then
  Begin
    Adv;
    ParseUnaryPow := Mk(nNot, ParseUnaryPow, 0, 0);
  End
  Else ParseUnaryPow := ParsePow;
End;

Function ParseUnary : LongInt;
Begin
  If IsOp(33) Then
  Begin
    Adv;
    ParseUnary := Mk(nNot, ParseUnary, 0, 0);
  End
  Else If IsOp(45) Then
  Begin
    Adv;
    ParseUnary := Mk(nNeg, ParseUnary, 0, 0);
  End
  Else If IsOp(43) Then
  Begin
    Adv;
    ParseUnary := Mk(nPlus, ParseUnary, 0, 0);
  End
  Else ParseUnary := ParsePow;
End;

Function ParseMul : LongInt;
Var E, R, Op : LongInt;
Begin
  E := ParseUnary;
  While IsOp(42) Or IsOp(47) Or IsOp(37) Do
  Begin
    Op := TokV[TP];
    Adv;
    R := ParseUnary;
    E := Mk(nBin, E, R, Op);
  End;
  ParseMul := E;
End;

Function ParseAdd : LongInt;
Var E, R, Op : LongInt;
Begin
  E := ParseMul;
  While IsOp(43) Or IsOp(45) Do
  Begin
    Op := TokV[TP];
    Adv;
    R := ParseMul;
    E := Mk(nBin, E, R, Op);
  End;
  ParseAdd := E;
End;

Function ParseConcat : LongInt;
Var E, R : LongInt;
Begin
  E := ParseAdd;
  While StartsCat And (Not (IsOp(45) Or IsOp(43))) And
        Not (IsKw(kIn)) Do
  Begin
    R := ParseAdd;
    E := Mk(nCat, E, R, 0);
  End;
  ParseConcat := E;
End;

Function ParseConcatPipe : LongInt;
Var E, N, K, V : LongInt;
Begin
  E := ParseConcat;
  While IsOp(124) And (TokT[TP + 1] = tKw) And
        (TokV[TP + 1] = kGetline) Do
  Begin
    Adv;
    Adv;
    V := 0;
    If (TokT[TP] = tName) Or IsOp(36) Then V := ParsePrimary;
    E := Mk(nGetl, 2, V, E);
  End;
  ParseConcatPipe := E;
End;

Function ParseCmp : LongInt;
Var E, R, Op : LongInt; Cmp : Boolean;
Begin
  E := ParseConcatPipe;
  Cmp := IsOp(60) Or IsOp(oLe) Or IsOp(oEq) Or IsOp(oNe) Or IsOp(oGe) Or
         (IsOp(62) And Not NoGt);
  While Cmp Do
  Begin
    Op := TokV[TP];
    Adv;
    R := ParseConcatPipe;
    E := Mk(nCmp, E, R, Op);
    Cmp := IsOp(60) Or IsOp(oLe) Or IsOp(oEq) Or IsOp(oNe) Or IsOp(oGe) Or
           (IsOp(62) And Not NoGt);
  End;
  ParseCmp := E;
End;

Function ParseMatch : LongInt;
Var E, R : LongInt;
Begin
  E := ParseCmp;
  While IsOp(126) Or IsOp(oNmatch) Do
  Begin
    If IsOp(126) Then
    Begin
      Adv;
      R := ParseCmp;
      E := Mk(nMatch, E, R, 0);
    End
    Else
    Begin
      Adv;
      R := ParseCmp;
      E := Mk(nNmatch, E, R, 0);
    End;
  End;
  ParseMatch := E;
End;

Function ParseIn : LongInt;
Var E, N : LongInt; Nm : String;
Begin
  E := ParseMatch;
  While IsKw(kIn) And (Not NoIn) Do
  Begin
    Adv;
    Nm := TokStr(TP);
    Adv;
    N := VarNode(Nm);
    E := Mk(nIn, E, N, 0);
  End;
  ParseIn := E;
End;

Function ParseAnd : LongInt;
Var E, R : LongInt;
Begin
  E := ParseIn;
  While IsOp(oAnd) Do
  Begin
    Adv;
    SkipNL;
    R := ParseIn;
    E := Mk(nAnd, E, R, 0);
  End;
  ParseAnd := E;
End;

Function ParseOr : LongInt;
Var E, R : LongInt;
Begin
  E := ParseAnd;
  While IsOp(oOr) Do
  Begin
    Adv;
    SkipNL;
    R := ParseAnd;
    E := Mk(nOr, E, R, 0);
  End;
  ParseOr := E;
End;

Function ParseTernary : LongInt;
Var C, A, B : LongInt;
Begin
  C := ParseOr;
  If IsOp(63) Then
  Begin
    Adv;
    SkipNL;
    A := ParseExpr;
    SkipNL;
    Need(58);
    SkipNL;
    B := ParseExpr;
    C := Mk(nCond, C, A, B);
  End;
  ParseTernary := C;
End;

Function AsgOp : LongInt;
Begin
  AsgOp := -1;
  If TokT[TP] <> tOp Then Exit;
  Case TokV[TP] Of
    61 : AsgOp := 0;
    oAddA : AsgOp := 43;
    oSubA : AsgOp := 45;
    oMulA : AsgOp := 42;
    oDivA : AsgOp := 47;
    oModA : AsgOp := 37;
    oPowA : AsgOp := 94;
  End;
End;

Function ParseExpr : LongInt;
Var E, R, Op : LongInt;
Begin
  E := ParseTernary;
  If IsLv(E) Then
  Begin
    Op := AsgOp;
    If Op >= 0 Then
    Begin
      Adv;
      SkipNL;
      R := ParseExpr;
      E := Mk(nAsg, E, R, Op);
    End;
  End;
  ParseExpr := E;
End;

{ ---------- instructions ---------- }

Function ParseBlock : LongInt;
Var H, L, S : LongInt;
Begin
  Need(123);
  H := 0;
  L := 0;
  SkipTerm;
  While Not IsOp(125) Do
  Begin
    If TokT[TP] = tEOF Then SynErr('} manquant');
    S := ParseStmt;
    If S <> 0 Then
    Begin
      If H = 0 Then H := S Else Nodes[L].D := S;
      L := S;
    End;
    SkipTerm;
  End;
  Adv;
  ParseBlock := Mk(sBlock, H, 0, 0);
End;

Procedure EndSimple;
Begin
  If IsOp(59) Or (TokT[TP] = tNL) Then
  Begin
    SkipTerm;
    Exit;
  End;
  If IsOp(125) Or (TokT[TP] = tEOF) Then Exit;
  SynErr('fin d''instruction attendue');
End;

Function ParseSimple : LongInt;
Var N, H, E, Kind, K, A, B : LongInt; Nm : String; Save : LongInt;
    IsP : Boolean;
Begin
  If IsKw(kPrint) Or IsKw(kPrintf) Then
  Begin
    IsP := IsKw(kPrint);
    Adv;
    Save := TP;
    H := 0;
    NoGt := True;
    If IsOp(40) Then
    Begin
      Adv;
      NoGt := False;
      H := ParseList(41);
      NoGt := True;
      SkipNL;
      If IsOp(41) Then
      Begin
        Adv;
        If Not (IsOp(59) Or IsOp(125) Or (TokT[TP] = tNL) Or
                (TokT[TP] = tEOF) Or IsOp(62) Or IsOp(oApp) Or
                IsOp(124)) Then
        Begin
          TP := Save;
          H := 0;
        End;
      End
      Else
      Begin
        TP := Save;
        H := 0;
      End;
    End;
    If (H = 0) And (TP = Save) Then
    Begin
      If Not (IsOp(59) Or IsOp(125) Or (TokT[TP] = tNL) Or
              (TokT[TP] = tEOF) Or IsOp(62) Or IsOp(oApp) Or
              IsOp(124)) Then H := ParseList(0);
    End;
    NoGt := False;
    Kind := 0;
    E := 0;
    If IsOp(62) Then Kind := 1
    Else If IsOp(oApp) Then Kind := 2
    Else If IsOp(124) Then Kind := 3;
    If Kind <> 0 Then
    Begin
      Adv;
      NoGt := True;
      E := ParseConcat;
      NoGt := False;
    End;
    If IsP Then N := Mk(sPrint, H, Kind, E)
    Else N := Mk(sPrintf, H, Kind, E);
    EndSimple;
    ParseSimple := N;
    Exit;
  End;
  If IsKw(kDelete) Then
  Begin
    Adv;
    Nm := TokStr(TP);
    Adv;
    A := VarNode(Nm);
    If IsOp(91) Then
    Begin
      Adv;
      H := ParseList(93);
      Need(93);
      N := Mk(sDel, Mk(nIdx, A, H, 0), 0, 0);
    End
    Else N := Mk(sDelAll, A, 0, 0);
    EndSimple;
    ParseSimple := N;
    Exit;
  End;
  If IsKw(kNext) Then
  Begin
    Adv;
    EndSimple;
    ParseSimple := Mk(sNext, 0, 0, 0);
    Exit;
  End;
  If IsKw(kNextFile) Then
  Begin
    Adv;
    EndSimple;
    ParseSimple := Mk(sNextF, 0, 0, 0);
    Exit;
  End;
  If IsKw(kBreak) Then
  Begin
    Adv;
    EndSimple;
    ParseSimple := Mk(sBreak, 0, 0, 0);
    Exit;
  End;
  If IsKw(kContinue) Then
  Begin
    Adv;
    EndSimple;
    ParseSimple := Mk(sCont, 0, 0, 0);
    Exit;
  End;
  If IsKw(kExit) Or IsKw(kReturn) Then
  Begin
    K := TokV[TP];
    Adv;
    E := 0;
    If Not (IsOp(59) Or IsOp(125) Or (TokT[TP] = tNL) Or
            (TokT[TP] = tEOF)) Then E := ParseExpr;
    EndSimple;
    If K = kExit Then ParseSimple := Mk(sExit, E, 0, 0)
    Else ParseSimple := Mk(sRet, E, 0, 0);
    Exit;
  End;
  E := ParseExpr;
  EndSimple;
  ParseSimple := Mk(sExpr, E, 0, 0);
End;

Function ParseStmt : LongInt;
Var N, C, T, E, Ini, Inc1, Body, V, Ar : LongInt; Nm : String; Save : LongInt;
Begin
  If IsOp(123) Then
  Begin
    ParseStmt := ParseBlock;
    Exit;
  End;
  If IsOp(59) Then
  Begin
    Adv;
    ParseStmt := 0;
    Exit;
  End;
  If IsKw(kIf) Then
  Begin
    Adv;
    Need(40);
    C := ParseExpr;
    SkipNL;
    Need(41);
    SkipNL;
    T := ParseStmt;
    E := 0;
    Save := TP;
    SkipTerm;
    If IsKw(kElse) Then
    Begin
      Adv;
      SkipNL;
      E := ParseStmt;
    End
    Else TP := Save;
    ParseStmt := Mk(sIf, C, T, E);
    Exit;
  End;
  If IsKw(kWhile) Then
  Begin
    Adv;
    Need(40);
    C := ParseExpr;
    SkipNL;
    Need(41);
    If IsOp(59) Then
    Begin
      Adv;
      Body := 0;
    End
    Else
    Begin
      SkipNL;
      Body := ParseStmt;
    End;
    N := Mk(sWhile, C, 0, 0);
    Nodes[N].B := Body;
    ParseStmt := N;
    Exit;
  End;
  If IsKw(kDo) Then
  Begin
    Adv;
    SkipNL;
    Body := ParseStmt;
    SkipTerm;
    If Not IsKw(kWhile) Then SynErr('attendu while');
    Adv;
    Need(40);
    C := ParseExpr;
    SkipNL;
    Need(41);
    EndSimple;
    ParseStmt := Mk(sDo, Body, C, 0);
    Exit;
  End;
  If IsKw(kFor) Then
  Begin
    Adv;
    Need(40);
    { for (k in tableau) ? }
    If (TokT[TP] = tName) And (TokT[TP + 1] = tKw) And
       (TokV[TP + 1] = kIn) And (TokT[TP + 2] = tName) And
       (TokT[TP + 3] = tOp) And (TokV[TP + 3] = 41) Then
    Begin
      V := VarNode(TokStr(TP));
      Adv;
      Adv;
      Ar := VarNode(TokStr(TP));
      Adv;
      Adv;
      SkipNL;
      Body := ParseStmt;
      N := Mk(sForIn, V, Ar, 0);
      Nodes[N].C := Body;
      ParseStmt := N;
      Exit;
    End;
    Ini := 0;
    C := 0;
    Inc1 := 0;
    If Not IsOp(59) Then Ini := Mk(sExpr, ParseExpr, 0, 0);
    Need(59);
    SkipNL;
    If Not IsOp(59) Then C := ParseExpr;
    Need(59);
    SkipNL;
    If Not IsOp(41) Then Inc1 := Mk(sExpr, ParseExpr, 0, 0);
    Need(41);
    If IsOp(59) Then
    Begin
      Adv;
      Body := 0;
    End
    Else
    Begin
      SkipNL;
      Body := ParseStmt;
    End;
    N := Mk(sFor, Ini, C, Inc1);
    Nodes[N].X := Body;
    ParseStmt := N;
    Exit;
  End;
  ParseStmt := ParseSimple;
End;

{ ---------- programme ---------- }

Procedure ParseProgram;
Var N, E, P1, P2, Act, K, I : LongInt; Nm : String;
Begin
  TP := 0;
  SkipTerm;
  While TokT[TP] <> tEOF Do
  Begin
    If IsKw(kFunction) Then
    Begin
      Adv;
      Nm := TokStr(TP);
      Adv;
      K := FnIdx(Nm);
      Need(40);
      NParams := 0;
      While Not IsOp(41) Do
      Begin
        SkipNL;
        If TokT[TP] <> tName Then SynErr('parametre attendu');
        Inc(NParams);
        Params[NParams] := TokStr(TP);
        Adv;
        SkipNL;
        If IsOp(44) Then Adv;
      End;
      Adv;
      SkipNL;
      FnNPar[K] := NParams;
      FnDefined[K] := 1;
      CurFn := K;
      FnBody[K] := ParseBlock;
      CurFn := 0;
      NParams := 0;
      SkipTerm;
      Continue;
    End;
    If NRule >= 400 Then Die('trop de regles');
    Inc(NRule);
    RuleK[NRule] := 2;
    RuleP1[NRule] := 0;
    RuleP2[NRule] := 0;
    RuleAct[NRule] := 0;
    RuleOn[NRule] := False;
    If IsKw(kBEGIN) Then
    Begin
      Adv;
      RuleK[NRule] := 0;
      SkipNL;
    End
    Else If IsKw(kEND) Then
    Begin
      Adv;
      RuleK[NRule] := 1;
      SkipNL;
    End
    Else If Not IsOp(123) Then
    Begin
      RuleP1[NRule] := ParseExpr;
      If IsOp(44) Then
      Begin
        Adv;
        SkipNL;
        RuleP2[NRule] := ParseExpr;
        RuleK[NRule] := 3;
      End;
    End;
    If IsOp(123) Then RuleAct[NRule] := ParseBlock;
    SkipTerm;
  End;
  For K := 1 To NFn Do
    If FnDefined[K] = 0 Then Die('fonction non definie : ' + FnName[K]);
End;

{ ---------- valeurs ---------- }

Var
  FSStr, OFSStr, ORSStr, RSStr, SubSep, ConvFmt, OFmt : String;
  NRv, FNRv, NFv : LongInt;
  Flow, ExitCode, FrameBase : LongInt;
  InEnd, InBegin : Boolean;
  Rec : Array[0..RecMax] Of Char;
  RecLen : LongInt;
  Fld : Array[0..MaxFld] Of TVal;
  FldOwn : Array[0..MaxFld] Of Boolean;
  FldValid, RecValid, AllOwn : Boolean;
  RetVal : TVal;
  Seed, PrevSeed : LongInt;
  RStart, RLength : LongInt;
  ReCacheS : Array[1..64] Of String;
  ReCacheP : Array[1..64] Of LongInt;
  ReCacheN, DynBase, DynSetBase : LongInt;
  Depth : LongInt;

Const
  fNum = 1; fStr = 2; fSN = 4;

Function ToStrC(Const V : TVal; Var P, L : LongInt; Const Fmt : String)
         : Boolean;
Var S : String; K : LongInt;
Begin
  If (V.F And fStr) <> 0 Then
  Begin
    P := V.P;
    L := V.L;
    ToStrC := True;
    Exit;
  End;
  S := NumToStr(V.N, Fmt);
  P := ANew(Length(S));
  For K := 1 To Length(S) Do Mem[0:P + K - 1] := Ord(S[K]);
  Mem[0:P + Length(S)] := 0;
  L := Length(S);
  ToStrC := True;
End;

Procedure ToStr(Const V : TVal; Var P, L : LongInt);
Begin
  ToStrC(V, P, L, ConvFmt);
End;

Function ToNum(Const V : TVal) : Double;
Begin
  If (V.F And fNum) <> 0 Then ToNum := V.N
  Else If (V.F And fStr) <> 0 Then ToNum := StrNum(V.P, V.L)
  Else ToNum := 0.0;
End;

Function IsNumeric(Const V : TVal) : Boolean;
Begin
  IsNumeric := False;
  If (V.F And fNum) <> 0 Then IsNumeric := True
  Else If ((V.F And fSN) <> 0) And (V.P <> 0) Then
    IsNumeric := LooksNum(V.P, V.L)
  Else If (V.F And fStr) = 0 Then IsNumeric := True;
End;

Function Truth(Const V : TVal) : Boolean;
Begin
  If (V.F And fSN) <> 0 Then
  Begin
    If LooksNum(V.P, V.L) Then Truth := StrNum(V.P, V.L) <> 0.0
    Else Truth := V.L > 0;
  End
  Else If (V.F And fNum) <> 0 Then Truth := V.N <> 0.0
  Else If (V.F And fStr) <> 0 Then Truth := V.L > 0
  Else Truth := False;
End;

{ valeur "chaine d'entree" : comparable comme nombre si elle en a l'air }
Procedure SetInput(Var V : TVal; P, L : LongInt);
Begin
  V.F := fStr Or fSN;
  V.P := P;
  V.L := L;
  V.N := 0.0;
End;

Procedure StoreVal(Var D : TVal; Const S : TVal);
Var NP : LongInt;
Begin
  If ((D.F And fStr) <> 0) And (D.P <> 0) Then PFree(D.P);
  D.F := S.F;
  D.N := S.N;
  D.P := 0;
  D.L := 0;
  D.C := 0;
  If (S.F And fStr) <> 0 Then
  Begin
    D.P := PDup(S.P, S.L);
    D.L := S.L;
  End;
End;

Procedure ClearVal(Var D : TVal);
Begin
  If ((D.F And fStr) <> 0) And (D.P <> 0) Then PFree(D.P);
  D.F := 0;
  D.N := 0.0;
  D.P := 0;
  D.L := 0;
End;

Procedure SetUninit(Var V : TVal);
Begin
  V.F := fNum Or fStr;
  V.N := 0.0;
  V.P := 0;
  V.L := 0;
End;

Procedure SetBool(Var V : TVal; B : Boolean);
Begin
  V.F := fNum;
  If B Then V.N := 1.0 Else V.N := 0.0;
  V.P := 0;
  V.L := 0;
End;

{ ---------- tableaux ---------- }

Function ArrAlloc : LongInt;
Var K, I : LongInt;
Begin
  K := 1;
  While (K <= NArr) And Arrs[K].Used Do Inc(K);
  If K > NArr Then
  Begin
    If NArr >= 255 Then Die('trop de tableaux');
    Inc(NArr);
    K := NArr;
  End;
  Arrs[K].Used := True;
  Arrs[K].Cnt := 0;
  Arrs[K].First := 0;
  Arrs[K].Last := 0;
  Arrs[K].NB := 64;
  Arrs[K].Buckets := PNew(64 * 4);
  For I := 0 To 63 Do MemL[0:Arrs[K].Buckets + I * 4] := 0;
  ArrAlloc := K;
End;

Function HashKey(P, L : LongInt) : LongInt;
Var H, K : LongInt;
Begin
  H := 5381;
  For K := 0 To L - 1 Do H := (H * 33 + Mem[0:P + K]) And $7FFFFFFF;
  HashKey := H;
End;

Function KeyEq(E : LongInt; P, L : LongInt) : Boolean;
Var K : LongInt;
Begin
  KeyEq := False;
  If EKeyL[E] <> L Then Exit;
  For K := 0 To L - 1 Do
    If Mem[0:EKeyP[E] + K] <> Mem[0:P + K] Then Exit;
  KeyEq := True;
End;

Function ArrFind(A, P, L : LongInt) : LongInt;
Var E : LongInt;
Begin
  ArrFind := 0;
  If (A < 1) Or (Not Arrs[A].Used) Then Exit;
  E := MemL[0:Arrs[A].Buckets + (HashKey(P, L) Mod Arrs[A].NB) * 4];
  While E <> 0 Do
  Begin
    If KeyEq(E, P, L) Then
    Begin
      ArrFind := E;
      Exit;
    End;
    E := EChain[E];
  End;
End;

Procedure ArrRehash(A : LongInt);
Var NB, I, E, Nx, H : LongInt; NBk : LongInt;
Begin
  NB := Arrs[A].NB * 4;
  NBk := PNew(NB * 4);
  For I := 0 To NB - 1 Do MemL[0:NBk + I * 4] := 0;
  E := Arrs[A].First;
  While E <> 0 Do
  Begin
    H := HashKey(EKeyP[E], EKeyL[E]) Mod NB;
    EChain[E] := MemL[0:NBk + H * 4];
    MemL[0:NBk + H * 4] := E;
    E := ENext[E];
  End;
  PFree(Arrs[A].Buckets);
  Arrs[A].Buckets := NBk;
  Arrs[A].NB := NB;
End;

Function ArrGet(A, P, L : LongInt) : LongInt;
Var E, H, Pt : LongInt;
Begin
  E := ArrFind(A, P, L);
  If E <> 0 Then
  Begin
    ArrGet := E;
    Exit;
  End;
  If Arrs[A].Cnt > Arrs[A].NB * 2 Then ArrRehash(A);
  If EFree <> 0 Then
  Begin
    E := EFree;
    EFree := EChain[E];
  End
  Else
  Begin
    If ENew >= MaxEnt Then Die('trop d''elements de tableau');
    Inc(ENew);
    E := ENew;
  End;
  EKeyP[E] := PDup(P, L);
  EKeyL[E] := L;
  SetUninit(EVal[E]);
  H := HashKey(P, L) Mod Arrs[A].NB;
  EChain[E] := MemL[0:Arrs[A].Buckets + H * 4];
  MemL[0:Arrs[A].Buckets + H * 4] := E;
  ENext[E] := 0;
  EPrev[E] := Arrs[A].Last;
  If Arrs[A].Last <> 0 Then ENext[Arrs[A].Last] := E
  Else Arrs[A].First := E;
  Arrs[A].Last := E;
  Inc(Arrs[A].Cnt);
  ArrGet := E;
End;

Procedure ArrFreeEnt(E : LongInt);
Begin
  PFree(EKeyP[E]);
  ClearVal(EVal[E]);
  EChain[E] := EFree;
  EFree := E;
End;

Procedure ArrDel(A, P, L : LongInt);
Var E, H, C, Pv : LongInt;
Begin
  E := ArrFind(A, P, L);
  If E = 0 Then Exit;
  H := HashKey(P, L) Mod Arrs[A].NB;
  C := MemL[0:Arrs[A].Buckets + H * 4];
  Pv := 0;
  While C <> E Do
  Begin
    Pv := C;
    C := EChain[C];
  End;
  If Pv = 0 Then MemL[0:Arrs[A].Buckets + H * 4] := EChain[E]
  Else EChain[Pv] := EChain[E];
  If EPrev[E] <> 0 Then ENext[EPrev[E]] := ENext[E]
  Else Arrs[A].First := ENext[E];
  If ENext[E] <> 0 Then EPrev[ENext[E]] := EPrev[E]
  Else Arrs[A].Last := EPrev[E];
  Dec(Arrs[A].Cnt);
  ArrFreeEnt(E);
End;

Procedure ArrClear(A : LongInt);
Var E, Nx, I : LongInt;
Begin
  If (A < 1) Or (Not Arrs[A].Used) Then Exit;
  E := Arrs[A].First;
  While E <> 0 Do
  Begin
    Nx := ENext[E];
    ArrFreeEnt(E);
    E := Nx;
  End;
  Arrs[A].First := 0;
  Arrs[A].Last := 0;
  Arrs[A].Cnt := 0;
  For I := 0 To Arrs[A].NB - 1 Do MemL[0:Arrs[A].Buckets + I * 4] := 0;
End;

Procedure ArrFree(A : LongInt);
Begin
  ArrClear(A);
  PFree(Arrs[A].Buckets);
  Arrs[A].Buckets := 0;
  Arrs[A].Used := False;
End;

{ ---------- cellules ---------- }

Function CellIdx(N : LongInt) : LongInt;
Var I : LongInt;
Begin
  If Nodes[N].B = 1 Then I := FrameBase + Nodes[N].A Else I := Nodes[N].A;
  While Cells[I].Kind = 3 Do I := Cells[I].Ref;
  CellIdx := I;
End;

Function CellArr(I : LongInt) : LongInt;
Begin
  If Cells[I].Kind = 0 Then
  Begin
    Cells[I].Kind := 2;
    Cells[I].Arr := ArrAlloc;
  End
  Else If Cells[I].Kind <> 2 Then
    Die('scalaire utilise comme tableau : ' + GNames[I Mod 256]);
  CellArr := Cells[I].Arr;
End;

Procedure RefreshSpecial(I : LongInt);
Begin
  If I = vNF Then
  Begin
    SetNum(Cells[I].V, NFv);
  End
  Else If I = vNR Then SetNum(Cells[I].V, NRv)
  Else If I = vFNR Then SetNum(Cells[I].V, FNRv);
End;

{ ---------- champs ---------- }

Procedure FreeFields;
Var K : LongInt;
Begin
  For K := 1 To NFv Do
    If FldOwn[K] Then
    Begin
      PFree(Fld[K].P);
      FldOwn[K] := False;
    End;
  NFv := 0;
End;

Procedure SetRecord(P, L : LongInt);
Begin
  FreeFields;
  If L > RecMax Then L := RecMax;
  If P <> LongInt(@Rec[0]) Then MCopy(LongInt(@Rec[0]), P, L);
  Rec[L] := #0;
  RecLen := L;
  RecValid := True;
  FldValid := False;
  AllOwn := False;
End;

Procedure AddField(P, L : LongInt);
Begin
  If NFv >= MaxFld Then Die('trop de champs');
  Inc(NFv);
  SetInput(Fld[NFv], P, L);
  FldOwn[NFv] := False;
End;

Function ReDyn(P, L : LongInt) : LongInt; Forward;

Var
  SplArr, SplCnt : LongInt;

Procedure SplitEmit(Sp, Sl : LongInt);
Var Ent, Kp, Kl : LongInt; Sx : String;
Begin
  Inc(SplCnt);
  If SplArr = 0 Then AddField(Sp, Sl)
  Else
  Begin
    Sx := NumS(SplCnt);
    Kp := ANew(Length(Sx));
    For Kl := 1 To Length(Sx) Do Mem[0:Kp + Kl - 1] := Ord(Sx[Kl]);
    Ent := ArrGet(SplArr, Kp, Length(Sx));
    ClearVal(EVal[Ent]);
    SetInput(EVal[Ent], Sp, Sl);
    EVal[Ent].P := PDup(Sp, Sl);
  End;
End;

Procedure Split(P, L : LongInt; Const Fs : String; Arr : LongInt);
Var I, S, Pr, C : LongInt;
Begin
  SplArr := Arr;
  SplCnt := 0;
  If L = 0 Then Exit;
  If (Fs = ' ') Then
  Begin
    I := 0;
    While I < L Do
    Begin
      While (I < L) And ((Mem[0:P + I] = 32) Or (Mem[0:P + I] = 9) Or
            (Mem[0:P + I] = 10)) Do Inc(I);
      If I >= L Then Break;
      S := I;
      While (I < L) And (Mem[0:P + I] <> 32) And (Mem[0:P + I] <> 9) And
            (Mem[0:P + I] <> 10) Do Inc(I);
      SplitEmit(P + S, I - S);
    End;
    Exit;
  End;
  If Fs = '' Then
  Begin
    For I := 0 To L - 1 Do SplitEmit(P + I, 1);
    Exit;
  End;
  If (Length(Fs) = 1) And (Fs <> '\') Then
  Begin
    C := Ord(Fs[1]);
    S := 0;
    For I := 0 To L - 1 Do
      If Mem[0:P + I] = C Then
      Begin
        SplitEmit(P + S, I - S);
        S := I + 1;
      End;
    SplitEmit(P + S, L - S);
    Exit;
  End;
  { expression reguliere }
  Pr := ReDyn(LongInt(@Fs[1]), Length(Fs));
  S := 0;
  I := 0;
  While I <= L Do
  Begin
    If Not ReSearch(Pr, P, L, I, True) Then Break;
    If ReCap[1] = ReCap[0] Then
    Begin
      I := ReCap[1] + 1;
      Continue;
    End;
    SplitEmit(P + S, ReCap[0] - S);
    S := ReCap[1];
    I := S;
  End;
  SplitEmit(P + S, L - S);
End;

Procedure SplitRecord;
Begin
  If FldValid Then Exit;
  FldValid := True;
  NFv := 0;
  Split(LongInt(@Rec[0]), RecLen, FSStr, 0);
End;

Procedure MakeOwn;
Var K, P : LongInt;
Begin
  If AllOwn Then Exit;
  For K := 1 To NFv Do
    If Not FldOwn[K] Then
    Begin
      P := PDup(Fld[K].P, Fld[K].L);
      Fld[K].P := P;
      FldOwn[K] := True;
    End;
  AllOwn := True;
End;

Procedure RebuildRecord;
Var K, N, P : LongInt;
Begin
  If RecValid Then Exit;
  N := 0;
  For K := 1 To NFv Do
  Begin
    If K > 1 Then
    Begin
      MCopy(LongInt(@Rec[N]), LongInt(@OFSStr[1]), Length(OFSStr));
      N := N + Length(OFSStr);
    End;
    If N + Fld[K].L > RecMax Then Break;
    MCopy(LongInt(@Rec[N]), Fld[K].P, Fld[K].L);
    N := N + Fld[K].L;
  End;
  Rec[N] := #0;
  RecLen := N;
  RecValid := True;
End;

Procedure GetField(I : LongInt);
Begin
  If I = 0 Then
  Begin
    RebuildRecord;
    SetInput(RV, LongInt(@Rec[0]), RecLen);
    Exit;
  End;
  If I < 0 Then Die('indice de champ negatif : $' + NumS(I));
  SplitRecord;
  If I > NFv Then
  Begin
    RV.F := fStr Or fSN;
    RV.P := 0;
    RV.L := 0;
    RV.N := 0.0;
    Exit;
  End;
  RV := Fld[I];
End;

Procedure SetNF(N : LongInt);
Var K : LongInt;
Begin
  SplitRecord;
  MakeOwn;
  If N > MaxFld Then Die('trop de champs');
  If N < 0 Then N := 0;
  While NFv < N Do
  Begin
    Inc(NFv);
    SetInput(Fld[NFv], PDup(0, 0), 0);
    Fld[NFv].P := PDup(0, 0);
    FldOwn[NFv] := True;
  End;
  While NFv > N Do
  Begin
    PFree(Fld[NFv].P);
    FldOwn[NFv] := False;
    Dec(NFv);
  End;
  RecValid := False;
End;

Procedure SetField(I : LongInt; Const V : TVal);
Var P, L, Pc : LongInt;
Begin
  If I = 0 Then
  Begin
    ToStr(V, P, L);
    SetRecord(P, L);
    Exit;
  End;
  If I < 0 Then Die('indice de champ negatif : $' + NumS(I));
  SplitRecord;
  If I > NFv Then SetNF(I);
  MakeOwn;
  ToStr(V, P, L);
  Pc := PDup(P, L);
  PFree(Fld[I].P);
  SetInput(Fld[I], Pc, L);
  If (V.F And fSN) = 0 Then Fld[I].F := fStr;
  FldOwn[I] := True;
  RecValid := False;
End;

{ ---------- expressions regulieres dynamiques ---------- }

Function ReDyn(P, L : LongInt) : LongInt;
Var S : String; K : LongInt; Pr : LongInt;
Begin
  S := SGet(P, L);
  For K := 1 To ReCacheN Do
    If ReCacheS[K] = S Then
    Begin
      ReDyn := ReCacheP[K];
      Exit;
    End;
  If (ReCacheN >= 64) Or (ReN > ReMaxProg - 4000) Or
     (ReSetN > ReMaxSet - 40) Then
  Begin
    ReN := DynBase;
    ReSetN := DynSetBase;
    ReCacheN := 0;
  End;
  Pr := ReCompile(S, True, False);
  If Pr < 0 Then Die('expression reguliere : ' + ReErr + ' dans /' + S + '/');
  Inc(ReCacheN);
  ReCacheS[ReCacheN] := S;
  ReCacheP[ReCacheN] := Pr;
  ReDyn := Pr;
End;

{ ---------- flux d'entree-sortie ---------- }

Const
  MaxStr = 24;

Var
  SName : Array[0..MaxStr] Of String;
  SKind, SFd, SPid, SBuf, SPos, SLen, SAll, SAllN, SAllP : Array[0..MaxStr]
    Of LongInt;
  SEof : Array[0..MaxStr] Of Boolean;
  RdBuf : Array[0..RecMax] Of Char;
  RdLen : LongInt;
  ArgIdx, ArgC : LongInt;
  MainOpen, MainDone : Boolean;
  Assigns : LongInt;
  FnV : TVal;

Procedure WriteFd(Fd : LongInt; P, L : LongInt);
Var Buf : Array[0..4095] Of Byte; K, N : LongInt;
Begin
  If Fd = 1 Then
  Begin
    OutMem(P, L);
    Exit;
  End;
  While L > 0 Do
  Begin
    N := L;
    If N > 4096 Then N := 4096;
    For K := 0 To N - 1 Do Buf[K] := Mem[0:P + K];
    SysWrite(Fd, Buf[0], N);
    P := P + N;
    L := L - N;
  End;
End;

Procedure StartCmd(Const Cmd : String; Writer : Boolean; Var Fd, Pid : LongInt);
Var Fds : Array[0..1] Of LongInt; R : LongInt;
Begin
  FlushOut;
  If SysPipe(Fds[0]) <> 0 Then
  Begin
    Fd := -1;
    Pid := 0;
    Exit;
  End;
  Pid := SysFork;
  If Pid = 0 Then
  Begin
    If Writer Then
    Begin
      SysDup2(Fds[0], 0);
    End
    Else SysDup2(Fds[1], 1);
    SysClose(Fds[0]);
    SysClose(Fds[1]);
    SysArgReset;
    SysArgAdd('sh');
    SysArgAdd('-c');
    SysArgAdd(Cmd);
    SysArgExec('/bin/sh');
    SysExit(127);
  End;
  If Writer Then
  Begin
    Fd := Fds[1];
    SysClose(Fds[0]);
  End
  Else
  Begin
    Fd := Fds[0];
    SysClose(Fds[1]);
  End;
End;

Function FindStream(Const Nm : String; Kind : LongInt) : LongInt;
Var K : LongInt;
Begin
  FindStream := -1;
  For K := 1 To MaxStr Do
    If (SKind[K] = Kind) And (SName[K] = Nm) Then
    Begin
      FindStream := K;
      Exit;
    End;
End;

Function NewStream(Const Nm : String; Kind, Fd, Pid : LongInt) : LongInt;
Var K : LongInt;
Begin
  For K := 1 To MaxStr Do
    If SKind[K] = 0 Then
    Begin
      SName[K] := Nm;
      SKind[K] := Kind;
      SFd[K] := Fd;
      SPid[K] := Pid;
      SPos[K] := 0;
      SLen[K] := 0;
      SEof[K] := False;
      SAll[K] := 0;
      SBuf[K] := 0;
      NewStream := K;
      Exit;
    End;
  Die('trop de fichiers ouverts');
  NewStream := -1;
End;

{ flux de sortie pour print > / >> / | : renvoie le descripteur }
Function OutFdOf(Kind : LongInt; Const Nm : String) : LongInt;
Var K, Fd, Pid : LongInt;
Begin
  If (Nm = '/dev/stdout') Or (Nm = '-') Then
  Begin
    OutFdOf := 1;
    Exit;
  End;
  If Nm = '/dev/stderr' Then
  Begin
    FlushOut;
    OutFdOf := 2;
    Exit;
  End;
  If Kind = 3 Then K := FindStream(Nm, 2) Else K := FindStream(Nm, 1);
  If K < 0 Then
  Begin
    If Kind = 3 Then
    Begin
      StartCmd(Nm, True, Fd, Pid);
      If Fd < 0 Then Die('impossible de creer un tube');
      K := NewStream(Nm, 2, Fd, Pid);
    End
    Else
    Begin
      If Kind = 1 Then Fd := SysOpen(Nm, $241, 438)
      Else Fd := SysOpen(Nm, $441, 438);
      If Fd < 0 Then Die('impossible d''ouvrir ' + Nm + ' : ' +
                         SysErrorText(SysErrno));
      K := NewStream(Nm, 1, Fd, 0);
    End;
  End;
  OutFdOf := SFd[K];
End;

Function CloseStream(K : LongInt) : LongInt;
Var St : LongInt;
Begin
  CloseStream := 0;
  If SBuf[K] <> 0 Then
  Begin
    PFree(SBuf[K]);
    SBuf[K] := 0;
  End;
  If SAll[K] <> 0 Then
  Begin
    PFree(SAll[K]);
    SAll[K] := 0;
  End;
  If SFd[K] > 2 Then SysClose(SFd[K]);
  If SPid[K] > 0 Then
  Begin
    St := 0;
    SysWaitPid(SPid[K], St, 0);
    If SysWIfExited(St) Then CloseStream := SysWExitStatus(St)
    Else CloseStream := 256 + SysWTermSig(St);
  End;
  SKind[K] := 0;
  SName[K] := '';
End;

Function CloseByName(Const Nm : String) : LongInt;
Var K : LongInt; Any : Boolean; R : LongInt;
Begin
  Any := False;
  R := 0;
  For K := 1 To MaxStr Do
    If (SKind[K] <> 0) And (SName[K] = Nm) Then
    Begin
      Any := True;
      R := CloseStream(K);
    End;
  If Any Then CloseByName := R Else CloseByName := -1;
End;

Procedure CloseAll;
Var K : LongInt;
Begin
  FlushOut;
  For K := 1 To MaxStr Do
    If SKind[K] <> 0 Then CloseStream(K);
End;

Function GetByte(K : LongInt) : LongInt;
Begin
  If SPos[K] >= SLen[K] Then
  Begin
    If SEof[K] Then
    Begin
      GetByte := -1;
      Exit;
    End;
    If SBuf[K] = 0 Then SBuf[K] := PNew(65536);
    SLen[K] := SysCall(3, SFd[K], SBuf[K], 65536, 0, 0);
    SPos[K] := 0;
    If SLen[K] <= 0 Then
    Begin
      SLen[K] := 0;
      SEof[K] := True;
      GetByte := -1;
      Exit;
    End;
  End;
  GetByte := Mem[0:SBuf[K] + SPos[K]];
  Inc(SPos[K]);
End;

{ lit un enregistrement dans RdBuf selon RS ; Faux a la fin }
Function ReadRec(K : LongInt) : Boolean;
Var C, N, Sep, Cnt, Pr : LongInt; Prev : LongInt;
Begin
  ReadRec := False;
  RdLen := 0;
  If Length(RSStr) > 1 Then
  Begin
    { RS expression reguliere : tout le flux est lu une fois }
    If SAll[K] = 0 Then
    Begin
      SAllN[K] := 0;
      SAll[K] := PNew(1048576);
      SAllP[K] := 0;
      C := GetByte(K);
      While C >= 0 Do
      Begin
        If SAllN[K] < 1048576 Then
        Begin
          Mem[0:SAll[K] + SAllN[K]] := C;
          Inc(SAllN[K]);
        End;
        C := GetByte(K);
      End;
    End;
    If SAllP[K] >= SAllN[K] Then Exit;
    Pr := ReDyn(LongInt(@RSStr[1]), Length(RSStr));
    If ReSearch(Pr, SAll[K], SAllN[K], SAllP[K], True) And
       (ReCap[1] > ReCap[0]) Then
    Begin
      N := ReCap[0] - SAllP[K];
      If N > RecMax Then N := RecMax;
      MCopy(LongInt(@RdBuf[0]), SAll[K] + SAllP[K], N);
      RdLen := N;
      SAllP[K] := ReCap[1];
    End
    Else
    Begin
      N := SAllN[K] - SAllP[K];
      If N > RecMax Then N := RecMax;
      MCopy(LongInt(@RdBuf[0]), SAll[K] + SAllP[K], N);
      RdLen := N;
      SAllP[K] := SAllN[K];
      If (RdLen > 0) And (RdBuf[RdLen - 1] = #10) And (RSStr = '') Then
        Dec(RdLen);
    End;
    ReadRec := True;
    Exit;
  End;
  If RSStr = '' Then
  Begin
    C := GetByte(K);
    While C = 10 Do C := GetByte(K);
    If C < 0 Then Exit;
    Cnt := 0;
    While C >= 0 Do
    Begin
      If C = 10 Then
      Begin
        Inc(Cnt);
        If Cnt >= 2 Then Break;
      End
      Else
      Begin
        While Cnt > 0 Do
        Begin
          If RdLen < RecMax Then
          Begin
            RdBuf[RdLen] := #10;
            Inc(RdLen);
          End;
          Dec(Cnt);
        End;
        If RdLen < RecMax Then
        Begin
          RdBuf[RdLen] := Chr(C);
          Inc(RdLen);
        End;
      End;
      C := GetByte(K);
    End;
    ReadRec := True;
    Exit;
  End;
  Sep := Ord(RSStr[1]);
  C := GetByte(K);
  If C < 0 Then Exit;
  While (C >= 0) And (C <> Sep) Do
  Begin
    If RdLen < RecMax Then
    Begin
      RdBuf[RdLen] := Chr(C);
      Inc(RdLen);
    End;
    C := GetByte(K);
  End;
  ReadRec := True;
End;

Procedure ProcAssign(Const S : String); Forward;

{ ouvre le fichier operande suivant (ARGV) ; Faux si plus rien }
Function OpenMain : Boolean;
Var Nm : String; E, Kp : LongInt; Key : String;
Begin
  OpenMain := False;
  While ArgIdx < ArgC Do
  Begin
    Key := NumS(ArgIdx);
    Kp := ANew(Length(Key));
    For E := 1 To Length(Key) Do Mem[0:Kp + E - 1] := Ord(Key[E]);
    E := ArrFind(Cells[vARGV].Arr, Kp, Length(Key));
    Inc(ArgIdx);
    If E = 0 Then Continue;
    Nm := SGet(EVal[E].P, EVal[E].L);
    If Nm = '' Then Continue;
    If (Pos('=', Nm) > 1) And ((Nm[1] = '_') Or ((Nm[1] >= 'A') And
       (Nm[1] <= 'Z')) Or ((Nm[1] >= 'a') And (Nm[1] <= 'z'))) And
       (Pos('/', Copy(Nm, 1, Pos('=', Nm))) = 0) Then
    Begin
      ProcAssign(Nm);
      Continue;
    End;
    Inc(Assigns);
    SetStr(FnV, Nm);
    StoreVal(Cells[vFILENAME].V, FnV);
    If Nm = '-' Then SFd[0] := 0
    Else
    Begin
      SFd[0] := SysOpen(Nm, 0, 0);
      If SFd[0] < 0 Then
      Begin
        FlushOut;
        SysPut(2, 'awk: impossible de lire ' + Nm + ' : ' +
               SysErrorText(SysErrno) + #10);
        Status := 2;
        Continue;
      End;
    End;
    SPos[0] := 0;
    SLen[0] := 0;
    SEof[0] := False;
    SAll[0] := 0;
    FNRv := 0;
    MainOpen := True;
    OpenMain := True;
    Exit;
  End;
  If (Assigns = 0) And (Not MainDone) Then
  Begin
    { aucun fichier : entree standard }
    MainDone := True;
    Inc(Assigns);
    SFd[0] := 0;
    SPos[0] := 0;
    SLen[0] := 0;
    SEof[0] := False;
    SAll[0] := 0;
    MainOpen := True;
    OpenMain := True;
  End;
End;

Function NextMainRaw : Boolean;
Begin
  NextMainRaw := False;
  While True Do
  Begin
    If Not MainOpen Then
      If Not OpenMain Then Exit;
    If ReadRec(0) Then
    Begin
      Inc(NRv);
      Inc(FNRv);
      NextMainRaw := True;
      Exit;
    End;
    If SFd[0] > 0 Then SysClose(SFd[0]);
    SFd[0] := -1;
    If SAll[0] <> 0 Then
    Begin
      PFree(SAll[0]);
      SAll[0] := 0;
    End;
    MainOpen := False;
  End;
End;

Function NextMain : Boolean;
Begin
  NextMain := False;
  If NextMainRaw Then
  Begin
    SetRecord(LongInt(@RdBuf[0]), RdLen);
    NextMain := True;
  End;
End;

Procedure SkipFile;
Begin
  If MainOpen Then
  Begin
    If SFd[0] > 0 Then SysClose(SFd[0]);
    SFd[0] := -1;
    MainOpen := False;
  End;
End;

{ ---------- sprintf ---------- }

Type
  TArgs = Array[1..32] Of TVal;

Function IntStr(X : Extended) : String;
Begin
  If X < 0.0 Then X := -X;
  IntStr := FmtF(Int(X), 0);
End;

Function BaseStr(X : Extended; B : LongInt; Upper : Boolean) : String;
Var S : String; D : LongInt; Q : Extended;
Begin
  If X < 0.0 Then X := X + 18446744073709551616.0;
  If X = 0.0 Then
  Begin
    BaseStr := '0';
    Exit;
  End;
  S := '';
  While X >= 1.0 Do
  Begin
    Q := Int(X / B);
    D := Trunc(X - Q * B);
    If D < 10 Then S := Chr(48 + D) + S
    Else If Upper Then S := Chr(55 + D) + S
    Else S := Chr(87 + D) + S;
    X := Q;
  End;
  BaseStr := S;
End;

Procedure DoSprintf(FP, FL : LongInt; Var Args : TArgs; NArgs : LongInt);
Var
  AP, AL : Array[1..32] Of LongInt;
  I, K, Need, Out, OutN, Ai, Width, Prec, N, C : LongInt;
  Left, Plus, Space, Alt, Zero, HasPrec, Neg : Boolean;
  Conv : Char;
  Piece, Pre, Dg : String;
  X : Extended;
  Sp, Sl, Pad : LongInt;

  Procedure Put(Ch : Char);
  Begin
    If OutN < Need Then
    Begin
      Mem[0:Out + OutN] := Ord(Ch);
      Inc(OutN);
    End;
  End;

Begin
  Need := FL + 64;
  For K := 1 To NArgs Do
  Begin
    ToStr(Args[K], AP[K], AL[K]);
    Need := Need + AL[K] + 400;
  End;
  Out := ANew(Need);
  OutN := 0;
  Ai := 0;
  I := 0;
  While I < FL Do
  Begin
    C := Mem[0:FP + I];
    Inc(I);
    If C <> 37 Then
    Begin
      Put(Chr(C));
      Continue;
    End;
    Left := False; Plus := False; Space := False; Alt := False;
    Zero := False; HasPrec := False;
    Width := 0; Prec := 0;
    While I < FL Do
    Begin
      C := Mem[0:FP + I];
      If C = 45 Then Left := True
      Else If C = 43 Then Plus := True
      Else If C = 32 Then Space := True
      Else If C = 35 Then Alt := True
      Else If C = 48 Then Zero := True
      Else Break;
      Inc(I);
    End;
    If (I < FL) And (Mem[0:FP + I] = 42) Then
    Begin
      Inc(I);
      Inc(Ai);
      If Ai <= NArgs Then Width := Trunc(ToNum(Args[Ai]));
      If Width < 0 Then
      Begin
        Left := True;
        Width := -Width;
      End;
    End
    Else
      While (I < FL) And (Mem[0:FP + I] >= 48) And (Mem[0:FP + I] <= 57) Do
      Begin
        Width := Width * 10 + Mem[0:FP + I] - 48;
        Inc(I);
      End;
    If (I < FL) And (Mem[0:FP + I] = 46) Then
    Begin
      Inc(I);
      HasPrec := True;
      If (I < FL) And (Mem[0:FP + I] = 42) Then
      Begin
        Inc(I);
        Inc(Ai);
        If Ai <= NArgs Then Prec := Trunc(ToNum(Args[Ai]));
        If Prec < 0 Then HasPrec := False;
      End
      Else
        While (I < FL) And (Mem[0:FP + I] >= 48) And
              (Mem[0:FP + I] <= 57) Do
        Begin
          Prec := Prec * 10 + Mem[0:FP + I] - 48;
          Inc(I);
        End;
    End;
    While (I < FL) And ((Mem[0:FP + I] = 104) Or (Mem[0:FP + I] = 108) Or
          (Mem[0:FP + I] = 76) Or (Mem[0:FP + I] = 113) Or
          (Mem[0:FP + I] = 106) Or (Mem[0:FP + I] = 122) Or
          (Mem[0:FP + I] = 116)) Do Inc(I);
    If I >= FL Then
    Begin
      Put('%');
      Break;
    End;
    Conv := Chr(Mem[0:FP + I]);
    Inc(I);
    If Conv = '%' Then
    Begin
      Put('%');
      Continue;
    End;
    Inc(Ai);
    If Width > 300 Then Width := 300;
    If Conv = 's' Then
    Begin
      If Ai <= NArgs Then
      Begin
        Sp := AP[Ai];
        Sl := AL[Ai];
      End
      Else
      Begin
        Sp := 0;
        Sl := 0;
      End;
      If HasPrec And (Prec < Sl) Then Sl := Prec;
      Pad := Width - Sl;
      If (Pad > 0) And (Not Left) Then
        For K := 1 To Pad Do Put(' ');
      For K := 0 To Sl - 1 Do Put(Chr(Mem[0:Sp + K]));
      If (Pad > 0) And Left Then
        For K := 1 To Pad Do Put(' ');
      Continue;
    End;
    If Conv = 'c' Then
    Begin
      Pad := Width - 1;
      If (Pad > 0) And (Not Left) Then
        For K := 1 To Pad Do Put(' ');
      If Ai <= NArgs Then
      Begin
        If ((Args[Ai].F And fNum) <> 0) And ((Args[Ai].F And fStr) = 0) Then
          Put(Chr(Trunc(Args[Ai].N) And 255))
        Else If AL[Ai] > 0 Then Put(Chr(Mem[0:AP[Ai]]));
      End;
      If (Pad > 0) And Left Then
        For K := 1 To Pad Do Put(' ');
      Continue;
    End;
    If Ai <= NArgs Then X := ToNum(Args[Ai]) Else X := 0.0;
    Neg := X < 0.0;
    Pre := '';
    Dg := '';
    Case Conv Of
      'd', 'i' :
        Begin
          If Neg Then X := -X;
          Dg := IntStr(Int(X));
          If HasPrec Then
            While Length(Dg) < Prec Do Dg := '0' + Dg;
          If Neg Then Pre := '-'
          Else If Plus Then Pre := '+'
          Else If Space Then Pre := ' ';
        End;
      'u' : Dg := IntStr(Int(X));
      'o' : Dg := BaseStr(Int(X), 8, False);
      'x' : Dg := BaseStr(Int(X), 16, False);
      'X' : Dg := BaseStr(Int(X), 16, True);
      'e', 'E', 'f', 'F', 'g', 'G' :
        Begin
          If Not HasPrec Then Prec := 6;
          If Neg Then X := -X;
          If (Conv = 'e') Or (Conv = 'E') Then Dg := FmtE(X, Prec, Conv = 'E')
          Else If (Conv = 'f') Or (Conv = 'F') Then Dg := FmtF(X, Prec)
          Else Dg := FmtG(X, Prec, Alt, Conv = 'G');
          If Neg Then Pre := '-'
          Else If Plus Then Pre := '+'
          Else If Space Then Pre := ' ';
        End;
    Else
      Begin
        Put('%');
        Put(Conv);
        Continue;
      End;
    End;
    If (Conv = 'x') And Alt And (X <> 0.0) Then Pre := '0x';
    If (Conv = 'X') And Alt And (X <> 0.0) Then Pre := '0X';
    If (Conv = 'o') And Alt Then Dg := '0' + Dg;
    Pad := Width - Length(Pre) - Length(Dg);
    If Left Then
    Begin
      For K := 1 To Length(Pre) Do Put(Pre[K]);
      For K := 1 To Length(Dg) Do Put(Dg[K]);
      For K := 1 To Pad Do Put(' ');
    End
    Else If Zero And ((Not HasPrec) Or (Pos(Conv, 'eEfFgG') > 0)) Then
    Begin
      For K := 1 To Length(Pre) Do Put(Pre[K]);
      For K := 1 To Pad Do Put('0');
      For K := 1 To Length(Dg) Do Put(Dg[K]);
    End
    Else
    Begin
      For K := 1 To Pad Do Put(' ');
      For K := 1 To Length(Pre) Do Put(Pre[K]);
      For K := 1 To Length(Dg) Do Put(Dg[K]);
    End;
  End;
  Mem[0:Out + OutN] := 0;
  ATop := (Out - LongInt(@Arena[0])) + OutN + 1;
  RV.F := fStr;
  RV.P := Out;
  RV.L := OutN;
  RV.N := 0.0;
End;

{ ---------- evaluation ---------- }

Type
  TLv = Record
    Kind, Cell, Fld, Arr, KP, KL : LongInt;
  End;

Procedure Ev(N : LongInt); Forward;
Procedure Exec(N : LongInt); Forward;
Function CallFn(F, Args : LongInt) : Boolean; Forward;

Function Nth(H, I : LongInt) : LongInt;
Begin
  While (H <> 0) And (I > 1) Do
  Begin
    H := Nodes[H].D;
    Dec(I);
  End;
  Nth := H;
End;

Function Count(H : LongInt) : LongInt;
Var K : LongInt;
Begin
  K := 0;
  While H <> 0 Do
  Begin
    Inc(K);
    H := Nodes[H].D;
  End;
  Count := K;
End;

{ cle de tableau pour la liste de subscripts H (resultat dans l'arene) }
Procedure SubKey(H : LongInt; Var KP, KL : LongInt);
Var P, L, Tot, Pos0, N, K : LongInt;
    Ps, Ls : Array[1..16] Of LongInt;
Begin
  N := 0;
  Tot := 0;
  While (H <> 0) And (N < 16) Do
  Begin
    Ev(H);
    Inc(N);
    If ((RV.F And fNum) <> 0) And ((RV.F And fStr) = 0) And
       (RV.N = Int(RV.N)) And (Abs(RV.N) < 1.0E15) Then
      ToStrC(RV, Ps[N], Ls[N], '%d')
    Else ToStr(RV, Ps[N], Ls[N]);
    Tot := Tot + Ls[N];
    H := Nodes[H].D;
  End;
  If N = 1 Then
  Begin
    KP := Ps[1];
    KL := Ls[1];
    Exit;
  End;
  KP := ANew(Tot + N * Length(SubSep));
  Pos0 := 0;
  For K := 1 To N Do
  Begin
    If K > 1 Then
    Begin
      MCopy(KP + Pos0, LongInt(@SubSep[1]), Length(SubSep));
      Pos0 := Pos0 + Length(SubSep);
    End;
    MCopy(KP + Pos0, Ps[K], Ls[K]);
    Pos0 := Pos0 + Ls[K];
  End;
  Mem[0:KP + Pos0] := 0;
  KL := Pos0;
End;

Procedure ResolveLv(N : LongInt; Var L : TLv);
Var A : LongInt; V : LongInt;
Begin
  Case Nodes[N].Op Of
    nVar :
      Begin
        L.Kind := 1;
        If Nodes[N].B = 1 Then L.Cell := FrameBase + Nodes[N].A
        Else L.Cell := Nodes[N].A;
      End;
    nIdx :
      Begin
        L.Kind := 3;
        A := CellArr(CellIdx(Nodes[N].A));
        L.Arr := A;
        SubKey(Nodes[N].B, L.KP, L.KL);
      End;
    nFld :
      Begin
        Ev(Nodes[N].A);
        L.Kind := 2;
        V := Trunc(ToNum(RV));
        L.Fld := V;
      End;
  Else
    Die('affectation a une valeur non modifiable');
  End;
End;

Function Follow(I : LongInt) : LongInt;
Begin
  While Cells[I].Kind = 3 Do I := Cells[I].Ref;
  Follow := I;
End;

Procedure LvGet(Const L : TLv);
Var I, E : LongInt;
Begin
  Case L.Kind Of
    1 :
      Begin
        I := Follow(L.Cell);
        If I < NSpecial Then
        Begin
          If I = vNF Then SplitRecord;
          RefreshSpecial(I);
        End;
        If Cells[I].Kind = 2 Then Die('tableau utilise comme scalaire');
        If Cells[I].Kind = 0 Then SetUninit(RV)
        Else RV := Cells[I].V;
      End;
    2 : GetField(L.Fld);
    3 :
      Begin
        E := ArrGet(L.Arr, L.KP, L.KL);
        RV := EVal[E];
      End;
  End;
End;

Procedure SpecialAssigned(I : LongInt);
Var P, Ln : LongInt;
Begin
  ToStr(Cells[I].V, P, Ln);
  Case I Of
    vNF : SetNF(Trunc(ToNum(Cells[I].V)));
    vNR : NRv := Trunc(ToNum(Cells[I].V));
    vFNR : FNRv := Trunc(ToNum(Cells[I].V));
    vFS : FSStr := SGet(P, Ln);
    vOFS : OFSStr := SGet(P, Ln);
    vORS : ORSStr := SGet(P, Ln);
    vRS : RSStr := SGet(P, Ln);
    vSUBSEP : SubSep := SGet(P, Ln);
    vCONVFMT : ConvFmt := SGet(P, Ln);
    vOFMT : OFmt := SGet(P, Ln);
  End;
End;

Procedure LvSet(Const L : TLv; Const V : TVal);
Var I, T, E : LongInt;
Begin
  Case L.Kind Of
    1 :
      Begin
        I := L.Cell;
        If Cells[I].Kind = 3 Then
        Begin
          T := Follow(I);
          If Cells[T].Kind = 2 Then Die('tableau utilise comme scalaire');
          Cells[I].Kind := 1;
          SetUninit(Cells[I].V);
          Cells[I].V.P := 0;
        End
        Else If Cells[I].Kind = 0 Then
        Begin
          Cells[I].Kind := 1;
          SetUninit(Cells[I].V);
        End
        Else If Cells[I].Kind = 2 Then
          Die('tableau utilise comme scalaire');
        StoreVal(Cells[I].V, V);
        If I < NSpecial Then SpecialAssigned(I);
      End;
    2 : SetField(L.Fld, V);
    3 :
      Begin
        E := ArrGet(L.Arr, L.KP, L.KL);
        StoreVal(EVal[E], V);
      End;
  End;
End;

Function CmpVals(Const A, B : TVal) : LongInt;
Var X, Y : Double; P1, L1, P2, L2, K, M, C : LongInt;
Begin
  If IsNumeric(A) And IsNumeric(B) Then
  Begin
    X := ToNum(A);
    Y := ToNum(B);
    If X < Y Then CmpVals := -1
    Else If X > Y Then CmpVals := 1
    Else CmpVals := 0;
    Exit;
  End;
  ToStr(A, P1, L1);
  ToStr(B, P2, L2);
  M := L1;
  If L2 < M Then M := L2;
  For K := 0 To M - 1 Do
  Begin
    C := Mem[0:P1 + K] - Mem[0:P2 + K];
    If C <> 0 Then
    Begin
      If C < 0 Then CmpVals := -1 Else CmpVals := 1;
      Exit;
    End;
  End;
  If L1 < L2 Then CmpVals := -1
  Else If L1 > L2 Then CmpVals := 1
  Else CmpVals := 0;
End;

{ le noeud est-il un litteral regex (ou une valeur) : renvoie le programme }
Function RegexOf(N : LongInt) : LongInt;
Var P, L : LongInt;
Begin
  If Nodes[N].Op = nRe Then
  Begin
    If Nodes[N].A < 0 Then
    Begin
      Nodes[N].A := ReCompile(Nodes[N].S, True, False);
      If Nodes[N].A < 0 Then Die('expression reguliere : ' + ReErr +
                                 ' dans /' + Nodes[N].S + '/');
    End;
    RegexOf := Nodes[N].A;
    Exit;
  End;
  Ev(N);
  ToStr(RV, P, L);
  RegexOf := ReDyn(P, L);
End;

Procedure ProcAssign(Const S : String);
Var K, Idx : LongInt; Nm : String; V : TVal; Sx : String; P, I : LongInt;
Begin
  K := Pos('=', S);
  Nm := Copy(S, 1, K - 1);
  Sx := '';
  I := K + 1;
  While I <= Length(S) Do
  Begin
    If (S[I] = '\') And (I < Length(S)) Then
    Begin
      Inc(I);
      Case S[I] Of
        'n' : Sx := Sx + #10;
        't' : Sx := Sx + #9;
        '\' : Sx := Sx + '\';
        '"' : Sx := Sx + '"';
        'r' : Sx := Sx + #13;
      Else
        Sx := Sx + '\' + S[I];
      End;
    End
    Else Sx := Sx + S[I];
    Inc(I);
  End;
  Idx := GlobalIdx(Nm);
  If Cells[Idx].Kind = 0 Then Cells[Idx].Kind := 1;
  P := ANew(Length(Sx));
  For I := 1 To Length(Sx) Do Mem[0:P + I - 1] := Ord(Sx[I]);
  SetInput(V, P, Length(Sx));
  StoreVal(Cells[Idx].V, V);
  If Idx < NSpecial Then SpecialAssigned(Idx);
End;

{ substitution sub/gsub : Global ; renvoie le nombre de remplacements dans
  Cnt, le resultat dans OutP/OutL (arene) }
Procedure DoSub(Pr, SP1, SL1, RP, RL : LongInt; Global : Boolean;
                Var OutP, OutL, Cnt : LongInt);
Var Pos0, Ms, Me, W, K, PrevEnd, Cap : LongInt; C : LongInt;
Begin
  Cap := SL1 + 16;
  If Global Then Cap := SL1 * 2 + 16 + RL * 4;
  Cnt := 0;
  Pos0 := 0;
  PrevEnd := -1;
  W := 0;
  OutP := ANew(Cap + RL * 8 + 64);
  While Pos0 <= SL1 Do
  Begin
    If Not ReSearch(Pr, SP1, SL1, Pos0, True) Then Break;
    Ms := ReCap[0];
    Me := ReCap[1];
    If (Ms = Me) And (Ms = PrevEnd) Then
    Begin
      For K := Pos0 To Ms Do
        If K < SL1 Then
        Begin
          Mem[0:OutP + W] := Mem[0:SP1 + K];
          Inc(W);
        End;
      Pos0 := Ms + 1;
      Continue;
    End;
    If W + (Ms - Pos0) + RL * 8 + SL1 > Cap + RL * 8 + 60 Then
    Begin
      { agrandir : nouveau tampon dans l'arene }
      Cap := (W + (Ms - Pos0) + RL * 8 + SL1) * 2;
      C := ANew(Cap + RL * 8 + 64);
      MCopy(C, OutP, W);
      OutP := C;
    End;
    For K := Pos0 To Ms - 1 Do
    Begin
      Mem[0:OutP + W] := Mem[0:SP1 + K];
      Inc(W);
    End;
    K := 0;
    While K < RL Do
    Begin
      C := Mem[0:RP + K];
      If (C = 92) And (K + 1 < RL) And ((Mem[0:RP + K + 1] = 38) Or
         (Mem[0:RP + K + 1] = 92)) Then
      Begin
        Inc(K);
        Mem[0:OutP + W] := Mem[0:RP + K];
        Inc(W);
      End
      Else If C = 38 Then
      Begin
        MCopy(OutP + W, SP1 + Ms, Me - Ms);
        W := W + Me - Ms;
      End
      Else
      Begin
        Mem[0:OutP + W] := C;
        Inc(W);
      End;
      Inc(K);
    End;
    Inc(Cnt);
    PrevEnd := Me;
    If Me = Ms Then
    Begin
      If Me < SL1 Then
      Begin
        Mem[0:OutP + W] := Mem[0:SP1 + Me];
        Inc(W);
      End;
      Pos0 := Me + 1;
    End
    Else Pos0 := Me;
    If Not Global Then Break;
  End;
  If Cnt > 0 Then
    For K := Pos0 To SL1 - 1 Do
    Begin
      Mem[0:OutP + W] := Mem[0:SP1 + K];
      Inc(W);
    End;
  Mem[0:OutP + W] := 0;
  OutL := W;
End;

Function IsLvAt(N : LongInt) : Boolean;
Begin
  IsLvAt := (Nodes[N].Op = nVar) Or (Nodes[N].Op = nIdx) Or
            (Nodes[N].Op = nFld);
End;

Function PowD(X, Y : Double) : Double;
Var R : Double; N, K : LongInt; Neg : Boolean;
Begin
  If Y = Int(Y) Then
  Begin
    If Abs(Y) <= 4096.0 Then
    Begin
      N := Trunc(Abs(Y));
      R := 1.0;
      K := N;
      While K > 0 Do
      Begin
        If (K And 1) <> 0 Then R := R * X;
        X := X * X;
        K := K Shr 1;
      End;
      If Y < 0.0 Then R := 1.0 / R;
      PowD := R;
      Exit;
    End;
  End;
  If X > 0.0 Then PowD := Exp(Y * Ln(X))
  Else If X = 0.0 Then PowD := 0.0
  Else PowD := 0.0;
End;

Procedure EvBi(N : LongInt);
Var
  B, H, A1, A2, A3 : LongInt;
  P, L, P2, L2, I, K, M, E, Cnt, OP, OL, Pr, St : LongInt;
  X, Y : Double;
  Lv : TLv;
  S : String;
  Args : TArgs;
  V1 : TVal;
Begin
  B := Nodes[N].A;
  H := Nodes[N].B;
  A1 := Nth(H, 1);
  A2 := Nth(H, 2);
  A3 := Nth(H, 3);
  Case B Of
    bLength :
      Begin
        If A1 = 0 Then
        Begin
          GetField(0);
          SetNum(RV, RV.L);
        End
        Else If (Nodes[A1].Op = nVar) And (Cells[CellIdx(A1)].Kind = 2) Then
          SetNum(RV, Arrs[Cells[CellIdx(A1)].Arr].Cnt)
        Else
        Begin
          Ev(A1);
          ToStr(RV, P, L);
          SetNum(RV, L);
        End;
      End;
    bSubstr :
      Begin
        Ev(A1);
        ToStr(RV, P, L);
        Ev(A2);
        X := ToNum(RV);
        If X <> X Then X := 0.0;
        If X > 1.0E9 Then X := 1.0E9;
        If X < -1.0E9 Then X := -1.0E9;
        K := Round(X);
        If A3 <> 0 Then
        Begin
          Ev(A3);
          Y := ToNum(RV);
          If Y > 1.0E9 Then Y := 1.0E9;
          If Y < -1.0E9 Then Y := -1.0E9;
          M := Round(Y);
        End
        Else M := L + 1;
        { caracteres de K a K + M - 1 }
        E := K + M - 1;
        If K < 1 Then K := 1;
        If E > L Then E := L;
        If E < K Then
        Begin
          RV.F := fStr;
          RV.P := P;
          RV.L := 0;
        End
        Else
        Begin
          RV.F := fStr;
          RV.P := P + K - 1;
          RV.L := E - K + 1;
        End;
        RV.N := 0.0;
      End;
    bIndex :
      Begin
        Ev(A1);
        ToStr(RV, P, L);
        Ev(A2);
        ToStr(RV, P2, L2);
        M := 0;
        If L2 = 0 Then M := 0
        Else
          For I := 0 To L - L2 Do
          Begin
            K := 0;
            While (K < L2) And (Mem[0:P + I + K] = Mem[0:P2 + K]) Do Inc(K);
            If K = L2 Then
            Begin
              M := I + 1;
              Break;
            End;
          End;
        SetNum(RV, M);
      End;
    bSplit :
      Begin
        Ev(A1);
        ToStr(RV, P, L);
        P := ADup(P, L);
        K := CellArr(CellIdx(A2));
        ArrClear(K);
        If A3 <> 0 Then
        Begin
          If Nodes[A3].Op = nRe Then S := Nodes[A3].S
          Else
          Begin
            Ev(A3);
            ToStr(RV, P2, L2);
            S := SGet(P2, L2);
          End;
        End
        Else S := FSStr;
        Split(P, L, S, K);
        SetNum(RV, SplCnt);
      End;
    bSub, bGsub :
      Begin
        Pr := RegexOf(A1);
        Ev(A2);
        ToStr(RV, P2, L2);
        P2 := ADup(P2, L2);
        If A3 <> 0 Then
        Begin
          If Not IsLvAt(A3) Then
          Begin
            { cible non modifiable : calcul sans stockage }
            Ev(A3);
            ToStr(RV, P, L);
            DoSub(Pr, P, L, P2, L2, B = bGsub, OP, OL, Cnt);
            SetNum(RV, Cnt);
            Exit;
          End;
          ResolveLv(A3, Lv);
        End
        Else
        Begin
          Lv.Kind := 2;
          Lv.Fld := 0;
        End;
        LvGet(Lv);
        ToStr(RV, P, L);
        P := ADup(P, L);
        DoSub(Pr, P, L, P2, L2, B = bGsub, OP, OL, Cnt);
        If Cnt > 0 Then
        Begin
          SetStr(V1, '');
          V1.F := fStr;
          V1.P := OP;
          V1.L := OL;
          LvSet(Lv, V1);
        End;
        SetNum(RV, Cnt);
      End;
    bMatch :
      Begin
        Ev(A1);
        ToStr(RV, P, L);
        P := ADup(P, L);
        Pr := RegexOf(A2);
        If ReSearch(Pr, P, L, 0, True) Then
        Begin
          RStart := ReCap[0] + 1;
          RLength := ReCap[1] - ReCap[0];
          If A3 <> 0 Then
          Begin
            K := CellArr(CellIdx(A3));
            ArrClear(K);
            For I := 0 To 9 Do
              If (ReCap[2 * I] >= 0) And (ReCap[2 * I + 1] >= ReCap[2 * I]) Then
              Begin
                S := NumS(I);
                E := ArrGet(K, LongInt(@S[1]), Length(S));
                SetInput(V1, P + ReCap[2 * I], ReCap[2 * I + 1] -
                         ReCap[2 * I]);
                StoreVal(EVal[E], V1);
              End;
          End;
        End
        Else
        Begin
          RStart := 0;
          RLength := -1;
        End;
        SetNum(Cells[vRSTART].V, RStart);
        SetNum(Cells[vRLENGTH].V, RLength);
        SetNum(RV, RStart);
      End;
    bSprintf :
      Begin
        Ev(A1);
        ToStr(RV, P, L);
        P := ADup(P, L);
        K := 0;
        M := Nodes[A1].D;
        While (M <> 0) And (K < 32) Do
        Begin
          Inc(K);
          Ev(M);
          Args[K] := RV;
          If ((Args[K].F And fStr) <> 0) And (Args[K].P <> 0) Then
          Begin
            Args[K].P := ADup(Args[K].P, Args[K].L);
          End;
          M := Nodes[M].D;
        End;
        DoSprintf(P, L, Args, K);
      End;
    bSin : Begin Ev(A1); SetNum(RV, Sin(ToNum(RV))); End;
    bCos : Begin Ev(A1); SetNum(RV, Cos(ToNum(RV))); End;
    bAtan2 :
      Begin
        Ev(A1);
        X := ToNum(RV);
        Ev(A2);
        Y := ToNum(RV);
        If Y = 0.0 Then
        Begin
          If X > 0.0 Then SetNum(RV, 1.5707963267948966)
          Else If X < 0.0 Then SetNum(RV, -1.5707963267948966)
          Else SetNum(RV, 0.0);
        End
        Else If Y > 0.0 Then SetNum(RV, ArcTan(X / Y))
        Else If X >= 0.0 Then SetNum(RV, ArcTan(X / Y) + 3.141592653589793)
        Else SetNum(RV, ArcTan(X / Y) - 3.141592653589793);
      End;
    bExp :
      Begin
        Ev(A1);
        X := ToNum(RV);
        If X > 700.0 Then Die('exp : debordement');
        SetNum(RV, Exp(X));
      End;
    bLog :
      Begin
        Ev(A1);
        X := ToNum(RV);
        If X <= 0.0 Then
        Begin
          FlushOut;
          SysPut(2, 'awk: log : argument hors domaine' + #10);
          SetNum(RV, -1.0E300);
        End
        Else SetNum(RV, Ln(X));
      End;
    bSqrt :
      Begin
        Ev(A1);
        X := ToNum(RV);
        If X < 0.0 Then
        Begin
          FlushOut;
          SysPut(2, 'awk: sqrt : argument hors domaine' + #10);
          SetNum(RV, 0.0);
        End
        Else SetNum(RV, Sqrt(X));
      End;
    bInt : Begin Ev(A1); SetNum(RV, Int(ToNum(RV))); End;
    bRand :
      Begin
        Seed := (Seed * 1103515245 + 12345) And $7FFFFFFF;
        SetNum(RV, (Seed Shr 7) / 16777216.0);
      End;
    bSrand :
      Begin
        K := PrevSeed;
        If A1 <> 0 Then
        Begin
          Ev(A1);
          PrevSeed := Trunc(ToNum(RV));
        End
        Else PrevSeed := SysTime;
        Seed := PrevSeed And $7FFFFFFF;
        SetNum(RV, K);
      End;
    bTolower, bToupper :
      Begin
        Ev(A1);
        ToStr(RV, P, L);
        OP := ANew(L);
        For I := 0 To L - 1 Do
        Begin
          K := Mem[0:P + I];
          If (B = bTolower) And (K >= 65) And (K <= 90) Then K := K + 32;
          If (B = bToupper) And (K >= 97) And (K <= 122) Then K := K - 32;
          Mem[0:OP + I] := K;
        End;
        Mem[0:OP + L] := 0;
        RV.F := fStr;
        RV.P := OP;
        RV.L := L;
        RV.N := 0.0;
      End;
    bSystem :
      Begin
        Ev(A1);
        ToStr(RV, P, L);
        S := SGet(P, L);
        FlushOut;
        K := SysFork;
        If K = 0 Then
        Begin
          SysArgReset;
          SysArgAdd('sh');
          SysArgAdd('-c');
          SysArgAdd(S);
          SysArgExec('/bin/sh');
          SysExit(127);
        End;
        St := 0;
        SysWaitPid(K, St, 0);
        If SysWIfExited(St) Then SetNum(RV, SysWExitStatus(St))
        Else SetNum(RV, 256 + SysWTermSig(St));
      End;
    bClose :
      Begin
        Ev(A1);
        ToStr(RV, P, L);
        SetNum(RV, CloseByName(SGet(P, L)));
      End;
    bFflush :
      Begin
        FlushOut;
        SetNum(RV, 0);
      End;
    bSystime : SetNum(RV, SysTime);
  End;
End;

Procedure DoGetline(N : LongInt);
Var Kind, Lvn, Src, K, Fd, Pid, P, L : LongInt; Lv : TLv; V : TVal;
    Nm : String; Ok : Boolean;
Begin
  Kind := Nodes[N].A;
  Lvn := Nodes[N].B;
  Src := Nodes[N].C;
  If Lvn <> 0 Then ResolveLv(Lvn, Lv);
  Ok := False;
  If Kind = 0 Then
  Begin
    If Lvn = 0 Then
    Begin
      If NextMain Then SetNum(RV, 1.0) Else SetNum(RV, 0.0);
      Exit;
    End;
    If Not NextMainRaw Then
    Begin
      SetNum(RV, 0.0);
      Exit;
    End;
    P := ANew(RdLen);
    MCopy(P, LongInt(@RdBuf[0]), RdLen);
    SetInput(V, P, RdLen);
    LvSet(Lv, V);
    SetNum(RV, 1.0);
    Exit;
  End;
  Ev(Src);
  ToStr(RV, P, L);
  Nm := SGet(P, L);
  If Kind = 1 Then
  Begin
    K := FindStream(Nm, 3);
    If K < 0 Then
    Begin
      If Nm = '-' Then Fd := 0 Else Fd := SysOpen(Nm, 0, 0);
      If Fd < 0 Then
      Begin
        SetNum(RV, -1.0);
        Exit;
      End;
      K := NewStream(Nm, 3, Fd, 0);
    End;
  End
  Else
  Begin
    K := FindStream(Nm, 4);
    If K < 0 Then
    Begin
      StartCmd(Nm, False, Fd, Pid);
      If Fd < 0 Then
      Begin
        SetNum(RV, -1.0);
        Exit;
      End;
      K := NewStream(Nm, 4, Fd, Pid);
    End;
  End;
  If Not ReadRec(K) Then
  Begin
    SetNum(RV, 0.0);
    Exit;
  End;
  If Kind = 2 Then
  Begin
    Inc(NRv);
  End;
  If Lvn = 0 Then SetRecord(LongInt(@RdBuf[0]), RdLen)
  Else
  Begin
    P := ANew(RdLen);
    MCopy(P, LongInt(@RdBuf[0]), RdLen);
    SetInput(V, P, RdLen);
    LvSet(Lv, V);
  End;
  SetNum(RV, 1.0);
End;

{ s = s expr expr... : ajout en place avec capacite (evite le cout
  quadratique des constructions de chaines) }
Function AppendFast(N : LongInt) : Boolean;
Var
  Ops : Array[1..16] Of LongInt;
  Ps, Ls : Array[1..16] Of LongInt;
  NO, T, K, Ci, Tot, L0, NewCap, Np, W : LongInt;
  R : LongInt;
Begin
  AppendFast := False;
  If Nodes[Nodes[N].A].Op <> nVar Then Exit;
  { operandes de la chaine nCat de gauche a droite }
  NO := 0;
  R := Nodes[N].B;
  While Nodes[R].Op = nCat Do
  Begin
    If NO >= 15 Then Exit;
    Inc(NO);
    Ops[NO] := Nodes[R].B;
    R := Nodes[R].A;
  End;
  If (Nodes[R].Op <> nVar) Or (Nodes[R].A <> Nodes[Nodes[N].A].A) Or
     (Nodes[R].B <> Nodes[Nodes[N].A].B) Then Exit;
  If NO = 0 Then Exit;
  If Nodes[R].B = 1 Then Ci := FrameBase + Nodes[R].A Else Ci := Nodes[R].A;
  If Cells[Ci].Kind <> 1 Then Exit;
  If Ci < NSpecial Then Exit;
  If ((Cells[Ci].V.F And fStr) = 0) Or (Cells[Ci].V.P = 0) Or
     ((Cells[Ci].V.F And fNum) <> 0) Then Exit;
  { evaluer les operandes (ordre inverse de la liste) }
  Tot := 0;
  For K := NO DownTo 1 Do
  Begin
    Ev(Ops[K]);
    ToStr(RV, Ps[NO - K + 1], Ls[NO - K + 1]);
    Ps[NO - K + 1] := ADup(Ps[NO - K + 1], Ls[NO - K + 1]);
    Tot := Tot + Ls[NO - K + 1];
  End;
  L0 := Cells[Ci].V.L;
  If Cells[Ci].V.C < L0 + Tot + 1 Then
  Begin
    NewCap := (L0 + Tot) * 2 + 16;
    Np := PNew(NewCap);
    MCopy(Np, Cells[Ci].V.P, L0);
    PFree(Cells[Ci].V.P);
    Cells[Ci].V.P := Np;
    Cells[Ci].V.C := NewCap;
  End;
  W := Cells[Ci].V.P + L0;
  For K := 1 To NO Do
  Begin
    MCopy(W, Ps[K], Ls[K]);
    W := W + Ls[K];
  End;
  Mem[0:W] := 0;
  Cells[Ci].V.L := L0 + Tot;
  Cells[Ci].V.F := fStr;
  Cells[Ci].V.N := 0.0;
  RV := Cells[Ci].V;
  AppendFast := True;
End;

Procedure Ev(N : LongInt);
Var
  Op, K, P, L, P2, L2, I, T : LongInt;
  X, Y, R : Double;
  A, B : TVal;
  Lv : TLv;
  Pr : LongInt;
Begin
  Op := Nodes[N].Op;
  Case Op Of
    nNum : SetNum(RV, Nodes[N].X);
    nStr :
      Begin
        If Nodes[N].A = 0 Then
        Begin
          Nodes[N].B := Length(Nodes[N].S);
          Nodes[N].A := PNew(Nodes[N].B);
          For I := 1 To Nodes[N].B Do
            Mem[0:Nodes[N].A + I - 1] := Ord(Nodes[N].S[I]);
          Mem[0:Nodes[N].A + Nodes[N].B] := 0;
        End;
        RV.F := fStr;
        RV.P := Nodes[N].A;
        RV.L := Nodes[N].B;
        RV.N := 0.0;
      End;
    nRe :
      Begin
        Pr := RegexOf(N);
        GetField(0);
        SetBool(RV, ReSearch(Pr, LongInt(@Rec[0]), RecLen, 0, False));
      End;
    nVar, nIdx, nFld :
      Begin
        If Op = nVar Then
        Begin
          If Nodes[N].B = 1 Then K := FrameBase + Nodes[N].A
          Else K := Nodes[N].A;
          K := Follow(K);
          If K < NSpecial Then
          Begin
            If K = vNF Then SplitRecord;
            RefreshSpecial(K);
          End;
          If Cells[K].Kind = 1 Then RV := Cells[K].V
          Else If Cells[K].Kind = 0 Then SetUninit(RV)
          Else Die('tableau utilise comme scalaire');
        End
        Else
        Begin
          ResolveLv(N, Lv);
          LvGet(Lv);
        End;
      End;
    nGroup :
      Begin
        If Nodes[N].A = 0 Then SetUninit(RV) Else Ev(Nodes[N].A);
      End;
    nAsg :
      Begin
        K := Nodes[N].C;
        If (K = 0) And (Nodes[Nodes[N].B].Op = nCat) And
           AppendFast(N) Then Exit;
        If K = 0 Then
        Begin
          Ev(Nodes[N].B);
          B := RV;
          If ((B.F And fStr) <> 0) And (B.P <> 0) Then
          Begin
            { la valeur peut pointer dans la cible : copie temporaire }
            B.P := ADup(B.P, B.L);
          End;
          ResolveLv(Nodes[N].A, Lv);
          LvSet(Lv, B);
          RV := B;
        End
        Else
        Begin
          Ev(Nodes[N].B);
          B := RV;
          ResolveLv(Nodes[N].A, Lv);
          LvGet(Lv);
          X := ToNum(RV);
          Y := ToNum(B);
          Case K Of
            43 : R := X + Y;
            45 : R := X - Y;
            42 : R := X * Y;
            47 : Begin
                   If Y = 0.0 Then Die('division par zero dans /=');
                   R := X / Y;
                 End;
            37 : Begin
                   If Y = 0.0 Then Die('division par zero dans %=');
                   R := X - Y * Int(X / Y);
                 End;
          Else
            R := PowD(X, Y);
          End;
          SetNum(A, R);
          LvSet(Lv, A);
          RV := A;
        End;
      End;
    nCond :
      Begin
        Ev(Nodes[N].A);
        If Truth(RV) Then Ev(Nodes[N].B) Else Ev(Nodes[N].C);
      End;
    nOr :
      Begin
        Ev(Nodes[N].A);
        If Truth(RV) Then SetBool(RV, True)
        Else
        Begin
          Ev(Nodes[N].B);
          SetBool(RV, Truth(RV));
        End;
      End;
    nAnd :
      Begin
        Ev(Nodes[N].A);
        If Not Truth(RV) Then SetBool(RV, False)
        Else
        Begin
          Ev(Nodes[N].B);
          SetBool(RV, Truth(RV));
        End;
      End;
    nIn :
      Begin
        If Nodes[N].C = 1 Then SubKey(Nodes[N].A, P, L)
        Else
        Begin
          Ev(Nodes[N].A);
          ToStr(RV, P, L);
        End;
        K := CellArr(CellIdx(Nodes[N].B));
        SetBool(RV, ArrFind(K, P, L) <> 0);
      End;
    nMatch, nNmatch :
      Begin
        Ev(Nodes[N].A);
        ToStr(RV, P, L);
        P := ADup(P, L);
        Pr := RegexOf(Nodes[N].B);
        If Op = nMatch Then SetBool(RV, ReSearch(Pr, P, L, 0, False))
        Else SetBool(RV, Not ReSearch(Pr, P, L, 0, False));
      End;
    nCmp :
      Begin
        Ev(Nodes[N].A);
        A := RV;
        If ((A.F And fStr) <> 0) And (A.P <> 0) Then A.P := ADup(A.P, A.L);
        Ev(Nodes[N].B);
        K := CmpVals(A, RV);
        Case Nodes[N].C Of
          60 : SetBool(RV, K < 0);
          oLe : SetBool(RV, K <= 0);
          oEq : SetBool(RV, K = 0);
          oNe : SetBool(RV, K <> 0);
          62 : SetBool(RV, K > 0);
          oGe : SetBool(RV, K >= 0);
        End;
      End;
    nCat :
      Begin
        Ev(Nodes[N].A);
        ToStr(RV, P, L);
        P := ADup(P, L);
        Ev(Nodes[N].B);
        ToStr(RV, P2, L2);
        T := ANew(L + L2);
        MCopy(T, P, L);
        MCopy(T + L, P2, L2);
        Mem[0:T + L + L2] := 0;
        RV.F := fStr;
        RV.P := T;
        RV.L := L + L2;
        RV.N := 0.0;
      End;
    nBin :
      Begin
        Ev(Nodes[N].A);
        X := ToNum(RV);
        Ev(Nodes[N].B);
        Y := ToNum(RV);
        Case Nodes[N].C Of
          43 : R := X + Y;
          45 : R := X - Y;
          42 : R := X * Y;
          47 : Begin
                 If Y = 0.0 Then Die('division par zero');
                 R := X / Y;
               End;
          37 : Begin
                 If Y = 0.0 Then Die('division par zero dans %');
                 R := X - Y * Int(X / Y);
               End;
        Else
          R := PowD(X, Y);
        End;
        SetNum(RV, R);
      End;
    nNeg : Begin Ev(Nodes[N].A); SetNum(RV, -ToNum(RV)); End;
    nPlus : Begin Ev(Nodes[N].A); SetNum(RV, ToNum(RV)); End;
    nNot : Begin Ev(Nodes[N].A); SetBool(RV, Not Truth(RV)); End;
    nPre, nPost :
      Begin
        ResolveLv(Nodes[N].A, Lv);
        LvGet(Lv);
        X := ToNum(RV);
        SetNum(A, X + Nodes[N].C);
        LvSet(Lv, A);
        If Op = nPre Then SetNum(RV, X + Nodes[N].C) Else SetNum(RV, X);
      End;
    nCall :
      Begin
        If Not CallFn(Nodes[N].A, Nodes[N].B) Then SetUninit(RV);
      End;
    nBi : EvBi(N);
    nGetl : DoGetline(N);
  Else
    Die('noeud inconnu');
  End;
End;

{ appel d'une fonction utilisateur ; Faux si pas de valeur }
Function CallFn(F, Args : LongInt) : Boolean;
Var
  NP, I, NewBase, A, Ci, OldBase, EntryTop, K, Sp, Dp : LongInt;
  Cnt : LongInt;
  Tmp : Array[0..31] Of TVal;
  Al : Array[0..31] Of LongInt;
  OldFlow : LongInt;
Begin
  NP := FnNPar[F];
  Cnt := Count(Args);
  If Cnt > NP Then Die('trop d''arguments pour ' + FnName[F]);
  If Depth > 400 Then Die('recursion trop profonde');
  Inc(Depth);
  EntryTop := ATop;
  NewBase := SPTop;
  If NewBase + NP + 2 >= MaxCell Then Die('pile de variables epuisee');
  { evaluer les arguments dans le cadre de l'appelant }
  A := Args;
  For I := 0 To NP - 1 Do
  Begin
    Al[I] := -1;
    If A <> 0 Then
    Begin
      If Nodes[A].Op = nVar Then
      Begin
        Ci := CellIdx(A);
        If (Cells[Ci].Kind = 2) Or (Cells[Ci].Kind = 0) Then
        Begin
          Al[I] := Ci;
          Tmp[I].F := 0;
          A := Nodes[A].D;
          Continue;
        End;
      End;
      Ev(A);
      Tmp[I] := RV;
      If ((Tmp[I].F And fStr) <> 0) And (Tmp[I].P <> 0) Then
        Tmp[I].P := ADup(Tmp[I].P, Tmp[I].L);
      A := Nodes[A].D;
    End
    Else
    Begin
      Al[I] := -2;
    End;
  End;
  For I := 0 To NP - 1 Do
  Begin
    Cells[NewBase + I].Kind := 0;
    Cells[NewBase + I].Arr := 0;
    Cells[NewBase + I].V.F := 0;
    Cells[NewBase + I].V.P := 0;
    If Al[I] = -2 Then Continue;
    If Al[I] >= 0 Then
    Begin
      Cells[NewBase + I].Kind := 3;
      Cells[NewBase + I].Ref := Al[I];
    End
    Else
    Begin
      Cells[NewBase + I].Kind := 1;
      Cells[NewBase + I].V.F := 0;
      Cells[NewBase + I].V.P := 0;
      StoreVal(Cells[NewBase + I].V, Tmp[I]);
    End;
  End;
  OldBase := FrameBase;
  FrameBase := NewBase;
  SPTop := NewBase + NP;
  RetVal.F := 0;
  Exec(FnBody[F]);
  FrameBase := OldBase;
  SPTop := NewBase;
  { liberer les locales }
  For I := 0 To NP - 1 Do
  Begin
    If Cells[NewBase + I].Kind = 1 Then ClearVal(Cells[NewBase + I].V)
    Else If Cells[NewBase + I].Kind = 2 Then ArrFree(Cells[NewBase + I].Arr);
    Cells[NewBase + I].Kind := 0;
  End;
  Dec(Depth);
  CallFn := False;
  If Flow = 3 Then
  Begin
    Flow := 0;
    { la valeur de retour est dans l'arene au-dessus de EntryTop : on la
      ramene au niveau d'entree }
    RV := RetVal;
    If (RV.F And fStr) <> 0 Then
    Begin
      MCopy(LongInt(@Arena[0]) + EntryTop, RV.P, RV.L);
      Mem[0:LongInt(@Arena[0]) + EntryTop + RV.L] := 0;
      RV.P := LongInt(@Arena[0]) + EntryTop;
      ATop := EntryTop + RV.L + 1;
    End
    Else ATop := EntryTop;
    CallFn := True;
  End
  Else ATop := EntryTop;
End;

Procedure PrintOut(Fd : LongInt; Const V : TVal; Fmt : Boolean);
Var P, L : LongInt;
Begin
  If Fmt Then ToStrC(V, P, L, OFmt) Else ToStr(V, P, L);
  WriteFd(Fd, P, L);
End;

Procedure Exec(N : LongInt);
Var
  Op, K, Mk0, Fd, Kind, H, M, I, Ar, Cnt, P, L, Pe : LongInt;
  Lv : TLv;
  Args : TArgs;
  V : TVal;
  Keys : LongInt;
  Nm : String;
  Cur, Nx : LongInt;
Begin
  Op := Nodes[N].Op;
  Mk0 := ATop;
  Case Op Of
    sExpr : Ev(Nodes[N].A);
    sBlock :
      Begin
        K := Nodes[N].A;
        While (K <> 0) And (Flow = 0) Do
        Begin
          Exec(K);
          K := Nodes[K].D;
        End;
      End;
    sIf :
      Begin
        Ev(Nodes[N].A);
        If Truth(RV) Then
        Begin
          ATop := Mk0;
          If Nodes[N].B <> 0 Then Exec(Nodes[N].B);
        End
        Else
        Begin
          ATop := Mk0;
          If Nodes[N].C <> 0 Then Exec(Nodes[N].C);
        End;
      End;
    sWhile :
      Begin
        While Flow = 0 Do
        Begin
          ATop := Mk0;
          Ev(Nodes[N].A);
          If Not Truth(RV) Then Break;
          ATop := Mk0;
          If Nodes[N].B <> 0 Then Exec(Nodes[N].B);
          If Flow = 4 Then
          Begin
            Flow := 0;
            Break;
          End;
          If Flow = 5 Then Flow := 0;
        End;
      End;
    sDo :
      Begin
        While Flow = 0 Do
        Begin
          ATop := Mk0;
          If Nodes[N].A <> 0 Then Exec(Nodes[N].A);
          If Flow = 4 Then
          Begin
            Flow := 0;
            Break;
          End;
          If Flow = 5 Then Flow := 0;
          If Flow <> 0 Then Break;
          ATop := Mk0;
          Ev(Nodes[N].B);
          If Not Truth(RV) Then Break;
        End;
      End;
    sFor :
      Begin
        If Nodes[N].A <> 0 Then Exec(Nodes[N].A);
        While Flow = 0 Do
        Begin
          ATop := Mk0;
          If Nodes[N].B <> 0 Then
          Begin
            Ev(Nodes[N].B);
            If Not Truth(RV) Then Break;
          End;
          ATop := Mk0;
          K := Trunc(Nodes[N].X);
          If K <> 0 Then Exec(K);
          If Flow = 4 Then
          Begin
            Flow := 0;
            Break;
          End;
          If Flow = 5 Then Flow := 0;
          If Flow <> 0 Then Break;
          ATop := Mk0;
          If Nodes[N].C <> 0 Then Exec(Nodes[N].C);
        End;
      End;
    sForIn :
      Begin
        Ar := CellArr(CellIdx(Nodes[N].B));
        Cnt := Arrs[Ar].Cnt;
        Keys := ANew(Cnt * 8 + 8);
        I := 0;
        Cur := Arrs[Ar].First;
        While Cur <> 0 Do
        Begin
          MemL[0:Keys + I * 8] := ADup(EKeyP[Cur], EKeyL[Cur]);
          MemL[0:Keys + I * 8 + 4] := EKeyL[Cur];
          Inc(I);
          Cur := ENext[Cur];
        End;
        Mk0 := ATop;
        K := 0;
        While (K < Cnt) And (Flow = 0) Do
        Begin
          ATop := Mk0;
          If ArrFind(Ar, MemL[0:Keys + K * 8], MemL[0:Keys + K * 8 + 4]) <> 0
          Then
          Begin
            ResolveLv(Nodes[N].A, Lv);
            SetInput(V, MemL[0:Keys + K * 8], MemL[0:Keys + K * 8 + 4]);
            LvSet(Lv, V);
            ATop := Mk0;
            If Nodes[N].C <> 0 Then Exec(Nodes[N].C);
            If Flow = 4 Then
            Begin
              Flow := 0;
              Break;
            End;
            If Flow = 5 Then Flow := 0;
          End;
          Inc(K);
        End;
      End;
    sPrint, sPrintf :
      Begin
        Kind := Nodes[N].B;
        Fd := 1;
        If Kind <> 0 Then
        Begin
          Ev(Nodes[N].C);
          ToStr(RV, P, L);
          Fd := OutFdOf(Kind, SGet(P, L));
        End;
        H := Nodes[N].A;
        If Op = sPrint Then
        Begin
          If H = 0 Then
          Begin
            GetField(0);
            WriteFd(Fd, RV.P, RV.L);
          End
          Else
          Begin
            M := H;
            I := 0;
            While M <> 0 Do
            Begin
              If I > 0 Then WriteFd(Fd, LongInt(@OFSStr[1]), Length(OFSStr));
              Ev(M);
              PrintOut(Fd, RV, True);
              Inc(I);
              M := Nodes[M].D;
            End;
          End;
          WriteFd(Fd, LongInt(@ORSStr[1]), Length(ORSStr));
        End
        Else
        Begin
          Ev(H);
          ToStr(RV, P, L);
          P := ADup(P, L);
          K := 0;
          M := Nodes[H].D;
          While (M <> 0) And (K < 32) Do
          Begin
            Inc(K);
            Ev(M);
            Args[K] := RV;
            If ((Args[K].F And fStr) <> 0) And (Args[K].P <> 0) Then
              Args[K].P := ADup(Args[K].P, Args[K].L);
            M := Nodes[M].D;
          End;
          DoSprintf(P, L, Args, K);
          WriteFd(Fd, RV.P, RV.L);
        End;
        If (Fd = 2) Then FlushOut;
      End;
    sNext : Flow := 1;
    sNextF : Flow := 6;
    sExit :
      Begin
        If Nodes[N].A <> 0 Then
        Begin
          Ev(Nodes[N].A);
          ExitCode := Trunc(ToNum(RV));
        End;
        Flow := 2;
      End;
    sRet :
      Begin
        If Nodes[N].A <> 0 Then
        Begin
          Ev(Nodes[N].A);
          RetVal := RV;
          If ((RetVal.F And fStr) <> 0) And (RetVal.P <> 0) Then
            RetVal.P := ADup(RetVal.P, RetVal.L);
        End
        Else SetUninit(RetVal);
        Flow := 3;
        Exit;
      End;
    sBreak : Flow := 4;
    sCont : Flow := 5;
    sDel :
      Begin
        K := Nodes[N].A;
        Ar := CellArr(CellIdx(Nodes[K].A));
        SubKey(Nodes[K].B, P, L);
        ArrDel(Ar, P, L);
      End;
    sDelAll :
      Begin
        Ar := CellArr(CellIdx(Nodes[N].A));
        ArrClear(Ar);
      End;
  End;
  If Flow <> 3 Then ATop := Mk0;
End;

{ ---------- programme principal ---------- }

Procedure RunRules(Kind : LongInt);
Var R : LongInt;
Begin
  For R := 1 To NRule Do
    If RuleK[R] = Kind Then
    Begin
      If RuleAct[R] <> 0 Then Exec(RuleAct[R]);
      If Flow = 2 Then Exit;
      Flow := 0;
    End;
End;

Procedure AddSrcText(Const S : String);
Var K : LongInt;
Begin
  If (SrcN > 0) And (SrcN < 131060) Then
  Begin
    Src[SrcN] := #10;
    Inc(SrcN);
  End;
  For K := 1 To Length(S) Do
    If SrcN < 131060 Then
    Begin
      Src[SrcN] := S[K];
      Inc(SrcN);
    End;
End;

Procedure AddSrcFile(Const Fn : String);
Var Fd, N, K : LongInt; Buf : Array[0..4095] Of Byte;
Begin
  If Fn = '-' Then Fd := 0 Else Fd := SysOpen(Fn, 0, 0);
  If Fd < 0 Then Die('impossible de lire ' + Fn + ' : ' +
                     SysErrorText(SysErrno));
  If (SrcN > 0) And (SrcN < 131060) Then
  Begin
    Src[SrcN] := #10;
    Inc(SrcN);
  End;
  N := SysRead(Fd, Buf[0], 4096);
  While N > 0 Do
  Begin
    For K := 0 To N - 1 Do
      If SrcN < 131060 Then
      Begin
        Src[SrcN] := Chr(Buf[K]);
        Inc(SrcN);
      End;
    N := SysRead(Fd, Buf[0], 4096);
  End;
  If Fd > 0 Then SysClose(Fd);
End;

Procedure InitVars;
Var K, Idx, E : LongInt; S, Key : String; V : TVal; P : LongInt;
Begin
  GNames[vNF] := 'NF';
  GNames[vNR] := 'NR';
  GNames[vFNR] := 'FNR';
  GNames[vFS] := 'FS';
  GNames[vOFS] := 'OFS';
  GNames[vORS] := 'ORS';
  GNames[vRS] := 'RS';
  GNames[vFILENAME] := 'FILENAME';
  GNames[vSUBSEP] := 'SUBSEP';
  GNames[vRSTART] := 'RSTART';
  GNames[vRLENGTH] := 'RLENGTH';
  GNames[vCONVFMT] := 'CONVFMT';
  GNames[vOFMT] := 'OFMT';
  GNames[vENVIRON] := 'ENVIRON';
  GNames[vARGC] := 'ARGC';
  GNames[vARGV] := 'ARGV';
  NGlob := NSpecial;
  For K := 0 To NSpecial - 1 Do
  Begin
    Cells[K].Kind := 1;
    SetUninit(Cells[K].V);
  End;
  Cells[vENVIRON].Kind := 0;
  Cells[vARGV].Kind := 0;
  FSStr := ' ';
  OFSStr := ' ';
  ORSStr := #10;
  RSStr := #10;
  SubSep := #28;
  ConvFmt := '%.6g';
  OFmt := '%.6g';
  SetStr(V, FSStr); StoreVal(Cells[vFS].V, V);
  SetStr(V, OFSStr); StoreVal(Cells[vOFS].V, V);
  SetStr(V, ORSStr); StoreVal(Cells[vORS].V, V);
  SetStr(V, RSStr); StoreVal(Cells[vRS].V, V);
  SetStr(V, SubSep); StoreVal(Cells[vSUBSEP].V, V);
  SetStr(V, ConvFmt); StoreVal(Cells[vCONVFMT].V, V);
  SetStr(V, OFmt); StoreVal(Cells[vOFMT].V, V);
  SetNum(V, 0.0);
  StoreVal(Cells[vRSTART].V, V);
  SetNum(V, -1.0);
  StoreVal(Cells[vRLENGTH].V, V);
  SPTop := 256;
  Seed := 0;
  PrevSeed := 0;
  SKind[0] := 3;
  SFd[0] := -1;
End;

Procedure InitEnv;
Var K, E, I : LongInt; S, Nm : String; V : TVal; P : LongInt; Ar : LongInt;
Begin
  Cells[vENVIRON].Kind := 2;
  Cells[vENVIRON].Arr := ArrAlloc;
  Ar := Cells[vENVIRON].Arr;
  For K := 0 To SysEnvCount - 1 Do
  Begin
    S := SysEnvStr(K);
    I := Pos('=', S);
    If I > 0 Then
    Begin
      Nm := Copy(S, 1, I - 1);
      E := ArrGet(Ar, LongInt(@Nm[1]), Length(Nm));
      S := Copy(S, I + 1, 255);
      P := ANew(Length(S));
      For I := 1 To Length(S) Do Mem[0:P + I - 1] := Ord(S[I]);
      SetInput(V, P, Length(S));
      StoreVal(EVal[E], V);
    End;
  End;
End;

Var
  FpuCw : Word;
  I, J, NArg, FirstFile : LongInt;
  A, V1 : String;
  HaveProg, EndOpt : Boolean;
  ProgText : String;
  E, R, Ar : LongInt;
  Vv : TVal;
  Pt : LongInt;
  Matched : Boolean;
  VOpt : Array[0..31] Of String;
  NVOpt : LongInt;

Begin
  asm
    mov ax, 0037Fh
    mov FpuCw, ax
    fldcw FpuCw
  end;
  ATop := 0;
  NNode := 0;
  NRule := 0;
  NFn := 0;
  NArr := 0;
  NParams := 0;
  ReN := 0;
  ReSetN := 0;
  InitVars;
  NArg := SysArgCount;
  HaveProg := False;
  EndOpt := False;
  NVOpt := 0;
  I := 1;
  While I < NArg Do
  Begin
    A := SysArgStr(I);
    If (Not EndOpt) And (Length(A) > 1) And (A[1] = '-') Then
    Begin
      If A = '--' Then
      Begin
        EndOpt := True;
        Inc(I);
        Break;
      End
      Else If (A = '--version') Or (A = '-version') Or (A = '-V') Then
      Begin
        SysPut(1, 'awk (KERNEL32) 1.0' + #10);
        SysExit(0);
      End
      Else If (A = '--help') Or (A = '-h') Then
      Begin
        SysPut(2, PS(UsageW[SysLang]) +
          'awk [-F fs] [-v var=val] (-f prog | ''prog'') [fichier ...]' + #10);
        SysExit(0);
      End
      Else If Copy(A, 1, 2) = '-F' Then
      Begin
        If Length(A) > 2 Then V1 := Copy(A, 3, 255)
        Else
        Begin
          Inc(I);
          If I >= NArg Then Die('-F : argument manquant');
          V1 := SysArgStr(I);
        End;
        If V1 = 't' Then V1 := #9;
        If V1 = '\t' Then V1 := #9;
        FSStr := V1;
        SetStr(Vv, V1);
        StoreVal(Cells[vFS].V, Vv);
      End
      Else If Copy(A, 1, 2) = '-v' Then
      Begin
        If Length(A) > 2 Then V1 := Copy(A, 3, 255)
        Else
        Begin
          Inc(I);
          If I >= NArg Then Die('-v : argument manquant');
          V1 := SysArgStr(I);
        End;
        If NVOpt < 32 Then
        Begin
          VOpt[NVOpt] := V1;
          Inc(NVOpt);
        End;
      End
      Else If Copy(A, 1, 2) = '-f' Then
      Begin
        If Length(A) > 2 Then V1 := Copy(A, 3, 255)
        Else
        Begin
          Inc(I);
          If I >= NArg Then Die('-f : argument manquant');
          V1 := SysArgStr(I);
        End;
        AddSrcFile(V1);
        HaveProg := True;
      End
      Else If A = '-' Then Break
      Else If (A = '-d') Or (A = '-S') Or (A = '--posix') Or
              (A = '--traditional') Or (A = '-P') Or (A = '--re-interval') Then
      Else
      Begin
        SysPut(2, 'awk: option inconnue ' + A + #10);
        SysExit(2);
      End;
      Inc(I);
    End
    Else Break;
  End;
  If Not HaveProg Then
  Begin
    If I >= NArg Then
    Begin
      SysPut(2, PS(UsageW[SysLang]) +
        'awk [-F fs] [-v var=val] (-f prog | ''prog'') [fichier ...]' + #10);
      SysExit(2);
    End;
    AddSrcText(SysArgStr(I));
    Inc(I);
  End;
  { ARGV }
  Cells[vARGV].Kind := 2;
  Cells[vARGV].Arr := ArrAlloc;
  Ar := Cells[vARGV].Arr;
  ArgC := 1;
  A := '0';
  E := ArrGet(Ar, LongInt(@A[1]), 1);
  SetStr(Vv, 'awk');
  StoreVal(EVal[E], Vv);
  While I < NArg Do
  Begin
    A := NumS(ArgC);
    E := ArrGet(Ar, LongInt(@A[1]), Length(A));
    V1 := SysArgStr(I);
    Pt := ANew(Length(V1));
    For J := 1 To Length(V1) Do Mem[0:Pt + J - 1] := Ord(V1[J]);
    SetInput(Vv, Pt, Length(V1));
    StoreVal(EVal[E], Vv);
    Inc(ArgC);
    Inc(I);
  End;
  SetNum(Vv, ArgC);
  Cells[vARGC].Kind := 1;
  StoreVal(Cells[vARGC].V, Vv);
  InitEnv;
  Lex;
  ParseProgram;
  For I := 1 To NNode Do
    If Nodes[I].Op = nRe Then
    Begin
      Nodes[I].A := ReCompile(Nodes[I].S, True, False);
      If Nodes[I].A < 0 Then
        Die('expression reguliere : ' + ReErr + ' dans /' + Nodes[I].S + '/');
    End;
  DynBase := ReN;
  DynSetBase := ReSetN;
  For I := 0 To NVOpt - 1 Do ProcAssign(VOpt[I]);
  ArgIdx := 1;
  { BEGIN }
  Flow := 0;
  RunRules(0);
  If Flow <> 2 Then
  Begin
    R := 0;
    For I := 1 To NRule Do
      If (RuleK[I] = 2) Or (RuleK[I] = 3) Or (RuleK[I] = 1) Then R := 1;
    If R = 1 Then
    Begin
      While (Flow = 0) And NextMain Do
      Begin
        ATop := 0;
        For I := 1 To NRule Do
        Begin
          If (RuleK[I] <> 2) And (RuleK[I] <> 3) Then Continue;
          Matched := False;
          If RuleK[I] = 2 Then
          Begin
            If RuleP1[I] = 0 Then Matched := True
            Else
            Begin
              Ev(RuleP1[I]);
              Matched := Truth(RV);
            End;
          End
          Else
          Begin
            If Not RuleOn[I] Then
            Begin
              Ev(RuleP1[I]);
              If Truth(RV) Then
              Begin
                Matched := True;
                RuleOn[I] := True;
              End;
            End
            Else Matched := True;
            If Matched And RuleOn[I] Then
            Begin
              Ev(RuleP2[I]);
              If Truth(RV) Then RuleOn[I] := False;
            End;
          End;
          If Matched Then
          Begin
            If RuleAct[I] = 0 Then
            Begin
              GetField(0);
              WriteFd(1, RV.P, RV.L);
              WriteFd(1, LongInt(@ORSStr[1]), Length(ORSStr));
            End
            Else Exec(RuleAct[I]);
          End;
          If Flow = 1 Then
          Begin
            Flow := 0;
            Break;
          End;
          If Flow = 6 Then
          Begin
            Flow := 0;
            SkipFile;
            Break;
          End;
          If Flow = 2 Then Break;
        End;
      End;
    End;
  End;
  { END : meme apres exit }
  Flow := 0;
  InEnd := True;
  RunRules(1);
  CloseAll;
  FlushOut;
  If ExitCode = 0 Then ExitCode := Status;
  SysExit(ExitCode);
End.
