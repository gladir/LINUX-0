{ TM1 : module du noyau (-3M) : init/exit, Export, External, donnees }
Program TM1;

Var
  Counter : LongInt;
  Name : Array[0..15] Of Char;
  Msg : String;

Procedure printk(Const S : String); External;
Function kmalloc(Size : LongInt) : LongInt; External;

Procedure Bump(N : LongInt);
Begin
  Counter := Counter + N;
End;

Procedure DoInit; ModuleInit;
Var P : LongInt;
Begin
  Msg := 'hello module';
  printk(Msg);
  P := kmalloc(64);
  Bump(P);
End;

Procedure DoExit; ModuleExit;
Begin
  printk('bye');
End;

Procedure Helper(X : LongInt); Export;
Begin
  Bump(X);
End;

Begin
End.
