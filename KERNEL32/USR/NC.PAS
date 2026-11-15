{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2026
  @website(https://www.gladir.com/linux-0)
  @abstract(Target: LPC -3X)
  @description: /bin/nc : client et serveur TCP/UDP (nc [-l] [-u] [-p port]
      hote port ; nc -l port).
}

Program NC;

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
  SysPut(2, 'nc: ' + What + ': ' + SysErrorText(SysErrno) + #10);
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
  Listen1, Udp : Boolean;
  Port, Ip, Sk, Cs, I, N, Code, Cnt : LongInt;
  A, Host : String;
  Args : Array[1..4] Of String;
  Sa : TSockAddrIn;
  B : Array[0..4095] Of Char;
  Pf : Array[0..3] Of LongInt;
  Open1 : Boolean;

BEGIN
  Listen1 := False;
  Udp := False;
  Port := 0;
  Cnt := 0;
  I := 1;
  While I < SysArgCount Do
  Begin
    A := SysArgStr(I);
    If A = '-l' Then Listen1 := True
    Else If A = '-u' Then Udp := True
    Else If (A = '-p') And (I + 1 < SysArgCount) Then
    Begin
      Inc(I);
      Val(SysArgStr(I), Port, Code);
    End
    Else If Cnt < 4 Then
    Begin
      Inc(Cnt);
      Args[Cnt] := A;
    End;
    Inc(I);
  End;
  If Listen1 Then
  Begin
    If (Port = 0) And (Cnt >= 1) Then Val(Args[Cnt], Port, Code);
  End
  Else
  Begin
    If Cnt < 2 Then Usage('nc [-u] host port | nc -l [-u] [-p] port');
    Host := Args[1];
    Port := SysServPort(Args[2], '');
    If Port = 0 Then Val(Args[2], Port, Code);
    If Not SysResolve(Host, Ip) Then
    Begin
      SysPut(2, 'nc: unknown host ' + Host + #10);
      SysExit(1);
    End;
  End;
  If Udp Then Sk := SysSocket(2, 2, 0) Else Sk := SysSocket(2, 1, 0);
  If Sk < 0 Then
  Begin
    Warn('socket');
    SysExit(1);
  End;
  If Listen1 Then
  Begin
    SysSockAddr(Sa, 0, Port);
    N := 1;
    SysSetSockOpt(Sk, 1, 2, LongInt(@N), 4);
    If SysBind(Sk, LongInt(@Sa), 16) < 0 Then
    Begin
      Warn('bind');
      SysExit(1);
    End;
    If Udp Then Cs := Sk
    Else
    Begin
      SysListen(Sk, 1);
      Cs := SysAccept(Sk, 0, 0);
      If Cs < 0 Then
      Begin
        Warn('accept');
        SysExit(1);
      End;
    End;
  End
  Else
  Begin
    SysSockAddr(Sa, Ip, Port);
    If SysConnect(Sk, LongInt(@Sa), 16) < 0 Then
    Begin
      Warn('connect');
      SysExit(1);
    End;
    Cs := Sk;
  End;
  Open1 := True;
  While Open1 Do
  Begin
    Pf[0] := Cs;
    Pf[1] := 1;
    Pf[2] := 0;
    Pf[3] := 1;
    N := SysPoll(LongInt(@Pf), 2, 1000);
    If N < 0 Then Break;
    If (Pf[1] Shr 16) <> 0 Then
    Begin
      N := SysRead(Cs, B, 4096);
      If N <= 0 Then Break;
      SysWrite(1, B, N);
    End;
    If (Pf[3] Shr 16) <> 0 Then
    Begin
      N := SysRead(0, B, 4096);
      If N <= 0 Then
      Begin
        SysShutdown(Cs, 1);
        { stdin ferme : attendre la fin de la reponse }
        While True Do
        Begin
          Pf[0] := Cs;
          Pf[1] := 1;
          N := SysPoll(LongInt(@Pf), 1, 2000);
          If N <= 0 Then Break;
          N := SysRead(Cs, B, 4096);
          If N <= 0 Then Break;
          SysWrite(1, B, N);
        End;
        Open1 := False;
      End
      Else SysWrite(Cs, B, N);
    End;
  End;
END.
