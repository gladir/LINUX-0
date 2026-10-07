{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2026
  @website(https://www.gladir.com/linux-0)
  @abstract(Target: Turbo Pascal 7, Free Pascal 3.2)
}

Program ANYTOPNM(Input,Output);

Uses DOS;

Const
  CopyBufferSize=4096;
  MaxPaletteEntries=256;

Type
  TByteBuffer=Array[1..CopyBufferSize]Of Byte;

Var
  ImageFile:File;
  Buffer:TByteBuffer;
  PaletteRed,PaletteGreen,PaletteBlue:Array[0..MaxPaletteEntries-1]Of Byte;
  FileName:String;
  BytesRead:Word;
  FileLength,PixelOffset,DIBSize,Width,Height,RowSize:LongInt;
  PaletteCount,ColorCount,X,Y,PhysicalRow,BitCount,Compression:LongInt;
  B,G,R,PixelByte,PaletteIndex,ShiftCount:Byte;
  TopDown,ValidBMP:Boolean;
  EnglishHelp:Boolean;

Function ReadAt(Offset:LongInt):Byte;
Var
  Value:Byte;
  Count:Word;
Begin
  Value:=0;
  If(Offset<0)or(Offset>=FileLength)Then Begin
    ValidBMP:=False;
    ReadAt:=0;
    Exit;
  End;
  Seek(ImageFile,Offset);
  BlockRead(ImageFile,Value,1,Count);
  If Count<>1 Then ValidBMP:=False;
  ReadAt:=Value;
End;

Function ReadWordAt(Offset:LongInt):Word;
Begin
  ReadWordAt:=Word(ReadAt(Offset))+Word(ReadAt(Offset+1))*256;
End;

Function ReadLongAt(Offset:LongInt):LongInt;
Var
  B0,B1,B2,B3:LongInt;
Begin
  B0:=ReadAt(Offset);
  B1:=ReadAt(Offset+1);
  B2:=ReadAt(Offset+2);
  B3:=ReadAt(Offset+3);
  ReadLongAt:=B0+(B1 shl 8)+(B2 shl 16)+(B3 shl 24);
End;

Function StrToUpper(S:String):String;
Var
  I:Integer;
Begin
  For I:=1 to Length(S)Do
    If S[I]in['a'..'z']Then S[I]:=Chr(Ord(S[I])-32);
  StrToUpper:=S;
End;

Procedure WriteBinaryByte(Value:Byte);
Begin
  Write(Output,Chr(Value));
End;

Procedure CopyNetpbm;
Var
  Count,I:Word;
Begin
  Seek(ImageFile,0);
  Repeat
    BlockRead(ImageFile,Buffer,SizeOf(Buffer),Count);
    For I:=1 to Count Do WriteBinaryByte(Buffer[I]);
  Until Count<SizeOf(Buffer);
End;

Procedure ReadBMPHeader;
Var
  SignedHeight:LongInt;
  PaletteOffset:LongInt;
  I:Integer;
Begin
  ValidBMP:=True;
  FileLength:=FileSize(ImageFile);
  PixelOffset:=ReadLongAt(10);
  DIBSize:=ReadLongAt(14);
  Width:=ReadLongAt(18);
  SignedHeight:=ReadLongAt(22);
  If SignedHeight<0 Then Begin
    TopDown:=True;
    Height:=-SignedHeight;
  End Else Begin
    TopDown:=False;
    Height:=SignedHeight;
  End;
  If ReadWordAt(26)<>1 Then ValidBMP:=False;
  BitCount:=ReadWordAt(28);
  Compression:=ReadLongAt(30);
  ColorCount:=ReadLongAt(46);
  If(DIBSize<40)or(DIBSize>FileLength-14)or(Width<=0)or(Height<=0)or
    (Width>1000000)or(Height>1000000)or(Compression<>0)or
    Not(BitCount in[1,4,8,24,32])Then ValidBMP:=False;
  If Not ValidBMP Then Exit;
  If BitCount<=8 Then Begin
    If ColorCount=0 Then PaletteCount:=1 shl BitCount
                    Else PaletteCount:=ColorCount;
    If(PaletteCount<=0)or(PaletteCount>MaxPaletteEntries)Then Begin
      ValidBMP:=False;
      Exit;
    End;
    PaletteOffset:=14+DIBSize;
    For I:=0 to PaletteCount-1 Do Begin
      PaletteBlue[I]:=ReadAt(PaletteOffset+I*4);
      PaletteGreen[I]:=ReadAt(PaletteOffset+I*4+1);
      PaletteRed[I]:=ReadAt(PaletteOffset+I*4+2);
    End;
  End;
  If Not ValidBMP Then Exit;
  If(PixelOffset<14+DIBSize)or(PixelOffset>FileLength)Then Begin
    ValidBMP:=False;
    Exit;
  End;
  RowSize:=((Width*BitCount+31)div 32)*4;
  If(RowSize<=0)or(Height>(FileLength-PixelOffset)div RowSize)Then
    ValidBMP:=False;
End;

Procedure GetPixel(PhysicalX,PhysicalY:LongInt);
Var
  Offset:LongInt;
Begin
  Offset:=PixelOffset+PhysicalY*RowSize;
  Case BitCount Of
    1:Begin
      PixelByte:=ReadAt(Offset+PhysicalX div 8);
      ShiftCount:=7-(PhysicalX mod 8);
      PaletteIndex:=(PixelByte shr ShiftCount)and 1;
    End;
    4:Begin
      PixelByte:=ReadAt(Offset+PhysicalX div 2);
      If(PhysicalX mod 2)=0Then PaletteIndex:=PixelByte shr 4
                            Else PaletteIndex:=PixelByte and $0F;
    End;
    8:PaletteIndex:=ReadAt(Offset+PhysicalX);
    24:Begin
      Offset:=Offset+PhysicalX*3;
      B:=ReadAt(Offset);
      G:=ReadAt(Offset+1);
      R:=ReadAt(Offset+2);
    End;
    32:Begin
      Offset:=Offset+PhysicalX*4;
      B:=ReadAt(Offset);
      G:=ReadAt(Offset+1);
      R:=ReadAt(Offset+2);
    End;
  End;
  If BitCount<=8 Then Begin
    If PaletteIndex>=PaletteCount Then Begin
      ValidBMP:=False;
      R:=0;
      G:=0;
      B:=0;
    End Else Begin
      R:=PaletteRed[PaletteIndex];
      G:=PaletteGreen[PaletteIndex];
      B:=PaletteBlue[PaletteIndex];
    End;
  End;
End;

Procedure ConvertBMP;
Begin
  ReadBMPHeader;
  If Not ValidBMP Then Begin
    WriteLn(Output,'Erreur : BMP invalide, compresse ou non pris en charge');
    Halt(1);
  End;
  WriteLn(Output,'P6');
  WriteLn(Output,Width,' ',Height);
  WriteLn(Output,'255');
  For Y:=0 to Height-1 Do Begin
    If TopDown Then PhysicalRow:=Y Else PhysicalRow:=Height-1-Y;
    For X:=0 to Width-1 Do Begin
      GetPixel(X,PhysicalRow);
      If Not ValidBMP Then Begin
        WriteLn(Output);
        WriteLn('Erreur : index de palette BMP invalide');
        Halt(1);
      End;
      WriteBinaryByte(R);
      WriteBinaryByte(G);
      WriteBinaryByte(B);
    End;
  End;
End;

Procedure PrintHelp;
Begin
  If EnglishHelp Then Begin
    WriteLn('ANYTOPNM : Convert supported images to portable anymap.');
    WriteLn('Syntax: anytopnm FILE');
    WriteLn('Supported: P1-P6 Netpbm and uncompressed BMP 1/4/8/24/32-bit.');
    WriteLn('Output is written to standard output.');
  End Else Begin
    WriteLn('ANYTOPNM : Cette commande permet de convertir une image prise en charge en format Netpbm.');
    WriteLn;
    WriteLn('Syntaxe : anytopnm FICHIER');
    WriteLn;
    WriteLn('Formats pris en charge : P1-P6 et BMP non compresse 1/4/8/24/32 bits.');
    WriteLn('Le resultat est ecrit sur la sortie standard.');
  End;
End;

BEGIN
  EnglishHelp:=Copy(StrToUpper(GetEnv('LANGUAGE')),1,2)='EN';
  If(ParamCount=0)or(ParamStr(1)='--help')or(ParamStr(1)='-h')or
    (ParamStr(1)='/?')or(ParamStr(1)='/h')or(ParamStr(1)='/H')Then Begin
    PrintHelp;
  End Else If(ParamStr(1)='--version')or(ParamStr(1)='-v')Then
    WriteLn('anytopnm (LINUX-0) 1.0')
  Else If ParamCount<>1 Then Begin
    WriteLn('Erreur : syntaxe : anytopnm fichier');
    Halt(2);
  End Else Begin
    FileName:=ParamStr(1);
    {$I-}Assign(ImageFile,FileName);
    Reset(ImageFile,1);{$I+}
    If IOResult<>0 Then Begin
      WriteLn('Erreur : impossible de lire ',FileName);
      Halt(1);
    End;
    FileLength:=FileSize(ImageFile);
    If FileLength<2 Then Begin
      Close(ImageFile);
      WriteLn('Erreur : format d''image inconnu');
      Halt(1);
    End;
    Seek(ImageFile,0);
    BlockRead(ImageFile,B,1,BytesRead);
    BlockRead(ImageFile,G,1,BytesRead);
    If(B=Ord('P'))and(G in[Ord('1')..Ord('7')])Then CopyNetpbm Else
    If(B=Ord('B'))and(G=Ord('M'))Then ConvertBMP Else Begin
      Close(ImageFile);
      WriteLn('Erreur : format d''image non pris en charge');
      Halt(1);
    End;
    Close(ImageFile);
  End;
END.
