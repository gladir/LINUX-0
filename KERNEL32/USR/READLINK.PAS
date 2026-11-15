{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2026
  @website(https://www.gladir.com/linux-0)
  @abstract(Target: LPC -3X)
  @description: /bin/readlink,
      /bin/realpath : affiche la cible d un lien ; -f (et realpath) : chemin
      absolu canonique.
}

Program READLINK;

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
  SysPut(2, 'readlink: ' + What + ': ' + SysErrorText(SysErrno) + #10);
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
  Full : Boolean;
  I, Rc : LongInt;
  A, Cwd, R : String;

{ chemin canonique : suit les liens, enleve . et .. }
Function Canon(P : String) : String;
Var Res, Part, L : String; K, Hops, Code : LongInt; St : TSysStat;
Begin
  If (P = '') Then P := '.';
  If P[1] <> '/' Then P := Cwd + '/' + P;
  Res := '';
  Hops := 0;
  While P <> '' Do
  Begin
    While (P <> '') And (P[1] = '/') Do P := Copy(P, 2, 255);
    If P = '' Then Break;
    K := Pos('/', P);
    If K = 0 Then
    Begin
      Part := P;
      P := '';
    End
    Else
    Begin
      Part := Copy(P, 1, K - 1);
      P := Copy(P, K + 1, 255);
    End;
    If Part = '.' Then
    Begin
    End
    Else If Part = '..' Then
    Begin
      K := Length(Res);
      While (K > 0) And (Res[K] <> '/') Do Dec(K);
      Res := Copy(Res, 1, K - 1);
    End
    Else
    Begin
      Res := Res + '/' + Part;
      If (SysLStat(Res, St) = 0) And ((St.Mode And $F000) = $A000) And
         (Hops < 40) Then
      Begin
        Inc(Hops);
        L := SysReadlink(Res);
        K := Length(Res);
        While (K > 0) And (Res[K] <> '/') Do Dec(K);
        Res := Copy(Res, 1, K - 1);
        If (L <> '') And (L[1] = '/') Then
        Begin
          Res := '';
          P := L + '/' + P;
        End
        Else P := L + '/' + P;
      End;
    End;
  End;
  If Res = '' Then Res := '/';
  Canon := Res;
End;

BEGIN
  Full := Pos('realpath', SysArgStr(0)) > 0;
  Rc := 0;
  Cwd := SysGetCwd;
  For I := 1 To SysArgCount - 1 Do
  Begin
    A := SysArgStr(I);
    If (A = '-f') Or (A = '-e') Or (A = '-m') Or (A = '-n') Then
    Begin
      If A = '-f' Then Full := True;
    End
    Else If Full Then SysPut(1, Canon(A) + #10)
    Else
    Begin
      R := SysReadlink(A);
      If R = '' Then Rc := 1 Else SysPut(1, R + #10);
    End;
  End;
  If SysArgCount < 2 Then Usage('readlink [-f] file...  |  realpath file...');
  SysExit(Rc);
END.
