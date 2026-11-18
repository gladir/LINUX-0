{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2026
  @website(https://www.gladir.com/linux-0)
  @abstract(Target: LPC -3X)
  @description: e2fsck (e2fsck-lite), fsck, fsck.ext2/3/4 : verification en
      LECTURE SEULE d'un systeme de fichiers ext2/ext3/ext4 (equivalent de
      e2fsck -n), sortie proche de e2fsck : superbloc, descripteurs de
      groupes, passes 1 (inodes, blocs, tailles, i_blocks, blocs partages),
      2 (repertoires : rec_len, entrees, types), 3 (connexite), 4 (nombres
      de liens), 5 (bitmaps et compteurs libres). Aucune correction n'est
      faite (reponse toujours "no"). Blocs mappes et extents. Code de sortie
      0 sain, 4 erreurs. fsck [-t type] [-N] [-A] [options] [dispositif...]
      choisit fsck.<type> d'apres /etc/fstab ou -t. Limites : 524288 inodes,
      33554432 blocs, 4096 groupes.
}

Program E2FSCK;

Const
  MaxIno = 524288;
  MaxBlkBits = 33554432;
  MaxGrp = 4096;
  Usage : Array[1..5] Of PChar = (
    'Usage : e2fsck [-fnpvy] dispositif | fsck [-t type] [-AN] [dispositif...]',
    'Usage: e2fsck [-fnpvy] device | fsck [-t type] [-AN] [device...]',
    'Aufruf: e2fsck [-fnpvy] Geraet | fsck [-t Typ] [-AN] [Geraet...]',
    'Uso: e2fsck [-fnpvy] dispositivo | fsck [-t tipo] [-AN] [dispositivo...]',
    'Uso: e2fsck [-fnpvy] dispositivo | fsck [-t tipo] [-AN] [dispositivo...]');

