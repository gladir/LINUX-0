{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2026
  @website(https://www.gladir.com/linux-0)
  @abstract(Target: Turbo Pascal 7, Free Pascal 3.2)
}

Program ZCAT(Input,Output);

Uses DOS
{$IFDEF FPC}
  {$IFDEF WINDOWS},Windows{$ENDIF}
  {$IFDEF UNIX},BaseUnix{$ENDIF}
{$ENDIF}
  ;

Const
  InputBufferSize=4096;
  WindowSize=32768;
  MaxHuffmanSymbols=288;
  MaxHuffmanBits=15;

Type
  TFileArray=Array[1..32]Of String;
  TInputBuffer=Array[0..InputBufferSize-1]Of Byte;
  THistory=Array[0..WindowSize-1]Of Byte;
  TCodeLengths=Array[0..MaxHuffmanSymbols-1]Of Byte;
  TCodeCounts=Array[0..MaxHuffmanBits]Of Word;
  TCodeSymbols=Array[0..MaxHuffmanSymbols-1]Of Word;
  THuffmanTree=Record
    Counts:TCodeCounts;
    Symbols:TCodeSymbols;
    MaxLength:Integer;
    SymbolCount:Integer;
  End;

Var
  InputFile:File;
  FileNames:TFileArray;
  InputBuffer:TInputBuffer;
  History:THistory;
  LiteralLengths,DistanceLengths:TCodeLengths;
  LiteralTree,DistanceTree,CodeTree:THuffmanTree;
  FileName,Argument,LanguageCode:String;
  FileCount,ArgumentIndex,FileIndex:Integer;
  InputLength,InputPosition,InputReadCount:Word;
  BitByte,BitCount:Byte;
  WindowPosition:Integer;
  WindowValid,MemberSize,TotalOutput:LongInt;
  MemberCRC,StoredCRC,StoredSize:LongInt;
  InputEOF,InputError,DecodeError,ErrorFound:Boolean;
  StandardInputMode:Boolean;

Procedure ReportError(Const MessageText:String);
Begin
  {$IFDEF FPC}
  If Copy(LanguageCode,1,2)='EN'Then
    WriteLn(ErrOutput,'zcat: ',FileName,': ',MessageText)
  Else WriteLn(ErrOutput,'zcat : ',FileName,': ',MessageText);
  {$ELSE}
  If Copy(LanguageCode,1,2)='EN'Then
    WriteLn('zcat: ',FileName,': ',MessageText)
  Else WriteLn('zcat : ',FileName,': ',MessageText);
  {$ENDIF}
  ErrorFound:=True;
End;

Procedure PrintHelp;
Begin
  If Copy(LanguageCode,1,2)='EN'Then Begin
    WriteLn('ZCAT : Decompress gzip files to standard output.');
    WriteLn('Syntax: zcat [-fhLV] [file ...]');
    WriteLn(' -f, --force    Continue even if the file has multiple links');
    WriteLn(' -h, --help     Display this help');
    WriteLn(' -L, --license  Display license information');
    WriteLn(' -V, --version  Display version information');
    WriteLn('Supports gzip headers and stored, fixed and dynamic DEFLATE blocks.');
  End Else Begin
    WriteLn('ZCAT : Cette commande permet de d'+#130+'compresser des fichiers gzip vers la sortie standard.');
    WriteLn;
    WriteLn('Syntaxe : zcat [-fhLV] [fichier ...]');
    WriteLn;
    WriteLn(' -f, --force    Forcer si le fichier possede plusieurs liens');
    WriteLn(' -h, --help     Afficher cette aide');
    WriteLn(' -L, --license  Afficher les informations de licence');
    WriteLn(' -V, --version  Afficher les informations de version');
    WriteLn;
    WriteLn('Prend en charge gzip et les blocs DEFLATE stockes, fixes ou dynamiques.');
  End;
End;

Procedure PrintLicense;
Begin
  WriteLn('ZCAT (LINUX-0)');
  WriteLn('Implementation native Pascal, sans programme externe.');
  WriteLn('Voir le fichier LICENSE du depot pour les conditions applicables.');
End;

Procedure OptionError(Const MessageText:String);
Begin
  If Copy(LanguageCode,1,2)='EN'Then
    WriteLn('zcat: ',MessageText)
  Else WriteLn('zcat : ',MessageText);
  Halt(2);
End;

Function RefillInputBuffer:Boolean;
Var
  {$IFDEF FPC}
    {$IFDEF WINDOWS}
  BytesRead:LongWord;
    {$ELSE}
  BytesRead:LongInt;
    {$ENDIF}
  {$ELSE}
  BytesRead:LongInt;
  {$ENDIF}
  {$IFNDEF FPC}
  DosRegisters:Registers;
  {$ENDIF}
Begin
  If StandardInputMode Then Begin
    {$IFDEF FPC}
      {$IFDEF WINDOWS}
      If Not ReadFile(GetStdHandle(STD_INPUT_HANDLE),InputBuffer,
                      InputBufferSize,BytesRead,Nil)Then
        BytesRead:=0;
      {$ELSE}
      BytesRead:=fpRead(0,InputBuffer,InputBufferSize);
      If BytesRead<0 Then Begin
        InputError:=True;
        RefillInputBuffer:=False;
        Exit;
      End;
      {$ENDIF}
    {$ELSE}
    DosRegisters.AH:=$3F;
    DosRegisters.BX:=0;
    DosRegisters.CX:=InputBufferSize;
    DosRegisters.DS:=Seg(InputBuffer);
    DosRegisters.DX:=Ofs(InputBuffer);
    MsDos(DosRegisters);
    BytesRead:=DosRegisters.AX;
    {$ENDIF}
    InputReadCount:=BytesRead;
  End Else Begin
    {$I-}BlockRead(InputFile,InputBuffer,SizeOf(InputBuffer),InputReadCount);{$I+}
    If IOResult<>0 Then Begin
      InputError:=True;
      RefillInputBuffer:=False;
      Exit;
    End;
  End;
  InputLength:=InputReadCount;
  InputPosition:=0;
  If InputLength=0 Then InputEOF:=True;
  RefillInputBuffer:=InputLength>0;
End;

Function ReadInputByte(Var Value:Byte):Boolean;
Begin
  If InputPosition>=InputLength Then
    If Not RefillInputBuffer Then Begin
      ReadInputByte:=False;
      Exit;
    End;
  Value:=InputBuffer[InputPosition];
  Inc(InputPosition);
  ReadInputByte:=True;
End;

Function ReadBits(Count:Integer):LongInt;
Var
  BitIndex:Integer;
  ResultValue:LongInt;
Begin
  ResultValue:=0;
  For BitIndex:=0 to Count-1 Do Begin
    If BitCount=0 Then Begin
      If Not ReadInputByte(BitByte)Then Begin
        DecodeError:=True;
        ReadBits:=ResultValue;
        Exit;
      End;
      BitCount:=8;
    End;
    If(BitByte and 1)<>0 Then
      ResultValue:=ResultValue or(LongInt(1)shl BitIndex);
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
  If Not ReadAlignedByte(Byte0)Then Begin
    ReadLittleLong:=False;
    Exit;
  End;
  If Not ReadAlignedByte(Byte1)Then Begin
    ReadLittleLong:=False;
    Exit;
  End;
  If Not ReadAlignedByte(Byte2)Then Begin
    ReadLittleLong:=False;
    Exit;
  End;
  If Not ReadAlignedByte(Byte3)Then Begin
    ReadLittleLong:=False;
    Exit;
  End;
  {$Q-}
  Value:=LongInt(Byte0)or(LongInt(Byte1)shl 8)or
         (LongInt(Byte2)shl 16)or(LongInt(Byte3)shl 24);
  {$Q+}
  ReadLittleLong:=True;
End;

Function BuildHuffmanTree(Var Tree:THuffmanTree;
                          Var Lengths:TCodeLengths;
                          SymbolLimit:Integer):Boolean;Forward;

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
      If Lengths[Symbol]>Tree.MaxLength Then
        Tree.MaxLength:=Lengths[Symbol];
    End;
  End;
  If Tree.SymbolCount=0 Then Begin
    BuildHuffmanTree:=False;
    Exit;
  End;
  Left:=1;
  For Bits:=1 to MaxHuffmanBits Do Begin
    Left:=(Left shl 1)-Tree.Counts[Bits];
    If Left<0 Then Begin
      BuildHuffmanTree:=False;
      Exit;
    End;
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
  Code:=0;
  First:=0;
  Index:=0;
  For LengthIndex:=1 to Tree.MaxLength Do Begin
    Code:=(Code shl 1)or ReadBits(1);
    If DecodeError Then Begin
      DecodeSymbol:=-1;
      Exit;
    End;
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
  BitIndex:Integer;
Begin
  {$Q-}
  MemberCRC:=MemberCRC xor Value;
  For BitIndex:=1 to 8 Do Begin
    If(MemberCRC and 1)<>0 Then
      MemberCRC:=(MemberCRC shr 1)xor LongInt($EDB88320)
    Else MemberCRC:=MemberCRC shr 1;
  End;
  {$Q+}
End;

Procedure WriteDecodedByte(Value:Byte);
Begin
  Write(Output,Chr(Value));
  History[WindowPosition]:=Value;
  If WindowPosition=WindowSize-1 Then WindowPosition:=0
  Else Inc(WindowPosition);
  If WindowValid<WindowSize Then Inc(WindowValid);
  {$Q-}
  Inc(MemberSize);
  Inc(TotalOutput);
  {$Q+}
  UpdateCRC(Value);
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
    265..268:LengthExtra:=1;
    269..272:LengthExtra:=2;
    273..276:LengthExtra:=3;
    277..280:LengthExtra:=4;
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
  If Code<4 Then DistanceExtra:=0
  Else DistanceExtra:=(Code div 2)-1;
End;

Function DecodeCompressedBlock:Boolean;
Var
  Symbol,LengthValue,DistanceCode:Integer;
  DistanceValue,SourcePosition:LongInt;
  CopyIndex:Integer;
  Value:Byte;
Begin
  DecodeCompressedBlock:=False;
  Repeat
    Symbol:=DecodeSymbol(LiteralTree);
    If DecodeError Then Exit;
    If Symbol<256 Then WriteDecodedByte(Byte(Symbol))
    Else If Symbol=256 Then Begin
      DecodeCompressedBlock:=True;
      Exit;
    End Else Begin
      If(Symbol<257)or(Symbol>285)Then Exit;
      LengthValue:=LengthBase(Symbol)+ReadBits(LengthExtra(Symbol));
      If DecodeError Then Exit;
      DistanceCode:=DecodeSymbol(DistanceTree);
      If DecodeError or(DistanceCode<0)or(DistanceCode>29)Then Exit;
      DistanceValue:=DistanceBase(DistanceCode)+
                     ReadBits(DistanceExtra(DistanceCode));
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
        Else If Index=LiteralCount Then
          PreviousLength:=LiteralLengths[LiteralCount-1]
        Else PreviousLength:=DistanceLengths[Index-LiteralCount-1];
      End Else If Symbol=17 Then Begin
        RepeatCount:=ReadBits(3)+3;
        PreviousLength:=0;
      End Else If Symbol=18 Then Begin
        RepeatCount:=ReadBits(7)+11;
        PreviousLength:=0;
      End Else Exit;
      If DecodeError or(RepeatCount>LiteralCount+DistanceCount-Index)Then Exit;
      While RepeatCount>0 Do Begin
        If Index<LiteralCount Then LiteralLengths[Index]:=PreviousLength
        Else DistanceLengths[Index-LiteralCount]:=PreviousLength;
        Inc(Index);
        Dec(RepeatCount);
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
  LengthValue,Complement:Word;
  StoredByte:Byte;
  StoredIndex:LongInt;
Begin
  InflateDeflate:=False;
  FinalBlock:=False;
  While Not FinalBlock Do Begin
    FinalBlock:=ReadBits(1)<>0;
    BlockType:=ReadBits(2);
    If DecodeError Then Exit;
    Case BlockType Of
      0:Begin
        BitCount:=0;
        If Not ReadLittleWord(LengthValue)Then Exit;
        If Not ReadLittleWord(Complement)Then Exit;
        If(LengthValue xor Complement)<>65535 Then Exit;
        For StoredIndex:=1 to LengthValue Do Begin
          If Not ReadAlignedByte(StoredByte)Then Exit;
          WriteDecodedByte(StoredByte);
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

Function ReadGzipHeader:Boolean;
Var
  Method,Flags,Value:Byte;
  ExtraLength,Index:Word;
  ExtraIndex:LongInt;
Begin
  ReadGzipHeader:=False;
  If Not ReadAlignedByte(Method)or Not ReadAlignedByte(Flags)Then Exit;
  If(Method<>8)or((Flags and $E0)<>0)Then Exit;
  For Index:=1 to 6 Do
    If Not ReadAlignedByte(Value)Then Exit;
  If(Flags and 4)<>0 Then Begin
    If Not ReadLittleWord(ExtraLength)Then Exit;
    For ExtraIndex:=1 to ExtraLength Do
      If Not ReadAlignedByte(Value)Then Exit;
  End;
  If(Flags and 8)<>0 Then Begin
    Repeat
      If Not ReadAlignedByte(Value)Then Exit;
    Until Value=0;
  End;
  If(Flags and 16)<>0 Then Begin
    Repeat
      If Not ReadAlignedByte(Value)Then Exit;
    Until Value=0;
  End;
  If(Flags and 2)<>0 Then Begin
    If Not ReadAlignedByte(Value)or Not ReadAlignedByte(Value)Then Exit;
  End;
  ReadGzipHeader:=True;
End;

Function DecodeGzipMember:Boolean;
Begin
  DecodeGzipMember:=False;
  If Not ReadGzipHeader Then Exit;
  WindowPosition:=0;
  WindowValid:=0;
  MemberSize:=0;
  MemberCRC:=LongInt($FFFFFFFF);
  BitCount:=0;
  DecodeError:=False;
  If Not InflateDeflate Then Exit;
  BitCount:=0;
  If Not ReadLittleLong(StoredCRC)Then Exit;
  If Not ReadLittleLong(StoredSize)Then Exit;
  If(StoredCRC<>(MemberCRC xor LongInt($FFFFFFFF)))or
    (StoredSize<>MemberSize)Then Exit;
  DecodeGzipMember:=True;
End;

Procedure DecompressFile(Const Name:String; UseStandardInput:Boolean);
Var
  FirstByte,SecondByte:Byte;
  HasMember:Boolean;
Begin
  FileName:=Name;
  StandardInputMode:=UseStandardInput;
  If Not StandardInputMode Then Begin
    Assign(InputFile,Name);
    FileMode:=0;
    {$I-}Reset(InputFile,1);{$I+}
    If IOResult<>0 Then Begin
      ReportError('impossible de lire le fichier');
      Exit;
    End;
  End;
  InputLength:=0;
  InputPosition:=0;
  BitCount:=0;
  InputEOF:=False;
  InputError:=False;
  TotalOutput:=0;
  HasMember:=False;
  Repeat
    If Not ReadAlignedByte(FirstByte)Then Break;
    If Not ReadAlignedByte(SecondByte)Then Begin
      ReportError('entete gzip tronque');
      Break;
    End;
    If(FirstByte<>31)or(SecondByte<>139)Then Begin
      ReportError('signature gzip invalide');
      Break;
    End;
    If Not DecodeGzipMember Then Begin
      ReportError('flux DEFLATE ou CRC gzip invalide');
      Break;
    End;
    HasMember:=True;
  Until InputEOF;
  If InputError Then ReportError('erreur de lecture');
  If Not HasMember and Not ErrorFound Then
    ReportError('fichier gzip vide ou invalide');
  If Not StandardInputMode Then Close(InputFile);
End;

BEGIN
  LanguageCode:=GetEnv('LANGUAGE');
  FileCount:=0;
  ErrorFound:=False;
  ArgumentIndex:=1;
  While ArgumentIndex<=ParamCount Do Begin
    Argument:=ParamStr(ArgumentIndex);
    If(Argument='--help')or(Argument='-h')Then Begin
      PrintHelp;
      Halt(0);
    End Else If(Argument='--license')or(Argument='-L')Then Begin
      PrintLicense;
      Halt(0);
    End Else If(Argument='--version')or(Argument='-V')Then Begin
      WriteLn('zcat (LINUX-0) 1.0');
      Halt(0);
    End Else If(Argument='--force')or(Argument='-f')Then Begin
    End
    Else If(Length(Argument)>1)and(Argument[1]='-')Then Begin
      If(Length(Argument)>2)and(Argument[2]='-')Then
        OptionError('option inconnue : '+Argument);
      For FileIndex:=2 to Length(Argument)Do Begin
        If Argument[FileIndex]='f'Then Begin
        End Else
        If Argument[FileIndex]='h'Then Begin
          PrintHelp;
          Halt(0);
        End Else If Argument[FileIndex]='L'Then Begin
          PrintLicense;
          Halt(0);
        End Else If Argument[FileIndex]='V'Then Begin
          WriteLn('zcat (LINUX-0) 1.0');
          Halt(0);
        End Else OptionError('option inconnue : '+Argument);
      End;
    End Else Begin
      If FileCount>=32 Then OptionError('trop de fichiers');
      Inc(FileCount);
      FileNames[FileCount]:=Argument;
    End;
    Inc(ArgumentIndex);
  End;
  If FileCount=0 Then DecompressFile('stdin',True)
  Else For FileIndex:=1 to FileCount Do Begin
    If FileNames[FileIndex]='-'Then DecompressFile('stdin',True)
    Else DecompressFile(FileNames[FileIndex],False);
  End;
  If ErrorFound Then Halt(1);
END.