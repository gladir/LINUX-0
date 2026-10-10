{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2026
  @website(https://www.gladir.com/linux-0)
  @abstract(Compress a file to Unix .Z format using LZW)
}

Program PCAT(Input,Output);

Uses DOS;

Const
  MaxBits=12;
  FirstCode=257;
  MaxCodes=1 shl MaxBits;
  HashSize=5003;
  BufferSize=2048;

Type
  TInputBuffer=Array[0..BufferSize-1]Of Byte;
  TOutputBuffer=Array[0..BufferSize-1]Of Byte;
  THashKeyArray=Array[0..HashSize-1]Of LongInt;
  THashCodeArray=Array[0..HashSize-1]Of Word;

Var
  InputFile,OutputFile:File;
  InputBuffer:TInputBuffer;
  OutputBuffer:TOutputBuffer;
  HashKeys:THashKeyArray;
  HashCodes:THashCodeArray;
  SourceName,OutputName,LanguageCode:String;
  InputLength,InputPosition,OutputPosition:Word;
  InputReadCount,WriteCount:Word;
  OriginalSize,CompressedSize,TotalOutput:LongInt;
  PrefixCode,NextCode,CodeWidth,MaxCode:Integer;
  BitByte,BitPosition,InputByte:Byte;
  InputError,OutputError:Boolean;
  SearchRecord:SearchRec;

Procedure ReportError(Const FrenchText,EnglishText:String);
Begin
  If Copy(LanguageCode,1,2)='EN'Then WriteLn('pcat: ',EnglishText)
  Else WriteLn('pcat : ',FrenchText);
End;

Function FileExistsTP(Const Name:String):Boolean;
Begin
  FindFirst(Name,AnyFile,SearchRecord);
  FileExistsTP:=(DosError=0)and((SearchRecord.Attr and Directory)=0);
  {$IFDEF FPC}FindClose(SearchRecord);{$ENDIF}
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
  OutputBuffer[OutputPosition]:=Value;
  Inc(OutputPosition);
  If OutputPosition=BufferSize Then FlushOutputBuffer;
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
  If(CodeWidth<MaxBits)and(NextCode>MaxCode)Then Begin
    FlushCodeByte;
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
  BitByte:=0;
  BitPosition:=0;
End;

Function FindCode(Prefix:Integer; Value:Byte; Var FoundCode:Integer):Boolean;
Var
  HashIndex,ProbeCount:Integer;
  Key:LongInt;
Begin
  Key:=(LongInt(Prefix) shl 8)+Value+1;
  HashIndex:=(LongInt(Prefix)*257+Value)mod HashSize;
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
  HashIndex:=(LongInt(Prefix)*257+Value)mod HashSize;
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
    FlushOutputBuffer;
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
  FlushOutputBuffer;
End;

Procedure PrintHelp;
Begin
  If Copy(LanguageCode,1,2)='EN'Then Begin
    WriteLn('pcat - compress a file using Unix .Z (LZW) format');
    WriteLn('Usage: pcat file');
    WriteLn('Creates file.Z and preserves the original file.');
    WriteLn('If compression does not reduce the size, file.Z is removed.');
  End Else Begin
    WriteLn('pcat - Cette commande permet de compresser un fichier au format Unix .Z (LZW)');
    WriteLn;
    WriteLn('Syntaxe : pcat fichier');
    WriteLn;
    WriteLn('Cree fichier.Z et conserve le fichier original.');
    WriteLn('Si la taille ne diminue pas, le fichier .Z est supprime.');
  End;
End;

Procedure CompressFile;
Var
  ErrorCode:Integer;
Begin
  If(Length(SourceName)>=253)Then Begin
    ReportError('nom de sortie trop long','output filename is too long');
    Halt(1);
  End;
  If(Length(SourceName)>=2)and(Copy(SourceName,Length(SourceName)-1,2)='.Z')Then Begin
    ReportError('le fichier semble deja compresse','file appears to be already compressed');
    Halt(1);
  End;
  Assign(InputFile,SourceName);
  FileMode:=0;
  {$I-}Reset(InputFile,1);{$I+}
  If IOResult<>0 Then Begin
    ReportError('impossible de lire '+SourceName,'cannot read '+SourceName);
    Halt(1);
  End;
  OriginalSize:=FileSize(InputFile);
  OutputName:=SourceName+'.Z';
  If FileExistsTP(OutputName)Then Begin
    Close(InputFile);
    ReportError('le fichier de sortie existe deja : '+OutputName,
                'output file already exists: '+OutputName);
    Halt(1);
  End;
  Assign(OutputFile,OutputName);
  FileMode:=1;
  {$I-}Rewrite(OutputFile,1);{$I+}
  If IOResult<>0 Then Begin
    Close(InputFile);
    ReportError('impossible de creer '+OutputName,'cannot create '+OutputName);
    Halt(1);
  End;
  CompressStream;
  Close(InputFile);
  {$I-}Close(OutputFile);{$I+}
  If(IOResult<>0)or OutputError Then Begin
    {$I-}Erase(OutputFile);{$I+}
    ErrorCode:=IOResult;
    If ErrorCode<>0 Then OutputError:=True;
    ReportError('erreur d''ecriture dans '+OutputName,
                'write error on '+OutputName);
    Halt(1);
  End;
  CompressedSize:=TotalOutput;
  If CompressedSize>=OriginalSize Then Begin
    {$I-}Erase(OutputFile);{$I+}
    If IOResult<>0 Then Begin
      ReportError('impossible de supprimer le resultat inefficace',
                  'cannot remove the larger compressed output');
      Halt(1);
    End;
    If Copy(LanguageCode,1,2)='EN'Then
      WriteLn('pcat: input retained; compression would not reduce its size')
    Else WriteLn('pcat : fichier conserve; la compression ne reduirait pas sa taille');
  End Else If Copy(LanguageCode,1,2)='EN'Then
    WriteLn('pcat: created ',OutputName,' (',CompressedSize,' bytes)')
  Else WriteLn('pcat : fichier cree ',OutputName,' (',CompressedSize,' octets)');
End;

Var
  Argument:String;
Begin
  LanguageCode:=GetEnv('LANGUAGE');
  If ParamCount<>1 Then Begin
    If(ParamCount=1)and((ParamStr(1)='-h')or(ParamStr(1)='--help')or
       (ParamStr(1)='/?'))Then Begin PrintHelp;Halt(0);End;
    If Copy(LanguageCode,1,2)='EN'Then WriteLn('Usage: pcat file')
    Else WriteLn('Syntaxe : pcat fichier');
    Halt(2);
  End;
  Argument:=ParamStr(1);
  If(Argument='-h')or(Argument='--help')or(Argument='/?')Then Begin
    PrintHelp;
    Halt(0);
  End;
  If Argument=''Then Begin
    If Copy(LanguageCode,1,2)='EN'Then WriteLn('pcat: empty filename')
    Else WriteLn('pcat : nom de fichier vide');
    Halt(2);
  End;
  SourceName:=Argument;
  CompressFile;
END.
