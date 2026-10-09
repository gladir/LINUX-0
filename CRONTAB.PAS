{ @author: Sylvain Maltais (support@gladir.com)
 @created: 2026
 @website(https://www.gladir.com/linux-0)
 @abstract(Target: Turbo Pascal 7, Free Pascal 3.2) }

Program CRONTAB;


Uses DOS;

Const
 MaxFiles=16;
 MaxUserName=63;

Type
 TFileArray=Array[1..MaxFiles]Of String[255];
 TMode=(_Install,_List,_Remove,_Edit);

Var
 InputFile,CrontabFile,TempFile:Text;
 FileNames:TFileArray;
 FileCount,ArgumentIndex:Integer;
 Mode:TMode;
 CurrentUser,CrontabDirectory,CrontabName,TempName,BackupName:String;
 Argument,OptionValue,SecurityLevel:String;
 UserSpecified,InteractiveRemove,AddSecurity,QuietMode,EndOptions:Boolean;
 ErrorFound,TempOpened:Boolean;
 ErrorCode,LineNumber:Integer;

Procedure PrintHelp;Begin
 If Copy(GetEnv('LANGUAGE'),1,2)='EN'Then Begin
  WriteLn('CRONTAB : Install, display, edit or remove a user crontab.');
  WriteLn('Syntax: crontab [-u user] file');
  WriteLn('        crontab [-u user] [-l | -r | -e] [-i] [-s]');
  WriteLn('        crontab -c directory');
  WriteLn(' -u USER  Select the crontab owner');
  WriteLn(' -l       Display the current crontab');
  WriteLn(' -r, -d  Remove the current crontab');
  WriteLn(' -e       Edit the crontab with the built-in line editor');
  WriteLn(' -i       Confirm before removal');
  WriteLn(' -s       Add MLS_LEVEL from the environment');
  WriteLn(' -c DIR   Select the crontab storage directory');
  WriteLn('A file name of - reads the replacement table from standard input.');
 End Else
 Begin
  WriteLn(
  'CRONTAB : Cette commande permet d''installer, d''afficher, de modifier ou de supprimer une table cron.');
  WriteLn;
  WriteLn('Syntaxe : crontab [-u utilisateur] fichier');
  WriteLn('          crontab [-u utilisateur] [-l | -r | -e] [-i] [-s]');
  WriteLn('          crontab -c repertoire');
  WriteLn;
  WriteLn(' -u UTILISATEUR  Choisir le proprietaire de la table');
  WriteLn(' -l              Afficher la table courante');
  WriteLn(' -r, -d          Supprimer la table courante');
  WriteLn(' -e              Modifier avec l''editeur integre');
  WriteLn(' -i              Confirmer avant la suppression');
  WriteLn(' -s              Ajouter MLS_LEVEL depuis l''environnement');
  WriteLn(' -c REP          Choisir le repertoire d''entreposage');
  WriteLn;
  WriteLn('Le nom - lit la table de remplacement depuis stdin.');
 End;
End;

Procedure PrintLicense;Begin
 WriteLn('CRONTAB (LINUX-0)');
 WriteLn('Implementation native Pascal, sans programme externe.');
 WriteLn('Voir le fichier LICENSE du depot pour les conditions applicables.');
End;

Procedure UsageError(Const MessageText:String);Begin
 WriteLn('crontab: ',MessageText);
 Halt(2);
End;

Procedure ReportError(Const MessageText:String);Begin
 If Not QuietMode Then WriteLn('crontab: ',MessageText);
 ErrorFound:=True;
End;

Function IsDirectory(Const Path:String):Boolean;
Var
 Search:SearchRec;
Begin
 FindFirst(Path,AnyFile,Search);
 IsDirectory:=(DosError=0)And((Search.Attr And Directory)<>0);
 {$IFDEF FPC}
  FindClose(Search);
 {$ENDIF}
End;

Function DirectorySeparator(Const Path:String):Char;Begin
 If(Pos('/',Path)>0)And(Pos('\',Path)=0)Then DirectorySeparator:='/'
 Else DirectorySeparator:='\';
End;

Procedure EnsureDirectory(Const Path:String);
Var
 Position,StartPosition:Integer;
 Prefix:String;
Begin
 If Path=''Then UsageError('repertoire vide');
 StartPosition:=1;
 If(Path[1]='\')Or(Path[1]='/')Then StartPosition:=2;
 If(Length(Path)>=3)And(Path[2]=':')Then StartPosition:=4;
 Position:=StartPosition;
 While Position<=Length(Path)+1 Do Begin
  If(Position>Length(Path))Or(Path[Position]In['\','/'])Then Begin
   Prefix:=Copy(Path,1,Position-1);
   If(Prefix<>'')And Not IsDirectory(Prefix)Then Begin
        {$I-}MkDir(Prefix);{$I+}
    If IOResult<>0 Then          If Not IsDirectory(Prefix)Then            UsageError(
    'impossible de creer le repertoire '+Prefix);
   End;
   StartPosition:=Position+1;
  End;
  Inc(Position);
 End;
End;

Function SafeUserName(Const Name:String):Boolean;
Var
 Index:Integer;
Begin
 SafeUserName:=(Name<>'')And(Length(Name)<=MaxUserName);
 For Index:=1 To Length(Name)Do    If Not(Name[Index]In['A'..'Z','a'..'z','0'..'9','_',
 '-','.'])Then      SafeUserName:=False;
End;

Function IsBlank(Const Value:String):Boolean;
Var
 Index:Integer;
Begin
 IsBlank:=True;
 For Index:=1 To Length(Value)Do    If Not(Value[Index]In[' ',#9,#13])Then Begin
  IsBlank:=False;
  Exit;
 End;
End;

Function IsCommentOrAssignment(Const Value:String):Boolean;
Var
 Position:Integer;
Begin
 Position:=1;
 While(Position<=Length(Value))And(Value[Position]In[' ',#9])Do Inc(Position);
 If Position>Length(Value)Then Begin
  IsCommentOrAssignment:=True; Exit;
 End;
 If Value[Position]='#'Then Begin
  IsCommentOrAssignment:=True; Exit;
 End;
 While(Position<=Length(Value))And
 (Value[Position]In['A'..'Z','a'..'z','0'..'9','_'])Do Inc(Position);
 IsCommentOrAssignment:=(Position>1)And(Position<=Length(Value))And
 (Value[Position]='=');
End;

Function IsValidCronLine(Const Value:String):Boolean;
Var
 Position,FieldCount,StartPosition:Integer;
 Token:String;
Begin
 IsValidCronLine:=True;
 If IsCommentOrAssignment(Value)Then Exit;
 Position:=1;
 While(Position<=Length(Value))And(Value[Position]In[' ',#9])Do Inc(Position);
 If Position>Length(Value)Then Exit;
 If Value[Position]='@'Then Begin
  StartPosition:=Position;
  While(Position<=Length(Value))And Not(Value[Position]In[' ',#9])Do Inc(Position);
  Token:=Copy(Value,StartPosition,Position-StartPosition);
  If Not((Token='@reboot')Or(Token='@yearly')Or(Token='@annually')Or
  (Token='@monthly')Or(Token='@weekly')Or(Token='@daily')Or
  (Token='@midnight')Or(Token='@hourly'))Then Begin
   IsValidCronLine:=False;
   Exit;
  End;
  While(Position<=Length(Value))And(Value[Position]In[' ',#9])Do Inc(Position);
  IsValidCronLine:=Position<=Length(Value);
  Exit;
 End;
 FieldCount:=0;
 While(FieldCount<5)And(Position<=Length(Value))Do Begin
  While(Position<=Length(Value))And(Value[Position]In[' ',#9])Do Inc(Position);
  If Position>Length(Value)Then Break;
  Inc(FieldCount);
  While(Position<=Length(Value))And Not(Value[Position]In[' ',#9])Do Inc(Position);
 End;
 While(Position<=Length(Value))And(Value[Position]In[' ',#9])Do Inc(Position);
 IsValidCronLine:=(FieldCount=5)And(Position<=Length(Value));
End;

Procedure ValidateCronLine(Const Value:String; AtLine:Integer);Begin
 If Not IsValidCronLine(Value)Then Begin
  WriteLn('crontab: ligne ',AtLine,' invalide');
  ErrorFound:=True;
 End;
End;

Procedure WriteSecurityLevel(Var Destination:Text);Begin
 If AddSecurity And(SecurityLevel<>'')Then    WriteLn(Destination,'MLS_LEVEL=',
 SecurityLevel);
End;

Procedure CopyTable(Var Source,Destination:Text; IncludeSecurity:Boolean);
Var
 CurrentLine:String;
 CurrentLineNumber:Integer;
Begin
 CurrentLineNumber:=0;
 If IncludeSecurity Then WriteSecurityLevel(Destination);
 While Not EOF(Source)Do Begin
  ReadLn(Source,CurrentLine);
  Inc(CurrentLineNumber);
  If Not(IncludeSecurity And AddSecurity And(SecurityLevel<>''))Or
  (Copy(CurrentLine,1,10)<>'MLS_LEVEL=')Then Begin
   ValidateCronLine(CurrentLine,CurrentLineNumber);
   WriteLn(Destination,CurrentLine);
  End;
 End;
End;

Function CronPath(Const UserName:String):String;
Var
 Separator:Char;
Begin
 Separator:=DirectorySeparator(CrontabDirectory);
 If CrontabDirectory[Length(CrontabDirectory)]In['\','/']Then    CronPath:=
 CrontabDirectory+UserName+'.tab'
 Else CronPath:=CrontabDirectory+Separator+UserName+'.tab';
End;

Function ExistingTable:Boolean;
Var
 Search:SearchRec;
Begin
 FindFirst(CrontabName,AnyFile,Search);
 ExistingTable:=(DosError=0)And((Search.Attr And Directory)=0);
 {$IFDEF FPC}
  FindClose(Search);
 {$ENDIF}
End;

Procedure OpenTempTable;Begin
 TempName:=CrontabName+'.tmp';
 Assign(TempFile,TempName);
  {$I-}Rewrite(TempFile);{$I+}
 If IOResult<>0 Then UsageError('impossible de creer '+TempName);
 TempOpened:=True;
End;

Procedure CloseTempTable;Begin
 If TempOpened Then Begin
  Close(TempFile);
  TempOpened:=False;
 End;
End;

Procedure CommitTempTable;
Var
 RenameError,IgnoredError:Integer;
 HadOldTable:Boolean;
Begin
 CloseTempTable;
 If ErrorFound Then Begin
  Assign(TempFile,TempName);
    {$I-}Erase(TempFile);{$I+}IgnoredError:=IOResult;
  Exit;
 End;
 BackupName:=CrontabName+'.bak';
 HadOldTable:=ExistingTable;
 If HadOldTable Then Begin
  Assign(CrontabFile,CrontabName);
    {$I-}Rename(CrontabFile,BackupName);{$I+}
  RenameError:=IOResult;
  If RenameError<>0 Then Begin
   ReportError('impossible de sauvegarder la table courante'); Exit;
  End;
 End;
 Assign(TempFile,TempName);
  {$I-}Rename(TempFile,CrontabName);{$I+}
 RenameError:=IOResult;
 If RenameError<>0 Then Begin
  If HadOldTable Then Begin
   Assign(CrontabFile,BackupName);
      {$I-}Rename(CrontabFile,CrontabName);{$I+}IgnoredError:=IOResult;
  End;
  ReportError('impossible d''installer la nouvelle table');
  Exit;
 End;
 If HadOldTable Then Begin
  Assign(CrontabFile,BackupName);
    {$I-}Erase(CrontabFile);{$I+}IgnoredError:=IOResult;
 End;
End;

Procedure InstallFromFile(Const FileName:String);
Var
 IgnoreError:Integer;
Begin
 OpenTempTable;
 If FileName='-'Then Begin
  CopyTable(Input,TempFile,True);
 End Else
 Begin
  Assign(InputFile,FileName);
    {$I-}Reset(InputFile);{$I+}
  If IOResult<>0 Then Begin
   CloseTempTable;
   Assign(TempFile,TempName);{$I-}Erase(TempFile);{$I+}IgnoreError:=IOResult;
   UsageError('impossible de lire '+FileName);
  End;
  CopyTable(InputFile,TempFile,True);
  Close(InputFile);
 End;
 CommitTempTable;
End;

Procedure EditTable;
Var
 CurrentLine:String;
Begin
 If ExistingTable Then Begin
  Assign(CrontabFile,CrontabName);
    {$I-}Reset(CrontabFile);{$I+}
  If IOResult=0 Then Begin
   WriteLn('--- ',CrontabName,' ---');
   While Not EOF(CrontabFile)Do Begin
    ReadLn(CrontabFile,CurrentLine); WriteLn(CurrentLine);
   End;
   Close(CrontabFile);
  End;
 End;
 WriteLn('Saisissez le nouveau crontab; une ligne contenant uniquement . termine.');
 OpenTempTable;
 WriteSecurityLevel(TempFile);
 LineNumber:=0;
 Repeat
 ReadLn(Input,CurrentLine);
 If CurrentLine<>'.'Then Begin
  Inc(LineNumber);
  If Not(AddSecurity And(SecurityLevel<>''))Or
  (Copy(CurrentLine,1,10)<>'MLS_LEVEL=')Then        ValidateCronLine(CurrentLine,
  LineNumber);
  If Not(AddSecurity And(SecurityLevel<>''))Or
  (Copy(CurrentLine,1,10)<>'MLS_LEVEL=')Then        WriteLn(TempFile,CurrentLine);
 End;
 Until CurrentLine='.';
 CommitTempTable;
End;

Procedure ListTable;
Var
 CurrentLine:String;
Begin
 If Not ExistingTable Then Begin
  WriteLn('crontab: aucune table pour ',CurrentUser);
  Halt(1);
 End;
 Assign(CrontabFile,CrontabName);
  {$I-}Reset(CrontabFile);{$I+}
 If IOResult<>0 Then UsageError('impossible de lire '+CrontabName);
 While Not EOF(CrontabFile)Do Begin
  ReadLn(CrontabFile,CurrentLine); WriteLn(CurrentLine);
 End;
 Close(CrontabFile);
End;

Function AskConfirmation:Boolean;
Var
 Reply:String;
Begin
 Write('Supprimer la table de ',CurrentUser,' ? (y/N) ');
 ReadLn(Input,Reply);
 AskConfirmation:=(Reply='y')Or(Reply='Y');
End;

Procedure RemoveTable;
Var
 FileToRemove:File;
Begin
 If Not ExistingTable Then Begin
  If Not QuietMode Then WriteLn('crontab: aucune table pour ',CurrentUser);
  Exit;
 End;
 If InteractiveRemove And Not AskConfirmation Then Exit;
 Assign(FileToRemove,CrontabName);
  {$I-}Erase(FileToRemove);{$I+}
 If IOResult<>0 Then ReportError('impossible de supprimer '+CrontabName);
End;

Procedure ReadOptionValue(Const OptionName:String; Var Index:Integer;
                          Var Value:String);Begin
 Inc(Index);
 If Index>ParamCount Then UsageError('valeur manquante pour '+OptionName);
 Value:=ParamStr(Index);
End;

BEGIN
 FileCount:=0;
 Mode:=_Install;
 UserSpecified:=False;
 InteractiveRemove:=False;
 AddSecurity:=False;
 QuietMode:=False;
 ErrorFound:=False;
 TempOpened:=False;
 EndOptions:=False;
 CrontabDirectory:=GetEnv('CRONTAB_DIR');
 If CrontabDirectory=''Then CrontabDirectory:='CRONTABS';
 CurrentUser:=GetEnv('USER');
 If CurrentUser=''Then CurrentUser:=GetEnv('USERNAME');
 If CurrentUser=''Then CurrentUser:='default';
 ArgumentIndex:=1;
 While ArgumentIndex<=ParamCount Do Begin
  Argument:=ParamStr(ArgumentIndex);
  If Not EndOptions And(Argument='--')Then EndOptions:=True Else
  If Not EndOptions And((Argument='--help')Or(Argument='-h')Or(Argument='/?'))Then Begin
   PrintHelp; Halt(0);
  End
  Else If Not EndOptions And((Argument='--version')Or(Argument='-V'))Then Begin
   WriteLn('crontab (LINUX-0) 1.0'); Halt(0);
  End
  Else If Not EndOptions And((Argument='--license')Or(Argument='-L'))Then Begin
   PrintLicense; Halt(0);
  End
  Else If Not EndOptions And((Argument='-u')Or(Argument='--user'))Then Begin
   ReadOptionValue(Argument,ArgumentIndex,OptionValue);
   If Not SafeUserName(OptionValue)Then UsageError('nom d''utilisateur invalide');
   CurrentUser:=OptionValue; UserSpecified:=True;
  End Else If Not EndOptions And(Argument='-c')Then Begin
   ReadOptionValue(Argument,ArgumentIndex,CrontabDirectory);
  End Else If Not EndOptions And((Argument='-l')Or(Argument='--list'))Then Mode:=_List
  Else If Not EndOptions And((Argument='-r')Or(Argument='-d')Or(Argument='--remove'))
  Then Mode:=_Remove Else
  If Not EndOptions And((Argument='-e')Or(Argument='--edit'))Then Mode:=_Edit
  Else If Not EndOptions And((Argument='-i')Or(Argument='--interactive'))
  Then InteractiveRemove:=True Else
  If Not EndOptions And((Argument='-s')Or(Argument='--selinux'))Then AddSecurity:=
  True
  Else If Not EndOptions And((Argument='-q')Or(Argument='--quiet'))Then QuietMode:=True
  Else If Not EndOptions And(Length(Argument)>1)And(Argument[1]='-')Then Begin
   If Argument[2]='-'Then UsageError('option inconnue : '+Argument);
   For ErrorCode:=2 To Length(Argument)Do Begin
    If Argument[ErrorCode]='u'Then Begin
     ReadOptionValue('-u',ArgumentIndex,OptionValue);
     If Not SafeUserName(OptionValue)Then UsageError('nom d''utilisateur invalide');
     CurrentUser:=OptionValue; UserSpecified:=True;
     Break;
    End Else If Argument[ErrorCode]='l'Then Mode:=_List
    Else If(Argument[ErrorCode]='r')Or(Argument[ErrorCode]='d')Then Mode:=_Remove
    Else If Argument[ErrorCode]='e'Then Mode:=_Edit
    Else If Argument[ErrorCode]='i'Then InteractiveRemove:=True
    Else If Argument[ErrorCode]='s'Then AddSecurity:=True
    Else UsageError('option inconnue : '+Argument);
   End;
  End Else If Not EndOptions And(Mode<>_Install)And(FileCount=0)
  And Not UserSpecified Then Begin
   If Not SafeUserName(Argument)Then UsageError('nom d''utilisateur invalide');
   CurrentUser:=Argument; UserSpecified:=True;
  End Else
  Begin
   If FileCount>=MaxFiles Then UsageError('trop de fichiers');
   Inc(FileCount); FileNames[FileCount]:=Argument;
  End;
  Inc(ArgumentIndex);
 End;
 If InteractiveRemove And(Mode<>_Remove)Then UsageError(
 '-i doit etre utilise avec -r ou -d');
 If(Mode<>_Install)And(FileCount>0)Then UsageError('fichier inattendu avec cette option');
 If(Mode=_Install)And(FileCount<>1)Then Begin
  PrintHelp; Halt(2);
 End;
 If Not SafeUserName(CurrentUser)Then UsageError('nom d''utilisateur invalide');
 EnsureDirectory(CrontabDirectory);
 CrontabName:=CronPath(CurrentUser);
 SecurityLevel:=GetEnv('MLS_LEVEL');
 Case Mode Of
 _List:ListTable;
 _Remove:RemoveTable;
 _Edit:EditTable;
 _Install:InstallFromFile(FileNames[1]);
End;
If ErrorFound Then Halt(1);
END.
