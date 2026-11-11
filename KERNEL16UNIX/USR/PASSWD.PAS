{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2026
  @website(https://www.gladir.com/linux-0)
  @abstract(Target: Linux Pascal (LPC /X))
  @description: passwd de LINUX-0 : change le mot de passe d'un utilisateur
   dans /etc/passwd (hachage de CRYPT.INC). Un utilisateur ordinaire ne
   change que le sien, apres avoir donne l'ancien; le super-utilisateur
   change celui de n'importe qui. Un mot de passe vide supprime le mot de
   passe.
   Usage : passwd [nom]
}

Program Passwd;

{$I-}

{$I CRYPT.INC}

Const
 MAXL=64;

Var
 Lines:Array[1..MAXL]Of String;
 NL,K,Me,Uid,E,Fd:Integer; Name,Old,New1,New2,Salt,L:String; F:Text;
 Found:Boolean; T:Longint;

BEGIN
 Me:=GetUid;
 Assign(F,'/etc/passwd'); Reset(F);
 If IOResult<>0 Then Begin WriteLn('passwd : /etc/passwd illisible'); Halt(1) End;
 NL:=0;
 While Not EOF(F)And(NL<MAXL) Do Begin Inc(NL); ReadLn(F,Lines[NL]) End;
 Close(F);
 Name:=''; Found:=False;
 If ArgCount>1 Then Name:=ArgStr(1);
 For K:=1 To NL Do Begin
  Val(PwField(Lines[K],3),Uid,E);
  If ((Name='')And(Uid=Me))Or((Name<>'')And(PwField(Lines[K],1)=Name)) Then Begin
   Found:=True; Break;
  End;
 End;
 If Not Found Then Begin WriteLn('passwd : utilisateur inconnu'); Halt(1) End;
 Name:=PwField(Lines[K],1);
 If (Me<>0)And(Uid<>Me) Then Begin WriteLn('passwd : permission refusee'); Halt(1) End;
 WriteLn('Changement du mot de passe de ',Name);
 L:=PwField(Lines[K],2);
 If (Me<>0)And(L<>'') Then Begin
  Old:=ReadPass('Ancien mot de passe : ');
  If Crypt(Old,Copy(L,1,2))<>L Then Begin WriteLn('Mot de passe incorrect'); Halt(1) End;
 End;
 New1:=ReadPass('Nouveau mot de passe : ');
 New2:=ReadPass('Nouveau mot de passe (encore) : ');
 If New1<>New2 Then Begin WriteLn('Les mots de passe sont differents'); Halt(1) End;
 If New1='' Then L:='' Else Begin
  T:=SysTime Xor GetPid;
  Salt:=CryptChars[(T And 63)+1]+CryptChars[((T Shr 6)And 63)+1];
  L:=Crypt(New1,Salt);
 End;
 Lines[K]:=PwField(Lines[K],1)+':'+L+':'+Copy(Lines[K],Length(PwField(Lines[K],1))+
   Length(PwField(Lines[K],2))+3,255);
 Assign(F,'/etc/ptmp'); Rewrite(F);
 If IOResult<>0 Then Begin WriteLn('passwd : /etc/ptmp : ',SysErrorText(Errno)); Halt(1) End;
 For E:=1 To NL Do WriteLn(F,Lines[E]);
 Close(F);
 SysUnlink('/etc/passwd');
 If SysRename('/etc/ptmp','/etc/passwd')<0 Then Begin
  WriteLn('passwd : ',SysErrorText(Errno)); Halt(1);
 End;
END.
