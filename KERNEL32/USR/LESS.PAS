{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2026
  @website(https://www.gladir.com/linux-0)
  @abstract(Target: LPC -3X)
  @description: /bin/less et /bin/more : pagineur. Lit des fichiers ou
      l'entree standard (le clavier est alors lu sur /dev/tty). Commandes :
      espace f ^F PgDn, b ^B PgUp, d u, j k Entree fleches, g G Ng, p N%,
      / ? n N (expressions regulieres, motifs mis en relief), -N -S -i,
      = (position), v (edition par vi), :n :p (fichiers), h (aide), q.
      more quitte a la fin du dernier fichier. Sortie non terminal : cat.
      Limites : 16 Mo, 400000 lignes (le reste est ignore).
}

Program LESS;

{$I REGEX.INC}

Const
  BufMax = 16777216;
  MaxLn = 400000;
  K_UP = 256; K_DOWN = 257; K_RIGHT = 258; K_LEFT = 259; K_HOME = 260;
  K_END = 261; K_PGUP = 262; K_PGDN = 263;
  Help : Array[1..5] Of PChar = (
    'SPC f b d u j k g G / ? n N -N = v q : page, ligne, recherche, quitter',
    'SPC f b d u j k g G / ? n N -N = v q : page, line, search, quit',
    'SPC f b d u j k g G / ? n N -N = v q : Seite, Zeile, Suche, Ende',
    'SPC f b d u j k g G / ? n N -N = v q : pagina, linea, buscar, salir',
    'SPC f b d u j k g G / ? n N -N = v q : pagina, riga, cerca, esci');

Var
  Buf : Array[0..BufMax] Of Byte;
  BLen : LongInt;
  Starts : Array[0..MaxLn] Of LongInt;
  NLn : LongInt;
  Top, Rows, Cols : LongInt;
  Files : Array[1..64] Of String;
  NFiles, CurFile : LongInt;
  Name : String;
  IsMore, ShowNum, Chop, Icase, IsTty : Boolean;
  Tty : LongInt;
  Term, Saved : TSysTermios;
  HaveTerm : Boolean;
  Pat : String;
  PatDir : LongInt;
  SPr : LongInt;
  SOk : Boolean;
  Msg : String;
  OutS : String;
  Lang : LongInt;
  FromStdin : Boolean;

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

Function NumS(V : LongInt) : String;
Var S : String;
Begin
  Str(V, S);
  NumS := S;
End;

Procedure OFlush;
Begin
  If Length(OutS) > 0 Then SysPut(1, OutS);
  OutS := '';
End;

Procedure OPut(Const S : String);
Begin
  If Length(OutS) + Length(S) > 250 Then OFlush;
  OutS := OutS + S;
End;

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

{ ---------- chargement ---------- }

Procedure Index;
Var I : LongInt;
Begin
  NLn := 0;
  Starts[0] := 0;
  For I := 0 To BLen - 1 Do
    If Buf[I] = 10 Then
    Begin
      Inc(NLn);
      If NLn <= MaxLn Then Starts[NLn] := I + 1;
    End;
  If NLn > MaxLn Then NLn := MaxLn;
  If (BLen > 0) And (Buf[BLen - 1] <> 10) Then
  Begin
    Inc(NLn);
    Starts[NLn] := BLen + 1;
  End;
  { NLn = nombre de lignes ; ligne k (1..NLn) = Starts[k-1] .. Starts[k]-1 }
End;

Function LoadFd(Fd : LongInt) : Boolean;
Var N : LongInt;
Begin
  BLen := 0;
  Repeat
    N := SysRead(Fd, Buf[BLen], 65536);
    If N > 0 Then BLen := BLen + N;
  Until (N <= 0) Or (BLen + 65536 > BufMax);
  Index;
  LoadFd := True;
End;

Function LoadName(Const F : String) : Boolean;
Var Fd : LongInt;
Begin
  LoadName := False;
  Fd := SysOpen(F, O_RDONLY, 0);
  If Fd < 0 Then
  Begin
    Msg := F + ': ' + SysErrorText(SysErrno);
    Exit;
  End;
  LoadFd(Fd);
  SysClose(Fd);
  LoadName := True;
End;

{ ---------- texte d'une ligne ---------- }

Function LineStr(K : LongInt) : String;
Var I, E, N : LongInt; S : String;
Begin
  S := '';
  If (K < 1) Or (K > NLn) Then
  Begin
    LineStr := S;
    Exit;
  End;
  E := Starts[K] - 1;
  If E > BLen Then E := BLen;
  If (E > Starts[K - 1]) And (Buf[E - 1] = 10) Then Dec(E);
  N := 0;
  For I := Starts[K - 1] To E - 1 Do
    If N < 250 Then
    Begin
      S := S + Chr(Buf[I]);
      Inc(N);
    End;
  LineStr := S;
End;

{ largeur affichable d'un texte (sequences ESC [ ... m de largeur nulle) }
Function Render(Const S : String; Var Vis : LongInt) : String;
Var I, C : LongInt; R : String; B : Byte; InEsc : Boolean;
Begin
  R := '';
  C := 0;
  InEsc := False;
  For I := 1 To Length(S) Do
  Begin
    B := Ord(S[I]);
    If InEsc Then
    Begin
      R := R + Chr(B);
      If ((B >= 64) And (B <= 126)) And (B <> 91) Then InEsc := False;
    End
    Else If B = 27 Then
    Begin
      InEsc := True;
      R := R + Chr(B);
    End
    Else If B = 9 Then
    Begin
      Repeat
        R := R + ' ';
        Inc(C);
      Until (C And 7) = 0;
    End
    Else If B = 13 Then
    Else If (B < 32) Or (B = 127) Then
    Begin
      R := R + '^' + Chr(B Xor 64);
      C := C + 2;
    End
    Else
    Begin
      R := R + Chr(B);
      If (B And $C0) <> $80 Then Inc(C);
    End;
  End;
  Vis := C;
  Render := R;
End;

{ nombre de rangees ecran de la ligne K }
Function RowsOf(K : LongInt) : LongInt;
Var V : LongInt; R : String;
Begin
  If Chop Then
  Begin
    RowsOf := 1;
    Exit;
  End;
  R := Render(LineStr(K), V);
  If ShowNum Then V := V + 7;
  If V <= Cols Then RowsOf := 1 Else RowsOf := (V + Cols - 1) Div Cols;
End;

{ met en relief les correspondances du motif dans le texte rendu }
Function Highlight(Const R : String) : String;
Var Res : String; P, S, E : LongInt; Tmp : String;
Begin
  If (Pat = '') Or (Not SOk) Then
  Begin
    Highlight := R;
    Exit;
  End;
  Tmp := R;
  Res := '';
  P := 0;
  While P <= Length(Tmp) Do
  Begin
    If Not ReSearch(SPr, LongInt(@Tmp[1]), Length(Tmp), P, False) Then Break;
    S := ReCap[0];
    E := ReCap[1];
    If E = S Then Break;
    Res := Res + Copy(Tmp, P + 1, S - P) + #27 + '[7m' +
           Copy(Tmp, S + 1, E - S) + #27 + '[27m';
    P := E;
  End;
  Highlight := Res + Copy(Tmp, P + 1, 255);
End;

Function Percent : LongInt;
Var L : LongInt;
Begin
  L := Top + Rows - 2;
  If L >= NLn Then Percent := 100
  Else If NLn = 0 Then Percent := 100
  Else Percent := L * 100 Div NLn;
End;

Function LastTop : LongInt;
Var K, R, T : LongInt;
Begin
  { premiere ligne telle que les lignes suivantes tiennent dans l'ecran }
  R := 0;
  K := NLn;
  While (K >= 1) And (R + RowsOf(K) <= Rows - 1) Do
  Begin
    R := R + RowsOf(K);
    Dec(K);
  End;
  T := K + 1;
  If T < 1 Then T := 1;
  LastTop := T;
End;

Procedure Draw;
Var
  R, K, V, Used, Part : LongInt;
  S, T, Pre, St : String;
Begin
  Layout;
  OPut(#27 + '[H');
  Used := 0;
  K := Top;
  While (Used < Rows - 1) And (K <= NLn) Do
  Begin
    S := Render(LineStr(K), V);
    Pre := '';
    If ShowNum Then
    Begin
      Pre := NumS(K);
      While Length(Pre) < 6 Do Pre := ' ' + Pre;
      Pre := Pre + ' ';
    End;
    S := Highlight(S);
    If Chop Then
    Begin
      OPut(Pre + S + #27 + '[K'#13#10);
      Inc(Used);
    End
    Else
    Begin
      OPut(Pre + S + #27 + '[K'#13#10);
      Used := Used + RowsOf(K);
    End;
    Inc(K);
  End;
  While Used < Rows - 1 Do
  Begin
    OPut('~' + #27 + '[K'#13#10);
    Inc(Used);
  End;
  If Msg <> '' Then St := Msg
  Else If NLn = 0 Then St := '(END)'
  Else If Top + Rows - 2 >= NLn Then
  Begin
    If IsMore Then St := '--More--(100%)' Else St := '(END)';
  End
  Else If IsMore Then St := '--More--(' + NumS(Percent) + '%)'
  Else St := Name + ' lines ' + NumS(Top) + '-' + NumS(Top + Rows - 2) +
             '/' + NumS(NLn) + ' ' + NumS(Percent) + '%';
  If Length(St) > Cols - 1 Then St := Copy(St, 1, Cols - 1);
  OPut(#27 + '[7m' + St + #27 + '[m' + #27 + '[K');
  OFlush;
  Msg := '';
End;

{ ---------- entree ---------- }

Function RawKey : LongInt;
Var B : Byte; N : LongInt;
Begin
  N := SysRead(Tty, B, 1);
  If N <= 0 Then RawKey := -1 Else RawKey := B;
End;

Function MoreIn(Ms : LongInt) : Boolean;
Var Pf : Array[0..1] Of LongInt;
Begin
  Pf[0] := Tty;
  Pf[1] := 1;
  MoreIn := SysPoll(LongInt(@Pf), 1, Ms) > 0;
End;

Function GetKey : LongInt;
Var C, D, E : LongInt;
Begin
  C := RawKey;
  If C = 27 Then
    If MoreIn(40) Then
    Begin
      D := RawKey;
      If (D = 91) Or (D = 79) Then
      Begin
        E := RawKey;
        Case E Of
          65 : C := K_UP;
          66 : C := K_DOWN;
          67 : C := K_RIGHT;
          68 : C := K_LEFT;
          72 : C := K_HOME;
          70 : C := K_END;
          53 : Begin RawKey; C := K_PGUP; End;
          54 : Begin RawKey; C := K_PGDN; End;
          49, 55 : Begin RawKey; C := K_HOME; End;
          52, 56 : Begin RawKey; C := K_END; End;
        End;
      End;
    End;
  GetKey := C;
End;

Function ReadLine(Const Prompt : String; Var S : String) : Boolean;
Var C : LongInt;
Begin
  S := '';
  ReadLine := False;
  While True Do
  Begin
    OPut(#27 + '[' + NumS(Rows) + ';1H' + #27 + '[K' + Prompt + S);
    OFlush;
    C := GetKey;
    If (C = 13) Or (C = 10) Then
    Begin
      ReadLine := True;
      Exit;
    End;
    If (C = 27) Or (C = 3) Or (C < 0) Then Exit;
    If (C = 8) Or (C = 127) Then
    Begin
      If S = '' Then Exit;
      Delete(S, Length(S), 1);
    End
    Else If (C >= 32) And (C < 256) And (Length(S) < 200) Then S := S + Chr(C);
  End;
End;

{ ---------- recherche ---------- }

Function Compile : Boolean;
Begin
  SPr := ReCompile(Pat, False, Icase);
  SOk := SPr >= 0;
  Compile := SOk;
End;

Function Search(From, Dir : LongInt) : Boolean;
Var K : LongInt; S : String;
Begin
  Search := False;
  If (Pat = '') Or (Not Compile) Then Exit;
  K := From;
  While (K >= 1) And (K <= NLn) Do
  Begin
    S := LineStr(K);
    If Length(S) > 0 Then
    Begin
      If ReSearch(SPr, LongInt(@S[1]), Length(S), 0, False) Then
      Begin
        Top := K;
        Search := True;
        Exit;
      End;
    End
    Else If ReSearch(SPr, LongInt(@S), 0, 0, False) Then
    Begin
      Top := K;
      Search := True;
      Exit;
    End;
    K := K + Dir;
  End;
End;

{ ---------- fichiers ---------- }

Procedure OpenCur;
Begin
  If FromStdin Then
  Begin
    Name := '(stdin)';
    Exit;
  End;
  Name := Files[CurFile];
  If Not LoadName(Name) Then
  Begin
    BLen := 0;
    NLn := 0;
  End;
  Top := 1;
End;

Procedure Edit;
Var Pid, St : LongInt;
Begin
  If FromStdin Then Exit;
  SysTcSetAttr(Tty, 1, Saved);
  OPut(#27 + '[?1049l');
  OFlush;
  Pid := SysFork;
  If Pid = 0 Then
  Begin
    SysArgReset;
    SysArgAdd('vi');
    SysArgAdd('+' + NumS(Top));
    SysArgAdd(Name);
    SysEnvInherit;
    SysArgExec('/bin/vi');
    SysExit(127);
  End;
  SysWaitPid(Pid, St, 0);
  SysTcSetAttr(Tty, 1, Term);
  OPut(#27 + '[?1049h');
  LoadName(Name);
End;

Procedure CatAll;
Var I, N, Fd : LongInt; B : Array[0..8191] Of Byte;
Begin
  If NFiles = 0 Then
  Begin
    Repeat
      N := SysRead(0, B, 8192);
      If N > 0 Then SysWrite(1, B, N);
    Until N <= 0;
    Exit;
  End;
  For I := 1 To NFiles Do
  Begin
    Fd := SysOpen(Files[I], O_RDONLY, 0);
    If Fd < 0 Then
      SysPut(2, 'less: ' + Files[I] + ': ' + SysErrorText(SysErrno) + #10)
    Else
    Begin
      Repeat
        N := SysRead(Fd, B, 8192);
        If N > 0 Then SysWrite(1, B, N);
      Until N <= 0;
      SysClose(Fd);
    End;
  End;
End;

Procedure Fwd(N : LongInt);
Var T : LongInt;
Begin
  T := LastTop;
  If Top + N <= T Then Top := Top + N
  Else Top := T;
  If Top < 1 Then Top := 1;
End;

Var
  I, C, Cnt, K, Code : LongInt;
  A, S : String;
  Quit, HasCnt : Boolean;
  Prog : String;
BEGIN
  Lang := SysLang;
  If (Lang < 1) Or (Lang > 5) Then Lang := 1;
  Prog := SysArgStr(0);
  While Pos('/', Prog) > 0 Do Prog := Copy(Prog, Pos('/', Prog) + 1, 255);
  IsMore := Prog = 'more';
  ShowNum := False;
  Chop := False;
  Icase := False;
  NFiles := 0;
  PatDir := 1;
  For I := 1 To SysArgCount - 1 Do
  Begin
    A := SysArgStr(I);
    If (A = '--help') Or (A = '/?') Then
    Begin
      SysPut(1, 'Usage: ' + Prog + ' [-NSi] [+/pattern] [file...]' + #10);
      SysExit(0);
    End
    Else If (Length(A) > 1) And (A[1] = '-') Then
    Begin
      For K := 2 To Length(A) Do
        Case A[K] Of
          'N' : ShowNum := True;
          'S' : Chop := True;
          'i', 'I' : Icase := True;
        End;
    End
    Else If (Length(A) > 2) And (A[1] = '+') And (A[2] = '/') Then
      Pat := Copy(A, 3, 255)
    Else If NFiles < 64 Then
    Begin
      Inc(NFiles);
      Files[NFiles] := A;
    End;
  End;
  IsTty := SysIsATty(1);
  FromStdin := NFiles = 0;
  If (Not IsTty) Or ((Not SysIsATty(0)) And FromStdin And False) Then
  Begin
    CatAll;
    SysExit(0);
  End;
  { clavier : /dev/tty, sinon l'entree standard }
  Tty := 0;
  If Not SysIsATty(0) Then
  Begin
    Tty := SysOpen('/dev/tty', O_RDWR, 0);
    If Tty < 0 Then
    Begin
      CatAll;
      SysExit(0);
    End;
  End;
  If FromStdin Then
  Begin
    LoadFd(0);
    Name := '(stdin)';
  End
  Else
  Begin
    CurFile := 1;
    OpenCur;
  End;
  Top := 1;
  HaveTerm := SysTcGetAttr(Tty, Saved) = 0;
  Term := Saved;
  Term.LFlag := Term.LFlag And Not (TTY_ICANON Or TTY_ECHO Or TTY_ISIG Or
                                    TTY_IEXTEN);
  Term.IFlag := Term.IFlag And Not (TTY_ICRNL Or TTY_IXON);
  Term.CC[TTY_VMIN] := 1;
  Term.CC[TTY_VTIME] := 0;
  If HaveTerm Then SysTcSetAttr(Tty, 1, Term);
  If Not IsMore Then OPut(#27 + '[?1049h');
  Layout;
  If Pat <> '' Then
  Begin
    Search(1, 1);
  End;
  Quit := False;
  While Not Quit Do
  Begin
    If Top > NLn Then Top := NLn;
    If Top < 1 Then Top := 1;
    Draw;
    Cnt := 0;
    HasCnt := False;
    C := GetKey;
    While (C >= Ord('0')) And (C <= Ord('9')) Do
    Begin
      Cnt := Cnt * 10 + C - 48;
      HasCnt := True;
      C := GetKey;
    End;
    If Not HasCnt Then Cnt := 1;
    Case C Of
      Ord(' '), Ord('f'), 6, K_PGDN, 22 :
        Begin
          If IsMore And (Top + Rows - 2 >= NLn) Then
          Begin
            If (Not FromStdin) And (CurFile < NFiles) Then
            Begin
              Inc(CurFile);
              OpenCur;
            End
            Else Quit := True;
          End
          Else Fwd((Rows - 1) * Cnt);
        End;
      13, 10, Ord('j'), 14, K_DOWN, Ord('e'), 5 :
        Begin
          If IsMore And (Top + Rows - 2 >= NLn) Then Quit := True
          Else Fwd(Cnt);
        End;
      Ord('b'), 2, K_PGUP, 27 + 1000 :
        Begin
          Top := Top - (Rows - 1) * Cnt;
          If Top < 1 Then Top := 1;
        End;
      Ord('k'), 16, K_UP, Ord('y'), 25 :
        Begin
          Top := Top - Cnt;
          If Top < 1 Then Top := 1;
        End;
      Ord('d'), 4 : Fwd(((Rows - 1) Div 2) * Cnt);
      Ord('u'), 21 :
        Begin
          Top := Top - ((Rows - 1) Div 2) * Cnt;
          If Top < 1 Then Top := 1;
        End;
      Ord('g'), Ord('<'), K_HOME :
        Begin
          If HasCnt Then Top := Cnt Else Top := 1;
        End;
      Ord('G'), Ord('>'), K_END :
        Begin
          If HasCnt Then Top := Cnt Else Top := LastTop;
        End;
      Ord('p'), Ord('%') :
        Begin
          If HasCnt Then Top := (NLn * Cnt) Div 100 + 1;
        End;
      Ord('/'), Ord('?') :
        Begin
          If C = Ord('/') Then K := 1 Else K := -1;
          If ReadLine(Chr(C), S) Then
          Begin
            If S <> '' Then Pat := S;
            PatDir := K;
            If Not Search(Top + K, K) Then Msg := 'Pattern not found';
          End;
        End;
      Ord('n'), Ord('N') :
        Begin
          K := PatDir;
          If C = Ord('N') Then K := -K;
          If Not Search(Top + K, K) Then Msg := 'Pattern not found';
        End;
      Ord('-') :
        Begin
          C := GetKey;
          If C = Ord('N') Then ShowNum := Not ShowNum
          Else If C = Ord('S') Then Chop := Not Chop
          Else If C = Ord('i') Then Icase := Not Icase;
        End;
      Ord('='), 7 :
        Msg := Name + ' lines ' + NumS(Top) + '-' + NumS(Top + Rows - 2) +
               '/' + NumS(NLn) + ' ' + NumS(Percent) + '%';
      Ord('v') : Edit;
      Ord('h'), Ord('H') : Msg := PS(Help[Lang]);
      Ord('r'), 12 : ;
      Ord(':') :
        Begin
          C := GetKey;
          If (C = Ord('n')) And (Not FromStdin) And (CurFile < NFiles) Then
          Begin
            Inc(CurFile);
            OpenCur;
          End
          Else If (C = Ord('p')) And (Not FromStdin) And (CurFile > 1) Then
          Begin
            Dec(CurFile);
            OpenCur;
          End
          Else If C = Ord('q') Then Quit := True;
        End;
      Ord('q'), Ord('Q'), 3, -1 : Quit := True;
      Ord('Z') :
        Begin
          C := GetKey;
          If C = Ord('Z') Then Quit := True;
        End;
    End;
  End;
  If Not IsMore Then OPut(#27 + '[?1049l')
  Else OPut(#27 + '[' + NumS(Rows) + ';1H' + #27 + '[K');
  OFlush;
  If HaveTerm Then SysTcSetAttr(Tty, 1, Saved);
END.
