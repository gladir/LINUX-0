{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2026
  @website(https://www.gladir.com/linux-0)
  @abstract(Target: LPC -3X)
  @description: /bin/pgrep, pkill, pidof,
      killall : recherche de processus par nom (/proc) ; pkill et killall
      envoient un signal (-s sig | -sig).
}

Program PGREP;

Const
  UsageW : Array[1..5] Of PChar =
    ('Usage : ', 'Usage: ', 'Aufruf: ', 'Uso: ', 'Uso: ');

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

Procedure Usage(Const Syn : String);
Begin
  SysPut(2, PS(UsageW[SysLang]) + Syn + #10);
  SysExit(1);
End;

Procedure Warn(Const What : String);
Begin
  SysPut(2, 'pgrep: ' + What + ': ' + SysErrorText(SysErrno) + #10);
End;

Function BaseOf(Const P : String) : String;
Var K, L : LongInt;
Begin
  L := Length(P);
  While (L > 1) And (P[L] = '/') Do Dec(L);
  K := L;
  While (K > 0) And (P[K] <> '/') Do Dec(K);
  BaseOf := Copy(P, K + 1, L - K);
End;

Function IsDir(Const P : String) : Boolean;
Var St : TSysStat;
Begin
  IsDir := (SysStat(P, St) = 0) And ((St.Mode And $F000) = $4000);
End;

Var
  Mode : LongInt;           { 1 pgrep 2 pkill 3 pidof 4 killall }
  Sig, I, N, Hits, Pid, Me : LongInt;
  Pat, A : String;
  Full, Exact : Boolean;

Function SigNum(Const S : String) : LongInt;
Var K, Code : LongInt;
Begin
  Val(S, K, Code);
  If Code = 0 Then
  Begin
    SigNum := K;
    Exit;
  End;
  If S = 'HUP' Then SigNum := 1 Else If S = 'INT' Then SigNum := 2
  Else If S = 'QUIT' Then SigNum := 3 Else If S = 'KILL' Then SigNum := 9
  Else If S = 'USR1' Then SigNum := 10 Else If S = 'USR2' Then SigNum := 12
  Else If S = 'ALRM' Then SigNum := 14 Else If S = 'TERM' Then SigNum := 15
  Else If S = 'CONT' Then SigNum := 18 Else If S = 'STOP' Then SigNum := 19
  Else SigNum := 15;
End;

Function ProcName(P : LongInt; Var Cmd : String) : String;
Var Fd : LongInt; L, Nm : String;
Begin
  Nm := '';
  Cmd := '';
  Fd := SysOpen('/proc/' + NumS(P) + '/status', O_RDONLY, 0);
  If Fd >= 0 Then
  Begin
    While SysReadLine(Fd, L) Do
      If Copy(L, 1, 5) = 'Name:' Then
      Begin
        Nm := Copy(L, 6, 80);
        While (Nm <> '') And ((Nm[1] = ' ') Or (Nm[1] = #9)) Do Nm := Copy(Nm,
          2, 80);
        Break;
      End;
    SysClose(Fd);
  End;
  Fd := SysOpen('/proc/' + NumS(P) + '/cmdline', O_RDONLY, 0);
  If Fd >= 0 Then
  Begin
    If SysReadLine(Fd, L) Then Cmd := L;
    SysClose(Fd);
  End;
  ProcName := Nm;
End;

Procedure Scan;
Var D, Ino, P, K, V : LongInt; Nm, Cmd, Pn : String; Ok, Hit : Boolean;
Begin
  D := SysOpenDir('/proc');
  If D < 0 Then Exit;
  While SysReadDir(D, Nm, Ino) Do
  Begin
    Ok := Length(Nm) > 0;
    V := 0;
    For K := 1 To Length(Nm) Do
      If (Nm[K] >= '0') And (Nm[K] <= '9') Then V := V * 10 + Ord(Nm[K]) - 48
      Else Ok := False;
    If (Not Ok) Or (V = Me) Then Continue;
    If ((Mode = 2) Or (Mode = 4)) And (V <= 2) Then Continue;
    Pn := ProcName(V, Cmd);
    If Full Then Hit := Pos(Pat, Cmd) > 0
    Else If Exact Then Hit := Pn = Pat
    Else Hit := Pos(Pat, Pn) > 0;
    If Hit Then
    Begin
      Inc(Hits);
      If (Mode = 1) Or (Mode = 3) Then SysPut(1, NumS(V) + #10)
      Else If SysKill(V, Sig) < 0 Then Warn(NumS(V));
    End;
  End;
  SysCloseDir(D);
End;

BEGIN
  Mode := 1;
  A := SysArgStr(0);
  If Pos('pkill', A) > 0 Then Mode := 2
  Else If Pos('pidof', A) > 0 Then Mode := 3
  Else If Pos('killall', A) > 0 Then Mode := 4;
  Sig := 15;
  Full := False;
  Exact := (Mode = 3) Or (Mode = 4);
  Pat := '';
  Hits := 0;
  Me := SysGetPid;
  I := 1;
  While I < SysArgCount Do
  Begin
    A := SysArgStr(I);
    If (A = '-f') Then Full := True
    Else If (A = '-x') Then Exact := True
    Else If (A = '-s') And (I + 1 < SysArgCount) Then
    Begin
      Inc(I);
      Sig := SigNum(SysArgStr(I));
    End
    Else If (Length(A) > 1) And (A[1] = '-') Then Sig := SigNum(Copy(A, 2, 20))
    Else Pat := A;
    Inc(I);
  End;
  If Pat = '' Then
    Usage('pgrep|pkill [-f] [-x] [-sig] pattern | pidof|killall name');
  Scan;
  If Hits = 0 Then SysExit(1);
END.
