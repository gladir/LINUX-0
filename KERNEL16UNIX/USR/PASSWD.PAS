{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2026
  @website(https://www.gladir.com/linux-0)
  @abstract(Target: KERNEL16UNIX (LPC /X))
  @description: passwd de LINUX-0 : change le mot de passe d'un utilisateur
   dans /etc/passwd. Un utilisateur ordinaire ne change que le sien, apres
   avoir donne l'ancien; le super-utilisateur change celui de n'importe qui.
   Un mot de passe vide supprime le mot de passe. Le fichier est recopie
   ligne a ligne dans /etc/ptmp, puis renomme (pas de limite de taille).
   Messages en francais, ou selon la variable d'environnement LANGUAGE : EN
   anglais, GR allemand, SP espagnol, IT italien.

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
   d'abord). Ce code est repris tel quel dans LOGIN.PAS et dans
   TOOLS/MKPASSWD.PAS (programme de l'hote).
   Usage : passwd [nom]
}

{$DEFINE LANGERR}   { messages d'erreur du systeme en 5 langues }

Program Passwd;

{$I-}

Const
 CryptChars:String[64]=
  './0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz';
 mUsage=1; mHelp2=2; mCantRead=3; mUnknown=4; mDenied=5; mChanging=6;
 mOldPw=7; mBadPw=8; mNewPw=9; mNewPw2=10; mDiffer=11; mBadOpt=12;
 { messages : colonnes FR, EN, GR (allemand), SP, IT }
 M:Array[1..12,1..5] Of PChar=(
  ('Usage : passwd [nom]','Usage: passwd [name]','Aufruf: passwd [Name]',
   'Uso: passwd [nombre]','Uso: passwd [nome]'),
  ('Change le mot de passe d''un utilisateur (le sien par defaut).',
   'Change the password of a user (your own by default).',
   'Aendert das Passwort eines Benutzers (standardmaessig das eigene).',
   'Cambia la contrasena de un usuario (la propia por omision).',
   'Cambia la password di un utente (la propria per default).'),
  ('passwd : /etc/passwd illisible','passwd: cannot read /etc/passwd',
   'passwd: /etc/passwd nicht lesbar','passwd: no se puede leer /etc/passwd',
   'passwd: impossibile leggere /etc/passwd'),
  ('passwd : utilisateur inconnu','passwd: unknown user',
   'passwd: unbekannter Benutzer','passwd: usuario desconocido',
   'passwd: utente sconosciuto'),
  ('passwd : permission refusee','passwd: permission denied',
   'passwd: Zugriff verweigert','passwd: permiso denegado',
   'passwd: permesso negato'),
  ('Changement du mot de passe de ','Changing the password of ',
   'Aendern des Passworts von ','Cambio de la contrasena de ',
   'Cambio della password di '),
  ('Ancien mot de passe : ','Old password: ','Altes Passwort: ',
   'Contrasena anterior: ','Vecchia password: '),
  ('Mot de passe incorrect','Incorrect password','Falsches Passwort',
   'Contrasena incorrecta','Password errata'),
  ('Nouveau mot de passe : ','New password: ','Neues Passwort: ',
   'Contrasena nueva: ','Nuova password: '),
  ('Nouveau mot de passe (encore) : ','New password (again): ',
   'Neues Passwort (nochmals): ','Contrasena nueva (otra vez): ',
   'Nuova password (ancora): '),
  ('Les mots de passe sont differents','The passwords differ',
   'Die Passwoerter sind verschieden','Las contrasenas son diferentes',
   'Le password sono diverse'),
  ('passwd : option inconnue : ','passwd: unknown option: ',
   'passwd: unbekannte Option: ','passwd: opcion desconocida: ',
   'passwd: opzione sconosciuta: '));

Var
 K,Me,Uid,E,Fd:Integer; Name,Old,New1,New2,Salt,L,S:String; F,G:Text;
 Found:Boolean; T:Longint;

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

Procedure Die(S:String);
Begin
 Put(2,S+#10); Halt(1);
End;

BEGIN
 Me:=GetUid;
 Name:=ArgStr(1);
 If (Name='/?')Or(Name='-h')Or(Name='--help') Then Begin
  Put(1,Msg(mUsage)+#10+Msg(mHelp2)+#10); Halt(0);
 End;
 If (Name<>'')And(Name[1]='-') Then Begin
  Put(2,Msg(mBadOpt)+Name+#10); Put(2,Msg(mUsage)+#10); Halt(2);
 End;
 Assign(F,'/etc/passwd'); Reset(F);
 If IOResult<>0 Then Die(Msg(mCantRead));
 Found:=False; L:='';
 While Not EOF(F) Do Begin
  ReadLn(F,S);
  Val(PwField(S,3),Uid,E);
  If E<>0 Then Uid:=-1;
  If ((Name='')And(Uid=Me))Or((Name<>'')And(PwField(S,1)=Name)) Then Begin
   Found:=True; L:=S; Break;
  End;
 End;
 Close(F);
 If Not Found Then Die(Msg(mUnknown));
 Name:=PwField(L,1);
 If (Me<>0)And(Uid<>Me) Then Die(Msg(mDenied));
 Put(1,Msg(mChanging)+Name+#10);
 S:=PwField(L,2);
 If (Me<>0)And(S<>'') Then Begin
  Old:=ReadPass(Msg(mOldPw));
  If Crypt(Old,Copy(S,1,2))<>S Then Die(Msg(mBadPw));
 End;
 New1:=ReadPass(Msg(mNewPw));
 New2:=ReadPass(Msg(mNewPw2));
 If New1<>New2 Then Die(Msg(mDiffer));
 If New1='' Then S:='' Else Begin
  T:=SysTime Xor GetPid;
  Salt:=CryptChars[(T And 63)+1]+CryptChars[((T Shr 6)And 63)+1];
  S:=Crypt(New1,Salt);
 End;
 { nouvelle ligne : nom, mot de passe, puis la fin de l'ancienne ligne }
 L:=PwField(L,1)+':'+S+':'+Copy(L,Length(PwField(L,1))+
   Length(PwField(L,2))+3,255);
 Assign(F,'/etc/passwd'); Reset(F);
 If IOResult<>0 Then Die(Msg(mCantRead));
 Assign(G,'/etc/ptmp'); Rewrite(G);
 If IOResult<>0 Then Die('passwd : /etc/ptmp : '+SysErrorText(Errno));
 While Not EOF(F) Do Begin
  ReadLn(F,S);
  If PwField(S,1)=Name Then WriteLn(G,L) Else WriteLn(G,S);
 End;
 Close(F); Close(G);
 If IOResult<>0 Then Die('passwd : /etc/ptmp : '+SysErrorText(Errno));
 SysUnlink('/etc/passwd');
 If SysRename('/etc/ptmp','/etc/passwd')<0 Then
  Die('passwd : '+SysErrorText(Errno));
END.
