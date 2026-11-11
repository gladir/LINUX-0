{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2026
  @website(https://www.gladir.com/linux-0)
  @abstract(Target: Linux Pascal (LPC /X))
  @description: Test des processus de LINUX-0 : fork (copie de la memoire),
   ordonnanceur preemptif (3 fils en calcul), tubes, kill, etat de wait
   (UNIX V7), gestionnaires de signaux, alarm, exec avec argc/argv sur la
   pile, read() d'un repertoire (entrees V7), stat, sgttyb, permissions.
   Lance comme /etc/init par TESTS/RUNTESTS.SH; affiche TERMINE a la fin.
}

Program TPROC;

Var
 P:Array[1..3] of Integer; I,J,St,W,R,Wf,Pid,Fd:Integer; X:Longint; V:Integer;
 Buf:Array[0..63] of Char; S:String; Caught,Alarms:Integer;
 Sg:TSgttyb; Tm:TTms; Ent:Array[0..15]of Byte; Stb:TStat; Old:Pointer;

Procedure OnSig(Sig:Integer);Far;
Begin
 Inc(Caught); WriteLn('  gestionnaire : signal ',Sig);
End;

Procedure OnAlarm(Sig:Integer);Far;
Begin
 Inc(Alarms);
End;

Procedure Ok(Cond:Boolean;What:String);
Begin
 If Cond Then WriteLn('ok ',What) Else WriteLn('ECHEC ',What);
End;

Begin
 { appele par exec plus bas : affiche ses arguments (pile UNIX) }
 If (ArgCount>1)And(ArgStr(1)='args')Then Begin
  Write('argc=',ArgCount);
  For I:=0 To ArgCount-1 Do Write(' [',ArgStr(I),']');
  WriteLn(' env=',EnvCount,' ',EnvStr(0));
  SysExit(ArgCount);
 End;
 WriteLn('== fork : copie de la memoire');
 V:=10;
 Pid:=Fork;
 If Pid=0 Then Begin
  V:=99; WriteLn('fils pid=',GetPid,' ppid=',GetPPid,' V=',V); SysExit(7);
 End;
 W:=WaitPid(Pid,St,0); WriteLn('pere V=',V,' fils ',W,' etat ',St);
 Ok(WIfExited(St)And(WExitStatus(St)=7)And(St=$700),'etat de wait = 7*256');
 WriteLn('== ordonnanceur : 3 fils en calcul');
 For I:=1 To 3 Do Begin
  P[I]:=Fork;
  If P[I]=0 Then Begin
   For J:=1 To 4 Do Begin
    X:=0; While X<8000000 Do Inc(X);
    WriteLn('  fils ',I,' tour ',J);
   End;
   SysExit(I);
  End;
 End;
 For I:=1 To 3 Do Begin
  W:=WaitPid(-1,St,0); WriteLn('termine ',W,' code ',WExitStatus(St));
 End;
 WriteLn('== tube');
 SysPipe(R,Wf);
 Pid:=Fork;
 If Pid=0 Then Begin
  SysClose(R); S:='message par le tube'; SysWrite(Wf,S[1],Length(S));
  SysClose(Wf); SysExit(0);
 End;
 SysClose(Wf);
 J:=SysRead(R,Buf,63); Buf[J]:=#0; Write('lu ',J,' : ');
 For I:=0 To J-1 Do Write(Buf[I]);
 WriteLn;
 J:=SysRead(R,Buf,63); WriteLn('fin de tube : ',J);
 SysClose(R); WaitPid(Pid,St,0);
 WriteLn('== kill');
 Pid:=Fork;
 If Pid=0 Then Begin Repeat X:=X+1 Until False End;
 SysSleep(1);
 WriteLn('kill -> ',SysKill(Pid,SIGTERM));
 W:=WaitPid(Pid,St,0); WriteLn('tue ',W,' etat ',St);
 Ok(WTermSig(St)=SIGTERM,'etat de wait = numero du signal');
 WriteLn('== signaux : gestionnaire, SIG_IGN, alarm');
 Caught:=0;
 SysSignal(SIGTERM,@OnSig);
 SysKill(GetPid,SIGTERM);
 Ok(Caught=1,'gestionnaire appele');
 Old:=SysSignal(SIGTERM,SIG_DFL);
 Ok(Old=Nil,'action remise a SIG_DFL apres le signal (V7)');
 SysSignal(SIGINT,SIG_IGN);
 SysKill(GetPid,SIGINT);
 Ok(True,'SIGINT ignore');
 SysSignal(SIGINT,SIG_DFL);
 Alarms:=0;
 SysSignal(SIGALRM,@OnAlarm);
 SysAlarm(1);
 W:=SysPause;
 Ok((Alarms=1)And(W<0)And(Errno=EINTR),'alarm + pause (EINTR)');
 Pid:=Fork;
 If Pid=0 Then Begin SysSignal(SIGQUIT,@OnSig); SysPause; SysExit(3) End;
 SysSleep(1); SysKill(Pid,SIGQUIT);
 WaitPid(Pid,St,0); Ok(WExitStatus(St)=3,'fils : gestionnaire puis exit(3)');
 WriteLn('== exec : argc, argv et envp sur la pile');
 Pid:=VFork;
 If Pid=0 Then Begin
  ArgReset; ArgAdd('tproc'); ArgAdd('args'); ArgAdd('deux mots'); ArgAdd('');
  EnvAdd('VAR=valeur');
  ArgExec('/etc/init'); SysExit(127);
 End;
 WaitPid(Pid,St,0); Ok(WExitStatus(St)=4,'argc = 4 (argument vide compris)');
 Pid:=Fork;
 If Pid=0 Then Begin Execv('/bin/echo','bonjour depuis echo'); SysExit(127) End;
 WaitPid(Pid,St,0); WriteLn('echo etat ',St);
 Pid:=VFork;
 If Pid=0 Then Begin Execv('/inexistant',''); SysExit(127) End;
 WaitPid(Pid,St,0); Ok(WExitStatus(St)=127,'exec impossible -> 127');
 WriteLn('== read() d''un repertoire, stat, terminal');
 Fd:=SysOpen('/etc',O_RDONLY,0); J:=0; S:='';
 While SysRead(Fd,Ent,16)=16 Do Begin
  Inc(J);
  If (Ent[2]=Ord('i'))And(Ent[3]=Ord('n'))And(Ent[4]=Ord('i'))And
    (Ent[5]=Ord('t'))And(Ent[6]=0) Then S:='init';
 End;
 SysClose(Fd);
 Ok((J>=2)And(S='init'),'entrees V7 de 16 octets ('+Chr(48+J Mod 10)+')');
 Ok((SysStat('/etc/init',Stb)=0)And(Stb.Size>1000)And
   (Stb.Mode And S_IFMT=S_IFREG),'stat V7');
 Ok((GTty(0,Sg)=0)And(Sg.Flags=ECHO+CRMOD)And(Sg.Erase=#8),'gtty : ECHO|CRMOD');
 Ok(Not IsATty(SysOpen('/etc/init',O_RDONLY,0)),
   'fichier : pas un terminal (ENOTTY)');
 SysTimes(Tm); Ok(Tm.CUTime>0,'times : temps des fils');
 WriteLn('== utilisateurs et permissions');
 Ok((GetUid=0)And(GetGid=0),'root');
 SysUmask($12);   { 022 en octal }
 Fd:=SysCreat('/usr/tmp/perm',$1B6); SysClose(Fd);
 Ok((SysStat('/usr/tmp/perm',Stb)=0)And(Stb.Mode And $1FF=$1A4),
   'umask 022 : 0644');
 Pid:=Fork;
 If Pid=0 Then Begin
  SetGid(100); SetUid(100);
  W:=0;
  If (SysOpen('/usr/tmp/perm',O_WRONLY,0)<0)And(Errno=EACCES) Then Inc(W);
  If SysOpen('/usr/tmp/perm',O_RDONLY,0)>=0 Then Inc(W);
  If (SetUid(0)<0)And(Errno=EPERM) Then Inc(W);
  If (SysKill(1,SIGTERM)<0)And(Errno=EPERM) Then Inc(W);
  If (SysChmod('/usr/tmp/perm',$1FF)<0)And(Errno=EPERM) Then Inc(W);
  If SysAccess('/usr/tmp/perm',R_OK)=0 Then Inc(W);
  If GetUid=100 Then Inc(W);
  SysExit(W);
 End;
 WaitPid(Pid,St,0); Str(WExitStatus(St),S);
 Ok(WExitStatus(St)=7,'uid 100 : 7 controles de permissions ('+S+')');
 SysChown('/usr/tmp/perm',100,100);
 Ok((SysStat('/usr/tmp/perm',Stb)=0)And(Stb.Uid=100),'chown');
 SysUnlink('/usr/tmp/perm');
 WriteLn('TERMINE');
 Repeat SysSleep(100) Until False;
End.
