{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2026
  @website(https://www.gladir.com/linux-0)
  @abstract(Target: LPC -3X)
  @description: WIDGETS.INC : widgets et boucle d'evenements de l'assistant.
      Etiquette multi-lignes, bouton, case a cocher, boutons radio, champ de
      texte (et mot de passe), liste deroulante a selection, barre de
      progression, journal ; boite de message modale ; focus clavier (Tab,
      Entree, Echap, fleches, Espace) et souris (clic, double clic). Les
      coordonnees des widgets sont relatives a la zone de contenu de la
      fenetre (UiOx, UiOy). UiRun rend l'identifiant du bouton active, ou 1000
      + identifiant d'un widget "notifiant" dont la valeur a change. Inclure
      apres INPUT.INC.
}

Const
  W_LABEL = 1;  W_BUTTON = 2;  W_CHECK = 3;  W_RADIO = 4;  W_EDIT = 5;
  W_LIST = 6;  W_PROG = 7;  W_LOG = 8;
  WF_DIS = 1;  WF_HID = 2;  WF_ON = 4;  WF_PWD = 8;  WF_DEF = 16;
  WF_CTR = 32;  WF_NOTIFY = 64;  WF_CANCEL = 128;  WF_DIM = 256;
  WF_ERR = 512;  WF_OK = 1024;  WF_NOFOCUS = 2048;
  MAXWID = 40;
  MAXITEMS = 1500;
  RES_TIMEOUT = -1;
  RES_NOTIFY = 1000;
  RES_REFUSE = 1099;
  MB_OK = 1;  MB_YESNO = 2;  MB_OKCANCEL = 3;

Type
  TWid = Record
    Kind, Id, X, Y, W, H, Fl, Val, Top, Cnt, Base, Grp, CPos, MaxLen :
      LongInt;
    Text : String;
  End;

Var
  UiWd, UiWdSave : Array[0..MAXWID - 1] Of TWid;
  UiWn, UiFoc, UiOx, UiOy, UiSaveN, UiSaveFoc : LongInt;
  UiItems : Array[0..MAXITEMS - 1] Of String[90];
  UiItN : LongInt;
  UiTitle, UiHead, UiFoot : String;
  UiLn : Array[0..63] Of String[120];
  UiLnN : LongInt;
  UiChanged : LongInt;
  UiNoMouse : Boolean;
  UiDlgOn : Boolean;
  UiDx, UiDy, UiDw, UiDh : LongInt;     { boite de dialogue en cours }
  UiDTitle : String;

{ ---- construction ---- }

Procedure UiClear;
Begin
  UiWn := 0;
  UiFoc := -1;
  UiItN := 0;
  UiOx := UiCx;
  UiOy := UiCy;
  UiDlgOn := False;
End;

Function UiAdd(Kind, Id, X, Y, W, H, Fl : LongInt; Const T : String) :
  LongInt;
Begin
  If UiWn >= MAXWID Then
  Begin
    UiAdd := MAXWID - 1;
    Exit;
  End;
  FillChar(UiWd[UiWn], SizeOf(TWid) - 256, 0);
  UiWd[UiWn].Kind := Kind;
  UiWd[UiWn].Id := Id;
  UiWd[UiWn].X := UiOx + X;
  UiWd[UiWn].Y := UiOy + Y;
  UiWd[UiWn].W := W;
  UiWd[UiWn].H := H;
  UiWd[UiWn].Fl := Fl;
  UiWd[UiWn].Text := T;
  UiWd[UiWn].MaxLen := 60;
  UiAdd := UiWn;
  Inc(UiWn);
End;

Function UiLabel(X, Y, W, H : LongInt; Const T : String; Fl : LongInt) :
  LongInt;
Begin
  UiLabel := UiAdd(W_LABEL, 0, X, Y, W, H, Fl Or WF_NOFOCUS, T);
End;

Function UiLabelId(Id, X, Y, W, H : LongInt; Const T : String; Fl : LongInt) :
  LongInt;
Begin
  UiLabelId := UiAdd(W_LABEL, Id, X, Y, W, H, Fl Or WF_NOFOCUS, T);
End;

Function UiButton(Id, X, Y, W : LongInt; Const T : String; Fl : LongInt) :
  LongInt;
Begin
  If W <= 0 Then W := Length(T) + 4;
  UiButton := UiAdd(W_BUTTON, Id, X, Y, W, 1, Fl, T);
End;

Function UiCheck(Id, X, Y, W : LongInt; Const T : String; On : Boolean;
  Fl : LongInt) : LongInt;
Begin
  If On Then Fl := Fl Or WF_ON;
  UiCheck := UiAdd(W_CHECK, Id, X, Y, W, 1, Fl, T);
End;

Function UiRadio(Id, Grp, X, Y, W : LongInt; Const T : String; On : Boolean;
  Fl : LongInt) : LongInt;
Var N : LongInt;
Begin
  If On Then Fl := Fl Or WF_ON;
  N := UiAdd(W_RADIO, Id, X, Y, W, 1, Fl, T);
  UiWd[N].Grp := Grp;
  UiRadio := N;
End;

Function UiEdit(Id, X, Y, W : LongInt; Const T : String; MaxLen, Fl :
  LongInt) : LongInt;
Var N : LongInt;
Begin
  N := UiAdd(W_EDIT, Id, X, Y, W, 1, Fl, T);
  UiWd[N].MaxLen := MaxLen;
  UiWd[N].CPos := Length(T);
  UiEdit := N;
End;

Function UiList(Id, X, Y, W, H, Fl : LongInt) : LongInt;
Var N : LongInt;
Begin
  N := UiAdd(W_LIST, Id, X, Y, W, H, Fl, '');
  UiWd[N].Base := UiItN;
  UiList := N;
End;

{ ajoute un element a la derniere liste creee }
Procedure UiListAdd(N : LongInt; Const S : String);
Begin
  If UiItN >= MAXITEMS Then Exit;
  UiItems[UiWd[N].Base + UiWd[N].Cnt] := S;
  Inc(UiWd[N].Cnt);
  Inc(UiItN);
End;

Function UiProg(Id, X, Y, W : LongInt) : LongInt;
Begin
  UiProg := UiAdd(W_PROG, Id, X, Y, W, 1, WF_NOFOCUS, '');
End;

Function UiLog(X, Y, W, H : LongInt) : LongInt;
Var N : LongInt;
Begin
  N := UiAdd(W_LOG, 0, X, Y, W, H, WF_NOFOCUS, '');
  UiWd[N].Base := UiItN;
  UiLog := N;
End;

Function UiFind(Id : LongInt) : LongInt;
Var I : LongInt;
Begin
  UiFind := -1;
  For I := 0 To UiWn - 1 Do
    If UiWd[I].Id = Id Then
    Begin
      UiFind := I;
      Exit;
    End;
End;

Function UiCanFocus(I : LongInt) : Boolean;
Begin
  UiCanFocus := (UiWd[I].Fl And (WF_DIS Or WF_HID Or WF_NOFOCUS)) = 0;
End;

Procedure UiFocusFirst;
Var I : LongInt;
Begin
  UiFoc := -1;
  For I := 0 To UiWn - 1 Do
    If UiCanFocus(I) Then
    Begin
      UiFoc := I;
      Exit;
    End;
End;

Procedure UiSetFocusId(Id : LongInt);
Var I : LongInt;
Begin
  I := UiFind(Id);
  If (I >= 0) And UiCanFocus(I) Then UiFoc := I;
End;

Procedure UiSetFlag(Id, Fl : LongInt; On : Boolean);
Var I : LongInt;
Begin
  I := UiFind(Id);
  If I < 0 Then Exit;
  If On Then UiWd[I].Fl := UiWd[I].Fl Or Fl
  Else UiWd[I].Fl := UiWd[I].Fl And Not Fl;
End;

Procedure UiSetEnabled(Id : LongInt; On : Boolean);
Var I : LongInt;
Begin
  I := UiFind(Id);
  If I < 0 Then Exit;
  If On Then UiWd[I].Fl := UiWd[I].Fl And Not WF_DIS
  Else UiWd[I].Fl := UiWd[I].Fl Or WF_DIS;
End;

Function UiGetText(Id : LongInt) : String;
Var I : LongInt;
Begin
  I := UiFind(Id);
  If I < 0 Then UiGetText := '' Else UiGetText := UiWd[I].Text;
End;

Procedure UiSetText(Id : LongInt; Const S : String);
Var I : LongInt;
Begin
  I := UiFind(Id);
  If I < 0 Then Exit;
  UiWd[I].Text := S;
  If UiWd[I].Kind = W_EDIT Then UiWd[I].CPos := Length(S);
End;

Function UiChecked(Id : LongInt) : Boolean;
Var I : LongInt;
Begin
  I := UiFind(Id);
  UiChecked := (I >= 0) And ((UiWd[I].Fl And WF_ON) <> 0);
End;

Procedure UiSetChecked(Id : LongInt; On : Boolean);
Var I : LongInt;
Begin
  I := UiFind(Id);
  If I < 0 Then Exit;
  If On Then UiWd[I].Fl := UiWd[I].Fl Or WF_ON
  Else UiWd[I].Fl := UiWd[I].Fl And Not WF_ON;
End;

{ indice de la selection d'une liste (-1 si vide) }
Function UiSel(Id : LongInt) : LongInt;
Var I : LongInt;
Begin
  I := UiFind(Id);
  If (I < 0) Or (UiWd[I].Cnt = 0) Then UiSel := -1 Else UiSel := UiWd[I].Val;
End;

Procedure UiSetSel(Id, V : LongInt);
Var I : LongInt;
Begin
  I := UiFind(Id);
  If I < 0 Then Exit;
  If V >= UiWd[I].Cnt Then V := UiWd[I].Cnt - 1;
  If V < 0 Then V := 0;
  UiWd[I].Val := V;
  If V < UiWd[I].Top Then UiWd[I].Top := V;
  If V >= UiWd[I].Top + UiWd[I].H Then UiWd[I].Top := V - UiWd[I].H + 1;
End;

Function UiSelText(Id : LongInt) : String;
Var I : LongInt;
Begin
  I := UiFind(Id);
  If (I < 0) Or (UiWd[I].Cnt = 0) Then UiSelText := ''
  Else UiSelText := UiItems[UiWd[I].Base + UiWd[I].Val];
End;

Procedure UiSetProg(Id, Permille : LongInt);
Var I : LongInt;
Begin
  I := UiFind(Id);
  If I < 0 Then Exit;
  If Permille < 0 Then Permille := 0;
  If Permille > 1000 Then Permille := 1000;
  UiWd[I].Val := Permille;
End;

Procedure UiLogAdd(N : LongInt; Const S : String);
Var I : LongInt;
Begin
  If UiWd[N].Cnt >= 60 Then
  Begin
    For I := 1 To UiWd[N].Cnt - 1 Do
      UiItems[UiWd[N].Base + I - 1] := UiItems[UiWd[N].Base + I];
    Dec(UiWd[N].Cnt);
    Dec(UiItN);
  End;
  If UiItN < MAXITEMS Then
  Begin
    UiItems[UiWd[N].Base + UiWd[N].Cnt] := S;
    Inc(UiWd[N].Cnt);
    Inc(UiItN);
  End;
  UiWd[N].Top := UiWd[N].Cnt - UiWd[N].H;
  If UiWd[N].Top < 0 Then UiWd[N].Top := 0;
End;

{ ---- coupe un texte en lignes de largeur W ---- }
Procedure UiWrap(Const T : String; W : LongInt);
Var I, Ws, L : LongInt; Cur, Wd : String;
Begin
  UiLnN := 0;
  If W < 4 Then W := 4;
  If W > 120 Then W := 120;
  Cur := '';
  Wd := '';
  For I := 1 To Length(T) + 1 Do
  Begin
    If (I > Length(T)) Or (T[I] = ' ') Or (T[I] = #10) Then
    Begin
      If Wd <> '' Then
      Begin
        If Cur = '' Then Cur := Wd
        Else If Length(Cur) + 1 + Length(Wd) <= W Then Cur := Cur + ' ' + Wd
        Else
        Begin
          If UiLnN < 63 Then
          Begin
            UiLn[UiLnN] := Cur;
            Inc(UiLnN);
          End;
          Cur := Wd;
        End;
        Wd := '';
      End;
      If (I <= Length(T)) And (T[I] = #10) Then
      Begin
        If UiLnN < 63 Then
        Begin
          UiLn[UiLnN] := Cur;
          Inc(UiLnN);
        End;
        Cur := '';
      End;
    End
    Else
    Begin
      Wd := Wd + T[I];
      If Length(Wd) > W Then
      Begin
        If Cur <> '' Then
        Begin
          If UiLnN < 63 Then
          Begin
            UiLn[UiLnN] := Cur;
            Inc(UiLnN);
          End;
          Cur := '';
        End;
        If UiLnN < 63 Then
        Begin
          UiLn[UiLnN] := Copy(Wd, 1, W);
          Inc(UiLnN);
        End;
        Wd := Copy(Wd, W + 1, 255);
      End;
    End;
  End;
  If (Cur <> '') And (UiLnN < 63) Then
  Begin
    UiLn[UiLnN] := Cur;
    Inc(UiLnN);
  End;
End;

{ ---- dessin ---- }

Function UiLblRole(Fl : LongInt) : LongInt;
Begin
  If (Fl And WF_ERR) <> 0 Then UiLblRole := R_ERR
  Else If (Fl And WF_OK) <> 0 Then UiLblRole := R_OK
  Else If (Fl And WF_DIM) <> 0 Then UiLblRole := R_DIM
  Else If (Fl And WF_DIS) <> 0 Then UiLblRole := R_DIS
  Else UiLblRole := R_WIN;
End;

Procedure UiDrawLabel(I : LongInt);
Var K, Role, X : LongInt;
Begin
  Role := UiLblRole(UiWd[I].Fl);
  UiWrap(UiWd[I].Text, UiWd[I].W);
  For K := 0 To UiLnN - 1 Do
    If K < UiWd[I].H Then
    Begin
      X := UiWd[I].X;
      If (UiWd[I].Fl And WF_CTR) <> 0 Then
        X := X + (UiWd[I].W - Length(UiLn[K])) Div 2;
      UiPutS(X, UiWd[I].Y + K, UiLn[K], Role);
    End;
End;

Procedure UiDrawButton(I : LongInt; Foc : Boolean);
Var Px, Py, W, H, Role, Tx, C1, C2, Bd : LongInt; T : String;
Begin
  T := UiWd[I].Text;
  If UiGfx Then
  Begin
    UiCellToPx(UiWd[I].X, UiWd[I].Y, Px, Py);
    W := UiWd[I].W * GCW;
    H := GCH - 4;
    Py := Py + 2;
    If (UiWd[I].Fl And WF_DIS) <> 0 Then
    Begin
      GFillRound(Px, Py, W, H, 3, $E4E8EF);
      GText(Px + (W - GTextW(T)) Div 2, Py + (H - GCH) Div 2 + 2, T,
        $9AA3B2, -1);
      Exit;
    End;
    If Foc Then
    Begin
      C1 := $4F98EA; C2 := $2F6DB5; Bd := $1D4E89;
    End
    Else
    Begin
      C1 := $FFFFFF; C2 := $D3DAE6; Bd := $8794AA;
      If (UiWd[I].Fl And WF_DEF) <> 0 Then Bd := $2F6DB5;
    End;
    GFillRound(Px, Py, W, H, 3, Bd);
    GGradV(Px + 1, Py + 2, W - 2, H - 4, C1, C2);
    GFillRect(Px + 3, Py + 1, W - 6, 1, C1);
    GFillRect(Px + 3, Py + H - 2, W - 6, 1, C2);
    If Foc Then Role := UiRoleFg[R_BTNF] Else Role := UiRoleFg[R_BTN];
    GText(Px + (W - GTextW(T)) Div 2, Py + (H - GCH) Div 2 + 2, T, Role, -1);
  End
  Else
  Begin
    If (UiWd[I].Fl And WF_DIS) <> 0 Then Role := R_DIS
    Else If Foc Then Role := R_BTNF
    Else Role := R_BTN;
    While (Length(T) > 0) And ((T[1] = '<') Or (T[1] = ' ')) Do
      Delete(T, 1, 1);
    While (Length(T) > 0) And ((T[Length(T)] = '>') Or
          (T[Length(T)] = ' ')) Do Delete(T, Length(T), 1);
    Tx := UiWd[I].X + (UiWd[I].W - Length(T) - 4) Div 2;
    UiPutS(Tx, UiWd[I].Y, '< ' + T + ' >', Role);
  End;
End;

Procedure UiDrawCheck(I : LongInt; Foc : Boolean);
Var Px, Py, Role : LongInt; On : Boolean;
Begin
  On := (UiWd[I].Fl And WF_ON) <> 0;
  If (UiWd[I].Fl And WF_DIS) <> 0 Then Role := R_DIS Else Role := R_WIN;
  If UiGfx Then
  Begin
    UiCellToPx(UiWd[I].X, UiWd[I].Y, Px, Py);
    Py := Py + (GCH - 16) Div 2;
    GFillRect(Px + 1, Py + 1, 16, 16, $FFFFFF);
    GFrame(Px + 1, Py + 1, 16, 16, $7A869A);
    If Foc Then GFrame(Px, Py, 18, 18, $2F6DB5);
    If On Then
    Begin
      GLine(Px + 4, Py + 9, Px + 7, Py + 13, $1D4E89);
      GLine(Px + 5, Py + 9, Px + 8, Py + 13, $1D4E89);
      GLine(Px + 7, Py + 13, Px + 14, Py + 5, $1D4E89);
      GLine(Px + 8, Py + 13, Px + 15, Py + 5, $1D4E89);
    End;
    UiPutS(UiWd[I].X + 2, UiWd[I].Y, UiWd[I].Text, Role);
    If Foc Then
      GHLine(Px + 2 * GCW, Py + 17, GTextW(UiWd[I].Text), $2F6DB5);
  End
  Else
  Begin
    If Foc Then Role := R_BTNF;
    If On Then UiPutS(UiWd[I].X, UiWd[I].Y, '[x] ' + UiWd[I].Text, Role)
    Else UiPutS(UiWd[I].X, UiWd[I].Y, '[ ] ' + UiWd[I].Text, Role);
  End;
End;

Procedure UiDrawRadio(I : LongInt; Foc : Boolean);
Var Px, Py, Role : LongInt; On : Boolean;
Begin
  On := (UiWd[I].Fl And WF_ON) <> 0;
  If (UiWd[I].Fl And WF_DIS) <> 0 Then Role := R_DIS Else Role := R_WIN;
  If UiGfx Then
  Begin
    UiCellToPx(UiWd[I].X, UiWd[I].Y, Px, Py);
    Py := Py + GCH Div 2;
    If Foc Then GFillCircle(Px + 9, Py, 9, $2F6DB5);
    GFillCircle(Px + 9, Py, 8, $7A869A);
    GFillCircle(Px + 9, Py, 7, $FFFFFF);
    If On Then GFillCircle(Px + 9, Py, 4, $1D4E89);
    UiPutS(UiWd[I].X + 2, UiWd[I].Y, UiWd[I].Text, Role);
  End
  Else
  Begin
    If Foc Then Role := R_BTNF;
    If On Then UiPutS(UiWd[I].X, UiWd[I].Y, '(*) ' + UiWd[I].Text, Role)
    Else UiPutS(UiWd[I].X, UiWd[I].Y, '( ) ' + UiWd[I].Text, Role);
  End;
End;

{ texte affiche d'un champ (mot de passe : puces) et premier caractere visible }
Procedure UiEditView(I : LongInt; Var Vis : String; Var First : LongInt);
Var Cap, L, K : LongInt; T : String;
Begin
  T := UiWd[I].Text;
  If (UiWd[I].Fl And WF_PWD) <> 0 Then
  Begin
    L := Length(T);
    T := '';
    For K := 1 To L Do
      If UiGfx Then T := T + Chr(149) Else T := T + '*';
  End;
  Cap := UiWd[I].W - 1;
  If UiGfx Then Cap := UiWd[I].W - 1;
  First := 0;
  If UiWd[I].CPos > Cap - 1 Then First := UiWd[I].CPos - Cap + 1;
  Vis := Copy(T, First + 1, Cap);
End;

Procedure UiDrawEdit(I : LongInt; Foc : Boolean);
Var Px, Py, W, H, First : LongInt; Vis : String;
Begin
  UiEditView(I, Vis, First);
  If UiGfx Then
  Begin
    UiCellToPx(UiWd[I].X, UiWd[I].Y, Px, Py);
    W := UiWd[I].W * GCW;
    H := GCH;
    If (UiWd[I].Fl And WF_DIS) <> 0 Then GFillRect(Px, Py + 1, W, H - 2,
      $E4E8EF)
    Else If (UiWd[I].Fl And WF_ERR) <> 0 Then
      GFillRect(Px, Py + 1, W, H - 2, UiRoleBg[R_FERR])
    Else GFillRect(Px, Py + 1, W, H - 2, $FFFFFF);
    If (UiWd[I].Fl And WF_ERR) <> 0 Then
    Begin
      GFrame(Px, Py + 1, W, H - 2, $C0281E);
      GFrame(Px + 1, Py + 2, W - 2, H - 4, $C0281E);
    End
    Else If Foc Then
    Begin
      GFrame(Px, Py + 1, W, H - 2, $2F6DB5);
      GFrame(Px + 1, Py + 2, W - 2, H - 4, $2F6DB5);
    End
    Else
    Begin
      GFrame(Px, Py + 1, W, H - 2, $7A869A);
      GHLine(Px + 1, Py + 2, W - 2, $C5CCD9);
    End;
    If (UiWd[I].Fl And WF_ERR) <> 0 Then
      GText(Px + 6, Py, Vis, UiRoleFg[R_FERR], -1)
    Else GText(Px + 6, Py, Vis, UiRoleFg[R_FIELD], -1);
    If Foc Then
      GFillRect(Px + 6 + (UiWd[I].CPos - First) * GCW, Py + 4, 2, H - 8,
        $1D4E89);
  End
  Else
  Begin
    If (UiWd[I].Fl And WF_ERR) <> 0 Then
    Begin
      UiFill(UiWd[I].X, UiWd[I].Y, UiWd[I].W, 1, R_FERR);
      UiPutS(UiWd[I].X, UiWd[I].Y, Vis, R_FERR);
    End
    Else
    Begin
      UiFill(UiWd[I].X, UiWd[I].Y, UiWd[I].W, 1, R_FIELD);
      UiPutS(UiWd[I].X, UiWd[I].Y, Vis, R_FIELD);
    End;
    If Foc Then
    Begin
      TxCurX := UiWd[I].X + UiWd[I].CPos - First;
      TxCurY := UiWd[I].Y;
    End;
  End;
End;

Procedure UiDrawList(I : LongInt; Foc : Boolean);
Var Px, Py, W, H, K, Idx, Role, Sb, Th, Tp, Cap : LongInt; S : String;
Begin
  W := UiWd[I].W; H := UiWd[I].H;
  Cap := W - 1;
  If UiGfx Then Cap := W - 1 Else Cap := W - 1;
  UiFill(UiWd[I].X, UiWd[I].Y, W, H, R_FIELD);
  For K := 0 To H - 1 Do
  Begin
    Idx := UiWd[I].Top + K;
    If Idx < UiWd[I].Cnt Then
    Begin
      S := UiItems[UiWd[I].Base + Idx];
      If Length(S) > Cap - 1 Then S := Copy(S, 1, Cap - 1);
      If (UiWd[I].Fl And WF_NOFOCUS) <> 0 Then Role := R_FIELD
      Else If Idx = UiWd[I].Val Then
      Begin
        If Foc Then Role := R_SEL Else Role := R_SELDIM;
        UiFill(UiWd[I].X, UiWd[I].Y + K, W - 1, 1, Role);
      End
      Else Role := R_FIELD;
      If UiGfx Then
      Begin
        If Idx = UiWd[I].Val Then
          UiFill(UiWd[I].X, UiWd[I].Y + K, W - 1, 1, Role);
        UiPutS(UiWd[I].X, UiWd[I].Y + K, ' ' + S, Role);
      End
      Else UiPutS(UiWd[I].X, UiWd[I].Y + K, ' ' + S, Role);
    End;
  End;
  { ascenseur }
  If UiWd[I].Cnt > H Then
  Begin
    If UiGfx Then
    Begin
      UiCellToPx(UiWd[I].X + W - 1, UiWd[I].Y, Px, Py);
      GFillRect(Px, Py + 2, GCW - 2, H * GCH - 4, $E4E8EF);
      Th := (H * GCH - 4) * H Div UiWd[I].Cnt;
      If Th < 12 Then Th := 12;
      Tp := (H * GCH - 4 - Th) * UiWd[I].Top Div (UiWd[I].Cnt - H);
      GFillRect(Px + 1, Py + 2 + Tp, GCW - 4, Th, $7A869A);
    End
    Else
    Begin
      For K := 0 To H - 1 Do
        UiPutCh(UiWd[I].X + W - 1, UiWd[I].Y + K, Ord('|'), R_FIELD);
      Tp := (H - 1) * UiWd[I].Top Div (UiWd[I].Cnt - H);
      UiPutCh(UiWd[I].X + W - 1, UiWd[I].Y + Tp, Ord('#'), R_FIELD);
    End;
  End;
  If UiGfx Then
  Begin
    UiCellToPx(UiWd[I].X, UiWd[I].Y, Px, Py);
    If Foc Then
    Begin
      GFrame(Px, Py, W * GCW, H * GCH, $2F6DB5);
      GFrame(Px + 1, Py + 1, W * GCW - 2, H * GCH - 2, $2F6DB5);
    End
    Else GFrame(Px, Py, W * GCW, H * GCH, $7A869A);
  End;
End;

Procedure UiDrawProg(I : LongInt);
Var Px, Py, W, H, Fw : LongInt; S : String;
Begin
  Str(UiWd[I].Val Div 10, S);
  S := S + '%';
  If UiGfx Then
  Begin
    UiCellToPx(UiWd[I].X, UiWd[I].Y, Px, Py);
    W := UiWd[I].W * GCW;
    H := GCH - 2;
    Py := Py + 1;
    GFillRound(Px, Py, W, H, 3, $9FB1CC);
    GFillRound(Px + 1, Py + 1, W - 2, H - 2, 3, $D5DBE5);
    Fw := (W - 4) * UiWd[I].Val Div 1000;
    If Fw > 0 Then
    Begin
      GGradV(Px + 2, Py + 2, Fw, H - 4, $5BA6F2, $2F6DB5);
      GFillRect(Px + 2, Py + 2, Fw, 1, $9CCBFA);
    End;
    GClipSet(Px + 2, Py, Fw, H);
    GText(Px + (W - GTextW(S)) Div 2, Py + (H - GCH) Div 2, S, $FFFFFF, -1);
    GClipSet(Px + 2 + Fw, Py, W - 2 - Fw, H);
    GText(Px + (W - GTextW(S)) Div 2, Py + (H - GCH) Div 2, S, $1E2430, -1);
    GClipAll;
  End
  Else
  Begin
    Fw := UiWd[I].W * UiWd[I].Val Div 1000;
    UiFill(UiWd[I].X, UiWd[I].Y, UiWd[I].W, 1, R_TROUGH);
    If Fw > 0 Then UiFill(UiWd[I].X, UiWd[I].Y, Fw, 1, R_BAR);
    UiPutS(UiWd[I].X + (UiWd[I].W - Length(S)) Div 2, UiWd[I].Y, S, R_BAR);
  End;
End;

Procedure UiDrawLog(I : LongInt);
Var K, Idx : LongInt;
Begin
  For K := 0 To UiWd[I].H - 1 Do
  Begin
    Idx := UiWd[I].Top + K;
    If Idx < UiWd[I].Cnt Then
      UiPutS(UiWd[I].X, UiWd[I].Y + K,
        Copy(UiItems[UiWd[I].Base + Idx], 1, UiWd[I].W), R_DIM);
  End;
End;

Procedure UiDrawWidgets;
Var I : LongInt; Foc : Boolean;
Begin
  TxCurX := -1;
  For I := 0 To UiWn - 1 Do
    If (UiWd[I].Fl And WF_HID) = 0 Then
    Begin
      Foc := (I = UiFoc);
      Case UiWd[I].Kind Of
        W_LABEL : UiDrawLabel(I);
        W_BUTTON : UiDrawButton(I, Foc);
        W_CHECK : UiDrawCheck(I, Foc);
        W_RADIO : UiDrawRadio(I, Foc);
        W_EDIT : UiDrawEdit(I, Foc);
        W_LIST : UiDrawList(I, Foc);
        W_PROG : UiDrawProg(I);
        W_LOG : UiDrawLog(I);
      End;
    End;
End;

{ dessine toute la page puis l'envoie a l'ecran }
Procedure UiRedraw;
Begin
  If UiGfx Then GClipAll;
  UiBackground(UiHead);
  UiWindow(UiTitle);
  UiDrawWidgets;
  UiFooter(UiFoot);
  UiPresent;
  If UiGfx And (InMsFd >= 0) Then GCursorShow(InMx, InMy);
End;

{ ---- boite de dialogue modale ---- }

Procedure UiDlgFrame;
Var Px, Py, W, H : LongInt;
Begin
  If UiGfx Then
  Begin
    UiCellToPx(UiDx, UiDy, Px, Py);
    W := UiDw * GCW; H := UiDh * GCH;
    GShade(Px + 6, Py + 6, W + 4, H + 4, 50);
    GFillRound(Px, Py, W, H, 4, $F3F5F9);
    GFrame(Px, Py + 4, W, H - 8, $2F6DB5);
    GFillRect(Px + 4, Py, W - 8, 1, $2F6DB5);
    GFillRect(Px + 4, Py + H - 1, W - 8, 1, $2F6DB5);
    GGradV(Px + 1, Py + 1, W - 2, GCH - 1, $3F7BC4, $23508F);
    GText(Px + GCW, Py + 1, UiDTitle, $FFFFFF, -1);
  End
  Else
  Begin
    UiFill(UiDx, UiDy, UiDw, UiDh, R_WIN);
    UiFill(UiDx, UiDy, UiDw, 1, R_TITLE);
    UiPutS(UiDx + 1, UiDy, UiDTitle, R_TITLE);
  End;
End;

Procedure UiPush;
Begin
  Move(UiWd, UiWdSave, SizeOf(UiWd));
  UiSaveN := UiWn;
  UiSaveFoc := UiFoc;
End;

Procedure UiPop;
Begin
  Move(UiWdSave, UiWd, SizeOf(UiWd));
  UiWn := UiSaveN;
  UiFoc := UiSaveFoc;
  UiDlgOn := False;
  UiOx := UiCx;
  UiOy := UiCy;
End;

Function UiRun(TimeoutMs : LongInt) : LongInt; Forward;

{ boite de message : titre, texte, un ou deux boutons (le second peut etre
  vide) ; rend 1 ou 2 }
Function UiMsgBox(Const Title, Text, B1, B2 : String) : LongInt;
Var Lines, W, H, Bw, N, R, Wc, Tw : LongInt;
Begin
  If UiGfx Then GClipAll;
  If UiHead = '' Then UiHead := ' ';
  UiRedraw;
  If UiGfx Then
  Begin
    GShade(0, 0, GW, GH, 35);
    GFlush;
  End;
  UiPush;
  Wc := UiCols - 10;
  If Wc > 64 Then Wc := 64;
  UiWrap(Text, Wc - 4);
  Lines := UiLnN;
  Tw := 24;
  For N := 0 To UiLnN - 1 Do
    If Length(UiLn[N]) > Tw Then Tw := Length(UiLn[N]);
  W := Tw + 4;
  If W < Length(Title) + 4 Then W := Length(Title) + 4;
  H := Lines + 5;
  If H > UiRows - 2 Then H := UiRows - 2;
  UiDw := W; UiDh := H;
  UiDx := (UiCols - W) Div 2;
  UiDy := (UiRows - H) Div 2;
  UiDTitle := Title;
  UiWn := 0;
  UiOx := UiDx + 2;
  UiOy := UiDy + 2;
  UiItN := UiItN;
  UiLabel(0, 0, W - 4, Lines, Text, 0);
  Bw := Length(B1) + 4;
  If B2 <> '' Then
  Begin
    UiButton(1, (W - 4) Div 2 - Bw - 1, Lines + 1, Bw, B1, WF_DEF);
    UiButton(2, (W - 4) Div 2 + 1, Lines + 1, Length(B2) + 4, B2,
      WF_CANCEL);
  End
  Else
    UiButton(1, (W - 4 - Bw) Div 2, Lines + 1, Bw, B1, WF_DEF Or WF_CANCEL);
  UiFocusFirst;
  UiDlgOn := True;
  R := UiRun(-1);
  UiPop;
  UiMsgBox := R;
End;

{ ---- evenements ---- }

Procedure UiFocusMove(Dir : LongInt);
Var I, N : LongInt;
Begin
  If UiWn = 0 Then Exit;
  I := UiFoc;
  For N := 1 To UiWn Do
  Begin
    I := (I + Dir + UiWn) Mod UiWn;
    If UiCanFocus(I) Then
    Begin
      UiFoc := I;
      Exit;
    End;
  End;
End;

Function UiDefButton : LongInt;
Var I : LongInt;
Begin
  UiDefButton := -1;
  For I := 0 To UiWn - 1 Do
    If (UiWd[I].Kind = W_BUTTON) And ((UiWd[I].Fl And WF_DEF) <> 0) And
       ((UiWd[I].Fl And (WF_DIS Or WF_HID)) = 0) Then
    Begin
      UiDefButton := UiWd[I].Id;
      Exit;
    End;
End;

Function UiCancelButton : LongInt;
Var I : LongInt;
Begin
  UiCancelButton := -1;
  For I := 0 To UiWn - 1 Do
    If (UiWd[I].Kind = W_BUTTON) And ((UiWd[I].Fl And WF_CANCEL) <> 0) And
       ((UiWd[I].Fl And (WF_DIS Or WF_HID)) = 0) Then
    Begin
      UiCancelButton := UiWd[I].Id;
      Exit;
    End;
End;

{ selection d'un bouton radio : decoche les autres du groupe }
Procedure UiRadioSelect(I : LongInt);
Var K : LongInt;
Begin
  For K := 0 To UiWn - 1 Do
    If (UiWd[K].Kind = W_RADIO) And (UiWd[K].Grp = UiWd[I].Grp) Then
      UiWd[K].Fl := UiWd[K].Fl And Not WF_ON;
  UiWd[I].Fl := UiWd[I].Fl Or WF_ON;
End;

Function UiNotifyRes(I : LongInt) : LongInt;
Begin
  If (UiWd[I].Fl And WF_NOTIFY) <> 0 Then
  Begin
    UiChanged := I;
    UiNotifyRes := RES_NOTIFY + UiWd[I].Id;
  End
  Else UiNotifyRes := 0;
End;

Procedure UiListScroll(I : LongInt);
Begin
  If UiWd[I].Val < 0 Then UiWd[I].Val := 0;
  If UiWd[I].Val >= UiWd[I].Cnt Then UiWd[I].Val := UiWd[I].Cnt - 1;
  If UiWd[I].Val < UiWd[I].Top Then UiWd[I].Top := UiWd[I].Val;
  If UiWd[I].Val >= UiWd[I].Top + UiWd[I].H Then
    UiWd[I].Top := UiWd[I].Val - UiWd[I].H + 1;
  If UiWd[I].Top < 0 Then UiWd[I].Top := 0;
End;

Function UiKeyList(I, Key : LongInt) : LongInt;
Var Old, K, C : LongInt;
Begin
  Old := UiWd[I].Val;
  Case Key Of
    K_UP : Dec(UiWd[I].Val);
    K_DOWN : Inc(UiWd[I].Val);
    K_PGUP : UiWd[I].Val := UiWd[I].Val - UiWd[I].H + 1;
    K_PGDN : UiWd[I].Val := UiWd[I].Val + UiWd[I].H - 1;
    K_HOME : UiWd[I].Val := 0;
    K_END : UiWd[I].Val := UiWd[I].Cnt - 1;
  Else
    If (Key >= 33) And (Key < 256) And (UiWd[I].Cnt > 0) Then
    Begin
      C := Ord(UpCase(Chr(Key)));
      For K := 1 To UiWd[I].Cnt Do
        If Ord(UpCase(UiItems[UiWd[I].Base + (Old + K) Mod UiWd[I].Cnt][1]))
           = C Then
        Begin
          UiWd[I].Val := (Old + K) Mod UiWd[I].Cnt;
          Break;
        End;
    End;
  End;
  UiListScroll(I);
  If UiWd[I].Val <> Old Then UiKeyList := UiNotifyRes(I)
  Else UiKeyList := 0;
End;

Function UiKeyEdit(I, Key : LongInt) : LongInt;
Var T : String; P : LongInt;
Begin
  T := UiWd[I].Text;
  P := UiWd[I].CPos;
  UiKeyEdit := 0;
  Case Key Of
    K_LEFT : If P > 0 Then Dec(P);
    K_RIGHT : If P < Length(T) Then Inc(P);
    K_HOME : P := 0;
    K_END : P := Length(T);
    K_BS : If P > 0 Then
           Begin
             Delete(T, P, 1);
             Dec(P);
           End;
    K_DEL : If P < Length(T) Then Delete(T, P + 1, 1);
    21 : Begin
           T := '';
           P := 0;
         End;
  Else
    If (Key >= 32) And (Key < 256) And (Length(T) < UiWd[I].MaxLen) Then
    Begin
      Insert(Chr(Key), T, P + 1);
      Inc(P);
    End;
  End;
  If T <> UiWd[I].Text Then UiKeyEdit := UiNotifyRes(I);
  UiWd[I].Text := T;
  UiWd[I].CPos := P;
End;

{ traite une touche ; rend le code de resultat ou 0 }
Function UiKey(Key : LongInt) : LongInt;
Var I, K, D, G : LongInt;
Begin
  UiKey := 0;
  If Key = K_ESC Then
  Begin
    K := UiCancelButton;
    If K >= 0 Then UiKey := K;
    Exit;
  End;
  If Key = K_TAB Then
  Begin
    UiFocusMove(1);
    Exit;
  End;
  If Key = K_BTAB Then
  Begin
    UiFocusMove(-1);
    Exit;
  End;
  If (UiFoc < 0) Or (UiFoc >= UiWn) Then Exit;
  I := UiFoc;
  Case UiWd[I].Kind Of
    W_BUTTON :
      If (Key = K_ENTER) Or (Key = 32) Then UiKey := UiWd[I].Id
      Else If (Key = K_DOWN) Or (Key = K_RIGHT) Then UiFocusMove(1)
      Else If (Key = K_UP) Or (Key = K_LEFT) Then UiFocusMove(-1);
    W_CHECK :
      If Key = 32 Then
      Begin
        UiWd[I].Fl := UiWd[I].Fl Xor WF_ON;
        UiKey := UiNotifyRes(I);
      End
      Else If Key = K_ENTER Then UiKey := UiDefButton
      Else If Key = K_DOWN Then UiFocusMove(1)
      Else If Key = K_UP Then UiFocusMove(-1);
    W_RADIO :
      Begin
        If (Key = K_DOWN) Or (Key = K_UP) Or (Key = K_RIGHT) Or
           (Key = K_LEFT) Then
        Begin
          If (Key = K_DOWN) Or (Key = K_RIGHT) Then D := 1 Else D := -1;
          G := UiWd[I].Grp;
          K := I;
          Repeat
            K := (K + D + UiWn) Mod UiWn;
          Until ((UiWd[K].Kind = W_RADIO) And (UiWd[K].Grp = G) And
                 UiCanFocus(K)) Or (K = I);
          If K <> I Then
          Begin
            UiFoc := K;
            UiRadioSelect(K);
            UiKey := UiNotifyRes(K);
          End;
        End
        Else If Key = 32 Then
        Begin
          UiRadioSelect(I);
          UiKey := UiNotifyRes(I);
        End
        Else If Key = K_ENTER Then UiKey := UiDefButton;
      End;
    W_EDIT :
      Begin
        If Key = K_ENTER Then
        Begin
          UiKey := UiDefButton;
          If UiKey < 0 Then UiKey := RES_REFUSE;
        End
        Else If (Key = K_DOWN) Then UiFocusMove(1)
        Else If (Key = K_UP) Then UiFocusMove(-1)
        Else UiKey := UiKeyEdit(I, Key);
      End;
    W_LIST :
      If Key = K_ENTER Then UiKey := UiDefButton
      Else UiKey := UiKeyList(I, Key);
  End;
End;

{ clic de souris en (Mx, My) pixels ; Dbl : double clic }
Function UiClick(Mx, My : LongInt; Dbl : Boolean) : LongInt;
Var Cx, Cy, I, Row, Rel : LongInt;
Begin
  UiClick := 0;
  If Not UiGfx Then Exit;
  UiPxToCell(Mx, My, Cx, Cy);
  For I := UiWn - 1 Downto 0 Do
    If ((UiWd[I].Fl And (WF_HID Or WF_DIS)) = 0) And
       (Cx >= UiWd[I].X) And (Cx < UiWd[I].X + UiWd[I].W) And
       (Cy >= UiWd[I].Y) And (Cy < UiWd[I].Y + UiWd[I].H) Then
    Begin
      Case UiWd[I].Kind Of
        W_BUTTON :
          Begin
            UiFoc := I;
            UiClick := UiWd[I].Id;
          End;
        W_CHECK :
          Begin
            UiFoc := I;
            UiWd[I].Fl := UiWd[I].Fl Xor WF_ON;
            UiClick := UiNotifyRes(I);
          End;
        W_RADIO :
          Begin
            UiFoc := I;
            UiRadioSelect(I);
            UiClick := UiNotifyRes(I);
          End;
        W_EDIT :
          Begin
            UiFoc := I;
            Rel := (Mx - UiOffX) Div GCW - UiWd[I].X;
            If Rel < 0 Then Rel := 0;
            UiWd[I].CPos := Rel;
            If UiWd[I].CPos > Length(UiWd[I].Text) Then
              UiWd[I].CPos := Length(UiWd[I].Text);
          End;
        W_LIST :
          Begin
            UiFoc := I;
            If Cx = UiWd[I].X + UiWd[I].W - 1 Then
            Begin
              If Cy < UiWd[I].Y + UiWd[I].H Div 2 Then
                UiWd[I].Val := UiWd[I].Val - UiWd[I].H + 1
              Else UiWd[I].Val := UiWd[I].Val + UiWd[I].H - 1;
              UiListScroll(I);
            End
            Else
            Begin
              Row := UiWd[I].Top + Cy - UiWd[I].Y;
              If Row < UiWd[I].Cnt Then
              Begin
                If Row <> UiWd[I].Val Then
                Begin
                  UiWd[I].Val := Row;
                  UiClick := UiNotifyRes(I);
                End
                Else If Dbl Then UiClick := UiDefButton;
              End;
            End;
          End;
      End;
      Exit;
    End;
End;

{ boucle d'evenements : rend un code de resultat (bouton, notification) ou
  RES_TIMEOUT si TimeoutMs (> 0) s'est ecoule sans evenement }
Function UiRun(TimeoutMs : LongInt) : LongInt;
Var K, A, B, R : LongInt; Need : Boolean;
Begin
  UiRun := RES_TIMEOUT;
  If UiDlgOn Then
  Begin
    UiDlgFrame;
    UiDrawWidgets;
    UiPresent;
    If UiGfx And (InMsFd >= 0) Then GCursorShow(InMx, InMy);
  End
  Else UiRedraw;
  While True Do
  Begin
    If Not InGet(K, A, B, TimeoutMs) Then
    Begin
      If TimeoutMs > 0 Then Exit;
      Continue;
    End;
    Need := False;
    R := 0;
    Case K Of
      EV_KEY :
        Begin
          If A = K_CAD Then A := K_ESC;
          If (A >= K_F1) And (A <= K_F12) And Not UiDlgOn Then
          Begin
            UiChanged := A;
            UiRun := 2000 + A - K_F1 + 1;
            Exit;
          End;
          R := UiKey(A);
          If R = -1 Then R := RES_REFUSE;
          Need := True;
        End;
      EV_CLICK :
        If Not UiNoMouse Then
        Begin
          R := UiClick(A, B Mod 100000, B >= 100000);
          Need := True;
        End;
      EV_MOVE :
        If UiGfx And (InMsFd >= 0) Then
        Begin
          GCursorHide;
          GCursorShow(A, B);
        End;
    End;
    If R <> 0 Then
    Begin
      UiRun := R;
      Exit;
    End;
    If Need Then
    Begin
      If UiDlgOn Then
      Begin
        UiDlgFrame;
        UiDrawWidgets;
        UiPresent;
        If UiGfx And (InMsFd >= 0) Then GCursorShow(InMx, InMy);
      End
      Else UiRedraw;
    End;
  End;
End;
