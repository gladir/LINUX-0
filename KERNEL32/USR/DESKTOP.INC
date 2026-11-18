{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2026
  @website(https://www.gladir.com/linux-0)
  @abstract(Target: LPC -3X)
  @description: DESKTOP.INC : moteur des environnements "compatibles GNOME"
      (apparence Adwaita : barre superieure Activites + horloge + menu
      systeme, fenetres a titre centre, vue Activites avec grille
      d'applications) et "compatibles KDE" (apparence Breeze : panneau en
      bas, lanceur d'applications, gestionnaire de taches, zone de
      notification + horloge, fenetres Breeze). Dessine sur /dev/fb0 avec
      GFX.INC, lit clavier et souris avec INPUT.INC, fenetres Terminal sur
      pty (VTVIEW.INC). Applications : fichiers .desktop de
      /usr/share/applications (Name, Exec, Terminal, NoDisplay) + Terminal.
      Deconnexion / Redemarrer / Eteindre : codes de sortie 0 / 100 / 101
      repris par k32-session. Inclure apres VTCORE, GFX, INPUT et VTVIEW. }

Const
  KD_GNOME = 1;  KD_KDE = 2;
  MAXW = 8;
  MAXA = 48;
  WK_TERM = 1;  WK_ABOUT = 2;

Type
  TWin = Record
    Used, Max : Boolean;
    Kind, Term, X, Y, W, H, SX, SY, SW, SH : LongInt;
    Title : String[40];
  End;

Var
  DeskKind : LongInt;
  TermOnly : Boolean;                { gnome-terminal / konsole : une fenetre }
  Wins : Array[0..MAXW - 1] Of TWin;
  ZOrd : Array[0..MAXW - 1] Of LongInt;
  NZ : LongInt;
  AName, AExec : Array[0..MAXA - 1] Of String[60];
  ATerm : Array[0..MAXA - 1] Of Boolean;
  NApps : LongInt;
  ExitCode_ : LongInt;
  Running : Boolean;
  { etat d'interface }
  Activities, MenuOpen, SysMenu, NeedDraw : Boolean;
  MenuSel : LongInt;
  DragW, DragMode, DragDx, DragDy : LongInt;     { 1 deplacer, 2 taille }
  FrameN : LongInt;
  Lang_ : LongInt;
  UserName_ : String;
  { rectangles de la fenetre en cours de calcul (WinRects) }
  RcX, RcY, RcW, RcH : LongInt;                 { exterieur }
  CcX, CcY : LongInt;                           { origine du contenu }
  TbH, Pad : LongInt;                           { hauteur du titre, marge }
  BcX, BcY, BcR, MxX, MiX : LongInt;            { boutons }
  BarH, PanH : LongInt;                         { barre / panneau }

Const
  DayFr : Array[0..6] Of String[9] = ('dim.', 'lun.', 'mar.', 'mer.', 'jeu.',
    'ven.', 'sam.');
  DayEn : Array[0..6] Of String[9] = ('Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri',
    'Sat');
  MonFr : Array[1..12] Of String[9] = ('janv.', 'f'#233'vr.', 'mars', 'avr.',
    'mai', 'juin', 'juil.', 'ao'#251't', 'sept.', 'oct.', 'nov.', 'd'#233'c.');
  MonEn : Array[1..12] Of String[9] = ('Jan', 'Feb', 'Mar', 'Apr', 'May',
    'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec');

{ ---- texte local (Windows-1252 : un octet par caractere) ---- }

Function T_(Const Fr, En : String) : String;
Begin
  If Lang_ = 1 Then T_ := Fr Else T_ := En;
End;

Function LangIsFr : Boolean;
Var E : String;
Begin
  E := SysGetEnv('LANGUAGE');
  If E = '' Then E := SysGetEnv('LANG');
  LangIsFr := (Copy(E, 1, 2) = 'FR') Or (Copy(E, 1, 2) = 'fr') Or (E = '');
End;

Function Two(V : LongInt) : String;
Var S : String;
Begin
  Str(V, S);
  If Length(S) < 2 Then S := '0' + S;
  Two := S;
End;

{ heure locale : H, M, jour de la semaine, jour, mois, annee }
Procedure LocalTime(Var H, M, Wd, D, Mo, Y : LongInt);
Var T, L, Days, Z, Era, Doe, Yoe, Doy, Mp : LongInt;
Begin
  T := SysTime;
  L := T + LnxTzAt(T);
  Days := L Div 86400;
  If L Mod 86400 < 0 Then Dec(Days);
  H := ((L Mod 86400) + 86400) Mod 86400 Div 3600;
  M := ((L Mod 86400) + 86400) Mod 3600 Div 60;
  Wd := (Days + 4) Mod 7;
  If Wd < 0 Then Wd := Wd + 7;
  Z := Days + 719468;
  If Z >= 0 Then Era := Z Div 146097 Else Era := (Z - 146096) Div 146097;
  Doe := Z - Era * 146097;
  Yoe := (Doe - Doe Div 1460 + Doe Div 36524 - Doe Div 146096) Div 365;
  Y := Yoe + Era * 400;
  Doy := Doe - (365 * Yoe + Yoe Div 4 - Yoe Div 100);
  Mp := (5 * Doy + 2) Div 153;
  D := Doy - (153 * Mp + 2) Div 5 + 1;
  If Mp < 10 Then Mo := Mp + 3 Else Mo := Mp - 9;
  If Mo <= 2 Then Inc(Y);
End;

Function DateStr : String;
Var H, M, Wd, D, Mo, Y : LongInt; S : String;
Begin
  LocalTime(H, M, Wd, D, Mo, Y);
  Str(D, S);
  If Lang_ = 1 Then DateStr := DayFr[Wd] + ' ' + S + ' ' + MonFr[Mo]
  Else DateStr := DayEn[Wd] + ' ' + MonEn[Mo] + ' ' + S;
End;

Function ClockStr : String;
Var H, M, Wd, D, Mo, Y : LongInt;
Begin
  LocalTime(H, M, Wd, D, Mo, Y);
  ClockStr := Two(H) + ':' + Two(M);
End;

{ ---- applications (.desktop) ---- }

Function DeskField(Const L, Key : String) : String;
Begin
  DeskField := '';
  If Copy(L, 1, Length(Key) + 1) = Key + '=' Then
    DeskField := Copy(L, Length(Key) + 2, 200);
End;

Procedure AddApp(Const N, E : String; Term : Boolean);
Begin
  If NApps >= MAXA Then Exit;
  AName[NApps] := N;
  AExec[NApps] := E;
  ATerm[NApps] := Term;
  Inc(NApps);
End;

{ nettoie une ligne Exec : retire les codes %f %u %F %U %i %c %k }
Function CleanExec(Const S : String) : String;
Var R : String; I : LongInt;
Begin
  R := '';
  I := 1;
  While I <= Length(S) Do
  Begin
    If (S[I] = '%') And (I < Length(S)) Then Inc(I)
    Else R := R + S[I];
    Inc(I);
  End;
  While (Length(R) > 0) And (R[Length(R)] = ' ') Do Delete(R, Length(R), 1);
  CleanExec := R;
End;

Procedure LoadApp(Const Path : String);
Var Fd : LongInt; L, Nm, NmL, Ex, Lg : String; Term, Hid, InEntry : Boolean;
Begin
  Fd := SysOpen(Path, O_RDONLY, 0);
  If Fd < 0 Then Exit;
  Nm := '';
  NmL := '';
  Ex := '';
  Term := False;
  Hid := False;
  InEntry := False;
  If Lang_ = 1 Then Lg := 'Name[fr]' Else Lg := 'Name[en]';
  While SysReadLine(Fd, L) Do
  Begin
    If Copy(L, 1, 1) = '[' Then InEntry := L = '[Desktop Entry]';
    If InEntry Then
    Begin
      If DeskField(L, 'Name') <> '' Then Nm := DeskField(L, 'Name');
      If DeskField(L, Lg) <> '' Then NmL := DeskField(L, Lg);
      If DeskField(L, 'Exec') <> '' Then Ex := CleanExec(DeskField(L, 'Exec'));
      If DeskField(L, 'Terminal') = 'true' Then Term := True;
      If DeskField(L, 'NoDisplay') = 'true' Then Hid := True;
    End;
  End;
  SysClose(Fd);
  If NmL <> '' Then Nm := NmL;
  If (Nm <> '') And (Ex <> '') And (Not Hid) Then AddApp(Nm, Ex, Term);
End;

Procedure LoadApps;
Var D, Ino : LongInt; Nm : String;
Begin
  NApps := 0;
  AddApp(T_('Terminal', 'Terminal'), '', True);
  D := SysOpenDir('/usr/share/applications');
  If D < 0 Then Exit;
  While SysReadDir(D, Nm, Ino) Do
    If (Length(Nm) > 8) And (Copy(Nm, Length(Nm) - 7, 8) = '.desktop') Then
      LoadApp('/usr/share/applications/' + Nm);
  SysCloseDir(D);
End;

{ ---- fenetres ---- }

Procedure ZRaise(I : LongInt);
Var K, J : LongInt;
Begin
  For K := 0 To NZ - 1 Do
    If ZOrd[K] = I Then
    Begin
      For J := K To NZ - 2 Do ZOrd[J] := ZOrd[J + 1];
      ZOrd[NZ - 1] := I;
      Exit;
    End;
End;

Function TopWin : LongInt;
Begin
  If NZ > 0 Then TopWin := ZOrd[NZ - 1] Else TopWin := -1;
End;

Procedure WinRects(I : LongInt);
Begin
  RcX := Wins[I].X;
  RcY := Wins[I].Y;
  RcW := Wins[I].W;
  RcH := Wins[I].H;
  If DeskKind = KD_GNOME Then
  Begin
    TbH := 36;
    Pad := 3;
    BcR := RcX + RcW - 26;
    BcX := RcX + RcW - 26;
    BcY := RcY + 9;
    MxX := RcX + RcW - 52;
    MiX := RcX + RcW - 78;
  End
  Else
  Begin
    TbH := 28;
    Pad := 2;
    BcR := RcX + RcW - 26;
    BcX := RcX + RcW - 26;
    BcY := RcY + 4;
    MxX := RcX + RcW - 50;
    MiX := RcX + RcW - 74;
  End;
  CcX := RcX + Pad;
  CcY := RcY + TbH;
End;

Function WorkTop : LongInt;
Begin
  If TermOnly Then WorkTop := 0
  Else If DeskKind = KD_GNOME Then WorkTop := BarH
  Else WorkTop := 0;
End;

Function WorkBot : LongInt;
Begin
  If TermOnly Then WorkBot := GH
  Else If DeskKind = KD_GNOME Then WorkBot := GH
  Else WorkBot := GH - PanH;
End;

{ taille exterieure d'une fenetre Terminal de Cols x Rows }
Procedure TermOuter(Cols, Rows : LongInt; Var W, H : LongInt);
Begin
  If DeskKind = KD_GNOME Then
  Begin
    W := Cols * GCW + 2 * 3;
    H := Rows * GCH + 36 + 3;
  End
  Else
  Begin
    W := Cols * GCW + 2 * 2;
    H := Rows * GCH + 28 + 2;
  End;
End;

Procedure WinFitTerm(I : LongInt);
Var C, R : LongInt;
Begin
  WinRects(I);
  C := (Wins[I].W - 2 * Pad) Div GCW;
  R := (Wins[I].H - TbH - Pad) Div GCH;
  If C > 150 Then C := 150;
  If R > 55 Then R := 55;
  If C < 20 Then C := 20;
  If R < 5 Then R := 5;
  TermResize(Wins[I].Term, C, R);
  TermOuter(VtCols, VtRows, Wins[I].W, Wins[I].H);
  If Wins[I].Max Then
  Begin
    Wins[I].W := GW;
    Wins[I].H := WorkBot - WorkTop;
  End;
End;

Function NewWin(Kind, Cols, Rows : LongInt; Const Title : String;
                Const Cmd : String) : LongInt;
Var I, Tn, W, H : LongInt;
Begin
  NewWin := -1;
  I := 0;
  While (I < MAXW) And Wins[I].Used Do Inc(I);
  If I >= MAXW Then Exit;
  If Kind = WK_TERM Then
  Begin
    Tn := 0;
    While (Tn < T_MAX) And Terms[Tn].Used Do Inc(Tn);
    If Tn >= T_MAX Then Exit;
    If Not TermOpen(Tn, Cols, Rows, Cmd) Then Exit;
    Wins[I].Term := Tn;
    TermOuter(Cols, Rows, W, H);
  End
  Else
  Begin
    Wins[I].Term := -1;
    W := 460;
    H := 250;
  End;
  Wins[I].Used := True;
  Wins[I].Max := False;
  Wins[I].Kind := Kind;
  Wins[I].Title := Title;
  Wins[I].W := W;
  Wins[I].H := H;
  Wins[I].X := (GW - W) Div 2 + (I Mod 4) * 28 - 40;
  Wins[I].Y := WorkTop + 40 + (I Mod 4) * 28;
  If Wins[I].X < 0 Then Wins[I].X := 0;
  If Wins[I].Y + H > WorkBot Then Wins[I].Y := WorkBot - H;
  If Wins[I].Y < WorkTop Then Wins[I].Y := WorkTop;
  ZOrd[NZ] := I;
  Inc(NZ);
  NewWin := I;
  NeedDraw := True;
End;

Procedure CloseWin(I : LongInt);
Var K, J : LongInt;
Begin
  If Not Wins[I].Used Then Exit;
  If Wins[I].Term >= 0 Then TermClose(Wins[I].Term);
  Wins[I].Used := False;
  For K := 0 To NZ - 1 Do
    If ZOrd[K] = I Then
    Begin
      For J := K To NZ - 2 Do ZOrd[J] := ZOrd[J + 1];
      Dec(NZ);
      Break;
    End;
  NeedDraw := True;
End;

Procedure ToggleMax(I : LongInt);
Begin
  If Wins[I].Max Then
  Begin
    Wins[I].Max := False;
    Wins[I].X := Wins[I].SX;
    Wins[I].Y := Wins[I].SY;
    Wins[I].W := Wins[I].SW;
    Wins[I].H := Wins[I].SH;
  End
  Else
  Begin
    Wins[I].SX := Wins[I].X;
    Wins[I].SY := Wins[I].Y;
    Wins[I].SW := Wins[I].W;
    Wins[I].SH := Wins[I].H;
    Wins[I].Max := True;
    Wins[I].X := 0;
    Wins[I].Y := WorkTop;
    Wins[I].W := GW;
    Wins[I].H := WorkBot - WorkTop;
  End;
  If Wins[I].Kind = WK_TERM Then
  Begin
    WinFitTerm(I);
    If Wins[I].Max Then
    Begin
      Wins[I].X := 0;
      Wins[I].Y := WorkTop;
    End;
  End;
  NeedDraw := True;
End;

{ ---- dessin : elements communs ---- }

Procedure TextC(X, Y, W : LongInt; Const S : String; Fg : LongInt);
Begin
  GText(X + (W - Length(S) * GCW) Div 2, Y, S, Fg, -1);
End;

Procedure IconApp(X, Y, Sz, N : LongInt);
Const Cols : Array[0..7] Of LongInt = ($3584E4, $E01B24, $33D17A, $F5C211,
  $9141AC, $FF7800, $1C71D8, $26A269);
Var C : LongInt; S : String;
Begin
  C := Cols[N Mod 8];
  If DeskKind = KD_KDE Then GFillRound(X, Y, Sz, Sz, 6, C)
  Else GFillRound(X, Y, Sz, Sz, Sz Div 4, C);
  S := Copy(AName[N], 1, 1);
  GCharScaled(X + (Sz - GCW * 2) Div 2, Y + (Sz - GCH * 2) Div 2, Ord(S[1]),
              $FFFFFF, 2);
End;

Procedure DrawWinGnome(I : LongInt; Act : Boolean);
Var C : LongInt;
Begin
  WinRects(I);
  GFillRound(RcX + 2, RcY + 4, RcW, RcH, 9, $0B0B0B);
  GFillRound(RcX, RcY, RcW, RcH, 9, $CDC7C2);
  If Act Then C := $EBEBEB Else C := $FAFAFA;
  GFillRound(RcX + 1, RcY + 1, RcW - 2, TbH + 6, 8, C);
  GFillRect(RcX + 1, RcY + TbH - 4, RcW - 2, 8, C);
  GHLine(RcX + 1, RcY + TbH - 1, RcW - 2, $CDC7C2);
  If Wins[I].Kind = WK_ABOUT Then
    GFillRect(RcX + 1, RcY + TbH, RcW - 2, RcH - TbH - 1, $FAFAFA)
  Else GFillRect(RcX + 1, RcY + TbH, RcW - 2, RcH - TbH - 1, $000000);
  TextC(RcX, RcY + 10, RcW, Wins[I].Title, $2E3436);
  GFillCircle(BcX + 9, BcY + 9, 10, $DDDAD6);
  GText(BcX + 5, BcY + 1, 'x', $2E3436, -1);
  GFillCircle(MxX + 9, BcY + 9, 10, $DDDAD6);
  GFrame(MxX + 5, BcY + 5, 9, 9, $2E3436);
  GFillCircle(MiX + 9, BcY + 9, 10, $DDDAD6);
  GHLine(MiX + 4, BcY + 13, 10, $2E3436);
End;

Procedure DrawWinKde(I : LongInt; Act : Boolean);
Var C : LongInt;
Begin
  WinRects(I);
  GFillRect(RcX + 3, RcY + 3, RcW, RcH, $1D2123);
  If Act Then C := $475057 Else C := $7A848A;
  GFillRect(RcX, RcY, RcW, RcH, C);
  GFillRect(RcX, RcY, RcW, TbH, C);
  If Act Then GHLine(RcX, RcY + TbH - 1, RcW, $3DAEE9);
  If Wins[I].Kind = WK_ABOUT Then
    GFillRect(RcX + Pad, RcY + TbH, RcW - 2 * Pad, RcH - TbH - Pad, $EFF0F1)
  Else GFillRect(RcX + Pad, RcY + TbH, RcW - 2 * Pad, RcH - TbH - Pad,
                 $000000);
  GText(RcX + 30, RcY + 6, Wins[I].Title, $FFFFFF, -1);
  GFillRound(RcX + 6, RcY + 6, 16, 16, 4, $3DAEE9);
  GText(BcX + 4, BcY + 2, 'x', $FFFFFF, -1);
  GFrame(MxX + 5, BcY + 5, 11, 11, $FFFFFF);
  GHLine(MiX + 5, BcY + 14, 11, $FFFFFF);
End;

Procedure DrawAboutText(I : LongInt);
Var X, Y : LongInt;
Begin
  WinRects(I);
  X := RcX + 24;
  Y := RcY + TbH + 20;
  If DeskKind = KD_GNOME Then
  Begin
    GText(X, Y, T_('Environnement compatible GNOME', 'GNOME-compatible ' +
                   'environment'), $2E3436, -1);
    GText(X, Y + 22, 'Adwaita - LINUX-0 KERNEL32', $5E5C64, -1);
  End
  Else
  Begin
    GText(X, Y, T_('Environnement compatible KDE', 'KDE-compatible ' +
                   'environment'), $232629, -1);
    GText(X, Y + 22, 'Breeze - LINUX-0 KERNEL32', $5E5C64, -1);
  End;
  GText(X, Y + 54, T_('Sans serveur X (phase 2) : dessin direct sur',
                      'No X server (phase 2): drawing directly on'),
        $5E5C64, -1);
  GText(X, Y + 74, '/dev/fb0, terminal VT100 sur pty.', $5E5C64, -1);
End;

Procedure DrawWindows;
Var K, I : LongInt;
Begin
  For K := 0 To NZ - 1 Do
  Begin
    I := ZOrd[K];
    If DeskKind = KD_GNOME Then DrawWinGnome(I, K = NZ - 1)
    Else DrawWinKde(I, K = NZ - 1);
    WinRects(I);
    If Wins[I].Kind = WK_TERM Then TermDraw(Wins[I].Term, CcX, CcY)
    Else DrawAboutText(I);
  End;
End;

{ ---- GNOME : barre superieure, menu systeme, vue Activites ---- }

Procedure DrawBarGnome;
Var S : String; X : LongInt;
Begin
  GFillRect(0, 0, GW, BarH, $000000);
  If Activities Then GFillRound(8, 3, 100, BarH - 6, 10, $3F3F3F);
  GText(18, 6, T_('Activit'#233's', 'Activities'), $FFFFFF, -1);
  S := DateStr + '  ' + ClockStr;
  GText((GW - Length(S) * GCW) Div 2, 6, S, $FFFFFF, -1);
  X := GW - 120;
  { icones du menu systeme : reseau, son, alimentation }
  GFillRect(X, 14, 3, 6, $FFFFFF);
  GFillRect(X + 5, 10, 3, 10, $FFFFFF);
  GFillRect(X + 10, 6, 3, 14, $FFFFFF);
  GFillCircle(X + 30, 13, 6, $FFFFFF);
  GFillCircle(X + 30, 13, 3, $000000);
  GText(X - 8 - Length(UserName_) * GCW, 6, UserName_, $FFFFFF, -1);
  If SysMenu Then GFillRound(GW - 70, 3, 62, BarH - 6, 10, $3F3F3F);
  GFillCircle(GW - 40, 14, 7, $FFFFFF);
  GFillCircle(GW - 40, 14, 4, $000000);
  GFillRect(GW - 41, 5, 3, 9, $FFFFFF);
End;

{ menu deroulant simple : Items (lignes separees par #10), position, selection }
Var
  PopItems : String;
  PopX, PopY, PopW, PopN : LongInt;

Procedure PopOpen(X, Y : LongInt; Const Items : String);
Var I : LongInt;
Begin
  PopItems := Items;
  PopN := 1;
  PopW := 0;
  For I := 1 To Length(Items) Do
    If Items[I] = #10 Then Inc(PopN);
  PopW := 180;
  PopX := X;
  PopY := Y;
  MenuSel := -1;
End;

Function PopItem(N : LongInt) : String;
Var I, C : LongInt; S : String;
Begin
  S := '';
  C := 0;
  For I := 1 To Length(PopItems) Do
  Begin
    If PopItems[I] = #10 Then
    Begin
      Inc(C);
      If C > N Then Break;
    End
    Else If C = N Then S := S + PopItems[I];
  End;
  PopItem := S;
End;

Procedure DrawPopup;
Var I : LongInt; S : String; Bg : LongInt;
Begin
  If DeskKind = KD_GNOME Then Bg := $2D2D2D Else Bg := $31363B;
  GFillRound(PopX, PopY, PopW, PopN * 30 + 10, 8, Bg);
  For I := 0 To PopN - 1 Do
  Begin
    S := PopItem(I);
    If I = MenuSel Then
    Begin
      If DeskKind = KD_GNOME Then GFillRound(PopX + 4, PopY + 5 + I * 30,
                                            PopW - 8, 28, 6, $4A4A4A)
      Else GFillRect(PopX + 4, PopY + 5 + I * 30, PopW - 8, 28, $3DAEE9);
    End;
    GText(PopX + 14, PopY + 11 + I * 30, S, $FFFFFF, -1);
  End;
End;

Procedure DrawActivities;
Var I, Cols, X, Y, Cell, Per : LongInt;
Begin
  GShade(0, BarH, GW, GH - BarH, 55);
  { champ de recherche }
  GFillRound(GW Div 2 - 160, BarH + 24, 320, 30, 15, $FFFFFF);
  GText(GW Div 2 - 140, BarH + 31, T_('Tapez pour rechercher', 'Type to ' +
        'search'), $77767B, -1);
  { grille d'applications }
  Cell := 130;
  Per := (GW - 240) Div Cell;
  If Per < 1 Then Per := 1;
  For I := 0 To NApps - 1 Do
  Begin
    X := 120 + (I Mod Per) * Cell + (Cell - 72) Div 2;
    Y := BarH + 100 + (I Div Per) * 120;
    IconApp(X, Y, 72, I);
    GText(X + 36 - Length(Copy(AName[I], 1, 14)) * GCW Div 2, Y + 82,
          Copy(AName[I], 1, 14), $FFFFFF, -1);
  End;
  { dock a gauche }
  GFillRound(10, BarH + 120, 64, 70 + NApps * 0, 10, $1A1A1A);
  If NApps > 0 Then IconApp(18, BarH + 140, 48, 0);
End;

{ ---- KDE : panneau, lanceur ---- }

Procedure DrawPanelKde;
Var X, K, I : LongInt; S : String;
Begin
  GFillRect(0, GH - PanH, GW, PanH, $232629);
  GHLine(0, GH - PanH, GW, $3DAEE9);
  If MenuOpen Then GFillRect(4, GH - PanH + 3, 44, PanH - 6, $3DAEE9)
  Else GFillRect(4, GH - PanH + 3, 44, PanH - 6, $31363B);
  GFillRound(12, GH - PanH + 9, 28, 22, 6, $FCFCFC);
  GText(14, GH - PanH + 12, 'K', $3DAEE9, -1);
  GText(24, GH - PanH + 12, '32', $232629, -1);
  X := 64;
  For K := 0 To NZ - 1 Do
  Begin
    I := ZOrd[K];
    If K = NZ - 1 Then GFillRect(X, GH - PanH + 3, 150, PanH - 6, $31363B)
    Else GFillRect(X, GH - PanH + 3, 150, PanH - 6, $2A2E32);
    If K = NZ - 1 Then GFillRect(X, GH - 5, 150, 2, $3DAEE9);
    S := Copy(Wins[I].Title, 1, 15);
    GText(X + 10, GH - PanH + 12, S, $FCFCFC, -1);
    X := X + 156;
  End;
  { zone de notification et horloge }
  GFillRect(GW - 180, GH - PanH + 12, 3, 8, $EFF0F1);
  GFillRect(GW - 175, GH - PanH + 8, 3, 12, $EFF0F1);
  GFillRect(GW - 170, GH - PanH + 4, 3, 16, $EFF0F1);
  GFillCircle(GW - 140, GH - PanH + 18, 6, $EFF0F1);
  S := ClockStr;
  GText(GW - 60 - Length(S) * GCW Div 2, GH - PanH + 5, S, $FCFCFC, -1);
  GText(GW - 60 - Length(DateStr) * GCW Div 2, GH - PanH + 22,
        DateStr, $BDC3C7, -1);
End;

Procedure DrawLauncherKde;
Var I, Y, W, H, X : LongInt;
Begin
  W := 360;
  H := 400;
  X := 4;
  Y := GH - PanH - H;
  GFillRect(X, Y, W, H, $31363B);
  GFrame(X, Y, W, H, $3DAEE9);
  GFillRect(X, Y, W, 44, $232629);
  GText(X + 14, Y + 14, UserName_ + '@' + SysGetEnv('HOSTNAME'), $FCFCFC, -1);
  For I := 0 To NApps - 1 Do
  Begin
    If I = MenuSel Then GFillRect(X + 4, Y + 50 + I * 28, W - 8, 26, $3DAEE9);
    IconApp(X + 10, Y + 52 + I * 28, 22, I);
    GText(X + 44, Y + 54 + I * 28, AName[I], $FCFCFC, -1);
  End;
  { boutons du bas }
  Y := GH - PanH - 40;
  GFillRect(X, Y, W, 40, $232629);
  GText(X + 14, Y + 12, T_('Quitter', 'Log out'), $FCFCFC, -1);
  GText(X + 130, Y + 12, T_('Red'#233'marrer', 'Restart'), $FCFCFC, -1);
  GText(X + 250, Y + 12, T_(''#201'teindre', 'Shut down'), $FCFCFC, -1);
  If MenuSel >= 1000 Then
    GFrame(X + 6 + (MenuSel - 1000) * 120, Y + 6, 110, 28, $3DAEE9);
End;

{ ---- fond d'ecran ---- }

Procedure DrawBackground;
Begin
  If DeskKind = KD_GNOME Then GGradV(0, 0, GW, GH, $245A91, $7B3F73)
  Else GGradV(0, 0, GW, GH, $1D99F3, $0F3D63);
End;

Procedure DrawAll;
Begin
  If TermOnly Then GFillRect(0, 0, GW, GH, $000000)
  Else DrawBackground;
  DrawWindows;
  If Not TermOnly Then
  Begin
    If DeskKind = KD_GNOME Then
    Begin
      DrawBarGnome;
      If Activities Then DrawActivities;
      If SysMenu Then DrawPopup;
    End
    Else
    Begin
      DrawPanelKde;
      If MenuOpen Then DrawLauncherKde;
    End;
  End;
  GFlush;
  If InMsFd >= 0 Then GCursorShow(InMx, InMy);
  NeedDraw := False;
End;

{ ---- actions ---- }

Procedure LaunchApp(N : LongInt);
Var C : String; W : LongInt;
Begin
  If N = 0 Then
    W := NewWin(WK_TERM, 80, 24, 'Terminal', '')
  Else
  Begin
    C := AExec[N] + '; echo; echo "[' +
         T_('Termin'#233' : Entr'#233'e pour fermer',
         'Done: Enter to close') + ']"; read x';
    W := NewWin(WK_TERM, 80, 24, AName[N], C);
  End;
  Activities := False;
  MenuOpen := False;
  SysMenu := False;
End;

Procedure DoAbout;
Var W : LongInt;
Begin
  W := NewWin(WK_ABOUT, 0, 0, T_(''#192' propos', 'About'), '');
End;

Procedure Quit_(Code : LongInt);
Begin
  ExitCode_ := Code;
  Running := False;
End;

{ ---- evenements ---- }

Function InRect(X, Y, Rx, Ry, Rw, Rh : LongInt) : Boolean;
Begin
  InRect := (X >= Rx) And (X < Rx + Rw) And (Y >= Ry) And (Y < Ry + Rh);
End;

{ fenetre sous le point (ordre de dessus en dessous) ; -1 si aucune }
Function WinAt(X, Y : LongInt) : LongInt;
Var K, I : LongInt;
Begin
  WinAt := -1;
  For K := NZ - 1 DownTo 0 Do
  Begin
    I := ZOrd[K];
    If InRect(X, Y, Wins[I].X, Wins[I].Y, Wins[I].W, Wins[I].H) Then
    Begin
      WinAt := I;
      Exit;
    End;
  End;
End;

Procedure ClickWin(I, X, Y : LongInt);
Begin
  ZRaise(I);
  WinRects(I);
  If InRect(X, Y, BcX, BcY, 20, 20) Then CloseWin(I)
  Else If InRect(X, Y, MxX, BcY, 20, 20) Then ToggleMax(I)
  Else If InRect(X, Y, MiX, BcY, 20, 20) Then
  Begin
    { reduire : sous le panneau, la fenetre passe au fond }
    If NZ > 1 Then
    Begin
      ZRaise(ZOrd[0]);
    End;
  End
  Else If Y < RcY + TbH Then
  Begin
    If Not Wins[I].Max Then
    Begin
      DragW := I;
      DragMode := 1;
      DragDx := X - RcX;
      DragDy := Y - RcY;
    End;
  End
  Else If (Wins[I].Kind = WK_TERM) And (Not Wins[I].Max) And
          (X > RcX + RcW - 16) And (Y > RcY + RcH - 16) Then
  Begin
    DragW := I;
    DragMode := 2;
  End;
  NeedDraw := True;
End;

Procedure MenuAction(S : String);
Begin
  If (S = T_('Se d'#233'connecter', 'Log out')) Then Quit_(0)
  Else If S = T_('Red'#233'marrer', 'Restart') Then Quit_(100)
  Else If S = T_(''#201'teindre', 'Power off') Then Quit_(101)
  Else If S = T_(''#192' propos', 'About') Then DoAbout
  Else If S = 'Terminal' Then LaunchApp(0);
  SysMenu := False;
End;

Procedure HandleClick(X, Y : LongInt);
Var I, N, Cell, Per, Ax, Ay : LongInt; S : String;
Begin
  { menu systeme GNOME }
  If SysMenu Then
  Begin
    If InRect(X, Y, PopX, PopY, PopW, PopN * 30 + 10) Then
    Begin
      N := (Y - PopY - 5) Div 30;
      If (N >= 0) And (N < PopN) Then MenuAction(PopItem(N));
      NeedDraw := True;
      Exit;
    End;
    SysMenu := False;
    NeedDraw := True;
  End;
  If (DeskKind = KD_GNOME) And (Not TermOnly) Then
  Begin
    If Y < BarH Then
    Begin
      If X < 120 Then Activities := Not Activities
      Else If X > GW - 80 Then
      Begin
        SysMenu := True;
        PopOpen(GW - 190, BarH + 4, T_('Se d'#233'connecter', 'Log out') + #10 +
                T_('Red'#233'marrer', 'Restart') + #10 +
                T_(''#201'teindre', 'Power off') +
                #10 + T_(''#192' propos', 'About'));
      End;
      NeedDraw := True;
      Exit;
    End;
    If Activities Then
    Begin
      Cell := 130;
      Per := (GW - 240) Div Cell;
      If Per < 1 Then Per := 1;
      For I := 0 To NApps - 1 Do
      Begin
        Ax := 120 + (I Mod Per) * Cell + (Cell - 72) Div 2;
        Ay := BarH + 100 + (I Div Per) * 120;
        If InRect(X, Y, Ax, Ay, 72, 100) Then
        Begin
          LaunchApp(I);
          Exit;
        End;
      End;
      If InRect(X, Y, 18, BarH + 140, 48, 48) Then
      Begin
        LaunchApp(0);
        Exit;
      End;
      Activities := False;
      NeedDraw := True;
      Exit;
    End;
  End;
  If (DeskKind = KD_KDE) And (Not TermOnly) Then
  Begin
    If MenuOpen Then
    Begin
      If InRect(X, Y, 4, GH - PanH - 400, 360, 360) Then
      Begin
        N := (Y - (GH - PanH - 400) - 50) Div 28;
        If (N >= 0) And (N < NApps) Then LaunchApp(N);
        Exit;
      End;
      If InRect(X, Y, 4, GH - PanH - 40, 360, 40) Then
      Begin
        N := (X - 4) Div 120;
        If N = 0 Then Quit_(0)
        Else If N = 1 Then Quit_(100)
        Else Quit_(101);
        Exit;
      End;
      MenuOpen := False;
      NeedDraw := True;
      If Y >= GH - PanH Then Exit;
    End;
    If Y >= GH - PanH Then
    Begin
      If X < 56 Then
      Begin
        MenuOpen := Not MenuOpen;
        MenuSel := -1;
      End
      Else If (X >= 64) And (X < 64 + NZ * 156) Then
      Begin
        N := (X - 64) Div 156;
        If N < NZ Then ZRaise(ZOrd[N]);
      End;
      NeedDraw := True;
      Exit;
    End;
  End;
  I := WinAt(X, Y);
  If I >= 0 Then ClickWin(I, X, Y);
End;

Procedure HandleMove(X, Y : LongInt);
Var Nw, Nh, C, R : LongInt;
Begin
  If DragW >= 0 Then
  Begin
    If (InMBtn And 1) = 0 Then
    Begin
      DragW := -1;
      Exit;
    End;
    If DragMode = 1 Then
    Begin
      Wins[DragW].X := X - DragDx;
      Wins[DragW].Y := Y - DragDy;
      If Wins[DragW].Y < WorkTop Then Wins[DragW].Y := WorkTop;
      NeedDraw := True;
    End
    Else
    Begin
      C := (X - Wins[DragW].X - 2 * 3) Div GCW;
      R := (Y - Wins[DragW].Y - 40) Div GCH;
      If C < 20 Then C := 20;
      If R < 5 Then R := 5;
      If C > 150 Then C := 150;
      If R > 55 Then R := 55;
      If (C <> Terms[Wins[DragW].Term].Cols) Or
         (R <> Terms[Wins[DragW].Term].Rows) Then
      Begin
        TermResize(Wins[DragW].Term, C, R);
        TermOuter(VtCols, VtRows, Wins[DragW].W, Wins[DragW].H);
        NeedDraw := True;
      End;
    End;
    Exit;
  End;
  If SysMenu Then
  Begin
    If InRect(X, Y, PopX, PopY, PopW, PopN * 30 + 10) Then
      MenuSel := (Y - PopY - 5) Div 30
    Else MenuSel := -1;
    NeedDraw := True;
  End;
  If MenuOpen And (DeskKind = KD_KDE) Then
  Begin
    If InRect(X, Y, 4, GH - PanH - 400, 360, 360) Then
      MenuSel := (Y - (GH - PanH - 400) - 50) Div 28
    Else If InRect(X, Y, 4, GH - PanH - 40, 360, 40) Then
      MenuSel := 1000 + (X - 4) Div 120
    Else MenuSel := -1;
    NeedDraw := True;
  End;
End;

Procedure SwitchVt(N : LongInt);
Begin
  If GTtyFd >= 0 Then
  Begin
    SysIoctlL(GTtyFd, $5606, N);
    SysIoctlL(GTtyFd, $5607, N);
  End;
  NeedDraw := True;
End;

Procedure HandleKey(K : LongInt);
Var T : LongInt;
Begin
  If InAlt And (K >= K_F1) And (K <= K_F12) Then
  Begin
    If K = K_F1 Then
    Begin
      If DeskKind = KD_GNOME Then Activities := Not Activities
      Else MenuOpen := Not MenuOpen;
      NeedDraw := True;
    End
    Else If K = K_F4 Then
    Begin
      If TopWin >= 0 Then CloseWin(TopWin);
    End
    Else SwitchVt(K - K_F1 + 1);
    Exit;
  End;
  If InAlt And (K = K_TAB) And (NZ > 1) Then
  Begin
    ZRaise(ZOrd[0]);
    NeedDraw := True;
    Exit;
  End;
  If K = K_CAD Then
  Begin
    If DeskKind = KD_GNOME Then
    Begin
      SysMenu := Not SysMenu;
      PopOpen(GW - 190, BarH + 4, T_('Se d'#233'connecter', 'Log out') + #10 +
              T_('Red'#233'marrer', 'Restart') + #10 +
              T_(''#201'teindre', 'Power off') + #10 +
              T_(''#192' propos', 'About'));
      MenuSel := 0;
    End
    Else
    Begin
      MenuOpen := Not MenuOpen;
      MenuSel := 1000;
    End;
    NeedDraw := True;
    Exit;
  End;
  If SysMenu And ((K = K_UP) Or (K = K_DOWN) Or (K = K_ENTER)) Then
  Begin
    If (K = K_DOWN) And (MenuSel < PopN - 1) Then Inc(MenuSel);
    If (K = K_UP) And (MenuSel > 0) Then Dec(MenuSel);
    If (K = K_ENTER) And (MenuSel >= 0) Then MenuAction(PopItem(MenuSel));
    NeedDraw := True;
    Exit;
  End;
  If MenuOpen And (DeskKind = KD_KDE) Then
  Begin
    If K = K_ENTER Then
    Begin
      If MenuSel >= 1000 Then
      Begin
        If MenuSel = 1000 Then Quit_(0)
        Else If MenuSel = 1001 Then Quit_(100)
        Else Quit_(101);
      End
      Else If (MenuSel >= 0) And (MenuSel < NApps) Then LaunchApp(MenuSel);
      Exit;
    End;
    If K = K_UP Then
    Begin
      If MenuSel >= 1000 Then MenuSel := NApps - 1
      Else If MenuSel > 0 Then Dec(MenuSel);
    End;
    If K = K_DOWN Then
    Begin
      If MenuSel < 0 Then MenuSel := 0
      Else If MenuSel < NApps - 1 Then Inc(MenuSel)
      Else If MenuSel < 1000 Then MenuSel := 1000;
    End;
    If (K = K_RIGHT) And (MenuSel >= 1000) And (MenuSel < 1002) Then
      Inc(MenuSel);
    If (K = K_LEFT) And (MenuSel > 1000) Then Dec(MenuSel);
    If (K <> K_ESC) Then
    Begin
      NeedDraw := True;
      Exit;
    End;
  End;
  If (K = K_ESC) And (Activities Or MenuOpen Or SysMenu) Then
  Begin
    Activities := False;
    MenuOpen := False;
    SysMenu := False;
    NeedDraw := True;
    Exit;
  End;
  T := TopWin;
  If (T >= 0) And (Wins[T].Kind = WK_TERM) Then
  Begin
    TermKey(Wins[T].Term, K);
    NeedDraw := True;
  End
  Else If (T >= 0) And (K = K_ESC) Then CloseWin(T);
End;

{ ---- initialisation et boucle ---- }

Procedure DeskInit(Kind : LongInt);
Var I : LongInt; E : String;
Begin
  DeskKind := Kind;
  Lang_ := 2;
  If LangIsFr Then Lang_ := 1;
  For I := 0 To MAXW - 1 Do Wins[I].Used := False;
  For I := 0 To T_MAX - 1 Do Terms[I].Used := False;
  NZ := 0;
  TermCur := 0;
  DragW := -1;
  Activities := False;
  MenuOpen := False;
  SysMenu := False;
  Running := True;
  ExitCode_ := 0;
  BarH := 28;
  PanH := 40;
  UserName_ := SysGetEnv('K32_USER');
  If UserName_ = '' Then UserName_ := 'root';
  TermUser := UserName_;
  TermHome := SysGetEnv('K32_HOME');
  If TermHome = '' Then TermHome := '/root';
  TermUid := 0;
  TermGid := 0;
  E := SysGetEnv('K32_UID');
  If E <> '' Then Val(E, TermUid, I);
  E := SysGetEnv('K32_GID');
  If E <> '' Then Val(E, TermGid, I);
  TermEnvN := 0;
  LoadApps;
End;

Procedure DeskRun(Const FirstCmd : String);
Var K, A, B, I, W : LongInt; Pumped, Any : Boolean; LastMin : LongInt;
Begin
  If TermOnly Then
  Begin
    W := NewWin(WK_TERM, 80, 24, 'Terminal', FirstCmd);
    If W >= 0 Then ToggleMax(W);
  End
  Else W := NewWin(WK_TERM, 80, 24, 'Terminal', FirstCmd);
  If W < 0 Then
  Begin
    ExitCode_ := 12;
    Exit;
  End;
  NeedDraw := True;
  LastMin := -1;
  While Running Do
  Begin
    Pumped := False;
    For I := 0 To T_MAX - 1 Do
      If TermPump(I) Then Pumped := True;
    For I := 0 To MAXW - 1 Do
      If Wins[I].Used And (Wins[I].Term >= 0) Then
        If Not Terms[Wins[I].Term].Alive Then CloseWin(I);
    If TermOnly And (NZ = 0) Then Running := False;
    If Pumped Then NeedDraw := True;
    If InGet(K, A, B, 30) Then
    Begin
      Case K Of
        EV_KEY : HandleKey(A);
        EV_CLICK : HandleClick(A, B Mod 100000);
        EV_MOVE :
          Begin
            HandleMove(A, B);
            If InMsFd >= 0 Then
            Begin
              GCursorHide;
              GCursorShow(A, B);
            End;
          End;
      End;
      If DragW >= 0 Then HandleMove(InMx, InMy);
    End;
    If NeedDraw Then DrawAll;
    I := Ord(ClockStr[5]);
    If I <> LastMin Then
    Begin
      LastMin := I;
      NeedDraw := True;
    End;
  End;
  For I := 0 To T_MAX - 1 Do TermClose(I);
End;
