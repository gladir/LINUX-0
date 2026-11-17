Program ER2;
{ erreur attendue : nom de fonction passe en parametre Var }
Function F : LongInt;
Begin
  F := 1;
End;
Procedure G(Var X : LongInt);
Begin
  X := 2;
End;
Begin
  G(F);
End.
