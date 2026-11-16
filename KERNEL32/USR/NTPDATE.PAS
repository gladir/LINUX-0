{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2026
  @website(https://www.gladir.com/linux-0)
  @abstract(Target: LPC -3X)
  @description: ntpdate et rdate (le nom lu dans argv[0]) : mise a l'heure par
   le reseau.
   ntpdate [-q] [-p port] serveur   client SNTP (UDP 123, version 4) : affiche
        le decalage et regle l'heure (settimeofday) sauf avec -q.
   rdate [-p] [-s] [-P port] serveur   protocole TIME (RFC 868, TCP 37) : -p
        affiche la date du serveur, -s regle l'heure (par defaut : les deux).
   serveur : adresse IPv4, nom (/etc/hosts, DNS de /etc/resolv.conf). }

Program NtpDate;

Const
  NtpToUnix = 2085978496;   { 2^32 - 2208988800 : secondes 1900 -> 1970 }
  MonN : Array[1..12] Of String[3] = ('Jan', 'Feb', 'Mar', 'Apr', 'May',
    'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec');
  DayN : Array[0..6] Of String[3] = ('Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri',
    'Sat');

Var
  Quiet, Show, SetIt, IsRdate : Boolean;
  Port, I, K, Fd, Ip, R, T, Off : LongInt;
  A, Srv, Prog, S1 : String;
  Sa : TSockAddrIn;
  Pk : Array[0..11] Of LongInt;
  Rcv : Array[0..11] Of LongInt;
  Pf : Array[0..1] Of LongInt;
  Tries : LongInt;

Procedure Die(Const S : String);
Begin
  SysPut(2, Prog + ': ' + S + #10);
  SysExit(1);
End;

Function Be32(Addr : LongInt; Off : LongInt) : LongInt;
Begin
  Be32 := (Mem[0:Addr + Off] Shl 24) Or (Mem[0:Addr + Off + 1] Shl 16) Or
          (Mem[0:Addr + Off + 2] Shl 8) Or Mem[0:Addr + Off + 3];
End;

Function Two(V : LongInt) : String;
Var S : String;
Begin
  Str(V, S);
  If Length(S) < 2 Then S := '0' + S;
  Two := S;
End;

{ date UTC d'un instant Unix : "Mon Nov 16 19:35:59 2026" }
Function UtcText(T : LongInt) : String;
Var Days, Sec, Y, M, D, Wd : LongInt; S : String;
Begin
  Days := T Div 86400;
  Sec := T Mod 86400;
  LnxCivil(Days, Y, M, D);
  Wd := (Days + 4) Mod 7;
  Str(Y, S);
  UtcText := DayN[Wd] + ' ' + MonN[M] + ' ' + Two(D) + ' ' + Two(Sec Div 3600)
    + ':' + Two((Sec Mod 3600) Div 60) + ':' + Two(Sec Mod 60) + ' ' + S;
End;

Procedure SetClock(T : LongInt);
Begin
  LnxTmp[0] := T;
  LnxTmp[1] := 0;
  If LnxSys3(79, LongInt(@LnxTmp), 0, 0) < 0 Then
    Die('impossible de regler l''heure (droits ?)');
End;

Begin
  Prog := SysArgStr(0);
  K := Length(Prog);
  While (K > 0) And (Prog[K] <> '/') Do Dec(K);
  Prog := Copy(Prog, K + 1, 20);
  IsRdate := (Prog = 'rdate') Or (Prog = 'RDATE');
  Quiet := False; Show := False; SetIt := False;
  Port := 0;
  Srv := '';
  I := 1;
  While I < SysArgCount Do
  Begin
    A := SysArgStr(I);
    If A = '-q' Then Quiet := True
    Else If A = '-p' Then
    Begin
      If IsRdate Then Show := True
      Else If I + 1 < SysArgCount Then
      Begin
        Inc(I);
        Val(SysArgStr(I), Port, K);
      End;
    End
    Else If A = '-P' Then
    Begin
      If I + 1 < SysArgCount Then
      Begin
        Inc(I);
        Val(SysArgStr(I), Port, K);
      End;
    End
    Else If A = '-s' Then SetIt := True
    Else If (A <> '') And (A[1] <> '-') Then Srv := A
    Else Die('option inconnue : ' + A);
    Inc(I);
  End;
  If Srv = '' Then
    Die('usage : ntpdate [-q] [-p port] serveur | rdate [-p] [-s] serveur');
  If Not SysParseIp(Srv, Ip) Then
    If Not SysResolve(Srv, Ip) Then Die('serveur inconnu : ' + Srv);
  If IsRdate Then
  Begin
    If Port = 0 Then Port := 37;
    If (Not Show) And (Not SetIt) Then
    Begin
      Show := True;
      SetIt := True;
    End;
    Fd := SysSocket(2, 1, 0);
    If Fd < 0 Then Die('socket impossible');
    SysSockAddr(Sa, Ip, Port);
    If SysConnect(Fd, LongInt(@Sa), 16) < 0 Then Die('connexion refusee');
    Pf[0] := Fd; Pf[1] := 1;
    If SysPoll(LongInt(@Pf), 1, 5000) <= 0 Then Die('delai depasse');
    R := SysRead(Fd, Rcv, 4);
    If R <> 4 Then Die('reponse invalide');
    T := Be32(LongInt(@Rcv), 0) + NtpToUnix;
    If Show Then SysPut(1, UtcText(T) + #10);
    If SetIt Then SetClock(T);
    SysExit(0);
  End;
  { ntpdate : SNTP }
  If Port = 0 Then Port := 123;
  Fd := SysSocket(2, 2, 0);
  If Fd < 0 Then Die('socket impossible');
  SysSockAddr(Sa, Ip, Port);
  For Tries := 1 To 3 Do
  Begin
    FillChar(Pk, SizeOf(Pk), 0);
    Pk[0] := $23;                       { LI 0, VN 4, mode 3 (client) }
    R := SysSendTo(Fd, LongInt(@Pk), 48, 0, LongInt(@Sa), 16);
    If R <> 48 Then Die('envoi impossible');
    Pf[0] := Fd; Pf[1] := 1;
    If SysPoll(LongInt(@Pf), 1, 2000) > 0 Then
    Begin
      R := SysRecvFrom(Fd, LongInt(@Rcv), 48, 0, 0, 0);
      If R >= 48 Then
      Begin
        T := Be32(LongInt(@Rcv), 40) + NtpToUnix;
        If Be32(LongInt(@Rcv), 40) = 0 Then Die('reponse invalide');
        Off := T - SysTime;
        Str(Off, S1);
        If Off >= 0 Then S1 := '+' + S1;
        If (Not Quiet) Then SetClock(T);
        If Quiet Then
          SysPut(1, 'server ' + Srv + ', offset ' + S1 + '.000 sec' + #10)
        Else
          SysPut(1, 'step time server ' + Srv + ' offset ' + S1 +
                 '.000 sec' + #10);
        SysExit(0);
      End;
    End;
  End;
  Die('pas de reponse de ' + Srv);
End.
