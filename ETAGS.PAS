{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2026
  @website(https://www.gladir.com/linux-0)
  @abstract(Target: Turbo Pascal 7, Free Pascal 3.2)
}

Program ETAGS;

Uses DOS;

Const
 MaxFiles=32;
 MaxTagName=63;
 MaxSourceLine=255;
 ReadBufferSize=1024;

Type
 TFileName=String[127];
 TTagName=String[MaxTagName];
 TSourceLine=String[MaxSourceLine];
 TReadBuffer=Array[1..ReadBufferSize]Of Byte;
 PTag=^TTag;
 TTag=Record
  Name:TTagName;
  LineNumber,ByteOffset:LongInt;
  Next:PTag;
 End;

Var
 SourceFile:File;
 TagFile:Text;
 FileNames:Array[1..MaxFiles]Of TFileName;
 FileCount,ArgumentIndex:Integer;
 OutputName,IncludeName,LanguageName,RegexPattern:String;
 AppendMode,DefinesEnabled,IgnoreIndentation:Boolean;
 RegexEnabled,QuietMode,ErrorFound:Boolean;
 HelpRequested,VersionRequested:Boolean;
 CurrentFile:TFileName;
 TagHead,TagTail:PTag;
 TagCount:LongInt;
 SourceLine:TSourceLine;
 LineNumber,LineOffset,ByteOffset:LongInt;
 CStatement:String;
 CStatementLine,CStatementOffset:LongInt;
 CBraceDepth:Integer;

Function IntToStr(Value:LongInt):String;
Var
 Number:String[20];
Begin
 Str(Value,Number);
 While(Length(Number)>0)And(Number[1]=' ')Do Delete(Number,1,1);
 IntToStr:=Number;
End;

Function IsIdentifierStart(Value:Char):Boolean;
Begin
 IsIdentifierStart:=Value In['A'..'Z','a'..'z','_','$'];
End;

Function IsIdentifierChar(Value:Char):Boolean;
Begin
 IsIdentifierChar:=Value In['A'..'Z','a'..'z','0'..'9','_','$'];
End;

Function LowerCaseText(Value:String):String;
Var
 Index:Integer;
Begin
 For Index:=1 To Length(Value)Do
  If Value[Index]In['A'..'Z']Then Value[Index]:=Chr(Ord(Value[Index])+32);
 LowerCaseText:=Value;
End;

Function TrimLeftText(Value:String):String;
Begin
 While(Length(Value)>0)And(Value[1]In[' ',#9])Do Delete(Value,1,1);
 TrimLeftText:=Value;
End;

Function StartsWith(Const Value,Prefix:String):Boolean;
Var
 Index:Integer;
Begin
 StartsWith:=False;
 If Length(Value)<Length(Prefix)Then Exit;
 For Index:=1 To Length(Prefix)Do
  If Value[Index]<>Prefix[Index]Then Exit;
 StartsWith:=True;
End;

Function IsPascalFile(Const Name:String):Boolean;
Var
 DotPosition,Index:Integer;
 Extension:String;
Begin
 DotPosition:=0;
 For Index:=1 To Length(Name)Do If Name[Index]='.'Then DotPosition:=Index;
 Extension:=LowerCaseText(Copy(Name,DotPosition,Length(Name)));
 IsPascalFile:=(Extension='.pas')Or(Extension='.pp')Or
               (Extension='.p')Or(Extension='.dpr');
End;

Function IsCFile(Const Name:String):Boolean;
Var
 DotPosition,Index:Integer;
 Extension:String;
Begin
 DotPosition:=0;
 For Index:=1 To Length(Name)Do If Name[Index]='.'Then DotPosition:=Index;
 Extension:=LowerCaseText(Copy(Name,DotPosition,Length(Name)));
 IsCFile:=(Extension='.c')Or(Extension='.h')Or(Extension='.cc')Or
          (Extension='.cpp')Or(Extension='.cxx')Or(Extension='.hpp')Or
          (Extension='.m')Or(Extension='.mm');
End;

Function SelectedLanguage(Const Name:String):String;
Begin
 If LanguageName<>''Then SelectedLanguage:=LowerCaseText(LanguageName)
 Else If IsPascalFile(Name)Then SelectedLanguage:='pascal'
 Else If IsCFile(Name)Then SelectedLanguage:='c'
 Else SelectedLanguage:='c';
End;

Function IsKeyword(Const Value:String):Boolean;
Begin
 IsKeyword:=(Value='if')Or(Value='while')Or(Value='for')Or
  (Value='switch')Or(Value='sizeof')Or(Value='return')Or
  (Value='catch')Or(Value='typeof')Or(Value='define')Or
  (Value='procedure')Or(Value='function')Or(Value='class')Or
  (Value='struct')Or(Value='union')Or(Value='enum');
End;

Function FirstIdentifier(Const Value:String;StartAt:Integer):String;
Var
 Position,StartPosition:Integer;
Begin
 FirstIdentifier:='';
 Position:=StartAt;
 While Position<=Length(Value)Do Begin
  If IsIdentifierStart(Value[Position])Then Begin
   StartPosition:=Position;
   Inc(Position);
   While(Position<=Length(Value))And IsIdentifierChar(Value[Position])Do
    Inc(Position);
   FirstIdentifier:=Copy(Value,StartPosition,Position-StartPosition);
   Exit;
  End;
  Inc(Position);
 End;
End;

Function PascalTagName(Const Value:String):String;
Var
 WorkLine,FirstWord,Rest:String;
 SpacePosition:Integer;
Begin
 PascalTagName:='';
 WorkLine:=TrimLeftText(Value);
 SpacePosition:=1;
 While(SpacePosition<=Length(WorkLine))And
      IsIdentifierChar(WorkLine[SpacePosition])Do Inc(SpacePosition);
 FirstWord:=LowerCaseText(Copy(WorkLine,1,SpacePosition-1));
 If(FirstWord<>'procedure')And(FirstWord<>'function')And
   (FirstWord<>'constructor')And(FirstWord<>'destructor')And
   (FirstWord<>'operator')Then Exit;
 Rest:=Copy(WorkLine,SpacePosition,Length(WorkLine));
 PascalTagName:=FirstIdentifier(Rest,1);
End;

Function CFunctionName(Const Value:String):String;
Var
 Position,StartPosition,OpenPosition,ClosePosition,ParenDepth:Integer;
 Candidate:String;
Begin
 CFunctionName:='';
 If(Pos('{',Value)=0)Then Exit;
 Position:=1;
 While Position<=Length(Value)Do Begin
  If IsIdentifierStart(Value[Position])Then Begin
   StartPosition:=Position;
   Inc(Position);
   While(Position<=Length(Value))And IsIdentifierChar(Value[Position])Do
    Inc(Position);
   Candidate:=Copy(Value,StartPosition,Position-StartPosition);
   If IsKeyword(LowerCaseText(Candidate))Then Continue;
   OpenPosition:=Position;
   While(OpenPosition<=Length(Value))And(Value[OpenPosition]In[' ',#9])Do
    Inc(OpenPosition);
   If(OpenPosition<=Length(Value))And(Value[OpenPosition]='(')Then Begin
    ClosePosition:=OpenPosition;
    ParenDepth:=0;
    While ClosePosition<=Length(Value)Do Begin
     If Value[ClosePosition]='('Then Inc(ParenDepth)
     Else If Value[ClosePosition]=')'Then Dec(ParenDepth);
     If(ParenDepth=0)And(ClosePosition>OpenPosition)Then Break;
     Inc(ClosePosition);
    End;
    If(ClosePosition<=Length(Value))And
      (Pos('{',Copy(Value,ClosePosition+1,Length(Value)))>0)Then Begin
     CFunctionName:=Candidate;
     Exit;
    End;
   End;
  End Else Inc(Position);
 End;
End;

Procedure AddTag(Const Name:String;TagLine,TagOffset:LongInt);
Var
 NewTag:PTag;
Begin
 If(Name='')Or(Length(Name)>MaxTagName)Then Exit;
 New(NewTag);
 NewTag^.Name:=Name;
 NewTag^.LineNumber:=TagLine;
 NewTag^.ByteOffset:=TagOffset;
 NewTag^.Next:=Nil;
 If TagHead=Nil Then TagHead:=NewTag
 Else TagTail^.Next:=NewTag;
 TagTail:=NewTag;
 Inc(TagCount);
End;

Procedure ScanDefine(Const Value:String;TagLine,TagOffset:LongInt);
Var
 CleanLine:String;
 Name:String;
 Position:Integer;
Begin
 If Not DefinesEnabled Then Exit;
 CleanLine:=TrimLeftText(Value);
 If(CleanLine='')Or(CleanLine[1]<>'#')Then Exit;
 Position:=2;
 While(Position<=Length(CleanLine))And
      (CleanLine[Position]In[' ',#9])Do Inc(Position);
 If Copy(CleanLine,Position,6)<>'define'Then Exit;
 Inc(Position,6);
 If(Position<=Length(CleanLine))And IsIdentifierChar(CleanLine[Position])Then Exit;
 While(Position<=Length(CleanLine))And
      (CleanLine[Position]In[' ',#9])Do Inc(Position);
 Name:=FirstIdentifier(CleanLine,Position);
 AddTag(Name,TagLine,TagOffset);
End;

Procedure ScanPascalLine(Const Value:String;TagLine,TagOffset:LongInt);
Var
 Name:String;
Begin
 Name:=PascalTagName(Value);
 If Name<>''Then AddTag(Name,TagLine,TagOffset);
End;

Procedure ScanCLine(Const Value:String;TagLine,TagOffset:LongInt);
Var
 CleanLine,Name:String;
 Position:Integer;
Begin
 CleanLine:=TrimLeftText(Value);
 ScanDefine(Value,TagLine,TagOffset);
 If CleanLine<>''Then
  If CleanLine[1]='#'Then Begin
   CStatement:='';
   Exit;
  End;
 If(Pos('//',CleanLine)>0)Then
  CleanLine:=Copy(CleanLine,1,Pos('//',CleanLine)-1);
 If CBraceDepth>0 Then Begin
  For Position:=1 To Length(CleanLine)Do Begin
   If CleanLine[Position]='{'Then Inc(CBraceDepth)
   Else If CleanLine[Position]='}'Then Dec(CBraceDepth);
  End;
  Exit;
 End;
 If CStatement=''Then Begin
  CStatementLine:=TagLine;
  CStatementOffset:=TagOffset;
 End;
 If Length(CStatement)<MaxSourceLine Then
  CStatement:=CStatement+' '+TrimLeftText(CleanLine);
 If(Pos(';',CStatement)>0)And(Pos('{',CStatement)=0)Then Begin
  CStatement:='';
  Exit;
 End;
 Name:=CFunctionName(CStatement);
 If Name<>''Then Begin
  AddTag(Name,CStatementLine,CStatementOffset);
    CBraceDepth:=0;
  For Position:=1 To Length(CStatement)Do Begin
   If CStatement[Position]='{'Then Inc(CBraceDepth)
   Else If CStatement[Position]='}'Then Dec(CBraceDepth);
  End;
  CStatement:='';
 End Else If Pos('{',CStatement)>0 Then CStatement:='';
End;

Procedure ProcessSourceLine(Const Value:String);
Var
 Language,RegexLine:String;
Begin
 Language:=SelectedLanguage(CurrentFile);
 If Language='pascal'Then ScanPascalLine(Value,LineNumber,LineOffset)
 Else ScanCLine(Value,LineNumber,LineOffset);
 If IgnoreIndentation Then RegexLine:=TrimLeftText(Value)
 Else RegexLine:=Value;
 If RegexEnabled And(RegexPattern<>'')And(Pos(RegexPattern,RegexLine)>0)Then
  AddTag(FirstIdentifier(Value,1),LineNumber,LineOffset);
End;

Procedure ReadSource;
Var
 Buffer:TReadBuffer;
 BytesRead,BufferIndex:Word;
 Character:Char;
Begin
 Assign(SourceFile,CurrentFile);
 {$I-}Reset(SourceFile,1);{$I+}
 If IOResult<>0 Then Begin
  If Not QuietMode Then WriteLn('etags: fichier introuvable: ',CurrentFile);
  ErrorFound:=True;
  Exit;
 End;
 TagHead:=Nil;
 TagTail:=Nil;
 TagCount:=0;
 LineNumber:=1;
 LineOffset:=0;
 ByteOffset:=0;
 SourceLine:='';
 CStatement:='';
 CBraceDepth:=0;
 Repeat
  BlockRead(SourceFile,Buffer,SizeOf(Buffer),BytesRead);
  For BufferIndex:=1 To BytesRead Do Begin
   Character:=Chr(Buffer[BufferIndex]);
   If Character=#10 Then Begin
    ProcessSourceLine(SourceLine);
    SourceLine:='';
    Inc(LineNumber);
    LineOffset:=ByteOffset+1;
   End Else If Character<>#13 Then Begin
    If Length(SourceLine)<MaxSourceLine Then
     SourceLine:=SourceLine+Character;
   End;
   Inc(ByteOffset);
  End;
 Until BytesRead=0;
 If SourceLine<>''Then ProcessSourceLine(SourceLine);
 Close(SourceFile);
End;

Procedure FreeTags;
Var
 CurrentTag,NextTag:PTag;
Begin
 CurrentTag:=TagHead;
 While CurrentTag<>Nil Do Begin
  NextTag:=CurrentTag^.Next;
  Dispose(CurrentTag);
  CurrentTag:=NextTag;
 End;
 TagHead:=Nil;
 TagTail:=Nil;
End;

Procedure WriteTagSection;
Var
 CurrentTag:PTag;
 SectionSize:LongInt;
 LineText,OffsetText:String;
Begin
 SectionSize:=0;
 CurrentTag:=TagHead;
 While CurrentTag<>Nil Do Begin
  LineText:=IntToStr(CurrentTag^.LineNumber);
  OffsetText:=IntToStr(CurrentTag^.ByteOffset);
  Inc(SectionSize,Length(CurrentTag^.Name)+1+Length(LineText)+1+
                  Length(OffsetText)+1);
  CurrentTag:=CurrentTag^.Next;
 End;
 Write(TagFile,#12,#10,CurrentFile,',',IntToStr(SectionSize),#10);
 CurrentTag:=TagHead;
 While CurrentTag<>Nil Do Begin
  LineText:=IntToStr(CurrentTag^.LineNumber);
  OffsetText:=IntToStr(CurrentTag^.ByteOffset);
  Write(TagFile,CurrentTag^.Name,#127,LineText,',',OffsetText,#10);
  CurrentTag:=CurrentTag^.Next;
 End;
End;

Procedure ProcessAllFiles;
Var
 FileIndex:Integer;
Begin
 For FileIndex:=1 To FileCount Do Begin
  CurrentFile:=FileNames[FileIndex];
  ReadSource;
  If TagCount>0 Then WriteTagSection;
  FreeTags;
 End;
End;

Procedure ShowHelp;
Begin
 WriteLn('ETAGS - Cette commande permet de automatiquement g'+#130+'n'+#130+'rer et mettre a jour un ',
         'fichier TAGS pour Emacs.');
 WriteLn;
 WriteLn('Syntaxe: ETAGS [options] fichier ...');
 WriteLn;
 WriteLn('  -a, --append              Ajouter au fichier TAGS');
 WriteLn('  -C, --c++                 Analyser le code C/C++');
 WriteLn('  -D, --no-defines          Ignorer les macros #define');
 WriteLn('  -d, --defines             Inclure les macros #define');
 WriteLn('  -H, -h, --help            Afficher cette aide');
 WriteLn('  -i, --include fichier     Ajouter une reference TAGS');
 WriteLn('  -l, --language langage    Forcer le langage');
 WriteLn('  -o, --output fichier      Nom du fichier de sortie');
 WriteLn('  -r, --regex texte         Baliser les lignes contenant le texte');
 WriteLn('  -R, --noregex             Desactiver les balises regex');
 WriteLn('  -S, --ignore-indentation  Ignorer l''indentation initiale');
 WriteLn('  -V, --version             Afficher la version');
End;

Procedure OptionError(Const MessageText:String);
Begin
 WriteLn('etags: ',MessageText);
 Halt(2);
End;

Function NextOptionValue(Var Index:Integer;Const OptionName:String;
                         Const CurrentValue:String):String;
Begin
 If CurrentValue<>''Then NextOptionValue:=CurrentValue
 Else Begin
  Inc(Index);
  If Index>ParamCount Then OptionError('valeur manquante pour '+OptionName);
  NextOptionValue:=ParamStr(Index);
 End;
End;

Procedure AddInputFile(Const Name:String);
Begin
 If FileCount>=MaxFiles Then OptionError('trop de fichiers');
 Inc(FileCount);
 FileNames[FileCount]:=Name;
End;

Procedure ParseLongOption(Const Argument:String;Var Index:Integer);
Var
 Value:String;
 SeparatorPosition:Integer;
Begin
 SeparatorPosition:=Pos('=',Argument);
 If SeparatorPosition>0 Then
  Value:=Copy(Argument,SeparatorPosition+1,MaxSourceLine)
 Else Value:='';
 If(Argument='--help')Then HelpRequested:=True
 Else If(Argument='--version')Then VersionRequested:=True
 Else If(Argument='--append')Then AppendMode:=True
 Else If(Argument='--c++')Then LanguageName:='c++'
 Else If(Argument='--no-defines')Then DefinesEnabled:=False
 Else If(Argument='--defines')Then DefinesEnabled:=True
 Else If(Argument='--ignore-indentation')Then IgnoreIndentation:=True
 Else If(Argument='--noregex')Then RegexEnabled:=False
 Else If(StartsWith(Argument,'--output'))Then
  OutputName:=NextOptionValue(Index,'--output',Value)
 Else If(StartsWith(Argument,'--include'))Then
  IncludeName:=NextOptionValue(Index,'--include',Value)
 Else If(StartsWith(Argument,'--language'))Then
  LanguageName:=NextOptionValue(Index,'--language',Value)
 Else If(StartsWith(Argument,'--regex'))Then
  RegexPattern:=NextOptionValue(Index,'--regex',Value)
 Else OptionError('option inconnue: '+Argument);
End;

Procedure ParseShortOptions(Const Argument:String;Var Index:Integer);
Var
 OptionPosition:Integer;
 OptionLetter:Char;
 Value:String;
Begin
 OptionPosition:=2;
 While OptionPosition<=Length(Argument)Do Begin
  OptionLetter:=Argument[OptionPosition];
  Value:=Copy(Argument,OptionPosition+1,MaxSourceLine);
  If(OptionLetter='o')Or(OptionLetter='i')Or(OptionLetter='l')Or
    (OptionLetter='r')Then Begin
   Value:=NextOptionValue(Index,Copy(Argument,1,2),Value);
   If OptionLetter='o'Then OutputName:=Value
   Else If OptionLetter='i'Then IncludeName:=Value
   Else If OptionLetter='l'Then LanguageName:=Value
   Else RegexPattern:=Value;
   Exit;
  End;
  If OptionLetter='a'Then AppendMode:=True
  Else If OptionLetter='C'Then LanguageName:='c++'
  Else If OptionLetter='D'Then DefinesEnabled:=False
  Else If OptionLetter='d'Then DefinesEnabled:=True
  Else If(OptionLetter='H')Or(OptionLetter='h')Then HelpRequested:=True
  Else If OptionLetter='R'Then RegexEnabled:=False
  Else If OptionLetter='S'Then IgnoreIndentation:=True
  Else If(OptionLetter='V')Or(OptionLetter='v')Then VersionRequested:=True
  Else OptionError('option inconnue: -'+OptionLetter);
  Inc(OptionPosition);
 End;
End;

Procedure ParseOptions;
Var
 Argument:String;
Begin
 ArgumentIndex:=1;
 While ArgumentIndex<=ParamCount Do Begin
  Argument:=ParamStr(ArgumentIndex);
  If(Argument='/?')Or(Argument='/h')Or(Argument='/H')Then
   HelpRequested:=True
  Else If StartsWith(Argument,'--')Then ParseLongOption(Argument,ArgumentIndex)
  Else If(Length(Argument)>1)And(Argument[1]='-')Then
   ParseShortOptions(Argument,ArgumentIndex)
  Else AddInputFile(Argument);
  Inc(ArgumentIndex);
 End;
End;

Procedure OpenOutput;
Begin
 If OutputName=''Then OutputName:='TAGS';
 Assign(TagFile,OutputName);
 If AppendMode Then Begin
  {$I-}Append(TagFile);{$I+}
  If IOResult<>0 Then Begin
   {$I-}Rewrite(TagFile);{$I+}
   If IOResult<>0 Then OptionError('impossible de creer '+OutputName);
  End;
 End Else Begin
  {$I-}Rewrite(TagFile);{$I+}
  If IOResult<>0 Then OptionError('impossible de creer '+OutputName);
 End;
End;

Procedure WriteInclude;
Begin
 If IncludeName<>''Then
  Write(TagFile,#12,#10,IncludeName,',include',#10);
End;

Begin
 FileCount:=0;
 ArgumentIndex:=0;
 OutputName:='';
 IncludeName:='';
 LanguageName:='';
 RegexPattern:='';
 AppendMode:=False;
 DefinesEnabled:=True;
 IgnoreIndentation:=False;
 RegexEnabled:=True;
 QuietMode:=False;
 ErrorFound:=False;
 HelpRequested:=False;
 VersionRequested:=False;
 ParseOptions;
 If HelpRequested Then Begin ShowHelp;Halt(0);End;
 If VersionRequested Then Begin
  WriteLn('etags 1.0 - LINUX-0 Pascal');
  Halt(0);
 End;
 If FileCount=0 Then OptionError('aucun fichier source indique');
 OpenOutput;
 WriteInclude;
 ProcessAllFiles;
 Close(TagFile);
 If ErrorFound Then Halt(1);
End.