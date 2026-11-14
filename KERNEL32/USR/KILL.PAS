{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2026
  @website(https://www.gladir.com/linux-0)
  @abstract(Target: LPC -3X)
  @description: /bin/kill : envoie un signal (kill [-s sig | -sig] pid... ;
      kill -l liste les signaux).
}

Program Kill;

Const
  M : Array[1..3, 1..5] Of PChar = (
    ('Usage : kill [-s signal | -signal] pid...',
      'Usage: kill [-s signal | -signal] pid...',
     'Aufruf: kill [-s Signal | -Signal] pid...',
       'Uso: kill [-s senal | -senal] pid...',
     'Uso: kill [-s segnale | -segnale] pid...'),
    ('signal inconnu : ', 'unknown signal: ', 'unbekanntes Signal: ',
      'senal desconocida: ',
     'segnale sconosciuto: '),
    ('kill : ', 'kill: ', 'kill: ', 'kill: ', 'kill: '));
  Names : Array[1..31] Of String[7] = (
    'HUP', 'INT', 'QUIT', 'ILL', 'TRAP', 'ABRT', 'BUS', 'FPE', 'KILL', 'USR1',
    'SEGV', 'USR2', 'PIPE', 'ALRM', 'TERM', 'STKFLT', 'CHLD', 'CONT', 'STOP',
    'TSTP', 'TTIN', 'TTOU', 'URG', 'XCPU', 'XFSZ', 'VTALRM', 'PROF', 'WINCH',
    'IO', 'PWR', 'SYS');

Var Sig, I, X, E : LongInt; A : String; Rc : LongInt;

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

Function SigOf(S : String) : LongInt;
Var K, V, C : LongInt;
Begin
  SigOf := -1;
  Val(S, V, C);
  If C = 0 Then
  Begin
    SigOf := V;
    Exit;
  End;
  For K := 1 To Length(S) Do S[K] := UpCase(S[K]);
  If Copy(S, 1, 3) = 'SIG' Then S := Copy(S, 4, 20);
  For K := 1 To 31 Do
    If Names[K] = S Then SigOf := K;
End;

BEGIN
  Sig := SIGTERM;
  I := 1;
  If SysArgCount < 2 Then
  Begin
    SysPut(2, Msg(1) + #10);
    SysExit(2);
  End;
  A := SysArgStr(1);
  If A = '-l' Then
  Begin
    For X := 1 To 31 Do SysPut(1, Names[X] + ' ');
    SysPut(1, #10);
    SysExit(0);
  End;
  If (A = '-s') And (SysArgCount > 2) Then
  Begin
    Sig := SigOf(SysArgStr(2));
    I := 3;
  End
  Else If (Length(A) > 1) And (A[1] = '-') Then
  Begin
    Sig := SigOf(Copy(A, 2, 20));
    I := 2;
  End;
  If Sig < 0 Then
  Begin
    SysPut(2, Msg(2) + A + #10);
    SysExit(1);
  End;
  Rc := 0;
  While I < SysArgCount Do
  Begin
    A := SysArgStr(I);
    Val(A, X, E);
    If (E <> 0) Or (SysKill(X, Sig) < 0) Then
    Begin
      If E <> 0 Then SysErrno := 3;
      SysPut(2, Msg(3) + A + ' : ' + SysErrorText(SysErrno) + #10);
      Rc := 1;
    End;
    Inc(I);
  End;
  SysExit(Rc);
END.
