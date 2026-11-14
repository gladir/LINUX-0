{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2026
  @website(https://www.gladir.com/linux-0)
  @abstract(Target: LPC -3X)
  @description: /bin/sync : ecrit les tampons du cache sur les disques.
}

Program Sync;
BEGIN
  SysSync;
END.
