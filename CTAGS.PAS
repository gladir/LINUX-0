{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2026
  @website(https://www.gladir.com/linux-0)
  @abstract(Target: Turbo Pascal 7, Free Pascal 3.2)
}

Program CTAGS;

Uses DOS;

Const
  MaxFiles=32;
  MaxTags=4096;
  MaxTagName=63;
  MaxFileName=127;
  MaxSourceLine=255;

Type
  TFileName=String[MaxFileName];
  TFileArray=Array[1..MaxFiles]Of TFileName;
  TTagName=String[MaxTagName];
  TSourceLine=String[MaxSourceLine];

Var
  SourceFile,TagFile:Text;
  FileNames:TFileArray;
  FileCount,ArgumentIndex,TagCount,OptionIndex:Integer;
  OutputName,CurrentFile,Argument,LanguageCode:String;
  BackwardSearch,IgnoreCase,Structures,Typedefs,VgrindMode:Boolean;
  RecursiveMode,AppendMode,CxrefMode,QuietMode,ErrorFound:Boolean;
  TagsOpened,InBlockComment,PendingTypedef:Boolean;
  LineNumber:LongInt;
  Statement,SanitizedLine:TSourceLine;
  StatementLine:LongInt;

Procedure ReportError(Const MessageText:String);
Begin
  If Not QuietMode Then WriteLn('ctags: ',CurrentFile,': ',MessageText);
  ErrorFound:=True;
End;

Procedure OptionError(Const MessageText:String);
Begin
  WriteLn('ctags: ',MessageText);
  Halt(2);
End;

Procedure PrintHelp;
Begin
  If Copy(LanguageCode,1,2)='EN'Then Begin
    WriteLn('CTAGS : Generate tags for C and C++ source files.');
    WriteLn('Syntax: ctags [-BSstvraT] file ...');
    WriteLn(' -B  Use backward-search tag patterns');
    WriteLn(' -S  Fold tag names to uppercase');
    WriteLn(' -s  Include struct, union and enum names');
    WriteLn(' -t  Include typedef names');
    WriteLn(' -v  Write vgrind index format');
    WriteLn(' -r  Recurse into source directories');
    WriteLn(' -a  Append to the output index');
    WriteLn(' -T  Write cxref-style output');
    WriteLn('Default output: tags; use vgrind or cxref with their formats.');
  End Else Begin
    WriteLn('CTAGS : Cette commande permet de g'+#130+'n'+#130+'r'+#130+' des tags pour les fichiers source C et C++.');
    WriteLn;
    WriteLn('Syntaxe : ctags [-BSstvraT] fichier ...');
    WriteLn(' -B  Utiliser des motifs de recherche arriere');
    WriteLn(' -S  Convertir les noms de tags en majuscules');
    WriteLn(' -s  Inclure les structures, unions et enumerations');
    WriteLn(' -t  Inclure les noms de typedef');
    WriteLn(' -v  Produire le format d''index vgrind');
    WriteLn(' -r  Parcourir recursivement les repertoires');
    WriteLn(' -a  Ajouter les tags a l''index existant');
    WriteLn(' -T  Produire le format cxref');
    WriteLn('Sortie par defaut : tags; les autres formats utilisent vgrind ou cxref.');
  End;
End;

Function IsIdentifierStart(Value:Char):Boolean;
Begin
  IsIdentifierStart:=Value in['A'..'Z','a'..'z','_','$'];
End;

Function IsIdentifierChar(Value:Char):Boolean;
Begin
  IsIdentifierChar:=Value in['A'..'Z','a'..'z','0'..'9','_','$'];
End;

Function NormalizeTagName(Const Name:String):String;
Var
  Index:Integer;
  Normalized:String;
Begin
  Normalized:=Name;
  If IgnoreCase Then
    For Index:=1 to Length(Normalized)Do
      If Normalized[Index]in['a'..'z']Then
        Normalized[Index]:=Chr(Ord(Normalized[Index])-32);
  NormalizeTagName:=Normalized;
End;

Function EscapePattern(Const Value:String; Delimiter:Char):String;
Var
  Index:Integer;
  ResultValue:String;
Begin
  ResultValue:='';
  For Index:=1 to Length(Value)Do Begin
    If(Value[Index]=Delimiter)or(Value[Index]=#92)Then
      ResultValue:=ResultValue+#92;
    If Value[Index]in[#9,#13]Then ResultValue:=ResultValue+' '
    Else ResultValue:=ResultValue+Value[Index];
  End;
  EscapePattern:=ResultValue;
End;

Procedure WriteTag(Const Name,FileName:String; TagLine:LongInt;
                   Kind:Char; Const SourceText:String);
Var
  StoredName,Pattern:String;
  Delimiter:Char;
Begin
  If(Name='')or(Length(Name)>MaxTagName)Then Exit;
  StoredName:=NormalizeTagName(Name);
  If VgrindMode Then
    WriteLn(TagFile,StoredName,#9,FileName,#9,TagLine)
  Else If CxrefMode Then
    WriteLn(TagFile,FileName,#9,TagLine,#9,StoredName)
  Else Begin
    If BackwardSearch Then Delimiter:='?'Else Delimiter:='/';
    Pattern:=EscapePattern(SourceText,Delimiter);
    Write(TagFile,StoredName,#9,FileName,#9,Delimiter,'^',Pattern,'$',Delimiter,
          ';"',#9,Kind,#9,'line:',TagLine);
    WriteLn(TagFile);
  End;
  Inc(TagCount);
End;

Function SkipSpaceBackward(Const Value:String; Position:Integer):Integer;
Begin
  While(Position>0)and(Value[Position]in[' ',#9])Do Dec(Position);
  SkipSpaceBackward:=Position;
End;

Function PreviousIdentifier(Const Value:String; Position:Integer):String;
Var
  FinishPosition,StartPosition:Integer;
Begin
  Position:=SkipSpaceBackward(Value,Position);
  FinishPosition:=Position;
  While(Position>0)and IsIdentifierChar(Value[Position])Do Dec(Position);
  StartPosition:=Position+1;
  If(StartPosition>FinishPosition)or
    not IsIdentifierStart(Value[StartPosition])Then PreviousIdentifier:=''
  Else PreviousIdentifier:=Copy(Value,StartPosition,FinishPosition-StartPosition+1);
End;

Function LastIdentifier(Const Value:String):String;
Var
  Position,StartPosition:Integer;
  Token:String;
Begin
  LastIdentifier:='';
  Position:=1;
  While Position<=Length(Value)Do Begin
    If IsIdentifierStart(Value[Position])Then Begin
      StartPosition:=Position;
      Inc(Position);
      While(Position<=Length(Value))and IsIdentifierChar(Value[Position])Do
        Inc(Position);
      Token:=Copy(Value,StartPosition,Position-StartPosition);
      If Token<>'typedef'Then LastIdentifier:=Token;
    End Else Inc(Position);
  End;
End;

Function FirstFunctionName(Const Value:String):String;
Var
  Position,OpenPosition:Integer;
  Candidate:String;
Begin
  FirstFunctionName:='';
  Position:=1;
  While Position<=Length(Value)Do Begin
    If Value[Position]='('Then Begin
      OpenPosition:=Position;
      Candidate:=PreviousIdentifier(Value,OpenPosition-1);
      If(Candidate<>'')and(Candidate<>'if')and(Candidate<>'while')and
        (Candidate<>'for')and(Candidate<>'switch')and
        (Candidate<>'sizeof')and(Candidate<>'return')Then
        FirstFunctionName:=Candidate;
      Exit;
    End;
    Inc(Position);
  End;
End;

Procedure AddAggregateTags(Const Value:String; TagLine:LongInt);
Var
  Position,StartPosition:Integer;
  Keyword,Name:String;
  Kind:Char;
Begin
  If Not Structures Then Exit;
  Position:=1;
  While Position<=Length(Value)Do Begin
    If IsIdentifierStart(Value[Position])Then Begin
      StartPosition:=Position;
      Inc(Position);
      While(Position<=Length(Value))and IsIdentifierChar(Value[Position])Do
        Inc(Position);
      Keyword:=Copy(Value,StartPosition,Position-StartPosition);
      If(Keyword='struct')or(Keyword='union')or(Keyword='enum')Then Begin
        While(Position<=Length(Value))and(Value[Position]in[' ',#9])Do Inc(Position);
        StartPosition:=Position;
        If(Position<=Length(Value))and IsIdentifierStart(Value[Position])Then Begin
          Inc(Position);
          While(Position<=Length(Value))and IsIdentifierChar(Value[Position])Do Inc(Position);
          Name:=Copy(Value,StartPosition,Position-StartPosition);
          If Keyword='struct'Then Kind:='s'
          Else If Keyword='union'Then Kind:='u'Else Kind:='e';
          WriteTag(Name,CurrentFile,TagLine,Kind,Value);
        End;
      End;
    End Else Inc(Position);
  End;
End;

Function SanitizeLine(Const Value:String):String;
Var
  Index:Integer;
  Quote:Char;
  ResultValue:String;
Begin
  ResultValue:='';
  Index:=1;
  Quote:=#0;
  While Index<=Length(Value)Do Begin
    If InBlockComment Then Begin
      If(Index<Length(Value))and(Value[Index]='*')and(Value[Index+1]='/')Then Begin
        InBlockComment:=False;
        ResultValue:=ResultValue+'  ';
        Inc(Index,2);
      End Else Begin ResultValue:=ResultValue+' '; Inc(Index); End;
    End Else If Quote<>#0 Then Begin
      If Value[Index]=#92 Then Begin
        ResultValue:=ResultValue+'  ';
        Inc(Index,2);
      End Else If Value[Index]=Quote Then Begin
        Quote:=#0;
        ResultValue:=ResultValue+' ';
        Inc(Index);
      End Else Begin ResultValue:=ResultValue+' '; Inc(Index); End;
    End Else If(Index<Length(Value))and(Value[Index]='/')and(Value[Index+1]='/')Then
      Break
    Else If(Index<Length(Value))and(Value[Index]='/')and(Value[Index+1]='*')Then Begin
      InBlockComment:=True;
      ResultValue:=ResultValue+'  ';
      Inc(Index,2);
    End Else If(Value[Index]=#34)or(Value[Index]=#39)Then Begin
      Quote:=Value[Index];
      ResultValue:=ResultValue+' ';
      Inc(Index);
    End Else Begin
      ResultValue:=ResultValue+Value[Index];
      Inc(Index);
    End;
  End;
  SanitizeLine:=ResultValue;
End;

Procedure ScanMacro(Const Value:String);
Var
  Position,StartPosition:Integer;
  Name:String;
Begin
  Position:=1;
  While(Position<=Length(Value))and(Value[Position]in[' ',#9])Do Inc(Position);
  If(Position>Length(Value))or(Value[Position]<>'#')Then Exit;
  Inc(Position);
  While(Position<=Length(Value))and(Value[Position]in[' ',#9])Do Inc(Position);
  If Copy(Value,Position,6)<>'define'Then Exit;
  Inc(Position,6);
  If(Position<=Length(Value))and IsIdentifierChar(Value[Position])Then Exit;
  While(Position<=Length(Value))and(Value[Position]in[' ',#9])Do Inc(Position);
  StartPosition:=Position;
  If(Position<=Length(Value))and IsIdentifierStart(Value[Position])Then Begin
    Inc(Position);
    While(Position<=Length(Value))and IsIdentifierChar(Value[Position])Do Inc(Position);
    Name:=Copy(Value,StartPosition,Position-StartPosition);
    WriteTag(Name,CurrentFile,LineNumber,'d',Value);
  End;
End;

Procedure ProcessSourceFile(Const FileName:String);
Var
  SourceLine,OriginalLine,FunctionName,TypedefName,StatementPattern:String;
  Position,ParenthesisDepth,LocalBraceDepth:Integer;
  SourceError:Integer;
Begin
  CurrentFile:=FileName;
  Assign(SourceFile,FileName);
  {$I-}Reset(SourceFile);{$I+}
  SourceError:=IOResult;
  If SourceError<>0Then Begin ReportError('impossible de lire le fichier'); Exit; End;
  LineNumber:=0;
  Statement:='';
  StatementLine:=1;
  InBlockComment:=False;
  PendingTypedef:=False;
  ParenthesisDepth:=0;
  LocalBraceDepth:=0;
  While Not EOF(SourceFile)Do Begin
    ReadLn(SourceFile,SourceLine);
    Inc(LineNumber);
    OriginalLine:=SourceLine;
    ScanMacro(OriginalLine);
    SanitizedLine:=SanitizeLine(SourceLine);
    AddAggregateTags(SanitizedLine,LineNumber);
    For Position:=1 to Length(SanitizedLine)Do Begin
      If LocalBraceDepth=0 Then Begin
        If(Statement='')and not(SanitizedLine[Position]in[' ',#9,#13])Then Begin
          StatementLine:=LineNumber;
          StatementPattern:=OriginalLine;
        End;
        If SanitizedLine[Position]='('Then Inc(ParenthesisDepth)
        Else If SanitizedLine[Position]=')'Then Dec(ParenthesisDepth);
        If SanitizedLine[Position]=';'Then Begin
          If Typedefs and(Pos('typedef',Statement)>0)Then Begin
            TypedefName:=LastIdentifier(Statement);
            If TypedefName<>''Then
              WriteTag(TypedefName,CurrentFile,StatementLine,'t',OriginalLine);
          End;
          PendingTypedef:=False;
          Statement:='';
          StatementPattern:='';
          ParenthesisDepth:=0;
          StatementLine:=LineNumber;
        End Else If(SanitizedLine[Position]='{')and(ParenthesisDepth=0)Then Begin
          If Pos('typedef',Statement)>0 Then PendingTypedef:=True;
          FunctionName:=FirstFunctionName(Statement);
          If FunctionName<>''Then
            WriteTag(FunctionName,CurrentFile,StatementLine,'f',StatementPattern);
          LocalBraceDepth:=1;
          Statement:='';
          StatementPattern:='';
          ParenthesisDepth:=0;
        End Else If Length(Statement)<250 Then
          Statement:=Statement+SanitizedLine[Position];
      End Else Begin
        If SanitizedLine[Position]='{'Then Inc(LocalBraceDepth)
        Else If SanitizedLine[Position]='}'Then Begin
          Dec(LocalBraceDepth);
          If LocalBraceDepth=0 Then Begin
            Statement:='';
            If PendingTypedef Then Statement:='typedef ';
            StatementPattern:=OriginalLine;
            ParenthesisDepth:=0;
            StatementLine:=LineNumber;
          End;
        End;
      End;
    End;
    If(LocalBraceDepth=0)and(Statement<>'')and
      (Length(Statement)<250)Then Statement:=Statement+' ';
  End;
  Close(SourceFile);
End;

Function IsSourceFile(Const Name:String):Boolean;
Var
  DotPosition,Index:Integer;
  Extension:String;
Begin
  DotPosition:=0;
  For Index:=1 to Length(Name)Do If Name[Index]='.'Then DotPosition:=Index;
  Extension:=Copy(Name,DotPosition,Length(Name));
  IsSourceFile:=(Extension='.c')or(Extension='.h')or(Extension='.cc')or
    (Extension='.cpp')or(Extension='.cxx')or(Extension='.hpp')or
    (Extension='.C')or(Extension='.H');
End;

Procedure ProcessPath(Const PathName:String);
Var
  Entry:SearchRec;
  Files,Directories:TFileArray;
  DirectoryName,Pattern,ChildPath:String;
  FileCountHere,DirectoryCount,Index:Integer;
Begin
  FindFirst(PathName,AnyFile,Entry);
  If DosError<>0Then Begin CurrentFile:=PathName; ReportError('fichier introuvable'); Exit; End;
  If(Entry.Attr and Directory)<>0Then Begin
    {$IFDEF FPC}FindClose(Entry);{$ENDIF}
    If Not RecursiveMode Then Begin CurrentFile:=PathName; ReportError('utilisez -r pour parcourir le repertoire'); Exit; End;
    DirectoryName:=PathName;
    If Not(DirectoryName[Length(DirectoryName)]in['\','/'])Then Begin
      If(Pos('/',DirectoryName)>0)and(Pos('\',DirectoryName)=0)Then DirectoryName:=DirectoryName+'/'
      Else DirectoryName:=DirectoryName+'\';
    End;
    Pattern:=DirectoryName+'*.*';
    FileCountHere:=0;
    DirectoryCount:=0;
    FindFirst(Pattern,AnyFile,Entry);
    While DosError=0 Do Begin
      If(Entry.Name<>'.')and(Entry.Name<>'..')Then Begin
        ChildPath:=DirectoryName+Entry.Name;
        If(Entry.Attr and Directory)<>0Then Begin
          If DirectoryCount<MaxFiles Then Begin Inc(DirectoryCount); Directories[DirectoryCount]:=ChildPath; End;
        End Else If IsSourceFile(Entry.Name)and(FileCountHere<MaxFiles)Then Begin
          Inc(FileCountHere);
          Files[FileCountHere]:=ChildPath;
        End;
      End;
      FindNext(Entry);
    End;
    {$IFDEF FPC}FindClose(Entry);{$ENDIF}
    For Index:=1 to FileCountHere Do ProcessSourceFile(Files[Index]);
    For Index:=1 to DirectoryCount Do ProcessPath(Directories[Index]);
  End Else Begin
    {$IFDEF FPC}FindClose(Entry);{$ENDIF}
    ProcessSourceFile(PathName);
  End;
End;

Procedure OpenTagOutput;
Begin
  If VgrindMode Then OutputName:='vgrind'
  Else If CxrefMode Then OutputName:='cxref'
  Else OutputName:='tags';
  Assign(TagFile,OutputName);
  If AppendMode Then Begin
    {$I-}Append(TagFile);{$I+}
    If IOResult<>0Then Begin
      {$I-}Rewrite(TagFile);{$I+}
      If IOResult<>0Then OptionError('impossible de creer '+OutputName);
    End;
  End Else Begin
    {$I-}Rewrite(TagFile);{$I+}
    If IOResult<>0Then OptionError('impossible de creer '+OutputName);
  End;
  TagsOpened:=True;
End;

Procedure CloseTagOutput;
Begin
  If TagsOpened Then Begin Close(TagFile); TagsOpened:=False; End;
End;

BEGIN
  LanguageCode:=GetEnv('LANGUAGE');
  FileCount:=0; TagCount:=0;
  BackwardSearch:=False; IgnoreCase:=False; Structures:=False; Typedefs:=False;
  VgrindMode:=False; RecursiveMode:=False; AppendMode:=False;
  CxrefMode:=False; QuietMode:=False; ErrorFound:=False; TagsOpened:=False;
  ArgumentIndex:=1;
  While ArgumentIndex<=ParamCount Do Begin
    Argument:=ParamStr(ArgumentIndex);
    If(Argument='--help')or(Argument='-h')or(Argument='/?')Then Begin PrintHelp; Halt(0); End
    Else If(Argument='--version')or(Argument='-V')Then Begin WriteLn('ctags (LINUX-0) 1.0'); Halt(0); End
    Else If(Length(Argument)>1)and(Argument[1]='-')Then Begin
      If(Length(Argument)>2)and(Argument[2]='-')Then OptionError('option inconnue : '+Argument);
      For OptionIndex:=2 to Length(Argument)Do Begin
        If Argument[OptionIndex]='B'Then BackwardSearch:=True Else
        If Argument[OptionIndex]='S'Then IgnoreCase:=True Else
        If Argument[OptionIndex]='s'Then Structures:=True Else
        If Argument[OptionIndex]='t'Then Typedefs:=True Else
        If Argument[OptionIndex]='v'Then VgrindMode:=True Else
        If Argument[OptionIndex]='r'Then RecursiveMode:=True Else
        If Argument[OptionIndex]='a'Then AppendMode:=True Else
        If Argument[OptionIndex]='T'Then CxrefMode:=True Else
        If Argument[OptionIndex]='q'Then QuietMode:=True Else OptionError('option inconnue : '+Argument);
      End;
    End Else Begin
      If FileCount>=MaxFiles Then OptionError('trop de fichiers');
      Inc(FileCount);
      FileNames[FileCount]:=Argument;
    End;
    Inc(ArgumentIndex);
  End;
  If FileCount=0 Then Begin PrintHelp; Halt(2); End;
  OpenTagOutput;
  For ArgumentIndex:=1 to FileCount Do ProcessPath(FileNames[ArgumentIndex]);
  CloseTagOutput;
  If ErrorFound Then Halt(1);
END.