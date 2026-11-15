{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2026
  @website(https://www.gladir.com/linux-0)
  @abstract(Target: LPC -3X)
  @description: /bin/shuf : melange les lignes (shuf [-n N] [-r] [-z]
      [-o fichier] [fichier] ; shuf -e arg... ; shuf -i LO-HI).
}

Program SHUF;

Const
  UsageW : Array[1..5] Of PChar =
    ('Usage : ', 'Usage: ', 'Aufruf: ', 'Uso: ', 'Uso: ');
  MaxN = 20000;

Var
  Items : Array[1..MaxN] Of String;
  N, Seed : LongInt;

Function PS(Q : PChar) : String;
Var X : String;
Begin
  X := '';
  While Q^ <> #0 Do
  Begin
    X := X + Q^;
    Inc(Q);
  End;
  PS := X;
End;

Function NumS(V : LongInt) : String;
Var S : String;
Begin
  Str(V, S);
  NumS := S;
End;

Function Rnd(M : LongInt) : LongInt;
Begin
  Seed := (Seed * 1103515245 + 12345) And $7FFFFFFF;
  Rnd := (Seed Shr 4) Mod M;
End;

Procedure Add(Const S : String);
Begin
  If N >= MaxN Then
  Begin
    SysPut(2, 'shuf: trop de lignes' + #10);
    SysExit(1);
  End;
  Inc(N);
  Items[N] := S;
End;

Var
  I, J, K, Cnt, Fd, Lo, Hi, E, Out : LongInt;
  A, F, OutFile : String;
  Rep, Echo, Range : Boolean;
  Tmp : String;
Begin
  Seed := SysTime * 7 + SysGetPid;
  Cnt := -1;
  Rep := False;
  Echo := False;
  Range := False;
  F := '';
  OutFile := '';
  N := 0;
  I := 1;
  While I < SysArgCount Do
  Begin
    A := SysArgStr(I);
    If (A = '-n') Or (A = '--head-count') Then
    Begin
      Inc(I);
      Val(SysArgStr(I), Cnt, E);
    End
    Else If A = '-r' Then Rep := True
    Else If A = '-e' Then Echo := True
    Else If A = '-z' Then
    Else If A = '-o' Then
    Begin
      Inc(I);
      OutFile := SysArgStr(I);
    End
    Else If A = '-i' Then
    Begin
      Inc(I);
      A := SysArgStr(I);
      K := Pos('-', A);
      Val(Copy(A, 1, K - 1), Lo, E);
      Val(Copy(A, K + 1, 20), Hi, E);
      Range := True;
    End
    Else If Echo Then Add(A)
    Else F := A;
    Inc(I);
  End;
  If Range Then
    For J := Lo To Hi Do Add(NumS(J))
  Else If Not Echo Then
  Begin
    If (F = '') Or (F = '-') Then Fd := 0 Else Fd := SysOpen(F, 0, 0);
    If Fd < 0 Then
    Begin
      SysPut(2, 'shuf: ' + F + ': ' + SysErrorText(SysErrno) + #10);
      SysExit(1);
    End;
    While SysReadLine(Fd, A) Do Add(A);
  End;
  Out := 1;
  If OutFile <> '' Then Out := SysOpen(OutFile, $241, 420);
  If Rep Then
  Begin
    If (N = 0) Then SysExit(1);
    If Cnt < 0 Then Cnt := 1000000;
    For J := 1 To Cnt Do SysPut(Out, Items[Rnd(N) + 1] + #10);
    SysExit(0);
  End;
  For J := N DownTo 2 Do
  Begin
    K := Rnd(J) + 1;
    Tmp := Items[J];
    Items[J] := Items[K];
    Items[K] := Tmp;
  End;
  If (Cnt < 0) Or (Cnt > N) Then Cnt := N;
  For J := 1 To Cnt Do SysPut(Out, Items[J] + #10);
End.
