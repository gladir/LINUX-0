{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2026
  @website(https://www.gladir.com/linux-0)
  @abstract(Target: LPC -3X)
  @description: /bin/cpio : archives cpio. cpio -o [-H newc|odc] [-v] < liste
      > archive ; cpio -i [-d] [-m] [-u] [-v] [-t] [motif...] < archive ;
      cpio -p [-d] [-m] [-v] repertoire < liste. Formats newc (070701, 070702
      lu) et odc (070707) ; fichiers, repertoires, liens symboliques,
      peripheriques, tubes ; liens physiques regroupes a l'ecriture (newc,
      donnees avec le dernier lien) et reconstitues a la lecture.
}

Program CPIO;

Const
  Usage : Array[1..5] Of PChar = (
    'Usage : cpio -o|-i|-p [-H newc|odc] [-dmuvt] [repertoire]',
    'Usage: cpio -o|-i|-p [-H newc|odc] [-dmuvt] [directory]',
    'Aufruf: cpio -o|-i|-p [-H newc|odc] [-dmuvt] [Verzeichnis]',
    'Uso: cpio -o|-i|-p [-H newc|odc] [-dmuvt] [directorio]',
    'Uso: cpio -o|-i|-p [-H newc|odc] [-dmuvt] [directorio]');

Var
  Lang : LongInt;
  Buf : Array[0..65535] Of Byte;
  Opt : Array[0..127] Of Boolean;
  Fmt : String;
  Pats : Array[1..32] Of String;
  NPat : LongInt;
  Dest : String;
  Odc : Boolean;
  OutBuf : Array[0..65535] Of Byte;
  OutN, Pos_ : LongInt;
  InBuf : Array[0..65535] Of Byte;
  InN, InP : LongInt;
  Rc : LongInt;

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

Procedure Flush;
Var D, R : LongInt;
Begin
  D := 0;
  While D < OutN Do
  Begin
    R := SysWrite(1, OutBuf[D], OutN - D);
    If R <= 0 Then SysExit(2);
    D := D + R;
  End;
  OutN := 0;
End;

Procedure PutB(B : Byte);
Begin
  If OutN >= 65536 Then Flush;
  OutBuf[OutN] := B;
  Inc(OutN);
  Inc(Pos_);
End;

Procedure PutS(Const S : String);
Var K : LongInt;
Begin
  For K := 1 To Length(S) Do PutB(Ord(S[K]));
End;

Function HexS(V, W : LongInt) : String;
Const D = '0123456789ABCDEF';
Var S : String; K : LongInt;
Begin
  S := '';
  For K := W - 1 DownTo 0 Do S := S + D[((V Shr (4 * K)) And 15) + 1];
  HexS := S;
End;

Function OctS(V, W : LongInt) : String;
Var S : String;
Begin
  S := '';
  While W > 0 Do
  Begin
    S := Chr(48 + (V And 7)) + S;
    V := V Shr 3;
    Dec(W);
  End;
  OctS := S;
End;

Procedure Align4;
Begin
  While (Pos_ And 3) <> 0 Do PutB(0);
End;

{ ------------------------------ ecriture ------------------------------ }

Var
  Seen : Array[1..512] Of LongInt;      { inode + dev pour les liens }
  SeenName : Array[1..512] Of String;
  NSeen : LongInt;

Procedure WriteEntry(Const Name : String);
Var
  St : TSysStat;
  Fd, N, Size, K, Mode, Ino : LongInt;
  Link : String;
  IsLink, IsReg : Boolean;
