{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2026
  @website(https://www.gladir.com/linux-0)
  @abstract(Target: LPC -3X)
  @description: GFXCUR0 : programme Graph qui n'appelle jamais Intr 33h :
    le curseur de l'unite doit etre affiche des InitGraph, au centre, et
    suivre la souris et changer de couleur chaque seconde (GFXT.PY, scenarios
    robust et prism). Argument : W fond blanc, K fond noir. Affiche les sources
    d'entree ouvertes. }

Program GfxCur0;

Uses Crt, Graph;

Var
  Gd, Gm : Integer;
  I : LongInt;

Begin
  Gd := Detect; Gm := 0;
  InitGraph(Gd, Gm, '');
  { fond : gris (defaut), W blanc pur, K noir }
  SetFillStyle(SolidFill, 7);
  If ParamStr(1) = 'W' Then SetFillStyle(SolidFill, 15);
  If ParamStr(1) = 'K' Then SetFillStyle(SolidFill, 0);
  Bar(0, 0, GetMaxX, GetMaxY);
  WriteLn('ready ', GetMaxX + 1, 'x', GetMaxY + 1, ' ', GfxSources);
  For I := 1 To 150 Do Delay(100);
  CloseGraph;
  WriteLn('fin');
End.
