{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2026
  @website(https://www.gladir.com/linux-0)
  @abstract(Target: LPC -3X)
  @description: GFX.INC : bibliotheque graphique de KERNEL32 sur /dev/fb0 (LPC
      -3X). Memoire d'image hors ecran 32 bits (0x00RRGGBB), primitives
      (pixel, rectangle, ligne, degrade, ombre, copie), polices bitmap 8x16,
      12x24 et 16x32 (FONTS.INC, jeu Windows-1252 : un octet par caractere),
      curseur de souris dessine par le logiciel. Tout est dessine dans le
      tampon GBack ; GFlush (ou GFlushRect) le recopie dans la memoire video :
      pas de scintillement. Inclure apres FONTS.INC. Noms globaux prefixes
      G...
}

Var
  GFbFd, GW, GH, GStride, GFb, GBack, GMapLen : LongInt;
  GOk : Boolean;
  GClipX0, GClipY0, GClipX1, GClipY1 : LongInt;
  GFontN, GFontAddr, GCW, GCH, GBPR : LongInt;   { police en cours }
  GTtyFd, GBackSz : LongInt;
  GBackP : Pointer;
  GCurX, GCurY : LongInt;
  GCurOn : Boolean;

Const
  GCurW = 15;                    { zone restauree par GCursorHide }
  GCurH = 22;
  { fleche "prisme" (meme dessin que l'unite Graph, TOOLS/L32GFX.PAS) :
    '#' contour noir, H reflet, L clair, M moyen, D sombre ; point chaud en
    (0,0) }
  GCurPrism : Array[0..21] Of String[15] = (
    '#..............', '##.............', '#H#............',
    '#HM#...........', '#HMM#..........', '#HLMM#.........',
    '#HLMMM#........', '#HLMMMM#.......', '#HLLMMMM#......',
    '#HLLMMMMM#.....', '#HLLLMMMMM#....', '#HLLLMMMMMD#...',
    '#HLLLLDDDDDD#..', '#HLLLLDD######.', '#HLL#LL#.......',
    '#HL#.#D#.......', '#H#..#LD#......', '##...#LD#......',
    '#.....#DD#.....', '......#LD#.....', '.......#DD#....',
    '.......###.....');
  { ancienne fleche (GFXPLAINCUR=1, k32setup.plaincursor) : X blanc, O noir }
  GCurPlain : Array[0..18] Of String[12] = (
    'X...........', 'XX..........', 'X.X.........', 'X..X........',
    'X...X.......', 'X....X......', 'X.....X.....', 'X......X....',
    'X.......X...', 'X........X..', 'X.....XXXXX.', 'X..X..X.....',
    'X.X.X..X....', 'XX..X..X....', 'X....X..X...', '.....X..X...',
    '......X..X..', '......X..X..', '.......XX...');
  { couleurs 0x00RRGGBB (claire, moyenne, sombre, reflet) pour rouge E02020,
    vert 20C040, bleu 2060E8 : claire = base + (255 - base) * 0,40, sombre =
    base * 0,60, reflet = base + (255 - base) * 0,75 (comme Graph) }
  GCurCol : Array[0..11] Of LongInt = (
    $EC7979, $E02020, $861313, $F7C7C7,
    $79D98C, $20C040, $137326, $C7EFCF,
    $79A0F1, $2060E8, $133A8B, $C7D7F9);

Var
  GPlain : Boolean;              { ancienne fleche blanche (comparaisons) }
  GCurIdx : LongInt;             { couleur courante : seconde mod 3 }

Function GRgb(R, G, B : LongInt) : LongInt;
Begin
  GRgb := (R And 255) Shl 16 Or (G And 255) Shl 8 Or (B And 255);
End;

{ melange : A% de C1 et le reste de C2 (A de 0 a 100) }
Function GMix(C1, C2, A : LongInt) : LongInt;
Var R, G, B : LongInt;
Begin
  R := (((C1 Shr 16) And 255) * A + ((C2 Shr 16) And 255) * (100 - A)) Div 100;
  G := (((C1 Shr 8) And 255) * A + ((C2 Shr 8) And 255) * (100 - A)) Div 100;
  B := ((C1 And 255) * A + (C2 And 255) * (100 - A)) Div 100;
  GMix := (R Shl 16) Or (G Shl 8) Or B;
End;

Procedure GFillRow(Addr, N, Col : LongInt);
Begin
  If N <= 0 Then Exit;
  asm
    push edi
    mov edi, Addr
    mov ecx, N
    mov eax, Col
    cld
    rep stosd
    pop edi
  end;
End;

Procedure GCopyDw(Src, Dst, N : LongInt);
Begin
  If N <= 0 Then Exit;
  asm
    push esi
    push edi
    mov esi, Src
    mov edi, Dst
    mov ecx, N
    cld
    rep movsd
    pop edi
    pop esi
  end;
End;

Procedure GClipAll;
Begin
  GClipX0 := 0; GClipY0 := 0; GClipX1 := GW; GClipY1 := GH;
End;

Procedure GClipSet(X, Y, W, H : LongInt);
Begin
  GClipX0 := X; GClipY0 := Y; GClipX1 := X + W; GClipY1 := Y + H;
  If GClipX0 < 0 Then GClipX0 := 0;
  If GClipY0 < 0 Then GClipY0 := 0;
  If GClipX1 > GW Then GClipX1 := GW;
  If GClipY1 > GH Then GClipY1 := GH;
End;

Procedure GFontSel(N : LongInt);
Begin
  GFontN := N;
  If N = 0 Then
  Begin
    GFontAddr := LongInt(@F8Data); GCW := F8W; GCH := F8H; GBPR := F8B;
  End
  Else If N = 1 Then
  Begin
    GFontAddr := LongInt(@F12Data); GCW := F12W; GCH := F12H; GBPR := F12B;
  End
  Else
  Begin
    GFontAddr := LongInt(@F16Data); GCW := F16W; GCH := F16H; GBPR := F16B;
  End;
End;

Procedure GPix(X, Y, Col : LongInt);
Begin
  If (X < GClipX0) Or (X >= GClipX1) Or (Y < GClipY0) Or (Y >= GClipY1) Then
    Exit;
  MemL[0:GBack + (Y * GW + X) * 4] := Col;
End;

Function GGetPix(X, Y : LongInt) : LongInt;
Begin
  If (X < 0) Or (X >= GW) Or (Y < 0) Or (Y >= GH) Then GGetPix := 0
  Else GGetPix := MemL[0:GBack + (Y * GW + X) * 4];
End;

Procedure GFillRect(X, Y, W, H, Col : LongInt);
Var Yy, X1 : LongInt;
Begin
  X1 := X + W;
  If X < GClipX0 Then X := GClipX0;
  If X1 > GClipX1 Then X1 := GClipX1;
  If Y < GClipY0 Then
  Begin
    H := H - (GClipY0 - Y);
    Y := GClipY0;
  End;
  If Y + H > GClipY1 Then H := GClipY1 - Y;
  If (X1 <= X) Or (H <= 0) Then Exit;
  For Yy := Y To Y + H - 1 Do
    GFillRow(GBack + (Yy * GW + X) * 4, X1 - X, Col);
End;

Procedure GHLine(X, Y, W, Col : LongInt);
Begin
  GFillRect(X, Y, W, 1, Col);
End;

Procedure GVLine(X, Y, H, Col : LongInt);
Begin
  GFillRect(X, Y, 1, H, Col);
End;

Procedure GFrame(X, Y, W, H, Col : LongInt);
Begin
  GHLine(X, Y, W, Col);
  GHLine(X, Y + H - 1, W, Col);
  GVLine(X, Y, H, Col);
  GVLine(X + W - 1, Y, H, Col);
End;

Procedure GLine(X0, Y0, X1, Y1, Col : LongInt);
Var Dx, Dy, Sx, Sy, Er, E2 : LongInt;
Begin
  Dx := X1 - X0; If Dx < 0 Then Dx := -Dx;
  Dy := Y1 - Y0; If Dy < 0 Then Dy := -Dy;
  If X0 < X1 Then Sx := 1 Else Sx := -1;
  If Y0 < Y1 Then Sy := 1 Else Sy := -1;
  Er := Dx - Dy;
  While True Do
  Begin
    GPix(X0, Y0, Col);
    If (X0 = X1) And (Y0 = Y1) Then Break;
    E2 := 2 * Er;
    If E2 > -Dy Then
    Begin
      Er := Er - Dy;
      X0 := X0 + Sx;
    End;
    If E2 < Dx Then
    Begin
      Er := Er + Dx;
      Y0 := Y0 + Sy;
    End;
  End;
End;

{ degrade vertical de C1 (haut) a C2 (bas) }
Procedure GGradV(X, Y, W, H, C1, C2 : LongInt);
Var I : LongInt;
Begin
  If H <= 0 Then Exit;
  If H = 1 Then
  Begin
    GFillRect(X, Y, W, 1, C1);
    Exit;
  End;
  For I := 0 To H - 1 Do
    GFillRect(X, Y + I, W, 1, GMix(C2, C1, I * 100 Div (H - 1)));
End;

{ degrade horizontal }
Procedure GGradH(X, Y, W, H, C1, C2 : LongInt);
Var I : LongInt;
Begin
  If W <= 1 Then
  Begin
    GFillRect(X, Y, W, H, C1);
    Exit;
  End;
  For I := 0 To W - 1 Do
    GFillRect(X + I, Y, 1, H, GMix(C2, C1, I * 100 Div (W - 1)));
End;

{ rectangle plein a coins coupes (rayon R pixels, 0 a 4) }
Procedure GFillRound(X, Y, W, H, R, Col : LongInt);
Begin
  If R <= 0 Then
  Begin
    GFillRect(X, Y, W, H, Col);
    Exit;
  End;
  GFillRect(X + R, Y, W - 2 * R, H, Col);
  GFillRect(X, Y + R, R, H - 2 * R, Col);
  GFillRect(X + W - R, Y + R, R, H - 2 * R, Col);
  If R >= 2 Then
  Begin
    GFillRect(X + 1, Y + 1, R - 1, R - 1, Col);
    GFillRect(X + W - R, Y + 1, R - 1, R - 1, Col);
    GFillRect(X + 1, Y + H - R, R - 1, R - 1, Col);
    GFillRect(X + W - R, Y + H - R, R - 1, R - 1, Col);
  End;
End;

{ assombrit une zone (ombre portee) : P% de noir }
Procedure GShade(X, Y, W, H, P : LongInt);
Var Xx, Yy, A : LongInt; Px : LongInt;
Begin
  If X < GClipX0 Then
  Begin
    W := W - (GClipX0 - X);
    X := GClipX0;
  End;
  If Y < GClipY0 Then
  Begin
    H := H - (GClipY0 - Y);
    Y := GClipY0;
  End;
  If X + W > GClipX1 Then W := GClipX1 - X;
  If Y + H > GClipY1 Then H := GClipY1 - Y;
  For Yy := Y To Y + H - 1 Do
    For Xx := X To X + W - 1 Do
    Begin
      A := GBack + (Yy * GW + Xx) * 4;
      Px := MemL[0:A];
      MemL[0:A] := GMix(0, Px, P);
    End;
End;

{ disque plein de centre (Cx,Cy) et rayon R }
Procedure GFillCircle(Cx, Cy, R, Col : LongInt);
Var Y, Hw : LongInt;
Begin
  For Y := -R To R Do
  Begin
    Hw := 0;
    While (Hw + 1) * (Hw + 1) + Y * Y <= R * R + R Do Inc(Hw);
    GFillRect(Cx - Hw, Cy + Y, 2 * Hw + 1, 1, Col);
  End;
End;

{ ---- texte ---- }

{ un caractere (code Windows-1252) ; Bg < 0 : fond transparent }
Procedure GChar(X, Y, Code, Fg, Bg : LongInt);
Var Row, B, K, Bits, A, Xp : LongInt;
Begin
  If Code < 32 Then Code := 32;
  If Code > 255 Then Code := 63;
  If (X + GCW <= GClipX0) Or (X >= GClipX1) Or (Y + GCH <= GClipY0) Or
     (Y >= GClipY1) Then Exit;
  If Bg >= 0 Then GFillRect(X, Y, GCW, GCH, Bg);
  A := GFontAddr + (Code - 32) * GBPR * GCH;
  For Row := 0 To GCH - 1 Do
  Begin
    If (Y + Row >= GClipY0) And (Y + Row < GClipY1) Then
      For B := 0 To GBPR - 1 Do
      Begin
        Bits := Mem[0:A + Row * GBPR + B];
        If Bits <> 0 Then
          For K := 0 To 7 Do
            If (Bits And ($80 Shr K)) <> 0 Then
            Begin
              Xp := X + B * 8 + K;
              If (Xp >= GClipX0) And (Xp < GClipX1) Then
                MemL[0:GBack + ((Y + Row) * GW + Xp) * 4] := Fg;
            End;
      End;
  End;
End;

Procedure GText(X, Y : LongInt; Const S : String; Fg, Bg : LongInt);
Var I : LongInt;
Begin
  For I := 1 To Length(S) Do
    GChar(X + (I - 1) * GCW, Y, Ord(S[I]), Fg, Bg);
End;

Function GTextW(Const S : String) : LongInt;
Begin
  GTextW := Length(S) * GCW;
End;

{ caractere agrandi N fois (titres, logo) }
Procedure GCharScaled(X, Y, Code, Fg, Sc : LongInt);
Var Row, B, K, Bits, A, Xp, Dx, Dy : LongInt;
Begin
  If Code < 32 Then Code := 32;
  If Code > 255 Then Code := 63;
  A := GFontAddr + (Code - 32) * GBPR * GCH;
  For Row := 0 To GCH - 1 Do
    For B := 0 To GBPR - 1 Do
    Begin
      Bits := Mem[0:A + Row * GBPR + B];
      If Bits <> 0 Then
        For K := 0 To 7 Do
          If (Bits And ($80 Shr K)) <> 0 Then
          Begin
            Xp := X + (B * 8 + K) * Sc;
            GFillRect(Xp, Y + Row * Sc, Sc, Sc, Fg);
          End;
    End;
End;

Procedure GTextScaled(X, Y : LongInt; Const S : String; Fg, Sc : LongInt);
Var I : LongInt;
Begin
  For I := 1 To Length(S) Do
    GCharScaled(X + (I - 1) * GCW * Sc, Y, Ord(S[I]), Fg, Sc);
End;

{ ---- copie vers l'ecran ---- }

Procedure GFlushRect(X, Y, W, H : LongInt);
Var Yy, X1 : LongInt;
Begin
  If Not GOk Then Exit;
  X1 := X + W;
  If X < 0 Then X := 0;
  If Y < 0 Then
  Begin
    H := H + Y;
    Y := 0;
  End;
  If X1 > GW Then X1 := GW;
  If Y + H > GH Then H := GH - Y;
  If (X1 <= X) Or (H <= 0) Then Exit;
  For Yy := Y To Y + H - 1 Do
    GCopyDw(GBack + (Yy * GW + X) * 4, GFb + Yy * GStride + X * 4, X1 - X);
End;

Procedure GFlush;
Begin
  GFlushRect(0, 0, GW, GH);
End;

{ curseur : dessine directement dans la memoire video (le tampon reste
  intact : GCursorHide recopie la zone depuis le tampon) }
Procedure GCursorHide;
Begin
  If GCurOn Then
  Begin
    GFlushRect(GCurX, GCurY, GCurW, GCurH);
    GCurOn := False;
  End;
End;

Procedure GCursorShow(X, Y : LongInt);
Var Row, Col, Xp, Yp, Base, Cl : LongInt; C : Char;
    Pal : Array[0..3] Of LongInt;
Begin
  If Not GOk Then Exit;
  GCurX := X; GCurY := Y;
  If GPlain Then
  Begin
    For Row := 0 To 18 Do
      For Col := 0 To 11 Do
      Begin
        C := GCurPlain[Row][Col + 1];
        Xp := X + Col; Yp := Y + Row;
        If (C <> '.') And (Xp >= 0) And (Xp < GW) And (Yp >= 0) And
           (Yp < GH) Then
        Begin
          If C = 'X' Then MemL[0:GFb + Yp * GStride + Xp * 4] := $FFFFFF
          Else MemL[0:GFb + Yp * GStride + Xp * 4] := 0;
        End;
      End;
    GCurOn := True;
    Exit;
  End;
  { couleur : seconde de l'horloge murale mod 3 (0 rouge, 1 vert, 2 bleu) }
  GCurIdx := SysTime Mod 3;
  Base := GCurIdx * 4;
  Pal[0] := GCurCol[Base];
  Pal[1] := GCurCol[Base + 1];
  Pal[2] := GCurCol[Base + 2];
  Pal[3] := GCurCol[Base + 3];
  For Row := 0 To GCurH - 1 Do
    For Col := 0 To GCurW - 1 Do
    Begin
      C := GCurPrism[Row][Col + 1];
      Xp := X + Col; Yp := Y + Row;
      If (C <> '.') And (Xp >= 0) And (Xp < GW) And (Yp >= 0) And
         (Yp < GH) Then
      Begin
        Case C Of
          'L' : Cl := Pal[0];
          'M' : Cl := Pal[1];
          'D' : Cl := Pal[2];
          'H' : Cl := Pal[3];
        Else Cl := 0;
        End;
        MemL[0:GFb + Yp * GStride + Xp * 4] := Cl;
      End;
    End;
  GCurOn := True;
End;

{ a appeler a chaque tour des boucles d'attente : si la seconde a change et
  que le curseur est affiche, le redessine en place (meme silhouette : rien
  a restaurer, ni trainee ni scintillement) }
Procedure GCursorTick;
Begin
  If GCurOn And Not GPlain Then
    If (SysTime Mod 3) <> GCurIdx Then GCursorShow(GCurX, GCurY);
End;

{ ---- ouverture du peripherique ---- }

{ ouvre /dev/fb0, choisit LxH en 32 bits, projette la memoire video, alloue
  le tampon ; passe la console en mode graphique (KD_GRAPHICS) }
Var GWhy : String;        { pourquoi le graphique est indisponible }

Function NumToS(V : LongInt) : String;
Var S : String;
Begin
  Str(V, S);
  NumToS := S;
End;

Function ErrS(E : LongInt) : String;
Var S : String;
Begin
  Str(E, S);
  ErrS := 'errno ' + S;
End;

{ premiere ligne de /proc/fb (ex. "0 BGA") ou '' }
Function GProcFb : String;
Var Fd, N : LongInt; B : Array[0..63] Of Byte; S : String; I : LongInt;
Begin
  GProcFb := '';
  Fd := SysOpen('/proc/fb', O_RDONLY, 0);
  If Fd < 0 Then Exit;
  N := SysRead(Fd, B, 63);
  SysClose(Fd);
  S := '';
  For I := 0 To N - 1 Do
  Begin
    If (B[I] = 10) Or (B[I] = 13) Then Break;
    S := S + Chr(B[I]);
  End;
  GProcFb := S;
End;

Function GOpen(WantW, WantH : LongInt) : Boolean;
Var Vi : Array[0..39] Of LongInt; Fi : Array[0..15] Of LongInt; R : LongInt;
Begin
  GOpen := False;
  GOk := False;
  GCurOn := False;
  GCurIdx := -1;
  If SysGetEnv('GFXPLAINCUR') = '1' Then GPlain := True;
  GWhy := '';
  GFbFd := SysOpen('/dev/fb0', O_RDWR, 0);
  If GFbFd < 0 Then
  Begin
    GWhy := '/dev/fb0 : ' + SysErrorText(SysErrno);
    If GProcFb = '' Then GWhy := GWhy + ' ; /proc/fb vide'
    Else GWhy := GWhy + ' ; /proc/fb : ' + GProcFb;
    Exit;
  End;
  FillChar(Vi, SizeOf(Vi), 0);
  If SysIoctl(GFbFd, $4600, Vi) < 0 Then
  Begin
    GWhy := 'FBIOGET_VSCREENINFO : ' + ErrS(SysErrno);
    SysClose(GFbFd);
    Exit;
  End;
  { demande toujours le mode voulu (programme la carte meme si la
    resolution annoncee est deja la bonne) ; sinon garde le mode courant }
  Vi[0] := WantW; Vi[1] := WantH; Vi[2] := WantW; Vi[3] := WantH;
  Vi[4] := 0; Vi[5] := 0; Vi[6] := 32; Vi[21] := 0;
  If SysIoctl(GFbFd, $4601, Vi) < 0 Then
  Begin
    FillChar(Vi, SizeOf(Vi), 0);
    If SysIoctl(GFbFd, $4600, Vi) < 0 Then
    Begin
      GWhy := 'FBIOPUT_VSCREENINFO : ' + ErrS(SysErrno);
      SysClose(GFbFd);
      Exit;
    End;
  End
  Else SysIoctl(GFbFd, $4600, Vi);
  GW := Vi[0]; GH := Vi[1];
  If (Vi[6] <> 32) Or (GW < 640) Or (GH < 480) Then
  Begin
    GWhy := 'mode ' + NumToS(GW) + 'x' + NumToS(GH) + 'x' + NumToS(Vi[6]) +
            ' (32 bits et 640x480 au moins requis)';
    SysClose(GFbFd);
    Exit;
  End;
  If SysIoctl(GFbFd, $4602, Fi) < 0 Then
  Begin
    GWhy := 'FBIOGET_FSCREENINFO : ' + ErrS(SysErrno);
    SysClose(GFbFd);
    Exit;
  End;
  GStride := Fi[12];
  If GStride < GW * 4 Then GStride := GW * 4;
  GMapLen := GStride * GH;
  R := LnxSys6(192, 0, GMapLen, 3, 1, GFbFd, 0);
  If (R < 0) And (R > -4096) Then
  Begin
    GWhy := 'mmap /dev/fb0 : ' + ErrS(-R);
    SysClose(GFbFd);
    Exit;
  End;
  GFb := R;
  If (GBack = 0) Or (GBackSz <> GW * GH * 4) Then
  Begin
    GetMem(GBackP, GW * GH * 4 + 64);
    GBack := LongInt(GBackP);
    GBackSz := GW * GH * 4;
  End;
  If GBack = 0 Then
  Begin
    GWhy := 'memoire insuffisante pour le tampon graphique';
    Exit;
  End;
  GTtyFd := SysOpen('/dev/tty0', O_RDWR, 0);
  If GTtyFd >= 0 Then SysIoctlL(GTtyFd, $4B3A, 1);
  GClipAll;
  GFontSel(0);
  GOk := True;
  GOpen := True;
End;

Procedure GClose;
Begin
  If GOk Then
  Begin
    GCursorHide;
    If GTtyFd >= 0 Then
    Begin
      SysIoctlL(GTtyFd, $4B3A, 0);
      SysClose(GTtyFd);
    End;
    LnxSys3(91, GFb, GMapLen, 0);
    SysClose(GFbFd);
    GOk := False;
  End;
End;
