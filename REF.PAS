{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2026
  @website(https://www.gladir.com/linux-0)
  @abstract(Display C function headers using a tags index)
}

Program REF;

Uses DOS;

Const
  MaxFilters=16;
  MaxTagName=63;
  MaxFileName=127;
  MaxTagLine=255;

Type
  TTagName=String[MaxTagName];
  TFileName=String[MaxFileName];
  TTagLine=String[MaxTagLine];
  TFilterArray=Array[1..MaxFilters]Of TFileName;

Var
  TagsFile:Text;
  TagsName:TFileName;
  RequestedTag:TTagName;
  TagRecord,TagName:TTagLine;
  TagSource:TFileName;
  TagAddress,TagClass:TTagLine;
  TagKind:Char;
  TagLineNumber,LineNumber:LongInt;
  ClassFilters,FileFilters:TFilterArray;
  ClassFilterCount,FileFilterCount:Integer;
  ShowTagInfo,CrossReference,FoundTag,English:Boolean;
  LanguageCode:String[20];
  Matches:LongInt;

Function TrimText(Value:TTagLine):TTagLine;
Begin
  While(Length(Value)>0)and(Value[1]in[' ',#9])Do Delete(Value,1,1);
  While(Length(Value)>0)and(Value[Length(Value)]in[' ',#9])Do
    Delete(Value,Length(Value),1);
  TrimText:=Value;
End;

Function ParseSmallNumber(Const Value:TTagLine; Var Number:Integer):Boolean;
Var
  Parsed,ErrorCode:Integer;
Begin
  Val(Value,Parsed,ErrorCode);
  ParseSmallNumber:=ErrorCode=0;
  If ErrorCode=0 Then Number:=Parsed;
End;

Function IsIdentifierChar(Character:Char):Boolean;
Begin
  IsIdentifierChar:=((Character>='a')and(Character<='z'))or
    ((Character>='A')and(Character<='Z'))or
    ((Character>='0')and(Character<='9'))or(Character='_');
End;

Function HasTagAt(Const LineText:TTagLine; Const Name:TTagName):Boolean;
Var
  Position,FoundAt,AfterName:Integer;
  Tail:TTagLine;
Begin
  HasTagAt:=False;
  Position:=1;
  While Position<=Length(LineText)Do Begin
    FoundAt:=Pos(Name,Copy(LineText,Position,MaxTagLine));
    If FoundAt=0 Then Exit;
    FoundAt:=FoundAt+Position-1;
    AfterName:=FoundAt+Length(Name);
    If((FoundAt=1)or Not IsIdentifierChar(LineText[FoundAt-1]))and
      ((AfterName>Length(LineText))or Not IsIdentifierChar(LineText[AfterName]))Then Begin
      Tail:=Copy(LineText,AfterName,MaxTagLine);
      If Pos('(',Tail)>0 Then Begin HasTagAt:=True;Exit;End;
    End;
    Position:=FoundAt+Length(Name);
  End;
End;

Function IsField(Const Value:TTagLine; Const Prefix:TTagLine):Boolean;
Begin
  IsField:=Copy(Value,1,Length(Prefix))=Prefix;
End;

Procedure ParseTagRecord(Const Value:TTagLine);
Var
  TabOne,TabTwo,TabThree,Position,FieldEnd,Number,ExtensionPosition:Integer;
  FieldValue,NumberText:TTagLine;
Begin
  TagName:='';TagSource:='';TagAddress:='';TagClass:='';
  TagKind:=#0;TagLineNumber:=0;
  TabOne:=Pos(#9,Value);
  If TabOne=0 Then Exit;
  TagName:=Copy(Value,1,TabOne-1);
  TabTwo:=Pos(#9,Copy(Value,TabOne+1,MaxTagLine));
  If TabTwo=0 Then Exit;
  Inc(TabTwo,TabOne);
  TagSource:=Copy(Value,TabOne+1,TabTwo-TabOne-1);
  TabThree:=Pos(#9,Copy(Value,TabTwo+1,MaxTagLine));
  If TabThree=0 Then Begin
    TagAddress:=Copy(Value,TabTwo+1,MaxTagLine);
    FieldEnd:=Length(TagAddress)+1;
  End Else Begin
    Inc(TabThree,TabTwo);
    TagAddress:=Copy(Value,TabTwo+1,TabThree-TabTwo-1);
    FieldEnd:=TabThree+1;
  End;
  Position:=FieldEnd;
  While Position<=Length(Value)Do Begin
    FieldEnd:=Position;
    While(FieldEnd<=Length(Value))and(Value[FieldEnd]<>#9)Do Inc(FieldEnd);
    FieldValue:=Copy(Value,Position,FieldEnd-Position);
    If IsField(FieldValue,'class:')Then
      TagClass:=Copy(FieldValue,7,MaxTagLine)
    Else If IsField(FieldValue,'line:')Then Begin
      NumberText:=Copy(FieldValue,6,MaxTagLine);
      If ParseSmallNumber(NumberText,Number)Then TagLineNumber:=Number;
    End Else If(Length(FieldValue)=1)and(TagKind=#0)Then
      TagKind:=FieldValue[1];
    Position:=FieldEnd+1;
  End;
  If(TagLineNumber=0)and(Length(TagAddress)>0)and
    (TagAddress[1]in['0'..'9'])Then Begin
    NumberText:=TagAddress;
    Position:=1;
    While(Position<=Length(NumberText))and(NumberText[Position]in['0'..'9'])Do Inc(Position);
    NumberText:=Copy(NumberText,1,Position-1);
    If ParseSmallNumber(NumberText,Number)Then TagLineNumber:=Number;
  End;
  ExtensionPosition:=Pos(';"',TagAddress);
  If ExtensionPosition>0 Then
    TagAddress:=Copy(TagAddress,1,ExtensionPosition-1);
End;

Function PassesFilters:Boolean;
Var
  Index:Integer;
  ClassOK,FileOK:Boolean;
Begin
  ClassOK:=ClassFilterCount=0;
  For Index:=1 to ClassFilterCount Do
    If TagClass=ClassFilters[Index]Then ClassOK:=True;
  FileOK:=FileFilterCount=0;
  For Index:=1 to FileFilterCount Do
    If TagSource=FileFilters[Index]Then FileOK:=True;
  PassesFilters:=ClassOK and FileOK;
End;

Function FindSourceLine(Const Name:TTagName; Const SourceName:TFileName):LongInt;
Var
  Source:Text;
  SourceLine:TTagLine;
  LineNumber:LongInt;
  ErrorCode:Integer;
Begin
  FindSourceLine:=0;
  Assign(Source,SourceName);
  {$I-}Reset(Source);{$I+}
  ErrorCode:=IOResult;
  If ErrorCode<>0 Then Exit;
  LineNumber:=0;
  While Not EOF(Source)Do Begin
    ReadLn(Source,SourceLine);
    Inc(LineNumber);
    If HasTagAt(SourceLine,Name)Then Begin
      FindSourceLine:=LineNumber;
      Break;
    End;
  End;
  Close(Source);
End;

Function SourceLineMatches(Const Name:TTagName; Const SourceName:TFileName;
                           WantedLine:LongInt):Boolean;
Var
  Source:Text;
  SourceLine:TTagLine;
  LineNumber:LongInt;
  ErrorCode:Integer;
Begin
  SourceLineMatches:=False;
  If WantedLine<1 Then Exit;
  Assign(Source,SourceName);
  {$I-}Reset(Source);{$I+}
  ErrorCode:=IOResult;
  If ErrorCode<>0 Then Exit;
  LineNumber:=0;
  While Not EOF(Source)Do Begin
    ReadLn(Source,SourceLine);
    Inc(LineNumber);
    If LineNumber=WantedLine Then Begin
      SourceLineMatches:=HasTagAt(SourceLine,Name);
      Break;
    End;
  End;
  Close(Source);
End;

Procedure PrintTagHeader(Const Name:TTagName; Const SourceName:TFileName;
                         StartLine:LongInt);
Var
  Source:Text;
  SourceLine:TTagLine;
  LineNumber:LongInt;
  Position,ParenthesisDepth:Integer;
  Quote:Char;
  Escaped,AtHeader,Found:Boolean;
  ErrorCode:Integer;
Begin
  Assign(Source,SourceName);
  {$I-}Reset(Source);{$I+}
  ErrorCode:=IOResult;
  If ErrorCode<>0 Then Begin
    If English Then WriteLn('ref: cannot open source file ',SourceName)
    Else WriteLn('ref : impossible d''ouvrir le fichier source ',SourceName);
    Exit;
  End;
  LineNumber:=0;Found:=False;
  While Not EOF(Source)Do Begin
    ReadLn(Source,SourceLine);
    Inc(LineNumber);
    If(LineNumber=StartLine)or((StartLine=0)and HasTagAt(SourceLine,Name))Then Begin
      Found:=True;
      Break;
    End;
  End;
  If Not Found Then Begin
    Close(Source);
    If English Then WriteLn('ref: definition not found in ',SourceName)
    Else WriteLn('ref : definition introuvable dans ',SourceName);
    Exit;
  End;
  ParenthesisDepth:=0;Quote:=#0;Escaped:=False;AtHeader:=True;
  While AtHeader Do Begin
    Position:=1;
    While Position<=Length(SourceLine)Do Begin
      If Quote<>#0 Then Begin
        If Escaped Then Escaped:=False
        Else If SourceLine[Position]=#92 Then Escaped:=True
        Else If SourceLine[Position]=Quote Then Quote:=#0;
      End Else If(SourceLine[Position]=#34)or(SourceLine[Position]=#39)Then
        Quote:=SourceLine[Position]
      Else If SourceLine[Position]='('Then Inc(ParenthesisDepth)
      Else If(SourceLine[Position]=')')and(ParenthesisDepth>0)Then Dec(ParenthesisDepth)
      Else If(SourceLine[Position]='{')and(ParenthesisDepth=0)Then Begin
        If Position>1 Then WriteLn(Copy(SourceLine,1,Position-1));
        AtHeader:=False;
        Break;
      End Else If(SourceLine[Position]=';')and(ParenthesisDepth=0)Then Begin
        WriteLn(Copy(SourceLine,1,Position));
        AtHeader:=False;
        Break;
      End;
      Inc(Position);
    End;
    If AtHeader Then Begin
      WriteLn(SourceLine);
      If EOF(Source)Then AtHeader:=False
      Else Begin ReadLn(Source,SourceLine);Inc(LineNumber);End;
    End;
  End;
  Close(Source);
End;

Procedure OutputMatch;
Var
  SourceLine:TTagLine;
  Source:Text;
  StartLine:LongInt;
  ErrorCode:Integer;
Begin
  If(TagName<>'')and(TagName<>RequestedTag)Then Exit;
  If Not PassesFilters Then Exit;
  FoundTag:=True;
  Inc(Matches);
  If ShowTagInfo Then Begin
    WriteLn(TagName,#9,TagSource,#9,TagAddress);
    Exit;
  End;
  StartLine:=TagLineNumber;
  If(StartLine>0)and Not SourceLineMatches(TagName,TagSource,StartLine)Then
    StartLine:=0;
  If StartLine=0 Then StartLine:=FindSourceLine(TagName,TagSource);
  If CrossReference Then Begin
    If StartLine>0 Then Begin
      Write(TagName:20,StartLine:7,' ',TagSource,#9);
      Assign(Source,TagSource);
      {$I-}Reset(Source);{$I+}
      ErrorCode:=IOResult;
      If ErrorCode=0 Then Begin
        LineNumber:=0;
        While Not EOF(Source)Do Begin
          ReadLn(Source,SourceLine);Inc(LineNumber);
          If LineNumber=StartLine Then Begin WriteLn(SourceLine);Break;End;
        End;
        Close(Source);
      End Else WriteLn;
    End Else WriteLn(TagName:20,' ',TagSource);
  End Else If StartLine>0 Then
    PrintTagHeader(TagName,TagSource,StartLine)
  Else Begin
    If English Then WriteLn('ref: no source line for ',TagName)
    Else WriteLn('ref : aucune ligne source pour ',TagName);
  End;
End;

Procedure PrintHelp;
Begin
  If English Then Begin
    WriteLn('ref - display a C function header');
    WriteLn('Usage: ref [-t] [-x] [-c class]... [-f file]... tag');
    WriteLn(' -t  Print tag, source file and address');
    WriteLn(' -x  Print a cross-reference line');
    WriteLn(' -c  Restrict matches to a class');
    WriteLn(' -f  Restrict matches to a source file');
    WriteLn('Reads the tags index in the current directory.');
  End Else Begin
    WriteLn('REF - Cette commande permet d''afficher l''ent'+#136+'te d''une fonction C.');
    WriteLn;
    WriteLn('Syntaxe : ref [-t] [-x] [-c classe]... [-f fichier]... tag');
    WriteLn;
    WriteLn(' -t  Afficher le tag, le fichier et l''adresse');
    WriteLn(' -x  Afficher une ligne de reference croisee');
    WriteLn(' -c  Limiter les resultats a une classe');
    WriteLn(' -f  Limiter les resultats a un fichier source');
    WriteLn;
    WriteLn('Lit le fichier tags du r'+#130+'pertoire courant.');
  End;
End;

Procedure OptionError(Const MessageText:TTagLine);
Begin
  If English Then WriteLn('ref: ',MessageText)
  Else WriteLn('ref : ',MessageText);
  Halt(2);
End;

Procedure SearchTags;
Var
  ErrorCode:Integer;
Begin
  Assign(TagsFile,TagsName);
  {$I-}Reset(TagsFile);{$I+}
  ErrorCode:=IOResult;
  If ErrorCode<>0 Then Begin
    If English Then WriteLn('ref: cannot open tags file ',TagsName)
    Else WriteLn('ref : impossible d''ouvrir le fichier tags ',TagsName);
    Halt(1);
  End;
  While Not EOF(TagsFile)Do Begin
    ReadLn(TagsFile,TagRecord);
    ParseTagRecord(TagRecord);
    OutputMatch;
  End;
  Close(TagsFile);
End;

Var
  Argument:TFileName;
  ArgumentIndex:Integer;
  HasTag:Boolean;
Begin
  LanguageCode:=GetEnv('LANGUAGE');
  English:=Copy(LanguageCode,1,2)='EN';
  TagsName:='tags';
  ClassFilterCount:=0;FileFilterCount:=0;
  ShowTagInfo:=False;CrossReference:=False;FoundTag:=False;Matches:=0;
  RequestedTag:='';HasTag:=False;ArgumentIndex:=1;
  While ArgumentIndex<=ParamCount Do Begin
    Argument:=ParamStr(ArgumentIndex);
    If(Argument='--help')or(Argument='-h')or(Argument='/?')Then Begin
      PrintHelp;Halt(0);
    End Else If(Argument='--version')or(Argument='-V')Then Begin
      WriteLn('ref (LINUX-0) 1.0');Halt(0);
    End Else If(Argument='-t')Then ShowTagInfo:=True
    Else If(Argument='-x')Then CrossReference:=True
    Else If(Argument='-c')Then Begin
      Inc(ArgumentIndex);
      If ArgumentIndex>ParamCount Then OptionError('-c requires a class');
      If ClassFilterCount>=MaxFilters Then OptionError('too many class filters');
      Inc(ClassFilterCount);ClassFilters[ClassFilterCount]:=ParamStr(ArgumentIndex);
    End Else If(Argument='-f')Then Begin
      Inc(ArgumentIndex);
      If ArgumentIndex>ParamCount Then OptionError('-f requires a file');
      If FileFilterCount>=MaxFilters Then OptionError('too many file filters');
      Inc(FileFilterCount);FileFilters[FileFilterCount]:=ParamStr(ArgumentIndex);
    End Else If(Length(Argument)>1)and(Argument[1]='-')Then
      OptionError('unknown option '+Argument)
    Else If Not HasTag Then Begin
      RequestedTag:=Argument;HasTag:=True;
    End Else OptionError('only one tag name is accepted');
    Inc(ArgumentIndex);
  End;
  If Not HasTag Then OptionError('a tag name is required');
  SearchTags;
  If Not FoundTag Then Begin
    If English Then WriteLn('ref: no matching tag found for ',RequestedTag)
    Else WriteLn('ref : aucun tag correspondant pour ',RequestedTag);
    Halt(1);
  End;
END.
