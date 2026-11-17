{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2026
  @website(https://www.gladir.com/linux-0)
  @abstract(Target: LPC -3X)
  @description: /bin/uptime : heure,
      duree de fonctionnement et charge (/proc/uptime, /proc/loadavg).
}

Program UPTIME;

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
  SysPut(2, 'uptime: ' + What + ': ' + SysErrorText(SysErrno) + #10);
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
  Fd, N, Up, Days, H, M, T : LongInt;
  L, Ld, Cur, S : String;

Function Two(V : LongInt) : String;
Begin
  If V < 10 Then Two := '0' + NumS(V) Else Two := NumS(V);
End;

BEGIN
  Up := 0;
  Ld := '';
  Fd := SysOpen('/proc/uptime', O_RDONLY, 0);
  If Fd >= 0 Then
  Begin
    If SysReadLine(Fd, L) Then Val(Copy(L, 1, Pos('.', L + '.') - 1), Up, N);
    SysClose(Fd);
  End;
  Fd := SysOpen('/proc/loadavg', O_RDONLY, 0);
  If Fd >= 0 Then
  Begin
    If SysReadLine(Fd, L) Then
    Begin
      N := Pos(' ', L);
      Ld := Copy(L, 1, N - 1);
      L := Copy(L, N + 1, 255);
      N := Pos(' ', L);
      Ld := Ld + ', ' + Copy(L, 1, N - 1);
      L := Copy(L, N + 1, 255);
      N := Pos(' ', L);
      Ld := Ld + ', ' + Copy(L, 1, N - 1);
    End;
    SysClose(Fd);
  End;
  T := (SysTime + LnxTz) Mod 86400;
  Cur := Two(T Div 3600) + ':' + Two((T Mod 3600) Div 60) + ':' + Two(T Mod 60);
  Days := Up Div 86400;
  H := (Up Mod 86400) Div 3600;
  M := (Up Mod 3600) Div 60;
  S := ' ' + Cur + ' up ';
  If Days > 0 Then S := S + NumS(Days) + ' day(s), ';
  S := S + NumS(H) + ':' + Two(M) + ',  load average: ' + Ld;
  SysPut(1, S + #10);
END.
