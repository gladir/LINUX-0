{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2026
  @website(https://www.gladir.com/linux-0)
  @abstract(Target: Turbo Pascal 7, Free Pascal 3.2)
}

Program ADDR2LINE(Input,Output);

{$A-}

Uses DOS;

Const
  MaxAddresses=32;
  MaxFiles=128;
  MaxDirectories=32;
  MaxOpcodes=32;

Type
  TStringArray=Array[1..MaxAddresses]Of String;
  TLineFileArray=Array[1..MaxFiles]Of String;
  TDirectoryArray=Array[0..MaxDirectories]Of String;
  TDirectoryIndexArray=Array[1..MaxFiles]Of LongInt;
  TOpcodeLengthArray=Array[1..MaxOpcodes]Of Byte;

Var
  ELFFile:File;
  FileName,CurrentParam:String;
  Addresses:TStringArray;
  LineFiles:TLineFileArray;
  LineDirectories:TDirectoryArray;
  LineFileDirectories:TDirectoryIndexArray;
  OpcodeLengths:TOpcodeLengthArray;
  AddressCount,I:Integer;
  ShowAddress,ShowFunction,ShortFileName,Pretty:Boolean;
  ReadError:Boolean;
  ELFClass,ELFData:Byte;
  SectionOffset,SectionSize,AddressValue:LongInt;
  SymbolTableOffset,SymbolTableSize,SymbolEntrySize:LongInt;
  SymbolStringOffset,SymbolStringSize:LongInt;
  ResolvedFile,ResolvedFunction:String;
  ResolvedLine:LongInt;
  AddressFound:Boolean;

Function ReadByte:Byte;
Var
  B:Byte;
  Count:Word;
Begin
  B:=0;
  {$I-}BlockRead(ELFFile,B,1,Count);{$I+}
  If IOResult<>0 Then ReadError:=True;
  If Count<>1 Then ReadError:=True;
  ReadByte:=B;
End;

Function ReadWordLE:Word;
Var
  B0,B1:Byte;
Begin
  B0:=ReadByte;
  B1:=ReadByte;
  ReadWordLE:=Word(B0)+(Word(B1) shl 8);
End;

Function ReadLongLE:LongInt;
Var
  B0,B1,B2,B3:Byte;
Begin
  B0:=ReadByte;
  B1:=ReadByte;
  B2:=ReadByte;
  B3:=ReadByte;
  ReadLongLE:=LongInt(B0)+(LongInt(B1) shl 8)+
              (LongInt(B2) shl 16)+(LongInt(B3) shl 24);
End;

Function ReadLongAt(Offset:LongInt):LongInt;
Begin
  Seek(ELFFile,Offset);
  ReadLongAt:=ReadLongLE;
End;

Function ReadWordAt(Offset:LongInt):Word;
Begin
  Seek(ELFFile,Offset);
  ReadWordAt:=ReadWordLE;
End;

Function ReadStringAt(Offset,MaxLength:LongInt):String;
Var
  S:String;
  B:Byte;
  Count:Integer;
Begin
  S:='';
  Seek(ELFFile,Offset);
  Count:=0;
  Repeat
    B:=ReadByte;
    If(B=0)or ReadError Then Break;
    If Length(S)<255 Then S:=S+Chr(B);
    Inc(Count);
  Until Count>=MaxLength;
  ReadStringAt:=S;
End;

Function ReadCString(EndPosition:LongInt):String;
Var
  S:String;
  B:Byte;
Begin
  S:='';
  While(FilePos(ELFFile)<EndPosition)and Not ReadError Do Begin
    B:=ReadByte;
    If B=0 Then Break;
    If Length(S)<255 Then S:=S+Chr(B);
  End;
  ReadCString:=S;
End;

Function ReadULEB(EndPosition:LongInt):LongInt;
Var
  B:Byte;
  ShiftCount:Integer;
  Value:LongInt;
Begin
  Value:=0;
  ShiftCount:=0;
  Repeat
    If(FilePos(ELFFile)>=EndPosition)or ReadError Then Begin
      ReadError:=True;
      Break;
    End;
    B:=ReadByte;
    If ShiftCount<32 Then Value:=Value or (LongInt(B and $7F) shl ShiftCount);
    Inc(ShiftCount,7);
  Until(B and $80)=0;
  ReadULEB:=Value;
End;

Function ReadSLEB(EndPosition:LongInt):LongInt;
Var
  B:Byte;
  ShiftCount:Integer;
  Value:LongInt;
Begin
  Value:=0;
  ShiftCount:=0;
  Repeat
    If(FilePos(ELFFile)>=EndPosition)or ReadError Then Begin
      ReadError:=True;
      Break;
    End;
    B:=ReadByte;
    If ShiftCount<32 Then Value:=Value or (LongInt(B and $7F) shl ShiftCount);
    Inc(ShiftCount,7);
  Until(B and $80)=0;
  If(ShiftCount<32)and((B and $40)<>0)Then
    Value:=Value or (LongInt(-1) shl ShiftCount);
  ReadSLEB:=Value;
End;

Function ParseAddress(Const S:String; Var Address:LongInt):Boolean;
Var
  I,Digit:Integer;
  C:Char;
  Value:LongInt;
Begin
  ParseAddress:=False;
  I:=1;
  If Copy(S,1,2)='0x'Then I:=3 Else
  If Copy(S,1,2)='0X'Then I:=3;
  If I>Length(S)Then Exit;
  Value:=0;
  While I<=Length(S)Do Begin
    C:=S[I];
    If C in['0'..'9']Then Digit:=Ord(C)-Ord('0') Else
    If C in['a'..'f']Then Digit:=Ord(C)-Ord('a')+10 Else
    If C in['A'..'F']Then Digit:=Ord(C)-Ord('A')+10 Else Exit;
    If Value>134217727 Then Exit;
    Value:=Value*16+Digit;
    Inc(I);
  End;
  Address:=Value;
  ParseAddress:=True;
End;

Function HexAddress(Value:LongInt):String;
Const
  Digits:Array[0..15]Of Char='0123456789abcdef';
Var
  S:String;
  R:Integer;
Begin
  S:='';
  If Value=0 Then S:='0';
  While Value>0 Do Begin
    R:=Value Mod 16;
    S:=Digits[R]+S;
    Value:=Value Div 16;
  End;
  HexAddress:='0x'+S;
End;

Function FindDebugLineSection:Boolean;
Var
  SectionTable,NameTableOffset,NameTableSize:LongInt;
  SectionEntry,SectionNameOffset,EntryNameOffset:LongInt;
  EntryOffset,EntrySize,LinkedStringIndex,LinkedStringEntry:LongInt;
  SectionEntrySize,SectionCount,NameTableIndex,Index:Word;
  SectionName:String;
Begin
  FindDebugLineSection:=False;
  SectionOffset:=0;
  SectionSize:=0;
  SymbolTableOffset:=0;
  SymbolTableSize:=0;
  SymbolEntrySize:=0;
  SymbolStringOffset:=0;
  SymbolStringSize:=0;
  SectionTable:=ReadLongAt(32);
  SectionEntrySize:=ReadWordAt(46);
  SectionCount:=ReadWordAt(48);
  NameTableIndex:=ReadWordAt(50);
  If(SectionTable<=0)or(SectionEntrySize<40)or(SectionCount=0)Then Exit;
  If NameTableIndex>=SectionCount Then Exit;
  SectionEntry:=SectionTable+LongInt(NameTableIndex)*SectionEntrySize;
  NameTableOffset:=ReadLongAt(SectionEntry+16);
  NameTableSize:=ReadLongAt(SectionEntry+20);
  If(NameTableOffset<0)or(NameTableSize<0)Then Exit;
  For Index:=0 to SectionCount-1 Do Begin
    SectionEntry:=SectionTable+LongInt(Index)*SectionEntrySize;
    SectionNameOffset:=ReadLongAt(SectionEntry);
    EntryOffset:=ReadLongAt(SectionEntry+16);
    EntrySize:=ReadLongAt(SectionEntry+20);
    If(SectionNameOffset>=0)and(SectionNameOffset<NameTableSize)Then Begin
      EntryNameOffset:=NameTableOffset+SectionNameOffset;
      SectionName:=ReadStringAt(EntryNameOffset,NameTableSize-SectionNameOffset);
      If SectionName='.debug_line'Then Begin
        SectionOffset:=EntryOffset;
        SectionSize:=EntrySize;
        FindDebugLineSection:=True;
      End
       Else If(SectionName='.symtab')or(SectionName='.dynsym')Then Begin
        If(SectionName='.symtab')or(SymbolTableOffset=0)Then Begin
          LinkedStringIndex:=ReadLongAt(SectionEntry+24);
          EntrySize:=ReadLongAt(SectionEntry+20);
          SymbolEntrySize:=ReadLongAt(SectionEntry+36);
          If(LinkedStringIndex>=0)and(LinkedStringIndex<SectionCount)Then Begin
            LinkedStringEntry:=SectionTable+
                               LinkedStringIndex*SectionEntrySize;
            SymbolTableOffset:=ReadLongAt(SectionEntry+16);
            SymbolTableSize:=EntrySize;
            SymbolStringOffset:=ReadLongAt(LinkedStringEntry+16);
            SymbolStringSize:=ReadLongAt(LinkedStringEntry+20);
          End;
        End;
      End;
    End;
  End;
End;

Function FindFunctionName(Target:LongInt):String;
Var
  EntryOffset,NameOffset,Value,Size:LongInt;
  EntryCount,Index:LongInt;
  Info:Byte;
  BestValue:LongInt;
  Candidate,BestName:String;
Begin
  BestName:='??';
  BestValue:=-1;
  If(SymbolTableOffset=0)or(SymbolEntrySize<16)Then Begin
    FindFunctionName:=BestName;
    Exit;
  End;
  EntryCount:=SymbolTableSize Div SymbolEntrySize;
  For Index:=0 to EntryCount-1 Do Begin
    EntryOffset:=SymbolTableOffset+Index*SymbolEntrySize;
    NameOffset:=ReadLongAt(EntryOffset);
    Value:=ReadLongAt(EntryOffset+4);
    Size:=ReadLongAt(EntryOffset+8);
    Seek(ELFFile,EntryOffset+12);
    Info:=ReadByte;
    If((Info and $0F)=2)and(NameOffset>0)and(NameOffset<SymbolStringSize)and
      (Value>=0)and(Value<=Target)and(Value>=BestValue)Then Begin
      If(Size=0)or(Target<Value+Size)Then Begin
        Candidate:=ReadStringAt(SymbolStringOffset+NameOffset,
                                SymbolStringSize-NameOffset);
        If Candidate<>''Then Begin
          BestName:=Candidate;
          BestValue:=Value;
        End;
      End;
    End;
  End;
  FindFunctionName:=BestName;
End;

Function JoinSourcePath(Const Directory,SourceName:String):String;
Begin
  If(Directory='')or(Directory='.')Then JoinSourcePath:=SourceName
  Else If(Directory[Length(Directory)]in['/','\'])Then
    JoinSourcePath:=Directory+SourceName
  Else JoinSourcePath:=Directory+'/'+SourceName;
End;

Function BaseName(Const S:String):String;
Var
  I,Start:Integer;
Begin
  Start:=1;
  For I:=1 to Length(S)Do
    If S[I]in['/','\']Then Start:=I+1;
  BaseName:=Copy(S,Start,Length(S));
End;

Procedure ResolveAddress(Target:LongInt; Var Found:Boolean);
Var
  UnitEnd,HeaderEnd,ExtendedEnd:LongInt;
  InitialLength,HeaderLength,ExtendedLength,Address:LongInt;
  LineNumber,FileNumber,DirectoryNumber,PreviousAddress:LongInt;
  PreviousLine,PreviousFile:LongInt;
  Version:Word;
  OpcodeBase,LineRange,MinimumInstruction:Byte;
  Opcode,SubOpcode,OperandCount,AdjustedOpcode:Byte;
  LineBase,LineIncrement:Integer;
  DirectoryCount,SourceFileCount,K:Integer;
  HavePrevious,ExtendedOpcode:Boolean;
  TempName:String;
  QueryResult:Boolean;
Begin
  Found:=False;
  QueryResult:=False;
  If SectionSize<=0 Then Exit;
  Seek(ELFFile,SectionOffset);
  While(FilePos(ELFFile)<SectionOffset+SectionSize)and Not ReadError Do Begin
    InitialLength:=ReadLongLE;
    If ReadError Then Exit;
    If InitialLength=0 Then Continue;
    If InitialLength<0 Then Exit;
    UnitEnd:=FilePos(ELFFile)+InitialLength;
    If UnitEnd>SectionOffset+SectionSize Then Exit;
    Version:=ReadWordLE;
    If(Version<2)or(Version>4)Then Begin
      Seek(ELFFile,UnitEnd);
      Continue;
    End;
    HeaderLength:=ReadLongLE;
    If(HeaderLength<0)or(FilePos(ELFFile)+HeaderLength>UnitEnd)Then Exit;
    HeaderEnd:=FilePos(ELFFile)+HeaderLength;
    MinimumInstruction:=ReadByte;
    If Version=4 Then ReadByte;
    ReadByte;
    LineBase:=ReadByte;
    If LineBase>=128 Then Dec(LineBase,256);
    LineRange:=ReadByte;
    OpcodeBase:=ReadByte;
    If(OpcodeBase=0)or(LineRange=0)Then Exit;
    For K:=1 to OpcodeBase-1 Do Begin
      If K<=MaxOpcodes Then OpcodeLengths[K]:=ReadByte
      Else ReadByte;
    End;
    For K:=0 to MaxDirectories Do LineDirectories[K]:='';
    DirectoryCount:=0;
    Repeat
      TempName:=ReadCString(HeaderEnd);
      If TempName=''Then Break;
      If DirectoryCount<MaxDirectories Then Begin
        Inc(DirectoryCount);
        LineDirectories[DirectoryCount]:=TempName;
      End;
    Until(FilePos(ELFFile)>=HeaderEnd)or ReadError;
    For K:=1 to MaxFiles Do Begin
      LineFiles[K]:='';
      LineFileDirectories[K]:=0;
    End;
    SourceFileCount:=0;
    Repeat
      TempName:=ReadCString(HeaderEnd);
      If TempName=''Then Break;
      If SourceFileCount<MaxFiles Then Begin
        Inc(SourceFileCount);
        LineFiles[SourceFileCount]:=TempName;
        LineFileDirectories[SourceFileCount]:=ReadULEB(HeaderEnd);
        ReadULEB(HeaderEnd);
        ReadULEB(HeaderEnd);
      End
       Else Begin
        ReadULEB(HeaderEnd);
        ReadULEB(HeaderEnd);
        ReadULEB(HeaderEnd);
      End;
    Until(FilePos(ELFFile)>=HeaderEnd)or ReadError;
    Seek(ELFFile,HeaderEnd);
    Address:=0;
    FileNumber:=1;
    LineNumber:=1;
    PreviousAddress:=0;
    PreviousLine:=0;
    PreviousFile:=0;
    HavePrevious:=False;
    While(FilePos(ELFFile)<UnitEnd)and Not ReadError and Not QueryResult Do Begin
      Opcode:=ReadByte;
      SubOpcode:=255;
      ExtendedOpcode:=False;
      If Opcode=0 Then Begin
        ExtendedOpcode:=True;
        ExtendedLength:=ReadULEB(UnitEnd);
        If(ExtendedLength<=0)or(ReadError)Then Break;
        ExtendedEnd:=FilePos(ELFFile)+ExtendedLength;
        SubOpcode:=ReadByte;
        Case SubOpcode Of
          1:Begin
            If HavePrevious and(Target>=PreviousAddress)and(Target<Address)Then Begin
              QueryResult:=True;
            End;
            HavePrevious:=False;
            Address:=0;
            FileNumber:=1;
            LineNumber:=1;
          End;
          2:Address:=ReadLongLE;
          3:Begin
            TempName:=ReadCString(ExtendedEnd);
            ReadULEB(ExtendedEnd);
            ReadULEB(ExtendedEnd);
            ReadULEB(ExtendedEnd);
            If(SourceFileCount<MaxFiles)and(TempName<>'')Then Begin
              Inc(SourceFileCount);
              LineFiles[SourceFileCount]:=TempName;
              LineFileDirectories[SourceFileCount]:=0;
            End;
          End;
          Else Begin
          End;
        End;
        If ExtendedOpcode and(FilePos(ELFFile)<ExtendedEnd)Then
          Seek(ELFFile,ExtendedEnd);
      End
       Else If Opcode<OpcodeBase Then Begin
        Case Opcode Of
          1:Begin
            If HavePrevious and(Target>=PreviousAddress)and(Target<Address)Then
              QueryResult:=True;
            If Not QueryResult Then Begin
              PreviousAddress:=Address;
              PreviousLine:=LineNumber;
              PreviousFile:=FileNumber;
              HavePrevious:=True;
            End;
          End;
          2:Address:=Address+ReadULEB(UnitEnd)*MinimumInstruction;
          3:LineNumber:=LineNumber+ReadSLEB(UnitEnd);
          4:FileNumber:=ReadULEB(UnitEnd);
          5:ReadULEB(UnitEnd);
          6:Begin
          End;
          7:Begin
            If HavePrevious and(Target>=PreviousAddress)and(Target<Address)Then
              QueryResult:=True;
            If Not QueryResult Then Begin
              PreviousAddress:=Address;
              PreviousLine:=LineNumber;
              PreviousFile:=FileNumber;
              HavePrevious:=True;
            End;
            Address:=Address+((255-OpcodeBase)div LineRange)*MinimumInstruction;
          End;
          8:Address:=Address+((255-OpcodeBase)div LineRange)*MinimumInstruction;
          9:Address:=Address+ReadWordLE;
          Else Begin
            OperandCount:=1;
            If Opcode-1<=MaxOpcodes Then OperandCount:=OpcodeLengths[Opcode-1];
            For K:=1 to OperandCount Do ReadULEB(UnitEnd);
          End;
        End;
      End
       Else Begin
        AdjustedOpcode:=Opcode-OpcodeBase;
        Address:=Address+(AdjustedOpcode div LineRange)*MinimumInstruction;
        LineIncrement:=LineBase+(AdjustedOpcode mod LineRange);
        LineNumber:=LineNumber+LineIncrement;
        If HavePrevious and(Target>=PreviousAddress)and(Target<Address)Then
          QueryResult:=True;
        If Not QueryResult Then Begin
          PreviousAddress:=Address;
          PreviousLine:=LineNumber;
          PreviousFile:=FileNumber;
          HavePrevious:=True;
        End;
      End;
      If QueryResult Then Begin
        ResolvedLine:=PreviousLine;
        If(PreviousFile>0)and(PreviousFile<=SourceFileCount)Then Begin
            DirectoryNumber:=LineFileDirectories[PreviousFile];
          If(DirectoryNumber>0)and(DirectoryNumber<=DirectoryCount)Then
              ResolvedFile:=JoinSourcePath(LineDirectories[DirectoryNumber],
                                            LineFiles[PreviousFile])
            Else ResolvedFile:=LineFiles[PreviousFile];
          Found:=True;
        End;
      End;
    End;
    If Found Then Exit;
    Seek(ELFFile,UnitEnd);
  End;
End;

Procedure PrintHelp;
Begin
  If Copy(GetEnv('LANGUAGE'),1,2)='EN'Then Begin
    WriteLn('ADDR2LINE : Convert addresses in an executable to source locations.');
    WriteLn('Syntax: addr2line [-a] [-f] [-s] [-e FILE] ADDRESS...');
    WriteLn(' -e FILE     Executable to inspect (default: a.out)');
    WriteLn(' -a          Display each address');
    WriteLn(' -f          Display the function name when a symbol is available');
    WriteLn(' -s          Display only the source basename');
    WriteLn(' -p          Display each result on one line');
    WriteLn(' -v, --version  Display version');
    WriteLn(' --help      Display this help');
    WriteLn('Support: ELF32 little-endian, DWARF .debug_line versions 2 through 4.');
  End
   Else Begin
    WriteLn('ADDR2LINE : Cette commande permet de convertir les adresses en fichiers et lignes source.');
    WriteLn;
    WriteLn('Syntaxe : addr2line [-a] [-f] [-s] [-e FICHIER] ADRESSE...');
    WriteLn;
    WriteLn(' -e FICHIER  Executable a examiner (defaut : a.out)');
    WriteLn(' -a          Affiche chaque adresse');
    WriteLn(' -f          Affiche le nom de fonction si un symbole existe');
    WriteLn(' -s          Affiche seulement le nom de base du fichier source');
    WriteLn(' -p          Affiche chaque resultat sur une ligne');
    WriteLn(' -v, --version  Affiche la version');
    WriteLn(' --help      Affiche cette aide');
    WriteLn('Support : ELF32 little-endian avec DWARF .debug_line versions 2 a 4.');
  End;
End;

BEGIN
  FileName:='a.out';
  AddressCount:=0;
  ShowAddress:=False;
  ShowFunction:=False;
  ShortFileName:=False;
  Pretty:=False;
  If ParamCount=0 Then Begin
    PrintHelp;
    Halt(0);
  End;
  I:=1;
  While I<=ParamCount Do Begin
    CurrentParam:=ParamStr(I);
    If(CurrentParam='--help')or(CurrentParam='-h')or(CurrentParam='/?')or
      (CurrentParam='/h')or(CurrentParam='/H')Then Begin
      PrintHelp;
      Halt(0);
    End
    Else If(CurrentParam='--version')or(CurrentParam='-V')or
      (CurrentParam='-v')Then Begin
      WriteLn('addr2line (LINUX-0) 1.0');
      Halt(0);
    End
     Else If(CurrentParam='-a')or(CurrentParam='--addresses')Then
      ShowAddress:=True
     Else If(CurrentParam='-f')or(CurrentParam='--functions')Then
      ShowFunction:=True
     Else If(CurrentParam='-s')or(CurrentParam='--basenames')Then
      ShortFileName:=True
     Else If(CurrentParam='-p')or(CurrentParam='--pretty-print')Then
      Pretty:=True
    Else If(CurrentParam='-e')or(CurrentParam='--exe')Then Begin
      Inc(I);
      If I>ParamCount Then Begin
        WriteLn('Erreur : fichier executable manquant apres -e');
        Halt(2);
      End;
      FileName:=ParamStr(I);
    End
    Else If Copy(CurrentParam,1,6)='--exe='Then
     FileName:=Copy(CurrentParam,7,255)
     Else If(Length(CurrentParam)>1)and(CurrentParam[1]='-')Then Begin
      WriteLn('Erreur : option inconnue : ',CurrentParam);
      Halt(2);
    End
     Else Begin
      If AddressCount>=MaxAddresses Then Begin
        WriteLn('Erreur : trop d''adresses');
        Halt(2);
      End;
      Inc(AddressCount);
      Addresses[AddressCount]:=CurrentParam;
    End;
    Inc(I);
  End;

  If AddressCount=0 Then Begin
    WriteLn('Erreur : adresse manquante');
    Halt(2);
  End;
  {$I-}Assign(ELFFile,FileName);
  Reset(ELFFile,1);{$I+}
  If IOResult<>0 Then Begin
    WriteLn('Erreur : impossible de lire ',FileName);
    Halt(1);
  End;
  Seek(ELFFile,0);
  ReadError:=False;
  If(ReadByte<>$7F)or(ReadByte<>Ord('E'))or(ReadByte<>Ord('L'))or
    (ReadByte<>Ord('F'))Then Begin
    Close(ELFFile);
    WriteLn('Erreur : fichier ELF invalide');
    Halt(1);
  End;
  ELFClass:=ReadByte;
  ELFData:=ReadByte;
  If(ELFClass<>1)or(ELFData<>1)Then Begin
    Close(ELFFile);
    WriteLn('Erreur : seuls les fichiers ELF32 little-endian sont pris en charge');
    Halt(1);
  End;
  If Not FindDebugLineSection Then Begin
    SectionOffset:=0;
    SectionSize:=0;
  End;

  For I:=1 to AddressCount Do Begin
    ResolvedFile:='??';
    ResolvedLine:=0;
    ResolvedFunction:='??';
    ReadError:=False;
    If Not ParseAddress(Addresses[I],AddressValue)Then Begin
      WriteLn('Erreur : adresse hexadecimale invalide : ',Addresses[I]);
      Halt(2);
    End;
    ResolveAddress(AddressValue,AddressFound);
    If ShowFunction Then ResolvedFunction:=FindFunctionName(AddressValue);
    If ShortFileName Then ResolvedFile:=BaseName(ResolvedFile);
    If Pretty Then Begin
      If ShowAddress Then Write(HexAddress(AddressValue),': ');
      If ShowFunction Then Write(ResolvedFunction,' at ');
    End
     Else Begin
      If ShowAddress Then WriteLn(HexAddress(AddressValue));
      If ShowFunction Then WriteLn(ResolvedFunction);
    End;
    WriteLn(ResolvedFile,':',ResolvedLine);
  End;
  Close(ELFFile);
END.
