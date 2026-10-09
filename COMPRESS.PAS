{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2026
  @website(https://www.gladir.com/linux-0)
  @abstract(Target: Turbo Pascal 7, Free Pascal 3.2)
}

Program COMPRESS(Input,Output);

Uses DOS;

Const
  MaxFiles=32;
  MaxBits=12;
  FirstCode=257;
  MaxCodes=1 shl MaxBits;
  HashSize=5003;
  BufferSize=2048;

Type
  TFileArray=Array[1..MaxFiles]Of String;
  TInputBuffer=Array[0..BufferSize-1]Of Byte;
  TOutputBuffer=Array[0..BufferSize-1]Of Byte;
  THashKeyArray=Array[0..HashSize-1]Of LongInt;
  THashCodeArray=Array[0..HashSize-1]Of Word;

Var
  InputFile,OutputFile:File;
  FileNames:TFileArray;
  InputBuffer:TInputBuffer;
  OutputBuffer:TOutputBuffer;
  HashKeys:THashKeyArray;
  HashCodes:THashCodeArray;
  OutputName,Argument,LanguageCode:String;
  FileCount,ArgumentIndex,FileIndex:Integer;
  InputLength,InputPosition,OutputPosition:Word;
  InputReadCount,WriteCount:Word;
  OriginalSize,CompressedSize,TotalOutput:LongInt;
  PrefixCode,NextCode,CodeWidth,MaxCode,CodeGroupCount:Integer;
  BitByte,BitPosition,InputByte:Byte;
  StdoutMode,ForceMode,VerboseMode,EndOptions:Boolean;
  InputError,OutputError,ErrorFound:Boolean;
  Search:SearchRec;

Procedure WriteError(Const MessageFrench,MessageEnglish:String);
Begin
  If Copy(LanguageCode,1,2)='EN'Then
    WriteLn('compress: ',MessageEnglish)
  Else WriteLn('compress : ',MessageFrench);
End;

Procedure PrintHelp;
Begin
  If Copy(LanguageCode,1,2)='EN'Then Begin
    WriteLn('COMPRESS : Compress files using the Unix .Z LZW format.');
    WriteLn('Syntax: compress [-c] [-f] [-v] file ...');
    WriteLn(' -c  Write compressed data to standard output');
    WriteLn(' -f  Force compression and overwrite existing .Z files');
    WriteLn(' -v  Report the compression ratio');
    WriteLn(' --help, --version  Display help or version information');
    WriteLn('The native encoder uses 12-bit LZW codes.');
  End Else Begin
    WriteLn('COMPRESS : Cette commande permet de compresser des fichiers au format LZW Unix .Z.');
    WriteLn;
    WriteLn('Syntaxe : compress [-c] [-f] [-v] fichier ...');
    WriteLn;
    WriteLn(' -c  Ecrire les donnees compressees sur la sortie standard');
    WriteLn(' -f  Forcer la compression et ecraser les fichiers .Z existants');
    WriteLn(' -v  Afficher le taux de compression');
    WriteLn(' --help, --version  Afficher l''aide ou la version');
    WriteLn;
    WriteLn('Le compresseur natif utilise des codes LZW de 12 bits.');
  End;
End;

Procedure OptionError(Const MessageFrench,MessageEnglish:String);
Begin
  WriteError(MessageFrench,MessageEnglish);
  Halt(2);
End;

Function FileExistsTP(Const Name:String):Boolean;
Begin
  FindFirst(Name,AnyFile,Search);
  FileExistsTP:=(DosError=0)and((Search.Attr and Directory)=0);
  {$IFDEF FPC}FindClose(Search);{$ENDIF}
End;

Function EraseFile(Const Name:String):Boolean;
Var
  FileToErase:File;
  EraseOK:Boolean;
Begin
  Assign(FileToErase,Name);
  {$I-}Erase(FileToErase);{$I+}
  EraseOK:=IOResult=0;
  EraseFile:=EraseOK;
  If Not EraseOK Then Begin
    WriteError('impossible de supprimer '+Name,
               'cannot remove '+Name);
    ErrorFound:=True;
  End;
End;

Function ReadInputByte(Var Value:Byte):Boolean;
Begin
  If InputPosition>=InputLength Then Begin
    {$I-}BlockRead(InputFile,InputBuffer,SizeOf(InputBuffer),InputReadCount);{$I+}
    If IOResult<>0 Then Begin
      InputError:=True;
      ReadInputByte:=False;
      Exit;
    End;
    InputLength:=InputReadCount;
    InputPosition:=0;
    If InputLength=0 Then Begin
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
  {$I-}BlockWrite(OutputFile,OutputBuffer,OutputPosition,WriteCount);{$I+}
  If(IOResult<>0)or(WriteCount<>OutputPosition)Then OutputError:=True;
  OutputPosition:=0;
End;

Procedure WriteOutputByte(Value:Byte);
Begin
  Inc(TotalOutput);
  If StdoutMode Then Write(Output,Chr(Value)) Else Begin
    OutputBuffer[OutputPosition]:=Value;
    Inc(OutputPosition);
    If OutputPosition=BufferSize Then FlushOutputBuffer;
  End;
End;

Procedure FlushCodeByte;
Begin
  If BitPosition>0 Then Begin
    WriteOutputByte(BitByte);
    BitByte:=0;
    BitPosition:=0;
  End;
End;

Procedure EmitCode(CodeValue:Integer);
Var
  BitIndex:Integer;
Begin
  For BitIndex:=0 to CodeWidth-1 Do Begin
    If(CodeValue and(1 shl BitIndex))<>0 Then
      BitByte:=BitByte or(1 shl BitPosition);
    Inc(BitPosition);
    If BitPosition=8 Then Begin
      WriteOutputByte(BitByte);
      BitByte:=0;
      BitPosition:=0;
    End;
  End;
  Inc(CodeGroupCount);
  If CodeGroupCount=8 Then CodeGroupCount:=0;
  If(CodeWidth<MaxBits)and(NextCode>MaxCode)Then Begin
    FlushCodeByte;
    CodeGroupCount:=0;
    Inc(CodeWidth);
    MaxCode:=(1 shl CodeWidth)-1;
  End;
End;

Procedure ResetDictionary;
Var
  Index:Integer;
Begin
  For Index:=0 to HashSize-1 Do HashKeys[Index]:=0;
  NextCode:=FirstCode;
  CodeWidth:=9;
  MaxCode:=(1 shl CodeWidth)-1;
  CodeGroupCount:=0;
  BitByte:=0;
  BitPosition:=0;
End;

Function FindCode(Prefix:Integer; Value:Byte; Var FoundCode:Integer):Boolean;
Var
  HashIndex,ProbeCount:Integer;
  Key:LongInt;
Begin
  Key:=(LongInt(Prefix) shl 8)+Value+1;
  HashIndex:=(Prefix*257+Value)mod HashSize;
  ProbeCount:=0;
  While ProbeCount<HashSize Do Begin
    If HashKeys[HashIndex]=Key Then Begin
      FoundCode:=HashCodes[HashIndex];
      FindCode:=True;
      Exit;
    End;
    If HashKeys[HashIndex]=0 Then Begin
      FindCode:=False;
      Exit;
    End;
    Inc(HashIndex);
    If HashIndex=HashSize Then HashIndex:=0;
    Inc(ProbeCount);
  End;
  FindCode:=False;
End;

Procedure AddCode(Prefix:Integer; Value:Byte);
Var
  HashIndex,ProbeCount:Integer;
  Key:LongInt;
Begin
  If NextCode>=MaxCodes Then Exit;
  Key:=(LongInt(Prefix) shl 8)+Value+1;
  HashIndex:=(Prefix*257+Value)mod HashSize;
  ProbeCount:=0;
  While(ProbeCount<HashSize)and(HashKeys[HashIndex]<>0)Do Begin
    Inc(HashIndex);
    If HashIndex=HashSize Then HashIndex:=0;
    Inc(ProbeCount);
  End;
  If ProbeCount>=HashSize Then Exit;
  HashKeys[HashIndex]:=Key;
  HashCodes[HashIndex]:=NextCode;
  Inc(NextCode);
End;

Procedure CompressStream;
Var
  FoundCode:Integer;
Begin
  TotalOutput:=0;
  OutputPosition:=0;
  InputPosition:=0;
  InputLength:=0;
  InputError:=False;
  OutputError:=False;
  WriteOutputByte(31);
  WriteOutputByte(157);
  WriteOutputByte(128+MaxBits);
  ResetDictionary;
  If Not ReadInputByte(InputByte)Then Begin
    If InputError Then OutputError:=True;
    FlushCodeByte;
    If Not StdoutMode Then FlushOutputBuffer;
    Exit;
  End;
  PrefixCode:=InputByte;
  While ReadInputByte(InputByte)Do Begin
    If FindCode(PrefixCode,InputByte,FoundCode)Then
      PrefixCode:=FoundCode
    Else Begin
      EmitCode(PrefixCode);
      AddCode(PrefixCode,InputByte);
      PrefixCode:=InputByte;
    End;
  End;
  If InputError Then OutputError:=True;
  EmitCode(PrefixCode);
  FlushCodeByte;
  If Not StdoutMode Then FlushOutputBuffer;
End;

Function HasZSuffix(Const Name:String):Boolean;
Begin
  HasZSuffix:=(Length(Name)>=2)and(Copy(Name,Length(Name)-1,2)='.Z');
End;

Procedure CompressOneFile(Const Name:String);
Var
  ExistingOutput,KeepSource:Boolean;
  Percent:LongInt;
Begin
  If HasZSuffix(Name)Then Begin
    WriteError('le fichier semble deja compresse : '+Name,
               'file appears to be already compressed: '+Name);
    ErrorFound:=True;
    Exit;
  End;
  Assign(InputFile,Name);
  FileMode:=0;
  {$I-}Reset(InputFile,1);{$I+}
  If IOResult<>0 Then Begin
    WriteError('impossible de lire '+Name,'cannot read '+Name);
    ErrorFound:=True;
    Exit;
  End;
  OriginalSize:=FileSize(InputFile);
  If Length(Name)>253 Then Begin
    Close(InputFile);
    WriteError('nom de sortie trop long pour '+Name,
               'output name is too long for '+Name);
    ErrorFound:=True;
    Exit;
  End;
  OutputName:=Name+'.Z';
  ExistingOutput:=False;
  If Not StdoutMode Then ExistingOutput:=FileExistsTP(OutputName);
  If ExistingOutput and Not ForceMode Then Begin
    Close(InputFile);
    WriteError('le fichier existe deja : '+OutputName,
               'output file already exists: '+OutputName);
    ErrorFound:=True;
    Exit;
  End;
  If ExistingOutput and Not EraseFile(OutputName)Then Begin
    Close(InputFile);
    Exit;
  End;
  If Not StdoutMode Then Begin
    Assign(OutputFile,OutputName);
    FileMode:=1;
    {$I-}Rewrite(OutputFile,1);{$I+}
    If IOResult<>0 Then Begin
      Close(InputFile);
      WriteError('impossible de creer '+OutputName,
                 'cannot create '+OutputName);
      ErrorFound:=True;
      Exit;
    End;
  End;
  CompressStream;
  Close(InputFile);
  If Not StdoutMode Then Begin
    Close(OutputFile);
    CompressedSize:=TotalOutput;
    If OutputError Then Begin
      EraseFile(OutputName);
      WriteError('erreur d''ecriture dans '+OutputName,
                 'write error on '+OutputName);
      ErrorFound:=True;
      Exit;
    End;
    KeepSource:=False;
    If Not ForceMode and(CompressedSize>=OriginalSize)Then Begin
      EraseFile(OutputName);
      KeepSource:=True;
    End;
    If Not KeepSource Then Begin
      EraseFile(Name);
      If VerboseMode Then Begin
        If OriginalSize=0 Then Percent:=0
        Else Percent:=Round((OriginalSize-CompressedSize)*100.0/OriginalSize);
        WriteLn(Name,': ',Percent,'% compression');
      End;
    End Else If VerboseMode Then
      WriteLn(Name,': not compressed (would grow); file retained');
  End;
End;

BEGIN
  LanguageCode:=GetEnv('LANGUAGE');
  FileCount:=0;
  StdoutMode:=False;
  ForceMode:=False;
  VerboseMode:=False;
  ErrorFound:=False;
  EndOptions:=False;
  ArgumentIndex:=1;
  While ArgumentIndex<=ParamCount Do Begin
    Argument:=ParamStr(ArgumentIndex);
    If Not EndOptions and(Argument='--')Then EndOptions:=True Else
    If Not EndOptions and((Argument='--help')or(Argument='-h')or
      (Argument='/?')or(Argument='/h')or(Argument='/H'))Then Begin
      PrintHelp;
      Halt(0);
    End Else If Not EndOptions and
      ((Argument='--version')or(Argument='-V'))Then Begin
      WriteLn('compress (LINUX-0) 1.0');
      Halt(0);
    End Else If Not EndOptions and((Argument='-c')or
      (Argument='--stdout'))Then StdoutMode:=True Else
    If Not EndOptions and((Argument='-f')or
      (Argument='--force'))Then ForceMode:=True Else
    If Not EndOptions and((Argument='-v')or
      (Argument='--verbose'))Then VerboseMode:=True Else
    If Not EndOptions and(Length(Argument)>1)and
      (Argument[1]='-')Then Begin
      If(Length(Argument)>2)and(Argument[2]='-')Then
        OptionError('option inconnue : '+Argument,'unknown option: '+Argument);
      For FileIndex:=2 to Length(Argument)Do Begin
        If Argument[FileIndex]='c'Then StdoutMode:=True Else
        If Argument[FileIndex]='f'Then ForceMode:=True Else
        If Argument[FileIndex]='v'Then VerboseMode:=True Else
          OptionError('option inconnue : '+Argument,
                      'unknown option: '+Argument);
      End;
    End Else Begin
      If FileCount>=MaxFiles Then
        OptionError('trop de fichiers','too many files');
      Inc(FileCount);
      FileNames[FileCount]:=Argument;
    End;
    Inc(ArgumentIndex);
  End;
  If FileCount=0 Then Begin
    PrintHelp;
    Halt(2);
  End;
  For FileIndex:=1 to FileCount Do
    CompressOneFile(FileNames[FileIndex]);
  If ErrorFound Then Halt(1);
END.