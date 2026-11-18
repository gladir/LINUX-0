{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2026
  @website(https://www.gladir.com/linux-0)
  @abstract(Target: LPC -3X)
  @description: L32GFX.PAS : unite Graph (sous-ensemble BGI de Turbo
    Pascal 7 et de Free Pascal) et souris (Intr 33h) des programmes -3X.
    Integre par MKAPI.PAS dans LPC32.PAS et injecte apres L32API.PAS
    seulement quand le programme contient Uses ... Graph (ou PtcGraph).
    Les noms definis ici remplacent les procedures predefinies du
    compilateur (comme pour un sous-programme du programme).
    Principe : un tampon d'image en memoire, un octet par pixel (indice de
    couleur 0..15 comme la memoire video VGA : les modes XOR, OR, AND de
    PutImage et SetWriteMode ont donc le sens de BGI), copie vers
    /dev/fb0 (32, 24 ou 16 bits par pixel) par BgFlush, appele aux
    moments d'attente (KeyPressed, ReadKey, Delay, souris) et a
    CloseGraph. Les noms internes commencent par Bg. }

Type
  PointType = Record X, Y : Integer; End;
  ArcCoordsType = Record X, Y, XStart, YStart, XEnd, YEnd : Integer; End;
  FillSettingsType = Record Pattern, Color : Word; End;
  FillPatternType = Array[1..8] Of Byte;
  LineSettingsType = Record LineStyle, Pattern, Thickness : Word; End;
  TextSettingsType = Record Font, Direction, CharSize, Horiz, Vert : Word;
  End;
  ViewPortType = Record X1, Y1, X2, Y2 : Integer; Clip : Boolean; End;
  PaletteType = Record Size : Byte; Colors : Array[0..15] Of ShortInt; End;
  TFPCHeapStatus = Record
    MaxHeapSize, MaxHeapUsed, CurrHeapSize, CurrHeapUsed, CurrHeapFree
      : LongInt;
  End;

Const
  NormalPut = 0;
  D1bit = 11; D2bit = 12; D4bit = 13; D8bit = 14; D12bit = 15;
  D15bit = 16; D16bit = 17; D24bit = 18; D32bit = 19; D64bit = 20;
  m320x200 = 0; m640x200 = 1; m640x350 = 2; m640x480 = 3; m800x600 = 4;
  m1024x768 = 5; m1280x1024 = 6; m1600x1200 = 7;

