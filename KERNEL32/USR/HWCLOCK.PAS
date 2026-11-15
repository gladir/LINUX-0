{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2026
  @website(https://www.gladir.com/linux-0)
  @abstract(Target: LPC -3X)
  @description: /sbin/hwclock : horloge materielle (/dev/rtc) : hwclock [-r] [-s] [-w] [--utc].
}

Program HWCLOCK;

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
  SysPut(2, 'hwclock: ' + What + ': ' + SysErrorText(SysErrno) + #10);
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
  Fd, Mode, I : LongInt;
  A : String;
  T : Array[0..8] Of LongInt;
  Y, Mo, D, H, Mi, S, Secs : LongInt;

Function Two(V : LongInt) : String;
Begin
  If V < 10 Then Two := '0' + NumS(V) Else Two := NumS(V);
End;

BEGIN
  Mode := 0;
  For I := 1 To SysArgCount - 1 Do
  Begin
    A := SysArgStr(I);
    If (A = '-s') Or (A = '--hctosys') Then Mode := 1
    Else If (A = '-w') Or (A = '--systohc') Then Mode := 2
    Else If (A = '-r') Or (A = '--show') Then Mode := 0;
  End;
  Fd := SysOpen('/dev/rtc', O_RDWR, 0);
  If Fd < 0 Then Fd := SysOpen('/dev/rtc0', O_RDWR, 0);
  If Fd < 0 Then
  Begin
    Warn('/dev/rtc');
    SysExit(1);
  End;
  If Mode = 2 Then
  Begin
    { struct rtc_time : sec min hour mday mon year wday yday isdst }
    Secs := SysTime;
    LnxCivil(Secs Div 86400, Y, Mo, D);
    T[0] := Secs Mod 60;
    T[1] := (Secs Mod 3600) Div 60;
    T[2] := (Secs Mod 86400) Div 3600;
    T[3] := D;
    T[4] := Mo - 1;
    T[5] := Y - 1900;
    T[6] := 0;
    T[7] := 0;
    T[8] := 0;
    If SysIoctl(Fd, $4024700A, T) < 0 Then
    Begin
      Warn('RTC_SET_TIME');
      SysExit(1);
    End;
    SysExit(0);
  End;
  If SysIoctl(Fd, $80247009, T) < 0 Then
  Begin
    Warn('RTC_RD_TIME');
    SysExit(1);
  End;
  Y := T[5] + 1900;
  Mo := T[4] + 1;
  If Mode = 1 Then
  Begin
    Secs := LnxDaysFromCivil(Y, Mo, T[3]) * 86400 + T[2] * 3600 + T[1] * 60 + T[0];
    LnxTmp[0] := Secs;
    LnxTmp[1] := 0;
    If LnxSys3(79, LongInt(@LnxTmp), 0, 0) < 0 Then
    Begin
      Warn('settimeofday');
      SysExit(1);
    End;
    SysExit(0);
  End;
  SysPut(1, NumS(Y) + '-' + Two(Mo) + '-' + Two(T[3]) + ' ' + Two(T[2]) + ':' +
    Two(T[1]) + ':' + Two(T[0]) + #10);
END.