Var
  Lang : LongInt;
  Prog, Dev : String;
  Fd : LongInt;
  Force, Verbose, Preen : Boolean;
  Buf : Array[0..65535] Of Byte;
  SB : Array[0..1023] Of Byte;
  BS, LogBs, NBlocks, FirstData, BPG, IPG, NGroups, ISize, NInodes : LongInt;
  FCompat, FIncompat, FRoCompat, State, DescSize, ResGdt, GdtBlocks : LongInt;
  FreeBlocksSB, FreeInodesSB, FirstIno, Rev : LongInt;
  GdBB, GdIB, GdIT, GdFB, GdFI, GdDirs : Array[0..MaxGrp - 1] Of LongInt;
  CalcBB : Array[0..MaxBlkBits Div 8] Of Byte;
  Flags : Array[0..MaxIno] Of Byte;     { 1 utilise 2 repertoire 4 vu en pass2 }
  Mode16 : Array[0..MaxIno] Of Word;
  ILinks : Array[0..MaxIno] Of Word;
  Cnt : Array[0..MaxIno] Of Word;       { liens comptes (pass 2) }
  Par : Array[0..MaxIno] Of LongInt;    { repertoire contenant }
  DotDot : Array[0..MaxIno] Of LongInt;
  Nm : Array[0..MaxIno] Of String[23];
  Errors : LongInt;
  NFiles, NFrag, UsedBlocks : LongInt;
  { enumeration des blocs d'un inode }
  CurIno, NData, NMeta, PrevBlk : LongInt;
  CurDir : LongInt;
  CollectDir : Boolean;
  DirBlk : Array[0..16383] Of LongInt;
  NDirBlk : LongInt;
  Frag : Boolean;
  BadBlk : Boolean;
  DupN : LongInt;
  DupIno : Array[0..255] Of LongInt;
  DupBlk : Array[0..255] Of LongInt;
  Part : String;
  PartOff : LongInt;       { decalage de la partition (dev?offset=N) }

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
  SysPut(1, S + #10);
End;

{ probleme : le message et la question (reponse toujours "no") ; Same :
  question sur la meme ligne (deux espaces), comme e2fsck pour certains }
Procedure Problem2(Const Msg, Ask : String; Same, Count : Boolean);
Begin
  If Count Then Inc(Errors);
  If Ask = '' Then Say(Msg)
  Else If Same Then Say(Msg + '  ' + Ask + ' no')
  Else
  Begin
    Say(Msg);
    Say(Ask + ' no');
  End;
  Say('');
End;

Procedure Problem(Const Msg, Ask : String);
Begin
  Problem2(Msg, Ask, False, True);
End;

Procedure ProblemS(Const Msg, Ask : String);
Begin
  Problem2(Msg, Ask, True, True);
End;

Procedure Fatal(Const S : String);
Begin
  SysPut(2, 'e2fsck: ' + S + #10);
  SysExit(8);
End;

Function U16(Var B : Array Of Byte; O : LongInt) : LongInt;
Begin
  U16 := B[O] Or (B[O + 1] Shl 8);
End;

Function U32(Var B : Array Of Byte; O : LongInt) : LongInt;
Begin
  U32 := U16(B, O) Or (U16(B, O + 2) Shl 16);
End;

Function SeekBlk(B : LongInt) : Boolean;
Var Lo, Hi, Res : LongInt;
Begin
  Lo := B Shl LogBs;
  Hi := B Shr (32 - LogBs);
  Lo := Lo + PartOff;
  If (Lo < PartOff) And (PartOff > 0) Then Inc(Hi);
  SeekBlk := SysLLSeek(Fd, Hi, Lo, LongInt(@Res), SEEK_SET) >= 0;
End;

Function ReadBlk(B : LongInt) : Boolean;
Var N, Got : LongInt;
Begin
  ReadBlk := False;
  If (B < 0) Or (B >= NBlocks) Then Exit;
  If Not SeekBlk(B) Then Exit;
  Got := 0;
  While Got < BS Do
  Begin
    N := SysRead(Fd, Buf[Got], BS - Got);
    If N <= 0 Then Exit;
    Got := Got + N;
  End;
  ReadBlk := True;
End;

{ ---------- bitmaps calculees ---------- }

Function GetB(Blk : LongInt) : Boolean;
Begin
  GetB := (CalcBB[Blk Shr 3] And (1 Shl (Blk And 7))) <> 0;
End;

Procedure SetB(Blk : LongInt);
Begin
  CalcBB[Blk Shr 3] := CalcBB[Blk Shr 3] Or (1 Shl (Blk And 7));
End;

{ ---------- ouverture et superbloc ---------- }

Function IsPow(G, Base : LongInt) : Boolean;
Var N : LongInt;
Begin
  N := Base;
  While N < G Do N := N * Base;
  IsPow := N = G;
End;

Function HasSuper(G : LongInt) : Boolean;
Begin
  If (FRoCompat And 1) = 0 Then
  Begin
    HasSuper := True;
    Exit;
  End;
  HasSuper := (G = 0) Or (G = 1) Or IsPow(G, 3) Or IsPow(G, 5) Or IsPow(G, 7);
End;

Procedure LoadSuper;
Var N, Got, I, Lo, Hi, Res : LongInt;
Begin
  Hi := 0;
  Lo := 1024;
  If SysLLSeek(Fd, 0, 1024 + PartOff, LongInt(@Res), SEEK_SET) < 0 Then
    Fatal('cannot read superblock');
  Got := 0;
  While Got < 1024 Do
  Begin
    N := SysRead(Fd, SB[Got], 1024 - Got);
    If N <= 0 Then Fatal('cannot read superblock');
    Got := Got + N;
  End;
  If U16(SB, 56) <> $EF53 Then
  Begin
    SysPut(2, 'e2fsck: Bad magic number in super-block while trying to open ' +
           Dev + #10);
    SysExit(8);
  End;
  NInodes := U32(SB, 0);
  NBlocks := U32(SB, 4);
  FreeBlocksSB := U32(SB, 12);
  FreeInodesSB := U32(SB, 16);
  FirstData := U32(SB, 20);
  LogBs := 10 + U32(SB, 24);
  BS := 1 Shl LogBs;
  BPG := U32(SB, 32);
  IPG := U32(SB, 40);
  State := U16(SB, 58);
  Rev := U32(SB, 76);
  ISize := 128;
  FirstIno := 11;
  FCompat := 0;
  FIncompat := 0;
  FRoCompat := 0;
  If Rev >= 1 Then
  Begin
    FirstIno := U32(SB, 84);
    ISize := U16(SB, 88);
    FCompat := U32(SB, 92);
    FIncompat := U32(SB, 96);
    FRoCompat := U32(SB, 100);
  End;
  DescSize := 32;
  If (FIncompat And $80) <> 0 Then
  Begin
    DescSize := U16(SB, 254);
    If DescSize < 64 Then DescSize := 64;
    NBlocks := NBlocks Or 0;
  End;
  ResGdt := U16(SB, 206);
  If (BS < 1024) Or (BS > 65536) Or (BPG = 0) Or (IPG = 0) Or
     (NBlocks <= FirstData) Then
    Fatal('superblock is corrupt');
  NGroups := (NBlocks - FirstData + BPG - 1) Div BPG;
  If NGroups > MaxGrp Then Fatal('too many block groups');
  If NInodes > MaxIno Then Fatal('too many inodes (max ' + NumS(MaxIno) + ')');
  If NBlocks > MaxBlkBits Then Fatal('too many blocks');
  GdtBlocks := (NGroups * DescSize + BS - 1) Div BS;
End;

Procedure LoadGroups;
Var G, Blk, Off, P : LongInt;
Begin
  Blk := FirstData + 1;
  P := 0;
  For G := 0 To NGroups - 1 Do
  Begin
    Off := (G * DescSize) Mod BS;
    If (G * DescSize) Div BS <> P Then
    Begin
      P := (G * DescSize) Div BS;
    End;
    If (Off = 0) Or (G = 0) Then
      If Not ReadBlk(Blk + P) Then Fatal('cannot read group descriptors');
    GdBB[G] := U32(Buf, Off);
    GdIB[G] := U32(Buf, Off + 4);
    GdIT[G] := U32(Buf, Off + 8);
    GdFB[G] := U16(Buf, Off + 12);
    GdFI[G] := U16(Buf, Off + 14);
    GdDirs[G] := U16(Buf, Off + 16);
  End;
End;

{ ---------- enumeration des blocs ---------- }

Procedure Visit(B : LongInt; Meta : Boolean);
Begin
  If (B < FirstData) Or (B >= NBlocks) Then
  Begin
    BadBlk := True;
    Exit;
  End;
  If GetB(B) Then
  Begin
    If DupN < 256 Then
    Begin
      DupIno[DupN] := CurIno;
      DupBlk[DupN] := B;
      Inc(DupN);
    End;
  End
  Else SetB(B);
  If Meta Then Inc(NMeta) Else Inc(NData);
  If (PrevBlk <> 0) And (PrevBlk + 1 <> B) Then Frag := True;
  PrevBlk := B;
  If CollectDir And (Not Meta) And (NDirBlk < 16384) Then
  Begin
    DirBlk[NDirBlk] := B;
    Inc(NDirBlk);
  End;
End;

Var
  IndBuf : Array[0..3, 0..65535] Of Byte;

Procedure WalkInd(B, Level : LongInt);
Var I, N, X : LongInt;
Begin
  If (B < FirstData) Or (B >= NBlocks) Then
  Begin
    BadBlk := True;
    Exit;
  End;
  Visit(B, True);
  If Level > 3 Then Exit;
  If Not ReadBlk(B) Then Exit;
  Move(Buf[0], IndBuf[Level][0], BS);
  N := BS Div 4;
  For I := 0 To N - 1 Do
  Begin
    X := U32(IndBuf[Level], I * 4);
    If X <> 0 Then
      If Level = 1 Then Visit(X, False)
      Else WalkInd(X, Level - 1);
  End;
End;

{ extents : noeud dans B (tableau d'octets) }
Procedure WalkExt(Var E : Array Of Byte; Depth : LongInt);
Var N, I, O, Lo, Len, Start, K, Nx : LongInt; Sub : Array[0..4095] Of Byte;
Begin
  If U16(E, 0) <> $F30A Then
  Begin
    BadBlk := True;
    Exit;
  End;
  N := U16(E, 2);
  For I := 0 To N - 1 Do
  Begin
    O := 12 + I * 12;
    If U16(E, 6) = 0 Then Depth := Depth Else ;
    If U16(E, 6) > 0 Then
    Begin
      { index : feuille_lo (4), feuille_hi (2) }
      Nx := U32(E, O + 4);
      Visit(Nx, True);
      If (Nx >= FirstData) And (Nx < NBlocks) And ReadBlk(Nx) Then
      Begin
        Move(Buf[0], Sub[0], 4096);
        WalkExt(Sub, Depth - 1);
      End;
    End
    Else
    Begin
      Len := U16(E, O + 4);
      If Len > 32768 Then Len := Len - 32768;
      Start := U32(E, O + 8);
      For K := 0 To Len - 1 Do Visit(Start + K, False);
    End;
  End;
End;

Procedure EnumBlocks(Ino : LongInt; Var Inode : Array Of Byte;
                     Collect : Boolean);
Var I, B, Fl, Mode : LongInt;
Begin
  CurIno := Ino;
  CollectDir := Collect;
  NData := 0;
  NMeta := 0;
  PrevBlk := 0;
  Frag := False;
  BadBlk := False;
  If Collect Then NDirBlk := 0;
  Fl := U32(Inode, 32);
  Mode := U16(Inode, 0);
  { liens symboliques courts : pas de blocs }
  If ((Mode And $F000) = $A000) And (U32(Inode, 28) = 0) Then Exit;
  If (Fl And $80000) <> 0 Then
  Begin
    { extents }
    Move(Inode[40], IndBuf[0][0], 60);
    WalkExt(IndBuf[0], 0);
    Exit;
  End;
  For I := 0 To 11 Do
  Begin
    B := U32(Inode, 40 + I * 4);
    If B <> 0 Then Visit(B, False);
  End;
  B := U32(Inode, 40 + 48);
  If B <> 0 Then WalkInd(B, 1);
  B := U32(Inode, 40 + 52);
  If B <> 0 Then WalkInd(B, 2);
  B := U32(Inode, 40 + 56);
  If B <> 0 Then WalkInd(B, 3);
End;

{ ---------- lecture d'un inode ---------- }

Var
  Ino128 : Array[0..511] Of Byte;

Function ReadInode(N : LongInt) : Boolean;
Var G, Idx, Per, Blk, Off : LongInt;
Begin
  ReadInode := False;
  If (N < 1) Or (N > NInodes) Then Exit;
  G := (N - 1) Div IPG;
  Idx := (N - 1) Mod IPG;
  Per := BS Div ISize;
  Blk := GdIT[G] + Idx Div Per;
  Off := (Idx Mod Per) * ISize;
  If Not ReadBlk(Blk) Then Exit;
  Move(Buf[Off], Ino128[0], 256);
  ReadInode := True;
End;

Function PathOf(N : LongInt) : String;
Var S : String; Cnt0, X : LongInt;
Begin
  If N = 2 Then
  Begin
    PathOf := '/';
    Exit;
  End;
  S := '';
  X := N;
  Cnt0 := 0;
  While (X <> 2) And (X > 0) And (Cnt0 < 40) Do
  Begin
    If (Par[X] = 0) Or (Nm[X] = '') Then
    Begin
      PathOf := '<' + NumS(X) + '>' + S;
      If S = '' Then PathOf := '<' + NumS(X) + '>';
      Exit;
    End;
    S := '/' + Nm[X] + S;
    X := Par[X];
    Inc(Cnt0);
  End;
  If S = '' Then S := '/';
  PathOf := S;
End;

{ ---------- passe 1 ---------- }

Procedure Pass1;
Var
  N, G, Idx, Per, Blk, Off, Mode, Exp, Links, Dtime : LongInt;
  Last : LongInt;
  Used : Boolean;
  I : LongInt;
Begin
  Say('Pass 1: Checking inodes, blocks, and sizes');
  { blocs des metadonnees de groupes }
  For G := 0 To NGroups - 1 Do
  Begin
    Blk := FirstData + G * BPG;
    If HasSuper(G) Then
    Begin
      SetB(Blk);
      For I := 1 To GdtBlocks + ResGdt Do
        If Blk + I < NBlocks Then SetB(Blk + I);
    End;
    If (GdBB[G] >= FirstData) And (GdBB[G] < NBlocks) Then SetB(GdBB[G]);
    If (GdIB[G] >= FirstData) And (GdIB[G] < NBlocks) Then SetB(GdIB[G]);
    Per := (IPG * ISize + BS - 1) Div BS;
    For I := 0 To Per - 1 Do
      If (GdIT[G] + I >= FirstData) And (GdIT[G] + I < NBlocks) Then
        SetB(GdIT[G] + I);
  End;
  Per := BS Div ISize;
  NFiles := 0;
  NFrag := 0;
  For N := 1 To NInodes Do
  Begin
    G := (N - 1) Div IPG;
    Idx := (N - 1) Mod IPG;
    If (GdIT[G] = 0) Or (GdIT[G] >= NBlocks) Then Continue;
    If Not ReadInode(N) Then Continue;
    Mode := U16(Ino128, 0);
    Links := U16(Ino128, 26);
    Dtime := U32(Ino128, 20);
    Mode16[N] := Mode;
    ILinks[N] := Links;
    Used := (Links > 0) Or ((N < FirstIno) And (N = 2));
    Mode16[N] := Mode;
    If (N < FirstIno) And (N <> 2) Then
    Begin
      { inodes reserves : blocs marques s'ils en ont }
      If Mode <> 0 Then
      Begin
        EnumBlocks(N, Ino128, False);
        Inc(NFiles);
        Flags[N] := 1;
      End
      Else Inc(NFiles);
      Flags[N] := Flags[N] Or 1;
      Continue;
    End;
    If (Links = 0) And (Mode <> 0) And (Dtime = 0) Then
    Begin
      ProblemS('Deleted inode ' + NumS(N) + ' has zero dtime.', 'Fix?');
      Continue;
    End;
    If Not Used Then Continue;
    Flags[N] := 1;
    Inc(NFiles);
    Case Mode And $F000 Of
      $4000 : Flags[N] := Flags[N] Or 2;
      $8000, $A000, $2000, $6000, $1000, $C000 : ;
    Else
      Begin
        { mode invalide : traite en passe 2 (chemin connu) }
        Flags[N] := Flags[N] Or 8;
        If U32(Ino128, 28) <> 0 Then
          ProblemS('Inode ' + NumS(N) + ', i_blocks is ' +
                   NumS(U32(Ino128, 28)) + ', should be 0.', 'Fix?');
        Continue;
      End;
    End;
    If ((Mode And $F000) = $2000) Or ((Mode And $F000) = $6000) Or
       ((Mode And $F000) = $1000) Or ((Mode And $F000) = $C000) Then Continue;
    DupN := 0;
    EnumBlocks(N, Ino128, False);
    If Frag Then Inc(NFrag);
    If BadBlk Then
      Problem('Inode ' + NumS(N) + ' has illegal block(s).', 'Clear?');
    If DupN > 0 Then
    Begin
      Inc(Errors);
      Say('Running additional passes to resolve blocks claimed by more than ' +
          'one inode...');
      Say('Pass 1B: Rescanning for multiply-claimed blocks');
      For I := 0 To DupN - 1 Do
        Say('Multiply-claimed block(s) in inode ' + NumS(DupIno[I]) + ': ' +
            NumS(DupBlk[I]));
      Say('Pass 1C: Scanning directories for inodes with multiply-claimed ' +
          'blocks');
      Say('Pass 1D: Reconciling multiply-claimed blocks');
      Say('');
    End;
    Exp := (NData + NMeta) * (BS Div 512);
    If (U32(Ino128, 28) <> Exp) And Not BadBlk Then
      ProblemS('Inode ' + NumS(N) + ', i_blocks is ' + NumS(U32(Ino128, 28)) +
              ', should be ' + NumS(Exp) + '.', 'Fix?');
    If (Mode And $F000) = $4000 Then
      If (U32(Ino128, 4) Mod BS <> 0) Or (U32(Ino128, 4) = 0) Then
        Problem('Inode ' + NumS(N) + ' (' + '...' + ') is a directory with ' +
                'a bad size.', 'Fix?');
  End;
End;

{ ---------- passe 2 : repertoires ---------- }

Function TypeOf(Mode : LongInt) : LongInt;
Begin
  Case Mode And $F000 Of
    $8000 : TypeOf := 1;
    $4000 : TypeOf := 2;
    $2000 : TypeOf := 3;
    $6000 : TypeOf := 4;
    $1000 : TypeOf := 5;
    $C000 : TypeOf := 6;
    $A000 : TypeOf := 7;
  Else TypeOf := 0;
  End;
End;

Function OctS(V : LongInt) : String;
Var S : String;
Begin
  S := '';
  Repeat
    S := Chr(48 + (V And 7)) + S;
    V := V Shr 3;
  Until V = 0;
  While Length(S) < 2 Do S := '0' + S;
  OctS := S;
End;

Procedure ScanDir(D : LongInt);
Var
  K, Off, RecLen, NameLen, Ino, Ft, B, Mode : LongInt;
  Name : String;
  I : LongInt;
  HaveFt : Boolean;
  DBuf : Array[0..65535] Of Byte;
  IsDot, IsDd : Boolean;
  Dots : LongInt;
  Pth : String;
Begin
  HaveFt := (FIncompat And 2) <> 0;
  If Not ReadInode(D) Then Exit;
  EnumBlocks(D, Ino128, True);
  Dots := 0;
  For K := 0 To NDirBlk - 1 Do
  Begin
    If Not ReadBlk(DirBlk[K]) Then Continue;
    Move(Buf[0], DBuf[0], BS);
    Off := 0;
    While Off < BS Do
    Begin
      RecLen := U16(DBuf, Off + 4);
      NameLen := DBuf[Off + 6];
      Ino := U32(DBuf, Off);
      If (RecLen < 8) Or (RecLen Mod 4 <> 0) Or (Off + RecLen > BS) Or
         (NameLen + 8 > RecLen) Then
      Begin
        Problem('Directory inode ' + NumS(D) + ', block #' + NumS(K) +
                ', offset ' + NumS(Off) + ': directory corrupted', 'Salvage?');
        Break;
      End;
      If Ino <> 0 Then
      Begin
        Name := '';
        For I := 0 To NameLen - 1 Do
          If Length(Name) < 200 Then Name := Name + Chr(DBuf[Off + 8 + I]);
        If HaveFt Then Ft := DBuf[Off + 7] Else Ft := 0;
        IsDot := (Name = '.');
        IsDd := (Name = '..');
        If (Ino > NInodes) Or (Ino < 1) Then
          Problem('Entry ''' + Name + ''' in ' + PathOf(D) + ' (' + NumS(D) +
                  ') has bad inode #: ' + NumS(Ino) + '.', 'Clear?')
        Else If (Flags[Ino] And 1) = 0 Then
        Begin
          ProblemS('Entry ''' + Name + ''' in ' + PathOf(D) + ' (' + NumS(D) +
                  ') has deleted/unused inode ' + NumS(Ino) + '.', 'Clear?');
          If HaveFt And (Mode16[Ino] = 0) And (Ft <> 0) Then
            Problem('Entry ''' + Name + ''' in ' + PathOf(D) + ' (' + NumS(D) +
                    ') has an incorrect filetype (was ' + NumS(Ft) +
                    ', should be 0).', 'Fix?');
        End
        Else
        Begin
          Inc(Cnt[Ino]);
          If ((Flags[Ino] And 8) <> 0) And ((Flags[Ino] And 16) = 0) Then
          Begin
            Flags[Ino] := Flags[Ino] Or 16;
            I := Mode16[Ino];
            If D = 2 Then Pth := '/' + Name Else Pth := PathOf(D) + '/' + Name;
            Problem('Inode ' + NumS(Ino) + ' (' + Pth + ') has invalid mode (' +
                    OctS(I) + ').', 'Clear?');
          End;
          If HaveFt And (Ft <> TypeOf(Mode16[Ino])) Then
            Problem('Entry ''' + Name + ''' in ' + PathOf(D) + ' (' + NumS(D) +
                    ') has an incorrect filetype (was ' + NumS(Ft) +
                    ', should be ' + NumS(TypeOf(Mode16[Ino])) + ').', 'Fix?');
          If IsDd Then DotDot[D] := Ino
          Else If Not IsDot Then
          Begin
            If (Par[Ino] = 0) Or ((Flags[Ino] And 2) = 0) Then
            Begin
              If Par[Ino] = 0 Then
              Begin
                Par[Ino] := D;
                Nm[Ino] := Copy(Name, 1, 23);
              End;
            End;
          End
          Else If Ino <> D Then
            Problem('Entry ''.'' in ' + PathOf(D) + ' (' + NumS(D) +
                    ') is not the directory itself.', 'Fix?');
        End;
      End;
      Off := Off + RecLen;
    End;
  End;
End;

Procedure Pass2;
Var N : LongInt;
Begin
  Say('Pass 2: Checking directory structure');
  For N := 1 To NInodes Do
    If (Flags[N] And 3) = 3 Then ScanDir(N);
End;

{ ---------- passe 3 : connexite ---------- }

Procedure Pass3;
Var N, X, Steps : LongInt; Reach : Boolean;
Begin
  Say('Pass 3: Checking directory connectivity');
  For N := 1 To NInodes Do
    If ((Flags[N] And 3) = 3) And (N <> 2) Then
    Begin
      X := N;
      Steps := 0;
      Reach := False;
      While (X > 0) And (Steps < 100) Do
      Begin
        If X = 2 Then
        Begin
          Reach := True;
          Break;
        End;
        X := Par[X];
        Inc(Steps);
      End;
      If Not Reach Then
      Begin
        Problem('Unconnected directory inode ' + NumS(N) + ' (was in <' +
                NumS(DotDot[N]) + '>)', 'Connect to /lost+found?');
        Cnt[N] := Cnt[N] + 0;
      End
      Else If (DotDot[N] <> Par[N]) And (DotDot[N] <> 0) Then
        Problem('''..'' in ' + PathOf(N) + ' (' + NumS(N) + ') is ' +
                PathOf(DotDot[N]) + ' (' + NumS(DotDot[N]) + '), should be ' +
                PathOf(Par[N]) + ' (' + NumS(Par[N]) + ').', 'Fix?');
    End;
End;

{ ---------- passe 4 : nombres de liens ---------- }

Procedure Pass4;
Var N : LongInt;
Begin
  Say('Pass 4: Checking reference counts');
  For N := 1 To NInodes Do
    If (Flags[N] And 1) <> 0 Then
    Begin
      If N < FirstIno Then
      Begin
        If (N = 2) And (Cnt[N] <> ILinks[N]) Then
          ProblemS('Inode 2 ref count is ' + NumS(ILinks[N]) + ', should be ' +
                  NumS(Cnt[N]) + '.', 'Fix?');
        Continue;
      End;
      If Cnt[N] = 0 Then
        Problem('Unattached inode ' + NumS(N), 'Connect to /lost+found?')
      Else If Cnt[N] <> ILinks[N] Then
        ProblemS('Inode ' + NumS(N) + ' ref count is ' + NumS(ILinks[N]) +
                ', should be ' + NumS(Cnt[N]) + '.', 'Fix?');
    End;
End;

{ ---------- passe 5 : bitmaps ---------- }

Procedure ReportDiff(Const Title : String; Var D : Array Of LongInt;
                     N : LongInt);
Var I, J : LongInt; S : String;
Begin
  If N = 0 Then Exit;
  S := Title + ' differences: ';
  I := 0;
  While I < N Do
  Begin
    J := I;
    While (J + 1 < N) And ((D[J + 1] > 0) = (D[I] > 0)) And
          (Abs(D[J + 1]) = Abs(D[J]) + 1) Do Inc(J);
    If D[I] > 0 Then S := S + ' +' Else S := S + ' -';
    If J > I Then S := S + '(' + NumS(Abs(D[I])) + '--' + NumS(Abs(D[J])) + ')'
    Else S := S + NumS(Abs(D[I]));
    I := J + 1;
  End;
  Say(S);
End;

Var
  Diffs : Array[0..65535] Of LongInt;

Procedure Pass5;
Var
  G, I, B, First, Cntf, ND, TotFree, TotFI, UsedI, Dirs : LongInt;
  Disk, Calc : Boolean;
  M, ByteI : LongInt;
  GFree : Array[0..MaxGrp - 1] Of LongInt;
  GFI : Array[0..MaxGrp - 1] Of LongInt;
  GDirs : Array[0..MaxGrp - 1] Of LongInt;
  Minus, Plus : LongInt;
  Mark : Array[0..3] Of Byte;
Begin
  Say('Pass 5: Checking group summary information');
  TotFree := 0;
  TotFI := 0;
  { bitmap des blocs }
  ND := 0;
  Plus := 0;
  Minus := 0;
  For G := 0 To NGroups - 1 Do
  Begin
    GFree[G] := 0;
    If Not ReadBlk(GdBB[G]) Then Continue;
    Cntf := BPG;
    If FirstData + (G + 1) * BPG > NBlocks Then
      Cntf := NBlocks - FirstData - G * BPG;
    For I := 0 To Cntf - 1 Do
    Begin
      B := FirstData + G * BPG + I;
      Disk := (Buf[I Shr 3] And (1 Shl (I And 7))) <> 0;
      Calc := GetB(B);
      If Not Disk Then Inc(GFree[G]);
      If Disk <> Calc Then
      Begin
        If ND < 65535 Then
        Begin
          If Calc Then Diffs[ND] := B Else Diffs[ND] := -B;
          Inc(ND);
        End;
      End;
    End;
    TotFree := TotFree + GFree[G];
  End;
  { plus puis moins : e2fsck les range par ordre de bloc, signes melanges }
  ReportDiff('Block bitmap', Diffs, ND);
  If ND > 0 Then Say('Fix? no' + #10);
  If ND > 0 Then Inc(Errors);
  { bitmap des inodes }
  ND := 0;
  For G := 0 To NGroups - 1 Do
  Begin
    GFI[G] := 0;
    GDirs[G] := 0;
    If Not ReadBlk(GdIB[G]) Then Continue;
    For I := 0 To IPG - 1 Do
    Begin
      B := G * IPG + I + 1;
      If B > NInodes Then Break;
      Disk := (Buf[I Shr 3] And (1 Shl (I And 7))) <> 0;
      Calc := (Flags[B] And 1) <> 0;
      If Not Disk Then Inc(GFI[G]);
      If Disk And ((Flags[B] And 3) = 3) Then Inc(GDirs[G]);
      If Disk <> Calc Then
      Begin
        If ND < 65535 Then
        Begin
          If Calc Then Diffs[ND] := B Else Diffs[ND] := -B;
          Inc(ND);
        End;
      End;
    End;
    TotFI := TotFI + GFI[G];
  End;
  ReportDiff('Inode bitmap', Diffs, ND);
  If ND > 0 Then
  Begin
    Say('Fix? no' + #10);
    Inc(Errors);
  End;
  For G := 0 To NGroups - 1 Do
  Begin
    If GFree[G] <> GdFB[G] Then
    Begin
      Problem('Free blocks count wrong for group #' + NumS(G) + ' (' +
              NumS(GdFB[G]) + ', counted=' + NumS(GFree[G]) + ').', 'Fix?');
    End;
  End;
  For G := 0 To NGroups - 1 Do
    If GFI[G] <> GdFI[G] Then
      Problem('Free inodes count wrong for group #' + NumS(G) + ' (' +
              NumS(GdFI[G]) + ', counted=' + NumS(GFI[G]) + ').', 'Fix?');
  For G := 0 To NGroups - 1 Do
    If GDirs[G] <> GdDirs[G] Then
      Problem('Directories count wrong for group #' + NumS(G) + ' (' +
              NumS(GdDirs[G]) + ', counted=' + NumS(GDirs[G]) + ').', 'Fix?');
  If TotFree <> FreeBlocksSB Then
    Problem2('Free blocks count wrong (' + NumS(FreeBlocksSB) + ', counted=' +
             NumS(TotFree) + ').', 'Fix?', False, False);
  If TotFI <> FreeInodesSB Then
    Problem2('Free inodes count wrong (' + NumS(FreeInodesSB) + ', counted=' +
             NumS(TotFI) + ').', 'Fix?', False, False);
  UsedBlocks := NBlocks - FreeBlocksSB;
  NFiles := NInodes - FreeInodesSB;
End;

Function Pct10(A, B : LongInt) : String;
Var V : LongInt;
Begin
  If B = 0 Then V := 0 Else V := (A * 1000 + B Div 2) Div B;
  Pct10 := NumS(V Div 10) + '.' + NumS(V Mod 10);
End;

{ ---------- programme e2fsck ---------- }

Procedure RunE2fsck;
Var
  I : LongInt;
  A : String;
  Counted : LongInt;
Begin
  Dev := '';
  For I := 1 To SysArgCount - 1 Do
  Begin
    A := SysArgStr(I);
    If (A = '--help') Or (A = '/?') Then
    Begin
      SysPut(1, PS(Usage[Lang]) + #10);
      SysExit(0);
    End;
    If (Length(A) > 1) And (A[1] = '-') Then
    Begin
      If Pos('f', A) > 0 Then Force := True;
      If Pos('v', A) > 0 Then Verbose := True;
      If Pos('p', A) > 0 Then Preen := True;
    End
    Else If Dev = '' Then Dev := A;
  End;
  If Dev = '' Then
  Begin
    SysPut(2, PS(Usage[Lang]) + #10);
    SysExit(16);
  End;
  PartOff := 0;
  I := Pos('?offset=', Dev);
  If I > 0 Then
  Begin
    Val(Copy(Dev, I + 8, 20), PartOff, Counted);
    Dev := Copy(Dev, 1, I - 1);
  End;
  Fd := SysOpen(Dev, O_RDONLY, 0);
  If Fd < 0 Then
  Begin
    SysPut(2, 'e2fsck: ' + SysErrorText(SysErrno) + ' while trying to open ' +
           Dev + #10);
    SysExit(8);
  End;
  LoadSuper;
  LoadGroups;
  If Not Preen Then SysPut(2, 'e2fsck 1.47.0 (5-Feb-2023)' + #10);
  If (Not Force) And ((State And 1) <> 0) And ((State And 2) = 0) Then
  Begin
    Say(Dev + ': clean, ' + NumS(NInodes - FreeInodesSB) + '/' +
        NumS(NInodes) + ' files, ' + NumS(NBlocks - FreeBlocksSB) + '/' +
        NumS(NBlocks) + ' blocks');
    SysExit(0);
  End;
  Errors := 0;
  Pass1;
  Pass2;
  Pass3;
  Pass4;
  Pass5;
  If Errors > 0 Then
  Begin
    Say('');
    Say(Dev + ': ********** WARNING: Filesystem still has errors **********');
    Say('');
  End;
  Say(Dev + ': ' + NumS(NFiles) + '/' + NumS(NInodes) + ' files (' +
      Pct10(NFrag, NFiles) + '% non-contiguous), ' + NumS(UsedBlocks) + '/' +
      NumS(NBlocks) + ' blocks');
  If Errors > 0 Then SysExit(4);
  SysExit(0);
End;

{ ---------- fsck : aiguilleur ---------- }

Procedure RunFsck;
Var
  I, Pid, St, Rc, Worst : LongInt;
  A, Typ, Fs : String;
  Opts : Array[1..16] Of String;
  NOpt : LongInt;
  Devs : Array[1..32] Of String;
  NDev : LongInt;
  All, NoRun : Boolean;
  Lines : Array[0..127] Of String;
  F, N, K : LongInt;
  B : Byte;
  Ln : String;
  Fields : Array[1..6] Of String;
Begin
  Typ := '';
  NOpt := 0;
  NDev := 0;
  All := False;
  NoRun := False;
  I := 1;
  While I < SysArgCount Do
  Begin
    A := SysArgStr(I);
    If (A = '--help') Or (A = '/?') Then
    Begin
      SysPut(1, PS(Usage[Lang]) + #10);
      SysExit(0);
    End
    Else If A = '-t' Then
    Begin
      Inc(I);
      If I < SysArgCount Then Typ := SysArgStr(I);
    End
    Else If A = '-A' Then All := True
    Else If A = '-N' Then NoRun := True
    Else If (A = '-P') Or (A = '-R') Or (A = '-T') Or (A = '-s') Then
    Else If (Length(A) > 1) And (A[1] = '-') Then
    Begin
      If NOpt < 16 Then
      Begin
        Inc(NOpt);
        Opts[NOpt] := A;
      End;
    End
    Else If NDev < 32 Then
    Begin
      Inc(NDev);
      Devs[NDev] := A;
    End;
    Inc(I);
  End;
  { /etc/fstab }
  N := 0;
  F := SysOpen('/etc/fstab', O_RDONLY, 0);
  If F >= 0 Then
  Begin
    Ln := '';
    While N < 128 Do
    Begin
      K := SysRead(F, B, 1);
      If (K <= 0) Or (B = 10) Then
      Begin
        If Ln <> '' Then
        Begin
          Lines[N] := Ln;
          Inc(N);
        End;
        Ln := '';
        If K <= 0 Then Break;
      End
      Else If Length(Ln) < 250 Then Ln := Ln + Chr(B);
    End;
    SysClose(F);
  End;
  If (All Or (NDev = 0)) Then
  Begin
    NDev := 0;
    For K := 0 To N - 1 Do
    Begin
      Ln := Lines[K];
      If (Ln = '') Or (Ln[1] = '#') Then Continue;
      For I := 1 To 6 Do Fields[I] := '';
      F := 1;
      For I := 1 To Length(Ln) Do
        If (Ln[I] = ' ') Or (Ln[I] = #9) Then
        Begin
          If (Fields[F] <> '') And (F < 6) Then Inc(F);
        End
        Else Fields[F] := Fields[F] + Ln[I];
      If (Fields[6] <> '') And (Fields[6] <> '0') And
         ((Typ = '') Or (Pos(Fields[3], Typ) > 0)) And (NDev < 32) Then
      Begin
        Inc(NDev);
        Devs[NDev] := Fields[1];
      End;
    End;
  End;
  Worst := 0;
  For I := 1 To NDev Do
  Begin
    Fs := Typ;
    If Fs = '' Then
      For K := 0 To N - 1 Do
      Begin
        Ln := Lines[K];
        If Copy(Ln, 1, Length(Devs[I])) = Devs[I] Then
        Begin
          F := 1;
          For St := 1 To 6 Do Fields[St] := '';
          For St := 1 To Length(Ln) Do
            If (Ln[St] = ' ') Or (Ln[St] = #9) Then
            Begin
              If (Fields[F] <> '') And (F < 6) Then Inc(F);
            End
            Else Fields[F] := Fields[F] + Ln[St];
          Fs := Fields[3];
        End;
      End;
    If (Fs = '') Or (Fs = 'auto') Then Fs := 'ext2';
    If NoRun Then
    Begin
      Say('[/sbin/fsck.' + Fs + ' (1) -- ' + Devs[I] + '] fsck.' + Fs + ' ' +
          Devs[I]);
      Continue;
    End;
    Pid := SysFork;
    If Pid = 0 Then
    Begin
      SysArgReset;
      SysArgAdd('fsck.' + Fs);
      For K := 1 To NOpt Do SysArgAdd(Opts[K]);
      SysArgAdd(Devs[I]);
      SysEnvInherit;
      SysArgExec('/bin/fsck.' + Fs);
      SysArgExec('/sbin/fsck.' + Fs);
      SysPut(2, 'fsck: fsck.' + Fs + ': not found' + #10);
      SysExit(8);
    End;
    SysWaitPid(Pid, St, 0);
    Rc := SysWExitStatus(St);
    If Rc > Worst Then Worst := Rc;
  End;
  SysExit(Worst);
End;

BEGIN
  Lang := SysLang;
  If (Lang < 1) Or (Lang > 5) Then Lang := 1;
  Prog := SysArgStr(0);
  While Pos('/', Prog) > 0 Do Prog := Copy(Prog, Pos('/', Prog) + 1, 255);
  If Prog = 'fsck' Then RunFsck
  Else RunE2fsck;
END.
