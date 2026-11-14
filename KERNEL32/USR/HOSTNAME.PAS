{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2026
  @website(https://www.gladir.com/linux-0)
  @abstract(Target: LPC -3X)
  @description: /bin/hostname : affiche ou change le nom de la machine (sethostname).
}

Program Hostname;
Var U : TUtsName; A : String; R : LongInt;
BEGIN
  If SysArgCount > 1 Then
  Begin
    A := SysArgStr(1);
    R := SysCall(74, SysNewZ(A), Length(A), 0, 0, 0);
    If R < 0 Then
    Begin
      SysErrno := -R;
      SysPut(2, 'hostname: ' + SysErrorText(SysErrno) + #10);
      SysExit(1);
    End;
    SysExit(0);
  End;
  SysUname(U);
  SysPut(1, U.NodeName + #10);
END.
