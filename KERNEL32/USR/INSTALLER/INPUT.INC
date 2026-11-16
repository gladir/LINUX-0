{ INPUT.INC : clavier et souris de l'assistant.
  Clavier : sur une console virtuelle (/dev/ttyN) le mode MEDIUMRAW
  (KDSKBMODE) donne les codes de touche Linux : la disposition (LAYOUTS.INC)
  est appliquee ICI (majuscules, AltGr, verrouillage majuscules), donc
  immediatement et sans table du noyau. Sur un port serie ou sans VT, les
  octets sont lus tels quels (UTF-8 et sequences ANSI : fleches, Tab...).
  Souris : /dev/input/mice (paquets PS/2 de trois octets), curseur logiciel.
  Evenements : touche (EV_KEY), clic (EV_CLICK, B=1 : double clic),
  deplacement (EV_MOVE). Inclure apres UIBASE.INC et LAYOUTS.INC. }

Const
  K_ENTER = 13;  K_TAB = 9;  K_ESC = 27;  K_BS = 8;
  K_BTAB = 300;  K_UP = 301;  K_DOWN = 302;  K_LEFT = 303;  K_RIGHT = 304;
  K_HOME = 305;  K_END = 306;  K_PGUP = 307;  K_PGDN = 308;  K_DEL = 309;
  K_INS = 310;  K_F1 = 311;  K_F2 = 312;  K_F3 = 313;  K_F4 = 314;
  K_F5 = 315;  K_F6 = 316;  K_F7 = 317;  K_F8 = 318;  K_F9 = 319;
  K_F10 = 320;  K_F11 = 321;  K_F12 = 322;  K_CAD = 330;
  EV_NONE = 0;  EV_KEY = 1;  EV_CLICK = 2;  EV_MOVE = 3;  EV_UP = 4;
  INQ = 64;

Var
  InTtyFd, InMsFd, InMode : LongInt;       { InMode : 0 octets, 1 MEDIUMRAW }
  InShift, InCtrl, InAlt, InAltGr, InCaps : Boolean;
  InLay : LongInt;
  InNorm, InShf, InAlg : Array[0..127] Of Byte;
  InQk, InQa, InQb : Array[0..INQ - 1] Of LongInt;
  InQh, InQt : LongInt;
  InRaw : Array[0..255] Of Byte;
  InRawN, InRawP : LongInt;
  InMsB : Array[0..2] Of Byte;
  InMsN : LongInt;
  InMx, InMy, InMBtn, InLastClk, InLastCx, InLastCy : LongInt;
  InMoved : Boolean;
  InIsVt : Boolean;
  InTtyName : String;

Procedure InPush(K, A, B : LongInt);
Begin
  If ((InQt + 1) Mod INQ) = InQh Then Exit;
  InQk[InQt] := K; InQa[InQt] := A; InQb[InQt] := B;
  InQt := (InQt + 1) Mod INQ;
End;

{ applique la disposition de clavier Idx (index de LayId) }
Procedure InSetLayout(Idx : LongInt);
Var I, K, Base : LongInt;
Begin
  If (Idx < 0) Or (Idx >= LayCount) Then Idx := 0;
  InLay := Idx;
  FillChar(InNorm, 128, 0);
  FillChar(InShf, 128, 0);
  FillChar(InAlg, 128, 0);
  Base := Idx * 144;
  For I := 0 To 47 Do
  Begin
    K := LayKc[I];
    If LayData[Base + I] <> 1 Then InNorm[K] := LayData[Base + I];
    If LayData[Base + 48 + I] <> 1 Then InShf[K] := LayData[Base + 48 + I];
    If LayData[Base + 96 + I] <> 1 Then InAlg[K] := LayData[Base + 96 + I];
  End;
  InNorm[57] := 32; InShf[57] := 32; InAlg[57] := 32;
  { pave numerique (verrouillage numerique suppose actif) }
  InNorm[71] := Ord('7'); InNorm[72] := Ord('8'); InNorm[73] := Ord('9');
  InNorm[74] := Ord('-'); InNorm[75] := Ord('4'); InNorm[76] := Ord('5');
  InNorm[77] := Ord('6'); InNorm[78] := Ord('+'); InNorm[79] := Ord('1');
  InNorm[80] := Ord('2'); InNorm[81] := Ord('3'); InNorm[82] := Ord('0');
  InNorm[83] := Ord('.'); InNorm[55] := Ord('*'); InNorm[98] := Ord('/');
