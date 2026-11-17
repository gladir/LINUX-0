{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2026
  @website(https://www.gladir.com/linux-0)
  @abstract(Target: LPC -3X)
  @description: /sbin/route : table de routage IPv4 (route [-n] :
      /proc/net/route).
}

Program ROUTE;

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
  SysPut(2, 'route: ' + What + ': ' + SysErrorText(SysErrno) + #10);
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
  Fd, K, N, Code, Fl : LongInt;
  L, F, Dst, Gw, Msk, Dev, Fs : String;
  Fields : Array[1..12] Of String;

Function HexIp(Const H : String) : String;
Var V, K, D : LongInt; C : Char;
Begin
  V := 0;
  For K := 1 To Length(H) Do
  Begin
    C := H[K];
    If (C >= '0') And (C <= '9') Then D := Ord(C) - 48
    Else If (C >= 'A') And (C <= 'F') Then D := Ord(C) - 55
    Else D := Ord(C) - 87;
    V := V * 16 + D;
  End;
  HexIp := SysIpStr(V);
End;

BEGIN
  Fd := SysOpen('/proc/net/route', O_RDONLY, 0);
  If Fd < 0 Then
  Begin
    Warn('/proc/net/route');
    SysExit(1);
  End;
  SysPut(1, 'Kernel IP routing table' + #10);
  SysPut(1, 'Destination     Gateway         Genmask         Flags Iface' +
    #10);
  SysReadLine(Fd, L);
  While SysReadLine(Fd, L) Do
  Begin
    N := 0;
    While (L <> '') And (N < 12) Do
    Begin
      While (L <> '') And ((L[1] = ' ') Or (L[1] = #9)) Do L := Copy(L, 2, 255);
      F := '';
      While (L <> '') And (L[1] <> ' ') And (L[1] <> #9) Do
      Begin
        F := F + L[1];
        L := Copy(L, 2, 255);
      End;
      Inc(N);
      Fields[N] := F;
    End;
    If N >= 8 Then
    Begin
      Dst := HexIp(Fields[2]);
      Gw := HexIp(Fields[3]);
      Msk := HexIp(Fields[8]);
      Val(Fields[4], Fl, Code);
      Fs := '';
      If (Fl And 1) <> 0 Then Fs := Fs + 'U';
      If (Fl And 2) <> 0 Then Fs := Fs + 'G';
      While Length(Dst) < 16 Do Dst := Dst + ' ';
      While Length(Gw) < 16 Do Gw := Gw + ' ';
      While Length(Msk) < 16 Do Msk := Msk + ' ';
      While Length(Fs) < 6 Do Fs := Fs + ' ';
      SysPut(1, Dst + Gw + Msk + Fs + Fields[1] + #10);
    End;
  End;
  SysClose(Fd);
END.
