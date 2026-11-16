{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2026
  @website(https://www.gladir.com/linux-0)
  @abstract(Target: LPC -3X)
  @description: FSPROBE.INC : reconnaissance du contenu d'un peripherique
      bloc (ext2/3/4, FAT, iso9660, minix, cramfs, romfs, swap) : type, nom
      de volume et UUID lus dans le superbloc. Utilise par blkid, lsblk,
      mount -L/-U (FSINFO.PAS, MOUNT.PAS). Declare : Sb, Probe.
}

Var
  Sb : Array[0..4095] Of Byte;

Function Rd32(Off : LongInt) : LongInt;
Begin
  Rd32 := Sb[Off] + Sb[Off + 1] * 256 + Sb[Off + 2] * 65536 +
          Sb[Off + 3] * 16777216;
End;

Function Rd16(Off : LongInt) : LongInt;
Begin
  Rd16 := Sb[Off] + Sb[Off + 1] * 256;
End;

Function Hx(V, N : LongInt) : String;
Const D : String = '0123456789abcdef';
Var R : String; K : LongInt;
Begin
  R := '';
  For K := N - 1 DownTo 0 Do R := R + D[((V Shr (K * 4)) And 15) + 1];
  Hx := R;
End;

Function UpperS(Const S : String) : String;
Var R : String; K : LongInt;
Begin
  R := S;
  For K := 1 To Length(R) Do R[K] := UpCase(R[K]);
  UpperS := R;
End;

Function TrimR(Const S : String) : String;
Var N : LongInt;
Begin
  N := Length(S);
  While (N > 0) And (S[N] In [' ', #0]) Do Dec(N);
  TrimR := Copy(S, 1, N);
End;

Function SbStr(Off, Len : LongInt) : String;
Var R : String; K : LongInt;
Begin
  R := '';
  For K := 0 To Len - 1 Do
  Begin
    If Sb[Off + K] = 0 Then Break;
    R := R + Chr(Sb[Off + K]);
  End;
  SbStr := R;
End;

Function UuidStr(Off : LongInt) : String;
Var K : LongInt; R : String;
Begin
  R := '';
  For K := 0 To 15 Do
  Begin
    R := R + Hx(Sb[Off + K], 2);
    If K In [3, 5, 7, 9] Then R := R + '-';
  End;
  UuidStr := R;
End;

Function ReadAt(Fd, Off, Len : LongInt) : LongInt;
Begin
  FillChar(Sb, SizeOf(Sb), 0);
  If SysLSeek(Fd, Off, SEEK_SET) < 0 Then
  Begin
    ReadAt := -1;
    Exit;
  End;
  ReadAt := LnxSys3(3, Fd, LongInt(@Sb), Len);
End;

{ Typ, Lbl, Uuid du contenu de Path (peripherique ou fichier) }
Procedure Probe(Const Path : String; Var Typ, Lbl, Uuid : String);
Var Fd, N, Cp, Inc_, Ro : LongInt;
Begin
  Typ := '';
  Lbl := '';
  Uuid := '';
  Fd := SysOpen(Path, O_RDONLY, 0);
  If Fd < 0 Then Exit;
  { ext2/3/4 : superbloc a 1024 }
  N := ReadAt(Fd, 1024, 1024);
  If (N >= 264) And (Rd16(56) = $EF53) Then
  Begin
    Cp := Rd32(92);
    Inc_ := Rd32(96);
    Ro := Rd32(100);
    Typ := 'ext2';
    If (Cp And 4) <> 0 Then Typ := 'ext3';
    If ((Inc_ And $2C0) <> 0) Or ((Ro And $478) <> 0) Then Typ := 'ext4';
    If ((Cp And 4) = 0) And ((Inc_ And $2C0) = 0) And ((Ro And $478) = 0) Then
      Typ := 'ext2';
    Lbl := SbStr(120, 16);
    Uuid := UuidStr(104);
    SysClose(Fd);
    Exit;
  End;
  { minix : superbloc a 1024, magie a 16 }
  If (N >= 32) Then
  Begin
    Cp := Rd16(16);
    If (Cp = $137F) Or (Cp = $138F) Or (Cp = $2468) Or (Cp = $2478) Then
    Begin
      Typ := 'minix';
      SysClose(Fd);
      Exit;
    End;
    If Rd16(24) = $4D5A Then
    Begin
      Typ := 'minix';
      SysClose(Fd);
      Exit;
    End;
  End;
  { debut du peripherique : FAT, cramfs, romfs, swap, ... }
  N := ReadAt(Fd, 0, 512);
  If N >= 512 Then
  Begin
    If Rd32(0) = $28CD3D45 Then
    Begin
      Typ := 'cramfs';
      Lbl := SbStr(48, 16);
      SysClose(Fd);
      Exit;
    End;
    If SbStr(0, 8) = '-rom1fs-' Then
    Begin
      Typ := 'romfs';
      Lbl := SbStr(16, 16);
      SysClose(Fd);
      Exit;
    End;
    If (Sb[510] = $55) And (Sb[511] = $AA) Then
    Begin
      If Copy(SbStr(82, 5), 1, 3) = 'FAT' Then
      Begin
        Typ := 'vfat';
        Lbl := TrimR(SbStr(71, 11));
        Uuid := UpperS(Hx(Rd16(69), 4) + '-' + Hx(Rd16(67), 4));
        SysClose(Fd);
        Exit;
      End;
      If (Copy(SbStr(54, 5), 1, 3) = 'FAT') Or (Sb[0] = $EB) Or
         (Sb[0] = $E9) Then
        If (Sb[11] = 0) And (Sb[12] In [2, 4, 8, 16]) Or (Sb[11] <> 0) Then
        Begin
          If (Copy(SbStr(54, 5), 1, 3) = 'FAT') Then
          Begin
            Typ := 'vfat';
            Lbl := TrimR(SbStr(43, 11));
            Uuid := UpperS(Hx(Rd16(41), 4) + '-' + Hx(Rd16(39), 4));
            SysClose(Fd);
            Exit;
          End;
        End;
    End;
  End;
  { swap : signature a 4086 }
  N := ReadAt(Fd, 0, 4096);
  If N >= 4096 Then
  Begin
    If (SbStr(4086, 10) = 'SWAPSPACE2') Or (SbStr(4086, 10) = 'SWAP-SPACE') Then
    Begin
      Typ := 'swap';
      If SbStr(4086, 10) = 'SWAPSPACE2' Then
      Begin
        Uuid := UuidStr(1036);
        Lbl := SbStr(1052, 16);
      End;
      SysClose(Fd);
      Exit;
    End;
  End;
  { iso9660 : descripteur a 32768 }
  N := ReadAt(Fd, 32768, 2048);
  If (N >= 2048) And (SbStr(1, 5) = 'CD001') Then
  Begin
    Typ := 'iso9660';
    Lbl := TrimR(SbStr(40, 32));
  End;
  SysClose(Fd);
End;