End;

Function InIsLetter(C : LongInt) : Boolean;
Begin
  InIsLetter := ((C >= 97) And (C <= 122)) Or ((C >= 224) And (C <= 254) And
    (C <> 247));
End;

{ un code de touche (MEDIUMRAW) -> evenement }
Procedure InKeyCode(Code : LongInt; Rel : Boolean);
Var C, Sh : LongInt;
Begin
  Case Code Of
    42, 54 : InShift := Not Rel;
    29, 97 : InCtrl := Not Rel;
    56 : InAlt := Not Rel;
    100 : InAltGr := Not Rel;
    58 : If Not Rel Then InCaps := Not InCaps;
  End;
  If Rel Then Exit;
  Case Code Of
    1 : InPush(EV_KEY, K_ESC, 0);
    14 : InPush(EV_KEY, K_BS, 0);
    15 : If InShift Then InPush(EV_KEY, K_BTAB, 0)
         Else InPush(EV_KEY, K_TAB, 0);
    28, 96 : InPush(EV_KEY, K_ENTER, 0);
    102 : InPush(EV_KEY, K_HOME, 0);
    103 : InPush(EV_KEY, K_UP, 0);
    104 : InPush(EV_KEY, K_PGUP, 0);
    105 : InPush(EV_KEY, K_LEFT, 0);
    106 : InPush(EV_KEY, K_RIGHT, 0);
    107 : InPush(EV_KEY, K_END, 0);
    108 : InPush(EV_KEY, K_DOWN, 0);
    109 : InPush(EV_KEY, K_PGDN, 0);
    110 : InPush(EV_KEY, K_INS, 0);
    111 : If InCtrl And InAlt Then InPush(EV_KEY, K_CAD, 0)
          Else InPush(EV_KEY, K_DEL, 0);
    59..68 : InPush(EV_KEY, K_F1 + Code - 59, 0);
    87 : InPush(EV_KEY, K_F11, 0);
    88 : InPush(EV_KEY, K_F12, 0);
  Else
    If Code < 128 Then
    Begin
      If InAltGr And (InAlg[Code] <> 0) Then C := InAlg[Code]
      Else
      Begin
        Sh := 0;
        If InShift Then Sh := 1;
        If InCaps And InIsLetter(InNorm[Code]) Then Sh := 1 - Sh;
        If Sh = 1 Then C := InShf[Code] Else C := InNorm[Code];
        If (C = 0) And (Sh = 1) Then C := InNorm[Code];
      End;
      If C <> 0 Then
      Begin
        If InCtrl Then
        Begin
          If (C >= 97) And (C <= 122) Then C := C - 96
          Else If (C >= 65) And (C <= 90) Then C := C - 64
          Else C := 0;
        End;
        If C <> 0 Then InPush(EV_KEY, C, 0);
      End;
    End;
  End;
End;

{ octets du clavier en mode "caracteres" : UTF-8 et sequences ANSI }
Function InByteAvail(Ms : LongInt) : Boolean;
Var Pf : Array[0..1] Of LongInt;
Begin
  If InRawP < InRawN Then
  Begin
    InByteAvail := True;
    Exit;
  End;
  Pf[0] := InTtyFd; Pf[1] := 1;
  InByteAvail := SysPoll(LongInt(@Pf), 1, Ms) > 0;
End;

Function InGetByte : LongInt;
Var R : LongInt;
Begin
  If InRawP >= InRawN Then
  Begin
    R := SysRead(InTtyFd, InRaw, 256);
    If R <= 0 Then
    Begin
      InGetByte := -1;
      Exit;
    End;
    InRawN := R;
    InRawP := 0;
  End;
  InGetByte := InRaw[InRawP];
  Inc(InRawP);
End;

