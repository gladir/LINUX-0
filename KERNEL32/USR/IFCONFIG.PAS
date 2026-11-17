{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2026
  @website(https://www.gladir.com/linux-0)
  @abstract(Target: LPC -3X)
  @description: /sbin/ifconfig : interfaces reseau (ifconfig [-a] [iface
      [adresse] [netmask m] [up|down] [mtu n]]),
      par ioctl SIOCGIF*/SIOCSIF* et /proc/net/dev.
}

Program IFCONFIG;

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
  SysPut(2, 'ifconfig: ' + What + ': ' + SysErrorText(SysErrno) + #10);
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

Const
  SIOCGIFFLAGS = $8913; SIOCSIFFLAGS = $8914; SIOCGIFADDR = $8915;
  SIOCSIFADDR = $8916; SIOCGIFNETMASK = $891B; SIOCSIFNETMASK = $891C;
  SIOCGIFMTU = $8921; SIOCSIFMTU = $8922; SIOCGIFHWADDR = $8927;
  SIOCGIFBRDADDR = $8919;

Type
  TIfReq = Record
    Name : Array[0..15] Of Byte;
    Data : Array[0..23] Of Byte;
  End;

Var
  Sk : LongInt;

Procedure SetName(Var R : TIfReq; Const N : String);
Var K : LongInt;
Begin
  FillChar(R, SizeOf(R), 0);
  For K := 1 To Length(N) Do
    If K <= 15 Then R.Name[K - 1] := Ord(N[K]);
End;

Function GetIp(Req : LongInt; Var R : TIfReq; Var Ip : LongInt) : Boolean;
Begin
  GetIp := False;
  Ip := 0;
  If SysIoctl(Sk, Req, R) < 0 Then Exit;
  Ip := R.Data[4] Or (R.Data[5] Shl 8) Or (R.Data[6] Shl 16) Or
        (R.Data[7] Shl 24);
  GetIp := True;
End;

Procedure PutIp(Var R : TIfReq; Ip : LongInt);
Var K : LongInt;
Begin
  For K := 0 To 23 Do R.Data[K] := 0;
  R.Data[0] := 2;
  R.Data[4] := Ip And 255;
  R.Data[5] := (Ip Shr 8) And 255;
  R.Data[6] := (Ip Shr 16) And 255;
  R.Data[7] := (Ip Shr 24) And 255;
End;

Function Hex2(V : LongInt) : String;
Const H = '0123456789abcdef';
Begin
  Hex2 := H[(V Shr 4) And 15 + 1] + H[V And 15 + 1];
End;

Procedure Show(Const N : String);
Var R : TIfReq; Ip, Fl, Mtu, K : LongInt; S,
  T : String; L : String; Fd : LongInt;
    Rx, Tx : String;
Begin
  SetName(R, N);
  If SysIoctl(Sk, SIOCGIFFLAGS, R) < 0 Then
  Begin
    SysPut(2, 'ifconfig: ' + N + ': ' + SysErrorText(SysErrno) + #10);
    Exit;
  End;
  Fl := R.Data[0] Or (R.Data[1] Shl 8);
  S := N + '      Link encap:';
  If (Fl And 8) <> 0 Then S := S + 'Local Loopback' Else S := S + 'Ethernet';
  SetName(R, N);
  If (SysIoctl(Sk, SIOCGIFHWADDR, R) = 0) And ((Fl And 8) = 0) Then
  Begin
    S := S + '  HWaddr ';
    For K := 0 To 5 Do
    Begin
      If K > 0 Then S := S + ':';
      S := S + Hex2(R.Data[2 + K]);
    End;
  End;
  SysPut(1, S + #10);
  SetName(R, N);
  If GetIp(SIOCGIFADDR, R, Ip) Then
  Begin
    S := '          inet addr:' + SysIpStr(Ip);
    SetName(R, N);
    If GetIp(SIOCGIFBRDADDR, R, Ip) And (Ip <> 0) And ((Fl And 8) = 0) Then
      S := S + '  Bcast:' + SysIpStr(Ip);
    SetName(R, N);
    If GetIp(SIOCGIFNETMASK, R, Ip) Then S := S + '  Mask:' + SysIpStr(Ip);
    SysPut(1, S + #10);
  End;
  S := '          ';
  If (Fl And 1) <> 0 Then S := S + 'UP ';
  If (Fl And 2) <> 0 Then S := S + 'BROADCAST ';
  If (Fl And 8) <> 0 Then S := S + 'LOOPBACK ';
  If (Fl And $40) <> 0 Then S := S + 'RUNNING ';
  If (Fl And $1000) <> 0 Then S := S + 'MULTICAST ';
  SetName(R, N);
  Mtu := 0;
  If SysIoctl(Sk, SIOCGIFMTU, R) = 0 Then
    Mtu := R.Data[0] Or (R.Data[1] Shl 8) Or (R.Data[2] Shl 16);
  Str(Mtu, T);
  SysPut(1, S + ' MTU:' + T + #10);
  { compteurs : /proc/net/dev }
  Fd := SysOpen('/proc/net/dev', O_RDONLY, 0);
  If Fd >= 0 Then
  Begin
    While SysReadLine(Fd, L) Do
    Begin
      While (L <> '') And (L[1] = ' ') Do L := Copy(L, 2, 255);
      If Copy(L, 1, Length(N) + 1) = N + ':' Then
      Begin
        L := Copy(L, Length(N) + 2, 255);
        K := 0;
        Rx := '';
        Tx := '';
        While (L <> '') And (K < 10) Do
        Begin
          While (L <> '') And (L[1] = ' ') Do L := Copy(L, 2, 255);
          T := '';
          While (L <> '') And (L[1] <> ' ') Do
          Begin
            T := T + L[1];
            L := Copy(L, 2, 255);
          End;
          If K = 0 Then Rx := 'RX bytes:' + T;
          If K = 1 Then Rx := 'RX packets:' + T + '  ' + Rx;
          If K = 8 Then Tx := 'TX bytes:' + T;
          If K = 9 Then Tx := 'TX packets:' + T + '  ' + Tx;
          Inc(K);
        End;
        SysPut(1, '          ' + Rx + #10 + '          ' + Tx + #10);
      End;
    End;
    SysClose(Fd);
  End;
  SysPut(1, #10);
End;

Procedure ShowAll(OnlyUp : Boolean);
Var Fd : LongInt; L, N : String; K : LongInt;
Begin
  Fd := SysOpen('/proc/net/dev', O_RDONLY, 0);
  If Fd < 0 Then
  Begin
    Show('lo');
    Exit;
  End;
  While SysReadLine(Fd, L) Do
  Begin
    K := Pos(':', L);
    If K > 0 Then
    Begin
      N := Copy(L, 1, K - 1);
      While (N <> '') And (N[1] = ' ') Do N := Copy(N, 2, 255);
      Show(N);
    End;
  End;
  SysClose(Fd);
End;

Var
  I, Ip, Fl, V, Code : LongInt;
  A, N : String;
  R : TIfReq;

BEGIN
  Sk := SysSocket(2, 2, 0);
  If Sk < 0 Then
  Begin
    Warn('socket');
    SysExit(1);
  End;
  If (SysArgCount < 2) Or (SysArgStr(1) = '-a') Then
  Begin
    ShowAll(False);
    SysExit(0);
  End;
  N := SysArgStr(1);
  If SysArgCount = 2 Then
  Begin
    Show(N);
    SysExit(0);
  End;
  I := 2;
  While I < SysArgCount Do
  Begin
    A := SysArgStr(I);
    If A = 'up' Then
    Begin
      SetName(R, N);
      SysIoctl(Sk, SIOCGIFFLAGS, R);
      Fl := R.Data[0] Or (R.Data[1] Shl 8);
      Fl := Fl Or 1 Or $40;
      R.Data[0] := Fl And 255;
      R.Data[1] := Fl Shr 8;
      If SysIoctl(Sk, SIOCSIFFLAGS, R) < 0 Then Warn(N);
    End
    Else If A = 'down' Then
    Begin
      SetName(R, N);
      SysIoctl(Sk, SIOCGIFFLAGS, R);
      Fl := (R.Data[0] Or (R.Data[1] Shl 8)) And Not 1;
      R.Data[0] := Fl And 255;
      R.Data[1] := Fl Shr 8;
      If SysIoctl(Sk, SIOCSIFFLAGS, R) < 0 Then Warn(N);
    End
    Else If (A = 'netmask') And (I + 1 < SysArgCount) Then
    Begin
      Inc(I);
      If Not SysParseIp(SysArgStr(I),
        Ip) Then Usage('ifconfig iface [addr] [netmask mask] [up|down]');
      SetName(R, N);
      PutIp(R, Ip);
      If SysIoctl(Sk, SIOCSIFNETMASK, R) < 0 Then Warn(N);
    End
    Else If (A = 'mtu') And (I + 1 < SysArgCount) Then
    Begin
      Inc(I);
      Val(SysArgStr(I), V, Code);
      SetName(R, N);
      R.Data[0] := V And 255;
      R.Data[1] := (V Shr 8) And 255;
      If SysIoctl(Sk, SIOCSIFMTU, R) < 0 Then Warn(N);
    End
    Else If SysParseIp(A, Ip) Then
    Begin
      SetName(R, N);
      PutIp(R, Ip);
      If SysIoctl(Sk, SIOCSIFADDR, R) < 0 Then Warn(N);
    End
    Else Usage('ifconfig [-a] [iface [addr] [netmask mask] [mtu n] [up|down]]');
    Inc(I);
  End;
END.
