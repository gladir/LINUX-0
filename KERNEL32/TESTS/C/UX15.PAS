{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2026
  @website(https://www.gladir.com/linux-0)
  @abstract(Target: LPC -3X)
  @description: UX15 : sources de la souris de l'unite Graph. Le relatif
    (MOUSEDEV, paquets PS/2) est toujours lu ; la source absolue (evdev,
    MOUSEEVDEV) ne prend la main qu'apres deux positions differentes, reste
    prioritaire GFXABSMS millisecondes (300 ici) apres sa derniere position
    nouvelle, puis le relatif reprend sans saut ; une source silencieuse ou
    qui repete la meme position ne bloque jamais le relatif. Le curseur est
    affiche des InitGraph, au centre de l'ecran. }

Program UX15;

Uses Crt, Graph, Dos;

Var
  R : Registers;
  Fr, Fa, Gd, Gm, P0, P1, P2, K : LongInt;

Procedure Chk(Const Nm : String; Ok : Boolean);
Begin
  If Ok Then WriteLn('ok   ', Nm) Else WriteLn('FAIL ', Nm);
End;

Procedure Rel(B0, Dx, Dy : Integer);
Var P : Array[0..2] Of Byte;
Begin
  P[0] := B0; P[1] := Dx; P[2] := Dy;
  SysWrite(Fr, P, 3);
End;

Procedure Ev(Ty, Co, V : LongInt);
Var B : Array[0..3] Of LongInt;
Begin
  B[0] := 0; B[1] := 0;
  B[2] := Ty Or (Co Shl 16);
  B[3] := V;
  SysWrite(Fa, B, 16);
End;

Procedure Get;
Begin
  R.AX := 3;
  Intr($33, R);
End;

Begin
  Fr := SysOpen(GetEnv('MOUSEDEV'), O_WRONLY Or O_APPEND, 0);
  Fa := SysOpen(GetEnv('MOUSEEVDEV'), O_WRONLY Or O_APPEND, 0);
  Gd := Detect; Gm := 0;
  InitGraph(Gd, Gm, '');
  Chk('curseur affiche des InitGraph', GfxCursorOn);
  Get;
  Chk('position initiale : centre', (R.CX = 320) And (R.DX = 240));
  Chk('sources ouvertes', (Pos('rel=', GfxSources) = 1) And
      (Pos('abs=aucun', GfxSources) = 0));
  { absolu silencieux : le relatif pilote }
  Rel($08, 10, 5);
  Get;
  Chk('absolu silencieux, relatif actif', (R.CX = 330) And (R.DX = 235));
  { une seule position : pas encore la main }
  Ev(3, 0, 500);
  Ev(0, 0, 0);
  Rel($08, 10, 0);
  Get;
  Chk('une position absolue ne suffit pas', (R.CX = 340) And (R.DX = 235));
  { deux positions differentes : l'absolu prend la main }
  Ev(3, 1, 1000);
  Ev(0, 0, 0);
  Get;
  Chk('absolu actif : position mise a l echelle', (R.CX = 319) And
      (R.DX = 239));
  Rel($08, 50, 0);
  Get;
  Chk('absolu recent : le relatif est ignore', (R.CX = 319) And (R.DX = 239));
  Ev(1, $110, 1);
  Ev(0, 0, 0);
  Get;
  Chk('bouton de la source absolue', R.BX = 1);
  Ev(1, $110, 0);
  Ev(0, 0, 0);
  { plus de position depuis plus de GFXABSMS : le relatif reprend }
  Delay(450);
  Rel($08, 10, 0);
  Get;
  Chk('absolu ancien : le relatif reprend sans saut', (R.CX = 329) And
      (R.DX = 239));
  { la meme position repetee ne redonne pas la main }
  Ev(3, 0, 500);
  Ev(0, 0, 0);
  Delay(450);
  Ev(3, 0, 500);
  Ev(0, 0, 0);
  Rel($08, 5, 0);
  Get;
  Chk('position absolue repetee : le relatif continue', R.CX = 334);
  { nouvelle position : l'absolu reprend }
  Ev(3, 0, 600);
  Ev(0, 0, 0);
  Get;
  Chk('nouvelle position absolue', (R.CX = 383) And (R.DX = 239));
  { couleur du curseur prisme : une teinte primaire par seconde, sans
    mouvement de la souris : rouge -> vert -> bleu (seconde murale mod 3) }
  P0 := GfxCursorPhase;
  K := 0;
  While (GfxCursorPhase = P0) And (K < 80) Do
  Begin
    Delay(100);
    Inc(K);
  End;
  P1 := GfxCursorPhase;
  K := 0;
  While (GfxCursorPhase = P1) And (K < 80) Do
  Begin
    Delay(100);
    Inc(K);
  End;
  P2 := GfxCursorPhase;
  Chk('couleur du curseur : change toute seule (sans souris)', P1 <> P0);
  Chk('couleur du curseur : cycle de 3 teintes', (P1 = (P0 + 1) Mod 3) And
      (P2 = (P1 + 1) Mod 3) And (P2 <> P0));
  R.AX := 2;
  Intr($33, R);
  Chk('fonction 02h masque le curseur', Not GfxCursorOn);
  R.AX := 1;
  Intr($33, R);
  Chk('fonction 01h le montre', GfxCursorOn);
  R.AX := 0;
  Intr($33, R);
  Chk('fonction 00h : curseur affiche', GfxCursorOn);
  CloseGraph;
  WriteLn('fin');
End.
