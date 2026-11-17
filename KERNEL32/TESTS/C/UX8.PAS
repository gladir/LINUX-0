Program UX8;
{ Delete borne par la longueur (position, nombre), Copy/Pos limites }
Var S : String; X, N : LongInt;
Begin
  S := 'a';
  X := 2;
  Delete(S, 1, X);
  WriteLn('[', S, ']', Length(S));
  S := 'abcdef';
  N := 100;
  Delete(S, 3, N);
  WriteLn('[', S, ']', Length(S));
  S := 'abc';
  Delete(S, 4, 1);
  Delete(S, 9, 1);
  Delete(S, 0, 1);
  WriteLn('[', S, ']', Length(S));
  S := 'hello world';
  Delete(S, 1, 6);
  WriteLn('[', S, ']', Length(S));
  S := 'abc';
  Delete(S, 2, 1);
  WriteLn('[', S, ']', Length(S));
End.
