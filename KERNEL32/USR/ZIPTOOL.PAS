{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2026
  @website(https://www.gladir.com/linux-0)
  @abstract(Target: LPC -3X)
  @description: zip, unzip, zipinfo (un seul programme, nom lu dans argv[0]).
      Archives ZIP (methodes 0 = stockee et 8 = deflate : decompression
      complete, compression LZ77 + Huffman fixe), CRC-32 verifie, dates et
      modes conserves. zip [-r] [-j] [-q] [-0] [-d] archive.zip fichier...
      unzip [-l] [-t] [-p] [-o] [-n] [-q] [-d dir] archive.zip [membre...]
      zipinfo archive.zip. Limites : 8 Mo par fichier, 4 Go (pas de ZIP64).
}

Program ZIPTOOL;

Const
  MaxData = 8388608;
  MaxEnt = 2000;
  Usage : Array[1..5] Of PChar = (
    'Usage : zip [-rjq0] a.zip fichier... | unzip [-ltpon] a.zip',
    'Usage: zip [-rjq0] a.zip file... | unzip [-ltpon] a.zip',
    'Aufruf: zip [-rjq0] a.zip Datei... | unzip [-ltpon] a.zip',
    'Uso: zip [-rjq0] a.zip fichero... | unzip [-ltpon] a.zip',
    'Uso: zip [-rjq0] a.zip file... | unzip [-ltpon] a.zip');
  LBase : Array[0..28] Of Word = (3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17, 19,
    23, 27, 31, 35, 43, 51, 59, 67, 83, 99, 115, 131, 163, 195, 227, 258);
  LExt : Array[0..28] Of Byte = (0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2,
    2, 3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5, 0);
  DBase : Array[0..29] Of Word = (1, 2, 3, 4, 5, 7, 9, 13, 17, 25, 33, 49, 65,
    97, 129, 193, 257, 385, 513, 769, 1025, 1537, 2049, 3073, 4097, 6145,
    8193, 12289, 16385, 24577);
  DExt : Array[0..29] Of Byte = (0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6,
    6, 7, 7, 8, 8, 9, 9, 10, 10, 11, 11, 12, 12, 13, 13);
  Order : Array[0..18] Of Byte = (16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12,
    3, 13, 2, 14, 1, 15);

Type
  THuff = Record
    Count : Array[0..15] Of LongInt;
    Sym : Array[0..287] Of LongInt;
  End;
  TEnt = Record
    Name : String;
    Method, Crc, CSize, USize, Off, Time, Dat, Attr : LongInt;
  End;

Var
  Lang : LongInt;
  Prog : String;
  Crc32T : Array[0..255] Of LongInt;
  Inp : Array[0..MaxData] Of Byte;     { donnees d'entree (compression) }
  Out : Array[0..MaxData + 65536] Of Byte;   { sortie }
  OutN : LongInt;
  Src : Array[0..MaxData + 65536] Of Byte;  { archive en memoire }
  SrcN : LongInt;
  Ents : Array[1..MaxEnt] Of TEnt;
  NEnt : LongInt;
  { lecteur / ecrivain de bits }
  BPos, BitBuf, BitCnt : LongInt;
  OBitBuf, OBitCnt : LongInt;
  Quiet, Recurse, JunkPaths, StoreOnly, ListOnly, TestOnly, ToStdout,
  Overwrite, NeverOver : Boolean;
  DestDir : String;
  Hd, Hl : Array[0..0] Of LongInt;
  FixLit, FixDist : THuff;
  ArcFd : LongInt;
  Head : Array[0..32767] Of LongInt;
  Prev : Array[0..32767] Of LongInt;

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

Procedure Die(Const S : String);
Begin
  SysPut(2, Prog + ': ' + S + #10);
  SysExit(1);
End;

Procedure InitCrc;
Var I, J, C : LongInt;
Begin
  For I := 0 To 255 Do
  Begin
    C := I;
    For J := 1 To 8 Do
      If (C And 1) <> 0 Then C := (C Shr 1) Xor LongInt($EDB88320)
      Else C := C Shr 1;
    Crc32T[I] := C;
  End;
End;

Function Crc(Var B : Array Of Byte; N : LongInt) : LongInt;
Var C, I : LongInt;
Begin
  C := LongInt($FFFFFFFF);
  For I := 0 To N - 1 Do
    C := Crc32T[(C Xor B[I]) And 255] Xor ((C Shr 8) And $FFFFFF);
  Crc := C Xor LongInt($FFFFFFFF);
End;

{ ------------------------- decompression ------------------------- }

Function GetBits(N : LongInt) : LongInt;
Var V : LongInt;
Begin
  While BitCnt < N Do
  Begin
    If BPos >= SrcN Then Die('unexpected end of data');
    BitBuf := BitBuf Or (LongInt(Src[BPos]) Shl BitCnt);
    Inc(BPos);
    BitCnt := BitCnt + 8;
  End;
  V := BitBuf And ((LongInt(1) Shl N) - 1);
  BitBuf := BitBuf Shr N;
  BitCnt := BitCnt - N;
  GetBits := V;
End;

Procedure Build(Var H : THuff; Var Len : Array Of LongInt; N : LongInt);
Var I, S : LongInt; Offs : Array[0..15] Of LongInt;
Begin
  For I := 0 To 15 Do H.Count[I] := 0;
  For I := 0 To N - 1 Do Inc(H.Count[Len[I]]);
  H.Count[0] := 0;
  Offs[1] := 0;
  For I := 1 To 14 Do Offs[I + 1] := Offs[I] + H.Count[I];
  For I := 0 To N - 1 Do
    If Len[I] <> 0 Then
    Begin
      H.Sym[Offs[Len[I]]] := I;
      Inc(Offs[Len[I]]);
    End;
End;

Function Decode(Var H : THuff) : LongInt;
Var Code, First, Index, Len, Cnt : LongInt;
Begin
  Code := 0;
  First := 0;
  Index := 0;
  For Len := 1 To 15 Do
  Begin
    Code := Code Or GetBits(1);
    Cnt := H.Count[Len];
    If Code - Cnt < First Then
    Begin
      Decode := H.Sym[Index + (Code - First)];
      Exit;
    End;
    Index := Index + Cnt;
    First := (First + Cnt) Shl 1;
    Code := Code Shl 1;
  End;
  Die('bad data');
End;

Procedure PutOut(B : Byte);
Begin
  If OutN > MaxData Then Die('file too large');
  Out[OutN] := B;
  Inc(OutN);
End;

Procedure Codes(Var L, D : THuff);
Var Sym, Len, Dist, K : LongInt;
Begin
  While True Do
  Begin
    Sym := Decode(L);
    If Sym < 256 Then PutOut(Sym)
    Else If Sym = 256 Then Exit
    Else
    Begin
      Sym := Sym - 257;
      If Sym > 28 Then Die('bad data');
      Len := LBase[Sym] + GetBits(LExt[Sym]);
      Sym := Decode(D);
      If Sym > 29 Then Die('bad data');
      Dist := DBase[Sym] + GetBits(DExt[Sym]);
      If Dist > OutN Then Die('bad data');
      For K := 1 To Len Do PutOut(Out[OutN - Dist]);
    End;
  End;
End;

Procedure InitFixed;
Var Len : Array[0..319] Of LongInt; I : LongInt;
Begin
  For I := 0 To 143 Do Len[I] := 8;
  For I := 144 To 255 Do Len[I] := 9;
  For I := 256 To 279 Do Len[I] := 7;
  For I := 280 To 287 Do Len[I] := 8;
  Build(FixLit, Len, 288);
  For I := 0 To 29 Do Len[I] := 5;
  Build(FixDist, Len, 30);
End;

{ decompresse Src[Start..] -> Out[0..OutN-1] }
Procedure Inflate(Start : LongInt);
Var
  Last, Typ, Len, NLen, NDist, NCode, I, Sym, Rep, Prev_ : LongInt;
  Lens : Array[0..319] Of LongInt;
  L, D, LC : THuff;
Begin
  BPos := Start;
  BitBuf := 0;
  BitCnt := 0;
  OutN := 0;
  Repeat
    Last := GetBits(1);
    Typ := GetBits(2);
    If Typ = 0 Then
    Begin
      BitBuf := 0;
      BitCnt := 0;
      If BPos + 4 > SrcN Then Die('bad data');
      Len := Src[BPos] Or (Src[BPos + 1] Shl 8);
      BPos := BPos + 4;
      For I := 1 To Len Do
      Begin
        If BPos >= SrcN Then Die('bad data');
        PutOut(Src[BPos]);
        Inc(BPos);
      End;
    End
    Else If Typ = 1 Then Codes(FixLit, FixDist)
    Else If Typ = 2 Then
    Begin
      NLen := GetBits(5) + 257;
      NDist := GetBits(5) + 1;
      NCode := GetBits(4) + 4;
      For I := 0 To 18 Do Lens[I] := 0;
      For I := 0 To NCode - 1 Do Lens[Order[I]] := GetBits(3);
      Build(LC, Lens, 19);
      I := 0;
      While I < NLen + NDist Do
      Begin
        Sym := Decode(LC);
        If Sym < 16 Then
        Begin
          Lens[I] := Sym;
          Inc(I);
        End
        Else
        Begin
          Prev_ := 0;
          If Sym = 16 Then
          Begin
            If I = 0 Then Die('bad data');
            Prev_ := Lens[I - 1];
            Rep := 3 + GetBits(2);
          End
          Else If Sym = 17 Then Rep := 3 + GetBits(3)
          Else Rep := 11 + GetBits(7);
          While Rep > 0 Do
          Begin
            Lens[I] := Prev_;
            Inc(I);
            Dec(Rep);
          End;
        End;
      End;
      Build(L, Lens, NLen);
      { la table des distances suit dans le meme tableau }
      For I := 0 To NDist - 1 Do Lens[300 - 300 + I] := Lens[NLen + I];
      Build(D, Lens, NDist);
      Codes(L, D);
    End
    Else Die('bad data');
  Until Last = 1;
End;

{ ------------------------- compression ------------------------- }

Procedure PutBits(V, N : LongInt);
Begin
  OBitBuf := OBitBuf Or (V Shl OBitCnt);
  OBitCnt := OBitCnt + N;
  While OBitCnt >= 8 Do
  Begin
    Out[OutN] := OBitBuf And 255;
    Inc(OutN);
    OBitBuf := OBitBuf Shr 8;
    OBitCnt := OBitCnt - 8;
  End;
End;

Function Rev(V, N : LongInt) : LongInt;
Var R, I : LongInt;
Begin
  R := 0;
  For I := 1 To N Do
  Begin
    R := (R Shl 1) Or (V And 1);
    V := V Shr 1;
  End;
  Rev := R;
End;

Procedure PutLit(Sym : LongInt);
Begin
  If Sym < 144 Then PutBits(Rev(48 + Sym, 8), 8)
  Else If Sym < 256 Then PutBits(Rev(400 + Sym - 144, 9), 9)
  Else If Sym < 280 Then PutBits(Rev(Sym - 256, 7), 7)
  Else PutBits(Rev(192 + Sym - 280, 8), 8);
End;

{ compresse Inp[0..N-1] -> Out (deflate, blocs fixes) }
Procedure Deflate(N : LongInt);
Var
  I, J, H, M, Best, BestD, Cand, Depth, K, Lc, Dc : LongInt;
Begin
  OutN := 0;
  OBitBuf := 0;
  OBitCnt := 0;
  For I := 0 To 32767 Do Head[I] := -1;
  PutBits(1, 1);
  PutBits(1, 2);
  I := 0;
  While I < N Do
  Begin
    Best := 0;
    BestD := 0;
    If I + 2 < N Then
    Begin
      H := ((Inp[I] Shl 10) Xor (Inp[I + 1] Shl 5) Xor Inp[I + 2]) And 32767;
      Cand := Head[H];
      Depth := 0;
      While (Cand >= 0) And (I - Cand <= 32768) And (Depth < 24) Do
      Begin
        M := 0;
        While (M < 258) And (I + M < N) And (Inp[Cand + M] = Inp[I + M]) Do
          Inc(M);
        If M > Best Then
        Begin
          Best := M;
          BestD := I - Cand;
          If M = 258 Then Break;
        End;
        Cand := Prev[Cand And 32767];
        If (Cand >= 0) And (I - Cand > 32768) Then Break;
        Inc(Depth);
      End;
    End;
    If Best >= 3 Then
    Begin
      Lc := 28;
      While LBase[Lc] > Best Do Dec(Lc);
      PutLit(257 + Lc);
      If LExt[Lc] > 0 Then PutBits(Best - LBase[Lc], LExt[Lc]);
      Dc := 29;
      While DBase[Dc] > BestD Do Dec(Dc);
      PutBits(Rev(Dc, 5), 5);
      If DExt[Dc] > 0 Then PutBits(BestD - DBase[Dc], DExt[Dc]);
      K := Best;
    End
    Else
    Begin
      PutLit(Inp[I]);
      K := 1;
    End;
    For J := 0 To K - 1 Do
    Begin
      If I + J + 2 < N Then
      Begin
        H := ((Inp[I + J] Shl 10) Xor (Inp[I + J + 1] Shl 5) Xor
              Inp[I + J + 2]) And 32767;
        Prev[(I + J) And 32767] := Head[H];
        Head[H] := I + J;
      End;
    End;
    I := I + K;
  End;
  PutLit(256);
  If OBitCnt > 0 Then PutBits(0, 8 - OBitCnt);
End;

{ ------------------------- fichiers ------------------------- }

Function DosTime(T : LongInt) : LongInt;
Var Days, Y, M, D, H, Mi, S, Z, Era, Doe, Yoe, Doy, Mp : LongInt;
Begin
  T := T + LnxTz;
  Days := T Div 86400;
  H := (T Mod 86400) Div 3600;
  Mi := (T Mod 3600) Div 60;
  S := T Mod 60;
  Z := Days + 719468;
  Era := Z Div 146097;
  Doe := Z - Era * 146097;
  Yoe := (Doe - Doe Div 1460 + Doe Div 36524 - Doe Div 146096) Div 365;
  Y := Yoe + Era * 400;
  Doy := Doe - (365 * Yoe + Yoe Div 4 - Yoe Div 100);
  Mp := (5 * Doy + 2) Div 153;
  D := Doy - (153 * Mp + 2) Div 5 + 1;
  If Mp < 10 Then M := Mp + 3 Else M := Mp - 9;
  If M <= 2 Then Y := Y + 1;
  If Y < 1980 Then
  Begin
    Y := 1980; M := 1; D := 1; H := 0; Mi := 0; S := 0;
  End;
  DosTime := ((Y - 1980) Shl 25) Or (M Shl 21) Or (D Shl 16) Or (H Shl 11) Or
             (Mi Shl 5) Or (S Div 2);
End;

Function UnixTime(Dt : LongInt) : LongInt;
Var Y, M, D, H, Mi, S, Yy, Era, Yoe, Doy, Doe, Days : LongInt;
Begin
  Y := ((Dt Shr 25) And 127) + 1980;
  M := (Dt Shr 21) And 15;
  D := (Dt Shr 16) And 31;
  H := (Dt Shr 11) And 31;
  Mi := (Dt Shr 5) And 63;
  S := (Dt And 31) * 2;
  Yy := Y;
  If M <= 2 Then Yy := Yy - 1;
  Era := Yy Div 400;
  Yoe := Yy - Era * 400;
  If M > 2 Then Doy := (153 * (M - 3) + 2) Div 5 + D - 1
  Else Doy := (153 * (M + 9) + 2) Div 5 + D - 1;
  Doe := Yoe * 365 + Yoe Div 4 - Yoe Div 100 + Doy;
  Days := Era * 146097 + Doe - 719468;
  UnixTime := Days * 86400 + H * 3600 + Mi * 60 + S - LnxTz;
End;

Procedure W16(V : LongInt);
Begin
  PutOut(V And 255);
  PutOut((V Shr 8) And 255);
End;

Procedure W32(V : LongInt);
Begin
  W16(V And $FFFF);
  W16((V Shr 16) And $FFFF);
End;

Function R16(P : LongInt) : LongInt;
Begin
  R16 := Src[P] Or (Src[P + 1] Shl 8);
End;

Function R32(P : LongInt) : LongInt;
Begin
  R32 := R16(P) Or (R16(P + 2) Shl 16);
End;

Procedure PutStr(Const S : String);
Var K : LongInt;
Begin
  For K := 1 To Length(S) Do PutOut(Ord(S[K]));
End;

Procedure WriteAll(Fd : LongInt; Var B : Array Of Byte; N : LongInt);
Var Done, R : LongInt;
Begin
  Done := 0;
  While Done < N Do
  Begin
    R := SysWrite(Fd, B[Done], N - Done);
    If R <= 0 Then Die('write error');
    Done := Done + R;
  End;
End;

Function ReadFd(Fd : LongInt; Var B : Array Of Byte; Max : LongInt) : LongInt;
Var N, R : LongInt;
Begin
  N := 0;
  Repeat
    R := SysRead(Fd, B[N], 65536);
    If R > 0 Then N := N + R;
  Until (R <= 0) Or (N + 65536 > Max);
  ReadFd := N;
End;

{ ------------------------- zip ------------------------- }

Var
  Cen : Array[0..262143] Of Byte;   { repertoire central }
  CenN : LongInt;
  ZNum : LongInt;
  ZOff : LongInt;
  ZFd : LongInt;

Procedure CenPut(V : LongInt; N : LongInt);
Var K : LongInt;
Begin
  For K := 0 To N - 1 Do
  Begin
    Cen[CenN] := (V Shr (8 * K)) And 255;
    Inc(CenN);
  End;
End;

Procedure AddFile(Const Path, Name : String; Mode, Mtime : LongInt;
                  IsDir : Boolean);
Var
  Fd, N, C, Meth, CSz, Dt : LongInt;
  St : TSysStat;
  Nm : String;
  K : LongInt;
Begin
  Nm := Name;
  If IsDir And (Nm[Length(Nm)] <> '/') Then Nm := Nm + '/';
  N := 0;
  If Not IsDir Then
  Begin
    Fd := SysOpen(Path, O_RDONLY, 0);
    If Fd < 0 Then
    Begin
      SysPut(2, 'zip: ' + Path + ': ' + SysErrorText(SysErrno) + #10);
      Exit;
    End;
    N := ReadFd(Fd, Inp, MaxData);
    SysClose(Fd);
  End;
  C := 0;
  If N > 0 Then C := Crc(Inp, N);
  Meth := 0;
  CSz := N;
  If (N > 0) And (Not StoreOnly) Then
  Begin
    Deflate(N);
    If OutN < N Then
    Begin
      Meth := 8;
      CSz := OutN;
    End;
  End;
  Dt := DosTime(Mtime);
  OutN := 0;
  { en-tete local }
  W32($04034B50);
  W16(20);
  W16(0);
  W16(Meth);
  W16(Dt And $FFFF);
  W16((Dt Shr 16) And $FFFF);
  W32(C);
  W32(CSz);
  W32(N);
  W16(Length(Nm));
  W16(0);
  PutStr(Nm);
  WriteAll(ZFd, Out, OutN);
  ZOff := ZOff;
  { reprise : les donnees compressees ont ete ecrasees dans Out par PutOut ;
    on recompresse dans le tampon de donnees }
  If Meth = 8 Then
  Begin
    Deflate(N);
    WriteAll(ZFd, Out, OutN);
  End
  Else If N > 0 Then WriteAll(ZFd, Inp, N);
  { repertoire central }
  CenPut($02014B50, 4);
  CenPut(20 + 768, 2);
  CenPut(20, 2);
  CenPut(0, 2);
  CenPut(Meth, 2);
  CenPut(Dt And $FFFF, 2);
  CenPut((Dt Shr 16) And $FFFF, 2);
  CenPut(C, 4);
  CenPut(CSz, 4);
  CenPut(N, 4);
  CenPut(Length(Nm), 2);
  CenPut(0, 2);
  CenPut(0, 2);
  CenPut(0, 2);
  CenPut(0, 2);
  CenPut((Mode Shl 16) Or Ord(IsDir) * $10, 4);
  CenPut(ZOff, 4);
  For K := 1 To Length(Nm) Do CenPut(Ord(Nm[K]), 1);
  Inc(ZNum);
  ZOff := ZOff + 30 + Length(Nm) + CSz;
  If Not Quiet Then
  Begin
    SysPut(1, '  adding: ' + Nm);
    If Meth = 8 Then
      SysPut(1, ' (deflated ' + NumS(100 - CSz * 100 Div (N + (Ord(N = 0)))) +
             '%)' + #10)
    Else SysPut(1, ' (stored 0%)' + #10);
  End;
End;

Procedure AddTree(Const Path : String; Top : Boolean);
Var
  St : TSysStat;
  Nm, Dh : String;
  D, Ino : LongInt;
  Names : Array[1..512] Of String;
  NN, K : LongInt;
  Ent : String;
Begin
  If SysLStat(Path, St) <> 0 Then
  Begin
    SysPut(2, 'zip warning: name not matched: ' + Path + #10);
    Exit;
  End;
  Nm := Path;
  If JunkPaths Then
  Begin
    K := Length(Nm);
    While (K > 0) And (Nm[K] <> '/') Do Dec(K);
    Nm := Copy(Nm, K + 1, 255);
  End;
  While (Length(Nm) > 2) And (Copy(Nm, 1, 2) = './') Do Delete(Nm, 1, 2);
  If (St.Mode And $F000) = $4000 Then
  Begin
    If Not JunkPaths Then AddFile(Path, Nm, St.Mode And 4095, St.MTime, True);
    If Recurse Then
    Begin
      D := SysOpenDir(Path);
      NN := 0;
      If D >= 0 Then
      Begin
        While SysReadDir(D, Ent, Ino) <> 0 Do
          If (Ent <> '.') And (Ent <> '..') And (NN < 512) Then
          Begin
            Inc(NN);
            Names[NN] := Ent;
          End;
        SysCloseDir(D);
      End;
      For K := 1 To NN Do
        If Path[Length(Path)] = '/' Then AddTree(Path + Names[K], False)
        Else AddTree(Path + '/' + Names[K], False);
    End;
  End
  Else If (St.Mode And $F000) = $8000 Then
    AddFile(Path, Nm, St.Mode And 4095, St.MTime, False);
End;

Procedure RunZip;
Var I, K : LongInt; A, Arc : String; NFiles : LongInt;
Begin
  Arc := '';
  NFiles := 0;
  For I := 1 To SysArgCount - 1 Do
  Begin
    A := SysArgStr(I);
    If (A = '--help') Or (A = '/?') Then
    Begin
      SysPut(1, PS(Usage[Lang]) + #10);
      SysExit(0);
    End;
  End;
  { options puis archive puis fichiers }
  K := 1;
  While K < SysArgCount Do
  Begin
    A := SysArgStr(K);
    If (Length(A) > 1) And (A[1] = '-') And (Arc = '') Then
    Begin
      For I := 2 To Length(A) Do
        Case A[I] Of
          'r' : Recurse := True;
          'j' : JunkPaths := True;
          'q' : Quiet := True;
          '0' : StoreOnly := True;
        End;
    End
    Else If Arc = '' Then Arc := A
    Else Break;
    Inc(K);
  End;
  If (Arc = '') Or (K >= SysArgCount) Then Die(PS(Usage[Lang]));
  If Copy(Arc, Length(Arc) - 3, 4) <> '.zip' Then
    If Pos('.', Arc) = 0 Then Arc := Arc + '.zip';
  ZFd := SysOpen(Arc, O_WRONLY Or O_CREAT Or O_TRUNC, 420);
  If ZFd < 0 Then Die(Arc + ': ' + SysErrorText(SysErrno));
  CenN := 0;
  ZNum := 0;
  ZOff := 0;
  While K < SysArgCount Do
  Begin
    AddTree(SysArgStr(K), True);
    Inc(K);
  End;
  { fin du repertoire central }
  WriteAll(ZFd, Cen, CenN);
  OutN := 0;
  W32($06054B50);
  W16(0);
  W16(0);
  W16(ZNum);
  W16(ZNum);
  W32(CenN);
  W32(ZOff);
  W16(0);
  WriteAll(ZFd, Out, OutN);
  SysClose(ZFd);
End;

{ ------------------------- unzip ------------------------- }

Procedure LoadZip(Const Arc : String);
Var Fd, P, Cd, N, I, Nl, El, Cl : LongInt;
Begin
  Fd := SysOpen(Arc, O_RDONLY, 0);
  If Fd < 0 Then Die(Arc + ': ' + SysErrorText(SysErrno));
  SrcN := ReadFd(Fd, Src, MaxData + 65536);
  SysClose(Fd);
  P := SrcN - 22;
  While (P >= 0) And (R32(P) <> $06054B50) Do Dec(P);
  If P < 0 Then Die('cannot find end of central directory');
  N := R16(P + 10);
  Cd := R32(P + 16);
  NEnt := 0;
  I := 0;
  While (I < N) And (NEnt < MaxEnt) Do
  Begin
    If R32(Cd) <> $02014B50 Then Die('bad central directory');
    Inc(NEnt);
    Ents[NEnt].Method := R16(Cd + 10);
    Ents[NEnt].Time := R16(Cd + 12);
    Ents[NEnt].Dat := R16(Cd + 14);
    Ents[NEnt].Crc := R32(Cd + 16);
    Ents[NEnt].CSize := R32(Cd + 20);
    Ents[NEnt].USize := R32(Cd + 24);
    Nl := R16(Cd + 28);
    El := R16(Cd + 30);
    Cl := R16(Cd + 32);
    Ents[NEnt].Attr := R32(Cd + 38);
    Ents[NEnt].Off := R32(Cd + 42);
    Ents[NEnt].Name := '';
    For P := 0 To Nl - 1 Do
      If P < 250 Then
        Ents[NEnt].Name := Ents[NEnt].Name + Chr(Src[Cd + 46 + P]);
    Cd := Cd + 46 + Nl + El + Cl;
    Inc(I);
  End;
End;

Function Exists(Const P : String) : Boolean;
Var St : TSysStat;
Begin
  Exists := SysStat(P, St) = 0;
End;

Procedure MkDirs(Const Path : String);
Var K : LongInt; P : String;
Begin
  For K := 1 To Length(Path) Do
    If (Path[K] = '/') And (K > 1) Then
    Begin
      P := Copy(Path, 1, K - 1);
      SysMkdir(P, 493);
    End;
End;

{ extrait le membre E : retourne faux si la somme de controle echoue }
Function Extract(Var E : TEnt; Dest : LongInt) : Boolean;
Var P, Nl, El : LongInt;
Begin
  Extract := False;
  P := E.Off;
  If R32(P) <> $04034B50 Then Die('bad local header');
  Nl := R16(P + 26);
  El := R16(P + 28);
  P := P + 30 + Nl + El;
  If E.Method = 0 Then
  Begin
    If E.USize > MaxData Then Die('file too large');
    Move(Src[P], Out[0], E.USize);
    OutN := E.USize;
  End
  Else If E.Method = 8 Then Inflate(P)
  Else Die('unsupported compression method ' + NumS(E.Method));
  Extract := Crc(Out, OutN) = E.Crc;
End;

Function Wanted(Const Nm : String; First : LongInt) : Boolean;
Var I, K : LongInt; A : String;
Begin
  If First >= SysArgCount Then
  Begin
    Wanted := True;
    Exit;
  End;
  Wanted := False;
  For I := First To SysArgCount - 1 Do
  Begin
    A := SysArgStr(I);
    If A = Nm Then Wanted := True;
    If (Length(A) > 0) And (A[Length(A)] = '*') Then
      If Copy(Nm, 1, Length(A) - 1) = Copy(A, 1, Length(A) - 1) Then
        Wanted := True;
  End;
End;

Procedure RunUnzip;
Var
  I, K, Arc, FirstM, Fd, Tot : LongInt;
  A, ArcN, Path : String;
  Ok : Boolean;
  Mode : LongInt;
Begin
  ArcN := '';
  FirstM := 0;
  DestDir := '';
  I := 1;
  While I < SysArgCount Do
  Begin
    A := SysArgStr(I);
    If (A = '--help') Or (A = '/?') Then
    Begin
      SysPut(1, PS(Usage[Lang]) + #10);
      SysExit(0);
    End
    Else If (Length(A) > 1) And (A[1] = '-') And (ArcN = '') Then
    Begin
      If A = '-d' Then
      Begin
        Inc(I);
        If I < SysArgCount Then DestDir := SysArgStr(I);
      End
      Else
        For K := 2 To Length(A) Do
          Case A[K] Of
            'l', 'v' : ListOnly := True;
            't' : TestOnly := True;
            'p' : ToStdout := True;
            'o' : Overwrite := True;
            'n' : NeverOver := True;
            'q' : Quiet := True;
          End;
    End
    Else If ArcN = '' Then
    Begin
      ArcN := A;
      FirstM := I + 1;
    End;
    Inc(I);
  End;
  If ArcN = '' Then Die(PS(Usage[Lang]));
  If (Not ListOnly) And (Pos('.', ArcN) = 0) Then ArcN := ArcN + '.zip';
  LoadZip(ArcN);
  If ListOnly Then
  Begin
    SysPut(1, 'Archive:  ' + ArcN + #10);
    SysPut(1, '  Length      Date    Time    Name' + #10);
    SysPut(1, '---------  ---------- -----   ----' + #10);
    Tot := 0;
    For I := 1 To NEnt Do
    Begin
      Str(Ents[I].USize : 9, A);
      A := A + '  ' + NumS(((Ents[I].Dat Shr 9) And 127) + 1980) + '-';
      K := (Ents[I].Dat Shr 5) And 15;
      If K < 10 Then A := A + '0';
      A := A + NumS(K) + '-';
      K := Ents[I].Dat And 31;
      If K < 10 Then A := A + '0';
      A := A + NumS(K) + ' ';
      K := (Ents[I].Time Shr 11) And 31;
      If K < 10 Then A := A + '0';
      A := A + NumS(K) + ':';
      K := (Ents[I].Time Shr 5) And 63;
      If K < 10 Then A := A + '0';
      A := A + NumS(K) + '   ' + Ents[I].Name;
      SysPut(1, A + #10);
      Tot := Tot + Ents[I].USize;
    End;
    SysPut(1, '---------                     -------' + #10);
    Str(Tot : 9, A);
    SysPut(1, A + '                     ' + NumS(NEnt) + ' files' + #10);
    Exit;
  End;
  If (DestDir <> '') Then
  Begin
    SysMkdir(DestDir, 493);
    If DestDir[Length(DestDir)] <> '/' Then DestDir := DestDir + '/';
  End;
  Tot := 0;
  For I := 1 To NEnt Do
    If Wanted(Ents[I].Name, FirstM) Then
    Begin
      Path := DestDir + Ents[I].Name;
      If (Length(Ents[I].Name) > 0) And
         (Ents[I].Name[Length(Ents[I].Name)] = '/') Then
      Begin
        If (Not TestOnly) And (Not ToStdout) Then
        Begin
          MkDirs(Path);
          SysMkdir(Copy(Path, 1, Length(Path) - 1), 493);
          If Not Quiet Then SysPut(1, '   creating: ' + Ents[I].Name + #10);
        End;
        Continue;
      End;
      Ok := Extract(Ents[I], 0);
      If Not Ok Then
      Begin
        SysPut(2, '    bad CRC ' + Ents[I].Name + #10);
        Tot := 1;
        Continue;
      End;
      If TestOnly Then
      Begin
        If Not Quiet Then
          SysPut(1, '    testing: ' + Ents[I].Name + '   OK' + #10);
        Continue;
      End;
      If ToStdout Then
      Begin
        WriteAll(1, Out, OutN);
        Continue;
      End;
      If Exists(Path) Then
        If NeverOver Then Continue;
      MkDirs(Path);
      Fd := SysOpen(Path, O_WRONLY Or O_CREAT Or O_TRUNC, 420);
      If Fd < 0 Then
      Begin
        SysPut(2, 'unzip: ' + Path + ': ' + SysErrorText(SysErrno) + #10);
        Tot := 1;
        Continue;
      End;
      If OutN > 0 Then WriteAll(Fd, Out, OutN);
      SysClose(Fd);
      Mode := (Ents[I].Attr Shr 16) And 4095;
      If Mode <> 0 Then SysChmod(Path, Mode);
      If Not Quiet Then
      Begin
        If Ents[I].Method = 8 Then
          SysPut(1, '  inflating: ' + Ents[I].Name + #10)
        Else SysPut(1, ' extracting: ' + Ents[I].Name + #10);
      End;
    End;
  SysExit(Tot);
End;

Begin
  Lang := SysLang;
  If (Lang < 1) Or (Lang > 5) Then Lang := 1;
  Prog := SysArgStr(0);
  While Pos('/', Prog) > 0 Do Prog := Copy(Prog, Pos('/', Prog) + 1, 255);
  InitCrc;
  InitFixed;
  If Prog = 'zip' Then RunZip
  Else If (Prog = 'unzip') Or (Prog = 'zipinfo') Then
  Begin
    If Prog = 'zipinfo' Then ListOnly := True;
    RunUnzip;
  End
  Else Die('zip | unzip | zipinfo');
End.
