{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2026
  @website(https://www.gladir.com/linux-0)
  @abstract(Target: LPC -3X)
  @description: who, users, w, last (nom lu dans argv[0]) : sessions ouvertes
      (/var/run/utmp) et historique des connexions (/var/log/wtmp) ;
      who [-a] [-b] [-q] [-H] [am i], users, w [-h], last [-n N] [nom].
}

Program WHO;

{$I UTMP.INC}

Const
  UsageW : Array[1..5] Of PChar =
    ('Usage : ', 'Usage: ', 'Aufruf: ', 'Uso: ', 'Uso: ');

Var
  Prog : String;
  Fn : String;

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

Function PadR(Const S : String; N : LongInt) : String;
Var R : String;
Begin
  R := S;
  While Length(R) < N Do R := R + ' ';
  PadR := R;
End;

{ jours depuis 1970 -> annee, mois, jour }
Procedure Civil(Days : LongInt; Var Y, M, D : LongInt);
Var Z, Era, Doe, Yoe, Doy, Mp : LongInt;
Begin
  Z := Days + 719468;
  Era := Z Div 146097;
  Doe := Z - Era * 146097;
  Yoe := (Doe - Doe Div 1460 + Doe Div 36524 - Doe Div 146096) Div 365;
  Y := Yoe + Era * 400;
  Doy := Doe - (365 * Yoe + Yoe Div 4 - Yoe Div 100);
  Mp := (5 * Doy + 2) Div 153;
  D := Doy - (153 * Mp + 2) Div 5 + 1;
  If Mp < 10 Then M := Mp + 3 Else M := Mp - 9;
  If M <= 2 Then Inc(Y);
End;

Function DateS(T : LongInt) : String;
Var Y, M, D : LongInt;
Begin
  Civil(T Div 86400, Y, M, D);
  DateS := NumS(Y) + '-' + Pad2(M) + '-' + Pad2(D) + ' ' +
           Pad2((T Mod 86400) Div 3600) + ':' + Pad2((T Mod 3600) Div 60);
End;

Const
  Mon : Array[1..12] Of PChar = ('Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec');
  Day : Array[0..6] Of PChar = ('Thu', 'Fri', 'Sat', 'Sun', 'Mon', 'Tue',
    'Wed');

Function DateL(T : LongInt) : String;
Var Y, M, D : LongInt;
Begin
  Civil(T Div 86400, Y, M, D);
  DateL := PS(Day[(T Div 86400) Mod 7]) + ' ' + PS(Mon[M]) + ' ' +
           Copy('  ' + NumS(D), Length(NumS(D)) + 1, 2) + ' ' +
           Pad2((T Mod 86400) Div 3600) + ':' + Pad2((T Mod 3600) Div 60);
End;

Function ReadFile1(Const F : String) : String;
Var Fd, N : LongInt; B : Array[0..255] Of Char; S : String; K : LongInt;
Begin
  S := '';
  Fd := SysOpen(F, 0, 0);
  If Fd >= 0 Then
  Begin
    N := SysRead(Fd, B, 255);
    For K := 0 To N - 1 Do
      If B[K] <> #10 Then S := S + B[K];
    SysClose(Fd);
  End;
  ReadFile1 := S;
End;

Function ThisTty : String;
Var T : String;
Begin
  T := SysReadlink('/proc/self/fd/0');
  If Copy(T, 1, 5) = '/dev/' Then T := Copy(T, 6, 40);
  ThisTty := T;
End;

Procedure DoWho;
Var Fd, N, Cnt : LongInt; U : TUtmp; Quiet, Boot, Head, All, Me : Boolean;
    I : LongInt; A, Names, Tty : String; Any : Boolean;
Begin
  Quiet := False; Boot := False; Head := False; All := False; Me := False;
  For I := 1 To SysArgCount - 1 Do
  Begin
    A := SysArgStr(I);
    If A = '-q' Then Quiet := True
    Else If A = '-b' Then Boot := True
    Else If A = '-H' Then Head := True
    Else If A = '-a' Then All := True
    Else If (A = '-m') Or (A = 'am') Or (A = 'i') Then Me := True
    Else If (A = '-u') Or (A = '-s') Or (A = '-T') Then
    Else If A = '--help' Then
    Begin
      SysPut(2, PS(UsageW[SysLang]) + 'who [-abqmH]' + #10);
      SysExit(0);
    End;
  End;
  Tty := ThisTty;
  Fd := SysOpen('/var/run/utmp', 0, 0);
  If Head Then
    SysPut(1, 'NAME     LINE         TIME             COMMENT' + #10);
  If Fd < 0 Then Exit;
  Cnt := 0;
  Names := '';
  While SysRead(Fd, U, UtSize) = UtSize Do
  Begin
    If Boot Or All Then
      If U.Typ = UtBoot Then
        SysPut(1, '         system boot  ' + DateS(U.Sec) + #10);
    If (U.Typ = UtUser) And ((Not Me) Or (UtLineS(U) = Tty)) Then
    Begin
      Inc(Cnt);
      Names := Names + UtUserS(U) + ' ';
      If (Not Quiet) And (Not Boot) Then
      Begin
        SysPut(1, PadR(UtUserS(U), 9) + PadR(UtLineS(U), 13) +
               DateS(U.Sec));
        If UtHostS(U) <> '' Then SysPut(1, ' (' + UtHostS(U) + ')');
        SysPut(1, #10);
      End;
    End;
  End;
  SysClose(Fd);
  If Quiet Then
  Begin
    SysPut(1, Copy(Names, 1, Length(Names) - 1) + #10);
    SysPut(1, '# users=' + NumS(Cnt) + #10);
  End;
End;

Procedure DoUsers;
Var Fd : LongInt; U : TUtmp; Names : String;
Begin
  Names := '';
  Fd := SysOpen('/var/run/utmp', 0, 0);
  If Fd >= 0 Then
  Begin
    While SysRead(Fd, U, UtSize) = UtSize Do
      If U.Typ = UtUser Then Names := Names + UtUserS(U) + ' ';
    SysClose(Fd);
  End;
  If Names <> '' Then SysPut(1, Copy(Names, 1, Length(Names) - 1) + #10);
End;

Function CmdOf(Pid : LongInt) : String;
Var Fd, N, K : LongInt; B : Array[0..127] Of Char; S : String;
Begin
  S := '';
  Fd := SysOpen('/proc/' + NumS(Pid) + '/cmdline', 0, 0);
  If Fd >= 0 Then
  Begin
    N := SysRead(Fd, B, 127);
    For K := 0 To N - 1 Do
      If B[K] = #0 Then S := S + ' ' Else S := S + B[K];
    SysClose(Fd);
  End;
  If S = '' Then S := '-';
  CmdOf := S;
End;

Procedure DoW;
Var Fd, Up, Cnt, Dd, Hh, Mm : LongInt; U : TUtmp; Hdr : Boolean; I : LongInt;
    S, Ld, Now : String; Rows : String;
Begin
  Hdr := True;
  For I := 1 To SysArgCount - 1 Do
    If SysArgStr(I) = '-h' Then Hdr := False;
  Cnt := 0;
  Fd := SysOpen('/var/run/utmp', 0, 0);
  Rows := '';
  If Fd >= 0 Then
  Begin
    While SysRead(Fd, U, UtSize) = UtSize Do
      If U.Typ = UtUser Then Inc(Cnt);
    SysClose(Fd);
  End;
  S := ReadFile1('/proc/uptime');
  Up := 0;
  I := 1;
  While (I <= Length(S)) And (S[I] >= '0') And (S[I] <= '9') Do
  Begin
    Up := Up * 10 + Ord(S[I]) - 48;
    Inc(I);
  End;
  Ld := ReadFile1('/proc/loadavg');
  Dd := Up Div 86400;
  Hh := (Up Mod 86400) Div 3600;
  Mm := (Up Mod 3600) Div 60;
  Now := Pad2((SysTime Mod 86400) Div 3600) + ':' +
         Pad2((SysTime Mod 3600) Div 60) + ':' + Pad2(SysTime Mod 60);
  If Hdr Then
  Begin
    S := ' ' + Now + ' up ';
    If Dd > 0 Then S := S + NumS(Dd) + ' days, ';
    S := S + NumS(Hh) + ':' + Pad2(Mm) + ',  ' + NumS(Cnt) + ' user';
    If Cnt <> 1 Then S := S + 's';
    S := S + ',  load average: ';
    If Ld <> '' Then S := S + Copy(Ld, 1, 14) Else S := S + '0.00, 0.00, 0.00';
    SysPut(1, S + #10);
    SysPut(1, 'USER     TTY      FROM             LOGIN@   IDLE   WHAT' + #10);
  End;
  Fd := SysOpen('/var/run/utmp', 0, 0);
  If Fd >= 0 Then
  Begin
    While SysRead(Fd, U, UtSize) = UtSize Do
      If U.Typ = UtUser Then
      Begin
        S := UtHostS(U);
        If S = '' Then S := '-';
        SysPut(1, PadR(UtUserS(U), 9) + PadR(UtLineS(U), 9) + PadR(S, 17) +
               Pad2((U.Sec Mod 86400) Div 3600) + ':' +
               Pad2((U.Sec Mod 3600) Div 60) + '    0.00s ' +
               CmdOf(U.Pid) + #10);
      End;
    SysClose(Fd);
  End;
End;

Type
  TRecs = Array[0..299] Of TUtmp;

Var
  Recs : TRecs;

Procedure DoLast;
Var Fd, N, K, J, Cnt, Lim, Dur, I : LongInt; U : TUtmp; A, Who1, Lg : String;
    Out : LongInt; S : String; Closed : Boolean;
Begin
  Lim := 1000000;
  Who1 := '';
  I := 1;
  While I < SysArgCount Do
  Begin
    A := SysArgStr(I);
    If A = '-n' Then
    Begin
      Inc(I);
      Val(SysArgStr(I), Lim, K);
    End
    Else If (Length(A) > 1) And (A[1] = '-') And (A[2] >= '0') And
            (A[2] <= '9') Then Val(Copy(A, 2, 9), Lim, K)
    Else Who1 := A;
    Inc(I);
  End;
  Fd := SysOpen('/var/log/wtmp', 0, 0);
  If Fd < 0 Then
  Begin
    SysPut(2, 'last: /var/log/wtmp : ' + SysErrorText(SysErrno) + #10);
    SysExit(1);
  End;
  N := 0;
  While SysRead(Fd, U, UtSize) = UtSize Do
  Begin
    If N >= 300 Then
    Begin
      For K := 0 To 298 Do Recs[K] := Recs[K + 1];
      N := 299;
    End;
    Recs[N] := U;
    Inc(N);
  End;
  SysClose(Fd);
  Cnt := 0;
  For K := N - 1 DownTo 0 Do
  Begin
    If (Recs[K].Typ = UtBoot) Or (Recs[K].Typ = UtUser) Then
    Begin
      If (Who1 <> '') And (UtUserS(Recs[K]) <> Who1) Then Continue;
      If Cnt >= Lim Then Break;
      Inc(Cnt);
      If Recs[K].Typ = UtBoot Then S := PadR('reboot', 9) +
        PadR('system boot', 13)
      Else S := PadR(UtUserS(Recs[K]), 9) + PadR(UtLineS(Recs[K]), 13);
      S := S + PadR(UtHostS(Recs[K]), 17) + DateL(Recs[K].Sec) + ' ';
      { recherche de la fin }
      Closed := False;
      For J := K + 1 To N - 1 Do
      Begin
        If (Recs[K].Typ = UtUser) And (Recs[J].Typ = UtDead) And
           (UtLineS(Recs[J]) = UtLineS(Recs[K])) Then
        Begin
          Dur := Recs[J].Sec - Recs[K].Sec;
          S := S + '- ' + Pad2((Recs[J].Sec Mod 86400) Div 3600) + ':' +
               Pad2((Recs[J].Sec Mod 3600) Div 60) + '  (' +
               Pad2(Dur Div 3600) + ':' + Pad2((Dur Mod 3600) Div 60) + ')';
          Closed := True;
          Break;
        End;
        If (Recs[K].Typ = UtBoot) And (Recs[J].Typ = UtBoot) Then
        Begin
          Dur := Recs[J].Sec - Recs[K].Sec;
          S := S + '- ' + Pad2((Recs[J].Sec Mod 86400) Div 3600) + ':' +
               Pad2((Recs[J].Sec Mod 3600) Div 60) + '  (' +
               Pad2(Dur Div 3600) + ':' + Pad2((Dur Mod 3600) Div 60) + ')';
          Closed := True;
          Break;
        End;
        If (Recs[K].Typ = UtUser) And (Recs[J].Typ = UtBoot) Then
        Begin
          S := S + '- crash';
          Closed := True;
          Break;
        End;
      End;
      If Not Closed Then
        If Recs[K].Typ = UtBoot Then S := S + 'still running'
        Else S := S + 'still logged in';
      SysPut(1, S + #10);
    End;
  End;
  If N > 0 Then
    SysPut(1, #10 + 'wtmp begins ' + DateL(Recs[0].Sec) + #10);
End;

Var K : LongInt;
Begin
  Prog := SysArgStr(0);
  K := Length(Prog);
  While (K > 0) And (Prog[K] <> '/') Do Dec(K);
  Prog := Copy(Prog, K + 1, 255);
  If Prog = 'users' Then DoUsers
  Else If Prog = 'w' Then DoW
  Else If Prog = 'last' Then DoLast
  Else DoWho;
  SysExit(0);
End.
