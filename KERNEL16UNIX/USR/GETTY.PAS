{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2026
  @website(https://www.gladir.com/linux-0)
  @abstract(Target: Linux Pascal (LPC /X))
  @description: getty de LINUX-0 (/etc/getty), lance par init sur chaque
   terminal de /etc/ttys : remet le terminal dans son etat normal (stty
   sane), affiche la banniere, le contenu de /etc/issue s'il existe et
   l'invite "login:", lit le nom de l'utilisateur puis execute /bin/login
   avec ce nom.
   Usage : getty [vitesse]   (la vitesse de /etc/ttys est ignoree)
}

Program Getty;

{$M 4096,0,0}

Var
 Sg:TSgttyb; TC:Array[0..5]Of Char;
 Name:String; C:Char; N:Integer; U:TUtsName;

Procedure Put(S:String);
Begin
 If S<>'' Then SysWrite(1,S[1],Length(S));
End;

Procedure Issue;
{ /etc/issue, tel quel }
Var Fd,N:Integer; B:Array[0..255]Of Char;
Begin
 Fd:=SysOpen('/etc/issue',O_RDONLY,0);
 If Fd<0 Then Exit;
 Repeat
  N:=SysRead(Fd,B,SizeOf(B));
  If N>0 Then SysWrite(1,B,N);
 Until N<=0;
 SysClose(Fd);
End;

BEGIN
 SysSignal(SIGINT,SIG_IGN); SysSignal(SIGQUIT,SIG_IGN);
 If GTty(0,Sg)=0 Then Begin
  Sg.Erase:=#8; Sg.Kill:=#21; Sg.Flags:=ECHO Or CRMOD;
  STty(0,Sg);
  TC[0]:=#3; TC[1]:=#28; TC[2]:=#17; TC[3]:=#19; TC[4]:=#4; TC[5]:=#255;
  SysIoctl(0,TIOCSETC,TC);
 End;
 SysUname(U);
 Repeat
  Put(#10+U.SysName+' '+U.Release+' ('+U.NodeName+')'+#10#10);
  Issue;
  Put('login: ');
  Name:='';
  Repeat
   N:=SysRead(0,C,1);
   If N<=0 Then SysExit(0);
   If C=#10 Then Break;
   If (C>' ')And(Length(Name)<31) Then Name:=Name+C;
  Until False;
 Until Name<>'';
 SysSignal(SIGINT,SIG_DFL); SysSignal(SIGQUIT,SIG_DFL);
 ArgReset; ArgAdd('login'); ArgAdd(Name);
 ArgExec('/bin/login');
 Put('getty : /bin/login : '+SysErrorText(Errno)+#10);
 SysExit(1);
END.
