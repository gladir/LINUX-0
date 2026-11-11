{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2026
  @website(https://www.gladir.com/linux-0)
  @abstract(Target: KERNEL16UNIX (LPC /X))
  @description: login de LINUX-0 (/bin/login) : verifie le nom et le mot de
   passe dans /etc/passwd (nom:mot de passe:uid:gid:commentaire:repertoire:
   interpreteur), puis ouvre la session : repertoire de connexion, groupe et
   utilisateur (setgid, setuid), /etc/motd, environnement (HOME, SHELL,
   USER, LOGNAME, PATH, plus LANGUAGE et TERM s'ils existent) et
   interpreteur de connexion ("-sh"). Un champ de mot de passe vide n'en
   demande pas. Messages en francais, ou selon la variable d'environnement
   LANGUAGE (transmise par init et getty) : EN anglais, GR allemand, SP
   espagnol, IT italien.

   Hachage des mots de passe de LINUX-0 (login, passwd, MKPASSWD), au
   format de /etc/passwd de UNIX V7 : 13 caracteres, les 2 premiers etant
   le sel, les 11 suivants le resultat code avec l'alphabet ./0-9A-Za-z.
   Ce n'est pas le DES de crypt(3) : quatre mots de 16 bits A, B, C, D
   (6A09h, BB67h, 3C6Eh, A54Fh) melangent 32 fois les octets x du sel puis
   du mot de passe :
     A := ((A xor x) * 31421 + 1) mod 65536
     B := ((B xor A) * 31421 + x) mod 65536
     C := ((C xor B) * 31421 + 7) mod 65536
     D := ((D xor C) * 31421 + A) mod 65536
   puis les 64 bits A:B:C:D sont codes par groupes de 6 bits (poids forts
   d'abord). Ce code est repris tel quel dans PASSWD.PAS et dans
   TOOLS/MKPASSWD.PAS (programme de l'hote).
   Usage : login [nom]
}

{$DEFINE LANGERR}   { messages d'erreur du systeme en 5 langues }

Program Login;

{$I-}

{$M 4096,0,0}

Const
 CryptChars:String[64]=
  './0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz';
 mPassword=1; mDenied=2; mNoHome=3; mNoSetuid=4; mUsage=5; mHelp2=6;
 { messages : colonnes FR, EN, GR (allemand), SP, IT }
 M:Array[1..6,1..5] Of PChar=(
  ('Mot de passe : ','Password: ','Passwort: ','Contrasena: ','Password: '),
  ('Connexion refusee','Login incorrect','Anmeldung fehlgeschlagen',
   'Acceso denegado','Accesso negato'),
  ('Pas de repertoire % : connexion dans /',
   'No directory %: logging in with home=/',
   'Kein Verzeichnis %: Anmeldung in /',
   'No hay directorio %: entrando en /',
   'Nessuna directory %: accesso in /'),
  ('login : setuid impossible : ','login: setuid failed: ',
   'login: setuid fehlgeschlagen: ','login: setuid ha fallado: ',
   'login: setuid fallito: '),
  ('Usage : login [nom]','Usage: login [name]','Aufruf: login [Name]',
   'Uso: login [nombre]','Uso: login [nome]'),
  ('Ouvre une session (nom et mot de passe de /etc/passwd).',
   'Open a session (name and password from /etc/passwd).',
   'Oeffnet eine Sitzung (Name und Passwort aus /etc/passwd).',
   'Abre una sesion (nombre y contrasena de /etc/passwd).',
   'Apre una sessione (nome e password da /etc/passwd).'));

Var
 Name,Pw,Entry,Home,Sh,S,Base,LangName,Term:String; Uid,Gid,E,Tries,K:Integer;
 Found:Boolean;

Function Msg(Id:Integer):String;
Var P:PChar; X:String;
Begin
 P:=M[Id,SysLang]; X:='';
 While P^<>#0 Do Begin X:=X+P^; Inc(P) End;
 Msg:=X;
End;

Procedure Put(Fd:Integer;S:String);
Begin
 If Length(S)>0 Then SysWrite(Fd,S[1],Length(S));
End;

Function Crypt(Pw,Salt:String):String;
Var A,B,C,D,X:Word; R,K,Bit,V:Integer; S,T:String;
 Function GetBit(N:Integer):Integer;
 Var W:Word;
 Begin
  Case N Div 16 Of 0:W:=A; 1:W:=B; 2:W:=C; Else W:=D End;
  If N>=64 Then GetBit:=0
  Else GetBit:=(W Shr (15-N Mod 16))And 1;
 End;
Begin
 Salt:=Copy(Salt+'..',1,2);
 S:=Salt+Pw;
 A:=$6A09; B:=$BB67; C:=$3C6E; D:=$A54F;
 For R:=1 To 32 Do
  For K:=1 To Length(S) Do Begin
   X:=Ord(S[K]);
   A:=Word(((Longint(A Xor X)*31421)+1)And $FFFF);
   B:=Word(((Longint(B Xor A)*31421)+X)And $FFFF);
   C:=Word(((Longint(C Xor B)*31421)+7)And $FFFF);
   D:=Word(((Longint(D Xor C)*31421)+A)And $FFFF);
  End;
 T:=Salt; Bit:=0;
 For K:=1 To 11 Do Begin
  V:=0;
  For R:=1 To 6 Do Begin V:=V*2+GetBit(Bit); Inc(Bit) End;
  T:=T+CryptChars[V+1];
 End;
 Crypt:=T;
End;

Function PwField(L:String;N:Integer):String;
{ champ N (1 = nom) d'une ligne de /etc/passwd }
Var K:Integer;
Begin
 For K:=2 To N Do Begin
  If Pos(':',L)=0 Then Begin PwField:=''; Exit End;
  Delete(L,1,Pos(':',L));
 End;
 If Pos(':',L)>0 Then L:=Copy(L,1,Pos(':',L)-1);
 PwField:=L;
End;

Function ReadPass(Prompt:String):String;
{ lecture d'un mot de passe sans echo }
Var Sg,Old:TSgttyb; S:String; C:Char; N:Integer; Tty:Boolean;
Begin
 Put(2,Prompt);
 Tty:=GTty(0,Old)=0;
 If Tty Then Begin
  Sg:=Old; Sg.Flags:=Sg.Flags And Not ECHO; SysIoctl(0,TIOCSETN,Sg);
 End;
 S:='';
 Repeat
  N:=SysRead(0,C,1);
  If (N<=0)Or(C=#10) Then Break;
  If Length(S)<64 Then S:=S+C;
 Until False;
 If Tty Then SysIoctl(0,TIOCSETN,Old);
 C:=#10; SysWrite(2,C,1);
 ReadPass:=S;
End;

Function ReadLine(Prompt:String):String;
Var S:String; C:Char; N:Integer;
Begin
 Put(1,Prompt);
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
 If (Name='/?')Or(Name='-h')Or(Name='--help') Then Begin
  Put(1,Msg(mUsage)+#10+Msg(mHelp2)+#10); SysExit(0);
 End;
 LangName:=SysGetEnv('LANGUAGE'); Term:=SysGetEnv('TERM');
 Tries:=0;
 Repeat
  While Name='' Do Name:=ReadLine('login: ');
  Found:=Lookup(Name,Entry);
  If Found And(PwField(Entry,2)='') Then Pw:=''
  Else Begin
   S:=ReadPass(Msg(mPassword));
   If Found Then Begin
    Pw:=PwField(Entry,2);
    If Crypt(S,Copy(Pw,1,2))<>Pw Then Found:=False;
   End;
  End;
  If Not Found Then Begin
   WriteLn(Msg(mDenied));
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
  S:=Msg(mNoHome); K:=Pos('%',S);
  WriteLn(Copy(S,1,K-1),Home,Copy(S,K+1,255));
  Home:='/'; SysChdir('/');
 End;
 If (SetGid(Gid)<0)Or(SetUid(Uid)<0) Then Begin
  WriteLn(Msg(mNoSetuid),SysErrorText(Errno)); SysExit(1);
 End;
 Motd;
 K:=Length(Sh);
 While (K>0)And(Sh[K]<>'/') Do Dec(K);
 Base:=Copy(Sh,K+1,255);
 SysSignal(SIGINT,SIG_DFL); SysSignal(SIGQUIT,SIG_DFL);
 ArgReset; ArgAdd('-'+Base);
 EnvAdd('HOME='+Home); EnvAdd('SHELL='+Sh); EnvAdd('USER='+Name);
 EnvAdd('LOGNAME='+Name); EnvAdd('PATH=/bin:/usr/bin');
 If LangName<>'' Then EnvAdd('LANGUAGE='+LangName);
 If Term<>'' Then EnvAdd('TERM='+Term);
 ArgExec(Sh);
 WriteLn('login : ',Sh,' : ',SysErrorText(Errno));
 SysExit(1);
END.
