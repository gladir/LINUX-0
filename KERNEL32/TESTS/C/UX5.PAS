Program UX5;
{ tableaux ouverts (Array Of T), Move d'un litteral, Insert dans String[n] }
Type TA = Array[3..7] Of LongInt;
Var
  V : TA;
  B : Array[0..9] Of Byte;
  Ss : Array[1..3] Of String;
  Ch : Array[0..9] Of Char;
  I : LongInt;
  S4 : String[4];
  S, T : String;
  T10 : String[10];

Function Sum(Const A : Array Of LongInt) : LongInt;
Var K, R : LongInt;
Begin
  R := 0;
  For K := Low(A) To High(A) Do R := R + A[K];
  Sum := R;
End;

Function Sum2(A : Array Of LongInt; K : LongInt) : LongInt;
Begin
  Sum2 := Sum(A) * K;
End;

Procedure Fill(Var A : Array Of Byte; X : Byte);
Var K : Integer;
Begin
  For K := 0 To High(A) Do A[K] := X + K;
End;

Procedure Show(Const A : Array Of String);
Var K : Integer;
Begin
  For K := 0 To High(A) Do WriteLn(K, A[K]);
End;

Function Cnt(C : Array Of Char) : Integer;
Begin
  Cnt := High(C) + 1;
End;

Procedure Outer;
  Procedure Inner(Const Q : Array Of Word; Z : Integer);
  Begin
    WriteLn(High(Q), ' ', Q[1], ' ', Z);
  End;
Begin
  Inner([10, 20, 30], 5);
End;

Begin
  For I := 3 To 7 Do V[I] := I;
  WriteLn(Sum(V), ' ', Sum2(V, 2), ' ', Sum([5]), ' ', Sum([1, 2 + 3, I]));
  Fill(B, 7);
  WriteLn(B[0], ' ', B[9]);
  Ss[1] := 'a'; Ss[2] := 'bb'; Ss[3] := 'ccc';
  Show(Ss);
  Outer;
  WriteLn(Cnt(['a', 'b', 'c']), ' ', Cnt(Ch));
  { Move d'un litteral : chaine Pascal (octet de longueur en tete) }
  FillChar(Ch, 10, '.');
  Move('abc', Ch, 3);
  WriteLn(Ord(Ch[0]), ' ', Ch[1], ' ', Ch[2], ' ', Ch[3]);
  S := 'xyz';
  Move(S, Ch, 3);
  WriteLn(Ord(Ch[0]), ' ', Ch[1], ' ', Ch[2]);
  Move(S[1], Ch, 3);
  WriteLn(Ch[0], Ch[1], Ch[2]);
  { Insert tronque dans une String[n] }
  S4 := 'abc'; Insert('XYZ', S4, 2); WriteLn(S4, ' ', Length(S4));
  S := 'hello'; Insert('--', S, 3); WriteLn(S);
  Insert('<', S, 1); Insert('>', S, 99); WriteLn(S);
  T := 'ab'; Insert(T, T, 2); WriteLn(T);
  T10 := 'xy'; Insert('0123456789', T10, 1); WriteLn(T10);
  S := '';
  For I := 1 To 40 Do Insert('abcdefgh', S, 1);
  WriteLn(Length(S));
End.
