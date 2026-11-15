{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2026
  @website(https://www.gladir.com/linux-0)
  @abstract(Target: LPC -3X)
  @description: /bin/xargs : construit des lignes de commande a partir de l
      entree standard (xargs [-n N] [-0] [-t] [-I repl] [commande [args]]).
}

Program XARGS;

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
  SysPut(2, 'xargs: ' + What + ': ' + SysErrorText(SysErrno) + #10);
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
  Cmd : Array[1..40] Of String;
  NCmd, MaxN, Cnt, Rc : LongInt;
  Items : Array[1..200] Of String;
  Zero, Trace : Boolean;
  Repl : String;


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

Procedure Run;
Var K, Pid, St, I : LongInt; A : String;
Begin
  If (Cnt = 0) And (Repl = '') Then Exit;
  If Trace Then
  Begin
    A := '';
    For K := 1 To NCmd Do A := A + Cmd[K] + ' ';
    For K := 1 To Cnt Do A := A + Items[K] + ' ';
    SysPut(2, A + #10);
  End;
  Pid := SysFork;
  If Pid = 0 Then
  Begin
    SysArgReset;
    For K := 1 To NCmd Do
      If (Repl <> '') And (Pos(Repl, Cmd[K]) > 0) And (Cnt > 0) Then
      Begin
        A := Cmd[K];
        I := Pos(Repl, A);
        While I > 0 Do
        Begin
          A := Copy(A, 1, I - 1) + Items[1] + Copy(A, I + Length(Repl), 255);
          I := Pos(Repl, A);
        End;
        SysArgAdd(A);
      End
      Else SysArgAdd(Cmd[K]);
    If Repl = '' Then
      For K := 1 To Cnt Do SysArgAdd(Items[K]);
    SysEnvInherit;
    A := FindExe(Cmd[1]);
    SysArgExec(A);
    SysExit(127);
  End;
  SysWaitPid(Pid, St, 0);
  If (SysWIfExited(St)) And (SysWExitStatus(St) <> 0) Then Rc := 123;
  Cnt := 0;
End;

Var
  I, N, K : LongInt;
  A, Cur : String;
  C : Char;
  Q : Char;
  Have : Boolean;

BEGIN
  NCmd := 0;
  MaxN := 200;
  Zero := False;
  Trace := False;
  Repl := '';
  Rc := 0;
  I := 1;
  While I < SysArgCount Do
  Begin
    A := SysArgStr(I);
    If (A = '-n') And (I + 1 < SysArgCount) Then
    Begin
      Inc(I);
      Val(SysArgStr(I), MaxN, K);
    End
    Else If (Copy(A, 1, 2) = '-n') And (Length(A) > 2) Then
      Val(Copy(A, 3, 10), MaxN, K)
    Else If A = '-0' Then Zero := True
    Else If A = '-t' Then Trace := True
    Else If (A = '-I') And (I + 1 < SysArgCount) Then
    Begin
      Inc(I);
      Repl := SysArgStr(I);
      MaxN := 1;
    End
    Else
    Begin
      While I < SysArgCount Do
      Begin
        If NCmd < 40 Then
        Begin
          Inc(NCmd);
          Cmd[NCmd] := SysArgStr(I);
        End;
        Inc(I);
      End;
      Break;
    End;
    Inc(I);
  End;
  If NCmd = 0 Then
  Begin
    NCmd := 1;
    Cmd[1] := 'echo';
  End;
  If MaxN > 200 Then MaxN := 200;
  Cnt := 0;
  Cur := '';
  Have := False;
  Q := #0;
  While SysRead(0, C, 1) = 1 Do
  Begin
    If Zero Then
    Begin
      If C = #0 Then
      Begin
        Inc(Cnt);
        Items[Cnt] := Cur;
        Cur := '';
        If Cnt >= MaxN Then Run;
      End
      Else If Length(Cur) < 255 Then Cur := Cur + C;
    End
    Else If Q <> #0 Then
    Begin
      If C = Q Then Q := #0
      Else If Length(Cur) < 255 Then Cur := Cur + C;
    End
    Else If (C = '"') Or (C = #39) Then
    Begin
      Q := C;
      Have := True;
    End
    Else If (C = ' ') Or (C = #9) Or (C = #10) Then
    Begin
      If (Cur <> '') Or Have Then
      Begin
        Inc(Cnt);
        Items[Cnt] := Cur;
        Cur := '';
        Have := False;
        If Cnt >= MaxN Then Run;
      End;
    End
    Else If Length(Cur) < 255 Then Cur := Cur + C;
  End;
  If (Cur <> '') Or Have Then
  Begin
    Inc(Cnt);
    Items[Cnt] := Cur;
  End;
  If Cnt > 0 Then Run;
  SysExit(Rc);
END.
