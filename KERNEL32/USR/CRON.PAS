{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2026
  @website(https://www.gladir.com/linux-0)
  @abstract(Target: LPC -3X)
  @description: crond (cron), crontab, at, atd, batch, atq, atrm (un seul
      programme, nom lu dans argv[0]). crond execute chaque minute les
      entrees de /etc/crontab, /etc/cron.d/* et /var/spool/cron/crontabs/*
      (champs min heure jour mois jour-semaine, listes, intervalles, pas,
      noms de mois et de jours, @reboot @hourly @daily @weekly @monthly
      @yearly, VAR=valeur, % = fin de commande / entree standard). La
      sortie des travaux est ajoutee a /var/log/cron.out. crontab : -l -e -r
      -u utilisateur fichier|-. at : [-f fichier] [-q f] [-m] heure [date]
      [+ N minutes|hours|days|weeks] ; atd execute les travaux de
      /var/spool/cron/atjobs ; batch : travail lance quand la charge est
      inferieure a 1,5. atq liste, atrm supprime.
}

Program CRON;

Const
  MaxEnt = 300;
  CronDir = '/var/spool/cron/crontabs';
  AtDir = '/var/spool/cron/atjobs';
  Months : Array[1..12] Of String[3] =
    ('jan', 'feb', 'mar', 'apr', 'may', 'jun', 'jul', 'aug', 'sep', 'oct',
     'nov', 'dec');
  Days : Array[0..6] Of String[3] =
    ('sun', 'mon', 'tue', 'wed', 'thu', 'fri', 'sat');
  Usage : Array[1..5] Of PChar = (
    'Usage : crontab [-u utilisateur] (-l | -e | -r | fichier)',
    'Usage: crontab [-u user] (-l | -e | -r | file)',
    'Aufruf: crontab [-u Benutzer] (-l | -e | -r | Datei)',
    'Uso: crontab [-u usuario] (-l | -e | -r | archivo)',
    'Uso: crontab [-u utente] (-l | -e | -r | file)');
  UsageAt : Array[1..5] Of PChar = (
    'Usage : at [-f fichier] [-m] heure [date] [+ N unites]',
    'Usage: at [-f file] [-m] time [date] [+ N units]',
    'Aufruf: at [-f Datei] [-m] Zeit [Datum] [+ N Einheiten]',
    'Uso: at [-f archivo] [-m] hora [fecha] [+ N unidades]',
    'Uso: at [-f file] [-m] ora [data] [+ N unita]');

Type
  TEnt = Record
    Mi : Array[0..59] Of Boolean;
    Hr : Array[0..23] Of Boolean;
    Dm : Array[1..31] Of Boolean;
    Mo : Array[1..12] Of Boolean;
    Dw : Array[0..6] Of Boolean;
    DmStar, DwStar, Reboot : Boolean;
    User : String[32];
    Cmd : String;
    EnvN : LongInt;
    EnvAt : LongInt;      { premiere variable VAR=valeur du fichier }
  End;

Var
  Ents : Array[1..MaxEnt] Of TEnt;
  NEnt : LongInt;
  Lang : LongInt;
  Prog : String;
  Foreground : Boolean;
  ErrMsg : String;
  Vars : Array[1..64] Of String;
  NVars : LongInt;

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

Function Lower(Const S : String) : String;
Var K : LongInt; R : String;
Begin
  R := S;
  For K := 1 To Length(R) Do
    If (R[K] >= 'A') And (R[K] <= 'Z') Then R[K] := Chr(Ord(R[K]) + 32);
  Lower := R;
End;

Function Trim(Const S : String) : String;
Var A, B : LongInt;
Begin
  A := 1;
  B := Length(S);
  While (A <= B) And ((S[A] = ' ') Or (S[A] = #9)) Do Inc(A);
  While (B >= A) And ((S[B] = ' ') Or (S[B] = #9) Or (S[B] = #13)) Do Dec(B);
  Trim := Copy(S, A, B - A + 1);
End;

{ ---------------- calendrier ---------------- }

Function DaysFromCivil(Y, M, D : LongInt) : LongInt;
Var Era, Yoe, Doy, Doe : LongInt;
Begin
  If M <= 2 Then Y := Y - 1;
  If Y >= 0 Then Era := Y Div 400 Else Era := (Y - 399) Div 400;
  Yoe := Y - Era * 400;
  If M > 2 Then Doy := (153 * (M - 3) + 2) Div 5 + D - 1
  Else Doy := (153 * (M + 9) + 2) Div 5 + D - 1;
  Doe := Yoe * 365 + Yoe Div 4 - Yoe Div 100 + Doy;
  DaysFromCivil := Era * 146097 + Doe - 719468;
End;

Procedure CivilFromDays(Z : LongInt; Var Y, M, D : LongInt);
Var Era, Doe, Yoe, Doy, Mp : LongInt;
Begin
  Z := Z + 719468;
  If Z >= 0 Then Era := Z Div 146097 Else Era := (Z - 146096) Div 146097;
  Doe := Z - Era * 146097;
  Yoe := (Doe - Doe Div 1460 + Doe Div 36524 - Doe Div 146096) Div 365;
  Y := Yoe + Era * 400;
  Doy := Doe - (365 * Yoe + Yoe Div 4 - Yoe Div 100);
  Mp := (5 * Doy + 2) Div 153;
  D := Doy - (153 * Mp + 2) Div 5 + 1;
  If Mp < 10 Then M := Mp + 3 Else M := Mp - 9;
  If M <= 2 Then Y := Y + 1;
End;

{ T = secondes locales depuis 1970 }
Procedure Break_(T : LongInt; Var Y, Mo, D, H, Mi, Wd : LongInt);
Var Dd : LongInt;
Begin
  Dd := T Div 86400;
  H := (T Mod 86400) Div 3600;
  Mi := (T Mod 3600) Div 60;
  CivilFromDays(Dd, Y, Mo, D);
  Wd := (Dd + 4) Mod 7;
  If Wd < 0 Then Wd := Wd + 7;
End;

Function Pad2(V : LongInt) : String;
Begin
  If V < 10 Then Pad2 := '0' + NumS(V) Else Pad2 := NumS(V);
End;

Function StampS(T : LongInt) : String;
Var Y, Mo, D, H, Mi, Wd : LongInt;
Begin
  Break_(T + LnxTz, Y, Mo, D, H, Mi, Wd);
  StampS := Chr(Ord(Days[Wd][1]) - 32) + Copy(Days[Wd], 2, 2) + ' ' +
            Chr(Ord(Months[Mo][1]) - 32) + Copy(Months[Mo], 2, 2) + ' ' +
            Pad2(D) + ' ' + Pad2(H) + ':' + Pad2(Mi) + ' ' + NumS(Y);
End;

{ ---------------- fichiers ---------------- }

Function ReadAll(Const Path : String; Var Lines : Array Of String;
                 Max : LongInt) : LongInt;
Var Fd, N, Cnt : LongInt; B : Byte; Ln : String;
Begin
  ReadAll := -1;
  Fd := SysOpen(Path, O_RDONLY, 0);
  If Fd < 0 Then Exit;
  Cnt := 0;
  Ln := '';
  While True Do
  Begin
    N := SysRead(Fd, B, 1);
    If (N <= 0) Or (B = 10) Then
    Begin
      If (N > 0) Or (Ln <> '') Then
        If Cnt < Max Then
        Begin
          Lines[Cnt] := Ln;
          Inc(Cnt);
        End;
      Ln := '';
      If N <= 0 Then Break;
    End
    Else If Length(Ln) < 250 Then Ln := Ln + Chr(B);
  End;
  SysClose(Fd);
  ReadAll := Cnt;
End;

Function WriteStr(Const Path, S : String; Mode : LongInt) : Boolean;
Var Fd : LongInt;
Begin
  Fd := SysOpen(Path, O_WRONLY Or O_CREAT Or O_TRUNC, Mode);
  WriteStr := False;
  If Fd < 0 Then Exit;
  SysPut(Fd, S);
  SysClose(Fd);
  WriteStr := True;
End;

Procedure LogLine(Const S : String);
Var Fd : LongInt;
Begin
  Fd := SysOpen('/var/log/cron.out', O_WRONLY Or O_CREAT Or O_APPEND, 420);
  If Fd >= 0 Then
  Begin
    SysPut(Fd, StampS(SysTime) + ' crond[' + NumS(SysGetPid) + ']: ' + S + #10);
    SysClose(Fd);
  End;
End;

{ ---------------- analyse d'un champ ---------------- }

Function NameVal(Const S : String; Mon : Boolean) : LongInt;
Var K : LongInt; L : String;
Begin
  NameVal := -1;
  L := Lower(S);
  If Mon Then
  Begin
    For K := 1 To 12 Do If L = Months[K] Then NameVal := K;
  End
  Else For K := 0 To 6 Do If L = Days[K] Then NameVal := K;
End;

Function ValOf(Const S : String; Mon, Dw : Boolean) : LongInt;
Var V, C : LongInt;
Begin
  Val(S, V, C);
  If C = 0 Then
  Begin
    ValOf := V;
    Exit;
  End;
  If Mon Then ValOf := NameVal(S, True)
  Else If Dw Then ValOf := NameVal(S, False)
  Else ValOf := -1;
End;

{ remplit Arr[Lo..Hi] ; faux si erreur ; Star = champ reduit a * }
Function Field(Const F : String; Lo, Hi : LongInt; Mon, Dw : Boolean;
               Var Arr : Array Of Boolean; Var Star : Boolean) : Boolean;
Var
  K, P, A, B, Stp, I : LongInt;
  Item, Rng : String;
Begin
  Field := False;
  For I := 0 To High(Arr) Do Arr[I] := False;
  Star := (F = '*') Or (Copy(F, 1, 2) = '*/');
  K := 1;
  While K <= Length(F) + 1 Do
  Begin
    Item := '';
    While (K <= Length(F)) And (F[K] <> ',') Do
    Begin
      Item := Item + F[K];
      Inc(K);
    End;
    Inc(K);
    If Item = '' Then Exit;
    Stp := 1;
    P := Pos('/', Item);
    If P > 0 Then
    Begin
      Val(Copy(Item, P + 1, 255), Stp, A);
      If (A <> 0) Or (Stp < 1) Then Exit;
      Item := Copy(Item, 1, P - 1);
    End;
    If Item = '*' Then
    Begin
      A := Lo;
      B := Hi;
    End
    Else
    Begin
      P := Pos('-', Item);
      If P > 0 Then
      Begin
        A := ValOf(Copy(Item, 1, P - 1), Mon, Dw);
        B := ValOf(Copy(Item, P + 1, 255), Mon, Dw);
      End
      Else
      Begin
        A := ValOf(Item, Mon, Dw);
        B := A;
        If Stp > 1 Then B := Hi;
      End;
    End;
    If Dw Then
    Begin
      If A = 7 Then A := 0;
      If (B = 7) And (A <> 0) Then B := 7;
    End;
    If (A < Lo) Or (B > Hi + Ord(Dw)) Or (A > B) Then Exit;
    I := A;
    While I <= B Do
    Begin
      If Dw And (I = 7) Then Arr[0] := True
      Else Arr[I - Lo] := True;
      I := I + Stp;
    End;
  End;
  Field := True;
End;

{ une ligne de crontab ; Sys = fichier systeme (champ utilisateur) }
Function ParseLine(Const Ln : String; Sys : Boolean; Const DefUser : String;
                   Var E : TEnt) : Boolean;
Var
  S : String;
  F : Array[1..5] Of String;
  I, P : LongInt;
  Dummy : Boolean;
Begin
  ParseLine := False;
  S := Trim(Ln);
  E.Reboot := False;
  E.User := DefUser;
  If Copy(S, 1, 1) = '@' Then
  Begin
    P := Pos(' ', S);
    If P = 0 Then Exit;
    F[1] := Lower(Copy(S, 2, P - 2));
    S := Trim(Copy(S, P + 1, 255));
    If F[1] = 'reboot' Then
    Begin
      E.Reboot := True;
      F[1] := '*'; F[2] := '*'; F[3] := '*'; F[4] := '*'; F[5] := '*';
    End
    Else If (F[1] = 'hourly') Then
    Begin F[1] := '0'; F[2] := '*'; F[3] := '*'; F[4] := '*'; F[5] := '*'; End
    Else If (F[1] = 'daily') Or (F[1] = 'midnight') Then
    Begin F[1] := '0'; F[2] := '0'; F[3] := '*'; F[4] := '*'; F[5] := '*'; End
    Else If F[1] = 'weekly' Then
    Begin F[1] := '0'; F[2] := '0'; F[3] := '*'; F[4] := '*'; F[5] := '0'; End
    Else If F[1] = 'monthly' Then
    Begin F[1] := '0'; F[2] := '0'; F[3] := '1'; F[4] := '*'; F[5] := '*'; End
    Else If (F[1] = 'yearly') Or (F[1] = 'annually') Then
    Begin F[1] := '0'; F[2] := '0'; F[3] := '1'; F[4] := '1'; F[5] := '*'; End
    Else
    Begin
      ErrMsg := 'bad @ keyword';
      Exit;
    End;
  End
  Else
    For I := 1 To 5 Do
    Begin
      P := 1;
      While (P <= Length(S)) And (S[P] <> ' ') And (S[P] <> #9) Do Inc(P);
      F[I] := Copy(S, 1, P - 1);
      S := Trim(Copy(S, P, 255));
      If F[I] = '' Then
      Begin
        ErrMsg := 'too few fields';
        Exit;
      End;
    End;
  If Sys Then
  Begin
    P := 1;
    While (P <= Length(S)) And (S[P] <> ' ') And (S[P] <> #9) Do Inc(P);
    E.User := Copy(S, 1, P - 1);
    S := Trim(Copy(S, P, 255));
  End;
  If S = '' Then
  Begin
    ErrMsg := 'no command';
    Exit;
  End;
  If Not Field(F[1], 0, 59, False, False, E.Mi, Dummy) Then
  Begin ErrMsg := 'bad minute'; Exit; End;
  If Not Field(F[2], 0, 23, False, False, E.Hr, Dummy) Then
  Begin ErrMsg := 'bad hour'; Exit; End;
  If Not Field(F[3], 1, 31, False, False, E.Dm, E.DmStar) Then
  Begin ErrMsg := 'bad day-of-month'; Exit; End;
  If Not Field(F[4], 1, 12, True, False, E.Mo, Dummy) Then
  Begin ErrMsg := 'bad month'; Exit; End;
  If Not Field(F[5], 0, 6, False, True, E.Dw, E.DwStar) Then
  Begin ErrMsg := 'bad day-of-week'; Exit; End;
  E.Cmd := S;
  ParseLine := True;
End;

Function Matches(Var E : TEnt; T : LongInt) : Boolean;
Var Y, Mo, D, H, Mi, Wd : LongInt; DayOk : Boolean;
Begin
  Break_(T, Y, Mo, D, H, Mi, Wd);
  Matches := False;
  If Not (E.Mi[Mi] And E.Hr[H] And E.Mo[Mo]) Then Exit;
  If E.DmStar Or E.DwStar Then DayOk := E.Dm[D] And E.Dw[Wd]
  Else DayOk := E.Dm[D] Or E.Dw[Wd];
  Matches := DayOk;
End;

{ ---------------- chargement des tables ---------------- }

Procedure LoadFile(Const Path : String; Sys : Boolean; Const User : String);
Var
  Lines : Array[0..511] Of String;
  N, I, P : LongInt;
  S : String;
Begin
  N := ReadAll(Path, Lines, 512);
  If N <= 0 Then Exit;
  NVars := 0;
  For I := 0 To N - 1 Do
  Begin
    S := Trim(Lines[I]);
    If (S = '') Or (S[1] = '#') Then Continue;
    P := Pos('=', S);
    If (P > 1) And (Pos(' ', Copy(S, 1, P - 1)) = 0) And
       (S[1] <> '@') And (S[1] <> '*') And ((S[1] < '0') Or (S[1] > '9')) Then
    Begin
      If NVars < 64 Then
      Begin
        Inc(NVars);
        Vars[NVars] := S;
      End;
      Continue;
    End;
    If NEnt >= MaxEnt Then Break;
    Inc(NEnt);
    If ParseLine(S, Sys, User, Ents[NEnt]) Then
    Begin
      Ents[NEnt].EnvN := NVars;
    End
    Else
    Begin
      Dec(NEnt);
      LogLine(Path + ': ' + ErrMsg + ': ' + S);
    End;
  End;
End;

Procedure LoadAll;
Var Dh, Ino : LongInt; Nm : String;
Begin
  NEnt := 0;
  LoadFile('/etc/crontab', True, 'root');
  Dh := SysOpenDir('/etc/cron.d');
  If Dh >= 0 Then
  Begin
    While SysReadDir(Dh, Nm, Ino) <> 0 Do
      If (Nm <> '') And (Nm[1] <> '.') Then
        LoadFile('/etc/cron.d/' + Nm, True, 'root');
    SysCloseDir(Dh);
  End;
  Dh := SysOpenDir(CronDir);
  If Dh >= 0 Then
  Begin
    While SysReadDir(Dh, Nm, Ino) <> 0 Do
      If (Nm <> '') And (Nm[1] <> '.') Then
        LoadFile(CronDir + '/' + Nm, False, Nm);
    SysCloseDir(Dh);
  End;
End;

{ ---------------- execution d'un travail ---------------- }

Procedure RunJob(Const User, Cmd : String; Const Extra : String);
Var
  Pid, Fd, P, K : LongInt;
  Pw : TSysPasswd;
  Shell, Home, Input, C : String;
Begin
  Shell := '/bin/sh';
  Home := '/';
  If SysGetPwNam(User, Pw) Then
  Begin
    Home := Pw.Home;
    If Pw.Shell <> '' Then Shell := '/bin/sh';
  End
  Else
  Begin
    LogLine('(' + User + ') unknown user');
    Exit;
  End;
  { % : fin de commande, le reste est l'entree standard }
  C := Cmd;
  Input := '';
  K := 1;
  While K <= Length(C) Do
  Begin
    If (C[K] = '\') And (K < Length(C)) And (C[K + 1] = '%') Then
    Begin
      Delete(C, K, 1);
      Inc(K);
    End
    Else If C[K] = '%' Then
    Begin
      Input := Copy(C, K + 1, 255);
      C := Copy(C, 1, K - 1);
      For P := 1 To Length(Input) Do If Input[P] = '%' Then Input[P] := #10;
      Input := Input + #10;
      Break;
    End
    Else Inc(K);
  End;
  LogLine('(' + User + ') CMD (' + C + ')');
  Pid := SysFork;
  If Pid <> 0 Then Exit;
  { enfant }
  SysSetSid;
  Fd := SysOpen('/var/log/cron.out', O_WRONLY Or O_CREAT Or O_APPEND, 420);
  If Fd < 0 Then Fd := SysOpen('/dev/null', O_WRONLY, 0);
  If Input <> '' Then
  Begin
    WriteStr('/tmp/.cron.' + NumS(SysGetPid), Input, 384);
    K := SysOpen('/tmp/.cron.' + NumS(SysGetPid), O_RDONLY, 0);
    SysUnlink('/tmp/.cron.' + NumS(SysGetPid));
  End
  Else K := SysOpen('/dev/null', O_RDONLY, 0);
  SysDup2(K, 0);
  SysDup2(Fd, 1);
  SysDup2(Fd, 2);
  If SysGetUid = 0 Then
  Begin
    SysSetGid(Pw.Gid);
    SysSetUid(Pw.Uid);
  End;
  SysChdir(Home);
  SysArgReset;
  SysArgAdd('sh');
  SysArgAdd('-c');
  SysArgAdd(C);
  SysEnvAdd('SHELL=/bin/sh');
  SysEnvAdd('HOME=' + Home);
  SysEnvAdd('LOGNAME=' + User);
  SysEnvAdd('USER=' + User);
  SysEnvAdd('PATH=/usr/bin:/bin:/usr/sbin:/sbin');
  If Extra <> '' Then SysEnvAdd(Extra);
  SysArgExec(Shell);
  SysExit(127);
End;

Procedure Reap;
Var St : LongInt;
Begin
  While SysWaitPid(-1, St, WNOHANG) > 0 Do ;
End;

{ ---------------- at ---------------- }

Function AtSpool(N : LongInt) : String;
Begin
  AtSpool := AtDir;
End;

Function HexS(V, W : LongInt) : String;
Const D = '0123456789abcdef';
Var S : String; K : LongInt;
Begin
  S := '';
  For K := W - 1 DownTo 0 Do S := S + D[((V Shr (4 * K)) And 15) + 1];
  HexS := S;
End;

Function HexVal(Const S : String) : LongInt;
Var K, V : LongInt;
Begin
  V := 0;
  For K := 1 To Length(S) Do
    If (S[K] >= '0') And (S[K] <= '9') Then V := V * 16 + Ord(S[K]) - 48
    Else If (S[K] >= 'a') And (S[K] <= 'f') Then V := V * 16 + Ord(S[K]) - 87;
  HexVal := V;
End;

{ analyse la specification d'heure ; resultat : secondes UTC ; faux si erreur }
Function ParseWhen(Const Spec : String; Var Res : LongInt) : Boolean;
Var
  W : Array[1..16] Of String;
  NW, I, J, P, Hh, Mm, Y, Mo, D, Hc, Mc, Wd, N, Lt, C : LongInt;
  S, U : String;
  HaveTime, HaveDate, Pm : Boolean;
  Dd : LongInt;
  Plus : LongInt;
Begin
  ParseWhen := False;
  NW := 0;
  S := Lower(Spec);
  While S <> '' Do
  Begin
    S := Trim(S);
    P := Pos(' ', S);
    If P = 0 Then P := Length(S) + 1;
    If NW < 16 Then
    Begin
      Inc(NW);
      W[NW] := Copy(S, 1, P - 1);
    End;
    S := Copy(S, P + 1, 255);
  End;
  Lt := SysTime + LnxTz;
  Break_(Lt, Y, Mo, D, Hc, Mc, Wd);
  Hh := Hc; Mm := Mc;
  HaveTime := False;
  HaveDate := False;
  Plus := 0;
  I := 1;
  While I <= NW Do
  Begin
    U := W[I];
    If U = 'now' Then HaveTime := True
    Else If U = 'midnight' Then Begin Hh := 0; Mm := 0; HaveTime := True; End
    Else If U = 'noon' Then Begin Hh := 12; Mm := 0; HaveTime := True; End
    Else If U = 'teatime' Then Begin Hh := 16; Mm := 0; HaveTime := True; End
    Else If U = 'today' Then HaveDate := True
    Else If U = 'tomorrow' Then
    Begin
      HaveDate := True;
      CivilFromDays(DaysFromCivil(Y, Mo, D) + 1, Y, Mo, D);
    End
    Else If U = '+' Then
    Begin
      If I + 2 > NW Then Exit;
      Val(W[I + 1], N, C);
      If C <> 0 Then Exit;
      U := W[I + 2];
      If Copy(U, 1, 3) = 'min' Then Plus := Plus + N * 60
      Else If Copy(U, 1, 4) = 'hour' Then Plus := Plus + N * 3600
      Else If Copy(U, 1, 3) = 'day' Then Plus := Plus + N * 86400
      Else If Copy(U, 1, 4) = 'week' Then Plus := Plus + N * 7 * 86400
      Else Exit;
      Inc(I, 2);
    End
    Else If (U[1] = '+') And (Length(U) > 1) Then
    Begin
      Val(Copy(U, 2, 255), N, C);
      If C <> 0 Then Exit;
      If I + 1 > NW Then Exit;
      Inc(I);
      U := W[I];
      If Copy(U, 1, 3) = 'min' Then Plus := Plus + N * 60
      Else If Copy(U, 1, 4) = 'hour' Then Plus := Plus + N * 3600
      Else If Copy(U, 1, 3) = 'day' Then Plus := Plus + N * 86400
      Else If Copy(U, 1, 4) = 'week' Then Plus := Plus + N * 7 * 86400
      Else Exit;
    End
    Else If (Pos(':', U) > 0) Or ((U[1] >= '0') And (U[1] <= '9') And
            (Length(U) >= 3) And (Pos('/', U) = 0) And (Pos('.', U) = 0)) Then
    Begin
      Pm := False;
      If Copy(U, Length(U) - 1, 2) = 'pm' Then
      Begin Pm := True; Delete(U, Length(U) - 1, 2); End
      Else If Copy(U, Length(U) - 1, 2) = 'am' Then
        Delete(U, Length(U) - 1, 2);
      P := Pos(':', U);
      If P > 0 Then
      Begin
        Val(Copy(U, 1, P - 1), Hh, C);
        If C <> 0 Then Exit;
        Val(Copy(U, P + 1, 255), Mm, C);
        If C <> 0 Then Exit;
      End
      Else
      Begin
        Val(U, N, C);
        If C <> 0 Then Exit;
        If Length(U) <= 2 Then Begin Hh := N; Mm := 0; End
        Else Begin Hh := N Div 100; Mm := N Mod 100; End;
      End;
      If Pm And (Hh < 12) Then Hh := Hh + 12;
      If (Hh > 23) Or (Mm > 59) Then Exit;
      HaveTime := True;
    End
    Else If Pos('/', U) > 0 Then
    Begin
      P := Pos('/', U);
      Val(Copy(U, 1, P - 1), Mo, C);
      If C <> 0 Then Exit;
      U := Copy(U, P + 1, 255);
      P := Pos('/', U);
      Val(Copy(U, 1, P - 1), D, C);
      If (C <> 0) Or (P = 0) Then Exit;
      Val(Copy(U, P + 1, 255), Y, C);
      If C <> 0 Then Exit;
      If Y < 100 Then Y := Y + 2000;
      HaveDate := True;
    End
    Else If Pos('.', U) > 0 Then
    Begin
      P := Pos('.', U);
      Val(Copy(U, 1, P - 1), D, C);
      If C <> 0 Then Exit;
      U := Copy(U, P + 1, 255);
      P := Pos('.', U);
      Val(Copy(U, 1, P - 1), Mo, C);
      If (C <> 0) Or (P = 0) Then Exit;
      Val(Copy(U, P + 1, 255), Y, C);
      If C <> 0 Then Exit;
      If Y < 100 Then Y := Y + 2000;
      HaveDate := True;
    End
    Else
    Begin
      { nom de mois suivi du jour (et de l'annee) }
      N := -1;
      For J := 1 To 12 Do If Copy(U, 1, 3) = Months[J] Then N := J;
      If N < 0 Then Exit;
      Mo := N;
      If I + 1 > NW Then Exit;
      Inc(I);
      Val(W[I], D, C);
      If C <> 0 Then Exit;
      If (I + 1 <= NW) And (Length(W[I + 1]) = 4) Then
      Begin
        Inc(I);
        Val(W[I], Y, C);
        If C <> 0 Then Exit;
      End;
      HaveDate := True;
    End;
    Inc(I);
  End;
  If (Not HaveTime) And (Not HaveDate) And (Plus = 0) Then Exit;
  Dd := DaysFromCivil(Y, Mo, D);
  Res := Dd * 86400 + Hh * 3600 + Mm * 60 - LnxTz;
  { heure deja passee aujourd'hui : demain }
  If HaveTime And (Not HaveDate) And (Res < SysTime) And (Plus = 0) Then
    Res := Res + 86400;
  If (Not HaveTime) And HaveDate Then ;
  If (Plus > 0) And (Not HaveTime) And (Not HaveDate) Then
    Res := SysTime + Plus
  Else Res := Res + Plus;
  ParseWhen := True;
End;

Function CurUser : String;
Var Pw : TSysPasswd;
Begin
  If SysGetPwUid(SysGetUid, Pw) Then CurUser := Pw.Name
  Else CurUser := NumS(SysGetUid);
End;

Procedure DoAt(Batch : Boolean);
Var
  I, Fd, N, T, Num : LongInt;
  A, Spec, FileIn, Body, Name, Dh, Nm2 : String;
  B : Byte;
  Dhl, Ino, Max : LongInt;
  Pw : TSysPasswd;
  St : TSysStat;
Begin
  Spec := '';
  FileIn := '';
  I := 1;
  While I < SysArgCount Do
  Begin
    A := SysArgStr(I);
    If (A = '--help') Or (A = '/?') Then
    Begin
      SysPut(1, PS(UsageAt[Lang]) + #10);
      SysExit(0);
    End
    Else If A = '-f' Then
    Begin
      Inc(I);
      If I < SysArgCount Then FileIn := SysArgStr(I);
    End
    Else If (A = '-q') Then Inc(I)
    Else If (A = '-m') Or (A = '-M') Or (A = '-v') Or (A = '-c') Then
    Else Spec := Spec + A + ' ';
    Inc(I);
  End;
  If Batch Then Spec := 'now'
  Else If Spec = '' Then
  Begin
    SysPut(2, PS(UsageAt[Lang]) + #10);
    SysExit(1);
  End;
  If Not ParseWhen(Spec, T) Then
  Begin
    SysPut(2, 'at: garbled time' + #10);
    SysExit(1);
  End;
  If FileIn <> '' Then Fd := SysOpen(FileIn, O_RDONLY, 0) Else Fd := 0;
  If Fd < 0 Then
  Begin
    SysPut(2, 'at: ' + FileIn + ': ' + SysErrorText(SysErrno) + #10);
    SysExit(1);
  End;
  Body := '';
  While SysRead(Fd, B, 1) > 0 Do
    If Length(Body) < 250 Then Body := Body + Chr(B);
  { corps : memes octets tels quels (jusqu'a 250) }
  If Fd > 0 Then SysClose(Fd);
  { numero de travail : plus grand + 1 }
  Max := 0;
  Dhl := SysOpenDir(AtDir);
  If Dhl < 0 Then
  Begin
    SysMkdir('/var/spool', 493);
    SysMkdir('/var/spool/cron', 493);
    SysMkdir(AtDir, 448);
    Dhl := SysOpenDir(AtDir);
  End;
  If Dhl >= 0 Then
  Begin
    While SysReadDir(Dhl, Nm2, Ino) <> 0 Do
      If (Length(Nm2) = 14) And ((Nm2[1] = 'a') Or (Nm2[1] = 'b')) Then
        If HexVal(Copy(Nm2, 2, 5)) > Max Then Max := HexVal(Copy(Nm2, 2, 5));
    SysCloseDir(Dhl);
  End;
  Num := Max + 1;
  Name := 'a';
  If Batch Then Name := 'b';
  Name := Name + HexS(Num, 5) + HexS(T Div 60, 8);
  Body := '#!/bin/sh' + #10 + '# atrun uid=' + NumS(SysGetUid) + ' gid=' +
          NumS(SysGetGid) + #10 + '# mail ' + CurUser + ' 0' + #10 +
          'umask 22' + #10 + 'cd ' + SysGetCwd + #10 + Body;
  If Not WriteStr(AtDir + '/' + Name, Body, 448) Then
  Begin
    SysPut(2, 'at: cannot create job' + #10);
    SysExit(1);
  End;
  SysChown(AtDir + '/' + Name, SysGetUid, SysGetGid);
  SysPut(2, 'job ' + NumS(Num) + ' at ' + StampS(T) + #10);
End;

Procedure AtQ(Remove : Boolean);
Var Dh, Ino, I, Id, Cnt : LongInt; Nm, A : String; St : TSysStat;
    Pw : TSysPasswd;
    Un : String;
Begin
  Dh := SysOpenDir(AtDir);
  If Dh < 0 Then Exit;
  While SysReadDir(Dh, Nm, Ino) <> 0 Do
    If (Length(Nm) = 14) And ((Nm[1] = 'a') Or (Nm[1] = 'b')) Then
    Begin
      Id := HexVal(Copy(Nm, 2, 5));
      SysStat(AtDir + '/' + Nm, St);
      If Remove Then
      Begin
        For I := 1 To SysArgCount - 1 Do
          If SysArgStr(I) = NumS(Id) Then
            If (SysGetUid = 0) Or (St.Uid = SysGetUid) Then
              SysUnlink(AtDir + '/' + Nm);
      End
      Else If (SysGetUid = 0) Or (St.Uid = SysGetUid) Then
      Begin
        If SysGetPwUid(St.Uid, Pw) Then Un := Pw.Name Else Un := NumS(St.Uid);
        SysPut(1, NumS(Id) + #9 + StampS(HexVal(Copy(Nm, 7, 8)) * 60) + ' ' +
               Nm[1] + ' ' + Un + #10);
      End;
    End;
  SysCloseDir(Dh);
End;

Function LoadAvg : LongInt;
Var Fd, N : LongInt; S : String; B : Byte; V : LongInt;
Begin
  LoadAvg := 0;
  Fd := SysOpen('/proc/loadavg', O_RDONLY, 0);
  If Fd < 0 Then Exit;
  S := '';
  While (SysRead(Fd, B, 1) > 0) And (B <> 32) And (Length(S) < 10) Do
    S := S + Chr(B);
  SysClose(Fd);
  V := 0;
  N := Pos('.', S);
  If N = 0 Then N := Length(S) + 1;
  Val(Copy(S, 1, N - 1), V, Fd);
  V := V * 100;
  If N < Length(S) Then
  Begin
    Val(Copy(S, N + 1, 2), Fd, N);
    If Length(S) - Pos('.', S) = 1 Then Fd := Fd * 10;
    V := V + Fd;
  End;
  LoadAvg := V;
End;

Procedure RunAtJobs;
Var
  Dh, Ino, Id : LongInt; Nm : String; St : TSysStat; Pw : TSysPasswd;
  Lines : Array[0..63] Of String; N : LongInt; Pid : LongInt;
  Names : Array[1..64] Of String; NN, K : LongInt; T : LongInt;
Begin
  Dh := SysOpenDir(AtDir);
  If Dh < 0 Then Exit;
  NN := 0;
  While SysReadDir(Dh, Nm, Ino) <> 0 Do
    If (Length(Nm) = 14) And ((Nm[1] = 'a') Or (Nm[1] = 'b')) And (NN < 64) Then
    Begin
      Inc(NN);
      Names[NN] := Nm;
    End;
  SysCloseDir(Dh);
  For K := 1 To NN Do
  Begin
    Nm := Names[K];
    T := HexVal(Copy(Nm, 7, 8)) * 60;
    If T > SysTime Then Continue;
    If (Nm[1] = 'b') And (LoadAvg >= 150) Then Continue;
    If SysStat(AtDir + '/' + Nm, St) <> 0 Then Continue;
    If Not SysGetPwUid(St.Uid, Pw) Then
    Begin
      SysUnlink(AtDir + '/' + Nm);
      Continue;
    End;
    LogLine('(' + Pw.Name + ') ATJOB ' + NumS(HexVal(Copy(Nm, 2, 5))));
    Pid := SysFork;
    If Pid = 0 Then
    Begin
      SysSetSid;
      N := SysOpen('/var/log/cron.out', O_WRONLY Or O_CREAT Or O_APPEND, 420);
      SysDup2(SysOpen('/dev/null', O_RDONLY, 0), 0);
      If N >= 0 Then
      Begin
        SysDup2(N, 1);
        SysDup2(N, 2);
      End;
      If SysGetUid = 0 Then
      Begin
        SysSetGid(Pw.Gid);
        SysSetUid(Pw.Uid);
      End;
      SysArgReset;
      SysArgAdd('sh');
      SysArgAdd(AtDir + '/' + Nm);
      SysEnvAdd('HOME=' + Pw.Home);
      SysEnvAdd('LOGNAME=' + Pw.Name);
      SysEnvAdd('PATH=/usr/bin:/bin:/usr/sbin:/sbin');
      SysArgExec('/bin/sh');
      SysExit(127);
    End;
    { le travail est execute : supprime des maintenant (comme atd) }
    SysUnlink(AtDir + '/' + Nm);
  End;
End;

{ ---------------- crond / atd ---------------- }

Procedure Daemon(IsAtd : Boolean);
Var
  Last, Now, I, J : LongInt;
  Fd : LongInt;
  First : Boolean;
Begin
  If Not Foreground Then
  Begin
    If SysFork > 0 Then SysExit(0);
    SysSetSid;
    SysClose(0);
    SysClose(1);
    SysClose(2);
    SysOpen('/dev/null', O_RDWR, 0);
    SysDup(0);
    SysDup(0);
  End;
  SysMkdir('/var/spool', 493);
  SysMkdir('/var/spool/cron', 493);
  SysMkdir(CronDir, 448);
  SysMkdir(AtDir, 448);
  If IsAtd Then WriteStr('/var/run/atd.pid', NumS(SysGetPid) + #10, 420)
  Else WriteStr('/var/run/crond.pid', NumS(SysGetPid) + #10, 420);
  LogLine('started');
  First := True;
  Last := SysTime Div 60;
  While True Do
  Begin
    Reap;
    If IsAtd Then
    Begin
      RunAtJobs;
      SysSleep(30);
    End
    Else
    Begin
      LoadAll;
      If First Then
      Begin
        For I := 1 To NEnt Do
          If Ents[I].Reboot Then RunJob(Ents[I].User, Ents[I].Cmd, '');
        First := False;
      End;
      Now := SysTime Div 60;
      While Last < Now Do
      Begin
        Inc(Last);
        For I := 1 To NEnt Do
          If (Not Ents[I].Reboot) And
             Matches(Ents[I], Last * 60 + LnxTz) Then
            RunJob(Ents[I].User, Ents[I].Cmd, '');
        Reap;
      End;
      { attendre le debut de la minute suivante }
      J := 60 - (SysTime Mod 60);
      If J < 1 Then J := 1;
      SysSleep(J);
    End;
  End;
End;

{ ---------------- crontab ---------------- }

Procedure CrontabCmd;
Var
  I, N, K, Fd, Pid, St : LongInt;
  A, Who, Path, FileArg, Mode, Body, Ed : String;
  Lines : Array[0..511] Of String;
  E : TEnt;
  Ok : Boolean;
  Pw : TSysPasswd;
  B : Byte;
  Tmp : String;
Begin
  Who := CurUser;
  Mode := '';
  FileArg := '';
  I := 1;
  While I < SysArgCount Do
  Begin
    A := SysArgStr(I);
    If (A = '--help') Or (A = '/?') Then
    Begin
      SysPut(1, PS(Usage[Lang]) + #10);
      SysExit(0);
    End
    Else If A = '-u' Then
    Begin
      Inc(I);
      If I < SysArgCount Then Who := SysArgStr(I);
      If (Who <> CurUser) And (SysGetUid <> 0) Then
      Begin
        SysPut(2, 'crontab: must be privileged to use -u' + #10);
        SysExit(1);
      End;
    End
    Else If (A = '-l') Or (A = '-r') Or (A = '-e') Then Mode := A
    Else FileArg := A;
    Inc(I);
  End;
  If (Mode = '') And (FileArg = '') Then
  Begin
    SysPut(2, PS(Usage[Lang]) + #10);
    SysExit(1);
  End;
  SysMkdir('/var/spool', 493);
  SysMkdir('/var/spool/cron', 493);
  SysMkdir(CronDir, 448);
  Path := CronDir + '/' + Who;
  If Mode = '-l' Then
  Begin
    N := ReadAll(Path, Lines, 512);
    If N < 0 Then
    Begin
      SysPut(2, 'no crontab for ' + Who + #10);
      SysExit(1);
    End;
    For K := 0 To N - 1 Do SysPut(1, Lines[K] + #10);
    SysExit(0);
  End;
  If Mode = '-r' Then
  Begin
    If SysUnlink(Path) < 0 Then
    Begin
      SysPut(2, 'no crontab for ' + Who + #10);
      SysExit(1);
    End;
    SysExit(0);
  End;
  If Mode = '-e' Then
  Begin
    Tmp := '/tmp/crontab.' + NumS(SysGetPid);
    N := ReadAll(Path, Lines, 512);
    Body := '';
    For K := 0 To N - 1 Do Body := Body + Lines[K] + #10;
    WriteStr(Tmp, Body, 384);
    SysChown(Tmp, SysGetUid, SysGetGid);
    Ed := SysGetEnv('VISUAL');
    If Ed = '' Then Ed := SysGetEnv('EDITOR');
    If Ed = '' Then Ed := 'vi';
    Pid := SysFork;
    If Pid = 0 Then
    Begin
      SysArgReset;
      SysArgAdd('sh');
      SysArgAdd('-c');
      SysArgAdd(Ed + ' ' + Tmp);
      SysEnvInherit;
      SysArgExec('/bin/sh');
      SysExit(127);
    End;
    SysWaitPid(Pid, St, 0);
    FileArg := Tmp;
  End;
  If FileArg = '-' Then Fd := 0 Else Fd := SysOpen(FileArg, O_RDONLY, 0);
  If Fd < 0 Then
  Begin
    SysPut(2, 'crontab: ' + FileArg + ': ' + SysErrorText(SysErrno) + #10);
    SysExit(1);
  End;
  N := 0;
  Body := '';
  Lines[0] := '';
  While SysRead(Fd, B, 1) > 0 Do
    If B = 10 Then
    Begin
      If N < 511 Then
      Begin
        Lines[N] := Body;
        Inc(N);
      End;
      Body := '';
    End
    Else If Length(Body) < 250 Then Body := Body + Chr(B);
  If Body <> '' Then
  Begin
    Lines[N] := Body;
    Inc(N);
  End;
  If Fd > 0 Then SysClose(Fd);
  If Mode = '-e' Then SysUnlink(FileArg);
  Ok := True;
  Body := '';
  For K := 0 To N - 1 Do
  Begin
    A := Trim(Lines[K]);
    If (A <> '') And (A[1] <> '#') And
       Not ((Pos('=', A) > 1) And (Pos(' ', Copy(A, 1, Pos('=', A) - 1)) = 0)
            And ((A[1] < '0') Or (A[1] > '9')) And (A[1] <> '*') And
            (A[1] <> '@')) Then
      If Not ParseLine(A, False, Who, E) Then
      Begin
        SysPut(2, 'crontab: "' + FileArg + '":' + NumS(K + 1) + ': ' + ErrMsg +
               #10);
        Ok := False;
      End;
    Body := Body + Lines[K] + #10;
  End;
  If Not Ok Then
  Begin
    SysPut(2, 'crontab: errors in crontab file, can''t install.' + #10);
    SysExit(1);
  End;
  If Not WriteStr(Path, Body, 384) Then
  Begin
    SysPut(2, 'crontab: ' + Path + ': ' + SysErrorText(SysErrno) + #10);
    SysExit(1);
  End;
  If SysGetPwNam(Who, Pw) Then SysChown(Path, Pw.Uid, Pw.Gid);
  SysExit(0);
End;

Var
  I : LongInt;
  A : String;
BEGIN
  Lang := SysLang;
  If (Lang < 1) Or (Lang > 5) Then Lang := 1;
  Prog := SysArgStr(0);
  While Pos('/', Prog) > 0 Do Prog := Copy(Prog, Pos('/', Prog) + 1, 255);
  Foreground := False;
  For I := 1 To SysArgCount - 1 Do
    If SysArgStr(I) = '-f' Then Foreground := True;
  If Prog = 'crontab' Then CrontabCmd
  Else If Prog = 'at' Then DoAt(False)
  Else If Prog = 'batch' Then DoAt(True)
  Else If Prog = 'atq' Then AtQ(False)
  Else If Prog = 'atrm' Then AtQ(True)
  Else If Prog = 'atd' Then Daemon(True)
  Else If (Prog = 'crond') Or (Prog = 'cron') Then Daemon(False)
  Else Daemon(False);
END.
