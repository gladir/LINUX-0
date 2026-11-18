{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2026
  @website(https://www.gladir.com/linux-0)
  @abstract(Target: LPC -3X)
  @description: /sbin/init (processus 1) de KERNEL32. Lit /etc/inittab
   (ou, a defaut, /etc/ttys), lance les programmes de demarrage, relance
   getty sur chaque terminal et recolte les processus orphelins.
   Format de /etc/inittab (une ligne par entree, # = commentaire) :
     id:niveaux:action:[VAR=valeur ...] commande arguments
   Actions : sysinit (execute et attendu au demarrage), wait (attendu),
   once (lance une fois), respawn (relance a chaque fin), ctrlaltdel
   (Ctrl-Alt-Suppr : SIGINT), shutdown (avant l'arret).
   Format de /etc/ttys (compatible KERNEL16UNIX) : 1 caractere actif (1) ou
   0, 1 caractere de vitesse (ignore), puis le nom du terminal de /dev.
   Signaux (comme busybox) : SIGUSR1 arret, SIGUSR2 extinction, SIGTERM
   redemarrage, SIGINT Ctrl-Alt-Suppr, SIGHUP relecture de /etc/inittab.
   Arret : entrees shutdown, SIGTERM puis SIGKILL a tous les processus,
   sync, appel systeme reboot.
   Langue : init cherche LANGUAGE=XX dans /etc/profile puis dans
   /etc/default/locale (ecrit par l'installateur) et la transmet aux
   programmes (FR par defaut, EN, GR, SP, IT).
   Si init n'est pas le processus 1 (essai sur un hote), il s'arrete sans
   appeler reboot.
}

Program Init;

{$I UTMP.INC}

{$I-}

Const
  MAXENT = 32;
  aSysinit = 1; aWait = 2; aOnce = 3; aRespawn = 4; aCtrlAltDel = 5;
  aShutdown = 6; aInitDef = 7;
  { messages : colonnes FR, EN, GR (allemand), SP, IT }
  M : Array[1..5, 1..5] Of PChar = (
    ('init : demarrage de LINUX-0', 'init: starting LINUX-0',
     'init: LINUX-0 wird gestartet', 'init: arrancando LINUX-0',
     'init: avvio di LINUX-0'),
    ('init : session trop souvent relancee, suspendue : ',
     'init: session respawning too fast, suspended: ',
     'init: Sitzung wird zu haeufig neu gestartet, ausgesetzt: ',
     'init: sesion reiniciada demasiado rapido, suspendida: ',
     'init: sessione riavviata troppo in fretta, sospesa: '),
    ('init : arret du systeme', 'init: system is going down',
     'init: System wird heruntergefahren', 'init: apagando el sistema',
     'init: arresto del sistema'),
    ('init : impossible d''executer ', 'init: cannot execute ',
     'init: kann nicht ausgefuehrt werden: ',
     'init: no se puede ejecutar ', 'init: impossibile eseguire '),
    ('init : redemarrage', 'init: restarting', 'init: Neustart',
     'init: reiniciando', 'init: riavvio'));

Type
  TEntry = Record
    Id : String[8];
    Lv : String[8];                 { niveaux d'execution }
    Action : LongInt;
    Cmd : String[200];
    Pid : LongInt;
    T0, T1, T2, T3, T4 : LongInt;   { dates des 5 derniers lancements }
    Hold : LongInt;                 { suspendu jusqu'a cette date }
  End;

Var
  E : Array[1..MAXENT] Of TEntry;
  NE : LongInt;
  LangName : String;
  SigFlag : LongInt;     { signal recu : 0 aucun }
  IsInit : Boolean;
  RunLevel, DefLevel, PrevLevel : Char;
  I, W, St : LongInt;
  UB : TUtmp;

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

Procedure Say(Const S : String);
Begin
  SysPut(2, S + #10);
End;

Procedure OnSignal(Sig : LongInt);
Begin
  SigFlag := Sig;
End;

{ langue : LANGUAGE=XX de /etc/profile, sinon de /etc/default/locale, sinon
  de l'environnement }
Function FindLang(Const Name : String) : String;
Var F : Text; S, R : String; K : LongInt;
Begin
  R := '';
  Assign(F, Name);
  Reset(F);
  If IOResult = 0 Then
  Begin
    While Not Eof(F) Do
    Begin
      ReadLn(F, S);
      If Copy(S, 1, 7) = 'export ' Then Delete(S, 1, 7);
      If Copy(S, 1, 9) = 'LANGUAGE=' Then
      Begin
        Delete(S, 1, 9);
        While (S <> '') And Not (UpCase(S[1]) In ['A'..'Z']) Do Delete(S, 1, 1);
        K := 1;
        While (K <= Length(S)) And (UpCase(S[K]) In ['A'..'Z']) Do Inc(K);
        R := Copy(S, 1, K - 1);
      End;
    End;
    Close(F);
  End;
  FindLang := R;
End;

Procedure ReadLang;
Begin
  LangName := FindLang('/etc/profile');
  If LangName = '' Then LangName := FindLang('/etc/default/locale');
  If LangName = '' Then LangName := SysGetEnv('LANGUAGE');
  If LangName <> '' Then SysSetLang(SysLangOf(LangName));
End;

Procedure AddEntry(Const Id : String; Act : LongInt; Const Cmd : String);
Begin
  If NE >= MAXENT Then Exit;
  Inc(NE);
  E[NE].Id := Id;
  E[NE].Lv := '';
  E[NE].Action := Act;
  E[NE].Cmd := Cmd;
  E[NE].Pid := 0;
  E[NE].T0 := 0; E[NE].T1 := 0; E[NE].T2 := 0; E[NE].T3 := 0; E[NE].T4 := 0;
  E[NE].Hold := 0;
End;

Function ActionOf(Const S : String) : LongInt;
Begin
  ActionOf := 0;
  If S = 'sysinit' Then ActionOf := aSysinit
  Else If S = 'wait' Then ActionOf := aWait
  Else If S = 'once' Then ActionOf := aOnce
  Else If S = 'respawn' Then ActionOf := aRespawn
  Else If S = 'ctrlaltdel' Then ActionOf := aCtrlAltDel
  Else If S = 'shutdown' Then ActionOf := aShutdown
  Else If S = 'initdefault' Then ActionOf := aInitDef;
End;

Function Exists(Const P : String) : Boolean;
Var St : TSysStat;
Begin
  Exists := SysStat(P, St) = 0;
End;

Procedure ReadInittab;
Var F : Text; S, Id, A, Lv : String; K, Act : LongInt;
Begin
  NE := 0;
  Assign(F, '/etc/inittab');
  Reset(F);
  If IOResult = 0 Then
  Begin
    While Not Eof(F) Do
    Begin
      ReadLn(F, S);
      While (S <> '') And ((S[1] = ' ') Or (S[1] = #9)) Do Delete(S, 1, 1);
      If (S = '') Or (S[1] = '#') Then Continue;
      K := Pos(':', S);
      If K = 0 Then Continue;
      Id := Copy(S, 1, K - 1);
      Delete(S, 1, K);
      K := Pos(':', S);                  { niveaux d'execution }
      If K = 0 Then Continue;
      Lv := Copy(S, 1, K - 1);
      Delete(S, 1, K);
      K := Pos(':', S);
      If K = 0 Then Continue;
      A := Copy(S, 1, K - 1);
      Delete(S, 1, K);
      Act := ActionOf(A);
      If Act = aInitDef Then
      Begin
        If Lv <> '' Then DefLevel := Lv[1];
      End
      Else If (Act <> 0) And (S <> '') Then
      Begin
        AddEntry(Id, Act, S);
        E[NE].Lv := Lv;
      End;
    End;
    Close(F);
    Exit;
  End;
  { /etc/ttys : 1 actif, 1 vitesse, nom }
  Assign(F, '/etc/ttys');
  Reset(F);
  If IOResult = 0 Then
  Begin
    While Not Eof(F) Do
    Begin
      ReadLn(F, S);
      If (Length(S) > 2) And (S[1] = '1') Then
        AddEntry(Copy(S, 3, 8), aRespawn, '/sbin/getty ' + Copy(S, 3, 40));
    End;
    Close(F);
    If NE > 0 Then Exit;
  End;
  { valeurs par defaut }
  If Exists('/etc/rc') Then AddEntry('rc', aSysinit, '/bin/sh /etc/rc');
  AddEntry('1', aRespawn, '/sbin/getty tty1');
  AddEntry('2', aRespawn, '/sbin/getty tty2');
  AddEntry('3', aRespawn, '/sbin/getty tty3');
  AddEntry('4', aRespawn, '/sbin/getty tty4');
  AddEntry('S0', aRespawn, 'TERM=vt100 /sbin/getty ttyS0');
  AddEntry('ca', aCtrlAltDel, '/sbin/reboot -f');
End;

{ lance la commande (VAR=valeur ... programme arguments) dans un fils }
Function Spawn(Const Cmd : String) : LongInt;
Var Pid, K : LongInt; S, W, Prog : String; HaveTerm : Boolean;
Begin
  Pid := SysFork;
  If Pid <> 0 Then
  Begin
    Spawn := Pid;
    Exit;
  End;
  { fils }
  SysSigAction(SIGINT, SIG_DFL, 0);
  SysSigAction(SIGTERM, SIG_DFL, 0);
  SysSigAction(SIGUSR1, SIG_DFL, 0);
  SysSigAction(SIGUSR2, SIG_DFL, 0);
  SysSigAction(SIGHUP, SIG_DFL, 0);
  SysSigAction(SIGTSTP, SIG_DFL, 0);
  SysArgReset;
  S := Cmd;
  Prog := '';
  HaveTerm := False;
  SysEnvAdd('PATH=/sbin:/bin:/usr/sbin:/usr/bin');
  SysEnvAdd('HOME=/');
  If LangName <> '' Then SysEnvAdd('LANGUAGE=' + LangName);
  While S <> '' Do
  Begin
    While (S <> '') And ((S[1] = ' ') Or (S[1] = #9)) Do Delete(S, 1, 1);
    If S = '' Then Break;
    K := 1;
    While (K <= Length(S)) And (S[K] <> ' ') And (S[K] <> #9) Do Inc(K);
    W := Copy(S, 1, K - 1);
    Delete(S, 1, K - 1);
    If (Prog = '') And (Pos('=', W) > 1) And (Pos('/', W) = 0) Then
    Begin
      If Copy(W, 1, 5) = 'TERM=' Then HaveTerm := True;
      SysEnvAdd(W);
    End
    Else
    Begin
      If Prog = '' Then Prog := W;
      SysArgAdd(W);
    End;
  End;
  If Not HaveTerm Then SysEnvAdd('TERM=linux');
  If Prog = '' Then SysExit(127);
  SysArgExec(Prog);
  Say(Msg(4) + Prog + ' : ' + SysErrorText(SysErrno));
  SysExit(127);
End;

{ l'entree K s'applique-t-elle au niveau d'execution courant ? }
Function InLevel(K : LongInt) : Boolean;
Begin
  InLevel := (E[K].Lv = '') Or (Pos(RunLevel, E[K].Lv) > 0);
End;

Function InLevelOf(K : LongInt; L : Char) : Boolean;
Begin
  InLevelOf := (E[K].Lv = '') Or (Pos(L, E[K].Lv) > 0);
End;

Function FindPid(P : LongInt) : LongInt;
Var K : LongInt;
Begin
  FindPid := 0;
  For K := 1 To NE Do
    If E[K].Pid = P Then FindPid := K;
End;

{ reinitialise les etats avec un nouveau lancement ; Vrai si trop rapide }
Function TooFast(K : LongInt) : Boolean;
Var Now : LongInt;
Begin
  Now := SysTime;
  TooFast := False;
  If Now < E[K].Hold Then
  Begin
    TooFast := True;
    Exit;
  End;
  E[K].T4 := E[K].T3; E[K].T3 := E[K].T2; E[K].T2 := E[K].T1;
  E[K].T1 := E[K].T0; E[K].T0 := Now;
  If (E[K].T4 <> 0) And (Now - E[K].T4 < 20) Then
  Begin
    E[K].Hold := Now + 60;
    Say(Msg(2) + E[K].Id);
    TooFast := True;
  End;
End;

Procedure StartRespawn(K : LongInt);
Begin
  If Not TooFast(K) Then E[K].Pid := Spawn(E[K].Cmd);
End;

{ attend la fin du processus Pid en recoltant les autres }
Procedure WaitFor(Pid : LongInt);
Var R, S2, K : LongInt;
Begin
  While True Do
  Begin
    R := SysWaitPid(-1, S2, 0);
    If R = Pid Then Exit;
    If R < 0 Then
    Begin
      If SysErrno <> 4 Then Exit;
      Continue;
    End;
    K := FindPid(R);
    If K > 0 Then E[K].Pid := 0;
  End;
End;

Procedure RunAll(Act : LongInt; Wait : Boolean);
Var K : LongInt; P : LongInt;
Begin
  For K := 1 To NE Do
    If (E[K].Action = Act) And InLevel(K) Then
    Begin
      P := Spawn(E[K].Cmd);
      If Wait And (P > 0) Then WaitFor(P)
      Else E[K].Pid := P;
    End;
End;

Procedure KillAll(Sig : LongInt);
{ comme Linux : tous les processus sauf init et l'appelant }
Begin
  SysKill(-1, Sig);
End;

Procedure Reap(Seconds : LongInt);
{ recolte les fils jusqu'a ce qu'il n'y en ait plus (ou Seconds secondes au
  plus) }
Var R, S2, T0, K : LongInt;
Begin
  T0 := SysTime;
  K := 0;
  While (SysTime - T0 < Seconds) And (K < 20000) Do
  Begin
    R := SysWaitPid(-1, S2, WNOHANG);
    If R < 0 Then Exit;
    If R = 0 Then
    Begin
      Inc(K);
      SysSleep(1);
    End;
  End;
End;

Procedure Shutdown(Cmd : LongInt);
Var K : LongInt;
Begin
  If Cmd = LINUX_REBOOT_RESTART Then Say(Msg(5)) Else Say(Msg(3));
  { on ne relance plus rien }
  For K := 1 To NE Do
    If E[K].Action = aRespawn Then E[K].Action := 0;
  RunAll(aShutdown, True);
  KillAll(SIGTERM);
  Reap(2);
  KillAll(SIGKILL);
  Reap(1);
  SysSync;
  If IsInit Then
  Begin
    SysReboot(LINUX_REBOOT_MAGIC1, LINUX_REBOOT_MAGIC2, Cmd);
    While True Do SysPause;
  End;
  SysExit(0);
End;

{ /var/run/runlevel : "precedent courant" (lu par la commande runlevel) }
Procedure WriteRunLevel;
Var Fd : LongInt;
Begin
  Fd := SysOpen('/var/run/runlevel', $241, 420);
  If Fd >= 0 Then
  Begin
    SysPut(Fd, PrevLevel + ' ' + RunLevel + #10);
    SysClose(Fd);
  End;
End;

{ passage au niveau d'execution New (telinit) }
Procedure ChangeLevel(New : Char);
Var OldE : Array[1..MAXENT] Of TEntry; NOld, J, K : LongInt; Found : Boolean;
    Pd : LongInt;
Begin
  If (New = '0') Then
  Begin
    Shutdown(LINUX_REBOOT_POWER_OFF);
    Exit;
  End;
  If New = '6' Then
  Begin
    Shutdown(LINUX_REBOOT_RESTART);
    Exit;
  End;
  NOld := NE;
  For K := 1 To NE Do OldE[K] := E[K];
  PrevLevel := RunLevel;
  RunLevel := New;
  ReadInittab;
  { les processus deja lances (meme id et meme commande) sont conserves }
  For K := 1 To NE Do
    For J := 1 To NOld Do
      If (OldE[J].Id = E[K].Id) And (OldE[J].Cmd = E[K].Cmd) Then
      Begin
        E[K].Pid := OldE[J].Pid;
        E[K].T0 := OldE[J].T0; E[K].T1 := OldE[J].T1;
        E[K].T2 := OldE[J].T2; E[K].T3 := OldE[J].T3;
        E[K].T4 := OldE[J].T4; E[K].Hold := OldE[J].Hold;
        OldE[J].Pid := 0;
      End;
  { arret des sessions qui ne sont plus de ce niveau }
  For J := 1 To NOld Do
    If OldE[J].Pid > 0 Then SysKill(OldE[J].Pid, SIGTERM);
  For K := 1 To NE Do
    If (E[K].Pid > 0) And (Not InLevel(K)) Then
    Begin
      SysKill(E[K].Pid, SIGTERM);
      E[K].Pid := 0;
    End;
  { wait / once du nouveau niveau, puis sessions }
  For K := 1 To NE Do
    If ((E[K].Action = aWait) Or (E[K].Action = aOnce)) And InLevel(K) And
       (E[K].Lv <> '') And (Not InLevelOf(K, PrevLevel)) Then
    Begin
      Pd := Spawn(E[K].Cmd);
      If (E[K].Action = aWait) And (Pd > 0) Then WaitFor(Pd);
    End;
  For K := 1 To NE Do
    If (E[K].Action = aRespawn) And InLevel(K) And (E[K].Pid = 0) Then
      StartRespawn(K);
  WriteRunLevel;
End;

{ demande 'R' de telinit (/var/run/init.req) : la racine a ete changee par
  pivot_root (l'installateur du CD demarre le systeme installe) ; init arrete
  tous les processus de l'ancienne racine puis se re-execute : le /sbin/init
  de la nouvelle racine, son /etc/inittab (/etc/rc demonte /oldroot). }
Procedure SwitchToNewRoot;
Var K : LongInt;
Begin
  For K := 1 To NE Do
    If E[K].Action = aRespawn Then E[K].Action := 0;
  KillAll(SIGTERM);
  Reap(2);
  KillAll(SIGKILL);
  Reap(1);
  SysSync;
  SysArgReset;
  SysArgAdd('/sbin/init');
  SysArgExec('/sbin/init');
  { echec : on garde l'ancien init, les sessions sont relancees }
  ReadInittab;
  For K := 1 To NE Do
    If (E[K].Action = aRespawn) And InLevel(K) Then StartRespawn(K);
End;

Procedure HandleSignal;
Var S, K : LongInt; Fd : LongInt; B : Array[0..7] Of Char; L : Char;
Begin
  S := SigFlag;
  SigFlag := 0;
  Case S Of
    SIGUSR1 : Shutdown(LINUX_REBOOT_HALT);
    SIGUSR2 : Shutdown(LINUX_REBOOT_POWER_OFF);
    SIGTERM : Shutdown(LINUX_REBOOT_RESTART);
    SIGINT :
      Begin
        K := 0;
        For I := 1 To NE Do
          If E[I].Action = aCtrlAltDel Then
          Begin
            Spawn(E[I].Cmd);
            K := 1;
          End;
        If K = 0 Then Shutdown(LINUX_REBOOT_RESTART);
      End;
    SIGHUP :
      Begin
        { telinit : /var/run/init.req contient le niveau demande (q : relire) }
        L := RunLevel;
        Fd := SysOpen('/var/run/init.req', 0, 0);
        If Fd >= 0 Then
        Begin
          If SysRead(Fd, B, 1) = 1 Then L := B[0];
          SysClose(Fd);
          SysUnlink('/var/run/init.req');
        End;
        If L = 'R' Then
        Begin
          SwitchToNewRoot;
          Exit;
        End;
        If (L = 'q') Or (L = 'Q') Then L := RunLevel;
        If (L = 's') Or (L = 'S') Then L := '1';
        ChangeLevel(L);
      End;
  End;
End;

Procedure OpenConsole;
Var Fd : LongInt; St : TSysStat;
Begin
  If SysFStat(0, St) < 0 Then
  Begin
    Fd := SysOpen('/dev/console', O_RDWR, 0);
    If Fd >= 0 Then
    Begin
      SysDup2(Fd, 0);
      SysDup2(Fd, 1);
      SysDup2(Fd, 2);
      If Fd > 2 Then SysClose(Fd);
    End;
  End;
End;

BEGIN
  IsInit := SysGetPid = 1;
  OpenConsole;
  ReadLang;
  Say(Msg(1));
  If IsInit Then SysSetSid;
  SysSigAction(SIGINT, LongInt(@OnSignal), 0);
  SysSigAction(SIGTERM, LongInt(@OnSignal), 0);
  SysSigAction(SIGUSR1, LongInt(@OnSignal), 0);
  SysSigAction(SIGUSR2, LongInt(@OnSignal), 0);
  SysSigAction(SIGHUP, LongInt(@OnSignal), 0);
  SysSigAction(SIGQUIT, SIG_IGN, 0);
  SysSigAction(SIGTSTP, SIG_IGN, 0);
  DefLevel := '3';
  RunLevel := '3';
  PrevLevel := 'N';
  ReadInittab;
  RunLevel := DefLevel;
  If IsInit Then
  Begin
    { utmp vide, enregistrement de demarrage dans wtmp }
    SysUnlink('/var/run/utmp');
    UtFill(UB, UtBoot, 0, '~', 'reboot', '');
    UtPutUtmp(UB);
    UtAppend('/var/log/wtmp', UB);
  End;
  WriteRunLevel;
  RunAll(aSysinit, True);
  RunAll(aWait, True);
  RunAll(aOnce, False);
  For I := 1 To NE Do
    If (E[I].Action = aRespawn) And InLevel(I) Then StartRespawn(I);
  While True Do
  Begin
    W := SysWaitPid(-1, St, 0);
    If SigFlag <> 0 Then HandleSignal;
    If W > 0 Then
    Begin
      I := FindPid(W);
      UtLogoff(W);
      If I > 0 Then
      Begin
        E[I].Pid := 0;
        If (E[I].Action = aRespawn) And InLevel(I) Then StartRespawn(I);
      End;
    End
    Else If (W < 0) And (SysErrno = 10) Then
    Begin
      { plus aucun fils : relancer les sessions suspendues puis attendre }
      For I := 1 To NE Do
        If (E[I].Action = aRespawn) And (E[I].Pid = 0) And InLevel(I) Then
          StartRespawn(I);
      SysSleep(1);
      If SigFlag <> 0 Then HandleSignal;
    End;
  End;
END.
