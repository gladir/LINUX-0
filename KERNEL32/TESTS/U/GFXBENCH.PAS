{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2026
  @website(https://www.gladir.com/linux-0)
  @abstract(Target: LPC -3X)
  @description: GFXBENCH : cout d'un deplacement de souris (unite Graph).
    Reproduit la boucle d'evenements de GEOWORKS (KeyPressed, GetMouseState,
    Delay(4)) pendant 8 secondes. Argument SW : curseur dessine par le
    programme (GetImage/PutImage/PutPixel, comme GEOWORKS) ; HW : curseur de
    l'unite (Intr 33h fonction 01h). Affiche les compteurs de GfxStat
    (appels noyau de l'unite Graph et pixels ecrits), a diviser par le
    nombre de deplacements. GFXT.PY / RUNGFX.SH bench. }

Program GfxBench;

Uses Crt, Graph, Dos;

Const
  Shape : Array[0..16] Of String[12] = (
    '.           ', '..          ', '.#.         ', '.##.        ',
    '.###.       ', '.####.      ', '.#####.     ', '.######.    ',
    '.#######.   ', '.########.  ', '.#####.....', '.##.##.     ',
    '.#. .##.    ', '..  .##.    ', '.    .##.   ', '     .##.   ',
    '      ..    ');

Var
  Gd, Gm, I, J : Integer;
  R : Registers;
  X, Y, B, Lx, Ly, Mv, Loops, T0 : LongInt;
  Sw, Saved : Boolean;
  Buf : Pointer;
  Sz, Cx, Cy : LongInt;
  C : Char;

Procedure Erase;
Begin
  If Saved Then
  Begin
    SetViewPort(0, 0, GetMaxX, GetMaxY, True);
    PutImage(Cx, Cy, Buf^, NormalPut);
    Saved := False;
  End;
End;

Procedure Draw(PX, PY : LongInt);
Begin
  Erase;
  SetViewPort(0, 0, GetMaxX, GetMaxY, True);
  GetImage(PX, PY, PX + 11, PY + 16, Buf^);
  Cx := PX; Cy := PY; Saved := True;
  For J := 0 To 16 Do
    For I := 1 To 12 Do
    Begin
      C := Shape[J][I];
      If C = '#' Then PutPixel(PX + I - 1, PY + J, 0)
      Else If C = '.' Then PutPixel(PX + I - 1, PY + J, 15);
    End;
End;

Begin
  Sw := ParamStr(1) = 'SW';
  Gd := Detect; Gm := 0;
  InitGraph(Gd, Gm, '');
  SetFillStyle(SolidFill, 7);
  Bar(0, 0, GetMaxX, GetMaxY);
  SetFillStyle(XHatchFill, 1);
  Bar(100, 100, 400, 300);
  R.AX := 0;
  Intr($33, R);
  Sz := ImageSize(0, 0, 11, 16);
  GetMem(Buf, Sz);
  Saved := False;
  If Not Sw Then
  Begin
    R.AX := 1;
    Intr($33, R);
  End;
  GfxFlush;
  Delay(100);
  WriteLn('ready ', GetMaxX + 1, 'x', GetMaxY + 1);
  GfxStatReset;
  Lx := -1; Ly := -1; Mv := 0; Loops := 0;
  T0 := GetTickCount;
  While GetTickCount - T0 < 8000 Do
  Begin
    Inc(Loops);
    If KeyPressed Then C := ReadKey;
    GetMouseState(X, Y, B);
    If (X <> Lx) Or (Y <> Ly) Then
    Begin
      Inc(Mv);
      Lx := X; Ly := Y;
      If Sw Then Draw(X, Y);
    End;
    Delay(4);
  End;
  Write('stat moves=', Mv, ' loops=', Loops);
  For I := 0 To 13 Do Write(' s', I, '=', GfxStat(I));
  WriteLn;
  CloseGraph;
  WriteLn('fin');
End.
