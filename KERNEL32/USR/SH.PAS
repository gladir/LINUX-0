{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2026
  @website(https://www.gladir.com/linux-0)
  @abstract(Target: LPC -3X)
  @description: /bin/sh de KERNEL32 : interpreteur de commandes de type
   POSIX en Pascal. Variables, export, $? $$ $! $# $@ $* $0 $1.., guillemets
   ' " \, expansions (*, ?, [..], ~, $(..), `..`, $((..)), formes avec
   accolades pour les valeurs par defaut, la longueur et les suffixes),
     redirections (< > >> 2> 2>&1 <<EOF <<-EOF <>),
   tubes, listes ; & && ||, travaux (jobs fg bg, Ctrl-Z), if/elif/else,
   while, until, for, case, fonctions, source, alias, trap, et les commandes
   internes cd pwd echo export unset exit read test [ set shift wait trap
   type umask exec alias unalias history eval . source : true false break
   continue return local jobs fg bg kill getopts command builtin readonly
   times ulimit(sans effet).
   Editeur de ligne avec historique (fleches, Debut, Fin, Suppr, ^A ^E ^K ^U
   ^W ^L, Tab) quand l'entree est un terminal. Scripts (#!/bin/sh), -c
   commande, /etc/profile et ~/.profile pour un interpreteur de connexion
   (argv[0] commencant par -). Invites : '# ' pour root et '$ ' sinon
   (variable PS1), '> ' pour la suite (PS2). Messages en 5 langues selon
   LANGUAGE (FR par defaut, EN, GR, SP, IT).
   Options : -c cmd, -s, -i, -l, -e, -x, -u, -n, -v ; "-" et "--".
   Limites : mots de 255 caracteres, 2000 arguments par commande.
}

Program Sh;

{$I-}

Const
  MAXVARS = 1500;
  MAXFUNCS = 100;
  MAXALIAS = 64;
  MAXJOBS = 32;
  MAXHIST = 100;
  MAXPOS = 200;
  MAXARGS = 2000;
  MAXSUBS = 4000;
  MAXTRAP = 40;
  MAXREDIR = 16;
  { jetons }
  tEOF = 0; tNL = 1; tWord = 2; tAndIf = 3; tOrIf = 4; tSemi = 5;
  tDSemi = 6; tAmp = 7; tPipe = 8; tLParen = 9; tRParen = 10; tLess = 11;
  tGreat = 12; tDGreat = 13; tDLess = 14; tDLessDash = 15; tLessAnd = 16;
  tGreatAnd = 17; tLessGreat = 18; tClobber = 19; tIONum = 20;
  tHereStr = 21; tAndGreat = 22; tAndDGreat = 23; tSemiAmp = 24;
  tDSemiAmp = 25;
  { noeuds }
  nSimple = 1; nPipe = 2; nAndOr = 3; nList = 4; nIf = 5; nWhile = 6;
  nUntil = 7; nFor = 8; nCase = 9; nBrace = 10; nSubshell = 11; nFunc = 12;
  nCaseItem = 13; nDBr = 14; nArith = 15; nArithFor = 16; nSelect = 17;
  { etats des travaux }
  jFree = 0; jRunning = 1; jStopped = 2; jDone = 3;

Type
  PStr = ^String;
  PWd = ^TWd;
  TWd = Record
    S : String;
    IsAssign : Boolean;
    Next : PWd;
  End;
  PRedir = ^TRedir;
  TRedir = Record
    Fd : LongInt;          { descripteur concerne (-1 : defaut) }
    Op : LongInt;          { tLess, tGreat, ... }
    Target : String;       { mot brut ; delimiteur pour << }
    Doc : LongInt;         { adresse du texte du document ici (0 : aucun) }
    DocLen : LongInt;
    DocExp : Boolean;      { le document est developpe }
    Next : PRedir;
  End;
  PNode = ^TNode;
  TNode = Record
    Kind : LongInt;
    Next : PNode;
    Op : LongInt;          { lien vers Next : tAndIf, tOrIf ; liste : tAmp }
    Neg, Bg : Boolean;
    A, B, C : PNode;
    Words : PWd;
    Redirs : PRedir;
    Name : String[63];
    Line : LongInt;
  End;
  TArgs = Record
    N : LongInt;
    It : Array[0..MAXARGS - 1] Of PStr;
  End;
  PArgs = ^TArgs;
  TVar = Record
    Name : String[63];
    Val : String;
    Exp, RO, Used : Boolean;
    Kind : Byte;           { 0 scalaire, 1 tableau indexe, 2 associatif }
    IntAttr : Boolean;     { declare -i }
    CaseAttr : Byte;       { 1 -l minuscules, 2 -u majuscules }
    Ref : Boolean;         { declare -n : Val = nom de la variable visee }
  End;
  TPollFd = Record
    Fd : LongInt;
    Events, REvents : Word;
  End;
  TJob = Record
    State : LongInt;
    Pgid : LongInt;
    NProc, NDone : LongInt;
    Pids : Array[0..15] Of LongInt;
    Dones : Array[0..15] Of Boolean;
    Status : LongInt;
    Cmd : String[100];
    Notified : Boolean;
    PStat : Array[0..15] Of LongInt;
  End;
  TIn = Record
    Fd : LongInt;          { -1 : source en memoire }
    Buf : LongInt;         { tampon de lecture ou texte }
    Cap : LongInt;
    Len, Cur : LongInt;
    Eof : Boolean;
    Pk, Pk2 : LongInt;     { caracteres en attente, -2 aucun }
    Inter : Boolean;       { lecture avec l'editeur de ligne }
    LineNo : LongInt;
    Name : String[80];
  End;

Var
  Vars : Array[0..MAXVARS - 1] Of TVar;
  Funcs : Array[0..MAXFUNCS - 1] Of Record
    Name : String[63];
    Body : PNode;
    Used : Boolean;
  End;
  Aliases : Array[0..MAXALIAS - 1] Of Record
    Name : String[31];
    Val : String[120];
    Used : Boolean;
  End;
  Jobs : Array[0..MAXJOBS - 1] Of TJob;
  Hist : Array[0..MAXHIST - 1] Of PStr;
  NHist : LongInt;
  PosArr : LongInt;                    { adresse du tableau de PStr (1..) }
  NPos : LongInt;
  Arg0 : String;
  Subs : Array[0..MAXSUBS - 1] Of LongInt;  { corps des $(..) : adresses }
  NSubs : LongInt;
  TrapCmd : Array[0..MAXTRAP] Of PStr;
  TrapPend : Array[0..MAXTRAP] Of LongInt;
  TrapAny : LongInt;
  CurIn : TIn;
  { etat de l'analyse lexicale }
  Tok : LongInt;
  TokS : String;
  TokQuoted : Boolean;
  TokNum : LongInt;
  HereN : LongInt;
  HereR : Array[0..MAXREDIR] Of PRedir;
  HereTab : Array[0..MAXREDIR] Of Boolean;    { <<- (tabulations retirees) }
  NodeHead : LongInt;                   { chaine de blocs a liberer }
  Pinned : Boolean;
  SynErr : Boolean;
  PromptMode : LongInt;                 { 1 PS1, 2 PS2 }
  { options }
  OptE, OptX, OptU, OptN, OptV, OptI, OptL, OptC, OptS : Boolean;
  Interactive : Boolean;
  BashMode : Boolean;                 { extensions de bash }
  OptPipe, OptNoGlob, OptNoClob, OptAllExp : Boolean;
  ExtGlob, NullGlob, DotGlob, NoCaseMatch, FailGlob, StarStar : Boolean;
  AoShort, NoErrChk, InDebug, InErrTrap, DbParse : Boolean;
  FnDepth : LongInt;
  StartTime : LongInt;
  CurLine : LongInt;
  ProcFds : Array[0..15] Of LongInt;  { <(..) >(..) : descripteurs a fermer }
  NProcFds : LongInt;
  JobCtl : Boolean;
  { etat de l'execution }
  LastStatus : LongInt;
  LastBg : LongInt;
  SubstStatus : LongInt;
  ShellPid : LongInt;
  ShellPgrp : LongInt;
  BreakN, ContN, RetFlag : LongInt;
  InFunc : LongInt;
  LoopDepth : LongInt;
  IntFlag : LongInt;
  ExitCode : LongInt;
  Uid : LongInt;
  TtyFd : LongInt;
  SavedTerm : TSysTermios;
  HaveTerm : Boolean;
  Lang : LongInt;
  OptInd : LongInt;
  OptPos : LongInt;
  SubDepth : LongInt;
  TmpCnt : LongInt;
  LocalSP : LongInt;
  LocalName : Array[0..255] Of String[63];
  LocalOld : Array[0..255] Of PStr;
  LocalKd : Array[0..255] Of Byte;
  LocalFrame : Array[0..31] Of LongInt;
  LocalFP : LongInt;

Procedure Fatal(Const S : String); Forward;

{ ---------- memoire ---------- }

Function Alloc(N : LongInt) : LongInt;
Var P : LongInt;
Begin
  P := HeapAlloc(1, 8, N);
  If P = 0 Then Fatal('out of memory');
  Alloc := P;
End;

{ bloc suivi : liberable en bloc (noeuds de l'arbre, documents ici) }
Function Track(N : LongInt) : LongInt;
Var P : LongInt;
Begin
  P := Alloc(N + 8);
  MemL[0:P] := NodeHead;
  NodeHead := P;
  Track := P + 8;
End;

Procedure FreeTracked(Head : LongInt);
Var P, Q : LongInt;
Begin
  P := Head;
  While P <> 0 Do
  Begin
    Q := MemL[0:P];
    HeapFree(1, 0, P);
    P := Q;
  End;
End;

Function NewNode(K : LongInt) : PNode;
Var P : PNode; A : LongInt;
Begin
  A := Track(SizeOf(TNode));
  P := PNode(A);
  P^.Kind := K;
  P^.Line := CurIn.LineNo;
  NewNode := P;
End;

Function MkStr(Const S : String) : PStr;
Var A : LongInt; P : PStr;
Begin
  A := Alloc(256);
  P := PStr(A);
  P^ := S;
  MkStr := P;
End;

Procedure FreeStr(P : PStr);
Begin
  If P <> Nil Then HeapFree(1, 0, LongInt(P));
End;

{ ---------- sortie ---------- }

Procedure Out(Fd : LongInt; Const S : String);
Begin
  If S <> '' Then SysPut(Fd, S);
End;

Procedure Err(Const S : String);
Begin
  SysPut(2, S + #10);
End;

Function IntStr(V : LongInt) : String;
Var S : String;
Begin
  Str(V, S);
  IntStr := S;
End;

Function StrInt(Const S : String; Var V : LongInt) : Boolean;
Var K : LongInt; Neg : Boolean;
Begin
  V := 0;
  K := 1;
  Neg := False;
  StrInt := False;
  While (K <= Length(S)) And ((S[K] = ' ') Or (S[K] = #9)) Do Inc(K);
  If (K <= Length(S)) And ((S[K] = '-') Or (S[K] = '+')) Then
  Begin
    Neg := S[K] = '-';
    Inc(K);
  End;
  If (K > Length(S)) Or (S[K] < '0') Or (S[K] > '9') Then Exit;
  While (K <= Length(S)) And (S[K] >= '0') And (S[K] <= '9') Do
  Begin
    V := V * 10 + Ord(S[K]) - 48;
    Inc(K);
  End;
  While (K <= Length(S)) And ((S[K] = ' ') Or (S[K] = #9)) Do Inc(K);
  If K <= Length(S) Then Exit;
  If Neg Then V := -V;
  StrInt := True;
End;

Function UpStr(Const S : String) : String;
Var R : String; K : LongInt;
Begin
  R := S;
  For K := 1 To Length(R) Do
    If (R[K] >= 'a') And (R[K] <= 'z') Then R[K] := Chr(Ord(R[K]) - 32);
  UpStr := R;
End;

Function LowStr(Const S : String) : String;
Var R : String; K : LongInt;
Begin
  R := S;
  For K := 1 To Length(R) Do
    If (R[K] >= 'A') And (R[K] <= 'Z') Then R[K] := Chr(Ord(R[K]) + 32);
  LowStr := R;
End;

{ ---------- messages (FR, EN, GR, SP, IT) ---------- }

Const
  mNotFound = 1; mSyntax = 2; mBadSub = 3; mNoFile = 4; mUsage = 5;
  mNotExec = 6; mCantFork = 7; mStopped = 8; mDone = 9; mNoJob = 10;
  mTooMany = 11; mReadonly = 12; mUnbound = 13; mBadNum = 14; mNotId = 15;
  mBadOpt = 16; mUnexpEof = 17; mUnexpTok = 18; mNoHome = 19; mCantOpen = 20;
  mNoSuchVar = 21; mNoTrap = 22; mRunning = 23; mNotBuiltin = 24;
  mDivZero = 25; mHelpUsage = 26;
  M : Array[1..26, 1..5] Of PChar = (
    ('commande introuvable', 'command not found', 'Befehl nicht gefunden',
     'orden no encontrada', 'comando non trovato'),
    ('erreur de syntaxe', 'syntax error', 'Syntaxfehler', 'error de sintaxis',
     'errore di sintassi'),
    ('mauvaise substitution', 'bad substitution', 'Falsche Ersetzung',
     'sustitucion incorrecta', 'sostituzione errata'),
    ('fichier introuvable', 'No such file or directory',
     'Datei nicht gefunden', 'no existe el fichero', 'file non trovato'),
    ('Usage', 'Usage', 'Aufruf', 'Uso', 'Uso'),
    ('permission refusee', 'Permission denied', 'Zugriff verweigert',
     'permiso denegado', 'permesso negato'),
    ('impossible de creer un processus', 'cannot fork',
     'Prozess kann nicht erzeugt werden', 'no se puede crear el proceso',
     'impossibile creare il processo'),
    ('Arrete', 'Stopped', 'Angehalten', 'Detenido', 'Fermato'),
    ('Termine', 'Done', 'Beendet', 'Hecho', 'Terminato'),
    ('travail inexistant', 'no such job', 'Job nicht gefunden',
     'no existe el trabajo', 'lavoro inesistente'),
    ('trop d''arguments', 'too many arguments', 'zu viele Argumente',
     'demasiados argumentos', 'troppi argomenti'),
    ('variable en lecture seule', 'readonly variable',
     'Variable ist schreibgeschuetzt', 'variable de solo lectura',
     'variabile di sola lettura'),
    ('variable non definie', 'parameter not set', 'Parameter nicht gesetzt',
     'parametro no definido', 'parametro non impostato'),
    ('nombre attendu', 'numeric argument required', 'Zahl erwartet',
     'se requiere un numero', 'numero richiesto'),
    ('identificateur invalide', 'not a valid identifier',
     'Ungueltiger Bezeichner', 'identificador no valido',
     'identificatore non valido'),
    ('option invalide', 'invalid option', 'Ungueltige Option',
     'opcion no valida', 'opzione non valida'),
    ('fin de fichier inattendue', 'unexpected end of file',
     'Unerwartetes Dateiende', 'fin de fichero inesperado',
     'fine del file inattesa'),
    ('element inattendu', 'unexpected token', 'Unerwartetes Element',
     'elemento inesperado', 'elemento inatteso'),
    ('HOME non defini', 'HOME not set', 'HOME nicht gesetzt',
     'HOME no definido', 'HOME non impostato'),
    ('impossible d''ouvrir', 'cannot open', 'kann nicht geoeffnet werden',
     'no se puede abrir', 'impossibile aprire'),
    ('variable inexistante', 'no such variable', 'Variable nicht gefunden',
     'no existe la variable', 'variabile inesistente'),
    ('signal inconnu', 'unknown signal', 'Unbekanntes Signal',
     'senal desconocida', 'segnale sconosciuto'),
    ('En cours', 'Running', 'Laufend', 'En ejecucion', 'In esecuzione'),
    ('n''est pas une commande interne', 'not a shell builtin',
     'kein eingebauter Befehl', 'no es una orden interna',
     'non e'' un comando interno'),
    ('division par zero', 'division by zero', 'Division durch Null',
     'division por cero', 'divisione per zero'),
    ('Usage', 'Usage', 'Aufruf', 'Uso', 'Uso'));

Function Msg(Id : LongInt) : String;
Var P : PChar; X : String;
Begin
  P := M[Id, Lang];
  X := '';
  While P^ <> #0 Do
  Begin
    X := X + P^;
    Inc(P);
  End;
  Msg := X;
End;

Procedure ShErr(Const S : String);
Begin
  If BashMode Then Err('bash: ' + S) Else Err('sh: ' + S);
End;

Procedure CleanExit(Code : LongInt); Forward;

Procedure Fatal(Const S : String);
Begin
  ShErr(S);
  SysExit(2);
End;

{ ---------- variables ---------- }

Var AnyRef : Boolean;

Function FindVar(Const N : String) : LongInt;
Var I : LongInt;
Begin
  For I := 0 To MAXVARS - 1 Do
    If Vars[I].Used And (Vars[I].Name = N) Then
    Begin
      FindVar := I;
      Exit;
    End;
  FindVar := -1;
End;

{ suit les variables nameref : nom effectif }
Function ResolveRef(Const N : String) : String;
Var I, Dp : LongInt; R : String;
Begin
  ResolveRef := N;
  If Not AnyRef Then Exit;
  R := N;
  For Dp := 1 To 8 Do
  Begin
    I := FindVar(R);
    If (I < 0) Or Not Vars[I].Ref Then Break;
    R := Vars[I].Val;
  End;
  ResolveRef := R;
End;

{ vrai si N est un tableau (indexe ou associatif) }
Function ArrKind(Const N0 : String) : LongInt;
Var I : LongInt; N : String;
Begin
  ArrKind := 0;
  N := ResolveRef(N0);
  I := FindVar(N);
  If I >= 0 Then ArrKind := Vars[I].Kind;
End;

Function IsAssocName(Const N : String) : Boolean;
Begin
  IsAssocName := ArrKind(N) = 2;
End;

Function ValidName(Const S : String) : Boolean;
Var K : LongInt;
Begin
  ValidName := False;
  If S = '' Then Exit;
  If Not (UpCase(S[1]) In ['A'..'Z', '_']) Then Exit;
  For K := 2 To Length(S) Do
    If Not (UpCase(S[K]) In ['A'..'Z', '_', '0'..'9']) Then Exit;
  ValidName := True;
End;

Function PosGet(I : LongInt) : String;
Begin
  If (I < 1) Or (I > NPos) Then PosGet := ''
  Else PosGet := PStr(MemL[0:PosArr + I * 4])^;
End;

Procedure PosClear;
Var I : LongInt;
Begin
  For I := 1 To NPos Do FreeStr(PStr(MemL[0:PosArr + I * 4]));
  NPos := 0;
End;

Procedure PosSet(Var A : TArgs; From : LongInt);
Var I : LongInt;
Begin
  PosArr := Alloc((MAXPOS + 2) * 4);
  NPos := 0;
  For I := From To A.N - 1 Do
    If NPos < MAXPOS Then
    Begin
      Inc(NPos);
      MemL[0:PosArr + NPos * 4] := LongInt(MkStr(A.It[I]^));
    End;
End;

Function GetVarRaw(Const N : String; Var V : String) : Boolean;
Var I : LongInt;
Begin
  I := FindVar(N);
  If I < 0 Then
  Begin
    V := '';
    GetVarRaw := False;
  End
  Else
  Begin
    V := Vars[I].Val;
    GetVarRaw := True;
  End;
End;

Function VarSet(Const N : String) : Boolean;
Var I : LongInt;
Begin
  I := FindVar(N);
  VarSet := I >= 0;
End;

{ valeur d'une variable ou d'un parametre special ; Faux si non definie }
Function GetVar(Const N0 : String; Var V : String) : Boolean;
Var K, X : LongInt; S, N : String;
Begin
  GetVar := True;
  V := '';
  N := N0;
  If AnyRef Then N := ResolveRef(N0);
  If N = '' Then Exit;
  Case N[1] Of
    '0'..'9' :
      Begin
        If StrInt(N, X) Then
        Begin
          If X = 0 Then V := Arg0
          Else
          Begin
            If X > NPos Then GetVar := False;
            V := PosGet(X);
          End;
          Exit;
        End;
      End;
    '?' : If Length(N) = 1 Then Begin V := IntStr(LastStatus); Exit; End;
    '$' : If Length(N) = 1 Then Begin V := IntStr(ShellPid); Exit; End;
    '!' : If Length(N) = 1 Then
          Begin
            If LastBg = 0 Then V := '' Else V := IntStr(LastBg);
            Exit;
          End;
    '#' : If Length(N) = 1 Then Begin V := IntStr(NPos); Exit; End;
    '-' : If Length(N) = 1 Then
          Begin
            S := '';
            If OptE Then S := S + 'e';
            If OptI Then S := S + 'i';
            If OptU Then S := S + 'u';
            If OptX Then S := S + 'x';
            V := S;
            Exit;
          End;
    '@', '*' :
      If Length(N) = 1 Then
      Begin
        S := '';
        For K := 1 To NPos Do
        Begin
          If K > 1 Then S := S + ' ';
          S := S + PosGet(K);
        End;
        V := S;
        Exit;
      End;
  End;
  If N = 'LINENO' Then
  Begin
    If CurLine > 0 Then V := IntStr(CurLine) Else V := IntStr(CurIn.LineNo);
    Exit;
  End;
  If N = 'RANDOM' Then
  Begin
    TmpCnt := (TmpCnt * 1103515245 + 12345 + SysTime) And $7FFFFFFF;
    V := IntStr((TmpCnt Shr 8) And $7FFF);
    Exit;
  End;
  If BashMode Then
  Begin
    If N = 'BASHPID' Then
    Begin
      V := IntStr(SysGetPid);
      Exit;
    End;
    If N = 'SECONDS' Then
    Begin
      V := IntStr(SysTime - StartTime);
      Exit;
    End;
    If N = 'EPOCHSECONDS' Then
    Begin
      V := IntStr(SysTime);
      Exit;
    End;
    If N = 'EUID' Then
    Begin
      V := IntStr(SysGetEUid);
      Exit;
    End;
  End;
  If N = 'PPID' Then
  Begin
    V := IntStr(SysGetPPid);
    Exit;
  End;
  If N = 'UID' Then
  Begin
    V := IntStr(Uid);
    Exit;
  End;
  K := FindVar(N);
  If K >= 0 Then
    If Vars[K].Kind > 0 Then K := FindVar(N + '[0]');
  If K < 0 Then
  Begin
    GetVar := False;
    Exit;
  End;
  V := Vars[K].Val;
End;

Function VarValue(Const N : String) : String;
Var V : String;
Begin
  GetVar(N, V);
  VarValue := V;
End;

Function ArithEval(Const S : String) : LongInt; Forward;

Function SetVar(Const N0, V : String) : Boolean;
Var I : LongInt; W, N : String;
Begin
  SetVar := True;
  N := N0;
  If AnyRef Then N := ResolveRef(N0);
  I := FindVar(N);
  If I >= 0 Then
  Begin
    If Vars[I].RO Then
    Begin
      ShErr(N + ': ' + Msg(mReadonly));
      SetVar := False;
      Exit;
    End;
    If Vars[I].Kind > 0 Then
    Begin
      SetVar := SetVar(N + '[0]', V);
      Exit;
    End;
    W := V;
    If Vars[I].IntAttr Then W := IntStr(ArithEval(V));
    If Vars[I].CaseAttr = 1 Then W := LowStr(W)
    Else If Vars[I].CaseAttr = 2 Then W := UpStr(W);
    Vars[I].Val := W;
    Exit;
  End;
  For I := 0 To MAXVARS - 1 Do
    If Not Vars[I].Used Then
    Begin
      Vars[I].Used := True;
      Vars[I].Name := N;
      Vars[I].Val := V;
      Vars[I].Exp := False;
      Vars[I].RO := False;
      Vars[I].Kind := 0;
      Vars[I].IntAttr := False;
      Vars[I].CaseAttr := 0;
      Vars[I].Ref := False;
      Exit;
    End;
  ShErr(Msg(mTooMany));
  SetVar := False;
End;

Procedure ExportVar(Const N : String; On : Boolean);
Var I : LongInt;
Begin
  I := FindVar(N);
  If I < 0 Then
  Begin
    If Not SetVar(N, '') Then Exit;
    I := FindVar(N);
    If I < 0 Then Exit;
  End;
  Vars[I].Exp := On;
End;

Procedure ArrClear(Const N : String); Forward;

Procedure UnsetVar(Const N : String);
Var I : LongInt;
Begin
  I := FindVar(N);
  If I < 0 Then Exit;
  If Vars[I].RO Then
  Begin
    ShErr(N + ': ' + Msg(mReadonly));
    Exit;
  End;
  If Vars[I].Kind > 0 Then ArrClear(N);
  Vars[I].Used := False;
End;

{ environnement pour execve : tableau de pointeurs vers des ASCIIZ }
Function BuildEnv : LongInt;
Var I, N, A : LongInt;
Begin
  N := 0;
  For I := 0 To MAXVARS - 1 Do
    If Vars[I].Used And Vars[I].Exp Then Inc(N);
  A := Alloc((N + 1) * 4);
  N := 0;
  For I := 0 To MAXVARS - 1 Do
    If Vars[I].Used And Vars[I].Exp Then
    Begin
      MemL[0:A + N * 4] := SysNewZ(Vars[I].Name + '=' + Vars[I].Val);
      Inc(N);
    End;
  MemL[0:A + N * 4] := 0;
  BuildEnv := A;
End;

Procedure ArgsInit(Var A : TArgs);
Begin
  A.N := 0;
End;

Procedure ArgsAdd(Var A : TArgs; Const S : String);
Begin
  If A.N >= MAXARGS Then
  Begin
    ShErr(Msg(mTooMany));
    Exit;
  End;
  A.It[A.N] := MkStr(S);
  Inc(A.N);
End;

Procedure ArgsFree(Var A : TArgs);
Var I : LongInt;
Begin
  For I := 0 To A.N - 1 Do FreeStr(A.It[I]);
  A.N := 0;
End;

{ tri alphabetique des elements a partir de From }
Procedure ArgsSort(Var A : TArgs; From : LongInt);
Var I, J : LongInt; T : PStr;
Begin
  For I := From + 1 To A.N - 1 Do
  Begin
    T := A.It[I];
    J := I - 1;
    While (J >= From) And (A.It[J]^ > T^) Do
    Begin
      A.It[J + 1] := A.It[J];
      Dec(J);
    End;
    A.It[J + 1] := T;
  End;
End;

{ ----- tableaux : cles, en-tete (Kind), liste ordonnee ----- }

Procedure ArrDeclare(Const N0 : String; Kind : LongInt);
Var I : LongInt; N : String;
Begin
  N := ResolveRef(N0);
  I := FindVar(N);
  If I < 0 Then
  Begin
    If Not SetVar(N, '') Then Exit;
    I := FindVar(N);
    If I < 0 Then Exit;
  End;
  If Vars[I].Kind = 0 Then
  Begin
    { le scalaire existant devient l'element 0 }
    If (Vars[I].Val <> '') And (Kind = 1) Then
      SetVar(N + '[0]', Vars[I].Val);
    Vars[I].Val := '';
  End;
  Vars[I].Kind := Kind;
End;

Procedure ArrClear(Const N0 : String);
Var I, L : LongInt; N : String;
Begin
  N := ResolveRef(N0);
  L := Length(N) + 1;
  For I := 0 To MAXVARS - 1 Do
    If Vars[I].Used And (Copy(Vars[I].Name, 1, L) = N + '[') Then
      Vars[I].Used := False;
End;

{ cles de N : Keys.It = chaines ; tableau indexe : ordre numerique }
Procedure ArrKeys(Const N0 : String; Var Keys : TArgs);
Var I, L, J, X, Y : LongInt; K : String; Tmp : PStr; Num : Boolean; N : String;
Begin
  N := ResolveRef(N0);
  ArgsInit(Keys);
  L := Length(N) + 1;
  Num := ArrKind(N) <> 2;
  For I := 0 To MAXVARS - 1 Do
    If Vars[I].Used And (Copy(Vars[I].Name, 1, L) = N + '[') Then
    Begin
      K := Copy(Vars[I].Name, L + 1, Length(Vars[I].Name) - L - 1);
      ArgsAdd(Keys, K);
    End;
  If Num Then
    For I := 1 To Keys.N - 1 Do
    Begin
      J := I;
      While J > 0 Do
      Begin
        If Not StrInt(Keys.It[J - 1]^, X) Then X := 0;
        If Not StrInt(Keys.It[J]^, Y) Then Y := 0;
        If X <= Y Then Break;
        Tmp := Keys.It[J - 1];
        Keys.It[J - 1] := Keys.It[J];
        Keys.It[J] := Tmp;
        Dec(J);
      End;
    End;
End;

Function ArrCount(Const N : String) : LongInt;
Var K : TArgs; C : LongInt;
Begin
  ArrKeys(N, K);
  C := K.N;
  ArgsFree(K);
  ArrCount := C;
End;

Function ArrNextIdx(Const N : String) : LongInt;
Var K : TArgs; X, M : LongInt;
Begin
  ArrKeys(N, K);
  M := -1;
  If K.N > 0 Then
    If StrInt(K.It[K.N - 1]^, X) Then M := X;
  ArgsFree(K);
  ArrNextIdx := M + 1;
End;


{ ---------- entree : fichiers, tampons, editeur de ligne ---------- }

Function ReadLineEd(Const Prompt : String; Var Line : String) : Boolean;
Forward;
Function PromptText(Mode : LongInt) : String; Forward;
Procedure DoTraps; Forward;
Procedure ReapJobs(Report : Boolean); Forward;

Procedure InOpenFd(Var I : TIn; Fd : LongInt; Size : LongInt);
Begin
  I.Fd := Fd;
  I.Cap := Size;
  I.Buf := Alloc(Size + 16);
  I.Len := 0;
  I.Cur := 0;
  I.Eof := False;
  I.Pk := -2;
  I.Pk2 := -2;
  I.Inter := False;
  I.LineNo := 1;
  I.Name := '';
End;

{ source en memoire : copie de S }
Procedure InOpenStr(Var I : TIn; Const S : String);
Var K : LongInt;
Begin
  I.Fd := -1;
  I.Cap := Length(S) + 2;
  I.Buf := Alloc(I.Cap + 16);
  For K := 1 To Length(S) Do Mem[0:I.Buf + K - 1] := Ord(S[K]);
  I.Len := Length(S);
  I.Cur := 0;
  I.Eof := False;
  I.Pk := -2;
  I.Pk2 := -2;
  I.Inter := False;
  I.LineNo := 1;
  I.Name := '';
End;

Procedure InOpenMem(Var I : TIn; Addr, Len : LongInt);
Begin
  I.Fd := -1;
  I.Cap := Len + 2;
  I.Buf := Alloc(Len + 16);
  LnxMove(Addr, I.Buf, Len);
  I.Len := Len;
  I.Cur := 0;
  I.Eof := False;
  I.Pk := -2;
  I.Pk2 := -2;
  I.Inter := False;
  I.LineNo := 1;
  I.Name := '';
End;

Procedure InClose(Var I : TIn);
Begin
  If I.Buf <> 0 Then HeapFree(1, 0, I.Buf);
  I.Buf := 0;
  If I.Fd > 2 Then SysClose(I.Fd);
  I.Fd := -1;
End;

{ remplit le tampon ; Faux a la fin }
Function InFill : Boolean;
Var N, C : LongInt; L : String;
Begin
  InFill := False;
  If CurIn.Eof Then Exit;
  If CurIn.Fd < 0 Then
  Begin
    CurIn.Eof := True;
    Exit;
  End;
  If CurIn.Inter Then
  Begin
    DoTraps;
    ReapJobs(True);
    If Not ReadLineEd(PromptText(PromptMode), L) Then
    Begin
      CurIn.Eof := True;
      Exit;
    End;
    N := Length(L);
    For C := 1 To N Do Mem[0:CurIn.Buf + C - 1] := Ord(L[C]);
    Mem[0:CurIn.Buf + N] := 10;
    CurIn.Len := N + 1;
    CurIn.Cur := 0;
    InFill := True;
    Exit;
  End;
  Repeat
    N := LnxSys3(3, CurIn.Fd, CurIn.Buf, CurIn.Cap);
  Until N <> -4;
  If N <= 0 Then
  Begin
    CurIn.Eof := True;
    Exit;
  End;
  CurIn.Len := N;
  CurIn.Cur := 0;
  InFill := True;
End;

Function InGetC : LongInt;
Var C : LongInt;
Begin
  If CurIn.Pk <> -2 Then
  Begin
    C := CurIn.Pk;
    CurIn.Pk := CurIn.Pk2;
    CurIn.Pk2 := -2;
    If C = 10 Then Inc(CurIn.LineNo);
    InGetC := C;
    Exit;
  End;
  If CurIn.Cur >= CurIn.Len Then
    If Not InFill Then
    Begin
      InGetC := -1;
      Exit;
    End;
  C := Mem[0:CurIn.Buf + CurIn.Cur];
  Inc(CurIn.Cur);
  If C = 10 Then
  Begin
    Inc(CurIn.LineNo);
    PromptMode := 2;
  End;
  InGetC := C;
End;

Procedure InUnget(C : LongInt);
Begin
  CurIn.Pk2 := CurIn.Pk;
  CurIn.Pk := C;
  If C = 10 Then Dec(CurIn.LineNo);
End;

{ ---------- tampon dynamique (corps de $(..), documents ici) ---------- }

Var
  DbAddr, DbLen, DbCap : LongInt;

Procedure DbReset;
Begin
  DbLen := 0;
  If DbAddr = 0 Then
  Begin
    DbCap := 4096;
    DbAddr := Alloc(DbCap);
  End;
End;

Procedure DbAdd(C : LongInt);
Var P : LongInt;
Begin
  If DbLen + 2 >= DbCap Then
  Begin
    P := Alloc(DbCap * 2);
    LnxMove(DbAddr, P, DbLen);
    HeapFree(1, 0, DbAddr);
    DbAddr := P;
    DbCap := DbCap * 2;
  End;
  Mem[0:DbAddr + DbLen] := C;
  Inc(DbLen);
End;

{ copie du tampon dans un bloc suivi : [longueur (4)][octets][0] }
Function DbKeep(Tracked : Boolean) : LongInt;
Var P : LongInt;
Begin
  If Tracked Then P := Track(DbLen + 8) Else P := Alloc(DbLen + 8);
  MemL[0:P] := DbLen;
  LnxMove(DbAddr, P + 4, DbLen);
  Mem[0:P + 4 + DbLen] := 0;
  DbKeep := P;
End;

{ ---------- analyse lexicale ---------- }

Procedure SynError(Const S : String);
Begin
  If SynErr Then Exit;
  SynErr := True;
  If CurIn.Name <> '' Then
    ShErr(CurIn.Name + ': ' + IntStr(CurIn.LineNo) + ': ' + S)
  Else
    ShErr(S);
End;

Function IsNameCh(C : LongInt) : Boolean;
Begin
  IsNameCh := ((C >= 48) And (C <= 57)) Or ((C >= 65) And (C <= 90)) Or
              ((C >= 97) And (C <= 122)) Or (C = 95);
End;

Function IsMeta(C : LongInt) : Boolean;
Begin
  IsMeta := (C = 32) Or (C = 9) Or (C = 10) Or (C = 124) Or (C = 38) Or
            (C = 59) Or (C = 40) Or (C = 41) Or (C = 60) Or (C = 62);
End;

Procedure WAdd(Var W : String; C : LongInt);
Begin
  If Length(W) >= 254 Then
  Begin
    SynError('word too long');
    Exit;
  End;
  W := W + Chr(C);
End;

Function SubPlaceholder(Body : LongInt) : String;
Var S : String; N : LongInt;
Begin
  If NSubs >= MAXSUBS Then
  Begin
    SynError('too many substitutions');
    SubPlaceholder := '';
    Exit;
  End;
  N := NSubs;
  Subs[N] := Body;
  Inc(NSubs);
  S := '$(' + #1 + Chr(48 + N Div 1000) + Chr(48 + (N Div 100) Mod 10) +
       Chr(48 + (N Div 10) Mod 10) + Chr(48 + N Mod 10) + ')';
  SubPlaceholder := S;
End;

{ copie jusqu'a la quote fermante C (incluse) dans le tampon dynamique }
Procedure DbCopyQuoted(Q : LongInt);
Var C : LongInt;
Begin
  DbAdd(Q);
  While True Do
  Begin
    C := InGetC;
    If C < 0 Then
    Begin
      SynError(Msg(mUnexpEof));
      Exit;
    End;
    DbAdd(C);
    If C = Q Then Exit;
    If (Q = 34) And (C = 92) Then
    Begin
      C := InGetC;
      If C >= 0 Then DbAdd(C);
    End;
  End;
End;

{ corps de $( ... ) : lit jusqu'a la parenthese fermante correspondante }
Function ScanCmdSub : LongInt;
Var C, Depth : LongInt;
Begin
  DbReset;
  Depth := 1;
  While True Do
  Begin
    C := InGetC;
    If C < 0 Then
    Begin
      SynError(Msg(mUnexpEof));
      Break;
    End;
    If C = 40 Then Inc(Depth)
    Else If C = 41 Then
    Begin
      Dec(Depth);
      If Depth = 0 Then Break;
    End
    Else If (C = 39) Or (C = 34) Then
    Begin
      DbCopyQuoted(C);
      Continue;
    End
    Else If C = 92 Then
    Begin
      DbAdd(C);
      C := InGetC;
      If C < 0 Then Break;
    End;
    DbAdd(C);
  End;
  ScanCmdSub := DbKeep(True);
End;

{ corps de `...` }
Function ScanBackquote : LongInt;
Var C : LongInt;
Begin
  DbReset;
  While True Do
  Begin
    C := InGetC;
    If C < 0 Then
    Begin
      SynError(Msg(mUnexpEof));
      Break;
    End;
    If C = 96 Then Break;
    If C = 92 Then
    Begin
      C := InGetC;
      If C < 0 Then Break;
      If (C <> 36) And (C <> 96) And (C <> 92) Then DbAdd(92);
    End;
    DbAdd(C);
  End;
  ScanBackquote := DbKeep(True);
End;

Procedure ScanDollar(Var W : String); Forward;

{ apres un $ : ajoute au mot la construction complete }
Procedure ScanDollar(Var W : String);
Var C, C2, Depth : LongInt; Q : Boolean;
Begin
  C := InGetC;
  If BashMode And (C = 39) Then
  Begin
    { $'...' : chaine a echappements, copiee telle quelle jusqu'a la quote }
    WAdd(W, 36);
    WAdd(W, 39);
    While True Do
    Begin
      C := InGetC;
      If C < 0 Then
      Begin
        SynError(Msg(mUnexpEof));
        Exit;
      End;
      WAdd(W, C);
      If C = 92 Then
      Begin
        C := InGetC;
        If C >= 0 Then WAdd(W, C);
      End
      Else If C = 39 Then Break;
    End;
    Exit;
  End;
  If C = 40 Then
  Begin
    C2 := InGetC;
    If C2 = 40 Then
    Begin
      { arithmetique : $(( ... )) }
      WAdd(W, 36); WAdd(W, 40); WAdd(W, 40);
      Depth := 2;
      While True Do
      Begin
        C := InGetC;
        If C < 0 Then
        Begin
          SynError(Msg(mUnexpEof));
          Exit;
        End;
        If C = 36 Then
        Begin
          ScanDollar(W);
          Continue;
        End;
        If C = 96 Then
        Begin
          W := W + SubPlaceholder(ScanBackquote);
          Continue;
        End;
        If C = 40 Then Inc(Depth)
        Else If C = 41 Then Dec(Depth);
        WAdd(W, C);
        If Depth = 0 Then Break;
      End;
      Exit;
    End;
    InUnget(C2);
    W := W + SubPlaceholder(ScanCmdSub);
    Exit;
  End;
  If C = 123 Then
  Begin
    WAdd(W, 36); WAdd(W, 123);
    Depth := 1;
    While True Do
    Begin
      C := InGetC;
      If C < 0 Then
      Begin
        SynError(Msg(mUnexpEof));
        Exit;
      End;
      WAdd(W, C);
      If C = 123 Then Inc(Depth)
      Else If C = 125 Then
      Begin
        Dec(Depth);
        If Depth = 0 Then Break;
      End
      Else If C = 92 Then
      Begin
        C := InGetC;
        If C >= 0 Then WAdd(W, C);
      End
      Else If (C = 39) Or (C = 34) Then
      Begin
        Q := True;
        While Q Do
        Begin
          C2 := InGetC;
          If C2 < 0 Then
          Begin
            SynError(Msg(mUnexpEof));
            Exit;
          End;
          WAdd(W, C2);
          If C2 = C Then Q := False
          Else If (C = 34) And (C2 = 92) Then
          Begin
            C2 := InGetC;
            If C2 >= 0 Then WAdd(W, C2);
          End;
        End;
      End;
    End;
    Exit;
  End;
  If IsNameCh(C) And ((C < 48) Or (C > 57)) Then
  Begin
    WAdd(W, 36);
    While IsNameCh(C) Do
    Begin
      WAdd(W, C);
      C := InGetC;
    End;
    InUnget(C);
    Exit;
  End;
  If ((C >= 48) And (C <= 57)) Or (C = 64) Or (C = 42) Or (C = 35) Or
     (C = 63) Or (C = 45) Or (C = 36) Or (C = 33) Then
  Begin
    WAdd(W, 36);
    WAdd(W, C);
    Exit;
  End;
  WAdd(W, 36);
  InUnget(C);
End;

Procedure ReadHeredocs;
Var I, C, K, L : LongInt; Line : String; Dash, Done : Boolean;
    R : PRedir; Delim : String;
Begin
  For I := 0 To HereN - 1 Do
  Begin
    R := HereR[I];
    Dash := HereTab[I];
    Delim := R^.Target;
    DbReset;
    Done := False;
    While Not Done Do
    Begin
      { une ligne }
      Line := '';
      K := 0;
      While True Do
      Begin
        C := InGetC;
        If C < 0 Then
        Begin
          Done := True;
          Break;
        End;
        If C = 10 Then Break;
        If Length(Line) < 255 Then Line := Line + Chr(C);
        Inc(K);
      End;
      If (K = 0) And (C < 0) Then Break;
      L := 1;
      If Dash Then
        While (L <= Length(Line)) And (Line[L] = #9) Do Inc(L);
      Line := Copy(Line, L, 255);
      If Line = Delim Then Break;
      For L := 1 To Length(Line) Do DbAdd(Ord(Line[L]));
      If C = 10 Then DbAdd(10);
    End;
    L := DbKeep(True);
    R^.Doc := L + 4;
    R^.DocLen := MemL[0:L];
  End;
  HereN := 0;
End;

Procedure GetTok;
Var C, C2, Depth : LongInt; W : String; AllDig, Q, PSub : Boolean;
Begin
  TokS := '';
  TokQuoted := False;
  TokNum := -1;
  While True Do
  Begin
    C := InGetC;
    While (C = 32) Or (C = 9) Do C := InGetC;
    If C = 92 Then
    Begin
      C2 := InGetC;
      If C2 = 10 Then Continue;
      InUnget(C2);
      Break;
    End;
    If C = 35 Then
    Begin
      Repeat
        C := InGetC;
      Until (C = 10) Or (C < 0);
    End;
    Break;
  End;
  If C < 0 Then
  Begin
    Tok := tEOF;
    Exit;
  End;
  If C = 10 Then
  Begin
    Tok := tNL;
    If HereN > 0 Then ReadHeredocs;
    Exit;
  End;
  PSub := False;
  If BashMode And ((C = 60) Or (C = 62)) Then
  Begin
    C2 := InGetC;
    If C2 = 40 Then PSub := True Else InUnget(C2);
  End;
  If Not PSub Then
  Case C Of
    38 : Begin
           C2 := InGetC;
           If C2 = 38 Then Tok := tAndIf
           Else If BashMode And (C2 = 62) Then
           Begin
             C2 := InGetC;
             If C2 = 62 Then Tok := tAndDGreat
             Else Begin InUnget(C2); Tok := tAndGreat; End;
           End
           Else Begin InUnget(C2); Tok := tAmp; End;
           Exit;
         End;
    124 : Begin
           C2 := InGetC;
           If C2 = 124 Then Tok := tOrIf
           Else Begin InUnget(C2); Tok := tPipe; End;
           Exit;
         End;
    59 : Begin
           C2 := InGetC;
           If C2 = 59 Then
           Begin
             Tok := tDSemi;
             If BashMode Then
             Begin
               C2 := InGetC;
               If C2 = 38 Then Tok := tDSemiAmp Else InUnget(C2);
             End;
           End
           Else If BashMode And (C2 = 38) Then Tok := tSemiAmp
           Else Begin InUnget(C2); Tok := tSemi; End;
           Exit;
         End;
    40 : Begin Tok := tLParen; Exit; End;
    41 : Begin Tok := tRParen; Exit; End;
    60 : Begin
           C2 := InGetC;
           If C2 = 60 Then
           Begin
             C2 := InGetC;
             If C2 = 45 Then Tok := tDLessDash
             Else If BashMode And (C2 = 60) Then Tok := tHereStr
             Else Begin InUnget(C2); Tok := tDLess; End;
           End
           Else If C2 = 38 Then Tok := tLessAnd
           Else If C2 = 62 Then Tok := tLessGreat
           Else Begin InUnget(C2); Tok := tLess; End;
           Exit;
         End;
    62 : Begin
           C2 := InGetC;
           If C2 = 62 Then Tok := tDGreat
           Else If C2 = 38 Then Tok := tGreatAnd
           Else If C2 = 124 Then Tok := tClobber
           Else Begin InUnget(C2); Tok := tGreat; End;
           Exit;
         End;
  End;
  { mot }
  W := '';
  If PSub Then
  Begin
    { <(commande) et >(commande) : le corps est range comme $( ) }
    WAdd(W, C);
    W := W + SubPlaceholder(ScanCmdSub);
    TokQuoted := True;
  End
  Else InUnget(C);
  While True Do
  Begin
    C := InGetC;
    If C < 0 Then Break;
    If IsMeta(C) Then
    Begin
      InUnget(C);
      Break;
    End;
    If C = 92 Then
    Begin
      C2 := InGetC;
      If C2 = 10 Then Continue;
      TokQuoted := True;
      WAdd(W, 92);
      If C2 >= 0 Then WAdd(W, C2);
    End
    Else If C = 39 Then
    Begin
      TokQuoted := True;
      WAdd(W, 39);
      Q := True;
      While Q Do
      Begin
        C2 := InGetC;
        If C2 < 0 Then
        Begin
          SynError(Msg(mUnexpEof));
          Q := False;
        End
        Else
        Begin
          WAdd(W, C2);
          If C2 = 39 Then Q := False;
        End;
      End;
    End
    Else If C = 34 Then
    Begin
      TokQuoted := True;
      WAdd(W, 34);
      Q := True;
      While Q Do
      Begin
        C2 := InGetC;
        If C2 < 0 Then
        Begin
          SynError(Msg(mUnexpEof));
          Q := False;
        End
        Else If C2 = 34 Then
        Begin
          WAdd(W, 34);
          Q := False;
        End
        Else If C2 = 92 Then
        Begin
          C2 := InGetC;
          If C2 = 10 Then Continue;
          WAdd(W, 92);
          If C2 >= 0 Then WAdd(W, C2);
        End
        Else If C2 = 36 Then ScanDollar(W)
        Else If C2 = 96 Then W := W + SubPlaceholder(ScanBackquote)
        Else WAdd(W, C2);
      End;
    End
    Else If C = 36 Then ScanDollar(W)
    Else If C = 96 Then W := W + SubPlaceholder(ScanBackquote)
    Else If BashMode And (ExtGlob Or DbParse) And
            ((C = 64) Or (C = 63) Or (C = 42) Or (C = 43) Or (C = 33)) Then
    Begin
      WAdd(W, C);
      C2 := InGetC;
      If C2 = 40 Then
      Begin
        { @( ?( *( +( !( : jusqu'a la parenthese fermante }
        WAdd(W, 40);
        Depth := 1;
        While Depth > 0 Do
        Begin
          C2 := InGetC;
          If C2 < 0 Then
          Begin
            SynError(Msg(mUnexpEof));
            Break;
          End;
          If C2 = 40 Then Inc(Depth)
          Else If C2 = 41 Then Dec(Depth);
          If C2 = 92 Then
          Begin
            WAdd(W, C2);
            C2 := InGetC;
          End;
          If C2 >= 0 Then WAdd(W, C2);
        End;
      End
      Else InUnget(C2);
    End
    Else WAdd(W, C);
  End;
  TokS := W;
  Tok := tWord;
  { numero de descripteur devant une redirection }
  AllDig := (W <> '') And Not TokQuoted;
  For C := 1 To Length(W) Do
    If (W[C] < '0') Or (W[C] > '9') Then AllDig := False;
  If AllDig Then
  Begin
    C := InGetC;
    InUnget(C);
    If (C = 60) Or (C = 62) Then
    Begin
      Tok := tIONum;
      StrInt(W, TokNum);
    End;
  End;
End;

{ ---------- analyse syntaxique ---------- }

Const
  rIf = 1; rThen = 2; rElse = 3; rElif = 4; rFi = 5; rDo = 6; rDone = 7;
  rCase = 8; rEsac = 9; rWhile = 10; rUntil = 11; rFor = 12; rIn = 13;
  rLBrace = 14; rRBrace = 15; rBang = 16; rFunction = 17; rDBr = 18;
  rSelect = 19;

Function ReservedOf : LongInt;
Var S : String;
Begin
  ReservedOf := 0;
  If (Tok <> tWord) Or TokQuoted Then Exit;
  S := TokS;
  If S = 'if' Then ReservedOf := rIf
  Else If S = 'then' Then ReservedOf := rThen
  Else If S = 'else' Then ReservedOf := rElse
  Else If S = 'elif' Then ReservedOf := rElif
  Else If S = 'fi' Then ReservedOf := rFi
  Else If S = 'do' Then ReservedOf := rDo
  Else If S = 'done' Then ReservedOf := rDone
  Else If S = 'case' Then ReservedOf := rCase
  Else If S = 'esac' Then ReservedOf := rEsac
  Else If S = 'while' Then ReservedOf := rWhile
  Else If S = 'until' Then ReservedOf := rUntil
  Else If S = 'for' Then ReservedOf := rFor
  Else If S = 'in' Then ReservedOf := rIn
  Else If S = '{' Then ReservedOf := rLBrace
  Else If S = '}' Then ReservedOf := rRBrace
  Else If S = '!' Then ReservedOf := rBang
  Else If S = 'function' Then ReservedOf := rFunction
  Else If BashMode And (S = '[[') Then ReservedOf := rDBr
  Else If BashMode And (S = 'select') Then ReservedOf := rSelect;
End;

Function ParseList(Top : Boolean) : PNode; Forward;
Function ParseCommand : PNode; Forward;

Function IsAssignWord(Const S : String) : Boolean;
Var K, Dp : LongInt;
Begin
  IsAssignWord := False;
  If S = '' Then Exit;
  If Not (UpCase(S[1]) In ['A'..'Z', '_']) Then Exit;
  K := 2;
  While (K <= Length(S)) And (UpCase(S[K]) In ['A'..'Z', '_', '0'..'9']) Do
    Inc(K);
  If BashMode Then
  Begin
    If (K <= Length(S)) And (S[K] = '[') Then
    Begin
      Dp := 1;
      Inc(K);
      While (K <= Length(S)) And (Dp > 0) Do
      Begin
        If S[K] = '[' Then Inc(Dp)
        Else If S[K] = ']' Then Dec(Dp);
        Inc(K);
      End;
      If Dp > 0 Then Exit;
    End;
    If (K < Length(S)) And (S[K] = '+') And (S[K + 1] = '=') Then Inc(K);
  End;
  If (K <= Length(S)) And (S[K] = '=') Then IsAssignWord := True;
End;

Function NewWord(Const S : String) : PWd;
Var P : PWd;
Begin
  P := PWd(Track(SizeOf(TWd)));
  P^.S := S;
  P^.IsAssign := False;
  P^.Next := Nil;
  NewWord := P;
End;

{ retire les guillemets et barres inverses d'un mot (delimiteur de <<) }
Function Unquote(Const S : String) : String;
Var K : LongInt; R : String; Q : Char;
Begin
  R := '';
  K := 1;
  While K <= Length(S) Do
  Begin
    If S[K] = '\' Then
    Begin
      Inc(K);
      If K <= Length(S) Then R := R + S[K];
    End
    Else If (S[K] = '''') Or (S[K] = '"') Then
    Begin
      Q := S[K];
      Inc(K);
      While (K <= Length(S)) And (S[K] <> Q) Do
      Begin
        R := R + S[K];
        Inc(K);
      End;
    End
    Else R := R + S[K];
    Inc(K);
  End;
  Unquote := R;
End;

Function IsRedirTok : Boolean;
Begin
  IsRedirTok := (Tok = tIONum) Or ((Tok >= tLess) And (Tok <= tClobber)) Or
                ((Tok >= tHereStr) And (Tok <= tAndDGreat));
End;

{ analyse d'une redirection ; Tok est l'operateur ou le numero }
Function ParseRedir : PRedir;
Var R : PRedir; Fd, Op : LongInt;
Begin
  ParseRedir := Nil;
  Fd := -1;
  If Tok = tIONum Then
  Begin
    Fd := TokNum;
    GetTok;
  End;
  Op := Tok;
  If ((Op < tLess) Or (Op > tClobber)) And ((Op < tHereStr) Or
     (Op > tAndDGreat)) Then
  Begin
    SynError(Msg(mSyntax));
    Exit;
  End;
  GetTok;
  If Tok <> tWord Then
  Begin
    SynError(Msg(mSyntax));
    Exit;
  End;
  R := PRedir(Track(SizeOf(TRedir)));
  R^.Op := Op;
  R^.Fd := Fd;
  R^.Next := Nil;
  R^.Doc := 0;
  R^.DocLen := 0;
  R^.DocExp := False;
  If (Op = tDLess) Or (Op = tDLessDash) Then
  Begin
    R^.Target := Unquote(TokS);
    R^.DocExp := Not TokQuoted;
    If HereN < MAXREDIR Then
    Begin
      HereR[HereN] := R;
      HereTab[HereN] := Op = tDLessDash;
      Inc(HereN);
    End;
    R^.Op := tDLess;
  End
  Else R^.Target := TokS;
  GetTok;
  ParseRedir := R;
End;

Procedure AddRedir(N : PNode; R : PRedir);
Var P : PRedir;
Begin
  If R = Nil Then Exit;
  If N^.Redirs = Nil Then N^.Redirs := R
  Else
  Begin
    P := N^.Redirs;
    While P^.Next <> Nil Do P := P^.Next;
    P^.Next := R;
  End;
End;

Procedure SkipNewlines;
Begin
  While Tok = tNL Do GetTok;
End;

Function Expect(R : LongInt) : Boolean;
Begin
  If ReservedOf <> R Then
  Begin
    If Tok = tEOF Then SynError(Msg(mUnexpEof))
    Else SynError(Msg(mUnexpTok) + ' ''' + TokS + '''');
    Expect := False;
    Exit;
  End;
  GetTok;
  Expect := True;
End;

Function AtListEnd : Boolean;
Var R : LongInt;
Begin
  AtListEnd := True;
  If (Tok = tEOF) Or (Tok = tRParen) Or (Tok = tDSemi) Then Exit;
  R := ReservedOf;
  If (R = rThen) Or (R = rElse) Or (R = rElif) Or (R = rFi) Or (R = rDo) Or
     (R = rDone) Or (R = rEsac) Or (R = rRBrace) Then Exit;
  AtListEnd := False;
End;

{ pipeline : [!] commande { | commande } }
Function ParsePipeline : PNode;
Var P, C, Last : PNode; Neg : Boolean;
Begin
  ParsePipeline := Nil;
  Neg := False;
  While ReservedOf = rBang Do
  Begin
    Neg := Not Neg;
    GetTok;
  End;
  P := NewNode(nPipe);
  P^.Neg := Neg;
  C := ParseCommand;
  If SynErr Or (C = Nil) Then Exit;
  P^.A := C;
  Last := C;
  While Tok = tPipe Do
  Begin
    GetTok;
    SkipNewlines;
    C := ParseCommand;
    If SynErr Or (C = Nil) Then Exit;
    Last^.Next := C;
    Last := C;
  End;
  ParsePipeline := P;
End;

{ liste ET-OU : pipeline { (&& | ||) pipeline } }
Function ParseAndOr : PNode;
Var N, P, Last : PNode; Op : LongInt;
Begin
  ParseAndOr := Nil;
  N := NewNode(nAndOr);
  P := ParsePipeline;
  If SynErr Or (P = Nil) Then Exit;
  N^.A := P;
  Last := P;
  While (Tok = tAndIf) Or (Tok = tOrIf) Do
  Begin
    Op := Tok;
    GetTok;
    SkipNewlines;
    P := ParsePipeline;
    If SynErr Or (P = Nil) Then Exit;
    Last^.Op := Op;
    Last^.Next := P;
    Last := P;
  End;
  ParseAndOr := N;
End;

{ liste de commandes. Top : s'arrete au premier saut de ligne }
Function ParseList(Top : Boolean) : PNode;
Var L, Item, Last : PNode;
Begin
  L := NewNode(nList);
  ParseList := L;
  Last := Nil;
  While True Do
  Begin
    If Top Then
    Begin
      If (Tok = tNL) Or (Tok = tEOF) Then Break;
    End
    Else SkipNewlines;
    If AtListEnd Then Break;
    Item := ParseAndOr;
    If SynErr Or (Item = Nil) Then Break;
    If Last = Nil Then L^.A := Item Else Last^.Next := Item;
    Last := Item;
    If Tok = tAmp Then
    Begin
      Item^.Bg := True;
      GetTok;
    End
    Else If Tok = tSemi Then GetTok
    Else If Tok = tNL Then
    Begin
      If Top Then Break;
      GetTok;
    End
    Else Break;
  End;
End;

Function ParseIf : PNode;
Var N, E : PNode;
Begin
  ParseIf := Nil;
  N := NewNode(nIf);
  GetTok;                                  { if / elif }
  N^.A := ParseList(False);
  If SynErr Then Exit;
  If Not Expect(rThen) Then Exit;
  N^.B := ParseList(False);
  If SynErr Then Exit;
  If ReservedOf = rElif Then
  Begin
    E := ParseIf;
    If E = Nil Then Exit;
    N^.C := E;
    ParseIf := N;
    Exit;
  End;
  If ReservedOf = rElse Then
  Begin
    GetTok;
    N^.C := ParseList(False);
    If SynErr Then Exit;
  End;
  If Not Expect(rFi) Then Exit;
  ParseIf := N;
End;

Function ParseWhile(Kind : LongInt) : PNode;
Var N : PNode;
Begin
  ParseWhile := Nil;
  N := NewNode(Kind);
  GetTok;
  N^.A := ParseList(False);
  If SynErr Then Exit;
  If Not Expect(rDo) Then Exit;
  N^.B := ParseList(False);
  If SynErr Then Exit;
  If Not Expect(rDone) Then Exit;
  ParseWhile := N;
End;

Function ParseFor : PNode;
Var N : PNode; W, Last : PWd; Hdr : String; K, Sp : LongInt;
Begin
  ParseFor := Nil;
  N := NewNode(nFor);
  GetTok;
  If BashMode And (Tok = tLParen) Then
  Begin
    GetTok;
    If Tok <> tLParen Then
    Begin
      SynError(Msg(mSyntax));
      Exit;
    End;
    Hdr := ReadArithBody;
    If SynErr Then Exit;
    N^.Kind := nArithFor;
    Last := Nil;
    Hdr := Hdr + ';';
    For K := 1 To 3 Do
    Begin
      Sp := Pos(';', Hdr);
      If Sp = 0 Then Sp := Length(Hdr) + 1;
      W := NewWord(Copy(Hdr, 1, Sp - 1));
      Hdr := Copy(Hdr, Sp + 1, 255);
      If Last = Nil Then N^.Words := W Else Last^.Next := W;
      Last := W;
    End;
    GetTok;
    If Tok = tSemi Then GetTok;
    SkipNewlines;
    If Not Expect(rDo) Then Exit;
    N^.B := ParseList(False);
    If SynErr Then Exit;
    If Not Expect(rDone) Then Exit;
    ParseFor := N;
    Exit;
  End;
  If (Tok <> tWord) Or Not ValidName(TokS) Then
  Begin
    SynError(Msg(mNotId));
    Exit;
  End;
  N^.Name := TokS;
  GetTok;
  SkipNewlines;
  N^.Neg := False;
  If ReservedOf = rIn Then
  Begin
    N^.Neg := True;                     { liste explicite }
    GetTok;
    Last := Nil;
    While Tok = tWord Do
    Begin
      W := NewWord(TokS);
      If Last = Nil Then N^.Words := W Else Last^.Next := W;
      Last := W;
      GetTok;
    End;
    If (Tok = tSemi) Or (Tok = tNL) Then GetTok;
    SkipNewlines;
  End
  Else If Tok = tSemi Then
  Begin
    GetTok;
    SkipNewlines;
  End;
  If Not Expect(rDo) Then Exit;
  N^.B := ParseList(False);
  If SynErr Then Exit;
  If Not Expect(rDone) Then Exit;
  ParseFor := N;
End;

Function ParseCase : PNode;
Var N, It, Last : PNode; W, LW : PWd;
Begin
  ParseCase := Nil;
  N := NewNode(nCase);
  GetTok;
  If Tok <> tWord Then
  Begin
    SynError(Msg(mSyntax));
    Exit;
  End;
  N^.Name := '';
  N^.Words := NewWord(TokS);
  GetTok;
  SkipNewlines;
  If Not Expect(rIn) Then Exit;
  SkipNewlines;
  Last := Nil;
  While ReservedOf <> rEsac Do
  Begin
    If Tok = tEOF Then
    Begin
      SynError(Msg(mUnexpEof));
      Exit;
    End;
    It := NewNode(nCaseItem);
    If Tok = tLParen Then GetTok;
    LW := Nil;
    While Tok = tWord Do
    Begin
      W := NewWord(TokS);
      If LW = Nil Then It^.Words := W Else LW^.Next := W;
      LW := W;
      GetTok;
      If Tok = tPipe Then GetTok Else Break;
    End;
    If Tok <> tRParen Then
    Begin
      SynError(Msg(mSyntax));
      Exit;
    End;
    GetTok;
    It^.A := ParseList(False);
    If SynErr Then Exit;
    If Last = Nil Then N^.B := It Else Last^.Next := It;
    Last := It;
    If (Tok = tDSemi) Or (Tok = tSemiAmp) Or (Tok = tDSemiAmp) Then
    Begin
      It^.Op := Tok;
      GetTok;
      SkipNewlines;
    End
    Else If ReservedOf <> rEsac Then
    Begin
      SynError(Msg(mUnexpTok) + ' ''' + TokS + '''');
      Exit;
    End;
  End;
  GetTok;
  ParseCase := N;
End;

{ commande simple ou definition de fonction }
Function ParseSimple : PNode;
Var N, F : PNode; W, LastW : PWd; SeenWord : Boolean; Cnt : LongInt;
    R : PRedir;
Begin
  ParseSimple := Nil;
  N := NewNode(nSimple);
  LastW := Nil;
  SeenWord := False;
  Cnt := 0;
  While True Do
  Begin
    If IsRedirTok Then
    Begin
      R := ParseRedir;
      If SynErr Then Exit;
      AddRedir(N, R);
    End
    Else If Tok = tWord Then
    Begin
      W := NewWord(TokS);
      If (Not SeenWord) And IsAssignWord(TokS) Then W^.IsAssign := True
      Else SeenWord := True;
      If LastW = Nil Then N^.Words := W Else LastW^.Next := W;
      LastW := W;
      Inc(Cnt);
      GetTok;
      If BashMode And (Tok = tLParen) And (W^.S <> '') And
         (W^.S[Length(W^.S)] = '=') Then
      Begin
        ParseCompound(W);
        If SynErr Then Exit;
        Continue;
      End;
      If (Cnt = 1) And (Not W^.IsAssign) And (Tok = tLParen) Then
      Begin
        { definition de fonction : nom ( ) corps }
        GetTok;
        If Tok <> tRParen Then
        Begin
          SynError(Msg(mSyntax));
          Exit;
        End;
        GetTok;
        SkipNewlines;
        F := NewNode(nFunc);
        F^.Name := W^.S;
        F^.A := ParseCommand;
        If SynErr Or (F^.A = Nil) Then Exit;
        ParseSimple := F;
        Exit;
      End;
    End
    Else Break;
  End;
  If (N^.Words = Nil) And (N^.Redirs = Nil) Then
  Begin
    If Tok = tEOF Then SynError(Msg(mUnexpEof))
    Else SynError(Msg(mUnexpTok));
    Exit;
  End;
  ParseSimple := N;
End;


{ ---------- bash : [[ ]], (( )), for ((;;)), select, tableaux ---------- }

{ regex apres =~ : lu tel quel jusqu'a un blanc hors parentheses }
Function ReadRegexWord : String;
Var C, C2, Depth : LongInt; W : String;
Begin
  W := '';
  Depth := 0;
  C := InGetC;
  While (C = 32) Or (C = 9) Do C := InGetC;
  While C >= 0 Do
  Begin
    If ((C = 32) Or (C = 9) Or (C = 10)) And (Depth = 0) Then
    Begin
      InUnget(C);
      Break;
    End;
    If C = 40 Then Inc(Depth)
    Else If C = 41 Then
    Begin
      If Depth = 0 Then
      Begin
        InUnget(C);
        Break;
      End;
      Dec(Depth);
    End;
    If C = 92 Then
    Begin
      WAdd(W, 92);
      C2 := InGetC;
      If C2 >= 0 Then WAdd(W, C2);
    End
    Else If C = 39 Then
    Begin
      WAdd(W, 39);
      Repeat
        C2 := InGetC;
        If C2 >= 0 Then WAdd(W, C2);
      Until (C2 = 39) Or (C2 < 0);
    End
    Else If C = 34 Then
    Begin
      WAdd(W, 34);
      Repeat
        C2 := InGetC;
        If C2 = 36 Then ScanDollar(W)
        Else If C2 >= 0 Then WAdd(W, C2);
        If C2 = 92 Then
        Begin
          C2 := InGetC;
          If C2 >= 0 Then WAdd(W, C2);
          C2 := 0;
        End;
      Until (C2 = 34) Or (C2 < 0);
    End
    Else If C = 36 Then ScanDollar(W)
    Else WAdd(W, C);
    C := InGetC;
  End;
  ReadRegexWord := W;
End;

{ corps de (( ... )) : lu jusqu'aux deux parentheses fermantes }
Function ReadArithBody : String;
Var C, C2, Depth : LongInt; W : String;
Begin
  W := '';
  Depth := 0;
  While True Do
  Begin
    C := InGetC;
    If C < 0 Then
    Begin
      SynError(Msg(mUnexpEof));
      Break;
    End;
    If C = 36 Then
    Begin
      ScanDollar(W);
      Continue;
    End;
    If C = 40 Then Inc(Depth)
    Else If C = 41 Then
    Begin
      If Depth = 0 Then
      Begin
        C2 := InGetC;
        If C2 = 41 Then Break;
        SynError(Msg(mSyntax));
        Break;
      End;
      Dec(Depth);
    End;
    WAdd(W, C);
  End;
  ReadArithBody := W;
End;

Function ParseDBr : PNode;
Var N : PNode; W, Last : PWd; S : String; IsOp : Boolean;
Begin
  ParseDBr := Nil;
  N := NewNode(nDBr);
  Last := Nil;
  DbParse := True;
  GetTok;
  While True Do
  Begin
    If SynErr Then
    Begin
      DbParse := False;
      Exit;
    End;
    If Tok = tEOF Then
    Begin
      SynError(Msg(mUnexpEof));
      Exit;
    End;
    If Tok = tNL Then
    Begin
      GetTok;
      Continue;
    End;
    If (Tok = tWord) And (TokS = ']]') And Not TokQuoted Then Break;
    IsOp := False;
    If Tok = tWord Then S := TokS
    Else
    Begin
      IsOp := True;
      Case Tok Of
        tAndIf : S := '&&';
        tOrIf : S := '||';
        tLParen : S := '(';
        tRParen : S := ')';
        tLess : S := '<';
        tGreat : S := '>';
      Else
        Begin
          SynError(Msg(mUnexpTok));
          Exit;
        End;
      End;
    End;
    W := NewWord(S);
    W^.IsAssign := IsOp;
    If Last = Nil Then N^.Words := W Else Last^.Next := W;
    Last := W;
    If (Not IsOp) And (S = '=~') And Not TokQuoted Then
    Begin
      W := NewWord(ReadRegexWord);
      Last^.Next := W;
      Last := W;
    End;
    GetTok;
  End;
  DbParse := False;
  GetTok;
  ParseDBr := N;
End;

{ corps d'une affectation composee a=( ... ) : les elements sont ranges dans
  le mot, apres #5, separes par #2 }
Procedure ParseCompound(W : PWd);
Var Items : String;
Begin
  GetTok;                                 { apres ( }
  Items := '';
  While True Do
  Begin
    If SynErr Then Exit;
    If Tok = tNL Then
    Begin
      GetTok;
      Continue;
    End;
    If Tok = tRParen Then Break;
    If Tok <> tWord Then
    Begin
      SynError(Msg(mSyntax));
      Exit;
    End;
    If Items <> '' Then Items := Items + #2;
    Items := Items + TokS;
    GetTok;
  End;
  GetTok;
  W^.S := W^.S + #5 + Items;
End;

Function ParseSelect : PNode;
Var N : PNode; W, Last : PWd;
Begin
  ParseSelect := Nil;
  N := NewNode(nSelect);
  GetTok;
  If (Tok <> tWord) Or Not ValidName(TokS) Then
  Begin
    SynError(Msg(mNotId));
    Exit;
  End;
  N^.Name := TokS;
  GetTok;
  SkipNewlines;
  N^.Neg := False;
  If ReservedOf = rIn Then
  Begin
    N^.Neg := True;
    GetTok;
    Last := Nil;
    While Tok = tWord Do
    Begin
      W := NewWord(TokS);
      If Last = Nil Then N^.Words := W Else Last^.Next := W;
      Last := W;
      GetTok;
    End;
    If (Tok = tSemi) Or (Tok = tNL) Then GetTok;
    SkipNewlines;
  End
  Else If Tok = tSemi Then
  Begin
    GetTok;
    SkipNewlines;
  End;
  If Not Expect(rDo) Then Exit;
  N^.B := ParseList(False);
  If SynErr Then Exit;
  If Not Expect(rDone) Then Exit;
  ParseSelect := N;
End;

Function ParseCommand : PNode;
Var N, L : PNode; R : LongInt; Rd : PRedir; FW : String; Body : String;
Begin
  ParseCommand := Nil;
  If SynErr Then Exit;
  N := Nil;
  If Tok = tLParen Then
  Begin
    GetTok;
    If BashMode And (Tok = tLParen) Then
    Begin
      { (( expression )) }
      Body := ReadArithBody;
      If SynErr Then Exit;
      N := NewNode(nArith);
      N^.Words := NewWord(Body);
      GetTok;
      While IsRedirTok Do
      Begin
        Rd := ParseRedir;
        If SynErr Then Exit;
        AddRedir(N, Rd);
      End;
      ParseCommand := N;
      Exit;
    End;
    N := NewNode(nSubshell);
    N^.A := ParseList(False);
    If SynErr Then Exit;
    If Tok <> tRParen Then
    Begin
      SynError(Msg(mSyntax));
      Exit;
    End;
    GetTok;
  End
  Else
  Begin
    R := ReservedOf;
    Case R Of
      rIf : N := ParseIf;
      rWhile : N := ParseWhile(nWhile);
      rUntil : N := ParseWhile(nUntil);
      rFor : N := ParseFor;
      rCase : N := ParseCase;
      rDBr : N := ParseDBr;
      rSelect : N := ParseSelect;
      rLBrace :
        Begin
          N := NewNode(nBrace);
          GetTok;
          N^.A := ParseList(False);
          If SynErr Then Exit;
          If Not Expect(rRBrace) Then Exit;
        End;
      rFunction :
        Begin
          GetTok;
          If Tok <> tWord Then
          Begin
            SynError(Msg(mSyntax));
            Exit;
          End;
          FW := TokS;
          GetTok;
          If Tok = tLParen Then
          Begin
            GetTok;
            If Tok <> tRParen Then
            Begin
              SynError(Msg(mSyntax));
              Exit;
            End;
            GetTok;
          End;
          SkipNewlines;
          N := NewNode(nFunc);
          N^.Name := FW;
          N^.A := ParseCommand;
          If SynErr Or (N^.A = Nil) Then Exit;
          ParseCommand := N;
          Exit;
        End;
      rThen, rElse, rElif, rFi, rDo, rDone, rEsac, rRBrace :
        Begin
          SynError(Msg(mUnexpTok) + ' ''' + TokS + '''');
          Exit;
        End;
    Else
      Begin
        N := ParseSimple;
        ParseCommand := N;
        Exit;
      End;
    End;
  End;
  If SynErr Or (N = Nil) Then Exit;
  { redirections apres une commande composee }
  While IsRedirTok Do
  Begin
    Rd := ParseRedir;
    If SynErr Then Exit;
    AddRedir(N, Rd);
  End;
  ParseCommand := N;
End;

{ ---------- filtrage par motif (case, *, ?, [..]) ---------- }

{ P : motif, PF : drapeaux ('1' = caractere entre guillemets : litteral) }
Function PatMatchAt(Const P, PF, T : String; PI, TI : LongInt) : Boolean;
Forward;

{ sous-chaine Sub (entiere) filtree par l'une des alternatives de Al }
Function ExtAny(Const P, PF : String; A0, A1 : LongInt; Const Sub : String)
    : Boolean;
Var Dp, K, St : LongInt;
Begin
  ExtAny := False;
  Dp := 0;
  St := A0;
  K := A0;
  While K <= A1 + 1 Do
  Begin
    If (K > A1) Or ((P[K] = '|') And (Dp = 0)) Then
    Begin
      If PatMatchAt(Copy(P, St, K - St), Copy(PF, St, K - St), Sub, 1, 1) Then
      Begin
        ExtAny := True;
        Exit;
      End;
      St := K + 1;
    End
    Else If P[K] = '(' Then Inc(Dp)
    Else If P[K] = ')' Then Dec(Dp);
    Inc(K);
  End;
End;

{ repetition : Sub est une suite (eventuellement vide si Zero) d'alternatives }
Function ExtRep(Const P, PF : String; A0, A1 : LongInt; Const Sub : String;
    Zero : Boolean) : Boolean;
Var L : LongInt;
Begin
  ExtRep := False;
  If Sub = '' Then
  Begin
    ExtRep := Zero;
    Exit;
  End;
  For L := 1 To Length(Sub) Do
    If ExtAny(P, PF, A0, A1, Copy(Sub, 1, L)) Then
      If ExtRep(P, PF, A0, A1, Copy(Sub, L + 1, 255), True) Then
      Begin
        ExtRep := True;
        Exit;
      End;
End;

Function PatMatchAt(Const P, PF, T : String; PI, TI : LongInt) : Boolean;
Var Neg, Ok : Boolean; C, Lo, Hi : Char; K, Dp, Cl, L : LongInt; Kd : Char;
Begin
  While PI <= Length(P) Do
  Begin
    If ExtGlob And (P[PI] In ['@', '?', '*', '+', '!']) And
       (PI < Length(P)) And (P[PI + 1] = '(') And (PF[PI] <> '1') Then
    Begin
      Dp := 0;
      Cl := PI + 1;
      While Cl <= Length(P) Do
      Begin
        If P[Cl] = '(' Then Inc(Dp)
        Else If P[Cl] = ')' Then
        Begin
          Dec(Dp);
          If Dp = 0 Then Break;
        End;
        Inc(Cl);
      End;
      If Cl <= Length(P) Then
      Begin
        Kd := P[PI];
        For L := 0 To Length(T) - TI + 1 Do
        Begin
          Ok := False;
          If Kd = '@' Then Ok := ExtAny(P, PF, PI + 2, Cl - 1, Copy(T, TI, L))
          Else If Kd = '?' Then
            Ok := (L = 0) Or ExtAny(P, PF, PI + 2, Cl - 1, Copy(T, TI, L))
          Else If Kd = '*' Then
            Ok := ExtRep(P, PF, PI + 2, Cl - 1, Copy(T, TI, L), True)
          Else If Kd = '+' Then
            Ok := ExtRep(P, PF, PI + 2, Cl - 1, Copy(T, TI, L), False)
          Else Ok := Not ExtAny(P, PF, PI + 2, Cl - 1, Copy(T, TI, L));
          If Ok And PatMatchAt(P, PF, T, Cl + 1, TI + L) Then
          Begin
            PatMatchAt := True;
            Exit;
          End;
        End;
        PatMatchAt := False;
        Exit;
      End;
    End;
    If (P[PI] = '*') And (PF[PI] <> '1') Then
    Begin
      While (PI <= Length(P)) And (P[PI] = '*') And (PF[PI] <> '1') Do Inc(PI);
      If PI > Length(P) Then
      Begin
        PatMatchAt := True;
        Exit;
      End;
      For K := TI To Length(T) + 1 Do
        If PatMatchAt(P, PF, T, PI, K) Then
        Begin
          PatMatchAt := True;
          Exit;
        End;
      PatMatchAt := False;
      Exit;
    End;
    If TI > Length(T) Then
    Begin
      PatMatchAt := False;
      Exit;
    End;
    If (P[PI] = '?') And (PF[PI] <> '1') Then
    Begin
      Inc(PI);
      Inc(TI);
    End
    Else If (P[PI] = '[') And (PF[PI] <> '1') Then
    Begin
      { ensemble : cherche la ] fermante }
      K := PI + 1;
      Neg := False;
      If (K <= Length(P)) And ((P[K] = '!') Or (P[K] = '^')) Then
      Begin
        Neg := True;
        Inc(K);
      End;
      Ok := False;
      C := T[TI];
      Lo := #0;
      While K <= Length(P) Do
      Begin
        If (P[K] = ']') And (K > PI + 1 + Ord(Neg)) Then Break;
        Lo := P[K];
        If (K + 2 <= Length(P)) And (P[K + 1] = '-') And (P[K + 2] <> ']') Then
        Begin
          Hi := P[K + 2];
          If (C >= Lo) And (C <= Hi) Then Ok := True;
          K := K + 3;
        End
        Else
        Begin
          If C = Lo Then Ok := True;
          Inc(K);
        End;
      End;
      If K > Length(P) Then
      Begin
        { pas de ] : [ litteral }
        If T[TI] <> '[' Then
        Begin
          PatMatchAt := False;
          Exit;
        End;
        Inc(PI);
        Inc(TI);
      End
      Else
      Begin
        If Ok = Neg Then
        Begin
          PatMatchAt := False;
          Exit;
        End;
        PI := K + 1;
        Inc(TI);
      End;
    End
    Else
    Begin
      If P[PI] <> T[TI] Then
      Begin
        PatMatchAt := False;
        Exit;
      End;
      Inc(PI);
      Inc(TI);
    End;
  End;
  PatMatchAt := TI > Length(T);
End;

Function PatMatch(Const P, PF, T : String) : Boolean;
Begin
  PatMatch := PatMatchAt(P, PF, T, 1, 1);
End;

{ ---------- expansion des mots ---------- }

Type
  TExp = Record
    S, F : String;
    Have : Boolean;
    Added : LongInt;
    AtUsed : Boolean;
    Dst : PArgs;
    Single : Boolean;
    Glob : Boolean;
  End;

Procedure ExpandInto(Var E : TExp; Const Raw : String; InDQ : Boolean);
Forward;
Function RunSubst(Idx : LongInt; Var Len : LongInt) : LongInt; Forward;
Function ArithEval(Const S : String) : LongInt; Forward;
Procedure GlobField(Const S, F : String; Dst : PArgs); Forward;
Function ExpandStr(Const Raw : String) : String; Forward;

Procedure ExpInit(Var E : TExp; Dst : PArgs; Single : Boolean);
Begin
  E.S := '';
  E.F := '';
  E.Have := False;
  E.Added := 0;
  E.AtUsed := False;
  E.Dst := Dst;
  E.Single := Single;
  E.Glob := True;
End;

Procedure AddChar(Var E : TExp; C : Char; Quoted : Boolean);
Begin
  If Length(E.S) < 254 Then
  Begin
    E.S := E.S + C;
    If Quoted Then E.F := E.F + '1' Else E.F := E.F + '0';
  End;
  E.Have := True;
  Inc(E.Added);
End;

Function HasGlob(Const S, F : String) : Boolean;
Var K : LongInt;
Begin
  HasGlob := False;
  For K := 1 To Length(S) Do
    If (F[K] <> '1') And ((S[K] = '*') Or (S[K] = '?') Or (S[K] = '[')) Then
    Begin
      HasGlob := True;
      Exit;
    End
    Else If ExtGlob And (F[K] <> '1') And (K < Length(S)) And
            (S[K + 1] = '(') And (S[K] In ['@', '+', '!']) Then
    Begin
      HasGlob := True;
      Exit;
    End;
End;

Procedure FinishField(Var E : TExp; Force : Boolean);
Begin
  If E.Single Then Exit;
  If E.Have Or Force Then
  Begin
    If E.Glob And Not OptNoGlob And HasGlob(E.S, E.F) Then
      GlobField(E.S, E.F, E.Dst)
    Else ArgsAdd(E.Dst^, E.S);
  End;
  E.S := '';
  E.F := '';
  E.Have := False;
End;

Function IfsOf : String;
Var V : String;
Begin
  If GetVarRaw('IFS', V) Then IfsOf := V Else IfsOf := ' ' + #9 + #10;
End;

{ ajoute une valeur : entre guillemets telle quelle, sinon decoupee par IFS }
Procedure AppendValue(Var E : TExp; Const V : String; Quoted : Boolean);
Var K : LongInt; Ifs : String; C : Char; InIfs, Ws : Boolean;
Begin
  If Quoted Or E.Single Then
  Begin
    For K := 1 To Length(V) Do AddChar(E, V[K], True);
    Exit;
  End;
  Ifs := IfsOf;
  For K := 1 To Length(V) Do
  Begin
    C := V[K];
    InIfs := Pos(C, Ifs) > 0;
    If InIfs Then
    Begin
      Ws := (C = ' ') Or (C = #9) Or (C = #10);
      If Ws Then
      Begin
        If E.Have Then FinishField(E, False);
      End
      Else FinishField(E, True);
    End
    Else AddChar(E, C, False);
  End;
End;

Procedure AppendBuf(Var E : TExp; Addr, Len : LongInt; Quoted : Boolean);
Var K : LongInt; C : Char; Ifs : String; Ws : Boolean;
Begin
  Ifs := '';
  If Not (Quoted Or E.Single) Then Ifs := IfsOf;
  For K := 0 To Len - 1 Do
  Begin
    C := Chr(Mem[0:Addr + K]);
    If Quoted Or E.Single Then AddChar(E, C, True)
    Else If Pos(C, Ifs) > 0 Then
    Begin
      Ws := (C = ' ') Or (C = #9) Or (C = #10);
      If Ws Then
      Begin
        If E.Have Then FinishField(E, False);
      End
      Else FinishField(E, True);
    End
    Else AddChar(E, C, False);
  End;
End;

Function HomeOf(Const User : String) : String;
Var P : TSysPasswd;
Begin
  HomeOf := '';
  If User = '' Then
  Begin
    HomeOf := VarValue('HOME');
    Exit;
  End;
  If SysGetPwNam(User, P) Then HomeOf := P.Home;
End;

{ valeur et etat d'une variable pour ${...} ; Set = definie et non vide }
Procedure ParamArray(Var E : TExp; Const Name, Sub, Op : String; DQ, Hash,
    KeysMode : Boolean); Forward;

Procedure ParamExpand(Var E : TExp; Const Inner : String; DQ : Boolean);
Var
  Name, Op, Word, V, R, Sub : String;
  K, K2, Cnt, X, Len, Dp : LongInt;
  IsSet, NullToo, Hash, Done, Indir, HasSub : Boolean;
  Anch : Char;
  E2 : TExp;
  Pat, PF : String;
  L2 : LongInt;
Begin
  Name := '';
  K := 1;
  Hash := False;
  Indir := False;
  HasSub := False;
  Sub := '';
  If (Length(Inner) > 1) And (Inner[1] = '#') And (Inner[2] <> '}') Then
  Begin
    Hash := True;
    K := 2;
  End
  Else If BashMode And (Length(Inner) > 1) And (Inner[1] = '!') And
          IsNameCh(Ord(Inner[2])) Then
  Begin
    Indir := True;
    K := 2;
  End;
  { nom : identificateur, chiffres, ou caractere special }
  If (K <= Length(Inner)) And IsNameCh(Ord(Inner[K])) Then
    While (K <= Length(Inner)) And IsNameCh(Ord(Inner[K])) Do
    Begin
      Name := Name + Inner[K];
      Inc(K);
    End
  Else If K <= Length(Inner) Then
  Begin
    Name := Inner[K];
    Inc(K);
  End;
  If BashMode And (K <= Length(Inner)) And (Inner[K] = '[') And
     ValidName(Name) Then
  Begin
    Dp := 1;
    X := K + 1;
    While (X <= Length(Inner)) And (Dp > 0) Do
    Begin
      If Inner[X] = '[' Then Inc(Dp)
      Else If Inner[X] = ']' Then Dec(Dp);
      Inc(X);
    End;
    Sub := Copy(Inner, K + 1, X - K - 2);
    K := X;
    HasSub := True;
  End;
  Op := Copy(Inner, K, 255);
  If HasSub And ((Sub = '@') Or (Sub = '*')) Then
  Begin
    ParamArray(E, ResolveRef(Name), Sub, Op, DQ, Hash, Indir);
    Exit;
  End;
  If Indir And (Op <> '') And ((Op = '*') Or (Op = '@')) And Not HasSub Then
  Begin
    { ${!prefixe*} : noms de variables }
    Word := '';
    For X := 0 To MAXVARS - 1 Do
      If Vars[X].Used And (Copy(Vars[X].Name, 1, Length(Name)) = Name) And
         (Pos('[', Vars[X].Name) = 0) Then
      Begin
        If Word <> '' Then Word := Word + ' ';
        Word := Word + Vars[X].Name;
      End;
    AppendValue(E, Word, DQ);
    Exit;
  End;
  If HasSub Then
  Begin
    Pat := Name;
    Name := ElemName(Name, Sub);
    If (Not VarSet(Name)) And (ArrKind(Pat) = 0) And (Name = Pat + '[0]') Then
      Name := Pat;
  End;
  If Indir Then
  Begin
    GetVar(Name, V);
    Name := V;
    If Pos('[', Name) > 0 Then
      Name := ElemName(Copy(Name, 1, Pos('[', Name) - 1),
                Copy(Name, Pos('[', Name) + 1,
                     Length(Name) - Pos('[', Name) - 1));
  End;
  If (Name = '@') Or (Name = '*') Then
  Begin
    If BashMode And (Length(Op) > 1) And (Op[1] = ':') And
       Not (Op[2] In ['-', '=', '?', '+']) Then
    Begin
      Pat := Copy(Op, 2, 255);
      X := Pos(':', Pat);
      If X = 0 Then
      Begin
        If Not StrInt(Pat, K2) Then K2 := 0;
        Len := 1000000;
      End
      Else
      Begin
        If Not StrInt(Copy(Pat, 1, X - 1), K2) Then K2 := 0;
        If Not StrInt(Copy(Pat, X + 1, 255), Len) Then Len := 0;
      End;
      If K2 < 0 Then K2 := NPos + 1 + K2;
      If K2 < 0 Then K2 := 0;
      Cnt := 0;
      For X := K2 To NPos Do
      Begin
        If Cnt >= Len Then Break;
        If X = 0 Then V := Arg0 Else V := PosGet(X);
        If (Cnt > 0) Then
          If DQ And (Name = '@') Then FinishField(E, True)
          Else If DQ Then AddChar(E, ' ', True)
          Else FinishField(E, False);
        AppendValue(E, V, DQ);
        Inc(Cnt);
      End;
      Exit;
    End;
    If Hash Then
    Begin
      AppendValue(E, IntStr(NPos), True);
      Exit;
    End;
    If (Op = '') Then
    Begin
      ExpandInto(E, '$' + Name, DQ);
      Exit;
    End;
  End;
  IsSet := GetVar(Name, V);
  If Hash Then
  Begin
    AppendValue(E, IntStr(Length(V)), True);
    Exit;
  End;
  If Op = '' Then
  Begin
    If (Not IsSet) And OptU Then
    Begin
      ShErr(Name + ': ' + Msg(mUnbound));
      ExitCode := 1;
      CleanExit(1);
    End;
    AppendValue(E, V, DQ);
    Exit;
  End;
  NullToo := False;
  If Op[1] = ':' Then
  Begin
    NullToo := True;
    Op := Copy(Op, 2, 255);
    If (Op <> '') And (Not (Op[1] In ['-', '=', '?', '+'])) Then
    Begin
      { sous-chaine : ${v:off:len} }
      K2 := Pos(':', Op);
      If K2 = 0 Then
      Begin
        If Not StrInt(Op, X) Then X := 0;
        Len := 100000;
      End
      Else
      Begin
        If Not StrInt(Copy(Op, 1, K2 - 1), X) Then X := 0;
        If Not StrInt(Copy(Op, K2 + 1, 255), Len) Then Len := 0;
      End;
      If X < 0 Then X := Length(V) + X;
      If X < 0 Then X := 0;
      AppendValue(E, Copy(V, X + 1, Len), DQ);
      Exit;
    End;
  End;
  If Op = '' Then
  Begin
    ShErr(Msg(mBadSub));
    Exit;
  End;
  Word := Copy(Op, 2, 255);
  Case Op[1] Of
    '^', ',' :
      Begin
        If (Word <> '') And (Word[1] = Op[1]) Then
        Begin
          If Op[1] = '^' Then R := UpStr(V) Else R := LowStr(V);
        End
        Else If V = '' Then R := ''
        Else If Op[1] = '^' Then R := UpStr(Copy(V, 1, 1)) + Copy(V, 2, 255)
        Else R := LowStr(Copy(V, 1, 1)) + Copy(V, 2, 255);
        AppendValue(E, R, DQ);
      End;
    '@' :
      Begin
        If Word = 'U' Then R := UpStr(V)
        Else If Word = 'L' Then R := LowStr(V)
        Else If Word = 'u' Then R := UpStr(Copy(V, 1, 1)) + Copy(V, 2, 255)
        Else If Word = 'Q' Then
        Begin
          R := '''';
          For K := 1 To Length(V) Do
            If V[K] = '''' Then R := R + '''\'''''
            Else R := R + V[K];
          R := R + '''';
        End
        Else R := V;
        AppendValue(E, R, DQ);
      End;
    '-' :
      Begin
        If IsSet And ((Not NullToo) Or (V <> '')) Then AppendValue(E, V, DQ)
        Else ExpandInto(E, Word, DQ);
      End;
    '=' :
      Begin
        If IsSet And ((Not NullToo) Or (V <> '')) Then AppendValue(E, V, DQ)
        Else
        Begin
          ExpInit(E2, Nil, True);
          ExpandInto(E2, Word, DQ);
          SetVar(Name, E2.S);
          AppendValue(E, E2.S, DQ);
        End;
      End;
    '?' :
      Begin
        If IsSet And ((Not NullToo) Or (V <> '')) Then AppendValue(E, V, DQ)
        Else
        Begin
          ExpInit(E2, Nil, True);
          ExpandInto(E2, Word, DQ);
          If E2.S = '' Then E2.S := Msg(mUnbound);
          ShErr(Name + ': ' + E2.S);
          If Not Interactive Then CleanExit(1);
        End;
      End;
    '+' :
      Begin
        If IsSet And ((Not NullToo) Or (V <> '')) Then
          ExpandInto(E, Word, DQ);
      End;
    '#', '%' :
      Begin
        Done := False;
        Cnt := 1;                           { 1 : plus court, 2 : plus long }
        If (Word <> '') And (Word[1] = Op[1]) Then
        Begin
          Cnt := 2;
          Word := Copy(Word, 2, 255);
        End;
        ExpInit(E2, Nil, True);
        ExpandInto(E2, Word, False);
        Pat := E2.S;
        PF := E2.F;
        R := V;
        If Op[1] = '#' Then
        Begin
          If Cnt = 1 Then
          Begin
            For K := 0 To Length(V) Do
              If (Not Done) And PatMatch(Pat, PF, Copy(V, 1, K)) Then
              Begin
                R := Copy(V, K + 1, 255);
                Done := True;
              End;
          End
          Else
            For K := Length(V) DownTo 0 Do
              If (Not Done) And PatMatch(Pat, PF, Copy(V, 1, K)) Then
              Begin
                R := Copy(V, K + 1, 255);
                Done := True;
              End;
        End
        Else
        Begin
          If Cnt = 1 Then
          Begin
            For K := Length(V) DownTo 0 Do
              If (Not Done) And PatMatch(Pat, PF, Copy(V, K + 1, 255)) Then
              Begin
                R := Copy(V, 1, K);
                Done := True;
              End;
          End
          Else
            For K := 0 To Length(V) Do
              If (Not Done) And PatMatch(Pat, PF, Copy(V, K + 1, 255)) Then
              Begin
                R := Copy(V, 1, K);
                Done := True;
              End;
        End;
        AppendValue(E, R, DQ);
      End;
    '/' :
      Begin
        { ${v/motif/remplacement} et ${v//motif/remplacement} }
        Cnt := 1;
        Anch := ' ';
        If (Word <> '') And (Word[1] = '/') Then
        Begin
          Cnt := 2;
          Word := Copy(Word, 2, 255);
        End
        Else If (Word <> '') And ((Word[1] = '#') Or (Word[1] = '%')) Then
        Begin
          Anch := Word[1];
          Word := Copy(Word, 2, 255);
        End;
        K2 := Pos('/', Word);
        If K2 = 0 Then
        Begin
          Pat := Word;
          R := '';
        End
        Else
        Begin
          Pat := Copy(Word, 1, K2 - 1);
          R := Copy(Word, K2 + 1, 255);
        End;
        ExpInit(E2, Nil, True);
        ExpandInto(E2, Pat, False);
        Pat := E2.S;
        PF := E2.F;
        ExpInit(E2, Nil, True);
        ExpandInto(E2, R, False);
        R := E2.S;
        Word := '';
        K := 1;
        If Anch <> ' ' Then
        Begin
          Done := False;
          If Anch = '#' Then
          Begin
            For L2 := Length(V) DownTo 0 Do
              If (Not Done) And PatMatch(Pat, PF, Copy(V, 1, L2)) Then
              Begin
                Word := R + Copy(V, L2 + 1, 255);
                Done := True;
              End;
          End
          Else
            For L2 := 0 To Length(V) Do
              If (Not Done) And PatMatch(Pat, PF, Copy(V, L2 + 1, 255)) Then
              Begin
                Word := Copy(V, 1, L2) + R;
                Done := True;
              End;
          If Not Done Then Word := V;
          K := Length(V) + 1;
        End;
        While K <= Length(V) Do
        Begin
          Done := False;
          For L2 := Length(V) - K + 1 DownTo 1 Do
            If (Not Done) And (Pat <> '') And
               PatMatch(Pat, PF, Copy(V, K, L2)) Then
            Begin
              Word := Word + R;
              K := K + L2;
              Done := True;
              If Cnt = 1 Then
              Begin
                Word := Word + Copy(V, K, 255);
                K := Length(V) + 1;
              End;
            End;
          If Not Done Then
          Begin
            Word := Word + V[K];
            Inc(K);
          End;
        End;
        AppendValue(E, Word, DQ);
      End;
  Else
    ShErr(Msg(mBadSub));
  End;
End;

Function ProcSubst(Idx : LongInt; IsIn : Boolean) : String; Forward;


{ ${nom[@]} ${nom[*]} ${#nom[@]} ${!nom[@]} ${nom[@]:d:n} ${nom[@]op...} }
Procedure ParamArray(Var E : TExp; Const Name, Sub, Op : String; DQ, Hash,
    KeysMode : Boolean);
Var Keys, Vals : TArgs; K, X, Off, Cnt, I : LongInt; V, Ifs, Q : String;
    Sep : Char; Sc : String; Tail : String;
Begin
  ArgsInit(Keys);
  ArgsInit(Vals);
  If ArrKind(Name) > 0 Then
  Begin
    ArrKeys(Name, Keys);
    For K := 0 To Keys.N - 1 Do
    Begin
      GetVar(Name + '[' + Keys.It[K]^ + ']', V);
      ArgsAdd(Vals, V);
    End;
  End
  Else If VarSet(Name) Then
  Begin
    ArgsAdd(Keys, '0');
    GetVar(Name, V);
    ArgsAdd(Vals, V);
  End;
  If Hash Then
  Begin
    AppendValue(E, IntStr(Keys.N), True);
    ArgsFree(Keys);
    ArgsFree(Vals);
    Exit;
  End;
  If Op <> '' Then
  Begin
    If (Op[1] = ':') And (Length(Op) > 1) And
       Not (Op[2] In ['-', '=', '?', '+']) Then
    Begin
      { tranche ${a[@]:off:len} }
      Tail := Copy(Op, 2, 255);
      X := Pos(':', Tail);
      If X = 0 Then
      Begin
        If Not StrInt(Tail, Off) Then Off := 0;
        Cnt := 1000000;
      End
      Else
      Begin
        If Not StrInt(Copy(Tail, 1, X - 1), Off) Then Off := 0;
        If Not StrInt(Copy(Tail, X + 1, 255), Cnt) Then Cnt := 0;
      End;
      If Off < 0 Then Off := Vals.N + Off;
      If Off < 0 Then Off := 0;
      For I := Vals.N - 1 DownTo 0 Do
        If (I < Off) Or (I >= Off + Cnt) Then
        Begin
          FreeStr(Vals.It[I]);
          For X := I To Vals.N - 2 Do Vals.It[X] := Vals.It[X + 1];
          Dec(Vals.N);
        End;
    End
    Else
    Begin
      { autre operation : appliquee a chaque element }
      For K := 0 To Keys.N - 1 Do
      Begin
        If (K > 0) And (DQ Or True) Then FinishField(E, DQ);
        ParamExpand(E, Name + '[' + Keys.It[K]^ + ']' + Op, DQ);
      End;
      ArgsFree(Keys);
      ArgsFree(Vals);
      Exit;
    End;
  End;
  If KeysMode Then
  Begin
    ArgsFree(Vals);
    Vals := Keys;
    Keys.N := 0;
  End;
  If DQ And (Sub = '*') Then
  Begin
    Ifs := IfsOf;
    If Ifs = '' Then Sep := #0 Else Sep := Ifs[1];
    For K := 0 To Vals.N - 1 Do
    Begin
      If (K > 0) And (Sep <> #0) Then AddChar(E, Sep, True);
      AppendValue(E, Vals.It[K]^, True);
    End;
  End
  Else If DQ Then
  Begin
    E.AtUsed := True;
    For K := 0 To Vals.N - 1 Do
    Begin
      If K > 0 Then FinishField(E, True);
      AppendValue(E, Vals.It[K]^, True);
    End;
  End
  Else
    For K := 0 To Vals.N - 1 Do
    Begin
      If K > 0 Then FinishField(E, False);
      AppendValue(E, Vals.It[K]^, False);
    End;
  ArgsFree(Keys);
  ArgsFree(Vals);
End;

Procedure ExpandInto(Var E : TExp; Const Raw : String; InDQ : Boolean);
Var
  K, X, Len, Depth, A, B : LongInt;
  C : Char;
  DQ : Boolean;
  Name, Inner, V, UserN : String;
  Sec0 : LongInt;
  AtSec : Boolean;
  Buf : LongInt;
  E2 : TExp;
Begin
  DQ := InDQ;
  K := 1;
  Sec0 := E.Added;
  AtSec := False;
  While K <= Length(Raw) Do
  Begin
    C := Raw[K];
    If C = '\' Then
    Begin
      Inc(K);
      If K <= Length(Raw) Then
      Begin
        If DQ And Not (Raw[K] In ['$', '`', '"', '\']) Then
          AddChar(E, '\', True);
        AddChar(E, Raw[K], True);
      End
      Else AddChar(E, '\', True);
    End
    Else If (C = '''') And Not DQ Then
    Begin
      E.Have := True;
      Inc(K);
      While (K <= Length(Raw)) And (Raw[K] <> '''') Do
      Begin
        AddChar(E, Raw[K], True);
        Inc(K);
      End;
    End
    Else If BashMode And ((C = '<') Or (C = '>')) And Not DQ And
            (K + 8 <= Length(Raw)) And (Raw[K + 1] = '$') And
            (Raw[K + 2] = '(') And (Raw[K + 3] = #1) Then
    Begin
      { <(cmd) >(cmd) : tube nomme /dev/fd/N }
      X := (Ord(Raw[K + 4]) - 48) * 1000 + (Ord(Raw[K + 5]) - 48) * 100 +
           (Ord(Raw[K + 6]) - 48) * 10 + Ord(Raw[K + 7]) - 48;
      V := ProcSubst(X, C = '<');
      For Len := 1 To Length(V) Do AddChar(E, V[Len], True);
      K := K + 8;
    End
    Else If C = '"' Then
    Begin
      If DQ And (Not InDQ) Then
      Begin
        { fermeture : un champ vide entre guillemets existe }
        If (E.Added = Sec0) And Not AtSec Then E.Have := True;
        DQ := False;
      End
      Else If Not DQ Then
      Begin
        DQ := True;
        Sec0 := E.Added;
        AtSec := False;
      End
      Else AddChar(E, '"', True);
    End
    Else If C = '$' Then
    Begin
      Inc(K);
      If K > Length(Raw) Then AddChar(E, '$', DQ)
      Else If BashMode And (Raw[K] = '''') And Not DQ Then
      Begin
        { $'...' : echappements du langage C }
        Inc(K);
        While (K <= Length(Raw)) And (Raw[K] <> '''') Do
        Begin
          If Raw[K] = '\' Then
          Begin
            Inc(K);
            If K > Length(Raw) Then Break;
            Case Raw[K] Of
              'n' : AddChar(E, #10, True);
              't' : AddChar(E, #9, True);
              'r' : AddChar(E, #13, True);
              'a' : AddChar(E, #7, True);
              'b' : AddChar(E, #8, True);
              'e', 'E' : AddChar(E, #27, True);
              'f' : AddChar(E, #12, True);
              'v' : AddChar(E, #11, True);
              '0'..'7' :
                Begin
                  X := 0;
                  Len := 0;
                  While (K <= Length(Raw)) And (Len < 3) And
                        (Raw[K] In ['0'..'7']) Do
                  Begin
                    X := X * 8 + Ord(Raw[K]) - 48;
                    Inc(K);
                    Inc(Len);
                  End;
                  Dec(K);
                  AddChar(E, Chr(X And 255), True);
                End;
              'x' :
                Begin
                  X := 0;
                  Len := 0;
                  Inc(K);
                  While (K <= Length(Raw)) And (Len < 2) And
                        (UpCase(Raw[K]) In ['0'..'9', 'A'..'F']) Do
                  Begin
                    If Raw[K] <= '9' Then X := X * 16 + Ord(Raw[K]) - 48
                    Else X := X * 16 + Ord(UpCase(Raw[K])) - 55;
                    Inc(K);
                    Inc(Len);
                  End;
                  Dec(K);
                  AddChar(E, Chr(X And 255), True);
                End;
              'c' :
                Begin
                  Inc(K);
                  If K <= Length(Raw) Then
                    AddChar(E, Chr(Ord(UpCase(Raw[K])) And 31), True);
                End;
            Else
              AddChar(E, Raw[K], True);
            End;
          End
          Else AddChar(E, Raw[K], True);
          Inc(K);
        End;
        E.Have := True;
      End
      Else If Raw[K] = '(' Then
      Begin
        If (K + 1 <= Length(Raw)) And (Raw[K + 1] = '(') Then
        Begin
          { arithmetique : $(( ... )) }
          Depth := 2;
          A := K + 2;
          B := A;
          While (B <= Length(Raw)) And (Depth > 0) Do
          Begin
            If Raw[B] = '(' Then Inc(Depth)
            Else If Raw[B] = ')' Then Dec(Depth);
            Inc(B);
          End;
          Inner := Copy(Raw, A, B - A - 2);
          ExpInit(E2, Nil, True);
          ExpandInto(E2, ' ' + Inner, False);
          AppendValue(E, IntStr(ArithEval(E2.S)), DQ);
          K := B - 1;
        End
        Else If (K + 1 <= Length(Raw)) And (Raw[K + 1] = #1) Then
        Begin
          X := (Ord(Raw[K + 2]) - 48) * 1000 + (Ord(Raw[K + 3]) - 48) * 100 +
               (Ord(Raw[K + 4]) - 48) * 10 + Ord(Raw[K + 5]) - 48;
          Buf := RunSubst(X, Len);
          AppendBuf(E, Buf, Len, DQ);
          HeapFree(1, 0, Buf);
          K := K + 6;
        End
        Else AddChar(E, '$', DQ);
      End
      Else If Raw[K] = '{' Then
      Begin
        Depth := 1;
        A := K + 1;
        B := A;
        While (B <= Length(Raw)) And (Depth > 0) Do
        Begin
          If Raw[B] = '{' Then Inc(Depth)
          Else If Raw[B] = '}' Then Dec(Depth)
          Else If Raw[B] = '\' Then Inc(B)
          Else If Raw[B] = '''' Then
          Begin
            Inc(B);
            While (B <= Length(Raw)) And (Raw[B] <> '''') Do Inc(B);
          End;
          Inc(B);
        End;
        Inner := Copy(Raw, A, B - A - 1);
        If (Inner = '@') Or (Inner = '*') Then AtSec := True;
        If BashMode And (Length(Inner) > 3) And
           ((Copy(Inner, Length(Inner) - 2, 3) = '[@]') Or
            (Copy(Inner, Length(Inner) - 2, 3) = '[*]')) Then AtSec := True;
        ParamExpand(E, Inner, DQ);
        K := B - 1;
      End
      Else If IsNameCh(Ord(Raw[K])) And ((Raw[K] < '0') Or (Raw[K] > '9')) Then
      Begin
        Name := '';
        While (K <= Length(Raw)) And IsNameCh(Ord(Raw[K])) Do
        Begin
          Name := Name + Raw[K];
          Inc(K);
        End;
        Dec(K);
        If Not GetVar(Name, V) And OptU Then
        Begin
          ShErr(Name + ': ' + Msg(mUnbound));
          CleanExit(1);
        End;
        AppendValue(E, V, DQ);
      End
      Else If (Raw[K] = '@') And DQ Then
      Begin
        AtSec := True;
        E.AtUsed := True;
        For X := 1 To NPos Do
        Begin
          If X > 1 Then FinishField(E, True);
          AppendValue(E, PosGet(X), True);
        End;
      End
      Else If (Raw[K] = '*') And DQ Then
      Begin
        V := IfsOf;
        If V = '' Then C := #0 Else C := V[1];
        For X := 1 To NPos Do
        Begin
          If (X > 1) And (C <> #0) Then AddChar(E, C, True);
          AppendValue(E, PosGet(X), True);
        End;
        If NPos = 0 Then AtSec := False;
      End
      Else If (Raw[K] = '@') Or (Raw[K] = '*') Then
      Begin
        For X := 1 To NPos Do
        Begin
          If X > 1 Then FinishField(E, False);
          AppendValue(E, PosGet(X), False);
        End;
      End
      Else If (Raw[K] In ['0'..'9', '?', '$', '!', '#', '-']) Then
      Begin
        Name := Raw[K];
        GetVar(Name, V);
        AppendValue(E, V, DQ);
      End
      Else AddChar(E, '$', DQ);
    End
    Else If (C = '~') And (K = 1) And Not DQ Then
    Begin
      A := K + 1;
      While (A <= Length(Raw)) And (Raw[A] <> '/') And (Raw[A] <> '"') And
            (Raw[A] <> '''') Do Inc(A);
      UserN := Copy(Raw, K + 1, A - K - 1);
      V := HomeOf(UserN);
      If (V = '') And (UserN <> '') Then AddChar(E, '~', True)
      Else If V = '' Then AddChar(E, '~', True)
      Else
      Begin
        For X := 1 To Length(V) Do AddChar(E, V[X], True);
        K := A - 1;
      End;
    End
    Else AddChar(E, C, DQ);
    Inc(K);
  End;
End;

{ ----- accolades : a{b,c}d, {1..5}, {a..e}, {01..10..2} ----- }

{ saute le contenu entre guillemets / ${..} / $(..) a partir de I (sur le
  caractere d'ouverture) ; rend l'indice du dernier caractere saute }
Function BraceSkip(Const R : String; I : LongInt) : LongInt;
Var C : Char; Dp : LongInt;
Begin
  C := R[I];
  If C = '\' Then
  Begin
    BraceSkip := I + 1;
    Exit;
  End;
  If C = '''' Then
  Begin
    Inc(I);
    While (I <= Length(R)) And (R[I] <> '''') Do Inc(I);
    BraceSkip := I;
    Exit;
  End;
  If C = '"' Then
  Begin
    Inc(I);
    While (I <= Length(R)) And (R[I] <> '"') Do
    Begin
      If R[I] = '\' Then Inc(I);
      Inc(I);
    End;
    BraceSkip := I;
    Exit;
  End;
  If (C = '$') And (I < Length(R)) Then
  Begin
    If R[I + 1] = '{' Then
    Begin
      Dp := 0;
      Inc(I);
      While I <= Length(R) Do
      Begin
        If R[I] = '{' Then Inc(Dp)
        Else If R[I] = '}' Then
        Begin
          Dec(Dp);
          If Dp = 0 Then Break;
        End
        Else If R[I] = '\' Then Inc(I);
        Inc(I);
      End;
      BraceSkip := I;
      Exit;
    End;
    If (R[I + 1] = '(') And (I + 7 <= Length(R)) And (R[I + 2] = #1) Then
    Begin
      BraceSkip := I + 7;
      Exit;
    End;
  End;
  BraceSkip := I;
End;

Procedure BraceSeq(Const Body : String; Var Items : TArgs; Var Ok : Boolean);
Var P1, P2, K : LongInt; A, B, Stp : String; X, Y, St, W, V : LongInt;
    Num : Boolean; Pad : Boolean; T : String; C : Char;
Begin
  Ok := False;
  P1 := Pos('..', Body);
  If P1 = 0 Then Exit;
  A := Copy(Body, 1, P1 - 1);
  T := Copy(Body, P1 + 2, 255);
  P2 := Pos('..', T);
  Stp := '';
  If P2 > 0 Then
  Begin
    B := Copy(T, 1, P2 - 1);
    Stp := Copy(T, P2 + 2, 255);
  End
  Else B := T;
  St := 1;
  If Stp <> '' Then
  Begin
    If Not StrInt(Stp, St) Then Exit;
    If St < 0 Then St := -St;
    If St = 0 Then St := 1;
  End;
  If StrInt(A, X) And StrInt(B, Y) And (A <> '') And (B <> '') Then
  Begin
    W := 0;
    Pad := False;
    If (Length(A) > 1) And
       ((A[1] = '0') Or ((A[1] = '-') And (A[2] = '0'))) Then
      Pad := True;
    If (Length(B) > 1) And
       ((B[1] = '0') Or ((B[1] = '-') And (B[2] = '0'))) Then
      Pad := True;
    If Pad Then
    Begin
      W := Length(A);
      If Length(B) > W Then W := Length(B);
    End;
    V := X;
    While True Do
    Begin
      T := IntStr(V);
      If Pad Then
        While Length(T) < W Do
          If T[1] = '-' Then T := '-0' + Copy(T, 2, 255) Else T := '0' + T;
      ArgsAdd(Items, T);
      If Items.N > 1000 Then Break;
      If X <= Y Then
      Begin
        V := V + St;
        If V > Y Then Break;
      End
      Else
      Begin
        V := V - St;
        If V < Y Then Break;
      End;
    End;
    Ok := True;
    Exit;
  End;
  If (Length(A) = 1) And (Length(B) = 1) And Not StrInt(A, X) Then
  Begin
    X := Ord(A[1]);
    Y := Ord(B[1]);
    V := X;
    While True Do
    Begin
      C := Chr(V);
      ArgsAdd(Items, C);
      If X <= Y Then
      Begin
        V := V + St;
        If V > Y Then Break;
      End
      Else
      Begin
        V := V - St;
        If V < Y Then Break;
      End;
    End;
    Ok := True;
  End;
End;

Procedure BraceExpand(Const Raw : String; Var Out : TArgs; Depth : LongInt);
Var I, J, Dp, NC, K, P0 : LongInt; C, C2 : Char;
    Commas : Array[0..63] Of LongInt;
    Pre, Post, Body : String; Items : TArgs; Ok : Boolean;
Begin
  If (Depth > 12) Or (Out.N >= MAXARGS - 8) Then
  Begin
    ArgsAdd(Out, Raw);
    Exit;
  End;
  I := 1;
  While I <= Length(Raw) Do
  Begin
    C := Raw[I];
    If (C = '\') Or (C = '''') Or (C = '"') Or (C = '$') Then
    Begin
      I := BraceSkip(Raw, I) + 1;
      Continue;
    End;
    If C = '{' Then
    Begin
      Dp := 1;
      J := I + 1;
      NC := 0;
      While (J <= Length(Raw)) And (Dp > 0) Do
      Begin
        C2 := Raw[J];
        If (C2 = '\') Or (C2 = '''') Or (C2 = '"') Or (C2 = '$') Then
          J := BraceSkip(Raw, J)
        Else If C2 = '{' Then Inc(Dp)
        Else If C2 = '}' Then Dec(Dp)
        Else If (C2 = ',') And (Dp = 1) And (NC < 63) Then
        Begin
          Commas[NC] := J;
          Inc(NC);
        End;
        If Dp > 0 Then Inc(J);
      End;
      If Dp = 0 Then
      Begin
        Pre := Copy(Raw, 1, I - 1);
        Post := Copy(Raw, J + 1, 255);
        Body := Copy(Raw, I + 1, J - I - 1);
        If NC > 0 Then
        Begin
          P0 := I + 1;
          For K := 0 To NC Do
          Begin
            If K < NC Then
              BraceExpand(Pre + Copy(Raw, P0, Commas[K] - P0) + Post, Out,
                          Depth + 1)
            Else
              BraceExpand(Pre + Copy(Raw, P0, J - P0) + Post, Out, Depth + 1);
            If K < NC Then P0 := Commas[K] + 1;
          End;
          Exit;
        End;
        ArgsInit(Items);
        BraceSeq(Body, Items, Ok);
        If Ok Then
        Begin
          For K := 0 To Items.N - 1 Do
            BraceExpand(Pre + Items.It[K]^ + Post, Out, Depth + 1);
          ArgsFree(Items);
          Exit;
        End;
        ArgsFree(Items);
      End;
    End;
    Inc(I);
  End;
  ArgsAdd(Out, Raw);
End;

Function HasBrace(Const R : String) : Boolean;
Var I : LongInt;
Begin
  HasBrace := False;
  I := 1;
  While I <= Length(R) Do
  Begin
    If (R[I] = '\') Or (R[I] = '''') Or (R[I] = '"') Or (R[I] = '$') Then
      I := BraceSkip(R, I)
    Else If R[I] = '{' Then
    Begin
      HasBrace := True;
      Exit;
    End;
    Inc(I);
  End;
End;

Procedure ExpandWord(Const Raw : String; Dst : PArgs);
Var E : TExp; B : TArgs; I : LongInt;
Begin
  If BashMode And (Pos('{', Raw) > 0) Then
    If HasBrace(Raw) Then
    Begin
      ArgsInit(B);
      BraceExpand(Raw, B, 0);
      If B.N > 1 Then
      Begin
        For I := 0 To B.N - 1 Do
        Begin
          ExpInit(E, Dst, False);
          ExpandInto(E, B.It[I]^, False);
          FinishField(E, False);
        End;
        ArgsFree(B);
        Exit;
      End;
      ArgsFree(B);
    End;
  ExpInit(E, Dst, False);
  ExpandInto(E, Raw, False);
  FinishField(E, False);
End;

Function ExpandStr(Const Raw : String) : String;
Var E : TExp;
Begin
  ExpInit(E, Nil, True);
  ExpandInto(E, Raw, False);
  ExpandStr := E.S;
End;

{ document ici : seuls $, ` et \ sont speciaux ; le texte est balaye comme
  l'interieur de guillemets et ecrit developpe sur Fd }
Procedure DocFlush(Fd : LongInt; Var W : String);
Var E : TExp;
Begin
  If W = '' Then Exit;
  ExpInit(E, Nil, True);
  ExpandInto(E, W, True);
  SysPut(Fd, E.S);
  W := '';
End;

Procedure DocExpandTo(Fd, Addr, Len : LongInt);
Var Saved : TIn; W : String; C, C2 : LongInt;
Begin
  Saved := CurIn;
  InOpenMem(CurIn, Addr, Len);
  W := '';
  While True Do
  Begin
    C := InGetC;
    If C < 0 Then Break;
    If C = 36 Then ScanDollar(W)
    Else If C = 96 Then W := W + SubPlaceholder(ScanBackquote)
    Else If C = 92 Then
    Begin
      C2 := InGetC;
      If C2 = 10 Then Continue;
      If (C2 = 36) Or (C2 = 96) Or (C2 = 92) Then
      Begin
        W := W + '\' + Chr(C2);
      End
      Else
      Begin
        W := W + '\\';
        If C2 >= 0 Then InUnget(C2);
      End;
    End
    Else W := W + Chr(C);
    If (Length(W) > 180) Or (C = 10) Then DocFlush(Fd, W);
  End;
  DocFlush(Fd, W);
  InClose(CurIn);
  CurIn := Saved;
End;

{ ---------- noms de fichiers : * ? [..] ---------- }

Function StatKind(Const P : String) : LongInt;
{ 0 inexistant, 1 repertoire, 2 autre }
Var St : TSysStat;
Begin
  If SysStat(P, St) < 0 Then
  Begin
    If SysLStat(P, St) < 0 Then StatKind := 0 Else StatKind := 2;
    Exit;
  End;
  If (St.Mode And S_IFMT) = S_IFDIR Then StatKind := 1 Else StatKind := 2;
End;

Procedure GlobRec(Const Prefix, Pat, PF : String; Start : LongInt;
    Dst : PArgs; Var Found : LongInt);
Var
  EndC, Next : LongInt; Comp, CF, Name, Path, Dir : String;
  Wild, Last : Boolean; D, Ino, K : LongInt; Tmp : TArgs;
  Hidden : Boolean;
Begin
  If Start > Length(Pat) Then
  Begin
    Exit;
  End;
  EndC := Start;
  While (EndC <= Length(Pat)) And (Pat[EndC] <> '/') Do Inc(EndC);
  Comp := Copy(Pat, Start, EndC - Start);
  CF := Copy(PF, Start, EndC - Start);
  Next := EndC + 1;
  Last := EndC > Length(Pat);
  If Comp = '' Then
  Begin
    { barre initiale ou doublee }
    If Last Then
    Begin
      Exit;
    End;
    If Start = 1 Then GlobRec('/', Pat, PF, Next, Dst, Found)
    Else GlobRec(Prefix, Pat, PF, Next, Dst, Found);
    Exit;
  End;
  Wild := HasGlob(Comp, CF);
  If Not Wild Then
  Begin
    Name := '';
    For K := 1 To Length(Comp) Do Name := Name + Comp[K];
    Path := Prefix + Name;
    If Last Then
    Begin
      If StatKind(Path) <> 0 Then
      Begin
        ArgsAdd(Dst^, Path);
        Inc(Found);
      End;
    End
    Else If StatKind(Path) = 1 Then
      GlobRec(Path + '/', Pat, PF, Next, Dst, Found);
    Exit;
  End;
  If Prefix = '' Then Dir := '.' Else Dir := Prefix;
  D := SysOpenDir(Dir);
  If D < 0 Then Exit;
  ArgsInit(Tmp);
  While SysReadDir(D, Name, Ino) Do
  Begin
    Hidden := (Name <> '') And (Name[1] = '.');
    If Hidden And Not DotGlob And ((Comp[1] <> '.') Or (CF[1] = '1')) Then
      Continue;
    If (Name = '.') Or (Name = '..') Then Continue;
    If PatMatch(Comp, CF, Name) Then ArgsAdd(Tmp, Name);
  End;
  SysCloseDir(D);
  ArgsSort(Tmp, 0);
  For K := 0 To Tmp.N - 1 Do
  Begin
    Path := Prefix + Tmp.It[K]^;
    If Last Then
    Begin
      ArgsAdd(Dst^, Path);
      Inc(Found);
    End
    Else If StatKind(Path) = 1 Then
      GlobRec(Path + '/', Pat, PF, Next, Dst, Found);
  End;
  ArgsFree(Tmp);
End;

Procedure GlobField(Const S, F : String; Dst : PArgs);
Var Found, K : LongInt; U : String;
Begin
  Found := 0;
  GlobRec('', S, F, 1, Dst, Found);
  If Found = 0 Then
  Begin
    If NullGlob Then Exit;
    If FailGlob Then
    Begin
      ShErr('no match: ' + S);
      Exit;
    End;
    { aucun fichier : le mot reste tel quel }
    U := S;
    ArgsAdd(Dst^, U);
  End;
End;

{$I REGEX.INC}

{ ---------- arithmetique : $(( )), (( )), let ---------- }

Var
  ArS : String;
  ArP : LongInt;
  ArErr : Boolean;
  ArNoEval : LongInt;                  { > 0 : sans effet (branche non prise) }
  ArDepth : LongInt;
  ArFailed : Boolean;                  { derniere evaluation en erreur }

Function ArComma : LongInt; Forward;
Function ArTernary : LongInt; Forward;
Function ElemName(Const N, Sub : String) : String; Forward;

Procedure ArSkip;
Begin
  While (ArP <= Length(ArS)) And ((ArS[ArP] = ' ') Or (ArS[ArP] = #9) Or
        (ArS[ArP] = #10)) Do
    Inc(ArP);
End;

Function ArDigit(C : Char) : LongInt;
Begin
  ArDigit := -1;
  If (C >= '0') And (C <= '9') Then ArDigit := Ord(C) - 48
  Else If (C >= 'a') And (C <= 'z') Then ArDigit := Ord(C) - 87
  Else If (C >= 'A') And (C <= 'Z') Then ArDigit := Ord(C) - 29
  Else If C = '@' Then ArDigit := 62
  Else If C = '_' Then ArDigit := 63;
End;

{ valeur numerique du texte d'une variable (evaluee comme expression) }
Function ArValueOf(Const Nm : String) : LongInt;
Var T : String; V : LongInt;
Begin
  ArValueOf := 0;
  If Not GetVar(Nm, T) Then
  Begin
    If OptU Then
    Begin
      ShErr(Nm + ': ' + Msg(mUnbound));
      ArErr := True;
    End;
    Exit;
  End;
  If T = '' Then Exit;
  If StrInt(T, V) And ((T[1] <> '0') Or (Length(T) = 1)) Then
  Begin
    ArValueOf := V;
    Exit;
  End;
  If ArDepth > 12 Then
  Begin
    ArErr := True;
    Exit;
  End;
  Inc(ArDepth);
  ArValueOf := ArithEval(T);
  Dec(ArDepth);
End;

{ lit un nombre : decimal, 0x.., 0.. (octal), base#chiffres }
Function ArNumber : LongInt;
Var V, Base, D, Start : LongInt; C : Char;
Begin
  V := 0;
  Start := ArP;
  If (ArS[ArP] = '0') And (ArP < Length(ArS)) And
     ((ArS[ArP + 1] = 'x') Or (ArS[ArP + 1] = 'X')) Then
  Begin
    ArP := ArP + 2;
    While (ArP <= Length(ArS)) And (ArDigit(ArS[ArP]) >= 0) And
          (ArDigit(ArS[ArP]) < 16) Do
    Begin
      V := V * 16 + ArDigit(ArS[ArP]);
      Inc(ArP);
    End;
    ArNumber := V;
    Exit;
  End;
  While (ArP <= Length(ArS)) And (ArS[ArP] >= '0') And (ArS[ArP] <= '9') Do
  Begin
    V := V * 10 + Ord(ArS[ArP]) - 48;
    Inc(ArP);
  End;
  If (ArP <= Length(ArS)) And (ArS[ArP] = '#') And (V >= 2) And (V <= 64) Then
  Begin
    Base := V;
    V := 0;
    Inc(ArP);
    While (ArP <= Length(ArS)) And (ArDigit(ArS[ArP]) >= 0) And
          (ArDigit(ArS[ArP]) < Base) Do
    Begin
      V := V * Base + ArDigit(ArS[ArP]);
      Inc(ArP);
    End;
    ArNumber := V;
    Exit;
  End;
  If (ArS[Start] = '0') And (Start < ArP - 1) Then
  Begin
    { octal }
    V := 0;
    D := Start;
    While D < ArP Do
    Begin
      C := ArS[D];
      If C > '7' Then ArErr := True;
      V := V * 8 + Ord(C) - 48;
      Inc(D);
    End;
  End;
  ArNumber := V;
End;

{ operateur d'affectation en ArP ? rend sa longueur (0 : aucun) et l'op }
Function ArAssignOp(Var Op : String) : LongInt;
Var C2, C3 : Char; L : LongInt;
Begin
  ArAssignOp := 0;
  Op := '';
  If ArP > Length(ArS) Then Exit;
  If ArP < Length(ArS) Then C2 := ArS[ArP + 1] Else C2 := #0;
  If ArP + 1 < Length(ArS) Then C3 := ArS[ArP + 2] Else C3 := #0;
  Case ArS[ArP] Of
    '=' : If C2 <> '=' Then Begin Op := '='; ArAssignOp := 1; End;
    '+', '-', '*', '/', '%', '&', '^', '|' :
      If C2 = '=' Then Begin Op := ArS[ArP]; ArAssignOp := 2; End;
    '<' : If (C2 = '<') And (C3 = '=') Then
          Begin Op := '<<'; ArAssignOp := 3; End;
    '>' : If (C2 = '>') And (C3 = '=') Then
          Begin Op := '>>'; ArAssignOp := 3; End;
  End;
  If (Op = '*') And False Then L := 0;
End;

Function ArApply(Const Op : String; L, R : LongInt) : LongInt;
Begin
  ArApply := R;
  If Op = '+' Then ArApply := L + R
  Else If Op = '-' Then ArApply := L - R
  Else If Op = '*' Then ArApply := L * R
  Else If (Op = '/') Or (Op = '%') Then
  Begin
    If R = 0 Then
    Begin
      If ArNoEval = 0 Then
      Begin
        ShErr(Msg(mDivZero));
        ArErr := True;
      End;
      ArApply := 0;
      Exit;
    End;
    If Op = '/' Then ArApply := L Div R Else ArApply := L Mod R;
  End
  Else If Op = '&' Then ArApply := L And R
  Else If Op = '|' Then ArApply := L Or R
  Else If Op = '^' Then ArApply := L Xor R
  Else If Op = '<<' Then ArApply := L Shl R
  Else If Op = '>>' Then ArApply := L Shr R;
End;

Function ArUnary : LongInt;
Var V, K, Old, L, Depth : LongInt; N, Sub, Nm, Op : String; C : Char;
Begin
  ArSkip;
  ArUnary := 0;
  If ArP > Length(ArS) Then
  Begin
    ArErr := True;
    Exit;
  End;
  C := ArS[ArP];
  If C = '(' Then
  Begin
    Inc(ArP);
    V := ArComma;
    ArSkip;
    If (ArP <= Length(ArS)) And (ArS[ArP] = ')') Then Inc(ArP)
    Else ArErr := True;
    ArUnary := V;
    Exit;
  End;
  If (C = '+') Or (C = '-') Then
  Begin
    If (ArP < Length(ArS)) And (ArS[ArP + 1] = C) Then
    Begin
      { ++x / --x }
      ArP := ArP + 2;
      ArSkip;
      N := '';
      While (ArP <= Length(ArS)) And IsNameCh(Ord(ArS[ArP])) Do
      Begin
        N := N + ArS[ArP];
        Inc(ArP);
      End;
      Sub := '';
      If (ArP <= Length(ArS)) And (ArS[ArP] = '[') Then
      Begin
        Depth := 1;
        K := ArP + 1;
        While (K <= Length(ArS)) And (Depth > 0) Do
        Begin
          If ArS[K] = '[' Then Inc(Depth)
          Else If ArS[K] = ']' Then Dec(Depth);
          Inc(K);
        End;
        Sub := Copy(ArS, ArP + 1, K - ArP - 2);
        ArP := K;
        Nm := ElemName(N, Sub);
      End
      Else Nm := N;
      If N = '' Then
      Begin
        ArErr := True;
        Exit;
      End;
      V := ArValueOf(Nm);
      If C = '+' Then Inc(V) Else Dec(V);
      If ArNoEval = 0 Then SetVar(Nm, IntStr(V));
      ArUnary := V;
      Exit;
    End;
    Inc(ArP);
    V := ArUnary;
    If C = '-' Then ArUnary := -V Else ArUnary := V;
    Exit;
  End;
  If C = '!' Then
  Begin
    Inc(ArP);
    V := ArUnary;
    If V = 0 Then ArUnary := 1 Else ArUnary := 0;
    Exit;
  End;
  If C = '~' Then
  Begin
    Inc(ArP);
    V := ArUnary;
    ArUnary := V Xor -1;
    Exit;
  End;
  If (C >= '0') And (C <= '9') Then
  Begin
    ArUnary := ArNumber;
    Exit;
  End;
  If IsNameCh(Ord(C)) Then
  Begin
    N := '';
    While (ArP <= Length(ArS)) And IsNameCh(Ord(ArS[ArP])) Do
    Begin
      N := N + ArS[ArP];
      Inc(ArP);
    End;
    Nm := N;
    If (ArP <= Length(ArS)) And (ArS[ArP] = '[') Then
    Begin
      Depth := 1;
      K := ArP + 1;
      While (K <= Length(ArS)) And (Depth > 0) Do
      Begin
        If ArS[K] = '[' Then Inc(Depth)
        Else If ArS[K] = ']' Then Dec(Depth);
        Inc(K);
      End;
      Sub := Copy(ArS, ArP + 1, K - ArP - 2);
      ArP := K;
      Nm := ElemName(N, Sub);
    End;
    ArSkip;
    { affectation }
    L := ArAssignOp(Op);
    If L > 0 Then
    Begin
      ArP := ArP + L;
      V := ArTernary;
      If Op <> '=' Then V := ArApply(Op, ArValueOf(Nm), V);
      If ArNoEval = 0 Then
      Begin
        If Not SetVar(Nm, IntStr(V)) Then ArErr := True;
      End;
      ArUnary := V;
      Exit;
    End;
    { x++ x-- }
    If (ArP < Length(ArS)) And ((ArS[ArP] = '+') Or (ArS[ArP] = '-')) And
       (ArS[ArP + 1] = ArS[ArP]) Then
    Begin
      Old := ArValueOf(Nm);
      If ArNoEval = 0 Then
        If ArS[ArP] = '+' Then SetVar(Nm, IntStr(Old + 1))
        Else SetVar(Nm, IntStr(Old - 1));
      ArP := ArP + 2;
      ArUnary := Old;
      Exit;
    End;
    ArUnary := ArValueOf(Nm);
    Exit;
  End;
  ArErr := True;
  Inc(ArP);
End;

Function ArPow : LongInt;
Var L, R, V, K : LongInt;
Begin
  L := ArUnary;
  ArSkip;
  If (ArP < Length(ArS)) And (ArS[ArP] = '*') And (ArS[ArP + 1] = '*') Then
  Begin
    ArP := ArP + 2;
    R := ArPow;
    V := 1;
    If R < 0 Then
    Begin
      If ArNoEval = 0 Then
      Begin
        ShErr('exponent less than 0');
        ArErr := True;
      End;
      ArPow := 0;
      Exit;
    End;
    For K := 1 To R Do V := V * L;
    ArPow := V;
    Exit;
  End;
  ArPow := L;
End;

{ niveaux : 1 || ; 2 && ; 3 | ; 4 ^ ; 5 & ; 6 == != ; 7 < <= > >= ;
  8 << >> ; 9 + - ; 10 * / % }
Function ArExpr(MinPrec : LongInt) : LongInt;
Var L, R, Prec : LongInt; C, C2, C3 : Char; Op : String;
Begin
  L := ArPow;
  While True Do
  Begin
    ArSkip;
    If ArP > Length(ArS) Then Break;
    C := ArS[ArP];
    If ArP < Length(ArS) Then C2 := ArS[ArP + 1] Else C2 := #0;
    If ArP + 1 < Length(ArS) Then C3 := ArS[ArP + 2] Else C3 := #0;
    Op := C;
    If (C2 = C) And (C In ['|', '&', '<', '>', '=']) Then Op := C + C2
    Else If (C2 = '=') And (C In ['!', '<', '>']) Then Op := C + C2;
    Prec := 0;
    If Op = '||' Then Prec := 1
    Else If Op = '&&' Then Prec := 2
    Else If Op = '|' Then Prec := 3
    Else If Op = '^' Then Prec := 4
    Else If Op = '&' Then Prec := 5
    Else If (Op = '==') Or (Op = '!=') Then Prec := 6
    Else If (Op = '<') Or (Op = '<=') Or (Op = '>') Or (Op = '>=') Then
      Prec := 7
    Else If (Op = '<<') Or (Op = '>>') Then Prec := 8
    Else If (Op = '+') Or (Op = '-') Then Prec := 9
    Else If ((Op = '*') And (C2 <> '*')) Or (Op = '/') Or (Op = '%') Then
      Prec := 10;
    { operateur compose (+= <<= ...) : laisse a l'affectation }
    If (Prec > 0) And (Length(Op) = 1) And (C2 = '=') And
       (C In ['+', '-', '*', '/', '%', '&', '^', '|']) Then Prec := 0;
    If (Prec > 0) And (Length(Op) = 2) And (C3 = '=') And
       ((Op = '<<') Or (Op = '>>')) Then Prec := 0;
    If (Prec = 0) Or (Prec < MinPrec) Then Break;
    ArP := ArP + Length(Op);
    If (Op = '||') And (L <> 0) Then
    Begin
      Inc(ArNoEval);
      R := ArExpr(Prec + 1);
      Dec(ArNoEval);
      L := 1;
      Continue;
    End;
    If (Op = '&&') And (L = 0) Then
    Begin
      Inc(ArNoEval);
      R := ArExpr(Prec + 1);
      Dec(ArNoEval);
      Continue;
    End;
    R := ArExpr(Prec + 1);
    If Op = '||' Then L := Ord((L <> 0) Or (R <> 0))
    Else If Op = '&&' Then L := Ord((L <> 0) And (R <> 0))
    Else If Op = '==' Then L := Ord(L = R)
    Else If Op = '!=' Then L := Ord(L <> R)
    Else If Op = '<' Then L := Ord(L < R)
    Else If Op = '<=' Then L := Ord(L <= R)
    Else If Op = '>' Then L := Ord(L > R)
    Else If Op = '>=' Then L := Ord(L >= R)
    Else L := ArApply(Op, L, R);
  End;
  ArExpr := L;
End;

Function ArTernary : LongInt;
Var C, A, B : LongInt;
Begin
  C := ArExpr(1);
  ArSkip;
  If (ArP <= Length(ArS)) And (ArS[ArP] = '?') Then
  Begin
    Inc(ArP);
    If C = 0 Then Inc(ArNoEval);
    A := ArTernary;
    If C = 0 Then Dec(ArNoEval);
    ArSkip;
    If (ArP <= Length(ArS)) And (ArS[ArP] = ':') Then Inc(ArP)
    Else ArErr := True;
    If C <> 0 Then Inc(ArNoEval);
    B := ArTernary;
    If C <> 0 Then Dec(ArNoEval);
    If C <> 0 Then ArTernary := A Else ArTernary := B;
    Exit;
  End;
  ArTernary := C;
End;

Function ArComma : LongInt;
Var V : LongInt;
Begin
  V := ArTernary;
  ArSkip;
  While (ArP <= Length(ArS)) And (ArS[ArP] = ',') Do
  Begin
    Inc(ArP);
    V := ArTernary;
    ArSkip;
  End;
  ArComma := V;
End;

Function ArithEval(Const S : String) : LongInt;
Var SaveS : String; SaveP, SaveNo : LongInt; V : LongInt; SaveErr : Boolean;
Begin
  SaveS := ArS;
  SaveP := ArP;
  SaveNo := ArNoEval;
  SaveErr := ArErr;
  ArS := S;
  ArP := 1;
  ArErr := False;
  ArNoEval := 0;
  ArSkip;
  If ArP > Length(ArS) Then V := 0
  Else V := ArComma;
  ArSkip;
  If ArP <= Length(ArS) Then ArErr := True;
  If ArErr Then ShErr(Msg(mSyntax) + ': ' + S);
  ArFailed := ArErr;
  ArS := SaveS;
  ArP := SaveP;
  ArNoEval := SaveNo;
  ArErr := SaveErr;
  ArithEval := V;
End;

{ nom interne d'un element de tableau : nom[cle] (cle numerique normalisee
  pour un tableau indexe, texte pour un tableau associatif) }
Function ElemName(Const N0, Sub : String) : String;
Var K, I, Mx, X : LongInt; S, N : String;
Begin
  N := ResolveRef(N0);
  If IsAssocName(N) Then
  Begin
    ElemName := N + '[' + ExpandStr(Sub) + ']';
    Exit;
  End;
  S := ExpandStr(Sub);
  K := ArithEval(S);
  If K < 0 Then
  Begin
    { indice negatif : depuis le dernier element }
    Mx := -1;
    For I := 0 To MAXVARS - 1 Do
      If Vars[I].Used And (Copy(Vars[I].Name, 1, Length(N) + 1) = N + '[') Then
        If StrInt(Copy(Vars[I].Name, Length(N) + 2,
                       Length(Vars[I].Name) - Length(N) - 2), X) Then
          If X > Mx Then Mx := X;
    K := Mx + 1 + K;
    If K < 0 Then K := 0;
  End;
  ElemName := N + '[' + IntStr(K) + ']';
End;

{ ---------- processus, travaux, terminal ---------- }

Var
  LastLine : String;
  InCond : LongInt;           { > 0 : dans une condition (set -e inactif) }
  ShellTerm : TSysTermios;
  HaveShellTerm : Boolean;

Procedure JobsInit;
Var I : LongInt;
Begin
  For I := 0 To MAXJOBS - 1 Do Jobs[I].State := jFree;
End;

Function JobNew(Const Cmd : String) : LongInt;
Var I : LongInt;
Begin
  For I := 0 To MAXJOBS - 1 Do
    If Jobs[I].State = jFree Then
    Begin
      Jobs[I].State := jRunning;
      Jobs[I].Pgid := 0;
      Jobs[I].NProc := 0;
      Jobs[I].NDone := 0;
      Jobs[I].Status := 0;
      Jobs[I].Cmd := Copy(Cmd, 1, 100);
      Jobs[I].Notified := False;
      JobNew := I;
      Exit;
    End;
  JobNew := -1;
End;

Procedure JobAddPid(J, Pid : LongInt);
Begin
  If J < 0 Then Exit;
  If Jobs[J].NProc < 16 Then
  Begin
    Jobs[J].Pids[Jobs[J].NProc] := Pid;
    Jobs[J].Dones[Jobs[J].NProc] := False;
    Inc(Jobs[J].NProc);
  End;
  If Jobs[J].Pgid = 0 Then Jobs[J].Pgid := Pid;
End;

Function StatusOf(St : LongInt) : LongInt;
Begin
  If SysWIfExited(St) Then StatusOf := SysWExitStatus(St)
  Else If SysWIfSignaled(St) Then StatusOf := 128 + SysWTermSig(St)
  Else StatusOf := 128 + SysWStopSig(St);
End;

{ met a jour la table avec l'etat d'un processus ; rend le numero du travail }
Function JobUpdate(Pid, St : LongInt) : LongInt;
Var J, K : LongInt;
Begin
  JobUpdate := -1;
  For J := 0 To MAXJOBS - 1 Do
    If Jobs[J].State <> jFree Then
      For K := 0 To Jobs[J].NProc - 1 Do
        If Jobs[J].Pids[K] = Pid Then
        Begin
          JobUpdate := J;
          If SysWIfStopped(St) Then
          Begin
            Jobs[J].State := jStopped;
            Jobs[J].Status := StatusOf(St);
            Jobs[J].Notified := False;
          End
          Else
          Begin
            If Not Jobs[J].Dones[K] Then
            Begin
              Jobs[J].Dones[K] := True;
              Inc(Jobs[J].NDone);
            End;
            Jobs[J].PStat[K] := StatusOf(St);
            If K = Jobs[J].NProc - 1 Then Jobs[J].Status := StatusOf(St);
            If Jobs[J].NDone >= Jobs[J].NProc Then Jobs[J].State := jDone
            Else If Jobs[J].State = jStopped Then Jobs[J].State := jRunning;
          End;
          Exit;
        End;
End;

Procedure ShowJob(J : LongInt; Cur : Boolean);
Var S, Mk : String;
Begin
  If Cur Then Mk := '+' Else Mk := ' ';
  Case Jobs[J].State Of
    jStopped : S := Msg(mStopped);
    jDone : S := Msg(mDone);
  Else S := Msg(mRunning);
  End;
  Out(1, '[' + IntStr(J + 1) + ']' + Mk + '  ' + S + #9 + Jobs[J].Cmd + #10);
End;

{ recolte les fils termines ou arretes sans attendre ; Report : annonces }
Procedure ReapJobs(Report : Boolean);
Var R, St, J : LongInt;
Begin
  While True Do
  Begin
    R := SysWaitPid(-1, St, WNOHANG Or WUNTRACED);
    If R <= 0 Then Break;
    J := JobUpdate(R, St);
  End;
  If Report And Interactive Then
    For J := 0 To MAXJOBS - 1 Do
      If (Jobs[J].State = jDone) And (Not Jobs[J].Notified) Then
      Begin
        ShowJob(J, False);
        Jobs[J].State := jFree;
      End;
End;

Procedure GiveTerm(Pgrp : LongInt);
Begin
  If JobCtl And (TtyFd >= 0) Then SysTcSetPgrp(TtyFd, Pgrp);
End;

{ attend la fin (ou l'arret) du travail J au premier plan }
Function JobWait(J : LongInt) : LongInt;
Var R, St, K : LongInt;
Begin
  While Jobs[J].State = jRunning Do
  Begin
    R := SysWaitPid(-1, St, WUNTRACED);
    If R < 0 Then
    Begin
      If SysErrno = 4 Then
      Begin
        If IntFlag <> 0 Then
        Begin
          { Ctrl-C au clavier : le noyau l'a envoye aussi au groupe }
          Continue;
        End;
        Continue;
      End;
      Jobs[J].State := jDone;
      Break;
    End;
    K := JobUpdate(R, St);
  End;
  JobWait := Jobs[J].Status;
  If JobCtl Then
  Begin
    GiveTerm(ShellPgrp);
    If HaveShellTerm Then SysTcSetAttr(TtyFd, 1, ShellTerm);
  End;
  If Jobs[J].State = jStopped Then
  Begin
    If Interactive Then
    Begin
      Out(1, #10);
      ShowJob(J, True);
    End;
    Jobs[J].Notified := True;
  End
  Else Jobs[J].State := jFree;
End;

{ reinitialise les signaux dans un fils }
Procedure ChildSignals;
Begin
  SysSigAction(SIGINT, SIG_DFL, 0);
  SysSigAction(SIGQUIT, SIG_DFL, 0);
  SysSigAction(SIGTSTP, SIG_DFL, 0);
  SysSigAction(SIGTTIN, SIG_DFL, 0);
  SysSigAction(SIGTTOU, SIG_DFL, 0);
  SysSigAction(SIGPIPE, SIG_DFL, 0);
  SysSigAction(SIGCHLD, SIG_DFL, 0);
  SysSigAction(SIGTERM, SIG_DFL, 0);
  SysSigAction(SIGHUP, SIG_DFL, 0);
End;

{ fork ; dans le fils : groupe de processus, signaux ; Pgid : groupe du
  travail (0 : nouveau groupe = ce processus) }
Function ForkProc(Pgid : LongInt; Fg : Boolean) : LongInt;
Var Pid : LongInt;
Begin
  Pid := SysFork;
  If Pid < 0 Then
  Begin
    ShErr(Msg(mCantFork));
    ForkProc := -1;
    Exit;
  End;
  If Pid = 0 Then
  Begin
    { fils }
    If JobCtl Then
    Begin
      SysSetPgid(0, Pgid);
      If Fg And (TtyFd >= 0) Then SysTcSetPgrp(TtyFd, SysGetPgrp);
    End;
    ChildSignals;
    If Not Fg And Not JobCtl Then
    Begin
      SysSigAction(SIGINT, SIG_IGN, 0);
      SysSigAction(SIGQUIT, SIG_IGN, 0);
    End;
    JobCtl := False;
    Interactive := False;
    CurIn.Inter := False;
    SubDepth := SubDepth + 1;
    TrapAny := 0;
    ForkProc := 0;
    Exit;
  End;
  If JobCtl Then
  Begin
    If Pgid = 0 Then SysSetPgid(Pid, Pid) Else SysSetPgid(Pid, Pgid);
  End;
  ForkProc := Pid;
End;

{ ---------- redirections ---------- }

Type
  TSaved = Record
    N : LongInt;
    Fd : Array[0..MAXREDIR] Of LongInt;
    Cp : Array[0..MAXREDIR] Of LongInt;
  End;
  PSaved = ^TSaved;

Function DupHigh(Fd : LongInt) : LongInt;
Var R : LongInt;
Begin
  R := SysFcntl(Fd, 0, 10);
  If R >= 0 Then SysFcntl(R, 2, 1);
  DupHigh := R;
End;

{ document ici : rend le descripteur de lecture d'un tube alimente par un fils }
Function HereDocFd(R : PRedir) : LongInt;
Var Fds : Array[0..1] Of LongInt; Pid, P, K, E : LongInt; Line : String;
    C : LongInt; Raw : String;
Begin
  HereDocFd := -1;
  If SysPipe(Fds[0]) < 0 Then Exit;
  Pid := SysFork;
  If Pid < 0 Then
  Begin
    SysClose(Fds[0]);
    SysClose(Fds[1]);
    Exit;
  End;
  If Pid = 0 Then
  Begin
    SysClose(Fds[0]);
    SysSigAction(SIGPIPE, SIG_DFL, 0);
    If Not R^.DocExp Then
    Begin
      P := 0;
      While P < R^.DocLen Do
      Begin
        K := LnxSys3(4, Fds[1], R^.Doc + P, R^.DocLen - P);
        If K <= 0 Then Break;
        P := P + K;
      End;
    End
    Else DocExpandTo(Fds[1], R^.Doc, R^.DocLen);
    SysExit(0);
  End;
  SysClose(Fds[1]);
  HereDocFd := Fds[0];
End;

{ <<< mot : tube alimente par un fils avec le texte S }
Function HereStrFd(Const S : String) : LongInt;
Var Fds : Array[0..1] Of LongInt; Pid, P, K : LongInt;
Begin
  HereStrFd := -1;
  If SysPipe(Fds[0]) < 0 Then Exit;
  Pid := SysFork;
  If Pid < 0 Then
  Begin
    SysClose(Fds[0]);
    SysClose(Fds[1]);
    Exit;
  End;
  If Pid = 0 Then
  Begin
    SysClose(Fds[0]);
    SysSigAction(SIGPIPE, SIG_DFL, 0);
    P := 0;
    While P < Length(S) Do
    Begin
      K := LnxSys3(4, Fds[1], LongInt(@S[1]) + P, Length(S) - P);
      If K <= 0 Then Break;
      P := P + K;
    End;
    SysExit(0);
  End;
  SysClose(Fds[1]);
  HereStrFd := Fds[0];
End;

Function ApplyRedirs(R : PRedir; Sv : PSaved) : Boolean;
Var Fd, H, Op, X : LongInt; Path, Wd : String;
Begin
  ApplyRedirs := True;
  While R <> Nil Do
  Begin
    Op := R^.Op;
    Fd := R^.Fd;
    If Fd < 0 Then
    Begin
      If (Op = tLess) Or (Op = tLessAnd) Or (Op = tLessGreat) Or (Op = tDLess)
         Or (Op = tHereStr) Then Fd := 0 Else Fd := 1;
    End;
    If Sv <> Nil Then
      If Sv^.N <= MAXREDIR Then
      Begin
        Sv^.Fd[Sv^.N] := Fd;
        Sv^.Cp[Sv^.N] := DupHigh(Fd);
        Inc(Sv^.N);
      End;
    H := -1;
    Case Op Of
      tLess, tGreat, tClobber, tDGreat, tLessGreat :
        Begin
          Path := ExpandStr(R^.Target);
          Case Op Of
            tLess : H := SysOpen(Path, O_RDONLY, 0);
            tDGreat : H := SysOpen(Path, O_WRONLY Or O_CREAT Or O_APPEND, 438);
            tLessGreat : H := SysOpen(Path, O_RDWR Or O_CREAT, 438);
          Else
            H := SysOpen(Path, O_WRONLY Or O_CREAT Or O_TRUNC, 438);
          End;
          If H < 0 Then
          Begin
            ShErr(Path + ': ' + SysErrorText(SysErrno));
            ApplyRedirs := False;
            Exit;
          End;
        End;
      tHereStr :
        Begin
          H := HereStrFd(ExpandStr(R^.Target) + #10);
          If H < 0 Then
          Begin
            ApplyRedirs := False;
            Exit;
          End;
        End;
      tAndGreat, tAndDGreat :
        Begin
          Path := ExpandStr(R^.Target);
          If Op = tAndDGreat Then
            H := SysOpen(Path, O_WRONLY Or O_CREAT Or O_APPEND, 438)
          Else H := SysOpen(Path, O_WRONLY Or O_CREAT Or O_TRUNC, 438);
          If H < 0 Then
          Begin
            ShErr(Path + ': ' + SysErrorText(SysErrno));
            ApplyRedirs := False;
            Exit;
          End;
          SysDup2(H, 1);
          SysDup2(H, 2);
          SysClose(H);
          H := -2;
        End;
      tDLess :
        Begin
          H := HereDocFd(R);
          If H < 0 Then
          Begin
            ApplyRedirs := False;
            Exit;
          End;
        End;
      tGreatAnd, tLessAnd :
        Begin
          Wd := ExpandStr(R^.Target);
          If Wd = '-' Then
          Begin
            SysClose(Fd);
            H := -2;
          End
          Else If StrInt(Wd, X) Then
          Begin
            If SysDup2(X, Fd) < 0 Then
            Begin
              ShErr(Wd + ': ' + SysErrorText(SysErrno));
              ApplyRedirs := False;
              Exit;
            End;
            H := -2;
          End
          Else
          Begin
            { >&fichier : sortie et erreur }
            H := SysOpen(Wd, O_WRONLY Or O_CREAT Or O_TRUNC, 438);
            If H < 0 Then
            Begin
              ShErr(Wd + ': ' + SysErrorText(SysErrno));
              ApplyRedirs := False;
              Exit;
            End;
            SysDup2(H, 1);
            SysDup2(H, 2);
            SysClose(H);
            H := -2;
          End;
        End;
    End;
    If H >= 0 Then
    Begin
      If H <> Fd Then
      Begin
        SysDup2(H, Fd);
        SysClose(H);
      End;
    End;
    R := R^.Next;
  End;
End;

Procedure RestoreRedirs(Sv : PSaved);
Var I : LongInt;
Begin
  For I := Sv^.N - 1 DownTo 0 Do
  Begin
    If Sv^.Cp[I] >= 0 Then
    Begin
      SysDup2(Sv^.Cp[I], Sv^.Fd[I]);
      SysClose(Sv^.Cp[I]);
    End
    Else SysClose(Sv^.Fd[I]);
  End;
  Sv^.N := 0;
End;

{ ---------- fonctions, alias, commandes internes ---------- }

Function FindFunc(Const N : String) : LongInt;
Var I : LongInt;
Begin
  For I := 0 To MAXFUNCS - 1 Do
    If Funcs[I].Used And (Funcs[I].Name = N) Then
    Begin
      FindFunc := I;
      Exit;
    End;
  FindFunc := -1;
End;

Function FindAlias(Const N : String) : LongInt;
Var I : LongInt;
Begin
  For I := 0 To MAXALIAS - 1 Do
    If Aliases[I].Used And (Aliases[I].Name = N) Then
    Begin
      FindAlias := I;
      Exit;
    End;
  FindAlias := -1;
End;

Const
  NBUILTIN = 59;
  BuiltinNames : Array[1..NBUILTIN] Of String[10] = (
    ':', '.', 'source', 'alias', 'bg', 'break', 'builtin', 'cd', 'command',
    'continue', 'echo', 'eval', 'exec', 'exit', 'export', 'false', 'fg',
    'getopts', 'history', 'jobs', 'kill', 'local', 'pwd', 'read', 'readonly',
    'return', 'set', 'shift', 'test', '[', 'times', 'trap', 'true', 'type',
    'ulimit', 'umask', 'unalias', 'unset', 'wait', 'hash', 'chdir', 'logout',
    'declare', 'typeset', 'let', 'mapfile', 'readarray', 'printf', 'shopt',
    'pushd', 'popd', 'dirs', 'complete', 'compgen', 'enable', 'disown',
    'bind', 'caller', 'compopt');

Function BuiltinId(Const N : String) : LongInt;
Var I : LongInt;
Begin
  For I := 1 To NBUILTIN Do
    If BuiltinNames[I] = N Then
    Begin
      If (I > 42) And Not BashMode Then Break;
      BuiltinId := I;
      Exit;
    End;
  BuiltinId := 0;
End;

Function RunBuiltin(Id : LongInt; Var A : TArgs; InPipe : Boolean) : LongInt;
Forward;
Function ExecCommand(N : PNode; InChild : Boolean) : LongInt; Forward;
Function ExecList(L : PNode) : LongInt; Forward;
Function ExecAndOr(N : PNode) : LongInt; Forward;

{ ---------- execution d'un programme externe ---------- }

Function PathOf(Const Name : String; Var Found : String) : LongInt;
{ 0 : trouve ; 1 : introuvable ; 2 : droit refuse }
Var P, D, Cand : String; K : LongInt; St : TSysStat; Denied : Boolean;
Begin
  Denied := False;
  If Pos('/', Name) > 0 Then
  Begin
    Found := Name;
    If SysStat(Name, St) < 0 Then PathOf := 1
    Else If (St.Mode And S_IFMT) = S_IFDIR Then PathOf := 2
    Else PathOf := 0;
    Exit;
  End;
  If Not GetVar('PATH', P) Then P := '/bin:/usr/bin';
  P := P + ':';
  While P <> '' Do
  Begin
    K := Pos(':', P);
    D := Copy(P, 1, K - 1);
    Delete(P, 1, K);
    If D = '' Then D := '.';
    Cand := D + '/' + Name;
    If SysStat(Cand, St) = 0 Then
      If (St.Mode And S_IFMT) = S_IFREG Then
      Begin
        If (St.Mode And $49) <> 0 Then
        Begin
          Found := Cand;
          PathOf := 0;
          Exit;
        End;
        Denied := True;
      End;
  End;
  If Denied Then PathOf := 2 Else PathOf := 1;
End;

Procedure ExecProgram(Var A : TArgs);
{ ne revient pas : execve ou sortie 126 / 127 }
Var
  Path : String; R, I, Argv, Envp, Code : LongInt;
Begin
  R := PathOf(A.It[0]^, Path);
  If R = 1 Then
  Begin
    ShErr(A.It[0]^ + ': ' + Msg(mNotFound));
    SysExit(127);
  End;
  If R = 2 Then
  Begin
    ShErr(A.It[0]^ + ': ' + Msg(mNotExec));
    SysExit(126);
  End;
  Argv := Alloc((A.N + 3) * 4);
  For I := 0 To A.N - 1 Do MemL[0:Argv + I * 4] := SysNewZ(A.It[I]^);
  MemL[0:Argv + A.N * 4] := 0;
  Envp := BuildEnv;
  SysExecve(Path, Argv, Envp);
  Code := SysErrno;
  If Code = 8 Then
  Begin
    { script sans #! : execute par /bin/sh }
    Argv := Alloc((A.N + 4) * 4);
    MemL[0:Argv] := SysNewZ('sh');
    MemL[0:Argv + 4] := SysNewZ(Path);
    For I := 1 To A.N - 1 Do MemL[0:Argv + (I + 1) * 4] := SysNewZ(A.It[I]^);
    MemL[0:Argv + (A.N + 1) * 4] := 0;
    SysExecve('/bin/sh', Argv, Envp);
  End;
  ShErr(A.It[0]^ + ': ' + SysErrorText(Code));
  If Code = 2 Then SysExit(127);
  SysExit(126);
End;

{ affectations prefixes : dans l'environnement d'un fils ou temporaires }
Type
  TOldVal = Record
    Name : String[63];
    Had : Boolean;
    Val : String;
    Exp : Boolean;
  End;
  TOlds = Record
    N : LongInt;
    It : Array[0..31] Of TOldVal;
  End;

{ affectation composee nom=(a b c) ; Items : elements separes par #2 }
Procedure AssignCompound(Const Nm : String; Append : Boolean;
    Const Items : String);
Var Kind, Idx, K, J, E, Dp : LongInt; It, Tok2, Key : String; A : TArgs;
    Rest : String; Fl : Boolean; Pend : String; HavePend : Boolean;
Begin
  Kind := ArrKind(Nm);
  If Kind = 0 Then Kind := 1;
  ArrDeclare(Nm, Kind);
  If Not Append Then ArrClear(Nm);
  Idx := 0;
  If Append And (Kind = 1) Then Idx := ArrNextIdx(Nm);
  HavePend := False;
  Rest := Items;
  While (Rest <> '') Or HavePend Do
  Begin
    If Rest = '' Then Break;
    K := Pos(#2, Rest);
    If K = 0 Then
    Begin
      It := Rest;
      Rest := '';
    End
    Else
    Begin
      It := Copy(Rest, 1, K - 1);
      Rest := Copy(Rest, K + 1, 2000);
    End;
    { [cle]=valeur }
    If (It <> '') And (It[1] = '[') Then
    Begin
      Dp := 1;
      J := 2;
      While (J <= Length(It)) And (Dp > 0) Do
      Begin
        If It[J] = '[' Then Inc(Dp)
        Else If It[J] = ']' Then Dec(Dp);
        Inc(J);
      End;
      If (Dp = 0) And (J <= Length(It)) And ((It[J] = '=') Or
         ((It[J] = '+') And (J < Length(It)) And (It[J + 1] = '='))) Then
      Begin
        Key := ElemName(Nm, Copy(It, 2, J - 3));
        Tok2 := ExpandStr(Copy(It, J + 1 + Ord(It[J] = '+'), 255));
        If It[J] = '+' Then
        Begin
          GetVar(Key, Pend);
          Tok2 := Pend + Tok2;
        End;
        SetVar(Key, Tok2);
        If Kind = 1 Then
          If StrInt(Copy(Key, Length(Nm) + 2, Length(Key) - Length(Nm) - 2),
                    E) Then Idx := E + 1;
        Continue;
      End;
    End;
    ArgsInit(A);
    ExpandWord(It, @A);
    For J := 0 To A.N - 1 Do
    Begin
      If Kind = 2 Then
      Begin
        If HavePend Then
        Begin
          SetVar(Nm + '[' + Pend + ']', A.It[J]^);
          HavePend := False;
        End
        Else
        Begin
          Pend := A.It[J]^;
          HavePend := True;
        End;
      End
      Else
      Begin
        SetVar(Nm + '[' + IntStr(Idx) + ']', A.It[J]^);
        Inc(Idx);
      End;
    End;
    ArgsFree(A);
  End;
  If HavePend Then SetVar(Nm + '[' + Pend + ']', '');
End;

{ decoupe un mot d'affectation : base, indice (ou ''), += ?, valeur brute }
Function SplitAssign(Const W : String; Var Base, Sub, Val_ : String;
    Var Append : Boolean) : Boolean;
Var K, Dp : LongInt;
Begin
  SplitAssign := False;
  Base := '';
  Sub := '';
  Append := False;
  K := 1;
  While (K <= Length(W)) And IsNameCh(Ord(W[K])) Do
  Begin
    Base := Base + W[K];
    Inc(K);
  End;
  If (K <= Length(W)) And (W[K] = '[') And BashMode Then
  Begin
    Dp := 1;
    Inc(K);
    While (K <= Length(W)) And (Dp > 0) Do
    Begin
      If W[K] = '[' Then Inc(Dp)
      Else If W[K] = ']' Then Dec(Dp);
      If Dp > 0 Then Sub := Sub + W[K];
      Inc(K);
    End;
  End;
  If (K < Length(W)) And (W[K] = '+') And (W[K + 1] = '=') Then
  Begin
    Append := True;
    Inc(K);
  End;
  If (K > Length(W)) Or (W[K] <> '=') Then Exit;
  Val_ := Copy(W, K + 1, 2000);
  SplitAssign := True;
End;

Procedure DoAssign(N : PNode; Var O : TOlds; Save : Boolean);
Var W : PWd; K, I : LongInt; Nm, V, Sub, Raw, Cur, EN : String; App : Boolean;
Begin
  W := N^.Words;
  While (W <> Nil) And W^.IsAssign Do
  Begin
    If Not SplitAssign(W^.S, Nm, Sub, Raw, App) Then
    Begin
      W := W^.Next;
      Continue;
    End;
    If (Raw <> '') And (Raw[1] = #5) Then
    Begin
      AssignCompound(ResolveRef(Nm), App, Copy(Raw, 2, 2000));
      W := W^.Next;
      Continue;
    End;
    V := ExpandStr(Raw);
    Nm := ResolveRef(Nm);
    If Sub <> '' Then
    Begin
      If ArrKind(Nm) = 0 Then
      Begin
        I := FindVar(Nm);
        ArrDeclare(Nm, 1);
      End;
      EN := ElemName(Nm, Sub);
      If App Then
      Begin
        GetVar(EN, Cur);
        V := Cur + V;
      End;
      SetVar(EN, V);
      W := W^.Next;
      Continue;
    End;
    If App Then
    Begin
      GetVar(Nm, Cur);
      I := FindVar(Nm);
      If (I >= 0) And Vars[I].IntAttr Then
        V := IntStr(ArithEval(Cur) + ArithEval(V))
      Else V := Cur + V;
    End;
    If Save And (O.N < 32) Then
    Begin
      O.It[O.N].Name := Nm;
      I := FindVar(Nm);
      O.It[O.N].Had := I >= 0;
      If I >= 0 Then
      Begin
        O.It[O.N].Val := Vars[I].Val;
        O.It[O.N].Exp := Vars[I].Exp;
      End;
      Inc(O.N);
    End;
    SetVar(Nm, V);
    If Save Then ExportVar(Nm, True);
    W := W^.Next;
  End;
End;

Procedure UndoAssign(Var O : TOlds);
Var I : LongInt;
Begin
  For I := O.N - 1 DownTo 0 Do
    If O.It[I].Had Then
    Begin
      SetVar(O.It[I].Name, O.It[I].Val);
      ExportVar(O.It[I].Name, O.It[I].Exp);
    End
    Else UnsetVar(O.It[I].Name);
  O.N := 0;
End;

Procedure XTrace(Var A : TArgs);
Var I : LongInt; S : String;
Begin
  S := '+';
  For I := 0 To A.N - 1 Do S := S + ' ' + A.It[I]^;
  Err(S);
End;

Function ExecFuncCall(F : LongInt; Var A : TArgs) : LongInt;
Var SaveArr, SaveN, St, I, SaveN2 : LongInt; Body : PNode;
Begin
  SaveArr := PosArr;
  SaveN := NPos;
  PosSet(A, 1);
  Inc(InFunc);
  If BashMode Then
  Begin
    ArrDeclare('FUNCNAME', 1);
    If ArrCount('FUNCNAME') = 0 Then SetVar('FUNCNAME[0]', 'main');
    For I := ArrCount('FUNCNAME') - 1 DownTo 0 Do
      SetVar('FUNCNAME[' + IntStr(I + 1) + ']',
             VarValue('FUNCNAME[' + IntStr(I) + ']'));
    SetVar('FUNCNAME[0]', Funcs[F].Name);
  End;
  If LocalFP < 31 Then
  Begin
    Inc(LocalFP);
    LocalFrame[LocalFP] := LocalSP;
  End;
  Body := Funcs[F].Body;
  St := ExecCommand(Body, False);
  If RetFlag <> 0 Then
  Begin
    RetFlag := 0;
    St := LastStatus;
  End;
  { variables locales : restauration }
  If LocalFP > 0 Then
  Begin
    While LocalSP > LocalFrame[LocalFP] Do
    Begin
      Dec(LocalSP);
      If Copy(LocalName[LocalSP], 1, 7) = '#clear:' Then
        ArrClear(Copy(LocalName[LocalSP], 8, 60))
      Else If LocalOld[LocalSP] = Nil Then
      Begin
        I := FindVar(LocalName[LocalSP]);
        If I >= 0 Then
        Begin
          If Vars[I].Kind > 0 Then ArrClear(LocalName[LocalSP]);
          Vars[I].Used := False;
        End;
      End
      Else
      Begin
        I := FindVar(LocalName[LocalSP]);
        If I < 0 Then
        Begin
          SetVar(LocalName[LocalSP], '');
          I := FindVar(LocalName[LocalSP]);
        End;
        If I >= 0 Then
        Begin
          Vars[I].Val := LocalOld[LocalSP]^;
          Vars[I].Kind := LocalKd[LocalSP];
          Vars[I].IntAttr := False;
          Vars[I].CaseAttr := 0;
          Vars[I].RO := False;
          Vars[I].Ref := False;
        End;
        FreeStr(LocalOld[LocalSP]);
      End;
    End;
    Dec(LocalFP);
  End;
  If BashMode Then
  Begin
    SaveN2 := ArrCount('FUNCNAME');
    For I := 0 To SaveN2 - 2 Do
      SetVar('FUNCNAME[' + IntStr(I) + ']',
             VarValue('FUNCNAME[' + IntStr(I + 1) + ']'));
    UnsetVar('FUNCNAME[' + IntStr(SaveN2 - 1) + ']');
    If SaveN2 = 2 Then UnsetVar('FUNCNAME');
    If (TrapCmd[35] <> Nil) And (TrapCmd[35]^ <> '') And Not InDebug Then
    Begin
      InDebug := True;
      RunText(TrapCmd[35]^);
      InDebug := False;
    End;
  End;
  Dec(InFunc);
  PosClear;
  HeapFree(1, 0, PosArr);
  PosArr := SaveArr;
  NPos := SaveN;
  ExecFuncCall := St;
End;

Function SimpleStatus(St : LongInt) : LongInt;
Begin
  SimpleStatus := St;
End;

Function ExecSimple(N : PNode; InChild : Boolean) : LongInt;
Var
  A, A2 : TArgs;
  W : PWd;
  Id, F, J, Pid, St, I, K, Cnt : LongInt;
  Sv : TSaved;
  Old : TOlds;
  Al : String;
  ExpandedAlias : Boolean;
  Tmp : TIn;
  Special : Boolean;
Begin
  Old.N := 0;
  Sv.N := 0;
  SubstStatus := 0;
  ArgsInit(A);
  W := N^.Words;
  While W <> Nil Do
  Begin
    If W^.IsAssign Then
    Else If BashMode And (Pos(#5, W^.S) > 0) And (A.N > 0) Then
      ArgsAdd(A, W^.S)
    Else ExpandWord(W^.S, @A);
    W := W^.Next;
  End;
  { alias : premier mot }
  If (A.N > 0) And (SubDepth >= 0) Then
  Begin
    I := FindAlias(A.It[0]^);
    If I >= 0 Then
    Begin
      Al := Aliases[I].Val;
      ArgsInit(A2);
      { decoupage simple de la valeur de l'alias en mots }
      While Al <> '' Do
      Begin
        While (Al <> '') And (Al[1] = ' ') Do Delete(Al, 1, 1);
        If Al = '' Then Break;
        K := 1;
        While (K <= Length(Al)) And (Al[K] <> ' ') Do Inc(K);
        ExpandWord(Copy(Al, 1, K - 1), @A2);
        Delete(Al, 1, K - 1);
      End;
      For K := 1 To A.N - 1 Do ArgsAdd(A2, A.It[K]^);
      ArgsFree(A);
      A := A2;
    End;
  End;
  If A.N = 0 Then
  Begin
    { affectations seules }
    DoAssign(N, Old, False);
    If N^.Redirs <> Nil Then
    Begin
      If ApplyRedirs(N^.Redirs, @Sv) Then ;
      RestoreRedirs(@Sv);
    End;
    ExecSimple := SubstStatus;
    ArgsFree(A);
    Exit;
  End;
  If OptX Then XTrace(A);
  { fonction ? }
  F := FindFunc(A.It[0]^);
  Id := 0;
  If F < 0 Then Id := BuiltinId(A.It[0]^);
  If (F >= 0) Or (Id > 0) Then
  Begin
    Special := (Id = 1) Or (Id = 2) Or (Id = 3) Or (Id = 6) Or (Id = 10) Or
               (Id = 12) Or (Id = 13) Or (Id = 14) Or (Id = 15) Or
               (Id = 25) Or (Id = 26) Or (Id = 27) Or (Id = 32) Or (Id = 38)
               Or (Id = 43) Or (Id = 44) Or (Id = 22) Or (Id = 45) Or
               (Id = 46) Or (Id = 47) Or (Id = 49) Or (Id = 50) Or (Id = 51);
    Special := Special Or (Id = 12);
    DoAssign(N, Old, Not Special);
    If N^.Redirs <> Nil Then
    Begin
      If Not ApplyRedirs(N^.Redirs, @Sv) Then
      Begin
        RestoreRedirs(@Sv);
        UndoAssign(Old);
        ArgsFree(A);
        ExecSimple := 1;
        Exit;
      End;
    End;
    If F >= 0 Then St := ExecFuncCall(F, A)
    Else St := RunBuiltin(Id, A, InChild);
    If (Id = 13) And (A.N = 1) Then Sv.N := 0;
    RestoreRedirs(@Sv);
    If Not Special Then UndoAssign(Old);
    ArgsFree(A);
    ExecSimple := St;
    Exit;
  End;
  { programme externe }
  If InChild Then
  Begin
    DoAssign(N, Old, True);
    If N^.Redirs <> Nil Then
      If Not ApplyRedirs(N^.Redirs, Nil) Then SysExit(1);
    ExecProgram(A);
  End;
  J := JobNew(LastLine);
  Pid := ForkProc(0, True);
  If Pid < 0 Then
  Begin
    If J >= 0 Then Jobs[J].State := jFree;
    ExecSimple := 1;
    Exit;
  End;
  If Pid = 0 Then
  Begin
    DoAssign(N, Old, True);
    If N^.Redirs <> Nil Then
      If Not ApplyRedirs(N^.Redirs, Nil) Then SysExit(1);
    ExecProgram(A);
  End;
  JobAddPid(J, Pid);
  GiveTerm(Pid);
  If J >= 0 Then St := JobWait(J)
  Else
  Begin
    SysWaitPid(Pid, I, 0);
    St := StatusOf(I);
  End;
  ArgsFree(A);
  ExecSimple := St;
End;

{ ---------- commandes composees, tubes, listes ---------- }

Function CaseMatch(Const Word : String; Pats : PWd) : Boolean;
Var E : TExp; W : String;
Begin
  CaseMatch := False;
  While Pats <> Nil Do
  Begin
    ExpInit(E, Nil, True);
    ExpandInto(E, Pats^.S, False);
    W := Word;
    If PatMatch(E.S, E.F, W) Then
    Begin
      CaseMatch := True;
      Exit;
    End;
    Pats := Pats^.Next;
  End;
End;

Function ExecBody(L : PNode) : LongInt;
Begin
  If L = Nil Then ExecBody := 0 Else ExecBody := ExecList(L);
End;

Function ExecFor(N : PNode) : LongInt;
Var A : TArgs; W : PWd; I, St : LongInt;
Begin
  ArgsInit(A);
  If N^.Neg Then
  Begin
    W := N^.Words;
    While W <> Nil Do
    Begin
      ExpandWord(W^.S, @A);
      W := W^.Next;
    End;
  End
  Else
    For I := 1 To NPos Do ArgsAdd(A, PosGet(I));
  St := 0;
  Inc(LoopDepth);
  For I := 0 To A.N - 1 Do
  Begin
    SetVar(N^.Name, A.It[I]^);
    St := ExecBody(N^.B);
    If RetFlag <> 0 Then Break;
    If BreakN > 0 Then
    Begin
      Dec(BreakN);
      Break;
    End;
    If ContN > 0 Then
    Begin
      Dec(ContN);
      If ContN > 0 Then Break;
    End;
    If IntFlag <> 0 Then Break;
  End;
  Dec(LoopDepth);
  ArgsFree(A);
  ExecFor := St;
End;

Function ExecWhile(N : PNode; IsUntil : Boolean) : LongInt;
Var C, St : LongInt;
Begin
  St := 0;
  Inc(LoopDepth);
  While True Do
  Begin
    Inc(InCond);
    C := ExecBody(N^.A);
    Dec(InCond);
    If RetFlag <> 0 Then Break;
    If BreakN > 0 Then
    Begin
      Dec(BreakN);
      Break;
    End;
    If IsUntil Then
    Begin
      If C = 0 Then Break;
    End
    Else If C <> 0 Then Break;
    St := ExecBody(N^.B);
    If RetFlag <> 0 Then Break;
    If BreakN > 0 Then
    Begin
      Dec(BreakN);
      Break;
    End;
    If ContN > 0 Then
    Begin
      Dec(ContN);
      If ContN > 0 Then Break;
    End;
    If IntFlag <> 0 Then Break;
  End;
  Dec(LoopDepth);
  ExecWhile := St;
End;

Function ExecCase(N : PNode) : LongInt;
Var It : PNode; Wd : String; Fall : Boolean; St : LongInt;
Begin
  Wd := ExpandStr(N^.Words^.S);
  It := N^.B;
  ExecCase := 0;
  Fall := False;
  St := 0;
  While It <> Nil Do
  Begin
    If Fall Or CaseMatch(Wd, It^.Words) Then
    Begin
      St := ExecBody(It^.A);
      ExecCase := St;
      If It^.Op = tSemiAmp Then Fall := True
      Else If It^.Op = tDSemiAmp Then Fall := False
      Else Exit;
      If RetFlag <> 0 Then Exit;
      If It^.Op = tDSemiAmp Then
      Begin
        It := It^.Next;
        Continue;
      End;
    End;
    It := It^.Next;
  End;
End;

{ sous-shell : fork, execute le noeud, sort }
Function ExecSubshell(N : PNode) : LongInt;
Var J, Pid, St : LongInt;
Begin
  J := JobNew(LastLine);
  Pid := ForkProc(0, True);
  If Pid < 0 Then
  Begin
    ExecSubshell := 1;
    Exit;
  End;
  If Pid = 0 Then
  Begin
    If N^.Redirs <> Nil Then
      If Not ApplyRedirs(N^.Redirs, Nil) Then SysExit(1);
    St := ExecBody(N^.A);
    CleanExit(St);
  End;
  JobAddPid(J, Pid);
  GiveTerm(Pid);
  If J >= 0 Then ExecSubshell := JobWait(J)
  Else
  Begin
    SysWaitPid(Pid, St, 0);
    ExecSubshell := StatusOf(St);
  End;
End;


Function ExecDBr(N : PNode) : LongInt; Forward;

{ evalue une expression arithmetique brute (avec developpement des $) }
Function ArithStr(Const Raw : String) : LongInt;
Var E : TExp;
Begin
  ExpInit(E, Nil, True);
  ExpandInto(E, ' ' + Raw, False);
  ArithStr := ArithEval(E.S);
End;

Function ExecArith(N : PNode) : LongInt;
Var V : LongInt;
Begin
  V := ArithStr(N^.Words^.S);
  If ArFailed Then ExecArith := 1
  Else If V <> 0 Then ExecArith := 0
  Else ExecArith := 1;
End;

Function ExecArithFor(N : PNode) : LongInt;
Var St, V : LongInt; Ini, Cnd, Stp : PWd; Done : Boolean;
Begin
  Ini := N^.Words;
  Cnd := Ini^.Next;
  Stp := Cnd^.Next;
  St := 0;
  If Ini^.S <> '' Then ArithStr(Ini^.S);
  Inc(LoopDepth);
  Done := False;
  While Not Done Do
  Begin
    If Cnd^.S <> '' Then
    Begin
      V := ArithStr(Cnd^.S);
      If (V = 0) Or ArFailed Then Break;
    End;
    St := ExecBody(N^.B);
    If RetFlag <> 0 Then Break;
    If BreakN > 0 Then
    Begin
      Dec(BreakN);
      Break;
    End;
    If ContN > 0 Then
    Begin
      Dec(ContN);
      If ContN > 0 Then Break;
    End;
    If IntFlag <> 0 Then Break;
    If Stp^.S <> '' Then ArithStr(Stp^.S);
  End;
  Dec(LoopDepth);
  ExecArithFor := St;
End;

Function ExecSelect(N : PNode) : LongInt;
Var A : TArgs; W : PWd; I, St, X : LongInt; L, Pr : String; Redo : Boolean;
Begin
  ArgsInit(A);
  If N^.Neg Then
  Begin
    W := N^.Words;
    While W <> Nil Do
    Begin
      ExpandWord(W^.S, @A);
      W := W^.Next;
    End;
  End
  Else
    For I := 1 To NPos Do ArgsAdd(A, PosGet(I));
  St := 0;
  Inc(LoopDepth);
  Redo := True;
  While True Do
  Begin
    If Redo Then
      For I := 0 To A.N - 1 Do
        Out(2, IntStr(I + 1) + ') ' + A.It[I]^ + #10);
    Pr := '#? ';
    If GetVarRaw('PS3', L) Then Pr := L;
    Out(2, Pr);
    If Not SysReadLine(0, L) Then
    Begin
      St := 1;
      Break;
    End;
    SetVar('REPLY', L);
    If L = '' Then
    Begin
      Redo := True;
      Continue;
    End;
    Redo := False;
    If StrInt(L, X) And (X >= 1) And (X <= A.N) Then
      SetVar(N^.Name, A.It[X - 1]^)
    Else SetVar(N^.Name, '');
    St := ExecBody(N^.B);
    If RetFlag <> 0 Then Break;
    If BreakN > 0 Then
    Begin
      Dec(BreakN);
      Break;
    End;
    If ContN > 0 Then
    Begin
      Dec(ContN);
      If ContN > 0 Then Break;
    End;
    If IntFlag <> 0 Then Break;
  End;
  Dec(LoopDepth);
  ArgsFree(A);
  ExecSelect := St;
End;

Function ExecCommand1(N : PNode; InChild : Boolean) : LongInt;
Var Sv : TSaved; St, I : LongInt;
Begin
  Sv.N := 0;
  St := 0;
  Case N^.Kind Of
    nSimple :
      Begin
        If BashMode And (TrapCmd[34] <> Nil) And Not InDebug Then
        Begin
          InDebug := True;
          RunText(TrapCmd[34]^);
          InDebug := False;
        End;
        St := ExecSimple(N, InChild);
      End;
    nSubshell :
      Begin
        If InChild Then
        Begin
          If N^.Redirs <> Nil Then
            If Not ApplyRedirs(N^.Redirs, Nil) Then SysExit(1);
          St := ExecBody(N^.A);
        End
        Else St := ExecSubshell(N);
      End;
    nFunc :
      Begin
        { definition : le noeud devient permanent }
        I := FindFunc(N^.Name);
        If I < 0 Then
          For I := 0 To MAXFUNCS - 1 Do
            If Not Funcs[I].Used Then Break;
        If (I >= 0) And (I < MAXFUNCS) Then
        Begin
          Funcs[I].Used := True;
          Funcs[I].Name := N^.Name;
          Funcs[I].Body := N^.A;
          Pinned := True;
        End
        Else ShErr(Msg(mTooMany));
        St := 0;
      End;
  Else
    Begin
      If N^.Redirs <> Nil Then
        If Not ApplyRedirs(N^.Redirs, @Sv) Then
        Begin
          RestoreRedirs(@Sv);
          ExecCommand1 := 1;
          Exit;
        End;
      Case N^.Kind Of
        nIf :
          Begin
            Inc(InCond);
            St := ExecBody(N^.A);
            Dec(InCond);
            If RetFlag <> 0 Then
            Begin
            End
            Else If St = 0 Then St := ExecBody(N^.B)
            Else If N^.C <> Nil Then
            Begin
              If N^.C^.Kind = nIf Then St := ExecCommand(N^.C, False)
              Else St := ExecBody(N^.C);
            End
            Else St := 0;
          End;
        nWhile : St := ExecWhile(N, False);
        nUntil : St := ExecWhile(N, True);
        nFor : St := ExecFor(N);
        nArithFor : St := ExecArithFor(N);
        nArith : St := ExecArith(N);
        nDBr : St := ExecDBr(N);
        nSelect : St := ExecSelect(N);
        nCase : St := ExecCase(N);
        nBrace : St := ExecBody(N^.A);
      End;
      If N^.Redirs <> Nil Then RestoreRedirs(@Sv);
    End;
  End;
  ExecCommand1 := St;
End;

Function ExecCommand(N : PNode; InChild : Boolean) : LongInt;
Var Mk : LongInt;
Begin
  Mk := NProcFds;
  If N^.Line > 0 Then CurLine := N^.Line;
  ExecCommand := ExecCommand1(N, InChild);
  If NProcFds > Mk Then CloseProcFds(Mk);
End;

{ execute un fils d'un tube : ne revient pas }
Procedure ExecChild(N : PNode);
Var St : LongInt;
Begin
  St := ExecCommand(N, True);
  CleanExit(St);
End;

{ $PIPESTATUS : N etats ; J = numero du travail (ou -1 / 1 processus) }
Procedure SetPipeStatus(N, Last, Fail, J : LongInt);
Var I : LongInt;
Begin
  ArrDeclare('PIPESTATUS', 1);
  ArrClear('PIPESTATUS');
  If (N = 1) Or (J < 0) Then
  Begin
    SetVar('PIPESTATUS[0]', IntStr(Last));
    Exit;
  End;
  For I := 0 To N - 1 Do
    If I < 16 Then
      SetVar('PIPESTATUS[' + IntStr(I) + ']', IntStr(Jobs[J].PStat[I]));
End;

Function ExecPipeline(P : PNode; Bg : Boolean) : LongInt;
Var
  C : PNode; N, I, J, Pid, Pgid, Prev, St, K, Pf : LongInt;
  Fds : Array[0..1] Of LongInt;
Begin
  N := 0;
  C := P^.A;
  While C <> Nil Do
  Begin
    Inc(N);
    C := C^.Next;
  End;
  If N = 1 Then
  Begin
    St := ExecCommand(P^.A, False);
    If BashMode Then SetPipeStatus(1, St, St, St);
    If P^.Neg Then St := Ord(St = 0);
    NoErrChk := P^.Neg;
    ExecPipeline := St;
    Exit;
  End;
  J := JobNew(LastLine);
  Pgid := 0;
  Prev := -1;
  C := P^.A;
  For I := 1 To N Do
  Begin
    Fds[0] := -1;
    Fds[1] := -1;
    If I < N Then
      If SysPipe(Fds[0]) < 0 Then
      Begin
        ShErr(Msg(mCantFork));
        Break;
      End;
    Pid := ForkProc(Pgid, Not Bg);
    If Pid < 0 Then Break;
    If Pid = 0 Then
    Begin
      If Prev >= 0 Then
      Begin
        SysDup2(Prev, 0);
        SysClose(Prev);
      End;
      If Fds[1] >= 0 Then
      Begin
        SysDup2(Fds[1], 1);
        SysClose(Fds[1]);
        SysClose(Fds[0]);
      End;
      ExecChild(C);
    End;
    If Pgid = 0 Then Pgid := Pid;
    JobAddPid(J, Pid);
    If Prev >= 0 Then SysClose(Prev);
    If Fds[1] >= 0 Then SysClose(Fds[1]);
    Prev := Fds[0];
    C := C^.Next;
  End;
  If Prev >= 0 Then SysClose(Prev);
  If J < 0 Then
  Begin
    ExecPipeline := 1;
    Exit;
  End;
  GiveTerm(Pgid);
  St := JobWait(J);
  If BashMode Then
  Begin
    Pf := 0;
    For I := 0 To N - 1 Do
      If (I < 16) And (Jobs[J].PStat[I] <> 0) Then Pf := Jobs[J].PStat[I];
    SetPipeStatus(N, St, Pf, J);
    If OptPipe And (Pf <> 0) Then St := Pf;
  End;
  If P^.Neg Then St := Ord(St = 0);
  NoErrChk := P^.Neg;
  ExecPipeline := St;
End;

Function RunPipe(P : PNode) : LongInt;
{ pipeline avec exemption de set -e quand elle est suivie de && ou || }
Var Ex : Boolean; St : LongInt;
Begin
  Ex := (P^.Op <> 0) Or P^.Neg;
  If Ex Then Inc(InCond);
  St := ExecPipeline(P, False);
  If Ex Then Dec(InCond);
  RunPipe := St;
End;

Function ExecAndOr(N : PNode) : LongInt;
Var P : PNode; St, Op : LongInt; Short, NE : Boolean;
Begin
  P := N^.A;
  Short := False;
  NoErrChk := False;
  St := RunPipe(P);
  NE := NoErrChk;
  While P^.Op <> 0 Do
  Begin
    Op := P^.Op;
    P := P^.Next;
    If ((Op = tAndIf) And (St = 0)) Or ((Op = tOrIf) And (St <> 0)) Then
    Begin
      NoErrChk := False;
      St := RunPipe(P);
      NE := NoErrChk;
    End
    Else Short := True;
    If RetFlag <> 0 Then Break;
    If (BreakN > 0) Or (ContN > 0) Then Break;
  End;
  AoShort := Short;
  NoErrChk := NE;
  ExecAndOr := St;
End;

Function ExecList(L : PNode) : LongInt;
Var It : PNode; St, J, Pid : LongInt;
Begin
  St := 0;
  It := L^.A;
  While It <> Nil Do
  Begin
    If It^.Bg Then
    Begin
      J := JobNew(LastLine);
      Pid := ForkProc(0, False);
      If Pid = 0 Then
      Begin
        If Not Interactive Then
        Begin
          { sans controle des travaux : entree standard vers /dev/null }
          If SysIsATty(0) = False Then
          Begin
            St := SysOpen('/dev/null', O_RDONLY, 0);
            If St >= 0 Then
            Begin
              SysDup2(St, 0);
              SysClose(St);
            End;
          End;
        End;
        St := ExecAndOr(It);
        CleanExit(St);
      End;
      If Pid > 0 Then
      Begin
        JobAddPid(J, Pid);
        LastBg := Pid;
        If Interactive And (J >= 0) Then
          Out(1, '[' + IntStr(J + 1) + '] ' + IntStr(Pid) + #10);
        If J >= 0 Then Jobs[J].Notified := False;
        St := 0;
      End;
    End
    Else St := ExecAndOr(It);
    LastStatus := St;
    If (St <> 0) And (InCond = 0) And (RetFlag = 0) And Not AoShort And
       Not NoErrChk And Not It^.Bg Then
    Begin
      If BashMode And (TrapCmd[33] <> Nil) And (TrapCmd[33]^ <> '') Then
      Begin
        If Not InErrTrap Then
        Begin
          InErrTrap := True;
          RunText(TrapCmd[33]^);
          InErrTrap := False;
          LastStatus := St;
        End;
      End;
      If OptE And Not Interactive Then CleanExit(St);
    End;
    If TrapAny <> 0 Then DoTraps;
    If (RetFlag <> 0) Or (BreakN > 0) Or (ContN > 0) Then Break;
    If IntFlag <> 0 Then Break;
    It := It^.Next;
  End;
  ExecList := St;
End;

{ ---------- sources de commandes : chaine, fichier ---------- }

Procedure RunLoop(Top : Boolean);
Var N : PNode; St : LongInt; Saved : LongInt;
    STok, STokNum, SHereN, SPrompt : LongInt; STokS : String;
    STokQ, SSyn : Boolean;
Begin
  STok := Tok; STokS := TokS; STokQ := TokQuoted; STokNum := TokNum;
  SHereN := HereN; SPrompt := PromptMode; SSyn := SynErr;
  Saved := NodeHead;
  NodeHead := 0;
  Pinned := False;
  SynErr := False;
  HereN := 0;
  PromptMode := 1;
  GetTok;
  While True Do
  Begin
    If Tok = tNL Then
    Begin
      PromptMode := 1;
      GetTok;
      Continue;
    End;
    If Tok = tEOF Then Break;
    SynErr := False;
    N := ParseList(True);
    If (Not SynErr) And (Tok <> tNL) And (Tok <> tEOF) Then
      SynError(Msg(mUnexpTok) + ' ''' + TokS + '''');
    If SynErr Then
    Begin
      LastStatus := 2;
      If Not Interactive Then
      Begin
        If Top Then CleanExit(2);
        Break;
      End;
      { saute le reste de la ligne }
      While (Tok <> tNL) And (Tok <> tEOF) Do GetTok;
      SynErr := False;
      FreeTracked(NodeHead);
      NodeHead := 0;
      Continue;
    End;
    If Not OptN Then
    Begin
      IntFlag := 0;
      St := ExecList(N);
      LastStatus := St;
    End;
    If Not Pinned Then FreeTracked(NodeHead);
    Pinned := False;
    NodeHead := 0;
    If (RetFlag <> 0) Or (BreakN > 0) Or (ContN > 0) Then Break;
    If Tok = tNL Then
    Begin
      PromptMode := 1;
      GetTok;
    End;
  End;
  NodeHead := Saved;
  Tok := STok; TokS := STokS; TokQuoted := STokQ; TokNum := STokNum;
  HereN := SHereN; PromptMode := SPrompt; SynErr := SSyn;
End;

Procedure RunString(Addr, Len : LongInt);
Var Saved : TIn; SaveSyn : Boolean;
Begin
  Saved := CurIn;
  InOpenMem(CurIn, Addr, Len);
  SaveSyn := SynErr;
  RunLoop(False);
  SynErr := SaveSyn;
  InClose(CurIn);
  CurIn := Saved;
End;

Procedure RunText(Const S : String);
Var Saved : TIn;
Begin
  Saved := CurIn;
  InOpenStr(CurIn, S);
  RunLoop(False);
  InClose(CurIn);
  CurIn := Saved;
End;

{ execute un fichier de commandes (source) ; Faux si ouverture impossible }
Function RunFile(Const Path : String; Top : Boolean) : Boolean;
Var Saved : TIn; Fd : LongInt;
Begin
  RunFile := False;
  Fd := SysOpen(Path, O_RDONLY, 0);
  If Fd < 0 Then Exit;
  RunFile := True;
  Saved := CurIn;
  InOpenFd(CurIn, Fd, 4096);
  CurIn.Name := Path;
  RunLoop(Top);
  InClose(CurIn);
  CurIn := Saved;
End;

{ substitution de commande : corps numero Idx ; rend le tampon (adresse) et
  sa longueur, sans les fins de ligne finales }
Function RunSubst(Idx : LongInt; Var Len : LongInt) : LongInt;
Var
  Fds : Array[0..1] Of LongInt; Pid, N, Cap, Buf, P, St, SaveStatus : LongInt;
  Body : LongInt; J : LongInt;
Begin
  Body := Subs[Idx];
  Len := 0;
  Cap := 4096;
  Buf := Alloc(Cap);
  RunSubst := Buf;
  If SysPipe(Fds[0]) < 0 Then Exit;
  J := JobNew('');
  Pid := ForkProc(0, True);
  If Pid < 0 Then
  Begin
    SysClose(Fds[0]);
    SysClose(Fds[1]);
    Exit;
  End;
  If Pid = 0 Then
  Begin
    SysClose(Fds[0]);
    SysDup2(Fds[1], 1);
    SysClose(Fds[1]);
    RunString(Body + 4, MemL[0:Body]);
    CleanExit(LastStatus);
  End;
  SysClose(Fds[1]);
  JobAddPid(J, Pid);
  While True Do
  Begin
    If Len + 2048 > Cap Then
    Begin
      P := Alloc(Cap * 2);
      LnxMove(Buf, P, Len);
      HeapFree(1, 0, Buf);
      Buf := P;
      Cap := Cap * 2;
    End;
    N := LnxSys3(3, Fds[0], Buf + Len, 2048);
    If N = -4 Then Continue;
    If N <= 0 Then Break;
    Len := Len + N;
  End;
  SysClose(Fds[0]);
  If J >= 0 Then
  Begin
    SaveStatus := JobWait(J);
    LastStatus := SaveStatus;
    SubstStatus := SaveStatus;
  End
  Else
  Begin
    SysWaitPid(Pid, St, 0);
    LastStatus := StatusOf(St);
    SubstStatus := LastStatus;
  End;
  While (Len > 0) And (Mem[0:Buf + Len - 1] = 10) Do Dec(Len);
  RunSubst := Buf;
End;

{ <(cmd) / >(cmd) : un fils execute cmd, relie a un tube ; le chemin rendu
  designe l'autre extremite (/dev/fd/N ou /proc/self/fd/N) }
Function ProcSubst(Idx : LongInt; IsIn : Boolean) : String;
Var Fds : Array[0..1] Of LongInt; Pid, Body, Mine, St : LongInt; Pth : String;
    T : TSysStat;
Begin
  ProcSubst := '';
  Body := Subs[Idx];
  If SysPipe(Fds[0]) < 0 Then Exit;
  Pid := ForkProc(0, False);
  If Pid < 0 Then
  Begin
    SysClose(Fds[0]);
    SysClose(Fds[1]);
    Exit;
  End;
  If Pid = 0 Then
  Begin
    If IsIn Then
    Begin
      SysClose(Fds[0]);
      SysDup2(Fds[1], 1);
      SysClose(Fds[1]);
    End
    Else
    Begin
      SysClose(Fds[1]);
      SysDup2(Fds[0], 0);
      SysClose(Fds[0]);
    End;
    RunString(Body + 4, MemL[0:Body]);
    CleanExit(LastStatus);
  End;
  If IsIn Then
  Begin
    SysClose(Fds[1]);
    Mine := Fds[0];
  End
  Else
  Begin
    SysClose(Fds[0]);
    Mine := Fds[1];
  End;
  If NProcFds < 16 Then
  Begin
    ProcFds[NProcFds] := Mine;
    Inc(NProcFds);
  End;
  If SysStat('/dev/fd', T) = 0 Then Pth := '/dev/fd/'
  Else Pth := '/proc/self/fd/';
  ProcSubst := Pth + IntStr(Mine);
End;

Procedure CloseProcFds(Mark : LongInt);
Begin
  While NProcFds > Mark Do
  Begin
    Dec(NProcFds);
    SysClose(ProcFds[NProcFds]);
  End;
End;

{ ---------- commandes internes ---------- }

Const
  NSIG = 32;
  SigNames : Array[0..NSIG - 1] Of String[8] = (
    'EXIT', 'HUP', 'INT', 'QUIT', 'ILL', 'TRAP', 'ABRT', 'BUS', 'FPE',
    'KILL', 'USR1', 'SEGV', 'USR2', 'PIPE', 'ALRM', 'TERM', 'STKFLT', 'CHLD',
    'CONT', 'STOP', 'TSTP', 'TTIN', 'TTOU', 'URG', 'XCPU', 'XFSZ', 'VTALRM',
    'PROF', 'WINCH', 'IO', 'PWR', 'SYS');

Function SigNum(Const S : String) : LongInt;
Var I, X : LongInt; U : String;
Begin
  SigNum := -1;
  If StrInt(S, X) Then
  Begin
    If (X >= 0) And (X < NSIG) Then SigNum := X;
    Exit;
  End;
  U := S;
  For I := 1 To Length(U) Do U[I] := UpCase(U[I]);
  If BashMode Then
  Begin
    If U = 'ERR' Then SigNum := 33
    Else If U = 'DEBUG' Then SigNum := 34
    Else If U = 'RETURN' Then SigNum := 35;
    If (U = 'ERR') Or (U = 'DEBUG') Or (U = 'RETURN') Then Exit;
  End;
  If Copy(U, 1, 3) = 'SIG' Then U := Copy(U, 4, 20);
  For I := 0 To NSIG - 1 Do
    If SigNames[I] = U Then
    Begin
      SigNum := I;
      Exit;
    End;
End;

Procedure TrapHandler(Sig : LongInt);
Begin
  If (Sig >= 0) And (Sig < NSIG) Then
  Begin
    TrapPend[Sig] := 1;
    TrapAny := 1;
  End;
  If Sig = SIGINT Then IntFlag := 1;
End;

Procedure IntHandler(Sig : LongInt);
Begin
  IntFlag := 1;
  If (Sig >= 0) And (Sig < NSIG) Then
    If TrapCmd[Sig] <> Nil Then
    Begin
      TrapPend[Sig] := 1;
      TrapAny := 1;
    End;
End;

Procedure DoTraps;
Var I : LongInt; Cmd : String;
Begin
  If TrapAny = 0 Then Exit;
  TrapAny := 0;
  For I := 1 To NSIG - 1 Do
    If TrapPend[I] <> 0 Then
    Begin
      TrapPend[I] := 0;
      If (TrapCmd[I] <> Nil) And (TrapCmd[I]^ <> '') Then
      Begin
        Cmd := TrapCmd[I]^;
        RunText(Cmd);
      End;
    End;
End;

Procedure HistSave; Forward;

Procedure CleanExit(Code : LongInt);
Var Cmd : String;
Begin
  If (TrapCmd[0] <> Nil) And (SubDepth = 0) Then
  Begin
    Cmd := TrapCmd[0]^;
    FreeStr(TrapCmd[0]);
    TrapCmd[0] := Nil;
    If Cmd <> '' Then RunText(Cmd);
  End;
  If HaveTerm And (SubDepth = 0) Then SysTcSetAttr(0, 1, SavedTerm);
  If Interactive And (SubDepth = 0) Then HistSave;
  SysExit(Code And 255);
End;

Procedure Say1(Const S : String);
Begin
  Out(1, S + #10);
End;

Function Join(Var A : TArgs; From : LongInt) : String;
Var I : LongInt; S : String;
Begin
  S := '';
  For I := From To A.N - 1 Do
  Begin
    If I > From Then S := S + ' ';
    S := S + A.It[I]^;
  End;
  Join := S;
End;

{ ----- echo ----- }
Function BiEcho(Var A : TArgs) : LongInt;
Var I, K, X, N : LongInt; S, R : String; NoNl, Esc, Stop : Boolean; C : Char;
Begin
  I := 1;
  NoNl := False;
  Esc := False;
  While (I < A.N) And (Length(A.It[I]^) > 1) And (A.It[I]^[1] = '-') Do
  Begin
    S := A.It[I]^;
    X := 2;
    While (X <= Length(S)) And (S[X] In ['n', 'e', 'E']) Do Inc(X);
    If X <= Length(S) Then Break;
    For X := 2 To Length(S) Do
      Case S[X] Of
        'n' : NoNl := True;
        'e' : Esc := True;
        'E' : Esc := False;
      End;
    Inc(I);
  End;
  R := '';
  Stop := False;
  While (I < A.N) And Not Stop Do
  Begin
    S := A.It[I]^;
    K := 1;
    While K <= Length(S) Do
    Begin
      C := S[K];
      If Esc And (C = '\') And (K < Length(S)) Then
      Begin
        Inc(K);
        Case S[K] Of
          'n' : R := R + #10;
          't' : R := R + #9;
          'r' : R := R + #13;
          'a' : R := R + #7;
          'b' : R := R + #8;
          'f' : R := R + #12;
          'v' : R := R + #11;
          'e' : R := R + #27;
          '\' : R := R + '\';
          'c' : Begin Stop := True; NoNl := True; Break; End;
          '0' :
            Begin
              X := 0;
              N := 0;
              While (K < Length(S)) And (N < 3) And (S[K + 1] >= '0') And
                    (S[K + 1] <= '7') Do
              Begin
                X := X * 8 + Ord(S[K + 1]) - 48;
                Inc(K);
                Inc(N);
              End;
              R := R + Chr(X And 255);
            End;
          'x' :
            Begin
              X := 0;
              N := 0;
              While (K < Length(S)) And (N < 2) And
                    (UpCase(S[K + 1]) In ['0'..'9', 'A'..'F']) Do
              Begin
                C := UpCase(S[K + 1]);
                If C <= '9' Then X := X * 16 + Ord(C) - 48
                Else X := X * 16 + Ord(C) - 55;
                Inc(K);
                Inc(N);
              End;
              R := R + Chr(X And 255);
            End;
        Else R := R + '\' + S[K];
        End;
      End
      Else R := R + C;
      Inc(K);
      If Length(R) > 200 Then
      Begin
        Out(1, R);
        R := '';
      End;
    End;
    Inc(I);
    If (I < A.N) And Not Stop Then R := R + ' ';
  End;
  If Not NoNl Then R := R + #10;
  Out(1, R);
  BiEcho := 0;
End;

{ ----- cd, pwd ----- }
Procedure SetPwd;
Var D : String;
Begin
  D := SysGetCwd;
  If D <> '' Then
  Begin
    SetVar('PWD', D);
    ExportVar('PWD', True);
  End;
End;

Function BiCd(Var A : TArgs) : LongInt;
Var D, Old : String; Show : Boolean;
Begin
  BiCd := 1;
  Show := False;
  If A.N > 2 Then
  Begin
    ShErr('cd: ' + Msg(mTooMany));
    Exit;
  End;
  If A.N < 2 Then
  Begin
    D := VarValue('HOME');
    If D = '' Then
    Begin
      ShErr('cd: ' + Msg(mNoHome));
      Exit;
    End;
  End
  Else D := A.It[1]^;
  If D = '-' Then
  Begin
    D := VarValue('OLDPWD');
    Show := True;
  End;
  Old := SysGetCwd;
  If SysChdir(D) < 0 Then
  Begin
    ShErr('cd: ' + D + ': ' + SysErrorText(SysErrno));
    Exit;
  End;
  SetVar('OLDPWD', Old);
  ExportVar('OLDPWD', True);
  SetPwd;
  If Show Then Say1(VarValue('PWD'));
  BiCd := 0;
End;

{ ----- export, readonly, unset, set, shift ----- }
Procedure ListVars(OnlyExp : Boolean; Const Pfx : String);
Var I : LongInt;
Begin
  For I := 0 To MAXVARS - 1 Do
    If Vars[I].Used And (Vars[I].Exp Or Not OnlyExp) Then
      Say1(Pfx + Vars[I].Name + '=''' + Vars[I].Val + '''');
End;

Function BiExport(Var A : TArgs; RO : Boolean) : LongInt;
Var I, K : LongInt; S, N : String; Off : Boolean;
Begin
  BiExport := 0;
  Off := False;
  If A.N = 1 Then
  Begin
    If RO Then ListVars(False, 'readonly ') Else ListVars(True, 'export ');
    Exit;
  End;
  For I := 1 To A.N - 1 Do
  Begin
    S := A.It[I]^;
    If S = '-p' Then
    Begin
      If RO Then ListVars(False, 'readonly ') Else ListVars(True, 'export ');
      Continue;
    End;
    If S = '-n' Then
    Begin
      Off := True;
      Continue;
    End;
    K := Pos('=', S);
    If K > 0 Then
    Begin
      N := Copy(S, 1, K - 1);
      If Not ValidName(N) Then
      Begin
        ShErr(N + ': ' + Msg(mNotId));
        BiExport := 1;
        Continue;
      End;
      SetVar(N, Copy(S, K + 1, 255));
    End
    Else N := S;
    If Not ValidName(N) Then
    Begin
      ShErr(N + ': ' + Msg(mNotId));
      BiExport := 1;
      Continue;
    End;
    If RO Then
    Begin
      If Not VarSet(N) Then SetVar(N, '');
      K := FindVar(N);
      If K >= 0 Then Vars[K].RO := True;
    End
    Else ExportVar(N, Not Off);
  End;
End;

Function BiUnset(Var A : TArgs) : LongInt;
Var I, K : LongInt; Fn : Boolean;
Begin
  Fn := False;
  BiUnset := 0;
  For I := 1 To A.N - 1 Do
  Begin
    If A.It[I]^ = '-f' Then Fn := True
    Else If A.It[I]^ = '-v' Then Fn := False
    Else If Fn Then
    Begin
      K := FindFunc(A.It[I]^);
      If K >= 0 Then Funcs[K].Used := False;
    End
    Else If BashMode And (Pos('[', A.It[I]^) > 0) And
            (A.It[I]^[Length(A.It[I]^)] = ']') Then
    Begin
      K := Pos('[', A.It[I]^);
      UnsetVar(ElemName(Copy(A.It[I]^, 1, K - 1),
               Copy(A.It[I]^, K + 1, Length(A.It[I]^) - K - 1)));
    End
    Else UnsetVar(A.It[I]^);
  End;
End;

Function BiShift(Var A : TArgs) : LongInt;
Var N, I : LongInt;
Begin
  N := 1;
  BiShift := 0;
  If A.N > 1 Then
    If Not StrInt(A.It[1]^, N) Then
    Begin
      ShErr('shift: ' + Msg(mBadNum));
      BiShift := 1;
      Exit;
    End;
  If (N < 0) Or (N > NPos) Then
  Begin
    BiShift := 1;
    Exit;
  End;
  For I := 1 To N Do FreeStr(PStr(MemL[0:PosArr + I * 4]));
  For I := N + 1 To NPos Do
    MemL[0:PosArr + (I - N) * 4] := MemL[0:PosArr + I * 4];
  NPos := NPos - N;
End;

Function OnOff(B : Boolean) : String;
Begin
  If B Then OnOff := 'on' Else OnOff := 'off';
End;

Function BiSet(Var A : TArgs) : LongInt;
Var I, K : LongInt; S : String; On : Boolean; A2 : TArgs;
Begin
  BiSet := 0;
  If A.N = 1 Then
  Begin
    ListVars(False, '');
    Exit;
  End;
  I := 1;
  While I < A.N Do
  Begin
    S := A.It[I]^;
    If S = '--' Then
    Begin
      ArgsInit(A2);
      For K := I + 1 To A.N - 1 Do ArgsAdd(A2, A.It[K]^);
      PosClear;
      HeapFree(1, 0, PosArr);
      PosSet(A2, 0);
      ArgsFree(A2);
      Exit;
    End;
    If (Length(S) > 1) And ((S[1] = '-') Or (S[1] = '+')) Then
    Begin
      On := S[1] = '-';
      For K := 2 To Length(S) Do
        Case S[K] Of
          'e' : OptE := On;
          'x' : OptX := On;
          'u' : OptU := On;
          'n' : OptN := On;
          'v' : OptV := On;
          'f' : OptNoGlob := On;
          'C' : OptNoClob := On;
          'a' : OptAllExp := On;
          'o' :
            Begin
              If I + 1 < A.N Then
              Begin
                Inc(I);
                If A.It[I]^ = 'pipefail' Then OptPipe := On
                Else If A.It[I]^ = 'errexit' Then OptE := On
                Else If A.It[I]^ = 'nounset' Then OptU := On
                Else If A.It[I]^ = 'xtrace' Then OptX := On
                Else If A.It[I]^ = 'verbose' Then OptV := On
                Else If A.It[I]^ = 'noexec' Then OptN := On
                Else If A.It[I]^ = 'noglob' Then OptNoGlob := On
                Else If A.It[I]^ = 'noclobber' Then OptNoClob := On
                Else If A.It[I]^ = 'allexport' Then OptAllExp := On;
              End
              Else
              Begin
                Say1('errexit       ' + Chr(9) + OnOff(OptE));
                Say1('noclobber     ' + Chr(9) + OnOff(OptNoClob));
                Say1('noexec        ' + Chr(9) + OnOff(OptN));
                Say1('noglob        ' + Chr(9) + OnOff(OptNoGlob));
                Say1('nounset       ' + Chr(9) + OnOff(OptU));
                Say1('pipefail      ' + Chr(9) + OnOff(OptPipe));
                Say1('verbose       ' + Chr(9) + OnOff(OptV));
                Say1('xtrace        ' + Chr(9) + OnOff(OptX));
              End;
            End;
        End;
    End
    Else
    Begin
      ArgsInit(A2);
      For K := I To A.N - 1 Do ArgsAdd(A2, A.It[K]^);
      PosClear;
      HeapFree(1, 0, PosArr);
      PosSet(A2, 0);
      ArgsFree(A2);
      Exit;
    End;
    Inc(I);
  End;
End;

{ ----- read ----- }
Function BiRead(Var A : TArgs) : LongInt;
Var
  I, N, K, X, V, Fd, Idx : LongInt; Raw : Boolean; Line, Ifs, Rest, Nm : String;
  C : Char; Eof, Esc : Boolean; Pr : String; Names : TArgs; NChars : LongInt;
  B : Array[0..3] Of Byte; ArrN : String; Delim : Char; Exact : Boolean;
  Tmo : LongInt; Pf : TPollFd;
Begin
  ArgsInit(Names);
  Raw := False;
  Pr := '';
  NChars := 0;
  Fd := 0;
  ArrN := '';
  Delim := #10;
  Exact := False;
  Tmo := -1;
  I := 1;
  While I < A.N Do
  Begin
    If A.It[I]^ = '-r' Then Raw := True
    Else If (A.It[I]^ = '-p') And (I + 1 < A.N) Then
    Begin
      Inc(I);
      Pr := A.It[I]^;
    End
    Else If (A.It[I]^ = '-n') And (I + 1 < A.N) Then
    Begin
      Inc(I);
      StrInt(A.It[I]^, NChars);
    End
    Else If (A.It[I]^ = '-N') And (I + 1 < A.N) Then
    Begin
      Inc(I);
      StrInt(A.It[I]^, NChars);
      Exact := True;
      Raw := True;
    End
    Else If (A.It[I]^ = '-a') And (I + 1 < A.N) Then
    Begin
      Inc(I);
      ArrN := A.It[I]^;
    End
    Else If (A.It[I]^ = '-d') And (I + 1 < A.N) Then
    Begin
      Inc(I);
      If A.It[I]^ = '' Then Delim := #0 Else Delim := A.It[I]^[1];
    End
    Else If (A.It[I]^ = '-u') And (I + 1 < A.N) Then
    Begin
      Inc(I);
      StrInt(A.It[I]^, Fd);
    End
    Else If (A.It[I]^ = '-t') And (I + 1 < A.N) Then
    Begin
      Inc(I);
      StrInt(A.It[I]^, Tmo);
    End
    Else If (A.It[I]^ = '-s') Or (A.It[I]^ = '-e') Then
    Else ArgsAdd(Names, A.It[I]^);
    Inc(I);
  End;
  If (Names.N = 0) And (ArrN = '') Then ArgsAdd(Names, 'REPLY');
  If (Pr <> '') And SysIsATty(Fd) Then Out(2, Pr);
  Line := '';
  Eof := False;
  Esc := False;
  While True Do
  Begin
    If Tmo >= 0 Then
    Begin
      Pf.Fd := Fd;
      Pf.Events := 1;
      Pf.REvents := 0;
      If SysPoll(LongInt(@Pf), 1, Tmo * 1000) <= 0 Then
      Begin
        Eof := True;
        Tmo := -2;
        Break;
      End;
    End;
    N := LnxSys3(3, Fd, LongInt(@B), 1);
    If N = -4 Then Continue;
    If N <= 0 Then
    Begin
      Eof := True;
      Break;
    End;
    C := Chr(B[0]);
    If Esc Then
    Begin
      Esc := False;
      If C <> #10 Then Line := Line + '\' + C;
      Continue;
    End;
    If (C = '\') And Not Raw Then
    Begin
      Esc := True;
      Continue;
    End;
    If (C = Delim) And Not Exact Then Break;
    If Length(Line) < 254 Then Line := Line + C;
    If (NChars > 0) And (Length(Line) >= NChars) Then Break;
  End;
  If Not GetVarRaw('IFS', Ifs) Then Ifs := ' ' + #9 + #10;
  If ArrN <> '' Then
  Begin
    { read -a : champs dans un tableau }
    ArrDeclare(ArrN, 1);
    ArrClear(ArrN);
    Rest := Line;
    Idx := 0;
    While True Do
    Begin
      While (Rest <> '') And (Pos(Rest[1], Ifs) > 0) And
            ((Rest[1] = ' ') Or (Rest[1] = #9) Or (Rest[1] = #10)) Do
        Delete(Rest, 1, 1);
      If Rest = '' Then Break;
      X := 1;
      While (X <= Length(Rest)) And (Pos(Rest[X], Ifs) = 0) Do Inc(X);
      SetVar(ArrN + '[' + IntStr(Idx) + ']', Copy(Rest, 1, X - 1));
      Inc(Idx);
      Rest := Copy(Rest, X + 1, 255);
    End;
    ArgsFree(Names);
    If Eof Then BiRead := 1 Else BiRead := 0;
    Exit;
  End;
  { decoupage en champs }
  Rest := Line;
  For K := 0 To Names.N - 1 Do
  Begin
    Nm := Names.It[K]^;
    { saute les blancs IFS de tete }
    While (Rest <> '') And (Pos(Rest[1], Ifs) > 0) And
          ((Rest[1] = ' ') Or (Rest[1] = #9) Or (Rest[1] = #10)) Do
      Delete(Rest, 1, 1);
    If K = Names.N - 1 Then
    Begin
      { dernier nom : tout le reste, blancs de fin retires }
      While (Rest <> '') And (Pos(Rest[Length(Rest)], Ifs) > 0) And
            ((Rest[Length(Rest)] = ' ') Or (Rest[Length(Rest)] = #9)) Do
        Delete(Rest, Length(Rest), 1);
      SetVar(Nm, Rest);
      Rest := '';
    End
    Else
    Begin
      X := 1;
      While (X <= Length(Rest)) And (Pos(Rest[X], Ifs) = 0) Do Inc(X);
      SetVar(Nm, Copy(Rest, 1, X - 1));
      Delete(Rest, 1, X);
    End;
  End;
  ArgsFree(Names);
  If Tmo = -2 Then BiRead := 142
  Else If Eof Then BiRead := 1 Else BiRead := 0;
End;

{ ----- test ----- }
Var
  TA : PArgs;
  TP, TN : LongInt;
  TErr : Boolean;

Function TestOr : Boolean; Forward;

Function TestUnary(Const Op, Arg : String) : Boolean;
Var St : TSysStat; X : LongInt; Ok : Boolean;
Begin
  TestUnary := False;
  If Op = '-z' Then TestUnary := Arg = ''
  Else If Op = '-n' Then TestUnary := Arg <> ''
  Else If Op = '-t' Then
  Begin
    If StrInt(Arg, X) Then TestUnary := SysIsATty(X);
  End
  Else If Op = '-e' Then TestUnary := SysStat(Arg, St) = 0
  Else If (Op = '-f') Then
  Begin
    If SysStat(Arg, St) = 0 Then TestUnary := (St.Mode And S_IFMT) = S_IFREG;
  End
  Else If Op = '-d' Then
  Begin
    If SysStat(Arg, St) = 0 Then TestUnary := (St.Mode And S_IFMT) = S_IFDIR;
  End
  Else If (Op = '-L') Or (Op = '-h') Then
  Begin
    If SysLStat(Arg, St) = 0 Then TestUnary := (St.Mode And S_IFMT) = S_IFLNK;
  End
  Else If Op = '-b' Then
  Begin
    If SysStat(Arg, St) = 0 Then TestUnary := (St.Mode And S_IFMT) = S_IFBLK;
  End
  Else If Op = '-c' Then
  Begin
    If SysStat(Arg, St) = 0 Then TestUnary := (St.Mode And S_IFMT) = S_IFCHR;
  End
  Else If Op = '-p' Then
  Begin
    If SysStat(Arg, St) = 0 Then TestUnary := (St.Mode And S_IFMT) = S_IFIFO;
  End
  Else If Op = '-s' Then
  Begin
    If SysStat(Arg, St) = 0 Then TestUnary := St.Size > 0;
  End
  Else If Op = '-r' Then TestUnary := SysAccess(Arg, 4) = 0
  Else If Op = '-w' Then TestUnary := SysAccess(Arg, 2) = 0
  Else If Op = '-x' Then TestUnary := SysAccess(Arg, 1) = 0
  Else If Op = '-u' Then
  Begin
    If SysStat(Arg, St) = 0 Then TestUnary := (St.Mode And $800) <> 0;
  End
  Else If Op = '-g' Then
  Begin
    If SysStat(Arg, St) = 0 Then TestUnary := (St.Mode And $400) <> 0;
  End
  Else If Op = '-k' Then
  Begin
    If SysStat(Arg, St) = 0 Then TestUnary := (St.Mode And $200) <> 0;
  End
  Else If Op = '-O' Then
  Begin
    If SysStat(Arg, St) = 0 Then TestUnary := St.Uid = Uid;
  End
  Else If Op = '-G' Then
  Begin
    If SysStat(Arg, St) = 0 Then TestUnary := St.Gid = SysGetGid;
  End;
End;

Function IsUnaryOp(Const S : String) : Boolean;
Begin
  IsUnaryOp := (Length(S) = 2) And (S[1] = '-') And
               (S[2] In ['z', 'n', 't', 'e', 'f', 'd', 'L', 'h', 'b', 'c', 'p',
                         's', 'r', 'w', 'x', 'u', 'g', 'k', 'O', 'G', 'S']);
End;

Function IsBinaryOp(Const S : String) : Boolean;
Begin
  IsBinaryOp := (S = '=') Or (S = '==') Or (S = '!=') Or (S = '<') Or
    (S = '>') Or (S = '-eq') Or (S = '-ne') Or (S = '-lt') Or (S = '-le') Or
    (S = '-gt') Or (S = '-ge') Or (S = '-nt') Or (S = '-ot') Or (S = '-ef');
End;

Function TestBinary(Const L, Op, R : String) : Boolean;
Var X, Y : LongInt; S1, S2 : TSysStat; Ok : Boolean;
Begin
  TestBinary := False;
  If (Op = '=') Or (Op = '==') Then TestBinary := L = R
  Else If Op = '!=' Then TestBinary := L <> R
  Else If Op = '<' Then TestBinary := L < R
  Else If Op = '>' Then TestBinary := L > R
  Else If (Op = '-nt') Or (Op = '-ot') Or (Op = '-ef') Then
  Begin
    Ok := (SysStat(L, S1) = 0) And (SysStat(R, S2) = 0);
    If Ok Then
    Begin
      If Op = '-nt' Then TestBinary := S1.MTime > S2.MTime
      Else If Op = '-ot' Then TestBinary := S1.MTime < S2.MTime
      Else TestBinary := (S1.Ino = S2.Ino) And (S1.Dev = S2.Dev);
    End;
  End
  Else
  Begin
    If (Not StrInt(L, X)) Or (Not StrInt(R, Y)) Then
    Begin
      ShErr('test: ' + Msg(mBadNum));
      TErr := True;
      Exit;
    End;
    If Op = '-eq' Then TestBinary := X = Y
    Else If Op = '-ne' Then TestBinary := X <> Y
    Else If Op = '-lt' Then TestBinary := X < Y
    Else If Op = '-le' Then TestBinary := X <= Y
    Else If Op = '-gt' Then TestBinary := X > Y
    Else TestBinary := X >= Y;
  End;
End;

Function TestPrimary : Boolean;
Var S, S2, S3 : String; R : Boolean;
Begin
  TestPrimary := False;
  If TP >= TN Then
  Begin
    TErr := True;
    Exit;
  End;
  S := TA^.It[TP]^;
  If S = '(' Then
  Begin
    Inc(TP);
    R := TestOr;
    If (TP < TN) And (TA^.It[TP]^ = ')') Then Inc(TP) Else TErr := True;
    TestPrimary := R;
    Exit;
  End;
  If S = '!' Then
  Begin
    If (TN - TP >= 2) Then
    Begin
      Inc(TP);
      TestPrimary := Not TestPrimary;
      Exit;
    End;
  End;
  { binaire : arg op arg }
  If (TP + 2 < TN) And IsBinaryOp(TA^.It[TP + 1]^) Then
  Begin
    S2 := TA^.It[TP + 1]^;
    S3 := TA^.It[TP + 2]^;
    TP := TP + 3;
    TestPrimary := TestBinary(S, S2, S3);
    Exit;
  End;
  If IsUnaryOp(S) And (TP + 1 < TN) Then
  Begin
    S2 := TA^.It[TP + 1]^;
    TP := TP + 2;
    TestPrimary := TestUnary(S, S2);
    Exit;
  End;
  Inc(TP);
  TestPrimary := S <> '';
End;

Function TestAnd : Boolean;
Var R : Boolean;
Begin
  R := TestPrimary;
  While (TP < TN) And (TA^.It[TP]^ = '-a') Do
  Begin
    Inc(TP);
    If Not TestPrimary Then R := False;
  End;
  TestAnd := R;
End;

Function TestOr : Boolean;
Var R : Boolean;
Begin
  R := TestAnd;
  While (TP < TN) And (TA^.It[TP]^ = '-o') Do
  Begin
    Inc(TP);
    If TestAnd Then R := True;
  End;
  TestOr := R;
End;

Function BiTest(Var A : TArgs; Bracket : Boolean) : LongInt;
Var R : Boolean;
Begin
  TA := @A;
  TP := 1;
  TN := A.N;
  TErr := False;
  If Bracket Then
  Begin
    If (TN < 2) Or (A.It[TN - 1]^ <> ']') Then
    Begin
      ShErr('[: ' + Msg(mSyntax));
      BiTest := 2;
      Exit;
    End;
    Dec(TN);
  End;
  If TN = 1 Then
  Begin
    BiTest := 1;
    Exit;
  End;
  R := TestOr;
  If TErr Or (TP < TN) Then
  Begin
    If Not TErr Then ShErr('test: ' + Msg(mSyntax));
    BiTest := 2;
    Exit;
  End;
  If R Then BiTest := 0 Else BiTest := 1;
End;

{ ----- trap ----- }

{ ---------- [[ expression ]] ---------- }

Var
  DbCur : PWd;
  DbErr : Boolean;

Function DbOr : Boolean; Forward;

Function DbIsOp(W : PWd; Const Op : String) : Boolean;
Begin
  DbIsOp := (W <> Nil) And W^.IsAssign And (W^.S = Op);
End;

Function DbBinWord(W : PWd) : Boolean;
Begin
  DbBinWord := False;
  If W = Nil Then Exit;
  If W^.IsAssign Then DbBinWord := (W^.S = '<') Or (W^.S = '>')
  Else DbBinWord := (W^.S = '==') Or (W^.S = '=') Or (W^.S = '!=') Or
    (W^.S = '=~') Or IsBinaryOp(W^.S);
End;

Function DbRegex(Const Txt : String; W : PWd) : Boolean;
Var E : TExp; Pat : String; K, Prog, G : LongInt; T : String;
Begin
  DbRegex := False;
  ExpInit(E, Nil, True);
  ExpandInto(E, W^.S, False);
  Pat := '';
  For K := 1 To Length(E.S) Do
  Begin
    If (E.F[K] = '1') And (E.S[K] In ['.', '[', ']', '(', ')', '*', '+', '?',
       '{', '}', '|', '^', '$', '\\']) Then Pat := Pat + '\\';
    Pat := Pat + E.S[K];
  End;
  ReN := 0;
  Prog := ReCompile(Pat, True, False);
  If Prog < 0 Then
  Begin
    DbErr := True;
    Exit;
  End;
  T := Txt;
  If Not ReSearch(Prog, LongInt(@T[1]), Length(T), 0, True) Then
  Begin
    ArrClear('BASH_REMATCH');
    Exit;
  End;
  ArrDeclare('BASH_REMATCH', 1);
  ArrClear('BASH_REMATCH');
  For G := 0 To ReProg[Prog].Y Do
    If (G <= 9) And (ReCap[2 * G] >= 0) Then
      SetVar('BASH_REMATCH[' + IntStr(G) + ']',
             Copy(T, ReCap[2 * G] + 1, ReCap[2 * G + 1] - ReCap[2 * G]))
    Else If G <= 9 Then SetVar('BASH_REMATCH[' + IntStr(G) + ']', '');
  DbRegex := True;
End;

Function DbPrimary : Boolean;
Var A, B, Op : String; W, R : PWd; Res : Boolean; X, Y : LongInt; E : TExp;
Begin
  DbPrimary := False;
  If DbCur = Nil Then
  Begin
    DbErr := True;
    Exit;
  End;
  If DbIsOp(DbCur, '(') Then
  Begin
    DbCur := DbCur^.Next;
    Res := DbOr;
    If DbIsOp(DbCur, ')') Then DbCur := DbCur^.Next Else DbErr := True;
    DbPrimary := Res;
    Exit;
  End;
  If (Not DbCur^.IsAssign) And (DbCur^.S = '!') Then
  Begin
    DbCur := DbCur^.Next;
    DbPrimary := Not DbPrimary;
    Exit;
  End;
  W := DbCur;
  If (Not W^.IsAssign) And (Length(W^.S) = 2) And (W^.S[1] = '-') And
     (W^.Next <> Nil) And Not DbBinWord(W^.Next) And Not W^.Next^.IsAssign Then
  Begin
    A := ExpandStr(W^.Next^.S);
    DbCur := W^.Next^.Next;
    If W^.S = '-v' Then
    Begin
      If Pos('[', A) > 0 Then
        DbPrimary := VarSet(ElemName(Copy(A, 1, Pos('[', A) - 1),
                       Copy(A, Pos('[', A) + 1, Length(A) - Pos('[', A) - 1)))
      Else DbPrimary := VarSet(A);
    End
    Else If W^.S = '-R' Then DbPrimary := VarSet(A)
    Else If W^.S = '-N' Then DbPrimary := TestUnary('-s', A)
    Else If W^.S = '-a' Then DbPrimary := TestUnary('-e', A)
    Else If W^.S = '-o' Then DbPrimary := False
    Else If W^.S = '-S' Then DbPrimary := TestUnary('-p', A)
    Else If IsUnaryOp(W^.S) Then DbPrimary := TestUnary(W^.S, A)
    Else DbErr := True;
    Exit;
  End;
  A := ExpandStr(W^.S);
  If DbBinWord(W^.Next) Then
  Begin
    Op := W^.Next^.S;
    R := W^.Next^.Next;
    If R = Nil Then
    Begin
      DbErr := True;
      Exit;
    End;
    DbCur := R^.Next;
    If (Op = '==') Or (Op = '=') Or (Op = '!=') Then
    Begin
      ExpInit(E, Nil, True);
      ExpandInto(E, R^.S, False);
      Res := PatMatch(E.S, E.F, A);
      If Op = '!=' Then Res := Not Res;
      DbPrimary := Res;
    End
    Else If Op = '=~' Then DbPrimary := DbRegex(A, R)
    Else If (Op = '<') Or (Op = '>') Or (Op = '-nt') Or (Op = '-ot') Or
            (Op = '-ef') Then
      DbPrimary := TestBinary(A, Op, ExpandStr(R^.S))
    Else
    Begin
      B := ExpandStr(R^.S);
      X := ArithEval(A);
      Y := ArithEval(B);
      If Op = '-eq' Then DbPrimary := X = Y
      Else If Op = '-ne' Then DbPrimary := X <> Y
      Else If Op = '-lt' Then DbPrimary := X < Y
      Else If Op = '-le' Then DbPrimary := X <= Y
      Else If Op = '-gt' Then DbPrimary := X > Y
      Else DbPrimary := X >= Y;
    End;
    Exit;
  End;
  DbCur := W^.Next;
  DbPrimary := A <> '';
End;

Function DbAnd : Boolean;
Var R, R2 : Boolean;
Begin
  R := DbPrimary;
  While DbIsOp(DbCur, '&&') Do
  Begin
    DbCur := DbCur^.Next;
    R2 := DbPrimary;
    R := R And R2;
  End;
  DbAnd := R;
End;

Function DbOr : Boolean;
Var R, R2 : Boolean;
Begin
  R := DbAnd;
  While DbIsOp(DbCur, '||') Do
  Begin
    DbCur := DbCur^.Next;
    R2 := DbAnd;
    R := R Or R2;
  End;
  DbOr := R;
End;

Function ExecDBr(N : PNode) : LongInt;
Var R : Boolean; SaveCur : PWd; SaveErr, SaveEx : Boolean;
Begin
  SaveCur := DbCur;
  SaveErr := DbErr;
  SaveEx := ExtGlob;
  ExtGlob := True;
  DbCur := N^.Words;
  DbErr := False;
  R := DbOr;
  ExtGlob := SaveEx;
  If DbErr Or (DbCur <> Nil) Then
  Begin
    ShErr(Msg(mSyntax) + ' [[');
    ExecDBr := 2;
  End
  Else If R Then ExecDBr := 0
  Else ExecDBr := 1;
  DbCur := SaveCur;
  DbErr := SaveErr;
End;

Function BiTrap(Var A : TArgs) : LongInt;
Var I, S : LongInt; Cmd : String;
Begin
  BiTrap := 0;
  If A.N = 1 Then
  Begin
    For I := 0 To 35 Do
      If TrapCmd[I] <> Nil Then
      Begin
        If I = 33 Then Say1('trap -- ''' + TrapCmd[I]^ + ''' ERR')
        Else If I = 34 Then Say1('trap -- ''' + TrapCmd[I]^ + ''' DEBUG')
        Else If I = 35 Then Say1('trap -- ''' + TrapCmd[I]^ + ''' RETURN')
        Else Say1('trap -- ''' + TrapCmd[I]^ + ''' SIG' + SigNames[I]);
      End;
    Exit;
  End;
  I := 1;
  If (A.N = 2) Or (A.It[1]^ = '-') Then
  Begin
    Cmd := '-';
    If A.N > 2 Then I := 2;
  End
  Else
  Begin
    Cmd := A.It[1]^;
    I := 2;
  End;
  If (A.N = 2) And (A.It[1]^ <> '-') Then
  Begin
    { trap SIGNAL : retablit le comportement par defaut }
    Cmd := '-';
    I := 1;
  End;
  While I < A.N Do
  Begin
    S := SigNum(A.It[I]^);
    If S < 0 Then
    Begin
      ShErr('trap: ' + A.It[I]^ + ': ' + Msg(mNoTrap));
      BiTrap := 1;
    End
    Else
    Begin
      FreeStr(TrapCmd[S]);
      TrapCmd[S] := Nil;
      TrapPend[S] := 0;
      If Cmd = '-' Then
      Begin
        If (S > 0) And (S < 33) Then
        Begin
          If S = SIGINT Then SysSigAction(S, LongInt(@IntHandler), 0)
          Else If (S <> SIGKILL) And (S <> SIGSTOP) Then
          Begin
            If (Not Interactive) Or ((S <> SIGQUIT) And (S <> SIGTSTP) And
                (S <> SIGTTIN) And (S <> SIGTTOU) And (S <> SIGTERM)) Then
              SysSigAction(S, SIG_DFL, 0)
            Else SysSigAction(S, SIG_IGN, 0);
          End;
        End;
      End
      Else
      Begin
        TrapCmd[S] := MkStr(Cmd);
        If (S > 0) And (S < 33) Then
        Begin
          If Cmd = '' Then SysSigAction(S, SIG_IGN, 0)
          Else If (S <> SIGKILL) And (S <> SIGSTOP) Then
            SysSigAction(S, LongInt(@TrapHandler), 0);
        End;
      End;
    End;
    Inc(I);
  End;
End;

{ ----- type, command ----- }
Function DescribeCmd(Const N : String; Verbose : Boolean) : Boolean;
Var K : LongInt; P : String;
Begin
  DescribeCmd := True;
  K := FindAlias(N);
  If K >= 0 Then
  Begin
    If Verbose Then Say1(N + ' is aliased to `' + Aliases[K].Val + '''')
    Else Say1('alias ' + N + '=''' + Aliases[K].Val + '''');
    Exit;
  End;
  If FindFunc(N) >= 0 Then
  Begin
    If Verbose Then Say1(N + ' is a function') Else Say1(N);
    Exit;
  End;
  If BuiltinId(N) > 0 Then
  Begin
    If Verbose Then Say1(N + ' is a shell builtin') Else Say1(N);
    Exit;
  End;
  If PathOf(N, P) = 0 Then
  Begin
    If Verbose Then Say1(N + ' is ' + P) Else Say1(P);
    Exit;
  End;
  If Verbose Then ShErr(N + ': ' + Msg(mNotFound));
  DescribeCmd := False;
End;

Function BiType(Var A : TArgs) : LongInt;
Var I : LongInt;
Begin
  BiType := 0;
  For I := 1 To A.N - 1 Do
    If Not DescribeCmd(A.It[I]^, True) Then BiType := 1;
End;

{ ----- umask ----- }
Function BiUmask(Var A : TArgs) : LongInt;
Var M, X, I : LongInt; S : String;
Begin
  BiUmask := 0;
  If (A.N = 1) Or (A.It[1]^ = '-S') Then
  Begin
    M := SysUmask(0);
    SysUmask(M);
    If (A.N > 1) Then
    Begin
      S := 'u=';
      If (M And 64) = 0 Then S := S + 'r';
      If (M And 128) = 0 Then S := S + 'w';
      If (M And 256) = 0 Then S := S + 'x';
      S := S + ',g=';
      If (M And 8) = 0 Then S := S + 'r';
      If (M And 16) = 0 Then S := S + 'w';
      If (M And 32) = 0 Then S := S + 'x';
      S := S + ',o=';
      If (M And 1) = 0 Then S := S + 'r';
      If (M And 2) = 0 Then S := S + 'w';
      If (M And 4) = 0 Then S := S + 'x';
      Say1(S);
    End
    Else
    Begin
      S := '0' + Chr(48 + (M Shr 6) And 7) + Chr(48 + (M Shr 3) And 7) +
           Chr(48 + M And 7);
      Say1(S);
    End;
    Exit;
  End;
  S := A.It[1]^;
  X := 0;
  For I := 1 To Length(S) Do
  Begin
    If (S[I] < '0') Or (S[I] > '7') Then
    Begin
      ShErr('umask: ' + S + ': ' + Msg(mBadNum));
      BiUmask := 1;
      Exit;
    End;
    X := X * 8 + Ord(S[I]) - 48;
  End;
  SysUmask(X);
End;

{ ----- alias ----- }
Function BiAlias(Var A : TArgs) : LongInt;
Var I, K, J : LongInt; N, V : String;
Begin
  BiAlias := 0;
  If A.N = 1 Then
  Begin
    For I := 0 To MAXALIAS - 1 Do
      If Aliases[I].Used Then
        Say1('alias ' + Aliases[I].Name + '=''' + Aliases[I].Val + '''');
    Exit;
  End;
  For I := 1 To A.N - 1 Do
  Begin
    K := Pos('=', A.It[I]^);
    If K = 0 Then
    Begin
      J := FindAlias(A.It[I]^);
      If J >= 0 Then Say1('alias ' + Aliases[J].Name + '=''' + Aliases[J].Val +
                          '''')
      Else
      Begin
        ShErr('alias: ' + A.It[I]^ + ': ' + Msg(mNoSuchVar));
        BiAlias := 1;
      End;
    End
    Else
    Begin
      N := Copy(A.It[I]^, 1, K - 1);
      V := Copy(A.It[I]^, K + 1, 120);
      J := FindAlias(N);
      If J < 0 Then
        For J := 0 To MAXALIAS - 1 Do
          If Not Aliases[J].Used Then Break;
      If (J >= 0) And (J < MAXALIAS) Then
      Begin
        Aliases[J].Used := True;
        Aliases[J].Name := N;
        Aliases[J].Val := V;
      End;
    End;
  End;
End;

Function BiUnalias(Var A : TArgs) : LongInt;
Var I, J : LongInt;
Begin
  BiUnalias := 0;
  For I := 1 To A.N - 1 Do
  Begin
    If A.It[I]^ = '-a' Then
      For J := 0 To MAXALIAS - 1 Do Aliases[J].Used := False
    Else
    Begin
      J := FindAlias(A.It[I]^);
      If J >= 0 Then Aliases[J].Used := False
      Else BiUnalias := 1;
    End;
  End;
End;

{ ----- eval, source, exec ----- }
Function BiEval(Var A : TArgs) : LongInt;
Var S : String;
Begin
  S := Join(A, 1);
  LastStatus := 0;
  RunText(S);
  BiEval := LastStatus;
End;

Function BiSource(Var A : TArgs) : LongInt;
Var P : String; SaveArr, SaveN : LongInt; A2 : TArgs; I : LongInt; Ok : Boolean;
Begin
  If A.N < 2 Then
  Begin
    ShErr('.: ' + Msg(mUsage) + ': . file [args]');
    BiSource := 2;
    Exit;
  End;
  If Pos('/', A.It[1]^) > 0 Then P := A.It[1]^
  Else If PathOf(A.It[1]^, P) <> 0 Then P := A.It[1]^;
  SaveArr := PosArr;
  SaveN := NPos;
  If A.N > 2 Then
  Begin
    ArgsInit(A2);
    For I := 2 To A.N - 1 Do ArgsAdd(A2, A.It[I]^);
    PosSet(A2, 0);
    ArgsFree(A2);
  End;
  LastStatus := 0;
  Ok := RunFile(P, False);
  If Not Ok Then
  Begin
    ShErr(A.It[1]^ + ': ' + SysErrorText(SysErrno));
    BiSource := 1;
  End
  Else BiSource := LastStatus;
  If RetFlag <> 0 Then RetFlag := 0;
  If A.N > 2 Then
  Begin
    PosClear;
    HeapFree(1, 0, PosArr);
    PosArr := SaveArr;
    NPos := SaveN;
  End;
End;

Function BiExec(Var A : TArgs) : LongInt;
Var A2 : TArgs; I : LongInt;
Begin
  BiExec := 0;
  If A.N = 1 Then Exit;
  ArgsInit(A2);
  For I := 1 To A.N - 1 Do ArgsAdd(A2, A.It[I]^);
  If HaveTerm Then SysTcSetAttr(0, 1, SavedTerm);
  ExecProgram(A2);
End;

{ ----- history ----- }
Function BiHistory(Var A : TArgs) : LongInt;
Var I : LongInt;
Begin
  BiHistory := 0;
  If (A.N > 1) And (A.It[1]^ = '-c') Then
  Begin
    For I := 0 To NHist - 1 Do FreeStr(Hist[I]);
    NHist := 0;
    Exit;
  End;
  For I := 0 To NHist - 1 Do
    Say1(IntStr(I + 1) + '  ' + Hist[I]^);
End;

{ ----- travaux ----- }
Function JobSpec(Const S : String) : LongInt;
{ %n, %%, %+, %-, %cmd ou un pid ; -1 si inexistant }
Var X, J : LongInt; T : String;
Begin
  JobSpec := -1;
  If (S = '') Or (S = '%') Or (S = '%%') Or (S = '%+') Or (S = '%-') Then
  Begin
    For J := MAXJOBS - 1 DownTo 0 Do
      If Jobs[J].State <> jFree Then
      Begin
        JobSpec := J;
        Exit;
      End;
    Exit;
  End;
  If S[1] = '%' Then
  Begin
    T := Copy(S, 2, 255);
    If StrInt(T, X) Then
    Begin
      If (X >= 1) And (X <= MAXJOBS) And (Jobs[X - 1].State <> jFree) Then
        JobSpec := X - 1;
      Exit;
    End;
    For J := 0 To MAXJOBS - 1 Do
      If (Jobs[J].State <> jFree) And (Pos(T, Jobs[J].Cmd) = 1) Then
      Begin
        JobSpec := J;
        Exit;
      End;
    Exit;
  End;
  If StrInt(S, X) Then
    For J := 0 To MAXJOBS - 1 Do
      If Jobs[J].State <> jFree Then
        If (Jobs[J].Pgid = X) Then
        Begin
          JobSpec := J;
          Exit;
        End;
End;

Function BiJobs(Var A : TArgs) : LongInt;
Var J : LongInt;
Begin
  ReapJobs(False);
  For J := 0 To MAXJOBS - 1 Do
    If Jobs[J].State <> jFree Then
    Begin
      ShowJob(J, True);
      If Jobs[J].State = jDone Then Jobs[J].State := jFree;
    End;
  BiJobs := 0;
End;

Function BiFg(Var A : TArgs; Bg : Boolean) : LongInt;
Var J : LongInt; S : String;
Begin
  If A.N > 1 Then S := A.It[1]^ Else S := '';
  J := JobSpec(S);
  If J < 0 Then
  Begin
    ShErr('fg: ' + Msg(mNoJob));
    BiFg := 1;
    Exit;
  End;
  Say1(Jobs[J].Cmd);
  If Jobs[J].State = jStopped Then
  Begin
    Jobs[J].State := jRunning;
    SysKill(-Jobs[J].Pgid, SIGCONT);
  End;
  If Bg Then
  Begin
    BiFg := 0;
    Exit;
  End;
  GiveTerm(Jobs[J].Pgid);
  Jobs[J].Notified := False;
  BiFg := JobWait(J);
End;

Function BiWait(Var A : TArgs) : LongInt;
Var I, J, St : LongInt;
Begin
  BiWait := 0;
  If A.N = 1 Then
  Begin
    For J := 0 To MAXJOBS - 1 Do
      If Jobs[J].State = jRunning Then JobWait(J);
    Exit;
  End;
  For I := 1 To A.N - 1 Do
  Begin
    J := JobSpec(A.It[I]^);
    If J < 0 Then BiWait := 127
    Else
    Begin
      St := JobWait(J);
      BiWait := St;
    End;
  End;
End;

Function BiKill(Var A : TArgs) : LongInt;
Var I, S, X, J : LongInt; Sg : String;
Begin
  BiKill := 0;
  S := SIGTERM;
  I := 1;
  If A.N = 1 Then
  Begin
    ShErr('kill: ' + Msg(mUsage) + ': kill [-s sig | -sig] pid...');
    BiKill := 2;
    Exit;
  End;
  If A.It[1]^ = '-l' Then
  Begin
    For J := 1 To NSIG - 1 Do Out(1, IntStr(J) + ') SIG' + SigNames[J] + '  ');
    Out(1, #10);
    Exit;
  End;
  If (A.It[1]^ = '-s') And (A.N > 2) Then
  Begin
    S := SigNum(A.It[2]^);
    I := 3;
  End
  Else If (A.It[1]^[1] = '-') And (Length(A.It[1]^) > 1) Then
  Begin
    S := SigNum(Copy(A.It[1]^, 2, 20));
    I := 2;
  End;
  If S < 0 Then
  Begin
    ShErr('kill: ' + Msg(mNoTrap));
    BiKill := 1;
    Exit;
  End;
  While I < A.N Do
  Begin
    Sg := A.It[I]^;
    If Sg[1] = '%' Then
    Begin
      J := JobSpec(Sg);
      If J < 0 Then
      Begin
        ShErr('kill: ' + Sg + ': ' + Msg(mNoJob));
        BiKill := 1;
      End
      Else
      Begin
        SysKill(-Jobs[J].Pgid, S);
        If (S = SIGCONT) And (Jobs[J].State = jStopped) Then
          Jobs[J].State := jRunning;
      End;
    End
    Else If StrInt(Sg, X) Then
    Begin
      If SysKill(X, S) < 0 Then
      Begin
        ShErr('kill: ' + Sg + ': ' + SysErrorText(SysErrno));
        BiKill := 1;
      End;
    End
    Else
    Begin
      ShErr('kill: ' + Sg + ': ' + Msg(mBadNum));
      BiKill := 1;
    End;
    Inc(I);
  End;
End;

{ ----- local, getopts, command ----- }
 memorise la variable N (et ses elements) pour la restauration en sortie de
  fonction ; la variable locale part vide }
Procedure LocalSave(Const N : String);
Var K, J : LongInt; Keys : TArgs;
Begin
  If InFunc = 0 Then Exit;
  { deja local dans ce cadre ? }
  For K := LocalFrame[LocalFP] To LocalSP - 1 Do
    If LocalName[K] = N Then Exit;
  If LocalSP > 250 Then Exit;
  K := FindVar(N);
  If (K >= 0) And (Vars[K].Kind > 0) Then
  Begin
    { le tableau est sauvegarde element par element }
    ArrKeys(N, Keys);
    For J := 0 To Keys.N - 1 Do
      If LocalSP < 250 Then
      Begin
        LocalName[LocalSP] := N + '[' + Keys.It[J]^ + ']';
        LocalOld[LocalSP] := MkStr(VarValue(N + '[' + Keys.It[J]^ + ']'));
        LocalKd[LocalSP] := 0;
        Inc(LocalSP);
      End;
    ArgsFree(Keys);
    LocalName[LocalSP] := '#clear:' + N;
    LocalOld[LocalSP] := Nil;
    Inc(LocalSP);
    ArrClear(N);
  End;
  LocalName[LocalSP] := N;
  K := FindVar(N);
  If K >= 0 Then
  Begin
    LocalOld[LocalSP] := MkStr(Vars[K].Val);
    LocalKd[LocalSP] := Vars[K].Kind;
  End
  Else
  Begin
    LocalOld[LocalSP] := Nil;
    LocalKd[LocalSP] := 0;
  End;
  Inc(LocalSP);
  If K >= 0 Then
  Begin
    Vars[K].Val := '';
    Vars[K].Kind := 0;
    Vars[K].RO := False;
  End;
End;

Procedure ShowDecl(I : LongInt);
Var F, S, Keys : String; K : LongInt; Ks : TArgs; Nm : String;
Begin
  Nm := Vars[I].Name;
  F := '-';
  If Vars[I].Kind = 1 Then F := F + 'a';
  If Vars[I].Kind = 2 Then F := F + 'A';
  If Vars[I].IntAttr Then F := F + 'i';
  If Vars[I].CaseAttr = 1 Then F := F + 'l';
  If Vars[I].CaseAttr = 2 Then F := F + 'u';
  If Vars[I].RO Then F := F + 'r';
  If Vars[I].Exp Then F := F + 'x';
  If F = '-' Then F := '--';
  If Vars[I].Kind > 0 Then
  Begin
    ArrKeys(Nm, Ks);
    S := '(';
    For K := 0 To Ks.N - 1 Do
    Begin
      If K > 0 Then S := S + ' ';
      S := S + '[' + Ks.It[K]^ + ']="' + VarValue(Nm + '[' + Ks.It[K]^ + ']') +
           '"';
    End;
    S := S + ')';
    ArgsFree(Ks);
    Say1('declare ' + F + ' ' + Nm + '=' + S);
  End
  Else Say1('declare ' + F + ' ' + Nm + '="' + Vars[I].Val + '"');
End;

{ declare / typeset / local / readonly (Mode 0 declare, 1 local) }
Function BiDeclare(Var A : TArgs; IsLocal : Boolean) : LongInt;
Var I, K, J, Kind, IntA, CaseA : LongInt; S, Nm, Sub, Raw, EN, Cur : String;
    FlA, FlAA, FlI, FlR, FlX, FlL, FlU, FlP, FlF, FlG, FlN : Boolean;
    OnI, OnR, OnX, App : Boolean; Opts : Boolean; Cnt : LongInt;
Begin
  BiDeclare := 0;
  FlA := False; FlAA := False; FlI := False; FlR := False; FlX := False;
  FlL := False; FlU := False; FlP := False; FlF := False; FlG := False;
  FlN := False; OnI := True; OnR := True; OnX := True;
  Opts := True;
  Cnt := 0;
  If IsLocal And (InFunc = 0) Then
  Begin
    ShErr('local: can only be used in a function');
    BiDeclare := 1;
    Exit;
  End;
  For I := 1 To A.N - 1 Do
  Begin
    S := A.It[I]^;
    If Opts And (Length(S) > 1) And ((S[1] = '-') Or (S[1] = '+')) And
       (Pos('=', S) = 0) Then
    Begin
      If S = '--' Then
      Begin
        Opts := False;
        Continue;
      End;
      For K := 2 To Length(S) Do
        Case S[K] Of
          'a' : FlA := True;
          'A' : FlAA := True;
          'i' : Begin FlI := True; OnI := S[1] = '-'; End;
          'r' : Begin FlR := True; OnR := S[1] = '-'; End;
          'x' : Begin FlX := True; OnX := S[1] = '-'; End;
          'l' : FlL := S[1] = '-';
          'u' : FlU := S[1] = '-';
          'p' : FlP := True;
          'f', 'F' : FlF := True;
          'g' : FlG := True;
          'n' : FlN := S[1] = '-';
          't' : ;
        End;
      Continue;
    End;
    Opts := False;
    Inc(Cnt);
    { nom, indice, +=, valeur brute }
    Nm := '';
    Raw := '';
    Sub := '';
    App := False;
    If Not SplitAssign(S, Nm, Sub, Raw, App) Then
    Begin
      Nm := S;
      Raw := #0;
    End;
    If Not ValidName(Nm) Then
    Begin
      ShErr(Nm + ': ' + Msg(mNotId));
      BiDeclare := 1;
      Continue;
    End;
    If FlP Then
    Begin
      K := FindVar(Nm);
      If K >= 0 Then ShowDecl(K) Else BiDeclare := 1;
      Continue;
    End;
    If FlF Then Continue;
    If (IsLocal Or (InFunc > 0)) And Not FlG Then LocalSave(Nm);
    If FlN Then
    Begin
      { nameref : la valeur est le nom de la cible }
      If Raw = #0 Then Raw := '';
      K := FindVar(Nm);
      If K < 0 Then
      Begin
        SetVar(Nm, Raw);
        K := FindVar(Nm);
      End
      Else Vars[K].Val := Raw;
      If K >= 0 Then Vars[K].Ref := True;
      AnyRef := True;
      Continue;
    End;
    If FlAA Then ArrDeclare(Nm, 2)
    Else If FlA Then ArrDeclare(Nm, 1);
    If Not VarSet(Nm) Then SetVar(Nm, '');
    K := FindVar(Nm);
    If K >= 0 Then
    Begin
      If FlI Then Vars[K].IntAttr := OnI;
      If FlL Then Vars[K].CaseAttr := 1;
      If FlU Then Vars[K].CaseAttr := 2;
      If FlX Then Vars[K].Exp := OnX;
    End;
    If Raw <> #0 Then
    Begin
      If (Raw <> '') And (Raw[1] = #5) Then
      Begin
        If (FlA Or FlAA) Then
        Else If ArrKind(Nm) = 0 Then ArrDeclare(Nm, 1);
        AssignCompound(Nm, App, Copy(Raw, 2, 2000));
      End
      Else If Sub <> '' Then
      Begin
        If ArrKind(Nm) = 0 Then ArrDeclare(Nm, 1);
        EN := ElemName(Nm, Sub);
        If App Then
        Begin
          GetVar(EN, Cur);
          Raw := Cur + Raw;
        End;
        SetVar(EN, Raw);
      End
      Else
      Begin
        If App Then
        Begin
          GetVar(Nm, Cur);
          If FlI Then Raw := IntStr(ArithEval(Cur) + ArithEval(Raw))
          Else Raw := Cur + Raw;
        End;
        SetVar(Nm, Raw);
      End;
    End;
    K := FindVar(Nm);
    If (K >= 0) And FlR Then Vars[K].RO := OnR;
  End;
  If (Cnt = 0) Or FlP Then
  Begin
    If (Cnt = 0) And Not FlF Then
      For I := 0 To MAXVARS - 1 Do
        If Vars[I].Used And (Pos('[', Vars[I].Name) = 0) Then
          If ((Not FlA) Or (Vars[I].Kind = 1)) And
             ((Not FlAA) Or (Vars[I].Kind = 2)) And
             ((Not FlX) Or Vars[I].Exp) And ((Not FlR) Or Vars[I].RO) Then
            ShowDecl(I);
  End;
End;

Function BiLocal(Var A : TArgs) : LongInt;
Begin
  BiLocal := BiDeclare(A, True);
End;

{ let "x=1+2" y=3 : chaque argument est une expression arithmetique }
Function BiLet(Var A : TArgs) : LongInt;
Var I : LongInt; V : LongInt;
Begin
  V := 0;
  BiLet := 1;
  If A.N < 2 Then
  Begin
    ShErr('let: expression expected');
    BiLet := 1;
    Exit;
  End;
  For I := 1 To A.N - 1 Do
  Begin
    V := ArithEval(A.It[I]^);
    If ArFailed Then
    Begin
      BiLet := 1;
      Exit;
    End;
  End;
  If V <> 0 Then BiLet := 0 Else BiLet := 1;
End;

{ mapfile / readarray [-t] [-n N] [-O origine] [-s N] [-d delim] [-u fd] [nom] }
Function BiMapfile(Var A : TArgs) : LongInt;
Var I, Fd, N, Org, Skip, Cnt, Idx, Lim : LongInt; Nm, L : String;
    Strip : Boolean;
    Delim : Char; C : Char; B : Array[0..3] Of Byte; Got : LongInt;
Begin
  Nm := 'MAPFILE';
  Strip := False;
  Fd := 0;
  Org := 0;
  Skip := 0;
  Lim := 0;
  Delim := #10;
  I := 1;
  While I < A.N Do
  Begin
    L := A.It[I]^;
    If L = '-t' Then Strip := True
    Else If (L = '-n') And (I + 1 < A.N) Then
    Begin
      Inc(I);
      StrInt(A.It[I]^, Lim);
    End
    Else If (L = '-O') And (I + 1 < A.N) Then
    Begin
      Inc(I);
      StrInt(A.It[I]^, Org);
    End
    Else If (L = '-s') And (I + 1 < A.N) Then
    Begin
      Inc(I);
      StrInt(A.It[I]^, Skip);
    End
    Else If (L = '-u') And (I + 1 < A.N) Then
    Begin
      Inc(I);
      StrInt(A.It[I]^, Fd);
    End
    Else If (L = '-d') And (I + 1 < A.N) Then
    Begin
      Inc(I);
      If A.It[I]^ = '' Then Delim := #0 Else Delim := A.It[I]^[1];
    End
    Else Nm := L;
    Inc(I);
  End;
  ArrDeclare(Nm, 1);
  If Org = 0 Then ArrClear(Nm);
  Idx := Org;
  Cnt := 0;
  While True Do
  Begin
    L := '';
    Got := 0;
    While True Do
    Begin
      N := LnxSys3(3, Fd, LongInt(@B), 1);
      If N = -4 Then Continue;
      If N <= 0 Then Break;
      Got := 1;
      C := Chr(B[0]);
      If C = Delim Then
      Begin
        If Not Strip Then L := L + C;
        Break;
      End;
      If Length(L) < 254 Then L := L + C;
    End;
    If (N <= 0) And (L = '') And (Got = 0) Then Break;
    Inc(Cnt);
    If Cnt > Skip Then
    Begin
      SetVar(Nm + '[' + IntStr(Idx) + ']', L);
      Inc(Idx);
    End;
    If (Lim > 0) And (Idx - Org >= Lim) Then Break;
    If N <= 0 Then Break;
  End;
  BiMapfile := 0;
End;

{ printf [-v var] format [arguments] }
Function BiPrintf(Var A : TArgs) : LongInt;
Var Fmt, Out_, Arg : String; I, K, J, AI, Wd, Pr, X, Rc : LongInt;
    VarN : String;
    Fl : String; Conv : Char; V : LongInt; D : Double; Left, Zero, Plus,
    Space, Alt, HavePr, Consumed, AnyArg : Boolean; Piece, Tmp : String;
    StartAI : LongInt; Stop : Boolean;

  Function NextArg : String;
  Begin
    If AI < A.N Then
    Begin
      NextArg := A.It[AI]^;
      Inc(AI);
      Consumed := True;
    End
    Else NextArg := '';
  End;

  Function ArgNum(Const S : String) : LongInt;
  Var Q : LongInt; Xv : LongInt;
  Begin
    ArgNum := 0;
    If S = '' Then Exit;
    If (S[1] = '''') Or (S[1] = '"') Then
    Begin
      If Length(S) > 1 Then ArgNum := Ord(S[2]);
      Exit;
    End;
    If StrInt(S, Xv) Then
    Begin
      ArgNum := Xv;
      Exit;
    End;
    If (Length(S) > 2) And (S[1] = '0') And ((S[2] = 'x') Or (S[2] = 'X')) Then
    Begin
      Xv := 0;
      For Q := 3 To Length(S) Do
        If UpCase(S[Q]) In ['0'..'9', 'A'..'F'] Then
          If S[Q] <= '9' Then Xv := Xv * 16 + Ord(S[Q]) - 48
          Else Xv := Xv * 16 + Ord(UpCase(S[Q])) - 55;
      ArgNum := Xv;
      Exit;
    End;
    If (Length(S) > 1) And (S[1] = '0') Then
    Begin
      Xv := 0;
      For Q := 2 To Length(S) Do
        If S[Q] In ['0'..'7'] Then Xv := Xv * 8 + Ord(S[Q]) - 48;
      ArgNum := Xv;
      Exit;
    End;
    ShErr('printf: ' + S + ': ' + Msg(mBadNum));
    Rc := 1;
  End;

  Function Pad(Const T : String; Fill : Char) : String;
  Var R : String;
  Begin
    R := T;
    If HavePr And (Conv = 's') And (Length(R) > Pr) Then R := Copy(R, 1, Pr);
    While Length(R) < Wd Do
      If Left Then R := R + ' '
      Else If (Fill = '0') And (Length(R) > 0) And
              ((R[1] = '-') Or (R[1] = '+')) And (Conv <> 's') Then
        R := R[1] + '0' + Copy(R, 2, 255)
      Else R := Fill + R;
    Pad := R;
  End;

  Function Radix(U : LongInt; Base : LongInt; Upper : Boolean) : String;
  Var R : String; Dg : LongInt; Neg : Boolean; Q : Double;
  Begin
    R := '';
    If U = 0 Then R := '0';
    While U <> 0 Do
    Begin
      If U < 0 Then
      Begin
        { entier non signe 32 bits }
        Q := U + 4294967296.0;
        Dg := Trunc(Q - Trunc(Q / Base) * Base);
        U := Trunc(Q / Base);
      End
      Else
      Begin
        Dg := U Mod Base;
        U := U Div Base;
      End;
      If Dg < 10 Then R := Chr(48 + Dg) + R
      Else If Upper Then R := Chr(55 + Dg) + R
      Else R := Chr(87 + Dg) + R;
    End;
    Radix := R;
  End;

  Function Esc(Const T : String; Var Stp : Boolean) : String;
  Var Q, Xv, Cn : LongInt; R : String;
  Begin
    R := '';
    Q := 1;
    Stp := False;
    While Q <= Length(T) Do
    Begin
      If (T[Q] = '\') And (Q < Length(T)) Then
      Begin
        Inc(Q);
        Case T[Q] Of
          'n' : R := R + #10;
          't' : R := R + #9;
          'r' : R := R + #13;
          'a' : R := R + #7;
          'b' : R := R + #8;
          'f' : R := R + #12;
          'v' : R := R + #11;
          'e', 'E' : R := R + #27;
          '\' : R := R + '\';
          '''' : R := R + '''';
          '"' : R := R + '"';
          'c' : Begin Stp := True; Break; End;
          '0'..'7' :
            Begin
              Xv := 0;
              Cn := 0;
              While (Q <= Length(T)) And (Cn < 3) And (T[Q] In ['0'..'7']) Do
              Begin
                Xv := Xv * 8 + Ord(T[Q]) - 48;
                Inc(Q);
                Inc(Cn);
              End;
              Dec(Q);
              R := R + Chr(Xv And 255);
            End;
          'x' :
            Begin
              Xv := 0;
              Cn := 0;
              Inc(Q);
              While (Q <= Length(T)) And (Cn < 2) And
                    (UpCase(T[Q]) In ['0'..'9', 'A'..'F']) Do
              Begin
                If T[Q] <= '9' Then Xv := Xv * 16 + Ord(T[Q]) - 48
                Else Xv := Xv * 16 + Ord(UpCase(T[Q])) - 55;
                Inc(Q);
                Inc(Cn);
              End;
              Dec(Q);
              R := R + Chr(Xv And 255);
            End;
        Else
          R := R + '\' + T[Q];
        End;
      End
      Else R := R + T[Q];
      Inc(Q);
    End;
    Esc := R;
  End;

Begin
  Rc := 0;
  VarN := '';
  AI := 1;
  If (AI < A.N) And (A.It[AI]^ = '-v') And (AI + 1 < A.N) Then
  Begin
    VarN := A.It[AI + 1]^;
    AI := AI + 2;
  End;
  If (AI < A.N) And (A.It[AI]^ = '--') Then Inc(AI);
  If AI >= A.N Then
  Begin
    ShErr('printf: usage: printf [-v var] format [arguments]');
    BiPrintf := 2;
    Exit;
  End;
  Fmt := A.It[AI]^;
  Inc(AI);
  Out_ := '';
  Stop := False;
  Repeat
    Consumed := False;
    AnyArg := AI < A.N;
    K := 1;
    While (K <= Length(Fmt)) And Not Stop Do
    Begin
      If Fmt[K] = '\' Then
      Begin
        J := K + 1;
        If (J <= Length(Fmt)) And (Fmt[J] In ['0'..'7']) Then
        Begin
          J := K + 1;
          While (J <= Length(Fmt)) And (J < K + 4) And (Fmt[J] In ['0'..'7']) Do
            Inc(J);
        End
        Else If (J <= Length(Fmt)) And (Fmt[J] = 'x') Then
        Begin
          Inc(J);
          While (J <= Length(Fmt)) And (J < K + 4) And
                (UpCase(Fmt[J]) In ['0'..'9', 'A'..'F']) Do Inc(J);
        End
        Else Inc(J);
        Out_ := Out_ + Esc(Copy(Fmt, K, J - K), Stop);
        K := J;
        Continue;
      End;
      If Fmt[K] <> '%' Then
      Begin
        Out_ := Out_ + Fmt[K];
        Inc(K);
        Continue;
      End;
      Inc(K);
      If K > Length(Fmt) Then
      Begin
        Out_ := Out_ + '%';
        Break;
      End;
      If Fmt[K] = '%' Then
      Begin
        Out_ := Out_ + '%';
        Inc(K);
        Continue;
      End;
      Left := False; Zero := False; Plus := False; Space := False; Alt := False;
      While (K <= Length(Fmt)) And (Fmt[K] In ['-', '0', '+', ' ', '#']) Do
      Begin
        Case Fmt[K] Of
          '-' : Left := True;
          '0' : Zero := True;
          '+' : Plus := True;
          ' ' : Space := True;
          '#' : Alt := True;
        End;
        Inc(K);
      End;
      Wd := 0;
      If (K <= Length(Fmt)) And (Fmt[K] = '*') Then
      Begin
        Wd := ArgNum(NextArg);
        If Wd < 0 Then
        Begin
          Left := True;
          Wd := -Wd;
        End;
        Inc(K);
      End
      Else
        While (K <= Length(Fmt)) And (Fmt[K] In ['0'..'9']) Do
        Begin
          Wd := Wd * 10 + Ord(Fmt[K]) - 48;
          Inc(K);
        End;
      HavePr := False;
      Pr := 0;
      If (K <= Length(Fmt)) And (Fmt[K] = '.') Then
      Begin
        HavePr := True;
        Inc(K);
        If (K <= Length(Fmt)) And (Fmt[K] = '*') Then
        Begin
          Pr := ArgNum(NextArg);
          Inc(K);
        End
        Else
          While (K <= Length(Fmt)) And (Fmt[K] In ['0'..'9']) Do
          Begin
            Pr := Pr * 10 + Ord(Fmt[K]) - 48;
            Inc(K);
          End;
      End;
      While (K <= Length(Fmt)) And (Fmt[K] In ['l', 'h', 'L', 'j', 'z', 't']) Do
        Inc(K);
      If K > Length(Fmt) Then Break;
      Conv := Fmt[K];
      Inc(K);
      Case Conv Of
        's' : Out_ := Out_ + Pad(NextArg, ' ');
        'b' :
          Begin
            Arg := Esc(NextArg, Stop);
            Out_ := Out_ + Pad(Arg, ' ');
          End;
        'q' :
          Begin
            Arg := NextArg;
            Piece := '';
            For J := 1 To Length(Arg) Do
              If Arg[J] In ['A'..'Z', 'a'..'z', '0'..'9', '_', '-', '.', '/',
                            ',', ':', '@', '%', '+', '='] Then
                Piece := Piece + Arg[J]
              Else Piece := Piece + '\' + Arg[J];
            If Arg = '' Then Piece := '''''';
            Out_ := Out_ + Pad(Piece, ' ');
          End;
        'c' :
          Begin
            Arg := NextArg;
            Out_ := Out_ + Pad(Copy(Arg, 1, 1), ' ');
          End;
        'd', 'i' :
          Begin
            V := ArgNum(NextArg);
            Piece := IntStr(V);
            If HavePr Then
              While Length(Piece) - Ord(V < 0) < Pr Do
                If V < 0 Then Piece := '-0' + Copy(Piece, 2, 255)
                Else Piece := '0' + Piece;
            If (V >= 0) And Plus Then Piece := '+' + Piece
            Else If (V >= 0) And Space Then Piece := ' ' + Piece;
            If Zero And Not Left And Not HavePr Then
              Out_ := Out_ + Pad(Piece, '0')
            Else Out_ := Out_ + Pad(Piece, ' ');
          End;
        'u', 'o', 'x', 'X' :
          Begin
            V := ArgNum(NextArg);
            If Conv = 'u' Then
            Begin
              If V < 0 Then
              Begin
                D := V + 4294967296.0;
                Str(D : 0 : 0, Piece);
              End
              Else Piece := IntStr(V);
            End
            Else If Conv = 'o' Then Piece := Radix(V, 8, False)
            Else Piece := Radix(V, 16, Conv = 'X');
            If HavePr Then
              While Length(Piece) < Pr Do Piece := '0' + Piece;
            If Alt And (V <> 0) Then
            Begin
              If Conv = 'x' Then Piece := '0x' + Piece
              Else If Conv = 'X' Then Piece := '0X' + Piece
              Else If Conv = 'o' Then Piece := '0' + Piece;
            End;
            If Zero And Not Left And Not HavePr Then
              Out_ := Out_ + Pad(Piece, '0')
            Else Out_ := Out_ + Pad(Piece, ' ');
          End;
        'f', 'F', 'e', 'E', 'g', 'G' :
          Begin
            Arg := NextArg;
            If Arg = '' Then D := 0
            Else If (Arg[1] = '''') Or (Arg[1] = '"') Then D := ArgNum(Arg)
            Else
            Begin
              Val(Arg, D, X);
              If X <> 0 Then
              Begin
                D := 0;
                ShErr('printf: ' + Arg + ': ' + Msg(mBadNum));
                Rc := 1;
              End;
            End;
            If Not HavePr Then Pr := 6;
            If (Conv = 'e') Or (Conv = 'E') Then
            Begin
              Str(D : 0 : Pr, Piece);
              Piece := Piece;
            End
            Else Str(D : 0 : Pr, Piece);
            If (Conv = 'g') Or (Conv = 'G') Then
            Begin
              Str(D : 0 : Pr, Piece);
              If Pos('.', Piece) > 0 Then
              Begin
                While (Piece <> '') And (Piece[Length(Piece)] = '0') Do
                  Delete(Piece, Length(Piece), 1);
                If (Piece <> '') And (Piece[Length(Piece)] = '.') Then
                  Delete(Piece, Length(Piece), 1);
              End;
            End;
            If (D >= 0) And Plus Then Piece := '+' + Piece
            Else If (D >= 0) And Space Then Piece := ' ' + Piece;
            If Zero And Not Left Then Out_ := Out_ + Pad(Piece, '0')
            Else Out_ := Out_ + Pad(Piece, ' ');
          End;
      Else
        Begin
          ShErr('printf: ' + Msg(mBadSub));
          Rc := 1;
        End;
      End;
    End;
  Until Stop Or (AI >= A.N) Or Not Consumed;
  If VarN <> '' Then SetVar(VarN, Out_)
  Else Out(1, Out_);
  BiPrintf := Rc;
End;

{ shopt [-s|-u|-q|-p] [nom...] }
Function ShoptRef(Const N : String; Var Found : Boolean) : Boolean;
Begin
  Found := True;
  If N = 'extglob' Then ShoptRef := ExtGlob
  Else If N = 'nullglob' Then ShoptRef := NullGlob
  Else If N = 'dotglob' Then ShoptRef := DotGlob
  Else If N = 'nocasematch' Then ShoptRef := NoCaseMatch
  Else If N = 'failglob' Then ShoptRef := FailGlob
  Else If N = 'globstar' Then ShoptRef := StarStar
  Else If (N = 'expand_aliases') Or (N = 'lastpipe') Or (N = 'cmdhist') Or
          (N = 'progcomp') Or (N = 'extquote') Or (N = 'interactive_comments')
          Or (N = 'sourcepath') Or (N = 'checkwinsize') Or (N = 'histappend')
          Or (N = 'inherit_errexit') Or (N = 'nocaseglob') Or
          (N = 'hostcomplete') Or (N = 'promptvars') Or (N = 'force_fignore')
    Then ShoptRef := (N = 'expand_aliases') Or (N = 'cmdhist') Or
         (N = 'progcomp') Or (N = 'extquote') Or (N = 'interactive_comments')
         Or (N = 'sourcepath') Or (N = 'hostcomplete') Or (N = 'promptvars')
         Or (N = 'force_fignore')
  Else
  Begin
    Found := False;
    ShoptRef := False;
  End;
End;

Function BiShopt(Var A : TArgs) : LongInt;
Var I : LongInt; Mode : Char; Nm : String; Ok, F : Boolean;
    Quiet, Prt : Boolean;
Const Names : String = 'dotglob,expand_aliases,extglob,failglob,globstar,' +
  'nullglob,nocasematch';
Begin
  BiShopt := 0;
  Mode := ' ';
  Quiet := False;
  Prt := False;
  I := 1;
  While (I < A.N) And (Length(A.It[I]^) > 1) And (A.It[I]^[1] = '-') Do
  Begin
    If A.It[I]^ = '-s' Then Mode := 's'
    Else If A.It[I]^ = '-u' Then Mode := 'u'
    Else If A.It[I]^ = '-q' Then Quiet := True
    Else If A.It[I]^ = '-p' Then Prt := True
    Else If A.It[I]^ = '-o' Then Mode := 'o';
    Inc(I);
  End;
  If I >= A.N Then
  Begin
    Nm := Names + ',';
    While Nm <> '' Do
    Begin
      Ok := ShoptRef(Copy(Nm, 1, Pos(',', Nm) - 1), F);
      If Ok Then Say1('shopt -s ' + Copy(Nm, 1, Pos(',', Nm) - 1))
      Else If Not Quiet Then
        Say1('shopt -u ' + Copy(Nm, 1, Pos(',', Nm) - 1));
      Delete(Nm, 1, Pos(',', Nm));
    End;
    Exit;
  End;
  While I < A.N Do
  Begin
    Nm := A.It[I]^;
    Ok := ShoptRef(Nm, F);
    If Not F Then
    Begin
      ShErr('shopt: ' + Nm + ': invalid shell option name');
      BiShopt := 1;
    End
    Else If Mode = 's' Then
    Begin
      If Nm = 'extglob' Then ExtGlob := True
      Else If Nm = 'nullglob' Then NullGlob := True
      Else If Nm = 'dotglob' Then DotGlob := True
      Else If Nm = 'nocasematch' Then NoCaseMatch := True
      Else If Nm = 'failglob' Then FailGlob := True
      Else If Nm = 'globstar' Then StarStar := True;
    End
    Else If Mode = 'u' Then
    Begin
      If Nm = 'extglob' Then ExtGlob := False
      Else If Nm = 'nullglob' Then NullGlob := False
      Else If Nm = 'dotglob' Then DotGlob := False
      Else If Nm = 'nocasematch' Then NoCaseMatch := False
      Else If Nm = 'failglob' Then FailGlob := False
      Else If Nm = 'globstar' Then StarStar := False;
    End
    Else
    Begin
      If Not Ok Then BiShopt := 1;
      If Not Quiet Then
        If Ok Then Say1('shopt -s ' + Nm) Else Say1('shopt -u ' + Nm);
    End;
    Inc(I);
  End;
End;

{ pile de repertoires : pushd popd dirs }
Var
  DirStack : Array[0..31] Of PStr;
  NDirs : LongInt;

Procedure ShowDirs;
Var S : String; K : LongInt;
Begin
  S := SysGetCwd;
  For K := NDirs - 1 DownTo 0 Do S := S + ' ' + DirStack[K]^;
  Say1(S);
End;

Function BiPushd(Var A : TArgs; Mode : LongInt) : LongInt;
Var Cur, Dst : String; K : LongInt; Cd : TArgs;
Begin
  BiPushd := 0;
  If Mode = 3 Then
  Begin
    ShowDirs;
    Exit;
  End;
  Cur := SysGetCwd;
  If Mode = 1 Then
  Begin
    If A.N < 2 Then
    Begin
      If NDirs = 0 Then
      Begin
        ShErr('pushd: no other directory');
        BiPushd := 1;
        Exit;
      End;
      Dst := DirStack[NDirs - 1]^;
      FreeStr(DirStack[NDirs - 1]);
      Dec(NDirs);
    End
    Else Dst := A.It[1]^;
    ArgsInit(Cd);
    ArgsAdd(Cd, 'cd');
    ArgsAdd(Cd, Dst);
    K := BiCd(Cd);
    ArgsFree(Cd);
    If K <> 0 Then
    Begin
      BiPushd := 1;
      Exit;
    End;
    If NDirs < 32 Then
    Begin
      DirStack[NDirs] := MkStr(Cur);
      Inc(NDirs);
    End;
    ShowDirs;
    Exit;
  End;
  { popd }
  If NDirs = 0 Then
  Begin
    ShErr('popd: directory stack empty');
    BiPushd := 1;
    Exit;
  End;
  Dst := DirStack[NDirs - 1]^;
  FreeStr(DirStack[NDirs - 1]);
  Dec(NDirs);
  ArgsInit(Cd);
  ArgsAdd(Cd, 'cd');
  ArgsAdd(Cd, Dst);
  BiPushd := BiCd(Cd);
  ArgsFree(Cd);
  ShowDirs;
End;

Function BiGetopts(Var A : TArgs) : LongInt;
Var
  Opts, Name, Cur, V : String; Ind, K, Len : LongInt; C : Char;
  Argc : LongInt; ArgV : TArgs; I : LongInt; Silent : Boolean;
Begin
  If A.N < 3 Then
  Begin
    BiGetopts := 2;
    Exit;
  End;
  Opts := A.It[1]^;
  Name := A.It[2]^;
  Silent := (Opts <> '') And (Opts[1] = ':');
  If Silent Then Delete(Opts, 1, 1);
  ArgsInit(ArgV);
  If A.N > 3 Then
    For I := 3 To A.N - 1 Do ArgsAdd(ArgV, A.It[I]^)
  Else
    For I := 1 To NPos Do ArgsAdd(ArgV, PosGet(I));
  If Not StrInt(VarValue('OPTIND'), Ind) Then Ind := 1;
  If Ind < 1 Then Ind := 1;
  If Ind > ArgV.N Then
  Begin
    SetVar(Name, '?');
    ArgsFree(ArgV);
    BiGetopts := 1;
    Exit;
  End;
  Cur := ArgV.It[Ind - 1]^;
  If (Length(Cur) < 2) Or (Cur[1] <> '-') Then
  Begin
    SetVar(Name, '?');
    ArgsFree(ArgV);
    BiGetopts := 1;
    Exit;
  End;
  If Cur = '--' Then
  Begin
    SetVar('OPTIND', IntStr(Ind + 1));
    SetVar(Name, '?');
    OptPos := 0;
    ArgsFree(ArgV);
    BiGetopts := 1;
    Exit;
  End;
  If OptPos < 2 Then OptPos := 2;
  C := Cur[OptPos];
  K := Pos(C, Opts);
  BiGetopts := 0;
  If (K = 0) Or (C = ':') Then
  Begin
    If Silent Then SetVar('OPTARG', C)
    Else
    Begin
      ShErr('illegal option -- ' + C);
      UnsetVar('OPTARG');
    End;
    SetVar(Name, '?');
    Inc(OptPos);
  End
  Else If (K < Length(Opts)) And (Opts[K + 1] = ':') Then
  Begin
    { option avec argument }
    If OptPos < Length(Cur) Then
    Begin
      SetVar('OPTARG', Copy(Cur, OptPos + 1, 255));
      Inc(Ind);
    End
    Else If Ind < ArgV.N Then
    begin
      SetVar('OPTARG', ArgV.It[Ind]^);
      Ind := Ind + 2;
    End
    Else
    Begin
      If Silent Then
      Begin
        SetVar(Name, ':');
        SetVar('OPTARG', C);
      End
      Else
      Begin
        ShErr('option requires an argument -- ' + C);
        SetVar(Name, '?');
      End;
      SetVar('OPTIND', IntStr(Ind + 1));
      OptPos := 0;
      ArgsFree(ArgV);
      Exit;
    End;
    SetVar(Name, C);
    OptPos := 0;
    SetVar('OPTIND', IntStr(Ind));
    ArgsFree(ArgV);
    Exit;
  End
  Else
  Begin
    SetVar(Name, C);
    Inc(OptPos);
    UnsetVar('OPTARG');
  End;
  If OptPos > Length(Cur) Then
  Begin
    OptPos := 0;
    Inc(Ind);
  End;
  SetVar('OPTIND', IntStr(Ind));
  ArgsFree(ArgV);
End;

Function BiCommand(Var A : TArgs; InPipe : Boolean) : LongInt;
Var I, Id : LongInt; A2 : TArgs; Verbose, Short, Any : Boolean;
Begin
  I := 1;
  Verbose := False;
  Short := False;
  While (I < A.N) And (Length(A.It[I]^) > 1) And (A.It[I]^[1] = '-') Do
  Begin
    If A.It[I]^ = '-v' Then Short := True
    Else If A.It[I]^ = '-V' Then Verbose := True
    Else If A.It[I]^ <> '-p' Then Break;
    Inc(I);
  End;
  If I >= A.N Then
  Begin
    BiCommand := 0;
    Exit;
  End;
  If Short Or Verbose Then
  Begin
    Any := True;
    While I < A.N Do
    Begin
      If Not DescribeCmd(A.It[I]^, Verbose) Then Any := False;
      Inc(I);
    End;
    If Any Then BiCommand := 0 Else BiCommand := 1;
    Exit;
  End;
  ArgsInit(A2);
  For Id := I To A.N - 1 Do ArgsAdd(A2, A.It[Id]^);
  Id := BuiltinId(A2.It[0]^);
  If Id > 0 Then BiCommand := RunBuiltin(Id, A2, InPipe)
  Else
  Begin
    { programme externe }
    I := ForkProc(0, True);
    If I = 0 Then ExecProgram(A2);
    If I < 0 Then BiCommand := 1
    Else
    Begin
      SysWaitPid(I, Id, 0);
      BiCommand := StatusOf(Id);
    End;
  End;
  ArgsFree(A2);
End;

Function BiBuiltin(Var A : TArgs; InPipe : Boolean) : LongInt;
Var A2 : TArgs; I, Id : LongInt;
Begin
  BiBuiltin := 0;
  If A.N < 2 Then Exit;
  Id := BuiltinId(A.It[1]^);
  If Id = 0 Then
  Begin
    ShErr(A.It[1]^ + ': ' + Msg(mNotBuiltin));
    BiBuiltin := 1;
    Exit;
  End;
  ArgsInit(A2);
  For I := 1 To A.N - 1 Do ArgsAdd(A2, A.It[I]^);
  BiBuiltin := RunBuiltin(Id, A2, InPipe);
  ArgsFree(A2);
End;

Function BiBreak(Var A : TArgs; Cont : Boolean) : LongInt;
Var N : LongInt;
Begin
  N := 1;
  If A.N > 1 Then
    If (Not StrInt(A.It[1]^, N)) Or (N < 1) Then N := 1;
  BiBreak := 0;
  If LoopDepth = 0 Then Exit;
  If N > LoopDepth Then N := LoopDepth;
  If Cont Then ContN := N Else BreakN := N;
End;

Function RunBuiltin(Id : LongInt; Var A : TArgs; InPipe : Boolean) : LongInt;
Var N : LongInt; S : String;
Begin
  RunBuiltin := 0;
  Case Id Of
    1, 33, 40 : RunBuiltin := 0;
    2, 3 : RunBuiltin := BiSource(A);
    4 : RunBuiltin := BiAlias(A);
    5 : RunBuiltin := BiFg(A, True);
    6 : RunBuiltin := BiBreak(A, False);
    7 : RunBuiltin := BiBuiltin(A, InPipe);
    8, 41 : RunBuiltin := BiCd(A);
    9 : RunBuiltin := BiCommand(A, InPipe);
    10 : RunBuiltin := BiBreak(A, True);
    11 : RunBuiltin := BiEcho(A);
    12 : RunBuiltin := BiEval(A);
    13 : RunBuiltin := BiExec(A);
    14, 42 :
      Begin
        If A.N > 1 Then
        Begin
          If Not StrInt(A.It[1]^, N) Then
          Begin
            ShErr('exit: ' + A.It[1]^ + ': ' + Msg(mBadNum));
            N := 2;
          End;
        End
        Else N := LastStatus;
        CleanExit(N);
      End;
    15 : RunBuiltin := BiExport(A, False);
    16 : RunBuiltin := 1;
    17 : RunBuiltin := BiFg(A, False);
    18 : RunBuiltin := BiGetopts(A);
    19 : RunBuiltin := BiHistory(A);
    20 : RunBuiltin := BiJobs(A);
    21 : RunBuiltin := BiKill(A);
    22 : RunBuiltin := BiLocal(A);
    23 : Begin Say1(SysGetCwd); RunBuiltin := 0; End;
    24 : RunBuiltin := BiRead(A);
    25 : RunBuiltin := BiExport(A, True);
    26 :
      Begin
        N := LastStatus;
        If A.N > 1 Then
          If Not StrInt(A.It[1]^, N) Then N := 2;
        LastStatus := N;
        RetFlag := 1;
        RunBuiltin := N;
      End;
    27 : RunBuiltin := BiSet(A);
    28 : RunBuiltin := BiShift(A);
    29 : RunBuiltin := BiTest(A, False);
    30 : RunBuiltin := BiTest(A, True);
    31 : Begin Say1('0m0.00s 0m0.00s'); Say1('0m0.00s 0m0.00s'); End;
    32 : RunBuiltin := BiTrap(A);
    34 : RunBuiltin := BiType(A);
    35 : Begin Say1('unlimited'); RunBuiltin := 0; End;
    36 : RunBuiltin := BiUmask(A);
    37 : RunBuiltin := BiUnalias(A);
    38 : RunBuiltin := BiUnset(A);
    39 : RunBuiltin := BiWait(A);
    43, 44 : RunBuiltin := BiDeclare(A, False);
    45 : RunBuiltin := BiLet(A);
    46, 47 : RunBuiltin := BiMapfile(A);
    48 : RunBuiltin := BiPrintf(A);
    49 : RunBuiltin := BiShopt(A);
    50 : RunBuiltin := BiPushd(A, 1);
    51 : RunBuiltin := BiPushd(A, 2);
    52 : RunBuiltin := BiPushd(A, 3);
    53, 54, 55, 56, 57, 58, 59 : RunBuiltin := 0;
  End;
End;

{ ---------- invite et editeur de ligne ---------- }

Function CwdShort : String;
Var D, H : String;
Begin
  D := VarValue('PWD');
  If D = '' Then D := SysGetCwd;
  H := VarValue('HOME');
  If (H <> '') And (H <> '/') And (Copy(D, 1, Length(H)) = H) And
     ((Length(D) = Length(H)) Or (D[Length(H) + 1] = '/')) Then
    D := '~' + Copy(D, Length(H) + 1, 255);
  CwdShort := D;
End;

Function PromptText(Mode : LongInt) : String;
Var P, R, Nm : String; K : LongInt; U : TSysPasswd; Un : TUtsName;
    Hn : String;
Begin
  If Mode = 2 Then
  Begin
    If Not GetVarRaw('PS2', P) Then P := '> ';
  End
  Else
  Begin
    If Not GetVarRaw('PS1', P) Then
    Begin
      If Uid = 0 Then P := '# ' Else P := '$ ';
    End;
  End;
  R := '';
  K := 1;
  While K <= Length(P) Do
  Begin
    If (P[K] = '\') And (K < Length(P)) Then
    Begin
      Inc(K);
      Case P[K] Of
        'u' : Begin
                If SysGetPwUid(Uid, U) Then R := R + U.Name
                Else R := R + IntStr(Uid);
              End;
        'h', 'H' :
              Begin
                SysUname(Un);
                Hn := Un.NodeName;
                If (P[K] = 'h') And (Pos('.', Hn) > 0) Then
                  Hn := Copy(Hn, 1, Pos('.', Hn) - 1);
                R := R + Hn;
              End;
        'w' : R := R + CwdShort;
        'W' : Begin
                Nm := CwdShort;
                While (Pos('/', Nm) > 0) And (Nm <> '/') Do
                  Nm := Copy(Nm, Pos('/', Nm) + 1, 255);
                If Nm = '' Then Nm := '/';
                R := R + Nm;
              End;
        '$' : If Uid = 0 Then R := R + '#' Else R := R + '$';
        'n' : R := R + #10;
        'r' : R := R + #13;
        'e' : R := R + #27;
        'a' : R := R + #7;
        '\' : R := R + '\';
        '[', ']' : ;
        's' : R := R + 'sh';
      Else R := R + '\' + P[K];
      End;
    End
    Else R := R + P[K];
    Inc(K);
  End;
  If Pos('$', R) > 0 Then R := ExpandStr(R);
  PromptText := R;
End;

Procedure SetRaw(On : Boolean);
Var T : TSysTermios;
Begin
  If Not HaveTerm Then Exit;
  If On Then
  Begin
    T := SavedTerm;
    T.LFlag := T.LFlag And Not (TTY_ICANON Or TTY_ECHO Or TTY_IEXTEN);
    T.LFlag := T.LFlag Or TTY_ISIG;
    T.CC[TTY_VMIN] := 1;
    T.CC[TTY_VTIME] := 0;
    SysTcSetAttr(0, 1, T);
  End
  Else SysTcSetAttr(0, 1, SavedTerm);
End;

Procedure HistAdd(Const L : String);
Var I : LongInt;
Begin
  If L = '' Then Exit;
  If (NHist > 0) And (Hist[NHist - 1]^ = L) Then Exit;
  If NHist >= MAXHIST Then
  Begin
    FreeStr(Hist[0]);
    For I := 1 To NHist - 1 Do Hist[I - 1] := Hist[I];
    Dec(NHist);
  End;
  Hist[NHist] := MkStr(L);
  Inc(NHist);
End;

Function GetKey : LongInt;
Var B : Array[0..1] Of Byte; N : LongInt;
Begin
  While True Do
  Begin
    N := LnxSys3(3, 0, LongInt(@B), 1);
    If N = -4 Then
    Begin
      GetKey := -2;
      Exit;
    End;
    If N <= 0 Then
    Begin
      GetKey := -1;
      Exit;
    End;
    GetKey := B[0];
    Exit;
  End;
End;

Procedure Redraw(Const Prompt, Buf : String; Cur : LongInt);
Var S : String; Back : LongInt;
Begin
  S := #13 + Prompt + Buf + #27'[K';
  Back := Length(Buf) - Cur;
  If Back > 0 Then S := S + #27'[' + IntStr(Back) + 'D';
  Out(1, S);
End;

{ completion : candidats dans A ; Pfx : debut du mot }
Procedure CompleteFiles(Const Word : String; Var A : TArgs);
Var Dir, Base, Name, Full : String; K, D, Ino : LongInt; St : TSysStat;
Begin
  K := Length(Word);
  While (K > 0) And (Word[K] <> '/') Do Dec(K);
  Dir := Copy(Word, 1, K);
  Base := Copy(Word, K + 1, 255);
  If Dir = '' Then D := SysOpenDir('.') Else D := SysOpenDir(Dir);
  If D < 0 Then Exit;
  While SysReadDir(D, Name, Ino) Do
  Begin
    If (Name = '.') Or (Name = '..') Then Continue;
    If (Name[1] = '.') And (Base = '') Then Continue;
    If Copy(Name, 1, Length(Base)) <> Base Then Continue;
    Full := Dir + Name;
    If (SysStat(Full, St) = 0) And ((St.Mode And S_IFMT) = S_IFDIR) Then
      Name := Name + '/';
    ArgsAdd(A, Name);
  End;
  SysCloseDir(D);
End;

Procedure CompleteCommands(Const Word : String; Var A : TArgs);
Var P, Dir, Name : String; K, D, Ino, I : LongInt;
Begin
  For I := 1 To NBUILTIN Do
    If Copy(BuiltinNames[I], 1, Length(Word)) = Word Then
      ArgsAdd(A, BuiltinNames[I]);
  For I := 0 To MAXFUNCS - 1 Do
    If Funcs[I].Used And (Copy(Funcs[I].Name, 1, Length(Word)) = Word) Then
      ArgsAdd(A, Funcs[I].Name);
  P := VarValue('PATH') + ':';
  While P <> '' Do
  Begin
    K := Pos(':', P);
    Dir := Copy(P, 1, K - 1);
    Delete(P, 1, K);
    If Dir = '' Then Continue;
    D := SysOpenDir(Dir);
    If D < 0 Then Continue;
    While SysReadDir(D, Name, Ino) Do
    Begin
      If Name[1] = '.' Then Continue;
      If Copy(Name, 1, Length(Word)) = Word Then ArgsAdd(A, Name);
    End;
    SysCloseDir(D);
  End;
End;

Procedure Complete(Const Prompt : String; Var Buf : String; Var Cur : LongInt;
    Var Twice : Boolean);
Var
  S, Start, I, N, K, L, W : LongInt; Word, Cand, Common : String;
  A : TArgs; First : Boolean; Cols, Rows, Col, X : LongInt; Wsz : TSysWinSize;
Begin
  S := Cur;
  While (S > 0) And (Not (Buf[S] In [' ', #9, ';', '|', '&', '(', '<', '>'])) Do
    Dec(S);
  Start := S;                           { le mot est Buf[Start+1..Cur] }
  Word := Copy(Buf, Start + 1, Cur - Start);
  { commande ? }
  First := True;
  For I := 1 To Start Do
    If Not (Buf[I] In [' ', #9, ';', '|', '&', '(']) Then First := False
    Else If Buf[I] In [';', '|', '&', '('] Then First := True;
  ArgsInit(A);
  If First And (Pos('/', Word) = 0) And (Word <> '') Then
    CompleteCommands(Word, A)
  Else CompleteFiles(Word, A);
  ArgsSort(A, 0);
  { retire les doublons }
  N := 0;
  For I := 0 To A.N - 1 Do
    If (N = 0) Or (A.It[N - 1]^ <> A.It[I]^) Then
    Begin
      A.It[N] := A.It[I];
      Inc(N);
    End;
  A.N := N;
  If A.N = 0 Then
  Begin
    Out(1, #7);
    ArgsFree(A);
    Exit;
  End;
  { prefixe commun }
  If Pos('/', Word) > 0 Then
  Begin
    K := Length(Word);
    While (K > 0) And (Word[K] <> '/') Do Dec(K);
    Cand := Copy(Word, 1, K);
  End
  Else Cand := '';
  Common := A.It[0]^;
  For I := 1 To A.N - 1 Do
  Begin
    L := 0;
    While (L < Length(Common)) And (L < Length(A.It[I]^)) And
          (Common[L + 1] = A.It[I]^[L + 1]) Do Inc(L);
    Common := Copy(Common, 1, L);
  End;
  Cand := Cand + Common;
  If (A.N = 1) Then
  Begin
    If Cand[Length(Cand)] <> '/' Then Cand := Cand + ' ';
  End;
  If Length(Cand) > Length(Word) Then
  Begin
    Buf := Copy(Buf, 1, Start) + Cand + Copy(Buf, Cur + 1, 255);
    Cur := Start + Length(Cand);
    Redraw(Prompt, Buf, Cur);
    Twice := False;
  End
  Else If A.N > 1 Then
  Begin
    If Not Twice Then
    Begin
      Twice := True;
      Out(1, #7);
    End
    Else
    Begin
      Twice := False;
      Cols := 80;
      If SysGetWinSize(0, Wsz) = 0 Then
        If Wsz.Col > 0 Then Cols := Wsz.Col;
      W := 0;
      For I := 0 To A.N - 1 Do
        If Length(A.It[I]^) > W Then W := Length(A.It[I]^);
      W := W + 2;
      N := Cols Div W;
      If N < 1 Then N := 1;
      Out(1, #10);
      Col := 0;
      For I := 0 To A.N - 1 Do
      Begin
        Cand := A.It[I]^;
        While Length(Cand) < W Do Cand := Cand + ' ';
        Out(1, Cand);
        Inc(Col);
        If Col >= N Then
        Begin
          Out(1, #10);
          Col := 0;
        End;
      End;
      If Col > 0 Then Out(1, #10);
      Redraw(Prompt, Buf, Cur);
    End;
  End;
  ArgsFree(A);
End;

Function ReadLineEd(Const Prompt : String; Var Line : String) : Boolean;
Var
  Buf, Saved : String; Cur, Key, K2, K3, HI, I, N,
    Num : LongInt; Done : Boolean;
  Twice, Raw : Boolean; C : Char; P2 : String;
Begin
  ReadLineEd := True;
  Out(1, Prompt);
  If Not HaveTerm Then
  Begin
    { entree non interactive : ligne simple }
    Buf := '';
    While True Do
    Begin
      Key := GetKey;
      If Key = -2 Then Continue;
      If Key < 0 Then
      Begin
        If Buf = '' Then ReadLineEd := False;
        Break;
      End;
      If Key = 10 Then Break;
      If Length(Buf) < 255 Then Buf := Buf + Chr(Key);
    End;
    Line := Buf;
    Exit;
  End;
  SetRaw(True);
  Buf := '';
  Cur := 0;
  HI := NHist;
  Saved := '';
  Done := False;
  Twice := False;
  While Not Done Do
  Begin
    Key := GetKey;
    If Key = -2 Then
    Begin
      If IntFlag <> 0 Then
      Begin
        IntFlag := 0;
        Out(1, '^C'#10);
        Buf := '';
        Cur := 0;
        Done := True;
        Break;
      End;
      Continue;
    End;
    If Key = -1 Then
    Begin
      If Buf = '' Then ReadLineEd := False;
      Done := True;
      Break;
    End;
    If Key <> 9 Then Twice := False;
    Case Key Of
      10, 13 :
        Begin
          Out(1, #10);
          Done := True;
        End;
      4 :
        Begin
          If Buf = '' Then
          Begin
            ReadLineEd := False;
            Out(1, #10);
            Done := True;
          End
          Else If Cur < Length(Buf) Then
          Begin
            Delete(Buf, Cur + 1, 1);
            Redraw(Prompt, Buf, Cur);
          End;
        End;
      1 : Begin Cur := 0; Redraw(Prompt, Buf, Cur); End;
      5 : Begin Cur := Length(Buf); Redraw(Prompt, Buf, Cur); End;
      2 : If Cur > 0 Then Begin Dec(Cur); Redraw(Prompt, Buf, Cur); End;
      6 : If Cur < Length(Buf) Then
          Begin
            Inc(Cur);
            Redraw(Prompt, Buf, Cur);
          End;
      11 : Begin Buf := Copy(Buf, 1, Cur); Redraw(Prompt, Buf, Cur); End;
      21 : Begin Buf := Copy(Buf, Cur + 1, 255); Cur := 0;
                  Redraw(Prompt, Buf, Cur); End;
      23 :
        Begin
          N := Cur;
          While (N > 0) And (Buf[N] = ' ') Do Dec(N);
          While (N > 0) And (Buf[N] <> ' ') Do Dec(N);
          Buf := Copy(Buf, 1, N) + Copy(Buf, Cur + 1, 255);
          Cur := N;
          Redraw(Prompt, Buf, Cur);
        End;
      12 :
        Begin
          Out(1, #27'[H'#27'[2J');
          Redraw(Prompt, Buf, Cur);
        End;
      8, 127 :
        If Cur > 0 Then
        Begin
          Delete(Buf, Cur, 1);
          Dec(Cur);
          Redraw(Prompt, Buf, Cur);
        End;
      9 : Complete(Prompt, Buf, Cur, Twice);
      16 :
        If HI > 0 Then
        Begin
          If HI = NHist Then Saved := Buf;
          Dec(HI);
          Buf := Hist[HI]^;
          Cur := Length(Buf);
          Redraw(Prompt, Buf, Cur);
        End;
      14 :
        If HI < NHist Then
        Begin
          Inc(HI);
          If HI = NHist Then Buf := Saved Else Buf := Hist[HI]^;
          Cur := Length(Buf);
          Redraw(Prompt, Buf, Cur);
        End;
      27 :
        Begin
          K2 := GetKey;
          If (K2 = 91) Or (K2 = 79) Then
          Begin
            Num := 0;
            K3 := GetKey;
            While (K3 >= 48) And (K3 <= 57) Do
            Begin
              Num := Num * 10 + K3 - 48;
              K3 := GetKey;
            End;
            Case K3 Of
              65 : If HI > 0 Then
                   Begin
                     If HI = NHist Then Saved := Buf;
                     Dec(HI);
                     Buf := Hist[HI]^;
                     Cur := Length(Buf);
                     Redraw(Prompt, Buf, Cur);
                   End;
              66 : If HI < NHist Then
                   Begin
                     Inc(HI);
                     If HI = NHist Then Buf := Saved Else Buf := Hist[HI]^;
                     Cur := Length(Buf);
                     Redraw(Prompt, Buf, Cur);
                   End;
              67 : If Cur < Length(Buf) Then
                   Begin
                     Inc(Cur);
                     Redraw(Prompt, Buf, Cur);
                   End;
              68 : If Cur > 0 Then
                   Begin
                     Dec(Cur);
                     Redraw(Prompt, Buf, Cur);
                   End;
              72 : Begin Cur := 0; Redraw(Prompt, Buf, Cur); End;
              70 : Begin Cur := Length(Buf); Redraw(Prompt, Buf, Cur); End;
              126 :
                Case Num Of
                  1, 7 : Begin Cur := 0; Redraw(Prompt, Buf, Cur); End;
                  4, 8 : Begin Cur := Length(Buf); Redraw(Prompt, Buf,
                    Cur); End;
                  3 : If Cur < Length(Buf) Then
                      Begin
                        Delete(Buf, Cur + 1, 1);
                        Redraw(Prompt, Buf, Cur);
                      End;
                End;
            End;
          End;
        End;
    Else
      If (Key >= 32) And (Key <> 127) And (Length(Buf) < 250) Then
      Begin
        C := Chr(Key);
        If Cur = Length(Buf) Then
        Begin
          Buf := Buf + C;
          Inc(Cur);
          Out(1, C);
        End
        Else
        Begin
          Insert(C, Buf, Cur + 1);
          Inc(Cur);
          Redraw(Prompt, Buf, Cur);
        End;
      End;
    End;
  End;
  SetRaw(False);
  Line := Buf;
  LastLine := Buf;
  If Buf <> '' Then HistAdd(Buf);
End;

{ ---------- historique, initialisation, programme principal ---------- }

Function HistPath : String;
Var H : String;
Begin
  H := VarValue('HOME');
  If H = '' Then HistPath := '' Else HistPath := H + '/.sh_history';
End;

Procedure HistLoad;
Var P, L : String; Fd : LongInt;
Begin
  P := HistPath;
  If P = '' Then Exit;
  Fd := SysOpen(P, O_RDONLY, 0);
  If Fd < 0 Then Exit;
  While SysReadLine(Fd, L) Do HistAdd(L);
  SysClose(Fd);
End;

Procedure HistSave;
Var P : String; Fd, I : LongInt;
Begin
  P := HistPath;
  If (P = '') Or (NHist = 0) Then Exit;
  Fd := SysOpen(P, O_WRONLY Or O_CREAT Or O_TRUNC, 384);
  If Fd < 0 Then Exit;
  For I := 0 To NHist - 1 Do SysPut(Fd, Hist[I]^ + #10);
  SysClose(Fd);
End;

Procedure ImportEnv;
Var I, K : LongInt; S, N : String;
Begin
  For I := 0 To SysEnvCount - 1 Do
  Begin
    S := SysEnvStr(I);
    K := Pos('=', S);
    If K > 1 Then
    Begin
      N := Copy(S, 1, K - 1);
      If ValidName(N) Then
      Begin
        SetVar(N, Copy(S, K + 1, 255));
        ExportVar(N, True);
      End;
    End;
  End;
End;

Procedure Usage;
Begin
  Err(Msg(mHelpUsage) +
    ': sh [-ceilnsuvx] [-c commande] [fichier [arguments]]');
  SysExit(2);
End;

Var
  AI, K, Fd : LongInt;
  Cmd, Script, A, S : String;
  HaveCmd, DoLogin, StdinMode : Boolean;
  Args : TArgs;
  Tmp : TSysStat;
  Ok : Boolean;

BEGIN
  Lang := SysLang;
  ShellPid := SysGetPid;
  Uid := SysGetUid;
  TmpCnt := ShellPid * 7919 + SysTime;
  JobsInit;
  PosArr := Alloc((MAXPOS + 2) * 4);
  NPos := 0;
  ImportEnv;
  If Not VarSet('PATH') Then
  Begin
    If Uid = 0 Then SetVar('PATH', '/sbin:/bin:/usr/sbin:/usr/bin')
    Else SetVar('PATH', '/bin:/usr/bin');
    ExportVar('PATH', True);
  End;
  If Not VarSet('IFS') Then SetVar('IFS', ' ' + #9 + #10);
  If Not VarSet('HOME') Then
  Begin
    SetVar('HOME', '/');
    ExportVar('HOME', True);
  End;
  SetVar('OPTIND', '1');
  SetPwd;
  Arg0 := SysArgStr(0);
  DoLogin := (Arg0 <> '') And (Arg0[1] = '-');
  A := Arg0;
  While Pos('/', A) > 0 Do A := Copy(A, Pos('/', A) + 1, 255);
  If (A <> '') And (A[1] = '-') Then A := Copy(A, 2, 255);
  BashMode := (A = 'bash');
  StartTime := SysTime;
  If BashMode Then
  Begin
    SetVar('BASH', '/bin/bash');
    SetVar('BASH_VERSION', '5.2.0(1)-release');
    SetVar('OSTYPE', 'linux-gnu');
    SetVar('BASH_VERSINFO[0]', '5');
    SetVar('BASH_VERSINFO[1]', '2');
    SetVar('BASH_VERSINFO[2]', '0');
    SetVar('BASH_VERSINFO[3]', '1');
    SetVar('BASH_VERSINFO[4]', 'release');
    SetVar('BASH_VERSINFO[5]', 'i686-pc-linux-gnu');
    ArrDeclare('BASH_VERSINFO', 1);
    SetVar('SHLVL', '1');
    S := '';
    K := SysOpen('/proc/sys/kernel/hostname', O_RDONLY, 0);
    If K >= 0 Then
    Begin
      SysReadLine(K, S);
      SysClose(K);
    End;
    If S <> '' Then SetVar('HOSTNAME', S);
  End;
  HaveCmd := False;
  Script := '';
  StdinMode := False;
  { options }
  AI := 1;
  While AI < SysArgCount Do
  Begin
    A := SysArgStr(AI);
    If (A = '--') Then
    Begin
      Inc(AI);
      Break;
    End;
    If (Length(A) < 2) Or ((A[1] <> '-') And (A[1] <> '+')) Then Break;
    If A = '-' Then
    Begin
      Inc(AI);
      Break;
    End;
    For K := 2 To Length(A) Do
      Case A[K] Of
        'c' : OptC := A[1] = '-';
        'e' : OptE := A[1] = '-';
        'i' : OptI := A[1] = '-';
        'l' : DoLogin := A[1] = '-';
        'n' : OptN := A[1] = '-';
        's' : OptS := A[1] = '-';
        'u' : OptU := A[1] = '-';
        'v' : OptV := A[1] = '-';
        'x' : OptX := A[1] = '-';
      Else
        Begin
          Err('sh: ' + A + ': ' + Msg(mBadOpt));
          Usage;
        End;
      End;
    Inc(AI);
  End;
  If OptC Then
  Begin
    If AI >= SysArgCount Then Usage;
    Cmd := SysArgStr(AI);
    Inc(AI);
    If AI < SysArgCount Then
    Begin
      Arg0 := SysArgStr(AI);
      Inc(AI);
    End;
    HaveCmd := True;
  End
  Else If (AI < SysArgCount) And (Not OptS) Then
  Begin
    Script := SysArgStr(AI);
    Arg0 := Script;
    Inc(AI);
  End
  Else StdinMode := True;
  { parametres positionnels }
  ArgsInit(Args);
  While AI < SysArgCount Do
  Begin
    ArgsAdd(Args, SysArgStr(AI));
    Inc(AI);
  End;
  PosSet(Args, 0);
  ArgsFree(Args);
  { interactif ? }
  Interactive := OptI;
  If (Not OptC) And StdinMode And SysIsATty(0) And SysIsATty(2) Then
    Interactive := True;
  If OptC Then Interactive := OptI And SysIsATty(0);
  If Interactive Then
  Begin
    TtyFd := -1;
    If SysIsATty(0) Then
    Begin
      TtyFd := 0;
      If SysTcGetAttr(0, SavedTerm) = 0 Then
      Begin
        HaveTerm := True;
        ShellTerm := SavedTerm;
        HaveShellTerm := True;
      End;
      { controle des travaux : le shell est dans son propre groupe, au
        premier plan }
      SysSigAction(SIGTTOU, SIG_IGN, 0);
      SysSigAction(SIGTTIN, SIG_IGN, 0);
      SysSigAction(SIGTSTP, SIG_IGN, 0);
      SysSigAction(SIGQUIT, SIG_IGN, 0);
      SysSigAction(SIGTERM, SIG_IGN, 0);
      If SysGetPgrp <> ShellPid Then SysSetPgid(0, 0);
      ShellPgrp := SysGetPgrp;
      If SysTcSetPgrp(0, ShellPgrp) = 0 Then JobCtl := True;
    End;
    SysSigAction(SIGINT, LongInt(@IntHandler), 0);
    HistLoad;
  End
  Else TtyFd := -1;
  SubDepth := 0;
  { interpreteur de connexion }
  If DoLogin Then
  Begin
    If RunFile('/etc/profile', False) Then ;
    S := VarValue('HOME') + '/.profile';
    If RunFile(S, False) Then ;
  End;
  If Interactive Then
  Begin
    S := VarValue('ENV');
    If S <> '' Then
      If RunFile(S, False) Then ;
  End;
  LastStatus := 0;
  If HaveCmd Then
  Begin
    CurIn.Name := '';
    InOpenStr(CurIn, Cmd);
    RunLoop(True);
    CleanExit(LastStatus);
  End;
  If Script <> '' Then
  Begin
    Fd := SysOpen(Script, O_RDONLY, 0);
    If Fd < 0 Then
    Begin
      Err('sh: ' + Script + ': ' + SysErrorText(SysErrno));
      SysExit(127);
    End;
    { le descripteur du script ne doit pas gener : place haut }
    K := DupHigh(Fd);
    If K >= 0 Then
    Begin
      SysClose(Fd);
      Fd := K;
    End;
    InOpenFd(CurIn, Fd, 4096);
    CurIn.Name := Script;
    RunLoop(True);
    CleanExit(LastStatus);
  End;
  { entree standard }
  If Interactive Then
  Begin
    InOpenFd(CurIn, 0, 16);
    CurIn.Inter := True;
    CurIn.Fd := 0;
    CurIn.Cap := 4096;
  End
  Else
  Begin
    K := 1;
    If SysLSeek(0, 0, 1) >= 0 Then K := 4096;
    InOpenFd(CurIn, 0, K);
  End;
  CurIn.Name := '';
  RunLoop(True);
  CleanExit(LastStatus);
END.
