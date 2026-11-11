{ Hachage des mots de passe de LINUX-0 (login, passwd), au format de
  /etc/passwd de UNIX V7 : 13 caracteres, les 2 premiers etant le sel,
  les 11 suivants le resultat code avec l'alphabet ./0-9A-Za-z.
  Ce n'est pas le DES de crypt(3) : quatre mots de 16 bits A, B, C, D
  (6A09h, BB67h, 3C6Eh, A54Fh) melangent 32 fois les octets x du sel puis
  du mot de passe :
    A := ((A xor x) * 31421 + 1) mod 65536
    B := ((B xor A) * 31421 + x) mod 65536
    C := ((C xor B) * 31421 + 7) mod 65536
    D := ((D xor C) * 31421 + A) mod 65536
  puis les 64 bits A:B:C:D sont codes par groupes de 6 bits (poids forts
  d'abord). Le meme calcul est fait sur l'hote par TOOLS/MKPASSWD.PAS (BUILD.SH). }

Const
 CryptChars:String[64]='./0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz';

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
 If Prompt<>'' Then SysWrite(2,Prompt[1],Length(Prompt));
 Tty:=GTty(0,Old)=0;
 If Tty Then Begin Sg:=Old; Sg.Flags:=Sg.Flags And Not ECHO; SysIoctl(0,TIOCSETN,Sg) End;
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