Procedure InCooked;
Var B, B2, Num, F : LongInt; S : String;
Begin
  B := InGetByte;
  If B < 0 Then Exit;
  If B = 27 Then
  Begin
    If Not InByteAvail(60) Then
    Begin
      InPush(EV_KEY, K_ESC, 0);
      Exit;
    End;
    B2 := InGetByte;
    If (B2 = Ord('[')) Or (B2 = Ord('O')) Then
    Begin
      Num := 0;
      F := InGetByte;
      While (F >= Ord('0')) And (F <= Ord('9')) Or (F = Ord(';')) Do
      Begin
        If F <> Ord(';') Then Num := Num * 10 + F - 48;
        F := InGetByte;
      End;
      Case F Of
        Ord('A') : InPush(EV_KEY, K_UP, 0);
        Ord('B') : InPush(EV_KEY, K_DOWN, 0);
        Ord('C') : InPush(EV_KEY, K_RIGHT, 0);
        Ord('D') : InPush(EV_KEY, K_LEFT, 0);
        Ord('H') : InPush(EV_KEY, K_HOME, 0);
        Ord('F') : InPush(EV_KEY, K_END, 0);
        Ord('Z') : InPush(EV_KEY, K_BTAB, 0);
        Ord('P') : InPush(EV_KEY, K_F1, 0);
        Ord('Q') : InPush(EV_KEY, K_F2, 0);
        Ord('R') : InPush(EV_KEY, K_F3, 0);
        Ord('S') : InPush(EV_KEY, K_F4, 0);
        Ord('~') :
          Case Num Of
            1, 7 : InPush(EV_KEY, K_HOME, 0);
            2 : InPush(EV_KEY, K_INS, 0);
            3 : InPush(EV_KEY, K_DEL, 0);
            4, 8 : InPush(EV_KEY, K_END, 0);
            5 : InPush(EV_KEY, K_PGUP, 0);
            6 : InPush(EV_KEY, K_PGDN, 0);
            11..15 : InPush(EV_KEY, K_F1 + Num - 11, 0);
            17..21 : InPush(EV_KEY, K_F6 + Num - 17, 0);
            23, 24 : InPush(EV_KEY, K_F11 + Num - 23, 0);
          End;
      End;
    End;
    Exit;
  End;
  If (B = 13) Or (B = 10) Then InPush(EV_KEY, K_ENTER, 0)
  Else If (B = 127) Or (B = 8) Then InPush(EV_KEY, K_BS, 0)
  Else If B = 9 Then InPush(EV_KEY, K_TAB, 0)
  Else If B < 32 Then InPush(EV_KEY, B, 0)
  Else If B < 128 Then InPush(EV_KEY, B, 0)
  Else If (B >= $C2) And (B < $F0) Then
  Begin
    S := Chr(B);
    If B < $E0 Then F := 1 Else F := 2;
    While (F > 0) And InByteAvail(30) Do
    Begin
      S := S + Chr(InGetByte);
      Dec(F);
    End;
    S := UiFromU8(S);
    If Length(S) > 0 Then InPush(EV_KEY, Ord(S[1]), 0);
  End;
End;

{ lit les paquets de souris disponibles }
Procedure InMouseRead;
Var N, I, B, Dx, Dy, Old : LongInt; Buf : Array[0..63] Of Byte;
Begin
  N := SysRead(InMsFd, Buf, 63);
  If N <= 0 Then Exit;
  For I := 0 To N - 1 Do
  Begin
    B := Buf[I];
    If (InMsN = 0) And ((B And 8) = 0) Then Continue;
    InMsB[InMsN] := B;
    Inc(InMsN);
    If InMsN = 3 Then
    Begin
      InMsN := 0;
      Dx := InMsB[1];
      Dy := InMsB[2];
      If (InMsB[0] And $10) <> 0 Then Dx := Dx - 256;
      If (InMsB[0] And $20) <> 0 Then Dy := Dy - 256;
      InMx := InMx + Dx;
      InMy := InMy - Dy;
      If InMx < 0 Then InMx := 0;
      If InMy < 0 Then InMy := 0;
      If InMx >= GW Then InMx := GW - 1;
      If InMy >= GH Then InMy := GH - 1;
      If (Dx <> 0) Or (Dy <> 0) Then InMoved := True;
      Old := InMBtn;
      InMBtn := InMsB[0] And 7;
      If ((InMBtn And 1) <> 0) And ((Old And 1) = 0) Then
      Begin
        If InMoved Then
        Begin
          InPush(EV_MOVE, InMx, InMy);
          InMoved := False;
        End;
        If (GetTickCount - InLastClk < 450) And
           (Abs(InMx - InLastCx) < 8) And (Abs(InMy - InLastCy) < 8) Then
        Begin
          InPush(EV_CLICK, InMx, InMy + 100000);
          InLastClk := 0;
        End
        Else
        Begin
          InPush(EV_CLICK, InMx, InMy);
          InLastClk := GetTickCount;
          InLastCx := InMx; InLastCy := InMy;
        End;
      End;
    End;
  End;
  If InMoved Then
  Begin
    InPush(EV_MOVE, InMx, InMy);
    InMoved := False;
  End;
