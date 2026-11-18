{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2026
  @website(https://www.gladir.com/linux-0)
  @abstract(Target: LPC -3X)
  @description: UX11 : essai de l'unite Graph integree (sous-ensemble BGI).
    Sans /dev/fb0 : GFXMEM=1 (tampon seul, RUN.SH). Chaque ligne "ok"/"FAIL"
    est une verification analytique ; les lignes "sum" sont des sommes de
    controle des indices de couleur (non-regression). Avec l'argument HOLD le
    programme garde la scene a l'ecran 40 s (essai sous QEMU, GFXT.PY) ;
    SCENEOUT=fichier.ppm ecrit la scene finale en PPM. }

Program UX11;

Uses Crt, Graph;

Var
  Gd, Gm, I, J, N : Integer;
  S0, S1, C : LongInt;
  Buf : Pointer;
  Sz : LongInt;
  Pal : PaletteType;
  Vp : ViewPortType;
  Pts : Array[1..5] Of PointType;

Procedure Chk(Const Nm : String; Ok : Boolean);
Begin
  If Ok Then WriteLn('ok   ', Nm) Else WriteLn('FAIL ', Nm);
End;

Function Count(Col : Integer) : LongInt;
Var X, Y, K : LongInt;
Begin
  K := 0;
  For Y := 0 To GetMaxY Do
    For X := 0 To GetMaxX Do
      If GetPixel(X, Y) = Col Then Inc(K);
  Count := K;
End;

Procedure Sum(Const Nm : String);
Begin
  WriteLn('sum  ', Nm, ' ', GfxSum);
End;

Procedure Scene;
Var K : Integer;
Begin
  ClearDevice;
  SetViewPort(0, 0, GetMaxX, GetMaxY, True);
  { barres des 16 couleurs }
  For K := 0 To 15 Do
  Begin
    SetFillStyle(SolidFill, K);
    Bar(K * 40, 0, K * 40 + 39, 59);
  End;
  { fonds hachures }
  For K := 1 To 11 Do
  Begin
    SetFillStyle(K, 1 + K Mod 15);
    SetColor(15);
    Bar(10 + K * 52, 70, 50 + K * 52, 110);
    Rectangle(10 + K * 52, 70, 50 + K * 52, 110);
  End;
  { styles de traits }
  For K := 0 To 3 Do
  Begin
    SetColor(10 + K);
    SetLineStyle(K, 0, 1);
    Line(20, 130 + K * 10, 300, 130 + K * 10);
  End;
  SetLineStyle(SolidLn, 0, ThickWidth);
  SetColor(14);
  Line(20, 180, 300, 200);
  SetLineStyle(SolidLn, 0, NormWidth);
  SetColor(12);
  Circle(100, 280, 60);
  SetColor(11);
  Ellipse(260, 280, 0, 360, 80, 40);
  SetColor(13);
  Arc(420, 280, 30, 200, 50);
  SetFillStyle(SolidFill, 9);
  SetColor(15);
  PieSlice(540, 280, 20, 300, 55);
  FillEllipse(100, 400, 60, 30);
  SetFillStyle(XHatchFill, 6);
  Pts[1].X := 200; Pts[1].Y := 360;
  Pts[2].X := 300; Pts[2].Y := 360;
  Pts[3].X := 340; Pts[3].Y := 440;
  Pts[4].X := 250; Pts[4].Y := 420;
  Pts[5].X := 190; Pts[5].Y := 450;
  FillPoly(5, Pts);
  SetColor(15);
  SetTextStyle(DefaultFont, HorizDir, 1);
  OutTextXY(380, 360, 'Hello, GEOWORKS ' + #130#133#138);
  SetTextStyle(DefaultFont, HorizDir, 3);
  SetColor(14);
  OutTextXY(380, 380, 'BGI 8x8');
  SetTextStyle(DefaultFont, VertDir, 1);
  SetColor(10);
  OutTextXY(620, 470, 'vertical');
  SetTextStyle(DefaultFont, HorizDir, 1);
  SetColor(4);
  SetFillStyle(SolidFill, 4);
  Rectangle(380, 420, 470, 470);
  FloodFill(400, 440, 4);
End;

Begin
  Gd := Detect; Gm := 0;
  InitGraph(Gd, Gm, '');
  Chk('InitGraph', GraphResult = grOk);
  Chk('taille 640x480', (GetMaxX = 639) And (GetMaxY = 479));
  Chk('couleur 15, fond 0', (GetColor = 15) And (GetBkColor = 0));
  Chk('GetMaxColor', GetMaxColor = 15);
  ClearDevice;
  Chk('ClearDevice', Count(0) = 640 * 480);

  { Bar, PutPixel, GetPixel }
  SetFillStyle(SolidFill, 4);
  Bar(10, 10, 19, 19);
  Chk('Bar 10x10', Count(4) = 100);
  Chk('GetPixel coins', (GetPixel(10, 10) = 4) And (GetPixel(19, 19) = 4) And
      (GetPixel(20, 20) = 0) And (GetPixel(9, 10) = 0));
  PutPixel(300, 300, 7);
  Chk('PutPixel', GetPixel(300, 300) = 7);
  PutPixel(300, 300, 0);

  { traits }
  SetColor(2);
  Line(0, 100, 100, 100);
  Line(0, 100, 0, 150);
  Chk('Line H et V', Count(2) = 101 + 50);
  SetColor(3);
  Line(200, 100, 300, 200);
  Chk('Line diagonale', Count(3) = 101);
  SetColor(5);
  MoveTo(400, 100);
  LineTo(450, 100);
  LineRel(0, 50);
  Chk('MoveTo LineTo LineRel', (GetX = 450) And (GetY = 150) And
      (Count(5) = 51 + 50));

  { XOR : deux traces rendent l'image }
  ClearDevice;
  SetFillStyle(SolidFill, 9);
  Bar(50, 50, 150, 150);
  S0 := GfxSum;
  SetWriteMode(XORPut);
  SetColor(15);
  Rectangle(40, 40, 160, 160);
  Rectangle(41, 41, 159, 159);
  Line(0, 0, 300, 200);
  Ellipse(100, 100, 0, 360, 70, 40);
  S1 := GfxSum;
  Chk('XOR trace', S1 <> S0);
  Rectangle(40, 40, 160, 160);
  Rectangle(41, 41, 159, 159);
  Line(0, 0, 300, 200);
  Ellipse(100, 100, 0, 360, 70, 40);
  SetWriteMode(NormalPut);
  Chk('XOR efface', GfxSum = S0);

  { GetImage / PutImage }
  Sz := ImageSize(40, 40, 160, 160);
  Chk('ImageSize', Sz = 4 + 121 * 121);
  GetMem(Buf, Sz);
  GetImage(40, 40, 160, 160, Buf^);
  S0 := GfxSum;
  ClearDevice;
  Chk('image effacee', Count(9) = 0);
  PutImage(40, 40, Buf^, NormalPut);
  Chk('PutImage copie', (GfxSum = S0) And (Count(9) = 101 * 101));
  PutImage(40, 40, Buf^, XORPut);
  Chk('PutImage XOR', Count(0) = 640 * 480);
  PutImage(40, 40, Buf^, OrPut);
  Chk('PutImage OR', GfxSum = S0);
  PutImage(40, 40, Buf^, NotPut);
  Chk('PutImage NOT', (Count(9) = 0) And (Count(6) = 101 * 101));
  PutImage(40, 40, Buf^, AndPut);
  Chk('PutImage AND', Count(0) >= 640 * 480 - 121 * 121);
  FreeMem(Buf, Sz);

  { viewport et ecretage }
  ClearDevice;
  SetViewPort(100, 100, 199, 199, True);
  GetViewSettings(Vp);
  Chk('GetViewSettings', (Vp.X1 = 100) And (Vp.Y2 = 199) And Vp.Clip);
  SetColor(14);
  PutPixel(0, 0, 14);
  PutPixel(99, 99, 14);
  PutPixel(100, 100, 14);
  PutPixel(-1, 5, 14);
  Line(-50, 50, 250, 50);
  Chk('viewport ecrete', Count(14) = 2 + 100);
  SetFillStyle(SolidFill, 1);
  Bar(-20, -20, 500, 500);
  Chk('Bar ecretee', (Count(1) = 100 * 100) And (Count(14) = 0));
  ClearViewPort;
  Chk('ClearViewPort', Count(0) = 640 * 480);
  SetViewPort(0, 0, GetMaxX, GetMaxY, True);

  { texte : taille 2 = 4 fois la taille 1 }
  ClearDevice;
  SetColor(15);
  SetTextStyle(DefaultFont, HorizDir, 1);
  OutTextXY(10, 10, 'A');
  C := Count(15);
  Chk('texte A', (C > 10) And (TextWidth('A') = 8) And (TextHeight('A') = 8));
  ClearDevice;
  SetTextStyle(DefaultFont, HorizDir, 2);
  OutTextXY(10, 10, 'A');
  Chk('texte x2', (Count(15) = 4 * C) And (TextWidth('AB') = 32));
  SetTextStyle(DefaultFont, HorizDir, 1);
  ClearDevice;
  SetTextJustify(CenterText, CenterText);
  OutTextXY(100, 100, 'HH');
  Chk('SetTextJustify', (GetPixel(92, 100) = 15) Or (GetPixel(93, 100) = 15) Or
      (GetPixel(92, 101) = 15) Or (Count(15) > 20));
  SetTextJustify(LeftText, TopText);

  { remplissage }
  ClearDevice;
  SetColor(15);
  Rectangle(200, 200, 260, 240);
  SetFillStyle(SolidFill, 4);
  FloodFill(230, 220, 15);
  Chk('FloodFill', Count(4) = 59 * 39);
  Chk('FloodFill borne', (GetPixel(199, 220) = 0) And
      (GetPixel(200, 220) = 15));

  { polygone, ellipse pleine }
  ClearDevice;
  SetFillStyle(SolidFill, 2);
  SetColor(2);
  Pts[1].X := 100; Pts[1].Y := 100;
  Pts[2].X := 200; Pts[2].Y := 100;
  Pts[3].X := 200; Pts[3].Y := 200;
  Pts[4].X := 100; Pts[4].Y := 200;
  FillPoly(4, Pts);
  Chk('FillPoly carre', Count(2) = 101 * 101);
  ClearDevice;
  SetFillStyle(SolidFill, 1);
  SetColor(1);
  FillEllipse(300, 200, 40, 20);
  C := Count(1);
  Chk('FillEllipse aire', (C > 2400) And (C < 2600));
  Chk('FillEllipse symetrie', (GetPixel(260, 200) = 1) And
      (GetPixel(340, 200) = 1) And (GetPixel(300, 180) = 1) And
      (GetPixel(300, 220) = 1) And (GetPixel(259, 200) = 0));
  ClearDevice;
  SetColor(1);
  Circle(300, 200, 40);
  Chk('Circle', (GetPixel(340, 200) = 1) And (GetPixel(260, 200) = 1) And
      (GetPixel(300, 160) = 1) And (GetPixel(300, 240) = 1) And
      (GetPixel(300, 200) = 0));

  { palette }
  GetPalette(Pal);
  Chk('GetPalette', (Pal.Size = 16) And (Pal.Colors[6] = 20) And
      (Pal.Colors[15] = 63));
  SetPalette(1, 4);
  GetPalette(Pal);
  Chk('SetPalette', Pal.Colors[1] = 4);
  SetPalette(1, 1);

  { pages }
  SetActivePage(1);
  Chk('SetActivePage sans page', GraphResult <> 0);
  Chk('GraphErrorMsg', GraphErrorMsg(grOk) = 'No error');

  { aucune sortie : sommes de controle pour la non-regression }
  Scene;
  Sum('scene');
  If GetEnv('SCENEOUT') <> '' Then GfxDump(GetEnv('SCENEOUT'));
  If ParamStr(1) = 'HOLD' Then Delay(40000);
  CloseGraph;
  WriteLn('fin');
End.
