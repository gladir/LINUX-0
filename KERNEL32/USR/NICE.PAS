{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2026
  @website(https://www.gladir.com/linux-0)
  @abstract(Target: LPC -3X)
  @description: /bin/nice : lance une commande avec une priorite modifiee
      (nice [-n N] commande...).
}

Program NICE;

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
  SysPut(2, 'nice: ' + What + ': ' + SysErrorText(SysErrno) + #10);
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
  N, I, K, Code : LongInt;
  A : String;

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
  N := 10;
  I := 1;
  If (SysArgCount > 2) And ((SysArgStr(1) = '-n') Or (SysArgStr(1) =
    '--adjustment')) Then
  Begin
    Val(SysArgStr(2), N, Code);
    I := 3;
  End
  Else If (SysArgCount > 1) And (Copy(SysArgStr(1), 1, 1) = '-') And
          (Length(SysArgStr(1)) > 1) And (SysArgStr(1)[2] >= '0') And
          (SysArgStr(1)[2] <= '9') Then
  Begin
    Val(Copy(SysArgStr(1), 2, 10), N, Code);
    I := 2;
  End;
  If I >= SysArgCount Then Usage('nice [-n N] command [args...]');
  { setpriority(PRIO_PROCESS, 0, nice) : 97 }
  SysCall(97, 0, 0, 20 + N, 0, 0);
  SysArgReset;
  For K := I To SysArgCount - 1 Do SysArgAdd(SysArgStr(K));
  SysEnvInherit;
  A := FindExe(SysArgStr(I));
  SysArgExec(A);
  Warn(SysArgStr(I));
  SysExit(127);
END.
