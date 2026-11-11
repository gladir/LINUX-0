{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2026
  @website(https://www.gladir.com/linux-0)
  @abstract(Target: KERNEL16UNIX (LPC /X))
  @description: id de LINUX-0 : utilisateur et groupe du processus, avec le
   nom de l'utilisateur pris dans /etc/passwd. -u et -g n'affichent que le
   numero de l'utilisateur ou du groupe, -n le nom (utilisateur) au lieu du
   numero. Messages en francais, ou selon la variable d'environnement
   LANGUAGE : EN anglais, GR allemand, SP espagnol, IT italien.
   Usage : id [-u | -g] [-n]
}

{$DEFINE LANGERR}   { messages d'erreur du systeme en 5 langues }

Program Id;

{$I-}

Const
 mHelp1=1; mHelp2=2; mHelp3=3; mHelp4=4; mHelp5=5; mBadOpt=6;
 { messages : colonnes FR, EN, GR (allemand), SP, IT }
 M:Array[1..6,1..5] Of PChar=(
  ('Usage : id [-u | -g] [-n]','Usage: id [-u | -g] [-n]',
   'Aufruf: id [-u | -g] [-n]','Uso: id [-u | -g] [-n]',
   'Uso: id [-u | -g] [-n]'),
  ('Affiche l''utilisateur et le groupe du processus.',
   'Print the user and group of the process.',
   'Zeigt Benutzer und Gruppe des Prozesses an.',
   'Muestra el usuario y el grupo del proceso.',
   'Mostra l''utente e il gruppo del processo.'),
  ('  -u  seulement le numero de l''utilisateur',
   '  -u  only the user number','  -u  nur die Benutzernummer',
   '  -u  solo el numero del usuario','  -u  solo il numero dell''utente'),
  ('  -g  seulement le numero du groupe','  -g  only the group number',
   '  -g  nur die Gruppennummer','  -g  solo el numero del grupo',
   '  -g  solo il numero del gruppo'),
  ('  -n  le nom de l''utilisateur au lieu du numero',
   '  -n  the user name instead of the number',
   '  -n  der Benutzername statt der Nummer',
   '  -n  el nombre del usuario en lugar del numero',
   '  -n  il nome dell''utente invece del numero'),
  ('id : option inconnue : ','id: unknown option: ',
   'id: unbekannte Option: ','id: opcion desconocida: ',
   'id: opzione sconosciuta: '));

Var
 U,G,I,K,Mode:Integer; Names:Boolean; S:String;

Function Msg(Id:Integer):String;
Var P:PChar; T:String;
Begin
 P:=M[Id,SysLang]; T:='';
 While P^<>#0 Do Begin T:=T+P^; Inc(P) End;
 Msg:=T;
End;

Procedure Put(Fd:Integer;S:String);
Begin
 If Length(S)>0 Then SysWrite(Fd,S[1],Length(S));
End;

Function UserName(Uid:Integer):String;
Var F:Text; S,N:String; U,E,P:Integer;
Begin
 UserName:='';
 Assign(F,'/etc/passwd'); Reset(F);
 If IOResult<>0 Then Exit;
 While Not EOF(F) Do Begin
  ReadLn(F,S);
  P:=Pos(':',S); N:=Copy(S,1,P-1); Delete(S,1,P);
  P:=Pos(':',S); Delete(S,1,P);
  P:=Pos(':',S); Val(Copy(S,1,P-1),U,E);
  If (E=0)And(U=Uid) Then Begin UserName:=N; Break End;
 End;
 Close(F);
End;

Function Who(N:Integer):String;
Var S:String;
Begin
 S:=UserName(N);
 If (S='')Or Not Names Then Str(N,S);
 Who:=S;
End;

BEGIN
 U:=GetUid; G:=GetGid; Mode:=0; Names:=False;
 For I:=1 To ArgCount-1 Do Begin
  S:=ArgStr(I);
  If (S='/?')Or(S='-h')Or(S='--help') Then Begin
   For K:=mHelp1 To mHelp5 Do Put(1,Msg(K)+#10);
   Halt(0);
  End Else If (Length(S)>1)And(S[1]='-') Then Begin
   { options groupees : -u -g -n, par exemple -un }
   For K:=2 To Length(S) Do
    If S[K]='u' Then Mode:=1
    Else If S[K]='g' Then Mode:=2
    Else If S[K]='n' Then Names:=True
    Else Begin
     Put(2,Msg(mBadOpt)+'-'+S[K]+#10); Put(2,Msg(mHelp1)+#10); Halt(2);
    End;
  End Else Begin
   Put(2,Msg(mBadOpt)+S+#10); Put(2,Msg(mHelp1)+#10); Halt(2);
  End;
 End;
 If Mode=1 Then Begin Put(1,Who(U)+#10); Halt(0) End;
 If Mode=2 Then Begin Str(G,S); Put(1,S+#10); Halt(0) End;
 Write('uid=',U);
 If UserName(U)<>'' Then Write('(',UserName(U),')');
 Write(' gid=',G);
 If GetEUid<>U Then Begin
  Write(' euid=',GetEUid);
  If UserName(GetEUid)<>'' Then Write('(',UserName(GetEUid),')');
 End;
 If GetEGid<>G Then Write(' egid=',GetEGid);
 WriteLn;
END.
