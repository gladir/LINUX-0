{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2026
  @website(https://www.gladir.com/linux-0)
  @abstract(Target: LPC -3X)
  @description: dumpe2fs, tune2fs, e2label, resize2fs (le nom lu dans argv[0]) :
   outils minimaux sur le superbloc ext2/ext3/ext4 (peripherique ou image).
   dumpe2fs [-h] dev     superbloc au format de GNU dumpe2fs -h (nom, UUID,
                         fonctions, nombres de blocs et d'inodes, montages...)
   tune2fs -l dev        idem ; -L nom, -m pct (blocs reserves), -c N (montages
                         maximum), -C N (compteur), -i duree[d|w|m] (controle
                         periodique), -e continue|remount-ro|panic : modifient
                         le superbloc (somme de controle metadata_csum
                         recalculee). Pas de -O ni -U.
   e2label dev [nom]     affiche ou change le nom du volume.
   resize2fs [-P] dev [blocs]   affiche la taille ; le changement de taille
                         n'est pas pris en charge (refus propre, code 1). }

Program E2Tools;

Const
  FeatC : Array[0..5] Of String[16] = ('dir_prealloc', 'imagic_inodes',
    'has_journal', 'ext_attr', 'resize_inode', 'dir_index');
  FeatI : Array[0..17] Of String[20] = ('compression', 'filetype',
    'needs_recovery', 'journal_dev', 'meta_bg', '', 'extent', '64bit', 'mmp',
    'flex_bg', 'ea_inode', '', 'dirdata', 'metadata_csum_seed', 'large_dir',
    'inline_data', 'encrypt', 'casefold');
  FeatR : Array[0..13] Of String[16] = ('sparse_super', 'large_file',
    'btree_dir', 'huge_file', 'uninit_bg', 'dir_nlink', 'extra_isize', '',
    'quota', 'bigalloc', 'metadata_csum', '', 'read-only', 'project');

Var
  Sb : Array[0..1023] Of Byte;
  Fd : LongInt;
  Crc : Array[0..255] Of LongInt;
  Prog, Dev : String;

Procedure Die(Const S : String);
Begin
  SysPut(2, Prog + ': ' + S + #10);
  SysExit(1);
End;

Function D32(Off : LongInt) : LongInt;
Begin
  D32 := Sb[Off] Or (Sb[Off + 1] Shl 8) Or (Sb[Off + 2] Shl 16) Or
         (Sb[Off + 3] Shl 24);
End;

Function D16(Off : LongInt) : LongInt;
Begin
  D16 := Sb[Off] Or (Sb[Off + 1] Shl 8);
End;

Procedure P32(Off, V : LongInt);
Begin
  Sb[Off] := V And 255;
  Sb[Off + 1] := (V Shr 8) And 255;
  Sb[Off + 2] := (V Shr 16) And 255;
  Sb[Off + 3] := (V Shr 24) And 255;
End;

Procedure P16(Off, V : LongInt);
Begin
  Sb[Off] := V And 255;
  Sb[Off + 1] := (V Shr 8) And 255;
End;

Function NumS(V : LongInt) : String;
Var S : String;
Begin
  Str(V, S);
  NumS := S;
End;

Procedure CrcInit;
Var I, J, C : LongInt;
Begin
  For I := 0 To 255 Do
  Begin
    C := I;
    For J := 1 To 8 Do
      If (C And 1) <> 0 Then C := (C Shr 1) Xor $82F63B78 Else C := C Shr 1;
    Crc[I] := C;
  End;
End;

Function SbCsum : LongInt;
Var C, K : LongInt;
Begin
  C := -1;
  For K := 0 To 1019 Do C := Crc[(C Xor Sb[K]) And $FF] Xor (C Shr 8);
  SbCsum := C;
End;

Procedure OpenDev(Write : Boolean);
Var N : LongInt;
Begin
  If Write Then Fd := SysOpen(Dev, O_RDWR, 0)
  Else Fd := SysOpen(Dev, O_RDONLY, 0);
  If Fd < 0 Then Die(Dev + ' : ' + SysErrorText(SysErrno));
  SysLSeek(Fd, 1024, SEEK_SET);
  N := SysRead(Fd, Sb, 1024);
  If (N <> 1024) Or (D16(56) <> $EF53) Then
    Die(Dev + ' : pas de systeme de fichiers ext2/3/4 (superbloc invalide)');
End;

Procedure SaveSb;
Begin
  If (D32(100) And $400) <> 0 Then P32(1020, SbCsum);
  SysLSeek(Fd, 1024, SEEK_SET);
  If SysWrite(Fd, Sb, 1024) <> 1024 Then Die('ecriture : ' +
    SysErrorText(SysErrno));
  LnxSys3(118, Fd, 0, 0);
End;

Function VolName : String;
Var I : LongInt; S : String;
Begin
  S := '';
  I := 120;
  While (I < 136) And (Sb[I] <> 0) Do
  Begin
    S := S + Chr(Sb[I]);
    Inc(I);
  End;
  VolName := S;
End;

Function Hex2(V : LongInt) : String;
Const H : String[16] = '0123456789abcdef';
Begin
  Hex2 := H[(V Shr 4) + 1] + H[(V And 15) + 1];
End;

Function UuidS : String;
Var I : LongInt; S : String;
Begin
  S := '';
  For I := 0 To 15 Do
  Begin
    S := S + Hex2(Sb[104 + I]);
    If (I = 3) Or (I = 5) Or (I = 7) Or (I = 9) Then S := S + '-';
  End;
  UuidS := S;
End;

Function Feats : String;
Var I : LongInt; S : String;
Begin
  S := '';
  For I := 0 To 5 Do
    If ((D32(92) And (1 Shl I)) <> 0) Then S := S + ' ' + FeatC[I];
  For I := 0 To 17 Do
    If ((D32(96) And (1 Shl I)) <> 0) And (FeatI[I] <> '') Then
      S := S + ' ' + FeatI[I];
  For I := 0 To 13 Do
    If ((D32(100) And (1 Shl I)) <> 0) And (FeatR[I] <> '') Then
      S := S + ' ' + FeatR[I];
  If S = '' Then Feats := '(none)' Else Feats := Copy(S, 2, 250);
End;

{ date comme ctime (UTC) ; 0 -> n/a }
Function TimeS(T : LongInt) : String;
Const Mo : String = 'JanFebMarAprMayJunJulAugSepOctNovDec';
      Dn : String = 'SunMonTueWedThuFriSat';
Var Days, Sec, Y, M, D, Wd : LongInt; Z : String;
  Function Two(V : LongInt) : String;
  Var S : String;
  Begin
    S := NumS(V);
    If Length(S) < 2 Then S := '0' + S;
    Two := S;
  End;
Begin
  If T = 0 Then
  Begin
    TimeS := 'n/a';
    Exit;
  End;
  Days := T Div 86400;
  Sec := T Mod 86400;
  LnxCivil(Days, Y, M, D);
  Wd := (Days + 4) Mod 7;
  Z := NumS(D);
  If Length(Z) < 2 Then Z := ' ' + Z;
  TimeS := Copy(Dn, Wd * 3 + 1, 3) + ' ' + Copy(Mo, M * 3 - 2, 3) + ' ' + Z +
    ' ' + Two(Sec Div 3600) + ':' + Two((Sec Mod 3600) Div 60) + ':' +
    Two(Sec Mod 60) + ' ' + NumS(Y);
End;

Procedure Show;
Var Bs, MaxM : LongInt; St, Er, Os : String;
Begin
  Bs := 1024 Shl D32(24);
  Write('Filesystem volume name:   ');
  If VolName = '' Then WriteLn('<none>') Else WriteLn(VolName);
  Write('Last mounted on:          ');
  If Sb[136] = 0 Then WriteLn('<not available>') Else
  Begin
    St := '';
    Er := '';
    Os := '';
    WriteLn('<see /proc/mounts>');
  End;
  WriteLn('Filesystem UUID:          ', UuidS);
  WriteLn('Filesystem magic number:  0xEF53');
  WriteLn('Filesystem revision #:    ', D32(76), ' (', 'dynamic',')');
  WriteLn('Filesystem features:      ', Feats);
  If (D16(58) And 1) <> 0 Then St := 'clean' Else St := 'not clean';
  If (D16(58) And 2) <> 0 Then St := St + ' with errors';
  WriteLn('Filesystem state:         ', St);
  Case D16(60) Of
    1 : Er := 'Continue';
    2 : Er := 'Remount read-only';
    3 : Er := 'Panic';
  Else
    Er := 'Unknown (continue)';
  End;
  WriteLn('Errors behavior:          ', Er);
  WriteLn('Inode count:              ', D32(0));
  WriteLn('Block count:              ', D32(4));
  WriteLn('Reserved block count:     ', D32(8));
  WriteLn('Free blocks:              ', D32(12));
  WriteLn('Free inodes:              ', D32(16));
  WriteLn('First block:              ', D32(20));
  WriteLn('Block size:               ', Bs);
  WriteLn('Blocks per group:         ', D32(32));
  WriteLn('Inodes per group:         ', D32(40));
  WriteLn('Inode blocks per group:   ', 0);
  WriteLn('Last mount time:          ', TimeS(D32(44)));
  WriteLn('Last write time:          ', TimeS(D32(48)));
  WriteLn('Mount count:              ', D16(52));
  MaxM := D16(54);
  If MaxM > 32767 Then MaxM := MaxM - 65536;
  WriteLn('Maximum mount count:      ', MaxM);
  WriteLn('Last checked:             ', TimeS(D32(64)));
  If D32(68) = 0 Then WriteLn('Check interval:           0 (<none>)')
  Else WriteLn('Check interval:           ', D32(68), ' (',
    D32(68) Div 86400, ' days)');
  WriteLn('Inode size:	          ', D16(88));
End;

Function ParseDur(Const S : String) : LongInt;
Var T : String; V, E, M : LongInt;
Begin
  T := S;
  M := 86400;
  If Length(T) > 0 Then
    Case UpCase(T[Length(T)]) Of
      'D' : Delete(T, Length(T), 1);
      'W' :
        Begin
          M := 7 * 86400;
          Delete(T, Length(T), 1);
        End;
      'M' :
        Begin
          M := 30 * 86400;
          Delete(T, Length(T), 1);
        End;
    End;
  Val(T, V, E);
  If E <> 0 Then Die('duree invalide : ' + S);
  ParseDur := V * M;
End;

Var
  I, Mode, V, E : LongInt;
  A, NewLabel, Arg : String;
  DoL, DoM, DoC, DoCC, DoI, DoE, ListOnly, PrintMin : Boolean;
  PctS, MaxS, CntS, IntS, ErrS : String;
Begin
  CrcInit;
  Prog := SysArgStr(0);
  I := Length(Prog);
  While (I > 0) And (Prog[I] <> '/') Do Dec(I);
  Prog := Copy(Prog, I + 1, 20);
  Dev := '';
  DoL := False; DoM := False; DoC := False; DoCC := False; DoI := False;
  DoE := False; ListOnly := False; PrintMin := False;
  I := 1;
  While I < SysArgCount Do
  Begin
    A := SysArgStr(I);
    If (A = '-h') Or (A = '-l') Then ListOnly := True
    Else If A = '-P' Then PrintMin := True
    Else If (A = '-L') And (I + 1 < SysArgCount) Then
    Begin
      Inc(I);
      NewLabel := SysArgStr(I);
      DoL := True;
    End
    Else If (A = '-m') And (I + 1 < SysArgCount) Then
    Begin
      Inc(I);
      PctS := SysArgStr(I);
      DoM := True;
    End
    Else If (A = '-c') And (I + 1 < SysArgCount) Then
    Begin
      Inc(I);
      MaxS := SysArgStr(I);
      DoC := True;
    End
    Else If (A = '-C') And (I + 1 < SysArgCount) Then
    Begin
      Inc(I);
      CntS := SysArgStr(I);
      DoCC := True;
    End
    Else If (A = '-i') And (I + 1 < SysArgCount) Then
    Begin
      Inc(I);
      IntS := SysArgStr(I);
      DoI := True;
    End
    Else If (A = '-e') And (I + 1 < SysArgCount) Then
    Begin
      Inc(I);
      ErrS := SysArgStr(I);
      DoE := True;
    End
    Else If (A <> '') And (A[1] <> '-') Then
    Begin
      If Dev = '' Then Dev := A
      Else If (Prog = 'e2label') And Not DoL Then
      Begin
        NewLabel := A;
        DoL := True;
      End
      Else Arg := A;
    End
    Else Die('option inconnue : ' + A);
    Inc(I);
  End;
  If Dev = '' Then
    Die('usage : dumpe2fs [-h] dev | tune2fs [-l] [-L n] [-m p] [-c n] ' +
        '[-C n] [-i d] [-e m] dev | e2label dev [n] | resize2fs dev');
  If Prog = 'dumpe2fs' Then
  Begin
    OpenDev(False);
    WriteLn('dumpe2fs 1.47.0 (LINUX-0)');
    Show;
    SysExit(0);
  End;
  If Prog = 'resize2fs' Then
  Begin
    OpenDev(False);
    V := D32(4);
    If PrintMin Then
    Begin
      WriteLn('Estimated minimum size of the filesystem: ', V - D32(12));
      SysExit(0);
    End;
    If (Arg = '') Or (Arg = NumS(V)) Then
    Begin
      WriteLn('The filesystem is already ', V, ' (', 1024 Shl D32(24),
        'k) blocks long.  Nothing to do!');
      SysExit(0);
    End;
    Die('changement de taille non pris en charge (' + Arg + ' blocs demandes)');
  End;
  If Prog = 'e2label' Then
  Begin
    If Not DoL Then
    Begin
      OpenDev(False);
      WriteLn(VolName);
      SysExit(0);
    End;
  End;
  OpenDev(DoL Or DoM Or DoC Or DoCC Or DoI Or DoE);
  If DoL Then
  Begin
    If Length(NewLabel) > 16 Then Die('nom trop long (16 caracteres au plus)');
    FillChar(Sb[120], 16, 0);
    For I := 1 To Length(NewLabel) Do Sb[119 + I] := Ord(NewLabel[I]);
  End;
  If DoM Then
  Begin
    Val(PctS, V, E);
    If (E <> 0) Or (V < 0) Or (V > 50) Then
      Die('pourcentage invalide : ' + PctS);
    P32(8, D32(4) Div 100 * V + (D32(4) Mod 100) * V Div 100);
    WriteLn('Setting reserved blocks percentage to ', V, '% (', D32(8),
      ' blocks)');
  End;
  If DoC Then
  Begin
    Val(MaxS, V, E);
    If E <> 0 Then Die('valeur invalide : ' + MaxS);
    If V = 0 Then V := -1;
    P16(54, V And $FFFF);
    WriteLn('Setting maximal mount count to ', V);
  End;
  If DoCC Then
  Begin
    Val(CntS, V, E);
    If E <> 0 Then Die('valeur invalide : ' + CntS);
    P16(52, V);
    WriteLn('Setting current mount count to ', V);
  End;
  If DoI Then
  Begin
    V := ParseDur(IntS);
    P32(68, V);
    WriteLn('Setting interval between checks to ', V, ' seconds');
  End;
  If DoE Then
  Begin
    If ErrS = 'continue' Then P16(60, 1)
    Else If ErrS = 'remount-ro' Then P16(60, 2)
    Else If ErrS = 'panic' Then P16(60, 3)
    Else Die('comportement inconnu : ' + ErrS);
    WriteLn('Setting error behavior to ', D16(60));
  End;
  If DoL Or DoM Or DoC Or DoCC Or DoI Or DoE Then SaveSb;
  If ListOnly Then
  Begin
    WriteLn('tune2fs 1.47.0 (LINUX-0)');
    Show;
  End;
End.
