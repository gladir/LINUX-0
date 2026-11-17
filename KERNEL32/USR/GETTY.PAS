{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2026
  @website(https://www.gladir.com/linux-0)
  @abstract(Target: LPC -3X)
  @description: /sbin/getty de KERNEL32, lance par init sur chaque terminal.
   Usage : getty [terminal [type]]   (par exemple getty tty1 linux)
   Ouvre /dev/<terminal> (ou le chemin absolu donne), en fait le terminal
   de controle d'une nouvelle session (setsid, TIOCSCTTY), le remet dans
   son etat normal (mode ligne, echo, ^C...), affiche /etc/issue (\n nom de
   la machine, \s systeme, \r version du noyau, \v version, \m machine,
   \l terminal, \d date, \t heure, \\ une barre oblique inverse) puis
   "machine login: ", lit le nom et execute /bin/login avec ce nom (en
   lui transmettant TERM et LANGUAGE). Sans argument, getty agit sur son
   entree standard. Messages selon LANGUAGE (FR, EN, GR, SP, IT).
}

Program Getty;

Const
  M : Array[1..3, 1..5] Of PChar = (
    ('getty : impossible d''ouvrir ', 'getty: cannot open ',
     'getty: kann nicht geoeffnet werden: ', 'getty: no se puede abrir ',
     'getty: impossibile aprire '),
    ('Usage : getty [terminal [type]]', 'Usage: getty [tty [type]]',
     'Aufruf: getty [Terminal [Typ]]', 'Uso: getty [terminal [tipo]]',
     'Uso: getty [terminale [tipo]]'),
    ('getty : /bin/login : ', 'getty: /bin/login: ', 'getty: /bin/login: ',
     'getty: /bin/login: ', 'getty: /bin/login: '));

Var
  Tty, Term, Lang, A, Name, Host : String;
  U : TUtsName;
  T : TSysTermios;
  Fd, N : LongInt;
  C : Char;

Function Msg(Id : LongInt) : String;
Var P : PChar; X : String;
Begin
  P := M[Id, SysLang];
  X := '';
  While P^ <> #0 Do
  Begin
    X := X + P^;
    Inc(P);
  End;
  Msg := X;
End;

Function Num2(V : LongInt) : String;
Var S : String;
Begin
  Str(V, S);
  If Length(S) < 2 Then S := '0' + S;
  Num2 := S;
End;

{ date et heure UTC : AAAA-MM-JJ et HH:MM }
Procedure DateTime(Var D, H : String);
Var T0, Days, Secs, Z, Era, Doe, Yoe, Doy, Mp, Y, Mo, Dd : LongInt;
    Ys : String;
Begin
  T0 := SysTime;
  Days := T0 Div 86400;
  Secs := T0 Mod 86400;
  Z := Days + 719468;
  Era := Z Div 146097;
  Doe := Z - Era * 146097;
  Yoe := (Doe - Doe Div 1460 + Doe Div 36524 - Doe Div 146096) Div 365;
  Y := Yoe + Era * 400;
  Doy := Doe - (365 * Yoe + Yoe Div 4 - Yoe Div 100);
  Mp := (5 * Doy + 2) Div 153;
  Dd := Doy - (153 * Mp + 2) Div 5 + 1;
  If Mp < 10 Then Mo := Mp + 3 Else Mo := Mp - 9;
  If Mo <= 2 Then Inc(Y);
  Str(Y, Ys);
  D := Ys + '-' + Num2(Mo) + '-' + Num2(Dd);
  H := Num2(Secs Div 3600) + ':' + Num2((Secs Mod 3600) Div 60);
End;

{ affiche /etc/issue en interpretant les sequences \x }
Procedure Issue;
Var Fd, N, K : LongInt; B : Array[0..255] Of Char; Esc : Boolean;
    S, D, H : String;
Begin
  Fd := SysOpen('/etc/issue', O_RDONLY, 0);
  If Fd < 0 Then
  Begin
    SysPut(1, #10 + U.SysName + ' ' + U.Release + ' (' + U.NodeName + ')'
           + #10#10);
    Exit;
  End;
  Esc := False;
  Repeat
    N := SysRead(Fd, B, 256);
    S := '';
    For K := 0 To N - 1 Do
    Begin
      If Esc Then
      Begin
        Esc := False;
        Case B[K] Of
          'n' : S := S + U.NodeName;
          's' : S := S + U.SysName;
          'r' : S := S + U.Release;
          'v' : S := S + U.Version;
          'm' : S := S + U.Machine;
          'l' : S := S + Tty;
          'd' : Begin DateTime(D, H); S := S + D; End;
          't' : Begin DateTime(D, H); S := S + H; End;
          '\' : S := S + '\';
        Else S := S + '\' + B[K];
        End;
      End
      Else If B[K] = '\' Then Esc := True
      Else S := S + B[K];
      If Length(S) > 200 Then
      Begin
        SysPut(1, S);
        S := '';
      End;
    End;
    SysPut(1, S);
  Until N <= 0;
  SysClose(Fd);
End;

BEGIN
  SysSigAction(SIGINT, SIG_IGN, 0);
  SysSigAction(SIGQUIT, SIG_IGN, 0);
  SysSigAction(SIGTSTP, SIG_IGN, 0);
  Tty := '';
  Term := '';
  If SysArgCount > 1 Then Tty := SysArgStr(1);
  If SysArgCount > 2 Then Term := SysArgStr(2);
  If (Tty = '/?') Or (Tty = '-h') Or (Tty = '--help') Then
  Begin
    SysPut(1, Msg(2) + #10);
    SysExit(0);
  End;
  If Tty <> '' Then
  Begin
    SysSetSid;
    If Tty[1] = '/' Then A := Tty Else A := '/dev/' + Tty;
    Fd := SysOpen(A, O_RDWR, 0);
    If Fd < 0 Then
    Begin
      SysPut(2, Msg(1) + A + ' : ' + SysErrorText(SysErrno) + #10);
      SysExit(1);
    End;
    SysIoctlL(Fd, TIOCSCTTY, 1);
    SysDup2(Fd, 0);
    SysDup2(Fd, 1);
    SysDup2(Fd, 2);
    If Fd > 2 Then SysClose(Fd);
  End;
  If SysTcGetAttr(0, T) = 0 Then
  Begin
    T.IFlag := (T.IFlag Or TTY_ICRNL Or TTY_IXON) And Not (TTY_INLCR Or
               TTY_ISTRIP);
    T.OFlag := T.OFlag Or TTY_OPOST Or TTY_ONLCR;
    T.LFlag := T.LFlag Or TTY_ISIG Or TTY_ICANON Or TTY_ECHO Or TTY_ECHOE
               Or TTY_ECHOK;
    T.CC[TTY_VINTR] := 3;
    T.CC[TTY_VQUIT] := 28;
    T.CC[TTY_VERASE] := 127;
    T.CC[TTY_VKILL] := 21;
    T.CC[TTY_VEOF] := 4;
    T.CC[TTY_VSUSP] := 26;
    SysTcSetAttr(0, 0, T);
  End;
  Lang := SysGetEnv('LANGUAGE');
  If Term = '' Then Term := SysGetEnv('TERM');
  SysUname(U);
  Host := U.NodeName;
  Repeat
    Issue;
    SysPut(1, Host + ' login: ');
    Name := '';
    Repeat
      N := SysRead(0, C, 1);
      If N <= 0 Then SysExit(0);
      If C = #10 Then Break;
      If (C > ' ') And (Length(Name) < 31) Then Name := Name + C;
    Until False;
  Until Name <> '';
  SysSigAction(SIGINT, SIG_DFL, 0);
  SysSigAction(SIGQUIT, SIG_DFL, 0);
  SysSigAction(SIGTSTP, SIG_DFL, 0);
  SysArgReset;
  SysArgAdd('login');
  SysArgAdd(Name);
  If Lang <> '' Then SysEnvAdd('LANGUAGE=' + Lang);
  If Term <> '' Then SysEnvAdd('TERM=' + Term);
  SysEnvAdd('PATH=/sbin:/bin:/usr/sbin:/usr/bin');
  SysArgExec('/bin/login');
  SysPut(2, Msg(3) + SysErrorText(SysErrno) + #10);
  SysExit(1);
END.
