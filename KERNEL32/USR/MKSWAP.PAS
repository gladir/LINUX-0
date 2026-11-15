{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2026
  @website(https://www.gladir.com/linux-0)
  @abstract(Target: LPC -3X)
  @description: /sbin/mkswap : prepare une zone d echange (fichier ou partition) : mkswap [-s Ko] [-L nom] peripherique (-s cree le fichier).
}

Program MKSWAP;

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
  SysPut(2, 'mkswap: ' + What + ': ' + SysErrorText(SysErrno) + #10);
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
  Fd, Size, Pages, I, Kb, Code : LongInt;
  A, Dev, Lab : String;
  B : Array[0..4095] Of Byte;
BEGIN
  Dev := '';
  Lab := '';
  Kb := 0;
  I := 1;
  While I < SysArgCount Do
  Begin
    A := SysArgStr(I);
    If (A = '-s') And (I + 1 < SysArgCount) Then
    Begin
      Inc(I);
      Val(SysArgStr(I), Kb, Code);
    End
    Else If (A = '-L') And (I + 1 < SysArgCount) Then
    Begin
      Inc(I);
      Lab := SysArgStr(I);
    End
    Else Dev := A;
    Inc(I);
  End;
  If Dev = '' Then Usage('mkswap [-s KiB] [-L label] device');
  Fd := SysOpen(Dev, O_RDWR Or O_CREAT, 384);
  If Fd < 0 Then
  Begin
    Warn(Dev);
    SysExit(1);
  End;
  If Kb > 0 Then SysTruncate(Dev, Kb * 1024);
  Size := SysLSeek(Fd, 0, SEEK_END);
  If Size <= 0 Then
  Begin
    If SysIoctl(Fd, $1260, Pages) = 0 Then Size := Pages * 512;
  End;
  Pages := Size Div 4096;
  If Pages < 10 Then
  Begin
    SysPut(2, 'mkswap: ' + Dev + ': too small' + #10);
    SysExit(1);
  End;
  FillChar(B, 4096, 0);
  B[$400] := 1;
  B[$404] := (Pages - 1) And 255;
  B[$405] := ((Pages - 1) Shr 8) And 255;
  B[$406] := ((Pages - 1) Shr 16) And 255;
  B[$407] := ((Pages - 1) Shr 24) And 255;
  For I := 1 To Length(Lab) Do
    If I <= 15 Then B[$41C + I - 1] := Ord(Lab[I]);
  Lab := 'SWAPSPACE2';
  For I := 1 To 10 Do B[4085 + I] := Ord(Lab[I]);
  SysLSeek(Fd, 0, SEEK_SET);
  SysWrite(Fd, B, 4096);
  SysSync;
  SysClose(Fd);
  SysPut(1, 'Setting up swapspace version 1, size = ' + NumS(Pages * 4) +
    ' KiB' + #10);
END.
