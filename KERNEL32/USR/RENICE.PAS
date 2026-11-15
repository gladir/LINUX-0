{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2026
  @website(https://www.gladir.com/linux-0)
  @abstract(Target: LPC -3X)
  @description: /bin/renice : change la priorite de processus
      (renice [-n] priorite pid...).
}

Program RENICE;

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
  SysPut(2, 'renice: ' + What + ': ' + SysErrorText(SysErrno) + #10);
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
  I, N, Pid, Code, Rc, R : LongInt;
  A : String;
BEGIN
  If SysArgCount < 3 Then Usage('renice [-n] priority pid...');
  I := 1;
  If SysArgStr(1) = '-n' Then I := 2;
  Val(SysArgStr(I), N, Code);
  Inc(I);
  Rc := 0;
  While I < SysArgCount Do
  Begin
    Val(SysArgStr(I), Pid, Code);
    { setpriority(PRIO_PROCESS = 0, pid, prio) }
    R := LnxRes(LnxSys3(97, 0, Pid, N));
    If R < 0 Then
    Begin
      Warn(SysArgStr(I));
      Rc := 1;
    End;
    Inc(I);
  End;
  SysExit(Rc);
END.
