{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2025
  @website(https://www.gladir.com/linux-0)
  @abstract(Target: Free Pascal 3.2, Turbo Pascal 7)
}

Program SED(Input,Output);

Uses DOS
{$IFDEF UNIX}
  ,BaseUnix
{$ENDIF}
  ;

Const
  MaxCommands=32;
  MaxFiles=32;

Type
  TCommand = Record
    Cmd:Char;
    Pattern:String;
    Replacement:String;
    Global:Boolean;
    Regex:Boolean;
  End;
  TCommandArray=Array[1..MaxCommands]of TCommand;
  TFileArray=Array[1..MaxFiles]of String;

Var
  Commands:TCommandArray;
  FileNames:TFileArray;
  FileView,TempView:Text;
  Line,Param,ScriptItem,InPlaceSuffix:String;
  I,J,ScriptCount,FileCount,LineLength,Err:Integer;
  SuppressDefault,InPlace,Unbuffered,FollowSymlinks,EndOptions:Boolean;
  RegexMode:Boolean;
  TmpLanguage:String;

Function StrToUpper(S:String):String;
Var
  I:Integer;
Begin
  For I:=1 to Length(S)do
    If S[I]in['a'..'z']Then S[I]:=Chr(Ord(S[I])-32);
  StrToUpper:=S;
End;

Function ParseCommand(Const CmdStr:String; Var Parsed:TCommand):Boolean;
Var
  I,Start:Integer;
  Delimiter:Char;
Begin
  ParseCommand:=False;
  Parsed.Regex:=RegexMode;
  If(CmdStr='d')or(CmdStr='p')or(CmdStr='l')Then Begin
    Parsed.Cmd:=CmdStr[1];
    ParseCommand:=True;
    Exit;
  End;
  If Length(CmdStr)<4 Then Exit;
  If CmdStr[1]<>'s' Then Exit;
  Delimiter:=CmdStr[2];
  If Delimiter='\' Then Exit;
  Start:=3;
  I:=Start;
  While(I<=Length(CmdStr))and(CmdStr[I]<>Delimiter)do Inc(I);
  If I>Length(CmdStr) Then Exit;
  Parsed.Pattern:=Copy(CmdStr,Start,I-Start);
  If Parsed.Pattern='' Then Exit;
  Start:=I+1;
  I:=Start;
  While(I<=Length(CmdStr))and(CmdStr[I]<>Delimiter)do Inc(I);
  Parsed.Replacement:=Copy(CmdStr,Start,I-Start);
  Parsed.Global:=False;
  If I<Length(CmdStr) Then Begin
    If Copy(CmdStr,I+1,Length(CmdStr))<>'g' Then Exit;
    Parsed.Global:=True;
  End;
  Parsed.Cmd:='s';
  ParseCommand:=True;
End;

Procedure AddScript(Const ScriptText:String);
Var
  I:Integer;
  Start:Integer;
  Item:String;
  Parsed:TCommand;
Begin
  Start:=1;
  For I:=1 to Length(ScriptText)+1 Do Begin
    If(I>Length(ScriptText))or(ScriptText[I]=';')or
      (ScriptText[I]=#10)or(ScriptText[I]=#13)Then Begin
      Item:=Copy(ScriptText,Start,I-Start);
      If Item<>''Then Begin
        If ScriptCount>=MaxCommands Then Begin
          WriteLn('Erreur : trop de commandes sed');
          Halt(2);
        End;
        If Not ParseCommand(Item,Parsed) Then Begin
          WriteLn('Erreur : commande sed invalide : ',Item);
          Halt(2);
        End;
        Inc(ScriptCount);
        Commands[ScriptCount]:=Parsed;
      End;
      Start:=I+1;
    End;
  End;
End;

Procedure AddScriptFile(Const FileName:String);
Var
  ScriptFile:Text;
  ScriptLine:String;
Begin
  {$I-}Assign(ScriptFile,FileName);
  Reset(ScriptFile);{$I+}
  If IOResult<>0 Then Begin
    WriteLn('Erreur : impossible de lire le script ',FileName);
    Halt(2);
  End;
  While Not EOF(ScriptFile) Do Begin
    ReadLn(ScriptFile,ScriptLine);
    AddScript(ScriptLine);
  End;
  Close(ScriptFile);
End;

Function MatchClass(Const Pattern:String; ClassStart,ClassEnd:Integer;
                    Value:Char):Boolean;
Var
  I:Integer;
  Negated,Matched:Boolean;
Begin
  Negated:=Pattern[ClassStart+1]='^';
  Matched:=False;
  I:=ClassStart+1;
  If Negated Then Inc(I);
  While I<ClassEnd Do Begin
    If(I+2<ClassEnd)and(Pattern[I+1]='-')Then Begin
      If(Value>=Pattern[I])and(Value<=Pattern[I+2])Then Matched:=True;
      Inc(I,3);
    End
     Else Begin
      If Value=Pattern[I]Then Matched:=True;
      Inc(I);
    End;
  End;
  MatchClass:=Matched Xor Negated;
End;

Function RegexAtomMatches(Const Text,Pattern:String; AtomStart,TextPos:Integer;
                          Var AtomEnd:Integer):Boolean;
Var
  I:Integer;
Begin
  RegexAtomMatches:=False;
  AtomEnd:=AtomStart;
  If TextPos>Length(Text)Then Exit;
  If Pattern[AtomStart]='['Then Begin
    I:=AtomStart+1;
    While(I<=Length(Pattern))and(Pattern[I]<>']')do Inc(I);
    If I>Length(Pattern)Then Begin
      RegexAtomMatches:=Text[TextPos]='[';
      Exit;
    End;
    AtomEnd:=I;
    RegexAtomMatches:=MatchClass(Pattern,AtomStart,I,Text[TextPos]);
  End
   Else If Pattern[AtomStart]='\'Then Begin
    If AtomStart<Length(Pattern)Then Begin
      AtomEnd:=AtomStart+1;
      RegexAtomMatches:=Text[TextPos]=Pattern[AtomStart+1];
    End
     Else RegexAtomMatches:=Text[TextPos]='\';
  End
   Else If Pattern[AtomStart]='.'Then RegexAtomMatches:=True
   Else RegexAtomMatches:=Text[TextPos]=Pattern[AtomStart];
End;

Function RegexMatchFrom(Const Text,Pattern:String; PatternPos,TextPos:Integer;
                        Var MatchEnd:Integer):Boolean;
Var
  AtomEnd,QuantifierPos,NextPattern,Count,MaxCount,MinCount:Integer;
  AtomEndAtPos,TryEnd:Integer;
  HasQuantifier,AtEnd:Boolean;
Begin
  If PatternPos>Length(Pattern)Then Begin
    MatchEnd:=TextPos-1;
    RegexMatchFrom:=True;
    Exit;
  End;
  If(Pattern[PatternPos]='$')and(PatternPos=Length(Pattern))Then Begin
    AtEnd:=TextPos>Length(Text);
    If AtEnd Then MatchEnd:=TextPos-1;
    RegexMatchFrom:=AtEnd;
    Exit;
  End;

  AtomEnd:=PatternPos;
  If Pattern[PatternPos]='['Then Begin
    AtomEnd:=PatternPos+1;
    While(AtomEnd<=Length(Pattern))and(Pattern[AtomEnd]<>']')do Inc(AtomEnd);
    If AtomEnd>Length(Pattern)Then AtomEnd:=PatternPos;
  End
   Else If(Pattern[PatternPos]='\')and(PatternPos<Length(Pattern))Then
    AtomEnd:=PatternPos+1;
  QuantifierPos:=AtomEnd+1;
  HasQuantifier:=False;
  MinCount:=1;
  MaxCount:=1;
  If(QuantifierPos<=Length(Pattern))and
    (Pattern[QuantifierPos]='*')Then Begin
    HasQuantifier:=True;
    MinCount:=0;
  End
   Else If RegexMode And(QuantifierPos<=Length(Pattern))and
     (Pattern[QuantifierPos]='+')Then Begin
    HasQuantifier:=True;
    MinCount:=1;
  End
   Else If RegexMode And(QuantifierPos<=Length(Pattern))and
     (Pattern[QuantifierPos]='?')Then Begin
    HasQuantifier:=True;
    MinCount:=0;
  End;
  NextPattern:=QuantifierPos;
  If HasQuantifier Then Inc(NextPattern);

  MaxCount:=0;
  While RegexAtomMatches(Text,Pattern,PatternPos,TextPos+MaxCount,
                         AtomEndAtPos)Do Inc(MaxCount);
  If Not HasQuantifier Then Begin
    If MaxCount>0 Then MaxCount:=1;
  End;
  If(RegexMode And(QuantifierPos<=Length(Pattern))and
    (Pattern[QuantifierPos]='?'))Then MaxCount:=1;
  Count:=MaxCount;
  While Count>=MinCount Do Begin
    If RegexMatchFrom(Text,Pattern,NextPattern,TextPos+Count,TryEnd)Then Begin
      MatchEnd:=TryEnd;
      RegexMatchFrom:=True;
      Exit;
    End;
    Dec(Count);
  End;
  RegexMatchFrom:=False;
End;

Function FindRegex(Const Text,Pattern:String; StartAt:Integer;
                   Var MatchStart,MatchEnd:Integer):Boolean;
Var
  Candidate,FoundEnd:Integer;
  Anchored:Boolean;
Begin
  Anchored:=(Length(Pattern)>0)and(Pattern[1]='^');
  Candidate:=StartAt;
  FindRegex:=False;
  While Candidate<=Length(Text)+1 Do Begin
    If(Anchored and(Candidate>1))Then Exit;
    If Anchored Then Begin
      If RegexMatchFrom(Text,Pattern,2,Candidate,FoundEnd)Then Begin
        MatchStart:=Candidate;
        MatchEnd:=FoundEnd;
        FindRegex:=True;
      End;
      Exit;
    End;
    If RegexMatchFrom(Text,Pattern,1,Candidate,FoundEnd)Then Begin
      MatchStart:=Candidate;
      MatchEnd:=FoundEnd;
      FindRegex:=True;
      Exit;
    End;
    Inc(Candidate);
  End;
End;

Function ExpandReplacement(Const Replacement,Source:String;
                           MatchStart,MatchEnd:Integer):String;
Var
  I:Integer;
  Expanded:String;
Begin
  Expanded:='';
  For I:=1 to Length(Replacement)Do Begin
    If(Replacement[I]='&')Then
      Expanded:=Expanded+Copy(Source,MatchStart,MatchEnd-MatchStart+1)
    Else Expanded:=Expanded+Replacement[I];
  End;
  ExpandReplacement:=Expanded;
End;

Function ApplyRegexSubstitution(Const Source,Pattern,Replacement:String;
                                Global:Boolean):String;
Var
  ResultLine,Expanded:String;
  P,MatchEnd,SearchFrom:Integer;
Begin
  ResultLine:=Source;
  SearchFrom:=1;
  Repeat
    If Not FindRegex(ResultLine,Pattern,SearchFrom,P,MatchEnd)Then Break;
    Expanded:=ExpandReplacement(Replacement,ResultLine,P,MatchEnd);
    ResultLine:=Copy(ResultLine,1,P-1)+Expanded+
                Copy(ResultLine,MatchEnd+1,Length(ResultLine));
    If Not Global Then Break;
    If MatchEnd<P Then SearchFrom:=P+Length(Expanded)+1
                   Else SearchFrom:=P+Length(Expanded);
  Until SearchFrom>Length(ResultLine)+1;
  ApplyRegexSubstitution:=ResultLine;
End;

Function ApplySubstitution(Const Source,Pattern,Replacement:String;
                           Global,UseRegex:Boolean):String;
Var
  ResultLine:String;
  P,SearchFrom:Integer;
Begin
  If UseRegex Then Begin
    ApplySubstitution:=ApplyRegexSubstitution(Source,Pattern,Replacement,Global);
    Exit;
  End;
  ResultLine:=Source;
  SearchFrom:=1;
  Repeat
    P:=Pos(Pattern,Copy(ResultLine,SearchFrom,Length(ResultLine)));
    If P>0 Then Begin
      P:=P+SearchFrom-1;
      ResultLine:=Copy(ResultLine,1,P-1)+Replacement+
                  Copy(ResultLine,P+Length(Pattern),Length(ResultLine));
      If Not Global Then Break;
      SearchFrom:=P+Length(Replacement);
    End;
  Until P=0;
  ApplySubstitution:=ResultLine;
End;

Procedure PrintEscaped(Const S:String; Var Destination:Text);
Var
  I,Column:Integer;
Begin
  Column:=0;
  For I:=1 to Length(S)Do Begin
    If(LineLength>0)and(Column>=LineLength)Then Begin
      Write(Destination,'\');
      WriteLn(Destination);
      Column:=0;
    End;
    Case S[I]of
      '\':Write(Destination,'\\');
      #9:Write(Destination,'\t');
      #13:Write(Destination,'\r');
      Else Write(Destination,S[I]);
    End;
    Inc(Column);
  End;
  WriteLn(Destination,'$');
End;

Procedure ProcessInput(Var Source,Destination:Text);
Var
  CommandIndex:Integer;
  Deleted:Boolean;
Begin
  While Not EOF(Source) Do Begin
    ReadLn(Source,Line);
    Deleted:=False;
    For CommandIndex:=1 to ScriptCount Do Begin
      If Not Deleted Then
        Case Commands[CommandIndex].Cmd Of
          's':Line:=ApplySubstitution(Line,Commands[CommandIndex].Pattern,
                    Commands[CommandIndex].Replacement,
                    Commands[CommandIndex].Global,
                    Commands[CommandIndex].Regex);
          'd':Deleted:=True;
          'p':WriteLn(Destination,Line);
          'l':PrintEscaped(Line,Destination);
        End;
    End;
    If Not SuppressDefault And Not Deleted Then WriteLn(Destination,Line);
    If Unbuffered Then Flush(Destination);
  End;
End;

Function MakeTempName(Const SourceName:String; Serial:Integer):String;
Var
  Dir:DirStr;
  Name:NameStr;
  Ext:ExtStr;
  Num:String;
  Candidate:String;
  Search:SearchRec;
Begin
  FSplit(FExpand(SourceName),Dir,Name,Ext);
  MakeTempName:='';
  While Serial<10000 Do Begin
    Str(Serial,Num);
    While Length(Num)<4 Do Num:='0'+Num;
    Candidate:=Dir+'SED'+Num+'.TMP';
    FindFirst(Candidate,AnyFile,Search);
    If DosError<>0 Then Begin
      MakeTempName:=Candidate;
      Exit;
    End;
    {$IFDEF FPC}FindClose(Search);{$ENDIF}
    Inc(Serial);
  End;
End;

Function RenamePath(Const OldName,NewName:String):Boolean;
Var
  F:File;
Begin
  Assign(F,OldName);
  {$I-}Rename(F,NewName);{$I+}
  RenamePath:=IOResult=0;
End;

Function ResolveLinkPath(Const SourceName:String):String;
{$IFDEF UNIX}
Var
  Current,Target:String;
  Buffer:Array[0..255]of Char;
  Dir:DirStr;
  NamePart:NameStr;
  Ext:ExtStr;
  BytesRead,Depth,I:LongInt;
Begin
  Current:=FExpand(SourceName);
  Depth:=0;
  Repeat
    BytesRead:=fpReadLink(PChar(Current),@Buffer[0],SizeOf(Buffer));
    If BytesRead<=0 Then Break;
    Target:='';
    For I:=0 to BytesRead-1 Do Target:=Target+Buffer[I];
    If(Target<>'')and(Target[1]<>'/')Then Begin
      FSplit(Current,Dir,NamePart,Ext);
      Target:=Dir+Target;
    End;
    Current:=FExpand(Target);
    Inc(Depth);
  Until Depth>=16;
  ResolveLinkPath:=Current;
End;
{$ELSE}
Begin
  ResolveLinkPath:=SourceName;
End;
{$ENDIF}

Procedure ErasePath(Const FileName:String);
Var
  F:File;
Begin
  Assign(F,FileName);
  {$I-}Erase(F);{$I+}
  If IOResult<>0 Then Exit;
End;

Procedure ProcessFile(Const FileName:String);
Var
  TempName,BackupName,ActiveName:String;
  BackupIsTemporary:Boolean;
Begin
  ActiveName:=FileName;
  If FollowSymlinks Then ActiveName:=ResolveLinkPath(FileName);
  {$I-}Assign(FileView,ActiveName);
  Reset(FileView);{$I+}
  If IOResult<>0 Then Begin
    WriteLn('Erreur : impossible de lire ',FileName);
    Halt(1);
  End;
  If Not InPlace Then Begin
    ProcessInput(FileView,Output);
    Close(FileView);
    Exit;
  End;

  TempName:=MakeTempName(ActiveName,1);
  If TempName='' Then Begin
    Close(FileView);
    WriteLn('Erreur : impossible de creer un fichier temporaire');
    Halt(1);
  End;
  {$I-}Assign(TempView,TempName);
  Rewrite(TempView);{$I+}
  If IOResult<>0 Then Begin
    Close(FileView);
    WriteLn('Erreur : impossible de creer ',TempName);
    Halt(1);
  End;
  ProcessInput(FileView,TempView);
  Close(FileView);
  Close(TempView);

  BackupIsTemporary:=InPlaceSuffix='';
  If BackupIsTemporary Then BackupName:=MakeTempName(ActiveName,2)
                       Else BackupName:=ActiveName+InPlaceSuffix;
  If(BackupName='')or(Not RenamePath(ActiveName,BackupName))Then Begin
    ErasePath(TempName);
    WriteLn('Erreur : impossible de sauvegarder ',FileName);
    Halt(1);
  End;
  If Not RenamePath(TempName,ActiveName) Then Begin
    RenamePath(BackupName,ActiveName);
    ErasePath(TempName);
    WriteLn('Erreur : impossible de remplacer ',FileName);
    Halt(1);
  End;
  If BackupIsTemporary Then ErasePath(BackupName);
End;

Procedure ReadOptionArgument(Const OptionName:String; Var Index:Integer;
                             Var Value:String);
Begin
  Inc(Index);
  If Index>ParamCount Then Begin
    WriteLn('Erreur : argument manquant pour ',OptionName);
    Halt(2);
  End;
  Value:=ParamStr(Index);
End;

BEGIN
  If(ParamCount=0)or(ParamStr(1)='/?')or(ParamStr(1)='--help')or
    (ParamStr(1)='-h')or(ParamStr(1)='/h')or(ParamStr(1)='/H')Then Begin
    TmpLanguage:=GetEnv('LANGUAGE');
    If StrToUpper(Copy(TmpLanguage,1,2))='EN' Then Begin
      WriteLn('SED : Stream editor for basic scripts.');
      WriteLn('Syntax: sed [OPTION]... SCRIPT [FILE]...');
      WriteLn(' -e SCRIPT, --expression=SCRIPT  add a script');
      WriteLn(' -f FILE, --file=FILE            add commands from a script file');
      WriteLn(' -i[SUFFIX], --in-place[=SUFFIX] edit files in place');
      WriteLn(' -n, --quiet, --silent           suppress automatic output');
      WriteLn(' -l N, --line-length=N           set l command line width');
      WriteLn(' -r, --regexp-extended           enable extended regular expressions');
      WriteLn(' -s, --separate                  process files separately');
      WriteLn(' -u, --unbuffered                flush output after each line');
      WriteLn(' --follow-symlinks, --POSIX, --version');
      WriteLn('Commands currently supported: s/old/new/[g], d, p, l');
    End
     Else Begin
      WriteLn('SED : Editeur de flux pour les scripts de base.');
      WriteLn('Syntaxe : sed [OPTION]... SCRIPT [FICHIER]...');
      WriteLn(' -e SCRIPT, --expression=SCRIPT  ajouter un script');
      WriteLn(' -f FICHIER, --file=FICHIER      ajouter un fichier de commandes');
      WriteLn(' -i[SUFFIXE], --in-place[=SUFFIXE] modifier les fichiers sur place');
      WriteLn(' -n, --quiet, --silent           supprimer l''affichage automatique');
      WriteLn(' -l N, --line-length=N           definir la largeur de la commande l');
      WriteLn(' -r, --regexp-extended           activer les expressions regulieres etendues');
      WriteLn(' -s, --separate                  traiter les fichiers separement');
      WriteLn(' -u, --unbuffered                vider la sortie apres chaque ligne');
      WriteLn(' --follow-symlinks, --POSIX, --version');
      WriteLn('Commandes gerees : s/ancien/nouveau/[g], d, p, l');
    End;
  End
   Else If ParamStr(1)='--version' Then
    WriteLn('SED 1.0 - Clone Pascal de sed')
   Else Begin
    ScriptCount:=0;
    FileCount:=0;
    SuppressDefault:=False;
    InPlace:=False;
    InPlaceSuffix:='';
    Unbuffered:=False;
    FollowSymlinks:=False;
    RegexMode:=False;
    EndOptions:=False;
    LineLength:=70;
    I:=1;
    While I<=ParamCount Do Begin
      Param:=ParamStr(I);
      If Not EndOptions And(Param='--')Then EndOptions:=True Else
      If Not EndOptions And((Param='-n')or(Param='--quiet')or
        (Param='--silent'))Then SuppressDefault:=True Else
      If Not EndOptions And((Param='-u')or(Param='--unbuffered'))Then
        Unbuffered:=True Else
      If Not EndOptions And((Param='-s')or(Param='--separate')or
        (Param='--POSIX')or(Param='--posix'))Then Begin
      End Else
      If Not EndOptions And(Param='--follow-symlinks')Then
        FollowSymlinks:=True Else
      If Not EndOptions And((Param='-r')or(Param='--regexp-extended'))Then Begin
        RegexMode:=True;
        For J:=1 to ScriptCount Do Commands[J].Regex:=True;
      End Else
      If Not EndOptions And((Param='-i')or(Param='--in-place'))Then
        InPlace:=True Else
      If Not EndOptions And(Copy(Param,1,11)='--in-place=')Then Begin
        InPlace:=True;
        InPlaceSuffix:=Copy(Param,12,244);
      End Else
      If Not EndOptions And(Copy(Param,1,2)='-i')and(Length(Param)>2)Then Begin
        InPlace:=True;
        InPlaceSuffix:=Copy(Param,3,253);
      End Else
      If Not EndOptions And(Param='-e')Then Begin
        ReadOptionArgument('-e',I,ScriptItem);
        AddScript(ScriptItem);
      End Else
      If Not EndOptions And(Copy(Param,1,13)='--expression=')Then
        AddScript(Copy(Param,14,242)) Else
      If Not EndOptions And(Param='-f')Then Begin
        ReadOptionArgument('-f',I,ScriptItem);
        AddScriptFile(ScriptItem);
      End Else
      If Not EndOptions And(Copy(Param,1,7)='--file=')Then
        AddScriptFile(Copy(Param,8,248)) Else
      If Not EndOptions And((Param='-l')or(Param='--line-length'))Then Begin
        ReadOptionArgument(Param,I,ScriptItem);
        Val(ScriptItem,LineLength,Err);
        If(Err<>0)or(LineLength<1)Then Begin
          WriteLn('Erreur : longueur de ligne invalide');
          Halt(2);
        End;
      End Else
      If Not EndOptions And(Copy(Param,1,14)='--line-length=')Then Begin
        ScriptItem:=Copy(Param,15,241);
        Val(ScriptItem,LineLength,Err);
        If(Err<>0)or(LineLength<1)Then Begin
          WriteLn('Erreur : longueur de ligne invalide');
          Halt(2);
        End;
      End Else
      If Not EndOptions And(Length(Param)>0)and(Param[1]='-')Then Begin
        WriteLn('Erreur : option sed inconnue : ',Param);
        Halt(2);
      End Else If ScriptCount=0 Then AddScript(Param) Else Begin
        If FileCount>=MaxFiles Then Begin
          WriteLn('Erreur : trop de fichiers');
          Halt(2);
        End;
        Inc(FileCount);
        FileNames[FileCount]:=Param;
      End;
      Inc(I);
    End;

    If ScriptCount=0 Then Begin
      WriteLn('Erreur : script sed manquant');
      Halt(2);
    End;
    If InPlace And(FileCount=0)Then Begin
      WriteLn('Erreur : -i exige au moins un fichier');
      Halt(2);
    End;
    If FileCount=0 Then ProcessInput(Input,Output)
     Else For I:=1 to FileCount Do ProcessFile(FileNames[I]);
   End;
END.