{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2026
  @website(https://www.gladir.com/linux-0)
  @abstract(Target: LPC -3X)
  @description: /bin/man (aussi apropos, whatis, info) : lecteur de pages de
      manuel. Cherche NOM.SECTION dans /usr/share/man/<LANGUE>/manN puis
      /usr/share/man/manN (MANPATH admis), formate le source roff (macros
      man : .TH .SH .SS .B .I .BR .RB .IR .BI .P .PP .TP .IP .RS .RE .nf .fi
      .br .sp, polices \fB \fI \fR) sur 78 colonnes et affiche par le
      pagineur ($PAGER ou less) quand la sortie est un terminal.
      man -k mot (apropos), man -f nom (whatis), man -w nom (chemin).
      info NOM : /usr/share/info/NOM[.info] (texte) ou, a defaut, la page man.
}

Program MAN;

Const
  Usage : Array[1..5] Of PChar = (
    'Usage : man [-k mot | -f nom | -w] [section] page',
    'Usage: man [-k word | -f name | -w] [section] page',
    'Aufruf: man [-k Wort | -f Name | -w] [Abschnitt] Seite',
    'Uso: man [-k palabra | -f nombre | -w] [seccion] pagina',
    'Uso: man [-k parola | -f nome | -w] [sezione] pagina');
  NoPage : Array[1..5] Of PChar = (
    'Pas d''entree de manuel pour ', 'No manual entry for ',
    'Keine Handbuchseite fuer ', 'No hay entrada de manual para ',
    'Nessuna voce di manuale per ');
  Secs = '1234567891';
  Width = 78;

Var
  Lang : LongInt;
  Color, ToTty : Boolean;
  { sortie formatee : lignes accumulees dans un tube vers le pagineur }
  OutFd : LongInt;
  OutS : String;
  { etat du formateur }
  Fill : Boolean;
  Indent, TpIndent, RsLevel : LongInt;
  Cur : String;            { ligne en cours (avec marqueurs de police) }
  CurVis : LongInt;
  Tp : LongInt;            { 1 : la prochaine ligne est une etiquette }
  TpTag : String;
  HaveTag : Boolean;
  Title, Section, Dat : String;
  LangDir : String;

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

Procedure OFlush;
Begin
  If (Length(OutS) > 0) And (OutFd >= 0) Then SysPut(OutFd, OutS);
  OutS := '';
End;

Procedure Emit(Const S : String);
Var K : LongInt; C : Char;
Begin
  If Length(OutS) > 200 Then OFlush;
  For K := 1 To Length(S) Do
  Begin
    C := S[K];
    If C = #1 Then
    Begin
      If Color Then OutS := OutS + #27 + '[1m';
    End
    Else If C = #2 Then
    Begin
      If Color Then OutS := OutS + #27 + '[0m';
    End
    Else If C = #3 Then
    Begin
      If Color Then OutS := OutS + #27 + '[4m';
    End
    Else OutS := OutS + C;
  End;
  OutS := OutS + #10;
End;

Function Spaces(N : LongInt) : String;
Var S : String;
Begin
  S := '';
  While Length(S) < N Do S := S + ' ';
  Spaces := S;
End;

Function VisLen(Const S : String) : LongInt;
Var K, N : LongInt;
Begin
  N := 0;
  For K := 1 To Length(S) Do
    If Not (S[K] In [#1, #2, #3]) Then Inc(N);
  VisLen := N;
End;

{ ecrit la ligne en cours }
Procedure Flush;
Begin
  If Cur <> '' Then
  Begin
    Emit(Spaces(Indent) + Cur);
    If Tp = 3 Then
    Begin
      Indent := TpIndent;
      Tp := 4;
    End;
  End;
  Cur := '';
  CurVis := 0;
End;

Procedure Blank;
Begin
  Flush;
  Emit('');
End;

Procedure AddWord(Const W : String);
Var V : LongInt;
Begin
  V := VisLen(W);
  If (CurVis > 0) And (Indent + CurVis + 1 + V > Width) Then Flush;
  If CurVis > 0 Then
  Begin
    Cur := Cur + ' ';
    Inc(CurVis);
  End;
  Cur := Cur + W;
  CurVis := CurVis + V;
End;

{ traduit les echappements roff d'une ligne ; polices -> marqueurs }
Function Esc(Const S : String) : String;
Var K : LongInt; R : String; C : Char;
Begin
  R := '';
  K := 1;
  While K <= Length(S) Do
  Begin
    C := S[K];
    If (C = '\') And (K < Length(S)) Then
    Begin
      Inc(K);
      Case S[K] Of
        'f' :
          Begin
            If K < Length(S) Then
            Begin
              Inc(K);
              Case S[K] Of
                'B' : R := R + #1;
                'I' : R := R + #3;
                'R', 'P' : R := R + #2;
              End;
            End;
          End;
        '-' : R := R + '-';
        'e' : R := R + '\';
        '&' : ;
        ' ' : R := R + ' ';
        '(' :
          Begin
            If Copy(S, K + 1, 2) = 'em' Then R := R + '--'
            Else If Copy(S, K + 1, 2) = 'en' Then R := R + '-'
            Else If Copy(S, K + 1, 2) = 'co' Then R := R + '(c)'
            Else If Copy(S, K + 1, 2) = 'aq' Then R := R + ''''
            Else If Copy(S, K + 1, 2) = 'lq' Then R := R + '"'
            Else If Copy(S, K + 1, 2) = 'rq' Then R := R + '"'
            Else R := R + '?';
            K := K + 2;
          End;
        '*' : K := K + 1;
      Else R := R + S[K];
      End;
    End
    Else R := R + C;
    Inc(K);
  End;
  Esc := R;
End;

{ separe les arguments d'une macro (guillemets admis) }
Function Args(Const S : String; Var A : Array Of String) : LongInt;
Var K, N : LongInt; Q : Boolean; T : String;
Begin
  N := 0;
  K := 1;
  While K <= Length(S) Do
  Begin
    While (K <= Length(S)) And (S[K] = ' ') Do Inc(K);
    If K > Length(S) Then Break;
    T := '';
    Q := S[K] = '"';
    If Q Then Inc(K);
    While (K <= Length(S)) And ((Q And (S[K] <> '"')) Or
                                ((Not Q) And (S[K] <> ' '))) Do
    Begin
      T := T + S[K];
      Inc(K);
    End;
    If Q And (K <= Length(S)) Then Inc(K);
    If N <= High(A) Then
    Begin
      A[N] := T;
      Inc(N);
    End;
  End;
  Args := N;
End;

Function IsNumber(Const S : String) : Boolean;
Var K : LongInt;
Begin
  IsNumber := Length(S) > 0;
  For K := 1 To Length(S) Do
    If (S[K] < '0') Or (S[K] > '9') Then IsNumber := False;
End;

Function ToNum(Const S : String) : LongInt;
Var V, C : LongInt;
Begin
  Val(S, V, C);
  If C <> 0 Then V := 0;
  ToNum := V;
End;

Procedure Words(Const S : String);
Var K : LongInt; W : String;
Begin
  W := '';
  For K := 1 To Length(S) Do
    If S[K] = ' ' Then
    Begin
      If W <> '' Then AddWord(W);
      W := '';
    End
    Else W := W + S[K];
  If W <> '' Then AddWord(W);
End;

{ ligne de texte (hors macro) }
Procedure TextLine(Const Raw : String);
Var S, Pad : String;
Begin
  S := Esc(Raw);
  If Not Fill Then
  Begin
    Flush;
    Emit(Spaces(Indent) + S);
    Exit;
  End;
  If S = '' Then
  Begin
    Blank;
    Exit;
  End;
  If Tp = 1 Then
  Begin
    { etiquette de .TP/.IP }
    Flush;
    Tp := 2;
    If Length(S) < 200 Then TpTag := S;
    HaveTag := True;
    If VisLen(TpTag) + 1 <= TpIndent - Indent - 1 Then
    Begin
      Pad := Spaces(TpIndent - Indent - VisLen(TpTag));
      Cur := TpTag + Pad;
      CurVis := TpIndent - Indent;
      Tp := 3;
    End
    Else
    Begin
      Emit(Spaces(Indent) + TpTag);
      Cur := '';
      CurVis := 0;
      Indent := TpIndent;
      Tp := 4;
    End;
    Exit;
  End;
  If Tp = 3 Then
  Begin
    { le texte suit l'etiquette sur la meme ligne }
    Words(S);
    Exit;
  End;
  Words(S);
End;

Procedure Macro(Const Ln : String);
Var
  A : Array[0..9] Of String;
  N, K, Sp : LongInt;
  M, S, Rest : String;
Begin
  Sp := Pos(' ', Ln);
  If Sp = 0 Then
  Begin
    M := Copy(Ln, 2, 255);
    Rest := '';
  End
  Else
  Begin
    M := Copy(Ln, 2, Sp - 2);
    Rest := Copy(Ln, Sp + 1, 255);
  End;
  N := Args(Rest, A);
  For K := 0 To N - 1 Do A[K] := Esc(A[K]);
  If (M = 'TH') Then
  Begin
    If N > 0 Then Title := A[0];
    If N > 1 Then Section := A[1];
    If N > 2 Then Dat := A[2];
    Emit(Title + '(' + Section + ')' + Spaces(Width - 2 * (Length(Title) +
         Length(Section) + 2)) + Title + '(' + Section + ')');
    Emit('');
  End
  Else If M = 'SH' Then
  Begin
    Flush;
    Tp := 0;
    Indent := 0;
    TpIndent := 14;
    RsLevel := 0;
    Emit('');
    S := '';
    For K := 0 To N - 1 Do S := S + A[K] + ' ';
    If S <> '' Then Delete(S, Length(S), 1);
    Emit(#1 + S + #2);
    Indent := 7;
    Fill := True;
  End
  Else If M = 'SS' Then
  Begin
    Flush;
    Tp := 0;
    Indent := 3;
    TpIndent := 14;
    S := '';
    For K := 0 To N - 1 Do S := S + A[K] + ' ';
    If S <> '' Then Delete(S, Length(S), 1);
    Emit('');
    Emit(Spaces(3) + #1 + S + #2);
    Indent := 7;
  End
  Else If (M = 'P') Or (M = 'PP') Or (M = 'LP') Then
  Begin
    Flush;
    Tp := 0;
    Indent := 7 + RsLevel * 7;
    Emit('');
  End
  Else If M = 'TP' Then
  Begin
    Flush;
    Emit('');
    Indent := 7 + RsLevel * 7;
    TpIndent := Indent + 7;
    If N > 0 Then
      If IsNumber(A[0]) Then TpIndent := Indent + ToNum(A[0]);
    Tp := 1;
  End
  Else If M = 'IP' Then
  Begin
    Flush;
    Emit('');
    Indent := 7 + RsLevel * 7;
    TpIndent := Indent + 7;
    If N > 1 Then
      If IsNumber(A[1]) Then TpIndent := Indent + ToNum(A[1]);
    If N > 0 Then
    Begin
      TpTag := A[0];
      Tp := 1;
      TextLine(A[0]);
    End
    Else
    Begin
      Cur := '';
      Indent := TpIndent;
      Tp := 4;
    End;
  End
  Else If M = 'RS' Then
  Begin
    Flush;
    Inc(RsLevel);
    Indent := 7 + RsLevel * 7;
  End
  Else If M = 'RE' Then
  Begin
    Flush;
    If RsLevel > 0 Then Dec(RsLevel);
    Indent := 7 + RsLevel * 7;
  End
  Else If M = 'nf' Then
  Begin
    Flush;
    Fill := False;
  End
  Else If M = 'fi' Then Fill := True
  Else If M = 'br' Then Flush
  Else If M = 'sp' Then
  Begin
    Flush;
    Emit('');
  End
  Else If (M = 'B') Or (M = 'I') Then
  Begin
    S := '';
    For K := 0 To N - 1 Do S := S + A[K] + ' ';
    If S <> '' Then Delete(S, Length(S), 1);
    If M = 'B' Then S := #1 + S + #2 Else S := #3 + S + #2;
    If (Tp = 1) Then TextLine(S) Else If Fill Then Words(S) Else TextLine(S);
  End
  Else If (M = 'BR') Or (M = 'RB') Or (M = 'IR') Or (M = 'RI') Or
          (M = 'BI') Or (M = 'IB') Then
  Begin
    S := '';
    For K := 0 To N - 1 Do
    Begin
      If M[(K Mod 2) + 1] = 'B' Then S := S + #1 + A[K] + #2
      Else If M[(K Mod 2) + 1] = 'I' Then S := S + #3 + A[K] + #2
      Else S := S + A[K];
    End;
    If Tp = 1 Then TextLine(S) Else If Fill Then Words(S) Else TextLine(S);
  End;
End;

Procedure Format(Fd : LongInt);
Var Line : String; Got : Boolean; B : Byte; N : LongInt;
Begin
  Fill := True;
  Indent := 7;
  TpIndent := 14;
  RsLevel := 0;
  Cur := '';
  CurVis := 0;
  Tp := 0;
  Line := '';
  Repeat
    Got := False;
    Line := '';
    While True Do
    Begin
      N := SysRead(Fd, B, 1);
      If N <= 0 Then Break;
      Got := True;
      If B = 10 Then Break;
      If Length(Line) < 250 Then Line := Line + Chr(B);
    End;
    If Got Then
    Begin
      If (Length(Line) >= 3) And (Copy(Line, 1, 3) = '.\"') Then
      Else If (Length(Line) > 1) And ((Line[1] = '.') Or (Line[1] = '''')) Then
        Macro(Line)
      Else
      Begin
        TextLine(Line);
      End;
    End;
  Until Not Got;
  Flush;
  OFlush;
End;

{ ---------------------- recherche des pages ---------------------- }

Function LangCode : String;
Begin
  Case Lang Of
    1 : LangCode := 'fr';
    3 : LangCode := 'de';
    4 : LangCode := 'es';
    5 : LangCode := 'it';
  Else LangCode := 'en';
  End;
End;

Function FileOk(Const P : String) : Boolean;
Var St : TSysStat;
Begin
  FileOk := (SysStat(P, St) = 0) And ((St.Mode And $F000) = $8000);
End;

Function ManPath : String;
Var P : String;
Begin
  P := SysGetEnv('MANPATH');
  If P = '' Then P := '/usr/share/man:/usr/local/share/man';
  ManPath := P;
End;

Function NextDir(Var P : String) : String;
Var K : LongInt;
Begin
  K := Pos(':', P);
  If K = 0 Then
  Begin
    NextDir := P;
    P := '';
  End
  Else
  Begin
    NextDir := Copy(P, 1, K - 1);
    P := Copy(P, K + 1, 255);
  End;
End;

{ chemin de la page NOM.SEC ; Sec = '' : toutes les sections }
Function FindPage(Const Nm, Sec : String; Var Found : String) : Boolean;
Var
  P, D, Order, C : String;
  K : LongInt;
  Pass : LongInt;
Begin
  FindPage := False;
  Order := '182345679';
  If Sec <> '' Then Order := Sec;
  P := ManPath;
  While P <> '' Do
  Begin
    D := NextDir(P);
    If D = '' Then Continue;
    For Pass := 1 To 2 Do
      For K := 1 To Length(Order) Do
      Begin
        C := D;
        If Pass = 1 Then C := C + '/' + LangCode;
        C := C + '/man' + Order[K] + '/' + Nm + '.' + Order[K];
        If FileOk(C) Then
        Begin
          Found := C;
          FindPage := True;
          Exit;
        End;
      End;
  End;
End;

{ ---------------------- -k, -f ---------------------- }

Function DescOf(Const Path : String) : String;
Var Fd, N, Cnt : LongInt; B : Byte; Ln : String; InName : Boolean; K : LongInt;
Begin
  DescOf := '';
  Fd := SysOpen(Path, O_RDONLY, 0);
  If Fd < 0 Then Exit;
  InName := False;
  Cnt := 0;
  Ln := '';
  While Cnt < 60 Do
  Begin
    Ln := '';
    While True Do
    Begin
      N := SysRead(Fd, B, 1);
      If N <= 0 Then Break;
      If B = 10 Then Break;
      If Length(Ln) < 250 Then Ln := Ln + Chr(B);
    End;
    If N <= 0 Then Break;
    Inc(Cnt);
    If InName Then
    Begin
      If (Length(Ln) > 0) And (Ln[1] <> '.') Then
      Begin
        K := Pos('\-', Ln);
        If K > 0 Then Ln := Copy(Ln, K + 2, 250);
        While (Length(Ln) > 0) And (Ln[1] = ' ') Do Delete(Ln, 1, 1);
        DescOf := Ln;
        Break;
      End;
    End
    Else If (Copy(Ln, 1, 3) = '.SH') And (Pos('NAME', Ln) > 0) Then
      InName := True;
  End;
  SysClose(Fd);
End;

Function Lower(Const S : String) : String;
Var K : LongInt; R : String;
Begin
  R := S;
  For K := 1 To Length(R) Do
    If (R[K] >= 'A') And (R[K] <= 'Z') Then R[K] := Chr(Ord(R[K]) + 32);
  Lower := R;
End;

Procedure Scan(Const Word : String; Exact : Boolean);
Var
  P, D, Dd, Nm, De : String;
  Dh, K, Ino, Sec : LongInt;
  Any : Boolean;
Begin
  Any := False;
  P := ManPath;
  While P <> '' Do
  Begin
    D := NextDir(P);
    If D = '' Then Continue;
    For Sec := 1 To 9 Do
    Begin
      Dd := D + '/man' + NumS(Sec);
      Dh := SysOpenDir(Dd);
      If Dh < 0 Then Dh := SysOpenDir(D + '/' + LangCode + '/man' + NumS(Sec));
      If Dh >= 0 Then
      Begin
        Dd := D + '/man' + NumS(Sec);
        While SysReadDir(Dh, Nm, Ino) <> 0 Do
          If (Length(Nm) > 2) And (Nm[1] <> '.') Then
          Begin
            K := Length(Nm);
            While (K > 0) And (Nm[K] <> '.') Do Dec(K);
            If K > 1 Then
            Begin
              De := DescOf(Dd + '/' + Nm);
              If De = '' Then De := DescOf(D + '/' + LangCode + '/man' +
                                           NumS(Sec) + '/' + Nm);
              If (Exact And (Lower(Copy(Nm, 1, K - 1)) = Lower(Word))) Or
                 ((Not Exact) And ((Pos(Lower(Word), Lower(Nm)) > 0) Or
                                   (Pos(Lower(Word), Lower(De)) > 0))) Then
              Begin
                SysPut(1, Copy(Nm, 1, K - 1) + ' (' + NumS(Sec) + ') - ' +
                       De + #10);
                Any := True;
              End;
            End;
          End;
        SysCloseDir(Dh);
      End;
    End;
  End;
  If Not Any Then SysPut(2, Word + ': nothing appropriate.' + #10);
End;

{ ---------------------- affichage ---------------------- }

Procedure Show(Const Path : String; Plain : Boolean);
Var
  Fd, Rd, Pid, St : LongInt;
  Fds : Array[0..1] Of LongInt;
  Pg : String;
Begin
  Fd := SysOpen(Path, O_RDONLY, 0);
  If Fd < 0 Then
  Begin
    SysPut(2, 'man: ' + Path + ': ' + SysErrorText(SysErrno) + #10);
    SysExit(1);
  End;
  OutFd := 1;
  Color := ToTty;
  Pid := 0;
  If ToTty Then
  Begin
    Pg := SysGetEnv('PAGER');
    If Pg = '' Then Pg := 'less';
    If SysPipe(Fds[0]) = 0 Then
    Begin
      Pid := SysFork;
      If Pid = 0 Then
      Begin
        SysClose(Fds[1]);
        SysDup2(Fds[0], 0);
        SysClose(Fds[0]);
        SysArgReset;
        SysArgAdd('sh');
        SysArgAdd('-c');
        SysArgAdd(Pg);
        SysEnvInherit;
        SysArgExec('/bin/sh');
        SysExit(127);
      End;
      SysClose(Fds[0]);
      OutFd := Fds[1];
    End;
  End;
  If Plain Then
  Begin
    { page deja formatee (info) : copie }
    Repeat
      Rd := SysRead(Fd, OutS[1], 200);
      If Rd > 0 Then
      Begin
        OutS[0] := Chr(Rd);
        OFlush;
      End;
    Until Rd <= 0;
  End
  Else Format(Fd);
  SysClose(Fd);
  If Pid > 0 Then
  Begin
    SysClose(OutFd);
    SysWaitPid(Pid, St, 0);
  End;
End;

Var
  I, K : LongInt;
  A, Nm, Sec, Path, Prog, Mode : String;
  Names : Array[1..16] Of String;
  NN : LongInt;
BEGIN
  Lang := SysLang;
  If (Lang < 1) Or (Lang > 5) Then Lang := 1;
  ToTty := SysIsATty(1);
  Prog := SysArgStr(0);
  While Pos('/', Prog) > 0 Do Prog := Copy(Prog, Pos('/', Prog) + 1, 255);
  Mode := '';
  If Prog = 'apropos' Then Mode := 'k'
  Else If Prog = 'whatis' Then Mode := 'f';
  Sec := '';
  NN := 0;
  I := 1;
  While I < SysArgCount Do
  Begin
    A := SysArgStr(I);
    If (A = '--help') Or (A = '/?') Or (A = '-h') Then
    Begin
      SysPut(1, PS(Usage[Lang]) + #10);
      SysExit(0);
    End
    Else If (A = '-k') Or (A = '--apropos') Then Mode := 'k'
    Else If (A = '-f') Or (A = '--whatis') Then Mode := 'f'
    Else If (A = '-w') Or (A = '--where') Then Mode := 'w'
    Else If (A = '-a') Or (A = '-c') Then
    Else If (Length(A) = 1) And (Pos(A, Secs) > 0) And (NN = 0) And
            (I + 1 < SysArgCount) Then Sec := A
    Else If NN < 16 Then
    Begin
      Inc(NN);
      Names[NN] := A;
    End;
    Inc(I);
  End;
  If NN = 0 Then
  Begin
    SysPut(2, PS(Usage[Lang]) + #10);
    SysExit(1);
  End;
  For K := 1 To NN Do
  Begin
    Nm := Names[K];
    If Mode = 'k' Then Scan(Nm, False)
    Else If Mode = 'f' Then Scan(Nm, True)
    Else If Prog = 'info' Then
    Begin
      Path := '/usr/share/info/' + Nm;
      If Not FileOk(Path) Then Path := '/usr/share/info/' + Nm + '.info';
      If FileOk(Path) Then Show(Path, True)
      Else If FindPage(Nm, '', Path) Then Show(Path, False)
      Else
      Begin
        SysPut(2, 'info: ' + PS(NoPage[Lang]) + Nm + #10);
        SysExit(1);
      End;
    End
    Else If FindPage(Nm, Sec, Path) Then
    Begin
      If Mode = 'w' Then SysPut(1, Path + #10) Else Show(Path, False);
    End
    Else
    Begin
      SysPut(2, PS(NoPage[Lang]) + Nm + #10);
      SysExit(16);
    End;
  End;
END.
