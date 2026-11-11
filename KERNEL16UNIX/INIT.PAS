{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2026
  @website(https://www.gladir.com/linux-0)
  @abstract(Target: KERNEL16UNIX (LPC /X))
  @description: Processus init (pid 1) de LINUX-0, comme celui de UNIX V7 :
   lit /etc/ttys et lance /etc/getty sur chaque terminal actif, relance
   getty quand la session se termine et recupere les processus orphelins
   (zombies). Sans /etc/getty, lance directement /bin/sh sur la console.
   Format de /etc/ttys (V7) : une ligne par terminal, 1er caractere 1
   (actif) ou 0, 2e caractere = vitesse (argument de getty), puis le nom
   du peripherique de /dev, par exemple "10console".
   Langue : init cherche la ligne LANGUAGE=XX de /etc/profile (ecrite par
   l'installateur) et transmet LANGUAGE a getty, login et sh. Messages en
   francais, ou selon LANGUAGE : EN anglais, GR allemand, SP espagnol, IT
   italien.
   Compilation : LPC /X INIT.PAS  -> /etc/init
}

{$DEFINE LANGERR}   { messages d'erreur du systeme en 5 langues }

Program Init;

{$I-}

{$M 4096,0,0}

Const
 MAXTTY=4;
 mStart=1; mNoSession=2;
 { messages : colonnes FR, EN, GR (allemand), SP, IT }
 M:Array[1..2,1..5] Of PChar=(
  ('init : demarrage de LINUX-0','init: starting LINUX-0',
   'init: LINUX-0 wird gestartet','init: arrancando LINUX-0',
   'init: avvio di LINUX-0'),
  ('init : impossible de lancer la session sur ',
   'init: cannot start the session on ',
   'init: Sitzung kann nicht gestartet werden auf ',
   'init: no se puede iniciar la sesion en ',
   'init: impossibile avviare la sessione su '));

Var
 TtyName:Array[1..MAXTTY]of String[15];
 TtySpeed:Array[1..MAXTTY]of Char;
 TtyPid:Array[1..MAXTTY]of Integer;
 TtyFail:Array[1..MAXTTY]of Integer;
 NTty,I,W,St,Lang:Integer;
 Getty:Boolean;
 LangName:String;

Function Msg(Id:Integer):String;
Var P:PChar; X:String;
Begin
 P:=M[Id,Lang]; X:='';
 While P^<>#0 Do Begin X:=X+P^; Inc(P) End;
 Msg:=X;
End;

Procedure ReadLang;
{ langue : LANGUAGE de l'environnement, puis la ligne LANGUAGE=XX de
  /etc/profile (celle de l'installateur) }
Var F:Text; S:String; K:Integer;
Begin
 LangName:=SysGetEnv('LANGUAGE');
 Assign(F,'/etc/profile'); Reset(F);
 If IOResult=0 Then Begin
  While Not EOF(F) Do Begin
   ReadLn(F,S);
   If Copy(S,1,9)='LANGUAGE=' Then Begin
    Delete(S,1,9);
    While (S<>'')And Not(S[1]In['A'..'Z','a'..'z']) Do Delete(S,1,1);
    K:=1;
    While (K<=Length(S))And(S[K]In['A'..'Z','a'..'z']) Do Inc(K);
    LangName:=Copy(S,1,K-1);
   End;
  End;
  Close(F);
 End;
 Lang:=SysLangOf(LangName);
End;

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
   ArgAdd('-'); ArgAdd(TtySpeed[K]);
   If LangName<>'' Then EnvAdd('LANGUAGE='+LangName);
   ArgExec('/etc/getty');
  End Else Begin
   ArgAdd('-sh'); EnvAdd('HOME=/'); EnvAdd('PATH=/bin:/usr/bin');
   If LangName<>'' Then EnvAdd('LANGUAGE='+LangName);
   ArgExec('/bin/sh');
  End;
  SysExit(127);
 End;
 TtyPid[K]:=Pid;
End;

BEGIN
 ReadLang;
 WriteLn(Msg(mStart));
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
    Else WriteLn(Msg(mNoSession),TtyName[I]);
   End;
  If W<0 Then SysSleep(1);
 Until False;
END.
