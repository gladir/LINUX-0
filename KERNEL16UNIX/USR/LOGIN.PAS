{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2026
  @website(https://www.gladir.com/linux-0)
  @abstract(Target: Linux Pascal (LPC /X))
  @description: login de LINUX-0 (/bin/login) : verifie le nom et le mot de
   passe dans /etc/passwd (nom:mot de passe:uid:gid:commentaire:repertoire:
   interpreteur), puis ouvre la session : repertoire de connexion, groupe et
   utilisateur (setgid, setuid), /etc/motd, environnement (HOME, SHELL,
   USER, LOGNAME, PATH) et interpreteur de connexion ("-sh"). Un champ de
   mot de passe vide n'en demande pas. Hachage : voir CRYPT.INC.
   Usage : login [nom]
}

Program Login;

{$I-}

{$M 4096,0,0}

{$I CRYPT.INC}

Var
 Name,Pw,Entry,Home,Sh,S,Base:String; Uid,Gid,E,Tries,K:Integer;
 F:Text; Found:Boolean;

Function ReadLine(Prompt:String):String;
Var S:String; C:Char; N:Integer;
Begin
 If Prompt<>'' Then SysWrite(1,Prompt[1],Length(Prompt));
 S:='';
 Repeat
  N:=SysRead(0,C,1);
  If N<=0 Then SysExit(1);
  If C=#10 Then Break;
  If (C>' ')And(Length(S)<31) Then S:=S+C;
 Until False;
 ReadLine:=S;
End;

Function Lookup(N:String;Var L:String):Boolean;
Var F:Text; S:String;
Begin
 Lookup:=False;
 Assign(F,'/etc/passwd'); Reset(F);
 If IOResult<>0 Then Exit;
 While Not EOF(F) Do Begin
  ReadLn(F,S);
  If PwField(S,1)=N Then Begin L:=S; Lookup:=True; Break End;
 End;
 Close(F);
End;

Procedure Motd;
Var F:Text; S:String;
Begin
 Assign(F,'/etc/motd'); Reset(F);
 If IOResult<>0 Then Exit;
 While Not EOF(F) Do Begin ReadLn(F,S); WriteLn(S) End;
 Close(F);
End;

BEGIN
 SysSignal(SIGINT,SIG_IGN); SysSignal(SIGQUIT,SIG_IGN);
 If ArgCount>1 Then Name:=ArgStr(1) Else Name:='';
 Tries:=0;
 Repeat
  While Name='' Do Name:=ReadLine('login: ');
  Found:=Lookup(Name,Entry);
  If Found And(PwField(Entry,2)='') Then Pw:=''
  Else Begin
   S:=ReadPass('Mot de passe : ');
   If Found Then Begin
    Pw:=PwField(Entry,2);
    If Crypt(S,Copy(Pw,1,2))<>Pw Then Found:=False;
   End;
  End;
  If Not Found Then Begin
   WriteLn('Connexion refusee');
   Inc(Tries);
   If Tries>=5 Then SysExit(1);
   Name:='';
  End;
 Until Found;
 Val(PwField(Entry,3),Uid,E); If E<>0 Then Uid:=0;
 Val(PwField(Entry,4),Gid,E); If E<>0 Then Gid:=0;
 Home:=PwField(Entry,6); If Home='' Then Home:='/';
 Sh:=PwField(Entry,7); If Sh='' Then Sh:='/bin/sh';
 If SysChdir(Home)<0 Then Begin
  WriteLn('Pas de repertoire ',Home,' : connexion dans /'); Home:='/'; SysChdir('/');
 End;
 If (SetGid(Gid)<0)Or(SetUid(Uid)<0) Then Begin
  WriteLn('login : setuid impossible : ',SysErrorText(Errno)); SysExit(1);
 End;
 Motd;
 K:=Length(Sh);
 While (K>0)And(Sh[K]<>'/') Do Dec(K);
 Base:=Copy(Sh,K+1,255);
 SysSignal(SIGINT,SIG_DFL); SysSignal(SIGQUIT,SIG_DFL);
 ArgReset; ArgAdd('-'+Base);
 EnvAdd('HOME='+Home); EnvAdd('SHELL='+Sh); EnvAdd('USER='+Name);
 EnvAdd('LOGNAME='+Name); EnvAdd('PATH=/bin:/usr/bin');
 ArgExec(Sh);
 WriteLn('login : ',Sh,' : ',SysErrorText(Errno));
 SysExit(1);
END.
