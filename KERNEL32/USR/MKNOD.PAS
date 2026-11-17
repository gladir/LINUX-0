{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2026
  @website(https://www.gladir.com/linux-0)
  @abstract(Target: LPC -3X)
  @description: /bin/mknod : cree un fichier special (mknod [-m mode] nom
      b|c|p [majeur mineur]).
}

Program MKNOD;

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
  SysPut(2, 'mknod: ' + What + ': ' + SysErrorText(SysErrno) + #10);
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
  Mode, Dev, Maj, Min, Code, I, N : LongInt;
  Typ, A : String;
  Arg : Array[1..8] Of String;

BEGIN
  Mode := 438;
  N := 0;
  I := 1;
  While I < SysArgCount Do
  Begin
    A := SysArgStr(I);
    If (A = '-m') And (I + 1 < SysArgCount) Then
    Begin
      Inc(I);
      Mode := 0;
      A := SysArgStr(I);
      For Code := 1 To Length(A) Do Mode := Mode * 8 + Ord(A[Code]) - 48;
    End
    Else If N < 8 Then
    Begin
      Inc(N);
      Arg[N] := A;
    End;
    Inc(I);
  End;
  If N < 2 Then Usage('mknod [-m mode] name b|c|p [major minor]');
  Typ := Arg[2];
  Dev := 0;
  If Typ <> 'p' Then
  Begin
    If N < 4 Then Usage('mknod [-m mode] name b|c|p [major minor]');
    Val(Arg[3], Maj, Code);
    Val(Arg[4], Min, Code);
    Dev := (Maj Shl 8) Or Min;
  End;
  If Typ = 'b' Then Mode := Mode Or $6000
  Else If Typ = 'c' Then Mode := Mode Or $2000
  Else If Typ = 'p' Then Mode := Mode Or $1000
  Else Usage('mknod [-m mode] name b|c|p [major minor]');
  If SysMknod(Arg[1], Mode, Dev) < 0 Then
  Begin
    Warn(Arg[1]);
    SysExit(1);
  End;
END.
