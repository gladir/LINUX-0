{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2026
  @website(https://www.gladir.com/linux-0)
  @abstract(Target: LPC -3X)
  @description: /sbin/k32-setup : assistant d'installation graphique de
   KERNEL32 (CD-ROM d'installation). Ecran /dev/fb0 (1024x768 32 bits),
   clavier, souris ; repli texte ANSI (touche F3). Langues : francais,
   English, Deutsch, Italiano, Espanol, Portugues, Nederlands. Etapes :
   langue, clavier, fuseau horaire, date et heure, nom de la machine,
   comptes, disque, partitionnement (assiste ou manuel), points de montage,
   recapitulatif, installation (partitions, mkfs, copie de /cdrom/system.tar,
   configuration, noyau, chargeur), fin. Mode automatique : parametre du
   noyau preseed=FICHIER (cle=valeur, voir README). Journal :
   /var/log/install.log.
   Usage : k32-setup [-t /dev/tty1] [-p fichier] [--text] [--restore]
     (--restore : remet le clavier et la console en mode normal)
   Sortie : 0 installation terminee (redemarre), 2 abandon, 3 erreur. }

Program K32Setup;

{$I FONTS.INC}
{$I GFX.INC}
{$I UIBASE.INC}
{$I LAYOUTS.INC}
{$I MSGS.INC}
{$I INPUT.INC}
{$I WIDGETS.INC}
{$I DISKS.INC}
{$I INSTOPS.INC}
{$I FSPROBE.INC}

Const
  NAV_BACK = 1;  NAV_NEXT = 2;  NAV_CANCEL = 3;
  RES_REBUILD = -2;
  S_LANG = 0;  S_WELC = 1;  S_KEY = 2;  S_TZ = 3;  S_CLK = 4;  S_HOST = 5;
  S_ACC = 6;  S_DISK = 7;  S_METH = 8;  S_PED = 9;  S_ROLE = 10;  S_SUM = 11;
  S_INST = 12;  S_END = 13;
  LangCode : Array[0..6] Of String[2] = ('FR', 'EN', 'DE', 'IT', 'ES', 'PT',
    'NL');
  LangName : Array[0..6] Of String[12] = ('Fran'#231'ais', 'English',
    'Deutsch', 'Italiano', 'Espa'#241'ol', 'Portugu'#234's', 'Nederlands');
  LangLoc : Array[0..6] Of String[5] = ('fr_FR', 'en_US', 'de_DE', 'it_IT',
    'es_ES', 'pt_PT', 'nl_NL');
  LangDefLay : Array[0..6] Of String[4] = ('fr', 'us', 'de', 'it', 'es', 'pt',
    'nl');
  LangDefTz : Array[0..6] Of String[20] = ('Europe/Paris', 'Europe/London',
    'Europe/Berlin', 'Europe/Rome', 'Europe/Madrid', 'Europe/Lisbon',
    'Europe/Amsterdam');
  ContDir : Array[0..10] Of String[12] = ('Africa', 'America', 'Antarctica',
    'Arctic', 'Asia', 'Atlantic', 'Australia', 'Europe', 'Indian', 'Pacific',
    'Etc');
  ZONEDIR = '/usr/share/zoneinfo/';
  CDMNT = '/cdrom';
  TGT = '/target';

Var
  Lang, LayI, Step, ClkUtc, FsKind, DiskIx, PartMode, TzCont : LongInt;
  LayTouched, TzTouched, ClkTouched, UseSwap, Quitting, AutoMode, TextOnly,
    NoUi, CdOk, TzLoaded, SwapEdited : Boolean;
  TzName, ClkDate, ClkTime, Host, RootPw, UserFull, UserName, UserPw,
    SwapMb, TtyPath, PresPath, RebootMode, DiskPath : String;
  Cities : Array[0..699] Of String[40];
  CityN : LongInt;
  PedKind, PedIdx : Array[0..31] Of LongInt;
  PedN : LongInt;
  StageBase, StageSpan : LongInt;
  InstLogW, InstProgW, InstLblW : LongInt;
  LastDraw : LongInt;
  CmdLine : String;
  PsKey, PsVal : Array[0..63] Of String[80];
  PsN : LongInt;
  FsName : Array[2..4] Of String[4];
  InstFailed : Boolean;
  ExistNote : String;          { contenu detecte sur le disque choisi }
  ExistSys : Boolean;

{ ---- textes ---- }

Function Msg(Id : LongInt) : String;
Var I, A, B : LongInt; X : String;
Begin
  A := MsgOff[Id * MsgLangs + Lang];
  B := MsgOff[Id * MsgLangs + Lang + 1];
  If B - A > 255 Then B := A + 255;
  X := '';
  For I := A To B - 1 Do X := X + Chr(MsgBlob[I]);
  Msg := X;
End;

Function NumS(V : LongInt) : String;
Var S : String;
Begin
  Str(V, S);
  NumS := S;
End;

{ remplace %1 %2 %3 }
Function Fmt(Id : LongInt; Const A, B, C : String) : String;
Var S, R : String; I : LongInt;
Begin
  S := Msg(Id);
  R := '';
  I := 1;
  While I <= Length(S) Do
  Begin
    If (S[I] = '%') And (I < Length(S)) And (S[I + 1] >= '1') And
       (S[I + 1] <= '3') Then
    Begin
      Case S[I + 1] Of
        '1' : R := R + A;
        '2' : R := R + B;
        '3' : R := R + C;
      End;
      Inc(I);
    End
    Else R := R + S[I];
    Inc(I);
  End;
  Fmt := R;
End;

Function PadR(Const S : String; N : LongInt) : String;
Var R : String;
Begin
  R := S;
  While Length(R) < N Do R := R + ' ';
  PadR := Copy(R, 1, N);
End;

Function PadL(Const S : String; N : LongInt) : String;
Var R : String;
Begin
  R := S;
  While Length(R) < N Do R := ' ' + R;
  PadL := R;
End;

Function LowerS(Const S : String) : String;
Var I : LongInt; R : String;
Begin
  R := S;
  For I := 1 To Length(R) Do
    If (R[I] >= 'A') And (R[I] <= 'Z') Then R[I] := Chr(Ord(R[I]) + 32);
  LowerS := R;
End;

{ ---- parametres : ligne de commande du noyau et fichier de reponses ---- }

Function CmdGet(Const Key : String) : String;
Var P, E : LongInt; K : String;
Begin
  CmdGet := '';
  K := ' ' + Key + '=';
  P := Pos(K, ' ' + CmdLine);
  If P = 0 Then Exit;
  P := P + Length(K) - 1;
  E := P;
  While (E <= Length(CmdLine)) And (CmdLine[E] <> ' ') And
        (CmdLine[E] <> #10) Do Inc(E);
  CmdGet := Copy(CmdLine, P, E - P);
End;

Function CmdHas(Const Key : String) : Boolean;
Begin
  CmdHas := (Pos(' ' + Key + ' ', ' ' + CmdLine + ' ') > 0) Or
            (CmdGet(Key) <> '');
End;

Procedure PsLoad(Const Path : String);
Var F, P : LongInt; L : String;
Begin
  PsN := 0;
  F := SysOpen(Path, O_RDONLY, 0);
  If F < 0 Then Exit;
  While SysReadLine(F, L) Do
  Begin
    While (Length(L) > 0) And (L[Length(L)] = #13) Do Delete(L, Length(L), 1);
    If (L = '') Or (L[1] = '#') Then Continue;
    P := Pos('=', L);
    If (P > 1) And (PsN < 64) Then
    Begin
      PsKey[PsN] := LowerS(Copy(L, 1, P - 1));
      PsVal[PsN] := UiFromU8(Copy(L, P + 1, 80));
      Inc(PsN);
    End;
  End;
  SysClose(F);
End;

Function PsGet(Const Key, Def : String) : String;
Var I : LongInt;
Begin
  PsGet := Def;
  For I := 0 To PsN - 1 Do
    If PsKey[I] = Key Then PsGet := PsVal[I];
End;

{ ---- dispositions, fuseaux ---- }

Function LayIndex(Const Id : String) : LongInt;
Var I : LongInt;
Begin
  LayIndex := 0;
  For I := 0 To LayCount - 1 Do
    If LayId[I] = Id Then LayIndex := I;
End;

Procedure ApplyLangDefaults;
Begin
  If Not LayTouched Then
  Begin
    LayI := LayIndex(LangDefLay[Lang]);
    InSetLayout(LayI);
  End;
  If Not TzTouched Then TzName := LangDefTz[Lang];
End;

Procedure TzSplit(Const Z : String; Var Cont, City : String);
Var P : LongInt;
Begin
  P := Pos('/', Z);
  If P = 0 Then
  Begin
    Cont := 'Etc';
    City := Z;
  End
  Else
  Begin
    Cont := Copy(Z, 1, P - 1);
    City := Copy(Z, P + 1, 60);
  End;
End;

Function ContIndex(Const C : String) : LongInt;
Var I : LongInt;
Begin
  ContIndex := 10;
  For I := 0 To 10 Do
    If ContDir[I] = C Then ContIndex := I;
End;

{ lit les villes d'une region dans /usr/share/zoneinfo (tri alphabetique ;
  les sous-dossiers comme America/Argentina sont aplatis) }
Procedure LoadCities(Idx : LongInt);
Var D, D2, I, J : LongInt; N, N2, Dir : String; Ino : LongInt; St : TSysStat;
  T : String[40];
Begin
  CityN := 0;
  If Idx = 10 Then
  Begin
    Cities[0] := 'UTC';
    Cities[1] := 'GMT';
    CityN := 2;
    Exit;
  End;
  Dir := ZONEDIR + ContDir[Idx];
  D := SysOpenDir(Dir);
  If D < 0 Then Exit;
  While SysReadDir(D, N, Ino) Do
  Begin
    If (N = '.') Or (N = '..') Or (Pos('.', N) > 0) Then Continue;
    If (SysStat(Dir + '/' + N, St) = 0) And
       ((St.Mode And S_IFMT) = S_IFDIR) Then
    Begin
      D2 := SysOpenDir(Dir + '/' + N);
      If D2 >= 0 Then
      Begin
        While SysReadDir(D2, N2, Ino) Do
          If (N2 <> '.') And (N2 <> '..') And (CityN < 700) Then
          Begin
            Cities[CityN] := Copy(N + '/' + N2, 1, 40);
            Inc(CityN);
          End;
        SysCloseDir(D2);
      End;
    End
    Else If CityN < 700 Then
    Begin
      Cities[CityN] := Copy(N, 1, 40);
      Inc(CityN);
    End;
  End;
  SysCloseDir(D);
  For I := 1 To CityN - 1 Do
  Begin
    T := Cities[I];
    J := I - 1;
    While (J >= 0) And (Cities[J] > T) Do
    Begin
      Cities[J + 1] := Cities[J];
      Dec(J);
    End;
    Cities[J + 1] := T;
  End;
End;

{ date locale dans la zone TzName : AAAA-MM-JJ et HH:MM:SS }
Procedure NowLocal(Var Dt, Tm : String; Var Off : LongInt);
Var T, Days, Secs, Y, M, D : LongInt;
Begin
  LnxTzSelect(TzName);
  T := SysTime;
  Off := LnxTzAt(T);
  T := T + Off;
  Days := T Div 86400;
  Secs := T Mod 86400;
  LnxCivil(Days, Y, M, D);
  Dt := NumS(Y) + '-' + OpNum2(M) + '-' + OpNum2(D);
  Tm := OpNum2(Secs Div 3600) + ':' + OpNum2((Secs Mod 3600) Div 60) + ':' +
        OpNum2(Secs Mod 60);
End;

Function OffStr(Off : LongInt) : String;
Var S : String; A : LongInt;
Begin
  If Off < 0 Then
  Begin
    S := '-';
    A := -Off;
  End
  Else
  Begin
    S := '+';
    A := Off;
  End;
  OffStr := 'UTC' + S + OpNum2(A Div 3600) + ':' + OpNum2((A Mod 3600) Div 60);
End;

{ ---- ecran : pages ---- }

Procedure UiReopen;
Begin
  If TextOnly Then
  Begin
    UiTextOpen;
    Exit;
  End;
  If GOk Or GOpen(1024, 768) Then UiGfxGrid
  Else
  Begin
    TextOnly := True;
    UiTextOpen;
  End;
End;

Procedure ToggleMode;
Begin
  If UiGfx Then
  Begin
    GClose;
    TextOnly := True;
    UiTextOpen;
  End
  Else If GOpen(1024, 768) Then
  Begin
    TextOnly := False;
    UiGfxGrid;
  End;
End;

Procedure RescueShell;
Var Pid, St, Fd : LongInt;
Begin
  If UiMsgBox(Msg(M_WARN_T), Msg(M_SHELL_Q), Msg(M_YES), Msg(M_NO)) <> 1 Then
    Exit;
  If UiGfx Then GClose Else UiTextClose;
  InClose;
  SysPut(UiOutFd, #27'[0m'#27'[2J'#27'[H');
  Pid := SysFork;
  If Pid = 0 Then
  Begin
    SysSetSid;
    If InTtyName = '' Then Fd := SysOpen('/dev/tty1', O_RDWR, 0)
    Else Fd := SysOpen(InTtyName, O_RDWR, 0);
    If Fd >= 0 Then
    Begin
      SysDup2(Fd, 0);
      SysDup2(Fd, 1);
      SysDup2(Fd, 2);
      SysIoctlL(0, TIOCSCTTY, 0);
    End;
    SysArgReset;
    SysArgAdd('sh');
    SysEnvInherit;
    SysArgExec('/bin/sh');
    SysExit(127);
  End;
  If Pid > 0 Then SysWaitPid(Pid, St, 0);
  InOpen(TtyPath, Not TextOnly);
  InSetLayout(LayI);
  If TextOnly Then UiTextOpen Else UiGfxGrid;
End;

Function StepNo(S : LongInt) : LongInt;
Var N, I : LongInt;
Begin
  N := 0;
  For I := 0 To S Do
    If (PartMode = 2) Or ((I <> S_PED) And (I <> S_ROLE)) Then Inc(N);
  StepNo := N;
End;

Function StepTotal : LongInt;
Begin
  If PartMode = 2 Then StepTotal := 14 Else StepTotal := 12;
End;

{ debut de page : titre, aide, boutons de navigation }
Procedure BeginPage(Id : LongInt; Const Name : String);
Begin
  UiClear;
  UiHead := Msg(M_TITLE);
  UiTitle := Msg(M_STEP) + ' ' + NumS(StepNo(Id)) + '/' + NumS(StepTotal) +
             ' - ' + Name;
  UiFoot := Msg(M_FOOT);
  OpMark('page ' + NumS(Id));
End;

Procedure NavButtons(BackOk : Boolean; Const NextText : String);
Var Y, Wn, Wc, Wb, X : LongInt;
Begin
  Y := UiWh - 4;
  Wc := Length(Msg(M_CANCEL)) + 4;
  Wn := Length(NextText) + 4;
  Wb := Length(Msg(M_BACK)) + 4;
  X := UiCw - Wc;
  UiButton(NAV_CANCEL, X, Y, Wc, Msg(M_CANCEL), WF_CANCEL);
  X := X - Wn - 1;
  UiButton(NAV_NEXT, X, Y, Wn, NextText, WF_DEF);
  X := X - Wb - 1;
  If BackOk Then UiButton(NAV_BACK, X, Y, Wb, Msg(M_BACK), 0)
  Else UiButton(NAV_BACK, X, Y, Wb, Msg(M_BACK), WF_DIS);
End;

Function ConfirmQuit : Boolean;
Begin
  ConfirmQuit := UiMsgBox(Msg(M_CANCEL_T), Msg(M_CANCEL_Q), Msg(M_YES),
                          Msg(M_NO)) = 1;
End;

{ aide (F1) : page de texte sur les touches et la souris }
Procedure PageHelp;
Var R : LongInt;
Begin
  UiClear;
  UiHead := Msg(M_TITLE);
  UiTitle := Msg(M_HELP_T);
  UiFoot := Msg(M_FOOT);
  UiLabel(0, 0, UiCw, 4, Msg(M_HELP_1), 0);
  UiLabel(0, 5, UiCw, 3, Msg(M_HELP_2), 0);
  UiLabel(0, 9, UiCw, 3, Msg(M_HELP_3), 0);
  UiLabel(0, 13, UiCw, 3, Msg(M_HELP_4), WF_DIM);
  UiButton(NAV_NEXT, UiCw - Length(Msg(M_OK)) - 4, UiWh - 4,
           Length(Msg(M_OK)) + 4, Msg(M_OK), WF_DEF Or WF_CANCEL);
  UiSetFocusId(NAV_NEXT);
  Repeat
    R := UiRun(-1);
  Until (R = NAV_NEXT) Or (R = RES_REBUILD);
End;

{ boucle d'une page : gere F2, F3 et l'annulation ; rend un identifiant de
  bouton, une notification (>= 1000) ou RES_REBUILD }
Function PageRun : LongInt;
Var R : LongInt;
Begin
  Repeat
    R := UiRun(-1);
    If R = 2002 Then
    Begin
      RescueShell;
      R := RES_REBUILD;
    End
    Else If R = 2003 Then
    Begin
      ToggleMode;
      R := RES_REBUILD;
    End
    Else If R = 2001 Then
    Begin
      PageHelp;
      R := RES_REBUILD;
    End
    Else If R >= 2001 Then R := 0
    Else If R = NAV_CANCEL Then
    Begin
      If ConfirmQuit Then Quitting := True Else R := 0;
    End;
  Until R <> 0;
  PageRun := R;
End;

Procedure ErrBox(Const S : String);
Begin
  UiMsgBox(Msg(M_ERR_T), S, Msg(M_OK), '');
End;

{ ---- contenu existant d'un disque ---- }

{ detecte le contenu des partitions de DiskDev (type de systeme de fichiers,
  nom, et presence d'un systeme LINUX-0 : /boot/linux0) ; remplit ExistNote }
Procedure ScanExisting(Const DiskDev : String);
Var I : LongInt; Typ, Lbl, Uu, Line : String;
Begin
  ExistNote := '';
  ExistSys := False;
  Dsk := DiskDev;
  DkReadTable;
  For I := 1 To MAXPT Do
    If Pt[I].Used And Not DkIsExt(I) Then
    Begin
      Typ := ''; Lbl := ''; Uu := '';
      Probe(DkPartDev(I), Typ, Lbl, Uu);
      Line := DkPartDev(I) + ' ' + NumS(DkMb(Pt[I].Size)) + ' MB ';
      If Typ <> '' Then Line := Line + Typ Else Line := Line + '(' +
        HexByte(Pt[I].Typ) + ')';
      If Lbl <> '' Then Line := Line + ' "' + Lbl + '"';
      If (Typ = 'ext2') Or (Typ = 'ext3') Or (Typ = 'ext4') Then
      Begin
        SysMkdir('/probe', 493);
        If SysMount(DkPartDev(I), '/probe', Typ, MS_RDONLY) = 0 Then
        Begin
          If OpFileExists('/probe/boot/linux0') Then
          Begin
            Line := Line + ' - ' + Msg(M_EXIST_SYS);
            ExistSys := True;
          End;
          SysUmount('/probe');
        End;
      End;
      ExistNote := ExistNote + Line + #10;
    End;
End;

{ memoire totale en Mo (/proc/meminfo) }
Function MemMb : LongInt;
Var F, V, E : LongInt; L : String;
Begin
  MemMb := 0;
  F := SysOpen('/proc/meminfo', O_RDONLY, 0);
  If F < 0 Then Exit;
  While SysReadLine(F, L) Do
    If Copy(L, 1, 9) = 'MemTotal:' Then
    Begin
      Val(DkField(L, 2), V, E);
      If E = 0 Then MemMb := V Div 1024;
      Break;
    End;
  SysClose(F);
End;

{ ---- page : langue ---- }

Procedure BuildLang;
Var L, I, H : LongInt;
Begin
  BeginPage(S_LANG, Msg(M_LANG_T));
  UiLabel(0, 0, UiCw, 3, Msg(M_LANG_I), 0);
  H := UiCh - 6;
  If H > 9 Then H := 9;
  L := UiList(10, 0, 3, 32, H, WF_NOTIFY);
  For I := 0 To 6 Do UiListAdd(L, LangName[I]);
  UiWd[L].Val := Lang;
  NavButtons(False, Msg(M_NEXT));
  UiSetFocusId(10);
End;

Function PageLang : LongInt;
Var R : LongInt;
Begin
  Repeat
    BuildLang;
    R := PageRun;
    If R = RES_NOTIFY + 10 Then
    Begin
      Lang := UiSel(10);
      ApplyLangDefaults;
      R := RES_REBUILD;
    End;
  Until R <> RES_REBUILD;
  PageLang := R;
End;

{ ---- page : accueil ---- }

Function PageWelc : LongInt;
Var R, M : LongInt; T : String;
Begin
  Repeat
    BeginPage(S_WELC, Msg(M_WEL_T));
    UiLabel(0, 0, UiCw, 5, Msg(M_WEL_I), 0);
    If UiGfx Then T := Fmt(M_WEL_MODE_G, NumS(GW), NumS(GH), '')
    Else T := Msg(M_WEL_MODE_T);
    M := MemMb;
    DkScan;
    UiLabel(0, 6, UiCw, 1, T, WF_DIM);
    UiLabel(0, 7, UiCw, 1, Fmt(M_WEL_MEM, NumS(M), '', ''), WF_DIM);
    UiLabel(0, 8, UiCw, 1, Fmt(M_WEL_DISKS, NumS(DkCount), '', ''), WF_DIM);
    UiLabel(0, 10, UiCw, 5, Msg(M_WEL_KEYS), 0);
    If M < 100 Then UiLabel(0, 15, UiCw, 1, 'RAM < 100 MB', WF_ERR);
    NavButtons(True, Msg(M_NEXT));
    UiSetFocusId(NAV_NEXT);
    R := PageRun;
    If R >= RES_NOTIFY Then R := RES_REBUILD;
  Until R <> RES_REBUILD;
  PageWelc := R;
End;

{ ---- page : clavier ---- }

Var KeyTest : String;

Procedure BuildKey;
Var L, I, H : LongInt;
Begin
  BeginPage(S_KEY, Msg(M_KEY_T));
  UiLabel(0, 0, UiCw, 3, Msg(M_KEY_I), 0);
  H := UiCh - 8;
  If H > LayCount Then H := LayCount;
  L := UiList(10, 0, 3, 40, H, WF_NOTIFY);
  For I := 0 To LayCount - 1 Do UiListAdd(L, LayName[I]);
  UiWd[L].Val := LayI;
  UiListScroll(L);
  UiLabel(0, UiCh - 3, 10, 1, Msg(M_KEY_TEST), 0);
  UiEdit(11, 11, UiCh - 3, 40, KeyTest, 60, 0);
  NavButtons(True, Msg(M_NEXT));
  UiSetFocusId(10);
End;

Function PageKey : LongInt;
Var R, I : LongInt; CodeS : String;
Begin
  Repeat
    BuildKey;
    Repeat
      R := PageRun;
      If R = RES_NOTIFY + 10 Then
      Begin
        LayI := UiSel(10);
        LayTouched := True;
        InSetLayout(LayI);
        R := 0;
      End
      Else If R = RES_NOTIFY + 11 Then R := 0;
    Until R <> 0;
    KeyTest := UiGetText(11);
  Until R <> RES_REBUILD;
  CodeS := '';
  For I := 1 To Length(KeyTest) Do CodeS := CodeS + ' ' + NumS(Ord(KeyTest[I]));
  OpMark('keytest=' + KeyTest + ' layout=' + LayId[LayI] + ' codes=' + CodeS);
  PageKey := R;
End;

{ ---- page : fuseau horaire ---- }

Procedure BuildTz;
Var L, I, H, Sel : LongInt; C, Ci, Dt, Tm : String; Off : LongInt;
Begin
  BeginPage(S_TZ, Msg(M_TZ_T));
  UiLabel(0, 0, UiCw, 2, Msg(M_TZ_I), 0);
  H := UiCh - 7;
  UiLabel(0, 2, 30, 1, Msg(M_TZ_REG), WF_DIM);
  L := UiList(10, 0, 3, 30, H, WF_NOTIFY);
  For I := 0 To 10 Do UiListAdd(L, Msg(M_CN0 + I));
  UiWd[L].Val := TzCont;
  UiListScroll(L);
  UiLabel(32, 2, 30, 1, Msg(M_TZ_CITY), WF_DIM);
  LoadCities(TzCont);
  L := UiList(11, 32, 3, UiCw - 32, H, WF_NOTIFY);
  Sel := 0;
  TzSplit(TzName, C, Ci);
  For I := 0 To CityN - 1 Do
  Begin
    UiListAdd(L, Cities[I]);
    If (ContIndex(C) = TzCont) And (Cities[I] = Ci) Then Sel := I;
  End;
  UiWd[L].Val := Sel;
  UiListScroll(L);
  NowLocal(Dt, Tm, Off);
  UiLabel(0, UiCh - 3, UiCw, 1, Msg(M_TZ_NOW) + ' ' + Dt + ' ' + Tm + '  (' +
          OffStr(Off) + ')', 0);
  NavButtons(True, Msg(M_NEXT));
  UiSetFocusId(11);
End;

Function PageTz : LongInt;
Var R, I : LongInt; C, Ci : String;
Begin
  TzSplit(TzName, C, Ci);
  TzCont := ContIndex(C);
  Repeat
    BuildTz;
    Repeat
      R := PageRun;
      If R = RES_NOTIFY + 10 Then
      Begin
        TzCont := UiSel(10);
        LoadCities(TzCont);
        If CityN > 0 Then
        Begin
          If TzCont = 10 Then TzName := Cities[0]
          Else TzName := ContDir[TzCont] + '/' + Cities[0];
        End;
        TzTouched := True;
        R := RES_REBUILD;
      End
      Else If R = RES_NOTIFY + 11 Then
      Begin
        I := UiSel(11);
        If (I >= 0) And (I < CityN) Then
        Begin
          If TzCont = 10 Then TzName := Cities[I]
          Else TzName := ContDir[TzCont] + '/' + Cities[I];
          TzTouched := True;
        End;
        R := RES_REBUILD;
      End;
    Until R <> 0;
  Until R <> RES_REBUILD;
  PageTz := R;
End;

{ ---- page : date et heure ---- }

Function ParseDate(Const S : String; Var Y, M, D : LongInt) : Boolean;
Var E : LongInt;
Begin
  ParseDate := False;
  If (Length(S) <> 10) Or (S[5] <> '-') Or (S[8] <> '-') Then Exit;
  Val(Copy(S, 1, 4), Y, E);
  If E <> 0 Then Exit;
  Val(Copy(S, 6, 2), M, E);
  If E <> 0 Then Exit;
  Val(Copy(S, 9, 2), D, E);
  If E <> 0 Then Exit;
  ParseDate := (Y >= 2000) And (Y <= 2099) And (M >= 1) And (M <= 12) And
               (D >= 1) And (D <= 31);
End;

Function ParseTime(Const S : String; Var H, M, Sc : LongInt) : Boolean;
Var E : LongInt;
Begin
  ParseTime := False;
  If (Length(S) <> 8) Or (S[3] <> ':') Or (S[6] <> ':') Then Exit;
  Val(Copy(S, 1, 2), H, E);
  If E <> 0 Then Exit;
  Val(Copy(S, 4, 2), M, E);
  If E <> 0 Then Exit;
  Val(Copy(S, 7, 2), Sc, E);
  If E <> 0 Then Exit;
  ParseTime := (H >= 0) And (H < 24) And (M >= 0) And (M < 60) And (Sc >= 0)
               And (Sc < 60);
End;

Var ClkDt0, ClkTm0 : String;

Procedure BuildClk;
Var Dt, Tm : String; Off : LongInt;
Begin
  BeginPage(S_CLK, Msg(M_CLK_T));
  If ClkDate = '' Then
  Begin
    NowLocal(Dt, Tm, Off);
    ClkDate := Dt;
    ClkTime := Tm;
    ClkDt0 := Dt;
    ClkTm0 := Tm;
  End;
  UiLabel(0, 0, UiCw, 3, Msg(M_CLK_I), 0);
  UiLabel(0, 4, 26, 1, Msg(M_CLK_DATE), 0);
  UiEdit(10, 27, 4, 12, ClkDate, 10, 0);
  UiLabel(0, 6, 26, 1, Msg(M_CLK_TIME), 0);
  UiEdit(11, 27, 6, 10, ClkTime, 8, 0);
  UiRadio(12, 1, 0, 9, UiCw, Msg(M_CLK_UTC), ClkUtc = 1, 0);
  UiRadio(13, 1, 0, 10, UiCw, Msg(M_CLK_LOC), ClkUtc = 0, 0);
  NavButtons(True, Msg(M_NEXT));
  UiSetFocusId(10);
End;

Function PageClk : LongInt;
Var R, Y, M, D, H, Mi, S : LongInt;
Begin
  Repeat
    BuildClk;
    Repeat
      R := PageRun;
      ClkDate := UiGetText(10);
      ClkTime := UiGetText(11);
      If UiChecked(12) Then ClkUtc := 1 Else ClkUtc := 0;
      If R = NAV_NEXT Then
        If Not (ParseDate(ClkDate, Y, M, D) And ParseTime(ClkTime, H, Mi, S))
        Then
        Begin
          ErrBox(Msg(M_CLK_BAD));
          R := 0;
        End;
      If (R >= RES_NOTIFY) Then R := 0;
    Until R <> 0;
  Until R <> RES_REBUILD;
  PageClk := R;
End;

{ ---- pages : nom de la machine, comptes ---- }

Function ValidHost(Const S : String) : Boolean;
Var I : LongInt; C : Char;
Begin
  ValidHost := False;
  If (Length(S) < 1) Or (Length(S) > 63) Or (S[1] = '-') Or (S[1] = '.') Then
    Exit;
  For I := 1 To Length(S) Do
  Begin
    C := S[I];
    If Not (((C >= 'a') And (C <= 'z')) Or ((C >= 'A') And (C <= 'Z')) Or
            ((C >= '0') And (C <= '9')) Or (C = '-') Or (C = '.')) Then Exit;
  End;
  ValidHost := True;
End;

Function PageHost : LongInt;
Var R : LongInt;
Begin
  Repeat
    BeginPage(S_HOST, Msg(M_HOST_T));
    UiLabel(0, 0, UiCw, 3, Msg(M_HOST_I), 0);
    UiLabel(0, 4, 26, 1, Msg(M_HOST_L), 0);
    UiEdit(10, 27, 4, 30, Host, 63, 0);
    NavButtons(True, Msg(M_NEXT));
    UiSetFocusId(10);
    Repeat
      R := PageRun;
      Host := UiGetText(10);
      If (R = NAV_NEXT) And Not ValidHost(Host) Then
      Begin
        ErrBox(Msg(M_HOST_BAD));
        R := 0;
      End;
      If R >= RES_NOTIFY Then R := 0;
    Until R <> 0;
  Until R <> RES_REBUILD;
  PageHost := R;
End;

Var RootPw2, UserPw2 : String;

Function ValidUser(Const S : String) : Boolean;
Var I : LongInt; C : Char;
Begin
  ValidUser := False;
  If (Length(S) < 1) Or (Length(S) > 31) Then Exit;
  If Not ((S[1] >= 'a') And (S[1] <= 'z')) Then Exit;
  For I := 1 To Length(S) Do
  Begin
    C := S[I];
    If Not (((C >= 'a') And (C <= 'z')) Or ((C >= '0') And (C <= '9')) Or
            (C = '-') Or (C = '_')) Then Exit;
  End;
  ValidUser := True;
End;

Function ReservedUser(Const S : String) : Boolean;
Begin
  ReservedUser := (S = 'root') Or (S = 'daemon') Or (S = 'bin') Or
    (S = 'sys') Or (S = 'nobody') Or (S = 'sync') Or (S = 'games') Or
    (S = 'man') Or (S = 'mail') Or (S = 'news') Or (S = 'www-data');
End;

Function PageAcc : LongInt;
Var R : LongInt;
Begin
  Repeat
    BeginPage(S_ACC, Msg(M_ACC_T));
    UiLabel(0, 0, UiCw, 3, Msg(M_ACC_I), 0);
    UiLabel(0, 4, 28, 1, Msg(M_ACC_ROOT), 0);
    UiEdit(10, 29, 4, 28, RootPw, 40, WF_PWD);
    UiLabel(0, 5, 28, 1, Msg(M_ACC_AGAIN), 0);
    UiEdit(11, 29, 5, 28, RootPw2, 40, WF_PWD);
    UiLabel(0, 7, 28, 1, Msg(M_ACC_FULL), 0);
    UiEdit(12, 29, 7, 28, UserFull, 40, 0);
    UiLabel(0, 8, 28, 1, Msg(M_ACC_USER), 0);
    UiEdit(13, 29, 8, 28, UserName, 31, 0);
    UiLabel(0, 9, 28, 1, Msg(M_ACC_PW), 0);
    UiEdit(14, 29, 9, 28, UserPw, 40, WF_PWD);
    UiLabel(0, 10, 28, 1, Msg(M_ACC_AGAIN), 0);
    UiEdit(15, 29, 10, 28, UserPw2, 40, WF_PWD);
    NavButtons(True, Msg(M_NEXT));
    UiSetFocusId(10);
    Repeat
      R := PageRun;
      RootPw := UiGetText(10);
      RootPw2 := UiGetText(11);
      UserFull := UiGetText(12);
      UserName := UiGetText(13);
      UserPw := UiGetText(14);
      UserPw2 := UiGetText(15);
      If R = NAV_NEXT Then
      Begin
        If RootPw = '' Then
        Begin
          ErrBox(Msg(M_ACC_E_ROOT));
          R := 0;
        End
        Else If RootPw <> RootPw2 Then
        Begin
          ErrBox(Msg(M_ACC_E_MATCH));
          R := 0;
        End
        Else If (UserName <> '') And Not ValidUser(UserName) Then
        Begin
          ErrBox(Msg(M_ACC_E_USER));
          R := 0;
        End
        Else If (UserName <> '') And ReservedUser(UserName) Then
        Begin
          ErrBox(Msg(M_ACC_E_RES));
          R := 0;
        End
        Else If (UserName <> '') And (UserPw <> UserPw2) Then
        Begin
          ErrBox(Msg(M_ACC_E_MATCH));
          R := 0;
        End;
      End;
      If R >= RES_NOTIFY Then R := 0;
    Until R <> 0;
  Until R <> RES_REBUILD;
  PageAcc := R;
End;

{ ---- page : disque ---- }

Function PageDisk : LongInt;
Var R, I, L : LongInt;
Begin
  Repeat
    DkScan;
    BeginPage(S_DISK, Msg(M_DISK_T));
    UiLabel(0, 0, UiCw, 3, Msg(M_DISK_I), 0);
    If DkCount = 0 Then
    Begin
      UiLabel(0, 4, UiCw, 2, Msg(M_DISK_NONE), WF_ERR);
      NavButtons(True, Msg(M_NEXT));
      UiSetEnabled(NAV_NEXT, False);
    End
    Else
    Begin
      L := UiList(10, 0, 4, 50, 4, WF_NOTIFY);
      For I := 0 To DkCount - 1 Do
        UiListAdd(L, PadR('/dev/' + DkName[I], 14) +
                  PadL(NumS(DkMb(DkSize[I])), 8) + ' ' +
                  ' MB');
      If DiskIx >= DkCount Then DiskIx := 0;
      UiWd[L].Val := DiskIx;
      ScanExisting('/dev/' + DkName[DiskIx]);
      OpMark('existing ' + ExistNote);
      If ExistNote = '' Then
        UiLabel(0, 9, UiCw, 1, Msg(M_EXIST_L) + ' ' + Msg(M_EXIST_NONE),
                WF_DIM)
      Else
        UiLabel(0, 9, UiCw, UiCh - 14, Msg(M_EXIST_L) + #10 + ExistNote,
                WF_ERR);
      NavButtons(True, Msg(M_NEXT));
      UiSetFocusId(10);
    End;
    R := PageRun;
    If DkCount > 0 Then DiskIx := UiSel(10);
    If R >= RES_NOTIFY Then R := RES_REBUILD;
  Until R <> RES_REBUILD;
  If (R = NAV_NEXT) And (DkCount > 0) Then
  Begin
    DiskPath := '/dev/' + DkName[DiskIx];
    Dsk := DiskPath;
  End;
  PageDisk := R;
End;

{ ---- page : methode de partitionnement ---- }

Function PageMeth : LongInt;
Var R, Mb, E, Sz : LongInt;
Begin
  { taille de swap proposee : un quart du disque, 256 Mo au plus }
  If Not SwapEdited Then
  Begin
    Mb := DkSectors(DiskPath) Div 2048 Div 4;
    If Mb > 256 Then Mb := 256;
    If Mb < 8 Then Mb := 8;
    SwapMb := NumS(Mb);
  End;
  Repeat
    BeginPage(S_METH, Msg(M_METH_T));
    UiLabel(0, 0, UiCw, 2, Fmt(M_METH_I, DiskPath, '', ''), 0);
    UiRadio(10, 1, 0, 2, UiCw, Msg(M_METH_GUIDED), PartMode = 1, WF_NOTIFY);
    UiRadio(11, 1, 0, 3, UiCw, Msg(M_METH_MANUAL), PartMode = 2, WF_NOTIFY);
    UiCheck(12, 3, 5, UiCw - 3, Msg(M_METH_SWAP), UseSwap, WF_NOTIFY);
    UiLabel(3, 6, 28, 1, Msg(M_METH_SWAPMB), 0);
    UiEdit(13, 32, 6, 8, SwapMb, 6, 0);
    UiLabel(0, 8, UiCw, 1, Msg(M_METH_FS), 0);
    UiRadio(14, 2, 3, 9, 10, 'ext4', FsKind = 4, 0);
    UiRadio(15, 2, 16, 9, 10, 'ext3', FsKind = 3, 0);
    UiRadio(16, 2, 29, 9, 10, 'ext2', FsKind = 2, 0);
    NavButtons(True, Msg(M_NEXT));
    UiSetFocusId(10);
    Repeat
      R := PageRun;
      If UiChecked(10) Then PartMode := 1 Else PartMode := 2;
      UseSwap := UiChecked(12);
      If UiGetText(13) <> SwapMb Then SwapEdited := True;
      SwapMb := UiGetText(13);
      If UiChecked(14) Then FsKind := 4
      Else If UiChecked(15) Then FsKind := 3
      Else FsKind := 2;
      If R = NAV_NEXT Then
      Begin
        If DkSectors(DiskPath) < 64 * 2048 Then
        Begin
          ErrBox(Msg(M_METH_E_SMALL));
          R := 0;
        End
        Else If (PartMode = 1) And UseSwap Then
        Begin
          Val(SwapMb, Mb, E);
          Sz := DkSectors(DiskPath) Div 2048;
          If (E <> 0) Or (Mb < 8) Or (Mb > Sz Div 2) Then
          Begin
            ErrBox(Msg(M_METH_E_SWAP));
            R := 0;
          End;
        End;
      End;
      If R >= RES_NOTIFY Then R := 0;
    Until R <> 0;
  Until R <> RES_REBUILD;
  PageMeth := R;
End;

{ ---- plan de partitionnement assiste ---- }

Procedure GuidedPlan;
Var Mb, E, Tot, Root, S : LongInt;
Begin
  Dsk := DiskPath;
  DskSec := DkSectors(Dsk);
  DkClearTable;
  Tot := DskSec;
  Mb := 0;
  If UseSwap Then
  Begin
    Val(SwapMb, Mb, E);
    If E <> 0 Then Mb := 0;
  End;
  Root := Tot - ALIGN_SEC - Mb * 2048;
  { une racine ext2/3/4 ne depasse pas 30 Go : le reste reste libre }
  If Root > 30000 * 2048 Then Root := 30000 * 2048;
  S := DkCreate(0, Root, PT_LINUX);
  If S > 0 Then
  Begin
    Pt[S].Active := True;
    Pt[S].Role := ROLE_ROOT;
  End;
  If Mb > 0 Then
  Begin
    S := DkCreate(0, Mb * 2048, PT_SWAP);
    If S > 0 Then Pt[S].Role := ROLE_SWAP;
  End;
End;

{ ---- page : editeur de partitions ---- }

Function HexByte(V : LongInt) : String;
Const Hx : String[16] = '0123456789ABCDEF';
Begin
  HexByte := Hx[(V Shr 4) And 15 + 1] + Hx[V And 15 + 1];
End;

Function TypeName(T : LongInt) : String;
Begin
  Case T Of
    $83 : TypeName := Msg(M_PED_TLINUX);
    $82 : TypeName := Msg(M_PED_TSWAP);
    $07 : TypeName := 'NTFS/HPFS (07)';
    $0B, $0C : TypeName := 'FAT32 (' + OpNum2(T) + ')';
    $05, $0F : TypeName := Msg(M_PED_TEXT);
    $EF : TypeName := 'EFI (EF)';
  Else
    TypeName := '(' + HexByte(T) + ')';
  End;
End;

Procedure BuildPedRows(Var L : LongInt);
Var I, K, J, T, Gs, Gz : LongInt; Pos_ : Array[0..31] Of LongInt; Line : String;
Begin
  PedN := 0;
  { cle de tri : 2 x debut ; les logiques et leurs plages libres : + 1, pour
    que l'etendue precede son contenu }
  For I := 1 To MAXPT Do
    If Pt[I].Used And (PedN < 30) Then
    Begin
      PedKind[PedN] := 1;
      PedIdx[PedN] := I;
      Pos_[PedN] := Pt[I].Start * 2;
      If I > 4 Then Pos_[PedN] := Pos_[PedN] + 1;
      Inc(PedN);
    End;
  K := 0;
  While DkGap(K, Gs, Gz) And (PedN < 30) Do
  Begin
    PedKind[PedN] := 2;
    PedIdx[PedN] := K;
    Pos_[PedN] := Gs * 2;
    Inc(PedN);
    Inc(K);
  End;
  K := 0;
  While DkLgGap(K, Gs, Gz) And (PedN < 30) Do
  Begin
    PedKind[PedN] := 3;
    PedIdx[PedN] := K;
    Pos_[PedN] := Gs * 2 + 1;
    Inc(PedN);
    Inc(K);
  End;
  For I := 0 To PedN - 2 Do
    For J := I + 1 To PedN - 1 Do
      If Pos_[J] < Pos_[I] Then
      Begin
        T := PedKind[I]; PedKind[I] := PedKind[J]; PedKind[J] := T;
        T := PedIdx[I]; PedIdx[I] := PedIdx[J]; PedIdx[J] := T;
        T := Pos_[I]; Pos_[I] := Pos_[J]; Pos_[J] := T;
      End;
  For I := 0 To PedN - 1 Do
  Begin
    If PedKind[I] = 1 Then
    Begin
      K := PedIdx[I];
      If Pt[K].Active Then Line := '*' Else Line := ' ';
      Line := PadR(NumS(K), 4) + PadR(Line, 6) +
              PadL(NumS(DkMb(Pt[K].Start)), 10) + '  ' +
              PadL(NumS(DkMb(Pt[K].Size)), 10) + '  ' + TypeName(Pt[K].Typ);
    End
    Else
    Begin
      If PedKind[I] = 2 Then DkGap(PedIdx[I], Gs, Gz)
      Else DkLgGap(PedIdx[I], Gs, Gz);
      Line := PadR('-', 10) + PadL(NumS(DkMb(Gs)), 10) + '  ' +
              PadL(NumS(DkMb(Gz)), 10) + '  ' + Msg(M_PED_FREE);
      If PedKind[I] = 3 Then Line := Line + ' (' + Msg(M_PED_LOGIC) + ')';
    End;
    UiListAdd(L, Line);
  End;
End;

{ taille saisie ("500M", "2G", "1024", vide = tout) en secteurs ; -1 si
  invalide }
Function ParseSize(Const S : String; Max : LongInt) : LongInt;
Var T : String; Mult, V, E, N : LongInt;
Begin
  ParseSize := -1;
  T := S;
  While (Length(T) > 0) And (T[Length(T)] = ' ') Do Delete(T, Length(T), 1);
  If T = '' Then
  Begin
    ParseSize := Max;
    Exit;
  End;
  Mult := 1;
  N := Length(T);
  If (T[N] = 'G') Or (T[N] = 'g') Then
  Begin
    Mult := 1024;
    Delete(T, N, 1);
  End
  Else If (T[N] = 'M') Or (T[N] = 'm') Then Delete(T, N, 1);
  Val(T, V, E);
  If (E <> 0) Or (V < 1) Or (V > 4000000) Then Exit;
  V := V * Mult;
  If V * 2048 > Max Then Exit;
  ParseSize := V * 2048;
End;

Var NewGap, NewTyp, NewKind : LongInt;   { NewKind : 2 primaire, 3 logique }

{ sous-page : nouvelle partition dans l'espace libre NewGap }
Function PageNewPart : Boolean;
Var R, Gs, Gz, Sz, Slot : LongInt; SzS : String;
Begin
  PageNewPart := False;
  If NewKind = 3 Then
  Begin
    If Not DkLgGap(NewGap, Gs, Gz) Then Exit;
    Gz := Gz - ALIGN_SEC;
  End
  Else If Not DkGap(NewGap, Gs, Gz) Then Exit;
  SzS := '';
  NewTyp := PT_LINUX;
  Repeat
    UiClear;
    UiHead := Msg(M_TITLE);
    UiTitle := Msg(M_PED_T) + ' - ' + Msg(M_PED_NEWT);
    UiFoot := Msg(M_FOOT);
    UiLabel(0, 0, UiCw, 2, Fmt(M_PED_I, Dsk, '', ''), WF_DIM);
    UiLabel(0, 3, UiCw, 1, Msg(M_PED_SIZE), 0);
    UiEdit(10, 0, 4, 14, SzS, 10, 0);
    UiLabel(16, 4, 30, 1, '(max ' + NumS(DkMb(Gz)) + ' MB)', WF_DIM);
    UiRadio(11, 1, 0, 6, 40, Msg(M_PED_TLINUX), NewTyp = PT_LINUX, 0);
    UiRadio(12, 1, 0, 7, 40, Msg(M_PED_TSWAP), NewTyp = PT_SWAP, 0);
    If (NewKind = 2) And (DkExt = 0) Then
      UiRadio(13, 1, 0, 8, 50, Msg(M_PED_TEXT), NewTyp = PT_EXT, 0);
    NavButtons(True, Msg(M_OK));
    UiSetFocusId(10);
    Repeat
      R := PageRun;
      SzS := UiGetText(10);
      If UiChecked(12) Then NewTyp := PT_SWAP Else NewTyp := PT_LINUX;
      If (NewKind = 2) And (DkExt = 0) Then
        If UiChecked(13) Then NewTyp := PT_EXT;
      If R = NAV_NEXT Then
      Begin
        Sz := ParseSize(SzS, Gz Div 2048 * 2048);
        If Sz < 2048 Then
        Begin
          ErrBox(Msg(M_PED_ERRSIZE));
          R := 0;
        End
        Else
        Begin
          If NewKind = 3 Then Slot := DkCreateLog(NewGap, Sz, NewTyp)
          Else Slot := DkCreate(NewGap, Sz, NewTyp);
          If Slot = 0 Then
          Begin
            ErrBox(Msg(M_PED_NOSLOT));
            R := 0;
          End
          Else PageNewPart := True;
        End;
      End;
      If R >= RES_NOTIFY Then R := 0;
    Until R <> 0;
  Until R <> RES_REBUILD;
End;

Function PagePed : LongInt;
Var R, L, Sel, K, Q, X : LongInt; T : String;
Begin
  Sel := 0;
  Repeat
    BeginPage(S_PED, Msg(M_PED_T));
    UiLabel(0, 0, UiCw, 2, Fmt(M_PED_I, Dsk, '', ''), 0);
    UiLabel(1, 2, UiCw, 1, PadR(Msg(M_PED_HN), 4) + PadR(Msg(M_PED_HB), 6) +
            PadL(Msg(M_PED_HS), 10) + '  ' + PadL(Msg(M_PED_HZ), 10) + '  ' +
            Msg(M_PED_TYPE), WF_DIM);
    L := UiList(10, 0, 3, UiCw, UiCh - 8, 0);
    BuildPedRows(L);
    If Sel < UiWd[L].Cnt Then UiWd[L].Val := Sel;
    UiListScroll(L);
    X := 0;
    For K := 0 To 4 Do
    Begin
      Case K Of
        0 : T := Msg(M_PED_NEW);
        1 : T := Msg(M_PED_DEL);
        2 : T := Msg(M_PED_TYPE);
        3 : T := Msg(M_PED_BOOT);
      Else
        T := Msg(M_PED_CLEAR);
      End;
      UiButton(20 + K, X, UiCh - 4, 0, T, 0);
      X := X + Length(T) + 5;
    End;
    NavButtons(True, Msg(M_NEXT));
    UiSetFocusId(10);
    Repeat
      R := PageRun;
      Sel := UiSel(10);
      If R = 20 Then
      Begin
        If (Sel >= 0) And (Sel < PedN) And (PedKind[Sel] >= 2) Then
        Begin
          If (PedKind[Sel] = 2) And (DkFreeSlot = 0) Then
            ErrBox(Msg(M_PED_NOSLOT))
          Else If (PedKind[Sel] = 3) And (DkLogCount >= MAXPT - 4) Then
            ErrBox(Msg(M_PED_NOSLOT))
          Else
          Begin
            NewGap := PedIdx[Sel];
            NewKind := PedKind[Sel];
            PageNewPart;
          End;
        End
        Else ErrBox(Msg(M_PED_NOSPACE));
        R := RES_REBUILD;
      End
      Else If R = 21 Then
      Begin
        If (Sel >= 0) And (Sel < PedN) And (PedKind[Sel] = 1) Then
          If UiMsgBox(Msg(M_WARN_T), Fmt(M_PED_CONFDEL, NumS(PedIdx[Sel]), '',
             ''), Msg(M_YES), Msg(M_NO)) = 1 Then
            DkDelete(PedIdx[Sel]);
        R := RES_REBUILD;
      End
      Else If R = 22 Then
      Begin
        If (Sel >= 0) And (Sel < PedN) And (PedKind[Sel] = 1) Then
        Begin
          K := PedIdx[Sel];
          If Not DkIsExt(K) Then
            If Pt[K].Typ = PT_LINUX Then Pt[K].Typ := PT_SWAP
            Else Pt[K].Typ := PT_LINUX;
        End;
        R := RES_REBUILD;
      End
      Else If R = 23 Then
      Begin
        If (Sel >= 0) And (Sel < PedN) And (PedKind[Sel] = 1) And
           (PedIdx[Sel] <= 4) And Not DkIsExt(PedIdx[Sel]) Then
        Begin
          K := PedIdx[Sel];
          Pt[K].Active := Not Pt[K].Active;
          If Pt[K].Active Then
            For Q := 1 To 4 Do
              If Q <> K Then Pt[Q].Active := False;
        End;
        R := RES_REBUILD;
      End
      Else If R = 24 Then
      Begin
        If UiMsgBox(Msg(M_WARN_T), Msg(M_PED_CONFCLR), Msg(M_YES),
                    Msg(M_NO)) = 1 Then DkClearTable;
        R := RES_REBUILD;
      End
      Else If R >= RES_NOTIFY Then R := 0;
      If R = RES_REBUILD Then Break;
    Until R <> 0;
  Until R <> RES_REBUILD;
  PagePed := R;
End;

{ ---- page : roles des partitions ---- }

{ systeme de fichiers de la partition I : le sien, sinon le defaut }
Function PartFs(I : LongInt) : LongInt;
Begin
  If (Pt[I].Fs >= 2) And (Pt[I].Fs <= 4) Then PartFs := Pt[I].Fs
  Else PartFs := FsKind;
End;

Function RoleText(R : LongInt) : String;
Begin
  Case R Of
    ROLE_ROOT : RoleText := Msg(M_ROLE_ROOT);
    ROLE_SWAP : RoleText := Msg(M_ROLE_SWAP);
    ROLE_HOME : RoleText := Msg(M_ROLE_HOME);
  Else
    RoleText := Msg(M_ROLE_NONE);
  End;
End;

{ role et systeme de fichiers d'une partition }
Function RoleLine(I : LongInt) : String;
Var T : String;
Begin
  T := RoleText(Pt[I].Role);
  If (Pt[I].Role = ROLE_ROOT) Or (Pt[I].Role = ROLE_HOME) Then
    T := T + ' ' + FsName[PartFs(I)];
  RoleLine := T;
End;

Procedure AutoRoles;
Var I, Nr : LongInt;
Begin
  Nr := 0;
  For I := 1 To MAXPT Do
    If Pt[I].Used And (Pt[I].Role = ROLE_ROOT) Then Inc(Nr);
  For I := 1 To MAXPT Do
    If Pt[I].Used And Not DkIsExt(I) Then
    Begin
      If (Pt[I].Role = ROLE_NONE) Then
      Begin
        If Pt[I].Typ = PT_SWAP Then Pt[I].Role := ROLE_SWAP
        Else If (Pt[I].Typ = PT_LINUX) And (Nr = 0) And (I <= 4) Then
        Begin
          Pt[I].Role := ROLE_ROOT;
          Inc(Nr);
        End;
      End;
    End;
End;

{ donne le role R a la partition K et le retire aux autres }
Procedure SetRole(K, R : LongInt);
Var I : LongInt;
Begin
  If R <> ROLE_NONE Then
    For I := 1 To MAXPT Do
      If (I <> K) And (Pt[I].Role = R) Then Pt[I].Role := ROLE_NONE;
  Pt[K].Role := R;
End;

Function PageRole : LongInt;
Var R, L, I, N, Sel, K : LongInt; Map : Array[0..11] Of LongInt; Nr : LongInt;
Begin
  AutoRoles;
  Sel := 0;
  Repeat
    BeginPage(S_ROLE, Msg(M_ROLE_T));
    UiLabel(0, 0, UiCw, 3, Msg(M_ROLE_I), 0);
    L := UiList(10, 0, 4, UiCw, 6, 0);
    N := 0;
    For I := 1 To MAXPT Do
      If Pt[I].Used And Not DkIsExt(I) Then
      Begin
        Map[N] := I;
        UiListAdd(L, PadR(DkPartDev(I), 12) + PadL(NumS(DkMb(Pt[I].Size)), 8) +
          ' MB  ' + PadR(TypeName(Pt[I].Typ), 16) + ' ' +
          RoleLine(I));
        Inc(N);
      End;
    If Sel < N Then UiWd[L].Val := Sel;
    UiButton(20, 0, 11, 0, Msg(M_ROLE_B), 0);
    UiButton(21, Length(Msg(M_ROLE_B)) + 6, 11, 0, Msg(M_ROLE_FSB), 0);
    UiLabel(0, 13, UiCw, 1, Msg(M_ROLE_FS), 0);
    UiRadio(14, 2, 3, 14, 10, 'ext4', FsKind = 4, WF_NOTIFY);
    UiRadio(15, 2, 16, 14, 10, 'ext3', FsKind = 3, WF_NOTIFY);
    UiRadio(16, 2, 29, 14, 10, 'ext2', FsKind = 2, WF_NOTIFY);
    NavButtons(True, Msg(M_NEXT));
    UiSetFocusId(10);
    Repeat
      R := PageRun;
      Sel := UiSel(10);
      If R >= RES_NOTIFY Then
      Begin
        { nouveau systeme de fichiers par defaut pour toutes les partitions }
        If UiChecked(14) Then FsKind := 4
        Else If UiChecked(15) Then FsKind := 3
        Else FsKind := 2;
        For K := 1 To MAXPT Do Pt[K].Fs := 0;
        R := RES_REBUILD;
      End;
      If R = 20 Then
      Begin
        If (Sel >= 0) And (Sel < N) Then
        Begin
          K := Map[Sel];
          SetRole(K, (Pt[K].Role + 1) Mod 4);
        End;
        R := RES_REBUILD;
      End
      Else If R = 21 Then
      Begin
        If (Sel >= 0) And (Sel < N) Then
        Begin
          K := Map[Sel];
          Pt[K].Fs := PartFs(K) - 1;
          If Pt[K].Fs < 2 Then Pt[K].Fs := 4;
        End;
        R := RES_REBUILD;
      End
      Else If R = NAV_NEXT Then
      Begin
        Nr := 0;
        K := 0;
        For I := 1 To MAXPT Do
          If Pt[I].Used And (Pt[I].Role = ROLE_ROOT) Then
          Begin
            Inc(Nr);
            K := I;
          End;
        If Nr <> 1 Then
        Begin
          ErrBox(Msg(M_ROLE_E_ROOT));
          R := 0;
        End
        Else If K > 4 Then
        Begin
          ErrBox(Msg(M_ROLE_E_PRIM));
          R := 0;
        End
        Else If Pt[K].Size < 64 * 2048 Then
        Begin
          ErrBox(Msg(M_ROLE_E_SMALL));
          R := 0;
        End;
      End
      Else If R >= RES_NOTIFY Then R := 0;
    Until R <> 0;
  Until R <> RES_REBUILD;
  PageRole := R;
End;

{ ---- page : recapitulatif ---- }

Function RootPart : LongInt;
Var I : LongInt;
Begin
  RootPart := 0;
  For I := 1 To MAXPT Do
    If Pt[I].Used And (Pt[I].Role = ROLE_ROOT) Then RootPart := I;
End;

Function PageSum : LongInt;
Var R, I, N : LongInt; T, U : String;
Begin
  If PartMode = 1 Then GuidedPlan;
  Repeat
    BeginPage(S_SUM, Msg(M_SUM_T));
    If UserName = '' Then U := Msg(M_SUM_NOUSER) Else U := UserName;
    T := Fmt(M_SUM_LANG, LangName[Lang], '', '') + #10 +
         Fmt(M_SUM_KEY, LayName[LayI], '', '') + #10 +
         Fmt(M_SUM_TZ, TzName, '', '') + #10 +
         Fmt(M_SUM_HOST, Host, '', '') + #10 +
         Fmt(M_SUM_USER, U, '', '') + #10 +
         Fmt(M_SUM_DISK, DiskPath, NumS(DkMb(DkSectors(DiskPath))), '');
    UiLabel(0, 0, UiCw, 6, T, 0);
    N := 0;
    T := '';
    For I := 1 To MAXPT Do
      If Pt[I].Used And Not DkIsExt(I) Then
      Begin
        If N > 0 Then T := T + #10;
        T := T + Fmt(M_SUM_PART, DkPartDev(I), NumS(DkMb(Pt[I].Size)),
                     RoleLine(I));
        Inc(N);
      End;
    UiLabel(0, 6, UiCw, 5, T, WF_DIM);
    If ExistNote <> '' Then
      UiLabel(0, 11, UiCw, UiCh - 14, Msg(M_SUM_EXIST) + #10 + ExistNote,
              WF_ERR);
    UiCheck(30, 0, UiCh - 2, UiCw, Fmt(M_SUM_CONF, DiskPath, '', ''), False,
            WF_NOTIFY Or WF_ERR);
    NavButtons(True, Msg(M_INSTALL));
    UiSetEnabled(NAV_NEXT, False);
    UiSetFocusId(30);
    Repeat
      R := PageRun;
      If R >= RES_NOTIFY Then
      Begin
        UiSetEnabled(NAV_NEXT, UiChecked(30));
        R := 0;
      End
      Else If R = NAV_NEXT Then
        If UiMsgBox(Msg(M_WARN_T), Msg(M_SUM_ASK), Msg(M_YES), Msg(M_NO)) <> 1
        Then R := 0;
    Until R <> 0;
  Until R <> RES_REBUILD;
  PageSum := R;
End;

{ ---- installation ---- }

Procedure OpUiHook(Const S : String; Permille : LongInt);
Var Now_ : LongInt; Force : Boolean;
Begin
  Force := False;
  If NoUi Or (InstProgW < 0) Then
  Begin
    If S <> '' Then SysPut(2, UiAscii(S) + #10);
    Exit;
  End;
  If S <> '' Then
  Begin
    UiLogAdd(InstLogW, S);
    Force := True;
  End;
  If Permille >= 0 Then
    UiSetProg(41, StageBase + Permille * StageSpan Div 1000);
  Now_ := GetTickCount;
  If Force Or (Now_ - LastDraw > 120) Or (Now_ - LastDraw < 0) Then
  Begin
    LastDraw := Now_;
    UiRedraw;
  End;
End;

Procedure InstStage(N, Base, Span : LongInt);
Begin
  StageBase := Base;
  StageSpan := Span;
  If Not NoUi Then
  Begin
    UiSetText(42, Msg(M_INST_1 + N - 1));
    UiSetProg(41, Base);
    UiRedraw;
  End;
  OpLog(Msg(M_INST_1 + N - 1));
End;


Function RootDev : String;
Begin
  RootDev := DkPartDev(RootPart);
End;

Function CfgRewrite(Const Path, Drop1, Drop2, Pre, Post : String) : Boolean;
Var Fi, Fo : LongInt; L, Tmp : String;
Begin
  CfgRewrite := False;
  Tmp := TGT + Path + '.new';
  Fo := SysOpen(Tmp, O_WRONLY Or O_CREAT Or O_TRUNC, 420);
  If Fo < 0 Then
  Begin
    OpErr := Tmp + ' : ' + SysErrorText(SysErrno);
    Exit;
  End;
  If Pre <> '' Then SysWrite(Fo, Pre[1], Length(Pre));
  Fi := SysOpen(TGT + Path, O_RDONLY, 0);
  If Fi >= 0 Then
  Begin
    While SysReadLine(Fi, L) Do
      If ((Drop1 = '') Or (Copy(L, 1, Length(Drop1)) <> Drop1)) And
         ((Drop2 = '') Or (Copy(L, 1, Length(Drop2)) <> Drop2)) Then
      Begin
        L := L + #10;
        SysWrite(Fo, L[1], Length(L));
      End;
    SysClose(Fi);
  End;
  If Post <> '' Then SysWrite(Fo, Post[1], Length(Post));
  SysClose(Fo);
  SysChmod(Tmp, 420);
  If SysRename(Tmp, TGT + Path) < 0 Then
  Begin
    OpErr := Path + ' : ' + SysErrorText(SysErrno);
    Exit;
  End;
  CfgRewrite := True;
End;

Function RandSalt : String;
Const Ch : String[64] =
  './0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz';
Var T : LongInt;
Begin
  T := SysTime * 7 + SysGetPid;
  RandSalt := Ch[T Mod 64 + 1] + Ch[(T Div 64) Mod 64 + 1];
End;

Function CfgAll : Boolean;
Var I, Hp, Sp : LongInt; Fs, Lc, Cr, U8, Km, Dev : String; Swap, Home : Boolean;
  Pw, Sh, Gr : String;
Begin
  CfgAll := False;
  Swap := False;
  Home := False;
  { fstab }
  Pw := '# /etc/fstab : genere par l''installateur' + #10 +
        RootDev + ' / ' + FsName[PartFs(RootPart)] + ' defaults 1 1' + #10;
  For I := 1 To MAXPT Do
    If Pt[I].Used Then
    Begin
      If Pt[I].Role = ROLE_HOME Then
      Begin
        Pw := Pw + DkPartDev(I) + ' /home ' + FsName[PartFs(I)] +
              ' defaults 1 2' + #10;
        Home := True;
      End
      Else If Pt[I].Role = ROLE_SWAP Then
      Begin
        Pw := Pw + DkPartDev(I) + ' none swap sw 0 0' + #10;
        Swap := True;
      End;
    End;
  Pw := Pw + 'proc /proc proc defaults 0 0' + #10;
  If Not OpWriteFile(TGT + '/etc/fstab', Pw, 420, False) Then Exit;
  { nom de la machine }
  If Not OpWriteFile(TGT + '/etc/hostname', Host + #10, 420, False) Then Exit;
  If Not OpWriteFile(TGT + '/etc/hosts', '127.0.0.1 localhost' + #10 +
     '127.0.1.1 ' + Host + #10 + '::1 localhost' + #10, 420, False) Then Exit;
  { comptes }
  Cr := SysCrypt(UiToU8(RootPw), RandSalt);
  If Not CfgRewrite('/etc/shadow', 'root:', 'linux:',
     'root:' + Cr + ':0:0:99999:7:::' + #10, '') Then Exit;
  SysChmod(TGT + '/etc/shadow', 384);
  If UserName <> '' Then
  Begin
    U8 := UiToU8(UserFull);
    Cr := SysCrypt(UiToU8(UserPw), RandSalt);
    If Not CfgRewrite('/etc/passwd', 'linux:', '', '',
       UserName + ':x:1000:1000:' + U8 + ':/home/' + UserName + ':/bin/sh' +
       #10) Then Exit;
    If Not CfgRewrite('/etc/shadow', 'linux:', '', '',
       UserName + ':' + Cr + ':0:0:99999:7:::' + #10) Then Exit;
    SysChmod(TGT + '/etc/shadow', 384);
    If Not CfgRewrite('/etc/group', 'linux:', 'users:', '',
       'users:x:100:' + UserName + #10 + UserName + ':x:1000:' + #10) Then
      Exit;
    If Not CfgRewrite('/etc/sudoers', 'linux ', '', '', UserName +
       ' ALL=(ALL) ALL' + #10) Then Exit;
    OpMkdirP(TGT + '/home/' + UserName, 493);
    SysChown(TGT + '/home/' + UserName, 1000, 1000);
    SysChmod(TGT + '/home/' + UserName, 493);
    SysChmod(TGT + '/etc/sudoers', 288);
  End
  Else
  Begin
    CfgRewrite('/etc/passwd', 'linux:', '', '', '');
    CfgRewrite('/etc/shadow', 'linux:', '', '', '');
    CfgRewrite('/etc/group', 'linux:', '', '', '');
    CfgRewrite('/etc/sudoers', 'linux ', '', '', '');
    SysChmod(TGT + '/etc/shadow', 384);
    SysChmod(TGT + '/etc/sudoers', 288);
  End;
  { langue, clavier, fuseau horaire, horloge }
  Lc := LangLoc[Lang] + '.UTF-8';
  If Not OpWriteFile(TGT + '/etc/profile',
     '# /etc/profile : genere par l''installateur' + #10 +
     'LANGUAGE=' + LangCode[Lang] + #10 + 'export LANGUAGE' + #10 +
     'LANG=' + Lc + #10 + 'export LANG' + #10 +
     'PATH=/sbin:/bin:/usr/sbin:/usr/bin' + #10 + 'export PATH' + #10 +
     'umask 022' + #10, 420, False) Then Exit;
  If Not OpWriteFile(TGT + '/etc/default/locale', 'LANG=' + Lc + #10 +
     'LANGUAGE=' + LowerS(LangCode[Lang]) + #10, 420, False) Then Exit;
  Km := LayId[LayI];
  If Not OpWriteFile(TGT + '/etc/default/keyboard', 'XKBLAYOUT="' + Km + '"' +
     #10 + 'KEYMAP=' + Km + #10, 420, False) Then Exit;
  If Not OpWriteFile(TGT + '/etc/timezone', TzName + #10, 420, False) Then
    Exit;
  If Not OpCopyFile(ZONEDIR + TzName, TGT + '/etc/localtime', 420) Then
    OpLog('fuseau : ' + OpErr);
  If ClkUtc = 1 Then Sh := 'UTC' Else Sh := 'LOCAL';
  If Not OpWriteFile(TGT + '/etc/adjtime', '0.000000 0 0.000000' + #10 + '0' +
     #10 + Sh + #10, 420, False) Then Exit;
  Gr := '# ajouts de l''installateur' + #10 +
        '[ -x /sbin/hwclock ] && /sbin/hwclock -s 2>/dev/null' + #10 +
        '[ -x /bin/loadkeys ] && . /etc/default/keyboard && ' +
        '/bin/loadkeys $KEYMAP 2>/dev/null' + #10;
  If Swap Then Gr := Gr + 'swapon -a 2>/dev/null' + #10;
  If Home Then Gr := Gr + 'mount -a 2>/dev/null' + #10;
  If Not OpWriteFile(TGT + '/etc/rc', Gr, 493, True) Then Exit;
  CfgAll := True;
End;

Function BootAll : Boolean;
Var Km, Cmd : String;
Begin
  BootAll := False;
  Km := LayId[LayI];
  Cmd := 'root=' + RootDev + ' rw console=tty0 console=ttyS0';
  { le noyau ne connait que us et fr : les autres dispositions sont
    chargees par loadkeys (KDSKBENT) depuis /etc/rc }
  If (Km = 'fr') Or (Km = 'us') Then Cmd := Cmd + ' keymap=' + Km;
  If Not OpCopyFile(CDMNT + '/boot/linux0', TGT + '/boot/linux0', 493) Then
    Exit;
  If Not OpWriteFile(TGT + '/boot/linux0.cfg', 'kernel=/boot/linux0' + #10 +
     'cmdline=' + Cmd + #10, 420, False) Then Exit;
  BootAll := True;
End;

Function MountCd : Boolean;
Const Devs : Array[0..3] Of String[10] = ('/dev/hdc', '/dev/hdd', '/dev/hdb',
  '/dev/sr0');
Var I : LongInt;
Begin
  MountCd := False;
  If OpFileExists(CDMNT + '/system.tar') Then
  Begin
    MountCd := True;
    Exit;
  End;
  SysMkdir(CDMNT, 493);
  For I := 0 To 3 Do
    If SysMount(Devs[I], CDMNT, 'iso9660', 1) = 0 Then
    Begin
      If OpFileExists(CDMNT + '/system.tar') Then
      Begin
        MountCd := True;
        Exit;
      End;
      SysUmount(CDMNT);
    End;
End;

Procedure CleanMounts;
Begin
  SysSync;
  SysUmount(TGT + '/home');
  SysUmount(TGT);
End;

{ l'installation proprement dite ; False en cas d'echec (OpErr : detail) }
Function DoInstall : Boolean;
Var I, Rc : LongInt; Dev, Lbl, Args : String;
Begin
  DoInstall := False;
  OpErr := '';
  If Not CdOk Then CdOk := MountCd;
  If Not CdOk Then
  Begin
    OpErr := Msg(M_E_CD);
    Exit;
  End;
  If PartMode = 1 Then GuidedPlan;
  { le role fixe le type : swap 82, le reste Linux 83 }
  For I := 1 To MAXPT Do
    If Pt[I].Used Then
    Begin
      If Pt[I].Role = ROLE_SWAP Then Pt[I].Typ := PT_SWAP
      Else If (Pt[I].Role <> ROLE_NONE) And (Pt[I].Typ = PT_SWAP) Then
        Pt[I].Typ := PT_LINUX;
      Pt[I].Active := Pt[I].Role = ROLE_ROOT;
    End;
  If (RootPart = 0) Or (RootPart > 4) Then
  Begin
    OpErr := Msg(M_ROLE_E_ROOT);
    If RootPart > 4 Then OpErr := Msg(M_ROLE_E_PRIM);
    Exit;
  End;
  Dsk := DiskPath;
  If DkBusy(Dsk) Then
  Begin
    OpErr := Fmt(M_E_BUSY, Dsk, '', '');
    Exit;
  End;
  { 1 : table des partitions + chargeur }
  InstStage(1, 0, 30);
  OpLog(Fmt(M_L_PART, Dsk, '', ''));
  If Not DkWriteTable Then
  Begin
    OpErr := Fmt(M_E_PART, Dsk, '', '');
    Exit;
  End;
  If Not DkReread Then
  Begin
    OpErr := Fmt(M_E_REREAD, Dsk, '', '');
    Exit;
  End;
  { 2 : formatage }
  InstStage(2, 30, 100);
  For I := 1 To MAXPT Do
    If Pt[I].Used And (Pt[I].Role <> ROLE_NONE) Then
    Begin
      Dev := DkPartDev(I);
      If Pt[I].Role = ROLE_SWAP Then
      Begin
        OpLog(Fmt(M_L_SWAP, Dev, '', ''));
        Rc := OpExec('/sbin/mkswap', Dev);
      End
      Else
      Begin
        If Pt[I].Role = ROLE_ROOT Then Lbl := 'root' Else Lbl := 'home';
        OpLog(Fmt(M_L_FMT, Dev, FsName[PartFs(I)], ''));
        Args := '-L ' + Lbl + ' ' + Dev;
        If Pt[I].Size > 2 * 1024 * 2048 Then Args := '-b 4096 ' + Args;
        Rc := OpExec('/sbin/mkfs.' + FsName[PartFs(I)], Args);
      End;
      If Rc <> 0 Then
      Begin
        OpErr := Fmt(M_E_FMT, Dev, '', '') + ' (' + NumS(Rc) + ')';
        Exit;
      End;
      If Not NoUi Then UiSetProg(41, 30 + (100 * I) Div 4);
    End;
  { 3 : montages }
  InstStage(3, 130, 20);
  SysMkdir(TGT, 493);
  Dev := RootDev;
  OpLog(Fmt(M_L_MNT, Dev, TGT, ''));
  If SysMount(Dev, TGT, FsName[PartFs(RootPart)], 0) < 0 Then
  Begin
    OpErr := Fmt(M_E_MNT, Dev, '', '') + ' : ' + SysErrorText(SysErrno);
    Exit;
  End;
  For I := 1 To MAXPT Do
    If Pt[I].Used And (Pt[I].Role = ROLE_HOME) Then
    Begin
      SysMkdir(TGT + '/home', 493);
      OpLog(Fmt(M_L_MNT, DkPartDev(I), TGT + '/home', ''));
      If SysMount(DkPartDev(I), TGT + '/home', FsName[PartFs(I)], 0) < 0 Then
      Begin
        OpErr := Fmt(M_E_MNT, DkPartDev(I), '', '') + ' : ' +
                 SysErrorText(SysErrno);
        CleanMounts;
        Exit;
      End;
    End;
  { 4 : copie }
  InstStage(4, 150, 700);
  OpLog(Msg(M_L_COPY));
  If Not OpExtract(CDMNT + '/system.tar', TGT) Then
  Begin
    OpErr := Fmt(M_E_COPY, OpErr, '', '');
    CleanMounts;
    Exit;
  End;
  OpLog(Fmt(M_L_FILES, NumS(OpNFiles), '', ''));
  { 5 : configuration }
  If UserName <> 'linux' Then SysRmdir(TGT + '/home/linux');
  InstStage(5, 850, 60);
  OpLog(Msg(M_L_CFG));
  If Not CfgAll Then
  Begin
    OpErr := Fmt(M_E_CFG, OpErr, '', '');
    CleanMounts;
    Exit;
  End;
  { 6 : noyau et chargeur }
  InstStage(6, 910, 60);
  OpLog(Msg(M_L_BOOT));
  If Not BootAll Then
  Begin
    OpErr := Fmt(M_E_CFG, OpErr, '', '');
    CleanMounts;
    Exit;
  End;
  { 7 : fin }
  InstStage(7, 970, 30);
  If OpLogFd >= 0 Then SysSync;
  OpCopyFile(LOGPATH, TGT + LOGPATH, 420);
  OpTzEnv := TzName;
  If ClkUtc = 1 Then OpExec('/sbin/hwclock', '-w --utc')
  Else OpExec('/sbin/hwclock', '-w --localtime');
  OpTzEnv := '';
  CleanMounts;
  If Not NoUi Then UiSetProg(41, 1000);
  DoInstall := True;
End;

Function PageInst : LongInt;
Var R, W : LongInt; Ok : Boolean;
Begin
  BeginPage(S_INST, Msg(M_INST_T));
  UiFoot := '';
  W := UiLabel(0, 0, UiCw, 1, '', 0);
  UiWd[W].Id := 42;
  UiProg(41, 0, 1, UiCw);
  InstLogW := UiLog(0, 3, UiCw, UiCh - 3);
  InstProgW := 1;
  UiFoc := -1;
  UiRedraw;
  InFlush;
  Ok := DoInstall;
  InFlush;
  InstProgW := -1;
  If Ok Then R := NAV_NEXT
  Else
  Begin
    OpLog(OpErr);
    UiMsgBox(Msg(M_ERR_T), OpErr + #10#10 + Msg(M_INST_FAIL), Msg(M_OK), '');
    R := NAV_BACK;
  End;
  PageInst := R;
End;

{ ---- page : fin ---- }

Procedure DoReboot;
Begin
  SysSync;
  If RebootMode = 'halt' Then
    SysReboot(LINUX_REBOOT_MAGIC1, LINUX_REBOOT_MAGIC2, LINUX_REBOOT_POWER_OFF)
  Else
    SysReboot(LINUX_REBOOT_MAGIC1, LINUX_REBOOT_MAGIC2, LINUX_REBOOT_RESTART);
End;

Function PageEnd(WaitSecs : LongInt) : LongInt;
Var R, X, W : LongInt;
Begin
  Repeat
    BeginPage(S_END, Msg(M_END_T));
    UiLabel(0, 1, UiCw, 8, Msg(M_END_I), 0);
    W := Length(Msg(M_REBOOT)) + 4;
    UiButton(NAV_NEXT, UiCw - W, UiWh - 4, W, Msg(M_REBOOT), WF_DEF);
    UiSetFocusId(NAV_NEXT);
    If WaitSecs > 0 Then R := UiRun(WaitSecs * 1000) Else R := PageRun;
    If R = NAV_CANCEL Then R := NAV_NEXT;
  Until R <> RES_REBUILD;
  PageEnd := R;
End;

{ ---- mode automatique : fichier de reponses ---- }

Function LangFromCode(Const C : String) : LongInt;
Var I : LongInt; U : String;
Begin
  U := UpCase(C[1]);
  LangFromCode := 1;
  For I := 0 To 6 Do
    If LowerS(LangCode[I]) = LowerS(C) Then LangFromCode := I;
  If LowerS(C) = 'gr' Then LangFromCode := 2;
  If LowerS(C) = 'sp' Then LangFromCode := 4;
End;

{ role et systeme de fichiers d'une partition creee par le fichier de reponses }
Procedure PsRole(Slot : LongInt; Const Mnt, Fs : String);
Begin
  Pt[Slot].Role := ROLE_NONE;
  If Mnt = '/' Then Pt[Slot].Role := ROLE_ROOT
  Else If Mnt = '/home' Then Pt[Slot].Role := ROLE_HOME
  Else If Mnt = 'swap' Then Pt[Slot].Role := ROLE_SWAP;
  If Fs = 'ext3' Then Pt[Slot].Fs := 3
  Else If Fs = 'ext2' Then Pt[Slot].Fs := 2
  Else If Fs = 'ext4' Then Pt[Slot].Fs := 4;
End;

{ parts=ext4:/:300M,swap:swap:64M,ext3:/home:*,ext4:/var:200M:logical
  (systeme de fichiers : mount : taille [: logical]) ; les partitions
  "logical" vont dans une etendue creee sur tout l'espace libre restant }
Function PsParts(Const Spec : String) : Boolean;
Var I, S, N, F, Sz, Slot, K, Best, Gs, Gz, BestSz, NLog : LongInt; E : String;
  EFs, EMnt, ESz : Array[0..7] Of String[20]; ELog : Array[0..7] Of Boolean;
  Role : LongInt;
Begin
  PsParts := False;
  Dsk := DiskPath;
  DskSec := DkSectors(Dsk);
  DkClearTable;
  I := 1;
  N := 0;
  NLog := 0;
  While (I <= Length(Spec)) And (N < 8) Do
  Begin
    S := I;
    While (I <= Length(Spec)) And (Spec[I] <> ',') Do Inc(I);
    E := Copy(Spec, S, I - S);
    Inc(I);
    F := Pos(':', E);
    If F = 0 Then Exit;
    EFs[N] := Copy(E, 1, F - 1);
    E := Copy(E, F + 1, 80);
    F := Pos(':', E);
    If F = 0 Then Exit;
    EMnt[N] := Copy(E, 1, F - 1);
    E := Copy(E, F + 1, 40);
    ELog[N] := False;
    F := Pos(':', E);
    If F > 0 Then
    Begin
      ELog[N] := Copy(E, F + 1, 1) = 'l';
      E := Copy(E, 1, F - 1);
    End;
    ESz[N] := E;
    If ELog[N] Then Inc(NLog);
    Inc(N);
  End;
  { 1 : les primaires }
  For K := 0 To N - 1 Do
    If Not ELog[K] Then
    Begin
      If ESz[K] = '*' Then Sz := DskSec Else Sz := ParseSize(ESz[K], DskSec);
      If Sz < 2048 Then Exit;
      If EMnt[K] = 'swap' Then Slot := DkCreate(0, Sz, PT_SWAP)
      Else Slot := DkCreate(0, Sz, PT_LINUX);
      If Slot = 0 Then Exit;
      PsRole(Slot, EMnt[K], EFs[K]);
    End;
  { 2 : l'etendue sur la plus grande plage libre, puis les logiques }
  If NLog > 0 Then
  Begin
    Best := -1;
    BestSz := 0;
    K := 0;
    While DkGap(K, Gs, Gz) Do
    Begin
      If Gz > BestSz Then
      Begin
        Best := K;
        BestSz := Gz;
      End;
      Inc(K);
    End;
    If Best < 0 Then Exit;
    If DkCreate(Best, BestSz, PT_EXT) = 0 Then Exit;
    For K := 0 To N - 1 Do
      If ELog[K] Then
      Begin
        If Not DkLgGap(0, Gs, Gz) Then Exit;
        If ESz[K] = '*' Then Sz := Gz Else Sz := ParseSize(ESz[K], Gz);
        If EMnt[K] = 'swap' Then Slot := DkCreateLog(0, Sz, PT_SWAP)
        Else Slot := DkCreateLog(0, Sz, PT_LINUX);
        If Slot = 0 Then Exit;
        PsRole(Slot, EMnt[K], EFs[K]);
      End;
  End;
  PsParts := N > 0;
End;

Procedure ApplyPreseed;
Var S, T : String;
Begin
  Lang := LangFromCode(PsGet('lang', 'en'));
  LayTouched := False;
  TzTouched := False;
  ApplyLangDefaults;
  S := PsGet('keyboard', '');
  If S <> '' Then
  Begin
    LayI := LayIndex(S);
    LayTouched := True;
    InSetLayout(LayI);
  End;
  S := PsGet('timezone', '');
  If S <> '' Then TzName := S;
  If LowerS(PsGet('clock', 'utc')) = 'local' Then ClkUtc := 0 Else ClkUtc := 1;
  Host := PsGet('hostname', 'linux0');
  RootPw := PsGet('rootpw', 'root');
  UserName := PsGet('user', '');
  UserFull := PsGet('fullname', UserName);
  UserPw := PsGet('userpw', '');
  DiskPath := PsGet('disk', '');
  S := PsGet('fs', 'ext4');
  If S = 'ext3' Then FsKind := 3 Else If S = 'ext2' Then FsKind := 2
  Else FsKind := 4;
  SwapMb := PsGet('swap', '0');
  UseSwap := SwapMb <> '0';
  If PsGet('partitioning', 'guided') = 'manual' Then PartMode := 2
  Else PartMode := 1;
  RebootMode := PsGet('reboot', 'reboot');
  S := PsGet('date', '');
  T := PsGet('time', '');
  If (S <> '') And (T <> '') Then
  Begin
    ClkDate := S;
    ClkTime := T;
    ClkTouched := True;
  End;
End;

{ regle l'heure du systeme depuis la date et l'heure saisies (fuseau choisi) }
Procedure SetSystemClock;
Var Y, M, D, H, Mi, S : LongInt; T : LongInt; Tm : Array[0..1] Of LongInt;
Begin
  If Not (ParseDate(ClkDate, Y, M, D) And ParseTime(ClkTime, H, Mi, S)) Then
    Exit;
  If (ClkDate = ClkDt0) And (ClkTime = ClkTm0) And Not ClkTouched Then Exit;
  LnxTzSelect(TzName);
  T := LnxDaysFromCivil(Y, M, D) * 86400 + H * 3600 + Mi * 60 + S;
  T := LnxTzUtcOf(T);
  Tm[0] := T;
  Tm[1] := 0;
  If LnxSys3(79, LongInt(@Tm), 0, 0) = 0 Then
    OpLog('clock set ' + ClkDate + ' ' + ClkTime + ' (' + TzName + ')');
End;

{ ---- programme principal ---- }

Function NextStep(S : LongInt) : LongInt;
Begin
  Case S Of
    S_METH : If PartMode = 2 Then NextStep := S_PED Else NextStep := S_SUM;
    S_PED : NextStep := S_ROLE;
    S_ROLE : NextStep := S_SUM;
  Else
    NextStep := S + 1;
  End;
End;

Function PrevStep(S : LongInt) : LongInt;
Begin
  Case S Of
    S_SUM : If PartMode = 2 Then PrevStep := S_ROLE Else PrevStep := S_METH;
    S_PED : PrevStep := S_METH;
    S_ROLE : PrevStep := S_PED;
  Else
    If S > 0 Then PrevStep := S - 1 Else PrevStep := 0;
  End;
End;

Procedure Wizard;
Var R : LongInt; PedInit : Boolean;
Begin
  PedInit := False;
  Step := S_LANG;
  While Not Quitting Do
  Begin
    R := NAV_NEXT;
    Case Step Of
      S_LANG : R := PageLang;
      S_WELC : R := PageWelc;
      S_KEY : R := PageKey;
      S_TZ : R := PageTz;
      S_CLK :
        Begin
          R := PageClk;
          If R = NAV_NEXT Then SetSystemClock;
        End;
      S_HOST : R := PageHost;
      S_ACC : R := PageAcc;
      S_DISK : R := PageDisk;
      S_METH :
        Begin
          R := PageMeth;
          If R = NAV_NEXT Then PedInit := False;
        End;
      S_PED :
        Begin
          If Not PedInit Then
          Begin
            Dsk := DiskPath;
            DkReadTable;
            PedInit := True;
          End;
          R := PagePed;
        End;
      S_ROLE : R := PageRole;
      S_SUM : R := PageSum;
      S_INST :
        Begin
          R := PageInst;
          If R = NAV_NEXT Then Step := S_END - 1;
        End;
      S_END :
        Begin
          PageEnd(0);
          Exit;
        End;
    End;
    If Quitting Then Break;
    If R = NAV_NEXT Then Step := NextStep(Step)
    Else If R = NAV_BACK Then Step := PrevStep(Step);
  End;
End;

Procedure Restore(Const Tty : String);
Var Fd : LongInt;
Begin
  Fd := SysOpen(Tty, O_RDWR, 0);
  If Fd < 0 Then Exit;
  SysIoctlL(Fd, $4B45, 1);
  SysIoctlL(Fd, $4B3A, 0);
  SysClose(Fd);
End;

Var
  I, Fd, N, Code : LongInt;
  A : String;
  Verbose : Boolean;

BEGIN
  FsName[2] := 'ext2'; FsName[3] := 'ext3'; FsName[4] := 'ext4';
  TtyPath := '';
  PresPath := '';
  TextOnly := False;
  Code := 0;
  I := 1;
  While I < SysArgCount Do
  Begin
    A := SysArgStr(I);
    If (A = '-t') And (I + 1 < SysArgCount) Then
    Begin
      Inc(I);
      TtyPath := SysArgStr(I);
    End
    Else If (A = '-p') And (I + 1 < SysArgCount) Then
    Begin
      Inc(I);
      PresPath := SysArgStr(I);
    End
    Else If A = '--text' Then TextOnly := True
    Else If A = '--restore' Then
    Begin
      If TtyPath = '' Then TtyPath := '/dev/tty1';
      Restore(TtyPath);
      SysExit(0);
    End;
    Inc(I);
  End;
  CmdLine := '';
  Fd := SysOpen('/proc/cmdline', O_RDONLY, 0);
  If Fd >= 0 Then
  Begin
    SysReadLine(Fd, CmdLine);
    SysClose(Fd);
  End;
  Verbose := CmdHas('k32setup.verbose');
  OpMarkFd := -1;
  If Verbose Then
  Begin
    A := CmdGet('k32setup.verbose');
    If A = '' Then A := '/dev/console';
    OpMarkFd := SysOpen(A, O_WRONLY Or O_NOCTTY, 0);
  End;
  SysClose(2);
  SysOpen('/dev/null', O_WRONLY, 0);
  If PresPath = '' Then PresPath := CmdGet('preseed');
  If CmdHas('text') Then TextOnly := True;
  Lang := 1;
  If CmdGet('lang') <> '' Then Lang := LangFromCode(CmdGet('lang'));
  LayI := 0;
  LayTouched := False;
  TzTouched := False;
  ApplyLangDefaults;
  Host := 'linux0';
  FsKind := 4;
  PartMode := 1;
  UseSwap := True;
  SwapMb := '256';
  ClkUtc := 1;
  RebootMode := 'reboot';
  InstProgW := -1;
  OpLogOpen;
  AutoMode := False;
  CdOk := MountCd;
  If PresPath <> '' Then
  Begin
    PsLoad(PresPath);
    AutoMode := PsN > 0;
  End;
  If AutoMode Then
  Begin
    ApplyPreseed;
    If PsGet('ui', 'gui') = 'none' Then NoUi := True;
    If PsGet('ui', 'gui') = 'text' Then TextOnly := True;
  End;
  If Not NoUi Then
  Begin
    If Not TextOnly Then
      If Not GOpen(1024, 768) Then TextOnly := True;
    InOpen(TtyPath, Not TextOnly);
    InSetLayout(LayI);
    UiCp437 := InIsVt;
    UiUtf8 := CmdHas('k32setup.utf8') And Not InIsVt;
    If TextOnly Then UiTextOpen Else UiGfxGrid;
  End;
  If AutoMode Then
  Begin
    { disque : le premier disque libre si non precise }
    DkScan;
    If DiskPath = '' Then
      If DkCount > 0 Then DiskPath := '/dev/' + DkName[0];
    Dsk := DiskPath;
    If PartMode = 2 Then
    Begin
      If Not PsParts(PsGet('parts', '')) Then
      Begin
        OpLog('preseed : parts invalide');
        Code := 3;
      End;
    End;
    If Code = 0 Then
    Begin
      SetSystemClock;
      If NoUi Then
      Begin
        If DoInstall Then OpLog('K32SETUP: DONE') Else
        Begin
          OpLog('K32SETUP: FAIL ' + OpErr);
          Code := 3;
        End;
      End
      Else
      Begin
        N := PageInst;
        If N = NAV_NEXT Then
        Begin
          OpLog('K32SETUP: DONE');
          Val(PsGet('endwait', '4'), N, I);
          If N > 0 Then PageEnd(N);
        End
        Else
        Begin
          OpLog('K32SETUP: FAIL ' + OpErr);
          Code := 3;
        End;
      End;
      If Code = 0 Then DoReboot;
    End;
  End
  Else
  Begin
    Wizard;
    If Quitting Then Code := 2;
  End;
  If Not NoUi Then
  Begin
    If UiGfx Then GClose Else UiTextClose;
    InClose;
  End;
  SysExit(Code);
END.