End;

{ attend un evenement au plus Ms millisecondes (Ms < 0 : sans limite) }
Procedure InPoll(Ms : LongInt);
Var Pf : Array[0..3] Of LongInt; N, R, B : LongInt;
Begin
  If InQh <> InQt Then Exit;
  Pf[0] := InTtyFd; Pf[1] := 1;
  N := 1;
  If InMsFd >= 0 Then
  Begin
    Pf[2] := InMsFd; Pf[3] := 1;
    N := 2;
  End;
  If InRawP < InRawN Then R := 1
  Else R := SysPoll(LongInt(@Pf), N, Ms);
  If R <= 0 Then Exit;
  If (InRawP < InRawN) Or ((Pf[1] Shr 16) <> 0) Then
  Begin
    If InMode = 1 Then
    Begin
      R := SysRead(InTtyFd, InRaw, 256);
      If R > 0 Then
        For B := 0 To R - 1 Do InKeyCode(InRaw[B] And $7F, (InRaw[B] And $80) <> 0);
    End
    Else
      InCooked;
  End;
  If (N = 2) And ((Pf[3] Shr 16) <> 0) Then InMouseRead;
End;

Function InGet(Var K, A, B : LongInt; Ms : LongInt) : Boolean;
Begin
  InPoll(Ms);
  If InQh = InQt Then
  Begin
    InGet := False;
    Exit;
  End;
  K := InQk[InQh]; A := InQa[InQh]; B := InQb[InQh];
  InQh := (InQh + 1) Mod INQ;
  InGet := True;
End;

Procedure InFlush;
Var Buf : Array[0..63] Of Byte;
Begin
  InQh := 0; InQt := 0; InRawN := 0; InRawP := 0;
End;

{ ouvre le clavier (Tty : chemin du terminal, '' = entree standard) et la
  souris (graphique) }
Procedure InOpen(Const Tty : String; WithMouse : Boolean);
Var I : LongInt;
Begin
  InQh := 0; InQt := 0; InRawN := 0; InRawP := 0; InMsN := 0;
  InShift := False; InCtrl := False; InAlt := False; InAltGr := False;
  InCaps := False;
  InTtyName := Tty;
  If Tty <> '' Then
  Begin
    InTtyFd := SysOpen(Tty, O_RDWR, 0);
    If InTtyFd < 0 Then InTtyFd := 0;
  End
  Else InTtyFd := 0;
  UiOutFd := 1;
  If InTtyFd > 0 Then UiOutFd := InTtyFd;
  { console virtuelle : /dev/ttyN, N chiffre }
  InIsVt := (Length(Tty) = 9) And (Copy(Tty, 1, 8) = '/dev/tty') And
            (Tty[9] >= '0') And (Tty[9] <= '9');
  UiTermRaw(InTtyFd);
  InMode := 0;
  If InIsVt Then
    If SysIoctlL(InTtyFd, $4B45, 2) = 0 Then InMode := 1;
  InMsFd := -1;
  If WithMouse Then
  Begin
    InMsFd := SysOpen('/dev/input/mice', O_RDONLY Or O_NONBLOCK, 0);
    If InMsFd < 0 Then InMsFd := SysOpen('/dev/psaux',
      O_RDONLY Or O_NONBLOCK, 0);
  End;
  InMx := GW Div 2; InMy := GH Div 2; InMBtn := 0; InLastClk := 0;
End;

Procedure InClose;
Begin
  If InMode = 1 Then SysIoctlL(InTtyFd, $4B45, 1);
  InMode := 0;
  UiTermRestore;
  If InMsFd >= 0 Then
  Begin
    SysClose(InMsFd);
    InMsFd := -1;
  End;
End;
