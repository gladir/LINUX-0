{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2026
  @website(https://www.gladir.com/linux-0)
  @abstract(Target: LPC -3X)
  @description: DISKS.INC : disques et table de partitions MBR de l'assistant.
      Detection (/proc/partitions), lecture et ecriture du MBR (quatre
      partitions primaires), calcul de l'espace libre, ecriture du chargeur
      (MBR + stage2), relecture de la table par le noyau (BLKRRPART). Aucun
      peripherique n'est modifie avant les appels explicites DkWriteTable /
      DkWriteBoot. Inclure apres WIDGETS.INC.
}

Const
  PT_LINUX = $83;  PT_SWAP = $82;
  ROLE_NONE = 0;  ROLE_ROOT = 1;  ROLE_SWAP = 2;  ROLE_HOME = 3;
  ALIGN_SEC = 2048;                 { debut de partition : 1 Mio }
  MAXDISK = 8;
  MAXPT = 12;                       { 4 primaires + 8 logiques (5..12) }
  PT_EXT = $05;

Type
  TPart = Record
    Used, Active : Boolean;
    Start, Size, Typ, Role, Fs : LongInt;   { Fs : 2, 3, 4 ou 0 (defaut) }
  End;

Var
  DkName : Array[0..MAXDISK - 1] Of String[16];
  DkSize : Array[0..MAXDISK - 1] Of LongInt;      { secteurs de 512 octets }
  DkCount : LongInt;
  Dsk : String;                                   { /dev/hda }
  DskSec : LongInt;
  Pt : Array[1..MAXPT] Of TPart;      { 5..12 : logiques, ordre du disque }
  Mbr : Array[0..511] Of Byte;
  St2 : Array[0..65535] Of Byte;
  St2Len : LongInt;

{ ---- detection ---- }

{ n-ieme mot (de 1) d'une ligne }
Function DkField(Const L : String; N : LongInt) : String;
Var I, K, S : LongInt;
Begin
  DkField := '';
  I := 1;
  For K := 1 To N Do
  Begin
    While (I <= Length(L)) And (L[I] = ' ') Do Inc(I);
    S := I;
    While (I <= Length(L)) And (L[I] <> ' ') Do Inc(I);
    If K = N Then DkField := Copy(L, S, I - S);
  End;
End;

Function DkIsDisk(Const N : String) : Boolean;
Begin
  DkIsDisk := False;
  If Length(N) < 3 Then Exit;
  If (Copy(N, 1, 2) = 'hd') Or (Copy(N, 1, 2) = 'sd') Or
     (Copy(N, 1, 2) = 'vd') Then
    DkIsDisk := (N[Length(N)] < '0') Or (N[Length(N)] > '9');
End;

{ le peripherique (ou l'une de ses partitions) est-il monte ou en swap ? }
Function DkBusy(Const Dev : String) : Boolean;
Var F, K : LongInt; L : String;
Begin
  DkBusy := False;
  For K := 1 To 2 Do
  Begin
    If K = 1 Then F := SysOpen('/proc/mounts', O_RDONLY, 0)
    Else F := SysOpen('/proc/swaps', O_RDONLY, 0);
    If F >= 0 Then
    Begin
      While SysReadLine(F, L) Do
        If Copy(L, 1, Length(Dev)) = Dev Then DkBusy := True;
      SysClose(F);
    End;
  End;
End;

{ disques durs utilisables : ni le CD ni un disque monte }
Procedure DkScan;
Var F, Blocks, E : LongInt; L, N : String;
Begin
  DkCount := 0;
  F := SysOpen('/proc/partitions', O_RDONLY, 0);
  If F < 0 Then Exit;
  While SysReadLine(F, L) Do
  Begin
    N := DkField(L, 4);
    If DkIsDisk(N) And (DkCount < MAXDISK) Then
    Begin
      Val(DkField(L, 3), Blocks, E);
      If (E = 0) And (Blocks >= 8192) And Not DkBusy('/dev/' + N) Then
      Begin
        DkName[DkCount] := N;
        DkSize[DkCount] := Blocks * 2;
        Inc(DkCount);
      End;
    End;
  End;
  SysClose(F);
End;

{ numero de la partition N (1..4) du disque Dsk : /dev/hda1, /dev/vda1 }
Function DkPartDev(N : LongInt) : String;
Var S : String;
Begin
  Str(N, S);
  DkPartDev := Dsk + S;
End;

{ ---- table de partitions ---- }

Function DkGetD(Off : LongInt) : LongInt;
Begin
  DkGetD := Mbr[Off] Or (Mbr[Off + 1] Shl 8) Or (Mbr[Off + 2] Shl 16) Or
            (Mbr[Off + 3] Shl 24);
End;

Procedure DkPutD(Off, V : LongInt);
Begin
  Mbr[Off] := V And 255;
  Mbr[Off + 1] := (V Shr 8) And 255;
  Mbr[Off + 2] := (V Shr 16) And 255;
  Mbr[Off + 3] := (V Shr 24) And 255;
End;

Procedure DkChs(Lba, Off : LongInt);
Var C, H, S : LongInt;
Begin
  C := Lba Div (255 * 63);
  H := (Lba Div 63) Mod 255;
  S := Lba Mod 63 + 1;
  If C > 1023 Then
  Begin
    C := 1023; H := 254; S := 63;
  End;
  Mbr[Off] := H;
  Mbr[Off + 1] := S Or ((C Shr 8) Shl 6);
  Mbr[Off + 2] := C And 255;
End;

{ taille du disque en secteurs (BLKGETSIZE) }
Function DkSectors(Const Dev : String) : LongInt;
Var Fd, S, E : LongInt;
Begin
  DkSectors := 0;
  Fd := SysOpen(Dev, O_RDONLY, 0);
  If Fd < 0 Then Exit;
  S := 0;
  If SysIoctl(Fd, $1260, S) < 0 Then S := 0;
  If S <= 0 Then
  Begin
    E := SysLSeek(Fd, 0, SEEK_END);
    If E > 0 Then S := E Div 512;
  End;
  SysClose(Fd);
  DkSectors := S;
End;

{ la partition I est-elle la partition etendue ? }
Function DkIsExt(I : LongInt) : Boolean;
Begin
  DkIsExt := (I <= 4) And Pt[I].Used And ((Pt[I].Typ = $05) Or
             (Pt[I].Typ = $0F) Or (Pt[I].Typ = $85));
End;

{ numero (1..4) de la partition etendue, 0 s'il n'y en a pas }
Function DkExt : LongInt;
Var I : LongInt;
Begin
  DkExt := 0;
  For I := 1 To 4 Do
    If DkIsExt(I) Then DkExt := I;
End;

{ place le pointeur du peripherique au secteur Sec (disques > 2 Go) }
Procedure DkSeekSec(Fd, Sec : LongInt);
Var Res : Array[0..1] Of LongInt;
Begin
  SysLLSeek(Fd, Sec Shr 23, (Sec And $7FFFFF) Shl 9, LongInt(@Res), SEEK_SET);
End;

{ lit le MBR du disque Dsk et la chaine des partitions logiques (5..) }
Procedure DkReadTable;
Var Fd, I, O, N, Ex, Base, Lba, Cnt, Nx : LongInt; Eb : Array[0..511] Of Byte;
Begin
  FillChar(Pt, SizeOf(Pt), 0);
  FillChar(Mbr, 512, 0);
  DskSec := DkSectors(Dsk);
  Fd := SysOpen(Dsk, O_RDONLY, 0);
  If Fd < 0 Then Exit;
  N := SysRead(Fd, Mbr, 512);
  SysClose(Fd);
  If (N <> 512) Or (Mbr[510] <> $55) Or (Mbr[511] <> $AA) Then
  Begin
    FillChar(Mbr, 512, 0);
    Exit;
  End;
  For I := 1 To 4 Do
  Begin
    O := 446 + (I - 1) * 16;
    Pt[I].Typ := Mbr[O + 4];
    Pt[I].Start := DkGetD(O + 8);
    Pt[I].Size := DkGetD(O + 12);
    Pt[I].Active := Mbr[O] = $80;
    Pt[I].Used := (Pt[I].Typ <> 0) And (Pt[I].Size > 0);
    Pt[I].Role := ROLE_NONE;
  End;
  { partitions logiques : EBR chaines, premier EBR au debut de l'etendue }
  Ex := DkExt;
  If Ex = 0 Then Exit;
  Base := Pt[Ex].Start;
  Lba := Base;
  N := 5;
  Cnt := 0;
  Fd := SysOpen(Dsk, O_RDONLY, 0);
  If Fd < 0 Then Exit;
  While (Cnt < 16) And (N <= MAXPT) Do
  Begin
    DkSeekSec(Fd, Lba);
    If SysRead(Fd, Eb, 512) <> 512 Then Break;
    If (Eb[510] <> $55) Or (Eb[511] <> $AA) Then Break;
    If (Eb[446 + 4] <> 0) And (Eb[446 + 12] + Eb[446 + 13] <> 0) Then
    Begin
      Pt[N].Used := True;
      Pt[N].Typ := Eb[446 + 4];
      Pt[N].Start := Lba + (Eb[446 + 8] Or (Eb[446 + 9] Shl 8) Or
                     (Eb[446 + 10] Shl 16) Or (Eb[446 + 11] Shl 24));
      Pt[N].Size := Eb[446 + 12] Or (Eb[446 + 13] Shl 8) Or
                    (Eb[446 + 14] Shl 16) Or (Eb[446 + 15] Shl 24);
      Inc(N);
    End;
    Nx := Eb[446 + 16 + 8] Or (Eb[446 + 16 + 9] Shl 8) Or
          (Eb[446 + 16 + 10] Shl 16) Or (Eb[446 + 16 + 11] Shl 24);
    If (Eb[446 + 16 + 4] = 0) Or (Nx = 0) Then Break;
    Lba := Base + Nx;
    Inc(Cnt);
  End;
  SysClose(Fd);
End;

Procedure DkClearTable;
Begin
  FillChar(Pt, SizeOf(Pt), 0);
End;

Function DkLastUsable : LongInt;
Begin
  DkLastUsable := DskSec - 1;
End;

{ espace libre : plus grande plage libre (debut, taille) alignee ; rend
  False s'il n'y a pas de place ou pas d'emplacement libre }
Function DkFreeSlot : LongInt;
Var I : LongInt;
Begin
  DkFreeSlot := 0;
  For I := 1 To 4 Do
    If Not Pt[I].Used Then
    Begin
      DkFreeSlot := I;
      Exit;
    End;
End;

{ plage libre numero K (0..) en ordre de position : debut et taille }
Function DkGap(K : LongInt; Var GStart, GSize : LongInt) : Boolean;
Var Ord_ : Array[1..4] Of LongInt; I, J, T, N, Pos, Idx, Gs : LongInt;
Begin
  N := 0;
  For I := 1 To 4 Do
    If Pt[I].Used Then
    Begin
      Inc(N);
      Ord_[N] := I;
    End;
  For I := 1 To N - 1 Do
    For J := I + 1 To N Do
      If Pt[Ord_[J]].Start < Pt[Ord_[I]].Start Then
      Begin
        T := Ord_[I]; Ord_[I] := Ord_[J]; Ord_[J] := T;
      End;
  Pos := ALIGN_SEC;
  Idx := 0;
  DkGap := False;
  For I := 1 To N + 1 Do
  Begin
    If I <= N Then Gs := Pt[Ord_[I]].Start - Pos Else Gs := DskSec - Pos;
    If Gs >= ALIGN_SEC Then
    Begin
      If Idx = K Then
      Begin
        GStart := Pos;
        GSize := Gs;
        DkGap := True;
        Exit;
      End;
      Inc(Idx);
    End;
    If I <= N Then
    Begin
      Pos := Pt[Ord_[I]].Start + Pt[Ord_[I]].Size;
      Pos := ((Pos + ALIGN_SEC - 1) Div ALIGN_SEC) * ALIGN_SEC;
    End;
  End;
End;

{ cree une partition de Size secteurs dans la plage libre K ; rend son numero
  (0 : echec) }
Function DkCreate(K, Size, Typ : LongInt) : LongInt;
Var Gs, Gz, Slot : LongInt;
Begin
  DkCreate := 0;
  Slot := DkFreeSlot;
  If Slot = 0 Then Exit;
  If Not DkGap(K, Gs, Gz) Then Exit;
  If Size > Gz Then Size := Gz;
  If Size < 2048 Then Exit;
  Pt[Slot].Used := True;
  Pt[Slot].Start := Gs;
  Pt[Slot].Size := Size;
  Pt[Slot].Typ := Typ;
  Pt[Slot].Active := False;
  Pt[Slot].Role := ROLE_NONE;
  DkCreate := Slot;
End;

{ nombre de partitions logiques (5..) }
Function DkLogCount : LongInt;
Var I, N : LongInt;
Begin
  N := 0;
  For I := 5 To MAXPT Do
    If Pt[I].Used Then Inc(N);
  DkLogCount := N;
End;

{ plage libre numero K (0..) a l'interieur de la partition etendue : GStart =
  place du futur EBR, GSize = taille de la plage (EBR de 1 Mio compris) }
Function DkLgGap(K : LongInt; Var GStart, GSize : LongInt) : Boolean;
Var Ex, I, Pos, Gs, Idx, ExEnd, Rg : LongInt;
Begin
  DkLgGap := False;
  Ex := DkExt;
  If Ex = 0 Then Exit;
  Pos := Pt[Ex].Start;
  ExEnd := Pt[Ex].Start + Pt[Ex].Size;
  Idx := 0;
  For I := 5 To MAXPT + 1 Do
  Begin
    If (I <= MAXPT) And Pt[I].Used Then Rg := Pt[I].Start - ALIGN_SEC
    Else If I > MAXPT Then Rg := ExEnd
    Else Continue;
    Gs := Rg - Pos;
    If Gs >= 2 * ALIGN_SEC Then
    Begin
      If Idx = K Then
      Begin
        GStart := Pos;
        GSize := Gs;
        DkLgGap := True;
        Exit;
      End;
      Inc(Idx);
    End;
    If I <= MAXPT Then
    Begin
      Pos := Pt[I].Start + Pt[I].Size;
      Pos := ((Pos + ALIGN_SEC - 1) Div ALIGN_SEC) * ALIGN_SEC;
    End;
  End;
End;

{ cree une partition logique de Size secteurs dans la plage K de l'etendue ;
  rend son numero (5..) ou 0 }
Function DkCreateLog(K, Size, Typ : LongInt) : LongInt;
Var Gs, Gz, St, I, J : LongInt;
Begin
  DkCreateLog := 0;
  If DkLogCount >= MAXPT - 4 Then Exit;
  If Not DkLgGap(K, Gs, Gz) Then Exit;
  If Size > Gz - ALIGN_SEC Then Size := Gz - ALIGN_SEC;
  If Size < 2048 Then Exit;
  St := Gs + ALIGN_SEC;
  I := 5;
  While (I <= MAXPT) And Pt[I].Used And (Pt[I].Start < St) Do Inc(I);
  { decale les suivantes d'un cran }
  For J := MAXPT DownTo I + 1 Do Pt[J] := Pt[J - 1];
  FillChar(Pt[I], SizeOf(TPart), 0);
  Pt[I].Used := True;
  Pt[I].Start := St;
  Pt[I].Size := Size;
  Pt[I].Typ := Typ;
  DkCreateLog := I;
End;

{ supprime la partition I ; l'etendue emporte ses partitions logiques }
Procedure DkDelete(I : LongInt);
Var J : LongInt;
Begin
  If DkIsExt(I) Then
    For J := 5 To MAXPT Do FillChar(Pt[J], SizeOf(TPart), 0);
  If I >= 5 Then
  Begin
    For J := I To MAXPT - 1 Do Pt[J] := Pt[J + 1];
    FillChar(Pt[MAXPT], SizeOf(TPart), 0);
  End
  Else FillChar(Pt[I], SizeOf(TPart), 0);
End;

{ ecrit les EBR des partitions logiques (le premier au debut de l'etendue) }
Function DkWriteLogical(Fd : LongInt) : Boolean;
Var Ex, J, Nx, E : LongInt; Z : Array[0..511] Of Byte;
Begin
  DkWriteLogical := True;
  Ex := DkExt;
  If Ex = 0 Then Exit;
  FillChar(Z, 512, 0);
  { etendue sans logique ou ancien EBR : secteur vierge au debut }
  DkSeekSec(Fd, Pt[Ex].Start);
  SysWrite(Fd, Z, 512);
  For J := 5 To MAXPT Do
    If Pt[J].Used Then
    Begin
      E := Pt[J].Start - ALIGN_SEC;
      FillChar(Mbr, 512, 0);
      Mbr[446 + 4] := Pt[J].Typ;
      DkChs(Pt[J].Start, 446 + 1);
      DkChs(Pt[J].Start + Pt[J].Size - 1, 446 + 5);
      DkPutD(446 + 8, Pt[J].Start - E);
      DkPutD(446 + 12, Pt[J].Size);
      If (J < MAXPT) And Pt[J + 1].Used Then
      Begin
        Nx := Pt[J + 1].Start - ALIGN_SEC;
        Mbr[446 + 16 + 4] := PT_EXT;
        DkChs(Nx, 446 + 16 + 1);
        DkChs(Pt[J + 1].Start + Pt[J + 1].Size - 1, 446 + 16 + 5);
        DkPutD(446 + 16 + 8, Nx - Pt[Ex].Start);
        DkPutD(446 + 16 + 12, Pt[J + 1].Start + Pt[J + 1].Size - Nx);
      End;
      Mbr[510] := $55;
      Mbr[511] := $AA;
      DkSeekSec(Fd, E);
      If SysWrite(Fd, Mbr, 512) <> 512 Then DkWriteLogical := False;
    End;
End;

{ ecrit le MBR (code de MBR.BIN, parametres du chargeur, table, signature) }
Function DkWriteTable : Boolean;
Var Fd, F2, N, I, O : LongInt; Code : Array[0..511] Of Byte;
Begin
  DkWriteTable := False;
  FillChar(Code, 512, 0);
  F2 := SysOpen('/usr/share/boot/MBR.BIN', O_RDONLY, 0);
  If F2 < 0 Then Exit;
  N := SysRead(F2, Code, 512);
  SysClose(F2);
  F2 := SysOpen('/usr/share/boot/STAGE2.BIN', O_RDONLY, 0);
  If F2 < 0 Then Exit;
  St2Len := 0;
  Repeat
    N := SysRead(F2, St2[St2Len], 65536 - St2Len);
    If N > 0 Then St2Len := St2Len + N;
  Until N <= 0;
  SysClose(F2);
  N := (St2Len + 511) Div 512;
  For I := 1 To 4 Do
    If Pt[I].Used And (Pt[I].Start < N + 2) Then Exit;
  FillChar(Mbr, 512, 0);
  Move(Code, Mbr, 440);
  DkPutD(3, 1);
  Mbr[7] := N And 255;
  Mbr[8] := (N Shr 8) And 255;
  For I := 1 To 4 Do
  Begin
    O := 446 + (I - 1) * 16;
    If Pt[I].Used Then
    Begin
      If Pt[I].Active Then Mbr[O] := $80;
      DkChs(Pt[I].Start, O + 1);
      Mbr[O + 4] := Pt[I].Typ;
      DkChs(Pt[I].Start + Pt[I].Size - 1, O + 5);
      DkPutD(O + 8, Pt[I].Start);
      DkPutD(O + 12, Pt[I].Size);
    End;
  End;
  Mbr[510] := $55;
  Mbr[511] := $AA;
  Fd := SysOpen(Dsk, O_RDWR, 0);
  If Fd < 0 Then Exit;
  If SysLSeek(Fd, 0, SEEK_SET) <> 0 Then
  Begin
    SysClose(Fd);
    Exit;
  End;
  If SysWrite(Fd, Mbr, 512) <> 512 Then
  Begin
    SysClose(Fd);
    Exit;
  End;
  { chargeur de la deuxieme etape : secteurs 1.. }
  SysLSeek(Fd, 512, SEEK_SET);
  FillChar(St2[St2Len], N * 512 - St2Len, 0);
  If SysWrite(Fd, St2, N * 512) <> N * 512 Then
  Begin
    SysClose(Fd);
    Exit;
  End;
  If Not DkWriteLogical(Fd) Then
  Begin
    SysClose(Fd);
    Exit;
  End;
  LnxSys3(118, Fd, 0, 0);
  SysClose(Fd);
  SysSync;
  DkWriteTable := True;
End;

{ demande au noyau de relire la table (BLKRRPART) et attend /dev/hdaN }
Function DkReread : Boolean;
Var Fd, I, K : LongInt; Ok : Boolean; S : TSysStat;
Begin
  DkReread := False;
  Fd := SysOpen(Dsk, O_RDONLY, 0);
  If Fd < 0 Then Exit;
  SysIoctlL(Fd, $125F, 0);
  SysClose(Fd);
  For K := 1 To 40 Do
  Begin
    Ok := True;
    For I := 1 To MAXPT Do
      If Pt[I].Used And Not DkIsExt(I) And
         (SysStat(DkPartDev(I), S) < 0) Then Ok := False;
    If Ok Then
    Begin
      DkReread := True;
      Exit;
    End;
    SysSleep(1);
  End;
End;

Function DkMb(Sec : LongInt) : LongInt;
Begin
  DkMb := Sec Div 2048;
End;
