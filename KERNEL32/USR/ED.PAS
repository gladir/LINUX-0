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
    If L > 0 Then SysWrite(Fd, Mem[0:P + 8], L);
    SysWrite(Fd, Mem[0:LongInt(@Tot)], 0);
    Tot := Tot + L + 1;
    L := 10;
    SysWrite(Fd, L, 1);
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

Procedure InputText(At : LongInt; Var Cnt : LongInt);
Var P, L : LongInt;
Begin
  Cnt := 0;
  While ReadInput(P, L) Do
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
Var Pat, Cmds, Line : String; Mk : LongInt; Ptrs, N, K, I, Hint, Found : LongInt;
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
    Else ExecLine(Cmds);
    If Done_ Then Break;
  End;
  For K := 0 To N - 1 Do LDrop(MemL[0:Ptrs + K * 4]);
  BFree(Ptrs);
  InGlobal := False;
End;

{ ---- execution d'une commande ---- }

Procedure ExecLine(Const Cmd : String);
Var
  Sv : String; SvPos : LongInt;
  A1, A2, Cnt, I, K, T, Dst, N, P, L, Nth, Q, X : LongInt;
  Has, Has2, Sep : Boolean;
  C : Char;
  NAddr : LongInt;
  Arg, Pat, Rep : String;
  D : Char;
  Glob, SP, SN, SL, Any : Boolean;
  Out, OutL : LongInt;
  Tot : LongInt;
  Ok : Boolean;
  Lo, Hi : LongInt;
Procedure Need(N : LongInt);
Begin
  If (A1 < N) And (Not LastErrSet) Then
  Begin
  End;
End;
Begin
End;
