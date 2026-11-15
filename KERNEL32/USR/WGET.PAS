{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2026
  @website(https://www.gladir.com/linux-0)
  @abstract(Target: LPC -3X)
  @description: /bin/wget : telecharge une URL http (wget [-O fichier] [-q]
      http://hote[:port]/chemin).
}

Program WGET;

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
  SysPut(2, 'wget: ' + What + ': ' + SysErrorText(SysErrno) + #10);
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
  Url, Host, Path, Out1, A : String;
  Port, Ip, Sk, I, K, N, Fo, Code, Tot, St : LongInt;
  Quiet : Boolean;
  Sa : TSockAddrIn;
  B : Array[0..4095] Of Char;
  Hdr : String;
  InHdr : Boolean;
  C : Char;
  Last4 : LongInt;

BEGIN
  Quiet := False;
  Out1 := '';
  Url := '';
  I := 1;
  While I < SysArgCount Do
  Begin
    A := SysArgStr(I);
    If (A = '-O') And (I + 1 < SysArgCount) Then
    Begin
      Inc(I);
      Out1 := SysArgStr(I);
    End
    Else If A = '-q' Then Quiet := True
    Else Url := A;
    Inc(I);
  End;
  If Url = '' Then Usage('wget [-q] [-O file] http://host[:port]/path');
  If Copy(Url, 1, 7) = 'http://' Then Url := Copy(Url, 8, 500);
  K := Pos('/', Url);
  If K = 0 Then
  Begin
    Host := Url;
    Path := '/';
  End
  Else
  Begin
    Host := Copy(Url, 1, K - 1);
    Path := Copy(Url, K, 500);
  End;
  Port := 80;
  K := Pos(':', Host);
  If K > 0 Then
  Begin
    Val(Copy(Host, K + 1, 10), Port, Code);
    Host := Copy(Host, 1, K - 1);
  End;
  If Out1 = '' Then
  Begin
    Out1 := BaseOf(Path);
    If Out1 = '' Then Out1 := 'index.html';
  End;
  If Not SysResolve(Host, Ip) Then
  Begin
    SysPut(2, 'wget: unable to resolve host address ' + Host + #10);
    SysExit(1);
  End;
  Sk := SysSocket(2, 1, 0);
  If Sk < 0 Then
  Begin
    Warn('socket');
    SysExit(1);
  End;
  SysSockAddr(Sa, Ip, Port);
  If SysConnect(Sk, LongInt(@Sa), 16) < 0 Then
  Begin
    Warn('connect');
    SysExit(1);
  End;
  Hdr := 'GET ' + Path + ' HTTP/1.0' + #13#10 + 'Host: ' + Host + #13#10 +
         'User-Agent: wget-linux0' + #13#10 + 'Connection: close' + #13#10 +
           #13#10;
  SysWrite(Sk, Hdr[1], Length(Hdr));
  If Out1 = '-' Then Fo := 1 Else Fo := SysCreat(Out1, 420);
  If Fo < 0 Then
  Begin
    Warn(Out1);
    SysExit(1);
  End;
  InHdr := True;
  Last4 := 0;
  Tot := 0;
  St := 0;
  Hdr := '';
  While True Do
  Begin
    N := SysRead(Sk, B, 4096);
    If N <= 0 Then Break;
    K := 0;
    If InHdr Then
    Begin
      While (K < N) And InHdr Do
      Begin
        C := B[K];
        Inc(K);
        If Length(Hdr) < 200 Then Hdr := Hdr + C;
        Last4 := ((Last4 Shl 8) Or Ord(C)) And $FFFFFFFF;
        If Last4 = $0D0A0D0A Then InHdr := False;
      End;
    End;
    If (Not InHdr) And (K < N) Then
    Begin
      SysWrite(Fo, B[K], N - K);
      Tot := Tot + N - K;
    End;
  End;
  SysClose(Sk);
  If Fo <> 1 Then SysClose(Fo);
  If Pos('200', Copy(Hdr, 1, 20)) = 0 Then
  Begin
    SysPut(2, 'wget: server returned: ' + Copy(Hdr, 1, Pos(#13,
      Hdr + #13) - 1) + #10);
    SysExit(1);
  End;
  If Not Quiet Then SysPut(2, Out1 + ' saved (' + NumS(Tot) + ' bytes)' + #10);
END.
