Program ER1;
{ erreur attendue : variable globale du meme nom qu'une procedure }
Var Ev : LongInt;
Procedure EV;
Begin
  WriteLn('x');
End;
Begin
  Ev := 3;
End.
