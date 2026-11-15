{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2026
  @website(https://www.gladir.com/linux-0)
  @abstract(Target: LPC -3X)
  @description: /bin/free : memoire libre et utilisee (/proc/meminfo) ; -m en
      Mo, -b en octets.
}

Program FREE;

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
  SysPut(2, 'free: ' + What + ': ' + SysErrorText(SysErrno) + #10);
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
  Unit1, Div1 : LongInt;
  Tot, Fre, Buf, Cac, SwT, SwF, K, Code, Fd : LongInt;
  L, Key, Sv : String;
  A : String;

Function Cell(V : LongInt) : String;
Var S : String;
Begin
  S := NumS(V Div Div1);
  While Length(S) < 11 Do S := ' ' + S;
  Cell := S;
End;

BEGIN
  Div1 := 1;
  If SysArgCount > 1 Then
  Begin
    A := SysArgStr(1);
    If A = '-m' Then Div1 := 1024
    Else If A = '-b' Then Div1 := 0;
  End;
  Tot := 0; Fre := 0; Buf := 0; Cac := 0; SwT := 0; SwF := 0;
  Fd := SysOpen('/proc/meminfo', O_RDONLY, 0);
  If Fd < 0 Then
  Begin
    Warn('/proc/meminfo');
    SysExit(1);
  End;
  While SysReadLine(Fd, L) Do
  Begin
    K := Pos(':', L);
    If K > 0 Then
    Begin
      Key := Copy(L, 1, K - 1);
      Sv := Copy(L, K + 1, 255);
      While (Sv <> '') And (Sv[1] = ' ') Do Sv := Copy(Sv, 2, 255);
      K := Pos(' ', Sv + ' ');
      Val(Copy(Sv, 1, K - 1), Code, K);
      If Key = 'MemTotal' Then Tot := Code
      Else If Key = 'MemFree' Then Fre := Code
      Else If Key = 'Buffers' Then Buf := Code
      Else If Key = 'Cached' Then Cac := Code
      Else If Key = 'SwapTotal' Then SwT := Code
      Else If Key = 'SwapFree' Then SwF := Code;
    End;
  End;
  SysClose(Fd);
  If Div1 = 0 Then
  Begin
    Div1 := 1;
    Tot := Tot * 1024; Fre := Fre * 1024; Buf := Buf * 1024;
    Cac := Cac * 1024; SwT := SwT * 1024; SwF := SwF * 1024;
  End;
  SysPut(1, '              total        used        free      buffers' +
    '      cached' + #10);
  SysPut(1, 'Mem:     ' + Cell(Tot) + Cell(Tot - Fre) + Cell(Fre) + Cell(Buf) +
    Cell(Cac) + #10);
  SysPut(1, 'Swap:    ' + Cell(SwT) + Cell(SwT - SwF) + Cell(SwF) + #10);
END.
