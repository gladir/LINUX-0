{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2026
  @website(https://www.gladir.com/linux-0)
  @abstract(Target: KERNEL16UNIX (LPC /X))
  @description: getty de LINUX-0 (/etc/getty), lance par init sur chaque
   terminal de /etc/ttys : remet le terminal dans son etat normal (stty
   sane), affiche la banniere, le contenu de /etc/issue s'il existe
   (\n = nom de la machine, \s = systeme, \r = version, \\ = une barre
   oblique inverse) et l'invite "login:", lit le nom de l'utilisateur puis
   execute /bin/login avec ce nom, en lui transmettant l'environnement
   (LANGUAGE, TERM). Messages en francais, ou selon la variable
   d'environnement LANGUAGE (transmise par init) : EN anglais, GR allemand,
   SP espagnol, IT italien.
   Usage : getty [vitesse]   (la vitesse de /etc/ttys est ignoree)
}

{$DEFINE LANGERR}   { messages d'erreur du systeme en 5 langues }

Program Getty;

{$M 4096,0,0}

Const
 mErr=1; mUsage=2; mHelp2=3;
 { messages : colonnes FR, EN, GR (allemand), SP, IT }
 M:Array[1..3,1..5] Of PChar=(
  ('getty : /bin/login : ','getty: /bin/login: ','getty: /bin/login: ',
   'getty: /bin/login: ','getty: /bin/login: '),
  ('Usage : getty [vitesse]','Usage: getty [speed]','Aufruf: getty [Speed]',
   'Uso: getty [velocidad]','Uso: getty [velocita]'),
  ('Lance /bin/login apres avoir affiche /etc/issue et "login:".',
   'Run /bin/login after displaying /etc/issue and "login:".',
   'Startet /bin/login nach Anzeige von /etc/issue und "login:".',
   'Ejecuta /bin/login tras mostrar /etc/issue y "login:".',
   'Esegue /bin/login dopo aver mostrato /etc/issue e "login:".'));

Var
 Sg:TSgttyb; TC:Array[0..5]Of Char;
 Name,LangName,Term,A:String; C:Char; N:Integer; U:TUtsName;

Function Msg(Id:Integer):String;
Var P:PChar; X:String;
Begin
 P:=M[Id,SysLang]; X:='';
 While P^<>#0 Do Begin X:=X+P^; Inc(P) End;
 Msg:=X;
End;

Procedure Put(S:String);
Begin
 If S<>'' Then SysWrite(1,S[1],Length(S));
End;

Procedure Issue;
{ /etc/issue : le texte, avec les sequences \n \s \r \\ }
Var Fd,N,K:Integer; B:Array[0..255]Of Char; Esc:Boolean; S:String;
Begin
 Fd:=SysOpen('/etc/issue',O_RDONLY,0);
 If Fd<0 Then Exit;
 Esc:=False;
 Repeat
  N:=SysRead(Fd,B,SizeOf(B));
  S:='';
  For K:=0 To N-1 Do
   If Esc Then Begin
    Esc:=False;
    Case B[K] Of
     'n': S:=S+U.NodeName;
     's': S:=S+U.SysName;
     'r': S:=S+U.Release;
     '\': S:=S+'\';
     Else S:=S+'\'+B[K];
    End;
   End Else If B[K]='\' Then Esc:=True
   Else S:=S+B[K];
  Put(S);
 Until N<=0;
 SysClose(Fd);
End;

BEGIN
 SysSignal(SIGINT,SIG_IGN); SysSignal(SIGQUIT,SIG_IGN);
 A:=ArgStr(1);
 If (A='/?')Or(A='-h')Or(A='--help') Then Begin
  Put(Msg(mUsage)+#10+Msg(mHelp2)+#10); SysExit(0);
 End;
 If GTty(0,Sg)=0 Then Begin
  Sg.Erase:=#8; Sg.Kill:=#21; Sg.Flags:=ECHO Or CRMOD;
  STty(0,Sg);
  TC[0]:=#3; TC[1]:=#28; TC[2]:=#17; TC[3]:=#19; TC[4]:=#4; TC[5]:=#255;
  SysIoctl(0,TIOCSETC,TC);
 End;
 SysUname(U);
 LangName:=SysGetEnv('LANGUAGE'); Term:=SysGetEnv('TERM');
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
 If LangName<>'' Then EnvAdd('LANGUAGE='+LangName);
 If Term<>'' Then EnvAdd('TERM='+Term);
 ArgExec('/bin/login');
 Put(Msg(mErr)+SysErrorText(Errno)+#10);
 SysExit(1);
END.
