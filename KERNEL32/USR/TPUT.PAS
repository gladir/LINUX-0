{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2026
  @website(https://www.gladir.com/linux-0)
  @abstract(Target: LPC -3X)
  @description: tput, clear, reset, infocmp, tset (un seul programme, le nom
      lu dans argv[0]). Base terminfo integree pour les terminaux linux,
      vt100, vt220, xterm, xterm-256color, ansi, screen (TERM ou -T type) :
      les capacites les plus utiles sont fabriquees sans fichier.
    tput [-T type] capacite [arguments]   cols lines colors it, clear, cup l c,
      home, el, ed, bold, dim, rev, smul, rmul, smso, rmso, blink, sgr0,
      setaf n, setab n, op, civis, cnorm, smcup, rmcup, bel, cr, hpa n,
      vpa n, cuu1 cud1 cuf1 cub1, cuu n, cud n, cuf n, cub n, ech n, dch1,
      il1, dl1, ich1, csr t b, sc, rc, rs1, rs2, rs3, init, reset, longname ;
      booleens am bce msgr xenl km hs mir eo ; code 1 si absent, 4 si inconnu.
    clear   efface l'ecran ; reset   reinitialise le terminal et le mode tty
    infocmp [-1] [type]   decrit le terminal en syntaxe terminfo
    Messages en cinq langues (LANGUAGE).
}

Program Tput;

Const
  M : Array[1..3, 1..5] Of PChar = (
    ('Usage : tput [-T type] capacite [arguments]',
     'Usage: tput [-T type] capname [args]',
     'Aufruf: tput [-T Typ] Faehigkeit [Argumente]',
     'Uso: tput [-T tipo] capacidad [argumentos]',
     'Uso: tput [-T tipo] capacita'' [argomenti]'),
    ('type de terminal inconnu : ', 'unknown terminal type: ',
     'unbekannter Terminaltyp: ', 'tipo de terminal desconocido: ',
     'tipo di terminale sconosciuto: '),
    ('capacite terminfo inconnue : ', 'unknown terminfo capability ',
     'unbekannte terminfo-Faehigkeit ', 'capacidad terminfo desconocida ',
     'capacita'' terminfo sconosciuta '));

Var
  Prog, Term : String;
  Kind : LongInt;      { 1 linux, 2 vt100, 3 xterm, 4 ansi, 5 screen, 6 vt220 }
  Colors : LongInt;
  Rc : LongInt;
  ClearK : Boolean;

Function Msg(Id : LongInt) : String;
Var P : PChar; X : String;
Begin
  P := M[Id, SysLang];
  X := '';
  While P^ <> #0 Do
  Begin
    X := X + P^;
    Inc(P);
  End;
  Msg := X;
End;

Function NumS(V : LongInt) : String;
Var S : String;
Begin
  Str(V, S);
  NumS := S;
End;

Function ToNum(Const S : String) : LongInt;
Var V, C : LongInt;
Begin
  Val(S, V, C);
  If C <> 0 Then V := 0;
  ToNum := V;
End;

Function Esc : String;
Begin
  Esc := #27;
End;

{ type de terminal connu ? }
Function SetTerm(Const T : String) : Boolean;
Begin
  SetTerm := True;
  Term := T;
  Colors := 8;
  If (T = 'linux') Or (T = 'linux-c') Or (T = 'linux-16color') Then
  Begin
    Kind := 1;
    If T = 'linux-16color' Then Colors := 16;
  End
  Else If (T = 'vt100') Or (T = 'vt102') Or (T = 'vt100-am') Then
  Begin
    Kind := 2;
    Colors := 0;
  End
  Else If (T = 'vt220') Or (T = 'vt200') Or (T = 'vt320') Then
  Begin
    Kind := 6;
    Colors := 0;
  End
  Else If (T = 'xterm') Or (T = 'xterm-color') Or (T = 'xterm-256color') Or
          (T = 'xterm-16color') Or (T = 'rxvt') Or (T = 'rxvt-unicode') Or
          (T = 'rxvt-256color') Or (T = 'alacritty') Or (T = 'st-256color')
  Then
  Begin
    Kind := 3;
    If Pos('256', T) > 0 Then Colors := 256;
    If T = 'xterm-16color' Then Colors := 16;
  End
  Else If (T = 'ansi') Or (T = 'ansi.sys') Or (T = 'cygwin') Then Kind := 4
  Else If (Copy(T, 1, 6) = 'screen') Or (Copy(T, 1, 4) = 'tmux') Then
  Begin
    Kind := 5;
    If Pos('256', T) > 0 Then Colors := 256;
  End
  Else SetTerm := False;
End;

Function WinCols : LongInt;
Var W : TSysWinSize; S : String; N : LongInt;
Begin
  WinCols := 80;
  S := SysGetEnv('COLUMNS');
  N := ToNum(S);
  If N > 0 Then
  Begin
    WinCols := N;
    Exit;
  End;
  If (SysGetWinSize(1, W) = 0) And (W.Col > 0) Then WinCols := W.Col
  Else If (SysGetWinSize(2, W) = 0) And (W.Col > 0) Then WinCols := W.Col;
End;

Function WinLines : LongInt;
Var W : TSysWinSize; S : String; N : LongInt;
Begin
  WinLines := 24;
  If Kind = 1 Then WinLines := 25;
  S := SysGetEnv('LINES');
  N := ToNum(S);
  If N > 0 Then
  Begin
    WinLines := N;
    Exit;
  End;
  If (SysGetWinSize(1, W) = 0) And (W.Row > 0) Then WinLines := W.Row
  Else If (SysGetWinSize(2, W) = 0) And (W.Row > 0) Then WinLines := W.Row;
End;

Function Sgr0 : String;
Begin
  Case Kind Of
    1 : Sgr0 := Esc + '[m' + #15;
    3, 5 : Sgr0 := Esc + '(B' + Esc + '[m';
    2 : Sgr0 := Esc + '[m' + #15;
  Else
    Sgr0 := Esc + '[0m';
  End;
End;

{ sequence de la capacite Cap (A, B : arguments) ; Known = False si inconnue }
Function Cap(Const Name : String; A, B : LongInt; Var Known : Boolean) : String;
Var E : String;
Begin
  E := Esc;
  Known := True;
  Cap := '';
  If Name = 'clear' Then
  Begin
    If Kind = 1 Then Cap := E + '[H' + E + '[J' + E + '[3J'
    Else If Kind = 2 Then Cap := E + '[H' + E + '[J'
    Else If Kind = 6 Then Cap := E + '[H' + E + '[J'
    Else Cap := E + '[H' + E + '[2J' + E + '[3J';
  End
  Else If Name = 'home' Then Cap := E + '[H'
  Else If Name = 'el' Then Cap := E + '[K'
  Else If Name = 'el1' Then Cap := E + '[1K'
  Else If Name = 'ed' Then Cap := E + '[J'
  Else If Name = 'cr' Then Cap := #13
  Else If Name = 'bel' Then Cap := #7
  Else If Name = 'ind' Then Cap := #10
  Else If Name = 'nel' Then Cap := #13 + #10
  Else If Name = 'cud1' Then Cap := #10
  Else If Name = 'cub1' Then Cap := #8
  Else If Name = 'cuf1' Then Cap := E + '[C'
  Else If Name = 'cuu1' Then Cap := E + '[A'
  Else If Name = 'ht' Then Cap := #9
  Else If Name = 'cup' Then
    Cap := E + '[' + NumS(A + 1) + ';' + NumS(B + 1) + 'H'
  Else If Name = 'hpa' Then Cap := E + '[' + NumS(A + 1) + 'G'
  Else If Name = 'vpa' Then Cap := E + '[' + NumS(A + 1) + 'd'
  Else If Name = 'csr' Then
    Cap := E + '[' + NumS(A + 1) + ';' + NumS(B + 1) + 'r'
  Else If Name = 'cuu' Then Cap := E + '[' + NumS(A) + 'A'
  Else If Name = 'cud' Then Cap := E + '[' + NumS(A) + 'B'
  Else If Name = 'cuf' Then Cap := E + '[' + NumS(A) + 'C'
  Else If Name = 'cub' Then Cap := E + '[' + NumS(A) + 'D'
  Else If Name = 'ech' Then Cap := E + '[' + NumS(A) + 'X'
  Else If Name = 'dch' Then Cap := E + '[' + NumS(A) + 'P'
  Else If Name = 'dch1' Then Cap := E + '[P'
  Else If Name = 'ich' Then Cap := E + '[' + NumS(A) + '@'
  Else If Name = 'ich1' Then Cap := E + '[@'
  Else If Name = 'il' Then Cap := E + '[' + NumS(A) + 'L'
  Else If Name = 'il1' Then Cap := E + '[L'
  Else If Name = 'dl' Then Cap := E + '[' + NumS(A) + 'M'
  Else If Name = 'dl1' Then Cap := E + '[M'
  Else If Name = 'bold' Then Cap := E + '[1m'
  Else If Name = 'dim' Then Cap := E + '[2m'
  Else If Name = 'rev' Then Cap := E + '[7m'
  Else If Name = 'smso' Then Cap := E + '[7m'
  Else If Name = 'rmso' Then Cap := E + '[27m'
  Else If Name = 'smul' Then Cap := E + '[4m'
  Else If Name = 'rmul' Then Cap := E + '[24m'
  Else If Name = 'blink' Then Cap := E + '[5m'
  Else If Name = 'invis' Then Cap := E + '[8m'
  Else If Name = 'sitm' Then Cap := E + '[3m'
  Else If Name = 'ritm' Then Cap := E + '[23m'
  Else If Name = 'sgr0' Then Cap := Sgr0
  Else If Name = 'smacs' Then Cap := E + '(0'
  Else If Name = 'rmacs' Then Cap := E + '(B'
  Else If Name = 'op' Then Cap := E + '[39;49m'
  Else If ((Name = 'setaf') Or (Name = 'setab')) And (Colors = 0) Then
    Known := True
  Else If (Name = 'civis') And (Kind In [2, 6]) Then Known := True
  Else If (Name = 'setaf') Or (Name = 'setab') Then
  Begin
    If Name = 'setaf' Then E := E + '[3' Else E := E + '[4';
    If A < 8 Then Cap := E + NumS(A) + 'm'
    Else If (A < 16) And (Colors <= 16) Then
    Begin
      If Name = 'setaf' Then Cap := Esc + '[9' + NumS(A - 8) + 'm'
      Else Cap := Esc + '[10' + NumS(A - 8) + 'm';
    End
    Else If Name = 'setaf' Then Cap := Esc + '[38;5;' + NumS(A) + 'm'
    Else Cap := Esc + '[48;5;' + NumS(A) + 'm';
  End
  Else If Name = 'civis' Then
  Begin
    If Kind = 1 Then Cap := E + '[?25l' + E + '[?1c' Else Cap := E + '[?25l';
  End
  Else If ((Name = 'cnorm') Or (Name = 'cvvis')) And (Kind In [2, 6]) Then
    Known := True
  Else If (Name = 'cnorm') Or (Name = 'cvvis') Then
  Begin
    If Kind = 1 Then Cap := E + '[?25h' + E + '[?0c'
    Else If Kind = 3 Then Cap := E + '[?12l' + E + '[?25h'
    Else Cap := E + '[?25h';
  End
  Else If Name = 'smcup' Then
  Begin
    If Kind = 3 Then Cap := E + '[?1049h' + E + '[22;0;0t'
    Else If Kind = 5 Then Cap := E + '[?1049h';
  End
  Else If Name = 'rmcup' Then
  Begin
    If Kind = 3 Then Cap := E + '[?1049l' + E + '[23;0;0t'
    Else If Kind = 5 Then Cap := E + '[?1049l';
  End
  Else If Name = 'sc' Then Cap := E + '7'
  Else If Name = 'rc' Then Cap := E + '8'
  Else If (Name = 'rs1') Or (Name = 'rs2') Or (Name = 'rs3') Then
  Begin
    If Name = 'rs1' Then Cap := E + 'c'
    Else If Name = 'rs2' Then
    Begin
      If Kind = 3 Then Cap := E + '[!p' + E + '[?3;4l' + E + '[4l' + E + '>'
      Else If Kind = 1 Then Cap := E + '[r'
    End;
  End
  Else If Name = 'kcuu1' Then Cap := E + 'OA'
  Else If Name = 'kcud1' Then Cap := E + 'OB'
  Else If Name = 'kcuf1' Then Cap := E + 'OC'
  Else If Name = 'kcub1' Then Cap := E + 'OD'
  Else If Name = 'kbs' Then Cap := #127
  Else If Name = 'smkx' Then Cap := E + '[?1h' + E + '='
  Else If Name = 'rmkx' Then Cap := E + '[?1l' + E + '>'
  Else Known := False;
End;

Function IsBool(Const N : String; Var V : Boolean) : Boolean;
Begin
  IsBool := True;
  V := False;
  If N = 'am' Then V := True
  Else If N = 'msgr' Then V := True
  Else If N = 'xenl' Then V := Kind <> 6
  Else If N = 'bce' Then V := Kind In [1, 3, 5]
  Else If N = 'km' Then V := Kind In [1, 3, 5, 6]
  Else If N = 'mir' Then V := True
  Else If N = 'eo' Then V := False
  Else If N = 'hs' Then V := False
  Else If N = 'xon' Then V := Kind = 2
  Else If (N = 'bw') Or (N = 'xt') Or (N = 'hc') Or (N = 'gn') Or (N = 'os')
    Or (N = 'ul') Or (N = 'in') Or (N = 'da') Or (N = 'db') Then V := False
  Else IsBool := False;
End;

Function LongName : String;
Begin
  Case Kind Of
    1 : LongName := 'Linux console';
    2 : LongName := 'DEC VT100 (w/advanced video)';
    3 : LongName := 'xterm terminal emulator (X Window System)';
    4 : LongName := 'ANSI/ECMA-48 terminal and ANSI.SYS compatible';
    5 : LongName := 'VT 100/ANSI X3.64 virtual terminal';
    6 : LongName := 'DEC VT220';
  Else
    LongName := Term;
  End;
End;

{ ESC -> \E, controles -> \r \n \t ou ^X (syntaxe terminfo) }
Function EscapeText(Const S : String) : String;
Var K : LongInt; R : String; C : Char;
Begin
  R := '';
  For K := 1 To Length(S) Do
  Begin
    C := S[K];
    If C = #27 Then R := R + '\E'
    Else If C = #13 Then R := R + '\r'
    Else If C = #10 Then R := R + '\n'
    Else If C = #9 Then R := R + '\t'
    Else If C = #8 Then R := R + '\b'
    Else If C = #7 Then R := R + '^G'
    Else If C = #15 Then R := R + '^O'
    Else If C = ',' Then R := R + '\,'
    Else R := R + C;
  End;
  EscapeText := R;
End;

Procedure PutStr(Const S : String);
Begin
  If S <> '' Then SysPut(1, S);
End;

Procedure RunTput;
Var I, K, A, B : LongInt; Name, S : String; Known, V : Boolean;
    Args : Array[1..4] Of String; NA : LongInt;
Begin
  Name := '';
  NA := 0;
  I := 1;
  While I < SysArgCount Do
  Begin
    S := SysArgStr(I);
    If (S = '-T') And (I + 1 < SysArgCount) Then
    Begin
      Inc(I);
      Term := SysArgStr(I);
    End
    Else If Copy(S, 1, 2) = '-T' Then Term := Copy(S, 3, 40)
    Else If (S = '-V') Then
    Begin
      SysPut(1, 'tput (KERNEL32 terminfo)' + #10);
      SysExit(0);
    End
    Else If (S = '-h') Or (S = '--help') Then
    Begin
      SysPut(1, Msg(1) + #10);
      SysExit(0);
    End
    Else If Name = '' Then Name := S
    Else If NA < 4 Then
    Begin
      Inc(NA);
      Args[NA] := S;
    End;
    Inc(I);
  End;
  If Name = '' Then
  Begin
    SysPut(2, Msg(1) + #10);
    SysExit(2);
  End;
  If Not SetTerm(Term) Then
  Begin
    SysPut(2, 'tput: ' + Msg(2) + Term + #10);
    SysExit(2);
  End;
  A := 0;
  B := 0;
  If NA >= 1 Then A := ToNum(Args[1]);
  If NA >= 2 Then B := ToNum(Args[2]);
  If Name = 'cols' Then
  Begin
    SysPut(1, NumS(WinCols) + #10);
    Exit;
  End;
  If Name = 'lines' Then
  Begin
    SysPut(1, NumS(WinLines) + #10);
    Exit;
  End;
  If (Name = 'colors') Or (Name = 'Co') Then
  Begin
    If Colors = 0 Then SysPut(1, '-1' + #10) Else SysPut(1, NumS(Colors) + #10);
    Exit;
  End;
  If Name = 'pairs' Then
  Begin
    If Colors > 0 Then SysPut(1, NumS(Colors * 8) + #10)
    Else SysPut(1, '0' + #10);
    Exit;
  End;
  If Name = 'it' Then
  Begin
    SysPut(1, '8' + #10);
    Exit;
  End;
  If Name = 'longname' Then
  Begin
    SysPut(1, LongName + #10);
    Exit;
  End;
  If Name = 'init' Then
  Begin
    PutStr(Cap('is2', 0, 0, Known));
    Exit;
  End;
  If Name = 'reset' Then
  Begin
    PutStr(Cap('rs1', 0, 0, Known));
    PutStr(Cap('rs2', 0, 0, Known));
    Exit;
  End;
  If IsBool(Name, V) Then
  Begin
    If V Then Rc := 0 Else Rc := 1;
    Exit;
  End;
  S := Cap(Name, A, B, Known);
  If Not Known Then
  Begin
    SysPut(2, 'tput: ' + Msg(3) + '''' + Name + '''' + #10);
    Rc := 4;
    Exit;
  End;
  If S = '' Then
  Begin
    Rc := 1;
    Exit;
  End;
  PutStr(S);
End;

Procedure RunReset;
Var T : TSysTermios; Known : Boolean;
Begin
  If SysTcGetAttr(0, T) = 0 Then
  Begin
    T.IFlag := (T.IFlag Or $500) And Not $40;      { BRKINT ICRNL }
    T.OFlag := T.OFlag Or 5;                       { OPOST ONLCR }
    T.LFlag := T.LFlag Or ($1 Or $2 Or $8 Or $10 Or $20 Or $40 Or $80 Or
                           $200 Or $800 Or $1000);
    SysTcSetAttr(0, 0, T);
  End;
  PutStr(Cap('rs1', 0, 0, Known));
  PutStr(Cap('rs2', 0, 0, Known));
  PutStr(Cap('clear', 0, 0, Known));
End;

Procedure RunInfocmp;
Var I : LongInt; One : Boolean; Sep, S : String; Known : Boolean;
Const
  Names : Array[1..34] Of String[6] = ('bel', 'blink', 'bold', 'clear', 'cr',
    'cub1', 'cud1', 'cuf1', 'cup', 'cuu1', 'dch1', 'dim', 'dl1', 'ed', 'el',
    'home', 'ich1', 'il1', 'invis', 'op', 'rev', 'rmacs', 'rmso', 'rmul',
    'sc', 'rc', 'setab', 'setaf', 'sgr0', 'smacs', 'smso', 'smul', 'civis',
    'cnorm');
Begin
  One := False;
  For I := 1 To SysArgCount - 1 Do
    If SysArgStr(I) = '-1' Then One := True
    Else If SysArgStr(I)[1] <> '-' Then Term := SysArgStr(I);
  If Not SetTerm(Term) Then
  Begin
    SysPut(2, 'infocmp: ' + Msg(2) + Term + #10);
    SysExit(1);
  End;
  SysPut(1, '#	Reconstructed via infocmp (KERNEL32)' + #10);
  SysPut(1, Term + '|' + LongName + ',' + #10);
  If One Then Sep := #10 + #9 Else Sep := ' ';
  S := #9 + 'am, bce, msgr, mir, xenl,';
  SysPut(1, S + #10);
  SysPut(1, #9 + 'colors#' + NumS(Colors) + ', cols#80, it#8, lines#' +
         NumS(WinLines) + ',' + #10);
  For I := 1 To 34 Do
  Begin
    S := Cap(Names[I], 1, 1, Known);
    If Known And (S <> '') Then
    Begin
      If Names[I] = 'cup' Then S := Esc + '[%i%p1%d;%p2%dH'
      Else If Names[I] = 'setaf' Then S := Esc + '[3%p1%dm'
      Else If Names[I] = 'setab' Then S := Esc + '[4%p1%dm';
      SysPut(1, #9 + Names[I] + '=' + EscapeText(S) + ',' + #10);
    End;
  End;
End;

BEGIN
  Prog := SysArgStr(0);
  While Pos('/', Prog) > 0 Do Prog := Copy(Prog, Pos('/', Prog) + 1, 255);
  Term := SysGetEnv('TERM');
  If Term = '' Then Term := 'linux';
  Rc := 0;
  If Prog = 'clear' Then
  Begin
    If Not SetTerm(Term) Then SetTerm('linux');
    PutStr(Cap('clear', 0, 0, ClearK));
  End
  Else If (Prog = 'reset') Or (Prog = 'tset') Then
  Begin
    If Not SetTerm(Term) Then SetTerm('linux');
    RunReset;
  End
  Else If Prog = 'infocmp' Then RunInfocmp
  Else RunTput;
  SysExit(Rc);
END.
