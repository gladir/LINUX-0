{ badinit : init_module echoue (-5) : le module ne reste pas charge }
Program BadInit;

Procedure printk(Const S : String); External;

Function InitBad : LongInt; ModuleInit;
Begin
  printk('badinit : echec volontaire');
  InitBad := -5;
End;

Begin
End.
