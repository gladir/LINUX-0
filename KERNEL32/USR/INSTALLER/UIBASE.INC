{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2026
  @website(https://www.gladir.com/linux-0)
  @abstract(Target: LPC -3X)
  @description: UIBASE.INC : couche d'affichage de l'assistant (graphique ET
      texte). L'ecran est une grille de cellules (Ui_Cols x Ui_Rows) ; chaque
      dessin porte un ROLE (couleurs). Mode graphique : cellule = police
      GFX.INC sur /dev/fb0 ; mode texte : sequences ANSI sur la console
      (repli, mode expert). Les chaines sont en Windows-1252 (un octet par
      caractere). Inclure apres GFX.INC.
}

Const
  R_BG = 0;  R_HEAD = 1;  R_HINT = 2;  R_WIN = 3;  R_TITLE = 4;
  R_FIELD = 5;  R_SEL = 6;  R_SELDIM = 7;  R_BTN = 8;  R_BTNF = 9;
  R_DIS = 10;  R_ERR = 11;  R_BAR = 12;  R_TROUGH = 13;  R_DLGT = 14;
  R_OK = 15;  R_DIM = 16;  R_BTNDEF = 17;  R_FERR = 18;

  { couleurs du theme graphique : premier plan, fond (-1 = transparent) }
  UiRoleFg : Array[0..18] Of LongInt = (
    $FFFFFF, $FFFFFF, $B9CCE6, $1E2430, $FFFFFF, $101820, $FFFFFF, $1E2430,
    $1E2430, $FFFFFF, $8A93A3, $B3261E, $2F6DB5, $D5DBE5, $FFFFFF, $1B7F3B,
    $5B6678, $1E2430, $5A0000);
  UiRoleBg : Array[0..18] Of LongInt = (
    $14406E, -1, -1, $F3F5F9, -1, $FFFFFF, $2F6DB5, $C5D3E8,
    -1, -1, $F3F5F9, $F3F5F9, $3C8DE0, $D5DBE5, -1, $F3F5F9,
    $F3F5F9, -1, $FFC9C9);

  { attributs texte : bits 0-2 premier plan, bit 3 gras, bits 4-6 fond }
  TxRoleAt : Array[0..18] Of Byte = (
    $4F, $4F, $47, $70, $4F, $60, $4F, $30, $70, $4F, $78, $71, $4F, $60,
    $4F, $72, $78, $70, $1F);

  UiBlue1 = $0B2A4A;
  UiBlue2 = $1B5694;

Var
  UiGfx : Boolean;              { True : graphique ; False : texte ANSI }
  UiCols, UiRows : LongInt;     { taille de la grille en cellules }
  UiOffX, UiOffY : LongInt;     { decalage pixel de la grille (graphique) }
  UiWx, UiWy, UiWw, UiWh : LongInt;    { fenetre principale (cellules) }
  UiCx, UiCy, UiCw, UiCh : LongInt;    { zone de contenu (cellules) }
  UiUtf8 : Boolean;             { le terminal affiche l'UTF-8 }
  UiCp437 : Boolean;            { console VGA : jeu de caracteres CP437 }
  TxCh, TxAt, TxShCh, TxShAt : Array[0..8191] Of Byte;
  TxOut : Array[0..65535] Of Byte;
  TxOutN : LongInt;
  TxCurX, TxCurY : LongInt;     { curseur materiel souhaite (-1 : cache) }
  TxShown : Boolean;
  UiOldTerm : TSysTermios;
  UiOutFd, UiTermFd : LongInt;
  UiHaveTerm : Boolean;

Const
  { Windows-1252, 128..159 -> Unicode }
  UiCp1252Hi : Array[0..31] Of Word = (
    $20AC, $003F, $201A, $0192, $201E, $2026, $2020, $2021, $02C6, $2030,
    $0160, $2039, $0152, $003F, $017D, $003F, $003F, $2018, $2019, $201C,
    $201D, $2022, $2013, $2014, $02DC, $2122, $0161, $203A, $0153, $003F,
    $017E, $0178);
  UiFold1 : String[96] = ' !cLoY|S"Ca<--R-o+23''uP.,1o>///?' +
    'AAAAAAACEEEEIIIIDNOOOOOxOUUUUYTs' + 'aaaaaaaceeeeiiiidnooooo/ouuuuyty';
  UiFold2 : String[32] = 'E?,f".++^%S<O?Z??''''""*--~Ts>o?zY';

{ ---- conversion de jeux de caracteres ---- }

{ un caractere Windows-1252 vers sa version ASCII (terminaux sans UTF-8) }
Function UiFoldCh(C : LongInt) : LongInt;
Begin
  If C < 128 Then UiFoldCh := C
  Else If C < 160 Then UiFoldCh := Ord(UiFold2[C - 127])
  Else UiFoldCh := Ord(UiFold1[C - 159]);
End;

{ Windows-1252 -> CP437 (console VGA du noyau) ; 0 si le caractere n'existe
  pas }
Function UiToCp437(C : LongInt) : LongInt;
Begin
  Case C Of
    199 : UiToCp437 := $80;  252 : UiToCp437 := $81;  233 : UiToCp437 := $82;
    226 : UiToCp437 := $83;  228 : UiToCp437 := $84;  224 : UiToCp437 := $85;
    229 : UiToCp437 := $86;  231 : UiToCp437 := $87;  234 : UiToCp437 := $88;
    235 : UiToCp437 := $89;  232 : UiToCp437 := $8A;  239 : UiToCp437 := $8B;
    238 : UiToCp437 := $8C;  236 : UiToCp437 := $8D;  196 : UiToCp437 := $8E;
    197 : UiToCp437 := $8F;  201 : UiToCp437 := $90;  230 : UiToCp437 := $91;
    198 : UiToCp437 := $92;  244 : UiToCp437 := $93;  246 : UiToCp437 := $94;
    242 : UiToCp437 := $95;  251 : UiToCp437 := $96;  249 : UiToCp437 := $97;
    255 : UiToCp437 := $98;  214 : UiToCp437 := $99;  220 : UiToCp437 := $9A;
    162 : UiToCp437 := $9B;  163 : UiToCp437 := $9C;  165 : UiToCp437 := $9D;
    225 : UiToCp437 := $A0;  237 : UiToCp437 := $A1;  243 : UiToCp437 := $A2;
    250 : UiToCp437 := $A3;  241 : UiToCp437 := $A4;  209 : UiToCp437 := $A5;
    170 : UiToCp437 := $A6;  186 : UiToCp437 := $A7;  191 : UiToCp437 := $A8;
    172 : UiToCp437 := $AA;  189 : UiToCp437 := $AB;  188 : UiToCp437 := $AC;
    161 : UiToCp437 := $AD;  171 : UiToCp437 := $AE;  187 : UiToCp437 := $AF;
    223 : UiToCp437 := $E1;  181 : UiToCp437 := $E6;  177 : UiToCp437 := $F1;
    176 : UiToCp437 := $F8;  183 : UiToCp437 := $FA;  178 : UiToCp437 := $FD;
  Else
    UiToCp437 := 0;
  End;
End;

{ chaine UTF-8 -> Windows-1252 (caracteres inconnus : ?) }
Function UiFromU8(Const S : String) : String;
Var I, C, C2, U, K : LongInt; R : String;
Begin
  R := '';
  I := 1;
  While I <= Length(S) Do
  Begin
    C := Ord(S[I]);
    If C < 128 Then
    Begin
      R := R + Chr(C);
      Inc(I);
    End
    Else If (C >= $C2) And (C < $E0) And (I < Length(S)) Then
    Begin
      C2 := Ord(S[I + 1]);
      U := ((C And $1F) Shl 6) Or (C2 And $3F);
      If U < 256 Then R := R + Chr(U)
      Else
      Begin
        K := 0;
        While (K < 32) And (UiCp1252Hi[K] <> U) Do Inc(K);
        If K < 32 Then R := R + Chr(128 + K) Else R := R + '?';
      End;
      I := I + 2;
    End
    Else If (C >= $E0) And (C < $F0) And (I + 1 < Length(S)) Then
    Begin
      U := ((C And $0F) Shl 12) Or ((Ord(S[I + 1]) And $3F) Shl 6) Or
           (Ord(S[I + 2]) And $3F);
      K := 0;
      While (K < 32) And (UiCp1252Hi[K] <> U) Do Inc(K);
      If K < 32 Then R := R + Chr(128 + K) Else R := R + '?';
      I := I + 3;
    End
    Else
    Begin
      R := R + '?';
      Inc(I);
    End;
  End;
  UiFromU8 := R;
End;

{ Windows-1252 -> UTF-8 (fichiers du systeme installe) }
Function UiToU8(Const S : String) : String;
Var I, C, U : LongInt; R : String;
Begin
  R := '';
  For I := 1 To Length(S) Do
  Begin
    C := Ord(S[I]);
    If C < 128 Then R := R + Chr(C)
    Else
    Begin
      If C < 160 Then U := UiCp1252Hi[C - 128] Else U := C;
      If U < 2048 Then
        R := R + Chr($C0 Or (U Shr 6)) + Chr($80 Or (U And $3F))
      Else
        R := R + Chr($E0 Or (U Shr 12)) + Chr($80 Or ((U Shr 6) And $3F)) +
             Chr($80 Or (U And $3F));
    End;
  End;
  UiToU8 := R;
End;

{ ASCII pur (noms de fichiers, machine, utilisateur) }
Function UiAscii(Const S : String) : String;
Var I : LongInt; R : String;
Begin
  R := '';
  For I := 1 To Length(S) Do R := R + Chr(UiFoldCh(Ord(S[I])));
  UiAscii := R;
End;

{ ---- sortie texte (ANSI) ---- }

Procedure TxFlushOut;
Var Done, R : LongInt;
Begin
  Done := 0;
  While Done < TxOutN Do
  Begin
    R := SysWrite(UiOutFd, TxOut[Done], TxOutN - Done);
    If R <= 0 Then Break;
    Done := Done + R;
  End;
  TxOutN := 0;
End;

Procedure TxPutB(B : LongInt);
Begin
  If TxOutN >= 65000 Then TxFlushOut;
  TxOut[TxOutN] := B;
  Inc(TxOutN);
End;

Procedure TxPutS(Const S : String);
Var I : LongInt;
Begin
  For I := 1 To Length(S) Do TxPutB(Ord(S[I]));
End;

Procedure TxPutNum(V : LongInt);
Var S : String;
Begin
  Str(V, S);
  TxPutS(S);
End;

Procedure TxPutCh(C : LongInt);
Var U : LongInt;
Begin
  If C < 32 Then C := 32;
  If C < 128 Then TxPutB(C)
  Else If UiCp437 And (UiToCp437(C) <> 0) Then TxPutB(UiToCp437(C))
  Else If UiUtf8 Then
  Begin
    If C < 160 Then U := UiCp1252Hi[C - 128] Else U := C;
    If U < 2048 Then
    Begin
      TxPutB($C0 Or (U Shr 6));
      TxPutB($80 Or (U And $3F));
    End
    Else
    Begin
      TxPutB($E0 Or (U Shr 12));
      TxPutB($80 Or ((U Shr 6) And $3F));
      TxPutB($80 Or (U And $3F));
    End;
  End
  Else TxPutB(UiFoldCh(C));
End;

Procedure TxAttr(A : LongInt);
Begin
  TxPutS(#27'[0');
  If (A And 8) <> 0 Then TxPutS(';1');
  TxPutS(';3'); TxPutNum(A And 7);
  TxPutS(';4'); TxPutNum((A Shr 4) And 7);
  TxPutS('m');
End;

Procedure TxGoto(X, Y : LongInt);
Begin
  TxPutS(#27'['); TxPutNum(Y + 1); TxPutS(';'); TxPutNum(X + 1);
  TxPutS('H');
End;

{ recopie les cellules modifiees vers le terminal }
Procedure TxFlush;
Var X, Y, I, A, LastA, LastI : LongInt;
Begin
  LastA := -1;
  LastI := -2;
  For Y := 0 To UiRows - 1 Do
    For X := 0 To UiCols - 1 Do
    Begin
      I := Y * UiCols + X;
      If ((TxCh[I] <> TxShCh[I]) Or (TxAt[I] <> TxShAt[I]) Or Not TxShown)
         And (I < UiCols * UiRows - 1) Then
      Begin
        If (LastI <> I - 1) Or (X = 0) Then TxGoto(X, Y);
        A := TxAt[I];
        If A <> LastA Then
        Begin
          TxAttr(A);
          LastA := A;
        End;
        TxPutCh(TxCh[I]);
        TxShCh[I] := TxCh[I];
        TxShAt[I] := TxAt[I];
        LastI := I;
      End;
    End;
  TxShown := True;
  TxPutS(#27'[0m');
  If TxCurX >= 0 Then
  Begin
    TxGoto(TxCurX, TxCurY);
    TxPutS(#27'[?25h');
  End
  Else TxPutS(#27'[?25l');
  TxFlushOut;
End;

Procedure TxClearAll(A : LongInt);
Var I : LongInt;
Begin
  For I := 0 To UiCols * UiRows - 1 Do
  Begin
    TxCh[I] := 32;
    TxAt[I] := A;
  End;
End;

{ ---- geometrie ---- }

Procedure UiCellToPx(Cx, Cy : LongInt; Var Px, Py : LongInt);
Begin
  Px := UiOffX + Cx * GCW;
  Py := UiOffY + Cy * GCH;
End;

Procedure UiPxToCell(Px, Py : LongInt; Var Cx, Cy : LongInt);
Begin
  Cx := (Px - UiOffX) Div GCW;
  Cy := (Py - UiOffY) Div GCH;
End;

{ calcule la fenetre et la zone de contenu selon la grille }
Procedure UiLayout;
Begin
  If UiGfx Then
  Begin
    UiWx := 2; UiWy := 4;
    UiWw := UiCols - 4; UiWh := UiRows - 7;
  End
  Else
  Begin
    UiWx := 0; UiWy := 1;
    UiWw := UiCols; UiWh := UiRows - 2;
  End;
  UiCx := UiWx + 2; UiCy := UiWy + 2;
  UiCw := UiWw - 4; UiCh := UiWh - 5;
End;

{ ---- dessin par roles ---- }

Procedure UiFill(Cx, Cy, Cw, Chh, Role : LongInt);
Var Px, Py, X, Y, I : LongInt;
Begin
  If UiGfx Then
  Begin
    UiCellToPx(Cx, Cy, Px, Py);
    If UiRoleBg[Role] >= 0 Then
      GFillRect(Px, Py, Cw * GCW, Chh * GCH, UiRoleBg[Role]);
  End
  Else
    For Y := Cy To Cy + Chh - 1 Do
      For X := Cx To Cx + Cw - 1 Do
        If (X >= 0) And (X < UiCols) And (Y >= 0) And (Y < UiRows) Then
        Begin
          I := Y * UiCols + X;
          TxCh[I] := 32;
          TxAt[I] := TxRoleAt[Role];
        End;
End;

{ texte a la cellule (Cx,Cy) ; fond du role (ou transparent) }
Procedure UiPutS(Cx, Cy : LongInt; Const S : String; Role : LongInt);
Var Px, Py, K, I : LongInt;
Begin
  If UiGfx Then
  Begin
    UiCellToPx(Cx, Cy, Px, Py);
    GText(Px, Py, S, UiRoleFg[Role], UiRoleBg[Role]);
  End
  Else
    For K := 1 To Length(S) Do
      If (Cx + K - 1 >= 0) And (Cx + K - 1 < UiCols) And (Cy >= 0) And
         (Cy < UiRows) Then
      Begin
        I := Cy * UiCols + Cx + K - 1;
        TxCh[I] := Ord(S[K]);
        TxAt[I] := TxRoleAt[Role];
      End;
End;

{ une cellule a l'ecran avec un attribut texte explicite }
Procedure UiPutCh(Cx, Cy, Code, Role : LongInt);
Var S : String;
Begin
  S := Chr(Code);
  UiPutS(Cx, Cy, S, Role);
End;

{ cadre 3D (relief) autour d'une zone de cellules, en pixels (mode
  graphique seulement) }
Procedure UiBevel(Cx, Cy, Cw, Chh : LongInt; Raised : Boolean);
Var Px, Py, W, H, Lt, Dk : LongInt;
Begin
  If Not UiGfx Then Exit;
  UiCellToPx(Cx, Cy, Px, Py);
  W := Cw * GCW; H := Chh * GCH;
  If Raised Then
  Begin
    Lt := $FFFFFF; Dk := $7A869A;
  End
  Else
  Begin
    Lt := $FFFFFF; Dk := $7A869A;
  End;
  If Raised Then
  Begin
    GHLine(Px, Py, W, Lt);
    GVLine(Px, Py, H, Lt);
    GHLine(Px, Py + H - 1, W, Dk);
    GVLine(Px + W - 1, Py, H, Dk);
  End
  Else
  Begin
    GHLine(Px, Py, W, Dk);
    GVLine(Px, Py, H, Dk);
    GHLine(Px, Py + H - 1, W, Lt);
    GVLine(Px + W - 1, Py, H, Lt);
  End;
End;

{ cadre de couleur Col autour d'une zone de cellules (pixel) }
Procedure UiBox(Cx, Cy, Cw, Chh, Col : LongInt);
Var Px, Py : LongInt;
Begin
  If Not UiGfx Then Exit;
  UiCellToPx(Cx, Cy, Px, Py);
  GFrame(Px, Py, Cw * GCW, Chh * GCH, Col);
End;

{ logo LINUX-0 dessine en vecteurs : pastille bleue ">_" et mot-symbole }
Procedure UiLogo(Px, Py, Sz : LongInt);
Var Fs, Sv : LongInt;
Begin
  GFillRound(Px, Py, Sz, Sz, 6, $FFFFFF);
  GGradV(Px + 3, Py + 3, Sz - 6, Sz - 6, $3C8DE0, $1D4E89);
  GFillRound(Px + 3, Py + 3, Sz - 6, 2, 0, $7FB4EE);
  { chevron > et tiret bas }
  GLine(Px + Sz Div 4, Py + Sz Div 4, Px + Sz Div 2, Py + Sz Div 2, $FFFFFF);
  GLine(Px + Sz Div 4 + 1, Py + Sz Div 4, Px + Sz Div 2 + 1, Py + Sz Div 2,
        $FFFFFF);
  GLine(Px + Sz Div 2, Py + Sz Div 2, Px + Sz Div 4, Py + 3 * Sz Div 4,
        $FFFFFF);
  GLine(Px + Sz Div 2 + 1, Py + Sz Div 2, Px + Sz Div 4 + 1,
        Py + 3 * Sz Div 4, $FFFFFF);
  GFillRect(Px + Sz Div 2 + 4, Py + 3 * Sz Div 4 - 2, Sz Div 4, 4, $FFFFFF);
End;

{ fond d'ecran : degrade, logo et titre (graphique) ou fond uni (texte) }
Procedure UiBackground(Const Title : String);
Var Lh, Px, Py, Sz : LongInt;
Begin
  If UiGfx Then
  Begin
    GGradV(0, 0, GW, GH, UiBlue1, UiBlue2);
    Sz := UiWy * GCH - 16;
    If Sz > 72 Then Sz := 72;
    UiLogo(UiOffX + UiWx * GCW, 8, Sz);
    Px := UiOffX + UiWx * GCW + Sz + 14;
    GFontSel(GFontN);
    Lh := GCH * 2;
    GTextScaled(Px, 6, 'LINUX-0', $FFFFFF, 2);
    GText(Px + 2, 6 + Lh + 2, 'KERNEL32  -  ' + Title, $B9CCE6, -1);
  End
  Else
  Begin
    TxClearAll(TxRoleAt[R_BG]);
    UiPutS(1, 0, Title, R_HEAD);
  End;
End;

{ fenetre principale avec barre de titre }
Procedure UiWindow(Const Title : String);
Var Px, Py, W, H : LongInt;
Begin
  If UiGfx Then
  Begin
    UiCellToPx(UiWx, UiWy, Px, Py);
    W := UiWw * GCW; H := UiWh * GCH;
    GShade(Px + 6, Py + 6, W + 4, H + 4, 55);
    GFillRound(Px, Py, W, H, 4, $F3F5F9);
    GFrame(Px, Py + 4, W, H - 8, $9FB1CC);
    GFillRect(Px + 4, Py, W - 8, 1, $9FB1CC);
    GFillRect(Px + 4, Py + H - 1, W - 8, 1, $9FB1CC);
    GGradV(Px + 1, Py + 1, W - 2, GCH - 1, $3F7BC4, $23508F);
    GText(Px + GCW, Py + 1, Title, $FFFFFF, -1);
    GHLine(Px + 1, Py + GCH, W - 2, $1A3C6E);
  End
  Else
  Begin
    UiFill(UiWx, UiWy, UiWw, UiWh, R_WIN);
    UiFill(UiWx, UiWy, UiWw, 1, R_TITLE);
    UiPutS(UiWx + 1, UiWy, Title, R_TITLE);
  End;
End;

{ ligne d'aide en bas de l'ecran }
Procedure UiFooter(Const S : String);
Begin
  If UiGfx Then
    UiPutS(UiWx, UiRows - 2, S, R_HINT)
  Else
    UiPutS(0, UiRows - 1, S, R_HINT);
End;

{ envoie l'image a l'ecran }
Procedure UiPresent;
Begin
  If UiGfx Then GFlush Else TxFlush;
End;

{ ---- terminal : initialisation et restauration ---- }

Procedure UiTermRaw(Fd : LongInt);
Var T : TSysTermios;
Begin
  UiTermFd := Fd;
  If SysTcGetAttr(Fd, UiOldTerm) = 0 Then UiHaveTerm := True;
  If Not UiHaveTerm Then Exit;
  T := UiOldTerm;
  T.IFlag := T.IFlag And Not (TTY_ICRNL Or TTY_IXON Or TTY_INLCR Or
    TTY_ISTRIP);
  T.LFlag := T.LFlag And Not (TTY_ICANON Or TTY_ECHO Or TTY_ISIG Or
    TTY_IEXTEN);
  T.OFlag := T.OFlag And Not TTY_OPOST;
  T.CC[TTY_VMIN] := 1;
  T.CC[TTY_VTIME] := 0;
  SysTcSetAttr(Fd, 0, T);
End;

Procedure UiTermRestore;
Begin
  If UiHaveTerm Then SysTcSetAttr(UiTermFd, 0, UiOldTerm);
End;

{ taille de la grille texte ; retourne False si le terminal est trop petit }
Procedure UiTextGrid;
Var Ws : TSysWinSize;
Begin
  UiCols := 80; UiRows := 25;
  If SysGetWinSize(UiOutFd, Ws) = 0 Then
  Begin
    If (Ws.Col >= 80) And (Ws.Col <= 160) Then UiCols := Ws.Col;
    If (Ws.Row >= 24) And (Ws.Row <= 50) Then UiRows := Ws.Row;
  End;
  If UiCols * UiRows > 8192 Then
  Begin
    UiCols := 80; UiRows := 25;
  End;
End;

{ passe en mode texte plein ecran }
Procedure UiTextOpen;
Begin
  UiGfx := False;
  UiTextGrid;
  UiOffX := 0; UiOffY := 0;
  FillChar(TxShCh, SizeOf(TxShCh), 0);
  FillChar(TxShAt, SizeOf(TxShAt), 0);
  TxShown := False;
  TxCurX := -1; TxCurY := -1;
  TxOutN := 0;
  TxPutS(#27'[0m'#27'[2J'#27'[H');
  TxFlushOut;
  UiLayout;
End;

Procedure UiTextClose;
Begin
  TxPutS(#27'[0m'#27'[2J'#27'[H'#27'[?25h');
  TxFlushOut;
End;

{ choisit la police selon la largeur d'ecran et calcule la grille }
Procedure UiGfxGrid;
Begin
  If GW >= 1500 Then GFontSel(2)
  Else If GW >= 1000 Then GFontSel(1)
  Else GFontSel(0);
  UiCols := GW Div GCW;
  UiRows := GH Div GCH;
  UiOffX := (GW - UiCols * GCW) Div 2;
  UiOffY := (GH - UiRows * GCH) Div 2;
  If UiCols > 160 Then
  Begin
    UiCols := 160;
    UiOffX := (GW - UiCols * GCW) Div 2;
  End;
  UiGfx := True;
  UiLayout;
End;
