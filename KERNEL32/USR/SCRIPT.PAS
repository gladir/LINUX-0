{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2026
  @website(https://www.gladir.com/linux-0)
  @abstract(Target: LPC -3X)
  @description: script : lance une commande (par defaut $SHELL ou /bin/sh) sur
   un pseudo-terminal (/dev/ptmx, /dev/pts/N) et recopie les echanges entre
   le terminal courant et le pty ; la sortie est aussi ecrite dans un
   fichier (typescript par defaut).
   script [-q] [-a] [-c commande] [-e] [fichier]
   -q : pas de messages Script started/done ; -a : ajoute au fichier ;
   -c : commande a lancer par /bin/sh -c ; -e : rend le code de retour de
   la commande. Le terminal courant est mis en mode brut (les touches ^C ^Z
   ^D sont interpretees par le pty, donc par le shell de l'autre cote). }

Program Script;

Var
  Master, Child, LogFd, OldOk : LongInt;
  Old : TSysTermios;
  Quiet_, Append_, Retcode_ : Boolean;
  FileName, CmdText : String;
  Status : LongInt;

Function NumS(V : LongInt) : String;
Var S : String;
Begin
  Str(V, S);
  NumS := S;
End;

Procedure Restore;
Begin
  If OldOk = 0 Then SysTcSetAttr(0, 1, Old);
End;

Procedure Die(Const S : String);
Begin
  Restore;
  SysPut(2, 'script: ' + S + #10);
  SysExit(1);
End;

Procedure Raw;
Var T : TSysTermios;
Begin
  T := Old;
  T.IFlag := T.IFlag And Not ($2 Or $100 Or $40 Or $80 Or $400 Or $200 Or
                              $1);
  T.OFlag := T.OFlag And Not 1;
  T.LFlag := T.LFlag And Not ($8 Or $40 Or $2 Or $1);
  T.CC[6] := 1;
  T.CC[5] := 0;
  SysTcSetAttr(0, 1, T);
End;

Var
  I, K, N, Idx, Unl, Ev, R, Pid, W : LongInt;
  A, Slave : String;
  Buf : Array[0..4095] Of Byte;
  Pf : Array[0..3] Of LongInt;
  Ws : TSysWinSize;
  Done : Boolean;
  EofSent : Boolean;
  Waited : LongInt;
Begin
  Waited := 0;
  Quiet_ := False;
  Append_ := False;
  Retcode_ := False;
  FileName := 'typescript';
  CmdText := '';
  I := 1;
  While I < SysArgCount Do
  Begin
    A := SysArgStr(I);
    If A = '-q' Then Quiet_ := True
    Else If A = '-a' Then Append_ := True
    Else If A = '-e' Then Retcode_ := True
    Else If A = '-c' Then
    Begin
      Inc(I);
      If I < SysArgCount Then CmdText := SysArgStr(I);
    End
    Else If (A = '-f') Or (A = '-t') Then
    Begin
    End
    Else If (A <> '') And (A[1] = '-') And (Length(A) > 1) Then
    Begin
      SysPut(2, 'Usage: script [-q] [-a] [-e] [-c command] [file]' + #10);
      SysExit(1);
    End
    Else FileName := A;
    Inc(I);
  End;
  OldOk := SysTcGetAttr(0, Old);
  Master := SysOpen('/dev/ptmx', 2, 0);
  If Master < 0 Then Die('cannot open /dev/ptmx: ' + SysErrorText(SysErrno));
  Unl := 0;
  SysIoctl(Master, $40045431, Unl);
  If SysIoctl(Master, $80045430, Idx) < 0 Then Die('TIOCGPTN failed');
  Slave := '/dev/pts/' + NumS(Idx);
  If SysGetWinSize(0, Ws) = 0 Then SysIoctl(Master, $5414, Ws);
  If Append_ Then LogFd := SysOpen(FileName, $441, 420)
  Else LogFd := SysOpen(FileName, $241, 420);
  If LogFd < 0 Then Die(FileName + ': ' + SysErrorText(SysErrno));
  If Not Quiet_ Then
    SysPut(1, 'Script started, output file is ' + FileName + #10);
  Child := SysFork;
  If Child = 0 Then
  Begin
    SysClose(Master);
    SysClose(LogFd);
    SysSetSid;
    K := SysOpen(Slave, 2, 0);
    If K < 0 Then
    Begin
      SysPut(2, 'script: ' + Slave + ': ' + SysErrorText(SysErrno) + #10);
      SysExit(1);
    End;
    SysIoctlL(K, $540E, 0);
    SysDup2(K, 0);
    SysDup2(K, 1);
    SysDup2(K, 2);
    If K > 2 Then SysClose(K);
    SysArgReset;
    If CmdText <> '' Then
    Begin
      SysArgAdd('/bin/sh');
      SysArgAdd('-c');
      SysArgAdd(CmdText);
      SysEnvInherit;
      SysArgExec('/bin/sh');
    End
    Else
    Begin
      A := SysGetEnv('SHELL');
      If A = '' Then A := '/bin/sh';
      SysArgAdd(A);
      SysEnvInherit;
      SysArgExec(A);
    End;
    SysExit(127);
  End;
  If OldOk = 0 Then Raw;
  Done := False;
  EofSent := False;
  While Not Done Do
  Begin
    { struct pollfd : fd (4), events (2), revents (2) }
    Pf[0] := 0;
    Pf[1] := 1;
    Pf[2] := Master;
    Pf[3] := 1;
    If EofSent Then Pf[0] := -1;
    R := SysPoll(LongInt(@Pf), 2, 500);
    If EofSent Then
    Begin
      Inc(Waited);
      If Waited = 6 Then SysKill(Child, 1);
      If Waited = 12 Then SysKill(Child, 9);
    End;
    If R < 0 Then
    Begin
      If SysErrno = 4 Then Continue;
      Break;
    End;
    { revents : mot de poids fort de Pf[1] et Pf[3] }
    Ev := (Pf[3] Shr 16) And $FFFF;
    If (Ev And $19) <> 0 Then
    Begin
      N := SysRead(Master, Buf[0], 4096);
      If N <= 0 Then
      Begin
        Done := True;
        Break;
      End;
      SysWrite(1, Buf[0], N);
      SysWrite(LogFd, Buf[0], N);
    End;
    Ev := (Pf[1] Shr 16) And $FFFF;
    If (Not EofSent) And ((Ev And $19) <> 0) Then
    Begin
      N := SysRead(0, Buf[0], 4096);
      If N <= 0 Then
      Begin
        EofSent := True;
        Buf[0] := 4;
        SysWrite(Master, Buf[0], 1);
      End
      Else SysWrite(Master, Buf[0], N);
    End;
    { le fils est-il termine ? }
    W := SysWaitPid(Child, Status, 1);
    If W = Child Then
    Begin
      { vider ce qui reste }
      While True Do
      Begin
        Pf[0] := Master;
        Pf[1] := 1;
        If SysPoll(LongInt(@Pf), 1, 50) <= 0 Then Break;
        N := SysRead(Master, Buf[0], 4096);
        If N <= 0 Then Break;
        SysWrite(1, Buf[0], N);
        SysWrite(LogFd, Buf[0], N);
      End;
      Done := True;
      Child := -1;
    End;
  End;
  If Child > 0 Then SysWaitPid(Child, Status, 0);
  Restore;
  SysClose(LogFd);
  If Not Quiet_ Then SysPut(1, 'Script done, output file is ' + FileName + #10);
  If Retcode_ Then
  Begin
    If SysWIfExited(Status) Then SysExit(SysWExitStatus(Status));
    SysExit(128 + SysWTermSig(Status));
  End;
  SysExit(0);
End.
