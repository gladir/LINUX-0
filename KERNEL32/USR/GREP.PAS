{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2026
  @website(https://www.gladir.com/linux-0)
  @abstract(Target: LPC -3X)
  @description: /bin/grep (egrep, fgrep) : recherche de motifs dans des
      fichiers (BRE, ERE, chaines fixes) : -E -F -G -e -f -i -v -w -x -c -l
      -L -o -q -s -n -b -H -h -r -R -A -B -C -m -a -z --include --exclude.
}

Program GREP;

{$I REGEX.INC}

Const
  UsageW : Array[1..5] Of PChar =
    ('Usage : ', 'Usage: ', 'Aufruf: ', 'Uso: ', 'Uso: ');
  MaxPat = 64;
  LMax = 262143;
  CtxMax = 32;
  CtxLen = 2048;

Var
  Pats : Array[1..MaxPat] Of LongInt;
  NPat : LongInt;
  PatText : Array[1..MaxPat] Of String;
  Ere, Fixed, Icase, Invert, WordM, LineM, CountM, ListM, ListN, OnlyM,
  Quiet, NoMsg, NumM, ByteM, WithName, NoName, Recurse, TextM, ZeroM,
  Deref : Boolean;
  MaxCount, After, Before : LongInt;
  Incl, Excl, ExclDir : Array[1..8] Of String;
  NIncl, NExcl, NExclDir : LongInt;
  Status : LongInt;
  OutBuf : Array[0..32767] Of Char;
  OutN : LongInt;
  InBuf : Array[0..65535] Of Byte;
  InPos, InLen, InFd : LongInt;
  LBuf : Array[0..LMax] Of Char;
  LLen : LongInt;
  LOff, NextOff : LongInt;
  Ctx : Array[0..CtxMax * CtxLen - 1] Of Char;
  CtxN : Array[0..CtxMax - 1] Of LongInt;
  CtxNo : Array[0..CtxMax - 1] Of LongInt;
  CtxOff : Array[0..CtxMax - 1] Of LongInt;
  CtxCnt, CtxHead : LongInt;
  FileName : String;
  Sep : Char;
  Printed : Boolean;

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
Begin
  If OutN > 0 Then SysWrite(1, OutBuf[0], OutN);
  OutN := 0;
End;

Procedure OutC(C : Char);
Begin
  If OutN >= 32768 Then Flush;
  OutBuf[OutN] := C;
  Inc(OutN);
End;

Procedure OutS(Const S : String);
Var K : LongInt;
Begin
  For K := 1 To Length(S) Do OutC(S[K]);
End;

Procedure OutMem(Base, N : LongInt);
Var K : LongInt;
Begin
  For K := 0 To N - 1 Do OutC(Chr(Mem[0:Base + K]));
End;

Procedure Die(Const Msg : String; Code : LongInt);
Begin
  Flush;
  SysPut(2, 'grep: ' + Msg + #10);
  SysExit(Code);
End;

Procedure Usage;
Begin
  Flush;
  SysPut(2, PS(UsageW[SysLang]) +
    'grep [-EFGivwxclLoqsnbHhrRaz] [-e motif] [-f fichier] [-A N] [-B N] ' +
    '[-C N] [-m N] [motif] [fichier...]' + #10);
  SysExit(2);
End;

{ ---------- motifs ---------- }

Function EscapeFixed(Const S : String) : String;
Var K : LongInt; R : String;
Begin
  R := '';
  For K := 1 To Length(S) Do
  Begin
    If Pos(S[K], '\.[]*^$') > 0 Then R := R + '\';
    R := R + S[K];
  End;
  EscapeFixed := R;
End;

Procedure AddPat(Const P : String);
Var Pr : LongInt; Q : String;
Begin
  If NPat >= MaxPat Then Die('trop de motifs', 2);
  If Fixed Then Q := EscapeFixed(P) Else Q := P;
  If Fixed Then Pr := ReCompile(Q, False, Icase)
  Else Pr := ReCompile(Q, Ere, Icase);
  If Pr < 0 Then Die(ReErr, 2);
  Inc(NPat);
  Pats[NPat] := Pr;
  PatText[NPat] := P;
End;

Procedure AddPatLines(Const S : String);
Var K : LongInt; Cur : String;
Begin
  Cur := '';
  For K := 1 To Length(S) Do
    If S[K] = #10 Then
    Begin
      AddPat(Cur);
      Cur := '';
    End
    Else Cur := Cur + S[K];
  AddPat(Cur);
End;

Procedure ReadPatFile(Const Fn : String);
Var Fd : LongInt; L : String;
Begin
  If Fn = '-' Then Fd := 0 Else Fd := SysOpen(Fn, 0, 0);
  If Fd < 0 Then Die(Fn + ': ' + SysErrorText(SysErrno), 2);
  While SysReadLine(Fd, L) Do AddPat(L);
  If Fd > 0 Then SysClose(Fd);
End;

{ ---------- lecture ---------- }

Function NextLine : Boolean;
Var C, N : LongInt;
Begin
  NextLine := False;
  LLen := 0;
  LOff := NextOff;
  While True Do
  Begin
    If InPos >= InLen Then
    Begin
      InLen := SysRead(InFd, InBuf[0], 65536);
      InPos := 0;
      If InLen <= 0 Then
      Begin
        InLen := 0;
        If LLen > 0 Then NextLine := True;
        Exit;
      End;
    End;
    C := InBuf[InPos];
    Inc(InPos);
    Inc(NextOff);
    If C = Ord(Sep) Then
    Begin
      NextLine := True;
      Exit;
    End;
    If LLen < LMax Then
    Begin
      LBuf[LLen] := Chr(C);
      Inc(LLen);
    End;
  End;
End;

{ ---------- recherche dans la ligne ---------- }

Function IsW(P : LongInt) : Boolean;
Begin
  If (P < 0) Or (P >= LLen) Then IsW := False
  Else IsW := ReIsWord(Ord(LBuf[P]));
End;

{ cherche la premiere correspondance a partir de From : MS, ME }
Function FindMatch(From : LongInt; Var MS, ME : LongInt) : Boolean;
Var K, Pos0 : LongInt; Found : Boolean; Base : LongInt;
Begin
  FindMatch := False;
  Base := LongInt(@LBuf[0]);
  MS := -1;
  ME := -1;
  For K := 1 To NPat Do
  Begin
    Pos0 := From;
    While Pos0 <= LLen Do
    Begin
      If Not ReSearch(Pats[K], Base, LLen, Pos0, True) Then Break;
      Found := True;
      If LineM Then
        Found := (ReCap[0] = 0) And (ReCap[1] = LLen)
      Else If WordM Then
        Found := (Not IsW(ReCap[0] - 1)) And (Not IsW(ReCap[1])) And
                 (Not ((ReCap[0] > 0) And ReIsWord(Ord(LBuf[ReCap[0]])) And
                       IsW(ReCap[0] - 1)));
      If Found And (ReCap[1] = ReCap[0]) And (From > 0) And
         (ReCap[0] = From) And OnlyM Then Found := False;
      If Found Then
      Begin
        If (MS < 0) Or (ReCap[0] < MS) Or
           ((ReCap[0] = MS) And (ReCap[1] > ME)) Then
        Begin
          MS := ReCap[0];
          ME := ReCap[1];
        End;
        Break;
      End;
      If LineM Then Break;
      Pos0 := ReCap[0] + 1;
    End;
  End;
  FindMatch := MS >= 0;
End;

{ ---------- sortie ---------- }

Procedure Prefix(Const Nm : String; No, Off : LongInt; Sepc : Char);
Begin
  If WithName Then
  Begin
    OutS(Nm);
    OutC(Sepc);
  End;
  If NumM Then
  Begin
    OutS(NumS(No));
    OutC(Sepc);
  End;
  If ByteM Then
  Begin
    OutS(NumS(Off));
    OutC(Sepc);
  End;
End;

Procedure PutCtx(Slot : LongInt; Const Nm : String);
Begin
  Prefix(Nm, CtxNo[Slot], CtxOff[Slot], '-');
  OutMem(LongInt(@Ctx[Slot * CtxLen]), CtxN[Slot]);
  OutC(Sep);
End;

Procedure SaveCtx(No : LongInt);
Var Slot, N : LongInt;
Begin
  If Before <= 0 Then Exit;
  Slot := (CtxHead + CtxCnt) Mod CtxMax;
  If CtxCnt >= Before Then
  Begin
    CtxHead := (CtxHead + 1) Mod CtxMax;
    Dec(CtxCnt);
    Slot := (CtxHead + CtxCnt) Mod CtxMax;
  End;
  N := LLen;
  If N > CtxLen Then N := CtxLen;
  Move(LBuf[0], Ctx[Slot * CtxLen], N);
  CtxN[Slot] := N;
  CtxNo[Slot] := No;
  CtxOff[Slot] := LOff;
  Inc(CtxCnt);
End;

{ ---------- un fichier ---------- }

Procedure DoFd(Fd : LongInt; Const Nm : String);
Var
  No, Hits, MS, ME, From, Pend, LastPrinted, K, Slot : LongInt;
  Sel, Binary, Stop, Any : Boolean;
  Head : Array[0..511] Of Byte;
Begin
  InFd := Fd;
  InPos := 0;
  InLen := 0;
  NextOff := 0;
  No := 0;
  Hits := 0;
  Pend := 0;
  LastPrinted := 0;
  CtxCnt := 0;
  CtxHead := 0;
  Stop := False;
  Binary := False;
  Any := False;
  If Not TextM Then
  Begin
    InLen := SysRead(Fd, InBuf[0], 65536);
    If InLen < 0 Then InLen := 0;
    InPos := 0;
    For K := 0 To InLen - 1 Do
      If (K < 512) And (InBuf[K] = 0) And (Sep <> #0) Then Binary := True;
  End;
  While (Not Stop) And NextLine Do
  Begin
    Inc(No);
    Sel := FindMatch(0, MS, ME);
    If Invert Then Sel := Not Sel;
    If Sel Then
    Begin
      Inc(Hits);
      Any := True;
      If Quiet Then
      Begin
        Status := 0;
        Flush;
        SysExit(0);
      End;
      If ListM Or ListN Then Stop := True
      Else If CountM Then
      Begin
      End
      Else If Binary Then
      Begin
        Stop := True;
      End
      Else
      Begin
        { contexte avant }
        If (After > 0) Or (Before > 0) Then
        Begin
          If LastPrinted = 0 Then
          Begin
            If Printed Then OutS('--' + #10);
          End
          Else If No - CtxCnt > LastPrinted + 1 Then OutS('--' + #10);
          For K := 0 To CtxCnt - 1 Do
            PutCtx((CtxHead + K) Mod CtxMax, Nm);
          CtxCnt := 0;
          CtxHead := 0;
        End;
        If OnlyM And (Not Invert) Then
        Begin
          From := 0;
          While (From <= LLen) And FindMatch(From, MS, ME) Do
          Begin
            If ME > MS Then
            Begin
              Prefix(Nm, No, LOff + MS, ':');
              OutMem(LongInt(@LBuf[0]) + MS, ME - MS);
              OutC(Sep);
            End;
            If ME > MS Then From := ME Else From := ME + 1;
          End;
        End
        Else If Not OnlyM Then
        Begin
          Prefix(Nm, No, LOff, ':');
          OutMem(LongInt(@LBuf[0]), LLen);
          OutC(Sep);
        End;
        LastPrinted := No;
        Printed := True;
        Pend := After;
      End;
      If (MaxCount >= 0) And (Hits >= MaxCount) Then Stop := True;
    End
    Else
    Begin
      If (Pend > 0) And (Not CountM) And (Not ListM) And (Not ListN) And
         (Not Quiet) And (Not Binary) Then
      Begin
        Prefix(Nm, No, LOff, '-');
        OutMem(LongInt(@LBuf[0]), LLen);
        OutC(Sep);
        LastPrinted := No;
        Dec(Pend);
      End
      Else SaveCtx(No);
    End;
    { apres le dernier succes : continuer le contexte apres }
    If Stop And (Pend > 0) And (Not CountM) And (Not ListM) And
       (Not ListN) And (Not Binary) And (MaxCount >= 0) Then
      While (Pend > 0) And NextLine Do
      Begin
        Inc(No);
        Prefix(Nm, No, LOff, '-');
        OutMem(LongInt(@LBuf[0]), LLen);
        OutC(Sep);
        Dec(Pend);
      End;
  End;
  If Any Then Status := 0;
  If CountM And (Not ListM) And (Not ListN) Then
  Begin
    If WithName Then
    Begin
      OutS(Nm);
      OutC(':');
    End;
    OutS(NumS(Hits) + #10);
  End;
  If ListM And Any Then OutS(Nm + #10);
  If ListN And (Not Any) Then
  Begin
    OutS(Nm + #10);
  End;
  If Binary And Any And (Not CountM) And (Not ListM) And (Not ListN) Then
    OutS('Binary file ' + Nm + ' matches' + #10);
End;

Function GlobMatch(Const G, S : String; Gi, Si : LongInt) : Boolean;
Begin
  While Gi <= Length(G) Do
  Begin
    If G[Gi] = '*' Then
    Begin
      While Si <= Length(S) + 1 Do
      Begin
        If GlobMatch(G, S, Gi + 1, Si) Then
        Begin
          GlobMatch := True;
          Exit;
        End;
        Inc(Si);
      End;
      GlobMatch := False;
      Exit;
    End;
    If Si > Length(S) Then
    Begin
      GlobMatch := False;
      Exit;
    End;
    If (G[Gi] <> '?') And (G[Gi] <> S[Si]) Then
    Begin
      GlobMatch := False;
      Exit;
    End;
    Inc(Gi);
    Inc(Si);
  End;
  GlobMatch := Si > Length(S);
End;

Function BaseOf(Const P : String) : String;
Var K : LongInt;
Begin
  K := Length(P);
  While (K > 0) And (P[K] <> '/') Do Dec(K);
  BaseOf := Copy(P, K + 1, 255);
End;

Function Wanted(Const P : String; IsCmdLine : Boolean) : Boolean;
Var K : LongInt; B : String;
Begin
  Wanted := True;
  B := BaseOf(P);
  For K := 1 To NExcl Do
    If GlobMatch(Excl[K], B, 1, 1) Then Wanted := False;
  If NIncl > 0 Then
  Begin
    Wanted := False;
    For K := 1 To NIncl Do
      If GlobMatch(Incl[K], B, 1, 1) Then Wanted := True;
  End;
End;

Procedure DoPath(Const P : String; Top : Boolean);
Var St : TSysStat; Fd, D, Ino, K : LongInt; Nm, Full : String;
    Names : Array[1..256] Of String;
    N : LongInt;
Begin
  If P = '-' Then
  Begin
    If WithName Then DoFd(0, '(standard input)')
    Else DoFd(0, '(standard input)');
    Exit;
  End;
  If SysStat(P, St) <> 0 Then
  Begin
    If Not NoMsg Then
    Begin
      Flush;
      SysPut(2, 'grep: ' + P + ': ' + SysErrorText(SysErrno) + #10);
    End;
    Status := 2;
    Exit;
  End;
  If (St.Mode And $F000) = $4000 Then
  Begin
    If Not Recurse Then
    Begin
      If Not NoMsg Then
      Begin
        Flush;
        SysPut(2, 'grep: ' + P + ': Is a directory' + #10);
      End;
      Exit;
    End;
    For K := 1 To NExclDir Do
      If (Not Top) And GlobMatch(ExclDir[K], BaseOf(P), 1, 1) Then Exit;
    D := SysOpenDir(P);
    If D < 0 Then
    Begin
      Status := 2;
      Exit;
    End;
    N := 0;
    While SysReadDir(D, Nm, Ino) Do
      If (Nm <> '.') And (Nm <> '..') And (N < 256) Then
      Begin
        Inc(N);
        Names[N] := Nm;
      End;
    SysCloseDir(D);
    { tri simple (insertion) }
    For K := 2 To N Do
    Begin
      Nm := Names[K];
      D := K - 1;
      While (D >= 1) And (Names[D] > Nm) Do
      Begin
        Names[D + 1] := Names[D];
        Dec(D);
      End;
      Names[D + 1] := Nm;
    End;
    For K := 1 To N Do
    Begin
      If P[Length(P)] = '/' Then Full := P + Names[K]
      Else Full := P + '/' + Names[K];
      DoPath(Full, False);
    End;
    Exit;
  End;
  If (Not Top) Or (NIncl > 0) Or (NExcl > 0) Then
    If Not Wanted(P, Top) Then Exit;
  Fd := SysOpen(P, 0, 0);
  If Fd < 0 Then
  Begin
    If Not NoMsg Then
    Begin
      Flush;
      SysPut(2, 'grep: ' + P + ': ' + SysErrorText(SysErrno) + #10);
    End;
    Status := 2;
    Exit;
  End;
  DoFd(Fd, P);
  SysClose(Fd);
End;

{ ---------- ligne de commande ---------- }

Var
  I, NArg, J, V : LongInt;
  A, Val1, Prog : String;
  Files : Array[1..64] Of String;
  NFiles : LongInt;
  HavePat, EndOpt : Boolean;

Function NumArg(Const S : String) : LongInt;
Var N, K : LongInt;
Begin
  N := 0;
  For K := 1 To Length(S) Do
    If (S[K] >= '0') And (S[K] <= '9') Then N := N * 10 + Ord(S[K]) - 48
    Else Usage;
  NumArg := N;
End;

Function BaseName(Const P : String) : String;
Begin
  BaseName := BaseOf(P);
End;

Begin
  Sep := #10;
  MaxCount := -1;
  Status := 1;
  NPat := 0;
  NFiles := 0;
  HavePat := False;
  EndOpt := False;
  ReN := 0;
  ReSetN := 0;
  Prog := BaseName(SysArgStr(0));
  Ere := Prog = 'egrep';
  Fixed := Prog = 'fgrep';
  NArg := SysArgCount;
  I := 1;
  { options : on les lit toutes d'abord (i, E, F influencent la compilation) }
  Val1 := '';
  While I < NArg Do
  Begin
    A := SysArgStr(I);
    If (Not EndOpt) And (Length(A) > 1) And (A[1] = '-') Then
    Begin
      If A = '--' Then EndOpt := True
      Else If A = '--ignore-case' Then Icase := True
      Else If A = '--invert-match' Then Invert := True
      Else If A = '--word-regexp' Then WordM := True
      Else If A = '--line-regexp' Then LineM := True
      Else If A = '--count' Then CountM := True
      Else If A = '--files-with-matches' Then ListM := True
      Else If A = '--files-without-match' Then ListN := True
      Else If A = '--only-matching' Then OnlyM := True
      Else If (A = '--quiet') Or (A = '--silent') Then Quiet := True
      Else If A = '--no-messages' Then NoMsg := True
      Else If A = '--line-number' Then NumM := True
      Else If A = '--byte-offset' Then ByteM := True
      Else If A = '--with-filename' Then WithName := True
      Else If A = '--no-filename' Then NoName := True
      Else If (A = '--recursive') Or (A = '--dereference-recursive') Then
        Recurse := True
      Else If A = '--text' Then TextM := True
      Else If A = '--null-data' Then Sep := #0
      Else If A = '--extended-regexp' Then Ere := True
      Else If A = '--fixed-strings' Then Fixed := True
      Else If A = '--basic-regexp' Then Ere := False
      Else If (Copy(A, 1, 7) = '--color') Or (A = '--line-buffered') Or
              (A = '--binary') Or (A = '--no-ignore-case') Then
      Else If Copy(A, 1, 9) = '--regexp=' Then
      Begin
        PatText[1] := Copy(A, 10, 255);
        Files[1] := '';
        { motif differe : compile apres lecture des options }
        Inc(NFiles);
        Files[NFiles] := 'e' + Copy(A, 10, 255);
      End
      Else If Copy(A, 1, 7) = '--file=' Then
      Begin
        Inc(NFiles);
        Files[NFiles] := 'f' + Copy(A, 8, 255);
      End
      Else If Copy(A, 1, 12) = '--max-count=' Then
        MaxCount := NumArg(Copy(A, 13, 20))
      Else If Copy(A, 1, 16) = '--after-context=' Then
        After := NumArg(Copy(A, 17, 20))
      Else If Copy(A, 1, 17) = '--before-context=' Then
        Before := NumArg(Copy(A, 18, 20))
      Else If Copy(A, 1, 10) = '--context=' Then
      Begin
        After := NumArg(Copy(A, 11, 20));
        Before := After;
      End
      Else If Copy(A, 1, 10) = '--include=' Then
      Begin
        If NIncl < 8 Then Inc(NIncl);
        Incl[NIncl] := Copy(A, 11, 255);
      End
      Else If Copy(A, 1, 10) = '--exclude=' Then
      Begin
        If NExcl < 8 Then Inc(NExcl);
        Excl[NExcl] := Copy(A, 11, 255);
      End
      Else If Copy(A, 1, 14) = '--exclude-dir=' Then
      Begin
        If NExclDir < 8 Then Inc(NExclDir);
        ExclDir[NExclDir] := Copy(A, 15, 255);
      End
      Else If A = '--help' Then Usage
      Else If A[2] = '-' Then Usage
      Else
      Begin
        J := 2;
        While J <= Length(A) Do
        Begin
          Case A[J] Of
            'E' : Ere := True;
            'F' : Fixed := True;
            'G' : Ere := False;
            'P' : Ere := True;
            'i', 'y' : Icase := True;
            'v' : Invert := True;
            'w' : WordM := True;
            'x' : LineM := True;
            'c' : CountM := True;
            'l' : ListM := True;
            'L' : ListN := True;
            'o' : OnlyM := True;
            'q' : Quiet := True;
            's' : NoMsg := True;
            'n' : NumM := True;
            'b' : ByteM := True;
            'H' : WithName := True;
            'h' : NoName := True;
            'r', 'R' : Recurse := True;
            'a' : TextM := True;
            'z' : Sep := #0;
            'I', 'U' : ;
            'e', 'f', 'm', 'A', 'B', 'C', 'd' :
              Begin
                If J < Length(A) Then Val1 := Copy(A, J + 1, 255)
                Else
                Begin
                  Inc(I);
                  If I >= NArg Then Usage;
                  Val1 := SysArgStr(I);
                End;
                Case A[J] Of
                  'e' : Begin
                          Inc(NFiles);
                          Files[NFiles] := 'e' + Val1;
                        End;
                  'f' : Begin
                          Inc(NFiles);
                          Files[NFiles] := 'f' + Val1;
                        End;
                  'm' : MaxCount := NumArg(Val1);
                  'A' : After := NumArg(Val1);
                  'B' : Before := NumArg(Val1);
                  'C' : Begin
                          After := NumArg(Val1);
                          Before := After;
                        End;
                  'd' : If Val1 = 'recurse' Then Recurse := True;
                End;
                J := Length(A);
              End;
            '0'..'9' :
              Begin
                V := 0;
                While (J <= Length(A)) And (A[J] >= '0') And
                      (A[J] <= '9') Do
                Begin
                  V := V * 10 + Ord(A[J]) - 48;
                  Inc(J);
                End;
                Dec(J);
                After := V;
                Before := V;
              End;
          Else
            Usage;
          End;
          Inc(J);
        End;
      End;
    End
    Else
    Begin
      Inc(NFiles);
      Files[NFiles] := 'F' + A;
    End;
    Inc(I);
  End;
  { motifs : -e et -f, sinon premier argument }
  For I := 1 To NFiles Do
    If Files[I][1] = 'e' Then
    Begin
      HavePat := True;
      AddPatLines(Copy(Files[I], 2, 255));
    End
    Else If Files[I][1] = 'f' Then
    Begin
      HavePat := True;
      ReadPatFile(Copy(Files[I], 2, 255));
    End;
  { fichiers a lire (ceux qui ne sont pas des options -e/-f) }
  J := 0;
  For I := 1 To NFiles Do
    If Files[I][1] = 'F' Then
    Begin
      If (Not HavePat) And (J = 0) Then
      Begin
        HavePat := True;
        AddPatLines(Copy(Files[I], 2, 255));
        J := -1;
      End
      Else
      Begin
        If J = -1 Then J := 0;
        Inc(J);
        PatText[J] := Copy(Files[I], 2, 255);
      End;
    End;
  If Not HavePat Then Usage;
  { liste finale de fichiers dans PatText[1..J] }
  If J < 0 Then J := 0;
  If (J > 1) Or Recurse Then WithName := True;
  If NoName Then WithName := False;
  If (J = 0) And (Not Recurse) Then DoPath('-', True)
  Else If J = 0 Then
  Begin
    WithName := True;
    DoPath('.', True);
  End
  Else
    For I := 1 To J Do DoPath(PatText[I], True);
  Flush;
  SysExit(Status);
End.
