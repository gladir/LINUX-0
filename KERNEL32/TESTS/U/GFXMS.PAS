{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2026
  @website(https://www.gladir.com/linux-0)
  @abstract(Target: LPC -3X)
  @description: GFXMS : souris (Intr 33h) et clavier (ReadKey) sous QEMU,
    pour GFXT.PY. Ecrit sur la sortie standard (port serie) la reponse de la
    fonction 00h, chaque changement de position ou de boutons avec l'heure en
    millisecondes, et chaque code de touche lu, pendant 25 secondes. }

Program GfxMs;

Uses Crt, Graph, Dos;

Var
  Gd, Gm : Integer;
  R : Registers;
  Lx, Ly, Lb, T0 : LongInt;

Begin
  Gd := Detect; Gm := 0;
  InitGraph(Gd, Gm, '');
  R.AX := 0;
  Intr($33, R);
  WriteLn('reset ax=', R.AX, ' bx=', R.BX);
  R.AX := 1;
  Intr($33, R);
  T0 := GetTickCount;
  Lx := -1; Ly := -1; Lb := -1;
  While GetTickCount - T0 < 25000 Do
  Begin
    R.AX := 3;
    Intr($33, R);
    If (R.CX <> Lx) Or (R.DX <> Ly) Or (R.BX <> Lb) Then
    Begin
      Lx := R.CX; Ly := R.DX; Lb := R.BX;
      WriteLn(GetTickCount - T0, ' x=', Lx, ' y=', Ly, ' b=', Lb);
    End;
    Delay(5);
    If KeyPressed Then WriteLn('key ', Ord(ReadKey));
  End;
  CloseGraph;
  WriteLn('fin');
End.
