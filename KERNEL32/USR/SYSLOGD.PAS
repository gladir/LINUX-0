{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2026
  @website(https://www.gladir.com/linux-0)
  @abstract(Target: LPC -3X)
  @description: syslogd et logger (nom lu dans argv[0]). syslogd [-n] [-S
      socket] [-C config] [-O dossier] : ecoute /dev/log (datagrammes AF_UNIX)
      et ecrit les messages dans /var/log/messages, ou selon /etc/syslog.conf
      (lignes "facilites.niveau  fichier" ; * = tout ; none = exclu).
      logger [-t etiquette] [-p facilite.niveau] [-i] [-S socket] message...
}

Program SYSLOGD;

Const
  UsageW : Array[1..5] Of PChar =
    ('Usage : ', 'Usage: ', 'Aufruf: ', 'Uso: ', 'Uso: ');
  MaxRule = 24;

Var
  Prog, SockPath, ConfPath, LogDir : String;
  RuleSel : Array[1..MaxRule] Of String;
  RuleFile : Array[1..MaxRule] Of String;
  NRule : LongInt;
  Foreground : Boolean;
  Buf : Array[0..2047] Of Char;

Function PS(Q : PChar) : String;
Var X : String;
Begin
  X := '';
  While Q^ <> #0 Do
  Begin
    X := X + Q^;
    Inc(Q);
  End;
  PS := X;
End;

Function NumS(V : LongInt) : String;
Var S : String;
Begin
  Str(V, S);
  NumS := S;
End;

Function Pad2(V : LongInt) : String;
Begin
  If V < 10 Then Pad2 := '0' + NumS(V) Else Pad2 := NumS(V);
End;

Const
  FacNames : Array[0..23] Of PChar = ('kern', 'user', 'mail', 'daemon',
    'auth', 'syslog', 'lpr', 'news', 'uucp', 'cron', 'authpriv', 'ftp',
    'ntp', 'audit', 'alert', 'clock', 'local0', 'local1', 'local2',
    'local3', 'local4', 'local5', 'local6', 'local7');
  LevNames : Array[0..7] Of PChar = ('emerg', 'alert', 'crit', 'err',
    'warning', 'notice', 'info', 'debug');
  MonN : Array[1..12] Of PChar = ('Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec');

Function FacOf(Const S : String) : LongInt;
Var K : LongInt;
Begin
  FacOf := -1;
  If S = '*' Then Exit;
  For K := 0 To 23 Do
    If PS(FacNames[K]) = S Then FacOf := K;
  If S = 'security' Then FacOf := 4;
End;

Function LevOf(Const S : String) : LongInt;
Var K : LongInt;
Begin
  LevOf := 8;
  If S = '*' Then
  Begin
    LevOf := 7;
    Exit;
  End;
  If S = 'none' Then Exit;
  For K := 0 To 7 Do
    If PS(LevNames[K]) = S Then LevOf := K;
  If S = 'error' Then LevOf := 3;
  If S = 'warn' Then LevOf := 4;
  If S = 'panic' Then LevOf := 0;
End;

{ jours -> mois, jour }
Procedure Civil(Days : LongInt; Var M, D : LongInt);
Var Z, Era, Doe, Yoe, Doy, Mp : LongInt;
Begin
  Z := Days + 719468;
  Era := Z Div 146097;
  Doe := Z - Era * 146097;
  Yoe := (Doe - Doe Div 1460 + Doe Div 36524 - Doe Div 146096) Div 365;
  Doy := Doe - (365 * Yoe + Yoe Div 4 - Yoe Div 100);
  Mp := (5 * Doy + 2) Div 153;
  D := Doy - (153 * Mp + 2) Div 5 + 1;
  If Mp < 10 Then M := Mp + 3 Else M := Mp - 9;
End;

Function Stamp : String;
Var T, M, D : LongInt; Ds : String;
Begin
  T := SysTime;
  Civil(T Div 86400, M, D);
  Ds := NumS(D);
  If D < 10 Then Ds := ' ' + Ds;
  Stamp := PS(MonN[M]) + ' ' + Ds + ' ' + Pad2((T Mod 86400) Div 3600) + ':' +
           Pad2((T Mod 3600) Div 60) + ':' + Pad2(T Mod 60);
End;

Function HostName : String;
Var U : TUtsName;
Begin
  If SysUname(U) = 0 Then HostName := U.NodeName Else HostName := 'localhost';
End;

Procedure Usage;
Begin
  SysPut(2, PS(UsageW[SysLang]) +
    'syslogd [-n] [-S socket] [-C config] [-O dossier]' + #10);
  SysExit(2);
End;

Type
  TSockUn = Record
    Family : Word;
    Path : Array[0..107] Of Char;
  End;

Procedure SetAddr(Var A : TSockUn; Const P : String);
Var K : LongInt;
Begin
  FillChar(A, SizeOf(A), 0);
  A.Family := 1;
  For K := 1 To Length(P) Do
    If K <= 107 Then A.Path[K - 1] := P[K];
End;

{ ---------- configuration ---------- }

Procedure AddRule(Const Sel, F : String);
Begin
  If NRule >= MaxRule Then Exit;
  Inc(NRule);
  RuleSel[NRule] := Sel;
  RuleFile[NRule] := F;
End;

Procedure ReadConf;
Var Fd, K : LongInt; L, Sel, F : String;
Begin
  NRule := 0;
  Fd := SysOpen(ConfPath, 0, 0);
  If Fd >= 0 Then
  Begin
    While SysReadLine(Fd, L) Do
    Begin
      While (L <> '') And ((L[1] = ' ') Or (L[1] = #9)) Do Delete(L, 1, 1);
      If (L = '') Or (L[1] = '#') Then Continue;
      K := 1;
      While (K <= Length(L)) And (L[K] <> ' ') And (L[K] <> #9) Do Inc(K);
      Sel := Copy(L, 1, K - 1);
      F := Copy(L, K + 1, 255);
      While (F <> '') And ((F[1] = ' ') Or (F[1] = #9)) Do Delete(F, 1, 1);
      If F <> '' Then AddRule(Sel, F);
    End;
    SysClose(Fd);
  End;
  If NRule = 0 Then
  Begin
    AddRule('*.info;auth,authpriv.none', LogDir + '/messages');
    AddRule('auth,authpriv.*', LogDir + '/auth.log');
    AddRule('kern.*', LogDir + '/kern.log');
  End;
End;

{ le message (facilite Fac, niveau Lev) correspond-il au selecteur ? }
Function SelMatch(Const Sel : String; Fac, Lev : LongInt) : Boolean;
Var Rest, Part, Facs, Lv : String; K, J, Pri : LongInt; Ok, Hit : Boolean;
    Fl : String; Neg : Boolean;
Begin
  Hit := False;
  Rest := Sel + ';';
  While Rest <> '' Do
  Begin
    K := Pos(';', Rest);
    Part := Copy(Rest, 1, K - 1);
    Rest := Copy(Rest, K + 1, 255);
    If Part = '' Then Continue;
    K := Pos('.', Part);
    If K = 0 Then Continue;
    Facs := Copy(Part, 1, K - 1) + ',';
    Lv := Copy(Part, K + 1, 40);
    Neg := False;
    If (Lv <> '') And (Lv[1] = '!') Then
    Begin
      Neg := True;
      Delete(Lv, 1, 1);
    End;
    Pri := LevOf(Lv);
    Ok := False;
    While Facs <> '' Do
    Begin
      J := Pos(',', Facs);
      Fl := Copy(Facs, 1, J - 1);
      Facs := Copy(Facs, J + 1, 255);
      If (Fl = '*') Or (FacOf(Fl) = Fac) Then Ok := True;
    End;
    If Ok Then
    Begin
      If Lv = 'none' Then Hit := False
      Else If (Lev <= Pri) Then Hit := True;
    End;
  End;
  SelMatch := Hit;
End;

Procedure WriteLog(Const F, Line : String);
Var Fd : LongInt;
Begin
  If F = '/dev/null' Then Exit;
  If (F <> '') And (F[1] = '-') Then Fd := SysOpen(Copy(F, 2, 255), $441, 420)
  Else Fd := SysOpen(F, $441, 420);
  If Fd < 0 Then Exit;
  SysPut(Fd, Line + #10);
  SysClose(Fd);
End;

Procedure Handle(N : LongInt);
Var Pri, Fac, Lev, K, P : LongInt; Msg, Line : String;
Begin
  Msg := '';
  For K := 0 To N - 1 Do
    If (Buf[K] <> #0) And (Length(Msg) < 250) And (Buf[K] <> #10) Then
      Msg := Msg + Buf[K];
  Pri := 13;
  If (Msg <> '') And (Msg[1] = '<') Then
  Begin
    P := Pos('>', Msg);
    If (P > 1) And (P < 6) Then
    Begin
      Val(Copy(Msg, 2, P - 2), Pri, K);
      Msg := Copy(Msg, P + 1, 255);
    End;
  End;
  Fac := Pri Shr 3;
  Lev := Pri And 7;
  { horodatage deja present (Mmm dd hh:mm:ss) : on le retire }
  If (Length(Msg) > 16) And (Msg[4] = ' ') And (Msg[10] = ':') And
     (Msg[13] = ':') Then Msg := Copy(Msg, 17, 255);
  Line := Stamp + ' ' + HostName + ' ' + Msg;
  For K := 1 To NRule Do
    If SelMatch(RuleSel[K], Fac, Lev) Then WriteLog(RuleFile[K], Line);
End;

Procedure RunSyslogd;
Var Fd, N, Pid : LongInt; A : TSockUn; Un : Boolean;
Begin
  ReadConf;
  Fd := SysSocket(1, 2, 0);
  If Fd < 0 Then
  Begin
    SysPut(2, 'syslogd: socket : ' + SysErrorText(SysErrno) + #10);
    SysExit(1);
  End;
  SysUnlink(SockPath);
  SetAddr(A, SockPath);
  If SysBind(Fd, LongInt(@A), 2 + Length(SockPath) + 1) < 0 Then
  Begin
    SysPut(2, 'syslogd: ' + SockPath + ' : ' + SysErrorText(SysErrno) + #10);
    SysExit(1);
  End;
  SysChmod(SockPath, 438);
  If Not Foreground Then
  Begin
    Pid := SysFork;
    If Pid > 0 Then SysExit(0);
    SysSetSid;
    SysClose(0);
    SysClose(1);
    SysClose(2);
  End;
  { message de demarrage }
  Move('<46>syslogd: started', Buf[0], 20);
  Handle(20);
  While True Do
  Begin
    N := SysRecvFrom(Fd, LongInt(@Buf[0]), 2047, 0, 0, 0);
    If N > 0 Then Handle(N)
    Else If (N < 0) And (SysErrno <> 4) Then SysSleep(1);
  End;
End;

Procedure RunLogger;
Var I, Fd, Pid, Pri, K : LongInt; A : String; Tag, Msg, Sel : String;
    Sa : TSockUn; Idf : Boolean; Fac, Lev : LongInt; Fs, Ls : String;
Begin
  Tag := '';
  Msg := '';
  Sel := 'user.notice';
  Idf := False;
  I := 1;
  While I < SysArgCount Do
  Begin
    A := SysArgStr(I);
    If A = '-t' Then
    Begin
      Inc(I);
      Tag := SysArgStr(I);
    End
    Else If A = '-p' Then
    Begin
      Inc(I);
      Sel := SysArgStr(I);
    End
    Else If A = '-i' Then Idf := True
    Else If A = '-S' Then
    Begin
      Inc(I);
      SockPath := SysArgStr(I);
    End
    Else If (A = '-s') Or (A = '-u') Then
    Else Msg := Msg + A + ' ';
    Inc(I);
  End;
  If Msg = '' Then
  Begin
    While SysReadLine(0, A) Do Msg := Msg + A;
  End
  Else Msg := Copy(Msg, 1, Length(Msg) - 1);
  If Tag = '' Then Tag := SysGetEnv('USER');
  If Tag = '' Then Tag := 'user';
  K := Pos('.', Sel);
  If K = 0 Then
  Begin
    Fs := 'user';
    Ls := Sel;
  End
  Else
  Begin
    Fs := Copy(Sel, 1, K - 1);
    Ls := Copy(Sel, K + 1, 40);
  End;
  Fac := FacOf(Fs);
  If Fac < 0 Then Fac := 1;
  Lev := LevOf(Ls);
  If Lev > 7 Then Lev := 5;
  Pri := Fac * 8 + Lev;
  If Idf Then Tag := Tag + '[' + NumS(SysGetPid) + ']';
  A := '<' + NumS(Pri) + '>' + Tag + ': ' + Msg;
  Fd := SysSocket(1, 2, 0);
  If Fd < 0 Then
  Begin
    SysPut(2, 'logger: socket : ' + SysErrorText(SysErrno) + #10);
    SysExit(1);
  End;
  SetAddr(Sa, SockPath);
  If SysSendTo(Fd, LongInt(@A[1]), Length(A), 0, LongInt(@Sa),
               2 + Length(SockPath) + 1) < 0 Then
  Begin
    SysPut(2, 'logger: ' + SockPath + ' : ' + SysErrorText(SysErrno) + #10);
    SysExit(1);
  End;
End;

Var I, K : LongInt; A : String;
Begin
  Prog := SysArgStr(0);
  K := Length(Prog);
  While (K > 0) And (Prog[K] <> '/') Do Dec(K);
  Prog := Copy(Prog, K + 1, 255);
  SockPath := '/dev/log';
  ConfPath := '/etc/syslog.conf';
  LogDir := '/var/log';
  Foreground := False;
  If Prog = 'logger' Then
  Begin
    RunLogger;
    SysExit(0);
  End;
  I := 1;
  While I < SysArgCount Do
  Begin
    A := SysArgStr(I);
    If A = '-n' Then Foreground := True
    Else If A = '-S' Then
    Begin
      Inc(I);
      SockPath := SysArgStr(I);
    End
    Else If A = '-C' Then
    Begin
      Inc(I);
      ConfPath := SysArgStr(I);
    End
    Else If A = '-O' Then
    Begin
      Inc(I);
      LogDir := SysArgStr(I);
    End
    Else If (A = '-m') Or (A = '-r') Or (A = '-K') Then
    Else Usage;
    Inc(I);
  End;
  RunSyslogd;
End.
