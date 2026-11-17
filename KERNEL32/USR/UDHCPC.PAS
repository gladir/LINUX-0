{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2026
  @website(https://www.gladir.com/linux-0)
  @abstract(Target: LPC -3X)
  @description: /sbin/udhcpc (dhclient) : client DHCP minimal par diffusion
      UDP (sans AF_PACKET) : udhcpc [-i interface] [-n] [-q] [-t essais]
      [-T secondes]. DISCOVER, OFFER, REQUEST, ACK ; configure l'interface
      (/sbin/ifconfig), la passerelle (/sbin/route) et /etc/resolv.conf.
      L'interface est d'abord montee a 0.0.0.0. Une seule negociation
      (pas de renouvellement de bail).
}

Program UDHCPC;

Const
  SIOCGIFHWADDR = $8927;
  Usage : Array[1..5] Of PChar = (
    'Usage : udhcpc [-i interface] [-n] [-q] [-t essais] [-T secondes]',
    'Usage: udhcpc [-i interface] [-n] [-q] [-t tries] [-T seconds]',
    'Aufruf: udhcpc [-i Schnittstelle] [-n] [-q] [-t N] [-T Sek]',
    'Uso: udhcpc [-i interfaz] [-n] [-q] [-t intentos] [-T segundos]',
    'Uso: udhcpc [-i interfaccia] [-n] [-q] [-t prove] [-T secondi]');

Type
  TIfReq = Record
    Name : Array[0..15] Of Byte;
    Data : Array[0..23] Of Byte;
  End;

Var
  Lang : LongInt;
  Iface : String;
  Mac : Array[0..5] Of Byte;
  Pk : Array[0..575] Of Byte;
  Rp : Array[0..1499] Of Byte;
  Xid : LongInt;
  Sk : LongInt;
  YourIp, ServerIp, Mask, Router, Dns, Lease : LongInt;
  MsgType : LongInt;

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

Procedure GetMac;
Var R : TIfReq; K, S : LongInt;
Begin
  FillChar(R, SizeOf(R), 0);
  For K := 1 To Length(Iface) Do
    If K <= 15 Then R.Name[K - 1] := Ord(Iface[K]);
  S := SysSocket(2, 2, 0);
  If SysIoctl(S, SIOCGIFHWADDR, R) = 0 Then
    For K := 0 To 5 Do Mac[K] := R.Data[2 + K]
  Else
    For K := 0 To 5 Do Mac[K] := 2 + K;
  SysClose(S);
End;

Procedure Put32(P : LongInt; V : LongInt);
Begin
  Pk[P] := (V Shr 24) And 255;
  Pk[P + 1] := (V Shr 16) And 255;
  Pk[P + 2] := (V Shr 8) And 255;
  Pk[P + 3] := V And 255;
End;

{ construit un message (Typ = 1 DISCOVER, 3 REQUEST) : retourne sa longueur }
Function Build(Typ : LongInt) : LongInt;
Var K, P : LongInt;
Begin
  FillChar(Pk, SizeOf(Pk), 0);
  Pk[0] := 1;
  Pk[1] := 1;
  Pk[2] := 6;
  Put32(4, Xid);
  Pk[10] := $80;
  For K := 0 To 5 Do Pk[28 + K] := Mac[K];
  Pk[236] := 99; Pk[237] := 130; Pk[238] := 83; Pk[239] := 99;
  P := 240;
  Pk[P] := 53; Pk[P + 1] := 1; Pk[P + 2] := Typ; Inc(P, 3);
  Pk[P] := 61; Pk[P + 1] := 7; Pk[P + 2] := 1;
  For K := 0 To 5 Do Pk[P + 3 + K] := Mac[K];
  Inc(P, 9);
  If Typ = 3 Then
  Begin
    Pk[P] := 50; Pk[P + 1] := 4;
    Pk[P + 2] := YourIp And 255; Pk[P + 3] := (YourIp Shr 8) And 255;
    Pk[P + 4] := (YourIp Shr 16) And 255; Pk[P + 5] := (YourIp Shr 24) And 255;
    Inc(P, 6);
    Pk[P] := 54; Pk[P + 1] := 4;
    Pk[P + 2] := ServerIp And 255; Pk[P + 3] := (ServerIp Shr 8) And 255;
    Pk[P + 4] := (ServerIp Shr 16) And 255;
    Pk[P + 5] := (ServerIp Shr 24) And 255;
    Inc(P, 6);
  End;
  Pk[P] := 55; Pk[P + 1] := 4; Pk[P + 2] := 1; Pk[P + 3] := 3;
  Pk[P + 4] := 6; Pk[P + 5] := 28; Inc(P, 6);
  Pk[P] := 255;
  Inc(P);
  If P < 300 Then P := 300;
  Build := P;
End;

Function Ip4(P : LongInt) : LongInt;
Begin
  Ip4 := Rp[P] Or (Rp[P + 1] Shl 8) Or (Rp[P + 2] Shl 16) Or (Rp[P + 3] Shl 24);
End;

{ analyse une reponse ; faux si ce n'est pas pour nous }
Function Parse(N : LongInt) : Boolean;
Var P, O, L : LongInt;
Begin
  Parse := False;
  If (N < 240) Or (Rp[0] <> 2) Then Exit;
  If (Rp[4] <> ((Xid Shr 24) And 255)) Or (Rp[7] <> (Xid And 255)) Then Exit;
  YourIp := Ip4(16);
  MsgType := 0;
  Mask := 0; Router := 0; Dns := 0; Lease := 0;
  P := 240;
  While P < N Do
  Begin
    O := Rp[P];
    If O = 255 Then Break;
    If O = 0 Then
    Begin
      Inc(P);
      Continue;
    End;
    L := Rp[P + 1];
    Case O Of
      53 : MsgType := Rp[P + 2];
      54 : ServerIp := Ip4(P + 2);
      1 : Mask := Ip4(P + 2);
      3 : Router := Ip4(P + 2);
      6 : Dns := Ip4(P + 2);
      51 : Lease := (Rp[P + 2] Shl 24) Or (Rp[P + 3] Shl 16) Or
                    (Rp[P + 4] Shl 8) Or Rp[P + 5];
    End;
    P := P + 2 + L;
  End;
  Parse := True;
End;

{ envoie le message et attend un type de reponse }
Function Exchange(Typ, Want, Secs : LongInt) : Boolean;
Var
  Len, N, T0, Left : LongInt;
  Dst, Src : TSockAddrIn;
  Pf : Array[0..1] Of LongInt;
  FromLen : LongInt;
Begin
  Exchange := False;
  Len := Build(Typ);
  SysSockAddr(Dst, SysIp(255, 255, 255, 255), 67);
  If SysSendTo(Sk, LongInt(@Pk[0]), Len, 0, LongInt(@Dst), 16) < 0 Then
  Begin
    SysPut(2, 'udhcpc: sendto: ' + SysErrorText(SysErrno) + #10);
    Exit;
  End;
  Left := Secs;
  While Left > 0 Do
  Begin
    Pf[0] := Sk;
    Pf[1] := 1;
    N := SysPoll(LongInt(@Pf), 1, 1000);
    If N <= 0 Then
    Begin
      Dec(Left);
      Continue;
    End;
    FromLen := 16;
    N := SysRecvFrom(Sk, LongInt(@Rp[0]), 1500, 0, LongInt(@Src),
                     LongInt(@FromLen));
    If N > 0 Then
      If Parse(N) And (MsgType = Want) Then
      Begin
        Exchange := True;
        Exit;
      End;
  End;
End;

Procedure Configure;
Var Av : Array[0..7] Of String; Fd : LongInt;
Begin
  Av[0] := Iface;
  Av[1] := SysIpStr(YourIp);
  Av[2] := 'netmask';
  If Mask <> 0 Then Av[3] := SysIpStr(Mask) Else Av[3] := '255.255.255.0';
  Av[4] := 'up';
  Run('ifconfig', Av, 5);
  If Router <> 0 Then
  Begin
    Av[0] := 'add'; Av[1] := 'default'; Av[2] := 'gw';
    Av[3] := SysIpStr(Router); Av[4] := 'dev'; Av[5] := Iface;
    Run('route', Av, 6);
  End;
  If Dns <> 0 Then
  Begin
    Fd := SysOpen('/etc/resolv.conf', O_WRONLY Or O_CREAT Or O_TRUNC, 420);
    If Fd >= 0 Then
    Begin
      SysPut(Fd, 'nameserver ' + SysIpStr(Dns) + #10);
      SysClose(Fd);
    End;
  End;
End;

Var
  I, Tries, TimeOut, One, Tv : LongInt;
  A : String;
  Quiet, Ok : Boolean;
  Av : Array[0..3] Of String;
  Sa : TSockAddrIn;
BEGIN
  Lang := SysLang;
  If (Lang < 1) Or (Lang > 5) Then Lang := 1;
  Iface := 'eth0';
  Tries := 3;
  TimeOut := 5;
  Quiet := False;
  I := 1;
  While I < SysArgCount Do
  Begin
    A := SysArgStr(I);
    If A = '-i' Then
    Begin
      Inc(I);
      If I < SysArgCount Then Iface := SysArgStr(I);
    End
    Else If A = '-t' Then
    Begin
      Inc(I);
      If I < SysArgCount Then Val(SysArgStr(I), Tries, One);
    End
    Else If A = '-T' Then
    Begin
      Inc(I);
      If I < SysArgCount Then Val(SysArgStr(I), TimeOut, One);
    End
    Else If (A = '-q') Or (A = '-n') Or (A = '-f') Or (A = '-b') Then
      Quiet := Quiet Or (A = '-q')
    Else If (A = '--help') Or (A = '/?') Then
    Begin
      SysPut(1, PS(Usage[Lang]) + #10);
      SysExit(0);
    End;
    Inc(I);
  End;
  GetMac;
  Av[0] := Iface; Av[1] := '0.0.0.0'; Av[2] := 'up';
  Run('ifconfig', Av, 3);
  Sk := SysSocket(2, 2, 0);
  If Sk < 0 Then
  Begin
    SysPut(2, 'udhcpc: socket: ' + SysErrorText(SysErrno) + #10);
    SysExit(1);
  End;
  One := 1;
  SysSetSockOpt(Sk, 1, 6, LongInt(@One), 4);
  SysSetSockOpt(Sk, 1, 2, LongInt(@One), 4);
  SysSockAddr(Sa, 0, 68);
  If SysBind(Sk, LongInt(@Sa), 16) < 0 Then
  Begin
    SysPut(2, 'udhcpc: bind: ' + SysErrorText(SysErrno) + #10);
    SysExit(1);
  End;
  Xid := SysTime Xor $5A5A1234;
  Ok := False;
  For I := 1 To Tries Do
  Begin
    SysPut(1, 'udhcpc: sending discover' + #10);
    If Exchange(1, 2, TimeOut) Then
    Begin
      SysPut(1, 'udhcpc: sending select for ' + SysIpStr(YourIp) + #10);
      If Exchange(3, 5, TimeOut) Then
      Begin
        Ok := True;
        Break;
      End;
    End;
  End;
  If Not Ok Then
  Begin
    SysPut(2, 'udhcpc: no lease, failing' + #10);
    SysExit(1);
  End;
  SysPut(1, 'udhcpc: lease of ' + SysIpStr(YourIp) + ' obtained, lease time ' +
         NumS(Lease) + #10);
  Configure;
END.
