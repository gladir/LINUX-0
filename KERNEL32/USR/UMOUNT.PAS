{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2026
  @website(https://www.gladir.com/linux-0)
  @abstract(Target: LPC -3X)
  @description: /sbin/umount : demonte un systeme de fichiers.
}

Program Umount;
Var I, Rc : LongInt;
BEGIN
  Rc := 0;
  For I := 1 To SysArgCount - 1 Do
    If SysUmount(SysArgStr(I)) < 0 Then
    Begin
      SysPut(2, 'umount: ' + SysArgStr(I) + ': ' + SysErrorText(SysErrno) + #10);
      Rc := 1;
    End;
  SysExit(Rc);
END.
