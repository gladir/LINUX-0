{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2026
  @website(https://www.gladir.com/linux-0)
  @abstract(Target: Turbo Pascal 7, Free Pascal 3.2)
}

Program H2PH(Input,Output);

Uses DOS;

Const
  MaxJobs=128;
  MaxConditions=32;
  MaxArguments=16;

Type
  TText=String[255];
  TPath=String[127];
  TArguments=Array[1..MaxArguments]Of String[63];
  PJob=^TJob;
  TJob=Record
    SourceName,RelativeName:TPath;
    Next:PJob;
  End;
  TCondition=Record
    ElseSeen:Boolean;
  End;

Var
  FirstJob,LastJob:PJob;
  Seen:Array[1..MaxJobs]Of TPath;
  SeenCount:Integer;
  Destination,CurrentSource,CurrentRelative:TPath;
  RecursiveMode,AutomaticMode,DebugMode,QuietMode,English:Boolean;
  ErrorFound,ConversionError,InComment,UseStdin:Boolean;
  Conditions:Array[1..MaxConditions]Of TCondition;
  ConditionDepth,ArgumentCount:Integer;
  MacroArguments:TArguments;
  LineNumber:LongInt;
  LanguageCode:TText;

Function TrimText(Value:TText):TText;
Begin
  While Length(Value)>0 Do Begin
    If Not(Value[1]In[' ',#9,#13])Then Break;
    Delete(Value,1,1);
  End;
  While Length(Value)>0 Do Begin
    If Not(Value[Length(Value)]In[' ',#9,#13])Then Break;
    Delete(Value,Length(Value),1);
  End;
  TrimText:=Value;
End;

Function IdentifierChar(Value:Char):Boolean;
Begin
  IdentifierChar:=Value In['A'..'Z','a'..'z','0'..'9','_'];
End;

Function IdentifierStart(Value:Char):Boolean;
Begin
  IdentifierStart:=Value In['A'..'Z','a'..'z','_'];
End;

Procedure ErrorMessage(Const FrenchText,EnglishText:TText);
Begin
  ErrorFound:=True;
  ConversionError:=True;
  {$IFDEF FPC}
  Write(ErrOutput,'h2ph: ',CurrentSource,':',LineNumber,': ');
  If English Then WriteLn(ErrOutput,EnglishText)
  Else WriteLn(ErrOutput,FrenchText);
  {$ELSE}
  Write('h2ph: ',CurrentSource,':',LineNumber,': ');
  If English Then WriteLn(EnglishText)Else WriteLn(FrenchText);
  {$ENDIF}
End;

Function DirectoryPart(Const Name:TPath):TPath;
Var Index:Integer;
Begin
  DirectoryPart:='';
  For Index:=Length(Name)Downto 1 Do
    If Name[Index]In['/',#92]Then Begin
      DirectoryPart:=Copy(Name,1,Index);
      Exit;
    End;
End;

Function BaseName(Const Name:TPath):TPath;
Var Index:Integer;
Begin
  Index:=Length(Name);
  While Index>0 Do Begin
    If Name[Index]In['/',#92,':']Then Break;
    Dec(Index);
  End;
  BaseName:=Copy(Name,Index+1,127);
End;

Function JoinPath(Const Parent,Child:TPath):TPath;
Var ResultPath:TPath;
Begin
  ResultPath:=Parent;
  If ResultPath<>''Then
    If Not(ResultPath[Length(ResultPath)]In['/',#92])Then Begin
      {$IFDEF UNIX}ResultPath:=ResultPath+'/';
      {$ELSE}ResultPath:=ResultPath+#92;{$ENDIF}
    End;
  If Length(ResultPath)+Length(Child)>127 Then Begin
    ErrorMessage('Chemin trop long','Path is too long');
    JoinPath:='';Exit;
  End;
  JoinPath:=ResultPath+Child;
End;

Function PerlName(Const Name:TPath):TPath;
Var ResultPath:TPath;
Begin
  ResultPath:=Name;
  If Length(ResultPath)>=2 Then
    If Copy(ResultPath,Length(ResultPath)-1,2)='.h'Then
      Delete(ResultPath,Length(ResultPath)-1,2);
  If Length(ResultPath)>124 Then Begin
    ErrorMessage('Nom de sortie trop long','Output filename is too long');
    PerlName:='';Exit;
  End;
  PerlName:=ResultPath+'.ph';
End;

Function SafeRelative(const Name:TPath):Boolean;
Var Index,Start:Integer; Component:TPath;
Begin
  SafeRelative:=False;
  If Name=''Then Exit;
  If Name[1]In['/',#92]Then Exit;
  If Pos(':',Name)>0 Then Exit;
  Start:=1;
  For Index:=1 To Length(Name)+1 Do Begin
    If Index<=Length(Name)Then
      If Not(Name[Index]In['/',#92])Then Continue;
    Component:=Copy(Name,Start,Index-Start);
    If Component='..'Then Exit;
    Start:=Index+1;
  End;
  SafeRelative:=True;
End;

Function Exists(const Name:TPath):Boolean;
Var Entry:SearchRec;
Begin
  FindFirst(Name,AnyFile,Entry);
  Exists:=DosError=0;
  {$IFDEF FPC}FindClose(Entry);{$ENDIF}
End;

Procedure AddJob(Const SourceName,RelativeName:TPath);
Var Index:Integer; FullName:TPath; Job:PJob;
Begin
  FullName:=FExpand(SourceName);
  For Index:=1 To SeenCount Do If Seen[Index]=FullName Then Exit;
  If SeenCount=MaxJobs Then Begin
    ErrorMessage('Trop de fichiers (maximum 128)','Too many files (maximum 128)');
    Exit;
  End;
  Inc(SeenCount);Seen[SeenCount]:=FullName;
  New(Job);Job^.SourceName:=SourceName;
  Job^.RelativeName:=RelativeName;Job^.Next:=Nil;
  If LastJob=Nil Then FirstJob:=Job Else LastJob^.Next:=Job;
  LastJob:=Job;
End;

Procedure CollectPath(Const Name,RelativeName:TPath; Depth:Integer);
Var Entry:SearchRec; Child,ChildRelative,Pattern:TPath;
    IsDirectory:Boolean;
Begin
  If Depth>32 Then Begin
    ErrorMessage('Recursion trop profonde','Recursion is too deep');Exit;
  End;
  FindFirst(Name,AnyFile,Entry);
  If DosError<>0 Then Begin
    ErrorMessage('Fichier introuvable: '+Name,'File not found: '+Name);Exit;
  End;
  IsDirectory:=(Entry.Attr And Directory)<>0;
  {$IFDEF FPC}FindClose(Entry);{$ENDIF}
  If Not IsDirectory Then Begin AddJob(Name,RelativeName);Exit;End;
  If Not RecursiveMode Then Begin
    ErrorMessage('Utilisez -r pour un repertoire','Use -r for a directory');Exit;
  End;
  Pattern:=JoinPath(Name,'*');
  {$IFNDEF FPC}Pattern:=JoinPath(Name,'*.*');{$ENDIF}
  FindFirst(Pattern,AnyFile,Entry);
  While DosError=0 Do Begin
    If(Entry.Name<>'.')And(Entry.Name<>'..')Then Begin
      Child:=JoinPath(Name,Entry.Name);
      ChildRelative:=JoinPath(RelativeName,Entry.Name);
      If(Entry.Attr And Directory)<>0 Then
        CollectPath(Child,ChildRelative,Depth+1)
      Else If Copy(Entry.Name,Length(Entry.Name)-1,2)='.h'Then
        AddJob(Child,ChildRelative);
    End;
    FindNext(Entry);
  End;
  {$IFDEF FPC}FindClose(Entry);{$ENDIF}
End;

Function MakeDirectories(Const Name:TPath):Boolean;
Var Index,Code:Integer; Prefix:TPath; Entry:SearchRec;
Begin
  MakeDirectories:=False;
  For Index:=1 To Length(Name)Do Begin
    If Not(Name[Index]In['/',#92])Then Continue;
    If(Index=1)Or((Index=3)And(Name[2]=':'))Then Continue;
    Prefix:=Copy(Name,1,Index-1);
    FindFirst(Prefix,AnyFile,Entry);
    Code:=DosError;
    If Code=0 Then Begin
      If(Entry.Attr And Directory)=0 Then Code:=5;
    End Else Begin
      {$I-}MkDir(Prefix);{$I+}Code:=IOResult;
    End;
    {$IFDEF FPC}FindClose(Entry);{$ENDIF}
    If Code<>0 Then Begin
      ErrorMessage('Impossible de creer: '+Prefix,'Cannot create: '+Prefix);Exit;
    End;
  End;
  MakeDirectories:=True;
End;

Function StripComments(Const Value:TText):TText;
Var Index:Integer; Quote:Char; ResultText:TText;
Begin
  Index:=1;Quote:=#0;ResultText:='';
  While Index<=Length(Value)Do Begin
    If InComment Then Begin
      If Index<Length(Value)Then
        If Copy(Value,Index,2)='*/'Then Begin
          InComment:=False;Inc(Index,2);Continue;
        End;
      Inc(Index);Continue;
    End;
    If Quote<>#0 Then Begin
      ResultText:=ResultText+Value[Index];
      If(Value[Index]=#92)And(Index<Length(Value))Then Begin
        Inc(Index);ResultText:=ResultText+Value[Index];
      End Else If Value[Index]=Quote Then Quote:=#0;
    End Else If Copy(Value,Index,2)='/*'Then Begin
      InComment:=True;ResultText:=ResultText+' ';Inc(Index,2);Continue;
    End Else If Copy(Value,Index,2)='//'Then Break
    Else Begin
      If Value[Index]In[#34,#39]Then Quote:=Value[Index];
      ResultText:=ResultText+Value[Index];
    End;
    Inc(Index);
  End;
  StripComments:=TrimText(ResultText);
End;

Procedure AppendChecked(Var Value:TText; Const Piece:TText);
Begin
  If Length(Value)+Length(Piece)>255 Then Begin
    ErrorMessage('Expression Perl trop longue','Perl expression too long');Exit;
  End;
  Value:=Value+Piece;
End;

Function Expression(Const Value:TText):TText;
Var Index,Start,ArgIndex:Integer; WordText,ResultText,Piece:TText;
    Quote:Char; DefinedPending,DefinedParenthesis:Boolean;
Begin
  Index:=1;ResultText:='';DefinedPending:=False;DefinedParenthesis:=False;
  While Index<=Length(Value)Do Begin
    If Value[Index]In[#34,#39]Then Begin
      Quote:=Value[Index];Start:=Index;Inc(Index);
      While Index<=Length(Value)Do Begin
        If Value[Index]=#92 Then Inc(Index)
        Else If Value[Index]=Quote Then Break;
        Inc(Index);
      End;
      If Index>Length(Value)Then Begin
        ErrorMessage('Chaine non terminee','Unterminated string');Break;
      End;
      Piece:=Copy(Value,Start,Index-Start+1);
      If Quote=#34 Then Begin
        WordText:='';
        For ArgIndex:=1 To Length(Piece)Do Begin
          If Piece[ArgIndex]In['$','@']Then AppendChecked(WordText,#92);
          AppendChecked(WordText,Piece[ArgIndex]);
        End;
        Piece:=WordText;
      End;
      AppendChecked(ResultText,Piece);Inc(Index);
    End Else If IdentifierStart(Value[Index])Then Begin
      Start:=Index;Inc(Index);
      While Index<=Length(Value)Do Begin
        If Not IdentifierChar(Value[Index])Then Break;
        Inc(Index);
      End;
      WordText:=Copy(Value,Start,Index-Start);
      If WordText='defined'Then Begin
        DefinedPending:=True;
        While Index<=Length(Value)Do Begin
          If Not(Value[Index]In[' ',#9])Then Break;Inc(Index);
        End;
        DefinedParenthesis:=False;
        If Index<=Length(Value)Then
          If Value[Index]='('Then Begin DefinedParenthesis:=True;Inc(Index);End;
      End
      Else Begin
        Piece:='&'+WordText+'()';
        ArgIndex:=Index;
        While ArgIndex<=Length(Value)Do Begin
          If Not(Value[ArgIndex]In[' ',#9])Then Break;Inc(ArgIndex);
        End;
        If ArgIndex<=Length(Value)Then
          If Value[ArgIndex]='('Then Piece:='&'+WordText;
        For ArgIndex:=1 To ArgumentCount Do
          If MacroArguments[ArgIndex]=WordText Then Begin
            Str(ArgIndex-1,Piece);Piece:='$_['+Piece+']';
          End;
        If DefinedPending Then Begin
          Piece:='defined(&'+WordText+')';DefinedPending:=False;
          If DefinedParenthesis Then Begin
            While Index<=Length(Value)Do Begin
              If Not(Value[Index]In[' ',#9])Then Break;Inc(Index);
            End;
            If Index<=Length(Value)Then Begin
              If Value[Index]=')'Then Inc(Index)
              Else ErrorMessage('defined invalide','Invalid defined expression');
            End Else ErrorMessage('defined non termine','Unterminated defined expression');
          End;
        End;
        AppendChecked(ResultText,Piece);
      End;
    End Else If Value[Index]In['0'..'9']Then Begin
      Start:=Index;Inc(Index);
      While Index<=Length(Value)Do Begin
        If Not(Value[Index]In['0'..'9','a'..'f','A'..'F','x','X','.'])Then Break;
        Inc(Index);
      End;
      AppendChecked(ResultText,Copy(Value,Start,Index-Start));
      While Index<=Length(Value)Do Begin
        If Not(Value[Index]In['U','u','L','l'])Then Break;
        Inc(Index);
      End;
    End Else Begin
      If DefinedPending And(Value[Index]In['(',')',' ',#9])Then Begin
        Inc(Index);Continue;
      End;
      If Value[Index]='#'Then
        ErrorMessage('Operateur de macro # non gere','Macro # operator unsupported');
      AppendChecked(ResultText,Value[Index]);Inc(Index);
    End;
  End;
  Expression:=ResultText;
End;

Procedure WritePerlLiteral(Var Target:Text; Const Value:TText);
Var Index:Integer;
Begin
  Write(Target,#39);
  For Index:=1 To Length(Value)Do Begin
    If Value[Index]In[#39,#92]Then Write(Target,#92);
    Write(Target,Value[Index]);
  End;
  Write(Target,#39);
End;

Procedure ConvertLine(Var Target:Text; Const Original:TText);
Var Line,Directive,Name,Value,Converted:TText;
    Index,Start,EndPosition,ArgStart:Integer;
    IncludeSource,IncludeRelative:TPath;
    FunctionMacro:Boolean;
Begin
  Line:=StripComments(Original);
  If DebugMode Then WriteLn(Target,'# C: ',Original);
  If Line=''Then Exit;
  If Line[1]<>'#'Then Begin WriteLn(Target,'# C: ',Line);Exit;End;
  Delete(Line,1,1);Line:=TrimText(Line);
  Index:=1;
  While Index<=Length(Line)Do Begin
    If Not IdentifierChar(Line[Index])Then Break;Inc(Index);
  End;
  Directive:=Copy(Line,1,Index-1);
  Value:=TrimText(Copy(Line,Index,255));
  ArgumentCount:=0;
  If Directive='define'Then Begin
    Index:=1;
    If Value=''Then Begin ErrorMessage('Macro sans nom','Missing macro name');Exit;End;
    If Not IdentifierStart(Value[1])Then Begin
      ErrorMessage('Nom de macro invalide','Invalid macro name');Exit;
    End;
    While Index<=Length(Value)Do Begin
      If Not IdentifierChar(Value[Index])Then Break;Inc(Index);
    End;
    Name:=Copy(Value,1,Index-1);FunctionMacro:=False;
    If Index<=Length(Value)Then FunctionMacro:=Value[Index]='(';
    If FunctionMacro Then Begin
      Inc(Index);
      While Index<=Length(Value)Do Begin
        While Index<=Length(Value)Do Begin
          If Not(Value[Index]In[' ',#9])Then Break;Inc(Index);
        End;
        If Index>Length(Value)Then Break;
        If Value[Index]=')'Then Begin Inc(Index);Break;End;
        ArgStart:=Index;
        While Index<=Length(Value)Do Begin
          If Not IdentifierChar(Value[Index])Then Break;Inc(Index);
        End;
        If(Index=ArgStart)Or(ArgumentCount=MaxArguments)Then Begin
          ErrorMessage('Arguments de macro non geres','Unsupported macro arguments');Exit;
        End;
        Inc(ArgumentCount);
        MacroArguments[ArgumentCount]:=Copy(Value,ArgStart,Index-ArgStart);
        While Index<=Length(Value)Do Begin
          If Not(Value[Index]In[' ',#9])Then Break;Inc(Index);
        End;
        If Index<=Length(Value)Then
          If Value[Index]=','Then Inc(Index)
          Else If Value[Index]<>')'Then Begin
            ErrorMessage('Arguments invalides','Invalid arguments');Exit;
          End;
      End;
    End;
    Value:=TrimText(Copy(Value,Index,255));
    If Value=''Then Value:='1';
    Converted:=Expression(Value);
    WriteLn(Target,'unless (defined &',Name,') {');
    Write(Target,'  eval ');
    WritePerlLiteral(Target,'sub '+Name+' { '+Converted+' }');
    WriteLn(Target,'; die $@ if $@;');
    WriteLn(Target,'}');
  End Else If(Directive='ifdef')Or(Directive='ifndef')Or(Directive='if')Then Begin
    If ConditionDepth=MaxConditions Then Begin
      ErrorMessage('Trop de conditions imbriquees','Too many nested conditions');Exit;
    End;
    Inc(ConditionDepth);Conditions[ConditionDepth].ElseSeen:=False;
    If Directive='ifdef'Then WriteLn(Target,'if (defined &',Value,') {')
    Else If Directive='ifndef'Then WriteLn(Target,'if (!defined &',Value,') {')
    Else Begin Converted:=Expression(Value);WriteLn(Target,'if (',Converted,') {');End;
  End Else If(Directive='else')Or(Directive='elif')Then Begin
    If ConditionDepth=0 Then Begin
      ErrorMessage('Condition sans #if','Conditional without #if');Exit;
    End;
    If Conditions[ConditionDepth].ElseSeen Then Begin
      ErrorMessage('Directive apres #else','Directive after #else');Exit;
    End;
    If Directive='else'Then Begin
      WriteLn(Target,'} else {');Conditions[ConditionDepth].ElseSeen:=True;
    End Else Begin Converted:=Expression(Value);WriteLn(Target,'} elsif (',Converted,') {');End;
  End Else If Directive='endif'Then Begin
    If ConditionDepth=0 Then ErrorMessage('#endif sans #if','#endif without #if')
    Else Begin WriteLn(Target,'}');Dec(ConditionDepth);End;
  End Else If Directive='undef'Then WriteLn(Target,'undef &',Value,';')
  Else If Directive='include'Then Begin
    If Length(Value)<3 Then Begin
      ErrorMessage('Inclusion invalide','Invalid include');Exit;
    End;
    Start:=2;EndPosition:=Start;
    While EndPosition<=Length(Value)Do Begin
      If Value[EndPosition]In[#34,'>']Then Break;Inc(EndPosition);
    End;
    Name:=Copy(Value,Start,EndPosition-Start);
    If Not SafeRelative(Name)Then Begin
      ErrorMessage('Chemin include non gere','Unsupported include path');Exit;
    End;
    IncludeSource:=Name;IncludeRelative:=Name;
    If Value[1]=#34 Then Begin
      IncludeSource:=JoinPath(DirectoryPart(CurrentSource),Name);
      IncludeRelative:=JoinPath(DirectoryPart(CurrentRelative),Name);
      If Not Exists(IncludeSource)Then Begin IncludeSource:=Name;IncludeRelative:=Name;End;
    End;
    Converted:=PerlName(IncludeRelative);
    Write(Target,'require ');WritePerlLiteral(Target,Converted);WriteLn(Target,';');
    If AutomaticMode Then Begin
      If Exists(IncludeSource)Then AddJob(IncludeSource,IncludeRelative)
      Else ErrorMessage('Include introuvable: '+Name,'Include not found: '+Name);
    End;
  End Else WriteLn(Target,'# C: #',Directive,' ',Value);
End;

Procedure ConvertStream(Var Source,Target:Text);
Var Line,LogicalLine:TText; Character:Char; Code:Integer;
    HasData,TooLong:Boolean;
Begin
  ConditionDepth:=0;LineNumber:=0;InComment:=False;LogicalLine:='';
  WriteLn(Target,'# Generated by h2ph (LINUX-0); C declarations remain comments.');
  While True Do Begin
    Line:='';HasData:=False;TooLong:=False;
    While True Do Begin
      {$I-}
      If EOF(Source)Then Begin {$I+}Break;End;
      Read(Source,Character);
      {$I+}Code:=IOResult;
      If Code<>0 Then Begin ErrorMessage('Erreur de lecture','Read error');Exit;End;
      HasData:=True;
      If Character=#10 Then Break;
      If Character<>#13 Then Begin
        If Length(Line)=255 Then TooLong:=True Else Line:=Line+Character;
      End;
    End;
    If Not HasData Then Break;
    Inc(LineNumber);
    If TooLong Then Begin ErrorMessage('Ligne C trop longue','C line too long');Continue;End;
    If Length(LogicalLine)+Length(Line)>255 Then Begin
      ErrorMessage('Macro trop longue','Macro too long');LogicalLine:='';Continue;
    End;
    LogicalLine:=LogicalLine+Line;
    If LogicalLine<>''Then
      If LogicalLine[Length(LogicalLine)]=#92 Then Begin
        Delete(LogicalLine,Length(LogicalLine),1);Continue;
      End;
    ConvertLine(Target,LogicalLine);LogicalLine:='';
    {$I-}Flush(Target);{$I+}Code:=IOResult;
    If Code<>0 Then Begin ErrorMessage('Erreur d''ecriture','Write error');Exit;End;
  End;
  If LogicalLine<>''Then ErrorMessage('Continuation non terminee','Unterminated continuation');
  If InComment Then ErrorMessage('Commentaire non termine','Unterminated comment');
  If ConditionDepth<>0 Then ErrorMessage('Condition non terminee','Unterminated conditional');
  WriteLn(Target,'1;');
End;

Procedure ConvertFile(Job:PJob);
Var Source,Target:Text; OutputName:TPath; Code:Integer;
Begin
  CurrentSource:=Job^.SourceName;CurrentRelative:=Job^.RelativeName;
  ConversionError:=False;LineNumber:=0;
  OutputName:=JoinPath(Destination,PerlName(CurrentRelative));
  If(OutputName='')Or ConversionError Then Exit;
  If Not MakeDirectories(OutputName)Then Exit;
  If FExpand(OutputName)=FExpand(CurrentSource)Then Begin
    ErrorMessage('Source et destination identiques','Source and destination are identical');Exit;
  End;
  Assign(Source,CurrentSource);FileMode:=0;
  {$I-}Reset(Source);{$I+}Code:=IOResult;
  If Code<>0 Then Begin ErrorMessage('Impossible de lire','Cannot read source');Exit;End;
  Assign(Target,OutputName);
  {$I-}Rewrite(Target);{$I+}Code:=IOResult;
  If Code<>0 Then Begin
    {$I-}Close(Source);{$I+}Code:=IOResult;
    ErrorMessage('Impossible de creer '+OutputName,'Cannot create '+OutputName);Exit;
  End;
  ConvertStream(Source,Target);
  {$I-}Close(Source);{$I+}Code:=IOResult;
  If Code<>0 Then ErrorMessage('Erreur de fermeture source','Error closing source');
  {$I-}Close(Target);{$I+}Code:=IOResult;
  If Code<>0 Then ErrorMessage('Erreur de fermeture sortie','Error closing output');
  If ConversionError Then Begin
    {$I-}Erase(Target);{$I+}Code:=IOResult;
  End Else If Not QuietMode Then WriteLn(CurrentSource,' -> ',OutputName);
End;

Procedure PrintHelp;
Begin
  If English Then Begin
    WriteLn('H2PH : Convert basic C header directives into Perl .ph files.');
    WriteLn('Usage: h2ph [-d destination] [-r | -a] [-l] [headerfiles]');
    WriteLn('No files: stdin to stdout. Default destination: current directory.');
    WriteLn('-r: recurse; -a: follow local includes; -D: C comments; -Q: quiet.');
    WriteLn('-l: symbolic link replication is unavailable with DOS alone.');
  End Else Begin
    WriteLn('H2PH : Cette commande permet de convertir les directives des ent'+#136+'tes C en fichiers Perl .ph.');
    WriteLn;
    WriteLn('Syntaxe : h2ph [-d destination] [-r | -a] [-l] [fichiers]');
    WriteLn;
    WriteLn('Sans fichier : stdin vers stdout. Destination par defaut : .');
    WriteLn('Options :');
    WriteLn('-r : Ce param'+#138+'tre active le mode recursif');
    WriteLn('-a : Ce param'+#138+'tre active le suivi des inclusions locales');
    WriteLn('-D : Ce param'+#138+'tre active le traitement des commentaires C');
    WriteLn('-Q : Ce param'+#138+'tre active le mode silencieux');
    WriteLn('-l : Ce param'+#138+'tre active la replication des liens symboliques (indisponible avec DOS seul).');
  End;
  WriteLn('Macros simples, #include, #if, #ifdef, #ifndef, #else, #elif, #endif, #undef.');
End;

Var Index:Integer; Argument,RelativeName:TPath; Job:PJob;
    EndOptions,LinkMode:Boolean;
Begin
  FirstJob:=Nil;LastJob:=Nil;SeenCount:=0;ErrorFound:=False;
  ConversionError:=False;LineNumber:=0;CurrentSource:='';
  Destination:='.';RecursiveMode:=False;AutomaticMode:=False;
  DebugMode:=False;QuietMode:=False;EndOptions:=False;LinkMode:=False;
  LanguageCode:=GetEnv('LANGUAGE');English:=Copy(LanguageCode,1,2)='EN';
  Index:=1;
  While Index<=ParamCount Do Begin
    Argument:=ParamStr(Index);
    If Not EndOptions And(Argument='--')Then EndOptions:=True
    Else If Not EndOptions And((Argument='--help')Or(Argument='-h')Or
      (Argument='/?')Or(Argument='/h')Or(Argument='/H'))Then Begin PrintHelp;Halt(0);End
    Else If Not EndOptions And(Argument='--version')Then Begin
      WriteLn('h2ph (LINUX-0) 1.0');Halt(0);
    End Else If Not EndOptions And(Argument='-d')Then Begin
      Inc(Index);
      If Index>ParamCount Then Begin ErrorMessage('-d attend un chemin','-d needs a path');Halt(2);End;
      Destination:=ParamStr(Index);
    End Else If Not EndOptions And(Argument='-r')Then RecursiveMode:=True
    Else If Not EndOptions And(Argument='-a')Then AutomaticMode:=True
    Else If Not EndOptions And(Argument='-l')Then LinkMode:=True
    Else If Not EndOptions And(Argument='-D')Then DebugMode:=True
    Else If Not EndOptions And(Argument='-Q')Then QuietMode:=True
    Else If Not EndOptions And(Length(Argument)>1)And(Argument[1]='-')Then Begin
      ErrorMessage('Option inconnue: '+Argument,'Unknown option: '+Argument);Halt(2);
    End;
    Inc(Index);
  End;
  If RecursiveMode And AutomaticMode Then Begin
    ErrorMessage('-r et -a sont exclusifs','-r and -a are mutually exclusive');Halt(2);
  End;
  If LinkMode Then Begin
    ErrorMessage('-l non disponible avec DOS seul','-l unavailable with DOS alone');Halt(2);
  End;
  Index:=1;EndOptions:=False;UseStdin:=True;
  While Index<=ParamCount Do Begin
    Argument:=ParamStr(Index);
    If Not EndOptions And(Argument='--')Then EndOptions:=True
    Else If Not EndOptions And(Argument='-d')Then Inc(Index)
    Else If Not EndOptions And(Argument<>'')And(Argument[1]='-')Then Begin End
    Else Begin
      UseStdin:=False;
      RelativeName:=Argument;
      If Not SafeRelative(RelativeName)Then RelativeName:=BaseName(Argument);
      CollectPath(Argument,RelativeName,0);
    End;
    Inc(Index);
  End;
  If UseStdin Then Begin
    CurrentSource:='stdin';CurrentRelative:='';ConversionError:=False;
    ConvertStream(Input,Output);
  End;
  While FirstJob<>Nil Do Begin
    Job:=FirstJob;FirstJob:=Job^.Next;
    If FirstJob=Nil Then LastJob:=Nil;
    ConvertFile(Job);Dispose(Job);
  End;
  If ErrorFound Then Halt(1);
END.