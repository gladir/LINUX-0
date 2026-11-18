{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2026
  @website(https://www.gladir.com/linux-0)
  @abstract(Target: LPC -3X)
  @description: ed : editeur de lignes POSIX avec les extensions de GNU ed.
   Adresses : n . $ + - %  , ;  /re/ ?re? 'x et decalages. Commandes :
   a i c d e E f g G h H j k l m n p P q Q r s t u v V w W y x z = ! #
   (suffixes p n l ; s avec g p n l et un numero d'occurrence ; & \1..\9 ;
   regex vide = derniere ; annulation u sur un niveau ; marques a-z).
   ed [-s] [-p invite] [fichier] ; "-" comme -s. }

Program Ed;

{$I REGEX.INC}

Const
  MaxMarks = 26;

Var
  { tampon : tableau de pointeurs vers des lignes
    (bloc : [0..3] references, [4..7] longueur, octets) }
  LP : LongInt;                  { adresse du tableau }
  NL, Cap : LongInt;
  Cur : LongInt;
  Marks : Array[0..MaxMarks - 1] Of LongInt;
  { annulation }
  UP : LongInt;
  UN, UCap, UCur : LongInt;
  UChanged, UValid : Boolean;
  Changed, Quiet, ErrAny, Verbose, ShowPrompt, InGlobal : Boolean;
  FileName, PromptS, LastErr, LastCmd : String;
  { dernier motif et dernier remplacement }
  LastRe, LastRepl : String;
  LastReProg : LongInt;
  ReValid : Boolean;
  { presse-papier y / x }
  YP : LongInt;
  YN : LongInt;
  { entree }
  InBuf : Array[0..8191] Of Byte;
  InPos, InCnt : LongInt;
  InEof, Interactive : Boolean;
  { sortie }
  OB : Array[0..8191] Of Byte;
  OLen : LongInt;
  Done_ : Boolean;
  QuitWarn : Boolean;
  SuffixP, SuffixN, SuffixL : Boolean;
  ByteCount : LongInt;
  ScrollN : LongInt;
  CmdStr : String;
  CPos : LongInt;
  Feed : String;
  UseFeed : Boolean;

Procedure Flush;
Begin
  If OLen > 0 Then SysWrite(1, OB[0], OLen);
  OLen := 0;
End;

Procedure OutC(C : Char);
Begin
  If OLen >= 8000 Then Flush;
  OB[OLen] := Ord(C);
  Inc(OLen);
End;

Procedure OutS(Const S : String);
Var K : LongInt;
Begin
  For K := 1 To Length(S) Do OutC(S[K]);
End;

Function NumS(V : LongInt) : String;
Var S : String;
Begin
  Str(V, S);
  NumS := S;
End;

{ ---- lignes ---- }

Function BAlloc(N : LongInt) : LongInt;
Var Pt : Pointer;
Begin
  GetMem(Pt, N + 16);
  If Pt = Nil Then
  Begin
    Flush;
    SysPut(2, 'ed: out of memory' + #10);
    SysExit(2);
  End;
  BAlloc := LongInt(Pt);
End;

Procedure BFree(P : LongInt);
Begin
  If P <> 0 Then FreeMem(Pointer(P), 1);
End;

Function LNew(Src, Len : LongInt) : LongInt;
Var P, K : LongInt;
Begin
  P := BAlloc(Len + 8);
  MemL[0:P] := 1;
  MemL[0:P + 4] := Len;
  For K := 0 To Len - 1 Do Mem[0:P + 8 + K] := Mem[0:Src + K];
  LNew := P;
End;

Procedure LRef(P : LongInt);
Begin
  MemL[0:P] := MemL[0:P] + 1;
End;

Procedure LDrop(P : LongInt);
Begin
  If P = 0 Then Exit;
  MemL[0:P] := MemL[0:P] - 1;
  If MemL[0:P] <= 0 Then BFree(P);
End;

Function LLen(P : LongInt) : LongInt;
Begin
  LLen := MemL[0:P + 4];
End;

Function LAt(I : LongInt) : LongInt;
Begin
  LAt := MemL[0:LP + (I - 1) * 4];
End;

Procedure SetL(I, P : LongInt);
Begin
  MemL[0:LP + (I - 1) * 4] := P;
End;

Procedure Grow(Need : LongInt);
Var N, K, C : LongInt;
Begin
  If Need <= Cap Then Exit;
  C := Cap * 2;
  If C < Need Then C := Need + 1024;
  N := BAlloc(C * 4);
  For K := 0 To NL - 1 Do MemL[0:N + K * 4] := MemL[0:LP + K * 4];
  BFree(LP);
  LP := N;
  Cap := C;
End;

{ ouvre un trou de Cnt lignes apres la ligne At (0 = au debut) }
Procedure OpenGap(At, Cnt : LongInt);
Var K : LongInt;
Begin
  Grow(NL + Cnt + 1);
  For K := NL DownTo At + 1 Do SetL(K + Cnt, LAt(K));
  NL := NL + Cnt;
End;

Procedure ClearMarksFor(P : LongInt);
Var K : LongInt;
Begin
  For K := 0 To MaxMarks - 1 Do
    If Marks[K] = P Then Marks[K] := 0;
End;

{ supprime les lignes A..B }
Procedure DelRange(A, B : LongInt);
Var K, D : LongInt;
Begin
  D := B - A + 1;
  For K := A To B Do
  Begin
    ClearMarksFor(LAt(K));
    LDrop(LAt(K));
  End;
  For K := B + 1 To NL Do SetL(K - D, LAt(K));
  NL := NL - D;
End;

{ ---- annulation ---- }

Procedure UFree;
Var K : LongInt;
Begin
  If UP <> 0 Then
  Begin
    For K := 0 To UN - 1 Do LDrop(MemL[0:UP + K * 4]);
    BFree(UP);
  End;
  UP := 0;
  UN := 0;
  UCap := 0;
End;

{ instantane de l'etat courant (avant modification) }
Procedure Snap;
Var K : LongInt;
Begin
  If InGlobal Then Exit;
  UFree;
  UP := BAlloc((NL + 1) * 4);
  UCap := NL + 1;
  UN := NL;
  For K := 0 To NL - 1 Do
  Begin
    MemL[0:UP + K * 4] := MemL[0:LP + K * 4];
    LRef(MemL[0:LP + K * 4]);
  End;
  UCur := Cur;
  UChanged := Changed;
  UValid := True;
End;

Procedure DoUndo;
Var P, N, C, K, Cu : LongInt; Ch : Boolean;
Begin
  { echange l'etat courant et l'instantane }
  P := UP;
  N := UN;
  C := UCap;
  Cu := UCur;
  Ch := UChanged;
  UP := LP;
  UN := NL;
  UCap := Cap;
  UCur := Cur;
  UChanged := Changed;
  LP := P;
  NL := N;
  Cap := C;
  Cur := Cu;
  Changed := Ch;
  If LP = 0 Then
  Begin
    LP := BAlloc(1024 * 4);
    Cap := 1024;
  End;
  For K := 0 To MaxMarks - 1 Do Marks[K] := 0;
End;

{ ---- erreurs ---- }

Procedure Fail(Const Msg : String);
Begin
  LastErr := Msg;
  ErrAny := True;
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
    Flush;
    InCnt := SysRead(0, InBuf[0], 8191);
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

{ ligne de l'entree standard dans un bloc (adresse, longueur) sans le
  saut de ligne ; Faux a la fin du fichier }
Function ReadInput(Var P, L : LongInt) : Boolean;
Var Cap2, B, K, Q : LongInt;
Begin
  Cap2 := 128;
  P := BAlloc(Cap2);
  L := 0;
  ReadInput := False;
  While True Do
  Begin
    B := ReadByte;
    If B < 0 Then
    Begin
      If L = 0 Then
      Begin
        BFree(P);
        P := 0;
        Exit;
      End;
      Break;
    End;
    If B = 10 Then Break;
    If L >= Cap2 Then
    Begin
      Cap2 := Cap2 * 2;
      Q := BAlloc(Cap2);
      For K := 0 To L - 1 Do Mem[0:Q + K] := Mem[0:P + K];
      BFree(P);
      P := Q;
    End;
    Mem[0:P + L] := B;
    Inc(L);
  End;
  ReadInput := True;
End;

Function ReadCmdLine(Var S : String) : Boolean;
Var P, L, K : LongInt;
Begin
  S := '';
  ReadCmdLine := ReadInput(P, L);
  If P = 0 Then Exit;
  For K := 0 To L - 1 Do
    If Length(S) < 250 Then S := S + Chr(Mem[0:P + K]);
  BFree(P);
End;

{ ---- fichiers ---- }

{ lit le fichier dans le tampon apres la ligne At ; rend le nombre d'octets }
Function ReadFileInto(Const Name : String; At : LongInt) : LongInt;
Var Fd, Got, K, S, N, Cnt, Tot, Q : LongInt; Buf, Acc, AL, AC : LongInt;
    Ptrs, PN, PC : LongInt; Cc : Byte;
Begin
  ReadFileInto := -1;
  Fd := SysOpen(Name, 0, 0);
  If Fd < 0 Then
  Begin
    Fail('Cannot open input file');
    Exit;
  End;
  Buf := BAlloc(65536);
  AC := 256;
  Acc := BAlloc(AC);
  AL := 0;
  PC := 1024;
  Ptrs := BAlloc(PC * 4);
  PN := 0;
  Tot := 0;
  While True Do
  Begin
    Got := LnxSys3(3, Fd, Buf, 65536);
    If Got <= 0 Then Break;
    Tot := Tot + Got;
    For K := 0 To Got - 1 Do
    Begin
      Cc := Mem[0:Buf + K];
      If Cc = 10 Then
      Begin
        If PN >= PC Then
        Begin
          PC := PC * 2;
          Q := BAlloc(PC * 4);
          For N := 0 To PN - 1 Do MemL[0:Q + N * 4] := MemL[0:Ptrs + N * 4];
          BFree(Ptrs);
          Ptrs := Q;
        End;
        MemL[0:Ptrs + PN * 4] := LNew(Acc, AL);
        Inc(PN);
        AL := 0;
      End
      Else
      Begin
        If AL >= AC Then
        Begin
          AC := AC * 2;
          Q := BAlloc(AC);
          For N := 0 To AL - 1 Do Mem[0:Q + N] := Mem[0:Acc + N];
          BFree(Acc);
          Acc := Q;
        End;
        Mem[0:Acc + AL] := Cc;
        Inc(AL);
      End;
    End;
  End;
  SysClose(Fd);
  If AL > 0 Then
  Begin
    If PN >= PC Then
    Begin
      PC := PC + 4;
      Q := BAlloc(PC * 4);
      For N := 0 To PN - 1 Do MemL[0:Q + N * 4] := MemL[0:Ptrs + N * 4];
      BFree(Ptrs);
      Ptrs := Q;
    End;
    MemL[0:Ptrs + PN * 4] := LNew(Acc, AL);
    Inc(PN);
    Tot := Tot + 1;
  End;
  OpenGap(At, PN);
  For K := 0 To PN - 1 Do SetL(At + 1 + K, MemL[0:Ptrs + K * 4]);
  If PN > 0 Then Cur := At + PN;
  BFree(Ptrs);
  BFree(Acc);
  BFree(Buf);
  ReadFileInto := Tot;
End;

Function WriteRange(Const Name : String; A, B : LongInt; Append : Boolean)
  : LongInt;
Var Fd, I, Tot, L, P : LongInt; Fl : LongInt;
Begin
  WriteRange := -1;
  Fl := $241;
  If Append Then Fl := $441;
  Fd := SysOpen(Name, Fl, 420);
  If Fd < 0 Then
  Begin
    Fail('Cannot open output file');
    Exit;
  End;
  Tot := 0;
  For I := A To B Do
  Begin
    P := LAt(I);
    L := LLen(P);
    If L > 0 Then LnxSys3(4, Fd, P + 8, L);
    Tot := Tot + L + 1;
    L := 10;
    LnxSys3(4, Fd, LongInt(@L), 1);
  End;
  SysClose(Fd);
  WriteRange := Tot;
End;

{ ---- regex ---- }

Function CompileRe(Const Pat : String) : Boolean;
Var Pr : LongInt;
Begin
  CompileRe := False;
  If (Pat = '') And (Not ReValid) Then
  Begin
    Fail('No previous pattern');
    Exit;
  End;
  If Pat = '' Then
  Begin
    CompileRe := True;
    Exit;
  End;
  ReN := 0;
  ReSetN := 0;
  Pr := ReCompile(Pat, False, False);
  If Pr < 0 Then
  Begin
    Fail('Invalid pattern delimiter');
    Exit;
  End;
  LastRe := Pat;
  LastReProg := Pr;
  ReValid := True;
  CompileRe := True;
End;

{ le motif de la derniere compilation est dans le programme regex global :
  on recompile si le dernier motif a change (ReProg est partage) }
Function MatchLine(P : LongInt) : Boolean;
Begin
  MatchLine := ReSearch(LastReProg, P + 8, LLen(P), 0, False);
End;

{ ---- analyse de la ligne de commande ---- }

Function Cc : Char;
Begin
  If CPos <= Length(CmdStr) Then Cc := CmdStr[CPos] Else Cc := #0;
End;

Procedure SkipSp;
Begin
  While (Cc = ' ') Or (Cc = #9) Do Inc(CPos);
End;

{ lit un motif delimite par Delim (CPos est apres le delimiteur ouvrant) }
Function ReadPat(Delim : Char) : String;
Var S : String; C : Char; InSet : Boolean;
Begin
  S := '';
  InSet := False;
  While CPos <= Length(CmdStr) Do
  Begin
    C := CmdStr[CPos];
    If (C = Delim) And (Not InSet) Then Break;
    If C = '\' Then
    Begin
      If (CPos < Length(CmdStr)) And (CmdStr[CPos + 1] = Delim) And
         (Delim <> '\') Then
      Begin
        S := S + Delim;
        Inc(CPos, 2);
        Continue;
      End;
      S := S + C;
      Inc(CPos);
      If CPos <= Length(CmdStr) Then
      Begin
        S := S + CmdStr[CPos];
        Inc(CPos);
      End;
      Continue;
    End;
    If C = '[' Then InSet := True
    Else If (C = ']') And InSet Then InSet := False;
    S := S + C;
    Inc(CPos);
  End;
  ReadPat := S;
End;

Function ParseNum : LongInt;
Var V : LongInt;
Begin
  V := 0;
  While (Cc >= '0') And (Cc <= '9') Do
  Begin
    V := V * 10 + Ord(Cc) - 48;
    Inc(CPos);
  End;
  ParseNum := V;
End;

{ cherche le motif en avant (Dir 1) ou en arriere (Dir -1) depuis From }
Function SearchLine(Dir, From : LongInt) : LongInt;
Var K, I : LongInt;
Begin
  SearchLine := -1;
  If NL = 0 Then Exit;
  I := From;
  For K := 1 To NL Do
  Begin
    I := I + Dir;
    If I > NL Then I := 1;
    If I < 1 Then I := NL;
    If MatchLine(LAt(I)) Then
    Begin
      SearchLine := I;
      Exit;
    End;
  End;
End;

{ une adresse ; Has = Vrai si une adresse a ete lue ; -1 en cas d'erreur }
Function ParseAddr(Var Has : Boolean) : LongInt;
Var V, N : LongInt; C, D : Char; Pat : String; Sg : LongInt; Base : LongInt;
Begin
  Has := False;
  SkipSp;
  C := Cc;
  Base := Cur;
  V := Cur;
  If (C >= '0') And (C <= '9') Then
  Begin
    V := ParseNum;
    Has := True;
  End
  Else If C = '.' Then
  Begin
    Inc(CPos);
    V := Cur;
    Has := True;
  End
  Else If C = '$' Then
  Begin
    Inc(CPos);
    V := NL;
    Has := True;
  End
  Else If (C = '/') Or (C = '?') Then
  Begin
    D := C;
    Inc(CPos);
    Pat := ReadPat(D);
    If Cc = D Then Inc(CPos);
    If Not CompileRe(Pat) Then
    Begin
      ParseAddr := -1;
      Exit;
    End;
    If D = '/' Then N := SearchLine(1, Cur) Else N := SearchLine(-1, Cur);
    If N < 0 Then
    Begin
      Fail('No match');
      ParseAddr := -1;
      Exit;
    End;
    V := N;
    Has := True;
  End
  Else If C = '''' Then
  Begin
    Inc(CPos);
    D := Cc;
    Inc(CPos);
    If (D < 'a') Or (D > 'z') Then
    Begin
      Fail('Invalid mark character');
      ParseAddr := -1;
      Exit;
    End;
    N := Marks[Ord(D) - 97];
    V := 0;
    If N <> 0 Then
      For Sg := 1 To NL Do
        If LAt(Sg) = N Then V := Sg;
    If V = 0 Then
    Begin
      Fail('Invalid address');
      ParseAddr := -1;
      Exit;
    End;
    Has := True;
  End;
  { decalages }
  While True Do
  Begin
    SkipSp;
    C := Cc;
    If (C = '+') Or (C = '-') Then
    Begin
      Inc(CPos);
      Sg := 1;
      If C = '-' Then Sg := -1;
      N := 1;
      If (Cc >= '0') And (Cc <= '9') Then N := ParseNum;
      V := V + Sg * N;
      Has := True;
    End
    Else If (C >= '0') And (C <= '9') And Has Then
    Begin
      V := V + ParseNum;
    End
    Else Break;
  End;
  ParseAddr := V;
End;

{ ---- affichage ---- }

Procedure PrintLine(I : LongInt; Num, List : Boolean);
Var P, L, K : LongInt; C : Byte;
Begin
  P := LAt(I);
  L := LLen(P);
  If Num Then OutS(NumS(I) + #9);
  For K := 0 To L - 1 Do
  Begin
    C := Mem[0:P + 8 + K];
    If List Then
    Begin
      If C = 92 Then OutS('\\')
      Else If C = 7 Then OutS('\a')
      Else If C = 8 Then OutS('\b')
      Else If C = 12 Then OutS('\f')
      Else If C = 13 Then OutS('\r')
      Else If C = 9 Then OutS('\t')
      Else If C = 11 Then OutS('\v')
      Else If (C < 32) Or (C >= 127) Then
      Begin
        OutC('\');
        OutC(Chr(48 + (C Shr 6)));
        OutC(Chr(48 + ((C Shr 3) And 7)));
        OutC(Chr(48 + (C And 7)));
      End
      Else OutC(Chr(C));
    End
    Else OutC(Chr(C));
  End;
  If List Then OutC('$');
  OutC(#10);
  Cur := I;
End;

Procedure ApplySuffix;
Begin
  If (Cur >= 1) And (Cur <= NL) Then
  Begin
    If SuffixL Then PrintLine(Cur, False, True)
    Else If SuffixN Then PrintLine(Cur, True, False)
    Else If SuffixP Then PrintLine(Cur, False, False);
  End;
End;

{ lit les suffixes p n l puis exige la fin de ligne }
Function ReadSuffix : Boolean;
Begin
  SuffixP := False;
  SuffixN := False;
  SuffixL := False;
  While True Do
  Begin
    If Cc = 'p' Then SuffixP := True
    Else If Cc = 'n' Then SuffixN := True
    Else If Cc = 'l' Then SuffixL := True
    Else Break;
    Inc(CPos);
  End;
  ReadSuffix := True;
  If Cc <> #0 Then
  Begin
    Fail('Invalid command suffix');
    ReadSuffix := False;
  End;
End;

{ ---- saisie de texte (a, i, c) ---- }

{ ligne de texte : de la liste de commandes d'un g, sinon de l'entree }
Function ReadText(Var P, L : LongInt) : Boolean;
Var K, N : LongInt;
Begin
  If Not UseFeed Then
  Begin
    ReadText := ReadInput(P, L);
    Exit;
  End;
  ReadText := False;
  If Feed = '' Then Exit;
  K := Pos(#10, Feed);
  If K = 0 Then N := Length(Feed) Else N := K - 1;
  P := BAlloc(N + 8);
  For L := 1 To N Do Mem[0:P + L - 1] := Ord(Feed[L]);
  L := N;
  If K = 0 Then Feed := '' Else Feed := Copy(Feed, K + 1, 250);
  ReadText := True;
End;

Procedure InputText(At : LongInt; Var Cnt : LongInt);
Var P, L : LongInt;
Begin
  Cnt := 0;
  While ReadText(P, L) Do
  Begin
    If (L = 1) And (Mem[0:P] = 46) Then
    Begin
      BFree(P);
      Break;
    End;
    OpenGap(At + Cnt, 1);
    SetL(At + Cnt + 1, LNew(P, L));
    BFree(P);
    Inc(Cnt);
  End;
  If Cnt > 0 Then Cur := At + Cnt;
End;

{ ---- substitution ---- }

{ construit la ligne de remplacement ; Mem[Base..] = ligne, groupes dans ReCap }
Function SubstLine(P : LongInt; Const Repl : String; Nth : LongInt;
                   Glob : Boolean; Var Out : LongInt; Var OutL : LongInt)
  : Boolean;
Var L, From, Cnt, S, E, K, G, J : LongInt; Cap2 : LongInt; Q : LongInt;
    Any : Boolean; C : Char; Done : Boolean;
Procedure Put(B : Byte);
Var N, T : LongInt;
Begin
  If OutL >= Cap2 Then
  Begin
    Cap2 := Cap2 * 2;
    N := BAlloc(Cap2);
    For T := 0 To OutL - 1 Do Mem[0:N + T] := Mem[0:Out + T];
    BFree(Out);
    Out := N;
  End;
  Mem[0:Out + OutL] := B;
  Inc(OutL);
End;
Begin
  L := LLen(P);
  Cap2 := L + 256;
  Out := BAlloc(Cap2);
  OutL := 0;
  From := 0;
  Cnt := 0;
  Any := False;
  Done := False;
  While (From <= L) And (Not Done) Do
  Begin
    If Not ReSearch(LastReProg, P + 8, L, From, False) Then Break;
    S := ReCap[0];
    E := ReCap[1];
    Inc(Cnt);
    If Cnt >= Nth Then
    Begin
      { texte avant la correspondance }
      For K := From To S - 1 Do Put(Mem[0:P + 8 + K]);
      { remplacement }
      J := 1;
      While J <= Length(Repl) Do
      Begin
        C := Repl[J];
        If C = '&' Then
        Begin
          For K := S To E - 1 Do Put(Mem[0:P + 8 + K]);
        End
        Else If (C = '\') And (J < Length(Repl)) Then
        Begin
          Inc(J);
          C := Repl[J];
          If (C >= '1') And (C <= '9') Then
          Begin
            G := Ord(C) - 48;
            If ReCap[G * 2] >= 0 Then
              For K := ReCap[G * 2] To ReCap[G * 2 + 1] - 1 Do
                Put(Mem[0:P + 8 + K]);
          End
          Else Put(Ord(C));
        End
        Else Put(Ord(C));
        Inc(J);
      End;
      Any := True;
      If E = S Then
      Begin
        If S < L Then Put(Mem[0:P + 8 + S]);
        From := E + 1;
      End
      Else From := E;
      If Not Glob Then Done := True;
    End
    Else
    Begin
      For K := From To E - 1 Do Put(Mem[0:P + 8 + K]);
      If E = S Then
      Begin
        If S < L Then Put(Mem[0:P + 8 + S]);
        From := E + 1;
      End
      Else From := E;
    End;
  End;
  If Any Then
    For K := From To L - 1 Do Put(Mem[0:P + 8 + K]);
  SubstLine := Any;
End;

Procedure ExecLine(Const Cmd : String); Forward;

{ ---- commande shell ---- }

Procedure RunShell(Const Cmd : String);
Var Pid, St : LongInt;
Begin
  Flush;
  Pid := SysFork;
  If Pid = 0 Then
  Begin
    SysArgReset;
    SysArgAdd('/bin/sh');
    SysArgAdd('-c');
    SysArgAdd(Cmd);
    SysEnvInherit;
    SysArgExec('/bin/sh');
    SysExit(127);
  End;
  SysWaitPid(Pid, St, 0);
End;

{ ---- global ---- }

Procedure DoGlobal(A1, A2 : LongInt; Inverse, Interact : Boolean);
Var Pat, Cmds, Line : String; Mk, K2 : LongInt;
    Ptrs, N, K, I, Hint, Found : LongInt;
    M : Boolean; D : Char; S2 : String; P : LongInt; More : Boolean;
Begin
  D := Cc;
  If (D = #0) Or (D = ' ') Then
  Begin
    Fail('Invalid pattern delimiter');
    Exit;
  End;
  Inc(CPos);
  Pat := ReadPat(D);
  If Cc = D Then Inc(CPos);
  If Not CompileRe(Pat) Then Exit;
  Cmds := '';
  If Not Interact Then
  Begin
    Cmds := Copy(CmdStr, CPos, 250);
    { suite de commandes sur plusieurs lignes (backslash final) }
    While (Length(Cmds) > 0) And (Cmds[Length(Cmds)] = '\') Do
    Begin
      Delete(Cmds, Length(Cmds), 1);
      If Not ReadCmdLine(Line) Then Break;
      Cmds := Cmds + #10 + Line;
    End;
    If Cmds = '' Then Cmds := 'p';
  End;
  { marque les lignes concernees }
  Ptrs := BAlloc((NL + 1) * 4);
  N := 0;
  For I := A1 To A2 Do
  Begin
    M := MatchLine(LAt(I));
    If M <> Inverse Then
    Begin
      MemL[0:Ptrs + N * 4] := LAt(I);
      LRef(LAt(I));
      Inc(N);
    End;
  End;
  If N = 0 Then
  Begin
    BFree(Ptrs);
    Fail('No match');
    Exit;
  End;
  Snap;
  InGlobal := True;
  Hint := 1;
  For K := 0 To N - 1 Do
  Begin
    P := MemL[0:Ptrs + K * 4];
    { retrouver la ligne }
    Found := 0;
    For I := 1 To NL Do
      If LAt(I) = P Then
      Begin
        Found := I;
        Break;
      End;
    If Found = 0 Then Continue;
    Cur := Found;
    If Interact Then
    Begin
      PrintLine(Cur, False, False);
      If Not ReadCmdLine(Line) Then Break;
      If Line = '' Then Continue;
      If Line = '&' Then Line := LastCmd;
      LastCmd := Line;
      ExecLine(Line);
    End
    Else
    Begin
      Feed := Cmds;
      UseFeed := True;
      While (Feed <> '') And (Not Done_) Do
      Begin
        K2 := Pos(#10, Feed);
        If K2 = 0 Then
        Begin
          Line := Feed;
          Feed := '';
        End
        Else
        Begin
          Line := Copy(Feed, 1, K2 - 1);
          Feed := Copy(Feed, K2 + 1, 250);
        End;
        ExecLine(Line);
      End;
      UseFeed := False;
    End;
    If Done_ Then Break;
  End;
  For K := 0 To N - 1 Do LDrop(MemL[0:Ptrs + K * 4]);
  BFree(Ptrs);
  InGlobal := False;
End;

{ ---- execution d'une commande ---- }

{ deplace/copie : copie les pointeurs A..B en tableau neuf }
Function CopyPtrs(A, B : LongInt) : LongInt;
Var P, K : LongInt;
Begin
  P := BAlloc((B - A + 2) * 4);
  For K := A To B Do MemL[0:P + (K - A) * 4] := LAt(K);
  CopyPtrs := P;
End;

Procedure CheckAddr(A : LongInt; Var Ok : Boolean);
Begin
  If (A < 0) Or (A > NL) Then
  Begin
    Fail('Invalid address');
    Ok := False;
  End;
End;

Procedure CmdSubst(A1, A2 : LongInt);
Var D : Char; Pat, Rep, Flags, Ln : String; Glob, SP, SN, SL, Repeat_ : Boolean;
    Nth, I, K, Out, OutL, Cnt, J, Last, S0, Pcs, Q : LongInt; Old, Nw : LongInt;
    NoMatch : Boolean; Line : String;
Begin
  D := Cc;
  Repeat_ := (D = #0) Or (D = 'g') Or (D = 'p') Or (D = 'l') Or
             (D = 'n') Or ((D >= '0') And (D <= '9')) Or (D = ' ');
  If Repeat_ Then
  Begin
    If Not ReValid Then
    Begin
      Fail('No previous substitution');
      Exit;
    End;
    Pat := '';
    Rep := LastRepl;
    If LastRe = '' Then
    Begin
      Fail('No previous substitution');
      Exit;
    End;
  End
  Else
  Begin
    Inc(CPos);
    Pat := ReadPat(D);
    If Cc = D Then Inc(CPos);
    { remplacement : jusqu'au delimiteur ; "\" + saut de ligne = ligne suite }
    Rep := '';
    While True Do
    Begin
      If CPos > Length(CmdStr) Then Break;
      If CmdStr[CPos] = D Then
      Begin
        Inc(CPos);
        Break;
      End;
      If CmdStr[CPos] = '\' Then
      Begin
        If CPos = Length(CmdStr) Then
        Begin
          { backslash final : continuer sur la ligne suivante }
          If UseFeed Then
          Begin
            K := Pos(#10, Feed);
            If K = 0 Then
            Begin
              Ln := Feed;
              Feed := '';
            End
            Else
            Begin
              Ln := Copy(Feed, 1, K - 1);
              Feed := Copy(Feed, K + 1, 250);
            End;
          End
          Else If Not ReadCmdLine(Ln) Then Ln := '';
          Rep := Rep + '\' + #10;
          CmdStr := CmdStr + Ln;
          Inc(CPos);
          Continue;
        End;
        If CmdStr[CPos + 1] = D Then
        Begin
          Rep := Rep + D;
          Inc(CPos, 2);
          Continue;
        End;
        Rep := Rep + '\' + CmdStr[CPos + 1];
        Inc(CPos, 2);
        Continue;
      End;
      Rep := Rep + CmdStr[CPos];
      Inc(CPos);
    End;
    If Rep = '%' Then Rep := LastRepl;
    LastRepl := Rep;
  End;
  Glob := False;
  SP := False;
  SN := False;
  SL := False;
  Nth := 1;
  While True Do
  Begin
    If Cc = 'g' Then Glob := True
    Else If Cc = 'p' Then SP := True
    Else If Cc = 'n' Then SN := True
    Else If Cc = 'l' Then SL := True
    Else If (Cc >= '0') And (Cc <= '9') Then
    Begin
      Nth := ParseNum;
      Dec(CPos);
    End
    Else Break;
    Inc(CPos);
  End;
  If Cc <> #0 Then
  Begin
    Fail('Invalid command suffix');
    Exit;
  End;
  If Not Repeat_ Then
  Begin
    If Not CompileRe(Pat) Then Exit;
  End
  Else
  Begin
    ReN := 0;
    ReSetN := 0;
    LastReProg := ReCompile(LastRe, False, False);
  End;
  { Rep : conversion des sequences "\" + saut de ligne en saut de ligne }
  Cnt := 0;
  Last := 0;
  Snap;
  I := A1;
  While I <= A2 Do
  Begin
    Old := LAt(I);
    If SubstLine(Old, Rep, Nth, Glob, Out, OutL) Then
    Begin
      { remplace la ligne ; coupe aux sauts de ligne inseres }
      S0 := 0;
      Pcs := 0;
      For K := 0 To OutL Do
        If (K = OutL) Or (Mem[0:Out + K] = 10) Then
        Begin
          Nw := LNew(Out + S0, K - S0);
          If Pcs = 0 Then
          Begin
            ClearMarksFor(Old);
            LDrop(Old);
            SetL(I, Nw);
          End
          Else
          Begin
            OpenGap(I + Pcs - 1, 1);
            SetL(I + Pcs, Nw);
            Inc(A2);
          End;
          Inc(Pcs);
          S0 := K + 1;
        End;
      I := I + Pcs - 1;
      Last := I;
      Inc(Cnt);
    End;
    BFree(Out);
    Inc(I);
  End;
  If Cnt = 0 Then
  Begin
    Fail('No match');
    Exit;
  End;
  Changed := True;
  Cur := Last;
  If SL Then PrintLine(Cur, False, True)
  Else If SN Then PrintLine(Cur, True, False)
  Else If SP Then PrintLine(Cur, False, False);
End;

Procedure LoadBuffer(Const Name : String);
Var N, K : LongInt;
Begin
  If NL > 0 Then DelRange(1, NL);
  Cur := 0;
  N := ReadFileInto(Name, 0);
  If N < 0 Then Exit;
  If Not Quiet Then OutS(NumS(N) + #10);
  Changed := False;
End;

Procedure ExecLine(Const Cmd : String);
Var
  A1, A2, NA, I, K, T, Dst, N, P, L, X, Cnt, Tot : LongInt;
  Has, Ok, Sep, DefDone : Boolean;
  C : Char;
  Arg, Tmp : String;
  Pt : LongInt;
  Q, Pt2 : LongInt;
  St : LongInt;
  Dirn : Boolean;
Begin
  CmdStr := Cmd;
  CPos := 1;
  A1 := Cur;
  A2 := Cur;
  NA := 0;
  Ok := True;
  { adresses }
  While True Do
  Begin
    SkipSp;
    If (Cc = '%') And (NA = 0) Then
    Begin
      Inc(CPos);
      A1 := 1;
      A2 := NL;
      NA := 2;
      Break;
    End;
    X := ParseAddr(Has);
    If ErrAny Then Exit;
    SkipSp;
    C := Cc;
    Sep := (C = ',') Or (C = ';');
    If Has Then
    Begin
      A1 := A2;
      A2 := X;
      Inc(NA);
    End
    Else If Sep Then
    Begin
      A1 := A2;
      If C = ',' Then A2 := 1 Else A2 := Cur;
      Inc(NA);
    End;
    If Not Sep Then Break;
    If C = ';' Then
    Begin
      If (A2 < 0) Or (A2 > NL) Then
      Begin
        Fail('Invalid address');
        Exit;
      End;
      Cur := A2;
    End;
    Inc(CPos);
    SkipSp;
    C := Cc;
    If Not (((C >= '0') And (C <= '9')) Or (C = '.') Or (C = '$') Or
            (C = '+') Or (C = '-') Or (C = '/') Or (C = '?') Or
            (C = '''')) Then
    Begin
      A1 := A2;
      A2 := NL;
      Inc(NA);
      Break;
    End;
  End;
  If NA > 2 Then NA := 2;
  If NA = 1 Then A1 := A2;
  SkipSp;
  C := Cc;
  If C <> #0 Then Inc(CPos);
  If (A1 < 0) Or (A2 < 0) Or (A1 > NL) Or (A2 > NL) Or (A1 > A2) Then
  Begin
    If Not ((NA > 0) And (A2 = 0) And ((C = 'a') Or (C = 'r') Or (C = 'i')
       Or (C = 'k') Or (C = #0) Or (C = 'x') Or (C = 't') Or (C = 'm'))) Then
    Begin
      If (NA > 0) Or (C = #0) Then
      Begin
        Fail('Invalid address');
        Exit;
      End;
    End;
  End;
  { commandes }
  Case C Of
    #0 :
      Begin
        If NA = 0 Then
        Begin
          If Cur + 1 > NL Then
          Begin
            Fail('Invalid address');
            Exit;
          End;
          A2 := Cur + 1;
        End;
        If (A2 < 1) Or (A2 > NL) Then
        Begin
          Fail('Invalid address');
          Exit;
        End;
        PrintLine(A2, False, False);
      End;
    'a', 'i' :
      Begin
        If NA = 0 Then A2 := Cur;
        If Not ReadSuffix Then Exit;
        Snap;
        If C = 'a' Then T := A2
        Else
        Begin
          T := A2 - 1;
          If T < 0 Then T := 0;
        End;
        InputText(T, Cnt);
        If Cnt > 0 Then Changed := True;
        ApplySuffix;
      End;
    'c' :
      Begin
        If NA = 0 Then
        Begin
          A1 := Cur;
          A2 := Cur;
        End;
        If (A1 < 1) Or (A2 > NL) Then
        Begin
          Fail('Invalid address');
          Exit;
        End;
        If Not ReadSuffix Then Exit;
        Snap;
        DelRange(A1, A2);
        Cur := A1 - 1;
        InputText(A1 - 1, Cnt);
        Changed := True;
        If Cnt = 0 Then
        Begin
          If A1 <= NL Then Cur := A1 Else Cur := NL;
        End;
        ApplySuffix;
      End;
    'd' :
      Begin
        If NA = 0 Then
        Begin
          A1 := Cur;
          A2 := Cur;
        End;
        If (A1 < 1) Or (A2 > NL) Then
        Begin
          Fail('Invalid address');
          Exit;
        End;
        If Not ReadSuffix Then Exit;
        Snap;
        DelRange(A1, A2);
        Changed := True;
        If A1 <= NL Then Cur := A1 Else Cur := NL;
        ApplySuffix;
      End;
    'e', 'E' :
      Begin
        SkipSp;
        If (C = 'e') And Changed And (Not QuitWarn) Then
        Begin
          QuitWarn := True;
          Fail('Warning: buffer modified');
          Exit;
        End;
        Arg := Copy(CmdStr, CPos, 250);
        If Arg <> '' Then FileName := Arg;
        If FileName = '' Then
        Begin
          Fail('No current filename');
          Exit;
        End;
        Snap;
        LoadBuffer(FileName);
        QuitWarn := False;
      End;
    'f' :
      Begin
        SkipSp;
        Arg := Copy(CmdStr, CPos, 250);
        If Arg <> '' Then FileName := Arg;
        OutS(FileName + #10);
      End;
    'g', 'v' :
      Begin
        If NA = 0 Then
        Begin
          A1 := 1;
          A2 := NL;
        End;
        If (NL = 0) Then
        Begin
          Fail('Invalid address');
          Exit;
        End;
        If InGlobal Then
        Begin
          Fail('Cannot nest global commands');
          Exit;
        End;
        DoGlobal(A1, A2, C = 'v', False);
      End;
    'G', 'V' :
      Begin
        If NA = 0 Then
        Begin
          A1 := 1;
          A2 := NL;
        End;
        If (NL = 0) Or InGlobal Then
        Begin
          Fail('Invalid address');
          Exit;
        End;
        DoGlobal(A1, A2, C = 'V', True);
      End;
    'h' :
      If LastErr <> '' Then OutS(LastErr + #10);
    'H' :
      Begin
        Verbose := Not Verbose;
        If Verbose And (LastErr <> '') Then OutS(LastErr + #10);
      End;
    'j' :
      Begin
        If NA = 0 Then
        Begin
          A1 := Cur;
          A2 := Cur + 1;
        End;
        If (A1 < 1) Or (A2 > NL) Then
        Begin
          Fail('Invalid address');
          Exit;
        End;
        If Not ReadSuffix Then Exit;
        If A1 < A2 Then
        Begin
          Snap;
          T := 0;
          For K := A1 To A2 Do T := T + LLen(LAt(K));
          P := BAlloc(T + 8);
          T := 0;
          For K := A1 To A2 Do
          Begin
            For I := 0 To LLen(LAt(K)) - 1 Do
              Mem[0:P + T + I] := Mem[0:LAt(K) + 8 + I];
            T := T + LLen(LAt(K));
          End;
          Q := LNew(P, T);
          BFree(P);
          DelRange(A1, A2);
          OpenGap(A1 - 1, 1);
          SetL(A1, Q);
          Cur := A1;
          Changed := True;
        End;
        ApplySuffix;
      End;
    'k' :
      Begin
        If NA = 0 Then A2 := Cur;
        If (A2 < 1) Or (A2 > NL) Then
        Begin
          Fail('Invalid address');
          Exit;
        End;
        X := Ord(Cc);
        Inc(CPos);
        If (X < 97) Or (X > 122) Then
        Begin
          Fail('Invalid mark character');
          Exit;
        End;
        Marks[X - 97] := LAt(A2);
        If Not ReadSuffix Then Exit;
        ApplySuffix;
      End;
    'l', 'n', 'p' :
      Begin
        If NA = 0 Then
        Begin
          A1 := Cur;
          A2 := Cur;
        End;
        If (A1 < 1) Or (A2 > NL) Then
        Begin
          Fail('Invalid address');
          Exit;
        End;
        Dec(CPos);
        If Not ReadSuffix Then Exit;
        For K := A1 To A2 Do PrintLine(K, SuffixN, SuffixL);
        Cur := A2;
      End;
    'm', 't' :
      Begin
        If NA = 0 Then
        Begin
          A1 := Cur;
          A2 := Cur;
        End;
        If (A1 < 1) Or (A2 > NL) Then
        Begin
          Fail('Invalid address');
          Exit;
        End;
        SkipSp;
        X := ParseAddr(Has);
        If (Not Has) Then X := Cur;
        If (X < 0) Or (X > NL) Then
        Begin
          Fail('Invalid address');
          Exit;
        End;
        If Not ReadSuffix Then Exit;
        Cnt := A2 - A1 + 1;
        If C = 'm' Then
        Begin
          If (X >= A1) And (X < A2) Then
          Begin
            Fail('Invalid destination');
            Exit;
          End;
          Snap;
          If X <> A2 Then
          Begin
            Pt := CopyPtrs(A1, A2);
            { retire sans liberer }
            For K := A2 + 1 To NL Do SetL(K - Cnt, LAt(K));
            NL := NL - Cnt;
            If X > A2 Then X := X - Cnt;
            OpenGap(X, Cnt);
            For K := 0 To Cnt - 1 Do SetL(X + 1 + K, MemL[0:Pt + K * 4]);
            BFree(Pt);
            Cur := X + Cnt;
          End
          Else Cur := A2;
        End
        Else
        Begin
          Snap;
          Pt := CopyPtrs(A1, A2);
          OpenGap(X, Cnt);
          For K := 0 To Cnt - 1 Do
          Begin
            LRef(MemL[0:Pt + K * 4]);
            SetL(X + 1 + K, MemL[0:Pt + K * 4]);
          End;
          BFree(Pt);
          Cur := X + Cnt;
        End;
        Changed := True;
        ApplySuffix;
      End;
    'P' :
      Begin
        ShowPrompt := Not ShowPrompt;
      End;
    'q', 'Q' :
      Begin
        If (C = 'q') And Changed And (Not QuitWarn) Then
        Begin
          QuitWarn := True;
          Fail('Warning: buffer modified');
          Exit;
        End;
        Done_ := True;
      End;
    'r' :
      Begin
        If NA = 0 Then A2 := NL;
        SkipSp;
        Arg := Copy(CmdStr, CPos, 250);
        If Arg = '' Then Arg := FileName;
        If FileName = '' Then FileName := Arg;
        If Arg = '' Then
        Begin
          Fail('No current filename');
          Exit;
        End;
        Snap;
        If Arg[1] = '!' Then
        Begin
          Tmp := '/tmp/ed.' + NumS(SysGetPid);
          RunShell(Copy(Arg, 2, 250) + ' > ' + Tmp);
          Tot := ReadFileInto(Tmp, A2);
          SysUnlink(Tmp);
        End
        Else Tot := ReadFileInto(Arg, A2);
        If Tot >= 0 Then
        Begin
          If Not Quiet Then OutS(NumS(Tot) + #10);
          Changed := True;
        End;
      End;
    's' :
      Begin
        If NA = 0 Then
        Begin
          A1 := Cur;
          A2 := Cur;
        End;
        If (A1 < 1) Or (A2 > NL) Then
        Begin
          Fail('Invalid address');
          Exit;
        End;
        CmdSubst(A1, A2);
      End;
    'u' :
      Begin
        If Not UValid Then
        Begin
          Fail('Nothing to undo');
          Exit;
        End;
        DoUndo;
      End;
    'w', 'W' :
      Begin
        If NA = 0 Then
        Begin
          A1 := 1;
          A2 := NL;
        End;
        Dirn := False;
        If Cc = 'q' Then
        Begin
          Dirn := True;
          Inc(CPos);
        End;
        SkipSp;
        Arg := Copy(CmdStr, CPos, 250);
        If Arg = '' Then Arg := FileName;
        If FileName = '' Then FileName := Arg;
        If Arg = '' Then
        Begin
          Fail('No current filename');
          Exit;
        End;
        If NL = 0 Then
        Begin
          A1 := 1;
          A2 := 0;
        End;
        Tot := WriteRange(Arg, A1, A2, C = 'W');
        If Tot < 0 Then Exit;
        If Not Quiet Then OutS(NumS(Tot) + #10);
        If (A1 <= 1) And (A2 >= NL) Then Changed := False;
        If Dirn Then Done_ := True;
      End;
    'x' :
      Begin
        If NA = 0 Then A2 := Cur;
        If YN = 0 Then
        Begin
          Fail('Nothing to put');
          Exit;
        End;
        Snap;
        OpenGap(A2, YN);
        For K := 0 To YN - 1 Do
        Begin
          LRef(MemL[0:YP + K * 4]);
          SetL(A2 + 1 + K, MemL[0:YP + K * 4]);
        End;
        Cur := A2 + YN;
        Changed := True;
        If Not ReadSuffix Then Exit;
        ApplySuffix;
      End;
    'y' :
      Begin
        If NA = 0 Then
        Begin
          A1 := Cur;
          A2 := Cur;
        End;
        If (A1 < 1) Or (A2 > NL) Then
        Begin
          Fail('Invalid address');
          Exit;
        End;
        If YP <> 0 Then
        Begin
          For K := 0 To YN - 1 Do LDrop(MemL[0:YP + K * 4]);
          BFree(YP);
        End;
        YP := CopyPtrs(A1, A2);
        YN := A2 - A1 + 1;
        For K := 0 To YN - 1 Do LRef(MemL[0:YP + K * 4]);
      End;
    'z' :
      Begin
        If NA = 0 Then A2 := Cur;
        If (Cc >= '0') And (Cc <= '9') Then ScrollN := ParseNum;
        If ScrollN < 1 Then ScrollN := 22;
        If A2 + 1 > NL Then
        Begin
          Fail('Invalid address');
          Exit;
        End;
        T := A2 + ScrollN;
        If T > NL Then T := NL;
        For K := A2 + 1 To T Do PrintLine(K, False, False);
        Cur := T;
      End;
    '=' :
      Begin
        If NA = 0 Then A2 := NL;
        OutS(NumS(A2) + #10);
      End;
    '!' :
      Begin
        Arg := Copy(CmdStr, CPos, 250);
        RunShell(Arg);
        If Not Quiet Then OutS('!' + #10);
      End;
    '#' : ;
  Else
    Fail('Unknown command');
  End;
End;

Procedure Usage;
Begin
  SysPut(1, 'Usage: ed [-s] [-p string] [file]' + #10);
  SysExit(0);
End;

Var
  I, K, N_ : LongInt;
  A, Line : String;
  Tm : TSysTermios;
  ExitErr, QuitFlagReset : Boolean;
Begin
  ExitErr := False;
  LP := 0;
  NL := 0;
  Cap := 0;
  Cur := 0;
  UP := 0;
  UN := 0;
  UCap := 0;
  UValid := False;
  Changed := False;
  Quiet := False;
  ErrAny := False;
  Verbose := False;
  ShowPrompt := False;
  InGlobal := False;
  UseFeed := False;
  Done_ := False;
  QuitWarn := False;
  FileName := '';
  PromptS := '*';
  LastErr := '';
  LastRe := '';
  LastRepl := '';
  ReValid := False;
  YP := 0;
  YN := 0;
  InPos := 0;
  InCnt := 0;
  InEof := False;
  OLen := 0;
  ScrollN := 22;
  For K := 0 To MaxMarks - 1 Do Marks[K] := 0;
  Grow(1024);
  Interactive := SysTcGetAttr(0, Tm) = 0;
  I := 1;
  While I < SysArgCount Do
  Begin
    A := SysArgStr(I);
    If (A = '-') Or (A = '-s') Or (A = '--quiet') Or (A = '--silent') Then
      Quiet := True
    Else If (A = '-p') And (I + 1 < SysArgCount) Then
    Begin
      Inc(I);
      PromptS := SysArgStr(I);
      ShowPrompt := True;
    End
    Else If Copy(A, 1, 2) = '-p' Then
    Begin
      PromptS := Copy(A, 3, 100);
      ShowPrompt := True;
    End
    Else If (A = '-h') Or (A = '--help') Then Usage
    Else If (A = '-V') Or (A = '--version') Then
    Begin
      SysPut(1, 'GNU Ed 1.17' + #10);
      SysExit(0);
    End
    Else If (A = '-G') Or (A = '--traditional') Then
    Begin
    End
    Else If (A <> '') And (A[1] = '-') Then
    Begin
      SysPut(2, 'ed: invalid option ''' + A + '''' + #10);
      SysExit(1);
    End
    Else
    Begin
      FileName := A;
      N_ := ReadFileInto(A, 0);
      If N_ >= 0 Then
      Begin
        If Not Quiet Then OutS(NumS(N_) + #10);
      End
      Else
      Begin
        OutS(A + ': No such file or directory' + #10);
        Flush;
        LastErr := 'Cannot open input file';
      End;
    End;
    Inc(I);
  End;
  While Not Done_ Do
  Begin
    If ShowPrompt Then OutS(PromptS);
    Flush;
    ErrAny := False;
    If Not ReadCmdLine(Line) Then Break;
    QuitFlagReset := False;
    ExecLine(Line);
    If ErrAny Then
    Begin
      OutS('?' + #10);
      If Verbose Then OutS(LastErr + #10);
      ExitErr := True;
    End
    Else If (Line <> 'q') And (Line <> 'e') Then QuitWarn := False;
    Flush;
  End;
  Flush;
  If ExitErr And (Not Interactive) Then SysExit(1);
  SysExit(0);
End.
