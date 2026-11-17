{ unkmod : utilise un symbole que le noyau n'exporte pas }
Program UnkMod;

Procedure symbole_inexistant(X : LongInt); External;

Function InitUnk : LongInt; ModuleInit;
Begin
  symbole_inexistant(1);
  InitUnk := 0;
End;

Begin
End.
