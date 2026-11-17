{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2026
  @website(https://www.gladir.com/linux-0)
  @abstract(Target: LPC -3X)
  @description: /bin/vi (view, ex, vim) : editeur de texte modal. Deplacements
      (hjkl, w b e W B E, 0 ^ $ | f F t T ; , % { } G gg H M L, Ctrl-F/B/D/U,
      ' `), insertion (i a I A o O R r s S C cw cc), suppression (x X dd D
      d{mouvement}), copie (y yy Y) et collage (p P), J ~ > <, recherche
      (/ ? n N, expressions regulieres), annulation (u, une etape), repetition
      (.), commandes ex (:w :q :wq :x :q! :e :r :N :d :y :s///g :g :set :!).
      Limites : lignes de 255 octets au plus (les plus longues sont
      coupees), 12000 lignes, un seul registre.
}

Program VI;

{$I REGEX.INC}

Const
  MaxL = 12000;
  MaxReg = 2000;
  K_UP = 256; K_DOWN = 257; K_RIGHT = 258; K_LEFT = 259; K_HOME = 260;
  K_END = 261; K_PGUP = 262; K_PGDN = 263; K_DEL = 264; K_EOF = -1;
  Mess : Array[1..8, 1..5] Of PChar = (
    ('Modifie depuis la derniere ecriture (! pour forcer)',
     'No write since last change (add ! to override)',
     'Nicht gespeichert (! zum Erzwingen)',
     'Sin guardar desde el ultimo cambio (! para forzar)',
     'Modificato dopo l''ultima scrittura (! per forzare)'),
    ('Motif introuvable', 'Pattern not found', 'Muster nicht gefunden',
     'Patron no encontrado', 'Modello non trovato'),
    ('Commande inconnue', 'Not an editor command', 'Unbekannter Befehl',
     'Orden desconocida', 'Comando sconosciuto'),
    ('nouveau fichier', 'new file', 'neue Datei', 'archivo nuevo',
     'nuovo file'),
    ('ecrit', 'written', 'geschrieben', 'escrito', 'scritto'),
    ('lignes longues coupees', 'long lines were split',
     'lange Zeilen geteilt', 'lineas largas partidas',
     'righe lunghe divise'),
    ('Pas de nom de fichier', 'No file name', 'Kein Dateiname',
     'Sin nombre de archivo', 'Nessun nome di file'),
    ('Usage : vi [+N] [fichier...]', 'Usage: vi [+N] [file...]',
     'Aufruf: vi [+N] [Datei...]', 'Uso: vi [+N] [archivo...]',
     'Uso: vi [+N] [file...]'));

Var
  L : Array[1..MaxL] Of String;
  Sn : Array[1..MaxL] Of String;
  NL, SnN, SnCy, SnCx : LongInt;
  RegL : Array[1..MaxReg] Of String;
  RegN : LongInt;
  RegLine : Boolean;
  Cy, Cx, Top, Left, Rows, Cols : LongInt;
  WantX : LongInt;          { colonne souhaitee pour j/k (colonne ecran) }
  FileName, AltName : String;
  Modified : Boolean;
  Msg : String;
  Quit : Boolean;
  Term, SavedTerm : TSysTermios;
  HaveTerm : Boolean;
  LastPat, LastRep : String;
  LastDir : LongInt;        { 1 avant, -1 arriere }
  OptNu, OptAi, OptIc, OptWs, OptList : Boolean;
  Marks : Array[0..25] Of LongInt;
  MarkX : Array[0..25] Of LongInt;
  LastF, LastFCh : LongInt;  { dernier f/F/t/T : type et caractere }
  { entree }
  KQ : String;               { touches rejouees (point) }
  KQPos : LongInt;
  CurKeys, LastKeys : String;
  Replaying : Boolean;
  InBuf : Array[0..255] Of Byte;
  InPos, InLen : LongInt;
  OutBuf : String;
  Dirty : Boolean;
  InsKeys : String;
  Lang : LongInt;
  EmptyBuf : Boolean;

Function PS(P : PChar) : String;
Var X : String;
Begin
  X := '';
  While P^ <> #0 Do
  Begin
    X := X + P^;
    Inc(P);
  End;
  PS := X;
End;

Function MS(N : LongInt) : String;
Begin
  MS := PS(Mess[N, Lang]);
End;

Function NumS(V : LongInt) : String;
Var S : String;
Begin
  Str(V, S);
  NumS := S;
End;

{ ------------------------------ sortie ------------------------------ }

Procedure OFlush;
Begin
  If Length(OutBuf) > 0 Then SysPut(1, OutBuf);
  OutBuf := '';
End;

Procedure OPut(Const S : String);
Begin
  If Length(OutBuf) + Length(S) > 250 Then OFlush;
  OutBuf := OutBuf + S;
End;

Procedure Goto_(R, C : LongInt);
Begin
  OPut(#27 + '[' + NumS(R) + ';' + NumS(C) + 'H');
End;

{ ------------------------------ tampon ------------------------------ }

Procedure SaveUndo;
Var I : LongInt;
Begin
  For I := 1 To NL Do Sn[I] := L[I];
  SnN := NL;
  SnCy := Cy;
  SnCx := Cx;
End;

Procedure DoUndo;
Var I, M, TY, TX : LongInt; T : String;
Begin
  M := NL;
  If SnN > M Then M := SnN;
  For I := 1 To M Do
  Begin
    T := L[I];
    L[I] := Sn[I];
    Sn[I] := T;
  End;
  I := NL;
  NL := SnN;
  SnN := I;
  TY := SnCy;
  TX := SnCx;
  SnCy := Cy;
  SnCx := Cx;
  Cy := TY;
  Cx := TX;
  If NL < 1 Then
  Begin
    NL := 1;
    L[1] := '';
  End;
  If Cy > NL Then Cy := NL;
  Modified := True;
  Dirty := True;
End;

Procedure InsLine(At : LongInt; Const S : String);
Var I : LongInt;
Begin
  If NL >= MaxL Then Exit;
  EmptyBuf := False;
  For I := NL DownTo At Do L[I + 1] := L[I];
  L[At] := S;
  Inc(NL);
  For I := 0 To 25 Do If Marks[I] >= At Then Inc(Marks[I]);
  Modified := True;
End;

Procedure DelLine(At : LongInt);
Var I : LongInt;
Begin
  For I := At To NL - 1 Do L[I] := L[I + 1];
  Dec(NL);
  If NL < 1 Then
  Begin
    NL := 1;
    L[1] := '';
    EmptyBuf := True;
  End;
  For I := 0 To 25 Do
    If Marks[I] = At Then Marks[I] := 0
    Else If Marks[I] > At Then Dec(Marks[I]);
  Modified := True;
End;

Function LenOf(Y : LongInt) : LongInt;
Begin
  LenOf := Length(L[Y]);
End;

Function Cls(Y, X : LongInt; Big : Boolean) : LongInt;
Var C : Char;
Begin
  If (X < 1) Or (X > Length(L[Y])) Then
  Begin
    Cls := 0;
    Exit;
  End;
  C := L[Y][X];
  If (C = ' ') Or (C = #9) Then Cls := 0
  Else If Big Then Cls := 1
  Else If ((C >= '0') And (C <= '9')) Or ((C >= 'a') And (C <= 'z')) Or
          ((C >= 'A') And (C <= 'Z')) Or (C = '_') Or (C >= #128) Then Cls := 1
  Else Cls := 2;
End;

{ colonne d'affichage (0 = premiere) du caractere X de la ligne Y }
Function DCol(Y, X : LongInt) : LongInt;
Var K, C : LongInt;
Begin
  C := 0;
  For K := 1 To X - 1 Do
  Begin
    If (K <= Length(L[Y])) And (L[Y][K] = #9) Then C := (C Or 7) + 1
    Else Inc(C);
  End;
  DCol := C;
End;

Function XFromCol(Y, Col : LongInt) : LongInt;
Var K, C, N : LongInt;
Begin
  C := 0;
  N := Length(L[Y]);
  K := 1;
  While K <= N Do
  Begin
    If L[Y][K] = #9 Then C := (C Or 7) + 1 Else Inc(C);
    If C > Col Then Break;
    Inc(K);
  End;
  If K > N Then K := N;
  If K < 1 Then K := 1;
  XFromCol := K;
End;

Procedure Fix(Ins : Boolean);
Var N : LongInt;
Begin
  If Cy < 1 Then Cy := 1;
  If Cy > NL Then Cy := NL;
  N := Length(L[Cy]);
  If Ins Then
  Begin
    If Cx > N + 1 Then Cx := N + 1;
  End
  Else If Cx > N Then Cx := N;
  If Cx < 1 Then Cx := 1;
End;

{ ------------------------------ ecran ------------------------------ }

Procedure Layout;
Var W : TSysWinSize;
Begin
  Rows := 24;
  Cols := 80;
  If SysGetWinSize(1, W) = 0 Then
    If (W.Row > 2) And (W.Col > 10) Then
    Begin
      Rows := W.Row;
      Cols := W.Col;
    End;
End;

Procedure Scroll;
Var C, TR : LongInt;
Begin
  TR := Rows - 1;
  If Cy < Top Then Top := Cy;
  If Cy > Top + TR - 1 Then Top := Cy - TR + 1;
  If Top < 1 Then Top := 1;
  C := DCol(Cy, Cx);
  If C < Left Then Left := C;
  If C > Left + Cols - 1 - 7 Then Left := C - (Cols - 1 - 7);
  If Left < 0 Then Left := 0;
End;

Function Expand(Y : LongInt) : String;
Var K, C : LongInt; R : String; Ch : Char;
Begin
  R := '';
  C := 0;
  For K := 1 To Length(L[Y]) Do
  Begin
    Ch := L[Y][K];
    If Ch = #9 Then
    Begin
      Repeat
        If (C >= Left) And (Length(R) < 255) Then R := R + ' ';
        Inc(C);
      Until (C And 7) = 0;
    End
    Else
    Begin
      If (Ch < ' ') Or (Ch = #127) Then
      Begin
        If (C >= Left) And (Length(R) < 254) Then
          R := R + '^' + Chr(Ord(Ch) Xor 64);
        C := C + 2;
      End
      Else
      Begin
        If (C >= Left) And (Length(R) < 255) Then R := R + Ch;
        Inc(C);
      End;
    End;
  End;
  Expand := R;
End;

Procedure Redraw(Const Mode : String);
Var I, Y, TR, Pc : LongInt; S, Pre, St : String;
Begin
  Layout;
  Scroll;
  TR := Rows - 1;
  OPut(#27 + '[?25l');
  For I := 1 To TR Do
  Begin
    Y := Top + I - 1;
    Goto_(I, 1);
    If Y <= NL Then
    Begin
      Pre := '';
      If OptNu Then
      Begin
        Pre := NumS(Y);
        While Length(Pre) < 4 Do Pre := ' ' + Pre;
        Pre := Pre + ' ';
      End;
      S := Expand(Y);
      If Length(Pre) + Length(S) > Cols Then
        S := Copy(S, 1, Cols - Length(Pre));
      OPut(Pre + S);
    End
    Else OPut('~');
    OPut(#27 + '[K');
  End;
  Goto_(Rows, 1);
  If Msg <> '' Then St := Msg
  Else
  Begin
    St := Mode;
    If St <> '' Then St := St + '  ';
    St := St + '"' + FileName + '"';
    If Modified Then St := St + ' [+]';
    St := St + '  ' + NumS(Cy) + ',' + NumS(Cx) + '  ' + NumS(NL) + 'L';
  End;
  If Length(St) > Cols - 1 Then St := Copy(St, 1, Cols - 1);
  OPut(#27 + '[7m' + St + #27 + '[m' + #27 + '[K');
  Pc := 0;
  If OptNu Then Pc := 5;
  Goto_(Cy - Top + 1, DCol(Cy, Cx) - Left + 1 + Pc);
  OPut(#27 + '[?25h');
  OFlush;
  Dirty := False;
End;

{ ------------------------------ entree ------------------------------ }

Function RawByte : LongInt;
Begin
  If InPos >= InLen Then
  Begin
    InLen := SysRead(0, InBuf[0], 256);
    InPos := 0;
    If InLen <= 0 Then
    Begin
      InLen := 0;
      RawByte := K_EOF;
      Exit;
    End;
  End;
  RawByte := InBuf[InPos];
  Inc(InPos);
End;

Function MoreInput(Ms : LongInt) : Boolean;
Var Pf : Array[0..1] Of LongInt;
Begin
  If InPos < InLen Then
  Begin
    MoreInput := True;
    Exit;
  End;
  Pf[0] := 0;
  Pf[1] := 1;
  MoreInput := SysPoll(LongInt(@Pf), 1, Ms) > 0;
End;

Function GetKey : LongInt;
Var C, D, E : LongInt;
Begin
  If KQPos <= Length(KQ) Then
  Begin
    GetKey := Ord(KQ[KQPos]);
    Inc(KQPos);
    If KQPos > Length(KQ) Then
    Begin
      KQ := '';
      KQPos := 1;
      Replaying := False;
    End;
    Exit;
  End;
  C := RawByte;
  If C = 27 Then
    If MoreInput(40) Then
    Begin
      D := RawByte;
      If (D = Ord('[')) Or (D = Ord('O')) Then
      Begin
        E := RawByte;
        Case E Of
          Ord('A') : C := K_UP;
          Ord('B') : C := K_DOWN;
          Ord('C') : C := K_RIGHT;
          Ord('D') : C := K_LEFT;
          Ord('H') : C := K_HOME;
          Ord('F') : C := K_END;
          Ord('1'), Ord('7') : Begin RawByte; C := K_HOME; End;
          Ord('4'), Ord('8') : Begin RawByte; C := K_END; End;
          Ord('3') : Begin RawByte; C := K_DEL; End;
          Ord('5') : Begin RawByte; C := K_PGUP; End;
          Ord('6') : Begin RawByte; C := K_PGDN; End;
        End;
      End
      Else
      Begin
        { Echap suivi d'une touche : Echap puis la touche }
        InPos := InPos - 1;
        If InPos < 0 Then InPos := 0;
      End;
    End;
  If (C >= 0) And (C < 256) And (Length(CurKeys) < 250) And (Not Replaying) Then
    CurKeys := CurKeys + Chr(C);
  GetKey := C;
End;

{ ------------------------------ registre ------------------------------ }

Procedure YankLines(Y1, Y2 : LongInt);
Var I : LongInt;
Begin
  RegN := 0;
  For I := Y1 To Y2 Do
    If RegN < MaxReg Then
    Begin
      Inc(RegN);
      RegL[RegN] := L[I];
    End;
  RegLine := True;
End;

{ copie de (Y1,X1) a (Y2,X2) inclus }
Procedure YankChars(Y1, X1, Y2, X2 : LongInt);
Var I : LongInt;
Begin
  RegLine := False;
  RegN := 0;
  If Y1 = Y2 Then
  Begin
    RegN := 1;
    RegL[1] := Copy(L[Y1], X1, X2 - X1 + 1);
    Exit;
  End;
  For I := Y1 To Y2 Do
    If RegN < MaxReg Then
    Begin
      Inc(RegN);
      If I = Y1 Then RegL[RegN] := Copy(L[I], X1, 255)
      Else If I = Y2 Then RegL[RegN] := Copy(L[I], 1, X2)
      Else RegL[RegN] := L[I];
    End;
End;

Procedure DelChars(Y1, X1, Y2, X2 : LongInt);
Var I : LongInt;
Begin
  If Y1 = Y2 Then
  Begin
    Delete(L[Y1], X1, X2 - X1 + 1);
    Modified := True;
    Exit;
  End;
  L[Y1] := Copy(L[Y1], 1, X1 - 1) + Copy(L[Y2], X2 + 1, 255);
  For I := Y2 DownTo Y1 + 1 Do DelLine(I);
  Modified := True;
End;

Procedure Put(After : Boolean);
Var I, K : LongInt; T : String;
Begin
  If RegN = 0 Then Exit;
  If RegLine Then
  Begin
    If After Then K := Cy + 1 Else K := Cy;
    For I := 1 To RegN Do InsLine(K + I - 1, RegL[I]);
    Cy := K;
    Cx := 1;
    Fix(False);
    Exit;
  End;
  If After And (Length(L[Cy]) > 0) Then Inc(Cx);
  If RegN = 1 Then
  Begin
    Insert(RegL[1], L[Cy], Cx);
    Cx := Cx + Length(RegL[1]) - 1;
    If Cx < 1 Then Cx := 1;
    Modified := True;
    Exit;
  End;
  T := Copy(L[Cy], Cx, 255);
  L[Cy] := Copy(L[Cy], 1, Cx - 1) + RegL[1];
  For I := 2 To RegN Do
    If I = RegN Then InsLine(Cy + I - 1, RegL[I] + T)
    Else InsLine(Cy + I - 1, RegL[I]);
  Modified := True;
End;

{ ------------------------------ recherche ------------------------------ }

Var
  SPr : LongInt;
  SOk : Boolean;

Function CompilePat(Const P : String) : Boolean;
Begin
  SPr := ReCompile(P, False, OptIc);
  SOk := SPr >= 0;
  CompilePat := SOk;
End;

{ cherche dans la ligne Y a partir de la colonne From (0-based) ; MStart,
  MEnd en 0-based }
Function MatchLine(Y, From : LongInt; Var MS_, ME : LongInt) : Boolean;
Var Ln : String;
Begin
  MatchLine := False;
  Ln := L[Y];
  If From > Length(Ln) Then Exit;
  If ReSearch(SPr, LongInt(@Ln[1]), Length(Ln), From, False) Then
  Begin
    MS_ := ReCap[0];
    ME := ReCap[1];
    MatchLine := True;
  End;
End;

Function FindNext(Dir : LongInt; Var Y, X : LongInt) : Boolean;
Var
  I, N, S, E, Best, BE, Yy : LongInt;
  Wrap : Boolean;
Begin
  FindNext := False;
  If LastPat = '' Then Exit;
  If Not CompilePat(LastPat) Then
  Begin
    Msg := ReErr;
    Exit;
  End;
  Yy := Y;
  If Dir > 0 Then
  Begin
    For N := 0 To NL Do
    Begin
      I := Yy + N;
      Wrap := False;
      If I > NL Then
      Begin
        I := I - NL;
        Wrap := True;
        If Not OptWs Then Break;
      End;
      If N = 0 Then S := X Else S := 0;
      If MatchLine(I, S, S, E) Then
      Begin
        Y := I;
        X := S + 1;
        FindNext := True;
        Exit;
      End;
    End;
  End
  Else
  Begin
    For N := 0 To NL Do
    Begin
      I := Yy - N;
      If I < 1 Then
      Begin
        I := I + NL;
        If Not OptWs Then Break;
      End;
      { derniere correspondance de la ligne avant X (pour N = 0) }
      Best := -1;
      S := 0;
      While MatchLine(I, S, S, E) Do
      Begin
        If (N = 0) And (S + 1 >= X) Then Break;
        Best := S;
        S := S + 1;
        If E > S Then S := S;
      End;
      If Best >= 0 Then
      Begin
        Y := I;
        X := Best + 1;
        FindNext := True;
        Exit;
      End;
    End;
  End;
End;

{ ------------------------------ mouvements ------------------------------ }

Function IsBlank(Y : LongInt) : Boolean;
Begin
  IsBlank := Length(L[Y]) = 0;
End;

Procedure WordFwd(Var Y, X : LongInt; Big : Boolean);
Var C : LongInt;
Begin
  C := Cls(Y, X, Big);
  If C <> 0 Then
    While (X <= Length(L[Y])) And (Cls(Y, X, Big) = C) Do Inc(X);
  While True Do
  Begin
    If X > Length(L[Y]) Then
    Begin
      If Y >= NL Then
      Begin
        X := Length(L[Y]);
        If X < 1 Then X := 1;
        Exit;
      End;
      Inc(Y);
      X := 1;
      If Length(L[Y]) = 0 Then Exit;
    End
    Else If Cls(Y, X, Big) = 0 Then Inc(X)
    Else Exit;
  End;
End;

Procedure WordBack(Var Y, X : LongInt; Big : Boolean);
Var C : LongInt;
Begin
  { reculer d'une position }
  Dec(X);
  While True Do
  Begin
    If X < 1 Then
    Begin
      If Y <= 1 Then
      Begin
        X := 1;
        Exit;
      End;
      Dec(Y);
      X := Length(L[Y]);
      If X < 1 Then
      Begin
        X := 1;
        Exit;
      End;
    End
    Else If Cls(Y, X, Big) = 0 Then Dec(X)
    Else Break;
  End;
  C := Cls(Y, X, Big);
  While (X > 1) And (Cls(Y, X - 1, Big) = C) Do Dec(X);
End;

Procedure WordEnd(Var Y, X : LongInt; Big : Boolean);
Var C : LongInt;
Begin
  Inc(X);
  While True Do
  Begin
    If X > Length(L[Y]) Then
    Begin
      If Y >= NL Then
      Begin
        X := Length(L[Y]);
        If X < 1 Then X := 1;
        Exit;
      End;
      Inc(Y);
      X := 1;
    End
    Else If Cls(Y, X, Big) = 0 Then Inc(X)
    Else Break;
  End;
  C := Cls(Y, X, Big);
  While (X < Length(L[Y])) And (Cls(Y, X + 1, Big) = C) Do Inc(X);
End;

Function MatchBracket(Var Y, X : LongInt) : Boolean;
Var
  O, C : Char;
  Dir, D, Y0, X0 : LongInt;
  Ch : Char;
Begin
  MatchBracket := False;
  If Length(L[Y]) < 1 Then Exit;
  Y0 := Y;
  X0 := X;
  { chercher la premiere parenthese a partir du curseur }
  While (X0 <= Length(L[Y0])) And
        (Pos(L[Y0][X0], '()[]{}') = 0) Do Inc(X0);
  If X0 > Length(L[Y0]) Then Exit;
  Ch := L[Y0][X0];
  Case Ch Of
    '(' : Begin O := '('; C := ')'; Dir := 1; End;
    ')' : Begin O := ')'; C := '('; Dir := -1; End;
    '[' : Begin O := '['; C := ']'; Dir := 1; End;
    ']' : Begin O := ']'; C := '['; Dir := -1; End;
    '{' : Begin O := '{'; C := '}'; Dir := 1; End;
  Else Begin O := '}'; C := '{'; Dir := -1; End;
  End;
  D := 0;
  While True Do
  Begin
    If L[Y0][X0] = O Then Inc(D)
    Else If L[Y0][X0] = C Then
    Begin
      Dec(D);
      If D = 0 Then
      Begin
        Y := Y0;
        X := X0;
        MatchBracket := True;
        Exit;
      End;
    End;
    X0 := X0 + Dir;
    While (X0 < 1) Or (X0 > Length(L[Y0])) Do
    Begin
      If Dir > 0 Then
      Begin
        Inc(Y0);
        If Y0 > NL Then Exit;
        X0 := 1;
      End
      Else
      Begin
        Dec(Y0);
        If Y0 < 1 Then Exit;
        X0 := Length(L[Y0]);
      End;
      If Length(L[Y0]) > 0 Then Break;
    End;
  End;
End;

Function FindChar(T : LongInt; Ch : Char; Cnt : LongInt; Var X : LongInt)
  : Boolean;
Var K, N, S : LongInt;
Begin
  FindChar := False;
  S := X;
  N := Cnt;
  If (T = Ord('f')) Or (T = Ord('t')) Then
  Begin
    K := S + 1;
    If (T = Ord('t')) And (LastF = 1) Then K := S + 2;
    While K <= Length(L[Cy]) Do
    Begin
      If L[Cy][K] = Ch Then
      Begin
        Dec(N);
        If N = 0 Then
        Begin
          If T = Ord('t') Then X := K - 1 Else X := K;
          FindChar := True;
          Exit;
        End;
      End;
      Inc(K);
    End;
  End
  Else
  Begin
    K := S - 1;
    If (T = Ord('T')) And (LastF = 1) Then K := S - 2;
    While K >= 1 Do
    Begin
      If L[Cy][K] = Ch Then
      Begin
        Dec(N);
        If N = 0 Then
        Begin
          If T = Ord('T') Then X := K + 1 Else X := K;
          FindChar := True;
          Exit;
        End;
      End;
      Dec(K);
    End;
  End;
End;

Function ReadLine(Const Prompt : String; Var S : String) : Boolean; Forward;

{ Mouvement : Cmd = touche ; resultat dans (Ty, Tx) ; Lw = par lignes ;
  Inc = inclusif ; Ok = mouvement valide. Op = vrai si operateur en cours. }
Procedure Motion(Cmd, Cnt : LongInt; HasCnt, Op : Boolean;
                 Var Ty, Tx : LongInt; Var Lw, Inc_, Ok : Boolean);
Var
  I, K, Y, X, C2 : LongInt;
  Ch : Char;
  S : String;
Begin
  Ty := Cy; Tx := Cx; Lw := False; Inc_ := False; Ok := True;
  Y := Cy; X := Cx;
  Case Cmd Of
    Ord('h'), 8, 127, K_LEFT :
      Begin
        If Cx <= 1 Then Ok := False Else Tx := Cx - Cnt;
        If Tx < 1 Then Tx := 1;
      End;
    Ord('l'), Ord(' '), K_RIGHT :
      Begin
        If Op Then K := Length(L[Cy]) + 1 Else K := Length(L[Cy]);
        If Cx >= K Then Ok := False Else Tx := Cx + Cnt;
        If Tx > K Then Tx := K;
      End;
    Ord('j'), 14, 10, K_DOWN, Ord('+'), 13 :
      Begin
        If Cy + Cnt > NL Then
          If Cy = NL Then Ok := False;
        Ty := Cy + Cnt;
        If Ty > NL Then Ty := NL;
        Lw := True;
        If (Cmd = Ord('+')) Or (Cmd = 13) Then Tx := 0
        Else Tx := XFromCol(Ty, WantX);
      End;
    Ord('k'), 16, K_UP, Ord('-') :
      Begin
        If Cy = 1 Then Ok := False;
        Ty := Cy - Cnt;
        If Ty < 1 Then Ty := 1;
        Lw := True;
        If Cmd = Ord('-') Then Tx := 0 Else Tx := XFromCol(Ty, WantX);
      End;
    Ord('0'), K_HOME : Tx := 1;
    Ord('^') : Tx := 0;
    Ord('$'), K_END :
      Begin
        Ty := Cy + Cnt - 1;
        If Ty > NL Then Ty := NL;
        Tx := Length(L[Ty]);
        If Tx < 1 Then Tx := 1;
        Inc_ := True;
        WantX := 100000;
      End;
    Ord('|') : Tx := XFromCol(Cy, Cnt - 1);
    Ord('G') :
      Begin
        If HasCnt Then Ty := Cnt Else Ty := NL;
        If Ty > NL Then Ty := NL;
        If Ty < 1 Then Ty := 1;
        Lw := True;
        Tx := 0;
      End;
    Ord('_') :
      Begin
        Ty := Cy + Cnt - 1;
        If Ty > NL Then Ty := NL;
        Lw := True;
        Tx := 0;
      End;
    Ord('w'), Ord('W') :
      Begin
        For I := 1 To Cnt Do WordFwd(Y, X, Cmd = Ord('W'));
        Ty := Y; Tx := X;
      End;
    Ord('b'), Ord('B') :
      Begin
        For I := 1 To Cnt Do WordBack(Y, X, Cmd = Ord('B'));
        Ty := Y; Tx := X;
      End;
    Ord('e'), Ord('E') :
      Begin
        For I := 1 To Cnt Do WordEnd(Y, X, Cmd = Ord('E'));
        Ty := Y; Tx := X;
        Inc_ := True;
      End;
    Ord('%') :
      Begin
        If MatchBracket(Y, X) Then
        Begin
          Ty := Y; Tx := X;
          Inc_ := True;
        End
        Else Ok := False;
      End;
    Ord('}') :
      Begin
        Y := Cy;
        For I := 1 To Cnt Do
        Begin
          While (Y < NL) And IsBlank(Y) Do Inc(Y);
          While (Y < NL) And Not IsBlank(Y) Do Inc(Y);
        End;
        Ty := Y;
        If Y = NL Then Tx := Length(L[Y]) Else Tx := 1;
        If Tx < 1 Then Tx := 1;
        If (Y = NL) And Not IsBlank(Y) Then Inc_ := True;
      End;
    Ord('{') :
      Begin
        Y := Cy;
        For I := 1 To Cnt Do
        Begin
          While (Y > 1) And IsBlank(Y) Do Dec(Y);
          While (Y > 1) And Not IsBlank(Y) Do Dec(Y);
        End;
        Ty := Y;
        Tx := 1;
      End;
    Ord('H') :
      Begin
        Ty := Top + Cnt - 1;
        If Ty > NL Then Ty := NL;
        Lw := True; Tx := 0;
      End;
    Ord('L') :
      Begin
        Ty := Top + Rows - 2 - (Cnt - 1);
        If Ty > NL Then Ty := NL;
        If Ty < 1 Then Ty := 1;
        Lw := True; Tx := 0;
      End;
    Ord('M') :
      Begin
        Ty := Top + (Rows - 1) Div 2;
        If Ty > NL Then Ty := Top + (NL - Top) Div 2;
        Lw := True; Tx := 0;
      End;
    Ord('f'), Ord('F'), Ord('t'), Ord('T') :
      Begin
        C2 := GetKey;
        If (C2 < 0) Or (C2 > 255) Then Ok := False
        Else
        Begin
          LastF := 0;
          LastFCh := C2;
          Ch := Chr(C2);
          If FindChar(Cmd, Ch, Cnt, Tx) Then
          Begin
            Inc_ := (Cmd = Ord('f')) Or (Cmd = Ord('t'));
            If Not Inc_ Then Inc_ := False;
            LastF := Cmd;
          End
          Else Ok := False;
          LastFCh := C2;
        End;
      End;
    Ord(';'), Ord(',') :
      Begin
        If LastF = 0 Then Ok := False
        Else
        Begin
          C2 := LastF;
          If Cmd = Ord(',') Then
            Case C2 Of
              Ord('f') : C2 := Ord('F');
              Ord('F') : C2 := Ord('f');
              Ord('t') : C2 := Ord('T');
              Ord('T') : C2 := Ord('t');
            End;
          { t/T repetes : sauter le caractere adjacent }
          If FindChar(C2, Chr(LastFCh), Cnt, Tx) Then
            Inc_ := (C2 = Ord('f')) Or (C2 = Ord('t'))
          Else Ok := False;
        End;
      End;
    Ord('n'), Ord('N') :
      Begin
        If LastPat = '' Then Ok := False
        Else
        Begin
          K := LastDir;
          If Cmd = Ord('N') Then K := -K;
          Y := Cy;
          X := Cx;
          For I := 1 To Cnt Do
          Begin
            If K > 0 Then X := X + 1;
            If Not FindNext(K, Y, X) Then
            Begin
              Ok := False;
              Msg := MS(2);
              Break;
            End;
          End;
          If Ok Then
          Begin
            Ty := Y;
            Tx := X;
          End;
        End;
      End;
    Ord('/'), Ord('?') :
      Begin
        If Cmd = Ord('/') Then K := 1 Else K := -1;
        If ReadLine(Chr(Cmd), S) Then
        Begin
          If S <> '' Then LastPat := S;
          LastDir := K;
          Y := Cy;
          X := Cx;
          If K > 0 Then X := X + 1;
          If FindNext(K, Y, X) Then
          Begin
            Ty := Y;
            Tx := X;
          End
          Else
          Begin
            Ok := False;
            Msg := MS(2);
          End;
        End
        Else Ok := False;
      End;
    Ord('`'), Ord(#39) :
      Begin
        C2 := GetKey;
        If (C2 >= Ord('a')) And (C2 <= Ord('z')) And
           (Marks[C2 - 97] > 0) Then
        Begin
          Ty := Marks[C2 - 97];
          If Ty > NL Then Ty := NL;
          If Cmd = Ord(#39) Then
          Begin
            Tx := 0;
            Lw := True;
          End
          Else Tx := MarkX[C2 - 97];
        End
        Else Ok := False;
      End;
  Else Ok := False;
  End;
  If Ok Then
  Begin
    If Tx = 0 Then
    Begin
      Tx := 1;
      While (Tx <= Length(L[Ty])) And ((L[Ty][Tx] = ' ') Or (L[Ty][Tx] = #9))
        Do Inc(Tx);
      If Tx > Length(L[Ty]) Then Tx := Length(L[Ty]);
      If Tx < 1 Then Tx := 1;
    End;
  End;
End;

{ ------------------------------ insertion ------------------------------ }

Function Indent(Const S : String) : String;
Var K : LongInt;
Begin
  K := 1;
  While (K <= Length(S)) And ((S[K] = ' ') Or (S[K] = #9)) Do Inc(K);
  Indent := Copy(S, 1, K - 1);
End;

Procedure PutChar(C : Char);
Begin
  If Length(L[Cy]) >= 254 Then Exit;
  Insert(C, L[Cy], Cx);
  Inc(Cx);
  Modified := True;
End;

Procedure SplitLine;
Var T, Ind : String;
Begin
  T := Copy(L[Cy], Cx, 255);
  L[Cy] := Copy(L[Cy], 1, Cx - 1);
  Ind := '';
  If OptAi Then
  Begin
    Ind := Indent(L[Cy]);
    If Length(L[Cy]) = Length(Ind) Then L[Cy] := '';
    While (Length(T) > 0) And ((T[1] = ' ') Or (T[1] = #9)) Do
      Delete(T, 1, 1);
  End;
  InsLine(Cy + 1, Ind + T);
  Inc(Cy);
  Cx := Length(Ind) + 1;
End;

{ boucle d'insertion ; Rep = mode remplacement ; Cnt = repetitions }
Procedure InsertMode(Rep : Boolean; Cnt : LongInt);
Var
  C, K, I, N : LongInt;
  Typed : String;
  Mode : String;
  Saved : String;
Begin
  If Rep Then Mode := '-- REPLACE --' Else Mode := '-- INSERT --';
  Typed := '';
  Msg := '';
  Saved := '';
  While True Do
  Begin
    Fix(True);
    Redraw(Mode);
    Msg := '';
    C := GetKey;
    If (C = K_EOF) Or (C = 27) Then Break;
    Case C Of
      13, 10 :
        Begin
          SplitLine;
          Typed := Typed + #10;
        End;
      8, 127 :
        Begin
          If Cx > 1 Then
          Begin
            Dec(Cx);
            Delete(L[Cy], Cx, 1);
            If Length(Typed) > 0 Then Delete(Typed, Length(Typed), 1);
          End
          Else If Cy > 1 Then
          Begin
            K := Length(L[Cy - 1]);
            L[Cy - 1] := L[Cy - 1] + L[Cy];
            DelLine(Cy);
            Dec(Cy);
            Cx := K + 1;
            If Length(Typed) > 0 Then Delete(Typed, Length(Typed), 1);
          End;
          Modified := True;
        End;
      23 :
        Begin
          { Ctrl-W : mot precedent }
          While (Cx > 1) And ((L[Cy][Cx - 1] = ' ') Or (L[Cy][Cx - 1] = #9))
            Do Begin Dec(Cx); Delete(L[Cy], Cx, 1); End;
          K := Cls(Cy, Cx - 1, False);
          While (Cx > 1) And (Cls(Cy, Cx - 1, False) = K) And (K <> 0) Do
          Begin
            Dec(Cx);
            Delete(L[Cy], Cx, 1);
          End;
          Typed := '';
        End;
      21 :
        Begin
          Delete(L[Cy], 1, Cx - 1);
          Cx := 1;
          Typed := '';
        End;
      K_LEFT : If Cx > 1 Then Dec(Cx);
      K_RIGHT : If Cx <= Length(L[Cy]) Then Inc(Cx);
      K_UP : If Cy > 1 Then Begin Dec(Cy); Fix(True); End;
      K_DOWN : If Cy < NL Then Begin Inc(Cy); Fix(True); End;
      K_DEL : If Cx <= Length(L[Cy]) Then Begin
                Delete(L[Cy], Cx, 1); Modified := True; End;
      K_HOME : Cx := 1;
      K_END : Cx := Length(L[Cy]) + 1;
      22 :
        Begin
          C := GetKey;
          If (C >= 0) And (C < 256) Then
          Begin
            PutChar(Chr(C));
            Typed := Typed + Chr(C);
          End;
        End;
    Else
      If (C >= 32) Or (C = 9) Then
      Begin
        If Rep And (Cx <= Length(L[Cy])) Then
        Begin
          L[Cy][Cx] := Chr(C);
          Inc(Cx);
          Modified := True;
        End
        Else PutChar(Chr(C));
        If C < 256 Then Typed := Typed + Chr(C);
      End;
    End;
  End;
  { repetitions (3ihello) }
  For I := 2 To Cnt Do
    For K := 1 To Length(Typed) Do
      If Typed[K] = #10 Then SplitLine Else PutChar(Typed[K]);
  If Cx > 1 Then Dec(Cx);
  Fix(False);
  Msg := '';
End;

{ ------------------------------ ex ------------------------------ }

Function ReadFileInto(Const Name : String; At : LongInt;
                      Var Chars : LongInt; Var Long : Boolean) : Boolean;
Var
  Fd, N, K, Cur : LongInt;
  Buf : Array[0..4095] Of Byte;
  S : String;
Begin
  ReadFileInto := False;
  Chars := 0;
  Long := False;
  Fd := SysOpen(Name, O_RDONLY, 0);
  If Fd < 0 Then Exit;
  Cur := At;
  S := '';
  Repeat
    N := SysRead(Fd, Buf[0], 4096);
    If N > 0 Then
    Begin
      Chars := Chars + N;
      For K := 0 To N - 1 Do
        If Buf[K] = 10 Then
        Begin
          If Cur < MaxL Then
          Begin
            Inc(Cur);
            InsLine(Cur, S);
          End;
          S := '';
        End
        Else If Length(S) < 255 Then S := S + Chr(Buf[K])
        Else
        Begin
          Long := True;
          If Cur < MaxL Then
          Begin
            Inc(Cur);
            InsLine(Cur, S);
          End;
          S := Chr(Buf[K]);
        End;
    End;
  Until N <= 0;
  If S <> '' Then
  Begin
    Inc(Cur);
    InsLine(Cur, S);
  End;
  SysClose(Fd);
  ReadFileInto := True;
End;

Function WriteLines(Const Name : String; Y1, Y2 : LongInt;
                    Append : Boolean) : Boolean;
Var Fd, I, Bytes, Fl : LongInt; S : String;
Begin
  WriteLines := False;
  Fl := O_WRONLY Or O_CREAT;
  If Append Then Fl := Fl Or O_APPEND Else Fl := Fl Or O_TRUNC;
  Fd := SysOpen(Name, Fl, 420);
  If Fd < 0 Then
  Begin
    Msg := Name + ': ' + SysErrorText(SysErrno);
    Exit;
  End;
  Bytes := 0;
  If EmptyBuf And (NL = 1) And (L[1] = '') Then Y2 := Y1 - 1;
  For I := Y1 To Y2 Do
  Begin
    S := L[I] + #10;
    If SysPut(Fd, S) < 0 Then
    Begin
      Msg := Name + ': ' + SysErrorText(SysErrno);
      SysClose(Fd);
      Exit;
    End;
    Bytes := Bytes + Length(S);
  End;
  SysClose(Fd);
  Msg := '"' + Name + '" ' + NumS(Y2 - Y1 + 1) + 'L, ' + NumS(Bytes) + 'C ' +
         MS(5);
  WriteLines := True;
End;

Procedure LoadFile(Const Name : String);
Var Ch : LongInt; Long, Ok : Boolean;
Begin
  NL := 1;
  L[1] := '';
  EmptyBuf := True;
  Modified := False;
  Cy := 1; Cx := 1; Top := 1; Left := 0;
  FileName := Name;
  If Name = '' Then Exit;
  Ok := ReadFileInto(Name, 0, Ch, Long);
  EmptyBuf := Ch = 0;
  If Not Ok Then
  Begin
    Msg := '"' + Name + '" [' + MS(4) + ']';
    Exit;
  End;
  If NL > 1 Then
    If L[NL] = '' Then
    Begin
      Dec(NL);
    End;
  Modified := False;
  Msg := '"' + Name + '" ' + NumS(NL) + 'L, ' + NumS(Ch) + 'C';
  If Long Then Msg := Msg + ' (' + MS(6) + ')';
End;

Procedure Shell(Const Cmd : String);
Var Pid, St : LongInt;
Begin
  OPut(#27 + '[?1049l');
  OFlush;
  If HaveTerm Then SysTcSetAttr(0, 1, SavedTerm);
  Pid := SysFork;
  If Pid = 0 Then
  Begin
    SysArgReset;
    SysArgAdd('sh');
    SysArgAdd('-c');
    SysArgAdd(Cmd);
    SysEnvInherit;
    SysArgExec('/bin/sh');
    SysExit(127);
  End;
  SysWaitPid(Pid, St, 0);
  SysPut(1, #10 + '[Enter]');
  If HaveTerm Then SysTcSetAttr(0, 1, Term);
  RawByte;
  OPut(#27 + '[?1049h');
  Dirty := True;
End;

Function AtEnd(Const S : String; P : LongInt) : Boolean;
Begin
  AtEnd := P > Length(S);
End;

Procedure SkipSp(Const S : String; Var P : LongInt);
Begin
  While (P <= Length(S)) And ((S[P] = ' ') Or (S[P] = #9)) Do Inc(P);
End;

{ adresse ex a partir de P ; Ok faux si absente }
Function ParseAddr(Const S : String; Var P : LongInt; Var A : LongInt)
  : Boolean;
Var V, C : LongInt; Pat : String; Found : Boolean; Y, X : LongInt; D : Char;
Begin
  ParseAddr := False;
  SkipSp(S, P);
  If AtEnd(S, P) Then Exit;
  Found := True;
  If (S[P] >= '0') And (S[P] <= '9') Then
  Begin
    A := 0;
    While (P <= Length(S)) And (S[P] >= '0') And (S[P] <= '9') Do
    Begin
      A := A * 10 + Ord(S[P]) - 48;
      Inc(P);
    End;
  End
  Else If S[P] = '.' Then Begin A := Cy; Inc(P); End
  Else If S[P] = '$' Then Begin A := NL; Inc(P); End
  Else If (S[P] = #39) And (P < Length(S)) Then
  Begin
    C := Ord(S[P + 1]) - 97;
    If (C >= 0) And (C <= 25) And (Marks[C] > 0) Then A := Marks[C]
    Else A := Cy;
    Inc(P, 2);
  End
  Else If (S[P] = '/') Or (S[P] = '?') Then
  Begin
    D := S[P];
    Inc(P);
    Pat := '';
    While (P <= Length(S)) And (S[P] <> D) Do
    Begin
      If (S[P] = '\') And (P < Length(S)) And (S[P + 1] = D) Then Inc(P);
      Pat := Pat + S[P];
      Inc(P);
    End;
    If P <= Length(S) Then Inc(P);
    If Pat <> '' Then LastPat := Pat;
    Y := Cy;
    X := 0;
    If D = '?' Then X := 32000;
    If D = '/' Then X := Length(L[Y]);
    If FindNext(Ord(D = '/') * 2 - 1, Y, X) Then A := Y
    Else
    Begin
      Msg := MS(2);
      A := Cy;
    End;
  End
  Else Found := False;
  If Not Found Then
  Begin
    { +n / -n seuls : relatif au courant }
    If (S[P] = '+') Or (S[P] = '-') Then A := Cy Else Exit;
  End;
  While (P <= Length(S)) And ((S[P] = '+') Or (S[P] = '-')) Do
  Begin
    D := S[P];
    Inc(P);
    V := 0;
    If (P <= Length(S)) And (S[P] >= '0') And (S[P] <= '9') Then
      While (P <= Length(S)) And (S[P] >= '0') And (S[P] <= '9') Do
      Begin
        V := V * 10 + Ord(S[P]) - 48;
        Inc(P);
      End
    Else V := 1;
    If D = '+' Then A := A + V Else A := A - V;
  End;
  ParseAddr := True;
End;

{ remplace dans la ligne Y ; retourne le nombre de substitutions }
Function SubstLine(Y : LongInt; Const Rep : String; Glob : Boolean) : LongInt;
Var
  Src, Res, Piece : String;
  Pos0, MS_, ME, N, K, G : LongInt;
  C : Char;
Begin
  SubstLine := 0;
  Src := L[Y];
  Res := '';
  Pos0 := 0;
  N := 0;
  While Pos0 <= Length(Src) Do
  Begin
    If Not ReSearch(SPr, LongInt(@Src[1]), Length(Src), Pos0, False) Then
      Break;
    MS_ := ReCap[0];
    ME := ReCap[1];
    Inc(N);
    Res := Res + Copy(Src, Pos0 + 1, MS_ - Pos0);
    K := 1;
    While K <= Length(Rep) Do
    Begin
      C := Rep[K];
      If (C = '&') Then Res := Res + Copy(Src, MS_ + 1, ME - MS_)
      Else If (C = '\') And (K < Length(Rep)) Then
      Begin
        Inc(K);
        If (Rep[K] >= '1') And (Rep[K] <= '9') Then
        Begin
          G := Ord(Rep[K]) - 48;
          If ReCap[2 * G] >= 0 Then
            Res := Res + Copy(Src, ReCap[2 * G] + 1,
                              ReCap[2 * G + 1] - ReCap[2 * G]);
        End
        Else If Rep[K] = 'n' Then Res := Res + #1
        Else If Rep[K] = 't' Then Res := Res + #9
        Else Res := Res + Rep[K];
      End
      Else Res := Res + C;
      Inc(K);
    End;
    If ME = MS_ Then
    Begin
      { correspondance vide : avancer d'un caractere }
      If MS_ < Length(Src) Then Res := Res + Src[MS_ + 1];
      Pos0 := MS_ + 1;
    End
    Else Pos0 := ME;
    If Not Glob Then Break;
  End;
  If N > 0 Then
  Begin
    If Pos0 <= Length(Src) Then Res := Res + Copy(Src, Pos0 + 1, 255);
    L[Y] := Res;
    Modified := True;
    { \n (octet 0 dans le remplacement) : couper la ligne }
    While Pos(#1, L[Y]) > 0 Do
    Begin
      K := Pos(#1, L[Y]);
      Piece := Copy(L[Y], K + 1, 255);
      L[Y] := Copy(L[Y], 1, K - 1);
      InsLine(Y + 1, Piece);
    End;
  End;
  SubstLine := N;
End;

Procedure ExCmd(Const Line : String); Forward;

Procedure DoSubst(Const S : String; Var P : LongInt; A1, A2 : LongInt);
Var
  D : Char;
  Pat, Rep, Fl : String;
  Y, Tot, Lines, N : LongInt;
  Glob : Boolean;
Begin
  D := S[P];
  Inc(P);
  Pat := '';
  While (P <= Length(S)) And (S[P] <> D) Do
  Begin
    If (S[P] = '\') And (P < Length(S)) Then
    Begin
      If S[P + 1] = D Then Inc(P)
      Else Begin Pat := Pat + S[P]; Inc(P); End;
    End;
    Pat := Pat + S[P];
    Inc(P);
  End;
  If P <= Length(S) Then Inc(P);
  Rep := '';
  While (P <= Length(S)) And (S[P] <> D) Do
  Begin
    If (S[P] = '\') And (P < Length(S)) Then
    Begin
      If S[P + 1] = D Then Inc(P)
      Else Begin Rep := Rep + S[P]; Inc(P); End;
    End;
    Rep := Rep + S[P];
    Inc(P);
  End;
  If P <= Length(S) Then Inc(P);
  Fl := Copy(S, P, 255);
  Glob := Pos('g', Fl) > 0;
  If Pat = '' Then Pat := LastPat;
  If Pat = '' Then
  Begin
    Msg := MS(2);
    Exit;
  End;
  LastPat := Pat;
  LastRep := Rep;
  If Pos('i', Fl) > 0 Then OptIc := True;
  If Not CompilePat(Pat) Then
  Begin
    Msg := ReErr;
    Exit;
  End;
  SaveUndo;
  Tot := 0;
  Lines := 0;
  Y := A1;
  While Y <= A2 Do
  Begin
    N := NL;
    If Y <= NL Then
    Begin
        N := SubstLine(Y, Rep, Glob);
      If N > 0 Then
      Begin
        Tot := Tot + N;
        Inc(Lines);
      End;
    End;
    Inc(Y);
  End;
  If Tot = 0 Then Msg := MS(2)
  Else
  Begin
    Cy := A2;
    If Cy > NL Then Cy := NL;
    Cx := 1;
    If Tot > 2 Then Msg := NumS(Tot) + ' / ' + NumS(Lines) + 'L';
  End;
End;

Function ReadLine(Const Prompt : String; Var S : String) : Boolean;
Var C : LongInt;
Begin
  S := '';
  ReadLine := False;
  While True Do
  Begin
    Goto_(Rows, 1);
    OPut(#27 + '[K' + Prompt + S);
    OFlush;
    C := GetKey;
    If (C = 13) Or (C = 10) Then
    Begin
      ReadLine := True;
      Exit;
    End;
    If (C = 27) Or (C = 3) Or (C = K_EOF) Then Exit;
    If (C = 8) Or (C = 127) Then
    Begin
      If S = '' Then Exit;
      Delete(S, Length(S), 1);
    End
    Else If C = 21 Then S := ''
    Else If C = 22 Then
    Begin
      C := GetKey;
      If (C >= 0) And (C < 256) And (Length(S) < 250) Then S := S + Chr(C);
    End
    Else If ((C >= 32) Or (C = 9)) And (C < 256) And (Length(S) < 250) Then
      S := S + Chr(C);
  End;
End;

Procedure Goto1(Y : LongInt);
Begin
  Cy := Y;
  If Cy < 1 Then Cy := 1;
  If Cy > NL Then Cy := NL;
  Cx := 1;
  While (Cx <= Length(L[Cy])) And ((L[Cy][Cx] = ' ') Or (L[Cy][Cx] = #9))
    Do Inc(Cx);
  Fix(False);
End;

Function NameArg(Const S : String; P : LongInt) : String;
Var T : String;
Begin
  T := Copy(S, P, 255);
  While (Length(T) > 0) And ((T[1] = ' ') Or (T[1] = #9)) Do Delete(T, 1, 1);
  While (Length(T) > 0) And ((T[Length(T)] = ' ')) Do Delete(T, Length(T), 1);
  If T = '%' Then T := FileName;
  NameArg := T;
End;

Procedure ExCmd(Const Line : String);
Var
  P, A1, A2, NAddr, K, Dest, I, Ch, Y, X, N : LongInt;
  Cmd, Arg, S : String;
  Bang, HasRange, Long : Boolean;
  Ok : Boolean;
  Pat : String;
  Marked : Array[1..MaxL] Of Boolean;
Begin
  S := Line;
  P := 1;
  SkipSp(S, P);
  While (P <= Length(S)) And (S[P] = ':') Do Inc(P);
  A1 := Cy;
  A2 := Cy;
  HasRange := False;
  If (P <= Length(S)) And (S[P] = '%') Then
  Begin
    A1 := 1;
    A2 := NL;
    HasRange := True;
    Inc(P);
  End
  Else If ParseAddr(S, P, A1) Then
  Begin
    HasRange := True;
    A2 := A1;
    SkipSp(S, P);
    If (P <= Length(S)) And ((S[P] = ',') Or (S[P] = ';')) Then
    Begin
      Inc(P);
      If Not ParseAddr(S, P, A2) Then A2 := Cy;
    End;
  End;
  SkipSp(S, P);
  If A1 < 1 Then A1 := 1;
  If A2 > NL Then A2 := NL;
  If A1 > NL Then A1 := NL;
  If A2 < A1 Then Begin K := A1; A1 := A2; A2 := K; End;
  If AtEnd(S, P) Then
  Begin
    If HasRange Then Goto1(A2);
    Exit;
  End;
  { nom de la commande }
  Cmd := '';
  If Pos(S[P], 's&<>!=@') > 0 Then
  Begin
    Cmd := S[P];
    Inc(P);
    If (Cmd = 's') Then
    Begin
      { s suivi d'un delimiteur : substitution ; sinon nom long (set...) }
      If (P <= Length(S)) And (S[P] >= 'a') And (S[P] <= 'z') Then
      Begin
        Dec(P);
        Cmd := '';
      End;
    End;
  End;
  If Cmd = '' Then
    While (P <= Length(S)) And (S[P] >= 'a') And (S[P] <= 'z') Do
    Begin
      Cmd := Cmd + S[P];
      Inc(P);
    End;
  Bang := (P <= Length(S)) And (S[P] = '!') And (Cmd <> '!');
  If Bang Then Inc(P);
  Arg := NameArg(S, P);
  If (Cmd = 'w') Or (Cmd = 'write') Or (Cmd = 'wq') Or (Cmd = 'x') Or
     (Cmd = 'xit') Or (Cmd = 'wa') Then
  Begin
    If (Length(Arg) > 0) And (Arg[1] = '>') And (Length(Arg) > 1) Then
    Begin
      Delete(Arg, 1, 1);
      Arg := NameArg(Arg, 1);
      If Not HasRange Then Begin A1 := 1; A2 := NL; End;
      WriteLines(Arg, A1, A2, True);
      Exit;
    End;
    If Arg = '' Then Arg := FileName;
    If Arg = '' Then
    Begin
      Msg := MS(7);
      Exit;
    End;
    If Not HasRange Then Begin A1 := 1; A2 := NL; End;
    If WriteLines(Arg, A1, A2, False) Then
    Begin
      If (Arg = FileName) And (A1 = 1) And (A2 = NL) Then Modified := False;
      If FileName = '' Then FileName := Arg;
      If (Cmd = 'wq') Or (Cmd = 'x') Or (Cmd = 'xit') Then Quit := True;
    End;
    Exit;
  End;
  If (Cmd = 'q') Or (Cmd = 'quit') Or (Cmd = 'qa') Or (Cmd = 'cq') Then
  Begin
    If Modified And Not Bang Then Msg := MS(1) Else Quit := True;
    Exit;
  End;
  If (Cmd = 'e') Or (Cmd = 'edit') Or (Cmd = 'vi') Then
  Begin
    If Modified And Not Bang Then
    Begin
      Msg := MS(1);
      Exit;
    End;
    If Arg = '' Then Arg := FileName;
    If Arg <> FileName Then AltName := FileName;
    LoadFile(Arg);
    Exit;
  End;
  If (Cmd = 'r') Or (Cmd = 'read') Then
  Begin
    If (Length(Arg) > 0) And (Arg[1] = '!') Then
    Begin
      Msg := '';
      Shell(Copy(Arg, 2, 255) + ' > /tmp/.vi.' + NumS(SysGetPid));
      SaveUndo;
      ReadFileInto('/tmp/.vi.' + NumS(SysGetPid), A2, Ch, Long);
      SysUnlink('/tmp/.vi.' + NumS(SysGetPid));
      Exit;
    End;
    If Arg = '' Then Arg := FileName;
    SaveUndo;
    If Not HasRange Then A2 := Cy;
    If ReadFileInto(Arg, A2, Ch, Long) Then
    Begin
      Goto1(A2 + 1);
      Msg := '"' + Arg + '" ' + NumS(Ch) + 'C';
    End
    Else Msg := Arg + ': ' + SysErrorText(SysErrno);
    Exit;
  End;
  If (Cmd = 'd') Or (Cmd = 'delete') Then
  Begin
    SaveUndo;
    YankLines(A1, A2);
    For I := A2 DownTo A1 Do DelLine(I);
    Goto1(A1);
    Exit;
  End;
  If (Cmd = 'y') Or (Cmd = 'yank') Then
  Begin
    YankLines(A1, A2);
    Exit;
  End;
  If (Cmd = 'pu') Or (Cmd = 'put') Then
  Begin
    SaveUndo;
    RegLine := True;
    Cy := A2;
    Put(True);
    Exit;
  End;
  If (Cmd = 's') Or (Cmd = 'substitute') Or (Cmd = '&') Then
  Begin
    If Cmd = '&' Then
    Begin
      S := '/' + LastPat + '/' + LastRep + '/' + Arg;
      P := 1;
    End
    Else If (Cmd = 'substitute') Then SkipSp(S, P);
    If P > Length(S) Then
    Begin
      Msg := MS(3);
      Exit;
    End;
    DoSubst(S, P, A1, A2);
    Exit;
  End;
  If (Cmd = 'g') Or (Cmd = 'global') Or (Cmd = 'v') Or (Cmd = 'vglobal') Then
  Begin
    S := Copy(S, P, 255);
    If Bang Then Cmd := 'v';
    If (Length(S) < 3) Then
    Begin
      Msg := MS(3);
      Exit;
    End;
    N := 2;
    Pat := '';
    While (N <= Length(S)) And (S[N] <> S[1]) Do
    Begin
      If (S[N] = '\') And (N < Length(S)) And (S[N + 1] = S[1]) Then Inc(N);
      Pat := Pat + S[N];
      Inc(N);
    End;
    Arg := Copy(S, N + 1, 255);
    If Arg = '' Then Arg := 'p';
    If Pat = '' Then Pat := LastPat;
    LastPat := Pat;
    If Not CompilePat(Pat) Then
    Begin
      Msg := ReErr;
      Exit;
    End;
    If Not HasRange Then Begin A1 := 1; A2 := NL; End;
    SaveUndo;
    For I := A1 To A2 Do
    Begin
      Ok := MatchLine(I, 0, K, X);
      If (Cmd = 'v') Or (Cmd = 'vglobal') Then Ok := Not Ok;
      Marked[I] := Ok;
    End;
    { de bas en haut : les numeros des lignes restantes ne bougent pas }
    For I := A2 DownTo A1 Do
      If Marked[I] And (I <= NL) Then
      Begin
        Cy := I;
        Cx := 1;
        ExCmd(Arg);
        If Not CompilePat(LastPat) Then ;
      End;
    Exit;
  End;
  If (Cmd = 'm') Or (Cmd = 'move') Or (Cmd = 't') Or (Cmd = 'co') Or
     (Cmd = 'copy') Then
  Begin
    N := 1;
    If Not ParseAddr(Arg, N, Dest) Then
    Begin
      If Arg = '0' Then Dest := 0 Else Begin Msg := MS(3); Exit; End;
    End;
    SaveUndo;
    YankLines(A1, A2);
    If (Cmd = 'm') Or (Cmd = 'move') Then
    Begin
      If (Dest >= A1) And (Dest < A2) Then Exit;
      For I := A2 DownTo A1 Do DelLine(I);
      If Dest > A2 Then Dest := Dest - (A2 - A1 + 1);
    End;
    For I := 1 To RegN Do InsLine(Dest + I, RegL[I]);
    Goto1(Dest + RegN);
    Exit;
  End;
  If (Cmd = 'j') Or (Cmd = 'join') Then
  Begin
    SaveUndo;
    If A2 = A1 Then A2 := A1 + 1;
    If A2 > NL Then A2 := NL;
    For I := A1 + 1 To A2 Do
    Begin
      S := L[A1];
      L[A1] := S + ' ' + L[I];
    End;
    For I := A2 DownTo A1 + 1 Do DelLine(I);
    Goto1(A1);
    Exit;
  End;
  If (Cmd = '>') Or (Cmd = '<') Then
  Begin
    SaveUndo;
    For I := A1 To A2 Do
      If Cmd = '>' Then
      Begin
        If L[I] <> '' Then L[I] := #9 + L[I];
      End
      Else If (Length(L[I]) > 0) And (L[I][1] = #9) Then Delete(L[I], 1, 1)
      Else
      Begin
        K := 0;
        While (K < 8) And (K < Length(L[I])) And (L[I][K + 1] = ' ') Do Inc(K);
        Delete(L[I], 1, K);
      End;
    Modified := True;
    Goto1(A2);
    Exit;
  End;
  If (Cmd = 'k') Or (Cmd = 'ma') Or (Cmd = 'mark') Then
  Begin
    If (Length(Arg) > 0) And (Arg[1] >= 'a') And (Arg[1] <= 'z') Then
    Begin
      Marks[Ord(Arg[1]) - 97] := A2;
      MarkX[Ord(Arg[1]) - 97] := 1;
    End;
    Exit;
  End;
  If (Cmd = 'u') Or (Cmd = 'undo') Then
  Begin
    DoUndo;
    Exit;
  End;
  If (Cmd = 'p') Or (Cmd = 'print') Or (Cmd = 'nu') Or (Cmd = 'number') Or
     (Cmd = '=') Then
  Begin
    If Cmd = '=' Then Msg := NumS(A2)
    Else Msg := L[A2];
    If Cmd <> '=' Then Goto1(A2);
    Exit;
  End;
  If (Cmd = 'noh') Or (Cmd = 'nohlsearch') Then Exit;
  If (Cmd = 'f') Or (Cmd = 'file') Then
  Begin
    If Arg <> '' Then FileName := Arg;
    Msg := '"' + FileName + '" ' + NumS(NL) + 'L';
    Exit;
  End;
  If (Cmd = 'se') Or (Cmd = 'set') Then
  Begin
    S := Arg;
    While S <> '' Do
    Begin
      K := Pos(' ', S);
      If K = 0 Then K := Length(S) + 1;
      Pat := Copy(S, 1, K - 1);
      S := NameArg(S, K + 1);
      If (Pat = 'nu') Or (Pat = 'number') Then OptNu := True
      Else If (Pat = 'nonu') Or (Pat = 'nonumber') Then OptNu := False
      Else If (Pat = 'ai') Or (Pat = 'autoindent') Then OptAi := True
      Else If (Pat = 'noai') Or (Pat = 'noautoindent') Then OptAi := False
      Else If (Pat = 'ic') Or (Pat = 'ignorecase') Then OptIc := True
      Else If (Pat = 'noic') Or (Pat = 'noignorecase') Then OptIc := False
      Else If (Pat = 'ws') Or (Pat = 'wrapscan') Then OptWs := True
      Else If (Pat = 'nows') Or (Pat = 'nowrapscan') Then OptWs := False;
    End;
    Dirty := True;
    Exit;
  End;
  If (Cmd = '!') Then
  Begin
    If Arg <> '' Then Shell(Arg);
    Exit;
  End;
  If (Cmd = 'n') Or (Cmd = 'next') Then
  Begin
    Msg := MS(3);
    Exit;
  End;
  Msg := MS(3) + ': ' + Cmd;
End;

{ ------------------------------ mode normal ------------------------------ }

Procedure FirstNonBlank;
Begin
  Cx := 1;
  While (Cx <= Length(L[Cy])) And ((L[Cy][Cx] = ' ') Or (L[Cy][Cx] = #9))
    Do Inc(Cx);
  If Cx > Length(L[Cy]) Then Cx := Length(L[Cy]);
  If Cx < 1 Then Cx := 1;
End;

{ applique l'operateur Op a la zone (Y1,X1)-(Y2,X2) ; Lw par lignes }
Procedure ApplyOp(Op : Char; Y1, X1, Y2, X2 : LongInt; Lw : Boolean);
Var I, K, Cnt, SaveY : LongInt; Ind : String;
Begin
  Cnt := Y2 - Y1 + 1;
  If Op <> 'y' Then SaveUndo;
  If Lw Then
  Begin
    Case Op Of
      'y' :
        Begin
          YankLines(Y1, Y2);
          Cy := Y1;
          If Cnt > 2 Then Msg := NumS(Cnt) + ' lines yanked';
        End;
      'd' :
        Begin
          YankLines(Y1, Y2);
          For I := Y2 DownTo Y1 Do DelLine(I);
          Goto1(Y1);
          If Cnt > 2 Then Msg := NumS(Cnt) + ' fewer lines';
        End;
      'c' :
        Begin
          YankLines(Y1, Y2);
          Ind := '';
          If OptAi Then Ind := Indent(L[Y1]);
          For I := Y2 DownTo Y1 + 1 Do DelLine(I);
          L[Y1] := Ind;
          Cy := Y1;
          Cx := Length(Ind) + 1;
          InsertMode(False, 1);
        End;
      '>', '<' :
        Begin
          For I := Y1 To Y2 Do
            If Op = '>' Then
            Begin
              If L[I] <> '' Then L[I] := #9 + L[I];
            End
            Else If (Length(L[I]) > 0) And (L[I][1] = #9) Then
              Delete(L[I], 1, 1)
            Else
            Begin
              K := 0;
              While (K < 8) And (K < Length(L[I])) And (L[I][K + 1] = ' ')
                Do Inc(K);
              Delete(L[I], 1, K);
            End;
          Modified := True;
          Goto1(Y1);
        End;
    End;
    Exit;
  End;
  { par caracteres : (Y1,X1)-(Y2,X2) inclus }
  If (Y1 = Y2) And (X2 < X1) Then
  Begin
    If Op = 'c' Then
    Begin
      Cy := Y1; Cx := X1;
      InsertMode(False, 1);
    End;
    Exit;
  End;
  Case Op Of
    'y' :
      Begin
        YankChars(Y1, X1, Y2, X2);
        Cy := Y1;
        Cx := X1;
      End;
    'd' :
      Begin
        YankChars(Y1, X1, Y2, X2);
        DelChars(Y1, X1, Y2, X2);
        Cy := Y1;
        Cx := X1;
        Fix(False);
      End;
    'c' :
      Begin
        YankChars(Y1, X1, Y2, X2);
        DelChars(Y1, X1, Y2, X2);
        Cy := Y1;
        Cx := X1;
        InsertMode(False, 1);
      End;
    '>', '<' : ApplyOp(Op, Y1, X1, Y2, X2, True);
  End;
End;

Procedure DoOperator(Op : Char; Cnt : LongInt; HasCnt : Boolean);
Var
  C2, C3, N2, Ty, Tx, Y1, X1, Y2, X2 : LongInt;
  Lw, Inc_, Ok, Has2 : Boolean;
  Y, X, K : LongInt;
Begin
  C2 := GetKey;
  N2 := 0;
  Has2 := False;
  While ((C2 >= Ord('1')) And (C2 <= Ord('9'))) Or
        (Has2 And (C2 = Ord('0'))) Do
  Begin
    N2 := N2 * 10 + C2 - 48;
    Has2 := True;
    C2 := GetKey;
  End;
  If Has2 Then
  Begin
    If HasCnt Then Cnt := Cnt * N2 Else Cnt := N2;
    HasCnt := True;
  End;
  If (C2 = Ord(Op)) Or ((Op = 'c') And (C2 = Ord('c'))) Then
  Begin
    Y1 := Cy;
    Y2 := Cy + Cnt - 1;
    If Y2 > NL Then Y2 := NL;
    ApplyOp(Op, Y1, 1, Y2, 1, True);
    Exit;
  End;
  If C2 = Ord('g') Then
  Begin
    C3 := GetKey;
    If C3 = Ord('g') Then
    Begin
      Y1 := Cy; Y2 := 1;
      If HasCnt Then Y2 := Cnt;
      If Y2 > NL Then Y2 := NL;
      If Y2 < Y1 Then Begin K := Y1; Y1 := Y2; Y2 := K; End;
      ApplyOp(Op, Y1, 1, Y2, 1, True);
    End;
    Exit;
  End;
  { objets de texte : iw aw }
  If (C2 = Ord('i')) Or (C2 = Ord('a')) Then
  Begin
    C3 := GetKey;
    If (C3 = Ord('w')) Or (C3 = Ord('W')) Then
    Begin
      Y := Cy;
      X := Cx;
      If Length(L[Y]) = 0 Then Exit;
      K := Cls(Y, X, C3 = Ord('W'));
      While (X > 1) And (Cls(Y, X - 1, C3 = Ord('W')) = K) Do Dec(X);
      X1 := X;
      X2 := Cx;
      While (X2 < Length(L[Y])) And (Cls(Y, X2 + 1, C3 = Ord('W')) = K) Do
        Inc(X2);
      If C2 = Ord('a') Then
      Begin
        If (X2 < Length(L[Y])) And (Cls(Y, X2 + 1, False) = 0) Then
          While (X2 < Length(L[Y])) And (Cls(Y, X2 + 1, False) = 0) Do Inc(X2)
        Else
          While (X1 > 1) And (Cls(Y, X1 - 1, False) = 0) Do Dec(X1);
      End;
      ApplyOp(Op, Y, X1, Y, X2, False);
    End;
    Exit;
  End;
  { cw : comme ce (le mot sans espaces suivants) }
  If (Op = 'c') And ((C2 = Ord('w')) Or (C2 = Ord('W'))) Then
    If Cls(Cy, Cx, C2 = Ord('W')) <> 0 Then
    Begin
      Y := Cy; X := Cx;
      K := Cnt;
      While K > 0 Do
      Begin
        If (X >= Length(L[Y])) Or
           (Cls(Y, X + 1, C2 = Ord('W')) <> Cls(Y, X, C2 = Ord('W'))) Then
        Begin
          If K > 1 Then
          Begin
            Dec(K);
            WordEnd(Y, X, C2 = Ord('W'));
            Continue;
          End;
        End
        Else If K > 1 Then
        Begin
          WordEnd(Y, X, C2 = Ord('W'));
          Dec(K);
          Continue;
        End
        Else
          While (X < Length(L[Y])) And
                (Cls(Y, X + 1, C2 = Ord('W')) = Cls(Y, X, C2 = Ord('W'))) Do
            Inc(X);
        Break;
      End;
      ApplyOp('c', Cy, Cx, Y, X, False);
      Exit;
    End;
  Motion(C2, Cnt, HasCnt, True, Ty, Tx, Lw, Inc_, Ok);
  If Not Ok Then
  Begin
    Exit;
  End;
  { dw sur la derniere partie d'une ligne : s'arrete a la fin de la ligne }
  If ((C2 = Ord('w')) Or (C2 = Ord('W'))) And (Ty > Cy) Then
  Begin
    Ty := Cy;
    Tx := Length(L[Cy]);
    Inc_ := True;
  End;
  Y1 := Cy; X1 := Cx; Y2 := Ty; X2 := Tx;
  If (Y2 < Y1) Or ((Y2 = Y1) And (X2 < X1)) Then
  Begin
    K := Y1; Y1 := Y2; Y2 := K;
    K := X1; X1 := X2; X2 := K;
  End;
  If Lw Then
  Begin
    ApplyOp(Op, Y1, 1, Y2, 1, True);
    Exit;
  End;
  If Not Inc_ Then
  Begin
    If (X2 = 1) And (Y2 > Y1) Then
    Begin
      Dec(Y2);
      X2 := Length(L[Y2]);
    End
    Else Dec(X2);
  End;
  ApplyOp(Op, Y1, X1, Y2, X2, False);
End;

Procedure ScrollTo(Cmd : Char);
Begin
  Case Cmd Of
    '.' : Top := Cy - (Rows - 1) Div 2;
    #13 : Top := Cy;
    '-' : Top := Cy - (Rows - 2);
  End;
  If Top < 1 Then Top := 1;
End;

Procedure NormalCmd;
Var
  C, C2, Cnt, K, I, Ty, Tx, Y, X, N : LongInt;
  HasCnt, Lw, Inc_, Ok, Modif, Rep0 : Boolean;
  S, T : String;
  Ch : Char;
Begin
  Rep0 := KQPos <= Length(KQ);
  CurKeys := '';
  Cnt := 1;
  HasCnt := False;
  Modif := False;
  C := GetKey;
  If C = K_EOF Then
  Begin
    Quit := True;
    Exit;
  End;
  If C = Ord('"') Then
  Begin
    GetKey;
    C := GetKey;
  End;
  If (C >= Ord('1')) And (C <= Ord('9')) Then
  Begin
    Cnt := 0;
    HasCnt := True;
    While ((C >= Ord('0')) And (C <= Ord('9'))) Do
    Begin
      Cnt := Cnt * 10 + C - 48;
      If Cnt > 100000 Then Cnt := 100000;
      C := GetKey;
    End;
  End;
  Msg := '';
  Case C Of
    Ord('i'), Ord('a'), Ord('I'), Ord('A'), Ord('o'), Ord('O') :
      Begin
        SaveUndo;
        Modif := True;
        Case C Of
          Ord('a') : If Length(L[Cy]) > 0 Then Inc(Cx);
          Ord('A') : Cx := Length(L[Cy]) + 1;
          Ord('I') :
            Begin
              FirstNonBlank;
              If (Length(L[Cy]) > 0) And
                 ((L[Cy][Cx] = ' ') Or (L[Cy][Cx] = #9)) Then Cx := Cx + 1;
            End;
          Ord('o') :
            Begin
              S := '';
              If OptAi Then S := Indent(L[Cy]);
              InsLine(Cy + 1, S);
              Inc(Cy);
              Cx := Length(S) + 1;
            End;
          Ord('O') :
            Begin
              S := '';
              If OptAi Then S := Indent(L[Cy]);
              InsLine(Cy, S);
              Cx := Length(S) + 1;
            End;
        End;
        If (C = Ord('o')) Or (C = Ord('O')) Then
        Begin
          InsertMode(False, 1);
          { 3ohello : repetition par lignes }
          For I := 2 To Cnt Do
          Begin
            InsLine(Cy + 1, L[Cy]);
            Inc(Cy);
          End;
        End
        Else InsertMode(False, Cnt);
      End;
    Ord('R') :
      Begin
        SaveUndo;
        Modif := True;
        InsertMode(True, 1);
      End;
    Ord('x'), K_DEL :
      Begin
        If Length(L[Cy]) > 0 Then
        Begin
          SaveUndo;
          Modif := True;
          N := Cx + Cnt - 1;
          If N > Length(L[Cy]) Then N := Length(L[Cy]);
          YankChars(Cy, Cx, Cy, N);
          Delete(L[Cy], Cx, N - Cx + 1);
          Modified := True;
          Fix(False);
        End;
      End;
    Ord('X') :
      Begin
        If Cx > 1 Then
        Begin
          SaveUndo;
          Modif := True;
          N := Cx - Cnt;
          If N < 1 Then N := 1;
          YankChars(Cy, N, Cy, Cx - 1);
          Delete(L[Cy], N, Cx - N);
          Cx := N;
          Modified := True;
        End;
      End;
    Ord('D'), Ord('C') :
      Begin
        SaveUndo;
        Modif := True;
        Y := Cy + Cnt - 1;
        If Y > NL Then Y := NL;
        If Length(L[Y]) >= Cx Then
        Begin
          If Y = Cy Then ApplyOp(Chr(Ord(C) + 32), Cy, Cx, Y, Length(L[Y]),
                                 False)
          Else ApplyOp(Chr(Ord(C) + 32), Cy, Cx, Y, Length(L[Y]), False);
        End
        Else If C = Ord('C') Then InsertMode(False, 1);
      End;
    Ord('s') :
      Begin
        SaveUndo;
        Modif := True;
        If Length(L[Cy]) > 0 Then
        Begin
          N := Cx + Cnt - 1;
          If N > Length(L[Cy]) Then N := Length(L[Cy]);
          ApplyOp('c', Cy, Cx, Cy, N, False);
        End
        Else InsertMode(False, 1);
      End;
    Ord('S') :
      Begin
        Modif := True;
        Y := Cy + Cnt - 1;
        If Y > NL Then Y := NL;
        ApplyOp('c', Cy, 1, Y, 1, True);
      End;
    Ord('d'), Ord('c'), Ord('y'), Ord('>'), Ord('<') :
      Begin
        Modif := C <> Ord('y');
        Y := Cy;
        X := Cx;
        DoOperator(Chr(C), Cnt, HasCnt);
        If C = Ord('y') Then
        Begin
          { yank : le curseur va au debut de la zone }
        End;
      End;
    Ord('Y') :
      Begin
        Y := Cy + Cnt - 1;
        If Y > NL Then Y := NL;
        YankLines(Cy, Y);
      End;
    Ord('p'), Ord('P') :
      Begin
        SaveUndo;
        Modif := True;
        For I := 1 To Cnt Do Put(C = Ord('p'));
      End;
    Ord('r') :
      Begin
        C2 := GetKey;
        If (C2 >= 32) And (C2 < 256) And (Cx + Cnt - 1 <= Length(L[Cy])) Then
        Begin
          SaveUndo;
          Modif := True;
          For I := 0 To Cnt - 1 Do L[Cy][Cx + I] := Chr(C2);
          Cx := Cx + Cnt - 1;
          Modified := True;
        End
        Else If (C2 = 13) And (Cx <= Length(L[Cy])) Then
        Begin
          SaveUndo;
          Modif := True;
          Delete(L[Cy], Cx, 1);
          SplitLine;
          Cx := 1;
        End;
      End;
    Ord('J') :
      Begin
        If Cy < NL Then
        Begin
          SaveUndo;
          Modif := True;
          N := Cnt;
          If N < 2 Then N := 2;
          For I := 2 To N Do
            If Cy < NL Then
            Begin
              T := L[Cy + 1];
              While (Length(T) > 0) And ((T[1] = ' ') Or (T[1] = #9)) Do
                Delete(T, 1, 1);
              K := Length(L[Cy]);
              If (K > 0) And (L[Cy][K] <> ' ') And (L[Cy][K] <> #9) And
                 (T <> '') And (T[1] <> ')') Then
                L[Cy] := L[Cy] + ' ' + T
              Else L[Cy] := L[Cy] + T;
              DelLine(Cy + 1);
              Cx := K + 1;
            End;
          Modified := True;
          Fix(False);
        End;
      End;
    Ord('~') :
      Begin
        If Length(L[Cy]) > 0 Then
        Begin
          SaveUndo;
          Modif := True;
          For I := 1 To Cnt Do
            If Cx <= Length(L[Cy]) Then
            Begin
              Ch := L[Cy][Cx];
              If (Ch >= 'a') And (Ch <= 'z') Then Ch := Chr(Ord(Ch) - 32)
              Else If (Ch >= 'A') And (Ch <= 'Z') Then Ch := Chr(Ord(Ch) + 32);
              L[Cy][Cx] := Ch;
              If Cx < Length(L[Cy]) Then Inc(Cx);
            End;
          Modified := True;
        End;
      End;
    Ord('u'), Ord('U') : DoUndo;
    Ord('.') :
      Begin
        If LastKeys <> '' Then
        Begin
          KQ := LastKeys;
          KQPos := 1;
          Replaying := True;
        End;
      End;
    Ord(':') :
      Begin
        If ReadLine(':', S) Then
        Begin
          Msg := '';
          If S <> '' Then ExCmd(S);
        End;
      End;
    Ord('&') : ExCmd('s/' + LastPat + '/' + LastRep + '/');
    Ord('m') :
      Begin
        C2 := GetKey;
        If (C2 >= Ord('a')) And (C2 <= Ord('z')) Then
        Begin
          Marks[C2 - 97] := Cy;
          MarkX[C2 - 97] := Cx;
        End;
      End;
    Ord('Z') :
      Begin
        C2 := GetKey;
        If C2 = Ord('Z') Then ExCmd('x')
        Else If C2 = Ord('Q') Then ExCmd('q!');
      End;
    Ord('*'), Ord('#') :
      Begin
        X := Cx;
        While (X <= Length(L[Cy])) And (Cls(Cy, X, False) <> 1) Do Inc(X);
        If X <= Length(L[Cy]) Then
        Begin
          While (X > 1) And (Cls(Cy, X - 1, False) = 1) Do Dec(X);
          N := X;
          While (N < Length(L[Cy])) And (Cls(Cy, N + 1, False) = 1) Do Inc(N);
          LastPat := '\<' + Copy(L[Cy], X, N - X + 1) + '\>';
          If C = Ord('*') Then LastDir := 1 Else LastDir := -1;
          Y := Cy;
          X := Cx;
          If LastDir > 0 Then Inc(X) Else X := X - 1;
          If FindNext(LastDir, Y, X) Then
          Begin
            Cy := Y;
            Cx := X;
          End
          Else Msg := MS(2);
        End;
      End;
    Ord('z') :
      Begin
        C2 := GetKey;
        ScrollTo(Chr(C2));
        If C2 = Ord('t') Then Top := Cy;
        If C2 = Ord('b') Then
        Begin
          Top := Cy - (Rows - 2);
          If Top < 1 Then Top := 1;
        End;
        Dirty := True;
      End;
    6, K_PGDN :
      Begin
        Top := Top + (Rows - 3) * Cnt;
        If Top > NL Then Top := NL;
        Cy := Top;
        FirstNonBlank;
      End;
    2, K_PGUP :
      Begin
        Top := Top - (Rows - 3) * Cnt;
        If Top < 1 Then Top := 1;
        Cy := Top + Rows - 2;
        If Cy > NL Then Cy := NL;
        FirstNonBlank;
      End;
    4 :
      Begin
        N := (Rows - 1) Div 2;
        Top := Top + N;
        Cy := Cy + N;
        If Cy > NL Then Cy := NL;
        If Top > NL Then Top := NL;
        FirstNonBlank;
      End;
    21 :
      Begin
        N := (Rows - 1) Div 2;
        Top := Top - N;
        If Top < 1 Then Top := 1;
        Cy := Cy - N;
        If Cy < 1 Then Cy := 1;
        FirstNonBlank;
      End;
    5 : If Top < NL Then Begin Inc(Top); If Cy < Top Then Cy := Top; End;
    25 : If Top > 1 Then Begin Dec(Top); If Cy > Top + Rows - 2 Then
           Cy := Top + Rows - 2; End;
    12 : Dirty := True;
    7 :
      Msg := '"' + FileName + '" ' + NumS(NL) + ' lines --' +
             NumS(Cy * 100 Div NL) + '%--';
    3, 27 : ;
    Ord('g') :
      Begin
        C2 := GetKey;
        If C2 = Ord('g') Then
        Begin
          If HasCnt Then Goto1(Cnt) Else Goto1(1);
          WantX := DCol(Cy, Cx);
        End
        Else If C2 = Ord('J') Then
        Begin
          Msg := MS(3);
        End;
      End;
  Else
    Begin
      Motion(C, Cnt, HasCnt, False, Ty, Tx, Lw, Inc_, Ok);
      If Ok Then
      Begin
        Cy := Ty;
        Cx := Tx;
        Fix(False);
        If (C <> Ord('j')) And (C <> Ord('k')) And (C <> K_UP) And
           (C <> K_DOWN) And (C <> 10) And (C <> 14) And (C <> 16) And
           (C <> Ord('$')) Then
          WantX := DCol(Cy, Cx)
        Else If (C = Ord('$')) Then WantX := 100000;
      End;
    End;
  End;
  If Modif And (Not Rep0) And (CurKeys <> '') Then LastKeys := CurKeys;
  Fix(False);
End;

{ ------------------------------ programme ------------------------------ }

Var
  I, K, StartLine, Code : LongInt;
  A : String;
BEGIN
  Lang := SysLang;
  If (Lang < 1) Or (Lang > 5) Then Lang := 1;
  NL := 1;
  L[1] := '';
  Cy := 1; Cx := 1; Top := 1; Left := 0;
  OptWs := True;
  OptAi := False;
  KQ := '';
  KQPos := 1;
  LastDir := 1;
  WantX := 0;
  StartLine := 0;
  FileName := '';
  Msg := '';
  A := SysArgStr(0);
  For I := 0 To 25 Do Marks[I] := 0;
  For I := 1 To SysArgCount - 1 Do
  Begin
    A := SysArgStr(I);
    If (A = '--help') Or (A = '/?') Then
    Begin
      SysPut(1, MS(8) + #10);
      SysExit(0);
    End;
    If (Length(A) > 1) And (A[1] = '+') Then
    Begin
      Val(Copy(A, 2, 255), StartLine, Code);
      If Code <> 0 Then StartLine := NL + 100000;
    End
    Else If (A[1] = '-') And (Length(A) > 1) Then
    Begin
    End
    Else If FileName = '' Then FileName := A;
  End;
  HaveTerm := SysTcGetAttr(0, SavedTerm) = 0;
  If Not HaveTerm Then
  Begin
    SysPut(2, 'vi: not a terminal'#10);
    SysExit(1);
  End;
  Term := SavedTerm;
  Term.LFlag := Term.LFlag And Not (TTY_ICANON Or TTY_ECHO Or TTY_ISIG Or
                                    TTY_IEXTEN);
  Term.IFlag := Term.IFlag And Not (TTY_ICRNL Or TTY_IXON);
  Term.CC[TTY_VMIN] := 1;
  Term.CC[TTY_VTIME] := 0;
  SysTcSetAttr(0, 1, Term);
  OPut(#27 + '[?1049h' + #27 + '[2J');
  LoadFile(FileName);
  If StartLine > 0 Then Goto1(StartLine);
  WantX := DCol(Cy, Cx);
  Quit := False;
  Dirty := True;
  While Not Quit Do
  Begin
    Fix(False);
    Redraw('');
    NormalCmd;
  End;
  OPut(#27 + '[?1049l');
  OFlush;
  SysTcSetAttr(0, 1, SavedTerm);
END.
