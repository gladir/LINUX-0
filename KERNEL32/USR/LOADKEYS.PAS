{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2026
  @website(https://www.gladir.com/linux-0)
  @abstract(Target: LPC -3X)
  @description: loadkeys et dumpkeys (le nom lu dans argv[0]) : disposition
   du clavier de la console par KDSKBENT / KDGKBENT (ioctl 0x4B47 / 0x4B46 sur
   /dev/tty0). Les dispositions de l'assistant d'installation sont integrees
   (us uk fr be de chde chfr it es pt nl : USR/INSTALLER/LAYOUTS.INC).
   loadkeys [-q] NOM       charge la disposition NOM
   loadkeys [-q] -f FICHIER  charge un fichier de lignes
                           "keycode N = normale majuscule altgr"
                           (un caractere, "nul", ou le code decimal 0..255
                            precede de #; dead_circ dead_diaer dead_grave
                            dead_acute dead_tilde : touches mortes)
   loadkeys -n ...         n'ecrit rien : affiche ce qui serait charge
   loadkeys -d             disposition par defaut (us)
   dumpkeys                affiche la disposition courante au meme format
   Le noyau doit offrir KDSKBENT/KDGKBENT (voir DEMANDES_A.md [E6]) ; sinon
   le programme le dit et rend 1. Valeur d'une touche : code Latin-1 ; touche
   morte : 0x500 + (0 grave, 1 aigu, 2 circonflexe, 3 tilde, 4 trema) comme
   Linux (KT_DEAD). }

Program LoadKeys;

{$I LAYOUTS.INC}

Const
  KDGKBENT = $4B46;
  KDSKBENT = $4B47;
  DeadName : Array[0..4] Of String[10] = ('dead_grave', 'dead_acute',
    'dead_circ', 'dead_tilde', 'dead_diaer');

Var
  Quiet, NoWrite, Dump : Boolean;
  Tty : LongInt;
  Ent : Array[0..1] Of LongInt;     { struct kbentry : table, index, valeur }
  Bad : LongInt;
  Vals : Array[0..127, 0..2] Of LongInt;  { -1 : inchange }

{ code interne de LAYOUTS.INC (2..6 : touches mortes) -> valeur du noyau }
Function KeyVal(V : LongInt) : LongInt;
Begin
  If V = 1 Then KeyVal := 0
  Else If (V >= 2) And (V <= 6) Then
    Case V Of
      2 : KeyVal := $502;
      3 : KeyVal := $504;
      4 : KeyVal := $500;
      5 : KeyVal := $501;
    Else
      KeyVal := $503;
    End
  Else If V = $80 Then KeyVal := 0
  Else KeyVal := V;
End;

Function SetEnt(Tbl, Idx, Val : LongInt) : LongInt;
Var A : Array[0..1] Of LongInt;
Begin
  { struct kbentry { u8 table; u8 index; u16 value } = un mot de 32 bits }
  A[0] := Tbl Or (Idx Shl 8) Or (Val Shl 16);
  SetEnt := SysIoctl(Tty, KDSKBENT, A);
End;

Function GetEnt(Tbl, Idx : LongInt; Var Val : LongInt) : LongInt;
Var A : Array[0..1] Of LongInt; R : LongInt;
Begin
  A[0] := Tbl Or (Idx Shl 8);
  R := SysIoctl(Tty, KDGKBENT, A);
  Val := (A[0] Shr 16) And $FFFF;
  GetEnt := R;
End;

Function ValText(V : LongInt) : String;
Var S : String;
Begin
  If V = 0 Then ValText := 'nul'
  Else If (V >= $500) And (V <= $504) Then ValText := DeadName[V - $500]
  Else If (V > 32) And (V < 127) Then ValText := Chr(V)
  Else
  Begin
    Str(V, S);
    ValText := '#' + S;
  End;
End;

Function ParseTok(Const T : String; Var V : LongInt) : Boolean;
Var I, E : LongInt;
Begin
  ParseTok := True;
  If T = 'nul' Then V := 0
  Else If T[1] = '#' Then
  Begin
    Val(Copy(T, 2, 5), V, E);
    ParseTok := (E = 0) And (V >= 0) And (V < 256);
  End
  Else
  Begin
    V := -1;
    For I := 0 To 4 Do
      If DeadName[I] = T Then V := $500 + I;
    If V < 0 Then
    Begin
      If Length(T) = 1 Then V := Ord(T[1])
      Else If (Length(T) = 2) And (T[1] >= #194) And (T[1] <= #195) Then
        V := ((Ord(T[1]) And 31) Shl 6) Or (Ord(T[2]) And 63)
      Else ParseTok := False;
    End;
  End;
End;

{ remplit Vals[] depuis la disposition integree Idx }
Procedure FromLayout(Idx : LongInt);
Var I, K, Pl : LongInt;
Begin
  FillChar(Vals, SizeOf(Vals), 255);
  For I := 0 To 47 Do
  Begin
    K := LayKc[I];
    For Pl := 0 To 2 Do
      Vals[K, Pl] := KeyVal(LayData[Idx * 144 + Pl * 48 + I]);
  End;
End;

Function LayByName(Const N : String) : LongInt;
Var I : LongInt;
Begin
  LayByName := -1;
  For I := 0 To LayCount - 1 Do
    If LayId[I] = N Then LayByName := I;
End;

{ lit un fichier "keycode N = a b c" }
Function FromFile(Const Path : String) : Boolean;
Var F, K, Pl, P, E, V, W : LongInt; L, T : String;
Begin
  FromFile := False;
  F := SysOpen(Path, O_RDONLY, 0);
  If F < 0 Then Exit;
  FillChar(Vals, SizeOf(Vals), 255);
  While SysReadLine(F, L) Do
  Begin
    If (L = '') Or (L[1] = '#') Then Continue;
    If Copy(L, 1, 8) <> 'keycode ' Then Continue;
    P := 9;
    W := 0;
    K := 0;
    While (P <= Length(L)) And (L[P] = ' ') Do Inc(P);
    While (P <= Length(L)) And (L[P] >= '0') And (L[P] <= '9') Do
    Begin
      K := K * 10 + Ord(L[P]) - 48;
      Inc(P);
    End;
    While (P <= Length(L)) And ((L[P] = ' ') Or (L[P] = '=')) Do Inc(P);
    Pl := 0;
    While (P <= Length(L)) And (Pl < 3) Do
    Begin
      T := '';
      While (P <= Length(L)) And (L[P] <> ' ') Do
      Begin
        T := T + L[P];
        Inc(P);
      End;
      While (P <= Length(L)) And (L[P] = ' ') Do Inc(P);
      If (T <> '') And (K > 0) And (K < 128) Then
        If ParseTok(T, V) Then Vals[K, Pl] := V
        Else
        Begin
          SysPut(2, 'loadkeys: ' + T + ' ?' + #10);
          Inc(Bad);
        End;
      Inc(Pl);
    End;
  End;
  SysClose(F);
  FromFile := True;
End;

Procedure Fail(Const S : String);
Begin
  SysPut(2, S + #10);
  SysExit(1);
End;

Var
  I, K, Pl, V, Idx : LongInt;
  A, Name, FileName, Line, Prog : String;
Begin
  Quiet := False; NoWrite := False; Dump := False;
  Bad := 0;
  Name := '';
  FileName := '';
  Prog := SysArgStr(0);
  K := Length(Prog);
  While (K > 0) And (Prog[K] <> '/') Do Dec(K);
  Prog := Copy(Prog, K + 1, 40);
  Dump := (Prog = 'dumpkeys') Or (Prog = 'DUMPKEYS');
  I := 1;
  While I < SysArgCount Do
  Begin
    A := SysArgStr(I);
    If A = '-q' Then Quiet := True
    Else If A = '-n' Then NoWrite := True
    Else If A = '-d' Then Name := 'us'
    Else If (A = '-f') And (I + 1 < SysArgCount) Then
    Begin
      Inc(I);
      FileName := SysArgStr(I);
    End
    Else Name := A;
    Inc(I);
  End;
  If (Not Dump) And (Name = '') And (FileName = '') Then
    Fail('Usage: loadkeys [-q] [-n] NOM | -f FICHIER | -d ; dumpkeys');
  Tty := 0;
  If Not NoWrite Then
  Begin
    Tty := SysOpen('/dev/tty0', O_RDWR, 0);
    If Tty < 0 Then Tty := SysOpen('/dev/console', O_RDWR, 0);
    If Tty < 0 Then Fail('loadkeys: pas de console');
  End;
  If Dump Then
  Begin
    For K := 1 To 127 Do
    Begin
      Line := '';
      For Pl := 0 To 2 Do
      Begin
        If GetEnt(Pl, K, V) < 0 Then Fail('dumpkeys: KDGKBENT non supporte');
        Line := Line + ' ' + ValText(V);
      End;
      If Line <> ' nul nul nul' Then
      Begin
        Str(K, A);
        SysPut(1, 'keycode ' + A + ' =' + Line + #10);
      End;
    End;
    SysExit(0);
  End;
  If FileName <> '' Then
  Begin
    If Not FromFile(FileName) Then Fail('loadkeys: ' + FileName + ' ?');
  End
  Else
  Begin
    Idx := LayByName(Name);
    If Idx < 0 Then Fail('loadkeys: disposition inconnue : ' + Name);
    FromLayout(Idx);
  End;
  For K := 1 To 127 Do
    If (Vals[K, 0] >= 0) Or (Vals[K, 1] >= 0) Or (Vals[K, 2] >= 0) Then
    Begin
      If NoWrite Then
      Begin
        Str(K, A);
        Line := 'keycode ' + A + ' =';
        For Pl := 0 To 2 Do
          If Vals[K, Pl] >= 0 Then Line := Line + ' ' + ValText(Vals[K, Pl])
          Else Line := Line + ' nul';
        SysPut(1, Line + #10);
      End
      Else
        For Pl := 0 To 2 Do
          If Vals[K, Pl] >= 0 Then
            If SetEnt(Pl, K, Vals[K, Pl]) < 0 Then
            Begin
              If Not Quiet Then
                SysPut(2, 'loadkeys: KDSKBENT non supporte par le noyau' + #10);
              SysExit(1);
            End;
    End;
  If Bad > 0 Then SysExit(1);
End.
