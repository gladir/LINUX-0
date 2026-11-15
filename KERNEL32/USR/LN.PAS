{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2026
  @website(https://www.gladir.com/linux-0)
  @abstract(Target: LPC -3X)
  @description: /bin/ln : cree des liens (ln [-sf] cible [lien] ; ln [-sf] cible... repertoire).
}

Program LN;

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
  SysPut(2, 'ln: ' + What + ': ' + SysErrorText(SysErrno) + #10);
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
  Arg : Array[1..100] Of String;
  Sym, Force : Boolean;
  I, K, N, Rc, R : LongInt;
  A, Dst : String;

Procedure MakeLink(Const Src, Dst : String);
Var R : LongInt;
Begin
  If Force Then SysUnlink(Dst);
  If Sym Then R := SysSymlink(Src, Dst) Else R := SysLink(Src, Dst);
  If R < 0 Then
  Begin
    Warn(Dst);
    Rc := 1;
  End;
End;

BEGIN
  Sym := False;
  Force := False;
  N := 0;
  Rc := 0;
  For I := 1 To SysArgCount - 1 Do
  Begin
    A := SysArgStr(I);
    If (Length(A) > 1) And (A[1] = '-') And (N = 0) Then
    Begin
      For K := 2 To Length(A) Do
        If A[K] = 's' Then Sym := True
        Else If A[K] = 'f' Then Force := True
        Else Usage('ln [-sf] target [link] | ln [-sf] target... directory');
    End
    Else If N < 100 Then
    Begin
      Inc(N);
      Arg[N] := A;
    End;
  End;
  If N = 0 Then Usage('ln [-sf] target [link] | ln [-sf] target... directory');
  If N = 1 Then MakeLink(Arg[1], BaseOf(Arg[1]))
  Else If (N = 2) And (Not IsDir(Arg[2])) Then MakeLink(Arg[1], Arg[2])
  Else
    For I := 1 To N - 1 Do
    Begin
      If Arg[N][Length(Arg[N])] = '/' Then Dst := Arg[N] + BaseOf(Arg[I])
      Else Dst := Arg[N] + '/' + BaseOf(Arg[I]);
      MakeLink(Arg[I], Dst);
    End;
  SysExit(Rc);
END.
