{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2026
  @website(https://www.gladir.com/linux-0)
  @abstract(Target: LPC -3X)
  @description: /sbin/sysctl : parametres du noyau (/proc/sys) : sysctl [-a] [-w] nom[=valeur].
}

Program SYSCTL;

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
  SysPut(2, 'sysctl: ' + What + ': ' + SysErrorText(SysErrno) + #10);
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
  I, K, Fd, Rc : LongInt;
  A, P, V, L : String;
  W : Boolean;

Function PathOf(Const Name : String) : String;
Var S : String; K : LongInt;
Begin
  S := '/proc/sys/';
  For K := 1 To Length(Name) Do
    If Name[K] = '.' Then S := S + '/' Else S := S + Name[K];
  PathOf := S;
End;

Procedure Walk(Dir, Pfx : String);
Var D, Ino, Fd : LongInt; Nm, V : String; St : TSysStat;
Begin
  D := SysOpenDir(Dir);
  If D < 0 Then Exit;
  While SysReadDir(D, Nm, Ino) Do
    If (Nm <> '.') And (Nm <> '..') Then
    Begin
      If (SysStat(Dir + '/' + Nm, St) = 0) And ((St.Mode And $F000) = $4000) Then
        Walk(Dir + '/' + Nm, Pfx + Nm + '.')
      Else
      Begin
        Fd := SysOpen(Dir + '/' + Nm, O_RDONLY, 0);
        If Fd >= 0 Then
        Begin
          If Not SysReadLine(Fd, V) Then V := '';
          SysPut(1, Pfx + Nm + ' = ' + V + #10);
          SysClose(Fd);
        End;
      End;
    End;
  SysCloseDir(D);
End;

BEGIN
  W := False;
  Rc := 0;
  If SysArgCount < 2 Then Usage('sysctl [-a] [-w] name[=value]...');
  For I := 1 To SysArgCount - 1 Do
  Begin
    A := SysArgStr(I);
    If A = '-a' Then Walk('/proc/sys', '')
    Else If A = '-w' Then W := True
    Else
    Begin
      K := Pos('=', A);
      If K > 0 Then
      Begin
        P := PathOf(Copy(A, 1, K - 1));
        V := Copy(A, K + 1, 255);
        Fd := SysOpen(P, O_WRONLY, 0);
        If Fd < 0 Then
        Begin
          Warn(Copy(A, 1, K - 1));
          Rc := 1;
        End
        Else
        Begin
          V := V + #10;
          SysWrite(Fd, V[1], Length(V));
          SysClose(Fd);
          SysPut(1, Copy(A, 1, K - 1) + ' = ' + Copy(A, K + 1, 255) + #10);
        End;
      End
      Else
      Begin
        Fd := SysOpen(PathOf(A), O_RDONLY, 0);
        If Fd < 0 Then
        Begin
          Warn(A);
          Rc := 1;
        End
        Else
        Begin
          If Not SysReadLine(Fd, L) Then L := '';
          SysPut(1, A + ' = ' + L + #10);
          SysClose(Fd);
        End;
      End;
    End;
  End;
  SysExit(Rc);
END.