Begin
  If SysLStat(Name, St) <> 0 Then
  Begin
    SysPut(2, 'cpio: ' + Name + ': ' + SysErrorText(SysErrno) + #10);
    Rc := 1;
    Exit;
  End;
  Mode := St.Mode;
  If (Mode And $F000) = $8000 Then St.NLink := 1;
  IsLink := (Mode And $F000) = $A000;
  IsReg := (Mode And $F000) = $8000;
  Size := 0;
  Link := '';
  If IsLink Then
  Begin
    Link := SysReadlink(Name);
    Size := Length(Link);
  End
  Else If IsReg Then Size := St.Size;
  If Odc Then
  Begin
    PutS('070707' + OctS(St.Dev, 6) + OctS(St.Ino, 6) + OctS(Mode, 6) +
         OctS(St.Uid, 6) + OctS(St.Gid, 6) + OctS(St.NLink, 6) +
         OctS(St.RDev, 6) + OctS(St.MTime, 11) + OctS(Length(Name) + 1, 6) +
         OctS(Size, 11));
    PutS(Name);
    PutB(0);
  End
  Else
  Begin
    PutS('070701' + HexS(St.Ino, 8) + HexS(Mode, 8) + HexS(St.Uid, 8) +
         HexS(St.Gid, 8) + HexS(St.NLink, 8) + HexS(St.MTime, 8) +
         HexS(Size, 8) + HexS(0, 8) + HexS(St.Dev, 8) + HexS(St.RDev Shr 8, 8) +
         HexS(St.RDev And 255, 8) + HexS(Length(Name) + 1, 8) + HexS(0, 8));
    PutS(Name);
    PutB(0);
    Align4;
  End;
  If IsLink Then
  Begin
    PutS(Link);
    If Not Odc Then Align4;
  End
  Else If IsReg And (Size > 0) Then
  Begin
    Fd := SysOpen(Name, O_RDONLY, 0);
    If Fd < 0 Then
    Begin
      SysPut(2, 'cpio: ' + Name + ': ' + SysErrorText(SysErrno) + #10);
      Rc := 1;
      For K := 1 To Size Do PutB(0);
    End
    Else
    Begin
      K := 0;
      While K < Size Do
      Begin
        N := SysRead(Fd, Buf[0], 65536);
        If N <= 0 Then Break;
        If K + N > Size Then N := Size - K;
        For Ino := 0 To N - 1 Do PutB(Buf[Ino]);
        K := K + N;
      End;
      While K < Size Do
      Begin
        PutB(0);
        Inc(K);
      End;
      SysClose(Fd);
    End;
    If Not Odc Then Align4;
  End;
  If Opt[Ord('v')] Then SysPut(2, Name + #10);
End;

Function ReadName(Var S : String) : Boolean;
Var B : Byte; N : LongInt;
Begin
  S := '';
  ReadName := False;
  While True Do
  Begin
    N := SysRead(0, B, 1);
    If N <= 0 Then Break;
    ReadName := True;
    If B = 10 Then Break;
    If Length(S) < 250 Then S := S + Chr(B);
  End;
End;

Procedure RunOut;
Var L : String;
Begin
  Odc := Fmt = 'odc';
  While ReadName(L) Do
    If L <> '' Then WriteEntry(L);
  { en-queue }
  If Odc Then
    PutS('070707' + OctS(0, 6) + OctS(0, 6) + OctS(0, 6) + OctS(0, 6) +
         OctS(0, 6) + OctS(1, 6) + OctS(0, 6) + OctS(0, 11) + OctS(11, 6) +
         OctS(0, 11) + 'TRAILER!!!')
  Else
  Begin
    PutS('070701' + HexS(0, 8) + HexS(0, 8) + HexS(0, 8) + HexS(0, 8) +
         HexS(1, 8) + HexS(0, 8) + HexS(0, 8) + HexS(0, 8) + HexS(0, 8) +
         HexS(0, 8) + HexS(0, 8) + HexS(11, 8) + HexS(0, 8) + 'TRAILER!!!');
  End;
  PutB(0);
  If Not Odc Then Align4;
  Flush;
End;

{ ------------------------------ lecture ------------------------------ }

Function GetB : LongInt;
Begin
  If InP >= InN Then
  Begin
    InN := SysRead(0, InBuf[0], 65536);
    InP := 0;
    If InN <= 0 Then
    Begin
      InN := 0;
      GetB := -1;
      Exit;
    End;
  End;
  GetB := InBuf[InP];
  Inc(InP);
  Inc(Pos_);
End;

Function GetField(N, Base : LongInt) : LongInt;
Var K, V, C : LongInt;
Begin
  V := 0;
  For K := 1 To N Do
  Begin
    C := GetB;
    If C < 0 Then
    Begin
      GetField := -1;
      Exit;
    End;
    If (C >= 48) And (C <= 57) Then V := V * Base + C - 48
    Else If (C >= 65) And (C <= 70) Then V := V * Base + C - 55
    Else If (C >= 97) And (C <= 102) Then V := V * Base + C - 87;
  End;
  GetField := V;
End;

Procedure SkipTo4;
Begin
  While (Pos_ And 3) <> 0 Do GetB;
End;

Function Wanted(Const Nm : String) : Boolean;
Var K, P : LongInt; T : String;
Begin
  If NPat = 0 Then
  Begin
    Wanted := True;
    Exit;
  End;
  Wanted := False;
  For K := 1 To NPat Do
  Begin
    T := Pats[K];
    If (T = Nm) Then Wanted := True
    Else If (Length(T) > 0) And (T[Length(T)] = '*') And
            (Copy(Nm, 1, Length(T) - 1) = Copy(T, 1, Length(T) - 1)) Then
      Wanted := True
    Else If T = '*' Then Wanted := True;
  End;
End;

Procedure MkDirs(Const Path : String);
Var K : LongInt;
Begin
  For K := 2 To Length(Path) Do
    If Path[K] = '/' Then SysMkdir(Copy(Path, 1, K - 1), 493);
End;

Const MaxHL = 64;
Var
  HlIno : Array[1..MaxHL] Of LongInt;
  HlNames : Array[1..MaxHL] Of String;
  NHl : LongInt;

Procedure RunIn(ListOnly : Boolean);
Var
  Magic, Ino, Mode, Uid, Gid, NLink, MTime, Size, NameLen, DevMaj, DevMin,
  RMaj, RMin, K, C, N, Fd, Dv, Rd : LongInt;
  Name, Data : String;
  Fmt7 : Boolean;
  Sig : String;
  Out : String;
  Skip : Boolean;
  Hold : Boolean;
Begin
  Pos_ := 0;
  While True Do
  Begin
    Sig := '';
    For K := 1 To 6 Do
    Begin
      C := GetB;
      If C < 0 Then Exit;
      Sig := Sig + Chr(C);
    End;
    If (Sig <> '070701') And (Sig <> '070702') And (Sig <> '070707') Then
    Begin
      SysPut(2, 'cpio: invalid magic number' + #10);
      SysExit(2);
    End;
    Fmt7 := Sig = '070707';
    If Fmt7 Then
    Begin
      Dv := GetField(6, 8);
      Ino := GetField(6, 8);
      Mode := GetField(6, 8);
      Uid := GetField(6, 8);
      Gid := GetField(6, 8);
      NLink := GetField(6, 8);
      Rd := GetField(6, 8);
      MTime := GetField(11, 8);
      NameLen := GetField(6, 8);
      Size := GetField(11, 8);
      RMaj := Rd;
      RMin := 0;
    End
    Else
    Begin
      Ino := GetField(8, 16);
      Mode := GetField(8, 16);
      Uid := GetField(8, 16);
      Gid := GetField(8, 16);
      NLink := GetField(8, 16);
      MTime := GetField(8, 16);
      Size := GetField(8, 16);
      DevMaj := GetField(8, 16);
      DevMin := GetField(8, 16);
      RMaj := GetField(8, 16);
      RMin := GetField(8, 16);
      NameLen := GetField(8, 16);
      GetField(8, 16);
    End;
    Name := '';
    For K := 1 To NameLen - 1 Do
    Begin
      C := GetB;
      If Length(Name) < 250 Then Name := Name + Chr(C);
    End;
    GetB;
    If Not Fmt7 Then SkipTo4;
    If Name = 'TRAILER!!!' Then Exit;
    Skip := (Not Wanted(Name)) Or ListOnly;
    Out := Dest + Name;
    Data := '';
    If (Mode And $F000) = $A000 Then
    Begin
      For K := 1 To Size Do
      Begin
        C := GetB;
        If Length(Data) < 250 Then Data := Data + Chr(C);
      End;
      If Not Fmt7 Then SkipTo4;
      If Not Skip Then
      Begin
        If Opt[Ord('d')] Then MkDirs(Out);
        SysUnlink(Out);
        If SysSymlink(Data, Out) < 0 Then
          SysPut(2, 'cpio: ' + Out + ': ' + SysErrorText(SysErrno) + #10);
      End;
    End
    Else If (Mode And $F000) = $8000 Then
    Begin
      Fd := -1;
      Hold := (NLink > 1) And (Size = 0) And (Not Fmt7);
      If (Not Skip) And (Not Hold) Then
      Begin
        If Opt[Ord('d')] Then MkDirs(Out);
        If Opt[Ord('u')] Then SysUnlink(Out);
        Fd := SysOpen(Out, O_WRONLY Or O_CREAT Or O_TRUNC, Mode And 4095);
        If Fd < 0 Then
          SysPut(2, 'cpio: ' + Out + ': ' + SysErrorText(SysErrno) + #10);
      End;
      N := 0;
      K := 0;
      While K < Size Do
      Begin
        C := GetB;
        If C < 0 Then Break;
        If Fd >= 0 Then
        Begin
          Buf[N] := C;
          Inc(N);
          If N = 65536 Then
          Begin
            SysWrite(Fd, Buf[0], N);
            N := 0;
          End;
        End;
        Inc(K);
      End;
      If (Fd >= 0) And (N > 0) Then SysWrite(Fd, Buf[0], N);
      If Fd >= 0 Then SysClose(Fd);
      If Not Fmt7 Then SkipTo4;
      { liens physiques : les donnees arrivent avec le dernier lien }
      If (NLink > 1) And (Not Fmt7) And (Not Skip) Then
      Begin
        If Hold Then
        Begin
          If NHl < MaxHL Then
          Begin
            Inc(NHl);
            HlIno[NHl] := Ino;
            HlNames[NHl] := Out;
          End;
        End
        Else
          For K := 1 To NHl Do
            If HlIno[K] = Ino Then
            Begin
              If Opt[Ord('d')] Then MkDirs(HlNames[K]);
              SysUnlink(HlNames[K]);
              SysLink(Out, HlNames[K]);
              HlIno[K] := -1;
            End;
      End;
    End
    Else
    Begin
      For K := 1 To Size Do GetB;
      If Not Fmt7 Then SkipTo4;
      If Not Skip Then
      Begin
        If Opt[Ord('d')] Then MkDirs(Out);
        If (Mode And $F000) = $4000 Then SysMkdir(Out, Mode And 4095)
        Else SysMknod(Out, Mode, (RMaj Shl 8) Or RMin);
      End;
    End;
    If Not Skip Then
    Begin
      If SysGetUid = 0 Then SysChown(Out, Uid, Gid);
      If (Mode And $F000) <> $A000 Then SysChmod(Out, Mode And 4095);
    End;
    If Opt[Ord('v')] Or ListOnly Then
      If Wanted(Name) Then SysPut(1, Name + #10);
  End;
End;

Procedure CopyOne(Const Src, Dst : String);
Var
  St : TSysStat;
  F1, F2, N : LongInt;
  Lk : String;
Begin
  If SysLStat(Src, St) <> 0 Then
  Begin
    SysPut(2, 'cpio: ' + Src + ': ' + SysErrorText(SysErrno) + #10);
    Rc := 1;
    Exit;
  End;
  If Opt[Ord('d')] Then MkDirs(Dst);
  If (St.Mode And $F000) = $4000 Then SysMkdir(Dst, St.Mode And 4095)
  Else If (St.Mode And $F000) = $A000 Then
  Begin
    Lk := SysReadlink(Src);
    SysUnlink(Dst);
    SysSymlink(Lk, Dst);
  End
  Else If (St.Mode And $F000) = $8000 Then
  Begin
    F1 := SysOpen(Src, O_RDONLY, 0);
    F2 := SysOpen(Dst, O_WRONLY Or O_CREAT Or O_TRUNC, St.Mode And 4095);
    If (F1 < 0) Or (F2 < 0) Then
    Begin
      SysPut(2, 'cpio: ' + Dst + ': ' + SysErrorText(SysErrno) + #10);
      Rc := 1;
      Exit;
    End;
    Repeat
      N := SysRead(F1, Buf[0], 65536);
      If N > 0 Then SysWrite(F2, Buf[0], N);
    Until N <= 0;
    SysClose(F1);
    SysClose(F2);
  End
  Else SysMknod(Dst, St.Mode, St.RDev);
  If SysGetUid = 0 Then SysChown(Dst, St.Uid, St.Gid);
  If (St.Mode And $F000) <> $A000 Then SysChmod(Dst, St.Mode And 4095);
  If Opt[Ord('v')] Then SysPut(2, Src + #10);
End;

Procedure RunPass;
Var L : String;
Begin
  While ReadName(L) Do
    If L <> '' Then CopyOne(L, Dest + L);
End;

Var
  I, K : LongInt;
  A : String;
BEGIN
  Lang := SysLang;
  If (Lang < 1) Or (Lang > 5) Then Lang := 1;
  Fmt := 'newc';
  NPat := 0;
  Dest := '';
  I := 1;
  While I < SysArgCount Do
  Begin
    A := SysArgStr(I);
    If (A = '--help') Or (A = '/?') Then
    Begin
      SysPut(1, PS(Usage[Lang]) + #10);
      SysExit(0);
    End
    Else If A = '-H' Then
    Begin
      Inc(I);
      If I < SysArgCount Then Fmt := SysArgStr(I);
    End
    Else If Copy(A, 1, 2) = '-H' Then Fmt := Copy(A, 3, 10)
    Else If (Length(A) > 1) And (A[1] = '-') Then
    Begin
      For K := 2 To Length(A) Do Opt[Ord(A[K])] := True;
    End
    Else If Opt[Ord('p')] And (Dest = '') Then Dest := A
    Else If NPat < 32 Then
    Begin
      Inc(NPat);
      Pats[NPat] := A;
    End;
    Inc(I);
  End;
  If (Dest <> '') And (Dest[Length(Dest)] <> '/') Then Dest := Dest + '/';
  If Opt[Ord('o')] Then RunOut
  Else If Opt[Ord('i')] Or Opt[Ord('t')] Then RunIn(Opt[Ord('t')])
  Else If Opt[Ord('p')] Then RunPass
  Else
  Begin
    SysPut(2, PS(Usage[Lang]) + #10);
    SysExit(2);
  End;
  SysExit(Rc);
END.
