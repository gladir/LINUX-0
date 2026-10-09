{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2021
  @website(https://www.gladir.com/linux-0)
  @abstract(Target: Turbo Pascal, Free Pascal)
}

Program CSH;

Uses DOS;

Const
 CommandList:Array[0..40]of String[16]=(
  'alias','bg','cd','chdir','dirs','echo','end','eval','exec','exit',
  'fg','foreach','glob','hashstat','history','jobs','kill','limit',
  'login','logout','nice','nohup','notify','popd','pushd','rehash',
  'repeat','set','setenv','source','stop','suspend','time','umask',
  'unalias','unhash','unlimit','unset','unsetenv','wait','while'
 );

 MaxStackDirectory=50;
 MaxHistory=100;
 MaxVariables=32;
 MaxAliases=32;
 MaxWords=24;
 MaxScriptLines=128;
 MaxSourceDepth=8;
 MaxLoopIterations=10000;

Type
 StrPointer=^String;
 TName=String[31];
 TValue=String[255];
 TShellEntry=Record
  Name:TName;
  Value:TValue;
 End;
 TShellEntryArray=Array[1..MaxVariables]of TShellEntry;
 TWordArray=Array[1..MaxWords]of String[127];
 TScriptLines=Array[1..MaxScriptLines]of String[255];
 PScriptLines=^TScriptLines;
 TScriptFrame=Record
  Lines:PScriptLines;
  LineCount,Position:Integer;
 End;
 TScriptStack=Array[1..MaxSourceDepth]of TScriptFrame;
 TIfFrame=Record
  Condition,ParentEnabled,ElseSeen:Boolean;
 End;
 TIfStack=Array[1..16]of TIfFrame;

Var
 StackDirectory:Array[1..MaxStackDirectory] of StrPointer;
 History:Array[1..MaxHistory] of StrPointer;
 Variables,Aliases:TShellEntryArray;
 IfFrames:TIfStack;
 ScriptFrames:TScriptStack;
 NumberHistory,NumberDirectory:Integer;
 CommandFound,Terminated:Boolean;
 CmdStr,ExpandedCommand,RawCommand,ScriptName,StartupFile,Argument:String;
 CurrCommand,ParamList:String;
 WordList:TWordArray;
 VariableCount,AliasCount,WordCount,ArgumentIndex:Integer;
 I,J:Byte;
BatchMode,ExecuteString,ExitOnError,IgnoreStartup,QuietMode:Boolean;
 InteractiveMode,SyntaxOnly,ReadStandardInput,SingleLine:Boolean;
 VerboseInput,VerboseExpand,VerboseBeforeConfig:Boolean;
 LastStatus:Integer;
 IfDepth:Integer;
 ScriptDepth:Integer;
 LoopDepth:Integer;
 ShellCommand:String;

Function TrimL(S:String):String;
Var
 I:Byte;
Begin
 For I:=1to Length(S)do Begin
  If S[I]<>' 'Then Begin
   TrimL:=Copy(S,I,255);
   Exit;
  End;
 End;
 TrimL:=S;
End;

Function TrimText(S:String):String;
Begin
 While(Length(S)>0)and(S[1]in[' ',#9])Do Delete(S,1,1);
 While(Length(S)>0)and(S[Length(S)]in[' ',#9])Do Delete(S,Length(S),1);
 TrimText:=S;
End;

Function LowerText(S:String):String;
Var
 Index:Integer;
Begin
 For Index:=1 to Length(S)Do
  If S[Index]in['A'..'Z']Then S[Index]:=Chr(Ord(S[Index])+32);
 LowerText:=S;
End;

Function GetShellVariable(Const Name:String):String;
Var
 Index:Integer;
 DirectoryName,StatusText:String;
Begin
 GetShellVariable:='';
 If Name='status'Then Begin
  Str(LastStatus,StatusText);
  GetShellVariable:=StatusText;
  Exit;
 End;
 If Name='cwd'Then Begin
  GetDir(0,DirectoryName);
  GetShellVariable:=DirectoryName;
  Exit;
 End;
 For Index:=1 to VariableCount Do
  If Variables[Index].Name=Name Then Begin
   GetShellVariable:=Variables[Index].Value;
   Exit;
  End;
 GetShellVariable:=GetEnv(Name);
End;

Function ExpandVariables(Const Source:String):String;
Var
 Index,StartPosition:Integer;
 Name,Expanded:String;
Begin
 Expanded:='';
 Index:=1;
 While Index<=Length(Source)Do Begin
  If(Source[Index]='$')and(Index<Length(Source))Then Begin
   Inc(Index);
   If Source[Index]='$'Then Begin
    Expanded:=Expanded+'0';
    Inc(Index);
   End Else If Source[Index]='?'Then Begin
    Str(LastStatus,Name);
    Expanded:=Expanded+Name;
    Inc(Index);
   End Else If Source[Index]='{'Then Begin
    Inc(Index);
    StartPosition:=Index;
    While(Index<=Length(Source))and(Source[Index]<>'}')Do Inc(Index);
    Name:=Copy(Source,StartPosition,Index-StartPosition);
    If Index<=Length(Source)Then Inc(Index);
    Expanded:=Expanded+GetShellVariable(Name);
   End Else Begin
    StartPosition:=Index;
    While(Index<=Length(Source))and
      (Source[Index]in['A'..'Z','a'..'z','0'..'9','_'])Do Inc(Index);
    If Index=StartPosition Then Expanded:=Expanded+'$'
    Else Begin
     Name:=Copy(Source,StartPosition,Index-StartPosition);
     Expanded:=Expanded+GetShellVariable(Name);
    End;
   End;
  End Else Begin
   Expanded:=Expanded+Source[Index];
   Inc(Index);
  End;
 End;
 ExpandVariables:=Expanded;
End;

Procedure ParseWords(Const Source:String);
Var
 Position:Integer;
 Quote:Char;
 CurrentWord:String;
Begin
 WordCount:=0;
 Position:=1;
 Quote:=#0;
 CurrentWord:='';
 While Position<=Length(Source)Do Begin
  If(Source[Position]=#92)and(Position<Length(Source))Then Begin
  If Source[Position+1]in[#92,#34,#39,'$',';',' ',#9]Then Begin
   Inc(Position);
   If Length(CurrentWord)<127 Then CurrentWord:=CurrentWord+Source[Position];
  End Else If Length(CurrentWord)<127 Then
   CurrentWord:=CurrentWord+#92;
  End Else If(Quote<>#0)Then Begin
   If Source[Position]=Quote Then Quote:=#0
   Else If Length(CurrentWord)<127 Then CurrentWord:=CurrentWord+Source[Position];
  End Else If(Source[Position]=#39)or(Source[Position]=#34)Then Begin
   Quote:=Source[Position];
  End Else If Source[Position]in[' ',#9]Then Begin
   If CurrentWord<>''Then Begin
    If WordCount<MaxWords Then Begin
     Inc(WordCount);
     WordList[WordCount]:=CurrentWord;
    End;
    CurrentWord:='';
   End;
  End Else If Length(CurrentWord)<127 Then
   CurrentWord:=CurrentWord+Source[Position];
  Inc(Position);
 End;
 If CurrentWord<>''Then Begin
  If WordCount<MaxWords Then Begin
   Inc(WordCount);
   WordList[WordCount]:=CurrentWord;
  End;
 End;
End;

Function GetParameter(Index:Integer):String;
Begin
 If(Index>=1)and(Index<WordCount)Then GetParameter:=WordList[Index+1]
 Else GetParameter:='';
End;

Function QuoteArgument(Const Value:String):String;
Var
 Index:Integer;
 NeedsQuotes:Boolean;
 ResultValue:String;
Begin
 NeedsQuotes:=(Pos(' ',Value)>0)or(Pos(#9,Value)>0);
 If Not NeedsQuotes Then Begin QuoteArgument:=Value; Exit; End;
 ResultValue:=Chr(34);
 For Index:=1 to Length(Value)Do Begin
  If Value[Index]=Chr(34)Then ResultValue:=ResultValue+Chr(92);
  ResultValue:=ResultValue+Value[Index];
 End;
 ResultValue:=ResultValue+Chr(34);
 QuoteArgument:=ResultValue;
End;

Function ExistingExecutable(Const Name:String):Boolean;
Var
 Search:SearchRec;
Begin
 FindFirst(Name,AnyFile,Search);
 ExistingExecutable:=(DosError=0)and((Search.Attr and Directory)=0);
 {$IFDEF FPC}FindClose(Search);{$ENDIF}
End;

Function FindExecutable(Const Name:String):String;
Var
 PathList,DirectoryName,Candidate,Extension,SystemDirectory:String;
 PathIndex,StartPosition,ExtensionIndex:Integer;
 Separator:Char;
Begin
 FindExecutable:='';
 Separator:=';';
 {$IFDEF UNIX}Separator:=':';{$ENDIF}
 PathList:=GetEnv('PATH');
 For ExtensionIndex:=0 to 2 Do Begin
  Extension:='';
  If(ExtensionIndex=1)and(Pos('.',Name)=0)Then Extension:='.EXE';
  If(ExtensionIndex=2)and(Pos('.',Name)=0)Then Extension:='.COM';
  If(ExtensionIndex>0)and(Pos('.',Name)>0)Then Continue;
  If(Pos('\',Name)>0)or(Pos('/',Name)>0)or(Pos(':',Name)>0)Then Begin
   Candidate:=Name+Extension;
   If ExistingExecutable(Candidate)Then Begin FindExecutable:=Candidate; Exit; End;
  End Else Begin
   StartPosition:=1;
   For PathIndex:=1 to Length(PathList)+1 Do Begin
    If(PathIndex>Length(PathList))or(PathList[PathIndex]=Separator)Then Begin
     DirectoryName:=Copy(PathList,StartPosition,PathIndex-StartPosition);
     If DirectoryName=''Then DirectoryName:='.';
     If(DirectoryName[Length(DirectoryName)]<>'\')and
       (DirectoryName[Length(DirectoryName)]<>'/')Then Begin
      If(Pos('/',DirectoryName)>0)and(Pos('\',DirectoryName)=0)Then
       DirectoryName:=DirectoryName+'/'
      Else DirectoryName:=DirectoryName+'\';
     End;
     Candidate:=DirectoryName+Name+Extension;
     If ExistingExecutable(Candidate)Then Begin FindExecutable:=Candidate; Exit; End;
     StartPosition:=PathIndex+1;
    End;
   End;
  End;
 End;
 {$IFDEF WINDOWS}
 SystemDirectory:=GetEnv('WINDIR');
 If SystemDirectory=''Then SystemDirectory:=GetEnv('SYSTEMROOT');
 If SystemDirectory<>''Then Begin
  If SystemDirectory[Length(SystemDirectory)]<>'\'Then
   SystemDirectory:=SystemDirectory+'\';
  SystemDirectory:=SystemDirectory+'System32\';
  Candidate:=SystemDirectory+Name;
  If ExistingExecutable(Candidate)Then FindExecutable:=Candidate;
 End;
 {$ENDIF}
End;

Function BuildParameterList:String;
Var
 Index:Integer;
 ResultValue:String;
Begin
 ResultValue:='';
 For Index:=2 to WordCount Do Begin
  If ResultValue<>''Then ResultValue:=ResultValue+' ';
  ResultValue:=ResultValue+QuoteArgument(WordList[Index]);
 End;
 BuildParameterList:=ResultValue;
End;

Procedure ExtractCommand;
Begin
 ParseWords(CmdStr);
 If WordCount=0 Then Begin CurrCommand:=''; ParamList:=''; Exit; End;
 CurrCommand:=LowerText(WordList[1]);
 ParamList:=BuildParameterList;
End;

Function ExtractParam(Index:Byte):String;
Begin
 ExtractParam:=GetParameter(Index);
End;

Function FindEntry(Var Entries:TShellEntryArray; EntryCount:Integer;
                   Const EntryName:String):Integer;
Var
 Index:Integer;
Begin
 FindEntry:=0;
 For Index:=1 to EntryCount Do
  If Entries[Index].Name=EntryName Then Begin
   FindEntry:=Index;
   Exit;
  End;
End;

Procedure StoreEntry(Var Entries:TShellEntryArray; Var EntryCount:Integer;
                     Const EntryName,EntryValue:String);
Var
 Index:Integer;
Begin
 If(EntryName='')or(Length(EntryName)>31)Then Begin
  WriteLn('Nom de variable invalide');
  LastStatus:=1;
  Exit;
 End;
 Index:=FindEntry(Entries,EntryCount,EntryName);
 If Index=0 Then Begin
  If EntryCount>=MaxVariables Then Begin
   WriteLn('Trop de variables');
   LastStatus:=1;
   Exit;
  End;
  Inc(EntryCount);
  Index:=EntryCount;
 End;
 Entries[Index].Name:=EntryName;
 Entries[Index].Value:=EntryValue;
 LastStatus:=0;
End;

Procedure DeleteEntry(Var Entries:TShellEntryArray; Var EntryCount:Integer;
                      Const EntryName:String);
Var
 Index,ShiftIndex:Integer;
Begin
 Index:=FindEntry(Entries,EntryCount,EntryName);
 If Index=0 Then Begin LastStatus:=1; Exit; End;
 For ShiftIndex:=Index to EntryCount-1 Do Entries[ShiftIndex]:=Entries[ShiftIndex+1];
 Dec(EntryCount);
 LastStatus:=0;
End;

Function ExpandAlias(Const Line:String):String;
Var
 Pass,Index:Integer;
 OriginalLine,FirstWord:String;
Begin
 OriginalLine:=Line;
 For Pass:=1 to 8 Do Begin
  ParseWords(OriginalLine);
  If WordCount=0 Then Break;
  Index:=FindEntry(Aliases,AliasCount,WordList[1]);
  If Index=0 Then Break;
  FirstWord:=Aliases[Index].Value;
  For Index:=2 to WordCount Do
   FirstWord:=FirstWord+' '+QuoteArgument(WordList[Index]);
  If FirstWord=OriginalLine Then Break;
  OriginalLine:=FirstWord;
 End;
 ExpandAlias:=OriginalLine;
End;

Procedure ProcessLine(Const Line:String);Forward;
Procedure RunExternal;Forward;

Function AddHistory(S:String):Boolean;
Var
 I:Word;
 P:StrPointer;
Begin
 If NumberHistory>=MaxHistory Then Begin
  FreeMem(History[1],Length(History[1]^)+1);
  For I:=1 to MaxHistory-1 do History[I]:=History[I+1];
  GetMem(P,Length(S)+1);
  P^:=S;
  History[MaxHistory]:=P;
  AddHistory:=True;
  Exit;
 End
  Else
 Begin
  Inc(NumberHistory);
  GetMem(P,Length(S)+1);
  P^:=S;
  History[NumberHistory]:=P;
  AddHistory:=True;
 End;
End;

Function PushDirectory(Directory:String):Boolean;
Var
 P:StrPointer;
Begin
 If NumberDirectory>=MaxStackDirectory Then Begin
  WriteLn('Pile de r�pertoire pleine');
  PushDirectory:=False;
  Exit;
 End;
 Inc(NumberDirectory);
 GetMem(P,Length(Directory)+1);
 P^:=Directory;
 StackDirectory[NumberDirectory]:=P;
 PushDirectory:=True;
End;

Function PopDirectory:String;Begin
 PopDirectory:='';
 If NumberDirectory>0Then Begin
  PopDirectory:=StackDirectory[NumberDirectory]^;
  FreeMem(StackDirectory[NumberDirectory],Length(StackDirectory[NumberDirectory]^)+1);
  Dec(NumberDirectory);
 End;
End;

Procedure HomeMessage;Begin
 WriteLn;
 WriteLn('csh - C Shell');
 WriteLn;
End;

Procedure ShowPrompt;Begin
 Write('%');
End;

Procedure AliasCommand;
Var
 Index,AliasIndex:Integer;
 AliasValue:String;
Begin
 If WordCount=1 Then Begin
  For Index:=1 to AliasCount Do
   WriteLn('alias ',Aliases[Index].Name,' ',Aliases[Index].Value);
  LastStatus:=0;
  Exit;
 End;
 AliasIndex:=FindEntry(Aliases,AliasCount,WordList[2]);
 If WordCount=2 Then Begin
  If AliasIndex=0 Then LastStatus:=1
  Else WriteLn('alias ',Aliases[AliasIndex].Name,' ',Aliases[AliasIndex].Value);
  Exit;
 End;
 AliasValue:='';
 For Index:=3 to WordCount Do Begin
  If AliasValue<>''Then AliasValue:=AliasValue+' ';
  AliasValue:=AliasValue+WordList[Index];
 End;
 StoreEntry(Aliases,AliasCount,WordList[2],AliasValue);
End;

Procedure BgCommand;Begin
 WriteLn('Cette commande n''est pas mise en oeuvre');
End;

Procedure ChdirCommand;
Var
 Error:Word;
 FirstParam,Dir:String;
Begin
 FirstParam:=ExtractParam(1);
 If FirstParam='-h'Then Begin
  WriteLn('chdir   Cette commande permet de fixer ou de demander le repertoire courant.');
  WriteLn;
  WriteLn('Syntaxe:');
  WriteLn;
  WriteLn('cd [-h] chemin');
  WriteLn('chdir [-h] chemin');
  WriteLn;
  WriteLn('  -h     Ce parametre permet d''afficher l''aide sur cette commande');
  WriteLn(' chemin  Ce parametre permet d''indiquer le chemin du repertoire.');
 End
  Else
 If Length(FirstParam)>0Then Begin
  {$I-} ChDir(FirstParam);{$I+}
  Error:=IoResult;
  If Error<>0Then WriteLn('Impossible de changer de repertoire');
 End
  Else
 Begin
  GetDir(0,Dir);
  WriteLn(Dir);
 End;
End;

Procedure DirsCommand;
Var
 Index:Integer;
 DirectoryName:String;
Begin
 GetDir(0,DirectoryName);
 Write(DirectoryName);
 For Index:=NumberDirectory downto 1 Do Write(' ',StackDirectory[Index]^);
 WriteLn;
 LastStatus:=0;
End;

Procedure EchoCommand;Begin WriteLn(ParamList); LastStatus:=0; End;

Procedure EndCommand;Begin
 WriteLn('Cette commande n''est pas mise en oeuvre');
End;

Procedure EvalCommand;Begin
 WriteLn('Cette commande n''est pas mise en oeuvre');
End;

Procedure ExecCommand;
Begin
 If WordCount<2 Then Begin LastStatus:=0; Exit; End;
 CurrCommand:=WordList[2];
 ParamList:='';
 For I:=3 to WordCount Do Begin
  If ParamList<>''Then ParamList:=ParamList+' ';
  ParamList:=ParamList+QuoteArgument(WordList[I]);
 End;
 RunExternal;
End;

Procedure ExitCommand;Begin
 Terminated:=True;
End;

Procedure FgCommand;Begin
 WriteLn('Cette commande n''est pas mise en oeuvre');
End;

Function FindScriptBlockEnd(StartLine:Integer):Integer;
Var
 Index,Nesting:Integer;
 CommandName:String;
Begin
 FindScriptBlockEnd:=0;
 Nesting:=1;
 For Index:=StartLine+1 to ScriptFrames[ScriptDepth].LineCount Do Begin
  ParseWords(ScriptFrames[ScriptDepth].Lines^[Index]);
  If WordCount>0 Then Begin
   CommandName:=LowerText(WordList[1]);
   If(CommandName='foreach')or(CommandName='while')Then Inc(Nesting)
   Else If CommandName='end'Then Begin
    Dec(Nesting);
    If Nesting=0 Then Begin FindScriptBlockEnd:=Index; Exit; End;
   End;
  End;
 End;
End;

Procedure ForeachCommand;
Var
 Values:TWordArray;
 ValueCount,Index,OpenPosition,ClosePosition,EndIndex,BodyIndex,FrameIndex,BlockStart:Integer;
 VariableName,ValueList,CurrentBodyLine:String;
Begin
 If ScriptDepth=0 Then Begin
  WriteLn('foreach: un bloc foreach doit provenir d''un script');
  LastStatus:=1;
  Exit;
 End;
 If WordCount<2 Then Begin WriteLn('foreach: nom de variable requis'); LastStatus:=1; Exit; End;
 VariableName:=WordList[2];
 OpenPosition:=Pos('(',ExpandedCommand);
 ClosePosition:=Pos(')',ExpandedCommand);
 If(OpenPosition=0)or(ClosePosition<=OpenPosition)Then Begin
  WriteLn('foreach: liste attendue entre parentheses'); LastStatus:=1; Exit;
 End;
 ValueList:=Copy(ExpandedCommand,OpenPosition+1,ClosePosition-OpenPosition-1);
 ParseWords(ValueList);
 ValueCount:=WordCount;
 For Index:=1 to ValueCount Do Values[Index]:=WordList[Index];
 BlockStart:=ScriptFrames[ScriptDepth].Position;
 EndIndex:=FindScriptBlockEnd(BlockStart);
 If EndIndex=0 Then Begin WriteLn('foreach: end manquant'); LastStatus:=1; Exit; End;
 If LoopDepth>=8 Then Begin WriteLn('foreach: imbrication trop profonde'); LastStatus:=1; Exit; End;
 Inc(LoopDepth);
 FrameIndex:=ScriptDepth;
 For Index:=1 to ValueCount Do Begin
  StoreEntry(Variables,VariableCount,VariableName,Values[Index]);
  BodyIndex:=BlockStart+1;
  While(BodyIndex<EndIndex)and Not Terminated Do Begin
   CurrentBodyLine:=ScriptFrames[FrameIndex].Lines^[BodyIndex];
   ScriptFrames[FrameIndex].Position:=BodyIndex;
   ProcessLine(CurrentBodyLine);
   BodyIndex:=ScriptFrames[FrameIndex].Position+1;
  End;
 End;
 ScriptFrames[FrameIndex].Position:=EndIndex;
 Dec(LoopDepth);
 LastStatus:=0;
End;

Procedure GlobCommand;Begin
 WriteLn('Cette commande n''est pas mise en oeuvre');
End;

Procedure HashstatCommand;Begin
 WriteLn('Cette commande n''est pas mise en oeuvre');
End;

Procedure HistoryCommand;
Var
 I:Integer;
 FirstParam:String;
Begin
 FirstParam:=ExtractParam(1);
 If FirstParam='-h'Then Begin
  WriteLn('history   Cette commande permet d''afficher l''historique des commandes.');
  WriteLn;
  WriteLn('Syntaxe:');
  WriteLn;
  WriteLn('history [-h]');
  WriteLn;
  WriteLn('  -h    Ce parametre permet d''afficher l''aide sur cette commande');
 End
  Else
 For I:=1 to NumberHistory do WriteLn(History[I]^);
End;

Procedure JobsCommand;Begin
 WriteLn('Cette commande n''est pas mise en oeuvre');
End;

Procedure KillCommand;Begin
 WriteLn('Cette commande n''est pas mise en oeuvre');
End;

Procedure LimitCommand;Begin
 WriteLn('Cette commande n''est pas mise en oeuvre');
End;

Procedure LoginCommand;Begin
 WriteLn('Cette commande n''est pas mise en oeuvre');
End;

Procedure LogoutCommand;
Var
 Value:Integer;
 Err:Word;
Begin
 If ParamList<>''Then Begin
  Val(ParamList,Value,Err);
  Halt(Value);
 End
  Else
 Terminated:=True;
End;

Procedure NiceCommand;Begin
 WriteLn('Cette commande n''est pas mise en oeuvre');
End;

Procedure NohupCommand;Begin
 WriteLn('Cette commande n''est pas mise en oeuvre');
End;

Procedure NotifyCommand;Begin
 WriteLn('Cette commande n''est pas mise en oeuvre');
End;

Procedure PopdCommand;
Var
 Error:Word;
 FirstParam,Dir:String;
Begin
 FirstParam:=ExtractParam(1);
 If FirstParam='-h'Then Begin
  WriteLn('popd   Cette commande permet de restaurer le repertoire.');
  WriteLn;
  WriteLn('Syntaxe:');
  WriteLn;
  WriteLn('popd [-h]');
  WriteLn;
  WriteLn('  -h     Ce parametre permet d''afficher l''aide sur cette commande');
 End
  Else
 Begin
  Dir:=PopDirectory;
    If Dir=''Then Begin WriteLn('popd: pile de repertoires vide'); LastStatus:=1; Exit; End;
  {$I-} ChDir(Dir);{$I+}
  Error:=IoResult;
    If Error<>0Then WriteLn('Impossible de changer de repertoire');
    If Error=0Then LastStatus:=0 Else LastStatus:=1;
 End;
End;

Procedure PushdCommand;
Var
 Error:Word;
 FirstParam,Dir:String;
Begin
 FirstParam:=ExtractParam(1);
 If FirstParam='-h'Then Begin
  WriteLn('pushd   Cette commande permet de sauver le repertoire.');
  WriteLn;
  WriteLn('Syntaxe:');
  WriteLn;
  WriteLn('pushd [-h] [chemin]');
  WriteLn;
  WriteLn('  -h     Ce parametre permet d''afficher l''aide sur cette commande');
  WriteLn(' chemin  Ce parametre permet d''indiquer le repertoire a mettre a la place.');
 End
  Else
 If Length(FirstParam)>0Then Begin
    GetDir(0,Dir);
    If Not(PushDirectory(Dir))Then WriteLn('Pile pleine');
  {$I-} ChDir(FirstParam);{$I+}
  Error:=IoResult;
  If Error<>0Then Begin
   WriteLn('Impossible de changer de repertoire');
   PopDirectory;
   LastStatus:=1;
  End Else LastStatus:=0;
 End
  Else
 Begin
  GetDir(0,Dir);
  If Not(PushDirectory(Dir))Then WriteLn('Pile pleine');
 End;
End;

Procedure RehashCommand;Begin
 WriteLn('Cette commande n''est pas mise en oeuvre');
End;

Procedure RepeatCommand;Begin
 WriteLn('Cette commande n''est pas mise en oeuvre');
End;

Procedure SetCommand;
Var
 Index,EqualPosition:Integer;
 VariableName,VariableValue:String;
Begin
 If WordCount=1 Then Begin
  For Index:=1 to VariableCount Do
   WriteLn('set ',Variables[Index].Name,' = ',Variables[Index].Value);
  LastStatus:=0;
  Exit;
 End;
 VariableName:=WordList[2];
 EqualPosition:=Pos('=',VariableName);
 If EqualPosition>0 Then Begin
  VariableValue:=Copy(VariableName,EqualPosition+1,255);
  VariableName:=Copy(VariableName,1,EqualPosition-1);
 End Else If(WordCount>=4)and(WordList[3]='=')Then Begin
  VariableValue:='';
  For Index:=4 to WordCount Do Begin
   If VariableValue<>''Then VariableValue:=VariableValue+' ';
   VariableValue:=VariableValue+WordList[Index];
  End;
 End Else If WordCount>=3 Then Begin
  VariableValue:='';
  For Index:=3 to WordCount Do Begin
   If VariableValue<>''Then VariableValue:=VariableValue+' ';
   VariableValue:=VariableValue+WordList[Index];
  End;
 End Else VariableValue:='';
 StoreEntry(Variables,VariableCount,VariableName,VariableValue);
End;

Procedure SetEnvCommand;Begin SetCommand; End;

Procedure SourceCommand;
Var
 SourceFile:Text;
 SourceLine,Name:String;
Begin
 Name:=ExtractParam(1);
 If Name=''Then Begin WriteLn('source: fichier requis'); LastStatus:=1; Exit; End;
 Assign(SourceFile,Name);
 {$I-}Reset(SourceFile);{$I+}
 If IOResult<>0 Then Begin WriteLn('source: impossible de lire ',Name); LastStatus:=1; Exit; End;
 While Not EOF(SourceFile)and Not Terminated Do Begin
  ReadLn(SourceFile,SourceLine);
  ProcessLine(SourceLine);
 End;
 Close(SourceFile);
End;

Procedure StopCommand;Begin
 WriteLn('Cette commande n''est pas mise en oeuvre');
End;

Procedure SuspendCommand;Begin
 WriteLn('Cette commande n''est pas mise en oeuvre');
End;

Procedure TimeCommand;Begin
 WriteLn('Cette commande n''est pas mise en oeuvre');
End;

Procedure UmaskCommand;Begin
 WriteLn('Cette commande n''est pas mise en oeuvre');
End;

Procedure UnaliasCommand;
Var
 Index:Integer;
Begin
 If WordCount<2 Then Begin WriteLn('unalias: nom requis'); LastStatus:=1; Exit; End;
 For Index:=2 to WordCount Do DeleteEntry(Aliases,AliasCount,WordList[Index]);
End;

Procedure UnhashCommand;Begin
 WriteLn('Cette commande n''est pas mise en oeuvre');
End;

Procedure UnlimitCommand;Begin
 WriteLn('Cette commande n''est pas mise en oeuvre');
End;

Procedure UnsetCommand;
Var
 Index:Integer;
Begin
 For Index:=2 to WordCount Do DeleteEntry(Variables,VariableCount,WordList[Index]);
End;

Procedure UnsetenvCommand;Begin UnsetCommand; End;

Procedure WaitCommand;Begin
 WriteLn('Cette commande n''est pas mise en oeuvre');
End;

Function EvaluateCondition(Const ConditionText:String):Boolean;Forward;

Procedure WhileCommand;
Var
 OpenPosition,ClosePosition,EndIndex,BodyIndex,FrameIndex,Iteration,BlockStart:Integer;
 ConditionText,BodyLine:String;
Begin
 If ScriptDepth=0 Then Begin
  WriteLn('while: un bloc while doit provenir d''un script');
  LastStatus:=1;
  Exit;
 End;
 OpenPosition:=Pos('(',RawCommand);
 ClosePosition:=0;
 If OpenPosition>0 Then
  For BodyIndex:=OpenPosition+1 to Length(RawCommand)Do
   If RawCommand[BodyIndex]=')'Then Begin ClosePosition:=BodyIndex; Break; End;
 If(OpenPosition=0)or(ClosePosition=0)Then Begin
  WriteLn('while: condition entre parentheses requise');
  LastStatus:=1;
  Exit;
 End;
 ConditionText:=Copy(RawCommand,OpenPosition+1,ClosePosition-OpenPosition-1);
 BlockStart:=ScriptFrames[ScriptDepth].Position;
 EndIndex:=FindScriptBlockEnd(BlockStart);
 If EndIndex=0 Then Begin WriteLn('while: end manquant'); LastStatus:=1; Exit; End;
 If LoopDepth>=8 Then Begin WriteLn('while: imbrication trop profonde'); LastStatus:=1; Exit; End;
 Inc(LoopDepth);
 FrameIndex:=ScriptDepth;
 Iteration:=0;
 While EvaluateCondition(ExpandVariables(ConditionText))and Not Terminated Do Begin
  Inc(Iteration);
  If Iteration>MaxLoopIterations Then Begin
   WriteLn('while: limite d''iterations depasse');
   LastStatus:=1;
   Break;
  End;
  BodyIndex:=BlockStart+1;
  While(BodyIndex<EndIndex)and Not Terminated Do Begin
   BodyLine:=ScriptFrames[FrameIndex].Lines^[BodyIndex];
   ScriptFrames[FrameIndex].Position:=BodyIndex;
   ProcessLine(BodyLine);
   BodyIndex:=ScriptFrames[FrameIndex].Position+1;
  End;
End;
  ScriptFrames[FrameIndex].Position:=EndIndex;
  Dec(LoopDepth);
End;

Function CurrentBranchEnabled:Boolean;
Var
 Index:Integer;
 Branch:Boolean;
Begin
 Branch:=True;
 For Index:=1 to IfDepth Do Begin
  If IfFrames[Index].ElseSeen Then
   Branch:=Branch and IfFrames[Index].ParentEnabled and
           Not IfFrames[Index].Condition
  Else Branch:=Branch and IfFrames[Index].ParentEnabled and
               IfFrames[Index].Condition;
 End;
 CurrentBranchEnabled:=Branch;
End;

Function EvaluateCondition(Const ConditionText:String):Boolean;
Var
 LeftValue,RightValue,OperatorText:String;
 LeftNumber,RightNumber:LongInt;
 ErrorLeft,ErrorRight:Integer;
Begin
 EvaluateCondition:=False;
 ParseWords(ConditionText);
 If WordCount=0 Then Exit;
 If WordCount=1 Then Begin
  EvaluateCondition:=(WordList[1]<>'')and(WordList[1]<>'0')and
                     (LowerText(WordList[1])<>'false');
  Exit;
 End;
 If WordCount<3 Then Exit;
 LeftValue:=WordList[1];
 OperatorText:=WordList[2];
 RightValue:=WordList[3];
 If(LeftValue=RightValue)and(OperatorText='==')Then EvaluateCondition:=True Else
 If(LeftValue<>RightValue)and(OperatorText='!=')Then EvaluateCondition:=True Else
 If(OperatorText='=')Then EvaluateCondition:=LeftValue=RightValue Else
 If(OperatorText='!=')Then EvaluateCondition:=LeftValue<>RightValue Else Begin
  Val(LeftValue,LeftNumber,ErrorLeft);
  Val(RightValue,RightNumber,ErrorRight);
  If(ErrorLeft=0)and(ErrorRight=0)Then Begin
   If(OperatorText='-eq')or(OperatorText='==')Then EvaluateCondition:=LeftNumber=RightNumber Else
   If OperatorText='-ne'Then EvaluateCondition:=LeftNumber<>RightNumber Else
   If(OperatorText='-gt')or(OperatorText='>')Then EvaluateCondition:=LeftNumber>RightNumber Else
   If(OperatorText='-lt')or(OperatorText='<')Then EvaluateCondition:=LeftNumber<RightNumber Else
   If OperatorText='-ge'Then EvaluateCondition:=LeftNumber>=RightNumber Else
   If OperatorText='-le'Then EvaluateCondition:=LeftNumber<=RightNumber;
  End;
 End;
End;

Procedure RunExternal;
Var
 ProgramPath:String;
Begin
 If SyntaxOnly Then Begin LastStatus:=0; Exit; End;
 ProgramPath:=FindExecutable(CurrCommand);
 If ProgramPath=''Then Begin
  If Not QuietMode Then WriteLn(CurrCommand,': commande introuvable');
  LastStatus:=127;
  Exit;
 End;
 {$I-}SwapVectors;Exec(ProgramPath,ParamList);SwapVectors;{$I+}
 If DosError<>0 Then Begin
  If Not QuietMode Then WriteLn(CurrCommand,': impossible de lancer la commande');
  LastStatus:=127;
 End Else LastStatus:=DosExitCode;
End;

Procedure ExecuteSingle(Const SourceLine:String);
Var
 OpenPosition,ClosePosition,Index,LoopCount,LoopIndex:Integer;
 ConditionText,CommandTail,Expanded:String;
 ErrorNumber:Integer;
 ParentEnabled:Boolean;
Begin
 Expanded:=ExpandVariables(TrimText(SourceLine));
 RawCommand:=TrimText(SourceLine);
 Expanded:=ExpandAlias(Expanded);
 ExpandedCommand:=Expanded;
 If VerboseExpand and(Expanded<>'')Then WriteLn('+ ',Expanded);
 CmdStr:=Expanded;
 ExtractCommand;
 If CurrCommand=''Then Exit;

 If CurrCommand='if'Then Begin
  OpenPosition:=Pos('(',Expanded);
  ClosePosition:=0;
  If OpenPosition>0 Then
   For Index:=OpenPosition+1 to Length(Expanded)Do
    If Expanded[Index]=')'Then Begin ClosePosition:=Index; Break; End;
  If(OpenPosition=0)or(ClosePosition=0)Then Begin
   WriteLn('if: syntaxe attendue: if (condition) [then|commande]');
   LastStatus:=1;
   Exit;
  End;
  ConditionText:=Copy(Expanded,OpenPosition+1,ClosePosition-OpenPosition-1);
  CommandTail:=TrimText(Copy(Expanded,ClosePosition+1,255));
  If Copy(CommandTail,1,4)='then'Then
   CommandTail:=TrimText(Copy(CommandTail,5,255));
  If CommandTail=''Then Begin
   If IfDepth>=16 Then Begin WriteLn('if: imbrication trop profonde'); LastStatus:=1; Exit; End;
    ParentEnabled:=CurrentBranchEnabled;
   Inc(IfDepth);
    IfFrames[IfDepth].ParentEnabled:=ParentEnabled;
   IfFrames[IfDepth].Condition:=EvaluateCondition(ConditionText);
   IfFrames[IfDepth].ElseSeen:=False;
   LastStatus:=0;
  End Else If CurrentBranchEnabled and EvaluateCondition(ConditionText)Then
   ProcessLine(CommandTail);
  Exit;
 End;
 If CurrCommand='else'Then Begin
  If IfDepth=0 Then Begin WriteLn('else sans if'); LastStatus:=1; End
  Else IfFrames[IfDepth].ElseSeen:=Not IfFrames[IfDepth].ElseSeen;
  Exit;
 End;
 If(CurrCommand='endif')or(CurrCommand='endif;')Then Begin
  If IfDepth>0 Then Dec(IfDepth)Else Begin WriteLn('endif sans if'); LastStatus:=1; End;
  Exit;
 End;
 If Not CurrentBranchEnabled Then Exit;
 If SyntaxOnly Then Begin LastStatus:=0; Exit; End;

 If CurrCommand='alias'Then AliasCommand Else
 If CurrCommand='unalias'Then UnaliasCommand Else
 If CurrCommand='set'Then SetCommand Else
 If CurrCommand='setenv'Then SetEnvCommand Else
 If CurrCommand='unset'Then UnsetCommand Else
 If CurrCommand='unsetenv'Then UnsetenvCommand Else
 If(CurrCommand='cd')or(CurrCommand='chdir')Then ChdirCommand Else
 If CurrCommand='pushd'Then PushdCommand Else
 If CurrCommand='popd'Then PopdCommand Else
 If CurrCommand='dirs'Then DirsCommand Else
 If CurrCommand='echo'Then EchoCommand Else
 If CurrCommand='history'Then HistoryCommand Else
 If CurrCommand='source'Then SourceCommand Else
 If CurrCommand='exit'Then ExitCommand Else
 If CurrCommand='logout'Then LogoutCommand Else
 If CurrCommand='exec'Then ExecCommand Else
 If CurrCommand='eval'Then EvalCommand Else
 If CurrCommand='foreach'Then ForeachCommand Else
 If CurrCommand='while'Then WhileCommand Else
 If CurrCommand='repeat'Then Begin
  Val(ExtractParam(1),LoopCount,ErrorNumber);
  If(ErrorNumber<>0)or(LoopCount<0)Then Begin LastStatus:=1; WriteLn('repeat: nombre invalide'); End
  Else Begin
   CommandTail:='';
   For Index:=2 to WordCount-1 Do Begin
    If CommandTail<>''Then CommandTail:=CommandTail+' ';
    CommandTail:=CommandTail+QuoteArgument(WordList[Index+1]);
   End;
   For LoopIndex:=1 to LoopCount Do ProcessLine(CommandTail);
   LastStatus:=0;
  End;
 End Else If CurrCommand='true'Then LastStatus:=0 Else
 If CurrCommand='false'Then LastStatus:=1 Else
 If CurrCommand='pwd'Then Begin GetDir(0,CommandTail); WriteLn(CommandTail); LastStatus:=0; End
 Else RunExternal;
 If ExitOnError and(LastStatus<>0)Then Terminated:=True;
End;

Procedure ProcessLine(Const Line:String);
Var
 Index,StartPosition:Integer;
 Quote:Char;
 Segment:String;
Begin
 StartPosition:=1;
 Quote:=#0;
 Index:=1;
 While Index<=Length(Line)+1 Do Begin
  If Index<=Length(Line)Then Begin
   If(Line[Index]=#92)and(Index<Length(Line))Then Inc(Index)
   Else If Quote<>#0 Then Begin
    If Line[Index]=Quote Then Quote:=#0;
   End Else If(Line[Index]=#39)or(Line[Index]=#34)Then Quote:=Line[Index];
  End;
  If(Index>Length(Line))or((Line[Index]=';')and(Quote=#0))Then Begin
   Segment:=TrimText(Copy(Line,StartPosition,Index-StartPosition));
   If Segment<>''Then ExecuteSingle(Segment);
  If Terminated Then Exit;
   StartPosition:=Index+1;
  End;
  Inc(Index);
 End;
End;

Procedure ProcessTextFile(Const FileName:String);
Var
 ScriptFile:Text;
 ScriptData:PScriptLines;
 ScriptLine:String;
 FrameIndex,LineIndex:Integer;
Begin
 If ScriptDepth>=MaxSourceDepth Then Begin
  WriteLn('source: imbrication maximale atteinte');
  LastStatus:=1;
  Exit;
 End;
 Assign(ScriptFile,FileName);
 {$I-}Reset(ScriptFile);{$I+}
 If IOResult<>0 Then Begin
  WriteLn('csh: impossible de lire ',FileName);
  LastStatus:=1;
  If ExitOnError Then Terminated:=True;
  Exit;
 End;
 New(ScriptData);
 ScriptDepth:=ScriptDepth+1;
 FrameIndex:=ScriptDepth;
 ScriptFrames[FrameIndex].Lines:=ScriptData;
 ScriptFrames[FrameIndex].LineCount:=0;
 ScriptFrames[FrameIndex].Position:=0;
 While Not EOF(ScriptFile)Do Begin
  If ScriptFrames[FrameIndex].LineCount>=MaxScriptLines Then Begin
   WriteLn('csh: script trop long (limite ',MaxScriptLines,' lignes)');
   LastStatus:=1;
   Break;
  End;
  Inc(ScriptFrames[FrameIndex].LineCount);
  ReadLn(ScriptFile,ScriptData^[ScriptFrames[FrameIndex].LineCount]);
 End;
 Close(ScriptFile);
 LineIndex:=1;
 While(LineIndex<=ScriptFrames[FrameIndex].LineCount)and Not Terminated Do Begin
  ScriptFrames[FrameIndex].Position:=LineIndex;
  ScriptLine:=ScriptData^[LineIndex];
  If InteractiveMode Then ShowPrompt;
  If VerboseInput Then WriteLn(ScriptLine);
  AddHistory(ScriptLine);
  ProcessLine(ScriptLine);
  If ScriptFrames[FrameIndex].Position<LineIndex Then
   Inc(LineIndex)
  Else LineIndex:=ScriptFrames[FrameIndex].Position+1;
 End;
 Dispose(ScriptData);
 ScriptDepth:=ScriptDepth-1;
End;

Procedure OldProcessTextFileUnused;
Var
 ScriptFile:Text;
 ScriptLine:String;
Begin
 While Not EOF(ScriptFile)and Not Terminated Do Begin
  ReadLn(ScriptFile,ScriptLine);
  If VerboseInput Then WriteLn(ScriptLine);
  AddHistory(ScriptLine);
  ProcessLine(ScriptLine);
 End;
End;

Procedure RunInput(Var Source:Text; IsInteractive:Boolean);
Var
 InputLine:String;
  LinesRead:Integer;
Begin
 LinesRead:=0;
 Repeat
  If IsInteractive Then ShowPrompt;
  If EOF(Source)Then Break;
  ReadLn(Source,InputLine);
  Inc(LinesRead);
  If VerboseInput Then WriteLn(InputLine);
  AddHistory(InputLine);
  ProcessLine(InputLine);
 Until Terminated or(SingleLine and(LinesRead>=1));
End;

Procedure RunStartupFile;
Var
 HomeDirectory,ConfigName:String;
 ConfigFile:Text;
Begin
 If IgnoreStartup or Not InteractiveMode Then Exit;
 HomeDirectory:=GetEnv('HOME');
 If HomeDirectory=''Then HomeDirectory:=GetEnv('USERPROFILE');
 If HomeDirectory=''Then Exit;
 If(HomeDirectory[Length(HomeDirectory)]='\')or
   (HomeDirectory[Length(HomeDirectory)]='/')Then
   ConfigName:=HomeDirectory+'.cshrc'
 Else If Pos('/',HomeDirectory)>0Then ConfigName:=HomeDirectory+'/.cshrc'
 Else ConfigName:=HomeDirectory+'\.cshrc';
 Assign(ConfigFile,ConfigName);
 {$I-}Reset(ConfigFile);{$I+}
 If IOResult=0 Then Begin
  Close(ConfigFile);
  ProcessTextFile(ConfigName);
 End;
End;

Procedure UnknownCommand;Begin
 WriteLn('Commande ou nom de fichier non reconnu');;
 WriteLn;
End;

BEGIN
 FillChar(History,SizeOf(History),0);
 FillChar(StackDirectory,SizeOf(StackDirectory),0);
 FillChar(Variables,SizeOf(Variables),0);
 FillChar(Aliases,SizeOf(Aliases),0);
 FillChar(IfFrames,SizeOf(IfFrames),0);
 NumberHistory:=0; NumberDirectory:=0; VariableCount:=0; AliasCount:=0;
 IfDepth:=0; ScriptDepth:=0; LoopDepth:=0;
 Terminated:=False; LastStatus:=0;
 BatchMode:=False; ExecuteString:=False; ExitOnError:=False;
 IgnoreStartup:=False; InteractiveMode:=False; SyntaxOnly:=False;
 ReadStandardInput:=False; SingleLine:=False; VerboseInput:=False;
 VerboseExpand:=False; VerboseBeforeConfig:=False; QuietMode:=False;
 ScriptName:=''; ShellCommand:='';
 ArgumentIndex:=1;
 While ArgumentIndex<=ParamCount Do Begin
  Argument:=ParamStr(ArgumentIndex);
  If(Argument='--help')or(Argument='-h')or(Argument='/?')Then Begin
   HomeMessage;
   WriteLn('CSH - Cette commande permet de lancer un C Shell.'); 
   WriteLn;
   WriteLn('Syntaxe : csh [-b] [-c commande] [-e] [-f] [-i] [-n] [-s] [-t] [-v] [-V] [-x] [-X] [script]');
   WriteLn;
   WriteLn(' -c commande  Executer une commande puis quitter');
   WriteLn(' -e           Quitter apres une commande en erreur');
   WriteLn(' -f           Ignorer ~/.cshrc');
   WriteLn(' -i           Forcer le mode interactif');
   WriteLn(' -n           Analyser sans executer');
   WriteLn(' -s, -t       Lire stdin; -t ne lit qu''une ligne');
   WriteLn(' -v, -x       Afficher les lignes ou commandes developpees');
   WriteLn('Builtins: set, setenv, alias, cd, source, history, repeat, if/else/endif.');
   Halt(0);
  End Else If(Argument='--version')or(Argument='-V')Then Begin
   WriteLn('csh (LINUX-0) 1.0');
   Halt(0);
  End Else If(Length(Argument)>1)and(Argument[1]='-')Then Begin
   If Argument[2]='-'Then Begin WriteLn('csh: option inconnue: ',Argument); Halt(2); End;
   For I:=2 to Length(Argument)Do Begin
    If Argument[I]='b'Then BatchMode:=True Else
    If Argument[I]='e'Then ExitOnError:=True Else
    If Argument[I]='f'Then IgnoreStartup:=True Else
    If Argument[I]='i'Then InteractiveMode:=True Else
    If Argument[I]='n'Then SyntaxOnly:=True Else
    If Argument[I]='s'Then ReadStandardInput:=True Else
    If Argument[I]='t'Then Begin ReadStandardInput:=True; SingleLine:=True; End Else
    If Argument[I]='v'Then VerboseInput:=True Else
    If Argument[I]='V'Then Begin VerboseInput:=True; VerboseBeforeConfig:=True; End Else
    If Argument[I]='x'Then VerboseExpand:=True Else
    If Argument[I]='X'Then Begin VerboseExpand:=True; VerboseBeforeConfig:=True; End Else
    If Argument[I]='c'Then Begin
     Inc(ArgumentIndex);
     If ArgumentIndex>ParamCount Then Begin WriteLn('csh: -c attend une commande'); Halt(2); End;
     ShellCommand:=ParamStr(ArgumentIndex);
     ExecuteString:=True;
     Break;
    End Else Begin WriteLn('csh: option inconnue: -',Argument[I]); Halt(2); End;
   End;
   If ExecuteString Then Break;
  End Else If ReadStandardInput Then Begin
   ScriptName:=Argument;
  End Else If ScriptName=''Then ScriptName:=Argument
  Else Begin WriteLn('csh: un seul script est accepte'); Halt(2); End;
  Inc(ArgumentIndex);
 End;
 If ReadStandardInput Then ScriptName:='';
 If Not ExecuteString and(ScriptName='')and Not ReadStandardInput Then
  InteractiveMode:=True;
 RunStartupFile;
 If ExecuteString Then Begin
  If VerboseInput Then WriteLn(ShellCommand);
  ProcessLine(ShellCommand);
 End Else If ScriptName<>''Then ProcessTextFile(ScriptName)
 Else If ReadStandardInput or SingleLine Then RunInput(Input,InteractiveMode)
 Else RunInput(Input,True);
 If InteractiveMode and Not Terminated and(ExecuteString or(ScriptName<>''))Then
  RunInput(Input,True);
END.
