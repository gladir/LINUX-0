{ hello : module de test de KERNEL32 (partie 36) : peripherique caractere
  /dev/hello (majeur 240), parametre count=N, symbole exporte hello_add }
Program Hello;

Const
  FoRead = 0; FoWrite = 1; FoIoctl = 3; FoOpen = 5; FoRelease = 6;

Var
  Ops     : Array[0..15] Of LongInt;
  Buf     : Array[0..255] Of Byte;
  Len, Writes, Major, Opens, Releases, Param : LongInt;

Procedure printk(Const S : String); External;
Procedure printk_int(Const S : String; V : LongInt); External;
Function register_chrdev(Major : LongInt; Const Name : String; Tab : LongInt)
    : LongInt; External;
Function unregister_chrdev(Major : LongInt) : LongInt; External;
Function copy_to_user(Dst, Src, N : LongInt) : LongInt; External;
Function copy_from_user(Dst, Src, N : LongInt) : LongInt; External;
Function file_get_pos(F : LongInt) : LongInt; External;
Function file_set_pos(F, P : LongInt) : LongInt; External;
Function module_param_int(Const Name : String; Def : LongInt) : LongInt;
    External;
Function put_user_long(Addr, V : LongInt) : LongInt; External;

Function hello_add(A, B : LongInt) : LongInt; Export;
Begin
  hello_add := A + B;
End;

Function DevRead(F, Ub, Cnt : LongInt) : LongInt;
Var P, N : LongInt;
Begin
  P := file_get_pos(F);
  If P >= Len Then
  Begin
    DevRead := 0;
    Exit;
  End;
  N := Len - P;
  If N > Cnt Then N := Cnt;
  If copy_to_user(Ub, LongInt(@Buf[P]), N) < 0 Then
  Begin
    DevRead := -14;
    Exit;
  End;
  file_set_pos(F, P + N);
  DevRead := N;
End;

Function DevWrite(F, Ub, Cnt : LongInt) : LongInt;
Var N : LongInt;
Begin
  N := Cnt;
  If N > 256 Then N := 256;
  If copy_from_user(LongInt(@Buf[0]), Ub, N) < 0 Then
  Begin
    DevWrite := -14;
    Exit;
  End;
  Len := N;
  Inc(Writes);
  DevWrite := N;
End;

Function DevIoctl(F, Cmd, Arg : LongInt) : LongInt;
Begin
  Case Cmd Of
    1 : DevIoctl := put_user_long(Arg, Writes);
    2 : DevIoctl := put_user_long(Arg, Param);
    3 : DevIoctl := put_user_long(Arg, Opens * 1000 + Releases);
  Else
    DevIoctl := -25;
  End;
End;

Function DevOpen(I, F : LongInt) : LongInt;
Begin
  Inc(Opens);
  DevOpen := 0;
End;

Function DevRelease(F : LongInt) : LongInt;
Begin
  Inc(Releases);
  DevRelease := 0;
End;

Function InitHello : LongInt; ModuleInit;
Begin
  Param := module_param_int('count', 3);
  Len := 0;
  Ops[FoRead] := LongInt(@DevRead);
  Ops[FoWrite] := LongInt(@DevWrite);
  Ops[FoIoctl] := LongInt(@DevIoctl);
  Ops[FoOpen] := LongInt(@DevOpen);
  Ops[FoRelease] := LongInt(@DevRelease);
  Major := register_chrdev(240, 'hello', LongInt(@Ops[0]));
  If Major < 0 Then
  Begin
    InitHello := Major;
    Exit;
  End;
  printk_int('hello : charge, majeur ', Major);
  InitHello := 0;
End;

Procedure ExitHello; ModuleExit;
Begin
  unregister_chrdev(Major);
  printk('hello : decharge');
End;

Begin
End.
