{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2026
  @website(https://www.gladir.com/linux-0)
  @abstract(Target: Turbo Pascal 7, Free Pascal 3.2)
}

Program FGREP(Input,Output);

Uses DOS;

Const
 MaxFiles=32;
 MaxPatterns=64;
 MaxPatternLength=127;
 MaxLineLength=255;
 MaxContext=64;
 ReadBufferSize=1024;

Type
 TFileName=String[127];
 TPattern=String[MaxPatternLength];
 TLine=String[MaxLineLength];
 TReadBuffer=Array[1..ReadBufferSize]Of Byte;
 TContextItem=Record
  Text:TLine;
  Number,Offset:LongInt;
 End;
 TContextBuffer=Array[1..MaxContext]Of TContextItem;

Var
 FileNames:Array[1..MaxFiles]Of TFileName;
 Patterns:Array[1..MaxPatterns]Of TPattern;
 BeforeBuffer:TContextBuffer;
 SourceFile:File;
 ReadBuffer:TReadBuffer;
 FileCount,PatternCount:Integer;
 BeforeCount,BeforeLimit,AfterLimit,AfterRemaining:Integer;
 ArgumentIndex,ReadCount,ReadPosition,Index,ErrorCode:Integer;
 BytePosition,LineNumber,MatchCount,LastPrintedLine:LongInt;
 LineOffset:LongInt;
 CurrentFile,Argument,ValueText,OptionText,OptionName:TFileName;
 InputFromStdin,CountOnly,NoFileName,IgnoreCase:Boolean;
 ListMatching,ListNonMatching,Quiet,Silent:Boolean;
 InvertMatch,WholeLine,WholeWord,ShowByte,ShowLine:Boolean;
 ErrorFound,AnySelected,HasExplicitPattern:Boolean;
 ContextShown,StreamEOF:Boolean;
 LineText:TLine;

Procedure OptionError(Const MessageText:TFileName);
Begin
 WriteLn('fgrep: ',MessageText);
 Halt(2);
End;

Procedure ShowHelp;Forward;
Procedure ShowVersion;Forward;
Procedure FinishFile;Forward;

Procedure AddPattern(Const Value:TPattern);
Begin
 If PatternCount>=MaxPatterns Then OptionError('trop de motifs');
 Inc(PatternCount);
 Patterns[PatternCount]:=Value;
 HasExplicitPattern:=True;
End;

Procedure AddFile(Const Name:TFileName);
Begin
 If FileCount>=MaxFiles Then OptionError('trop de fichiers');
 Inc(FileCount);
 FileNames[FileCount]:=Name;
End;

Function UpperChar(Value:Char):Char;
Begin
 If Value In['a'..'z']Then UpperChar:=Chr(Ord(Value)-32)
 Else UpperChar:=Value;
End;

Function EqualChar(LeftChar,RightChar:Char):Boolean;
Begin
 If IgnoreCase Then EqualChar:=UpperChar(LeftChar)=UpperChar(RightChar)
 Else EqualChar:=LeftChar=RightChar;
End;

Function IsWordChar(Value:Char):Boolean;
Begin
 IsWordChar:=Value In['A'..'Z','a'..'z','0'..'9','_'];
End;

Function ContainsPattern(Const TextLine:TLine;Const Pattern:TPattern):Boolean;
Var
 StartAt,CharacterIndex:Integer;
 Matches:Boolean;
Begin
 ContainsPattern:=False;
 If Pattern=''Then Begin
  ContainsPattern:=True;
  Exit;
 End;
 If WholeLine And(Length(TextLine)<>Length(Pattern))Then Exit;
 If Length(Pattern)>Length(TextLine)Then Exit;
 StartAt:=1;
 While StartAt<=Length(TextLine)-Length(Pattern)+1 Do Begin
  Matches:=True;
  For CharacterIndex:=1 To Length(Pattern)Do
   If Not EqualChar(TextLine[StartAt+CharacterIndex-1],Pattern[CharacterIndex])Then Begin
    Matches:=False;
    Break;
   End;
  If Matches And WholeWord Then Begin
   If(StartAt>1)And IsWordChar(TextLine[StartAt-1])Then Matches:=False;
   If(StartAt+Length(Pattern)<=Length(TextLine))And
     IsWordChar(TextLine[StartAt+Length(Pattern)])Then Matches:=False;
  End;
  If Matches Then Begin
   ContainsPattern:=True;
   Exit;
  End;
  If WholeLine Then Exit;
  Inc(StartAt);
 End;
End;

Function LineMatches(Const TextLine:TLine):Boolean;
Var
 PatternIndex:Integer;
 Matched:Boolean;
Begin
 Matched:=False;
 For PatternIndex:=1 To PatternCount Do
  If ContainsPattern(TextLine,Patterns[PatternIndex])Then Begin
   Matched:=True;
   Break;
  End;
 If InvertMatch Then Matched:=Not Matched;
 LineMatches:=Matched;
End;

Procedure WriteLinePrefix(Number,Offset:LongInt);
Begin
 If(FileCount>1)And Not NoFileName And Not InputFromStdin Then
  Write(CurrentFile,':');
 If ShowByte Then Write(Offset,':');
 If ShowLine Then Write(Number,':');
End;

Procedure PrintGroupSeparator;
Begin
 If(ContextShown)And(LastPrintedLine>0)Then WriteLn('--');
End;

Procedure PrintContextItem(Const Item:TContextItem);
Begin
 If Item.Number<=LastPrintedLine Then Exit;
 If(LastPrintedLine>0)And(Item.Number>LastPrintedLine+1)Then
  PrintGroupSeparator;
 WriteLinePrefix(Item.Number,Item.Offset);
 WriteLn(Item.Text);
 LastPrintedLine:=Item.Number;
 ContextShown:=True;
End;

Procedure PrintBeforeContext;
Var
 BufferIndex:Integer;
Begin
 For BufferIndex:=BeforeCount Downto 1 Do
  PrintContextItem(BeforeBuffer[BufferIndex]);
End;

Procedure StoreBeforeContext(Const TextLine:TLine;Number,Offset:LongInt);
Var
 BufferIndex:Integer;
Begin
 If BeforeCount<MaxContext Then Inc(BeforeCount);
 For BufferIndex:=BeforeCount Downto 2 Do
  BeforeBuffer[BufferIndex]:=BeforeBuffer[BufferIndex-1];
 BeforeBuffer[1].Text:=TextLine;
 BeforeBuffer[1].Number:=Number;
 BeforeBuffer[1].Offset:=Offset;
End;

Procedure PrintCurrentLine(Const TextLine:TLine;Number,Offset:LongInt);
Begin
 If Number<=LastPrintedLine Then Exit;
 If(LastPrintedLine>0)And(Number>LastPrintedLine+1)And
   ((BeforeLimit>0)Or(AfterLimit>0))Then PrintGroupSeparator;
 WriteLinePrefix(Number,Offset);
 WriteLn(TextLine);
 LastPrintedLine:=Number;
 ContextShown:=True;
End;

Procedure ProcessLine(Const TextLine:TLine;Number,Offset:LongInt);
Var
 Matched:Boolean;
Begin
 Matched:=LineMatches(TextLine);
 If Matched Then Begin
  Inc(MatchCount);
  AnySelected:=True;
 End;
 If Not Quiet And Not CountOnly And Not ListMatching And Not ListNonMatching Then Begin
  If Matched Then Begin
   PrintBeforeContext;
   PrintCurrentLine(TextLine,Number,Offset);
  AfterRemaining:=AfterLimit;
  End Else If AfterRemaining>0 Then Begin
   PrintCurrentLine(TextLine,Number,Offset);
   Dec(AfterRemaining);
  End;
 End;
 If BeforeLimit>0 Then StoreBeforeContext(TextLine,Number,Offset);
End;

Function NextSourceByte(Var Character:Char):Boolean;
Var
 BytesRead:Word;
Begin
 NextSourceByte:=False;
 If StreamEOF Then Exit;
 If ReadPosition>ReadCount Then Begin
  {$I-}BlockRead(SourceFile,ReadBuffer,SizeOf(ReadBuffer),BytesRead);{$I+}
  If IOResult<>0 Then Begin
   StreamEOF:=True;
   ErrorFound:=True;
   Exit;
  End;
  ReadCount:=BytesRead;
  ReadPosition:=1;
  If ReadCount=0 Then Begin
   StreamEOF:=True;
   Exit;
  End;
 End;
 Character:=Chr(ReadBuffer[ReadPosition]);
 Inc(ReadPosition);
 Inc(BytePosition);
 NextSourceByte:=True;
End;

Function ReadFileLine(Var TextLine:TLine;Var Number,Offset:LongInt):Boolean;
Var
 Character:Char;
 GotAny:Boolean;
Begin
 TextLine:='';
 Offset:=BytePosition;
 GotAny:=False;
 While NextSourceByte(Character)Do Begin
  GotAny:=True;
  If Character=#10 Then Begin
   Inc(LineNumber);
   Number:=LineNumber-1;
   ReadFileLine:=True;
   Exit;
  End;
  If(Character<>#13)And(Length(TextLine)<MaxLineLength)Then
   TextLine:=TextLine+Character;
 End;
 ReadFileLine:=GotAny;
 If GotAny Then Begin
  Inc(LineNumber);
  Number:=LineNumber-1;
 End;
End;

Procedure ResetFileState;
Begin
 ReadCount:=0;
 ReadPosition:=1;
 BytePosition:=0;
 LineNumber:=1;
 BeforeCount:=0;
 AfterRemaining:=0;
 MatchCount:=0;
 LastPrintedLine:=0;
 ContextShown:=False;
 AnySelected:=False;
 StreamEOF:=False;
End;

Procedure ProcessNamedFile(Const Name:TFileName);
Var
 ReadNumber,ReadOffset:LongInt;
 OldFileMode:Byte;
Begin
 CurrentFile:=Name;
 Assign(SourceFile,Name);
 OldFileMode:=FileMode;
 FileMode:=0;
 {$I-}Reset(SourceFile,1);{$I+}
 ErrorCode:=IOResult;
 FileMode:=OldFileMode;
 If ErrorCode<>0 Then Begin
  If Not Silent Then WriteLn('fgrep: impossible de lire ',Name);
  ErrorFound:=True;
  Exit;
 End;
 ResetFileState;
 While ReadFileLine(LineText,ReadNumber,ReadOffset)Do
  ProcessLine(LineText,ReadNumber,ReadOffset);
 {$I-}Close(SourceFile);{$I+}
 If IOResult<>0 Then ErrorFound:=True;
 FinishFile;
End;

Procedure ProcessStandardInput;
Var
 ReadNumber,ReadOffset:LongInt;
Begin
 CurrentFile:='';
 InputFromStdin:=True;
 ResetFileState;
 ReadNumber:=0;
 ReadOffset:=0;
 While Not EOF(Input)Do Begin
  ReadLn(Input,LineText);
  Inc(ReadNumber);
  ProcessLine(LineText,ReadNumber,ReadOffset);
  {$IFDEF UNIX}
  Inc(ReadOffset,Length(LineText)+1);
  {$ELSE}
  Inc(ReadOffset,Length(LineText)+2);
  {$ENDIF}
 End;
 FinishFile;
End;

Procedure FinishFile;
Begin
 If Quiet Then Exit;
 If CountOnly Then Begin
  If Not NoFileName And(FileCount>1)And Not InputFromStdin Then
   Write(CurrentFile,':');
  WriteLn(MatchCount);
 End Else If ListMatching And AnySelected Then Begin
  If InputFromStdin Then WriteLn('(standard input)')Else WriteLn(CurrentFile);
 End Else If ListNonMatching And Not AnySelected Then Begin
  If InputFromStdin Then WriteLn('(standard input)')Else WriteLn(CurrentFile);
 End;
End;

Procedure LoadPatternFile(Const Name:TFileName);
Var
 PatternFile:Text;
 PatternLine:TPattern;
 OldFileMode:Byte;
Begin
 Assign(PatternFile,Name);
 OldFileMode:=FileMode;
 FileMode:=0;
 {$I-}Reset(PatternFile);{$I+}
 ErrorCode:=IOResult;
 FileMode:=OldFileMode;
 If ErrorCode<>0 Then Begin
  If Not Silent Then WriteLn('fgrep: fichier de motifs introuvable: ',Name);
  ErrorFound:=True;
  HasExplicitPattern:=True;
  Exit;
 End;
 HasExplicitPattern:=True;
 While Not EOF(PatternFile)Do Begin
  ReadLn(PatternFile,PatternLine);
  AddPattern(PatternLine);
 End;
 Close(PatternFile);
End;

Function ParseNumber(Const TextValue,OptionName:TFileName):Integer;
Var
 Number,Err:Integer;
Begin
 Val(TextValue,Number,Err);
 If(Err<>0)Or(Number<0)Or(Number>MaxContext)Then
  OptionError('valeur de contexte invalide pour '+OptionName);
 ParseNumber:=Number;
End;

Procedure SetContext(Value:Integer);
Begin
 BeforeLimit:=Value;
 AfterLimit:=Value;
End;

Procedure ParseContextOption(Const OptionText:TFileName;Var Index:Integer);
Var
 OptionName,Value:TFileName;
 ContextValue:Integer;
Begin
 OptionName:=Copy(OptionText,1,2);
 Value:=Copy(OptionText,3,MaxLineLength);
 If Value=''Then Begin
  Inc(Index);
  If Index>ParamCount Then OptionError('argument manquant pour '+OptionName);
  Value:=ParamStr(Index);
 End;
 ContextValue:=ParseNumber(Value,OptionName);
 If OptionName='-A'Then AfterLimit:=ContextValue
 Else If OptionName='-B'Then BeforeLimit:=ContextValue
 Else SetContext(ContextValue);
End;

Procedure ParsePatternOption(Const OptionText:TFileName;Var Index:Integer);
Var
 OptionName,Value:TFileName;
Begin
 OptionName:=Copy(OptionText,1,2);
 Value:=Copy(OptionText,3,MaxLineLength);
 If Value=''Then Begin
  Inc(Index);
  If Index>ParamCount Then OptionError('argument manquant pour '+OptionName);
  Value:=ParamStr(Index);
 End;
 If OptionName='-e'Then AddPattern(Value)
 Else LoadPatternFile(Value);
End;

Procedure ParseOptions;
Var
 OptionPosition,Index:Integer;
 Value:TFileName;
 PatternWasSet:Boolean;
Begin
 FileCount:=0;
 PatternCount:=0;
 BeforeCount:=0;
 BeforeLimit:=0;
 AfterLimit:=0;
 CountOnly:=False;
 NoFileName:=False;
 IgnoreCase:=False;
 ListMatching:=False;
 ListNonMatching:=False;
 Quiet:=False;
 Silent:=False;
 InvertMatch:=False;
 WholeLine:=False;
 WholeWord:=False;
 ShowByte:=False;
 ShowLine:=False;
 ErrorFound:=False;
 AnySelected:=False;
 InputFromStdin:=False;
 HasExplicitPattern:=False;
 PatternWasSet:=False;
 Index:=1;
 While Index<=ParamCount Do Begin
  Argument:=ParamStr(Index);
  If(Argument='--help')Or(Argument='-H')Or(Argument='/?')Or
    (Argument='/h')Or(Argument='/H')Then Begin ShowHelp;Halt(0);End
  Else If(Argument='--version')Or(Argument='-V')Then Begin ShowVersion;Halt(0);End
  Else If Argument='--version'Then Begin ShowVersion;Halt(0);End
  Else If Argument='--'Then Begin
   Inc(Index);
   While Index<=ParamCount Do Begin
    If Not PatternWasSet And Not HasExplicitPattern Then Begin
     AddPattern(ParamStr(Index));
     PatternWasSet:=True;
    End Else AddFile(ParamStr(Index));
    Inc(Index);
   End;
   Break;
  End Else If(Argument='-A')Or(Argument='-B')Or(Argument='-C')Or
              ((Length(Argument)>2)And(Argument[1]='-')And
               (Argument[2]In['A','B','C']))Then
   ParseContextOption(Argument,Index)
  Else If(Argument='-e')Or(Argument='-f')Or
          ((Length(Argument)>2)And(Argument[1]='-')And
           (Argument[2]In['e','f']))Then
   ParsePatternOption(Argument,Index)
  Else If(Length(Argument)>1)And(Argument[1]='-')And
          (Argument[2]In['0'..'9'])Then
   SetContext(ParseNumber(Copy(Argument,2,MaxLineLength),'-NUM'))
  Else If(Argument='-b')Then ShowByte:=True
  Else If(Argument='-c')Then CountOnly:=True
  Else If(Argument='-h')Then NoFileName:=True
  Else If(Argument='-i')Then IgnoreCase:=True
  Else If(Argument='-l')Then ListMatching:=True
  Else If(Argument='-L')Then ListNonMatching:=True
  Else If(Argument='-n')Then ShowLine:=True
  Else If(Argument='-q')Then Quiet:=True
  Else If(Argument='-s')Then Silent:=True
  Else If(Argument='-v')Then InvertMatch:=True
  Else If(Argument='-w')Then WholeWord:=True
  Else If(Argument='-x')Then WholeLine:=True
  Else If(Argument='/?')Or(Argument='/h')Or(Argument='/H')Then Begin ShowHelp;Halt(0);End
  Else If(Argument='-hhelp')Or(Argument='--')Then Begin ShowHelp;Halt(0);End
  Else If(Length(Argument)>1)And(Argument[1]='-')Then Begin
   If Argument='-h'Then NoFileName:=True
   Else Begin
    OptionPosition:=2;
    While OptionPosition<=Length(Argument)Do Begin
     Case Argument[OptionPosition]Of
      'b':ShowByte:=True;
      'c':CountOnly:=True;
      'h':NoFileName:=True;
      'i':IgnoreCase:=True;
      'l':ListMatching:=True;
      'L':ListNonMatching:=True;
      'n':ShowLine:=True;
      'q':Quiet:=True;
      's':Silent:=True;
      'v':InvertMatch:=True;
      'w':WholeWord:=True;
      'x':WholeLine:=True;
     Else OptionError('option inconnue: -'+Argument[OptionPosition]);
     End;
     Inc(OptionPosition);
    End;
   End;
  End Else If Not PatternWasSet And Not HasExplicitPattern Then Begin
   AddPattern(Argument);
   PatternWasSet:=True;
  End Else AddFile(Argument);
  Inc(Index);
 End;
 If Not HasExplicitPattern And(PatternCount=0)Then
  OptionError('aucun motif fourni');
 If FileCount=0 Then InputFromStdin:=True;
End;

Procedure ShowHelp;
Begin
 WriteLn('FGREP - Cette commande permet de rechercher des chaines litterales dans les fichiers.');
 WriteLn;
 WriteLn('Syntaxe: FGREP [options] motif [fichier ...]');
 WriteLn;
 WriteLn('  -b -n       Afficher les offsets et numeros de ligne');
 WriteLn('  -c          Compter les lignes correspondantes');
 WriteLn('  -e motif    Ajouter un motif litteral');
 WriteLn('  -f fichier  Lire les motifs depuis un fichier');
 WriteLn('  -h          Masquer les noms de fichiers');
 WriteLn('  -i          Ignorer la casse');
 WriteLn('  -l / -L     Lister les fichiers avec / sans correspondance');
 WriteLn('  -q -s       Mode silencieux / masquer les erreurs de lecture');
 WriteLn('  -v -w -x    Inverser / mot entier / ligne entiere');
 WriteLn('  -A n -B n -C n, -NUM  Afficher du contexte');
 WriteLn('  --help /?   Afficher cette aide');
 WriteLn; WriteLn('Les motifs sont litteraux: aucune expression reguliere n''est interpretee.');
End;

Procedure ShowVersion;
Begin
 WriteLn('fgrep 1.0 - LINUX-0 Pascal');
End;

Begin
 ParseOptions;
 If InputFromStdin Then ProcessStandardInput
 Else For Index:=1 To FileCount Do ProcessNamedFile(FileNames[Index]);
 If ErrorFound Then Halt(2);
 If AnySelected Then Halt(0)Else Halt(1);
End.