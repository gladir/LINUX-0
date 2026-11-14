{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2026
  @website(https://www.gladir.com/linux-0)
  @abstract(Target: Free Pascal)
  @description: Unite hote de LPC32 : rend executable le fichier produit
    (chmod 755) sous Linux. Isolee pour que les identificateurs de BaseUnix
    ne se melangent pas a ceux de LPC32.
}

{$MODE TP}
{$H-}

Unit L32SYS;

Interface

Procedure L32MakeExec(Const Path : String);
Function L32GetEnv(Const Name : String) : String;

Implementation

Uses BaseUnix, Strings;

Procedure L32MakeExec(Const Path : String);
Begin
  FpChmod(Path, 493);   { 0755 octal }
End;

Function L32GetEnv(Const Name : String) : String;
Begin
  L32GetEnv := StrPas(fpGetEnv(Name));
End;

End.
