{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2026
  @website(https://www.gladir.com/linux-0)
  @abstract(Target: LPC -3X)
  @description: lsof, fuser, netstat, ss, lspci, lsusb, losetup (un seul
      programme, nom lu dans argv[0]). Lisent /proc et /sys comme Linux :
      /proc/PID/{status,cmdline,fd,maps}, /proc/net/{tcp,udp,unix,dev,route},
      /sys/bus/pci/devices, /sys/bus/usb/devices ; losetup utilise les ioctl
      LOOP_* de /dev/loopN. Les fichiers absents du noyau donnent une table
      vide ou un message (voir BUGS_NOYAU.md).
}

Program PROCINFO;

Const
  Usage : Array[1..5] Of PChar = (
    'Usage : lsof | fuser | netstat | ss | lspci | lsusb | losetup',
    'Usage: lsof | fuser | netstat | ss | lspci | lsusb | losetup',
    'Aufruf: lsof | fuser | netstat | ss | lspci | lsusb | losetup',
    'Uso: lsof | fuser | netstat | ss | lspci | lsusb | losetup',
    'Uso: lsof | fuser | netstat | ss | lspci | lsusb | losetup');
  TcpStates : Array[1..12] Of String[12] = ('ESTABLISHED', 'SYN_SENT',
    'SYN_RECV', 'FIN_WAIT1', 'FIN_WAIT2', 'TIME_WAIT', 'CLOSE', 'CLOSE_WAIT',
    'LAST_ACK', 'LISTEN', 'CLOSING', 'NEW_SYN_RECV');
  LOOP_SET_FD = $4C00; LOOP_CLR_FD = $4C01; LOOP_SET_STATUS64 = $4C04;
  LOOP_GET_STATUS64 = $4C05; LOOP_CTL_GET_FREE = $4C82;

Var
  Lang : LongInt;
  Prog : String;
  Args : Array[1..32] Of String;
  NArg : LongInt;
  Opt : Array[0..127] Of Boolean;
  OptVal : Array[0..127] Of String;

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

Function Trim_(Const S : String) : String;
Var A, B : LongInt;
Begin
  A := 1;
  B := Length(S);
  While (A <= B) And (S[A] = ' ') Do Inc(A);
  While (B >= A) And (S[B] = ' ') Do Dec(B);
  Trim_ := Copy(S, A, B - A + 1);
End;

Function Pad(Const S : String; N : LongInt) : String;
Var R : String;
Begin
  R := S;
  While Length(R) < N Do R := R + ' ';
  Pad := R;
End;

Function PadL(Const S : String; N : LongInt) : String;
Var R : String;
Begin
  R := S;
  While Length(R) < N Do R := ' ' + R;
  PadL := R;
End;

Function ReadSmall(Const Path : String) : String;
Var Fd, N : LongInt; B : Byte; S : String;
Begin
  ReadSmall := '';
  Fd := SysOpen(Path, O_RDONLY, 0);
  If Fd < 0 Then Exit;
  S := '';
  While (SysRead(Fd, B, 1) > 0) And (Length(S) < 250) Do S := S + Chr(B);
  SysClose(Fd);
  While (Length(S) > 0) And (S[Length(S)] In [#10, #13, ' ']) Do
    Delete(S, Length(S), 1);
  ReadSmall := S;
End;

{ ligne "Cle:\tvaleur" de /proc/PID/status }
Function StatusField(Const Pid, Key : String) : String;
Var Fd, N : LongInt; B : Byte; Ln : String; Got : Boolean;
Begin
  StatusField := '';
  Fd := SysOpen('/proc/' + Pid + '/status', O_RDONLY, 0);
  If Fd < 0 Then Exit;
  Ln := '';
  Got := False;
  While True Do
  Begin
    N := SysRead(Fd, B, 1);
    If (N <= 0) Or (B = 10) Then
    Begin
      If Copy(Ln, 1, Length(Key) + 1) = Key + ':' Then
      Begin
        Ln := Copy(Ln, Length(Key) + 2, 250);
        While (Length(Ln) > 0) And (Ln[1] In [' ', #9]) Do Delete(Ln, 1, 1);
        StatusField := Ln;
        Break;
      End;
      Ln := '';
      If N <= 0 Then Break;
    End
    Else If Length(Ln) < 250 Then Ln := Ln + Chr(B);
  End;
  SysClose(Fd);
End;

Function IsNum(Const S : String) : Boolean;
Var K : LongInt;
Begin
  IsNum := Length(S) > 0;
  For K := 1 To Length(S) Do
    If (S[K] < '0') Or (S[K] > '9') Then IsNum := False;
End;

Function ToNum(Const S : String) : LongInt;
Var V, C : LongInt;
Begin
  Val(S, V, C);
  If C <> 0 Then V := 0;
  ToNum := V;
End;

Function UserOf(Const Pid : String) : String;
Var U : String; Pw : TSysPasswd; K : LongInt;
Begin
  U := StatusField(Pid, 'Uid');
  K := Pos(#9, U);
  If K > 0 Then U := Copy(U, 1, K - 1);
  K := Pos(' ', U);
  If K > 0 Then U := Copy(U, 1, K - 1);
  If SysGetPwUid(ToNum(U), Pw) Then UserOf := Pw.Name Else UserOf := U;
End;

Function CmdOf(Const Pid : String) : String;
Var S : String;
Begin
  S := StatusField(Pid, 'Name');
  If S = '' Then S := ReadSmall('/proc/' + Pid + '/comm');
  CmdOf := S;
End;

{ liste des PID de /proc }
Function Pids(Var L : Array Of String) : LongInt;
Var D, Ino, N : LongInt; Nm : String;
Begin
  N := 0;
  D := SysOpenDir('/proc');
  If D >= 0 Then
  Begin
    While SysReadDir(D, Nm, Ino) <> 0 Do
      If IsNum(Nm) And (N <= High(L)) Then
      Begin
        L[N] := Nm;
        Inc(N);
      End;
    SysCloseDir(D);
  End;
  Pids := N;
End;

Function TypeName(Mode : LongInt) : String;
Begin
  Case Mode And $F000 Of
    $8000 : TypeName := 'REG';
    $4000 : TypeName := 'DIR';
    $2000 : TypeName := 'CHR';
    $6000 : TypeName := 'BLK';
    $1000 : TypeName := 'FIFO';
    $C000 : TypeName := 'sock';
    $A000 : TypeName := 'LINK';
  Else TypeName := 'unknown';
  End;
End;

{ ------------------------------ lsof ------------------------------ }

Procedure ParseOpts(Const Valued : String);
Var I, K : LongInt; A : String;
Begin
  NArg := 0;
  I := 1;
  While I < SysArgCount Do
  Begin
    A := SysArgStr(I);
    If (A = '--help') Or (A = '/?') Then
    Begin
      SysPut(1, PS(Usage[Lang]) + #10);
      SysExit(0);
    End;
    If (Length(A) > 1) And (A[1] = '-') Then
    Begin
      K := 2;
      While K <= Length(A) Do
      Begin
        Opt[Ord(A[K])] := True;
        If Pos(A[K], Valued) > 0 Then
        Begin
          If K < Length(A) Then OptVal[Ord(A[K])] := Copy(A, K + 1, 255)
          Else
          Begin
            Inc(I);
            If I < SysArgCount Then OptVal[Ord(A[K])] := SysArgStr(I);
          End;
          K := Length(A);
        End;
        Inc(K);
      End;
    End
    Else If NArg < 32 Then
    Begin
      Inc(NArg);
      Args[NArg] := A;
    End;
    Inc(I);
  End;
End;

Procedure RunLsof;
Var
  L : Array[0..255] Of String;
  N, I, D, Ino, K : LongInt;
  Pid, Nm, Cmd, Usr, Tgt, FdName : String;
  St : TSysStat;
  Fds : Array[0..255] Of String;
  NF, J : LongInt;
  Match : Boolean;
Begin
  ParseOpts('pucd');
  SysPut(1, Pad('COMMAND', 10) + PadL('PID', 6) + ' ' + Pad('USER', 9) +
         Pad('FD', 6) + Pad('TYPE', 6) + 'NAME' + #10);
  N := Pids(L);
  For I := 0 To N - 1 Do
  Begin
    Pid := L[I];
    If Opt[Ord('p')] And (OptVal[Ord('p')] <> Pid) Then Continue;
    Cmd := CmdOf(Pid);
    If Opt[Ord('c')] And (Copy(Cmd, 1, Length(OptVal[Ord('c')])) <>
                           OptVal[Ord('c')]) Then Continue;
    Usr := UserOf(Pid);
    If Opt[Ord('u')] And (OptVal[Ord('u')] <> Usr) Then Continue;
    { cwd, exe, descripteurs }
    NF := 0;
    Fds[NF] := 'cwd'; Inc(NF);
    Fds[NF] := 'txt'; Inc(NF);
    D := SysOpenDir('/proc/' + Pid + '/fd');
    If D >= 0 Then
    Begin
      While SysReadDir(D, Nm, Ino) <> 0 Do
        If IsNum(Nm) And (NF < 250) Then
        Begin
          Fds[NF] := Nm;
          Inc(NF);
        End;
      SysCloseDir(D);
    End;
    For J := 0 To NF - 1 Do
    Begin
      If Fds[J] = 'cwd' Then Tgt := SysReadlink('/proc/' + Pid + '/cwd')
      Else If Fds[J] = 'txt' Then Tgt := SysReadlink('/proc/' + Pid + '/exe')
      Else Tgt := SysReadlink('/proc/' + Pid + '/fd/' + Fds[J]);
      If Tgt = '' Then Continue;
      If Fds[J] = 'cwd' Then FdName := 'cwd'
      Else If Fds[J] = 'txt' Then FdName := 'txt'
      Else
      Begin
        FdName := Fds[J];
        FdName := FdName + 'u';
      End;
      If Fds[J] <> 'cwd' Then
        If Fds[J] <> 'txt' Then
          If SysFStat(ToNum(Fds[J]), St) = 0 Then Ino := 0;
      St.Mode := 0;
      If SysStat(Tgt, St) <> 0 Then
        If Copy(Tgt, 1, 7) = 'socket:' Then St.Mode := $C000
        Else If Copy(Tgt, 1, 5) = 'pipe:' Then St.Mode := $1000;
      If NArg > 0 Then
      Begin
        Match := False;
        For K := 1 To NArg Do If Args[K] = Tgt Then Match := True;
        If Not Match Then Continue;
      End;
      SysPut(1, Pad(Cmd, 10) + PadL(Pid, 6) + ' ' + Pad(Usr, 9) +
             Pad(FdName, 6) + Pad(TypeName(St.Mode), 6) + Tgt + #10);
    End;
  End;
End;

{ ------------------------------ fuser ------------------------------ }

Procedure RunFuser;
Var
  L : Array[0..255] Of String;
  N, I, K, D, Ino, F, Cnt : LongInt;
  Nm, Tgt, Line : String;
  St, T : TSysStat;
  Found, Show : Boolean;
  Pids_ : Array[0..63] Of String;
  NP : LongInt;
Begin
  ParseOpts('');
  If NArg = 0 Then
  Begin
    SysPut(2, PS(Usage[Lang]) + #10);
    SysExit(1);
  End;
  N := Pids(L);
  Found := False;
  For F := 1 To NArg Do
  Begin
    If SysStat(Args[F], T) <> 0 Then
    Begin
      SysPut(2, 'fuser: ' + Args[F] + ': ' + SysErrorText(SysErrno) + #10);
      Continue;
    End;
    NP := 0;
    For I := 0 To N - 1 Do
    Begin
      Show := False;
      D := SysOpenDir('/proc/' + L[I] + '/fd');
      If D >= 0 Then
      Begin
        While SysReadDir(D, Nm, Ino) <> 0 Do
          If IsNum(Nm) Then
          Begin
            If (SysStat('/proc/' + L[I] + '/fd/' + Nm, St) = 0) And
               (St.Ino = T.Ino) And (St.Dev = T.Dev) Then Show := True;
          End;
        SysCloseDir(D);
      End;
      If SysStat('/proc/' + L[I] + '/cwd', St) = 0 Then
        If (St.Ino = T.Ino) And (St.Dev = T.Dev) Then Show := True;
      If SysStat('/proc/' + L[I] + '/exe', St) = 0 Then
        If (St.Ino = T.Ino) And (St.Dev = T.Dev) Then Show := True;
      If Show And (NP < 64) Then
      Begin
        Pids_[NP] := L[I];
        Inc(NP);
      End;
    End;
    If NP > 0 Then
    Begin
      Found := True;
      If Not Opt[Ord('s')] Then
      Begin
        Line := Args[F] + ':';
        For K := 0 To NP - 1 Do
          If Opt[Ord('v')] Then
            Line := Line + #10 + '                     ' + UserOf(Pids_[K]) +
                    ' ' + PadL(Pids_[K], 6) + ' ' + CmdOf(Pids_[K])
          Else Line := Line + ' ' + PadL(Pids_[K], 5);
        SysPut(1, Line + #10);
      End;
      If Opt[Ord('k')] Then
        For K := 0 To NP - 1 Do SysKill(ToNum(Pids_[K]), SIGKILL);
    End;
  End;
  If Found Then SysExit(0) Else SysExit(1);
End;

{ ------------------------------ netstat, ss ------------------------------ }

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

Function Swap32(V : LongInt) : LongInt;
Begin
  Swap32 := ((V And $FF) Shl 24) Or ((V And $FF00) Shl 8) Or
            ((V Shr 8) And $FF00) Or ((V Shr 24) And $FF);
End;

{ adresse "0100007F:0050" de /proc/net/tcp -> 127.0.0.1:80 }
Function AddrS(Const H : String; Numeric : Boolean) : String;
Var P : LongInt; A, Port : LongInt; S : String;
Begin
  P := Pos(':', H);
  If P = 0 Then
  Begin
    AddrS := H;
    Exit;
  End;
  A := Swap32(HexV(Copy(H, 1, P - 1)));
  Port := HexV(Copy(H, P + 1, 8));
  If (A = 0) And (Port = 0) Then
  Begin
    AddrS := '*:*';
    Exit;
  End;
  If A = 0 Then S := '0.0.0.0' Else S := SysIpStr(Swap32(A));
  If Port = 0 Then AddrS := S + ':*'
  Else AddrS := S + ':' + NumS(Port);
End;

Function Field(Const L : String; N : LongInt) : String;
Var K, F : LongInt; R : String;
Begin
  R := '';
  F := 1;
  For K := 1 To Length(L) Do
    If (L[K] = ' ') Or (L[K] = #9) Then
    Begin
      If R <> '' Then
      Begin
        If F = N Then
        Begin
          Field := R;
          Exit;
        End;
        Inc(F);
        R := '';
      End;
    End
    Else R := R + L[K];
  If (R <> '') And (F = N) Then Field := R Else Field := '';
End;

Procedure NetTable(Const Path, Proto : String; Ss : Boolean);
Var Fd, N : LongInt; B : Byte; Ln : String; First : Boolean; St : LongInt;
    Local, Rem, State, Q : String; Sq, Rq : String;
Begin
  Fd := SysOpen(Path, O_RDONLY, 0);
  If Fd < 0 Then Exit;
  Ln := '';
  First := True;
  While True Do
  Begin
    N := SysRead(Fd, B, 1);
    If (N <= 0) Or (B = 10) Then
    Begin
      If Ln <> '' Then
      Begin
        If First Then First := False
        Else
        Begin
          Local := AddrS(Field(Ln, 2), True);
          Rem := AddrS(Field(Ln, 3), True);
          St := HexV(Field(Ln, 4));
          Q := Field(Ln, 5);
          Sq := NumS(HexV(Copy(Q, 1, Pos(':', Q) - 1)));
          Rq := NumS(HexV(Copy(Q, Pos(':', Q) + 1, 8)));
          If Proto = 'udp' Then
          Begin
            If St = 1 Then State := 'ESTABLISHED' Else State := '';
          End
          Else If (St >= 1) And (St <= 12) Then State := TcpStates[St]
          Else State := NumS(St);
          If (Opt[Ord('l')] And (State <> 'LISTEN')) Or
             ((Not Opt[Ord('a')]) And (Not Opt[Ord('l')]) And
              (State = 'LISTEN')) Then
          Else If Ss Then
            SysPut(1, Pad(Proto, 6) + Pad(State, 11) + PadL(Rq, 7) +
                   PadL(Sq, 7) + ' ' + Pad(Local, 24) + Rem + #10)
          Else
            SysPut(1, Pad(Proto, 6) + PadL(Rq, 6) + PadL(Sq, 7) + ' ' +
                   Pad(Local, 24) + Pad(Rem, 24) + State + #10);
        End;
      End;
      Ln := '';
      If N <= 0 Then Break;
    End
    Else If Length(Ln) < 250 Then Ln := Ln + Chr(B);
  End;
  SysClose(Fd);
End;

Procedure RunNetstat(Ss : Boolean);
Var Fd, N, K : LongInt; B : Byte; Ln, Path : String; First : Boolean;
    Tcp, Udp : Boolean;
Begin
  ParseOpts('');
  Tcp := Opt[Ord('t')] Or ((Not Opt[Ord('t')]) And (Not Opt[Ord('u')]));
  Udp := Opt[Ord('u')] Or ((Not Opt[Ord('t')]) And (Not Opt[Ord('u')]));
  If Opt[Ord('r')] Then
  Begin
    SysPut(1, 'Kernel IP routing table' + #10);
    SysPut(1, 'Destination     Gateway         Genmask         Flags   ' +
           'Metric Ref    Use Iface' + #10);
    Fd := SysOpen('/proc/net/route', O_RDONLY, 0);
    If Fd >= 0 Then
    Begin
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
              SysPut(1, Pad(SysIpStr(HexV(Field(Ln, 2))), 16) +
                     Pad(SysIpStr(HexV(Field(Ln, 3))), 16) +
                     Pad(SysIpStr(HexV(Field(Ln, 8))), 16) +
                     Pad('U', 8) + Pad(Field(Ln, 7), 7) + '0' + '      0 ' +
                     Field(Ln, 1) + #10);
          Ln := '';
          If N <= 0 Then Break;
        End
        Else If Length(Ln) < 250 Then Ln := Ln + Chr(B);
      End;
      SysClose(Fd);
    End;
    Exit;
  End;
  If Opt[Ord('i')] Then
  Begin
    SysPut(1, 'Kernel Interface table' + #10);
    SysPut(1, 'Iface      MTU    RX-OK RX-ERR RX-DRP TX-OK TX-ERR ' +
           'TX-DRP' + #10);
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
          If (K > 2) And (Ln <> '') Then
          Begin
            N := Pos(':', Ln);
            SysPut(1, Pad(Trim_(Copy(Ln, 1, N - 1)), 10) + #10);
          End;
          Ln := '';
          If N <= 0 Then Break;
        End
        Else If Length(Ln) < 250 Then Ln := Ln + Chr(B);
      End;
      SysClose(Fd);
    End;
    Exit;
  End;
  If Ss Then
    SysPut(1, 'Netid State      Recv-Q Send-Q Local Address:Port      ' +
           'Peer Address:Port' + #10)
  Else
  Begin
    SysPut(1, 'Active Internet connections ' + Copy('(servers and established)',
           1, 25 * Ord(Opt[Ord('a')])) + #10);
    SysPut(1, 'Proto Recv-Q Send-Q Local Address           ' +
           'Foreign Address         State' + #10);
  End;
  If Tcp Then NetTable('/proc/net/tcp', 'tcp', Ss);
  If Udp Then NetTable('/proc/net/udp', 'udp', Ss);
End;

{ ------------------------------ lspci, lsusb ------------------------------ }

Function ClassName(C : LongInt) : String;
Begin
  Case C Shr 8 Of
    $0100 : ClassName := 'SCSI storage controller';
    $0101 : ClassName := 'IDE interface';
    $0106 : ClassName := 'SATA controller';
    $0200 : ClassName := 'Ethernet controller';
    $0300 : ClassName := 'VGA compatible controller';
    $0401 : ClassName := 'Multimedia audio controller';
    $0600 : ClassName := 'Host bridge';
    $0601 : ClassName := 'ISA bridge';
    $0604 : ClassName := 'PCI bridge';
    $0C03 : ClassName := 'USB controller';
  Else ClassName := 'Class ' + NumS(C Shr 8);
  End;
End;

Procedure RunLspci;
Var D, Ino, N : LongInt; Nm, V, Dv, C, Cl : String;
    Names : Array[0..255] Of String;
    NN, I, J : LongInt; T : String;
Begin
  D := SysOpenDir('/sys/bus/pci/devices');
  If D < 0 Then
  Begin
    SysPut(2, 'lspci: cannot open /sys/bus/pci/devices: ' +
           SysErrorText(SysErrno) + #10);
    SysExit(1);
  End;
  NN := 0;
  While SysReadDir(D, Nm, Ino) <> 0 Do
    If (Nm <> '.') And (Nm <> '..') And (NN < 256) Then
    Begin
      Names[NN] := Nm;
      Inc(NN);
    End;
  SysCloseDir(D);
  For I := 0 To NN - 2 Do
    For J := I + 1 To NN - 1 Do
      If Names[J] < Names[I] Then
      Begin
        T := Names[I]; Names[I] := Names[J]; Names[J] := T;
      End;
  For I := 0 To NN - 1 Do
  Begin
    Nm := Names[I];
    V := ReadSmall('/sys/bus/pci/devices/' + Nm + '/vendor');
    Dv := ReadSmall('/sys/bus/pci/devices/' + Nm + '/device');
    C := ReadSmall('/sys/bus/pci/devices/' + Nm + '/class');
    If Copy(V, 1, 2) = '0x' Then V := Copy(V, 3, 8);
    If Copy(Dv, 1, 2) = '0x' Then Dv := Copy(Dv, 3, 8);
    If Copy(C, 1, 2) = '0x' Then C := Copy(C, 3, 8);
    If Copy(Nm, 1, 5) = '0000:' Then Nm := Copy(Nm, 6, 20);
    SysPut(1, Nm + ' ' + ClassName(HexV(C)) + ': ' + V + ':' + Dv + #10);
  End;
End;

Procedure RunLsusb;
Var D, Ino, I, J, NN : LongInt; Nm, T, Id, Bus, Dev, Pr, Mf : String;
    Names : Array[0..127] Of String;
Begin
  D := SysOpenDir('/sys/bus/usb/devices');
  If D < 0 Then
  Begin
    SysPut(2, 'lsusb: cannot open /sys/bus/usb/devices: ' +
           SysErrorText(SysErrno) + #10);
    SysExit(1);
  End;
  NN := 0;
  While SysReadDir(D, Nm, Ino) <> 0 Do
    If (Nm <> '.') And (Nm <> '..') And (NN < 128) Then
    Begin
      Names[NN] := Nm;
      Inc(NN);
    End;
  SysCloseDir(D);
  For I := 0 To NN - 2 Do
    For J := I + 1 To NN - 1 Do
      If Names[J] < Names[I] Then
      Begin
        T := Names[I]; Names[I] := Names[J]; Names[J] := T;
      End;
  For I := 0 To NN - 1 Do
  Begin
    Nm := Names[I];
    Id := ReadSmall('/sys/bus/usb/devices/' + Nm + '/idVendor');
    If Id = '' Then Continue;
    Bus := ReadSmall('/sys/bus/usb/devices/' + Nm + '/busnum');
    Dev := ReadSmall('/sys/bus/usb/devices/' + Nm + '/devnum');
    Pr := ReadSmall('/sys/bus/usb/devices/' + Nm + '/idProduct');
    Mf := ReadSmall('/sys/bus/usb/devices/' + Nm + '/manufacturer') + ' ' +
          ReadSmall('/sys/bus/usb/devices/' + Nm + '/product');
    While Length(Bus) < 3 Do Bus := '0' + Bus;
    While Length(Dev) < 3 Do Dev := '0' + Dev;
    SysPut(1, 'Bus ' + Bus + ' Device ' + Dev + ': ID ' + Id + ':' + Pr + ' ' +
           Mf + #10);
  End;
End;

{ ------------------------------ losetup ------------------------------ }

Type
  TLoopInfo = Record
    Device, Inode, RDevice, Offset, SizeLimit : Array[0..1] Of LongInt;
    Number, EncType, EncKeySize, Flags : LongInt;
    FileName : Array[0..63] Of Byte;
    CryptName : Array[0..63] Of Byte;
    EncKey : Array[0..31] Of Byte;
    Init : Array[0..3] Of LongInt;
  End;

Function LoopInfoS(Const Dev : String; Var Li : TLoopInfo) : String;
Var K : LongInt; F : String;
Begin
  F := '';
  K := 0;
  While (K < 64) And (Li.FileName[K] <> 0) Do
  Begin
    F := F + Chr(Li.FileName[K]);
    Inc(K);
  End;
  LoopInfoS := Pad(Dev + ':', 14) + '[' + NumS(Li.Device[0]) + ']:' +
               NumS(Li.Inode[0]) + ' (' + F + ')';
End;

Procedure RunLosetup;
Var
  Fd, Lf, I, K, Ctl, Rc : LongInt;
  Li : TLoopInfo;
  Dev, F : String;
  Ro : Boolean;
  Off : LongInt;
  Any : Boolean;
Begin
  ParseOpts('o');
  Off := 0;
  If Opt[Ord('o')] Then Off := ToNum(OptVal[Ord('o')]);
  Ro := Opt[Ord('r')];
  If Opt[Ord('a')] Or (NArg = 0) And (Not Opt[Ord('f')]) And
     (Not Opt[Ord('d')]) Then
  Begin
    For I := 0 To 15 Do
    Begin
      Dev := '/dev/loop' + NumS(I);
      Fd := SysOpen(Dev, O_RDONLY, 0);
      If Fd < 0 Then Continue;
      FillChar(Li, SizeOf(Li), 0);
      If SysIoctl(Fd, LOOP_GET_STATUS64, Li) = 0 Then
        SysPut(1, LoopInfoS(Dev, Li) + #10);
      SysClose(Fd);
    End;
    Exit;
  End;
  If Opt[Ord('d')] Then
  Begin
    For K := 1 To NArg Do
    Begin
      Fd := SysOpen(Args[K], O_RDONLY, 0);
      If (Fd < 0) Or (SysIoctlL(Fd, LOOP_CLR_FD, 0) < 0) Then
      Begin
        SysPut(2, 'losetup: ' + Args[K] + ': detach failed: ' +
               SysErrorText(SysErrno) + #10);
        SysExit(1);
      End;
      SysClose(Fd);
    End;
    Exit;
  End;
  If Opt[Ord('f')] And (NArg = 0) Then
  Begin
    Ctl := SysOpen('/dev/loop-control', O_RDWR, 0);
    If Ctl >= 0 Then
    Begin
      K := SysIoctlL(Ctl, LOOP_CTL_GET_FREE, 0);
      If K >= 0 Then
      Begin
        SysPut(1, '/dev/loop' + NumS(K) + #10);
        Exit;
      End;
    End;
    For I := 0 To 15 Do
    Begin
      Dev := '/dev/loop' + NumS(I);
      Fd := SysOpen(Dev, O_RDONLY, 0);
      If Fd < 0 Then Continue;
      FillChar(Li, SizeOf(Li), 0);
      If SysIoctl(Fd, LOOP_GET_STATUS64, Li) < 0 Then
      Begin
        SysPut(1, Dev + #10);
        SysClose(Fd);
        Exit;
      End;
      SysClose(Fd);
    End;
    SysPut(2, 'losetup: cannot find an unused loop device' + #10);
    SysExit(1);
  End;
  { losetup [-f] dev fichier }
  If NArg < 2 Then
  Begin
    SysPut(2, PS(Usage[Lang]) + #10);
    SysExit(1);
  End;
  Dev := Args[1];
  F := Args[2];
  Fd := SysOpen(Dev, O_RDWR, 0);
  If Fd < 0 Then Fd := SysOpen(Dev, O_RDONLY, 0);
  If Fd < 0 Then
  Begin
    SysPut(2, 'losetup: ' + Dev + ': ' + SysErrorText(SysErrno) + #10);
    SysExit(1);
  End;
  If Ro Then Lf := SysOpen(F, O_RDONLY, 0) Else Lf := SysOpen(F, O_RDWR, 0);
  If Lf < 0 Then Lf := SysOpen(F, O_RDONLY, 0);
  If Lf < 0 Then
  Begin
    SysPut(2, 'losetup: ' + F + ': ' + SysErrorText(SysErrno) + #10);
    SysExit(1);
  End;
  If SysIoctlL(Fd, LOOP_SET_FD, Lf) < 0 Then
  Begin
    SysPut(2, 'losetup: ' + Dev + ': failed to set up loop device: ' +
           SysErrorText(SysErrno) + #10);
    SysExit(1);
  End;
  FillChar(Li, SizeOf(Li), 0);
  Li.Offset[0] := Off;
  If Ro Then Li.Flags := 1;
  For K := 1 To Length(F) Do
    If K <= 63 Then Li.FileName[K - 1] := Ord(F[K]);
  SysIoctl(Fd, LOOP_SET_STATUS64, Li);
  SysClose(Lf);
  SysClose(Fd);
End;

BEGIN
  Lang := SysLang;
  If (Lang < 1) Or (Lang > 5) Then Lang := 1;
  Prog := SysArgStr(0);
  While Pos('/', Prog) > 0 Do Prog := Copy(Prog, Pos('/', Prog) + 1, 255);
  If Prog = 'lsof' Then RunLsof
  Else If Prog = 'fuser' Then RunFuser
  Else If Prog = 'netstat' Then RunNetstat(False)
  Else If Prog = 'ss' Then RunNetstat(True)
  Else If Prog = 'lspci' Then RunLspci
  Else If Prog = 'lsusb' Then RunLsusb
  Else If Prog = 'losetup' Then RunLosetup
  Else
  Begin
    SysPut(1, PS(Usage[Lang]) + #10);
    SysExit(1);
  End;
END.
