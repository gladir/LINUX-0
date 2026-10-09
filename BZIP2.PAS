{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2026
  @website(https://www.gladir.com/linux-0)
  @abstract(Target: Turbo Pascal 7, Free Pascal 3.2)
}

Program BZIP2(Input,Output);

Uses DOS;

Const
  MaxBlockSize=8192;
  MaxSelectors=256;
  MaxGroups=6;
  MaxAlphabet=258;
  MaxCodeLength=23;
  BufferSize=4096;
  MaxFiles=32;
  MaxCompressInput=512;
  MaxRLEBlock=640;
  MaxEncodedSymbols=1300;

Type
  TBlockBytes=Array[0..MaxBlockSize-1]Of Byte;
  TNextArray=Array[0..MaxBlockSize-1]Of LongInt;
  TGroupLengths=Array[0..MaxGroups-1,0..MaxAlphabet-1]Of Byte;
  TSelectorArray=Array[0..MaxSelectors-1]Of Byte;
  TCodeArray=Array[0..MaxCodeLength]Of LongInt;
  TPermArray=Array[0..MaxAlphabet-1]Of Integer;
  TByteList=Array[0..255]Of Byte;
  TInUse=Array[0..255]Of Boolean;
  TInUseGroups=Array[0..15]Of Boolean;
  TCountArray=Array[0..256]Of LongInt;
  TStringArray=Array[1..32]Of String;
  TCompressInput=Array[0..MaxCompressInput-1]Of Byte;
  TRLEData=Array[0..MaxRLEBlock-1]Of Byte;
  TSortIndex=Array[0..MaxRLEBlock-1]Of Word;
  TEncodedSymbols=Array[0..MaxEncodedSymbols-1]Of Word;
  TFrequencies=Array[0..MaxAlphabet-1]Of LongInt;

Var
  InputFile,OutputFile:File;
  BWTData:TBlockBytes;
  NextIndex:TNextArray;
  CodeLengths:TGroupLengths;
  Selectors:TSelectorArray;
  HuffmanBase,HuffmanLimit:TCodeArray;
  HuffmanPerm:TPermArray;
  MTFList,SequenceToByte:TByteList;
  InUse:TInUse;
  InUseGroups:TInUseGroups;
  ByteCounts:TCountArray;
  CompressInput:TCompressInput;
  RLEBlock:TRLEData;
  RotationIndex:TSortIndex;
  EncodedSymbols:TEncodedSymbols;
  Frequencies:TFrequencies;
  InputFiles:TStringArray;
  OutputName,Argument,ActualCRCText,StoredCRCText:String;
  FileCount,I,J,FileIndex:Integer;
  BlockFactor,SelectorCount,SelectorPosition:Integer;
  MaxDecodedBlock:LongInt;
  AlphaSize,InUseCount,GroupCount,CurrentGroup,UsedGroupSymbols:Integer;
  CompressInputCount,RLELength,SymbolCount,ZeroRun:Integer;
  MinCodeLength,MaxCodeLengthValue:Integer;
  BlockCount,OriginalPointer:LongInt;
  InputLength,InputPosition:LongInt;
  BitByte:Byte;
  BitsLeft:Integer;
  OutputBitBuffer:LongInt;
  OutputBitCount:Integer;
  BlockCRC,StoredBlockCRC,CombinedCRC,StoredCombinedCRC:LongInt;
  DecompressMode,TestMode,WriteStdout,ForceOutput,KeepInput:Boolean;
  Quiet,CompressionRequested,CompressionMode:Boolean;
  VerboseLevel:Integer;
  BlocksProcessed:LongInt;
  InputError,DecodeError:Boolean;
  ValueLong:LongInt;
  WriteCount:Word;

Procedure Fail(Const MessageText:String);
Begin
  If Not Quiet Then WriteLn('bzip2: ',MessageText);
  Halt(1);
End;

Function ReadInputByte(Var Value:Byte):Boolean;
Var
  Count:Word;
Begin
  If InputPosition>=InputLength Then Begin
    ReadInputByte:=False;
    Exit;
  End;
  BlockRead(InputFile,Value,1,Count);
  If Count<>1 Then Begin
    ReadInputByte:=False;
    Exit;
  End;
  Inc(InputPosition);
  ReadInputByte:=True;
End;

Function ReadBits(BitCount:Integer):LongInt;
Var
  BitIndex:Integer;
  ResultValue:LongInt;
Begin
  ResultValue:=0;
  For BitIndex:=1 to BitCount Do Begin
    If BitsLeft=0 Then Begin
      If Not ReadInputByte(BitByte)Then Begin
        InputError:=True;
        ReadBits:=ResultValue;
        Exit;
      End;
      BitsLeft:=8;
    End;
    ResultValue:=(ResultValue shl 1)or((BitByte shr (BitsLeft-1))and 1);
    Dec(BitsLeft);
  End;
  ReadBits:=ResultValue;
End;

Function ReadByteAligned:Byte;
Var
  B:Byte;
Begin
  BitsLeft:=0;
  If Not ReadInputByte(B)Then Begin
    InputError:=True;
    ReadByteAligned:=0;
  End Else ReadByteAligned:=B;
End;

Function FileExistsTP(Name:String):Boolean;
Var
  Search:SearchRec;
Begin
  FindFirst(Name,AnyFile,Search);
  FileExistsTP:=(DosError=0)and((Search.Attr and Directory)=0);
  {$IFDEF FPC}FindClose(Search);{$ENDIF}
End;

Procedure RemoveInput(Name:String);
Var
  FileToRemove:File;
Begin
  Assign(FileToRemove,Name);
  {$I-}Erase(FileToRemove);{$I+}
  If IOResult<>0 Then Fail('impossible de supprimer '+Name);
End;

Function HasBZ2Suffix(Const Name:String):Boolean;
Var
  Suffix:String;
  Start:Integer;
Begin
  If Length(Name)<4 Then Begin
    HasBZ2Suffix:=False;
    Exit;
  End;
  Start:=Length(Name)-3;
  Suffix:=Copy(Name,Start,4);
  HasBZ2Suffix:=(Suffix='.bz2')or(Suffix='.BZ2');
End;

Function DefaultOutputName(Const Name:String):String;
Begin
  If HasBZ2Suffix(Name)Then
    DefaultOutputName:=Copy(Name,1,Length(Name)-4)
  Else DefaultOutputName:=Name+'.out';
End;

Procedure BuildHuffmanTable(GroupNumber:Integer);
Var
  I,LengthIndex,Position,Vector,Count:Integer;
Begin
  MinCodeLength:=MaxCodeLength+1;
  MaxCodeLengthValue:=0;
  For I:=0 to AlphaSize-1 Do Begin
    Count:=CodeLengths[GroupNumber,I];
    If Count<MinCodeLength Then MinCodeLength:=Count;
    If Count>MaxCodeLengthValue Then MaxCodeLengthValue:=Count;
  End;
  If(MinCodeLength<1)or(MaxCodeLengthValue>MaxCodeLength)Then Begin
    DecodeError:=True;
    Exit;
  End;
  For I:=0 to MaxCodeLength Do HuffmanBase[I]:=0;
  For I:=0 to AlphaSize-1 Do
    Inc(HuffmanBase[CodeLengths[GroupNumber,I]+1]);
  For I:=1 to MaxCodeLength Do
    HuffmanBase[I]:=HuffmanBase[I]+HuffmanBase[I-1];
  Position:=0;
  For LengthIndex:=MinCodeLength to MaxCodeLengthValue Do
    For I:=0 to AlphaSize-1 Do
      If CodeLengths[GroupNumber,I]=LengthIndex Then Begin
        HuffmanPerm[Position]:=I;
        Inc(Position);
      End;
  Vector:=0;
  For LengthIndex:=MinCodeLength to MaxCodeLengthValue Do Begin
    Vector:=Vector+HuffmanBase[LengthIndex+1]-HuffmanBase[LengthIndex];
    HuffmanLimit[LengthIndex]:=Vector-1;
    Vector:=Vector shl 1;
  End;
  For LengthIndex:=MinCodeLength+1 to MaxCodeLengthValue Do
    HuffmanBase[LengthIndex]:=((HuffmanLimit[LengthIndex-1]+1)shl 1)-
                              HuffmanBase[LengthIndex];
End;

Function NextHuffmanSymbol:Integer;
Var
  CodeValue,CodeLength,PermIndex:LongInt;
Begin
  If UsedGroupSymbols=0 Then Begin
    If SelectorPosition>=SelectorCount Then Begin
      DecodeError:=True;
      NextHuffmanSymbol:=0;
      Exit;
    End;
    CurrentGroup:=Selectors[SelectorPosition];
    Inc(SelectorPosition);
    BuildHuffmanTable(CurrentGroup);
    If DecodeError Then Begin
      NextHuffmanSymbol:=0;
      Exit;
    End;
  End;
  Inc(UsedGroupSymbols);
  If UsedGroupSymbols=50 Then UsedGroupSymbols:=0;
  CodeLength:=MinCodeLength;
  CodeValue:=ReadBits(CodeLength);
  While(CodeLength<=MaxCodeLengthValue)and
    (CodeValue>HuffmanLimit[CodeLength])Do Begin
    Inc(CodeLength);
    CodeValue:=(CodeValue shl 1)or ReadBits(1);
  End;
  If(CodeLength>MaxCodeLengthValue)or InputError Then Begin
    DecodeError:=True;
    NextHuffmanSymbol:=0;
    Exit;
  End;
  PermIndex:=CodeValue-HuffmanBase[CodeLength];
  If(PermIndex<0)or(PermIndex>=AlphaSize)Then Begin
    DecodeError:=True;
    NextHuffmanSymbol:=0;
  End Else NextHuffmanSymbol:=HuffmanPerm[PermIndex];
End;

Procedure StoreLastByte(Value:Byte; Count:LongInt);
Var
  I:LongInt;
Begin
  If(Count<0)or(Count>MaxDecodedBlock-BlockCount)or
    (Count>MaxBlockSize-BlockCount)Then Begin
    DecodeError:=True;
    Exit;
  End;
  For I:=1 to Count Do Begin
    BWTData[BlockCount]:=Value;
    Inc(BlockCount);
  End;
End;

Function DecodeBlock:Boolean;
Var
  I,J,Group,UnaryCount,Symbol,NextSymbol,MTFIndex:Integer;
  RunAccum,RunWeight:LongInt;
Begin
  DecodeBlock:=False;
  StoredBlockCRC:=ReadBits(32);
  If InputError Then Exit;
  If ReadBits(1)<>0 Then Begin
    Fail('les blocs randomises ne sont pas pris en charge');
  End;
  OriginalPointer:=ReadBits(24);
  InUseCount:=0;
  For I:=0 to 255 Do InUse[I]:=False;
  For Group:=0 to 15 Do InUseGroups[Group]:=ReadBits(1)<>0;
  For Group:=0 to 15 Do Begin
    If InUseGroups[Group]Then
      For I:=0 to 15 Do
        If ReadBits(1)<>0 Then Begin
          InUse[Group*16+I]:=True;
          Inc(InUseCount);
        End;
  End;
  If(InUseCount=0)or(InUseCount>256)Then Exit;
  J:=0;
  For I:=0 to 255 Do
    If InUse[I]Then Begin
      SequenceToByte[J]:=I;
      Inc(J);
    End;
  InUseCount:=J;
  AlphaSize:=InUseCount+2;
  GroupCount:=ReadBits(3);
  SelectorCount:=ReadBits(15);
  If(GroupCount<2)or(GroupCount>MaxGroups)or
    (SelectorCount<1)or(SelectorCount>MaxSelectors)Then Exit;
  For I:=0 to GroupCount-1 Do MTFList[I]:=I;
  For I:=0 to SelectorCount-1 Do Begin
    UnaryCount:=0;
    While ReadBits(1)<>0 Do Begin
      Inc(UnaryCount);
      If UnaryCount>=GroupCount Then Exit;
    End;
    Group:=MTFList[UnaryCount];
    For J:=UnaryCount downto 1 Do MTFList[J]:=MTFList[J-1];
    MTFList[0]:=Group;
    Selectors[I]:=Group;
  End;
  For I:=0 to InUseCount-1 Do MTFList[I]:=I;
  For Group:=0 to GroupCount-1 Do Begin
    I:=ReadBits(5);
    If(I<1)or(I>MaxCodeLength)Then Exit;
    For J:=0 to AlphaSize-1 Do Begin
      While ReadBits(1)<>0 Do Begin
        If ReadBits(1)=0 Then Inc(I) Else Dec(I);
        If(I<1)or(I>MaxCodeLength)Then Exit;
      End;
      CodeLengths[Group,J]:=I;
    End;
  End;
  BlockCount:=0;
  SelectorPosition:=0;
  UsedGroupSymbols:=0;
  DecodeError:=False;
  Symbol:=NextHuffmanSymbol;
  While(Symbol<>InUseCount+1)and Not DecodeError Do Begin
    If(Symbol=0)or(Symbol=1)Then Begin
      RunAccum:=-1;
      RunWeight:=1;
      Repeat
        If Symbol=0 Then Inc(RunAccum,RunWeight)
                    Else Inc(RunAccum,RunWeight*2);
        RunWeight:=RunWeight*2;
        Symbol:=NextHuffmanSymbol;
      Until(Symbol>1)or DecodeError;
      Inc(RunAccum);
      If Not DecodeError Then StoreLastByte(SequenceToByte[MTFList[0]],RunAccum);
    End;
    If Not DecodeError and(Symbol<>InUseCount+1)Then Begin
      MTFIndex:=Symbol-1;
      If(MTFIndex<1)or(MTFIndex>=InUseCount)Then Begin
        DecodeError:=True;
      End Else Begin
        NextSymbol:=MTFList[MTFIndex];
        For J:=MTFIndex downto 1 Do MTFList[J]:=MTFList[J-1];
        MTFList[0]:=NextSymbol;
        StoreLastByte(SequenceToByte[NextSymbol],1);
        Symbol:=NextHuffmanSymbol;
      End;
    End;
  End;
  If DecodeError or(BlockCount=0)or(OriginalPointer<0)or
    (OriginalPointer>=BlockCount)Then Exit;
  DecodeBlock:=True;
End;

Procedure BuildBWTIndex;
Var
  I,ByteValue:Integer;
  Position:LongInt;
Begin
  For I:=0 to 256 Do ByteCounts[I]:=0;
  For I:=0 to BlockCount-1 Do Inc(ByteCounts[BWTData[I]]);
  Position:=0;
  For I:=0 to 255 Do Begin
    ValueLong:=ByteCounts[I];
    ByteCounts[I]:=Position;
    Inc(Position,ValueLong);
  End;
  ByteCounts[256]:=BlockCount;
  For I:=0 to BlockCount-1 Do Begin
    ByteValue:=BWTData[I];
    NextIndex[ByteCounts[ByteValue]]:=I;
    Inc(ByteCounts[ByteValue]);
  End;
End;

{$Q-}
Procedure WriteDecodedByte(Value:Byte);
Var
  I:Integer;
Begin
  BlockCRC:=BlockCRC xor (LongInt(Value) shl 24);
  For I:=1 to 8 Do Begin
    If(BlockCRC and LongInt($80000000))<>0 Then
      BlockCRC:=(BlockCRC shl 1)xor LongInt($04C11DB7)
    Else BlockCRC:=BlockCRC shl 1;
  End;
  If Not TestMode Then Begin
    If WriteStdout Then Write(Output,Chr(Value))
    Else Begin
      BlockWrite(OutputFile,Value,1,WriteCount);
      If WriteCount<>1 Then Fail('echec d''ecriture');
    End;
  End;
End;
{$Q+}

Procedure DecodeOriginalBlock;
Var
  Position,Index:LongInt;
  Value:Byte;
  LastByte:Integer;
  SameCount:Integer;
  ExpectRunCount:Boolean;
  ExtraCount:Integer;
Begin
  BuildBWTIndex;
  Position:=NextIndex[OriginalPointer];
  LastByte:=-1;
  SameCount:=0;
  ExpectRunCount:=False;
  BlockCRC:=LongInt($FFFFFFFF);
  For Index:=0 to BlockCount-1 Do Begin
    Value:=BWTData[Position];
    Position:=NextIndex[Position];
    If ExpectRunCount Then Begin
      ExtraCount:=Value;
      For I:=1 to ExtraCount Do WriteDecodedByte(Byte(LastByte));
      ExpectRunCount:=False;
      SameCount:=0;
    End Else Begin
      WriteDecodedByte(Value);
      If Value=LastByte Then Inc(SameCount)
      Else Begin
        LastByte:=Value;
        SameCount:=1;
      End;
      If SameCount=4 Then ExpectRunCount:=True;
    End;
  End;
  If ExpectRunCount Then Begin
    DecodeError:=True;
  End;
  BlockCRC:=BlockCRC xor LongInt($FFFFFFFF);
  If BlockCRC<>StoredBlockCRC Then Begin
    DecodeError:=True;
    Str(BlockCRC,ActualCRCText);
    Str(StoredBlockCRC,StoredCRCText);
  End;
End;

Function ReadMagic24:LongInt;
Begin
  ReadMagic24:=ReadBits(24);
End;

Procedure ProcessBzipStream;
Var
  MagicHigh,MagicLow:LongInt;
  ExpectedCRC:LongInt;
Begin
  BitsLeft:=0;
  CombinedCRC:=0;
  BlocksProcessed:=0;
  Repeat
    MagicHigh:=ReadMagic24;
    MagicLow:=ReadMagic24;
    If InputError Then Fail('flux bzip2 tronque');
    If(MagicHigh=$177245)and(MagicLow=$385090)Then Begin
      StoredCombinedCRC:=ReadBits(32);
      If InputError Then Fail('CRC combine tronque');
      If StoredCombinedCRC<>CombinedCRC Then Fail('CRC combine invalide');
      Break;
    End;
    If(MagicHigh<>$314159)or(MagicLow<>$265359)Then
      Fail('signature de bloc bzip2 invalide');
    If Not DecodeBlock Then Fail('bloc bzip2 invalide ou trop volumineux');
    ExpectedCRC:=StoredBlockCRC;
    DecodeOriginalBlock;
    If DecodeError Then
      Fail('CRC de bloc invalide: calcule '+ActualCRCText+
           ', attendu '+StoredCRCText);
    {$Q-}
    CombinedCRC:=((CombinedCRC shl 1)or((CombinedCRC shr 31)and 1))xor ExpectedCRC;
    {$Q+}
    Inc(BlocksProcessed);
    If(VerboseLevel>1)and(TestMode or Not WriteStdout)Then
      WriteLn('  bloc ',BlocksProcessed,' valide, ',BlockCount,' octets BWT');
  Until False;
  If(VerboseLevel>0)and(TestMode or Not WriteStdout)Then
    WriteLn('  flux bzip2 verifie');
End;

Function ParseNumber(Const S:String; Var Value:LongInt):Boolean;
Var
  ErrorCode:Integer;
Begin
  Val(S,Value,ErrorCode);
  ParseNumber:=ErrorCode=0;
End;

Function OutputNameFor(Const Name:String):String;
Begin
  If(Length(Name)>4)and(Copy(Name,Length(Name)-3,4)='.bz2')Then
    OutputNameFor:=Copy(Name,1,Length(Name)-4)
  Else OutputNameFor:=Name+'.out';
End;

Procedure WriteOutputByte(Value:Byte);
Begin
  If WriteStdout Then Write(Output,Chr(Value)) Else Begin
    BlockWrite(OutputFile,Value,1,WriteCount);
    If WriteCount<>1 Then Fail('echec d''ecriture du flux compresse');
  End;
End;

{$Q-}{$R-}
Procedure WriteBits(Value:LongInt; BitCount:Integer);
Var
  BitIndex:Integer;
Begin
  For BitIndex:=BitCount-1 downto 0 Do Begin
    OutputBitBuffer:=(OutputBitBuffer shl 1)or((Value shr BitIndex)and 1);
    Inc(OutputBitCount);
    If OutputBitCount=8 Then Begin
      WriteOutputByte(Byte(OutputBitBuffer));
      OutputBitBuffer:=0;
      OutputBitCount:=0;
    End;
  End;
End;
{$Q+}{$R+}

Procedure FinishBits;
Begin
  If OutputBitCount>0 Then Begin
    OutputBitBuffer:=OutputBitBuffer shl (8-OutputBitCount);
    WriteOutputByte(Byte(OutputBitBuffer));
    OutputBitBuffer:=0;
    OutputBitCount:=0;
  End;
End;

Procedure WriteBzipHeader;
Begin
  WriteOutputByte(Ord('B'));
  WriteOutputByte(Ord('Z'));
  WriteOutputByte(Ord('h'));
  WriteOutputByte(Ord('0')+BlockFactor);
End;

Procedure WriteLongBits(Value:LongInt);
Begin
  WriteBits((Value shr 24)and 255,8);
  WriteBits((Value shr 16)and 255,8);
  WriteBits((Value shr 8)and 255,8);
  WriteBits(Value and 255,8);
End;

{$Q-}
Function CRCUpdateByte(CRC:LongInt; Value:Byte):LongInt;
Var
  BitIndex:Integer;
Begin
  CRC:=CRC xor (LongInt(Value) shl 24);
  For BitIndex:=1 to 8 Do Begin
    If(CRC and LongInt($80000000))<>0 Then
      CRC:=(CRC shl 1)xor LongInt($04C11DB7)
    Else CRC:=CRC shl 1;
  End;
  CRCUpdateByte:=CRC;
End;
{$Q+}

Procedure AppendRLE(Value:Byte; Count:Integer);
Var
  I:Integer;
Begin
  If Count>=4 Then Begin
    For I:=1 to 4 Do Begin
      If RLELength>=MaxRLEBlock Then Fail('bloc RLE trop volumineux');
      RLEBlock[RLELength]:=Value;
      Inc(RLELength);
    End;
    If RLELength>=MaxRLEBlock Then Fail('bloc RLE trop volumineux');
    RLEBlock[RLELength]:=Count-4;
    Inc(RLELength);
  End Else
    For I:=1 to Count Do Begin
      If RLELength>=MaxRLEBlock Then Fail('bloc RLE trop volumineux');
      RLEBlock[RLELength]:=Value;
      Inc(RLELength);
    End;
End;

Function CompareRotations(A,B:Integer):Integer;
Var
  I,IndexA,IndexB:Integer;
Begin
  CompareRotations:=0;
  For I:=0 to RLELength-1 Do Begin
    IndexA:=(A+I)mod RLELength;
    IndexB:=(B+I)mod RLELength;
    If RLEBlock[IndexA]<RLEBlock[IndexB]Then Begin
      CompareRotations:=-1;
      Exit;
    End Else If RLEBlock[IndexA]>RLEBlock[IndexB]Then Begin
      CompareRotations:=1;
      Exit;
    End;
  End;
End;

Procedure SortRotations(Left,Right:Integer);
Var
  I,J,Pivot,Temp:Integer;
Begin
  I:=Left;
  J:=Right;
  Pivot:=RotationIndex[(Left+Right)div 2];
  Repeat
    While CompareRotations(RotationIndex[I],Pivot)<0 Do Inc(I);
    While CompareRotations(RotationIndex[J],Pivot)>0 Do Dec(J);
    If I<=J Then Begin
      Temp:=RotationIndex[I];
      RotationIndex[I]:=RotationIndex[J];
      RotationIndex[J]:=Temp;
      Inc(I);
      Dec(J);
    End;
  Until I>J;
  If Left<J Then SortRotations(Left,J);
  If I<Right Then SortRotations(I,Right);
End;

Procedure AppendSymbol(Value:Integer);
Begin
  If(Value<0)or(Value>=MaxAlphabet)or(SymbolCount>=MaxEncodedSymbols)Then
    Fail('trop de symboles dans le bloc');
  EncodedSymbols[SymbolCount]:=Value;
  Inc(SymbolCount);
  Inc(Frequencies[Value]);
End;

Procedure EmitZeroRun;
Var
  RunValue:Integer;
Begin
  If ZeroRun=0 Then Exit;
  RunValue:=ZeroRun-1;
  Repeat
    If(RunValue and 1)<>0 Then AppendSymbol(1)Else AppendSymbol(0);
    If RunValue<2 Then Break;
    RunValue:=(RunValue-2)div 2;
  Until False;
  ZeroRun:=0;
End;

Procedure BuildMTFStream;
Var
  I,J,CompactIndex,TempValue:Integer;
Begin
  For I:=0 to 255 Do InUse[I]:=False;
  For I:=0 to RLELength-1 Do InUse[RLEBlock[I]]:=True;
  InUseCount:=0;
  For I:=0 to 255 Do
    If InUse[I]Then Begin
      SequenceToByte[InUseCount]:=I;
      Inc(InUseCount);
    End;
  If InUseCount=0 Then Fail('alphabet vide dans le bloc');
  AlphaSize:=InUseCount+2;
  For I:=0 to InUseCount-1 Do MTFList[I]:=I;
  For I:=0 to MaxAlphabet-1 Do Frequencies[I]:=0;
  SymbolCount:=0;
  ZeroRun:=0;
  For I:=0 to RLELength-1 Do Begin
    CompactIndex:=0;
    While(CompactIndex<InUseCount)and
      (SequenceToByte[MTFList[CompactIndex]]<>BWTData[I])Do Inc(CompactIndex);
    If CompactIndex=0 Then Inc(ZeroRun) Else Begin
      EmitZeroRun;
      AppendSymbol(CompactIndex+1);
      TempValue:=MTFList[CompactIndex];
      For J:=CompactIndex downto 1 Do MTFList[J]:=MTFList[J-1];
      MTFList[0]:=TempValue;
    End;
  End;
  EmitZeroRun;
  AppendSymbol(InUseCount+1);
End;

Procedure EncodeOneBlock;
Var
  I,J,RunLength,Position:Integer;
  Value:Byte;
  SelectorCountValue,SymbolIndex:Integer;
Begin
  RLELength:=0;
  I:=0;
  While I<CompressInputCount Do Begin
    Value:=CompressInput[I];
    RunLength:=1;
    While(I+RunLength<CompressInputCount)and
      (CompressInput[I+RunLength]=Value)Do Inc(RunLength);
    Position:=0;
    While Position<RunLength Do Begin
      If RunLength-Position>255 Then J:=255 Else J:=RunLength-Position;
      AppendRLE(Value,J);
      Inc(Position,J);
    End;
    Inc(I,RunLength);
  End;
  For I:=0 to RLELength-1 Do RotationIndex[I]:=I;
  If RLELength>1 Then SortRotations(0,RLELength-1);
  OriginalPointer:=0;
  For I:=0 to RLELength-1 Do Begin
    Position:=RotationIndex[I];
    If Position=0 Then OriginalPointer:=I;
    If Position=0 Then Position:=RLELength;
    BWTData[I]:=RLEBlock[Position-1];
  End;
  BuildMTFStream;

  WriteLongBits($31415926);
  WriteBits($5359,16);
  WriteLongBits(BlockCRC xor LongInt($FFFFFFFF));
  WriteBits(0,1);
  WriteBits(OriginalPointer,24);
  For I:=0 to 15 Do Begin
    Value:=0;
    For J:=0 to 15 Do
      If InUse[I*16+J]Then Value:=1;
    WriteBits(Value,1);
  End;
  For I:=0 to 15 Do
    If InUse[I*16]or InUse[I*16+1]or InUse[I*16+2]or InUse[I*16+3]or
      InUse[I*16+4]or InUse[I*16+5]or InUse[I*16+6]or InUse[I*16+7]or
      InUse[I*16+8]or InUse[I*16+9]or InUse[I*16+10]or InUse[I*16+11]or
      InUse[I*16+12]or InUse[I*16+13]or InUse[I*16+14]or InUse[I*16+15]Then
      For J:=0 to 15 Do WriteBits(Ord(InUse[I*16+J]),1);
  WriteBits(2,3);
  SelectorCountValue:=(SymbolCount+49)div 50;
  If(SelectorCountValue<1)or(SelectorCountValue>MaxSelectors)Then
    Fail('trop de selecteurs Huffman');
  WriteBits(SelectorCountValue,15);
  For I:=1 to SelectorCountValue Do WriteBits(0,1);
  For I:=1 to 2 Do Begin
    WriteBits(9,5);
    For J:=0 to AlphaSize-1 Do WriteBits(0,1);
  End;
  For SymbolIndex:=0 to SymbolCount-1 Do
    WriteBits(EncodedSymbols[SymbolIndex],9);
End;

Procedure WriteBzipStreamEnd;
Begin
  WriteLongBits($17724538);
  WriteBits($5090,16);
  WriteLongBits(CombinedCRC);
  FinishBits;
End;

Procedure ProcessOneFile(Const Name:String);
Var
  InputHeader:Array[1..4]Of Byte;
Begin
  Assign(InputFile,Name);
  {$I-}Reset(InputFile,1);{$I+}
  If IOResult<>0 Then Fail('impossible de lire '+Name);
  InputLength:=FileSize(InputFile);
  InputPosition:=0;
  For I:=1 to 4 Do Begin
    If Not ReadInputByte(InputHeader[I])Then Fail('fichier bzip2 trop court');
  End;
  If(InputHeader[1]<>Ord('B'))or(InputHeader[2]<>Ord('Z'))or
    (InputHeader[3]<>Ord('h'))or Not(InputHeader[4]in[Ord('1')..Ord('9')])Then
    Fail('signature BZh invalide');
  BlockFactor:=InputHeader[4]-Ord('0');
  MaxDecodedBlock:=LongInt(BlockFactor)*100000;
  If TestMode Then Begin
    ProcessBzipStream;
    Close(InputFile);
    If(VerboseLevel>0)and Not Quiet Then WriteLn(Name,': OK');
  End Else Begin
    If WriteStdout Then Begin
      ProcessBzipStream;
      Close(InputFile);
    End Else Begin
      OutputName:=OutputNameFor(Name);
      If FileExistsTP(OutputName)and Not ForceOutput Then Begin
        Close(InputFile);
        Fail('le fichier de sortie existe deja: '+OutputName);
      End;
      If FileExistsTP(OutputName)Then RemoveInput(OutputName);
      Assign(OutputFile,OutputName);
      {$I-}Rewrite(OutputFile,1);{$I+}
      If IOResult<>0 Then Begin
        Close(InputFile);
        Fail('impossible de creer '+OutputName);
      End;
      ProcessBzipStream;
      Close(OutputFile);
      Close(InputFile);
      If Not KeepInput Then RemoveInput(Name);
      If(VerboseLevel>0)and Not Quiet Then WriteLn(Name,': decompression vers ',OutputName);
    End;
  End;
End;

Procedure CompressOneFile(Const Name:String);
Var
  Count:Word;
  OutputExists:Boolean;
Begin
  If HasBZ2Suffix(Name)Then Fail('le fichier porte deja le suffixe .bz2: '+Name);
  Assign(InputFile,Name);
  {$I-}Reset(InputFile,1);{$I+}
  If IOResult<>0 Then Fail('impossible de lire '+Name);
  OutputName:=Name+'.bz2';
  OutputExists:=FileExistsTP(OutputName);
  If OutputExists and Not WriteStdout and Not ForceOutput Then Begin
    Close(InputFile);
    Fail('le fichier de sortie existe deja: '+OutputName);
  End;
  If OutputExists and Not WriteStdout and ForceOutput Then RemoveInput(OutputName);
  If Not WriteStdout Then Begin
    Assign(OutputFile,OutputName);
    {$I-}Rewrite(OutputFile,1);{$I+}
    If IOResult<>0 Then Begin
      Close(InputFile);
      Fail('impossible de creer '+OutputName);
    End;
  End;
  OutputBitBuffer:=0;
  OutputBitCount:=0;
  CombinedCRC:=0;
  BlocksProcessed:=0;
  WriteBzipHeader;
  Repeat
    CompressInputCount:=0;
    While(CompressInputCount<MaxCompressInput)and
      (FilePos(InputFile)<FileSize(InputFile))Do Begin
      BlockRead(InputFile,CompressInput[CompressInputCount],1,Count);
      If Count<>1 Then Break;
      Inc(CompressInputCount);
    End;
    If CompressInputCount>0 Then Begin
      BlockCRC:=LongInt($FFFFFFFF);
      For I:=0 to CompressInputCount-1 Do
        BlockCRC:=CRCUpdateByte(BlockCRC,CompressInput[I]);
      EncodeOneBlock;
      Inc(BlocksProcessed);
      If(VerboseLevel>1)and Not WriteStdout and Not Quiet Then
        WriteLn('  bloc ',BlocksProcessed,' compresse, ',CompressInputCount,' octets');
      {$Q-}
      CombinedCRC:=((CombinedCRC shl 1)or((CombinedCRC shr 31)and 1))xor
                    (BlockCRC xor LongInt($FFFFFFFF));
      {$Q+}
    End;
  Until CompressInputCount=0;
  WriteBzipStreamEnd;
  Close(InputFile);
  If Not WriteStdout Then Close(OutputFile);
  If Not KeepInput and Not WriteStdout Then RemoveInput(Name);
  If(VerboseLevel>0)and Not Quiet and Not WriteStdout Then
    WriteLn(Name,': compresse');
End;

Procedure PrintHelp;
Begin
  If Copy(GetEnv('LANGUAGE'),1,2)='EN'Then Begin
    WriteLn('bzip2 : compress and decompress bzip2 streams.');
    WriteLn('Syntax: bzip2 [OPTIONS] FILE...');
    WriteLn(' -1..-9              Select the level recorded in the stream header');
    WriteLn(' --fast, --best      Select level 1 or 9');
    WriteLn(' -c, --stdout        Write output to standard output');
    WriteLn(' -d, --decompress    Decompress');
    WriteLn(' -z, --compress      Force compression');
    WriteLn(' -f, --force         Overwrite existing output files');
    WriteLn(' -k, --keep          Keep input files');
    WriteLn(' -q, --quiet         Suppress non-critical diagnostics');
    WriteLn(' -s, --small         Select the bounded-memory compatibility mode');
    WriteLn(' -t, --test          Test stream integrity and CRC');
    WriteLn(' -v, --verbose       Increase verbosity; repeat for block details');
    WriteLn(' -V, --version       Display version');
    WriteLn(' -L, --license       Display license information');
    WriteLn(' -h, --help, /?, /h, /H');
    WriteLn('                     Display this help');
    WriteLn('Native compression uses blocks of up to 512 input bytes.');
    WriteLn('The selected level is written to the stream header.');
  End Else Begin
    WriteLn('bzip2 : Cette commande permet de compresser et de decompresser des flux bzip2.');
    WriteLn;
    WriteLn('Syntaxe : bzip2 [OPTIONS] FICHIER...');
    WriteLn;
    WriteLn(' -1..-9              Choisir le niveau inscrit dans l''entete');
    WriteLn(' --fast, --best      Choisir le niveau 1 ou 9');
    WriteLn(' -c, --stdout        Ecrire la sortie sur stdout');
    WriteLn(' -d, --decompress    Decompresser');
    WriteLn(' -z, --compress      Forcer la compression');
    WriteLn(' -f, --force         Ecraser les fichiers de sortie existants');
    WriteLn(' -k, --keep          Conserver les fichiers source');
    WriteLn(' -q, --quiet         Supprimer les diagnostics non critiques');
    WriteLn(' -s, --small         Mode de compatibilite a memoire bornee');
    WriteLn(' -t, --test          Verifier le flux et son CRC');
    WriteLn(' -v, --verbose       Augmenter le detail; repeter pour les blocs');
    WriteLn(' -V, --version       Afficher la version');
    WriteLn(' -L, --license       Afficher la licence');
    WriteLn(' -h, --help, /?, /h, /H');
    WriteLn('                     Afficher cette aide');
    WriteLn;
    WriteLn('La compression native utilise des blocs de 512 octets maximum.');
    WriteLn('Le niveau choisi est inscrit dans l''entete du flux.');
  End;
End;

BEGIN
  FileCount:=0;
  BlockFactor:=9;
  DecompressMode:=False;
  TestMode:=False;
  WriteStdout:=False;
  ForceOutput:=False;
  KeepInput:=False;
  Quiet:=False;
  VerboseLevel:=0;
  CompressionRequested:=False;
  CompressionMode:=False;
  I:=1;
  While I<=ParamCount Do Begin
    Argument:=ParamStr(I);
    If(Argument='--help')or(Argument='-h')or(Argument='/?')or
      (Argument='/h')or(Argument='/H')Then Begin
      PrintHelp;
      Halt(0);
    End Else If(Argument='--version')or(Argument='-V')Then Begin
      WriteLn('bzip2 (LINUX-0) 1.0');
      Halt(0);
    End Else If(Argument='--compress')Then CompressionRequested:=True Else
    If(Argument='-L')or(Argument='--license')Then Begin
      WriteLn('bzip2 (LINUX-0) 1.0');
      WriteLn('Decompression subset based on the bzip2 stream format.');
      Halt(0);
    End Else If(Argument='--decompress')Then DecompressMode:=True Else
    If(Argument='--test')Then TestMode:=True Else
    If(Argument='--stdout')Then WriteStdout:=True Else
    If(Argument='--force')Then ForceOutput:=True Else
    If(Argument='--keep')Then KeepInput:=True Else
    If(Argument='--quiet')Then Quiet:=True Else
    If(Argument='--verbose')Then Inc(VerboseLevel) Else
    If(Argument='--best')Then BlockFactor:=9 Else
    If(Argument='--fast')Then BlockFactor:=1 Else
    If(Argument='--small')Then Begin
    End Else
    If(Length(Argument)=2)and(Argument[1]='-')and
      (Argument[2]in['1'..'9'])Then BlockFactor:=Ord(Argument[2])-Ord('0') Else
    If(Argument='-d')Then DecompressMode:=True Else
    If(Argument='-t')Then TestMode:=True Else
    If(Argument='-c')Then WriteStdout:=True Else
    If(Argument='-f')Then ForceOutput:=True Else
    If(Argument='-k')Then KeepInput:=True Else
    If(Argument='-q')Then Quiet:=True Else
    If(Argument='-s')Then Begin
    End Else
    If(Argument='-z')Then CompressionRequested:=True Else
    If(Length(Argument)>1)and(Argument[1]='-')Then Begin
      For J:=2 to Length(Argument)Do Begin
        If Argument[J]='d'Then DecompressMode:=True Else
        If Argument[J]='t'Then TestMode:=True Else
        If Argument[J]='c'Then WriteStdout:=True Else
        If Argument[J]='f'Then ForceOutput:=True Else
        If Argument[J]='k'Then KeepInput:=True Else
        If Argument[J]='q'Then Quiet:=True Else
        If Argument[J]='s'Then Begin
        End Else If Argument[J]='v'Then Inc(VerboseLevel) Else
        If Argument[J]='z'Then CompressionRequested:=True Else
        If Argument[J]in['1'..'9']Then BlockFactor:=Ord(Argument[J])-Ord('0')
        Else Fail('option inconnue: '+Argument);
      End;
    End Else Begin
      If FileCount>=MaxFiles Then Fail('trop de fichiers');
      Inc(FileCount);
      InputFiles[FileCount]:=Argument;
    End;
    Inc(I);
  End;
  If TestMode and CompressionRequested Then
    Fail('options de compression incompatibles avec -t');
  If DecompressMode and CompressionRequested Then
    Fail('options -d et -z incompatibles');
  If TestMode Then DecompressMode:=True;
  CompressionMode:=Not DecompressMode and Not TestMode;
  If FileCount=0 Then Fail('un fichier bzip2 est requis dans ce sous-ensemble');
  For FileIndex:=1 to FileCount Do Begin
    If CompressionMode Then CompressOneFile(InputFiles[FileIndex])
                       Else ProcessOneFile(InputFiles[FileIndex]);
  End;
END.
