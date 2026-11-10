{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2026
  @website(https://www.gladir.com/linux-0)
  @abstract(Target: Turbo Pascal 7)
  @description: Test du noyau KERNEL16 : fixe la date (INT 21h AH=2Bh) puis
    la relit (AH=2Ah). Le noyau doit convertir l'annee en BCD pour le BIOS.
}

Program TKDATE;

Uses DOS;

Var
 Y,M,D,W:Word;

BEGIN
 SetDate(2027,3,15);
 GetDate(Y,M,D,W);
 WriteLn('Date relue : ',Y,'-',M,'-',D);
 If(Y=2027)and(M=3)and(D=15)Then WriteLn('OK')Else WriteLn('ECHEC');
END.
