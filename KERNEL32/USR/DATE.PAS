{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2026
  @website(https://www.gladir.com/linux-0)
  @abstract(Target: LPC -3X)
  @description: /bin/date : affiche ou regle la date (syntaxe de GNU date).
   date [-u] [-d TEXTE | -r FICHIER | -s TEXTE] [-R | -I[date|hours|minutes|
        seconds] | +FORMAT]
   Fuseau : TZ ou /etc/localtime (L32API : TZif, heure d'ete) ; dans TEXTE,
   TZ="Zone" ou un sigle (UTC GMT Z CET CEST EST EDT PST PDT JST BST ...) ou
   +hh:mm. TEXTE : @epoch, AAAA-MM-JJ[ T]HH:MM[:SS], MM/JJ/AAAA, "15 June 2024",
   "June 15, 2024 3pm", now today yesterday tomorrow noon midnight, un jour de
   la semaine (monday, next friday, last tue), "3 days ago", "+2 weeks",
   "next month", "last year", "2024-01-31 +1 month".
   FORMAT : %a %A %b %B %h %c %C %d %D %e %F %g %G %H %I %j %k %l %m %M %n %N
   %p %P %r %R %s %S %t %T %u %U %V %w %W %x %X %y %Y %z %:z %Z %% ; indicateurs
   - (sans zero) _ (espaces) 0 ^ (majuscules) et largeur. Annees 1970..2037
   (secondes 32 bits). }

Program Date;

Const
  MonL : Array[1..12] Of String[9] = ('January', 'February', 'March', 'April',
    'May', 'June', 'July', 'August', 'September', 'October', 'November',
    'December');
  DayL : Array[0..6] Of String[9] = ('Sunday', 'Monday', 'Tuesday',
    'Wednesday', 'Thursday', 'Friday', 'Saturday');

Var
  UseUtc : Boolean;
  Zone : String;                    { zone en vigueur ('' = TZ/localtime) }
  { date analysee }
  PY, PM, PD, PH, PN, PS : LongInt;  { annee mois jour heure minute seconde }
  HaveD, HaveT, HaveOff, Relative : Boolean;
  OffSec : LongInt;                  { decalage explicite (secondes est) }
  RelDays, RelMonths, RelSecs, WantWd, WdMode : LongInt;
  Epoch : LongInt;
  HaveEpoch : Boolean;
  Base : LongInt;

Procedure Die(Const S : String);
Begin
  SysPut(2, 'date: ' + S + #10);
  SysExit(1);
End;

Function LowerS(Const S : String) : String;
Var I : LongInt; R : String;
Begin
  R := S;
  For I := 1 To Length(R) Do
    If (R[I] >= 'A') And (R[I] <= 'Z') Then R[I] := Chr(Ord(R[I]) + 32);
  LowerS := R;
End;

Function IsDigits(Const S : String) : Boolean;
Var I : LongInt;
Begin
  IsDigits := Length(S) > 0;
  For I := 1 To Length(S) Do
    If (S[I] < '0') Or (S[I] > '9') Then IsDigits := False;
End;

Function ToNum(Const S : String) : LongInt;
Var V, E : LongInt;
Begin
  Val(S, V, E);
  If E <> 0 Then V := -1;
  ToNum := V;
End;

Function Leap(Y : LongInt) : Boolean;
Begin
  Leap := ((Y Mod 4 = 0) And (Y Mod 100 <> 0)) Or (Y Mod 400 = 0);
End;

Function DaysIn(Y, M : LongInt) : LongInt;
Begin
  Case M Of
    4, 6, 9, 11 : DaysIn := 30;
    2 : If Leap(Y) Then DaysIn := 29 Else DaysIn := 28;
  Else
    DaysIn := 31;
  End;
End;

{ zone en vigueur : decalage a l'est de UTC pour l'instant UTC T }
Function OffAt(T : LongInt) : LongInt;
Begin
  If UseUtc Then OffAt := 0 Else OffAt := LnxTzAt(T);
End;

{ champs locaux d'un instant UTC }
Procedure Local(T : LongInt; Var Y, M, D, H, N, S, Wd : LongInt);
Var L, Days, Sec : LongInt;
Begin
  L := T + OffAt(T);
  Days := L Div 86400;
  Sec := L Mod 86400;
  If Sec < 0 Then
  Begin
    Sec := Sec + 86400;
    Dec(Days);
  End;
  LnxCivil(Days, Y, M, D);
  H := Sec Div 3600;
  N := (Sec Mod 3600) Div 60;
  S := Sec Mod 60;
  Wd := (Days + 4) Mod 7;
  If Wd < 0 Then Wd := Wd + 7;
End;

{ instant UTC d'une heure locale (champs, eventuellement hors bornes) }
Function FromLocal(Y, M, D, H, N, S : LongInt) : LongInt;
Var L : LongInt;
Begin
  While M > 12 Do
  Begin
    M := M - 12;
    Inc(Y);
  End;
  While M < 1 Do
  Begin
    M := M + 12;
    Dec(Y);
  End;
  L := LnxDaysFromCivil(Y, M, 1) * 86400 + (D - 1) * 86400 + H * 3600 +
       N * 60 + S;
  If UseUtc Then FromLocal := L Else FromLocal := LnxTzUtcOf(L);
End;

{ jour de l'annee (1..366) }
Function YDay(Y, M, D : LongInt) : LongInt;
Begin
  YDay := LnxDaysFromCivil(Y, M, D) - LnxDaysFromCivil(Y, 1, 1) + 1;
End;

{ ---- analyse du texte de -d ---- }

Function MonthOf(Const W : String) : LongInt;
Var I : LongInt; L : String;
Begin
  MonthOf := 0;
  L := LowerS(W);
  If Length(L) < 3 Then Exit;
  For I := 1 To 12 Do
    If (LowerS(MonL[I]) = L) Or (Copy(LowerS(MonL[I]), 1, 3) = L) Or
       ((I = 9) And (L = 'sept')) Then MonthOf := I;
End;

Function WeekdayOf(Const W : String) : LongInt;
Var I : LongInt; L : String;
Begin
  WeekdayOf := -1;
  L := LowerS(W);
  If Length(L) < 3 Then Exit;
  For I := 0 To 6 Do
    If (LowerS(DayL[I]) = L) Or (Copy(LowerS(DayL[I]), 1, 3) = L) Then
      WeekdayOf := I;
End;

{ sigle de zone -> decalage en secondes a l'est ; False si inconnu }
Function AbbrOff(Const W : String; Var Off : LongInt) : Boolean;
Var L : String;
Begin
  AbbrOff := True;
  L := LowerS(W);
  If (L = 'z') Or (L = 'utc') Or (L = 'gmt') Or (L = 'ut') Then Off := 0
  Else If L = 'cet' Then Off := 3600
  Else If L = 'cest' Then Off := 7200
  Else If L = 'eet' Then Off := 7200
  Else If L = 'eest' Then Off := 10800
  Else If L = 'wet' Then Off := 0
  Else If L = 'west' Then Off := 3600
  Else If L = 'bst' Then Off := 3600
  Else If L = 'est' Then Off := -18000
  Else If L = 'edt' Then Off := -14400
  Else If L = 'cst' Then Off := -21600
  Else If L = 'cdt' Then Off := -18000
  Else If L = 'mst' Then Off := -25200
  Else If L = 'mdt' Then Off := -21600
  Else If L = 'pst' Then Off := -28800
  Else If L = 'pdt' Then Off := -25200
  Else If L = 'jst' Then Off := 32400
  Else If L = 'msk' Then Off := 10800
  Else AbbrOff := False;
End;

{ +hh:mm, -hhmm, +hh }
Function NumOff(Const W : String; Var Off : LongInt) : Boolean;
Var S : String; H, M, Sg : LongInt;
Begin
  NumOff := False;
  If (Length(W) < 2) Or ((W[1] <> '+') And (W[1] <> '-')) Then Exit;
  If W[1] = '-' Then Sg := -1 Else Sg := 1;
  S := Copy(W, 2, 10);
  M := 0;
  If Pos(':', S) > 0 Then
  Begin
    H := ToNum(Copy(S, 1, Pos(':', S) - 1));
    M := ToNum(Copy(S, Pos(':', S) + 1, 2));
  End
  Else If Length(S) = 4 Then
  Begin
    H := ToNum(Copy(S, 1, 2));
    M := ToNum(Copy(S, 3, 2));
  End
  Else H := ToNum(S);
  If (H < 0) Or (M < 0) Or (H > 14) Or (M > 59) Then Exit;
  Off := Sg * (H * 3600 + M * 60);
  NumOff := True;
End;

Function UnitSecs(Const U : String) : LongInt;
Var L : String;
Begin
  L := LowerS(U);
  If (L = 'sec') Or (L = 'secs') Or (L = 'second') Or (L = 'seconds') Then
    UnitSecs := 1
  Else If (L = 'min') Or (L = 'mins') Or (L = 'minute') Or (L = 'minutes') Then
    UnitSecs := 60
  Else If (L = 'hour') Or (L = 'hours') Or (L = 'hr') Or (L = 'hrs') Then
    UnitSecs := 3600
  Else If (L = 'day') Or (L = 'days') Then UnitSecs := 86400
  Else If (L = 'week') Or (L = 'weeks') Then UnitSecs := 604800
  Else If (L = 'fortnight') Or (L = 'fortnights') Then UnitSecs := 1209600
  Else If (L = 'month') Or (L = 'months') Then UnitSecs := -1
  Else If (L = 'year') Or (L = 'years') Then UnitSecs := -12
  Else UnitSecs := 0;
End;

Procedure AddRel(N, U : LongInt);
Begin
  If U > 0 Then
  Begin
    If U Mod 86400 = 0 Then RelDays := RelDays + N * (U Div 86400)
    Else RelSecs := RelSecs + N * U;
  End
  Else RelMonths := RelMonths + N * (-U);
  Relative := True;
End;

Function Tok(Const S : String; Var P : LongInt) : String;
Var T : String;
Begin
  While (P <= Length(S)) And ((S[P] = ' ') Or (S[P] = ',')) Do Inc(P);
  T := '';
  While (P <= Length(S)) And (S[P] <> ' ') And (S[P] <> ',') Do
  Begin
    T := T + S[P];
    Inc(P);
  End;
  Tok := T;
End;

{ analyse une heure HH:MM[:SS][am|pm] ; Suffix : "am"/"pm" separe }
Function ParseTime(Const W : String) : Boolean;
Var A, B, C, K, H, M, S : LongInt; T, Sfx : String;
Begin
  ParseTime := False;
  T := LowerS(W);
  Sfx := '';
  If (Length(T) > 2) And ((Copy(T, Length(T) - 1, 2) = 'am') Or
     (Copy(T, Length(T) - 1, 2) = 'pm')) Then
  Begin
    Sfx := Copy(T, Length(T) - 1, 2);
    T := Copy(T, 1, Length(T) - 2);
  End;
  If Pos(':', T) = 0 Then
  Begin
    If (Sfx = '') Or Not IsDigits(T) Then Exit;
    H := ToNum(T);
    M := 0;
    S := 0;
  End
  Else
  Begin
    K := Pos(':', T);
    H := ToNum(Copy(T, 1, K - 1));
    T := Copy(T, K + 1, 20);
    K := Pos(':', T);
    S := 0;
    If K > 0 Then
    Begin
      M := ToNum(Copy(T, 1, K - 1));
      S := ToNum(Copy(T, K + 1, 2));
    End
    Else M := ToNum(T);
  End;
  If (H < 0) Or (M < 0) Or (S < 0) Or (M > 59) Or (S > 60) Then Exit;
  If Sfx = 'pm' Then
  Begin
    If H < 12 Then H := H + 12;
  End
  Else If Sfx = 'am' Then
  Begin
    If H = 12 Then H := 0;
  End;
  If H > 24 Then Exit;
  PH := H; PN := M; PS := S;
  HaveT := True;
  ParseTime := True;
End;

{ date ISO / US dans un seul mot : AAAA-MM-JJ, AAAA/MM/JJ, MM/JJ/AAAA,
  AAAAMMJJ, avec eventuel T HH:MM... colle }
Function ParseDateWord(Const W : String) : Boolean;
Var A, B, C, K : LongInt; T, R : String; Sep : Char;
Begin
  ParseDateWord := False;
  T := W;
  K := Pos('T', T);
  If (K > 4) And IsDigits(Copy(T, 1, 4)) Then
  Begin
    R := Copy(T, K + 1, 40);
    T := Copy(T, 1, K - 1);
    If Not ParseDateWord(T) Then Exit;
    { fuseau colle : Z, +hh:mm, -hh:mm }
    K := Length(R);
    If (K > 0) And ((R[K] = 'Z') Or (R[K] = 'z')) Then
    Begin
      HaveOff := True;
      OffSec := 0;
      R := Copy(R, 1, K - 1);
    End
    Else
    Begin
      K := Pos('+', R);
      If K = 0 Then K := Pos('-', R);
      If K > 0 Then
      Begin
        If NumOff(Copy(R, K, 10), OffSec) Then HaveOff := True;
        R := Copy(R, 1, K - 1);
      End;
    End;
    ParseDateWord := ParseTime(R);
    Exit;
  End;
  Sep := '-';
  If Pos('/', T) > 0 Then Sep := '/';
  K := Pos(Sep, T);
  If K > 0 Then
  Begin
    A := ToNum(Copy(T, 1, K - 1));
    T := Copy(T, K + 1, 20);
    K := Pos(Sep, T);
    If K = 0 Then Exit;
    B := ToNum(Copy(T, 1, K - 1));
    C := ToNum(Copy(T, K + 1, 10));
    If (A < 0) Or (B < 0) Or (C < 0) Then Exit;
    If A > 31 Then
    Begin
      PY := A; PM := B; PD := C;
    End
    Else If Sep = '/' Then
    Begin
      PM := A; PD := B; PY := C;
      If PY < 100 Then
        If PY < 69 Then PY := PY + 2000 Else PY := PY + 1900;
    End
    Else Exit;
  End
  Else If IsDigits(T) And (Length(T) = 8) Then
  Begin
    PY := ToNum(Copy(T, 1, 4));
    PM := ToNum(Copy(T, 5, 2));
    PD := ToNum(Copy(T, 7, 2));
  End
  Else Exit;
  If (PM < 1) Or (PM > 12) Or (PD < 1) Or (PD > DaysIn(PY, PM)) Then Exit;
  HaveD := True;
  ParseDateWord := True;
End;

{ analyse le texte de -d ; remplit les champs P*, Rel*, Off* }
Procedure ParseText(Const Txt : String);
Var P, N, U, K, Wd : LongInt; W, W2, Lw : String; Ago : Boolean;
  Y, M, D, H, Mi, S, Dw : LongInt;
Begin
  P := 1;
  Local(Base, Y, M, D, H, Mi, S, Dw);
  While True Do
  Begin
    W := Tok(Txt, P);
    If W = '' Then Break;
    Lw := LowerS(W);
    If (Length(W) > 3) And (Copy(W, 1, 3) = 'TZ=') Then
    Begin
      W2 := Copy(W, 4, 80);
      While (Length(W2) > 0) And ((W2[1] = '"') Or (W2[1] = '''')) Do
        Delete(W2, 1, 1);
      While (Length(W2) > 0) And ((W2[Length(W2)] = '"') Or
            (W2[Length(W2)] = '''')) Do Delete(W2, Length(W2), 1);
      Zone := W2;
      LnxTzSelect(Zone);
      UseUtc := False;
    End
    Else If W[1] = '@' Then
    Begin
      Epoch := ToNum(Copy(W, 2, 15));
      If (Copy(W, 2, 1) = '-') Then Epoch := -ToNum(Copy(W, 3, 15));
      HaveEpoch := True;
    End
    Else If ParseDateWord(W) Then
    Begin
    End
    Else If ((Lw = 'am') Or (Lw = 'pm')) And HaveT Then
    Begin
      If (Lw = 'pm') And (PH < 12) Then PH := PH + 12;
      If (Lw = 'am') And (PH = 12) Then PH := 0;
    End
    Else If (Pos(':', W) > 0) Or (Copy(Lw, Length(Lw) - 1, 2) = 'am') Or
            (Copy(Lw, Length(Lw) - 1, 2) = 'pm') Then
    Begin
      If Not ParseTime(W) Then Die('date invalide : ' + Txt);
    End
    Else If (Lw = 'now') Or (Lw = 'today') Then
    Begin
      If Lw = 'today' Then
      Begin
        If Not HaveT Then
        Begin
          PH := 0; PN := 0; PS := 0;
          HaveT := True;
        End;
      End;
    End
    Else If Lw = 'tomorrow' Then
    Begin
      RelDays := RelDays + 1;
      Relative := True;
      If Not HaveT Then
      Begin
        PH := 0; PN := 0; PS := 0;
        HaveT := True;
      End;
    End
    Else If Lw = 'yesterday' Then
    Begin
      RelDays := RelDays - 1;
      Relative := True;
      If Not HaveT Then
      Begin
        PH := 0; PN := 0; PS := 0;
        HaveT := True;
      End;
    End
    Else If Lw = 'noon' Then
    Begin
      PH := 12; PN := 0; PS := 0;
      HaveT := True;
    End
    Else If Lw = 'midnight' Then
    Begin
      PH := 0; PN := 0; PS := 0;
      HaveT := True;
    End
    Else If Lw = 'ago' Then
    Begin
      RelDays := -RelDays;
      RelMonths := -RelMonths;
      RelSecs := -RelSecs;
    End
    Else If (Lw = 'next') Or (Lw = 'last') Or (Lw = 'this') Then
    Begin
      W2 := Tok(Txt, P);
      U := UnitSecs(W2);
      Wd := WeekdayOf(W2);
      If Lw = 'next' Then N := 1 Else If Lw = 'last' Then N := -1 Else N := 0;
      If U <> 0 Then AddRel(N, U)
      Else If Wd >= 0 Then
      Begin
        WantWd := Wd;
        WdMode := N;
        If Not HaveT Then
        Begin
          PH := 0; PN := 0; PS := 0;
          HaveT := True;
        End;
      End
      Else Die('date invalide : ' + Txt);
    End
    Else If WeekdayOf(W) >= 0 Then
    Begin
      WantWd := WeekdayOf(W);
      WdMode := 0;
      If Not HaveT Then
      Begin
        PH := 0; PN := 0; PS := 0;
        HaveT := True;
      End;
    End
    Else If MonthOf(W) > 0 Then
    Begin
      { "June 15, 2024" ou "June 15" ou "June 2024" }
      PM := MonthOf(W);
      If Not HaveD Then PY := Y;
      PD := 1;
      K := P;
      W2 := Tok(Txt, K);
      If IsDigits(W2) Then
      Begin
        N := ToNum(W2);
        If (N >= 1) And (N <= 31) And (Length(W2) <= 2) Then
        Begin
          PD := N;
          P := K;
          W2 := Tok(Txt, K);
          If IsDigits(W2) And (Length(W2) = 4) Then
          Begin
            PY := ToNum(W2);
            P := K;
          End;
        End
        Else If Length(W2) = 4 Then
        Begin
          PY := N;
          P := K;
        End;
      End;
      HaveD := True;
    End
    Else If IsDigits(W) And (Length(W) <= 2) Then
    Begin
      { "15 June 2024" ou "3 days" }
      N := ToNum(W);
      K := P;
      W2 := Tok(Txt, K);
      If MonthOf(W2) > 0 Then
      Begin
        PD := N;
        PM := MonthOf(W2);
        P := K;
        PY := Y;
        W2 := Tok(Txt, K);
        If IsDigits(W2) And (Length(W2) = 4) Then
        Begin
          PY := ToNum(W2);
          P := K;
        End;
        HaveD := True;
      End
      Else If UnitSecs(W2) <> 0 Then
      Begin
        AddRel(N, UnitSecs(W2));
        P := K;
      End
      Else Die('date invalide : ' + Txt);
    End
    Else If (W[1] = '+') Or (W[1] = '-') Then
    Begin
      If NumOff(W, OffSec) And (Pos(':', W) > 0) Then HaveOff := True
      Else
      Begin
        If W[1] = '-' Then N := -ToNum(Copy(W, 2, 9))
        Else N := ToNum(Copy(W, 2, 9));
        W2 := Tok(Txt, P);
        U := UnitSecs(W2);
        If (U = 0) Then
        Begin
          If NumOff(W, OffSec) Then HaveOff := True
          Else Die('date invalide : ' + Txt);
        End
        Else AddRel(N, U);
      End;
    End
    Else If AbbrOff(W, OffSec) Then HaveOff := True
    Else Die('date invalide : ' + Txt);
  End;
End;

{ ---- calcul de l'instant ---- }
Function ResolveIn(Const Txt : String) : LongInt;
Var Y, M, D, H, N, S, Dw, T, Add : LongInt;
Begin
  HaveD := False; HaveT := False; HaveOff := False; HaveEpoch := False;
  Relative := False; RelDays := 0; RelMonths := 0; RelSecs := 0;
  WantWd := -1; WdMode := 0;
  ParseText(Txt);
  If HaveEpoch Then
  Begin
    T := Epoch;
    If RelDays + RelMonths + RelSecs = 0 Then
    Begin
      ResolveIn := T;
      Exit;
    End;
    Base := T;
  End;
  Local(Base, Y, M, D, H, N, S, Dw);
  If HaveD Then
  Begin
    Y := PY; M := PM; D := PD;
    If Not HaveT Then
    Begin
      H := 0; N := 0; S := 0;
    End;
  End;
  If HaveT Then
  Begin
    H := PH; N := PN; S := PS;
  End;
  M := M + RelMonths;
  D := D + RelDays;
  If WantWd >= 0 Then
  Begin
    T := FromLocal(Y, M, D, 0, 0, 0);
    Local(T, Y, M, D, H, N, S, Dw);
    If HaveT Then
    Begin
      H := PH; N := PN; S := PS;
    End;
    Add := (WantWd - Dw + 7) Mod 7;
    If WdMode = 1 Then
    Begin
      If Add = 0 Then Add := 7;
    End
    Else If WdMode = -1 Then
    Begin
      Add := Add - 7;
      If Add = 0 Then Add := -7;
    End;
    D := D + Add;
  End;
  If HaveOff Then
  Begin
    { champs donnes a l'heure du decalage explicite }
    If M > 12 Then
    Begin
      Y := Y + (M - 1) Div 12;
      M := (M - 1) Mod 12 + 1;
    End;
    ResolveIn := LnxDaysFromCivil(Y, M, 1) * 86400 + (D - 1) * 86400 +
                 H * 3600 + N * 60 + S - OffSec + RelSecs;
  End
  Else ResolveIn := FromLocal(Y, M, D, H, N, S) + RelSecs;
End;

{ un TZ="..." du texte ne sert qu'a l'analyse : retour a la zone courante }
Function Resolve(Const Txt : String) : LongInt;
Begin
  Resolve := ResolveIn(Txt);
  If Zone <> '' Then
  Begin
    LnxTzSelect('');
    Zone := '';
  End;
End;

{ ---- mise en forme (strftime) ---- }

Function Pad(V, W : LongInt; Ch : Char) : String;
Var S : String;
Begin
  Str(V, S);
  While Length(S) < W Do S := Ch + S;
  Pad := S;
End;

Function Upper(Const S : String) : String;
Var I : LongInt; R : String;
Begin
  R := S;
  For I := 1 To Length(R) Do
    If (R[I] >= 'a') And (R[I] <= 'z') Then R[I] := Chr(Ord(R[I]) - 32);
  Upper := R;
End;

{ semaine ISO : numero (1..53) et annee }
Procedure IsoWeek(Y, M, D : LongInt; Var Wk, Wy : LongInt);
Var Yd, Wd, W, Dec31 : LongInt;
Begin
  Yd := YDay(Y, M, D);
  Wd := (LnxDaysFromCivil(Y, M, D) + 3) Mod 7;     { lundi = 0 }
  If Wd < 0 Then Wd := Wd + 7;
  W := (Yd - 1 - Wd + 10) Div 7;
  Wy := Y;
  If W < 1 Then
  Begin
    Wy := Y - 1;
    Dec31 := YDay(Wy, 12, 31);
    W := (Dec31 - 1 - ((Wd - Yd + 1 + 7 * 60) Mod 7) + 10) Div 7;
    { recalcul direct pour le 31 decembre de l'annee precedente }
    Wd := (LnxDaysFromCivil(Wy, 12, 31) + 3) Mod 7;
    If Wd < 0 Then Wd := Wd + 7;
    W := (Dec31 - 1 - Wd + 10) Div 7;
  End
  Else If W = 53 Then
  Begin
    { 53 seulement si le 1er janvier suivant n'est pas lundi a jeudi }
    Wd := (LnxDaysFromCivil(Y + 1, 1, 1) + 3) Mod 7;
    If Wd < 0 Then Wd := Wd + 7;
    If Wd <= 3 Then
    Begin
      W := 1;
      Wy := Y + 1;
    End;
  End;
  Wk := W;
End;

Function Fmt(Const F : String; T : LongInt) : String;
Var
  R, Sub, Piece : String;
  I, Y, M, D, H, N, S, Wd, Off, Wk, Wy, V, W : LongInt;
  Flag, C : Char;
  Colon : Boolean;
Begin
  Local(T, Y, M, D, H, N, S, Wd);
  Off := OffAt(T);
  R := '';
  I := 1;
  While I <= Length(F) Do
  Begin
    If F[I] <> '%' Then
    Begin
      R := R + F[I];
      Inc(I);
      Continue;
    End;
    Inc(I);
    If I > Length(F) Then Break;
    Flag := #0;
    Colon := False;
    W := -1;
    While (I <= Length(F)) And ((F[I] = '-') Or (F[I] = '_') Or (F[I] = '0')
          Or (F[I] = '^')) Do
    Begin
      Flag := F[I];
      Inc(I);
    End;
    If (I <= Length(F)) And (F[I] >= '1') And (F[I] <= '9') Then
    Begin
      W := 0;
      While (I <= Length(F)) And (F[I] >= '0') And (F[I] <= '9') Do
      Begin
        W := W * 10 + Ord(F[I]) - 48;
        Inc(I);
      End;
    End;
    If (I <= Length(F)) And (F[I] = ':') Then
    Begin
      Colon := True;
      Inc(I);
    End;
    If I > Length(F) Then Break;
    C := F[I];
    Inc(I);
    Piece := '';
    Case C Of
      '%' : Piece := '%';
      'n' : Piece := #10;
      't' : Piece := #9;
      'a' : Piece := Copy(DayL[Wd], 1, 3);
      'A' : Piece := DayL[Wd];
      'b', 'h' : Piece := Copy(MonL[M], 1, 3);
      'B' : Piece := MonL[M];
      'C' : Piece := Pad(Y Div 100, 2, '0');
      'd' : Piece := Pad(D, 2, '0');
      'e' : Piece := Pad(D, 2, ' ');
      'D' : Piece := Fmt('%m/%d/%y', T);
      'F' : Piece := Fmt('%Y-%m-%d', T);
      'H' : Piece := Pad(H, 2, '0');
      'k' : Piece := Pad(H, 2, ' ');
      'I' :
        Begin
          V := H Mod 12;
          If V = 0 Then V := 12;
          Piece := Pad(V, 2, '0');
        End;
      'l' :
        Begin
          V := H Mod 12;
          If V = 0 Then V := 12;
          Piece := Pad(V, 2, ' ');
        End;
      'j' : Piece := Pad(YDay(Y, M, D), 3, '0');
      'm' : Piece := Pad(M, 2, '0');
      'M' : Piece := Pad(N, 2, '0');
      'N' : Piece := '000000000';
      'p' : If H < 12 Then Piece := 'AM' Else Piece := 'PM';
      'P' : If H < 12 Then Piece := 'am' Else Piece := 'pm';
      'r' : Piece := Fmt('%I:%M:%S %p', T);
      'R' : Piece := Fmt('%H:%M', T);
      's' : Str(T, Piece);
      'S' : Piece := Pad(S, 2, '0');
      'T', 'X' : Piece := Fmt('%H:%M:%S', T);
      'u' : If Wd = 0 Then Piece := '7' Else Piece := Pad(Wd, 1, '0');
      'w' : Piece := Pad(Wd, 1, '0');
      'U' : Piece := Pad((YDay(Y, M, D) - 1 + 7 - Wd) Div 7, 2, '0');
      'W' : Piece := Pad((YDay(Y, M, D) - 1 + 7 - ((Wd + 6) Mod 7)) Div 7, 2,
                         '0');
      'V' :
        Begin
          IsoWeek(Y, M, D, Wk, Wy);
          Piece := Pad(Wk, 2, '0');
        End;
      'G' :
        Begin
          IsoWeek(Y, M, D, Wk, Wy);
          Piece := Pad(Wy, 4, '0');
        End;
      'g' :
        Begin
          IsoWeek(Y, M, D, Wk, Wy);
          Piece := Pad(Wy Mod 100, 2, '0');
        End;
      'y' : Piece := Pad(Y Mod 100, 2, '0');
      'Y' : Str(Y, Piece);
      'x' : Piece := Fmt('%m/%d/%y', T);
      'c' : Piece := Fmt('%a %b %e %H:%M:%S %Y', T);
      'z' :
        Begin
          V := Off;
          If V < 0 Then
          Begin
            Piece := '-';
            V := -V;
          End
          Else Piece := '+';
          Piece := Piece + Pad(V Div 3600, 2, '0');
          If Colon Then Piece := Piece + ':';
          Piece := Piece + Pad((V Mod 3600) Div 60, 2, '0');
        End;
      'Z' :
        Begin
          If UseUtc Then Piece := 'UTC'
          Else
          Begin
            Piece := LnxTzAbbr(T);
            If Piece = '' Then
              If Off = 0 Then Piece := 'UTC'
              Else
              Begin
                V := Off;
                If V < 0 Then
                Begin
                  Piece := '-';
                  V := -V;
                End
                Else Piece := '+';
                Piece := Piece + Pad(V Div 3600, 2, '0');
                If (V Mod 3600) <> 0 Then
                  Piece := Piece + Pad((V Mod 3600) Div 60, 2, '0');
              End;
          End;
        End;
    Else
      Piece := '%' + C;
    End;
    { indicateurs }
    If Flag = '-' Then
      While (Length(Piece) > 1) And ((Piece[1] = '0') Or (Piece[1] = ' ')) Do
        Delete(Piece, 1, 1)
    Else If Flag = '_' Then
    Begin
      V := 1;
      While (V < Length(Piece)) And (Piece[V] = '0') Do
      Begin
        Piece[V] := ' ';
        Inc(V);
      End;
    End
    Else If Flag = '^' Then Piece := Upper(Piece)
    Else If Flag = '0' Then
      While (Length(Piece) > 0) And (Piece[1] = ' ') Do
      Begin
        Piece[1] := '0';
        Break;
      End;
    If W > Length(Piece) Then
      If (C = 'd') Or (C = 'm') Or (C = 'H') Or (C = 'Y') Or (C = 'j') Or
         (C = 'M') Or (C = 'S') Or (C = 'y') Or (C = 's') Then
        While Length(Piece) < W Do Piece := '0' + Piece
      Else
        While Length(Piece) < W Do Piece := ' ' + Piece;
    R := R + Piece;
  End;
  Fmt := R;
End;

Var
  I, Mode, SetT, T : LongInt;
  A, Text, FormatS, Iso : String;
  HaveFmt, DoSet, Rfc : Boolean;
  St : TSysStat;
Begin
  UseUtc := False;
  Zone := '';
  Text := '';
  FormatS := '';
  Iso := '';
  HaveFmt := False;
  DoSet := False;
  Rfc := False;
  Base := SysTime;
  T := 0;
  I := 1;
  While I < SysArgCount Do
  Begin
    A := SysArgStr(I);
    If (A = '-u') Or (A = '--utc') Or (A = '--universal') Then UseUtc := True
    Else If ((A = '-d') Or (A = '--date')) And (I + 1 < SysArgCount) Then
    Begin
      Inc(I);
      Text := SysArgStr(I);
    End
    Else If Copy(A, 1, 7) = '--date=' Then Text := Copy(A, 8, 200)
    Else If ((A = '-s') Or (A = '--set')) And (I + 1 < SysArgCount) Then
    Begin
      Inc(I);
      Text := SysArgStr(I);
      DoSet := True;
    End
    Else If ((A = '-r') Or (A = '--reference')) And (I + 1 < SysArgCount) Then
    Begin
      Inc(I);
      If SysStat(SysArgStr(I), St) <> 0 Then Die(SysArgStr(I) + ' : absent');
      Str(St.MTime, Text);
      Text := '@' + Text;
    End
    Else If (A = '-R') Or (A = '--rfc-email') Or (A = '--rfc-2822') Then
      Rfc := True
    Else If (A = '-I') Or (Copy(A, 1, 2) = '-I') Or
            (Copy(A, 1, 11) = '--iso-8601') Then
    Begin
      Iso := 'date';
      If Copy(A, 1, 2) = '-I' Then
      Begin
        If Length(A) > 2 Then Iso := Copy(A, 3, 20);
      End
      Else If Pos('=', A) > 0 Then Iso := Copy(A, Pos('=', A) + 1, 20);
    End
    Else If (A <> '') And (A[1] = '+') Then
    Begin
      FormatS := Copy(A, 2, 250);
      HaveFmt := True;
    End
    Else Die('option inconnue : ' + A);
    Inc(I);
  End;
  If Not UseUtc Then LnxTzSelect('');
  If Text <> '' Then T := Resolve(Text) Else T := Base;
  If DoSet Then
  Begin
    LnxTmp[0] := T;
    LnxTmp[1] := 0;
    If LnxSys3(79, LongInt(@LnxTmp), 0, 0) < 0 Then
      Die('impossible de regler l''heure');
  End;
  If Rfc Then FormatS := '%a, %d %b %Y %H:%M:%S %z'
  Else If Iso <> '' Then
  Begin
    If Iso = 'date' Then FormatS := '%F'
    Else If Iso = 'hours' Then FormatS := '%FT%H%:z'
    Else If Iso = 'minutes' Then FormatS := '%FT%H:%M%:z'
    Else If Iso = 'seconds' Then FormatS := '%FT%T%:z'
    Else Die('argument invalide pour -I : ' + Iso);
  End
  Else If Not HaveFmt Then FormatS := '%a %b %e %H:%M:%S %Z %Y';
  SysPut(1, Fmt(FormatS, T) + #10);
End.
