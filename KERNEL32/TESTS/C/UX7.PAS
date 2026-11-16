Program UX7;
{ temporaires String : plusieurs concatenations / Copy / Concat vivants dans le
  meme appel, comparaisons de concatenations, appels imbriques }
Function F(A : String; N : LongInt; B : String) : String;
Begin
  F := A + '|' + IntToStr(N) + '|' + B;
End;
Function G(A, B, C : String) : String;
Begin
  G := A + '|' + B + '|' + C;
End;
Function H(A : String; B : String) : Integer;
Begin
  H := Length(A) * 100 + Length(B);
End;
Var X, Y, Z : String;
Begin
  X := 'ab'; Y := 'cd'; Z := 'ef';
  WriteLn(F(X + Y, 5, Z + X));
  WriteLn(G(X + Y, Y + Z, Z + X));
  WriteLn(G(X + Y + Z, Y + Z + X, Z + X + Y));
  WriteLn(G(Copy(X + Y, 2, 2), UpperCase(Y + Z), IntToStr(12) + X));
  WriteLn(F(F(X + Y, 1, Z + X), 2, F(Y + Z, 3, X + Y)));
  X := 'abcdef'; Y := 'ghijkl'; Z := 'mnopqr';
  WriteLn(G(Copy(X, 1, 2), Copy(Y, 2, 3), Copy(Z, 3, 2)));
  WriteLn(G(Copy(X, 1, 2), Y + Z, Copy(Z, 3, 2)));
  WriteLn(G(Concat(X, Y), Concat(Y, Z), Concat(Z, X)));
  WriteLn(G(UpperCase(X), LowerCase('QQ'), IntToStr(77)));
  WriteLn(G(X + Copy(Y, 1, 2), Copy(X, 1, 1) + Z, 'k' + Y));
  WriteLn(H(X + Y, Y + Z + X));
  WriteLn(G(Chr(65) + X, 'a' + Chr(66), X + Chr(67)));
  WriteLn(G(X + Y + Z + X, Y + Z, Z));
  WriteLn(G(G(X + Y, Z + X, Y + Z), G(Y + X, X + Z, Z + Y), 'e'));
  Write(X + Y, '|', Y + Z, '|', Z + X); WriteLn;
  WriteLn(Length(X + Y) + Length(Y + Z), ' ', Pos(X + 'g', X + Y + Z));
  If (X + Y) = (X + Z) Then WriteLn('eq') Else WriteLn('ne');
  If (X + Y) < (Y + Z) Then WriteLn('lt') Else WriteLn('ge');
  WriteLn(Copy(X + Y, 5, 4) + Copy(Y + Z, 5, 4) + Copy(Z + X, 5, 4));
End.
