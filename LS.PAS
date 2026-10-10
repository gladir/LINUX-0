{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2026
  @website(https://www.gladir.com/linux-0)
  @abstract(Target: Turbo Pascal 7, Free Pascal 3.2)
}

Program LS;

Uses DOS;

Const
  MaxEntries=240;
  MaxOperands=32;
  MaxNameLength=127;
  MaxPathLength=255;
  MaxIgnorePatterns=16;
  DefaultWidth=80;

Type
  TName=String[MaxNameLength];
  TPath=String[MaxPathLength];
  TEntryPointer=^TEntry;
  TEntry=Record
    Name:TName;
    Attributes:Word;
    SearchTime:LongInt;
    Size:LongInt;
    Ordinal:LongInt;
    Next:TEntryPointer;
  End;
  TOperandArray=Array[1..MaxOperands]Of TPath;
  TIgnoreArray=Array[1..MaxIgnorePatterns]Of TName;

Var
  Operands:TOperandArray;
  IgnorePatterns:TIgnoreArray;
  OperandCount,IgnoreCount,WidthColumns,TabSize,MainIndex:Integer;
  FormatMode,SortMode:Integer;
  ShowAll,AlmostAll,IgnoreBackups,DirectoryAsFile:Boolean;
  Classify,FileTypeOnly,LongFormat,VerboseFormat:Boolean;
  ShowInode,ShowSize,SizeInKilobytes,NumericIds:Boolean;
  ShowGroup,NoGroup,QuoteNames,EscapeNames,HideControls:Boolean;
  ReverseSort,Recursive,NoSort,FullTime:Boolean;
  QuietErrors,English,ErrorFound,PermitDirectorySuffix:Boolean;
  EntrySerial:LongInt;

Function UpperCharacter(Value:Char):Char;
Begin
  If(Value>='a')and(Value<='z')Then UpperCharacter:=Chr(Ord(Value)-32)
  Else UpperCharacter:=Value;
End;

Function UpperText(Const Value:TName):TName;
Var
  Index:Integer;
  ResultText:TName;
Begin
  ResultText:=Value;
  For Index:=1 to Length(ResultText)Do
    ResultText[Index]:=UpperCharacter(ResultText[Index]);
  UpperText:=ResultText;
End;

Function JoinPath(Const DirectoryName:TPath; Const FileName:TName):TPath;
Var
  Separator:Char;
  ResultPath:TPath;
Begin
  If DirectoryName=''Then Begin JoinPath:=FileName;Exit;End;
  If(DirectoryName[Length(DirectoryName)]='/')or
    (DirectoryName[Length(DirectoryName)]=#92)Then Separator:=#0
  Else If Pos('/',DirectoryName)>0 Then Separator:='/'
  Else Separator:=#92;
  ResultPath:=DirectoryName;
  If Separator<>#0 Then ResultPath:=ResultPath+Separator;
  JoinPath:=ResultPath+FileName;
End;

Function EntryIsDirectory(Attributes:Word):Boolean;
Begin
  EntryIsDirectory:=(Attributes and Directory)<>0;
End;

Function IsHiddenName(Const Name:TName; Attributes:Word):Boolean;
Begin
  IsHiddenName:=((Attributes and Hidden)<>0)or
    ((Length(Name)>0)and(Name[1]='.'));
End;

Function IsBackupName(Const Name:TName):Boolean;
Begin
  IsBackupName:=(Length(Name)>0)and(Name[Length(Name)]='~');
End;

Function WildcardMatch(Const Pattern,Value:TName):Boolean;
Var
  PatternPosition,ValuePosition,StarPosition,RetryPosition:Integer;
  PatternCharacter,ValueCharacter:Char;
Begin
  PatternPosition:=1;ValuePosition:=1;StarPosition:=0;RetryPosition:=0;
  While ValuePosition<=Length(Value)Do Begin
    If PatternPosition<=Length(Pattern)Then Begin
      PatternCharacter:=UpperCharacter(Pattern[PatternPosition]);
      ValueCharacter:=UpperCharacter(Value[ValuePosition]);
      If(PatternCharacter='?')or(PatternCharacter=ValueCharacter)Then Begin
        Inc(PatternPosition);Inc(ValuePosition);Continue;
      End;
      If PatternCharacter='*'Then Begin
        StarPosition:=PatternPosition;
        Inc(PatternPosition);
        RetryPosition:=ValuePosition;
        Continue;
      End;
    End;
    If StarPosition<>0 Then Begin
      PatternPosition:=StarPosition+1;
      Inc(RetryPosition);
      ValuePosition:=RetryPosition;
    End Else Begin WildcardMatch:=False;Exit;End;
  End;
  While(PatternPosition<=Length(Pattern))and(Pattern[PatternPosition]='*')Do
    Inc(PatternPosition);
  WildcardMatch:=PatternPosition>Length(Pattern);
End;

Function IgnoredName(Const Name:TName):Boolean;
Var
  Index:Integer;
Begin
  IgnoredName:=False;
  For Index:=1 to IgnoreCount Do
    If WildcardMatch(IgnorePatterns[Index],Name)Then Begin
      IgnoredName:=True;
      Exit;
    End;
End;

Function ExtensionOf(Const Name:TName):TName;
Var
  Index,DotPosition:Integer;
Begin
  DotPosition:=0;
  For Index:=1 to Length(Name)Do If Name[Index]='.'Then DotPosition:=Index;
    If DotPosition=0 Then ExtensionOf:=''
  Else ExtensionOf:=UpperText(Copy(Name,DotPosition,MaxNameLength));
End;

Function EntryComesBefore(LeftEntry,RightEntry:TEntryPointer):Boolean;
Var
  LeftKey,RightKey:TName;
  LeftDate,RightDate:LongInt;
  Before:Boolean;
Begin
  Case SortMode Of
    1:Before:=False;
      2:Begin
      LeftDate:=LeftEntry^.SearchTime;
      RightDate:=RightEntry^.SearchTime;
      Before:=LeftDate>RightDate;
    End;
    3:Before:=LeftEntry^.Size>RightEntry^.Size;
    4:Begin
      LeftKey:=ExtensionOf(LeftEntry^.Name);
      RightKey:=ExtensionOf(RightEntry^.Name);
      If LeftKey=RightKey Then Before:=UpperText(LeftEntry^.Name)<UpperText(RightEntry^.Name)
      Else Before:=LeftKey<RightKey;
    End;
  Else Before:=UpperText(LeftEntry^.Name)<UpperText(RightEntry^.Name);
  End;
  If ReverseSort Then Before:=Not Before;
  EntryComesBefore:=Before;
End;

Procedure AddEntry(Var Head,Tail:TEntryPointer; Const Name:TName;
                   Attributes:Word; SearchTime,Size:LongInt;
                   Var Count:Integer);
Var
  NewEntry,PreviousEntry,CurrentEntry:TEntryPointer;
Begin
  If Count>=MaxEntries Then Exit;
  If Not ShowAll and Not AlmostAll and IsHiddenName(Name,Attributes)Then Exit;
  If AlmostAll and((Name='.')or(Name='..'))Then Exit;
  If IgnoreBackups and IsBackupName(Name)Then Exit;
  If IgnoredName(Name)Then Exit;
  New(NewEntry);
  NewEntry^.Name:=Name;
  NewEntry^.Attributes:=Attributes;
  NewEntry^.SearchTime:=SearchTime;
  NewEntry^.Size:=Size;
  Inc(EntrySerial);
  NewEntry^.Ordinal:=EntrySerial;
  NewEntry^.Next:=Nil;
  Inc(Count);
  If NoSort or(SortMode=1)or(Head=Nil)Then Begin
    If Tail=Nil Then Head:=NewEntry Else Tail^.Next:=NewEntry;
    Tail:=NewEntry;
    Exit;
  End;
  PreviousEntry:=Nil;
  CurrentEntry:=Head;
  While(CurrentEntry<>Nil)and Not(EntryComesBefore(NewEntry,CurrentEntry))Do Begin
    PreviousEntry:=CurrentEntry;
    CurrentEntry:=CurrentEntry^.Next;
  End;
  If PreviousEntry=Nil Then Begin
    NewEntry^.Next:=Head;
    Head:=NewEntry;
  End Else Begin
    NewEntry^.Next:=CurrentEntry;
    PreviousEntry^.Next:=NewEntry;
  End;
  If CurrentEntry=Nil Then Tail:=NewEntry;
End;

Procedure FreeEntries(Var Head:TEntryPointer);
Var
  Entry,NextEntry:TEntryPointer;
Begin
  Entry:=Head;
  While Entry<>Nil Do Begin
    NextEntry:=Entry^.Next;
    Dispose(Entry);
    Entry:=NextEntry;
  End;
  Head:=Nil;
End;

Function EntrySuffix(Entry:TEntryPointer):Char;
Begin
  EntrySuffix:=#0;
  If EntryIsDirectory(Entry^.Attributes)Then Begin
    If Classify or FileTypeOnly or(PermitDirectorySuffix)Then EntrySuffix:='/';
  End Else If Classify Then Begin
    If((Pos('.EXE',UpperText(Entry^.Name))>0)or
      (Pos('.COM',UpperText(Entry^.Name))>0)or
      (Pos('.BAT',UpperText(Entry^.Name))>0))Then EntrySuffix:='*';
  End;
End;

Function OctalEscape(Value:Byte):TName;
Var
  ResultText:TName;
Begin
  ResultText:=#92+Chr(Ord('0')+(Value div 64));
  ResultText:=ResultText+Chr(Ord('0')+((Value div 8)mod 8));
  ResultText:=ResultText+Chr(Ord('0')+(Value mod 8));
  OctalEscape:=ResultText;
End;

Function QuotedName(Entry:TEntryPointer):TName;
Var
  Index:Integer;
  Character:Char;
  ResultName:TName;
Begin
  ResultName:='';
  If QuoteNames Then ResultName:=ResultName+#34;
    For Index:=1 to Length(Entry^.Name)Do Begin
    Character:=Entry^.Name[Index];
    If(Character<#32)or(Character=#127)Then Begin
      If HideControls Then ResultName:=ResultName+'?'
      Else If EscapeNames Then ResultName:=ResultName+OctalEscape(Ord(Character))
      Else ResultName:=ResultName+Character;
    End Else If QuoteNames and(Character in[#34,#92])Then
      ResultName:=ResultName+#92+Character
    Else ResultName:=ResultName+Character;
  End;
  If QuoteNames Then ResultName:=ResultName+#34;
  If EntrySuffix(Entry)<>#0 Then ResultName:=ResultName+EntrySuffix(Entry);
  QuotedName:=ResultName;
End;

Procedure WriteLongEntry(Entry:TEntryPointer);
Var
  DateTimeValue:DateTime;
  SizeValue:LongInt;
  AttributeText:String[6];
Begin
  AttributeText:='------';
  If EntryIsDirectory(Entry^.Attributes)Then AttributeText[1]:='d';
  If(Entry^.Attributes and ReadOnly)<>0Then AttributeText[2]:='r';
  If(Entry^.Attributes and Hidden)<>0Then AttributeText[3]:='h';
  If(Entry^.Attributes and SysFile)<>0Then AttributeText[4]:='s';
  If(Entry^.Attributes and Archive)<>0Then AttributeText[5]:='a';
  Write(AttributeText,'  ');
  If ShowInode Then Write(Entry^.Ordinal:8,' ');
  If ShowSize Then Begin
    SizeValue:=(Entry^.Size+511)div 512;
    Write(SizeValue:8,' ');
  End;
  If VerboseFormat Then Write('0 0 ')
  Else If NumericIds Then Write('0 0 ')
  Else If ShowGroup and Not NoGroup Then Write('0 ');
  If SizeInKilobytes Then Write(((Entry^.Size+1023)div 1024):9,'K ')
  Else Write(Entry^.Size:10,' ');
  UnpackTime(Entry^.SearchTime,DateTimeValue);
  Write(DateTimeValue.Year:4,'-',DateTimeValue.Month:2,'-',DateTimeValue.Day:2,' ');
  Write(DateTimeValue.Hour:2,':',DateTimeValue.Min:2);
  If FullTime Then Write(':',DateTimeValue.Sec:2);
  Write(' ');
  WriteLn(QuotedName(Entry));
End;

Procedure WriteEntryName(Entry:TEntryPointer; Width:Integer);
Var
  Name:TName;
  Index:Integer;
Begin
  Name:=QuotedName(Entry);
  If ShowInode Then Write(Entry^.Ordinal:8,' ');
  If ShowSize Then Write(((Entry^.Size+511)div 512):8,' ');
  Write(Name);
  If Width>Length(Name)Then
    For Index:=Length(Name)+1 to Width Do Write(' ');
End;

Function EntryCount(Head:TEntryPointer):Integer;
Var
  Entry:TEntryPointer;
  Count:Integer;
Begin
  Count:=0;
  Entry:=Head;
  While Entry<>Nil Do Begin Inc(Count);Entry:=Entry^.Next;End;
  EntryCount:=Count;
End;

Procedure DisplayEntries(Head:TEntryPointer);
Var
  Entry:TEntryPointer;
  Count,MaxWidth,Columns,Rows,RowIndex,ColumnIndex,CellWidth:Integer;
  Names:Array[1..MaxEntries]Of TEntryPointer;
Begin
  Count:=EntryCount(Head);
  If Count=0 Then Exit;
  If LongFormat or VerboseFormat Then Begin
    Entry:=Head;
    While Entry<>Nil Do Begin WriteLongEntry(Entry);Entry:=Entry^.Next;End;
    Exit;
  End;
  If FormatMode=5 Then Begin
    Entry:=Head;
    While Entry<>Nil Do Begin WriteEntryName(Entry,0);WriteLn;Entry:=Entry^.Next;End;
    Exit;
  End;
  MaxWidth:=1;Entry:=Head;RowIndex:=0;
  While Entry<>Nil Do Begin
    Inc(RowIndex);Names[RowIndex]:=Entry;
    If Length(QuotedName(Entry))>MaxWidth Then MaxWidth:=Length(QuotedName(Entry));
    Entry:=Entry^.Next;
  End;
  If FormatMode=2 Then Begin
    For RowIndex:=1 to Count Do Begin
      If RowIndex>1 Then Write(', ');
      Write(QuotedName(Names[RowIndex]));
    End;
    WriteLn;
    Exit;
  End;
  CellWidth:=MaxWidth+2;
  If TabSize>1 Then CellWidth:=((CellWidth+TabSize-1)div TabSize)*TabSize;
  Columns:=WidthColumns div CellWidth;
  If Columns<1 Then Columns:=1;
  If Columns>Count Then Columns:=Count;
  Rows:=(Count+Columns-1)div Columns;
  If FormatMode=3 Then Begin
    For RowIndex:=0 to Rows-1 Do Begin
      For ColumnIndex:=0 to Columns-1 Do Begin
        If RowIndex*Columns+ColumnIndex<Count Then Begin
          Entry:=Names[RowIndex*Columns+ColumnIndex+1];
          WriteEntryName(Entry,CellWidth);
        End;
      End;
      WriteLn;
    End;
  End Else Begin
    For RowIndex:=0 to Rows-1 Do Begin
      For ColumnIndex:=0 to Columns-1 Do Begin
        If ColumnIndex*Rows+RowIndex<Count Then Begin
          Entry:=Names[ColumnIndex*Rows+RowIndex+1];
          WriteEntryName(Entry,CellWidth);
        End;
      End;
      WriteLn;
    End;
  End;
End;

Procedure GatherPath(Const SearchPath:TPath; Var Head,Tail:TEntryPointer;
                     Var Count:Integer);
Var
  SearchRecord:SearchRec;
  BaseName:TName;
Begin
  FindFirst(SearchPath,AnyFile,SearchRecord);
  While DosError=0 Do Begin
    BaseName:=SearchRecord.Name;
    If(ShowAll or AlmostAll)or((BaseName<>'.')and(BaseName<>'..'))Then
      AddEntry(Head,Tail,BaseName,SearchRecord.Attr,SearchRecord.Time,
           SearchRecord.Size,Count);
    FindNext(SearchRecord);
  End;
  {$IFDEF FPC}FindClose(SearchRecord);{$ENDIF}
End;

Procedure ListDirectory(Const DirectoryName:TPath; Depth:Integer);
Var
  Head,Tail,Entry,NextEntry:TEntryPointer;
  Count:Integer;
  Pattern:TPath;
Begin
  If Depth>32 Then Begin
    If Not QuietErrors Then WriteLn('ls: profondeur recursive maximale atteinte: ',DirectoryName);
    ErrorFound:=True;
    Exit;
  End;
  Head:=Nil;Tail:=Nil;Count:=0;
  Pattern:=JoinPath(DirectoryName,'*.*');
  GatherPath(Pattern,Head,Tail,Count);
  If Depth>0 Then WriteLn(DirectoryName,':');
  DisplayEntries(Head);
  If Recursive Then Begin
    Entry:=Head;
    While Entry<>Nil Do Begin
      NextEntry:=Entry^.Next;
      If EntryIsDirectory(Entry^.Attributes)and(Entry^.Name<>'.')and(Entry^.Name<>'..')Then
        ListDirectory(JoinPath(DirectoryName,Entry^.Name),Depth+1);
      Entry:=NextEntry;
    End;
  End;
  FreeEntries(Head);
End;

Procedure ListOperand(Const Operand:TPath);
Var
  SearchRecord:SearchRec;
  Head,Tail:TEntryPointer;
  Count:Integer;
  Found,IsDirectoryOperand:Boolean;
Begin
  Head:=Nil;Tail:=Nil;Count:=0;Found:=False;IsDirectoryOperand:=False;
  FindFirst(Operand,AnyFile,SearchRecord);
  If DosError=0 Then Begin
    Found:=True;
    IsDirectoryOperand:=EntryIsDirectory(SearchRecord.Attr)and Not DirectoryAsFile;
  End;
  {$IFDEF FPC}FindClose(SearchRecord);{$ENDIF}
  If Not Found Then Begin
    If Not QuietErrors Then WriteLn('ls: impossible d''acceder a ',Operand);
    ErrorFound:=True;
    Exit;
  End;
  If IsDirectoryOperand Then Begin
    ListDirectory(Operand,0);
    Exit;
  End;
  GatherPath(Operand,Head,Tail,Count);
  If Count=0 Then Begin
    If Not QuietErrors Then WriteLn('ls: aucun fichier correspondant: ',Operand);
    ErrorFound:=True;
  End Else DisplayEntries(Head);
  FreeEntries(Head);
End;

Function ParseNumber(Const TextValue:TPath; Var Number:Integer):Boolean;
Var
  Parsed,ErrorCode:Integer;
Begin
  Val(TextValue,Parsed,ErrorCode);
  ParseNumber:=ErrorCode=0;
  If ErrorCode=0 Then Number:=Parsed;
End;

Procedure AddOperand(Const Value:TPath);
Begin
  If OperandCount>=MaxOperands Then Begin
    WriteLn('ls: trop d''operandes');Halt(2);
  End;
  Inc(OperandCount);Operands[OperandCount]:=Value;
End;

Procedure AddIgnorePattern(Const Value:TName);
Begin
  If IgnoreCount>=MaxIgnorePatterns Then Begin
    WriteLn('ls: trop de motifs -I');Halt(2);
  End;
  Inc(IgnoreCount);IgnorePatterns[IgnoreCount]:=Value;
End;

Procedure PrintHelp;
Begin
  If English Then Begin
    WriteLn('ls - list directory contents');
    WriteLn('Usage: ls [OPTIONS] [name ...]');
    WriteLn(' -a -A -B -d -F -i -l -m -n -p -q -Q -R -r -S -s -t -U -u -x -1');
    WriteLn(' -w cols -T cols -I pattern');
    WriteLn(' --all --almost-all --ignore-backups --classify --directory');
    WriteLn(' --format=FORMAT --sort=ORDER --ignore=PATTERN --width=COLS');
    WriteLn(' --recursive --reverse --size --inode --full-time --help --version');
  End Else Begin
    WriteLn('LS - Cette commande permet d''afficher le contenu des r'+#130+'pertoires.');
    WriteLn;
    WriteLn('Syntaxe : ls [OPTIONS] [nom ...]');
    WriteLn;
    WriteLn('-a                  Afficher tous les fichiers, y compris les fichiers caches');
    WriteLn('-A                  Afficher presque tous les fichiers, sauf . et ..');
    WriteLn('-B                  Ignorer les fichiers de sauvegarde se terminant par ~');
    WriteLn('-d                  Afficher les informations sur le repertoire lui-meme');
    WriteLn('-F                  Ajouter un caractere special aux fichiers selon leur type');
    WriteLn('-i                  Afficher l''inode des fichiers');
    WriteLn('-l                  Afficher les fichiers en format long');
    WriteLn('-m                  Afficher les fichiers separes par des virgules');
    WriteLn('-n                  Afficher les numeros d''utilisateur et de groupe au lieu des noms');
    WriteLn('-p                  Ajouter un / aux repertoires');
    WriteLn('-q                  Remplacer les caracteres non imprimables par des ?');
    WriteLn('-Q                  Mettre les noms de fichiers entre guillemets');
    WriteLn('-R                  Afficher les repertoires de maniere recursive');
    WriteLn('-r                  Trier dans l''ordre inverse');
    WriteLn('-S                  Trier par taille');
    WriteLn('-s                  Afficher la taille des fichiers en blocs');
    WriteLn('-t                  Trier par date de modification');
    WriteLn('-U                  Ne pas trier, afficher dans l''ordre de creation');
    WriteLn('-u                  Trier par date d''acces');
    WriteLn('-x                  Afficher les fichiers en colonnes');
    WriteLn('-1                  Afficher un fichier par ligne');
    WriteLn(' -w colonnes        Indique la largeur des colonnes');
    WriteLn(' -T colonnes        Indique le nombre de colonnes');
    WriteLn(' -I motif           Ignore les fichiers correspondant au motif');
    WriteLn(' --all              Indique tous les fichiers, y compris les fichiers caches');
    WriteLn(' --almost-all       Indique presque tous les fichiers, sauf . et ..');
    WriteLn(' --ignore-backups   Ignore les fichiers de sauvegarde se terminant par ~');
    WriteLn(' --classify         Ajouter un caractere special aux fichiers selon leur type');
    WriteLn(' --directory        Afficher les informations sur le repertoire lui-meme');
    WriteLn(' --format=FORMAT    Indique le format d''affichage');
    WriteLn(' --sort=ORDRE       Indique l''ordre de tri');
    WriteLn(' --ignore=MOTIF     Ignore les fichiers correspondant au motif');
    WriteLn(' --width=COLONNES   Indique la largeur des colonnes');
    WriteLn(' --recursive        Afficher les repertoires de maniere recursive');
    WriteLn(' --reverse          Trier dans l''ordre inverse');
    WriteLn(' --size             Trier par taille');
    WriteLn(' --inode            Afficher l''inode des fichiers');
    WriteLn(' --full-time        Afficher la date et l''heure complete de modification');
    WriteLn(' --help             Afficher l''aide');
    WriteLn(' --version          Afficher la version');
  End;
End;

Procedure OptionError(Const MessageText:TPath);
Begin
  If English Then WriteLn('ls: ',MessageText)Else WriteLn('ls : ',MessageText);
  Halt(2);
End;

Procedure SetFormat(Const Value:TName);
Begin
  If(Value='long')or(Value='verbose')Then Begin LongFormat:=True;FormatMode:=5;End
  Else If Value='commas'Then FormatMode:=2
  Else If(Value='across')Then FormatMode:=3
  Else If(Value='vertical')Then FormatMode:=4
  Else If(Value='single-column')Then FormatMode:=5
  Else OptionError('format inconnu: '+Value);
End;

Procedure SetSort(Const Value:TName);
Begin
  If Value='none'Then Begin NoSort:=True;SortMode:=1;End
  Else If Value='time'Then Begin NoSort:=False;SortMode:=2;End
  Else If Value='size'Then Begin NoSort:=False;SortMode:=3;End
  Else If Value='extension'Then Begin NoSort:=False;SortMode:=4;End
  Else OptionError('ordre de tri inconnu: '+Value);
End;

Procedure ParseOptions;
Var
  Index,CharacterIndex,Number:Integer;
  Argument,OptionValue:TPath;
  EndOptions:Boolean;
Begin
  Index:=1;EndOptions:=False;
  While Index<=ParamCount Do Begin
    Argument:=ParamStr(Index);
    If Not EndOptions and(Argument='--')Then EndOptions:=True
    Else If Not EndOptions and((Argument='--help')or(Argument='-h')or
      (Argument='/?')or(Argument='/h')or(Argument='/H'))Then Begin PrintHelp;Halt(0);End
    Else If Not EndOptions and((Argument='--version')or(Argument='-V'))Then Begin
      WriteLn('ls (LINUX-0) 2.0');Halt(0);
    End Else If Not EndOptions and(Argument='--all')Then ShowAll:=True
    Else If Not EndOptions and(Argument='--almost-all')Then AlmostAll:=True
    Else If Not EndOptions and((Argument='-B')or(Argument='--ignore-backups'))Then IgnoreBackups:=True
    Else If Not EndOptions and((Argument='-b')or(Argument='--escape'))Then EscapeNames:=True
    Else If Not EndOptions and(Argument='--classify')Then Classify:=True
    Else If Not EndOptions and((Argument='-d')or(Argument='--directory'))Then DirectoryAsFile:=True
    Else If Not EndOptions and((Argument='-F'))Then Classify:=True
    Else If Not EndOptions and(Argument='--file-type')Then FileTypeOnly:=True
    Else If Not EndOptions and(Argument='--full-time')Then FullTime:=True
    Else If Not EndOptions and((Argument='-G')or(Argument='--group'))Then ShowGroup:=True
    Else If Not EndOptions and((Argument='-g')or(Argument='-l'))Then LongFormat:=True
    Else If Not EndOptions and((Argument='-i')or(Argument='--inode'))Then ShowInode:=True
    Else If Not EndOptions and((Argument='-k')or(Argument='--kilobytes'))Then SizeInKilobytes:=True
    Else If Not EndOptions and((Argument='-L')or(Argument='--dereference'))Then Begin End
    Else If Not EndOptions and((Argument='-m')or(Argument='--format=commas'))Then FormatMode:=2
    Else If Not EndOptions and((Argument='-n')or(Argument='--numeric-uid-gid'))Then Begin
      NumericIds:=True;LongFormat:=True;
    End
    Else If Not EndOptions and((Argument='-N')or(Argument='--literal'))Then Begin QuoteNames:=False;EscapeNames:=False;End
    Else If Not EndOptions and((Argument='--no-group')or(Argument='-no-group'))Then NoGroup:=True
    Else If Not EndOptions and(Argument='--hide-control-chars')Then HideControls:=True
    Else If Not EndOptions and((Argument='-p'))Then PermitDirectorySuffix:=True
    Else If Not EndOptions and(Argument='--quote-name')Then QuoteNames:=True
    Else If Not EndOptions and((Argument='-Q'))Then QuoteNames:=True
    Else If Not EndOptions and((Argument='-q')or(Argument='--hide-control-chars'))Then HideControls:=True
    Else If Not EndOptions and((Argument='-R')or(Argument='--recursive'))Then Recursive:=True
    Else If Not EndOptions and((Argument='-r')or(Argument='--reverse'))Then ReverseSort:=True
    Else If Not EndOptions and(Argument='-S')Then SortMode:=3
    Else If Not EndOptions and((Argument='-s')or(Argument='--size'))Then ShowSize:=True
    Else If Not EndOptions and((Argument='-t')or(Argument='-c')or(Argument='-u'))Then Begin
      SortMode:=2;
    End Else If Not EndOptions and(Argument='-U')Then Begin NoSort:=True;SortMode:=1;End
    Else If Not EndOptions and((Argument='-1'))Then FormatMode:=5
    Else If Not EndOptions and(Argument='-C')Then FormatMode:=4
    Else If Not EndOptions and(Argument='-x')Then FormatMode:=3
    Else If Not EndOptions and(Argument='-f')Then Begin ShowAll:=True;NoSort:=True;SortMode:=1;End
    Else If Not EndOptions and(Argument='--format')Then Begin
      Inc(Index);If Index>ParamCount Then OptionError('--format attend une valeur');
      SetFormat(ParamStr(Index));
    End Else If Not EndOptions and(Copy(Argument,1,9)='--format=')Then
      SetFormat(Copy(Argument,10,MaxNameLength))
    Else If Not EndOptions and(Copy(Argument,1,8)='-format=')Then
      SetFormat(Copy(Argument,9,MaxNameLength))
    Else If Not EndOptions and(Argument='--sort')Then Begin
      Inc(Index);If Index>ParamCount Then OptionError('--sort attend un ordre');
      SetSort(ParamStr(Index));
    End Else If Not EndOptions and(Copy(Argument,1,7)='--sort=')Then
      SetSort(Copy(Argument,8,MaxNameLength))
    Else If Not EndOptions and(Copy(Argument,1,6)='-sort=')Then
      SetSort(Copy(Argument,7,MaxNameLength))
    Else If Not EndOptions and(Argument='--time')Then Begin
      Inc(Index);If Index>ParamCount Then OptionError('--time attend une valeur');
      OptionValue:=ParamStr(Index);
      If Not((OptionValue='atime')or(OptionValue='access')or(OptionValue='use')or
        (OptionValue='ctime')or(OptionValue='status'))Then OptionError('type de temps inconnu');
      LongFormat:=True;
    End Else If Not EndOptions and(Copy(Argument,1,7)='--time=')Then Begin
      OptionValue:=Copy(Argument,8,MaxNameLength);
      If Not((OptionValue='atime')or(OptionValue='access')or(OptionValue='use')or
        (OptionValue='ctime')or(OptionValue='status'))Then OptionError('type de temps inconnu');
      LongFormat:=True;
    End
    Else If Not EndOptions and((Argument='-w')or(Argument='-T'))Then Begin
      Inc(Index);If Index>ParamCount Then OptionError(Argument+' attend un nombre');
      OptionValue:=ParamStr(Index);
      If Not ParseNumber(OptionValue,Number)Then OptionError('nombre invalide');
      If Argument='-w'Then WidthColumns:=Number Else TabSize:=Number;
    End Else If Not EndOptions and(Copy(Argument,1,3)='-w=')Then Begin
      OptionValue:=Copy(Argument,4,MaxPathLength);
      If Not ParseNumber(OptionValue,WidthColumns)Then OptionError('largeur invalide');
    End Else If Not EndOptions and(Copy(Argument,1,3)='-T=')Then Begin
      OptionValue:=Copy(Argument,4,MaxPathLength);
      If Not ParseNumber(OptionValue,TabSize)Then OptionError('taille de tabulation invalide');
    End Else If Not EndOptions and(Copy(Argument,1,2)='-w')and(Length(Argument)>2)Then Begin
      OptionValue:=Copy(Argument,3,MaxPathLength);
      If Not ParseNumber(OptionValue,WidthColumns)Then OptionError('largeur invalide');
    End Else If Not EndOptions and(Copy(Argument,1,2)='-T')and(Length(Argument)>2)Then Begin
      OptionValue:=Copy(Argument,3,MaxPathLength);
      If Not ParseNumber(OptionValue,TabSize)Then OptionError('taille de tabulation invalide');
    End Else If Not EndOptions and(Copy(Argument,1,8)='--width=')Then Begin
      OptionValue:=Copy(Argument,9,MaxPathLength);
      If Not ParseNumber(OptionValue,WidthColumns)Then OptionError('largeur invalide');
    End Else If Not EndOptions and(Copy(Argument,1,10)='--tabsize=')Then Begin
      OptionValue:=Copy(Argument,11,MaxPathLength);
      If Not ParseNumber(OptionValue,TabSize)Then OptionError('taille de tabulation invalide');
    End Else If Not EndOptions and((Argument='-I'))Then Begin
      Inc(Index);If Index>ParamCount Then OptionError('-I attend un motif');
      AddIgnorePattern(ParamStr(Index));
    End Else If Not EndOptions and(Copy(Argument,1,3)='-I=')Then
      AddIgnorePattern(Copy(Argument,4,MaxNameLength))
    Else If Not EndOptions and(Copy(Argument,1,9)='--ignore=')Then
      AddIgnorePattern(Copy(Argument,10,MaxNameLength))
    Else If Not EndOptions and(Length(Argument)>1)and(Argument[1]='-')Then Begin
      For CharacterIndex:=2 to Length(Argument)Do Begin
        Case Argument[CharacterIndex]Of
          'a':ShowAll:=True;
          'A':AlmostAll:=True;
          'B':IgnoreBackups:=True;
          'b':EscapeNames:=True;
          'C':FormatMode:=4;
          'c','t','u':SortMode:=2;
          'd':DirectoryAsFile:=True;
          'F':Classify:=True;
          'f':Begin ShowAll:=True;NoSort:=True;SortMode:=1;End;
          'g','l':LongFormat:=True;
          'G':ShowGroup:=True;
          'i':ShowInode:=True;
          'k':SizeInKilobytes:=True;
          'm':FormatMode:=2;
          'n':NumericIds:=True;
          'N':Begin QuoteNames:=False;EscapeNames:=False;End;
          'p':PermitDirectorySuffix:=True;
          'q':HideControls:=True;
          'Q':QuoteNames:=True;
          'R':Recursive:=True;
          'r':ReverseSort:=True;
          'S':SortMode:=3;
          's':ShowSize:=True;
          'U':Begin NoSort:=True;SortMode:=1;End;
          'X':SortMode:=4;
          'x':FormatMode:=3;
          '1':FormatMode:=5;
        Else OptionError('option inconnue: '+Argument);End;
      End;
    End Else AddOperand(Argument);
    Inc(Index);
  End;
End;

Begin
  OperandCount:=0;IgnoreCount:=0;
  WidthColumns:=DefaultWidth;TabSize:=8;FormatMode:=0;SortMode:=0;
  ShowAll:=False;AlmostAll:=False;IgnoreBackups:=False;DirectoryAsFile:=False;
  Classify:=False;FileTypeOnly:=False;LongFormat:=False;VerboseFormat:=False;
  ShowInode:=False;ShowSize:=False;SizeInKilobytes:=False;NumericIds:=False;
  ShowGroup:=False;NoGroup:=False;QuoteNames:=False;EscapeNames:=False;HideControls:=False;
  ReverseSort:=False;Recursive:=False;NoSort:=False;FullTime:=False;
  QuietErrors:=False;ErrorFound:=False;EntrySerial:=0;
  English:=Copy(GetEnv('LANGUAGE'),1,2)='EN';
  ParseOptions;
  If OperandCount=0 Then Begin
    ListDirectory('.',0);
  End Else For MainIndex:=1 to OperandCount Do ListOperand(Operands[MainIndex]);
  If ErrorFound Then Halt(1);
END.
