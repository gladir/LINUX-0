{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2026
  @website(https://www.gladir.com/linux-0)
  @abstract(Target: Linux Pascal (LPC /X))
  @description: mkdir de LINUX-0 : cree des repertoires (mode 0777 filtre
   par umask), avec "." et "..".
   Usage : mkdir repertoire...
}

Program MkDir_;

Var
 I,R:Integer;

BEGIN
 R:=0;
 If ArgCount<2 Then Begin WriteLn('usage : mkdir repertoire...'); Halt(2) End;
 For I:=1 To ArgCount-1 Do
  If SysMkdir(ArgStr(I),$1FF)<0 Then Begin
   WriteLn('mkdir : ',ArgStr(I),' : ',SysErrorText(Errno)); R:=1;
  End;
 Halt(R);
END.
