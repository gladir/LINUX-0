{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2026
  @website(https://www.gladir.com/linux-0)
  @abstract(Target: LPC -3X)
  @description: tcpdump : capture et decodage des trames par une socket
   AF_PACKET (ETH_P_ALL). Decode Ethernet, ARP, IPv4, IPv6 (en-tete), ICMP,
   TCP (drapeaux, options), UDP, DNS et BOOTP/DHCP.
   tcpdump [-i interface] [-n] [-c N] [-e] [-x|-xx] [-q] [-s N] [-w fichier]
           [-r fichier] [expression]
   Expression : tcp udp icmp arp ip ip6, [src|dst] host H, [src|dst] net N/M,
   [src|dst] port P, less N, greater N, broadcast ; operateurs and or not
   && || ! et parentheses. Les numeros de sequence TCP sont absolus (comme
   avec -S). -w ecrit un fichier pcap (LINKTYPE_ETHERNET) relisible par -r. }

Program Tcpdump;

Const
  MaxBuf = 9999;
  MaxNode = 80;

Var
  Pk : Array[0..MaxBuf] Of Byte;
  PLen, PCap : LongInt;          { longueur reelle, octets captures }
  PSec, PUsec, PType : LongInt;
  { champs analyses }
  PEth, PProto, PSrc, PDst, PSp, PDp : LongInt;
  PIsIp, PIsArp, PIsIp6 : Boolean;
  Numeric, ShowEth, QuietF : Boolean;
  HexLevel, Count, SnapLen : LongInt;
  Iface, WFile, RFile : String;
  Stop : Boolean;
  { arbre du filtre }
  NT, NA, NB, NC : Array[0..MaxNode - 1] Of LongInt;
  NN, Root : LongInt;
  Toks : Array[0..63] Of String[40];
  NTok, TokI : LongInt;

Procedure OnSignal(Sig : LongInt);
Begin
  Stop := True;
End;

Function NumS(V : LongInt) : String;
Var S : String;
Begin
  Str(V, S);
  NumS := S;
End;

Function HexD(D : LongInt) : Char;
Begin
  D := D And 15;
  If D < 10 Then HexD := Chr(48 + D) Else HexD := Chr(87 + D);
End;

Function Hx2(B : LongInt) : String;
Begin
  Hx2 := HexD(B Shr 4) + HexD(B);
End;

Function Hx4(B : LongInt) : String;
Begin
  Hx4 := Hx2(B Shr 8) + Hx2(B);
End;

Function HexV(V : LongInt) : String;
Var S : String; I : LongInt; Z : Boolean;
Begin
  S := '';
  Z := True;
  For I := 7 DownTo 0 Do
    If (((V Shr (I * 4)) And 15) <> 0) Or (Not Z) Or (I = 0) Then
    Begin
      Z := False;
      S := S + HexD(V Shr (I * 4));
    End;
  HexV := '0x' + S;
End;

Function U8(O : LongInt) : LongInt;
Begin
  If (O >= 0) And (O < PCap) Then U8 := Pk[O] Else U8 := 0;
End;

Function U16(O : LongInt) : LongInt;
Begin
  U16 := U8(O) * 256 + U8(O + 1);
End;

Function U32(O : LongInt) : LongInt;
Begin
  U32 := (U8(O) Shl 24) Or (U8(O + 1) Shl 16) Or (U8(O + 2) Shl 8) Or U8(O + 3);
End;

Function U32S(V : LongInt) : String;
Var H, L : LongInt; S : String;
Begin
  { decimal non signe }
  If V >= 0 Then
  Begin
    Str(V, S);
    U32S := S;
    Exit;
  End;
  H := (V Shr 1) And $7FFFFFFF;
  L := V And 1;
  H := H Div 5;
  Str(H, S);
  { H * 10 + reste : calcul direct }
  U32S := S;
  H := ((V Shr 1) And $7FFFFFFF) Mod 5;
  L := H * 2 + L;
  Str(L, S);
  U32S := U32S + S;
End;

Function IpS(V : LongInt) : String;
Begin
  IpS := NumS((V Shr 24) And 255) + '.' + NumS((V Shr 16) And 255) + '.' +
         NumS((V Shr 8) And 255) + '.' + NumS(V And 255);
End;

Function MacS(O : LongInt) : String;
Var K : LongInt; S : String;
Begin
  S := '';
  For K := 0 To 5 Do
  Begin
    If K > 0 Then S := S + ':';
    S := S + Hx2(U8(O + K));
  End;
  MacS := S;
End;

Function Ip6S(O : LongInt) : String;
Var G : Array[0..7] Of LongInt; I, B0, BL, S0, SL : LongInt; R : String;
Begin
  For I := 0 To 7 Do G[I] := U16(O + I * 2);
  { plus longue suite de zeros (>= 2) }
  BL := 0;
  B0 := -1;
  I := 0;
  While I < 8 Do
  Begin
    If G[I] = 0 Then
    Begin
      S0 := I;
      SL := 0;
      While (I < 8) And (G[I] = 0) Do
      Begin
        Inc(SL);
        Inc(I);
      End;
      If SL > BL Then
      Begin
        BL := SL;
        B0 := S0;
      End;
    End
    Else Inc(I);
  End;
  If BL < 2 Then B0 := -1;
  R := '';
  I := 0;
  While I < 8 Do
  Begin
    If I = B0 Then
    Begin
      R := R + '::';
      I := I + BL;
    End
    Else
    Begin
      If (R <> '') And (Copy(R, Length(R), 1) <> ':') Then R := R + ':';
      R := R + Copy(HexV(G[I]), 3, 8);
      Inc(I);
    End;
  End;
  Ip6S := R;
End;

Function PortS(P : LongInt; Const Proto : String) : String;
Begin
  PortS := NumS(P);
  If Numeric Then Exit;
  If P = 53 Then PortS := 'domain'
  Else If (P = 80) And (Proto = 'tcp') Then PortS := 'http'
  Else If (P = 443) And (Proto = 'tcp') Then PortS := 'https'
  Else If (P = 22) And (Proto = 'tcp') Then PortS := 'ssh'
  Else If (P = 23) And (Proto = 'tcp') Then PortS := 'telnet'
  Else If (P = 25) And (Proto = 'tcp') Then PortS := 'smtp'
  Else If P = 67 Then PortS := 'bootps'
  Else If P = 68 Then PortS := 'bootpc'
  Else If P = 123 Then PortS := 'ntp';
End;

{ --- filtre --- }

Procedure Tokenize(Const E : String);
Var I : LongInt; T : String;
Procedure Push;
Begin
  If (T <> '') And (NTok < 64) Then
  Begin
    Toks[NTok] := T;
    Inc(NTok);
  End;
  T := '';
End;
Begin
  NTok := 0;
  T := '';
  For I := 1 To Length(E) Do
    If (E[I] = ' ') Or (E[I] = #9) Then Push
    Else If (E[I] = '(') Or (E[I] = ')') Or (E[I] = '!') Then
    Begin
      Push;
      T := E[I];
      Push;
    End
    Else T := T + E[I];
  Push;
End;

Function Peek : String;
Begin
  If TokI < NTok Then Peek := Toks[TokI] Else Peek := '';
End;

Procedure Bad(Const S : String);
Begin
  SysPut(2, 'tcpdump: expression : ' + S + #10);
  SysExit(1);
End;

Function Node(T, A, B, C : LongInt) : LongInt;
Begin
  If NN >= MaxNode Then Bad('trop complexe');
  NT[NN] := T;
  NA[NN] := A;
  NB[NN] := B;
  NC[NN] := C;
  Node := NN;
  Inc(NN);
End;

Function ParseOr : LongInt; Forward;

Function MaskOf(L : LongInt) : LongInt;
Begin
  If L <= 0 Then MaskOf := 0
  Else If L >= 32 Then MaskOf := -1
  Else MaskOf := -1 Shl (32 - L);
End;

Function ParsePrim : LongInt;
Var T, D, K, V, Ip, M, Err, P, N1 : LongInt; W, A : String; Q : Boolean;
Begin
  W := Peek;
  If W = '(' Then
  Begin
    Inc(TokI);
    N1 := ParseOr;
    If Peek <> ')' Then Bad('parenthese fermante attendue');
    Inc(TokI);
    ParsePrim := N1;
    Exit;
  End;
  If (W = 'not') Or (W = '!') Then
  Begin
    Inc(TokI);
    ParsePrim := Node(7, ParsePrim, 0, 0);
    Exit;
  End;
  P := -1;
  If W = 'ip' Then P := 1
  Else If W = 'ip6' Then P := 2
  Else If W = 'arp' Then P := 3
  Else If W = 'tcp' Then P := 4
  Else If W = 'udp' Then P := 5
  Else If W = 'icmp' Then P := 6;
  If P > 0 Then Inc(TokI);
  W := Peek;
  D := 0;
  If W = 'src' Then
  Begin
    D := 1;
    Inc(TokI);
  End
  Else If W = 'dst' Then
  Begin
    D := 2;
    Inc(TokI);
  End;
  W := Peek;
  If (W = 'host') Or (W = 'net') Or (W = 'port') Then
  Begin
    Inc(TokI);
    A := Peek;
    Inc(TokI);
    If W = 'port' Then
    Begin
      Val(A, V, Err);
      If Err <> 0 Then Bad('port invalide ' + A);
      K := Node(3, D, V, 0);
    End
    Else
    Begin
      M := -1;
      V := Pos('/', A);
      If V > 0 Then
      Begin
        Val(Copy(A, V + 1, 3), M, Err);
        M := MaskOf(M);
        A := Copy(A, 1, V - 1);
      End;
      If Not SysParseIp(A, Ip) Then Bad('adresse invalide ' + A);
      Ip := ((Ip And 255) Shl 24) Or ((Ip And $FF00) Shl 8) Or
            ((Ip Shr 8) And $FF00) Or ((Ip Shr 24) And 255);
      If W = 'host' Then M := -1;
      K := Node(2, D, Ip And M, M);
    End;
    If P > 0 Then K := Node(5, Node(1, P, 0, 0), K, 0);
    ParsePrim := K;
    Exit;
  End;
  If (W = 'less') Or (W = 'greater') Then
  Begin
    Inc(TokI);
    Val(Peek, V, Err);
    Inc(TokI);
    If W = 'less' Then ParsePrim := Node(8, 0, V, 0)
    Else ParsePrim := Node(8, 1, V, 0);
    Exit;
  End;
  If W = 'broadcast' Then
  Begin
    Inc(TokI);
    ParsePrim := Node(9, 0, 0, 0);
    Exit;
  End;
  If P > 0 Then
  Begin
    ParsePrim := Node(1, P, 0, 0);
    Exit;
  End;
  Bad('mot inattendu ''' + W + '''');
End;

Function ParseAnd : LongInt;
Var L, R : LongInt; W : String;
Begin
  L := ParsePrim;
  While True Do
  Begin
    W := Peek;
    If (W = 'and') Or (W = '&&') Then
    Begin
      Inc(TokI);
      R := ParsePrim;
      L := Node(5, L, R, 0);
    End
    Else If (W <> '') And (W <> 'or') And (W <> '||') And (W <> ')') Then
    Begin
      R := ParsePrim;
      L := Node(5, L, R, 0);
    End
    Else Break;
  End;
  ParseAnd := L;
End;

Function ParseOr : LongInt;
Var L, R : LongInt; W : String;
Begin
  L := ParseAnd;
  While True Do
  Begin
    W := Peek;
    If (W = 'or') Or (W = '||') Then
    Begin
      Inc(TokI);
      R := ParseAnd;
      L := Node(6, L, R, 0);
    End
    Else Break;
  End;
  ParseOr := L;
End;

Function Eval(N : LongInt) : Boolean;
Var Ok : Boolean;
Begin
  Eval := False;
  Case NT[N] Of
    1 : Case NA[N] Of
          1 : Eval := PIsIp;
          2 : Eval := PIsIp6;
          3 : Eval := PIsArp;
          4 : Eval := PIsIp And (PProto = 6);
          5 : Eval := PIsIp And (PProto = 17);
          6 : Eval := PIsIp And (PProto = 1);
        End;
    2 : If PIsIp Or PIsArp Then
        Begin
          If NA[N] = 1 Then Eval := (PSrc And NC[N]) = NB[N]
          Else If NA[N] = 2 Then Eval := (PDst And NC[N]) = NB[N]
          Else Eval := ((PSrc And NC[N]) = NB[N]) Or
                       ((PDst And NC[N]) = NB[N]);
        End;
    3 : If PIsIp And ((PProto = 6) Or (PProto = 17)) Then
        Begin
          If NA[N] = 1 Then Eval := PSp = NB[N]
          Else If NA[N] = 2 Then Eval := PDp = NB[N]
          Else Eval := (PSp = NB[N]) Or (PDp = NB[N]);
        End;
    5 : Eval := Eval(NA[N]) And Eval(NB[N]);
    6 : Eval := Eval(NA[N]) Or Eval(NB[N]);
    7 : Eval := Not Eval(NA[N]);
    8 : If NA[N] = 0 Then Eval := PLen <= NB[N] Else Eval := PLen >= NB[N];
    9 : Eval := (U8(0) And U8(1) And U8(2) And U8(3) And U8(4) And U8(5)) =
                255;
  End;
End;

{ --- analyse et affichage --- }

Procedure Analyse;
Var Hl : LongInt;
Begin
  PIsIp := False;
  PIsArp := False;
  PIsIp6 := False;
  PProto := 0;
  PSrc := 0;
  PDst := 0;
  PSp := -1;
  PDp := -1;
  PEth := U16(12);
  If PEth = $0800 Then
  Begin
    PIsIp := True;
    Hl := (U8(14) And 15) * 4;
    PProto := U8(23);
    PSrc := U32(26);
    PDst := U32(30);
    If ((PProto = 6) Or (PProto = 17)) And ((U16(20) And $1FFF) = 0) Then
    Begin
      PSp := U16(14 + Hl);
      PDp := U16(16 + Hl);
    End;
  End
  Else If PEth = $0806 Then
  Begin
    PIsArp := True;
    PSrc := U32(28);
    PDst := U32(38);
  End
  Else If PEth = $86DD Then
  Begin
    PIsIp6 := True;
    PProto := U8(20);
  End;
End;

Function QName(Base, Off : LongInt; Var Nxt : LongInt) : String;
Var R : String; L, P, Guard : LongInt; Jumped : Boolean;
Begin
  R := '';
  P := Off;
  Nxt := Off;
  Jumped := False;
  Guard := 0;
  While Guard < 40 Do
  Begin
    Inc(Guard);
    L := U8(P);
    If L = 0 Then
    Begin
      If Not Jumped Then Nxt := P + 1;
      Break;
    End;
    If (L And $C0) = $C0 Then
    Begin
      If Not Jumped Then Nxt := P + 2;
      Jumped := True;
      P := Base + (((L And $3F) Shl 8) Or U8(P + 1));
      Continue;
    End;
    Inc(P);
    While L > 0 Do
    Begin
      R := R + Chr(U8(P));
      Inc(P);
      Dec(L);
    End;
    R := R + '.';
  End;
  If R = '' Then R := '.';
  QName := R;
End;

Function DnsType(T : LongInt) : String;
Begin
  Case T Of
    1 : DnsType := 'A';
    2 : DnsType := 'NS';
    5 : DnsType := 'CNAME';
    6 : DnsType := 'SOA';
    12 : DnsType := 'PTR';
    15 : DnsType := 'MX';
    16 : DnsType := 'TXT';
    28 : DnsType := 'AAAA';
    33 : DnsType := 'SRV';
    255 : DnsType := 'ANY';
  Else
    DnsType := 'Type' + NumS(T);
  End;
End;

Function DnsText(O, Len : LongInt) : String;
Var Base, Fl, Qd, An, Ns, Ar, I, P, T, Rl, Nx, Rc : LongInt; S, A : String;
Begin
  Base := O;
  Fl := U16(O + 2);
  Qd := U16(O + 4);
  An := U16(O + 6);
  Ns := U16(O + 8);
  Ar := U16(O + 10);
  S := NumS(U16(O));
  P := O + 12;
  If (Fl And $8000) = 0 Then
  Begin
    If (Fl And $100) <> 0 Then S := S + '+';
    If Qd > 0 Then
    Begin
      A := QName(Base, P, Nx);
      S := S + ' ' + DnsType(U16(Nx)) + '? ' + A;
    End;
    DnsText := S + ' (' + NumS(Len) + ')';
    Exit;
  End;
  Rc := Fl And 15;
  If Rc = 3 Then S := S + ' NXDomain'
  Else If Rc = 2 Then S := S + ' ServFail'
  Else If Rc = 5 Then S := S + ' Refused'
  Else If Rc <> 0 Then S := S + ' Rcode' + NumS(Rc);
  S := S + ' ' + NumS(An) + '/' + NumS(Ns) + '/' + NumS(Ar);
  For I := 1 To Qd Do
  Begin
    A := QName(Base, P, Nx);
    P := Nx + 4;
  End;
  For I := 1 To An Do
  Begin
    If P >= PCap Then Break;
    A := QName(Base, P, Nx);
    T := U16(Nx);
    Rl := U16(Nx + 8);
    P := Nx + 10;
    If I > 1 Then S := S + ',';
    S := S + ' ' + DnsType(T) + ' ';
    If (T = 1) And (Rl = 4) Then S := S + IpS(U32(P))
    Else If T = 28 Then S := S + Ip6S(P)
    Else If (T = 2) Or (T = 5) Or (T = 12) Then S := S + QName(Base, P, Nx)
    Else If T = 15 Then S := S + NumS(U16(P)) + ' ' + QName(Base, P + 2, Nx)
    Else S := S + '...';
    P := P + Rl;
  End;
  DnsText := S + ' (' + NumS(Len) + ')';
End;

Function TcpOpts(O, E : LongInt) : String;
Var S : String; K, L : LongInt;
Procedure Add(Const X : String);
Begin
  If S <> '' Then S := S + ',';
  S := S + X;
End;
Begin
  S := '';
  K := O;
  While K < E Do
  Begin
    L := U8(K);
    If L = 0 Then
    Begin
      Add('eol');
      Break;
    End
    Else If L = 1 Then
    Begin
      Add('nop');
      Inc(K);
    End
    Else
    Begin
      If (U8(K + 1) < 2) Or (K + U8(K + 1) > E) Then Break;
      Case L Of
        2 : Add('mss ' + NumS(U16(K + 2)));
        3 : Add('wscale ' + NumS(U8(K + 2)));
        4 : Add('sackOK');
        8 : Add('TS val ' + U32S(U32(K + 2)) + ' ecr ' + U32S(U32(K + 6)));
      Else
        Add('unknown-' + NumS(L));
      End;
      K := K + U8(K + 1);
    End;
  End;
  TcpOpts := S;
End;

Function IcmpText(O, Len : LongInt) : String;
Var T, C : LongInt; S : String;
Begin
  T := U8(O);
  C := U8(O + 1);
  Case T Of
    8 : S := 'echo request, id ' + NumS(U16(O + 4)) + ', seq ' +
             NumS(U16(O + 6));
    0 : S := 'echo reply, id ' + NumS(U16(O + 4)) + ', seq ' +
             NumS(U16(O + 6));
    3 : Case C Of
          0 : S := 'net unreachable';
          1 : S := 'host unreachable';
          2 : S := 'protocol unreachable';
          3 : S := 'port unreachable';
          4 : S := 'unreachable - need to frag';
        Else
          S := 'unreachable (code ' + NumS(C) + ')';
        End;
    11 : S := 'time exceeded in-transit';
    5 : S := 'redirect';
    4 : S := 'source quench';
  Else
    S := 'type ' + NumS(T) + ' code ' + NumS(C);
  End;
  IcmpText := S + ', length ' + NumS(Len);
End;

Function L4Text(Hl : LongInt) : String;
Var O, Tl, Tcl, Fl, Dl, Seq, Ack : LongInt; S, F, Opt, Pn : String;
Begin
  L4Text := '';
  O := 14 + Hl;
  Tl := U16(16);
  Case PProto Of
    1 : L4Text := 'ICMP ' + IcmpText(O, Tl - Hl);
    6 : Begin
          If O + 20 > PCap Then
          Begin
            L4Text := '[|tcp]';
            Exit;
          End;
          Tcl := (U8(O + 12) Shr 4) * 4;
          Fl := U8(O + 13);
          Dl := Tl - Hl - Tcl;
          F := '';
          If (Fl And 2) <> 0 Then F := F + 'S';
          If (Fl And 1) <> 0 Then F := F + 'F';
          If (Fl And 8) <> 0 Then F := F + 'P';
          If (Fl And 4) <> 0 Then F := F + 'R';
          If (Fl And 32) <> 0 Then F := F + 'U';
          If (Fl And 64) <> 0 Then F := F + 'E';
          If (Fl And 128) <> 0 Then F := F + 'W';
          If (Fl And 16) <> 0 Then F := F + '.';
          If F = '' Then F := 'none';
          Seq := U32(O + 4);
          Ack := U32(O + 8);
          S := 'Flags [' + F + '], ';
          If Dl > 0 Then
            S := S + 'seq ' + U32S(Seq) + ':' + U32S(Seq + Dl)
          Else S := S + 'seq ' + U32S(Seq);
          If (Fl And 16) <> 0 Then S := S + ', ack ' + U32S(Ack);
          S := S + ', win ' + NumS(U16(O + 14));
          If (Fl And 32) <> 0 Then S := S + ', urg ' + NumS(U16(O + 18));
          Opt := '';
          If Tcl > 20 Then Opt := TcpOpts(O + 20, O + Tcl);
          If Opt <> '' Then S := S + ', options [' + Opt + ']';
          L4Text := S + ', length ' + NumS(Dl);
        End;
    17 : Begin
           If O + 8 > PCap Then
           Begin
             L4Text := '[|udp]';
             Exit;
           End;
           Dl := U16(O + 4) - 8;
           If (PSp = 53) Or (PDp = 53) Then
           Begin
             If Dl >= 12 Then L4Text := DnsText(O + 8, Dl)
             Else L4Text := 'UDP, length ' + NumS(Dl);
           End
           Else If ((PSp = 67) And (PDp = 68)) Or
                   ((PSp = 68) And (PDp = 67)) Then
           Begin
             If U8(O + 8) = 1 Then
               L4Text := 'BOOTP/DHCP, Request from ' + MacS(O + 8 + 28) +
                         ', length ' + NumS(Dl)
             Else L4Text := 'BOOTP/DHCP, Reply, length ' + NumS(Dl);
           End
           Else L4Text := 'UDP, length ' + NumS(Dl);
         End;
  Else
    L4Text := 'ip-proto-' + NumS(PProto) + ' ' + NumS(Tl - Hl);
  End;
End;

Function EthName(T : LongInt) : String;
Begin
  Case T Of
    $0800 : EthName := 'IPv4';
    $0806 : EthName := 'ARP';
    $86DD : EthName := 'IPv6';
  Else
    EthName := 'Unknown';
  End;
End;

Function TimeS : String;
Var L, H, M, S : LongInt;
Begin
  L := PSec + LnxTzAt(PSec);
  L := L Mod 86400;
  If L < 0 Then L := L + 86400;
  H := L Div 3600;
  M := (L Mod 3600) Div 60;
  S := L Mod 60;
  TimeS := Copy(NumS(100 + H), 2, 2) + ':' + Copy(NumS(100 + M), 2, 2) + ':' +
           Copy(NumS(100 + S), 2, 2) + '.' + Copy(NumS(1000000 + PUsec), 2, 6);
End;

Procedure ShowPacket;
Var Hl, Tl, Base : LongInt; Src : String;
Begin
  Analyse;
  Src := TimeS + ' ';
  If ShowEth Then
    Src := Src + MacS(6) + ' > ' + MacS(0) + ', ethertype ' + EthName(PEth) +
           ' (0x' + Hx4(PEth) + '), length ' + NumS(PLen) + ': ';
  If PIsArp Then
  Begin
    If U16(20) = 1 Then
      Src := Src + 'ARP, Request who-has ' + IpS(U32(38)) + ' tell ' +
             IpS(U32(28)) + ', length ' + NumS(PLen - 14)
    Else If U16(20) = 2 Then
      Src := Src + 'ARP, Reply ' + IpS(U32(28)) + ' is-at ' + MacS(22) +
             ', length ' + NumS(PLen - 14)
    Else Src := Src + 'ARP, length ' + NumS(PLen - 14);
  End
  Else If PIsIp Then
  Begin
    Hl := (U8(14) And 15) * 4;
    Tl := U16(16);
    If QuietF And (PSp >= 0) And (PProto = 6) Then
      Src := Src + 'IP ' + IpS(PSrc) + '.' + PortS(PSp, 'tcp') + ' > ' +
             IpS(PDst) + '.' + PortS(PDp, 'tcp') + ': tcp ' +
             NumS(Tl - Hl - (U8(14 + Hl + 12) Shr 4) * 4)
    Else If QuietF And (PSp >= 0) Then
      Src := Src + 'IP ' + IpS(PSrc) + '.' + PortS(PSp, 'udp') + ' > ' +
             IpS(PDst) + '.' + PortS(PDp, 'udp') + ': UDP, length ' +
             NumS(Tl - Hl - 8)
    Else If QuietF Then
      Src := Src + 'IP ' + IpS(PSrc) + ' > ' + IpS(PDst) + ': ' +
             NumS(Tl - Hl)
    Else If PSp >= 0 Then
    Begin
      If PProto = 6 Then
        Src := Src + 'IP ' + IpS(PSrc) + '.' + PortS(PSp, 'tcp') + ' > ' +
               IpS(PDst) + '.' + PortS(PDp, 'tcp') + ': ' + L4Text(Hl)
      Else
        Src := Src + 'IP ' + IpS(PSrc) + '.' + PortS(PSp, 'udp') + ' > ' +
               IpS(PDst) + '.' + PortS(PDp, 'udp') + ': ' + L4Text(Hl);
    End
    Else Src := Src + 'IP ' + IpS(PSrc) + ' > ' + IpS(PDst) + ': ' +
                L4Text(Hl);
  End
  Else If PIsIp6 Then
    Src := Src + 'IP6 ' + Ip6S(22) + ' > ' + Ip6S(38) + ': ' +
           'ip6-proto-' + NumS(PProto) + ', length ' + NumS(U16(18))
  Else
    Src := Src + 'ethertype ' + HexV(PEth) + ', length ' + NumS(PLen);
  SysPut(1, Src + #10);
  If HexLevel > 0 Then
  Begin
    Base := 14;
    If HexLevel > 1 Then Base := 0;
    Hl := Base;
    While Hl < PCap Do
    Begin
      Src := #9 + '0x' + Hx4(Hl - Base) + ':  ';
      Tl := 0;
      While (Tl < 16) And (Hl + Tl < PCap) Do
      Begin
        Src := Src + Hx2(Pk[Hl + Tl]);
        If (Tl And 1) = 1 Then Src := Src + ' ';
        Inc(Tl);
      End;
      SysPut(1, Src + #10);
      Hl := Hl + 16;
    End;
  End;
End;

{ --- pcap --- }

Procedure PutLE(Fd, V : LongInt);
Var B : Array[0..3] Of Byte;
Begin
  B[0] := V And 255;
  B[1] := (V Shr 8) And 255;
  B[2] := (V Shr 16) And 255;
  B[3] := (V Shr 24) And 255;
  SysWrite(Fd, B[0], 4);
End;

Procedure WriteHeader(Fd : LongInt);
Var B : Array[0..3] Of Byte;
Begin
  PutLE(Fd, $A1B2C3D4);
  B[0] := 2; B[1] := 0; B[2] := 4; B[3] := 0;
  SysWrite(Fd, B[0], 4);
  PutLE(Fd, 0);
  PutLE(Fd, 0);
  PutLE(Fd, SnapLen);
  PutLE(Fd, 1);
End;

Procedure WritePacket(Fd : LongInt);
Begin
  PutLE(Fd, PSec);
  PutLE(Fd, PUsec);
  PutLE(Fd, PCap);
  PutLE(Fd, PLen);
  SysWrite(Fd, Pk[0], PCap);
End;

Function ReadAll(Fd : LongInt; Var B; N : LongInt) : Boolean;
Var Got, R : LongInt;
Begin
  Got := 0;
  While Got < N Do
  Begin
    R := LnxSys3(3, Fd, LongInt(@B) + Got, N - Got);
    If R <= 0 Then
    Begin
      ReadAll := False;
      Exit;
    End;
    Got := Got + R;
  End;
  ReadAll := True;
End;

Function LE32(Var B; O : LongInt) : LongInt;
Var P : LongInt;
Begin
  P := LongInt(@B) + O;
  LE32 := Mem[0:P] Or (Mem[0:P + 1] Shl 8) Or (Mem[0:P + 2] Shl 16) Or
          (Mem[0:P + 3] Shl 24);
End;

Procedure Usage;
Begin
  SysPut(2, 'Usage: tcpdump [-i interface] [-nqexl] [-c count] [-s snaplen]' +
         ' [-w file] [-r file] [expression]' + #10);
  SysExit(1);
End;

Var
  I, J, K, Sk, Rd, Wd, Got, Cap, Ix : LongInt;
  A, Expr, V : String;
  Ifr : Array[0..9] Of LongInt;
  Ll : Array[0..4] Of LongInt;
  LlLen : LongInt;
  Hdr : Array[0..5] Of LongInt;
  Rec : Array[0..3] Of LongInt;
  C : Char;
  Matched, Seen : LongInt;
Begin
  Numeric := False;
  ShowEth := False;
  QuietF := False;
  HexLevel := 0;
  Count := 0;
  SnapLen := 65535;
  Iface := '';
  WFile := '';
  RFile := '';
  Stop := False;
  Expr := '';
  Matched := 0;
  Seen := 0;
  I := 1;
  While I < SysArgCount Do
  Begin
    A := SysArgStr(I);
    If (A <> '') And (A[1] = '-') And (Length(A) > 1) Then
    Begin
      J := 2;
      While J <= Length(A) Do
      Begin
        C := A[J];
        Inc(J);
        If (C = 'i') Or (C = 'c') Or (C = 's') Or (C = 'w') Or (C = 'r') Then
        Begin
          If J <= Length(A) Then V := Copy(A, J, 200)
          Else
          Begin
            Inc(I);
            If I >= SysArgCount Then Usage;
            V := SysArgStr(I);
          End;
          J := Length(A) + 1;
          If C = 'i' Then Iface := V
          Else If C = 'w' Then WFile := V
          Else If C = 'r' Then RFile := V
          Else
          Begin
            K := 0;
            For Ix := 1 To Length(V) Do K := K * 10 + Ord(V[Ix]) - 48;
            If C = 'c' Then Count := K
            Else
            Begin
              SnapLen := K;
              If SnapLen = 0 Then SnapLen := 262144;
            End;
          End;
        End
        Else If C = 'n' Then Numeric := True
        Else If C = 'e' Then ShowEth := True
        Else If C = 'q' Then QuietF := True
        Else If C = 'x' Then Inc(HexLevel)
        Else If C = 'X' Then Inc(HexLevel)
        Else If (C = 'l') Or (C = 'v') Or (C = 'p') Or (C = 'S') Or
                (C = 't') Or (C = 'U') Then
        Begin
        End
        Else Usage;
      End;
    End
    Else
    Begin
      If Expr <> '' Then Expr := Expr + ' ';
      Expr := Expr + A;
    End;
    Inc(I);
  End;
  NN := 0;
  Root := -1;
  If Expr <> '' Then
  Begin
    Tokenize(Expr);
    TokI := 0;
    Root := ParseOr;
    If TokI < NTok Then Bad('mot inattendu ''' + Peek + '''');
  End;
  Wd := -1;
  If WFile <> '' Then
  Begin
    If WFile = '-' Then Wd := 1
    Else Wd := SysOpen(WFile, $241, 420);
    If Wd < 0 Then
    Begin
      SysPut(2, 'tcpdump: ' + WFile + ': ' + SysErrorText(SysErrno) + #10);
      SysExit(1);
    End;
    WriteHeader(Wd);
  End;
  If RFile <> '' Then
  Begin
    Rd := SysOpen(RFile, 0, 0);
    If Rd < 0 Then
    Begin
      SysPut(2, 'tcpdump: ' + RFile + ': ' + SysErrorText(SysErrno) + #10);
      SysExit(1);
    End;
    If (Not ReadAll(Rd, Hdr, 24)) Or (LE32(Hdr, 0) <> $A1B2C3D4) Then
    Begin
      SysPut(2, 'tcpdump: ' + RFile + ': pas un fichier pcap' + #10);
      SysExit(1);
    End;
    SysPut(2, 'reading from file ' + RFile + ', link-type EN10MB (Ethernet)' +
           #10);
    While ReadAll(Rd, Rec, 16) Do
    Begin
      PSec := LE32(Rec, 0);
      PUsec := LE32(Rec, 4);
      Cap := LE32(Rec, 8);
      PLen := LE32(Rec, 12);
      If (Cap < 0) Or (Cap > MaxBuf) Then Break;
      If Not ReadAll(Rd, Pk, Cap) Then Break;
      PCap := Cap;
      Inc(Seen);
      Analyse;
      If (Root < 0) Or Eval(Root) Then
      Begin
        Inc(Matched);
        If Wd >= 0 Then WritePacket(Wd) Else ShowPacket;
        If (Count > 0) And (Matched >= Count) Then Break;
      End;
    End;
    SysExit(0);
  End;
  Sk := SysSocket(17, 3, $0300);
  If Sk < 0 Then
  Begin
    SysPut(2, 'tcpdump: socket AF_PACKET : ' + SysErrorText(SysErrno) + #10);
    SysExit(1);
  End;
  If (Iface <> '') And (Iface <> 'any') Then
  Begin
    K := SysSocket(2, 2, 0);
    For J := 0 To 9 Do Ifr[J] := 0;
    For J := 1 To Length(Iface) Do
      Mem[0:LongInt(@Ifr) + J - 1] := Ord(Iface[J]);
    If SysIoctl(K, $8933, Ifr) < 0 Then
    Begin
      SysPut(2, 'tcpdump: ' + Iface + ': No such device exists' + #10);
      SysExit(1);
    End;
    Ix := Ifr[4];
    SysClose(K);
    Ll[0] := 0;
    Ll[1] := 0;
    Ll[2] := 0;
    Ll[3] := 0;
    Ll[4] := 0;
    Mem[0:LongInt(@Ll)] := 17;
    Mem[0:LongInt(@Ll) + 1] := 0;
    Mem[0:LongInt(@Ll) + 2] := 0;
    Mem[0:LongInt(@Ll) + 3] := 3;
    Ll[1] := Ix;
    If SysBind(Sk, LongInt(@Ll), 20) < 0 Then
    Begin
      SysPut(2, 'tcpdump: bind ' + Iface + ' : ' + SysErrorText(SysErrno) +
             #10);
      SysExit(1);
    End;
    SysPut(2, 'tcpdump: listening on ' + Iface +
           ', link-type EN10MB (Ethernet), snapshot length ' +
           NumS(SnapLen) + ' bytes' + #10);
  End
  Else
    SysPut(2, 'tcpdump: listening on any, link-type EN10MB (Ethernet), ' +
           'snapshot length ' + NumS(SnapLen) + ' bytes' + #10);
  SysSigAction(2, LongInt(@OnSignal), 0);
  SysSigAction(15, LongInt(@OnSignal), 0);
  While Not Stop Do
  Begin
    LlLen := 20;
    Got := SysRecvFrom(Sk, LongInt(@Pk), MaxBuf + 1, 0, LongInt(@Ll),
                       LongInt(@LlLen));
    If Got < 0 Then
    Begin
      If SysErrno = 4 Then Continue;
      Break;
    End;
    PLen := Got;
    PCap := Got;
    If PCap > SnapLen Then PCap := SnapLen;
    PType := Mem[0:LongInt(@Ll) + 10];
    If (PType = 4) And (Mem[0:LongInt(@Ll) + 8] = 4) And
       (Mem[0:LongInt(@Ll) + 9] = 3) Then Continue;
    LnxSys3(78, LongInt(@LnxTmp), 0, 0);
    PSec := LnxTmp[0];
    PUsec := LnxTmp[1];
    Inc(Seen);
    Analyse;
    If (Root < 0) Or Eval(Root) Then
    Begin
      Inc(Matched);
      If Wd >= 0 Then WritePacket(Wd) Else ShowPacket;
      If (Count > 0) And (Matched >= Count) Then Stop := True;
    End;
  End;
  SysPut(2, NumS(Matched) + ' packets captured' + #10 + NumS(Seen) +
         ' packets received by filter' + #10 +
         '0 packets dropped by kernel' + #10);
  SysExit(0);
End.
