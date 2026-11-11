{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2026
  @website(https://www.gladir.com/linux-0)
  @abstract(Target: Linux Pascal (LPC /X))
  @description: Processus init (pid 1) de LINUX-0, comme celui de UNIX V7 :
   lit /etc/ttys et lance /etc/getty sur chaque terminal actif, relance
   getty quand la session se termine et recupere les processus orphelins
   (zombies). Sans /etc/getty, lance directement /bin/sh sur la console.
   Format de /etc/ttys (V7) : une ligne par terminal, 1er caractere 1
   (actif) ou 0, 2e caractere = vitesse (argument de getty), puis le nom
   du peripherique de /dev, par exemple "10console".
   Compilation : LPC /X INIT.PAS  -> /etc/init
}

Program Init;

{$I-}

{$M 4096,0,0}

Const
 MAXTTY=4;

Var
 TtyName:Array[1..MAXTTY]of String[15];
 TtySpeed:Array[1..MAXTTY]of Char;
 TtyPid:Array[1..MAXTTY]of Integer;
 TtyFail:Array[1..MAXTTY]of Integer;
 NTty,I,W,St:Integer;
 Getty:Boolean;

Function Exists(S:String):Boolean;
Var St:TStat;
Begin
 Exists:=SysStat(S,St)=0;
End;

Procedure ReadTtys;
Var F:Text; S:String;
Begin
 NTty:=0;
 Assign(F,'/etc/ttys'); Reset(F);
 If IOResult=0 Then Begin
  While Not EOF(F)And(NTty<MAXTTY)Do Begin
   ReadLn(F,S);
   If(Length(S)>2)And(S[1]='1')Then Begin
    Inc(NTty); TtySpeed[NTty]:=S[2]; TtyName[NTty]:=Copy(S,3,15);
   End;
  End;
  Close(F);
 End;
 If NTty=0 Then Begin
  NTty:=1; TtySpeed[1]:='0'; TtyName[1]:='console';
 End;
 For I:=1 To NTty Do Begin TtyPid[I]:=0; TtyFail[I]:=0 End;
End;

Procedure Spawn(K:Integer);
{ processus de session du terminal K : getty (ou sh), entree et sorties
  standard sur /dev/<nom> }
Var Pid,Fd:Integer;
Begin
 Pid:=VFork;
 If Pid=0 Then Begin
  Fd:=SysOpen('/dev/'+TtyName[K],O_RDWR,0);
  If Fd>=0 Then Begin
   SysDup2(Fd,0); SysDup2(Fd,1); SysDup2(Fd,2);
   If Fd>2 Then SysClose(Fd);
  End;
  ArgReset;
  If Getty Then Begin
   ArgAdd('-'); ArgAdd(TtySpeed[K]); ArgExec('/etc/getty');
  End Else Begin
   ArgAdd('-sh'); EnvAdd('HOME=/'); EnvAdd('PATH=/bin:/usr/bin');
   ArgExec('/bin/sh');
  End;
  SysExit(127);
 End;
 TtyPid[K]:=Pid;
End;

BEGIN
 WriteLn('init : demarrage de LINUX-0');
 SysSignal(SIGINT,SIG_IGN); SysSignal(SIGQUIT,SIG_IGN);
 Getty:=Exists('/etc/getty');
 ReadTtys;
 For I:=1 To NTty Do Spawn(I);
 Repeat
  W:=WaitPid(-1,St,0);
  If W>0 Then
   For I:=1 To NTty Do If TtyPid[I]=W Then Begin
    { une session se termine : nouveau getty (abandon apres 5 echecs
      d'execution de suite) }
    If WIfExited(St)And(WExitStatus(St)=127)Then Inc(TtyFail[I])
    Else TtyFail[I]:=0;
    If TtyFail[I]<5 Then Spawn(I)
    Else WriteLn('init : impossible de lancer la session sur ',TtyName[I]);
   End;
  If W<0 Then SysSleep(1);
 Until False;
END.
