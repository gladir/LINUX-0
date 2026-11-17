Program UX4;
{ String[n] a taille reelle (troncature, SizeOf), chaine -> variable locale
  du meme nom qu'une fonction, litteraux reels en double precision }
Type
  Rec = Record
    A : String[10];
    N : LongInt;
    B : String[3];
    C : Byte;
  End;
  Str5 = String[5];
Var
  G : String[8];
  R : Rec;
  Arr : Array[1..4] Of String[6];
  T5 : Str5;
  K : LongInt;
  D : Double;
Const
  CS : String[4] = 'abcd';
  Cmds : Array[0..2] Of String[6] = ('ls', 'cat', 'mkdir');
Function Cur : String;
Begin
  Cur := 'fonction';
End;
Function Grow(Bytes : LongInt) : LongInt;
Var Cur, Want : LongInt;
Begin
  Cur := 5;
  Want := Cur + Bytes;
  Grow := Want;
End;
Procedure P(Var S : String);
Begin
  S := 'xyz';
End;
Procedure Loc;
Var L : String[4]; M : LongInt;
Begin
  M := 12345;
  L := 'toolongvalue';
  WriteLn('L=', L, ' ', Length(L), ' M=', M);
End;
Begin
  WriteLn(SizeOf(Rec), ' ', SizeOf(G), ' ', SizeOf(Arr), ' ', SizeOf(T5));
  R.N := 99; R.C := 7;
  R.A := 'abcdefghijklmnopqrstuvwxyz';
  R.B := 'zzzzzzzz';
  WriteLn(R.A, '|', R.B, '|', R.N, '|', R.C);
  G := 'hello world';
  Arr[1] := 'qwertyuiop'; Arr[2] := 'second';
  WriteLn(G, ' ', Arr[1], ' ', Arr[2], ' ', Length(Arr[1]));
  T5 := G + '!!!!';
  WriteLn(T5, ' ', CS, ' ', Cmds[2]);
  Loc;
  K := 5;
  P(R.A); WriteLn(R.A);
  T5 := Copy(G, 2, 3); WriteLn(T5);
  Str(123456789, T5); WriteLn(T5, '/', K);
  WriteLn(Grow(3), ' ', Cur);
  D := 100.0 / 3.0;
  WriteLn(D:0:8, ' ', (100.0 / 3.0):0:8);
End.
