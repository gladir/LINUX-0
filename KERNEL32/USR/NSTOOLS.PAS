{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2026
  @website(https://www.gladir.com/linux-0)
  @abstract(Target: LPC -3X)
  @description: chroot, unshare, nsenter, pivot_root, switch_root, setpriv
      (un seul programme, le nom lu dans argv[0]) : appels chroot, unshare,
      setns, pivot_root, mount(MS_MOVE), setresuid/setresgid, prctl du noyau.
    chroot RACINE [COMMANDE [ARG...]]
    unshare [-munipUCTf] [-r] [--mount-proc[=DIR]] [COMMANDE [ARG...]]
      -m montages -u UTS -i IPC -n reseau -p PID -U utilisateur -C cgroup
      -T temps -f fork avant l'exec -r correspondance root (uid/gid 0)
    nsenter -t PID [-munipUC] [-S uid] [-G gid] [COMMANDE [ARG...]]
    pivot_root NOUVELLE_RACINE ANCIENNE_RACINE
    switch_root [-c console] NOUVELLE_RACINE INIT [ARG...]
    setpriv [--reuid N] [--regid N] [--ruid N] [--rgid N] [--clear-groups]
      [--groups a,b] [--no-new-privs] [--inh-caps ...] COMMANDE [ARG...]
    Messages en cinq langues (LANGUAGE).
}

Program NsTools;

Const
  CLONE_NEWTIME = $80; CLONE_NEWNS = $20000; CLONE_NEWCGROUP = $2000000;
  CLONE_NEWUTS = $4000000; CLONE_NEWIPC = $8000000;
  CLONE_NEWUSER = $10000000; CLONE_NEWPID = $20000000;
  CLONE_NEWNET = $40000000;
  MS_MOVE = 8192; MS_REC = 16384; MS_PRIVATE = 262144;
  U : Array[1..6, 1..5] Of PChar = (
    ('Usage : chroot RACINE [COMMANDE [ARG...]]',
     'Usage: chroot NEWROOT [COMMAND [ARG...]]',
     'Aufruf: chroot WURZEL [BEFEHL [ARG...]]',
     'Uso: chroot RAIZ [ORDEN [ARG...]]',
     'Uso: chroot RADICE [COMANDO [ARG...]]'),
    ('Usage : unshare [-munipUCTfr] [--mount-proc] [COMMANDE [ARG...]]',
     'Usage: unshare [-munipUCTfr] [--mount-proc] [COMMAND [ARG...]]',
     'Aufruf: unshare [-munipUCTfr] [--mount-proc] [BEFEHL [ARG...]]',
     'Uso: unshare [-munipUCTfr] [--mount-proc] [ORDEN [ARG...]]',
     'Uso: unshare [-munipUCTfr] [--mount-proc] [COMANDO [ARG...]]'),
    ('Usage : nsenter -t PID [-munipUC] [COMMANDE [ARG...]]',
     'Usage: nsenter -t PID [-munipUC] [COMMAND [ARG...]]',
     'Aufruf: nsenter -t PID [-munipUC] [BEFEHL [ARG...]]',
     'Uso: nsenter -t PID [-munipUC] [ORDEN [ARG...]]',
     'Uso: nsenter -t PID [-munipUC] [COMANDO [ARG...]]'),
    ('Usage : pivot_root NOUVELLE_RACINE ANCIENNE_RACINE',
     'Usage: pivot_root NEW_ROOT PUT_OLD',
     'Aufruf: pivot_root NEUE_WURZEL ALTE_WURZEL',
     'Uso: pivot_root RAIZ_NUEVA RAIZ_ANTIGUA',
     'Uso: pivot_root NUOVA_RADICE VECCHIA_RADICE'),
    ('Usage : switch_root NOUVELLE_RACINE INIT [ARG...]',
     'Usage: switch_root NEW_ROOT INIT [ARG...]',
     'Aufruf: switch_root NEUE_WURZEL INIT [ARG...]',
     'Uso: switch_root RAIZ_NUEVA INIT [ARG...]',
     'Uso: switch_root NUOVA_RADICE INIT [ARG...]'),
    ('Usage : setpriv [--reuid N] [--regid N] [--clear-groups] COMMANDE...',
     'Usage: setpriv [--reuid N] [--regid N] [--clear-groups] COMMAND...',
     'Aufruf: setpriv [--reuid N] [--regid N] [--clear-groups] BEFEHL...',
     'Uso: setpriv [--reuid N] [--regid N] [--clear-groups] ORDEN...',
     'Uso: setpriv [--reuid N] [--regid N] [--clear-groups] COMANDO...'));

Var
  Prog : String;
  Rc : LongInt;

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

Function ToNum(Const S : String) : LongInt;
Var V, C : LongInt;
Begin
  Val(S, V, C);
  If C <> 0 Then V := -1;
  ToNum := V;
End;

Procedure Usage(K : LongInt);
Begin
  SysPut(2, PS(U[K, SysLang]) + #10);
  SysExit(1);
End;

Procedure Die(Const What : String);
Begin
  SysPut(2, Prog + ': ' + What + ': ' + SysErrorText(SysErrno) + #10);
  SysExit(1);
End;

Function FindExe(Const Name : String) : String;
Var Path, Dir : String; K : LongInt;
Begin
  FindExe := Name;
  If Pos('/', Name) > 0 Then Exit;
  Path := SysGetEnv('PATH');
  If Path = '' Then Path := '/bin:/usr/bin:/sbin:/usr/sbin';
  While Path <> '' Do
  Begin
    K := Pos(':', Path);
    If K = 0 Then
    Begin
      Dir := Path;
      Path := '';
    End
    Else
    Begin
      Dir := Copy(Path, 1, K - 1);
      Path := Copy(Path, K + 1, 255);
    End;
    If SysAccess(Dir + '/' + Name, 1) = 0 Then
    Begin
      FindExe := Dir + '/' + Name;
      Exit;
    End;
  End;
End;

{ execute les arguments From.. d'argv (shell par defaut) }
Procedure RunCmd(From : LongInt);
Var K : LongInt;
Begin
  SysArgReset;
  If From >= SysArgCount Then
  Begin
    SysArgAdd('/bin/sh');
    SysEnvInherit;
    SysArgExec('/bin/sh');
    Die('/bin/sh');
  End;
  For K := From To SysArgCount - 1 Do SysArgAdd(SysArgStr(K));
  SysEnvInherit;
  SysArgExec(FindExe(SysArgStr(From)));
  Die(SysArgStr(From));
End;

{ attend le fils et rend son code }
Procedure ForkAndWait(Run : Boolean);
Var Pid, St : LongInt;
Begin
  Pid := SysFork;
  If Pid < 0 Then Die('fork');
  If Pid = 0 Then Exit;
  SysWaitPid(Pid, St, 0);
  If SysWIfExited(St) Then SysExit(SysWExitStatus(St));
  SysExit(128 + SysWTermSig(St));
End;

Procedure WriteFile(Const Path, Text : String);
Var Fd : LongInt;
Begin
  Fd := SysOpen(Path, O_WRONLY, 0);
  If Fd < 0 Then Exit;
  LnxSys3(4, Fd, LongInt(@Text[1]), Length(Text));
  SysClose(Fd);
End;

Procedure RunChroot;
Var Dir : String;
Begin
  If SysArgCount < 2 Then Usage(1);
  Dir := SysArgStr(1);
  If LnxRes(LnxSys3(61, LnxZ(Dir), 0, 0)) < 0 Then Die(Dir);
  If SysChdir('/') < 0 Then Die('/');
  RunCmd(2);
End;

Procedure RunUnshare;
Var I, K, Fl : LongInt; A, Mp : String; Fk, Root, MountProc : Boolean;
    Uid, Gid : LongInt;
Begin
  Fl := 0;
  Fk := False;
  Root := False;
  MountProc := False;
  Mp := '/proc';
  I := 1;
  While I < SysArgCount Do
  Begin
    A := SysArgStr(I);
    If (Length(A) < 2) Or (A[1] <> '-') Then Break;
    If A = '--' Then
    Begin
      Inc(I);
      Break;
    End;
    If A = '--fork' Then Fk := True
    Else If A = '--map-root-user' Then Root := True
    Else If Copy(A, 1, 12) = '--mount-proc' Then
    Begin
      MountProc := True;
      Fl := Fl Or CLONE_NEWNS;
      If Length(A) > 13 Then Mp := Copy(A, 14, 100);
    End
    Else If A = '--mount' Then Fl := Fl Or CLONE_NEWNS
    Else If A = '--uts' Then Fl := Fl Or CLONE_NEWUTS
    Else If A = '--ipc' Then Fl := Fl Or CLONE_NEWIPC
    Else If A = '--net' Then Fl := Fl Or CLONE_NEWNET
    Else If A = '--pid' Then Fl := Fl Or CLONE_NEWPID
    Else If A = '--user' Then Fl := Fl Or CLONE_NEWUSER
    Else If A = '--cgroup' Then Fl := Fl Or CLONE_NEWCGROUP
    Else If A = '--time' Then Fl := Fl Or CLONE_NEWTIME
    Else If (A[2] <> '-') Then
      For K := 2 To Length(A) Do
        Case A[K] Of
          'm' : Fl := Fl Or CLONE_NEWNS;
          'u' : Fl := Fl Or CLONE_NEWUTS;
          'i' : Fl := Fl Or CLONE_NEWIPC;
          'n' : Fl := Fl Or CLONE_NEWNET;
          'p' : Fl := Fl Or CLONE_NEWPID;
          'U' : Fl := Fl Or CLONE_NEWUSER;
          'C' : Fl := Fl Or CLONE_NEWCGROUP;
          'T' : Fl := Fl Or CLONE_NEWTIME;
          'f' : Fk := True;
          'r' : Root := True;
        Else
          Usage(2);
        End
    Else Usage(2);
    Inc(I);
  End;
  If Root Then Fl := Fl Or CLONE_NEWUSER;
  Uid := SysGetUid;
  Gid := SysGetGid;
  If Fl = 0 Then Usage(2);
  If LnxRes(LnxSys3(310, Fl, 0, 0)) < 0 Then Die('unshare failed');
  If Root Then
  Begin
    WriteFile('/proc/self/setgroups', 'deny');
    WriteFile('/proc/self/uid_map', '0 ' + NumS(Uid) + ' 1' + #10);
    WriteFile('/proc/self/gid_map', '0 ' + NumS(Gid) + ' 1' + #10);
  End;
  If (Fl And CLONE_NEWPID) <> 0 Then Fk := True;
  If Fk Then ForkAndWait(True);
  If MountProc Then
  Begin
    LnxSys6(21, LnxZ('none'), LnxZ('/'), 0, MS_REC Or MS_PRIVATE, 0, 0);
    If LnxRes(LnxSys6(21, LnxZ('proc'), LnxZ(Mp), LnxZ('proc'), 0, 0, 0)) < 0
    Then Die('mount proc');
  End;
  RunCmd(I);
End;

Procedure RunNsenter;
Var I, K, Pid, Fd, Fl : LongInt; A, Nm, Pth : String; Fk : Boolean;
    Names : Array[1..8] Of String; NN : LongInt; Cl : LongInt;
Begin
  Pid := -1;
  NN := 0;
  Fk := False;
  I := 1;
  While I < SysArgCount Do
  Begin
    A := SysArgStr(I);
    If (Length(A) < 2) Or (A[1] <> '-') Then Break;
    If A = '--' Then
    Begin
      Inc(I);
      Break;
    End;
    If ((A = '-t') Or (A = '--target')) And (I + 1 < SysArgCount) Then
    Begin
      Inc(I);
      Pid := ToNum(SysArgStr(I));
    End
    Else If Copy(A, 1, 9) = '--target=' Then Pid := ToNum(Copy(A, 10, 20))
    Else If (A = '-S') Or (A = '-G') Then Inc(I)
    Else If A = '--mount' Then Begin Inc(NN); Names[NN] := 'mnt'; End
    Else If A = '--uts' Then Begin Inc(NN); Names[NN] := 'uts'; End
    Else If A = '--ipc' Then Begin Inc(NN); Names[NN] := 'ipc'; End
    Else If A = '--net' Then Begin Inc(NN); Names[NN] := 'net'; End
    Else If A = '--pid' Then Begin Inc(NN); Names[NN] := 'pid'; End
    Else If A = '--user' Then Begin Inc(NN); Names[NN] := 'user'; End
    Else If A = '--cgroup' Then Begin Inc(NN); Names[NN] := 'cgroup'; End
    Else If A[2] <> '-' Then
      For K := 2 To Length(A) Do
        If NN < 8 Then
          Case A[K] Of
            'm' : Begin Inc(NN); Names[NN] := 'mnt'; End;
            'u' : Begin Inc(NN); Names[NN] := 'uts'; End;
            'i' : Begin Inc(NN); Names[NN] := 'ipc'; End;
            'n' : Begin Inc(NN); Names[NN] := 'net'; End;
            'p' : Begin Inc(NN); Names[NN] := 'pid'; End;
            'U' : Begin Inc(NN); Names[NN] := 'user'; End;
            'C' : Begin Inc(NN); Names[NN] := 'cgroup'; End;
            'a' : ;
          End
    Else Usage(3);
    Inc(I);
  End;
  If Pid < 0 Then Usage(3);
  If NN = 0 Then
  Begin
    { tous les espaces de noms }
    Names[1] := 'user'; Names[2] := 'mnt'; Names[3] := 'uts';
    Names[4] := 'ipc'; Names[5] := 'net'; Names[6] := 'pid';
    NN := 6;
  End;
  { l'espace utilisateur d'abord, le montage en dernier }
  For Cl := 1 To NN Do
  Begin
    Nm := Names[Cl];
    If Nm = 'mnt' Then Continue;
    Pth := '/proc/' + NumS(Pid) + '/ns/' + Nm;
    Fd := SysOpen(Pth, O_RDONLY, 0);
    If Fd < 0 Then Die(Pth);
    If Nm = 'pid' Then Fk := True;
    If LnxRes(LnxSys3(346, Fd, 0, 0)) < 0 Then Die('setns ' + Nm);
    SysClose(Fd);
  End;
  For Cl := 1 To NN Do
    If Names[Cl] = 'mnt' Then
    Begin
      Pth := '/proc/' + NumS(Pid) + '/ns/mnt';
      Fd := SysOpen(Pth, O_RDONLY, 0);
      If Fd < 0 Then Die(Pth);
      If LnxRes(LnxSys3(346, Fd, 0, 0)) < 0 Then Die('setns mnt');
      SysClose(Fd);
    End;
  Fl := 0;
  If Fk Then ForkAndWait(True);
  RunCmd(I);
End;

Procedure RunPivot;
Begin
  If SysArgCount <> 3 Then Usage(4);
  If LnxRes(LnxSys3(217, LnxZ(SysArgStr(1)), LnxZ(SysArgStr(2)), 0)) < 0 Then
    Die('pivot_root');
End;

Procedure RunSwitchRoot;
Var I, K : LongInt; Nw, Cons : String; Dirs : Array[1..4] Of String;
Begin
  I := 1;
  Cons := '';
  If (SysArgCount > 3) And (SysArgStr(1) = '-c') Then
  Begin
    Cons := SysArgStr(2);
    I := 3;
  End;
  If SysArgCount < I + 2 Then Usage(5);
  Nw := SysArgStr(I);
  Dirs[1] := '/dev'; Dirs[2] := '/proc'; Dirs[3] := '/sys'; Dirs[4] := '/run';
  For K := 1 To 4 Do
  Begin
    SysMkdir(Nw + Dirs[K], 493);
    { MS_MOVE : echec tolere (point non monte) }
    LnxSys6(21, LnxZ(Dirs[K]), LnxZ(Nw + Dirs[K]), 0, MS_MOVE, 0, 0);
  End;
  If SysChdir(Nw) < 0 Then Die(Nw);
  If LnxRes(LnxSys6(21, LnxZ('.'), LnxZ('/'), 0, MS_MOVE, 0, 0)) < 0 Then
    Die('mount --move');
  If LnxRes(LnxSys3(61, LnxZ('.'), 0, 0)) < 0 Then Die('chroot');
  SysChdir('/');
  If Cons <> '' Then
  Begin
    K := SysOpen(Cons, O_RDWR, 0);
    If K >= 0 Then
    Begin
      SysDup2(K, 0);
      SysDup2(K, 1);
      SysDup2(K, 2);
      If K > 2 Then SysClose(K);
    End;
  End;
  RunCmd(I + 1);
End;

Procedure RunSetpriv;
Var I, Ru, Rg, K, N : LongInt; A, L : String; NoPriv, ClrGrp : Boolean;
    Gr : Array[0..31] Of LongInt; NG : LongInt; HaveG : Boolean;
Begin
  Ru := -1;
  Rg := -1;
  NoPriv := False;
  ClrGrp := False;
  HaveG := False;
  NG := 0;
  I := 1;
  While I < SysArgCount Do
  Begin
    A := SysArgStr(I);
    If (Length(A) < 2) Or (A[1] <> '-') Then Break;
    If A = '--' Then
    Begin
      Inc(I);
      Break;
    End;
    If ((A = '--reuid') Or (A = '--ruid')) And (I + 1 < SysArgCount) Then
    Begin
      Inc(I);
      Ru := ToNum(SysArgStr(I));
    End
    Else If ((A = '--regid') Or (A = '--rgid')) And (I + 1 < SysArgCount) Then
    Begin
      Inc(I);
      Rg := ToNum(SysArgStr(I));
    End
    Else If A = '--clear-groups' Then ClrGrp := True
    Else If (A = '--groups') And (I + 1 < SysArgCount) Then
    Begin
      Inc(I);
      L := SysArgStr(I) + ',';
      While L <> '' Do
      Begin
        K := Pos(',', L);
        N := ToNum(Copy(L, 1, K - 1));
        If (N >= 0) And (NG < 32) Then
        Begin
          Gr[NG] := N;
          Inc(NG);
        End;
        L := Copy(L, K + 1, 255);
      End;
      HaveG := True;
    End
    Else If A = '--no-new-privs' Then NoPriv := True
    Else If (A = '--inh-caps') Or (A = '--bounding-set') Or
            (A = '--ambient-caps') Or (A = '--securebits') Then Inc(I)
    Else Usage(6);
    Inc(I);
  End;
  If I >= SysArgCount Then Usage(6);
  If ClrGrp Then
  Begin
    If LnxRes(LnxSys3(206, 0, 0, 0)) < 0 Then Die('setgroups');
  End
  Else If HaveG Then
    If LnxRes(LnxSys3(206, NG, LongInt(@Gr), 0)) < 0 Then Die('setgroups');
  If Rg >= 0 Then
    If LnxRes(LnxSys3(210, Rg, Rg, Rg)) < 0 Then Die('setresgid');
  If Ru >= 0 Then
    If LnxRes(LnxSys3(208, Ru, Ru, Ru)) < 0 Then Die('setresuid');
  If NoPriv Then LnxSys6(172, 38, 1, 0, 0, 0, 0);
  RunCmd(I);
End;

BEGIN
  Prog := SysArgStr(0);
  While Pos('/', Prog) > 0 Do Prog := Copy(Prog, Pos('/', Prog) + 1, 255);
  Rc := 0;
  If Prog = 'chroot' Then RunChroot
  Else If Prog = 'unshare' Then RunUnshare
  Else If Prog = 'nsenter' Then RunNsenter
  Else If Prog = 'pivot_root' Then RunPivot
  Else If Prog = 'switch_root' Then RunSwitchRoot
  Else If Prog = 'setpriv' Then RunSetpriv
  Else
  Begin
    SysPut(1, PS(U[1, SysLang]) + #10);
    SysPut(1, PS(U[2, SysLang]) + #10);
    SysPut(1, PS(U[3, SysLang]) + #10);
  End;
  SysExit(Rc);
END.
