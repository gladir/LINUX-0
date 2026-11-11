{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2026
  @website(https://www.gladir.com/linux-0)
  @abstract(Target: Linux Pascal (LPC /X))
  @description: rmdir de LINUX-0 : supprime des repertoires vides.
   Usage : rmdir repertoire...
}

Program RmDir_;

Var
 I,R:Integer;

BEGIN
 R:=0;
 If ArgCount<2 Then Begin WriteLn('usage : rmdir repertoire...'); Halt(2) End;
 For I:=1 To ArgCount-1 Do
  If SysRmdir(ArgStr(I))<0 Then Begin
   WriteLn('rmdir : ',ArgStr(I),' : ',SysErrorText(Errno)); R:=1;
  End;
 Halt(R);
END.
