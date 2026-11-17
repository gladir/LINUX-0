{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2026
  @website(https://www.gladir.com/linux-0)
  @abstract(Target: LPC -3X)
  @description: /bin/ip : ip addr|link|route [show|add|del|set] ... Sans
      netlink : lecture par ioctl SIOCGIF* et /proc/net/route, modifications
      par /sbin/ifconfig et /sbin/route (memes ioctl). Formes admises :
      ip [-4] addr [show [dev X]] | addr add A/N dev X | addr del A/N dev X,
      ip link [show [X]] | link set [dev] X up|down [mtu N],
      ip route [show] | route add default via G [dev X] | route add R/N via G
      [dev X] | route del R/N, ip -s link (compteurs de /proc/net/dev).
}

Program IPTOOL;

Const
  SIOCGIFFLAGS = $8913; SIOCGIFADDR = $8915; SIOCGIFNETMASK = $891B;
  SIOCGIFMTU = $8921; SIOCGIFHWADDR = $8927; SIOCGIFBRDADDR = $8919;
  Usage : Array[1..5] Of PChar = (
    'Usage : ip [-4] [-s] (addr | link | route) [show | add | del | set] ...',
    'Usage: ip [-4] [-s] (addr | link | route) [show | add | del | set] ...',
    'Aufruf: ip [-4] [-s] (addr | link | route) [show | add | del | set] ...',
    'Uso: ip [-4] [-s] (addr | link | route) [show | add | del | set] ...',
    'Uso: ip [-4] [-s] (addr | link | route) [show | add | del | set] ...');

Type
  TIfReq = Record
    Name : Array[0..15] Of Byte;
    Data : Array[0..23] Of Byte;
  End;

Var
  Lang, Sk : LongInt;
  Stats : Boolean;
  A : Array[1..24] Of String;
  NA : LongInt;

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

Function ToNum(Const S : String) : LongInt;
Var V, C : LongInt;
Begin
  Val(S, V, C);
  If C <> 0 Then V := -1;
  ToNum := V;
End;

Procedure Fail(Const S : String);
Begin
  SysPut(2, 'ip: ' + S + #10);
  SysExit(1);
End;

Procedure SetName(Var R : TIfReq; Const N : String);
Var K : LongInt;
Begin
  FillChar(R, SizeOf(R), 0);
  For K := 1 To Length(N) Do
    If K <= 15 Then R.Name[K - 1] := Ord(N[K]);
End;

Function GetIp(Const N : String; Req : LongInt; Var Ip : LongInt) : Boolean;
Var R : TIfReq;
Begin
  SetName(R, N);
  GetIp := False;
  Ip := 0;
  If SysIoctl(Sk, Req, R) < 0 Then Exit;
  Ip := R.Data[4] Or (R.Data[5] Shl 8) Or (R.Data[6] Shl 16) Or
        (R.Data[7] Shl 24);
  GetIp := True;
End;

Function Hex2(V : LongInt) : String;
Const H = '0123456789abcdef';
Begin
  Hex2 := H[(V Shr 4) And 15 + 1] + H[V And 15 + 1];
End;

Function PrefixOf(Mask : LongInt) : LongInt;
Var K, N : LongInt;
Begin
  N := 0;
  For K := 0 To 31 Do
    If (Mask And (LongInt(1) Shl K)) <> 0 Then Inc(N);
  PrefixOf := N;
End;

Function MaskOf(N : LongInt) : String;
Var M, K : LongInt;
Begin
  M := 0;
  For K := 0 To N - 1 Do M := M Or (LongInt(1) Shl (K Mod 8 + 8 * (K Div 8)));
  MaskOf := SysIpStr(M);
End;

Function Names(Var L : Array Of String) : LongInt;
Var Fd, N, K : LongInt; B : Byte; Ln : String; Cnt : LongInt;
Begin
  Cnt := 0;
  Fd := SysOpen('/proc/net/dev', O_RDONLY, 0);
  If Fd >= 0 Then
  Begin
    Ln := '';
    K := 0;
    While True Do
    Begin
      N := SysRead(Fd, B, 1);
      If (N <= 0) Or (B = 10) Then
      Begin
        Inc(K);
        If (K > 2) And (Ln <> '') And (Cnt <= High(L)) Then
        Begin
          N := Pos(':', Ln);
          If N > 0 Then
          Begin
            L[Cnt] := Copy(Ln, 1, N - 1);
            While (Length(L[Cnt]) > 0) And (L[Cnt][1] = ' ') Do
              Delete(L[Cnt], 1, 1);
            Inc(Cnt);
          End;
        End;
        Ln := '';
        If N <= 0 Then Break;
      End
      Else If Length(Ln) < 250 Then Ln := Ln + Chr(B);
    End;
    SysClose(Fd);
  End;
  Names := Cnt;
End;

Function FlagsS(Fl : LongInt; Mtu : LongInt) : String;
Var S : String;
Begin
  S := '<';
  If (Fl And 8) <> 0 Then S := S + 'LOOPBACK,';
  If (Fl And 2) <> 0 Then S := S + 'BROADCAST,';
  If (Fl And $1000) <> 0 Then S := S + 'MULTICAST,';
  If (Fl And 1) <> 0 Then S := S + 'UP,LOWER_UP,';
  If S[Length(S)] = ',' Then Delete(S, Length(S), 1);
  S := S + '> mtu ' + NumS(Mtu);
  If (Fl And 8) <> 0 Then S := S + ' qdisc noqueue state UNKNOWN'
  Else If (Fl And 1) <> 0 Then S := S + ' qdisc pfifo_fast state UP'
  Else S := S + ' qdisc noop state DOWN';
  FlagsS := S;
End;

Procedure ShowDev(Idx : LongInt; Const N : String; WithAddr : Boolean);
Var R : TIfReq; Fl, Mtu, Ip, Mk, Bc, K : LongInt; S : String;
Begin
  SetName(R, N);
  If SysIoctl(Sk, SIOCGIFFLAGS, R) < 0 Then Exit;
  Fl := R.Data[0] Or (R.Data[1] Shl 8);
  SetName(R, N);
  Mtu := 1500;
  If SysIoctl(Sk, SIOCGIFMTU, R) = 0 Then
    Mtu := R.Data[0] Or (R.Data[1] Shl 8) Or (R.Data[2] Shl 16);
  SysPut(1, NumS(Idx) + ': ' + N + ': ' + FlagsS(Fl, Mtu) + #10);
  SetName(R, N);
  S := '00:00:00:00:00:00';
  If SysIoctl(Sk, SIOCGIFHWADDR, R) = 0 Then
  Begin
    S := '';
    For K := 0 To 5 Do
    Begin
      If K > 0 Then S := S + ':';
      S := S + Hex2(R.Data[2 + K]);
    End;
  End;
  If (Fl And 8) <> 0 Then
    SysPut(1, '    link/loopback ' + S + ' brd 00:00:00:00:00:00' + #10)
  Else
    SysPut(1, '    link/ether ' + S + ' brd ff:ff:ff:ff:ff:ff' + #10);
  If WithAddr And GetIp(N, SIOCGIFADDR, Ip) Then
  Begin
    GetIp(N, SIOCGIFNETMASK, Mk);
    S := '    inet ' + SysIpStr(Ip) + '/' + NumS(PrefixOf(Mk));
    If ((Fl And 8) = 0) And GetIp(N, SIOCGIFBRDADDR, Bc) And (Bc <> 0) Then
      S := S + ' brd ' + SysIpStr(Bc);
    If (Fl And 8) <> 0 Then S := S + ' scope host ' + N
    Else S := S + ' scope global ' + N;
    SysPut(1, S + #10);
  End;
End;

Function Trim_(Const S : String) : String;
Var X, Y : LongInt;
Begin
  X := 1;
  Y := Length(S);
  While (X <= Y) And (S[X] = ' ') Do Inc(X);
  While (Y >= X) And (S[Y] = ' ') Do Dec(Y);
  Trim_ := Copy(S, X, Y - X + 1);
End;

Procedure ShowStats(Const N : String);
Var Fd, K, P, Cnt : LongInt; B : Byte; Ln : String; F : Array[1..16] Of String;
Begin
  Fd := SysOpen('/proc/net/dev', O_RDONLY, 0);
  If Fd < 0 Then Exit;
  Ln := '';
  While True Do
  Begin
    K := SysRead(Fd, B, 1);
    If (K <= 0) Or (B = 10) Then
    Begin
      P := Pos(':', Ln);
      If (P > 0) Then
      Begin
        If Trim_(Copy(Ln, 1, P - 1)) = N Then
        Begin
          Ln := Copy(Ln, P + 1, 250);
          For K := 1 To 16 Do F[K] := '';
          Cnt := 1;
          For K := 1 To Length(Ln) Do
            If Ln[K] = ' ' Then
            Begin
              If (F[Cnt] <> '') And (Cnt < 16) Then Inc(Cnt);
            End
            Else F[Cnt] := F[Cnt] + Ln[K];
          SysPut(1, '    RX: bytes  packets  errors  dropped' + #10 +
                 '    ' + F[1] + ' ' + F[2] + ' ' + F[3] + ' ' + F[4] + #10 +
                 '    TX: bytes  packets  errors  dropped' + #10 +
                 '    ' + F[9] + ' ' + F[10] + ' ' + F[11] + ' ' + F[12] + #10);
        End;
      End;
      Ln := '';
      If K <= 0 Then Break;
    End
    Else If Length(Ln) < 250 Then Ln := Ln + Chr(B);
  End;
  SysClose(Fd);
End;

{ ---------- routes ---------- }

Function Swap32(V : LongInt) : LongInt;
Begin
  Swap32 := V;
End;

Function HexV(Const S : String) : LongInt;
Var K, V, C : LongInt;
Begin
  V := 0;
  For K := 1 To Length(S) Do
  Begin
    C := Ord(S[K]);
    If (C >= 48) And (C <= 57) Then V := V * 16 + C - 48
    Else If (C >= 65) And (C <= 70) Then V := V * 16 + C - 55
    Else If (C >= 97) And (C <= 102) Then V := V * 16 + C - 87;
  End;
  HexV := V;
End;

{ /proc/net/route : adresses en hexa little-endian = octets dans l'ordre
  memoire de SysIp : la valeur lue comme nombre est deja celle de SysIpStr }
Procedure ShowRoutes;
Var Fd, N, K, F : LongInt; B : Byte; Ln : String; First : Boolean;
    Fl : Array[1..11] Of String; Dst, Gw, Mk : LongInt; S : String;
Begin
  Fd := SysOpen('/proc/net/route', O_RDONLY, 0);
  If Fd < 0 Then Exit;
  Ln := '';
  First := True;
  While True Do
  Begin
    N := SysRead(Fd, B, 1);
    If (N <= 0) Or (B = 10) Then
    Begin
      If Ln <> '' Then
        If First Then First := False
        Else
        Begin
          For K := 1 To 11 Do Fl[K] := '';
          F := 1;
          For K := 1 To Length(Ln) Do
            If (Ln[K] = ' ') Or (Ln[K] = #9) Then
            Begin
              If (Fl[F] <> '') And (F < 11) Then Inc(F);
            End
            Else Fl[F] := Fl[F] + Ln[K];
          Dst := HexV(Fl[2]);
          Gw := HexV(Fl[3]);
          Mk := HexV(Fl[8]);
          If Dst = 0 Then S := 'default' Else S := SysIpStr(Dst);
          If (Dst <> 0) Then S := S + '/' + NumS(PrefixOf(Mk));
          If Gw <> 0 Then S := S + ' via ' + SysIpStr(Gw);
          S := S + ' dev ' + Fl[1];
          If (Gw = 0) Then S := S + ' scope link';
          SysPut(1, S + #10);
        End;
      Ln := '';
      If N <= 0 Then Break;
    End
    Else If Length(Ln) < 250 Then Ln := Ln + Chr(B);
  End;
  SysClose(Fd);
End;

{ lance /sbin/ifconfig ou /sbin/route avec les arguments donnes }
Function Run(Const Prog : String; Const Av : Array Of String;
             N : LongInt) : LongInt;
Var Pid, St, K : LongInt;
Begin
  Pid := SysFork;
  If Pid = 0 Then
  Begin
    SysArgReset;
    SysArgAdd(Prog);
    For K := 0 To N - 1 Do SysArgAdd(Av[K]);
    SysEnvInherit;
    SysArgExec('/sbin/' + Prog);
    SysArgExec('/bin/' + Prog);
    SysExit(127);
  End;
  SysWaitPid(Pid, St, 0);
  Run := SysWExitStatus(St);
End;

Function ArgOf(Const Key : String) : String;
Var I : LongInt;
Begin
  ArgOf := '';
  For I := 1 To NA - 1 Do
    If A[I] = Key Then
    Begin
      ArgOf := A[I + 1];
      Exit;
    End;
End;

Procedure SplitCidr(Const S : String; Var Ip : String; Var Len : LongInt);
Var K : LongInt;
Begin
  K := Pos('/', S);
  If K = 0 Then
  Begin
    Ip := S;
    Len := 32;
  End
  Else
  Begin
    Ip := Copy(S, 1, K - 1);
    Len := ToNum(Copy(S, K + 1, 5));
  End;
End;

Procedure DoAddr;
Var
  Names_ : Array[0..31] Of String;
  N, I : LongInt;
  Dev, Ip, Sub : String;
  Len : LongInt;
  Av : Array[0..7] Of String;
Begin
  Sub := 'show';
  If NA >= 2 Then Sub := A[2];
  Dev := ArgOf('dev');
  If (Sub = 'show') Or (Sub = 'list') Or (Sub = 'ls') Or (Sub = 'l') Or
     (NA < 2) Then
  Begin
    If (Dev = '') And (NA >= 3) And (Sub <> 'show') Then Dev := '';
    N := Names(Names_);
    For I := 0 To N - 1 Do
      If (Dev = '') Or (Dev = Names_[I]) Then ShowDev(I + 1, Names_[I], True);
    Exit;
  End;
  If (Sub = 'add') Or (Sub = 'del') Then
  Begin
    If (NA < 3) Or (Dev = '') Then Fail('dev X required');
    SplitCidr(A[3], Ip, Len);
    If Sub = 'add' Then
    Begin
      Av[0] := Dev; Av[1] := Ip; Av[2] := 'netmask'; Av[3] := MaskOf(Len);
      If Run('ifconfig', Av, 4) <> 0 Then SysExit(2);
    End
    Else
    Begin
      Av[0] := Dev; Av[1] := '0.0.0.0';
      If Run('ifconfig', Av, 2) <> 0 Then SysExit(2);
    End;
    Exit;
  End;
  Fail('unknown addr command "' + Sub + '"');
End;

Procedure DoLink;
Var
  Names_ : Array[0..31] Of String;
  N, I, K : LongInt;
  Dev, Sub : String;
  Av : Array[0..7] Of String;
Begin
  Sub := 'show';
  If NA >= 2 Then Sub := A[2];
  If (Sub = 'show') Or (Sub = 'list') Or (NA < 2) Then
  Begin
    Dev := '';
    If (NA >= 3) Then Dev := A[3];
    If Dev = 'dev' Then Dev := ArgOf('dev');
    N := Names(Names_);
    For I := 0 To N - 1 Do
      If (Dev = '') Or (Dev = Names_[I]) Then
      Begin
        ShowDev(I + 1, Names_[I], False);
        If Stats Then ShowStats(Names_[I]);
      End;
    Exit;
  End;
  If Sub = 'set' Then
  Begin
    Dev := ArgOf('dev');
    If Dev = '' Then
      If NA >= 3 Then Dev := A[3];
    If Dev = '' Then Fail('dev X required');
    For K := 3 To NA Do
    Begin
      If A[K] = 'up' Then
      Begin
        Av[0] := Dev; Av[1] := 'up';
        If Run('ifconfig', Av, 2) <> 0 Then SysExit(2);
      End
      Else If A[K] = 'down' Then
      Begin
        Av[0] := Dev; Av[1] := 'down';
        If Run('ifconfig', Av, 2) <> 0 Then SysExit(2);
      End
      Else If (A[K] = 'mtu') And (K < NA) Then
      Begin
        Av[0] := Dev; Av[1] := 'mtu'; Av[2] := A[K + 1];
        If Run('ifconfig', Av, 3) <> 0 Then SysExit(2);
      End;
    End;
    Exit;
  End;
  Fail('unknown link command "' + Sub + '"');
End;

Procedure DoRoute;
Var
  Sub, Dst, Via, Dev, Ip : String;
  Len : LongInt;
  Av : Array[0..11] Of String;
  N : LongInt;
Begin
  Sub := 'show';
  If NA >= 2 Then Sub := A[2];
  If (Sub = 'show') Or (Sub = 'list') Or (NA < 2) Then
  Begin
    ShowRoutes;
    Exit;
  End;
  If (Sub = 'add') Or (Sub = 'del') Then
  Begin
    If NA < 3 Then Fail('destination required');
    Dst := A[3];
    Via := ArgOf('via');
    Dev := ArgOf('dev');
    N := 0;
    Av[N] := Sub; Inc(N);
    If Dst = 'default' Then
    Begin
      Av[N] := 'default'; Inc(N);
    End
    Else
    Begin
      SplitCidr(Dst, Ip, Len);
      If Len = 32 Then
      Begin
        Av[N] := '-host'; Inc(N);
        Av[N] := Ip; Inc(N);
      End
      Else
      Begin
        Av[N] := '-net'; Inc(N);
        Av[N] := Ip; Inc(N);
        Av[N] := 'netmask'; Inc(N);
        Av[N] := MaskOf(Len); Inc(N);
      End;
    End;
    If Via <> '' Then
    Begin
      Av[N] := 'gw'; Inc(N);
      Av[N] := Via; Inc(N);
    End;
    If Dev <> '' Then
    Begin
      Av[N] := 'dev'; Inc(N);
      Av[N] := Dev; Inc(N);
    End;
    If Run('route', Av, N) <> 0 Then SysExit(2);
    Exit;
  End;
  Fail('unknown route command "' + Sub + '"');
End;

Var
  I, K : LongInt;
  S, Obj : String;
BEGIN
  Lang := SysLang;
  If (Lang < 1) Or (Lang > 5) Then Lang := 1;
  Sk := SysSocket(2, 2, 0);
  NA := 0;
  Obj := '';
  For I := 1 To SysArgCount - 1 Do
  Begin
    S := SysArgStr(I);
    If (S = '--help') Or (S = '/?') Or (S = '-h') Then
    Begin
      SysPut(1, PS(Usage[Lang]) + #10);
      SysExit(0);
    End
    Else If (S = '-4') Or (S = '-o') Or (S = '-br') Then
    Else If S = '-s' Then Stats := True
    Else If NA < 24 Then
    Begin
      Inc(NA);
      A[NA] := S;
    End;
  End;
  If NA = 0 Then Fail(PS(Usage[Lang]));
  Obj := A[1];
  { objet : abreviations }
  If (Obj = 'addr') Or (Obj = 'address') Or (Obj = 'a') Then DoAddr
  Else If (Obj = 'link') Or (Obj = 'l') Then DoLink
  Else If (Obj = 'route') Or (Obj = 'r') Or (Obj = 'ro') Then DoRoute
  Else Fail('Object "' + Obj + '" is unknown, try "ip help".');
END.
