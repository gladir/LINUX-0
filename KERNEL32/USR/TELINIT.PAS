{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2026
  @website(https://www.gladir.com/linux-0)
  @abstract(Target: LPC -3X)
  @description: telinit, runlevel, shutdown (nom lu dans argv[0]) : niveaux
      d'execution de init (telinit 0-6 q S ; runlevel) et arret programme
      (shutdown [-h|-H|-P|-r|-c|-k] [-t secondes] now|+minutes|hh:mm
      [message]) ; le message est diffuse aux terminaux de /var/run/utmp.
}

Program TELINIT;

{$I UTMP.INC}

Const
  UsageW : Array[1..5] Of PChar =
    ('Usage : ', 'Usage: ', 'Aufruf: ', 'Uso: ', 'Uso: ');
  Down : Array[1..5] Of PChar = (
    'Arret du systeme dans ', 'System going down in ',
    'System wird heruntergefahren in ', 'Apagando el sistema en ',
    'Arresto del sistema tra ');
  Mins : Array[1..5] Of PChar = (' minute(s)', ' minute(s)', ' Minute(n)',
    ' minuto(s)', ' minuto/i');
  Now1 : Array[1..5] Of PChar = ('Arret immediat du systeme',
    'System going down NOW', 'System wird SOFORT heruntergefahren',
    'Apagando el sistema AHORA', 'Arresto immediato del sistema');

Var
  Prog : String;

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

Procedure Usage(Const Syn : String);
Begin
  SysPut(2, PS(UsageW[SysLang]) + Syn + #10);
  SysExit(2);
End;

Procedure DoTelinit;
Var A : String; Fd : LongInt;
Begin
  If SysArgCount < 2 Then Usage('telinit {0-6|q|Q|s|S}');
  A := SysArgStr(1);
  If (Length(A) <> 1) Or (Pos(A, '0123456qQsSuU') = 0) Then
    Usage('telinit {0-6|q|Q|s|S}');
  If (A = 'u') Or (A = 'U') Then A := 'q';
  Fd := SysOpen('/var/run/init.req', $241, 420);
  If Fd < 0 Then
  Begin
    SysPut(2, 'telinit: /var/run/init.req : ' + SysErrorText(SysErrno) + #10);
    SysExit(1);
  End;
  SysPut(Fd, A + #10);
  SysClose(Fd);
  If SysKill(1, SIGHUP) < 0 Then
  Begin
    SysPut(2, 'telinit: ' + SysErrorText(SysErrno) + #10);
    SysExit(1);
  End;
End;

Procedure DoRunlevel;
Var L : String; Fd : LongInt;
Begin
  Fd := SysOpen('/var/run/runlevel', 0, 0);
  If Fd < 0 Then
  Begin
    SysPut(1, 'unknown' + #10);
    SysExit(1);
  End;
  If SysReadLine(Fd, L) Then SysPut(1, L + #10);
  SysClose(Fd);
End;

{ diffuse un message a tous les terminaux ouverts }
Procedure Wall(Const Msg : String);
Var Fd, T : LongInt; U : TUtmp;
Begin
  Fd := SysOpen('/var/run/utmp', 0, 0);
  If Fd < 0 Then Exit;
  While SysRead(Fd, U, UtSize) = UtSize Do
    If U.Typ = UtUser Then
    Begin
      T := SysOpen('/dev/' + UtLineS(U), 1, 0);
      If T >= 0 Then
      Begin
        SysPut(T, #10 + 'Broadcast message from root:' + #10 + Msg + #10);
        SysClose(T);
      End;
    End;
  SysClose(Fd);
  SysPut(2, Msg + #10);
End;

Procedure DoShutdown;
Var
  I, Delay, K, E, Sig, H, M : LongInt;
  A, When, Msg : String;
  Cancel, KeepUp : Boolean;
Begin
  Sig := SIGUSR2;
  Cancel := False;
  KeepUp := False;
  When := '';
  Msg := '';
  Delay := 0;
  I := 1;
  While I < SysArgCount Do
  Begin
    A := SysArgStr(I);
    If A = '-h' Then Sig := SIGUSR2
    Else If A = '-P' Then Sig := SIGUSR2
    Else If A = '-H' Then Sig := SIGUSR1
    Else If A = '-r' Then Sig := SIGTERM
    Else If A = '-c' Then Cancel := True
    Else If A = '-k' Then KeepUp := True
    Else If (A = '-t') Or (A = '-a') Or (A = '-F') Or (A = '-f') Or
            (A = '-n') Or (A = '--no-wall') Then
    Begin
      If A = '-t' Then Inc(I);
    End
    Else If (Length(A) > 0) And (A[1] = '-') Then
      Usage('shutdown [-hHPrck] [-t sec] now|+minutes|hh:mm [message]')
    Else If When = '' Then When := A
    Else Msg := Msg + A + ' ';
    Inc(I);
  End;
  If Cancel Then
  Begin
    Wall('Arret annule / shutdown cancelled');
    SysExit(0);
  End;
  If When = '' Then
    Usage('shutdown [-hHPrck] [-t sec] now|+minutes|hh:mm [message]');
  If When = 'now' Then Delay := 0
  Else If When[1] = '+' Then
  Begin
    Val(Copy(When, 2, 9), K, E);
    If E <> 0 Then Usage('shutdown [options] +minutes');
    Delay := K * 60;
  End
  Else
  Begin
    K := Pos(':', When);
    If K = 0 Then Usage('shutdown [options] hh:mm');
    Val(Copy(When, 1, K - 1), H, E);
    Val(Copy(When, K + 1, 9), M, E);
    Delay := (H * 3600 + M * 60) - (SysTime Mod 86400);
    If Delay < 0 Then Delay := Delay + 86400;
  End;
  If Delay > 0 Then
  Begin
    Wall(PS(Down[SysLang]) + NumS(Delay Div 60) + PS(Mins[SysLang]) +
         ' ' + Msg);
    SysSleep(Delay);
  End
  Else Wall(PS(Now1[SysLang]) + ' ' + Msg);
  If KeepUp Then SysExit(0);
  SysSync;
  If SysKill(1, Sig) < 0 Then
  Begin
    SysPut(2, 'shutdown: ' + SysErrorText(SysErrno) + #10);
    SysExit(1);
  End;
End;

Var K : LongInt;
Begin
  Prog := SysArgStr(0);
  K := Length(Prog);
  While (K > 0) And (Prog[K] <> '/') Do Dec(K);
  Prog := Copy(Prog, K + 1, 255);
  If Prog = 'runlevel' Then DoRunlevel
  Else If Prog = 'shutdown' Then DoShutdown
  Else DoTelinit;
  SysExit(0);
End.
