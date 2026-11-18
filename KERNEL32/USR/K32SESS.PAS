{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2026
  @website(https://www.gladir.com/linux-0)
  @abstract(Target: LPC -3X)
  @description: k32-session : mode de demarrage de KERNEL32.
   k32-session get            affiche le mode (terminal, kde, gnome, geoworks)
   k32-session set MODE       l'ecrit dans /etc/k32/session
   k32-session run            lance l'environnement du mode ; rend 0 quand il
                              se termine normalement, 10 : /dev/fb0
                              indisponible, 11 : programme absent, 12 :
                              l'environnement a echoue (repli : terminal)
   k32-session tty TTY        pour init : run puis getty TTY (retour au login
                              a la sortie de l'environnement ; le terminal
                              texte reste toujours disponible)
   k32-session status         mode, /dev/fb0 et programme (diagnostic)
   Programmes : kde -> /usr/bin/k32-kde, gnome -> /usr/bin/k32-gnome,
   geoworks -> /usr/bin/geoworks. Codes de sortie de l'environnement : 100
   redemarrer, 101 eteindre (executes ici, en root). L'environnement tourne
   par root (fb0, souris, pty) ; ses terminaux passent au premier utilisateur
   normal (uid >= 1000, ou /etc/k32/session-user) via K32_USER/UID/GID/HOME.
   Journal : /var/log/k32-session.log. }

Program K32Sess;

Const
  SESSFILE = '/etc/k32/session';
  LOGFILE = '/var/log/k32-session.log';
  FastFail = 8;                  { secondes : un echec plus rapide = repli }

Var
  Prog : String;

Function NumS(V : LongInt) : String;
Var S : String;
Begin
  Str(V, S);
  NumS := S;
End;

Function ValidMode(Const M : String) : Boolean;
Begin
  ValidMode := (M = 'terminal') Or (M = 'kde') Or (M = 'gnome') Or
               (M = 'geoworks');
End;

Function Lower(Const S : String) : String;
Var I : LongInt; R : String;
Begin
  R := S;
  For I := 1 To Length(R) Do
    If (R[I] >= 'A') And (R[I] <= 'Z') Then R[I] := Chr(Ord(R[I]) + 32);
  Lower := R;
End;

Function Trim(Const S : String) : String;
Var A, B : LongInt;
Begin
  A := 1;
  B := Length(S);
  While (A <= B) And ((S[A] = ' ') Or (S[A] = #9) Or (S[A] = #13)) Do Inc(A);
  While (B >= A) And ((S[B] = ' ') Or (S[B] = #9) Or (S[B] = #13)) Do Dec(B);
  Trim := Copy(S, A, B - A + 1);
End;

{ lit un fichier d'une ligne ; '' si absent }
Function ReadLine1(Const Path : String) : String;
Var Fd : LongInt; L : String;
Begin
  ReadLine1 := '';
  Fd := SysOpen(Path, O_RDONLY, 0);
  If Fd < 0 Then Exit;
  If SysReadLine(Fd, L) Then ReadLine1 := Trim(L);
  SysClose(Fd);
End;

Function ReadMode : String;
Var M : String;
Begin
  M := Lower(ReadLine1(SESSFILE));
  If ValidMode(M) Then ReadMode := M Else ReadMode := 'terminal';
End;

Procedure Log(Const S : String);
Var Fd, T : LongInt; L : String;
Begin
  T := SysTime;
  Fd := SysOpen(LOGFILE, O_WRONLY Or O_CREAT Or O_APPEND, 420);
  If Fd < 0 Then Exit;
  L := NumS(T) + ' ' + S + #10;
  SysWrite(Fd, L[1], Length(L));
  SysClose(Fd);
End;

Procedure Say(Const S : String);
Begin
  SysPut(2, 'k32-session: ' + S + #10);
  Log(S);
End;

Function FbOk : Boolean;
Var Fd : LongInt; Vi : Array[0..39] Of LongInt;
Begin
  FbOk := False;
  Fd := SysOpen('/dev/fb0', O_RDWR, 0);
  If Fd < 0 Then Exit;
  FillChar(Vi, SizeOf(Vi), 0);
  FbOk := SysIoctl(Fd, $4600, Vi) >= 0;
  SysClose(Fd);
End;

Function ProgFor(Const M : String) : String;
Var N : String;
Begin
  If M = 'kde' Then N := 'k32-kde'
  Else If M = 'gnome' Then N := 'k32-gnome'
  Else If M = 'geoworks' Then N := 'geoworks'
  Else N := '';
  ProgFor := '';
  If N = '' Then Exit;
  If SysAccess('/usr/bin/' + N, 1) = 0 Then ProgFor := '/usr/bin/' + N
  Else If SysAccess('/bin/' + N, 1) = 0 Then ProgFor := '/bin/' + N
  Else ProgFor := '/usr/bin/' + N;
End;

Function BaseOf(Const P : String) : String;
Var K : LongInt;
Begin
  K := Length(P);
  While (K > 0) And (P[K] <> '/') Do Dec(K);
  BaseOf := Copy(P, K + 1, 40);
End;

{ utilisateur de la session : session-user, sinon le premier uid >= 1000 }
Function PickUser(Var P : TSysPasswd) : Boolean;
Var N : String; Fd : LongInt; L : String; K : LongInt;
Begin
  PickUser := False;
  N := ReadLine1('/etc/k32/session-user');
  If (N <> '') And SysGetPwNam(N, P) Then
  Begin
    PickUser := True;
    Exit;
  End;
  Fd := SysOpen('/etc/passwd', O_RDONLY, 0);
  If Fd < 0 Then Exit;
  While SysReadLine(Fd, L) Do
  Begin
    K := Pos(':', L);
    If K > 1 Then
      If SysGetPwNam(Copy(L, 1, K - 1), P) Then
        If (P.Uid >= 1000) And (P.Uid < 60000) Then
        Begin
          PickUser := True;
          Break;
        End;
  End;
  SysClose(Fd);
End;

{ remet la console en mode texte (l'environnement a pu planter) }
Procedure TextMode;
Var Fd : LongInt;
Begin
  Fd := SysOpen('/dev/tty0', O_RDWR, 0);
  If Fd < 0 Then Exit;
  SysIoctlL(Fd, $4B3A, 0);
  SysClose(Fd);
  SysPut(1, #27'[0m'#27'[2J'#27'[H');
End;

Procedure OpenTty(Const Tty : String);
Var Fd : LongInt; A : String;
Begin
  A := Tty;
  If (A <> '') And (A[1] <> '/') Then A := '/dev/' + A;
  SysSetSid;
  Fd := SysOpen(A, O_RDWR, 0);
  If Fd < 0 Then Exit;
  SysIoctlL(Fd, $540E, 1);
  SysDup2(Fd, 0);
  SysDup2(Fd, 1);
  SysDup2(Fd, 2);
  If Fd > 2 Then SysClose(Fd);
End;

Procedure RunShellCmd(Const P : String);
Var Pid, St : LongInt;
Begin
  Pid := SysFork;
  If Pid = 0 Then
  Begin
    SysArgReset;
    SysArgAdd(Copy(P, Pos('/', P) + 1, 40));
    SysEnvInherit;
    SysArgExec(P);
    SysExit(127);
  End;
  If Pid > 0 Then SysWaitPid(Pid, St, 0);
End;

{ lance l'environnement ; rend le code de session (voir l'en-tete) }
Function RunSession(Const Tty : String) : LongInt;
Var M, Pg : String; Pu : TSysPasswd; HaveUser : Boolean;
    Pid, St, T0, Rc : LongInt;
Begin
  RunSession := 0;
  M := ReadMode;
  If M = 'terminal' Then Exit;
  If Not FbOk Then
  Begin
    Say('/dev/fb0 indisponible : demarrage en terminal texte (mode ' + M + ')');
    RunSession := 10;
    Exit;
  End;
  Pg := ProgFor(M);
  If SysAccess(Pg, 1) <> 0 Then
  Begin
    Say(Pg + ' absent : demarrage en terminal texte (mode ' + M + ')');
    RunSession := 11;
    Exit;
  End;
  HaveUser := PickUser(Pu);
  T0 := SysTime;
  Pid := SysFork;
  If Pid = 0 Then
  Begin
    SysArgReset;
    SysArgAdd(BaseOf(Pg));
    SysEnvAdd('TERM=linux');
    SysEnvAdd('PATH=/sbin:/bin:/usr/sbin:/usr/bin');
    SysEnvAdd('XDG_SESSION_TYPE=tty');
    SysEnvAdd('XDG_SESSION_CLASS=user');
    If M = 'kde' Then SysEnvAdd('XDG_CURRENT_DESKTOP=KDE')
    Else If M = 'gnome' Then SysEnvAdd('XDG_CURRENT_DESKTOP=GNOME');
    SysEnvAdd('K32_SESSION=' + M);
    SysEnvAdd('HOME=/root');
    SysEnvAdd('USER=root');
    SysEnvAdd('LOGNAME=root');
    SysEnvAdd('SHELL=/bin/sh');
    SysEnvAdd('K32_TTY=' + Tty);
    If HaveUser Then
    Begin
      { le bureau reste root (fb0, souris, pty) ; ses terminaux passent a
        l'utilisateur }
      SysEnvAdd('K32_USER=' + Pu.Name);
      SysEnvAdd('K32_UID=' + NumS(Pu.Uid));
      SysEnvAdd('K32_GID=' + NumS(Pu.Gid));
      SysEnvAdd('K32_HOME=' + Pu.Home);
    End
    Else
    Begin
      SysEnvAdd('K32_USER=root');
      SysEnvAdd('K32_UID=0');
      SysEnvAdd('K32_GID=0');
      SysEnvAdd('K32_HOME=/root');
    End;
    SysChdir('/root');
    SysArgExec(Pg);
    SysExit(127);
  End;
  If Pid < 0 Then
  Begin
    Say('fork impossible');
    RunSession := 12;
    Exit;
  End;
  SysWaitPid(Pid, St, 0);
  TextMode;
  If SysWIfExited(St) Then Rc := SysWExitStatus(St)
  Else Rc := 128 + SysWTermSig(St);
  If Rc = 100 Then
  Begin
    Log('redemarrage demande par ' + M);
    RunShellCmd('/sbin/reboot');
  End
  Else If Rc = 101 Then
  Begin
    Log('arret demande par ' + M);
    RunShellCmd('/sbin/poweroff');
  End
  Else If (Rc <> 0) And (SysTime - T0 < FastFail) Then
  Begin
    Say('l''environnement ' + M + ' a echoue (code ' + NumS(Rc) +
        ') : demarrage en terminal texte');
    SysSleep(3);
    RunSession := 12;
    Exit;
  End
  Else Log('fin de la session ' + M + ' (code ' + NumS(Rc) + ')');
End;

Procedure Usage;
Begin
  SysPut(2, 'Usage: k32-session get | set terminal|kde|gnome|geoworks | ' +
         'run | tty TTY | status' + #10);
  SysExit(2);
End;

Var
  Cmd, M : String;
  Fd, Rc : LongInt;
Begin
  If SysArgCount < 2 Then Usage;
  Cmd := SysArgStr(1);
  If Cmd = 'get' Then
    SysPut(1, ReadMode + #10)
  Else If Cmd = 'set' Then
  Begin
    If SysArgCount < 3 Then Usage;
    M := Lower(SysArgStr(2));
    If Not ValidMode(M) Then
    Begin
      SysPut(2, 'k32-session: mode invalide : ' + M +
             ' (terminal, kde, gnome, geoworks)' + #10);
      SysExit(1);
    End;
    SysMkdir('/etc', 493);
    SysMkdir('/etc/k32', 493);
    Fd := SysOpen(SESSFILE, O_WRONLY Or O_CREAT Or O_TRUNC, 420);
    If Fd < 0 Then
    Begin
      SysPut(2, 'k32-session: ' + SESSFILE + ' : ' +
             SysErrorText(SysErrno) + #10);
      SysExit(1);
    End;
    M := M + #10;
    SysWrite(Fd, M[1], Length(M));
    SysClose(Fd);
  End
  Else If Cmd = 'run' Then
    SysExit(RunSession('/dev/tty1'))
  Else If Cmd = 'tty' Then
  Begin
    If SysArgCount < 3 Then Usage;
    OpenTty(SysArgStr(2));
    Rc := RunSession('/dev/' + SysArgStr(2));
    SysArgReset;
    SysArgAdd('getty');
    SysArgAdd(SysArgStr(2));
    SysArgAdd('linux');
    SysEnvInherit;
    SysArgExec('/sbin/getty');
    SysPut(2, 'k32-session: /sbin/getty : ' + SysErrorText(SysErrno) + #10);
    SysExit(1);
  End
  Else If Cmd = 'status' Then
  Begin
    M := ReadMode;
    Prog := ProgFor(M);
    SysPut(1, 'mode: ' + M + #10);
    If FbOk Then SysPut(1, 'fb0: ok' + #10) Else SysPut(1, 'fb0: absent' + #10);
    If Prog <> '' Then
      If SysAccess(Prog, 1) = 0 Then SysPut(1, 'programme: ' + Prog + #10)
      Else SysPut(1, 'programme: ' + Prog + ' (absent)' + #10);
  End
  Else Usage;
End.
