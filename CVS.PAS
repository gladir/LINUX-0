{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2026
  @website(https://www.gladir.com/linux-0)
  @abstract(Target: Turbo Pascal 7, Free Pascal 3.2)
}

Program CVS;

Uses DOS;

Const
  MaxEntries=96;
  MaxArguments=64;
  CopyBufferSize=2048;

Type
  TRepoName=String[127];
  TArgumentArray=Array[1..MaxArguments]Of TRepoName;
  TCopyBuffer=Array[0..CopyBufferSize-1]Of Byte;
  TRepoEntry=Record
    Name:TRepoName;
    Revision:LongInt;
  End;
  TEntryArray=Array[1..MaxEntries]Of TRepoEntry;

Var
  Entries:TEntryArray;
  Arguments:TArgumentArray;
  RepoPath,CommandName,OptionValue,CommitMessage,CurrentFile,Argument,LanguageCode:String;
  EntryCount,ArgumentCount,ArgumentIndex,EntryIndex,FileIndex:Integer;
  RevisionNumber,NextRevision:LongInt;
  QuietMode,ForceMode,ErrorFound,DryRun:Boolean;
  Search:SearchRec;

Function FindArgument(Const Name:String):Integer;Forward;

Procedure ReportError(Const MessageText:String);
Begin
  If Not QuietMode Then WriteLn('cvs: ',MessageText);
  ErrorFound:=True;
End;

Procedure OptionError(Const MessageText:String);
Begin
  WriteLn('cvs: ',MessageText);
  Halt(2);
End;

Procedure UsageError(Const MessageText:String);
Begin
  WriteLn('cvs: ',MessageText);
  Halt(2);
End;

Procedure PrintHelp;
Begin
  If Copy(GetEnv('LANGUAGE'),1,2)='EN'Then Begin
    WriteLn('CVS : Manage a local source revision repository.');
    WriteLn('Syntax: cvs [-qQfn] [-d repository] command [options] [files ...]');
    WriteLn(' init [directory]          Create a repository');
    WriteLn(' add file ...               Add files to tracking');
    WriteLn(' commit [-m message]        Save changed files as a revision');
    WriteLn(' status [file ...]          Show tracked-file state');
    WriteLn(' log [file ...]             Show revision history');
    WriteLn(' diff [file ...]            Report changed files');
    WriteLn(' checkout [file ...]        Restore files from the repository');
    WriteLn(' update [file ...]          Restore missing working files');
    WriteLn(' remove file ...            Stop tracking files (working files remain)');
    WriteLn(' -d DIR  Select local repository directory (default .cvs)');
    WriteLn(' -q      Suppress routine messages');
    WriteLn(' -n      Do not change repository or working files');
    WriteLn('This is a local Pascal implementation; it does not use a CVS server.');
  End Else Begin
    WriteLn('CVS : Cette commande permet de g'+#130+'rer un d'+#130+'pot local de revisions de sources.');
    WriteLn;
    WriteLn('Syntaxe : cvs [-qQfn] [-d depot] commande [options] [fichiers ...]');
    WriteLn(' init [repertoire]          Creer un depot');
    WriteLn(' add fichier ...            Ajouter des fichiers au suivi');
    WriteLn(' commit [-m message]        Enregistrer les fichiers modifies');
    WriteLn(' status [fichier ...]       Afficher l''etat des fichiers suivis');
    WriteLn(' log [fichier ...]          Afficher l''historique des revisions');
    WriteLn(' diff [fichier ...]         Signaler les fichiers modifies');
    WriteLn(' checkout [fichier ...]     Restaurer les fichiers du depot');
    WriteLn(' update [fichier ...]       Restaurer les fichiers absents');
    WriteLn(' remove fichier ...         Retirer du suivi, sans effacer le fichier');
    WriteLn(' -d REP  Choisir le depot local (defaut .cvs)');
    WriteLn(' -q      Supprimer les messages ordinaires');
    WriteLn(' -n      Ne modifier ni depot ni fichiers de travail');
    WriteLn('Implementation locale Pascal; aucun serveur CVS n''est utilise.');
  End;
End;

Function JoinPath(Const BasePath,FileName:String):String;
Begin
  If(BasePath<>'')and(BasePath[Length(BasePath)]in['\','/'])Then
    JoinPath:=BasePath+FileName
  Else JoinPath:=BasePath+'\'+FileName;
End;

Function IsDirectory(Const PathName:String):Boolean;
Var
  DirectorySearch:SearchRec;
Begin
  FindFirst(PathName,AnyFile,DirectorySearch);
  IsDirectory:=(DosError=0)and((DirectorySearch.Attr and Directory)<>0);
  {$IFDEF FPC}FindClose(DirectorySearch);{$ENDIF}
End;

Function FileExistsTP(Const PathName:String):Boolean;
Var
  FileSearch:SearchRec;
Begin
  FindFirst(PathName,AnyFile,FileSearch);
  FileExistsTP:=(DosError=0)and((FileSearch.Attr and Directory)=0);
  {$IFDEF FPC}FindClose(FileSearch);{$ENDIF}
End;

Procedure EnsureRepository;
Begin
  If IsDirectory(RepoPath)Then Exit;
  {$I-}MkDir(RepoPath);{$I+}
  If(IOResult<>0)and Not IsDirectory(RepoPath)Then
    UsageError('impossible de creer le depot '+RepoPath);
End;

Function EntriesPath:String;
Begin
  EntriesPath:=JoinPath(RepoPath,'Entries');
End;

Function NextPath:String;
Begin
  NextPath:=JoinPath(RepoPath,'Next');
End;

Function HistoryPath:String;
Begin
  HistoryPath:=JoinPath(RepoPath,'History');
End;

Function SnapshotPath(Revision:LongInt):String;
Var
  RevisionText:String;
Begin
  Str(Revision,RevisionText);
  While Length(RevisionText)<8 Do RevisionText:='0'+RevisionText;
  SnapshotPath:=JoinPath(RepoPath,'R'+RevisionText+'.DAT');
End;

Function FindEntry(Const Name:String):Integer;
Var
  Index:Integer;
Begin
  FindEntry:=0;
  For Index:=1 to EntryCount Do
    If Entries[Index].Name=Name Then Begin
      FindEntry:=Index;
      Exit;
    End;
End;

Procedure LoadEntries;
Var
  EntryFile:Text;
  LineText,RevisionText:String;
  SeparatorPosition,ErrorCode:Integer;
Begin
  EntryCount:=0;
  If Not FileExistsTP(EntriesPath)Then Exit;
  Assign(EntryFile,EntriesPath);
  {$I-}Reset(EntryFile);{$I+}
  If IOResult<>0 Then Begin ReportError('impossible de lire Entries'); Exit; End;
  While Not EOF(EntryFile)and(EntryCount<MaxEntries)Do Begin
    ReadLn(EntryFile,LineText);
    SeparatorPosition:=Pos('|',LineText);
    If SeparatorPosition>0 Then Begin
      Inc(EntryCount);
      Entries[EntryCount].Name:=Copy(LineText,1,SeparatorPosition-1);
      RevisionText:=Copy(LineText,SeparatorPosition+1,255);
      Val(RevisionText,Entries[EntryCount].Revision,ErrorCode);
      If ErrorCode<>0 Then Entries[EntryCount].Revision:=0;
    End;
  End;
  Close(EntryFile);
End;

Function ReadNextRevision:LongInt;
Var
  NextFile:Text;
  Value:LongInt;
Begin
  ReadNextRevision:=1;
  If Not FileExistsTP(NextPath)Then Exit;
  Assign(NextFile,NextPath);
  {$I-}Reset(NextFile);{$I+}
  If IOResult<>0 Then Exit;
  ReadLn(NextFile,Value);
  Close(NextFile);
  If Value>0 Then ReadNextRevision:=Value;
End;

Procedure SaveNextRevision(Value:LongInt);
Var
  NextFile:Text;
Begin
  Assign(NextFile,NextPath);
  {$I-}Rewrite(NextFile);{$I+}
  If IOResult<>0 Then Begin ReportError('impossible de mettre a jour Next'); Exit; End;
  WriteLn(NextFile,Value);
  Close(NextFile);
End;

Procedure WriteEntriesFile;
Var
  EntryFile:Text;
  TempName,BackupName:String;
  Index,IOError:Integer;
Begin
  TempName:=EntriesPath+'.tmp';
  BackupName:=EntriesPath+'.bak';
  Assign(EntryFile,TempName);
  {$I-}Rewrite(EntryFile);{$I+}
  If IOResult<>0 Then Begin ReportError('impossible de creer Entries.tmp'); Exit; End;
  For Index:=1 to EntryCount Do
    WriteLn(EntryFile,Entries[Index].Name,'|',Entries[Index].Revision);
  Close(EntryFile);
  If FileExistsTP(EntriesPath)Then Begin
    If FileExistsTP(BackupName)Then Begin
      Assign(EntryFile,BackupName);{$I-}Erase(EntryFile);{$I+}IOError:=IOResult;
    End;
    Assign(EntryFile,EntriesPath);{$I-}Rename(EntryFile,BackupName);{$I+}
    IOError:=IOResult;
    If IOError<>0 Then Begin ReportError('impossible de sauvegarder Entries'); Exit; End;
  End;
  Assign(EntryFile,TempName);{$I-}Rename(EntryFile,EntriesPath);{$I+}
  IOError:=IOResult;
  If IOError<>0 Then Begin
    If FileExistsTP(BackupName)Then Begin
      Assign(EntryFile,BackupName);{$I-}Rename(EntryFile,EntriesPath);{$I+}IOError:=IOResult;
    End;
    ReportError('impossible de remplacer Entries');
    Exit;
  End;
  If FileExistsTP(BackupName)Then Begin
    Assign(EntryFile,BackupName);{$I-}Erase(EntryFile);{$I+}IOError:=IOResult;
  End;
End;

Function FilesEqual(Const FirstName,SecondName:String):Boolean;
Var
  FirstFile,SecondFile:File;
  FirstBuffer,SecondBuffer:Array[0..CopyBufferSize-1]Of Byte;
  FirstCount,SecondCount:Word;
  Index:Integer;
  Different:Boolean;
Begin
  FilesEqual:=False;
  Assign(FirstFile,FirstName);Assign(SecondFile,SecondName);
  FileMode:=0;
  {$I-}Reset(FirstFile,1);{$I+}
  If IOResult<>0 Then Exit;
  {$I-}Reset(SecondFile,1);{$I+}
  If IOResult<>0 Then Begin Close(FirstFile); Exit; End;
  Different:=FileSize(FirstFile)<>FileSize(SecondFile);
  While Not Different Do Begin
    BlockRead(FirstFile,FirstBuffer,SizeOf(FirstBuffer),FirstCount);
    BlockRead(SecondFile,SecondBuffer,SizeOf(SecondBuffer),SecondCount);
    If FirstCount<>SecondCount Then Begin Different:=True; Break; End;
    If FirstCount=0 Then Break;
    For Index:=0 to FirstCount-1 Do
      If FirstBuffer[Index]<>SecondBuffer[Index]Then Different:=True;
  End;
  Close(SecondFile);Close(FirstFile);
  FilesEqual:=Not Different;
End;

Procedure CopyFileBytes(Const SourceName,TargetName:String);
Var
  SourceFile,TargetFile:File;
  Buffer:Array[0..CopyBufferSize-1]Of Byte;
  ReadCount,WriteCount:Word;
Begin
  Assign(SourceFile,SourceName);FileMode:=0;
  {$I-}Reset(SourceFile,1);{$I+}
  If IOResult<>0 Then Begin ReportError('impossible de lire '+SourceName); Exit; End;
  Assign(TargetFile,TargetName);FileMode:=1;
  {$I-}Rewrite(TargetFile,1);{$I+}
  If IOResult<>0 Then Begin Close(SourceFile);ReportError('impossible de creer '+TargetName);Exit;End;
  Repeat
    BlockRead(SourceFile,Buffer,SizeOf(Buffer),ReadCount);
    If ReadCount>0 Then Begin
      BlockWrite(TargetFile,Buffer,ReadCount,WriteCount);
      If WriteCount<>ReadCount Then Begin ReportError('ecriture incomplete');Break;End;
    End;
  Until ReadCount=0;
  Close(TargetFile);Close(SourceFile);
End;

Procedure AddFiles;
Var
  Index,EntryIndex:Integer;
Begin
  EnsureRepository;
  LoadEntries;
  For Index:=1 to ArgumentCount Do Begin
    CurrentFile:=Arguments[Index];
    If Not FileExistsTP(CurrentFile)Then ReportError('fichier introuvable: '+CurrentFile)
    Else If Pos('|',CurrentFile)>0 Then ReportError('le nom contient un separateur reserve |')
    Else Begin
      EntryIndex:=FindEntry(CurrentFile);
      If EntryIndex>0 Then WriteLn(CurrentFile,' deja suivi')
      Else If EntryCount>=MaxEntries Then ReportError('index plein')
      Else Begin
        Inc(EntryCount);
        Entries[EntryCount].Name:=CurrentFile;
        Entries[EntryCount].Revision:=0;
        WriteLn('Ajoute ',CurrentFile);
      End;
    End;
  End;
  WriteEntriesFile;
End;

Procedure AppendHistory(Revision:LongInt; Const FileName,MessageText:String);
Var
  HistoryFile:Text;
Begin
  Assign(HistoryFile,HistoryPath);
  {$I-}Append(HistoryFile);{$I+}
  If IOResult<>0 Then Begin
    {$I-}Rewrite(HistoryFile);{$I+}
    If IOResult<>0 Then Begin ReportError('impossible de creer History'); Exit; End;
  End;
  WriteLn(HistoryFile,Revision,'|',GetEnv('USERNAME'),'|',FileName,'|',MessageText);
  Close(HistoryFile);
End;

Procedure CommitFiles;
Var
  Index,Committed:Integer;
  SnapshotName:String;
Begin
  EnsureRepository;
  LoadEntries;
  RevisionNumber:=ReadNextRevision;
  Committed:=0;
  For Index:=1 to EntryCount Do Begin
    CurrentFile:=Entries[Index].Name;
    If Not FileExistsTP(CurrentFile)Then Begin
      If Entries[Index].Revision>0 Then ReportError('fichier suivi absent: '+CurrentFile);
    End Else If(Entries[Index].Revision=0)or
      Not FilesEqual(CurrentFile,SnapshotPath(Entries[Index].Revision))Then Begin
        SnapshotName:=SnapshotPath(RevisionNumber);
        If ForceMode or Not FileExistsTP(SnapshotName)Then Begin
          CopyFileBytes(CurrentFile,SnapshotName);
          If Not ErrorFound Then Begin
            Entries[Index].Revision:=RevisionNumber;
            AppendHistory(RevisionNumber,CurrentFile,CommitMessage);
            Inc(RevisionNumber);
            Inc(Committed);
          End;
        End Else ReportError('revision deja existante: '+SnapshotName);
      End;
  End;
  If Committed=0 Then Begin
    If Not QuietMode Then WriteLn('Aucune modification a enregistrer');
  End Else Begin
    WriteEntriesFile;
    SaveNextRevision(RevisionNumber);
    If Not QuietMode Then WriteLn(Committed,' fichier(s) valide(s)');
  End;
End;

Procedure StatusFiles;
Var
  Index:Integer;
  Selected:Boolean;
Begin
  LoadEntries;
  For Index:=1 to EntryCount Do Begin
    Selected:=(ArgumentCount=0)or(FindArgument(Entries[Index].Name)>0);
    If Selected Then Begin
      CurrentFile:=Entries[Index].Name;
      If Entries[Index].Revision=0 Then WriteLn('? ',CurrentFile)
      Else If Not FileExistsTP(CurrentFile)Then WriteLn('! ',CurrentFile,' (missing)')
      Else If FilesEqual(CurrentFile,SnapshotPath(Entries[Index].Revision))Then
        WriteLn('= ',CurrentFile)
      Else WriteLn('M ',CurrentFile);
    End;
  End;
End;

Procedure RestoreFiles(OnlyMissing:Boolean);
Var
  Index:Integer;
Begin
  LoadEntries;
  For Index:=1 to EntryCount Do Begin
    If((ArgumentCount=0)or(FindArgument(Entries[Index].Name)>0))and
      (Entries[Index].Revision>0)Then Begin
      CurrentFile:=Entries[Index].Name;
      If Not(OnlyMissing and FileExistsTP(CurrentFile))Then Begin
        If FileExistsTP(CurrentFile)and Not ForceMode and
          Not FilesEqual(CurrentFile,SnapshotPath(Entries[Index].Revision))Then
          ReportError('fichier modifie, refus de remplacer: '+CurrentFile)
        Else Begin
          CopyFileBytes(SnapshotPath(Entries[Index].Revision),CurrentFile);
          If Not ErrorFound Then WriteLn('Restaure ',CurrentFile);
        End;
      End;
    End;
  End;
End;

Procedure RemoveFiles;
Var
  Index,EntryIndex,ShiftIndex:Integer;
Begin
  LoadEntries;
  For Index:=1 to ArgumentCount Do Begin
    EntryIndex:=FindEntry(Arguments[Index]);
    If EntryIndex=0 Then WriteLn('Non suivi: ',Arguments[Index])
    Else Begin
      For ShiftIndex:=EntryIndex to EntryCount-1 Do Entries[ShiftIndex]:=Entries[ShiftIndex+1];
      Dec(EntryCount);
      WriteLn('Retire du suivi: ',Arguments[Index]);
    End;
  End;
  WriteEntriesFile;
End;

Procedure ShowLog;
Var
  HistoryFile:Text;
  LineText:String;
Begin
  If Not FileExistsTP(HistoryPath)Then Begin WriteLn('Aucun historique');Exit;End;
  Assign(HistoryFile,HistoryPath);
  {$I-}Reset(HistoryFile);{$I+}
  If IOResult<>0 Then Begin ReportError('impossible de lire History');Exit;End;
  While Not EOF(HistoryFile)Do Begin ReadLn(HistoryFile,LineText);WriteLn(LineText);End;
  Close(HistoryFile);
End;

Procedure ShowDiff;
Var
  Index:Integer;
Begin
  LoadEntries;
  For Index:=1 to EntryCount Do Begin
    If(ArgumentCount=0)or(FindArgument(Entries[Index].Name)>0)Then Begin
      CurrentFile:=Entries[Index].Name;
      If Entries[Index].Revision=0 Then WriteLn('Ajout: ',CurrentFile)
      Else If Not FileExistsTP(CurrentFile)Then WriteLn('Supprime localement: ',CurrentFile)
      Else If Not FilesEqual(CurrentFile,SnapshotPath(Entries[Index].Revision))Then
        WriteLn('Modifie: ',CurrentFile)
      Else If Not QuietMode Then WriteLn('Identique: ',CurrentFile);
    End;
  End;
End;

Procedure InitializeRepository;
Var
  NextFile:Text;
Begin
  If IsDirectory(RepoPath)Then Begin
    If FileExistsTP(EntriesPath)Then UsageError('depot deja initialise');
  End Else Begin
    {$I-}MkDir(RepoPath);{$I+}
    If(IOResult<>0)and Not IsDirectory(RepoPath)Then UsageError('impossible de creer '+RepoPath);
  End;
  Assign(NextFile,NextPath);
  {$I-}Rewrite(NextFile);{$I+}
  If IOResult<>0Then UsageError('impossible de creer Next');
  WriteLn(NextFile,1);
  Close(NextFile);
  Assign(NextFile,EntriesPath);
  {$I-}Rewrite(NextFile);{$I+}
  If IOResult<>0Then UsageError('impossible de creer Entries');
  Close(NextFile);
  WriteLn('Depot initialise dans ',RepoPath);
End;

Procedure ReadCommitMessage;
Var
  Index:Integer;
Begin
  CommitMessage:='';
  Index:=1;
  While Index<=ArgumentCount Do Begin
    If Arguments[Index]='-m'Then Begin
      Inc(Index);
      If Index>ArgumentCount Then UsageError('-m attend un message');
      CommitMessage:=Arguments[Index];
    End Else If Copy(Arguments[Index],1,2)='-m'Then
      CommitMessage:=Copy(Arguments[Index],3,255);
    Inc(Index);
  End;
End;

Function FindArgument(Const Name:String):Integer;
Var
  Index:Integer;
Begin
  FindArgument:=0;
  For Index:=1 to ArgumentCount Do
    If Arguments[Index]=Name Then Begin FindArgument:=Index;Exit;End;
End;

Procedure CollectArguments(StartIndex:Integer);
Begin
  ArgumentCount:=0;
  While StartIndex<=ParamCount Do Begin
    If ArgumentCount>=MaxArguments Then UsageError('trop d''arguments');
    Inc(ArgumentCount);
    Arguments[ArgumentCount]:=ParamStr(StartIndex);
    Inc(StartIndex);
  End;
End;

Procedure ExecuteCommand;
Begin
  If CommandName='init'Then InitializeRepository Else
  If CommandName='add'Then AddFiles Else
  If CommandName='commit'Then Begin ReadCommitMessage;CommitFiles;End Else
  If CommandName='status'Then StatusFiles Else
  If CommandName='log'Then ShowLog Else
  If CommandName='diff'Then ShowDiff Else
  If CommandName='checkout'Then RestoreFiles(False) Else
  If CommandName='update'Then RestoreFiles(True) Else
  If CommandName='remove'Then RemoveFiles Else
  UsageError('commande inconnue: '+CommandName);
End;

BEGIN
  RepoPath:='.cvs';
  QuietMode:=False;ForceMode:=False;DryRun:=False;ErrorFound:=False;
  CommandName:='';ArgumentCount:=0;ArgumentIndex:=1;
  While ArgumentIndex<=ParamCount Do Begin
    Argument:=ParamStr(ArgumentIndex);
    If(Argument='--help')or(Argument='-h')or(Argument='/?')Then Begin PrintHelp;Halt(0);End
    Else If(Argument='--version')or(Argument='-V')Then Begin WriteLn('cvs (LINUX-0) 1.0');Halt(0);End
    Else If(Argument='-d')Then Begin
      Inc(ArgumentIndex);
      If ArgumentIndex>ParamCount Then UsageError('-d attend un depot');
      RepoPath:=ParamStr(ArgumentIndex);
    End Else If(Argument='-q')or(Argument='-Q')Then QuietMode:=True
    Else If Argument='-f'Then ForceMode:=True
    Else If Argument='-n'Then DryRun:=True
    Else If(Length(Argument)>2)and(Copy(Argument,1,2)='-d')Then RepoPath:=Copy(Argument,3,255)
    Else If(Length(Argument)>1)and(Argument[1]='-')and(CommandName='')Then
      OptionError('option inconnue: '+Argument)
    Else If CommandName=''Then CommandName:=Argument
    Else Begin
      If ArgumentCount>=MaxArguments Then OptionError('trop d''arguments');
      Inc(ArgumentCount);Arguments[ArgumentCount]:=Argument;
    End;
    Inc(ArgumentIndex);
  End;
  If CommandName=''Then Begin PrintHelp;Halt(2);End;
  If CommandName='init'Then Begin
    If ArgumentCount>0 Then RepoPath:=Arguments[1];
    If DryRun Then WriteLn('Simulation: init ',RepoPath)Else InitializeRepository;
    Halt(0);
  End;
  If DryRun Then Begin WriteLn('Simulation: ',CommandName);Halt(0);End;
  EnsureRepository;
  LoadEntries;
  ExecuteCommand;
  If ErrorFound Then Halt(1);
END.