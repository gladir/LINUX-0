{ irqmod : module de test de request_irq : IRQ 8 (horloge CMOS, interruption
  periodique a 1024 Hz) comptee par le gestionnaire ; /dev/irqmod (majeur 241),
  ioctl 1 : nombre d'IRQ recues }
Program IrqMod;

Var
  Ops   : Array[0..15] Of LongInt;
  Count, Major : LongInt;

Procedure printk(Const S : String); External;
Function register_chrdev(Major : LongInt; Const Name : String; Tab : LongInt)
    : LongInt; External;
Function unregister_chrdev(Major : LongInt) : LongInt; External;
Function request_irq(Irq, Fn : LongInt) : LongInt; External;
Function free_irq(Irq : LongInt) : LongInt; External;
Function put_user_long(Addr, V : LongInt) : LongInt; External;

Procedure Handler;
Var C : LongInt;
Begin
  Inc(Count);
  Port[$70] := $0C;
  C := Port[$71];
  If C = 255 Then Count := Count;
End;

Function DevIoctl(F, Cmd, Arg : LongInt) : LongInt;
Begin
  If Cmd = 1 Then DevIoctl := put_user_long(Arg, Count)
  Else DevIoctl := -25;
End;

Function InitIrq : LongInt; ModuleInit;
Var R, B : LongInt;
Begin
  Count := 0;
  Ops[3] := LongInt(@DevIoctl);
  Major := register_chrdev(241, 'irqmod', LongInt(@Ops[0]));
  If Major < 0 Then
  Begin
    InitIrq := Major;
    Exit;
  End;
  R := request_irq(8, LongInt(@Handler));
  If R < 0 Then
  Begin
    unregister_chrdev(Major);
    InitIrq := R;
    Exit;
  End;
  Port[$70] := $8A;
  Port[$71] := $26;
  Port[$70] := $8B;
  B := Port[$71];
  Port[$70] := $8B;
  Port[$71] := B Or $40;
  printk('irqmod : charge');
  InitIrq := 0;
End;

Procedure ExitIrq; ModuleExit;
Var B : LongInt;
Begin
  Port[$70] := $8B;
  B := Port[$71];
  Port[$70] := $8B;
  Port[$71] := B And $BF;
  Port[$70] := $0C;
  B := Port[$71];
  free_irq(8);
  unregister_chrdev(Major);
  printk('irqmod : decharge');
End;

Begin
End.
