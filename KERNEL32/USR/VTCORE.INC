{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2026
  @website(https://www.gladir.com/linux-0)
  @abstract(Target: LPC -3X)
  @description: VTCORE.INC : coeur d'un emulateur de terminal VT100/ANSI
      (sans dependance graphique ni pty : testable sur l'hote). Ecran de
      VtCols x VtRows cellules (au plus 160 x 60), 16 couleurs, gras,
      souligne, inverse, region de defilement, curseur, sauvegarde du
      curseur, ecran alternatif simple, historique de defilement
      (VT_SB lignes), reponses (DSR, DA) accumulees dans VtOut. Sequences :
      CR LF BS HT BEL ; ESC 7 8 D E M c ( ) ] ; CSI A B C D E F G H f d J K
      L M P @ X S T m r s u h l n c et leurs variantes ? (25 cursor, 7 wrap,
      1 touches curseur applicatives, 1049/47 ecran alternatif).
      Les octets UTF-8 sont decodes vers Latin-1 (autres : ?). Noms
      globaux prefixes Vt. }

Const
  VT_MC = 160;
  VT_MR = 60;
  VT_SB = 300;               { lignes d'historique }
  VF_UL = 1;  VF_REV = 2;  VF_BOLD = 4;

Var
  VtCols, VtRows : LongInt;
  VtCh : Array[0..VT_MC * VT_MR - 1] Of Byte;
  VtAt : Array[0..VT_MC * VT_MR - 1] Of Byte;     { fg | bg shl 4 }
  VtFl : Array[0..VT_MC * VT_MR - 1] Of Byte;
  VtDirty : Array[0..VT_MR - 1] Of Boolean;
  { historique }
  SbCh, SbAt, SbFl : Array[0..VT_SB * VT_MC - 1] Of Byte;
  SbN, SbHead : LongInt;                         { nombre de lignes, ecriture }
  { ecran principal sauvegarde pendant l'ecran alternatif }
  AltCh, AltAt, AltFl : Array[0..VT_MC * VT_MR - 1] Of Byte;
  VtAlt : Boolean;
  VtCx, VtCy, VtTop, VtBot : LongInt;
  VtSvX, VtSvY, VtSvAt, VtSvFl : LongInt;
  VtCurAt, VtCurFl : LongInt;                    { attributs courants }
  VtWrapPend, VtWrap, VtCurOn, VtAppKeys, VtOrigin : Boolean;
  VtTabs : Array[0..VT_MC - 1] Of Boolean;
  { analyseur }
  VtSt : LongInt;                                { 0 sol 1 ESC 2 CSI 3 OSC
                                                   4 ESC( 5 ignorer jusqu'a ST }
  VtPar : Array[0..15] Of LongInt;
  VtNPar : LongInt;
  VtPriv : Boolean;
  VtU8 : LongInt;                                { octets UTF-8 restants }
  VtU8c : LongInt;
  VtOut : String;                                { reponses vers le programme }
  VtBell : Boolean;
  VtLast : LongInt;                              { dernier caractere imprime }

Function VtIdx(X, Y : LongInt) : LongInt;
Begin
  VtIdx := Y * VT_MC + X;
End;

Procedure VtMarkAll;
Var Y : LongInt;
Begin
  For Y := 0 To VT_MR - 1 Do VtDirty[Y] := True;
End;

Procedure VtClearCells(X0, Y0, X1, Y1 : LongInt);
Var X, Y, I : LongInt;
Begin
  For Y := Y0 To Y1 Do
  Begin
    VtDirty[Y] := True;
    For X := X0 To X1 Do
    Begin
      I := VtIdx(X, Y);
      VtCh[I] := 32;
      VtAt[I] := (VtCurAt And $F0) Or 7;
      VtFl[I] := 0;
    End;
  End;
End;

Procedure VtReset;
Var X : LongInt;
Begin
  VtCurAt := 7;                  { blanc sur noir }
  VtCurFl := 0;
  VtClearCells(0, 0, VT_MC - 1, VT_MR - 1);
  VtCx := 0; VtCy := 0; VtTop := 0; VtBot := VtRows - 1;
  VtSvX := 0; VtSvY := 0; VtSvAt := 7; VtSvFl := 0;
  VtWrapPend := False; VtWrap := True; VtCurOn := True; VtAppKeys := False;
  VtOrigin := False;
  VtAlt := False;
  VtSt := 0; VtNPar := 0; VtPriv := False; VtU8 := 0;
  VtOut := '';
  VtBell := False;
  VtLast := 32;
  For X := 0 To VT_MC - 1 Do VtTabs[X] := (X Mod 8) = 0;
  VtMarkAll;
End;

Procedure VtInit(Cols, Rows : LongInt);
Begin
  If Cols > VT_MC Then Cols := VT_MC;
  If Rows > VT_MR Then Rows := VT_MR;
  If Cols < 20 Then Cols := 20;
  If Rows < 5 Then Rows := 5;
  VtCols := Cols;
  VtRows := Rows;
  SbN := 0;
  SbHead := 0;
  VtReset;
End;

{ nouvelle taille : conserve le contenu (coin haut gauche) }
Procedure VtResize(Cols, Rows : LongInt);
Begin
  If Cols > VT_MC Then Cols := VT_MC;
  If Rows > VT_MR Then Rows := VT_MR;
  If Cols < 20 Then Cols := 20;
  If Rows < 5 Then Rows := 5;
  VtCols := Cols;
  VtRows := Rows;
  If VtCx >= VtCols Then VtCx := VtCols - 1;
  If VtCy >= VtRows Then VtCy := VtRows - 1;
  VtTop := 0;
  VtBot := VtRows - 1;
  VtWrapPend := False;
  VtMarkAll;
End;

{ empile la ligne Y dans l'historique }
Procedure VtPushSb(Y : LongInt);
Var X, B, A : LongInt;
Begin
  B := SbHead * VT_MC;
  A := Y * VT_MC;
  For X := 0 To VT_MC - 1 Do
  Begin
    SbCh[B + X] := VtCh[A + X];
    SbAt[B + X] := VtAt[A + X];
    SbFl[B + X] := VtFl[A + X];
  End;
  SbHead := (SbHead + 1) Mod VT_SB;
  If SbN < VT_SB Then Inc(SbN);
End;

{ fait defiler la region Top..Bot d'une ligne vers le haut }
Procedure VtScrollUp(Top, Bot : LongInt);
Var Y, X, A, B : LongInt;
Begin
  If (Top = 0) And (Not VtAlt) Then VtPushSb(0);
  For Y := Top To Bot - 1 Do
  Begin
    A := VtIdx(0, Y);
    B := VtIdx(0, Y + 1);
    For X := 0 To VT_MC - 1 Do
    Begin
      VtCh[A + X] := VtCh[B + X];
      VtAt[A + X] := VtAt[B + X];
      VtFl[A + X] := VtFl[B + X];
    End;
    VtDirty[Y] := True;
  End;
  VtClearCells(0, Bot, VT_MC - 1, Bot);
End;

Procedure VtScrollDown(Top, Bot : LongInt);
Var Y, X, A, B : LongInt;
Begin
  For Y := Bot DownTo Top + 1 Do
  Begin
    A := VtIdx(0, Y);
    B := VtIdx(0, Y - 1);
    For X := 0 To VT_MC - 1 Do
    Begin
      VtCh[A + X] := VtCh[B + X];
      VtAt[A + X] := VtAt[B + X];
      VtFl[A + X] := VtFl[B + X];
    End;
    VtDirty[Y] := True;
  End;
  VtClearCells(0, Top, VT_MC - 1, Top);
End;

Procedure VtLineFeed;
Begin
  If VtCy = VtBot Then VtScrollUp(VtTop, VtBot)
  Else If VtCy < VtRows - 1 Then Inc(VtCy);
End;

Procedure VtRevIndex;
Begin
  If VtCy = VtTop Then VtScrollDown(VtTop, VtBot)
  Else If VtCy > 0 Then Dec(VtCy);
End;

Procedure VtPutCell(C : LongInt);
Var I : LongInt;
Begin
  If VtWrapPend And VtWrap Then
  Begin
    VtCx := 0;
    VtLineFeed;
  End;
  VtWrapPend := False;
  I := VtIdx(VtCx, VtCy);
  VtCh[I] := C;
  VtAt[I] := VtCurAt;
  VtFl[I] := VtCurFl;
  VtDirty[VtCy] := True;
  VtLast := C;
  If VtCx < VtCols - 1 Then Inc(VtCx)
  Else VtWrapPend := True;
End;

Function VtPar0(N, Def : LongInt) : LongInt;
Begin
  If (N >= VtNPar) Or (VtPar[N] <= 0) Then VtPar0 := Def
  Else VtPar0 := VtPar[N];
End;

Procedure VtSetXY(X, Y : LongInt);
Begin
  If X < 0 Then X := 0;
  If X >= VtCols Then X := VtCols - 1;
  If VtOrigin Then
  Begin
    Y := Y + VtTop;
    If Y < VtTop Then Y := VtTop;
    If Y > VtBot Then Y := VtBot;
  End
  Else
  Begin
    If Y < 0 Then Y := 0;
    If Y >= VtRows Then Y := VtRows - 1;
  End;
  VtCx := X;
  VtCy := Y;
  VtWrapPend := False;
End;

Procedure VtEraseLine(Mode : LongInt);
Begin
  If Mode = 0 Then VtClearCells(VtCx, VtCy, VtCols - 1, VtCy)
  Else If Mode = 1 Then VtClearCells(0, VtCy, VtCx, VtCy)
  Else VtClearCells(0, VtCy, VtCols - 1, VtCy);
End;

Procedure VtEraseDisplay(Mode : LongInt);
Begin
  If Mode = 0 Then
  Begin
    VtClearCells(VtCx, VtCy, VtCols - 1, VtCy);
    If VtCy < VtRows - 1 Then VtClearCells(0, VtCy + 1, VtCols - 1, VtRows - 1);
  End
  Else If Mode = 1 Then
  Begin
    If VtCy > 0 Then VtClearCells(0, 0, VtCols - 1, VtCy - 1);
    VtClearCells(0, VtCy, VtCx, VtCy);
  End
  Else VtClearCells(0, 0, VtCols - 1, VtRows - 1);
End;

{ couleur 256 -> 16 }
Function VtMap256(N : LongInt) : LongInt;
Var R, G, B, V : LongInt;
Begin
  If N < 16 Then
  Begin
    VtMap256 := N;
    Exit;
  End;
  If N >= 232 Then
  Begin
    V := (N - 232) * 10 + 8;
    If V < 64 Then VtMap256 := 0
    Else If V < 128 Then VtMap256 := 8
    Else If V < 200 Then VtMap256 := 7
    Else VtMap256 := 15;
    Exit;
  End;
  N := N - 16;
  R := (N Div 36) * 2 Div 5;
  G := ((N Div 6) Mod 6) * 2 Div 5;
  B := (N Mod 6) * 2 Div 5;
  V := (R And 1) Or ((G And 1) Shl 1) Or ((B And 1) Shl 2);
  If (R + G + B) >= 4 Then V := V + 8;
  If V = 0 Then V := 8;
  VtMap256 := V;
End;

{ attributs de graphisme (SGR) }
Procedure VtSgr;
Var I, P, Fg, Bg : LongInt;
Begin
  If VtNPar = 0 Then
  Begin
    VtNPar := 1;
    VtPar[0] := 0;
  End;
  Fg := VtCurAt And 15;
  Bg := (VtCurAt Shr 4) And 15;
  I := 0;
  While I < VtNPar Do
  Begin
    P := VtPar[I];
    If P <= 0 Then
    Begin
      Fg := 7; Bg := 0; VtCurFl := 0;
    End
    Else If P = 1 Then VtCurFl := VtCurFl Or VF_BOLD
    Else If P = 4 Then VtCurFl := VtCurFl Or VF_UL
    Else If P = 7 Then VtCurFl := VtCurFl Or VF_REV
    Else If P = 22 Then VtCurFl := VtCurFl And Not VF_BOLD
    Else If P = 24 Then VtCurFl := VtCurFl And Not VF_UL
    Else If P = 27 Then VtCurFl := VtCurFl And Not VF_REV
    Else If (P >= 30) And (P <= 37) Then Fg := P - 30
    Else If P = 39 Then Fg := 7
    Else If (P >= 40) And (P <= 47) Then Bg := P - 40
    Else If P = 49 Then Bg := 0
    Else If (P >= 90) And (P <= 97) Then Fg := P - 90 + 8
    Else If (P >= 100) And (P <= 107) Then Bg := P - 100 + 8
    Else If (P = 38) Or (P = 48) Then
    Begin
      If (I + 2 < VtNPar) And (VtPar[I + 1] = 5) Then
      Begin
        If P = 38 Then Fg := VtMap256(VtPar[I + 2])
        Else Bg := VtMap256(VtPar[I + 2]);
        I := I + 2;
      End
      Else If (I + 4 < VtNPar) And (VtPar[I + 1] = 2) Then
      Begin
        Fg := 7;
        I := I + 4;
      End;
    End;
    Inc(I);
  End;
  VtCurAt := Fg Or (Bg Shl 4);
End;

Procedure VtDecSet(On : Boolean);
Var I, P : LongInt;
Begin
  For I := 0 To VtNPar - 1 Do
  Begin
    P := VtPar[I];
    If P = 25 Then VtCurOn := On
    Else If P = 7 Then VtWrap := On
    Else If P = 1 Then VtAppKeys := On
    Else If P = 6 Then
    Begin
      VtOrigin := On;
      VtSetXY(0, 0);
    End
    Else If (P = 1049) Or (P = 47) Or (P = 1047) Then
    Begin
      If On And (Not VtAlt) Then
      Begin
        Move(VtCh, AltCh, SizeOf(VtCh));
        Move(VtAt, AltAt, SizeOf(VtAt));
        Move(VtFl, AltFl, SizeOf(VtFl));
        VtAlt := True;
        VtClearCells(0, 0, VT_MC - 1, VT_MR - 1);
        VtCx := 0; VtCy := 0;
      End
      Else If (Not On) And VtAlt Then
      Begin
        Move(AltCh, VtCh, SizeOf(VtCh));
        Move(AltAt, VtAt, SizeOf(VtAt));
        Move(AltFl, VtFl, SizeOf(VtFl));
        VtAlt := False;
        VtMarkAll;
      End;
    End;
  End;
End;

Function NumStr(V : LongInt) : String;
Var S : String;
Begin
  Str(V, S);
  NumStr := S;
End;

Procedure VtCsi(F : Char);
Var N, I, X, Y : LongInt;
Begin
  If VtPriv Then
  Begin
    If F = 'h' Then VtDecSet(True)
    Else If F = 'l' Then VtDecSet(False);
    Exit;
  End;
  Case F Of
    'A' : VtSetXY(VtCx, VtCy - VtPar0(0, 1));
    'B', 'e' : VtSetXY(VtCx, VtCy + VtPar0(0, 1));
    'C', 'a' : VtSetXY(VtCx + VtPar0(0, 1), VtCy);
    'D' : VtSetXY(VtCx - VtPar0(0, 1), VtCy);
    'E' : VtSetXY(0, VtCy + VtPar0(0, 1));
    'F' : VtSetXY(0, VtCy - VtPar0(0, 1));
    'G', '`' : VtSetXY(VtPar0(0, 1) - 1, VtCy);
    'd' : VtSetXY(VtCx, VtPar0(0, 1) - 1);
    'H', 'f' : VtSetXY(VtPar0(1, 1) - 1, VtPar0(0, 1) - 1);
    'J' : VtEraseDisplay(VtPar0(0, 0));
    'K' : VtEraseLine(VtPar0(0, 0));
    'L' :
      If (VtCy >= VtTop) And (VtCy <= VtBot) Then
        For I := 1 To VtPar0(0, 1) Do VtScrollDown(VtCy, VtBot);
    'M' :
      If (VtCy >= VtTop) And (VtCy <= VtBot) Then
        For I := 1 To VtPar0(0, 1) Do
        Begin
          { sans historique : copie directe }
          For Y := VtCy To VtBot - 1 Do
            For X := 0 To VT_MC - 1 Do
            Begin
              VtCh[VtIdx(X, Y)] := VtCh[VtIdx(X, Y + 1)];
              VtAt[VtIdx(X, Y)] := VtAt[VtIdx(X, Y + 1)];
              VtFl[VtIdx(X, Y)] := VtFl[VtIdx(X, Y + 1)];
            End;
          For Y := VtCy To VtBot Do VtDirty[Y] := True;
          VtClearCells(0, VtBot, VT_MC - 1, VtBot);
        End;
    'P' :
      Begin
        N := VtPar0(0, 1);
        If N > VtCols - VtCx Then N := VtCols - VtCx;
        For X := VtCx To VtCols - 1 - N Do
        Begin
          VtCh[VtIdx(X, VtCy)] := VtCh[VtIdx(X + N, VtCy)];
          VtAt[VtIdx(X, VtCy)] := VtAt[VtIdx(X + N, VtCy)];
          VtFl[VtIdx(X, VtCy)] := VtFl[VtIdx(X + N, VtCy)];
        End;
        VtClearCells(VtCols - N, VtCy, VtCols - 1, VtCy);
      End;
    '@' :
      Begin
        N := VtPar0(0, 1);
        If N > VtCols - VtCx Then N := VtCols - VtCx;
        For X := VtCols - 1 DownTo VtCx + N Do
        Begin
          VtCh[VtIdx(X, VtCy)] := VtCh[VtIdx(X - N, VtCy)];
          VtAt[VtIdx(X, VtCy)] := VtAt[VtIdx(X - N, VtCy)];
          VtFl[VtIdx(X, VtCy)] := VtFl[VtIdx(X - N, VtCy)];
        End;
        VtClearCells(VtCx, VtCy, VtCx + N - 1, VtCy);
      End;
    'X' :
      Begin
        N := VtPar0(0, 1);
        If VtCx + N > VtCols Then N := VtCols - VtCx;
        VtClearCells(VtCx, VtCy, VtCx + N - 1, VtCy);
      End;
    'S' : For I := 1 To VtPar0(0, 1) Do VtScrollUp(VtTop, VtBot);
    'T' : For I := 1 To VtPar0(0, 1) Do VtScrollDown(VtTop, VtBot);
    'm' : VtSgr;
    'r' :
      Begin
        Y := VtPar0(0, 1) - 1;
        X := VtPar0(1, VtRows) - 1;
        If (Y >= 0) And (X > Y) And (X < VtRows) Then
        Begin
          VtTop := Y;
          VtBot := X;
        End
        Else
        Begin
          VtTop := 0;
          VtBot := VtRows - 1;
        End;
        VtSetXY(0, 0);
      End;
    's' : Begin VtSvX := VtCx; VtSvY := VtCy; End;
    'u' : VtSetXY(VtSvX, VtSvY);
    'n' :
      Begin
        If VtPar0(0, 0) = 6 Then
          VtOut := VtOut + #27'[' + NumStr(VtCy + 1) + ';' + NumStr(VtCx + 1) +
                   'R'
        Else If VtPar0(0, 0) = 5 Then VtOut := VtOut + #27'[0n';
      End;
    'c' : VtOut := VtOut + #27'[?1;2c';
  End;
End;

{ un octet de la sortie du programme }
Procedure VtPut(B : Byte);
Var C : LongInt;
Begin
  { UTF-8 }
  If VtU8 > 0 Then
  Begin
    If (B And $C0) = $80 Then
    Begin
      VtU8c := (VtU8c Shl 6) Or (B And $3F);
      Dec(VtU8);
      If VtU8 = 0 Then
      Begin
        C := VtU8c;
        If C > 255 Then
        Begin
          If (C >= $2500) And (C <= $257F) Then
          Begin
            If (C = $2500) Or (C = $2501) Then C := 45
            Else If (C = $2502) Or (C = $2503) Then C := 124
            Else C := 43;
          End
          Else If C = $2022 Then C := 183
          Else C := 63;
        End;
        VtPutCell(C);
      End;
      Exit;
    End;
    VtU8 := 0;
  End;
  If VtSt = 0 Then
  Begin
    If B >= $C2 Then
    Begin
      If B < $E0 Then
      Begin
        VtU8 := 1;
        VtU8c := B And $1F;
      End
      Else If B < $F0 Then
      Begin
        VtU8 := 2;
        VtU8c := B And $0F;
      End
      Else
      Begin
        VtU8 := 3;
        VtU8c := B And $07;
      End;
      Exit;
    End;
    Case B Of
      7 : VtBell := True;
      8 : If VtCx > 0 Then
          Begin
            Dec(VtCx);
            VtWrapPend := False;
          End;
      9 : Begin
            C := VtCx + 1;
            While (C < VtCols - 1) And (Not VtTabs[C]) Do Inc(C);
            If C > VtCols - 1 Then C := VtCols - 1;
            VtCx := C;
            VtWrapPend := False;
          End;
      10, 11, 12 : Begin
                     VtLineFeed;
                     VtWrapPend := False;
                   End;
      13 : Begin
             VtCx := 0;
             VtWrapPend := False;
           End;
      27 : VtSt := 1;
      14, 15 : ;
    Else
      If B >= 32 Then VtPutCell(B);
    End;
    Exit;
  End;
  If VtSt = 1 Then
  Begin
    VtSt := 0;
    Case Chr(B) Of
      '[' : Begin
              VtSt := 2;
              VtNPar := 0;
              VtPriv := False;
              FillChar(VtPar, SizeOf(VtPar), 0);
            End;
      ']' : VtSt := 3;
      '(', ')', '*', '+' : VtSt := 4;
      'P', '_', '^', 'X' : VtSt := 5;
      '7' : Begin VtSvX := VtCx; VtSvY := VtCy; VtSvAt := VtCurAt;
                  VtSvFl := VtCurFl; End;
      '8' : Begin VtSetXY(VtSvX, VtSvY); VtCurAt := VtSvAt;
                  VtCurFl := VtSvFl; End;
      'D' : VtLineFeed;
      'E' : Begin VtCx := 0; VtLineFeed; End;
      'M' : VtRevIndex;
      'H' : VtTabs[VtCx] := True;
      'c' : VtReset;
      '=', '>' : ;
    End;
    Exit;
  End;
  If VtSt = 2 Then
  Begin
    If (B >= 48) And (B <= 57) Then
    Begin
      If VtNPar = 0 Then VtNPar := 1;
      If VtNPar <= 16 Then
        VtPar[VtNPar - 1] := VtPar[VtNPar - 1] * 10 + B - 48;
    End
    Else If B = 59 Then
    Begin
      If VtNPar = 0 Then VtNPar := 1;
      If VtNPar < 16 Then Inc(VtNPar);
    End
    Else If (B = 63) Or (B = 62) Or (B = 61) Then VtPriv := True
    Else If (B >= 64) And (B <= 126) Then
    Begin
      VtSt := 0;
      VtCsi(Chr(B));
    End
    Else If (B < 32) Then
    Begin
      { caracteres de controle dans une sequence : executes }
      If B = 8 Then
        If VtCx > 0 Then Dec(VtCx);
      If B = 10 Then VtLineFeed;
      If B = 13 Then VtCx := 0;
    End;
    Exit;
  End;
  If VtSt = 3 Then
  Begin
    If B = 7 Then VtSt := 0
    Else If B = 27 Then VtSt := 5;
    Exit;
  End;
  If VtSt = 4 Then
  Begin
    VtSt := 0;
    Exit;
  End;
  If VtSt = 5 Then
  Begin
    If (B = 92) Or (B = 7) Then VtSt := 0;
    Exit;
  End;
End;

Procedure VtWriteStr(Const S : String);
Var I : LongInt;
Begin
  For I := 1 To Length(S) Do VtPut(Ord(S[I]));
End;

{ octets a envoyer au programme pour une touche : K = code de INPUT.INC
  (touche ordinaire 32..255, K_ENTER..., 300+ : touches speciales) }
Function VtKeyStr(K : LongInt; Ctrl, Alt : Boolean) : String;
Var S : String; Pre : String;
Begin
  S := '';
  If Alt Then Pre := #27 Else Pre := '';
  If (K >= 32) And (K < 256) Then
  Begin
    If Ctrl And (K >= 64) And (K < 128) Then S := Chr(K And 31)
    Else If Ctrl And (K = 32) Then S := #0
    Else If K < 128 Then S := Chr(K)
    Else If K < 256 Then S := Chr($C0 Or (K Shr 6)) + Chr($80 Or (K And $3F));
    VtKeyStr := Pre + S;
    Exit;
  End;
  Case K Of
    13 : S := #13;
    9 : S := #9;
    27 : S := #27;
    8 : S := #127;
    300 : S := #27'[Z';
    301 : If VtAppKeys Then S := #27'OA' Else S := #27'[A';
    302 : If VtAppKeys Then S := #27'OB' Else S := #27'[B';
    303 : If VtAppKeys Then S := #27'OD' Else S := #27'[D';
    304 : If VtAppKeys Then S := #27'OC' Else S := #27'[C';
    305 : S := #27'[H';
    306 : S := #27'[F';
    307 : S := #27'[5~';
    308 : S := #27'[6~';
    309 : S := #27'[3~';
    310 : S := #27'[2~';
    311 : S := #27'OP';
    312 : S := #27'OQ';
    313 : S := #27'OR';
    314 : S := #27'OS';
    315 : S := #27'[15~';
    316 : S := #27'[17~';
    317 : S := #27'[18~';
    318 : S := #27'[19~';
    319 : S := #27'[20~';
    320 : S := #27'[21~';
    321 : S := #27'[23~';
    322 : S := #27'[24~';
  Else
    If (K >= 1) And (K < 32) Then S := Chr(K);
  End;
  If Ctrl And (K >= 1) And (K < 32) Then S := Chr(K);
  VtKeyStr := Pre + S;
End;

{ texte de la ligne Y de l'ecran (sans espaces de fin) : essais }
Function VtRowText(Y : LongInt) : String;
Var X, E : LongInt; S : String;
Begin
  S := '';
  E := VtCols - 1;
  While (E >= 0) And (VtCh[VtIdx(E, Y)] = 32) Do Dec(E);
  For X := 0 To E Do S := S + Chr(VtCh[VtIdx(X, Y)]);
  VtRowText := S;
End;

{ ligne N de l'historique (0 = la plus recente) dans VtSbRow ; texte }
Function VtSbText(N : LongInt) : String;
Var B, X, E : LongInt; S : String;
Begin
  S := '';
  If (N < 0) Or (N >= SbN) Then
  Begin
    VtSbText := S;
    Exit;
  End;
  B := ((SbHead - 1 - N + VT_SB * 2) Mod VT_SB) * VT_MC;
  E := VtCols - 1;
  While (E >= 0) And (SbCh[B + E] = 32) Do Dec(E);
  For X := 0 To E Do S := S + Chr(SbCh[B + X]);
  VtSbText := S;
End;
