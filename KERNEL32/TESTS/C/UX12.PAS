{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2026
  @website(https://www.gladir.com/linux-0)
  @abstract(Target: LPC -3X)
  @description: UX12 : souris Intr 33h (unite Graph integree). RUN.SH donne
    dans MOUSEDEV un fichier vide qui tient lieu de /dev/input/mice : le
    programme y ajoute des paquets PS/2 de trois octets (octet d'etat avec
    bit 3, deplacement X, deplacement Y positif vers le haut) et verifie les
    reponses des fonctions 00h, 03h, 04h, 05h, 06h, 07h, 08h et 0Bh. }

Program UX12;

Uses Crt, Graph, Dos;

Var
  R : Registers;
  Fd : LongInt;
  Gd, Gm : Integer;

Procedure Chk(Const Nm : String; Ok : Boolean);
Begin
  If Ok Then WriteLn('ok   ', Nm) Else WriteLn('FAIL ', Nm);
End;

Procedure Pkt(B0, Dx, Dy : Integer);
Var P : Array[0..2] Of Byte;
Begin
  P[0] := B0; P[1] := Dx; P[2] := Dy;
  SysWrite(Fd, P, 3);
End;

Procedure Get;
Begin
  R.AX := 3;
  Intr($33, R);
End;

Begin
  Fd := SysOpen(GetEnv('MOUSEDEV'), O_WRONLY Or O_APPEND, 0);
  R.AX := 0;
  Intr($33, R);
  Chk('fonction 00h', (R.AX = $FFFF) And (R.BX = 3));
  Gd := Detect; Gm := 0;
  InitGraph(Gd, Gm, '');
  Get;
  Chk('position initiale', (R.CX = 320) And (R.DX = 240) And (R.BX = 0));
  Pkt($08, 10, 5);
  Get;
  Chk('deplacement +10 -5', (R.CX = 330) And (R.DX = 235));
  Pkt($18, 236, 0);
  Get;
  Chk('deplacement negatif', (R.CX = 310) And (R.DX = 235));
  Pkt($09, 0, 0);
  Get;
  Chk('bouton gauche', R.BX = 1);
  Pkt($0F, 0, 0);
  Get;
  Chk('trois boutons', R.BX = 7);
  Pkt($08, 0, 0);
  R.AX := 5; R.BX := 0;
  Intr($33, R);
  Chk('fonction 05h', (R.BX = 1) And (R.CX = 310) And (R.DX = 235));
  R.AX := 6; R.BX := 0;
  Intr($33, R);
  Chk('fonction 06h', (R.BX = 1) And (R.CX = 310) And (R.DX = 235));
  R.AX := 6; R.BX := 0;
  Intr($33, R);
  Chk('compteur remis a zero', R.BX = 0);
  R.AX := 11;
  Intr($33, R);
  Chk('fonction 0Bh', (R.CX = 65526) And (R.DX = 65531));
  R.AX := 7; R.CX := 100; R.DX := 200;
  Intr($33, R);
  Get;
  Chk('plage X (07h)', (R.CX = 200) And (R.DX = 235));
  R.AX := 8; R.CX := 50; R.DX := 60;
  Intr($33, R);
  Get;
  Chk('plage Y (08h)', (R.CX = 200) And (R.DX = 60));
  Pkt($18, 156, 0);
  Pkt($08, 0, 5);
  Get;
  Chk('butee basse', (R.CX = 100) And (R.DX = 55));
  R.AX := 4; R.CX := 150; R.DX := 58;
  Intr($33, R);
  Get;
  Chk('fonction 04h', (R.CX = 150) And (R.DX = 58));
  R.AX := 1;
  Intr($33, R);
  R.AX := 2;
  Intr($33, R);
  R.AX := 3;
  Chk('GetMouseState', MouseDriverFound);
  CloseGraph;
  WriteLn('fin');
End.
