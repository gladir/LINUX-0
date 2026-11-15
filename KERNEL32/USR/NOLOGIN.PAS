{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2026
  @website(https://www.gladir.com/linux-0)
  @abstract(Target: LPC -3X)
  @description: /sbin/nologin : refuse une connexion (shell des comptes systeme).
}

Program NOLOGIN;

BEGIN
  SysPut(1, 'This account is currently not available.' + #10);
  SysExit(1);
END.
