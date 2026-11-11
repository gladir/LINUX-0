{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2026
  @website(https://www.gladir.com/linux-0)
  @abstract(Target: Linux Pascal (LPC /X))
  @description: id de LINUX-0 : utilisateur et groupe du processus, avec le
   nom de l'utilisateur pris dans /etc/passwd.
   Usage : id
}

Program Id;

{$I-}

Var
 U,G:Integer;

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

BEGIN
 U:=GetUid; G:=GetGid;
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
