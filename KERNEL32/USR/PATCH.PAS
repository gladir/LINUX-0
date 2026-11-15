{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2026
  @website(https://www.gladir.com/linux-0)
  @abstract(Target: LPC -3X)
  @description: /bin/patch : applique une difference (formats unifie, de
      contexte et normal). patch [-pN] [-R] [-N] [-b] [-s] [-F N]
      [--dry-run] [-d dir] [-i fichier] [-o sortie] [fichier]. Position des
      blocs corrigee par decalage, tolerance (fuzz) de 0 a 2 lignes de
      contexte, blocs refuses ecrits dans fichier.rej, creation et
      suppression de fichiers (/dev/null), detection d'un patch deja
      applique. Limites : lignes de 255 octets, 20000 lignes par fichier,
      30000 lignes de patch.
}

Program PATCH;

Const
  MaxF = 20000;
  MaxP = 30000;
  MaxH = 1500;
  Usage : Array[1..5] Of PChar = (
    'Usage : patch [-pN] [-R] [-N] [-b] [-s] [-i fichier] [cible]',
    'Usage: patch [-pN] [-R] [-N] [-b] [-s] [-i patch] [file]',
    'Aufruf: patch [-pN] [-R] [-N] [-b] [-s] [-i Patch] [Datei]',
    'Uso: patch [-pN] [-R] [-N] [-b] [-s] [-i parche] [archivo]',
    'Uso: patch [-pN] [-R] [-N] [-b] [-s] [-i patch] [file]');

Var
  PL : Array[1..MaxP] Of String;
  NP : LongInt;
  FL : Array[1..MaxF] Of String;
  NF : LongInt;
  HT : Array[1..MaxH] Of Char;
  HS : Array[1..MaxH] Of String;
  NH : LongInt;
  HOld, HNew : LongInt;       { debuts annonces (ancien, nouveau) }
  PStrip, MaxFuzz : LongInt;
  Rev, Forward_, Backup, Quiet, DryRun : Boolean;
  PatchFile, OutFile, ArgFile, Dir : String;
  Lang : LongInt;
  Failed : LongInt;
  Rej : String;
  RejN : LongInt;
  FileMissing : Boolean;

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

Procedure Say(Const S : String);
Begin
  If Not Quiet Then SysPut(1, S + #10);
End;

Procedure Die(Const S : String);
Begin
  SysPut(2, 'patch: **** ' + S + #10);
  SysExit(2);
End;

Function StartsWith(Const S, P : String) : Boolean;
Begin
  StartsWith := Copy(S, 1, Length(P)) = P;
End;

Function Num(Const S : String; Var P : LongInt) : LongInt;
Var V : LongInt;
Begin
  V := 0;
  While (P <= Length(S)) And (S[P] >= '0') And (S[P] <= '9') Do
  Begin
    V := V * 10 + Ord(S[P]) - 48;
    Inc(P);
  End;
  Num := V;
End;

{ ---------- lecture ---------- }

Function ReadLines(Fd : LongInt; Var Dst : Array Of String; Max : LongInt)
  : LongInt;
Var N, Cnt : LongInt; B : Byte; Ln : String; Got : Boolean;
Begin
  Cnt := 0;
  Ln := '';
  Got := False;
  While True Do
  Begin
    N := SysRead(Fd, B, 1);
    If N <= 0 Then Break;
    Got := True;
    If B = 10 Then
    Begin
      If Cnt < Max Then
      Begin
        Dst[Cnt] := Ln;
        Inc(Cnt);
      End;
      Ln := '';
      Got := False;
    End
    Else If B <> 13 Then
    Begin
      If Length(Ln) < 255 Then Ln := Ln + Chr(B);
    End
    Else If Length(Ln) < 255 Then Ln := Ln + Chr(B);
  End;
  If Got And (Cnt < Max) Then
  Begin
    Dst[Cnt] := Ln;
    Inc(Cnt);
  End;
  ReadLines := Cnt;
End;

Function LoadFile(Const Name : String) : Boolean;
Var Fd : LongInt;
Begin
  LoadFile := False;
  NF := 0;
  Fd := SysOpen(Name, O_RDONLY, 0);
  If Fd < 0 Then Exit;
  NF := ReadLines(Fd, FL, MaxF);
  SysClose(Fd);
  LoadFile := True;
End;

Function SaveFile(Const Name : String) : Boolean;
Var Fd, I : LongInt; Buf : String;
Begin
  SaveFile := False;
  Fd := SysOpen(Name, O_WRONLY Or O_CREAT Or O_TRUNC, 420);
  If Fd < 0 Then Exit;
  For I := 1 To NF Do
    If SysPut(Fd, FL[I] + #10) < 0 Then
    Begin
      SysClose(Fd);
      Exit;
    End;
  SysClose(Fd);
  SaveFile := True;
End;

{ ---------- noms de fichiers ---------- }

Function StripName(Const S : String) : String;
Var T : String; K, N : LongInt;
Begin
  T := S;
  { couper a la tabulation ou a l'espace suivi d'une date }
  K := Pos(#9, T);
  If K > 0 Then T := Copy(T, 1, K - 1);
  While (Length(T) > 0) And (T[Length(T)] = ' ') Do Delete(T, Length(T), 1);
  If (Length(T) > 1) And (T[1] = '"') Then
    T := Copy(T, 2, Length(T) - 2);
  N := PStrip;
  While N > 0 Do
  Begin
    K := Pos('/', T);
    If K = 0 Then Break;
    T := Copy(T, K + 1, 255);
    While (Length(T) > 0) And (T[1] = '/') Do Delete(T, 1, 1);
    Dec(N);
  End;
  StripName := T;
End;

Function Exists(Const P : String) : Boolean;
Var St : TSysStat;
Begin
  Exists := SysStat(P, St) = 0;
End;

{ ---------- analyse d'un bloc ---------- }

Procedure AddH(C : Char; Const S : String);
Begin
  If NH < MaxH Then
  Begin
    Inc(NH);
    HT[NH] := C;
    HS[NH] := S;
  End;
End;

{ Fin de l'en-tete du bloc ; I = ligne courante, retourne la suivante }
Function ParseUnified(I : LongInt) : LongInt;
Var
  S : String;
  P, OC, NC, O, Nn : LongInt;
Begin
  S := PL[I];
  P := 5;
  HOld := Num(S, P);
  OC := 1;
  If (P <= Length(S)) And (S[P] = ',') Then
  Begin
    Inc(P);
    OC := Num(S, P);
  End;
  While (P <= Length(S)) And ((S[P] = ' ') Or (S[P] = '+')) Do Inc(P);
  HNew := Num(S, P);
  NC := 1;
  If (P <= Length(S)) And (S[P] = ',') Then
  Begin
    Inc(P);
    NC := Num(S, P);
  End;
  { bloc sans ligne d'un cote : la position est celle de la ligne precedente }
  If OC = 0 Then Inc(HOld);
  If NC = 0 Then Inc(HNew);
  NH := 0;
  O := 0;
  Nn := 0;
  Inc(I);
  While (I <= NP) And ((O < OC) Or (Nn < NC)) Do
  Begin
    S := PL[I];
    If StartsWith(S, '\') Then
    Begin
      Inc(I);
      Continue;
    End;
    If S = '' Then S := ' ';
    Case S[1] Of
      ' ' : Begin AddH(' ', Copy(S, 2, 255)); Inc(O); Inc(Nn); End;
      '-' : Begin AddH('-', Copy(S, 2, 255)); Inc(O); End;
      '+' : Begin AddH('+', Copy(S, 2, 255)); Inc(Nn); End;
    Else Break;
    End;
    Inc(I);
  End;
  While (I <= NP) And StartsWith(PL[I], '\') Do Inc(I);
  ParseUnified := I;
End;

Function ParseContext(I : LongInt) : LongInt;
Var
  S : String;
  P, OC, K, J : LongInt;
  OT : Array[1..MaxH] Of Char;
  OS_ : Array[1..MaxH] Of String;
  NT : Array[1..MaxH] Of Char;
  NS : Array[1..MaxH] Of String;
  NO, NN, A, B : LongInt;
  HaveNew : Boolean;
Begin
  { PL[I] = '*** a,b ****' }
  S := PL[I];
  P := 5;
  HOld := Num(S, P);
  OC := 1;
  If (P <= Length(S)) And (S[P] = ',') Then
  Begin
    Inc(P);
    OC := Num(S, P) - HOld + 1;
  End
  Else OC := 1;
  NO := 0;
  NN := 0;
  Inc(I);
  While (I <= NP) And Not StartsWith(PL[I], '--- ') Do
  Begin
    S := PL[I];
    If StartsWith(S, '\') Then Begin Inc(I); Continue; End;
    If StartsWith(S, '***') Then Break;
    If Length(S) >= 2 Then
    Begin
      Inc(NO);
      If NO <= MaxH Then
      Begin
        OT[NO] := S[1];
        OS_[NO] := Copy(S, 3, 255);
      End;
    End
    Else If Length(S) = 1 Then
    Begin
      Inc(NO);
      If NO <= MaxH Then
      Begin
        OT[NO] := S[1];
        OS_[NO] := '';
      End;
    End;
    Inc(I);
  End;
  { section nouvelle : --- c,d ---- }
  HaveNew := False;
  If (I <= NP) And StartsWith(PL[I], '--- ') Then
  Begin
    S := PL[I];
    P := 5;
    HNew := Num(S, P);
    Inc(I);
    HaveNew := True;
    While (I <= NP) And Not StartsWith(PL[I], '***************') Do
    Begin
      S := PL[I];
      If StartsWith(S, '\') Then Begin Inc(I); Continue; End;
      If Length(S) >= 1 Then
      Begin
        Inc(NN);
        If NN <= MaxH Then
        Begin
          NT[NN] := S[1];
          NS[NN] := Copy(S, 3, 255);
        End;
      End;
      Inc(I);
    End;
  End;
  { section nouvelle absente (suppressions seules) : l'ancienne fait foi }
  If NN = 0 Then HaveNew := False;
  { fusion : sans section ancienne marquee (aucune ligne - ou !), la
    section nouvelle fait foi pour les ajouts ; sinon parcours parallele }
  NH := 0;
  A := 1;
  B := 1;
  If Not HaveNew Then
  Begin
    For K := 1 To NO Do
      If OT[K] = ' ' Then AddH(' ', OS_[K]) Else AddH('-', OS_[K]);
  End
  Else If NO = 0 Then
  Begin
    { section ancienne absente (ajouts seuls) : tout vient de la nouvelle }
    For K := 1 To NN Do
      If NT[K] = '+' Then AddH('+', NS[K]) Else AddH(' ', NS[K]);
  End
  Else
  Begin
    While (A <= NO) Or (B <= NN) Do
    Begin
      If (A <= NO) And (OT[A] = ' ') And (B <= NN) And (NT[B] = ' ') Then
      Begin
        AddH(' ', OS_[A]);
        Inc(A);
        Inc(B);
      End
      Else
      Begin
        K := A + B;
        While (A <= NO) And ((OT[A] = '-') Or (OT[A] = '!')) Do
        Begin
          AddH('-', OS_[A]);
          Inc(A);
        End;
        While (B <= NN) And ((NT[B] = '+') Or (NT[B] = '!')) Do
        Begin
          AddH('+', NS[B]);
          Inc(B);
        End;
        If K = A + B Then
        Begin
          { aucun progres : contextes disparates }
          If A <= NO Then Inc(A);
          If B <= NN Then Inc(B);
        End;
      End;
    End;
  End;
  ParseContext := I;
End;

{ diff normal : N[,M](a|d|c)N[,M] }
Function ParseNormal(I : LongInt) : LongInt;
Var S : String; P, A1, A2, B1, B2 : LongInt; C : Char;
Begin
  S := PL[I];
  P := 1;
  A1 := Num(S, P);
  A2 := A1;
  If S[P] = ',' Then
  Begin
    Inc(P);
    A2 := Num(S, P);
  End;
  C := S[P];
  Inc(P);
  B1 := Num(S, P);
  B2 := B1;
  If (P <= Length(S)) And (S[P] = ',') Then
  Begin
    Inc(P);
    B2 := Num(S, P);
  End;
  NH := 0;
  Inc(I);
  HOld := A1;
  HNew := B1;
  If C = 'a' Then HOld := A1 + 1;
  If C = 'd' Then HNew := B1 + 1;
  While (I <= NP) And StartsWith(PL[I], '< ') Do
  Begin
    AddH('-', Copy(PL[I], 3, 255));
    Inc(I);
  End;
  If (I <= NP) And (PL[I] = '---') Then Inc(I);
  While (I <= NP) And StartsWith(PL[I], '> ') Do
  Begin
    AddH('+', Copy(PL[I], 3, 255));
    Inc(I);
  End;
  While (I <= NP) And StartsWith(PL[I], '\') Do Inc(I);
  ParseNormal := I;
End;

{ ---------- application ---------- }

Function SameLine(Const A, B : String; Fuzz : LongInt) : Boolean;
Var X, Y : String;
Begin
  If A = B Then
  Begin
    SameLine := True;
    Exit;
  End;
  If Fuzz = 0 Then
  Begin
    SameLine := False;
    Exit;
  End;
  X := A;
  Y := B;
  While (Length(X) > 0) And (X[Length(X)] In [' ', #9, #13]) Do
    Delete(X, Length(X), 1);
  While (Length(Y) > 0) And (Y[Length(Y)] In [' ', #9, #13]) Do
    Delete(Y, Length(Y), 1);
  SameLine := X = Y;
End;

{ cherche le bloc (cote ancien) dans FL : position de la premiere ligne du
  bloc complet ; tolerance Fuzz ; Want = position attendue ; -1 si absent }
Function Locate(Want, Fuzz : LongInt; Reverse : Boolean) : LongInt;
Var
  First, Last, Pre, Post, K, N, S0, S1, Off, P, Sk, Total, M : LongInt;
  Ok : Boolean;
  Ty : Char;
Begin
  Locate := -1;
  Total := 0;
  For K := 1 To NH Do
  Begin
    Ty := HT[K];
    If Reverse Then
    Begin
      If Ty = '+' Then Ty := '-' Else If Ty = '-' Then Ty := '+';
    End;
    If Ty <> '+' Then Inc(Total);
  End;
  { contexte de tete et de queue (ligne anciennes) }
  Pre := 0;
  K := 1;
  While (K <= NH) And (HT[K] = ' ') Do
  Begin
    Inc(Pre);
    Inc(K);
  End;
  Post := 0;
  K := NH;
  While (K >= 1) And (HT[K] = ' ') Do
  Begin
    Inc(Post);
    Dec(K);
  End;
  If Pre = NH Then Post := 0;
  Sk := Fuzz;
  If Sk > Pre Then Sk := Pre;
  S0 := Sk;
  Sk := Fuzz;
  If Sk > Post Then Sk := Post;
  S1 := Sk;
  If Total = 0 Then
  Begin
    { insertion pure : position donnee }
    Locate := Want;
    Exit;
  End;
  For Off := 0 To NF + 1 Do
  Begin
    For M := 0 To 1 Do
    Begin
      If (M = 1) And (Off = 0) Then Continue;
      If M = 0 Then P := Want + Off Else P := Want - Off;
      If (P < 1) Or (P > NF + 1) Then Continue;
      { P = position de la premiere ligne ancienne du bloc complet }
      Ok := True;
      N := 0;
      K := 0;
      While Ok And (K < NH) Do
      Begin
        Inc(K);
        Ty := HT[K];
        If Reverse Then
        Begin
          If Ty = '+' Then Ty := '-' Else If Ty = '-' Then Ty := '+';
        End;
        If Ty = '+' Then Continue;
        Inc(N);
        { ligne ignoree par la tolerance ? }
        If (N <= S0) Or (Total - N < S1) Then Continue;
        If (P + N - 1 > NF) Or (Not SameLine(FL[P + N - 1], HS[K], Fuzz)) Then
          Ok := False;
      End;
      If Ok Then
      Begin
        Locate := P;
        Exit;
      End;
    End;
  End;
End;

Procedure Apply(P : LongInt; Reverse : Boolean);
Var K, N, I, Del, Pos0 : LongInt; Ty : Char;
    NewL : Array[1..MaxH] Of String;
    NN : LongInt;
Begin
  { remplace les lignes anciennes [P .. P+Del-1] par les nouvelles }
  Del := 0;
  NN := 0;
  For K := 1 To NH Do
  Begin
    Ty := HT[K];
    If Reverse Then
    Begin
      If Ty = '+' Then Ty := '-' Else If Ty = '-' Then Ty := '+';
    End;
    If Ty <> '+' Then Inc(Del);
    If Ty <> '-' Then
    Begin
      Inc(NN);
      NewL[NN] := HS[K];
    End;
  End;
  If NN <> Del Then
  Begin
    If NN > Del Then
    Begin
      For I := NF DownTo P + Del Do
        If I + (NN - Del) <= MaxF Then FL[I + (NN - Del)] := FL[I];
    End
    Else
      For I := P + Del To NF Do FL[I - (Del - NN)] := FL[I];
    NF := NF + NN - Del;
  End;
  For K := 1 To NN Do FL[P + K - 1] := NewL[K];
End;

Procedure RejectHunk(Num_ : LongInt; OldS, NewS : LongInt);
Var K : LongInt;
Begin
  If RejN = 0 Then Rej := '';
  Inc(RejN);
  Rej := Rej + '@@ -' + NumS(OldS) + ' +' + NumS(NewS) + ' @@' + #10;
  For K := 1 To NH Do Rej := Rej + HT[K] + HS[K] + #10;
End;

Var
  RejBuf : Array[1..1] Of String;
  RejFd : LongInt;

Procedure WriteRej(Const Name : String);
Var Fd : LongInt;
Begin
  If RejN = 0 Then Exit;
  Fd := SysOpen(Name + '.rej', O_WRONLY Or O_CREAT Or O_TRUNC, 420);
  If Fd >= 0 Then
  Begin
    SysPut(Fd, '--- ' + Name + #10 + '+++ ' + Name + #10);
    SysPut(Fd, Rej);
    SysClose(Fd);
  End;
End;

{ applique le bloc courant ; retourne vrai si reussi }
Function DoHunk(Idx : LongInt; Var Delta : LongInt;
                Reverse : Boolean) : Boolean;
Var Want, P, F, Off : LongInt; Os, Ns : LongInt;
Begin
  If Reverse Then
  Begin
    Os := HNew;
    Ns := HOld;
  End
  Else
  Begin
    Os := HOld;
    Ns := HNew;
  End;
  If Os < 1 Then Os := 1;
  Want := Os + Delta;
  P := -1;
  For F := 0 To MaxFuzz Do
  Begin
    P := Locate(Want, F, Reverse);
    If P >= 0 Then Break;
  End;
  If P < 0 Then
  Begin
    DoHunk := False;
    Exit;
  End;
  Off := P - Want;
  If (F > 0) Or (Off <> 0) Then
  Begin
    If F > 0 Then
      Say('Hunk #' + NumS(Idx) + ' succeeded at ' + NumS(P) + ' with fuzz ' +
          NumS(F) + '.')
    Else If Off <> 0 Then
      Say('Hunk #' + NumS(Idx) + ' succeeded at ' + NumS(P) + ' (offset ' +
          NumS(Off) + ' line' + Copy('s', 1, Ord(Abs(Off) <> 1)) + ').');
  End;
  If Not DryRun Then Apply(P, Reverse);
  { decalage cumule pour les blocs suivants (positions de l'original) }
  Delta := P - Os;
  If Not DryRun Then
    For F := 1 To NH Do
    Begin
      If (HT[F] = '+') Xor Reverse Then Inc(Delta)
      Else If HT[F] <> ' ' Then Dec(Delta);
    End;
  DoHunk := True;
End;

{ ---------- fichier ---------- }

Procedure PatchOne(Const OldN, NewN : String; Start, Stop : LongInt;
                   Fmt : Char);
Var
  Target : String;
  I, NHunk, Failed1, Delta, Ok : LongInt;
  Created, Deleted, Try : Boolean;
  Reversed : Boolean;
Begin
  If ArgFile <> '' Then Target := ArgFile
  Else
  Begin
    Target := StripName(NewN);
    If (Not Exists(Target)) And (StripName(OldN) <> '/dev/null') And
       (Pos('/dev/null', OldN) <> 1) Then
      If Exists(StripName(OldN)) Then Target := StripName(OldN);
  End;
  Created := False;
  If Exists(Target) Then LoadFile(Target)
  Else
  Begin
    NF := 0;
    Created := True;
  End;
  Say('patching file ' + Target);
  NHunk := 0;
  Failed1 := 0;
  Delta := 0;
  RejN := 0;
  Reversed := Rev;
  I := Start;
  While I <= Stop Do
  Begin
    If (Fmt = 'u') And StartsWith(PL[I], '@@ -') Then I := ParseUnified(I)
    Else If (Fmt = 'c') And StartsWith(PL[I], '*** ') And
            (Pos('****', PL[I]) > 0) Then I := ParseContext(I)
    Else If (Fmt = 'n') And (PL[I] <> '') And (PL[I][1] >= '0') And
            (PL[I][1] <= '9') Then I := ParseNormal(I)
    Else
    Begin
      Inc(I);
      Continue;
    End;
    Inc(NHunk);
    If (NHunk = 1) And (Not Rev) And (Not Forward_) And (NH > 0) Then
    Begin
      { patch deja applique (ou inverse) ? }
      Try := DoHunk(1, Delta, False);
      If Not Try Then
      Begin
        Delta := 0;
        If (Locate(HNew, 0, True) >= 0) Then
        Begin
          SysPut(2, 'Reversed (or previously applied) patch detected!  ' +
                 'Skipping patch.' + #10);
          Inc(Failed);
          Exit;
        End;
        RejectHunk(1, HOld, HNew);
        Inc(Failed1);
        SysPut(1, 'Hunk #1 FAILED at ' + NumS(HOld) + '.' + #10);
      End
      Else If Not DryRun Then ;
      Continue;
    End;
    If DoHunk(NHunk, Delta, Reversed) Then
    Else
    Begin
      RejectHunk(NHunk, HOld, HNew);
      Inc(Failed1);
      SysPut(1, 'Hunk #' + NumS(NHunk) + ' FAILED at ' + NumS(HOld) + '.' +
             #10);
    End;
  End;
  If Failed1 > 0 Then
  Begin
    Inc(Failed);
    If Not DryRun Then WriteRej(Target);
    SysPut(1, NumS(Failed1) + ' out of ' + NumS(NHunk) + ' hunk' +
           Copy('s', 1, Ord(NHunk <> 1)) + ' FAILED -- saving rejects to ' +
           'file ' +
           Target + '.rej' + #10);
  End;
  If DryRun Then Exit;
  Deleted := (NF = 0) And (Pos('/dev/null', NewN) = 1) And (Not Created);
  If Deleted Then
  Begin
    SysUnlink(Target);
    Exit;
  End;
  If Backup And (Not Created) And Exists(Target) Then
    SysRename(Target, Target + '.orig');
  If OutFile <> '' Then Target := OutFile;
  If NHunk - Failed1 > 0 Then
    If Not SaveFile(Target) Then
    Begin
      SysPut(2, 'patch: ' + Target + ': ' + SysErrorText(SysErrno) + #10);
      Inc(Failed);
    End;
End;

{ ---------- programme ---------- }

Var
  I, J, K, Fd, SecStart : LongInt;
  A, OldN, NewN : String;
  Fmt : Char;
  Starts : Array[1..64] Of LongInt;
  Fmts : Array[1..64] Of Char;
  Olds, News : Array[1..64] Of String;
  NSec : LongInt;
BEGIN
  Lang := SysLang;
  If (Lang < 1) Or (Lang > 5) Then Lang := 1;
  PStrip := 0;
  MaxFuzz := 2;
  I := 1;
  While I < SysArgCount Do
  Begin
    A := SysArgStr(I);
    If (A = '--help') Or (A = '/?') Then
    Begin
      SysPut(1, PS(Usage[Lang]) + #10);
      SysExit(0);
    End
    Else If (Length(A) >= 2) And (Copy(A, 1, 2) = '-p') Then
    Begin
      If Length(A) > 2 Then Val(Copy(A, 3, 255), PStrip, J)
      Else
      Begin
        Inc(I);
        If I < SysArgCount Then Val(SysArgStr(I), PStrip, J);
      End;
    End
    Else If (A = '-R') Or (A = '--reverse') Then Rev := True
    Else If (A = '-N') Or (A = '--forward') Then Forward_ := True
    Else If (A = '-b') Or (A = '--backup') Then Backup := True
    Else If (A = '-s') Or (A = '--silent') Or (A = '--quiet') Then Quiet := True
    Else If A = '--dry-run' Then DryRun := True
    Else If Copy(A, 1, 2) = '-F' Then
    Begin
      If Length(A) > 2 Then Val(Copy(A, 3, 255), MaxFuzz, J)
      Else
      Begin
        Inc(I);
        If I < SysArgCount Then Val(SysArgStr(I), MaxFuzz, J);
      End;
    End
    Else If (A = '-i') Or (A = '--input') Then
    Begin
      Inc(I);
      If I < SysArgCount Then PatchFile := SysArgStr(I);
    End
    Else If A = '-o' Then
    Begin
      Inc(I);
      If I < SysArgCount Then OutFile := SysArgStr(I);
    End
    Else If A = '-d' Then
    Begin
      Inc(I);
      If I < SysArgCount Then Dir := SysArgStr(I);
    End
    Else If A = '-u' Then
    Else If (A <> '') And (A[1] <> '-') Then
    Begin
      If ArgFile = '' Then ArgFile := A
      Else If PatchFile = '' Then PatchFile := A;
    End;
    Inc(I);
  End;
  If Dir <> '' Then SysChdir(Dir);
  If PatchFile = '' Then Fd := 0 Else Fd := SysOpen(PatchFile, O_RDONLY, 0);
  If Fd < 0 Then Die(PatchFile + ': ' + SysErrorText(SysErrno));
  NP := ReadLines(Fd, PL, MaxP);
  If Fd > 0 Then SysClose(Fd);
  { reperer les sections de fichiers }
  NSec := 0;
  I := 1;
  While I <= NP Do
  Begin
    If StartsWith(PL[I], '--- ') And (I < NP) And StartsWith(PL[I + 1], '+++ ')
       And (I + 2 <= NP) And StartsWith(PL[I + 2], '@@ ') Then
    Begin
      Inc(NSec);
      If NSec > 64 Then Die('too many files');
      Starts[NSec] := I + 2;
      Fmts[NSec] := 'u';
      Olds[NSec] := Copy(PL[I], 5, 255);
      News[NSec] := Copy(PL[I + 1], 5, 255);
      I := I + 2;
    End
    Else If StartsWith(PL[I], '*** ') And (I < NP) And
            StartsWith(PL[I + 1], '--- ') And (I + 2 <= NP) And
            StartsWith(PL[I + 2], '***************') Then
    Begin
      Inc(NSec);
      If NSec > 64 Then Die('too many files');
      Starts[NSec] := I + 3;
      Fmts[NSec] := 'c';
      Olds[NSec] := Copy(PL[I], 5, 255);
      News[NSec] := Copy(PL[I + 1], 5, 255);
      I := I + 2;
    End
    Else If (NSec = 0) And (PL[I] <> '') And (PL[I][1] >= '0') And
            (PL[I][1] <= '9') And
            ((Pos('a', PL[I]) > 0) Or (Pos('c', PL[I]) > 0) Or
             (Pos('d', PL[I]) > 0)) Then
    Begin
      Inc(NSec);
      Starts[NSec] := I;
      Fmts[NSec] := 'n';
      Olds[NSec] := ArgFile;
      News[NSec] := ArgFile;
    End;
    Inc(I);
  End;
  If NSec = 0 Then Die('Only garbage was found in the patch input.');
  For K := 1 To NSec Do
  Begin
    If K < NSec Then SecStart := Starts[K + 1] - 1 Else SecStart := NP;
    If (Fmts[K] <> 'n') And (K < NSec) Then SecStart := Starts[K + 1] - 3;
    If SecStart < Starts[K] Then SecStart := NP;
    If (Fmts[K] = 'n') And (ArgFile = '') Then Die('no file to patch');
    PatchOne(Olds[K], News[K], Starts[K], SecStart, Fmts[K]);
  End;
  If Failed > 0 Then SysExit(1);
END.
