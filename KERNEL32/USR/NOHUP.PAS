{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2026
  @website(https://www.gladir.com/linux-0)
  @abstract(Target: LPC -3X)
  @description: /bin/nohup : lance une commande insensible a SIGHUP (sortie
      vers nohup.out si terminal).
}

Program NOHUP;

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
  SysPut(2, 'nohup: ' + What + ': ' + SysErrorText(SysErrno) + #10);
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
  K, Fd : LongInt;
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
  If SysArgCount < 2 Then Usage('nohup command [args...]');
  SysSigAction(SIGHUP, SIG_IGN, 0);
  If SysIsATty(1) Then
  Begin
    Fd := SysOpen('nohup.out', O_WRONLY Or O_CREAT Or O_APPEND, 384);
    If Fd >= 0 Then
    Begin
      SysPut(2, 'nohup: ignoring input and appending output to nohup.out' +
        #10);
      SysDup2(Fd, 1);
      If SysIsATty(2) Then SysDup2(Fd, 2);
      SysClose(Fd);
    End;
  End;
  SysArgReset;
  For K := 1 To SysArgCount - 1 Do SysArgAdd(SysArgStr(K));
  SysEnvInherit;
  A := FindExe(SysArgStr(1));
  SysArgExec(A);
  Warn(SysArgStr(1));
  SysExit(127);
END.