Var
  BgOk, BgMem : Boolean;       { graphique actif ; sans /dev/fb0 }
  BgRes : Integer;             { GraphResult }
  BgWhy : String;              { raison d'un echec (GfxWhy) }
  BgW, BgH : LongInt;          { taille logique de l'ecran }
  BgBuf : LongInt;             { adresse de la page de dessin }
  BgPages : Array[0..3] Of LongInt;
  BgAct, BgVis : LongInt;      { pages de dessin et affichee }
  BgDirty : Boolean;           { rectangle a recopier vers l'ecran }
  BgDx1, BgDy1, BgDx2, BgDy2 : LongInt;
  BgColor, BgBk, BgFillCol, BgFillPat, BgMode : LongInt;
  BgUser : Array[0..7] Of Byte;
  BgLnSt, BgLnPat, BgLnTh : LongInt;
  BgVx, BgVy, BgVx2, BgVy2 : LongInt;     { fenetre (viewport) absolue }
  BgClip : Boolean;
  BgCx1, BgCy1, BgCx2, BgCy2 : LongInt;   { rectangle d'ecretage }
  BgCpx, BgCpy : LongInt;
  BgFont, BgDir, BgSize, BgHj, BgVj : LongInt;
  BgPal : Array[0..15] Of Byte;           { registre de palette -> CAN }
  BgDac : Array[0..255] Of LongInt;       { 0x00RRGGBB }
  BgFin : Array[0..15] Of LongInt;        { pixel ecran de chaque couleur }
  BgFd, BgFb, BgStride, BgBpp, BgBytes, BgFbW, BgFbH : LongInt;
  BgOfx, BgOfy, BgMapLen, BgTtyFd : LongInt;
  BgRo, BgRl, BgGo, BgGl, BgBo, BgBl : LongInt;
  BgDrv, BgMod : LongInt;
  BgArc : ArcCoordsType;
  BgTermOk, BgRawOn, BgKdOn, BgTermTry : Boolean;
  BgTermSv, BgTermNw : Array[0..8] Of LongInt;
  BgGfxHook : Boolean;
  BgPtsX, BgPtsY : Array[0..400] Of LongInt;
  BgSt : Array[0..15] Of LongInt;         { compteurs (GfxStat) }
  BgRn : LongInt;                         { rectangles a recopier }
  BgRx1, BgRy1, BgRx2, BgRy2 : Array[0..7] Of LongInt;
  BgEdge : Array[0..260] Of LongInt;

Const
  BgPatTab : Array[0..95] Of Byte = (
    $00,$00,$00,$00,$00,$00,$00,$00, $FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,
    $FF,$FF,$00,$00,$FF,$FF,$00,$00, $01,$02,$04,$08,$10,$20,$40,$80,
    $E0,$C1,$83,$07,$0E,$1C,$38,$70, $F0,$78,$3C,$1E,$0F,$87,$C3,$E1,
    $A5,$D2,$69,$B4,$5A,$2D,$96,$4B, $FF,$88,$88,$88,$FF,$88,$88,$88,
    $81,$42,$24,$18,$18,$24,$42,$81, $CC,$33,$CC,$33,$CC,$33,$CC,$33,
    $80,$00,$08,$00,$80,$00,$08,$00, $88,$00,$22,$00,$88,$00,$22,$00);

Const
  BgFont8 : Array[0..2047] Of Byte = (
    $00,$00,$00,$00,$00,$00,$00,$00,
    $7E,$81,$A5,$81,$BD,$99,$81,$7E,
    $7E,$FF,$DB,$FF,$C3,$E7,$FF,$7E,
    $6C,$FE,$FE,$FE,$7C,$38,$10,$00,
    $10,$38,$7C,$FE,$7C,$38,$10,$00,
    $38,$7C,$38,$FE,$FE,$7C,$38,$7C,
    $10,$10,$38,$7C,$FE,$7C,$38,$7C,
    $00,$00,$18,$3C,$3C,$18,$00,$00,
    $FF,$FF,$E7,$C3,$C3,$E7,$FF,$FF,
    $00,$3C,$66,$42,$42,$66,$3C,$00,
    $FF,$C3,$99,$BD,$BD,$99,$C3,$FF,
    $0F,$07,$0F,$7D,$CC,$CC,$CC,$78,
    $3C,$66,$66,$66,$3C,$18,$7E,$18,
    $3F,$33,$3F,$30,$30,$70,$F0,$E0,
    $7F,$63,$7F,$63,$63,$67,$E6,$C0,
    $99,$5A,$3C,$E7,$E7,$3C,$5A,$99,
    $80,$E0,$F8,$FE,$F8,$E0,$80,$00,
    $02,$0E,$3E,$FE,$3E,$0E,$02,$00,
    $18,$3C,$7E,$18,$18,$7E,$3C,$18,
    $66,$66,$66,$66,$66,$00,$66,$00,
    $7F,$DB,$DB,$7B,$1B,$1B,$1B,$00,
    $3E,$63,$38,$6C,$6C,$38,$CC,$78,
    $00,$00,$00,$00,$7E,$7E,$7E,$00,
    $18,$3C,$7E,$18,$7E,$3C,$18,$FF,
    $18,$3C,$7E,$18,$18,$18,$18,$00,
    $18,$18,$18,$18,$7E,$3C,$18,$00,
    $00,$18,$0C,$FE,$0C,$18,$00,$00,
    $00,$30,$60,$FE,$60,$30,$00,$00,
    $00,$00,$C0,$C0,$C0,$FE,$00,$00,
    $00,$24,$66,$FF,$66,$24,$00,$00,
    $00,$18,$3C,$7E,$FF,$FF,$00,$00,
    $00,$FF,$FF,$7E,$3C,$18,$00,$00,
    $00,$00,$00,$00,$00,$00,$00,$00,
    $30,$78,$78,$78,$30,$00,$30,$00,
    $6C,$6C,$6C,$00,$00,$00,$00,$00,
    $6C,$6C,$FE,$6C,$FE,$6C,$6C,$00,
    $30,$7C,$C0,$78,$0C,$F8,$30,$00,
    $00,$C6,$CC,$18,$30,$66,$C6,$00,
    $38,$6C,$38,$76,$DC,$CC,$76,$00,
    $60,$60,$C0,$00,$00,$00,$00,$00,
    $18,$30,$60,$60,$60,$30,$18,$00,
    $60,$30,$18,$18,$18,$30,$60,$00,
    $00,$66,$3C,$FF,$3C,$66,$00,$00,
    $00,$30,$30,$FC,$30,$30,$00,$00,
    $00,$00,$00,$00,$00,$30,$30,$60,
    $00,$00,$00,$FC,$00,$00,$00,$00,
    $00,$00,$00,$00,$00,$30,$30,$00,
    $06,$0C,$18,$30,$60,$C0,$80,$00,
    $7C,$C6,$C6,$C6,$C6,$C6,$7C,$00,
    $30,$70,$30,$30,$30,$30,$FC,$00,
    $78,$CC,$0C,$38,$60,$CC,$FC,$00,
    $78,$CC,$0C,$38,$0C,$CC,$78,$00,
    $1C,$3C,$6C,$CC,$FE,$0C,$1E,$00,
    $FC,$C0,$F8,$0C,$0C,$CC,$78,$00,
    $38,$60,$C0,$F8,$CC,$CC,$78,$00,
    $FC,$CC,$0C,$18,$30,$30,$30,$00,
    $78,$CC,$CC,$78,$CC,$CC,$78,$00,
    $78,$CC,$CC,$7C,$0C,$18,$70,$00,
    $00,$30,$30,$00,$00,$30,$30,$00,
    $00,$30,$30,$00,$00,$30,$30,$60,
    $18,$30,$60,$C0,$60,$30,$18,$00,
    $00,$00,$FC,$00,$00,$FC,$00,$00,
    $60,$30,$18,$0C,$18,$30,$60,$00,
    $78,$CC,$0C,$18,$30,$00,$30,$00,
    $7C,$C6,$DE,$DE,$DE,$C0,$78,$00,
    $38,$6C,$C6,$C6,$FE,$C6,$C6,$00,
    $FC,$C6,$C6,$FC,$C6,$C6,$FC,$00,
    $7C,$C6,$C6,$C0,$C0,$C6,$7C,$00,
    $F8,$CC,$C6,$C6,$C6,$CC,$F8,$00,
    $FE,$C0,$C0,$FC,$C0,$C0,$FE,$00,
    $FE,$C0,$C0,$FC,$C0,$C0,$C0,$00,
    $7C,$C6,$C0,$CE,$C6,$C6,$7E,$00,
    $C6,$C6,$C6,$FE,$C6,$C6,$C6,$00,
    $78,$30,$30,$30,$30,$30,$78,$00,
    $1E,$06,$06,$06,$C6,$C6,$7C,$00,
    $C6,$CC,$D8,$F0,$D8,$CC,$C6,$00,
    $C0,$C0,$C0,$C0,$C0,$C0,$FE,$00,
    $C6,$EE,$FE,$D6,$C6,$C6,$C6,$00,
    $C6,$E6,$F6,$DE,$CE,$C6,$C6,$00,
    $7C,$C6,$C6,$C6,$C6,$C6,$7C,$00,
    $FC,$C6,$C6,$FC,$C0,$C0,$C0,$00,
    $7C,$C6,$C6,$C6,$C6,$C6,$7C,$06,
    $FC,$C6,$C6,$FC,$C6,$C6,$C6,$00,
    $78,$CC,$60,$30,$18,$CC,$78,$00,
    $FC,$30,$30,$30,$30,$30,$30,$00,
    $C6,$C6,$C6,$C6,$C6,$C6,$7C,$00,
    $C6,$C6,$C6,$C6,$C6,$6C,$38,$00,
    $C6,$C6,$C6,$D6,$FE,$EE,$C6,$00,
    $C6,$C6,$6C,$38,$6C,$C6,$C6,$00,
    $C3,$C3,$66,$3C,$18,$18,$18,$00,
    $FE,$0C,$18,$30,$60,$C0,$FE,$00,
    $3C,$30,$30,$30,$30,$30,$3C,$00,
    $C0,$60,$30,$18,$0C,$06,$03,$00,
    $3C,$0C,$0C,$0C,$0C,$0C,$3C,$00,
    $00,$38,$6C,$C6,$00,$00,$00,$00,
    $00,$00,$00,$00,$00,$00,$00,$FF,
    $30,$30,$18,$00,$00,$00,$00,$00,
    $00,$00,$7C,$06,$7E,$C6,$7E,$00,
    $C0,$C0,$FC,$C6,$C6,$E6,$DC,$00,
    $00,$00,$7C,$C6,$C0,$C0,$7E,$00,
    $06,$06,$7E,$C6,$C6,$CE,$76,$00,
    $00,$00,$7C,$C6,$FE,$C0,$7E,$00,
    $1E,$30,$7C,$30,$30,$30,$30,$00,
    $00,$00,$7E,$C6,$CE,$76,$06,$7C,
    $C0,$C0,$FC,$C6,$C6,$C6,$C6,$00,
    $18,$00,$38,$18,$18,$18,$3C,$00,
    $18,$00,$38,$18,$18,$18,$18,$F0,
    $C0,$C0,$CC,$D8,$F0,$D8,$CC,$00,
    $38,$18,$18,$18,$18,$18,$3C,$00,
    $00,$00,$CC,$FE,$D6,$C6,$C6,$00,
    $00,$00,$FC,$C6,$C6,$C6,$C6,$00,
    $00,$00,$7C,$C6,$C6,$C6,$7C,$00,
    $00,$00,$FC,$C6,$C6,$E6,$DC,$C0,
    $00,$00,$7E,$C6,$C6,$CE,$76,$06,
    $00,$00,$6E,$70,$60,$60,$60,$00,
    $00,$00,$7C,$C0,$7C,$06,$FC,$00,
    $30,$30,$7C,$30,$30,$30,$1C,$00,
    $00,$00,$C6,$C6,$C6,$C6,$7E,$00,
    $00,$00,$C6,$C6,$C6,$6C,$38,$00,
    $00,$00,$C6,$C6,$D6,$FE,$6C,$00,
    $00,$00,$C6,$6C,$38,$6C,$C6,$00,
    $00,$00,$C6,$C6,$CE,$76,$06,$7C,
    $00,$00,$FC,$18,$30,$60,$FC,$00,
    $1C,$30,$30,$E0,$30,$30,$1C,$00,
    $18,$18,$18,$00,$18,$18,$18,$00,
    $E0,$30,$30,$1C,$30,$30,$E0,$00,
    $76,$DC,$00,$00,$00,$00,$00,$00,
    $00,$10,$38,$6C,$C6,$C6,$FE,$00,
    $78,$CC,$C0,$CC,$78,$18,$0C,$78,
    $00,$CC,$00,$CC,$CC,$CC,$7E,$00,
    $1C,$00,$78,$CC,$FC,$C0,$78,$00,
    $7E,$C3,$3C,$06,$3E,$66,$3F,$00,
    $CC,$00,$78,$0C,$7C,$CC,$7E,$00,
    $E0,$00,$78,$0C,$7C,$CC,$7E,$00,
    $30,$30,$78,$0C,$7C,$CC,$7E,$00,
    $00,$00,$78,$C0,$C0,$78,$0C,$38,
    $7E,$C3,$3C,$66,$7E,$60,$3C,$00,
    $CC,$00,$78,$CC,$FC,$C0,$78,$00,
    $E0,$00,$78,$CC,$FC,$C0,$78,$00,
    $CC,$00,$70,$30,$30,$30,$78,$00,
    $7C,$C6,$38,$18,$18,$18,$3C,$00,
    $E0,$00,$70,$30,$30,$30,$78,$00,
    $C6,$38,$6C,$C6,$FE,$C6,$C6,$00,
    $30,$30,$00,$78,$CC,$FC,$CC,$00,
    $1C,$00,$FC,$60,$78,$60,$FC,$00,
    $00,$00,$7F,$0C,$7F,$CC,$7F,$00,
    $3E,$6C,$CC,$FE,$CC,$CC,$CE,$00,
    $78,$CC,$00,$78,$CC,$CC,$78,$00,
    $00,$CC,$00,$78,$CC,$CC,$78,$00,
    $00,$E0,$00,$78,$CC,$CC,$78,$00,
    $78,$CC,$00,$CC,$CC,$CC,$7E,$00,
    $00,$E0,$00,$CC,$CC,$CC,$7E,$00,
    $00,$CC,$00,$CC,$CC,$7C,$0C,$F8,
    $C3,$18,$3C,$66,$66,$3C,$18,$00,
    $CC,$00,$CC,$CC,$CC,$CC,$78,$00,
    $18,$18,$7E,$C0,$C0,$7E,$18,$18,
    $38,$6C,$64,$F0,$60,$E6,$FC,$00,
    $CC,$CC,$78,$FC,$30,$FC,$30,$30,
    $F8,$CC,$CC,$FA,$C6,$CF,$C6,$C7,
    $0E,$1B,$18,$3C,$18,$18,$D8,$70,
    $1C,$00,$78,$0C,$7C,$CC,$7E,$00,
    $38,$00,$70,$30,$30,$30,$78,$00,
    $00,$1C,$00,$78,$CC,$CC,$78,$00,
    $00,$1C,$00,$CC,$CC,$CC,$7E,$00,
    $00,$F8,$00,$F8,$CC,$CC,$CC,$00,
    $FC,$00,$CC,$EC,$FC,$DC,$CC,$00,
    $3C,$6C,$6C,$3E,$00,$7E,$00,$00,
    $38,$6C,$6C,$38,$00,$7C,$00,$00,
    $30,$00,$30,$60,$C0,$CC,$78,$00,
    $00,$00,$00,$FC,$C0,$C0,$00,$00,
    $00,$00,$00,$FC,$0C,$0C,$00,$00,
    $C3,$C6,$CC,$DE,$33,$66,$CC,$0F,
    $C3,$C6,$CC,$DB,$37,$6F,$CF,$03,
    $18,$18,$00,$18,$18,$18,$18,$00,
    $00,$33,$66,$CC,$66,$33,$00,$00,
    $00,$CC,$66,$33,$66,$CC,$00,$00,
    $22,$88,$22,$88,$22,$88,$22,$88,
    $55,$AA,$55,$AA,$55,$AA,$55,$AA,
    $DB,$77,$DB,$EE,$DB,$77,$DB,$EE,
    $18,$18,$18,$18,$18,$18,$18,$18,
    $18,$18,$18,$18,$F8,$18,$18,$18,
    $18,$18,$F8,$18,$F8,$18,$18,$18,
    $36,$36,$36,$36,$F6,$36,$36,$36,
    $00,$00,$00,$00,$FE,$36,$36,$36,
    $00,$00,$F8,$18,$F8,$18,$18,$18,
    $36,$36,$F6,$06,$F6,$36,$36,$36,
    $36,$36,$36,$36,$36,$36,$36,$36,
    $00,$00,$FE,$06,$F6,$36,$36,$36,
    $36,$36,$F6,$06,$FE,$00,$00,$00,
    $36,$36,$36,$36,$FE,$00,$00,$00,
    $18,$18,$F8,$18,$F8,$00,$00,$00,
    $00,$00,$00,$00,$F8,$18,$18,$18,
    $18,$18,$18,$18,$1F,$00,$00,$00,
    $18,$18,$18,$18,$FF,$00,$00,$00,
    $00,$00,$00,$00,$FF,$18,$18,$18,
    $18,$18,$18,$18,$1F,$18,$18,$18,
    $00,$00,$00,$00,$FF,$00,$00,$00,
    $18,$18,$18,$18,$FF,$18,$18,$18,
    $18,$18,$1F,$18,$1F,$18,$18,$18,
    $36,$36,$36,$36,$37,$36,$36,$36,
    $36,$36,$37,$30,$3F,$00,$00,$00,
    $00,$00,$3F,$30,$37,$36,$36,$36,
    $36,$36,$F7,$00,$FF,$00,$00,$00,
    $00,$00,$FF,$00,$F7,$36,$36,$36,
    $36,$36,$37,$30,$37,$36,$36,$36,
    $00,$00,$FF,$00,$FF,$00,$00,$00,
    $36,$36,$F7,$00,$F7,$36,$36,$36,
    $18,$18,$FF,$00,$FF,$00,$00,$00,
    $36,$36,$36,$36,$FF,$00,$00,$00,
    $00,$00,$FF,$00,$FF,$18,$18,$18,
    $00,$00,$00,$00,$FF,$36,$36,$36,
    $36,$36,$36,$36,$3F,$00,$00,$00,
    $18,$18,$1F,$18,$1F,$00,$00,$00,
    $00,$00,$1F,$18,$1F,$18,$18,$18,
    $00,$00,$00,$00,$3F,$36,$36,$36,
    $36,$36,$36,$36,$FF,$36,$36,$36,
    $18,$18,$FF,$18,$FF,$18,$18,$18,
    $18,$18,$18,$18,$F8,$00,$00,$00,
    $00,$00,$00,$00,$1F,$18,$18,$18,
    $FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,
    $00,$00,$00,$00,$FF,$FF,$FF,$FF,
    $F0,$F0,$F0,$F0,$F0,$F0,$F0,$F0,
    $0F,$0F,$0F,$0F,$0F,$0F,$0F,$0F,
    $FF,$FF,$FF,$FF,$00,$00,$00,$00,
    $00,$00,$76,$DC,$C8,$DC,$76,$00,
    $00,$78,$CC,$F8,$CC,$F8,$C0,$C0,
    $00,$FC,$CC,$C0,$C0,$C0,$C0,$00,
    $00,$FE,$6C,$6C,$6C,$6C,$6C,$00,
    $FC,$CC,$60,$30,$60,$CC,$FC,$00,
    $00,$00,$7E,$D8,$D8,$D8,$70,$00,
    $00,$66,$66,$66,$66,$7C,$60,$C0,
    $00,$76,$DC,$18,$18,$18,$18,$00,
    $FC,$30,$78,$CC,$CC,$78,$30,$FC,
    $38,$6C,$C6,$FE,$C6,$6C,$38,$00,
    $38,$6C,$C6,$C6,$6C,$6C,$EE,$00,
    $1C,$30,$18,$7C,$CC,$CC,$78,$00,
    $00,$00,$7E,$DB,$DB,$7E,$00,$00,
    $06,$0C,$7E,$DB,$DB,$7E,$60,$C0,
    $38,$60,$C0,$F8,$C0,$60,$38,$00,
    $78,$CC,$CC,$CC,$CC,$CC,$CC,$00,
    $00,$FC,$00,$FC,$00,$FC,$00,$00,
    $30,$30,$FC,$30,$30,$00,$FC,$00,
    $60,$30,$18,$30,$60,$00,$FC,$00,
    $18,$30,$60,$30,$18,$00,$FC,$00,
    $0E,$1B,$1B,$18,$18,$18,$18,$18,
    $18,$18,$18,$18,$18,$D8,$D8,$70,
    $30,$30,$00,$FC,$00,$30,$30,$00,
    $00,$76,$DC,$00,$76,$DC,$00,$00,
    $38,$6C,$6C,$38,$00,$00,$00,$00,
    $00,$00,$00,$18,$18,$00,$00,$00,
    $00,$00,$00,$00,$18,$00,$00,$00,
    $0F,$0C,$0C,$0C,$EC,$6C,$3C,$1C,
    $78,$6C,$6C,$6C,$6C,$00,$00,$00,
    $70,$18,$30,$60,$78,$00,$00,$00,
    $00,$00,$3C,$3C,$3C,$3C,$00,$00,
    $00,$00,$00,$00,$00,$00,$00,$00
  );

{ ---- palette ---- }

Function BgEga(I : LongInt) : LongInt;
Var R, G, B : LongInt;
Begin
  R := (((I Shr 2) And 1) * 2 + ((I Shr 5) And 1)) * 85;
  G := (((I Shr 1) And 1) * 2 + ((I Shr 4) And 1)) * 85;
  B := ((I And 1) * 2 + ((I Shr 3) And 1)) * 85;
  BgEga := (R Shl 16) Or (G Shl 8) Or B;
End;

{ pixel ecran d'une couleur 0x00RRGGBB selon le format du fb }
Function BgPack(C : LongInt) : LongInt;
Var R, G, B : LongInt;
Begin
  R := (C Shr 16) And 255;
  G := (C Shr 8) And 255;
  B := C And 255;
  If BgBpp = 8 Then BgPack := C
  Else
    BgPack := ((R Shr (8 - BgRl)) Shl BgRo) Or
              ((G Shr (8 - BgGl)) Shl BgGo) Or
              ((B Shr (8 - BgBl)) Shl BgBo);
End;

Procedure BgMakeFin;
Var I : LongInt;
Begin
  For I := 0 To 15 Do BgFin[I] := BgPack(BgDac[BgPal[I]]);
End;

Procedure BgDefPal;
Const Std : Array[0..15] Of Byte =
    (0, 1, 2, 3, 4, 5, 20, 7, 56, 57, 58, 59, 60, 61, 62, 63);
Var I : LongInt;
Begin
  For I := 0 To 63 Do BgDac[I] := BgEga(I);
  For I := 64 To 255 Do BgDac[I] := 0;
  For I := 0 To 15 Do BgPal[I] := Std[I];
  BgMakeFin;
End;

{ ---- zones et ecretage ---- }

Procedure BgSetClip;
Begin
  If BgClip Then
  Begin
    BgCx1 := BgVx; BgCy1 := BgVy; BgCx2 := BgVx2; BgCy2 := BgVy2;
  End
  Else
  Begin
    BgCx1 := 0; BgCy1 := 0; BgCx2 := BgW - 1; BgCy2 := BgH - 1;
  End;
End;

{ rectangles modifies : au plus 8, fusionnes quand ils se touchent ; BgDx1..
  BgDy2 = rectangle englobant (une seule commande de mise a jour) }
Procedure BgDirt(X1, Y1, X2, Y2 : LongInt);
Var T, I, J, Best, Grow, G : LongInt; Again : Boolean;
Begin
  If X1 > X2 Then Begin T := X1; X1 := X2; X2 := T; End;
  If Y1 > Y2 Then Begin T := Y1; Y1 := Y2; Y2 := T; End;
  If X1 < 0 Then X1 := 0;
  If Y1 < 0 Then Y1 := 0;
  If X2 >= BgW Then X2 := BgW - 1;
  If Y2 >= BgH Then Y2 := BgH - 1;
  If (X1 > X2) Or (Y1 > Y2) Then Exit;
  If BgAct <> BgVis Then Exit;
  If Not BgDirty Then
  Begin
    BgDirty := True;
    BgRn := 0;
    BgDx1 := X1; BgDy1 := Y1; BgDx2 := X2; BgDy2 := Y2;
  End
  Else
  Begin
    If X1 < BgDx1 Then BgDx1 := X1;
    If Y1 < BgDy1 Then BgDy1 := Y1;
    If X2 > BgDx2 Then BgDx2 := X2;
    If Y2 > BgDy2 Then BgDy2 := Y2;
  End;
  { fusion avec un rectangle qui touche (marge de 4 pixels) }
  For I := 0 To BgRn - 1 Do
    If (X1 <= BgRx2[I] + 4) And (X2 >= BgRx1[I] - 4) And
       (Y1 <= BgRy2[I] + 4) And (Y2 >= BgRy1[I] - 4) Then
    Begin
      If BgRx1[I] < X1 Then X1 := BgRx1[I];
      If BgRy1[I] < Y1 Then Y1 := BgRy1[I];
      If BgRx2[I] > X2 Then X2 := BgRx2[I];
      If BgRy2[I] > Y2 Then Y2 := BgRy2[I];
      BgRx1[I] := X1; BgRy1[I] := Y1; BgRx2[I] := X2; BgRy2[I] := Y2;
      { le rectangle agrandi peut en toucher d'autres }
      Again := True;
      While Again Do
      Begin
        Again := False;
        For J := 0 To BgRn - 1 Do
          If (J <> I) And (BgRx1[J] <= BgRx2[I] + 4) And
             (BgRx2[J] >= BgRx1[I] - 4) And (BgRy1[J] <= BgRy2[I] + 4) And
             (BgRy2[J] >= BgRy1[I] - 4) And (BgRx2[J] >= BgRx1[J]) Then
          Begin
            If BgRx1[J] < BgRx1[I] Then BgRx1[I] := BgRx1[J];
            If BgRy1[J] < BgRy1[I] Then BgRy1[I] := BgRy1[J];
            If BgRx2[J] > BgRx2[I] Then BgRx2[I] := BgRx2[J];
            If BgRy2[J] > BgRy2[I] Then BgRy2[I] := BgRy2[J];
            BgRx2[J] := -1; BgRx1[J] := 0;   { rectangle vide }
            Again := True;
          End;
      End;
      Exit;
    End;
  { nouveau rectangle : place libre ou fusion la moins couteuse }
  For I := 0 To BgRn - 1 Do
    If BgRx2[I] < BgRx1[I] Then
    Begin
      BgRx1[I] := X1; BgRy1[I] := Y1; BgRx2[I] := X2; BgRy2[I] := Y2;
      Exit;
    End;
  If BgRn < 8 Then
  Begin
    BgRx1[BgRn] := X1; BgRy1[BgRn] := Y1;
    BgRx2[BgRn] := X2; BgRy2[BgRn] := Y2;
    Inc(BgRn);
    Exit;
  End;
  Best := 0; Grow := 2147483647;
  For I := 0 To 7 Do
  Begin
    G := (Abs(BgRx1[I] - X1) + Abs(BgRx2[I] - X2)) *
         (Abs(BgRy1[I] - Y1) + Abs(BgRy2[I] - Y2));
    If G < Grow Then Begin Grow := G; Best := I; End;
  End;
  If X1 < BgRx1[Best] Then BgRx1[Best] := X1;
  If Y1 < BgRy1[Best] Then BgRy1[Best] := Y1;
  If X2 > BgRx2[Best] Then BgRx2[Best] := X2;
  If Y2 > BgRy2[Best] Then BgRy2[Best] := Y2;
End;

{ ---- memoire ---- }

Procedure BgFillSpan(Dst, Cnt, Val : LongInt);
Begin
  If Cnt <= 0 Then Exit;
  asm
    push edi
    mov edi, Dst
    mov ecx, Cnt
    mov eax, Val
    cld
    rep stosb
    pop edi
  end;
End;

Procedure BgCopySpan(Src, Dst, Cnt : LongInt);
Begin
  If Cnt <= 0 Then Exit;
  asm
    push esi
    push edi
    mov esi, Src
    mov edi, Dst
    mov ecx, Cnt
    cld
    rep movsb
    pop edi
    pop esi
  end;
End;

{ pixel (absolu, ecrete) selon le mode d'ecriture }
Procedure BgPut(X, Y, C : LongInt);
Var A : LongInt;
Begin
  If (X < BgCx1) Or (X > BgCx2) Or (Y < BgCy1) Or (Y > BgCy2) Then Exit;
  A := BgBuf + Y * BgW + X;
  Case BgMode Of
    0 : Mem[0:A] := C;
    1 : Mem[0:A] := (Mem[0:A] Xor C) And 255;
    2 : Mem[0:A] := (Mem[0:A] Or C) And 255;
    3 : Mem[0:A] := (Mem[0:A] And C) And 255;
  Else
    Mem[0:A] := (Not C) And 15;
  End;
End;

{ pixel en mode copie (remplissages) }
Procedure BgPutC(X, Y, C : LongInt);
Begin
  If (X < BgCx1) Or (X > BgCx2) Or (Y < BgCy1) Or (Y > BgCy2) Then Exit;
  Mem[0:BgBuf + Y * BgW + X] := C;
End;

{ trait horizontal plein en mode copie, ecrete }
Procedure BgSpan(X1, X2, Y, C : LongInt);
Begin
  If (Y < BgCy1) Or (Y > BgCy2) Then Exit;
  If X1 < BgCx1 Then X1 := BgCx1;
  If X2 > BgCx2 Then X2 := BgCx2;
  If X1 > X2 Then Exit;
  BgFillSpan(BgBuf + Y * BgW + X1, X2 - X1 + 1, C);
End;

{ trait horizontal avec le motif de remplissage courant }
Procedure BgPatSpan(X1, X2, Y : LongInt);
Var X, Bits, Row : LongInt;
Begin
  If (Y < BgCy1) Or (Y > BgCy2) Then Exit;
  If X1 < BgCx1 Then X1 := BgCx1;
  If X2 > BgCx2 Then X2 := BgCx2;
  If X1 > X2 Then Exit;
  If BgFillPat = 1 Then
  Begin
    BgFillSpan(BgBuf + Y * BgW + X1, X2 - X1 + 1, BgFillCol);
    Exit;
  End;
  If BgFillPat = 0 Then
  Begin
    BgFillSpan(BgBuf + Y * BgW + X1, X2 - X1 + 1, 0);
    Exit;
  End;
  Row := Y And 7;
  If BgFillPat = 12 Then Bits := BgUser[Row]
  Else Bits := BgPatTab[BgFillPat * 8 + Row];
  For X := X1 To X2 Do
    If (Bits And (128 Shr (X And 7))) <> 0 Then
      Mem[0:BgBuf + Y * BgW + X] := BgFillCol
    Else
      Mem[0:BgBuf + Y * BgW + X] := 0;
End;

{ ---- traits ---- }

Function BgLinePat : LongInt;
Begin
  Case BgLnSt Of
    0 : BgLinePat := $FFFF;
    1 : BgLinePat := $CCCC;
    2 : BgLinePat := $FC78;
    3 : BgLinePat := $F8F8;
  Else
    BgLinePat := BgLnPat And $FFFF;
  End;
End;

Procedure BgLine1(X0, Y0, X1, Y1 : LongInt);
Var Dx, Dy, Sx, Sy, Er, E2, K, Pat : LongInt;
Begin
  Pat := BgLinePat;
  If (Pat = $FFFF) And (BgMode = 0) And (Y0 = Y1) Then
  Begin
    If X0 > X1 Then BgSpan(X1, X0, Y0, BgColor)
    Else BgSpan(X0, X1, Y0, BgColor);
    Exit;
  End;
  Dx := X1 - X0; If Dx < 0 Then Dx := -Dx;
  Dy := Y1 - Y0; If Dy < 0 Then Dy := -Dy;
  If X0 < X1 Then Sx := 1 Else Sx := -1;
  If Y0 < Y1 Then Sy := 1 Else Sy := -1;
  Er := Dx - Dy;
  K := 0;
  While True Do
  Begin
    If (Pat = $FFFF) Or ((Pat And (32768 Shr (K And 15))) <> 0) Then
      BgPut(X0, Y0, BgColor);
    Inc(K);
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

Procedure BgLine(X0, Y0, X1, Y1 : LongInt);
Begin
  BgDirt(X0 - 2, Y0 - 2, X1 + 2, Y1 + 2);
  BgLine1(X0, Y0, X1, Y1);
  If BgLnTh >= 3 Then
  Begin
    If Abs(X1 - X0) >= Abs(Y1 - Y0) Then
    Begin
      BgLine1(X0, Y0 - 1, X1, Y1 - 1);
      BgLine1(X0, Y0 + 1, X1, Y1 + 1);
    End
    Else
    Begin
      BgLine1(X0 - 1, Y0, X1 - 1, Y1);
      BgLine1(X0 + 1, Y0, X1 + 1, Y1);
    End;
  End;
End;

Procedure BgRect(X1, Y1, X2, Y2 : LongInt);
Var T : LongInt;
Begin
  If X1 > X2 Then Begin T := X1; X1 := X2; X2 := T; End;
  If Y1 > Y2 Then Begin T := Y1; Y1 := Y2; Y2 := T; End;
  BgDirt(X1 - 2, Y1 - 2, X2 + 2, Y2 + 2);
  BgLine1(X1, Y1, X2, Y1);
  If Y2 > Y1 Then BgLine1(X1, Y2, X2, Y2);
  If Y2 - Y1 >= 2 Then
  Begin
    BgLine1(X1, Y1 + 1, X1, Y2 - 1);
    If X2 > X1 Then BgLine1(X2, Y1 + 1, X2, Y2 - 1);
  End;
End;

{ ---- ellipses : etendue de la demi-ligne Y (0..Ry) ---- }

Function BgHalf(Rx, Ry, Y : LongInt) : LongInt;
Var V : Double;
Begin
  If Ry <= 0 Then Begin BgHalf := Rx; Exit; End;
  If Y >= Ry Then Begin BgHalf := 0; Exit; End;
  V := (1.0 * Rx) * (1.0 * Rx) *
       (1.0 - (1.0 * Y) * (1.0 * Y) / ((1.0 * Ry) * (1.0 * Ry)));
  BgHalf := Trunc(Sqrt(V) + 0.5);
End;

Procedure BgEllipseOut(Cx, Cy, Rx, Ry : LongInt);
Var Y, A, B, X : LongInt;
Begin
  If Rx < 0 Then Rx := 0;
  If Ry < 0 Then Ry := 0;
  BgDirt(Cx - Rx - 1, Cy - Ry - 1, Cx + Rx + 1, Cy + Ry + 1);
  If Ry = 0 Then
  Begin
    For X := Cx - Rx To Cx + Rx Do BgPut(X, Cy, BgColor);
    Exit;
  End;
  For Y := 0 To Ry Do
  Begin
    A := BgHalf(Rx, Ry, Y);
    If Y = Ry Then B := -1 Else B := BgHalf(Rx, Ry, Y + 1);
    If B < 0 Then
    Begin
      { ligne du sommet : tout le segment, une seule fois }
      For X := -A To A Do
      Begin
        BgPut(Cx + X, Cy - Y, BgColor);
        If Y > 0 Then BgPut(Cx + X, Cy + Y, BgColor);
      End;
    End
    Else
      For X := B To A Do
      Begin
        BgPut(Cx + X, Cy - Y, BgColor);
        If X > 0 Then BgPut(Cx - X, Cy - Y, BgColor);
        If Y > 0 Then
        Begin
          BgPut(Cx + X, Cy + Y, BgColor);
          If X > 0 Then BgPut(Cx - X, Cy + Y, BgColor);
        End;
      End;
  End;
End;

Procedure BgEllipseFill(Cx, Cy, Rx, Ry : LongInt);
Var Y, A : LongInt;
Begin
  If Rx < 0 Then Rx := 0;
  If Ry < 0 Then Ry := 0;
  BgDirt(Cx - Rx - 1, Cy - Ry - 1, Cx + Rx + 1, Cy + Ry + 1);
  For Y := 0 To Ry Do
  Begin
    A := BgHalf(Rx, Ry, Y);
    BgPatSpan(Cx - A, Cx + A, Cy - Y);
    If Y > 0 Then BgPatSpan(Cx - A, Cx + A, Cy + Y);
  End;
End;

Function BgRnd(D : Double) : LongInt;
Begin
  If D >= 0 Then BgRnd := Trunc(D + 0.5) Else BgRnd := -Trunc(0.5 - D);
End;

{ points d'un arc (degres, sens trigonometrique) dans BgPtsX/Y ; rend N }
Function BgArcPts(Cx, Cy, St, En, Rx, Ry, First : LongInt) : LongInt;
Var Span, N, I : LongInt; A : Double;
Begin
  St := St Mod 360; If St < 0 Then St := St + 360;
  En := En Mod 360; If En < 0 Then En := En + 360;
  If En <= St Then En := En + 360;
  Span := En - St;
  If Span > 360 Then Span := 360;
  N := 0;
  For I := 0 To Span Do
  Begin
    A := (St + I) * 3.14159265358979 / 180.0;
    BgPtsX[First + N] := Cx + BgRnd(Rx * Cos(A));
    BgPtsY[First + N] := Cy - BgRnd(Ry * Sin(A));
    Inc(N);
  End;
  BgArcPts := N;
End;

{ remplissage d'un polygone (sommets BgPtsX/Y[0..N-1]), motif courant }
Procedure BgPolyFill(N : LongInt);
Var Ymin, Ymax, Y, I, J, K, Cnt, X1, Y1, X2, Y2, T : LongInt;
Begin
  If N < 3 Then Exit;
  Ymin := BgPtsY[0]; Ymax := Ymin;
  For I := 1 To N - 1 Do
  Begin
    If BgPtsY[I] < Ymin Then Ymin := BgPtsY[I];
    If BgPtsY[I] > Ymax Then Ymax := BgPtsY[I];
  End;
  If Ymin < BgCy1 Then Ymin := BgCy1;
  If Ymax > BgCy2 Then Ymax := BgCy2;
  For Y := Ymin To Ymax Do
  Begin
    Cnt := 0;
    For I := 0 To N - 1 Do
    Begin
      J := (I + 1) Mod N;
      X1 := BgPtsX[I]; Y1 := BgPtsY[I];
      X2 := BgPtsX[J]; Y2 := BgPtsY[J];
      If Y1 = Y2 Then Continue;
      If Y1 > Y2 Then
      Begin
        T := X1; X1 := X2; X2 := T;
        T := Y1; Y1 := Y2; Y2 := T;
      End;
      If (Y >= Y1) And (Y < Y2) And (Cnt < 255) Then
      Begin
        BgEdge[Cnt] := X1 + ((Y - Y1) * (X2 - X1) * 2 + (Y2 - Y1)) Div
          (2 * (Y2 - Y1));
        Inc(Cnt);
      End;
    End;
    For I := 1 To Cnt - 1 Do
    Begin
      T := BgEdge[I];
      K := I - 1;
      While (K >= 0) And (BgEdge[K] > T) Do
      Begin
        BgEdge[K + 1] := BgEdge[K];
        Dec(K);
      End;
      BgEdge[K + 1] := T;
    End;
    I := 0;
    While I + 1 < Cnt Do
    Begin
      BgPatSpan(BgEdge[I], BgEdge[I + 1], Y);
      I := I + 2;
    End;
  End;
End;

Procedure BgPolyBounds(N : LongInt);
Var I, X1, Y1, X2, Y2 : LongInt;
Begin
  If N < 1 Then Exit;
  X1 := BgPtsX[0]; X2 := X1; Y1 := BgPtsY[0]; Y2 := Y1;
  For I := 1 To N - 1 Do
  Begin
    If BgPtsX[I] < X1 Then X1 := BgPtsX[I];
    If BgPtsX[I] > X2 Then X2 := BgPtsX[I];
    If BgPtsY[I] < Y1 Then Y1 := BgPtsY[I];
    If BgPtsY[I] > Y2 Then Y2 := BgPtsY[I];
  End;
  BgDirt(X1 - 2, Y1 - 2, X2 + 2, Y2 + 2);
End;

{ ---- interface BGI : dessin ---- }

Procedure BgChar(X, Y, Ch, Size, Dir : LongInt);
Var R, C, Bits, Gp, Px, Py, Dx, Dy : LongInt;
Begin
  Gp := (Ch And 255) * 8;
  For R := 0 To 7 Do
  Begin
    Bits := BgFont8[Gp + R];
    If Bits = 0 Then Continue;
    For C := 0 To 7 Do
      If (Bits And (128 Shr C)) <> 0 Then
      Begin
        If Dir = 0 Then
        Begin
          Px := X + C * Size; Py := Y + R * Size;
        End
        Else
        Begin
          Px := X + R * Size; Py := Y - (C + 1) * Size + 1;
        End;
        If Size = 1 Then BgPut(Px, Py, BgColor)
        Else
          For Dy := 0 To Size - 1 Do
            For Dx := 0 To Size - 1 Do BgPut(Px + Dx, Py + Dy, BgColor);
      End;
  End;
End;

Procedure BgText(X, Y : LongInt; Const S : String);
Var I, W, H, X0, Y0 : LongInt;
Begin
  W := Length(S) * 8 * BgSize;
  H := 8 * BgSize;
  If BgDir = 0 Then
  Begin
    Case BgHj Of
      1 : X0 := X - W Div 2;
      2 : X0 := X - W;
    Else
      X0 := X;
    End;
    Case BgVj Of
      0 : Y0 := Y - H + 1;
      1 : Y0 := Y - H Div 2;
    Else
      Y0 := Y;
    End;
    BgDirt(X0, Y0, X0 + W, Y0 + H);
    For I := 1 To Length(S) Do
      BgChar(X0 + (I - 1) * 8 * BgSize, Y0, Ord(S[I]), BgSize, 0);
  End
  Else
  Begin
    Case BgHj Of
      1 : Y0 := Y + W Div 2;
      2 : Y0 := Y + W;
    Else
      Y0 := Y;
    End;
    Case BgVj Of
      0 : X0 := X - H + 1;
      1 : X0 := X - H Div 2;
    Else
      X0 := X;
    End;
    BgDirt(X0, Y0 - W, X0 + H, Y0);
    For I := 1 To Length(S) Do
      BgChar(X0, Y0 - (I - 1) * 8 * BgSize, Ord(S[I]), BgSize, 1);
  End;
End;

Procedure SetColor_G(Color : Word);
Begin
  BgColor := Color And 15;
End;

Function GetColor_G : Word;
Begin
  GetColor_G := BgColor;
End;

Procedure SetBkColor_G(Color : Word);
Begin
  BgBk := Color And 15;
  BgPal[0] := BgPal[BgBk];
  BgMakeFin;
  BgDirt(0, 0, BgW - 1, BgH - 1);
End;

Function GetBkColor_G : Word;
Begin
  GetBkColor_G := BgBk;
End;

Procedure SetWriteMode_G(WriteMode : Integer);
Begin
  BgMode := WriteMode;
  If (BgMode < 0) Or (BgMode > 4) Then BgMode := 0;
End;

Procedure SetLineStyle_G(LineStyle, Pattern, Thickness : Word);
Begin
  If LineStyle > 4 Then Begin BgRes := -11; Exit; End;
  BgLnSt := LineStyle;
  BgLnPat := Pattern;
  If Thickness >= 3 Then BgLnTh := 3 Else BgLnTh := 1;
End;

Procedure GetLineSettings_G(Var LineInfo : LineSettingsType);
Begin
  LineInfo.LineStyle := BgLnSt;
  LineInfo.Pattern := BgLnPat;
  LineInfo.Thickness := BgLnTh;
End;

Procedure SetFillStyle_G(Pattern, Color : Word);
Begin
  If (Pattern > 12) Or ((Pattern = 12) And False) Then
  Begin
    BgRes := -11;
    Exit;
  End;
  BgFillPat := Pattern;
  BgFillCol := Color And 15;
End;

Procedure SetFillPattern_G(Var Pattern; Color : Word);
Var I, A : LongInt;
Begin
  A := LongInt(@Pattern);
  For I := 0 To 7 Do BgUser[I] := Mem[0:A + I];
  BgFillPat := 12;
  BgFillCol := Color And 15;
End;

Procedure GetFillSettings_G(Var FillInfo : FillSettingsType);
Begin
  FillInfo.Pattern := BgFillPat;
  FillInfo.Color := BgFillCol;
End;

Procedure GetFillPattern_G(Var FillPattern : FillPatternType);
Var I : LongInt;
Begin
  For I := 0 To 7 Do
    If BgFillPat = 12 Then FillPattern[I + 1] := BgUser[I]
    Else FillPattern[I + 1] := BgPatTab[BgFillPat * 8 + I];
End;

Procedure SetViewPort_G(X1, Y1, X2, Y2 : Integer; Clip : Boolean);
Begin
  If (X1 < 0) Or (Y1 < 0) Or (X2 >= BgW) Or (Y2 >= BgH) Or (X2 < X1) Or
     (Y2 < Y1) Then
  Begin
    BgRes := -11;
    Exit;
  End;
  BgVx := X1; BgVy := Y1; BgVx2 := X2; BgVy2 := Y2;
  BgClip := Clip;
  BgSetClip;
  BgCpx := 0; BgCpy := 0;
End;

Procedure GetViewSettings_G(Var ViewPort : ViewPortType);
Begin
  ViewPort.X1 := BgVx; ViewPort.Y1 := BgVy;
  ViewPort.X2 := BgVx2; ViewPort.Y2 := BgVy2;
  ViewPort.Clip := BgClip;
End;

Procedure ClearViewPort_G;
Var Y : LongInt;
Begin
  BgDirt(BgVx, BgVy, BgVx2, BgVy2);
  For Y := BgVy To BgVy2 Do
    BgFillSpan(BgBuf + Y * BgW + BgVx, BgVx2 - BgVx + 1, 0);
  BgCpx := 0; BgCpy := 0;
End;

Procedure ClearDevice_G;
Begin
  BgDirt(0, 0, BgW - 1, BgH - 1);
  BgFillSpan(BgBuf, BgW * BgH, 0);
  BgCpx := 0; BgCpy := 0;
End;

Procedure PutPixel_G(X, Y : Integer; Pixel : Word);
Begin
  X := X + BgVx; Y := Y + BgVy;
  BgDirt(X, Y, X, Y);
  BgPut(X, Y, Pixel And 15);
End;

Function GetPixel_G(X, Y : Integer) : Word;
Begin
  X := X + BgVx; Y := Y + BgVy;
  If (X < 0) Or (Y < 0) Or (X >= BgW) Or (Y >= BgH) Then GetPixel_G := 0
  Else GetPixel_G := Mem[0:BgBuf + Y * BgW + X];
End;

Procedure Line_G(X1, Y1, X2, Y2 : Integer);
Begin
  BgLine(X1 + BgVx, Y1 + BgVy, X2 + BgVx, Y2 + BgVy);
End;

Procedure MoveTo_G(X, Y : Integer);
Begin
  BgCpx := X; BgCpy := Y;
End;

Procedure MoveRel_G(Dx, Dy : Integer);
Begin
  BgCpx := BgCpx + Dx; BgCpy := BgCpy + Dy;
End;

Procedure LineTo_G(X, Y : Integer);
Begin
  BgLine(BgCpx + BgVx, BgCpy + BgVy, X + BgVx, Y + BgVy);
  BgCpx := X; BgCpy := Y;
End;

Procedure LineRel_G(Dx, Dy : Integer);
Begin
  LineTo_G(BgCpx + Dx, BgCpy + Dy);
End;

Function GetX_G : Integer;
Begin
  GetX_G := BgCpx;
End;

Function GetY_G : Integer;
Begin
  GetY_G := BgCpy;
End;

Function GetMaxX_G : Integer;
Begin
  GetMaxX_G := BgW - 1;
End;

Function GetMaxY_G : Integer;
Begin
  GetMaxY_G := BgH - 1;
End;

Function GetMaxColor_G : Word;
Begin
  GetMaxColor_G := 15;
End;

Procedure Rectangle_G(X1, Y1, X2, Y2 : Integer);
Begin
  BgRect(X1 + BgVx, Y1 + BgVy, X2 + BgVx, Y2 + BgVy);
  If BgLnTh >= 3 Then
  Begin
    BgRect(X1 + BgVx - 1, Y1 + BgVy - 1, X2 + BgVx + 1, Y2 + BgVy + 1);
    BgRect(X1 + BgVx + 1, Y1 + BgVy + 1, X2 + BgVx - 1, Y2 + BgVy - 1);
  End;
End;

Procedure Bar_G(X1, Y1, X2, Y2 : Integer);
Var T, Y : LongInt;
Begin
  X1 := X1 + BgVx; X2 := X2 + BgVx;
  Y1 := Y1 + BgVy; Y2 := Y2 + BgVy;
  If X1 > X2 Then Begin T := X1; X1 := X2; X2 := T; End;
  If Y1 > Y2 Then Begin T := Y1; Y1 := Y2; Y2 := T; End;
  BgDirt(X1, Y1, X2, Y2);
  For Y := Y1 To Y2 Do BgPatSpan(X1, X2, Y);
End;

Procedure Bar3D_G(X1, Y1, X2, Y2 : Integer; Depth : Word; Top : Boolean);
Var X, Y : LongInt;
Begin
  Bar_G(X1, Y1, X2, Y2);
  X := X1 + BgVx; Y := Y1 + BgVy;
  Rectangle_G(X1, Y1, X2, Y2);
  If Depth > 0 Then
  Begin
    BgLine(X2 + BgVx, Y1 + BgVy, X2 + BgVx + Depth, Y1 + BgVy - Depth);
    BgLine(X2 + BgVx + Depth, Y1 + BgVy - Depth, X2 + BgVx + Depth,
           Y2 + BgVy - Depth);
    BgLine(X2 + BgVx + Depth, Y2 + BgVy - Depth, X2 + BgVx, Y2 + BgVy);
    If Top Then
    Begin
      BgLine(X1 + BgVx, Y1 + BgVy, X1 + BgVx + Depth, Y1 + BgVy - Depth);
      BgLine(X1 + BgVx + Depth, Y1 + BgVy - Depth, X2 + BgVx + Depth,
             Y1 + BgVy - Depth);
    End;
  End;
End;

Function BgS16(V : LongInt) : LongInt;
Begin
  V := V And $FFFF;
  If V > 32767 Then V := V - 65536;
  BgS16 := V;
End;

Procedure BgLoadPoly(N : Word; Var P);
Var I, A : LongInt;
Begin
  A := LongInt(@P);
  If N > 400 Then N := 400;
  For I := 0 To N - 1 Do
  Begin
    BgPtsX[I] := BgS16(MemW[0:A + I * 4]) + BgVx;
    BgPtsY[I] := BgS16(MemW[0:A + I * 4 + 2]) + BgVy;
  End;
End;

Procedure DrawPoly_G(NumPoints : Word; Var PolyPoints);
Var I : LongInt;
Begin
  If NumPoints < 1 Then Exit;
  If NumPoints > 400 Then NumPoints := 400;
  BgLoadPoly(NumPoints, PolyPoints);
  BgPolyBounds(NumPoints);
  If NumPoints = 1 Then BgPut(BgPtsX[0], BgPtsY[0], BgColor);
  For I := 0 To NumPoints - 2 Do
    BgLine(BgPtsX[I], BgPtsY[I], BgPtsX[I + 1], BgPtsY[I + 1]);
End;

Procedure FillPoly_G(NumPoints : Word; Var PolyPoints);
Var I : LongInt;
Begin
  If NumPoints < 1 Then Exit;
  If NumPoints > 400 Then NumPoints := 400;
  BgLoadPoly(NumPoints, PolyPoints);
  BgPolyBounds(NumPoints);
  BgPolyFill(NumPoints);
  For I := 0 To NumPoints - 1 Do
    BgLine(BgPtsX[I], BgPtsY[I], BgPtsX[(I + 1) Mod NumPoints],
           BgPtsY[(I + 1) Mod NumPoints]);
End;

Procedure Ellipse_G(X, Y : Integer; StAngle, EndAngle, XRadius,
    YRadius : Word);
Var N, I : LongInt;
Begin
  X := X + BgVx; Y := Y + BgVy;
  If (StAngle = 0) And (EndAngle >= 360) Then
    BgEllipseOut(X, Y, XRadius, YRadius)
  Else
  Begin
    N := BgArcPts(X, Y, StAngle, EndAngle, XRadius, YRadius, 0);
    BgPolyBounds(N);
    For I := 0 To N - 2 Do
      BgLine(BgPtsX[I], BgPtsY[I], BgPtsX[I + 1], BgPtsY[I + 1]);
    BgArc.X := X - BgVx; BgArc.Y := Y - BgVy;
    BgArc.XStart := BgPtsX[0] - BgVx; BgArc.YStart := BgPtsY[0] - BgVy;
    BgArc.XEnd := BgPtsX[N - 1] - BgVx; BgArc.YEnd := BgPtsY[N - 1] - BgVy;
  End;
End;

Procedure Circle_G(X, Y : Integer; Radius : Word);
Begin
  Ellipse_G(X, Y, 0, 360, Radius, Radius);
End;

Procedure Arc_G(X, Y : Integer; StAngle, EndAngle, Radius : Word);
Begin
  Ellipse_G(X, Y, StAngle, EndAngle, Radius, Radius);
End;

Procedure FillEllipse_G(X, Y : Integer; XRadius, YRadius : Word);
Begin
  X := X + BgVx; Y := Y + BgVy;
  BgEllipseFill(X, Y, XRadius, YRadius);
  BgEllipseOut(X, Y, XRadius, YRadius);
End;

Procedure Sector_G(X, Y : Integer; StAngle, EndAngle, XRadius,
    YRadius : Word);
Var N, I : LongInt;
Begin
  X := X + BgVx; Y := Y + BgVy;
  BgPtsX[0] := X; BgPtsY[0] := Y;
  N := BgArcPts(X, Y, StAngle, EndAngle, XRadius, YRadius, 1) + 1;
  BgPolyBounds(N);
  BgPolyFill(N);
  For I := 0 To N - 1 Do
    BgLine(BgPtsX[I], BgPtsY[I], BgPtsX[(I + 1) Mod N],
           BgPtsY[(I + 1) Mod N]);
End;

Procedure PieSlice_G(X, Y : Integer; StAngle, EndAngle, Radius : Word);
Begin
  Sector_G(X, Y, StAngle, EndAngle, Radius, Radius);
End;

Procedure GetArcCoords_G(Var ArcCoords : ArcCoordsType);
Begin
  ArcCoords := BgArc;
End;

Procedure GetAspectRatio_G(Var XAsp, YAsp : Word);
Begin
  XAsp := 10000; YAsp := 10000;
End;

Procedure SetAspectRatio_G(XAsp, YAsp : Word);
Begin
End;

Procedure FloodFill_G(X, Y : Integer; Border : Word);
Var Mk, Sp, Sx, Sy, Xl, Xr, I, Yy, N : LongInt; Stk : ^LongInt;
    Ok : Boolean;
Begin
  X := X + BgVx; Y := Y + BgVy;
  If (X < BgCx1) Or (X > BgCx2) Or (Y < BgCy1) Or (Y > BgCy2) Then Exit;
  Border := Border And 15;
  If Mem[0:BgBuf + Y * BgW + X] = Border Then Exit;
  N := BgW * BgH;
  GetMem(Mk, N);
  GetMem(Stk, 16384 * 8);
  If (Mk = 0) Or (LongInt(Stk) = 0) Then
  Begin
    BgRes := -7;
    Exit;
  End;
  BgFillSpan(Mk, N, 0);
  Sp := 0;
  MemL[0:LongInt(Stk)] := X; MemL[0:LongInt(Stk) + 4] := Y; Sp := 1;
  BgDirt(BgCx1, BgCy1, BgCx2, BgCy2);
  While Sp > 0 Do
  Begin
    Dec(Sp);
    Sx := MemL[0:LongInt(Stk) + Sp * 8];
    Sy := MemL[0:LongInt(Stk) + Sp * 8 + 4];
    If (Sy < BgCy1) Or (Sy > BgCy2) Then Continue;
    If Mem[0:Mk + Sy * BgW + Sx] <> 0 Then Continue;
    If Mem[0:BgBuf + Sy * BgW + Sx] = Border Then Continue;
    Xl := Sx;
    While (Xl > BgCx1) And (Mem[0:BgBuf + Sy * BgW + Xl - 1] <> Border) And
          (Mem[0:Mk + Sy * BgW + Xl - 1] = 0) Do Dec(Xl);
    Xr := Sx;
    While (Xr < BgCx2) And (Mem[0:BgBuf + Sy * BgW + Xr + 1] <> Border) And
          (Mem[0:Mk + Sy * BgW + Xr + 1] = 0) Do Inc(Xr);
    BgFillSpan(Mk + Sy * BgW + Xl, Xr - Xl + 1, 1);
    For Yy := Sy - 1 To Sy + 1 Do
      If (Yy <> Sy) And (Yy >= BgCy1) And (Yy <= BgCy2) Then
      Begin
        I := Xl;
        While I <= Xr Do
        Begin
          If (Mem[0:BgBuf + Yy * BgW + I] <> Border) And
             (Mem[0:Mk + Yy * BgW + I] = 0) Then
          Begin
            If Sp < 16383 Then
            Begin
              MemL[0:LongInt(Stk) + Sp * 8] := I;
              MemL[0:LongInt(Stk) + Sp * 8 + 4] := Yy;
              Inc(Sp);
            End;
            While (I <= Xr) And (Mem[0:BgBuf + Yy * BgW + I] <> Border) Do
              Inc(I);
          End
          Else Inc(I);
        End;
      End;
  End;
  { remplissage selon le motif }
  For Yy := BgCy1 To BgCy2 Do
  Begin
    I := BgCx1;
    While I <= BgCx2 Do
    Begin
      If Mem[0:Mk + Yy * BgW + I] <> 0 Then
      Begin
        Xl := I;
        While (I <= BgCx2) And (Mem[0:Mk + Yy * BgW + I] <> 0) Do Inc(I);
        BgPatSpan(Xl, I - 1, Yy);
      End
      Else Inc(I);
    End;
  End;
  FreeMem(Mk, N);
  FreeMem(Stk, 16384 * 8);
End;

{ ---- texte ---- }

Procedure SetTextStyle_G(Font, Direction, CharSize : Word);
Begin
  BgFont := Font;
  BgDir := Direction And 1;
  If CharSize < 1 Then CharSize := 1;
  If CharSize > 10 Then CharSize := 10;
  BgSize := CharSize;
End;

Procedure SetUserCharSize_G(MultX, DivX, MultY, DivY : Word);
Begin
End;

Procedure SetTextJustify_G(Horiz, Vert : Word);
Begin
  If (Horiz > 2) Or (Vert > 2) Then
  Begin
    BgRes := -11;
    Exit;
  End;
  BgHj := Horiz; BgVj := Vert;
End;

Procedure GetTextSettings_G(Var TextInfo : TextSettingsType);
Begin
  TextInfo.Font := BgFont;
  TextInfo.Direction := BgDir;
  TextInfo.CharSize := BgSize;
  TextInfo.Horiz := BgHj;
  TextInfo.Vert := BgVj;
End;

Function TextWidth_G(Const TextString : String) : Word;
Begin
  TextWidth_G := Length(TextString) * 8 * BgSize;
End;

Function TextHeight_G(Const TextString : String) : Word;
Begin
  TextHeight_G := 8 * BgSize;
End;

Procedure OutTextXY_G(X, Y : Integer; Const TextString : String);
Begin
  BgText(X + BgVx, Y + BgVy, TextString);
End;

Procedure OutText_G(Const TextString : String);
Begin
  BgText(BgCpx + BgVx, BgCpy + BgVy, TextString);
  If (BgDir = 0) And (BgHj = 0) Then
    BgCpx := BgCpx + Length(TextString) * 8 * BgSize;
End;

Function InstallUserFont_G(Const FontFileName : String) : Integer;
Begin
  InstallUserFont_G := 0;
End;

Function RegisterBGIfont_G(Font : Pointer) : Integer;
Begin
  RegisterBGIfont_G := 0;
End;

Function RegisterBGIdriver_G(Driver : Pointer) : Integer;
Begin
  RegisterBGIdriver_G := 0;
End;

Function InstallUserDriver_G(Const DriverFileName : String;
    AutoDetectPtr : Pointer) : Integer;
Begin
  InstallUserDriver_G := 0;
End;

Procedure SetGraphBufSize_G(BufSize : Word);
Begin
End;

{ ---- images ---- }

Function ImageSize_G(X1, Y1, X2, Y2 : Integer) : LongInt;
Var W, H : LongInt;
Begin
  W := X2 - X1; If W < 0 Then W := -W;
  H := Y2 - Y1; If H < 0 Then H := -H;
  ImageSize_G := 4 + (W + 1) * (H + 1);
End;

Procedure GetImage_G(X1, Y1, X2, Y2 : Integer; Var BitMap);
Var A, W, H, Y, Xa, Xb, Ys, T, D : LongInt;
Begin
  A := LongInt(@BitMap);
  X1 := X1 + BgVx; X2 := X2 + BgVx;
  Y1 := Y1 + BgVy; Y2 := Y2 + BgVy;
  If X1 > X2 Then Begin T := X1; X1 := X2; X2 := T; End;
  If Y1 > Y2 Then Begin T := Y1; Y1 := Y2; Y2 := T; End;
  W := X2 - X1 + 1; H := Y2 - Y1 + 1;
  MemW[0:A] := W; MemW[0:A + 2] := H;
  For Y := 0 To H - 1 Do
  Begin
    D := A + 4 + Y * W;
    Ys := Y1 + Y;
    If (Ys < 0) Or (Ys >= BgH) Then BgFillSpan(D, W, 0)
    Else
    Begin
      Xa := X1; Xb := X2;
      If Xa < 0 Then Xa := 0;
      If Xb >= BgW Then Xb := BgW - 1;
      If Xa > Xb Then BgFillSpan(D, W, 0)
      Else
      Begin
        If Xa > X1 Then BgFillSpan(D, Xa - X1, 0);
        BgCopySpan(BgBuf + Ys * BgW + Xa, D + (Xa - X1), Xb - Xa + 1);
        If Xb < X2 Then BgFillSpan(D + (Xb - X1) + 1, X2 - Xb, 0);
      End;
    End;
  End;
End;

Procedure PutImage_G(X, Y : Integer; Var BitMap; BitBlt : Word);
Var A, W, H, R, Xa, Xb, I, S, D, V : LongInt;
Begin
  A := LongInt(@BitMap);
  W := MemW[0:A]; H := MemW[0:A + 2];
  X := X + BgVx; Y := Y + BgVy;
  BgDirt(X, Y, X + W - 1, Y + H - 1);
  For R := 0 To H - 1 Do
  Begin
    If (Y + R < BgCy1) Or (Y + R > BgCy2) Then Continue;
    Xa := X; Xb := X + W - 1;
    If Xa < BgCx1 Then Xa := BgCx1;
    If Xb > BgCx2 Then Xb := BgCx2;
    If Xa > Xb Then Continue;
    S := A + 4 + R * W + (Xa - X);
    D := BgBuf + (Y + R) * BgW + Xa;
    If BitBlt = 0 Then BgCopySpan(S, D, Xb - Xa + 1)
    Else
      For I := 0 To Xb - Xa Do
      Begin
        V := Mem[0:S + I];
        Case BitBlt Of
          1 : Mem[0:D + I] := (Mem[0:D + I] Xor V) And 255;
          2 : Mem[0:D + I] := (Mem[0:D + I] Or V) And 255;
          3 : Mem[0:D + I] := (Mem[0:D + I] And V) And 255;
        Else
          Mem[0:D + I] := (Not V) And 15;
        End;
      End;
  End;
End;

{ ---- palette ---- }

Function GetPaletteSize_G : Integer;
Begin
  GetPaletteSize_G := 16;
End;

Procedure GetPalette_G(Var Palette : PaletteType);
Var I : LongInt;
Begin
  Palette.Size := 16;
  For I := 0 To 15 Do Palette.Colors[I] := BgPal[I];
End;

Procedure GetDefaultPalette_G(Var Palette : PaletteType);
Const Std : Array[0..15] Of Byte =
    (0, 1, 2, 3, 4, 5, 20, 7, 56, 57, 58, 59, 60, 61, 62, 63);
Var I : LongInt;
Begin
  Palette.Size := 16;
  For I := 0 To 15 Do Palette.Colors[I] := Std[I];
End;

Procedure SetPalette_G(ColorNum : Word; Color : ShortInt);
Begin
  If ColorNum > 15 Then Begin BgRes := -11; Exit; End;
  BgPal[ColorNum] := Color And 63;
  BgMakeFin;
  BgDirt(0, 0, BgW - 1, BgH - 1);
End;

Procedure SetAllPalette_G(Var Palette);
Var I, A : LongInt;
Begin
  A := LongInt(@Palette);
  For I := 0 To 15 Do BgPal[I] := Mem[0:A + 1 + I] And 63;
  BgMakeFin;
  BgDirt(0, 0, BgW - 1, BgH - 1);
End;

{ DAC : composantes de 0 a 63 (VGA) }
Procedure SetRGBPalette_G(ColorNum, RedValue, GreenValue,
    BlueValue : Integer);
Var R, G, B : LongInt;
Begin
  If (ColorNum < 0) Or (ColorNum > 255) Then Begin BgRes := -11; Exit; End;
  R := (RedValue And 63) Shl 2; R := R Or (R Shr 6);
  G := (GreenValue And 63) Shl 2; G := G Or (G Shr 6);
  B := (BlueValue And 63) Shl 2; B := B Or (B Shr 6);
  BgDac[ColorNum] := (R Shl 16) Or (G Shl 8) Or B;
  BgMakeFin;
  BgDirt(0, 0, BgW - 1, BgH - 1);
End;

{ pages }

Procedure SetActivePage_G(Page : Word);
Begin
  If (Page > 3) Or (BgPages[Page] = 0) Then Begin BgRes := -11; Exit; End;
  BgAct := Page;
  BgBuf := BgPages[Page];
End;

Procedure SetVisualPage_G(Page : Word);
Begin
  If (Page > 3) Or (BgPages[Page] = 0) Then Begin BgRes := -11; Exit; End;
  BgVis := Page;
  BgDirty := False;
  BgDirt(0, 0, BgW - 1, BgH - 1);
End;

{ ---- ecran : /dev/fb0 ---- }

Procedure BgRow32(Src, Dst, Cnt : LongInt);
Begin
  asm
    push esi
    push edi
    push ebx
    mov esi, Src
    mov edi, Dst
    mov ecx, Cnt
    mov ebx, offset BgFin
  @l32:
    movzx eax, byte ptr [esi]
    inc esi
    and eax, 15
    mov eax, [ebx+eax*4]
    mov [edi], eax
    add edi, 4
    dec ecx
    jnz @l32
    pop ebx
    pop edi
    pop esi
  end;
End;

Procedure BgRow16(Src, Dst, Cnt : LongInt);
Begin
  asm
    push esi
    push edi
    push ebx
    mov esi, Src
    mov edi, Dst
    mov ecx, Cnt
    mov ebx, offset BgFin
  @l16:
    movzx eax, byte ptr [esi]
    inc esi
    and eax, 15
    mov eax, [ebx+eax*4]
    mov [edi], ax
    add edi, 2
    dec ecx
    jnz @l16
    pop ebx
    pop edi
    pop esi
  end;
End;

Procedure BgRowOut(S, D, N : LongInt);
Var I, V : LongInt;
Begin
  If N <= 0 Then Exit;
  Case BgBpp Of
    32 : BgRow32(S, D, N);
    16, 15 : BgRow16(S, D, N);
    24 :
      For I := 0 To N - 1 Do
      Begin
        V := BgFin[Mem[0:S + I] And 15];
        Mem[0:D + I * 3] := V And 255;
        Mem[0:D + I * 3 + 1] := (V Shr 8) And 255;
        Mem[0:D + I * 3 + 2] := (V Shr 16) And 255;
      End;
  Else
    BgCopySpan(S, D, N);
  End;
End;

{ un pixel directement dans la memoire video (curseur) }
Procedure BgFbPix(X, Y, Idx : LongInt);
Var A, V : LongInt;
Begin
  If (X < 0) Or (Y < 0) Or (X >= BgW) Or (Y >= BgH) Then Exit;
  A := BgFb + (BgOfy + Y) * BgStride + (BgOfx + X) * BgBytes;
  V := BgFin[Idx And 15];
  Case BgBytes Of
    4 : MemL[0:A] := V;
    2 : MemW[0:A] := V And $FFFF;
    3 : Begin
          Mem[0:A] := V And 255;
          Mem[0:A + 1] := (V Shr 8) And 255;
          Mem[0:A + 2] := (V Shr 16) And 255;
        End;
  Else
    Mem[0:A] := Idx;
  End;
End;

{ ---- souris : etat (voir Intr 33h plus bas) ---- }

Const
  BgCurShape : Array[0..16] Of String[12] = (
    '.           ', '..          ', '.#.         ', '.##.        ',
    '.###.       ', '.####.      ', '.#####.     ', '.######.    ',
    '.#######.   ', '.########.  ', '.#####.....', '.##.##.     ',
    '.#. .##.    ', '..  .##.    ', '.    .##.   ', '     .##.   ',
    '      ..    ');

Var
  BgMsFd, BgMx, BgMy, BgMb, BgMinX, BgMaxX, BgMinY, BgMaxY : LongInt;
  BgMkx, BgMky, BgMsN, BgCurVis, BgCurX, BgCurY : LongInt;
  BgMsPk : Array[0..3] Of Byte;
  BgPressN, BgRelN, BgPressX, BgPressY, BgRelX, BgRelY : Array[0..2] Of
    LongInt;
  BgMsOpen, BgCurDrawn, BgRange : Boolean;
  I_Dummy : LongInt;
  { entree absolue (evdev avec ABS_X et ABS_Y) }
  BgAbsFd, BgAbsX, BgAbsY, BgAbsMinX, BgAbsMaxX, BgAbsMinY, BgAbsMaxY : LongInt;
  BgAbsSyn, BgAbsOk, BgAbsPoll : Boolean;
  { pilote : commandes de mise a jour et curseur materiel (ioctl 46F0h...) }
  BgHwUpd, BgHwCur, BgHwTried, BgHwOn, BgHwWant : Boolean;
  BgHwX, BgHwY : LongInt;
  { horloge du processeur (RDTSC) : cycles par milliseconde }
  BgTscV, BgTscMs, BgLastPoll, BgLastFl : LongInt;
  BgNoTsc, BgMsPoll, BgKbdUsed, BgEof : Boolean;
  BgDumpName : String;
  BgDumpT : LongInt;

Procedure GfxDump(Const FileName : String); Forward;
Procedure BgKRead; Forward;

Function BgTsc : LongInt;
Begin
  asm
    rdtsc
    mov BgTscV, eax
  end;
  BgTsc := BgTscV;
End;

{ heure en millisecondes (appel systeme, compte) }
Function BgNow : LongInt;
Begin
  Inc(BgSt[4]);
  BgNow := GetTickCount;
End;

{ au moins Ms millisecondes depuis le cycle Since ? (toujours vrai sans
  horloge du processeur) }
Function BgElapsed(Since, Ms : LongInt) : Boolean;
Var D : Double;
Begin
  If BgNoTsc Or (BgTscMs <= 0) Then
  Begin
    BgElapsed := True;
    Exit;
  End;
  D := BgTsc - Since;
  If D < 0 Then D := D + 4294967296.0;
  BgElapsed := D >= 1.0 * Ms * BgTscMs;
End;

Procedure BgCalib;
Var T0, T1, C0, C1 : LongInt;
Begin
  If (BgTscMs <> 0) Or BgNoTsc Then Exit;
  If GetEnv('GFXNOTSC') <> '' Then
  Begin
    BgNoTsc := True;
    Exit;
  End;
  T0 := GetTickCount;
  C0 := BgTsc;
  Sleep(20);
  C1 := BgTsc;
  T1 := GetTickCount;
  If T1 > T0 Then BgTscMs := ((C1 - C0) And $7FFFFFFF) Div (T1 - T0);
  If BgTscMs < 50000 Then
  Begin
    BgNoTsc := True;
    BgTscMs := 0;
  End;
  BgLastPoll := BgTsc;
  BgLastFl := BgLastPoll;
End;

Procedure BgCurDraw;
Var R, C : LongInt; Ch : Char;
Begin
  For R := 0 To 16 Do
    For C := 1 To 12 Do
    Begin
      Ch := BgCurShape[R][C];
      If Ch = '#' Then BgFbPix(BgMx + C - 1, BgMy + R, 0)
      Else If Ch = '.' Then BgFbPix(BgMx + C - 1, BgMy + R, 15);
    End;
  BgCurX := BgMx; BgCurY := BgMy;
  Inc(BgSt[8]);
  BgSt[7] := BgSt[7] + 204;
  BgCurDrawn := True;
End;

{ curseur materiel : image (ARGB) puis position ; ioctl du pilote, sans
  effet (ENOTTY) sur un noyau qui ne les a pas }
Procedure BgHwDefine;
Var A : Array[0..5] Of LongInt; Px : Array[0..203] Of LongInt; R, C : LongInt;
    Ch : Char;
Begin
  BgHwTried := True;
  If BgMem Or (BgFd < 0) Then Exit;
  For R := 0 To 16 Do
    For C := 1 To 12 Do
    Begin
      Ch := BgCurShape[R][C];
      If Ch = '#' Then Px[R * 12 + C - 1] := $FF000000
      Else If Ch = '.' Then Px[R * 12 + C - 1] := $FFFFFFFF
      Else Px[R * 12 + C - 1] := 0;
    End;
  A[0] := 12; A[1] := 17; A[2] := 0; A[3] := 0; A[4] := LongInt(@Px);
  Inc(BgSt[9]);
  If SysIoctl(BgFd, $46F1, A) = 0 Then BgHwCur := True;
End;

Procedure BgHwMove(On : Boolean);
Var A : Array[0..2] Of LongInt;
Begin
  A[0] := BgOfx + BgMx; A[1] := BgOfy + BgMy;
  If On Then A[2] := 1 Else A[2] := 0;
  Inc(BgSt[9]);
  SysIoctl(BgFd, $46F2, A);
  BgHwOn := On;
  BgHwX := BgMx; BgHwY := BgMy;
End;

{ une seule commande de mise a jour du pilote pour le rectangle (VMware SVGA :
  sans elle le noyau redessine tout l'ecran 20 fois par seconde) }
Procedure BgHwUpdate(X1, Y1, X2, Y2 : LongInt);
Var A : Array[0..3] Of LongInt;
Begin
  If Not BgHwUpd Then Exit;
  If X1 < 0 Then X1 := 0;
  If Y1 < 0 Then Y1 := 0;
  If X2 >= BgW Then X2 := BgW - 1;
  If Y2 >= BgH Then Y2 := BgH - 1;
  If (X2 < X1) Or (Y2 < Y1) Then Exit;
  A[0] := BgOfx + X1; A[1] := BgOfy + Y1;
  A[2] := X2 - X1 + 1; A[3] := Y2 - Y1 + 1;
  Inc(BgSt[9]);
  SysIoctl(BgFd, $46F0, A);
End;

{ l'etat du curseur differe-t-il de ce qui est affiche ? }
Function BgCurChange : Boolean;
Begin
  BgCurChange := False;
  If BgHwCur Then
  Begin
    If (BgCurVis >= 1) <> BgHwOn Then BgCurChange := True
    Else If BgHwOn And ((BgHwX <> BgMx) Or (BgHwY <> BgMy)) Then
      BgCurChange := True;
  End
  Else If BgCurDrawn Then
  Begin
    If (BgCurVis < 1) Or (BgCurX <> BgMx) Or (BgCurY <> BgMy) Then
      BgCurChange := True;
  End
  Else If BgCurVis >= 1 Then BgCurChange := True;
End;

Procedure BgFlush;
Var Y, Wid, I, Ux1, Uy1, Ux2, Uy2, Rows : LongInt; Any : Boolean;
Begin
  If Not BgOk Then Exit;
  If (BgCurVis >= 1) And (Not BgHwTried) Then
  Begin
    If BgHwWant Then BgHwDefine Else BgHwTried := True;
  End;
  Any := False;
  Ux1 := 0; Uy1 := 0; Ux2 := -1; Uy2 := -1;
  If BgHwCur Then
  Begin
    If BgCurChange Then BgHwMove(BgCurVis >= 1);
  End
  Else If BgCurDrawn And ((BgCurVis < 1) Or (BgCurX <> BgMx) Or
                          (BgCurY <> BgMy)) Then
  Begin
    BgDirt(BgCurX, BgCurY, BgCurX + 12, BgCurY + 17);
    BgCurDrawn := False;
  End;
  If BgDirty Then
  Begin
    Inc(BgSt[5]);
    For I := 0 To BgRn - 1 Do
      If BgRx2[I] >= BgRx1[I] Then
      Begin
        Wid := BgRx2[I] - BgRx1[I] + 1;
        Rows := BgRy2[I] - BgRy1[I] + 1;
        BgSt[6] := BgSt[6] + Rows;
        BgSt[7] := BgSt[7] + Wid * Rows;
        If Not BgMem Then
          For Y := BgRy1[I] To BgRy2[I] Do
            BgRowOut(BgPages[BgVis] + Y * BgW + BgRx1[I],
                     BgFb + (BgOfy + Y) * BgStride +
                     (BgOfx + BgRx1[I]) * BgBytes, Wid);
      End;
    Ux1 := BgDx1; Uy1 := BgDy1; Ux2 := BgDx2; Uy2 := BgDy2;
    Any := True;
    BgDirty := False;
    BgRn := 0;
    BgCurDrawn := False;
    If BgMem And (BgDumpName <> '') And
       (GetTickCount - BgDumpT > 700) Then
    Begin
      BgDumpT := GetTickCount;
      GfxDump(BgDumpName);
    End;
  End;
  If (BgCurVis >= 1) And (Not BgCurDrawn) And (Not BgMem) And
     (Not BgHwCur) Then
  Begin
    BgCurDraw;
    If Any Then
    Begin
      If BgMx < Ux1 Then Ux1 := BgMx;
      If BgMy < Uy1 Then Uy1 := BgMy;
      If BgMx + 12 > Ux2 Then Ux2 := BgMx + 12;
      If BgMy + 17 > Uy2 Then Uy2 := BgMy + 17;
    End
    Else
    Begin
      Ux1 := BgMx; Uy1 := BgMy; Ux2 := BgMx + 12; Uy2 := BgMy + 17;
      Any := True;
    End;
  End;
  If Any Then BgHwUpdate(Ux1, Uy1, Ux2, Uy2);
End;

{ ---- evenements de la souris (paquets PS/2 et evdev absolu) ---- }

Procedure BgSetBtn(Nb : LongInt);
Var K, Old : LongInt;
Begin
  Old := BgMb;
  BgMb := Nb;
  For K := 0 To 2 Do
  Begin
    If ((BgMb Shr K) And 1 = 1) And ((Old Shr K) And 1 = 0) Then
    Begin
      Inc(BgPressN[K]); BgPressX[K] := BgMx; BgPressY[K] := BgMy;
    End;
    If ((BgMb Shr K) And 1 = 0) And ((Old Shr K) And 1 = 1) Then
    Begin
      Inc(BgRelN[K]); BgRelX[K] := BgMx; BgRelY[K] := BgMy;
    End;
  End;
End;

Procedure BgMouseRead;
Var Buf : Array[0..63] Of Byte; N, I, B, Dx, Dy, Pass : LongInt;
Begin
  If BgMsFd < 0 Then Exit;
  For Pass := 1 To 4 Do
  Begin
    Inc(BgSt[1]);
    N := SysRead(BgMsFd, Buf, 63);
    If N <= 0 Then
    Begin
      { prete a lire mais rien : fichier de test (pas de poll) }
      If N = 0 Then BgMsPoll := False;
      Exit;
    End;
    For I := 0 To N - 1 Do
    Begin
      B := Buf[I];
      If (BgMsN = 0) And ((B And 8) = 0) Then Continue;
      BgMsPk[BgMsN] := B;
      Inc(BgMsN);
      If BgMsN = 3 Then
      Begin
        BgMsN := 0;
        Inc(BgSt[11]);
        Dx := BgMsPk[1];
        Dy := BgMsPk[2];
        If (BgMsPk[0] And $10) <> 0 Then Dx := Dx - 256;
        If (BgMsPk[0] And $20) <> 0 Then Dy := Dy - 256;
        BgMx := BgMx + Dx;
        BgMy := BgMy - Dy;
        BgMkx := BgMkx + Dx;
        BgMky := BgMky - Dy;
        If BgMx < BgMinX Then BgMx := BgMinX;
        If BgMx > BgMaxX Then BgMx := BgMaxX;
        If BgMy < BgMinY Then BgMy := BgMinY;
        If BgMy > BgMaxY Then BgMy := BgMaxY;
        BgSetBtn(BgMsPk[0] And 7);
      End;
    End;
    If N < 63 Then Exit;
  End;
End;

{ position absolue : valeurs du peripherique mises a l'echelle de l'ecran
  (plage de la souris : fonctions 07h et 08h) }
Procedure BgAbsPlace;
Var V : LongInt;
Begin
  If BgAbsMaxX > BgAbsMinX Then
  Begin
    V := BgAbsX - BgAbsMinX;
    If V < 0 Then V := 0;
    If V > BgAbsMaxX - BgAbsMinX Then V := BgAbsMaxX - BgAbsMinX;
    BgMx := BgMinX + V * (BgMaxX - BgMinX) Div (BgAbsMaxX - BgAbsMinX);
  End;
  If BgAbsMaxY > BgAbsMinY Then
  Begin
    V := BgAbsY - BgAbsMinY;
    If V < 0 Then V := 0;
    If V > BgAbsMaxY - BgAbsMinY Then V := BgAbsMaxY - BgAbsMinY;
    BgMy := BgMinY + V * (BgMaxY - BgMinY) Div (BgAbsMaxY - BgAbsMinY);
  End;
  BgAbsSyn := False;
End;

Procedure BgAbsRead;
Var Ev : Array[0..63] Of LongInt; N, I, P, Ty, Co, V, Nb, Bit, Pass : LongInt;
Begin
  If Not BgAbsOk Then Exit;
  For Pass := 1 To 4 Do
  Begin
    Inc(BgSt[1]);
    N := SysRead(BgAbsFd, Ev, 256);
    If N = 0 Then BgAbsPoll := False;
    If N < 16 Then
    Begin
      If BgAbsSyn Then BgAbsPlace;
      Exit;
    End;
    For I := 0 To N Div 16 - 1 Do
    Begin
      P := LongInt(@Ev) + I * 16;
      Ty := MemW[0:P + 8];
      Co := MemW[0:P + 10];
      V := MemL[0:P + 12];
      If Ty = 3 Then
      Begin
        If Co = 0 Then BgAbsX := V
        Else If Co = 1 Then BgAbsY := V;
        If Co <= 1 Then BgAbsSyn := True;
        Inc(BgSt[11]);
      End
      Else If Ty = 1 Then
      Begin
        Bit := 0;
        Case Co Of
          $110, $14A : Bit := 1;
          $111 : Bit := 2;
          $112 : Bit := 4;
        End;
        If Bit <> 0 Then
        Begin
          If BgAbsSyn Then BgAbsPlace;
          Nb := BgMb;
          If V = 1 Then Nb := Nb Or Bit
          Else If V = 0 Then Nb := Nb And (Not Bit);
          If Nb <> BgMb Then BgSetBtn(Nb);
        End;
      End
      Else If (Ty = 0) And (Co = 0) And BgAbsSyn Then BgAbsPlace;
    End;
    If N < 256 Then Exit;
  End;
  If BgAbsSyn Then BgAbsPlace;
End;

{ une attente : une seule commande poll sur le clavier, la souris et le
  peripherique absolu, puis lecture groupee de ce qui est pret }
Procedure BgPoll(Ms : LongInt);
Var Pf : Array[0..5] Of LongInt; N, K0, KM, KA, R : LongInt;
Begin
  N := 0; K0 := -1; KM := -1; KA := -1;
  If BgKbdUsed And (Not BgEof) Then
  Begin
    Pf[0] := 0; Pf[1] := 1; K0 := 0; N := 1;
  End;
  If BgMsOpen And BgMsPoll And (BgMsFd >= 0) Then
  Begin
    Pf[N * 2] := BgMsFd; Pf[N * 2 + 1] := 1; KM := N; Inc(N);
  End;
  If BgAbsOk And BgAbsPoll Then
  Begin
    Pf[N * 2] := BgAbsFd; Pf[N * 2 + 1] := 1; KA := N; Inc(N);
  End;
  If N = 0 Then
  Begin
    If Ms > 0 Then
    Begin
      Inc(BgSt[3]);
      Sleep(Ms);
    End;
    BgLastPoll := BgTsc;
    If BgMsOpen And (Not BgMsPoll) Then BgMouseRead;
    If BgAbsOk And (Not BgAbsPoll) Then BgAbsRead;
    Exit;
  End;
  Inc(BgSt[0]);
  R := SysPoll(LongInt(@Pf), N, Ms);
  BgLastPoll := BgTsc;
  If R > 0 Then
  Begin
    If (K0 >= 0) And ((Pf[K0 * 2 + 1] Shr 16) <> 0) Then BgKRead;
    If (KM >= 0) And ((Pf[KM * 2 + 1] Shr 16) <> 0) Then BgMouseRead;
    If (KA >= 0) And ((Pf[KA * 2 + 1] Shr 16) <> 0) Then BgAbsRead;
  End;
  If BgMsOpen And (Not BgMsPoll) Then BgMouseRead;
  If BgAbsOk And (Not BgAbsPoll) Then BgAbsRead;
End;

{ recopie vers l'ecran si quelque chose a change et si la derniere recopie
  date d'au moins 8 ms (au plus ~125 images par seconde) }
Procedure BgFlushDue;
Begin
  If Not BgOk Then Exit;
  If Not (BgDirty Or BgCurChange) Then Exit;
  If BgElapsed(BgLastFl, 8) Then
  Begin
    BgFlush;
    BgLastFl := BgTsc;
  End;
End;

{ appelee par KeyPressed, GetMouseState, Intr 33h : lit les entrees au plus
  une fois par milliseconde (Delay lit deja pendant son attente) }
Procedure BgTick;
Begin
  Inc(BgSt[10]);
  If BgMsOpen Or BgKbdUsed Then
    If BgElapsed(BgLastPoll, 1) Then BgPoll(0);
  BgFlushDue;
End;

{ recopie immediate (sans limite de cadence) }
Procedure GfxFlush;
Begin
  If BgMsOpen Or BgKbdUsed Then BgPoll(0);
  BgFlush;
  BgLastFl := BgTsc;
End;

{ ---- terminal : mode brut du clavier ---- }

Procedure BgTermRaw;
Var I : LongInt;
Begin
  BgKbdUsed := True;
  If BgRawOn Or BgTermTry Then Exit;
  BgTermTry := True;
  If SysIoctl(0, $5401, BgTermSv) < 0 Then Exit;
  BgTermOk := True;
  For I := 0 To 8 Do BgTermNw[I] := BgTermSv[I];
  BgTermNw[0] := BgTermNw[0] And (Not ($1 + $2 + $8 + $20 + $40 + $80 +
    $100 + $400));
  BgTermNw[3] := BgTermNw[3] And (Not ($1 + $2 + $8 + $40 + $8000));
  Mem[0:LongInt(@BgTermNw) + 22] := 0;
  Mem[0:LongInt(@BgTermNw) + 23] := 1;
  SysIoctl(0, $5402, BgTermNw);
  BgRawOn := True;
End;

Procedure BgTermBack;
Begin
  If BgRawOn Then SysIoctl(0, $5402, BgTermSv);
  BgRawOn := False;
  BgTermTry := False;
  BgKbdUsed := False;
End;

{ ---- ouverture et fermeture de l'ecran ---- }

Function BgNum(V : LongInt) : String;
Var S : String;
Begin
  Str(V, S);
  BgNum := S;
End;

Function BgOpenFb(Var W, H : LongInt) : Boolean;
Var Vi : Array[0..39] Of LongInt; Fi : Array[0..15] Of LongInt;
    R, Try : LongInt;
Begin
  BgOpenFb := False;
  BgFd := SysOpen('/dev/fb0', O_RDWR, 0);
  If BgFd < 0 Then
  Begin
    BgWhy := '/dev/fb0 : ' + SysErrorText(SysErrno);
    Exit;
  End;
  FillChar(Vi, SizeOf(Vi), 0);
  If SysIoctl(BgFd, $4600, Vi) < 0 Then
  Begin
    BgWhy := 'FBIOGET_VSCREENINFO';
    SysClose(BgFd);
    Exit;
  End;
  { carte VMware SVGA : 640x480 n'est pas affiche par QEMU (la surface
    "invite non initialisee" a la meme taille) : 800x600 a la place }
  FillChar(Fi, SizeOf(Fi), 0);
  SysIoctl(BgFd, $4602, Fi);
  If ((Fi[0] And $FFFFFF) = $574D56) And (W = 640) And (H = 480) Then
  Begin
    W := 800; H := 600;
  End;
  For Try := 0 To 1 Do
  Begin
    Vi[0] := W; Vi[1] := H; Vi[2] := W; Vi[3] := H;
    Vi[4] := 0; Vi[5] := 0; Vi[21] := 0;
    If Try = 0 Then Vi[6] := 32 Else Vi[6] := 16;
    If SysIoctl(BgFd, $4601, Vi) = 0 Then Break;
  End;
  FillChar(Vi, SizeOf(Vi), 0);
  SysIoctl(BgFd, $4600, Vi);
  BgFbW := Vi[0]; BgFbH := Vi[1]; BgBpp := Vi[6];
  If (BgBpp <> 32) And (BgBpp <> 24) And (BgBpp <> 16) And
     (BgBpp <> 15) And (BgBpp <> 8) Then
  Begin
    BgWhy := 'mode ' + BgNum(BgFbW) + 'x' + BgNum(BgFbH) + 'x' +
             BgNum(BgBpp) + ' non pris en charge';
    SysClose(BgFd);
    Exit;
  End;
  If (BgFbW < W) Or (BgFbH < H) Then
  Begin
    BgWhy := 'mode ' + BgNum(BgFbW) + 'x' + BgNum(BgFbH) +
             ' trop petit pour ' + BgNum(W) + 'x' + BgNum(H);
    SysClose(BgFd);
    Exit;
  End;
  BgRo := Vi[8]; BgRl := Vi[9]; BgGo := Vi[11]; BgGl := Vi[12];
  BgBo := Vi[14]; BgBl := Vi[15];
  BgBytes := (BgBpp + 7) Div 8;
  FillChar(Fi, SizeOf(Fi), 0);
  SysIoctl(BgFd, $4602, Fi);
  BgStride := Fi[12];
  If BgStride < BgFbW * BgBytes Then BgStride := Fi[11];
  If BgStride < BgFbW * BgBytes Then BgStride := Vi[2] * BgBytes;
  BgMapLen := BgStride * BgFbH;
  R := LnxSys6(192, 0, BgMapLen, 3, 1, BgFd, 0);
  If (R < 0) And (R > -4096) Then
  Begin
    BgWhy := 'mmap /dev/fb0 : errno ' + BgNum(-R);
    SysClose(BgFd);
    Exit;
  End;
  BgFb := R;
  BgOfx := (BgFbW - W) Div 2;
  BgOfy := (BgFbH - H) Div 2;
  { bande noire autour d'un ecran logique plus petit }
  If (BgFbW > W) Or (BgFbH > H) Then BgFillSpan(BgFb, BgMapLen, 0);
  BgOpenFb := True;
End;

Procedure BgLeave;
Begin
  If Not BgMem Then
  Begin
    If BgHwOn Then BgHwMove(False);
    BgHwCur := False; BgHwTried := False; BgHwUpd := False;
    If BgKdOn And (BgTtyFd >= 0) Then SysIoctlL(BgTtyFd, $4B3A, 0);
    BgKdOn := False;
    If BgFb <> 0 Then LnxSys3(91, BgFb, BgMapLen, 0);
    BgFb := 0;
    If BgFd >= 0 Then SysClose(BgFd);
    BgFd := -1;
    If BgTtyFd > 2 Then SysClose(BgTtyFd);
    BgTtyFd := -1;
  End;
  BgCurDrawn := False;
End;

Procedure BgStatLine;
Var I : LongInt; S, T : String;
Begin
  If GetEnv('GFXSTAT') = '' Then Exit;
  S := 'GFXSTAT';
  For I := 0 To 11 Do
  Begin
    Str(BgSt[I], T);
    S := S + ' s' + BgNum(I) + '=' + T;
  End;
  SysPut(2, S + #10);
End;

Procedure BgAtExit;
Begin
  BgStatLine;
  If BgOk Then
  Begin
    BgFlush;
    BgOk := False;
    BgLeave;
  End;
  BgTermBack;
End;

Procedure BgInitState;
Var I : LongInt;
Begin
  BgColor := 15; BgBk := 0; BgFillCol := 15; BgFillPat := 1; BgMode := 0;
  For I := 0 To 7 Do BgUser[I] := $FF;
  BgLnSt := 0; BgLnPat := $FFFF; BgLnTh := 1;
  BgVx := 0; BgVy := 0; BgVx2 := BgW - 1; BgVy2 := BgH - 1; BgClip := True;
  BgSetClip;
  BgCpx := 0; BgCpy := 0;
  BgFont := 0; BgDir := 0; BgSize := 1; BgHj := 0; BgVj := 2;
  BgDefPal;
End;

Procedure GraphDefaults_G;
Begin
  BgInitState;
End;

Function BgEnvMode(Var W, H : LongInt) : Boolean;
Var S : String; P : LongInt; A, B : LongInt;
Begin
  BgEnvMode := False;
  S := GetEnv('GFXMODE');
  P := Pos('x', S);
  If P < 2 Then Exit;
  Val(Copy(S, 1, P - 1), A, I_Dummy);
  Val(Copy(S, P + 1, 10), B, I_Dummy);
  If (A < 320) Or (B < 200) Or (A > 2560) Or (B > 1600) Then Exit;
  W := A; H := B;
  BgEnvMode := True;
End;

Procedure DetectGraph_G(Var GraphDriver, GraphMode : Integer);
Begin
  GraphDriver := 9;
  GraphMode := 2;
End;

Function BgModeSize(Drv, Mo : LongInt; Var W, H : LongInt) : Boolean;
Begin
  BgModeSize := True;
  If Drv = 9 Then
  Begin
    W := 640;
    Case Mo Of
      0 : H := 200;
      1 : H := 350;
      2 : H := 480;
    Else
      BgModeSize := False;
    End;
  End
  Else If Drv = 3 Then
  Begin
    W := 640;
    Case Mo Of
      0 : H := 200;
      1 : H := 350;
    Else
      BgModeSize := False;
    End;
  End
  Else If (Drv >= 11) And (Drv <= 20) Then
  Begin
    Case Mo Of
      0 : Begin W := 320; H := 200; End;
      1 : Begin W := 640; H := 200; End;
      2 : Begin W := 640; H := 350; End;
      3 : Begin W := 640; H := 480; End;
      4 : Begin W := 800; H := 600; End;
      5 : Begin W := 1024; H := 768; End;
      6 : Begin W := 1280; H := 1024; End;
      7 : Begin W := 1600; H := 1200; End;
    Else
      BgModeSize := False;
    End;
  End
  Else BgModeSize := False;
End;

Procedure GetModeRange_G(GraphDriver : Integer; Var LoMode, HiMode : SmallInt);
Begin
  Case GraphDriver Of
    9 : Begin LoMode := 0; HiMode := 2; End;
    3 : Begin LoMode := 0; HiMode := 1; End;
    11..20 : Begin LoMode := 0; HiMode := 6; End;
  Else
    Begin LoMode := -1; HiMode := -1; End;
  End;
End;

Procedure BgFreePages;
Var I : LongInt;
Begin
  For I := 0 To 3 Do
    If BgPages[I] <> 0 Then
    Begin
      FreeMem(Pointer(BgPages[I]), BgW * BgH + 64);
      BgPages[I] := 0;
    End;
End;

Procedure InitGraph_G(Var GraphDriver, GraphMode : Integer;
    Const PathToDriver : String);
Var W, H, Mo, Try : LongInt; Ok : Boolean; Pt : Pointer;
    HwA : Array[0..3] Of LongInt;
Begin
  BgRes := 0;
  BgWhy := '';
  If BgOk Then BgAtExit;
  If GraphDriver = 0 Then
  Begin
    GraphDriver := 9;
    GraphMode := 2;
  End;
  BgDrv := GraphDriver;
  If Not BgModeSize(GraphDriver, GraphMode, W, H) Then
  Begin
    BgRes := -10;
    If GraphMode < 0 Then BgRes := -4;
    If (GraphDriver <> 9) And (GraphDriver <> 3) And
       ((GraphDriver < 11) Or (GraphDriver > 20)) Then BgRes := -4;
    GraphDriver := BgRes;
    Exit;
  End;
  BgEnvMode(W, H);
  BgMem := GetEnv('GFXMEM') <> '';
  BgDumpName := GetEnv('GFXDUMP');
  BgDumpT := GetTickCount;
  BgFd := -1; BgTtyFd := -1; BgFb := 0;
  Mo := GraphMode;
  Try := 0;
  While True Do
  Begin
    If BgMem Then
    Begin
      Ok := True;
      BgFbW := W; BgFbH := H; BgBpp := 32; BgBytes := 4;
      BgRo := 16; BgRl := 8; BgGo := 8; BgGl := 8; BgBo := 0; BgBl := 8;
    End
    Else Ok := BgOpenFb(W, H);
    If Ok Then Break;
    { en D4bit sans -maxscreen : replier sur un mode plus petit }
    If (GraphDriver >= 11) And (Mo > 3) Then
    Begin
      Dec(Mo);
      BgModeSize(GraphDriver, Mo, W, H);
    End
    Else Break;
  End;
  If Not Ok Then
  Begin
    BgRes := -2;
    GraphDriver := -2;
    Exit;
  End;
  BgW := W; BgH := H;
  GetMem(Pt, BgW * BgH + 64);
  BgPages[0] := LongInt(Pt);
  If BgPages[0] = 0 Then
  Begin
    BgRes := -5;
    BgWhy := 'memoire insuffisante';
    BgLeave;
    GraphDriver := -5;
    Exit;
  End;
  BgAct := 0; BgVis := 0; BgBuf := BgPages[0];
  BgFillSpan(BgBuf, BgW * BgH, 0);
  BgInitState;
  BgOk := True;
  If Not BgMem Then
  Begin
    If SysIoctlL(0, $4B3A, 1) = 0 Then BgTtyFd := 0
    Else
    Begin
      BgTtyFd := SysOpen('/dev/tty0', O_RDWR, 0);
      If BgTtyFd >= 0 Then SysIoctlL(BgTtyFd, $4B3A, 1);
    End;
    BgKdOn := BgTtyFd >= 0;
  End;
  BgCalib;
  BgHwUpd := False; BgHwCur := False; BgHwTried := False; BgHwOn := False;
  { curseur materiel (ioctl 46F1h/46F2h) : seulement si GFXHWCUR=1 }
  BgHwWant := GetEnv('GFXHWCUR') = '1';
  If Not BgMem Then
  Begin
    FillChar(HwA, SizeOf(HwA), 0);
    Inc(BgSt[9]);
    BgHwUpd := SysIoctl(BgFd, $46F0, HwA) = 0;
  End;
  BgTermRaw;
  If Not BgGfxHook Then
  Begin
    LnxExitHook := BgAtExit;
    BgGfxHook := True;
  End;
  If Not BgRange Then
  Begin
    BgMinX := 0; BgMaxX := BgW - 1; BgMinY := 0; BgMaxY := BgH - 1;
  End;
  If BgMx > BgMaxX Then BgMx := BgMaxX;
  If BgMy > BgMaxY Then BgMy := BgMaxY;
  BgCurDrawn := False;
  BgDirty := False;
  BgDirt(0, 0, BgW - 1, BgH - 1);
  BgFlush;
End;

Procedure CloseGraph_G;
Begin
  If BgOk Then
  Begin
    BgFlush;
    BgOk := False;
    BgLeave;
    BgFreePages;
  End;
  BgTermBack;
End;

Procedure RestoreCrtMode_G;
Begin
  If BgOk Then
  Begin
    BgOk := False;
    BgLeave;
  End;
  BgTermBack;
End;

Procedure SetGraphMode_G(Mode : Integer);
Var D, M : Integer;
Begin
  D := BgDrv; M := Mode;
  If Not BgOk Then
  Begin
    BgFreePages;
    InitGraph_G(D, M, '');
  End
  Else
  Begin
    ClearDevice_G;
    BgInitState;
  End;
End;

Function GetGraphMode_G : Integer;
Begin
  GetGraphMode_G := BgMod;
End;

Function GetMaxMode_G : Integer;
Begin
  If BgDrv = 9 Then GetMaxMode_G := 2 Else GetMaxMode_G := 6;
End;

Function GetDriverName_G : String;
Begin
  GetDriverName_G := 'VGA';
End;

Function GetModeName_G(ModeNumber : Integer) : String;
Begin
  Case ModeNumber Of
    0 : GetModeName_G := '640 x 200 VGA';
    1 : GetModeName_G := '640 x 350 VGA';
  Else
    GetModeName_G := '640 x 480 VGA';
  End;
End;

Function GraphResult_G : Integer;
Begin
  GraphResult_G := BgRes;
  BgRes := 0;
End;

Function GraphErrorMsg_G(ErrorCode : Integer) : String;
Begin
  Case ErrorCode Of
    0 : GraphErrorMsg_G := 'No error';
    -1 : GraphErrorMsg_G := '(BGI) graphics not installed';
    -2 : GraphErrorMsg_G := 'Graphics hardware not detected';
    -3 : GraphErrorMsg_G := 'Device driver file not found';
    -4 : GraphErrorMsg_G := 'Invalid device driver file';
    -5 : GraphErrorMsg_G := 'Not enough memory to load driver';
    -6 : GraphErrorMsg_G := 'Out of memory in scan fill';
    -7 : GraphErrorMsg_G := 'Out of memory in flood fill';
    -8 : GraphErrorMsg_G := 'Font file not found';
    -9 : GraphErrorMsg_G := 'Not enough memory to load font';
    -10 : GraphErrorMsg_G := 'Invalid graphics mode for selected driver';
    -11 : GraphErrorMsg_G := 'Graphics error';
    -12 : GraphErrorMsg_G := 'Graphics I/O error';
    -13 : GraphErrorMsg_G := 'Invalid font file';
    -14 : GraphErrorMsg_G := 'Invalid font number';
    -18 : GraphErrorMsg_G := 'Invalid version';
  Else
    GraphErrorMsg_G := 'Graphics error';
  End;
End;

{ raison detaillee du dernier echec de InitGraph (extension) }
Function GfxWhy : String;
Begin
  GfxWhy := BgWhy;
End;

{ ---- souris : interruption 33h ---- }

Procedure BgMouseReset; Forward;

{ numero d'ioctl Linux : direction, type, numero, taille }
Function BgIoc(Dir, Typ, Nr, Sz : LongInt) : LongInt;
Begin
  BgIoc := (Dir Shl 30) Or (Sz Shl 16) Or (Typ Shl 8) Or Nr;
End;

{ periphique evdev a position absolue (EV_ABS avec ABS_X et ABS_Y : tablette,
  VMMDev de VirtualBox...) : /dev/input/event0..7 par EVIOCGBIT, ou le
  fichier MOUSEEVDEV (essais ; MOUSEABS=xmax,ymax pour la plage) }
Procedure BgAbsSetup(Fd : LongInt);
Var Ai : Array[0..5] Of LongInt; S : String; P : LongInt;
Begin
  BgAbsFd := Fd;
  BgAbsOk := True;
  BgAbsPoll := True;
  BgAbsMinX := 0; BgAbsMaxX := 32767; BgAbsMinY := 0; BgAbsMaxY := 32767;
  S := GetEnv('MOUSEABS');
  P := Pos(',', S);
  If P > 1 Then
  Begin
    Val(Copy(S, 1, P - 1), BgAbsMaxX, I_Dummy);
    Val(Copy(S, P + 1, 10), BgAbsMaxY, I_Dummy);
  End;
  FillChar(Ai, SizeOf(Ai), 0);
  If SysIoctl(Fd, BgIoc(2, 69, 64, 24), Ai) >= 0 Then
    If Ai[2] > Ai[1] Then
    Begin
      BgAbsMinX := Ai[1]; BgAbsMaxX := Ai[2];
    End;
  FillChar(Ai, SizeOf(Ai), 0);
  If SysIoctl(Fd, BgIoc(2, 69, 65, 24), Ai) >= 0 Then
    If Ai[2] > Ai[1] Then
    Begin
      BgAbsMinY := Ai[1]; BgAbsMaxY := Ai[2];
    End;
End;

Procedure BgAbsFind;
Var N, Fd : LongInt; P : String; Bits : Array[0..7] Of Byte;
Begin
  BgAbsOk := False;
  BgAbsSyn := False;
  P := GetEnv('MOUSEEVDEV');
  If P <> '' Then
  Begin
    Fd := SysOpen(P, O_RDONLY Or O_NONBLOCK, 0);
    If Fd >= 0 Then BgAbsSetup(Fd);
    Exit;
  End;
  If GetEnv('MOUSEREL') <> '' Then Exit;
  For N := 0 To 7 Do
  Begin
    Str(N, P);
    Fd := SysOpen('/dev/input/event' + P, O_RDONLY Or O_NONBLOCK, 0);
    If Fd < 0 Then Continue;
    FillChar(Bits, SizeOf(Bits), 0);
    If SysIoctl(Fd, BgIoc(2, 69, 32, 8), Bits) >= 0 Then
      If (Bits[0] And 8) <> 0 Then
      Begin
        FillChar(Bits, SizeOf(Bits), 0);
        If SysIoctl(Fd, BgIoc(2, 69, 35, 8), Bits) >= 0 Then
          If (Bits[0] And 3) = 3 Then
          Begin
            BgAbsSetup(Fd);
            Exit;
          End;
      End;
    SysClose(Fd);
  End;
End;

Procedure BgMouseOpen;
Var P : String;
Begin
  If BgMsOpen Then Exit;
  BgMsPoll := True;
  BgMsFd := -1;
  P := GetEnv('MOUSEDEV');
  If P = '' Then P := '/dev/input/mice';
  BgMsFd := SysOpen(P, O_RDONLY Or O_NONBLOCK, 0);
  If (BgMsFd < 0) And (P = '/dev/input/mice') Then
    BgMsFd := SysOpen('/dev/psaux', O_RDONLY Or O_NONBLOCK, 0);
  BgAbsFind;
  If (BgMsFd >= 0) Or BgAbsOk Then
  Begin
    BgMsOpen := True;
    BgMouseReset;
  End;
End;

Procedure BgMouseReset;
Var K : LongInt;
Begin
  If Not BgMsOpen Then
  Begin
    BgMouseOpen;
    Exit;
  End;
  If BgW > 0 Then
  Begin
    BgMinX := 0; BgMaxX := BgW - 1; BgMinY := 0; BgMaxY := BgH - 1;
  End
  Else
  Begin
    BgMinX := 0; BgMaxX := 639; BgMinY := 0; BgMaxY := 479;
  End;
  BgRange := False;
  BgMx := (BgMaxX + 1) Div 2; BgMy := (BgMaxY + 1) Div 2;
  BgMb := 0; BgMkx := 0; BgMky := 0; BgMsN := 0;
  BgCurVis := 0;
  For K := 0 To 2 Do
  Begin
    BgPressN[K] := 0; BgRelN[K] := 0;
    BgPressX[K] := 0; BgPressY[K] := 0; BgRelX[K] := 0; BgRelY[K] := 0;
  End;
End;

Function MouseDriverFound : Boolean;
Begin
  BgMouseOpen;
  MouseDriverFound := BgMsOpen;
End;

Procedure GetMouseState(Var X, Y, Button : LongInt);
Begin
  BgMouseOpen;
  BgTick;
  X := BgMx; Y := BgMy; Button := BgMb;
End;

Procedure BgInt33(Var R : Registers);
Var K : LongInt;
Begin
  Case R.AX Of
    $00, $21 :
      Begin
        BgMouseReset;
        If BgMsOpen Then
        Begin
          R.AX := $FFFF;
          R.BX := 3;
        End
        Else R.AX := 0;
      End;
    $01 : Begin Inc(BgCurVis); If BgCurVis > 1 Then BgCurVis := 1;
            BgFlush; End;
    $02 : Begin Dec(BgCurVis); BgFlush; End;
    $03 :
      Begin
        BgTick;
        R.BX := BgMb; R.CX := BgMx; R.DX := BgMy;
      End;
    $04 : Begin
            BgMx := R.CX; BgMy := R.DX;
            If BgMx < BgMinX Then BgMx := BgMinX;
            If BgMx > BgMaxX Then BgMx := BgMaxX;
            If BgMy < BgMinY Then BgMy := BgMinY;
            If BgMy > BgMaxY Then BgMy := BgMaxY;
            BgFlush;
          End;
    $05, $06 :
      Begin
        BgTick;
        K := R.BX;
        If K > 2 Then K := 2;
        If R.AX = 5 Then
        Begin
          R.BX := BgPressN[K]; R.CX := BgPressX[K]; R.DX := BgPressY[K];
          BgPressN[K] := 0;
        End
        Else
        Begin
          R.BX := BgRelN[K]; R.CX := BgRelX[K]; R.DX := BgRelY[K];
          BgRelN[K] := 0;
        End;
        R.AX := BgMb;
      End;
    $07 : Begin
            BgMinX := R.CX; BgMaxX := R.DX; BgRange := True;
            If BgMx < BgMinX Then BgMx := BgMinX;
            If BgMx > BgMaxX Then BgMx := BgMaxX;
          End;
    $08 : Begin
            BgMinY := R.CX; BgMaxY := R.DX; BgRange := True;
            If BgMy < BgMinY Then BgMy := BgMinY;
            If BgMy > BgMaxY Then BgMy := BgMaxY;
          End;
    $0B : Begin
            BgTick;
            R.CX := BgMkx And $FFFF; R.DX := BgMky And $FFFF;
            BgMkx := 0; BgMky := 0;
          End;
    $1F : R.AX := $FFFF;
    $20 : R.AX := $FFFF;
    $24 : Begin R.BX := $0626; R.CX := $0400; End;
  End;
End;

{ Intr (appel du compilateur) : seule l'interruption 33h (souris) est
  emulee }
Procedure Intr_G(IntNo : LongInt; Var Regs : Registers);
Begin
  If IntNo = $33 Then BgInt33(Regs);
End;

{ ---- clavier : Crt.ReadKey et KeyPressed sur la console ---- }

Const
  BgCp437 : Array[0..127] Of Word = (
    $00C7,$00FC,$00E9,$00E2,$00E4,$00E0,$00E5,$00E7,
    $00EA,$00EB,$00E8,$00EF,$00EE,$00EC,$00C4,$00C5,
    $00C9,$00E6,$00C6,$00F4,$00F6,$00F2,$00FB,$00F9,
    $00FF,$00D6,$00DC,$00A2,$00A3,$00A5,$20A7,$0192,
    $00E1,$00ED,$00F3,$00FA,$00F1,$00D1,$00AA,$00BA,
    $00BF,$2310,$00AC,$00BD,$00BC,$00A1,$00AB,$00BB,
    $2591,$2592,$2593,$2502,$2524,$2561,$2562,$2556,
    $2555,$2563,$2551,$2557,$255D,$255C,$255B,$2510,
    $2514,$2534,$252C,$251C,$2500,$253C,$255E,$255F,
    $255A,$2554,$2569,$2566,$2560,$2550,$256C,$2567,
    $2568,$2564,$2565,$2559,$2558,$2552,$2553,$256B,
    $256A,$2518,$250C,$2588,$2584,$258C,$2590,$2580,
    $03B1,$00DF,$0393,$03C0,$03A3,$03C3,$00B5,$03C4,
    $03A6,$0398,$03A9,$03B4,$221E,$03C6,$03B5,$2229,
    $2261,$00B1,$2265,$2264,$2320,$2321,$00F7,$2248,
    $00B0,$2219,$00B7,$221A,$207F,$00B2,$25A0,$00A0);

Var
  BgKq : Array[0..63] Of Word;
  BgKh, BgKt, BgPend, BgInN, BgInP, BgShift, BgEvFd : LongInt;
  BgIn : Array[0..255] Of Byte;
  BgEvOpen : Boolean;

Procedure BgKPush(K : LongInt);
Begin
  If ((BgKt + 1) And 63) = BgKh Then Exit;
  BgKq[BgKt] := K;
  BgKt := (BgKt + 1) And 63;
End;

{ page de codes 437 d'un point de code Unicode ('?' si inconnu) }
Function BgToCp437(Cp : LongInt) : LongInt;
Var I : LongInt;
Begin
  If Cp < 128 Then
  Begin
    BgToCp437 := Cp;
    Exit;
  End;
  For I := 0 To 127 Do
    If BgCp437[I] = Cp Then
    Begin
      BgToCp437 := I + 128;
      Exit;
    End;
  BgToCp437 := 63;
End;

{ Alt + caractere : code etendu de Turbo Pascal (256 + code de balayage) }
Function BgAltKey(C : LongInt) : LongInt;
Const Row1 : String[10] = 'qwertyuiop';
      Row2 : String[9] = 'asdfghjkl';
      Row3 : String[7] = 'zxcvbnm';
Var P : LongInt;
Begin
  If (C >= 65) And (C <= 90) Then C := C + 32;
  BgAltKey := 27;
  P := Pos(Chr(C), Row1);
  If (P > 0) And (C > 0) Then Begin BgAltKey := 256 + 15 + P; Exit; End;
  P := Pos(Chr(C), Row2);
  If (P > 0) And (C > 0) Then Begin BgAltKey := 256 + 29 + P; Exit; End;
  P := Pos(Chr(C), Row3);
  If (P > 0) And (C > 0) Then Begin BgAltKey := 256 + 43 + P; Exit; End;
  If (C >= 49) And (C <= 57) Then BgAltKey := 256 + 119 + C - 48
  Else If C = 48 Then BgAltKey := 256 + 129
  Else If C = 45 Then BgAltKey := 256 + 130
  Else If C = 61 Then BgAltKey := 256 + 131;
End;

{ lit les octets disponibles sur l'entree standard (sans attendre) }
Procedure BgKParse; Forward;

{ lit les octets du clavier deja signales par poll }
Procedure BgKRead;
Var R : LongInt;
Begin
  If BgInP < BgInN Then Exit;
  BgInP := 0; BgInN := 0;
  If BgEof Then Exit;
  Inc(BgSt[2]);
  R := SysRead(0, BgIn, 256);
  If R <= 0 Then
  Begin
    BgEof := True;
    Exit;
  End;
  BgInN := R;
  BgKParse;
End;

{ transforme les octets lus en touches (file BgKq) }
Procedure BgKParse;
Var B, B2, Num, F, Cp, Len : LongInt;
Begin
  While BgInP < BgInN Do
  Begin
    B := BgIn[BgInP];
    Inc(BgInP);
    If B = 27 Then
    Begin
      If BgInP >= BgInN Then
      Begin
        BgKPush(27);
        Continue;
      End;
      B2 := BgIn[BgInP];
      If (B2 = 91) Or (B2 = 79) Then
      Begin
        Inc(BgInP);
        Num := 0;
        If (BgInP < BgInN) And (BgIn[BgInP] = 91) Then
        Begin
          { ESC [ [ A..E : F1 a F5 de la console Linux }
          Inc(BgInP);
          If BgInP < BgInN Then
          Begin
            F := BgIn[BgInP]; Inc(BgInP);
            If (F >= 65) And (F <= 69) Then BgKPush(256 + 59 + F - 65);
          End;
          Continue;
        End;
        F := 0;
        While BgInP < BgInN Do
        Begin
          F := BgIn[BgInP];
          Inc(BgInP);
          If (F >= 48) And (F <= 57) Then Num := Num * 10 + F - 48
          Else If F = 59 Then
          Begin
            { parametres suivants (modificateurs) : ignores }
            While (BgInP < BgInN) And (BgIn[BgInP] >= 48) And
                  (BgIn[BgInP] <= 59) Do Inc(BgInP);
          End
          Else Break;
        End;
        Case F Of
          65 : BgKPush(256 + 72);
          66 : BgKPush(256 + 80);
          67 : BgKPush(256 + 77);
          68 : BgKPush(256 + 75);
          72 : BgKPush(256 + 71);
          70 : BgKPush(256 + 79);
          80 : BgKPush(256 + 59);
          81 : BgKPush(256 + 60);
          82 : BgKPush(256 + 61);
          83 : BgKPush(256 + 62);
          90 : BgKPush(256 + 15);
          126 :
            Case Num Of
              1, 7 : BgKPush(256 + 71);
              2 : BgKPush(256 + 82);
              3 : BgKPush(256 + 83);
              4, 8 : BgKPush(256 + 79);
              5 : BgKPush(256 + 73);
              6 : BgKPush(256 + 81);
              11..15 : BgKPush(256 + 59 + Num - 11);
              17..21 : BgKPush(256 + 64 + Num - 17);
              23 : BgKPush(256 + 133);
              24 : BgKPush(256 + 134);
            End;
        End;
      End
      Else
      Begin
        Inc(BgInP);
        BgKPush(BgAltKey(B2));
      End;
      Continue;
    End;
    If B = 127 Then BgKPush(8)
    Else If (B >= $C2) And (B < $F0) Then
    Begin
      If B < $E0 Then Begin Len := 1; Cp := B And $1F; End
      Else Begin Len := 2; Cp := B And $0F; End;
      While (Len > 0) And (BgInP < BgInN) Do
      Begin
        Cp := (Cp Shl 6) Or (BgIn[BgInP] And $3F);
        Inc(BgInP);
        Dec(Len);
      End;
      BgKPush(BgToCp437(Cp));
    End
    Else BgKPush(B);
  End;
End;

Function KeyPressed_G : Boolean;
Begin
  BgTermRaw;
  BgTick;
  KeyPressed_G := (BgKh <> BgKt) Or (BgPend > 0);
End;

Function ReadKey_G : Char;
Var K : LongInt;
Begin
  BgTermRaw;
  If BgPend > 0 Then
  Begin
    ReadKey_G := Chr(BgPend - 1);
    BgPend := 0;
    Exit;
  End;
  While True Do
  Begin
    BgFlushDue;
    If BgKh <> BgKt Then Break;
    If BgEof Then
    Begin
      ReadKey_G := #26;
      Exit;
    End;
    BgPoll(20);
    If BgKh <> BgKt Then Break;
  End;
  K := BgKq[BgKh];
  BgKh := (BgKh + 1) And 63;
  If K >= 256 Then
  Begin
    BgPend := K - 256 + 1;
    ReadKey_G := #0;
  End
  Else ReadKey_G := Chr(K);
End;

{ etat des touches de majuscules : octet du BIOS (40h:17h), lu par
  evenements /dev/input/event0 : bit 0 Maj droite, 1 Maj gauche, 2 Ctrl,
  3 Alt, 6 Verrouillage majuscules }
Function GetShiftState : Byte;
Var Ev : Array[0..15] Of Byte; N, I, Code, V, B : LongInt;
Begin
  If Not BgEvOpen Then
  Begin
    BgEvFd := SysOpen('/dev/input/event0', O_RDONLY Or O_NONBLOCK, 0);
    BgEvOpen := True;
  End;
  If BgEvFd >= 0 Then
    Repeat
      N := SysRead(BgEvFd, Ev, 16);
      If N < 16 Then Break;
      If MemW[0:LongInt(@Ev) + 8] = 1 Then
      Begin
        Code := MemW[0:LongInt(@Ev) + 10];
        V := MemL[0:LongInt(@Ev) + 12];
        B := 0;
        Case Code Of
          54 : B := 1;
          42 : B := 2;
          29, 97 : B := 4;
          56, 100 : B := 8;
        End;
        If B <> 0 Then
        Begin
          If V <> 0 Then BgShift := BgShift Or B
          Else BgShift := BgShift And (Not B);
        End
        Else If (Code = 58) And (V = 1) Then BgShift := BgShift Xor 64;
      End;
    Until False;
  GetShiftState := BgShift;
End;

{ ---- Crt : attente, son ---- }

Procedure Delay_G(Ms : Word);
Var T0, C0, Rem, Chunk : LongInt; UseT : Boolean; D : Double;
Begin
  If BgOk Then
  Begin
    BgFlush;
    BgLastFl := BgTsc;
  End;
  If Ms = 0 Then
  Begin
    BgTick;
    Exit;
  End;
  If (Not BgMsOpen) And (Not BgKbdUsed) Then
  Begin
    Inc(BgSt[3]);
    Sleep(Ms);
    Exit;
  End;
  UseT := (Not BgNoTsc) And (BgTscMs > 0) And (Ms <= 500);
  If UseT Then C0 := BgTsc Else T0 := BgNow;
  While True Do
  Begin
    If UseT Then
    Begin
      D := BgTsc - C0;
      If D < 0 Then D := D + 4294967296.0;
      Rem := Ms - Trunc(D / BgTscMs);
    End
    Else Rem := Ms - (BgNow - T0);
    If Rem <= 0 Then Break;
    Chunk := Rem;
    If BgDirty Or BgCurChange Then
      If Chunk > 4 Then Chunk := 4;
    BgPoll(Chunk);
    BgFlushDue;
  End;
  If BgDirty Or BgCurChange Then
  Begin
    BgFlush;
    BgLastFl := BgTsc;
  End;
End;

Procedure Sound_G(Hz : Word);
Begin
End;

Procedure NoSound_G;
Begin
End;

{ ---- outils de test ---- }

{ compteurs : 0 poll, 1 lectures souris, 2 lectures clavier, 3 sommeils,
  4 heures lues, 5 recopies vers l'ecran, 6 lignes, 7 pixels, 8 curseurs
  dessines, 9 ioctl du pilote, 10 BgTick, 11 paquets souris }
Function GfxStat(I : LongInt) : LongInt;
Begin
  If (I >= 0) And (I <= 15) Then GfxStat := BgSt[I] Else GfxStat := 0;
End;

Procedure GfxStatReset;
Begin
  FillChar(BgSt, SizeOf(BgSt), 0);
End;

{ somme de controle des indices de couleur de la page affichee }
Function GfxSum : LongInt;
Var I, S, A : LongInt;
Begin
  S := 0;
  A := BgPages[BgVis];
  For I := 0 To BgW * BgH - 1 Do S := S * 31 + Mem[0:A + I] + 1;
  GfxSum := S;
End;

{ ecrit la page affichee en PPM (couleurs RVB de la palette) }
Procedure GfxDump(Const FileName : String);
Var Fd, X, Y, V, A, P : LongInt; Row : Array[0..4095] Of Byte; Hd : String;
Begin
  Fd := SysOpen(FileName, O_WRONLY Or O_CREAT Or O_TRUNC, 420);
  If Fd < 0 Then Exit;
  Hd := 'P6' + #10 + BgNum(BgW) + ' ' + BgNum(BgH) + #10 + '255' + #10;
  SysPut(Fd, Hd);
  A := BgPages[BgVis];
  For Y := 0 To BgH - 1 Do
  Begin
    P := 0;
    For X := 0 To BgW - 1 Do
    Begin
      V := BgDac[BgPal[Mem[0:A + Y * BgW + X] And 15]];
      Row[P] := (V Shr 16) And 255;
      Row[P + 1] := (V Shr 8) And 255;
      Row[P + 2] := V And 255;
      P := P + 3;
    End;
    SysWrite(Fd, Row, P);
  End;
  SysClose(Fd);
End;

Function GetFPCHeapStatus : TFPCHeapStatus;
Var H : TFPCHeapStatus;
Begin
  FillChar(H, SizeOf(H), 0);
  H.CurrHeapFree := 8000000;
  GetFPCHeapStatus := H;
End;
