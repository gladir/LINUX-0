{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2026
  @website(https://www.gladir.com/linux-0)
  @abstract(Target: Turbo Pascal 7, Free Pascal 3.2)
}

Program GZIP(Input,Output);

Uses DOS;

Const
  MaxFiles=16;
  InputBufferSize=2048;
  OutputBufferSize=2048;
  CompressBlockSize=1024;
  HashSize=2048;
  WindowSize=32768;
  MaxHuffmanSymbols=288;
  MaxHuffmanBits=15;

Type
  TFileName=String[127];
  TFileArray=Array[1..MaxFiles]Of TFileName;
  TInputBuffer=Array[0..InputBufferSize-1]Of Byte;
  TOutputBuffer=Array[0..OutputBufferSize-1]Of Byte;
  TCompressBuffer=Array[0..CompressBlockSize-1]Of Byte;
  TMatchHeads=Array[0..HashSize-1]Of Integer;
  TPreviousMatch=Array[0..CompressBlockSize-1]Of Integer;
  THistory=Array[0..WindowSize-1]Of Byte;
  TCodeLengths=Array[0..MaxHuffmanSymbols-1]Of Byte;
  TCodeCounts=Array[0..MaxHuffmanBits]Of Word;
  TCodeSymbols=Array[0..MaxHuffmanSymbols-1]Of Word;
  THuffmanTree=Record
    Counts:TCodeCounts;
    Symbols:TCodeSymbols;
    MaxLength,SymbolCount:Integer;
  End;

Var
  SourceFile,DestFile:File;
  FileNames:TFileArray;
  InputBuffer:TInputBuffer;
  OutputBuffer:TOutputBuffer;
  CompressBuffer:TCompressBuffer;
  MatchHeads:TMatchHeads;
  PreviousMatch:TPreviousMatch;
  History:THistory;
  LiteralLengths,DistanceLengths:TCodeLengths;
  LiteralTree,DistanceTree,CodeTree:THuffmanTree;
  SourceName,DestName,Suffix,Argument,LanguageCode,HeaderFileName:String;
  FileCount,ArgumentIndex,FileIndex,SearchLimit:Integer;
  InputLength,InputPosition,InputReadCount:Word;
  OutputPosition,WriteCount:Word;
  BitByte,BitCount,OutBitByte,OutBitCount:Byte;
  WindowPosition:Integer;
  WindowValid:LongInt;
  MemberCRC,StoredCRC,StoredSize,MemberSize,TotalOutput:LongInt;
  GzipTime,CompressedInputSize,TotalInflated:LongInt;
  CompressedSize,TotalInput:LongInt;
  CompressionLevel,BlockCount:Integer;
  StdoutMode,ForceMode,VerboseMode,QuietMode,DecompressMode:Boolean;
  TestMode,ListMode,RecursiveMode,SaveName,EndOptions:Boolean;
  InputEOF,InputError,DecodeError,OutputError,ErrorFound:Boolean;

Function BuildHuffmanTree(Var Tree:THuffmanTree;
                          Var Lengths:TCodeLengths;
                          SymbolLimit:Integer):Boolean;Forward;

Procedure ReportError(Const MessageText:String);
Begin
  If Not QuietMode Then WriteLn('gzip: ',SourceName,': ',MessageText);
  ErrorFound:=True;
End;

Procedure OptionError(Const MessageText:String);
Begin
  WriteLn('gzip: ',MessageText);
  Halt(2);
End;

Procedure PrintHelp;
Begin
  If Copy(LanguageCode,1,2)='EN'Then Begin
    WriteLn('GZIP : Compress or decompress files in gzip format.');
    WriteLn('Syntax: gzip [-acdfhlLnNrtvV19] [-S suffix] [file ...]');
    WriteLn(' -1..-9, --fast, --best  Set compression effort');
    WriteLn(' -c, --stdout            Write to standard output');
    WriteLn(' -d, --decompress        Decompress');
    WriteLn(' -f, --force             Overwrite existing output files');
    WriteLn(' -l, --list              List compressed file information');
    WriteLn(' -n, --no-name           Do not save original name');
    WriteLn(' -N, --name              Save original name in the gzip header');
    WriteLn(' -q, --quiet             Suppress warnings');
    WriteLn(' -r, --recursive         Accept recursive traversal request');
    WriteLn(' -S, --suffix SUFFIX     Set the gzip suffix');
    WriteLn(' -t, --test              Test compressed file integrity');
    WriteLn(' -v, --verbose           Report compression ratio');
    WriteLn(' -h, --help; -L, --license; -V, --version');
    WriteLn('Native encoder uses LZ77 and fixed-Huffman DEFLATE blocks.');
  End Else Begin
    WriteLn('GZIP : Cette commande permet de compresser et d'+#130+'compresser des fichiers au format gzip.');
    WriteLn;
    WriteLn('Syntaxe : gzip [-acdfhlLnNrtvV19] [-S suffixe] [fichier ...]');
    WriteLn;
    WriteLn(' -1..-9, --fast, --best  Regler le niveau de compression');
    WriteLn(' -c, --stdout            Ecrire vers la sortie standard');
    WriteLn(' -d, --decompress        Decompresser');
    WriteLn(' -f, --force             Ecraser les fichiers de sortie');
    WriteLn(' -l, --list              Afficher les informations du fichier');
    WriteLn(' -n, --no-name           Ne pas sauvegarder le nom original');
    WriteLn(' -N, --name              Sauvegarder le nom original');
    WriteLn(' -q, --quiet             Supprimer les avertissements');
    WriteLn(' -r, --recursive         Demander le parcours recursif');
    WriteLn(' -S, --suffix SUFFIXE    Definir le suffixe gzip');
    WriteLn(' -t, --test              Verifier l''integrite du fichier');
    WriteLn(' -v, --verbose           Afficher le taux de compression');
    WriteLn(' -h, --help; -L, --license; -V, --version');
    WriteLn('Le compresseur natif utilise LZ77 et DEFLATE a Huffman fixe.');
  End;
End;

Procedure PrintLicense;
Begin
  WriteLn('GZIP (LINUX-0)');
  WriteLn('Implementation native Pascal, sans programme externe.');
  WriteLn('Voir le fichier LICENSE du depot pour les conditions applicables.');
End;

Function FileExistsTP(Const Name:String):Boolean;
Var
  Search:SearchRec;
Begin
  FindFirst(Name,AnyFile,Search);
  FileExistsTP:=(DosError=0)and((Search.Attr and Directory)=0);
  {$IFDEF FPC}FindClose(Search);{$ENDIF}
End;

Function DeleteFileTP(Const Name:String):Boolean;
Var
  FileToDelete:File;
  DeleteOK:Boolean;
Begin
  Assign(FileToDelete,Name);
  {$I-}Erase(FileToDelete);{$I+}
  DeleteOK:=IOResult=0;
  DeleteFileTP:=DeleteOK;
  If Not DeleteOK Then ReportError('impossible de supprimer '+Name);
End;

Function ReadInputByte(Var Value:Byte):Boolean;
Begin
  If InputPosition>=InputLength Then Begin
    {$I-}BlockRead(SourceFile,InputBuffer,SizeOf(InputBuffer),InputReadCount);{$I+}
    If IOResult<>0 Then Begin
      InputError:=True;
      ReadInputByte:=False;
      Exit;
    End;
    InputLength:=InputReadCount;
    InputPosition:=0;
    If InputLength=0 Then Begin
      InputEOF:=True;
      ReadInputByte:=False;
      Exit;
    End;
  End;
  Value:=InputBuffer[InputPosition];
  Inc(InputPosition);
  ReadInputByte:=True;
End;

Procedure FlushOutputBuffer;
Begin
  If OutputPosition=0 Then Exit;
  {$I-}BlockWrite(DestFile,OutputBuffer,OutputPosition,WriteCount);{$I+}
  If(IOResult<>0)or(WriteCount<>OutputPosition)Then OutputError:=True;
  OutputPosition:=0;
End;

Procedure WriteRawByte(Value:Byte);
Begin
  Inc(TotalOutput);
  If StdoutMode Then Write(Output,Chr(Value)) Else Begin
    OutputBuffer[OutputPosition]:=Value;
    Inc(OutputPosition);
    If OutputPosition=OutputBufferSize Then FlushOutputBuffer;
  End;
End;

Procedure WriteRawWord(Value:Word);
Begin
  WriteRawByte(Byte(Value and 255));
  WriteRawByte(Byte((Value shr 8)and 255));
End;

Procedure WriteRawLong(Value:LongInt);
Begin
  {$Q-}
  WriteRawByte(Byte(Value and 255));
  WriteRawByte(Byte((Value shr 8)and 255));
  WriteRawByte(Byte((Value shr 16)and 255));
  WriteRawByte(Byte((Value shr 24)and 255));
  {$Q+}
End;

Procedure WriteBits(Value:LongInt; Count:Integer);
Var
  Index:Integer;
Begin
  For Index:=0 to Count-1 Do Begin
    If(Value and(LongInt(1)shl Index))<>0 Then
      OutBitByte:=OutBitByte or(1 shl OutBitCount);
    Inc(OutBitCount);
    If OutBitCount=8 Then Begin
      WriteRawByte(OutBitByte);
      OutBitByte:=0;
      OutBitCount:=0;
    End;
  End;
End;

Procedure FlushBits;
Begin
  If OutBitCount>0 Then Begin
    WriteRawByte(OutBitByte);
    OutBitByte:=0;
    OutBitCount:=0;
  End;
End;

Function ReverseBits(Value,Count:Integer):Integer;
Var
  Index,Reversed:Integer;
Begin
  Reversed:=0;
  For Index:=1 to Count Do Begin
    Reversed:=(Reversed shl 1)or(Value and 1);
    Value:=Value shr 1;
  End;
  ReverseBits:=Reversed;
End;

Procedure WriteFixedSymbol(Symbol:Integer);
Var
  Code,Count:Integer;
Begin
  If Symbol<=143 Then Begin
    Code:=$30+Symbol;
    Count:=8;
  End Else If Symbol<=255 Then Begin
    Code:=$190+Symbol-144;
    Count:=9;
  End Else If Symbol<=279 Then Begin
    Code:=Symbol-256;
    Count:=7;
  End Else Begin
    Code:=$C0+Symbol-280;
    Count:=8;
  End;
  WriteBits(ReverseBits(Code,Count),Count);
End;

Function LengthBase(Code:Integer):Integer;
Begin
  Case Code Of
    257:LengthBase:=3; 258:LengthBase:=4; 259:LengthBase:=5;
    260:LengthBase:=6; 261:LengthBase:=7; 262:LengthBase:=8;
    263:LengthBase:=9; 264:LengthBase:=10; 265:LengthBase:=11;
    266:LengthBase:=13; 267:LengthBase:=15; 268:LengthBase:=17;
    269:LengthBase:=19; 270:LengthBase:=23; 271:LengthBase:=27;
    272:LengthBase:=31; 273:LengthBase:=35; 274:LengthBase:=43;
    275:LengthBase:=51; 276:LengthBase:=59; 277:LengthBase:=67;
    278:LengthBase:=83; 279:LengthBase:=99; 280:LengthBase:=115;
    281:LengthBase:=131; 282:LengthBase:=163; 283:LengthBase:=195;
    284:LengthBase:=227; 285:LengthBase:=258;
  Else LengthBase:=0;
  End;
End;

Function LengthExtra(Code:Integer):Integer;
Begin
  Case Code Of
    265..268:LengthExtra:=1; 269..272:LengthExtra:=2;
    273..276:LengthExtra:=3; 277..280:LengthExtra:=4;
    281..284:LengthExtra:=5;
  Else LengthExtra:=0;
  End;
End;

Function DistanceBase(Code:Integer):LongInt;
Begin
  Case Code Of
    0:DistanceBase:=1; 1:DistanceBase:=2; 2:DistanceBase:=3;
    3:DistanceBase:=4; 4:DistanceBase:=5; 5:DistanceBase:=7;
    6:DistanceBase:=9; 7:DistanceBase:=13; 8:DistanceBase:=17;
    9:DistanceBase:=25; 10:DistanceBase:=33; 11:DistanceBase:=49;
    12:DistanceBase:=65; 13:DistanceBase:=97; 14:DistanceBase:=129;
    15:DistanceBase:=193; 16:DistanceBase:=257; 17:DistanceBase:=385;
    18:DistanceBase:=513; 19:DistanceBase:=769; 20:DistanceBase:=1025;
    21:DistanceBase:=1537; 22:DistanceBase:=2049; 23:DistanceBase:=3073;
    24:DistanceBase:=4097; 25:DistanceBase:=6145; 26:DistanceBase:=8193;
    27:DistanceBase:=12289; 28:DistanceBase:=16385; 29:DistanceBase:=24577;
  Else DistanceBase:=0;
  End;
End;

Function DistanceExtra(Code:Integer):Integer;
Begin
  If Code<4 Then DistanceExtra:=0 Else DistanceExtra:=(Code div 2)-1;
End;

Procedure WriteMatch(LengthValue,DistanceValue:Integer);
Var
  Code,Extra,DistanceCode,DistanceBits:Integer;
Begin
  Code:=257;
  While Code<285 Do Begin
    Extra:=LengthExtra(Code);
    If LengthValue<LengthBase(Code)+(1 shl Extra)Then Break;
    Inc(Code);
  End;
  WriteFixedSymbol(Code);
  Extra:=LengthExtra(Code);
  If Extra>0 Then WriteBits(LengthValue-LengthBase(Code),Extra);
  DistanceCode:=0;
  While DistanceCode<29 Do Begin
    Extra:=DistanceExtra(DistanceCode);
    If DistanceValue<DistanceBase(DistanceCode)+(1 shl Extra)Then Break;
    Inc(DistanceCode);
  End;
  DistanceBits:=ReverseBits(DistanceCode,5);
  WriteBits(DistanceBits,5);
  Extra:=DistanceExtra(DistanceCode);
  If Extra>0 Then WriteBits(DistanceValue-DistanceBase(DistanceCode),Extra);
End;

Function MatchHash(Position:Integer):Integer;
Begin
  MatchHash:=(CompressBuffer[Position]*251+
              CompressBuffer[Position+1]*31+
              CompressBuffer[Position+2])mod HashSize;
End;

Procedure InsertPosition(Position,BlockLength:Integer);
Var
  HashValue:Integer;
Begin
  If Position+2>=BlockLength Then Exit;
  HashValue:=MatchHash(Position);
  PreviousMatch[Position]:=MatchHeads[HashValue];
  MatchHeads[HashValue]:=Position;
End;

Procedure FindMatch(Position,BlockLength:Integer;
                    Var MatchLength,MatchDistance:Integer);
Var
  Candidate,Probe,Limit,CurrentLength:Integer;
  HashValue:Integer;
Begin
  MatchLength:=0;
  MatchDistance:=0;
  If Position+2>=BlockLength Then Exit;
  HashValue:=MatchHash(Position);
  Candidate:=MatchHeads[HashValue];
  Limit:=BlockLength-Position;
  If Limit>258 Then Limit:=258;
  Probe:=0;
  While(Candidate>=0)and(Probe<SearchLimit)Do Begin
    If Candidate>=Position Then Break;
    If Position-Candidate>WindowSize Then Break;
    CurrentLength:=0;
    While(CurrentLength<Limit)and
      (CompressBuffer[Candidate+CurrentLength]=
       CompressBuffer[Position+CurrentLength])Do Inc(CurrentLength);
    If CurrentLength>MatchLength Then Begin
      MatchLength:=CurrentLength;
      MatchDistance:=Position-Candidate;
      If MatchLength=Limit Then Exit;
    End;
    Candidate:=PreviousMatch[Candidate];
    Inc(Probe);
  End;
  If MatchLength<3 Then Begin
    MatchLength:=0;
    MatchDistance:=0;
  End;
End;

Procedure EncodeFixedBlock(BlockLength:Integer; IsFinal:Boolean);
Var
  Position,MatchLength,MatchDistance,Index:Integer;
Begin
  If IsFinal Then WriteBits(1,1)Else WriteBits(0,1);
  WriteBits(1,2);
  For Index:=0 to HashSize-1 Do MatchHeads[Index]:=-1;
  For Index:=0 to BlockLength-1 Do PreviousMatch[Index]:=-1;
  Position:=0;
  While Position<BlockLength Do Begin
    FindMatch(Position,BlockLength,MatchLength,MatchDistance);
    If MatchLength>=3 Then Begin
      WriteMatch(MatchLength,MatchDistance);
      For Index:=Position to Position+MatchLength-1 Do
        InsertPosition(Index,BlockLength);
      Inc(Position,MatchLength);
    End Else Begin
      WriteFixedSymbol(CompressBuffer[Position]);
      InsertPosition(Position,BlockLength);
      Inc(Position);
    End;
  End;
  WriteFixedSymbol(256);
End;

Function ReadBits(Count:Integer):LongInt;
Var
  Index:Integer;
  ResultValue:LongInt;
Begin
  ResultValue:=0;
  For Index:=0 to Count-1 Do Begin
    If BitCount=0 Then Begin
      If Not ReadInputByte(BitByte)Then Begin
        DecodeError:=True;
        ReadBits:=ResultValue;
        Exit;
      End;
      BitCount:=8;
    End;
    If(BitByte and 1)<>0 Then
      ResultValue:=ResultValue or(LongInt(1)shl Index);
    BitByte:=BitByte shr 1;
    Dec(BitCount);
  End;
  ReadBits:=ResultValue;
End;

Function ReadAlignedByte(Var Value:Byte):Boolean;
Begin
  BitCount:=0;
  ReadAlignedByte:=ReadInputByte(Value);
End;

Function ReadLittleWord(Var Value:Word):Boolean;
Var
  LowByte,HighByte:Byte;
Begin
  If Not ReadAlignedByte(LowByte)Then Begin
    ReadLittleWord:=False;
    Exit;
  End;
  If Not ReadAlignedByte(HighByte)Then Begin
    ReadLittleWord:=False;
    Exit;
  End;
  Value:=LowByte or(Word(HighByte)shl 8);
  ReadLittleWord:=True;
End;

Function ReadLittleLong(Var Value:LongInt):Boolean;
Var
  Byte0,Byte1,Byte2,Byte3:Byte;
Begin
  If Not ReadAlignedByte(Byte0)Then Begin ReadLittleLong:=False; Exit; End;
  If Not ReadAlignedByte(Byte1)Then Begin ReadLittleLong:=False; Exit; End;
  If Not ReadAlignedByte(Byte2)Then Begin ReadLittleLong:=False; Exit; End;
  If Not ReadAlignedByte(Byte3)Then Begin ReadLittleLong:=False; Exit; End;
  {$Q-}
  Value:=LongInt(Byte0)or(LongInt(Byte1)shl 8)or
         (LongInt(Byte2)shl 16)or(LongInt(Byte3)shl 24);
  {$Q+}
  ReadLittleLong:=True;
End;

Procedure BuildFixedTrees;
Var
  Symbol:Integer;
Begin
  For Symbol:=0 to MaxHuffmanSymbols-1 Do LiteralLengths[Symbol]:=0;
  For Symbol:=0 to 143 Do LiteralLengths[Symbol]:=8;
  For Symbol:=144 to 255 Do LiteralLengths[Symbol]:=9;
  For Symbol:=256 to 279 Do LiteralLengths[Symbol]:=7;
  For Symbol:=280 to 287 Do LiteralLengths[Symbol]:=8;
  For Symbol:=0 to 31 Do DistanceLengths[Symbol]:=5;
  BuildHuffmanTree(LiteralTree,LiteralLengths,288);
  BuildHuffmanTree(DistanceTree,DistanceLengths,32);
End;

Function BuildHuffmanTree(Var Tree:THuffmanTree;
                          Var Lengths:TCodeLengths;
                          SymbolLimit:Integer):Boolean;
Var
  Bits,Symbol,Index:Integer;
  Left:LongInt;
Begin
  For Bits:=0 to MaxHuffmanBits Do Tree.Counts[Bits]:=0;
  Tree.SymbolCount:=0;
  Tree.MaxLength:=0;
  For Symbol:=0 to SymbolLimit-1 Do Begin
    If Lengths[Symbol]>MaxHuffmanBits Then Begin
      BuildHuffmanTree:=False;
      Exit;
    End;
    If Lengths[Symbol]>0 Then Begin
      Inc(Tree.Counts[Lengths[Symbol]]);
      Inc(Tree.SymbolCount);
      If Lengths[Symbol]>Tree.MaxLength Then Tree.MaxLength:=Lengths[Symbol];
    End;
  End;
  If Tree.SymbolCount=0 Then Begin BuildHuffmanTree:=False; Exit; End;
  Left:=1;
  For Bits:=1 to MaxHuffmanBits Do Begin
    Left:=(Left shl 1)-Tree.Counts[Bits];
    If Left<0 Then Begin BuildHuffmanTree:=False; Exit; End;
  End;
  Tree.Counts[0]:=0;
  Index:=0;
  For Bits:=1 to MaxHuffmanBits Do
    For Symbol:=0 to SymbolLimit-1 Do
      If Lengths[Symbol]=Bits Then Begin
        Tree.Symbols[Index]:=Symbol;
        Inc(Index);
      End;
  BuildHuffmanTree:=True;
End;

Function DecodeSymbol(Var Tree:THuffmanTree):Integer;
Var
  Code,First,Index,Count,LengthIndex,SymbolIndex:LongInt;
Begin
  Code:=0; First:=0; Index:=0;
  For LengthIndex:=1 to Tree.MaxLength Do Begin
    Code:=(Code shl 1)or ReadBits(1);
    If DecodeError Then Begin DecodeSymbol:=-1; Exit; End;
    Count:=Tree.Counts[LengthIndex];
    If(Code>=First)and(Code<First+Count)Then Begin
      SymbolIndex:=Index+Code-First;
      DecodeSymbol:=Tree.Symbols[SymbolIndex];
      Exit;
    End;
    Inc(Index,Count);
    First:=(First+Count)shl 1;
  End;
  DecodeError:=True;
  DecodeSymbol:=-1;
End;

Procedure UpdateCRC(Value:Byte);
Var
  Index:Integer;
Begin
  {$Q-}
  MemberCRC:=MemberCRC xor Value;
  For Index:=1 to 8 Do Begin
    If(MemberCRC and 1)<>0 Then
      MemberCRC:=(MemberCRC shr 1)xor LongInt($EDB88320)
    Else MemberCRC:=MemberCRC shr 1;
  End;
  {$Q+}
End;

Procedure WriteDecodedByte(Value:Byte);
Begin
  If Not TestMode and Not ListMode Then WriteRawByte(Value);
  History[WindowPosition]:=Value;
  If WindowPosition=WindowSize-1 Then WindowPosition:=0
  Else Inc(WindowPosition);
  If WindowValid<WindowSize Then Inc(WindowValid);
  {$Q-}
  Inc(MemberSize);
  Inc(TotalInflated);
  {$Q+}
  UpdateCRC(Value);
End;

Function DecodeSymbolLengthBase(Code:Integer):Integer;
Begin
  Case Code Of
    257:DecodeSymbolLengthBase:=3; 258:DecodeSymbolLengthBase:=4;
    259:DecodeSymbolLengthBase:=5; 260:DecodeSymbolLengthBase:=6;
    261:DecodeSymbolLengthBase:=7; 262:DecodeSymbolLengthBase:=8;
    263:DecodeSymbolLengthBase:=9; 264:DecodeSymbolLengthBase:=10;
    265:DecodeSymbolLengthBase:=11; 266:DecodeSymbolLengthBase:=13;
    267:DecodeSymbolLengthBase:=15; 268:DecodeSymbolLengthBase:=17;
    269:DecodeSymbolLengthBase:=19; 270:DecodeSymbolLengthBase:=23;
    271:DecodeSymbolLengthBase:=27; 272:DecodeSymbolLengthBase:=31;
    273:DecodeSymbolLengthBase:=35; 274:DecodeSymbolLengthBase:=43;
    275:DecodeSymbolLengthBase:=51; 276:DecodeSymbolLengthBase:=59;
    277:DecodeSymbolLengthBase:=67; 278:DecodeSymbolLengthBase:=83;
    279:DecodeSymbolLengthBase:=99; 280:DecodeSymbolLengthBase:=115;
    281:DecodeSymbolLengthBase:=131; 282:DecodeSymbolLengthBase:=163;
    283:DecodeSymbolLengthBase:=195; 284:DecodeSymbolLengthBase:=227;
    285:DecodeSymbolLengthBase:=258;
  Else DecodeSymbolLengthBase:=0;
  End;
End;

Function DecodeSymbolLengthExtra(Code:Integer):Integer;
Begin
  Case Code Of
    265..268:DecodeSymbolLengthExtra:=1;
    269..272:DecodeSymbolLengthExtra:=2;
    273..276:DecodeSymbolLengthExtra:=3;
    277..280:DecodeSymbolLengthExtra:=4;
    281..284:DecodeSymbolLengthExtra:=5;
  Else DecodeSymbolLengthExtra:=0;
  End;
End;

Function DecodeDistanceBase(Code:Integer):LongInt;
Begin
  Case Code Of
    0:DecodeDistanceBase:=1; 1:DecodeDistanceBase:=2;
    2:DecodeDistanceBase:=3; 3:DecodeDistanceBase:=4;
    4:DecodeDistanceBase:=5; 5:DecodeDistanceBase:=7;
    6:DecodeDistanceBase:=9; 7:DecodeDistanceBase:=13;
    8:DecodeDistanceBase:=17; 9:DecodeDistanceBase:=25;
    10:DecodeDistanceBase:=33; 11:DecodeDistanceBase:=49;
    12:DecodeDistanceBase:=65; 13:DecodeDistanceBase:=97;
    14:DecodeDistanceBase:=129; 15:DecodeDistanceBase:=193;
    16:DecodeDistanceBase:=257; 17:DecodeDistanceBase:=385;
    18:DecodeDistanceBase:=513; 19:DecodeDistanceBase:=769;
    20:DecodeDistanceBase:=1025; 21:DecodeDistanceBase:=1537;
    22:DecodeDistanceBase:=2049; 23:DecodeDistanceBase:=3073;
    24:DecodeDistanceBase:=4097; 25:DecodeDistanceBase:=6145;
    26:DecodeDistanceBase:=8193; 27:DecodeDistanceBase:=12289;
    28:DecodeDistanceBase:=16385; 29:DecodeDistanceBase:=24577;
  Else DecodeDistanceBase:=0;
  End;
End;

Function DecodeDistanceExtra(Code:Integer):Integer;
Begin
  If Code<4 Then DecodeDistanceExtra:=0
  Else DecodeDistanceExtra:=(Code div 2)-1;
End;

Function DecodeCompressedBlock:Boolean;
Var
  Symbol,LengthValue,DistanceCode,CopyIndex:Integer;
  DistanceValue,SourcePosition:LongInt;
  Value:Byte;
Begin
  DecodeCompressedBlock:=False;
  Repeat
    Symbol:=DecodeSymbol(LiteralTree);
    If DecodeError Then Exit;
    If Symbol<256 Then WriteDecodedByte(Byte(Symbol))
    Else If Symbol=256 Then Begin DecodeCompressedBlock:=True; Exit; End
    Else Begin
      If(Symbol<257)or(Symbol>285)Then Exit;
      LengthValue:=DecodeSymbolLengthBase(Symbol)+
                   ReadBits(DecodeSymbolLengthExtra(Symbol));
      DistanceCode:=DecodeSymbol(DistanceTree);
      If DecodeError or(DistanceCode<0)or(DistanceCode>29)Then Exit;
      DistanceValue:=DecodeDistanceBase(DistanceCode)+
                     ReadBits(DecodeDistanceExtra(DistanceCode));
      If DecodeError or(DistanceValue<1)or(DistanceValue>WindowValid)Then Exit;
      For CopyIndex:=1 to LengthValue Do Begin
        SourcePosition:=(LongInt(WindowPosition)-DistanceValue+WindowSize)
                         and(WindowSize-1);
        Value:=History[SourcePosition];
        WriteDecodedByte(Value);
      End;
    End;
  Until DecodeError;
End;

Function DecodeDynamicTrees:Boolean;
Const
  CodeOrder:Array[0..18]Of Byte=
    (16,17,18,0,8,7,9,6,10,5,11,4,12,3,13,2,14,1,15);
Var
  LiteralCount,DistanceCount,CodeCount:Integer;
  Index,Symbol,RepeatCount,PreviousLength:Integer;
  CodeLengthLengths:TCodeLengths;
Begin
  DecodeDynamicTrees:=False;
  LiteralCount:=ReadBits(5)+257;
  DistanceCount:=ReadBits(5)+1;
  CodeCount:=ReadBits(4)+4;
  If DecodeError or(LiteralCount>286)or(DistanceCount>32)Then Exit;
  For Index:=0 to 18 Do CodeLengthLengths[Index]:=0;
  For Index:=0 to CodeCount-1 Do
    CodeLengthLengths[CodeOrder[Index]]:=ReadBits(3);
  If DecodeError or Not BuildHuffmanTree(CodeTree,CodeLengthLengths,19)Then Exit;
  For Index:=0 to MaxHuffmanSymbols-1 Do LiteralLengths[Index]:=0;
  For Index:=0 to MaxHuffmanSymbols-1 Do DistanceLengths[Index]:=0;
  Index:=0;
  While Index<LiteralCount+DistanceCount Do Begin
    Symbol:=DecodeSymbol(CodeTree);
    If DecodeError Then Exit;
    If Symbol<=15 Then Begin
      If Index<LiteralCount Then LiteralLengths[Index]:=Symbol
      Else DistanceLengths[Index-LiteralCount]:=Symbol;
      Inc(Index);
    End Else Begin
      If Symbol=16 Then Begin
        If Index=0 Then Exit;
        RepeatCount:=ReadBits(2)+3;
        If Index<LiteralCount Then PreviousLength:=LiteralLengths[Index-1]
        Else If Index=LiteralCount Then PreviousLength:=LiteralLengths[LiteralCount-1]
        Else PreviousLength:=DistanceLengths[Index-LiteralCount-1];
      End Else If Symbol=17 Then Begin
        RepeatCount:=ReadBits(3)+3; PreviousLength:=0;
      End Else If Symbol=18 Then Begin
        RepeatCount:=ReadBits(7)+11; PreviousLength:=0;
      End Else Exit;
      If DecodeError or(RepeatCount>LiteralCount+DistanceCount-Index)Then Exit;
      While RepeatCount>0 Do Begin
        If Index<LiteralCount Then LiteralLengths[Index]:=PreviousLength
        Else DistanceLengths[Index-LiteralCount]:=PreviousLength;
        Inc(Index); Dec(RepeatCount);
      End;
    End;
  End;
  If LiteralLengths[256]=0 Then Exit;
  If Not BuildHuffmanTree(LiteralTree,LiteralLengths,LiteralCount)Then Exit;
  If Not BuildHuffmanTree(DistanceTree,DistanceLengths,DistanceCount)Then Exit;
  DecodeDynamicTrees:=True;
End;

Function InflateDeflate:Boolean;
Var
  FinalBlock,BlockDone:Boolean;
  BlockType:Integer;
  BlockLength,Complement:Word;
  StoredValue:Byte;
  Index:LongInt;
Begin
  InflateDeflate:=False; FinalBlock:=False;
  While Not FinalBlock Do Begin
    FinalBlock:=ReadBits(1)<>0;
    BlockType:=ReadBits(2);
    If DecodeError Then Exit;
    Case BlockType Of
      0:Begin
        BitCount:=0;
        If Not ReadLittleWord(BlockLength)Then Exit;
        If Not ReadLittleWord(Complement)Then Exit;
        If(BlockLength xor Complement)<>65535 Then Exit;
        For Index:=1 to BlockLength Do Begin
          If Not ReadAlignedByte(StoredValue)Then Exit;
          WriteDecodedByte(StoredValue);
        End;
      End;
      1:Begin
        BuildFixedTrees;
        BlockDone:=DecodeCompressedBlock;
        If Not BlockDone Then Exit;
      End;
      2:Begin
        If Not DecodeDynamicTrees Then Exit;
        BlockDone:=DecodeCompressedBlock;
        If Not BlockDone Then Exit;
      End;
    Else Exit;
    End;
  End;
  InflateDeflate:=Not DecodeError;
End;

Procedure WriteGzipHeader(Const Name:String);
Var
  Index:Integer;
  StoredName:String;
Begin
  WriteRawByte(31); WriteRawByte(139); WriteRawByte(8);
  If SaveName Then WriteRawByte(8)Else WriteRawByte(0);
  If SaveName Then WriteRawLong(GzipTime)Else WriteRawLong(0);
  If CompressionLevel=1 Then WriteRawByte(4)
  Else If CompressionLevel=9 Then WriteRawByte(2)
  Else WriteRawByte(0);
  WriteRawByte(255);
  If SaveName Then Begin
    StoredName:=Name;
    For Index:=1 to Length(Name)Do
      If(Name[Index]='\')or(Name[Index]='/')Then
        StoredName:=Copy(Name,Index+1,255);
    For Index:=1 to Length(StoredName)Do WriteRawByte(Ord(StoredName[Index]));
    WriteRawByte(0);
  End;
End;

Function BaseName(Const Name:String):String;
Var
  Index:Integer;
Begin
  BaseName:=Name;
  For Index:=1 to Length(Name)Do
    If(Name[Index]='\')or(Name[Index]='/')Then
      BaseName:=Copy(Name,Index+1,255);
End;

Function DosDateTimeToUnix(PackedTime:LongInt):LongInt;
Var
  YearValue,MonthValue,DayValue,HourValue,MinuteValue,SecondValue:Integer;
  YearIndex,MonthIndex:Integer;
  Days:LongInt;
Begin
  YearValue:=1980+((PackedTime shr 25)and 127);
  MonthValue:=(PackedTime shr 21)and 15;
  DayValue:=(PackedTime shr 16)and 31;
  HourValue:=(PackedTime shr 11)and 31;
  MinuteValue:=(PackedTime shr 5)and 63;
  SecondValue:=(PackedTime and 31)*2;
  Days:=0;
  For YearIndex:=1970 to YearValue-1 Do Begin
    Inc(Days,365);
    If(YearIndex mod 4=0)and((YearIndex mod 100<>0)or(YearIndex mod 400=0))Then
      Inc(Days);
  End;
  For MonthIndex:=1 to MonthValue-1 Do Begin
    Case MonthIndex Of
      4,6,9,11:Inc(Days,30);
      2:Begin
        Inc(Days,28);
        If(YearValue mod 4=0)and
          ((YearValue mod 100<>0)or(YearValue mod 400=0))Then Inc(Days);
      End;
    Else Inc(Days,31);
    End;
  End;
  Inc(Days,DayValue-1);
  DosDateTimeToUnix:=(((Days*24+HourValue)*60+MinuteValue)*60)+SecondValue;
End;

Procedure WriteGzipTrailer;
Begin
  FlushBits;
  WriteRawLong(MemberCRC xor LongInt($FFFFFFFF));
  WriteRawLong(MemberSize);
End;

Function CompressionHash(Position,BlockLength:Integer):Integer;
Begin
  CompressionHash:=(CompressBuffer[Position]*251+
    CompressBuffer[Position+1]*31+CompressBuffer[Position+2])mod HashSize;
End;

Function CountMatch(Position,Candidate,Limit:Integer):Integer;
Var
  Count:Integer;
Begin
  Count:=0;
  While(Count<Limit)and
    (CompressBuffer[Candidate+Count]=CompressBuffer[Position+Count])Do
    Inc(Count);
  CountMatch:=Count;
End;

Procedure FindCompressionMatch(Position,BlockLength:Integer;
                               Var BestLength,BestDistance:Integer);
Var
  HashValue,Candidate,Probe,Limit,CurrentLength:Integer;
Begin
  BestLength:=0; BestDistance:=0;
  If Position+2>=BlockLength Then Exit;
  HashValue:=CompressionHash(Position,BlockLength);
  Candidate:=MatchHeads[HashValue];
  Limit:=BlockLength-Position;
  If Limit>258 Then Limit:=258;
  Probe:=0;
  While(Candidate>=0)and(Probe<SearchLimit)Do Begin
    If Candidate>=Position Then Break;
    CurrentLength:=CountMatch(Position,Candidate,Limit);
    If CurrentLength>BestLength Then Begin
      BestLength:=CurrentLength;
      BestDistance:=Position-Candidate;
      If BestLength=Limit Then Exit;
    End;
    Candidate:=PreviousMatch[Candidate];
    Inc(Probe);
  End;
  If BestLength<3 Then Begin BestLength:=0; BestDistance:=0; End;
End;

Procedure InsertCompressionPosition(Position,BlockLength:Integer);
Var
  HashValue:Integer;
Begin
  If Position+2>=BlockLength Then Exit;
  HashValue:=CompressionHash(Position,BlockLength);
  PreviousMatch[Position]:=MatchHeads[HashValue];
  MatchHeads[HashValue]:=Position;
End;

Procedure EncodeCompressionBlock(BlockLength:Integer; IsFinal:Boolean);
Var
  Index,Position,MatchLength,MatchDistance:Integer;
Begin
  If IsFinal Then WriteBits(1,1)Else WriteBits(0,1);
  WriteBits(1,2);
  For Index:=0 to HashSize-1 Do MatchHeads[Index]:=-1;
  For Index:=0 to CompressBlockSize-1 Do PreviousMatch[Index]:=-1;
  Position:=0;
  While Position<BlockLength Do Begin
    FindCompressionMatch(Position,BlockLength,MatchLength,MatchDistance);
    If MatchLength>=3 Then Begin
      WriteMatch(MatchLength,MatchDistance);
      For Index:=Position to Position+MatchLength-1 Do
        InsertCompressionPosition(Index,BlockLength);
      Inc(Position,MatchLength);
    End Else Begin
      WriteFixedSymbol(CompressBuffer[Position]);
      InsertCompressionPosition(Position,BlockLength);
      Inc(Position);
    End;
  End;
  WriteFixedSymbol(256);
End;

Procedure CompressFile(Const Name:String);
Var
  OutputExists,KeepOriginal:Boolean;
  ReadCount,Index,BlockLength:Integer;
  FileLength:LongInt;
  DosFileTime:LongInt;
  Percent:Integer;
Begin
  SourceName:=Name;
  If(Length(Name)>=Length(Suffix))and
    (Copy(Name,Length(Name)-Length(Suffix)+1,Length(Suffix))=Suffix)Then Begin
    ReportError('le fichier porte deja le suffixe de sortie');
    Exit;
  End;
  Assign(SourceFile,Name);
  FileMode:=0;
  {$I-}Reset(SourceFile,1);{$I+}
  If IOResult<>0 Then Begin ReportError('impossible de lire le fichier'); Exit; End;
  FileLength:=FileSize(SourceFile);
  GzipTime:=0;
  If SaveName Then Begin
    GetFTime(SourceFile,DosFileTime);
    GzipTime:=DosDateTimeToUnix(DosFileTime);
  End;
  DestName:=Name+Suffix;
  If Length(DestName)>127 Then Begin
    Close(SourceFile); ReportError('nom de sortie trop long'); Exit;
  End;
  If DestName=Name Then Begin
    Close(SourceFile); ReportError('le suffixe de sortie correspond au fichier source'); Exit;
  End;
  OutputExists:=FileExistsTP(DestName);
  If OutputExists and Not ForceMode and Not StdoutMode Then Begin
    Close(SourceFile); ReportError('le fichier de sortie existe deja'); Exit;
  End;
  If OutputExists and ForceMode and Not StdoutMode Then
    If Not DeleteFileTP(DestName)Then Begin Close(SourceFile); Exit; End;
  If Not StdoutMode Then Begin
    Assign(DestFile,DestName); FileMode:=1;
    {$I-}Rewrite(DestFile,1);{$I+}
    If IOResult<>0 Then Begin Close(SourceFile); ReportError('impossible de creer la sortie'); Exit; End;
  End;
  TotalOutput:=0; OutputPosition:=0; OutBitByte:=0; OutBitCount:=0;
  MemberCRC:=LongInt($FFFFFFFF); MemberSize:=0;
  WriteGzipHeader(Name);
  BlockCount:=0; TotalInput:=0;
  Repeat
    {$I-}BlockRead(SourceFile,CompressBuffer,CompressBlockSize,ReadCount);{$I+}
    If IOResult<>0 Then Begin OutputError:=True; Break; End;
    BlockLength:=ReadCount;
    For Index:=0 to BlockLength-1 Do Begin
      UpdateCRC(CompressBuffer[Index]);
      {$Q-}Inc(MemberSize);{$Q+}
    End;
    Inc(TotalInput,BlockLength);
    Inc(BlockCount);
    EncodeCompressionBlock(BlockLength,FilePos(SourceFile)>=FileLength);
  Until(BlockLength=0)or(FilePos(SourceFile)>=FileLength);
  If(FileLength=0)and(BlockCount=0)Then EncodeCompressionBlock(0,True);
  WriteGzipTrailer;
  If Not StdoutMode Then Begin
    FlushOutputBuffer;
    Close(DestFile);
  End;
  Close(SourceFile);
  CompressedSize:=TotalOutput;
  If OutputError Then Begin
    If Not StdoutMode Then DeleteFileTP(DestName);
    ReportError('erreur pendant la compression');
    Exit;
  End;
  KeepOriginal:=False;
  If Not ForceMode and(CompressedSize>=FileLength)and Not StdoutMode Then Begin
    DeleteFileTP(DestName);
    KeepOriginal:=True;
  End;
  If Not StdoutMode and Not KeepOriginal Then DeleteFileTP(Name);
  If VerboseMode and Not QuietMode and Not StdoutMode Then Begin
    If FileLength=0 Then Percent:=0
    Else Percent:=Round((FileLength-CompressedSize)*100.0/FileLength);
    WriteLn(Name,': ',Percent,'%');
  End;
End;

Function ReadGzipHeader:Boolean;
Var
  Method,Flags,Value:Byte;
  ExtraLength,Index:Word;
  ExtraIndex:LongInt;
Begin
  ReadGzipHeader:=False;
  HeaderFileName:='';
  If Not ReadAlignedByte(Method)or Not ReadAlignedByte(Flags)Then Exit;
  If(Method<>8)or((Flags and $E0)<>0)Then Exit;
  For Index:=1 to 6 Do If Not ReadAlignedByte(Value)Then Exit;
  If(Flags and 4)<>0 Then Begin
    If Not ReadLittleWord(ExtraLength)Then Exit;
    For ExtraIndex:=1 to ExtraLength Do If Not ReadAlignedByte(Value)Then Exit;
  End;
  If(Flags and 8)<>0 Then Begin
    Repeat
      If Not ReadAlignedByte(Value)Then Exit;
      If(Value<>0)and(Length(HeaderFileName)<255)Then
        HeaderFileName:=HeaderFileName+Chr(Value);
    Until Value=0;
  End;
  If(Flags and 16)<>0 Then Begin
    Repeat If Not ReadAlignedByte(Value)Then Exit Until Value=0;
  End;
  If(Flags and 2)<>0 Then Begin
    If Not ReadAlignedByte(Value)Then Exit;
    If Not ReadAlignedByte(Value)Then Exit;
  End;
  ReadGzipHeader:=True;
End;

Function DecompressMember:Boolean;
Begin
  DecompressMember:=False;
  If Not ReadGzipHeader Then Exit;
  WindowPosition:=0; WindowValid:=0;
  MemberCRC:=LongInt($FFFFFFFF); MemberSize:=0;
  BitCount:=0; DecodeError:=False;
  If Not InflateDeflate Then Exit;
  BitCount:=0;
  If Not ReadLittleLong(StoredCRC)Then Exit;
  If Not ReadLittleLong(StoredSize)Then Exit;
  If(StoredCRC<>(MemberCRC xor LongInt($FFFFFFFF)))or
    (StoredSize<>MemberSize)Then Exit;
  DecompressMember:=True;
End;

Procedure DecompressFile(Const Name:String);
Var
  FirstByte,SecondByte:Byte;
  HasMember:Boolean;
Begin
  SourceName:=Name;
  Assign(SourceFile,Name); FileMode:=0;
  {$I-}Reset(SourceFile,1);{$I+}
  If IOResult<>0 Then Begin ReportError('impossible de lire le fichier'); Exit; End;
  CompressedInputSize:=FileSize(SourceFile);
  InputLength:=0; InputPosition:=0; InputEOF:=False; InputError:=False;
  HasMember:=False; TotalOutput:=0; TotalInflated:=0;
  Repeat
    If Not ReadAlignedByte(FirstByte)Then Break;
    If Not ReadAlignedByte(SecondByte)Then Begin ReportError('entete gzip tronque'); Break; End;
    If(FirstByte<>31)or(SecondByte<>139)Then Begin ReportError('signature gzip invalide'); Break; End;
    If Not DecompressMember Then Begin ReportError('flux DEFLATE ou CRC invalide'); Break; End;
    HasMember:=True;
  Until InputEOF;
  If InputError Then ReportError('erreur de lecture');
  If Not HasMember and Not ErrorFound Then ReportError('fichier gzip vide ou invalide');
  Close(SourceFile);
End;

Procedure ProcessFile(Const Name:String);
Var
  InputName,OutputLabel:String;
  OutputOpened,HadPreviousError:Boolean;
  Percent:Integer;
Begin
  If DecompressMode or TestMode or ListMode Then Begin
    InputName:=Name;
    OutputOpened:=False;
    HadPreviousError:=ErrorFound;
    ErrorFound:=False;
    OutputError:=False;
    OutputPosition:=0;
    If Not StdoutMode and Not TestMode and Not ListMode Then Begin
      If(Length(Name)>=Length(Suffix))and
        (Copy(Name,Length(Name)-Length(Suffix)+1,Length(Suffix))=Suffix)Then
        DestName:=Copy(Name,1,Length(Name)-Length(Suffix))
      Else DestName:=Name+'.out';
      If Length(DestName)>127 Then Begin SourceName:=Name; ReportError('nom de sortie trop long'); Exit; End;
      If FileExistsTP(DestName)Then Begin
        If Not ForceMode Then Begin SourceName:=Name; ReportError('le fichier de sortie existe deja'); Exit; End;
        If Not DeleteFileTP(DestName)Then Exit;
      End;
      Assign(DestFile,DestName); FileMode:=1;
      {$I-}Rewrite(DestFile,1);{$I+}
      If IOResult<>0 Then Begin SourceName:=Name; ReportError('impossible de creer la sortie'); Exit; End;
      OutputOpened:=True;
    End;
    DecompressFile(InputName);
    If OutputOpened Then Begin
      FlushOutputBuffer;
      Close(DestFile);
      If OutputError Then ReportError('erreur pendant la decompression');
      If ErrorFound Then DeleteFileTP(DestName)
      Else DeleteFileTP(Name);
    End;
    If ListMode and Not ErrorFound Then Begin
      If TotalInflated=0 Then Percent:=0
      Else Percent:=Round((TotalInflated-CompressedInputSize)*100.0/TotalInflated);
      OutputLabel:=Name;
      If HeaderFileName<>''Then OutputLabel:=HeaderFileName;
      WriteLn(CompressedInputSize:10,TotalInflated:12,Percent:8,'% ',OutputLabel);
    End;
    ErrorFound:=ErrorFound or HadPreviousError;
  End Else CompressFile(Name);
End;

Procedure ProcessPath(Const Name:String);
Var
  DirectoryEntry:SearchRec;
  Subdirectories:TFileArray;
  DirectoryName,Pattern,ChildName:String;
  SubdirectoryCount,Index:Integer;
  HasGzipSuffix:Boolean;
Begin
  FindFirst(Name,AnyFile,DirectoryEntry);
  If DosError<>0 Then Begin
    SourceName:=Name;
    ReportError('fichier ou repertoire introuvable');
    Exit;
  End;
  If(DirectoryEntry.Attr and Directory)<>0 Then Begin
    {$IFDEF FPC}FindClose(DirectoryEntry);{$ENDIF}
    If Not RecursiveMode Then Begin
      SourceName:=Name;
      ReportError('utilisez -r pour parcourir un repertoire');
      Exit;
    End;
    DirectoryName:=Name;
    If(Length(DirectoryName)>0)and
      not(DirectoryName[Length(DirectoryName)]in['\','/'])Then Begin
      If(Pos('/',DirectoryName)>0)and(Pos('\',DirectoryName)=0)Then
        DirectoryName:=DirectoryName+'/'
      Else DirectoryName:=DirectoryName+'\';
    End;
    Pattern:=DirectoryName+'*.*';
    SubdirectoryCount:=0;
    FindFirst(Pattern,AnyFile,DirectoryEntry);
    While DosError=0 Do Begin
      If(DirectoryEntry.Name<>'.')and(DirectoryEntry.Name<>'..')Then Begin
        ChildName:=DirectoryName+DirectoryEntry.Name;
        If(DirectoryEntry.Attr and Directory)<>0 Then Begin
          If SubdirectoryCount<MaxFiles Then Begin
            Inc(SubdirectoryCount);
            Subdirectories[SubdirectoryCount]:=ChildName;
          End Else Begin
            SourceName:=ChildName;
            ReportError('trop de sous-repertoires dans '+Name);
          End;
        End Else If(DirectoryEntry.Attr and VolumeID)=0 Then Begin
          HasGzipSuffix:=(Length(DirectoryEntry.Name)>=Length(Suffix))and
            (Copy(DirectoryEntry.Name,
              Length(DirectoryEntry.Name)-Length(Suffix)+1,
              Length(Suffix))=Suffix);
          If DecompressMode or TestMode or ListMode Then Begin
            If HasGzipSuffix Then ProcessFile(ChildName);
          End Else If Not HasGzipSuffix Then ProcessFile(ChildName);
        End;
      End;
      FindNext(DirectoryEntry);
    End;
    {$IFDEF FPC}FindClose(DirectoryEntry);{$ENDIF}
    For Index:=1 to SubdirectoryCount Do
      ProcessPath(Subdirectories[Index]);
  End Else Begin
    {$IFDEF FPC}FindClose(DirectoryEntry);{$ENDIF}
    ProcessFile(Name);
  End;
End;

Procedure ReadOptionValue(Const OptionName:String; Var Index:Integer;
                          Const Current:String; Var Value:String);
Begin
  If Current<>''Then Value:=Current Else Begin
    Inc(Index);
    If Index>ParamCount Then OptionError('valeur manquante pour '+OptionName);
    Value:=ParamStr(Index);
  End;
End;

BEGIN
  LanguageCode:=GetEnv('LANGUAGE');
  FileCount:=0; Suffix:='.gz'; CompressionLevel:=6;
  StdoutMode:=False; ForceMode:=False; VerboseMode:=False; QuietMode:=False;
  DecompressMode:=False; TestMode:=False; ListMode:=False;
  RecursiveMode:=False; SaveName:=True; EndOptions:=False; ErrorFound:=False;
  SearchLimit:=16;
  ArgumentIndex:=1;
  While ArgumentIndex<=ParamCount Do Begin
    Argument:=ParamStr(ArgumentIndex);
    If Not EndOptions and(Argument='--')Then EndOptions:=True Else
    If Not EndOptions and((Argument='--help')or(Argument='-h')or(Argument='/?'))Then Begin PrintHelp; Halt(0); End
    Else If Not EndOptions and((Argument='--version')or(Argument='-V'))Then Begin WriteLn('gzip (LINUX-0) 1.0'); Halt(0); End
    Else If Not EndOptions and((Argument='--license')or(Argument='-L'))Then Begin PrintLicense; Halt(0); End
    Else If Not EndOptions and((Argument='--stdout')or(Argument='--to-stdout')or(Argument='-c'))Then StdoutMode:=True
    Else If Not EndOptions and((Argument='--decompress')or(Argument='--uncompress')or(Argument='-d'))Then DecompressMode:=True
    Else If Not EndOptions and((Argument='--force')or(Argument='-f'))Then ForceMode:=True
    Else If Not EndOptions and((Argument='--quiet')or(Argument='-q'))Then QuietMode:=True
    Else If Not EndOptions and((Argument='--verbose')or(Argument='-v'))Then VerboseMode:=True
    Else If Not EndOptions and((Argument='--test')or(Argument='-t'))Then TestMode:=True
    Else If Not EndOptions and((Argument='--list')or(Argument='-l'))Then ListMode:=True
    Else If Not EndOptions and((Argument='--recursive')or(Argument='-r'))Then RecursiveMode:=True
    Else If Not EndOptions and((Argument='--name')or(Argument='-N'))Then SaveName:=True
    Else If Not EndOptions and((Argument='--no-name')or(Argument='-n'))Then SaveName:=False
    Else If Not EndOptions and((Argument='--best')or(Argument='-9'))Then Begin CompressionLevel:=9; SearchLimit:=128; End
    Else If Not EndOptions and((Argument='--fast')or(Argument='-1'))Then Begin CompressionLevel:=1; SearchLimit:=2; End
    Else If Not EndOptions and(Argument='-S')Then Begin ReadOptionValue(Argument,ArgumentIndex,'',Suffix); End
    Else If Not EndOptions and(Argument='--suffix')Then Begin ReadOptionValue(Argument,ArgumentIndex,'',Suffix); End
    Else If Not EndOptions and(Length(Argument)>8)and(Copy(Argument,1,8)='--suffix=')Then Suffix:=Copy(Argument,9,127)
    Else If Not EndOptions and(Length(Argument)=2)and(Argument[1]='-')and(Argument[2]in['1'..'9'])Then Begin
      CompressionLevel:=Ord(Argument[2])-Ord('0');
      SearchLimit:=CompressionLevel*14;
    End Else If Not EndOptions and(Length(Argument)>2)and(Copy(Argument,1,2)='-S')Then Suffix:=Copy(Argument,3,127)
    Else If Not EndOptions and(Length(Argument)>1)and(Argument[1]='-')Then Begin
      If Argument[2]='-'Then OptionError('option inconnue : '+Argument);
      For FileIndex:=2 to Length(Argument)Do Begin
        If Argument[FileIndex]='a'Then Begin End Else
        If Argument[FileIndex]='c'Then StdoutMode:=True Else
        If Argument[FileIndex]='d'Then DecompressMode:=True Else
        If Argument[FileIndex]='f'Then ForceMode:=True Else
        If Argument[FileIndex]='h'Then Begin PrintHelp; Halt(0); End Else
        If Argument[FileIndex]='l'Then ListMode:=True Else
        If Argument[FileIndex]='L'Then Begin PrintLicense; Halt(0); End Else
        If Argument[FileIndex]='n'Then SaveName:=False Else
        If Argument[FileIndex]='N'Then SaveName:=True Else
        If Argument[FileIndex]='q'Then QuietMode:=True Else
        If Argument[FileIndex]='r'Then RecursiveMode:=True Else
        If Argument[FileIndex]='t'Then TestMode:=True Else
        If Argument[FileIndex]='v'Then VerboseMode:=True Else
        If Argument[FileIndex]='V'Then Begin WriteLn('gzip (LINUX-0) 1.0'); Halt(0); End Else
          OptionError('option inconnue : '+Argument);
      End;
    End Else Begin
      If FileCount>=MaxFiles Then OptionError('trop de fichiers');
      Inc(FileCount); FileNames[FileCount]:=Argument;
    End;
    Inc(ArgumentIndex);
  End;
  If(FileCount=0)or(Length(Suffix)=0)Then Begin PrintHelp; Halt(2); End;
  For FileIndex:=1 to FileCount Do ProcessPath(FileNames[FileIndex]);
  If ErrorFound Then Halt(1);
END.