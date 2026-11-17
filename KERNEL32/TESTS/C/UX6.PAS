Program UX6;
{ pointeurs de procedures et de fonctions, packed record, reels au format
  Turbo Pascal }
Type
  TProc = Procedure;
  TCb = Procedure(N : LongInt; Const S : String);
  TFn = Function(A, B : LongInt) : LongInt;
  TRf = Function(X : Double) : Double;
  TCmd = Record
    Name : String[8];
    Run : TProc;
    Fn : TFn;
  End;
  PK = Packed Record
    A : Byte;
    B : Word;
    C : LongInt;
  End;
Var
  P, Q : TProc;
  Cb : TCb;
  Tab : Array[1..3] Of TCmd;
  I : Integer;
  K : PK;
  Fs : Array[0..1] Of TFn;
  D : Double;
  S : String;
  Err : Integer;
  Rf : TRf;

Procedure Hi; Begin WriteLn('hi'); End;
Procedure Yo; Begin WriteLn('yo'); End;
Procedure Show(N : LongInt; Const S : String);
Begin
  WriteLn(N, ':', S);
End;
Function Add(A, B : LongInt) : LongInt; Begin Add := A + B; End;
Function Mul(A, B : LongInt) : LongInt; Begin Mul := A * B; End;
Function Half(X : Double) : Double; Begin Half := X / 2.0; End;

Procedure Apply(Pr : TProc; Cnt : Integer);
Var K : Integer;
Begin
  For K := 1 To Cnt Do Pr;
End;

Function Calc(Fn : TFn; X : LongInt) : LongInt;
Begin
  Calc := Fn(X, X + 1);
End;

Begin
  P := Hi; Q := Yo;
  If P <> Q Then WriteLn('diff');
  Apply(P, 2); Apply(Q, 1);
  Cb := Show; Cb(5, 'five');
  Tab[1].Name := 'one'; Tab[1].Run := Hi; Tab[1].Fn := Add;
  Tab[2].Name := 'two'; Tab[2].Run := Yo; Tab[2].Fn := Mul;
  Tab[3].Run := Nil;
  For I := 1 To 3 Do
    If Assigned(Tab[I].Run) Then
    Begin
      Tab[I].Run;
      WriteLn(Tab[I].Fn(3, 4));
    End
    Else WriteLn('nil ', I);
  WriteLn(Calc(Add, 5), ' ', Calc(Mul, 5));
  Fs[0] := Add; Fs[1] := Mul;
  WriteLn(Fs[1](6, 7));
  If Tab[3].Run = Nil Then WriteLn('isnil');
  If P <> Nil Then WriteLn('notnil');
  P := Nil;
  If P = Nil Then WriteLn('nil');
  Rf := Half;
  WriteLn(Rf(5.0):0:2);
  WriteLn(SizeOf(K));
  { reels : Write par defaut au format Turbo Pascal }
  WriteLn(0.0); WriteLn(-123.456); WriteLn(1.5e-7); WriteLn(3.14159265358979);
  WriteLn(-1.0:12); WriteLn(2.5:3); WriteLn(100.0/3.0:10:4); WriteLn(-0.5:8:1);
  D := 123.456789; WriteLn(D); WriteLn(D:12); WriteLn(1/3);
  Str(-3.14159:10:3, S); WriteLn('[', S, ']');
  Str(2.0:0:0, S); WriteLn('[', S, ']');
  Str(1234.5, S); WriteLn('[', S, ']');
  Val('3.25', D, Err); WriteLn(D:0:2, ' ', Err);
  Val('1.5E2', D, Err); WriteLn(D:0:1, ' ', Err);
  Val('12abc', D, Err); WriteLn(Err);
  Val('-0.001', D, Err); WriteLn(D:0:4, ' ', Err);
End.
