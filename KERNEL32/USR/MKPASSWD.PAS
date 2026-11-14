{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2026
  @website(https://www.gladir.com/linux-0)
  @abstract(Target: LPC -3X)
  @description: /sbin/mkpasswd : affiche le mot de passe code (13 caracteres) pour /etc/shadow : mkpasswd mot_de_passe [sel].
}

Program Mkpasswd;
Var S : String; Pw : String;
BEGIN
  If SysArgCount < 2 Then
  Begin
    SysPut(2, 'Usage: mkpasswd password [salt]' + #10);
    SysExit(1);
  End;
  Pw := SysArgStr(1);
  If SysArgCount > 2 Then S := SysArgStr(2)
  Else S := Chr(97 + SysTime Mod 26) + Chr(97 + (SysTime Div 7) Mod 26);
  SysPut(1, SysCrypt(Pw, S) + #10);
END.
