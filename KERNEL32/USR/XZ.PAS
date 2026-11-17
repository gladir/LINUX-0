{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2026
  @website(https://www.gladir.com/linux-0)
  @abstract(Target: LPC -3X)
  @description: xz, unxz, xzcat, lzma, unlzma, lzcat (un seul programme, le
      nom lu dans argv[0]) : format .xz (LZMA2, controles CRC32 et CRC64,
      flux concatenes) et format .lzma ancien, en lecture ET en ecriture.
    xz [-dzckftlqv0..9e] [fichier...]    sans fichier : entree standard vers
      la sortie standard. -d decompresse, -z compresse (defaut), -c vers la
      sortie standard, -k conserve la source, -f ecrase, -t teste, -l liste.
    Compression : LZMA greedy avec chaines de hachage (lc=3 lp=0 pb=2,
    fenetre de 1 Mio) dans des blocs LZMA2 ; controle CRC64. Le fichier
    d'entree est lu en memoire (limite : memoire libre). La decompression
    d'un flux dont le dictionnaire depasse 32 Mio est refusee.
    Messages en cinq langues (LANGUAGE).
}

Program Xz;

Const
  DICTMAX = 33554432;
  CHUNK = 32768;                       { octets bruts par bloc LZMA2 }
  M : Array[1..8, 1..5] Of PChar = (
    ('Usage : xz [-dzckftlqv0-9e] [fichier...]',
     'Usage: xz [-dzckftlqv0-9e] [file...]',
     'Aufruf: xz [-dzckftlqv0-9e] [Datei...]',
     'Uso: xz [-dzckftlqv0-9e] [fichero...]',
     'Uso: xz [-dzckftlqv0-9e] [file...]'),
    ('format de fichier inconnu', 'file format not recognized',
     'Dateiformat nicht erkannt', 'formato de fichero no reconocido',
     'formato di file non riconosciuto'),
    ('donnees corrompues', 'compressed data is corrupt',
     'Komprimierte Daten sind beschaedigt', 'los datos estan danados',
     'dati compressi danneggiati'),
    ('fin de fichier inattendue', 'unexpected end of input',
     'unerwartetes Dateiende', 'fin de entrada inesperado',
     'fine dell''input inattesa'),
    ('dictionnaire trop grand', 'dictionary too large',
     'Woerterbuch zu gross', 'diccionario demasiado grande',
     'dizionario troppo grande'),
    ('le fichier de sortie existe deja', 'output file already exists',
     'Ausgabedatei existiert bereits', 'el fichero de salida ya existe',
     'il file di output esiste gia'''),
    ('somme de controle incorrecte', 'check value mismatch',
     'Pruefsumme falsch', 'suma de comprobacion incorrecta',
     'checksum errato'),
    ('suffixe inconnu : fichier ignore', 'unknown suffix: file skipped',
     'unbekannte Endung: Datei uebersprungen',
     'sufijo desconocido: fichero omitido',
     'suffisso sconosciuto: file ignorato'));

Var
  Prog : String;
  Rc : LongInt;
  WinTotal : LongInt;
  OptD, OptC, OptK, OptF, OptT, OptL, OptQ, OptV, Lzma : Boolean;
  { entree en memoire }
  InBuf : LongInt;
  InLen, InPos : LongInt;
  { sortie bufferisee }
  OutFd : LongInt;
  OutBuf : Array[0..65535] Of Byte;
  OutN : LongInt;
  OutTotal : LongInt;
  { controles }
  Crc32Tab : Array[0..255] Of LongInt;
  Crc64Lo, Crc64Hi : Array[0..255] Of LongInt;
  CheckKind : LongInt;
  C32 : LongInt;
  C64Lo, C64Hi : LongInt;
  { fenetre du dictionnaire }
  Win : LongInt;
  WinSize, WinPos, WinFill : LongInt;
  { decodeur de plage }
  RcRange, RcCode : LongInt;
  RcBad : Boolean;
  Failed : Boolean;
  FailMsg : LongInt;
  { modele LZMA }
  Lc, Lp, Pb : LongInt;
  IsMatch : Array[0..191] Of Word;
  IsRep, IsRepG0, IsRepG1, IsRepG2 : Array[0..11] Of Word;
  IsRep0Long : Array[0..191] Of Word;
  PosSlot : Array[0..255] Of Word;
  SpecPos : Array[0..127] Of Word;
  Align : Array[0..15] Of Word;
  LenCh, LenCh2 : Array[0..1] Of Word;
  LenLow : Array[0..255] Of Word;       { 2 x 16 x 8 }
  LenMid : Array[0..255] Of Word;
  LenHigh : Array[0..511] Of Word;      { 2 x 256 }
  Lit : Array[0..24575] Of Word;        { 0x300 << (lc + lp), lc + lp <= 5 }
  LitMax : LongInt;
  State, Rep0, Rep1, Rep2, Rep3 : LongInt;

Function Msg(Id : LongInt) : String;
Var P : PChar; X : String;
Begin
  P := M[Id, SysLang];
  X := '';
  While P^ <> #0 Do
  Begin
    X := X + P^;
    Inc(P);
  End;
  Msg := X;
End;

Procedure Fail(Id : LongInt);
Begin
  If Not Failed Then FailMsg := Id;
  Failed := True;
End;

Function GetL(A : LongInt) : LongInt;
Begin
  GetL := MemL[0:A];
End;

Function Alloc(N : LongInt) : LongInt;
Begin
  Alloc := HeapAlloc(1, 8, N);
End;

Function NumS(V : LongInt) : String;
Var S : String;
Begin
  Str(V, S);
  NumS := S;
End;

{ ---------- sommes de controle ---------- }

Procedure CrcInit;
Var I, J, C, Lo, Hi, T : LongInt;
Begin
  For I := 0 To 255 Do
  Begin
    C := I;
    For J := 1 To 8 Do
      If (C And 1) <> 0 Then C := (C Shr 1) Xor $EDB88320 Else C := C Shr 1;
    Crc32Tab[I] := C;
    Lo := I;
    Hi := 0;
    For J := 1 To 8 Do
    Begin
      T := Lo And 1;
      Lo := (Lo Shr 1) Or (Hi Shl 31);
      Hi := Hi Shr 1;
      If T <> 0 Then
      Begin
        Lo := Lo Xor $D7870F42;
        Hi := Hi Xor $C96C5795;
      End;
    End;
    Crc64Lo[I] := Lo;
    Crc64Hi[I] := Hi;
  End;
End;

Function Crc32Of(Crc : LongInt; Addr, Len : LongInt) : LongInt;
Var P : ^Byte; K : LongInt;
Begin
  Crc := Crc Xor -1;
  For K := 0 To Len - 1 Do
  Begin
    P := Pointer(Addr + K);
    Crc := Crc32Tab[(Crc Xor P^) And $FF] Xor (Crc Shr 8);
  End;
  Crc32Of := Crc Xor -1;
End;

Procedure CheckByte(B : LongInt);
Var I, Lo, Hi : LongInt;
Begin
  If CheckKind = 1 Then
    C32 := Crc32Tab[(C32 Xor B) And $FF] Xor (C32 Shr 8)
  Else If CheckKind = 4 Then
  Begin
    I := (C64Lo Xor B) And $FF;
    Lo := (C64Lo Shr 8) Or (C64Hi Shl 24);
    Hi := C64Hi Shr 8;
    C64Lo := Lo Xor Crc64Lo[I];
    C64Hi := Hi Xor Crc64Hi[I];
  End;
End;

Procedure CheckStart;
Begin
  C32 := -1;
  C64Lo := -1;
  C64Hi := -1;
End;

{ ---------- sortie ---------- }

Procedure OutFlush;
Var P, K : LongInt;
Begin
  P := 0;
  If OutFd >= 0 Then
    While P < OutN Do
    Begin
      K := LnxSys3(4, OutFd, LongInt(@OutBuf) + P, OutN - P);
      If K <= 0 Then
      Begin
        Failed := True;
        Break;
      End;
      P := P + K;
    End;
  OutN := 0;
End;

Procedure OutByte(B : LongInt);
Begin
  If OutN >= 65536 Then OutFlush;
  OutBuf[OutN] := B;
  Inc(OutN);
  Inc(OutTotal);
  CheckByte(B);
End;

Procedure OutRaw(B : LongInt);
Begin
  If OutN >= 65536 Then OutFlush;
  OutBuf[OutN] := B;
  Inc(OutN);
End;

Procedure OutRaw32(V : LongInt);
Begin
  OutRaw(V And 255);
  OutRaw((V Shr 8) And 255);
  OutRaw((V Shr 16) And 255);
  OutRaw((V Shr 24) And 255);
End;

{ ---------- decodeur de plage ---------- }

Function InByte : LongInt;
Begin
  If InPos >= InLen Then
  Begin
    Fail(4);
    InByte := 0;
    Exit;
  End;
  InByte := Mem[0:InBuf + InPos];
  Inc(InPos);
End;

Procedure RcNorm;
Begin
  If (RcRange And $FF000000) = 0 Then
  Begin
    RcRange := RcRange Shl 8;
    RcCode := (RcCode Shl 8) Or InByte;
  End;
End;

Function UCmp(A, B : LongInt) : LongInt;
Begin
  A := A Xor $80000000;
  B := B Xor $80000000;
  If A < B Then UCmp := -1 Else If A > B Then UCmp := 1 Else UCmp := 0;
End;

Function RcBitD(Var P : Word) : LongInt;
Var Bound : LongInt;
Begin
  Bound := (RcRange Shr 11) * P;
  If UCmp(RcCode, Bound) < 0 Then
  Begin
    RcRange := Bound;
    P := P + ((2048 - P) Shr 5);
    RcNorm;
    RcBitD := 0;
  End
  Else
  Begin
    RcRange := RcRange - Bound;
    RcCode := RcCode - Bound;
    P := P - (P Shr 5);
    RcNorm;
    RcBitD := 1;
  End;
End;

Function RcDirect(N : LongInt) : LongInt;
Var R, T : LongInt;
Begin
  R := 0;
  While N > 0 Do
  Begin
    RcRange := RcRange Shr 1;
    RcCode := RcCode - RcRange;
    T := 0 - (RcCode Shr 31);
    RcCode := RcCode + (RcRange And T);
    RcNorm;
    R := (R Shl 1) + (T + 1);
    Dec(N);
  End;
  RcDirect := R;
End;

Procedure RcInitD;
Var K : LongInt;
Begin
  RcCode := 0;
  RcRange := -1;
  InByte;
  For K := 1 To 4 Do RcCode := (RcCode Shl 8) Or InByte;
End;

{ ---------- modele ---------- }

Procedure FillProb(Var A : Word; N : LongInt);
Var P : ^Word; K : LongInt;
Begin
  For K := 0 To N - 1 Do
  Begin
    P := Pointer(LongInt(@A) + K * 2);
    P^ := 1024;
  End;
End;

Procedure ModelReset;
Begin
  FillProb(IsMatch[0], 192);
  FillProb(IsRep[0], 12);
  FillProb(IsRepG0[0], 12);
  FillProb(IsRepG1[0], 12);
  FillProb(IsRepG2[0], 12);
  FillProb(IsRep0Long[0], 192);
  FillProb(PosSlot[0], 256);
  FillProb(SpecPos[0], 128);
  FillProb(Align[0], 16);
  FillProb(LenCh[0], 2);
  FillProb(LenCh2[0], 2);
  FillProb(LenLow[0], 256);
  FillProb(LenMid[0], 256);
  FillProb(LenHigh[0], 512);
  FillProb(Lit[0], 24576);
  State := 0;
  Rep0 := 0;
  Rep1 := 0;
  Rep2 := 0;
  Rep3 := 0;
End;

Function SetProps(B : LongInt) : Boolean;
Begin
  SetProps := False;
  If B >= 225 Then Exit;
  Lc := B Mod 9;
  B := B Div 9;
  Lp := B Mod 5;
  Pb := B Div 5;
  If Lc + Lp > 4 Then Exit;
  LitMax := (1 Shl (Lc + Lp)) * 768;
  SetProps := True;
End;

Function TreeD(Var A : Word; Base, Bits : LongInt) : LongInt;
Var M_, K : LongInt; P : ^Word;
Begin
  M_ := 1;
  For K := 1 To Bits Do
  Begin
    P := Pointer(LongInt(@A) + (Base + M_) * 2);
    M_ := (M_ Shl 1) + RcBitD(P^);
  End;
  TreeD := M_ - (1 Shl Bits);
End;

Function RTreeD(Var A : Word; Base, Bits : LongInt) : LongInt;
Var M_, K, R : LongInt; P : ^Word;
Begin
  M_ := 1;
  R := 0;
  For K := 0 To Bits - 1 Do
  Begin
    P := Pointer(LongInt(@A) + (Base + M_) * 2);
    If RcBitD(P^) <> 0 Then
    Begin
      M_ := (M_ Shl 1) + 1;
      R := R Or (1 Shl K);
    End
    Else M_ := M_ Shl 1;
  End;
  RTreeD := R;
End;

Function LenD(Rep : LongInt; PosState : LongInt) : LongInt;
Var Ch : LongInt;
Begin
  If RcBitD(LenCh[Rep]) = 0 Then
  Begin
    LenD := TreeD(LenLow[0], (Rep * 16 + PosState) * 8, 3);
    Exit;
  End;
  If RcBitD(LenCh2[Rep]) = 0 Then
  Begin
    LenD := 8 + TreeD(LenMid[0], (Rep * 16 + PosState) * 8, 3);
    Exit;
  End;
  LenD := 16 + TreeD(LenHigh[0], Rep * 256, 8);
End;

{ ---------- fenetre ---------- }

Function WinGet(Dist : LongInt) : LongInt;
Var P : LongInt;
Begin
  P := WinPos - Dist - 1;
  If P < 0 Then P := P + WinSize;
  WinGet := Mem[0:Win + P];
End;

Procedure WinPut(B : LongInt);
Begin
  Mem[0:Win + WinPos] := B;
  Inc(WinPos);
  If WinPos >= WinSize Then WinPos := 0;
  If WinFill < WinSize Then Inc(WinFill);
  Inc(WinTotal);
  OutByte(B);
End;

{ decode jusqu'a Limit octets ; Unk : taille inconnue (arret sur marqueur) }
Procedure DecodeLzma(Limit : LongInt; Unk : Boolean);
Var Done, PosState, B, Sym, MB, Off, Len, DistSlot, NDirect, Dist, K, LS,
    LitState, PrevB, Bit : LongInt; Mask : LongInt; P : ^Word;
Begin
  Done := 0;
  Mask := (1 Shl Pb) - 1;
  While (Unk Or (Done < Limit)) And Not Failed Do
  Begin
    PosState := WinTotal And Mask;
    If InPos > InLen + 8 Then
    Begin
      Fail(4);
      Exit;
    End;
    If RcBitD(IsMatch[State * 16 + PosState]) = 0 Then
    Begin
      { litteral }
      PrevB := 0;
      If WinFill > 0 Then PrevB := WinGet(0);
      LitState := ((WinTotal And ((1 Shl Lp) - 1)) Shl Lc) +
                  (PrevB Shr (8 - Lc));
      Off := LitState * 768;
      Sym := 1;
      If State >= 7 Then
      Begin
        MB := WinGet(Rep0);
        While Sym < 256 Do
        Begin
          Bit := (MB Shr 7) And 1;
          MB := MB Shl 1;
          P := Pointer(LongInt(@Lit[0]) + (Off + ((1 + Bit) Shl 8) + Sym) * 2);
          K := RcBitD(P^);
          Sym := (Sym Shl 1) Or K;
          If K <> Bit Then Break;
        End;
      End;
      While Sym < 256 Do
      Begin
        P := Pointer(LongInt(@Lit[0]) + (Off + Sym) * 2);
        Sym := (Sym Shl 1) Or RcBitD(P^);
      End;
      WinPut(Sym And 255);
      Inc(Done);
      If State < 4 Then State := 0
      Else If State < 10 Then State := State - 3
      Else State := State - 6;
      Continue;
    End;
    If RcBitD(IsRep[State]) = 0 Then
    Begin
      { correspondance simple }
      Rep3 := Rep2;
      Rep2 := Rep1;
      Rep1 := Rep0;
      Len := LenD(0, PosState);
      If State < 7 Then State := 7 Else State := 10;
      If Len < 4 Then LS := Len Else LS := 3;
      DistSlot := TreeD(PosSlot[0], LS * 64, 6);
      If DistSlot < 4 Then Dist := DistSlot
      Else
      Begin
        NDirect := (DistSlot Shr 1) - 1;
        Dist := (2 Or (DistSlot And 1)) Shl NDirect;
        If DistSlot < 14 Then
          Dist := Dist + RTreeD(SpecPos[0], Dist - DistSlot, NDirect)
        Else
        Begin
          Dist := Dist + (RcDirect(NDirect - 4) Shl 4);
          Dist := Dist + RTreeD(Align[0], 0, 4);
        End;
      End;
      Rep0 := Dist;
      If Dist = -1 Then
      Begin
        { marqueur de fin }
        Exit;
      End;
    End
    Else
    Begin
      If WinFill = 0 Then
      Begin
        Fail(3);
        Exit;
      End;
      If RcBitD(IsRepG0[State]) = 0 Then
      Begin
        If RcBitD(IsRep0Long[State * 16 + PosState]) = 0 Then
        Begin
          { rep courte : un octet }
          If State < 7 Then State := 9 Else State := 11;
          WinPut(WinGet(Rep0));
          Inc(Done);
          Continue;
        End;
      End
      Else
      Begin
        If RcBitD(IsRepG1[State]) = 0 Then Dist := Rep1
        Else
        Begin
          If RcBitD(IsRepG2[State]) = 0 Then Dist := Rep2
          Else
          Begin
            Dist := Rep3;
            Rep3 := Rep2;
          End;
          Rep2 := Rep1;
        End;
        Rep1 := Rep0;
        Rep0 := Dist;
      End;
      Len := LenD(1, PosState);
      If State < 7 Then State := 8 Else State := 11;
    End;
    Len := Len + 2;
    If (UCmp(Rep0, WinFill) >= 0) Or (Rep0 < 0) Then
    Begin
      Fail(3);
      Exit;
    End;
    If (Not Unk) And (Done + Len > Limit) Then
    Begin
      Fail(3);
      Exit;
    End;
    For K := 1 To Len Do
    Begin
      WinPut(WinGet(Rep0));
      Inc(Done);
    End;
  End;
End;

{ ---------- lecture d'entrees ---------- }

Function RdVar(Var V : LongInt) : Boolean;
Var B, Sh : LongInt;
Begin
  V := 0;
  Sh := 0;
  RdVar := False;
  While Sh < 35 Do
  Begin
    B := InByte;
    If Failed Then Exit;
    V := V Or ((B And $7F) Shl Sh);
    If (B And $80) = 0 Then
    Begin
      RdVar := True;
      Exit;
    End;
    Sh := Sh + 7;
  End;
End;

Function Rd32 : LongInt;
Var V : LongInt;
Begin
  V := InByte;
  V := V Or (InByte Shl 8);
  V := V Or (InByte Shl 16);
  V := V Or (InByte Shl 24);
  Rd32 := V;
End;

{ decode un flux LZMA2 : dictionnaire Dict }
Procedure DecodeLzma2(DictSize : LongInt);
Var Ctl, Un, Pk, Props, Mode, Start : LongInt;
Begin
  WinSize := DictSize;
  If WinSize < 4096 Then WinSize := 4096;
  If (WinSize > DICTMAX) Or (WinSize < 0) Then
  Begin
    Fail(5);
    Exit;
  End;
  Win := Alloc(WinSize + 16);
  WinPos := 0;
  WinFill := 0;
  WinTotal := 0;
  Lc := 3; Lp := 0; Pb := 2;
  LitMax := 24576;
  ModelReset;
  While Not Failed Do
  Begin
    Ctl := InByte;
    If Failed Then Exit;
    If Ctl = 0 Then Break;
    If (Ctl = 1) Or (Ctl = 2) Then
    Begin
      Un := (InByte Shl 8) Or InByte;
      Inc(Un);
      If Ctl = 1 Then
      Begin
        WinFill := 0;
        WinTotal := 0;
      End;
      While (Un > 0) And Not Failed Do
      Begin
        WinPut(InByte);
        Dec(Un);
      End;
      Continue;
    End;
    If Ctl < $80 Then
    Begin
      Fail(3);
      Exit;
    End;
    Un := ((Ctl And $1F) Shl 16) + (InByte Shl 8);
    Un := Un + InByte + 1;
    Pk := (InByte Shl 8) + InByte + 1;
    Mode := (Ctl Shr 5) And 3;
    If Mode = 3 Then
    Begin
      WinFill := 0;
      WinTotal := 0;
    End;
    If Mode >= 2 Then
    Begin
      Props := InByte;
      If Not SetProps(Props) Then
      Begin
        Fail(3);
        Exit;
      End;
    End;
    If Mode >= 1 Then ModelReset;
    Start := InPos;
    RcInitD;
    DecodeLzma(Un, False);
    If Failed Then Exit;
    If InPos <> Start + Pk Then
    Begin
      Fail(3);
      Exit;
    End;
  End;
End;

{ ---------- conteneur .xz ---------- }

Function Skip4 : Boolean;
Begin
  While (InPos And 3) <> 0 Do
    If InByte <> 0 Then
    Begin
      Fail(2);
      Skip4 := False;
      Exit;
    End;
  Skip4 := True;
End;

Function CheckSize(K : LongInt) : LongInt;
Begin
  Case K Of
    0 : CheckSize := 0;
    1 : CheckSize := 4;
    4 : CheckSize := 8;
    10 : CheckSize := 32;
  Else
    CheckSize := 0;
  End;
End;

{ un flux .xz complet a partir de InPos ; Vrai si decode }
Function DecodeXz : Boolean;
Var Hs, Fl, K, Sz, Hdr, Ps, Dict, B, Id, Nrec, V, I, Cs, Want, Lo, Hi,
    Start, Idx0 : LongInt; Ok : Boolean; Have : Boolean;
Begin
  DecodeXz := False;
  If InPos + 12 > InLen Then
  Begin
    Fail(1);
    Exit;
  End;
  { en-tete de flux : FD 37 7A 58 5A 00, indicateurs, CRC32 }
  Start := InPos;
  If Crc32Of(0, InBuf + InPos + 6, 2) <> GetL(InBuf + InPos + 8) Then
  Begin
    Fail(2);
    Exit;
  End;
  CheckKind := Mem[0:InBuf + InPos + 7] And 15;
  InPos := InPos + 12;
  Nrec := 0;
  While Not Failed Do
  Begin
    Hs := InByte;
    If Failed Then Exit;
    If Hs = 0 Then
    Begin
      { index }
      Idx0 := InPos - 1;
      RdVar(V);
      I := V;
      For K := 1 To I Do
      Begin
        RdVar(V);
        RdVar(V);
      End;
      Skip4;
      InPos := InPos + 4;               { CRC32 de l'index (non verifie) }
      Break;
    End;
    Hdr := (Hs + 1) * 4;
    Start := InPos - 1;
    If Start + Hdr > InLen Then
    Begin
      Fail(4);
      Exit;
    End;
    If Crc32Of(0, InBuf + Start, Hdr - 4) <> GetL(InBuf + Start + Hdr - 4)
    Then
    Begin
      Fail(2);
      Exit;
    End;
    Fl := InByte;
    If (Fl And $40) <> 0 Then RdVar(V);
    If (Fl And $80) <> 0 Then RdVar(V);
    If (Fl And 3) <> 0 Then
    Begin
      Fail(1);
      Exit;
    End;
    Id := 0;
    RdVar(Id);
    If Id <> $21 Then
    Begin
      Fail(1);
      Exit;
    End;
    RdVar(Ps);
    Dict := InByte;
    If Dict > 40 Then
    Begin
      Fail(3);
      Exit;
    End;
    If Dict = 40 Then Dict := -1
    Else Dict := (2 Or (Dict And 1)) Shl ((Dict Shr 1) + 11);
    InPos := Start + Hdr;
    CheckStart;
    OutTotal := 0;
    DecodeLzma2(Dict);
    If Win <> 0 Then
    Begin
      HeapFree(1, 0, Win);
      Win := 0;
    End;
    If Failed Then Exit;
    Skip4;
    { controle }
    Cs := CheckSize(CheckKind);
    If InPos + Cs > InLen Then
    Begin
      Fail(4);
      Exit;
    End;
    If CheckKind = 1 Then
    Begin
      If GetL(InBuf + InPos) <> (C32 Xor -1) Then Fail(7);
    End
    Else If CheckKind = 4 Then
    Begin
      If (GetL(InBuf + InPos) <> (C64Lo Xor -1)) Or
         (GetL(InBuf + InPos + 4) <> (C64Hi Xor -1)) Then Fail(7);
    End;
    InPos := InPos + Cs;
    Inc(Nrec);
  End;
  If Failed Then Exit;
  { pied de flux : 12 octets }
  InPos := InPos + 12;
  If InPos > InLen Then
  Begin
    Fail(4);
    Exit;
  End;
  DecodeXz := True;
End;

Function DecodeLzmaAlone : Boolean;
Var Props, Dict, K, SzLo, SzHi : LongInt;
Begin
  DecodeLzmaAlone := False;
  If InLen < 13 Then
  Begin
    Fail(1);
    Exit;
  End;
  Props := InByte;
  Dict := Rd32;
  SzLo := Rd32;
  SzHi := Rd32;
  If Not SetProps(Props) Then
  Begin
    Fail(1);
    Exit;
  End;
  If (Dict < 4096) Or (UCmp(Dict, DICTMAX) > 0) Then Dict := 4096;
  If UCmp(Dict, DICTMAX) > 0 Then
  Begin
    Fail(5);
    Exit;
  End;
  WinSize := Dict;
  If WinSize < 65536 Then WinSize := 65536;
  Win := Alloc(WinSize + 16);
  WinPos := 0;
  WinFill := 0;
  WinTotal := 0;
  CheckKind := 0;
  ModelReset;
  RcInitD;
  If (SzLo = -1) And (SzHi = -1) Then DecodeLzma(0, True)
  Else DecodeLzma(SzLo, False);
  DecodeLzmaAlone := Not Failed;
End;

{ ---------- compression ---------- }

Var
  { codeur de plage }
  EcLow : Double;
  EcRange, EcCache, EcCacheSize : LongInt;
  CoBuf : LongInt;                       { sortie du bloc en cours }
  CoLen : LongInt;
  { recherche de correspondances }
  Hash : Array[0..65535] Of LongInt;
  Prev : LongInt;                        { chaine : une entree par octet }
  ESrc : LongInt;                        { donnees a compresser }
  ELen : LongInt;

Procedure CoPut(B : LongInt);
Begin
  Mem[0:CoBuf + CoLen] := B And 255;
  Inc(CoLen);
End;

Procedure EcShift;
Var Hi, Lo : LongInt; T : Double;
Begin
  Hi := 0;
  If EcLow >= 4294967296.0 Then Hi := 1;
  T := EcLow - Hi * 4294967296.0;
  If (T < 4278190080.0) Or (Hi <> 0) Then
  Begin
    Lo := EcCache;
    Repeat
      CoPut(Lo + Hi);
      Lo := 255;
      Dec(EcCacheSize);
    Until EcCacheSize = 0;
    EcCache := Trunc(T / 16777216.0) And 255;
  End;
  Inc(EcCacheSize);
  EcLow := (T - Trunc(T / 16777216.0) * 16777216.0) * 256.0;
End;

Procedure EcInit;
Begin
  EcLow := 0;
  EcRange := -1;
  EcCache := 0;
  EcCacheSize := 1;
  CoLen := 0;
End;

Procedure EcBit(Var P : Word; Bit : LongInt);
Var Bound : LongInt;
Begin
  Bound := (EcRange Shr 11) * P;
  If Bit = 0 Then
  Begin
    EcRange := Bound;
    P := P + ((2048 - P) Shr 5);
  End
  Else
  Begin
    If Bound >= 0 Then EcLow := EcLow + Bound
    Else EcLow := EcLow + Bound + 4294967296.0;
    EcRange := EcRange - Bound;
    P := P - (P Shr 5);
  End;
  While (EcRange And $FF000000) = 0 Do
  Begin
    EcRange := EcRange Shl 8;
    EcShift;
  End;
End;

Procedure EcDirect(V, N : LongInt);
Var K, B : LongInt;
Begin
  For K := N - 1 DownTo 0 Do
  Begin
    EcRange := EcRange Shr 1;
    If ((V Shr K) And 1) <> 0 Then
      EcLow := EcLow + (EcRange And $7FFFFFFF) +
               ((EcRange Shr 31) * 2147483648.0);
    While (EcRange And $FF000000) = 0 Do
    Begin
      EcRange := EcRange Shl 8;
      EcShift;
    End;
  End;
End;

Procedure EcFlush;
Var K : LongInt;
Begin
  For K := 1 To 5 Do EcShift;
End;

Procedure EcTree(Var A : Word; Base, Bits, Sym : LongInt);
Var M_, K, Bit : LongInt; P : ^Word;
Begin
  M_ := 1;
  For K := Bits - 1 DownTo 0 Do
  Begin
    Bit := (Sym Shr K) And 1;
    P := Pointer(LongInt(@A) + (Base + M_) * 2);
    EcBit(P^, Bit);
    M_ := (M_ Shl 1) Or Bit;
  End;
End;

Procedure EcRTree(Var A : Word; Base, Bits, Sym : LongInt);
Var M_, K, Bit : LongInt; P : ^Word;
Begin
  M_ := 1;
  For K := 0 To Bits - 1 Do
  Begin
    Bit := (Sym Shr K) And 1;
    P := Pointer(LongInt(@A) + (Base + M_) * 2);
    EcBit(P^, Bit);
    M_ := (M_ Shl 1) Or Bit;
  End;
End;

Procedure EcLen(Rep, Len, PosState : LongInt);
Begin
  Len := Len - 2;
  If Len < 8 Then
  Begin
    EcBit(LenCh[Rep], 0);
    EcTree(LenLow[0], (Rep * 16 + PosState) * 8, 3, Len);
  End
  Else If Len < 16 Then
  Begin
    EcBit(LenCh[Rep], 1);
    EcBit(LenCh2[Rep], 0);
    EcTree(LenMid[0], (Rep * 16 + PosState) * 8, 3, Len - 8);
  End
  Else
  Begin
    EcBit(LenCh[Rep], 1);
    EcBit(LenCh2[Rep], 1);
    EcTree(LenHigh[0], Rep * 256, 8, Len - 16);
  End;
End;

Function EByte(P : LongInt) : LongInt;
Begin
  EByte := Mem[0:ESrc + P];
End;

Function Slot(Dist : LongInt) : LongInt;
Var K : LongInt;
Begin
  If Dist < 4 Then
  Begin
    Slot := Dist;
    Exit;
  End;
  K := 31;
  While ((Dist Shr K) And 1) = 0 Do Dec(K);
  Slot := (K * 2) + ((Dist Shr (K - 1)) And 1);
End;

{ encode les octets [Pos0, Pos1) comme un bloc LZMA ; Pos0 = debut absolu }
Procedure EncodeRange(Pos0, Pos1 : LongInt);
Var Pos, MatchLen, MatchDist, L, D, Cand, Chain, Best, BestD, H, PosState,
    LitState, PrevB, Off, Sym, MB, Bit, K, Mask, Sl, NDirect, Base, LS,
    MaxL, RepLen : LongInt; P : ^Word; Dst : LongInt;
Begin
  Mask := (1 Shl Pb) - 1;
  Pos := Pos0;
  While Pos < Pos1 Do
  Begin
    PosState := Pos And Mask;
    MaxL := Pos1 - Pos;
    If MaxL > 273 Then MaxL := 273;
    { cherche une correspondance }
    Best := 0;
    BestD := 0;
    If MaxL >= 3 Then
    Begin
      H := (EByte(Pos) Shl 8 Xor EByte(Pos + 1) Shl 4 Xor EByte(Pos + 2)) And
           $FFFF;
      H := (EByte(Pos) * 251 + EByte(Pos + 1) * 31 + EByte(Pos + 2)) And $FFFF;
      Cand := Hash[H];
      Chain := 0;
      While (Cand >= 0) And (Chain < 24) Do
      Begin
        D := Pos - Cand - 1;
        If D >= 1048576 - 8 Then Break;
        L := 0;
        While (L < MaxL) And (EByte(Cand + L) = EByte(Pos + L)) Do Inc(L);
        If L > Best Then
        Begin
          Best := L;
          BestD := D;
          If L = MaxL Then Break;
        End;
        Cand := GetL(Prev + (Cand And $FFFFF) * 4);
        If (Cand >= 0) And (Pos - Cand - 1 >= 1048576 - 8) Then Break;
        Inc(Chain);
      End;
    End;
    { correspondance a la distance Rep0 ? }
    RepLen := 0;
    If Pos > 0 Then
    Begin
      If (Rep0 < Pos) And (Rep0 < 1048576 - 8) Then
      Begin
        While (RepLen < MaxL) And
              (EByte(Pos - Rep0 - 1 + RepLen) = EByte(Pos + RepLen)) Do
          Inc(RepLen);
      End;
    End;
    { choix }
    If (RepLen >= 2) And (RepLen + 1 >= Best) Then
    Begin
      EcBit(IsMatch[State * 16 + PosState], 1);
      EcBit(IsRep[State], 1);
      EcBit(IsRepG0[State], 0);
      EcBit(IsRep0Long[State * 16 + PosState], 1);
      EcLen(1, RepLen, PosState);
      If State < 7 Then State := 8 Else State := 11;
      MatchLen := RepLen;
    End
    Else If Best >= 3 Then
    Begin
      EcBit(IsMatch[State * 16 + PosState], 1);
      EcBit(IsRep[State], 0);
      EcLen(0, Best, PosState);
      If Best - 2 < 4 Then LS := Best - 2 Else LS := 3;
      Sl := Slot(BestD);
      EcTree(PosSlot[0], LS * 64, 6, Sl);
      If Sl >= 4 Then
      Begin
        NDirect := (Sl Shr 1) - 1;
        Base := (2 Or (Sl And 1)) Shl NDirect;
        If Sl < 14 Then
          EcRTree(SpecPos[0], Base - Sl, NDirect, BestD - Base)
        Else
        Begin
          EcDirect((BestD - Base) Shr 4, NDirect - 4);
          EcRTree(Align[0], 0, 4, (BestD - Base) And 15);
        End;
      End;
      Rep3 := Rep2;
      Rep2 := Rep1;
      Rep1 := Rep0;
      Rep0 := BestD;
      If State < 7 Then State := 7 Else State := 10;
      MatchLen := Best;
    End
    Else
    Begin
      { litteral }
      EcBit(IsMatch[State * 16 + PosState], 0);
      PrevB := 0;
      If Pos > 0 Then PrevB := EByte(Pos - 1);
      LitState := ((Pos And ((1 Shl Lp) - 1)) Shl Lc) + (PrevB Shr (8 - Lc));
      Off := LitState * 768;
      Sym := EByte(Pos) Or 256;
      If State >= 7 Then
      Begin
        MB := EByte(Pos - Rep0 - 1);
        Base := 256;
        K := 8;
        Dst := 1;
        While K > 0 Do
        Begin
          Dec(K);
          Bit := (Sym Shr K) And 1;
          MB := MB Shl 1;
          P := Pointer(LongInt(@Lit[0]) +
               (Off + ((1 + ((MB Shr 8) And 1)) Shl 8) + Dst) * 2);
          EcBit(P^, Bit);
          Dst := (Dst Shl 1) Or Bit;
          If ((MB Shr 8) And 1) <> Bit Then Break;
        End;
        While K > 0 Do
        Begin
          Dec(K);
          Bit := (Sym Shr K) And 1;
          P := Pointer(LongInt(@Lit[0]) + (Off + Dst) * 2);
          EcBit(P^, Bit);
          Dst := (Dst Shl 1) Or Bit;
        End;
      End
      Else
      Begin
        Dst := 1;
        For K := 7 DownTo 0 Do
        Begin
          Bit := (Sym Shr K) And 1;
          P := Pointer(LongInt(@Lit[0]) + (Off + Dst) * 2);
          EcBit(P^, Bit);
          Dst := (Dst Shl 1) Or Bit;
        End;
      End;
      If State < 4 Then State := 0
      Else If State < 10 Then State := State - 3
      Else State := State - 6;
      MatchLen := 1;
    End;
    { met a jour la table de hachage pour tous les octets consommes }
    For K := 0 To MatchLen - 1 Do
      If Pos + K + 3 <= ELen Then
      Begin
        H := (EByte(Pos + K) * 251 + EByte(Pos + K + 1) * 31 +
              EByte(Pos + K + 2)) And $FFFF;
        MemL[0:Prev + ((Pos + K) And $FFFFF) * 4] := Hash[H];
        Hash[H] := Pos + K;
      End;
    Pos := Pos + MatchLen;
  End;
  { le dernier bloc peut deborder Pos1 d'un octet de correspondance : rare }
End;

Procedure PutLe(V : Double; N : LongInt);
Var K : LongInt; T : Double;
Begin
  T := V;
  For K := 1 To N Do
  Begin
    OutRaw(Trunc(T - Trunc(T / 256) * 256));
    T := Trunc(T / 256);
  End;
End;

Procedure PutVar(V : LongInt);
Begin
  While V >= 128 Do
  Begin
    OutRaw((V And 127) Or 128);
    V := V Shr 7;
  End;
  OutRaw(V);
End;

Function VarLen(V : LongInt) : LongInt;
Var N : LongInt;
Begin
  N := 1;
  While V >= 128 Do
  Begin
    V := V Shr 7;
    Inc(N);
  End;
  VarLen := N;
End;

{ compresse les ELen octets de ESrc vers OutFd au format .xz }
Procedure CompressXz;
Var Pos, N, K, Hl, PackN, Total, HdrSz, Un, I, C0, C1, IdxLen : LongInt;
    First : Boolean; Hd : Array[0..31] Of Byte; Cr : LongInt;
    Idx : Array[0..31] Of Byte; Ni : LongInt;
    T : Double;
Begin
  { en-tete de flux : CRC64 (type 4) }
  OutRaw($FD); OutRaw($37); OutRaw($7A); OutRaw($58); OutRaw($5A); OutRaw(0);
  Hd[0] := 0;
  Hd[1] := 4;
  OutRaw(0);
  OutRaw(4);
  Hd[0] := 0;
  Hd[1] := 4;
  OutRaw32(Crc32Of(0, LongInt(@Hd), 2));
  CheckKind := 4;
  CheckStart;
  PackN := 0;
  If ELen > 0 Then
  Begin
    { en-tete de bloc : taille 12 (octets/4 - 1 = 2), indicateurs 0,
      filtre LZMA2 (0x21, 1, propriete 16 = 1 Mio), remplissage, CRC32 }
    Hd[0] := 2;
    Hd[1] := 0;
    Hd[2] := $21;
    Hd[3] := 1;
    Hd[4] := 16;
    Hd[5] := 0;
    Hd[6] := 0;
    Hd[7] := 0;
    Cr := Crc32Of(0, LongInt(@Hd), 8);
    For K := 0 To 7 Do OutRaw(Hd[K]);
    OutRaw32(Cr);
    HdrSz := 12;
    { donnees LZMA2 }
    Lc := 3; Lp := 0; Pb := 2;
    ModelReset;
    FillChar(Hash, SizeOf(Hash), 255);
    Prev := Alloc(1048576 * 4 + 16);
    CoBuf := Alloc(CHUNK * 2 + 4096);
    Pos := 0;
    First := True;
    While Pos < ELen Do
    Begin
      N := ELen - Pos;
      If N > CHUNK Then N := CHUNK;
      EcInit;
      EncodeRange(Pos, Pos + N);
      EcFlush;
      If First Then C0 := $E0 Else C0 := $80;
      OutRaw(C0 Or (((N - 1) Shr 16) And $1F));
      OutRaw(((N - 1) Shr 8) And 255);
      OutRaw((N - 1) And 255);
      OutRaw(((CoLen - 1) Shr 8) And 255);
      OutRaw((CoLen - 1) And 255);
      PackN := PackN + 5;
      If First Then
      Begin
        OutRaw((Pb * 5 + Lp) * 9 + Lc);
        Inc(PackN);
        First := False;
      End;
      For K := 0 To CoLen - 1 Do OutRaw(Mem[0:CoBuf + K]);
      PackN := PackN + CoLen;
      Pos := Pos + N;
    End;
    OutRaw(0);
    Inc(PackN);
    HeapFree(1, 0, Prev);
    HeapFree(1, 0, CoBuf);
    { remplissage a 4 octets }
    K := PackN;
    While (K And 3) <> 0 Do
    Begin
      OutRaw(0);
      Inc(K);
    End;
    { controle CRC64 des donnees brutes }
    For K := 0 To ELen - 1 Do CheckByte(EByte(K));
    OutRaw32(C64Lo Xor -1);
    OutRaw32(C64Hi Xor -1);
  End;
  { index }
  Ni := 0;
  Idx[Ni] := 0; Inc(Ni);
  If ELen > 0 Then
  Begin
    Idx[Ni] := 1; Inc(Ni);
    Un := HdrSz + PackN + 8;                 { taille non remplie }
    While Un >= 128 Do
    Begin
      Idx[Ni] := (Un And 127) Or 128; Inc(Ni);
      Un := Un Shr 7;
    End;
    Idx[Ni] := Un; Inc(Ni);
    Un := ELen;
    While Un >= 128 Do
    Begin
      Idx[Ni] := (Un And 127) Or 128; Inc(Ni);
      Un := Un Shr 7;
    End;
    Idx[Ni] := Un; Inc(Ni);
  End
  Else
  Begin
    Idx[Ni] := 0; Inc(Ni);
  End;
  While ((Ni + 4) And 3) <> 0 Do
  Begin
    Idx[Ni] := 0;
    Inc(Ni);
  End;
  Cr := Crc32Of(0, LongInt(@Idx), Ni);
  For K := 0 To Ni - 1 Do OutRaw(Idx[K]);
  OutRaw32(Cr);
  IdxLen := Ni + 4;
  { pied de flux }
  Hd[0] := ((IdxLen Div 4) - 1) And 255;
  Hd[1] := (((IdxLen Div 4) - 1) Shr 8) And 255;
  Hd[2] := 0;
  Hd[3] := 0;
  Hd[4] := 0;
  Hd[5] := 4;
  OutRaw32(Crc32Of(0, LongInt(@Hd), 6));
  For K := 0 To 5 Do OutRaw(Hd[K]);
  OutRaw($59);
  OutRaw($5A);
End;

{ ---------- fichiers ---------- }

Function ReadAll(Fd : LongInt) : Boolean;
Var Cap, N : LongInt; P : LongInt;
Begin
  Cap := 1 Shl 20;
  InBuf := Alloc(Cap + 16);
  InLen := 0;
  ReadAll := True;
  While True Do
  Begin
    If InLen + 65536 > Cap Then
    Begin
      P := Alloc(Cap * 2 + 16);
      If P = 0 Then
      Begin
        ReadAll := False;
        Exit;
      End;
      LnxMove(InBuf, P, InLen);
      HeapFree(1, 0, InBuf);
      InBuf := P;
      Cap := Cap * 2;
    End;
    N := LnxSys3(3, Fd, InBuf + InLen, 65536);
    If N = -4 Then Continue;
    If N <= 0 Then Break;
    InLen := InLen + N;
  End;
End;

Procedure Process(Const Name : String; IsStdin : Boolean);
Var Fd, Dst, Mode : LongInt; Src, Out_ : String; Ok, ToStd, Xz : Boolean;
    St : TSysStat; Suf : String; Sx : String;
Begin
  Failed := False;
  FailMsg := 0;
  Win := 0;
  If IsStdin Then
  Begin
    Fd := 0;
    Src := '(stdin)';
  End
  Else
  Begin
    Src := Name;
    Fd := SysOpen(Name, O_RDONLY, 0);
    If Fd < 0 Then
    Begin
      SysPut(2, Prog + ': ' + Name + ': ' + SysErrorText(SysErrno) + #10);
      Rc := 1;
      Exit;
    End;
  End;
  ToStd := OptC Or IsStdin;
  If (Not IsStdin) And (Not ToStd) Then
  Begin
    If OptD Or OptT Then
    Begin
      Sx := '';
      If (Length(Name) > 3) And (Copy(Name, Length(Name) - 2, 3) = '.xz') Then
        Out_ := Copy(Name, 1, Length(Name) - 3)
      Else If (Length(Name) > 5) And (Copy(Name, Length(Name) - 4, 5) = '.lzma')
        Then Out_ := Copy(Name, 1, Length(Name) - 5)
      Else If (Length(Name) > 4) And (Copy(Name, Length(Name) - 3, 4) = '.txz')
        Then Out_ := Copy(Name, 1, Length(Name) - 4) + '.tar'
      Else
      Begin
        If Not OptT Then
        Begin
          SysPut(2, Prog + ': ' + Name + ': ' + Msg(8) + #10);
          Rc := 1;
          SysClose(Fd);
          Exit;
        End;
        Out_ := Name;
      End;
    End
    Else If Lzma Then Out_ := Name + '.lzma'
    Else Out_ := Name + '.xz';
  End;
  If Not ReadAll(Fd) Then
  Begin
    SysPut(2, Prog + ': ' + Msg(4) + #10);
    Rc := 1;
    Exit;
  End;
  If Not IsStdin Then SysClose(Fd);
  OutFd := -1;
  OutN := 0;
  If Not OptT Then
  Begin
    If ToStd Then OutFd := 1
    Else
    Begin
      Mode := O_WRONLY Or O_CREAT Or O_EXCL;
      If OptF Then Mode := O_WRONLY Or O_CREAT Or O_TRUNC;
      SysStat(Name, St);
      OutFd := SysOpen(Out_, Mode, St.Mode And $FFF);
      If OutFd < 0 Then
      Begin
        SysPut(2, Prog + ': ' + Out_ + ': ' + SysErrorText(SysErrno) + #10);
        Rc := 1;
        Exit;
      End;
    End;
  End;
  InPos := 0;
  OutTotal := 0;
  If OptD Or OptT Then
  Begin
    Ok := True;
    While Ok And (InPos < InLen) And Not Failed Do
    Begin
      { remplissage de flux (zeros) entre flux concatenes }
      While (InPos + 4 <= InLen) And (GetL(InBuf + InPos) = 0) Do
        InPos := InPos + 4;
      If InPos >= InLen Then Break;
      If (InLen - InPos >= 6) And (Mem[0:InBuf + InPos] = $FD) And
         (Mem[0:InBuf + InPos + 1] = $37) And (Mem[0:InBuf + InPos + 2] = $7A)
      Then Ok := DecodeXz
      Else If (InPos = 0) And (Mem[0:InBuf] = $5D) Then
      Begin
        Ok := DecodeLzmaAlone;
        InPos := InLen;
      End
      Else
      Begin
        Fail(1);
        Ok := False;
      End;
    End;
    OutFlush;
    If Failed Then
    Begin
      SysPut(2, Prog + ': ' + Src + ': ' + Msg(FailMsg) + #10);
      Rc := 1;
      If (OutFd > 2) Then
      Begin
        SysClose(OutFd);
        SysUnlink(Out_);
      End;
      Exit;
    End;
    If InLen = 0 Then
    Begin
      SysPut(2, Prog + ': ' + Src + ': ' + Msg(1) + #10);
      Rc := 1;
    End;
  End
  Else
  Begin
    ESrc := InBuf;
    ELen := InLen;
    CompressXz;
    OutFlush;
  End;
  If (OutFd > 2) Then SysClose(OutFd);
  If (Not IsStdin) And (Not ToStd) And (Not OptK) And (Not OptT) And
     (Rc = 0) Then SysUnlink(Name);
  If OptV And Not OptQ Then
    SysPut(2, Src + ': ' + NumS(InLen) + ' -> ' + NumS(OutTotal) + #10);
  If InBuf <> 0 Then HeapFree(1, 0, InBuf);
  InBuf := 0;
End;

{ xz -l : liste brute (taille compressee / non compressee de chaque fichier) }
Procedure ListFile(Const Name : String);
Var Fd : LongInt;
Begin
  Fd := SysOpen(Name, O_RDONLY, 0);
  If Fd < 0 Then
  Begin
    SysPut(2, Prog + ': ' + Name + ': ' + SysErrorText(SysErrno) + #10);
    Rc := 1;
    Exit;
  End;
  ReadAll(Fd);
  SysClose(Fd);
  Failed := False;
  OptT := True;
  OutFd := -1;
  InPos := 0;
  OutTotal := 0;
  If (InLen > 12) And (Mem[0:InBuf] = $FD) Then
  Begin
    DecodeXz;
    OutFlush;
  End
  Else Fail(1);
  OptT := False;
  If Failed Then
  Begin
    SysPut(2, Prog + ': ' + Name + ': ' + Msg(FailMsg) + #10);
    Rc := 1;
  End
  Else
    SysPut(1, Name + ' ' + NumS(InLen) + ' ' + NumS(OutTotal) + #10);
  HeapFree(1, 0, InBuf);
  InBuf := 0;
End;

Var
  I, K, NF : LongInt;
  A : String;
  Names : Array[1..64] Of String;
  NoMore : Boolean;

BEGIN
  CrcInit;
  Prog := SysArgStr(0);
  While Pos('/', Prog) > 0 Do Prog := Copy(Prog, Pos('/', Prog) + 1, 255);
  OptD := False; OptC := False; OptK := False; OptF := False; OptT := False;
  OptL := False; OptQ := False; OptV := False;
  Lzma := (Prog = 'lzma') Or (Prog = 'unlzma') Or (Prog = 'lzcat');
  If (Prog = 'unxz') Or (Prog = 'unlzma') Then OptD := True;
  If (Prog = 'xzcat') Or (Prog = 'lzcat') Then
  Begin
    OptD := True;
    OptC := True;
  End;
  Rc := 0;
  NF := 0;
  NoMore := False;
  For I := 1 To SysArgCount - 1 Do
  Begin
    A := SysArgStr(I);
    If (Not NoMore) And (A = '--') Then NoMore := True
    Else If (Not NoMore) And (Length(A) > 1) And (A[1] = '-') Then
    Begin
      If (A = '--help') Or (A = '/?') Then
      Begin
        SysPut(1, Msg(1) + #10);
        SysExit(0);
      End;
      If A = '--decompress' Then A := '-d'
      Else If A = '--compress' Then A := '-z'
      Else If A = '--stdout' Then A := '-c'
      Else If A = '--keep' Then A := '-k'
      Else If A = '--force' Then A := '-f'
      Else If A = '--test' Then A := '-t'
      Else If A = '--list' Then A := '-l'
      Else If A = '--quiet' Then A := '-q'
      Else If A = '--verbose' Then A := '-v';
      For K := 2 To Length(A) Do
        Case A[K] Of
          'd' : OptD := True;
          'z' : OptD := False;
          'c' : OptC := True;
          'k' : OptK := True;
          'f' : OptF := True;
          't' : OptT := True;
          'l' : OptL := True;
          'q' : OptQ := True;
          'v' : OptV := True;
          '0'..'9', 'e', 'T', 'S' : ;
        End;
    End
    Else If NF < 64 Then
    Begin
      Inc(NF);
      Names[NF] := A;
    End;
  End;
  If OptT Then OptD := True;
  If NF = 0 Then
  Begin
    If SysIsATty(0) And Not OptD Then
    Begin
      SysPut(2, Msg(1) + #10);
      SysExit(1);
    End;
    OptC := True;
    Process('', True);
  End
  Else
    For I := 1 To NF Do
      If OptL Then ListFile(Names[I])
      Else Process(Names[I], False);
  SysExit(Rc);
END.
