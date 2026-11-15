{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2026
  @website(https://www.gladir.com/linux-0)
  @abstract(Target: LPC -3X)
  @description: /bin/ping : echo ICMP (ping [-c n] [-w s] hote), socket brut.
}

Program PING;

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
  SysPut(2, 'ping: ' + What + ': ' + SysErrorText(SysErrno) + #10);
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

Type
  TPkt = Array[0..127] Of Byte;

Var
  Ip, Cnt, I, R, Got, Sent, Id, Seq, Tmo, K, Code : LongInt;
  A, Host : String;
  Sk : LongInt;
  Sa : TSockAddrIn;
  Pk, Rv : Array[0..127] Of Byte;
  Pf : Array[0..1] Of LongInt;
  Tm0, Tm1 : Array[0..1] Of LongInt;
  Ms, Hl, Ttl, Sum, MinMs, MaxMs, TotMs : LongInt;

Function Cksum(Var B : TPkt; N : LongInt) : LongInt;
Var K, S : LongInt;
Begin
  S := 0;
  K := 0;
  While K + 1 < N Do
  Begin
    S := S + (B[K] Shl 8) + B[K + 1];
    K := K + 2;
  End;
  If K < N Then S := S + (B[K] Shl 8);
  While (S Shr 16) <> 0 Do S := (S And $FFFF) + (S Shr 16);
  Cksum := (Not S) And $FFFF;
End;

Function Stamp : LongInt;
Begin
  SysCall(78, LongInt(@Tm0), 0, 0, 0, 0);
  Stamp := Tm0[0] * 1000 + Tm0[1] Div 1000;
End;

BEGIN
  Cnt := 4;
  Tmo := 3;
  Host := '';
  I := 1;
  While I < SysArgCount Do
  Begin
    A := SysArgStr(I);
    If (A = '-c') And (I + 1 < SysArgCount) Then
    Begin
      Inc(I);
      Val(SysArgStr(I), Cnt, Code);
    End
    Else If (A = '-w') And (I + 1 < SysArgCount) Then
    Begin
      Inc(I);
      Val(SysArgStr(I), Tmo, Code);
    End
    Else Host := A;
    Inc(I);
  End;
  If Host = '' Then Usage('ping [-c count] [-w seconds] host');
  If Not SysResolve(Host, Ip) Then
  Begin
    SysPut(2, 'ping: unknown host ' + Host + #10);
    SysExit(2);
  End;
  Sk := SysSocket(2, 3, 1);
  If Sk < 0 Then
  Begin
    Warn('socket');
    SysExit(2);
  End;
  SysSockAddr(Sa, Ip, 0);
  Id := (SysGetPid And $FFFF);
  Sent := 0;
  Got := 0;
  MinMs := 1000000;
  MaxMs := 0;
  TotMs := 0;
  SysPut(1, 'PING ' + Host + ' (' + SysIpStr(Ip) + '): 56 data bytes' + #10);
  For Seq := 1 To Cnt Do
  Begin
    FillChar(Pk, SizeOf(Pk), 0);
    Pk[0] := 8;
    Pk[4] := Id Shr 8;
    Pk[5] := Id And 255;
    Pk[6] := Seq Shr 8;
    Pk[7] := Seq And 255;
    For K := 8 To 63 Do Pk[K] := K;
    Code := Cksum(Pk, 64);
    Pk[2] := Code Shr 8;
    Pk[3] := Code And 255;
    Ms := Stamp;
    If SysSendTo(Sk, LongInt(@Pk), 64, 0, LongInt(@Sa), 16) < 0 Then
    Begin
      Warn('sendto');
      Continue;
    End;
    Inc(Sent);
    Repeat
      Pf[0] := Sk;
      Pf[1] := 1;
      R := SysPoll(LongInt(@Pf), 1, Tmo * 1000 - (Stamp - Ms));
      If R <= 0 Then Break;
      R := SysRecvFrom(Sk, LongInt(@Rv), 128, 0, 0, 0);
      If R < 28 Then Continue;
      Hl := (Rv[0] And 15) * 4;
      Ttl := Rv[8];
      If (Rv[Hl] = 0) And (Rv[Hl + 4] = (Id Shr 8)) And
         (Rv[Hl + 5] = (Id And 255)) And (Rv[Hl + 7] = (Seq And 255)) Then
      Begin
        Inc(Got);
        K := Stamp - Ms;
        TotMs := TotMs + K;
        If K < MinMs Then MinMs := K;
        If K > MaxMs Then MaxMs := K;
        SysPut(1, NumS(R - Hl) + ' bytes from ' + SysIpStr(Ip) + ': icmp_seq=' +
          NumS(Seq) + ' ttl=' + NumS(Ttl) + ' time=' + NumS(K) + ' ms' + #10);
        Break;
      End;
    Until False;
    If (Seq < Cnt) And (Stamp - Ms < 1000) Then SysSleep(1);
  End;
  SysPut(1, #10 + '--- ' + Host + ' ping statistics ---' + #10);
  SysPut(1, NumS(Sent) + ' packets transmitted, ' + NumS(Got) +
    ' received, ' + NumS(100 - (Got * 100) Div (Sent + Ord(Sent = 0))) +
    '% packet loss' + #10);
  If Got > 0 Then
    SysPut(1, 'round-trip min/avg/max = ' + NumS(MinMs) + '/' +
      NumS(TotMs Div Got) + '/' + NumS(MaxMs) + ' ms' + #10);
  If Got = 0 Then SysExit(1);
END.
