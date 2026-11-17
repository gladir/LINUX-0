{ hello2 : module de test qui depend de hello (symbole hello_add) }
Program Hello2;

Var
  Res : LongInt;

Procedure printk(Const S : String); External;
Function hello_add(A, B : LongInt) : LongInt; External;

Function hello2_twice(X : LongInt) : LongInt; Export;
Begin
  hello2_twice := hello_add(X, X);
End;

Function InitHello2 : LongInt; ModuleInit;
Begin
  Res := hello2_twice(21);
  If Res <> 42 Then
  Begin
    InitHello2 := -22;
    Exit;
  End;
  printk('hello2 : charge');
  InitHello2 := 0;
End;

Procedure ExitHello2; ModuleExit;
Begin
  printk('hello2 : decharge');
End;

Begin
End.
