{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2026
  @website(https://www.gladir.com/linux-0)
  @abstract(Target: LPC -3X)
  @description: /bin/timeout : lance une commande et l arrete apres un delai
      (timeout [-s sig] secondes commande...).
}

Program TIMEOUT;

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
  SysPut(2, 'timeout: ' + What + ': ' + SysErrorText(SysErrno) + #10);
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
  Secs, Code, I, K, Pid, St, Sig, R : LongInt;
  A : String;
  Done : Boolean;

Function FindExe(Const Name : String) : String;
Var Path, Dir : String; K : LongInt;
Begin
  FindExe := Name;
  If Pos('/', Name) > 0 Then Exit;
  Path := SysGetEnv('PATH');
  If Path = '' Then Path := '/bin:/usr/bin:/sbin:/usr/sbin';
  While Path <> '' Do
  Begin
    K := Pos(':', Path);
    If K = 0 Then
    Begin
      Dir := Path;
      Path := '';
    End
    Else
    Begin
      Dir := Copy(Path, 1, K - 1);
      Path := Copy(Path, K + 1, 255);
    End;
    If SysAccess(Dir + '/' + Name, 1) = 0 Then
    Begin
      FindExe := Dir + '/' + Name;
      Exit;
    End;
  End;
End;

BEGIN
  Sig := 15;
  I := 1;
  If (SysArgCount > 3) And (SysArgStr(1) = '-s') Then
  Begin
    Val(SysArgStr(2), Sig, Code);
    I := 3;
  End;
  If I + 1 >= SysArgCount Then
    Usage('timeout [-s signal] seconds command [args...]');
  Val(SysArgStr(I), Secs, Code);
  Inc(I);
  Pid := SysFork;
  If Pid = 0 Then
  Begin
    SysArgReset;
    For K := I To SysArgCount - 1 Do SysArgAdd(SysArgStr(K));
    SysEnvInherit;
    A := FindExe(SysArgStr(I));
    SysArgExec(A);
    Warn(SysArgStr(I));
    SysExit(127);
  End;
  Done := False;
  K := 0;
  While Not Done Do
  Begin
    R := SysWaitPid(Pid, St, WNOHANG);
    If R = Pid Then Done := True
    Else If R < 0 Then Done := True
    Else
    Begin
      SysSleep(1);
      Inc(K);
      If K >= Secs Then
      Begin
        SysKill(Pid, Sig);
        SysWaitPid(Pid, St, 0);
        SysExit(124);
      End;
    End;
  End;
  If SysWIfExited(St) Then SysExit(SysWExitStatus(St));
  SysExit(128 + SysWTermSig(St));
END.
