{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2026
  @website(https://www.gladir.com/linux-0)
  @abstract(Replace strings in files or standard input)
}

Program REPLACE(Input,Output);

Uses DOS;

Const
  MaxPairs=16;
  MaxFiles=32;
  InputBufferSize=4096;
  MaxPatternLength=255;
  MaxFileName=255;

Type
  TText=String[MaxPatternLength];
  TFileName=String[MaxFileName];
  TReplacement=Record
    FromText,ToText:TText;
  End;
  TReplacementArray=Array[1..MaxPairs]Of TReplacement;
  TFileArray=Array[1..MaxFiles]Of TFileName;
  TInputBuffer=Array[0..InputBufferSize-1]Of Byte;
  TOutputBuffer=Array[0..InputBufferSize-1]Of Byte;
  TPendingBuffer=Array[0..MaxPatternLength-1]Of Byte;

Var
  Replacements:TReplacementArray;
  FileNames:TFileArray;
  PairCount,FileCount,FileIndex:Integer;
  QuietMode,VerboseMode,DebugMode,English:Boolean;
  ErrorFound,InputIsStandard,OutputIsStandard,InputAtEnd,StreamError:Boolean;
  InputFile,OutputFile:File;
  InputBuffer:TInputBuffer;
  OutputBuffer:TOutputBuffer;
  Pending:TpendingBuffer;
  InputLength,InputPosition,OutputPosition,WriteCount:Word;
  PendingCount,LongestPattern:Integer;
  InputByte:Byte;
  ReplacedCount:LongInt;
  LanguageCode:String[20];
  CurrentInputName:TFileName;

Procedure ReportError(Const FrenchText,EnglishText:TFileName);
Begin
  ErrorFound:=True;
  If QuietMode Then Exit;
  If English Then WriteLn('replace: ',CurrentInputName,': ',EnglishText)
  Else WriteLn('replace : ',CurrentInputName,': ',FrenchText);
End;

Procedure PrintHelp;
Begin
  If English Then Begin
    WriteLn('replace - replace every occurrence of text');
    WriteLn('Usage: replace [-s] [-v] [-#debug_options] from to [from to]... [-- file ...]');
    WriteLn('Without files, reads standard input and writes standard output.');
    WriteLn('Files are replaced only when at least one change was made.');
  End Else Begin
    WriteLn('REPLACE - Cette commande permet de remplacer toutes les occurrences d''une chaine');
    WriteLn;
    WriteLn('Syntaxe : replace [-s] [-v] [-#debug_options] source cible [source cible]... [-- fichier ...]');
    WriteLn;
    WriteLn('Options :');
    WriteLn(' -s  Mode silencieux, ne pas afficher les messages d''information');
    WriteLn(' -v  Mode verbeux, afficher les messages d''information');
    WriteLn(' -#debug_options  Options de debug (ex: -d pour activer le debug)');
    WriteLn;
    WriteLn('Sans fichier, lit l''entree standard et ecrit sur la sortie standard.');
    WriteLn('Un fichier est modifie seulement si au moins un remplacement a eu lieu.');
  End;
End;

Procedure UsageError(Const MessageText:TFileName);
Begin
  If English Then WriteLn('replace: ',MessageText)
  Else WriteLn('replace : ',MessageText);
  Halt(2);
End;

Function FileExists(Const Name:TFileName):Boolean;
Var
  SearchRecord:SearchRec;
Begin
  FindFirst(Name,AnyFile,SearchRecord);
  FileExists:=(DosError=0)and((SearchRecord.Attr and Directory)=0);
  {$IFDEF FPC}FindClose(SearchRecord);{$ENDIF}
End;

Function ReadSourceByte(Var Value:Byte):Boolean;
Var
  Character:Char;
  ReadCount:Word;
Begin
  If InputIsStandard Then Begin
    If EOF(Input)Then Begin
      ReadSourceByte:=False;
      Exit;
    End;
    If Eoln(Input)Then Begin
      ReadLn(Input);
      Value:=10;
    End Else Begin
      Read(Input,Character);
      Value:=Ord(Character);
    End;
    ReadSourceByte:=True;
    Exit;
  End;
  If InputPosition>=InputLength Then Begin
    {$I-}BlockRead(InputFile,InputBuffer,SizeOf(InputBuffer),ReadCount);{$I+}
    If IOResult<>0 Then Begin
      InputAtEnd:=True;
      StreamError:=True;
      ReadSourceByte:=False;
      Exit;
    End;
    InputLength:=ReadCount;
    InputPosition:=0;
    If InputLength=0 Then Begin
      InputAtEnd:=True;
      ReadSourceByte:=False;
      Exit;
    End;
  End;
  Value:=InputBuffer[InputPosition];
  Inc(InputPosition);
  ReadSourceByte:=True;
End;

Procedure FlushOutput;
Begin
  If OutputIsStandard or(OutputPosition=0)Then Exit;
  {$I-}BlockWrite(OutputFile,OutputBuffer,OutputPosition,WriteCount);{$I+}
  If(IOResult<>0)or(WriteCount<>OutputPosition)Then StreamError:=True;
  OutputPosition:=0;
End;

Procedure WriteOutputByte(Value:Byte);
Begin
  If OutputIsStandard Then Write(Output,Chr(Value))
  Else Begin
    OutputBuffer[OutputPosition]:=Value;
    Inc(OutputPosition);
    If OutputPosition=InputBufferSize Then FlushOutput;
  End;
End;

Procedure WriteReplacement(Index:Integer);
Var
  CharacterIndex:Integer;
Begin
  For CharacterIndex:=1 to Length(Replacements[Index].ToText)Do
    WriteOutputByte(Ord(Replacements[Index].ToText[CharacterIndex]));
  Inc(ReplacedCount);
End;

Procedure ShiftPending(Count:Integer);
Var
  Index:Integer;
Begin
  If Count>=PendingCount Then Begin
    PendingCount:=0;
    Exit;
  End;
  For Index:=Count to PendingCount-1 Do Pending[Index-Count]:=Pending[Index];
  Dec(PendingCount,Count);
End;

Procedure FillPending;
Begin
  While(PendingCount<MaxPatternLength)and Not InputAtEnd Do Begin
    If Not ReadSourceByte(InputByte)Then Begin
      InputAtEnd:=True;
      Exit;
    End;
    Pending[PendingCount]:=InputByte;
    Inc(PendingCount);
  End;
End;

Function PrefixMatches(PatternIndex,Count:Integer):Boolean;
Var
  Index:Integer;
Begin
  PrefixMatches:=False;
  For Index:=0 to Count-1 Do
    If Pending[Index]<>Ord(Replacements[PatternIndex].FromText[Index+1])Then Exit;
  PrefixMatches:=True;
End;

Procedure ProcessStream;
Var
  Index,CompareLength,BestPattern,BestLength:Integer;
  NeedMore:Boolean;
Begin
  InputAtEnd:=False;
  InputLength:=0;
  InputPosition:=0;
  OutputPosition:=0;
  PendingCount:=0;
  ReplacedCount:=0;
  FillPending;
  While PendingCount>0 Do Begin
    BestPattern:=0;
    BestLength:=0;
    NeedMore:=False;
    For Index:=1 to PairCount Do Begin
      CompareLength:=PendingCount;
      If CompareLength>Length(Replacements[Index].FromText)Then
        CompareLength:=Length(Replacements[Index].FromText);
      If PrefixMatches(Index,CompareLength)Then Begin
        If Length(Replacements[Index].FromText)<=PendingCount Then Begin
          If Length(Replacements[Index].FromText)>BestLength Then Begin
            BestPattern:=Index;
            BestLength:=Length(Replacements[Index].FromText);
          End;
        End Else If Not InputAtEnd Then NeedMore:=True;
      End;
    End;
    If NeedMore and(PendingCount<MaxPatternLength)Then Begin
      FillPending;
      Continue;
    End;
    If BestPattern>0 Then Begin
      WriteReplacement(BestPattern);
      ShiftPending(BestLength);
    End Else Begin
      WriteOutputByte(Pending[0]);
      ShiftPending(1);
    End;
    If Not InputAtEnd Then FillPending;
  End;
  If Not OutputIsStandard Then FlushOutput;
End;

Procedure SplitName(Const Name:TFileName; Var BaseName,Extension:TFileName);
Var
  Index,LastSlash,DotPosition:Integer;
Begin
  LastSlash:=0;
  DotPosition:=0;
  For Index:=1 to Length(Name)Do Begin
    If(Name[Index]='/')or(Name[Index]=#92)Then Begin
      LastSlash:=Index;
      DotPosition:=0;
    End Else If Name[Index]='.'Then DotPosition:=Index;
  End;
  If DotPosition>LastSlash Then Begin
    BaseName:=Copy(Name,1,DotPosition-1);
    Extension:=Copy(Name,DotPosition,MaxFileName);
  End Else Begin
    BaseName:=Name;
    Extension:='';
  End;
End;

Function MakeSiblingName(Const Name,Extension:TFileName):TFileName;
Var
  BaseName,OldExtension:TFileName;
Begin
  SplitName(Name,BaseName,OldExtension);
  MakeSiblingName:=BaseName+Extension;
End;

Procedure ReplaceFile(Const Name:TFileName);
Var
  TempName,BackupName:TFileName;
  ErrorCode:Integer;
  TempReady,BackupMoved:Boolean;
Begin
  CurrentInputName:=Name;
  Assign(InputFile,Name);
  FileMode:=0;
  {$I-}Reset(InputFile,1);{$I+}
  ErrorCode:=IOResult;
  If ErrorCode<>0 Then Begin
    ReportError('impossible de lire le fichier','cannot read file');
    Exit;
  End;
  TempName:=MakeSiblingName(Name,'.$$$');
  BackupName:=MakeSiblingName(Name,'.RBK');
  If(TempName=Name)or(BackupName=Name)or FileExists(TempName)or FileExists(BackupName)Then Begin
    Close(InputFile);
    ReportError('fichier temporaire ou de sauvegarde deja present',
                'temporary or backup file already exists');
    Exit;
  End;
  Assign(OutputFile,TempName);
  FileMode:=1;
  {$I-}Rewrite(OutputFile,1);{$I+}
  ErrorCode:=IOResult;
  If ErrorCode<>0 Then Begin
    Close(InputFile);
    ReportError('impossible de creer le fichier temporaire',
                'cannot create temporary file');
    Exit;
  End;
  InputIsStandard:=False;
  OutputIsStandard:=False;
  InputAtEnd:=False;
  StreamError:=False;
  ProcessStream;
  {$I-}Close(InputFile);{$I+}
  ErrorCode:=IOResult;
  If ErrorCode<>0 Then StreamError:=True;
  {$I-}Close(OutputFile);{$I+}
  ErrorCode:=IOResult;
  TempReady:=ErrorCode=0;
  If StreamError or Not TempReady Then Begin
    Assign(OutputFile,TempName);
    {$I-}Erase(OutputFile);{$I+}
    ErrorCode:=IOResult;
    ReportError('erreur d''entree/sortie','input/output error');
    Exit;
  End;
  If ReplacedCount=0 Then Begin
    Assign(OutputFile,TempName);
    {$I-}Erase(OutputFile);{$I+}
    ErrorCode:=IOResult;
    If VerboseMode and Not QuietMode Then WriteLn(Name,': aucune occurrence');
    Exit;
  End;
  Assign(InputFile,Name);
  {$I-}Rename(InputFile,BackupName);{$I+}
  ErrorCode:=IOResult;
  BackupMoved:=ErrorCode=0;
  If Not BackupMoved Then Begin
    Assign(OutputFile,TempName);
    {$I-}Erase(OutputFile);{$I+}
    ErrorCode:=IOResult;
    ReportError('impossible de creer la sauvegarde du fichier',
                'cannot create backup of source file');
    Exit;
  End;
  Assign(OutputFile,TempName);
  {$I-}Rename(OutputFile,Name);{$I+}
  ErrorCode:=IOResult;
  If ErrorCode<>0 Then Begin
    Assign(InputFile,BackupName);
    {$I-}Rename(InputFile,Name);{$I+}
    ErrorCode:=IOResult;
    ReportError('impossible de remplacer le fichier original',
                'cannot replace original file');
    Exit;
  End;
  Assign(InputFile,BackupName);
  {$I-}Erase(InputFile);{$I+}
  ErrorCode:=IOResult;
  If ErrorCode<>0 Then ReportError('impossible de supprimer la sauvegarde',
                                   'cannot remove backup file');
  If VerboseMode and Not QuietMode Then
    WriteLn(Name,': ',ReplacedCount,' remplacement(s)');
End;

Procedure ProcessStandardInput;
Begin
  CurrentInputName:='stdin';
  InputIsStandard:=True;
  OutputIsStandard:=True;
  InputAtEnd:=False;
  StreamError:=False;
  ProcessStream;
End;

Procedure ParseArguments;
Var
  Argument:TFileName;
  Index,PairEnd:Integer;
  SeparatorFound:Boolean;
Begin
  Index:=1;
  While Index<=ParamCount Do Begin
    Argument:=ParamStr(Index);
    If(Argument='-?')or(Argument='--I')or(Argument='--help')or(Argument='/?')Then Begin
      PrintHelp;
      Halt(0);
    End Else If(Argument='-V')or(Argument='--version')Then Begin
      WriteLn('replace (LINUX-0) 1.0');
      Halt(0);
    End Else If Argument='-s'Then QuietMode:=True
    Else If Argument='-v'Then VerboseMode:=True
    Else If(Length(Argument)>1)and(Argument[1]='-')and(Argument[2]='#')Then Begin
      DebugMode:=True;
      If Argument<>'-#'Then WriteLn('replace: debug option ',Copy(Argument,3,MaxFileName));
    End Else Break;
    Inc(Index);
  End;
  PairEnd:=Index;
  SeparatorFound:=False;
  While PairEnd<=ParamCount Do Begin
    If ParamStr(PairEnd)='--'Then Begin
      SeparatorFound:=True;
      Break;
    End;
    If PairEnd=ParamCount Then UsageError('paire source/cible incomplete');
    If PairCount>=MaxPairs Then UsageError('trop de paires de remplacement');
    Inc(PairCount);
    Replacements[PairCount].FromText:=ParamStr(PairEnd);
    Replacements[PairCount].ToText:=ParamStr(PairEnd+1);
    If Replacements[PairCount].FromText=''Then
      UsageError('la chaine source ne peut pas etre vide');
    If Length(Replacements[PairCount].FromText)>LongestPattern Then
      LongestPattern:=Length(Replacements[PairCount].FromText);
    Inc(PairEnd,2);
  End;
  If PairCount=0 Then UsageError('aucune paire de remplacement');
  If SeparatorFound Then Begin
    Index:=PairEnd+1;
    While Index<=ParamCount Do Begin
      If FileCount>=MaxFiles Then UsageError('trop de fichiers');
      Inc(FileCount);
      FileNames[FileCount]:=ParamStr(Index);
      Inc(Index);
    End;
    If FileCount=0 Then UsageError('nom de fichier attendu apres --');
  End;
End;

Begin
  PairCount:=0;FileCount:=0;LongestPattern:=0;
  QuietMode:=False;VerboseMode:=False;DebugMode:=False;ErrorFound:=False;
  InputIsStandard:=False;OutputIsStandard:=False;InputAtEnd:=False;
  StreamError:=False;
  LanguageCode:=GetEnv('LANGUAGE');
  English:=Copy(LanguageCode,1,2)='EN';
  ParseArguments;
  If DebugMode and Not QuietMode Then
    WriteLn('replace: ',PairCount,' paire(s), motif maximal ',LongestPattern,' octets');
  If FileCount=0 Then ProcessStandardInput
  Else For FileIndex:=1 to FileCount Do ReplaceFile(FileNames[FileIndex]);
  If ErrorFound Then Halt(1);
END.
