{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2026
  @website(https://www.gladir.com/linux-0)
  @abstract(Target: LPC -3X)
  @description: telnet, ftp, httpd, traceroute (un seul programme, nom lu dans
      argv[0]). telnet hote [port] : negociation IAC (ECHO distant gere par le
      terminal local), ftp [-n] hote [port] : client en mode passif (user pass
      ls dir cd pwd get put mget mdelete mkdir rmdir delete rename binary
      ascii lcd ! quit), httpd [-p port] [-d racine] [-f] : serveur HTTP/1.0
      statique (GET, HEAD, index.html, listing de repertoire), traceroute
      [-m sauts] [-w s] hote : sondes UDP a TTL croissant, reponses ICMP
      (socket brute).
}

Program NETUTIL;

Const
  Usage : Array[1..5] Of PChar = (
    'Usage : telnet|ftp|httpd|traceroute hote [port]',
    'Usage: telnet|ftp|httpd|traceroute host [port]',
    'Aufruf: telnet|ftp|httpd|traceroute Host [Port]',
    'Uso: telnet|ftp|httpd|traceroute host [puerto]',
    'Uso: telnet|ftp|httpd|traceroute host [porta]');

Var
  Lang : LongInt;
  Prog : String;
  Buf : Array[0..8191] Of Byte;

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

Procedure Die(Const S : String; Rc : LongInt);
Begin
  SysPut(2, Prog + ': ' + S + #10);
  SysExit(Rc);
End;

Function ToNum(Const S : String) : LongInt;
Var V, C : LongInt;
Begin
  Val(S, V, C);
  If C <> 0 Then V := -1;
  ToNum := V;
End;

{ connexion TCP : retourne le descripteur ou -1 }
Function Dial(Const Host : String; Port : LongInt) : LongInt;
Var Ip, Sk : LongInt; Sa : TSockAddrIn;
Begin
  Dial := -1;
  If Not SysResolve(Host, Ip) Then
  Begin
    SysPut(2, Prog + ': ' + Host + ': Name or service not known' + #10);
    Exit;
  End;
  Sk := SysSocket(2, 1, 0);
  If Sk < 0 Then Exit;
  SysSockAddr(Sa, Ip, Port);
  If SysConnect(Sk, LongInt(@Sa), 16) < 0 Then
  Begin
    SysPut(2, Prog + ': Unable to connect to ' + Host + ': ' +
           SysErrorText(SysErrno) + #10);
    SysClose(Sk);
    Exit;
  End;
  Dial := Sk;
End;

Function ReadFdLine(Fd : LongInt; Var L : String) : Boolean;
Var B : Byte; N : LongInt;
Begin
  L := '';
  ReadFdLine := False;
  While True Do
  Begin
    N := SysRead(Fd, B, 1);
    If N <= 0 Then Break;
    ReadFdLine := True;
    If B = 10 Then Break;
    If (B <> 13) And (Length(L) < 250) Then L := L + Chr(B);
  End;
End;

{ ------------------------------ telnet ------------------------------ }

Const
  IAC = 255; DONT = 254; DO_ = 253; WONT = 252; WILL = 251; SB = 250; SE = 240;
  OPT_ECHO = 1; OPT_SGA = 3; OPT_TTYPE = 24;

Procedure RunTelnet;
Var
  Host : String;
  Port, Sk, N, I, State, Cmd, Opt, K : LongInt;
  Pf : Array[0..3] Of LongInt;
  T, Saved : TSysTermios;
  HaveT, EchoOff : Boolean;
  Out : Array[0..8191] Of Byte;
  On_ : LongInt;
  Rsp : Array[0..2] Of Byte;
Begin
  If SysArgCount < 2 Then Die(PS(Usage[Lang]), 1);
  Host := SysArgStr(1);
  Port := 23;
  If SysArgCount > 2 Then Port := ToNum(SysArgStr(2));
  Sk := Dial(Host, Port);
  If Sk < 0 Then SysExit(1);
  SysPut(1, 'Connected to ' + Host + '.' + #10 +
         'Escape character is ''^]''.' + #10);
  HaveT := SysTcGetAttr(0, Saved) = 0;
  T := Saved;
  EchoOff := False;
  State := 0;
  While True Do
  Begin
    Pf[0] := 0; Pf[1] := 1;
    Pf[2] := Sk; Pf[3] := 1;
    N := SysPoll(LongInt(@Pf), 2, 1000);
    If N < 0 Then Break;
    If (Pf[3] Shr 16) <> 0 Then
    Begin
      N := SysRead(Sk, Buf[0], 8192);
      If N <= 0 Then Break;
      On_ := 0;
      For I := 0 To N - 1 Do
      Begin
        Case State Of
          0 : If Buf[I] = IAC Then State := 1
              Else
              Begin
                Out[On_] := Buf[I];
                Inc(On_);
              End;
          1 : If Buf[I] = IAC Then
              Begin
                Out[On_] := IAC;
                Inc(On_);
                State := 0;
              End
              Else If (Buf[I] >= WILL) And (Buf[I] <= DONT) Then
              Begin
                Cmd := Buf[I];
                State := 2;
              End
              Else If Buf[I] = SB Then State := 3
              Else State := 0;
          2 : Begin
                Opt := Buf[I];
                State := 0;
                Rsp[0] := IAC;
                Rsp[2] := Opt;
                If Cmd = WILL Then
                Begin
                  If Opt = OPT_ECHO Then
                  Begin
                    Rsp[1] := DO_;
                    If HaveT Then
                    Begin
                      T.LFlag := T.LFlag And Not TTY_ECHO;
                      SysTcSetAttr(0, 1, T);
                    End;
                    EchoOff := True;
                  End
                  Else If Opt = OPT_SGA Then Rsp[1] := DO_
                  Else Rsp[1] := DONT;
                  SysWrite(Sk, Rsp[0], 3);
                End
                Else If Cmd = WONT Then
                Begin
                  If (Opt = OPT_ECHO) And HaveT Then
                  Begin
                    SysTcSetAttr(0, 1, Saved);
                    EchoOff := False;
                  End;
                  Rsp[1] := DONT;
                  SysWrite(Sk, Rsp[0], 3);
                End
                Else If Cmd = DO_ Then
                Begin
                  If Opt = OPT_SGA Then Rsp[1] := WILL Else Rsp[1] := WONT;
                  SysWrite(Sk, Rsp[0], 3);
                End;
              End;
          3 : If Buf[I] = IAC Then State := 4;
          4 : If Buf[I] = SE Then State := 0 Else State := 3;
        End;
      End;
      If On_ > 0 Then SysWrite(1, Out[0], On_);
    End;
    If (Pf[1] Shr 16) <> 0 Then
    Begin
      N := SysRead(0, Buf[0], 8192);
      If N <= 0 Then
      Begin
        SysShutdown(Sk, 1);
        { laisser le serveur finir d'envoyer }
        While SysPoll(LongInt(@Pf[2]), 1, 1500) > 0 Do
        Begin
          N := SysRead(Sk, Buf[0], 8192);
          If N <= 0 Then Break;
          SysWrite(1, Buf[0], N);
        End;
        Break;
      End;
      { LF -> CR LF, IAC double }
      On_ := 0;
      For I := 0 To N - 1 Do
      Begin
        If Buf[I] = 10 Then
        Begin
          Out[On_] := 13;
          Inc(On_);
          Out[On_] := 10;
          Inc(On_);
        End
        Else
        Begin
          Out[On_] := Buf[I];
          Inc(On_);
          If Buf[I] = IAC Then
          Begin
            Out[On_] := IAC;
            Inc(On_);
          End;
        End;
      End;
      SysWrite(Sk, Out[0], On_);
    End;
  End;
  If HaveT Then SysTcSetAttr(0, 1, Saved);
  SysPut(1, 'Connection closed by foreign host.' + #10);
  SysClose(Sk);
End;

{ ------------------------------ ftp ------------------------------ }

Var
  Ctl : LongInt;
  Host_ : String;
  Binary : Boolean;
  Verbose : Boolean;

{ lit une reponse (lignes multiples), retourne le code }
Function Reply(Echo : Boolean) : LongInt;
Var L : String; Code : LongInt; Multi : Boolean;
Begin
  Reply := -1;
  Multi := False;
  While ReadFdLine(Ctl, L) Do
  Begin
    If Echo Then SysPut(1, L + #10);
    If Length(L) >= 4 Then
    Begin
      Code := ToNum(Copy(L, 1, 3));
      If Code > 0 Then
      Begin
        If L[4] = '-' Then
        Begin
          Multi := True;
          Reply := Code;
        End
        Else If L[4] = ' ' Then
        Begin
          Reply := Code;
          Exit;
        End;
      End;
    End;
  End;
End;

Function Cmd_(Const C : String; Echo : Boolean) : LongInt;
Begin
  SysPut(Ctl, C + #13#10);
  Cmd_ := Reply(Echo);
End;

{ ouvre la connexion de donnees (mode passif) }
Function DataConn(Const C : String) : LongInt;
Var L : String; K, P, A, B, Code, Sk : LongInt; N : Array[1..6] Of LongInt;
    Sa : TSockAddrIn; Ip : LongInt;
Begin
  DataConn := -1;
  SysPut(Ctl, 'PASV' + #13#10);
  If Not ReadFdLine(Ctl, L) Then Exit;
  If Copy(L, 1, 3) <> '227' Then
  Begin
    SysPut(1, L + #10);
    Exit;
  End;
  K := Pos('(', L);
  If K = 0 Then Exit;
  Delete(L, 1, K);
  For K := 1 To 6 Do
  Begin
    P := 1;
    While (P <= Length(L)) And (L[P] >= '0') And (L[P] <= '9') Do Inc(P);
    N[K] := ToNum(Copy(L, 1, P - 1));
    Delete(L, 1, P);
  End;
  Ip := SysIp(N[1], N[2], N[3], N[4]);
  Sk := SysSocket(2, 1, 0);
  SysSockAddr(Sa, Ip, N[5] * 256 + N[6]);
  If SysConnect(Sk, LongInt(@Sa), 16) < 0 Then
  Begin
    SysClose(Sk);
    Exit;
  End;
  SysPut(Ctl, C + #13#10);
  Code := Reply(True);
  If (Code < 100) Or (Code >= 400) Then
  Begin
    SysClose(Sk);
    Exit;
  End;
  DataConn := Sk;
End;

Procedure GetFile(Const Remote, Local : String);
Var Sk, Fd, N, Tot : LongInt;
Begin
  If Binary Then Cmd_('TYPE I', False) Else Cmd_('TYPE A', False);
  Sk := DataConn('RETR ' + Remote);
  If Sk < 0 Then Exit;
  Fd := SysOpen(Local, O_WRONLY Or O_CREAT Or O_TRUNC, 420);
  If Fd < 0 Then
  Begin
    SysPut(1, 'local: ' + Local + ': ' + SysErrorText(SysErrno) + #10);
    SysClose(Sk);
    Exit;
  End;
  Tot := 0;
  Repeat
    N := SysRead(Sk, Buf[0], 8192);
    If N > 0 Then
    Begin
      SysWrite(Fd, Buf[0], N);
      Tot := Tot + N;
    End;
  Until N <= 0;
  SysClose(Fd);
  SysClose(Sk);
  Reply(True);
  SysPut(1, NumS(Tot) + ' bytes received' + #10);
End;

Procedure PutFile(Const Local, Remote : String);
Var Sk, Fd, N, Tot : LongInt;
Begin
  Fd := SysOpen(Local, O_RDONLY, 0);
  If Fd < 0 Then
  Begin
    SysPut(1, 'local: ' + Local + ': ' + SysErrorText(SysErrno) + #10);
    Exit;
  End;
  If Binary Then Cmd_('TYPE I', False) Else Cmd_('TYPE A', False);
  Sk := DataConn('STOR ' + Remote);
  If Sk < 0 Then
  Begin
    SysClose(Fd);
    Exit;
  End;
  Tot := 0;
  Repeat
    N := SysRead(Fd, Buf[0], 8192);
    If N > 0 Then
    Begin
      SysWrite(Sk, Buf[0], N);
      Tot := Tot + N;
    End;
  Until N <= 0;
  SysClose(Fd);
  SysClose(Sk);
  Reply(True);
  SysPut(1, NumS(Tot) + ' bytes sent' + #10);
End;

Procedure List(Const C, Arg : String);
Var Sk, N : LongInt;
Begin
  Cmd_('TYPE A', False);
  If Arg = '' Then Sk := DataConn(C) Else Sk := DataConn(C + ' ' + Arg);
  If Sk < 0 Then Exit;
  Repeat
    N := SysRead(Sk, Buf[0], 8192);
    If N > 0 Then SysWrite(1, Buf[0], N);
  Until N <= 0;
  SysClose(Sk);
  Reply(True);
End;

Procedure RunFtp;
Var
  I, Port, Code : LongInt;
  A, L, Cm, Ar, Usr, Pw : String;
  NoAuto : Boolean;
  K : LongInt;
  Interactive : Boolean;
Begin
  NoAuto := False;
  Host_ := '';
  Port := 21;
  For I := 1 To SysArgCount - 1 Do
  Begin
    A := SysArgStr(I);
    If A = '-n' Then NoAuto := True
    Else If (Length(A) > 0) And (A[1] = '-') Then
    Else If Host_ = '' Then Host_ := A
    Else Port := ToNum(A);
  End;
  Binary := False;
  Interactive := SysIsATty(0);
  Ctl := -1;
  If Host_ <> '' Then
  Begin
    Ctl := Dial(Host_, Port);
    If Ctl < 0 Then SysExit(1);
    SysPut(1, 'Connected to ' + Host_ + '.' + #10);
    Reply(True);
    If Not NoAuto Then
    Begin
      SysPut(1, 'Name (' + Host_ + ':' + 'user): ');
      If ReadFdLine(0, Usr) Then
      Begin
        If Usr = '' Then Usr := 'anonymous';
        Code := Cmd_('USER ' + Usr, True);
        If Code = 331 Then
        Begin
          SysPut(1, 'Password: ');
          ReadFdLine(0, Pw);
          Cmd_('PASS ' + Pw, True);
        End;
      End;
    End;
  End;
  While True Do
  Begin
    SysPut(1, 'ftp> ');
    If Not ReadFdLine(0, L) Then Break;
    If Not Interactive Then SysPut(1, L + #10);
    K := Pos(' ', L);
    If K = 0 Then
    Begin
      Cm := L;
      Ar := '';
    End
    Else
    Begin
      Cm := Copy(L, 1, K - 1);
      Ar := Copy(L, K + 1, 250);
    End;
    If (Cm = 'quit') Or (Cm = 'bye') Or (Cm = 'exit') Then
    Begin
      If Ctl >= 0 Then Cmd_('QUIT', True);
      Break;
    End
    Else If Cm = 'open' Then
    Begin
      K := Pos(' ', Ar);
      Host_ := Ar;
      Port := 21;
      If K > 0 Then
      Begin
        Host_ := Copy(Ar, 1, K - 1);
        Port := ToNum(Copy(Ar, K + 1, 10));
      End;
      Ctl := Dial(Host_, Port);
      If Ctl >= 0 Then Reply(True);
    End
    Else If Cm = 'binary' Then
    Begin
      Binary := True;
      SysPut(1, '200 Type set to I.' + #10);
    End
    Else If Cm = 'ascii' Then
    Begin
      Binary := False;
      SysPut(1, '200 Type set to A.' + #10);
    End
    Else If Cm = 'lcd' Then SysChdir(Ar)
    Else If Cm = '!' Then
    Begin
      K := SysFork;
      If K = 0 Then
      Begin
        SysArgReset;
        SysArgAdd('sh');
        SysArgAdd('-c');
        SysArgAdd(Ar);
        SysEnvInherit;
        SysArgExec('/bin/sh');
        SysExit(127);
      End;
      SysWaitPid(K, Code, 0);
    End
    Else If Ctl < 0 Then SysPut(1, 'Not connected.' + #10)
    Else If Cm = 'user' Then
    Begin
      K := Pos(' ', Ar);
      If K = 0 Then
      Begin
        Usr := Ar;
        Pw := '';
      End
      Else
      Begin
        Usr := Copy(Ar, 1, K - 1);
        Pw := Copy(Ar, K + 1, 100);
      End;
      Code := Cmd_('USER ' + Usr, True);
      If Code = 331 Then
      Begin
        If (K = 0) Then
        Begin
          SysPut(1, 'Password: ');
          ReadFdLine(0, Pw);
        End;
        Cmd_('PASS ' + Pw, True);
      End;
    End
    Else If (Cm = 'ls') Or (Cm = 'dir') Then
    Begin
      If Cm = 'ls' Then List('NLST', Ar) Else List('LIST', Ar);
    End
    Else If Cm = 'cd' Then Cmd_('CWD ' + Ar, True)
    Else If Cm = 'cdup' Then Cmd_('CDUP', True)
    Else If Cm = 'pwd' Then Cmd_('PWD', True)
    Else If Cm = 'mkdir' Then Cmd_('MKD ' + Ar, True)
    Else If Cm = 'rmdir' Then Cmd_('RMD ' + Ar, True)
    Else If Cm = 'delete' Then Cmd_('DELE ' + Ar, True)
    Else If Cm = 'rename' Then
    Begin
      K := Pos(' ', Ar);
      If K > 0 Then
        If Cmd_('RNFR ' + Copy(Ar, 1, K - 1), True) = 350 Then
          Cmd_('RNTO ' + Copy(Ar, K + 1, 200), True);
    End
    Else If Cm = 'get' Then
    Begin
      K := Pos(' ', Ar);
      If K > 0 Then GetFile(Copy(Ar, 1, K - 1), Copy(Ar, K + 1, 200))
      Else GetFile(Ar, Ar);
    End
    Else If Cm = 'put' Then
    Begin
      K := Pos(' ', Ar);
      If K > 0 Then PutFile(Copy(Ar, 1, K - 1), Copy(Ar, K + 1, 200))
      Else PutFile(Ar, Ar);
    End
    Else If Cm = 'system' Then Cmd_('SYST', True)
    Else If Cm = 'size' Then Cmd_('SIZE ' + Ar, True)
    Else If (Cm = 'quote') Then Cmd_(Ar, True)
    Else If Cm = 'close' Then
    Begin
      Cmd_('QUIT', True);
      SysClose(Ctl);
      Ctl := -1;
    End
    Else If Cm <> '' Then SysPut(1, '?Invalid command' + #10);
  End;
  If Ctl >= 0 Then SysClose(Ctl);
End;

{ ------------------------------ httpd ------------------------------ }

Var
  DocRoot : String;

Function Mime(Const P : String) : String;
Var K : LongInt; E : String;
Begin
  K := Length(P);
  While (K > 0) And (P[K] <> '.') And (P[K] <> '/') Do Dec(K);
  E := '';
  If (K > 0) And (P[K] = '.') Then E := Copy(P, K + 1, 10);
  If (E = 'html') Or (E = 'htm') Then Mime := 'text/html'
  Else If (E = 'txt') Or (E = 'c') Or (E = 'pas') Or (E = 'md') Then
    Mime := 'text/plain'
  Else If E = 'css' Then Mime := 'text/css'
  Else If E = 'js' Then Mime := 'application/javascript'
  Else If E = 'json' Then Mime := 'application/json'
  Else If E = 'png' Then Mime := 'image/png'
  Else If (E = 'jpg') Or (E = 'jpeg') Then Mime := 'image/jpeg'
  Else If E = 'gif' Then Mime := 'image/gif'
  Else If E = 'xml' Then Mime := 'application/xml'
  Else If E = 'zip' Then Mime := 'application/zip'
  Else Mime := 'application/octet-stream';
End;

Procedure Respond(Cn : LongInt; Code : LongInt; Const Msg, Typ : String;
                  Len : LongInt; Head : Boolean; Const Body : String);
Begin
  SysPut(Cn, 'HTTP/1.0 ' + NumS(Code) + ' ' + Msg + #13#10 +
         'Server: LINUX-0 httpd' + #13#10 + 'Content-Type: ' + Typ + #13#10 +
         'Content-Length: ' + NumS(Len) + #13#10 + 'Connection: close' +
         #13#10#13#10);
  If (Not Head) And (Body <> '') Then SysPut(Cn, Body);
End;

Procedure Serve(Cn : LongInt);
Var
  L, Meth, Path, Full, Q, Listing, Nm : String;
  K, Fd, N, D, Ino : LongInt;
  St : TSysStat;
  Head : Boolean;
Begin
  If Not ReadFdLine(Cn, L) Then Exit;
  { vider les en-tetes }
  Repeat
    If Not ReadFdLine(Cn, Q) Then Break;
  Until Q = '';
  K := Pos(' ', L);
  If K = 0 Then
  Begin
    Respond(Cn, 400, 'Bad Request', 'text/plain', 12, False,
            'Bad Request' + #10);
    Exit;
  End;
  Meth := Copy(L, 1, K - 1);
  Path := Copy(L, K + 1, 250);
  K := Pos(' ', Path);
  If K > 0 Then Path := Copy(Path, 1, K - 1);
  K := Pos('?', Path);
  If K > 0 Then Path := Copy(Path, 1, K - 1);
  Head := Meth = 'HEAD';
  If (Meth <> 'GET') And (Not Head) Then
  Begin
    Respond(Cn, 501, 'Not Implemented', 'text/plain', 16, False,
            'Not Implemented' + #10);
    Exit;
  End;
  If (Pos('..', Path) > 0) Or (Path = '') Or (Path[1] <> '/') Then
  Begin
    Respond(Cn, 403, 'Forbidden', 'text/plain', 10, Head, 'Forbidden' + #10);
    Exit;
  End;
  Full := DocRoot + Path;
  If SysStat(Full, St) <> 0 Then
  Begin
    Respond(Cn, 404, 'Not Found', 'text/plain', 10, Head, 'Not Found' + #10);
    Exit;
  End;
  If (St.Mode And $F000) = $4000 Then
  Begin
    If Full[Length(Full)] <> '/' Then Full := Full + '/';
    If SysStat(Full + 'index.html', St) = 0 Then Full := Full + 'index.html'
    Else
    Begin
      Listing := '<html><body><h1>Index of ' + Path + '</h1><ul>' + #10;
      D := SysOpenDir(Full);
      If D >= 0 Then
      Begin
        While SysReadDir(D, Nm, Ino) <> 0 Do
          If (Nm <> '.') And (Length(Listing) < 200) Then
            Listing := Listing + '<li><a href="' + Nm + '">' + Nm +
                       '</a>' + #10;
        SysCloseDir(D);
      End;
      Listing := Listing + '</ul></body></html>' + #10;
      Respond(Cn, 200, 'OK', 'text/html', Length(Listing), Head, Listing);
      Exit;
    End;
  End;
  Fd := SysOpen(Full, O_RDONLY, 0);
  If (Fd < 0) Or (SysFStat(Fd, St) <> 0) Then
  Begin
    Respond(Cn, 403, 'Forbidden', 'text/plain', 10, Head, 'Forbidden' + #10);
    Exit;
  End;
  Respond(Cn, 200, 'OK', Mime(Full), St.Size, True, '');
  If Not Head Then
    Repeat
      N := SysRead(Fd, Buf[0], 8192);
      If N > 0 Then SysWrite(Cn, Buf[0], N);
    Until N <= 0;
  SysClose(Fd);
End;

Procedure RunHttpd;
Var
  I, Port, Sk, Cn, Pid, St, One : LongInt;
  A : String;
  Fg : Boolean;
  Sa : TSockAddrIn;
Begin
  Port := 80;
  DocRoot := '/var/www';
  Fg := False;
  I := 1;
  While I < SysArgCount Do
  Begin
    A := SysArgStr(I);
    If A = '-p' Then
    Begin
      Inc(I);
      If I < SysArgCount Then Port := ToNum(SysArgStr(I));
    End
    Else If A = '-d' Then
    Begin
      Inc(I);
      If I < SysArgCount Then DocRoot := SysArgStr(I);
    End
    Else If A = '-f' Then Fg := True
    Else If (A = '--help') Or (A = '/?') Then Die(PS(Usage[Lang]), 0);
    Inc(I);
  End;
  While (Length(DocRoot) > 1) And (DocRoot[Length(DocRoot)] = '/') Do
    Delete(DocRoot, Length(DocRoot), 1);
  Sk := SysSocket(2, 1, 0);
  One := 1;
  SysSetSockOpt(Sk, 1, 2, LongInt(@One), 4);
  SysSockAddr(Sa, 0, Port);
  If SysBind(Sk, LongInt(@Sa), 16) < 0 Then
    Die('bind: ' + SysErrorText(SysErrno), 1);
  SysListen(Sk, 8);
  If Not Fg Then
  Begin
    If SysFork > 0 Then SysExit(0);
    SysSetSid;
  End;
  While True Do
  Begin
    Cn := SysAccept(Sk, 0, 0);
    If Cn < 0 Then Continue;
    Pid := SysFork;
    If Pid = 0 Then
    Begin
      SysClose(Sk);
      Serve(Cn);
      SysClose(Cn);
      SysExit(0);
    End;
    SysClose(Cn);
    While SysWaitPid(-1, St, WNOHANG) > 0 Do ;
  End;
End;

{ ------------------------------ traceroute ------------------------------ }

Var
  Tv : Array[0..1] Of LongInt;

Function NowMs : LongInt;
Begin
  SysCall(78, LongInt(@Tv[0]), 0, 0, 0, 0);
  NowMs := (Tv[0] Mod 100000) * 1000 + Tv[1] Div 1000;
End;

Procedure RunTraceroute;
Var
  I, MaxHops, Ip, Us, Rs, Ttl, Probe, N, T0, T1, Dst, Hop, Wait, Port : LongInt;
  Host, A : String;
  Sa, From : TSockAddrIn;
  Pf : Array[0..1] Of LongInt;
  FromLen : LongInt;
  Reached : Boolean;
  Last : LongInt;
  Ms : LongInt;
  Ty, Cd : LongInt;
Begin
  MaxHops := 30;
  Wait := 3;
  Host := '';
  I := 1;
  While I < SysArgCount Do
  Begin
    A := SysArgStr(I);
    If A = '-m' Then
    Begin
      Inc(I);
      If I < SysArgCount Then MaxHops := ToNum(SysArgStr(I));
    End
    Else If A = '-w' Then
    Begin
      Inc(I);
      If I < SysArgCount Then Wait := ToNum(SysArgStr(I));
    End
    Else If (A = '--help') Or (A = '/?') Then Die(PS(Usage[Lang]), 0)
    Else If (Length(A) > 0) And (A[1] <> '-') Then Host := A;
    Inc(I);
  End;
  If Host = '' Then Die(PS(Usage[Lang]), 1);
  If Not SysResolve(Host, Ip) Then
    Die(Host + ': Name or service not known', 1);
  Us := SysSocket(2, 2, 0);
  Rs := SysSocket(2, 3, 1);
  If (Us < 0) Or (Rs < 0) Then Die('socket: ' + SysErrorText(SysErrno), 1);
  SysPut(1, 'traceroute to ' + Host + ' (' + SysIpStr(Ip) + '), ' +
         NumS(MaxHops) + ' hops max, 60 byte packets' + #10);
  Reached := False;
  Ttl := 1;
  While (Ttl <= MaxHops) And (Not Reached) Do
  Begin
    SysSetSockOpt(Us, 0, 2, LongInt(@Ttl), 4);
    SysPut(1, NumS(Ttl));
    If Ttl < 10 Then SysPut(1, ' ');
    Last := 0;
    For Probe := 1 To 3 Do
    Begin
      Port := 33434 + Ttl * 3 + Probe;
      SysSockAddr(Sa, Ip, Port);
      T0 := NowMs;
      FillChar(Buf, 32, 0);
      SysSendTo(Us, LongInt(@Buf[0]), 32, 0, LongInt(@Sa), 16);
      Pf[0] := Rs;
      Pf[1] := 1;
      N := SysPoll(LongInt(@Pf), 1, Wait * 1000);
      If N <= 0 Then SysPut(1, '  *')
      Else
      Begin
        FromLen := 16;
        N := SysRecvFrom(Rs, LongInt(@Buf[0]), 512, 0, LongInt(@From),
                         LongInt(@FromLen));
        If N < 28 Then
        Begin
          SysPut(1, '  *');
          Continue;
        End;
        Ty := Buf[20];
        Cd := Buf[21];
        If From.Addr <> Last Then
        Begin
          SysPut(1, '  ' + SysIpStr(From.Addr));
          Last := From.Addr;
        End;
        Ms := NowMs - T0;
        SysPut(1, '  ' + NumS(Ms) + ' ms');
        If (Ty = 3) Or ((Ty = 0)) Then Reached := True;
      End;
    End;
    SysPut(1, #10);
    Inc(Ttl);
  End;
End;

BEGIN
  Lang := SysLang;
  If (Lang < 1) Or (Lang > 5) Then Lang := 1;
  Prog := SysArgStr(0);
  While Pos('/', Prog) > 0 Do Prog := Copy(Prog, Pos('/', Prog) + 1, 255);
  If Prog = 'telnet' Then RunTelnet
  Else If Prog = 'ftp' Then RunFtp
  Else If Prog = 'httpd' Then RunHttpd
  Else If Prog = 'traceroute' Then RunTraceroute
  Else Die(PS(Usage[Lang]), 1);
END.
