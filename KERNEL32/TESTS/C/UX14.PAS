{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2026
  @website(https://www.gladir.com/linux-0)
  @abstract(Target: LPC -3X)
  @description: UX14 : recopie par rectangles et souris absolue (unite Graph
    integree). 1) les zones modifiees sont recopiees separement (compteurs de
    GfxStat : lignes et pixels) et fusionnees quand elles se touchent ; 2)
    evenements evdev EV_ABS / EV_KEY / EV_SYN ajoutes au fichier MOUSEEVDEV
    (plage MOUSEABS=1000,2000, RUN.SH) : position mise a l'echelle de
    l'ecran, boutons BTN_LEFT et BTN_RIGHT. }

Program UX14;

Uses Crt, Graph, Dos;

Var
  R : Registers;
  Fd, Gd, Gm : LongInt;
  I : Integer;

Procedure Chk(Const Nm : String; Ok : Boolean);
Begin
  If Ok Then WriteLn('ok   ', Nm) Else WriteLn('FAIL ', Nm);
End;

Procedure Ev(Ty, Co, V : LongInt);
Var B : Array[0..3] Of LongInt;
Begin
  B[0] := 0; B[1] := 0;
  B[2] := Ty Or (Co Shl 16);
  B[3] := V;
  SysWrite(Fd, B, 16);
End;

Procedure Get;
Begin
  R.AX := 3;
  Intr($33, R);
End;

Begin
  Fd := SysOpen(GetEnv('MOUSEEVDEV'), O_WRONLY Or O_APPEND, 0);
  Gd := Detect; Gm := 0;
  InitGraph(Gd, Gm, '');
  SetFillStyle(SolidFill, 1);
  GfxFlush;
  GfxStatReset;
  Bar(10, 10, 19, 19);
  Bar(500, 400, 509, 409);
  GfxFlush;
  Chk('deux zones separees : 1 recopie', GfxStat(5) = 1);
  Chk('deux zones separees : 20 lignes, 200 pixels',
      (GfxStat(6) = 20) And (GfxStat(7) = 200));
  GfxStatReset;
  Bar(10, 10, 29, 29);
  Bar(25, 25, 40, 40);
  GfxFlush;
  Chk('deux zones qui se touchent : une seule', (GfxStat(6) = 31) And
      (GfxStat(7) = 31 * 31));
  GfxStatReset;
  For I := 0 To 11 Do Bar(I * 50, I * 30, I * 50 + 5, I * 30 + 5);
  GfxFlush;
  Chk('12 zones (8 au plus) : bien moins que l ecran',
      (GfxStat(7) > 12 * 36 - 1) And (GfxStat(7) < 100000));
  Chk('pas d image complete inutile', GfxStat(5) = 1);

  R.AX := 0;
  Intr($33, R);
  Chk('fonction 00h', R.AX = $FFFF);
  Ev(3, 0, 500);
  Ev(3, 1, 1000);
  Ev(0, 0, 0);
  Get;
  Chk('absolu milieu', (R.CX = 319) And (R.DX = 239) And (R.BX = 0));
  Ev(1, $110, 1);
  Ev(0, 0, 0);
  Get;
  Chk('BTN_LEFT', R.BX = 1);
  Ev(1, $110, 0);
  Ev(1, $111, 1);
  Ev(0, 0, 0);
  Get;
  Chk('BTN_RIGHT', R.BX = 2);
  Ev(1, $111, 0);
  Ev(3, 0, 1000);
  Ev(3, 1, 2000);
  Ev(0, 0, 0);
  Get;
  Chk('absolu coin bas droit', (R.CX = 639) And (R.DX = 479) And (R.BX = 0));
  Ev(3, 0, 0);
  Ev(3, 1, 0);
  Ev(0, 0, 0);
  Get;
  Chk('absolu coin haut gauche', (R.CX = 0) And (R.DX = 0));
  R.AX := 7; R.CX := 0; R.DX := 99;
  Intr($33, R);
  R.AX := 8; R.CX := 0; R.DX := 99;
  Intr($33, R);
  Ev(3, 0, 1000);
  Ev(3, 1, 2000);
  Ev(0, 0, 0);
  Get;
  Chk('plage 0..99 (fonctions 07h et 08h)', (R.CX = 99) And (R.DX = 99));
  Ev(3, 0, 5000);
  Ev(0, 0, 0);
  Get;
  Chk('valeur hors plage bornee', R.CX = 99);
  CloseGraph;
  WriteLn('fin');
End.
