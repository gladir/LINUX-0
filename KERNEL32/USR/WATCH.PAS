{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2026
  @website(https://www.gladir.com/linux-0)
  @abstract(Target: LPC -3X)
  @description: /bin/watch : repete une commande (watch [-n secondes] commande...).
}

Program WATCH;

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
  SysPut(2, 'watch: ' + What + ': ' + SysErrorText(SysErrno) + #10);
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
  Secs, I, K, Code, Pid, St : LongInt;
  Cmd : String;
BEGIN
  Secs := 2;
  I := 1;
  If (SysArgCount > 2) And (SysArgStr(1) = '-n') Then
  Begin
    Val(SysArgStr(2), Secs, Code);
    I := 3;
  End;
  If I >= SysArgCount Then Usage('watch [-n seconds] command...');
  Cmd := '';
  For K := I To SysArgCount - 1 Do Cmd := Cmd + SysArgStr(K) + ' ';
  While True Do
  Begin
    SysPut(1, #27 + '[H' + #27 + '[2J' + 'Every ' + NumS(Secs) + 's: ' + Cmd + #10 + #10);
    Pid := SysFork;
    If Pid = 0 Then
    Begin
      SysArgReset;
      SysArgAdd('sh');
      SysArgAdd('-c');
      SysArgAdd(Cmd);
      SysEnvInherit;
      SysArgExec('/bin/sh');
      SysExit(127);
    End;
    SysWaitPid(Pid, St, 0);
    SysSleep(Secs);
  End;
END.
